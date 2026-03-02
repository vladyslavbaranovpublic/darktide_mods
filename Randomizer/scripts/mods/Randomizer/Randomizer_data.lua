--[[
    File: Randomizer_data.lua
    Description: Mod settings, spawn pools, weight tables, and difficulty scaling data.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local mod = get_mod("Randomizer")

local Breeds = require("scripts/settings/breed/breeds")
local BreedSettings = require("scripts/settings/breed/breed_settings")
local Pickups = require("scripts/settings/pickup/pickups")

local RandomizerData = {}

RandomizerData.category_order = {
    "regular",
    "elites",
    "specials",
    "bosses",
    "patrols",
    "hordes",
    "items",
}

RandomizerData.default_weights = {
    regular = 100,
    elites = 70,
    specials = 65,
    bosses = 20,
    patrols = 55,
    hordes = 85,
    items = 100,
}

RandomizerData.source_weight_order = {
    "roamer",
    "horde",
    "patrol",
    "special_event",
    "monster_event",
    "scripted",
    "unknown",
}

RandomizerData.source_default_weights = {
    roamer = 100,
    horde = 100,
    patrol = 100,
    special_event = 100,
    monster_event = 100,
    scripted = 100,
    unknown = 100,
}

RandomizerData.enemy_archetype_order = {
    "regular_melee",
    "regular_ranged",
    "elite_melee",
    "elite_ranged",
    "elite_ogryn",
    "special_disabler",
    "special_ranged",
    "special_aoe",
    "boss_monstrosity",
    "boss_captain",
}

RandomizerData.enemy_archetype_default_weights = {
    regular_melee = 100,
    regular_ranged = 100,
    elite_melee = 100,
    elite_ranged = 100,
    elite_ogryn = 100,
    special_disabler = 100,
    special_ranged = 100,
    special_aoe = 100,
    boss_monstrosity = 100,
    boss_captain = 100,
}

RandomizerData.item_class_order = {
    "stims",
    "medkits",
    "ammo",
    "grenades",
    "materials",
    "deployables",
    "pocketables",
    "misc",
}

RandomizerData.item_class_default_weights = {
    stims = 30,
    medkits = 25,
    ammo = 20,
    grenades = 15,
    materials = 10,
    deployables = 20,
    pocketables = 15,
    misc = 20,
}

RandomizerData.item_specific_default_weights = {
    ammo_crate = 50,
}

RandomizerData.weight_tables = {
    default = {
        regular = 100,
        elites = 70,
        specials = 65,
        bosses = 20,
        patrols = 55,
        hordes = 85,
        items = 100,
    },
    danger_high = {
        regular = 45,
        elites = 90,
        specials = 95,
        bosses = 100,
        patrols = 75,
        hordes = 60,
        items = 25,
    },
    safer = {
        regular = 100,
        elites = 45,
        specials = 35,
        bosses = 20,
        patrols = 40,
        hordes = 90,
        items = 100,
    },
}

RandomizerData.difficulty_scaling = {
    [1] = {
        regular = 1.35,
        elites = 0.65,
        specials = 0.55,
        bosses = 0.35,
        patrols = 0.70,
        hordes = 1.10,
        items = 1.10,
    },
    [2] = {
        regular = 1.20,
        elites = 0.80,
        specials = 0.75,
        bosses = 0.55,
        patrols = 0.85,
        hordes = 1.05,
        items = 1.05,
    },
    [3] = {
        regular = 1.00,
        elites = 1.00,
        specials = 1.00,
        bosses = 1.00,
        patrols = 1.00,
        hordes = 1.00,
        items = 1.00,
    },
    [4] = {
        regular = 0.85,
        elites = 1.20,
        specials = 1.25,
        bosses = 1.35,
        patrols = 1.10,
        hordes = 0.95,
        items = 0.95,
    },
    [5] = {
        regular = 0.70,
        elites = 1.40,
        specials = 1.55,
        bosses = 1.80,
        patrols = 1.25,
        hordes = 0.85,
        items = 0.90,
    },
}

RandomizerData.safety = {
    -- Maximum number of randomizer-created bosses alive at once (does not block mission-scripted bosses).
    max_randomized_bosses_alive = 4,
    -- Absolute emergency cap used by strict boss-only mode to prevent runaway boss flooding.
    max_randomized_bosses_alive_hard_cap = 12,
    -- Cooldown between randomizer-created boss spawns.
    boss_min_seconds_between_random_spawns = 30,
    -- Prevent randomizer-created bosses during initial mission warmup.
    boss_warmup_seconds = 30,
    -- Extra randomized item spawn controls.
    extra_items_min_seconds_between_spawns = 0.15,
    -- Extra enemy spawn controls from enemy spawn rate multiplier.
    max_extra_enemies_alive = 100,
    max_extra_enemies_per_mission = 2000,
    -- Delay extra randomizer-created enemies at mission start to avoid pre-pacing spikes.
    extra_enemy_warmup_seconds = 20,
    -- How many update passes a pending strict-despawn unit can be retried before dropping.
    max_pending_enemy_despawn_retries = 30,
}

RandomizerData.protected_pickup_names = {
    communications_hack_device = true,
    consumable = true,
    grimoire = true,
    tome = true,
}

RandomizerData.protected_pickup_groups = {
    luggable = true,
}

RandomizerData.blocked_randomizer_pickup_names = {
    -- Known unstable pickup for random spawning in normal missions; can produce invalid HUD icon state.
    breach_charge_pocketable = true,
}

RandomizerData.blocked_randomizer_enemy_names = {
    -- Daemonhost variants are tightly coupled to scripted placement/nav constraints.
    chaos_mutator_daemonhost = true,
}

RandomizerData.blocked_randomizer_enemy_name_patterns = {
    "daemonhost",
}

-- Enemy breeds that should default to "disabled" when running the baseline reset action.
RandomizerData.reset_default_disabled_enemy_breeds = {
    "cultist_ritualist",
    "cultist_flamer",
}

local MINION_BREED_TYPE = BreedSettings.types.minion

local function _sanitize_setting_token(value)
    local token = string.lower(tostring(value or "unknown"))

    token = token:gsub("[^%w]", "_")
    token = token:gsub("_+", "_")
    token = token:gsub("^_+", "")
    token = token:gsub("_+$", "")

    if token == "" then
        token = "unknown"
    end

    return token
end

local function _append(array, value)
    array[#array + 1] = value
end

local function _is_enemy_blocked_for_randomizer(breed_name)
    if type(breed_name) ~= "string" then
        return true
    end

    if RandomizerData.blocked_randomizer_enemy_names[breed_name] == true then
        return true
    end

    local patterns = RandomizerData.blocked_randomizer_enemy_name_patterns or {}

    for i = 1, #patterns do
        local pattern = patterns[i]

        if type(pattern) == "string" and pattern ~= "" and string.find(breed_name, pattern, 1, true) then
            return true
        end
    end

    return false
end

local function _build_enemy_disable_setting_maps(enemy_pool)
    local ordered_breeds = {}
    local setting_by_breed = {}
    local used_setting_ids = {}

    if type(enemy_pool) ~= "table" then
        return ordered_breeds, setting_by_breed
    end

    for i = 1, #enemy_pool do
        local breed_name = enemy_pool[i]

        if type(breed_name) == "string" then
            local base_setting_id = "disable_enemy_" .. _sanitize_setting_token(breed_name)
            local setting_id = base_setting_id
            local suffix = 2

            while used_setting_ids[setting_id] do
                setting_id = string.format("%s_%d", base_setting_id, suffix)
                suffix = suffix + 1
            end

            used_setting_ids[setting_id] = true
            _append(ordered_breeds, breed_name)

            setting_by_breed[breed_name] = setting_id
        end
    end

    return ordered_breeds, setting_by_breed
end

local function _classify_breed(breed_name, breed)
    local normalized_name = string.lower(tostring(breed_name or ""))
    local tags = breed.tags or {}
    local blackboard_component_config = breed.blackboard_component_config
    local has_patrol_blackboard = type(blackboard_component_config) == "table"
        and blackboard_component_config.patrol ~= nil

    local is_boss = breed.is_boss == true or tags.monster == true
    local is_special = tags.special == true
    local is_elite = tags.elite == true
    local is_horde = tags.horde == true
    local can_patrol = breed.can_patrol == true
    -- `can_patrol` alone is too broad; some breeds flagged with it do not expose
    -- a patrol blackboard component and can crash patrol behavior state machines.
    local is_patrol = can_patrol and has_patrol_blackboard

    local primary = "regular"

    if is_boss then
        primary = "bosses"
    elseif is_special then
        primary = "specials"
    elseif is_elite then
        primary = "elites"
    elseif is_horde then
        primary = "hordes"
    end

    local archetype

    if is_boss then
        local captain_like = string.find(normalized_name, "captain", 1, true)
            or string.find(normalized_name, "commander", 1, true)
            or string.find(normalized_name, "twin", 1, true)

        archetype = captain_like and "boss_captain" or "boss_monstrosity"
    elseif is_special then
        local disabler_like = string.find(normalized_name, "trapper", 1, true)
            or string.find(normalized_name, "hound", 1, true)
            or string.find(normalized_name, "dog", 1, true)
            or string.find(normalized_name, "mutant", 1, true)
            or string.find(normalized_name, "net", 1, true)
            or string.find(normalized_name, "grab", 1, true)
        local aoe_like = string.find(normalized_name, "burster", 1, true)
            or string.find(normalized_name, "bomber", 1, true)
            or string.find(normalized_name, "grenadier", 1, true)
            or string.find(normalized_name, "tox", 1, true)
            or string.find(normalized_name, "gas", 1, true)

        if disabler_like then
            archetype = "special_disabler"
        elseif aoe_like then
            archetype = "special_aoe"
        else
            archetype = "special_ranged"
        end
    elseif is_elite then
        local ogryn_like = string.find(normalized_name, "ogryn", 1, true)
            or string.find(normalized_name, "crusher", 1, true)
            or string.find(normalized_name, "bulwark", 1, true)
            or string.find(normalized_name, "reaper", 1, true)
        local ranged_like = string.find(normalized_name, "gunner", 1, true)
            or string.find(normalized_name, "shotgun", 1, true)
            or string.find(normalized_name, "sniper", 1, true)
            or string.find(normalized_name, "plasma", 1, true)
            or string.find(normalized_name, "rifle", 1, true)
            or string.find(normalized_name, "stubber", 1, true)

        if ogryn_like then
            archetype = "elite_ogryn"
        elseif ranged_like then
            archetype = "elite_ranged"
        else
            archetype = "elite_melee"
        end
    else
        local ranged_like = string.find(normalized_name, "rifle", 1, true)
            or string.find(normalized_name, "gunner", 1, true)
            or string.find(normalized_name, "shotgun", 1, true)
            or string.find(normalized_name, "sniper", 1, true)
            or string.find(normalized_name, "stubber", 1, true)
            or string.find(normalized_name, "flamer", 1, true)

        archetype = ranged_like and "regular_ranged" or "regular_melee"
    end

    return {
        is_boss = is_boss,
        is_special = is_special,
        is_elite = is_elite,
        is_horde = is_horde,
        is_patrol = is_patrol,
        can_patrol = can_patrol,
        has_patrol_blackboard = has_patrol_blackboard,
        primary = primary,
        archetype = archetype,
    }
end

local function _classify_pickup(pickup_name, pickup_data)
    local group = pickup_data.group or "misc"
    local interaction_type = pickup_data.interaction_type or "none"

    if group == "forge_material" or pickup_name == "small_metal" or pickup_name == "large_metal" or pickup_name == "small_platinum" or pickup_name == "large_platinum" then
        return "materials"
    end

    if string.find(pickup_name, "medical_crate", 1, true) then
        return "medkits"
    end

    if string.find(pickup_name, "syringe_", 1, true) then
        return "stims"
    end

    if string.find(pickup_name, "ammo_cache", 1, true) then
        return "ammo"
    end

    if string.find(pickup_name, "small_grenade", 1, true) or string.find(pickup_name, "breach_charge", 1, true) then
        return "grenades"
    end

    if group == "deployable" then
        return "deployables"
    end

    if group == "pocketable" then
        return "pocketables"
    end

    if interaction_type == "side_mission" or group == "side_mission_collect" then
        return "misc"
    end

    return "misc"
end

function RandomizerData.build_spawn_pools()
    local enemy_pools = {
        all = {},
        regular = {},
        elites = {},
        specials = {},
        bosses = {},
        patrols = {},
        hordes = {},
        by_archetype = {},
        by_name = {},
    }

    for i = 1, #RandomizerData.enemy_archetype_order do
        local archetype = RandomizerData.enemy_archetype_order[i]

        enemy_pools.by_archetype[archetype] = {}
    end

    for breed_name, breed in pairs(Breeds) do
        local valid_enemy = type(breed) == "table"
            and breed.breed_type == MINION_BREED_TYPE
            and type(breed_name) == "string"
            and breed.unit_template_name ~= nil
            and not _is_enemy_blocked_for_randomizer(breed_name)

        if valid_enemy then
            local meta = _classify_breed(breed_name, breed)

            enemy_pools.by_name[breed_name] = meta
            _append(enemy_pools.all, breed_name)

            if type(meta.archetype) == "string" and type(enemy_pools.by_archetype[meta.archetype]) == "table" then
                _append(enemy_pools.by_archetype[meta.archetype], breed_name)
            end

            if meta.primary == "regular" then
                _append(enemy_pools.regular, breed_name)
            end

            if meta.is_elite then
                _append(enemy_pools.elites, breed_name)
            end

            if meta.is_special then
                _append(enemy_pools.specials, breed_name)
            end

            if meta.is_boss then
                _append(enemy_pools.bosses, breed_name)
            end

            if meta.is_horde then
                _append(enemy_pools.hordes, breed_name)
            end

            if meta.is_patrol then
                _append(enemy_pools.patrols, breed_name)
            end
        end
    end

    local item_pools = {
        all = {},
        safe = {},
        safe_non_materials = {},
        by_group = {},
        by_class = {},
        safe_by_class = {},
        by_name = {},
    }

    for i = 1, #RandomizerData.item_class_order do
        local class_name = RandomizerData.item_class_order[i]

        item_pools.by_class[class_name] = {}
        item_pools.safe_by_class[class_name] = {}
    end

    for pickup_name, pickup_data in pairs(Pickups.by_name) do
        local valid_pickup = type(pickup_data) == "table"
            and pickup_data.unit_name ~= nil
            and type(pickup_name) == "string"
            and RandomizerData.blocked_randomizer_pickup_names[pickup_name] ~= true

        if valid_pickup then
            local group = pickup_data.group or "misc"

            if not item_pools.by_group[group] then
                item_pools.by_group[group] = {}
            end

            local is_mission_critical = pickup_data.is_side_mission_pickup == true
                or pickup_data.interaction_type == "side_mission"
                or RandomizerData.protected_pickup_names[pickup_name] == true
                or RandomizerData.protected_pickup_groups[group] == true
            local item_class = _classify_pickup(pickup_name, pickup_data)

            item_pools.by_name[pickup_name] = {
                group = group,
                interaction_type = pickup_data.interaction_type,
                is_mission_critical = is_mission_critical,
                item_class = item_class,
            }

            _append(item_pools.by_group[group], pickup_name)
            _append(item_pools.all, pickup_name)
            _append(item_pools.by_class[item_class], pickup_name)

            if not is_mission_critical then
                _append(item_pools.safe, pickup_name)
                _append(item_pools.safe_by_class[item_class], pickup_name)

                if item_class ~= "materials" then
                    _append(item_pools.safe_non_materials, pickup_name)
                end
            end
        end
    end

    local pools_to_sort = {
        enemy_pools.all,
        enemy_pools.regular,
        enemy_pools.elites,
        enemy_pools.specials,
        enemy_pools.bosses,
        enemy_pools.patrols,
        enemy_pools.hordes,
        item_pools.all,
        item_pools.safe,
        item_pools.safe_non_materials,
    }

    for i = 1, #pools_to_sort do
        table.sort(pools_to_sort[i])
    end

    for group, entries in pairs(item_pools.by_group) do
        if type(group) == "string" and type(entries) == "table" then
            table.sort(entries)
        end
    end

    for item_class, entries in pairs(item_pools.by_class) do
        if type(item_class) == "string" and type(entries) == "table" then
            table.sort(entries)
        end
    end

    for item_class, entries in pairs(item_pools.safe_by_class) do
        if type(item_class) == "string" and type(entries) == "table" then
            table.sort(entries)
        end
    end

    for archetype, entries in pairs(enemy_pools.by_archetype) do
        if type(archetype) == "string" and type(entries) == "table" then
            table.sort(entries)
        end
    end

    return {
        enemies = enemy_pools,
        items = item_pools,
    }
end

local initial_pools = RandomizerData.build_spawn_pools()
RandomizerData.enemy_disable_order, RandomizerData.enemy_disable_setting_by_breed = _build_enemy_disable_setting_maps(initial_pools.enemies and initial_pools.enemies.all)
RandomizerData.is_enemy_blocked_for_randomizer = _is_enemy_blocked_for_randomizer

local function _build_enemy_override_group_widget()
    local sub_widgets = {}
    local ordered_breeds = RandomizerData.enemy_disable_order or {}
    local setting_by_breed = RandomizerData.enemy_disable_setting_by_breed or {}

    for i = 1, #ordered_breeds do
        local breed_name = ordered_breeds[i]
        local setting_id = setting_by_breed[breed_name]

        if type(setting_id) == "string" then
            _append(sub_widgets, {
                setting_id = setting_id,
                type = "checkbox",
                default_value = false,
            })
        end
    end

    return {
        setting_id = "group_randomizer_enemy_overrides",
        type = "group",
        sub_widgets = sub_widgets,
    }
end

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

local function _build_darktide_baseline_settings()
    local baseline = {
        enable_randomizer = true,
        use_vanilla_enemy_logic = false,
        use_vanilla_item_logic = false,
        debug_mode = false,
        action_kill_all_enemies = false,
        action_reset_darktide_defaults = false,
        seed_value = 0,
        use_random_seed = true,
        random_every_mission = false,
        enable_fine_tuning = true,
        enable_chaos_mode = false,
        enable_difficulty_scaling = true,
        enemy_spawn_rate_multiplier = 1.0,
        max_alive_enemies_cap = 0,
        strict_enemy_weight_enforcement = false,
        remove_boss_alive_limit = false,
        enable_refined_enemy_weights = false,
        item_spawn_rate_multiplier = 1.0,
        disable_material_spawns = false,
        spawn_extra_random_items = false,
        extra_random_item_chance = 0,
        extra_random_item_max_per_mission = 0,
    }

    for i = 1, #RandomizerData.category_order do
        local category = RandomizerData.category_order[i]
        local enabled_setting = CATEGORY_ENABLED_SETTING[category]
        local weight_setting = CATEGORY_WEIGHT_SETTING[category]

        if type(enabled_setting) == "string" then
            baseline[enabled_setting] = true
        end

        if type(weight_setting) == "string" then
            baseline[weight_setting] = math.max(0, math.floor(tonumber(RandomizerData.default_weights[category]) or 0))
        end
    end

    for i = 1, #RandomizerData.item_class_order do
        local item_class = RandomizerData.item_class_order[i]
        local setting_id = ITEM_CLASS_WEIGHT_SETTING[item_class]

        if type(setting_id) == "string" then
            baseline[setting_id] = math.max(0, math.floor(tonumber(RandomizerData.item_class_default_weights[item_class]) or 0))
        end
    end

    for item_key, setting_id in pairs(ITEM_SPECIFIC_WEIGHT_SETTING) do
        if type(setting_id) == "string" then
            baseline[setting_id] = math.max(0, math.floor(tonumber(RandomizerData.item_specific_default_weights[item_key]) or 0))
        end
    end

    for i = 1, #RandomizerData.source_weight_order do
        local source_name = RandomizerData.source_weight_order[i]
        local setting_id = SOURCE_WEIGHT_SETTING[source_name]

        if type(setting_id) == "string" then
            baseline[setting_id] = math.max(0, math.floor(tonumber(RandomizerData.source_default_weights[source_name]) or 100))
        end
    end

    for i = 1, #RandomizerData.enemy_archetype_order do
        local archetype = RandomizerData.enemy_archetype_order[i]
        local setting_id = ARCHETYPE_WEIGHT_SETTING[archetype]

        if type(setting_id) == "string" then
            baseline[setting_id] = math.max(0, math.floor(tonumber(RandomizerData.enemy_archetype_default_weights[archetype]) or 100))
        end
    end

    for _, setting_id in pairs(RandomizerData.enemy_disable_setting_by_breed or {}) do
        if type(setting_id) == "string" then
            baseline[setting_id] = false
        end
    end

    local reset_disabled_breeds = RandomizerData.reset_default_disabled_enemy_breeds or {}
    local setting_by_breed = RandomizerData.enemy_disable_setting_by_breed or {}

    for i = 1, #reset_disabled_breeds do
        local breed_name = reset_disabled_breeds[i]
        local setting_id = setting_by_breed[breed_name]

        if type(setting_id) == "string" then
            baseline[setting_id] = true
        end
    end

    return baseline
end

RandomizerData.darktide_baseline_settings = _build_darktide_baseline_settings()

local mod_data = {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "group_randomizer_general",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_randomizer",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "use_vanilla_enemy_logic",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "use_vanilla_item_logic",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "debug_mode",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "action_kill_all_enemies",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "action_reset_darktide_defaults",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "seed_value",
                        type = "numeric",
                        default_value = 0,
                        range = { 0, 2147483646 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "use_random_seed",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "random_every_mission",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "enable_fine_tuning",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "enable_chaos_mode",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "enable_difficulty_scaling",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "enemy_spawn_rate_multiplier",
                        type = "numeric",
                        default_value = 1.0,
                        range = { 1, 5 },
                        decimals_number = 1,
                    },
                    {
                        setting_id = "max_alive_enemies_cap",
                        type = "numeric",
                        default_value = 200,
                        range = { 0, 1000 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "strict_enemy_weight_enforcement",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "remove_boss_alive_limit",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "enable_refined_enemy_weights",
                        type = "checkbox",
                        default_value = false,
                    },
                },
            },
            {
                setting_id = "group_randomizer_categories",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "randomize_regular_enemies",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "randomize_elites",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "randomize_specials",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "randomize_bosses",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "randomize_patrols",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "randomize_hordes",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "randomize_items",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
            {
                setting_id = "group_randomizer_weights",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "weight_regular",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.regular,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "weight_elites",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.elites,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "weight_specials",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.specials,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "weight_bosses",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.bosses,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "weight_patrols",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.patrols,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "weight_hordes",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.hordes,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "weight_items",
                        type = "numeric",
                        default_value = RandomizerData.default_weights.items,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                },
            },
            {
                setting_id = "group_randomizer_refined_weights",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "source_weight_roamer",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.roamer,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "source_weight_horde",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.horde,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "source_weight_patrol",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.patrol,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "source_weight_special_event",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.special_event,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "source_weight_monster_event",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.monster_event,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "source_weight_scripted",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.scripted,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "source_weight_unknown",
                        type = "numeric",
                        default_value = RandomizerData.source_default_weights.unknown,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_regular_melee",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.regular_melee,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_regular_ranged",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.regular_ranged,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_elite_melee",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.elite_melee,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_elite_ranged",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.elite_ranged,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_elite_ogryn",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.elite_ogryn,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_special_disabler",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.special_disabler,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_special_ranged",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.special_ranged,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_special_aoe",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.special_aoe,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_boss_monstrosity",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.boss_monstrosity,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "archetype_weight_boss_captain",
                        type = "numeric",
                        default_value = RandomizerData.enemy_archetype_default_weights.boss_captain,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                },
            },
            {
                setting_id = "group_randomizer_items",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "item_spawn_rate_multiplier",
                        type = "numeric",
                        default_value = 1.0,
                        range = { 1, 10 },
                        decimals_number = 1,
                    },
                    {
                        setting_id = "disable_material_spawns",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "spawn_extra_random_items",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "extra_random_item_chance",
                        type = "numeric",
                        default_value = 10,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "extra_random_item_max_per_mission",
                        type = "numeric",
                        default_value = 25,
                        range = { 0, 300 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_stims",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.stims,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_medkits",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.medkits,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_ammo",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.ammo,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_ammo_crate",
                        type = "numeric",
                        default_value = RandomizerData.item_specific_default_weights.ammo_crate,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_grenades",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.grenades,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_materials",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.materials,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_deployables",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.deployables,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_pocketables",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.pocketables,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = "item_weight_misc",
                        type = "numeric",
                        default_value = RandomizerData.item_class_default_weights.misc,
                        range = { 0, 100 },
                        decimals_number = 0,
                    },
                },
            },
        },
    },
    randomizer_data = RandomizerData,
}

mod_data.options.widgets[#mod_data.options.widgets + 1] = _build_enemy_override_group_widget()

return mod_data
