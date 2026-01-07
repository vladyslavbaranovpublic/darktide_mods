--[[
	File: SlowMode.lua
	Description: Gameplay speed controller with hotkeys, presets, and HUD timer support.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	Last Updated: 2026-01-05
	Author: LAUREHTE
]]
local mod = get_mod("SlowMode")

local HUD_TIMER_CLASS = "HudElementSlowModeTimer"
local HUD_TIMER_FILE = "SlowMode/scripts/mods/SlowMode/hud_element_slowmode_timer"

local SETTINGS = {
	speed_percent = "slowmode_speed_percent",
	preset_1_percent = "slowmode_preset_1_percent",
	preset_2_percent = "slowmode_preset_2_percent",
	preset_3_percent = "slowmode_preset_3_percent",
}

local STEP_PERCENT = 10
local MIN_PERCENT = 0
local MAX_PERCENT = 300
local DEFAULT_PERCENT = 100

mod:register_hud_element({
	class_name = HUD_TIMER_CLASS,
	filename = HUD_TIMER_FILE,
	use_hud_scale = true,
	visibility_groups = {
		"alive",
	},
})

mod._scale_percent = DEFAULT_PERCENT
mod:set(SETTINGS.speed_percent, DEFAULT_PERCENT, false)

local function clamp(value, min_value, max_value)
	if value < min_value then
		return min_value
	end
	if value > max_value then
		return max_value
	end
	return value
end

local function scale_from_percent(percent)
	if percent <= 0 then
		return 0
	end
	return percent / 100
end

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

local function current_game_mode_name()
	local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
	if not game_mode_manager or not game_mode_manager.game_mode_name then
		return nil
	end

	return game_mode_manager:game_mode_name()
end

local function is_allowed_context()
	local game_mode_name = current_game_mode_name()
	if not game_mode_name then
		return false
	end

	if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
		return false
	end

	return true
end

local function apply_gameplay_scale(percent)
	local time_manager = Managers and Managers.time
	if not time_manager or not time_manager.has_timer or not time_manager:has_timer("gameplay") then
		return false
	end

	time_manager:set_local_scale("gameplay", scale_from_percent(percent))
	return true
end

local function reset_to_default(apply_scale)
	mod._scale_percent = DEFAULT_PERCENT
	mod:set(SETTINGS.speed_percent, DEFAULT_PERCENT, false)

	if apply_scale then
		apply_gameplay_scale(DEFAULT_PERCENT)
	end
end

local function snap_up(value, step)
	if value % step == 0 then
		return value + step
	end

	return math.ceil(value / step) * step
end

local function snap_down(value, step)
	if value % step == 0 then
		return value - step
	end

	return math.floor(value / step) * step
end

function mod:_set_percent(value, silent)
	if not is_allowed_context() then
		reset_to_default(false)
		if not silent then
			mod:echo("SlowMode: only available in missions or Psykanium.")
		end
		return
	end

	local percent = clamp(value, MIN_PERCENT, MAX_PERCENT)
	mod._scale_percent = percent
	mod:set(SETTINGS.speed_percent, percent, false)

	local applied = apply_gameplay_scale(percent)
	if silent then
		return
	end

	if percent <= 0 then
		mod:echo("SlowMode: 0%%")
	elseif applied then
		mod:echo("SlowMode: %d%%", percent)
	else
		mod:echo("SlowMode: %d%% (applies when gameplay timer is active)", percent)
	end
end

function mod:increase_speed()
	if not is_allowed_context() then
		mod:echo("SlowMode: only available in missions or Psykanium.")
		return
	end

	local current = mod._scale_percent or DEFAULT_PERCENT
	local next_value = snap_up(current, STEP_PERCENT)

	mod:_set_percent(next_value)
end

function mod:decrease_speed()
	if not is_allowed_context() then
		mod:echo("SlowMode: only available in missions or Psykanium.")
		return
	end

	local current = mod._scale_percent or DEFAULT_PERCENT
	local next_value = snap_down(current, STEP_PERCENT)

	mod:_set_percent(next_value)
end

function mod:_apply_preset(setting_id)
	local percent = get_setting_number(setting_id, DEFAULT_PERCENT)
	mod:_set_percent(percent)
end

function mod:apply_preset_1()
	mod:_apply_preset(SETTINGS.preset_1_percent)
end

function mod:apply_preset_2()
	mod:_apply_preset(SETTINGS.preset_2_percent)
end

function mod:apply_preset_3()
	mod:_apply_preset(SETTINGS.preset_3_percent)
end

function mod.on_game_state_changed(status, state_name)
	if status == "enter" then
		local should_apply = state_name == "StateGameplay" and is_allowed_context()
		reset_to_default(should_apply)
	end
end

function mod.on_setting_changed(setting_id)
	if setting_id == SETTINGS.speed_percent then
		mod:_set_percent(mod:get(SETTINGS.speed_percent) or DEFAULT_PERCENT, true)
	end
end

mod:hook("AdaptiveClockHandlerClient", "post_update", function(func, self, main_dt)
	func(self, main_dt)

	if not is_allowed_context() then
		return
	end

	local percent = mod._scale_percent or DEFAULT_PERCENT
	local time_manager = Managers and Managers.time
	if time_manager and time_manager.has_timer and time_manager:has_timer("gameplay") then
		time_manager:set_local_scale("gameplay", scale_from_percent(percent))
	end
end)

return mod
