--[[
	File: RitualZones_marker.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	Last Updated: 2026-01-06
	Author: LAUREHTE
]]
local UIWidget = require("scripts/managers/ui/ui_widget")

local template = {}
local DEFAULT_ICON = "content/ui/materials/icons/difficulty/difficulty_skull_uprising"
local DEFAULT_COLOR = { 180, 120, 255 }

template.name = "RitualZones_marker"
template.size = {
	64,
	64,
}
template.unit_node = "ui_marker"
template.max_distance = 200
template.min_distance = 0
template.position_offset = {
	0,
	0,
	1.2,
}
template.check_line_of_sight = false

local function apply_icon_settings(widget, marker)
	local data = marker.data or {}
	local icon_size = data.icon_size or template.size[1]
	local icon_color = data.color or DEFAULT_COLOR

	local style = widget.style.icon
	style.size[1] = icon_size
	style.size[2] = icon_size
	style.default_size[1] = icon_size
	style.default_size[2] = icon_size
	style.color[2] = icon_color[1] or DEFAULT_COLOR[1]
	style.color[3] = icon_color[2] or DEFAULT_COLOR[2]
	style.color[4] = icon_color[3] or DEFAULT_COLOR[3]

	widget.content.icon = data.icon or DEFAULT_ICON
	marker.template.check_line_of_sight = false
end

template.create_widget_defintion = function(self, scenegraph_id)
	local size = self.size

	return UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "icon",
			value = DEFAULT_ICON,
			value_id = "icon",
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "center",
				size = {
					size[1],
					size[2],
				},
				default_size = {
					size[1],
					size[2],
				},
				offset = {
					0,
					0,
					0,
				},
				color = {
					255,
					DEFAULT_COLOR[1],
					DEFAULT_COLOR[2],
					DEFAULT_COLOR[3],
				},
			},
			visibility_function = function(content)
				return content.icon ~= nil
			end,
		},
	}, scenegraph_id)
end

template.on_enter = function(widget, marker)
	apply_icon_settings(widget, marker)
end

template.update_function = function(parent, ui_renderer, widget, marker)
	apply_icon_settings(widget, marker)

	widget.content.line_of_sight_progress = 1
	widget.alpha_multiplier = 1

	return false
end

return template
