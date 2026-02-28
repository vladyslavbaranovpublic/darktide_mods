--[[
    File: SlotZones_localization.lua
    Description: English localization strings and dynamic color option labels.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local InputUtils = require("scripts/managers/input/input_utils")

local function readable(text)
	local tokens = string.split(text, "_")
	for i, token in ipairs(tokens) do
		tokens[i] = string.upper(string.sub(token, 1, 1)) .. string.sub(token, 2)
	end
	return table.concat(tokens, " ")
end

local function add_color_localizations(localizations)
	if not Color or not Color.list or not InputUtils then
		return
	end
	for _, color_name in ipairs(Color.list) do
		local ok, color_values = pcall(Color[color_name], 255, true)
		if ok and color_values then
			local text = InputUtils.apply_color_to_input_text(readable(color_name), color_values)
			localizations[color_name] = { en = text }
		end
	end
end

local localizations = {
	mod_name = {
		en = "{#color(230,70,70)}\xEE\x84\x94 Slot Zones \xEE\x84\x94{#reset()}",
	},
	mod_description = {
        en = "{#color(230,70,70)}Release 1.0.0{#reset()} | Author: LAUREHTE\n{#color(230,70,70)}Visualize the slot system around targets with debug lines and labels.{#reset()}",
    },
	slotzones_enabled = {
		en = "Enable Slot Zones",
	},
	target_mode = {
		en = "Target mode",
	},
	target_mode_self = {
		en = "Self only",
	},
	target_mode_party = {
		en = "Party",
	},
	target_mode_all = {
		en = "All slot targets",
	},
	slot_filter = {
		en = "Slot filter",
	},
	slot_filter_all = {
		en = "All slots",
	},
	slot_filter_active = {
		en = "Active (occupied, assigned, or queued)",
	},
	slot_filter_occupied = {
		en = "Occupied only",
	},
	slot_filter_queued = {
		en = "Queued only",
	},
	slot_filter_free = {
		en = "Free only",
	},
	general_group = {
		en = "General and performance",
	},
	slot_geometry_group = {
		en = "Slot geometry",
	},
	slot_user_group = {
		en = "Slot-user and enemy visuals",
	},
	debug_enabled = {
		en = "Enable debug visuals",
	},
	draw_origin = {
		en = "Draw target origin",
	},
	draw_slots = {
		en = "Draw slot cylinders",
	},
	slot_radius_scale = {
		en = "Slot radius scale",
	},
	slot_height = {
		en = "Slot cylinder height",
	},
	enemy_ring_height = {
		en = "Enemy ring height",
	},
	slot_segments = {
		en = "Slot circle segments",
	},
	slot_height_rings = {
		en = "Slot height rings (0 = auto)",
	},
	slot_vertical_lines = {
		en = "Slot vertical lines",
	},
	draw_slot_user_lines = {
		en = "Draw slot-user connection lines",
	},
	draw_ghost_slots = {
		en = "Draw ghost slots",
	},
	draw_user_slot_rings = {
		en = "Draw rings under slot users",
	},
	user_slot_radius_scale = {
		en = "User ring radius scale",
	},
	occupied_distance_scale = {
		en = "Occupied distance scale",
	},
	slot_color_group = {
		en = "Slot colors",
	},
	slot_normal_free_color = {
		en = "Normal free color",
	},
	slot_normal_occupied_color = {
		en = "Normal occupied color",
	},
	slot_normal_moving_color = {
		en = "Normal moving color",
	},
	slot_medium_free_color = {
		en = "Medium free color",
	},
	slot_medium_occupied_color = {
		en = "Medium occupied color",
	},
	slot_medium_moving_color = {
		en = "Medium moving color",
	},
	slot_large_free_color = {
		en = "Large free color",
	},
	slot_large_occupied_color = {
		en = "Large occupied color",
	},
	slot_large_moving_color = {
		en = "Large moving color",
	},
	queue_group = {
		en = "Queue visuals",
	},
	draw_queue_positions = {
		en = "Draw queue slot rings",
	},
	draw_queue_lines = {
		en = "Draw queue slot to unit lines",
	},
	draw_queue_unit_rings = {
		en = "Draw queue unit rings",
	},
	draw_queue_unit_lines = {
		en = "Draw queue unit to slot lines",
	},
	queue_unit_radius_scale = {
		en = "Queue unit ring radius scale",
	},
	queue_unit_color = {
		en = "Queue unit ring color",
	},
	queue_radius_scale = {
		en = "Queue radius scale",
	},
	queue_slot_height = {
		en = "Queue slot ring height",
	},
	queue_line_thickness = {
		en = "Queue line thickness",
	},
	max_queue_lines = {
		en = "Max queue units per slot (0 = all)",
	},
	label_core_group = {
		en = "Label core",
	},
	label_slot_group = {
		en = "Slot labels",
	},
	label_entity_group = {
		en = "User and enemy labels",
	},
	debug_text_enabled = {
		en = "Debug text mode",
	},
	debug_text_mode_off = {
		en = "Off",
	},
	debug_text_mode_labels = {
		en = "Labels",
	},
	debug_text_mode_distances = {
		en = "Distances",
	},
	debug_text_mode_both = {
		en = "Labels + distances",
	},
	debug_text_background = {
		en = "Label background",
	},
	debug_text_size = {
		en = "Label size",
	},
	debug_text_height = {
		en = "Label height",
	},
	draw_label_lines = {
		en = "Draw label connector lines",
	},
	label_line_thickness = {
		en = "Label line thickness",
	},
	debug_label_draw_distance = {
		en = "Label draw distance (m)",
	},
	debug_label_refresh_interval = {
		en = "Label refresh interval (sec)",
	},
	debug_label_marker_cap = {
		en = "Label cap",
	},
	debug_label_move_threshold = {
		en = "Label refresh move threshold (m)",
	},
	label_slots_normal = {
		en = "Label normal slots",
	},
	label_slot_normal_size = {
		en = "Normal slot label size (0 = default)",
	},
	label_slot_normal_height = {
		en = "Normal slot label height (0 = default)",
	},
	label_slots_medium = {
		en = "Label medium slots",
	},
	label_slot_medium_size = {
		en = "Medium slot label size (0 = default)",
	},
	label_slot_medium_height = {
		en = "Medium slot label height (0 = default)",
	},
	label_slots_large = {
		en = "Label large slots",
	},
	label_slot_large_size = {
		en = "Large slot label size (0 = default)",
	},
	label_slot_large_height = {
		en = "Large slot label height (0 = default)",
	},
	label_show_queue = {
		en = "Label queue info",
	},
	label_show_user = {
		en = "Label occupant name",
	},
	label_slot_users = {
		en = "Label assigned slot users",
	},
	label_enemy_units = {
		en = "Label enemy units (fallback)",
	},
	label_show_target = {
		en = "Label target units",
	},
	queue_label_enabled = {
		en = "Label queue units",
	},
	queue_label_size = {
		en = "Queue label size",
	},
	queue_label_height = {
		en = "Queue label height",
	},
	queue_label_color = {
		en = "Queue label color",
	},
	debug_draw_distance = {
		en = "Debug draw distance (m)",
	},
	debug_update_interval = {
		en = "Smoothing interval (sec)",
	},
	debug_max_targets = {
		en = "Max targets",
	},
}

add_color_localizations(localizations)

return localizations
