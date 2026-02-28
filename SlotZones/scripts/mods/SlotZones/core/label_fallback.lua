--[[
    File: label_fallback.lua
    Description: Fallback world-space text renderer when marker API is unavailable.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local LabelFallback = {}
LabelFallback.__index = LabelFallback

function LabelFallback.new(runtime)
	return setmetatable({
		runtime = runtime,
		world = nil,
		gui = nil,
		entries = {},
	}, LabelFallback)
end

local function resolve_color(refs, rgb)
	if not refs or type(rgb) ~= "table" then
		return nil
	end
	local color_api = refs.Color
	if not color_api then
		return nil
	end
	local r = rgb[1] or 255
	local g = rgb[2] or 255
	local b = rgb[3] or 255
	if type(color_api) == "function" then
		local ok, value = pcall(color_api, r, g, b)
		if ok and value then
			return value
		end
		ok, value = pcall(color_api, 255, r, g, b)
		if ok and value then
			return value
		end
	end
	local mt = getmetatable(color_api)
	if mt and type(mt.__call) == "function" then
		local ok, value = pcall(color_api, r, g, b)
		if ok and value then
			return value
		end
		ok, value = pcall(color_api, 255, r, g, b)
		if ok and value then
			return value
		end
	end
	if type(color_api.new) == "function" then
		local ok, value = pcall(color_api.new, 255, r, g, b)
		if ok and value then
			return value
		end
	end
	if type(color_api.from_rgb) == "function" then
		local ok, value = pcall(color_api.from_rgb, r, g, b)
		if ok and value then
			return value
		end
	end
	return nil
end

function LabelFallback:_ensure(world)
	if self.gui and self.world == world then
		return true
	end
	self:destroy()
	local refs = self.runtime.resolve()
	if not world or not refs.World or not refs.Gui or not refs.Matrix4x4 or not refs.Vector3 or not refs.Quaternion then
		return false
	end
	local ok, gui = pcall(refs.World.create_world_gui, world, refs.Matrix4x4.identity(), 1, 1)
	if ok and gui then
		self.world = world
		self.gui = gui
		return true
	end
	return false
end

function LabelFallback:clear(world)
	local entries = self.entries
	if not self.gui then
		for i = #entries, 1, -1 do
			entries[i] = nil
		end
		return
	end
	if not world or self.world ~= world then
		-- World changed (or cleanup with unknown world): drop ids without touching stale gui handles.
		for i = #entries, 1, -1 do
			entries[i] = nil
		end
		return
	end
	local refs = self.runtime.resolve()
	for i = #entries, 1, -1 do
		local id = entries[i]
		if id and refs.Gui and refs.Gui.destroy_text_3d then
			pcall(refs.Gui.destroy_text_3d, self.gui, id)
		end
		entries[i] = nil
	end
end

function LabelFallback:destroy()
	-- Reference-drop only; explicit gui destroy can crash during world transitions.
	self:clear(nil)
	self.gui = nil
	self.world = nil
end

function LabelFallback:render(world, label_entries, settings, enabled, refresh)
	if not enabled then
		self:clear(world)
		return
	end
	if not label_entries or #label_entries == 0 then
		self:clear(world)
		return
	end
	if not world then
		self:clear(nil)
		return
	end
	if not self:_ensure(world) then
		return
	end

	self:clear(world)
	local refs = self.runtime.resolve()
	if not refs.Gui or not refs.Matrix4x4 or not refs.Vector3 or not refs.Quaternion then
		return
	end
	local gui = self.gui
	local entries = self.entries
	local font_sets = {
		{ material = "content/ui/fonts/arial", font = "content/ui/fonts/arial" },
		{ material = "core/editor_slave/gui/arial", font = "core/editor_slave/gui/arial" },
		{ material = "content/ui/fonts/proxima_nova_bold", font = "content/ui/fonts/proxima_nova_bold" },
	}
	local limit = settings.label_marker_cap or #label_entries
	if limit <= 0 then
		limit = #label_entries
	end
	local count = math.min(#label_entries, limit)
	local size_default = settings.text_size or 0.2
	local height_default = settings.text_height or 1.0

	local viewport_name = nil
	if Managers and Managers.player and Managers.player.local_player then
		local player = Managers.player:local_player(1)
		viewport_name = player and player.viewport_name
	end
	local camera_rotation = nil
	if viewport_name and Managers and Managers.state and Managers.state.camera and Managers.state.camera.camera_rotation then
		local ok, rot = pcall(Managers.state.camera.camera_rotation, Managers.state.camera, viewport_name)
		if ok and rot then
			camera_rotation = rot
		end
	end

	for i = 1, count do
		local entry = label_entries[i]
		local text = entry and entry.text
		local pos = entry and entry.position
		if text and pos then
			local size = entry.text_size or size_default
			if size < 0.1 then
				size = 0.1
			end
			local height = entry.height or height_default
			local color = resolve_color(refs, entry.color or { 255, 255, 255 })
			if not color then
				color = resolve_color(refs, { 255, 255, 255 })
			end
			local offset = refs.Vector3(0, 0, 0)
			local world_pos = pos + refs.Vector3(0, 0, height)
			local rot = camera_rotation or refs.Quaternion.identity()
			local tm = refs.Matrix4x4.from_quaternion_position(rot, world_pos)
			if color then
				local text_id = nil
				for fi = 1, #font_sets do
					local set = font_sets[fi]
					local ok, id = pcall(refs.Gui.text_3d, gui, text, set.material, size, set.font, tm, offset, 3, color)
					if ok and id then
						text_id = id
						break
					end
				end
				if text_id then
					entries[#entries + 1] = text_id
				end
			end
		end
	end
end

return LabelFallback
