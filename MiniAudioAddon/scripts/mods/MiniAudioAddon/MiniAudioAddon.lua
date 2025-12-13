local mod = get_mod("MiniAudioAddon")
local DLS = get_mod("DarktideLocalServer")

local cjson = rawget(_G, "cjson")
if not cjson then
    local ok, lib = pcall(require, "cjson")
    if ok then
        cjson = lib
    end
end

local Vector3 = rawget(_G, "Vector3")
local Vector3Box = rawget(_G, "Vector3Box")
local Quaternion = rawget(_G, "Quaternion")
local QuaternionBox = rawget(_G, "QuaternionBox")
local Matrix4x4 = rawget(_G, "Matrix4x4")
local Unit = rawget(_G, "Unit")
local World = rawget(_G, "World")
local LineObject = rawget(_G, "LineObject")

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

local Utils = try_load_module("MiniAudioAddon/scripts/mods/MiniAudioAddon/core/utils") or
    try_load_module("scripts/mods/MiniAudioAddon/core/utils") or
    try_load_module("core/utils")

if not Utils then
    mod:error("[MiniAudioAddon] Falling back to inline helpers; utility module unavailable.")
    Utils = {}
end

local safe_forward
local safe_up

local function fallback_clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

local function fallback_now()
    local ok, t = pcall(function()
        if Managers and Managers.time then
            return Managers.time:time("gameplay")
        end
    end)
    if ok and t then
        return t
    end
    return os.clock()
end

local function fallback_realtime_now()
    local ok, t = pcall(function()
        if Managers and Managers.time then
            return Managers.time:time("ui") or Managers.time:time("gameplay")
        end
    end)
    if ok and t then
        return t
    end
    return os.clock()
end

