--[[
    File: utilities/io_utils.lua
    Description: File I/O and path utilities for MiniAudioAddon.
    Overall Release Version: 1.0.2
    File Version: 1.0.0
]]

local IOUtils = {}

local Mods = rawget(_G, "Mods")
local ascii_proxy_cache = {}
local Shell_ref = nil
local Utils_ref = nil
local MEDIA_DURATION_CACHE = {}

local function sanitize_ps_single(value)
    if Utils_ref and Utils_ref.sanitize_for_ps_single then
        return Utils_ref.sanitize_for_ps_single(value)
    end
    return tostring(value or ""):gsub("'", "''")
end

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

local function copy_using_io_path(source_path, destination)
    local io_api = (Mods and Mods.lua and Mods.lua.io) or io
    if not io_api or type(io_api.open) ~= "function" then
        return false
    end

    local read_ok, reader = pcall(io_api.open, source_path, "rb")
    if not read_ok or not reader then
        return false
    end

    local data = reader:read("*a")
    reader:close()
    if not data then
        return false
    end

    local write_ok, writer = pcall(io_api.open, destination, "wb")
    if not write_ok or not writer then
        return false
    end
    writer:write(data)
    writer:close()
    return true
end

local function enumerate_dir_short_names(directory)
    if not directory or directory == "" then
        return nil
    end

    local popen_factory = Utils_ref and Utils_ref.locate_popen and Utils_ref.locate_popen()
    if not popen_factory then
        if io and io.popen then
            popen_factory = function(cmd) return io.popen(cmd, "r") end
        else
            return nil
        end
    end

    local command = string.format('cmd /S /C "dir /a-d /x \\"%s\\""', directory)
    local pipe = popen_factory(command)
    return pipe
end

local function short_path_for(path)
    local directory = IOUtils.directory_of(path)
    local filename = path and path:match("([^/\\]+)$")
    if not directory or not filename then
        return nil
    end

    local pipe = enumerate_dir_short_names(directory)
    if not pipe then
        return nil
    end

    local request_name = filename and filename:lower() or nil
    for line in pipe:lines() do
        local short, long = line:match("^[^%s]+%s+[^%s]+%s+[^%s]+%s+([^%s]*)%s+(.+)$")
        if short and long then
            long = long:gsub("^%s+", "")
            if long == filename and short ~= "" then
                pipe:close()
                return IOUtils.ensure_trailing_separator(directory) .. short
            end
            if request_name and long:lower() == request_name and short ~= "" then
                pipe:close()
                return IOUtils.ensure_trailing_separator(directory) .. short
            end
        end
    end
    pipe:close()
    return nil
end

function IOUtils.copy_file(source, destination)
    if not source or not destination then
        return false
    end

    if copy_using_io_path(source, destination) then
        return true
    end

    local short_source = short_path_for(source)
    if short_source and short_source ~= source and copy_using_io_path(short_source, destination) then
        return true
    end

    if Shell_ref and Shell_ref.run_command then
        local function sanitize_ps(value)
            if Utils_ref and Utils_ref.sanitize_for_ps_single then
                return Utils_ref.sanitize_for_ps_single(value)
            end
            value = tostring(value or ""):gsub("'", "''")
            return value
        end

        local source_arg = short_source or source
        local command = string.format(
            [[powershell -NoLogo -NoProfile -Command "& { Copy-Item -LiteralPath '%s' -Destination '%s' -Force }"]],
            sanitize_ps(source_arg),
            sanitize_ps(destination)
        )

        if Shell_ref.run_command(command, "copy_file_proxy", { prefer_local = true }) then
            return true
        end
    end

    if mod_ref and mod_ref.error then
        mod_ref:error("[MiniAudioAddon] Failed to copy %s -> %s", tostring(source), tostring(destination))
    end

    return false
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
    Shell_ref = dependencies.Shell
    Utils_ref = dependencies.Utils
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
local function resolve_existing_path(candidate)
    if not candidate or candidate == "" then
        return nil
    end
    local path = IOUtils.sanitize_path(candidate)
    if not path then
        return nil
    end
    if IOUtils.file_exists(path) then
        return path
    end
    if IOUtils.is_absolute_path(path) then
        local short = short_path_for(path)
        if short and IOUtils.file_exists(short) then
            return short
        end
    end
    return nil
