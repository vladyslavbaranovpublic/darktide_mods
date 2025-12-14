local mod = get_mod("ElevatorMusic")
local MiniAudio = get_mod("MiniAudioAddon")
local DLS = get_mod("DarktideLocalServer")

local Managers = rawget(_G, "Managers")
local Unit = rawget(_G, "Unit")
local Vector3 = rawget(_G, "Vector3")
local Vector3Box = rawget(_G, "Vector3Box")
local Quaternion = rawget(_G, "Quaternion")
local QuaternionBox = rawget(_G, "QuaternionBox")
local Matrix4x4 = rawget(_G, "Matrix4x4")
local World = rawget(_G, "World")
local LineObject = rawget(_G, "LineObject")
local Color = rawget(_G, "Color")

local math = math
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local table = table

local HEIGHT_OFFSET = 2.0
local IDLE_VOLUME_SCALE = 0.55
local DISTANCE_ATTENUATION_SCALE = 0.8
local MARKER_RADIUS = 0.50
local MARKER_ARROW_LENGTH = 0.6

local AUDIO_EXTENSIONS = {
    [".flac"] = true,
    [".mp3"] = true,
    [".wav"] = true,
}

local UNSUPPORTED_EXTENSIONS = {
    [".ogg"] = "Ogg Vorbis",
    [".opus"] = "Opus",
}

local FALLBACK_FILENAMES = {
    "elevator_music.mp3",
    "elevator_music.wav",
    "Darktide Elevator Music 2025-12-04 09_14_fixed.mp3",
}

local DIRECTION_NAMES = {}
local DIRECTION_VALUES = {}
do
    local lookup = rawget(_G, "NetworkLookup")
    local source = lookup and lookup.moveable_platform_direction
    if source then
        for label, value in pairs(source) do
            DIRECTION_NAMES[value] = label
            DIRECTION_VALUES[label] = value
        end
    else
        DIRECTION_NAMES[1] = "none"
        DIRECTION_NAMES[2] = "forward"
        DIRECTION_NAMES[3] = "backward"
        DIRECTION_VALUES.none = 1
        DIRECTION_VALUES.forward = 2
        DIRECTION_VALUES.backward = 3
    end
end

local function direction_name(value)
    return DIRECTION_NAMES[value] or "none"
end

local PROCESS_ID = mod:get_name()

local state = {
    platforms = {},
    markers = {},
    playlist = {},
    audio_folder = nil,
    client_active = false,
    daemon_ready = false,
    next_daemon_check = 0,
    last_scan_t = 0,
    next_index = 1,
    warned_files = false,
    warned_api = false,
    sequence = 0,
    watchers_registered = false,
    unsupported_signature = nil,
    spatial_override_active = false,
    test_emitter = nil,
    pose_helpers_missing = false,
    visuals_warned = false,
}
local visuals_module = nil

local stop_all_emitters -- forward declaration so callbacks can reference it
local fade_ms -- forward declaration so earlier functions can close over it
local log_echo -- forward declaration for helper logging
local log_error -- forward declaration for helper logging
local stop_test_emitter -- forward declaration for the diagnostic emitter
local function new_pose_tracker()
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    local factory = MiniAudio and MiniAudio.pose_tracker
    if factory and factory.new then
        return factory.new({ height_offset = HEIGHT_OFFSET })
    end
    return nil
end

local function clamp(value, min_value, max_value)
    if min_value > max_value then
        min_value, max_value = max_value, min_value
    end
    return math.max(min_value, math.min(max_value, value))
end

local function finite(value, default)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return default or 0
    end
    return value
end

local function sample_delta_time(timer_name)
    if not timer_name or not Managers or not Managers.time then
        return nil
    end

    local manager = Managers.time
    if not manager or not manager.delta_time then
        return nil
    end

    local ok, value = pcall(manager.delta_time, manager, timer_name)
    if ok and type(value) == "number" then
        return value
    end

    return nil
end

local function delta_time()
    return sample_delta_time("gameplay")
        or sample_delta_time("ui")
        or sample_delta_time("fixed")
        or 0.016
end

local function emitter_update_interval()
    return math.max(0.02, delta_time())
end

local function rainbow_module()
    if visuals_module == false then
        return nil
    end
    if visuals_module then
        return visuals_module
    end

    local ok, module = pcall(function()
        return mod:io_dofile("ElevatorMusic/scripts/mods/ElevatorMusic/visuals/rainbow")
    end)
    if not ok or not module then
        visuals_module = false
        return nil
    end
    visuals_module = module
    if state.visuals_warned then
        state.visuals_warned = false
    end
    return visuals_module
end

local function visuals_enabled()
    return mod:get("elevatormusic_visuals_enable")
end

local function visuals_settings()
    return {
        speed = clamp(finite(mod:get("elevatormusic_visuals_speed") or 1.2, 1.2), 0.05, 6),
        jitter = clamp(finite(mod:get("elevatormusic_visuals_randomness") or 0.3, 0.3), 0, 3),
        radius = clamp(finite(mod:get("elevatormusic_visuals_radius") or 0.55, 0.55), 0.2, 1.5),
    }
end

local function visuals_attach(entry, position)
    local module = rainbow_module()
    if not module then
        if not state.visuals_warned and visuals_enabled() then
            log_error("[ElevatorMusic] Rainbow visuals unavailable; update ElevatorMusic.")
            state.visuals_warned = true
        end
        return
    end
    if not visuals_enabled() then
        module.remove(entry.key)
        return
    end
    local settings = visuals_settings()
    module.spawn(entry.key, settings)
    module.configure(entry.key, settings)
    module.set_position(entry.key, position)
end

local function visuals_update(entry, position)
    local module = rainbow_module()
    if not module then
        return
    end
    if not visuals_enabled() then
        module.remove(entry.key)
        return
    end
    local settings = visuals_settings()
    module.configure(entry.key, settings)
    module.set_position(entry.key, position)
end

local function visuals_detach(entry)
    local module = rainbow_module()
    if module then
        module.remove(entry.key)
    end
end

local function visuals_refresh_all()
    local module = rainbow_module()
    if not module then
        return
    end
    if not visuals_enabled() then
        module.remove_all()
        return
    end
    for key, entry in pairs(state.platforms) do
        if entry.emitter and entry.emitter.tracker then
            local _, position = entry.emitter.tracker:source_payload()
            if position then
                visuals_attach(entry, position)
            end
        end
    end

    local test = state.test_emitter
    if test and test.entry and test.pose then
        visuals_attach(test.entry, test.pose)
    end
