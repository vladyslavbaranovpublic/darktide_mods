--[[
    File: boss_randomizer.lua
    Description: Boss-specific helper logic for identifying and selecting boss enemies.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local BossRandomizer = {}

function BossRandomizer.is_boss(core, breed_name)
    local enemies = core.state.pools and core.state.pools.enemies
    local enemy_meta = enemies and enemies.by_name and enemies.by_name[breed_name]

    return enemy_meta and enemy_meta.is_boss == true or false
end

function BossRandomizer.random_boss(core)
    local enemies = core.state.pools and core.state.pools.enemies
    local boss_pool = enemies and enemies.bosses

    if not boss_pool or #boss_pool == 0 then
        return nil
    end

    return core:random_array_entry(boss_pool)
end

return BossRandomizer
