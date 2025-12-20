--[[
    File: core/daemon_paths.lua
    Description: Daemon path resolution for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local DaemonPaths = {}

-- Dependencies
local mod = nil
local IOUtils = nil
local DaemonState = nil
local Utils = nil
local debug_enabled = nil
local PayloadBuilder = nil

function DaemonPaths.init(dependencies)
    mod = dependencies.mod
    IOUtils = dependencies.IOUtils
    DaemonState = dependencies.DaemonState
    Utils = dependencies.Utils
    debug_enabled = dependencies.debug_enabled
    PayloadBuilder = dependencies.PayloadBuilder
end

-- ============================================================================
-- HELPER FUNCTIONS (use IOUtils)
-- ============================================================================

local function file_exists(path)
    return IOUtils and IOUtils.file_exists and IOUtils.file_exists(path) or false
end

local function prefer_existing_path(candidates)
    return IOUtils and IOUtils.prefer_existing_path and IOUtils.prefer_existing_path(candidates) or nil
end

local function prefer_path_with_fallback(candidates)
    return IOUtils and IOUtils.prefer_path_with_fallback and IOUtils.prefer_path_with_fallback(candidates) or nil
end

local function directory_of(path)
    return IOUtils and IOUtils.directory_of and IOUtils.directory_of(path) or nil
end

local function join_path(base, fragment)
    return IOUtils and IOUtils.join_path and IOUtils.join_path(base, fragment) or nil
end

local function ensure_trailing_separator(path)
    return IOUtils and IOUtils.ensure_trailing_separator and IOUtils.ensure_trailing_separator(path) or path
end

-- ============================================================================
-- PATH RESOLUTION
-- ============================================================================

function DaemonPaths.ensure()
    -- Check if already resolved
    if DaemonState.get_daemon_exe() and DaemonState.get_daemon_ctl() then
        return true
    end

    local previous_pipe_directory = DaemonState.get_pipe_directory()
    local DLS = rawget(_G, "get_mod") and get_mod("DarktideLocalServer")
    if not DLS then
        return false
    end

    local mod_fs = IOUtils.get_mod_filesystem_path()
    if not mod_fs then
        return false
    end

    local addon_parent = IOUtils.parent_directory(mod_fs)
    local sibling_audio_base = addon_parent and join_path(addon_parent, "Audio")
    local local_audio_bin = nil

    if mod_fs then
        local_audio_bin = join_path(mod_fs, "Audio\\bin\\") or join_path(mod_fs, "audio\\bin\\")
        if local_audio_bin and local_audio_bin ~= "" then
            local_audio_bin = ensure_trailing_separator(local_audio_bin)
        end
    end

    -- Resolve daemon executable
    if not DaemonState.get_daemon_exe() then
        local exe_candidates = {
            join_path(mod_fs, "Audio\\bin\\miniaudio_dt.exe"),
            join_path(mod_fs, "audio\\bin\\miniaudio_dt.exe"),
            join_path(mod_fs, "Audio\\miniaudio_dt.exe"),
            join_path(mod_fs, "audio\\miniaudio_dt.exe"),
        }

        if sibling_audio_base then
            exe_candidates[#exe_candidates + 1] = join_path(sibling_audio_base, "bin\\miniaudio_dt.exe")
            exe_candidates[#exe_candidates + 1] = join_path(sibling_audio_base, "Audio\\bin\\miniaudio_dt.exe")
            exe_candidates[#exe_candidates + 1] = join_path(sibling_audio_base, "audio\\bin\\miniaudio_dt.exe")
        end

        local exe_path = prefer_existing_path(exe_candidates)
        DaemonState.set_daemon_exe(exe_path)
    end

    -- Resolve control file
    if local_audio_bin then
        DaemonState.set_daemon_ctl(local_audio_bin .. "miniaudio_dt.ctl")
    end

    if not DaemonState.get_daemon_ctl() then
        local ctl_candidates = {}

        local exe_dir = DaemonState.get_daemon_exe() and directory_of(DaemonState.get_daemon_exe()) or nil
        if exe_dir then
            ctl_candidates[#ctl_candidates + 1] = ensure_trailing_separator(exe_dir) .. "miniaudio_dt.ctl"
        end

        if mod_fs then
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "Audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "Audio\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "audio\\miniaudio_dt.ctl")
        end

        if sibling_audio_base then
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "Audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "Audio\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "audio\\miniaudio_dt.ctl")
        end

        local ctl_path = prefer_path_with_fallback(ctl_candidates)
        DaemonState.set_daemon_ctl(ctl_path)
    end

    -- Create control file if missing
    local ctl_path = DaemonState.get_daemon_ctl()
    if ctl_path and not file_exists(ctl_path) then
        local default_payload = "volume=1.000\r\npan=0.000\r\nstop=0\r\n"
        if not Utils.direct_write_file(ctl_path, default_payload) then
            if mod then
                mod:error("[DaemonPaths] Failed to create control file at %s", tostring(ctl_path))
            end
            return false
        end
    end

    -- Resolve pipe paths
    if local_audio_bin then
        DaemonState.set_pipe_payload(local_audio_bin .. "miniaudio_dt_payload.txt")
        DaemonState.set_pipe_directory(local_audio_bin)
    end

    if DaemonState.get_daemon_ctl() and not DaemonState.get_pipe_payload() then
        local base_dir = directory_of(DaemonState.get_daemon_ctl())
        if not base_dir and DaemonState.get_daemon_exe() then
            base_dir = directory_of(DaemonState.get_daemon_exe())
        end
        if base_dir then
            DaemonState.set_pipe_payload(join_path(base_dir, "miniaudio_dt_payload.txt"))
        end
    end

    if DaemonState.get_pipe_payload() and not DaemonState.get_pipe_directory() then
        local pipe_dir = directory_of(DaemonState.get_pipe_payload())
        if pipe_dir and pipe_dir ~= "" then
            DaemonState.set_pipe_directory(ensure_trailing_separator(pipe_dir))
        end
    end

    -- Purge payload files if pipe directory changed
    if DaemonState.get_pipe_directory() and DaemonState.get_pipe_directory() ~= previous_pipe_directory then
        if PayloadBuilder and PayloadBuilder.purge_payload_files then
            PayloadBuilder.purge_payload_files(DaemonState.get_pipe_payload(), DaemonState.get_pipe_directory())
        end
    end

    -- Debug output
    if debug_enabled and debug_enabled() and mod then
        mod:echo("[DaemonPaths] EXE=%s", tostring(DaemonState.get_daemon_exe()))
        mod:echo("[DaemonPaths] CTL=%s", tostring(DaemonState.get_daemon_ctl()))
    end

    return DaemonState.get_daemon_exe() ~= nil and DaemonState.get_daemon_ctl() ~= nil
end

return DaemonPaths
