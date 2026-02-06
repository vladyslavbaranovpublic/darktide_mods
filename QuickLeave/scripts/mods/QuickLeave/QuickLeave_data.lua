--[[
	File: QuickLeave_data.lua
	Description: Mod settings and metadata.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	File Introduced in: 1.0.0
	Last Updated: 2026-02-06
	Author: LAUREHTE
]]
local mod = get_mod("QuickLeave")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	allow_rehooking = true,
	options = {
		widgets = {
			{
				setting_id = "show_in_intro",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "show_in_outro",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "use_safe_button_template",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "debug_enabled",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "quick_leave_hotkey",
				type = "keybind",
				default_value = {},
				keybind_trigger = "pressed",
				keybind_type = "function_call",
				function_name = "quick_leave_hotkey",
			},
		},
	},
}
