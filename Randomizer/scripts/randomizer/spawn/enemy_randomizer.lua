--[[
    File: enemy_randomizer.lua
    Description: Enemy spawn replacement logic with category weighting and difficulty scaling.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local EnemyRandomizer = {}

local CATEGORY_ORDER = {
    "regular",
    "elites",
    "specials",
    "bosses",
    "patrols",
    "hordes",
}

local function _clamp_0_100(value)
    local numeric = tonumber(value) or 0

    if numeric < 0 then
        return 0
    end

    if numeric > 100 then
        return 100
    end

    return numeric
end

local function _is_enemy_disabled(config, breed_name)
    return config and config.disabled_enemy_breeds and config.disabled_enemy_breeds[breed_name] == true or false
end

local function _requested_category(core, requested_breed)
    if core.boss_randomizer and core.boss_randomizer.is_boss(core, requested_breed) then
        return "bosses"
    end

    local enemy_meta = core.state.pools.enemies.by_name[requested_breed]

    if not enemy_meta then
        return "regular"
    end

    if enemy_meta.is_special then
        return "specials"
    end

    if enemy_meta.is_elite then
        return "elites"
    end

    if enemy_meta.is_horde then
        return "hordes"
    end

    if core.patrol_randomizer and core.patrol_randomizer.is_patrol(core, requested_breed) then
        return "patrols"
    end

    return "regular"
end

local function _resolve_spawn_source(requested_meta, context)
    if type(context) == "table" and type(context.spawn_source) == "string" then
        return context.spawn_source
    end

    local optional_param_table = context and context.optional_param_table

    if requested_meta and requested_meta.is_boss == true then
        return "monster_event"
    end

    if requested_meta and requested_meta.is_special == true then
        return "special_event"
    end

    if type(optional_param_table) == "table" then
        if optional_param_table.optional_mission_objective_id ~= nil
            or optional_param_table.optional_spawner_unit ~= nil
            or optional_param_table.optional_spawn_delay ~= nil
        then
            return "scripted"
        end

        if optional_param_table.optional_group_id ~= nil then
            if requested_meta and requested_meta.is_patrol == true then
                return "patrol"
            end

            if requested_meta and requested_meta.is_horde == true then
                return "horde"
            end

            return "roamer"
        end
    end

    if requested_meta and (requested_meta.is_horde == true or requested_meta.is_patrol == true) then
        return requested_meta.is_patrol == true and "patrol" or "horde"
    end

    if requested_meta then
        return "roamer"
    end

    return "unknown"
end

local function _source_allows_randomization(core, config, source_key)
    if not config or config.enable_refined_enemy_weights ~= true then
        return true
    end

    local source_weights = config.source_weights or {}
    local configured_weight = _clamp_0_100(source_weights[source_key] or source_weights.unknown or 100)

    if configured_weight <= 0 then
        return false
    end

    if configured_weight >= 100 then
        return true
    end

    return core:next_float() <= (configured_weight / 100)
end

local function _candidate_archetype_weight(config, candidate_meta)
    if not config or config.enable_refined_enemy_weights ~= true then
        return 100
    end

    local archetype_weights = config.archetype_weights or {}
    local archetype = candidate_meta and candidate_meta.archetype

    return _clamp_0_100(archetype and archetype_weights[archetype] or 100)
end

local function _is_compatible_replacement(core, requested_breed, requested_meta, selected_category, candidate_breed, config)
    if type(candidate_breed) ~= "string" then
        return false
    end

    if core:is_enemy_blocked_for_randomizer(candidate_breed) then
        return false
    end

    if _is_enemy_disabled(config, candidate_breed) then
        return false
    end

    local candidate_meta = core.state.pools.enemies.by_name[candidate_breed]

    if not candidate_meta then
        return false
    end

    if _candidate_archetype_weight(config, candidate_meta) <= 0 then
        return false
    end

    -- Patrol requests require patrol-capable replacement to keep patrol blackboard usage valid.
    if requested_meta and requested_meta.is_patrol and not candidate_meta.is_patrol then
        return false
    end
    -- Do not inject patrol-only breeds into non-patrol requests; patrol behavior can
    -- assume patrol group state and break mission AI when spawned standalone.
    if requested_meta and not requested_meta.is_patrol and candidate_meta.is_patrol then
        return false
    end

    local requested_is_boss = requested_meta and requested_meta.is_boss == true or false
    local candidate_is_boss = candidate_meta.is_boss == true

    if requested_is_boss and not candidate_is_boss then
        return false
    end

    if requested_is_boss and candidate_is_boss then
        local requested_archetype = requested_meta and requested_meta.archetype
        local candidate_archetype = candidate_meta and candidate_meta.archetype

        if type(requested_archetype) == "string"
            and type(candidate_archetype) == "string"
            and requested_archetype ~= candidate_archetype
        then
            -- Boss mutator/script flows can assume specific boss extension contracts.
            -- Keep replacement within the same boss archetype family.
            return false
        end
    end

    if candidate_is_boss and not requested_is_boss then
        -- Outside chaos mode, bosses should only come from the explicit boss category.
        if selected_category ~= "bosses" then
            return false
        end

        if not core:can_spawn_random_boss(requested_breed, config) then
            return false
        end
    end

    return true
end

local function _random_compatible_from_pool(core, pool, requested_breed, requested_meta, selected_category, config)
    if type(pool) ~= "table" or #pool == 0 then
        return nil
    end

    if config and config.enable_refined_enemy_weights == true then
        local weighted_candidates = {}
        local candidate_order = {}

        for i = 1, #pool do
            local candidate = pool[i]

            if _is_compatible_replacement(core, requested_breed, requested_meta, selected_category, candidate, config) then
                local candidate_meta = core.state.pools.enemies.by_name[candidate]
                local weight = _candidate_archetype_weight(config, candidate_meta)

                if weight > 0 then
                    candidate_order[#candidate_order + 1] = candidate
                    weighted_candidates[candidate] = weight
                end
            end
        end

        local weighted_pick = core.utils.weighted_pick(weighted_candidates, candidate_order, function()
            return core:next_float()
        end)

        if type(weighted_pick) == "string" then
            return weighted_pick
        end
    end

    local count = #pool
    local start_index = core:next_int(1, count)

    for i = 0, count - 1 do
        local index = ((start_index + i - 1) % count) + 1
        local candidate = pool[index]

        if _is_compatible_replacement(core, requested_breed, requested_meta, selected_category, candidate, config) then
            return candidate
        end
    end

    return nil
end

local function _resolve_disabled_requested_replacement(core, requested_breed, requested_meta, request_category, config)
    local enemy_pools = core.state.pools and core.state.pools.enemies

    if not enemy_pools then
        return nil
    end

    local request_pool = enemy_pools[request_category]
    local replacement = _random_compatible_from_pool(core, request_pool, requested_breed, requested_meta, request_category, config)

    if not replacement then
        replacement = _random_compatible_from_pool(core, enemy_pools.all, requested_breed, requested_meta, "disabled_override", config)
    end

    return replacement
end

local function _build_scaled_weights(core, config, source_key)
    local weights = {}
    local categories = config and config.categories or {}
    local configured_weights = config and config.weights or {}
    local _ = source_key

    for i = 1, #CATEGORY_ORDER do
        local category = CATEGORY_ORDER[i]
        local enabled = categories[category] ~= false
        local base_weight = tonumber(configured_weights[category]) or 0

        weights[category] = enabled and math.max(0, base_weight) or 0
    end

    if config and config.enable_difficulty_scaling then
        local rank = core:get_difficulty_rank()
        local scale_table = core.data.difficulty_scaling and core.data.difficulty_scaling[rank]

        if scale_table then
            for i = 1, #CATEGORY_ORDER do
                local category = CATEGORY_ORDER[i]
                local scale = tonumber(scale_table[category]) or 1

                weights[category] = math.max(0, math.floor(weights[category] * scale + 0.5))
            end
        end
    end

    return weights
end

local function _build_weighted_fallback_order(available_weights, selected_category)
    local fallback_order = {}

    for i = 1, #CATEGORY_ORDER do
        local category = CATEGORY_ORDER[i]

        if category ~= selected_category and (available_weights[category] or 0) > 0 then
            fallback_order[#fallback_order + 1] = category
        end
    end

    return fallback_order
end

local function _pick_forced_candidate_from_pool(core, pool, requested_breed, config)
    if type(pool) ~= "table" or #pool == 0 then
        return nil
    end

    if config and config.enable_refined_enemy_weights == true then
        local weighted_candidates = {}
        local candidate_order = {}

        for i = 1, #pool do
            local candidate = pool[i]
            local candidate_meta = core.state.pools.enemies.by_name[candidate]
            local archetype_weight = _candidate_archetype_weight(config, candidate_meta)

            if type(candidate) == "string"
                and archetype_weight > 0
                and core:is_valid_enemy(candidate)
                and not core:is_enemy_blocked_for_randomizer(candidate)
                and not _is_enemy_disabled(config, candidate)
            then
                if core:is_boss_breed(candidate) then
                    if core:can_spawn_random_boss(requested_breed, config) then
                        candidate_order[#candidate_order + 1] = candidate
                        weighted_candidates[candidate] = archetype_weight
                    end
                else
                    candidate_order[#candidate_order + 1] = candidate
                    weighted_candidates[candidate] = archetype_weight
                end
            end
        end

        local weighted_pick = core.utils.weighted_pick(weighted_candidates, candidate_order, function()
            return core:next_float()
        end)

        if type(weighted_pick) == "string" then
            return weighted_pick
        end
    end

    local count = #pool
    local start_index = core:next_int(1, count) or 1

    for i = 0, count - 1 do
        local index = ((start_index + i - 1) % count) + 1
        local candidate = pool[index]

        if type(candidate) == "string"
            and core:is_valid_enemy(candidate)
            and not core:is_enemy_blocked_for_randomizer(candidate)
            and not _is_enemy_disabled(config, candidate)
        then
            if core:is_boss_breed(candidate) then
                if core:can_spawn_random_boss(requested_breed, config) then
                    return candidate
                end
            else
                return candidate
            end
        end
    end

    return nil
end

function EnemyRandomizer.randomize(core, requested_breed, context, config)
    if type(requested_breed) ~= "string" or not core:is_valid_enemy(requested_breed) then
        return requested_breed
    end

    if core:is_enemy_blocked_for_randomizer(requested_breed) then
        return requested_breed
    end

    local enemy_pools = core.state.pools.enemies
    local enemy_meta = enemy_pools.by_name[requested_breed]
    local request_category = _requested_category(core, requested_breed)
    local requested_disabled = _is_enemy_disabled(config, requested_breed)
    local source_key = _resolve_spawn_source(enemy_meta, context)

    if not enemy_meta then
        return requested_breed
    end

    if config.enable_chaos_mode then
        local chaos_enemy = core.chaos_mode.random_enemy(core, requested_breed, enemy_meta, config, context)

        if core:is_valid_enemy(chaos_enemy) and not _is_enemy_disabled(config, chaos_enemy) then
            return chaos_enemy
        end

        if requested_disabled then
            local disabled_override = _resolve_disabled_requested_replacement(core, requested_breed, enemy_meta, request_category, config)

            if core:is_valid_enemy(disabled_override) then
                return disabled_override
            end
        end

        return requested_breed
    end

    if not _source_allows_randomization(core, config, source_key) then
        return requested_breed
    end

    local optional_param_table = context and context.optional_param_table
    local is_grouped_spawn = type(optional_param_table) == "table" and optional_param_table.optional_group_id ~= nil

    if is_grouped_spawn then
        -- Grouped spawns must preserve internal group composition and behavior contracts.
        -- Randomizing individual members can produce mixed patrol state and crash AI nodes
        -- (e.g. bt_renegade_flamer_patrol_action member_patrol nil).
        return requested_breed
    end

    if config.categories[request_category] == false and not requested_disabled then
        return requested_breed
    end

    if requested_disabled and config.categories[request_category] == false then
        local disabled_override = _resolve_disabled_requested_replacement(core, requested_breed, enemy_meta, request_category, config)

        if core:is_valid_enemy(disabled_override) then
            return disabled_override
        end
    end

    local scaled_weights = _build_scaled_weights(core, config, source_key)
    local available_weights = {}

    for i = 1, #CATEGORY_ORDER do
        local category = CATEGORY_ORDER[i]
        local category_pool = enemy_pools[category]

        if category_pool and #category_pool > 0 then
            available_weights[category] = scaled_weights[category] or 0
        else
            available_weights[category] = 0
        end
    end

    local selected_category = core.utils.weighted_pick(available_weights, CATEGORY_ORDER, function()
        return core:next_float()
    end)

    if not selected_category then
        return requested_breed
    end

    local selected_pool = enemy_pools[selected_category]
    local replacement = _random_compatible_from_pool(core, selected_pool, requested_breed, enemy_meta, selected_category, config)

    if not replacement then
        local fallback_order = _build_weighted_fallback_order(available_weights, selected_category)
        local fallback_weights = {}

        for i = 1, #fallback_order do
            local category = fallback_order[i]
            fallback_weights[category] = available_weights[category] or 0
        end

        local fallback_category = core.utils.weighted_pick(fallback_weights, fallback_order, function()
            return core:next_float()
        end)

        if fallback_category then
            replacement = _random_compatible_from_pool(core, enemy_pools[fallback_category], requested_breed, enemy_meta, fallback_category, config)
        end
    end

    if not replacement and requested_disabled then
        replacement = _resolve_disabled_requested_replacement(core, requested_breed, enemy_meta, request_category, config)
    end

    if replacement and core:is_valid_enemy(replacement) then
        return replacement
    end

    return requested_breed
end

function EnemyRandomizer.pick_forced_strict_replacement(core, requested_breed, config, context)
    if type(requested_breed) ~= "string" or not core:is_valid_enemy(requested_breed) then
        return nil
    end

    local enemy_pools = core.state.pools and core.state.pools.enemies

    if not enemy_pools then
        return nil
    end

    local requested_meta = enemy_pools.by_name and enemy_pools.by_name[requested_breed]
    local source_key = _resolve_spawn_source(requested_meta, context)

    if not _source_allows_randomization(core, config, source_key) then
        return nil
    end

    local scaled_weights = _build_scaled_weights(core, config or {}, source_key)
    local available_weights = {}

    for i = 1, #CATEGORY_ORDER do
        local category = CATEGORY_ORDER[i]
        local pool = enemy_pools[category]
        local has_entries = type(pool) == "table" and #pool > 0

        if has_entries then
            available_weights[category] = tonumber(scaled_weights[category]) or 0
        else
            available_weights[category] = 0
        end
    end

    local selected_category = core.utils.weighted_pick(available_weights, CATEGORY_ORDER, function()
        return core:next_float()
    end)

    if selected_category then
        local selected_pool = enemy_pools[selected_category]
        local candidate = _pick_forced_candidate_from_pool(core, selected_pool, requested_breed, config)

        if candidate then
            return candidate
        end
    end

    local fallback_order = _build_weighted_fallback_order(available_weights, selected_category)

    for i = 1, #fallback_order do
        local category = fallback_order[i]
        local pool = enemy_pools[category]
        local candidate = _pick_forced_candidate_from_pool(core, pool, requested_breed, config)

        if candidate then
            return candidate
        end
    end

    return nil
end

return EnemyRandomizer
