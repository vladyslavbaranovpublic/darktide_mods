--[[
    File: spawn_hooks.lua
    Description: Hook registration for mission start, enemy spawns, and item spawns.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local SpawnHooks = {}

local function _fallback_hud_icon(slot_name, is_weapon)
    if slot_name == "slot_pocketable_small" then
        return "content/ui/materials/icons/pocketables/hud/small/party_syringe_power"
    end

    if slot_name == "slot_pocketable" then
        return "content/ui/materials/icons/pocketables/hud/small/party_ammo_crate"
    end

    if is_weapon then
        return "content/ui/materials/icons/weapons/hud/autogun_01"
    end

    return "content/ui/materials/icons/pocketables/hud/small/party_non_grenade"
end

local function _sanitize_hud_icon(icon, slot_name, is_weapon)
    if type(icon) == "string" and icon ~= "" then
        return icon
    end

    return _fallback_hud_icon(slot_name, is_weapon)
end

local function _offset_enemy_spawn_position(core, position)
    if not position or not Vector3 then
        return position
    end

    local x = (core:next_float() * 2 - 1) * 1.2
    local y = (core:next_float() * 2 - 1) * 1.2
    local offset = Vector3(x, y, 0)

    return position + offset
end

local function _try_spawn_forced_boss_replacement(func, spawn_manager, core, config, blocked_breed, position, rotation, side_id, optional_param_table)
    if not core:is_boss_only_mode(config) then
        return
    end

    if core:is_boss_breed(blocked_breed) then
        return
    end

    if core:is_enemy_blocked_for_randomizer(blocked_breed) then
        return
    end

    local is_grouped_spawn = type(optional_param_table) == "table" and optional_param_table.optional_group_id ~= nil

    if is_grouped_spawn and config.strict_enemy_weight_enforcement ~= true then
        return
    end

    if not position then
        return
    end

    if not core:can_spawn_random_boss(blocked_breed, config) then
        return
    end

    local boss_breed
    local pick_forced = core.enemy_randomizer and core.enemy_randomizer.pick_forced_strict_replacement

    if type(pick_forced) == "function" then
        local forced_breed = pick_forced(core, blocked_breed, config, {
            optional_param_table = optional_param_table,
        })

        if core:is_boss_breed(forced_breed) then
            boss_breed = forced_breed
        end
    end

    if not boss_breed and core.boss_randomizer then
        local attempts = 8

        for _ = 1, attempts do
            local candidate = core.boss_randomizer.random_boss(core)
            local disabled = config and config.disabled_enemy_breeds and config.disabled_enemy_breeds[candidate] == true

            if core:is_valid_enemy(candidate) and not core:is_enemy_blocked_for_randomizer(candidate) and not disabled then
                boss_breed = candidate
                break
            end
        end
    end

    if not core:is_valid_enemy(boss_breed) or core:is_enemy_blocked_for_randomizer(boss_breed) then
        return
    end

    if config and config.disabled_enemy_breeds and config.disabled_enemy_breeds[boss_breed] == true then
        return
    end

    local boss_position = _offset_enemy_spawn_position(core, position)
    local spawn_params = optional_param_table

    if is_grouped_spawn then
        -- Group metadata is tied to specific member behavior contracts. Spawn boss replacements
        -- as standalone units to avoid inheriting incompatible group/patrol state.
        spawn_params = nil
    end

    local boss_unit = func(spawn_manager, boss_breed, boss_position, rotation, side_id, spawn_params)

    core:on_enemy_spawned(boss_unit, blocked_breed, boss_breed, {
        is_extra_spawn = false,
        is_forced_boss_replacement = true,
    })
end

local function _try_spawn_forced_weighted_replacement(func, spawn_manager, core, config, blocked_breed, position, rotation, side_id, optional_param_table)
    if not config or config.strict_enemy_weight_enforcement ~= true then
        return
    end

    if not core.enemy_randomizer or type(core.enemy_randomizer.pick_forced_strict_replacement) ~= "function" then
        return
    end

    if core:is_boss_only_mode(config) then
        return
    end

    if not position then
        return
    end

    local replacement_breed = core.enemy_randomizer.pick_forced_strict_replacement(core, blocked_breed, config, {
        optional_param_table = optional_param_table,
    })

    if not core:is_valid_enemy(replacement_breed) then
        return
    end

    if core:should_despawn_enemy_for_weights(config, replacement_breed, nil) then
        return
    end

    local replacement_position = _offset_enemy_spawn_position(core, position)
    local replacement_unit = func(spawn_manager, replacement_breed, replacement_position, rotation, side_id, nil)

    core:on_enemy_spawned(replacement_unit, blocked_breed, replacement_breed, {
        is_extra_spawn = false,
        is_forced_weight_replacement = true,
    })
end

local function _scale_pickup_pool_counts(pickup_pool, multiplier)
    if type(pickup_pool) ~= "table" then
        return pickup_pool
    end

    local scaled_pool = {}

    for pickup_type, entries in pairs(pickup_pool) do
        if type(entries) == "table" then
            local scaled_entries = {}

            for pickup_name, amount in pairs(entries) do
                local numeric_amount = tonumber(amount) or 0

                if numeric_amount > 0 then
                    scaled_entries[pickup_name] = math.max(1, math.floor(numeric_amount * multiplier + 0.5))
                else
                    scaled_entries[pickup_name] = amount
                end
            end

            scaled_pool[pickup_type] = scaled_entries
        else
            scaled_pool[pickup_type] = entries
        end
    end

    return scaled_pool
end

local function _collect_available_spawners(pickup_spawners, distribution_type)
    local available_spawners = {}

    if type(pickup_spawners) ~= "table" then
        return available_spawners
    end

    for i = 1, #pickup_spawners do
        local spawner_extension = pickup_spawners[i]

        if spawner_extension and spawner_extension.register_spawn_locations then
            spawner_extension:register_spawn_locations(available_spawners, distribution_type)
        end
    end

    return available_spawners
end

local function _try_spawn_filler_item(core, config, spawner_entry)
    if type(spawner_entry) ~= "table" then
        return false
    end

    local spawner_extension = spawner_entry.extension
    local component_index = spawner_entry.index

    if not spawner_extension or not component_index then
        return false
    end

    if not spawner_extension.can_spawn_pickup or not spawner_extension.spawn_specific_item then
        return false
    end

    local include_materials = not config.disable_material_spawns
    local weighted_attempts = 8

    for _ = 1, weighted_attempts do
        local weighted_pickup = core.item_randomizer.pick_weighted_item(core, config, include_materials)

        if core:is_valid_item(weighted_pickup) and spawner_extension:can_spawn_pickup(component_index, weighted_pickup) then
            spawner_extension:spawn_specific_item(component_index, weighted_pickup, true)

            return true
        end
    end

    local item_pools = core.state.pools and core.state.pools.items
    local fallback_pool

    if include_materials then
        fallback_pool = item_pools and item_pools.safe or {}
    else
        fallback_pool = item_pools and item_pools.safe_non_materials or {}
    end

    local pool_size = #fallback_pool

    if pool_size <= 0 then
        return false
    end

    local start_index = core:next_int(1, pool_size) or 1

    for offset = 0, pool_size - 1 do
        local index = ((start_index + offset - 1) % pool_size) + 1
        local pickup_name = fallback_pool[index]

        if core:is_valid_item(pickup_name) and spawner_extension:can_spawn_pickup(component_index, pickup_name) then
            spawner_extension:spawn_specific_item(component_index, pickup_name, true)

            return true
        end
    end

    return false
end

function SpawnHooks.register(mod, core)
    if mod._randomizer_hooks_registered then
        return
    end

    mod._randomizer_hooks_registered = true

    mod:hook("MinionSpawnManager", "spawn_minion", function(func, self, breed_name, position, rotation, side_id, optional_param_table)
        if not core or not mod:is_enabled() then
            return func(self, breed_name, position, rotation, side_id, optional_param_table)
        end

        local can_randomize, config = core:should_randomize()

        if not can_randomize then
            return func(self, breed_name, position, rotation, side_id, optional_param_table)
        end

        if config.use_vanilla_enemy_logic == true then
            return func(self, breed_name, position, rotation, side_id, optional_param_table)
        end

        local enemy_context = {
            side_id = side_id,
            optional_param_table = optional_param_table,
        }
        local replacement_breed = core.enemy_randomizer.randomize(core, breed_name, enemy_context, config)

        local unit = func(self, replacement_breed, position, rotation, side_id, optional_param_table)

        core:on_enemy_spawned(unit, breed_name, replacement_breed, {
            is_extra_spawn = false,
        })

        if unit and core:should_despawn_enemy_for_weights(config, replacement_breed, optional_param_table) then
            core:queue_enemy_despawn(unit)
            _try_spawn_forced_boss_replacement(func, self, core, config, replacement_breed, position, rotation, side_id, optional_param_table)
            _try_spawn_forced_weighted_replacement(func, self, core, config, replacement_breed, position, rotation, side_id, optional_param_table)
        end

        if unit then
            core:enforce_alive_enemy_cap(config, self, side_id, unit)
        end

        local extra_spawns_requested = core:get_extra_enemy_spawn_count(config)

        if extra_spawns_requested <= 0 then
            return unit
        end

        local extra_context = {
            requested_breed = breed_name,
            optional_param_table = optional_param_table,
        }

        for _ = 1, extra_spawns_requested do
            if not core:can_spawn_extra_enemy(config, extra_context) then
                break
            end

            local extra_breed = core.enemy_randomizer.randomize(core, breed_name, extra_context, config)
            local extra_position = _offset_enemy_spawn_position(core, position)

            local extra_unit = func(self, extra_breed, extra_position, rotation, side_id, optional_param_table)

            core:on_enemy_spawned(extra_unit, breed_name, extra_breed, {
                is_extra_spawn = true,
            })

            if extra_unit and core:should_despawn_enemy_for_weights(config, extra_breed, optional_param_table) then
                core:queue_enemy_despawn(extra_unit)
                _try_spawn_forced_boss_replacement(func, self, core, config, extra_breed, extra_position, rotation, side_id, optional_param_table)
                _try_spawn_forced_weighted_replacement(func, self, core, config, extra_breed, extra_position, rotation, side_id, optional_param_table)
            end

            if extra_unit then
                core:enforce_alive_enemy_cap(config, self, side_id, extra_unit)
            end
        end

        return unit
    end)

    local MONSTER_PACING_TIMER_TYPES = {
        "monsters",
        "boss_patrols",
    }

    local function _sanitize_monster_pacing_tables(monster_pacing)
        if type(monster_pacing) ~= "table" then
            return
        end

        -- Default pacing expects these scheduling tables to always exist.
        if type(monster_pacing._monsters) ~= "table" then
            monster_pacing._monsters = {}
        end

        if type(monster_pacing._alive_monsters) ~= "table" then
            monster_pacing._alive_monsters = {}
        end

        if monster_pacing._boss_patrols ~= nil and type(monster_pacing._boss_patrols) ~= "table" then
            monster_pacing._boss_patrols = {}
        end

        monster_pacing._currently_spawned_by_timer = type(monster_pacing._currently_spawned_by_timer) == "table" and monster_pacing._currently_spawned_by_timer or {}
        monster_pacing._amount_allowed_by_type = type(monster_pacing._amount_allowed_by_type) == "table" and monster_pacing._amount_allowed_by_type or {}
        local spawned_by_timer = monster_pacing._currently_spawned_by_timer
        local amount_allowed = monster_pacing._amount_allowed_by_type

        for i = 1, #MONSTER_PACING_TIMER_TYPES do
            local name = MONSTER_PACING_TIMER_TYPES[i]

            if type(spawned_by_timer[name]) ~= "table" then
                spawned_by_timer[name] = {}
            end

            if type(amount_allowed[name]) ~= "number" then
                amount_allowed[name] = 0
            end
        end

        if type(amount_allowed.total) ~= "number" then
            amount_allowed.total = 0
        end

        local template = monster_pacing._template
        local pacing_manager = Managers and Managers.state and Managers.state.pacing

        if type(template) ~= "table" or not pacing_manager or not pacing_manager.get_table_entry_by_heat_stage then
            return
        end

        local max_allowed_by_current_heat_level = pacing_manager:get_table_entry_by_heat_stage(template.max_allowed_by_heat)

        if type(max_allowed_by_current_heat_level) ~= "table" then
            return
        end

        for name in pairs(max_allowed_by_current_heat_level) do
            if type(spawned_by_timer[name]) ~= "table" then
                spawned_by_timer[name] = {}
            end

            if type(amount_allowed[name]) ~= "number" then
                amount_allowed[name] = 0
            end
        end
    end

    local function _monster_allowance_fallback(monster_pacing)
        local template = monster_pacing and monster_pacing._template
        local pacing_manager = Managers and Managers.state and Managers.state.pacing

        if type(template) ~= "table" or not pacing_manager or not pacing_manager.get_table_entry_by_heat_stage then
            return false
        end

        local max_allowed_by_current_heat_level = pacing_manager:get_table_entry_by_heat_stage(template.max_allowed_by_heat)

        if type(max_allowed_by_current_heat_level) ~= "table" then
            return false
        end

        _sanitize_monster_pacing_tables(monster_pacing)

        local total_allowed = 0
        local currently_spawned = monster_pacing._currently_spawned_by_timer
        local amount_allowed = monster_pacing._amount_allowed_by_type

        for name, template_amount in pairs(max_allowed_by_current_heat_level) do
            local spawned = currently_spawned[name]
            local amount = (tonumber(template_amount) or 0) - (type(spawned) == "table" and #spawned or 0)

            amount_allowed[name] = amount
            total_allowed = total_allowed + amount
        end

        amount_allowed.total = total_allowed

        return total_allowed > 0
    end

    mod:hook("MonsterPacing", "_update_allowance", function(func, self, dt, t, side_id, target_side_id)
        _sanitize_monster_pacing_tables(self)

        local ok, result = pcall(func, self, dt, t, side_id, target_side_id)

        if ok then
            return result
        end

        _sanitize_monster_pacing_tables(self)

        return _monster_allowance_fallback(self)
    end)

    mod:hook("MonsterPacing", "update", function(func, self, dt, t, side_id, target_side_id)
        _sanitize_monster_pacing_tables(self)

        local ok, result = pcall(func, self, dt, t, side_id, target_side_id)

        if ok then
            return result
        end

        _sanitize_monster_pacing_tables(self)

        local retry_ok, retry_result = pcall(func, self, dt, t, side_id, target_side_id)

        if retry_ok then
            return retry_result
        end

        -- Avoid hard-crashing the whole session on a pacing-table desync frame.
        return nil
    end)

    mod:hook_safe("MinionSpawnManager", "update", function(self, dt, t)
        if not core or not mod:is_enabled() then
            return
        end

        local can_randomize, config = core:should_randomize()

        if can_randomize and config.use_vanilla_enemy_logic ~= true then
            core:process_pending_enemy_despawns(self)
        end
    end)

    mod:hook_safe("MinionSpawnManager", "despawn_minion", function(self, unit)
        if core and mod:is_enabled() then
            core:on_enemy_despawned(unit)
        end
    end)

    mod:hook("PickupSystem", "spawn_spread_pickups", function(func, self, pickup_spawners, distribution_type, pickup_pool, seed)
        if not core or not mod:is_enabled() then
            return func(self, pickup_spawners, distribution_type, pickup_pool, seed)
        end

        local can_randomize, config = core:should_randomize()

        if not can_randomize then
            return func(self, pickup_spawners, distribution_type, pickup_pool, seed)
        end

        if config.use_vanilla_item_logic == true then
            return func(self, pickup_spawners, distribution_type, pickup_pool, seed)
        end

        local items_enabled = config.categories and config.categories.items ~= false
        local item_weight = tonumber(config.weights and config.weights.items) or 0

        if not items_enabled or item_weight <= 0 then
            return func(self, pickup_spawners, distribution_type, pickup_pool, seed)
        end

        local multiplier = core.utils.clamp(tonumber(config.item_spawn_rate_multiplier) or 1.0, 1.0, 10.0)

        if multiplier <= 1.0 then
            return func(self, pickup_spawners, distribution_type, pickup_pool, seed)
        end

        -- Keep side-mission objective logic stable (grimoires/tomes/etc).
        if distribution_type == "side_mission" then
            return func(self, pickup_spawners, distribution_type, pickup_pool, seed)
        end

        local scaled_pickup_pool = _scale_pickup_pool_counts(pickup_pool, multiplier)
        local result_seed = func(self, pickup_spawners, distribution_type, scaled_pickup_pool, seed)

        -- Darktide can still leave valid item locations empty when pool entries do not
        -- align with each location's pickup allow-list. Fill a multiplier-scaled portion
        -- of remaining non-chest locations using per-spawner compatible pickups.
        local extra_fill_probability = core.utils.clamp((multiplier - 1.0) / 9.0, 0.0, 1.0)

        if extra_fill_probability <= 0 then
            return result_seed
        end

        local remaining_spawners = _collect_available_spawners(pickup_spawners, distribution_type)
        local num_remaining_spawners = #remaining_spawners

        for i = 1, num_remaining_spawners do
            local spawner_entry = remaining_spawners[i]

            if spawner_entry and not spawner_entry.chest and core:next_float() <= extra_fill_probability then
                _try_spawn_filler_item(core, config, spawner_entry)
            end
        end

        return result_seed
    end)

    mod:hook("PickupSystem", "spawn_pickup", function(func, self, pickup_name, position, rotation, optional_pickup_spawner, optional_placed_on_unit, optional_spawn_interaction_cooldown, optional_origin_player, skip_group)
        if not core or not mod:is_enabled() then
            return func(self, pickup_name, position, rotation, optional_pickup_spawner, optional_placed_on_unit, optional_spawn_interaction_cooldown, optional_origin_player, skip_group)
        end

        if optional_origin_player ~= nil then
            -- Player-origin pickup spawns (drops/ability-driven flows) should stay vanilla.
            return func(self, pickup_name, position, rotation, optional_pickup_spawner, optional_placed_on_unit, optional_spawn_interaction_cooldown, optional_origin_player, skip_group)
        end

        local can_randomize, config = core:should_randomize()

        if not can_randomize then
            return func(self, pickup_name, position, rotation, optional_pickup_spawner, optional_placed_on_unit, optional_spawn_interaction_cooldown, optional_origin_player, skip_group)
        end

        if config.use_vanilla_item_logic == true then
            return func(self, pickup_name, position, rotation, optional_pickup_spawner, optional_placed_on_unit, optional_spawn_interaction_cooldown, optional_origin_player, skip_group)
        end

        local replacement_pickup = core.item_randomizer.randomize(core, pickup_name, {
            optional_pickup_spawner = optional_pickup_spawner,
            optional_placed_on_unit = optional_placed_on_unit,
            skip_group = skip_group,
        }, config)

        local pickup_unit, pickup_unit_go_id = func(
            self,
            replacement_pickup,
            position,
            rotation,
            optional_pickup_spawner,
            optional_placed_on_unit,
            optional_spawn_interaction_cooldown,
            optional_origin_player,
            skip_group
        )

        if config.spawn_extra_random_items and core:should_spawn_extra_item(config, pickup_name) then
            local extra_pickup = core.item_randomizer.pick_weighted_item(core, config, not config.disable_material_spawns)

            if core:is_valid_item(extra_pickup) then
                func(
                    self,
                    extra_pickup,
                    position,
                    rotation,
                    nil,
                    nil,
                    optional_spawn_interaction_cooldown,
                    optional_origin_player,
                    nil
                )

                core:on_extra_item_spawned()
            end
        end

        return pickup_unit, pickup_unit_go_id
    end)

    -- Safety: some pocketable item definitions can resolve to empty icon strings, which
    -- crash retained UI rendering with "Error loading material '0'".
    mod:hook("HudElementPlayerWeapon", "set_icon", function(func, self, icon, is_weapon)
        local slot_name = self and self._slot_name
        local safe_icon = _sanitize_hud_icon(icon, slot_name, is_weapon)

        return func(self, safe_icon, is_weapon)
    end)

    mod:hook_safe("StateGameplay", "on_enter", function(self, parent, params, creation_context)
        if core and mod:is_enabled() then
            core:on_mission_start(params)
        end
    end)
end

return SpawnHooks
