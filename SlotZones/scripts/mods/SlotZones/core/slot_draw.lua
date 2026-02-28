--[[
    File: slot_draw.lua
    Description: Main slot/queue debug draw pipeline and frame orchestration.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local SlotDraw = {}
SlotDraw.__index = SlotDraw
local function new_weak_key_table()
	return setmetatable({}, { __mode = "k" })
end
local function clear_table(table_ref)
	if not table_ref then
		return
	end
	for key in pairs(table_ref) do
		table_ref[key] = nil
	end
end
local function clear_array(table_ref, from_index)
	if not table_ref then
		return
	end
	local start_index = from_index or 1
	for i = #table_ref, start_index, -1 do
		table_ref[i] = nil
	end
end
local function stable_unit_key(util, unit)
	if util and util.unit_key then
		local ok_key, key = pcall(util.unit_key, util, unit)
		if ok_key and key then
			return key
		end
	end
	if unit == nil then
		return "none"
	end
	return tostring(unit)
end
function SlotDraw.new(mod, constants, util, line_draw, slot_logic, markers, slot_draw_users, label_fallback)
	local position_cache = {
		targets = new_weak_key_table(),
		slots = new_weak_key_table(),
		queues = new_weak_key_table(),
		ghosts = new_weak_key_table(),
		units = new_weak_key_table(),
	}
	return setmetatable({
		mod = mod,
		constants = constants,
		util = util,
		line_draw = line_draw,
		slot_logic = slot_logic,
		markers = markers,
		slot_draw_users = slot_draw_users and slot_draw_users.new and slot_draw_users.new() or slot_draw_users,
		label_fallback = label_fallback,
		state = {
			last_label_refresh_t = nil,
			last_label_refresh_position = nil,
			logged_missing_system = false,
			logged_no_targets = false,
			logged_no_slots = false,
			slot_offsets = new_weak_key_table(),
			slot_local_offsets = new_weak_key_table(),
			slot_raw_positions = new_weak_key_table(),
			position_cache = position_cache,
			estimated_slots = new_weak_key_table(),
			player_key = {},
			drawn_user_units = {},
			drawn_queue_units = {},
			label_entries = {},
			candidates = {},
			results = {},
		},
	}, SlotDraw)
end
function SlotDraw:log_once(flag, message)
	if self.state[flag] then
		return
	end
	self.state[flag] = true
	if self.mod and self.mod.echo then
		self.mod:echo(message)
	end
end
function SlotDraw:reset_refresh()
	self.state.last_label_refresh_t = nil
	self.state.last_label_refresh_position = nil
	self.state.logged_missing_system = false
	self.state.logged_no_targets = false
	self.state.logged_no_slots = false
	self.state.force_label_refresh_until = nil
end
function SlotDraw:reset_state()
	self.markers:clear()
	self.line_draw:destroy()
	if self.label_fallback then
		self.label_fallback:clear()
	end
	self:reset_refresh()
	self.state.slot_offsets = new_weak_key_table()
	self.state.slot_local_offsets = new_weak_key_table()
	self.state.slot_raw_positions = new_weak_key_table()
	self.state.position_cache = {
		targets = new_weak_key_table(),
		slots = new_weak_key_table(),
		queues = new_weak_key_table(),
		ghosts = new_weak_key_table(),
		units = new_weak_key_table(),
	}
	self.state.estimated_slots = new_weak_key_table()
	clear_table(self.state.drawn_user_units)
	clear_table(self.state.drawn_queue_units)
	clear_array(self.state.label_entries)
	clear_array(self.state.candidates)
	clear_array(self.state.results)
	if self.slot_draw_users and self.slot_draw_users.reset then
		self.slot_draw_users:reset()
	end
end
function SlotDraw:force_label_refresh(duration, now_t)
	local now = tonumber(now_t) or 0
	local span = tonumber(duration) or 0
	if span < 0 then
		span = 0
	end
	self.state.force_label_refresh_until = now + span
	self.state.last_label_refresh_t = nil
	self.state.last_label_refresh_position = nil
end
function SlotDraw:_label_slot_type_enabled(slot_type, settings)
	if slot_type == "normal" then
		return settings.label_slots_normal ~= false
	end
	if slot_type == "medium" then
		return settings.label_slots_medium ~= false
	end
	if slot_type == "large" then
		return settings.label_slots_large ~= false
	end
	return true
end
function SlotDraw:_slot_label_size(slot_type, settings)
	local size = 0
	if slot_type == "normal" then
		size = settings.label_slot_normal_size or 0
	elseif slot_type == "medium" then
		size = settings.label_slot_medium_size or 0
	elseif slot_type == "large" then
		size = settings.label_slot_large_size or 0
	end
	if size and size > 0 then
		return size
	end
	return settings.text_size
end
function SlotDraw:_slot_label_height(slot_type, settings)
	local height = 0
	if slot_type == "normal" then
		height = settings.label_slot_normal_height or 0
	elseif slot_type == "medium" then
		height = settings.label_slot_medium_height or 0
	elseif slot_type == "large" then
		height = settings.label_slot_large_height or 0
	end
	if height and height > 0 then
		return height
	end
	return settings.text_height
end
function SlotDraw:_append_distance(label_text, dist_val, mode)
	if not label_text then
		return label_text
	end
	if type(dist_val) ~= "number" or dist_val ~= dist_val then
		return label_text
	end
	if mode == "distances" then
		return string.format("%s\n%.1fm", label_text, dist_val)
	end
	if mode == "both" then
		return string.format("%s | %.1fm", label_text, dist_val)
	end
	return label_text
end
function SlotDraw:_lerp_position(a, b, t)
	if not a or not b then
		return a or b
	end
	local refs = self.line_draw.runtime.resolve()
	if refs.Vector3 and refs.Vector3.lerp then
		return refs.Vector3.lerp(a, b, t)
	end
	return a + (b - a) * t
end
function SlotDraw:_draw_label_line(line_object, center, radius, label_height, rgb, thickness, player_pos)
	if not line_object or not center or not label_height then
		return
	end
	local refs = self.line_draw.runtime.resolve()
	if not refs.Vector3 then
		return
	end
	local start_pos = center
	if radius and radius > 0 and player_pos then
		local dir = player_pos - center
		if dir and dir.x and dir.y then
			dir.z = 0
			local len = refs.Vector3.length(dir)
			if len and len > 0.001 then
				local norm = refs.Vector3.normalize(dir)
				start_pos = center + norm * radius
			end
		end
	end
	local end_pos = center + refs.Vector3(0, 0, label_height)
	local alpha = 160
	if thickness and thickness > 0 then
		alpha = math.min(255, math.floor(alpha + thickness * 240 + 0.5))
	end
	local color = self.line_draw:to_color(rgb or self.constants.COLORS.origin, alpha)
	if refs.LineObject and refs.LineObject.add_line then
		pcall(refs.LineObject.add_line, line_object, color, start_pos, end_pos)
	else
		self.line_draw:draw_thick_line(line_object, color, start_pos, end_pos, 0)
	end
end
function SlotDraw:_smooth_position(cache, key, raw_pos, alpha)
	local entry = cache[key]
	if not raw_pos or key == nil then
		if not entry then
			return raw_pos
		end
		local refs = self.line_draw.runtime.resolve()
		local v3box = refs.Vector3Box
		if entry.box and v3box and v3box.unbox then
			local ok, vec = pcall(v3box.unbox, entry.box)
			if ok and vec then
				return vec
			end
		end
		return entry.vec or raw_pos
	end
	local ok_pos, rx, ry, rz = pcall(function()
		return raw_pos.x, raw_pos.y, raw_pos.z
	end)
	if not ok_pos or rx == nil or ry == nil or rz == nil then
		return nil
	end
	if rx ~= rx or ry ~= ry or rz ~= rz or rx <= -math.huge or ry <= -math.huge or rz <= -math.huge or rx >= math.huge or ry >= math.huge or rz >= math.huge then
		return nil
	end
	if not entry then
		local refs = self.line_draw.runtime.resolve()
		local v3box = refs.Vector3Box
		local box = nil
		if v3box then
			local ok, new_box = pcall(v3box, rx, ry, rz)
			if ok and new_box then
				box = new_box
			end
		end
		local vec = refs.Vector3 and refs.Vector3(rx, ry, rz) or nil
		cache[key] = { x = rx, y = ry, z = rz, box = box, vec = vec }
		if box and v3box and v3box.unbox then
			local ok, boxed_vec = pcall(v3box.unbox, box)
			if ok and boxed_vec then
				return boxed_vec
			end
		end
		return vec or raw_pos
	end
	local dx_raw = rx - entry.x
	local dy_raw = ry - entry.y
	local dz_raw = rz - entry.z
	local jitter_epsilon_sq = 0.0004
	local delta_sq = dx_raw * dx_raw + dy_raw * dy_raw + dz_raw * dz_raw
	if delta_sq <= jitter_epsilon_sq then
		local refs = self.line_draw.runtime.resolve()
		local v3box = refs.Vector3Box
		if entry.box and v3box and v3box.unbox then
			local ok_unbox, boxed_vec = pcall(v3box.unbox, entry.box)
			if ok_unbox and boxed_vec then
				return boxed_vec
			end
		end
		return entry.vec or raw_pos
	end
	if alpha >= 1 then
		entry.x = rx
		entry.y = ry
		entry.z = rz
		local refs = self.line_draw.runtime.resolve()
		local v3box = refs.Vector3Box
		if entry.box and v3box and v3box.store and v3box.unbox then
			local ok = pcall(v3box.store, entry.box, rx, ry, rz)
			if not ok then
				local vec = refs.Vector3 and refs.Vector3(rx, ry, rz) or nil
				if vec then
					pcall(v3box.store, entry.box, vec)
				end
			end
			local ok_unbox, boxed_vec = pcall(v3box.unbox, entry.box)
			if ok_unbox and boxed_vec then
				return boxed_vec
			end
		end
		local vec = entry.vec
		if vec and vec.x ~= nil then
			vec.x = rx
			vec.y = ry
			vec.z = rz
			return vec
		end
		return raw_pos
	end
	local sx = entry.x + (rx - entry.x) * alpha
	local sy = entry.y + (ry - entry.y) * alpha
	local sz = entry.z + (rz - entry.z) * alpha
	entry.x = sx
	entry.y = sy
	entry.z = sz
	local refs = self.line_draw.runtime.resolve()
	local v3box = refs.Vector3Box
	if entry.box and v3box and v3box.store and v3box.unbox then
		local ok = pcall(v3box.store, entry.box, sx, sy, sz)
		if not ok then
			local vec = refs.Vector3 and refs.Vector3(sx, sy, sz) or nil
			if vec then
				pcall(v3box.store, entry.box, vec)
			end
		end
		local ok_unbox, boxed_vec = pcall(v3box.unbox, entry.box)
		if ok_unbox and boxed_vec then
			return boxed_vec
		end
	end
	local vec = entry.vec
	if vec and vec.x ~= nil then
		vec.x = sx
		vec.y = sy
		vec.z = sz
		return vec
	end
	if refs.Vector3 then
		vec = refs.Vector3(sx, sy, sz)
		entry.vec = vec
		return vec
	end
	return { x = sx, y = sy, z = sz }
end
function SlotDraw:_estimated_cache(target_unit, slot_type)
	local by_unit = self.state.estimated_slots[target_unit]
	if not by_unit then
		by_unit = {}
		self.state.estimated_slots[target_unit] = by_unit
	end
	local by_type = by_unit[slot_type]
	if not by_type then
		by_type = {}
		by_unit[slot_type] = by_type
	end
	return by_type
end
function SlotDraw:collect_target_units(slot_system, unit_extension_data, settings, player_pos, draw_distance_override)
	local candidates = self.state.candidates
	clear_array(candidates)
	local draw_distance = draw_distance_override or settings.debug_draw_distance
	local max_dist_sq = draw_distance > 0 and draw_distance * draw_distance or nil
	local target_mode = settings.target_mode
	local party_mode = target_mode == "self" or target_mode == "party"
	local max_targets = settings.debug_max_targets
	local local_player = Managers.player and Managers.player:local_player(1)
	local has_slot_system = unit_extension_data ~= nil
	local candidate_count = 0
	local function add_candidate(unit)
		if not unit then
			return
		end
		local extension = self.slot_logic:get_slot_extension(unit, unit_extension_data)
		if has_slot_system and extension and not extension.all_slots and not party_mode then
			return
		end
		if has_slot_system and not extension and target_mode == "all" then
			return
		end
		local unit_pos = self.util:get_unit_position(unit, extension)
		if not unit_pos then
			return
		end
		local dist_sq = player_pos and unit_pos and self.util:distance_squared(player_pos, unit_pos) or nil
		if max_dist_sq and dist_sq and dist_sq > max_dist_sq then
			return
		end
		candidate_count = candidate_count + 1
		local entry = candidates[candidate_count]
		if not entry then
			entry = {}
			candidates[candidate_count] = entry
		end
		entry.unit = unit
		entry.dist_sq = dist_sq or 0
	end
	if target_mode == "self" or target_mode == "party" or not slot_system then
		local player_manager = Managers.player
		if player_manager and player_manager.players then
			local players = player_manager:players()
			for _, player in pairs(players) do
				local unit = player and player.player_unit
				if target_mode == "self" and local_player and player ~= local_player then
					unit = nil
				end
				if unit then
					add_candidate(unit)
				end
			end
		end
		if candidate_count == 0 then
			local spawn_manager = Managers.state and Managers.state.player_unit_spawn
			if spawn_manager and spawn_manager.alive_players then
				local ok, alive_players = pcall(spawn_manager.alive_players, spawn_manager)
				if ok and alive_players then
					for i = 1, #alive_players do
						add_candidate(alive_players[i])
					end
				end
			end
		end
		if #candidates == 0 then
			local fallback_unit = local_player and local_player.player_unit
			if fallback_unit then
				add_candidate(fallback_unit)
			end
		end
	elseif slot_system then
		local targets = slot_system._target_units or {}
		for i = 1, #targets do
			add_candidate(targets[i])
		end
	end
	clear_array(candidates, candidate_count + 1)
	table.sort(candidates, function(a, b)
		return a.dist_sq < b.dist_sq
	end)
	local results = self.state.results
	clear_array(results)
	local limit = math.min(candidate_count, max_targets > 0 and max_targets or candidate_count)
	for i = 1, limit do
		results[i] = candidates[i].unit
	end
	clear_array(results, limit + 1)
	if #results == 0 then
		local fallback_unit = local_player and local_player.player_unit
		if fallback_unit then
			results[1] = fallback_unit
		end
	end
	return results
end
function SlotDraw:draw_estimated_slots(line_object, target_unit, target_pos, target_rot, settings, player_pos, label_entries, alpha)
	local target_key = stable_unit_key(self.util, target_unit)
	if settings.slot_filter ~= "all" then
		return 0
	end
	local refs = self.line_draw.runtime.resolve()
	if not refs.Vector3 then
		return 0
	end
	local quat = refs.Quaternion
	local can_rotate = quat and quat.rotate and target_rot
	local drawn_count = 0
	for _, slot_type in ipairs(self.constants.SLOT_TYPES) do
		local slot_settings = self.constants.SlotTypeSettings[slot_type]
		if slot_settings then
			local slot_cache = self:_estimated_cache(target_unit, slot_type)
			local slot_colors = settings.slot_type_colors and settings.slot_type_colors[slot_type]
			local free_rgb = slot_colors and slot_colors.free or self.constants.COLORS.free
			local base_color = self.line_draw:to_color(free_rgb, 200)
			local count = slot_settings.count or 0
			local distance_value = slot_settings.distance or 0
			local slot_radius = (slot_settings.radius or 0.5) * settings.slot_radius_scale
			for i = 1, count do
				local angle = (i - 1) / math.max(1, count) * math.pi * 2
				local local_offset = refs.Vector3(math.cos(angle) * distance_value, math.sin(angle) * distance_value, 0)
				local offset = local_offset
				if can_rotate then
					offset = quat.rotate(target_rot, local_offset)
				end
				local slot_pos = target_pos + offset
				local smooth_pos = self:_smooth_position(slot_cache, i, slot_pos, alpha)
				if self.slot_draw_users and self.slot_draw_users.track_slot_position then
					self.slot_draw_users:track_slot_position(smooth_pos)
				end
				if settings.draw_slots and line_object then
					local step = settings.slot_height > 0 and settings.slot_height / 2 or 0.5
					self.line_draw:draw_cylinder(
						line_object,
						smooth_pos,
						slot_radius,
						settings.slot_height,
						step,
						settings.slot_segments,
						base_color,
						settings.slot_height_rings,
						settings.slot_vertical_lines
					)
					drawn_count = drawn_count + 1
				end
				if label_entries and settings.text_mode ~= "off" then
					local dist_val = player_pos and self.util:distance(player_pos, smooth_pos) or nil
					if type(dist_val) ~= "number" or dist_val ~= dist_val then
						dist_val = nil
					end
					local label_max = settings.label_draw_distance
					local allow_label = true
					if label_max and label_max > 0 and dist_val and dist_val > label_max then
						allow_label = false
					end
					if allow_label and self:_label_slot_type_enabled(slot_type, settings) then
						local label_text = string.format("Slot %d (%s)\nestimated", i, slot_type)
						local key = string.format("%s_est_%s_%s", target_key, slot_type, i)
						local label_size = self:_slot_label_size(slot_type, settings)
						local label_height = self:_slot_label_height(slot_type, settings)
						local index = #label_entries + 1
						local entry = label_entries[index]
						if not entry then
							entry = {}
							label_entries[index] = entry
						end
						entry.key = key
						entry.position = smooth_pos
						entry.text = label_text
						entry.color = free_rgb
						entry.distance = dist_val or 0
						entry.text_size = label_size
						entry.height = label_height
						if settings.draw_label_lines and line_object then
							self:_draw_label_line(
								line_object,
								smooth_pos,
								slot_radius,
								label_height,
								free_rgb,
								settings.label_line_thickness,
								player_pos
							)
						end
					end
				end
			end
		end
	end
	return drawn_count
end
function SlotDraw:draw_target_slots(line_object, target_unit, target_extension, settings, player_pos, unit_extension_data, label_entries, alpha)
	local refs = self.line_draw.runtime.resolve()
	local raw_target_pos = self.util:get_unit_position(target_unit, target_extension)
	if not raw_target_pos then
		return 0
	end
	local target_rot = self.util:get_unit_rotation(target_unit, target_extension)
	local quat = refs.Quaternion
	local can_rotate = quat and quat.rotate and quat.inverse and target_rot
	local target_pos = self:_smooth_position(self.state.position_cache.targets, target_unit, raw_target_pos, alpha)
	if not target_pos then
		return 0
	end
	local drawn_user_units = self.state.drawn_user_units
	local drawn_queue_units = self.state.drawn_queue_units
	local target_key = stable_unit_key(self.util, target_unit)
	local slots_drawn = 0
	local saw_slot_data = false
	if settings.draw_origin and line_object then
		local origin_color = self.line_draw:to_color(self.constants.COLORS.origin, 200)
		self.line_draw:draw_point(line_object, target_pos, origin_color)
	end
	if label_entries and settings.text_mode ~= "off" and settings.label_show_target ~= false then
		local dist_val = player_pos and self.util:distance(player_pos, target_pos) or nil
		if type(dist_val) ~= "number" or dist_val ~= dist_val then
			dist_val = nil
		end
		local label_max = settings.label_draw_distance
		local allow_label = true
		if label_max and label_max > 0 and dist_val and dist_val > label_max then
			allow_label = false
		end
		if allow_label then
			local label_text = string.format("Target: %s", self.slot_logic:unit_label(target_unit))
			local key = string.format("target_%s", target_key)
			local index = #label_entries + 1
			local entry = label_entries[index]
			if not entry then
				entry = {}
				label_entries[index] = entry
			end
			entry.key = key
			entry.position = target_pos
			entry.text = label_text
			entry.color = self.constants.COLORS.origin
			entry.distance = dist_val or 0
			if settings.draw_label_lines and line_object then
				self:_draw_label_line(
					line_object,
					target_pos,
					0,
					settings.text_height,
					self.constants.COLORS.origin,
					settings.label_line_thickness,
					player_pos
				)
			end
		end
	end
	if not target_extension or not target_extension.all_slots then
		if settings.slot_filter == "all" then
			return self:draw_estimated_slots(line_object, target_unit, target_pos, target_rot, settings, player_pos, label_entries, alpha)
		end
		return 0
	end
	for _, slot_type in ipairs(self.constants.SLOT_TYPES) do
		local slot_data = target_extension.all_slots[slot_type]
		if slot_data then
			saw_slot_data = true
			local slots = slot_data.slots
			local total_slots_count = slot_data.total_slots_count or #slots
			local slot_raw_positions = self.state.slot_raw_positions
			local slot_offsets = self.state.slot_offsets
			local slot_local_offsets = self.state.slot_local_offsets
			local offset_eps_sq = 0.01 * 0.01
			for i = 1, total_slots_count do
				local slot = slots[i]
				if slot then
					local slot_settings = self.constants.SlotTypeSettings[slot.type] or self.constants.SlotTypeSettings.normal
					local slot_distance = (slot_settings and slot_settings.distance) or 0
					local slot_count = (slot_settings and slot_settings.count) or total_slots_count
					local slot_index = slot.index or i
					local estimated_pos = nil
					local estimated_local = nil
					if refs.Vector3 and slot_distance > 0 and target_pos then
						local angle = (slot_index - 1) / math.max(1, slot_count) * math.pi * 2
						estimated_local = refs.Vector3(math.cos(angle) * slot_distance, math.sin(angle) * slot_distance, 0)
						if can_rotate then
							estimated_pos = target_pos + quat.rotate(target_rot, estimated_local)
						else
							estimated_pos = target_pos + estimated_local
						end
					end
					local raw_slot_pos = slot.absolute_position and slot.absolute_position:unbox() or nil
					if raw_slot_pos and raw_target_pos then
						if raw_slot_pos.x == 0 and raw_slot_pos.y == 0 and raw_slot_pos.z == 0 then
							if raw_target_pos.x ~= 0 or raw_target_pos.y ~= 0 or raw_target_pos.z ~= 0 then
								raw_slot_pos = nil
							end
						end
					end
					local last_raw = slot_raw_positions[slot]
					local cached_raw = raw_slot_pos or last_raw
					if raw_slot_pos then
						slot_raw_positions[slot] = raw_slot_pos
					end
					local slot_offset = slot_offsets[slot]
					local slot_local_offset = slot_local_offsets[slot]
					if raw_slot_pos and raw_target_pos then
						local changed = not last_raw
						if last_raw then
							local dist_sq = self.util:distance_squared(raw_slot_pos, last_raw) or 0
							changed = dist_sq > offset_eps_sq
						end
						if changed or not slot_offset then
							slot_offset = raw_slot_pos - raw_target_pos
							slot_offsets[slot] = slot_offset
						end
						if can_rotate then
							local delta = raw_slot_pos - raw_target_pos
							local ok_inv, inv = pcall(quat.inverse, target_rot)
							if ok_inv and inv then
								local ok_local, local_offset = pcall(quat.rotate, inv, delta)
								if ok_local and local_offset then
									slot_local_offset = local_offset
									slot_local_offsets[slot] = slot_local_offset
								end
							end
						end
					end
					if not slot_offset and estimated_pos and target_pos then
						slot_offset = estimated_pos - target_pos
						slot_offsets[slot] = slot_offset
					end
					if not slot_local_offset and estimated_local then
						slot_local_offset = estimated_local
						slot_local_offsets[slot] = slot_local_offset
					end
					local desired_slot_pos = nil
					if slot_local_offset and can_rotate and target_pos then
						desired_slot_pos = target_pos + quat.rotate(target_rot, slot_local_offset)
					elseif slot_offset and target_pos then
						desired_slot_pos = target_pos + slot_offset
					elseif cached_raw then
						desired_slot_pos = cached_raw
					elseif estimated_pos then
						desired_slot_pos = estimated_pos
					end
					if cached_raw and desired_slot_pos then
						desired_slot_pos = self:_lerp_position(desired_slot_pos, cached_raw, 0.25)
					end
					local slot_pos = desired_slot_pos and self:_smooth_position(self.state.position_cache.slots, slot, desired_slot_pos, alpha) or nil
					local state_slot_pos = cached_raw or desired_slot_pos or slot_pos
					if slot_pos and self.slot_draw_users and self.slot_draw_users.track_slot_position then
						self.slot_draw_users:track_slot_position(slot_pos)
					end
					if slot_pos and state_slot_pos then
						local slot_visible = self.slot_logic:slot_passes_filter(
							slot,
							state_slot_pos,
							settings.slot_filter,
							settings,
							unit_extension_data
						)
						local state_rgb = self.slot_logic:slot_state_rgb(slot, state_slot_pos, settings, unit_extension_data)
						local state_color = self.line_draw:to_color(state_rgb, 220)
						local slot_radius = (slot_settings and slot_settings.radius or 0.5) * settings.slot_radius_scale
						local slot_height = settings.slot_height
						if slot_visible then
							if settings.draw_slots and line_object then
								local step = slot_height > 0 and slot_height / 2 or 0.5
								self.line_draw:draw_cylinder(
									line_object,
									slot_pos,
									slot_radius,
									slot_height,
									step,
									settings.slot_segments,
									state_color,
									settings.slot_height_rings,
									settings.slot_vertical_lines
								)
							end
							slots_drawn = slots_drawn + 1
							if settings.draw_ghost_slots and slot.ghost_position and line_object then
								local raw_ghost_pos = slot.ghost_position:unbox()
								local ghost_pos = raw_ghost_pos
									and self:_smooth_position(self.state.position_cache.ghosts, slot, raw_ghost_pos, alpha)
									or nil
								if ghost_pos and (ghost_pos.x ~= 0 or ghost_pos.y ~= 0 or ghost_pos.z ~= 0) then
									local ghost_color = self.line_draw:to_color(self.constants.COLORS.ghost, 200)
									self.line_draw:draw_point(line_object, ghost_pos, ghost_color)
								end
							end
						end
						if self.slot_draw_users then
							self.slot_draw_users:draw_slot_users(
								self,
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
								slot.type or slot_type,
								target_unit,
								slot_visible,
								drawn_user_units,
								drawn_queue_units
							)
						end
					end
				end
			end
		end
	end
	if saw_slot_data and slots_drawn == 0 and settings.slot_filter == "all" then
		slots_drawn = slots_drawn + self:draw_estimated_slots(line_object, target_unit, target_pos, target_rot, settings, player_pos, label_entries, alpha)
	end
	return slots_drawn
end
function SlotDraw:draw_debug(world, dt, t, settings)
	local slot_system = Managers.state and Managers.state.extension and Managers.state.extension:system("slot_system")
	local unit_extension_data = slot_system and slot_system._unit_extension_data or nil
	if not unit_extension_data then
		self:log_once("logged_missing_system", "[SlotZones] slot_system unavailable on client; falling back to unit extensions.")
	end
	local player_unit = self.util:get_local_player_unit()
	local raw_player_pos = player_unit and self.util:get_unit_position(player_unit) or nil
	local update_interval = settings.debug_update_interval
	local alpha = 1
	if update_interval > 0 then
		local delta = tonumber(dt) or 0
		if delta < 0 then
			delta = 0
		end
		if delta > 0 then
			alpha = math.min(delta / update_interval, 1)
		end
	end
	local player_key = player_unit or self.state.player_key
	local player_pos =
		raw_player_pos and self:_smooth_position(self.state.position_cache.units, player_key, raw_player_pos, alpha) or nil
	if not player_pos then
		player_pos = raw_player_pos
	end
	clear_table(self.state.drawn_user_units)
	clear_table(self.state.drawn_queue_units)
	if self.slot_draw_users and self.slot_draw_users.reset then
		self.slot_draw_users:reset()
	end
	local label_mode = settings.text_mode
	local label_enabled = label_mode and label_mode ~= "off"
	if not label_enabled then
		if settings.label_slots_normal
			or settings.label_slots_medium
			or settings.label_slots_large
			or settings.label_slot_users
			or settings.label_enemy_units
			or settings.label_show_queue
			or settings.label_show_target
			or settings.queue_label_enabled then
			label_enabled = true
			label_mode = "labels"
		end
	end
	local label_interval = settings.label_refresh_interval
	if label_enabled and self.state.last_label_refresh_t and t < self.state.last_label_refresh_t then
		self:reset_refresh()
	end
	local label_due = label_enabled and (
		label_interval <= 0
		or self.state.last_label_refresh_t == nil
		or (t - self.state.last_label_refresh_t) >= label_interval
	)
	if label_enabled and self.state.force_label_refresh_until and t <= self.state.force_label_refresh_until then
		label_due = true
	end
	if label_enabled and settings.label_move_threshold > 0 and player_pos then
		local last_pos = self.state.last_label_refresh_position
		if not last_pos then
			label_due = true
		else
			local move_threshold_sq = settings.label_move_threshold * settings.label_move_threshold
			local moved_sq = self.util:distance_squared(player_pos, last_pos) or 0
			if moved_sq >= move_threshold_sq then
				label_due = true
			end
		end
	end
	if label_enabled and not label_due and self.markers and self.markers.entries and next(self.markers.entries) == nil then
		label_due = true
	end
	if label_enabled and not label_due and self.markers and self.markers.entries then
		local has_id = false
		for _, entry in pairs(self.markers.entries) do
			if entry and entry.id then
				has_id = true
			elseif entry and entry._pending and (not entry._pending_t or (t - entry._pending_t) > 0.5) then
				label_due = true
				break
			elseif entry and not entry._pending and not entry.id then
				label_due = true
				break
			end
		end
		if not label_due and not has_id then
			label_due = true
		end
	end
	if not settings.debug_enabled and not label_due then
		return
	end
	local draw_distance = settings.debug_draw_distance
	if label_enabled and settings.label_draw_distance > 0 and draw_distance > 0 then
		draw_distance = math.max(draw_distance, settings.label_draw_distance)
	end
	local line_object = nil
	if settings.debug_enabled then
		line_object = self.line_draw:ensure(world)
		if line_object then
			local ok = self.line_draw:reset(line_object)
			if not ok then
				self.line_draw:destroy()
				line_object = self.line_draw:ensure(world)
				if line_object then
					self.line_draw:reset(line_object)
				end
			end
		end
	else
		self.line_draw:clear(world)
	end
	local label_entries = nil
	if label_enabled then
		label_entries = self.state.label_entries
		clear_array(label_entries)
	end
	local targets = self:collect_target_units(slot_system, unit_extension_data, settings, raw_player_pos, draw_distance)
	if #targets == 0 then
		self:log_once("logged_no_targets", "[SlotZones] No slot targets found. Try Target mode = All or spawn enemies.")
		if settings.slot_filter == "all" and player_unit and (player_pos or raw_player_pos) then
			local fallback_pos = player_pos or raw_player_pos
			local fallback_rot = self.util:get_unit_rotation(player_unit)
			self:draw_estimated_slots(
				line_object,
				player_unit,
				fallback_pos,
				fallback_rot,
				settings,
				player_pos,
				label_entries,
				alpha
			)
		end
	end
	local total_slots_drawn = 0
	for _, target_unit in ipairs(targets) do
		local target_extension = self.slot_logic:get_slot_extension(target_unit, unit_extension_data)
		local ok_draw, drawn_or_error = pcall(self.draw_target_slots, self, line_object, target_unit, target_extension, settings, player_pos, unit_extension_data, label_entries, alpha)
		if ok_draw then
			total_slots_drawn = total_slots_drawn + (drawn_or_error or 0)
		end
	end
	if self.slot_draw_users then
		pcall(self.slot_draw_users.draw_fallback, self.slot_draw_users, self, line_object, slot_system, unit_extension_data, settings, player_pos, label_entries, alpha, self.state.drawn_user_units)
	end
	local origin_pos = player_pos or raw_player_pos
	if line_object and settings.draw_origin and origin_pos then
		local origin_color = self.line_draw:to_color(self.constants.COLORS.origin, 180)
		self.line_draw:draw_point(line_object, origin_pos, origin_color)
	end
	if #targets > 0 and total_slots_drawn == 0 then
		self:log_once("logged_no_slots", "[SlotZones] No slots drawn. Try Slot filter = All or spawn enemies.")
	end
	if line_object and settings.debug_enabled then
		self.line_draw:dispatch(world, line_object)
	end
	if label_entries then
		local markers_ready = self.markers and self.markers.is_ready and self.markers:is_ready() or false
		local fallback_enabled = false
		local fallback_entries = nil
		if #label_entries > 0 then
			if markers_ready then
				if self.markers and self.markers.reset_stale_pending then
					self.markers:reset_stale_pending(t, 0.5)
				end
				if label_due then
					local refreshed = self.markers:refresh(label_entries, settings, t)
					if refreshed then
						self.state.last_label_refresh_t = t
						self.state.last_label_refresh_position = player_pos
					end
				else
					self.markers:update_positions(label_entries)
				end
				local markers_visible = self.markers and self.markers.has_active_ids and self.markers:has_active_ids()
					or false
				fallback_enabled = not markers_visible
				fallback_entries = fallback_enabled and label_entries or nil
			else
				if label_due then
					self.state.last_label_refresh_t = t
					self.state.last_label_refresh_position = player_pos
				end
				fallback_enabled = true
				fallback_entries = label_entries
			end
		elseif label_due then
			self.markers:clear()
			self.state.last_label_refresh_t = t
			self.state.last_label_refresh_position = player_pos
		end
		if self.label_fallback then
			self.label_fallback:render(world, fallback_entries, settings, fallback_enabled, label_due)
		end
	end
end
return SlotDraw
