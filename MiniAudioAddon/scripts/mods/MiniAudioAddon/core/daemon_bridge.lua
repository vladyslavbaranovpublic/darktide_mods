--[[
    File: core/daemon_bridge.lua
    Description: Daemon communication and payload management for MiniAudioAddon.
    Overall Release Version: 1.0.2
    File Version: 1.0.2
]]
local mod = get_mod("MiniAudioAddon")

local Bridge = {}

-- Load PayloadBuilder
local PayloadBuilder = mod:io_dofile("MiniAudioAddon/scripts/mods/MiniAudioAddon/core/payload_builder")

-- Module-level state (initialized via init_state)
local Utils = nil
local get_daemon_stdio = nil
local set_daemon_stdio = nil
local get_daemon_pipe_name = nil
local get_daemon_pending_messages = nil
local get_daemon_is_running = nil
local get_daemon_has_known_process = nil
local get_daemon_exe = nil
local MIN_TRANSPORT_SPEED = nil
local MAX_TRANSPORT_SPEED = nil
local PIPE_RETRY_DELAY = nil
local PIPE_RETRY_MAX_ATTEMPTS = nil
local PIPE_RETRY_GRACE = nil

-- Direct dependencies (eliminates circular dependencies)
local DaemonState = nil
local DaemonPaths = nil
local Shell = nil
local AudioProfiles = nil
local DaemonLifecycle = nil

-- Event handler callbacks (keep these 6)
local write_api_log = nil
local log_last_play_payload = nil
local handle_daemon_payload_delivery = nil
local handle_daemon_stop_delivery = nil
local handle_daemon_play_failure = nil
local handle_daemon_stop_failure = nil

-- For debug testing
local function debug_enabled()
    return mod and mod:get("miniaudioaddon_debug")
end

local function verbose_debug_enabled()
    -- If there isn't a dedicated verbose toggle, reuse the main debug flag
    if mod and mod.get and mod:get("miniaudioaddon_debug_verbose") ~= nil then
        return mod:get("miniaudioaddon_debug_verbose")
    end
    return debug_enabled()
end

function Bridge.init_state(state)
    Utils = state.Utils
    get_daemon_stdio = state.get_daemon_stdio
    set_daemon_stdio = state.set_daemon_stdio
    get_daemon_pipe_name = state.get_daemon_pipe_name
    get_daemon_pending_messages = state.get_daemon_pending_messages
    get_daemon_is_running = state.get_daemon_is_running
    get_daemon_has_known_process = state.get_daemon_has_known_process
    get_daemon_exe = state.get_daemon_exe
    MIN_TRANSPORT_SPEED = state.MIN_TRANSPORT_SPEED
    MAX_TRANSPORT_SPEED = state.MAX_TRANSPORT_SPEED
    PIPE_RETRY_DELAY = state.PIPE_RETRY_DELAY
    PIPE_RETRY_MAX_ATTEMPTS = state.PIPE_RETRY_MAX_ATTEMPTS
    PIPE_RETRY_GRACE = state.PIPE_RETRY_GRACE
end

function Bridge.init_dependencies(dependencies)
    -- Direct module dependencies (eliminates circular dependencies)
    DaemonState = dependencies.DaemonState
    DaemonPaths = dependencies.DaemonPaths
    Shell = dependencies.Shell
    AudioProfiles = dependencies.AudioProfiles
    DaemonLifecycle = dependencies.DaemonLifecycle
end

function Bridge.init_callbacks(callbacks)
    -- Event handler callbacks only (no circular dependencies)
    write_api_log = callbacks.write_api_log
    log_last_play_payload = callbacks.log_last_play_payload
    handle_daemon_payload_delivery = callbacks.handle_daemon_payload_delivery
    handle_daemon_stop_delivery = callbacks.handle_daemon_stop_delivery
    handle_daemon_play_failure = callbacks.handle_daemon_play_failure
    handle_daemon_stop_failure = callbacks.handle_daemon_stop_failure
    
    -- Initialize PayloadBuilder with DaemonBridge functions
    if PayloadBuilder and PayloadBuilder.init then
        PayloadBuilder.init({
            daemon_track_profile = Bridge.daemon_track_profile,
            daemon_spatial_effects = Bridge.daemon_spatial_effects,
            apply_transport_fields = Bridge.apply_transport_fields,
        })
    end
