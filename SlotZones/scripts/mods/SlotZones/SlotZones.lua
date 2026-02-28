--[[
    File: SlotZones.lua
    Description: SlotZones mod entry point and lifecycle wiring.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]
local mod = get_mod("SlotZones")

local constants = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/constants")
local runtime = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/runtime")
local Util = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/util")
local Settings = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/settings")
local LineDraw = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/line_draw")
local SlotLogic = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/slot_logic")
local SlotDraw = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/slot_draw")
local SlotDrawUsers = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/slot_draw_users")
local LabelFallback = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/label_fallback")
local Markers = mod:io_dofile("SlotZones/scripts/mods/SlotZones/core/markers")
local SlotZonesDebugLabelMarker = mod:io_dofile("SlotZones/scripts/mods/SlotZones/SlotZones_debug_label_marker")

local util = Util.new(runtime)
local settings = Settings.new(mod, constants, runtime)
local line_draw = LineDraw.new(runtime)
local slot_logic = SlotLogic.new(constants, util)
local markers = Markers.new(mod, SlotZonesDebugLabelMarker)
local label_fallback = LabelFallback.new(runtime)
local slot_draw = SlotDraw.new(mod, constants, util, line_draw, slot_logic, markers, SlotDrawUsers, label_fallback)

markers:register_hooks()

local cleanup_done = false
local last_world = nil
local pending_label_boost = nil
local draw_error_backoff_until = nil
local draw_error_logged = false

local function cleanup_debug()
	slot_draw:reset_state()
	cleanup_done = true
	last_world = nil
	pending_label_boost = nil
	draw_error_backoff_until = nil
	draw_error_logged = false
end

mod.on_setting_changed = function(_)
	settings:clear_cache()
	slot_draw:reset_refresh()
	markers:clear()
end

mod.on_enabled = function()
	settings:clear_cache()
	slot_draw:reset_refresh()
	markers:clear()
	markers:register_hooks()
end

mod.on_disabled = function()
	cleanup_debug()
end

mod.on_unload = function()
	cleanup_debug()
end

mod.on_reload = function()
	cleanup_debug()
	settings:clear_cache()
	slot_draw:reset_refresh()
	markers:clear()
	markers:register_hooks()
end

mod.update = function(dt, t)
	markers:register_hooks()
	markers:flush_pending()
	if not mod:is_enabled() or settings:get_bool("slotzones_enabled", true) == false then
		if not cleanup_done then
			cleanup_debug()
		end
		return
	end
	if not util:is_gameplay_state() then
		if not cleanup_done then
			cleanup_debug()
		end
		return
	end
	cleanup_done = false

	local world = util:get_level_world()
	if not world then
		return
	end
	if world ~= last_world then
		last_world = world
		slot_draw:reset_state()
		settings:clear_cache()
		pending_label_boost = (util:get_time_value(t) or 0) + 2.0
		slot_draw:force_label_refresh(2.0, util:get_time_value(t))
	end
	local now_t = util:get_time_value(t)
	if pending_label_boost and now_t and now_t >= pending_label_boost then
		pending_label_boost = nil
		slot_draw:force_label_refresh(1.0, now_t)
	end

	local time_value = now_t
	local current = settings:build()
	if draw_error_backoff_until and time_value < draw_error_backoff_until then
		line_draw:clear(world)
		markers:clear()
		return
	end

	if not current.debug_enabled and (current.text_mode == nil or current.text_mode == "off") then
		line_draw:clear(world)
		markers:clear()
		return
	end

	local ok_draw, draw_error = pcall(slot_draw.draw_debug, slot_draw, world, dt, time_value, current)
	if not ok_draw then
		line_draw:clear(world)
		markers:clear()
		draw_error_backoff_until = time_value + 1
		if not draw_error_logged then
			draw_error_logged = true
			mod:echo(string.format("[SlotZones] draw guard caught error: %s", tostring(draw_error)))
		end
		return
	end
	draw_error_logged = false
	draw_error_backoff_until = nil
end