end

local function visuals_tick(dt)
    local module = rainbow_module()
    if module and module.update then
        module.update(dt)
    end
end

local function now()
    local ok, clock_value = pcall(function()
        if Managers and Managers.time then
            return Managers.time:time("ui") or Managers.time:time("gameplay")
        end
    end)
    return ok and clock_value or os.clock()
end

local function vec3_to_array(vec)
    if not vec or not Vector3 then
        return { 0, 0, 0 }
    end
    return { Vector3.x(vec), Vector3.y(vec), Vector3.z(vec) }
end

local function unit_key(unit)
    if not unit then
        return nil
    end
    if Unit and Unit.id_string then
        local ok, key = pcall(Unit.id_string, unit)
        if ok and key then
            return key
        end
    end
    return tostring(unit)
end

local function player_unit()
    if not Managers or not Managers.player then
        return nil
    end

    local player_manager = Managers.player
    local fetch = nil
    if player_manager.local_player_safe then
        fetch = function(id)
            local ok, value = pcall(player_manager.local_player_safe, player_manager, id)
            if ok then
                return value
            end
        end
    elseif player_manager.local_player then
        fetch = function(id)
            local ok, value = pcall(player_manager.local_player, player_manager, id)
            if ok then
                return value
            end
        end
    end

    local player = fetch and fetch(1) or nil
    return player and player.player_unit or nil
end

local function player_position()
    local unit = player_unit()
    if unit and Unit and Unit.alive and Unit.alive(unit) then
        return Unit.world_position(unit, 1)
    end
    return nil
end

local function player_basis()
    local unit = player_unit()
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return nil
    end

    local ok_pos, position = pcall(Unit.world_position, unit, 1)
    local ok_rot, rotation = pcall(Unit.world_rotation, unit, 1)
    if not ok_pos or not ok_rot or not position or not rotation then
        return nil
    end

    local forward = Quaternion and Quaternion.forward and Quaternion.forward(rotation)
    local up = Quaternion and Quaternion.up and Quaternion.up(rotation)
    if not forward and Vector3 then
        forward = Vector3(0, 0, 1)
    end
    if not up and Vector3 then
        up = Vector3(0, 0, 1)
    end

    local right = nil
    if forward and up and Vector3 and Vector3.cross then
        local cross = Vector3.cross(forward, up)
        if Vector3.normalize then
            cross = Vector3.normalize(cross)
        end
        right = cross
    end
    if (not right) and Vector3 then
        right = Vector3(1, 0, 0)
    end

    return position, forward, right, up, rotation
end

local function fallback_listener_payload()
    if not Managers or not Managers.state or not Managers.state.camera or not Matrix4x4 then
        return nil
    end

    local player_manager = Managers.player
    if not player_manager or not player_manager.local_player then
        return nil
    end

    local player = player_manager:local_player(1)
    if not player or not player.viewport_name then
        return nil
    end

    local camera_manager = Managers.state.camera
    local pose = camera_manager:listener_pose(player.viewport_name)
    if not pose then
        return nil
    end

    local position = Matrix4x4.translation(pose)
    local rotation = Matrix4x4.rotation(pose)
    if not position or not rotation then
        return nil
    end

    local forward = Quaternion and Quaternion.forward and Quaternion.forward(rotation)
    local up = Quaternion and Quaternion.up and Quaternion.up(rotation)

    return {
        position = vec3_to_array(position),
        forward = vec3_to_array(forward or (Vector3 and Vector3(0, 0, 1)) or { 0, 0, 1 }),
        up = vec3_to_array(up or (Vector3 and Vector3(0, 1, 0)) or { 0, 1, 0 }),
    }
end

local function extension_world_position(unit)
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return nil
    end
    return Unit.world_position(unit, 1)
end

local function extension_forward(unit)
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return nil
    end
    if Quaternion and Quaternion.forward then
        local rotation = Unit.world_rotation(unit, 1)
        local ok, forward = pcall(Quaternion.forward, rotation)
        if ok and forward then
            return forward
        end
    end
    if Vector3 and Vector3.forward then
        return Vector3.forward()
    end
    return Vector3 and Vector3(0, 0, 1) or nil
end

local function resolve_audio_folder()
    if state.audio_folder then
        return state.audio_folder
    end

    if DLS and DLS.get_mod_path then
        local ok, folder = pcall(DLS.get_mod_path, mod, "audio", false)
        if ok and folder then
            state.audio_folder = folder
            return folder
        end

        ok, folder = pcall(DLS.get_mod_path, mod, "audio", true)
        if ok and folder then
            state.audio_folder = folder:gsub('"', "")
            return state.audio_folder
        end
    end

    state.audio_folder = string.format("mods/%s/audio", mod:get_name())
    return state.audio_folder
end

