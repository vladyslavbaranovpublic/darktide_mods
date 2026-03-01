--[[
    File: Randomizer.lua
    Description: Main entry point for the Randomizer mod and module bootstrap.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local mod = get_mod("Randomizer")

local data_file = mod:io_dofile("Randomizer/scripts/mods/Randomizer/Randomizer_data")
local randomizer_data = data_file.randomizer_data or {}

local utils = mod:io_dofile("Randomizer/scripts/randomizer/utils")
local seed = mod:io_dofile("Randomizer/scripts/randomizer/seed")
local settings = mod:io_dofile("Randomizer/scripts/randomizer/settings")
local spawn_hooks = mod:io_dofile("Randomizer/scripts/randomizer/spawn_hooks")
local core_module = mod:io_dofile("Randomizer/scripts/randomizer/core")

local enemy_randomizer = mod:io_dofile("Randomizer/scripts/randomizer/spawn/enemy_randomizer")
local item_randomizer = mod:io_dofile("Randomizer/scripts/randomizer/spawn/item_randomizer")
local patrol_randomizer = mod:io_dofile("Randomizer/scripts/randomizer/spawn/patrol_randomizer")
local boss_randomizer = mod:io_dofile("Randomizer/scripts/randomizer/spawn/boss_randomizer")
local chaos_mode = mod:io_dofile("Randomizer/scripts/randomizer/spawn/chaos_mode")

mod.randomizer = core_module.new({
    mod = mod,
    data = randomizer_data,
    utils = utils,
    seed = seed,
    settings = settings,
    enemy_randomizer = enemy_randomizer,
    item_randomizer = item_randomizer,
    patrol_randomizer = patrol_randomizer,
    boss_randomizer = boss_randomizer,
    chaos_mode = chaos_mode,
})

spawn_hooks.register(mod, mod.randomizer)

mod.on_enabled = function()
    if mod.randomizer then
        mod.randomizer:on_enabled()
    end
end

mod.on_disabled = function()
    if mod.randomizer then
        mod.randomizer:on_disabled()
    end
end

mod.on_setting_changed = function(setting_id)
    if mod.randomizer then
        mod.randomizer:on_setting_changed(setting_id)
    end
end

mod:command("randomizer_seed", "Show current Randomizer seed.", function()
    if mod.randomizer then
        mod:echo(string.format("[Randomizer] Active seed: %s", tostring(mod.randomizer:get_active_seed())))
    end
end)

mod:command("randomizer_kill_all", "Despawn all currently spawned enemy minions (local-host only).", function()
    if mod.randomizer then
        local despawned = mod.randomizer:kill_all_enemies()

        mod:echo(string.format("[Randomizer] Kill-all executed. Despawned %d enemies.", despawned))
    end
end)
