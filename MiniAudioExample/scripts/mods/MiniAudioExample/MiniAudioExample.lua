local mod = get_mod("MiniAudioExample")
local MiniAudio = get_mod("MiniAudioAddon")
local DLS = get_mod("DarktideLocalServer")

local Mods = rawget(_G, "Mods")
local Imgui = rawget(_G, "Imgui")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local Matrix4x4 = rawget(_G, "Matrix4x4")

local function locate_popen()
    local io_variants = {}
    if Mods and Mods.lua and Mods.lua.io then
        io_variants[#io_variants + 1] = Mods.lua.io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        io_variants[#io_variants + 1] = global_io
    end

    for _, candidate in ipairs(io_variants) do
        if type(candidate) == "table" and type(candidate.popen) == "function" then
            return function(cmd, mode)
                return candidate.popen(cmd, mode or "r")
            end
        end
    end

    return nil
end

local popen = locate_popen()

local function default_sample_path(relative_subpath)
    if MiniAudio and DLS and DLS.get_mod_path then
        local ok, resolved = pcall(DLS.get_mod_path, MiniAudio, relative_subpath, false)
        if ok and resolved then
            return resolved
        end
    end

    return string.format("mods/MiniAudioAddon/%s", relative_subpath:gsub("\\", "/"))
end

local SAMPLE_TRACKS = {
    mp3 = default_sample_path("Audio\\test\\Free_Test_Data_2MB_MP3.mp3"),
    wav = default_sample_path("Audio\\test\\Free_Test_Data_2MB_WAV.wav"),
}

local CURSOR_TOKEN = "MiniAudioExampleCursor"

local ROLLOFF_OPTIONS = { "linear", "logarithmic", "exponential", "none" }

local MAIN_WINDOW_DEFAULT = {
    width = 880,
    height = 720,
    margin = 20,
}

local STATUS_WINDOW_DEFAULT = {
    width = 420,
    height = 360,
    margin = 20,
}

local CURSOR_SERVICE_ORDER = {
    "View",
    "Ingame",
    "IngameMenu",
    "Menu",
    "Debug",
}

local DMFCore = rawget(_G, "dmf")

local function get_cursor_position()
    local input_manager = Managers and Managers.input
    if not input_manager or not input_manager.get_input_service then
        return nil, nil
    end

    for _, service_name in ipairs(CURSOR_SERVICE_ORDER) do
        local service = input_manager:get_input_service(service_name)
        if service and service.get then
            local cursor = service:get("cursor")
            if cursor and cursor[1] and cursor[2] then
                return cursor[1], cursor[2]
            end
        end
    end

    return nil, nil
end

local function resolve_dmf_core()
    if DMFCore and DMFCore.run_command then
        return DMFCore
    end

    local candidate = rawget(_G, "dmf") or rawget(_G, "DMF")
    if type(candidate) == "table" and candidate.run_command then
        DMFCore = candidate
        return DMFCore
    end

    if get_mod then
        local mod = get_mod("DMF")
        if mod and mod.run_command then
            DMFCore = mod
            return DMFCore
        end
    end

    return nil
end

local function resolution_size()
    local width = MAIN_WINDOW_DEFAULT.width + 2 * MAIN_WINDOW_DEFAULT.margin
    local height = MAIN_WINDOW_DEFAULT.height + 2 * MAIN_WINDOW_DEFAULT.margin
    if RESOLUTION_LOOKUP then
        width = RESOLUTION_LOOKUP.width or width
        height = RESOLUTION_LOOKUP.height or height
    end
    return width, height
end

local function default_main_window_rect()
    local screen_w, screen_h = resolution_size()
    local margin = MAIN_WINDOW_DEFAULT.margin or 20
    local width = math.min(MAIN_WINDOW_DEFAULT.width, math.max(320, screen_w - margin * 2))
    local height = math.min(MAIN_WINDOW_DEFAULT.height, math.max(200, screen_h - margin * 2))
    local cursor_x, cursor_y = get_cursor_position()
    local pos_x, pos_y

    if cursor_x and cursor_y then
        pos_x = math.floor(cursor_x - width * 0.5)
        pos_y = math.floor(cursor_y - height * 0.35)
    else
        pos_x = math.floor((screen_w - width) / 2)
        pos_y = math.floor((screen_h - height) / 2)
    end

    pos_x = math.max(margin, math.min(screen_w - width - margin, pos_x))
    pos_y = math.max(margin, math.min(screen_h - height - margin, pos_y))

    return pos_x, pos_y, width, height
end

local function default_status_window_rect()
    local screen_w, screen_h = resolution_size()
    local margin = STATUS_WINDOW_DEFAULT.margin or 20
    local width = math.min(STATUS_WINDOW_DEFAULT.width, math.max(260, screen_w - margin * 2))
    local height = math.min(STATUS_WINDOW_DEFAULT.height, math.max(200, screen_h - margin * 2))
    local cursor_x, cursor_y = get_cursor_position()
    local pos_x, pos_y

    if cursor_x and cursor_y then
        pos_x = math.floor(cursor_x + width * 0.25)
        pos_y = math.floor(cursor_y - height * 0.5)
    else
        pos_x = screen_w - width - margin
        pos_y = margin
    end

    pos_x = math.max(margin, math.min(screen_w - width - margin, pos_x))
    pos_y = math.max(margin, math.min(screen_h - height - margin, pos_y))

    return pos_x, pos_y, width, height
end

local state = {
    window_open = false,
    window_main_initialized = false,
    window_status_initialized = false,
    track_id = "mae_track",
    control_track_id = "mae_track",
    process_id = "901",
    file_path = SAMPLE_TRACKS.mp3,
    loop = true,
    autoplay = true,
    volume = 1.0,
    start_seconds = "0",
    seek_seconds = "30",
    skip_seconds = "5",
    speed = 1.0,
    reverse = false,
    min_distance = 1.0,
    max_distance = 30.0,
    rolloff_index = 1,
    occlusion = 0.0,
    pan_override = 0.0,
    doppler = 1.0,
    use_manual_source = false,
    source_position = { 0, 0, 0 },
    source_forward = { 0, 0, 1 },
    source_velocity = { 0, 0, 0 },
    stop_fade = "0",
    stop_process = "901",
    clear_timeout = "2",
    status_snapshot = {},
    next_status_poll = 0,
    status_interval = 0.5,
    log_lines = {},
    log_limit = 120,
    random_folder = "G:\\SteamLibrary\\steamapps\\common\\Warhammer 40,000 DARKTIDE\\mods\\ElevatorMusic\\audio",
    random_files = {},
    random_loop = false,
    random_id_prefix = "rng",
    random_process = "777",
    random_autoplay = true,
    random_volume_min = 0.8,
    random_volume_max = 1.2,
    random_speed_min = 0.9,
    random_speed_max = 1.1,
    random_start_min = 0.0,
    random_start_max = 0.0,
    random_forward_min = 4.0,
    random_forward_max = 8.0,
    random_side_range = 6.0,
    random_up_min = -0.5,
    random_up_max = 0.5,
    random_reverse_chance = 0.0,
    random_queue_loop = false,
    random_queue_autoplay = true,
    random_include_subfolders = false,
    random_force_id = "",
    random_override_process = "",
    random_override_volume = "",
    random_override_speed = "",
    random_override_start = "",
    random_override_pan = "",
    random_stop_after = "",
    random_stop_fade = "",
    random_last_track_id = nil,
    random_last_track_path = nil,
    random_last_track_path = nil,
    emitter_distance = "4",
    emit_path = SAMPLE_TRACKS.mp3,
    simple_variant = "mp3",
    manual_path = SAMPLE_TRACKS.mp3,
    manual_volume = 1.0,
    manual_pan = 0.0,
    spatial_radius = "6",
    spatial_period = "8",
    spatial_height = "0",
    spatial_duration = "0",
    direction_yaw = "0",
    direction_pitch = "0",
    direction_distance = "6",
    follow_offset = { "0", "0", "0" },
    loop_radius = "6",
    loop_period = "8",
    loop_height = "0",
    loop_duration = "0",
    status_message = "",
    api_logging = false,
    cursor_pushed = false,
    active_macros = {},
    macro_tracks = {},
    random_stop_queue = {},
    spatial_override_active = false,
}

local function vec3_to_array(vec)
    if Vector3 and vec then
        return { Vector3.x(vec), Vector3.y(vec), Vector3.z(vec) }
    elseif type(vec) == "table" then
        return { vec[1] or 0, vec[2] or 0, vec[3] or 0 }
    end
    return { 0, 0, 0 }
end

local function copy_components(vec)
    if Vector3 and vec then
        return { Vector3.x(vec), Vector3.y(vec), Vector3.z(vec) }
    elseif type(vec) == "table" then
        return { vec[1] or 0, vec[2] or 0, vec[3] or 0 }
    end
    return nil
end

local function capture_listener_context()
    if not Managers or not Managers.state or not Managers.state.camera then
        return nil
    end

    local camera_manager = Managers.state.camera
    local player = Managers.player and Managers.player:local_player(1)
    if not player or not player.viewport_name then
        return nil
    end

    local pose = camera_manager:listener_pose(player.viewport_name)
    if not pose then
        return nil
    end

    local position = Matrix4x4 and Matrix4x4.translation and Matrix4x4.translation(pose)
    local rotation = Matrix4x4 and Matrix4x4.rotation and Matrix4x4.rotation(pose)
    if not position or not rotation then
        return nil
    end

    local forward = Quaternion and Quaternion.forward and Quaternion.forward(rotation)
    local up = Quaternion and Quaternion.up and Quaternion.up(rotation)
    local right = Quaternion and Quaternion.right and Quaternion.right(rotation)
    if not forward or not up or not right then
        return nil
    end

    local listener_position = copy_components(position)
    local listener_forward = copy_components(forward)
    local listener_up = copy_components(up)
    local listener_right = copy_components(right)

    return {
        listener = {
            position = listener_position,
            forward = listener_forward,
            up = listener_up,
        },
        position = listener_position,
        forward_vec = listener_forward,
        up_vec = listener_up,
        right_vec = listener_right,
    }
end

local function add_scaled(base, dir, scalar)
    local result = { base[1], base[2], base[3] }
    if dir and scalar and scalar ~= 0 then
        result[1] = result[1] + dir[1] * scalar
        result[2] = result[2] + dir[2] * scalar
        result[3] = result[3] + dir[3] * scalar
    end
    return result
end

local function build_source_from_context(ctx, offsets)
    if not ctx or not ctx.position then
        return nil
    end

    local offsets_table = offsets or {}
    local world = { ctx.position[1], ctx.position[2], ctx.position[3] }

    if offsets_table.forward and ctx.forward_vec then
        world = add_scaled(world, ctx.forward_vec, offsets_table.forward)
    end
    if offsets_table.right and ctx.right_vec then
        world = add_scaled(world, ctx.right_vec, offsets_table.right)
    end
    if offsets_table.up and ctx.up_vec then
        world = add_scaled(world, ctx.up_vec, offsets_table.up)
    end

    return {
        position = world,
        forward = ctx.forward_vec and { ctx.forward_vec[1], ctx.forward_vec[2], ctx.forward_vec[3] } or { 0, 0, 1 },
        velocity = { 0, 0, 0 },
    }
end

local function append_log(fmt, ...)
    local message = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        message = ok and formatted or tostring(fmt)
    end

    local entry = string.format("%s %s", os.date("%H:%M:%S"), message)
    state.log_lines[#state.log_lines + 1] = entry
    while #state.log_lines > state.log_limit do
        table.remove(state.log_lines, 1)
    end
end

local function require_listener_context()
    local ctx = capture_listener_context()
    if not ctx then
        append_log("Listener pose unavailable; enter gameplay before running this action.")
    end
    return ctx
end

local function ensure_addon()
    if not MiniAudio then
        MiniAudio = get_mod("MiniAudioAddon")
    end
    return MiniAudio
end

local function ensure_api()
    local addon = ensure_addon()
    return addon and addon.api or nil
end

local function ensure_spatial_mode_enabled()
    local addon = ensure_addon()
    if not addon then
        append_log("MiniAudioAddon missing; enable the mod.")
        return false
    end

    if addon.get and addon:get("miniaudioaddon_spatial_mode") then
        return true
    end

    if state.spatial_override_active then
        return true
    end

    if addon.set_spatial_mode then
        addon:set_spatial_mode(true)
        state.spatial_override_active = true
        append_log("Forced MiniAudioAddon spatial mode ON for testing.")
        return true
    end

    append_log("Enable MiniAudioAddon spatial mode (mod options) to run API tests.")
    return false
end

local function release_spatial_override()
    if not state.spatial_override_active then
        return
    end

    local addon = ensure_addon()
    if addon and addon.set_spatial_mode then
        addon:set_spatial_mode(nil)
    end
    state.spatial_override_active = false
    append_log("Restored MiniAudioAddon spatial mode preference.")
end

local function attempt_daemon_restart(label, args, arg_count)
    local addon = ensure_addon()
    if not addon or not addon.daemon_start then
        append_log("Daemon restart unavailable (%s).", label)
        return false
    end

    local path_hint
    if arg_count >= 1 then
        local first = args[1]
        if type(first) == "table" and first.path and first.path ~= "" then
            path_hint = first.path
        end
    end

    if not path_hint or path_hint == "" then
        path_hint = (state.file_path and state.file_path ~= "") and state.file_path or SAMPLE_TRACKS.mp3
    end

    if addon:daemon_start(path_hint) then
        append_log("Daemon restarted for %s; retrying...", label)
        return true
    end

    append_log("Failed to restart daemon for %s", label)
    return false
end

local function run_api(label, fn, ...)
    if not fn then
        append_log("%s unavailable (API missing)", label)
        return false
    end

    if not ensure_spatial_mode_enabled() then
        append_log("%s skipped (spatial mode disabled).", label)
        return false
    end

    local args = { ... }
    local arg_count = select("#", ...)

    local function invoke()
        return pcall(fn, table.unpack(args, 1, arg_count))
    end

    local ok, result_or_err, extra = invoke()
    if not ok then
        append_log("%s failed: %s", label, tostring(result_or_err))
        return false
    end

    if result_or_err == false then
        local handled = false
        if extra == "send_failed" and attempt_daemon_restart(label, args, arg_count) then
            ok, result_or_err, extra = invoke()
            handled = true
        end

        if not result_or_err then
            local reason = tostring(extra or "unknown")
            if handled and extra == "send_failed" then
                reason = reason .. " (after retry)"
            end
            append_log("%s rejected: %s", label, reason)
        end
    else
        append_log("%s succeeded", label)
    end

    return result_or_err, extra
end

local function run_dmf_command(name, ...)
    DMFCore = resolve_dmf_core()
    if not DMFCore or not DMFCore.run_command then
        append_log("DMF unavailable; cannot run /%s", name)
        return
    end

    local args = { ... }
    local ok, err = pcall(DMFCore.run_command, name, table.unpack(args))
    if not ok then
        append_log("/%s errored: %s", name, tostring(err))
    else
        append_log("/%s %s", name, table.concat(args, " "))
    end
end

local function parse_number(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        local parsed = tonumber(value)
        if parsed then
            return parsed
        end
    end
    return nil
end

local function clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

local function resolve_range(min_value, max_value, clamp_min, clamp_max, fallback_min, fallback_max)
    local min_num = parse_number(min_value)
    local max_num = parse_number(max_value)
    if not min_num then
        min_num = fallback_min or clamp_min or 0
    end
    if not max_num then
        max_num = fallback_max or clamp_max or min_num
    end
    if min_num > max_num then
        min_num, max_num = max_num, min_num
    end
    if clamp_min then
        min_num = math.max(clamp_min, min_num)
    end
    if clamp_max then
        max_num = math.min(clamp_max, max_num)
    end
    if min_num > max_num then
        min_num = max_num
    end
    return min_num, max_num
end

local function random_between(min_value, max_value)
    if not min_value or not max_value then
        return min_value or max_value or 0
    end
    if math.abs(max_value - min_value) < 1e-6 then
        return min_value
    end
    return min_value + math.random() * (max_value - min_value)
end

local function random_signed_range(max_abs)
    local magnitude = math.abs(parse_number(max_abs) or 0)
    if magnitude <= 0 then
        return 0
    end
    return random_between(-magnitude, magnitude)
end

local function chance_true(probability)
    local clamped = clamp(parse_number(probability) or 0, 0, 1)
    if clamped <= 0 then
        return false
    end
    if clamped >= 1 then
        return true
    end
    return math.random() < clamped
end

local function join_path(folder, file_name)
    if not folder or folder == "" then
        return file_name
    end

    local sep = folder:match("[\\/%.]$") and "" or "\\"
    return string.format("%s%s%s", folder, sep, file_name)
end

local function scan_audio_folder(folder)
    if not popen then
        append_log("Folder scan unavailable (no IO.popen)")
        return
    end

    if not folder or folder == "" then
        append_log("Provide a folder path before scanning.")
        return
    end

    local command = string.format('cmd /S /C "dir /b /a-d%s \"%s\""', state.random_include_subfolders and " /s" or "", folder)
    local handle = popen(command, "r")
    if not handle then
        append_log("Failed to enumerate %s", folder)
        return
    end

    local files = {}
    for line in handle:lines() do
        local cleaned = line and line:gsub("^%s+", ""):gsub("%s+$", "") or nil
        if cleaned and cleaned ~= "" then
            local lower = cleaned:lower()
            if lower:match("%.mp3$") or lower:match("%.wav$") or lower:match("%.flac$") or lower:match("%.ogg$") or lower:match("%.opus$") then
                if state.random_include_subfolders then
                    files[#files + 1] = cleaned
                else
                    files[#files + 1] = join_path(folder, cleaned)
                end
            end
        end
    end

    handle:close()
    table.sort(files)
    state.random_files = files
    append_log("Scanned %s%s -> %d playable files", folder, state.random_include_subfolders and " (recursive)" or "", #files)
end

local function pick_random_file()
    if #state.random_files == 0 then
        append_log("Scan a folder first.")
        return nil
    end

    local idx = math.random(1, #state.random_files)
    local path = state.random_files[idx]
    state.file_path = path
    state.manual_path = path
    append_log("Picked random file #%d -> %s", idx, path)
    return path
end

local function ensure_status(api)
    if not api or not api.status then
        state.status_snapshot = {}
        return
    end

    local snapshot = api.status()
    if type(snapshot) ~= "table" then
        state.status_snapshot = {}
        return
    end

    state.status_snapshot = snapshot
end

local function draw_vector_input(label, values)
    Imgui.push_id(label)
    for i = 1, 3 do
        local tag = string.format("%s[%d]", label, i)
        values[i] = Imgui.input_text(tag, values[i])
    end
    Imgui.pop_id()
end

local function build_source_payload(ctx, offsets)
    if not state.use_manual_source then
        ctx = ctx or capture_listener_context()
        if ctx then
            return build_source_from_context(ctx, offsets or { forward = 4 })
        end
        return nil
    end

    local position = {}
    local forward = {}
    local velocity = {}
    for i = 1, 3 do
        position[i] = parse_number(state.source_position[i]) or 0
        forward[i] = parse_number(state.source_forward[i]) or 0
        velocity[i] = parse_number(state.source_velocity[i]) or 0
    end

    return {
        position = position,
        forward = forward,
        velocity = velocity,
    }
end

local function build_profile()
    local min_dist = clamp(state.min_distance or 1.0, 0.01, 1000.0)
    local max_dist = clamp(state.max_distance or (min_dist + 1.0), min_dist + 0.5, 2000.0)
    local rolloff = ROLLOFF_OPTIONS[state.rolloff_index] or ROLLOFF_OPTIONS[1]

    return {
        min_distance = min_dist,
        max_distance = max_dist,
        rolloff = rolloff,
    }
end

local function build_effects()
    return {
        occlusion = clamp(state.occlusion or 0, 0, 1),
        pan_override = clamp(state.pan_override or 0, -1, 1),
        doppler = math.max(0.01, state.doppler or 1),
    }
end

local function compute_randomized_values()
    local values = {}

    local vol_min, vol_max = resolve_range(state.random_volume_min, state.random_volume_max, 0, 3, 0.8, 1.2)
    local speed_min, speed_max = resolve_range(state.random_speed_min, state.random_speed_max, 0.125, 4.0, 0.9, 1.1)
    local start_min, start_max = resolve_range(state.random_start_min, state.random_start_max, 0, nil, 0, 0)
    local forward_min, forward_max = resolve_range(state.random_forward_min, state.random_forward_max, -2000, 2000, 2, 6)
    local up_min, up_max = resolve_range(state.random_up_min, state.random_up_max, -2000, 2000, -0.5, 0.5)

    local override_volume = parse_number(state.random_override_volume)
    values.volume = override_volume or random_between(vol_min, vol_max)

    local override_speed = parse_number(state.random_override_speed)
    values.speed = clamp(override_speed or random_between(speed_min, speed_max), 0.125, 4.0)

    local override_start = parse_number(state.random_override_start)
    values.start_seconds = math.max(0, override_start ~= nil and override_start or random_between(start_min, start_max))

    local ctx = capture_listener_context()
    values.listener = ctx and ctx.listener or nil

    local offsets = {
        forward = random_between(forward_min, forward_max),
        right = random_signed_range(state.random_side_range),
        up = random_between(up_min, up_max),
    }

    if ctx then
        values.source = build_source_from_context(ctx, offsets)
    end

    local pan_override = parse_number(state.random_override_pan)
    if not pan_override and offsets.right and state.random_side_range and state.random_side_range > 0 then
        local side_ratio = offsets.right / math.max(0.01, state.random_side_range)
        pan_override = clamp(side_ratio, -1, 1)
    end

    if pan_override then
        values.effects = { pan_override = clamp(pan_override, -1, 1) }
    end

    values.reverse = chance_true(state.random_reverse_chance)

    return values
end

local function build_random_payload(path, overrides)
    if not path or path == "" then
        return nil, "Missing path"
    end

    overrides = overrides or {}

    local forced_id = state.random_force_id
    if forced_id == "" then
        forced_id = nil
    end
    local id = overrides.id or forced_id or string.format("%s_%05d", state.random_id_prefix, math.random(10000, 99999))

    local process_id = parse_number(overrides.process_id)
    if not process_id then
        process_id = parse_number(state.random_override_process)
    end
    if not process_id then
        process_id = parse_number(state.random_process)
    end
    local loop_flag = overrides.loop
    if loop_flag == nil then
        loop_flag = state.random_loop
    end
    local autoplay_flag = overrides.autoplay
    if autoplay_flag == nil then
        autoplay_flag = state.random_autoplay
    end

    local values = compute_randomized_values()

    local payload = {
        id = id,
        path = path,
        loop = loop_flag,
        autoplay = autoplay_flag,
        volume = values.volume,
        start_seconds = values.start_seconds,
        speed = values.speed,
        profile = build_profile(),
        source = values.source,
        process_id = process_id,
        effects = values.effects,
        listener = values.listener,
    }

    payload.reverse = overrides.reverse
    if payload.reverse == nil then
        payload.reverse = values.reverse
    end

    local extras = nil
    local stop_after = parse_number(state.random_stop_after)
    if stop_after and stop_after > 0 then
        extras = {
            stop_after = stop_after,
        }
        local fade_ms = parse_number(state.random_stop_fade)
        if fade_ms and fade_ms > 0 then
            extras.stop_fade = fade_ms
        end
    end

    return payload, extras
end

local function build_random_update_spec(track_id)
    if not track_id or track_id == "" then
        return nil, "Missing track id"
    end

    local values = compute_randomized_values()
    return {
        id = track_id,
        volume = values.volume,
        profile = build_profile(),
        source = values.source,
        listener = values.listener,
        effects = values.effects,
        speed = values.speed,
        reverse = values.reverse,
    }
end

local function queue_random_auto_stop(track_id, delay_seconds, fade_ms)
    if not track_id or not delay_seconds or delay_seconds <= 0 then
        return
    end

    state.random_stop_queue[#state.random_stop_queue + 1] = {
        id = track_id,
        when = (os.clock() or 0) + delay_seconds,
        fade = fade_ms,
    }
end

local function apply_random_extras(payload, extras)
    if not payload or not extras then
        return
    end

    if extras.stop_after and extras.stop_after > 0 then
        queue_random_auto_stop(payload.id, extras.stop_after, extras.stop_fade)
        append_log("Auto-stop scheduled for %s in %.2fs", payload.id, extras.stop_after)
    end
end

local function update_random_stop_queue(api)
    if not api or not api.stop then
        return
    end

    if not state.random_stop_queue or #state.random_stop_queue == 0 then
        return
    end

    local now = os.clock() or 0
    local index = 1
    while index <= #state.random_stop_queue do
        local job = state.random_stop_queue[index]
        if not job or not job.when or now >= job.when then
            if job and job.id then
                local opts = job.fade and { fade = job.fade } or nil
                run_api("stop#auto", api.stop, job.id, opts)
            end
            table.remove(state.random_stop_queue, index)
        else
            index = index + 1
        end
    end
end

local function draw_play_controls(api)
    if not Imgui.collapsing_header("Play / Update", true) then
        return
    end

    local function submit_play(path_override)
        local target_path = path_override or state.file_path
        if path_override then
            state.file_path = target_path
        end

        local ctx = capture_listener_context()

        local payload = {
            id = (state.track_id ~= "" and state.track_id) or nil,
            path = target_path,
            loop = state.loop,
            autoplay = state.autoplay,
            volume = state.volume,
            profile = build_profile(),
            effects = build_effects(),
            source = build_source_payload(ctx),
            process_id = parse_number(state.process_id),
            start_seconds = parse_number(state.start_seconds),
            seek_seconds = parse_number(state.seek_seconds),
            skip_seconds = parse_number(state.skip_seconds),
            speed = state.speed,
            reverse = state.reverse,
        }

        if ctx then
            payload.listener = ctx.listener
        end

        if payload.path and payload.path ~= "" then
            local ok = run_api("play", api.play, payload)
            if ok then
                state.control_track_id = payload.id or state.track_id
            end
        else
            append_log("Provide a path before playing.")
        end
    end

    state.track_id = Imgui.input_text("Track ID", state.track_id)
    state.file_path = Imgui.input_text("Audio Path", state.file_path or "")

    if Imgui.button("Play Sample MP3") then
        submit_play(SAMPLE_TRACKS.mp3)
    end
    Imgui.same_line()
    if Imgui.button("Play Sample WAV") then
        submit_play(SAMPLE_TRACKS.wav)
    end

    state.process_id = Imgui.input_text("Process ID (optional number)", state.process_id or "")
    state.loop = Imgui.checkbox("Loop playback", state.loop)
    state.autoplay = Imgui.checkbox("Autoplay when ready", state.autoplay)

    state.volume = Imgui.input_float("Volume (linear 0..3)", state.volume, "%.2f")
    state.start_seconds = Imgui.input_text("Start Seconds (seek before play)", state.start_seconds or "")
    state.seek_seconds = Imgui.input_text("Seek Seconds (absolute)", state.seek_seconds or "")
    state.skip_seconds = Imgui.input_text("Skip Seconds (relative)", state.skip_seconds or "")
    state.speed = Imgui.input_float("Speed / Pitch", state.speed, "%.3f")
    state.reverse = Imgui.checkbox("Reverse", state.reverse)

    Imgui.separator()
    Imgui.text("Spatial Profile")
    state.min_distance = Imgui.input_float("Min Distance", state.min_distance, "%.2f")
    state.max_distance = Imgui.input_float("Max Distance", state.max_distance, "%.2f")
    state.rolloff_index = math.max(1, math.min(#ROLLOFF_OPTIONS, Imgui.slider_int and Imgui.slider_int("Rolloff Choice", state.rolloff_index, 1, #ROLLOFF_OPTIONS) or state.rolloff_index))
    if not Imgui.slider_int then
        state.rolloff_index = Imgui.input_int and Imgui.input_int("Rolloff Index (1-4)", state.rolloff_index) or state.rolloff_index
        state.rolloff_index = math.max(1, math.min(#ROLLOFF_OPTIONS, state.rolloff_index))
    end
    Imgui.text(string.format("Using rolloff=%s", ROLLOFF_OPTIONS[state.rolloff_index]))

    state.occlusion = Imgui.input_float("Occlusion 0..1", state.occlusion, "%.2f")
    state.pan_override = Imgui.input_float("Pan Override -1..1", state.pan_override, "%.2f")
    state.doppler = Imgui.input_float("Doppler Factor", state.doppler, "%.2f")

    state.use_manual_source = Imgui.checkbox("Provide manual source transform", state.use_manual_source)
    if state.use_manual_source then
        Imgui.text("Source position xyz")
        draw_vector_input("source_pos", state.source_position)
        Imgui.text("Source forward xyz")
        draw_vector_input("source_fwd", state.source_forward)
        Imgui.text("Source velocity xyz")
        draw_vector_input("source_vel", state.source_velocity)
    end

    if Imgui.button("Play / Replace Track") then
        submit_play()
    end

    Imgui.same_line()
    if Imgui.button("Update (volume/spatial)") then
        if not state.track_id or state.track_id == "" then
            append_log("Track ID required for update.")
        else
            local spec = {
                id = state.track_id,
                volume = state.volume,
                profile = build_profile(),
                effects = build_effects(),
                source = build_source_payload(),
                speed = state.speed,
                reverse = state.reverse,
            }
            run_api("update", api.update, spec)
        end
    end
end

local function draw_transport_controls(api)
    if not Imgui.collapsing_header("Transport & Lifecycle", true) then
        return
    end

    state.control_track_id = Imgui.input_text("Target Track ID", state.control_track_id or state.track_id or "")
    local track_id = state.control_track_id ~= "" and state.control_track_id or nil

    state.stop_fade = Imgui.input_text("Stop fade ms (optional)", state.stop_fade)
    Imgui.push_id("stop_process_input")
    state.stop_process = Imgui.input_text("Stop process id", state.stop_process)
    Imgui.pop_id()
    state.clear_timeout = Imgui.input_text("Clear finished timeout (seconds)", state.clear_timeout)

    if Imgui.button("Pause") and track_id then
        run_api("pause", api.pause, track_id)
    end
    Imgui.same_line()
    if Imgui.button("Resume") and track_id then
        run_api("resume", api.resume, track_id)
    end
    Imgui.same_line()
    if Imgui.button("Seek abs") and track_id then
        run_api("seek", api.seek, track_id, parse_number(state.seek_seconds) or 0)
    end
    Imgui.same_line()
    if Imgui.button("Skip +/-") and track_id then
        run_api("skip", api.skip, track_id, parse_number(state.skip_seconds) or 0)
    end

    if Imgui.button("Apply speed") and track_id then
        run_api("speed", api.speed, track_id, state.speed)
    end
    Imgui.same_line()
    if Imgui.button("Set reverse flag") and track_id ~= nil then
        run_api("reverse", api.reverse, track_id, state.reverse)
    end

    if Imgui.button("Stop track") and track_id then
        local fade = parse_number(state.stop_fade)
        local opts = fade and { fade = fade } or nil
        run_api("stop", api.stop, track_id, opts)
    end
    Imgui.same_line()
    if Imgui.button("Remove track (forget)") and track_id then
        run_api("remove", api.remove, track_id)
    end
    Imgui.same_line()
    if Imgui.button("Mark finished (demo)") and track_id then
        run_api("set_state", api.set_track_state, track_id, "finished")
    end

    if Imgui.button("Stop all tracks") then
        api.stop_all()
        append_log("Issued stop_all()")
    end
    Imgui.same_line()
    Imgui.push_id("stop_process_button")
    if Imgui.button("Stop process id") then
        local pid = parse_number(state.stop_process)
        if pid then
            run_api("stop_process", api.stop_process, pid)
        else
            append_log("Provide a numeric process id.")
        end
    end
    Imgui.pop_id()

    if Imgui.button("Clear finished entries") then
        local timeout = parse_number(state.clear_timeout)
        run_api("clear_finished", api.clear_finished, timeout)
    end
end

local function draw_randomizer(api)
    if not Imgui.collapsing_header("Randomizer & Folder Tests", false) then
        return
    end

    state.random_folder = Imgui.input_text("Audio folder", state.random_folder or "")
    state.random_include_subfolders = Imgui.checkbox("Include subfolders", state.random_include_subfolders)
    if Imgui.button("Scan folder") then
        scan_audio_folder(state.random_folder)
    end
    Imgui.same_line()
    if Imgui.button("Pick random file") then
        pick_random_file()
    end

    Imgui.text(string.format("%d files cached", #state.random_files))
    Imgui.separator()
    Imgui.text("Random playback behavior")
    state.random_loop = Imgui.checkbox("Loop random plays", state.random_loop)
    state.random_autoplay = Imgui.checkbox("Autoplay random tracks", state.random_autoplay)
    state.random_queue_loop = Imgui.checkbox("Loop queued tracks", state.random_queue_loop)
    state.random_queue_autoplay = Imgui.checkbox("Autoplay queued tracks", state.random_queue_autoplay)
    state.random_id_prefix = Imgui.input_text("Random ID prefix", state.random_id_prefix)
    state.random_process = Imgui.input_text("Random process id", state.random_process)

    Imgui.separator()
    Imgui.text("Volume / speed / start ranges")
    state.random_volume_min = Imgui.input_float("Volume min", state.random_volume_min, "%.2f")
    state.random_volume_max = Imgui.input_float("Volume max", state.random_volume_max, "%.2f")
    if state.random_volume_min > state.random_volume_max then
        state.random_volume_min, state.random_volume_max = state.random_volume_max, state.random_volume_min
    end
    state.random_speed_min = Imgui.input_float("Speed min", state.random_speed_min, "%.2f")
    state.random_speed_max = Imgui.input_float("Speed max", state.random_speed_max, "%.2f")
    if state.random_speed_min > state.random_speed_max then
        state.random_speed_min, state.random_speed_max = state.random_speed_max, state.random_speed_min
    end
    state.random_start_min = Imgui.input_float("Start seconds min", state.random_start_min, "%.2f")
    state.random_start_max = Imgui.input_float("Start seconds max", state.random_start_max, "%.2f")
    if state.random_start_min > state.random_start_max then
        state.random_start_min, state.random_start_max = state.random_start_max, state.random_start_min
    end

    Imgui.separator()
    Imgui.text("Spatial offsets (meters)")
    state.random_forward_min = Imgui.input_float("Forward offset min", state.random_forward_min, "%.2f")
    state.random_forward_max = Imgui.input_float("Forward offset max", state.random_forward_max, "%.2f")
    if state.random_forward_min > state.random_forward_max then
        state.random_forward_min, state.random_forward_max = state.random_forward_max, state.random_forward_min
    end
    local side_value = select(1, Imgui.input_float("Side offset +/- range", state.random_side_range, "%.2f"))
    state.random_side_range = math.max(0, side_value or 0)
    state.random_up_min = Imgui.input_float("Up offset min", state.random_up_min, "%.2f")
    state.random_up_max = Imgui.input_float("Up offset max", state.random_up_max, "%.2f")
    if state.random_up_min > state.random_up_max then
        state.random_up_min, state.random_up_max = state.random_up_max, state.random_up_min
    end

    state.random_reverse_chance = clamp(Imgui.input_float("Reverse probability (0..1)", state.random_reverse_chance, "%.2f"), 0, 1)

    Imgui.separator()
    Imgui.text("Manual overrides (blank = use random settings)")
    state.random_force_id = Imgui.input_text("Force track ID", state.random_force_id or "")
    state.random_override_process = Imgui.input_text("Override process id", state.random_override_process or "")
    state.random_override_volume = Imgui.input_text("Volume override", state.random_override_volume or "")
    state.random_override_start = Imgui.input_text("Start seconds override", state.random_override_start or "")
    state.random_override_speed = Imgui.input_text("Speed override", state.random_override_speed or "")
    state.random_override_pan = Imgui.input_text("Pan override (-1..1)", state.random_override_pan or "")
    state.random_stop_after = Imgui.input_text("Auto-stop after seconds", state.random_stop_after or "")
    state.random_stop_fade = Imgui.input_text("Auto-stop fade ms", state.random_stop_fade or "")

    if state.random_last_track_id then
        Imgui.text(string.format("Last random track: %s", state.random_last_track_id))
        Imgui.same_line()
        if Imgui.button("Update last track##random_live") then
            local spec, err = build_random_update_spec(state.random_last_track_id)
            if spec then
                run_api("update#random_live", api.update, spec)
            else
                append_log("Random update aborted: %s", tostring(err))
            end
        end
    end

    Imgui.separator()
    if Imgui.button("Play random now") then
        local path = pick_random_file()
        if path then
            local payload, extras_or_err = build_random_payload(path)
            if payload then
                local ok = run_api("play#random", api.play, payload)
                if ok then
                    state.random_last_track_id = payload.id
                    state.random_last_track_path = payload.path
                    apply_random_extras(payload, extras_or_err)
                end
            else
                append_log("Random play aborted: %s", tostring(extras_or_err))
            end
        end
    end

    if Imgui.button("Queue entire folder") and #state.random_files > 0 then
        for index, path in ipairs(state.random_files) do
            local payload, extras = build_random_payload(path, {
                id = string.format("%s_%03d", state.random_id_prefix, index),
                loop = state.random_queue_loop,
                autoplay = state.random_queue_autoplay,
            })
            if payload then
                local ok = run_api("play#queue", api.play, payload)
                if ok then
                    state.random_last_track_id = payload.id
                    state.random_last_track_path = payload.path
                    apply_random_extras(payload, extras)
                end
            else
                append_log("Random queue entry skipped: %s", tostring(extras))
            end
        end
    end
end

local function draw_cli_shortcuts()
    if not Imgui.collapsing_header("Built-in Test Shortcuts", false) then
        return
    end

    Imgui.text("Simple sample harness")
    state.simple_variant = Imgui.input_text("Sample type (mp3|wav)", state.simple_variant)
    if Imgui.button("Simple Play") then
        run_dmf_command("miniaudio_simple_play", state.simple_variant)
    end
    Imgui.same_line()
    if Imgui.button("Simple Emit") then
        run_dmf_command("miniaudio_simple_emit", state.emitter_distance, state.simple_variant)
    end
    Imgui.same_line()
    if Imgui.button("Simple Stop/cleanup") then
        run_dmf_command("miniaudio_simple_stop")
    end

    Imgui.separator()
    Imgui.text("Emitter sandbox")
    state.emit_path = Imgui.input_text("Emitter path", state.emit_path)
    state.emitter_distance = Imgui.input_text("Emitter distance", state.emitter_distance)
    if Imgui.button("Emit start (sphere)") then
        run_dmf_command("miniaudio_emit_start", state.emit_path, state.emitter_distance)
    end
    Imgui.same_line()
    if Imgui.button("Emit stop") then
        run_dmf_command("miniaudio_emit_stop")
    end

    Imgui.separator()
    Imgui.text("Spatial playground")
    state.spatial_radius = Imgui.input_text("Orbit radius", state.spatial_radius)
    state.spatial_period = Imgui.input_text("Orbit period", state.spatial_period)
    state.spatial_height = Imgui.input_text("Orbit height", state.spatial_height)
    state.spatial_duration = Imgui.input_text("Optional duration", state.spatial_duration)
    state.loop_radius = Imgui.input_text("Loop radius", state.loop_radius)
    state.loop_period = Imgui.input_text("Loop period", state.loop_period)
    state.loop_height = Imgui.input_text("Loop height", state.loop_height)
    if Imgui.button("Orbit test") then
        run_dmf_command("miniaudio_spatial_test", "orbit", state.spatial_radius, state.spatial_period, state.spatial_height, state.file_path)
    end
    Imgui.same_line()
    if Imgui.button("Loop test") then
        run_dmf_command("miniaudio_spatial_test", "loop", state.loop_radius, state.loop_period, state.loop_height, state.file_path)
    end

    state.direction_yaw = Imgui.input_text("Direction yaw", state.direction_yaw)
    state.direction_pitch = Imgui.input_text("Direction pitch", state.direction_pitch)
    state.direction_distance = Imgui.input_text("Direction distance", state.direction_distance)
    if Imgui.button("Directional ping") then
        run_dmf_command("miniaudio_spatial_test", "direction", state.direction_yaw, state.direction_pitch, state.direction_distance, state.file_path)
    end

    Imgui.text("Follow offsets xyz")
    for i = 1, 3 do
        state.follow_offset[i] = Imgui.input_text(string.format("Follow offset %d", i), state.follow_offset[i])
    end
    if Imgui.button("Follow player") then
        run_dmf_command("miniaudio_spatial_test", "follow", state.file_path, state.follow_offset[1], state.follow_offset[2], state.follow_offset[3])
    end
    Imgui.same_line()
    if Imgui.button("Spin in-place") then
        run_dmf_command("miniaudio_spatial_test", "spin", state.spatial_radius, state.spatial_period, state.spatial_height, state.file_path)
    end
    Imgui.same_line()
    if Imgui.button("Stop spatial test") then
        run_dmf_command("miniaudio_spatial_test", "stop")
    end

    Imgui.separator()
    Imgui.text("Manual CLI path tester")
    state.manual_path = Imgui.input_text("Test path", state.manual_path or "")
    if Imgui.button("Run /miniaudio_test_play") then
        run_dmf_command("miniaudio_test_play", state.manual_path)
    end
    Imgui.same_line()
    if Imgui.button("Stop manual track") then
        run_dmf_command("miniaudio_test_stop")
    end

    Imgui.separator()
    if Imgui.button("Cleanup payload files") then
        run_dmf_command("miniaudio_cleanup_payloads")
    end
end

local function draw_daemon_controls(api)
    if not Imgui.collapsing_header("Daemon Controls", false) then
        return
    end

    state.manual_path = Imgui.input_text("Daemon autoplay path", state.manual_path or "")
    state.manual_volume = Imgui.input_float("Daemon volume (0..3)", state.manual_volume, "%.2f")
    state.manual_pan = Imgui.input_float("Daemon pan (-1..1)", state.manual_pan, "%.2f")

    local addon = ensure_addon()

    if Imgui.button("Start / restart daemon") then
        if addon and addon.daemon_start then
            addon:daemon_start(state.manual_path ~= "" and state.manual_path or nil, state.manual_volume, state.manual_pan)
            append_log("daemon_start issued")
        else
            append_log("MiniAudioAddon missing; cannot start daemon")
        end
    end

    Imgui.same_line()
    if Imgui.button("Stop daemon process") then
        if addon and addon.daemon_stop then
            addon:daemon_stop()
            append_log("daemon_stop issued")
        else
            append_log("Daemon stop unavailable")
        end
    end

    if Imgui.button("Manual volume/pan override") then
        if addon and addon.daemon_manual_control then
            addon:daemon_manual_control(state.manual_volume, state.manual_pan)
            append_log("Manual override applied (volume=%.2f pan=%.2f)", state.manual_volume, state.manual_pan)
        end
    end
    Imgui.same_line()
    if Imgui.button("Release manual override") then
        if addon and addon.daemon_manual_control then
            addon:daemon_manual_control(nil, nil)
            run_dmf_command("miniaudio_manual_clear")
        end
    end

    if Imgui.button("Broadcast daemon update (volume/pan)") then
        if addon and addon.daemon_update then
            addon:daemon_update(state.manual_volume, state.manual_pan)
            append_log("daemon_update applied")
        end
    end

    if Imgui.button("Shutdown daemon via API") then
        run_api("shutdown", api.shutdown_daemon)
    end
end

local function draw_status_panel(api)
    if not Imgui.collapsing_header("Daemon / Track Status", true) then
        return
    end

    local addon = ensure_addon()
    local running = addon and addon.is_daemon_running and addon:is_daemon_running()
    Imgui.text(string.format("Daemon running: %s", running and "yes" or "no"))
    Imgui.same_line()
    Imgui.text(string.format("Tracks tracked: %d", api.tracks_count()))
    Imgui.same_line()
    Imgui.text(string.format("Has track %s: %s", state.control_track_id or "?", api.has_track(state.control_track_id or "__nil") and "yes" or "no"))

    if Imgui.button("Refresh status now") then
        ensure_status(api)
    end

    local snapshot = state.status_snapshot or {}
    if type(snapshot) == "table" and #snapshot > 0 then
        Imgui.begin_child_window("track_snapshot", 0, 200, true, "horizontal_scrollbar")
        for _, entry in ipairs(snapshot) do
            if entry and entry.id then
                Imgui.text(string.format("[%s] state=%s process=%s loop=%s speed=%.2f reverse=%s time=%.2fs",
                    entry.id,
                    entry.state or "unknown",
                    tostring(entry.process_id or "-"),
                    tostring(entry.loop),
                    entry.speed or 1.0,
                    entry.reverse and "true" or "false",
                    entry.updated or 0))
            end
        end
        Imgui.end_child_window()
    else
        Imgui.text("No active entries.")
    end
end

local function draw_log_panel()
    if not Imgui.collapsing_header("Action Log", false) then
        return
    end

    Imgui.begin_child_window("mae_log", 0, 260, true, "horizontal_scrollbar")
    for index = #state.log_lines, 1, -1 do
        Imgui.text(state.log_lines[index])
    end
    Imgui.end_child_window()
end

local function unique_id(prefix)
    local stamp = math.floor((os.clock() or 0) * 1000)
    return string.format("%s_%d_%04d", prefix or "mae", stamp, math.random(1000, 9999))
end

local function count_table_entries(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function enqueue_macro(name, steps)
    if not steps or #steps == 0 then
        return
    end

    state.active_macros[#state.active_macros + 1] = {
        name = name,
        steps = steps,
        index = 1,
        next_time = os.clock() or 0,
    }
    append_log("Macro '%s' queued (%d steps)", name, #steps)
end

local function stop_macro_tracks(api)
    api = api or ensure_api()
    if not api then
        append_log("Cannot stop macro tracks: API unavailable")
        return
    end

    for track_id in pairs(state.macro_tracks) do
        run_api("stop#macro", api.stop, track_id)
        state.macro_tracks[track_id] = nil
    end
    state.active_macros = {}
end

local function queue_line_macro()
    local path = (state.file_path and state.file_path ~= "") and state.file_path or SAMPLE_TRACKS.mp3
    local spacing = 4
    local count = 5
    local ids = {}
    local steps = {}
    local ctx = require_listener_context()
    if not ctx then
        return
    end
    local base_profile = { min_distance = 1.0, max_distance = 25.0, rolloff = "linear" }

    for index = 1, count do
        local offset = (index - ((count + 1) / 2)) * spacing
        local track_id = unique_id("maeLine")
        ids[#ids + 1] = track_id
        local offset_right = offset
        local delay_after = (index == count) and 6 or 0
        steps[#steps + 1] = {
            delay = delay_after,
            fn = function(api)
                local source = build_source_from_context(ctx, { right = offset_right, forward = 6 })
                if not source then
                    append_log("Line macro skipped (listener lost).")
                    return
                end
                run_api("play#line", api.play, {
                    id = track_id,
                    path = path,
                    loop = true,
                    volume = 0.8,
                    listener = ctx.listener,
                    source = source,
                    profile = base_profile,
                })
                state.macro_tracks[track_id] = true
            end,
        }
    end

    steps[#steps + 1] = {
        delay = 0,
        fn = function(api)
            for _, track_id in ipairs(ids) do
                run_api("stop#line", api.stop, track_id)
                state.macro_tracks[track_id] = nil
            end
        end,
    }

    enqueue_macro("Line array", steps)
end

local function queue_reverse_macro()
    local path = (state.file_path and state.file_path ~= "") and state.file_path or SAMPLE_TRACKS.mp3
    local track_id = unique_id("maeReverse")
    local ctx = require_listener_context()
    if not ctx then
        return
    end
    local steps = {
        {
            delay = 0,
            fn = function(api)
                local source = build_source_from_context(ctx, { forward = 4 })
                if not source then
                    append_log("Reverse macro skipped (listener lost).")
                    return
                end
                run_api("play#reverse", api.play, {
                    id = track_id,
                    path = path,
                    loop = true,
                    start_seconds = 0,
                    volume = 1.0,
                    listener = ctx.listener,
                    source = source,
                    profile = { min_distance = 1.0, max_distance = 18.0, rolloff = "linear" },
                })
                state.macro_tracks[track_id] = true
            end,
        },
        {
            delay = 2.0,
            fn = function(api)
                run_api("reverse#flip", api.reverse, track_id, true)
            end,
        },
        {
            delay = 1.5,
            fn = function(api)
                run_api("reverse#flip", api.reverse, track_id, false)
            end,
        },
        {
            delay = 0.5,
            fn = function(api)
                run_api("speed#burst", api.speed, track_id, 1.75)
            end,
        },
        {
            delay = 1.0,
            fn = function(api)
                run_api("stop#reverse", api.stop, track_id)
                state.macro_tracks[track_id] = nil
            end,
        },
    }

    enqueue_macro("Reverse shuttle", steps)
end

local function queue_vertical_macro()
    local path = (state.file_path and state.file_path ~= "") and state.file_path or SAMPLE_TRACKS.mp3
    local track_id = unique_id("maeVertical")
    local ctx = require_listener_context()
    if not ctx then
        return
    end
    local offsets = {
        { forward = 4, up = 0 },
        { forward = 4, up = 4 },
        { forward = 4, up = 8 },
        { forward = 4, up = 2 },
    }

    local steps = {
        {
            delay = 0,
            fn = function(api)
                local source = build_source_from_context(ctx, offsets[1])
                if not source then
                    append_log("Vertical macro skipped (listener lost).")
                    return
                end
                run_api("play#vertical", api.play, {
                    id = track_id,
                    path = path,
                    loop = true,
                    volume = 0.9,
                    source = source,
                    listener = ctx.listener,
                    profile = { min_distance = 1.0, max_distance = 20.0, rolloff = "linear" },
                })
                state.macro_tracks[track_id] = true
            end,
        },
    }

    for idx = 2, #offsets do
        steps[#steps + 1] = {
            delay = 1.0,
            fn = function(api)
                local source = build_source_from_context(ctx, offsets[idx])
                if not source then
                    append_log("Vertical macro update skipped (listener lost).")
                    return
                end
                run_api("update#vertical", api.update, {
                    id = track_id,
                    source = source,
                })
            end,
        }
    end

    steps[#steps + 1] = {
        delay = 0.5,
        fn = function(api)
            run_api("pause#vertical", api.pause, track_id)
        end,
    }

    steps[#steps + 1] = {
        delay = 0.5,
        fn = function(api)
            run_api("resume#vertical", api.resume, track_id)
        end,
    }

    steps[#steps + 1] = {
        delay = 0.5,
        fn = function(api)
            run_api("stop#vertical", api.stop, track_id)
            state.macro_tracks[track_id] = nil
        end,
    }

    enqueue_macro("Vertical sweep", steps)
end

local function draw_macro_panel(api)
    if not Imgui.collapsing_header("Scenario Macros", false) then
        return
    end

    Imgui.text("Preset experiments that queue scripted API calls:")
    if Imgui.button("Line speaker array") then
        queue_line_macro()
    end
    Imgui.same_line()
    if Imgui.button("Reverse shuttle") then
        queue_reverse_macro()
    end
    Imgui.same_line()
    if Imgui.button("Vertical sweep") then
        queue_vertical_macro()
    end

    if Imgui.button("Stop macro tracks") then
        stop_macro_tracks(api)
    end

    Imgui.text(string.format("Active macros: %d", #state.active_macros))
    Imgui.same_line()
    Imgui.text(string.format("Macro tracks playing: %d", count_table_entries(state.macro_tracks)))
end

local function update_macros(api)
    if not api or #state.active_macros == 0 then
        return
    end

    local now = os.clock() or 0
    local index = 1
    while index <= #state.active_macros do
        local macro = state.active_macros[index]
        local step = macro.steps[macro.index]
        if not step then
            append_log("Macro '%s' completed", macro.name)
            table.remove(state.active_macros, index)
        elseif now >= (macro.next_time or now) then
            if step.fn then
                local ok, err = pcall(step.fn, api)
                if not ok then
                    append_log("Macro '%s' step error: %s", macro.name, err)
                end
            end
            macro.next_time = now + (step.delay or 0)
            macro.index = macro.index + 1
        else
            index = index + 1
        end
    end
end

local function toggle_cursor(enable)
    local input_manager = Managers and Managers.input
    if not input_manager then
        return
    end

    if enable and not state.cursor_pushed then
        input_manager:push_cursor(CURSOR_TOKEN)
        state.cursor_pushed = true
    elseif not enable and state.cursor_pushed then
        input_manager:pop_cursor(CURSOR_TOKEN)
        state.cursor_pushed = false
    end
end

local function reset_window_layout()
    state.window_main_initialized = false
    state.window_status_initialized = false
end

local function render_window()
    if not state.window_open or not Imgui then
        return
    end

    if not state.window_main_initialized then
        local pos_x, pos_y, width, height = default_main_window_rect()
        if Imgui.set_next_window_size then
            Imgui.set_next_window_size(width, height)
        end
        if Imgui.set_next_window_pos then
            Imgui.set_next_window_pos(pos_x, pos_y)
        end
    end

    local _, closed = Imgui.begin_window("MiniAudio Example Suite", "horizontal_scrollbar")
    if closed then
        mod.toggle_window()
        Imgui.end_window()
        return
    end
    state.window_main_initialized = true

    local api = ensure_api()
    if not api then
        Imgui.text_colored(255, 0, 0, 255, "MiniAudioAddon missing; install/enable it to use this sample mod.")
        Imgui.end_window()
        return
    end

    local base_cursor_x, base_cursor_y = 0, 0
    if Imgui.get_cursor_pos then
        base_cursor_x, base_cursor_y = Imgui.get_cursor_pos()
    end
    local win_width = 600
    if Imgui.get_window_size then
        local w = { Imgui.get_window_size() }
        win_width = w[1] or win_width
    end
    local button_width = 120
    local padding = 10
    local start_x = math.max(0, win_width - (button_width * 2 + padding * 2))
    Imgui.set_cursor_pos(start_x, base_cursor_y + 24)

    if Imgui.button("Stop all tracks##toolbar", button_width) then
        if api.stop_all then
            api.stop_all()
            append_log("stop_all issued via toolbar")
        end
    end
    Imgui.same_line()
    if Imgui.button("Kill daemon##toolbar", button_width) then
        local addon = ensure_addon()
        if addon and addon.daemon_stop then
            addon:daemon_stop()
            append_log("daemon_stop issued via toolbar")
        end
    end

    Imgui.set_cursor_pos(base_cursor_x, base_cursor_y + 56)
    Imgui.spacing()

    state.api_logging = Imgui.checkbox("Enable API debug echo", state.api_logging)
    if Imgui.button("Apply logging toggle") then
        run_api("enable_logging", api.enable_logging, state.api_logging)
    end

    draw_play_controls(api)
    draw_transport_controls(api)
    draw_randomizer(api)
    draw_cli_shortcuts()
    draw_daemon_controls(api)
    draw_macro_panel(api)

    Imgui.end_window()

    if not state.window_status_initialized then
        local pos_x, pos_y, width, height = default_status_window_rect()
        if Imgui.set_next_window_size then
            Imgui.set_next_window_size(width, height)
        end
        if Imgui.set_next_window_pos then
            Imgui.set_next_window_pos(pos_x, pos_y)
        end
    end

    local _, closed_right = Imgui.begin_window("MiniAudio Example Suite - Status", "horizontal_scrollbar")
    if not closed_right then
        state.window_status_initialized = true
        draw_status_panel(api)
        draw_log_panel()
        Imgui.end_window()
    else
        Imgui.end_window()
    end
end

function mod.toggle_window()
    state.window_open = not state.window_open
    if state.window_open and Imgui then
        toggle_cursor(true)
        Imgui.open_imgui()
    elseif not state.window_open and Imgui then
        toggle_cursor(false)
        Imgui.close_imgui()
    end
end

mod:command("miniaudio_example", "Toggle the MiniAudioExample ImGui tester.", function()
    mod.toggle_window()
end)

function mod:keybind_toggle_window()
    mod.toggle_window()
end

local function auto_open_if_needed()
    if mod:get("mae_auto_open") then
        if not state.window_open then
            mod.toggle_window()
        end
    end
end

function mod.update(dt)
    local api = ensure_api()
    update_macros(api)
    update_random_stop_queue(api)

    if state.window_open then
        if api and state.next_status_poll <= (os.clock() or 0) then
            ensure_status(api)
            state.next_status_poll = (os.clock() or 0) + state.status_interval
        end
        render_window()
    end

    local addon = ensure_addon()
    if addon and addon.set_client_active and addon.api then
        addon:set_client_active(mod:get_name(), addon.api.tracks_count() > 0)
    end
end

function mod.on_game_state_changed(status, state_name)
    if status == "enter" and state_name == "StateGameplay" then
        auto_open_if_needed()
    end
end

function mod.on_setting_changed(setting_id)
    if setting_id == "mae_auto_open" then
        auto_open_if_needed()
    end
end

local function close_window(reset_layout)
    if state.window_open and Imgui then
        Imgui.close_imgui()
    end
    state.window_open = false
    toggle_cursor(false)
    if reset_layout then
        reset_window_layout()
    end
end

function mod.on_unload()
    close_window(true)
    stop_macro_tracks()
    release_spatial_override()
end

function mod.on_disabled()
    close_window(true)
    stop_macro_tracks()
    release_spatial_override()
end

mod:hook("UIManager", "using_input", function(func, ...)
    if state.window_open then
        return true
    end
    return func(...)
end)
