--[[
    File: utilities/logging.lua
    Description: API logging utilities for MiniAudioAddon
    Overall Release Version: 1.0.2
    File Version: 1.0.0
]]

local Logging = {}

-- Dependencies (injected via init)
local mod = nil
local IOUtils = nil
local DaemonPaths = nil
local DaemonState = nil
local unpack_args = table.unpack or unpack

-- Internal state
local API_LOG_PATH = nil
local api_log_guard = false

--[[
    Initialize Logging module with dependencies
    
    Args:
        dependencies: Table with {mod, IOUtils, DaemonPaths, DaemonState}
]]
function Logging.init(dependencies)
    mod = dependencies.mod
    IOUtils = dependencies.IOUtils
    DaemonPaths = dependencies.DaemonPaths
    DaemonState = dependencies.DaemonState
end

--[[
    Check if API logging is enabled
    
    Returns: Boolean true if API logging is enabled in mod settings
]]
function Logging.api_log_enabled()
    if not mod then
        return false
    end
    local value = mod:get("miniaudioaddon_api_log")
    return value and true or false
end

--[[
    Get or determine API log file path
    
    Searches for appropriate location to write API log file.
    Caches path once determined.
    
    Returns: String absolute path to API log file or nil
]]
function Logging.ensure_api_log_path()
    if API_LOG_PATH then
        return API_LOG_PATH
    end

    -- Try pipe directory first (if daemon paths are resolved)
    if DaemonPaths and DaemonPaths.ensure and DaemonPaths.ensure() and DaemonState and DaemonState.get_pipe_directory then
        local pipe_dir = DaemonState.get_pipe_directory()
        if pipe_dir and pipe_dir ~= "" then
            API_LOG_PATH = IOUtils.add_trailing_slash(pipe_dir) .. "miniaudio_api_log.txt"
            return API_LOG_PATH
        end
    end

    -- Try mod filesystem path
    if IOUtils and IOUtils.get_mod_filesystem_path then
        local base = IOUtils.get_mod_filesystem_path()
        if base then
            API_LOG_PATH = IOUtils.add_trailing_slash(base) .. "miniaudio_api_log.txt"
            return API_LOG_PATH
        end
    end

    -- Fallback to DLS path
    local DLS = rawget(_G, "get_mod") and rawget(_G, "get_mod")("DarktideLocalServer")
    if DLS and DLS.get_mod_path and mod then
        local ok, root = pcall(DLS.get_mod_path, mod, nil, false)
        if ok and root and IOUtils then
            API_LOG_PATH = IOUtils.add_trailing_slash(root) .. "miniaudio_api_log.txt"
            return API_LOG_PATH
        end
    end

    return nil
end

--[[
    Write timestamped message to API log file
    
    Internal function for writing to log. Protected against re-entry.
    
    Args:
        fmt: String format string
        ...: Format arguments
]]
function Logging.write_api_log(fmt, ...)
    if not Logging.api_log_enabled() or api_log_guard then
        return
    end

    api_log_guard = true
    local path = Logging.ensure_api_log_path()
    if not path then
        api_log_guard = false
        return
    end

    local ok, line = pcall(string.format, fmt, ...)
    if not ok then
        line = fmt or ""
    end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    if IOUtils and IOUtils.append_text_file then
        IOUtils.append_text_file(path, string.format("[%s] %s\n", timestamp or "?", line))
    end
    api_log_guard = false
end

--[[
    Announce API log path to user
    
    Echoes the location where API logs are being written.
    Only announces if API logging is enabled.
]]
function Logging.announce_api_log_path()
    if not mod or not mod:get("miniaudioaddon_api_log") then
        return
    end
    local path = Logging.ensure_api_log_path()
    if path then
        mod:echo("[MiniAudioAddon] API log writing to: %s", path)
    else
        mod:echo("[MiniAudioAddon] API log enabled, but no log path is available.")
    end
end

--[[
    Sanitize API label for logging
    
    Removes problematic characters from source labels.
    
    Args:
        label: String or any value to sanitize
    Returns: Sanitized string label
]]
function Logging.sanitize_api_label(label)
    label = tostring(label or "external")
    label = label:gsub("%s+", " "):gsub("[%[%]\r\n]", "?")
    return label
end

--[[
    Public API log function (exposed to external mods)
    
    Flexible logging function that accepts either:
    - (source, format, ...) - source label, format string, args
    - (mod_table, format, ...) - mod table with :get_name(), format, args
    - (format, ...) - just format string and args (source = "external")
    
    Args:
        arg1: Source string, mod table, or format string
        arg2: Format string or first format arg
        ...: Format arguments
]]
function Logging.api_log(arg1, arg2, ...)
    if not Logging.api_log_enabled() then
        return
    end

    local source = arg1
    local fmt = arg2
    local args = { ... }

    if type(source) ~= "string" then
        -- Colon usage or source omitted
        local maybe_self = source
        local resolved = nil
        if type(maybe_self) == "table" and maybe_self.get_name then
            local ok, name = pcall(maybe_self.get_name, maybe_self)
            if ok then
                resolved = name
            end
            fmt = arg2
            args = { ... }
        else
            fmt = arg1
            args = { arg2, ... }
        end
        source = resolved
    end

    if not fmt then
        return
    end

    local ok, line = pcall(string.format, fmt, unpack_args(args))
    if not ok then
        line = fmt
    end

    Logging.write_api_log("EXT[%s] %s", Logging.sanitize_api_label(source or "external"), line)
end

--[[
    Reset API log path cache
    
    Forces recalculation of log path on next write.
    Useful after daemon restarts or path changes.
]]
function Logging.reset_cache()
    API_LOG_PATH = nil
end

return Logging
