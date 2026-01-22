--[[
	File: SlowMode_data.lua
	Description: Mod settings and UI layout for SlowMode.
	Overall Release Version: 1.1.0
	File Version: 1.0.0
	Last Updated: 2026-01-05
	Author: LAUREHTE
]]
local mod = get_mod("SlowMode")

local function numeric_setting(setting_id, default_value, min_value, max_value, step_size)
	return {
		setting_id = setting_id,
		type = "numeric",
		range = { min_value, max_value },
		default_value = default_value,
		decimals_number = 0,
		step_size_value = step_size or 1,
	}
end

local function keybind_setting(setting_id, function_name)
	return {
		setting_id = setting_id,
		type = "keybind",
		default_value = {},
		keybind_global = true,
		keybind_trigger = "pressed",
		keybind_type = "function_call",
		function_name = function_name,
	}
end

local mod_data = {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "slowmode_general_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "slowmode_enabled",
						type = "checkbox",
						default_value = true,
					},
					numeric_setting("slowmode_speed_percent", 100, 0, 500, 1),
				},
			},
			{
				setting_id = "slowmode_presets_group",
				type = "group",
				sub_widgets = {
					numeric_setting("slowmode_preset_1_percent", 50, 0, 500, 1),
					keybind_setting("slowmode_preset_1_key", "apply_preset_1"),
					numeric_setting("slowmode_preset_2_percent", 100, 0, 500, 1),
					keybind_setting("slowmode_preset_2_key", "apply_preset_2"),
					numeric_setting("slowmode_preset_3_percent", 150, 0, 500, 1),
					keybind_setting("slowmode_preset_3_key", "apply_preset_3"),
				},
			},
			{
				setting_id = "slowmode_hotkeys_group",
				type = "group",
				sub_widgets = {
					keybind_setting("slowmode_speed_up", "increase_speed"),
					keybind_setting("slowmode_speed_down", "decrease_speed"),
				},
			},
			{
				setting_id = "slowmode_timer_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "slowmode_show_timer",
						type = "checkbox",
						default_value = false,
					},
					numeric_setting("slowmode_timer_font_size", 20, 8, 72, 1),
					numeric_setting("slowmode_timer_x", 20, 0, 5000, 1),
					numeric_setting("slowmode_timer_y", 20, 0, 2000, 1),
				},
			},
		},
	},
}

return mod_data
