local ManualCommands = {}

function ManualCommands.register(mod, deps)
    if not mod or not deps then
        return
    end

    local collect_command_args = deps.collect_command_args or function(...)
        return { ... }
    end
    local expand_track_path = deps.expand_track_path
    local start_manual_track = deps.start_manual_track
    local stop_manual_track = deps.stop_manual_track
    local has_manual_track = deps.has_manual_track or function()
        return false
    end
    local manual_stop_pending = deps.manual_stop_pending or function()
        return false
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
        if not has_manual_track() and not manual_stop_pending() then
            mod:echo("[MiniAudioAddon] No manual daemon track is active.")
            return
        end

        stop_manual_track(false)
    end

    mod:command("miniaudio_test_play", "Play a file through the daemon once spatial mode is enabled. Usage: /miniaudio_test_play <path>", command_test_play)
    mod:command("miniaudio_test_stop", "Stop the manual daemon playback triggered by /miniaudio_test_play.", command_test_stop)
end

return ManualCommands
