--[[
	File: RitualZones_data.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	Last Updated: 2026-01-06
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
						default_value = 42,
						range = { 16, 96 },
					},
					{
						setting_id = "tracker_height",
						type = "numeric",
						default_value = 0.8,
						range = { 0.2, 3 },
						decimals_number = 1,
					},
					{
						setting_id = "tracker_size",
						type = "numeric",
						default_value = 22,
						range = { 10, 48 },
					},
				},
			},
			{
				setting_id = "debug_group",
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
						setting_id = "debug_text_enabled",
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
						default_value = 0.4,
						range = { 0, 3 },
						decimals_number = 2,
					},
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
						setting_id = "boss_patrol_triggers_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "pacing_spawn_triggers_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "respawn_progress_enabled",
						type = "checkbox",
						default_value = false,
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
				},
			},
		},
	},
}
