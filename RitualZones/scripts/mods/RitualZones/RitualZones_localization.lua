--[[
	File: RitualZones_localization.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.01.0
	File Version: 1.1.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
return {
	mod_name = {
		en = "{#color(180,120,255)}\xEE\x80\x9E Ritual Zones \xEE\x80\x9E{#reset()}",
	},
	mod_description = {
		en = "{#color(180,120,255)}Release 1.0.0{#reset()} | Author: LAUREHTE\nDraws ritual trigger zones and shows ritual timers for havoc daemonhosts.",
	},
	ritualzones_enabled = {
		en = "Enable Ritual Zones",
	},
	marker_group = {
		en = "{#color(210,170,255)}Marker & Tracker{#reset()}",
	},
	marker_enabled = {
		en = "Show skull marker",
	},
	marker_size = {
		en = "Skull marker size",
	},
	marker_through_walls_enabled = {
		en = "Show markers through walls",
	},
	tracker_height = {
		en = "Tracker text height",
	},
	tracker_size = {
		en = "Tracker text size",
	},
	debug_visual_group = {
		en = "{#color(210,170,255)}Debug Visuals{#reset()}",
	},
	debug_text_group = {
		en = "{#color(210,170,255)}Debug Text{#reset()}",
	},
	cache_group = {
		en = "{#color(210,170,255)}Cache{#reset()}",
	},
	boss_group = {
		en = "{#color(210,170,255)}Boss Triggers{#reset()}",
	},
	pacing_group = {
		en = "{#color(210,170,255)}Pacing & Ambush{#reset()}",
	},
	respawn_group = {
		en = "{#color(210,170,255)}Respawn{#reset()}",
	},
	debug_enabled = {
		en = "Enable debug visuals",
	},
	path_enabled = {
		en = "Draw main path",
	},
	debug_text_enabled = {
		en = "Debug text mode",
	},
	debug_labels_through_walls = {
		en = "Debug labels through walls",
	},
	debug_text_mode_off = {
		en = "Off",
	},
	debug_text_mode_on = {
		en = "On",
	},
	debug_text_mode_labels = {
		en = "Labels only",
	},
	debug_text_mode_distances = {
		en = "Distances only",
	},
	debug_text_mode_both = {
		en = "Labels + distances",
	},
	debug_text_size = {
		en = "Debug text size",
	},
	debug_text_height = {
		en = "Debug text height",
	},
	debug_update_interval = {
		en = "Debug refresh interval (sec)",
	},
	debug_draw_distance = {
		en = "Debug draw distance (m)",
	},
	debug_label_height_group = {
		en = "{#color(210,170,255)}Debug Label Heights{#reset()}",
	},
	debug_text_z_offset = {
		en = "Label height offset (0.5 steps)",
	},
	cache_record_enabled = {
		en = "Record offline cache",
	},
	cache_debug_enabled = {
		en = "Cache debug output",
	},
	cache_update_interval = {
		en = "Cache update interval (sec)",
	},
	cache_use_enabled = {
		en = "Use cached data online",
	},
	cache_use_offline_enabled = {
		en = "Use cached data offline",
	},
	boss_trigger_spheres_enabled = {
		en = "Draw boss trigger spheres",
	},
	boss_mutator_triggers_enabled = {
		en = "Boss triggers: mutator monsters",
	},
	boss_twins_triggers_enabled = {
		en = "Boss triggers: twins ambush",
	},
	twins_ambush_triggers_mode = {
		en = "Twins ambush triggers",
	},
	twins_ambush_triggers_off = {
		en = "Off",
	},
	twins_ambush_triggers_always = {
		en = "Always",
	},
	twins_ambush_triggers_until_spawn = {
		en = "Until twins spawn",
	},
	twins_spawn_triggers_mode = {
		en = "Twins spawn triggers",
	},
	twins_spawn_triggers_off = {
		en = "Off",
	},
	twins_spawn_triggers_always = {
		en = "Always",
	},
	twins_spawn_triggers_until_spawn = {
		en = "Until twins spawn",
	},
	boss_patrol_triggers_enabled = {
		en = "Boss triggers: patrol pacing",
	},
	pacing_spawn_triggers_enabled = {
		en = "Draw pacing spawn triggers",
	},
	ambush_trigger_spheres_enabled = {
		en = "Draw ambush horde triggers",
	},
	backtrack_trigger_sphere_enabled = {
		en = "Draw backtrack horde trigger",
	},
	respawn_progress_enabled = {
		en = "Draw respawn progress points",
	},
	respawn_beacon_enabled = {
		en = "Draw respawn beacons",
	},
	priority_beacon_enabled = {
		en = "Draw priority respawn beacon",
	},
	respawn_beacon_line_enabled = {
		en = "Draw line to active beacon",
	},
	respawn_threshold_enabled = {
		en = "Draw respawn thresholds",
	},
	respawn_backline_enabled = {
		en = "Draw respawn backline",
	},
	respawn_move_triggers_enabled = {
		en = "Rescue move triggers",
	},
	priority_move_triggers_enabled = {
		en = "Priority move triggers",
	},
	respawn_move_triggers_off = {
		en = "Off",
	},
	respawn_move_triggers_always = {
		en = "Always",
	},
	respawn_move_triggers_hogtied = {
		en = "Only when hogtied",
	},
	path_height = {
		en = "Path height",
	},
	sphere_radius_scale = {
		en = "Sphere radius scale",
	},
	trigger_points_enabled = {
		en = "Draw trigger points",
	},
	progress_point_enabled = {
		en = "Draw progress point",
	},
	progress_height = {
		en = "Progress point height",
	},
	gate_enabled = {
		en = "Draw gate",
	},
	gate_width = {
		en = "Gate width",
	},
	gate_height = {
		en = "Gate height",
	},
	gate_slices = {
		en = "Gate slices",
	},
}
