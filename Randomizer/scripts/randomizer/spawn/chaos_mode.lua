--[[
    File: chaos_mode.lua
    Description: Chaos mode rules that bypass category and weight constraints.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local ChaosMode = {}

local function _is_luggable_pickup_name(pickup_name)
    return type(pickup_name) == "string" and string.find(pickup_name, "luggable", 1, true) ~= nil
end

local function _is_candidate_compatible(core, candidate, config, requested_meta)
    if type(candidate) ~= "string" then
        return false
    end

    if core:is_enemy_blocked_for_randomizer(candidate) then
        return false
    end

    if config and config.disabled_enemy_breeds and config.disabled_enemy_breeds[candidate] == true then
        return false
    end

    local enemies = core.state.pools and core.state.pools.enemies
    local candidate_meta = enemies and enemies.by_name and enemies.by_name[candidate]

    if not candidate_meta then
        return false
    end

    local request_is_patrol = requested_meta and requested_meta.is_patrol == true or false
    local candidate_is_patrol = candidate_meta.is_patrol == true
    local request_is_boss = requested_meta and requested_meta.is_boss == true or false
    local candidate_is_boss = candidate_meta.is_boss == true

    if request_is_patrol and not candidate_is_patrol then
        -- Patrol requests require patrol-capable breeds or patrol systems can nil-index.
        return false
    end

    if not request_is_patrol and candidate_is_patrol then
        -- Patrol-only breeds in non-patrol requests can assume missing patrol state.
        return false
    end

    if request_is_boss and not candidate_is_boss then
        return false
    end

    if request_is_boss and candidate_is_boss then
        local requested_archetype = requested_meta and requested_meta.archetype
        local candidate_archetype = candidate_meta and candidate_meta.archetype

        if type(requested_archetype) == "string"
            and type(candidate_archetype) == "string"
            and requested_archetype ~= candidate_archetype
        then
            return false
        end
    end

    return true
end

local function _pick_compatible_from_pool(core, pool, config, requested_meta)
    if type(pool) ~= "table" or #pool == 0 then
        return nil
    end

    local count = #pool
    local start_index = core:next_int(1, count)

    for i = 0, count - 1 do
        local idx = ((start_index + i - 1) % count) + 1
        local candidate = pool[idx]

        if _is_candidate_compatible(core, candidate, config, requested_meta) then
            return candidate
        end
    end

    return nil
end

function ChaosMode.random_enemy(core, requested_breed, requested_meta, config, context)
    local enemy_pools = core.state.pools and core.state.pools.enemies

    if not enemy_pools then
        return requested_breed
    end

    local replacement = _pick_compatible_from_pool(core, enemy_pools.all, config, requested_meta)

    if core:is_valid_enemy(replacement) then
        return replacement
    end

    return requested_breed
end

function ChaosMode.random_item(core, requested_pickup)
    local item_pools = core.state.pools and core.state.pools.items

    if not item_pools then
        return requested_pickup
    end

    if _is_luggable_pickup_name(requested_pickup) then
        return requested_pickup
    end

    local requested_meta = item_pools.by_name and item_pools.by_name[requested_pickup]

    if requested_meta and requested_meta.is_mission_critical == true then
        return requested_pickup
    end

    -- Chaos item randomization still uses safe pools to avoid replacing objective/luggable
    -- pickups with incompatible types that can break mission extension contracts.
    local replacement = core:random_array_entry(item_pools.safe)

    if core:is_valid_item(replacement) then
        return replacement
    end

    return requested_pickup
end

return ChaosMode
