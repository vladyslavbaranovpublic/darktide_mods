--[[
    File: slot_logic.lua
    Description: Slot-state and queue logic helpers used by debug rendering.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local SlotLogic = {}
SlotLogic.__index = SlotLogic

function SlotLogic.new(constants, util)
	return setmetatable({
		constants = constants,
		util = util,
	}, SlotLogic)
end

local function resolve_unit_id(id)
	if type(id) ~= "number" then
		return nil
	end
	local spawner = Managers.state and Managers.state.unit_spawner
	if not spawner or not spawner.unit then
		return nil
	end
	local ok, resolved = pcall(spawner.unit, spawner, id)
	if ok and resolved then
		return resolved
	end
	ok, resolved = pcall(spawner.unit, spawner, id, true)
	if ok and resolved then
		return resolved
	end
	return nil
end

local function resolve_unit_ref(value, depth)
	if value == nil then
		return nil
	end
	local level = depth or 0
	if level > 2 then
		return nil
	end
	local value_type = type(value)
	if value_type == "userdata" then
		return value
	end
	if value_type == "number" then
		return resolve_unit_id(value)
	end
	if value_type ~= "table" then
		return nil
	end

	local direct =
		rawget(value, "unit")
		or rawget(value, "user_unit")
		or rawget(value, "target_unit")
		or rawget(value, "player_unit")
		or rawget(value, 1)
	if direct and direct ~= value then
		local resolved = resolve_unit_ref(direct, level + 1)
		if resolved then
			return resolved
		end
	end

	local id =
		rawget(value, "unit_id")
		or rawget(value, "user_unit_id")
		or rawget(value, "target_unit_id")
		or rawget(value, "id")
	if type(id) == "number" then
		local resolved = resolve_unit_id(id)
		if resolved then
			return resolved
		end
	end

	local scanned = 0
	for key, sub_value in pairs(value) do
		scanned = scanned + 1
		if scanned > 8 then
			break
		end
		if type(sub_value) == "userdata" then
			return sub_value
		end
		if type(key) == "userdata" then
			return key
		end
	end

	return nil
end

local function build_queue_units(queue)
	local units = {}
	if not queue then
		return units, 0
	end
	local n = #queue
	for i = 1, n do
		local unit = resolve_unit_ref(queue[i])
		if unit then
			units[#units + 1] = unit
		end
	end
	if #units > 0 then
		return units, #units
	end
	local ordered = {}
	for key, value in pairs(queue) do
		ordered[#ordered + 1] = { key = key, value = value }
	end
	table.sort(ordered, function(a, b)
		local ka = type(a.key) == "number" and a.key or math.huge
		local kb = type(b.key) == "number" and b.key or math.huge
		return ka < kb
	end)
	for i = 1, #ordered do
		local value = ordered[i].value
		local unit = resolve_unit_ref(value)
		if not unit then
			unit = resolve_unit_ref(ordered[i].key)
		end
		if unit then
			units[#units + 1] = unit
		end
	end
	return units, #units
end

local function queue_count(queue)
	local _, n = build_queue_units(queue)
	if n and n > 0 then
		return n
	end
	if not queue then
		return 0
	end
	local raw = #queue
	if raw and raw > 0 then
		return raw
	end
	local count = 0
	for key, value in pairs(queue) do
		local key_t = type(key)
		local value_t = type(value)
		local looks_like_entry = key_t == "number"
			or key_t == "userdata"
			or value_t == "number"
			or value_t == "userdata"
			or value_t == "table"
			or key_t == "table"
		if looks_like_entry then
			count = count + 1
		end
	end
	return count
end

function SlotLogic:_find_slot_user(slot, unit_extension_data)
	if not slot then
		return nil
	end
	local user_unit = resolve_unit_ref(slot.user_unit)
	if user_unit and self.util:unit_is_alive(user_unit) then
		return user_unit
	end
	local extension_data = unit_extension_data
	if not extension_data then
		local slot_system = Managers.state and Managers.state.extension and Managers.state.extension:system("slot_system")
		extension_data = slot_system and slot_system._unit_extension_data or nil
	end
	if extension_data then
		for unit, extension in pairs(extension_data) do
			if extension and extension.slot == slot and self.util:unit_is_alive(unit) then
				return unit
			end
		end
	end
	return user_unit
end

function SlotLogic:_has_slot_waiters(slot, unit_extension_data)
	if not slot then
		return false
	end
	local extension_data = unit_extension_data
	if not extension_data then
		local slot_system = Managers.state and Managers.state.extension and Managers.state.extension:system("slot_system")
		extension_data = slot_system and slot_system._unit_extension_data or nil
	end
	if not extension_data then
		return false
	end
	for unit, extension in pairs(extension_data) do
		if extension and extension.wait_slot == slot and self.util:unit_is_alive(unit) then
			return true
		end
	end
	return false
end

function SlotLogic:slot_occupied(slot, slot_pos, settings, unit_extension_data)
	local user_unit = self:_find_slot_user(slot, unit_extension_data)
	if not slot or not user_unit or slot.disabled or slot.released then
		return false
	end
	if not self.util:unit_is_alive(user_unit) then
		return false
	end
	local user_pos = self.util:get_unit_position(user_unit)
	if not user_pos or not slot_pos then
		return false
	end
	local slot_settings = self.constants.SlotTypeSettings[slot.type] or self.constants.SlotTypeSettings.normal
	local radius = slot_settings and slot_settings.radius or 0.5
	local scale = settings and settings.occupied_distance_scale or 1.0
	local threshold = math.max(radius, 0.75) * math.max(scale, 0.5) * 1.5
	local dist_sq = nil
	if Vector3 and Vector3.flat and Vector3.distance_squared then
		local user_flat = Vector3.flat(user_pos)
		local slot_flat = Vector3.flat(slot_pos)
		dist_sq = Vector3.distance_squared(user_flat, slot_flat)
	else
		local dx = user_pos.x - slot_pos.x
		local dy = user_pos.y - slot_pos.y
		dist_sq = dx * dx + dy * dy
	end
	dist_sq = dist_sq or math.huge
	return dist_sq <= (threshold * threshold)
end

function SlotLogic:slot_state_rgb(slot, slot_pos, settings, unit_extension_data)
	if slot.disabled then
		return self.constants.COLORS.blocked
	end
	if slot.released then
		return self.constants.COLORS.released
	end
	local slot_type = slot.type
	local slot_colors = settings and settings.slot_type_colors and settings.slot_type_colors[slot_type]
	if slot.user_unit then
		if self:slot_occupied(slot, slot_pos, settings, unit_extension_data) then
			return slot_colors and slot_colors.occupied or self.constants.COLORS.occupied
		end
		return slot_colors and slot_colors.moving or self.constants.COLORS.moving
	end
	return slot_colors and slot_colors.free or self.constants.COLORS.free
end

function SlotLogic:slot_passes_filter(slot, slot_pos, filter, settings, unit_extension_data)
	if filter == "all" then
		return true
	end
	local occupied = self:slot_occupied(slot, slot_pos, settings, unit_extension_data)
	local assigned = self:_find_slot_user(slot, unit_extension_data) ~= nil
	local queued = queue_count(slot.queue) > 0 or self:_has_slot_waiters(slot, unit_extension_data)
	local free = (not slot.disabled) and (not occupied) and (not assigned) and (not queued)
	if filter == "active" then
		return occupied or queued or assigned
	end
	if filter == "occupied" then
		return occupied or assigned
	end
	if filter == "queued" then
		return queued
	end
	if filter == "free" then
		return free
	end
	return true
end

function SlotLogic:unit_label(unit)
	if not unit then
		return "none"
	end
	local player = Managers.player and Managers.player:player_by_unit(unit)
	if player and player.name then
		return player:name()
	end
	if ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "unit_data_system") then
		local unit_data = ScriptUnit.extension(unit, "unit_data_system")
		local breed_name = unit_data and unit_data:breed_name()
		if breed_name then
			return breed_name
		end
	end
	return tostring(unit)
end

function SlotLogic:get_slot_extension(unit, unit_extension_data)
	if not unit then
		return nil
	end
	if unit_extension_data and unit_extension_data[unit] then
		return unit_extension_data[unit]
	end
	if ScriptUnit and ScriptUnit.has_extension then
		local ok_system, extension_system = pcall(ScriptUnit.has_extension, unit, "slot_system")
		if ok_system and extension_system then
			if type(extension_system) == "table" then
				return extension_system
			end
			if ScriptUnit.extension then
				local ok_ext_system, ext_system = pcall(ScriptUnit.extension, unit, "slot_system")
				if ok_ext_system and ext_system then
					return ext_system
				end
			end
		end
		local ok_slot, extension_slot = pcall(ScriptUnit.has_extension, unit, "slot")
		if ok_slot and extension_slot then
			if type(extension_slot) == "table" then
				return extension_slot
			end
			if ScriptUnit.extension then
				local ok_ext_slot, ext_slot = pcall(ScriptUnit.extension, unit, "slot")
				if ok_ext_slot and ext_slot then
					return ext_slot
				end
			end
		end
		if ScriptUnit.extension then
			local ok_system_ext, ext_system = pcall(ScriptUnit.extension, unit, "slot_system")
			if ok_system_ext and ext_system then
				return ext_system
			end
			local ok_slot_ext, ext_slot = pcall(ScriptUnit.extension, unit, "slot")
			if ok_slot_ext and ext_slot then
				return ext_slot
			end
		end
	end
	return nil
end

function SlotLogic:find_next_in_queue(slot, unit_extension_data, queue_units)
	local units, queue_n
	if queue_units then
		units = queue_units
		queue_n = #queue_units
	else
		units, queue_n = build_queue_units(slot and slot.queue)
	end
	if not units or queue_n == 0 then
		return nil
	end
	for i = queue_n, 1, -1 do
		local queued_unit = units[i]
		local queued_extension = self:get_slot_extension(queued_unit, unit_extension_data)
		if not queued_extension or not queued_extension.use_slot_type or queued_extension.use_slot_type == slot.type then
			return queued_unit
		end
	end
	return units[queue_n]
end

function SlotLogic:build_slot_label(slot, slot_pos, settings, distance_value, unit_extension_data)
	local header = string.format("Slot %d (%s)", slot.index or 0, slot.type or "?")
	local mode = settings.text_mode
	local dist_ok = type(distance_value) == "number" and distance_value == distance_value
	local show_user = settings.label_show_user ~= false
	local show_queue = settings.label_show_queue ~= false
	if mode == "distances" then
		if dist_ok then
			return string.format("%s\n%.1fm", header, distance_value)
		end
		return header
	end

	local occupied = self:slot_occupied(slot, slot_pos, settings, unit_extension_data)
	local user_unit = self:_find_slot_user(slot, unit_extension_data)
	local status = slot.disabled and "blocked"
		or slot.released and "released"
		or user_unit and (occupied and "occupied" or "assigned")
		or "free"
	local line = status
	if user_unit and show_user then
		line = string.format("%s | %s", line, self:unit_label(user_unit))
	end
	local queue_units, queue_n = build_queue_units(slot.queue)
	if queue_n > 0 and show_queue then
		local next_unit = self:find_next_in_queue(slot, unit_extension_data, queue_units)
		local next_name = next_unit and self:unit_label(next_unit) or "?"
		line = string.format("%s | q:%d next:%s", line, queue_n, next_name)
	end
	if mode == "both" and dist_ok then
		line = string.format("%s | %.1fm", line, distance_value)
	end
	return string.format("%s\n%s", header, line)
end

return SlotLogic
