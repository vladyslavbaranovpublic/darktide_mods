--[[
    File: Randomizer_localization.lua
    Description: Localization strings for Randomizer labels, descriptions, and UI text.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Breeds = require("scripts/settings/breed/breeds")
local BreedSettings = require("scripts/settings/breed/breed_settings")

local MINION_BREED_TYPE = BreedSettings.types.minion
local BLOCKED_RANDOMIZER_ENEMY_NAMES = {
    chaos_mutator_daemonhost = true,
}
local BLOCKED_RANDOMIZER_ENEMY_NAME_PATTERNS = {
    "daemonhost",
}

local localizations = {
    mod_name = {
        en = "{#color(70,205,195)}\xEE\x80\xAA Randomizer \xEE\x80\xAB{#reset()}",
    },
    mod_description = {
        en = "{#color(90,220,210)}Release 1.0.1{#reset()} | Author: LAUREHTE\n{#color(60,175,165)}Randomizes enemy and item spawns in local-controlled missions with seed support, fine-tuning, and optional chaos mode.{#reset()}",
    },

    group_randomizer_general = {
        en = "{#color(70,205,195)}Core ------------------------------------------------------------------------{#reset()}",
    },
    enable_randomizer = {
        en = "Enable Randomizer",
    },
    enable_randomizer_description = {
        en = "Master switch for all randomization hooks.",
    },
    debug_mode = {
        en = "Debug Mode",
    },
    debug_mode_description = {
        en = "Enable verbose Randomizer logs for diagnostics. When disabled, only major error logs are printed.",
    },
    action_kill_all_enemies = {
        en = "Kill All Enemies (Execute)",
    },
    action_kill_all_enemies_description = {
        en = "One-shot action. Set this to On to despawn all currently spawned enemy minions, then it auto-resets to Off. Local-host only.",
    },
    action_reset_darktide_defaults = {
        en = "Reset To Darktide Baseline (Execute)",
    },
    action_reset_darktide_defaults_description = {
        en = "One-shot action. Restores Randomizer settings to baseline default values, including category/source/archetype weights and enemy override checkboxes, then auto-resets to Off.",
    },
    seed_value = {
        en = "Seed (Optional)",
    },
    seed_value_description = {
        en = "Set a numeric seed for reproducible results. Use 0 to leave it unset.",
    },
    use_random_seed = {
        en = "Use Random Seed",
    },
    use_random_seed_description = {
        en = "Generate a random seed when a manual seed is not used.",
    },
    random_every_mission = {
        en = "Random Every Mission",
    },
    random_every_mission_description = {
        en = "Generate a fresh seed each mission start. Seed logging is shown only when Debug Mode is enabled.",
    },
    enable_fine_tuning = {
        en = "Enable Fine-Tuning",
    },
    enable_fine_tuning_description = {
        en = "Enable category toggles and per-category weighting.",
    },
    enable_chaos_mode = {
        en = "Enable Chaos Mode",
    },
    enable_chaos_mode_description = {
        en = "Ignores category/source/archetype weights and strict weight culling. Any enemy spawn can become any random valid enemy (with mission-critical safety guards).",
    },
    enable_difficulty_scaling = {
        en = "Difficulty Scaling",
    },
    enable_difficulty_scaling_description = {
        en = "Bias randomization toward tougher outcomes on higher difficulties.",
    },
    enemy_spawn_rate_multiplier = {
        en = "Enemy Spawn Rate Multiplier",
    },
    enemy_spawn_rate_multiplier_description = {
        en = "Spawns extra enemies per normal spawn (1.0x-5.0x) with safety caps. Higher values effectively raise encounter density and active enemy pressure.",
    },
    max_alive_enemies_cap = {
        en = "Max Alive Enemies Cap",
    },
    max_alive_enemies_cap_description = {
        en = "Maximum alive enemy minions allowed at once. 0 disables this cap. Overflow enemies are queued for safe despawn.",
    },
    strict_enemy_weight_enforcement = {
        en = "Strict Enemy Weight Enforcement",
    },
    strict_enemy_weight_enforcement_description = {
        en = "If enabled, enemies from disabled/zero-weight categories are force-despawned after spawn, including grouped spawns. Randomizer then attempts standalone weighted replacements; in Boss-Only setups, non-bosses are still culled even when boss replacement is temporarily blocked by boss safety timers/caps. Can alter scripted encounters and reduce stability.",
    },
    remove_boss_alive_limit = {
        en = "Remove Boss Alive Limit",
    },
    remove_boss_alive_limit_description = {
        en = "If enabled, Randomizer ignores its concurrent randomized-boss cap. Cooldown and other boss safety checks still apply.",
    },
    enable_refined_enemy_weights = {
        en = "Enable Refined Enemy Weights",
    },
    enable_refined_enemy_weights_description = {
        en = "Enable additional source and archetype enemy weighting layers. When OFF, all Source/Archetype sliders are ignored.",
    },

    group_randomizer_categories = {
        en = "{#color(70,205,195)}Category Toggles ------------------------------------------------------------{#reset()}",
    },
    randomize_regular_enemies = {
        en = "Regular Enemies",
    },
    randomize_regular_enemies_description = {
        en = "Allow randomization for non-elite, non-special, non-boss, non-horde enemy requests.",
    },
    randomize_elites = {
        en = "Elites",
    },
    randomize_elites_description = {
        en = "Allow randomization for elite enemy requests.",
    },
    randomize_specials = {
        en = "Specials",
    },
    randomize_specials_description = {
        en = "Allow randomization for special enemy requests.",
    },
    randomize_bosses = {
        en = "Bosses",
    },
    randomize_bosses_description = {
        en = "Allow randomization for boss requests.",
    },
    randomize_patrols = {
        en = "Patrols",
    },
    randomize_patrols_description = {
        en = "Allow patrol-capable enemies to be randomized through patrol weighting.",
    },
    randomize_hordes = {
        en = "Hordes",
    },
    randomize_hordes_description = {
        en = "Allow horde-tagged enemy requests to be randomized. Many common trash/melee/rifle enemies are horde-tagged.",
    },
    randomize_items = {
        en = "Items",
    },
    randomize_items_description = {
        en = "Allow item spawn randomization.",
    },

    group_randomizer_weights = {
        en = "{#color(70,205,195)}Category Weights ------------------------------------------------------------{#reset()}",
    },
    weight_regular = {
        en = "Weight: Regular",
    },
    weight_regular_description = {
        en = "Relative chance (0-100) for non-horde regular enemies in weighted randomization.",
    },
    weight_elites = {
        en = "Weight: Elites",
    },
    weight_elites_description = {
        en = "Relative chance (0-100) for elites in weighted randomization.",
    },
    weight_specials = {
        en = "Weight: Specials",
    },
    weight_specials_description = {
        en = "Relative chance (0-100) for specials in weighted randomization.",
    },
    weight_bosses = {
        en = "Weight: Bosses",
    },
    weight_bosses_description = {
        en = "Relative chance (0-100) for bosses in weighted randomization.",
    },
    weight_patrols = {
        en = "Weight: Patrols",
    },
    weight_patrols_description = {
        en = "Relative chance (0-100) for patrol-capable enemies in weighted randomization.",
    },
    weight_hordes = {
        en = "Weight: Hordes",
    },
    weight_hordes_description = {
        en = "Relative chance (0-100) for horde-tagged enemies in weighted randomization. Setting this to 0 removes many common trash units in strict mode.",
    },
    weight_items = {
        en = "Weight: Items",
    },
    weight_items_description = {
        en = "Replacement chance only (0-100). This decides whether the original spawned item gets replaced. It does NOT increase total item count.",
    },
    group_randomizer_refined_weights = {
        en = "{#color(70,205,195)}Refined Enemy Weights -------------------------------------------------------{#reset()}",
    },
    source_weight_roamer = {
        en = "Source Weight: Roamer",
    },
    source_weight_roamer_description = {
        en = "Chance weight (0-100) for randomization on roamer-style enemy spawn requests.",
    },
    source_weight_horde = {
        en = "Source Weight: Horde",
    },
    source_weight_horde_description = {
        en = "Chance weight (0-100) for randomization on horde/group horde spawn requests.",
    },
    source_weight_patrol = {
        en = "Source Weight: Patrol",
    },
    source_weight_patrol_description = {
        en = "Chance weight (0-100) for randomization on patrol-tagged spawn requests.",
    },
    source_weight_special_event = {
        en = "Source Weight: Special Event",
    },
    source_weight_special_event_description = {
        en = "Chance weight (0-100) for randomization on special-event style spawn requests.",
    },
    source_weight_monster_event = {
        en = "Source Weight: Monster Event",
    },
    source_weight_monster_event_description = {
        en = "Chance weight (0-100) for randomization on monster-event style spawn requests.",
    },
    source_weight_scripted = {
        en = "Source Weight: Scripted",
    },
    source_weight_scripted_description = {
        en = "Chance weight (0-100) for randomization on scripted/spawner/objective spawn requests.",
    },
    source_weight_unknown = {
        en = "Source Weight: Unknown",
    },
    source_weight_unknown_description = {
        en = "Chance weight (0-100) for randomization on spawn requests that cannot be classified safely.",
    },
    archetype_weight_regular_melee = {
        en = "Archetype Weight: Regular Melee",
    },
    archetype_weight_regular_melee_description = {
        en = "Selection weight (0-100) for regular melee archetype candidates.",
    },
    archetype_weight_regular_ranged = {
        en = "Archetype Weight: Regular Ranged",
    },
    archetype_weight_regular_ranged_description = {
        en = "Selection weight (0-100) for regular ranged archetype candidates.",
    },
    archetype_weight_elite_melee = {
        en = "Archetype Weight: Elite Melee",
    },
    archetype_weight_elite_melee_description = {
        en = "Selection weight (0-100) for elite melee archetype candidates.",
    },
    archetype_weight_elite_ranged = {
        en = "Archetype Weight: Elite Ranged",
    },
    archetype_weight_elite_ranged_description = {
        en = "Selection weight (0-100) for elite ranged archetype candidates.",
    },
    archetype_weight_elite_ogryn = {
        en = "Archetype Weight: Elite Ogryn",
    },
    archetype_weight_elite_ogryn_description = {
        en = "Selection weight (0-100) for elite ogryn archetype candidates.",
    },
    archetype_weight_special_disabler = {
        en = "Archetype Weight: Special Disabler",
    },
    archetype_weight_special_disabler_description = {
        en = "Selection weight (0-100) for disabler special archetype candidates.",
    },
    archetype_weight_special_ranged = {
        en = "Archetype Weight: Special Ranged",
    },
    archetype_weight_special_ranged_description = {
        en = "Selection weight (0-100) for ranged special archetype candidates.",
    },
    archetype_weight_special_aoe = {
        en = "Archetype Weight: Special AOE",
    },
    archetype_weight_special_aoe_description = {
        en = "Selection weight (0-100) for AOE special archetype candidates.",
    },
    archetype_weight_boss_monstrosity = {
        en = "Archetype Weight: Boss Monstrosity",
    },
    archetype_weight_boss_monstrosity_description = {
        en = "Selection weight (0-100) for monstrosity boss archetype candidates.",
    },
    archetype_weight_boss_captain = {
        en = "Archetype Weight: Boss Captain",
    },
    archetype_weight_boss_captain_description = {
        en = "Selection weight (0-100) for captain-style boss archetype candidates.",
    },

    group_randomizer_items = {
        en = "{#color(70,205,195)}Item Fine-Tuning ------------------------------------------------------------{#reset()}",
    },
    group_randomizer_enemy_overrides = {
        en = "{#color(70,205,195)}Enemy Spawn Overrides ------------------------------------------------------{#reset()}",
    },
    group_randomizer_enemy_overrides_description = {
        en = "Disable specific enemy breeds from being spawned by Randomizer. This list is generated from all valid minion breeds.",
    },
    item_spawn_rate_multiplier = {
        en = "Item Spawn Rate Multiplier",
    },
    item_spawn_rate_multiplier_description = {
        en = "Scales mission pickup counts (1.0x-10.0x) and performs an extra fill pass on empty valid item locations. Only applies when Item category is enabled and Item weight is above 0.",
    },
    disable_material_spawns = {
        en = "Disable Material Spawns",
    },
    disable_material_spawns_description = {
        en = "If the game tries to spawn plasteel/diamantine, Randomizer replaces it with non-material items.",
    },
    spawn_extra_random_items = {
        en = "Spawn Extra Random Items",
    },
    spawn_extra_random_items_description = {
        en = "Enables the separate chance-based bonus item system. This is independent from the Item Spawn Rate Multiplier.",
    },
    extra_random_item_chance = {
        en = "Extra Item Chance",
    },
    extra_random_item_chance_description = {
        en = "When the bonus item system is enabled, this is the chance (0-100) to spawn one extra randomized item on top of the normal spawn.",
    },
    extra_random_item_max_per_mission = {
        en = "Extra Items Max/Mission",
    },
    extra_random_item_max_per_mission_description = {
        en = "Safety cap for the bonus item system so chance-based extra items cannot keep growing without limit in one mission.",
    },
    item_weight_stims = {
        en = "Item Weight: Stims",
    },
    item_weight_stims_description = {
        en = "Type selection weight. Higher means replacement/extra item picks are more likely to be stims. This affects WHAT item is chosen, not how many spawn.",
    },
    item_weight_medkits = {
        en = "Item Weight: Medkits",
    },
    item_weight_medkits_description = {
        en = "Type selection weight. Set this high and other item weights low/zero to force mostly medkits.",
    },
    item_weight_ammo = {
        en = "Item Weight: Ammo",
    },
    item_weight_ammo_description = {
        en = "Type selection weight for ammo pickups.",
    },
    item_weight_ammo_crate = {
        en = "Item Weight: Ammo Crate",
    },
    item_weight_ammo_crate_description = {
        en = "Within the Ammo class only, controls ammo cache preference versus clip ammo. 0 = never ammo crate when alternatives exist, 100 = always ammo crate when possible.",
    },
    item_weight_grenades = {
        en = "Item Weight: Grenades",
    },
    item_weight_grenades_description = {
        en = "Type selection weight for grenade/breach-charge style pickups.",
    },
    item_weight_materials = {
        en = "Item Weight: Materials",
    },
    item_weight_materials_description = {
        en = "Type selection weight for plasteel/diamantine when materials are allowed.",
    },
    item_weight_deployables = {
        en = "Item Weight: Deployables",
    },
    item_weight_deployables_description = {
        en = "Type selection weight for deployable items.",
    },
    item_weight_pocketables = {
        en = "Item Weight: Pocketables",
    },
    item_weight_pocketables_description = {
        en = "Type selection weight for pocketable items.",
    },
    item_weight_misc = {
        en = "Item Weight: Misc",
    },
    item_weight_misc_description = {
        en = "Type selection weight for miscellaneous items.",
    },
}

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

local function _format_breed_label(breed_name)
    local tokens = {}

    for token in string.gmatch(tostring(breed_name), "[^_]+") do
        local first = string.sub(token, 1, 1)
        local rest = string.sub(token, 2)

        tokens[#tokens + 1] = string.upper(first) .. rest
    end

    return table.concat(tokens, " ")
end

local function _collect_enemy_breeds()
    local breed_names = {}

    for breed_name, breed_data in pairs(Breeds) do
        local valid_key = type(breed_name) == "string"
        local blocked = valid_key and BLOCKED_RANDOMIZER_ENEMY_NAMES[breed_name] == true or false

        if valid_key and not blocked then
            for i = 1, #BLOCKED_RANDOMIZER_ENEMY_NAME_PATTERNS do
                local pattern = BLOCKED_RANDOMIZER_ENEMY_NAME_PATTERNS[i]

                if string.find(breed_name, pattern, 1, true) then
                    blocked = true
                    break
                end
            end
        end

        local valid_enemy = type(breed_name) == "string"
            and type(breed_data) == "table"
            and breed_data.breed_type == MINION_BREED_TYPE
            and breed_data.unit_template_name ~= nil
            and not blocked

        if valid_enemy then
            breed_names[#breed_names + 1] = breed_name
        end
    end

    table.sort(breed_names)

    return breed_names
end

local function _append_enemy_override_localizations()
    local used_setting_ids = {}
    local breed_names = _collect_enemy_breeds()

    for i = 1, #breed_names do
        local breed_name = breed_names[i]
        local base_setting_id = "disable_enemy_" .. _sanitize_setting_token(breed_name)
        local setting_id = base_setting_id
        local suffix = 2

        while used_setting_ids[setting_id] do
            setting_id = string.format("%s_%d", base_setting_id, suffix)
            suffix = suffix + 1
        end

        used_setting_ids[setting_id] = true

        localizations[setting_id] = {
            en = string.format("Disable: %s", _format_breed_label(breed_name)),
        }
        localizations[setting_id .. "_description"] = {
            en = string.format("If enabled, '%s' cannot be selected as a randomized enemy spawn.", breed_name),
        }
    end
end

_append_enemy_override_localizations()

return localizations
