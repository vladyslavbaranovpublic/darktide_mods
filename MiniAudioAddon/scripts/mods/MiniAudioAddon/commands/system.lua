local SystemCommands = {}

function SystemCommands.register(mod, deps)
    if not mod or not deps then
        return
    end

    local clamp = deps.clamp or math.clamp
    local daemon_manual_control = deps.daemon_manual_control
    local report_manual_error = deps.report_manual_error or function() end
    local manual_override_active = deps.manual_override_active or function()
        return false
    end
    local clear_manual_override = deps.clear_manual_override or function() end

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
        if not manual_override_active() then
            mod:echo("[MiniAudioAddon] No manual daemon overrides are active.")
            return
        end

        clear_manual_override("manual_clear")
        mod:echo("[MiniAudioAddon] Manual daemon overrides cleared; automatic control restored.")
    end

    mod:command("miniaudio_manual_clear", "Release manual daemon overrides so automatic mixing resumes.", command_manual_clear)
    mod:command("elevatormusic_manual_clear", "Alias for /miniaudio_manual_clear.", command_manual_clear)
end

return SystemCommands
