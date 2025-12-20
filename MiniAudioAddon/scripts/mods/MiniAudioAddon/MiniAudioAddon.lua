--[[
    File: MiniAudioAddon.lua
    Description: Core MiniAudioAddon implementation that manages the MiniAudio daemon,
    exposes the public API used by other mods, and maintains diagnostics utilities.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
]]
local mod                   =     get_mod("MiniAudioAddon")
local DLS                   =     get_mod("DarktideLocalServer")

local Vector3               =     rawget(_G, "Vector3")
local Vector3Box            =     rawget(_G, "Vector3Box")
local Quaternion            =     rawget(_G, "Quaternion")
local QuaternionBox         =     rawget(_G, "QuaternionBox")
local Unit                  =     rawget(_G, "Unit")

-- ============================================================================
-- MODULE LOADING HELPERS
-- ============================================================================
--[[
    Resolve MiniAudioAddon module paths and provide convenience wrappers for loading.
    Args:       name/path strings as described below
    Returns:    Loaded module or fallback/nil
]]
-- Attempt to load a module from the given path, returning nil on failure
local function try_load_module(path)
    local ok, result = pcall(function()
        return mod:io_dofile(path)
    end)

    if ok then
        return result
    end

    mod:error("[MiniAudioAddon] Failed to load %s (%s)", tostring(path), tostring(result))
    return nil
end
-- Load a core MiniAudioAddon module from known locations
local function load_core_module(name, mod_property)
    if mod_property and mod[mod_property] then
        return mod[mod_property]
    end

    local module        =       try_load_module("MiniAudioAddon/scripts/mods/MiniAudioAddon/" .. name)  or 
                                try_load_module("scripts/mods/MiniAudioAddon/" .. name)                 or
                                try_load_module("mods/MiniAudioAddon/" .. name)
    
    if module and mod_property then
        mod[mod_property] =     module
    end
    
    return module
end
-- Load a required module, logging an error if it cannot be found
local function load_required_module(path, property, fallback)
    local module        =       load_core_module(path, property)
    if module then return module
    end

    mod:error("[MiniAudioAddon] CRITICAL: Failed to load %s module", path)
    return fallback
end
--  Wrapper for checking if debug is enabled setting under the tag "miniaudioaddon_debug"
local function debug_enabled()
    return mod:get("miniaudioaddon_debug")
end

-- ============================================================================
-- MODULE LOADING
-- ============================================================================
--[[
    Load every dependency the addon needs and cache it on the mod table when appropriate.
    Args:       none
    Returns:    Local references to required modules
]]

-- Utility modules
local Utils             =       load_required_module("utilities/utils", "utils", {})                   or {}
local IOUtils           =       load_required_module("utilities/io_utils", "io_utils", {})             or {}
local Logging           =       load_core_module("utilities/logging", "logging")
local SpatialTests      =       load_core_module("features/spatial_tests")
-- Core modules
local PoseTracker       =       load_core_module("core/pose_tracker", "pose_tracker")
local DaemonBridge      =       load_core_module("core/daemon_bridge", "daemon_bridge")
local AudioProfiles     =       load_core_module("core/audio_profiles", "audio_profiles")
local ClientManager     =       load_core_module("core/client_manager", "client_manager")
local Constants         =       load_core_module("core/constants", "constants")
local DaemonState       =       load_core_module("core/daemon_state", "daemon_state")
local DaemonPaths       =       load_core_module("core/daemon_paths", "daemon_paths")
local Shell             =       load_core_module("utilities/shell", "shell")
local Listener          =       load_core_module("utilities/listener", "listener")
local DaemonLifecycle   =       load_core_module("core/daemon_lifecycle", "daemon_lifecycle")
local Sphere            =       load_core_module("debug_visuals/sphere", "sphere")
local EmitterManager    =       load_core_module("core/emitter_manager", "emitter_manager")
local PayloadBuilder    =       load_core_module("core/payload_builder", "payload_builder")
local PlaylistManager   =       load_core_module("features/playlist_manager", "playlist_manager")
local PlatformController=       load_core_module("features/platform_controller", "platform_controller")
-- API factory (required)
local api_factory       =       load_core_module("core/api", "api")

-- ============================================================================
-- CONSTANTS AND STATE HELPERS
-- ============================================================================
--[[
    Define daemon tuning constants and wrap DaemonState access with safe helpers.
    Args:       none
    Returns:    Shared locals and guard functions
]]
local USE_MINIAUDIO_DAEMON          =       true

local on_generation_reset_callback  =       nil
local on_daemon_reset_callback      =       nil
local spatial_tests                 =       nil
local spatial_test_stop
local update_spatial_test
local start_spatial_test
local manual_track_path             =       nil
local manual_track_stop_pending     =       false
local manual_track_stop_message     =       nil
local manual_track_start_pending    =       false
local emitter_state                 =       nil


local legacy_clients = {}
local function set_client_active(client_id, has_active)
    if ClientManager and ClientManager.set_active then
        return ClientManager.set_active(client_id, has_active)
    end
    if has_active then
        legacy_clients[client_id] = true
    else
        legacy_clients[client_id] = nil
    end
end

local function has_any_clients()
    if ClientManager and ClientManager.has_any_clients then
        return ClientManager.has_any_clients()
    end
    return next(legacy_clients) ~= nil
end


local staged_payload_cleanups = {}
local purge_payload_files
local ensure_daemon_ready_for_tests
local ensure_listener_payload
local ensure_daemon_active
local cleanup_emitter_state
local clear_manual_track_state
local finalize_emitter_stop
local finalize_spatial_test_stop
local has_spatial_state
local run_shell_command
local run_spatial_command

-- ============================================================================
-- CALLBACK HANDLERS
-- ============================================================================
local function lifecycle_emitter_clear(reason)
    if cleanup_emitter_state then
        cleanup_emitter_state(reason or "daemon_reset", true)
    end
end

local function lifecycle_spatial_clear(reason)
    if spatial_test_stop then
        spatial_test_stop(reason or "daemon_reset", true)
    end
end

local function handle_daemon_stop_delivery(info)
    if not info or info.cmd ~= "stop" then
        return
    end

    if info.id == Constants.TRACK_IDS.manual then
        clear_manual_track_state()
        return
    end

    if emitter_state and emitter_state.track_id == info.id then
        finalize_emitter_stop()
        return
    end

    if spatial_tests and spatial_tests.handle_stop_delivery then
        spatial_tests.handle_stop_delivery(info.id)
    end
end

local function handle_daemon_stop_failure(info)
    if not info or info.cmd ~= "stop" then
        return
    end

    if info.id == Constants.TRACK_IDS.manual then
        if manual_track_stop_pending and manual_track_stop_message then
            mod:echo("[MiniAudioAddon] Manual stop command could not reach the daemon; run /miniaudio_test_stop again.")
        end
        manual_track_stop_pending = false
        manual_track_stop_message = nil
        return
    end

    if emitter_state and emitter_state.track_id == info.id then
        emitter_state.pending_stop = false
        if emitter_state.pending_message then
            mod:echo("[MiniAudioAddon] Failed to stop the emitter test; run /miniaudio_emit_stop again.")
        end
        return
    end

    if spatial_tests and spatial_tests.handle_stop_failure then
        spatial_tests.handle_stop_failure(info.id)
    end
