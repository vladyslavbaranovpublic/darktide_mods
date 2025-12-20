--[[
    File: utilities/io_utils.lua
    Description: File I/O and path utilities for MiniAudioAddon.
    Overall Release Version: 1.0.2
    File Version: 1.0.0
]]

local IOUtils = {}

local Mods = rawget(_G, "Mods")

function IOUtils.append_text_file(path, contents)
    if not path or not contents then
        return false
    end

    local io_variants = {}
    local mods_io = Mods and Mods.lua and Mods.lua.io
    if mods_io then
        io_variants[#io_variants + 1] = Mods.lua.io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        io_variants[#io_variants + 1] = global_io
    end

    for _, io_api in ipairs(io_variants) do
        if type(io_api) == "table" and type(io_api.open) == "function" then
            local ok, handle_or_err = pcall(io_api.open, path, "ab")
            if ok and handle_or_err then
                local file = handle_or_err
                local wrote = pcall(function()
                    file:write(contents)
                    if file.flush then
                        file:flush()
                    end
                end)
                pcall(function()
                    if file.close then
                        file:close()
                    end
                end)
                if wrote then
                    return true
                end
            end
        end
    end

    return false
end

--[[ 
    Delete a file safely
    
    Args:
        path: Absolute path to delete
    Returns: true if deletion succeeded
]]
function IOUtils.delete_file(path)
    if not path or path == "" then
        return false
    end

    local ok, result = pcall(os.remove, path)
    if not ok then
        return false
    end
    return result ~= nil
end

function IOUtils.add_trailing_slash(path)
    if not path or path == "" then
        return path
    end
    local last = path:sub(-1)
    if last == "\\" or last == "/" then
        return path
    end
    return path .. "\\"
end

-- ============================================================================
-- PATH UTILITIES (Consolidated from MiniAudioAddon.lua)
-- ============================================================================

-- Cached paths
local MOD_BASE_PATH = nil
local MOD_FILESYSTEM_PATH = nil
local MOD_AUDIO_FOLDER_CACHE = {}

-- Dependencies (injected via init)
local mod_ref = nil
local DLS_ref = nil

--[[
    Initialize IoUtils with required dependencies
    
    Args:
        dependencies: Table with {mod, DLS}
]]
function IOUtils.init(dependencies)
    mod_ref = dependencies.mod
    DLS_ref = dependencies.DLS
end

--[[
    Get mod base path (logical mod path)
    
    Returns the virtual mod path in the format "mods/ModName/".
    This is NOT a filesystem path.
    
    Returns: String mod base path or nil
]]
function IOUtils.get_mod_base_path()
    if MOD_BASE_PATH then
        return MOD_BASE_PATH
    end

    -- Construct the mod path from the mod name
    local mod_name = mod_ref and mod_ref:get_name()
    if not mod_name then
        return nil
    end

    local path = string.format("mods/%s/", mod_name)
    MOD_BASE_PATH = path
    return MOD_BASE_PATH
end

--[[
    Check if file exists on disk
    
    Tries multiple IO APIs (Mods.lua.io, global io) to check file existence.
    
    Args:
        path: String absolute path to check
    Returns: Boolean true if file exists
]]
function IOUtils.file_exists(path)
    if not path or path == "" then
        return false
    end

    local variants = {}
    local mods_io = Mods and Mods.lua and Mods.lua.io
    if mods_io then
        variants[#variants + 1] = mods_io
    end

    local global_io = rawget(_G, "io")
    if global_io then
        variants[#variants + 1] = global_io
    end

    for _, io_api in ipairs(variants) do
        if type(io_api) == "table" and type(io_api.open) == "function" then
            local ok, file_or_err = pcall(io_api.open, path, "rb")
            if ok and file_or_err then
                local file = file_or_err
                pcall(function()
                    if file.close then
                        file:close()
                    end
                end)
                return true
            end
        end
    end

    return false
end

--[[
    Return first existing path from candidate list
    
    Args:
        candidates: Array of path strings to check
    Returns: First existing path or nil
]]
function IOUtils.prefer_existing_path(candidates)
    for _, candidate in ipairs(candidates) do
        if IOUtils.file_exists(candidate) then
            return candidate
        end
    end
    return nil
end

--[[
    Return first existing path or last non-empty candidate as fallback
    
    Args:
        candidates: Array of path strings to check
    Returns: First existing path or last non-empty candidate
]]
function IOUtils.prefer_path_with_fallback(candidates)
    local fallback = nil

    for _, candidate in ipairs(candidates) do
        if candidate and candidate ~= "" then
            fallback = fallback or candidate
            if IOUtils.file_exists(candidate) then
                return candidate
            end
        end
    end

    return fallback
end

--[[
    Sanitize path string (trim whitespace, remove quotes)
    
    Args:
        path: String path to sanitize
    Returns: Cleaned path string or nil
]]
function IOUtils.sanitize_path(path)
    if not path then
        return nil
    end
    path = tostring(path)
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    if #path == 0 then
        return nil
    end
    if path:sub(1, 1) == '"' then
        path = path:sub(2)
    end
    if path:sub(-1) == '"' then
        path = path:sub(1, -2)
    end
    if path:sub(1, 1) == "'" then
        path = path:sub(2)
    end
    if path:sub(-1) == "'" then
        path = path:sub(1, -2)
    end
    return path
end

--[[
    Extract directory from path (including trailing separator)
    
    Args:
        path: String file path
    Returns: Directory path with trailing separator or nil
]]
function IOUtils.directory_of(path)
    if not path then
        return nil
    end

    local idx = path:match(".*()[/\\]")
    if not idx then
        return nil
    end

    return path:sub(1, idx)
end

--[[
    Remove trailing separator from directory path
    
    Args:
        path: String directory path
    Returns: Normalized path without trailing separator
]]
function IOUtils.normalize_directory(path)
    if not path then
        return nil
    end

    if path:sub(-1) == "\\" or path:sub(-1) == "/" then
        return path:sub(1, -2)
    end

    return path
end

--[[
    Wrap daemon command to change directory before execution
    
    Changes to daemon executable's directory before running command.
    Required for daemon to find DLLs in same directory.
    
    Args:
        command: String shell command
        daemon_exe_path: String path to daemon executable
    Returns: Wrapped command with cd prefix
]]
function IOUtils.wrap_daemon_command(command, daemon_exe_path)
    if not command or command == "" then
        return command
    end

    local exe_dir = daemon_exe_path and IOUtils.normalize_directory(IOUtils.directory_of(daemon_exe_path))
    if not exe_dir or exe_dir == "" then
        return command
    end

    local is_windows = package and package.config and package.config:sub(1, 1) == "\\"
    if is_windows then
        return string.format('cd /d "%s" && %s', exe_dir, command)
    end

    return string.format('cd "%s" && %s', exe_dir, command)
end

--[[
    Get parent directory of path
    
    Args:
        path: String path (file or directory)
    Returns: Parent directory path or nil
]]
function IOUtils.parent_directory(path)
    if not path then
        return nil
    end

    local trimmed = path
    if trimmed:sub(-1) == "\\" or trimmed:sub(-1) == "/" then
        trimmed = trimmed:sub(1, -2)
    end

    return IOUtils.directory_of(trimmed)
end

--[[
    Ensure path has trailing separator (alias for add_trailing_slash)
    
    Args:
        path: String directory path
    Returns: Path with trailing backslash
]]
function IOUtils.ensure_trailing_separator(path)
    return IOUtils.add_trailing_slash(path)
end

--[[
    Join base path with fragment
    
    Normalizes separators to backslash and ensures proper joining.
    
    Args:
        base: String base directory path
        fragment: String relative path fragment
    Returns: Joined path or nil
]]
function IOUtils.join_path(base, fragment)
    if not base or not fragment or fragment == "" then
        return nil
    end

    fragment = fragment:gsub("^[/\\]+", "")
    fragment = fragment:gsub("/", "\\")
    return IOUtils.ensure_trailing_separator(base) .. fragment
end

--[[
    Get mod filesystem path (physical disk path)
    
    Returns the absolute filesystem path where mod files are located.
    Uses DLS to locate MiniAudioAddon.mod file.
    
    Returns: String absolute filesystem path or nil
]]
function IOUtils.get_mod_filesystem_path()
    if MOD_FILESYSTEM_PATH then
        return MOD_FILESYSTEM_PATH
    end

    if not DLS_ref or not DLS_ref.get_mod_path then
        return nil
    end

    local marker = DLS_ref.get_mod_path(mod_ref, "MiniAudioAddon.mod", false)
        or DLS_ref.get_mod_path(mod_ref, "MiniAudioAddon.mod", true)

    if not marker then
        return nil
    end

    marker = IOUtils.sanitize_path(marker)
    local directory = IOUtils.directory_of(marker)
    if not directory then
        return nil
    end

    MOD_FILESYSTEM_PATH = directory
    return MOD_FILESYSTEM_PATH
end

--[[
    Check if path is absolute
    
    Args:
        path: String path to check
    Returns: Boolean true if absolute path (drive letter or UNC)
]]
function IOUtils.is_absolute_path(path)
    if not path then
        return false
    end
    return path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
end

--[[
    Expand track path to absolute filesystem path
    
    Searches multiple locations:
    1. If absolute, checks if exists
    2. Relative to MiniAudioAddon folder
    3. Relative to MiniAudioAddon/Audio folder
    4. Relative to sibling mod folders
    
    Args:
        path: String track path (absolute or relative)
    Returns: Absolute path to existing file or nil
]]
function IOUtils.expand_track_path(path)
    local sanitized = IOUtils.sanitize_path(path)
    if not sanitized or sanitized == "" then
        return nil
    end

    if IOUtils.is_absolute_path(sanitized) then
        return IOUtils.file_exists(sanitized) and sanitized or nil
    end

    local candidates = {}
    candidates[#candidates + 1] = sanitized

    local normalized = sanitized:gsub("/", "\\")
    if normalized ~= sanitized then
        candidates[#candidates + 1] = normalized
    end

    local base = IOUtils.get_mod_filesystem_path()
    if base then
        -- Search in MiniAudioAddon folder
        candidates[#candidates + 1] = IOUtils.join_path(base, normalized)
        candidates[#candidates + 1] = IOUtils.join_path(base, sanitized)
        candidates[#candidates + 1] = IOUtils.join_path(base, "Audio\\" .. normalized)
        candidates[#candidates + 1] = IOUtils.join_path(base, "audio\\" .. normalized)
        
        -- Also search in sibling mod folders (go up to mods/ then into specified mod)
        local mods_base = IOUtils.parent_directory(base)
        if mods_base then
            candidates[#candidates + 1] = IOUtils.join_path(mods_base, normalized)
            candidates[#candidates + 1] = IOUtils.join_path(mods_base, sanitized)
        end
    end

    return IOUtils.prefer_existing_path(candidates)
end

--[[
    Resolve a mod's audio folder using IOUtils.expand_track_path.

    Args:
        mod_instance: DMF mod table
        subpath: optional subfolder (default "audio")
    Returns: absolute folder path string (cached per mod/subpath)
]]
local function _mod_name(mod_instance)
    if not mod_instance then
        return "UnknownMod"
    end
    if type(mod_instance.get_name) == "function" then
        local ok, name = pcall(mod_instance.get_name, mod_instance)
        if ok and name and name ~= "" then
            return name
        end
    end
    return "UnknownMod"
end

local function _normalize_folder(path)
    local sanitized = IOUtils.sanitize_path(path)
    if not sanitized then
        return nil
    end
    sanitized = sanitized:gsub("/", "\\")
    return sanitized
end

local function _join_folder(base, fragment)
    if not base or base == "" then
        return nil
    end
    base = base:gsub("/", "\\")
    fragment = fragment or ""
    fragment = fragment:gsub("^[/\\]+", ""):gsub("/", "\\")
    if fragment == "" then
        return _normalize_folder(base)
    end
    if base:sub(-1) == "\\" then
        return _normalize_folder(base .. fragment)
    end
    return _normalize_folder(base .. "\\" .. fragment)
end

local function _root_from_script(mod_instance)
    if not mod_instance or type(mod_instance.script_mod_path) ~= "function" then
        return nil
    end
    local ok, script_path = pcall(mod_instance.script_mod_path, mod_instance)
    if not ok or not script_path or script_path == "" then
        return nil
    end
    script_path = _normalize_folder(script_path)
    if not script_path then
        return nil
    end
    local trimmed = script_path:gsub("[/\\]scripts[/\\].-$", "")
    if trimmed and trimmed ~= "" then
        return trimmed
    end
    return nil
end

local function _root_from_fields(mod_instance)
    if not mod_instance then
        return nil
    end
    local candidates = { "_path", "path" }
    for _, field in ipairs(candidates) do
        local value = mod_instance[field]
        if type(value) == "string" and value ~= "" then
            local normalized = _normalize_folder(value)
            if normalized then
                return normalized
            end
        end
    end

    if type(mod_instance.get_mod_path) == "function" then
        local ok, value = pcall(mod_instance.get_mod_path, mod_instance)
        if ok and value and value ~= "" then
            local normalized = _normalize_folder(value)
            if normalized then
                return normalized
            end
        end
    end

    return nil
end

local function _root_from_mods_table(mod_name)
    if not Mods or not Mods.mods or not mod_name then
        return nil
    end
    local mod_entry = Mods.mods[mod_name]
    if not mod_entry then
        return nil
    end
    local candidates = { mod_entry.path, mod_entry._path }
    for _, value in ipairs(candidates) do
        if type(value) == "string" and value ~= "" then
            local normalized = _normalize_folder(value)
            if normalized then
                return normalized
            end
        end
    end
    return nil
end

local function _try_dls_path(mod_instance, target_subpath)
    if not DLS_ref or not DLS_ref.get_mod_path then
        return nil
    end
    local ok, resolved = pcall(DLS_ref.get_mod_path, mod_instance, target_subpath, false)
    if ok and resolved then
        return _normalize_folder(resolved)
    end
    return nil
end

function IOUtils.resolve_mod_audio_folder(mod_instance, subpath)
    if not mod_instance then
        return nil
    end

    local mod_name = _mod_name(mod_instance)
    local target_subpath = (subpath and subpath ~= "" and subpath) or "audio"
    target_subpath = target_subpath:gsub("^[/\\]+", ""):gsub("/", "\\")

    local cache_key = string.format("%s::%s", mod_name, target_subpath)
    local cached = MOD_AUDIO_FOLDER_CACHE[cache_key]
    if cached then
        return cached
    end

    local folder = _try_dls_path(mod_instance, target_subpath)
    if not folder then
        local root = _root_from_script(mod_instance)
            or _root_from_fields(mod_instance)
            or _root_from_mods_table(mod_name)
        if root then
            folder = _join_folder(root, target_subpath)
        end
    end

    if not folder and IOUtils.expand_track_path then
        local relative = string.format("%s/%s", mod_name, target_subpath)
        local expanded = IOUtils.expand_track_path(relative)
        if expanded and IOUtils.directory_of then
            local dir = IOUtils.directory_of(expanded)
            folder = _normalize_folder(dir or expanded)
        end
    end

    if not folder then
        folder = _normalize_folder(string.format("mods\\%s\\%s", mod_name, target_subpath))
    end

    MOD_AUDIO_FOLDER_CACHE[cache_key] = folder
    return folder
end

--[[
    Reset cached paths (for testing or hot reload)
]]
function IOUtils.reset_cache()
    MOD_BASE_PATH = nil
    MOD_FILESYSTEM_PATH = nil
    MOD_AUDIO_FOLDER_CACHE = {}
end

return IOUtils
