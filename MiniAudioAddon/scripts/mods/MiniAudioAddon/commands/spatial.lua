local Vector3 = rawget(_G, "Vector3")
local Vector3Box = rawget(_G, "Vector3Box")

local SpatialCommands = {}

function SpatialCommands.register(mod, deps)
    if not mod or not deps then
        return
    end

    local Utils = deps.Utils or mod.utils or mod.Utils or {}
    local collect_command_args = deps.collect_command_args or function(...)
        return { ... }
    end
    local join_command_args = deps.join_command_args or function(args, start_idx, end_idx)
        start_idx = start_idx or 1
        end_idx = end_idx or #args
        if start_idx > end_idx then
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

    local ensure_listener_payload = deps.ensure_listener_payload or function()
        return true
    end
    local spatial_mode_enabled = deps.spatial_mode_enabled or function()
        return true
    end
    local ensure_daemon_ready_for_tests = deps.ensure_daemon_ready_for_tests or function()
        return true
    end
    local start_spatial_test = deps.start_spatial_test or function() end
    local stop_spatial_test = deps.stop_spatial_test or function()
        return true
    end
    local has_spatial_state = deps.has_spatial_state or function()
        return false
    end
    local default_profile = deps.default_profile or function()
        return {}
    end
    local expand_track_path = deps.expand_track_path or function()
        return nil
    end
    local listener_pose = deps.listener_pose or function()
        return nil, nil
    end

    local function command_spatial_test(mode, ...)
        mode = mode and string.lower(mode) or "orbit"
        local args = collect_command_args(...)

        if mode == "stop" then
            stop_spatial_test("user", false)
            return
        end

        if has_spatial_state() then
            local cleared = stop_spatial_test("restart", true)
            if not cleared then
                mod:echo("[MiniAudioAddon] A spatial test is already running; stop it before starting another.")
                return
            end

            if has_spatial_state() then
                mod:echo("[MiniAudioAddon] Waiting for the previous spatial test to stop; try again shortly.")
                return
            end
        end

        if not spatial_mode_enabled() then
            mod:echo("[MiniAudioAddon] Enable spatial daemon mode to run the spatial test.")
            return
        end

        if not ensure_listener_payload() then
            return
        end

        local initial_listener_pos, initial_listener_rot = listener_pose()

        local track_id = string.format("__miniaudio_test_%d_%05d", math.floor(os.time() or 0), math.random(10000, 99999))
        local base_volume = 1.0
        local profile = default_profile()

        local function resolve_or_error(raw_path)
            if not raw_path or raw_path == "" then
                mod:echo("[MiniAudioAddon] Provide an audio file path for the spatial test.")
                return nil
            end
            local resolved = expand_track_path(raw_path)
            if not resolved then
                mod:echo("[MiniAudioAddon] Could not find audio file: %s", tostring(raw_path))
                return nil
            end
            return resolved
        end

        local function take_number(idx, default)
            local candidate = args[idx]
            local parsed = candidate and tonumber(candidate)
            if parsed then
                return parsed, idx + 1
            end
            return default, idx
        end

        if mode == "orbit" then
            local idx = 1
            local radius; radius, idx = take_number(idx, 4)
            local period; period, idx = take_number(idx, 6)
            local duration; duration, idx = take_number(idx, 0)
            local raw_path = join_command_args(args, idx)
            local resolved = resolve_or_error(raw_path)
            if not resolved or not ensure_daemon_ready_for_tests(resolved) then
                return
            end

            start_spatial_test({
                mode = "orbit",
                track_id = track_id,
                path = resolved,
                radius = radius,
                period = period,
                duration = duration,
                volume = base_volume,
                profile = profile,
                elapsed = 0,
            })
        elseif mode == "direction" or mode == "directional" then
            local idx = 1
            local yaw; yaw, idx = take_number(idx, 0)
            local pitch; pitch, idx = take_number(idx, 0)
            local distance; distance, idx = take_number(idx, 6)
            local raw_path = join_command_args(args, idx)
            local resolved = resolve_or_error(raw_path)
            if not resolved or not ensure_daemon_ready_for_tests(resolved) then
                return
            end

            start_spatial_test({
                mode = "directional",
                track_id = track_id,
                path = resolved,
                yaw = yaw,
                pitch = pitch,
                distance = distance,
                duration = 0,
                volume = base_volume,
                profile = profile,
                elapsed = 0,
            })
        elseif mode == "follow" then
            local follow_args = {}
            for i = 1, #args do
                follow_args[i] = args[i]
            end
            if #follow_args == 0 then
                mod:echo("[MiniAudioAddon] Usage: /miniaudio_spatial_test follow <path> [offset_x offset_y offset_z]")
                return
            end

            local offset_components = { 0, 0, 0 }
            local axis = 3
            while axis >= 1 and #follow_args > 0 do
                local candidate = tonumber(follow_args[#follow_args])
                if candidate then
                    offset_components[axis] = candidate
                    follow_args[#follow_args] = nil
                    axis = axis - 1
                else
                    break
                end
            end

            local raw_path = table.concat(follow_args, " ")
            local resolved = resolve_or_error(raw_path)
            if not resolved or not ensure_daemon_ready_for_tests(resolved) then
                return
            end

            start_spatial_test({
                mode = "follow",
                track_id = track_id,
                path = resolved,
                offset = Vector3 and Vector3(offset_components[1], offset_components[2], offset_components[3])
                    or { offset_components[1], offset_components[2], offset_components[3] },
                duration = 0,
                volume = base_volume,
                profile = profile,
                elapsed = 0,
            })
        elseif mode == "loop" then
            local idx = 1
            local radius; radius, idx = take_number(idx, 6)
            local period; period, idx = take_number(idx, 8)
            local height; height, idx = take_number(idx, 0)
            local raw_path = join_command_args(args, idx)
            local resolved = resolve_or_error(raw_path)
            if not resolved or not ensure_daemon_ready_for_tests(resolved) then
                return
            end

            start_spatial_test({
                mode = "loop",
                track_id = track_id,
                path = resolved,
                radius = radius,
                period = period,
                height = height,
                duration = 0,
                volume = base_volume,
                profile = profile,
                elapsed = 0,
            })
        elseif mode == "spin" then
            if not initial_listener_pos or not initial_listener_rot then
                mod:echo("[MiniAudioAddon] Listener pose unavailable; enter gameplay before starting the spin test.")
                return
            end

            if not Vector3 then
                mod:echo("[MiniAudioAddon] Spin mode requires vector math support; unavailable in this environment.")
                return
            end

            local idx = 1
            local radius; radius, idx = take_number(idx, 4)
            local period; period, idx = take_number(idx, 6)
            local duration; duration, idx = take_number(idx, 0)
            local raw_path = join_command_args(args, idx)
            local resolved = resolve_or_error(raw_path)
            if not resolved or not ensure_daemon_ready_for_tests(resolved) then
                return
            end

            local anchor_position = initial_listener_pos
            local anchor_up = Utils.safe_up and Utils.safe_up(initial_listener_rot) or nil
            local anchor_forward = Utils.safe_forward and Utils.safe_forward(initial_listener_rot) or nil
            local anchor_right = anchor_forward and anchor_up and Vector3.normalize(Vector3.cross(anchor_forward, anchor_up)) or nil

            if Vector3 and anchor_right then
                anchor_forward = Vector3.normalize(Vector3.cross(anchor_up, anchor_right))
            end

            start_spatial_test({
                mode = "spin",
                track_id = track_id,
                path = resolved,
                radius = radius,
                period = period,
                duration = duration,
                volume = base_volume,
                profile = profile,
                elapsed = 0,
                anchor_position = Vector3Box and Vector3Box(anchor_position) or anchor_position,
                anchor_forward = Vector3Box and Vector3Box(anchor_forward) or anchor_forward,
                anchor_right = Vector3Box and Vector3Box(anchor_right) or anchor_right,
                anchor_up = Vector3Box and Vector3Box(anchor_up) or anchor_up,
            })
        else
            mod:echo("[MiniAudioAddon] Unknown spatial test mode: " .. tostring(mode))
            return
        end
    end

    mod:command("miniaudio_spatial_test", "Run spatial daemon tests. Usage: /miniaudio_spatial_test <orbit|direction|follow|loop|spin|stop> [...].", command_spatial_test)
    mod:command("elevatormusic_spatial_test", "Alias for /miniaudio_spatial_test.", command_spatial_test)

    return {
        run = command_spatial_test,
    }
end

return SpatialCommands
