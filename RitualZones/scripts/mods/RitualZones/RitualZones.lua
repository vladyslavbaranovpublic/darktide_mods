--[[
	File: RitualZones.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.2.0
	File Version: 1.2.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local mod = get_mod("RitualZones")
mod:register_hud_element({
	class_name = "HudElementRitualZones",
	filename = "RitualZones/scripts/mods/RitualZones/RitualZones_hud_element",
	use_hud_scale = true,
	visibility_groups = { "alive" },
})
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
	RESPAWN_REWIND_SAFE_MARGIN = 0,
	NAV_MESH_ABOVE = 5,
	NAV_MESH_BELOW = 5,
	TRIGGER_PAST_MARGIN = 1.0,
	PATH_START_CLAMP_RADIUS = 12,
	PATH_START_CLAMP_DISTANCE = 30,
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
		["Respawn Progress"] = { -0.25, -0.15, 2.0 },
		["Respawn Progress Warning"] = { -0.25, -0.35, 3.5 },
		["Respawn Progress Warning (You)"] = { -0.15, -0.55, 4.0 },
		["Respawn Progress Warning (Leader)"] = { 0.15, -0.55, 4.0 },
		["Respawn Warning Debug (You)"] = { -0.15, -0.75, 4.5 },
		["Respawn Warning Debug (Leader)"] = { 0.15, -0.75, 4.5 },
		["Respawn Beacon Threshold"] = { 0.15, -0.25, 2.0 },
		["Respawn Backline"] = { -0.35, -0.25, 1.5 },
		["Respawn Rewind Threshold"] = { 0.35, -0.35, 4.0 },
		["Respawn Rewind Lost"] = { 0.35, -0.35, 4.5 },
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
local CACHE_LABELS = {
	boss_trigger = { label = "Boss Trigger", loc = "label_boss_trigger" },
	boss_unit_trigger = { label = "Boss Unit Trigger", loc = "label_boss_unit_trigger" },
	boss_patrol_trigger = { label = "Boss Patrol Trigger", loc = "label_boss_patrol_trigger" },
	twins_spawn = { label = "Twins Spawn Trigger", loc = "label_twins_spawn_trigger" },
	twins_ambush = { label = "Twins Ambush Trigger", loc = "label_twins_ambush_trigger" },
	pacing_spawn = { label = "Pacing Spawn", loc = "label_pacing_spawn" },
	pacing_monsters = { label = "Pacing Spawn: monsters", loc = "label_pacing_spawn_monsters" },
	pacing_witches = { label = "Pacing Spawn: witches", loc = "label_pacing_spawn_witches" },
	pacing_captains = { label = "Pacing Spawn: captains", loc = "label_pacing_spawn_captains" },
	ambush_horde = { label = "Ambush Horde Trigger", loc = "label_ambush_horde_trigger" },
	backtrack_horde = { label = "Backtrack Horde Trigger", loc = "label_backtrack_horde_trigger" },
}
local cache_label_for_key = nil
local LABEL_LOCALIZATION_KEYS = {
	["Progress"] = "label_progress",
	["Progress (You)"] = "label_progress_you",
	["Progress (Leader)"] = "label_progress_leader",
	["Max Progress"] = "label_max_progress",
	["Boss Trigger"] = "label_boss_trigger",
	["Boss Unit Trigger"] = "label_boss_unit_trigger",
	["Boss Patrol Trigger"] = "label_boss_patrol_trigger",
	["Ambush Horde Trigger"] = "label_ambush_horde_trigger",
	["Backtrack Horde Trigger"] = "label_backtrack_horde_trigger",
	["Respawn Progress"] = "label_respawn_progress",
	["Respawn Progress Warning"] = "label_respawn_progress_warning",
	["Respawn Progress Warning (You)"] = "label_respawn_progress_warning_you",
	["Respawn Progress Warning (Leader)"] = "label_respawn_progress_warning_leader",
	["Respawn Warning Debug (You)"] = "label_respawn_warning_debug_you",
	["Respawn Warning Debug (Leader)"] = "label_respawn_warning_debug_leader",
	["Respawn Beacon Threshold"] = "label_respawn_beacon_threshold",
	["Respawn Backline"] = "label_respawn_backline",
	["Respawn Rewind Threshold"] = "label_respawn_rewind_threshold",
	["Respawn Rewind Lost"] = "label_respawn_rewind_lost",
	["Respawn Beacon"] = "label_respawn_beacon",
	["Priority Respawn Beacon"] = "label_priority_respawn_beacon",
	["Rescue Move Trigger"] = "label_rescue_move_trigger",
	["Rescue Move Trigger Warning"] = "label_rescue_move_trigger_warning",
	["Priority Move Trigger"] = "label_priority_move_trigger",
	["Priority Move Trigger Warning"] = "label_priority_move_trigger_warning",
	["Ritual Spawn Trigger"] = "label_ritual_spawn_trigger",
	["Ritual Start Trigger"] = "label_ritual_start_trigger",
	["Ritual Speedup Trigger"] = "label_ritual_speedup_trigger",
	["Twins Ambush Trigger"] = "label_twins_ambush_trigger",
	["Twins Spawn Trigger"] = "label_twins_spawn_trigger",
	["Pacing Spawn"] = "label_pacing_spawn",
	["Pacing Spawn: monsters"] = "label_pacing_spawn_monsters",
	["Pacing Spawn: witches"] = "label_pacing_spawn_witches",
	["Pacing Spawn: captains"] = "label_pacing_spawn_captains",
	["Trigger"] = "label_trigger",
}
local offline_cache = mod:persistent_table("offline_cache")
local cache_state = {
	loaded = false,
	load_failed = false,
	runtime_dirty = false,
	dirs_checked = false,
	write_fail_t = -math.huge,
	write_fail_count = 0,
	last_recorded_mission = nil,
	record_mission = nil,
	record_count = 0,
	last_skip_t = -math.huge,
	last_skip_reason = nil,
	last_update_t = -math.huge,
	last_record_enabled = nil,
	last_use_enabled = nil,
	last_use_offline_enabled = nil,
	last_clear_action = nil,
	last_reset_action = nil,
	resetting_settings = false,
	sweep_active = false,
	sweep_start_t = nil,
	sweep_duration = 0,
	sweep_path_total = 0,
	sweep_next_record_t = -math.huge,
	sweep_record_interval = 0,
	sweep_hold_until = nil,
}
local _io = Mods and Mods.lua and Mods.lua.io or nil
local _os = Mods and Mods.lua and Mods.lua.os or nil
local _loadstring = Mods and Mods.lua and Mods.lua.loadstring or nil

function cache_debug(message)
	if mod:get("cache_debug_enabled") then
		mod:echo("[RitualZones Cache] " .. tostring(message))
	end
end

function cache_debug_skip(reason, t, min_interval)
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
	if cache_state.last_skip_reason ~= reason or (now and (now - cache_state.last_skip_t) >= interval) then
		cache_debug(string.format("Record skipped: %s", reason))
		cache_state.last_skip_reason = reason
		if now then
			cache_state.last_skip_t = now
		end
	end
end

local markers = {}
local timer_markers = {}
local timer_state = {}
local debug_label_state = { markers = {}, generation = 0, marker_count = 0 }


local debug_label_limits = { max_markers = 200, hard_cap = 200, move_threshold_sq = 1.0 }


local pending_marker_cleanup = false
local debug_lines = { world = nil, object = nil }
local max_progress_distance = nil
local player_progress = {}
local boss_triggered = {}
local speedup_triggered = {}
local ritual_start_triggered = {}
local ritual_spawn_triggered = {}
local pacing_triggered = {}
local ambush_triggered = {}
local ritual_ended_units = {}
local markers_dirty = true
local timer_dirty = true
local marker_generation = 0
local cleanup_done = false
local debug_state = {
	text_manager = nil,
	text_world = nil,
	last_refresh_t = nil,
	last_label_refresh_t = nil,
	label_refresh_enabled = true,
	last_label_refresh_position = nil,
	force_label_refresh_frames = 0,
	last_labels_through_walls = nil,
	last_text_background = nil,
	text_z_offset = 0,
}
local respawn_state = {
	waiting_active = false,
	rewind_crossed = false,
	rewind_lost = false,
	safe_locked_active = false,
	safe_locked_distance = nil,
}
local last_active_respawn_beacon = nil
local last_active_respawn_beacon_distance = nil
local debug_label_scale_min = 0.75
local debug_label_scale_max = 1.0
local debug_label_scale_range = 120
local get_player_name = nil
local LineObject = rawget(_G, "LineObject")
local Color = rawget(_G, "Color")
local Matrix4x4 = rawget(_G, "Matrix4x4")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local World = rawget(_G, "World")
local Gui = rawget(_G, "Gui")
local Unit = rawget(_G, "Unit")

function resolve_debug_modules()
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

function is_gameplay_state()
	if not Managers or not Managers.state or not Managers.state.game_mode then
		return false
	end

	local game_mode = Managers.state.game_mode:game_mode_name()
	if game_mode == "hub" then
		return false
	end

	return true
end

function is_server()
	return Managers.state and Managers.state.game_session and Managers.state.game_session:is_server() or false
end

function cache_use_enabled()
	local use_enabled = mod:get("cache_use_enabled")
	if use_enabled == nil then
		return true
	end
	return use_enabled
end

function cache_use_offline_enabled()
	return mod:get("cache_use_offline_enabled") or false
end

function cache_record_enabled()
	return mod:get("cache_record_enabled") or false
end

function debug_text_mode()
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
	if type(mode) == "string" then
		local lowered = string.lower(mode)
		if lowered == "true" then
			return "both"
		end
		if lowered == "false" then
			return "off"
		end
		if lowered == "labels only" or lowered == "labelsonly" then
			return "labels"
		end
		if lowered == "distances only" or lowered == "distancesonly" then
			return "distances"
		end
		if lowered == "labels + distances" or lowered == "labels+distances" then
			return "both"
		end
		if lowered == "on" or lowered == "off" or lowered == "labels" or lowered == "distances" or lowered == "both" then
			return lowered
		end
		return "on"
	end
	return mode
end

function debug_text_enabled_mode(mode)
	return mode == "on"
		or mode == "labels"
		or mode == "distances"
		or mode == "both"
end

function debug_text_show_labels(mode)
	return mode == "on" or mode == "labels" or mode == "both"
end

function debug_text_show_distances(mode)
	return mode == "on" or mode == "distances" or mode == "both"
end

function cache_reads_allowed()
	return cache_use_enabled() or cache_use_offline_enabled() or cache_record_enabled()
end

function is_havoc_ritual_active()
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

function can_record_cache()
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

function get_mission_name()
	local mission_manager = Managers.state and Managers.state.mission
	if mission_manager and mission_manager.mission_name then
		local ok, mission_name = pcall(mission_manager.mission_name, mission_manager)
		if ok then
			return mission_name
		end
	end
	return nil
end

function get_cache_root()
	local root = offline_cache.maps
	if not root then
		root = {}
		offline_cache.maps = root
	end
	return root
end

function normalize_path(path)
	if not path or path == "" then
		return nil
	end
	path = path:gsub("/", "\\")
	path = path:gsub("\\+$", "")
	return path
end

function mod_root_from_script()
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

function script_mod_root()
	if not mod or type(mod.script_mod_path) ~= "function" then
		return nil
	end
	local ok, script_path = pcall(mod.script_mod_path, mod)
	if not ok or not script_path or script_path == "" then
		return nil
	end
	return normalize_path(script_path)
end

function resolve_mod_root()
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

function build_mod_path(relative_path)
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

function get_appdata_cache_paths()
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

function get_script_cache_paths()
	local mod_name = "RitualZones"
	if mod and type(mod.get_name) == "function" then
		local ok, name = pcall(mod.get_name, mod)
		if ok and name and name ~= "" then
			mod_name = name
		end
	end
	local function is_absolute(path)
		return path and (path:match("^%a:[/\\]") or path:match("^\\\\"))
	end
	local function mods_root_from_binaries(path)
		if not path then
			return nil
		end
		local normalized = normalize_path(path)
		if not normalized then
			return nil
		end
		local base = normalized:match("^(.*)[/\\]binaries[/\\].*$") or normalized:match("^(.*)[/\\]binaries$")
		if not base then
			return nil
		end
		return normalize_path(base .. "\\mods")
	end
	local function mods_root_from_cwd()
		if not _io or not _io.popen then
			return nil
		end
		local handle = _io.popen("cd")
		if not handle then
			return nil
		end
		local cwd = handle:read("*l")
		handle:close()
		if not cwd or cwd == "" then
			return nil
		end
		cwd = normalize_path(cwd)
		local root = cwd:match("^(.*)[/\\]binaries[/\\].*$") or cwd:match("^(.*)[/\\]binaries$")
		if not root then
			root = cwd:match("^(.*[/\\]mods)[/\\].*$") or cwd:match("^(.*[/\\]mods)$")
			if root then
				return normalize_path(root)
			end
		end
		if not root then
			return nil
		end
		return normalize_path(root .. "\\mods")
	end
	local root = nil
	local cwd_mods_root = mods_root_from_cwd()
	if cwd_mods_root then
		root = normalize_path(cwd_mods_root .. "\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
	end
	if mod and type(mod.get_mod_path) == "function" then
		local ok, value = pcall(mod.get_mod_path, mod)
		if ok and value and value ~= "" then
			local normalized = normalize_path(value)
			if normalized and is_absolute(normalized) and not root then
				local forced_mods_root = mods_root_from_binaries(normalized)
				if forced_mods_root then
					root = normalize_path(forced_mods_root .. "\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
				else
					root = normalize_path(normalized .. "\\scripts\\mods\\" .. mod_name)
				end
			end
		end
	end
	if not root and mod and mod._path and mod._path ~= "" then
		local normalized = normalize_path(mod._path)
		if normalized and is_absolute(normalized) then
			local forced_mods_root = mods_root_from_binaries(normalized)
			if forced_mods_root then
				root = normalize_path(forced_mods_root .. "\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
			else
				root = normalize_path(normalized .. "\\scripts\\mods\\" .. mod_name)
			end
		end
	end
	local mod_root = mod_root_from_script() or resolve_mod_root()
	if not root and mod_root and is_absolute(mod_root) then
		local forced_mods_root = mods_root_from_binaries(mod_root)
		if forced_mods_root then
			root = normalize_path(forced_mods_root .. "\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
		else
			root = normalize_path(mod_root .. "\\scripts\\mods\\" .. mod_name)
		end
	end
	if not root then
		root = script_mod_root()
		local forced_mods_root = mods_root_from_binaries(root)
		if forced_mods_root then
			root = normalize_path(forced_mods_root .. "\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
		elseif root and not is_absolute(root) and mod_root and is_absolute(mod_root) then
			root = normalize_path(mod_root .. "\\" .. root)
		elseif root and is_absolute(root) then
			root = normalize_path(root)
		end
	end
	if not root then
		root = build_mod_path("scripts/mods/" .. mod_name)
		root = normalize_path(root)
	end
	if root and not is_absolute(root) then
		local mods_root = mods_root_from_cwd()
		if mods_root then
			root = normalize_path(mods_root .. "\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
		end
	end
	if not root then
		root = normalize_path("mods\\" .. mod_name .. "\\scripts\\mods\\" .. mod_name)
	end
	local dir = root and (root .. "\\cache") or nil
	local file = dir and (dir .. "\\ritualzones_cache.lua") or nil
	return dir, file
end

function get_primary_cache_paths()
	local app_dir, app_file = get_appdata_cache_paths()
	if app_dir and app_file then
		return app_dir, app_file
	end
	return get_script_cache_paths()
end

function mkdir(path)
	if not path or not _os or not _os.execute then
		return false
	end
	local normalized = path:gsub("/", "\\")
	local ok = _os.execute('if not exist "' .. normalized .. '" mkdir "' .. normalized .. '"')
	return ok == true or ok == 0
end

function ensure_cache_dir()
	if cache_state.dirs_checked then
		return
	end
	cache_state.dirs_checked = true
	if not _io or not _os or not _os.execute then
		return
	end
	local cache_dir = select(1, get_appdata_cache_paths())
	if cache_dir then
		mkdir(cache_dir)
	end
	local script_dir = select(1, get_script_cache_paths())
	if script_dir then
		mkdir(script_dir)
	end
end

function cache_file_exists()
	if not _io then
		return false
	end
	local _, cache_file = get_appdata_cache_paths()
	local file = cache_file and _io.open(cache_file, "r")
	if file then
		file:close()
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
local add_beacon_to_cache = nil
local normalize_label_map = nil
local is_finite_number = nil

function sanitize_cache_content(content)
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

function is_array_table(tbl)
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

function serialize_value(value, indent)
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
	if cache_state.loaded or not _io or not _loadstring then
		return
	end

	local _, script_file = get_script_cache_paths()
	local _, app_file = get_appdata_cache_paths()
	local tried_paths = {
		{ path = script_file, label = "script_cache" },
		{ path = app_file, label = "appdata_cache" },
	}

	local loaded_any = false
	local parse_error = false
	local loaded_script = false
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
				respawn_progress_points = {},
				respawn_beacons = {},
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
		entry.respawn_progress_points = entry.respawn_progress_points or {}
		entry.respawn_beacons = entry.respawn_beacons or {}
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
		local function merge_label_map(target_list, source_list, default_label)
			if not source_list then
				return
			end
			if is_array_table(source_list) then
				for i = 1, #source_list do
					local item = source_list[i]
					if type(item) == "table" then
						add_entry_to_cache(target_list, item.distance, item.label or default_label)
					else
						add_entry_to_cache(target_list, item, default_label)
					end
				end
				return
			end
			for key, bucket in pairs(source_list) do
				local label = cache_label_for_key(key) or default_label or key
				if is_array_table(bucket) then
					for i = 1, #bucket do
						add_entry_to_cache(target_list, bucket[i], label)
					end
				elseif type(bucket) == "table" and bucket.distance then
					add_entry_to_cache(target_list, bucket.distance, bucket.label or label)
				end
			end
		end

		merge_label_map(target.boss, source.boss, "Boss Trigger")
		merge_label_map(target.pacing, source.pacing, "Pacing Spawn")
		merge_label_map(target.ambush, source.ambush, "Ambush Horde Trigger")
		local respawn = source.respawn or {}
		for i = 1, #respawn do
			add_distance_to_cache(target.respawn, respawn[i])
		end
		local respawn_points = source.respawn_progress_points or source.respawn_points or {}
		for i = 1, #respawn_points do
			local item = respawn_points[i]
			if type(item) == "table" then
				add_beacon_to_cache(
					target.respawn_progress_points,
					item.distance,
					item.position or item.pos or item.location
				)
			elseif is_finite_number(item) then
				add_beacon_to_cache(target.respawn_progress_points, item, nil)
			end
		end
		local respawn_beacons = source.respawn_beacons or {}
		for i = 1, #respawn_beacons do
			local item = respawn_beacons[i]
			if type(item) == "table" then
				add_beacon_to_cache(
					target.respawn_beacons,
					item.distance,
					item.position or item.pos or item.location,
					nil,
					item.priority or item.is_priority or item.is_priority_beacon or item.is_priority_respawn_beacon
				)
			end
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
		cache_state.load_failed = false
	else
		cache_state.load_failed = parse_error
	end
	cache_state.loaded = true
	if loaded_any then
		write_cache_file()
		local map_count = 0
		for _ in pairs(merged_maps) do
			map_count = map_count + 1
		end
		cache_debug(string.format("Loaded cache (maps=%d, script=%s, appdata=%s)", map_count, tostring(loaded_script), tostring(loaded_app)))
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
	if not cache_reads_allowed() and not cache_state.runtime_dirty then
		cache_debug("Cache write skipped (disabled)")
		return
	end
	if cache_state.write_fail_count > 0 then
		local now = nil
		if Managers.time and Managers.time.time then
			local ok, value = pcall(Managers.time.time, Managers.time, "gameplay")
			if ok then
				now = value
			end
		end
		if not now then
			now = os.time()
		end
		local backoff = math.min(60, math.max(2, 2 ^ cache_state.write_fail_count))
		if (now - cache_state.write_fail_t) < backoff then
			cache_debug_skip("cache write backoff", now, backoff)
			return
		end
	end
	ensure_cache_loaded()
	if cache_state.load_failed and cache_file_exists() and not cache_state.runtime_dirty then
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

	local _, app_file = get_appdata_cache_paths()
	local _, script_file = get_script_cache_paths()
	local wrote_app = write_to(app_file, "appdata")
	local wrote_script = write_to(script_file, "script")
	if not wrote_app and not wrote_script then
		local now = nil
		if Managers.time and Managers.time.time then
			local ok, value = pcall(Managers.time.time, Managers.time, "gameplay")
			if ok then
				now = value
			end
		end
		if not now then
			now = os.time()
		end
		cache_state.write_fail_count = math.min(cache_state.write_fail_count + 1, 10)
		cache_state.write_fail_t = now
		cache_debug(string.format("Cache write failed; backing off (count=%d)", cache_state.write_fail_count))
		return
	end
	cache_state.write_fail_count = 0
	cache_state.write_fail_t = -math.huge
	cache_state.runtime_dirty = false
end

ensure_cache_loaded = function()
	if cache_state.loaded then
		return
	end
	if not cache_reads_allowed() then
		cache_debug("Cache load skipped (disabled)")
		return
	end
	if not is_gameplay_state() then
		cache_debug_skip("cache load deferred: not in gameplay", nil, 5)
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
			respawn_progress_points = {},
			respawn_beacons = {},
		}
		root[mission_name] = entry
		created = true
	end
	entry.path = entry.path or {}
	entry.ritual = entry.ritual or { spawn = {}, start = {}, speedup = {} }
	entry.ritual.spawn = entry.ritual.spawn or {}
	entry.ritual.start = entry.ritual.start or {}
	entry.ritual.speedup = entry.ritual.speedup or {}
	entry.boss = normalize_label_map(entry.boss or {}, "Boss Trigger")
	entry.pacing = normalize_label_map(entry.pacing or {}, "Pacing Spawn")
	entry.ambush = normalize_label_map(entry.ambush or {}, "Ambush Horde Trigger")
	entry.respawn = entry.respawn or {}
	entry.respawn_progress_points = entry.respawn_progress_points or {}
	entry.respawn_beacons = entry.respawn_beacons or {}
	return entry, created
end

local function refresh_cache_from_disk()
	if not cache_reads_allowed() then
		cache_debug("Cache refresh skipped (disabled)")
		return
	end
	if cache_state.runtime_dirty then
		write_cache_file()
	end
	cache_state.loaded = false
	cache_state.load_failed = false
	if not is_gameplay_state() then
		cache_debug_skip("cache load deferred: not in gameplay", nil, 5)
		return
	end
	load_cache_file()
end

function mod.clear_cache_keybind_func()
	if not _os then
		mod:echo("[RitualZones Cache] Cache clear skipped: no os module")
		return
	end

	local function delete_cache_file(path, label)
		if not path or path == "" then
			cache_debug(string.format("Cache clear skipped (%s): no path", tostring(label)))
			return false
		end

		local removed = false
		if _os.remove then
			local ok = _os.remove(path)
			if ok then
				removed = true
			end
		end
		if not removed and _os.execute then
			local normalized = path:gsub("/", "\\")
			_os.execute('del /q "' .. normalized .. '"')
			removed = true
		end

		if removed then
			cache_debug(string.format("Cache cleared (%s): %s", tostring(label), tostring(path)))
		else
			cache_debug(string.format("Cache clear failed (%s): %s", tostring(label), tostring(path)))
		end
		return removed
	end

	local _, app_file = get_appdata_cache_paths()
	local _, script_file = get_script_cache_paths()
	delete_cache_file(app_file, "appdata")
	delete_cache_file(script_file, "script")

	offline_cache.version = CACHE.VERSION
	offline_cache.maps = {}
	cache_state.loaded = true
	cache_state.load_failed = false
	cache_state.runtime_dirty = false
	cache_state.record_mission = nil
	cache_state.record_count = 0
	cache_state.last_skip_reason = nil
	cache_state.last_skip_t = -math.huge

	mod:echo("[RitualZones Cache] Cache cleared")
end

function mod.cache_sweep_keybind_func()
	if cache_state.sweep_active then
		cache_state.sweep_active = false
		cache_state.sweep_start_t = nil
		cache_state.sweep_hold_until = nil
		mod:echo("[RitualZones Cache] Cache sweep canceled")
		return
	end
	if not cache_record_enabled() then
		mod:echo("[RitualZones Cache] Cache sweep skipped: record offline cache disabled")
		return
	end
	if not is_gameplay_state() then
		mod:echo("[RitualZones Cache] Cache sweep skipped: not in gameplay")
		return
	end
	if not can_record_cache() then
		mod:echo("[RitualZones Cache] Cache sweep skipped: not server/host")
		return
	end
	local path_total = MainPathQueries.total_path_distance and MainPathQueries.total_path_distance()
	if not path_total or not is_finite_number(path_total) or path_total <= 0 then
		mod:echo("[RitualZones Cache] Cache sweep skipped: no valid main path")
		return
	end
	local duration = tonumber(mod:get("cache_sweep_duration")) or 15
	if duration < 5 then
		duration = 5
	elseif duration > 30 then
		duration = 30
	end
	cache_state.sweep_active = true
	cache_state.sweep_start_t = nil
	cache_state.sweep_duration = duration
	cache_state.sweep_path_total = path_total
	cache_state.sweep_next_record_t = -math.huge
	cache_state.sweep_record_interval = math.max(0.1, duration / CACHE.MAX_RECORDS_PER_MISSION)
	cache_state.sweep_hold_until = nil
	cache_state.last_update_t = -math.huge
	cache_state.record_count = 0
	cache_debug(string.format("Cache sweep started (%.1fs)", duration))
end

function update_cache_sweep(t)
	if not cache_state.sweep_active then
		return
	end
	if not cache_record_enabled() then
		cache_state.sweep_active = false
		cache_state.sweep_start_t = nil
		cache_state.sweep_hold_until = nil
		cache_debug("Cache sweep stopped: record disabled")
		return
	end
	if not can_record_cache() then
		cache_state.sweep_active = false
		cache_state.sweep_start_t = nil
		cache_state.sweep_hold_until = nil
		cache_debug("Cache sweep stopped: not server/host")
		return
	end
	local path_total = cache_state.sweep_path_total
	if not path_total or not is_finite_number(path_total) or path_total <= 0 then
		cache_state.sweep_active = false
		cache_state.sweep_start_t = nil
		cache_state.sweep_hold_until = nil
		cache_debug("Cache sweep stopped: invalid path")
		return
	end
	local now = t or 0
	if cache_state.sweep_start_t == nil then
		cache_state.sweep_start_t = now
		cache_state.sweep_next_record_t = now
	end
	local duration = cache_state.sweep_duration or 1
	if duration <= 0 then
		duration = 1
	end
	local ratio = math.min(math.max((now - cache_state.sweep_start_t) / duration, 0), 1)
	local distance = ratio * path_total
	local position = MainPathQueries.position_from_distance and MainPathQueries.position_from_distance(distance)
	if position and Managers.player and Managers.player.local_player then
		local player = Managers.player:local_player(1)
		local unit = player and player.player_unit
		if unit and Unit.alive and Unit.alive(unit) then
			local movement = mod._player_movement
			if movement == nil then
				local ok, value = pcall(require, "scripts/utilities/player_movement")
				if ok then
					movement = value
					mod._player_movement = value
				end
			end
			if movement and movement.teleport_fixed_update then
				movement.teleport_fixed_update(unit, position, Unit.local_rotation(unit, 1))
			elseif movement and movement.teleport then
				movement.teleport(unit, position)
			elseif Unit.set_local_position then
				Unit.set_local_position(unit, 1, position)
			end
		end
	end
	if now >= (cache_state.sweep_next_record_t or -math.huge) then
		cache_state.last_update_t = -math.huge
		cache_state.sweep_next_record_t = now + (cache_state.sweep_record_interval or 0.5)
	end
	if ratio >= 1 then
		if cache_state.sweep_hold_until == nil then
			cache_state.sweep_hold_until = now + 1
			cache_state.last_update_t = -math.huge
		elseif now >= cache_state.sweep_hold_until then
			cache_state.sweep_active = false
			cache_state.sweep_start_t = nil
			cache_state.sweep_hold_until = nil
			cache_debug("Cache sweep finished")
		end
	end
end

local function vector_to_table(vec)
	if not vec then
		return nil
	end
	if type(vec) == "table" then
		local x = vec[1] or vec.x
		local y = vec[2] or vec.y
		local z = vec[3] or vec.z
		if is_finite_number(x) and is_finite_number(y) and is_finite_number(z) then
			return { x, y, z }
		end
	end
	if not Vector3 or not Vector3.x then
		return nil
	end
	local ok_x, x = pcall(Vector3.x, vec)
	if not ok_x then
		return nil
	end
	local ok_y, y = pcall(Vector3.y, vec)
	if not ok_y then
		return nil
	end
	local ok_z, z = pcall(Vector3.z, vec)
	if not ok_z then
		return nil
	end
	return { x, y, z }
end

local function vector_from_table(tbl)
	if not tbl or not Vector3 then
		return nil
	end
	local x = tbl[1] or tbl.x
	local y = tbl[2] or tbl.y
	local z = tbl[3] or tbl.z
	if not is_finite_number(x) or not is_finite_number(y) or not is_finite_number(z) then
		return nil
	end
	return Vector3(x, y, z)
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

local function cache_key_for_label(label, fallback_key)
	if not label then
		return fallback_key
	end
	for key, data in pairs(CACHE_LABELS) do
		if data.label == label then
			return key
		end
	end
	if label:find("Pacing Spawn:", 1, true) then
		local lower = string.lower(label)
		if lower:find("monsters", 1, true) then
			return "pacing_monsters"
		elseif lower:find("witches", 1, true) then
			return "pacing_witches"
		elseif lower:find("captains", 1, true) then
			return "pacing_captains"
		end
		return "pacing_spawn"
	end
	return fallback_key
end

cache_label_for_key = function(key)
	local data = key and CACHE_LABELS[key] or nil
	return data and data.label or key
end

local function cache_loc_key_for_label(label)
	local loc_key = LABEL_LOCALIZATION_KEYS[label]
	if loc_key then
		return loc_key
	end
	local key = cache_key_for_label(label)
	local data = key and CACHE_LABELS[key] or nil
	return data and data.loc or nil
end

distance_exists = function(list, distance, tolerance, label)
	if not list or not distance then
		return false
	end
	if not is_array_table(list) then
		if label then
			local key = cache_key_for_label(label, label)
			local bucket = key and list[key] or nil
			if bucket and is_array_table(bucket) then
				for i = 1, #bucket do
					if math.abs(bucket[i] - distance) <= tolerance then
						return true
					end
				end
			end
		else
			for _, bucket in pairs(list) do
				if is_array_table(bucket) then
					for i = 1, #bucket do
						if math.abs(bucket[i] - distance) <= tolerance then
							return true
						end
					end
				end
			end
		end
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
	local tol = tolerance or CACHE.DISTANCE_TOLERANCE
	local key = cache_key_for_label(label, label)
	local use_map = key and (not is_array_table(list) or next(list) == nil)
	if use_map then
		local bucket = list[key]
		if not bucket then
			bucket = {}
			list[key] = bucket
		end
		if distance_exists(bucket, distance, tol) then
			return false
		end
		bucket[#bucket + 1] = distance
		return true
	end
	if is_array_table(list) then
		if distance_exists(list, distance, tol, label) then
			return false
		end
		list[#list + 1] = {
			distance = distance,
			label = label,
		}
		return true
	end
	return false
end

add_beacon_to_cache = function(list, distance, position, tolerance, is_priority)
	if not distance or not list or not is_finite_number(distance) then
		return false
	end
	if type(tolerance) == "boolean" and is_priority == nil then
		is_priority = tolerance
		tolerance = nil
	end
	local pos_tbl = vector_to_table(position) or position
	if pos_tbl and type(pos_tbl) ~= "table" then
		pos_tbl = nil
	end
	local tol = tolerance or CACHE.DISTANCE_TOLERANCE
	for i = 1, #list do
		local item = list[i]
		local item_distance = type(item) == "table" and item.distance or nil
		if item_distance and math.abs(item_distance - distance) <= tol then
			local updated = false
			if pos_tbl and type(item) == "table" and not item.position then
				item.position = pos_tbl
				updated = true
			end
			if is_priority and type(item) == "table" and not item.priority then
				item.priority = true
				updated = true
			end
			return updated
		end
	end
	local entry = {
		distance = distance,
		position = pos_tbl,
	}
	if is_priority then
		entry.priority = true
	end
	list[#list + 1] = entry
	return true
end

normalize_label_map = function(list, default_label)
	if not list then
		return {}
	end
	if is_array_table(list) then
		local normalized = {}
		for i = 1, #list do
			local item = list[i]
			if type(item) == "table" then
				add_entry_to_cache(normalized, item.distance, item.label or default_label)
			elseif is_finite_number(item) then
				add_entry_to_cache(normalized, item, default_label)
			end
		end
		return normalized
	end
	return list
end

local function get_cache_entry(mission_name, path_total)
	ensure_cache_loaded()
	if not mission_name then
		cache_debug_skip("cache lookup skipped: no mission name", nil, 5)
		return nil
	end
	local root = offline_cache.maps
	if not root then
		cache_debug_skip("cache lookup skipped: empty cache", nil, 5)
		return nil
	end
	local entry = root[mission_name]
	if not entry or entry.version ~= CACHE.VERSION then
		cache_debug_skip(string.format("cache miss: %s", tostring(mission_name)), nil, 5)
		return nil
	end
	local cached_total = entry.path and entry.path.total
	if cached_total and path_total then
		local tolerance = tonumber(mod:get("cache_path_tolerance")) or CACHE.PATH_TOLERANCE
		tolerance = math.max(0, tolerance)
		local diff = math.abs(cached_total - path_total)
		if diff > tolerance then
			cache_debug_skip(
				string.format(
					"cache path mismatch: %s (cached=%.1f current=%.1f diff=%.1f tol=%.1f)",
					tostring(mission_name),
					cached_total,
					path_total,
					diff,
					tolerance
				),
				nil,
				5
			)
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
	local boss = entry.boss
	if is_array_table(boss) then
		for i = 1, #boss do
			local item = boss[i]
			local label = type(item) == "table" and item.label or "Boss Trigger"
			local distance = type(item) == "table" and item.distance or item
			if distance and is_finite_number(distance) then
				list[#list + 1] = {
					distance = distance,
					label = label,
					key = string.format("boss_cache:%s:%.2f", tostring(label), distance),
				}
			end
		end
		return list
	end
	for key, bucket in pairs(boss) do
		if is_array_table(bucket) then
			local label = cache_label_for_key(key)
			for i = 1, #bucket do
				local distance = bucket[i]
				if is_finite_number(distance) then
					list[#list + 1] = {
						distance = distance,
						label = label,
						key = string.format("boss_cache:%s:%.2f", tostring(key), distance),
					}
				end
			end
		end
	end
	return list
end

local function cached_pacing_triggers(entry)
	local list = {}
	if not entry or not entry.pacing then
		return list
	end
	local pacing = entry.pacing
	if is_array_table(pacing) then
		for i = 1, #pacing do
			local item = pacing[i]
			local label = type(item) == "table" and item.label or "Pacing Spawn"
			local distance = type(item) == "table" and item.distance or item
			if distance and is_finite_number(distance) then
				list[#list + 1] = {
					distance = distance,
					label = label,
					key = string.format("pacing_cache:%s:%.2f", tostring(label), distance),
				}
			end
		end
		return list
	end
	for key, bucket in pairs(pacing) do
		if is_array_table(bucket) then
			local label = cache_label_for_key(key)
			for i = 1, #bucket do
				local distance = bucket[i]
				if is_finite_number(distance) then
					list[#list + 1] = {
						distance = distance,
						label = label,
						key = string.format("pacing_cache:%s:%.2f", tostring(key), distance),
					}
				end
			end
		end
	end
	return list
end

local function cached_ambush_triggers(entry)
	local list = {}
	if not entry or not entry.ambush then
		return list
	end
	local ambush = entry.ambush
	if is_array_table(ambush) then
		for i = 1, #ambush do
			local item = ambush[i]
			local label = type(item) == "table" and item.label or "Ambush Horde Trigger"
			local distance = type(item) == "table" and item.distance or item
			if distance and is_finite_number(distance) then
				list[#list + 1] = {
					distance = distance,
					label = label,
					key = string.format("ambush_cache:%s:%.2f", tostring(label), distance),
				}
			end
		end
		return list
	end
	for key, bucket in pairs(ambush) do
		if is_array_table(bucket) then
			local label = cache_label_for_key(key)
			for i = 1, #bucket do
				local distance = bucket[i]
				if is_finite_number(distance) then
					list[#list + 1] = {
						distance = distance,
						label = label,
						key = string.format("ambush_cache:%s:%.2f", tostring(key), distance),
					}
				end
			end
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

local function cached_respawn_progress_points(entry)
	if not entry or not entry.respawn_progress_points then
		return {}
	end
	return entry.respawn_progress_points
end

local function cached_respawn_beacons(entry)
	if not entry or not entry.respawn_beacons then
		return {}
	end
	return entry.respawn_beacons
end

local function cached_priority_beacon(entry)
	if not entry or not entry.respawn_beacons then
		return nil, nil
	end
	local best_distance = nil
	local best_position = nil
	for i = 1, #entry.respawn_beacons do
		local item = entry.respawn_beacons[i]
		if type(item) == "table" and item.distance and (item.priority or item.is_priority or item.is_priority_beacon or item.is_priority_respawn_beacon) then
			if not best_distance or item.distance > best_distance then
				best_distance = item.distance
				best_position = vector_from_table(item.position or item.pos or item.location)
			end
		end
	end
	return best_distance, best_position
end

local function unit_is_alive(unit)
	if not unit then
		return false
	end
	if ScriptUnit and ScriptUnit.has_extension then
		local health_ext = ScriptUnit.has_extension(unit, "health_system")
		if health_ext and health_ext.is_alive then
			local ok, alive = pcall(health_ext.is_alive, health_ext)
			if ok then
				return alive and true or false
			end
		end
	end
	if ALIVE then
		return ALIVE[unit]
	end
	return Unit.alive and Unit.alive(unit)
end

is_finite_number = function(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function localize_label(key, fallback)
	if mod and mod.localize then
		local ok, value = pcall(mod.localize, mod, key)
		if ok and value and value ~= key then
			return value
		end
	end
	return fallback or key
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
		local start_pos = MainPathQueries.position_from_distance(0)
		if start_pos then
			local ahead_pos = MainPathQueries.position_from_distance(1)
			if ahead_pos then
				local dir = ahead_pos - start_pos
				if Vector3.length(dir) > 0.001 then
					dir = Vector3.normalize(dir)
					local start_dot = Vector3.dot(position - start_pos, dir)
					if start_dot < 0 then
						return 0
					end
				end
			end
			local start_distance = safe_distance(position, start_pos)
			if start_distance
				and start_distance <= CONST.PATH_START_CLAMP_RADIUS
				and travel_distance > CONST.PATH_START_CLAMP_DISTANCE then
				return 0
			end
		end
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
				CONST.NAV_MESH_ABOVE,
				CONST.NAV_MESH_BELOW,
				1,
				1
			)
		end
		if not nav_position then
			nav_position = NavQueries.position_on_mesh(
				nav_world,
				position,
				CONST.NAV_MESH_ABOVE,
				CONST.NAV_MESH_BELOW,
				traverse_logic
			)
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
				CONST.NAV_MESH_ABOVE,
				CONST.NAV_MESH_BELOW,
				1,
				1
			)
		end
		if not manager_nav_position then
			manager_nav_position = NavQueries.position_on_mesh(
				manager_nav_world,
				position,
				CONST.NAV_MESH_ABOVE,
				CONST.NAV_MESH_BELOW,
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
			local slot = player.slot and player:slot()
			entries[#entries + 1] = {
				player = player,
				unit = unit,
				distance = entry.distance,
				alive = entry.alive,
				is_local = player == local_player,
				slot = slot,
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

local function get_respawn_beacon_ahead_distance(respawn_system)
	local default_distance = CONST.RESPAWN_BEACON_AHEAD_DISTANCE
	if not respawn_system then
		return default_distance
	end
	local distance = respawn_system._respawn_beacon_ahead_distance
		or respawn_system._beacon_ahead_distance
		or respawn_system._respawn_ahead_distance
		or respawn_system._ahead_distance
		or respawn_system.respawn_beacon_ahead_distance
		or respawn_system.beacon_ahead_distance
	if is_finite_number(distance) then
		return distance
	end
	local settings = respawn_system._settings or respawn_system.settings
	if settings and is_finite_number(settings.respawn_beacon_ahead_distance) then
		return settings.respawn_beacon_ahead_distance
	end
	return default_distance
end

local function collect_respawn_progress_distances()
	local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
	local distances = {}
	local seen = {}
	local ahead_distance = get_respawn_beacon_ahead_distance(respawn_system)

	local function add_distance(distance)
		if not distance then
			return
		end
		local progress = math.max(0, distance - ahead_distance)
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

local function get_active_respawn_progress_distance(path_total, reference_distance)
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

	if active_distance then
		local ahead_distance = get_respawn_beacon_ahead_distance(respawn_system)
		local progress = active_distance - ahead_distance
		if path_total then
			progress = math.max(0, math.min(progress, path_total))
		end
		return progress
	end

	local distances = collect_respawn_progress_distances()
	if #distances == 0 then
		return nil
	end

	local best_distance = nil
	if reference_distance then
		for i = 1, #distances do
			local candidate = distances[i]
			if candidate and candidate >= reference_distance then
				if not best_distance or candidate < best_distance then
					best_distance = candidate
				end
			end
		end
	end
	if not best_distance then
		for i = 1, #distances do
			local candidate = distances[i]
			if candidate and is_finite_number(candidate) then
				if not best_distance or candidate > best_distance then
					best_distance = candidate
				end
			end
		end
	end
	if best_distance and path_total then
		best_distance = math.max(0, math.min(best_distance, path_total))
	end
	return best_distance
end

local function collect_respawn_beacon_entries(path_total, fallback_progress, cache_entry, allow_path_fallback)
	local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
	local entries = {}
	local seen = {}
	local priority_unit = get_priority_respawn_beacon_unit(respawn_system)
	local cached_beacons = cached_respawn_beacons(cache_entry)
	local ahead_distance = get_respawn_beacon_ahead_distance(respawn_system)
	if allow_path_fallback == nil then
		allow_path_fallback = true
	end

	local function find_cached_position(distance)
		if not cached_beacons or not distance then
			return nil
		end
		local tol = CACHE.DISTANCE_TOLERANCE
		for i = 1, #cached_beacons do
			local item = cached_beacons[i]
			if type(item) == "table" and item.distance and math.abs(item.distance - distance) <= tol then
				local pos = vector_from_table(item.position or item.pos or item.location)
				if pos then
					return pos
				end
			end
		end
		return nil
	end

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
		if not position then
			position = find_cached_position(distance)
		end
		if not position and allow_path_fallback then
			position = MainPathQueries.position_from_distance(distance)
		end
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
					add_entry(distance, position, unit, is_priority)
				end
			end
		end
	end

	if #entries == 0 and cached_beacons and #cached_beacons > 0 then
		for i = 1, #cached_beacons do
			local item = cached_beacons[i]
			if type(item) == "table" and item.distance then
				local pos = vector_from_table(item.position or item.pos or item.location)
				add_entry(item.distance, pos, nil, false)
			end
		end
	end

	if #entries == 0 and fallback_progress then
		for i = 1, #fallback_progress do
			local distance = fallback_progress[i] + ahead_distance
			local position = nil
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
	local base_label = localize_label("rescue_move_trigger_label", "Rescue Move Trigger")

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
					local label = base_label
					local name = get_player_name(player)
					if name then
						label = string.format("%s (%s)", base_label, name)
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

collect_priority_move_triggers = function(path_total, mode, priority_unit, priority_distance)
	if mode == "off" then
		return {}
	end
	if mode == "hogtied" and not has_hogtied_players() then
		return {}
	end
	if not priority_unit and not priority_distance then
		return {}
	end

	local base_distance = priority_distance
	if not base_distance and priority_unit then
		local position = get_unit_position(priority_unit)
		base_distance = position and (get_position_travel_distance(position) or get_unit_travel_distance(priority_unit))
	end
	if not base_distance or not is_finite_number(base_distance) then
		return {}
	end
	local trigger_distance = base_distance + CONST.RESPAWN_MOVE_TRIGGER_DISTANCE
	if path_total then
		trigger_distance = math.max(0, math.min(trigger_distance, path_total))
	end
	local behind_distance = get_behind_player_distance()
	local passed = behind_distance and behind_distance > trigger_distance
	return {
		{
			distance = trigger_distance,
			label = localize_label("priority_move_trigger_label", "Priority Move Trigger (Teleports teammates)"),
			passed = passed,
		},
	}
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
	if mission_name ~= cache_state.record_mission then
		cache_state.record_mission = mission_name
		cache_state.record_count = 0
	end
	if cache_state.record_count >= CACHE.MAX_RECORDS_PER_MISSION then
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
	if t and (t - cache_state.last_update_t) < update_interval then
		cache_debug_skip("update interval", t, update_interval)
		return
	end
	cache_state.last_update_t = t or 0

	local entry, created = ensure_cache_entry(mission_name)
	local updated = created
	if mission_name ~= cache_state.last_recorded_mission then
		cache_state.last_recorded_mission = mission_name
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
			local distance = respawn_distances[i]
			updated = add_distance_to_cache(entry.respawn, distance) or updated
			if distance and MainPathQueries.position_from_distance then
				local position = MainPathQueries.position_from_distance(distance)
				if position then
					updated = add_beacon_to_cache(entry.respawn_progress_points, distance, position) or updated
				end
			end
		end
		local respawn_beacons = collect_respawn_beacon_entries(path_total, nil, nil, false)
		for i = 1, #respawn_beacons do
			local beacon = respawn_beacons[i]
			if beacon and beacon.position and beacon.distance then
				updated = add_beacon_to_cache(
					entry.respawn_beacons,
					beacon.distance,
					beacon.position,
					nil,
					beacon.priority
				) or updated
			end
		end
		local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
		local priority_unit = get_priority_respawn_beacon_unit(respawn_system)
		if priority_unit then
			local priority_distance = get_priority_respawn_beacon_distance(respawn_system, priority_unit)
			local priority_position = nil
			if Unit and Unit.world_position then
				local ok, value = pcall(Unit.world_position, priority_unit, 1)
				if ok and value then
					priority_position = value
				end
			end
			if not priority_position and priority_distance and MainPathQueries.position_from_distance then
				priority_position = MainPathQueries.position_from_distance(priority_distance)
			end
			if priority_distance and is_finite_number(priority_distance) then
				updated = add_beacon_to_cache(
					entry.respawn_beacons,
					priority_distance,
					priority_position,
					nil,
					true
				) or updated
			end
		end
	elseif updated then
		cache_debug("Main path not registered yet; deferring path capture")
	else
		cache_debug_skip("main path not registered", t, 2)
	end

	if updated then
		entry.updated_at = os.time()
		cache_state.runtime_dirty = true
		write_cache_file()
		cache_debug(string.format("Updated cache for %s", tostring(mission_name)))
		cache_state.record_count = cache_state.record_count + 1
	else
		cache_debug_skip("no new data", t, update_interval)
	end
end

local function clear_markers()
	if not Managers.event then
		pending_marker_cleanup = true
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
		pending_marker_cleanup = true
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
		pending_marker_cleanup = true
		return
	end

	for key, entry in pairs(debug_label_state.markers) do
		if entry.id then
			Managers.event:trigger("remove_world_marker", entry.id)
		end
		debug_label_state.markers[key] = nil
	end
	debug_label_state.marker_count = 0
end

local function begin_debug_label_markers()
	debug_label_state.generation = debug_label_state.generation + 1
end

local function finalize_debug_label_markers()
	if not Managers.event then
		debug_label_state.markers = {}
		debug_label_state.marker_count = 0
		return
	end
	for key, entry in pairs(debug_label_state.markers) do
		if entry.generation ~= debug_label_state.generation then
			if entry.id then
				Managers.event:trigger("remove_world_marker", entry.id)
			end
			debug_label_state.markers[key] = nil
			debug_label_state.marker_count = math.max(0, debug_label_state.marker_count - 1)
		end
	end
end

local function prune_debug_label_markers(player_position)
	if not Managers.event or not player_position then
		return
	end
	local marker_range = tonumber(mod:get("debug_label_draw_distance")) or 0
	if marker_range <= 0 then
		return
	end
	local max_range_sq = marker_range * marker_range
	for key, entry in pairs(debug_label_state.markers) do
		local pos = entry and entry.position
		if pos then
			local dx = pos.x - player_position.x
			local dy = pos.y - player_position.y
			local dz = pos.z - player_position.z
			local dist_sq = dx * dx + dy * dy + dz * dz
			entry.distance_sq = dist_sq
			if dist_sq > max_range_sq then
				if entry.id then
					Managers.event:trigger("remove_world_marker", entry.id)
				end
				debug_label_state.markers[key] = nil
				debug_label_state.marker_count = math.max(0, debug_label_state.marker_count - 1)
			end
		end
	end
end

local function build_debug_label_key(text, position)
	if not position then
		return tostring(text or "")
	end
	local base = tostring(text or "")
	base = base:gsub("%s%[[^%]]+%]$", "")
	base = base:gsub("%b[]", "")
	base = base:gsub("%b()", "")
	base = base:gsub("%d+%.?%d*%s*[ms]", "")
	base = base:gsub("%d+%.?%d*", "")
	base = base:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if base == "" then
		base = "label"
	end
	local step = 0.1
	local x = math.floor((position.x or 0) / step + 0.5) * step
	local y = math.floor((position.y or 0) / step + 0.5) * step
	local z = math.floor((position.z or 0) / step + 0.5) * step
	return string.format("%s@%.1f,%.1f,%.1f", base, x, y, z)
end

local function ensure_debug_label_marker(key, text, position, size, color, check_line_of_sight, use_distance_scale)
	if not Managers.event or not RitualZonesDebugLabelMarker then
		return false
	end
	local player_position = nil
	if Managers.player and Managers.player.local_player then
		local player = Managers.player:local_player(1)
		if player then
			local unit = player.player_unit
			if unit then
				player_position = get_unit_position(unit)
			end
		end
	end
	local marker_range = tonumber(mod:get("debug_label_draw_distance")) or 0
	local max_range_sq = nil
	if marker_range > 0 then
		max_range_sq = marker_range * marker_range
	end
	local distance_sq = nil
	if player_position then
		local dx = position.x - player_position.x
		local dy = position.y - player_position.y
		local dz = position.z - player_position.z
		distance_sq = dx * dx + dy * dy + dz * dz
	end
	if max_range_sq and distance_sq and distance_sq > max_range_sq then
		local existing = debug_label_state.markers[key]
		if existing and existing.id then
			Managers.event:trigger("remove_world_marker", existing.id)
			debug_label_state.markers[key] = nil
			debug_label_state.marker_count = math.max(0, debug_label_state.marker_count - 1)
		end
		return false
	end
	if not debug_label_state.markers[key] and debug_label_state.marker_count >= debug_label_limits.max_markers then
		local is_priority = key == "Max Progress"
			or key:find("^Progress")
			or key:find("^Respawn Progress Warning")
			or key:find("^Respawn Warning Debug")
		local function pick_farthest(allow_priority)
			local far_key = nil
			local far_dist = -1
			for existing_key, existing in pairs(debug_label_state.markers) do
				if existing_key ~= key and existing then
					local keep = existing_key:find("^Progress")
						or existing_key:find("^Respawn Progress Warning")
						or existing_key:find("^Respawn Warning Debug")
						or existing_key:find("^Respawn Progress")
						or existing_key:find("^Respawn Beacon")
						or existing_key:find("^Ritual")
						or existing_key:find("^Twins")
						or existing_key:find("^Rescue Move Trigger")
						or existing_key:find("^Priority Move Trigger")
						or existing_key:find("^Pacing Spawn: monsters")
						or existing_key:find("^Pacing Spawn: witches")
						or existing_key:find("^Pacing Spawn: captains")
					if allow_priority or not keep then
						local existing_dist = existing.distance_sq
						if existing_dist == nil then
							existing_dist = math.huge
						end
						if existing_dist > far_dist then
							far_dist = existing_dist
							far_key = existing_key
						end
					end
				end
			end
			return far_key
		end
		local far_key = pick_farthest(false)
		if not far_key then
			far_key = pick_farthest(true)
		end
		if far_key then
			local existing = debug_label_state.markers[far_key]
			if existing and existing.id then
				Managers.event:trigger("remove_world_marker", existing.id)
			end
			debug_label_state.markers[far_key] = nil
			debug_label_state.marker_count = math.max(0, debug_label_state.marker_count - 1)
		end
		if not debug_label_state.markers[key] and debug_label_state.marker_count >= debug_label_limits.max_markers then
			return false
		end
	end
	local use_los = check_line_of_sight and true or false
	if RitualZonesDebugLabelMarker then
		RitualZonesDebugLabelMarker.check_line_of_sight = use_los
	end
	local show_background = mod:get("debug_text_background") and true or false
	local scale_min = use_distance_scale and debug_label_scale_min or 1
	local scale_max = use_distance_scale and debug_label_scale_max or 1
	local scale_range = use_distance_scale and debug_label_scale_range or 1
	local entry = debug_label_state.markers[key]
	if entry then
		entry.generation = debug_label_state.generation
		entry.data.text = text
		entry.data.color = color
		entry.data.text_size = size
		entry.data.show_background = show_background
		entry.data.check_line_of_sight = use_los
		entry.distance_sq = distance_sq
		entry.data.distance_scale_min = scale_min
		entry.data.distance_scale_max = scale_max
		entry.data.distance_scale_range = scale_range
		local pos = entry.position
		local dx = position.x - (pos and pos.x or 0)
		local dy = position.y - (pos and pos.y or 0)
		local dz = position.z - (pos and pos.z or 0)
		if entry.id and (not pos or (dx * dx + dy * dy + dz * dz) > debug_label_limits.move_threshold_sq) then
			local old_id = entry.id
			entry.id = nil
			entry.position = { x = position.x, y = position.y, z = position.z }
			Managers.event:trigger(
				"add_world_marker_position",
				RitualZonesDebugLabelMarker.name,
				position,
				function(marker_id)
					entry.id = marker_id
					if old_id then
						Managers.event:trigger("remove_world_marker", old_id)
					end
				end,
				entry.data
			)
		else
			entry.position = { x = position.x, y = position.y, z = position.z }
		end
		return true
	end

	local data = {
		text = text,
		color = color,
		text_size = size,
		show_background = show_background,
		check_line_of_sight = use_los,
		distance_scale_min = scale_min,
		distance_scale_max = scale_max,
		distance_scale_range = scale_range,
	}
	local new_entry = {
		id = nil,
		data = data,
		generation = debug_label_state.generation,
		distance_sq = distance_sq,
		position = { x = position.x, y = position.y, z = position.z },
	}
	debug_label_state.markers[key] = new_entry
	debug_label_state.marker_count = debug_label_state.marker_count + 1

	Managers.event:trigger("add_world_marker_position", RitualZonesDebugLabelMarker.name, position, function(marker_id)
		new_entry.id = marker_id
	end, data)
	return true
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
		if unit_is_alive(unit) and not ritual_ended_units[unit] then
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
			if not unit_is_alive(unit) then
				ritual_ended_units[unit] = nil
			end
		end
	end
end

local function ensure_timer_marker(unit, text, color, text_size, height, show_background)
	local entry = timer_markers[unit]
	if entry and entry.id and entry.generation == marker_generation then
		entry.data.text = text
		entry.data.color = color
		entry.data.text_size = text_size
		entry.data.height = height
		entry.data.show_background = show_background
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
		show_background = show_background,
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
	local show_background = mod:get("ritual_text_background_enabled") or false
	local active = {}

	for i = 1, #ritual_units do
		local unit = ritual_units[i]
		if unit_is_alive(unit) and not ritual_ended_units[unit] then
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
				ensure_timer_marker(unit, text, color, text_size, 1.2 + height, show_background)
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
			ritual_ended_units[unit] = nil
		elseif not active[unit] then
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
	if not debug_state.text_manager then
		debug_state.text_world = nil
		return
	end

	if debug_state.text_manager.destroy then
		pcall(debug_state.text_manager.destroy, debug_state.text_manager)
	end

	debug_state.text_manager = nil
	debug_state.text_world = nil
end

local function ensure_debug_text_manager(world)
	resolve_debug_modules()
	if not world or not World or not Gui or not Matrix4x4 or not Vector3 or not Quaternion or not Color then
		return nil
	end

	if debug_state.text_manager and debug_state.text_world == world then
		return debug_state.text_manager
	end

	destroy_debug_text_manager()
	local ok, world_gui = pcall(World.create_world_gui, world, Matrix4x4.identity(), 1, 1)
	if not ok or not world_gui then
		if not debug_state.debug_text_log_gui_failed then
			debug_state.debug_text_log_gui_failed = true
			mod:echo("[RitualZones] Debug text: World.create_world_gui failed")
		end
		return nil
	end

	local manager = {
		_world = world,
		_world_gui = world_gui,
		_world_texts = {},
		_world_text_size = 0.6,
	}

	function manager:output_world_text(text, text_size, position, time, category, color, viewport_name)
		if self._disabled then
			return
		end
		local ok = pcall(function()
			if not text or not position or not self._world_gui then
				return
			end

			local gui = self._world_gui
			local material = "content/ui/fonts/arial"
			local font = "content/ui/fonts/arial"
			text_size = tonumber(text_size) or self._world_text_size
			if text_size < 0.1 then
				text_size = 0.1
			end

			local tm = nil
			if viewport_name and Managers and Managers.state and Managers.state.camera then
				local ok_rot, camera_rotation =
					pcall(Managers.state.camera.camera_rotation, Managers.state.camera, viewport_name)
				if ok_rot and camera_rotation then
					tm = Matrix4x4.from_quaternion_position(camera_rotation, position)
				end
			end
			if not tm then
				tm = Matrix4x4.from_quaternion_position(Quaternion.identity(), position)
			end

			local text_value = tostring(text)
			local text_width = nil
			local text_height = nil
			local ok_extents, text_extent_min, text_extent_max =
				pcall(Gui.text_extents, gui, text_value, font, text_size)
			if ok_extents and text_extent_min and text_extent_max then
				text_width = text_extent_max[1] - text_extent_min[1]
				text_height = text_extent_max[2] - text_extent_min[2]
			end
			if not text_width or not text_height or text_width <= 0 or text_height <= 0 then
				local length = utf8 and utf8.len(text_value) or #text_value
				text_width = (text_size * 0.6) * length
				text_height = text_size
			end
			local text_offset = Vector3(-text_width / 2, -text_height / 2, 0)
			category = category or "none"
			color = color or Vector3(255, 255, 255)

			local text_func = Gui and Gui.text_3d
			if type(text_func) ~= "function" then
				if not debug_state.debug_text_log_text_failed then
					debug_state.debug_text_log_text_failed = true
					mod:echo("[RitualZones] Debug text: Gui.text_3d missing")
				end
				return
			end

			local color_value = nil
			if type(Color) == "function" then
				color_value = Color(255, color.x, color.y, color.z)
			elseif type(Color) == "table" then
				local mt = getmetatable(Color)
				if mt and type(mt.__call) == "function" then
					color_value = Color(255, color.x, color.y, color.z)
				elseif type(Color.new) == "function" then
					color_value = Color.new(255, color.x, color.y, color.z)
				elseif type(Color.from_rgb) == "function" then
					color_value = Color.from_rgb(color.x, color.y, color.z)
				end
			end
			if not color_value and type(Color) == "function" then
				color_value = Color(255, 255, 255, 255)
			end

			local ok_text, id = pcall(text_func, gui, text_value, material, text_size, font, tm, text_offset, 0, color_value)
			if not ok_text then
				ok_text, id = pcall(text_func, gui, text_value, font, text_size, material, tm, text_offset, 0, color_value)
			end
			if not ok_text or not id then
				self._disabled = true
				if not debug_state.debug_text_log_text_failed then
					debug_state.debug_text_log_text_failed = true
					mod:echo("[RitualZones] Debug text: Gui.text_3d failed; disabling world labels for this session")
				end
				return
			end
			local entry = { id = id }
			self._world_texts[category] = self._world_texts[category] or {}
			self._world_texts[category][#self._world_texts[category] + 1] = entry
		end)

		if not ok and not debug_state.debug_text_log_text_failed then
			debug_state.debug_text_log_text_failed = true
			mod:echo("[RitualZones] Debug text: output_world_text failed")
		end
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

	debug_state.text_manager = manager
	debug_state.text_world = world

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
	return Vector3(offset[1] * s, offset[2] * s, offset[3] + debug_state.text_z_offset)
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

local function output_debug_text(debug_text, text, position, size, color_rgb, key_override)
	if not position or not Vector3 then
		return
	end
	local labels_through_walls = mod:get("debug_labels_through_walls") == true
	local wants_background = mod:get("debug_text_background") == true
	local force_markers = debug_state.force_label_markers and true or false
	if labels_through_walls or wants_background or force_markers then
		if debug_state.label_refresh_enabled then
			local key = key_override or build_debug_label_key(text, position)
			local ok = ensure_debug_label_marker(
				key,
				text,
				position,
				size,
				color_rgb,
				not labels_through_walls,
				labels_through_walls
			)
			if ok then
				return
			end
		elseif labels_through_walls then
			return
		end
		if force_markers or wants_background then
			return
		end
	end
	if not debug_text then
		if not debug_state.debug_text_log_missing then
			debug_state.debug_text_log_missing = true
			mod:echo("[RitualZones] Debug text: manager missing, labels skipped")
		end
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
local draw_thick_line = nil
local format_debug_label = nil
local resolve_color_setting = nil

resolve_color_setting = function(setting_id, fallback)
	local fallback_color = fallback or { 255, 255, 255 }
	local color_name = mod:get(setting_id)
	if type(color_name) ~= "string" or not Color or not Color[color_name] then
		return fallback_color
	end
	local ok, values = pcall(Color[color_name], 255, true)
	if not ok or not values then
		return fallback_color
	end
	return { values[2], values[3], values[4] }
end

local function get_debug_settings()
	resolve_debug_modules()
	local settings = {}
	settings.gate_enabled = mod:get("gate_enabled")
	if settings.gate_enabled == nil then
		settings.gate_enabled = true
	end
	settings.path_enabled = mod:get("path_enabled")
	settings.debug_text_mode = debug_text_mode()
	local forced_labels = (mod:get("debug_labels_through_walls") or mod:get("debug_text_background")) and true or false
	settings.debug_text_enabled = debug_text_enabled_mode(settings.debug_text_mode) or forced_labels
	settings.debug_text_show_labels = debug_text_show_labels(settings.debug_text_mode) or forced_labels
	settings.debug_text_show_distances = debug_text_show_distances(settings.debug_text_mode) or forced_labels
	settings.debug_distance_enabled = settings.debug_text_show_distances
	settings.debug_respawn_warning = mod:get("debug_respawn_warning") and true or false
	settings.debug_text_size = mod:get("debug_text_size") or 0.2
	settings.debug_text_height = mod:get("debug_text_height") or 0.4
	settings.debug_text_z_offset = mod:get("debug_text_z_offset") or 0
	settings.debug_text_z_offset = math.floor(settings.debug_text_z_offset * 2 + 0.5) / 2
	debug_state.text_z_offset = settings.debug_text_z_offset
	settings.debug_label_scale_min = mod:get("debug_label_distance_scale_min")
	settings.debug_label_scale_max = mod:get("debug_label_distance_scale_max")
	settings.debug_label_scale_range = mod:get("debug_label_distance_scale_range")
	debug_label_scale_min = tonumber(settings.debug_label_scale_min) or debug_label_scale_min
	debug_label_scale_max = tonumber(settings.debug_label_scale_max) or debug_label_scale_max
	debug_label_scale_range = tonumber(settings.debug_label_scale_range) or debug_label_scale_range
	local marker_cap = tonumber(mod:get("debug_label_marker_cap"))
	local move_threshold = tonumber(mod:get("debug_label_move_threshold"))
	if marker_cap and marker_cap >= 50 then
		debug_label_limits.max_markers = math.min(debug_label_limits.hard_cap, math.floor(marker_cap + 0.5))
	end
	if move_threshold and move_threshold > 0 then
		debug_label_limits.move_threshold_sq = move_threshold * move_threshold
	end
	if debug_label_scale_min < 0.05 then
		debug_label_scale_min = 0.05
	end
	if debug_label_scale_max < 0.1 then
		debug_label_scale_max = 0.1
	end
	if debug_label_scale_max < debug_label_scale_min then
		debug_label_scale_max = debug_label_scale_min
	end
	if debug_label_scale_range < 10 then
		debug_label_scale_range = 10
	end
	settings.debug_draw_distance = mod:get("debug_draw_distance") or 0
	settings.debug_text_offset_scale = math.max(0.15, settings.debug_text_size * 2)
	settings.progress_sphere_color = resolve_color_setting("color_sphere", CONST.PROGRESS_COLOR)
	settings.progress_line_color = resolve_color_setting("color_line", settings.progress_sphere_color)
	settings.passed_color = resolve_color_setting("color_passed", CONST.MARKER_COLOR)
	settings.path_color = resolve_color_setting("color_path", CONST.PATH_COLOR)
	settings.beacon_color = resolve_color_setting("color_beacon", CONST.RESPAWN_BEACON_COLOR)
	settings.path_line_thickness = mod:get("path_line_thickness")
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
	settings.progress_spheres_mode = mod:get("progress_spheres_mode")
	settings.progress_spheres_slot = mod:get("progress_spheres_slot")
	settings.progress_line_mode = mod:get("progress_line_mode")
	settings.progress_gate_mode = mod:get("progress_gate_mode")
	settings.progress_gate_leader_enabled = mod:get("progress_gate_leader_enabled")
	settings.progress_gate_max_enabled = mod:get("progress_gate_max_enabled")
	settings.progress_gate_width = mod:get("progress_gate_width")
	settings.progress_gate_height = mod:get("progress_gate_height")
	settings.progress_gate_slices = mod:get("progress_gate_slices")
	settings.progress_line_thickness = mod:get("progress_line_thickness")
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
	if settings.progress_spheres_mode == nil then
		settings.progress_spheres_mode = "all"
	end
	if settings.progress_spheres_mode ~= "all"
		and settings.progress_spheres_mode ~= "self"
		and settings.progress_spheres_mode ~= "leader"
		and settings.progress_spheres_mode ~= "slot" then
		settings.progress_spheres_mode = "all"
	end
	if settings.progress_spheres_slot == nil then
		settings.progress_spheres_slot = 1
	end
	settings.progress_spheres_slot = math.floor(settings.progress_spheres_slot + 0.5)
	if settings.progress_spheres_slot < 1 then
		settings.progress_spheres_slot = 1
	elseif settings.progress_spheres_slot > 4 then
		settings.progress_spheres_slot = 4
	end
	if settings.progress_line_mode == nil then
		local legacy = mod:get("progress_line_enabled")
		settings.progress_line_mode = legacy and "self" or "off"
	end
	if settings.progress_line_mode ~= "off"
		and settings.progress_line_mode ~= "self"
		and settings.progress_line_mode ~= "slot"
		and settings.progress_line_mode ~= "all" then
		settings.progress_line_mode = "off"
	end
	if settings.progress_gate_mode == nil then
		settings.progress_gate_mode = "off"
	end
	if settings.progress_gate_mode ~= "off"
		and settings.progress_gate_mode ~= "self"
		and settings.progress_gate_mode ~= "slot"
		and settings.progress_gate_mode ~= "all" then
		settings.progress_gate_mode = "off"
	end
	if settings.progress_gate_leader_enabled == nil then
		settings.progress_gate_leader_enabled = false
	end
	if settings.progress_gate_max_enabled == nil then
		settings.progress_gate_max_enabled = false
	end
	if settings.progress_gate_width == nil then
		settings.progress_gate_width = 6
	end
	if settings.progress_gate_height == nil then
		settings.progress_gate_height = 6
	end
	if settings.progress_gate_slices == nil then
		settings.progress_gate_slices = 4
	end
	settings.progress_gate_width = math.max(0.5, tonumber(settings.progress_gate_width) or 6)
	settings.progress_gate_height = math.max(0.5, tonumber(settings.progress_gate_height) or 6)
	settings.progress_gate_slices = math.max(1, math.floor(tonumber(settings.progress_gate_slices) or 1))
	if settings.path_line_thickness == nil then
		settings.path_line_thickness = 0
	end
	settings.path_line_thickness = math.max(0, tonumber(settings.path_line_thickness) or 0)
	if settings.progress_line_thickness == nil then
		settings.progress_line_thickness = 0
	end
	settings.progress_line_thickness = math.max(0, tonumber(settings.progress_line_thickness) or 0)
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
		or settings.progress_line_mode ~= "off"
		or settings.progress_gate_mode ~= "off"
		or settings.progress_gate_leader_enabled
		or settings.progress_gate_max_enabled
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
		remove_distance = progress_reference_distance - CONST.TRIGGER_PAST_MARGIN
	elseif Managers.state.main_path and Managers.state.main_path.ahead_unit then
		local _, ahead_distance = Managers.state.main_path:ahead_unit(1)
		if ahead_distance then
			remove_distance = ahead_distance - CONST.TRIGGER_PAST_MARGIN
		end
	end
	if path_total and remove_distance then
		remove_distance = math.max(0, math.min(remove_distance, path_total))
	end

	state.player_distance = player_distance
	state.local_distance = local_distance
	state.progress_entries = progress_entries
	state.leader_distance = leader_distance
	state.leader_player = leader_player
	state.progress_reference_distance = progress_reference_distance
	state.remove_distance = remove_distance
	state.max_progress_distance = max_progress_distance
	local waiting_to_spawn, respawn_min_time = has_players_waiting_to_spawn()
	state.respawn_waiting = waiting_to_spawn
	state.respawn_min_time = respawn_min_time
	state.respawn_state = {
		rewind_lost = respawn_state and respawn_state.rewind_lost or false,
	}
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
	local path_rgb = settings.path_color or CONST.PATH_COLOR
	local path_color = Color(120, path_rgb[1], path_rgb[2], path_rgb[3])
	draw_main_path(
		state.line_object,
		path_color,
		settings.path_height,
		state.player_position,
		settings.debug_draw_distance,
		settings.path_line_thickness
	)
end

local function flush_pending_marker_cleanup()
	if not pending_marker_cleanup then
		return
	end
	if not Managers.event then
		return
	end
	pending_marker_cleanup = false
	clear_markers()
	clear_timer_markers()
	clear_debug_label_markers()
end

function draw_debug_progress(settings, state)
	local line_mode = settings.progress_line_mode or "off"
	local gate_mode = settings.progress_gate_mode or "off"
	local draw_lines = line_mode ~= "off"
	local draw_gates = gate_mode ~= "off"
		or settings.progress_gate_leader_enabled
		or settings.progress_gate_max_enabled
	local sphere_color = settings.progress_sphere_color or CONST.PROGRESS_COLOR
	local line_color = settings.progress_line_color or sphere_color
	if not settings.progress_point_enabled and not draw_lines and not draw_gates then
		return
	end
	local progress_entries = state.progress_entries or {}
	local progress_group_counts = {}
	local progress_group_indices = {}
	local mode = settings.progress_spheres_mode or "all"
	local focus_slot = settings.progress_spheres_slot or 1
	local leader_player = state.leader_player
	local local_line_position = nil
	local local_line_radius = nil
	local draw_spheres = settings.progress_point_enabled
	local gate_width = settings.progress_gate_width or 6
	local gate_height = settings.progress_gate_height or 6
	local gate_slices = settings.progress_gate_slices or 1
	local line_thickness = settings.progress_line_thickness or 0
	local warn_active = state.respawn_waiting and not state.hogtied_present and not state.respawn_state.rewind_lost
	local safe_progress_distance = state.safe_respawn_distance
	local warn_safe_distance = state.respawn_rewind_threshold_distance or safe_progress_distance
	local min_respawn_time = state.respawn_min_time

	for i = 1, #progress_entries do
		local entry = progress_entries[i]
		local distance = entry.distance
		local show_entry = true
		if mode == "self" then
			show_entry = entry.is_local == true
		elseif mode == "leader" then
			show_entry = leader_player and entry.player == leader_player
		elseif mode == "slot" then
			local slot = entry.slot
			if slot == nil then
				local player = entry.player
				slot = player and player.slot and player:slot()
				entry.slot = slot
			end
			show_entry = slot == focus_slot
		end
		entry._show = show_entry
		local gate_show = false
		if gate_mode == "all" then
			gate_show = true
		elseif gate_mode == "self" then
			gate_show = entry.is_local == true
		elseif gate_mode == "slot" then
			local slot = entry.slot
			if slot == nil then
				local player = entry.player
				slot = player and player.slot and player:slot()
				entry.slot = slot
			end
			gate_show = slot == focus_slot
		end
		if settings.progress_gate_leader_enabled and leader_player and entry.player == leader_player then
			gate_show = true
		end
		entry._gate = gate_show
		local line_show = false
		if line_mode == "all" then
			line_show = true
		elseif line_mode == "self" then
			line_show = entry.is_local == true
		elseif line_mode == "slot" then
			local slot = entry.slot
			if slot == nil then
				local player = entry.player
				slot = player and player.slot and player:slot()
				entry.slot = slot
			end
			line_show = slot == focus_slot
		end
		entry._line = line_show
		if show_entry and distance and is_finite_number(distance) then
			local bucket = math.floor((distance / CONST.PROGRESS_STACK_STEP) + 0.5) * CONST.PROGRESS_STACK_STEP
			entry.stack_key = bucket
			progress_group_counts[bucket] = (progress_group_counts[bucket] or 0) + 1
		end
	end

	for i = 1, #progress_entries do
		local entry = progress_entries[i]
		local distance = entry.distance
		local is_leader = leader_player and entry.player == leader_player
		local warn_is_leader = is_leader and not entry.is_local
		local warn_entry = warn_active and warn_safe_distance and (entry.is_local or warn_is_leader)
		local debug_warn_entry = settings.debug_respawn_warning and (entry.is_local or warn_is_leader)
		local skip_entry = not entry._show and not entry._line and not entry._gate and not warn_entry and not debug_warn_entry
		if not skip_entry then
			if state.path_total then
				distance = math.max(0, math.min(distance, state.path_total))
			end
			local progress_position = MainPathQueries.position_from_distance(distance)
			if progress_position and within_draw_distance(progress_position, settings, state) then
			local color_values = is_leader and CONST.RING_COLORS.purple or sphere_color
			local alpha_value = entry.alive and 220 or 140
			local color = Color(alpha_value, color_values[1], color_values[2], color_values[3])
			local stack_offset = 0
			if entry._show then
				local stack_key = entry.stack_key or distance or 0
				local stack_index = (progress_group_indices[stack_key] or 0) + 1
				progress_group_indices[stack_key] = stack_index
				stack_offset = (stack_index - 1) * CONST.PROGRESS_STACK_HEIGHT * settings.sphere_radius_scale
			end
			local position = progress_position
				+ Vector3(0, 0, settings.path_height + settings.progress_height + stack_offset)
			entry._position = position
			entry._radius = 0.4 * settings.sphere_radius_scale
			if entry.is_local then
				local_line_position = position
				local_line_radius = entry._radius
			end
			if draw_spheres and entry._show then
				draw_sphere(state.line_object, position, 0.4 * settings.sphere_radius_scale, 20, color)
				if settings.debug_text_enabled then
					local label = nil
					local label_color = color_values
					if is_leader then
						label = "Progress (Leader)"
						label_color = CONST.RING_COLORS.purple
					elseif entry.is_local then
						label = "Progress (You)"
						label_color = sphere_color
					else
						local name = get_player_name(entry.player)
						if name then
							label = string.format("Progress (%s)", tostring(name))
							label_color = sphere_color
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
							local key_override = label
							if is_leader then
								key_override = "Progress (Leader)"
							elseif entry.is_local then
								key_override = "Progress (You)"
							elseif entry.slot then
								key_override = string.format("Progress (Slot %s)", tostring(entry.slot))
							end
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
								label_color,
								key_override
							)
						end
					end
				end
			end
			if settings.debug_respawn_warning and distance and is_finite_number(distance) then
				local safe_value = warn_safe_distance and string.format("%.1f", warn_safe_distance) or "nil"
				local return_value = warn_safe_distance and string.format("%.1f", distance - warn_safe_distance) or "nil"
				local warn_label = string.format(
					"Warn=%s Safe=%s Dist=%.1f Ret=%s Wait=%s Hog=%s Lost=%s",
					tostring(warn_active),
					safe_value,
					distance,
					return_value,
					tostring(state.respawn_waiting),
					tostring(state.hogtied_present),
					tostring(state.respawn_state.rewind_lost)
				)
				local debug_key = entry.is_local and "Respawn Warning Debug (You)"
					or "Respawn Warning Debug (Leader)"
				if entry.is_local or is_leader then
					local debug_position = get_debug_text_position(
						position,
						debug_key,
						settings.debug_text_height,
						settings.debug_text_offset_scale
					)
					output_debug_text(
						state.debug_text,
						warn_label,
						debug_position,
						settings.debug_text_size * 0.9,
						CONST.RING_COLORS.orange,
						debug_key
					)
				end
			end
			if warn_entry and settings.debug_text_enabled and distance and warn_safe_distance then
				local warn_return_distance = distance - warn_safe_distance
				if warn_return_distance > 0 then
					local warn_label = "RETURN TO SAFE"
					if not settings.debug_text_show_distances then
						warn_label = string.format("RETURN TO SAFE %.0fm", math.max(0, warn_return_distance))
					end
					if min_respawn_time and is_finite_number(min_respawn_time) then
						warn_label = string.format("%s (%.0fs)", warn_label, math.max(0, min_respawn_time))
					end
					local warn_text = format_debug_label(
						warn_label,
						settings.debug_text_show_distances and warn_return_distance or nil,
						settings.debug_text_show_distances,
						settings.debug_text_show_labels
					)
					if warn_text then
						local warn_key = entry.is_local and "Respawn Progress Warning (You)"
							or "Respawn Progress Warning (Leader)"
						local text_position = get_debug_text_position(
							position,
							warn_key,
							settings.debug_text_height,
							settings.debug_text_offset_scale
						)
						output_debug_text(
							state.debug_text,
							warn_text,
							text_position,
							settings.debug_text_size * 1.3,
							CONST.RING_COLORS.red,
							warn_key
						)
					end
				end
			end
			if entry._gate and draw_gates then
				local direction = main_path_direction(distance)
				if direction then
					draw_gate_plane(
						state.line_object,
						position,
						direction,
						gate_width,
						gate_height,
						gate_slices,
						Color(200, color_values[1], color_values[2], color_values[3])
					)
				end
			end
			end
		end
	end

	if draw_lines then
		for i = 1, #progress_entries do
			local entry = progress_entries[i]
			if entry._line and entry._position and within_draw_distance(entry._position, settings, state) then
				local radius = entry._radius or (0.4 * settings.sphere_radius_scale)
				local offset = Vector3(0, 0, settings.path_height + radius)
				local from_position = entry.is_local and state.player_position or get_unit_position(entry.unit)
				if from_position then
					local from = from_position + offset
					local to = entry._position
					local line_color_rgb = entry.is_leader and CONST.RING_COLORS.purple or line_color
					local line_color = Color(200, line_color_rgb[1], line_color_rgb[2], line_color_rgb[3])
					draw_thick_line(state.line_object, line_color, from, to, line_thickness)
				end
			end
		end
	end

	if (draw_spheres or settings.progress_gate_max_enabled) and state.max_progress_distance then
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
			if draw_spheres then
				draw_sphere(state.line_object, position, 0.5 * settings.sphere_radius_scale, 20, max_color)
			end
			if settings.progress_gate_max_enabled then
				local direction = main_path_direction(state.max_progress_distance)
				if direction then
					draw_gate_plane(
						state.line_object,
						position,
						direction,
						gate_width,
						gate_height,
						gate_slices,
						Color(200, CONST.PROGRESS_MAX_COLOR[1], CONST.PROGRESS_MAX_COLOR[2], CONST.PROGRESS_MAX_COLOR[3])
					)
				end
			end
			if draw_spheres and settings.debug_text_enabled then
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
							CONST.PROGRESS_MAX_COLOR,
							"Max Progress"
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
		local skip_trigger = false
		if trigger.label == "Twins Spawn Trigger" then
			if twins_spawn_mode == "off" then
				skip_trigger = true
			elseif twins_spawn_mode == "until_spawn" then
				local spawned = twins_spawned
				if not spawned and state.progress_reference_distance and distance then
					spawned = distance <= state.progress_reference_distance
				end
				if spawned then
					skip_trigger = true
				end
			end
		elseif trigger.label == "Twins Ambush Trigger" then
			if twins_ambush_mode == "off" then
				skip_trigger = true
			elseif twins_ambush_mode == "until_spawn" then
				local spawned = twins_spawned
				if not spawned and state.progress_reference_distance and distance then
					spawned = distance <= state.progress_reference_distance
				end
				if spawned then
					skip_trigger = true
				end
			end
		end
		if not skip_trigger then
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
				local color_rgb = passed and settings.passed_color or CONST.BOSS_TRIGGER_COLOR
				local boss_color = Color(220, color_rgb[1], color_rgb[2], color_rgb[3])
				local radius = CONST.BOSS_TRIGGER_RADIUS * settings.sphere_radius_scale
				local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
				if within_draw_distance(sphere_position, settings, state) then
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
			end
		end
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
			local color_rgb = passed and settings.passed_color or CONST.PACING_TRIGGER_COLOR
			local pace_color = Color(200, color_rgb[1], color_rgb[2], color_rgb[3])
			local radius = CONST.TRIGGER_POINT_RADIUS * settings.sphere_radius_scale
			local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
			if within_draw_distance(sphere_position, settings, state) then
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
		end
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
			local color_rgb = passed and settings.passed_color or CONST.AMBUSH_TRIGGER_COLOR
			local radius = CONST.TRIGGER_POINT_RADIUS * settings.sphere_radius_scale
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
		end
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
local color_rgb = passed and settings.passed_color or CONST.BACKTRACK_TRIGGER_COLOR
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

	local respawn_system = Managers.state.extension and Managers.state.extension:system("respawn_beacon_system")
	local ahead_distance = get_respawn_beacon_ahead_distance(respawn_system)
	local respawn_distances = {}
	local safe_progress_distance = state.safe_respawn_distance
	if settings.respawn_progress_enabled or settings.respawn_beacon_enabled then
		respawn_distances = collect_respawn_progress_distances()
	end

	if settings.respawn_progress_enabled then
		local use_distances = respawn_distances
		if not settings.allow_live_data and state.cache_entry then
			local cached = cached_respawn_distances(state.cache_entry)
			if cached and #cached > 0 then
				use_distances = cached
			end
		elseif #respawn_distances == 0 and state.cache_entry then
			use_distances = cached_respawn_distances(state.cache_entry)
		end
		local cached_progress_points = state.cache_entry and cached_respawn_progress_points(state.cache_entry) or nil
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
		local active_progress_distance = active_distance and (active_distance - ahead_distance)
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
		local computed_safe = safe_progress_distance or active_progress_distance
		local warn_reference_distance = state.progress_reference_distance
			or state.ahead_distance
			or state.player_distance
		local warn_prev_distance = nil
		local warn_next_distance = nil
		if warn_active and warn_reference_distance and use_distances and #use_distances > 0 then
			local sorted_distances = {}
			for i = 1, #use_distances do
				local value = use_distances[i]
				if is_finite_number(value) then
					sorted_distances[#sorted_distances + 1] = value
				end
			end
			table.sort(sorted_distances)
			for i = 1, #sorted_distances do
				local value = sorted_distances[i]
				if value <= warn_reference_distance + CACHE.DISTANCE_TOLERANCE then
					warn_prev_distance = value
				elseif not warn_next_distance then
					warn_next_distance = value
					break
				end
			end
		end
		if warn_active then
			if not respawn_state.safe_locked_active then
				respawn_state.safe_locked_distance = nil
			end
			respawn_state.safe_locked_active = true
			if warn_prev_distance then
				respawn_state.safe_locked_distance = warn_prev_distance
			elseif computed_safe then
				if not respawn_state.safe_locked_distance then
					respawn_state.safe_locked_distance = computed_safe
				elseif computed_safe > respawn_state.safe_locked_distance + CACHE.DISTANCE_TOLERANCE then
					-- Allow the safe point to advance if the active beacon moves forward.
					respawn_state.safe_locked_distance = computed_safe
				end
			end
			if respawn_state.safe_locked_distance then
				safe_progress_distance = respawn_state.safe_locked_distance
				state.safe_respawn_distance = respawn_state.safe_locked_distance
			end
		elseif not respawn_state.rewind_lost then
			respawn_state.safe_locked_active = false
			respawn_state.safe_locked_distance = nil
			if computed_safe then
				safe_progress_distance = computed_safe
				state.safe_respawn_distance = computed_safe
			end
		elseif respawn_state.safe_locked_distance then
			safe_progress_distance = respawn_state.safe_locked_distance
			state.safe_respawn_distance = respawn_state.safe_locked_distance
		end
		for i = 1, #use_distances do
			local distance = use_distances[i]
			if distance and state.path_total then
				distance = math.max(0, math.min(distance, state.path_total))
			end
			local passed = state.progress_reference_distance and distance and distance <= state.progress_reference_distance
			local position = nil
			if cached_progress_points and distance then
				for j = 1, #cached_progress_points do
					local item = cached_progress_points[j]
					local item_distance = item and item.distance
					if item_distance and math.abs(item_distance - distance) <= CACHE.DISTANCE_TOLERANCE then
						position = vector_from_table(item.position or item.pos or item.location)
						if position then
							break
						end
					end
				end
			end
			if not position then
				position = distance and MainPathQueries.position_from_distance(distance)
			end
			if position then
				local base_color_rgb = passed and settings.passed_color or CONST.RESPAWN_PROGRESS_COLOR
				local warn_color_rgb = base_color_rgb
				local warn_status = nil
				if warn_active and distance then
					if warn_prev_distance and math.abs(distance - warn_prev_distance) <= CACHE.DISTANCE_TOLERANCE then
						warn_status = "Return"
						warn_color_rgb = CONST.RING_COLORS.red
					elseif warn_next_distance and math.abs(distance - warn_next_distance) <= CACHE.DISTANCE_TOLERANCE then
						warn_status = "Do Not Cross"
						warn_color_rgb = CONST.RESPAWN_PROGRESS_COLOR
					end
				elseif respawn_state.rewind_lost
					and safe_progress_distance
					and distance
					and math.abs(distance - safe_progress_distance) <= CACHE.DISTANCE_TOLERANCE then
					warn_status = "Lost"
					warn_color_rgb = { 255, 255, 255 }
				end
				local respawn_color = Color(220, warn_color_rgb[1], warn_color_rgb[2], warn_color_rgb[3])
				local radius = CONST.RESPAWN_PROGRESS_RADIUS * settings.sphere_radius_scale
				local sphere_position = position + Vector3(0, 0, settings.path_height + radius)
				if within_draw_distance(sphere_position, settings, state) then
					draw_sphere(state.line_object, sphere_position, radius, 18, respawn_color)
					if settings.debug_text_enabled then
						local base_label = "Respawn Progress"
						local base_text = format_debug_label(
							base_label,
							distance,
							settings.debug_text_show_distances,
							settings.debug_text_show_labels
						)
						if base_text then
							local text_position = get_debug_text_position(
								sphere_position,
								base_label,
								settings.debug_text_height,
								settings.debug_text_offset_scale
							)
							output_debug_text(
								state.debug_text,
								base_text,
								text_position,
								settings.debug_text_size,
								base_color_rgb
							)
						end
						if warn_status then
							local warn_label = warn_status
							if warn_status == "Return" and warn_reference_distance and warn_prev_distance then
								local warn_return_distance = warn_reference_distance - warn_prev_distance
								warn_label = string.format("RETURN %.0fm", math.max(0, warn_return_distance))
							end
							if min_respawn_time and is_finite_number(min_respawn_time) then
								if warn_status ~= "Lost" then
									warn_label = string.format("%s (%.0fs)", warn_label, math.max(0, min_respawn_time))
								end
							end
							local warn_text = format_debug_label(
								warn_label,
								distance,
								settings.debug_text_show_distances,
								settings.debug_text_show_labels
							)
							if warn_text then
								local text_position = get_debug_text_position(
									sphere_position,
									"Respawn Progress Warning",
									settings.debug_text_height,
									settings.debug_text_offset_scale
								)
								output_debug_text(
									state.debug_text,
									warn_text,
									text_position,
									settings.debug_text_size,
									warn_color_rgb
								)
							end
						end
					end
				end
			end
		end
	end

	if settings.respawn_beacon_enabled then
		local fallback_distances = respawn_distances or {}
		if #fallback_distances == 0 and state.cache_entry then
			fallback_distances = cached_respawn_distances(state.cache_entry)
		end
		local beacon_entries = collect_respawn_beacon_entries(state.path_total, fallback_distances, state.cache_entry, true)
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
					local color_rgb = settings.beacon_color
					local base_label = "Respawn Beacon"
					if entry.priority or (entry.unit and entry.unit == priority_unit) then
						color_rgb = settings.passed_color
						base_label = "Respawn Beacon (Priority)"
					elseif entry.unit and entry.unit == active_unit then
						color_rgb = settings.progress_sphere_color
						base_label = "Respawn Beacon (Active)"
						last_active_respawn_beacon_distance = distance
					elseif entry.unit
						and last_active_respawn_beacon
						and entry.unit == last_active_respawn_beacon then
						color_rgb = settings.progress_sphere_color
						base_label = "Respawn Beacon (Last Active)"
					elseif not entry.unit
						and last_active_respawn_beacon_distance
						and distance
						and math.abs(distance - last_active_respawn_beacon_distance) <= 0.2 then
						color_rgb = settings.progress_sphere_color
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
		if state.cache_entry and (priority_distance == nil or priority_distance ~= priority_distance) then
			local cached_distance, cached_position = cached_priority_beacon(state.cache_entry)
			if cached_distance then
				priority_distance = cached_distance
			end
			if not priority_position and cached_position then
				priority_position = cached_position
			end
		end
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
			local color_rgb = settings.progress_line_color
			local color = Color(200, color_rgb[1], color_rgb[2], color_rgb[3])
			pcall(LineObject.add_line, state.line_object, color, from, to)
		end
	end

	if settings.respawn_threshold_enabled then
		local threshold_distance = state.ahead_distance and (state.ahead_distance + ahead_distance)
		if threshold_distance and state.path_total then
			threshold_distance = math.max(0, math.min(threshold_distance, state.path_total))
		end
		if threshold_distance then
			local position = MainPathQueries.position_from_distance(threshold_distance)
			if position then
				local color_rgb = settings.passed_color
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
					beacon_distances[#beacon_distances + 1] = progress_distance + ahead_distance
				end
			end
			table.sort(beacon_distances)
		end
		if beacon_distances and #beacon_distances > 1 then
			table.sort(beacon_distances)
		end

		local active_unit = respawn_system and respawn_system._current_active_respawn_beacon
		local active_distance = nil
		local safe_threshold = nil
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
				local best_diff = math.huge
				for i = 1, #beacon_distances do
					local diff = math.abs(beacon_distances[i] - active_distance)
					if diff < best_diff then
						best_diff = diff
						chosen_index = i
					end
				end
			elseif state.ahead_distance then
				local min_distance = state.ahead_distance + ahead_distance
				for i = 1, #beacon_distances do
					if min_distance < beacon_distances[i] or i == #beacon_distances then
						chosen_index = i
						break
					end
				end
			end

			if chosen_index then
				local active_beacon_distance = beacon_distances[chosen_index]
				if active_beacon_distance then
					safe_threshold = active_beacon_distance - ahead_distance
					if state.path_total then
						safe_threshold = math.max(0, math.min(safe_threshold, state.path_total))
					end
				end
			end
			if chosen_index and chosen_index > 1 then
				rewind_threshold = beacon_distances[chosen_index - 1] - ahead_distance
				if state.path_total then
					rewind_threshold = math.max(0, math.min(rewind_threshold, state.path_total))
				end
			end
		end

		local safe_margin = CONST.RESPAWN_REWIND_SAFE_MARGIN or 0
		local threshold_distance = rewind_threshold or safe_threshold
		if threshold_distance and safe_margin ~= 0 then
			threshold_distance = threshold_distance - safe_margin
			if state.path_total then
				threshold_distance = math.max(0, math.min(threshold_distance, state.path_total))
			end
		end
		state.respawn_rewind_threshold_distance = threshold_distance
		if threshold_distance and not safe_progress_distance then
			safe_progress_distance = threshold_distance
			state.safe_respawn_distance = threshold_distance
		end
		if threshold_distance and not safe_progress_distance then
			safe_progress_distance = threshold_distance
		end

		if threshold_distance then
			local position = MainPathQueries.position_from_distance(threshold_distance)
			if position then
				local waiting_to_spawn = state.respawn_waiting
				local warn_active = waiting_to_spawn and not state.hogtied_present
				local min_respawn_time = state.respawn_min_time
				if warn_active and not respawn_state.waiting_active then
					respawn_state.rewind_crossed = false
					respawn_state.rewind_lost = false
				elseif not warn_active and respawn_state.waiting_active then
					respawn_state.rewind_lost = respawn_state.rewind_crossed and true or false
				end
				respawn_state.waiting_active = warn_active

				local reference_distance = state.ahead_distance or state.progress_reference_distance or state.player_distance
				local crossed = reference_distance and reference_distance > threshold_distance
				local return_distance = nil
				if reference_distance and threshold_distance then
					return_distance = reference_distance - threshold_distance
				end
				local show_threshold = warn_active or respawn_state.rewind_lost
				local status = nil
				local color_rgb = nil

				if warn_active then
					if return_distance and return_distance > 0 then
						respawn_state.rewind_crossed = crossed or respawn_state.rewind_crossed
					else
						status = "DO NOT CROSS"
						color_rgb = CONST.RESPAWN_PROGRESS_COLOR
						respawn_state.rewind_crossed = false
					end
				elseif respawn_state.rewind_lost then
					status = "Lost"
					color_rgb = { 255, 255, 255 }
				end
				state.respawn_state.rewind_lost = respawn_state.rewind_lost

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
							if status == "Lost" then
								base_label = "Respawn Rewind Lost"
							elseif min_respawn_time and is_finite_number(min_respawn_time) then
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

				if warn_active
					and not respawn_state.rewind_lost
					and (state.respawn_rewind_threshold_distance or safe_progress_distance)
					and settings.debug_text_enabled
					and not settings.progress_point_enabled then
					local anchors = {}
					local local_anchor = state.local_distance or state.player_distance
					if local_anchor then
						anchors[#anchors + 1] = {
							distance = local_anchor,
							label_key = "Respawn Progress Warning (You)",
						}
					end
					if state.leader_distance then
						anchors[#anchors + 1] = {
							distance = state.leader_distance,
							label_key = "Respawn Progress Warning (Leader)",
						}
					end
					for i = 1, #anchors do
						local anchor = anchors[i]
						local anchor_distance = anchor.distance
						local anchor_safe = safe_progress_distance or state.respawn_rewind_threshold_distance
						local anchor_return = anchor_distance and anchor_safe and (anchor_distance - anchor_safe) or nil
						if anchor_return and anchor_return > 0 then
							local anchor_position = MainPathQueries.position_from_distance(anchor_distance)
							if anchor_position then
								local warn_label = string.format("RETURN TO SAFE %.0fm", anchor_return)
								if min_respawn_time and is_finite_number(min_respawn_time) then
									warn_label =
										string.format("%s (%.0fs)", warn_label, math.max(0, min_respawn_time))
								end
								local warn_text = format_debug_label(
									warn_label,
									anchor_distance,
									settings.debug_text_show_distances,
									settings.debug_text_show_labels
								)
								if warn_text then
									local warn_color = CONST.RING_COLORS.red
									local warn_position = anchor_position
										+ Vector3(0, 0, settings.path_height + CONST.RESPAWN_PROGRESS_RADIUS)
									local text_position = get_debug_text_position(
										warn_position,
										anchor.label_key,
										settings.debug_text_height,
										settings.debug_text_offset_scale
									)
									output_debug_text(
										state.debug_text,
										warn_text,
										text_position,
										settings.debug_text_size * 1.3,
										warn_color
									)
								end
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
					local color_rgb = trigger.passed and settings.passed_color or CONST.RESPAWN_MOVE_TRIGGER_COLOR
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
		local priority_distance = get_priority_respawn_beacon_distance(respawn_system, priority_unit)
		if (priority_distance == nil or not is_finite_number(priority_distance)) and state.cache_entry then
			local cached_distance = cached_priority_beacon(state.cache_entry)
			if cached_distance then
				priority_distance = cached_distance
			end
		end
		local move_triggers = collect_priority_move_triggers(
			state.path_total,
			settings.priority_move_triggers_mode,
			priority_unit,
			priority_distance
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
					local color_rgb = trigger.passed and settings.passed_color or CONST.RING_COLORS.orange
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
				color = Color(
					state.alpha,
					settings.passed_color[1],
					settings.passed_color[2],
					settings.passed_color[3]
				)
			end
			local base_position = position + Vector3(0, 0, settings.path_height)
			if within_draw_distance(base_position, settings, state) then
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
						local color_rgb = persist_passed and settings.passed_color or { color[2], color[3], color[4] }
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

local function localize_debug_label_text(label)
	if not label then
		return label
	end
	local localized = label
	local loc_key = cache_loc_key_for_label(label)
	if not loc_key then
		loc_key = LABEL_LOCALIZATION_KEYS[label]
	end
	if loc_key then
		localized = localize_label(loc_key, label)
	end
	local function replace_prefix(prefix, key)
		if localized:sub(1, #prefix) == prefix then
			localized = localize_label(key, prefix) .. localized:sub(#prefix + 1)
		end
	end
	replace_prefix("RETURN TO SAFE", "label_return_to_safe")
	replace_prefix("RETURN", "label_return")
	localized = localized:gsub("Do Not Cross", localize_label("label_do_not_cross", "Do Not Cross"))
	localized = localized:gsub("DO NOT CROSS", localize_label("label_do_not_cross", "DO NOT CROSS"))
	localized = localized:gsub("%f[%w]Lost%f[%W]", localize_label("label_lost", "Lost"))
	return localized
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
	label = localize_debug_label_text(label)
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

	if gate_slices > 1 then
		local step = gate_height / gate_slices
		for i = 1, gate_slices - 1 do
			local offset = -half_height + step * i
			local slice_left = center - right * half_width + up * offset
			local slice_right = center + right * half_width + up * offset
			pcall(LineObject.add_line, line_object, color, slice_left, slice_right)
		end
	end
end

draw_thick_line = function(line_object, color, from, to, thickness)
	if thickness == nil or thickness <= 0 then
		pcall(LineObject.add_line, line_object, color, from, to)
		return
	end
	local direction = to - from
	if Vector3.length(direction) < 0.001 then
		pcall(LineObject.add_line, line_object, color, from, to)
		return
	end
	local dir = Vector3.normalize(direction)
	local axis = Vector3.up()
	if math.abs(Vector3.dot(dir, axis)) > 0.9 then
		axis = Vector3(1, 0, 0)
	end
	local right = Vector3.normalize(Vector3.cross(dir, axis))
	local up = Vector3.normalize(Vector3.cross(right, dir))
	local offset = thickness
	pcall(LineObject.add_line, line_object, color, from, to)
	pcall(LineObject.add_line, line_object, color, from + right * offset, to + right * offset)
	pcall(LineObject.add_line, line_object, color, from - right * offset, to - right * offset)
	pcall(LineObject.add_line, line_object, color, from + up * offset, to + up * offset)
	pcall(LineObject.add_line, line_object, color, from - up * offset, to - up * offset)
end

draw_main_path = function(line_object, color, height, player_position, max_distance, thickness)
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
							draw_thick_line(line_object, color, position, next_pos, thickness)
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
	local forced_labels = (mod:get("debug_labels_through_walls") or mod:get("debug_text_background")) and true or false
	if forced_labels and not debug_text_allowed then
		debug_text_allowed = true
	end
	local labels_through_walls = (mod:get("debug_labels_through_walls") == true) and debug_text_allowed
	local background_enabled = mod:get("debug_text_background") == true
	local markers_active = labels_through_walls or (debug_text_allowed and background_enabled)
	debug_state.force_label_markers = false
	debug_state.label_refresh_enabled = false
	if not markers_active then
		clear_debug_label_markers()
		debug_state.last_label_refresh_t = nil
		debug_state.last_label_refresh_position = nil
		debug_state.force_label_markers = false
	end
	local update_interval = mod:get("debug_update_interval") or 0
	if update_interval < 0 then
		update_interval = 0
	end
	local label_refresh_interval = tonumber(mod:get("debug_label_refresh_interval")) or 0.5
	if label_refresh_interval < 0 then
		label_refresh_interval = 0
	end
	local label_refresh_due = markers_active
		and (label_refresh_interval == 0 or not debug_state.last_label_refresh_t or (t and (t - debug_state.last_label_refresh_t) >= label_refresh_interval))
	if markers_active and debug_state.force_label_refresh_frames > 0 then
		label_refresh_due = true
	end

	local settings = get_debug_settings()
	if not settings.show_any then
		clear_line_object(world)
		clear_debug_label_markers()
		return
	end

	local line_object = ensure_line_object(world)
	if not line_object then
		return
	end

	do
		local ok_get, func = pcall(function()
			return MainPathQueries and MainPathQueries.is_main_path_registered
		end)
		if ok_get and type(func) == "function" then
			local ok, registered = pcall(function()
				return func(MainPathQueries)
			end)
			if ok and not registered then
				pcall(LineObject.reset, line_object)
				pcall(LineObject.dispatch, world, line_object)
				return
			end
		end
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
	state.cache_entry = cache_entry
	state.ritual_units = ritual_units
	state.ritual_enabled = ritual_enabled
	if markers_active and state.player_position then
		if not debug_state.last_label_refresh_position then
			label_refresh_due = true
		else
			local dx = state.player_position.x - debug_state.last_label_refresh_position.x
			local dy = state.player_position.y - debug_state.last_label_refresh_position.y
			local dz = state.player_position.z - debug_state.last_label_refresh_position.z
			if (dx * dx + dy * dy + dz * dz) >= debug_label_limits.move_threshold_sq then
				label_refresh_due = true
			end
		end
	end
	if markers_active and debug_label_state.marker_count == 0 then
		label_refresh_due = true
		if debug_state.force_label_refresh_frames < 1 then
			debug_state.force_label_refresh_frames = 1
		end
	end
	if label_refresh_due then
		debug_state.last_label_refresh_t = t or 0
		if state.player_position then
			debug_state.last_label_refresh_position = {
				x = state.player_position.x,
				y = state.player_position.y,
				z = state.player_position.z,
			}
		else
			debug_state.last_label_refresh_position = nil
		end
		if debug_state.force_label_refresh_frames > 0 then
			debug_state.force_label_refresh_frames = debug_state.force_label_refresh_frames - 1
		end
	end
	debug_state.label_refresh_enabled = label_refresh_due
	if update_interval > 0
		and t
		and debug_state.last_refresh_t
		and (t - debug_state.last_refresh_t) < update_interval
		and not label_refresh_due then
		pcall(LineObject.dispatch, world, line_object)
		return
	end
	debug_state.last_refresh_t = t or 0

	local debug_text = nil
	if settings.debug_text_enabled and not labels_through_walls and not background_enabled then
		debug_text = get_debug_text_manager(world)
		if debug_text then
			clear_debug_text(debug_text)
		else
			debug_state.force_label_markers = true
		end
	else
		clear_debug_text(debug_state.text_manager)
		destroy_debug_text_manager()
	end
	state.debug_text = debug_text
	if debug_state.force_label_markers then
		markers_active = true
		if not label_refresh_due then
			label_refresh_due = true
			debug_state.last_label_refresh_t = t or 0
			if state.player_position then
				debug_state.last_label_refresh_position = {
					x = state.player_position.x,
					y = state.player_position.y,
					z = state.player_position.z,
				}
			else
				debug_state.last_label_refresh_position = nil
			end
			if debug_state.force_label_refresh_frames > 0 then
				debug_state.force_label_refresh_frames = debug_state.force_label_refresh_frames - 1
			end
		end
		debug_state.label_refresh_enabled = label_refresh_due
	end
	markers_active = markers_active or debug_state.force_label_markers
	if not pcall(LineObject.reset, line_object) then
		destroy_debug_lines()
		return
	end
	if markers_active and label_refresh_due then
		begin_debug_label_markers()
	end
	if markers_active and label_refresh_due and state.player_position then
		prune_debug_label_markers(state.player_position)
	end

	draw_debug_path(settings, state)
	draw_debug_respawn_points(settings, state)
	draw_debug_progress(settings, state)
	draw_debug_boss_triggers(settings, state)
	draw_debug_pacing_triggers(settings, state)
	draw_debug_ambush_triggers(settings, state)
	draw_debug_backtrack_trigger(settings, state)
	draw_debug_ritual_triggers(settings, state)

	pcall(LineObject.dispatch, world, line_object)
	if markers_active and label_refresh_due then
		finalize_debug_label_markers()
	end
end

local function mark_dirty()
	markers_dirty = true
	timer_dirty = true
	debug_state.last_refresh_t = nil
	debug_state.last_label_refresh_t = nil
	debug_state.last_label_refresh_position = nil
	debug_state.force_label_refresh_frames = 0
end

local function collect_default_settings()
	local ok, data = pcall(mod.io_dofile, mod, "RitualZones/scripts/mods/RitualZones/RitualZones_data")
	if not ok or type(data) ~= "table" then
		return nil
	end

	local defaults = {}
	local function add_defaults(widgets)
		for i = 1, #widgets do
			local widget = widgets[i]
			if widget.setting_id and widget.default_value ~= nil then
				defaults[widget.setting_id] = widget.default_value
			end
			if widget.sub_widgets then
				add_defaults(widget.sub_widgets)
			end
		end
	end

	if data.options and data.options.widgets then
		add_defaults(data.options.widgets)
	end

	return defaults
end

local function reset_settings_to_defaults()
	if cache_state.resetting_settings then
		return
	end
	cache_state.resetting_settings = true

	local defaults = collect_default_settings()
	if defaults then
		for setting_id, default_value in pairs(defaults) do
			if type(mod.set) == "function" then
				mod:set(setting_id, default_value, false)
			end
		end
	end

	if type(mod.set) == "function" then
		mod:set("settings_reset_action", "idle", false)
	end
	cache_state.last_reset_action = "idle"
	cache_state.resetting_settings = false
	mark_dirty()
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
	respawn_state.waiting_active = false
	respawn_state.rewind_crossed = false
	respawn_state.rewind_lost = false
	cache_state.sweep_active = false
	cache_state.sweep_start_t = nil
	cache_state.sweep_hold_until = nil
	debug_state.last_refresh_t = nil
	debug_state.last_label_refresh_t = nil
	debug_state.last_label_refresh_position = nil
	debug_state.force_label_refresh_frames = 0
	mod._hud_data = nil
	if clear_text then
		local debug_text = get_debug_text_manager(world)
		clear_debug_text(debug_text)
		destroy_debug_text_manager()
	end
	mark_dirty()
end

local function ensure_marker_templates(world_markers)
	if not world_markers or not world_markers._marker_templates then
		return
	end
	if RitualZonesMarker then
		world_markers._marker_templates[RitualZonesMarker.name] = RitualZonesMarker
	end
	if RitualZonesTimerMarker then
		world_markers._marker_templates[RitualZonesTimerMarker.name] = RitualZonesTimerMarker
	end
	if RitualZonesDebugLabelMarker then
		world_markers._marker_templates[RitualZonesDebugLabelMarker.name] = RitualZonesDebugLabelMarker
	end
end

mod:hook_safe(CLASS.HudElementWorldMarkers, "init", function(self)
	ensure_marker_templates(self)
	marker_generation = marker_generation + 1
	markers_dirty = true
	timer_dirty = true
end)

local function prune_invalid_markers(world_markers)
	if not world_markers then
		return
	end
	local markers_by_type = world_markers._markers_by_type
	local markers_by_id = world_markers._markers_by_id
	if not markers_by_type or not markers_by_id then
		return
	end
	for marker_type, markers in pairs(markers_by_type) do
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

mod:hook(CLASS.HudElementWorldMarkers, "update", function(func, self, dt, t, ui_renderer, render_settings, input_service)
	ensure_marker_templates(self)
	if not mod:is_enabled() then
		prune_invalid_markers(self)
	end
	return func(self, dt, t, ui_renderer, render_settings, input_service)
end)

mod:hook_safe(CLASS.HudElementBossHealth, "event_boss_encounter_start", function(self, unit, boss_extension)
	if not unit_is_alive(unit) or not ScriptUnit.has_extension(unit, "unit_data_system") then
		return
	end
	ritual_ended_units[unit] = nil

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
	ritual_ended_units[unit] = true
	timer_state[unit] = nil
	local entry = timer_markers[unit]
	if entry and entry.id then
		Managers.event:trigger("remove_world_marker", entry.id)
	end
	timer_markers[unit] = nil
end)

mod.on_setting_changed = function()
	if cache_state.resetting_settings then
		return
	end
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
	local markers_active = (mod:get("debug_labels_through_walls") == true and debug_text_enabled_mode(mode))
		or (mod:get("debug_text_background") == true and debug_text_enabled_mode(mode))
	if not markers_active then
		clear_debug_label_markers()
	end
	if markers_active then
		debug_state.force_label_refresh_frames = 3
	end
	local through_walls = mod:get("debug_labels_through_walls") == true
	local background_on = mod:get("debug_text_background") == true
	if debug_state.last_labels_through_walls == nil then
		debug_state.last_labels_through_walls = through_walls
	end
	if debug_state.last_text_background == nil then
		debug_state.last_text_background = background_on
	end
	if through_walls ~= debug_state.last_labels_through_walls or background_on ~= debug_state.last_text_background then
		clear_debug_label_markers()
		debug_state.last_label_refresh_t = nil
		debug_state.last_label_refresh_position = nil
		debug_state.force_label_refresh_frames = 3
		debug_state.last_labels_through_walls = through_walls
		debug_state.last_text_background = background_on
	end

	local record_enabled = cache_record_enabled()
	if record_enabled ~= cache_state.last_record_enabled then
		cache_state.last_record_enabled = record_enabled
		if record_enabled then
			cache_debug("Cache record enabled")
			cache_state.record_mission = nil
			cache_state.record_count = 0
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
	if use_enabled ~= cache_state.last_use_enabled then
		cache_state.last_use_enabled = use_enabled
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
	if use_offline_enabled ~= cache_state.last_use_offline_enabled then
		cache_state.last_use_offline_enabled = use_offline_enabled
		if use_offline_enabled then
			cache_debug("Cache use enabled (offline)")
			if cache_reads_allowed() then
				refresh_cache_from_disk()
			end
		else
			cache_debug("Cache use disabled (offline)")
		end
	end

	local clear_action = mod:get("cache_clear_action") or "idle"
	if clear_action ~= cache_state.last_clear_action then
		cache_state.last_clear_action = clear_action
		if clear_action == "execute" then
			mod.clear_cache_keybind_func()
			cache_state.last_clear_action = "idle"
			if type(mod.set) == "function" then
				mod:set("cache_clear_action", "idle", false)
			end
		end
	end

	local reset_action = mod:get("settings_reset_action") or "idle"
	if reset_action ~= cache_state.last_reset_action then
		cache_state.last_reset_action = reset_action
		if reset_action == "execute" then
			reset_settings_to_defaults()
		end
	end
end

mod.on_enabled = function()
	cleanup_done = false
	mark_dirty()
end

mod.on_game_state_changed = function(status, state_name)
	if status == "enter" and (state_name == "GameplayStateRun" or state_name == "StateGameplay") then
		mark_dirty()
		debug_state.force_label_refresh_frames = 2
		if cache_reads_allowed() then
			refresh_cache_from_disk()
		end
		return
	end

	if cache_state.runtime_dirty then
		ensure_cache_loaded()
		write_cache_file()
	end
	reset_runtime_state(true)
	cleanup_done = false
end

mod.on_disabled = function()
	if cache_state.runtime_dirty then
		ensure_cache_loaded()
		write_cache_file()
	end
	reset_runtime_state(true)
	cleanup_done = true
end

mod.update = function(dt, t)
	flush_pending_marker_cleanup()
	if not mod:is_enabled() then
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

	local ritual_features_enabled = mod:get("ritualzones_enabled") and true or false
	local ritual_enabled = ritual_features_enabled and is_havoc_ritual_active()
	local ritual_units = ritual_enabled and find_ritual_units() or {}

	if ritual_features_enabled then
		update_markers(ritual_units)
		update_timer_markers(ritual_units, dt or 0, t or 0)
	else
		if next(markers) ~= nil then
			clear_markers()
		end
		if next(timer_markers) ~= nil then
			clear_timer_markers()
		end
		for unit in pairs(timer_state) do
			timer_state[unit] = nil
		end
		for unit in pairs(ritual_ended_units) do
			ritual_ended_units[unit] = nil
		end
		for key in pairs(speedup_triggered) do
			speedup_triggered[key] = nil
		end
		for key in pairs(ritual_start_triggered) do
			ritual_start_triggered[key] = nil
		end
		for key in pairs(ritual_spawn_triggered) do
			ritual_spawn_triggered[key] = nil
		end
	end

	update_cache_sweep(t or 0)
	record_offline_cache(ritual_units, t or 0)
	draw_debug_lines(world, ritual_units, t or 0, ritual_enabled)

	local hud_enabled = mod:get("hud_enabled")
	if hud_enabled then
		local ok = pcall(function()
			local hud_state = build_debug_state(nil)
			local entries = {}
			local self_entry = nil
			local leader_player = hud_state.leader_player
			local leader_name = leader_player and get_player_name and get_player_name(leader_player) or nil
			local progress_entries = hud_state.progress_entries or {}
			for i = 1, #progress_entries do
				local entry = progress_entries[i]
				local name = get_player_name and get_player_name(entry.player) or nil
				local info = {
					name = name,
					distance = entry.distance,
					is_local = entry.is_local,
					is_leader = leader_player and entry.player == leader_player or false,
					alive = entry.alive,
				}
				entries[#entries + 1] = info
				if entry.is_local then
					self_entry = info
				end
			end
			mod._hud_data = {
				player_distance = hud_state.player_distance,
				leader_distance = hud_state.leader_distance,
				leader_name = leader_name,
				max_progress_distance = hud_state.max_progress_distance,
				entries = entries,
				self = self_entry,
			}
		end)
		if not ok then
			mod._hud_data = nil
		end
	else
		mod._hud_data = nil
	end
end
