--[[
	File: hud_element_slowmode_timer.lua
	Description: HUD element for displaying the slow-mode-aware gameplay timer.
	Overall Release Version: 1.1.0
	File Version: 1.0.0
	Last Updated: 2026-01-05
	Author: LAUREHTE
]]
local mod = get_mod("SlowMode")
local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")

local HOST_TYPES = MatchmakingConstants.HOST_TYPES

local Definitions = mod:io_dofile("SlowMode/scripts/mods/SlowMode/hud_element_slowmode_timer_definitions")

local HudElementSlowModeTimer = class("HudElementSlowModeTimer", "HudElementBase")

local SETTINGS = {
	enabled = "slowmode_enabled",
	show_timer = "slowmode_show_timer",
	timer_x = "slowmode_timer_x",
	timer_y = "slowmode_timer_y",
	timer_font_size = "slowmode_timer_font_size",
}

local DEFAULT_TIMER_X = 20
local DEFAULT_TIMER_Y = 20
local DEFAULT_FONT_SIZE = 20
local TIMER_HEIGHT_PADDING = 20

local function get_setting_number(setting_id, fallback)
	local value = mod:get(setting_id)
	if value == nil then
		return fallback
	end

	local parsed = tonumber(value)
	if not parsed then
		return fallback
	end

	return parsed
end

local function is_mod_active()
	if mod.is_enabled and not mod:is_enabled() then
		return false
	end

	if mod:get(SETTINGS.enabled) == false then
		return false
	end

	return true
end

local function current_host_type()
	local connection = Managers and Managers.connection
	if connection and connection.host_type then
		return connection:host_type()
	end

	local multiplayer_session = Managers and Managers.multiplayer_session
	if multiplayer_session and multiplayer_session.host_type then
		return multiplayer_session:host_type()
	end

	return nil
end

local function is_training_grounds_mode(game_mode_name)
	return game_mode_name == "training_grounds" or game_mode_name == "shooting_range"
end

local function is_offline_allowed(game_mode_name)
	local host_type = current_host_type()
	if not host_type then
		return false
	end

	if host_type == HOST_TYPES.singleplay then
		return true
	end

	if host_type == HOST_TYPES.singleplay_backend_session then
		return is_training_grounds_mode(game_mode_name)
	end

	return false
end

local function is_timer_allowed()
	if not is_mod_active() then
		return false
	end

	if not mod:get(SETTINGS.show_timer) then
		return false
	end

	local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
	if not game_mode_manager or not game_mode_manager.game_mode_name then
		return false
	end

	local game_mode_name = game_mode_manager:game_mode_name()
	if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
		return false
	end

	return is_offline_allowed(game_mode_name)
end

function HudElementSlowModeTimer:init(parent, draw_layer, start_scale)
	HudElementSlowModeTimer.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._last_x = nil
	self._last_y = nil
	self._last_font_size = nil
end

function HudElementSlowModeTimer:update(dt, t, ui_renderer, render_settings, input_service)
	HudElementSlowModeTimer.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	if not is_timer_allowed() then
		return
	end

	local time_manager = Managers and Managers.time
	if not time_manager or not time_manager.has_timer or not time_manager:has_timer("gameplay") then
		return
	end

	local widget = self._widgets_by_name.timer
	if not widget then
		return
	end

	local current_time = time_manager:time("gameplay") or 0
	widget.content.timer_text = string.format("Time: %.3fs", current_time)

	local font_size = get_setting_number(SETTINGS.timer_font_size, DEFAULT_FONT_SIZE)
	if font_size ~= self._last_font_size then
		widget.style.timer_text.font_size = font_size
		self:_set_scenegraph_size("timer", nil, font_size + TIMER_HEIGHT_PADDING)
		self._last_font_size = font_size
	end

	local x = get_setting_number(SETTINGS.timer_x, DEFAULT_TIMER_X)
	local y = get_setting_number(SETTINGS.timer_y, DEFAULT_TIMER_Y)
	if x ~= self._last_x or y ~= self._last_y then
		self:set_scenegraph_position("timer", x, y)
		self._last_x = x
		self._last_y = y
	end
end

function HudElementSlowModeTimer:draw(dt, t, ui_renderer, render_settings, input_service)
	if not is_timer_allowed() then
		return
	end

	HudElementSlowModeTimer.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
end

return HudElementSlowModeTimer
