--[[
    File: item_randomizer.lua
    Description: Item spawn replacement logic with safety guards for mission-critical pickups.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local ItemRandomizer = {}

local function _is_ammo_crate_pickup(pickup_name)
    return type(pickup_name) == "string" and string.find(pickup_name, "ammo_cache", 1, true) ~= nil
end

local function _is_luggable_pickup_name(pickup_name)
    return type(pickup_name) == "string" and string.find(pickup_name, "luggable", 1, true) ~= nil
end

local function _item_meta(core, pickup_name)
    local item_pools = core.state.pools and core.state.pools.items

    if not item_pools or type(pickup_name) ~= "string" then
        return nil
    end

    return item_pools.by_name and item_pools.by_name[pickup_name]
end

local function _is_context_mission_critical(context)
    if type(context) ~= "table" then
        return false
    end

    -- Pickups spawned/attached to explicit units (for puzzle/health-station style flows)
    -- often assume specific extension contracts and should not be randomized.
    if context.optional_placed_on_unit ~= nil then
        return true
    end

    local pickup_spawner = context.optional_pickup_spawner

    if type(pickup_spawner) == "table" and type(pickup_spawner._components) == "table" then
        local components = pickup_spawner._components

        for i = 1, #components do
            local component = components[i]
            local spawnable_pickups = component and component.spawnable_pickups

            if type(spawnable_pickups) == "table" then
                for j = 1, #spawnable_pickups do
                    if _is_luggable_pickup_name(spawnable_pickups[j]) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function ItemRandomizer.is_mission_critical(core, pickup_name)
    if _is_luggable_pickup_name(pickup_name) then
        return true
    end

    local meta = _item_meta(core, pickup_name)

    return meta and meta.is_mission_critical == true or false
end

local function _build_item_class_weights(core, config, include_materials)
    local item_pools = core.state.pools and core.state.pools.items
    local class_order = core.data.item_class_order or {}
    local weights = {}

    for i = 1, #class_order do
        local item_class = class_order[i]
        local configured_weight = tonumber(config.item_weights[item_class]) or 0
        local safe_pool = item_pools.safe_by_class and item_pools.safe_by_class[item_class]
        local safe_count = safe_pool and #safe_pool or 0

        if safe_count <= 0 then
            configured_weight = 0
        elseif item_class == "materials" and not include_materials then
            configured_weight = 0
        end

        weights[item_class] = math.max(0, configured_weight)
    end

    return weights
end

local function _pick_ammo_item(core, config, selected_pool)
    if type(selected_pool) ~= "table" or #selected_pool == 0 then
        return nil
    end

    local specific_weights = config.item_specific_weights or {}
    local ammo_crate_weight = core.utils.clamp(tonumber(specific_weights.ammo_crate) or 50, 0, 100)
    local non_crate_weight = 100 - ammo_crate_weight
    local weight_by_pickup = {}
    local has_positive_weight = false

    for i = 1, #selected_pool do
        local pickup_name = selected_pool[i]
        local weight = _is_ammo_crate_pickup(pickup_name) and ammo_crate_weight or non_crate_weight

        weight_by_pickup[pickup_name] = weight

        if weight > 0 then
            has_positive_weight = true
        end
    end

    if has_positive_weight then
        local weighted_item = core.utils.weighted_pick(weight_by_pickup, selected_pool, function()
            return core:next_float()
        end)

        if core:is_valid_item(weighted_item) then
            return weighted_item
        end
    end

    return core:random_array_entry(selected_pool)
end

function ItemRandomizer.pick_weighted_item(core, config, include_materials)
    local item_pools = core.state.pools and core.state.pools.items

    if not item_pools then
        return nil
    end

    local class_order = core.data.item_class_order or {}
    local class_weights = _build_item_class_weights(core, config, include_materials == true)
    local selected_class = core.utils.weighted_pick(class_weights, class_order, function()
        return core:next_float()
    end)

    if selected_class then
        local selected_pool = item_pools.safe_by_class and item_pools.safe_by_class[selected_class]
        local selected_item

        if selected_class == "ammo" then
            selected_item = _pick_ammo_item(core, config, selected_pool)
        else
            selected_item = core:random_array_entry(selected_pool)
        end

        if core:is_valid_item(selected_item) then
            return selected_item
        end
    end

    local fallback_pool = item_pools.safe

    if not include_materials then
        fallback_pool = item_pools.safe_non_materials or {}
    end

    return core:random_array_entry(fallback_pool)
end

function ItemRandomizer.randomize(core, requested_pickup, context, config)
    if type(requested_pickup) ~= "string" or not core:is_valid_item(requested_pickup) then
        return requested_pickup
    end

    if _is_luggable_pickup_name(requested_pickup) then
        return requested_pickup
    end

    local item_meta = _item_meta(core, requested_pickup)

    if not item_meta then
        return requested_pickup
    end

    if item_meta.is_mission_critical or _is_context_mission_critical(context) then
        return requested_pickup
    end

    if config.enable_chaos_mode then
        local chaos_item = core.chaos_mode.random_item(core, requested_pickup)

        if core:is_valid_item(chaos_item) then
            return chaos_item
        end

        return requested_pickup
    end

    if config.categories.items == false then
        return requested_pickup
    end

    local force_replace_material = config.disable_material_spawns and item_meta.item_class == "materials"

    if not force_replace_material then
        local item_weight = tonumber(config.weights.items) or 0

        if item_weight <= 0 then
            return requested_pickup
        end

        if item_weight < 100 then
            local roll = core:next_float()

            if roll > (item_weight / 100) then
                return requested_pickup
            end
        end
    end

    local replacement = ItemRandomizer.pick_weighted_item(core, config, not config.disable_material_spawns)

    if core:is_valid_item(replacement) then
        return replacement
    end

    local items = core.state.pools and core.state.pools.items or {}
    local fallback_pool = items.all or {}

    if config.disable_material_spawns then
        fallback_pool = items.safe_non_materials or {}
    end

    local fallback = core:random_array_entry(fallback_pool)

    if core:is_valid_item(fallback) then
        return fallback
    end

    return requested_pickup
end

return ItemRandomizer
