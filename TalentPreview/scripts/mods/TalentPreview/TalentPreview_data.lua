--[[
	File: TalentPreview_data.lua
	Description: Data file to pull setting defaults and data for mod settings
	Overall Release Version: 1.1.0
	File Version: 1.1.0
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
                setting_id = "show_keystone",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_stat",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_default",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_modifiers",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_aura",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_blitz",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_ability_modifiers",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "show_broker_stimm",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "preview_background",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "preview_background_character",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "icon_size",
                type = "numeric",
                default_value = 60,
                range = {25, 100},
                decimals_number = 0,
            },
            {
                setting_id = "icons_per_row",
                type = "numeric",
                default_value = 4,
                range = {3, 10},
                decimals_number = 0,
            },
            {
                setting_id = "preview_offset_y",
                type = "numeric",
                default_value = 170,
                range = {0, 300},
                decimals_number = 0,
            },
            {
                setting_id = "preview_offset_x",
                type = "numeric",
                default_value = -10,
                range = {-200, 200},
                decimals_number = 0,
            },
        },
    },
}
