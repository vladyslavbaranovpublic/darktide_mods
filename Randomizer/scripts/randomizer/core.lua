--[[
    File: core.lua
    Description: Core runtime state manager for seed lifecycle and randomization dispatch.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Core = {}
Core.__index = Core

local ENEMY_WEIGHT_CATEGORIES = {
    "regular",
    "elites",
    "specials",
    "bosses",
    "patrols",
    "hordes",
}
local ACTION_KILL_ALL_ENEMIES_SETTING = "action_kill_all_enemies"

local function _table_size(t)
    local count = 0

    if type(t) ~= "table" then
        return count
    end

    for _ in pairs(t) do
        count = count + 1
    end

    return count
end

function Core.new(deps)
    local self = setmetatable({}, Core)

    self.mod = deps.mod
    self.data = deps.data or {}
    self.utils = deps.utils
    self.seed = deps.seed
    self.settings = deps.settings
    self.enemy_randomizer = deps.enemy_randomizer
    self.item_randomizer = deps.item_randomizer
    self.patrol_randomizer = deps.patrol_randomizer
    self.boss_randomizer = deps.boss_randomizer
    self.chaos_mode = deps.chaos_mode

    self.state = {
        active_seed = 1,
        rng_state = 1,
        last_seed_reason = "init",
        mission_count = 0,
        boss_runtime = {
            randomized_boss_unit_lookup = {},
            randomized_boss_alive = 0,
            last_randomized_boss_spawn_t = -math.huge,
            mission_start_t = 0,
        },
        enemy_runtime = {
            extra_spawned_count = 0,
            extra_alive = 0,
            extra_unit_lookup = {},
            pending_despawn_units = {},
        },
        item_runtime = {
            extra_spawned_count = 0,
            last_extra_spawn_t = -math.huge,
        },
        session_runtime = {
            checked = false,
            value = false,
            next_check_t = 0,
        },
        config_cache = nil,
        pools = {
            enemies = {
                all = {},
                by_name = {},
            },
            items = {
                all = {},
                safe = {},
                safe_non_materials = {},
                by_name = {},
            },
        },
    }

    self:_refresh_pools()
    self:_refresh_config()
    self:refresh_seed("mod_init", true)
    self:_print_pool_summary()

    return self
end

function Core:_log_error(message)
    if self.mod and self.mod.echo then
        self.mod:echo(string.format("[Randomizer][Error] %s", tostring(message)))
    end
end

function Core:_log_debug(message, config)
    local active_config = config or self.state.config_cache

    if active_config and active_config.debug_mode == true and self.mod and self.mod.echo then
        self.mod:echo(tostring(message))
    end
end

function Core:_is_local_controlled_session_cached()
    local runtime = self.state.session_runtime

    if not runtime then
        return self.utils.is_local_controlled_session()
    end

    local now = self.utils.get_gameplay_time() or 0

    if runtime.checked and now < (runtime.next_check_t or 0) then
        return runtime.value == true
    end

    local value = self.utils.is_local_controlled_session()

    runtime.checked = true
    runtime.value = value == true
    runtime.next_check_t = now + 1

    return runtime.value
end

function Core:_refresh_pools()
    if type(self.data.build_spawn_pools) == "function" then
        local ok, pools_or_error = pcall(self.data.build_spawn_pools)

        if ok and type(pools_or_error) == "table" then
            self.state.pools = pools_or_error

            return
        end

        self:_log_error(string.format("Failed building spawn pools: %s", tostring(pools_or_error)))
    end
end

function Core:_refresh_config()
    local previous = self.state.config_cache
    local ok, config_or_error = pcall(self.settings.get_config, self.mod, self.data, self.utils)

    if ok and type(config_or_error) == "table" then
        self.state.config_cache = config_or_error

        return config_or_error
    end

    if previous then
        self:_log_error(string.format("Failed reading settings, using previous config: %s", tostring(config_or_error)))
        self.state.config_cache = previous

        return previous
    end

    local category_order = self.settings and self.settings.category_order or {}
    local default_weights = self.data.default_weights or {}
    local item_class_order = self.data.item_class_order or {}
    local item_class_defaults = self.data.item_class_default_weights or {}
    local item_specific_defaults = self.data.item_specific_default_weights or {}
    local source_weight_order = self.data.source_weight_order or {}
    local source_default_weights = self.data.source_default_weights or {}
    local archetype_weight_order = self.data.enemy_archetype_order or {}
    local archetype_default_weights = self.data.enemy_archetype_default_weights or {}
    local fallback_categories = {}
    local fallback_weights = {}
    local fallback_item_weights = {}
    local fallback_item_specific_weights = {}
    local fallback_source_weights = {}
    local fallback_archetype_weights = {}

    for i = 1, #category_order do
        local category = category_order[i]

        if type(category) == "string" then
            fallback_categories[category] = true
            fallback_weights[category] = self.utils.clamp(tonumber(default_weights[category]) or 100, 0, 100)
        end
    end

    for i = 1, #item_class_order do
        local item_class = item_class_order[i]

        if type(item_class) == "string" then
            fallback_item_weights[item_class] = self.utils.clamp(tonumber(item_class_defaults[item_class]) or 0, 0, 100)
        end
    end

    for item_key, default_weight in pairs(item_specific_defaults) do
        if type(item_key) == "string" then
            fallback_item_specific_weights[item_key] = self.utils.clamp(tonumber(default_weight) or 0, 0, 100)
        end
    end

    for i = 1, #source_weight_order do
        local source_name = source_weight_order[i]

        if type(source_name) == "string" then
            fallback_source_weights[source_name] = self.utils.clamp(tonumber(source_default_weights[source_name]) or 100, 0, 100)
        end
    end

    for i = 1, #archetype_weight_order do
        local archetype_name = archetype_weight_order[i]

        if type(archetype_name) == "string" then
            fallback_archetype_weights[archetype_name] = self.utils.clamp(tonumber(archetype_default_weights[archetype_name]) or 100, 0, 100)
        end
    end

    local fallback = {
        enable_randomizer = true,
        debug_mode = false,
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
        categories = fallback_categories,
        weights = fallback_weights,
        item_weights = fallback_item_weights,
        item_specific_weights = fallback_item_specific_weights,
        source_weights = fallback_source_weights,
        archetype_weights = fallback_archetype_weights,
        disabled_enemy_breeds = {},
    }

    self:_log_error(string.format("Failed reading settings, using fallback config: %s", tostring(config_or_error)))
    self.state.config_cache = fallback

    return fallback
end

function Core:_print_pool_summary()
    local enemy_count = #(self.state.pools.enemies and self.state.pools.enemies.all or {})
    local item_count = #(self.state.pools.items and self.state.pools.items.all or {})

    self:_log_debug(string.format("[Randomizer] Loaded %d enemy breeds and %d pickup types.", enemy_count, item_count))
end

function Core:get_config()
    if not self.state.config_cache then
        return self:_refresh_config()
    end

    return self.state.config_cache
end

function Core:refresh_seed(reason, force_new)
    local config = self:get_config()

    return self.seed.resolve_seed(self.mod, config, self.state, reason, force_new == true)
end

function Core:on_enabled()
    self:_refresh_pools()
    self.state.session_runtime = {
        checked = false,
        value = false,
        next_check_t = 0,
    }
    self:_refresh_config()
    self:refresh_seed("mod_enabled", false)
end

function Core:on_disabled()
    -- Hooks remain registered, but gated by mod enabled state and settings.
    local enemy_runtime = self.state.enemy_runtime

    if enemy_runtime then
        enemy_runtime.pending_despawn_units = {}
    end
end

function Core:on_setting_changed(setting_id)
    self:_refresh_config()
    self:_handle_action_setting(setting_id)

    if self.settings.is_seed_related_setting(setting_id) then
        self:refresh_seed("setting_changed", true)
    end
end

function Core:_handle_action_setting(setting_id)
    if setting_id ~= ACTION_KILL_ALL_ENEMIES_SETTING then
        return
    end

    if not self.mod or type(self.mod.get) ~= "function" or type(self.mod.set) ~= "function" then
        return
    end

    local should_execute = self.mod:get(ACTION_KILL_ALL_ENEMIES_SETTING) == true

    if not should_execute then
        return
    end

    if not self:_is_local_controlled_session_cached() then
        self:_log_error("Kill All Enemies is only available in local-controlled sessions.")
        self.mod:set(ACTION_KILL_ALL_ENEMIES_SETTING, false, true)

        return
    end

    local despawned = self:kill_all_enemies()
    local config = self:get_config()

    self:_log_debug(string.format("[Randomizer] Kill-all action executed. Despawned %d enemies.", despawned), config)
    self.mod:set(ACTION_KILL_ALL_ENEMIES_SETTING, false, true)
end

function Core:kill_all_enemies()
    if not self:_is_local_controlled_session_cached() then
        return 0
    end

    local minion_spawn_manager = Managers and Managers.state and Managers.state.minion_spawn

    if not minion_spawn_manager then
        return 0
    end

    local despawned = 0
    local used_bulk_despawn = false

    if type(minion_spawn_manager.despawn_all_minions) == "function" then
        local count_before = type(minion_spawn_manager.num_spawned_minions) == "function"
            and tonumber(minion_spawn_manager:num_spawned_minions())
            or nil
        local ok = pcall(minion_spawn_manager.despawn_all_minions, minion_spawn_manager)

        if ok then
            used_bulk_despawn = true
            despawned = math.max(0, math.floor(count_before or 0))
        end
    end

    if not used_bulk_despawn and type(minion_spawn_manager.despawn_minion) == "function" then
        local lookup = minion_spawn_manager._spawned_minions_index_lookup
        local units = {}

        if type(lookup) == "table" then
            for unit in pairs(lookup) do
                units[#units + 1] = unit
            end
        end

        for i = 1, #units do
            local unit = units[i]
            local is_alive = true

            if type(Alive) == "function" then
                is_alive = Alive(unit) == true
            end

            if unit and is_alive then
                local ok = pcall(minion_spawn_manager.despawn_minion, minion_spawn_manager, unit)

                if ok then
                    despawned = despawned + 1
                end
            end
        end
    end

    local boss_runtime = self.state.boss_runtime

    if boss_runtime then
        boss_runtime.randomized_boss_unit_lookup = {}
        boss_runtime.randomized_boss_alive = 0
        boss_runtime.last_randomized_boss_spawn_t = -math.huge
    end

    local enemy_runtime = self.state.enemy_runtime

    if enemy_runtime then
        enemy_runtime.pending_despawn_units = {}
        enemy_runtime.extra_alive = 0
        enemy_runtime.extra_unit_lookup = {}
    end

    return despawned
end

function Core:on_mission_start(params)
    self.state.mission_count = self.state.mission_count + 1

    self:_refresh_pools()

    self.state.boss_runtime = {
        randomized_boss_unit_lookup = {},
        randomized_boss_alive = 0,
        last_randomized_boss_spawn_t = -math.huge,
        mission_start_t = self.utils.get_gameplay_time() or 0,
    }
    self.state.enemy_runtime = {
        extra_spawned_count = 0,
        extra_alive = 0,
        extra_unit_lookup = {},
        pending_despawn_units = {},
    }
    self.state.item_runtime = {
        extra_spawned_count = 0,
        last_extra_spawn_t = -math.huge,
    }
    self.state.session_runtime = {
        checked = false,
        value = false,
        next_check_t = 0,
    }

    local config = self:_refresh_config()

    if config.random_every_mission then
        self:refresh_seed("mission_start", true)
    elseif self.state.active_seed and self.state.active_seed > 0 then
        self.seed.reset_rng(self.state)

        self:_log_debug(string.format("[Randomizer] Mission %d using seed %d.", self.state.mission_count, self.state.active_seed), config)
    else
        self:refresh_seed("mission_start", false)
    end

    if params and params.mission_name then
        self:_log_debug(string.format("[Randomizer] Mission detected: %s", tostring(params.mission_name)), config)
    end
end

function Core:should_randomize()
    if not self.mod:is_enabled() then
        return false, nil
    end

    local config = self:get_config()

    if not config.enable_randomizer then
        return false, config
    end

    if not self:_is_local_controlled_session_cached() then
        return false, config
    end

    return true, config
end

function Core:randomize_enemy(requested_breed, context)
    local can_randomize, config = self:should_randomize()

    if not can_randomize then
        return requested_breed
    end

    return self.enemy_randomizer.randomize(self, requested_breed, context, config)
end

function Core:randomize_item(requested_pickup, context)
    local can_randomize, config = self:should_randomize()

    if not can_randomize then
        return requested_pickup
    end

    return self.item_randomizer.randomize(self, requested_pickup, context, config)
end

function Core:get_active_seed()
    return self.state.active_seed
end

function Core:is_boss_breed(breed_name)
    local enemies = self.state.pools and self.state.pools.enemies
    local enemy_meta = enemies and enemies.by_name and enemies.by_name[breed_name]

    return enemy_meta and enemy_meta.is_boss == true or false
end

function Core:can_spawn_random_boss(requested_breed, config)
    if self:is_boss_breed(requested_breed) then
        return true
    end

    local safety = self.data.safety or {}
    local runtime = self.state.boss_runtime

    if not runtime then
        return true
    end

    local strict_boss_only_mode = config
        and config.strict_enemy_weight_enforcement == true
        and self:is_boss_only_mode(config)
    local remove_cap = config and config.remove_boss_alive_limit == true

    if strict_boss_only_mode then
        -- Always keep a hard safety ceiling for strict boss-only mode.
        local hard_cap = math.max(1, math.floor(tonumber(safety.max_randomized_bosses_alive_hard_cap) or 12))

        if runtime.randomized_boss_alive >= hard_cap then
            return false
        end
    end

    if not remove_cap then
        local max_alive = tonumber(safety.max_randomized_bosses_alive) or 1

        if runtime.randomized_boss_alive >= math.max(0, math.floor(max_alive)) then
            return false
        end
    end

    local now = self.utils.get_gameplay_time()

    if now then
        local warmup_seconds = tonumber(safety.boss_warmup_seconds) or 0
        local cooldown_seconds = tonumber(safety.boss_min_seconds_between_random_spawns) or 0
        local mission_elapsed = now - (runtime.mission_start_t or 0)
        local since_last_random_boss = now - (runtime.last_randomized_boss_spawn_t or -math.huge)

        if mission_elapsed < math.max(0, warmup_seconds) then
            return false
        end

        if since_last_random_boss < math.max(0, cooldown_seconds) then
            return false
        end
    end

    return true
end

function Core:can_spawn_extra_enemy(config, context)
    if not config then
        return false
    end

    local multiplier = self.utils.clamp(tonumber(config.enemy_spawn_rate_multiplier) or 1.0, 1.0, 5.0)

    if multiplier <= 1.0 then
        return false
    end

    local runtime = self.state.enemy_runtime

    if not runtime then
        return false
    end

    local safety = self.data.safety or {}
    local max_alive = math.max(0, math.floor(tonumber(safety.max_extra_enemies_alive) or 80))
    local max_per_mission = math.max(0, math.floor(tonumber(safety.max_extra_enemies_per_mission) or 2000))

    if runtime.extra_alive >= max_alive then
        return false
    end

    if max_per_mission > 0 and runtime.extra_spawned_count >= max_per_mission then
        return false
    end

    local optional_param_table = context and context.optional_param_table
    local is_grouped_spawn = type(optional_param_table) == "table" and optional_param_table.optional_group_id ~= nil

    if is_grouped_spawn then
        -- Never inject extra units into a game-managed group; this can break patrol/group AI contracts.
        return false
    end

    return true
end

function Core:enforce_alive_enemy_cap(config, spawn_manager, side_id, preferred_unit)
    if not config then
        return 0
    end

    local cap = math.max(0, math.floor(tonumber(config.max_alive_enemies_cap) or 0))

    if cap <= 0 then
        return 0
    end

    if tonumber(side_id) ~= 2 then
        return 0
    end

    local manager = spawn_manager or Managers and Managers.state and Managers.state.minion_spawn

    if not manager then
        return 0
    end

    local count = nil

    if type(manager.num_spawned_minions) == "function" then
        count = tonumber(manager:num_spawned_minions())
    end

    if not count and type(manager._num_spawned_minions) == "number" then
        count = manager._num_spawned_minions
    end

    if not count then
        return 0
    end

    local overflow = math.max(0, math.floor(count - cap))

    if overflow <= 0 then
        return 0
    end

    local queued = 0
    local pending = self.state.enemy_runtime and self.state.enemy_runtime.pending_despawn_units or nil

    local function _queue_if_valid(unit)
        if not unit or overflow <= 0 then
            return
        end

        local is_alive = true

        if type(Alive) == "function" then
            is_alive = Alive(unit) == true
        end

        if not is_alive then
            return
        end

        if type(pending) == "table" and pending[unit] ~= nil then
            return
        end

        self:queue_enemy_despawn(unit)
        overflow = overflow - 1
        queued = queued + 1
    end

    _queue_if_valid(preferred_unit)

    if overflow > 0 then
        local spawned_minions = type(manager.spawned_minions) == "function" and manager:spawned_minions() or manager._spawned_minions

        if type(spawned_minions) == "table" then
            for i = 1, #spawned_minions do
                _queue_if_valid(spawned_minions[i])

                if overflow <= 0 then
                    break
                end
            end
        end
    end

    if queued > 0 then
        self:_log_debug(string.format("[Randomizer] Alive enemy cap enforced: cap=%d queued_despawns=%d", cap, queued), config)
    end

    return queued
end

function Core:get_enemy_category(breed_name)
    local enemies = self.state.pools and self.state.pools.enemies
    local enemy_meta = enemies and enemies.by_name and enemies.by_name[breed_name]

    if not enemy_meta then
        return nil
    end

    if enemy_meta.is_boss == true then
        return "bosses"
    end

    if enemy_meta.is_special == true then
        return "specials"
    end

    if enemy_meta.is_elite == true then
        return "elites"
    end

    if enemy_meta.is_horde == true then
        return "hordes"
    end

    if enemy_meta.is_patrol == true then
        return "patrols"
    end

    return "regular"
end

function Core:get_enemy_spawn_source(breed_name, optional_param_table)
    local enemies = self.state.pools and self.state.pools.enemies
    local enemy_meta = enemies and enemies.by_name and enemies.by_name[breed_name]

    if enemy_meta and enemy_meta.is_boss == true then
        return "monster_event"
    end

    if enemy_meta and enemy_meta.is_special == true then
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
            if enemy_meta and enemy_meta.is_patrol == true then
                return "patrol"
            end

            if enemy_meta and enemy_meta.is_horde == true then
                return "horde"
            end

            return "roamer"
        end
    end

    if enemy_meta and (enemy_meta.is_horde == true or enemy_meta.is_patrol == true) then
        return enemy_meta.is_patrol == true and "patrol" or "horde"
    end

    if enemy_meta then
        return "roamer"
    end

    return "unknown"
end

function Core:should_despawn_enemy_for_weights(config, breed_name, optional_param_table)
    if not config or type(breed_name) ~= "string" then
        return false
    end

    if config.enable_chaos_mode == true then
        return false
    end

    if config.strict_enemy_weight_enforcement ~= true then
        return false
    end

    local is_grouped_spawn = type(optional_param_table) == "table" and optional_param_table.optional_group_id ~= nil

    if self:is_enemy_blocked_for_randomizer(breed_name) then
        return false
    end

    if config.disabled_enemy_breeds and config.disabled_enemy_breeds[breed_name] == true then
        return true
    end

    local category = self:get_enemy_category(breed_name)
    local enemies = self.state.pools and self.state.pools.enemies
    local enemy_meta = enemies and enemies.by_name and enemies.by_name[breed_name]

    if type(category) ~= "string" then
        return false
    end

    -- Mission boss encounters can be hard-scripted and despawning them can break flow.
    if category == "bosses" then
        return false
    end

    local enabled = config.categories and config.categories[category] ~= false
    local weight = config.weights and tonumber(config.weights[category]) or 0
    local should_despawn = false
    local despawn_reason = nil
    local source_key = nil

    if config.enable_refined_enemy_weights == true then
        local source_weights = config.source_weights or {}
        source_key = self:get_enemy_spawn_source(breed_name, optional_param_table)
        local source_weight = tonumber(source_weights[source_key] or source_weights.unknown or 100) or 100

        if source_weight <= 0 then
            should_despawn = true
            despawn_reason = despawn_reason or "source_weight_zero"
        end

        local archetype = enemy_meta and enemy_meta.archetype

        if type(archetype) == "string" then
            local archetype_weights = config.archetype_weights or {}
            local archetype_weight = tonumber(archetype_weights[archetype] or 100) or 100

            if archetype_weight <= 0 then
                should_despawn = true
                despawn_reason = despawn_reason or "archetype_weight_zero"
            end
        end
    end

    if not enabled then
        should_despawn = true
        despawn_reason = despawn_reason or "category_disabled"
    elseif weight <= 0 then
        should_despawn = true
        despawn_reason = despawn_reason or "category_weight_zero"
    end

    if not should_despawn then
        return false
    end

    if is_grouped_spawn then
        -- In strict mode we allow culling grouped disallowed breeds, but replacement logic
        -- must spawn standalone units to avoid invalid patrol/group blackboard assumptions.
        self:_log_debug(string.format(
            "[Randomizer] Strict despawn queued: breed=%s category=%s archetype=%s source=%s grouped=true reason=%s",
            tostring(breed_name),
            tostring(category),
            tostring(enemy_meta and enemy_meta.archetype or "unknown"),
            tostring(source_key or self:get_enemy_spawn_source(breed_name, optional_param_table)),
            tostring(despawn_reason or "unknown")
        ), config)

        return true
    end

    self:_log_debug(string.format(
        "[Randomizer] Strict despawn queued: breed=%s category=%s archetype=%s source=%s grouped=false reason=%s",
        tostring(breed_name),
        tostring(category),
        tostring(enemy_meta and enemy_meta.archetype or "unknown"),
        tostring(source_key or self:get_enemy_spawn_source(breed_name, optional_param_table)),
        tostring(despawn_reason or "unknown")
    ), config)

    return true
end

function Core:is_boss_only_mode(config)
    if not config then
        return false
    end

    local categories = config.categories or {}
    local weights = config.weights or {}
    local bosses_enabled = categories.bosses ~= false
    local bosses_weight = tonumber(weights.bosses) or 0

    if not bosses_enabled or bosses_weight <= 0 then
        return false
    end

    for i = 1, #ENEMY_WEIGHT_CATEGORIES do
        local category = ENEMY_WEIGHT_CATEGORIES[i]

        if category ~= "bosses" then
            local enabled = categories[category] ~= false
            local weight = tonumber(weights[category]) or 0

            if enabled and weight > 0 then
                return false
            end
        end
    end

    return true
end

function Core:queue_enemy_despawn(unit)
    if not unit then
        return
    end

    local runtime = self.state.enemy_runtime

    if not runtime or type(runtime.pending_despawn_units) ~= "table" then
        return
    end

    if runtime.pending_despawn_units[unit] == nil then
        runtime.pending_despawn_units[unit] = 0
    end
end

function Core:process_pending_enemy_despawns(spawn_manager)
    local runtime = self.state.enemy_runtime

    if not runtime or type(runtime.pending_despawn_units) ~= "table" then
        return
    end

    if not spawn_manager or type(spawn_manager.despawn_minion) ~= "function" then
        return
    end

    if next(runtime.pending_despawn_units) == nil then
        return
    end

    local max_retry = math.max(1, math.floor(tonumber(self.data.safety and self.data.safety.max_pending_enemy_despawn_retries) or 30))
    local pending = runtime.pending_despawn_units
    local lookup = spawn_manager._spawned_minions_index_lookup

    for unit, attempts in pairs(pending) do
        local retry_count = math.max(0, math.floor(tonumber(attempts) or 0))
        local alive = true

        if type(Alive) == "function" then
            alive = Alive(unit) == true
        end

        if not unit or not alive then
            retry_count = retry_count + 1

            if retry_count > max_retry then
                pending[unit] = nil
            else
                pending[unit] = retry_count
            end
        else
            local ok = pcall(spawn_manager.despawn_minion, spawn_manager, unit)
            local still_spawned = type(lookup) == "table" and lookup[unit] ~= nil

            if ok and not still_spawned then
                pending[unit] = nil
            else
                retry_count = retry_count + 1

                if retry_count > max_retry then
                    pending[unit] = nil
                else
                    pending[unit] = retry_count
                end
            end
        end
    end
end

function Core:get_extra_enemy_spawn_count(config)
    local multiplier = self.utils.clamp(tonumber(config and config.enemy_spawn_rate_multiplier) or 1.0, 1.0, 5.0)
    local extra_budget = math.max(0, multiplier - 1.0)
    local guaranteed = math.floor(extra_budget)
    local fractional = extra_budget - guaranteed

    if fractional > 0 and self:next_float() <= fractional then
        guaranteed = guaranteed + 1
    end

    return guaranteed
end

function Core:on_enemy_spawned(unit, requested_breed, final_breed, spawn_context)
    if not unit then
        return
    end

    local boss_runtime = self.state.boss_runtime

    if boss_runtime then
        local is_randomized_boss = self:is_boss_breed(final_breed) and not self:is_boss_breed(requested_breed)

        if is_randomized_boss and not boss_runtime.randomized_boss_unit_lookup[unit] then
            boss_runtime.randomized_boss_unit_lookup[unit] = true
            boss_runtime.randomized_boss_alive = boss_runtime.randomized_boss_alive + 1

            local now = self.utils.get_gameplay_time()

            if now then
                boss_runtime.last_randomized_boss_spawn_t = now
            end
        end
    end

    local enemy_runtime = self.state.enemy_runtime
    local is_extra_spawn = spawn_context and spawn_context.is_extra_spawn == true

    if enemy_runtime and is_extra_spawn and not enemy_runtime.extra_unit_lookup[unit] then
        enemy_runtime.extra_unit_lookup[unit] = true
        enemy_runtime.extra_spawned_count = enemy_runtime.extra_spawned_count + 1
        enemy_runtime.extra_alive = enemy_runtime.extra_alive + 1
    end
end

function Core:on_enemy_despawned(unit)
    if not unit then
        return
    end

    local boss_runtime = self.state.boss_runtime

    if boss_runtime and boss_runtime.randomized_boss_unit_lookup[unit] then
        boss_runtime.randomized_boss_unit_lookup[unit] = nil
        boss_runtime.randomized_boss_alive = math.max(0, boss_runtime.randomized_boss_alive - 1)
    end

    local enemy_runtime = self.state.enemy_runtime

    if enemy_runtime and enemy_runtime.extra_unit_lookup[unit] then
        enemy_runtime.extra_unit_lookup[unit] = nil
        enemy_runtime.extra_alive = math.max(0, enemy_runtime.extra_alive - 1)
    end
end

function Core:should_spawn_extra_item(config, requested_pickup)
    if not config or not config.spawn_extra_random_items then
        return false
    end

    if config.categories and config.categories.items == false then
        return false
    end

    if self.item_randomizer and self.item_randomizer.is_mission_critical(self, requested_pickup) then
        return false
    end

    local runtime = self.state.item_runtime

    if not runtime then
        return false
    end

    local chance = self.utils.clamp(tonumber(config.extra_random_item_chance) or 0, 0, 100)

    if chance <= 0 then
        return false
    end

    local max_per_mission = math.max(0, math.floor(tonumber(config.extra_random_item_max_per_mission) or 0))

    if max_per_mission > 0 and runtime.extra_spawned_count >= max_per_mission then
        return false
    end

    local min_gap = tonumber(self.data.safety and self.data.safety.extra_items_min_seconds_between_spawns) or 0
    local now = self.utils.get_gameplay_time()

    if now and now - (runtime.last_extra_spawn_t or -math.huge) < math.max(0, min_gap) then
        return false
    end

    return self:next_float() <= (chance / 100)
end

function Core:on_extra_item_spawned()
    local runtime = self.state.item_runtime

    if not runtime then
        return
    end

    runtime.extra_spawned_count = runtime.extra_spawned_count + 1

    local now = self.utils.get_gameplay_time()

    if now then
        runtime.last_extra_spawn_t = now
    end
end

function Core:next_float()
    return self.seed.next_float(self.state)
end

function Core:next_int(min_value, max_value)
    return self.seed.next_int(self.state, min_value, max_value)
end

function Core:random_array_entry(array)
    if type(array) ~= "table" or #array == 0 then
        return nil
    end

    local index = self.seed.choose_index(self.state, #array)

    if not index then
        return nil
    end

    return array[index]
end

function Core:is_valid_enemy(breed_name)
    if type(breed_name) ~= "string" then
        return false
    end

    local enemies = self.state.pools and self.state.pools.enemies

    return enemies and enemies.by_name and enemies.by_name[breed_name] ~= nil or false
end

function Core:is_enemy_blocked_for_randomizer(breed_name)
    if type(breed_name) ~= "string" then
        return true
    end

    local checker = self.data and self.data.is_enemy_blocked_for_randomizer

    if type(checker) == "function" then
        return checker(breed_name) == true
    end

    return false
end

function Core:is_valid_item(pickup_name)
    if type(pickup_name) ~= "string" then
        return false
    end

    local items = self.state.pools and self.state.pools.items

    return items and items.by_name and items.by_name[pickup_name] ~= nil or false
end

function Core:get_difficulty_rank()
    local difficulty_manager = Managers and Managers.state and Managers.state.difficulty

    if not difficulty_manager then
        return 3
    end

    local challenge = difficulty_manager.get_challenge and difficulty_manager:get_challenge() or difficulty_manager:get_initial_challenge()
    local resistance = difficulty_manager.get_resistance and difficulty_manager:get_resistance() or difficulty_manager:get_initial_resistance()

    challenge = tonumber(challenge) or 3
    resistance = tonumber(resistance) or 3

    local average = (challenge + resistance) * 0.5
    local rank = math.floor(average + 0.5)

    return self.utils.clamp(rank, 1, 5)
end

function Core:debug_summary()
    local enemy_pool = self.state.pools.enemies or {}
    local item_pool = self.state.pools.items or {}

    return {
        seed = self.state.active_seed,
        mission_count = self.state.mission_count,
        enemy_categories = {
            all = #(enemy_pool.all or {}),
            regular = #(enemy_pool.regular or {}),
            elites = #(enemy_pool.elites or {}),
            specials = #(enemy_pool.specials or {}),
            bosses = #(enemy_pool.bosses or {}),
            patrols = #(enemy_pool.patrols or {}),
            hordes = #(enemy_pool.hordes or {}),
            enemy_meta = _table_size(enemy_pool.by_name),
        },
        item_categories = {
            all = #(item_pool.all or {}),
            safe = #(item_pool.safe or {}),
            safe_non_materials = #(item_pool.safe_non_materials or {}),
            item_meta = _table_size(item_pool.by_name),
        },
    }
end

return Core
