local mod = get_mod("RitualZones")

local Definitions =
	mod:io_dofile("RitualZones/scripts/mods/RitualZones/RitualZones_hud_element_definitions")

local HudElementRitualZones = class("HudElementRitualZones", "HudElementBase")

local function is_finite_number(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function format_distance(distance)
	if not is_finite_number(distance) then
		return "--"
	end
	return string.format("%.1fm", distance)
end

function HudElementRitualZones:init(parent, draw_layer, start_scale)
	HudElementRitualZones.super.init(self, parent, draw_layer, start_scale, Definitions)
end

function HudElementRitualZones:update(dt, t, ui_renderer, render_settings, input_service)
	HudElementRitualZones.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	if not mod:get("hud_enabled") then
		return
	end

	local widget = self._widgets_by_name.ritualzones_hud
	if not widget then
		return
	end

	local data = mod._hud_data
	if not data then
		widget.content.hud_text = ""
		return
	end

	local lines = {}
	local show_all = mod:get("hud_show_all")
	local show_self = mod:get("hud_show_self")
	local show_max = mod:get("hud_show_max")
	local show_leader = mod:get("hud_show_leader")
	local show_leader_name = mod:get("hud_show_leader_name")
	local hud_x = tonumber(mod:get("hud_pos_x")) or 20
	local hud_y = tonumber(mod:get("hud_pos_y")) or 240
	local hud_width = math.max(60, tonumber(mod:get("hud_width")) or 420)
	local hud_height = math.max(40, tonumber(mod:get("hud_height")) or 220)
	local hud_font_size = math.max(10, tonumber(mod:get("hud_font_size")) or 18)
	local hud_bg_opacity = tonumber(mod:get("hud_bg_opacity"))
	if hud_bg_opacity == nil then
		hud_bg_opacity = 140
	end
	hud_bg_opacity = math.max(0, math.min(255, math.floor(hud_bg_opacity + 0.5)))
	local padding = 8

	local background = widget.style.background
	if background then
		background.offset[1] = hud_x
		background.offset[2] = hud_y
		background.size[1] = hud_width
		background.size[2] = hud_height
		background.color[1] = hud_bg_opacity
	end

	local text_style = widget.style.hud_text
	text_style.font_size = hud_font_size
	text_style.offset[1] = hud_x + padding
	text_style.offset[2] = hud_y + padding
	text_style.size[1] = math.max(10, hud_width - padding * 2)
	text_style.size[2] = math.max(10, hud_height - padding * 2)

	if show_self and not show_all then
		local self_entry = data.self
		if self_entry and self_entry.distance then
			lines[#lines + 1] = string.format("You: %s", format_distance(self_entry.distance))
		end
	end

	if show_leader then
		local label = "Leader"
		if show_leader_name and data.leader_name and data.leader_name ~= "" then
			label = string.format("Leader (%s)", data.leader_name)
		end
		lines[#lines + 1] = string.format("%s: %s", label, format_distance(data.leader_distance))
	end

	if show_max then
		lines[#lines + 1] = string.format("Max: %s", format_distance(data.max_progress_distance))
	end

	if show_all then
		local entries = data.entries or {}
		for i = 1, #entries do
			local entry = entries[i]
			if entry and entry.distance then
				local name = entry.name or string.format("Player %d", i)
				if entry.is_local then
					name = "You"
				end
				if show_leader_name and entry.is_leader then
					name = name .. " (Leader)"
				end
				lines[#lines + 1] = string.format("%s: %s", name, format_distance(entry.distance))
			end
		end
	end

	widget.content.hud_text = table.concat(lines, "\n")
end

function HudElementRitualZones:draw(dt, t, ui_renderer, render_settings, input_service)
	if not mod:get("hud_enabled") then
		return
	end
	if not mod._hud_data then
		return
	end
	HudElementRitualZones.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
end

return HudElementRitualZones