end

local function handle_daemon_payload_delivery(info)
    if not info or info.cmd ~= "play" then
        return
    end

    if info.id == Constants.TRACK_IDS.manual then
        manual_track_start_pending = false
    end

    if emitter_state and emitter_state.track_id == info.id then
        emitter_state.pending_start = false
        emitter_state.started = true
        emitter_state.next_update = Utils.realtime_now()
    end

    if spatial_tests and spatial_tests.handle_play_delivery then
        spatial_tests.handle_play_delivery(info.id)
    end
end

local function handle_daemon_play_failure(info)
    if not info or info.cmd ~= "play" then
        return
    end

    if info.id == Constants.TRACK_IDS.manual then
        manual_track_start_pending = false
        manual_track_path = nil
        manual_track_stop_pending = false
        manual_track_stop_message = nil
        mod:echo("[MiniAudioAddon] Manual daemon playback request failed to reach the daemon; try again.")
        return
    end

    if emitter_state and emitter_state.track_id == info.id then
        cleanup_emitter_state("[MiniAudioAddon] Emitter start request failed; run /miniaudio_emit_start again.", false)
        return
    end

    if spatial_tests and spatial_tests.handle_play_failure then
        spatial_tests.handle_play_failure(info.id)
    end
end

-- ============================================================================
-- 
-- ===========================================================================

purge_payload_files = function()
    staged_payload_cleanups = {}

    local payload_path = DaemonState and DaemonState.get_pipe_payload and DaemonState.get_pipe_payload()
    local pipe_directory = DaemonState and DaemonState.get_pipe_directory and DaemonState.get_pipe_directory()

    if PayloadBuilder and PayloadBuilder.purge_payload_files then
        return PayloadBuilder.purge_payload_files(payload_path, pipe_directory)
    end

    if IOUtils and IOUtils.delete_file then
        if payload_path and payload_path ~= "" then
            IOUtils.delete_file(payload_path)
        end

        if pipe_directory and pipe_directory ~= "" then
            local directory = IOUtils.ensure_trailing_separator and IOUtils.ensure_trailing_separator(pipe_directory) or pipe_directory
            IOUtils.delete_file(directory .. "miniaudio_dt_last_play.json")
        end
    end

    return true
end

clear_manual_track_state = function()
    manual_track_path = nil
    manual_track_stop_pending = false
    manual_track_start_pending = false

    local message = manual_track_stop_message
    manual_track_stop_message = nil

    purge_payload_files()

    if message then
        mod:echo(message)
    end
end

local function log_last_play_payload(encoded)
    local pipe_directory = DaemonState and DaemonState.get_pipe_directory and DaemonState.get_pipe_directory()
    if not encoded or encoded == "" or not pipe_directory then
        return
    end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local payload = string.format("-- %s\n%s\n", timestamp or "", encoded)
    local debug_path = pipe_directory .. "miniaudio_dt_last_play.json"
    Utils.direct_write_file(debug_path, payload)
end

local function clear_manual_override(reason)
    if DaemonState and DaemonState.clear_manual_override then
        DaemonState.clear_manual_override(reason)
    end
end

local function apply_manual_override(volume_linear, pan)
    if DaemonState and DaemonState.apply_manual_override then
        return DaemonState.apply_manual_override(volume_linear, pan)
    end
    return volume_linear, pan
end


ensure_daemon_active = function(path_hint)
    if DaemonState and DaemonState.is_active and DaemonState.is_active() then
        return true
    end

    if ensure_daemon_ready_for_tests then
        return ensure_daemon_ready_for_tests(path_hint)
    end

    return false
end

local function spatial_mode_enabled()
    if mod.forced_spatial ~= nil then
        return mod.forced_spatial
    end
    return mod:get("miniaudioaddon_spatial_mode")
end

function mod:set_spatial_mode(enabled)
    mod.forced_spatial = enabled
end

function mod:debug_markers_enabled()
    local value = self:get("miniaudioaddon_debug_spheres")
    if value == nil then
        return true
    end
    return value
end

function mod:spatial_distance_scale()
    local scale = tonumber(self:get("miniaudioaddon_distance_scale")) or 1.0
    return Utils.clamp(scale, 0.5, 4.0)
end

run_shell_command = function(cmd, why, opts)
    if not (Shell and Shell.run_command) then
        return false
    end

    local ok = Shell.run_command(cmd, why, opts)
    if not ok and why and debug_enabled() then
        mod:error("[MiniAudioAddon] Command failed (%s): %s", why, cmd)
    end
    return ok
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================
--[[
    Initialize loaded modules with the dependencies they require.
    Args:       none
    Returns:    none
]]

if Constants and Constants.init then
    Constants.init()
end

if DaemonState and DaemonState.init then
    DaemonState.init({
        Utils = Utils,
        debug_enabled       = debug_enabled,
        generation_callback = function(generation, reason) end,  --Used for external mods or modules to understand when generation changes
    })
end

if Shell then
    Shell.init({
        DLS = DLS,
        mod = mod,
        debug_enabled = debug_enabled,
    })
end

if Listener and Listener.init then
    Listener.init({
        mod = mod,
        Utils = Utils,
    })
end

if DaemonPaths and DaemonPaths.init then
    DaemonPaths.init({
        mod = mod,
        IOUtils = IOUtils,
        DaemonState = DaemonState,
        Utils = Utils,
        debug_enabled = debug_enabled,
        PayloadBuilder = PayloadBuilder,
    })
end

if EmitterManager and Utils and PoseTracker and DaemonBridge then
    EmitterManager.init({
        Utils = Utils,
        PoseTracker = PoseTracker,
        DaemonBridge = DaemonBridge,
    })
end

if Sphere and Utils then
    Sphere.init({
        Utils = Utils,
    })
end

if PlaylistManager and PlaylistManager.init then
    PlaylistManager.init({
        Utils = Utils,
        IOUtils = IOUtils,
        Constants = Constants,
    })
end

if PlatformController and PlatformController.init then
    PlatformController.init({
        Utils = Utils,
        EmitterManager = EmitterManager,
        Sphere = Sphere,
        PlaylistManager = PlaylistManager,
        ClientManager = ClientManager,
        MiniAudioMod = mod,
        IOUtils = IOUtils,
    })
end

if IOUtils and IOUtils.init then
    IOUtils.init({ 
        mod = mod, 
        DLS = DLS 
    })
end

if Logging and Logging.init then
    Logging.init({
        mod = mod,
        IOUtils = IOUtils,
        DaemonPaths = DaemonPaths,
        DaemonState = DaemonState,
    })
end

-- ============================================================================
-- DAEMON BRIDGE AND LIFECYCLE INITIALIZATION
-- ============================================================================

