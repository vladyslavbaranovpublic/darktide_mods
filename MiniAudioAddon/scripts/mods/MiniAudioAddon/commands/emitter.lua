local EmitterCommands = {}

function EmitterCommands.register(mod, deps)
    if not mod or not deps then
        return
    end

    local collect_command_args = deps.collect_command_args or function(...)
        return { ... }
    end
    local expand_track_path = deps.expand_track_path
    local start_emitter_track = deps.start_emitter_track
    local cleanup_emitter_state = deps.cleanup_emitter_state or function() end
    local emitter_active = deps.emitter_active or function()
        return false
    end

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
        if not emitter_active() then
            mod:echo("[MiniAudioAddon] No emitter test is active.")
            return
        end

        cleanup_emitter_state("[MiniAudioAddon] Emitter test stopped.", false)
    end

    mod:command("miniaudio_emit_start", "Spawn a debug cube in front of you that emits audio. Usage: /miniaudio_emit_start <path> [distance]", command_emit_start)
    mod:command("miniaudio_emit_stop", "Stop and remove the debug audio emitter cube.", command_emit_stop)
end

return EmitterCommands
