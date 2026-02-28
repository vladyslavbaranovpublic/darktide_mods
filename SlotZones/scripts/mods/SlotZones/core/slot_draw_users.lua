--[[
    File: slot_draw_users.lua
    Description: Slot-user, queue-user, and fallback unit drawing helpers.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local SlotDrawUsers = {}
SlotDrawUsers.__index = SlotDrawUsers

function SlotDrawUsers.new()
	return setmetatable({ _slot_positions = {} }, SlotDrawUsers)
end

local function safe_distance(util, a, b)
	local dist_val = util and util.distance and a and b and util:distance(a, b) or nil
	if type(dist_val) ~= "number" or dist_val ~= dist_val then
		return nil
	end
	return dist_val
end

local function resolve_line_thickness(settings)
	local thickness = settings.queue_line_thickness or 0
	if thickness <= 0 then
		thickness = 0.02
	end
	return thickness
end

local function resolve_slot_type(slot, fallback)
	if slot and slot.type then
		return slot.type
	end
	return fallback
end

local function resolve_unit_from_pair(key, value)
	local value_type = type(value)
	if value_type == "userdata" then
		return value
	end
	if value_type == "table" then
		local direct =
			rawget(value, "unit")
			or rawget(value, "user_unit")
			or rawget(value, "target_unit")
			or rawget(value, "player_unit")
			or rawget(value, 1)
		if direct and direct ~= value then
			local resolved = resolve_unit_from_pair(nil, direct)
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
			local resolved = resolve_unit_from_pair(nil, id)
			if resolved then
				return resolved
			end
		end
		local scanned = 0
		for sub_key, sub_value in pairs(value) do
			scanned = scanned + 1
			if scanned > 8 then
				break
			end
			if type(sub_value) == "userdata" then
				return sub_value
			end
			if type(sub_key) == "userdata" then
				return sub_key
			end
		end
		return nil
	end
	local key_type = type(key)
	if key_type == "userdata" then
		return key
	end
	local id = nil
	if value_type == "number" then
		id = value
	elseif key_type == "number" then
		id = key
	end
	if id then
		local spawner = Managers.state and Managers.state.unit_spawner
		if spawner and spawner.unit then
			local ok, resolved = pcall(spawner.unit, spawner, id)
			if ok and resolved then
				return resolved
			end
			ok, resolved = pcall(spawner.unit, spawner, id, true)
			if ok and resolved then
				return resolved
			end
		end
	end
	return nil
end

local function resolve_unit_ref(value)
	return resolve_unit_from_pair(nil, value)
end

local function stable_unit_key(unit, util)
	if util and util.unit_key then
		local ok_key, key = pcall(util.unit_key, util, unit)
		if ok_key and key then
			return key
		end
	end
	if not unit then
		return "none"
	end
	if type(unit) == "number" then
		return tostring(unit)
	end
	local unit_spawner = Managers.state and Managers.state.unit_spawner
	if unit_spawner and unit_spawner.game_object_id then
		local ok_go, go_id = pcall(unit_spawner.game_object_id, unit_spawner, unit)
		if ok_go and type(go_id) == "number" and go_id > 0 then
			return tostring(go_id)
		end
	end
	if unit_spawner and unit_spawner.game_object_id_or_level_index then
		local ok_idx, is_level_unit, id = pcall(unit_spawner.game_object_id_or_level_index, unit_spawner, unit)
		if ok_idx and type(id) == "number" then
			return (is_level_unit and "L" or "G") .. tostring(id)
		end
	end
	return tostring(unit)
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
		local pair = ordered[i]
		local unit = resolve_unit_from_pair(pair.key, pair.value)
		if unit then
			units[#units + 1] = unit
		end
	end
	return units, #units
end

local function collect_waiting_units(slot, unit_extension_data, util)
	local units = {}
	if not slot or not unit_extension_data or not util then
		return units, 0
	end
	for unit, extension in pairs(unit_extension_data) do
		if extension and extension.wait_slot == slot and util:unit_is_alive(unit) then
			units[#units + 1] = unit
		end
	end
	return units, #units
end

local function estimate_queue_position(slot_draw, util, target_unit, slot, slot_pos, slot_radius)
	if not slot_pos then
		return nil
	end
	local target_pos = nil
	if target_unit and util and util.unit_is_alive and util:unit_is_alive(target_unit) then
		target_pos = util:get_unit_position(target_unit)
	end
	local dx, dy = 0, 0
	if target_pos then
		dx = (slot_pos.x or 0) - (target_pos.x or 0)
		dy = (slot_pos.y or 0) - (target_pos.y or 0)
	end
	local len_sq = dx * dx + dy * dy
	if len_sq < 1e-4 then
		local angle = (((slot and slot.index) or 1) - 1) * 0.9
		dx = math.cos(angle)
		dy = math.sin(angle)
		len_sq = 1
	end
	local inv_len = 1 / math.sqrt(len_sq)
	local outward = math.max((slot_radius or 0.5) * 2.2, 0.8)
	local qx = (slot_pos.x or 0) + dx * inv_len * outward
	local qy = (slot_pos.y or 0) + dy * inv_len * outward
	local qz = slot_pos.z or 0
	local refs = util and util.runtime and util.runtime.resolve and util.runtime.resolve() or nil
	if refs and refs.Vector3 then
		return refs.Vector3(qx, qy, qz)
	end
	return { x = qx, y = qy, z = qz }
end

function SlotDrawUsers:reset()
	local positions = self._slot_positions
	if not positions then
		self._slot_positions = {}
		return
	end
	for i = #positions, 1, -1 do
		positions[i] = nil
	end
end

function SlotDrawUsers:track_slot_position(pos)
	if not pos then
		return
	end
	local positions = self._slot_positions
	if not positions then
		positions = {}
		self._slot_positions = positions
	end
	positions[#positions + 1] = pos
end

function SlotDrawUsers:nearest_slot_position(slot_draw, pos)
	local positions = self._slot_positions
	if not positions or not pos or not slot_draw or not slot_draw.util then
		return nil
	end
	local util = slot_draw.util
	local best_pos = nil
	local best_dist = nil
	for i = 1, #positions do
		local candidate = positions[i]
		local dist_sq = util:distance_squared(pos, candidate)
		if dist_sq and (not best_dist or dist_sq < best_dist) then
			best_dist = dist_sq
			best_pos = candidate
		end
	end
	return best_pos
end

function SlotDrawUsers:draw_slot_users(
	slot_draw,
	line_object,
	slot,
	slot_pos,
	state_slot_pos,
	settings,
	player_pos,
	unit_extension_data,
	label_entries,
	alpha,
	slot_radius,
	state_rgb,
	slot_label_type,
	target_unit,
	slot_visible,
	drawn_user_units,
	drawn_queue_units
)
	if not slot_draw or not slot or not slot_pos or not state_slot_pos then
		return
	end

	local util = slot_draw.util
	local constants = slot_draw.constants
	local line_draw = slot_draw.line_draw
	local local_player_unit = util and util.get_local_player_unit and util:get_local_player_unit() or nil
	state_rgb = type(state_rgb) == "table" and state_rgb or constants.COLORS.moving

	local user_unit = resolve_unit_ref(slot.user_unit)
	if local_player_unit and user_unit == local_player_unit then
		user_unit = nil
	end
	local target_key = stable_unit_key(target_unit, util)
	local user_pos = nil
	if user_unit and util:unit_is_alive(user_unit) then
		local raw_user_pos = util:get_unit_position(user_unit)
		user_pos = raw_user_pos and slot_draw:_smooth_position(slot_draw.state.position_cache.units, user_unit, raw_user_pos, alpha) or nil
	end

	local line_thickness = resolve_line_thickness(settings)
	if settings.draw_slot_user_lines and user_unit and line_object and user_pos then
		local line_color = line_draw:to_color(state_rgb, 180)
		line_draw:draw_thick_line(line_object, line_color, slot_pos, user_pos, line_thickness)
	end

	if settings.draw_user_slot_rings and user_unit and line_object and user_pos then
		if not drawn_user_units[user_unit] and util:unit_is_alive(user_unit) then
			local ring_color = line_draw:to_color(state_rgb, 200)
			local ring_settings = constants.SlotTypeSettings[slot_label_type] or constants.SlotTypeSettings.normal
			local ring_radius = (ring_settings and ring_settings.radius or 0.5) * settings.user_slot_radius_scale
			local user_height = settings.enemy_ring_height or settings.slot_height or 0
			local step = user_height > 0 and user_height / 2 or 0.5
			line_draw:draw_cylinder(
				line_object,
				user_pos,
				ring_radius,
				user_height,
				step,
				settings.slot_segments,
				ring_color,
				settings.slot_height_rings,
				settings.slot_vertical_lines
			)
			drawn_user_units[user_unit] = true
		end
	end

	if label_entries and settings.text_mode ~= "off" and settings.label_slot_users and user_unit and user_pos then
		local dist_val = safe_distance(util, player_pos, user_pos)
		local label_max = settings.label_draw_distance
		local allow_label = true
		if label_max and label_max > 0 and dist_val and dist_val > label_max then
			allow_label = false
		end
		if allow_label then
			local occupied = slot_draw.slot_logic:slot_occupied(slot, slot_pos, settings, unit_extension_data)
			local status = occupied and "occupied" or "moving"
			local label_text = string.format(
				"%s\n%s -> Slot %d (%s)",
				slot_draw.slot_logic:unit_label(user_unit),
				status,
				slot.index or 0,
				slot.type or "?"
			)
			label_text = slot_draw:_append_distance(label_text, dist_val, settings.text_mode)
			local key = string.format("slot_user_%s_%s_%s", target_key, slot.type or "slot", slot.index or 0)
			local index = #label_entries + 1
			local entry = label_entries[index]
			if not entry then
				entry = {}
				label_entries[index] = entry
			end
			entry.key = key
			entry.position = user_pos
			entry.text = label_text
			entry.color = state_rgb
			entry.distance = dist_val or 0
			entry.priority = 20
			if settings.draw_label_lines and line_object then
				local ring_settings = constants.SlotTypeSettings[slot_label_type] or constants.SlotTypeSettings.normal
				local ring_radius = (ring_settings and ring_settings.radius or 0.5) * settings.user_slot_radius_scale
				slot_draw:_draw_label_line(
					line_object,
					user_pos,
					ring_radius,
					settings.text_height,
					state_rgb,
					settings.label_line_thickness,
					player_pos
				)
			end
		end
	end

	local queue_units, queue_n = build_queue_units(slot.queue)
	if queue_n == 0 then
		queue_units, queue_n = collect_waiting_units(slot, unit_extension_data, util)
	end
	local raw_queue_pos = slot.queue_position and slot.queue_position.unbox and slot.queue_position:unbox() or nil
	if not raw_queue_pos then
		raw_queue_pos = estimate_queue_position(slot_draw, util, target_unit, slot, slot_pos, slot_radius)
	end
	local queue_pos = raw_queue_pos and slot_draw:_smooth_position(slot_draw.state.position_cache.queues, slot, raw_queue_pos, alpha) or nil
	local queue_any_visible = slot_visible and queue_pos and (queue_n > 0 or settings.slot_filter == "all")
	local queue_radius = slot_radius * settings.queue_radius_scale
	if queue_any_visible and settings.draw_queue_positions and line_object then
		local queue_color = line_draw:to_color(constants.COLORS.queue, 200)
		local queue_height = settings.queue_slot_height or 0
		local queue_step = queue_height > 0 and queue_height / 2 or 0
		line_draw:draw_cylinder(
			line_object,
			queue_pos,
			queue_radius,
			queue_height,
			queue_step,
			settings.slot_segments,
			queue_color,
			settings.slot_height_rings,
			settings.slot_vertical_lines
		)
	end
	if queue_any_visible and settings.draw_queue_positions then
		if label_entries and settings.text_mode ~= "off" and settings.queue_label_enabled then
			local dist_val = safe_distance(util, player_pos, queue_pos)
			local label_max = settings.label_draw_distance
			local allow_label = true
			if label_max and label_max > 0 and dist_val and dist_val > label_max then
				allow_label = false
			end
			if allow_label then
				local label_text = string.format("Queue pos\nSlot %d (%s)", slot.index or 0, slot.type or "?")
				label_text = slot_draw:_append_distance(label_text, dist_val, settings.text_mode)
				local key = string.format("queue_pos_%s_%s_%s", target_key, slot.type or "slot", slot.index or 0)
				local index = #label_entries + 1
				local entry = label_entries[index]
				if not entry then
					entry = {}
					label_entries[index] = entry
				end
				entry.key = key
				entry.position = queue_pos
				entry.text = label_text
				entry.color = settings.queue_label_color or constants.COLORS.queue
				entry.distance = dist_val or 0
				entry.text_size = settings.queue_label_size
				entry.height = settings.queue_label_height
				entry.priority = 30
				if settings.draw_label_lines and line_object then
					slot_draw:_draw_label_line(
						line_object,
						queue_pos,
						queue_radius,
						entry.height or settings.text_height,
						entry.color,
						settings.label_line_thickness,
						player_pos
					)
				end
			end
		end
	end

	local next_unit = queue_n > 0 and slot_draw.slot_logic:find_next_in_queue(slot, unit_extension_data, queue_units) or nil
	local limit = settings.max_queue_lines
	if limit <= 0 or limit > queue_n then
		limit = queue_n
	end

	if queue_any_visible and settings.draw_queue_lines and queue_n > 0 and line_object then
		for qi = 1, limit do
			local queued_unit = queue_units[qi]
			if queued_unit and queued_unit ~= local_player_unit and util:unit_is_alive(queued_unit) then
				local raw_queued_pos = util:get_unit_position(queued_unit)
				local queued_pos = raw_queued_pos and slot_draw:_smooth_position(
					slot_draw.state.position_cache.units,
					queued_unit,
					raw_queued_pos,
					alpha
				) or nil
				if queued_pos then
					local is_next = next_unit and queued_unit == next_unit
					local line_rgb = is_next and constants.COLORS.queue_next or constants.COLORS.queue
					local line_color = line_draw:to_color(line_rgb, 180)
					line_draw:draw_thick_line(line_object, line_color, queue_pos, queued_pos, line_thickness)
				end
			end
		end
	end

	if slot_visible and queue_n > 0 then
		for qi = 1, limit do
			local queued_unit = queue_units[qi]
			if queued_unit and queued_unit ~= local_player_unit and util:unit_is_alive(queued_unit)
				and (not user_unit or queued_unit ~= user_unit) then
				local raw_queued_pos = util:get_unit_position(queued_unit)
				local queued_pos = raw_queued_pos and slot_draw:_smooth_position(
					slot_draw.state.position_cache.units,
					queued_unit,
					raw_queued_pos,
					alpha
				) or nil
				if queued_pos then
					local occupied = slot_draw.slot_logic:slot_occupied(slot, slot_pos, settings, unit_extension_data)
					local slot_colors = settings.slot_type_colors and settings.slot_type_colors[slot.type]
					local queue_rgb = type(settings.queue_unit_color) == "table" and settings.queue_unit_color
						or constants.COLORS.queue
					local occupied_rgb = slot_colors and type(slot_colors.occupied) == "table" and slot_colors.occupied
						or constants.COLORS.occupied
					local ring_rgb = occupied and occupied_rgb or queue_rgb
					local is_next = next_unit and queued_unit == next_unit
					if settings.draw_queue_unit_lines and line_object then
						local line_color = line_draw:to_color(ring_rgb, 180)
						line_draw:draw_thick_line(line_object, line_color, queued_pos, slot_pos, line_thickness)
					end
					if settings.draw_queue_unit_rings and line_object and not drawn_queue_units[queued_unit] then
						local queue_color = line_draw:to_color(ring_rgb, 200)
						local ring_settings = constants.SlotTypeSettings[slot_label_type] or constants.SlotTypeSettings.normal
						local ring_radius = (ring_settings and ring_settings.radius or 0.5) * settings.queue_unit_radius_scale
						local queue_unit_height = settings.enemy_ring_height or settings.slot_height or 0
						local queue_unit_step = queue_unit_height > 0 and queue_unit_height / 2 or 0.5
						line_draw:draw_cylinder(
							line_object,
							queued_pos,
							ring_radius,
							queue_unit_height,
							queue_unit_step,
							settings.slot_segments,
							queue_color,
							settings.slot_height_rings,
							settings.slot_vertical_lines
						)
					end
					if label_entries and settings.text_mode ~= "off" and settings.queue_label_enabled and not drawn_queue_units[queued_unit] then
						local dist_val = safe_distance(util, player_pos, queued_pos)
						local label_max = settings.label_draw_distance
						local allow_label = true
						if label_max and label_max > 0 and dist_val and dist_val > label_max then
							allow_label = false
						end
						if allow_label then
							local status = is_next and "next" or "waiting"
							local label_text = string.format(
								"Queue %d\n%s\n%s -> Slot %d (%s)",
								qi,
								slot_draw.slot_logic:unit_label(queued_unit),
								status,
								slot.index or 0,
								slot.type or "?"
							)
							label_text = slot_draw:_append_distance(label_text, dist_val, settings.text_mode)
							local key = string.format(
								"queue_%s_%s_%s_%s",
								target_key,
								slot.type or "slot",
								slot.index or 0,
								stable_unit_key(queued_unit, util)
							)
							local index = #label_entries + 1
							local entry = label_entries[index]
							if not entry then
								entry = {}
								label_entries[index] = entry
							end
							entry.key = key
							entry.position = queued_pos
							entry.text = label_text
							local queue_label_rgb = type(settings.queue_label_color) == "table" and settings.queue_label_color
								or constants.COLORS.queue
							entry.color = occupied and occupied_rgb or queue_label_rgb
							entry.distance = dist_val or 0
							entry.text_size = settings.queue_label_size
							entry.height = settings.queue_label_height
							entry.priority = 15
							if settings.draw_label_lines and line_object then
								local ring_settings = constants.SlotTypeSettings[slot_label_type] or constants.SlotTypeSettings.normal
								local ring_radius = (ring_settings and ring_settings.radius or 0.5) * settings.queue_unit_radius_scale
								slot_draw:_draw_label_line(
									line_object,
									queued_pos,
									ring_radius,
									entry.height or settings.text_height,
									entry.color,
									settings.label_line_thickness,
									player_pos
								)
							end
						end
					end
					drawn_queue_units[queued_unit] = true
				end
			end
		end
	end

	if slot_visible and label_entries and settings.text_mode ~= "off" then
		local dist_val = safe_distance(util, player_pos, slot_pos)
		local label_max = settings.label_draw_distance
		local allow_label = true
		if label_max and label_max > 0 and dist_val and dist_val > label_max then
			allow_label = false
		end
		if allow_label and slot_draw:_label_slot_type_enabled(resolve_slot_type(slot, slot_label_type), settings) then
			local label_text = slot_draw.slot_logic:build_slot_label(slot, state_slot_pos, settings, dist_val, unit_extension_data)
			local key = string.format("%s_%s_%s", target_key, slot.type or "slot", slot.index or 0)
			local label_size = slot_draw:_slot_label_size(slot_label_type, settings)
			local label_height = slot_draw:_slot_label_height(slot_label_type, settings)
			local index = #label_entries + 1
			local entry = label_entries[index]
			if not entry then
				entry = {}
				label_entries[index] = entry
			end
			entry.key = key
			entry.position = slot_pos
			entry.text = label_text
			entry.color = state_rgb
			entry.distance = dist_val or 0
			entry.text_size = label_size
			entry.height = label_height
			if settings.draw_label_lines and line_object then
				slot_draw:_draw_label_line(
					line_object,
					slot_pos,
					slot_radius,
					label_height,
					state_rgb,
					settings.label_line_thickness,
					player_pos
				)
			end
		end
	end
end

function SlotDrawUsers:draw_fallback(
	slot_draw,
	line_object,
	slot_system,
	unit_extension_data,
	settings,
	player_pos,
	label_entries,
	alpha,
	drawn_user_units
)
	if not slot_draw then
		return
	end
	local draw_any_rings = settings.draw_user_slot_rings or settings.draw_queue_unit_rings
	local draw_any_lines = settings.draw_slot_user_lines or settings.draw_queue_unit_lines
	local draw_any_labels = settings.label_enemy_units or settings.queue_label_enabled
	if not draw_any_rings and not draw_any_lines and not draw_any_labels then
		return
	end

	local util = slot_draw.util
	local constants = slot_draw.constants
	local line_draw = slot_draw.line_draw
	local local_player_unit = util and util.get_local_player_unit and util:get_local_player_unit() or nil
	local line_thickness = resolve_line_thickness(settings)
	local seen_units = {}
	local function unit_alive(unit)
		if not unit then
			return false
		end
		local ok, alive = pcall(util.unit_is_alive, util, unit)
		return ok and alive or false
	end

	local function add_unit(unit)
		if not unit or unit == local_player_unit or seen_units[unit] or not unit_alive(unit) then
			return
		end
		seen_units[unit] = true
	end

	if unit_extension_data then
		for unit, extension in pairs(unit_extension_data) do
			if extension and (extension.use_slot_type or extension.slot or extension.wait_slot) then
				add_unit(unit)
			end
		end
	end

	if slot_system then
		local update_units = slot_system._update_slots_user_units or {}
		for i = 1, #update_units do
			add_unit(update_units[i])
		end
		local prioritized = slot_system._update_slots_user_units_prioritized
		if prioritized then
			for unit in pairs(prioritized) do
				add_unit(unit)
			end
		end
	end

	if not slot_system then
		local side_system = Managers.state and Managers.state.extension and Managers.state.extension:system("side_system")
		if side_system then
			local side = nil
			if local_player_unit and side_system.side_by_unit then
				side = side_system.side_by_unit[local_player_unit]
			end
			if not side and side_system.get_default_player_side_name and side_system.get_side_from_name then
				local ok_name, side_name = pcall(side_system.get_default_player_side_name, side_system)
				if ok_name and side_name then
					local ok_side, side_obj = pcall(side_system.get_side_from_name, side_system, side_name)
					if ok_side and side_obj then
						side = side_obj
					end
				end
			end
			if side and side.relation_units then
				local function add_units_from_list(units)
					if not units then
						return
					end
					local count = units.size or #units
					if count and count > 0 then
						for i = 1, count do
							local unit = resolve_unit_from_pair(i, units[i])
							if unit then
								add_unit(unit)
							end
						end
						return
					end
					for key, value in pairs(units) do
						local unit = resolve_unit_from_pair(key, value)
						if unit then
							add_unit(unit)
						end
					end
				end
				local function add_relation_units(relation)
					local ok_rel, units = pcall(side.relation_units, side, relation)
					if ok_rel and units then
						add_units_from_list(units)
					end
				end
				if side.alive_units_by_tag then
					local ok_alive, units = pcall(side.alive_units_by_tag, side, "enemy")
					if ok_alive and units then
						add_units_from_list(units)
					end
				end
				add_relation_units("enemy")
				add_relation_units("neutral")
			end
		end
		local extension_manager = Managers.state and Managers.state.extension
		if extension_manager and extension_manager.get_entities then
			local ok_entities, unit_entities = pcall(extension_manager.get_entities, extension_manager, "unit_data_system")
			if ok_entities and unit_entities then
				for unit in pairs(unit_entities) do
					add_unit(unit)
				end
			end
		end
		if extension_manager and extension_manager.units then
			local ok_units, unit_map = pcall(extension_manager.units, extension_manager)
			if ok_units and unit_map then
				for unit in pairs(unit_map) do
					if ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "unit_data_system") then
						add_unit(unit)
					end
				end
			end
		end
		if ALIVE then
			for unit, alive in pairs(ALIVE) do
				if alive then
					if Managers.player and Managers.player.player_by_unit and Managers.player:player_by_unit(unit) then
						goto continue_alive
					end
					if ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "unit_data_system") then
						add_unit(unit)
					end
				end
				::continue_alive::
			end
		end
	end

	if not next(seen_units) then
		return
	end

	for unit in pairs(seen_units) do
		if local_player_unit and unit == local_player_unit then
			goto continue
		end
		local extension = nil
		if unit_extension_data then
			extension = unit_extension_data[unit]
		end
		if not extension and slot_draw.slot_logic and slot_draw.slot_logic.get_slot_extension then
			extension = slot_draw.slot_logic:get_slot_extension(unit, unit_extension_data)
		end
		if drawn_user_units and drawn_user_units[unit] then
			goto continue
		end

		if not unit_alive(unit) then
			goto continue
		end

		local raw_user_pos = util:get_unit_position(unit)
		local user_pos = raw_user_pos and slot_draw:_smooth_position(slot_draw.state.position_cache.units, unit, raw_user_pos, alpha) or nil
		if not user_pos then
			goto continue
		end

		local slot = extension and (extension.slot or extension.wait_slot) or nil
		local slot_pos = nil
		if slot_system and slot_system.user_unit_slot_position then
			local ok, pos = pcall(slot_system.user_unit_slot_position, slot_system, unit)
			if ok and pos then
				slot_pos = pos
			end
		end
		if not slot_pos and slot and slot.absolute_position and slot.absolute_position.unbox then
			slot_pos = slot.absolute_position:unbox()
		end
		if slot_pos and slot then
			slot_pos = slot_draw:_smooth_position(slot_draw.state.position_cache.slots, slot, slot_pos, alpha)
		end
		if not slot_pos then
			slot_pos = self:nearest_slot_position(slot_draw, user_pos)
		end

		local slot_type = resolve_slot_type(slot, extension and extension.use_slot_type or nil)
		local slot_settings = constants.SlotTypeSettings[slot_type] or constants.SlotTypeSettings.normal
		local state_rgb = slot and slot_draw.slot_logic:slot_state_rgb(slot, slot_pos or user_pos, settings, unit_extension_data)
			or constants.COLORS.moving
		if type(state_rgb) ~= "table" then
			state_rgb = constants.COLORS.moving
		end
		local is_waiting = extension and extension.wait_slot ~= nil
		local ring_scale = is_waiting and (settings.queue_unit_radius_scale or settings.user_slot_radius_scale)
			or settings.user_slot_radius_scale
		local ring_radius = (slot_settings and slot_settings.radius or 0.5) * ring_scale
		local queue_rgb = type(settings.queue_unit_color) == "table" and settings.queue_unit_color or constants.COLORS.queue
		local ring_rgb = is_waiting and queue_rgb or state_rgb
		if type(ring_rgb) ~= "table" then
			ring_rgb = constants.COLORS.queue
		end
		local slot_user = slot and slot_draw.slot_logic and slot_draw.slot_logic._find_slot_user
			and slot_draw.slot_logic:_find_slot_user(slot, unit_extension_data)
		if slot and slot_user == unit and slot_draw.slot_logic:slot_occupied(slot, slot_pos or user_pos, settings, unit_extension_data) then
			goto continue
		end

		if settings.debug_draw_distance and settings.debug_draw_distance > 0 and player_pos then
			local dist_sq = util:distance_squared(player_pos, user_pos)
			if dist_sq and dist_sq > (settings.debug_draw_distance * settings.debug_draw_distance) then
				goto continue
			end
		end

		local draw_ring_for_unit = is_waiting and settings.draw_queue_unit_rings or settings.draw_user_slot_rings
		if draw_ring_for_unit and line_object then
			local ring_color = line_draw:to_color(ring_rgb, 200)
			local user_height = settings.enemy_ring_height or settings.slot_height or 0
			local step = user_height > 0 and user_height / 2 or 0.5
			line_draw:draw_cylinder(
				line_object,
				user_pos,
				ring_radius,
				user_height,
				step,
				settings.slot_segments,
				ring_color,
				settings.slot_height_rings,
				settings.slot_vertical_lines
			)
		end

		local draw_line_for_unit = is_waiting and settings.draw_queue_unit_lines or settings.draw_slot_user_lines
		if draw_line_for_unit and line_object and slot_pos then
			local line_color = line_draw:to_color(ring_rgb, 180)
			line_draw:draw_thick_line(line_object, line_color, slot_pos, user_pos, line_thickness)
		end

		local draw_label_for_unit = settings.label_enemy_units or (is_waiting and settings.queue_label_enabled)
		if label_entries and settings.text_mode ~= "off" and draw_label_for_unit then
			local dist_val = safe_distance(util, player_pos, user_pos)
			local label_max = settings.label_draw_distance
			local allow_label = true
			if label_max and label_max > 0 and dist_val and dist_val > label_max then
				allow_label = false
			end
			if allow_label then
				local status = extension and extension.wait_slot and "waiting" or "moving"
				if slot and slot_draw.slot_logic:slot_occupied(slot, slot_pos or user_pos, settings, unit_extension_data) then
					status = "occupied"
				end
				local label_text = string.format(
					"%s\n%s -> Slot %d (%s)",
					slot_draw.slot_logic:unit_label(unit),
					status,
					slot and slot.index or 0,
					slot_type or "?"
				)
				label_text = slot_draw:_append_distance(label_text, dist_val, settings.text_mode)
				local key = string.format("slot_user_fallback_%s", stable_unit_key(unit, util))
				local index = #label_entries + 1
				local entry = label_entries[index]
				if not entry then
					entry = {}
					label_entries[index] = entry
				end
				entry.key = key
				entry.position = user_pos
				entry.text = label_text
				local queue_label_rgb = type(settings.queue_label_color) == "table" and settings.queue_label_color
					or constants.COLORS.queue
				entry.color = is_waiting and queue_label_rgb or state_rgb
				entry.distance = dist_val or 0
				entry.priority = 25
			end
		end

		if drawn_user_units then
			drawn_user_units[unit] = true
		end

		::continue::
	end
end

return SlotDrawUsers
