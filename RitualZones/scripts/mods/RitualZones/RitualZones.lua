--[[
	File: RitualZones.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.01.0
	File Version: 1.1.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local mod = get_mod("RitualZones")
local RitualZonesMarker = mod:io_dofile("RitualZones/scripts/mods/RitualZones/RitualZones_marker")
local RitualZonesTimerMarker = mod:io_dofile("RitualZones/scripts/mods/RitualZones/RitualZones_timer_marker")
local RitualZonesDebugLabelMarker = mod:io_dofile("RitualZones/scripts/mods/RitualZones/RitualZones_debug_label_marker")

local HavocMutatorLocalSettings = require("scripts/settings/havoc/havoc_mutator_local_settings")
local DaemonhostActions = require("scripts/settings/breed/breed_actions/chaos/chaos_mutator_daemonhost_actions")
local MainPathQueries = require("scripts/utilities/main_path_queries")
local NavQueries = require("scripts/utilities/nav_queries")
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")
local Breeds = require("scripts/settings/breed/breeds")

local CONST = {
	MARKER_ICON = "content/ui/materials/icons/difficulty/difficulty_skull_uprising",
	MARKER_COLOR = { 180, 120, 255 },
	PATH_COLOR = { 80, 200, 255 },
	PROGRESS_COLOR = { 120, 255, 140 },
	PROGRESS_MAX_COLOR = { 255, 120, 180 },
	BOSS_TRIGGER_COLOR = { 255, 120, 70 },
	AMBUSH_TRIGGER_COLOR = { 255, 90, 200 },
	BACKTRACK_TRIGGER_COLOR = { 255, 160, 40 },
	PACING_TRIGGER_COLOR = { 140, 170, 255 },
	RESPAWN_PROGRESS_COLOR = { 120, 255, 255 },
	RESPAWN_MOVE_TRIGGER_COLOR = { 255, 190, 90 },
	RESPAWN_BEACON_COLOR = { 140, 255, 200 },
	TRIGGER_POINT_RADIUS = 0.35,
	BOSS_TRIGGER_RADIUS = 0.45,
	RESPAWN_PROGRESS_RADIUS = 0.45,
	RESPAWN_BEACON_AHEAD_DISTANCE = 25,
	RESPAWN_MOVE_TRIGGER_DISTANCE = 30,
	BACKTRACK_ALLOWED_DISTANCE = 50,
	MAX_PROGRESS_HEIGHT_OFFSET = 0.25,
	PROGRESS_STACK_STEP = 0.5,
	PROGRESS_STACK_HEIGHT = 0.35,
	RING_COLORS = {
		red = { 255, 60, 60 },
		orange = { 255, 150, 40 },
		yellow = { 255, 220, 80 },
		purple = { 180, 120, 255 },
	},
	DEBUG_TEXT_OFFSETS = {
		["Progress"] = { 0.25, 0.15, 1.0 },
		["Progress (You)"] = { 0.25, 0.15, 1.0 },
		["Progress (Leader)"] = { 0.25, 0.25, 1.5 },
		["Max Progress"] = { -0.25, 0.15, 2.0 },
		["Boss Trigger"] = { 0.25, -0.15, 1.5 },
		["Boss Unit Trigger"] = { 0.35, -0.05, 2.5 },
		["Boss Patrol Trigger"] = { 0.35, -0.15, 3.0 },
		["Ambush Horde Trigger"] = { 0.25, -0.25, 3.5 },
		["Backtrack Horde Trigger"] = { -0.25, 0.25, 3.5 },
		["Respawn Progress"] = { -0.25, -0.15, 1.0 },
		["Respawn Progress Warning"] = { -0.25, -0.35, 3.5 },
		["Respawn Beacon Threshold"] = { 0.15, -0.25, 2.0 },
		["Respawn Backline"] = { -0.35, -0.25, 1.5 },
		["Respawn Rewind Threshold"] = { 0.35, -0.35, 4.0 },
		["Respawn Beacon"] = { -0.15, -0.25, 2.0 },
		["Priority Respawn Beacon"] = { 0.15, -0.25, 3.0 },
		["Rescue Move Trigger"] = { -0.15, -0.25, 1.5 },
		["Rescue Move Trigger Warning"] = { -0.15, -0.35, 3.0 },
		["Priority Move Trigger"] = { -0.15, -0.25, 1.5 },
		["Priority Move Trigger Warning"] = { -0.15, -0.35, 3.0 },
		["Ritual Spawn Trigger"] = { 0.25, 0, 2.0 },
		["Ritual Start Trigger"] = { 0, 0.25, 2.5 },
		["Ritual Speedup Trigger"] = { -0.25, 0, 3.0 },
		["Twins Ambush Trigger"] = { 0.35, -0.25, 3.5 },
		["Twins Spawn Trigger"] = { -0.35, -0.25, 3.0 },
		["Pacing Spawn"] = { 0.35, 0.25, 1.5 },
		["Pacing Spawn: monsters"] = { 0.45, 0.25, 2.0 },
		["Pacing Spawn: witches"] = { 0.15, 0.15, 2.5 },
		["Pacing Spawn: captains"] = { 0.15, 0.15, 3.0 },
		["Trigger"] = { 0, 0.25, 0.5 },
	},
}
local CACHE = {
	VERSION = 1,
	DISTANCE_TOLERANCE = 0.2,
	PATH_TOLERANCE = 5,
	UPDATE_INTERVAL = 1.0,
	MAX_RECORDS_PER_MISSION = 60,
}
local offline_cache = mod:persistent_table("offline_cache")
local cache_loaded = false
local cache_load_failed = false
local cache_runtime_dirty = false
local last_recorded_mission = nil
local cache_record_mission = nil
local cache_record_count = 0
local last_cache_skip_t = -math.huge
local last_cache_skip_reason = nil
local _io = Mods and Mods.lua and Mods.lua.io or nil
local _os = Mods and Mods.lua and Mods.lua.os or nil
local _loadstring = Mods and Mods.lua and Mods.lua.loadstring or nil
local CACHE_DIR_FALLBACK = "mods/RitualZones/cache"
local CACHE_FILE_FALLBACK = "mods/RitualZones/cache/ritualzones_cache.lua"

local function cache_debug(message)
	if mod:get("cache_debug_enabled") then
		mod:echo("[RitualZones Cache] " .. tostring(message))
	end
end

local function cache_debug_skip(reason, t, min_interval)
	if not mod:get("cache_debug_enabled") then
		return
	end
	local now = t
	if not now and Managers.time and Managers.time.time then
		local ok, value = pcall(Managers.time.time, Managers.time, "gameplay")
		if ok then
			now = value
		end
	end
	local interval = min_interval or 1.0
	if last_cache_skip_reason ~= reason or (now and (now - last_cache_skip_t) >= interval) then
		cache_debug(string.format("Record skipped: %s", reason))
		last_cache_skip_reason = reason
		if now then
			last_cache_skip_t = now
		end
	end
end

local markers = {}
local timer_markers = {}
local timer_state = {}
local debug_label_markers = {}
local debug_label_generation = 0
local debug_lines = { world = nil, object = nil }
local max_progress_distance = nil
local player_progress = {}
local boss_triggered = {}
local speedup_triggered = {}
local ritual_start_triggered = {}
local ritual_spawn_triggered = {}
local pacing_triggered = {}
local ambush_triggered = {}
local markers_dirty = true
local timer_dirty = true
local marker_generation = 0
local cleanup_done = false
local debug_text_manager = nil
local debug_text_world = nil
local last_debug_refresh_t = nil
local last_cache_update_t = -math.huge
local last_cache_record_enabled = nil
local last_cache_use_enabled = nil
local last_cache_use_offline_enabled = nil
local last_active_respawn_beacon = nil
local last_active_respawn_beacon_distance = nil
local respawn_waiting_active = false
local respawn_rewind_crossed = false
local respawn_rewind_lost = false
local debug_text_z_offset = 0
local get_player_name = nil
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

local function is_server()
	return Managers.state and Managers.state.game_session and Managers.state.game_session:is_server() or false
end

local function cache_use_enabled()
	local use_enabled = mod:get("cache_use_enabled")
	if use_enabled == nil then
		return true
	end
	return use_enabled
end

local function cache_use_offline_enabled()
	return mod:get("cache_use_offline_enabled") or false
end

local function cache_record_enabled()
	return mod:get("cache_record_enabled") or false
end

local function debug_text_mode()
	local mode = mod:get("debug_text_enabled")
	if mode == nil then
		return "off"
	end
	if mode == true then
		return "both"
	end
	if mode == false then
		return "off"
	end
	return mode
end

local function debug_text_enabled_mode(mode)
	return mode == "on"
		or mode == "labels"
		or mode == "distances"
		or mode == "both"
end

local function debug_text_show_labels(mode)
	return mode == "on" or mode == "labels" or mode == "both"
end

local function debug_text_show_distances(mode)
	return mode == "on" or mode == "distances" or mode == "both"
end

local function cache_reads_allowed()
	return cache_use_enabled() or cache_use_offline_enabled() or cache_record_enabled()
end

local function is_havoc_ritual_active()
	if not Managers or not Managers.state or not Managers.state.difficulty then
		return false
	end
	local difficulty = Managers.state.difficulty
	if not difficulty.get_parsed_havoc_data then
		return false
	end
	local ok, havoc_data = pcall(difficulty.get_parsed_havoc_data, difficulty)
	if not ok or not havoc_data or not havoc_data.circumstances then
		return false
	end
	for i = 1, #havoc_data.circumstances do
		if havoc_data.circumstances[i] == "mutator_havoc_chaos_rituals" then
			return true
		end
	end
	return false
end

local function can_record_cache()
	if is_server() then
		return true
	end
	local connection = Managers.connection
	if connection and connection.is_host then
		local ok, is_host = pcall(connection.is_host, connection)
		if ok and is_host then
			return true
		end
	end
	return false
end

local function get_mission_name()
	local mission_manager = Managers.state and Managers.state.mission
	if mission_manager and mission_manager.mission_name then
		local ok, mission_name = pcall(mission_manager.mission_name, mission_manager)
		if ok then
			return mission_name
		end
	end
	return nil
end

local function get_cache_root()
	local root = offline_cache.maps
	if not root then
		root = {}
		offline_cache.maps = root
	end
	return root
end

local function normalize_path(path)
	if not path or path == "" then
		return nil
	end
	path = path:gsub("/", "\\")
	path = path:gsub("\\+$", "")
	return path
end

local function mod_root_from_script()
	if not mod or type(mod.script_mod_path) ~= "function" then
		return nil
	end
	local ok, script_path = pcall(mod.script_mod_path, mod)
	if not ok or not script_path or script_path == "" then
		return nil
	end
	script_path = normalize_path(script_path)
	if not script_path then
		return nil
	end
	local trimmed = script_path:gsub("[/\\]scripts[/\\].-$", "")
	return normalize_path(trimmed)
end

local function script_mod_root()
	if not mod or type(mod.script_mod_path) ~= "function" then
		return nil
	end
	local ok, script_path = pcall(mod.script_mod_path, mod)
	if not ok or not script_path or script_path == "" then
		return nil
	end
	return normalize_path(script_path)
end

local function resolve_mod_root()
	local root = mod_root_from_script()
	if root then
		return root
	end
	if mod and mod._path and mod._path ~= "" then
		root = normalize_path(mod._path)
	end
	if mod and type(mod.get_mod_path) == "function" then
		local ok, value = pcall(mod.get_mod_path, mod)
		if ok and value and value ~= "" then
			root = normalize_path(value)
		end
	end
	if Mods and mod and type(mod.get_name) == "function" then
		local ok, name = pcall(mod.get_name, mod)
		local mod_name = ok and name or nil
		if mod_name and Mods.mods and Mods.mods[mod_name] then
			local mod_data = Mods.mods[mod_name]
			root = normalize_path(mod_data.path or mod_data._path)
		end
	end
	if not root then
		return nil
	end
	if not root:match("^%a:[/\\]") and not root:match("^\\\\") then
		if not root:lower():match("^mods[/\\]") then
			root = normalize_path("mods\\" .. root)
		end
	end
	return root
end

local function build_mod_path(relative_path)
	if not relative_path then
		return nil
	end
	local root = resolve_mod_root()
	if not root then
		return relative_path
	end
	local normalized_relative = relative_path:gsub("/", "\\")
	return root .. "\\" .. normalized_relative
end

local function get_appdata_cache_paths()
	if not _os or not _os.getenv then
		return nil, nil
	end
	local appdata = _os.getenv("APPDATA") or _os.getenv("AppData")
	if not appdata or appdata == "" then
		return nil, nil
	end
	local base = appdata .. "\\Fatshark\\Darktide\\RitualZones\\cache"
	local file = base .. "\\ritualzones_cache.lua"
	return base, file
end

local function get_mod_cache_paths()
	local dir = build_mod_path("cache")
	local file = build_mod_path("cache/ritualzones_cache.lua")
	if dir == "cache" or file == "cache\\ritualzones_cache.lua" then
		dir = CACHE_DIR_FALLBACK
		file = CACHE_FILE_FALLBACK
	end
	return dir, file
end

local function get_script_cache_paths()
	local root = script_mod_root()
	if not root then
		local mod_name = "RitualZones"
		if mod and type(mod.get_name) == "function" then
			local ok, name = pcall(mod.get_name, mod)
			if ok and name and name ~= "" then
				mod_name = name
			end
		end
		root = build_mod_path("scripts/mods/" .. mod_name)
		root = normalize_path(root)
	end
	if not root then
		root = normalize_path("mods\\RitualZones\\scripts\\mods\\RitualZones")
	end
	local dir = root .. "\\cache"
	local file = dir .. "\\ritualzones_cache.lua"
	return dir, file
end

local function get_primary_cache_paths()
	local app_dir, app_file = get_appdata_cache_paths()
	if app_dir and app_file then
		return app_dir, app_file
	end
	return get_mod_cache_paths()
end

local function mkdir(path)
	if not path or not _os or not _os.execute then
		return
	end
	local normalized = path:gsub("/", "\\")
	_os.execute('if not exist "' .. normalized .. '" mkdir "' .. normalized .. '"')
end

local function ensure_cache_dir()
	if not _io or not _os or not _os.execute then
		return
	end
	local cache_dir = select(1, get_primary_cache_paths())
	if cache_dir then
		mkdir(cache_dir)
	end
	local mod_dir = select(1, get_mod_cache_paths())
	if mod_dir then
		mkdir(mod_dir)
	end
	local script_dir = select(1, get_script_cache_paths())
	if script_dir then
		mkdir(script_dir)
	end
end

local function cache_file_exists()
	if not _io then
		return false
	end
	local _, cache_file = get_primary_cache_paths()
	local file = cache_file and _io.open(cache_file, "r")
	if file then
		file:close()
		return true
	end
	local _, mod_file = get_mod_cache_paths()
	local mod_handle = mod_file and _io.open(mod_file, "r")
	if mod_handle then
		mod_handle:close()
		return true
	end
	local _, script_file = get_script_cache_paths()
	local script_handle = script_file and _io.open(script_file, "r")
	if script_handle then
		script_handle:close()
		return true
	end
	return false
end

local distance_exists = nil
local add_distance_to_cache = nil
local add_entry_to_cache = nil
local is_finite_number = nil

local function sanitize_cache_content(content)
	if not content then
		return content, false
	end
	local cleaned = content
	cleaned = cleaned:gsub("^\239\187\191", "")
	cleaned = cleaned:gsub("%z", "")
	cleaned = cleaned:gsub("[\1-\8\11\12\14-\31\127]", "")
	cleaned = cleaned:gsub("%-?1%.#IND", "0")
	cleaned = cleaned:gsub("%-?1%.#INF", "0")
	cleaned = cleaned:gsub("%f[%w][Nn][Aa][Nn]%f[%W]", "0")
	cleaned = cleaned:gsub("%f[%w][Ii][Nn][Ff]%f[%W]", "0")
	cleaned = cleaned:gsub("([\r\n][\t ]*)end%s*=", "%1[\"end\"] =")
	return cleaned, cleaned ~= content
end

local function is_array_table(tbl)
	local count = 0
	for key, _ in pairs(tbl) do
		if type(key) ~= "number" then
			return false
		end
		if key > count then
			count = key
		end
	end
	return count == #tbl
end

local serialize_table = nil
local write_cache_file = nil
local RESERVED_KEYS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["goto"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

local function serialize_value(value, indent)
	local value_type = type(value)
	if value_type == "table" then
		return serialize_table(value, indent)
	elseif value_type == "string" then
		return string.format("%q", value)
	elseif value_type == "number" or value_type == "boolean" then
		if value_type == "number" and (value ~= value or value == math.huge or value == -math.huge) then
			return "0"
		end
		return tostring(value)
	end
	return "nil"
end

serialize_table = function(tbl, indent)
	indent = indent or 0
	local pad = string.rep(" ", indent)
	local next_pad = string.rep(" ", indent + 2)
	local lines = { "{" }

	if is_array_table(tbl) then
		for i = 1, #tbl do
			lines[#lines + 1] = next_pad .. serialize_value(tbl[i], indent + 2) .. ","
		end
	else
		local keys = {}
		for key, _ in pairs(tbl) do
			keys[#keys + 1] = key
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for i = 1, #keys do
			local key = keys[i]
			local key_type = type(key)
			local key_repr = nil
			if key_type == "string" and key:match("^[%a_][%w_]*$") and not RESERVED_KEYS[key] then
				key_repr = key
			else
				key_repr = "[" .. serialize_value(key, indent + 2) .. "]"
			end
			lines[#lines + 1] = next_pad .. key_repr .. " = " .. serialize_value(tbl[key], indent + 2) .. ","
		end
	end

	lines[#lines + 1] = pad .. "}"
	return table.concat(lines, "\n")
end

local ensure_cache_loaded = nil

local function load_cache_file()
	if cache_loaded or not _io or not _loadstring then
		return
	end

	local mod_dir, mod_file = get_mod_cache_paths()
	local script_dir, script_file = get_script_cache_paths()
	local app_dir, app_file = get_appdata_cache_paths()
	local tried_paths = {
		{ path = script_file, label = "script_cache" },
		{ path = mod_file, label = "mod_cache" },
		{ path = app_file, label = "appdata_cache" },
	}

	local loaded_any = false
	local parse_error = false
	local loaded_script = false
	local loaded_mod = false
	local loaded_app = false
	local merged_maps = {}

	local function get_or_create_entry(mission_name)
		local entry = merged_maps[mission_name]
		if not entry then
			entry = {
				version = CACHE.VERSION,
				path = {},
				ritual = {
					spawn = {},
					start = {},
					speedup = {},
				},
				boss = {},
				pacing = {},
				ambush = {},
				respawn = {},
			}
			merged_maps[mission_name] = entry
		end
		entry.path = entry.path or {}
		entry.ritual = entry.ritual or { spawn = {}, start = {}, speedup = {} }
		entry.ritual.spawn = entry.ritual.spawn or {}
		entry.ritual.start = entry.ritual.start or {}
		entry.ritual.speedup = entry.ritual.speedup or {}
		entry.boss = entry.boss or {}
		entry.pacing = entry.pacing or {}
		entry.ambush = entry.ambush or {}
		entry.respawn = entry.respawn or {}
		return entry
	end

	local function merge_entry(target, source)
		if not source then
			return
		end
		if source.path then
			if source.path.total and not target.path.total then
				target.path.total = source.path.total
			end
			if source.path.segments and not target.path.segments then
				target.path.segments = source.path.segments
			end
			if source.path.start and not target.path.start then
				target.path.start = source.path.start
			end
			if source.path["end"] and not target.path["end"] then
				target.path["end"] = source.path["end"]
			end
		end
		if source.ritual then
			local spawn = source.ritual.spawn or {}
			for i = 1, #spawn do
				add_distance_to_cache(target.ritual.spawn, spawn[i])
			end
			local start = source.ritual.start or {}
			for i = 1, #start do
				add_distance_to_cache(target.ritual.start, start[i])
			end
			local speedup = source.ritual.speedup or {}
			for i = 1, #speedup do
				add_distance_to_cache(target.ritual.speedup, speedup[i])
			end
		end
		local boss = source.boss or {}
		for i = 1, #boss do
			local item = boss[i]
			if type(item) == "table" then
				add_entry_to_cache(target.boss, item.distance, item.label)
			else
				add_entry_to_cache(target.boss, item, nil)
			end
		end
		local pacing = source.pacing or {}
		for i = 1, #pacing do
			local item = pacing[i]
			if type(item) == "table" then
				add_entry_to_cache(target.pacing, item.distance, item.label)
			else
				add_entry_to_cache(target.pacing, item, nil)
			end
		end
		local ambush = source.ambush or {}
		for i = 1, #ambush do
			local item = ambush[i]
			if type(item) == "table" then
				add_entry_to_cache(target.ambush, item.distance, item.label)
			else
				add_entry_to_cache(target.ambush, item, nil)
			end
		end
		local respawn = source.respawn or {}
		for i = 1, #respawn do
			add_distance_to_cache(target.respawn, respawn[i])
		end
	end

	for i = 1, #tried_paths do
		local path = tried_paths[i].path
		local label = tried_paths[i].label
		if path then
			local file = _io.open(path, "r")
			if file then
				local content = file:read("*all")
				file:close()
				local cleaned, changed = sanitize_cache_content(content)
				if changed then
					cache_debug(string.format("Sanitized cache content (%s)", tostring(label)))
				end
				local chunk, err = _loadstring(cleaned, path)
				if chunk then
					local ok, result = pcall(chunk)
					if ok and type(result) == "table" and type(result.maps) == "table" then
						for mission_name, data in pairs(result.maps) do
							local entry = get_or_create_entry(mission_name)
							merge_entry(entry, data)
						end
						loaded_any = true
						if label == "script_cache" then
							loaded_script = true
						elseif label == "mod_cache" then
							loaded_mod = true
						elseif label == "appdata_cache" then
							loaded_app = true
						end
					else
						parse_error = true
						cache_debug(string.format("Cache load failed (%s): %s", tostring(label), tostring(result)))
					end
				else
					parse_error = true
					cache_debug(string.format("Cache load failed (%s): %s", tostring(label), tostring(err)))
				end
			end
		end
	end

	if loaded_any then
		offline_cache.version = CACHE.VERSION
		offline_cache.maps = merged_maps
		cache_load_failed = false
	else
		cache_load_failed = parse_error
	end
	cache_loaded = true
	if loaded_any then
		write_cache_file()
		local map_count = 0
		for _ in pairs(merged_maps) do
			map_count = map_count + 1
		end
		cache_debug(string.format("Loaded cache (maps=%d, script=%s, mod=%s, appdata=%s)", map_count, tostring(loaded_script), tostring(loaded_mod), tostring(loaded_app)))
	else
		if parse_error then
			cache_debug("Cache load failed (parse error)")
		else
			cache_debug("No cache data loaded from disk")
		end
	end
end

write_cache_file = function()
	if not _io then
		return
	end
	if not cache_reads_allowed() and not cache_runtime_dirty then
		cache_debug("Cache write skipped (disabled)")
		return
	end
	ensure_cache_loaded()
	if cache_load_failed and cache_file_exists() and not cache_runtime_dirty then
		return
	end
	ensure_cache_dir()
	local function write_to(path, label)
		if not path then
			cache_debug(string.format("Skip write (%s): no path", label or "unknown"))
			return false
		end
		local file = _io.open(path, "w")
		if not file then
			cache_debug(string.format("Write failed (%s): %s", label or "unknown", tostring(path)))
			return false
		end
		file:write("-- RitualZones cache\nreturn ")
		file:write(serialize_table(offline_cache, 0))
		file:write("\n")
		file:close()
		cache_debug(string.format("Write ok (%s): %s", label or "unknown", tostring(path)))
		return true
	end

	local _, primary_file = get_primary_cache_paths()
	local _, mod_file = get_mod_cache_paths()
	local _, script_file = get_script_cache_paths()
	local wrote_primary = write_to(primary_file, "appdata")
	local wrote_mod = write_to(mod_file, "mod")
	local wrote_script = write_to(script_file, "script")
	if not wrote_primary and not wrote_mod and not wrote_script then
		return
	end
	cache_runtime_dirty = false
end

ensure_cache_loaded = function()
	if cache_loaded then
		return
	end
	if not cache_reads_allowed() then
		cache_debug("Cache load skipped (disabled)")
		return
	end
	load_cache_file()
end

local function ensure_cache_entry(mission_name)
	ensure_cache_loaded()
	offline_cache.version = CACHE.VERSION
	local root = get_cache_root()
	local entry = root[mission_name]
	local created = false
	if not entry or entry.version ~= CACHE.VERSION then
		entry = {
			version = CACHE.VERSION,
			path = {},
			ritual = {
				spawn = {},
				start = {},
				speedup = {},
			},
			boss = {},
			pacing = {},
			ambush = {},
			respawn = {},
		}
		root[mission_name] = entry
		created = true
	end
	entry.path = entry.path or {}
	entry.ritual = entry.ritual or { spawn = {}, start = {}, speedup = {} }
	entry.ritual.spawn = entry.ritual.spawn or {}
	entry.ritual.start = entry.ritual.start or {}
	entry.ritual.speedup = entry.ritual.speedup or {}
	entry.boss = entry.boss or {}
	entry.pacing = entry.pacing or {}
	entry.ambush = entry.ambush or {}
	entry.respawn = entry.respawn or {}
	return entry, created
end

local function refresh_cache_from_disk()
	if not cache_reads_allowed() then
		cache_debug("Cache refresh skipped (disabled)")
		return
	end
	if cache_runtime_dirty then
		write_cache_file()
	end
	cache_loaded = false
	cache_load_failed = false
	load_cache_file()
end

local function vector_to_table(vec)
	if not vec or not Vector3 or not Vector3.x then
		return nil
	end
	return { Vector3.x(vec), Vector3.y(vec), Vector3.z(vec) }
end

local function table_distance(a, b)
	if not a or not b then
		return math.huge
	end
	local dx = (a[1] or 0) - (b[1] or 0)
	local dy = (a[2] or 0) - (b[2] or 0)
	local dz = (a[3] or 0) - (b[3] or 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function update_path_signature(entry, path_total)
	if not entry or not path_total or not is_finite_number(path_total) then
		return false
	end
	local updated = false
	if entry.path.total ~= path_total then
		entry.path.total = path_total
		updated = true
	end
	local main_path = Managers.state and Managers.state.main_path
	local segments = main_path and main_path._main_path_segments
	if segments and entry.path.segments ~= #segments then
		entry.path.segments = #segments
		updated = true
	end
	local start_pos = MainPathQueries.position_from_distance(0)
	if start_pos then
		local start_tbl = vector_to_table(start_pos)
		if start_tbl and table_distance(start_tbl, entry.path.start) > 0.1 then
			entry.path.start = start_tbl
			updated = true
		end
	end
	local end_pos = MainPathQueries.position_from_distance(path_total)
	if end_pos then
		local end_tbl = vector_to_table(end_pos)
		if end_tbl and table_distance(end_tbl, entry.path["end"]) > 0.1 then
			entry.path["end"] = end_tbl
			updated = true
		end
	end
	return updated
end

distance_exists = function(list, distance, tolerance, label)
	if not list or not distance then
		return false
	end
	for i = 1, #list do
		local item = list[i]
		local item_distance = type(item) == "table" and item.distance or item
		local item_label = type(item) == "table" and item.label or nil
		if (not label or label == item_label) and item_distance ~= nil then
			if math.abs(item_distance - distance) <= tolerance then
				return true
			end
		end
	end
	return false
end

add_distance_to_cache = function(list, distance, tolerance)
	if not distance or not list or not is_finite_number(distance) then
		return false
	end
	if distance_exists(list, distance, tolerance or CACHE.DISTANCE_TOLERANCE) then
		return false
	end
	list[#list + 1] = distance
	return true
end

add_entry_to_cache = function(list, distance, label, tolerance)
	if not distance or not list or not is_finite_number(distance) then
		return false
	end
	if distance_exists(list, distance, tolerance or CACHE.DISTANCE_TOLERANCE, label) then
		return false
	end
	list[#list + 1] = {
		distance = distance,
		label = label,
	}
	return true
end

local function get_cache_entry(mission_name, path_total)
	ensure_cache_loaded()
	if not mission_name then
		return nil
	end
	local root = offline_cache.maps
	if not root then
		return nil
	end
	local entry = root[mission_name]
	if not entry or entry.version ~= CACHE.VERSION then
		return nil
	end
	local cached_total = entry.path and entry.path.total
	if cached_total and path_total then
		if math.abs(cached_total - path_total) > CACHE.PATH_TOLERANCE then
			return nil
		end
	end
	return entry
end

local function cached_path_triggers(entry)
	if not entry or not entry.ritual then
		return {}
	end
	local triggers = {}
	local spawn = entry.ritual.spawn or {}
	local start = entry.ritual.start or {}
	local speedup = entry.ritual.speedup or {}
	for i = 1, #spawn do
		triggers[#triggers + 1] = { id = "spawn_trigger", distance = spawn[i], color = "red" }
	end
	for i = 1, #start do
		triggers[#triggers + 1] = { id = "ritual_start", distance = start[i], color = "orange" }
	end
	for i = 1, #speedup do
		triggers[#triggers + 1] = { id = "ritual_speedup", distance = speedup[i], color = "yellow" }
	end
	return triggers
end

local function cached_boss_triggers(entry)
	local list = {}
	if not entry or not entry.boss then
		return list
	end
	for i = 1, #entry.boss do
		local item = entry.boss[i]
		if item and item.distance then
			list[#list + 1] = {
				distance = item.distance,
				label = item.label,
				key = string.format("boss_cache:%s:%.2f", tostring(item.label), item.distance),
			}
		end
	end
	return list
end

local function cached_pacing_triggers(entry)
	local list = {}
	if not entry or not entry.pacing then
		return list
	end
	for i = 1, #entry.pacing do
		local item = entry.pacing[i]
		if item and item.distance then
			list[#list + 1] = {
				distance = item.distance,
				label = item.label,
				key = string.format("pacing_cache:%s:%.2f", tostring(item.label), item.distance),
			}
		end
	end
	return list
end

local function cached_ambush_triggers(entry)
	local list = {}
	if not entry or not entry.ambush then
		return list
	end
	for i = 1, #entry.ambush do
		local item = entry.ambush[i]
		if item and item.distance then
			list[#list + 1] = {
				distance = item.distance,
				label = item.label,
				key = string.format("ambush_cache:%s:%.2f", tostring(item.label), item.distance),
			}
		end
	end
	return list
end

local function cached_respawn_distances(entry)
	if not entry or not entry.respawn then
		return {}
	end
	return entry.respawn
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

is_finite_number = function(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

get_priority_respawn_beacon_unit = function(respawn_system)
	if not respawn_system then
		return nil
	end
	local unit = respawn_system._priority_respawn_beacon
		or respawn_system._priority_beacon
		or respawn_system._priority_respawn_beacon_unit
		or respawn_system._priority_beacon_unit
		or respawn_system.priority_respawn_beacon
		or respawn_system.priority_beacon
	if unit then
		return unit
	end
	local data = respawn_system._priority_respawn_beacon_data or respawn_system._priority_beacon_data
	if data and data.unit then
		return data.unit
	end
	return nil
end

get_priority_respawn_beacon_distance = function(respawn_system, priority_unit)
	if not respawn_system then
		return nil
	end
	local direct = respawn_system._priority_respawn_beacon_distance
		or respawn_system._priority_beacon_distance
		or respawn_system._priority_respawn_beacon_main_path_distance
		or respawn_system._priority_beacon_main_path_distance
		or respawn_system.priority_respawn_beacon_distance
		or respawn_system.priority_beacon_distance
	if is_finite_number(direct) then
		return direct
	end
	local data = respawn_system._priority_respawn_beacon_data or respawn_system._priority_beacon_data
	if data and is_finite_number(data.distance) then
		return data.distance
	end
	if priority_unit then
		local lookup = respawn_system._beacon_main_path_distance_lookup
		if lookup then
			local distance = lookup[priority_unit]
			if is_finite_number(distance) then
				return distance
			end
		end
		local beacon_data = respawn_system._beacon_main_path_data
		if beacon_data then
			for i = 1, #beacon_data do
				local row = beacon_data[i]
				if row and row.unit == priority_unit and is_finite_number(row.distance) then
					return row.distance
				end
			end
		end
	end
	return nil
end

is_twins_spawned = function()
	local mutator_manager = Managers.state and Managers.state.mutator
	local mutators = mutator_manager and mutator_manager._mutators
	local mutator_twins = mutators and mutators.mutator_monster_havoc_twins
	if not mutator_twins then
		return false
	end
	local alive = mutator_twins._alive_monsters
	if alive and #alive > 0 then
		return true
	end
	return false
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

local function within_draw_distance(position, settings, state)
	local max_distance = settings and settings.debug_draw_distance or 0
	if not max_distance or max_distance <= 0 then
		return true
	end
	local player_position = state and state.player_position
	if not player_position then
		return true
	end
	local distance = safe_distance(position, player_position)
	if not distance then
		return true
	end
	return distance <= max_distance
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
	local rgb = CONST.RING_COLORS[color_name] or CONST.RING_COLORS.red
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

local function player_can_progress(unit)
	if not unit or not unit_is_alive(unit) then
		return false
	end
	if not PlayerUnitStatus or not PlayerUnitStatus.is_disabled then
		return true
	end
	local unit_data_extension =
		ScriptUnit.has_extension(unit, "unit_data_system") and ScriptUnit.extension(unit, "unit_data_system")
	if not unit_data_extension or not unit_data_extension.read_component then
		return true
	end
	local ok, character_state_component = pcall(unit_data_extension.read_component, unit_data_extension, "character_state")
	if not ok or not character_state_component then
		return true
	end
	local is_disabled = PlayerUnitStatus.is_disabled(character_state_component)
	return not is_disabled
end

local function collect_player_progress(path_total)
	local players_manager = Managers.player
	if not players_manager then
		return {}, nil, nil, nil
	end
	local players = players_manager:players()
	local local_player = players_manager:local_player(1)
	local entries = {}
	local leader_player = nil
	local leader_distance = nil
	local seen = {}

	for _, player in pairs(players) do
		seen[player] = true
		local entry = player_progress[player]
		if not entry then
			entry = { distance = nil, alive = false }
			player_progress[player] = entry
		end

		local unit = player.player_unit
		local alive_for_progress = unit and player_can_progress(unit)
		if alive_for_progress then
			local position = get_unit_position(unit)
			local distance = position and (get_position_travel_distance(position) or get_unit_travel_distance(unit))
			if distance and is_finite_number(distance) then
				if path_total then
					distance = math.max(0, math.min(distance, path_total))
				end
				entry.distance = distance
				entry.alive = true
			end
		end
		entry.alive = alive_for_progress and entry.distance ~= nil

		if entry.distance then
			entries[#entries + 1] = {
				player = player,
				unit = unit,
				distance = entry.distance,
				alive = entry.alive,
				is_local = player == local_player,
			}
			if entry.alive and (not leader_distance or entry.distance > leader_distance) then
				leader_distance = entry.distance
				leader_player = player
			end
		end
	end

	for player, _ in pairs(player_progress) do
		if not seen[player] then
			player_progress[player] = nil
		end
	end

	local local_distance = nil
	if local_player then
		local entry = player_progress[local_player]
		if entry and entry.distance then
			local_distance = entry.distance
		end
	end

	return entries, leader_distance, leader_player, local_distance
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
	if not distance or not is_finite_number(distance) then
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

local function get_default_side_id()
	local side_system = Managers.state.extension and Managers.state.extension:system("side_system")
	if not side_system or not side_system.get_default_player_side_name then
		return nil
	end
	local default_side_name = side_system:get_default_player_side_name()
	local player_side = side_system:get_side_from_name(default_side_name)
	return player_side and player_side.side_id
end

local function collect_ambush_triggers()
	local horde_manager = Managers.state.horde
	if not horde_manager or not horde_manager.horde_positions then
		return {}
	end
	local positions = horde_manager:horde_positions("ambush_horde")
	if not positions then
		return {}
	end
	local triggers = {}
	local seen = {}
	for i = 1, #positions do
		local position = positions[i]
		local distance = position and get_position_travel_distance(position)
		if distance and is_finite_number(distance) then
			local key = string.format("ambush:%.2f", distance)
			if not seen[key] then
				seen[key] = true
				triggers[#triggers + 1] = {
					distance = distance,
					label = "Ambush Horde Trigger",
				}
			end
		end
	end
	return triggers
end

local function get_backtrack_trigger_distance(path_total)
	local main_path = Managers.state.main_path
	if not main_path or not main_path.furthest_travel_distance then
		return nil
	end
	local side_id = get_default_side_id()
	if not side_id then
		return nil
	end
	local ok, furthest = pcall(main_path.furthest_travel_distance, main_path, side_id)
	if not ok or not furthest then
		return nil
	end
	local trigger_distance = furthest - CONST.BACKTRACK_ALLOWED_DISTANCE
	if path_total then
		trigger_distance = math.max(0, math.min(trigger_distance, path_total))
	end
	return trigger_distance
end

local function collect_respawn_progress_distances()
	local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
	local distances = {}
	local seen = {}

	local function add_distance(distance)
		if not distance then
			return
		end
		local progress = math.max(0, distance - CONST.RESPAWN_BEACON_AHEAD_DISTANCE)
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

local function collect_respawn_beacon_entries(path_total, fallback_progress)
	local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
	local entries = {}
	local seen = {}
	local priority_unit = get_priority_respawn_beacon_unit(respawn_system)

	local function add_entry(distance, position, unit, is_priority)
		if not distance or not is_finite_number(distance) then
			return
		end
		if path_total then
			distance = math.max(0, math.min(distance, path_total))
		end
		local key = string.format("beacon:%.2f", distance)
		if seen[key] then
			return
		end
		seen[key] = true
		entries[#entries + 1] = {
			distance = distance,
			position = position,
			unit = unit,
			priority = is_priority or false,
		}
	end

	if respawn_system then
		local beacon_data = respawn_system._beacon_main_path_data
		if beacon_data then
			for i = 1, #beacon_data do
				local data = beacon_data[i]
				local unit = data and data.unit
				local distance = data and data.distance
				local is_priority = data
					and (data.priority or data.is_priority or data.is_priority_beacon or data.is_priority_respawn_beacon)
					or (unit and priority_unit and unit == priority_unit)
				local position = nil
				if unit and Unit and Unit.world_position then
					local ok, value = pcall(Unit.world_position, unit, 1)
					if ok then
						position = value
					end
				end
				if not position and distance then
					position = MainPathQueries.position_from_distance(distance)
				end
				add_entry(distance, position, unit, is_priority)
			end
		else
			local lookup = respawn_system._beacon_main_path_distance_lookup
			if lookup then
				for unit, distance in pairs(lookup) do
					local is_priority = unit and priority_unit and unit == priority_unit
					local position = nil
					if unit and Unit and Unit.world_position then
						local ok, value = pcall(Unit.world_position, unit, 1)
						if ok then
							position = value
						end
					end
					if not position and distance then
						position = MainPathQueries.position_from_distance(distance)
					end
					add_entry(distance, position, unit, is_priority)
				end
			end
		end
	end

	if #entries == 0 and fallback_progress then
		for i = 1, #fallback_progress do
			local distance = fallback_progress[i] + CONST.RESPAWN_BEACON_AHEAD_DISTANCE
			local position = MainPathQueries.position_from_distance(distance)
			add_entry(distance, position, nil, false)
		end
	end

	if #entries == 0 then
		local component_system = Managers.state.extension and Managers.state.extension:system("component_system")
		if component_system and component_system.get_units_from_component_name then
			local units = component_system:get_units_from_component_name("RespawnBeacon")
			if units then
				for i = 1, #units do
					local unit = units[i]
					if unit and Unit and Unit.world_position then
						local ok, position = pcall(Unit.world_position, unit, 1)
						if ok and position then
							local distance = get_position_travel_distance(position)
							add_entry(distance, position, unit, unit == priority_unit)
						end
					end
				end
			end
		end
	end

	return entries
end

local function is_player_hogtied(player_unit)
	if not player_unit or not unit_is_alive(player_unit) then
		return false
	end
	if not PlayerUnitStatus or not PlayerUnitStatus.is_hogtied then
		return false
	end
	if not ScriptUnit.has_extension(player_unit, "unit_data_system") then
		return false
	end
	local unit_data_extension = ScriptUnit.extension(player_unit, "unit_data_system")
	if not unit_data_extension or not unit_data_extension.read_component then
		return false
	end
	local ok, character_state_component =
		pcall(unit_data_extension.read_component, unit_data_extension, "character_state")
	if not ok or not character_state_component then
		return false
	end
	return PlayerUnitStatus.is_hogtied(character_state_component)
end

local function has_hogtied_players()
	local players_manager = Managers.player
	if not players_manager then
		return false
	end
	local players = players_manager:players()
	for _, player in pairs(players) do
		local unit = player and player.player_unit
		if unit and is_player_hogtied(unit) then
			return true
		end
	end
	return false
end

local function get_behind_player_distance()
	local main_path = Managers.state.main_path
	if not main_path or not main_path.behind_unit then
		return nil
	end
	local side_id = get_default_side_id()
	if not side_id then
		return nil
	end
	local ok, _, behind_distance = pcall(main_path.behind_unit, main_path, side_id)
	if not ok then
		return nil
	end
	return behind_distance
end

local function has_players_waiting_to_spawn()
	local game_mode_manager = Managers.state and Managers.state.game_mode
	local game_mode = game_mode_manager and game_mode_manager.game_mode and game_mode_manager:game_mode()
	local players_manager = Managers.player
	local players = players_manager and players_manager:players()
	local time_manager = Managers.time
	local now = nil
	if time_manager and time_manager.time then
		local ok, value = pcall(time_manager.time, time_manager, "gameplay")
		if ok then
			now = value
		end
	end
	local waiting_to_spawn = false
	local min_remaining = nil

	if game_mode and game_mode.player_time_until_spawn and players and now then
		for _, player in pairs(players) do
			local unit = player and player.player_unit
			if not unit or not unit_is_alive(unit) then
				local ok_time, ready_time = pcall(game_mode.player_time_until_spawn, game_mode, player)
				if ok_time and ready_time and is_finite_number(ready_time) then
					local remaining = ready_time - now
					if remaining < 0 then
						remaining = 0
					end
					waiting_to_spawn = true
					if not min_remaining or remaining < min_remaining then
						min_remaining = remaining
					end
				end
			end
		end
	end

	local spawn_manager = Managers.state and Managers.state.player_unit_spawn
	if spawn_manager and spawn_manager.has_players_waiting_to_spawn then
		local ok, waiting = pcall(spawn_manager.has_players_waiting_to_spawn, spawn_manager)
		if ok and waiting then
			waiting_to_spawn = true
			if min_remaining == nil then
				min_remaining = 0
			end
		end
	end

	return waiting_to_spawn, min_remaining
end

local function collect_hogtied_move_triggers(path_total, mode)
	local players_manager = Managers.player
	if not players_manager then
		return {}
	end
	if mode == "off" then
		return {}
	end
	local behind_distance = get_behind_player_distance()
	local entries = {}
	local seen = {}
	local players = players_manager:players()

	for _, player in pairs(players) do
		local unit = player.player_unit
		local include = false
		if mode == "always" then
			include = unit and unit_is_alive(unit)
		else
			include = is_player_hogtied(unit)
		end
		if include then
			local position = get_unit_position(unit)
			local distance = position and (get_position_travel_distance(position) or get_unit_travel_distance(unit))
			if distance and is_finite_number(distance) then
				local trigger_distance = distance + CONST.RESPAWN_MOVE_TRIGGER_DISTANCE
				if path_total then
					trigger_distance = math.max(0, math.min(trigger_distance, path_total))
				end
				local key = string.format("rescue_move:%.2f", trigger_distance)
				if not seen[key] then
					seen[key] = true
					local passed = behind_distance and behind_distance > trigger_distance
					local label = "Rescue Move Trigger"
					local name = get_player_name(player)
					if name then
						label = string.format("Rescue Move Trigger (%s)", name)
					end
					entries[#entries + 1] = {
						distance = trigger_distance,
						label = label,
						passed = passed,
					}
				end
			end
		end
	end

	return entries
end

collect_priority_move_triggers = function(path_total, mode, priority_unit)
	local players_manager = Managers.player
	if not players_manager or not priority_unit then
		return {}
	end
	if mode == "off" then
		return {}
	end
	local behind_distance = get_behind_player_distance()
	local entries = {}
	local seen = {}
	local players = players_manager:players()

	for _, player in pairs(players) do
		local unit = player.player_unit
		local include = false
		if mode == "always" then
			include = unit and unit_is_alive(unit)
		else
			include = is_player_hogtied(unit)
		end
		if include then
			local position = get_unit_position(unit)
			local distance = position and (get_position_travel_distance(position) or get_unit_travel_distance(unit))
			if distance and is_finite_number(distance) then
				local trigger_distance = distance + CONST.RESPAWN_MOVE_TRIGGER_DISTANCE
				if path_total then
					trigger_distance = math.max(0, math.min(trigger_distance, path_total))
				end
				local key = string.format("priority_move:%.2f", trigger_distance)
				if not seen[key] then
					seen[key] = true
					local passed = behind_distance and behind_distance > trigger_distance
					local label = "Priority Move Trigger"
					local name = get_player_name(player)
					if name then
						label = string.format("Priority Move Trigger (%s)", name)
					end
					entries[#entries + 1] = {
						distance = trigger_distance,
						label = label,
						passed = passed,
					}
				end
			end
		end
	end

	return entries
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

local function record_offline_cache(ritual_units, t)
	if not mod:get("cache_record_enabled") then
		cache_debug_skip("record disabled", t, 2)
		return
	end
	if not can_record_cache() then
		cache_debug_skip("not server/host", t, 2)
		return
	end
	if not is_gameplay_state() then
		cache_debug_skip("not in gameplay state", t, 2)
		return
	end
	local mission_name = get_mission_name()
	if not mission_name or mission_name == "hub_ship" then
		cache_debug_skip("invalid mission name", t, 2)
		return
	end
	if mission_name ~= cache_record_mission then
		cache_record_mission = mission_name
		cache_record_count = 0
	end
	if cache_record_count >= CACHE.MAX_RECORDS_PER_MISSION then
		cache_debug_skip("record limit reached", t, 5)
		return
	end
	ensure_cache_loaded()
	if not cache_file_exists() then
		write_cache_file()
	end
	local main_path_ready = true
	if MainPathQueries.is_main_path_registered and not MainPathQueries.is_main_path_registered() then
		main_path_ready = false
	end
	local update_interval = mod:get("cache_update_interval") or CACHE.UPDATE_INTERVAL
	if update_interval < 0.1 then
		update_interval = 0.1
	end
	if t and (t - last_cache_update_t) < update_interval then
		cache_debug_skip("update interval", t, update_interval)
		return
	end
	last_cache_update_t = t or 0

	local entry, created = ensure_cache_entry(mission_name)
	local updated = created
	if mission_name ~= last_recorded_mission then
		last_recorded_mission = mission_name
		updated = true
	end
	if main_path_ready then
		local path_total = MainPathQueries.total_path_distance and MainPathQueries.total_path_distance()
		if path_total then
			updated = update_path_signature(entry, path_total) or updated
		end

		local ritual_triggers = collect_path_triggers(ritual_units or {})
		for i = 1, #ritual_triggers do
			local trigger = ritual_triggers[i]
			if trigger.id == "spawn_trigger" then
				updated = add_distance_to_cache(entry.ritual.spawn, trigger.distance) or updated
			elseif trigger.id == "ritual_start" then
				updated = add_distance_to_cache(entry.ritual.start, trigger.distance) or updated
			elseif trigger.id == "ritual_speedup" then
				updated = add_distance_to_cache(entry.ritual.speedup, trigger.distance) or updated
			end
		end

		local boss_triggers = collect_boss_triggers({
			mutator = true,
			twins = true,
			boss_patrols = true,
		})
		for i = 1, #boss_triggers do
			local trigger = boss_triggers[i]
			updated = add_entry_to_cache(entry.boss, trigger.distance, trigger.label) or updated
		end

		local pacing_triggers = collect_pacing_spawn_triggers()
		for i = 1, #pacing_triggers do
			local trigger = pacing_triggers[i]
			updated = add_entry_to_cache(entry.pacing, trigger.distance, trigger.label) or updated
		end

		local ambush_triggers = collect_ambush_triggers()
		for i = 1, #ambush_triggers do
			local trigger = ambush_triggers[i]
			updated = add_entry_to_cache(entry.ambush, trigger.distance, trigger.label) or updated
		end

		local respawn_distances = collect_respawn_progress_distances()
		for i = 1, #respawn_distances do
			updated = add_distance_to_cache(entry.respawn, respawn_distances[i]) or updated
		end
	elseif updated then
		cache_debug("Main path not registered yet; deferring path capture")
	else
		cache_debug_skip("main path not registered", t, 2)
	end

	if updated then
		entry.updated_at = os.time()
		cache_runtime_dirty = true
		write_cache_file()
		cache_debug(string.format("Updated cache for %s", tostring(mission_name)))
		cache_record_count = cache_record_count + 1
	else
		cache_debug_skip("no new data", t, update_interval)
	end
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

local function clear_debug_label_markers()
	if not Managers.event then
		debug_label_markers = {}
		return
	end

	for key, entry in pairs(debug_label_markers) do
		if entry.id then
			Managers.event:trigger("remove_world_marker", entry.id)
		end
		debug_label_markers[key] = nil
	end
end

local function begin_debug_label_markers()
	debug_label_generation = debug_label_generation + 1
end

local function finalize_debug_label_markers()
	if not Managers.event then
		debug_label_markers = {}
		return
	end
	for key, entry in pairs(debug_label_markers) do
		if entry.generation ~= debug_label_generation then
			if entry.id then
				Managers.event:trigger("remove_world_marker", entry.id)
			end
			debug_label_markers[key] = nil
		end
	end
end

local function build_debug_label_key(text, position)
	if not position then
		return tostring(text or "")
	end
	local base = tostring(text or "")
	base = base:gsub("%s%[[^%]]+%]$", "")
	local step = 0.1
	local x = math.floor((position.x or 0) / step + 0.5) * step
	local y = math.floor((position.y or 0) / step + 0.5) * step
	local z = math.floor((position.z or 0) / step + 0.5) * step
	return string.format("%s@%.1f,%.1f,%.1f", base, x, y, z)
end

local function ensure_debug_label_marker(key, text, position, size, color)
	if not Managers.event or not RitualZonesDebugLabelMarker then
		return
	end
	local entry = debug_label_markers[key]
	if entry and entry.id and entry.generation == debug_label_generation then
		entry.data.text = text
		entry.data.color = color
		entry.data.text_size = size
		return
	end

	if entry and entry.id then
		Managers.event:trigger("remove_world_marker", entry.id)
	end

	local data = {
		text = text,
		color = color,
		text_size = size,
	}
	local new_entry = {
		id = nil,
		data = data,
		generation = debug_label_generation,
	}
	debug_label_markers[key] = new_entry

	Managers.event:trigger("add_world_marker_position", RitualZonesDebugLabelMarker.name, position, function(marker_id)
		new_entry.id = marker_id
	end, data)
end

local function ensure_marker(unit, icon_size, color)
	local entry = markers[unit]
	if entry and entry.id and entry.generation == marker_generation then
		entry.data.icon_size = icon_size
		entry.data.color = color
		entry.data.icon = CONST.MARKER_ICON
		return
	end

	if entry and entry.id and Managers.event then
		Managers.event:trigger("remove_world_marker", entry.id)
	end

	local data = {
		icon = CONST.MARKER_ICON,
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

	local through_walls = mod:get("marker_through_walls_enabled") or false
	if RitualZonesMarker then
		RitualZonesMarker.check_line_of_sight = not through_walls
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
			ensure_marker(unit, icon_size, CONST.MARKER_COLOR)
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

	local through_walls = mod:get("marker_through_walls_enabled") or false
	if RitualZonesTimerMarker then
		RitualZonesTimerMarker.check_line_of_sight = not through_walls
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
	local base_label = label
	if base_label and base_label:find(" [", 1, true) then
		base_label = base_label:gsub("%s%[[^%]]+%]$", "")
	end
	local offset = CONST.DEBUG_TEXT_OFFSETS[base_label]
	if not offset and label and string.find(label, "Progress (", 1, true) then
		offset = CONST.DEBUG_TEXT_OFFSETS["Progress"]
	end
	if not offset and label and string.find(label, "Pacing Spawn:", 1, true) then
		offset = CONST.DEBUG_TEXT_OFFSETS["Pacing Spawn"]
	end
	if not offset and label and string.find(label, "Rescue Move Trigger", 1, true) then
		offset = CONST.DEBUG_TEXT_OFFSETS["Rescue Move Trigger"]
	end
	if not offset and label and string.find(label, "Priority Move Trigger", 1, true) then
		offset = CONST.DEBUG_TEXT_OFFSETS["Priority Move Trigger"]
	end
	if not offset and label and string.find(label, "Respawn Beacon", 1, true) then
		offset = CONST.DEBUG_TEXT_OFFSETS["Respawn Beacon"]
	end
	if not offset then
		return nil
	end
	local s = scale or 1
	return Vector3(offset[1] * s, offset[2] * s, offset[3] + debug_text_z_offset)
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
	if not position or not Vector3 then
		return
	end
	if mod:get("debug_labels_through_walls") then
		local key = build_debug_label_key(text, position)
		ensure_debug_label_marker(key, text, position, size, color_rgb)
		return
	end
	if not debug_text then
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

local function strip_rich_text(text)
	if not text then
		return text
	end
	local cleaned = text:gsub("{#.-}", "")
	cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
	return cleaned
end

get_player_name = function(player)
	if not player or type(player.name) ~= "function" then
		return nil
	end
	local ok, name = pcall(player.name, player)
	if ok and name and name ~= "" then
		return strip_rich_text(name)
	end
	return nil
end

local draw_main_path = nil
local draw_sphere = nil
local draw_gate_plane = nil
local format_debug_label = nil

local function get_debug_settings()
	local settings = {}
	settings.gate_enabled = mod:get("gate_enabled")
	if settings.gate_enabled == nil then
		settings.gate_enabled = true
	end
	settings.path_enabled = mod:get("path_enabled")
	settings.debug_text_mode = debug_text_mode()
	settings.debug_text_enabled = debug_text_enabled_mode(settings.debug_text_mode)
	settings.debug_text_show_labels = debug_text_show_labels(settings.debug_text_mode)
	settings.debug_text_show_distances = debug_text_show_distances(settings.debug_text_mode)
	settings.debug_distance_enabled = settings.debug_text_show_distances
	settings.debug_text_size = mod:get("debug_text_size") or 0.2
	settings.debug_text_height = mod:get("debug_text_height") or 0.4
	settings.debug_text_z_offset = mod:get("debug_text_z_offset") or 0
	settings.debug_text_z_offset = math.floor(settings.debug_text_z_offset * 2 + 0.5) / 2
	debug_text_z_offset = settings.debug_text_z_offset
	settings.debug_draw_distance = mod:get("debug_draw_distance") or 0
	settings.debug_text_offset_scale = math.max(0.15, settings.debug_text_size * 2)
	settings.boss_trigger_spheres_enabled = mod:get("boss_trigger_spheres_enabled")
	settings.boss_mutator_triggers_enabled = mod:get("boss_mutator_triggers_enabled")
	settings.boss_twins_triggers_enabled = mod:get("boss_twins_triggers_enabled")
	settings.twins_ambush_triggers_mode = mod:get("twins_ambush_triggers_mode")
	settings.twins_spawn_triggers_mode = mod:get("twins_spawn_triggers_mode")
	settings.boss_patrol_triggers_enabled = mod:get("boss_patrol_triggers_enabled")
	settings.pacing_spawn_triggers_enabled = mod:get("pacing_spawn_triggers_enabled")
	settings.ambush_trigger_spheres_enabled = mod:get("ambush_trigger_spheres_enabled")
	settings.backtrack_trigger_sphere_enabled = mod:get("backtrack_trigger_sphere_enabled")
	settings.cache_use_enabled = mod:get("cache_use_enabled")
	settings.cache_use_offline_enabled = mod:get("cache_use_offline_enabled")
	settings.respawn_progress_enabled = mod:get("respawn_progress_enabled")
	settings.respawn_beacon_enabled = mod:get("respawn_beacon_enabled")
	settings.priority_beacon_enabled = mod:get("priority_beacon_enabled")
	settings.respawn_beacon_line_enabled = mod:get("respawn_beacon_line_enabled")
	settings.respawn_threshold_enabled = mod:get("respawn_threshold_enabled")
	settings.respawn_backline_enabled = mod:get("respawn_backline_enabled")
	settings.respawn_move_triggers_mode = mod:get("respawn_move_triggers_enabled")
	settings.priority_move_triggers_mode = mod:get("priority_move_triggers_enabled")
	settings.trigger_points_enabled = mod:get("trigger_points_enabled")
	settings.progress_point_enabled = mod:get("progress_point_enabled")
	settings.path_height = mod:get("path_height") or 0.15
	settings.progress_height = mod:get("progress_height") or 0.15
	settings.sphere_radius_scale = mod:get("sphere_radius_scale") or 1
	settings.gate_width = mod:get("gate_width") or 6
	settings.gate_height = mod:get("gate_height") or 8
	settings.gate_slices = mod:get("gate_slices") or 1
	if settings.sphere_radius_scale < 0.05 then
		settings.sphere_radius_scale = 0.05
	end
	settings.allow_live_data = is_server()
	if settings.debug_draw_distance < 0 then
		settings.debug_draw_distance = 0
	end
	if settings.boss_mutator_triggers_enabled == nil then
		settings.boss_mutator_triggers_enabled = true
	end
	if settings.boss_twins_triggers_enabled == nil then
		settings.boss_twins_triggers_enabled = true
	end
	if settings.twins_ambush_triggers_mode == nil then
		settings.twins_ambush_triggers_mode = "always"
	end
	if settings.twins_spawn_triggers_mode == nil then
		settings.twins_spawn_triggers_mode = "always"
	end
	if settings.boss_patrol_triggers_enabled == nil then
		settings.boss_patrol_triggers_enabled = true
	end
	if settings.twins_spawn_triggers_mode ~= "always"
		and settings.twins_spawn_triggers_mode ~= "off"
		and settings.twins_spawn_triggers_mode ~= "until_spawn" then
		settings.twins_spawn_triggers_mode = "always"
	end
	if settings.twins_ambush_triggers_mode ~= "always"
		and settings.twins_ambush_triggers_mode ~= "off"
		and settings.twins_ambush_triggers_mode ~= "until_spawn" then
		settings.twins_ambush_triggers_mode = "always"
	end
	if settings.pacing_spawn_triggers_enabled == nil then
		settings.pacing_spawn_triggers_enabled = false
	end
	if settings.ambush_trigger_spheres_enabled == nil then
		settings.ambush_trigger_spheres_enabled = false
	end
	if settings.backtrack_trigger_sphere_enabled == nil then
		settings.backtrack_trigger_sphere_enabled = false
	end
	if settings.respawn_threshold_enabled == nil then
		settings.respawn_threshold_enabled = false
	end
	if settings.respawn_backline_enabled == nil then
		settings.respawn_backline_enabled = false
	end
	if settings.respawn_beacon_line_enabled == nil then
		settings.respawn_beacon_line_enabled = false
	end
	if settings.priority_beacon_enabled == nil then
		settings.priority_beacon_enabled = false
	end
	if settings.cache_use_enabled == nil then
		settings.cache_use_enabled = true
	end
	if settings.cache_use_offline_enabled == nil then
		settings.cache_use_offline_enabled = false
	end
	if settings.respawn_move_triggers_mode == nil then
		settings.respawn_move_triggers_mode = "off"
	elseif settings.respawn_move_triggers_mode == true then
		settings.respawn_move_triggers_mode = "hogtied"
	elseif settings.respawn_move_triggers_mode == false then
		settings.respawn_move_triggers_mode = "off"
	end
	if settings.priority_move_triggers_mode == nil then
		settings.priority_move_triggers_mode = "off"
	elseif settings.priority_move_triggers_mode == true then
		settings.priority_move_triggers_mode = "hogtied"
	elseif settings.priority_move_triggers_mode == false then
		settings.priority_move_triggers_mode = "off"
	end
	if settings.respawn_move_triggers_mode ~= "off"
		and settings.respawn_move_triggers_mode ~= "always"
		and settings.respawn_move_triggers_mode ~= "hogtied" then
		settings.respawn_move_triggers_mode = "off"
	end
	if settings.priority_move_triggers_mode ~= "off"
		and settings.priority_move_triggers_mode ~= "always"
		and settings.priority_move_triggers_mode ~= "hogtied" then
		settings.priority_move_triggers_mode = "off"
	end
	if not settings.allow_live_data and not settings.cache_use_enabled then
		settings.boss_trigger_spheres_enabled = false
		settings.pacing_spawn_triggers_enabled = false
		settings.ambush_trigger_spheres_enabled = false
		settings.trigger_points_enabled = false
	end
	settings.show_any = settings.path_enabled
		or settings.trigger_points_enabled
		or settings.progress_point_enabled
		or settings.boss_trigger_spheres_enabled
		or settings.pacing_spawn_triggers_enabled
		or settings.ambush_trigger_spheres_enabled
		or settings.backtrack_trigger_sphere_enabled
		or settings.respawn_progress_enabled
		or settings.respawn_beacon_enabled
		or settings.priority_beacon_enabled
		or settings.respawn_beacon_line_enabled
		or settings.respawn_threshold_enabled
		or settings.respawn_backline_enabled
		or settings.respawn_move_triggers_mode ~= "off"
		or settings.priority_move_triggers_mode ~= "off"
		or settings.debug_text_enabled
	return settings
end

function build_debug_state(path_total)
	local state = {}
	state.path_total = path_total

	local player = Managers.player and Managers.player:local_player(1)
	local player_unit = player and player.player_unit
	local player_distance = nil

	if player_unit and unit_is_alive(player_unit) then
		local player_position = get_unit_position(player_unit)
		state.player_position = player_position
		player_distance = get_position_travel_distance(player_position)
		if not player_distance then
			player_distance = get_unit_travel_distance(player_unit)
		end
	end
	if path_total and player_distance then
		player_distance = math.max(0, math.min(player_distance, path_total))
	end
	if player_distance and not is_finite_number(player_distance) then
		player_distance = nil
	end

	local progress_entries, leader_distance, leader_player, local_distance = collect_player_progress(path_total)
	if local_distance then
		player_distance = local_distance
	end
	local progress_reference_distance = leader_distance or player_distance
	if progress_reference_distance and (not max_progress_distance or progress_reference_distance > max_progress_distance) then
		max_progress_distance = progress_reference_distance
	end

	local remove_distance = nil
	if progress_reference_distance then
		remove_distance = progress_reference_distance - TRIGGER_PAST_MARGIN
	elseif Managers.state.main_path and Managers.state.main_path.ahead_unit then
		local _, ahead_distance = Managers.state.main_path:ahead_unit(1)
		if ahead_distance then
			remove_distance = ahead_distance - TRIGGER_PAST_MARGIN
		end
	end
	if path_total and remove_distance then
		remove_distance = math.max(0, math.min(remove_distance, path_total))
	end

	state.player_distance = player_distance
	state.progress_entries = progress_entries
	state.leader_distance = leader_distance
	state.leader_player = leader_player
	state.progress_reference_distance = progress_reference_distance
	state.remove_distance = remove_distance
	state.max_progress_distance = max_progress_distance
	local waiting_to_spawn, respawn_min_time = has_players_waiting_to_spawn()
	state.respawn_waiting = waiting_to_spawn
	state.respawn_min_time = respawn_min_time
	state.hogtied_present = has_hogtied_players()
	if Managers.state.main_path and Managers.state.main_path.ahead_unit then
		local side_id = get_default_side_id()
		if side_id then
			local ok_ahead, _, ahead_distance = pcall(Managers.state.main_path.ahead_unit, Managers.state.main_path, side_id)
			if ok_ahead then
				state.ahead_distance = ahead_distance
			end
			local ok_behind, _, behind_distance = pcall(Managers.state.main_path.behind_unit, Managers.state.main_path, side_id)
			if ok_behind then
				state.behind_distance = behind_distance
			end
		end
	end
	state.alpha = 200

	return state
end

function draw_debug_path(settings, state)
	if not settings.path_enabled then
		return
	end
	local path_color = Color(120, CONST.PATH_COLOR[1], CONST.PATH_COLOR[2], CONST.PATH_COLOR[3])
	draw_main_path(
		state.line_object,
		path_color,
		settings.path_height,
		state.player_position,
		settings.debug_draw_distance
	)
end

function draw_debug_progress(settings, state)
	if not settings.progress_point_enabled then
		return
	end
	local progress_entries = state.progress_entries or {}
	local progress_group_counts = {}
	local progress_group_indices = {}

	for i = 1, #progress_entries do
		local distance = progress_entries[i].distance
		if distance and is_finite_number(distance) then
			local bucket = math.floor((distance / CONST.PROGRESS_STACK_STEP) + 0.5) * CONST.PROGRESS_STACK_STEP
			progress_entries[i].stack_key = bucket
			progress_group_counts[bucket] = (progress_group_counts[bucket] or 0) + 1
		end
	end

	for i = 1, #progress_entries do
		local entry = progress_entries[i]
		local distance = entry.distance
		if state.path_total then
			distance = math.max(0, math.min(distance, state.path_total))
		end
		local progress_position = MainPathQueries.position_from_distance(distance)
		if progress_position then
			if not within_draw_distance(progress_position, settings, state) then
				goto continue_progress
			end
			local is_leader = state.leader_player and entry.player == state.leader_player
			local color_values = is_leader and CONST.RING_COLORS.purple or CONST.PROGRESS_COLOR
			local alpha_value = entry.alive and 220 or 140
			local color = Color(alpha_value, color_values[1], color_values[2], color_values[3])
			local stack_key = entry.stack_key or distance or 0
			local stack_index = (progress_group_indices[stack_key] or 0) + 1
			progress_group_indices[stack_key] = stack_index
			local stack_offset = (stack_index - 1) * CONST.PROGRESS_STACK_HEIGHT * settings.sphere_radius_scale
			local position = progress_position
				+ Vector3(0, 0, settings.path_height + settings.progress_height + stack_offset)
			draw_sphere(state.line_object, position, 0.4 * settings.sphere_radius_scale, 20, color)
			if settings.debug_text_enabled then
				local label = nil
				local label_color = color_values
				if is_leader then
					label = "Progress (Leader)"
					label_color = CONST.RING_COLORS.purple
				elseif entry.is_local then
					label = "Progress (You)"
					label_color = CONST.PROGRESS_COLOR
				else
					local name = get_player_name(entry.player)
					if name then
						label = string.format("Progress (%s)", tostring(name))
						label_color = CONST.PROGRESS_COLOR
					end
				end
				if label then
					local label_text = format_debug_label(
						label,
						distance,
						settings.debug_text_show_distances,
						settings.debug_text_show_labels
					)
					if label_text then
						local text_position = get_debug_text_position(
							position,
							label,
							settings.debug_text_height,
							settings.debug_text_offset_scale
						)
						output_debug_text(
							state.debug_text,
							label_text,
							text_position,
							settings.debug_text_size,
							label_color
						)
					end
				end
			end
		end
		::continue_progress::
	end

	if state.max_progress_distance then
		local max_position = MainPathQueries.position_from_distance(state.max_progress_distance)
		if max_position then
			if not within_draw_distance(max_position, settings, state) then
				return
			end
			local max_offset = 0
			if state.leader_distance and math.abs(state.max_progress_distance - state.leader_distance) < 0.05 then
				max_offset = CONST.MAX_PROGRESS_HEIGHT_OFFSET
			end
			local max_stack_offset = 0
			local max_bucket = math.floor((state.max_progress_distance / CONST.PROGRESS_STACK_STEP) + 0.5) * CONST.PROGRESS_STACK_STEP
			local group_count = progress_group_counts[max_bucket] or 0
			if group_count > 0 then
				max_stack_offset = group_count * CONST.PROGRESS_STACK_HEIGHT * settings.sphere_radius_scale
			end
			local max_color = Color(220, CONST.PROGRESS_MAX_COLOR[1], CONST.PROGRESS_MAX_COLOR[2], CONST.PROGRESS_MAX_COLOR[3])
			local position = max_position
				+ Vector3(
					0,
					0,
					settings.path_height + settings.progress_height + max_offset + max_stack_offset
				)
			draw_sphere(state.line_object, position, 0.5 * settings.sphere_radius_scale, 20, max_color)
			if settings.debug_text_enabled then
				local base_label = "Max Progress"
				local label_text = format_debug_label(
					base_label,
					state.max_progress_distance,
					settings.debug_text_show_distances,
					settings.debug_text_show_labels
				)
				if label_text then
					local text_position = get_debug_text_position(
						position,
						base_label,
						settings.debug_text_height,
						settings.debug_text_offset_scale
					)
					output_debug_text(
						state.debug_text,
						label_text,
						text_position,
						settings.debug_text_size,
						CONST.PROGRESS_MAX_COLOR
					)
				end
			end
		end
	end
end

function draw_debug_boss_triggers(settings, state)
	if not settings.boss_trigger_spheres_enabled then
		return
	end
	local boss_triggers = collect_boss_triggers({
		mutator = settings.boss_mutator_triggers_enabled,
		twins = settings.boss_twins_triggers_enabled,
		boss_patrols = settings.boss_patrol_triggers_enabled,
	})
	if #boss_triggers == 0 and state.cache_entry then
		boss_triggers = cached_boss_triggers(state.cache_entry)
	end
	if #boss_triggers == 0 then
		return
	end
	local twins_spawn_mode = settings.twins_spawn_triggers_mode or "always"
	local twins_ambush_mode = settings.twins_ambush_triggers_mode or "always"
	local twins_spawned = (twins_spawn_mode == "until_spawn" or twins_ambush_mode == "until_spawn")
		and is_twins_spawned()
		or false
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
		if distance and state.path_total then
			distance = math.max(0, math.min(distance, state.path_total))
		end
		if trigger.label == "Twins Spawn Trigger" then
			if twins_spawn_mode == "off" then
				goto continue_boss
			elseif twins_spawn_mode == "until_spawn" then
				local spawned = twins_spawned
				if not spawned and state.progress_reference_distance and distance then
					spawned = distance <= state.progress_reference_distance
				end
				if spawned then
					goto continue_boss
				end
			end
		elseif trigger.label == "Twins Ambush Trigger" then
			if twins_ambush_mode == "off" then
				goto continue_boss
			elseif twins_ambush_mode == "until_spawn" then
				local spawned = twins_spawned
				if not spawned and state.progress_reference_distance and distance then
					spawned = distance <= state.progress_reference_distance
				end
				if spawned then
					goto continue_boss
				end
			end
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
					local step = (CONST.BOSS_TRIGGER_RADIUS * 2.2) * settings.sphere_radius_scale
					local centered_index = group_index - (group_count + 1) * 0.5
					position = position + right * (step * centered_index)
				end
			end
			local key = trigger.key or string.format("boss:%.2f", distance or 0)
			local passed = boss_triggered[key]
				or (state.progress_reference_distance and distance and distance <= state.progress_reference_distance)
			if passed and not boss_triggered[key] then
				boss_triggered[key] = true
			end
			local color_rgb = passed and CONST.MARKER_COLOR or CONST.BOSS_TRIGGER_COLOR
			local boss_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
			local radius = CONST.BOSS_TRIGGER_RADIUS * settings.sphere_radius_scale
			local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
			if not within_draw_distance(sphere_position, settings, state) then
				goto continue_boss
			end
			draw_sphere(state.line_object, sphere_position, radius, 18, boss_color)
			if settings.debug_text_enabled then
				local base_label = trigger.label or "Boss Trigger"
				local label_text = format_debug_label(
					base_label,
					distance,
					settings.debug_text_show_distances,
					settings.debug_text_show_labels
				)
				if label_text then
					local text_position = get_debug_text_position(
						sphere_position,
						base_label,
						settings.debug_text_height,
						settings.debug_text_offset_scale
					)
					output_debug_text(
						state.debug_text,
						label_text,
						text_position,
						settings.debug_text_size,
						color_rgb
					)
				end
			end
		end
		::continue_boss::
	end
end

function draw_debug_pacing_triggers(settings, state)
	if not settings.pacing_spawn_triggers_enabled then
		return
	end
	local pacing_triggers = collect_pacing_spawn_triggers()
	if #pacing_triggers == 0 and state.cache_entry then
		pacing_triggers = cached_pacing_triggers(state.cache_entry)
	end
	if #pacing_triggers == 0 then
		return
	end
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
		if distance and state.path_total then
			distance = math.max(0, math.min(distance, state.path_total))
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
				local step = (CONST.TRIGGER_POINT_RADIUS * 2.2) * settings.sphere_radius_scale
				local centered_index = group_index - (group_count + 1) * 0.5
				position = position + right * (step * centered_index)
			end
			local key = trigger.key or string.format("pacing:%.2f", distance or 0)
			local passed = pacing_triggered[key]
				or (state.progress_reference_distance and distance and distance <= state.progress_reference_distance)
			if passed and not pacing_triggered[key] then
				pacing_triggered[key] = true
			end
			local color_rgb = passed and CONST.MARKER_COLOR or CONST.PACING_TRIGGER_COLOR
			local pace_color = Color(200, color_rgb[1], color_rgb[2], color_rgb[3])
			local radius = CONST.TRIGGER_POINT_RADIUS * settings.sphere_radius_scale
			local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
			if not within_draw_distance(sphere_position, settings, state) then
				goto continue_pacing
			end
			draw_sphere(state.line_object, sphere_position, radius, 16, pace_color)
			if settings.debug_text_enabled then
				local base_label = trigger.label or "Pacing Spawn"
				local label_text = format_debug_label(
					base_label,
					distance,
					settings.debug_text_show_distances,
					settings.debug_text_show_labels
				)
				if label_text then
					local text_position = get_debug_text_position(
						sphere_position,
						base_label,
						settings.debug_text_height,
						settings.debug_text_offset_scale
					)
					output_debug_text(
						state.debug_text,
						label_text,
						text_position,
						settings.debug_text_size,
						color_rgb
					)
				end
			end
		end
		::continue_pacing::
	end
end

function draw_debug_ambush_triggers(settings, state)
	if not settings.ambush_trigger_spheres_enabled then
		return
	end
	local ambush_triggers = {}
	if settings.allow_live_data then
		ambush_triggers = collect_ambush_triggers()
	end
	if #ambush_triggers == 0 and state.cache_entry then
		ambush_triggers = cached_ambush_triggers(state.cache_entry)
	end
	if #ambush_triggers == 0 then
		return
	end
	local ambush_counts = {}
	local ambush_indices = {}
	for i = 1, #ambush_triggers do
		local distance = ambush_triggers[i].distance
		local distance_key = string.format("ambush_dist:%.2f", distance or 0)
		ambush_counts[distance_key] = (ambush_counts[distance_key] or 0) + 1
	end
	for i = 1, #ambush_triggers do
		local trigger = ambush_triggers[i]
		local distance = trigger.distance
		if distance and state.path_total then
			distance = math.max(0, math.min(distance, state.path_total))
		end
		local distance_key = string.format("ambush_dist:%.2f", distance or 0)
		local group_count = ambush_counts[distance_key] or 1
		local group_index = (ambush_indices[distance_key] or 0) + 1
		ambush_indices[distance_key] = group_index
		local position = distance and MainPathQueries.position_from_distance(distance)
		if position then
			if group_count > 1 then
				local direction = main_path_direction(distance)
				local right = direction and Vector3.cross(Vector3.up(), direction)
				if not right or Vector3.length(right) < 0.001 then
					right = Vector3(1, 0, 0)
				end
				right = Vector3.normalize(right)
				local step = (CONST.TRIGGER_POINT_RADIUS * 2.2) * settings.sphere_radius_scale
				local centered_index = group_index - (group_count + 1) * 0.5
				position = position + right * (step * centered_index)
			end
			local key = trigger.key or string.format("ambush:%.2f", distance or 0)
			local passed = ambush_triggered[key]
				or (state.progress_reference_distance and distance and distance <= state.progress_reference_distance)
			if passed and not ambush_triggered[key] then
				ambush_triggered[key] = true
			end
			local color_rgb = passed and CONST.MARKER_COLOR or CONST.AMBUSH_TRIGGER_COLOR
			local radius = CONST.TRIGGER_POINT_RADIUS * settings.sphere_radius_scale
			local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
			if not within_draw_distance(sphere_position, settings, state) then
				goto continue_ambush
			end
			draw_sphere(state.line_object, sphere_position, radius, 18, Color(220, color_rgb[1], color_rgb[2], color_rgb[3]))
			if settings.debug_text_enabled then
				local base_label = trigger.label or "Ambush Horde Trigger"
				local label_text = format_debug_label(
					base_label,
					distance,
					settings.debug_text_show_distances,
					settings.debug_text_show_labels
				)
				if label_text then
					local text_position = get_debug_text_position(
						sphere_position,
						base_label,
						settings.debug_text_height,
						settings.debug_text_offset_scale
					)
					output_debug_text(
						state.debug_text,
						label_text,
						text_position,
						settings.debug_text_size,
						color_rgb
					)
				end
			end
		end
		::continue_ambush::
	end
end

function draw_debug_backtrack_trigger(settings, state)
	if not settings.backtrack_trigger_sphere_enabled then
		return
	end
	local trigger_distance = get_backtrack_trigger_distance(state.path_total)
	if not trigger_distance then
		return
	end
	local position = MainPathQueries.position_from_distance(trigger_distance)
	if not position then
		return
	end
	local passed = state.progress_reference_distance
		and trigger_distance
		and state.progress_reference_distance <= trigger_distance
	local color_rgb = passed and CONST.MARKER_COLOR or CONST.BACKTRACK_TRIGGER_COLOR
	local radius = CONST.TRIGGER_POINT_RADIUS * settings.sphere_radius_scale
	local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
	if not within_draw_distance(sphere_position, settings, state) then
		return
	end
	draw_sphere(state.line_object, sphere_position, radius, 18, Color(220, color_rgb[1], color_rgb[2], color_rgb[3]))
	if settings.debug_text_enabled then
		local base_label = "Backtrack Horde Trigger"
		local label_text = format_debug_label(
			base_label,
			trigger_distance,
			settings.debug_text_show_distances,
			settings.debug_text_show_labels
		)
		if label_text then
			local text_position = get_debug_text_position(
				sphere_position,
				base_label,
				settings.debug_text_height,
				settings.debug_text_offset_scale
			)
			output_debug_text(
				state.debug_text,
				label_text,
				text_position,
				settings.debug_text_size,
				color_rgb
			)
		end
	end
end

function draw_debug_respawn_points(settings, state)
	if not settings.respawn_progress_enabled
		and not settings.respawn_beacon_enabled
		and settings.respawn_move_triggers_mode == "off" then
		return
	end

	local respawn_distances = {}
	if settings.respawn_progress_enabled or settings.respawn_beacon_enabled then
		respawn_distances = collect_respawn_progress_distances()
	end

	if settings.respawn_progress_enabled then
		local use_distances = respawn_distances
		if #respawn_distances == 0 and state.cache_entry then
			use_distances = cached_respawn_distances(state.cache_entry)
		end
		local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
		local active_unit = respawn_system and respawn_system._current_active_respawn_beacon
		local active_distance = nil
		if active_unit and respawn_system then
			local lookup = respawn_system._beacon_main_path_distance_lookup
			if lookup then
				active_distance = lookup[active_unit]
			end
			if not active_distance then
				local beacon_data = respawn_system._beacon_main_path_data
				if beacon_data then
					for i = 1, #beacon_data do
						local data = beacon_data[i]
						if data and data.unit == active_unit then
							active_distance = data.distance
							break
						end
					end
				end
			end
		end
		local active_progress_distance = active_distance
			and (active_distance - CONST.RESPAWN_BEACON_AHEAD_DISTANCE)
		if active_progress_distance and state.path_total then
			active_progress_distance = math.max(0, math.min(active_progress_distance, state.path_total))
		end
		if not active_progress_distance and use_distances and #use_distances > 0 then
			local reference_distance =
				state.ahead_distance or state.progress_reference_distance or state.player_distance
			local best_distance = nil
			if reference_distance then
				for i = 1, #use_distances do
					local candidate = use_distances[i]
					if candidate and candidate >= reference_distance then
						if not best_distance or candidate < best_distance then
							best_distance = candidate
						end
					end
				end
			end
			if not best_distance then
				for i = 1, #use_distances do
					local candidate = use_distances[i]
					if candidate and is_finite_number(candidate) then
						if not best_distance or candidate > best_distance then
							best_distance = candidate
						end
					end
				end
			end
			if best_distance and state.path_total then
				best_distance = math.max(0, math.min(best_distance, state.path_total))
			end
			active_progress_distance = best_distance
		end
		local waiting_to_spawn = state.respawn_waiting
		local warn_active = waiting_to_spawn and not state.hogtied_present
		local min_respawn_time = state.respawn_min_time
		for i = 1, #use_distances do
			local distance = use_distances[i]
			if distance and state.path_total then
				distance = math.max(0, math.min(distance, state.path_total))
			end
			local passed = state.progress_reference_distance and distance and distance <= state.progress_reference_distance
			local position = distance and MainPathQueries.position_from_distance(distance)
			if position then
				local color_rgb = passed and CONST.MARKER_COLOR or CONST.RESPAWN_PROGRESS_COLOR
				local warn_status = nil
				if warn_active
					and active_progress_distance
					and distance
					and math.abs(distance - active_progress_distance) <= CACHE.DISTANCE_TOLERANCE then
					local reference_distance = state.progress_reference_distance
						or state.ahead_distance
						or state.player_distance
					local crossed = reference_distance and reference_distance > distance
					if crossed then
						warn_status = "Return"
						color_rgb = CONST.RING_COLORS.red
					else
						warn_status = "Do Not Cross"
						color_rgb = CONST.RESPAWN_PROGRESS_COLOR
					end
				end
				local respawn_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
				local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
				local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
				if not within_draw_distance(sphere_position, settings, state) then
					goto continue_respawn
				end
				draw_sphere(state.line_object, sphere_position, radius, 18, respawn_color)
				if settings.debug_text_enabled then
					local base_label = "Respawn Progress"
					local label_key = warn_status and "Respawn Progress Warning" or base_label
					if warn_status then
						if min_respawn_time and is_finite_number(min_respawn_time) then
							base_label = string.format(
								"%s (%s %.0fs)",
								base_label,
								warn_status,
								math.max(0, min_respawn_time)
							)
						else
							base_label = string.format("%s (%s)", base_label, warn_status)
						end
					end
					local label_text = format_debug_label(
						base_label,
						distance,
						settings.debug_text_show_distances,
						settings.debug_text_show_labels
					)
					if label_text then
						local text_position = get_debug_text_position(
							sphere_position,
							label_key,
							settings.debug_text_height,
							settings.debug_text_offset_scale
						)
						output_debug_text(
							state.debug_text,
							label_text,
							text_position,
							settings.debug_text_size,
							color_rgb
						)
					end
				end
			end
			::continue_respawn::
		end
	end

	if settings.respawn_beacon_enabled then
		local fallback_distances = respawn_distances or {}
		if #fallback_distances == 0 and state.cache_entry then
			fallback_distances = cached_respawn_distances(state.cache_entry)
		end
		local beacon_entries = collect_respawn_beacon_entries(state.path_total, fallback_distances)
		if #beacon_entries > 0 then
			local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
			local priority_unit = get_priority_respawn_beacon_unit(respawn_system)
			local active_unit = respawn_system and respawn_system._current_active_respawn_beacon
			if active_unit then
				last_active_respawn_beacon = active_unit
			end
			for i = 1, #beacon_entries do
				local entry = beacon_entries[i]
				local position = entry.position
				local distance = entry.distance
				if position then
					local color_rgb = CONST.RESPAWN_BEACON_COLOR
					local base_label = "Respawn Beacon"
					if entry.priority or (entry.unit and entry.unit == priority_unit) then
						color_rgb = CONST.MARKER_COLOR
						base_label = "Respawn Beacon (Priority)"
					elseif entry.unit and entry.unit == active_unit then
						color_rgb = CONST.PROGRESS_COLOR
						base_label = "Respawn Beacon (Active)"
						last_active_respawn_beacon_distance = distance
					elseif entry.unit
						and last_active_respawn_beacon
						and entry.unit == last_active_respawn_beacon then
						color_rgb = CONST.PROGRESS_COLOR
						base_label = "Respawn Beacon (Last Active)"
					elseif not entry.unit
						and last_active_respawn_beacon_distance
						and distance
						and math.abs(distance - last_active_respawn_beacon_distance) <= 0.2 then
						color_rgb = CONST.PROGRESS_COLOR
						base_label = "Respawn Beacon (Last Active)"
					end
					local beacon_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
					local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
					if within_draw_distance(sphere_position, settings, state) then
						draw_sphere(state.line_object, sphere_position, radius, 18, beacon_color)
						if settings.debug_text_enabled then
							local label_text = format_debug_label(
								base_label,
								distance,
								settings.debug_text_show_distances,
								settings.debug_text_show_labels
							)
							if label_text then
								local text_position = get_debug_text_position(
									sphere_position,
									base_label,
									settings.debug_text_height,
									settings.debug_text_offset_scale
								)
								output_debug_text(
									state.debug_text,
									label_text,
									text_position,
									settings.debug_text_size,
									color_rgb
								)
							end
						end
					end
				end
			end
		end
	end
	if settings.priority_beacon_enabled then
		local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
		local priority_unit = get_priority_respawn_beacon_unit(respawn_system)
		local priority_position = nil
		local priority_distance = get_priority_respawn_beacon_distance(respawn_system, priority_unit)
		if priority_unit and Unit and Unit.world_position then
			local ok, position = pcall(Unit.world_position, priority_unit, 1)
			if ok and position then
				priority_position = position
				if not priority_distance then
					priority_distance = get_position_travel_distance(position)
				end
			end
		end
		if not priority_position and priority_distance then
			priority_position = MainPathQueries.position_from_distance(priority_distance)
		end
		if priority_position then
			local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
			local sphere_position = priority_position + Vector3(0, 0, settings.path_height + radius)
			if within_draw_distance(sphere_position, settings, state) then
				local color_rgb = CONST.RING_COLORS.orange
				draw_sphere(
					state.line_object,
					sphere_position,
					radius,
					18,
					Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
				)
				if settings.debug_text_enabled then
					local base_label = "Priority Respawn Beacon"
					local label_text = format_debug_label(
						base_label,
						priority_distance,
						settings.debug_text_show_distances,
						settings.debug_text_show_labels
					)
					if label_text then
						local text_position = get_debug_text_position(
							sphere_position,
							base_label,
							settings.debug_text_height,
							settings.debug_text_offset_scale
						)
						output_debug_text(
							state.debug_text,
							label_text,
							text_position,
							settings.debug_text_size,
							color_rgb
						)
					end
				end
			end
		end
	end
	if settings.respawn_beacon_line_enabled and state.player_position then
		local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
		local active_unit = respawn_system and respawn_system._current_active_respawn_beacon
		local active_position = nil
		if active_unit and Unit and Unit.world_position then
			local ok, position = pcall(Unit.world_position, active_unit, 1)
			if ok and position then
				active_position = position
			end
		end
		if not active_position and active_unit and respawn_system then
			local active_distance = nil
			local lookup = respawn_system._beacon_main_path_distance_lookup
			if lookup then
				active_distance = lookup[active_unit]
			end
			if not active_distance then
				local beacon_data = respawn_system._beacon_main_path_data
				if beacon_data then
					for i = 1, #beacon_data do
						local data = beacon_data[i]
						if data and data.unit == active_unit then
							active_distance = data.distance
							break
						end
					end
				end
			end
			if active_distance then
				active_position = MainPathQueries.position_from_distance(active_distance)
			end
		end
		if active_position and within_draw_distance(active_position, settings, state) then
			local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
			local offset = Vector3(0, 0, settings.path_height + radius)
			local from = state.player_position + offset
			local to = active_position + offset
			local color_rgb = CONST.PROGRESS_COLOR
			local color = Color(200, color_rgb[1], color_rgb[2], color_rgb[3])
			pcall(LineObject.add_line, state.line_object, color, from, to)
		end
	end

	if settings.respawn_threshold_enabled then
		local threshold_distance = state.ahead_distance and (state.ahead_distance + CONST.RESPAWN_BEACON_AHEAD_DISTANCE)
		if threshold_distance and state.path_total then
			threshold_distance = math.max(0, math.min(threshold_distance, state.path_total))
		end
		if threshold_distance then
			local position = MainPathQueries.position_from_distance(threshold_distance)
			if position then
				local color_rgb = CONST.MARKER_COLOR
				local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
				local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
				if within_draw_distance(sphere_position, settings, state) then
					draw_sphere(
						state.line_object,
						sphere_position,
						radius,
						18,
						Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
					)
					if settings.debug_text_enabled then
						local base_label = "Respawn Beacon Threshold"
						local label_text = format_debug_label(
							base_label,
							threshold_distance,
							settings.debug_text_show_distances,
							settings.debug_text_show_labels
						)
						if label_text then
							local text_position = get_debug_text_position(
								sphere_position,
								base_label,
								settings.debug_text_height,
								settings.debug_text_offset_scale
							)
							output_debug_text(
								state.debug_text,
								label_text,
								text_position,
								settings.debug_text_size,
								color_rgb
							)
						end
					end
				end
			end
		end

		local rewind_threshold = nil
		local beacon_distances = nil
		local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
		local beacon_data = respawn_system and respawn_system._beacon_main_path_data
		if beacon_data and #beacon_data > 0 then
			beacon_distances = {}
			for i = 1, #beacon_data do
				local data = beacon_data[i]
				if data and data.distance then
					beacon_distances[#beacon_distances + 1] = data.distance
				end
			end
		elseif respawn_distances and #respawn_distances > 0 then
			beacon_distances = {}
			for i = 1, #respawn_distances do
				local progress_distance = respawn_distances[i]
				if progress_distance and is_finite_number(progress_distance) then
					beacon_distances[#beacon_distances + 1] =
						progress_distance + CONST.RESPAWN_BEACON_AHEAD_DISTANCE
				end
			end
			table.sort(beacon_distances)
		end

		local active_unit = respawn_system and respawn_system._current_active_respawn_beacon
		local active_distance = nil
		if beacon_distances then
			if active_unit and respawn_system and respawn_system._beacon_main_path_distance_lookup then
				active_distance = respawn_system._beacon_main_path_distance_lookup[active_unit]
			end
			if active_unit and not active_distance and beacon_data then
				for i = 1, #beacon_data do
					local data = beacon_data[i]
					if data and data.unit == active_unit then
						active_distance = data.distance
						break
					end
				end
			end

			local chosen_index = nil
			if active_distance then
				for i = 1, #beacon_distances do
					if math.abs(beacon_distances[i] - active_distance) <= 0.1 then
						chosen_index = i
						break
					end
				end
			elseif state.ahead_distance then
				local min_distance = state.ahead_distance + CONST.RESPAWN_BEACON_AHEAD_DISTANCE
				for i = 1, #beacon_distances do
					if min_distance < beacon_distances[i] or i == #beacon_distances then
						chosen_index = i
						break
					end
				end
			end

			if chosen_index and chosen_index > 1 then
				rewind_threshold = beacon_distances[chosen_index - 1] - CONST.RESPAWN_BEACON_AHEAD_DISTANCE
				if state.path_total then
					rewind_threshold = math.max(0, math.min(rewind_threshold, state.path_total))
				end
			end
		end

		if rewind_threshold then
			local position = MainPathQueries.position_from_distance(rewind_threshold)
			if position then
				local waiting_to_spawn = state.respawn_waiting
				local warn_active = waiting_to_spawn and not state.hogtied_present
				local min_respawn_time = state.respawn_min_time
				if warn_active and not respawn_waiting_active then
					respawn_rewind_crossed = false
					respawn_rewind_lost = false
				elseif not warn_active and respawn_waiting_active then
					respawn_rewind_lost = respawn_rewind_crossed and true or false
				end
				respawn_waiting_active = warn_active

				local reference_distance = state.progress_reference_distance or state.ahead_distance or state.player_distance
				local crossed = reference_distance and reference_distance > rewind_threshold
				local show_threshold = warn_active or respawn_rewind_lost
				local status = nil
				local color_rgb = nil

				if warn_active then
					if crossed then
						status = "Return"
						color_rgb = CONST.RING_COLORS.red
						respawn_rewind_crossed = true
					else
						status = "Safe"
						color_rgb = CONST.RESPAWN_PROGRESS_COLOR
						respawn_rewind_crossed = false
					end
				elseif respawn_rewind_lost then
					status = "Lost"
					color_rgb = { 255, 255, 255 }
				end

				if show_threshold and status and color_rgb then
					local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
					if within_draw_distance(sphere_position, settings, state) then
						draw_sphere(
							state.line_object,
							sphere_position,
							radius,
							18,
							Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
						)
						if settings.debug_text_enabled then
						local base_label = "Respawn Rewind Threshold"
						if min_respawn_time and is_finite_number(min_respawn_time) and status ~= "Lost" then
							base_label = string.format(
								"%s (%s %.0fs)",
								base_label,
								status,
								math.max(0, min_respawn_time)
							)
						else
							base_label = string.format("%s (%s)", base_label, status)
						end
						local label_text = format_debug_label(
							base_label,
							rewind_threshold,
							settings.debug_text_show_distances,
							settings.debug_text_show_labels
						)
							if label_text then
								local text_position = get_debug_text_position(
									sphere_position,
									base_label,
									settings.debug_text_height,
									settings.debug_text_offset_scale
								)
								output_debug_text(
									state.debug_text,
									label_text,
									text_position,
									settings.debug_text_size,
									color_rgb
								)
							end
						end
					end
				end
			end
		end
	end

	if settings.respawn_move_triggers_mode ~= "off" then
		local move_triggers = collect_hogtied_move_triggers(
			state.path_total,
			settings.respawn_move_triggers_mode
		)
		if #move_triggers > 0 then
			local move_counts = {}
			local move_indices = {}
			for i = 1, #move_triggers do
				local distance_key = string.format("move:%.2f", move_triggers[i].distance or 0)
				move_counts[distance_key] = (move_counts[distance_key] or 0) + 1
			end
			for i = 1, #move_triggers do
				local trigger = move_triggers[i]
				local distance = trigger.distance
				if distance and state.path_total then
					distance = math.max(0, math.min(distance, state.path_total))
				end
				local distance_key = string.format("move:%.2f", distance or 0)
				local group_count = move_counts[distance_key] or 1
				local group_index = (move_indices[distance_key] or 0) + 1
				move_indices[distance_key] = group_index
				local position = distance and MainPathQueries.position_from_distance(distance)
				if position then
					if group_count > 1 then
						local direction = main_path_direction(distance)
						local right = direction and Vector3.cross(Vector3.up(), direction)
						if not right or Vector3.length(right) < 0.001 then
							right = Vector3(1, 0, 0)
						end
						right = Vector3.normalize(right)
						local step = (CONST.RESPAWN_PROGRESS_RADIUS * 2.2) * settings.sphere_radius_scale
						local centered_index = group_index - (group_count + 1) * 0.5
						position = position + right * (step * centered_index)
					end
					local color_rgb = trigger.passed and CONST.MARKER_COLOR or CONST.RESPAWN_MOVE_TRIGGER_COLOR
					local move_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
					local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
					if within_draw_distance(sphere_position, settings, state) then
						draw_sphere(state.line_object, sphere_position, radius, 18, move_color)
						if settings.debug_text_enabled then
							local base_label = trigger.label
							local label_text = format_debug_label(
								base_label,
								distance,
								settings.debug_text_show_distances,
								settings.debug_text_show_labels
							)
							if label_text then
								local text_position = get_debug_text_position(
									sphere_position,
									base_label,
									settings.debug_text_height,
									settings.debug_text_offset_scale
								)
								output_debug_text(
									state.debug_text,
									label_text,
									text_position,
									settings.debug_text_size,
									color_rgb
								)
							end
							if state.hogtied_present then
								local warn_label = "Rescue Move Trigger Warning"
								local warn_text = "Rescue Move Trigger (Do Not Cross)"
								local warn_label_text = format_debug_label(
									warn_text,
									distance,
									settings.debug_text_show_distances,
									settings.debug_text_show_labels
								)
								if warn_label_text then
									local text_position = get_debug_text_position(
										sphere_position,
										warn_label,
										settings.debug_text_height,
										settings.debug_text_offset_scale
									)
									output_debug_text(
										state.debug_text,
										warn_label_text,
										text_position,
										settings.debug_text_size,
										CONST.RING_COLORS.red
									)
								end
							end
						end
					end
				end
			end
		end
	end

	if settings.priority_move_triggers_mode ~= "off" then
		local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
		local priority_unit = get_priority_respawn_beacon_unit(respawn_system)
		local move_triggers = collect_priority_move_triggers(
			state.path_total,
			settings.priority_move_triggers_mode,
			priority_unit
		)
		if #move_triggers > 0 then
			local move_counts = {}
			local move_indices = {}
			for i = 1, #move_triggers do
				local distance_key = string.format("priority_move:%.2f", move_triggers[i].distance or 0)
				move_counts[distance_key] = (move_counts[distance_key] or 0) + 1
			end
			for i = 1, #move_triggers do
				local trigger = move_triggers[i]
				local distance = trigger.distance
				if distance and state.path_total then
					distance = math.max(0, math.min(distance, state.path_total))
				end
				local distance_key = string.format("priority_move:%.2f", distance or 0)
				local group_count = move_counts[distance_key] or 1
				local group_index = (move_indices[distance_key] or 0) + 1
				move_indices[distance_key] = group_index
				local position = distance and MainPathQueries.position_from_distance(distance)
				if position then
					if group_count > 1 then
						local direction = main_path_direction(distance)
						local right = direction and Vector3.cross(Vector3.up(), direction)
						if not right or Vector3.length(right) < 0.001 then
							right = Vector3(1, 0, 0)
						end
						right = Vector3.normalize(right)
						local step = (CONST.RESPAWN_PROGRESS_RADIUS * 2.2) * settings.sphere_radius_scale
						local centered_index = group_index - (group_count + 1) * 0.5
						position = position + right * (step * centered_index)
					end
					local color_rgb = trigger.passed and CONST.MARKER_COLOR or CONST.RING_COLORS.orange
					local move_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
					local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
					local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
					if within_draw_distance(sphere_position, settings, state) then
						draw_sphere(state.line_object, sphere_position, radius, 18, move_color)
						if settings.debug_text_enabled then
							local base_label = trigger.label
							local label_text = format_debug_label(
								base_label,
								distance,
								settings.debug_text_show_distances,
								settings.debug_text_show_labels
							)
							if label_text then
								local text_position = get_debug_text_position(
									sphere_position,
									base_label,
									settings.debug_text_height,
									settings.debug_text_offset_scale
								)
								output_debug_text(
									state.debug_text,
									label_text,
									text_position,
									settings.debug_text_size,
									color_rgb
								)
							end
							if state.hogtied_present then
								local warn_label = "Priority Move Trigger Warning"
								local warn_text = "Priority Move Trigger (Do Not Cross)"
								local warn_label_text = format_debug_label(
									warn_text,
									distance,
									settings.debug_text_show_distances,
									settings.debug_text_show_labels
								)
								if warn_label_text then
									local text_position = get_debug_text_position(
										sphere_position,
										warn_label,
										settings.debug_text_height,
										settings.debug_text_offset_scale
									)
									output_debug_text(
										state.debug_text,
										warn_label_text,
										text_position,
										settings.debug_text_size,
										CONST.RING_COLORS.red
									)
								end
							end
						end
					end
				end
			end
		end
	end
end

function draw_debug_ritual_triggers(settings, state)
	if not state.ritual_enabled then
		return
	end
	if not settings.trigger_points_enabled then
		return
	end
	local triggers = collect_path_triggers(state.ritual_units or {})
	if #triggers == 0 and state.cache_entry then
		triggers = cached_path_triggers(state.cache_entry)
	end
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
		if distance and state.path_total then
			distance = math.max(0, math.min(distance, state.path_total))
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
			elseif trigger.id == "spawn_trigger" then
				persist_table = ritual_spawn_triggered
				persist_key = string.format("spawn:%.2f", distance)
			end
		end
		if persist_table and persist_key then
			persist_passed = persist_table[persist_key]
				or (state.progress_reference_distance and distance <= state.progress_reference_distance)
			if persist_passed and not persist_table[persist_key] then
				persist_table[persist_key] = true
			end
		end
		if not persist_table and state.remove_distance and distance and distance <= state.remove_distance then
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
					local step = (CONST.TRIGGER_POINT_RADIUS * 2.2) * settings.sphere_radius_scale
					local centered_index = group_index - (group_count + 1) * 0.5
					position = position + right * (step * centered_index)
				end
			end
			local color = get_color(trigger.color, state.alpha)
			if persist_passed then
				color = Color(state.alpha, CONST.MARKER_COLOR[1], CONST.MARKER_COLOR[2], CONST.MARKER_COLOR[3])
			end
			local base_position = position + Vector3(0, 0, settings.path_height)
			if not within_draw_distance(base_position, settings, state) then
				goto continue_ritual
			end
			if settings.gate_enabled then
				draw_gate_plane(
					state.line_object,
					base_position,
					direction,
					settings.gate_width,
					settings.gate_height,
					settings.gate_slices,
					color
				)
			end
			local trigger_radius = CONST.TRIGGER_POINT_RADIUS * settings.sphere_radius_scale
			local trigger_position = base_position + Vector3(0, 0, trigger_radius)
			draw_sphere(state.line_object, trigger_position, trigger_radius, 16, color)
			if settings.debug_text_enabled then
				local base_label = "Trigger"
				if trigger.id == "spawn_trigger" then
					base_label = "Ritual Spawn Trigger"
				elseif trigger.id == "ritual_start" then
					base_label = "Ritual Start Trigger"
				elseif trigger.id == "ritual_speedup" then
					base_label = "Ritual Speedup Trigger"
				end
				local label_text = format_debug_label(
					base_label,
					distance,
					settings.debug_text_show_distances,
					settings.debug_text_show_labels
				)
				if label_text then
					local text_position = get_debug_text_position(
						trigger_position,
						base_label,
						settings.debug_text_height,
						settings.debug_text_offset_scale
					)
					local color_rgb = persist_passed and CONST.MARKER_COLOR or { color[2], color[3], color[4] }
					output_debug_text(
						state.debug_text,
						label_text,
						text_position,
						settings.debug_text_size,
						color_rgb
					)
				end
			end
		end
		::continue_ritual::
	end
end

format_debug_label = function(label, distance, show_distance, show_label)
	if not show_label then
		if show_distance and is_finite_number(distance) then
			return string.format("%.1fm", distance)
		end
		return nil
	end
	if not label then
		return nil
	end
	if not show_distance or not is_finite_number(distance) then
		return label
	end
	return string.format("%s [%.1fm]", label, distance)
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

draw_sphere = function(line_object, center, radius, segments, color)
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

draw_gate_plane = function(line_object, base_position, direction, width, height, slices, color)
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

draw_main_path = function(line_object, color, height, player_position, max_distance)
	local main_path_manager = Managers.state.main_path
	local segments = main_path_manager and main_path_manager._main_path_segments
	if not segments then
		return
	end

	local h = Vector3(0, 0, height or 0.2)
	local use_cull = max_distance and max_distance > 0 and player_position

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
						local allow = true
						if use_cull then
							local dist_a = safe_distance(position, player_position)
							local dist_b = safe_distance(next_pos, player_position)
							if dist_a and dist_b and dist_a > max_distance and dist_b > max_distance then
								allow = false
							end
						end
						if allow then
							pcall(LineObject.add_line, line_object, color, position, next_pos)
						end
					end
				end
			end
		end
	end
end

function draw_debug_lines(world, ritual_units, t, ritual_enabled)
	if not mod:get("debug_enabled") then
		clear_line_object(world)
		clear_debug_label_markers()
		return
	end

	resolve_debug_modules()
	if not world or not Vector3 or not LineObject or not Color then
		return
	end
	local debug_mode = debug_text_mode()
	local debug_text_allowed = debug_text_enabled_mode(debug_mode)
	local labels_through_walls = mod:get("debug_labels_through_walls") and debug_text_allowed
	if not labels_through_walls then
		clear_debug_label_markers()
	end
	local update_interval = mod:get("debug_update_interval") or 0
	if update_interval < 0 then
		update_interval = 0
	end
	if update_interval > 0 and t and last_debug_refresh_t and (t - last_debug_refresh_t) < update_interval then
		local line_object = ensure_line_object(world)
		if line_object then
			pcall(LineObject.dispatch, world, line_object)
			return
		end
	end

	last_debug_refresh_t = t or 0

	local settings = get_debug_settings()
	if not settings.show_any then
		clear_line_object(world)
		clear_debug_label_markers()
		return
	end

	local debug_text = nil
	if settings.debug_text_enabled then
		debug_text = get_debug_text_manager(world)
		clear_debug_text(debug_text)
	else
		clear_debug_text(debug_text_manager)
		destroy_debug_text_manager()
	end
	if labels_through_walls then
		begin_debug_label_markers()
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

	local path_total = MainPathQueries.total_path_distance and MainPathQueries.total_path_distance()
	local cache_entry = nil
	if settings.allow_live_data then
		if settings.cache_use_offline_enabled then
			cache_entry = get_cache_entry(get_mission_name(), path_total)
		end
	elseif settings.cache_use_enabled then
		cache_entry = get_cache_entry(get_mission_name(), path_total)
	end
	local state = build_debug_state(path_total)
	state.line_object = line_object
	state.debug_text = debug_text
	state.cache_entry = cache_entry
	state.ritual_units = ritual_units
	state.ritual_enabled = ritual_enabled

	draw_debug_path(settings, state)
	draw_debug_progress(settings, state)
	draw_debug_boss_triggers(settings, state)
	draw_debug_pacing_triggers(settings, state)
	draw_debug_ambush_triggers(settings, state)
	draw_debug_backtrack_trigger(settings, state)
	draw_debug_respawn_points(settings, state)
	draw_debug_ritual_triggers(settings, state)

	pcall(LineObject.dispatch, world, line_object)
	if labels_through_walls then
		finalize_debug_label_markers()
	end
end

local function mark_dirty()
	markers_dirty = true
	timer_dirty = true
end

local function reset_runtime_state(clear_text)
	clear_markers()
	clear_timer_markers()
	clear_debug_label_markers()
	local world = Managers.world and Managers.world:world("level_world")
	if world then
		clear_line_object(world)
	end
	destroy_debug_lines()
	max_progress_distance = nil
	player_progress = {}
	boss_triggered = {}
	speedup_triggered = {}
	ritual_start_triggered = {}
	ritual_spawn_triggered = {}
	pacing_triggered = {}
	ambush_triggered = {}
	last_active_respawn_beacon = nil
	last_active_respawn_beacon_distance = nil
	respawn_waiting_active = false
	respawn_rewind_crossed = false
	respawn_rewind_lost = false
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
	if RitualZonesDebugLabelMarker then
		self._marker_templates[RitualZonesDebugLabelMarker.name] = RitualZonesDebugLabelMarker
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
	local mode = debug_text_mode()
	if not debug_text_enabled_mode(mode) then
		destroy_debug_text_manager()
	end
	if not (mod:get("debug_labels_through_walls") and debug_text_enabled_mode(mode)) then
		clear_debug_label_markers()
	end

	local record_enabled = cache_record_enabled()
	if record_enabled ~= last_cache_record_enabled then
		last_cache_record_enabled = record_enabled
		if record_enabled then
			cache_debug("Cache record enabled")
			cache_record_mission = nil
			cache_record_count = 0
			if is_gameplay_state() then
				cache_debug("Cache record toggle: attempting update")
				local ritual_enabled = is_havoc_ritual_active()
				local ritual_units = ritual_enabled and find_ritual_units() or {}
				local t = nil
				if Managers.time and Managers.time.time then
					local ok, value = pcall(Managers.time.time, Managers.time, "gameplay")
					if ok then
						t = value
					end
				end
				record_offline_cache(ritual_units, t or 0)
			end
		else
			cache_debug("Cache record disabled")
		end
	end

	local use_enabled = cache_use_enabled()
	if use_enabled ~= last_cache_use_enabled then
		last_cache_use_enabled = use_enabled
		if use_enabled then
			cache_debug("Cache use enabled")
			if cache_reads_allowed() then
				refresh_cache_from_disk()
			end
		else
			cache_debug("Cache use disabled")
		end
	end
	local use_offline_enabled = cache_use_offline_enabled()
	if use_offline_enabled ~= last_cache_use_offline_enabled then
		last_cache_use_offline_enabled = use_offline_enabled
		if use_offline_enabled then
			cache_debug("Cache use enabled (offline)")
			if cache_reads_allowed() then
				refresh_cache_from_disk()
			end
		else
			cache_debug("Cache use disabled (offline)")
		end
	end
end

mod.on_enabled = function()
	cleanup_done = false
	mark_dirty()
end

mod.on_game_state_changed = function(status, state_name)
	if status == "enter" and (state_name == "GameplayStateRun" or state_name == "StateGameplay") then
		if cache_reads_allowed() then
			refresh_cache_from_disk()
		end
		return
	end

	if cache_reads_allowed() or cache_runtime_dirty then
		ensure_cache_loaded()
		write_cache_file()
	end
	reset_runtime_state(true)
	cleanup_done = false
end

mod.on_disabled = function()
	if cache_reads_allowed() or cache_runtime_dirty then
		ensure_cache_loaded()
		write_cache_file()
	end
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

	local ritual_enabled = is_havoc_ritual_active()
	local ritual_units = ritual_enabled and find_ritual_units() or {}

	update_markers(ritual_units)
	update_timer_markers(ritual_units, dt or 0, t or 0)
	record_offline_cache(ritual_units, t or 0)
	draw_debug_lines(world, ritual_units, t or 0, ritual_enabled)
end