local function locate_popen()
    local Mods = rawget(_G, "Mods")
    local candidates = {}
    if Mods and Mods.lua and Mods.lua.io then
        candidates[#candidates + 1] = Mods.lua.io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        candidates[#candidates + 1] = global_io
    end

    for _, candidate in ipairs(candidates) do
        if type(candidate) == "table" and type(candidate.popen) == "function" then
            return function(cmd)
                return candidate.popen(cmd, "r")
            end
        end
    end

    return nil
end

local function extension_of(path)
    local dot = path:match("^.*(%.[^%.]+)$")
    return dot and dot:lower() or ""
end

local function log_unsupported_files(skipped)
    if not skipped or not next(skipped) then
        state.unsupported_signature = nil
        return
    end

    local signature_parts = {}
    local items = {}
    local total = 0

    for ext, count in pairs(skipped) do
        total = total + count
        signature_parts[#signature_parts + 1] = string.format("%s=%d", ext, count)
        local label = UNSUPPORTED_EXTENSIONS[ext]
        if type(label) == "string" then
            items[#items + 1] = string.format("%s (%s) x%d", label, ext, count)
        else
            items[#items + 1] = string.format("%s x%d", ext, count)
        end
    end

    table.sort(signature_parts)
    table.sort(items)

    local signature = table.concat(signature_parts, "|")
    if state.unsupported_signature == signature then
        return
    end
    state.unsupported_signature = signature

    local plural = total == 1 and "" or "s"
    log_error(
        "[ElevatorMusic] Skipped %d unsupported audio file%s (%s). Convert them to MP3/FLAC/WAV (see audio/EXAMPLE COMMAND TO FIX BROKEN SOUND FILES.txt).",
        total,
        plural,
        table.concat(items, ", ")
    )
end

local function fallback_track_path(folder)
    for _, name in ipairs(FALLBACK_FILENAMES) do
        local candidate = string.format("%s\\%s", folder, name)
        local file = io.open(candidate, "rb")
        if file then
            file:close()
            return candidate
        end
    end
    return nil
end

local function scan_audio_folder(force)
    local folder = resolve_audio_folder()
    if not folder then
        return
    end

    local recently_scanned = now() - state.last_scan_t < 2
    if not force and (#state.playlist > 0 or recently_scanned) then
        return
    end

    local popen = locate_popen()
    if not popen then
        if not state.warned_files then
            log_error("[ElevatorMusic] IO.popen unavailable; cannot enumerate audio files.")
            state.warned_files = true
        end
        return
    end

    local pipe = popen(string.format('cmd /S /C "dir /b /a-d \"%s\""', folder))
    if not pipe then
        return
    end

    state.playlist = {}
    state.last_scan_t = now()
    state.next_index = 1
    local skipped = {}

    for line in pipe:lines() do
        local trimmed = line and line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local ext = extension_of(trimmed)
            if AUDIO_EXTENSIONS[ext] then
                state.playlist[#state.playlist + 1] = string.format("%s\\%s", folder, trimmed)
            elseif UNSUPPORTED_EXTENSIONS[ext] then
                skipped[ext] = (skipped[ext] or 0) + 1
            end
        end
    end
    pipe:close()

    log_unsupported_files(skipped)

    if #state.playlist == 0 then
        local fallback = fallback_track_path(folder)
        if fallback then
            state.playlist[1] = fallback
            if not state.warned_files then
                local name = fallback:match("([^/\\]+)$") or fallback
                log_echo("[ElevatorMusic] No custom playlist detected; using fallback track '%s'.", name)
                state.warned_files = true
            end
        elseif not state.warned_files then
            log_echo("[ElevatorMusic] Place MP3/FLAC/WAV files under %s to enable elevator music.", folder)
            state.warned_files = true
        end
    else
        if not state.warned_files then
            log_echo("[ElevatorMusic] Found %d track(s).", #state.playlist)
        end
        state.warned_files = false
    end
end

local function pick_track_path()
    scan_audio_folder()
    if #state.playlist == 0 then
        return nil
    end

    if mod:get("elevatormusic_random_order") then
        return state.playlist[math.random(1, #state.playlist)]
    end

    local path = state.playlist[state.next_index]
    state.next_index = state.next_index + 1
    if state.next_index > #state.playlist then
        state.next_index = 1
    end
    return path
end

local function ensure_api()
    if MiniAudio and MiniAudio.api then
        return MiniAudio.api
    end

    MiniAudio = get_mod("MiniAudioAddon")
    if MiniAudio and MiniAudio.api then
        return MiniAudio.api
    end

    if not state.warned_api then
        log_error("[ElevatorMusic] MiniAudioAddon is required. Enable MiniAudioAddon before using ElevatorMusic.")
        state.warned_api = true
    end
    return nil
end

local function debug_logging_enabled()
    return mod:get("elevatormusic_debug") and true or false
end

local function log_api_event(fmt, ...)
    if not fmt then
        return
    end

    if not debug_logging_enabled() then
        return
    end

    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    local api_log = MiniAudio and MiniAudio.api_log
    if not api_log then
        return
    end

    local ok, err = pcall(api_log, mod:get_name(), fmt, ...)
    if not ok and mod:get("elevatormusic_debug") then
        mod:echo("[ElevatorMusic] API log failed: %s", tostring(err))
    end
end

log_echo = function(fmt, ...)
    if fmt then
        log_api_event("ECHO: " .. tostring(fmt), ...)
    end
    if mod.echo then
        return mod:echo(fmt, ...)
    end
end

log_error = function(fmt, ...)
    if fmt then
        log_api_event("ERROR: " .. tostring(fmt), ...)
    end
    if mod.error then
        return mod:error(fmt, ...)
    end
end

local function current_listener()
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if MiniAudio and MiniAudio.ensure_listener_payload then
        local ok, payload = pcall(MiniAudio.ensure_listener_payload, MiniAudio)
        if ok and payload then
            return payload
        end
    end

    local api = ensure_api()
    if not api then
        return nil
    end

    local builder = api.build_listener
    if not builder then
        return nil
    end

    local ok, listener = pcall(builder)
    if ok then
        return listener
    end
    return fallback_listener_payload()
end

local function on_daemon_reset(reason)
    stop_all_emitters(reason or "daemon_reset")
    state.daemon_ready = false
    state.next_daemon_check = 0
    state.client_active = false
    log_api_event("daemon_reset (%s)", tostring(reason or "unknown"))
end

local function register_miniaudio_watchers()
    if state.watchers_registered then
        return
    end

    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio then
        return
    end

    if MiniAudio.on_generation_reset then
        pcall(MiniAudio.on_generation_reset, MiniAudio, on_daemon_reset)
    end
    if MiniAudio.on_daemon_reset then
        pcall(MiniAudio.on_daemon_reset, MiniAudio, on_daemon_reset)
    end

    state.watchers_registered = true
end

local function sync_client_activity()
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio or not MiniAudio.set_client_active then
        return
    end

    local any_active = false
    for _, entry in pairs(state.platforms) do
        if entry.emitter then
            any_active = true
            break
        end
    end

    if state.client_active ~= any_active then
        state.client_active = any_active
        pcall(MiniAudio.set_client_active, MiniAudio, mod:get_name(), any_active)
    end
end

local function reset_miniaudio(reason, hard)
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    log_api_event("miniaudio_reset reason=%s hard=%s", tostring(reason or "unknown"), tostring(hard and true or false))
    if MiniAudio and MiniAudio.api and MiniAudio.api.stop_process then
        pcall(MiniAudio.api.stop_process, MiniAudio.api, PROCESS_ID, { fade = fade_ms() })
    end

    if MiniAudio and MiniAudio.set_client_active then
        pcall(MiniAudio.set_client_active, MiniAudio, mod:get_name(), false)
    end

    if hard and MiniAudio and MiniAudio.daemon_stop then
        log_api_event("daemon_stop requested (reason=%s)", tostring(reason or "unknown"))
        pcall(MiniAudio.daemon_stop, MiniAudio)
    end

    state.client_active = false
    if hard then
        state.daemon_ready = false
        state.next_daemon_check = 0
        release_spatial_override()
    end

    if mod:get("elevatormusic_debug") then
        log_echo("[ElevatorMusic] MiniAudio reset (%s).", tostring(reason or "unknown"))
    end
end

local function call_api(label, method, payload)
    local api = ensure_api()
    if not api then
        return false, "missing_api"
    end

    local fn = api[method]
    if not fn then
        log_error("[ElevatorMusic] Unknown MiniAudio API method '%s'.", tostring(method))
        return false, "missing_method"
    end

    local ok, result, extra
    if method == "play" or method == "update" then
        ok, result, extra = pcall(fn, payload)
    elseif method == "stop" then
        payload = payload or {}
        ok, result, extra = pcall(fn, payload.id, { fade = payload.fade })
    else
        ok, result, extra = pcall(fn, payload)
    end
    if not ok then
        log_error("[ElevatorMusic] %s failed: %s", label, tostring(result))
        log_api_event("%s failed (%s)", tostring(label), tostring(result))
        return false, "pcall_failed"
    end

    if result == false then
        if extra ~= "unknown_track" then
            log_error("[ElevatorMusic] %s rejected (%s).", label, tostring(extra or "unknown"))
        elseif mod:get("elevatormusic_debug") then
            log_echo("[ElevatorMusic] %s dropped (track missing).", label)
        end
        log_api_event("%s rejected (%s)", tostring(label), tostring(extra or "unknown"))
        return false, extra or "rejected"
    end

    return true, result
end

local function daemon_play(payload)
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio or not MiniAudio.daemon_send_play then
        return false, "missing_daemon"
    end

    local ok, result, detail = pcall(MiniAudio.daemon_send_play, MiniAudio, payload)
    if not ok then
        log_error("[ElevatorMusic] daemon play failed: %s", tostring(result))
        return false, "pcall_failed"
    end
    if not result then
        log_error("[ElevatorMusic] daemon play rejected (%s).", tostring(detail or "unknown"))
        return false, detail or "send_failed"
    end
    return true, detail
end

local function daemon_update(payload)
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio or not MiniAudio.daemon_send_update then
        return false, "missing_daemon"
    end

    local ok, result, detail = pcall(MiniAudio.daemon_send_update, MiniAudio, payload)
    if not ok then
        log_error("[ElevatorMusic] daemon update failed: %s", tostring(result))
        return false, "pcall_failed"
    end
    if not result then
        log_error("[ElevatorMusic] daemon update rejected (%s).", tostring(detail or "unknown"))
        return false, detail or "send_failed"
    end
    return true
end

local function daemon_stop(track_id, fade)
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio or not MiniAudio.daemon_send_stop then
        return false, "missing_daemon"
    end

    local ok, result, detail = pcall(MiniAudio.daemon_send_stop, MiniAudio, track_id, fade or 0)
    if not ok then
        log_error("[ElevatorMusic] daemon stop failed: %s", tostring(result))
        return false, "pcall_failed"
    end
    if not result then
        log_error("[ElevatorMusic] daemon stop rejected (%s).", tostring(detail or "unknown"))
        return false, detail or "send_failed"
    end
    return true
end

local function marker_state(entry)
    local key = entry.key
    if not key then
        return nil
    end

    local marker = state.markers[key]
    if not marker then
        marker = {
            text_category = string.format("ElevatorMusic_%s", key),
            text_color = Vector3 and Vector3(255, 220, 80),
        }
        state.markers[key] = marker
    end
    return marker
end

local function clear_marker(entry)
    local marker = entry and marker_state(entry)
    if not marker then
        return
    end

    if marker.line_object and marker.world and LineObject then
        LineObject.reset(marker.line_object)
        LineObject.dispatch(marker.world, marker.line_object)
    end

    local debug_text = Managers and Managers.state and Managers.state.debug_text
    if debug_text and marker.text_category and debug_text.clear_world_text then
        debug_text:clear_world_text(marker.text_category)
    end
end

local function draw_marker(entry, position, rotation, mode_label)
    local show = mod:get("elevatormusic_show_markers")
    local marker = marker_state(entry)
    if not marker or not show then
        clear_marker(entry)
        return
    end

    if not LineObject or not World or not Managers or not Managers.world or not position then
        clear_marker(entry)
        return
    end

    local world = Managers.world:world("level_world")
    if not world then
        clear_marker(entry)
        return
    end

    if not marker.line_object or marker.world ~= world then
        local ok, line_object = pcall(World.create_line_object, world)
        if not ok or not line_object then
            return
        end
        marker.line_object = line_object
        marker.world = world
    end

    LineObject.reset(marker.line_object)
    local sphere_color = Color and Color(200, 255, 200, 80) or nil
    LineObject.add_sphere(marker.line_object, sphere_color, position, MARKER_RADIUS, 16, 12)

    if rotation and Quaternion and Vector3 and Vector3.cross and Vector3.normalize then
        local forward = Quaternion.forward and Quaternion.forward(rotation) or Vector3(0, 0, 1)
        local up = Quaternion.up and Quaternion.up(rotation) or Vector3(0, 0, 1)
        local right = Vector3.normalize(Vector3.cross(forward, up))
        local tip = position + forward * MARKER_ARROW_LENGTH
        local left_tip = tip - right * 0.18
        local right_tip = tip + right * 0.18
        local color = Color and Color(200, 255, 160, 60) or nil
        LineObject.add_line(marker.line_object, color, position, tip)
        LineObject.add_line(marker.line_object, color, tip, left_tip)
        LineObject.add_line(marker.line_object, color, tip, right_tip)
    end

    LineObject.dispatch(marker.world, marker.line_object)

    local debug_text = Managers and Managers.state and Managers.state.debug_text
    if debug_text and debug_text.output_world_text and Vector3 then
        local label = string.format("Elevator (%s)", mode_label or "off")
        local label_pos = position + Vector3(0, 0, 0.45)
        local player_pos = player_position()
        if player_pos and Vector3.distance then
            local ok, distance = pcall(Vector3.distance, player_pos, position)
            if ok and distance then
                label = string.format("%s - %.1fm", label, distance)
            end
        end
        local color = marker.text_color or Vector3(255, 220, 80)
        debug_text:output_world_text(label, 0.08, label_pos, 0.12, marker.text_category, color)
    end
end

local function destroy_marker(entry)
    clear_marker(entry)
    if entry and entry.key then
        local marker = state.markers[entry.key]
        if marker and marker.line_object and marker.world and LineObject then
            LineObject.reset(marker.line_object)
            LineObject.dispatch(marker.world, marker.line_object)
        end
        state.markers[entry.key] = nil
    end
end

local function refresh_marker(entry, mode_label)
    if not entry then
        return
    end

    local position, rotation
    local apply_offset = true

    if entry.pose_provider then
        local ok, pose = pcall(entry.pose_provider, entry)
        if ok and pose and pose.position then
            position = pose.position
            rotation = pose.rotation
            if pose.offset ~= nil then
                apply_offset = pose.offset and true or false
            end
        end
    end

    if not position then
        local unit = entry.unit
        if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
            destroy_marker(entry)
            return
        end
        position = Unit.world_position(unit, 1)
        rotation = Unit.world_rotation(unit, 1)
        apply_offset = true
    end

    if apply_offset and Vector3 then
        position = position + Vector3(0, 0, HEIGHT_OFFSET)
    end

    draw_marker(entry, position, rotation, mode_label)
end

local function idle_settings()
    local radius = clamp(finite(mod:get("elevatormusic_idle_distance") or 10, 10), 2, 40)
    local full = clamp(finite(mod:get("elevatormusic_idle_full_distance") or 4, 4), 0.5, radius - 0.2)
    local hysteresis = math.max(0.5, radius * 0.2)
    return radius, radius + hysteresis, full
end

local function scaled_distance(value)
    if not value then
        return value
    end
    return value * DISTANCE_ATTENUATION_SCALE
end

local function base_volume()
    local percent = clamp(finite(mod:get("elevatormusic_volume_percent") or 100, 100), 5, 300)
    return clamp(percent / 100, 0.05, 3.0)
end

fade_ms = function()
    local seconds = finite(mod:get("elevatormusic_fade_seconds") or 1.5, 1.5)
    if seconds <= 0 then
        return 0
    end
    return math.floor(seconds * 1000)
end

local function idle_volume(distance, radius, full)
    radius = scaled_distance(radius or select(1, idle_settings()))
    full = scaled_distance(full or select(3, idle_settings()))

    local scale = 1.0
    if distance and distance > full then
        local span = math.max(radius - full, 0.001)
        scale = clamp(1 - (distance - full) / span, 0, 1)
    end

    return base_volume() * IDLE_VOLUME_SCALE * scale
end

local function activation_volume(distance, radius, full)
    radius = scaled_distance(radius or select(1, idle_settings()))
    full = scaled_distance(full or select(3, idle_settings()))

    local limit = clamp(radius * 1.5, full + 0.5, math.max(radius * 2, full + 0.5))
    if not distance then
        return base_volume()
    end
    if distance <= full then
        return base_volume()
    end
    if distance >= limit then
        return 0
    end

    local frac = (distance - full) / (limit - full)
    return base_volume() * (1 - frac)
end

local function volume_for_mode(mode, distance, radius, full)
    if mode == "activation" then
        return activation_volume(distance, radius, full)
    end
    return idle_volume(distance, radius, full)
end

local function release_spatial_override()
    if state.spatial_override_active and MiniAudio and MiniAudio.set_spatial_mode then
        pcall(MiniAudio.set_spatial_mode, MiniAudio, nil)
        state.spatial_override_active = false
    end
end

local function spatial_mode_ready()
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio then
        return false
    end

    local enabled = true
    if MiniAudio.get then
        local ok, value = pcall(MiniAudio.get, MiniAudio, "miniaudioaddon_spatial_mode")
        if ok then
            enabled = value ~= false
        end
    end

    if enabled then
        return true
    end

    if MiniAudio.set_spatial_mode then
        local ok, err = pcall(MiniAudio.set_spatial_mode, MiniAudio, true)
        if ok then
            state.spatial_override_active = true
            return true
        elseif mod:get("elevatormusic_debug") then
            mod:echo("[ElevatorMusic] Failed to force MiniAudio spatial mode: %s", tostring(err))
        end
    end

    return false
end

local function prewarm_daemon(force)
    MiniAudio = MiniAudio or get_mod("MiniAudioAddon")
    if not MiniAudio then
        return
    end
    register_miniaudio_watchers()

    local running = MiniAudio.is_daemon_running and MiniAudio:is_daemon_running()
    if running then
        if spatial_mode_ready() then
            state.daemon_ready = true
        else
            state.daemon_ready = false
        end
        return
    end

    state.daemon_ready = false
    if not spatial_mode_ready() then
        return
    end

    local current_time = now()
    if not force and state.next_daemon_check and state.next_daemon_check > current_time then
        return
    end
    state.next_daemon_check = current_time + 2

    if MiniAudio.daemon_start then
        log_api_event("daemon_start requested (force=%s)", tostring(force or false))
        local ok, started = pcall(MiniAudio.daemon_start, MiniAudio, nil, 1.0, 0.0)
        if ok and started then
            state.daemon_ready = true
            log_api_event("daemon_start succeeded")
        else
            log_api_event("daemon_start failed (%s)", tostring(started))
        end
    end
end

local function build_profile(mode, radius, full)
    radius = scaled_distance(radius or select(1, idle_settings()))
    full = scaled_distance(full or select(3, idle_settings()))

    local rolloff = mod:get("elevatormusic_spatial_rolloff") or "linear"
    if mode == "activation" then
        local min_distance = clamp(full * 0.75, 0.5, 25)
        local max_distance = clamp(radius * 3.0, min_distance + 1, 150)
        return {
            min_distance = min_distance,
            max_distance = max_distance,
            rolloff = rolloff,
        }
    end

    local min_distance = clamp(full * 0.6, 0.35, radius - 0.5)
    local max_distance = clamp(radius * 1.8, min_distance + 1, 90)
    return {
        min_distance = min_distance,
        max_distance = max_distance,
        rolloff = rolloff,
    }
end

local function stop_emitter(entry, reason)
    local emitter = entry and entry.emitter
    if not emitter then
        return
    end

    local fade = fade_ms()
    log_api_event(
        "stop request id=%s key=%s reason=%s fade=%s",
        tostring(emitter.id),
        tostring(entry.key or "unknown"),
        tostring(reason or "unknown"),
        tostring(fade or 0)
    )
    daemon_stop(emitter.id, fade)

    entry.emitter = nil
    visuals_detach(entry)

    if mod:get("elevatormusic_debug") then
        log_echo("[ElevatorMusic] Stopped %s (%s).", tostring(entry.key), tostring(reason or "unknown"))
    end

    sync_client_activity()
end

local function start_emitter(entry, mode, distance)
    if not mod:get("elevatormusic_enable") then
        return
    end

    prewarm_daemon()
    if not state.daemon_ready then
        return
    end

    local path = pick_track_path()
    if not path then
        return
    end

    local radius, _, full = idle_settings()
    local volume = volume_for_mode(mode, distance, radius, full)
    state.sequence = state.sequence + 1

    local emitter_state = {
        id = string.format("elevatormusic_%s_%d", tostring(entry.key), state.sequence),
        mode = mode,
        path = path,
        next_update = 0,
        linger_until = nil,
        linger_total = nil,
    }

    emitter_state.tracker = new_pose_tracker()
    if not emitter_state.tracker then
        if not state.pose_helpers_missing then
            log_error("[ElevatorMusic] MiniAudioAddon pose helpers unavailable; update MiniAudioAddon.")
            state.pose_helpers_missing = true
        end
        return
    end

    entry.emitter = emitter_state

    if not emitter_state.tracker:sample_unit(entry.unit) then
        entry.emitter = nil
        return
    end

    local source, position, rotation = emitter_state.tracker:source_payload()
    if not source then
        entry.emitter = nil
        return
    end

    local payload = {
        id = emitter_state.id,
        path = path,
        loop = true,
        volume = volume,
        profile = build_profile(mode, radius, full),
        source = source,
        listener = current_listener(),
        autoplay = true,
        require_listener = true,
        process_id = PROCESS_ID,
    }

    log_api_event(
        "start request key=%s mode=%s track=%s volume=%.3f distance=%s listener=%s",
        tostring(entry.key or "unknown"),
        tostring(mode),
        tostring(path),
        volume,
        distance and string.format("%.2f", distance) or "nil",
        payload.listener and "yes" or "no"
    )

    local ok, queued = daemon_play(payload)
    if not ok then
        if mod:get("elevatormusic_debug") then
            log_echo("[ElevatorMusic] Failed to start %s via daemon.", tostring(entry.key))
        end
        entry.emitter = nil
        return
    end
    emitter_state.pending_start = queued and true or false
    emitter_state.started = not emitter_state.pending_start

    draw_marker(entry, position, rotation, mode)
    visuals_attach(entry, position)
    log_api_event(
        "started id=%s key=%s mode=%s track=%s",
        tostring(payload.id),
        tostring(entry.key or "unknown"),
        tostring(mode),
        tostring(path)
    )

    if mod:get("elevatormusic_debug") then
        log_echo("[ElevatorMusic] Started %s -> %s (%s).", tostring(entry.key), path, mode)
    end

    sync_client_activity()
end

local function pick_test_track()
    scan_audio_folder()
    if #state.playlist > 0 then
        return state.playlist[1]
    end
    local folder = resolve_audio_folder()
    return folder and fallback_track_path(folder) or nil
end

local function ensure_test_marker_entry(test)
    if test.entry then
        return test.entry
    end

    local entry = { key = "test_emitter" }
    entry.pose_provider = function()
        if not state.test_emitter or not state.test_emitter.pose then
            return nil
        end
        return {
            position = state.test_emitter.pose,
            rotation = nil,
            offset = false,
        }
    end
    test.entry = entry
    return entry
end

local function compute_test_pose(test, dt)
    if not test then
        return nil
    end

    if dt and dt ~= 0 then
        test.elapsed = (test.elapsed or 0) + dt
    end

    local anchor = unbox_vec3(test.anchor_box)
    local forward = unbox_vec3(test.forward_box)
    local right = unbox_vec3(test.right_box)
    local up = unbox_vec3(test.up_box)
    if not anchor or not forward or not right or not up or not Vector3 then
        return nil
    end

    local center = anchor + forward * (test.forward_offset or 4)
    if test.height and test.height ~= 0 then
        center = center + up * test.height
    end

    local amplitude = test.amplitude or 4
    local speed = test.speed or 1
    local elapsed = test.elapsed or 0
    local phase = elapsed * speed
    local offset = math.sin(phase) * amplitude
    local position = center + right * offset

    local derivative = math.cos(phase)
    local direction = right
    if derivative < 0 and Vector3 then
        direction = right * -1
    end
    if Vector3.normalize and direction then
        direction = Vector3.normalize(direction)
    end

    return position, direction
end

local function start_test_emitter()
    if state.test_emitter or not mod:get("elevatormusic_test_emitter") then
        return
    end

    prewarm_daemon()
    if not state.daemon_ready then
        return
    end

    local track = pick_test_track()
    if not track then
        return
    end

    local position, forward, right, up = player_basis()
    if not position or not forward or not right or not up then
        return
    end

    state.sequence = state.sequence + 1
    local test = {
        id = string.format("elevatormusic_test_%d", state.sequence),
        path = track,
        amplitude = 5,
        forward_offset = 5,
        height = 1.5,
        speed = (2 * math.pi) / 6,
        follow_player = true,
        volume = base_volume(),
        elapsed = 0,
    }

    test.anchor_box = store_vec3(test.anchor_box, position)
    test.forward_box = store_vec3(test.forward_box, forward)
    test.right_box = store_vec3(test.right_box, right)
    test.up_box = store_vec3(test.up_box, up)

    ensure_test_marker_entry(test)

    local start_pos, direction = compute_test_pose(test, 0)
    if not start_pos then
        return
    end
    test.pose = start_pos
    if test.entry then
        visuals_attach(test.entry, start_pos)
    end

    local payload = {
        id = test.id,
        path = track,
        loop = true,
        volume = test.volume,
        profile = build_profile("activation"),
        source = {
            position = vec3_to_array(start_pos),
            forward = vec3_to_array(direction or forward),
            velocity = { 0, 0, 0 },
        },
        listener = current_listener(),
        autoplay = true,
        require_listener = true,
        process_id = PROCESS_ID,
    }

    local ok = call_api("play#test_emitter", "play", payload)
    if not ok then
        if test.entry then
            destroy_marker(test.entry)
            visuals_detach(test.entry)
        end
        return
    end

    state.test_emitter = test
    log_api_event("test_emitter started id=%s path=%s", tostring(test.id), tostring(track))
end

stop_test_emitter = function(reason)
    local test = state.test_emitter
    if not test then
        return
    end

    log_api_event("test_emitter stop id=%s reason=%s", tostring(test.id), tostring(reason or "unknown"))
    call_api("stop#test_emitter", "stop", { id = test.id, fade = fade_ms() })
    if test.entry then
        destroy_marker(test.entry)
        visuals_detach(test.entry)
    end
    state.test_emitter = nil
end

local function update_test_emitter(dt)
    if not mod:get("elevatormusic_enable") then
        if state.test_emitter then
            stop_test_emitter("disabled")
        end
        return
    end

    if not mod:get("elevatormusic_test_emitter") then
        if state.test_emitter then
            stop_test_emitter("setting_disabled")
        end
        return
    end

    if not state.test_emitter then
        start_test_emitter()
        return
    end

    local test = state.test_emitter
    if test.follow_player then
        local anchor_pos, forward, right, up = player_basis()
        if anchor_pos and forward and right and up then
            test.anchor_box = store_vec3(test.anchor_box, anchor_pos)
            test.forward_box = store_vec3(test.forward_box, forward)
            test.right_box = store_vec3(test.right_box, right)
            test.up_box = store_vec3(test.up_box, up)
        end
    end

    local position, direction = compute_test_pose(test, dt)
    if not position then
        stop_test_emitter("missing_pose")
        return
    end
    test.pose = position

    if test.entry then
        refresh_marker(test.entry, "test")
        visuals_update(test.entry, position)
    end

    local payload = {
        id = test.id,
        profile = build_profile("activation"),
        volume = test.volume,
        source = {
            position = vec3_to_array(position),
            forward = vec3_to_array(direction or unbox_vec3(test.forward_box) or { 0, 0, 1 }),
            velocity = { 0, 0, 0 },
        },
        listener = current_listener(),
    }

    local ok, reason = call_api("update#test_emitter", "update", payload)
    if not ok and reason == "unknown_track" then
        state.test_emitter = nil
        start_test_emitter()
    end
end

local function idle_allowed(distance)
    local enable_idle = mod:get("elevatormusic_idle_enabled")
    if not enable_idle then
        return false
    end
    if not distance then
        return false
    end
    local radius = idle_settings()
    return distance <= radius
end

local function update_emitter(entry, distance)
    local emitter = entry.emitter
    if not emitter then
        return
    end

    if emitter.next_update and emitter.next_update > now() then
        return
    end
    emitter.next_update = now() + emitter_update_interval()

    local tracker = emitter.tracker
    if not tracker then
        tracker = new_pose_tracker()
        emitter.tracker = tracker
    end

    if not tracker then
        if not state.pose_helpers_missing then
            log_error("[ElevatorMusic] MiniAudioAddon pose helpers unavailable; update MiniAudioAddon.")
            state.pose_helpers_missing = true
        end
        stop_emitter(entry, "unit_missing")
        return
    end

    if not tracker:sample_unit(entry.unit) then
        stop_emitter(entry, "unit_missing")
        return
    end

    local source, position, rotation = tracker:source_payload()
    if not source then
        stop_emitter(entry, "unit_missing")
        return
    end

    local radius, _, full = idle_settings()
    local target_volume = volume_for_mode(emitter.mode, distance, radius, full)

    if emitter.mode == "activation" and not entry.moving then
        if emitter.linger_until then
            local remaining = emitter.linger_until - now()
            if remaining <= 0 then
                emitter.linger_until = nil
                emitter.linger_total = nil
                if mod:get("elevatormusic_idle_after_activation") and idle_allowed(distance) then
                    emitter.mode = "idle"
                    target_volume = volume_for_mode("idle", distance, radius, full)
                else
                    stop_emitter(entry, "activation_complete")
                    return
                end
            else
                local span = emitter.linger_total or 1
                local fade = clamp(remaining / span, 0, 1)
                target_volume = target_volume * fade
            end
        else
            if mod:get("elevatormusic_idle_after_activation") and idle_allowed(distance) then
                emitter.mode = "idle"
                target_volume = volume_for_mode("idle", distance, radius, full)
            else
                stop_emitter(entry, "activation_stop")
                return
            end
        end
    end

    local payload = {
        id = emitter.id,
        volume = target_volume,
        profile = build_profile(emitter.mode, radius, full),
        source = source,
        listener = current_listener(),
    }

    local ok, reason = daemon_update(payload)
    if not ok then
        stop_emitter(entry, reason == "missing_track" and "lost_track" or "update_failed")
        return
    end

    draw_marker(entry, position, rotation, emitter.mode)
    visuals_update(entry, position)
end

local function ensure_platform_entry(self)
    local unit = self and self._unit
    if not unit then
        return nil
    end

    local key = unit_key(unit)
    if not key then
        return nil
    end

    local entry = state.platforms[key]
    if not entry then
        entry = {
            key = key,
            unit = unit,
            extension = self,
            direction = "none",
            moving = false,
            emitter = nil,
            last_distance = nil,
        }
        entry.pose_provider = function(target)
            local emitter_state = target and target.emitter
            local tracker = emitter_state and emitter_state.tracker
            if tracker then
                local _, position, rotation = tracker:source_payload()
                if position then
                    return {
                        position = position,
                        rotation = rotation,
                        offset = false,
                    }
                end
            end
            return nil
        end
        state.platforms[key] = entry
    else
        entry.unit = unit
        entry.extension = self
    end

    return entry
end

local function drop_platform(key, reason)
    local entry = state.platforms[key]
    if not entry then
        return
    end

    stop_emitter(entry, reason or "removed")
    destroy_marker(entry)

    state.platforms[key] = nil
end

local function handle_direction_event(self, direction)
    if not mod:get("elevatormusic_enable") then
        return
    end

    local entry = ensure_platform_entry(self)
    if not entry then
        return
    end

    local new_dir = direction_name(direction)
    entry.direction = new_dir
    entry.moving = new_dir ~= "none"

    if entry.emitter and entry.emitter.mode == "activation" and not entry.moving then
        local linger = clamp(finite(mod:get("elevatormusic_activation_linger") or 0, 0), 0, 20)
        if linger > 0 then
            entry.emitter.linger_total = linger
            entry.emitter.linger_until = now() + linger
        end
    elseif entry.moving and mod:get("elevatormusic_play_activation") then
        if entry.emitter then
            entry.emitter.mode = "activation"
            entry.emitter.linger_until = nil
            entry.emitter.linger_total = nil
        else
            start_emitter(entry, "activation", entry.last_distance)
        end
    end
end

local function update_platform(entry, player_pos)
    if not mod:get("elevatormusic_enable") then
        return
    end

    local unit = entry.unit
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        drop_platform(entry.key, "unit_dead")
        return
    end

    if entry.extension and entry.extension.story_direction then
        local current = direction_name(entry.extension:story_direction())
        entry.direction = current
        entry.moving = current ~= "none"
    end

    local distance = nil
    if player_pos and Vector3 and Vector3.distance then
        local pos = Unit.world_position(unit, 1)
        local ok, dist = pcall(Vector3.distance, pos, player_pos)
        if ok then
            distance = dist
        end
    end
    entry.last_distance = distance

    local wants_activation = entry.moving and mod:get("elevatormusic_play_activation")
    if wants_activation then
        if not entry.emitter then
            start_emitter(entry, "activation", distance)
        else
            entry.emitter.mode = "activation"
            entry.emitter.linger_until = nil
            entry.emitter.linger_total = nil
        end
        update_emitter(entry, distance)
        return
    end

    if entry.emitter and entry.emitter.mode == "activation" then
        update_emitter(entry, distance)
        return
    end

    if not mod:get("elevatormusic_idle_enabled") then
        if entry.emitter and entry.emitter.mode == "idle" then
            stop_emitter(entry, "idle_disabled")
        end
        return
    end

    local start_radius, stop_radius = idle_settings()
    local inside = distance and distance <= start_radius
    local outside = (not distance) or distance >= stop_radius

    if entry.emitter and entry.emitter.mode == "idle" then
        if outside then
            stop_emitter(entry, "idle_out_of_range")
            return
        end
        update_emitter(entry, distance)
        return
    end

    if inside then
        if not entry.emitter then
            start_emitter(entry, "idle", distance)
        else
            entry.emitter.mode = "idle"
        end
        update_emitter(entry, distance)
    end

    local marker_mode = (entry.emitter and entry.emitter.mode)
        or (entry.moving and "activation")
        or (mod:get("elevatormusic_idle_enabled") and "idle")
        or "off"
    refresh_marker(entry, marker_mode)
end

stop_all_emitters = function(reason)
    local had_active = false
    for _, entry in pairs(state.platforms) do
        if entry.emitter then
            had_active = true
            break
        end
    end

    if had_active then
        log_api_event("stop_all_emitters reason=%s", tostring(reason or "unknown"))
    end

    for key, entry in pairs(state.platforms) do
        stop_emitter(entry, reason)
        destroy_marker(entry)
    end

    stop_test_emitter(reason)
    local module = rainbow_module()
    if module and module.remove_all then
        module.remove_all()
    end
    state.visuals_warned = false

    sync_client_activity()
end

mod:hook_safe("MoveablePlatformExtension", "update", function(self)
    ensure_platform_entry(self)
end)

mod:hook_safe("MoveablePlatformExtension", "destroy", function(self)
    local key = unit_key(self._unit)
    if key then
        drop_platform(key, "platform_destroyed")
    end
end)

mod:hook_safe("MoveablePlatformExtension", "_set_direction", function(self, direction)
    handle_direction_event(self, direction)
end)

mod:hook_safe("MoveablePlatformExtension", "set_direction_husk", function(self, direction)
    handle_direction_event(self, direction)
end)

mod.update = function()
    local dt = delta_time()
    update_test_emitter(dt)
    visuals_tick(dt)

    if not mod:get("elevatormusic_enable") then
        stop_all_emitters("disabled")
        return
    end

    prewarm_daemon()

    local listener_pos = player_position()
    if not listener_pos then
        stop_all_emitters("no_player")
        return
    end

    for key, entry in pairs(state.platforms) do
        update_platform(entry, listener_pos)
    end
end

mod.on_enabled = function()
    reset_miniaudio("enabled", false)
    scan_audio_folder(true)
    prewarm_daemon(true)
end

mod.on_disabled = function()
    stop_all_emitters("mod_disabled")
    reset_miniaudio("mod_disabled", true)
end

mod.on_unload = function()
    stop_all_emitters("unload")
    reset_miniaudio("mod_unload", true)
end

mod.on_game_state_changed = function(status, state_name)
    if status == "enter" and state_name == "StateGameplay" then
        reset_miniaudio("enter_gameplay", false)
        scan_audio_folder(true)
        prewarm_daemon(true)
    elseif status == "exit" and state_name == "StateGameplay" then
        stop_all_emitters("leaving_gameplay")
        reset_miniaudio("leave_gameplay", false)
    end
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "elevatormusic_show_markers" then
        if not mod:get("elevatormusic_show_markers") then
            for _, entry in pairs(state.platforms) do
                clear_marker(entry)
            end
        end
    elseif setting_id == "elevatormusic_volume_percent" then
        for _, entry in pairs(state.platforms) do
            update_emitter(entry, entry.last_distance)
        end
    elseif setting_id == "elevatormusic_enable" then
        if not mod:get("elevatormusic_enable") then
            stop_all_emitters("setting_disabled")
            reset_miniaudio("setting_disabled", false)
        else
            scan_audio_folder(true)
            prewarm_daemon(true)
        end
    elseif setting_id == "elevatormusic_idle_enabled" or setting_id == "elevatormusic_play_activation" then
        if not mod:get(setting_id) then
            stop_all_emitters("setting_changed")
        end
    elseif setting_id == "elevatormusic_test_emitter" then
        if mod:get("elevatormusic_test_emitter") then
            start_test_emitter()
        else
            stop_test_emitter("setting_disabled")
        end
    elseif setting_id == "elevatormusic_visuals_enable"
        or setting_id == "elevatormusic_visuals_speed"
        or setting_id == "elevatormusic_visuals_randomness"
        or setting_id == "elevatormusic_visuals_radius" then
        if not mod:get("elevatormusic_visuals_enable") then
            state.visuals_warned = false
        end
        visuals_refresh_all()
    end
end

mod:command("elevatormusic_refresh", "Rescan mods/ElevatorMusic/audio for new files.", function()
    scan_audio_folder(true)
end)
--[[
    File: ElevatorMusic.lua
    Description: Main ElevatorMusic mod script that discovers elevator platforms,
    manages MiniAudio emitters, and coordinates playlist playback plus debug tooling.
    Overall Release Version: 0.5
    File Version: 0.5.0
]]