if DaemonBridge and DaemonBridge.init_state then
    DaemonBridge.init_state({
        Utils = Utils,
        get_daemon_stdio = function()
            if DaemonState and DaemonState.get_stdio then
                return DaemonState.get_stdio()
            end
            return nil
        end,
        set_daemon_stdio = function(value)
            if DaemonState and DaemonState.set_stdio then
                DaemonState.set_stdio(value)
            end
        end,
        get_daemon_pipe_name = function()
            if DaemonState and DaemonState.get_pipe_name then
                return DaemonState.get_pipe_name()
            end
            return nil
        end,
        get_daemon_pending_messages = function()
            if DaemonState and DaemonState.get_pending_messages then
                return DaemonState.get_pending_messages()
            end
            return {}
        end,
        get_daemon_is_running = function()
            if DaemonState and DaemonState.is_running then
                return DaemonState.is_running()
            end
            return false
        end,
        get_daemon_has_known_process = function()
            if DaemonState and DaemonState.has_known_process then
                return DaemonState.has_known_process()
            end
            return false
        end,
        get_daemon_exe = function()
            if DaemonState and DaemonState.get_daemon_exe then
                return DaemonState.get_daemon_exe()
            end
            return nil
        end,
        MIN_TRANSPORT_SPEED = Constants.MIN_TRANSPORT_SPEED,
        MAX_TRANSPORT_SPEED = Constants.MAX_TRANSPORT_SPEED,
        PIPE_RETRY_DELAY = Constants.PIPE_RETRY_DELAY,
        PIPE_RETRY_MAX_ATTEMPTS = Constants.PIPE_RETRY_MAX_ATTEMPTS,
        PIPE_RETRY_GRACE = Constants.PIPE_RETRY_GRACE,
    })
end

if DaemonBridge and DaemonBridge.init_dependencies then
    DaemonBridge.init_dependencies({
        DaemonState = DaemonState,
        DaemonPaths = DaemonPaths,
        Shell = Shell,
        AudioProfiles = AudioProfiles,
        DaemonLifecycle = DaemonLifecycle,
    })
end

if DaemonBridge and DaemonBridge.init_callbacks then
    DaemonBridge.init_callbacks({
        write_api_log = Logging and Logging.write_api_log or function() end,
        log_last_play_payload = log_last_play_payload,
        handle_daemon_payload_delivery = handle_daemon_payload_delivery,
        handle_daemon_stop_delivery = handle_daemon_stop_delivery,
        handle_daemon_play_failure = handle_daemon_play_failure,
        handle_daemon_stop_failure = handle_daemon_stop_failure,
    })
end

if DaemonLifecycle and DaemonLifecycle.init then
    DaemonLifecycle.init({
        mod = mod,
        DLS = DLS,
        Utils = Utils,
        IOUtils = IOUtils,
        DaemonBridge = DaemonBridge,
        DaemonState = DaemonState,
        DaemonPaths = DaemonPaths,
        ClientManager = ClientManager,
        Shell = Shell,
        Constants = Constants,
        handle_daemon_stop_failure = handle_daemon_stop_failure,
        manual_playback_clear = clear_manual_track_state,
        emitter_test_clear = lifecycle_emitter_clear,
        spatial_test_clear = lifecycle_spatial_clear,
    })
end

-- ============================================================================
-- ERROR AND ECHO WRAPPER TO LOG API CALLS
-- ============================================================================
--[[
    Monkey-patch mod:echo and mod:error to also write to API log when enabled.
    The miniaudio_api_log_wrapped guard ensures we only monkey‑patch mod:echo/mod:error once so 
    every console message also hits Logging.write_api_log(...) when API logging is enabled. Without 
    it API log setting wouldn’t capture calls from MiniAudioAddon or dependent mods.
    This basically allows whatever is echoed or error in DMF to go into our text API text file
    from  MiniAudioAddon or any mod that uses it.
    Args:       none
    Returns:    none
]]

if not mod.miniaudio_api_log_wrapped then
    mod.miniaudio_api_log_wrapped = true
    local original_echo = mod.echo
    local original_error = mod.error

    function mod:echo(fmt, ...)
        if fmt and Logging and Logging.api_log_enabled() then
            Logging.write_api_log("ECHO: " .. tostring(fmt), ...)
        end
        if original_echo then
            return original_echo(self, fmt, ...)
        end
    end

    function mod:error(fmt, ...)
        if fmt and Logging and Logging.api_log_enabled() then
            Logging.write_api_log("ERROR: " .. tostring(fmt), ...)
        end
        if original_error then
            return original_error(self, fmt, ...)
        end
    end
end

-- ============================================================================
-- DAEMON WATCHDOG HELPERS
-- ============================================================================

local function schedule_daemon_watchdog()
    if DaemonLifecycle and DaemonLifecycle.schedule_watchdog then
        DaemonLifecycle.schedule_watchdog()
        return
    end

    if DaemonState and DaemonState.set_watchdog_until and DaemonState.set_watchdog_next_attempt then
        DaemonState.set_watchdog_until(Utils.realtime_now() + (Constants.DAEMON_WATCHDOG_WINDOW or 0))
        DaemonState.set_watchdog_next_attempt(0)
    end
end

local function has_internal_activity()
    if DaemonLifecycle and DaemonLifecycle.has_internal_activity then
        return DaemonLifecycle.has_internal_activity(
            manual_track_path ~= nil,
            manual_track_stop_pending,
            emitter_state ~= nil,
            has_spatial_state and has_spatial_state()
        )
    end

    if manual_track_path or manual_track_stop_pending then
        return true
    end

    if emitter_state or (has_spatial_state and has_spatial_state()) then
        return true
    end

    local pending = (DaemonState and DaemonState.get_pending_messages and DaemonState.get_pending_messages()) or {}
    return pending and #pending > 0
end

local function daemon_is_idle()
    return (not has_any_clients()) and not has_internal_activity()
end

local function clear_daemon_watchdog()
    if DaemonLifecycle and DaemonLifecycle.clear_watchdog then
        DaemonLifecycle.clear_watchdog()
        return
    end

    if DaemonState and DaemonState.set_watchdog_until and DaemonState.set_watchdog_next_attempt then
        DaemonState.set_watchdog_until(0)
        DaemonState.set_watchdog_next_attempt(0)
    end
end

local function reset_daemon_status(reason)
    if DaemonLifecycle and DaemonLifecycle.reset then
        DaemonLifecycle.reset(reason)
    end
    staged_payload_cleanups = {}
end


-- ============================================================================
-- FULL EXTERNAL MOD API EXPOSURE OVERIDE (Allows other mods direct access to methods in these modules)
-- ============================================================================
mod.IOUtils     = IOUtils or {}
mod.io_utils    = mod.IOUtils       -- Legacy alias
mod.Utils       = Utils or {}
mod.utils       = mod.Utils         -- Legacy alias
mod.playlist_manager = PlaylistManager
mod.platform_controller = PlatformController

-- ============================================================================
-- EXTERNAL MOD API EXPOSURE
-- ============================================================================
-- Note: mod.api.expand_track_path will be set by init_api_layer() later

