local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIHudSettings = require("scripts/settings/ui/ui_hud_settings")

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	ritualzones_hud = {
		parent = "screen",
		vertical_alignment = "top",
		horizontal_alignment = "left",
		size = { 520, 300 },
		position = { 20, 240, 55 },
	},
}

local widget_definitions = {
	ritualzones_hud = UIWidget.create_definition({
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				color = { 140, 0, 0, 0 },
				offset = { 0, 0, 1 },
				size = { 420, 220 },
			},
		},
		{
			pass_type = "text",
			style_id = "hud_text",
			value_id = "hud_text",
			value = "",
			style = {
				font_size = 18,
				text_vertical_alignment = "top",
				text_horizontal_alignment = "left",
				font_type = "proxima_nova_bold",
				text_color = UIHudSettings.color_tint_main_1,
				offset = { 8, 8, 2 },
				size = { 404, 204 },
			},
		},
	}, "ritualzones_hud"),
}

return {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
}
