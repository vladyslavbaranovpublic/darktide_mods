--[[
    File: settings.lua
    Description: Settings loading, normalization, and cached build state.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Settings = {}
Settings.__index = Settings

function Settings.new(mod, constants, runtime)
	return setmetatable({
		mod = mod,
		constants = constants,
		runtime = runtime,
		cache = {},
		_built = nil,
		_dirty = true,
	}, Settings)
end

function Settings:get(setting_id)
	local value = self.cache[setting_id]
	if value == nil then
		value = self.mod:get(setting_id)
		if value ~= nil then
			self.cache[setting_id] = value
		end
	end
	return value
end

function Settings:get_bool(setting_id, default_value)
	local value = self:get(setting_id)
	if value == nil then
		return default_value == true
	end
	if value == true or value == 1 or value == "1" or value == "true" or value == "on" then
		return true
	end
	if value == false or value == 0 or value == "0" or value == "false" or value == "off" then
		return false
	end
	if type(value) == "string" then
		local normalized = string.lower(value)
		if normalized == "true" or normalized == "on" or normalized == "enabled" or normalized == "yes" then
			return true
		end
		if normalized == "false" or normalized == "off" or normalized == "disabled" or normalized == "no" then
			return false
		end
	end
	return default_value == true
end

function Settings:clear_cache()
	for key in pairs(self.cache) do
		self.cache[key] = nil
	end
	self._dirty = true
end

function Settings:resolve_color_setting(setting_id, fallback)
	local refs = self.runtime.resolve()
	local fallback_color = {
		tonumber(fallback and fallback[1]) or 255,
		tonumber(fallback and fallback[2]) or 255,
		tonumber(fallback and fallback[3]) or 255,
	}
	local color_name = self.mod:get(setting_id)
	if type(color_name) ~= "string" or not refs.Color or not refs.Color[color_name] then
		return fallback_color
	end
	local ok, values = pcall(refs.Color[color_name], 255, true)
	if not ok or not values then
		return fallback_color
	end
	return {
		tonumber(values[2]) or fallback_color[1],
		tonumber(values[3]) or fallback_color[2],
		tonumber(values[4]) or fallback_color[3],
	}
end

function Settings:build()
	if not self._dirty and self._built then
		return self._built
	end
	local defaults = self.constants.DEFAULT_SLOT_COLORS
	local legacy_label_user_units = self:get_bool("label_user_units", true)
	local settings = {
		debug_enabled = self:get_bool("debug_enabled", true),
		draw_origin = self:get_bool("draw_origin", true),
		draw_slots = self:get_bool("draw_slots", true),
		draw_slot_user_lines = self:get_bool("draw_slot_user_lines", true),
		draw_ghost_slots = self:get_bool("draw_ghost_slots", true),
		draw_user_slot_rings = self:get_bool("draw_user_slot_rings", true),
		user_slot_radius_scale = tonumber(self:get("user_slot_radius_scale")) or 1.1,
		occupied_distance_scale = tonumber(self:get("occupied_distance_scale")) or 1.0,
		draw_queue_positions = self:get_bool("draw_queue_positions", true),
		draw_queue_lines = self:get_bool("draw_queue_lines", true),
		slot_radius_scale = tonumber(self:get("slot_radius_scale")) or 1.0,
		slot_height = tonumber(self:get("slot_height")) or 1.0,
		enemy_ring_height = tonumber(self:get("enemy_ring_height")) or 1.0,
		slot_height_rings = math.floor(tonumber(self:get("slot_height_rings")) or 0),
		slot_segments = tonumber(self:get("slot_segments")) or 18,
		slot_vertical_lines = math.floor(tonumber(self:get("slot_vertical_lines")) or 4),
		queue_radius_scale = tonumber(self:get("queue_radius_scale")) or 0.5,
		queue_slot_height = tonumber(self:get("queue_slot_height")) or 0,
		queue_line_thickness = tonumber(self:get("queue_line_thickness")) or 0,
		max_queue_lines = math.floor(tonumber(self:get("max_queue_lines")) or 0),
		draw_queue_unit_rings = self:get_bool("draw_queue_unit_rings", true),
		draw_queue_unit_lines = self:get_bool("draw_queue_unit_lines", true),
		queue_unit_radius_scale = tonumber(self:get("queue_unit_radius_scale")) or 0.9,
		queue_unit_color = self:resolve_color_setting("queue_unit_color", self.constants.COLORS.queue),
		queue_label_enabled = self:get_bool("queue_label_enabled", true),
		queue_label_size = tonumber(self:get("queue_label_size")) or 0.2,
		queue_label_height = tonumber(self:get("queue_label_height")) or 1.6,
		queue_label_color = self:resolve_color_setting("queue_label_color", self.constants.COLORS.queue),
		debug_draw_distance = tonumber(self:get("debug_draw_distance")) or 0,
		debug_update_interval = tonumber(self:get("debug_update_interval")) or 0,
		debug_max_targets = math.floor(tonumber(self:get("debug_max_targets")) or 6),
		target_mode = self:get("target_mode") or "self",
		slot_filter = self:get("slot_filter") or "all",
		text_mode = self:get("debug_text_enabled") or "labels",
		text_background = self:get_bool("debug_text_background", true),
		text_size = tonumber(self:get("debug_text_size")) or 0.25,
		text_height = tonumber(self:get("debug_text_height")) or 1.2,
		draw_label_lines = self:get_bool("draw_label_lines", false),
		label_line_thickness = tonumber(self:get("label_line_thickness")) or 0.04,
		label_draw_distance = tonumber(self:get("debug_label_draw_distance")) or 0,
		label_refresh_interval = tonumber(self:get("debug_label_refresh_interval")) or 0.1,
		label_marker_cap = math.floor(tonumber(self:get("debug_label_marker_cap")) or 25),
		label_move_threshold = tonumber(self:get("debug_label_move_threshold")) or 0.25,
		label_slots_normal = self:get_bool("label_slots_normal", true),
		label_slots_medium = self:get_bool("label_slots_medium", true),
		label_slots_large = self:get_bool("label_slots_large", true),
		label_slot_normal_size = tonumber(self:get("label_slot_normal_size")) or 0,
		label_slot_normal_height = tonumber(self:get("label_slot_normal_height")) or 0,
		label_slot_medium_size = tonumber(self:get("label_slot_medium_size")) or 0,
		label_slot_medium_height = tonumber(self:get("label_slot_medium_height")) or 0,
		label_slot_large_size = tonumber(self:get("label_slot_large_size")) or 0,
		label_slot_large_height = tonumber(self:get("label_slot_large_height")) or 0,
		label_show_queue = self:get_bool("label_show_queue", true),
		label_show_user = self:get_bool("label_show_user", true),
		label_slot_users = self:get_bool("label_slot_users", legacy_label_user_units),
		label_enemy_units = self:get_bool("label_enemy_units", legacy_label_user_units),
		label_show_target = self:get_bool("label_show_target", false),
		slot_type_colors = {
			normal = {
				free = self:resolve_color_setting("slot_normal_free_color", defaults.normal.free),
				occupied = self:resolve_color_setting("slot_normal_occupied_color", defaults.normal.occupied),
				moving = self:resolve_color_setting("slot_normal_moving_color", defaults.normal.moving),
			},
			medium = {
				free = self:resolve_color_setting("slot_medium_free_color", defaults.medium.free),
				occupied = self:resolve_color_setting("slot_medium_occupied_color", defaults.medium.occupied),
				moving = self:resolve_color_setting("slot_medium_moving_color", defaults.medium.moving),
			},
			large = {
				free = self:resolve_color_setting("slot_large_free_color", defaults.large.free),
				occupied = self:resolve_color_setting("slot_large_occupied_color", defaults.large.occupied),
				moving = self:resolve_color_setting("slot_large_moving_color", defaults.large.moving),
			},
		},
	}

	if type(settings.text_mode) ~= "string" then
		settings.text_mode = "labels"
	elseif settings.text_mode ~= "off"
		and settings.text_mode ~= "labels"
		and settings.text_mode ~= "distances"
		and settings.text_mode ~= "both" then
		settings.text_mode = "labels"
	end
	if type(settings.target_mode) ~= "string" then
		settings.target_mode = "self"
	end
	if type(settings.slot_filter) ~= "string" then
		settings.slot_filter = "all"
	end
	if settings.text_mode == "off" then
		if settings.label_slots_normal or settings.label_slots_medium or settings.label_slots_large
			or settings.label_slot_users
			or settings.label_enemy_units
			or settings.label_show_queue
			or settings.label_show_target
			or settings.queue_label_enabled then
			settings.text_mode = "labels"
		end
	end
	if settings.slot_radius_scale < 0.05 then
		settings.slot_radius_scale = 0.05
	end
	if settings.queue_radius_scale < 0.05 then
		settings.queue_radius_scale = 0.05
	end
	if settings.queue_unit_radius_scale < 0.05 then
		settings.queue_unit_radius_scale = 0.05
	end
	if settings.queue_label_size < 0.05 then
		settings.queue_label_size = 0.05
	end
	if settings.queue_label_height < 0 then
		settings.queue_label_height = 0
	end
	if settings.label_slot_normal_size < 0 then
		settings.label_slot_normal_size = 0
	elseif settings.label_slot_normal_size > 1 then
		settings.label_slot_normal_size = 1
	end
	if settings.label_slot_normal_height < 0 then
		settings.label_slot_normal_height = 0
	elseif settings.label_slot_normal_height > 8 then
		settings.label_slot_normal_height = 8
	end
	if settings.label_slot_medium_size < 0 then
		settings.label_slot_medium_size = 0
	elseif settings.label_slot_medium_size > 1 then
		settings.label_slot_medium_size = 1
	end
	if settings.label_slot_medium_height < 0 then
		settings.label_slot_medium_height = 0
	elseif settings.label_slot_medium_height > 8 then
		settings.label_slot_medium_height = 8
	end
	if settings.label_slot_large_size < 0 then
		settings.label_slot_large_size = 0
	elseif settings.label_slot_large_size > 1 then
		settings.label_slot_large_size = 1
	end
	if settings.label_slot_large_height < 0 then
		settings.label_slot_large_height = 0
	elseif settings.label_slot_large_height > 8 then
		settings.label_slot_large_height = 8
	end
	if settings.slot_height_rings < 0 then
		settings.slot_height_rings = 0
	elseif settings.slot_height_rings > 50 then
		settings.slot_height_rings = 50
	end
	if settings.slot_vertical_lines < 0 then
		settings.slot_vertical_lines = 0
	elseif settings.slot_vertical_lines > 50 then
		settings.slot_vertical_lines = 50
	end
	if settings.debug_update_interval < 0 then
		settings.debug_update_interval = 0
	elseif settings.debug_update_interval > 3 then
		settings.debug_update_interval = 3
	end
	if settings.label_refresh_interval < 0 then
		settings.label_refresh_interval = 0
	elseif settings.label_refresh_interval > 3 then
		settings.label_refresh_interval = 3
	end
	if settings.text_mode ~= "off" and settings.label_marker_cap <= 0 then
		settings.label_marker_cap = 25
	end
	if settings.user_slot_radius_scale < 0 then
		settings.user_slot_radius_scale = 0
	end
	if settings.enemy_ring_height < 0 then
		settings.enemy_ring_height = 0
	elseif settings.enemy_ring_height > 8 then
		settings.enemy_ring_height = 8
	end
	if settings.queue_slot_height < 0 then
		settings.queue_slot_height = 0
	elseif settings.queue_slot_height > 8 then
		settings.queue_slot_height = 8
	end
	if settings.occupied_distance_scale < 0 then
		settings.occupied_distance_scale = 0
	end

	self._built = settings
	self._dirty = false
	return settings
end

return Settings
