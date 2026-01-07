--[[
	File: RitualZones.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	Last Updated: 2026-01-06
	Author: LAUREHTE
]]
local mod = get_mod("RitualZones")
local RitualZonesMarker = mod:io_dofile("RitualZones/scripts/mods/RitualZones/RitualZones_marker")
local RitualZonesTimerMarker = mod:io_dofile("RitualZones/scripts/mods/RitualZones/RitualZones_timer_marker")

local HavocMutatorLocalSettings = require("scripts/settings/havoc/havoc_mutator_local_settings")
local DaemonhostActions = require("scripts/settings/breed/breed_actions/chaos/chaos_mutator_daemonhost_actions")
local MainPathQueries = require("scripts/utilities/main_path_queries")
local NavQueries = require("scripts/utilities/nav_queries")
local Breeds = require("scripts/settings/breed/breeds")

local MARKER_ICON = "content/ui/materials/icons/difficulty/difficulty_skull_uprising"
local MARKER_COLOR = { 180, 120, 255 }
local PATH_COLOR = { 80, 200, 255 }
local PROGRESS_COLOR = { 120, 255, 140 }
local PROGRESS_MAX_COLOR = { 255, 120, 180 }
local BOSS_TRIGGER_COLOR = { 255, 120, 70 }
local PACING_TRIGGER_COLOR = { 140, 170, 255 }
local RESPAWN_PROGRESS_COLOR = { 120, 255, 255 }
local TRIGGER_POINT_RADIUS = 0.35
local BOSS_TRIGGER_RADIUS = 0.45
local RESPAWN_PROGRESS_RADIUS = 0.45
local RESPAWN_BEACON_AHEAD_DISTANCE = 25
local RING_COLORS = {
	red = { 255, 60, 60 },
	orange = { 255, 150, 40 },
	yellow = { 255, 220, 80 },
	purple = { 180, 120, 255 },
}
local DEBUG_TEXT_OFFSETS = {
	["Progress"] = { 0.25, 0.15, 0.5 },
	["Max Progress"] = { -0.25, 0.15, 1.5 },
	["Boss Trigger"] = { 0.25, -0.15, 2 },
	["Boss Unit Trigger"] = { 0.35, -0.05, 2 },
	["Boss Patrol Trigger"] = { 0.35, -0.15, 2 },
	["Respawn Progress"] = { -0.25, -0.15, 0 },
	["Ritual Spawn Trigger"] = { 0.25, 0, 0.5 },
	["Ritual Start Trigger"] = { 0, 0.25, 1 },
	["Ritual Speedup Trigger"] = { -0.25, 0, 3 },
	["Twins Ambush Trigger"] = { 0.35, -0.25, 2.5 },
	["Twins Spawn Trigger"] = { -0.35, -0.25, 1.5 },
	["Pacing Spawn"] = { 0.35, 0.25, 1 },
	["Pacing Spawn: monsters"] = { 0.45, 0.25, 1 },
	["Pacing Spawn: witches"] = { 0.15, 0.15, 2 },
	["Pacing Spawn: captains"] = { 0.15, 0.15, 1.5 },
	["Trigger"] = { 0, 0.25, 0 },
}

local markers = {}
local timer_markers = {}
local timer_state = {}
local debug_lines = { world = nil, object = nil }
local max_progress_distance = nil
local boss_triggered = {}
local speedup_triggered = {}
local ritual_start_triggered = {}
local pacing_triggered = {}
local markers_dirty = true
local timer_dirty = true
local marker_generation = 0
local cleanup_done = false
local debug_text_manager = nil
local debug_text_world = nil
local LineObject = rawget(_G, "LineObject")
local Color = rawget(_G, "Color")
local Matrix4x4 = rawget(_G, "Matrix4x4")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local World = rawget(_G, "World")
local Gui = rawget(_G, "Gui")
local Unit = rawget(_G, "Unit")
local NAV_MESH_ABOVE, NAV_MESH_BELOW = 5, 5
local TRIGGER_PAST_MARGIN = 1.0

local function resolve_debug_modules()
	if not LineObject then
		LineObject = rawget(_G, "LineObject")
	end
	if not Color then
		Color = rawget(_G, "Color")
	end
	if not Matrix4x4 then
		Matrix4x4 = rawget(_G, "Matrix4x4")
	end
	if not Vector3 then
		Vector3 = rawget(_G, "Vector3")
	end
	if not Quaternion then
		Quaternion = rawget(_G, "Quaternion")
	end
	if not World then
		World = rawget(_G, "World")
	end
	if not Gui then
		Gui = rawget(_G, "Gui")
	end
	if not Unit then
		Unit = rawget(_G, "Unit")
	end
end

local function is_gameplay_state()
	if not Managers or not Managers.state or not Managers.state.game_mode then
		return false
	end

	local game_mode = Managers.state.game_mode:game_mode_name()
	if game_mode == "hub" then
		return false
	end

	return true
end

local function unit_is_alive(unit)
	if not unit then
		return false
	end
	if ALIVE then
		return ALIVE[unit]
	end
	return Unit.alive and Unit.alive(unit)
end

