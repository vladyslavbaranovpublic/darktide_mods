--[[
	File: RitualZones_debug_label_marker.lua
	Description: Debug label marker used for through-wall text.
	Overall Release Version: 1.2.0
	File Version: 1.2.0
	Last Updated: 2026-01-07
	Author: LAUREHTE
]]
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIFonts = require("scripts/managers/ui/ui_fonts")

local template = {}

template.name = "RitualZones_debug_label_marker"
template.size = {
	300,
	60,
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
	local scaled = math.floor(size * 200 + 0.5)
	if scaled < 14 then
		scaled = 14
	elseif scaled > 72 then
		scaled = 72
	end
	return scaled
end

local DEFAULT_COLOR = { 255, 255, 255 }
local DEFAULT_FONT = "proxima_nova_bold"
local DEFAULT_BG_ALPHA = 160
local BACKGROUND_PADDING = 1.15
local DISTANCE_SCALE_MIN = 0.05
local DISTANCE_SCALE_MAX = 0.5
local DISTANCE_SCALE_RANGE = 300

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
		if widget.content then
			widget.content._rz_bg_cache = nil
		end
		return
	end

	local width, height = nil, nil
	local clean_text = (text or ""):gsub("{#.-}", "")
	local max_width = nil
	if widget and widget.style and widget.style.label and widget.style.label.size then
		max_width = widget.style.label.size[1]
	end
	local cache_key = table.concat({
		text or "",
		font_type or "",
		tostring(font_size or ""),
		tostring(alpha or ""),
		tostring(max_width or ""),
	}, "|")
	local cache = widget.content and widget.content._rz_bg_cache
	if cache and cache.key == cache_key and cache.width and cache.height then
		bg_style.size[1] = cache.width
		bg_style.size[2] = cache.height
		bg_style.color[1] = alpha or DEFAULT_BG_ALPHA
		return
	end
	if ui_renderer and widget and widget.style and widget.style.label then
		local text_options = UIFonts.get_font_options_by_style(widget.style.label)
		local width, height =
			UIRenderer.text_size(ui_renderer, clean_text, font_type, font_size, widget.style.label.size, text_options)
		if width and height and width > 0 and height > 0 then
			bg_style.size[1] = math.max(1, width * BACKGROUND_PADDING)
			bg_style.size[2] = math.max(1, height * BACKGROUND_PADDING)
			bg_style.color[1] = alpha or DEFAULT_BG_ALPHA
			if widget.content then
				widget.content._rz_bg_cache = {
					key = cache_key,
					width = bg_style.size[1],
					height = bg_style.size[2],
				}
			end
			return
		end
	end
	if text and text ~= "" then
		local line_count = 0
		local max_line_width = 0
		local line_height = font_size
		for line in string.gmatch(text, "([^\n]+)") do
			local clean_line = line:gsub("{#.-}", "")
			line_count = line_count + 1
			local line_width, line_h = nil, nil
			if ui_renderer then
				line_width, line_h = UIRenderer.text_size(ui_renderer, line, font_type, font_size)
			end
			if not line_width or line_width <= 0 then
				local length = utf8 and utf8.len(clean_line) or #clean_line
				line_width = (font_size * 0.6) * length
			end
			if line_h and line_h > line_height then
				line_height = line_h
			end
			if line_width > max_line_width then
				max_line_width = line_width
			end
		end
		if line_count == 0 then
			line_count = 1
			local length = utf8 and utf8.len(clean_text) or #clean_text
			max_line_width = (font_size * 0.6) * length
		end
		if max_width and max_line_width > max_width then
			local wrap_lines = math.max(1, math.ceil(max_line_width / max_width))
			line_count = line_count * wrap_lines
			width = max_width
		else
			width = max_line_width
		end
		height = line_height * line_count
	end
	if max_width and width and width > max_width then
		width = max_width
	end
	if not width or not height or width <= 0 or height <= 0 then
		local length = utf8 and utf8.len(clean_text) or #clean_text
		width = (font_size * 0.6) * length
		height = font_size
	end

	bg_style.size[1] = math.max(1, width * BACKGROUND_PADDING)
	bg_style.size[2] = math.max(1, height * BACKGROUND_PADDING)
	bg_style.color[1] = alpha or DEFAULT_BG_ALPHA
	if widget.content then
		widget.content._rz_bg_cache = {
			key = cache_key,
			width = bg_style.size[1],
			height = bg_style.size[2],
		}
	end
end

local function apply_distance_scale(base_size, distance, min_scale, max_scale, range)
	local scale_min = tonumber(min_scale) or DISTANCE_SCALE_MIN
	local scale_max = tonumber(max_scale) or DISTANCE_SCALE_MAX
	local scale_range = tonumber(range) or DISTANCE_SCALE_RANGE
	if scale_min < 0.05 then
		scale_min = 0.05
	end
	if scale_max < scale_min then
		scale_max = scale_min
	end
	if scale_range < 10 then
		scale_range = 10
	end
	local dist = distance or 0
	if dist < 0 then
		dist = 0
	end
	local t = math.min(dist / scale_range, 1)
	local scale = scale_max + (scale_min - scale_max) * t
	return math.max(8, math.floor(base_size * scale + 0.5))
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
	widget.style.label.font_size = resolve_font_size(data.text_size)
	template.position_offset[3] = data.height or template.position_offset[3]
end

template.update_function = function(parent, ui_renderer, widget, marker, template_instance, dt, t)
	local data = marker.data or {}
	local style = widget.style.label
	local color = data.color or DEFAULT_COLOR
	local bg_style = widget.style.background
	local base_font_size = resolve_font_size(data.text_size or style.font_size)
	local distance = widget.content and widget.content.distance
	local scaled_font_size =
		apply_distance_scale(base_font_size, distance, data.distance_scale_min, data.distance_scale_max, data.distance_scale_range)

	widget.content.label = data.text or ""
	style.font_size = scaled_font_size
	style.text_color[2] = color[1] or DEFAULT_COLOR[1]
	style.text_color[3] = color[2] or DEFAULT_COLOR[2]
	style.text_color[4] = color[3] or DEFAULT_COLOR[3]
	local alpha = data.background_alpha or DEFAULT_BG_ALPHA
	if bg_style then
		bg_style.color[1] = alpha
		bg_style.color[2] = 0
		bg_style.color[3] = 0
		bg_style.color[4] = 0
	end
	update_background(widget, ui_renderer, widget.content.label, style.font_type, style.font_size, data.show_background, alpha)
	if marker and marker.template then
		marker.template.check_line_of_sight = data.check_line_of_sight and true or false
	end
	marker.template.position_offset[3] = data.height or marker.template.position_offset[3]

	return false
end

return template