local function fallback_json_escape(str)
    if not str then
        return ""
    end

    return (tostring(str)
        :gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r"))
end

local function fallback_simple_json_encode(value)
    local value_type = type(value)
    if value_type == "table" then
        local is_array = true
        local max_index = 0

        for key in pairs(value) do
            if type(key) ~= "number" then
                is_array = false
                break
            end
            if key > max_index then
                max_index = key
            end
        end

        if is_array then
            local parts = {}
            for i = 1, max_index do
                parts[i] = fallback_simple_json_encode(value[i])
            end
            return string.format("[%s]", table.concat(parts, ","))
        end

        local entries = {}
        for k, v in pairs(value) do
            entries[#entries + 1] = string.format("\"%s\":%s", fallback_json_escape(k), fallback_simple_json_encode(v))
        end
        table.sort(entries)
        return string.format("{%s}", table.concat(entries, ","))
    elseif value_type == "string" then
        return string.format("\"%s\"", fallback_json_escape(value))
    elseif value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end

    return "null"
end

local function fallback_encode_json(payload)
    if cjson and cjson.encode then
        return pcall(cjson.encode, payload)
    end
    return true, fallback_simple_json_encode(payload)
end

local function fallback_direct_write_file(path, contents)
    local io_variants = {}
    local mods_io = rawget(_G, "Mods") and rawget(Mods, "lua") and rawget(Mods.lua, "io")
    if mods_io then
        io_variants[#io_variants + 1] = mods_io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        io_variants[#io_variants + 1] = global_io
    end

    for _, io_api in ipairs(io_variants) do
        if type(io_api) == "table" and type(io_api.open) == "function" then
            local ok, file_or_err = pcall(io_api.open, path, "wb")
            if ok and file_or_err then
                local file = file_or_err
                local wrote = pcall(function()
                    file:write(contents)
                    if file.flush then
                        file:flush()
                    end
                end)
                pcall(function()
                    if file.close then
                        file:close()
                    end
                end)
                if wrote then
                    return true
                end
            end
        end
    end

    return false
end

local function fallback_sanitize_for_format(value)
    if not value then
        return ""
    end
    return tostring(value):gsub("%%", "%%%%")
end

local function fallback_sanitize_for_ps_single(value)
    if not value then
        return ""
    end
    return tostring(value):gsub("'", "''")
end

local function fallback_vec3_to_array(v)
    if not v or not Vector3 then
        return { 0, 0, 0 }
    end

    return { Vector3.x(v), Vector3.y(v), Vector3.z(v) }
end

local function fallback_locate_popen()
    local candidates = {}
    local mods_io = rawget(_G, "Mods") and rawget(Mods, "lua") and rawget(Mods.lua, "io")
    if mods_io then
        candidates[#candidates + 1] = mods_io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        candidates[#candidates + 1] = global_io
    end

    for _, api in ipairs(candidates) do
        if type(api) == "table" and type(api.popen) == "function" then
            return function(cmd, mode)
                return api.popen(cmd, mode or "r")
            end
        end
    end

    return nil
end

local clamp = Utils.clamp or fallback_clamp
local now = Utils.now or fallback_now
local realtime_now = Utils.realtime_now or fallback_realtime_now
local encode_json_payload = Utils.encode_json or fallback_encode_json
local direct_write_file = Utils.direct_write_file or fallback_direct_write_file
local sanitize_for_format = Utils.sanitize_for_format or fallback_sanitize_for_format
local sanitize_for_ps_single = Utils.sanitize_for_ps_single or fallback_sanitize_for_ps_single
local vec3_to_array = Utils.vec3_to_array or fallback_vec3_to_array
local build_listener_payload = Utils.build_listener_payload
local locate_popen = Utils.locate_popen or fallback_locate_popen

if not build_listener_payload then
    local function listener_pose()
        if not Managers or not Managers.state or not Managers.state.camera or not Matrix4x4 then
            return nil, nil
        end

        local camera_manager = Managers.state.camera
        local player = Managers.player and Managers.player:local_player(1)
        if not player then
            return nil, nil
        end

        local viewport_name = player.viewport_name
        if not viewport_name then
            return nil, nil
        end

        local pose = camera_manager:listener_pose(viewport_name)
        if not pose then
            return nil, nil
        end

        local position = Matrix4x4.translation(pose)
        local rotation = Matrix4x4.rotation(pose)

        return position, rotation
    end

    build_listener_payload = function()
        local position, rotation = listener_pose()
        if not position or not rotation then
            return nil
        end

        return {
            position = vec3_to_array(position),
            forward = vec3_to_array(safe_forward(rotation)),
            up = vec3_to_array(safe_up(rotation)),
        }
    end
end
local USE_MINIAUDIO_DAEMON = true

local MINIAUDIO_DAEMON_EXE
local MINIAUDIO_DAEMON_CTL
local MINIAUDIO_PIPE_PAYLOAD
local MINIAUDIO_PIPE_DIRECTORY
local MOD_BASE_PATH = nil
local MOD_FILESYSTEM_PATH = nil
local MIN_TRANSPORT_SPEED = 0.125
local MAX_TRANSPORT_SPEED = 4.0

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
local DAEMON_WATCHDOG_WINDOW = 5.0
local DAEMON_WATCHDOG_COOLDOWN = 0.35
local DAEMON_STATUS_POLL_INTERVAL = 1.0
local PIPE_RETRY_MAX_ATTEMPTS = 60
local PIPE_RETRY_GRACE = 4.0
local PIPE_RETRY_DELAY = 0.05

local active_clients = {}
local generation_callback = nil
local reset_callback = nil

local spatial_test_state = nil
local spatial_test_stop
local update_spatial_test

local manual_track_path = nil
local manual_track_stop_pending = false
local manual_track_stop_message = nil
local manual_track_start_pending = false
local emitter_state = nil
local TRACK_IDS = {
    manual = "__miniaudio_manual",
    emitter = "__miniaudio_emitter",
}

local MARKER_SETTINGS = {
    emitter_unit = "core/units/cube",
    update_interval = 0.15,
    emitter_text = "miniaudio_emitter",
    spatial_text = "miniaudio_spatial",
    default_color = Vector3 and Vector3(255, 220, 80) or nil,
}

local SIMPLE_TEST = {
    tracks = {
        mp3 = "Audio\\test\\Free_Test_Data_2MB_MP3.mp3",
        wav = "Audio\\test\\Free_Test_Data_2MB_WAV.wav",
    },
    default = "mp3",
}

local emitter_marker_state = {
    text_category = MARKER_SETTINGS.emitter_text,
    label = "MiniAudio Emit",
    text_color = MARKER_SETTINGS.default_color,
}
local spatial_marker_state = {
    text_category = MARKER_SETTINGS.spatial_text,
    label = "MiniAudio Spatial",
    text_color = MARKER_SETTINGS.default_color,
}
local staged_payload_cleanups = {}

local ensure_daemon_paths
local ensure_daemon_ready_for_tests
local ensure_listener_payload
local ensure_daemon_active
local cleanup_emitter_state
local finalize_manual_track_stop
local finalize_emitter_stop
local finalize_spatial_test_stop

local run_shell_command

local function noop() end
local notify_generation_reset = noop

local function debug_enabled()
    return mod:get("miniaudioaddon_debug")
end

local function bump_daemon_generation(reason)
    daemon_generation = daemon_generation + 1
    notify_generation_reset(daemon_generation, reason or "generation bump")
    return daemon_generation
end

local function unbox_vector(boxed)
    if Vector3Box and boxed and boxed.unbox then
        local ok, value = pcall(boxed.unbox, boxed)
        if ok and value then
            return value
        end
    end
    return boxed
end

safe_forward = function(rot)
    if not Quaternion or not Vector3 then
        return { 0, 0, 1 }
    end

    if not rot then
        return Vector3.normalize(Vector3(0, 0, 1))
    end

    local ok, forward = pcall(Quaternion.forward, rot)
    if ok and forward then
        return Vector3.normalize(forward)
    end

    return Vector3.normalize(Vector3(0, 0, 1))
end

safe_up = function(rot)
    if not Quaternion or not Vector3 then
        return { 0, 1, 0 }
    end

    if not rot then
        return Vector3(0, 1, 0)
    end

    local ok, up = pcall(Quaternion.up, rot)
    if ok and up then
        return Vector3.normalize(up)
    end

    return Vector3(0, 1, 0)
end

local function listener_pose()
    if not Managers or not Managers.state or not Managers.state.camera or not Matrix4x4 then
        return nil, nil
    end

    local camera_manager = Managers.state.camera
    local player = Managers.player and Managers.player:local_player(1)
    if not player then
        return nil, nil
    end

    local viewport_name = player.viewport_name
    if not viewport_name then
        return nil, nil
    end

    local pose = camera_manager:listener_pose(viewport_name)
    if not pose then
        return nil, nil
    end

    local position = Matrix4x4.translation(pose)
    local rotation = Matrix4x4.rotation(pose)

    return position, rotation
end

local function daemon_control_values(volume_linear, pan)
    local clamped_volume = math.max(0.0, math.min(volume_linear or 1.0, 3.0))
    local clamped_pan = math.max(-1.0, math.min(pan or 0.0, 1.0))
    return math.floor(clamped_volume * 100 + 0.5), clamped_pan, clamped_volume
end

local daemon_popen = locate_popen()
local daemon_stdio = nil
local daemon_stdio_mode = nil

local function close_daemon_stdio(reason)
    if not daemon_stdio then
        return
    end

    local ok, err = pcall(function()
        if daemon_stdio.flush then
            daemon_stdio:flush()
        end
        if daemon_stdio.close then
            daemon_stdio:close()
        end
    end)

    if debug_enabled() then
        if ok then
            mod:echo("[MiniAudioAddon] Closed daemon stdin (%s).", tostring(reason or "unknown"))
        else
            mod:error("[MiniAudioAddon] Failed to close daemon stdin (%s): %s", tostring(reason), tostring(err))
        end
    end

    daemon_stdio = nil
    daemon_stdio_mode = nil
end

local function send_via_stdin(encoded)
    if not daemon_stdio then
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
        daemon_stdio:write(line)
        if daemon_stdio.flush then
            daemon_stdio:flush()
        end
    end)

    if not ok then
        if debug_enabled() then
            mod:error("[MiniAudioAddon] Failed to write to daemon stdin: %s", tostring(err))
        end
        close_daemon_stdio("stdin_write_failed")
        return false
    end

    return true
end

local function delete_file(path)
    if not path or path == "" then
        return false
    end

    local ok, result = pcall(os.remove, path)
    if not ok then
        return false
    end

    return result ~= nil
end

local function stage_pipe_payload(_)
    return nil
end

local function remove_staged_payload_entry(_)
end

local function cleanup_staged_payload(_)
end

local function purge_payload_files()
    staged_payload_cleanups = {}
    return true
end

local function log_last_play_payload(encoded)
    if not encoded or encoded == "" or not MINIAUDIO_PIPE_DIRECTORY then
        return
    end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local payload = string.format("-- %s\n%s\n", timestamp or "", encoded)
    local debug_path = MINIAUDIO_PIPE_DIRECTORY .. "miniaudio_dt_last_play.json"
    direct_write_file(debug_path, payload)
end

local function clear_manual_override(reason)
    if not daemon_manual_override then
        return
    end

    if reason and debug_enabled() then
        mod:echo("[MiniAudioAddon] Manual daemon override cleared (%s).", tostring(reason))
    end

    daemon_manual_override = nil
end

local function apply_manual_override(volume_linear, pan)
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

local function next_pipe_name()
    local timestamp = os.time() or 0
    local random_part = math.random(10000, 99999)
    return string.format("miniaudio_dt_%d_%d", timestamp, random_part)
end

local function daemon_is_active()
    return daemon_is_running or daemon_pending_start or daemon_has_known_process
end

ensure_daemon_active = function(path_hint)
    if daemon_is_active() then
        return true
    end

    if ensure_daemon_ready_for_tests then
        return ensure_daemon_ready_for_tests(path_hint)
    end

    return false
end

local function spatial_mode_enabled()
    if mod._forced_spatial ~= nil then
        return mod._forced_spatial
    end
    return mod:get("miniaudioaddon_spatial_mode")
end

function mod:set_spatial_mode(enabled)
    mod._forced_spatial = enabled
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
    return clamp(scale, 0.5, 4.0)
end

run_shell_command = function(cmd, why, opts)
    opts = opts or {}
    local ran = false

    local function try_dls()
        if ran or opts.local_only then
            return
        end

        if DLS and DLS.run_command then
            local ok = pcall(DLS.run_command, cmd)
            if ok then
                ran = true
            end
        end
    end

    local function try_local()
        if ran or opts.dls_only then
            return
        end

        local os_ok, os_result = pcall(os.execute, cmd)
        if os_ok and os_result then
            ran = true
        end
    end

    if opts.prefer_local then
        try_local()
        if not ran then
            try_dls()
        end
    else
        try_dls()
        if not ran then
            try_local()
        end
    end

    if not ran and why and debug_enabled() then
        mod:error("[MiniAudioAddon] Command failed (%s): %s", why, cmd)
    end

    return ran
end

local function send_via_pipe_client(payload)
    if not daemon_pipe_name or not payload or payload == "" then
        return false
    end

    if not ensure_daemon_paths() then
        mod:error("[MiniAudioAddon] Pipe write requested before daemon paths resolved.")
        return false
    end

    local payload_block = sanitize_for_format(payload)
    local exe_path_ps = sanitize_for_ps_single(MINIAUDIO_DAEMON_EXE)
    local pipe_ps = sanitize_for_ps_single(daemon_pipe_name)

    local command = string.format(
        [[powershell -NoLogo -NoProfile -Command "& { $payload = @'
%s
'@; & '%s' --pipe-client --pipe '%s' --payload $payload }"]],
        payload_block,
        exe_path_ps,
        pipe_ps
    )

    local succeeded = run_shell_command and run_shell_command(command, "daemon pipe client", { prefer_local = true })
    if not succeeded and debug_enabled() then
        mod:error("[MiniAudioAddon] Pipe client invocation failed.")
    end

    return succeeded or false
end

local function deliver_daemon_payload(encoded)
    if send_via_stdin(encoded) then
        return true
    end

    return send_via_pipe_client(encoded)
end

local function handle_daemon_stop_delivery(info)
    if not info or info.cmd ~= "stop" then
        return
    end

    if info.id == TRACK_IDS.manual then
        finalize_manual_track_stop()
        return
    end

    if emitter_state and emitter_state.track_id == info.id then
        finalize_emitter_stop()
        return
    end

    if spatial_test_state and spatial_test_state.track_id == info.id then
        finalize_spatial_test_stop()
    end
end

local function handle_daemon_stop_failure(info)
    if not info or info.cmd ~= "stop" then
        return
    end

    if info.id == TRACK_IDS.manual then
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

    if spatial_test_state and spatial_test_state.track_id == info.id then
        spatial_test_state.stopping = false
        if spatial_test_state.stop_message and not spatial_test_state.stop_silent then
            mod:echo("[MiniAudioAddon] Failed to stop the spatial test; run /miniaudio_spatial_test stop again.")
        end
    end
end

local function handle_daemon_payload_delivery(info)
    if not info or info.cmd ~= "play" then
        return
    end

    if info.id == TRACK_IDS.manual then
        manual_track_start_pending = false
    end

    if emitter_state and emitter_state.track_id == info.id then
        emitter_state.pending_start = false
        emitter_state.started = true
        emitter_state.next_update = realtime_now()
    end

    if spatial_test_state and spatial_test_state.track_id == info.id then
        spatial_test_state.pending_start = false
        spatial_test_state.started = true
    end
end

local function handle_daemon_play_failure(info)
    if not info or info.cmd ~= "play" then
        return
    end

    if info.id == TRACK_IDS.manual then
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

    if spatial_test_state and spatial_test_state.track_id == info.id then
        spatial_test_stop("start_failed", true)
        mod:echo("[MiniAudioAddon] Spatial test start request failed; try again.")
    end
end

local function daemon_send_json(payload)
    if not payload then
        return false, "missing_payload"
    end

    if not spatial_mode_enabled() then
        return false, "spatial_disabled"
    end

    local daemon_ready = daemon_is_active()
    if not daemon_ready then
        if payload.cmd == "play" then
            if not ensure_daemon_active(payload.path) then
                return false, "daemon_unavailable"
            end
            daemon_ready = daemon_is_active()
        else
            if debug_enabled() then
                mod:echo("[MiniAudioAddon] Ignoring cmd=%s (daemon offline).", tostring(payload.cmd))
            end
            return false, "daemon_offline"
        end
    end

    local ok, encoded, encode_err = encode_json_payload(payload)
    if not ok or not encoded then
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

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] Daemon send cmd=%s id=%s", tostring(payload.cmd), tostring(payload.id))
    end

    if payload.cmd == "play" then
        log_last_play_payload(encoded)
    end

    if deliver_daemon_payload(encoded) then
        handle_daemon_payload_delivery(payload)
        handle_daemon_stop_delivery(payload)
        return true, false
    end

    daemon_pending_messages[#daemon_pending_messages + 1] = {
        encoded = encoded,
        attempts = 1,
        created = realtime_now(),
        next_attempt = realtime_now() + PIPE_RETRY_DELAY,
        cmd = payload.cmd,
        id = payload.id,
        payload = payload,
    }

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] Daemon send deferred (cmd=%s id=%s); waiting for IPC.", tostring(payload.cmd), tostring(payload.id))
    end

    return true, true
end

local function flush_pending_daemon_messages()
    if not spatial_mode_enabled() then
        return
    end

    local idx = 1
    while idx <= #daemon_pending_messages do
        local entry = daemon_pending_messages[idx]
        local rt_now = realtime_now()
        if entry.next_attempt and rt_now < entry.next_attempt then
            idx = idx + 1
        elseif deliver_daemon_payload(entry.encoded) then
            handle_daemon_payload_delivery(entry.payload or entry)
            handle_daemon_stop_delivery(entry.payload or entry)
            table.remove(daemon_pending_messages, idx)
        else
            entry.attempts = entry.attempts + 1
            entry.next_attempt = rt_now + PIPE_RETRY_DELAY

            local attempts_exceeded = entry.attempts > PIPE_RETRY_MAX_ATTEMPTS
            local grace_expired = entry.created and (rt_now - entry.created) > PIPE_RETRY_GRACE
            local daemon_ready = daemon_is_running or daemon_has_known_process

            if attempts_exceeded and (daemon_ready or grace_expired) then
                handle_daemon_play_failure(entry.payload or entry)
                handle_daemon_stop_failure(entry.payload or entry)
                table.remove(daemon_pending_messages, idx)
            else
                idx = idx + 1
            end
        end
    end
end

local function default_profile()
    local scale = mod:spatial_distance_scale()
    local min_distance = clamp(1 * scale, 0.25, 50)
    local max_distance = clamp(30 * scale, min_distance + 1, 200)
    return {
        min_distance = min_distance,
        max_distance = max_distance,
        rolloff = mod:get("miniaudioaddon_spatial_rolloff") or "linear",
    }
end
local function daemon_track_profile(profile)
    profile = profile or {}
    local defaults = default_profile()
    return {
        min_distance = profile.min_distance or defaults.min_distance,
        max_distance = profile.max_distance or defaults.max_distance,
        rolloff = profile.rolloff or defaults.rolloff,
    }
end

local function daemon_spatial_effects(overrides)
    overrides = overrides or {}
    local effects = {}
    if overrides.occlusion ~= nil then
        effects.occlusion = clamp(overrides.occlusion, 0, 1)
    else
        effects.occlusion = mod:get("miniaudioaddon_spatial_occlusion") or 0
    end

    if overrides.pan_override ~= nil then
        effects.pan_override = clamp(overrides.pan_override, -1, 1)
    end

    if overrides.doppler ~= nil then
        effects.doppler = math.max(0, overrides.doppler)
    end

    if overrides.directional_attenuation ~= nil then
        effects.directional_attenuation = clamp(overrides.directional_attenuation, 0, 1)
    end

    if overrides.cone then
        effects.cone = {
            inner = clamp(overrides.cone.inner or 360, 0, 360),
            outer = clamp(overrides.cone.outer or overrides.cone.inner or 360, 0, 360),
            outer_gain = clamp(overrides.cone.outer_gain or 0, 0, 1),
        }
    end

    return effects
end

local function apply_transport_fields(payload, track)
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
    if speed then
        payload.speed = clamp(speed, MIN_TRANSPORT_SPEED, MAX_TRANSPORT_SPEED)
    end

    if track.reverse ~= nil then
        payload.reverse = track.reverse and true or false
    end

    if track.autoplay ~= nil then
        payload.autoplay = track.autoplay and true or false
    end
end

local function schedule_daemon_watchdog()
    daemon_watchdog_until = realtime_now() + DAEMON_WATCHDOG_WINDOW
    daemon_watchdog_next_attempt = 0
end

local function has_internal_activity()
    if manual_track_path or manual_track_stop_pending then
        return true
    end

    if emitter_state or spatial_test_state then
        return true
    end

    return daemon_pending_messages and #daemon_pending_messages > 0
end

local function daemon_is_idle()
    return next(active_clients) == nil and not has_internal_activity()
end

local function clear_daemon_watchdog()
    daemon_watchdog_until = 0
    daemon_watchdog_next_attempt = 0
end

local function kill_daemon_process(pid)
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
    if run_shell_command and run_shell_command(taskkill_cmd, "daemon taskkill", { prefer_local = true }) then
        return
    end

    local powershell_cmd = string.format([[powershell -NoLogo -NoProfile -Command "Stop-Process -Id %s -Force" ]], tostring(numeric_pid))
    if run_shell_command then
        run_shell_command(powershell_cmd, "daemon stop-process", { prefer_local = true, local_only = true })
    else
        pcall(os.execute, powershell_cmd)
    end
end

local function decode_json_payload(payload)
    if type(payload) ~= "string" then
        return payload, nil
    end

    if not (cjson and cjson.decode) then
        return nil, "cjson module unavailable"
    end

    local ok, decoded = pcall(cjson.decode, payload)
    if not ok then
        return nil, decoded or "decode failed"
    end

    return decoded, nil
end

local function reset_daemon_status(reason)
    if (daemon_is_running or daemon_pending_start or daemon_pid) and debug_enabled() then
        mod:echo("[MiniAudioAddon] Daemon status reset (%s).", tostring(reason))
    end

    close_daemon_stdio(reason or "reset")
    local pending = daemon_pending_messages
    if pending and #pending > 0 then
        for _, entry in ipairs(pending) do
            handle_daemon_stop_failure(entry)
        end
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
    staged_payload_cleanups = {}

    if manual_track_path or manual_track_stop_pending then
        manual_track_path = nil
        manual_track_stop_pending = false
        manual_track_stop_message = nil
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Manual daemon playback cleared (%s).", tostring(reason or "daemon_reset"))
        end
    end

    if emitter_state then
        destroy_spawned_unit(emitter_state.unit)
        emitter_state = nil
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Emitter state cleared (%s).", tostring(reason or "daemon_reset"))
        end
    end

    if spatial_test_state then
        spatial_test_state = nil
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Spatial test state cleared (%s).", tostring(reason or "daemon_reset"))
        end
    end

    if reset_callback then
        pcall(reset_callback, reason)
    end
end

notify_generation_reset = function(generation, reason)
    if generation_callback then
        local ok, err = pcall(generation_callback, generation, reason)
        if not ok and debug_enabled() then
            mod:error("[MiniAudioAddon] generation callback failed: %s", tostring(err))
        end
    end
end

local function get_mod_base_path()
    if MOD_BASE_PATH then
        return MOD_BASE_PATH
    end

    -- Construct the mod path from the mod name
    local mod_name = mod:get_name()
    if not mod_name then
        return nil
    end

    local path = string.format("mods/%s/", mod_name)
    MOD_BASE_PATH = path
    return MOD_BASE_PATH
end

local function file_exists(path)
    if not path or path == "" then
        return false
    end

    local variants = {}
    local mods_io = rawget(_G, "Mods")
    mods_io = mods_io and mods_io.lua and mods_io.lua.io
    if mods_io then
        variants[#variants + 1] = mods_io
    end

    local global_io = rawget(_G, "io")
    if global_io then
        variants[#variants + 1] = global_io
    end

    for _, io_api in ipairs(variants) do
        if type(io_api) == "table" and type(io_api.open) == "function" then
            local ok, file_or_err = pcall(io_api.open, path, "rb")
            if ok and file_or_err then
                local file = file_or_err
                pcall(function()
                    if file.close then
                        file:close()
                    end
                end)
                return true
            end
        end
    end

    return false
end

local function prefer_existing_path(candidates)
    for _, candidate in ipairs(candidates) do
        if file_exists(candidate) then
            return candidate
        end
    end
    return nil
end

local function prefer_path_with_fallback(candidates)
    local fallback = nil

    for _, candidate in ipairs(candidates) do
        if candidate and candidate ~= "" then
            fallback = fallback or candidate
            if file_exists(candidate) then
                return candidate
            end
        end
    end

    return fallback
end

local function sanitize_path(path)
    if not path then
        return nil
    end
    path = tostring(path)
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    if #path == 0 then
        return nil
    end
    if path:sub(1, 1) == '"' then
        path = path:sub(2)
    end
    if path:sub(-1) == '"' then
        path = path:sub(1, -2)
    end
    if path:sub(1, 1) == "'" then
        path = path:sub(2)
    end
    if path:sub(-1) == "'" then
        path = path:sub(1, -2)
    end
    return path
end

local function directory_of(path)
    if not path then
        return nil
    end

    local idx = path:match(".*()[/\\]")
    if not idx then
        return nil
    end

    return path:sub(1, idx)
end

local function normalize_directory(path)
    if not path then
        return nil
    end

    if path:sub(-1) == "\\" or path:sub(-1) == "/" then
        return path:sub(1, -2)
    end

    return path
end

local function wrap_daemon_command(command)
    if not command or command == "" then
        return command
    end

    local exe_dir = MINIAUDIO_DAEMON_EXE and normalize_directory(directory_of(MINIAUDIO_DAEMON_EXE))
    if not exe_dir or exe_dir == "" then
        return command
    end

    local is_windows = package and package.config and package.config:sub(1, 1) == "\\"
    if is_windows then
        return string.format('cd /d "%s" && %s', exe_dir, command)
    end

    return string.format('cd "%s" && %s', exe_dir, command)
end

local function parent_directory(path)
    if not path then
        return nil
    end

    local trimmed = path
    if trimmed:sub(-1) == "\\" or trimmed:sub(-1) == "/" then
        trimmed = trimmed:sub(1, -2)
    end

    return directory_of(trimmed)
end

local function ensure_trailing_separator(path)
    if not path or path == "" then
        return path
    end

    local last = path:sub(-1)
    if last == "\\" or last == "/" then
        return path
    end

    return path .. "\\"
end

local function join_path(base, fragment)
    if not base or not fragment or fragment == "" then
        return nil
    end

    fragment = fragment:gsub("^[/\\]+", "")
    fragment = fragment:gsub("/", "\\")
    return ensure_trailing_separator(base) .. fragment
end

local function get_mod_filesystem_path()
    if MOD_FILESYSTEM_PATH then
        return MOD_FILESYSTEM_PATH
    end

    if not DLS or not DLS.get_mod_path then
        return nil
    end

    local marker = DLS.get_mod_path(mod, "MiniAudioAddon.mod", false)
        or DLS.get_mod_path(mod, "MiniAudioAddon.mod", true)

    if not marker then
        return nil
    end

    marker = sanitize_path(marker)
    local directory = directory_of(marker)
    if not directory then
        return nil
    end

    MOD_FILESYSTEM_PATH = directory
    return MOD_FILESYSTEM_PATH
end

local function is_absolute_path(path)
    if not path then
        return false
    end
    return path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
end

local function expand_track_path(path)
    local sanitized = sanitize_path(path)
    if not sanitized or sanitized == "" then
        return nil
    end

    if is_absolute_path(sanitized) then
        return file_exists(sanitized) and sanitized or nil
    end

    local candidates = {}
    candidates[#candidates + 1] = sanitized

    local normalized = sanitized:gsub("/", "\\")
    if normalized ~= sanitized then
        candidates[#candidates + 1] = normalized
    end

    local base = get_mod_filesystem_path()
    if base then
        candidates[#candidates + 1] = join_path(base, normalized)
        candidates[#candidates + 1] = join_path(base, sanitized)
        candidates[#candidates + 1] = join_path(base, "Audio\\" .. normalized)
        candidates[#candidates + 1] = join_path(base, "audio\\" .. normalized)
    end

    return prefer_existing_path(candidates)
end

local function destroy_spawned_unit(unit)
    if not unit then
        return
    end

    local spawner = Managers and Managers.state and Managers.state.unit_spawner
    if spawner and spawner.mark_for_deletion then
        local ok = pcall(spawner.mark_for_deletion, spawner, unit)
        if ok then
            return
        end
    end

    local world = Managers and Managers.world and Managers.world:world("level_world")
    if world and World and Unit and Unit.alive and Unit.alive(unit) then
        pcall(World.destroy_unit, world, unit)
    end
end

local function spawn_debug_unit(unit_name, position, rotation)
    if not unit_name then
        return nil
    end

    local spawner = Managers and Managers.state and Managers.state.unit_spawner
    if spawner and spawner.spawn_unit then
        local ok, unit = pcall(spawner.spawn_unit, spawner, unit_name, position, rotation)
        if ok and unit then
            return unit
        end
    end

    if not Managers or not Managers.world or not World then
        return nil
    end

    local world = Managers.world:world("level_world")
    if not world then
        return nil
    end

    local ok, unit = pcall(World.spawn_unit_ex, world, unit_name, nil, position, rotation)
    if ok then
        return unit
    end

    return nil
end

local function ensure_marker_line_object(state)
    if not LineObject or not World or not Managers or not Managers.world then
        return nil, nil
    end

    local world = Managers.world:world("level_world")
    if not world then
        return nil, nil
    end

    if not state.line_object or state.line_world ~= world then
        local ok, line_object = pcall(World.create_line_object, world)
        if not ok or not line_object then
            return nil, nil
        end
        state.line_object = line_object
        state.line_world = world
    end

    return state.line_object, state.line_world
end

local function clear_marker(state)
    if not state then
        return
    end

    if state.line_object and state.line_world and LineObject then
        LineObject.reset(state.line_object)
        LineObject.dispatch(state.line_world, state.line_object)
    end

    local debug_text = Managers and Managers.state and Managers.state.debug_text
    if debug_text and debug_text.clear_world_text and state.text_category then
        debug_text:clear_world_text(state.text_category)
    end
end

local function draw_marker(state, position, rotation)
    if not state then
        return
    end

    if not mod:debug_markers_enabled() then
        clear_marker(state)
        return
    end

    if not position then
        clear_marker(state)
        return
    end

    local line_object, world = ensure_marker_line_object(state)
    if line_object and world and LineObject.add_sphere then
        LineObject.reset(line_object)
    local Color = rawget(_G, "Color")
    local sphere_color = Color and Color(255, 255, 200, 80) or nil
        LineObject.add_sphere(line_object, sphere_color, position, 0.3, 16, 12)

        if rotation and Vector3 and Vector3.normalize then
            local forward = safe_forward(rotation)
            local up = safe_up(rotation)
            local right = Vector3.normalize(Vector3.cross(forward, up))
            local tip = position + forward * 0.6
            local left_tip = tip - right * 0.15
            local right_tip = tip + right * 0.15
            local Color = rawget(_G, "Color")
            local color = Color and Color(255, 255, 140, 40) or nil
            LineObject.add_line(line_object, color, position, tip)
            LineObject.add_line(line_object, color, tip, left_tip)
            LineObject.add_line(line_object, color, tip, right_tip)
        end

        LineObject.dispatch(world, line_object)
    end

    local debug_text = Managers and Managers.state and Managers.state.debug_text
    if debug_text and debug_text.output_world_text and Vector3 and state.text_category then
        local label_position = position + Vector3(0, 0, 0.45)
        local color = state.text_color or MARKER_SETTINGS.default_color or Vector3(255, 220, 80)
        debug_text:output_world_text(state.label or "MiniAudio Marker", 0.08, label_position, 0.12, state.text_category, color)
    end
end

local function draw_emitter_marker(position, rotation)
    draw_marker(emitter_marker_state, position, rotation)
end

local function clear_emitter_marker()
    clear_marker(emitter_marker_state)
end

local function draw_spatial_marker(position)
    draw_marker(spatial_marker_state, position, nil)
end

local function clear_spatial_marker()
    clear_marker(spatial_marker_state)
end

ensure_daemon_paths = function()
    if MINIAUDIO_DAEMON_EXE and MINIAUDIO_DAEMON_CTL then
        return true
    end

    local previous_pipe_directory = MINIAUDIO_PIPE_DIRECTORY
    if not DLS then
        return false
    end

    local mod_fs = get_mod_filesystem_path()
    if not mod_fs then
        return false
    end

    local addon_parent = parent_directory(mod_fs)
    local sibling_audio_base = addon_parent and join_path(addon_parent, "Audio")
    local local_audio_bin = nil

    if mod_fs then
        local_audio_bin = join_path(mod_fs, "Audio\\bin\\") or join_path(mod_fs, "audio\\bin\\")
        if local_audio_bin and local_audio_bin ~= "" then
            local_audio_bin = ensure_trailing_separator(local_audio_bin)
        end
    end

    if not MINIAUDIO_DAEMON_EXE then
        local exe_candidates = {
            join_path(mod_fs, "Audio\\bin\\miniaudio_dt.exe"),
            join_path(mod_fs, "audio\\bin\\miniaudio_dt.exe"),
            join_path(mod_fs, "Audio\\miniaudio_dt.exe"),
            join_path(mod_fs, "audio\\miniaudio_dt.exe"),
        }

        if sibling_audio_base then
            exe_candidates[#exe_candidates + 1] = join_path(sibling_audio_base, "bin\\miniaudio_dt.exe")
            exe_candidates[#exe_candidates + 1] = join_path(sibling_audio_base, "Audio\\bin\\miniaudio_dt.exe")
            exe_candidates[#exe_candidates + 1] = join_path(sibling_audio_base, "audio\\bin\\miniaudio_dt.exe")
        end

        MINIAUDIO_DAEMON_EXE = prefer_existing_path(exe_candidates)
    end

    if local_audio_bin then
        MINIAUDIO_DAEMON_CTL = local_audio_bin .. "miniaudio_dt.ctl"
    end

    if not MINIAUDIO_DAEMON_CTL then
        local ctl_candidates = {}

        local exe_dir = MINIAUDIO_DAEMON_EXE and directory_of(MINIAUDIO_DAEMON_EXE) or nil
        if exe_dir then
            ctl_candidates[#ctl_candidates + 1] = ensure_trailing_separator(exe_dir) .. "miniaudio_dt.ctl"
        end

        if mod_fs then
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "Audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "Audio\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(mod_fs, "audio\\miniaudio_dt.ctl")
        end

        if sibling_audio_base then
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "Audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "audio\\bin\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "Audio\\miniaudio_dt.ctl")
            ctl_candidates[#ctl_candidates + 1] = join_path(sibling_audio_base, "audio\\miniaudio_dt.ctl")
        end

        MINIAUDIO_DAEMON_CTL = prefer_path_with_fallback(ctl_candidates)
    end

    if MINIAUDIO_DAEMON_CTL and not file_exists(MINIAUDIO_DAEMON_CTL) then
        local default_payload = "volume=1.000\r\npan=0.000\r\nstop=0\r\n"
        if not direct_write_file(MINIAUDIO_DAEMON_CTL, default_payload) then
            mod:error("[MiniAudioAddon] Failed to create control file at %s", tostring(MINIAUDIO_DAEMON_CTL))
            return false
        end
    end

    if local_audio_bin then
        MINIAUDIO_PIPE_PAYLOAD = local_audio_bin .. "miniaudio_dt_payload.txt"
        MINIAUDIO_PIPE_DIRECTORY = local_audio_bin
    end

    if MINIAUDIO_DAEMON_CTL and not MINIAUDIO_PIPE_PAYLOAD then
        local base_dir = directory_of(MINIAUDIO_DAEMON_CTL)
        if not base_dir and MINIAUDIO_DAEMON_EXE then
            base_dir = directory_of(MINIAUDIO_DAEMON_EXE)
        end
        if base_dir then
            MINIAUDIO_PIPE_PAYLOAD = join_path(base_dir, "miniaudio_dt_payload.txt")
        end
    end

    if MINIAUDIO_PIPE_PAYLOAD and not MINIAUDIO_PIPE_DIRECTORY then
        local pipe_dir = directory_of(MINIAUDIO_PIPE_PAYLOAD)
        if pipe_dir and pipe_dir ~= "" then
            MINIAUDIO_PIPE_DIRECTORY = ensure_trailing_separator(pipe_dir)
        end
    end

    if MINIAUDIO_PIPE_DIRECTORY and MINIAUDIO_PIPE_DIRECTORY ~= previous_pipe_directory then
        purge_payload_files()
    end

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] EXE=%s", tostring(MINIAUDIO_DAEMON_EXE))
        mod:echo("[MiniAudioAddon] CTL=%s", tostring(MINIAUDIO_DAEMON_CTL))
    end

    return MINIAUDIO_DAEMON_EXE ~= nil and MINIAUDIO_DAEMON_CTL ~= nil
end

local function daemon_log_path()
    if not ensure_daemon_paths() then
        return nil
    end

    local base_dir = MINIAUDIO_DAEMON_EXE and directory_of(MINIAUDIO_DAEMON_EXE) or nil
    if not base_dir or base_dir == "" then
        base_dir = MINIAUDIO_DAEMON_CTL and directory_of(MINIAUDIO_DAEMON_CTL) or nil
    end
    if not base_dir or base_dir == "" then
        return nil
    end

    return ensure_trailing_separator(base_dir) .. "miniaudio_dt_log.txt"
end

local function clear_daemon_log_file(reason)
    local path = daemon_log_path()
    if not path then
        return false
    end

    local ok = direct_write_file(path, "")
    if ok then
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Cleared daemon log (%s).", tostring(reason or "unknown"))
        end
        return true
    end

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] Failed to clear daemon log (%s).", tostring(reason or "unknown"))
    end
    return false
end

local function daemon_write_control(volume_linear, pan, stop_flag, opts)
    if not USE_MINIAUDIO_DAEMON then
        return false
    end

    if not ensure_daemon_paths() then
        mod:error("[MiniAudioAddon] daemon_write_control: cannot resolve daemon paths.")
        return false
    end

    local volume_percent, clamped_pan, clamped_volume = daemon_control_values(volume_linear, pan)
    volume_linear = clamped_volume
    local stop_int = stop_flag and 1 or 0
    opts = opts or {}

    local skip_write = false
    if not opts.force and daemon_last_control then
        local delta_pan = math.abs(daemon_last_control.pan - clamped_pan)
        local delta_volume = math.abs(daemon_last_control.volume - volume_linear)
        if delta_volume <= 0.001
            and daemon_last_control.stop == stop_int
            and delta_pan <= 0.0005 then

            skip_write = true
        end
    end

    if skip_write then
        return true
    end

    local payload = string.format("volume=%.3f\r\npan=%.3f\r\nstop=%d\r\n", volume_linear, clamped_pan, stop_int)
    local ok = direct_write_file(MINIAUDIO_DAEMON_CTL, payload)
    local fallback_cmd = nil

    if not ok then
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Direct control file write failed; attempting via PowerShell.")
        end

        local escaped_path = MINIAUDIO_DAEMON_CTL:gsub("'", "''")
        local cmd = string.format(
            [[powershell -NoLogo -NoProfile -Command "Set-Content -Path '%s' -Value @('volume=%.3f','pan=%.3f','stop=%d') -Encoding ASCII"]],
            escaped_path, volume_linear, clamped_pan, stop_int
        )

        ok = run_shell_command(cmd, "daemon ctl write")
        fallback_cmd = cmd
    end

    if ok then
        daemon_last_control = {
            volume = volume_linear,
            pan = clamped_pan,
            stop = stop_int,
        }
    end

    if ok and debug_enabled() then
        if fallback_cmd then
            mod:echo("[MiniAudioAddon] daemon_write_control -> cmd: %s", fallback_cmd)
        else
            mod:echo("[MiniAudioAddon] daemon_write_control -> direct write to %s", tostring(MINIAUDIO_DAEMON_CTL))
        end
    end

    return ok
end

local function daemon_force_quit(opts)
    local skip_stop_flag = opts and opts.skip_stop_flag
    local last_pid = daemon_pid

    bump_daemon_generation("force_quit")
    reset_daemon_status("force_quit")
    daemon_stop_reassert_last = 0

    if not skip_stop_flag and (daemon_is_running or daemon_pending_start or daemon_has_known_process) then
        daemon_write_control(0.0, 0.0, true, { force = true })
        daemon_stop_reassert_until = realtime_now() + 3.0
    else
        daemon_stop_reassert_until = 0
    end

    kill_daemon_process(last_pid)
    purge_payload_files()
end

local function daemon_start(path, volume_linear, pan)
    if not DLS then
        mod:error("[MiniAudioAddon] Cannot start daemon; DLS missing.")
        return false
    end

    if not ensure_daemon_paths() then
        mod:error(
            "[MiniAudioAddon] Cannot start daemon; failed to resolve exe/ctl (exe=%s, ctl=%s).",
            tostring(MINIAUDIO_DAEMON_EXE),
            tostring(MINIAUDIO_DAEMON_CTL)
        )
        return false
    end

    daemon_force_quit({ skip_stop_flag = true })

    local initial_volume, initial_pan = apply_manual_override(volume_linear or 1.0, pan or 0.0)
    local volume_percent, clamped_pan, clamped_initial_volume = daemon_control_values(initial_volume, initial_pan)
    initial_volume = clamped_initial_volume
    initial_pan = clamped_pan
    daemon_write_control(initial_volume, initial_pan, false)

    local requested_pipe_name = next_pipe_name()
    local pipe_arg = requested_pipe_name and string.format(' --pipe "%s"', requested_pipe_name) or ""

    local cmd_base = string.format('"%s" --daemon --log', MINIAUDIO_DAEMON_EXE)

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] daemon_start: path='%s'", tostring(path))
    end

    local has_autoplay_path = path and path ~= ""
    if has_autoplay_path then
        cmd_base = string.format('%s -i "%s"', cmd_base, path)
    else
        cmd_base = string.format('%s --no-autoplay', cmd_base)
    end

    local stdin_cmd = string.format('%s --stdin --ctl "%s"%s -volume %d',
        cmd_base, MINIAUDIO_DAEMON_CTL, pipe_arg, volume_percent)
    local cmd = string.format('%s --ctl "%s"%s -volume %d',
        cmd_base, MINIAUDIO_DAEMON_CTL, pipe_arg, volume_percent)

    stdin_cmd = wrap_daemon_command(stdin_cmd)
    cmd = wrap_daemon_command(cmd)

    clear_daemon_watchdog()

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] daemon_start cmd: %s", stdin_cmd)
    end

    daemon_stop_reassert_until = 0
    daemon_stop_reassert_last = 0

    if daemon_popen then
        local ok, handle_or_err = pcall(daemon_popen, stdin_cmd, "w")
        if ok and handle_or_err then
            daemon_stdio = handle_or_err
            daemon_stdio_mode = "stdin"
            daemon_is_running = true
            daemon_pending_start = false
            daemon_pipe_name = requested_pipe_name
            daemon_pid = nil
            daemon_has_known_process = false
            daemon_next_status_poll = 0
            daemon_missing_status_checks = 0
            if debug_enabled() then
                mod:echo("[MiniAudioAddon] Daemon running (stdin bridge).")
            end
            return true
        end

        if debug_enabled() then
            mod:error("[MiniAudioAddon] Failed to start daemon via stdin bridge: %s", tostring(handle_or_err))
        end
    end

    daemon_pending_start = true
    local launch_generation = bump_daemon_generation("launch start")

    local ok, promise = pcall(DLS.run_command, cmd)
    if ok and promise then
        promise
        :next(function(response)
            if launch_generation ~= daemon_generation then
                return
            end

            local payload = response and response.body
            local decoded, decode_err = decode_json_payload(payload)
            if decode_err then
                mod:error("[MiniAudioAddon] Failed to decode daemon launch response (%s).", tostring(decode_err))
                reset_daemon_status("launch decode failed")
                return
            end
            payload = decoded

            if type(payload) ~= "table" or payload.success ~= true then
                local reason = payload and payload.stderr or payload and payload.stdout or "unknown"
                mod:error("[MiniAudioAddon] Daemon launch rejected (%s).", tostring(reason))
                reset_daemon_status("launch rejected")
                return
            end

            if payload.pid == nil then
                mod:error("[MiniAudioAddon] Daemon launch response missing PID.")
                reset_daemon_status("launch missing pid")
                return
            end

            daemon_pid = tonumber(payload.pid) or payload.pid
            daemon_is_running = true
            daemon_pending_start = false
            daemon_next_status_poll = 0
            daemon_has_known_process = daemon_pid ~= nil
            daemon_missing_status_checks = 0
            daemon_pipe_name = requested_pipe_name

            if debug_enabled() then
                mod:echo("[MiniAudioAddon] Daemon running (pid=%s).", tostring(daemon_pid))
            end
        end)
        :catch(function(error)
            if launch_generation ~= daemon_generation then
                return
            end

            local body = error and error.body
            mod:error("[MiniAudioAddon] Daemon launch request failed: %s", tostring(body or error))
            reset_daemon_status("launch request failed")
        end)

        return true
    end

    mod:error("[MiniAudioAddon] Failed to start daemon via DLS: %s", tostring(promise))
    daemon_pending_start = false

    if run_shell_command(cmd, "daemon fallback start") then
        daemon_is_running = true
        daemon_pid = nil
        daemon_has_known_process = false
        daemon_next_status_poll = 0
        daemon_missing_status_checks = 0
        daemon_pipe_name = requested_pipe_name

        if debug_enabled() then
            mod:echo("[MiniAudioAddon] Daemon fallback launch succeeded (no PID tracking).")
        end

        return true
    end

    reset_daemon_status("launch failed")
    return false
end

local function daemon_update(volume_linear, pan)
    if not daemon_is_running then
        return
    end

    if daemon_manual_override then
        if debug_enabled() then
            mod:echo("[MiniAudioAddon] daemon_update skipped due to manual override (vol=%.3f, pan=%.3f)",
                daemon_manual_override.volume or -1, daemon_manual_override.pan or -1)
        end
        return
    end

    volume_linear, pan = apply_manual_override(volume_linear, pan)
    daemon_write_control(volume_linear, pan, false)
end

local function daemon_stop()
    local had_running_daemon = daemon_is_running or daemon_pending_start or daemon_has_known_process
    local should_push_stop = had_running_daemon or daemon_last_control ~= nil
    local last_pid = daemon_pid

    bump_daemon_generation("stop")
    reset_daemon_status("stop")
    daemon_stop_reassert_last = 0
    schedule_daemon_watchdog()

    clear_manual_override("stop")

    if should_push_stop then
        daemon_write_control(0.0, 0.0, true, { force = true })
        daemon_stop_reassert_until = realtime_now() + 3.0
    else
        daemon_stop_reassert_until = 0
    end

    kill_daemon_process(last_pid)
end
local function daemon_manual_control(volume_linear, pan)
    if not USE_MINIAUDIO_DAEMON then
        return false, "disabled"
    end

    if not (daemon_is_running or daemon_pending_start or daemon_has_known_process) then
        return false, "not_running"
    end

    local current_volume = daemon_last_control and daemon_last_control.volume or nil
    local current_pan = daemon_last_control and daemon_last_control.pan or 0.0
    local target_volume = volume_linear or current_volume or 1.0
    local target_pan = pan ~= nil and pan or current_pan

    daemon_manual_override = daemon_manual_override or {}
    if volume_linear ~= nil then
        daemon_manual_override.volume = target_volume
    end
    if pan ~= nil then
        daemon_manual_override.pan = target_pan
    end
    if daemon_manual_override.volume == nil and daemon_manual_override.pan == nil then
        daemon_manual_override = nil
    end

    local pipe_ok = false
    if daemon_pipe_name then
        pipe_ok = true
        if volume_linear ~= nil then
            pipe_ok = send_via_pipe_client(string.format("volume=%.3f", target_volume)) and pipe_ok
        end
        if pan ~= nil then
            pipe_ok = send_via_pipe_client(string.format("pan=%.3f", target_pan)) and pipe_ok
        end
    end

    local file_ok = daemon_write_control(target_volume, target_pan, false, { force = true })
    local succeeded = file_ok or pipe_ok

    if not succeeded then
        return false, "write_failed"
    end

    daemon_last_control = daemon_last_control or {}
    daemon_last_control.volume = target_volume
    daemon_last_control.pan = target_pan
    daemon_last_control.stop = 0

    if debug_enabled() then
        mod:echo("[MiniAudioAddon] Manual override set: volume=%.3f, pan=%.3f",
            daemon_manual_override and daemon_manual_override.volume or -1,
            daemon_manual_override and daemon_manual_override.pan or -1)
    end

    return true
end

local function daemon_send_play(track)
    if not track or not track.id then
        return false, "missing_track"
    end

    if not spatial_mode_enabled() then
        return false, "spatial_disabled"
    end

    if not daemon_is_active() then
        if not ensure_daemon_ready_for_tests(track.path) then
            return false, "daemon_unavailable"
        end
    end

    local payload = {
        cmd = "play",
        id = track.id,
        path = track.path,
        loop = track.loop ~= false,
        volume = clamp(track.volume or 1.0, 0.0, 3.0),
        profile = daemon_track_profile(track.profile),
        source = track.source,
        listener = track.listener or build_listener_payload(),
        effects = daemon_spatial_effects(track.effects),
    }

    apply_transport_fields(payload, track)

    local ok, detail = daemon_send_json(payload)
    return ok, detail
end

local function daemon_send_update(track)
    if not track or not track.id then
        return false, "missing_track"
    end

    local payload = {
        cmd = "update",
        id = track.id,
        volume = clamp(track.volume or 1.0, 0.0, 3.0),
        profile = track.profile and daemon_track_profile(track.profile) or nil,
        source = track.source,
        listener = track.listener or build_listener_payload(),
        effects = track.effects and daemon_spatial_effects(track.effects) or nil,
    }

    apply_transport_fields(payload, track)

    return daemon_send_json(payload)
end

local function daemon_send_stop(track_id, fade)
    if not track_id then
        return false, "missing_id"
    end

    return daemon_send_json({
        cmd = "stop",
        id = track_id,
        fade = fade or 0,
    })
end

local function daemon_send_pause(track_id)
    if not track_id then
        return false, "missing_id"
    end

    return daemon_send_json({
        cmd = "pause",
        id = track_id,
    })
end

local function daemon_send_resume(track_id)
    if not track_id then
        return false, "missing_id"
    end

    return daemon_send_json({
        cmd = "resume",
        id = track_id,
    })
end

local function daemon_send_seek(track_id, seconds)
    if not track_id then
        return false, "missing_id"
    end
    if seconds == nil then
        return false, "missing_value"
    end

    return daemon_send_json({
        cmd = "seek",
        id = track_id,
        seconds = seconds,
    })
end

local function daemon_send_skip(track_id, seconds)
    if not track_id then
        return false, "missing_id"
    end
    if seconds == nil then
        return false, "missing_value"
    end

    return daemon_send_json({
        cmd = "skip",
        id = track_id,
        seconds = seconds,
    })
end

local function daemon_send_speed(track_id, speed)
    if not track_id then
        return false, "missing_id"
    end
    if speed == nil then
        return false, "missing_value"
    end

    return daemon_send_json({
        cmd = "speed",
        id = track_id,
        speed = clamp(speed, MIN_TRANSPORT_SPEED, MAX_TRANSPORT_SPEED),
    })
end

local function daemon_send_reverse(track_id, enabled)
    if not track_id then
        return false, "missing_id"
    end

    return daemon_send_json({
        cmd = "reverse",
        id = track_id,
        reverse = enabled and true or false,
    })
end

local function daemon_send_shutdown()
    return daemon_send_json({ cmd = "shutdown" })
end

function mod:daemon_start(path, volume, pan)
    return daemon_start(path, volume, pan)
end

function mod:daemon_stop()
    daemon_stop()
end

function mod:daemon_update(volume, pan)
    daemon_update(volume, pan)
end

function mod:daemon_send_play(payload)
    return daemon_send_play(payload)
end

function mod:daemon_send_update(payload)
    return daemon_send_update(payload)
end

function mod:daemon_send_stop(track_id, fade)
    return daemon_send_stop(track_id, fade)
end

function mod:daemon_send_pause(track_id)
    return daemon_send_pause(track_id)
end

function mod:daemon_send_resume(track_id)
    return daemon_send_resume(track_id)
end

function mod:daemon_send_seek(track_id, seconds)
    return daemon_send_seek(track_id, seconds)
end

function mod:daemon_send_skip(track_id, seconds)
    return daemon_send_skip(track_id, seconds)
end

function mod:daemon_send_speed(track_id, speed)
    return daemon_send_speed(track_id, speed)
end

function mod:daemon_send_reverse(track_id, enabled)
    return daemon_send_reverse(track_id, enabled)
end

function mod:daemon_send_shutdown()
    return daemon_send_shutdown()
end

function mod:daemon_manual_control(volume, pan)
    return daemon_manual_control(volume, pan)
end

function mod:is_daemon_running()
    return daemon_is_running or daemon_pending_start
end

function mod:get_pipe_name()
    return daemon_pipe_name
end

function mod:get_generation()
    return daemon_generation
end

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
    if has_active then
        active_clients[client_id] = true
    else
        active_clients[client_id] = nil
    end
end

function mod:on_generation_reset(callback)
    generation_callback = callback
end

function mod:on_daemon_reset(callback)
    reset_callback = callback
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

local function command_set_volume(value)
    if not value then
        mod:echo("Usage: /miniaudio_volume <value>")
        return
    end

    local parsed = tonumber(value)
    if not parsed then
        mod:echo(string.format("Invalid volume value: %s", tostring(value)))
        return
    end

    local volume_linear = parsed
    if volume_linear > 3 then
        volume_linear = clamp(volume_linear / 100.0, 0.0, 3.0)
    end

    volume_linear = clamp(volume_linear, 0.0, 3.0)
    local ok, reason = daemon_manual_control(volume_linear, nil)

    if not ok then
        report_manual_error(reason)
        return
    end

    mod:echo("[MiniAudioAddon] Manual volume set -> %.0f%% (%.2f).", volume_linear * 100, volume_linear)
end

mod:command("miniaudio_volume", "Set daemon playback volume (0..3 linear or 0..300%).", command_set_volume)
mod:command("elevatormusic_volume", "Alias for /miniaudio_volume.", command_set_volume)

local function command_set_pan(value)
    if not value then
        mod:echo("Usage: /miniaudio_pan <value>")
        return
    end

    local parsed = tonumber(value)
    if not parsed then
        mod:echo(string.format("Invalid pan value: %s", tostring(value)))
        return
    end

    local pan = clamp(parsed, -1.0, 1.0)
    local ok, reason = daemon_manual_control(nil, pan)

    if not ok then
        report_manual_error(reason)
        return
    end

    mod:echo("[MiniAudioAddon] Manual pan set -> %.3f.", pan)
end

mod:command("miniaudio_pan", "Set daemon playback pan (-1.0 = left, 1.0 = right).", command_set_pan)
mod:command("elevatormusic_pan", "Alias for /miniaudio_pan.", command_set_pan)

local function command_manual_clear()
    if not daemon_manual_override then
        mod:echo("[MiniAudioAddon] No manual daemon overrides are active.")
        return
    end

    clear_manual_override("manual_clear")
    mod:echo("[MiniAudioAddon] Manual daemon overrides cleared; automatic control restored.")
end

mod:command("miniaudio_manual_clear", "Release manual daemon overrides so automatic mixing resumes.", command_manual_clear)
mod:command("elevatormusic_manual_clear", "Alias for /miniaudio_manual_clear.", command_manual_clear)

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

finalize_manual_track_stop = function()
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

    local ok, queued = daemon_send_stop(TRACK_IDS.manual, 0.35)
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

    finalize_manual_track_stop()
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
        id = TRACK_IDS.manual,
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
    local relative = SIMPLE_TEST.tracks[key] or SIMPLE_TEST.tracks[SIMPLE_TEST.default]
    if not relative then
        return nil
    end

    local resolved = expand_track_path(relative)
    if not resolved then
        mod:echo("[MiniAudioAddon] Simple test file missing: %s", relative)
    end
    return resolved
end

local function start_emitter_track(resolved_path, distance)
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

    local listener_pos, listener_rot = listener_pose()
    if not listener_pos or not listener_rot or not Vector3 then
        mod:echo("[MiniAudioAddon] Listener pose unavailable; enter gameplay before running emitter tests.")
        return false
    end

    local distance_clamped = clamp(distance or 3, 0.5, 25)
    local forward = safe_forward(listener_rot)
    local spawn_pos = listener_pos + forward * distance_clamped
    local spawn_rot = listener_rot
    local show_debug_markers = mod:debug_markers_enabled()
    local unit = nil
    if show_debug_markers then
        unit = spawn_debug_unit(MARKER_SETTINGS.emitter_unit, spawn_pos, spawn_rot)
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
    local emitter_min_distance = clamp(distance_clamped * 0.25 * distance_scale, 0.5, 25.0)
    local emitter_max_distance = clamp(distance_clamped * 5.0 * distance_scale, emitter_min_distance + 5.0, 150.0)
    emitter_profile.min_distance = emitter_min_distance
    emitter_profile.max_distance = emitter_max_distance

    local track = {
        id = TRACK_IDS.emitter,
        path = resolved_path,
        loop = true,
        volume = 1.0,
        profile = emitter_profile,
        listener = listener,
        source = {
            position = vec3_to_array(spawn_pos),
            forward = vec3_to_array(forward),
            velocity = { 0, 0, 0 },
        },
    }

    local ok, queued = daemon_send_play(track)
    if ok then
        emitter_state = {
            unit = unit,
            track_id = TRACK_IDS.emitter,
            path = resolved_path,
            next_update = realtime_now(),
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

    local ok, queued = daemon_send_stop(state.track_id, state.fade or 0.35)
    if not ok then
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

local function command_test_play(...)
    local args = collect_command_args(...)
    if #args == 0 then
        mod:echo("Usage: /miniaudio_test_play <absolute-or-relative-path>")
        return
    end

    local combined_path = table.concat(args, " ")
    local resolved = expand_track_path(combined_path)
    if not resolved then
        mod:echo("[MiniAudioAddon] Could not find audio file: %s", tostring(combined_path))
        return
    end

    start_manual_track(resolved)
end

local function command_test_stop()
    if not manual_track_path and not manual_track_stop_pending then
        mod:echo("[MiniAudioAddon] No manual daemon track is active.")
        return
    end

    stop_manual_track(false)
end

mod:command("miniaudio_test_play", "Play a file through the daemon once spatial mode is enabled. Usage: /miniaudio_test_play <path>", command_test_play)
mod:command("miniaudio_test_stop", "Stop the manual daemon playback triggered by /miniaudio_test_play.", command_test_stop)

local function command_emit_start(...)
    local args = collect_command_args(...)
    if #args == 0 then
        mod:echo("Usage: /miniaudio_emit_start <path> [distance]")
        return
    end

    local distance_arg = nil
    if #args >= 2 then
        local maybe_distance = tonumber(args[#args])
        if maybe_distance then
            distance_arg = maybe_distance
            args[#args] = nil
        end
    end

    local raw_path = table.concat(args, " ")
    local resolved = expand_track_path(raw_path)
    if not resolved then
        mod:echo("[MiniAudioAddon] Could not find audio file: %s", tostring(raw_path))
        return
    end

    start_emitter_track(resolved, distance_arg and tonumber(distance_arg) or nil)
end

local function command_emit_stop()
    if not emitter_state then
        mod:echo("[MiniAudioAddon] No emitter test is active.")
        return
    end

    cleanup_emitter_state("[MiniAudioAddon] Emitter test stopped.", false)
end

mod:command("miniaudio_emit_start", "Spawn a debug cube in front of you that emits audio. Usage: /miniaudio_emit_start <path> [distance]", command_emit_start)
mod:command("miniaudio_emit_stop", "Stop and remove the debug audio emitter cube.", command_emit_stop)

local function command_simple_play(choice)
    local resolved = resolve_simple_track(choice)
    if resolved then
        start_manual_track(resolved)
    end
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

local function command_simple_emit(arg1, arg2)
    local distance, choice = parse_simple_distance_and_choice(arg1, arg2)
    local resolved = resolve_simple_track(choice)
    if resolved then
        start_emitter_track(resolved, distance)
    end
end

local function command_simple_spatial(mode, choice)
    local resolved = resolve_simple_track(choice)
    if not resolved then
        return
    end

    mode = mode and mode:lower() or "orbit"
    if mode == "orbit" then
        command_spatial_test("orbit", "4", "6", "0", resolved)
    elseif mode == "direction" or mode == "directional" then
        command_spatial_test("direction", "0", "0", "6", resolved)
    elseif mode == "follow" then
        command_spatial_test("follow", resolved, "0", "0", "0")
    elseif mode == "loop" then
        command_spatial_test("loop", "6", "8", "0", resolved)
    elseif mode == "spin" then
        command_spatial_test("spin", "4", "6", "0", resolved)
    else
        mod:echo("[MiniAudioAddon] Unknown simple spatial mode: %s", tostring(mode))
    end
end

mod:command("miniaudio_simple_play", "Play the bundled sample tracks (usage: /miniaudio_simple_play [mp3|wav]).", command_simple_play)
mod:command("miniaudio_simple_emit", "Spawn the sample emitter cube (usage: /miniaudio_simple_emit [distance] [mp3|wav]).", command_simple_emit)
mod:command("miniaudio_simple_spatial", "Run spatial tests using the bundled tracks (usage: /miniaudio_simple_spatial <orbit|direction|follow|loop> [mp3|wav]).", command_simple_spatial)
mod:command("miniaudio_simple_stop", "Stop the bundled sample playback/emitter.", function()
    local acted = false

    if manual_track_path or manual_track_stop_pending then
        acted = true
        stop_manual_track(false)
    end

    if emitter_state then
        acted = true
        cleanup_emitter_state("[MiniAudioAddon] Emitter test stopped.", false)
    end

    if not acted then
        mod:echo("[MiniAudioAddon] No simple test playback/emitter is active.")
    end
end)

local function command_cleanup_payloads()
    ensure_daemon_paths()
    if not MINIAUDIO_PIPE_DIRECTORY then
        mod:echo("[MiniAudioAddon] Payload directory not resolved; nothing to clean.")
        return
    end

    purge_payload_files()
    mod:echo(string.format("[MiniAudioAddon] Cleared payload files under %s", MINIAUDIO_PIPE_DIRECTORY))
end

mod:command("miniaudio_cleanup_payloads", "Delete leftover miniaudio payload files beside the daemon.", command_cleanup_payloads)

ensure_listener_payload = function()
    local payload = build_listener_payload()
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
        send_play = daemon_send_play,
        send_update = daemon_send_update,
        send_stop = daemon_send_stop,
        send_pause = daemon_send_pause,
        send_resume = daemon_send_resume,
        send_seek = daemon_send_seek,
        send_skip = daemon_send_skip,
        send_speed = daemon_send_speed,
        send_reverse = daemon_send_reverse,
        send_shutdown = daemon_send_shutdown,
        send_json = daemon_send_json,
        ensure_listener = ensure_listener_payload,
        build_listener = build_listener_payload,
        spatial_mode_enabled = spatial_mode_enabled,
        now = now,
        realtime_now = realtime_now,
    })

    if api then
        mod.api = api
    else
        mod:error("[MiniAudioAddon] Failed to initialize MiniAudio API module.")
    end
end

init_api_layer()

ensure_daemon_ready_for_tests = function(path_hint)
    if daemon_is_running or daemon_pending_start or daemon_has_known_process then
        return true
    end

    if daemon_start("", 1.0, 0.0) then
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

local function build_spatial_stop_message(reason, silent)
    if silent then
        return nil
    end
    if reason and debug_enabled() then
        return string.format("[MiniAudioAddon] Spatial test stopped (%s).", tostring(reason))
    end
    return "[MiniAudioAddon] Spatial test stopped."
end

spatial_test_stop = function(reason, silent)
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
        local ok, queued = daemon_send_stop(state.track_id, state.fade or 0.25)
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

finalize_spatial_test_stop = function()
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

update_spatial_test = function()
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

    local listener_forward = safe_forward(listener_rot)
    local listener_up = safe_up(listener_rot)
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
        velocity = vec3_to_array(Vector3(-radius * math.sin(angle), radius * math.cos(angle), 0))
    elseif state.mode == "spin" and Vector3 then
        local anchor_position = unbox_vector(state.anchor_position)
        local anchor_right = unbox_vector(state.anchor_right)
        local anchor_forward = unbox_vector(state.anchor_forward)
        local anchor_up = unbox_vector(state.anchor_up) or Vector3(0, 0, 1)

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
        velocity = vec3_to_array(tangential)
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
            position = vec3_to_array(source_pos),
            forward = vec3_to_array(source_forward),
            velocity = velocity,
        },
        listener = build_listener_payload(),
        effects = daemon_spatial_effects(state.effects),
    }

    local ok, queued = daemon_send_json(payload)
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

local function command_spatial_test(mode, ...)
    mode = mode and string.lower(mode) or "orbit"
    local args = collect_command_args(...)

    if mode == "stop" then
        spatial_test_stop("user", false)
        return
    end

    if spatial_test_state then
        local cleared = spatial_test_stop("restart", true)
        if not cleared then
            mod:echo("[MiniAudioAddon] A spatial test is already running; stop it before starting another.")
            return
        end

        if spatial_test_state then
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

    if mode == "orbit" then
        local idx = 1
        local function take_number(default)
            local candidate = args[idx]
            local parsed = candidate and tonumber(candidate)
            if parsed then
                idx = idx + 1
                return parsed
            end
            return default
        end

        local radius = take_number(4)
        local period = take_number(6)
        local duration = take_number(0)
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
        local function take_number(default)
            local candidate = args[idx]
            local parsed = candidate and tonumber(candidate)
            if parsed then
                idx = idx + 1
                return parsed
            end
            return default
        end

        local yaw = take_number(0)
        local pitch = take_number(0)
        local distance = take_number(6)
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
        local function take_number(default)
            local candidate = args[idx]
            local parsed = candidate and tonumber(candidate)
            if parsed then
                idx = idx + 1
                return parsed
            end
            return default
        end

        local radius = take_number(6)
        local period = take_number(8)
        local height = take_number(0)
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
        local function take_number(default)
            local candidate = args[idx]
            local parsed = candidate and tonumber(candidate)
            if parsed then
                idx = idx + 1
                return parsed
            end
            return default
        end

        local radius = take_number(4)
        local period = take_number(6)
        local duration = take_number(0)
        local raw_path = join_command_args(args, idx)
        local resolved = resolve_or_error(raw_path)
        if not resolved or not ensure_daemon_ready_for_tests(resolved) then
            return
        end

        local anchor_position = initial_listener_pos
        local anchor_up = safe_up(initial_listener_rot)
        local anchor_forward = safe_forward(initial_listener_rot)
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
mod.on_disabled = function()
    active_clients = {}
    spatial_test_stop("disabled")
    clear_spatial_marker()
    stop_manual_track(true)
    cleanup_emitter_state(nil, true)
    daemon_stop()

    for _, entry in ipairs(staged_payload_cleanups) do
        if entry and entry.path and entry.path ~= MINIAUDIO_PIPE_PAYLOAD then
            delete_file(entry.path)
        end
    end
    staged_payload_cleanups = {}
    purge_payload_files()
    clear_daemon_log_file("mod_disabled")
end

mod.on_unload = function()
    clear_daemon_log_file("mod_unload")
end

mod.on_game_state_changed = function(status, state_name)
    if status == "enter" and state_name == "StateGameplay" then
        clear_daemon_log_file("enter_gameplay")
    end
end

mod.update = function(dt)
    if spatial_mode_enabled() then
        flush_pending_daemon_messages()
    end

    if staged_payload_cleanups and #staged_payload_cleanups > 0 then
        local rt_now = realtime_now()
        local idx = 1
        while idx <= #staged_payload_cleanups do
            local entry = staged_payload_cleanups[idx]
            if entry.delete_after and entry.delete_after <= rt_now then
                local removed = true
                if entry.path and entry.path ~= MINIAUDIO_PIPE_PAYLOAD then
                    removed = delete_file(entry.path)
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

    if spatial_test_state then
        spatial_test_state.dt = dt or 0.016
        update_spatial_test()
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
                destroy_spawned_unit(unit)
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
            local rt = realtime_now()
            if not state.pending_start and (not state.next_update or rt >= state.next_update) then
                local forward = safe_forward(rotation)
                daemon_send_update({
                    id = state.track_id,
                    source = {
                        position = vec3_to_array(position),
                        forward = vec3_to_array(forward),
                        velocity = { 0, 0, 0 },
                    },
                    listener = build_listener_payload(),
                })
                state.next_update = rt + MARKER_SETTINGS.update_interval
            end

            draw_emitter_marker(position, rotation)
        end
    end

    if USE_MINIAUDIO_DAEMON then
        local t_now = now()
        local rt_now = realtime_now()

        if daemon_watchdog_until > 0 and rt_now >= daemon_watchdog_until then
            daemon_watchdog_until = 0
        end

        if daemon_stop_reassert_until > 0 and rt_now < daemon_stop_reassert_until then
            if (rt_now - daemon_stop_reassert_last) >= 0.5 then
                daemon_write_control(0.0, 0.0, true, { force = true })
                daemon_stop_reassert_last = rt_now
            end
        elseif daemon_stop_reassert_until > 0 and rt_now >= daemon_stop_reassert_until then
            daemon_stop_reassert_until = 0
            daemon_stop_reassert_last = 0
        end

        if daemon_is_idle() and (daemon_is_running or daemon_watchdog_until > 0) then
            if daemon_watchdog_until == 0 then
                schedule_daemon_watchdog()
            elseif rt_now >= daemon_watchdog_until and daemon_watchdog_next_attempt <= rt_now then
                daemon_force_quit()
                daemon_watchdog_next_attempt = rt_now + DAEMON_WATCHDOG_COOLDOWN
            end
        elseif daemon_watchdog_until > 0 then
            clear_daemon_watchdog()
        end

        if daemon_pid and daemon_is_running and daemon_has_known_process and DLS and DLS.process_is_running then
            if daemon_next_status_poll <= t_now then
                daemon_next_status_poll = t_now + DAEMON_STATUS_POLL_INTERVAL
                local poll_generation = daemon_generation
                local request = DLS.process_is_running(daemon_pid)

                if request then
                    request:next(function(response)
                        if poll_generation ~= daemon_generation then
                            return
                        end

                        local body = response and response.body
                        if body and body.process_is_running == false then
                            daemon_missing_status_checks = daemon_missing_status_checks + 1
                            if daemon_missing_status_checks >= 5 then
                                if daemon_is_idle() then
                                    daemon_missing_status_checks = 0
                                    daemon_force_quit()
                                else
                                    daemon_missing_status_checks = 5
                                end
                            end
                        else
                            daemon_missing_status_checks = 0
                        end
                    end):catch(function(error)
                        if poll_generation ~= daemon_generation then
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