local function draw_emitter_marker(position, rotation)
    if not mod:debug_markers_enabled() then
        Sphere.clear_marker("emitter")
        return
    end
    
    Sphere.draw_marker(
        "emitter",
        position,
        rotation,
        emitter_marker_state.label,
        emitter_marker_state.text_category,
        emitter_marker_state.text_color
    )
end

local function clear_emitter_marker()
    Sphere.clear_marker("emitter")
end

local function draw_spatial_marker(position)
    if not mod:debug_markers_enabled() then
        Sphere.clear_marker("spatial")
        return
    end
    
    Sphere.draw_marker(
        "spatial",
        position,
        nil,
        spatial_marker_state.label,
        spatial_marker_state.text_category,
        spatial_marker_state.text_color
    )
end

local function clear_spatial_marker()
    Sphere.clear_marker("spatial")
end

local function clear_daemon_log_file(reason)
    if mod:get("miniaudioaddon_clear_logs") == false then
        return false
    end
    if DaemonLifecycle and DaemonLifecycle.clear_log then
        return DaemonLifecycle.clear_log(reason)
    end
    return false
end

local function daemon_write_control(volume_linear, pan, stop_flag, opts)
    if not (DaemonLifecycle and DaemonLifecycle.write_control) then
        return false
    end
    return DaemonLifecycle.write_control(volume_linear, pan, stop_flag, opts)
end

local function daemon_force_quit(opts)
    if DaemonLifecycle and DaemonLifecycle.force_quit then
        DaemonLifecycle.force_quit(opts)
    end
    purge_payload_files()
end

local function daemon_start(path, volume_linear, pan)
    if not (DaemonLifecycle and DaemonLifecycle.start) then
        return false
    end
    return DaemonLifecycle.start(path, volume_linear, pan)
end
if ClientManager and ClientManager.init then
    ClientManager.init({
        daemon_is_active = function()
            return DaemonState and DaemonState.is_active and DaemonState.is_active()
        end,
        daemon_start = daemon_start,
    })
end

local function daemon_update(volume_linear, pan)
    if DaemonLifecycle and DaemonLifecycle.update then
        DaemonLifecycle.update(volume_linear, pan)
    end
end

local function daemon_stop()
    if DaemonLifecycle and DaemonLifecycle.stop then
        DaemonLifecycle.stop()
    end
end
local function daemon_manual_control(volume_linear, pan)
    if not (DaemonLifecycle and DaemonLifecycle.manual_control) then
        return false, "not_available"
    end
    return DaemonLifecycle.manual_control(volume_linear, pan)
end

-- ============================================================================
-- CLIENT MANAGEMENT
-- ============================================================================

local function infer_client_id()
    local dbg = debug and debug.getinfo
    if not dbg then
        return nil
    end

    for level = 3, 8 do
        local info = dbg(level, "S")
        local src = info and info.source
        if type(src) == "string" then
            local cleaned = src:gsub("^@", "")
            local mod_name = cleaned:match("mods[/\\]([^/\\]+)")
            if mod_name and mod_name ~= mod:get_name() then
                return mod_name
            end
        end
    end

    return nil
end

function mod:set_client_active(client_id, has_active)
    client_id = client_id or infer_client_id() or "default"
    set_client_active(client_id, has_active)
end

function mod:_set_keepalive(active)
    self._keepalive_flag = active and true or false
    set_client_active("MiniAudioAddon_keepalive", self._keepalive_flag)
end

function mod:ensure_daemon_keepalive()
    self:_set_keepalive(true)
    if not (DaemonState and DaemonState.is_active and DaemonState.is_active()) then
        daemon_start("", 1.0, 0.0)
    end
end

function mod:on_generation_reset(callback)
    on_generation_reset_callback = callback
    if ClientManager and ClientManager.set_generation_callback then
        ClientManager.set_generation_callback(on_generation_reset_callback)
    end
end

function mod:on_daemon_reset(callback)
    on_daemon_reset_callback = callback
    if ClientManager and ClientManager.set_reset_callback then
        ClientManager.set_reset_callback(on_daemon_reset_callback)
    end
end

local function report_manual_error(reason)
    if reason == "disabled" then
        mod:echo("[MiniAudioAddon] Manual controls require the miniaudio daemon backend.")
    elseif reason == "not_running" then
        mod:echo("[MiniAudioAddon] No daemon-managed track is currently running.")
    else
        mod:echo(string.format("[MiniAudioAddon] Failed to send manual control update (%s).", tostring(reason)))
    end
end

local function manual_override_active()
    return DaemonState and DaemonState.get_manual_override and DaemonState.get_manual_override() ~= nil
end

