--[[
	File: RitualZones_debug_label_marker.lua
	Description: Debug label marker used for through-wall text.
	Overall Release Version: 1.01.0
	File Version: 1.1.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local UIWidget = require("scripts/managers/ui/ui_widget")

local template = {}

template.name = "RitualZones_debug_label_marker"
template.size = {
	600,
	120,
}
template.max_distance = 200
template.min_distance = 0
template.position_offset = {
	0,
	0,
	0,
}
template.check_line_of_sight = false

local function resolve_font_size(value)
	local size = tonumber(value) or 0.2
	local scaled = math.floor(size * 100 + 0.5)
	if scaled < 14 then
		scaled = 14
	elseif scaled > 64 then
		scaled = 64
	end
	return scaled
end

local DEFAULT_COLOR = { 255, 255, 255 }
local DEFAULT_FONT = "proxima_nova_bold"

template.create_widget_defintion = function(self, scenegraph_id)
	return UIWidget.create_definition({
		{
			pass_type = "text",
			style_id = "label",
			value_id = "label",
			value = "",
			style = {
				vertical_alignment = "center",
				horizontal_alignment = "center",
				text_vertical_alignment = "center",
				text_horizontal_alignment = "center",
				font_type = DEFAULT_FONT,
				font_size = 22,
				text_color = { 255, 255, 255, 255 },
				default_text_color = { 255, 255, 255, 255 },
				offset = { 0, 0, 0 },
				size = template.size,
			},
		},
	}, scenegraph_id)
end

template.on_enter = function(widget, marker)
	local data = marker.data or {}
	widget.content.label = data.text or ""
	widget.style.label.font_size = resolve_font_size(data.text_size)
	template.position_offset[3] = data.height or template.position_offset[3]
end

template.update_function = function(parent, ui_renderer, widget, marker)
	local data = marker.data or {}
	local style = widget.style.label
	local color = data.color or DEFAULT_COLOR

	widget.content.label = data.text or ""
	style.font_size = resolve_font_size(data.text_size or style.font_size)
	style.text_color[2] = color[1] or DEFAULT_COLOR[1]
	style.text_color[3] = color[2] or DEFAULT_COLOR[2]
	style.text_color[4] = color[3] or DEFAULT_COLOR[3]
	marker.template.position_offset[3] = data.height or marker.template.position_offset[3]

	return false
end

return template
