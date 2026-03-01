--[[
    File: patrol_randomizer.lua
    Description: Patrol-specific helper logic for identifying and selecting patrol-capable enemies.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local PatrolRandomizer = {}

function PatrolRandomizer.is_patrol(core, breed_name)
    local enemies = core.state.pools and core.state.pools.enemies
    local enemy_meta = enemies and enemies.by_name and enemies.by_name[breed_name]

    return enemy_meta and enemy_meta.is_patrol == true or false
end

function PatrolRandomizer.random_patrol(core)
    local enemies = core.state.pools and core.state.pools.enemies
    local patrol_pool = enemies and enemies.patrols

    if not patrol_pool or #patrol_pool == 0 then
        return nil
    end

    return core:random_array_entry(patrol_pool)
end

return PatrolRandomizer
