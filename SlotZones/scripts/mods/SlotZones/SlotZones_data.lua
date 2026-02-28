--[[
    File: SlotZones_data.lua
    Description: DMF settings schema and option groups for SlotZones.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local mod = get_mod("SlotZones")

local color_options = {}
if Color and Color.list then
	for _, color_name in ipairs(Color.list) do
		local localized_name = mod:localize(color_name)
		color_options[#color_options + 1] = {
			text = color_name,
			value = color_name,
			localized_text = localized_name,
		}
	end
	table.sort(color_options, function(a, b)
		return a.text < b.text
	end)
end

local function get_color_options()
	if table.clone then
		return table.clone(color_options)
	end
	local clone = {}
	for i = 1, #color_options do
		clone[i] = color_options[i]
	end
	return clone
end

local target_mode_options = {
	{ text = "target_mode_self", value = "self" },
	{ text = "target_mode_party", value = "party" },
	{ text = "target_mode_all", value = "all" },
}

local slot_filter_options = {
	{ text = "slot_filter_all", value = "all" },
	{ text = "slot_filter_active", value = "active" },
	{ text = "slot_filter_occupied", value = "occupied" },
	{ text = "slot_filter_queued", value = "queued" },
	{ text = "slot_filter_free", value = "free" },
}

local debug_text_mode_options = {
	{ text = "debug_text_mode_off", value = "off" },
	{ text = "debug_text_mode_labels", value = "labels" },
	{ text = "debug_text_mode_distances", value = "distances" },
	{ text = "debug_text_mode_both", value = "both" },
}

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "slotzones_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "general_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "target_mode",
						type = "dropdown",
						default_value = "self",
						options = target_mode_options,
					},
					{
						setting_id = "slot_filter",
						type = "dropdown",
						default_value = "all",
						options = slot_filter_options,
					},
					{
						setting_id = "debug_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "debug_draw_distance",
						type = "numeric",
						default_value = 0,
						range = { 0, 200 },
						decimals_number = 1,
					},
					{
						setting_id = "debug_max_targets",
						type = "numeric",
						default_value = 6,
						range = { 1, 20 },
					},
					{
						setting_id = "debug_update_interval",
						type = "numeric",
						default_value = 0.1,
						range = { 0, 3.0 },
						decimals_number = 3,
					},
				},
			},
			{
				setting_id = "slot_geometry_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "draw_origin",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "draw_slots",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "draw_ghost_slots",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "slot_radius_scale",
						type = "numeric",
						default_value = 1.0,
						range = { 0.2, 3.0 },
						decimals_number = 2,
					},
					{
						setting_id = "slot_height",
						type = "numeric",
						default_value = 1.0,
						range = { 0, 4.0 },
						decimals_number = 2,
					},
					{
						setting_id = "slot_segments",
						type = "numeric",
						default_value = 18,
						range = { 8, 48 },
					},
					{
						setting_id = "slot_height_rings",
						type = "numeric",
						default_value = 0,
						range = { 0, 50 },
					},
					{
						setting_id = "slot_vertical_lines",
						type = "numeric",
						default_value = 4,
						range = { 0, 50 },
					},
					{
						setting_id = "occupied_distance_scale",
						type = "numeric",
						default_value = 1.0,
						range = { 0.5, 3.0 },
						decimals_number = 2,
					},
				},
			},
			{
				setting_id = "slot_user_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "draw_user_slot_rings",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "user_slot_radius_scale",
						type = "numeric",
						default_value = 1.1,
						range = { 0.2, 3.0 },
						decimals_number = 2,
					},
					{
						setting_id = "enemy_ring_height",
						type = "numeric",
						default_value = 1.0,
						range = { 0, 4.0 },
						decimals_number = 2,
					},
					{
						setting_id = "draw_slot_user_lines",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "queue_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "draw_queue_positions",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "queue_radius_scale",
						type = "numeric",
						default_value = 1.0,
						range = { 0.2, 2.0 },
						decimals_number = 2,
					},
					{
						setting_id = "queue_slot_height",
						type = "numeric",
						default_value = 0.1,
						range = { 0, 4.0 },
						decimals_number = 2,
					},
					{
						setting_id = "draw_queue_lines",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "queue_line_thickness",
						type = "numeric",
						default_value = 0,
						range = { 0, 0.4 },
						decimals_number = 2,
					},
					{
						setting_id = "max_queue_lines",
						type = "numeric",
						default_value = 30,
						range = { 0, 50 },
					},
					{
						setting_id = "draw_queue_unit_rings",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "queue_unit_radius_scale",
						type = "numeric",
						default_value = 1.0,
						range = { 0.2, 3.0 },
						decimals_number = 2,
					},
					{
						setting_id = "queue_unit_color",
						type = "dropdown",
						default_value = "light_blue",
						options = get_color_options(),
					},
					{
						setting_id = "draw_queue_unit_lines",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "slot_color_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "slot_normal_free_color",
						type = "dropdown",
						default_value = "lime",
						options = get_color_options(),
					},
					{
						setting_id = "slot_normal_occupied_color",
						type = "dropdown",
						default_value = "orange",
						options = get_color_options(),
					},
					{
						setting_id = "slot_normal_moving_color",
						type = "dropdown",
						default_value = "yellow",
						options = get_color_options(),
					},
					{
						setting_id = "slot_medium_free_color",
						type = "dropdown",
						default_value = "steel_blue",
						options = get_color_options(),
					},
					{
						setting_id = "slot_medium_occupied_color",
						type = "dropdown",
						default_value = "deep_pink",
						options = get_color_options(),
					},
					{
						setting_id = "slot_medium_moving_color",
						type = "dropdown",
						default_value = "medium_purple",
						options = get_color_options(),
					},
					{
						setting_id = "slot_large_free_color",
						type = "dropdown",
						default_value = "khaki",
						options = get_color_options(),
					},
					{
						setting_id = "slot_large_occupied_color",
						type = "dropdown",
						default_value = "red",
						options = get_color_options(),
					},
					{
						setting_id = "slot_large_moving_color",
						type = "dropdown",
						default_value = "tomato",
						options = get_color_options(),
					},
				},
			},
			{
				setting_id = "label_core_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_text_enabled",
						type = "dropdown",
						default_value = "labels",
						options = debug_text_mode_options,
					},
					{
						setting_id = "debug_text_background",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "debug_text_size",
						type = "numeric",
						default_value = 0.17,
						range = { 0.1, 0.6 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_text_height",
						type = "numeric",
						default_value = 1.5,
						range = { 0.4, 4.0 },
						decimals_number = 2,
					},
					{
						setting_id = "draw_label_lines",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_line_thickness",
						type = "numeric",
						default_value = 0.02,
						range = { 0, 0.4 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_label_draw_distance",
						type = "numeric",
						default_value = 0,
						range = { 0, 200 },
						decimals_number = 1,
					},
					{
						setting_id = "debug_label_refresh_interval",
						type = "numeric",
						default_value = 0.1,
						range = { 0, 3.0 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_label_move_threshold",
						type = "numeric",
						default_value = 0.20,
						range = { 0, 5.0 },
						decimals_number = 2,
					},
					{
						setting_id = "debug_label_marker_cap",
						type = "numeric",
						default_value = 35,
						range = { 0, 200 },
					},
				},
			},
			{
				setting_id = "label_slot_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "label_slots_normal",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_slot_normal_size",
						type = "numeric",
						default_value = 0,
						range = { 0, 0.8 },
						decimals_number = 2,
					},
					{
						setting_id = "label_slot_normal_height",
						type = "numeric",
						default_value = 0,
						range = { 0, 6.0 },
						decimals_number = 2,
					},
					{
						setting_id = "label_slots_medium",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_slot_medium_size",
						type = "numeric",
						default_value = 0,
						range = { 0, 0.8 },
						decimals_number = 2,
					},
					{
						setting_id = "label_slot_medium_height",
						type = "numeric",
						default_value = 0,
						range = { 0, 6.0 },
						decimals_number = 2,
					},
					{
						setting_id = "label_slots_large",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_slot_large_size",
						type = "numeric",
						default_value = 0,
						range = { 0, 0.8 },
						decimals_number = 2,
					},
					{
						setting_id = "label_slot_large_height",
						type = "numeric",
						default_value = 0,
						range = { 0, 6.0 },
						decimals_number = 2,
					},
					{
						setting_id = "label_show_user",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_show_queue",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_show_target",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "label_entity_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "label_slot_users",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "label_enemy_units",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "queue_label_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "queue_label_size",
						type = "numeric",
						default_value = 0.2,
						range = { 0.1, 0.6 },
						decimals_number = 2,
					},
					{
						setting_id = "queue_label_height",
						type = "numeric",
						default_value = 3.0,
						range = { 0, 4.0 },
						decimals_number = 2,
					},
					{
						setting_id = "queue_label_color",
						type = "dropdown",
						default_value = "light_blue",
						options = get_color_options(),
					},
				},
			},
		},
	},
}
