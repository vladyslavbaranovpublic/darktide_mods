--[[
    File: core/daemon_state.lua
    Description: Centralized daemon state management for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local DaemonState = {}

-- Daemon runtime state
local daemon_is_running = false
local daemon_pending_start = false
local daemon_pid = nil
local daemon_generation = 0
local daemon_has_known_process = false
local daemon_next_status_poll = 0
local daemon_missing_status_checks = 0
local daemon_last_control = nil
local daemon_manual_override = nil
local daemon_pipe_name = nil
local daemon_pending_messages = {}
local daemon_watchdog_until = 0
local daemon_watchdog_next_attempt = 0
local daemon_stop_reassert_until = 0
local daemon_stop_reassert_last = 0

-- Daemon stdio state
local daemon_stdio = nil
local daemon_stdio_mode = nil

-- Daemon paths
local MINIAUDIO_DAEMON_EXE = nil
local MINIAUDIO_DAEMON_CTL = nil
local MINIAUDIO_PIPE_PAYLOAD = nil
local MINIAUDIO_PIPE_DIRECTORY = nil

-- Dependencies
local Utils = nil
local debug_enabled = nil

-- Generation callback
local generation_callback = nil

function DaemonState.init(dependencies)
    Utils = dependencies.Utils
    debug_enabled = dependencies.debug_enabled
    generation_callback = dependencies.generation_callback
end

-- ============================================================================
-- PATH GETTERS/SETTERS
-- ============================================================================

function DaemonState.get_daemon_exe()
    return MINIAUDIO_DAEMON_EXE
end

function DaemonState.set_daemon_exe(path)
    MINIAUDIO_DAEMON_EXE = path
end

function DaemonState.get_daemon_ctl()
    return MINIAUDIO_DAEMON_CTL
end

function DaemonState.set_daemon_ctl(path)
    MINIAUDIO_DAEMON_CTL = path
end

function DaemonState.get_pipe_payload()
    return MINIAUDIO_PIPE_PAYLOAD
end

function DaemonState.set_pipe_payload(path)
    MINIAUDIO_PIPE_PAYLOAD = path
end

function DaemonState.get_pipe_directory()
    return MINIAUDIO_PIPE_DIRECTORY
end

function DaemonState.set_pipe_directory(path)
    MINIAUDIO_PIPE_DIRECTORY = path
end

-- ============================================================================
-- RUNTIME STATE GETTERS
-- ============================================================================

function DaemonState.is_running()
    return daemon_is_running
end

function DaemonState.is_pending_start()
    return daemon_pending_start
end

function DaemonState.get_pid()
    return daemon_pid
end

function DaemonState.get_generation()
    return daemon_generation
end

function DaemonState.has_known_process()
    return daemon_has_known_process
end

function DaemonState.get_next_status_poll()
    return daemon_next_status_poll
end

function DaemonState.get_missing_status_checks()
    return daemon_missing_status_checks
end

function DaemonState.get_last_control()
    return daemon_last_control
end

function DaemonState.get_manual_override()
    return daemon_manual_override
end

function DaemonState.get_pipe_name()
    return daemon_pipe_name
end

function DaemonState.get_pending_messages()
    return daemon_pending_messages
end

function DaemonState.get_watchdog_until()
    return daemon_watchdog_until
end

function DaemonState.get_watchdog_next_attempt()
    return daemon_watchdog_next_attempt
end

function DaemonState.get_stop_reassert_until()
    return daemon_stop_reassert_until
end

function DaemonState.get_stop_reassert_last()
    return daemon_stop_reassert_last
end

function DaemonState.get_stdio()
    return daemon_stdio
end

function DaemonState.get_stdio_mode()
    return daemon_stdio_mode
end

-- ============================================================================
-- STATE MUTATIONS
-- ============================================================================

function DaemonState.set_running(value)
    daemon_is_running = value
end

function DaemonState.set_pending_start(value)
    daemon_pending_start = value
end

function DaemonState.set_pid(value)
    daemon_pid = value
end

function DaemonState.set_has_known_process(value)
    daemon_has_known_process = value
end

function DaemonState.set_next_status_poll(value)
    daemon_next_status_poll = value
end

function DaemonState.set_missing_status_checks(value)
    daemon_missing_status_checks = value
end

function DaemonState.set_last_control(value)
    daemon_last_control = value
end

function DaemonState.set_manual_override(value)
    daemon_manual_override = value
end

function DaemonState.set_pipe_name(value)
    daemon_pipe_name = value
end

function DaemonState.set_watchdog_until(value)
    daemon_watchdog_until = value
end

function DaemonState.set_watchdog_next_attempt(value)
    daemon_watchdog_next_attempt = value
end

function DaemonState.set_stop_reassert_until(value)
    daemon_stop_reassert_until = value
end

function DaemonState.set_stop_reassert_last(value)
    daemon_stop_reassert_last = value
end

function DaemonState.set_stdio(value)
    daemon_stdio = value
end

function DaemonState.set_stdio_mode(value)
    daemon_stdio_mode = value
end

function DaemonState.add_pending_message(message)
    daemon_pending_messages[#daemon_pending_messages + 1] = message
end

function DaemonState.clear_pending_messages()
    daemon_pending_messages = {}
end

-- ============================================================================
-- HIGH-LEVEL OPERATIONS
-- ============================================================================

function DaemonState.is_active()
    return daemon_is_running or daemon_pending_start or daemon_has_known_process
end

function DaemonState.bump_generation(reason)
    daemon_generation = daemon_generation + 1
    
    if generation_callback then
        local ok, err = pcall(generation_callback, daemon_generation, reason or "generation bump")
        if not ok and debug_enabled and debug_enabled() then
            local mod = get_mod("MiniAudioAddon")
            if mod then
                mod:error("[DaemonState] generation callback failed: %s", tostring(err))
            end
        end
    end
    
    return daemon_generation
end

function DaemonState.clear_manual_override(reason)
    if not daemon_manual_override then
        return
    end

    if reason and debug_enabled and debug_enabled() then
        local mod = get_mod("MiniAudioAddon")
        if mod then
            mod:echo("[DaemonState] Manual daemon override cleared (%s).", tostring(reason))
        end
    end

    daemon_manual_override = nil
end

function DaemonState.apply_manual_override(volume_linear, pan)
    if not daemon_manual_override then
        return volume_linear, pan
    end

    if daemon_manual_override.volume ~= nil then
        volume_linear = daemon_manual_override.volume
    end
    if daemon_manual_override.pan ~= nil then
        pan = daemon_manual_override.pan
    end

    return volume_linear, pan
end

function DaemonState.next_pipe_name()
    local timestamp = os.time() or 0
    local random_part = math.random(10000, 99999)
    return string.format("miniaudio_dt_%d_%d", timestamp, random_part)
end

function DaemonState.reset(reason)
    if (daemon_is_running or daemon_pending_start or daemon_pid) and debug_enabled and debug_enabled() then
        local mod = get_mod("MiniAudioAddon")
        if mod then
            mod:echo("[DaemonState] Daemon status reset (%s).", tostring(reason))
        end
    end

    -- Fail all pending messages
    if daemon_pending_messages and #daemon_pending_messages > 0 then
        -- Note: Failure handling should be done by caller who has handle_daemon_stop_failure callback
        -- We just clear the list here
        daemon_pending_messages = {}
    end

    daemon_is_running = false
    daemon_pending_start = false
    daemon_pid = nil
    daemon_next_status_poll = 0
    daemon_has_known_process = false
    daemon_last_control = nil
    daemon_pipe_name = nil
    daemon_missing_status_checks = 0
    daemon_pending_messages = {}
    daemon_stdio = nil
    daemon_stdio_mode = nil
end

-- ============================================================================
-- STATE REFERENCE TABLE (for backward compatibility with daemon_bridge)
-- ============================================================================

function DaemonState.get_state_ref()
    return {
        daemon_stdio = daemon_stdio,
        daemon_stdio_mode = daemon_stdio_mode,
    }
end

return DaemonState
