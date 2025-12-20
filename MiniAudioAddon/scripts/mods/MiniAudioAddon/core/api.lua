--[[
    File: core/api.lua
    Description: API helpers for MiniAudioAddon, providing a safe interface
    into MiniAudio-compatible source payloads for emitters.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
]]

return function(mod, Utils, main)
    if not mod or not main then
        return nil
    end

    local DaemonBridge = main.DaemonBridge
    local logger = main.logger

    local clamp = Utils and Utils.clamp or function(v, min, max) return math.max(min, math.min(max, v)) end
    local now = main.now or os.clock
    local realtime_now = main.realtime_now or os.clock
    local spatial_mode_enabled = main.spatial_mode_enabled
    local daemon_is_active = main.daemon_is_active
    local ensure_daemon_ready = main.ensure_daemon_ready
    local MIN_TRANSPORT_SPEED = main.MIN_TRANSPORT_SPEED or 0.125
    local MAX_TRANSPORT_SPEED = main.MAX_TRANSPORT_SPEED or 4.0
    local tracks = {}
    local process_index = {}
    local logging_enabled = false

    local function log(fmt, ...)
        if logger then
            local ok, err = pcall(logger, fmt, ...)
            if not ok and mod and mod.error then
                mod:error("[MiniAudioAPI] Log failure: %s", tostring(err))
            end
        end

        if not logging_enabled then
            return
        end

        if mod and mod.echo and fmt then
            local message = string.format(fmt, ...)
            mod:echo(string.format("[MiniAudioAPI] %s", message))
        end
    end

    local function next_track_id()
        local stamp = math.floor(realtime_now() * 1000)
        local rand = math.random(1000, 9999)
        return string.format("mini_track_%d_%04d", stamp, rand)
    end

    local function bind_process(entry, process_id)
        if not process_id then
            return
        end

        process_index[process_id] = process_index[process_id] or {}
        process_index[process_id][entry.id] = true
        entry.process_id = process_id
    end

    local function touch_entry(entry, state)
        if not entry then
            return
        end
        entry.updated = realtime_now()
        if state then
            entry.state = state
        end
    end

    local function create_or_update_entry(payload, state)
        local entry = tracks[payload.id] or { id = payload.id }
        entry.path = payload.path or entry.path
        entry.loop = payload.loop ~= false
        entry.volume = payload.volume or entry.volume or 1.0
        entry.profile = Utils.deepcopy(payload.profile) or entry.profile
        entry.source = Utils.deepcopy(payload.source) or entry.source
        entry.effects = Utils.deepcopy(payload.effects) or entry.effects
        entry.speed = payload.speed or entry.speed or 1.0
        entry.reverse = payload.reverse or entry.reverse or false
        entry.listener = Utils.deepcopy(payload.listener) or entry.listener
        entry.start_seconds = payload.start_seconds or entry.start_seconds
        entry.seek_seconds = payload.seek_seconds
        entry.skip_seconds = payload.skip_seconds
        entry.autoplay = payload.autoplay
        entry.state = state or entry.state or "pending"
        entry.created = entry.created or realtime_now()
        touch_entry(entry)
        tracks[payload.id] = entry
        bind_process(entry, payload.process_id)
        return entry
    end

    local function remove_entry(id)
        local entry = tracks[id]
        if not entry then
            return
        end

        if entry.process_id and process_index[entry.process_id] then
            process_index[entry.process_id][id] = nil
            if not next(process_index[entry.process_id]) then
                process_index[entry.process_id] = nil
            end
        end

        tracks[id] = nil
    end

    -- ============================================================================
    -- LOW-LEVEL DAEMON COMMUNICATION WRAPPERS
    -- ============================================================================
    -- Thin wrappers that call DaemonBridge functions with validation

    local function daemon_send_play(track)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track or not track.id then
            return false, "missing_track"
        end
        if not spatial_mode_enabled or not spatial_mode_enabled() then
            return false, "spatial_disabled"
        end
        if daemon_is_active and not daemon_is_active() then
            if ensure_daemon_ready and not ensure_daemon_ready(track.path) then
                return false, "daemon_unavailable"
            end
        end

        -- Prepare track with defaults
        track.loop = track.loop ~= false
        track.volume = clamp(track.volume or 1.0, 0.0, 3.0)
        track.listener = track.listener or (Utils and Utils.build_listener_payload and Utils.build_listener_payload()) or nil
        track.effects = track.effects and DaemonBridge.daemon_spatial_effects and DaemonBridge.daemon_spatial_effects(track.effects) or nil
        
        return DaemonBridge.play(track)
    end

    local function daemon_send_update(track)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track or not track.id then
            return false, "missing_track"
        end

        -- Prepare track with defaults
        track.volume = track.volume and clamp(track.volume, 0.0, 3.0) or nil
        track.listener = track.listener or (Utils and Utils.build_listener_payload and Utils.build_listener_payload()) or nil
        track.effects = track.effects and DaemonBridge.daemon_spatial_effects and DaemonBridge.daemon_spatial_effects(track.effects) or nil
        
        return DaemonBridge.update(track)
    end

    local function daemon_send_stop(track_id, fade)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        return DaemonBridge.stop(track_id, fade)
    end

    local function daemon_send_pause(track_id)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        return DaemonBridge.pause(track_id)
    end

    local function daemon_send_resume(track_id)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        return DaemonBridge.resume(track_id)
    end

    local function daemon_send_seek(track_id, seconds)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        if seconds == nil then
            return false, "missing_value"
        end
        return DaemonBridge.seek(track_id, seconds)
    end

    local function daemon_send_skip(track_id, seconds)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        if seconds == nil then
            return false, "missing_value"
        end
        return DaemonBridge.skip(track_id, seconds)
    end

    local function daemon_send_speed(track_id, speed)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        if speed == nil then
            return false, "missing_value"
        end
        return DaemonBridge.speed(track_id, clamp(speed, MIN_TRANSPORT_SPEED, MAX_TRANSPORT_SPEED))
    end

    local function daemon_send_reverse(track_id, enabled)
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        if not track_id then
            return false, "missing_id"
        end
        return DaemonBridge.reverse(track_id, enabled)
    end

    local function daemon_send_shutdown()
        if not DaemonBridge then
            return false, "daemon_bridge_unavailable"
        end
        return DaemonBridge.shutdown()
    end

    -- ============================================================================
    -- HIGH-LEVEL API FUNCTIONS
    -- ============================================================================

    local Api = {}

    function Api.enable_logging(enabled)
        logging_enabled = enabled and true or false
    end

    --- Register or unregister a mod as an active MiniAudio client
    -- This is a convenience wrapper around mod:set_client_active with error handling
    -- @param client_name string - Name of the client mod (typically from mod:get_name())
    -- @param active boolean - true to register as active, false to unregister
    -- @return boolean - true if successful, false if MiniAudio unavailable or call failed
    function Api.register_client(client_name, active)
        if not mod or not mod.set_client_active then
            return false
        end
        
        local ok = pcall(mod.set_client_active, mod, client_name, active)
        if ok then
            log("register_client: %s -> %s", tostring(client_name), active and "active" or "inactive")
        else
            log("register_client failed: %s", tostring(client_name))
        end
        return ok
    end

    local function guard_spatial()
        return not spatial_mode_enabled or spatial_mode_enabled()
    end

    function Api.play(spec)
        if not guard_spatial() then
            return false, "spatial_disabled"
        end

        spec = spec or {}
        local id = spec.id or next_track_id()
        local path = spec.path or spec.file or spec.resource
        if not path then
            log("API.play failed id=%s reason=missing_path", tostring(id))
            return false, "missing_path"
        end
        log("API.play request id=%s path=%s", tostring(id), tostring(path))

        local listener = Utils and Utils.ensure_listener and Utils.ensure_listener(spec.listener) or spec.listener
        if spec.require_listener ~= false and not listener then
            log("API.play failed id=%s reason=listener_unavailable", tostring(id))
            return false, "listener_unavailable"
        end

        local payload = {
            id = id,
            path = path,
            loop = spec.loop,
            volume = spec.volume,
            profile = spec.profile,
            source = spec.source,
            listener = listener,
            effects = spec.effects,
            process_id = spec.process_id or spec.owner,
            start_seconds = spec.start_seconds,
            seek_seconds = spec.seek_seconds,
            skip_seconds = spec.skip_seconds,
            speed = spec.speed,
            reverse = spec.reverse,
            autoplay = spec.autoplay,
        }

        local ok, queued_or_reason = daemon_send_play(payload)
        if not ok then
            log("API.play failed id=%s reason=%s", tostring(id), tostring(queued_or_reason))
            return false, queued_or_reason or "send_failed"
        end

        local queued = queued_or_reason and true or false
        local entry = create_or_update_entry(payload, queued and "pending" or "playing")
        log("API.play success id=%s path=%s queued=%s", tostring(id), tostring(path), tostring(queued))
        return true, entry
    end

    function Api.update(spec)
        if not main.send_update then
            return false, "unsupported"
        end

        spec = spec or {}
        if not spec.id then
            return false, "missing_id"
        end

        local entry = tracks[spec.id]
        if not entry then
            log("API.update failed id=%s reason=unknown_track", tostring(spec.id))
            return false, "unknown_track"
        end
        log("API.update request id=%s", tostring(spec.id))

        local payload = {
            id = spec.id,
            volume = spec.volume,
            profile = spec.profile,
            source = spec.source,
            listener = spec.listener or entry.listener or (Utils and Utils.ensure_listener and Utils.ensure_listener()),
            effects = spec.effects,
            seek_seconds = spec.seek_seconds,
            skip_seconds = spec.skip_seconds,
            speed = spec.speed,
            reverse = spec.reverse,
        }

        local ok, reason = main.send_update(payload)
        if not ok then
            log("API.update failed id=%s reason=%s", tostring(spec.id), tostring(reason))
            return false, reason or "send_failed"
        end

        entry.volume = payload.volume or entry.volume
        entry.profile = payload.profile and Utils.deepcopy(payload.profile) or entry.profile
        entry.source = payload.source and Utils.deepcopy(payload.source) or entry.source
        entry.effects = payload.effects and Utils.deepcopy(payload.effects) or entry.effects
        entry.speed = payload.speed or entry.speed
        if payload.reverse ~= nil then
            entry.reverse = payload.reverse
        end
        touch_entry(entry, "playing")

        log("API.update success id=%s", tostring(spec.id))
        return true, entry
    end

    function Api.stop(id, opts)
        if not id then
            return false, "missing_id"
        end

        log("API.stop request id=%s", tostring(id))
        local ok, reason = daemon_send_stop(id, opts and opts.fade)
        if ok then
            touch_entry(tracks[id], "stopping")
            remove_entry(id)
             log("API.stop success id=%s", tostring(id))
            return true
        end

        log("API.stop failed id=%s reason=%s", tostring(id), tostring(reason))
        return false, reason or "send_failed"
    end

    function Api.stop_all(opts)
        local targets = {}
        for id in pairs(tracks) do
            targets[#targets + 1] = id
        end
        log("API.stop_all count=%d", #targets)
        for _, id in ipairs(targets) do
            Api.stop(id, opts)
        end
    end

    function Api.stop_process(process_id, opts)
        if not process_id then
            return false, "missing_process"
        end

        local ids = process_index[process_id]
        if not ids then
            return false, "no_tracks"
        end

        local had_any = false
        for id in pairs(ids) do
            Api.stop(id, opts)
            had_any = true
        end

        log("API.stop_process process_id=%s had_any=%s", tostring(process_id), tostring(had_any))
        return had_any
    end

    local function simple_control(sender, id, value, state_label, label)
        if not sender then
            return false, "unsupported"
        end
        if not id then
            return false, "missing_id"
        end

        log("API.%s request id=%s value=%s", tostring(label or "control"), tostring(id), tostring(value))

        local ok, reason = sender(id, value)
        if ok then
            local entry = tracks[id]
            if entry then
                touch_entry(entry, state_label)
            end
            log("API.%s success id=%s", tostring(label or "control"), tostring(id))
            return true
        end
        log("API.%s failed id=%s reason=%s", tostring(label or "control"), tostring(id), tostring(reason))
        return false, reason or "send_failed"
    end

    function Api.pause(id)
        return simple_control(daemon_send_pause, id, nil, "paused", "pause")
    end

    function Api.resume(id)
        return simple_control(daemon_send_resume, id, nil, "playing", "resume")
    end

    function Api.seek(id, seconds)
        return simple_control(daemon_send_seek, id, seconds, nil, "seek")
    end

    function Api.skip(id, seconds)
        return simple_control(daemon_send_skip, id, seconds, nil, "skip")
    end

    function Api.speed(id, value)
        return simple_control(daemon_send_speed, id, clamp(value or 1.0, 0.125, 4.0), nil, "speed")
    end

    function Api.reverse(id, enabled)
        return simple_control(daemon_send_reverse, id, enabled, nil, "reverse")
    end

    function Api.shutdown_daemon()
        log("API.shutdown_daemon request")
        local ok, reason = daemon_send_shutdown()
        if ok then
            log("API.shutdown_daemon success")
            return true
        end
        log("API.shutdown_daemon failed reason=%s", tostring(reason))
        return false, reason or "send_failed"
    end

    function Api.remove(id)
        log("API.remove id=%s", tostring(id))
        remove_entry(id)
    end

    function Api.status(filter)
        filter = filter or {}
        if filter.id then
            return tracks[filter.id] and Utils.deepcopy(tracks[filter.id]) or nil
        end

        if filter.process_id then
            local ids = process_index[filter.process_id]
            local list = {}
            if ids then
                for id in pairs(ids) do
                    list[#list + 1] = Utils.deepcopy(tracks[id])
                end
            end
            return list
        end

        local list = {}
        for _, entry in pairs(tracks) do
            list[#list + 1] = Utils.deepcopy(entry)
        end
        return list
    end

    function Api.tracks_count()
        local count = 0
        for _ in pairs(tracks) do
            count = count + 1
        end
        return count
    end

    function Api.has_track(id)
        return tracks[id] ~= nil
    end

    function Api.set_track_state(id, state)
        local entry = tracks[id]
        if entry then
            touch_entry(entry, state)
        end
    end

    function Api.clear_finished(timeout)
        local deadline = timeout and realtime_now() - timeout or nil
        for id, entry in pairs(tracks) do
            if entry.state == "stopped" or entry.state == "finished" then
                if not deadline or (entry.updated and entry.updated < deadline) then
                    remove_entry(id)
                end
            end
        end
    end

    -- ============================================================================
    -- DAEMON LIFECYCLE MANAGEMENT
    -- ============================================================================

    --- Start the MiniAudio daemon
    -- @param path string - Optional audio file path to auto-play on startup
    -- @param volume number - Initial volume (0.0-3.0)
    -- @param pan number - Initial pan (-1.0 to 1.0, 0 = center)
    -- @return boolean, string - success status and optional error reason
    function Api.daemon_start(path, volume, pan)
        if main.daemon_start then
            return main.daemon_start(path, volume, pan)
        end
        return false, "unsupported"
    end

    --- Stop the MiniAudio daemon
    function Api.daemon_stop()
        if main.daemon_stop then
            main.daemon_stop()
        end
    end

    --- Update daemon volume and pan
    -- @param volume number - Volume (0.0-3.0)
    -- @param pan number - Pan (-1.0 to 1.0)
    function Api.daemon_update(volume, pan)
        if main.daemon_update then
            main.daemon_update(volume, pan)
        end
    end

    --- Manually control daemon volume/pan (overrides automatic mixing)
    -- @param volume number - Volume (0.0-3.0) or nil to keep current
    -- @param pan number - Pan (-1.0 to 1.0) or nil to keep current
    -- @return boolean, string - success status and optional error reason
    function Api.daemon_manual_control(volume, pan)
        if main.daemon_manual_control then
            return main.daemon_manual_control(volume, pan)
        end
        return false, "unsupported"
    end

    --- Check if daemon is running or starting
    -- @return boolean - true if daemon is active
    function Api.is_daemon_running()
        if main.get_daemon_is_running then
            return main.get_daemon_is_running()
        end
        return false
    end

    --- Get the current daemon named pipe identifier
    -- @return string|nil - pipe name or nil if unavailable
    function Api.get_pipe_name()
        if main.get_daemon_pipe_name then
            return main.get_daemon_pipe_name()
        end
        return nil
    end

    --- Get the current daemon generation number (increments on restart)
    -- @return number - generation number
    function Api.get_generation()
        if main.get_daemon_generation then
            return main.get_daemon_generation()
        end
        return 0
    end

    return Api
end
