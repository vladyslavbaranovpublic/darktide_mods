--[[
	File: RitualZones_data.lua
	Description: Settings and mod data file.
	Overall Release Version: 1.2.0
	File Version: 1.2.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local mod = get_mod("RitualZones")

local color_options = {}
if Color and Color.list then
	for _, color_name in ipairs(Color.list) do
		local localized_name = mod:localize(color_name)
		color_options[#color_options + 1] = {
			text = color_name,
			value = color_name,
			localized_text = localized_name,
		}
	end
	table.sort(color_options, function(a, b)
		return a.text < b.text
	end)
end

local function get_color_options()
	return table.clone(color_options)
end

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "ritualzones_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "ritual_text_background_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "marker_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "marker_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "marker_size",
						type = "numeric",
						default_value = 80,
						range = { 16, 124 },
					},
					{
						setting_id = "marker_through_walls_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "tracker_height",
						type = "numeric",
						default_value = 2.0,
						range = { 0.2, 5 },
						decimals_number = 1,
					},
					{
						setting_id = "tracker_size",
						type = "numeric",
						default_value = 35,
						range = { 10, 60 },
					},
				},
			},
			{
				setting_id = "debug_visual_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "path_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "path_line_thickness",
						type = "numeric",
						default_value = 0.1,
						range = { 0, 0.5 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_draw_distance",
						type = "numeric",
						default_value = 120,
						range = { 0, 150 },
						decimals_number = 1,
					},
					{
						setting_id = "debug_update_interval",
						type = "numeric",
						default_value = 0.01,
						range = { 0, 0.5 },
						decimals_number = 3,
					},
					{
						setting_id = "path_height",
						type = "numeric",
						default_value = 0.45,
						range = { 0, 3 },
						decimals_number = 2,
					},
					{
						setting_id = "sphere_radius_scale",
						type = "numeric",
						default_value = 0.35,
						range = { 0.2, 4 },
						decimals_number = 2,
					},
					{
						setting_id = "trigger_points_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "gate_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "gate_width",
						type = "numeric",
						default_value = 10,
						range = { 1, 100 },
					},
					{
						setting_id = "gate_height",
						type = "numeric",
						default_value = 8,
						range = { 1, 50 },
					},
					{
						setting_id = "gate_slices",
						type = "numeric",
						default_value = 10,
						range = { 1, 40 },
					},
					{
						setting_id = "progress_point_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "progress_spheres_mode",
						type = "dropdown",
						default_value = "all",
						options = {
							{ text = "progress_spheres_mode_all", value = "all" },
							{ text = "progress_spheres_mode_self", value = "self" },
							{ text = "progress_spheres_mode_leader", value = "leader" },
							{ text = "progress_spheres_mode_slot", value = "slot" },
						},
					},
					{
						setting_id = "progress_spheres_slot",
						type = "numeric",
						default_value = 1,
						range = { 1, 4 },
					},
					{
						setting_id = "progress_line_mode",
						type = "dropdown",
						default_value = "all",
						options = {
							{ text = "progress_line_mode_off", value = "off" },
							{ text = "progress_line_mode_self", value = "self" },
							{ text = "progress_line_mode_slot", value = "slot" },
							{ text = "progress_line_mode_all", value = "all" },
						},
					},
					{
						setting_id = "progress_gate_mode",
						type = "dropdown",
						default_value = "off",
						options = {
							{ text = "progress_gate_mode_off", value = "off" },
							{ text = "progress_gate_mode_self", value = "self" },
							{ text = "progress_gate_mode_slot", value = "slot" },
							{ text = "progress_gate_mode_all", value = "all" },
						},
					},
					{
						setting_id = "progress_gate_leader_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "progress_gate_max_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "progress_gate_width",
						type = "numeric",
						default_value = 6,
						range = { 1, 50 },
					},
					{
						setting_id = "progress_gate_height",
						type = "numeric",
						default_value = 6,
						range = { 1, 30 },
					},
					{
						setting_id = "progress_gate_slices",
						type = "numeric",
						default_value = 4,
						range = { 1, 40 },
					},
					{
						setting_id = "progress_line_thickness",
						type = "numeric",
						default_value = 0,
						range = { 0, 0.5 },
						decimals_number = 2,
					},
					{
						setting_id = "progress_height",
						type = "numeric",
						default_value = 0.15,
						range = { 0, 3 },
						decimals_number = 2,
					},
				},
			},
			{
				setting_id = "color_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "color_sphere",
						type = "dropdown",
						default_value = "lime",
						options = get_color_options(),
					},
					{
						setting_id = "color_line",
						type = "dropdown",
						default_value = "deep_pink",
						options = get_color_options(),
					},
					{
						setting_id = "color_passed",
						type = "dropdown",
						default_value = "white",
						options = get_color_options(),
					},
					{
						setting_id = "color_path",
						type = "dropdown",
						default_value = "steel_blue",
						options = get_color_options(),
					},
					{
						setting_id = "color_beacon",
						type = "dropdown",
						default_value = "yellow_green",
						options = get_color_options(),
					},
				},
			},
			{
				setting_id = "debug_text_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_text_enabled",
						type = "dropdown",
						default_value = "on",
						options = {
							{ text = "debug_text_mode_off", value = "off" },
							{ text = "debug_text_mode_on", value = "on" },
							{ text = "debug_text_mode_labels", value = "labels" },
							{ text = "debug_text_mode_distances", value = "distances" },
							{ text = "debug_text_mode_both", value = "both" },
						},
					},
					{
						setting_id = "debug_labels_through_walls",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "debug_text_background",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "debug_text_size",
						type = "numeric",
						default_value = 0.2,
						range = { 0.05, 1 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_label_distance_scale_min",
						type = "numeric",
						default_value = 0.10,
						range = { 0.05, 1.5 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_label_distance_scale_max",
						type = "numeric",
						default_value = .5,
						range = { 0.05, 3 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_label_distance_scale_range",
						type = "numeric",
						default_value = 100,
						range = { 10, 600 },
						decimals_number = 0,
					},
					{
						setting_id = "debug_text_height",
						type = "numeric",
						default_value = 0.2,
						range = { 0, 3 },
						decimals_number = 2,
					},
				},
			},
			{
				setting_id = "hud_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "hud_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_pos_x",
						type = "numeric",
						default_value = 20,
						range = { -2000, 2000 },
					},
					{
						setting_id = "hud_pos_y",
						type = "numeric",
						default_value = 240,
						range = { -2000, 2000 },
					},
					{
						setting_id = "hud_width",
						type = "numeric",
						default_value = 420,
						range = { 120, 1000 },
					},
					{
						setting_id = "hud_height",
						type = "numeric",
						default_value = 220,
						range = { 60, 600 },
					},
					{
						setting_id = "hud_font_size",
						type = "numeric",
						default_value = 18,
						range = { 10, 36 },
					},
					{
						setting_id = "hud_bg_opacity",
						type = "numeric",
						default_value = 140,
						range = { 0, 255 },
					},
					{
						setting_id = "hud_show_self",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_show_all",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_show_max",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_show_leader",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_show_leader_name",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "cache_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "cache_record_enabled",
						type = "checkbox",
						default_value = false,
						tooltip = "cache_record_enabled_desc",

					},
					{
						setting_id = "cache_sweep_keybind",
						type = "keybind",
						default_value = {},
						keybind_global = true,
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "cache_sweep_keybind_func",
						tooltip = "cache_sweep_keybind_desc",
					},
					{
						setting_id = "cache_sweep_duration",
						type = "numeric",
						default_value = 15.0,
						range = { 5, 30 },
						decimals_number = 1,
					},
					{
						setting_id = "cache_use_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "cache_use_offline_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "cache_update_interval",
						type = "numeric",
						default_value = 20.0,
						range = { 0.1, 60 },
						decimals_number = 1,
					},
					{
						setting_id = "cache_path_tolerance",
						type = "numeric",
						default_value = 40,
						range = { 0, 200 },
						decimals_number = 1,
					},
					{
						setting_id = "cache_debug_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "cache_clear_action",
						type = "dropdown",
						default_value = "idle",
						options = {
							{ text = "cache_clear_action_idle", value = "idle" },
							{ text = "cache_clear_action_execute", value = "execute" },
						},
						tooltip = "cache_clear_action_desc",
					},
				},
			},
			{
				setting_id = "boss_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "boss_trigger_spheres_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "boss_mutator_triggers_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "boss_twins_triggers_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "twins_ambush_triggers_mode",
						type = "dropdown",
						default_value = "always",
						options = {
							{ text = "twins_ambush_triggers_off", value = "off" },
							{ text = "twins_ambush_triggers_always", value = "always" },
							{ text = "twins_ambush_triggers_until_spawn", value = "until_spawn" },
						},
					},
					{
						setting_id = "twins_spawn_triggers_mode",
						type = "dropdown",
						default_value = "always",
						options = {
							{ text = "twins_spawn_triggers_off", value = "off" },
							{ text = "twins_spawn_triggers_always", value = "always" },
							{ text = "twins_spawn_triggers_until_spawn", value = "until_spawn" },
						},
					},
					{
						setting_id = "boss_patrol_triggers_enabled",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "pacing_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "pacing_spawn_triggers_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "ambush_trigger_spheres_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "backtrack_trigger_sphere_enabled",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "respawn_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "respawn_progress_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "respawn_beacon_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "priority_beacon_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "respawn_beacon_line_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "respawn_threshold_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "respawn_backline_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "respawn_move_triggers_enabled",
						type = "dropdown",
						default_value = "always",
						options = {
							{ text = "respawn_move_triggers_off", value = "off" },
							{ text = "respawn_move_triggers_always", value = "always" },
							{ text = "respawn_move_triggers_hogtied", value = "hogtied" },
						},
					},
					{
						setting_id = "priority_move_triggers_enabled",
						type = "dropdown",
						default_value = "always",
						options = {
							{ text = "respawn_move_triggers_off", value = "off" },
							{ text = "respawn_move_triggers_always", value = "always" },
							{ text = "respawn_move_triggers_hogtied", value = "hogtied" },
						},
					},
				},
			},
			{
				setting_id = "performance_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_label_marker_cap",
						type = "numeric",
						default_value = 40,
						range = { 10, 200 },
						decimals_number = 0,
						tooltip = "debug_label_marker_cap_desc",
					},
					{
						setting_id = "debug_label_move_threshold",
						type = "numeric",
						default_value = 0.20,
						range = { 0.0, 4 },
						decimals_number = 2,
						tooltip = "debug_label_move_threshold_desc",
					},
					{
						setting_id = "debug_label_draw_distance",
						type = "numeric",
						default_value = 40,
						range = { 0, 250 },
						decimals_number = 0,
						tooltip = "debug_label_draw_distance_desc",
					},
					{
						setting_id = "debug_label_refresh_interval",
						type = "numeric",
						default_value = 0.70,
						range = { 0, 5 },
						decimals_number = 2,
						tooltip = "debug_label_refresh_interval_desc",
					},
				},
			},
			{
				setting_id = "debug_helpers_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_text_z_offset",
						type = "numeric",
						default_value = -2,
						range = { -6, 6 },
						decimals_number = 1,
					},
					{
						setting_id = "debug_respawn_warning",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "settings_reset_action",
						type = "dropdown",
						default_value = "idle",
						options = {
							{ text = "settings_reset_action_idle", value = "idle" },
							{ text = "settings_reset_action_execute", value = "execute" },
						},
						tooltip = "settings_reset_action_desc",
					},
				},
			},
		},
	},
}
