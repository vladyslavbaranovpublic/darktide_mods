--[[
    File: line_draw.lua
    Description: Safe debug line-object drawing helpers and primitives.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local LineDraw = {}
LineDraw.__index = LineDraw

local function clear_local_state(self)
	self.world = nil
	self.object = nil
end

function LineDraw.new(runtime)
	return setmetatable({
		runtime = runtime,
		world = nil,
		object = nil,
	}, LineDraw)
end

function LineDraw:destroy()
	-- Reference-drop only; explicit destroy can crash on stale pointers during transitions.
	clear_local_state(self)
end

function LineDraw:clear(world)
	local refs = self.runtime.resolve()
	local line_object = self.object
	if not line_object then
		return
	end
	local owner_world = self.world
	local target_world = world or owner_world
	if not owner_world then
		self.object = nil
		return
	end
	if not world then
		-- Cleanup during transitions frequently has no stable world handle; avoid touching stale objects.
		clear_local_state(self)
		return
	end
	if target_world and owner_world ~= target_world then
		clear_local_state(self)
		return
	end
	local line_api = refs.LineObject
	local reset_fn = line_api and line_api.reset
	local dispatch_fn = line_api and line_api.dispatch
	if type(reset_fn) ~= "function" then
		clear_local_state(self)
		return
	end
	if type(dispatch_fn) ~= "function" then
		clear_local_state(self)
		return
	end
	local ok_draw = pcall(function()
		reset_fn(line_object)
		dispatch_fn(target_world, line_object)
	end)
	if not ok_draw then
		clear_local_state(self)
	end
end

function LineDraw:ensure(world)
	local refs = self.runtime.resolve()
	if not refs.LineObject or not refs.World or not world then
		return nil
	end
	if self.world ~= world or not self.object then
		self:destroy()
		local ok, line_object = pcall(refs.World.create_line_object, world)
		if ok and line_object then
			self.world = world
			self.object = line_object
		end
	end
	return self.object
end

function LineDraw:reset(line_object)
	local refs = self.runtime.resolve()
	local reset_fn = refs.LineObject and refs.LineObject.reset
	if not line_object or line_object ~= self.object or not self.world or type(reset_fn) ~= "function" then
		return false
	end
	local ok = pcall(function()
		reset_fn(line_object)
	end)
	if not ok then
		clear_local_state(self)
	end
	return ok
end

function LineDraw:dispatch(world, line_object)
	local refs = self.runtime.resolve()
	local dispatch_fn = refs.LineObject and refs.LineObject.dispatch
	if line_object and world and self.world == world and line_object == self.object and type(dispatch_fn) == "function" then
		local ok = pcall(function()
			dispatch_fn(world, line_object)
		end)
		if not ok then
			clear_local_state(self)
		end
	end
end

function LineDraw:to_color(rgb, alpha)
	local refs = self.runtime.resolve()
	local r, g, b = 255, 255, 255
	if type(rgb) == "table" then
		r = tonumber(rgb[1]) or tonumber(rgb.r) or tonumber(rgb.red) or 255
		g = tonumber(rgb[2]) or tonumber(rgb.g) or tonumber(rgb.green) or 255
		b = tonumber(rgb[3]) or tonumber(rgb.b) or tonumber(rgb.blue) or 255
	end
	local a = tonumber(alpha) or 220
	if a < 0 then
		a = 0
	elseif a > 255 then
		a = 255
	end
	if r < 0 then
		r = 0
	elseif r > 255 then
		r = 255
	end
	if g < 0 then
		g = 0
	elseif g > 255 then
		g = 255
	end
	if b < 0 then
		b = 0
	elseif b > 255 then
		b = 255
	end
	if not refs.Color then
		return { r, g, b }
	end
	if type(refs.Color) == "function" then
		return refs.Color(a, r, g, b)
	end
	local mt = getmetatable(refs.Color)
	if mt and type(mt.__call) == "function" then
		return refs.Color(a, r, g, b)
	end
	if type(refs.Color.new) == "function" then
		return refs.Color.new(a, r, g, b)
	end
	return { r, g, b }
end

function LineDraw:add_circle_lines(line_object, color, center, radius, segments)
	local refs = self.runtime.resolve()
	if not refs.Vector3 or radius <= 0 then
		return
	end
	local safe_segments = math.max(8, segments or 24)
	local step = (math.pi * 2) / safe_segments
	local prev = center + refs.Vector3(radius, 0, 0)
	for i = 1, safe_segments do
		local angle = step * i
		local next_pos = center + refs.Vector3(math.cos(angle) * radius, math.sin(angle) * radius, 0)
		pcall(refs.LineObject.add_line, line_object, color, prev, next_pos)
		prev = next_pos
	end
end

function LineDraw:draw_point(line_object, center, color)
	local refs = self.runtime.resolve()
	if not refs.Vector3 then
		return
	end
	if refs.LineObject and refs.LineObject.add_sphere then
		pcall(refs.LineObject.add_sphere, line_object, color, center, 0.12, 8, 8)
		return
	end
	local offset = refs.Vector3(0.2, 0, 0)
	pcall(refs.LineObject.add_line, line_object, color, center - offset, center + offset)
	offset = refs.Vector3(0, 0.2, 0)
	pcall(refs.LineObject.add_line, line_object, color, center - offset, center + offset)
	offset = refs.Vector3(0, 0, 0.2)
	pcall(refs.LineObject.add_line, line_object, color, center - offset, center + offset)
end

function LineDraw:draw_cylinder(line_object, center, radius, height, step, segments, color, height_rings, vertical_lines)
	local refs = self.runtime.resolve()
	if not refs.Vector3 then
		return
	end
	local safe_height = math.max(0, height or 0)
	if center then
		local z_lift = safe_height > 0 and 0.03 or 0.07
		center = center + refs.Vector3(0, 0, z_lift)
	end
	if radius <= 0 then
		self:draw_point(line_object, center, color)
		return
	end

	local normal = refs.Vector3(0, 0, 1)
	local safe_segments = math.max(8, segments or 24)
	local safe_step = math.max(0.1, step or 0.5)
	local half_height = safe_height * 0.5
	local stack_count = 0
	local ring_count = height_rings and math.floor(height_rings) or 0
	if ring_count < 0 then
		ring_count = 0
	end

	if safe_height > 0 and ring_count <= 0 then
		stack_count = math.max(1, math.floor(half_height / safe_step + 0.5))
	end

	if stack_count == 0 and ring_count == 0 then
		-- Zero-height rings are especially prone to z-fighting; use explicit line loops for stability.
		self:add_circle_lines(line_object, color, center, radius, safe_segments)
	elseif ring_count <= 0 then
		for s = -stack_count, stack_count do
			local pos = center + refs.Vector3(0, 0, safe_step * s)
			if refs.LineObject.add_circle then
				local ok = pcall(refs.LineObject.add_circle, line_object, color, pos, radius, normal, safe_segments)
				if not ok then
					self:add_circle_lines(line_object, color, pos, radius, safe_segments)
				end
			else
				self:add_circle_lines(line_object, color, pos, radius, safe_segments)
			end
		end
	else
		local total_rings = ring_count + 2
		local ring_step = total_rings > 1 and safe_height / (total_rings - 1) or safe_height
		for i = 0, total_rings - 1 do
			local pos = center + refs.Vector3(0, 0, -half_height + ring_step * i)
			if refs.LineObject.add_circle then
				local ok = pcall(refs.LineObject.add_circle, line_object, color, pos, radius, normal, safe_segments)
				if not ok then
					self:add_circle_lines(line_object, color, pos, radius, safe_segments)
				end
			else
				self:add_circle_lines(line_object, color, pos, radius, safe_segments)
			end
		end
	end

	if safe_height > 0 then
		local line_count = vertical_lines and math.floor(vertical_lines) or 4
		if line_count < 0 then
			line_count = 0
		end
		if line_count > 0 then
			local step_angle = (math.pi * 2) / line_count
			for i = 1, line_count do
				local angle = step_angle * (i - 1)
				local offset = refs.Vector3(math.cos(angle) * radius, math.sin(angle) * radius, 0)
				local from = center + offset + refs.Vector3(0, 0, -half_height)
				local to = center + offset + refs.Vector3(0, 0, half_height)
				pcall(refs.LineObject.add_line, line_object, color, from, to)
			end
		end
	end
end

function LineDraw:draw_thick_line(line_object, color, from, to, thickness)
	local refs = self.runtime.resolve()
	if not refs.Vector3 then
		return
	end
	if thickness == nil or thickness <= 0 then
		pcall(refs.LineObject.add_line, line_object, color, from, to)
		return
	end
	local direction = to - from
	if refs.Vector3.length(direction) < 0.001 then
		pcall(refs.LineObject.add_line, line_object, color, from, to)
		return
	end
	local dir = refs.Vector3.normalize(direction)
	local axis = refs.Vector3.up()
	if math.abs(refs.Vector3.dot(dir, axis)) > 0.9 then
		axis = refs.Vector3(1, 0, 0)
	end
	local right = refs.Vector3.normalize(refs.Vector3.cross(dir, axis))
	local up = refs.Vector3.normalize(refs.Vector3.cross(right, dir))
	local offset = thickness
	pcall(refs.LineObject.add_line, line_object, color, from, to)
	pcall(refs.LineObject.add_line, line_object, color, from + right * offset, to + right * offset)
	pcall(refs.LineObject.add_line, line_object, color, from - right * offset, to - right * offset)
	pcall(refs.LineObject.add_line, line_object, color, from + up * offset, to + up * offset)
	pcall(refs.LineObject.add_line, line_object, color, from - up * offset, to - up * offset)
end

return LineDraw