end

function IOUtils.prefer_existing_path(candidates)
    for _, candidate in ipairs(candidates) do
        local resolved = resolve_existing_path(candidate)
        if resolved then
            return resolved
        end
    end
    return nil
end

function IOUtils.resolve_existing_path(path)
    return resolve_existing_path(path)
end

function IOUtils.resolve_short_path(path)
    return short_path_for(path)
end

local function fetch_media_duration(path)
    local popen_factory = Utils_ref and Utils_ref.locate_popen and Utils_ref.locate_popen()
    if not popen_factory then
        return nil
    end
    local directory = IOUtils.directory_of(path)
    local filename = path and path:match("([^/\\]+)$")
    if not directory or not filename then
        return nil
    end

    local command = string.format(
        [[powershell -NoLogo -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; $folder='%s'; $file='%s'; $shell = New-Object -ComObject Shell.Application; $dir = $shell.Namespace($folder); if ($dir -eq $null) { return }; $item = $dir.ParseName($file); if ($item -eq $null) { return }; $ticks = $item.ExtendedProperty('System.Media.Duration'); if ($ticks) { $seconds = [math]::Round($ticks / 10000000, 3); Write-Output $seconds }"]],
        sanitize_ps_single(directory),
        sanitize_ps_single(filename)
    )

    local pipe = popen_factory(command)
    if not pipe then
        return nil
    end
    local output = pipe:read("*a")
    pipe:close()
    if not output then
        return nil
    end
    local trimmed = output:gsub("^%s+", ""):gsub("%s+$", "")
    local duration = tonumber(trimmed)
    return duration
end

function IOUtils.get_media_duration(path)
    if not path then
        return nil
    end
    local cached = MEDIA_DURATION_CACHE[path]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local duration = fetch_media_duration(path)
    if duration and duration > 0 then
        MEDIA_DURATION_CACHE[path] = duration
        return duration
    end

    MEDIA_DURATION_CACHE[path] = false
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
        return resolve_existing_path(sanitized)
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

local function needs_ascii_proxy(path)
    return path and path:find("[\128-\255]")
end

local function sanitize_filename(name)
    if not name or name == "" then
        return "track"
    end
    local sanitized = name:gsub("[^%w%._%-]", "_")
    if sanitized == "" then
        sanitized = "track"
    end
    return sanitized
end

local function ascii_proxy_directory()
    if ascii_proxy_cache.__dir then
        return ascii_proxy_cache.__dir
    end
    local base = IOUtils.get_mod_filesystem_path()
    if not base then
        return nil
    end
    local dir = IOUtils.ensure_trailing_separator(base) .. "Audio"
    ascii_proxy_cache.__dir = dir
    return dir
end

local function simple_hash(str)
    local hash = 5381
    for i = 1, #str do
        local byte = string.byte(str, i)
        hash = (hash * 33 + (byte or 0)) % 0x100000000
    end
    return hash
end

function IOUtils.ensure_ascii_proxy(path)
    if not needs_ascii_proxy(path) then
        return path
    end

    if ascii_proxy_cache[path] and IOUtils.file_exists(ascii_proxy_cache[path]) then
        return ascii_proxy_cache[path]
    end

    local proxy_dir = ascii_proxy_directory()
    if not proxy_dir then
        return path
    end

    local filename = path:match("([^/\\]+)$") or "track"
    local ext = filename:match("(%.%w+)$") or ""
    local basename = filename:sub(1, #filename - #ext)
    if basename == "" then
        basename = filename
        ext = ""
    end
    basename = sanitize_filename(basename)
    local hash = simple_hash(path)
    local proxy_name = string.format("proxy_%s_%08x%s", basename, hash, ext)
    local proxy_path = IOUtils.ensure_trailing_separator(proxy_dir) .. proxy_name

    if not IOUtils.file_exists(proxy_path) then
        local copied = IOUtils.copy_file(path, proxy_path)
        if not copied then
            return path
        end
    end

    ascii_proxy_cache[path] = proxy_path
    return proxy_path
end

return IOUtils
