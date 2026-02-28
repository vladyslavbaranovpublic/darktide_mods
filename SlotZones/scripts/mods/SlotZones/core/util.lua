--[[
    File: util.lua
    Description: Utility helpers for world/unit access and math.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Util = {}
Util.__index = Util

local function valid_number(v)
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function valid_vector3(v)
	if not v then
		return false
	end
	local ok_x, x = pcall(function()
		return v.x
	end)
	local ok_y, y = pcall(function()
		return v.y
	end)
	local ok_z, z = pcall(function()
		return v.z
	end)
	if not ok_x or not ok_y or not ok_z then
		return false
	end
	return valid_number(x) and valid_number(y) and valid_number(z)
end

function Util.new(runtime)
	return setmetatable({
		runtime = runtime,
		_cached_world = nil,
		_unit_key_serials = setmetatable({}, { __mode = "k" }),
		_unit_key_next = 1,
	}, Util)
end

function Util:unit_key(unit)
	if unit == nil then
		return "none"
	end
	local unit_type = type(unit)
	if unit_type == "number" then
		return "N:" .. tostring(unit)
	end
	if unit_type ~= "userdata" then
		return tostring(unit)
	end

	local serials = self._unit_key_serials
	if not serials then
		serials = setmetatable({}, { __mode = "k" })
		self._unit_key_serials = serials
	end
	local serial = serials[unit]
	if not serial then
		serial = self._unit_key_next or 1
		self._unit_key_next = serial + 1
		serials[unit] = serial
	end

	local spawner = Managers.state and Managers.state.unit_spawner
	if spawner and spawner.game_object_id then
		local ok_go, go_id = pcall(spawner.game_object_id, spawner, unit)
		if ok_go and type(go_id) == "number" and go_id > 0 then
			return string.format("GO:%d:%d", go_id, serial)
		end
	end
	if spawner and spawner.game_object_id_or_level_index then
		local ok_idx, is_level_unit, id = pcall(spawner.game_object_id_or_level_index, spawner, unit)
		if ok_idx and type(id) == "number" then
			return string.format("%s:%d:%d", is_level_unit and "L" or "G", id, serial)
		end
	end

	return "U:" .. tostring(serial)
end

function Util:is_gameplay_state()
	if not Managers or not Managers.state or not Managers.state.game_mode then
		return false
	end
	local game_mode = Managers.state.game_mode:game_mode_name()
	return game_mode ~= "hub"
end

function Util:unit_is_alive(unit)
	local refs = self.runtime.resolve()
	if type(unit) ~= "userdata" then
		if ALIVE then
			local ok_alive, alive_lookup = pcall(function()
				return ALIVE[unit]
			end)
			return ok_alive and alive_lookup and true or false
		end
		return false
	end
	if not unit or not refs.Unit or not refs.Unit.alive then
		if ALIVE then
			local ok_alive, alive_lookup = pcall(function()
				return ALIVE[unit]
			end)
			if ok_alive and alive_lookup then
				return true
			end
		end
		return false
	end
	local ok, alive = pcall(refs.Unit.alive, unit)
	if ok then
		return alive and true or false
	end
	if ALIVE then
		local ok_alive, alive_lookup = pcall(function()
			return ALIVE[unit]
		end)
		if ok_alive and alive_lookup then
			return true
		end
	end
	return false
end

function Util:get_local_player_unit()
	local player_manager = Managers.player
	local local_player = player_manager and player_manager:local_player(1)
	return local_player and local_player.player_unit or nil
end

function Util:get_time_value(t)
	if t ~= nil then
		return t
	end
	local time_manager = Managers.time
	if time_manager and time_manager.time then
		local ok, value = pcall(time_manager.time, time_manager, "gameplay")
		if ok and value ~= nil then
			return value
		end
		ok, value = pcall(time_manager.time, time_manager, "main")
		if ok and value ~= nil then
			return value
		end
	end
	return 0
end

function Util:get_unit_position(unit, extension)
	if not unit then
		return nil
	end
	if not self:unit_is_alive(unit) then
		return nil
	end
	if extension and extension.position and extension.position.unbox then
		local ok, pos = pcall(extension.position.unbox, extension.position)
		if ok and pos and valid_vector3(pos) then
			return pos
		end
	end
	if POSITION_LOOKUP then
		local ok_lookup, lookup_pos = pcall(function()
			return POSITION_LOOKUP[unit]
		end)
		if ok_lookup and lookup_pos and valid_vector3(lookup_pos) then
			return lookup_pos
		end
	end
	local refs = self.runtime.resolve()
	if refs.Unit and refs.Unit.world_position then
		local ok, pos = pcall(refs.Unit.world_position, unit, 1)
		if ok and pos and valid_vector3(pos) then
			return pos
		end
	end
	return nil
end

function Util:get_unit_rotation(unit, extension)
	if extension and extension.rotation and extension.rotation.unbox then
		local ok, rot = pcall(extension.rotation.unbox, extension.rotation)
		if ok and rot then
			return rot
		end
	end
	if not unit then
		return nil
	end
	if not self:unit_is_alive(unit) then
		return nil
	end
	local refs = self.runtime.resolve()
	if refs.Unit and refs.Unit.world_rotation then
		local ok, rot = pcall(refs.Unit.world_rotation, unit, 1)
		if ok and rot then
			return rot
		end
	end
	if refs.Unit and refs.Unit.local_rotation then
		local ok, rot = pcall(refs.Unit.local_rotation, unit, 1)
		if ok and rot then
			return rot
		end
	end
	return nil
end

function Util:get_level_world()
	local world_manager = Managers.world
	if not world_manager or not world_manager.world then
		return nil
	end
	local cached = self._cached_world
	if cached then
		local worlds = rawget(world_manager, "_worlds")
		if worlds then
			for _, candidate in pairs(worlds) do
				if candidate == cached then
					return cached
				end
			end
		end
		local disabled_worlds = rawget(world_manager, "_disabled_worlds")
		if disabled_worlds then
			for _, candidate in pairs(disabled_worlds) do
				if candidate == cached then
					self._cached_world = nil
					break
				end
			end
		end
	end
	local world = world_manager:world("level_world")
	if world then
		self._cached_world = world
		return world
	end
	world = world_manager:world("gameplay_world") or world_manager:world("game_world") or world_manager:world("hub_world")
	if world then
		self._cached_world = world
		return world
	end
	local worlds = rawget(world_manager, "_worlds")
	if worlds then
		for name, candidate in pairs(worlds) do
			if type(name) == "string" and name:find("level") then
				self._cached_world = candidate
				return candidate
			end
		end
		for _, candidate in pairs(worlds) do
			self._cached_world = candidate
			return candidate
		end
	end
	local disabled_worlds = rawget(world_manager, "_disabled_worlds")
	if disabled_worlds then
		for name, candidate in pairs(disabled_worlds) do
			if type(name) == "string" and name:find("level") then
				self._cached_world = candidate
				return candidate
			end
		end
		for _, candidate in pairs(disabled_worlds) do
			self._cached_world = candidate
			return candidate
		end
	end
	return nil
end

function Util:distance_squared(a, b)
	if not a or not b then
		return nil
	end
	if not valid_vector3(a) or not valid_vector3(b) then
		return nil
	end
	local refs = self.runtime.resolve()
	if refs.Vector3 and refs.Vector3.distance_squared then
		return refs.Vector3.distance_squared(a, b)
	end
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return dx * dx + dy * dy + dz * dz
end

function Util:distance(a, b)
	if not a or not b then
		return nil
	end
	local refs = self.runtime.resolve()
	if refs.Vector3 and refs.Vector3.distance then
		return refs.Vector3.distance(a, b)
	end
	local dist_sq = self:distance_squared(a, b)
	return dist_sq and math.sqrt(dist_sq) or nil
end

return Util
