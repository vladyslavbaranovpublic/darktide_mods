--[[
	File: hud_element_slowmode_timer_definitions.lua
	Description: Scenegraph and widget definitions for the SlowMode timer HUD element.
	Overall Release Version: 1.1.0
	File Version: 1.0.0
	Last Updated: 2026-01-05
	Author: LAUREHTE
]]
local UIHudSettings = require("scripts/settings/ui/ui_hud_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local DEFAULT_SIZE = { 400, 40 }
local DEFAULT_POSITION = { 20, 20, 60 }
local DEFAULT_FONT_SIZE = 20

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	timer = {
		parent = "screen",
		vertical_alignment = "top",
		horizontal_alignment = "left",
		size = DEFAULT_SIZE,
		position = DEFAULT_POSITION,
	},
}

local widget_definitions = {
	timer = UIWidget.create_definition({
		{
			pass_type = "text",
			style_id = "timer_text",
			value_id = "timer_text",
			value = "Time: 0.000s",
			style = {
				font_size = DEFAULT_FONT_SIZE,
				text_vertical_alignment = "top",
				text_horizontal_alignment = "left",
				font_type = "proxima_nova_bold",
				text_color = UIHudSettings.color_tint_main_1,
				offset = { 0, 0, 2 },
			},
		},
	}, "timer"),
}

return {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
}
