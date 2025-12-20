local SimpleCommands = {}

function SimpleCommands.register(mod, deps)
    if not mod or not deps then
        return
    end

    local expand_track_path = deps.expand_track_path
    local simple_tracks = deps.simple_tracks or {}
    local simple_default = deps.simple_default
    local start_manual_track = deps.start_manual_track
    local start_emitter_track = deps.start_emitter_track
    local stop_manual_track = deps.stop_manual_track or function() end
    local cleanup_emitter_state = deps.cleanup_emitter_state or function() end
    local manual_track_active = deps.manual_track_active or function()
        return false
    end
    local manual_stop_pending = deps.manual_stop_pending or function()
        return false
    end
    local emitter_active = deps.emitter_active or function()
        return false
    end
    local spatial_run = deps.spatial_run

    local function resolve_simple_track(choice)
        local key = choice and choice:lower()
        local relative = simple_tracks[key] or simple_tracks[simple_default]
        if not relative then
            return nil
        end

        local resolved = expand_track_path(relative)
        if not resolved then
            mod:echo("[MiniAudioAddon] Simple test file missing: %s", relative)
        end
        return resolved
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

    local function command_simple_play(choice)
        local resolved = resolve_simple_track(choice)
        if resolved then
            start_manual_track(resolved)
        end
    end

    local function command_simple_emit(arg1, arg2)
        local distance, choice = parse_simple_distance_and_choice(arg1, arg2)
        local resolved = resolve_simple_track(choice)
        if resolved then
            start_emitter_track(resolved, distance)
        end
    end

    local function command_simple_spatial(mode, choice)
        if not spatial_run then
            mod:echo("[MiniAudioAddon] Spatial test commands unavailable.")
            return
        end

        local resolved = resolve_simple_track(choice)
        if not resolved then
            return
        end

        mode = mode and mode:lower() or "orbit"
        if mode == "orbit" then
            spatial_run("orbit", "4", "6", "0", resolved)
        elseif mode == "direction" or mode == "directional" then
            spatial_run("direction", "0", "0", "6", resolved)
        elseif mode == "follow" then
            spatial_run("follow", resolved, "0", "0", "0")
        elseif mode == "loop" then
            spatial_run("loop", "6", "8", "0", resolved)
        else
            mod:echo("[MiniAudioAddon] Unknown simple spatial mode: %s", tostring(mode))
        end
    end

    local function command_simple_stop()
        local acted = false

        if manual_track_active() or manual_stop_pending() then
            acted = true
            stop_manual_track(false)
        end

        if emitter_active() then
            acted = true
            cleanup_emitter_state("[MiniAudioAddon] Emitter test stopped.", false)
        end

        if not acted then
            mod:echo("[MiniAudioAddon] No simple test playback/emitter is active.")
        end
    end

    mod:command("miniaudio_simple_play", "Play the bundled sample tracks (usage: /miniaudio_simple_play [mp3|wav]).", command_simple_play)
    mod:command("miniaudio_simple_emit", "Spawn the sample emitter cube (usage: /miniaudio_simple_emit [distance] [mp3|wav]).", command_simple_emit)
    mod:command("miniaudio_simple_spatial", "Run spatial tests using the bundled tracks (usage: /miniaudio_simple_spatial <orbit|direction|follow|loop> [mp3|wav]).", command_simple_spatial)
    mod:command("miniaudio_simple_stop", "Stop the bundled sample playback/emitter.", command_simple_stop)
end

return SimpleCommands
