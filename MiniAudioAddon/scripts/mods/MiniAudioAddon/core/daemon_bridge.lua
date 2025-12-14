local mod = get_mod("MiniAudioAddon")

local Bridge = {}

local function call_bridge(method, ...)
    if not mod or not mod[method] then
        return false, "unsupported"
    end

    local ok, result, extra = pcall(mod[method], mod, ...)
    if not ok then
        return false, "pcall_failed", result
    end
    if result == false then
        return false, extra or "send_failed"
    end
    return true, result
end

function Bridge.play(payload)
    return call_bridge("daemon_send_play", payload)
end

function Bridge.update(payload)
    return call_bridge("daemon_send_update", payload)
end

function Bridge.stop(id, fade)
    return call_bridge("daemon_send_stop", id, fade or 0)
end

return Bridge
--[[
    File: core/daemon_bridge.lua
    Description: Safe wrapper around MiniAudioAddon daemon send/update/stop helpers,
    providing reusable functions to other mods.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
]]