end

-- Daemon communication functions

function Bridge.daemon_control_values(volume_linear, pan)
    local clamped_volume = math.max(0.0, math.min(volume_linear or 1.0, 3.0))
    local clamped_pan = math.max(-1.0, math.min(pan or 0.0, 1.0))
    return math.floor(clamped_volume * 100 + 0.5), clamped_pan, clamped_volume
end

function Bridge.close_daemon_stdio(reason, state_ref)
    if debug_enabled() then
        mod:echo("[MiniAudioAddon][daemon_bridge.lua][Bridge.close_daemon_stdio] Closing daemon stdio (%s).", tostring(reason or "unknown"))
    end
    local stdio = state_ref and state_ref.daemon_stdio or (get_daemon_stdio and get_daemon_stdio())
    if not stdio then
        return
    end

    local ok, err = pcall(function()
        if stdio.flush then
            stdio:flush()
        end
        if stdio.close then
            stdio:close()
        end
    end)

    if mod and mod:get("miniaudioaddon_debug") then
        if ok then
            mod:echo("[MiniAudioAddon] Closed daemon stdin (%s).", tostring(reason or "unknown"))
        else
            mod:error("[MiniAudioAddon] Failed to close daemon stdin (%s): %s", tostring(reason), tostring(err))
        end
    end

    if state_ref then
        state_ref.daemon_stdio = nil
        state_ref.daemon_stdio_mode = nil
    elseif set_daemon_stdio then
        set_daemon_stdio(nil)
    end
end

function Bridge.send_via_stdin(encoded, state_ref)
    if verbose_debug_enabled() then
        mod:echo("[MiniAudioAddon][daemon_bridge.lua] Sending payload via stdin pipe.")
    end
    local stdio = state_ref and state_ref.daemon_stdio or (get_daemon_stdio and get_daemon_stdio())
    if not stdio then
        return false
    end

    local line = encoded
    if type(line) ~= "string" or line == "" then
        return false
    end

    if line:sub(-1) ~= "\n" then
        line = line .. "\n"
    end

    local ok, err = pcall(function()
        stdio:write(line)
        if stdio.flush then
            stdio:flush()
        end
    end)

    if not ok then
        if debug_enabled() then
            mod:error("[MiniAudioAddon] Failed to write to daemon stdin: %s", tostring(err))
        end
        Bridge.close_daemon_stdio("stdin_write_failed", state_ref)
        return false
    end

    return true
end

