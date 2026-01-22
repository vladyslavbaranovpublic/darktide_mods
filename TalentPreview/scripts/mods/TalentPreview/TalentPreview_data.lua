--[[
	File: TalentPreview_data.lua
	Description: Data file to pull setting defaults and data for mod settings
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	Last Updated: 2026-01-21
	Author: LAUREHTE
]]

local mod = get_mod("TalentPreview")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "enable_in_lobby",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "icon_size",
                type = "numeric",
                default_value = 50,
                range = {25, 100},
                decimals_number = 0,
            },
            {
                setting_id = "icons_per_row",
                type = "numeric",
                default_value = 5,
                range = {3, 10},
                decimals_number = 0,
            },
            {
                setting_id = "preview_offset_y",
                type = "numeric",
                default_value = 150,
                range = {0, 300},
                decimals_number = 0,
            },
            {
                setting_id = "preview_offset_x",
                type = "numeric",
                default_value = -35,
                range = {-200, 200},
                decimals_number = 0,
            },
        },
    },
}
