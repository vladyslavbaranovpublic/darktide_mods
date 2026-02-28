--[[
    File: markers.lua
    Description: World-marker lifecycle and label marker synchronization.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Markers = {}
Markers.__index = Markers

local function mark_entry_removed(entry)
	if entry then
		entry._removed = true
		entry._token = (entry._token or 0) + 1
		entry._pending = nil
		if entry._pending_remove_id and Managers and Managers.event then
			Managers.event:trigger("remove_world_marker", entry._pending_remove_id)
			entry._pending_remove_id = nil
		end
	end
end

local function add_world_marker_position_safe(table_ref, key, entry, template_name, position, data, on_assigned)
	if not Managers or not Managers.event then
		return
	end
	entry._removed = false
	entry._token = (entry._token or 0) + 1
	local token = entry._token
	entry._pending = true
	entry._pending_t = Managers.time and Managers.time:time("main") or os.clock()

	Managers.event:trigger("add_world_marker_position", template_name, position, function(marker_id)
		if entry._removed or table_ref[key] ~= entry or entry._token ~= token then
			Managers.event:trigger("remove_world_marker", marker_id)
			return
		end
		entry.id = marker_id
		entry._pending = nil
		entry._pending_t = nil
		if on_assigned then
			pcall(on_assigned, marker_id)
		end
	end, data)
end

local function ensure_marker_templates(world_markers, template)
	if type(world_markers) ~= "table" or not world_markers._marker_templates then
		return
	end
	if template then
		world_markers._marker_templates[template.name] = template
	end
end

local function prune_invalid_markers(world_markers)
	if type(world_markers) ~= "table" then
		return
	end
	local markers_by_type = world_markers._markers_by_type
	local markers_by_id = world_markers._markers_by_id
	if not markers_by_type or not markers_by_id then
		return
	end
	for _, markers in pairs(markers_by_type) do
		for i = #markers, 1, -1 do
			local marker = markers[i]
			if not marker or not marker.widget then
				if marker and marker.id then
					markers_by_id[marker.id] = nil
				end
				table.remove(markers, i)
			end
		end
	end
end

local function is_entry_better(a, b)
	if not a then
		return false
	end
	if not b then
		return true
	end
	local pa = a.priority or 0
	local pb = b.priority or 0
	if pa ~= pb then
		return pa > pb
	end
	local da = a.distance or math.huge
	local db = b.distance or math.huge
	if da ~= db then
		return da < db
	end
	local ka = tostring(a.key or "")
	local kb = tostring(b.key or "")
	if ka ~= kb then
		return ka < kb
	end
	return false
end

local function recompute_worst(buffer, count)
	if count <= 0 then
		return 0
	end
	local worst_idx = 1
	for i = 2, count do
		if is_entry_better(buffer[worst_idx], buffer[i]) then
			worst_idx = i
		end
	end
	return worst_idx
end

local function select_top_entries(source, cap, out)
	if not source or cap <= 0 then
		for i = #out, 1, -1 do
			out[i] = nil
		end
		return 0
	end
	local count = 0
	local worst_idx = 0
	for i = 1, #source do
		local candidate = source[i]
		if candidate and candidate.key and candidate.position then
			if count < cap then
				count = count + 1
				out[count] = candidate
				worst_idx = recompute_worst(out, count)
			elseif worst_idx > 0 and is_entry_better(candidate, out[worst_idx]) then
				out[worst_idx] = candidate
				worst_idx = recompute_worst(out, count)
			end
		end
	end
	for i = #out, count + 1, -1 do
		out[i] = nil
	end
	if count > 1 then
		table.sort(out, is_entry_better)
	end
	return count
end

function Markers.new(mod, template)
	return setmetatable({
		mod = mod,
		template = template,
		entries = {},
		pending_cleanup = false,
		pending_remove_ids = {},
		generation = 0,
		world_markers = nil,
		_hooks_registered = false,
		_selected_entries = {},
	}, Markers)
end

function Markers:_ensure_world_markers()
	if self.world_markers then
		if type(self.world_markers) == "table"
			and self.world_markers._markers_by_id
			and self.world_markers._marker_templates then
			return self.world_markers
		end
		self.world_markers = nil
	end
	local ui_manager = Managers and Managers.ui
	if not ui_manager or not ui_manager.get_hud then
		return nil
	end
	local hud = ui_manager:get_hud()
	if not hud or not hud.element then
		return nil
	end
	local element = hud:element("HudElementWorldMarkers")
	if not element then
		return nil
	end
	self.world_markers = element
	ensure_marker_templates(element, self.template)
	return element
end

function Markers:register_hooks()
	if self._hooks_registered then
		return
	end
	local template = self.template
	local markers = self
	local class_ref = rawget(_G, "CLASS")
	local class_name = class_ref and class_ref.HudElementWorldMarkers or nil
	if not class_name then
		return
	end
	self._hooks_registered = true
	self.mod:hook_safe(class_name, "init", function(self)
		markers.world_markers = self
		ensure_marker_templates(self, template)
	end)
	self.mod:hook(class_name, "update", function(func, self, dt, t, ui_renderer, render_settings, input_service)
		markers.world_markers = self
		ensure_marker_templates(self, template)
		prune_invalid_markers(self)
		return func(self, dt, t, ui_renderer, render_settings, input_service)
	end)
end

function Markers:_set_marker_position(marker_entry, position)
	if not marker_entry or not marker_entry.id or not position then
		return false
	end
	local world_markers = self:_ensure_world_markers() or self.world_markers
	if not world_markers then
		return false
	end
	local by_id = world_markers._markers_by_id
	local marker = by_id and by_id[marker_entry.id]
	if not marker or not marker.world_position then
		return false
	end
	if marker.world_position.store then
		local ok = pcall(marker.world_position.store, marker.world_position, position)
		return ok and true or false
	end
	if Vector3Box and Vector3Box.store then
		local ok = pcall(Vector3Box.store, marker.world_position, position)
		return ok and true or false
	end
	return false
end

function Markers:clear()
	local has_events = Managers and Managers.event
	for key, entry in pairs(self.entries) do
		mark_entry_removed(entry)
		if entry.id then
			if has_events then
				Managers.event:trigger("remove_world_marker", entry.id)
			else
				self.pending_remove_ids[#self.pending_remove_ids + 1] = entry.id
			end
		end
		self.entries[key] = nil
	end
	self.pending_cleanup = not has_events
	if has_events and #self.pending_remove_ids > 0 then
		for i = 1, #self.pending_remove_ids do
			Managers.event:trigger("remove_world_marker", self.pending_remove_ids[i])
		end
		self.pending_remove_ids = {}
	end
	self.world_markers = nil
end

function Markers:flush_pending()
	if self.pending_cleanup and Managers and Managers.event then
		self.pending_cleanup = false
		if #self.pending_remove_ids > 0 then
			for i = 1, #self.pending_remove_ids do
				Managers.event:trigger("remove_world_marker", self.pending_remove_ids[i])
			end
			self.pending_remove_ids = {}
		end
	end
end

function Markers:is_ready()
	if not Managers or not Managers.event then
		return false
	end
	local world_markers = self:_ensure_world_markers()
	return world_markers ~= nil
end

function Markers:has_active_ids()
	local world_markers = self:_ensure_world_markers()
	local by_id = world_markers and world_markers._markers_by_id or nil
	for _, entry in pairs(self.entries) do
		if entry and entry.id then
			if not by_id then
				return true
			end
			local marker = by_id[entry.id]
			if marker and marker.widget then
				return true
			end
		end
	end
	return false
end

function Markers:reset_stale_pending(now_t, timeout_s)
	local now = tonumber(now_t) or 0
	local timeout = tonumber(timeout_s) or 0.5
	for _, entry in pairs(self.entries) do
		if entry and entry._pending and not entry.id then
			local pending_t = entry._pending_t
			if (not pending_t) or (now - pending_t) > timeout then
				entry._pending = nil
				entry._pending_t = nil
			end
		end
	end
end

function Markers:refresh(label_entries, settings, now_t)
	if not label_entries or #label_entries == 0 then
		self:clear()
		return false
	end
	if not self.template then
		return false
	end
	if not Managers or not Managers.event then
		return false
	end
	self:_ensure_world_markers()
	local cap = settings.label_marker_cap
	if not cap or cap <= 0 then
		return false
	end
	local selected = self._selected_entries
	local count = select_top_entries(label_entries, cap, selected)
	if count <= 0 then
		self:clear()
		return false
	end
	self.generation = (self.generation or 0) + 1
	local generation = self.generation
	for i = 1, count do
		local entry = selected[i]
		local marker_entry = self.entries[entry.key]
		if not marker_entry then
			marker_entry = { id = nil, data = {}, position = nil }
			self.entries[entry.key] = marker_entry
		end
		marker_entry.generation = generation
		local data = marker_entry.data
		data.text = entry.text
		data.color = entry.color
		data.text_size = entry.text_size or settings.text_size
		data.height = entry.height or settings.text_height
		if entry.show_background ~= nil then
			data.show_background = entry.show_background
		else
			data.show_background = settings.text_background
		end
		data.check_line_of_sight = false

		local position = entry.position
		if position then
			if marker_entry._pending and not marker_entry.id then
				local pending_t = marker_entry._pending_t
				if pending_t and now_t and (now_t - pending_t) > 0.5 then
					marker_entry._pending = nil
					marker_entry._pending_t = nil
				end
			end
			if marker_entry.id and not marker_entry._pending then
				marker_entry.position = position
				if not self:_set_marker_position(marker_entry, position) then
					local old_id = marker_entry.id
					marker_entry.id = nil
					marker_entry._pending = nil
					marker_entry._pending_t = nil
					marker_entry._pending_remove_id = old_id
					add_world_marker_position_safe(
						self.entries,
						entry.key,
						marker_entry,
						self.template.name,
						position,
						data,
						function()
							if old_id and Managers and Managers.event then
								Managers.event:trigger("remove_world_marker", old_id)
							end
							if marker_entry._pending_remove_id == old_id then
								marker_entry._pending_remove_id = nil
							end
						end
					)
				end
			elseif not marker_entry.id and not marker_entry._pending then
				marker_entry.position = position
				add_world_marker_position_safe(self.entries, entry.key, marker_entry, self.template.name, position, data)
			else
				marker_entry.position = position
			end
		end
	end
	for key, marker_entry in pairs(self.entries) do
		if marker_entry.generation ~= generation then
			mark_entry_removed(marker_entry)
			if marker_entry.id and Managers and Managers.event then
				Managers.event:trigger("remove_world_marker", marker_entry.id)
			end
			self.entries[key] = nil
		end
	end
	return true
end

function Markers:update_positions(label_entries)
	if not label_entries or #label_entries == 0 then
		return
	end
	self:_ensure_world_markers()
	for i = 1, #label_entries do
		local entry = label_entries[i]
		if entry and entry.key and entry.position then
			local marker_entry = self.entries[entry.key]
			if marker_entry and marker_entry.id and not marker_entry._pending then
				marker_entry.position = entry.position
				if not self:_set_marker_position(marker_entry, entry.position) then
					marker_entry.id = nil
					marker_entry._pending = nil
					marker_entry._pending_t = nil
				end
			end
		end
	end
end

return Markers