function Bridge.send_via_pipe_client(payload)
    local pipe_name = get_daemon_pipe_name and get_daemon_pipe_name()
    if not pipe_name or not payload or payload == "" then
        return false
    end

    if not DaemonPaths or not DaemonPaths.ensure() then
        if mod then
            mod:error("[MiniAudioAddon] Pipe write requested before daemon paths resolved.")
        end
        return false
    end

    local daemon_exe = get_daemon_exe and get_daemon_exe()
    if not daemon_exe or daemon_exe == "" then
        if mod then
            mod:error("[MiniAudioAddon] Pipe write requested before daemon executable known.")
        end
        return false
    end

    local payload_block = Utils and Utils.sanitize_for_format(payload) or payload
    local exe_path_ps = Utils and Utils.sanitize_for_ps_single(daemon_exe) or daemon_exe
    local pipe_ps = Utils and Utils.sanitize_for_ps_single(pipe_name) or pipe_name

    local command = string.format(
        [[powershell -NoLogo -NoProfile -Command "& { $payload = @'
%s
'@; & '%s' --pipe-client --pipe '%s' --payload $payload }"]],
        payload_block,
        exe_path_ps,
        pipe_ps
    )

    local succeeded = Shell and Shell.run_command(command, "daemon pipe client", { prefer_local = true })
    if not succeeded and debug_enabled() then
        if mod then
            mod:error("[MiniAudioAddon] Pipe client invocation failed.")
        end
    end

    return succeeded or false
end

function Bridge.deliver_daemon_payload(encoded, state_ref)
    if verbose_debug_enabled() then
        mod:echo("[MiniAudioAddon][daemon_bridge.lua][Bridge.deliver_daemon_payload] Entered function.");
    end
    if Bridge.send_via_stdin(encoded, state_ref) then
        return true
    end

    return Bridge.send_via_pipe_client(encoded)
end

function Bridge.daemon_send_json(payload)
    if verbose_debug_enabled() then
        mod:echo("[MiniAudioAddon][daemon_bridge.lua][Bridge.daemon_send_json] Entered function.");
    end
    if not payload then
        if write_api_log then write_api_log("SKIP: missing payload") end
        return false, "missing_payload"
    end

    if not mod or not mod:get("miniaudioaddon_spatial_mode") then
        if write_api_log then write_api_log("SKIP cmd=%s id=%s reason=spatial_disabled", tostring(payload.cmd), tostring(payload.id)) end
        return false, "spatial_disabled"
    end

    local daemon_ready = (DaemonState and DaemonState.is_active()) or (get_daemon_is_running and get_daemon_is_running())
    if not daemon_ready then
        if payload.cmd == "play" then
            if write_api_log then write_api_log("Daemon offline; attempting start for cmd=%s id=%s", tostring(payload.cmd), tostring(payload.id)) end
            if DaemonLifecycle and DaemonLifecycle.start then
                if verbose_debug_enabled() then
                    mod:echo("[MiniAudioAddon][daemon_bridge.lua][Bridge.daemon_send_json] Attempt to start the daemon via the lifecycle manager.");
                end
                local started = false
                local ok = pcall(function()
                    started = DaemonLifecycle.start(payload.path)
                end)
                if not ok or not started then
                    if write_api_log then write_api_log("FAILED start cmd=%s id=%s reason=daemon_unavailable", tostring(payload.cmd), tostring(payload.id)) end
                    return false, "daemon_unavailable"
                end
                        daemon_ready = (DaemonState and DaemonState.is_active()) or (get_daemon_is_running and get_daemon_is_running())
                    else
                if write_api_log then write_api_log("FAILED start cmd=%s id=%s reason=no_daemon_lifecycle", tostring(payload.cmd), tostring(payload.id)) end
                return false, "daemon_unavailable"
            end
        else
            if verbose_debug_enabled() then
                mod:echo("[MiniAudioAddon][daemon_bridge.lua][Bridge.daemon_send_json] Attempt to start the daemon via the lifecycle manager.");
            end
            if write_api_log then write_api_log("SKIP cmd=%s id=%s reason=daemon_offline", tostring(payload.cmd), tostring(payload.id)) end
            if debug_enabled() then
                mod:echo("[MiniAudioAddon][daemon_bridge.lua][Bridge.daemon_send_json] Ignoring cmd=%s (daemon offline).", tostring(payload.cmd))
            end
            return false, "daemon_offline"
        end
    end

    local ok, encoded, encode_err
    if not Utils or not Utils.encode_json_payload then
        ok, encoded, encode_err = false, nil, "no_utils"
    else
        ok, encoded, encode_err = Utils.encode_json_payload(payload)
    end
    
    if not ok or not encoded then
        if write_api_log then write_api_log("ENCODE_FAIL cmd=%s id=%s reason=%s", tostring(payload.cmd), tostring(payload.id), tostring(encode_err)) end
        if debug_enabled() then
            mod:error("[MiniAudioAddon] Failed to encode daemon payload (cmd=%s id=%s): %s",
                tostring(payload.cmd), tostring(payload.id), tostring(encode_err or "unknown"))
        end
        return false, encode_err or "encode_failed"
    end

    if encode_err and debug_enabled() then
        mod:echo("[MiniAudioAddon] JSON encode fallback triggered for cmd=%s (%s)",
            tostring(payload.cmd), tostring(encode_err))
    end

    if write_api_log then write_api_log("SEND cmd=%s id=%s payload=%s", tostring(payload.cmd), tostring(payload.id), encoded) end
    if debug_enabled() then
        mod:echo("[MiniAudioAddon] Daemon send cmd=%s id=%s", tostring(payload.cmd), tostring(payload.id))
    end

    if payload.cmd == "play" and log_last_play_payload then
        log_last_play_payload(encoded)
    end

    if Bridge.deliver_daemon_payload(encoded) then
        if write_api_log then write_api_log("DELIVERED cmd=%s id=%s immediate", tostring(payload.cmd), tostring(payload.id)) end
        if handle_daemon_payload_delivery then handle_daemon_payload_delivery(payload) end
        if payload.cmd == "stop" and handle_daemon_stop_delivery then
            handle_daemon_stop_delivery(payload)
        end
        return true, false
    end

    local daemon_pending_messages = get_daemon_pending_messages and get_daemon_pending_messages()
    if daemon_pending_messages and Utils then
        daemon_pending_messages[#daemon_pending_messages + 1] = {
            encoded = encoded,
            attempts = 1,
            created = Utils.realtime_now(),
            next_attempt = Utils.realtime_now() + (PIPE_RETRY_DELAY or 0.05),
            cmd = payload.cmd,
            id = payload.id,
            payload = payload,
        }

        if write_api_log then write_api_log("QUEUED cmd=%s id=%s attempts=%d", tostring(payload.cmd), tostring(payload.id), 1) end
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Daemon send deferred (cmd=%s id=%s); waiting for IPC.", tostring(payload.cmd), tostring(payload.id))
        end
    end

    return true, true
end

function Bridge.flush_pending_daemon_messages()
    if not mod or not mod:get("miniaudioaddon_spatial_mode") then
        return
    end

    local daemon_pending_messages = get_daemon_pending_messages and get_daemon_pending_messages()
    if not daemon_pending_messages or not Utils then
        return
    end

    local idx = 1
    while idx <= #daemon_pending_messages do
        local entry = daemon_pending_messages[idx]
        local rt_now = Utils.realtime_now()
        if entry.next_attempt and rt_now < entry.next_attempt then
            idx = idx + 1
        elseif Bridge.deliver_daemon_payload(entry.encoded) then
            if handle_daemon_payload_delivery then handle_daemon_payload_delivery(entry.payload or entry) end
            if (entry.payload or entry).cmd == "stop" and handle_daemon_stop_delivery then
                handle_daemon_stop_delivery(entry.payload or entry)
            end
            table.remove(daemon_pending_messages, idx)
            if write_api_log then write_api_log("RETRY_DELIVERED cmd=%s id=%s attempts=%d", tostring(entry.cmd), tostring(entry.id), entry.attempts) end
        else
            entry.attempts = entry.attempts + 1
            entry.next_attempt = rt_now + (PIPE_RETRY_DELAY or 0.05)

            local attempts_exceeded = entry.attempts > (PIPE_RETRY_MAX_ATTEMPTS or 60)
            local grace_expired = entry.created and (rt_now - entry.created) > (PIPE_RETRY_GRACE or 4.0)
            local daemon_ready = (get_daemon_is_running and get_daemon_is_running()) or (get_daemon_has_known_process and get_daemon_has_known_process())

            if attempts_exceeded and (daemon_ready or grace_expired) then
                local payload_entry = entry.payload or entry
                if payload_entry.cmd == "play" and handle_daemon_play_failure then
                    handle_daemon_play_failure(payload_entry)
                elseif payload_entry.cmd == "stop" and handle_daemon_stop_failure then
                    handle_daemon_stop_failure(payload_entry)
                end
                table.remove(daemon_pending_messages, idx)
                if write_api_log then write_api_log("RETRY_FAILED cmd=%s id=%s attempts=%d reason=timeout", tostring(entry.cmd), tostring(entry.id), entry.attempts) end
            else
                idx = idx + 1
            end
        end
    end
end

function Bridge.daemon_track_profile(profile)
    profile = profile or {}
    local defaults = AudioProfiles and AudioProfiles.MEDIUM_RANGE or {}
    return {
        min_distance = profile.min_distance or defaults.min_distance,
        max_distance = profile.max_distance or defaults.max_distance,
        rolloff = profile.rolloff or defaults.rolloff,
    }
end

function Bridge.daemon_spatial_effects(overrides)
    overrides = overrides or {}
    local effects = {}
    if overrides.occlusion ~= nil then
        effects.occlusion = Utils and Utils.clamp(overrides.occlusion, 0, 1) or overrides.occlusion
    else
        effects.occlusion = mod and mod:get("miniaudioaddon_spatial_occlusion") or 0
    end

    if overrides.pan_override ~= nil then
        effects.pan_override = Utils and Utils.clamp(overrides.pan_override, -1, 1) or overrides.pan_override
    end

    if overrides.doppler ~= nil then
        effects.doppler = math.max(0, overrides.doppler)
    end

    if overrides.directional_attenuation ~= nil then
        effects.directional_attenuation = Utils and Utils.clamp(overrides.directional_attenuation, 0, 1) or overrides.directional_attenuation
    end

    if overrides.cone then
        effects.cone = {
            inner = Utils and Utils.clamp(overrides.cone.inner or 360, 0, 360) or (overrides.cone.inner or 360),
            outer = Utils and Utils.clamp(overrides.cone.outer or overrides.cone.inner or 360, 0, 360) or (overrides.cone.outer or overrides.cone.inner or 360),
            outer_gain = Utils and Utils.clamp(overrides.cone.outer_gain or 0, 0, 1) or (overrides.cone.outer_gain or 0),
        }
    end

    return effects
end

function Bridge.apply_transport_fields(payload, track)
    if not payload or not track then
        return
    end

    if track.process_id then
        payload.process_id = track.process_id
    end

    local start_seconds = tonumber(track.start_seconds)
    if start_seconds and start_seconds >= 0 then
        payload.start_seconds = start_seconds
    end

    local seek_seconds = tonumber(track.seek_seconds)
    if seek_seconds then
        payload.seek_seconds = seek_seconds
    end

    local skip_seconds = tonumber(track.skip_seconds)
    if skip_seconds then
        payload.skip_seconds = skip_seconds
    end

    local speed = tonumber(track.speed)
    if speed and Utils then
        payload.speed = Utils.clamp(speed, MIN_TRANSPORT_SPEED or 0.125, MAX_TRANSPORT_SPEED or 4.0)
    elseif speed then
        payload.speed = speed
    end

    if track.reverse ~= nil then
        payload.reverse = track.reverse and true or false
    end

    if track.autoplay ~= nil then
        payload.autoplay = track.autoplay and true or false
    end
end

-- Bridge API methods - use PayloadBuilder for all payload construction

function Bridge.play(track)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_play(track)
    return Bridge.daemon_send_json(payload)
end

function Bridge.update(track)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_update(track)
    return Bridge.daemon_send_json(payload)
end

function Bridge.stop(track_id, fade)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_stop(track_id, fade)
    return Bridge.daemon_send_json(payload)
end

function Bridge.pause(track_id)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_pause(track_id)
    return Bridge.daemon_send_json(payload)
end

function Bridge.resume(track_id)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_resume(track_id)
    return Bridge.daemon_send_json(payload)
end

function Bridge.seek(track_id, seconds)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_seek(track_id, seconds)
    return Bridge.daemon_send_json(payload)
end

function Bridge.skip(track_id, seconds)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_skip(track_id, seconds)
    return Bridge.daemon_send_json(payload)
end

function Bridge.speed(track_id, speed)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_speed(track_id, speed)
    return Bridge.daemon_send_json(payload)
end

function Bridge.reverse(track_id, enabled)
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_reverse(track_id, enabled)
    return Bridge.daemon_send_json(payload)
end

function Bridge.shutdown()
    if not PayloadBuilder then
        return false, "payload_builder_unavailable"
    end
    local payload = PayloadBuilder.build_shutdown()
    return Bridge.daemon_send_json(payload)
end

--[[
    High-level wrapper: Create a spatial audio emitter with all setup in one call
    
    Args:
        config: {
            id_prefix = string,           -- Prefix for generated track ID (e.g., "orb1", "ambient")
            path = string,                -- Audio file path (use MiniAudio.expand_track_path first)
            position = Vector3,           -- World position for the emitter
            forward = Vector3,            -- Optional: Forward direction (defaults to Quaternion.forward(rotation))
            rotation = Quaternion,        -- Optional: Rotation (used if forward not provided)
            tracker_offset = table,       -- Optional: {x_offset, y_offset, z_offset} for tracker
            profile = table,              -- Audio profile: {min_distance, max_distance, rolloff}
            loop = boolean,               -- Optional: Loop audio (default: true)
            volume = number,              -- Optional: Volume 0.0-1.0 (default: 1.0)
            autoplay = boolean,           -- Optional: Start playing immediately (default: true)
            require_listener = boolean,   -- Optional: Require listener updates (default: false)
            process_id = string,          -- Optional: Process identifier for tracking
        }
        Utils = table,                    -- MiniAudioUtils module
        PoseTrackerModule = table,        -- PoseTracker module
    
    Returns:
        success (boolean), tracker (PoseTracker), track_id (string), error_message (string)
]]
function Bridge.create_spatial_emitter(config, Utils, PoseTrackerModule)
    -- Validate required parameters
    if not config.path or not config.position then
        return false, nil, nil, "Missing required parameters: path and position"
    end
    
    if not Utils or not PoseTrackerModule then
        return false, nil, nil, "Missing required modules: Utils and PoseTrackerModule"
    end
    
    -- Create tracker with optional offset
    local tracker
    if config.tracker_offset then
        tracker = PoseTrackerModule.new(config.tracker_offset)
    else
        tracker = PoseTrackerModule.new()
    end
    
    -- Set tracker position
    if not tracker:set_manual(config.position, config.forward, config.rotation) then
        return false, nil, nil, "Failed to set tracker position"
    end
    
    -- Get listener context
    local listener_ctx = Utils.get_listener_context()
    if not listener_ctx then
        return false, nil, nil, "Failed to get listener context"
    end
    
    -- Get source payload from tracker
    local source = tracker:source_payload()
    if not source then
        return false, nil, nil, "Failed to get source payload from tracker"
    end
    
    -- Generate unique track ID
    local track_id = Utils.generate_track_id(config.id_prefix or "spatial")
    
    -- Build payload
    local payload = {
        id = track_id,
        path = config.path,
        loop = config.loop ~= false,  -- Default true
        volume = config.volume or 1.0,
        profile = config.profile or {},
        source = source,
        listener = listener_ctx.listener,
        autoplay = config.autoplay ~= false,  -- Default true
        require_listener = config.require_listener or false,
        process_id = config.process_id,
    }
    
    -- Call daemon_send_play
    local ok, result, detail = Bridge.play(payload)
    if not ok then
        return false, nil, nil, detail or "play failed"
    end
    
    return true, tracker, track_id, nil
end

--[[
    High-level wrapper: Update spatial audio emitter position and listener
    
    Args:
        config: {
            id = string,                  -- Track ID from create_spatial_emitter
            tracker = PoseTracker,        -- PoseTracker instance
            profile = table,              -- Optional: Audio profile {min_distance, max_distance, rolloff}
            volume = number,              -- Optional: Volume 0.0-1.0 (default: 1.0)
            loop = boolean,               -- Optional: Maintain loop state (default: true)
        }
        Utils = table,                    -- MiniAudioUtils module
    
    Returns:
        success (boolean), error_message (string)
]]
function Bridge.update_spatial_audio(config, Utils)
    -- Validate required parameters
    if not config.id or not config.tracker then
        return false, "Missing required parameters: id and tracker"
    end
    
    if not Utils then
        return false, "Missing required module: Utils"
    end
    
    -- Get listener context
    local listener_ctx = Utils.get_listener_context()
    if not listener_ctx then
        return false, "Failed to get listener context"
    end
    
    -- Get source payload from tracker
    local source = config.tracker:source_payload()
    if not source then
        return false, "Failed to get source payload from tracker"
    end
    
    -- Build update payload
    local payload = {
        id = config.id,
        source = source,
        listener = listener_ctx.listener,
        volume = config.volume or 1.0,
        loop = config.loop ~= false,  -- Default true
        profile = config.profile or {},
    }
    
    -- Call daemon_send_update
    local ok, result, detail = Bridge.update(payload)
    if not ok then
        return false, detail or "update failed"
    end
    
    return true, nil
end

--[[
    High-level wrapper: Stop spatial audio emitter with fade
    
    Args:
        config: {
            id = string,                  -- Track ID to stop
            fade = number,                -- Optional: Fade out duration in seconds (default: 0)
        }
    
    Returns:
        success (boolean), error_message (string)
]]
function Bridge.stop_spatial_emitter(config)
    -- Validate required parameters
    if not config or not config.id then
        return false, "Missing required parameter: id"
    end
    
    -- Call daemon_send_stop
    local ok, result, detail = Bridge.stop(config.id, config.fade or 0)
    if not ok then
        return false, detail or "stop failed"
    end
    
    return true, nil
end

return Bridge
