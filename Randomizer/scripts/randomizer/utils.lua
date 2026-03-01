--[[
    File: utils.lua
    Description: Shared helper utilities for safety checks, weighted picks, and setting reads.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")

local HOST_TYPES = MatchmakingConstants.HOST_TYPES

local Utils = {}

function Utils.clamp(value, min_value, max_value)
    local number = tonumber(value) or min_value

    if number < min_value then
        return min_value
    end

    if number > max_value then
        return max_value
    end

    return number
end

function Utils.safe_get_setting(mod, setting_id, fallback)
    local ok, value = pcall(mod.get, mod, setting_id)

    if ok and value ~= nil then
        return value
    end

    return fallback
end

function Utils.is_server_authority()
    local game_session = Managers and Managers.state and Managers.state.game_session

    return game_session and game_session:is_server() or false
end

function Utils.is_local_controlled_session()
    if not Utils.is_server_authority() then
        return false
    end

    local multiplayer_session = Managers and Managers.multiplayer_session

    if multiplayer_session and HOST_TYPES then
        local host_type = multiplayer_session:host_type()

        if host_type == HOST_TYPES.singleplay then
            return true
        end
    end

    local player_manager = Managers and Managers.player

    if player_manager and player_manager.human_players then
        local human_players = player_manager:human_players()

        for _, player in pairs(human_players) do
            local is_human = player and player.is_human_controlled and player:is_human_controlled()

            if is_human and player.remote then
                return false
            end
        end
    end

    return true
end

function Utils.weighted_pick(weight_by_key, ordered_keys, random_float_fn)
    local total_weight = 0

    for i = 1, #ordered_keys do
        local key = ordered_keys[i]
        local weight = tonumber(weight_by_key[key]) or 0

        if weight > 0 then
            total_weight = total_weight + weight
        end
    end

    if total_weight <= 0 then
        return nil
    end

    local roll = random_float_fn() * total_weight
    local running = 0

    for i = 1, #ordered_keys do
        local key = ordered_keys[i]
        local weight = tonumber(weight_by_key[key]) or 0

        if weight > 0 then
            running = running + weight

            if roll <= running then
                return key
            end
        end
    end

    for i = #ordered_keys, 1, -1 do
        local fallback_key = ordered_keys[i]

        if (tonumber(weight_by_key[fallback_key]) or 0) > 0 then
            return fallback_key
        end
    end

    return nil
end

function Utils.get_gameplay_time()
    local time_manager = Managers and Managers.time

    if not time_manager or not time_manager.time then
        return nil
    end

    local ok, value = pcall(time_manager.time, time_manager, "gameplay")

    if ok then
        return tonumber(value)
    end

    return nil
end

return Utils
