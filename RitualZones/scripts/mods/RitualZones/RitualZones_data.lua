--[[
	File: RitualZones_data.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.01.0
	File Version: 1.1.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local mod = get_mod("RitualZones")

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
						default_value = false,
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
						default_value = 25,
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
						default_value = false,
					},
					{
						setting_id = "debug_draw_distance",
						type = "numeric",
						default_value = 80,
						range = { 0, 150 },
						decimals_number = 1,
					},
					{
						setting_id = "debug_update_interval",
						type = "numeric",
						default_value = 0.1,
						range = { 0, 0.5 },
						decimals_number = 3,
					},
					{
						setting_id = "path_height",
						type = "numeric",
						default_value = 0.15,
						range = { 0, 3 },
						decimals_number = 2,
					},
					{
						setting_id = "sphere_radius_scale",
						type = "numeric",
						default_value = 1,
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
						default_value = true,
					},
					{
						setting_id = "gate_width",
						type = "numeric",
						default_value = 6,
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
						default_value = 4,
						range = { 1, 20 },
					},
					{
						setting_id = "progress_point_enabled",
						type = "checkbox",
						default_value = true,
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
				setting_id = "debug_text_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_text_enabled",
						type = "dropdown",
						default_value = "off",
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
						setting_id = "debug_text_size",
						type = "numeric",
						default_value = 0.2,
						range = { 0.05, 1 },
						decimals_number = 2,
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
				setting_id = "cache_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "cache_record_enabled",
						type = "checkbox",
						default_value = false,
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
						default_value = 1.0,
						range = { 0.1, 10 },
						decimals_number = 2,
					},
					{
						setting_id = "cache_debug_enabled",
						type = "checkbox",
						default_value = false,
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
						default_value = false,
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
						default_value = false,
					},
					{
						setting_id = "ambush_trigger_spheres_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "backtrack_trigger_sphere_enabled",
						type = "checkbox",
						default_value = false,
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
						default_value = false,
					},
					{
						setting_id = "respawn_beacon_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "priority_beacon_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "respawn_beacon_line_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "respawn_threshold_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "respawn_backline_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "respawn_move_triggers_enabled",
						type = "dropdown",
						default_value = "hogtied",
						options = {
							{ text = "respawn_move_triggers_off", value = "off" },
							{ text = "respawn_move_triggers_always", value = "always" },
							{ text = "respawn_move_triggers_hogtied", value = "hogtied" },
						},
					},
					{
						setting_id = "priority_move_triggers_enabled",
						type = "dropdown",
						default_value = "hogtied",
						options = {
							{ text = "respawn_move_triggers_off", value = "off" },
							{ text = "respawn_move_triggers_always", value = "always" },
							{ text = "respawn_move_triggers_hogtied", value = "hogtied" },
						},
					},
				},
			},
			{
				setting_id = "debug_label_height_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_text_z_offset",
						type = "numeric",
						default_value = 0,
						range = { -6, 6 },
						decimals_number = 1,
					},
				},
			},
		},
	},
}
