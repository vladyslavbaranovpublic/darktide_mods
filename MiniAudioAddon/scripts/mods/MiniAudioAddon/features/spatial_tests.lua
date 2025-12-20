local Vector3 = rawget(_G, "Vector3")
local Vector3Box = rawget(_G, "Vector3Box")
local Quaternion = rawget(_G, "Quaternion")
local QuaternionBox = rawget(_G, "QuaternionBox")

local SpatialTests = {}

function SpatialTests.new(mod, deps)
    if not mod or not deps then
        return nil
    end

    local Utils = deps.Utils or {}
    local DaemonState = deps.DaemonState
    local DaemonBridge = deps.DaemonBridge or {}
    local daemon_start = deps.daemon_start
    local daemon_send_json = deps.daemon_send_json or DaemonBridge.daemon_send_json
    local daemon_send_stop = deps.daemon_send_stop or rawget(_G, "daemon_send_stop") or DaemonBridge.stop
    local daemon_track_profile = deps.daemon_track_profile or DaemonBridge.daemon_track_profile or function(profile)
        return profile
    end
    local daemon_spatial_effects = deps.daemon_spatial_effects or DaemonBridge.daemon_spatial_effects or function(effects)
        return effects
    end
    local draw_spatial_marker = deps.draw_spatial_marker or function() end
    local clear_spatial_marker = deps.clear_spatial_marker or function() end
    local purge_payload_files = deps.purge_payload_files or function() end
    local debug_enabled = deps.debug_enabled or function()
        return false
    end
    local listener_pose = deps.listener_pose or Utils.listener_pose or function()
        return nil, nil
    end

    local spatial_test_state = nil

    local function ensure_daemon_ready_for_tests(path_hint)
        local running = DaemonState and DaemonState.is_running and DaemonState.is_running()
        local pending = DaemonState and DaemonState.is_pending_start and DaemonState.is_pending_start()
        local known = DaemonState and DaemonState.has_known_process and DaemonState.has_known_process()
        if running or pending or known then
            return true
        end

        if daemon_start and daemon_start("", 1.0, 0.0) then
            return true
        end

        mod:error("[MiniAudioAddon] Failed to launch the daemon for the spatial test.")
        return false
    end

    local function start_spatial_test(state)
        state.stopping = false
        state.pending_notice = nil
        state.stop_message = nil
        state.stop_silent = false
        state.started = state.started or false
        state.pending_start = false
        spatial_test_state = state
        mod:echo(string.format("[MiniAudioAddon] Spatial test '%s' started.", state.mode))
    end

    local function has_spatial_state()
        return spatial_test_state ~= nil
    end

    local function build_spatial_stop_message(reason, silent)
        if silent then
            return nil
        end
        if reason and debug_enabled() then
            return string.format("[MiniAudioAddon] Spatial test stopped (%s).", tostring(reason))
        end
        return "[MiniAudioAddon] Spatial test stopped."
    end

    local function finalize_spatial_test_stop()
        if not spatial_test_state then
            return
        end

        local message = spatial_test_state.stop_message or build_spatial_stop_message(spatial_test_state.stop_reason, spatial_test_state.stop_silent)
        spatial_test_state = nil
        clear_spatial_marker()
        purge_payload_files()

        if message then
            mod:echo(message)
        end
    end

    local function spatial_test_stop(reason, silent)
        if not spatial_test_state then
            return true
        end

        local state = spatial_test_state
        state.stop_message = state.stop_message or build_spatial_stop_message(reason, silent)
        state.stop_silent = silent or false
        state.stop_reason = reason

        if state.stopping then
            if not silent and not state.pending_notice then
                mod:echo("[MiniAudioAddon] Waiting for the spatial test to stop...")
                state.pending_notice = true
            end
            return true
        end

        state.stopping = true

        if state.track_id then
            local ok, queued = daemon_send_stop and daemon_send_stop(state.track_id, state.fade or 0.25)
            if not ok then
                state.stopping = false
                state.pending_notice = nil
                if not silent then
                    mod:echo("[MiniAudioAddon] Failed to stop the spatial test; run /miniaudio_spatial_test stop again.")
                end
                return false
            end

            if queued then
                if not silent then
                    mod:echo("[MiniAudioAddon] Waiting for the spatial test to stop...")
                end
                state.pending_notice = true
                return true
            end
        end

        finalize_spatial_test_stop()
        return true
    end

    local function update_spatial_test()
        if not spatial_test_state or spatial_test_state.stopping then
            return
        end

        local listener_pos, listener_rot = listener_pose()
        if not listener_pos or not listener_rot then
            spatial_test_stop("listener missing")
            return
        end

        local state = spatial_test_state
        state.elapsed = (state.elapsed or 0) + (state.dt or 0.016)

        if state.duration and state.duration > 0 and state.elapsed >= state.duration then
            spatial_test_stop("duration")
            return
        end

        local listener_forward = Utils.safe_forward(listener_rot)
        local listener_up = Utils.safe_up(listener_rot)
        local right = Vector3 and Vector3.normalize(Vector3.cross(listener_forward, listener_up)) or { 1, 0, 0 }
        if Vector3 then
            listener_forward = Vector3.normalize(Vector3.cross(listener_up, right))
        end

        local source_pos
        local source_forward
        local velocity = { 0, 0, 0 }

        if state.mode == "orbit" then
            local angle = (state.elapsed / state.period) * math.pi * 2
            local horizontal
            if Vector3 then
                horizontal = (right * math.cos(angle)) + (listener_forward * math.sin(angle))
            else
                horizontal = { math.cos(angle), 0, math.sin(angle) }
            end
            local height = state.height or 0
            source_pos = listener_pos + horizontal * state.radius + listener_up * height
            source_forward = Vector3 and Vector3.normalize(listener_pos - source_pos) or { 0, 0, 1 }
        elseif state.mode == "directional" then
            local yaw = math.rad(state.yaw or 0)
            local pitch = math.rad(state.pitch or 0)
            local dir = listener_forward
            if Vector3 then
                dir = Quaternion.rotate(Quaternion(right, pitch), dir)
                dir = Quaternion.rotate(Quaternion(listener_up, yaw), dir)
                dir = Vector3.normalize(dir)
            end
            source_pos = listener_pos + dir * (state.distance or 6)
            source_forward = Vector3 and Vector3.normalize(listener_pos - source_pos) or { 0, 0, 1 }
        elseif state.mode == "follow" then
            local offset = state.offset or (Vector3 and Vector3(0, 0, 0) or { 0, 0, 0 })
            source_pos = listener_pos + offset
            source_forward = listener_forward
        elseif state.mode == "loop" and Vector3 then
            local angle = (state.elapsed / state.period) * math.pi * 2
            local radius = state.radius or 5
            source_pos = listener_pos + Vector3(radius * math.cos(angle), radius * math.sin(angle), state.height or 0)
            source_forward = Vector3.normalize(listener_pos - source_pos)
            velocity = Utils.vec3_to_array(Vector3(-radius * math.sin(angle), radius * math.cos(angle), 0))
        elseif state.mode == "spin" and Vector3 then
            local anchor_position = Utils.unbox_vector(state.anchor_position)
            local anchor_right = Utils.unbox_vector(state.anchor_right)
            local anchor_forward = Utils.unbox_vector(state.anchor_forward)
            local anchor_up = Utils.unbox_vector(state.anchor_up) or Vector3(0, 0, 1)

            if not anchor_position or not anchor_right or not anchor_forward then
                spatial_test_stop("missing_anchor", true)
                return
            end

            local radius = state.radius or 4
            local period = math.max(0.1, state.period or 6)
            local angle = (state.elapsed / period) * math.pi * 2
            local horizontal = (anchor_right * math.cos(angle)) + (anchor_forward * math.sin(angle))
            local height_vec = anchor_up * (state.height or 0)
            source_pos = anchor_position + horizontal * radius + height_vec
            source_forward = Vector3.normalize(anchor_position - source_pos)

            local angular_speed = (math.pi * 2) / period
            local tangential = (-anchor_right * math.sin(angle) + anchor_forward * math.cos(angle)) * (radius * angular_speed)
            velocity = Utils.vec3_to_array(tangential)
        else
            return
        end

        draw_spatial_marker(source_pos)

        if state.pending_start then
            return
        end

        local payload = {
            cmd = state.started and "update" or "play",
            id = state.track_id,
            path = state.path,
            loop = true,
            volume = state.volume or 1.0,
            profile = daemon_track_profile(state.profile),
            source = {
                position = Utils.vec3_to_array(source_pos),
                forward = Utils.vec3_to_array(source_forward),
                velocity = velocity,
            },
            listener = Utils.build_listener_payload(),
            effects = daemon_spatial_effects(state.effects),
        }

        local ok, queued = daemon_send_json and daemon_send_json(payload)
        if not ok then
            return
        end

        if payload.cmd == "play" then
            if queued then
                state.pending_start = true
            else
                state.started = true
                state.pending_start = false
            end
        end
    end

    local function handle_stop_delivery(track_id)
        if spatial_test_state and spatial_test_state.track_id == track_id then
            finalize_spatial_test_stop()
            return true
        end
        return false
    end

    local function handle_stop_failure(track_id)
        if spatial_test_state and spatial_test_state.track_id == track_id then
            spatial_test_state.stopping = false
            if spatial_test_state.stop_message and not spatial_test_state.stop_silent then
                mod:echo("[MiniAudioAddon] Failed to stop the spatial test; run /miniaudio_spatial_test stop again.")
            end
            return true
        end
        return false
    end

    local function handle_play_delivery(track_id)
        if spatial_test_state and spatial_test_state.track_id == track_id then
            spatial_test_state.pending_start = false
            spatial_test_state.started = true
            return true
        end
        return false
    end

    local function handle_play_failure(track_id)
        if spatial_test_state and spatial_test_state.track_id == track_id then
            spatial_test_stop("start_failed", true)
            mod:echo("[MiniAudioAddon] Spatial test start request failed; try again.")
            return true
        end
        return false
    end

    return {
        ensure_ready = ensure_daemon_ready_for_tests,
        start = start_spatial_test,
        stop = spatial_test_stop,
        finalize = finalize_spatial_test_stop,
        has_state = has_spatial_state,
        update = function(dt)
            if spatial_test_state then
                spatial_test_state.dt = dt or 0.016
                update_spatial_test()
            end
        end,
        handle_stop_delivery = handle_stop_delivery,
        handle_stop_failure = handle_stop_failure,
        handle_play_delivery = handle_play_delivery,
        handle_play_failure = handle_play_failure,
    }
end

return SpatialTests
