--[[
	File: RitualZones_timer_marker.lua
	Description: Draws ritual trigger zones and shows ritual timers for havoc daemonhosts.
	Overall Release Version: 1.2.0
	File Version: 1.2.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

local template = {}

template.name = "RitualZones_timer_marker"
template.size = {
	600,
	120,
}
template.unit_node = "ui_marker"
template.max_distance = 200
template.min_distance = 0
template.position_offset = {
	0,
	0,
	2.0,
}
template.check_line_of_sight = false

local DEFAULT_COLOR = { 255, 255, 255 }
local DEFAULT_FONT = "proxima_nova_bold"
local DEFAULT_BG_ALPHA = 160
local BACKGROUND_PADDING = 1.15

local function measure_text(ui_renderer, text, font_type, font_size)
	if not text or text == "" then
		return 0, 0
	end
	if ui_renderer then
		local width, height = UIRenderer.text_size(ui_renderer, text, font_type, font_size)
		if width and height and width > 0 and height > 0 then
			return width, height
		end
	end
	local length = utf8 and utf8.len(text) or #text
	return (font_size * 0.6) * length, font_size
end

local function update_background(widget, ui_renderer, text, font_type, font_size, show_background, alpha)
	if not widget then
		return
	end

	widget.content.show_background = show_background and true or false
	local bg_style = widget.style.background
	if not bg_style then
		return
	end

	if not show_background or not text or text == "" then
		bg_style.size[1] = 0
		bg_style.size[2] = 0
		bg_style.color[1] = 0
		return
	end

	local max_width = 0
	local total_height = 0
	for line in string.gmatch(text, "([^\n]+)") do
		local width, height = measure_text(ui_renderer, line, font_type, font_size)
		if width > max_width then
			max_width = width
		end
		total_height = total_height + height
	end

	if max_width == 0 and total_height == 0 then
		local width, height = measure_text(ui_renderer, text, font_type, font_size)
		max_width = width
		total_height = height
	end

	bg_style.size[1] = math.max(1, max_width * BACKGROUND_PADDING)
	bg_style.size[2] = math.max(1, total_height * BACKGROUND_PADDING)
	bg_style.color[1] = alpha or DEFAULT_BG_ALPHA
end

template.create_widget_defintion = function(self, scenegraph_id)
	return UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "background",
			value_id = "background",
			value = "content/ui/materials/backgrounds/default_square",
			style = {
				vertical_alignment = "center",
				horizontal_alignment = "center",
				color = { DEFAULT_BG_ALPHA, 0, 0, 0 },
				offset = { 0, 0, -1 },
				size = { 0, 0 },
			},
		},
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
	widget.content.show_background = data.show_background and true or false
	template.position_offset[3] = data.height or template.position_offset[3]
end

template.update_function = function(parent, ui_renderer, widget, marker)
	local data = marker.data or {}
	local style = widget.style.label
	local color = data.color or DEFAULT_COLOR

	widget.content.label = data.text or ""
	style.font_size = data.text_size or style.font_size
	style.text_color[2] = color[1] or DEFAULT_COLOR[1]
	style.text_color[3] = color[2] or DEFAULT_COLOR[2]
	style.text_color[4] = color[3] or DEFAULT_COLOR[3]
	marker.template.position_offset[3] = data.height or marker.template.position_offset[3]
	update_background(widget, ui_renderer, widget.content.label, DEFAULT_FONT, style.font_size, data.show_background, data.background_alpha)

	return false
end

return template
