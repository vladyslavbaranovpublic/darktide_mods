local function deepcopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepcopy(v)
    end
    return copy
end

local function default_clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

return function(mod, Utils, deps)
    if not mod or not deps then
        return nil
    end

    local clamp = (Utils and Utils.clamp) or default_clamp
    local now = deps.now or os.clock
    local realtime_now = deps.realtime_now or os.clock
    local tracks = {}
    local process_index = {}
    local logging_enabled = false

    local function log(fmt, ...)
        if not logging_enabled then
            return
        end

        local message = string.format(fmt, ...)
        mod:echo(string.format("[MiniAudioAPI] %s", message))
    end

    local function ensure_listener(listener)
        if listener then
            return listener
        end

        if deps.ensure_listener then
            return deps.ensure_listener()
        end

        if deps.build_listener then
            return deps.build_listener()
        end

        return nil
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
        entry.profile = deepcopy(payload.profile) or entry.profile
        entry.source = deepcopy(payload.source) or entry.source
        entry.effects = deepcopy(payload.effects) or entry.effects
        entry.speed = payload.speed or entry.speed or 1.0
        entry.reverse = payload.reverse or entry.reverse or false
        entry.listener = deepcopy(payload.listener) or entry.listener
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

    local Api = {}

    function Api.enable_logging(enabled)
        logging_enabled = enabled and true or false
    end

    local function guard_spatial()
        return not deps.spatial_mode_enabled or deps.spatial_mode_enabled()
    end

    function Api.play(spec)
        if not deps.send_play then
            return false, "unsupported"
        end

        if not guard_spatial() then
            return false, "spatial_disabled"
        end

        spec = spec or {}
        local id = spec.id or next_track_id()
        local path = spec.path or spec.file or spec.resource
        if not path then
            return false, "missing_path"
        end

        local listener = ensure_listener(spec.listener)
        if spec.require_listener ~= false and not listener then
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

        local ok, queued_or_reason = deps.send_play(payload)
        if not ok then
            return false, queued_or_reason or "send_failed"
        end

        local queued = queued_or_reason and true or false
        local entry = create_or_update_entry(payload, queued and "pending" or "playing")
        log("play id=%s path=%s queued=%s", tostring(id), tostring(path), tostring(queued))
        return true, entry
    end

    function Api.update(spec)
        if not deps.send_update then
            return false, "unsupported"
        end

        spec = spec or {}
        if not spec.id then
            return false, "missing_id"
        end

        local entry = tracks[spec.id]
        if not entry then
            return false, "unknown_track"
        end

        local payload = {
            id = spec.id,
            volume = spec.volume,
            profile = spec.profile,
            source = spec.source,
            listener = spec.listener or entry.listener or ensure_listener(),
            effects = spec.effects,
            seek_seconds = spec.seek_seconds,
            skip_seconds = spec.skip_seconds,
            speed = spec.speed,
            reverse = spec.reverse,
        }

        local ok, reason = deps.send_update(payload)
        if not ok then
            return false, reason or "send_failed"
        end

        entry.volume = payload.volume or entry.volume
        entry.profile = payload.profile and deepcopy(payload.profile) or entry.profile
        entry.source = payload.source and deepcopy(payload.source) or entry.source
        entry.effects = payload.effects and deepcopy(payload.effects) or entry.effects
        entry.speed = payload.speed or entry.speed
        if payload.reverse ~= nil then
            entry.reverse = payload.reverse
        end
        touch_entry(entry, "playing")

        return true, entry
    end

    function Api.stop(id, opts)
        if not deps.send_stop then
            return false, "unsupported"
        end

        if not id then
            return false, "missing_id"
        end

        local ok, reason = deps.send_stop(id, opts and opts.fade)
        if ok then
            touch_entry(tracks[id], "stopping")
            remove_entry(id)
            return true
        end

        return false, reason or "send_failed"
    end

    function Api.stop_all(opts)
        local targets = {}
        for id in pairs(tracks) do
            targets[#targets + 1] = id
        end
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

        return had_any
    end

    local function simple_control(sender, id, value, state_label)
        if not sender then
            return false, "unsupported"
        end
        if not id then
            return false, "missing_id"
        end

        local ok, reason = sender(id, value)
        if ok then
            local entry = tracks[id]
            if entry then
                touch_entry(entry, state_label)
            end
            return true
        end
        return false, reason or "send_failed"
    end

    function Api.pause(id)
        return simple_control(deps.send_pause, id, nil, "paused")
    end

    function Api.resume(id)
        return simple_control(deps.send_resume, id, nil, "playing")
    end

    function Api.seek(id, seconds)
        return simple_control(deps.send_seek, id, seconds, nil)
    end

    function Api.skip(id, seconds)
        return simple_control(deps.send_skip, id, seconds, nil)
    end

    function Api.speed(id, value)
        return simple_control(deps.send_speed, id, clamp(value or 1.0, 0.125, 4.0), nil)
    end

    function Api.reverse(id, enabled)
        return simple_control(deps.send_reverse, id, enabled, nil)
    end

    function Api.shutdown_daemon()
        if deps.send_shutdown then
            local ok, reason = deps.send_shutdown()
            if ok then
                return true
            end
            return false, reason or "send_failed"
        end
        return false, "unsupported"
    end

    function Api.remove(id)
        remove_entry(id)
    end

    function Api.status(filter)
        filter = filter or {}
        if filter.id then
            return tracks[filter.id] and deepcopy(tracks[filter.id]) or nil
        end

        if filter.process_id then
            local ids = process_index[filter.process_id]
            local list = {}
            if ids then
                for id in pairs(ids) do
                    list[#list + 1] = deepcopy(tracks[id])
                end
            end
            return list
        end

        local list = {}
        for _, entry in pairs(tracks) do
            list[#list + 1] = deepcopy(entry)
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

    return Api
end