local function collect_command_args(...)
    local args = { ... }
    local cleaned = {}
    for _, value in ipairs(args) do
        if value ~= nil and value ~= "" then
            cleaned[#cleaned + 1] = value
        end
    end
    return cleaned
end

local function join_command_args(args, start_idx, end_idx)
    start_idx = start_idx or 1
    end_idx = end_idx or #args
    if start_idx > end_idx or start_idx > #args then
        return nil
    end

    local parts = {}
    for i = start_idx, math.min(end_idx, #args) do
        parts[#parts + 1] = args[i]
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " ")
end

local function require_spatial_mode()
    if spatial_mode_enabled() then
        return true
    end

    mod:echo("[MiniAudioAddon] Enable spatial mode in the mod options to use the JSON daemon tests.")
    return false
end

local function stop_manual_track(silent)
    if not manual_track_path then
        if not silent then
            mod:echo("[MiniAudioAddon] No manual daemon track is active.")
        end
        return false
    end

    if manual_track_stop_pending then
        if not silent then
            mod:echo("[MiniAudioAddon] Manual daemon stop already pending; wait a moment.")
        end
        return true
    end

    local ok, queued = daemon_send_stop(Constants.TRACK_IDS.manual, 0.35)
    if not ok then
        if not silent then
            mod:echo("[MiniAudioAddon] Failed to stop the manual daemon track; run /miniaudio_test_stop again.")
        end
        return false
    end

    manual_track_stop_message = silent and nil or "[MiniAudioAddon] Manual daemon track stopped."

    if queued then
        manual_track_stop_pending = true
        if not silent then
            mod:echo("[MiniAudioAddon] Waiting for the daemon to apply the stop request...")
        end
        return true
    end

    clear_manual_track_state()
    return true
end

local function start_manual_track(resolved_path)
    if not resolved_path then
        return false
    end

    if manual_track_path then
        if not stop_manual_track(true) then
            mod:echo("[MiniAudioAddon] Failed to stop the previous manual test.")
            return false
        end

        if manual_track_path or manual_track_stop_pending then
            mod:echo("[MiniAudioAddon] Waiting for the previous manual test to stop; try again in a moment.")
            return false
        end
    elseif manual_track_stop_pending then
        mod:echo("[MiniAudioAddon] A manual daemon stop is already pending; try again once it finishes.")
        return false
    end

    if not require_spatial_mode() then
        return false
    end

    if not ensure_daemon_ready_for_tests(resolved_path) then
        return false
    end

    local listener = ensure_listener_payload()
    if not listener then
        return false
    end

    local track = {
        id = Constants.TRACK_IDS.manual,
        path = resolved_path,
        loop = true,
        volume = 1.0,
        profile = default_profile(),
        listener = listener,
        source = {
            position = listener.position,
            forward = listener.forward,
            velocity = { 0, 0, 0 },
        },
    }

    local ok, queued = daemon_send_play(track)
    if ok then
        manual_track_path = resolved_path
        manual_track_stop_pending = false
        manual_track_stop_message = nil
        manual_track_start_pending = queued or false
        mod:echo("[MiniAudioAddon] Manual daemon playback started: %s", resolved_path)
        if queued then
            mod:echo("[MiniAudioAddon] Waiting for the daemon to accept the manual playback request...")
        end
        return true
    end

    mod:echo("[MiniAudioAddon] Failed to start manual daemon playback.")
    return false
end

local function resolve_simple_track(choice)
    local key = choice and choice:lower()
    local relative = Constants.SIMPLE_TEST.tracks[key]  or Constants.SIMPLE_TEST.tracks[Constants.SIMPLE_TEST.default]
    if not relative then
        return nil
    end

    local resolved = IOUtils.expand_track_path(relative)
    if not resolved then
        mod:echo("[MiniAudioAddon] Simple test file missing: %s", relative)
    end
    return resolved
end

local function default_profile()
    local base = AudioProfiles and AudioProfiles.MEDIUM_RANGE or {
        min_distance = 1.0,
        max_distance = 20.0,
        rolloff = "logarithmic",
    }

    local profile = AudioProfiles and AudioProfiles.copy and AudioProfiles.copy(base) or {
        min_distance = base.min_distance,
        max_distance = base.max_distance,
        rolloff = base.rolloff,
    }

    profile.rolloff = mod:get("miniaudioaddon_spatial_rolloff") or profile.rolloff or "linear"
    return profile
end

local function parse_simple_distance_and_choice(a, b)
    local distance = nil
    local choice = a

    if a and tonumber(a) then
        distance = tonumber(a)
        choice = b
    elseif b and tonumber(b) then
        distance = tonumber(b)
    end

    return distance, choice
end

local function manual_track_active()
    return manual_track_path ~= nil
end

local function manual_stop_pending_flag()
    return manual_track_stop_pending
end

local function emitter_active()
    return emitter_state ~= nil
end

local function start_emitter_track(resolved_path, distance, absolute_profile)
    if not resolved_path then
        return false
    end

    if emitter_state then
        if not cleanup_emitter_state(nil, true) then
            mod:echo("[MiniAudioAddon] Failed to stop the previous emitter test.")
            return false
        end

        if emitter_state then
            mod:echo("[MiniAudioAddon] Waiting for the previous emitter test to stop; try again shortly.")
            return false
        end
    end

    if not require_spatial_mode() then
        return false
    end

    if not ensure_daemon_ready_for_tests(resolved_path) then
        return false
    end

    local listener_pos, listener_rot = Utils.listener_pose()
    if not listener_pos or not listener_rot or not Vector3 then
        mod:echo("[MiniAudioAddon] Listener pose unavailable; enter gameplay before running emitter tests.")
        return false
    end

    local distance_clamped = Utils.clamp(distance or 3, 0.5, 25)
    local forward = Utils.safe_forward(listener_rot)
    local spawn_pos = listener_pos + forward * distance_clamped
    local spawn_rot = listener_rot
    local show_debug_markers = mod:debug_markers_enabled()
    local unit = nil
    if show_debug_markers then
        unit = Sphere.spawn_unit(Constants.MARKER_SETTINGS.emitter_unit, spawn_pos, spawn_rot)
    end
    if show_debug_markers and not unit then
        mod:echo("[MiniAudioAddon] Failed to spawn the debug emitter unit; using a wireframe marker instead.")
    end

    local listener = ensure_listener_payload()
    if not listener then
        destroy_spawned_unit(unit)
        return false
    end

    local emitter_profile = default_profile()
    local distance_scale = mod:spatial_distance_scale()
    if absolute_profile then
        emitter_profile.min_distance = Utils.clamp(1.0 * distance_scale, 0.35, 10.0)
        emitter_profile.max_distance = Utils.clamp(30.0 * distance_scale, emitter_profile.min_distance + 1.0, 200.0)
    else
        local emitter_min_distance = Utils.clamp(distance_clamped * 0.25 * distance_scale, 0.5, 25.0)
        local emitter_max_distance = Utils.clamp(distance_clamped * 5.0 * distance_scale, emitter_min_distance + 5.0, 150.0)
        emitter_profile.min_distance = emitter_min_distance
        emitter_profile.max_distance = emitter_max_distance
    end

    local track = {
        id = Constants.TRACK_IDS.emitter,
        path = resolved_path,
        loop = true,
        volume = 1.0,
        profile = emitter_profile,
        listener = listener,
        source = {
            position = Utils.vec3_to_array(spawn_pos),
            forward = Utils.vec3_to_array(forward),
            velocity = { 0, 0, 0 },
        },
    }

    local ok, queued = daemon_send_play(track)
    if ok then
        emitter_state = {
            unit = unit,
            track_id = Constants.TRACK_IDS.emitter,
            path = resolved_path,
            next_update = Utils.realtime_now(),
            pending_start = queued or false,
            started = not queued,
            pending_stop = false,
            pending_message = nil,
            position_box = Vector3Box and Vector3Box(spawn_pos) or spawn_pos,
            rotation_box = QuaternionBox and QuaternionBox(spawn_rot) or spawn_rot,
        }
        local status = queued and "pending" or "started"
        mod:echo("[MiniAudioAddon] Debug emitter spawned %.1fm ahead; audio %s.", distance_clamped, status)
        if queued then
            mod:echo("[MiniAudioAddon] Waiting for the daemon to accept the emitter playback request...")
        end
        draw_emitter_marker(spawn_pos, spawn_rot)
        return true
    end

    destroy_spawned_unit(unit)
    mod:echo("[MiniAudioAddon] Failed to start the emitter audio.")
    return false
end

cleanup_emitter_state = function(reason, silent)
    if not emitter_state then
        return false
    end

    local state = emitter_state
    local message = nil
    if not silent then
        message = reason or "[MiniAudioAddon] Emitter test stopped."
    end

    if state.pending_stop then
        if message then
            state.pending_message = state.pending_message or message
            if not silent then
                mod:echo("[MiniAudioAddon] Waiting for the emitter stop to finish...")
            end
        end
        return true
    end

    destroy_spawned_unit(state.unit)
    state.unit = nil

    state.position_box = nil
    state.rotation_box = nil

    clear_emitter_marker()

    state.pending_message = message

    if state.pending_start then
        state.pending_start = false
        state.track_id = nil
    end

    if not state.track_id then
        emitter_state = nil
        purge_payload_files()
        if message then
            mod:echo(message)
        end
        return true
    end

    local ok, queued, detail = daemon_send_stop(state.track_id, state.fade or 0.35)
    local reason = detail
    if not ok then
        if reason == "daemon_offline" then
            emitter_state = nil
            purge_payload_files()
            if message then
                mod:echo(message)
            end
            return true
        end
        state.pending_message = nil
        state.pending_stop = false
        if not silent then
            mod:echo("[MiniAudioAddon] Failed to stop the emitter test; run /miniaudio_emit_stop again.")
        end
        return false
    end

    if queued then
        state.pending_stop = true
        if not silent then
            mod:echo("[MiniAudioAddon] Waiting for the emitter stop request to reach the daemon...")
        end
        return true
    end

    emitter_state = nil
    purge_payload_files()
    if message then
        mod:echo(message)
    end
    return true
end

finalize_emitter_stop = function()
    if not emitter_state then
        return
    end

    local message = emitter_state.pending_message
    clear_emitter_marker()
    emitter_state = nil
    purge_payload_files()
    if message then
        mod:echo(message)
    end
end


local function command_cleanup_payloads()
    if DaemonPaths and DaemonPaths.ensure then
        DaemonPaths.ensure()
    end
    local pipe_directory = DaemonState and DaemonState.get_pipe_directory and DaemonState.get_pipe_directory()
    if not pipe_directory then
        mod:echo("[MiniAudioAddon] Payload directory not resolved; nothing to clean.")
        return
    end

    purge_payload_files()
    mod:echo(string.format("[MiniAudioAddon] Cleared payload files under %s", pipe_directory))
end

mod:command("miniaudio_cleanup_payloads", "Delete leftover miniaudio payload files beside the daemon.", command_cleanup_payloads)

ensure_listener_payload = function()
    local payload = Utils.build_listener_payload()
    if payload then
        return payload
    end

    mod:echo("[MiniAudioAddon] Listener pose unavailable; enter gameplay before running the spatial test.")
    return nil
end

local function init_api_layer()
    local api_factory = try_load_module("MiniAudioAddon/scripts/mods/MiniAudioAddon/core/api") or
        try_load_module("scripts/mods/MiniAudioAddon/core/api") or
        try_load_module("core/api")

    if not api_factory then
        mod:error("[MiniAudioAddon] core/api.lua missing; API exports unavailable.")
        return
    end

    local api = api_factory(mod, Utils, {
        DaemonBridge = DaemonBridge,
        Utils = Utils,
        ensure_listener = ensure_listener_payload,
        build_listener = Utils.build_listener_payload,
        spatial_mode_enabled = spatial_mode_enabled,
        daemon_is_active = function()
            return DaemonState and DaemonState.is_active and DaemonState.is_active()
        end,
        ensure_daemon_ready = ensure_daemon_ready_for_tests,
        daemon_start = daemon_start,
        daemon_stop = daemon_stop,
        daemon_update = daemon_update,
        daemon_manual_control = daemon_manual_control,
        get_daemon_is_running = function()
            local running = DaemonState and DaemonState.is_running and DaemonState.is_running()
            local pending = DaemonState and DaemonState.is_pending_start and DaemonState.is_pending_start()
            return (running or pending) and true or false
        end,
        get_daemon_pipe_name = function()
            if DaemonState and DaemonState.get_pipe_name then
                return DaemonState.get_pipe_name()
            end
            return nil
        end,
        get_daemon_generation = daemon_generation,
        now = now,
        realtime_now = Utils.realtime_now,
        logger = write_api_log,
        MIN_TRANSPORT_SPEED = Constants.MIN_TRANSPORT_SPEED,
        MAX_TRANSPORT_SPEED = Constants.MAX_TRANSPORT_SPEED,
    })

    if api then
        mod.api = api
        -- Add additional API properties
        mod.api.expand_track_path = IOUtils.expand_track_path
        mod.api.listener_pose = Utils.listener_pose
        mod.api.build_listener_payload = Utils.build_listener_payload
        mod.api.ensure_listener = Utils.ensure_listener
        mod.api.Utils = mod.utils
        mod.api.PoseTracker = mod.pose_tracker
        mod.api.DaemonBridge = mod.daemon_bridge
        mod.api.Sphere = mod.sphere
        mod.api.EmitterManager = mod.emitter_manager
        mod.api.AudioProfiles = mod.audio_profiles
        mod.api.Logging = mod.logging
        mod.api.playlist = PlaylistManager
        mod.api.platform_controller = PlatformController
        mod.api.is_daemon_running = function()
            local running = DaemonState and DaemonState.is_running and DaemonState.is_running()
            local pending = DaemonState and DaemonState.is_pending_start and DaemonState.is_pending_start()
            return (running or pending) and true or false
        end
        mod.api.get_pipe_name = function()
            if DaemonState and DaemonState.get_pipe_name then
                return DaemonState.get_pipe_name()
            end
            return nil
        end
        mod.api.get_generation = DaemonState.get_generation
        mod.api.daemon_start = daemon_start
        mod.api.daemon_stop = daemon_stop
        mod.api.daemon_update = daemon_update
        mod.api.daemon_manual_control = daemon_manual_control
        mod.api.register_client = function(client_name, active)
            set_client_active(client_name or mod:get_name(), active)
            return true
        end
        if mod.emitter_manager then
            mod.api.emitter_get = mod.emitter_manager.get
            mod.api.emitter_exists = mod.emitter_manager.exists
            mod.api.emitter_position = mod.emitter_manager.get_position
            mod.api.emitter_stop_all = mod.emitter_manager.stop_all
        end
    else
        mod:error("[MiniAudioAddon] Failed to initialize MiniAudio API module.")
    end
end

init_api_layer()

if SpatialTests then
    spatial_tests = SpatialTests.new(mod, {
        Utils = Utils,
        DaemonState = DaemonState,
        DaemonBridge = DaemonBridge,
        daemon_start = daemon_start,
        daemon_send_json = DaemonBridge and DaemonBridge.daemon_send_json,
        daemon_send_stop = rawget(_G, "daemon_send_stop"),
        daemon_track_profile = DaemonBridge and DaemonBridge.daemon_track_profile,
        daemon_spatial_effects = DaemonBridge and DaemonBridge.daemon_spatial_effects,
        draw_spatial_marker = draw_spatial_marker,
        clear_spatial_marker = clear_spatial_marker,
        purge_payload_files = function()
            return purge_payload_files()
        end,
        debug_enabled = debug_enabled,
        listener_pose = Utils.listener_pose,
    })

    if spatial_tests then
        ensure_daemon_ready_for_tests = spatial_tests.ensure_ready
        spatial_test_stop = spatial_tests.stop
        finalize_spatial_test_stop = spatial_tests.finalize
        update_spatial_test = function(dt)
            spatial_tests.update(dt)
        end
        has_spatial_state = spatial_tests.has_state
        start_spatial_test = spatial_tests.start
    end
end

ensure_daemon_ready_for_tests = ensure_daemon_ready_for_tests or function()
    return false
end
spatial_test_stop = spatial_test_stop or function()
    return true
end
finalize_spatial_test_stop = finalize_spatial_test_stop or function()
end
has_spatial_state = has_spatial_state or function()
    return false
end
start_spatial_test = start_spatial_test or function() end
update_spatial_test = update_spatial_test or function() end

-- ============================================================================
--  Register Command Modules
-- ============================================================================
--[[
    Name:       register_command_modules
    Purpose:    Load and register command modules that expose chat commands for MiniAudioAddon.
                Each module receives the exact helpers it needs so the bootstrap file only
                coordinates wiring without embedding the command logic.
    Args:       None
    Returns:    None
]]
--[[

]]
local function register_command_modules()
    local function register(path, deps)
        local module = load_core_module(path)
        if module and module.register then
            return module.register(mod, deps)
        elseif debug_enabled() then
            mod:echo("[MiniAudioAddon] Command module missing: %s", path)
        end
        return nil
    end

    register("commands/system", {
        clamp = Utils.clamp,
        daemon_manual_control = daemon_manual_control,
        report_manual_error = report_manual_error,
        manual_override_active = manual_override_active,
        clear_manual_override = clear_manual_override,
    })

    register("commands/manual", {
        collect_command_args = collect_command_args,
        expand_track_path = IOUtils.expand_track_path,
        start_manual_track = start_manual_track,
        stop_manual_track = stop_manual_track,
        has_manual_track = manual_track_active,
        manual_stop_pending = manual_stop_pending_flag,
    })

    register("commands/emitter", {
        collect_command_args = collect_command_args,
        expand_track_path = IOUtils.expand_track_path,
        start_emitter_track = start_emitter_track,
        cleanup_emitter_state = cleanup_emitter_state,
        emitter_active = emitter_active,
    })

    local spatial_module = register("commands/spatial", {
        collect_command_args = collect_command_args,
        join_command_args = join_command_args,
        Utils = Utils,
        ensure_listener_payload = ensure_listener_payload,
        spatial_mode_enabled = spatial_mode_enabled,
        ensure_daemon_ready_for_tests = ensure_daemon_ready_for_tests,
        start_spatial_test = start_spatial_test,
        stop_spatial_test = spatial_test_stop,
        has_spatial_state = has_spatial_state,
        default_profile = default_profile,
        expand_track_path = IOUtils.expand_track_path,
        listener_pose = Utils.listener_pose,
    })

    if spatial_module and spatial_module.run then
        run_spatial_command = spatial_module.run
    end

    register("commands/simple", {
        expand_track_path = IOUtils.expand_track_path,
        simple_tracks = Constants.SIMPLE_TEST.tracks,
        simple_default = Constants.SIMPLE_TEST.default,
        start_manual_track = start_manual_track,
        start_emitter_track = start_emitter_track,
        stop_manual_track = stop_manual_track,
        cleanup_emitter_state = cleanup_emitter_state,
        manual_track_active = manual_track_active,
        manual_stop_pending = manual_stop_pending_flag,
        emitter_active = emitter_active,
        spatial_run = run_spatial_command,
    })
end

register_command_modules()

-- ============================================================================
--  Loaded Mods
-- ============================================================================
--[[
    Name:       mod.on_all_mods_loaded
    Purpose:    Ensures the daemon is kept alive and announces the API log path
                once all mods have been loaded.
    Args:       None
    Returns:    None
]]
function mod.on_all_mods_loaded()
    mod:ensure_daemon_keepalive()
    Logging.announce_api_log_path()
end
-- ============================================================================
--  Disable Mod
-- ============================================================================
--[[
    Name:       mod.on_disabled
    Purpose:    Handles cleanup when the mod is disabled, including disabling keepalive,
                stopping spatial tests, clearing legacy clients, and cleaning up payload files.
    Args:       None
    Returns:    None
]]
mod.on_disabled = function()
    mod:_set_keepalive(false)
    legacy_clients = {}
    if ClientManager and ClientManager.clear_all then
        ClientManager.clear_all()
    end
    spatial_test_stop("disabled")
    stop_manual_track(true)
    cleanup_emitter_state(nil, true)
    daemon_stop()

    local pipe_payload = DaemonState and DaemonState.get_pipe_payload and DaemonState.get_pipe_payload()
    if IOUtils and IOUtils.delete_file then
        for _, entry in ipairs(staged_payload_cleanups) do
            if entry and entry.path and entry.path ~= pipe_payload then
                IOUtils.delete_file(entry.path)
            end
        end
    end
    staged_payload_cleanups = {}
    purge_payload_files()
    clear_daemon_log_file("mod_disabled")
end
-- ============================================================================
-- Unloading mods
-- ============================================================================
--[[
    Name:       mod.on_unload
    Purpose:    Handles cleanup when the mod is unloaded, including disabling keepalive
                and clearing the daemon log file.
    Args:       None
    Returns:    None
]]
-- ============================================================================
mod.on_unload = function()
    mod:_set_keepalive(false)
    clear_daemon_log_file("mod_unload")
end

-- ============================================================================
-- On Game State Changed for Gameplay Entry, Entering Game/Meat Grinder/Etc.
-- ============================================================================
--[[
    Name:       mod.on_game_state_changed
    Purpose:    Handles changes to the game state, specifically clearing the daemon log
                file upon entering gameplay.
    Args:       status (string) - The status of the game state change ("enter" or "exit").
                state_name (string) - The name of the new game state.
    Returns:    None
]]
-- ============================================================================
mod.on_game_state_changed = function(status, state_name)
    if status == "enter" and state_name == "StateGameplay" then
        clear_daemon_log_file("enter_gameplay")
    end
end

-- ============================================================================
-- On Setting Changed for API logging
-- ============================================================================
--[[
    Name:       mod.on_setting_changed
    Purpose:    Handles changes to mod settings, specifically enabling or disabling
                API logging.
    Args:       setting_id (string) - The identifier of the changed setting.
    Returns:    None
]]
-- ============================================================================

function mod.on_setting_changed(setting_id)
    if setting_id == "miniaudioaddon_api_log" then
        if mod:get("miniaudioaddon_api_log") then
            Logging.announce_api_log_path()
        else
            mod:echo("[MiniAudioAddon] API log disabled.")
        end
    end
end
-- ============================================================================
-- Update Loop
-- ============================================================================
--[[
    Name:       mod.update
    Purpose:    Main update loop for the mod; handles daemon message flushing,
                keepalive checks, spatial test updates, and emitter marker updates.
    Args:       dt (number) - Delta time since the last update call.
    Returns:    None
]]
-- ============================================================================

mod.update = function(dt)
    if spatial_mode_enabled() then
        DaemonBridge.flush_pending_daemon_messages()
    end

    if mod._keepalive_flag and not (DaemonState and DaemonState.is_active and DaemonState.is_active()) then
        mod:ensure_daemon_keepalive()
    end

    if mod.api and mod.api.tracks_count and mod.set_client_active then
        local has_tracks = (mod.api.tracks_count() or 0) > 0
        mod:set_client_active(mod:get_name(), has_tracks)
    end

    if staged_payload_cleanups and #staged_payload_cleanups > 0 then
        local rt_now = Utils.realtime_now()
        local idx = 1
        while idx <= #staged_payload_cleanups do
            local entry = staged_payload_cleanups[idx]
            if entry.delete_after and entry.delete_after <= rt_now then
                local removed = true
                local pipe_payload = DaemonState and DaemonState.get_pipe_payload and DaemonState.get_pipe_payload()
                if entry.path and entry.path ~= pipe_payload and IOUtils and IOUtils.delete_file then
                    removed = IOUtils.delete_file(entry.path)
                end

                if removed then
                    table.remove(staged_payload_cleanups, idx)
                else
                    entry.delete_after = rt_now + 4.0
                    idx = idx + 1
                end
            else
                idx = idx + 1
            end
        end
    end

    if update_spatial_test then
        update_spatial_test(dt or 0.016)
    end

    if emitter_state and spatial_mode_enabled() and not emitter_state.pending_stop then
        local state = emitter_state
        local unit = state.unit
        local position
        local rotation

        if unit and Unit and Unit.alive and Unit.alive(unit) then
            local ok_pos, current_position = pcall(Unit.world_position, unit, 1)
            local ok_rot, current_rotation = pcall(Unit.world_rotation, unit, 1)
            if ok_pos and ok_rot and current_position and current_rotation then
                position = current_position
                rotation = current_rotation
                if Vector3Box then
                    if state.position_box then
                        state.position_box:store(position)
                    else
                        state.position_box = Vector3Box(position)
                    end
                else
                    state.position_box = position
                end
                if QuaternionBox then
                    if state.rotation_box then
                        state.rotation_box:store(rotation)
                    else
                        state.rotation_box = QuaternionBox(rotation)
                    end
                else
                    state.rotation_box = rotation
                end
            end
        else
            if unit then
                Sphere.destroy_unit(unit)
                state.unit = nil
            end

            if state.position_box then
                if Vector3Box and state.position_box.unbox then
                    position = state.position_box:unbox()
                else
                    position = state.position_box
                end
            end
            if state.rotation_box then
                if QuaternionBox and state.rotation_box.unbox then
                    rotation = state.rotation_box:unbox()
                else
                    rotation = state.rotation_box
                end
            end
        end

        if not position or not rotation then
            cleanup_emitter_state("[MiniAudioAddon] Emitter marker unavailable.", false)
        else
            local rt = Utils.realtime_now()
            if not state.pending_start and (not state.next_update or rt >= state.next_update) then
                local forward = Utils.safe_forward(rotation)
                daemon_send_update({
                    id = state.track_id,
                    source = {
                        position = Utils.vec3_to_array(position),
                        forward = Utils.vec3_to_array(forward),
                        velocity = { 0, 0, 0 },
                    },
                    listener = Utils.build_listener_payload(),
                })
                state.next_update = rt + Constants.MARKER_SETTINGS.update_interval
            end

            draw_emitter_marker(position, rotation)
        end
    end

    if USE_MINIAUDIO_DAEMON then
        local t_now = Utils.now()
        local rt_now = Utils.realtime_now()
        local watchdog_until = DaemonState and DaemonState.get_watchdog_until and DaemonState.get_watchdog_until() or 0
        local watchdog_next_attempt = DaemonState and DaemonState.get_watchdog_next_attempt and DaemonState.get_watchdog_next_attempt() or 0
        local stop_until = DaemonState and DaemonState.get_stop_reassert_until and DaemonState.get_stop_reassert_until() or 0
        local stop_last = DaemonState and DaemonState.get_stop_reassert_last and DaemonState.get_stop_reassert_last() or 0

        if watchdog_until > 0 and rt_now >= watchdog_until and DaemonState and DaemonState.set_watchdog_until then
            DaemonState.set_watchdog_until(0)
            watchdog_until = 0
        end

        if stop_until > 0 and rt_now < stop_until then
            if (rt_now - stop_last) >= 0.5 then
                daemon_write_control(0.0, 0.0, true, { force = true })
                if DaemonState and DaemonState.set_stop_reassert_last then
                    DaemonState.set_stop_reassert_last(rt_now)
                end
            end
        elseif stop_until > 0 and DaemonState and DaemonState.set_stop_reassert_until then
            DaemonState.set_stop_reassert_until(0)
            DaemonState.set_stop_reassert_last(0)
        end

        local daemon_running = DaemonState and DaemonState.is_running and DaemonState.is_running()
        if daemon_is_idle() and (daemon_running or watchdog_until > 0) then
            if watchdog_until == 0 then
                schedule_daemon_watchdog()
            elseif rt_now >= watchdog_until and watchdog_next_attempt <= rt_now then
                daemon_force_quit()
                if DaemonState and DaemonState.set_watchdog_next_attempt then
                    DaemonState.set_watchdog_next_attempt(rt_now + (Constants.DAEMON_WATCHDOG_COOLDOWN or 0))
                end
            end
        elseif watchdog_until > 0 then
            clear_daemon_watchdog()
        end

        local current_pid = DaemonState and DaemonState.get_pid and DaemonState.get_pid()
        local has_known = DaemonState and DaemonState.has_known_process and DaemonState.has_known_process()
        if current_pid and daemon_running and has_known and DLS and DLS.process_is_running then
            local next_poll = (DaemonState and DaemonState.get_next_status_poll and DaemonState.get_next_status_poll()) or 0
            if next_poll <= t_now then
                if DaemonState and DaemonState.set_next_status_poll then
                    DaemonState.set_next_status_poll(t_now + (Constants.DAEMON_STATUS_POLL_INTERVAL or 0))
                end
                local poll_generation = DaemonState.get_generation()
                local request = DLS.process_is_running(current_pid)

                if request then
                    request:next(function(response)
                        if poll_generation ~= DaemonState.get_generation() then
                            return
                        end

                        local body = response and response.body
                        if body and body.process_is_running == false then
                            local missing = ((DaemonState and DaemonState.get_missing_status_checks and DaemonState.get_missing_status_checks()) or 0) + 1
                            if DaemonState and DaemonState.set_missing_status_checks then
                                DaemonState.set_missing_status_checks(missing)
                            end
                            if missing >= 5 then
                                if daemon_is_idle() then
                                    if DaemonState and DaemonState.set_missing_status_checks then
                                        DaemonState.set_missing_status_checks(0)
                                    end
                                    daemon_force_quit()
                                else
                                    if DaemonState and DaemonState.set_missing_status_checks then
                                        DaemonState.set_missing_status_checks(5)
                                    end
                                end
                            end
                        else
                            if DaemonState and DaemonState.set_missing_status_checks then
                                DaemonState.set_missing_status_checks(0)
                            end
                        end
                    end):catch(function(error)
                        if poll_generation ~= DaemonState.get_generation() then
                            return
                        end

                        if debug_enabled() then
                            mod:echo("[MiniAudioAddon] Daemon status check failed: %s", tostring(error and error.body or error))
                        end
                    end)
                end
            end
        end
    end
end

return mod
