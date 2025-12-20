--[[
    File: core/payload_builder.lua
    Description: Centralized payload building for daemon communication.
    All JSON payload construction happens here - single source of truth.
    Overall Release Version: 1.0.2
    File Version: 1.0.2
]]

local PayloadBuilder = {}

-- Dependencies (set via init)
local daemon_track_profile = nil
local daemon_spatial_effects = nil
local apply_transport_fields = nil

--[[
    Initialize PayloadBuilder with dependencies from DaemonBridge
    
    Args:
        deps: {
            daemon_track_profile = function,
            daemon_spatial_effects = function,
            apply_transport_fields = function,
        }
]]
function PayloadBuilder.init(deps)
    daemon_track_profile = deps.daemon_track_profile
    daemon_spatial_effects = deps.daemon_spatial_effects
    apply_transport_fields = deps.apply_transport_fields
end

--[[
    Build a 'play' command payload
    
    Args:
        track: {
            id = string,
            path = string,
            loop = boolean,
            volume = number,
            profile = table,
            source = table,
            listener = table,
            effects = table,
            autoplay = boolean,
            require_listener = boolean,
            process_id = string,
            -- Transport fields (optional):
            start_seconds = number,
            seek_seconds = number,
            skip_seconds = number,
            speed = number,
            reverse = boolean,
        }
    
    Returns:
        payload: Complete JSON payload ready for daemon_send_json
]]
function PayloadBuilder.build_play(track)
    local payload = {
        cmd = "play",
        id = track.id,
        path = track.path,
        loop = track.loop,
        volume = track.volume,
        profile = track.profile and daemon_track_profile and daemon_track_profile(track.profile) or nil,
        source = track.source,
        listener = track.listener,
        effects = track.effects and daemon_spatial_effects and daemon_spatial_effects(track.effects) or nil,
        autoplay = track.autoplay,
        require_listener = track.require_listener,
        process_id = track.process_id,
    }
    
    -- Apply transport fields (start_seconds, seek_seconds, skip_seconds, speed, reverse)
    if apply_transport_fields then
        apply_transport_fields(payload, track)
    end
    
    return payload
end

--[[
    Build an 'update' command payload
    
    Args:
        track: {
            id = string,
            volume = number (optional),
            profile = table (optional),
            source = table (optional),
            listener = table (optional),
            effects = table (optional),
            -- Transport fields (optional):
            seek_seconds = number,
            skip_seconds = number,
            speed = number,
            reverse = boolean,
        }
    
    Returns:
        payload: Complete JSON payload ready for daemon_send_json
]]
function PayloadBuilder.build_update(track)
    local payload = {
        cmd = "update",
        id = track.id,
        volume = track.volume,
        profile = track.profile and daemon_track_profile and daemon_track_profile(track.profile) or nil,
        source = track.source,
        listener = track.listener,
        effects = track.effects and daemon_spatial_effects and daemon_spatial_effects(track.effects) or nil,
    }
    
    -- Apply transport fields
    if apply_transport_fields then
        apply_transport_fields(payload, track)
    end
    
    return payload
end

--[[
    Build a 'stop' command payload
    
    Args:
        track_id: string - Track ID to stop
        fade: number - Fade duration in seconds (default: 0)
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_stop(track_id, fade)
    return {
        cmd = "stop",
        id = track_id,
        fade = fade or 0,
    }
end

--[[
    Build a 'pause' command payload
    
    Args:
        track_id: string - Track ID to pause
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_pause(track_id)
    return {
        cmd = "pause",
        id = track_id,
    }
end

--[[
    Build a 'resume' command payload
    
    Args:
        track_id: string - Track ID to resume
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_resume(track_id)
    return {
        cmd = "resume",
        id = track_id,
    }
end

--[[
    Build a 'seek' command payload
    
    Args:
        track_id: string - Track ID
        seconds: number - Position to seek to in seconds
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_seek(track_id, seconds)
    return {
        cmd = "seek",
        id = track_id,
        seconds = seconds,
    }
end

--[[
    Build a 'skip' command payload
    
    Args:
        track_id: string - Track ID
        seconds: number - Number of seconds to skip forward/backward
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_skip(track_id, seconds)
    return {
        cmd = "skip",
        id = track_id,
        seconds = seconds,
    }
end

--[[
    Build a 'speed' command payload
    
    Args:
        track_id: string - Track ID
        speed: number - Playback speed multiplier
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_speed(track_id, speed)
    return {
        cmd = "speed",
        id = track_id,
        speed = speed,
    }
end

--[[
    Build a 'reverse' command payload
    
    Args:
        track_id: string - Track ID
        enabled: boolean - Enable/disable reverse playback
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_reverse(track_id, enabled)
    return {
        cmd = "reverse",
        id = track_id,
        reverse = enabled and true or false,
    }
end

--[[
    Build a 'shutdown' command payload
    
    Returns:
        payload: Complete JSON payload
]]
function PayloadBuilder.build_shutdown()
    return {
        cmd = "shutdown"
    }
end

--[[
    Purge any existing payload files
    
    Returns:
        None
]]
local function ensure_trailing_separator(path)
    if not path or path == "" then
        return nil
    end
    local last = path:sub(-1)
    if last == "\\" or last == "/" then
        return path
    end
    return path .. "\\"
end

function PayloadBuilder.purge_payload_files(pipe_payload, pipe_directory)
    if pipe_payload and pipe_payload ~= "" then
        pcall(os.remove, pipe_payload)
    end

    local directory = ensure_trailing_separator(pipe_directory)
    if directory then
        pcall(os.remove, directory .. "miniaudio_dt_last_play.json")
    end

    return true
end

return PayloadBuilder
