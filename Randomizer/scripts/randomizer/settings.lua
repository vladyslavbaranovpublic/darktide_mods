--[[
    File: settings.lua
    Description: Runtime settings extraction and validation helpers.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Settings = {}

Settings.category_order = {
    "regular",
    "elites",
    "specials",
    "bosses",
    "patrols",
    "hordes",
    "items",
}

local CATEGORY_ENABLED_SETTING = {
    regular = "randomize_regular_enemies",
    elites = "randomize_elites",
    specials = "randomize_specials",
    bosses = "randomize_bosses",
    patrols = "randomize_patrols",
    hordes = "randomize_hordes",
    items = "randomize_items",
}

local CATEGORY_WEIGHT_SETTING = {
    regular = "weight_regular",
    elites = "weight_elites",
    specials = "weight_specials",
    bosses = "weight_bosses",
    patrols = "weight_patrols",
    hordes = "weight_hordes",
    items = "weight_items",
}

local ITEM_CLASS_WEIGHT_SETTING = {
    stims = "item_weight_stims",
    medkits = "item_weight_medkits",
    ammo = "item_weight_ammo",
    grenades = "item_weight_grenades",
    materials = "item_weight_materials",
    deployables = "item_weight_deployables",
    pocketables = "item_weight_pocketables",
    misc = "item_weight_misc",
}

local ITEM_SPECIFIC_WEIGHT_SETTING = {
    ammo_crate = "item_weight_ammo_crate",
}

local SOURCE_WEIGHT_SETTING = {
    roamer = "source_weight_roamer",
    horde = "source_weight_horde",
    patrol = "source_weight_patrol",
    special_event = "source_weight_special_event",
    monster_event = "source_weight_monster_event",
    scripted = "source_weight_scripted",
    unknown = "source_weight_unknown",
}

local ARCHETYPE_WEIGHT_SETTING = {
    regular_melee = "archetype_weight_regular_melee",
    regular_ranged = "archetype_weight_regular_ranged",
    elite_melee = "archetype_weight_elite_melee",
    elite_ranged = "archetype_weight_elite_ranged",
    elite_ogryn = "archetype_weight_elite_ogryn",
    special_disabler = "archetype_weight_special_disabler",
    special_ranged = "archetype_weight_special_ranged",
    special_aoe = "archetype_weight_special_aoe",
    boss_monstrosity = "archetype_weight_boss_monstrosity",
    boss_captain = "archetype_weight_boss_captain",
}

local SEED_RELATED_SETTINGS = {
    seed_value = true,
    use_random_seed = true,
    random_every_mission = true,
}

local function _read_boolean(mod, utils, setting_id, fallback)
    return utils.safe_get_setting(mod, setting_id, fallback) == true
end

function Settings.get_config(mod, data, utils)
    local defaults = data.default_weights or {}
    local item_defaults = data.item_class_default_weights or {}
    local item_specific_defaults = data.item_specific_default_weights or {}
    local item_class_order = data.item_class_order or {}
    local source_weight_order = data.source_weight_order or {}
    local source_default_weights = data.source_default_weights or {}
    local archetype_weight_order = data.enemy_archetype_order or {}
    local archetype_default_weights = data.enemy_archetype_default_weights or {}
    local fine_tuning_enabled = _read_boolean(mod, utils, "enable_fine_tuning", true)

    local config = {
        enable_randomizer = _read_boolean(mod, utils, "enable_randomizer", true),
        use_vanilla_enemy_logic = _read_boolean(mod, utils, "use_vanilla_enemy_logic", false),
        use_vanilla_item_logic = _read_boolean(mod, utils, "use_vanilla_item_logic", false),
        debug_mode = _read_boolean(mod, utils, "debug_mode", false),
        seed_value = math.floor(tonumber(utils.safe_get_setting(mod, "seed_value", 0)) or 0),
        use_random_seed = _read_boolean(mod, utils, "use_random_seed", true),
        random_every_mission = _read_boolean(mod, utils, "random_every_mission", false),
        enable_fine_tuning = fine_tuning_enabled,
        enable_chaos_mode = _read_boolean(mod, utils, "enable_chaos_mode", false),
        enable_difficulty_scaling = _read_boolean(mod, utils, "enable_difficulty_scaling", true),
        enemy_spawn_rate_multiplier = utils.clamp(tonumber(utils.safe_get_setting(mod, "enemy_spawn_rate_multiplier", 1.0)) or 1.0, 1.0, 5.0),
        max_alive_enemies_cap = math.max(0, math.floor((tonumber(utils.safe_get_setting(mod, "max_alive_enemies_cap", 0)) or 0) + 0.5)),
        strict_enemy_weight_enforcement = _read_boolean(mod, utils, "strict_enemy_weight_enforcement", false),
        remove_boss_alive_limit = _read_boolean(mod, utils, "remove_boss_alive_limit", false),
        enable_refined_enemy_weights = _read_boolean(mod, utils, "enable_refined_enemy_weights", false),
        item_spawn_rate_multiplier = utils.clamp(tonumber(utils.safe_get_setting(mod, "item_spawn_rate_multiplier", 1.0)) or 1.0, 1.0, 10.0),
        disable_material_spawns = _read_boolean(mod, utils, "disable_material_spawns", false),
        spawn_extra_random_items = _read_boolean(mod, utils, "spawn_extra_random_items", false),
        extra_random_item_chance = utils.clamp(math.floor((tonumber(utils.safe_get_setting(mod, "extra_random_item_chance", 0)) or 0) + 0.5), 0, 100),
        extra_random_item_max_per_mission = math.max(0, math.floor((tonumber(utils.safe_get_setting(mod, "extra_random_item_max_per_mission", 0)) or 0) + 0.5)),
        categories = {},
        weights = {},
        item_weights = {},
        item_specific_weights = {},
        source_weights = {},
        archetype_weights = {},
        disabled_enemy_breeds = {},
    }

    for i = 1, #Settings.category_order do
        local category = Settings.category_order[i]
        local default_weight = defaults[category] or 100

        if fine_tuning_enabled then
            local enabled_setting = CATEGORY_ENABLED_SETTING[category]
            local weight_setting = CATEGORY_WEIGHT_SETTING[category]
            local enabled = _read_boolean(mod, utils, enabled_setting, true)
            local weight = tonumber(utils.safe_get_setting(mod, weight_setting, default_weight)) or default_weight

            config.categories[category] = enabled
            config.weights[category] = utils.clamp(math.floor(weight + 0.5), 0, 100)
        else
            config.categories[category] = true
            config.weights[category] = utils.clamp(default_weight, 0, 100)
        end
    end

    for i = 1, #item_class_order do
        local item_class = item_class_order[i]
        local setting_id = ITEM_CLASS_WEIGHT_SETTING[item_class]
        local default_weight = item_defaults[item_class] or 0
        local configured_weight = tonumber(utils.safe_get_setting(mod, setting_id, default_weight)) or default_weight

        config.item_weights[item_class] = utils.clamp(math.floor(configured_weight + 0.5), 0, 100)
    end

    for item_key, setting_id in pairs(ITEM_SPECIFIC_WEIGHT_SETTING) do
        local default_weight = tonumber(item_specific_defaults[item_key]) or 0
        local configured_weight = tonumber(utils.safe_get_setting(mod, setting_id, default_weight)) or default_weight

        config.item_specific_weights[item_key] = utils.clamp(math.floor(configured_weight + 0.5), 0, 100)
    end

    for i = 1, #source_weight_order do
        local source_name = source_weight_order[i]
        local setting_id = SOURCE_WEIGHT_SETTING[source_name]
        local default_weight = tonumber(source_default_weights[source_name]) or 100
        local configured_weight = default_weight

        if type(setting_id) == "string" then
            configured_weight = tonumber(utils.safe_get_setting(mod, setting_id, default_weight)) or default_weight
        end

        config.source_weights[source_name] = utils.clamp(math.floor(configured_weight + 0.5), 0, 100)
    end

    for i = 1, #archetype_weight_order do
        local archetype_name = archetype_weight_order[i]
        local setting_id = ARCHETYPE_WEIGHT_SETTING[archetype_name]
        local default_weight = tonumber(archetype_default_weights[archetype_name]) or 100
        local configured_weight = default_weight

        if type(setting_id) == "string" then
            configured_weight = tonumber(utils.safe_get_setting(mod, setting_id, default_weight)) or default_weight
        end

        config.archetype_weights[archetype_name] = utils.clamp(math.floor(configured_weight + 0.5), 0, 100)
    end

    local enemy_disable_settings = data.enemy_disable_setting_by_breed or {}

    for breed_name, setting_id in pairs(enemy_disable_settings) do
        if type(breed_name) == "string" and type(setting_id) == "string" then
            if _read_boolean(mod, utils, setting_id, false) then
                config.disabled_enemy_breeds[breed_name] = true
            end
        end
    end

    return config
end

function Settings.is_seed_related_setting(setting_id)
    return SEED_RELATED_SETTINGS[setting_id] == true
end

function Settings.category_enabled(config, category)
    return config and config.categories and config.categories[category] ~= false
end

function Settings.weight_for(config, category, fallback)
    if not config or not config.weights then
        return fallback
    end

    return config.weights[category] or fallback
end

return Settings
