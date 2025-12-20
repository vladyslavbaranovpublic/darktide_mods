--[[
    File: core/daemon_lifecycle.lua
    Description: Daemon process lifecycle management for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local DaemonLifecycle = {}

-- Dependencies
local mod = nil
local DLS = nil
local Utils = nil
local IOUtils = nil
local DaemonBridge = nil
local DaemonState = nil
local DaemonPaths = nil
local ClientManager = nil
local Shell = nil
local Constants = nil

-- State for callbacks
local handle_daemon_stop_failure = nil
local manual_playback_clear = nil
local emitter_test_clear = nil
local spatial_test_clear = nil

-- Engine references
local daemon_popen = nil

function DaemonLifecycle.init(dependencies)
    mod = dependencies.mod
    DLS = dependencies.DLS
    Utils = dependencies.Utils
    IOUtils = dependencies.IOUtils
    DaemonBridge = dependencies.DaemonBridge
    DaemonState = dependencies.DaemonState
    DaemonPaths = dependencies.DaemonPaths
    ClientManager = dependencies.ClientManager
    Shell = dependencies.Shell
    Constants = dependencies.Constants
    handle_daemon_stop_failure = dependencies.handle_daemon_stop_failure
    manual_playback_clear = dependencies.manual_playback_clear
    emitter_test_clear = dependencies.emitter_test_clear
    spatial_test_clear = dependencies.spatial_test_clear
    
    daemon_popen = Utils and Utils.locate_popen and Utils.locate_popen()
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function debug_enabled()
    return mod and mod:get("miniaudioaddon_debug")
end

-- ============================================================================
-- WATCHDOG MANAGEMENT
-- ============================================================================

function DaemonLifecycle.schedule_watchdog()
    local window = Constants and Constants.DAEMON_WATCHDOG_WINDOW or 5.0
    DaemonState.set_watchdog_until(Utils.realtime_now() + window)
    DaemonState.set_watchdog_next_attempt(0)
end

function DaemonLifecycle.clear_watchdog()
    DaemonState.set_watchdog_until(0)
    DaemonState.set_watchdog_next_attempt(0)
end

function DaemonLifecycle.has_internal_activity(manual_active, manual_stop_pending, emitter_active, spatial_active)
    if manual_active or manual_stop_pending then
        return true
    end

    if emitter_active or spatial_active then
        return true
    end

    local pending = DaemonState.get_pending_messages()
    return pending and #pending > 0
end

function DaemonLifecycle.is_idle()
    -- Check if no clients are active and no internal activity
    local has_clients = ClientManager and ClientManager.has_any_clients()
    if has_clients then
        return false
    end
    
    -- Will need to check feature activity - for now return false if daemon running
    return not DaemonState.is_running()
end

-- ============================================================================
-- PROCESS MANAGEMENT
-- ============================================================================

function DaemonLifecycle.kill_process(pid)
    if not pid then
        return
    end

    if DLS and DLS.stop_process then
        pcall(DLS.stop_process, pid)
    end

    local numeric_pid = tonumber(pid) or pid
    if not numeric_pid then
        return
    end

    local taskkill_cmd = string.format('taskkill /T /F /PID %s >nul 2>&1', tostring(numeric_pid))
    if Shell and Shell.run_command(taskkill_cmd, "daemon taskkill", { prefer_local = true }) then
        return
    end

    local powershell_cmd = string.format([[powershell -NoLogo -NoProfile -Command "Stop-Process -Id %s -Force" ]], tostring(numeric_pid))
    if Shell then
        Shell.run_command(powershell_cmd, "daemon stop-process", { prefer_local = true, local_only = true })
    else
        pcall(os.execute, powershell_cmd)
    end
end

-- ============================================================================
-- DAEMON LOGGING
-- ============================================================================

function DaemonLifecycle.get_log_path()
    if not DaemonPaths or not DaemonPaths.ensure() then
        return nil
    end

    local exe_path = DaemonState.get_daemon_exe()
    local ctl_path = DaemonState.get_daemon_ctl()
    
    local base_dir = exe_path and IOUtils.directory_of(exe_path) or nil
    if not base_dir or base_dir == "" then
        base_dir = ctl_path and IOUtils.directory_of(ctl_path) or nil
    end
    if not base_dir or base_dir == "" then
        return nil
    end

    return IOUtils.ensure_trailing_separator(base_dir) .. "miniaudio_dt_log.txt"
end

function DaemonLifecycle.clear_log(reason)
    if mod and mod:get("miniaudioaddon_clear_logs") == false then
        return false
    end
    
    local path = DaemonLifecycle.get_log_path()
    if not path then
        return false
    end

    local ok = Utils.direct_write_file(path, "")
    if ok then
        if debug_enabled() and mod then
            mod:echo("[DaemonLifecycle] Cleared daemon log (%s).", tostring(reason or "unknown"))
        end
        return true
    end

    if debug_enabled() and mod then
        mod:echo("[DaemonLifecycle] Failed to clear daemon log (%s).", tostring(reason or "unknown"))
    end
    return false
end

-- ============================================================================
-- CONTROL FILE MANAGEMENT
-- ============================================================================

function DaemonLifecycle.write_control(volume_linear, pan, stop_flag, opts)
    if not DaemonPaths or not DaemonPaths.ensure() then
        if mod then
            mod:error("[DaemonLifecycle] write_control: cannot resolve daemon paths.")
        end
        return false
    end

    local ctl_path = DaemonState.get_daemon_ctl()
    local volume_percent, clamped_pan, clamped_volume = DaemonBridge.daemon_control_values(volume_linear, pan)
    volume_linear = clamped_volume
    local stop_int = stop_flag and 1 or 0
    opts = opts or {}

    -- Skip redundant writes
    local skip_write = false
    if not opts.force then
        local last_control = DaemonState.get_last_control()
        if last_control then
            local delta_pan = math.abs(last_control.pan - clamped_pan)
            local delta_volume = math.abs(last_control.volume - volume_linear)
            if delta_volume <= 0.001
                and last_control.stop == stop_int
                and delta_pan <= 0.0005 then

                skip_write = true
            end
        end
    end

    if skip_write then
        return true
    end

    local payload = string.format("volume=%.3f\r\npan=%.3f\r\nstop=%d\r\n", volume_linear, clamped_pan, stop_int)
    local ok = Utils.direct_write_file(ctl_path, payload)
    local fallback_cmd = nil

    if not ok then
        if debug_enabled() and mod then
            mod:echo("[DaemonLifecycle] Direct control file write failed; attempting via PowerShell.")
        end

        local escaped_path = ctl_path:gsub("'", "''")
        local cmd = string.format(
            [[powershell -NoLogo -NoProfile -Command "Set-Content -Path '%s' -Value @('volume=%.3f','pan=%.3f','stop=%d') -Encoding ASCII"]],
            escaped_path, volume_linear, clamped_pan, stop_int
        )

        ok = Shell and Shell.run_command(cmd, "daemon ctl write")
        fallback_cmd = cmd
    end

    if ok then
        DaemonState.set_last_control({
            volume = volume_linear,
            pan = clamped_pan,
            stop = stop_int,
        })
    end

    if ok and debug_enabled() and mod then
        if fallback_cmd then
            mod:echo("[DaemonLifecycle] write_control -> cmd: %s", fallback_cmd)
        else
            mod:echo("[DaemonLifecycle] write_control -> direct write to %s", tostring(ctl_path))
        end
    end

    return ok
end

-- ============================================================================
-- DAEMON RESET
-- ============================================================================

function DaemonLifecycle.reset(reason)
    if (DaemonState.is_running() or DaemonState.is_pending_start() or DaemonState.get_pid()) and debug_enabled() and mod then
        mod:echo("[DaemonLifecycle] Daemon status reset (%s).", tostring(reason))
    end

    -- Close stdio
    local state_ref = DaemonState.get_state_ref()
    if DaemonBridge then
        DaemonBridge.close_daemon_stdio(reason or "reset", state_ref)
    end
    
    -- Fail all pending messages
    local pending = DaemonState.get_pending_messages()
    if pending and #pending > 0 and handle_daemon_stop_failure then
        for _, entry in ipairs(pending) do
            handle_daemon_stop_failure(entry)
        end
    end

    -- Reset daemon state
    DaemonState.reset(reason)

    -- Clear feature states
    if manual_playback_clear then
        manual_playback_clear(reason)
    end
    
    if emitter_test_clear then
        emitter_test_clear(reason)
    end
    
    if spatial_test_clear then
        spatial_test_clear(reason)
    end

    -- Notify callbacks
    if ClientManager then
        ClientManager.notify_daemon_reset(reason)
    end
end

-- ============================================================================
-- DAEMON START
-- ============================================================================

function DaemonLifecycle.start(path, volume_linear, pan)
    if not DLS then
        if mod then
            mod:error("[DaemonLifecycle] Cannot start daemon; DLS missing.")
        end
        return false
    end

    if not DaemonPaths or not DaemonPaths.ensure() then
        local exe = DaemonState.get_daemon_exe()
        local ctl = DaemonState.get_daemon_ctl()
        if mod then
            mod:error(
                "[DaemonLifecycle] Cannot start daemon; failed to resolve exe/ctl (exe=%s, ctl=%s).",
                tostring(exe),
                tostring(ctl)
            )
        end
        return false
    end

    DaemonLifecycle.force_quit({ skip_stop_flag = true })

    local initial_volume, initial_pan = DaemonState.apply_manual_override(volume_linear or 1.0, pan or 0.0)
    local volume_percent, clamped_pan, clamped_initial_volume = DaemonBridge.daemon_control_values(initial_volume, initial_pan)
    initial_volume = clamped_initial_volume
    initial_pan = clamped_pan
    DaemonLifecycle.write_control(initial_volume, initial_pan, false)

    local requested_pipe_name = DaemonState.next_pipe_name()
    local pipe_arg = requested_pipe_name and string.format(' --pipe "%s"', requested_pipe_name) or ""

    local daemon_exe = DaemonState.get_daemon_exe()
    local daemon_ctl = DaemonState.get_daemon_ctl()
    local cmd_base = string.format('"%s" --daemon --log', daemon_exe)

    if debug_enabled() and mod then
        mod:echo("[DaemonLifecycle] start: path='%s'", tostring(path))
    end

    local has_autoplay_path = path and path ~= ""
    if has_autoplay_path then
        cmd_base = string.format('%s -i "%s"', cmd_base, path)
    else
        cmd_base = string.format('%s --no-autoplay', cmd_base)
    end

    local stdin_cmd = string.format('%s --stdin --ctl "%s"%s -volume %d',
        cmd_base, daemon_ctl, pipe_arg, volume_percent)
    local cmd = string.format('%s --ctl "%s"%s -volume %d',
        cmd_base, daemon_ctl, pipe_arg, volume_percent)

    stdin_cmd = IOUtils.wrap_daemon_command(stdin_cmd, daemon_exe)
    cmd = IOUtils.wrap_daemon_command(cmd, daemon_exe)

    DaemonLifecycle.clear_watchdog()

    if debug_enabled() and mod then
        mod:echo("[DaemonLifecycle] start cmd: %s", stdin_cmd)
    end

    DaemonState.set_stop_reassert_until(0)
    DaemonState.set_stop_reassert_last(0)

    -- Try stdin mode first
    if daemon_popen then
        local ok, handle_or_err = pcall(daemon_popen, stdin_cmd, "w")
        if ok and handle_or_err then
            DaemonState.set_stdio(handle_or_err)
            DaemonState.set_stdio_mode("stdin")
            DaemonState.set_running(true)
            DaemonState.set_pending_start(false)
            DaemonState.set_pipe_name(requested_pipe_name)
            DaemonState.set_pid(nil)
            DaemonState.set_has_known_process(false)
            DaemonState.set_next_status_poll(0)
            DaemonState.set_missing_status_checks(0)
            if debug_enabled() and mod then
                mod:echo("[DaemonLifecycle] Daemon running (stdin bridge).")
            end
            return true
        end

        if debug_enabled() and mod then
            mod:error("[DaemonLifecycle] Failed to start daemon via stdin bridge: %s", tostring(handle_or_err))
        end
    end

    -- Try DLS promise-based launch
    DaemonState.set_pending_start(true)
    local launch_generation = DaemonState.bump_generation("launch start")

    local ok, promise = pcall(DLS.run_command, cmd)
    if ok and promise then
        promise
        :next(function(response)
            if launch_generation ~= DaemonState.get_generation() then
                return
            end

            local payload = response and response.body
            local decoded, decode_err = Utils.decode_json_payload(payload)
            if decode_err then
                if mod then
                    mod:error("[DaemonLifecycle] Failed to decode daemon launch response (%s).", tostring(decode_err))
                end
                DaemonLifecycle.reset("launch decode failed")
                return
            end
            payload = decoded

            if type(payload) ~= "table" or payload.success ~= true then
                local reason = payload and payload.stderr or payload and payload.stdout or "unknown"
                if mod then
                    mod:error("[DaemonLifecycle] Daemon launch rejected (%s).", tostring(reason))
                end
                DaemonLifecycle.reset("launch rejected")
                return
            end

            if payload.pid == nil then
                if mod then
                    mod:error("[DaemonLifecycle] Daemon launch response missing PID.")
                end
                DaemonLifecycle.reset("launch missing pid")
                return
            end

            DaemonState.set_pid(tonumber(payload.pid) or payload.pid)
            DaemonState.set_running(true)
            DaemonState.set_pending_start(false)
            DaemonState.set_next_status_poll(0)
            DaemonState.set_has_known_process(DaemonState.get_pid() ~= nil)
            DaemonState.set_missing_status_checks(0)
            DaemonState.set_pipe_name(requested_pipe_name)

            if debug_enabled() and mod then
                mod:echo("[DaemonLifecycle] Daemon running (pid=%s).", tostring(DaemonState.get_pid()))
            end
        end)
        :catch(function(error)
            if launch_generation ~= DaemonState.get_generation() then
                return
            end

            local body = error and error.body
            if mod then
                mod:error("[DaemonLifecycle] Daemon launch request failed: %s", tostring(body or error))
            end
            DaemonLifecycle.reset("launch request failed")
        end)

        return true
    end

    if mod then
        mod:error("[DaemonLifecycle] Failed to start daemon via DLS: %s", tostring(promise))
    end
    DaemonState.set_pending_start(false)

    -- Fallback to shell command
    if Shell and Shell.run_command(cmd, "daemon fallback start") then
        DaemonState.set_running(true)
        DaemonState.set_pid(nil)
        DaemonState.set_has_known_process(false)
        DaemonState.set_next_status_poll(0)
        DaemonState.set_missing_status_checks(0)
        DaemonState.set_pipe_name(requested_pipe_name)

        if debug_enabled() and mod then
            mod:echo("[DaemonLifecycle] Daemon fallback launch succeeded (no PID tracking).")
        end

        return true
    end

    DaemonLifecycle.reset("launch failed")
    return false
end

-- ============================================================================
-- DAEMON STOP
-- ============================================================================

function DaemonLifecycle.stop()
    local had_running_daemon = DaemonState.is_running() or DaemonState.is_pending_start() or DaemonState.has_known_process()
    local should_push_stop = had_running_daemon or DaemonState.get_last_control() ~= nil
    local last_pid = DaemonState.get_pid()

    DaemonState.bump_generation("stop")
    DaemonLifecycle.reset("stop")
    DaemonState.set_stop_reassert_last(0)
    DaemonLifecycle.schedule_watchdog()

    DaemonState.clear_manual_override("stop")

    if should_push_stop then
        DaemonLifecycle.write_control(0.0, 0.0, true, { force = true })
        DaemonState.set_stop_reassert_until(Utils.realtime_now() + 3.0)
    else
        DaemonState.set_stop_reassert_until(0)
    end

    DaemonLifecycle.kill_process(last_pid)
end

-- ============================================================================
-- DAEMON UPDATE
-- ============================================================================

function DaemonLifecycle.update(volume_linear, pan)
    if not DaemonState.is_running() then
        return
    end

    local manual_override = DaemonState.get_manual_override()
    if manual_override then
        if debug_enabled() and mod then
            mod:echo("[DaemonLifecycle] update skipped due to manual override (vol=%.3f, pan=%.3f)",
                manual_override.volume or -1, manual_override.pan or -1)
        end
        return
    end

    volume_linear, pan = DaemonState.apply_manual_override(volume_linear, pan)
    DaemonLifecycle.write_control(volume_linear, pan, false)
end

-- ============================================================================
-- DAEMON MANUAL CONTROL
-- ============================================================================

function DaemonLifecycle.manual_control(volume_linear, pan)
    if not DaemonState.is_active() then
        return false, "not_running"
    end

    local last_control = DaemonState.get_last_control()
    local current_volume = last_control and last_control.volume or nil
    local current_pan = last_control and last_control.pan or 0.0
    local target_volume = volume_linear or current_volume or 1.0
    local target_pan = pan ~= nil and pan or current_pan

    -- Update manual override state
    local manual_override = DaemonState.get_manual_override() or {}
    if volume_linear ~= nil then
        manual_override.volume = target_volume
    end
    if pan ~= nil then
        manual_override.pan = target_pan
    end
    if manual_override.volume == nil and manual_override.pan == nil then
        manual_override = nil
    end
    DaemonState.set_manual_override(manual_override)

    -- Try pipe client method
    local pipe_ok = false
    local pipe_name = DaemonState.get_pipe_name()
    if pipe_name and DaemonBridge then
        pipe_ok = true
        if volume_linear ~= nil then
            pipe_ok = DaemonBridge.send_via_pipe_client(string.format("volume=%.3f", target_volume)) and pipe_ok
        end
        if pan ~= nil then
            pipe_ok = DaemonBridge.send_via_pipe_client(string.format("pan=%.3f", target_pan)) and pipe_ok
        end
    end

    -- Try control file method
    local file_ok = DaemonLifecycle.write_control(target_volume, target_pan, false, { force = true })
    local succeeded = file_ok or pipe_ok

    if not succeeded then
        return false, "write_failed"
    end

    if debug_enabled() and mod then
        mod:echo("[DaemonLifecycle] Manual override set: volume=%.3f, pan=%.3f",
            manual_override and manual_override.volume or -1,
            manual_override and manual_override.pan or -1)
    end

    return true
end

-- ============================================================================
-- DAEMON FORCE QUIT
-- ============================================================================

function DaemonLifecycle.force_quit(opts)
    local skip_stop_flag = opts and opts.skip_stop_flag
    local last_pid = DaemonState.get_pid()

    DaemonState.bump_generation("force_quit")
    DaemonLifecycle.reset("force_quit")
    DaemonState.set_stop_reassert_last(0)

    if not skip_stop_flag and DaemonState.is_active() then
        DaemonLifecycle.write_control(0.0, 0.0, true, { force = true })
        DaemonState.set_stop_reassert_until(Utils.realtime_now() + 3.0)
    else
        DaemonState.set_stop_reassert_until(0)
    end

    DaemonLifecycle.kill_process(last_pid)
    
    -- Purge payload files (if callback provided)
    -- This would need to be passed in dependencies or handled elsewhere
end

return DaemonLifecycle