local function is_finite_number(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function is_finite_vector(vec)
	if not vec or not Vector3 or not Vector3.x then
		return false
	end
	return is_finite_number(Vector3.x(vec))
		and is_finite_number(Vector3.y(vec))
		and is_finite_number(Vector3.z(vec))
end

local function get_unit_position(unit)
	local pos = POSITION_LOOKUP[unit]
	if pos and is_finite_vector(pos) then
		return pos
	end

	if Unit and Unit.world_position then
		local ok, value = pcall(Unit.world_position, unit, 1)
		if ok and value and is_finite_vector(value) then
			return value
		end
	end

	return nil
end

local function safe_distance(a, b)
	if not a or not b or not Vector3 then
		return nil
	end

	local ok, dist = pcall(Vector3.distance, a, b)
	if not ok then
		ok, dist = pcall(function()
			return Vector3.length(a - b)
		end)
	end

	if not ok or not is_finite_number(dist) then
		return nil
	end

	return dist
end

local function get_position_travel_distance(position)
	if not position then
		return nil
	end

	local ok, _, travel_distance = pcall(MainPathQueries.closest_position, position)
	if ok and travel_distance ~= nil then
		return travel_distance
	end

	local main_path = Managers.state.main_path
	if main_path and main_path.travel_distance_from_position then
		local ok_distance, distance = pcall(main_path.travel_distance_from_position, main_path, position)
		if ok_distance then
			return distance
		end
	end

	return nil
end

local function get_monster_position(monster)
	if not monster then
		return nil
	end

	local position = monster.position
	if position and position.unbox then
		local ok, value = pcall(position.unbox, position)
		if ok and is_finite_vector(value) then
			return value
		end
	end

	if is_finite_vector(position) then
		return position
	end

	return nil
end

local function get_color(color_name, alpha)
	local rgb = RING_COLORS[color_name] or RING_COLORS.red
	local a = alpha or 180
	return Color(a, rgb[1], rgb[2], rgb[3])
end

local function get_ring_defs()
	local rings = {}
	local trigger_distance = HavocMutatorLocalSettings.mutator_havoc_chaos_rituals.trigger_distance

	if trigger_distance and trigger_distance > 0 then
		rings[#rings + 1] = {
			id = "spawn_trigger",
			radius = trigger_distance,
			color = "red",
		}
	end

	local passive = DaemonhostActions.passive or {}
	local far_distance = passive.far_distance_offset
	local close_distance = passive.close_distance_offset

	if far_distance and far_distance > 0 then
		rings[#rings + 1] = {
			id = "ritual_start",
			radius = far_distance,
			color = "orange",
		}
	end

	if close_distance and close_distance > 0 then
		rings[#rings + 1] = {
			id = "ritual_speedup",
			radius = close_distance,
			color = "yellow",
		}
	end

	return rings
end

local function main_path_direction(travel_distance)
	if not travel_distance then
		return nil
	end

	local behind = MainPathQueries.position_from_distance(travel_distance - 1)
	local ahead = MainPathQueries.position_from_distance(travel_distance + 1)
	local direction = nil

	if behind and ahead then
		local diff = ahead - behind
		if Vector3.length(diff) > 0.001 then
			direction = Vector3.normalize(diff)
		end
	elseif ahead then
		local position = MainPathQueries.position_from_distance(travel_distance)
		if position then
			local diff = ahead - position
			if Vector3.length(diff) > 0.001 then
				direction = Vector3.normalize(diff)
			end
		end
	elseif behind then
		local position = MainPathQueries.position_from_distance(travel_distance)
		if position then
			local diff = position - behind
			if Vector3.length(diff) > 0.001 then
				direction = Vector3.normalize(diff)
			end
		end
	end

	return direction
end

local function get_unit_travel_distance(unit)
	if not unit then
		return nil
	end

	local position = POSITION_LOOKUP[unit] or Unit.world_position(unit, 1)
	if not position then
		return nil
	end

	local nav_ext = ScriptUnit.has_extension(unit, "navigation_system") and ScriptUnit.extension(unit, "navigation_system")
	local nav_world = nav_ext and nav_ext:nav_world()
	local traverse_logic = nav_ext and nav_ext:traverse_logic()
	local nav_position = nil

	if nav_world then
		if NavQueries.position_on_mesh_with_outside_position then
			nav_position = NavQueries.position_on_mesh_with_outside_position(
				nav_world,
				traverse_logic,
				position,
				NAV_MESH_ABOVE,
				NAV_MESH_BELOW,
				1,
				1
			)
		end
		if not nav_position then
			nav_position = NavQueries.position_on_mesh(nav_world, position, NAV_MESH_ABOVE, NAV_MESH_BELOW, traverse_logic)
		end
	end

	if nav_position then
		local _, travel_distance = MainPathQueries.closest_position(nav_position)
		if travel_distance ~= nil then
			return travel_distance
		end
		local main_path = Managers.state.main_path
		if main_path and main_path.travel_distance_from_position then
			local ok, distance = pcall(main_path.travel_distance_from_position, main_path, nav_position)
			if ok then
				return distance
			end
		end
	end

	local ok, _, travel_distance = pcall(MainPathQueries.closest_position, position)
	if ok then
		return travel_distance
	end

	local nav_mesh = Managers.state.nav_mesh
	local manager_nav_world = nav_mesh and nav_mesh:nav_world()
	local manager_traverse_logic = nav_mesh and nav_mesh.client_traverse_logic and nav_mesh:client_traverse_logic()
	if manager_nav_world then
		local manager_nav_position = nil
		if NavQueries.position_on_mesh_with_outside_position then
			manager_nav_position = NavQueries.position_on_mesh_with_outside_position(
				manager_nav_world,
				manager_traverse_logic,
				position,
				NAV_MESH_ABOVE,
				NAV_MESH_BELOW,
				1,
				1
			)
		end
		if not manager_nav_position then
			manager_nav_position = NavQueries.position_on_mesh(
				manager_nav_world,
				position,
				NAV_MESH_ABOVE,
				NAV_MESH_BELOW,
				manager_traverse_logic
			)
		end
		if manager_nav_position then
			local _, manager_distance = MainPathQueries.closest_position(manager_nav_position)
			if manager_distance ~= nil then
				return manager_distance
			end
		end
	end

	local main_path = Managers.state.main_path
	if main_path and main_path.travel_distance_from_position then
		local ok, travel_distance = pcall(main_path.travel_distance_from_position, main_path, position)
		if ok then
			return travel_distance
		end
	end

	return nil
end

local function add_spawn_trigger_distance(triggers, seen, distance)
	if distance == nil then
		return
	end

	distance = math.max(0, distance)
	local key = string.format("spawn:%.2f", distance)
	if not seen[key] then
		seen[key] = true
		triggers[#triggers + 1] = {
			id = "spawn_trigger",
			distance = distance,
			color = "red",
		}
	end
end

local function add_speedup_triggers(triggers, seen, travel_distance, far_offset, close_offset)
	if travel_distance == nil then
		return
	end

	if far_offset and far_offset > 0 then
		local distance = math.max(0, travel_distance - far_offset)
		local key = string.format("far:%.2f", distance)
		if not seen[key] then
			seen[key] = true
			triggers[#triggers + 1] = {
				id = "ritual_start",
				distance = distance,
				color = "orange",
			}
		end
	end

	if close_offset and close_offset > 0 then
		local distance = math.max(0, travel_distance - close_offset)
		local key = string.format("close:%.2f", distance)
		if not seen[key] then
			seen[key] = true
			triggers[#triggers + 1] = {
				id = "ritual_speedup",
				distance = distance,
				color = "yellow",
			}
		end
	end
end

local function is_boss_breed(breed_name)
	if not breed_name then
		return false
	end
	if breed_name == "chaos_mutator_daemonhost" then
		return true
	end
	local breed = Breeds and Breeds[breed_name]
	return breed and breed.is_boss or false
end

local function add_trigger_entry(entries, seen, key_prefix, distance, label)
	if not distance then
		return
	end
	distance = math.max(0, distance)
	local key = string.format("%s:%.2f", key_prefix or "trigger", distance)
	if not seen[key] then
		seen[key] = true
		entries[#entries + 1] = {
			distance = distance,
			key = key,
			label = label,
		}
	end
end

local function collect_boss_triggers(options)
	local entries = {}
	local seen = {}
	local mutator_manager = Managers.state.mutator
	local mutators = (mutator_manager and mutator_manager._mutators) or {}

	if options and options.mutator then
		local function add_monster(monster)
			if not monster or not is_boss_breed(monster.breed_name) then
				return
			end
			add_trigger_entry(entries, seen, "boss", monster.travel_distance, "Boss Trigger")
		end

		for _, mutator in pairs(mutators) do
			local monsters = mutator and mutator._monsters
			if monsters then
				for i = 1, #monsters do
					add_monster(monsters[i])
				end
			end
			local alive_monsters = mutator and mutator._alive_monsters
			if alive_monsters then
				for i = 1, #alive_monsters do
					add_monster(alive_monsters[i])
				end
			end
		end
	end

	if options and options.twins then
		local mutator_twins = mutators.mutator_monster_havoc_twins
		if mutator_twins then
			local active_twins = mutator_twins._monsters
			if active_twins then
				for i = 1, #active_twins do
					local twin = active_twins[i]
					if twin then
						add_trigger_entry(entries, seen, "twins", twin.travel_distance, "Twins Ambush Trigger")
					end
				end
			end

			local spawn_sections = mutator_twins._spawn_point_sections
			if spawn_sections then
				for _, section_data in pairs(spawn_sections) do
					for _, spawn_data in pairs(section_data) do
						if spawn_data then
							add_trigger_entry(
								entries,
								seen,
								"twins_point",
								spawn_data.spawn_travel_distance,
								"Twins Spawn Trigger"
							)
						end
					end
				end
			end
		end
	end

	if options and options.boss_patrols then
		local pacing_manager = Managers.state.pacing
		local monster_pacing = pacing_manager and pacing_manager._monster_pacing
		local boss_patrols = monster_pacing and monster_pacing._boss_patrols
		if boss_patrols then
			for i = 1, #boss_patrols do
				local boss_patrol = boss_patrols[i]
				if boss_patrol then
					add_trigger_entry(
						entries,
						seen,
						"boss_patrol",
						boss_patrol.travel_distance or boss_patrol.spawn_point_travel_distance,
						"Boss Patrol Trigger"
					)
				end
			end
		end
	end

	return entries
end

local function collect_pacing_spawn_triggers()
	local pacing_manager = Managers.state.pacing
	local monster_pacing = pacing_manager and pacing_manager._monster_pacing
	local spawn_sections = monster_pacing and monster_pacing._spawn_type_point_sections
	if not spawn_sections then
		return {}
	end

	local entries = {}
	local seen = {}

	for spawn_type, sections in pairs(spawn_sections) do
		for _, section_data in pairs(sections) do
			for _, spawn_data in pairs(section_data) do
				if spawn_data then
					add_trigger_entry(
						entries,
						seen,
						"pacing_" .. tostring(spawn_type),
						spawn_data.spawn_travel_distance or spawn_data.spawn_point_travel_distance,
						"Pacing Spawn: " .. tostring(spawn_type)
					)
				end
			end
		end
	end

	return entries
end

local function collect_respawn_progress_distances()
	local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
	local distances = {}
	local seen = {}

	local function add_distance(distance)
		if not distance then
			return
		end
		local progress = math.max(0, distance - RESPAWN_BEACON_AHEAD_DISTANCE)
		local key = string.format("respawn:%.2f", progress)
		if not seen[key] then
			seen[key] = true
			distances[#distances + 1] = progress
		end
	end

	local function add_units_travel_distance(units)
		if not units then
			return
		end
		for i = 1, #units do
			local unit = units[i]
			if unit_is_alive(unit) then
				local position = get_unit_position(unit)
				if position then
					add_distance(get_position_travel_distance(position))
				end
			end
		end
	end

	if respawn_system then
		local beacon_data = respawn_system._beacon_main_path_data
		if beacon_data then
			for i = 1, #beacon_data do
				local data = beacon_data[i]
				add_distance(data and data.distance)
			end
		else
			local lookup = respawn_system._beacon_main_path_distance_lookup
			if lookup then
				for _, distance in pairs(lookup) do
					add_distance(distance)
				end
			end
		end

		if #distances == 0 then
			local beacon_map = respawn_system.unit_to_extension_map
					and respawn_system:unit_to_extension_map()
				or respawn_system._unit_to_extension_map
			if beacon_map then
				for unit, _ in pairs(beacon_map) do
					if unit_is_alive(unit) and Unit and Unit.world_position then
						local ok, position = pcall(Unit.world_position, unit, 1)
						if ok and position then
							add_distance(get_position_travel_distance(position))
						end
					end
				end
			end
		end
	end

	if #distances == 0 then
		local component_system = Managers.state.extension and Managers.state.extension:system("component_system")
		if component_system and component_system.get_units_from_component_name then
			local units = component_system:get_units_from_component_name("RespawnBeacon")
			add_units_travel_distance(units)
		end
	end

	return distances
end

local function get_ritual_total_time()
	local passive = DaemonhostActions.passive or {}
	local ritual_timings = passive.ritual_timings
	if not ritual_timings then
		return nil
	end

	local difficulty = Managers.state.difficulty
	if difficulty and difficulty.get_table_entry_by_challenge then
		local ok, entry = pcall(difficulty.get_table_entry_by_challenge, difficulty, ritual_timings)
		if ok and entry then
			ritual_timings = entry
		end
	end

	if type(ritual_timings) ~= "table" then
		return nil
	end

	local total = 0
	for i = 1, #ritual_timings do
		local timing = ritual_timings[i]
		if type(timing) == "table" then
			local min = tonumber(timing[1]) or 0
			local max = tonumber(timing[2]) or min
			total = total + (min + max) * 0.5
		end
	end

	return total > 0 and total or nil
end

local function find_ritual_units()
	local side_system = Managers.state.extension and Managers.state.extension:system("side_system")
	if not side_system then
		return {}
	end

	local player_side = side_system:get_side_from_name("heroes")
	if not player_side then
		return {}
	end

	local enemy_units = nil
	if player_side.alive_units_by_tag then
		enemy_units = player_side:alive_units_by_tag("enemy", "witch")
	end
	local count = enemy_units and (enemy_units.size or #enemy_units) or 0
	if count == 0 then
		enemy_units = player_side:relation_units("enemy") or {}
	end
	enemy_units = enemy_units or {}
	local ritual_units = {}
	local seen = {}

	local function add_ritual_unit(unit, skip_breed_check)
		if not unit or seen[unit] or not unit_is_alive(unit) then
			return
		end
		if skip_breed_check then
			ritual_units[#ritual_units + 1] = unit
			seen[unit] = true
			return
		end
		if ScriptUnit.has_extension(unit, "unit_data_system") then
			local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
			local breed = unit_data_extension and unit_data_extension:breed()
			if breed and breed.name == "chaos_mutator_daemonhost" then
				ritual_units[#ritual_units + 1] = unit
				seen[unit] = true
			end
		end
	end

	count = enemy_units.size or #enemy_units

	if count > 0 then
		for i = 1, count do
			add_ritual_unit(enemy_units[i])
		end
	else
		for key, value in pairs(enemy_units) do
			local unit = key
			if type(unit) ~= "userdata" then
				unit = value
			end
			add_ritual_unit(unit)
		end
	end

	local mutator_manager = Managers.state.mutator
	local mutator = mutator_manager and mutator_manager:mutator("mutator_monster_spawner")
	if mutator and mutator._alive_monsters then
		for i = 1, #mutator._alive_monsters do
			local monster = mutator._alive_monsters[i]
			if monster and monster.breed_name == "chaos_mutator_daemonhost" then
				add_ritual_unit(monster.spawned_unit, true)
			end
		end
	end

	return ritual_units
end

local function collect_spawn_triggers(triggers, seen, ritual_units)
	local trigger_distance = HavocMutatorLocalSettings.mutator_havoc_chaos_rituals
		and HavocMutatorLocalSettings.mutator_havoc_chaos_rituals.trigger_distance

	if ritual_units and trigger_distance and trigger_distance > 0 then
		for i = 1, #ritual_units do
			local unit = ritual_units[i]
			if unit_is_alive(unit) then
				local travel_distance = get_unit_travel_distance(unit)
				if travel_distance then
					add_spawn_trigger_distance(triggers, seen, travel_distance - trigger_distance)
				end
			end
		end
	end

	local mutator_manager = Managers.state.mutator
	local mutator = mutator_manager and mutator_manager:mutator("mutator_monster_spawner")
	if not mutator then
		return
	end

	local function add_monster(monster)
		if not monster or monster.breed_name ~= "chaos_mutator_daemonhost" then
			return
		end
		local distance = monster.travel_distance
		if not distance then
			return
		end
		add_spawn_trigger_distance(triggers, seen, distance)
	end

	if mutator._alive_monsters then
		for i = 1, #mutator._alive_monsters do
			add_monster(mutator._alive_monsters[i])
		end
	end

	if mutator._monsters then
		for i = 1, #mutator._monsters do
			add_monster(mutator._monsters[i])
		end
	end
end

local function collect_path_triggers(ritual_units)
	local triggers = {}
	local seen = {}
	local trigger_distance = HavocMutatorLocalSettings.mutator_havoc_chaos_rituals
		and HavocMutatorLocalSettings.mutator_havoc_chaos_rituals.trigger_distance

	collect_spawn_triggers(triggers, seen, ritual_units)

	local passive = DaemonhostActions.passive or {}
	local far_offset = passive.far_distance_offset
	local close_offset = passive.close_distance_offset

	for i = 1, #ritual_units do
		local unit = ritual_units[i]
		if unit_is_alive(unit) then
			local travel_distance = get_unit_travel_distance(unit)
			add_speedup_triggers(triggers, seen, travel_distance, far_offset, close_offset)
		end
	end

	if trigger_distance and trigger_distance > 0 then
		for i = 1, #triggers do
			local trigger = triggers[i]
			if trigger.id == "spawn_trigger" then
				add_speedup_triggers(triggers, seen, trigger.distance + trigger_distance, far_offset, close_offset)
			end
		end
	end

	local mutator_manager = Managers.state.mutator
	local mutator = mutator_manager and mutator_manager:mutator("mutator_monster_spawner")
	if mutator and mutator._alive_monsters then
		for i = 1, #mutator._alive_monsters do
			local monster = mutator._alive_monsters[i]
			if monster and monster.breed_name == "chaos_mutator_daemonhost" then
				local travel_distance = nil
				local spawned_unit = monster.spawned_unit
				if spawned_unit and unit_is_alive(spawned_unit) then
					travel_distance = get_unit_travel_distance(spawned_unit)
				end
				if not travel_distance then
					local position = get_monster_position(monster)
					travel_distance = get_position_travel_distance(position)
				end
				add_speedup_triggers(triggers, seen, travel_distance, far_offset, close_offset)
			end
		end
	end

	return triggers
end

local function clear_markers()
	if not Managers.event then
		markers = {}
		return
	end

	for unit, entry in pairs(markers) do
		if entry.id then
			Managers.event:trigger("remove_world_marker", entry.id)
		end
		markers[unit] = nil
	end
end

local function clear_timer_markers()
	if not Managers.event then
		timer_markers = {}
		return
	end

	for unit, entry in pairs(timer_markers) do
		if entry.id then
			Managers.event:trigger("remove_world_marker", entry.id)
		end
		timer_markers[unit] = nil
	end
end

local function ensure_marker(unit, icon_size, color)
	local entry = markers[unit]
	if entry and entry.id and entry.generation == marker_generation then
		entry.data.icon_size = icon_size
		entry.data.color = color
		entry.data.icon = MARKER_ICON
		return
	end

	if entry and entry.id and Managers.event then
		Managers.event:trigger("remove_world_marker", entry.id)
	end

	local data = {
		icon = MARKER_ICON,
		icon_size = icon_size,
		color = color,
	}
	local new_entry = {
		id = nil,
		data = data,
		generation = marker_generation,
	}

	markers[unit] = new_entry

	if Managers.event then
		Managers.event:trigger("add_world_marker_unit", RitualZonesMarker.name, unit, function(marker_id)
			new_entry.id = marker_id
		end, data)
	end
end

local function update_markers(ritual_units)
	if not Managers or not Managers.event then
		clear_markers()
		return
	end

	if not mod:get("marker_enabled") then
		clear_markers()
		return
	end

	if markers_dirty then
		clear_markers()
		markers_dirty = false
	end

	local icon_size = mod:get("marker_size") or 42
	local active = {}

	for i = 1, #ritual_units do
		local unit = ritual_units[i]
		if unit_is_alive(unit) then
			ensure_marker(unit, icon_size, MARKER_COLOR)
			active[unit] = true
		end
	end

	for unit, entry in pairs(markers) do
		if not active[unit] or not unit_is_alive(unit) then
			if entry.id then
				Managers.event:trigger("remove_world_marker", entry.id)
			end
			markers[unit] = nil
		end
	end
end

local function ensure_timer_marker(unit, text, color, text_size, height)
	local entry = timer_markers[unit]
	if entry and entry.id and entry.generation == marker_generation then
		entry.data.text = text
		entry.data.color = color
		entry.data.text_size = text_size
		entry.data.height = height
		return
	end

	if entry and entry.id and Managers.event then
		Managers.event:trigger("remove_world_marker", entry.id)
	end

	local data = {
		text = text,
		color = color,
		text_size = text_size,
		height = height,
	}
	local new_entry = {
		id = nil,
		data = data,
		generation = marker_generation,
	}

	timer_markers[unit] = new_entry

	if Managers.event then
		Managers.event:trigger("add_world_marker_unit", RitualZonesTimerMarker.name, unit, function(marker_id)
			new_entry.id = marker_id
		end, data)
	end
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function lerp_color(c1, c2, t)
	return {
		math.floor(lerp(c1[1], c2[1], t) + 0.5),
		math.floor(lerp(c1[2], c2[2], t) + 0.5),
		math.floor(lerp(c1[3], c2[3], t) + 0.5),
	}
end

local function alpha(hz, cutoff)
	local tau = 1.0 / (2 * math.pi * cutoff)
	local te = 1.0 / hz
	return 1.0 / (1.0 + tau / te)
end

local function low_pass(state, prev_key, value, alpha_value)
	local filtered = alpha_value * value + (1 - alpha_value) * (state[prev_key] or value)
	state[prev_key] = filtered
	return filtered
end

local function filter_health_rate(state, current_rate)
	if current_rate == nil or current_rate ~= current_rate then
		return state.rate
	end

	local prev_rate = state.rate or current_rate
	local direction_changed = prev_rate * current_rate < 0

	if direction_changed then
		state._filter_derivative_prev = 0
		state._filter_rate_prev = current_rate
		return current_rate
	end

	local rate_derivative = (current_rate - prev_rate) * (state._filter_hz or 1)
	local filtered_derivative = low_pass(
		state,
		"_filter_derivative_prev",
		rate_derivative,
		alpha(state._filter_hz or 1, state._filter_d_cutoff or 1)
	)
	local adaptive_cutoff = (state._filter_min_cutoff or 0.1)
		+ (state._filter_beta or 1) * math.abs(filtered_derivative)

	return low_pass(
		state,
		"_filter_rate_prev",
		current_rate,
		alpha(state._filter_hz or 1, adaptive_cutoff)
	)
end

local function calculate_rate(current_value, previous_value, dt)
	if not dt or dt <= 0 then
		return nil
	end

	local rate = (current_value - previous_value) / dt
	if rate == 0 or math.abs(rate) > 1 then
		return nil
	end

	return rate
end

local function timer_color(time_left)
	local white = { 255, 255, 255 }
	local yellow = { 255, 255, 0 }
	local orange = { 255, 165, 0 }
	local red = { 255, 0, 0 }

	if not time_left or time_left >= 180 then
		return white
	end
	if time_left >= 60 then
		return lerp_color(white, yellow, (180 - time_left) / 120)
	end
	if time_left >= 30 then
		return lerp_color(yellow, orange, (60 - time_left) / 30)
	end
	if time_left > 0 then
		return lerp_color(orange, red, (30 - time_left) / 30)
	end
	return red
end

local function format_time(seconds)
	if not seconds then
		return "--"
	end
	if seconds <= 0 then
		return "0:00"
	end
	if seconds >= 60 then
		local minutes = math.floor(seconds / 60)
		local remaining = seconds - minutes * 60
		return string.format("%d:%04.1f", minutes, remaining)
	end
	return string.format("0:%04.1f", seconds)
end

local function update_timer_state(unit, dt, t)
	local data = timer_state[unit] or {}
	if not ScriptUnit.has_extension(unit, "health_system") then
		return nil, data
	end

	local health_extension = ScriptUnit.extension(unit, "health_system")
	local current_health_percent = health_extension:current_health_percent()
	if not is_finite_number(current_health_percent) then
		return nil, data
	end
	local now = t
	if now == nil and Managers.time then
		local time_manager = Managers.time
		if time_manager.time then
			local ok, value = pcall(time_manager.time, time_manager, "gameplay")
			if ok and value ~= nil then
				now = value
			else
				ok, value = pcall(time_manager.time, time_manager, "main")
				if ok and value ~= nil then
					now = value
				end
			end
		end
	end

	if data.last_health_percent == nil then
		data.last_health_percent = current_health_percent
		data.last_time_checked = now
		timer_state[unit] = data
		return nil, data
	end

	if not data.started and current_health_percent < 0.99 then
		data.started = true
	end

	if data.started and current_health_percent >= 0.999 then
		data.completed = true
	end

	if data.last_health_percent ~= nil
		and now
		and data.last_health_percent ~= current_health_percent then
		local delta_t = now - (data.last_time_checked or now)
		if delta_t <= 0 then
			timer_state[unit] = data
			return data.time_left, data
		end
		local raw_rate = calculate_rate(current_health_percent, data.last_health_percent, delta_t)
		data._filter_hz = delta_t > 0 and (1 / delta_t) or 1
		if raw_rate and raw_rate < 0 then
			data._filter_min_cutoff = 0.001
			data._filter_beta = 1
			data._filter_d_cutoff = 0.1
		else
			data._filter_min_cutoff = 10
			data._filter_beta = 30
			data._filter_d_cutoff = 10
		end

		data.rate = filter_health_rate(data, raw_rate) or data.rate

		if data.rate and (data.rate ~= 0 or math.abs(data.rate) > 1) then
			local dir = (data.last_health_percent - current_health_percent) < 0 and 1 or 0
			data.time_left = (dir - current_health_percent) / data.rate
			if data.time_left and data.time_left < 0 then
				data.time_left = 0
			end
		end

		data.last_health_percent = current_health_percent
		data.last_time_checked = now
		data.dt_decay = 1
	elseif data.time_left and dt and dt > 0 then
		if data.rate and data.rate < 0 then
			data.dt_decay = math.max(0, (data.dt_decay or 1) - 0.125 * dt)
		else
			data.dt_decay = 1
		end
		data.time_left = math.max(0, data.time_left - dt * (data.dt_decay or 1))
	end

	if data.time_left ~= nil and data.time_left <= 0 and data.started then
		data.completed = true
	end

	timer_state[unit] = data
	return data.time_left, data
end

local function update_timer_markers(ritual_units, dt, t)
	if not Managers or not Managers.event then
		clear_timer_markers()
		return
	end

	if timer_dirty then
		clear_timer_markers()
		timer_dirty = false
	end

	local player = Managers.player and Managers.player:local_player(1)
	local player_unit = player and player.player_unit
	if not player_unit or not unit_is_alive(player_unit) then
		clear_timer_markers()
		return
	end

	if not dt or dt <= 0 then
		local time_manager = Managers.time
		if time_manager and time_manager.delta_time then
			local ok, value = pcall(time_manager.delta_time, time_manager, "gameplay")
			if ok then
				dt = value
			end
			if not dt or dt <= 0 then
				ok, value = pcall(time_manager.delta_time, time_manager, "main")
				if ok then
					dt = value
				end
			end
		end
	end

	local height = mod:get("tracker_height") or 0.8
	local text_size = mod:get("tracker_size") or 22
	local active = {}

	for i = 1, #ritual_units do
		local unit = ritual_units[i]
		if unit_is_alive(unit) then
			local unit_pos = get_unit_position(unit)
			local player_pos = get_unit_position(player_unit)
			local distance = safe_distance(unit_pos, player_pos)
			local time_left, state = update_timer_state(unit, dt, t)

			if state and state.completed then
				local entry = timer_markers[unit]
				if entry and entry.id then
					Managers.event:trigger("remove_world_marker", entry.id)
				end
				timer_markers[unit] = nil
			else
				local display_time = time_left
				local color = timer_color(display_time)
				local distance_text = distance and string.format("%.0fm", distance) or "??m"
				local text = string.format("%s | %s", distance_text, format_time(display_time))
				ensure_timer_marker(unit, text, color, text_size, 1.2 + height)
				active[unit] = true
			end
		end
	end

	for unit, entry in pairs(timer_markers) do
		local state = timer_state[unit]
		if not unit_is_alive(unit) then
			if entry.id then
				Managers.event:trigger("remove_world_marker", entry.id)
			end
			timer_markers[unit] = nil
			timer_state[unit] = nil
		elseif not active[unit] and not (state and state.completed) then
			if entry.id then
				Managers.event:trigger("remove_world_marker", entry.id)
			end
			timer_markers[unit] = nil
			timer_state[unit] = nil
		end
	end
end

local function destroy_debug_lines()
	resolve_debug_modules()
	if debug_lines.world and debug_lines.object and World and World.destroy_line_object then
		pcall(World.destroy_line_object, debug_lines.world, debug_lines.object)
	end

	debug_lines.world = nil
	debug_lines.object = nil
end

local function clear_line_object(world)
	resolve_debug_modules()
	local line_object = debug_lines.object
	if line_object and debug_lines.world == world and LineObject then
		if pcall(LineObject.reset, line_object) then
			pcall(LineObject.dispatch, world, line_object)
		end
	end
end

local function destroy_debug_text_manager()
	if not debug_text_manager then
		debug_text_world = nil
		return
	end

	if debug_text_manager.destroy then
		pcall(debug_text_manager.destroy, debug_text_manager)
	end

	debug_text_manager = nil
	debug_text_world = nil
end

local function ensure_debug_text_manager(world)
	resolve_debug_modules()
	if not world or not World or not Gui or not Matrix4x4 or not Vector3 or not Quaternion or not Color then
		return nil
	end

	if debug_text_manager and debug_text_world == world then
		return debug_text_manager
	end

	destroy_debug_text_manager()
	local ok, world_gui = pcall(World.create_world_gui, world, Matrix4x4.identity(), 1, 1)
	if not ok or not world_gui then
		return nil
	end

	local manager = {
		_world = world,
		_world_gui = world_gui,
		_world_texts = {},
		_world_text_size = 0.6,
	}

	function manager:output_world_text(text, text_size, position, time, category, color, viewport_name)
		if not text or not position or not self._world_gui then
			return
		end

		local gui = self._world_gui
		local material = "content/ui/fonts/arial"
		local font = "content/ui/fonts/arial"
		text_size = text_size or self._world_text_size

		local tm = nil
		if viewport_name and Managers and Managers.state and Managers.state.camera then
			local ok_rot, camera_rotation = pcall(Managers.state.camera.camera_rotation, Managers.state.camera, viewport_name)
			if ok_rot and camera_rotation then
				tm = Matrix4x4.from_quaternion_position(camera_rotation, position)
			end
		end
		if not tm then
			tm = Matrix4x4.from_quaternion_position(Quaternion.identity(), position)
		end

		local text_extent_min, text_extent_max = Gui.text_extents(gui, text, font, text_size)
		local text_width = text_extent_max[1] - text_extent_min[1]
		local text_height = text_extent_max[2] - text_extent_min[2]
		local text_offset = Vector3(-text_width / 2, -text_height / 2, 0)
		category = category or "none"
		color = color or Vector3(255, 255, 255)

		local id = Gui.text_3d(gui, text, material, text_size, font, tm, text_offset, 0, Color(color.x, color.y, color.z))
		local entry = { id = id }

		self._world_texts[category] = self._world_texts[category] or {}
		self._world_texts[category][#self._world_texts[category] + 1] = entry
	end

	function manager:clear_world_text(clear_category)
		if not self._world_gui then
			return
		end

		for category, gui_texts in pairs(self._world_texts) do
			if not clear_category or category == "none" or clear_category == category then
				for i = #gui_texts, 1, -1 do
					local gui_text = gui_texts[i]
					if gui_text and gui_text.id then
						pcall(Gui.destroy_text_3d, self._world_gui, gui_text.id)
					end
					table.remove(gui_texts, i)
				end
			end
		end
	end

	function manager:destroy()
		self:clear_world_text()
		if World and World.destroy_gui and self._world_gui then
			pcall(World.destroy_gui, self._world, self._world_gui)
		end
		self._world_gui = nil
	end

	debug_text_manager = manager
	debug_text_world = world

	return manager
end

local function get_debug_text_manager(world)
	return ensure_debug_text_manager(world)
end

local function clear_debug_text(debug_text)
	if debug_text and debug_text.clear_world_text then
		pcall(debug_text.clear_world_text, debug_text, "RitualZones")
	end
end

local function get_debug_text_offset(label, scale)
	if not Vector3 then
		return nil
	end
	local offset = DEBUG_TEXT_OFFSETS[label]
	if not offset and label and string.find(label, "Pacing Spawn:", 1, true) then
		offset = DEBUG_TEXT_OFFSETS["Pacing Spawn"]
	end
	if not offset then
		return nil
	end
	local s = scale or 1
	return Vector3(offset[1] * s, offset[2] * s, offset[3] * s)
end

local function get_debug_text_position(base_position, label, height, scale)
	if not base_position or not Vector3 then
		return base_position
	end
	local position = base_position + Vector3(0, 0, height or 0)
	local offset = get_debug_text_offset(label, scale)
	if offset then
		position = position + offset
	end
	return position
end

local function output_debug_text(debug_text, text, position, size, color_rgb)
	if not debug_text or not position or not Vector3 then
		return
	end

	local color = Vector3(color_rgb[1], color_rgb[2], color_rgb[3])
	local viewport_name = nil
	if Managers and Managers.player and Managers.player.local_player then
		local player = Managers.player:local_player(1)
		viewport_name = player and player.viewport_name
	end
	pcall(debug_text.output_world_text, debug_text, text, size, position, nil, "RitualZones", color, viewport_name)
end

local function ensure_line_object(world)
	resolve_debug_modules()
	if not LineObject or not World or not world then
		return nil
	end

	if debug_lines.world ~= world or not debug_lines.object then
		destroy_debug_lines()
		local ok, line_object = pcall(World.create_line_object, world)
		if ok and line_object then
			debug_lines.world = world
			debug_lines.object = line_object
		end
	end

	return debug_lines.object
end

local function add_circle_lines(line_object, color, center, radius, segments)
	if radius <= 0 then
		return
	end
	local safe_segments = math.max(8, segments or 24)
	local step = (math.pi * 2) / safe_segments
	local prev = center + Vector3(radius, 0, 0)
	for i = 1, safe_segments do
		local angle = step * i
		local next_pos = center + Vector3(math.cos(angle) * radius, math.sin(angle) * radius, 0)
		pcall(LineObject.add_line, line_object, color, prev, next_pos)
		prev = next_pos
	end
end

local function draw_point(line_object, center, color)
	if LineObject.add_sphere then
		pcall(LineObject.add_sphere, line_object, color, center, 0.15, 8, 8)
		return
	end
	local offset = Vector3(0.2, 0, 0)
	pcall(LineObject.add_line, line_object, color, center - offset, center + offset)
	offset = Vector3(0, 0.2, 0)
	pcall(LineObject.add_line, line_object, color, center - offset, center + offset)
	offset = Vector3(0, 0, 0.2)
	pcall(LineObject.add_line, line_object, color, center - offset, center + offset)
end

local function draw_cylinder(line_object, center, radius, height, step, segments, color)
	if radius <= 0 then
		draw_point(line_object, center, color)
		return
	end

	local normal = Vector3(0, 0, 1)
	local safe_segments = math.max(8, segments or 24)
	local safe_height = math.max(0, height or 0)
	local safe_step = math.max(0.1, step or 0.5)
	local half_height = safe_height * 0.5
	local stack_count = 0

	if safe_height > 0 then
		stack_count = math.max(1, math.floor(half_height / safe_step + 0.5))
	end

	if stack_count == 0 then
		if LineObject.add_circle then
			local ok = pcall(LineObject.add_circle, line_object, color, center, radius, normal, safe_segments)
			if not ok then
				add_circle_lines(line_object, color, center, radius, safe_segments)
			end
		else
			add_circle_lines(line_object, color, center, radius, safe_segments)
		end
	else
		for s = -stack_count, stack_count do
			local pos = center + Vector3(0, 0, safe_step * s)
			if LineObject.add_circle then
				local ok = pcall(LineObject.add_circle, line_object, color, pos, radius, normal, safe_segments)
				if not ok then
					add_circle_lines(line_object, color, pos, radius, safe_segments)
				end
			else
				add_circle_lines(line_object, color, pos, radius, safe_segments)
			end
		end
	end

	if safe_height > 0 then
		local offsets = {
			Vector3(radius, 0, 0),
			Vector3(-radius, 0, 0),
			Vector3(0, radius, 0),
			Vector3(0, -radius, 0),
		}
		for i = 1, #offsets do
			local offset = offsets[i]
			local from = center + offset + Vector3(0, 0, -half_height)
			local to = center + offset + Vector3(0, 0, half_height)
			pcall(LineObject.add_line, line_object, color, from, to)
		end
	end
end

local function draw_sphere(line_object, center, radius, segments, color)
	if radius <= 0 then
		draw_point(line_object, center, color)
		return
	end

	local safe_segments = math.max(8, segments or 24)
	local safe_rings = math.max(6, math.floor(safe_segments * 0.5))
	if LineObject.add_sphere then
		pcall(LineObject.add_sphere, line_object, color, center, radius, safe_segments, safe_rings)
	else
		add_circle_lines(line_object, color, center, radius, safe_segments)
	end
end

local function draw_box(line_object, center, radius, height, color)
	if radius <= 0 then
		draw_point(line_object, center, color)
		return
	end
	if not Matrix4x4 or not Quaternion or not Matrix4x4.from_quaternion_position then
		draw_cylinder(line_object, center, radius, height, height, 16, color)
		return
	end

	local half_height = math.max(0, (height or 0) * 0.5)
	local extents = Vector3(radius, radius, half_height)
	local pose = Matrix4x4.from_quaternion_position(Quaternion.identity(), center)

	pcall(LineObject.add_box, line_object, color, pose, extents)
end

local function draw_gate_plane(line_object, base_position, direction, width, height, slices, color)
	if not direction then
		draw_point(line_object, base_position, color)
		return
	end

	local gate_height = math.max(0.5, height or 4)
	local gate_width = math.max(0.5, width or 6)
	local half_width = gate_width * 0.5
	local half_height = gate_height * 0.5
	local gate_slices = math.floor(tonumber(slices) or 1)
	local up = Vector3.up()
	local right = Vector3.cross(up, direction)
	if Vector3.length(right) < 0.001 then
		right = Vector3(1, 0, 0)
	end
	right = Vector3.normalize(right)

	local center = base_position
	local top_left = center - right * half_width + up * half_height
	local top_right = center + right * half_width + up * half_height
	local bottom_left = center - right * half_width - up * half_height
	local bottom_right = center + right * half_width - up * half_height

	pcall(LineObject.add_line, line_object, color, top_left, top_right)
	pcall(LineObject.add_line, line_object, color, top_right, bottom_right)
	pcall(LineObject.add_line, line_object, color, bottom_right, bottom_left)
	pcall(LineObject.add_line, line_object, color, bottom_left, top_left)

	if gate_slices > 1 then
		local step = gate_width / gate_slices
		for i = 1, gate_slices - 1 do
			local offset = -half_width + step * i
			local slice_top = center + right * offset + up * half_height
			local slice_bottom = center + right * offset - up * half_height
			pcall(LineObject.add_line, line_object, color, slice_top, slice_bottom)
		end
	end
end

local function draw_main_path(line_object, color, height)
	local main_path_manager = Managers.state.main_path
	local segments = main_path_manager and main_path_manager._main_path_segments
	if not segments then
		return
	end

	local h = Vector3(0, 0, height or 0.2)

	for i = 1, #segments do
		local path = segments[i].nodes
		if path then
			for j = 1, #path do
				local node = path[j]
				if node then
					local position = Vector3(node[1], node[2], node[3]) + h
					local next_node = nil
					if j < #path then
						next_node = path[j + 1]
					elseif i < #segments then
						local next_segment = segments[i + 1]
						local next_path = next_segment and next_segment.nodes
						next_node = next_path and next_path[1]
					end
					if next_node then
						local next_pos = Vector3(next_node[1], next_node[2], next_node[3]) + h
						pcall(LineObject.add_line, line_object, color, position, next_pos)
					end
				end
			end
		end
	end
end

local function draw_debug_lines(world, ritual_units)
	if not mod:get("debug_enabled") then
		clear_line_object(world)
		return
	end

	resolve_debug_modules()
	if not world or not Vector3 or not LineObject or not Color then
		return
	end

	local gate_enabled = mod:get("gate_enabled")
	if gate_enabled == nil then
		gate_enabled = true
	end
	local path_enabled = mod:get("path_enabled")
	local debug_text_enabled = mod:get("debug_text_enabled")
	local debug_text_size = mod:get("debug_text_size") or 0.2
	local debug_text_height = mod:get("debug_text_height") or 0.4
	local debug_text_offset_scale = math.max(0.15, debug_text_size * 2)
	local boss_trigger_spheres_enabled = mod:get("boss_trigger_spheres_enabled")
	local boss_mutator_triggers_enabled = mod:get("boss_mutator_triggers_enabled")
	local boss_twins_triggers_enabled = mod:get("boss_twins_triggers_enabled")
	local boss_patrol_triggers_enabled = mod:get("boss_patrol_triggers_enabled")
	local pacing_spawn_triggers_enabled = mod:get("pacing_spawn_triggers_enabled")
	if boss_mutator_triggers_enabled == nil then
		boss_mutator_triggers_enabled = true
	end
	if boss_twins_triggers_enabled == nil then
		boss_twins_triggers_enabled = true
	end
	if boss_patrol_triggers_enabled == nil then
		boss_patrol_triggers_enabled = true
	end
	if pacing_spawn_triggers_enabled == nil then
		pacing_spawn_triggers_enabled = false
	end
	local respawn_progress_enabled = mod:get("respawn_progress_enabled")
	local trigger_points_enabled = mod:get("trigger_points_enabled")
	local progress_point_enabled = mod:get("progress_point_enabled")
	local path_height = mod:get("path_height") or 0.15
	local progress_height = mod:get("progress_height") or 0.15
	local sphere_radius_scale = mod:get("sphere_radius_scale") or 1
	if sphere_radius_scale < 0.05 then
		sphere_radius_scale = 0.05
	end
	local show_any = path_enabled
		or trigger_points_enabled
		or progress_point_enabled
		or boss_trigger_spheres_enabled
		or pacing_spawn_triggers_enabled
		or respawn_progress_enabled
		or debug_text_enabled
	if not show_any then
		clear_line_object(world)
		return
	end

	local debug_text = nil
	if debug_text_enabled then
		debug_text = get_debug_text_manager(world)
		clear_debug_text(debug_text)
	else
		clear_debug_text(debug_text_manager)
		destroy_debug_text_manager()
	end

	local line_object = ensure_line_object(world)
	if not line_object or not pcall(LineObject.reset, line_object) then
		destroy_debug_lines()
		return
	end

	if MainPathQueries.is_main_path_registered and not MainPathQueries.is_main_path_registered() then
		pcall(LineObject.dispatch, world, line_object)
		return
	end

	local gate_width = mod:get("gate_width") or 6
	local gate_height = mod:get("gate_height") or 8
	local gate_slices = mod:get("gate_slices") or 1
	local path_total = MainPathQueries.total_path_distance and MainPathQueries.total_path_distance()
	local remove_distance = nil
	local player = Managers.player and Managers.player:local_player(1)
	local player_unit = player and player.player_unit
	local player_distance = nil
	if player_unit and unit_is_alive(player_unit) then
		local player_position = get_unit_position(player_unit)
		player_distance = get_position_travel_distance(player_position)
		if not player_distance then
			player_distance = get_unit_travel_distance(player_unit)
		end
		if player_distance then
			remove_distance = player_distance - TRIGGER_PAST_MARGIN
		end
	end
	if not remove_distance and Managers.state.main_path and Managers.state.main_path.ahead_unit then
		local _, ahead_distance = Managers.state.main_path:ahead_unit(1)
		if ahead_distance then
			remove_distance = ahead_distance - TRIGGER_PAST_MARGIN
		end
	end
	if path_total then
		if player_distance then
			player_distance = math.max(0, math.min(player_distance, path_total))
		end
		if remove_distance then
			remove_distance = math.max(0, math.min(remove_distance, path_total))
		end
	end
	local alpha = 200

	if path_enabled then
		local path_color = Color(120, PATH_COLOR[1], PATH_COLOR[2], PATH_COLOR[3])
		draw_main_path(line_object, path_color, path_height)
	end

	if progress_point_enabled and player_distance then
		if path_total then
			player_distance = math.max(0, math.min(player_distance, path_total))
		end
		if not max_progress_distance or player_distance > max_progress_distance then
			max_progress_distance = player_distance
		end
		local progress_position = MainPathQueries.position_from_distance(player_distance)
		if progress_position then
			local color = Color(220, PROGRESS_COLOR[1], PROGRESS_COLOR[2], PROGRESS_COLOR[3])
			local position = progress_position + Vector3(0, 0, path_height + progress_height)
			draw_sphere(line_object, position, 0.4 * sphere_radius_scale, 20, color)
			if debug_text_enabled then
				local text_position = get_debug_text_position(position, "Progress", debug_text_height, debug_text_offset_scale)
				output_debug_text(
					debug_text,
					"Progress",
					text_position,
					debug_text_size,
					PROGRESS_COLOR
				)
			end
		end
		if max_progress_distance then
			local max_position = MainPathQueries.position_from_distance(max_progress_distance)
			if max_position then
				local max_color = Color(220, PROGRESS_MAX_COLOR[1], PROGRESS_MAX_COLOR[2], PROGRESS_MAX_COLOR[3])
				local position = max_position + Vector3(0, 0, path_height + progress_height)
				draw_sphere(line_object, position, 0.45 * sphere_radius_scale, 20, max_color)
				if debug_text_enabled then
					local text_position =
						get_debug_text_position(position, "Max Progress", debug_text_height, debug_text_offset_scale)
					output_debug_text(
						debug_text,
						"Max Progress",
						text_position,
						debug_text_size,
						PROGRESS_MAX_COLOR
					)
				end
			end
		end
	end

	if boss_trigger_spheres_enabled then
		local boss_triggers = collect_boss_triggers({
			mutator = boss_mutator_triggers_enabled,
			twins = boss_twins_triggers_enabled,
			boss_patrols = boss_patrol_triggers_enabled,
		})
		if #boss_triggers > 0 then
			local twins_counts = {}
			local twins_indices = {}
			for i = 1, #boss_triggers do
				local trigger = boss_triggers[i]
				if trigger.label == "Twins Ambush Trigger" then
					local distance_key = string.format("twins_dist:%.2f", trigger.distance or 0)
					twins_counts[distance_key] = (twins_counts[distance_key] or 0) + 1
				end
			end
			for i = 1, #boss_triggers do
				local trigger = boss_triggers[i]
				local distance = trigger.distance
				if distance and path_total then
					distance = math.max(0, math.min(distance, path_total))
				end
				local position = distance and MainPathQueries.position_from_distance(distance)
				if position then
					if trigger.label == "Twins Ambush Trigger" then
						local distance_key = string.format("twins_dist:%.2f", distance or 0)
						local group_count = twins_counts[distance_key] or 1
						local group_index = (twins_indices[distance_key] or 0) + 1
						twins_indices[distance_key] = group_index
						if group_count > 1 then
							local direction = main_path_direction(distance)
							local right = direction and Vector3.cross(Vector3.up(), direction)
							if not right or Vector3.length(right) < 0.001 then
								right = Vector3(1, 0, 0)
							end
							right = Vector3.normalize(right)
							local step = (BOSS_TRIGGER_RADIUS * 2.2) * sphere_radius_scale
							local centered_index = group_index - (group_count + 1) * 0.5
							position = position + right * (step * centered_index)
						end
					end
					local key = trigger.key or string.format("boss:%.2f", distance or 0)
					local passed = boss_triggered[key] or (player_distance and distance and distance <= player_distance)
					if passed and not boss_triggered[key] then
						boss_triggered[key] = true
					end
					local color_rgb = passed and MARKER_COLOR or BOSS_TRIGGER_COLOR
					local boss_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
					local radius = BOSS_TRIGGER_RADIUS * sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, path_height + radius)
					draw_sphere(line_object, sphere_position, radius, 18, boss_color)
					if debug_text_enabled then
						local label = trigger.label or "Boss Trigger"
						local text_position =
							get_debug_text_position(sphere_position, label, debug_text_height, debug_text_offset_scale)
						output_debug_text(
							debug_text,
							label,
							text_position,
							debug_text_size,
							color_rgb
						)
					end
				end
			end
		end
	end

	if pacing_spawn_triggers_enabled then
		local pacing_triggers = collect_pacing_spawn_triggers()
		if #pacing_triggers > 0 then
			local pacing_counts = {}
			local pacing_indices = {}
			for i = 1, #pacing_triggers do
				local distance = pacing_triggers[i].distance
				local distance_key = string.format("pacing_dist:%.2f", distance or 0)
				pacing_counts[distance_key] = (pacing_counts[distance_key] or 0) + 1
			end
			for i = 1, #pacing_triggers do
				local trigger = pacing_triggers[i]
				local distance = trigger.distance
				if distance and path_total then
					distance = math.max(0, math.min(distance, path_total))
				end
				local distance_key = string.format("pacing_dist:%.2f", distance or 0)
				local group_count = pacing_counts[distance_key] or 1
				local group_index = (pacing_indices[distance_key] or 0) + 1
				pacing_indices[distance_key] = group_index
				local position = distance and MainPathQueries.position_from_distance(distance)
				if position then
					if group_count > 1 then
						local direction = main_path_direction(distance)
						local right = direction and Vector3.cross(Vector3.up(), direction)
						if not right or Vector3.length(right) < 0.001 then
							right = Vector3(1, 0, 0)
						end
						right = Vector3.normalize(right)
						local step = (TRIGGER_POINT_RADIUS * 2.2) * sphere_radius_scale
						local centered_index = group_index - (group_count + 1) * 0.5
						position = position + right * (step * centered_index)
					end
					local key = trigger.key or string.format("pacing:%.2f", distance or 0)
					local passed = pacing_triggered[key] or (player_distance and distance and distance <= player_distance)
					if passed and not pacing_triggered[key] then
						pacing_triggered[key] = true
					end
					local color_rgb = passed and MARKER_COLOR or PACING_TRIGGER_COLOR
					local pace_color = Color(200, color_rgb[1], color_rgb[2], color_rgb[3])
					local radius = TRIGGER_POINT_RADIUS * sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, path_height + radius)
					draw_sphere(line_object, sphere_position, radius, 16, pace_color)
					if debug_text_enabled then
						local label = trigger.label or "Pacing Spawn"
						local text_position =
							get_debug_text_position(sphere_position, label, debug_text_height, debug_text_offset_scale)
						output_debug_text(
							debug_text,
							label,
							text_position,
							debug_text_size,
							color_rgb
						)
					end
				end
			end
		end
	end

	if respawn_progress_enabled then
		local respawn_distances = collect_respawn_progress_distances()
		if #respawn_distances > 0 then
			for i = 1, #respawn_distances do
				local distance = respawn_distances[i]
				if distance and path_total then
					distance = math.max(0, math.min(distance, path_total))
				end
				local passed = player_distance and distance and distance <= player_distance
				local position = distance and MainPathQueries.position_from_distance(distance)
				if position then
					local color_rgb = passed and MARKER_COLOR or RESPAWN_PROGRESS_COLOR
					local respawn_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
					local radius = RESPAWN_PROGRESS_RADIUS * sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, path_height + radius)
					draw_sphere(line_object, sphere_position, radius, 18, respawn_color)
					if debug_text_enabled then
						local text_position = get_debug_text_position(
							sphere_position,
							"Respawn Progress",
							debug_text_height,
							debug_text_offset_scale
						)
						output_debug_text(
							debug_text,
							"Respawn Progress",
							text_position,
							debug_text_size,
							color_rgb
						)
					end
				end
			end
		end
	end

	if trigger_points_enabled then
		local triggers = collect_path_triggers(ritual_units or {})
		local spawn_counts = {}
		local spawn_indices = {}
		for i = 1, #triggers do
			local trigger = triggers[i]
			if trigger.id == "spawn_trigger" then
				local distance_key = string.format("spawn_dist:%.2f", trigger.distance or 0)
				spawn_counts[distance_key] = (spawn_counts[distance_key] or 0) + 1
			end
		end
		for i = 1, #triggers do
			local trigger = triggers[i]
			local distance = trigger.distance
			if distance and path_total then
				distance = math.max(0, math.min(distance, path_total))
			end
			local persist_table = nil
			local persist_key = nil
			local persist_passed = false
			if distance then
				if trigger.id == "ritual_speedup" then
					persist_table = speedup_triggered
					persist_key = string.format("speedup:%.2f", distance)
				elseif trigger.id == "ritual_start" then
					persist_table = ritual_start_triggered
					persist_key = string.format("start:%.2f", distance)
				end
			end
			if persist_table and persist_key then
				persist_passed = persist_table[persist_key] or (player_distance and distance <= player_distance)
				if persist_passed and not persist_table[persist_key] then
					persist_table[persist_key] = true
				end
			end
			if not persist_table and remove_distance and distance and distance <= remove_distance then
				distance = nil
			end
			local position = distance and MainPathQueries.position_from_distance(distance)
			if position then
				local direction = main_path_direction(distance)
				if trigger.id == "spawn_trigger" then
					local distance_key = string.format("spawn_dist:%.2f", distance or 0)
					local group_count = spawn_counts[distance_key] or 1
					local group_index = (spawn_indices[distance_key] or 0) + 1
					spawn_indices[distance_key] = group_index
					if group_count > 1 then
						local right = direction and Vector3.cross(Vector3.up(), direction)
						if not right or Vector3.length(right) < 0.001 then
							right = Vector3(1, 0, 0)
						end
						right = Vector3.normalize(right)
						local step = (TRIGGER_POINT_RADIUS * 2.2) * sphere_radius_scale
						local centered_index = group_index - (group_count + 1) * 0.5
						position = position + right * (step * centered_index)
					end
				end
				local color = get_color(trigger.color, alpha)
				if persist_passed then
					color = Color(alpha, MARKER_COLOR[1], MARKER_COLOR[2], MARKER_COLOR[3])
				end
				local base_position = position + Vector3(0, 0, path_height)
				if gate_enabled then
					draw_gate_plane(line_object, base_position, direction, gate_width, gate_height, gate_slices, color)
				end
				local trigger_radius = TRIGGER_POINT_RADIUS * sphere_radius_scale
				local trigger_position = base_position + Vector3(0, 0, trigger_radius)
				draw_sphere(line_object, trigger_position, trigger_radius, 16, color)
				if debug_text_enabled then
					local label = "Trigger"
					if trigger.id == "spawn_trigger" then
						label = "Ritual Spawn Trigger"
					elseif trigger.id == "ritual_start" then
						label = "Ritual Start Trigger"
					elseif trigger.id == "ritual_speedup" then
						label = "Ritual Speedup Trigger"
					end
					local text_position =
						get_debug_text_position(trigger_position, label, debug_text_height, debug_text_offset_scale)
					local color_rgb = persist_passed and MARKER_COLOR or { color[2], color[3], color[4] }
					output_debug_text(
						debug_text,
						label,
						text_position,
						debug_text_size,
						color_rgb
					)
				end
			end
		end
	end

	pcall(LineObject.dispatch, world, line_object)
end

local function mark_dirty()
	markers_dirty = true
	timer_dirty = true
end

local function reset_runtime_state(clear_text)
	clear_markers()
	clear_timer_markers()
	local world = Managers.world and Managers.world:world("level_world")
	if world then
		clear_line_object(world)
	end
	destroy_debug_lines()
	max_progress_distance = nil
	boss_triggered = {}
	speedup_triggered = {}
	ritual_start_triggered = {}
	pacing_triggered = {}
	if clear_text then
		local debug_text = get_debug_text_manager(world)
		clear_debug_text(debug_text)
		destroy_debug_text_manager()
	end
	mark_dirty()
end

mod:hook_safe(CLASS.HudElementWorldMarkers, "init", function(self)
	if RitualZonesMarker then
		self._marker_templates[RitualZonesMarker.name] = RitualZonesMarker
	end
	if RitualZonesTimerMarker then
		self._marker_templates[RitualZonesTimerMarker.name] = RitualZonesTimerMarker
	end
	marker_generation = marker_generation + 1
	markers_dirty = true
	timer_dirty = true
end)

mod:hook_safe(CLASS.HudElementBossHealth, "event_boss_encounter_start", function(self, unit, boss_extension)
	if not unit_is_alive(unit) or not ScriptUnit.has_extension(unit, "unit_data_system") then
		return
	end

	local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	if not breed or breed.name ~= "chaos_mutator_daemonhost" then
		return
	end

	local data = timer_state[unit] or {}
	data.started = true
	data.completed = false

	if ScriptUnit.has_extension(unit, "health_system") then
		local health_extension = ScriptUnit.extension(unit, "health_system")
		local current_health_percent = health_extension:current_health_percent()
		if is_finite_number(current_health_percent) then
			data.last_health_percent = current_health_percent
		end
	end

	if not data.start_time and Managers.time and Managers.time.time then
		local ok, value = pcall(Managers.time.time, Managers.time, "gameplay")
		if ok and value ~= nil then
			data.start_time = value
		else
			ok, value = pcall(Managers.time.time, Managers.time, "main")
			if ok and value ~= nil then
				data.start_time = value
			end
		end
	end

	timer_state[unit] = data
end)

mod:hook_safe(CLASS.HudElementBossHealth, "event_boss_encounter_end", function(self, unit, boss_extension)
	timer_state[unit] = nil
	local entry = timer_markers[unit]
	if entry and entry.id then
		Managers.event:trigger("remove_world_marker", entry.id)
	end
	timer_markers[unit] = nil
end)

mod.on_setting_changed = function()
	mark_dirty()
	local world = Managers.world and Managers.world:world("level_world")
	if world then
		clear_line_object(world)
	end
	local debug_text = get_debug_text_manager(world)
	clear_debug_text(debug_text)
	if not mod:get("debug_text_enabled") then
		destroy_debug_text_manager()
	end
end

mod.on_enabled = function()
	cleanup_done = false
	mark_dirty()
end

mod.on_game_state_changed = function(status, state_name)
	if status == "enter" and (state_name == "GameplayStateRun" or state_name == "StateGameplay") then
		return
	end

	reset_runtime_state(true)
	cleanup_done = false
end

mod.on_disabled = function()
	reset_runtime_state(true)
	cleanup_done = true
end

mod.update = function(dt, t)
	if not mod:get("ritualzones_enabled") then
		if not cleanup_done then
			reset_runtime_state(true)
			cleanup_done = true
		end
		return
	end
	cleanup_done = false

	if not is_gameplay_state() then
		return
	end

	local world = Managers.world and Managers.world:world("level_world")
	if not world then
		return
	end

	if t == nil and Managers.time then
		local time_manager = Managers.time
		if time_manager.time then
			local ok, value = pcall(time_manager.time, time_manager, "gameplay")
			if ok and value ~= nil then
				t = value
			end
		end
		if t == nil then
			local ok, value = pcall(time_manager.time, time_manager, "main")
			if ok and value ~= nil then
				t = value
			end
		end
	end

	local ritual_units = find_ritual_units()

	update_markers(ritual_units)
	update_timer_markers(ritual_units, dt or 0, t or 0)
	draw_debug_lines(world, ritual_units)
end
