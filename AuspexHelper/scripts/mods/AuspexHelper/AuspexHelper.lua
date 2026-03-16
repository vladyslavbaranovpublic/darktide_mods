--[[
	File: AuspexHelper.lua
	Description: Main entry point for the Auspex Helper mod and module bootstrap.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	File Introduced in: 1.0.0
	Last Updated: 2026-03-14
	Author: LAUREHTE
]]

local mod = get_mod("AuspexHelper")
local MasterItems = require("scripts/backend/master_items")
local PlayerUnitVisualLoadout = require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")
local MinigameSettings = require("scripts/settings/minigame/minigame_settings")
local OutlineSettings = require("scripts/settings/outline/outline_settings")
local ScannerDisplayViewDecodeSymbolsSettings = require("scripts/ui/views/scanner_display_view/scanner_display_view_decode_symbols_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local InputServiceClass = require("scripts/managers/input/input_service")
local OVERLAY_VIEW_NAME = "auspex_helper_overlay_view"
local PREVIEW_VIEW_NAME = "auspex_helper_preview_view"
WORLD_SCAN_VIEW_NAME = "auspex_helper_world_scan_view"
WORLD_SCAN_ICONS_VIEW_NAME = "auspex_helper_world_scan_icons_view"
local STOCK_SCANNER_VIEW_NAME = "scanner_display_view"
local OVERLAY_VIEW_PATH = "AuspexHelper/scripts/mods/AuspexHelper/ui/auspex_practice_view"
local PREVIEW_CLOSE_TIMEOUT = 0.75
local PREVIEW_VIEW_OPEN_RETRY_INTERVAL = 0.25
local PREVIEW_VIEW_OPEN_TIMEOUT = 6
local PRACTICE_ITEM_OPEN_TIMEOUT = 2
local PRACTICE_DEVICE_SLOT = "slot_device"
local PRACTICE_SOUND_WEAPON_TEMPLATE = "communications_hack_device_pocketable"
PREVIEW_DECODE_SYMBOLS_12_TYPE = "decode_symbols_12"
PREVIEW_DECODE_SYMBOLS_12_STAGE_AMOUNT = 12
PREVIEW_DECODE_MAX_GRID_HEIGHT = 920
local EXPEDITION_MINIGAME_TYPE = rawget(MinigameSettings.types, "expedition") or rawget(MinigameSettings.types, "scan") or "scan"
local PRACTICE_ITEM_IDS = {
	"content/items/pocketable/communications_hack_device_pocketable",
}

_is_auspex_helper_pass_through_view = function(view_name)
	return view_name == PREVIEW_VIEW_NAME
		or view_name == WORLD_SCAN_VIEW_NAME
		or view_name == WORLD_SCAN_ICONS_VIEW_NAME
end

local scannable_units = {}
local scanner_world_helper_active = false
local preview_close_requested_at = nil
local preview_reopen_requested = false
local preview_close_view_name = nil
local preview_input_polling = false
local preview_input_simulation_active = false
local preview_input_simulation_service = nil
local practice_session = nil
local practice_scanner_item = nil
local practice_scanner_item_name = nil
local practice_scanner_item_lookup_complete = false
local practice_scanner_item_retry_at = 0
local MINIGAME_ENABLE_SETTINGS = {
	[MinigameSettings.types.decode_symbols] = "enable_decode_minigame",
	[PREVIEW_DECODE_SYMBOLS_12_TYPE] = "enable_decode_minigame",
	[MinigameSettings.types.drill] = "enable_drill_minigame",
	[MinigameSettings.types.frequency] = "enable_frequency_minigame",
	[MinigameSettings.types.balance] = "enable_balance_minigame",
	[EXPEDITION_MINIGAME_TYPE] = "enable_expedition_minigame",
}
local SCANNER_HIDE_SETTING_IDS = {
	HudElementCrosshair = "scanner_hide_crosshair",
	HudElementCrosshairHud = "scanner_hide_crosshair_hud",
	HudElementDodgeCounter = "scanner_hide_dodge_counter",
	HudElementDodgeCount = "scanner_hide_dodge_count",
	HudElementStamina = "scanner_hide_stamina",
}
local SCANNER_EXCLUDED_ELEMENTS = {
	ConstantElementChat = true,
}
local SCANNER_SETTING_IDS = {
	enable_scanner_visibility = true,
	scanner_transparency_amount = true,
	scanner_smooth_fade = true,
	scanner_fade_duration = true,
	scanner_caption_opacity = true,
	scanner_hide_crosshair = true,
	scanner_hide_crosshair_hud = true,
	scanner_hide_dodge_counter = true,
	scanner_hide_dodge_count = true,
	scanner_hide_stamina = true,
	scanner_hide_ability_icons = true,
	scanner_hide_buff_bars = true,
}
local scanner_ability_icons = {}
local scanner_equipped_active = false
local scanner_overlay_active = false
local scanner_searching_active = false
local scanner_current_alpha = 1
local scanner_fade_target = nil
local scanner_fade_speed = 0
local scanner_subtitle_hook_applied = false
local decode_same_targets_count = 0
local decode_autosolve_cooldown = 0
local decode_autosolve_press_deadline = 0
local expedition_same_targets_count = 0
local expedition_autosolve_cooldown = 0
local expedition_autosolve_press_deadline = 0
local frequency_autosolve_submit_cooldown = 0
local balance_cursor_x = 0
local balance_cursor_y = 0
local balance_previous_x = 0
local balance_previous_y = 0
local balance_velocity_x = 0
local balance_velocity_y = 0
local balance_distance = 0
local balance_input_window = 0
local EMPTY_WIDGETS_BY_NAME = {}
local DECODE_TARGET_FILL_ALPHA = 18
local _sync_scanner_hud_visibility
local _active_live_minigame
local _active_decode_autosolve_minigame
local _active_expedition_autosolve_minigame
local _active_frequency_autosolve_minigame

if not math.clamp then
	function math.clamp(value, minimum, maximum)
		return value < minimum and minimum or (value > maximum and maximum or value)
	end
end

local function _gameplay_time()
	local time_manager = Managers.time

	if not time_manager then
		return 0
	end

	if time_manager.has_timer and time_manager:has_timer("gameplay") then
		return time_manager:time("gameplay")
	end

	if time_manager.has_timer and time_manager:has_timer("main") then
		return time_manager:time("main")
	end

	return 0
end

local function _has_gameplay_timer()
	local time_manager = Managers.time

	return time_manager ~= nil and time_manager.has_timer ~= nil and time_manager:has_timer("gameplay")
end

local function _preview_supports_missing_gameplay_timer()
	return mod._preview_allow_missing_gameplay_timer == true
end

local function _ui_highlight_color(alpha_override)
	local alpha = alpha_override ~= nil and alpha_override or (mod:get("ui_color_alpha") or 210)

	return {
		alpha,
		mod:get("ui_color_red") or 255,
		mod:get("ui_color_green") or 165,
		mod:get("ui_color_blue") or 0,
	}
end

local function _world_scan_color(alpha_override)
	local alpha = alpha_override ~= nil and alpha_override or (mod:get("world_scan_color_alpha") or 255)

	return {
		alpha,
		mod:get("world_scan_color_red") or 0,
		mod:get("world_scan_color_green") or 255,
		mod:get("world_scan_color_blue") or 110,
	}
end

local function _world_scan_outline_color()
	local color = _world_scan_color()

	return {
		color[2] / 255,
		color[3] / 255,
		color[4] / 255,
	}
end

local function _world_scan_display_mode()
	return mod:get("world_scan_display_mode") or "highlight"
end

local function _world_scan_uses_highlight()
	local mode = _world_scan_display_mode()

	return mode == "highlight" or mode == "both"
end

local function _world_scan_uses_icon()
	local mode = _world_scan_display_mode()

	return mode == "icon" or mode == "both"
end

local function _is_expedition_minigame_type(minigame_type)
	return minigame_type == EXPEDITION_MINIGAME_TYPE
end

_preview_display_minigame_type = function(minigame_type)
	if minigame_type == PREVIEW_DECODE_SYMBOLS_12_TYPE then
		return MinigameSettings.types.decode_symbols
	end

	return minigame_type
end

local function _is_mod_active()
	return mod:is_enabled() and mod:get("enable_mod_override") ~= false
end

local function _should_highlight_world_scans()
	return _is_mod_active() and mod:get("enable_world_scans")
end

_world_scan_always_show = function()
	return _should_highlight_world_scans() and mod:get("world_scan_always_show") == true
end

_world_scan_effective_active = function()
	return _world_scan_always_show() or scanner_world_helper_active or scanner_equipped_active or scanner_searching_active
end

_world_scan_show_through_walls = function()
	return mod:get("world_scan_through_walls") ~= false
end

_world_scan_needs_visibility_refresh = function()
	return _should_highlight_world_scans() and not _world_scan_show_through_walls()
end

_world_scan_uses_item_overlay = function()
	return _should_highlight_world_scans() and mod:get("world_scan_item_overlay") == true
end

_scanner_scan_settings = function()
	if mod._scanner_scan_settings then
		return mod._scanner_scan_settings
	end

	local ok, scanner_equip_template = pcall(require, "scripts/settings/equipment/weapon_templates/devices/scanner_equip")
	local actions = ok and scanner_equip_template and scanner_equip_template.actions or nil
	local action_scan = actions and actions.action_scan or nil
	local action_scan_confirm = actions and actions.action_scan_confirm or nil
	local scan_settings = action_scan and action_scan.scan_settings or action_scan_confirm and action_scan_confirm.scan_settings

	if not scan_settings then
		scan_settings = {
			confirm_time = 1,
			fail_time_time = 0.6,
			outline_time = 0.5,
			distance = {
				far = 20,
				near = 6,
			},
			angle = {
				outer = 1.57075,
				inner = {
					far = 0.174533,
					near = 0.01,
				},
				line_of_sight_check = {
					horizontal = 0.174533,
					vertical = 0.698132,
				},
			},
			score_distribution = {
				angle = 0.2,
				distance = 0.8,
			},
		}
	end

	mod._scanner_scan_settings = scan_settings

	return scan_settings
end

local function _world_scan_collect_scannable_units(include_inactive)
	local state_managers = Managers.state
	local extension_manager = state_managers and state_managers.extension
	local result = {}

	if not extension_manager or not extension_manager:has_system("mission_objective_zone_system") then
		return result
	end

	local mission_objective_zone_system = extension_manager:system("mission_objective_zone_system")
	local mission_objective_system = extension_manager:has_system("mission_objective_system") and extension_manager:system("mission_objective_system") or nil

	if mission_objective_system then
		local active_objectives = mission_objective_system:active_objectives() or nil

		if active_objectives then
			for objective, _ in pairs(active_objectives) do
				local objective_name = objective and objective.name and objective:name() or nil
				local objective_group_id = objective and objective.group_id and objective:group_id() or nil
				local selected_units = nil

				if objective_name and objective_group_id ~= nil and mission_objective_zone_system.retrieve_selected_units_for_event then
					local ok, units = pcall(mission_objective_zone_system.retrieve_selected_units_for_event, mission_objective_zone_system, objective_name, objective_group_id)

					if ok then
						selected_units = units
					end
				end

				local zone_extension = objective_name and objective_group_id ~= nil and mission_objective_zone_system:current_active_zone(objective_name, objective_group_id) or nil
				local zone_units = zone_extension and zone_extension.scannable_units and zone_extension:scannable_units() or nil
				local candidate_sets = {
					selected_units,
					zone_units,
				}

				for set_index = 1, #candidate_sets do
					local units = candidate_sets[set_index]

					if units and #units > 0 then
						for i = 1, #units do
							local scannable_unit = units[i]

							if scannable_unit and Unit.alive(scannable_unit) then
								result[scannable_unit] = true
							end
						end
					end
				end
			end
		end
	end

	if next(result) ~= nil then
		return result
	end

	local active_scannables = mission_objective_zone_system and mission_objective_zone_system:scannable_units() or {}

	for scannable_unit, _ in pairs(active_scannables) do
		if Unit.alive(scannable_unit) then
			local scannable_extension = ScriptUnit.has_extension(scannable_unit, "mission_objective_zone_scannable_system")

			if scannable_extension and scannable_extension:is_active() then
				result[scannable_unit] = true
			end
		end
	end

	return result
end

_world_scan_player_context = function()
	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1) or nil
	local player_unit = player and player.player_unit or nil

	if not player_unit or not Unit.alive(player_unit) then
		return nil
	end

	local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
	local interaction_extension = ScriptUnit.has_extension(player_unit, "interaction_system")
	local first_person = unit_data_extension and unit_data_extension:read_component("first_person")
	local physics_world = interaction_extension and interaction_extension._physics_world

	if not first_person or not physics_world then
		return nil
	end

	return player_unit, first_person, physics_world
end

_world_scan_has_active_scannables = function()
	if not scannable_units or next(scannable_units) == nil then
		_refresh_scannable_units()
	end

	for scannable_unit, _ in pairs(scannable_units) do
		if Unit.alive(scannable_unit) then
			local scannable_extension = ScriptUnit.has_extension(scannable_unit, "mission_objective_zone_scannable_system")

			if scannable_extension and (scannable_extension:is_active() or _world_scan_always_show()) then
				return true
			end
		end
	end

	return false
end

_request_world_scan_refresh = function(force_now)
	mod._world_scan_next_refresh_t = nil
	mod._world_scan_next_visibility_refresh_t = nil

	if force_now and (_world_scan_effective_active() or scanner_searching_active or scanner_overlay_active) then
		_set_world_scan_highlights(_world_scan_effective_active())
		_refresh_world_scan_overlay_view()
		_refresh_world_scan_icons_view()
	end
end

_world_scan_unit_is_visible = function(scannable_unit, scannable_extension)
	if _world_scan_show_through_walls() then
		return true
	end

	local _, first_person, physics_world = _world_scan_player_context()
	local scan_settings = _scanner_scan_settings()

	if not first_person or not physics_world or not scan_settings then
		return true
	end

	local Scanning = require("scripts/utilities/scanning")
	local ok, result = pcall(Scanning.check_line_of_sight_to_unit, physics_world, first_person, scannable_unit, scan_settings, scannable_extension)

	if ok and result == true then
		return true
	end

	local from_position = first_person.position
	local target_position = scannable_extension and scannable_extension:center_poisition() or POSITION_LOOKUP[scannable_unit]

	if not from_position or not target_position then
		return true
	end

	local to_target = target_position - from_position
	local distance = Vector3.length(to_target)

	if distance <= 0.001 then
		return true
	end

	local blocked = PhysicsWorld.raycast(physics_world, from_position, Vector3.normalize(to_target), distance, "any", "collision_filter", "filter_interactable_line_of_sight_check")

	return not blocked
end

local function _is_minigame_enabled(minigame_type)
	if not _is_mod_active() then
		return false
	end

	local setting_id = MINIGAME_ENABLE_SETTINGS[minigame_type]

	if not setting_id then
		return true
	end

	return mod:get(setting_id) ~= false
end

local function _tag_minigame_type(minigame, minigame_type)
	if type(minigame) == "table" and minigame_type ~= nil then
		minigame._auspex_helper_minigame_type = minigame_type
	end

	return minigame
end

local function _minigame_type_hint(minigame)
	return type(minigame) == "table" and (rawget(minigame, "_auspex_helper_minigame_type") or rawget(minigame, "_minigame_type")) or nil
end

local function _should_highlight_decode_targets()
	return _is_minigame_enabled(MinigameSettings.types.decode_symbols) and mod:get("enable_decode_helper")
end

local function _should_highlight_expedition_targets()
	return _is_minigame_enabled(EXPEDITION_MINIGAME_TYPE) and mod:get("enable_expedition_helper") ~= false
end

local function _should_highlight_drill_targets()
	return _is_minigame_enabled(MinigameSettings.types.drill) and mod:get("enable_drill_helper")
end

local function _should_show_drill_direction_arrows()
	return _is_minigame_enabled(MinigameSettings.types.drill) and mod:get("enable_drill_direction_arrows") ~= false
end

_is_drill_autosolve_enabled = function()
	return _is_minigame_enabled(MinigameSettings.types.drill) and mod:get("enable_drill_autosolve")
end

_drill_autosolve_speed = function()
	return math.clamp(mod:get("drill_autosolve_speed") or 1, 0.25, 3)
end

_drill_autosolve_step_delay = function()
	return math.max((MinigameSettings.drill_move_delay or 0.12) / _drill_autosolve_speed(), 0.02)
end

local function _is_scanner_visibility_enabled()
	return _is_mod_active() and mod:get("enable_scanner_visibility")
end

local function _is_decode_autosolve_enabled()
	return _is_minigame_enabled(MinigameSettings.types.decode_symbols) and mod:get("enable_decode_autosolve")
end

local function _is_expedition_autosolve_enabled()
	return _is_minigame_enabled(EXPEDITION_MINIGAME_TYPE) and mod:get("enable_expedition_autosolve")
end

local function _is_frequency_autosolve_enabled()
	return _is_minigame_enabled(MinigameSettings.types.frequency) and mod:get("enable_frequency_autosolve")
end

local function _is_balance_autosolve_enabled()
	return _is_minigame_enabled(MinigameSettings.types.balance) and mod:get("enable_balance_autosolve")
end

local function _clear_preview_close_request()
	preview_close_requested_at = nil
	preview_close_view_name = nil
end

local function _reset_scanner_fade_state()
	scanner_fade_target = nil
	scanner_current_alpha = 1
end

local function _track_scanner_ability_icon(icon)
	if icon then
		scanner_ability_icons[icon] = true
	end
end

local function _untrack_scanner_ability_icon(icon)
	if icon then
		scanner_ability_icons[icon] = nil
	end
end

local function _is_buff_bar(class_name)
	return type(class_name) == "string" and (string.find(class_name, "^HudElementBuffBar") ~= nil or class_name == "HudElementPlayerBuffs")
end

local function _is_ability_icon(class_name)
	return type(class_name) == "string" and (string.find(class_name, "^HudElementPlayerAbility") ~= nil or string.find(class_name, "^HudElementPlayerSlotItemAbility") ~= nil)
end

local function _should_hide_scanner_element(class_name)
	if not _is_scanner_visibility_enabled() or SCANNER_EXCLUDED_ELEMENTS[class_name] then
		return false
	end

	local setting_id = SCANNER_HIDE_SETTING_IDS[class_name]

	if setting_id then
		return mod:get(setting_id) ~= false
	end

	if _is_ability_icon(class_name) then
		return mod:get("scanner_hide_ability_icons") ~= false
	end

	if _is_buff_bar(class_name) then
		return mod:get("scanner_hide_buff_bars") ~= false
	end

	return false
end

local function _scanner_hidden_alpha()
	return math.clamp(mod:get("scanner_transparency_amount") or 0, 0, 1)
end

local function _overlay_scanner_view_active()
	local ui_manager = Managers.ui

	if not ui_manager then
		return false
	end

	return ui_manager:view_active(PREVIEW_VIEW_NAME)
		or ui_manager:is_view_closing(PREVIEW_VIEW_NAME)
		or ui_manager:view_active(OVERLAY_VIEW_NAME)
		or ui_manager:is_view_closing(OVERLAY_VIEW_NAME)
		or ui_manager:view_active(WORLD_SCAN_VIEW_NAME)
		or ui_manager:is_view_closing(WORLD_SCAN_VIEW_NAME)
end

local function _scanner_is_active()
	return scanner_equipped_active or scanner_searching_active or scanner_overlay_active
end

local function _refresh_scanner_overlay_state()
	local active = _overlay_scanner_view_active()

	if scanner_overlay_active == active then
		return
	end

	scanner_overlay_active = active
	_sync_scanner_hud_visibility()
end

_suppress_world_scan_views = function(duration)
	local suppress_until = _gameplay_time() + math.max(duration or 0, 0)

	if suppress_until > (mod._world_scan_views_suppressed_until or 0) then
		mod._world_scan_views_suppressed_until = suppress_until
	end
end

_world_scan_views_suppressed = function()
	return _gameplay_time() < (mod._world_scan_views_suppressed_until or 0)
end

local function _apply_scanner_alpha_to_widget(widget, alpha)
	if not widget then
		return
	end

	local hidden_alpha = _scanner_hidden_alpha()
	local fully_hidden = hidden_alpha <= 0.001 and alpha <= 0.001

	if widget.content then
		widget.content.visible = not fully_hidden
	end

	widget.alpha_multiplier = alpha

	if widget.style then
		for _, style in pairs(widget.style) do
			if type(style) == "table" and style.color then
				if not style.__auspex_helper_original_alpha then
					style.__auspex_helper_original_alpha = style.color[1]
				end

				style.color[1] = fully_hidden and 0 or math.floor(style.__auspex_helper_original_alpha * alpha)
			end
		end
	end

	widget.dirty = true
end

local function _apply_scanner_alpha_to_element(element, alpha)
	if not element or SCANNER_EXCLUDED_ELEMENTS[element.__class_name] then
		return
	end

	if element._widgets then
		for _, widget in pairs(element._widgets) do
			_apply_scanner_alpha_to_widget(widget, alpha)
		end

		if element.set_dirty then
			element:set_dirty()
		end
	end

	if element._widgets_by_name then
		for _, widget in pairs(element._widgets_by_name) do
			_apply_scanner_alpha_to_widget(widget, alpha)
		end
	end

	if element._stamina_nodge_widget then
		_apply_scanner_alpha_to_widget(element._stamina_nodge_widget, alpha)
	end

	if element.__class_name == "HudElementStamina" and element._widgets_by_name then
		for widget_name, widget in pairs(element._widgets_by_name) do
			if widget_name == "gauge" or widget_name == "stamina_bar" or widget_name == "stamina_depleted_bar" then
				_apply_scanner_alpha_to_widget(widget, alpha)
			end
		end
	end

	if element._instance_data_tables then
		for _, data in pairs(element._instance_data_tables) do
			if data.instance then
				_apply_scanner_alpha_to_element(data.instance, alpha)
			end
		end
	end

	if element._player_weapons then
		for _, weapon_data in pairs(element._player_weapons) do
			if weapon_data.hud_element_player_weapon then
				_apply_scanner_alpha_to_element(weapon_data.hud_element_player_weapon, alpha)
			end
		end
	end

	if element._player_weapons_array then
		for _, weapon_data in ipairs(element._player_weapons_array) do
			if weapon_data.hud_element_player_weapon then
				_apply_scanner_alpha_to_element(weapon_data.hud_element_player_weapon, alpha)
			end
		end
	end

	if element._player_panel_by_unique_id then
		for _, panel_data in pairs(element._player_panel_by_unique_id) do
			if panel_data.panel then
				_apply_scanner_alpha_to_element(panel_data.panel, alpha)
			end
		end
	end

	if element._player_panels_array then
		for _, panel_data in ipairs(element._player_panels_array) do
			if panel_data.panel then
				_apply_scanner_alpha_to_element(panel_data.panel, alpha)
			end
		end
	end
end

local function _apply_scanner_current_alpha()
	local ui_manager = Managers.ui
	local hud = ui_manager and ui_manager:get_hud()

	if not hud then
		return
	end

	local function _set_element_alpha(element, class_name)
		if not element then
			return
		end

		if _should_hide_scanner_element(class_name) then
			_apply_scanner_alpha_to_element(element, scanner_current_alpha)
		else
			_apply_scanner_alpha_to_element(element, 1)
		end
	end

	for class_name, _ in pairs(SCANNER_HIDE_SETTING_IDS) do
		_set_element_alpha(hud:element(class_name), class_name)
	end

	for class_name, _ in pairs(hud._elements or {}) do
		if _is_buff_bar(class_name) or _is_ability_icon(class_name) then
			_set_element_alpha(hud:element(class_name), class_name)
		end
	end

	local constant_elements = ui_manager and ui_manager:ui_constant_elements()

	if constant_elements and constant_elements._elements then
		for class_name, element in pairs(constant_elements._elements) do
			if _is_buff_bar(class_name) or _is_ability_icon(class_name) then
				_set_element_alpha(element, class_name)
			end
		end
	end

	for icon, _ in pairs(scanner_ability_icons) do
		if icon.__class_name then
			_set_element_alpha(icon, icon.__class_name)
		end
	end
end

local function _set_scanner_hud_visibility(show)
	if not _is_scanner_visibility_enabled() then
		show = true
	end

	local target_alpha = show and 1 or _scanner_hidden_alpha()

	if mod:get("scanner_smooth_fade") then
		if math.abs(scanner_current_alpha - target_alpha) > 0.001 then
			scanner_fade_target = target_alpha
			scanner_fade_speed = math.abs(scanner_current_alpha - target_alpha) / math.clamp(mod:get("scanner_fade_duration") or 0.3, 0.05, 10)
		end
	else
		scanner_fade_target = nil
		scanner_current_alpha = target_alpha
	end

	_apply_scanner_current_alpha()
end

_sync_scanner_hud_visibility = function()
	_set_scanner_hud_visibility(not (_is_scanner_visibility_enabled() and _scanner_is_active()))
end

local function _set_scanner_equipped_state(active)
	scanner_equipped_active = active == true
	_sync_scanner_hud_visibility()
end

_refresh_world_scan_overlay_view = function()
	local ui_manager = Managers.ui

	if not ui_manager then
		return
	end

	local active = ui_manager:view_active(WORLD_SCAN_VIEW_NAME)
	local closing = ui_manager:is_view_closing(WORLD_SCAN_VIEW_NAME)
	local blocked_by_minigame = ui_manager:view_active(STOCK_SCANNER_VIEW_NAME)
		or ui_manager:view_active(PREVIEW_VIEW_NAME)
		or ui_manager:is_view_closing(PREVIEW_VIEW_NAME)
		or ui_manager:view_active(OVERLAY_VIEW_NAME)
		or ui_manager:is_view_closing(OVERLAY_VIEW_NAME)
	local should_open = _is_mod_active()
		and _world_scan_uses_item_overlay()
		and scanner_searching_active
		and _world_scan_has_active_scannables()
		and not _world_scan_views_suppressed()
		and not blocked_by_minigame

	if should_open then
		if not active and not closing then
			ui_manager:open_view(WORLD_SCAN_VIEW_NAME, nil, false, false, nil, {
				auspex_helper_is_practice = false,
				auspex_helper_world_scan_overlay = true,
				minigame_type = MinigameSettings.types.none,
			}, {
				use_transition_ui = false,
			})
		end
	elseif active or closing then
		ui_manager:close_view(WORLD_SCAN_VIEW_NAME, true)
	end

	_refresh_scanner_overlay_state()
end

_refresh_world_scan_icons_view = function()
	local ui_manager = Managers.ui

	if not ui_manager then
		return
	end

	local active = ui_manager:view_active(WORLD_SCAN_ICONS_VIEW_NAME)
	local closing = ui_manager:is_view_closing(WORLD_SCAN_ICONS_VIEW_NAME)
	local blocked_by_overlay = ui_manager:view_active(STOCK_SCANNER_VIEW_NAME)
		or ui_manager:view_active(PREVIEW_VIEW_NAME)
		or ui_manager:is_view_closing(PREVIEW_VIEW_NAME)
		or ui_manager:view_active(OVERLAY_VIEW_NAME)
		or ui_manager:is_view_closing(OVERLAY_VIEW_NAME)
	local icon_units = mod._world_scan_icon_units
	local should_open = _is_mod_active()
		and _world_scan_uses_icon()
		and _world_scan_effective_active()
		and icon_units ~= nil
		and next(icon_units) ~= nil
		and not _world_scan_views_suppressed()
		and not blocked_by_overlay

	if should_open then
		if not active and not closing then
			ui_manager:open_view(WORLD_SCAN_ICONS_VIEW_NAME, nil, false, false, nil, {
				auspex_helper_is_practice = false,
				auspex_helper_world_scan_icons = true,
				minigame_type = MinigameSettings.types.none,
			}, {
				use_transition_ui = false,
			})
		end
	elseif active or closing then
		ui_manager:close_view(WORLD_SCAN_ICONS_VIEW_NAME, true)
	end
end

local function _set_scanner_searching_state(active)
	scanner_searching_active = active == true
	_refresh_world_scan_overlay_view()
	_sync_scanner_hud_visibility()
end

_scanner_search_input_active = function()
	local input_manager = Managers.input
	local input_service = input_manager and input_manager:get_input_service("Ingame")

	if not input_service or input_service:is_null_service() then
		return false
	end

	return not not (input_service:_get("action_two_hold") or input_service:_get("action_two_pressed"))
end

local function _reset_decode_autosolve()
	decode_same_targets_count = 0
	decode_autosolve_cooldown = 0
	decode_autosolve_press_deadline = 0
end

local function _reset_expedition_autosolve()
	expedition_same_targets_count = 0
	expedition_autosolve_cooldown = 0
	expedition_autosolve_press_deadline = 0
end

local function _reset_frequency_autosolve()
	frequency_autosolve_submit_cooldown = 0
end

_reset_drill_autosolve = function()
	mod._drill_autosolve_move_cooldown = 0
	mod._drill_autosolve_submit_cooldown = 0
	mod._drill_autosolve_press_deadline = 0
	mod._drill_autosolve_release_deadline = 0
	mod._drill_autosolve_second_press_deadline = 0
	mod._drill_autosolve_force_release = false
	mod._drill_autosolve_stage = nil
	mod._drill_autosolve_minigame = nil
	mod._drill_autosolve_stage_ready_time = 0
	mod._drill_autosolve_selected_stage = nil
	mod._drill_autosolve_selected_index = nil
	mod._drill_autosolve_selected_at = 0
end

mod._sync_drill_autosolve_stage = function(minigame)
	if not _looks_like_drill_minigame(minigame) then
		mod._drill_autosolve_stage = nil

		return
	end

	local current_stage = minigame:current_stage()

	if mod._drill_autosolve_stage == current_stage then
		return
	end

	mod._drill_autosolve_stage = current_stage
	mod._drill_autosolve_submit_cooldown = 0
	mod._drill_autosolve_press_deadline = 0
	mod._drill_autosolve_release_deadline = 0
	mod._drill_autosolve_second_press_deadline = 0
	mod._drill_autosolve_force_release = false
	mod._drill_autosolve_stage_ready_time = _gameplay_time() + 0.05
	mod._drill_autosolve_selected_stage = current_stage
	mod._drill_autosolve_selected_index = nil
	mod._drill_autosolve_selected_at = 0
end

mod._sync_drill_autosolve_minigame = function(minigame)
	if mod._drill_autosolve_minigame == minigame then
		return
	end

	mod._drill_autosolve_minigame = minigame
	_reset_drill_autosolve()
	mod._drill_autosolve_minigame = minigame
end

local function _decode_autosolve_cooldown_seconds()
	return (mod:get("decode_interact_cooldown") or 150) * 0.001
end

local function _expedition_autosolve_cooldown_seconds()
	return (mod:get("expedition_interact_cooldown") or 150) * 0.001
end

local function _decode_target_precision()
	return (mod:get("decode_target_precision") or 4) * 0.1
end

local function _expedition_target_precision()
	return (mod:get("expedition_target_precision") or 4) * 0.1
end

_is_networked_live_session = function()
	local connection_manager = Managers.connection
	local host_type = connection_manager and connection_manager.host_type and connection_manager:host_type() or nil

	return host_type ~= nil and host_type ~= "singleplay" and host_type ~= "singleplay_backend_session"
end

_is_networked_live_minigame = function(minigame)
	return minigame ~= nil and not practice_session and _is_networked_live_session() and minigame == (_active_live_minigame and _active_live_minigame() or nil)
end

_decode_autosolve_prediction_seconds = function(minigame)
	if _is_networked_live_minigame(minigame) then
		return 0.06
	end

	return 0
end

_decode_autosolve_press_window_seconds = function(minigame)
	if _is_networked_live_minigame(minigame) then
		return 0.09
	end

	return 0.035
end

local function _expedition_autosolve_prediction_seconds(minigame)
	if _is_networked_live_minigame(minigame) then
		return 0.06
	end

	return 0
end

local function _expedition_autosolve_press_window_seconds(minigame)
	if _is_networked_live_minigame(minigame) then
		return 0.09
	end

	return 0.035
end

local function _frequency_autosolve_strength()
	return mod:get("frequency_autosolve_strength") or 1
end

local PRIMARY_HOLD_ACTIONS = {
	action_one_hold = true,
	interact_hold = true,
	interact_primary_hold = true,
	jump_held = true,
}

local function _is_primary_hold_action(action_name)
	return PRIMARY_HOLD_ACTIONS[action_name] == true
end

local function _is_decode_on_target(minigame, time, stage_offset)
	if not minigame or not time then
		return false
	end

	local current_stage = minigame._current_stage

	if not current_stage then
		return false
	end

	current_stage = current_stage + (stage_offset or 0)

	local sweep_duration = minigame._decode_symbols_sweep_duration
	local targets = minigame._decode_targets or {}
	local target = targets[current_stage]

	if not target then
		return false
	end

	local precision = _decode_target_precision()

	if _is_networked_live_minigame(minigame) then
		precision = math.max(0.05, precision - 0.08)
	end

	local target_margin = 1 / (minigame._decode_symbols_items_per_stage - 1) * sweep_duration
	local start_target = (target - (1.5 - precision)) * target_margin
	local end_target = (target - (0.5 + precision)) * target_margin
	local cursor_time = minigame:_calculate_cursor_time(time + _decode_autosolve_prediction_seconds(minigame))

	return cursor_time > start_target and cursor_time < end_target
end

local function _is_expedition_on_target(minigame, time, stage_offset)
	if not minigame or not time then
		return false
	end

	local current_stage = minigame._current_stage

	if not current_stage then
		return false
	end

	current_stage = current_stage + (stage_offset or 0)

	local sweep_duration = minigame._decode_symbols_sweep_duration
	local targets = minigame._decode_targets or {}
	local target = targets[current_stage]

	if not target then
		return false
	end

	local precision = _expedition_target_precision()

	if _is_networked_live_minigame(minigame) then
		precision = math.max(0.05, precision - 0.08)
	end

	local target_margin = 1 / (minigame._decode_symbols_items_per_stage - 1) * sweep_duration
	local start_target = (target - (1.5 - precision)) * target_margin
	local end_target = (target - (0.5 + precision)) * target_margin
	local cursor_time = minigame:_calculate_cursor_time(time + _expedition_autosolve_prediction_seconds(minigame))

	return cursor_time > start_target and cursor_time < end_target
end

local function _count_decode_same_targets(minigame)
	if not minigame then
		return 0
	end

	local current_stage = minigame._current_stage
	local targets = minigame._decode_targets

	if not current_stage or not targets or next(targets) == nil then
		return 0
	end

	local current_target = targets[current_stage]
	local count = 0

	for index = current_stage, #targets do
		if targets[index] == current_target then
			count = count + 1
		else
			break
		end
	end

	return count
end

local function _count_expedition_same_targets(minigame)
	if not minigame then
		return 0
	end

	local current_stage = minigame._current_stage
	local targets = minigame._decode_targets

	if not current_stage or not targets or next(targets) == nil then
		return 0
	end

	local current_target = targets[current_stage]
	local count = 0

	for index = current_stage, #targets do
		if targets[index] == current_target then
			count = count + 1
		else
			break
		end
	end

	return count
end

_looks_like_drill_minigame = function(minigame)
	return minigame and minigame.targets and minigame.correct_targets and minigame.cursor_position and minigame.current_stage and minigame.search_percentage and minigame.uses_joystick and minigame:uses_joystick()
end

_drill_autosolve_move_vector = function(minigame)
	if not _is_drill_autosolve_enabled() or not _looks_like_drill_minigame(minigame) then
		return nil
	end

	if minigame:state() ~= MinigameSettings.game_states.gameplay then
		return nil
	end

	local stage = minigame:current_stage()
	local targets = minigame:targets()
	local correct_targets = minigame:correct_targets()
	local correct_target = stage and correct_targets and correct_targets[stage]
	local target = stage and targets and targets[stage] and correct_target and targets[stage][correct_target]
	local cursor_position = minigame:cursor_position()

	if not target or not cursor_position then
		return nil
	end

	local delta_x = target.x - cursor_position.x
	local delta_y = -(target.y - cursor_position.y)
	local length = math.sqrt(delta_x * delta_x + delta_y * delta_y)

	if length <= 0.01 then
		return Vector3.zero()
	end

	return Vector3(delta_x / length, delta_y / length, 0)
end

_should_submit_drill_autosolve = function(minigame, t)
	if not _is_drill_autosolve_enabled() or not _looks_like_drill_minigame(minigame) then
		return false
	end

	if minigame:state() ~= MinigameSettings.game_states.gameplay then
		return false
	end

	local stage = minigame:current_stage()
	local correct_targets = minigame:correct_targets()
	local selected_index = minigame.selected_index and minigame:selected_index() or nil
	local correct_target = stage and correct_targets and correct_targets[stage]
	local search_time = rawget(minigame, "_search_time")
	local networked_live = _is_networked_live_minigame(minigame)
	local submit_time = (t or _gameplay_time()) + (networked_live and 0.12 or 0)
	local search_ready = search_time and submit_time >= search_time + (MinigameSettings.drill_search_time or 0)
	local tracked_stage = mod._drill_autosolve_selected_stage
	local tracked_index = mod._drill_autosolve_selected_index

	if tracked_stage ~= stage or tracked_index ~= selected_index then
		mod._drill_autosolve_selected_stage = stage
		mod._drill_autosolve_selected_index = selected_index
		mod._drill_autosolve_selected_at = submit_time
	end

	if submit_time < (mod._drill_autosolve_stage_ready_time or 0) then
		return false
	end

	if submit_time < (mod._drill_autosolve_selected_at or 0) + (networked_live and 0.05 or 0.03) then
		return false
	end

	return search_ready and selected_index ~= nil and selected_index == correct_target
end

local function _reset_balance_autosolve()
	balance_input_window = 0
end

local function _balance_autosolve_strength()
	return mod:get("balance_autosolve_strength") or 0.66
end

_balance_autosolve_axis_value = function(axis_value, axis_velocity, distance, strength)
	local magnitude = math.abs(axis_value)

	if magnitude <= 0.035 then
		return nil
	end

	local velocity = math.abs(axis_velocity or 0)
	local moving_outward = (axis_value > 0 and (axis_velocity or 0) > 0) or (axis_value < 0 and (axis_velocity or 0) < 0)
	local outward_velocity = moving_outward and velocity or 0
	local center_factor = math.clamp((distance - 0.08) / 0.55, 0, 1)
	center_factor = center_factor * center_factor

	if distance < 0.18 and outward_velocity < 0.7 then
		return nil
	end

	local override_value = magnitude * strength * (0.18 + center_factor * 0.92)

	if outward_velocity > 0.4 then
		override_value = override_value + math.min(outward_velocity * 0.04, 0.2)
	end

	if distance >= 0.92 or outward_velocity >= 3.5 then
		local axis_share = magnitude / math.max(distance, 0.001)
		local recovery_strength = distance >= 0.985 and 1.35 or outward_velocity >= 5 and 1.3 or 1.15

		override_value = math.max(override_value, math.min(axis_share * recovery_strength, 1))
	end

	return math.clamp(override_value, 0, 1)
end

_balance_autosolve_move_vector = function(minigame)
	if not _is_balance_autosolve_enabled() or not minigame or not minigame.position then
		return nil
	end

	local position = minigame:position()
	local distance = minigame.distance and minigame:distance() or math.sqrt(position.x * position.x + position.y * position.y)

	if distance <= 0.02 then
		return nil
	end

	local strength = _balance_autosolve_strength()
	local x = 0
	local y = 0
	local input_x = _balance_autosolve_axis_value(position.x, balance_velocity_x, distance, strength)
	local input_y = _balance_autosolve_axis_value(position.y, balance_velocity_y, distance, strength)

	if input_x then
		x = position.x > 0 and -input_x or input_x
	end

	if input_y then
		y = position.y > 0 and input_y or -input_y
	end

	if x == 0 and y == 0 then
		return nil
	end

	return Vector3(x, y, 0)
end

local function _handle_decode_autosolve_input(action_name, result)
	if not _is_decode_autosolve_enabled() or not _is_primary_hold_action(action_name) then
		return result
	end

	local gameplay_time = _gameplay_time()
	local minigame = _active_decode_autosolve_minigame and _active_decode_autosolve_minigame() or nil

	if not minigame then
		decode_autosolve_press_deadline = 0

		return result
	end

	if decode_autosolve_press_deadline > gameplay_time then
		return true
	end

	if result or decode_autosolve_cooldown > 0 then
		return result
	end

	if not _is_decode_on_target(minigame, gameplay_time) then
		return result
	end

	local current_stage = minigame._current_stage
	local targets = minigame._decode_targets or {}
	local same_next_target = current_stage and targets[current_stage] ~= nil and targets[current_stage] == targets[current_stage + 1]
	local press_window = _decode_autosolve_press_window_seconds(minigame)

	decode_autosolve_press_deadline = gameplay_time + press_window
	decode_autosolve_cooldown = press_window + (same_next_target and 0.05 or _decode_autosolve_cooldown_seconds())

	return true
end

local function _handle_expedition_autosolve_input(action_name, result)
	if not _is_expedition_autosolve_enabled() or not _is_primary_hold_action(action_name) then
		return result
	end

	local gameplay_time = _gameplay_time()
	local minigame = _active_expedition_autosolve_minigame and _active_expedition_autosolve_minigame() or nil

	if not minigame then
		expedition_autosolve_press_deadline = 0

		return result
	end

	if expedition_autosolve_press_deadline > gameplay_time then
		return true
	end

	if result or expedition_autosolve_cooldown > 0 then
		return result
	end

	if not _is_expedition_on_target(minigame, gameplay_time) then
		return result
	end

	local current_stage = minigame._current_stage
	local targets = minigame._decode_targets or {}
	local same_next_target = current_stage and targets[current_stage] ~= nil and targets[current_stage] == targets[current_stage + 1]
	local press_window = _expedition_autosolve_press_window_seconds(minigame)

	expedition_autosolve_press_deadline = gameplay_time + press_window
	expedition_autosolve_cooldown = press_window + (same_next_target and 0.05 or _expedition_autosolve_cooldown_seconds())

	return true
end

local function _frequency_autosolve_move_vector(minigame)
	local current = minigame and minigame.frequency and minigame:frequency() or nil
	local target = minigame and minigame.target_frequency and minigame:target_frequency() or nil

	if not current or not target then
		return nil
	end

	local margin = MinigameSettings.frequency_success_margin or 0.1
	local strength = _frequency_autosolve_strength()
	local range_x = math.max(MinigameSettings.frequency_width_max_scale - MinigameSettings.frequency_width_min_scale, 0.001)
	local range_y = math.max(MinigameSettings.frequency_height_max_scale - MinigameSettings.frequency_height_min_scale, 0.001)
	local delta_x = target.x - current.x
	local delta_y = target.y - current.y
	local input_x = math.abs(delta_x) <= margin * 0.35 and 0 or math.clamp(delta_x / (range_x * 0.2) * strength, -1, 1)
	local input_y = math.abs(delta_y) <= margin * 0.35 and 0 or math.clamp(delta_y / (range_y * 0.2) * strength, -1, 1)

	return Vector3(input_x, input_y, 0)
end

local function _handle_frequency_autosolve_input(action_name, result)
	if not _is_frequency_autosolve_enabled() then
		return result
	end

	local minigame = _active_frequency_autosolve_minigame and _active_frequency_autosolve_minigame() or nil

	if not minigame then
		return result
	end

	if action_name == "move" then
		if type(result) == "userdata" and (result.x ~= 0 or result.y ~= 0 or result.z ~= 0) then
			return result
		end

		return _frequency_autosolve_move_vector(minigame) or result
	end

	if result or not _is_primary_hold_action(action_name) or frequency_autosolve_submit_cooldown > 0 then
		return result
	end

	if minigame.is_visually_on_target and minigame:is_visually_on_target() then
		frequency_autosolve_submit_cooldown = 0.12

		return true
	end

	return result
end

_handle_drill_autosolve_input = function(action_name, result)
	if not _is_drill_autosolve_enabled() then
		return result
	end

	local minigame = _active_drill_autosolve_minigame and _active_drill_autosolve_minigame() or nil

	if not minigame then
		mod._sync_drill_autosolve_minigame(nil)
		return result
	end

	mod._sync_drill_autosolve_minigame(minigame)
	mod._sync_drill_autosolve_stage(minigame)

	if _is_primary_hold_action(action_name) then
		local gameplay_time = _gameplay_time()

		if (mod._drill_autosolve_press_deadline or 0) > gameplay_time then
			return true
		end

		if (mod._drill_autosolve_release_deadline or 0) > gameplay_time then
			return false
		end

		if (mod._drill_autosolve_second_press_deadline or 0) > gameplay_time then
			return true
		end

		if mod._drill_autosolve_force_release then
			mod._drill_autosolve_force_release = false

			return false
		end

		if not result and (mod._drill_autosolve_submit_cooldown or 0) <= 0 and _should_submit_drill_autosolve(minigame, gameplay_time) then
			mod._drill_autosolve_submit_cooldown = _drill_autosolve_step_delay()
			mod._drill_autosolve_press_deadline = gameplay_time + 0.08
			mod._drill_autosolve_release_deadline = gameplay_time + 0.12
			mod._drill_autosolve_second_press_deadline = gameplay_time + 0.2
			mod._drill_autosolve_force_release = true

			return true
		end

		return result
	end

	if action_name == "move" then
		local auto_move = _drill_autosolve_move_vector(minigame)

		if not auto_move then
			return result
		end

		return auto_move
	end

	local auto_move = _drill_autosolve_move_vector(minigame)

	if not auto_move then
		return result
	end

	local override_value = nil

	if action_name == "move_left" and (auto_move.x or 0) < -0.15 then
		override_value = math.abs(auto_move.x or 0)
	elseif action_name == "move_right" and (auto_move.x or 0) > 0.15 then
		override_value = math.abs(auto_move.x or 0)
	elseif action_name == "move_forward" and (auto_move.y or 0) > 0.15 then
		override_value = math.abs(auto_move.y or 0)
	elseif action_name == "move_backward" and (auto_move.y or 0) < -0.15 then
		override_value = math.abs(auto_move.y or 0)
	end

	if override_value then
		local current_value = type(result) == "number" and result or (result and 1 or 0)

		return math.max(current_value, override_value)
	end

	return result
end

local function _handle_balance_autosolve_input(action_name, result)
	if not _is_balance_autosolve_enabled() or balance_input_window <= 0 or balance_distance <= 0.2 then
		return result
	end

	local strength = _balance_autosolve_strength()
	local override_value = nil
	local edge_recovery = balance_distance >= 0.92

	if balance_cursor_x > 0 and action_name == "move_left" and (edge_recovery or balance_velocity_x > -0.5) then
		override_value = _balance_autosolve_axis_value(balance_cursor_x, balance_velocity_x, balance_distance, strength)
	elseif balance_cursor_x < 0 and action_name == "move_right" and (edge_recovery or balance_velocity_x < 0.5) then
		override_value = _balance_autosolve_axis_value(balance_cursor_x, balance_velocity_x, balance_distance, strength)
	elseif balance_cursor_y > 0 and action_name == "move_forward" and (edge_recovery or balance_velocity_y > -0.5) then
		override_value = _balance_autosolve_axis_value(balance_cursor_y, balance_velocity_y, balance_distance, strength)
	elseif balance_cursor_y < 0 and action_name == "move_backward" and (edge_recovery or balance_velocity_y < 0.5) then
		override_value = _balance_autosolve_axis_value(balance_cursor_y, balance_velocity_y, balance_distance, strength)
	end

	if override_value then
		local current_value = type(result) == "number" and result or 0

		return math.max(current_value, override_value)
	end

	return result
end

_refresh_scannable_units = function()
	scannable_units = _world_scan_collect_scannable_units(_world_scan_always_show())
	mod._world_scan_scannable_units = scannable_units
end

local function _apply_world_scan_outline_settings()
	local prop_outline_settings = OutlineSettings and OutlineSettings.PropOutlineExtension
	local outline_color = _world_scan_outline_color()
	local signature = string.format("%d:%d:%d:%s", outline_color[1] or 0, outline_color[2] or 0, outline_color[3] or 0, _world_scan_show_through_walls() and "1" or "0")

	if not prop_outline_settings then
		return
	end

	if mod._world_scan_outline_settings_signature == signature then
		return
	end

	mod._world_scan_outline_settings_signature = signature

	if prop_outline_settings.scanning then
		prop_outline_settings.scanning.color = outline_color
		prop_outline_settings.scanning.material_layers = {
			"scanning",
		}
	end

	if prop_outline_settings.scanning_confirm then
		prop_outline_settings.scanning_confirm.color = outline_color
		prop_outline_settings.scanning_confirm.material_layers = _world_scan_show_through_walls() and {
			"scanning",
			"scanning_reversed_depth",
		} or {
			"scanning",
		}
	end
end

_apply_world_scan_outline_color_to_unit = function(scannable_unit)
	if not scannable_unit or not Unit.alive(scannable_unit) then
		return
	end

	local color = _world_scan_outline_color()
	local color_vector = Vector3(color[1], color[2], color[3])
	local signature = string.format("%d:%d:%d", color[1] or 0, color[2] or 0, color[3] or 0)
	local applied_signatures = mod._world_scan_unit_color_signatures or {}

	mod._world_scan_unit_color_signatures = applied_signatures

	if applied_signatures[scannable_unit] == signature then
		return
	end

	pcall(Unit.set_vector3_for_material, scannable_unit, "scanning", "outline_color", color_vector)
	pcall(Unit.set_vector3_for_material, scannable_unit, "scanning_reversed_depth", "outline_color", color_vector)
	applied_signatures[scannable_unit] = signature
end

_set_world_scan_markers = function(active)
	local icon_units = mod._world_scan_icon_units or {}
	local enabled = active and _should_highlight_world_scans() and _world_scan_uses_icon() or false

	table.clear(icon_units)
	mod._world_scan_icon_units = icon_units

	if not enabled then
		_refresh_world_scan_icons_view()

		return
	end

	for scannable_unit, _ in pairs(scannable_units) do
		if Unit.alive(scannable_unit) then
			local scannable_extension = ScriptUnit.has_extension(scannable_unit, "mission_objective_zone_scannable_system")

			if scannable_extension and (scannable_extension:is_active() or _world_scan_always_show()) then
				local visible = _world_scan_show_through_walls() or _world_scan_unit_is_visible(scannable_unit, scannable_extension)

				if visible then
					icon_units[scannable_unit] = true
				end
			end
		end
	end

	_refresh_world_scan_icons_view()
end

_set_world_scan_highlights = function(active, refresh_units)
	local enabled = active and _should_highlight_world_scans() and _world_scan_uses_highlight() or false
	local highlighted_units = mod._world_scan_highlighted_units or {}
	local next_highlighted_units = {}

	_apply_world_scan_outline_settings()

	if refresh_units ~= false then
		_refresh_scannable_units()
	end

	for scannable_unit, _ in pairs(scannable_units) do
		if Unit.alive(scannable_unit) then
			local scannable_extension = ScriptUnit.has_extension(scannable_unit, "mission_objective_zone_scannable_system")

			if scannable_extension and (scannable_extension:is_active() or _world_scan_always_show()) then
				local visible = false

				if enabled then
					visible = _world_scan_show_through_walls() or _world_scan_unit_is_visible(scannable_unit, scannable_extension)
				end

				scannable_extension:set_scanning_outline(visible)
				scannable_extension:set_scanning_highlight(visible)

				if visible then
					next_highlighted_units[scannable_unit] = true
					_apply_world_scan_outline_color_to_unit(scannable_unit)
				elseif mod._world_scan_unit_color_signatures then
					mod._world_scan_unit_color_signatures[scannable_unit] = nil
				end
			end
		end
	end

	for highlighted_unit, _ in pairs(highlighted_units) do
		if not next_highlighted_units[highlighted_unit] and Unit.alive(highlighted_unit) then
			local highlighted_extension = ScriptUnit.has_extension(highlighted_unit, "mission_objective_zone_scannable_system")

			if highlighted_extension then
				highlighted_extension:set_scanning_outline(false)
				highlighted_extension:set_scanning_highlight(false)
			end
		end
	end

	mod._world_scan_highlighted_units = next_highlighted_units

	_set_world_scan_markers(active)
end

local function _ensure_decode_overlay_widgets(view, widget_count, widget_size)
	if widget_count <= 0 then
		view._auspex_helper_decode_widgets = nil

		return nil
	end

	local widgets = view._auspex_helper_decode_widgets
	local active_widget_size = widget_size or ScannerDisplayViewDecodeSymbolsSettings.decode_symbol_widget_size
	local previous_widget_size = view._auspex_helper_decode_widget_size

	if widgets and #widgets == widget_count and previous_widget_size and previous_widget_size[1] == active_widget_size[1] and previous_widget_size[2] == active_widget_size[2] then
		return widgets
	end

	widgets = {}

	for index = 1, widget_count do
		local widget_definition = UIWidget.create_definition({
			{
				pass_type = "texture",
				style_id = "highlight",
				value = "content/ui/materials/backgrounds/scanner/scanner_decode_symbol_highlight",
				style = {
					hdr = true,
					color = _ui_highlight_color(),
				},
			},
		}, "center_pivot", nil, active_widget_size)

		widgets[index] = UIWidget.init("auspex_helper_decode_" .. tostring(index), widget_definition)
	end

	view._auspex_helper_decode_widgets = widgets
	view._auspex_helper_decode_widget_size = {
		active_widget_size[1],
		active_widget_size[2],
	}

	return widgets
end

local DRILL_DIRECTION_ARROW_MATERIAL = "content/ui/materials/buttons/arrow_01"
local DRILL_DIRECTION_ARROW_SIZE = {
	44,
	44,
}
local DRILL_DIRECTION_WIDGET_SPECS = {
	left = {
		angle = math.rad(180),
		input_x = -1,
		input_y = 0,
		offset_x = -1,
		offset_y = 0,
		offset = { 0, 0, 7 },
	},
	right = {
		angle = 0,
		input_x = 1,
		input_y = 0,
		offset_x = 1,
		offset_y = 0,
		offset = { 0, 0, 7 },
	},
	up = {
		angle = math.rad(90),
		input_x = 0,
		input_y = 1,
		offset_x = 0,
		offset_y = -1,
		offset = { 0, 0, 7 },
	},
	down = {
		angle = math.rad(-90),
		input_x = 0,
		input_y = -1,
		offset_x = 0,
		offset_y = 1,
		offset = { 0, 0, 7 },
	},
}
local DRILL_DIRECTION_WIDGET_ORDER = {
	"left",
	"right",
	"up",
	"down",
}

local function _ensure_drill_direction_widgets(view)
	local widgets = view._auspex_helper_drill_direction_widgets

	if widgets then
		return widgets
	end

	widgets = {}

	for index = 1, #DRILL_DIRECTION_WIDGET_ORDER do
		local direction = DRILL_DIRECTION_WIDGET_ORDER[index]
		local spec = DRILL_DIRECTION_WIDGET_SPECS[direction]
		local widget_definition = UIWidget.create_definition({
			{
				pass_type = "rotated_texture",
				style_id = "arrow",
				value = DRILL_DIRECTION_ARROW_MATERIAL,
				style = {
					angle = spec.angle,
					color = {
						0,
						0,
						0,
						0,
					},
					offset = spec.offset,
					pivot = {},
				},
			},
		}, "center_pivot", nil, DRILL_DIRECTION_ARROW_SIZE)

		widgets[direction] = UIWidget.init("auspex_helper_drill_arrow_" .. direction, widget_definition)
	end

	view._auspex_helper_drill_direction_widgets = widgets

	return widgets
end

_drill_target_for_input = function(cursor_position, targets, selected_index, input_x, input_y)
	if not cursor_position or not targets or (input_x == 0 and input_y == 0) then
		return nil
	end

	local aim_radian = math.atan2(-input_y, input_x)
	local closest_index = nil
	local lowest_points = math.huge

	for index = 1, #targets do
		if index ~= selected_index then
			local target = targets[index]
			local radian = math.atan2(target.y - cursor_position.y, target.x - cursor_position.x)
			local angle = math.abs(radian - aim_radian)

			if angle > math.pi then
				angle = 2 * math.pi - angle
			end

			local distance = math.sqrt((cursor_position.x - target.x) * (cursor_position.x - target.x) + (cursor_position.y - target.y) * (cursor_position.y - target.y))
			local points = distance + angle * MinigameSettings.drill_move_distance_power

			if points < lowest_points and angle < math.pi / 3 then
				closest_index = index
				lowest_points = points
			end
		end
	end

	return closest_index
end

local function _set_drill_direction_widgets(view, minigame)
	local widgets = _ensure_drill_direction_widgets(view)
	local color = _ui_highlight_color()
	local hidden_color = {
		0,
		0,
		0,
		0,
	}
	local show_arrows = _should_show_drill_direction_arrows() and minigame and minigame.state and minigame:state() == MinigameSettings.game_states.gameplay
	local left_active = false
	local right_active = false
	local up_active = false
	local down_active = false
	local anchor_x = 0
	local anchor_y = 0
	local anchor_half_width = 48
	local anchor_half_height = 48

	if show_arrows then
		local stage = minigame:current_stage()
		local targets = minigame:targets()
		local stage_targets = stage and targets and targets[stage]
		local correct_targets = minigame:correct_targets()
		local cursor_position = minigame:cursor_position()
		local selected_index = minigame.selected_index and minigame:selected_index() or nil
		local correct_target = stage and correct_targets and correct_targets[stage]
		local target_widgets = stage and view._target_widgets and view._target_widgets[stage]
		local anchor_widget = target_widgets and target_widgets[selected_index]

		if anchor_widget then
			local anchor_size = anchor_widget.content and anchor_widget.content.size or DRILL_DIRECTION_ARROW_SIZE
			local anchor_offset = anchor_widget.offset or {
				0,
				0,
				0,
			}

			anchor_half_width = (anchor_size[1] or 96) * 0.5
			anchor_half_height = (anchor_size[2] or 96) * 0.5
			anchor_x = (anchor_offset[1] or 0) + anchor_half_width
			anchor_y = (anchor_offset[2] or 0) + anchor_half_height
		end

		if cursor_position and stage_targets and correct_target then
			left_active = _drill_target_for_input(cursor_position, stage_targets, selected_index, -1, 0) == correct_target
			right_active = _drill_target_for_input(cursor_position, stage_targets, selected_index, 1, 0) == correct_target
			up_active = _drill_target_for_input(cursor_position, stage_targets, selected_index, 0, 1) == correct_target
			down_active = _drill_target_for_input(cursor_position, stage_targets, selected_index, 0, -1) == correct_target
		else
			show_arrows = false
		end
	end

	local arrow_distance_x = anchor_half_width + DRILL_DIRECTION_ARROW_SIZE[1] * 0.5 + 12
	local arrow_distance_y = anchor_half_height + DRILL_DIRECTION_ARROW_SIZE[2] * 0.5 + 12

	for index = 1, #DRILL_DIRECTION_WIDGET_ORDER do
		local direction = DRILL_DIRECTION_WIDGET_ORDER[index]
		local widget = widgets[direction]
		local spec = DRILL_DIRECTION_WIDGET_SPECS[direction]
		local style = widget and widget.style and widget.style.arrow
		local offset = style and style.offset

		if offset then
			offset[1] = anchor_x + spec.offset_x * arrow_distance_x - DRILL_DIRECTION_ARROW_SIZE[1] * 0.5
			offset[2] = anchor_y + spec.offset_y * arrow_distance_y - DRILL_DIRECTION_ARROW_SIZE[2] * 0.5
		end
	end

	widgets.left.style.arrow.color = show_arrows and left_active and color or hidden_color
	widgets.right.style.arrow.color = show_arrows and right_active and color or hidden_color
	widgets.up.style.arrow.color = show_arrows and up_active and color or hidden_color
	widgets.down.style.arrow.color = show_arrows and down_active and color or hidden_color
end

mod._set_drill_direction_widgets = _set_drill_direction_widgets

mod:hook_require("scripts/ui/hud/elements/player_ability/hud_element_player_ability", function(HudElementPlayerAbility)
	mod:hook_safe(HudElementPlayerAbility, "init", function(self)
		_track_scanner_ability_icon(self)
	end)

	mod:hook_safe(HudElementPlayerAbility, "destroy", function(self)
		_untrack_scanner_ability_icon(self)
	end)
end)

mod:hook_require("scripts/ui/hud/elements/player_ability/hud_element_player_slot_item_ability", function(HudElementPlayerSlotItemAbility)
	mod:hook_safe(HudElementPlayerSlotItemAbility, "init", function(self)
		_track_scanner_ability_icon(self)
	end)

	mod:hook_safe(HudElementPlayerSlotItemAbility, "destroy", function(self)
		_untrack_scanner_ability_icon(self)
	end)
end)

local HudElementBase = rawget(_G, "HudElementBase")

if HudElementBase then
	mod:hook_safe(HudElementBase, "init", function(self)
		if not (_is_scanner_visibility_enabled() and _scanner_is_active()) then
			return
		end

		if not _should_hide_scanner_element(self.__class_name) then
			return
		end

		local alpha = mod:get("scanner_smooth_fade") and scanner_current_alpha or _scanner_hidden_alpha()

		_apply_scanner_alpha_to_element(self, alpha)
	end)
end

mod:hook_require("scripts/ui/constant_elements/elements/subtitles/constant_element_subtitles", function(Subtitles)
	if scanner_subtitle_hook_applied then
		return
	end

	scanner_subtitle_hook_applied = true

	mod:hook_safe(Subtitles, "update", function(self)
		if not (_is_scanner_visibility_enabled() and _scanner_is_active()) then
			if self.__auspex_helper_captions_restored then
				return
			end

			if self._setup_text_opacity then
				self:_setup_text_opacity()
			end

			if self._setup_letterbox then
				self:_setup_letterbox()
			end

			self.__auspex_helper_captions_restored = true

			return
		end

		local alpha = math.clamp((mod:get("scanner_caption_opacity") or 0) * 255, 0, 255)

		if self._set_text_opacity then
			self:_set_text_opacity(alpha)
		end

		if self._set_letterbox_opacity then
			self:_set_letterbox_opacity(alpha)
		end

		self.__auspex_helper_captions_restored = false
	end)
end)

local PreviewMinigameBase = {}

function PreviewMinigameBase:_init_base(stage_amount)
	self._action_held = nil
	self._completed = false
	self._current_stage = 1
	self._current_state = MinigameSettings.game_states.gameplay
	self._stage_amount = stage_amount or 1
	self._should_exit = false
end

function PreviewMinigameBase:is_completed()
	return self._completed or self._current_stage > self._stage_amount
end

function PreviewMinigameBase:complete()
	self._completed = true
	self._current_stage = self._stage_amount + 1
end

function PreviewMinigameBase:current_stage()
	return self._current_stage
end

function PreviewMinigameBase:state()
	return self._current_state
end

function PreviewMinigameBase:uses_action()
	return true
end

function PreviewMinigameBase:uses_joystick()
	return false
end

function PreviewMinigameBase:start(player)
	self._action_held = false
	self._player = player
	self._should_exit = false
end

function PreviewMinigameBase:stop()
	self._should_exit = true
end

function PreviewMinigameBase:setup_game()
	return
end

function PreviewMinigameBase:handle_state(state)
	if state == MinigameSettings.game_states.intro then
		return MinigameSettings.game_states.gameplay
	elseif state == MinigameSettings.game_states.transition and self:is_completed() then
		return MinigameSettings.game_states.outro
	end

	return state
end

function PreviewMinigameBase:set_state(state)
	self._current_state = self:handle_state(state)
end

function PreviewMinigameBase:action(held, t)
	if self._action_held == nil then
		if held then
			return false
		end

		self._action_held = false
	end

	if self._action_held ~= held then
		self._action_held = held

		if held then
			self:on_action_pressed(t or _gameplay_time())
		else
			self:on_action_released(t or _gameplay_time())
		end

		return true
	end

	return false
end

function PreviewMinigameBase:on_action_pressed(t)
	return
end

function PreviewMinigameBase:on_action_released(t)
	return
end

function PreviewMinigameBase:on_axis_set(t, x, y)
	return
end

function PreviewMinigameBase:update(dt, t)
	return
end

function PreviewMinigameBase:escape_action(action_two_pressed)
	if action_two_pressed then
		self._should_exit = true

		return true
	end

	return false
end

function PreviewMinigameBase:blocks_weapon_actions()
	return true
end

function PreviewMinigameBase:should_exit()
	return self._should_exit == true or self:is_completed()
end

function PreviewMinigameBase:angle_check()
	return false
end

function PreviewMinigameBase:unit()
	return nil
end

function PreviewMinigameBase:unequip_on_exit()
	return false
end

local function _practice_decode_speed_multiplier()
	return math.clamp(mod:get("practice_decode_speed_multiplier") or 1, 0.5, 3)
end

local function _practice_decode_sweep_duration()
	return math.max(MinigameSettings.decode_symbols_sweep_duration / _practice_decode_speed_multiplier(), 0.1)
end

_decode_layout = function(minigame)
	local base_widget_size = ScannerDisplayViewDecodeSymbolsSettings.decode_symbol_widget_size
	local base_spacing = ScannerDisplayViewDecodeSymbolsSettings.decode_symbol_spacing
	local stage_amount = minigame and minigame._stage_amount or MinigameSettings.decode_symbols_stage_amount
	local items_per_stage = MinigameSettings.decode_symbols_items_per_stage
	local total_height = base_widget_size[2] * stage_amount + base_spacing * (stage_amount - 1)
	local scale = total_height > PREVIEW_DECODE_MAX_GRID_HEIGHT and PREVIEW_DECODE_MAX_GRID_HEIGHT / total_height or 1
	local widget_size = {
		base_widget_size[1] * scale,
		base_widget_size[2] * scale,
	}
	local spacing = base_spacing * scale

	return {
		stage_amount = stage_amount,
		widget_size = widget_size,
		spacing = spacing,
		starting_offset_x = -(widget_size[1] * items_per_stage + spacing * (items_per_stage - 1)) * 0.5,
		starting_offset_y = -(widget_size[2] * stage_amount + spacing * (stage_amount - 1)) * 0.5,
	}
end

local function _practice_balance_time_multiplier()
	return math.clamp(mod:get("practice_balance_time_multiplier") or 3, 1, 10)
end

local function _practice_balance_difficulty()
	return math.clamp(mod:get("practice_balance_difficulty") or 1, 0.5, 3)
end

local function _configure_preview_balance_settings(minigame)
	local difficulty = _practice_balance_difficulty()
	local difficulty_root = math.sqrt(difficulty)
	local start_scale = 1 + (difficulty_root - 1) * 0.45

	minigame._balance_progress_rate = 0.28 / _practice_balance_time_multiplier()
	minigame._balance_push_ratio = MinigameSettings.balance_push_ratio * difficulty_root
	minigame._balance_disrupt_interval = MinigameSettings.balance_disrupt_interval / difficulty_root
	minigame._balance_disrupt_power = MinigameSettings.balance_disrupt_power * difficulty_root
	minigame._balance_move_ratio = MinigameSettings.balance_move_ratio / difficulty_root
	minigame._balance_max_speed = MinigameSettings.balance_max_speed * difficulty_root
	minigame._balance_start_distance_scale = start_scale
	minigame._balance_start_speed_scale = start_scale
end

local function _random_decode_targets(stage_amount)
	local targets = {}
	local previous_target = nil
	local target_stage_amount = stage_amount or MinigameSettings.decode_symbols_stage_amount
	local items_per_stage = MinigameSettings.decode_symbols_items_per_stage

	for stage = 1, target_stage_amount do
		local target = math.random(1, items_per_stage)

		if items_per_stage > 1 and previous_target and target == previous_target and math.random() < 0.65 then
			target = target % items_per_stage + 1
		end

		targets[stage] = target
		previous_target = target
	end

	return targets
end

local PreviewDecodeMinigame = setmetatable({}, { __index = PreviewMinigameBase })
PreviewDecodeMinigame.__index = PreviewDecodeMinigame

function PreviewDecodeMinigame:new()
	local stage_amount = MinigameSettings.decode_symbols_stage_amount
	local total_items = stage_amount * MinigameSettings.decode_symbols_items_per_stage
	local symbol_pool_size = MinigameSettings.decode_symbols_total_items
	local symbols = {}

	for index = 1, total_items do
		symbols[index] = (index - 1) % symbol_pool_size + 1
	end

	local minigame = setmetatable({
		_decode_targets = _random_decode_targets(stage_amount),
		_decode_symbols_sweep_duration = _practice_decode_sweep_duration(),
		_decode_symbols_items_per_stage = MinigameSettings.decode_symbols_items_per_stage,
		_start_time = _gameplay_time(),
		_symbols = symbols,
	}, PreviewDecodeMinigame)

	minigame:_init_base(stage_amount)

	return minigame
end

function PreviewDecodeMinigame:new_with_stage_amount(stage_amount)
	local total_items = stage_amount * MinigameSettings.decode_symbols_items_per_stage
	local symbol_pool_size = MinigameSettings.decode_symbols_total_items
	local symbols = {}

	for index = 1, total_items do
		symbols[index] = (index - 1) % symbol_pool_size + 1
	end

	local minigame = setmetatable({
		_decode_targets = _random_decode_targets(stage_amount),
		_decode_symbols_sweep_duration = _practice_decode_sweep_duration(),
		_decode_symbols_items_per_stage = MinigameSettings.decode_symbols_items_per_stage,
		_start_time = _gameplay_time(),
		_symbols = symbols,
	}, PreviewDecodeMinigame)

	minigame:_init_base(stage_amount)

	return minigame
end

function PreviewDecodeMinigame:start(player)
	PreviewMinigameBase.start(self, player)
	self._decode_symbols_sweep_duration = _practice_decode_sweep_duration()
	self._start_time = _gameplay_time()
end

function PreviewDecodeMinigame:start_time()
	return self._start_time
end

function PreviewDecodeMinigame:current_decode_target()
	return self._decode_targets[self._current_stage]
end

function PreviewDecodeMinigame:sweep_duration()
	return self._decode_symbols_sweep_duration
end

function PreviewDecodeMinigame:symbols()
	return self._symbols
end

function PreviewDecodeMinigame:_calculate_cursor_time(time)
	local delta_time = (time or _gameplay_time()) - self._start_time
	local sweep_duration = self:sweep_duration()
	local cursor_time = delta_time % (sweep_duration * 2)

	if sweep_duration < cursor_time then
		cursor_time = 2 * sweep_duration - cursor_time
	end

	return cursor_time
end

function PreviewDecodeMinigame:is_on_target(time)
	local target = self:current_decode_target()

	if not target then
		return false
	end

	local sweep_duration = self:sweep_duration()
	local target_margin = 1 / (self._decode_symbols_items_per_stage - 1) * sweep_duration
	local start_target = (target - 1.5) * target_margin
	local end_target = (target - 0.5) * target_margin
	local cursor_time = self:_calculate_cursor_time(time)

	return start_target < cursor_time and cursor_time < end_target
end

function PreviewDecodeMinigame:on_action_pressed(t)
	if self:is_on_target(t) then
		local is_last_stage = self._current_stage >= self._stage_amount

		self._current_stage = self._current_stage + 1

		if self._current_stage > self._stage_amount then
			self:play_sound("sfx_minigame_success_last")
			self:complete()
		elseif is_last_stage then
			self:play_sound("sfx_minigame_success_last")
		else
			self:play_sound("sfx_minigame_success")
		end
	else
		self._current_stage = math.max(self._current_stage - 1, 1)
		self:play_sound("sfx_minigame_fail")
	end
end

local PreviewDrillMinigame = setmetatable({}, { __index = PreviewMinigameBase })
PreviewDrillMinigame.__index = PreviewDrillMinigame
local DRILL_TARGET_TEMPLATES = {
	{
		{ x = -0.72, y = 0.23 },
		{ x = -0.21, y = -0.24 },
		{ x = 0.11, y = 0.34 },
		{ x = 0.64, y = -0.09 },
		{ x = 0.27, y = -0.39 },
	},
	{
		{ x = -0.61, y = -0.04 },
		{ x = -0.07, y = 0.29 },
		{ x = 0.46, y = -0.22 },
		{ x = 0.75, y = 0.21 },
		{ x = 0.05, y = -0.43 },
	},
	{
		{ x = -0.77, y = -0.17 },
		{ x = -0.29, y = 0.35 },
		{ x = 0.24, y = -0.32 },
		{ x = 0.68, y = 0.09 },
		{ x = 0.02, y = 0.03 },
	},
}

local function _randomized_drill_targets()
	local randomized_targets = {}

	for stage = 1, #DRILL_TARGET_TEMPLATES do
		local base_targets = DRILL_TARGET_TEMPLATES[stage]
		local mirror_x = math.random(0, 1) == 1 and -1 or 1
		local mirror_y = math.random(0, 1) == 1 and -1 or 1
		local rotation = (math.random() * 2 - 1) * 0.45
		local sin_rotation = math.sin(rotation)
		local cos_rotation = math.cos(rotation)
		local stage_targets = {}

		for index = 1, #base_targets do
			local base_target = base_targets[index]
			local x = base_target.x * mirror_x
			local y = base_target.y * mirror_y
			local rotated_x = x * cos_rotation - y * sin_rotation
			local rotated_y = x * sin_rotation + y * cos_rotation

			stage_targets[index] = {
				x = math.clamp(rotated_x + (math.random() * 2 - 1) * 0.05, -0.82, 0.82),
				y = math.clamp(rotated_y + (math.random() * 2 - 1) * 0.05, -0.48, 0.48),
			}
		end

		randomized_targets[stage] = stage_targets
	end

	return randomized_targets
end

local function _random_drill_correct_targets(targets)
	local correct_targets = {}

	for stage = 1, #targets do
		correct_targets[stage] = math.random(1, #targets[stage])
	end

	return correct_targets
end

function PreviewDrillMinigame:new()
	local targets = _randomized_drill_targets()
	local minigame = setmetatable({
		_correct_targets = _random_drill_correct_targets(targets),
		_cursor_position = {
			x = 0,
			y = 0,
		},
		_last_move = 0,
		_search_time = false,
		_selected_index = nil,
		_targets = targets,
		_transition_start_time = nil,
		_search_feedback_played = false,
	}, PreviewDrillMinigame)

	minigame:_init_base(MinigameSettings.drill_stage_amount)

	return minigame
end

function PreviewDrillMinigame:targets()
	return self._targets
end

function PreviewDrillMinigame:correct_targets()
	return self._correct_targets
end

function PreviewDrillMinigame:selected_index()
	return self._selected_index
end

function PreviewDrillMinigame:cursor_position()
	return self._cursor_position
end

function PreviewDrillMinigame:is_searching()
	return not not self._search_time
end

function PreviewDrillMinigame:search_percentage(time)
	if not self._search_time then
		return 0
	end

	return math.clamp(((time or _gameplay_time()) - self._search_time) / MinigameSettings.drill_search_time, 0, 1)
end

function PreviewDrillMinigame:is_on_target()
	return self._selected_index ~= nil and self._selected_index == self._correct_targets[self._current_stage]
end

function PreviewDrillMinigame:transition_percentage(time)
	if self._current_state ~= MinigameSettings.game_states.transition and self._current_state ~= MinigameSettings.game_states.outro then
		return 0
	end

	if not self._transition_start_time then
		return 0
	end

	return math.clamp(((time or _gameplay_time()) - self._transition_start_time) / MinigameSettings.drill_transition_time, 0, 1)
end

function PreviewDrillMinigame:handle_state(state)
	state = PreviewMinigameBase.handle_state(self, state)

	if state == MinigameSettings.game_states.transition or state == MinigameSettings.game_states.outro then
		self._transition_start_time = _gameplay_time()
	end

	return state
end

function PreviewDrillMinigame:uses_joystick()
	return true
end

function PreviewDrillMinigame:update(dt, t)
	if self._current_state == MinigameSettings.game_states.transition and t - self._transition_start_time >= MinigameSettings.drill_transition_time then
		self:set_state(MinigameSettings.game_states.gameplay)
		self._transition_start_time = nil
		self._search_feedback_played = false
		return
	elseif self._current_state == MinigameSettings.game_states.outro then
		if t - self._transition_start_time >= MinigameSettings.drill_transition_time then
			self._should_exit = true
			self._completed = true
			self._current_state = MinigameSettings.game_states.complete
		end

		return
	end

	if self._current_state ~= MinigameSettings.game_states.gameplay then
		return
	end

	if self._search_time and not self._search_feedback_played and self:search_percentage(t) >= 1 then
		self._search_feedback_played = true

		if self:is_on_target() then
			self:play_sound("sfx_minigame_bio_selection_right")
		else
			self:play_sound("sfx_minigame_bio_selection_wrong")
		end
	end
end

function PreviewDrillMinigame:on_action_pressed(t)
	if self._current_state ~= MinigameSettings.game_states.gameplay or not self._selected_index or not self._search_time then
		return
	end

	if self:search_percentage(t) < 1 then
		return
	end

	if self:is_on_target() then
		self._search_time = false
		self._search_feedback_played = false
		self._selected_index = nil
		self._cursor_position.x = 0
		self._cursor_position.y = 0
		local is_last_stage = self._current_stage >= self._stage_amount

		self._current_stage = math.min(self._current_stage + 1, self._stage_amount + 1)

		if self._current_stage > self._stage_amount then
			self:play_sound("sfx_minigame_bio_progress_last")
		else
			if is_last_stage then
				self:play_sound("sfx_minigame_bio_progress_last")
			else
				self:play_sound("sfx_minigame_bio_progress")
			end
		end

		self:set_state(MinigameSettings.game_states.transition)
	else
		self._search_time = false
		self._search_feedback_played = false
		self:play_sound("sfx_minigame_bio_fail")
	end
end

function PreviewDrillMinigame:should_exit()
	return self._current_state == MinigameSettings.game_states.complete
end

function PreviewDrillMinigame:on_axis_set(t, x, y)
	if self._current_state ~= MinigameSettings.game_states.gameplay or self:is_completed() or (x == 0 and y == 0) then
		return
	end

	if t <= self._last_move + MinigameSettings.drill_move_delay then
		return
	end

	self._last_move = t

	local aim_radian = math.atan2(-y, x)
	local targets = self._targets[self._current_stage]
	local cursor_position = self._cursor_position
	local closest_index = nil
	local lowest_points = math.huge

	for index = 1, #targets do
		if index ~= self._selected_index then
			local target = targets[index]
			local radian = math.atan2(target.y - cursor_position.y, target.x - cursor_position.x)
			local angle = math.abs(radian - aim_radian)

			if angle > math.pi then
				angle = 2 * math.pi - angle
			end

			local distance = math.sqrt((cursor_position.x - target.x) * (cursor_position.x - target.x) + (cursor_position.y - target.y) * (cursor_position.y - target.y))
			local points = distance + angle * MinigameSettings.drill_move_distance_power

			if points < lowest_points and angle < math.pi / 3 then
				closest_index = index
				lowest_points = points
			end
		end
	end

	if closest_index then
		local target = targets[closest_index]

		self._selected_index = closest_index
		self._cursor_position.x = target.x
		self._cursor_position.y = target.y
		self._search_time = t
		self._search_feedback_played = false
		self:play_sound("sfx_minigame_bio_selection")
	end
end

local PreviewBalanceMinigame = setmetatable({}, { __index = PreviewMinigameBase })
PreviewBalanceMinigame.__index = PreviewBalanceMinigame

local function _reset_preview_balance_state(minigame)
	local angle = math.random() * math.pi * 2
	local distance_scale = minigame._balance_start_distance_scale or 1
	local speed_scale = minigame._balance_start_speed_scale or 1
	local distance = math.min((0.28 + math.random() * 0.22) * distance_scale, 0.82)
	local drift_angle = angle + math.pi * 0.35

	minigame._last_axis_set = _gameplay_time()
	minigame._position.x = math.cos(angle) * distance
	minigame._position.y = -math.sin(angle) * distance
	minigame._speed.x = math.cos(drift_angle) * 0.85 * speed_scale
	minigame._speed.y = -math.sin(drift_angle) * 0.85 * speed_scale
	minigame._progression = 0
	minigame._disrupt_timer = math.min(minigame._balance_disrupt_interval or MinigameSettings.balance_disrupt_interval, 0.45)
	minigame._is_stuck_indication = false
	minigame._sound_alert_time = 0
end

function PreviewBalanceMinigame:new()
	local minigame = setmetatable({
		_disrupt_timer = MinigameSettings.balance_disrupt_interval,
		_last_axis_set = _gameplay_time(),
		_position = {
			x = 0,
			y = 0,
		},
		_progression = 0,
		_speed = {
			x = 0,
			y = 0,
		},
		_is_stuck_indication = false,
		_sound_alert_time = 0,
	}, PreviewBalanceMinigame)

	minigame:_init_base(1)
	_configure_preview_balance_settings(minigame)
	_reset_preview_balance_state(minigame)

	return minigame
end

function PreviewBalanceMinigame:start(player)
	PreviewMinigameBase.start(self, player)
	_configure_preview_balance_settings(self)
	_reset_preview_balance_state(self)
end

function PreviewBalanceMinigame:uses_action()
	return false
end

function PreviewBalanceMinigame:uses_joystick()
	return true
end

function PreviewBalanceMinigame:position()
	return self._position
end

function PreviewBalanceMinigame:distance()
	local position = self._position

	return math.sqrt(position.x * position.x + position.y * position.y)
end

function PreviewBalanceMinigame:progressing()
	return self:distance() < 1
end

function PreviewBalanceMinigame:progression()
	return self._progression
end

function PreviewBalanceMinigame:update(dt, t)
	local position = self._position
	local speed = self._speed

	position.x = position.x + speed.x * dt
	position.y = position.y + speed.y * dt

	local aim_away = math.atan2(-position.y, position.x)
	local distance = self:distance()

	if distance > 1.02 then
		position.x = math.cos(aim_away) * 1.01
		position.y = -math.sin(aim_away) * 1.01
		speed.x = 0
		speed.y = 0
	elseif distance < 1 then
		local power = (1 - distance) * (self._balance_push_ratio or MinigameSettings.balance_push_ratio) * dt

		speed.x = speed.x + math.cos(aim_away) * power
		speed.y = speed.y - math.sin(aim_away) * power
	end

	self._disrupt_timer = self._disrupt_timer - dt

	if self:progressing() then
		self._progression = math.min(self._progression + dt * (self._balance_progress_rate or 0.28), 1)

		if self._disrupt_timer <= 0 then
			self._disrupt_timer = self._disrupt_timer + (self._balance_disrupt_interval or MinigameSettings.balance_disrupt_interval)

			local aim_random = math.random() * math.pi * 2
			local power = self._balance_disrupt_power or MinigameSettings.balance_disrupt_power

			speed.x = speed.x + math.cos(aim_random) * power
			speed.y = speed.y - math.sin(aim_random) * power
		end
	else
		self._disrupt_timer = self._balance_disrupt_interval or MinigameSettings.balance_disrupt_interval
	end

	if self._sound_alert_time > 0 then
		self._sound_alert_time = self._sound_alert_time - dt
	else
		local is_stuck = not self:progressing()

		if is_stuck ~= self._is_stuck_indication then
			if is_stuck then
				self:play_sound("sfx_minigame_fail")
			end

			self._is_stuck_indication = is_stuck
			self._sound_alert_time = MinigameSettings.balance_sound_block or 0
		end
	end

	local max_speed = self._balance_max_speed or MinigameSettings.balance_max_speed

	speed.x = math.clamp(speed.x, -max_speed, max_speed)
	speed.y = math.clamp(speed.y, -max_speed, max_speed)

	if self._progression >= 1 and not self:is_completed() then
		self:play_sound("sfx_minigame_success_last")
		self:complete()
	end
end

function PreviewBalanceMinigame:on_axis_set(t, x, y)
	y = -y

	local dt = math.max(t - self._last_axis_set, 0)

	self._last_axis_set = t

	if x ~= 0 then
		self._speed.x = self._speed.x + x * (self._balance_move_ratio or MinigameSettings.balance_move_ratio) * dt
	end

	if y ~= 0 then
		self._speed.y = self._speed.y + y * (self._balance_move_ratio or MinigameSettings.balance_move_ratio) * dt
	end
end

local PreviewFrequencyMinigame = setmetatable({}, { __index = PreviewMinigameBase })
PreviewFrequencyMinigame.__index = PreviewFrequencyMinigame

local function _clamp_practice_frequency(point)
	return {
		x = math.clamp(point.x, MinigameSettings.frequency_width_min_scale, MinigameSettings.frequency_width_max_scale),
		y = math.clamp(point.y, MinigameSettings.frequency_height_min_scale, MinigameSettings.frequency_height_max_scale),
	}
end

local function _random_frequency_point()
	local min_x = MinigameSettings.frequency_width_min_scale
	local max_x = MinigameSettings.frequency_width_max_scale
	local min_y = MinigameSettings.frequency_height_min_scale
	local max_y = MinigameSettings.frequency_height_max_scale

	return {
		x = min_x + (max_x - min_x) * math.random(),
		y = min_y + (max_y - min_y) * math.random(),
	}
end

local function _random_frequency_stage_pair()
	for _ = 1, 16 do
		local start = _clamp_practice_frequency(_random_frequency_point())
		local target = _clamp_practice_frequency(_random_frequency_point())
		local delta_x = math.abs(start.x - target.x)
		local delta_y = math.abs(start.y - target.y)

		if delta_x + delta_y >= 0.9 and (delta_x >= 0.25 or delta_y >= 0.25) then
			return start, target
		end
	end

	return _clamp_practice_frequency({
		x = MinigameSettings.frequency_width_min_scale,
		y = MinigameSettings.frequency_height_min_scale,
	}), _clamp_practice_frequency({
		x = MinigameSettings.frequency_width_max_scale,
		y = MinigameSettings.frequency_height_max_scale,
	})
end

local function _random_frequency_patterns()
	local starts = {}
	local targets = {}

	for stage = 1, MinigameSettings.frequency_search_stage_amount do
		local start, target = _random_frequency_stage_pair()

		starts[stage] = start
		targets[stage] = target
	end

	return starts, targets
end

function PreviewFrequencyMinigame:new()
	local starts, targets = _random_frequency_patterns()
	local start_frequency = starts[1]
	local target_frequency = targets[1]
	local minigame = setmetatable({
		_frequency = {
			x = start_frequency.x,
			y = start_frequency.y,
		},
		_frequency_starts = starts,
		_frequency_targets = targets,
		_last_axis_set = _gameplay_time(),
		_target_frequency = {
			x = target_frequency.x,
			y = target_frequency.y,
		},
	}, PreviewFrequencyMinigame)

	minigame:_init_base(MinigameSettings.frequency_search_stage_amount)

	return minigame
end

function PreviewFrequencyMinigame:uses_joystick()
	return true
end

function PreviewFrequencyMinigame:frequency()
	return self._frequency
end

function PreviewFrequencyMinigame:target_frequency()
	return self._target_frequency
end

function PreviewFrequencyMinigame:_set_stage_targets(stage)
	local starts = self._frequency_starts
	local targets = self._frequency_targets
	local start = starts[stage] or starts[#starts]
	local target = targets[stage] or targets[#targets]

	self._frequency.x = start.x
	self._frequency.y = start.y
	self._target_frequency.x = target.x
	self._target_frequency.y = target.y
end

function PreviewFrequencyMinigame:_is_frequency_on_target(x, y)
	return math.abs(x - self._target_frequency.x) < MinigameSettings.frequency_success_margin and math.abs(y - self._target_frequency.y) < MinigameSettings.frequency_success_margin
end

function PreviewFrequencyMinigame:_adjust_value_with_auto_aim(current_value, target_value, change_ratio, dt, min_scale, max_scale, input)
	local new_value = math.clamp(current_value + input * change_ratio * dt, min_scale, max_scale)
	local to_target = math.abs(new_value - target_value)

	if MinigameSettings.frequency_help_enabled and to_target < MinigameSettings.frequency_help_margin then
		local adjustment = (1 - to_target / MinigameSettings.frequency_help_margin) * MinigameSettings.frequency_help_power * dt

		if to_target < adjustment then
			new_value = target_value
		else
			if new_value - target_value > 0 then
				adjustment = -adjustment
			end

			new_value = new_value + adjustment
		end
	end

	return new_value
end

function PreviewFrequencyMinigame:is_visually_on_target()
	local frequency = self._frequency

	return self:_is_frequency_on_target(frequency.x, frequency.y)
end

function PreviewFrequencyMinigame:on_action_pressed(t)
	local frequency = self._frequency

	if self:_is_frequency_on_target(frequency.x, frequency.y) then
		local is_last_stage = self._current_stage >= self._stage_amount

		self._current_stage = self._current_stage + 1

		if self._current_stage > self._stage_amount then
			self:play_sound("sfx_minigame_sinus_success_last")
			self:complete()
		else
			self:_set_stage_targets(self._current_stage)
			if is_last_stage then
				self:play_sound("sfx_minigame_sinus_success_last")
			else
				self:play_sound("sfx_minigame_success")
			end
		end
	else
		self._current_stage = math.max(self._current_stage - 1, 1)
		self:_set_stage_targets(self._current_stage)
		self:play_sound("sfx_minigame_bio_fail")
	end
end

function PreviewFrequencyMinigame:on_axis_set(t, x, y)
	local dt = math.max(t - self._last_axis_set, 0)

	self._last_axis_set = t

	if x ~= 0 then
		local old_x = self._frequency.x
		local new_x = self:_adjust_value_with_auto_aim(old_x, self._target_frequency.x, MinigameSettings.frequency_change_ratio_x, dt, MinigameSettings.frequency_width_min_scale, MinigameSettings.frequency_width_max_scale, x)

		if old_x ~= new_x then
			self._frequency.x = new_x
			self:play_sound("sfx_minigame_sinus_adjust_x")
		end
	end

	if y ~= 0 then
		local old_y = self._frequency.y
		local new_y = self:_adjust_value_with_auto_aim(old_y, self._target_frequency.y, MinigameSettings.frequency_change_ratio_y, dt, MinigameSettings.frequency_height_min_scale, MinigameSettings.frequency_height_max_scale, y)

		if old_y ~= new_y then
			self._frequency.y = new_y
			self:play_sound("sfx_minigame_sinus_adjust_y")
		end
	end
end

local PREVIEW_MINIGAME_FACTORIES = {
	[MinigameSettings.types.decode_symbols] = function()
		return PreviewDecodeMinigame:new()
	end,
	[PREVIEW_DECODE_SYMBOLS_12_TYPE] = function()
		return PreviewDecodeMinigame:new_with_stage_amount(PREVIEW_DECODE_SYMBOLS_12_STAGE_AMOUNT)
	end,
	[MinigameSettings.types.drill] = function()
		return PreviewDrillMinigame:new()
	end,
	[MinigameSettings.types.balance] = function()
		return PreviewBalanceMinigame:new()
	end,
	[MinigameSettings.types.frequency] = function()
		return PreviewFrequencyMinigame:new()
	end,
}

local PreviewMinigameExtension = {}
PreviewMinigameExtension.__index = PreviewMinigameExtension

function PreviewMinigameExtension:new(minigame_type)
	local factory = PREVIEW_MINIGAME_FACTORIES[minigame_type]

	if not factory then
		return nil
	end

	local minigame = factory()

	_tag_minigame_type(minigame, minigame_type)

	return setmetatable({
		_minigame = minigame,
		_minigame_type = minigame_type,
	}, PreviewMinigameExtension)
end

function PreviewMinigameExtension:minigame_type()
	return self._minigame_type
end

function PreviewMinigameExtension:minigame()
	return self._minigame
end

local function _try_minigame_extension_minigame(minigame_extension, minigame_type)
	if not minigame_extension or not minigame_extension.minigame then
		return nil
	end

	local ok, minigame = nil, nil

	if minigame_type ~= nil then
		ok, minigame = pcall(minigame_extension.minigame, minigame_extension, minigame_type)
	else
		ok, minigame = pcall(minigame_extension.minigame, minigame_extension)
	end

	return ok and minigame or nil
end

local function _local_player()
	local cached_player = mod._cached_local_player

	if cached_player ~= nil then
		return cached_player or nil
	end

	local player_manager = Managers.player

	if not player_manager then
		mod._cached_local_player = false
		return nil
	end

	local connection_manager = Managers.connection

	if connection_manager and connection_manager.is_initialized and not connection_manager:is_initialized() then
		mod._cached_local_player = false
		return nil
	end

	if player_manager.local_player_safe then
		local ok, player = pcall(player_manager.local_player_safe, player_manager, 1)

		if ok and player then
			mod._cached_local_player = player
			return player
		end
	end

	if not connection_manager or not connection_manager.is_initialized or not connection_manager:is_initialized() then
		mod._cached_local_player = false
		return nil
	end

	if (player_manager._num_players or 0) <= 0 or (player_manager._num_human_players or 0) <= 0 then
		mod._cached_local_player = false
		return nil
	end

	if not player_manager.local_player then
		mod._cached_local_player = false
		return nil
	end

	local ok, player = pcall(player_manager.local_player, player_manager, 1)

	mod._cached_local_player = ok and player or false

	return ok and player or nil
end

local function _local_player_unit()
	local cached_player_unit = mod._cached_local_player_unit

	if cached_player_unit ~= nil then
		return cached_player_unit or nil
	end

	local player = _local_player()
	local player_unit = player and player.player_unit or nil

	mod._cached_local_player_unit = player_unit and Unit.alive(player_unit) and player_unit or false

	return mod._cached_local_player_unit or nil
end

_active_live_minigame = function()
	local cached_live_minigame = mod._cached_live_minigame

	if cached_live_minigame ~= nil then
		return cached_live_minigame or nil
	end

	local player_unit = _local_player_unit()
	local character_state_machine_extension = player_unit and ScriptUnit.has_extension(player_unit, "character_state_machine_system")

	if not character_state_machine_extension or character_state_machine_extension:current_state_name() ~= "minigame" then
		mod._cached_live_minigame = false
		mod._cached_live_minigame_type = nil
		return nil
	end

	local current_state = character_state_machine_extension:current_state()

	if current_state and current_state.minigame then
		mod._cached_live_minigame = current_state:minigame() or false
		_tag_minigame_type(mod._cached_live_minigame or nil, mod._cached_live_minigame_type)

		return mod._cached_live_minigame or nil
	end

	mod._cached_live_minigame = current_state and current_state._minigame or false
	_tag_minigame_type(mod._cached_live_minigame or nil, mod._cached_live_minigame_type)

	return mod._cached_live_minigame or nil
end

local function _active_live_minigame_type()
	local live_minigame = _active_live_minigame()

	return _minigame_type_hint(live_minigame) or mod._cached_live_minigame_type
end

local function _active_practice_minigame()
	if practice_session and practice_session.minigame and not practice_session.pending_item_mode then
		return practice_session.minigame
	end

	return nil
end

local function _active_practice_minigame_type()
	local practice_minigame = _active_practice_minigame()

	return _minigame_type_hint(practice_minigame) or (practice_session and practice_session.minigame_type) or nil
end

local function _looks_like_decode_style_minigame(minigame)
	return minigame and minigame.current_decode_target and minigame.sweep_duration and minigame.is_on_target
end

local function _looks_like_decode_minigame(minigame)
	local minigame_type = _minigame_type_hint(minigame)

	return (minigame_type == nil or not _is_expedition_minigame_type(minigame_type)) and _looks_like_decode_style_minigame(minigame)
end

local function _looks_like_expedition_minigame(minigame)
	return _is_expedition_minigame_type(_minigame_type_hint(minigame)) and _looks_like_decode_style_minigame(minigame)
end

local function _resolve_decode_style_minigame(minigame_extension)
	if not minigame_extension then
		return nil
	end

	local minigame_type = minigame_extension.minigame_type and minigame_extension:minigame_type() or nil
	local candidate_types = _is_expedition_minigame_type(minigame_type) and {
		EXPEDITION_MINIGAME_TYPE,
		false,
		MinigameSettings.types.decode_symbols,
	} or {
		MinigameSettings.types.decode_symbols,
		false,
		EXPEDITION_MINIGAME_TYPE,
	}

	for index = 1, #candidate_types do
		local candidate_type = candidate_types[index]
		local minigame = _tag_minigame_type(_try_minigame_extension_minigame(minigame_extension, candidate_type or nil), candidate_type or minigame_type)

		if _looks_like_decode_style_minigame(minigame) then
			return minigame
		end
	end

	return nil
end

local function _decode_style_future_rows(minigame)
	if _looks_like_expedition_minigame(minigame) then
		return 0
	end

	return _should_highlight_decode_targets() and (mod:get("decode_future_rows") or 0) or 0
end

local function _looks_like_frequency_minigame(minigame)
	return minigame and minigame.frequency and minigame.target_frequency and minigame.is_visually_on_target
end

_looks_like_balance_minigame = function(minigame)
	return minigame and minigame.position and minigame.distance and minigame.progression and minigame.uses_joystick and minigame:uses_joystick()
end

_active_decode_autosolve_minigame = function()
	local practice_minigame = _active_practice_minigame()
	local practice_minigame_type = _active_practice_minigame_type()

	if (practice_minigame_type == MinigameSettings.types.decode_symbols or practice_minigame_type == PREVIEW_DECODE_SYMBOLS_12_TYPE) and _looks_like_decode_minigame(practice_minigame) then
		return practice_minigame
	end

	local live_minigame = _active_live_minigame()
	local live_minigame_type = _active_live_minigame_type()

	if (live_minigame_type == nil or live_minigame_type == MinigameSettings.types.decode_symbols) and _looks_like_decode_minigame(live_minigame) then
		return live_minigame
	end

	return nil
end

_active_expedition_autosolve_minigame = function()
	local practice_minigame = _active_practice_minigame()

	if _is_expedition_minigame_type(_active_practice_minigame_type()) and _looks_like_expedition_minigame(practice_minigame) then
		return practice_minigame
	end

	local live_minigame = _active_live_minigame()

	if _is_expedition_minigame_type(_active_live_minigame_type()) and _looks_like_expedition_minigame(live_minigame) then
		return live_minigame
	end

	return nil
end

_active_frequency_autosolve_minigame = function()
	local practice_minigame = _active_practice_minigame()

	if _looks_like_frequency_minigame(practice_minigame) then
		return practice_minigame
	end

	local live_minigame = _active_live_minigame()

	if _looks_like_frequency_minigame(live_minigame) then
		return live_minigame
	end

	return nil
end

_active_drill_autosolve_minigame = function()
	local practice_minigame = _active_practice_minigame()

	if _looks_like_drill_minigame(practice_minigame) then
		return practice_minigame
	end

	local live_minigame = _active_live_minigame()

	if _looks_like_drill_minigame(live_minigame) then
		return live_minigame
	end

	return nil
end

local function _ignore_errors(callback)
	if callback then
		xpcall(callback, function()
			return
		end)
	end
end

local function _force_cancel_local_minigame_state()
	local player_unit = _local_player_unit()

	if not player_unit then
		return
	end

	local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
	local character_state_machine_extension = ScriptUnit.has_extension(player_unit, "character_state_machine_system")

	_ignore_errors(function()
		if character_state_machine_extension and character_state_machine_extension:current_state_name() == "minigame" then
			local current_state = character_state_machine_extension:current_state()

			if current_state and current_state.force_cancel then
				current_state:force_cancel()
			end
		end
	end)

	_ignore_errors(function()
		if not unit_data_extension then
			return
		end

		local minigame_character_state = unit_data_extension:write_component("minigame_character_state")

		if not minigame_character_state then
			return
		end

		minigame_character_state.interface_level_unit_id = NetworkConstants.invalid_level_unit_id
		minigame_character_state.interface_game_object_id = NetworkConstants.invalid_game_object_id
		minigame_character_state.interface_is_level_unit = true
		minigame_character_state.pocketable_device_active = false
	end)
end

local PRACTICE_SOUND_SOURCE_NAME = "_speaker"

local function _with_practice_sound_profile(visual_loadout_extension, callback)
	if not callback then
		return false
	end

	local profile_properties = visual_loadout_extension and visual_loadout_extension.profile_properties and visual_loadout_extension:profile_properties() or nil

	if not profile_properties then
		return callback()
	end

	local previous_weapon_template = profile_properties.wielded_weapon_template

	if previous_weapon_template == PRACTICE_SOUND_WEAPON_TEMPLATE then
		return callback()
	end

	profile_properties.wielded_weapon_template = PRACTICE_SOUND_WEAPON_TEMPLATE

	local ok, result = xpcall(callback, debug.traceback)

	profile_properties.wielded_weapon_template = previous_weapon_template

	if ok then
		return result
	end

	return false
end

local function _trigger_practice_sound_from_source(fx_extension, alias, source_name)
	if not fx_extension or not alias or not source_name then
		return false
	end

	if not fx_extension:sound_source(source_name) then
		return false
	end

	local playing_id = fx_extension:trigger_gear_wwise_event_with_source(alias, nil, source_name, false, true)

	if playing_id then
		return true
	end

	return false
end

local function _trigger_practice_sound_at_position(fx_extension, alias, position)
	if not fx_extension or not alias or not position then
		return false
	end

	if fx_extension.trigger_gear_wwise_event_with_position then
		return not not fx_extension:trigger_gear_wwise_event_with_position(alias, nil, position, false, true)
	end

	return false
end

local function _play_practice_sound_from_slot(visual_loadout_extension, fx_extension, slot_name, alias)
	local fx_sources = slot_name and visual_loadout_extension:source_fx_for_slot(slot_name)

	if type(fx_sources) ~= "table" then
		return false
	end

	local preferred_source_name = fx_sources[PRACTICE_SOUND_SOURCE_NAME]

	if _trigger_practice_sound_from_source(fx_extension, alias, preferred_source_name) then
		return true
	end

	for _, candidate_source_name in pairs(fx_sources) do
		if candidate_source_name ~= preferred_source_name and _trigger_practice_sound_from_source(fx_extension, alias, candidate_source_name) then
			return true
		end
	end

	return false
end

local function _play_practice_sound(alias)
	local player_unit = _local_player_unit()
	local fx_extension = player_unit and ScriptUnit.has_extension(player_unit, "fx_system")
	local unit_data_extension = player_unit and ScriptUnit.has_extension(player_unit, "unit_data_system")
	local visual_loadout_extension = player_unit and ScriptUnit.has_extension(player_unit, "visual_loadout_system")

	if not alias or not fx_extension or not unit_data_extension or not visual_loadout_extension then
		return false
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local wielded_slot = inventory_component and inventory_component.wielded_slot
	local played = _with_practice_sound_profile(visual_loadout_extension, function()
		local tried_slots = {}
		local slot_order = {
			PRACTICE_DEVICE_SLOT,
			wielded_slot,
		}

		for index = 1, #slot_order do
			local slot_name = slot_order[index]

			if slot_name and not tried_slots[slot_name] then
				tried_slots[slot_name] = true

				if _play_practice_sound_from_slot(visual_loadout_extension, fx_extension, slot_name, alias) then
					return true
				end
			end
		end

		local player_position = Unit.alive(player_unit) and Unit.world_position(player_unit, 1) or nil

		if _trigger_practice_sound_at_position(fx_extension, alias, player_position) then
			return true
		end

		if fx_extension.trigger_gear_wwise_event then
			return not not fx_extension:trigger_gear_wwise_event(alias, nil)
		end

		return false
	end)

	return not not played
end

function PreviewMinigameBase:play_sound(alias)
	_play_practice_sound(alias)
end

local function _build_preview_context(minigame_type)
	local minigame_extension = PreviewMinigameExtension:new(minigame_type)
	local display_minigame_type = _preview_display_minigame_type(minigame_type)

	if not minigame_extension then
		return nil
	end

	return {
		auspex_unit = nil,
		auspex_helper_is_practice = true,
		device_owner_unit = _local_player_unit(),
		minigame_extension = minigame_extension,
		minigame_type = display_minigame_type,
	}, minigame_extension
end

local function _minigame_display_mode()
	return mod:get("live_display_mode") or "item"
end

local function _practice_view_name()
	local session = practice_session

	if session and session.view_name then
		return session.view_name
	end

	return _minigame_display_mode() == "item" and STOCK_SCANNER_VIEW_NAME or PREVIEW_VIEW_NAME
end

local _cleanup_preview_session
local _open_preview_view
local _abort_preview_session
local _set_preview_input_simulation

local function _close_view(view_name, force_close)
	local ui_manager = Managers.ui

	if not ui_manager or not view_name then
		return false
	end

	local is_active = ui_manager:view_active(view_name)
	local is_closing = ui_manager:is_view_closing(view_name)

	if not is_active and not is_closing then
		return false
	end

	if force_close then
		_clear_preview_close_request()
	else
		preview_close_requested_at = _gameplay_time()
		preview_close_view_name = view_name
	end

	ui_manager:close_view(view_name, force_close == true)

	if force_close and practice_session and practice_session.view_name == view_name then
		_cleanup_preview_session()
	end

	return true
end

local function _close_preview_view(force_close)
	if practice_session and (practice_session.pending_item_mode or practice_session.item_mode) then
		local should_reopen = preview_reopen_requested and _is_mod_active() and mod:get("enable_preview")

		_abort_preview_session()

		if should_reopen then
			preview_reopen_requested = false
			_open_preview_view()
		end

		return true
	end

	return _close_view(_practice_view_name(), force_close)
end

local function _apply_mod_override_state()
	if not _is_mod_active() then
		_reset_decode_autosolve()
		_reset_expedition_autosolve()
		_reset_drill_autosolve()
		_reset_frequency_autosolve()
		_reset_balance_autosolve()
		mod._world_scan_next_refresh_t = nil
		mod._world_scan_next_visibility_refresh_t = nil

		preview_reopen_requested = false
		_reset_scanner_fade_state()

		_apply_scanner_current_alpha()
		_set_world_scan_highlights(false)
		_close_preview_view(false)
		_close_view(OVERLAY_VIEW_NAME, true)
		_close_view(WORLD_SCAN_VIEW_NAME, true)
		_close_view(WORLD_SCAN_ICONS_VIEW_NAME, true)
		_sync_scanner_hud_visibility()

		return
	end

	if _world_scan_effective_active() then
		_set_world_scan_highlights(true)
	end

	_sync_scanner_hud_visibility()
end

local function _practice_scanner_item()
	if practice_scanner_item and practice_scanner_item_name then
		return practice_scanner_item, practice_scanner_item_name
	end

	local t = _gameplay_time()

	if practice_scanner_item_lookup_complete and t < practice_scanner_item_retry_at then
		return nil, nil
	end

	for index = 1, #PRACTICE_ITEM_IDS do
		local item_name = PRACTICE_ITEM_IDS[index]
		local item = MasterItems.get_item(item_name)

		if item then
			practice_scanner_item = item
			practice_scanner_item_name = item_name
			practice_scanner_item_lookup_complete = true

			return item, item_name
		end
	end

	practice_scanner_item_lookup_complete = true
	practice_scanner_item_retry_at = t + 5

	return nil, nil
end

_practice_auspex_unit = function(player_unit)
	local visual_loadout_extension = player_unit and ScriptUnit.has_extension(player_unit, "visual_loadout_system")
	local item_unit_1p = visual_loadout_extension and visual_loadout_extension:unit_and_attachments_from_slot(PRACTICE_DEVICE_SLOT)

	return item_unit_1p
end

_is_practice_auspex_ready = function(auspex_unit)
	if not auspex_unit or not Unit.alive(auspex_unit) then
		return false
	end

	if not ScriptUnit.has_extension(auspex_unit, "scanner_display_system") then
		return false
	end

	local ok, plane_mesh = pcall(Unit.mesh, auspex_unit, "auspex_scanner_display")

	return ok and plane_mesh ~= nil
end

_practice_interface_unit = function(player_unit)
	local unit_data_extension = player_unit and ScriptUnit.has_extension(player_unit, "unit_data_system")
	local minigame_character_state = unit_data_extension and unit_data_extension:read_component("minigame_character_state")

	if not minigame_character_state then
		return nil
	end

	local is_level_unit = minigame_character_state.interface_is_level_unit
	local unit_id = is_level_unit and minigame_character_state.interface_level_unit_id or minigame_character_state.interface_game_object_id
	local has_interface = unit_id ~= nil and unit_id ~= NetworkConstants.invalid_level_unit_id and unit_id ~= NetworkConstants.invalid_game_object_id

	if not has_interface then
		return nil
	end

	local unit_spawner = Managers.state and Managers.state.unit_spawner

	return unit_spawner and unit_spawner:unit(unit_id, is_level_unit) or nil
end

_is_practice_interface_ready = function(interface_unit)
	return interface_unit ~= nil and Unit.alive(interface_unit) and ScriptUnit.has_extension(interface_unit, "minigame_system") ~= nil
end

_set_practice_item_focus_active = function(session, active)
	if not session or not session.player_unit then
		return false
	end

	local player_unit = session.player_unit
	local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
	local character_state_machine_extension = ScriptUnit.has_extension(player_unit, "character_state_machine_system")
	local animation_extension = ScriptUnit.has_extension(player_unit, "animation_system")

	if not unit_data_extension then
		return false
	end

	local minigame_character_state = unit_data_extension:write_component("minigame_character_state")
	local active_value = active == true

	minigame_character_state.pocketable_device_active = active_value

	if animation_extension and session.item_focus_active ~= active_value then
		animation_extension:anim_event_1p(active_value and "auspex_start_focus" or "auspex_stop_focus")
	end

	session.item_focus_active = active_value

	if active_value then
		session.item_focus_requested_at = _gameplay_time()
	else
		if character_state_machine_extension and character_state_machine_extension:current_state_name() == "minigame" then
			local current_state = character_state_machine_extension:current_state()

			if current_state and current_state.force_cancel then
				current_state:force_cancel()
			end
		end

		session.item_minigame_bound = false
	end

	return true
end

_open_preview_session_view = function(session)
	local ui_manager = Managers.ui

	if not ui_manager or not session or not session.view_name or not session.context then
		return false
	end

	if ui_manager:view_active(session.view_name) or ui_manager:is_view_closing(session.view_name) then
		return false
	end

	ui_manager:open_view(session.view_name, nil, false, false, nil, session.context, {
		use_transition_ui = false,
	})

	session.opened_at = _gameplay_time()

	if session.view_name == PREVIEW_VIEW_NAME or session.view_name == OVERLAY_VIEW_NAME then
		_refresh_scanner_overlay_state()
	end

	return true
end

_overlay_preview_view_is_active = function(session)
	local ui_manager = Managers.ui

	if not ui_manager or not session or session.item_mode or session.pending_item_mode or not session.view_name then
		return false
	end

	return ui_manager:view_active(session.view_name) and not ui_manager:is_view_closing(session.view_name)
end

_close_world_scan_views = function()
	_suppress_world_scan_views(0.35)
	_close_view(WORLD_SCAN_VIEW_NAME, true)
	_close_view(WORLD_SCAN_ICONS_VIEW_NAME, true)
	_refresh_scanner_overlay_state()
end

_start_preview_minigame = function(session, player)
	local minigame = session and session.minigame

	if not minigame or session.minigame_started then
		return false
	end

	if minigame.setup_game then
		minigame:setup_game()
	end

	if minigame.start then
		minigame:start(player or _local_player())
	end

	session.minigame_started = true

	return true
end

_open_overlay_preview_session = function(session, show_item_warning)
	if not session or not session.context then
		return false
	end

	session.auspex_unit = nil
	session.item_mode = false
	session.pending_item_mode = false
	session.player_unit = nil
	session.view_name = PREVIEW_VIEW_NAME
	session.context.auspex_unit = nil
	session.context.device_owner_unit = _local_player_unit()
	session.next_view_open_retry_at = 0
	session.overlay_view_ready = false
	session.allow_missing_gameplay_timer = not _has_gameplay_timer()
	mod._preview_allow_missing_gameplay_timer = session.allow_missing_gameplay_timer == true
	practice_session = session
	_close_world_scan_views()

	local opened = _open_preview_session_view(session)

	if show_item_warning then
		mod:notify(mod:localize("practice_item_unavailable"))
	end

	return opened
end

_try_open_pending_item_preview = function(session)
	if not session or not session.pending_item_mode or not session.player_unit or not session.context then
		return false
	end

	if session.pending_item_ready_at and _gameplay_time() < session.pending_item_ready_at then
		return false
	end

	local auspex_unit = _practice_auspex_unit(session.player_unit)
	local interface_unit = _practice_interface_unit(session.player_unit)

	if not _is_practice_auspex_ready(auspex_unit) or not _is_practice_interface_ready(interface_unit) then
		return false
	end

	session.auspex_unit = auspex_unit
	session.interface_unit = interface_unit
	session.pending_item_mode = false
	session.context.auspex_unit = auspex_unit
	session.context.device_owner_unit = session.player_unit
	session.context.interface_unit = interface_unit

	return _set_practice_item_focus_active(session, true)
end

_equip_practice_scanner = function()
	local player_unit = _local_player_unit()
	local unit_data_extension = player_unit and ScriptUnit.has_extension(player_unit, "unit_data_system")
	local visual_loadout_extension = player_unit and ScriptUnit.has_extension(player_unit, "visual_loadout_system")

	if not player_unit or not unit_data_extension or not visual_loadout_extension then
		return nil
	end

	local scanner_item, scanner_item_name = _practice_scanner_item()

	if not scanner_item or not scanner_item_name then
		return nil
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local current_device_item_name = inventory_component[PRACTICE_DEVICE_SLOT]
	local current_wielded_slot = inventory_component.wielded_slot
	local t = _gameplay_time()
	local equipped_practice_device = current_device_item_name ~= scanner_item_name

	if equipped_practice_device then
		if PlayerUnitVisualLoadout.slot_equipped(inventory_component, visual_loadout_extension, PRACTICE_DEVICE_SLOT) then
			PlayerUnitVisualLoadout.unequip_item_from_slot(player_unit, PRACTICE_DEVICE_SLOT, t)
		end

		PlayerUnitVisualLoadout.equip_item_to_slot(player_unit, scanner_item, PRACTICE_DEVICE_SLOT, nil, t)
	end

	if current_wielded_slot ~= PRACTICE_DEVICE_SLOT then
		PlayerUnitVisualLoadout.wield_slot(PRACTICE_DEVICE_SLOT, player_unit, t)
	end

	return {
		equipped_practice_device = equipped_practice_device,
		player_unit = player_unit,
		previous_device_item_name = current_device_item_name,
		previous_wielded_slot = current_wielded_slot,
	}
end

_try_equip_practice_scanner = function()
	local ok, result_or_error = xpcall(_equip_practice_scanner, debug.traceback)

	if ok then
		return result_or_error, nil
	end

	return nil, result_or_error
end

_restore_practice_scanner = function(session)
	if not session or not session.player_unit then
		return
	end

	local player_unit = session.player_unit
	local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
	local visual_loadout_extension = ScriptUnit.has_extension(player_unit, "visual_loadout_system")

	if not unit_data_extension or not visual_loadout_extension then
		return
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local t = _gameplay_time()

	if session.equipped_practice_device then
		local previous_item_name = session.previous_device_item_name

		if previous_item_name and previous_item_name ~= "not_equipped" then
			local previous_item = MasterItems.get_item(previous_item_name)

			if previous_item then
				PlayerUnitVisualLoadout.equip_item_to_slot(player_unit, previous_item, PRACTICE_DEVICE_SLOT, nil, t)
			else
				PlayerUnitVisualLoadout.unequip_item_from_slot(player_unit, PRACTICE_DEVICE_SLOT, t)
			end
		else
			PlayerUnitVisualLoadout.unequip_item_from_slot(player_unit, PRACTICE_DEVICE_SLOT, t)
		end
	end

	local previous_wielded_slot = session.previous_wielded_slot

	if previous_wielded_slot and previous_wielded_slot ~= "none" and inventory_component.wielded_slot ~= previous_wielded_slot and visual_loadout_extension:can_wield(previous_wielded_slot) then
		PlayerUnitVisualLoadout.wield_slot(previous_wielded_slot, player_unit, t)
	end
end

_practice_item_mode_supported_here = function()
	local game_mode_manager = Managers.state and Managers.state.game_mode
	local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name() or nil

	return game_mode_name ~= nil and game_mode_name ~= "hub" and game_mode_name ~= "prologue_hub"
end

_live_item_mode_supported_here = function()
	local connection_manager = Managers.connection
	local host_type = connection_manager and connection_manager:host_type() or nil

	return host_type == nil or host_type == "singleplay" or host_type == "singleplay_backend_session"
end

_live_item_state_is_unsafe = function(state_name)
	return state_name == "hogtied" or state_name == "netted" or state_name == "pounced" or state_name == "grabbed" or state_name == "warp_grabbed" or state_name == "mutant_charged" or state_name == "knocked_down" or state_name == "dead" or state_name == "consumed" or state_name == "exploding" or state_name == "ledge_hanging" or state_name == "ledge_hanging_falling" or state_name == "ledge_hanging_pull_up" or state_name == "stunned"
end

_notify_live_item_overlay_fallback = function()
	local t = _gameplay_time()
	local next_allowed_t = mod._live_item_overlay_notify_t or 0

	if t < next_allowed_t then
		return
	end

	mod._live_item_overlay_notify_t = t + 5

	mod:notify(mod:localize("live_item_online_unavailable"))
end

_abort_live_item_scanner_if_unsafe = function()
	if practice_session or _minigame_display_mode() ~= "item" then
		return false
	end

	local ui_manager = Managers.ui

	if not ui_manager then
		return false
	end

	local stock_view_active = ui_manager:view_active(STOCK_SCANNER_VIEW_NAME) or ui_manager:is_view_closing(STOCK_SCANNER_VIEW_NAME)

	if not stock_view_active and not scanner_equipped_active and not scanner_searching_active then
		return false
	end

	local player_unit = _local_player_unit()
	local character_state_machine_extension = player_unit and ScriptUnit.has_extension(player_unit, "character_state_machine_system")
	local state_name = character_state_machine_extension and character_state_machine_extension:current_state_name() or nil

	if not _live_item_state_is_unsafe(state_name) then
		return false
	end

	_ignore_errors(function()
		_close_view(STOCK_SCANNER_VIEW_NAME, true)
	end)
	_ignore_errors(function()
		_force_cancel_local_minigame_state()
	end)
	_set_scanner_searching_state(false)
	_set_scanner_equipped_state(false)

	return true
end

function _cleanup_preview_session()
	if not practice_session then
		mod._preview_allow_missing_gameplay_timer = false
		_set_preview_input_simulation(false)

		return
	end

	local session = practice_session

	mod._preview_allow_missing_gameplay_timer = false
	_set_preview_input_simulation(false)

	if session.item_mode then
		_ignore_errors(function()
			_set_practice_item_focus_active(session, false)
		end)

		_ignore_errors(function()
			_restore_practice_scanner(session)
		end)
	end

	practice_session = nil
end

function _abort_preview_session()
	local ui_manager = Managers.ui

	_clear_preview_close_request()
	preview_reopen_requested = false

	if practice_session and practice_session.item_mode then
		_ignore_errors(function()
			_set_practice_item_focus_active(practice_session, false)
		end)
	end

	if ui_manager then
		if ui_manager:view_active(PREVIEW_VIEW_NAME) or ui_manager:is_view_closing(PREVIEW_VIEW_NAME) then
			ui_manager:close_view(PREVIEW_VIEW_NAME, true)
		end

		if ui_manager:view_active(STOCK_SCANNER_VIEW_NAME) or ui_manager:is_view_closing(STOCK_SCANNER_VIEW_NAME) then
			ui_manager:close_view(STOCK_SCANNER_VIEW_NAME, true)
		end
	end

	_cleanup_preview_session()
end

function _open_preview_view()
	local ui_manager = Managers.ui

	if not ui_manager then
		return
	end

	local view_name = _practice_view_name()

	if ui_manager:view_active(view_name) or ui_manager:is_view_closing(view_name) then
		return
	end

	local minigame_type = mod:get("preview_type") or MinigameSettings.types.decode_symbols

	if not _is_minigame_enabled(minigame_type) then
		mod:notify(mod:localize("preview_type_disabled"))

		return
	end

	if _is_expedition_minigame_type(minigame_type) then
		mod:notify(mod:localize("preview_type_expedition_placeholder"))

		return
	end

	local context, minigame_extension = _build_preview_context(minigame_type)

	if not context or not minigame_extension then
		mod:notify(mod:localize("preview_unavailable"))

		return
	end

	local session = {
		context = context,
		item_mode = false,
		minigame = minigame_extension:minigame(),
		minigame_started = false,
		minigame_extension = minigame_extension,
		minigame_type = minigame_type,
		opened_at = _gameplay_time(),
		previous_action_one_hold = false,
		previous_interact_hold = false,
		previous_jump_held = false,
		previous_primary_input = false,
		primary_hold = false,
		view_name = PREVIEW_VIEW_NAME,
	}

	if _minigame_display_mode() == "item" then
		if not _practice_item_mode_supported_here() then
			mod:notify(mod:localize("practice_item_hub_unavailable"))
			_open_overlay_preview_session(session)

			return
		end

		local device_session = nil

		device_session = _try_equip_practice_scanner()

		if device_session then
			context.device_owner_unit = device_session.player_unit
			session.equipped_practice_device = device_session.equipped_practice_device
			session.item_mode = true
			session.item_minigame_bound = false
			session.pending_item_mode = true
			session.pending_item_ready_at = _gameplay_time() + 0.1
			session.player_unit = device_session.player_unit
			session.previous_device_item_name = device_session.previous_device_item_name
			session.previous_wielded_slot = device_session.previous_wielded_slot
			session.view_name = STOCK_SCANNER_VIEW_NAME
			practice_session = session
			_try_open_pending_item_preview(session)
			session.opened_at = _gameplay_time()
		else
			_open_overlay_preview_session(session, true)
		end
	else
		_open_overlay_preview_session(session, _minigame_display_mode() == "item")
	end
end

mod:register_view({
	view_name = PREVIEW_VIEW_NAME,
	view_settings = {
		allow_hud = true,
		class = "AuspexOverlayView",
		close_on_hotkey_pressed = false,
		disable_game_world = false,
		init_view_function = function()
			return true
		end,
		load_always = true,
		load_in_hub = true,
		package = "packages/ui/views/scanner_display_view/scanner_display_view",
		path = OVERLAY_VIEW_PATH,
		state_bound = false,
		use_transition_ui = false,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
		close_transition_time = nil,
		transition_time = nil,
	},
})

mod:register_view({
	view_name = OVERLAY_VIEW_NAME,
	view_settings = {
		allow_hud = true,
		class = "AuspexOverlayView",
		close_on_hotkey_pressed = false,
		disable_game_world = false,
		init_view_function = function()
			return true
		end,
		load_always = true,
		load_in_hub = false,
		package = "packages/ui/views/scanner_display_view/scanner_display_view",
		path = OVERLAY_VIEW_PATH,
		state_bound = false,
		use_transition_ui = false,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
		close_transition_time = nil,
		transition_time = nil,
	},
})

mod:register_view({
	view_name = WORLD_SCAN_VIEW_NAME,
	view_settings = {
		allow_hud = true,
		class = "AuspexOverlayView",
		close_on_hotkey_pressed = false,
		disable_game_world = false,
		init_view_function = function()
			return true
		end,
		load_always = true,
		load_in_hub = false,
		package = "packages/ui/views/scanner_display_view/scanner_display_view",
		path = OVERLAY_VIEW_PATH,
		state_bound = false,
		use_transition_ui = false,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
		close_transition_time = nil,
		transition_time = nil,
	},
})

mod:register_view({
	view_name = WORLD_SCAN_ICONS_VIEW_NAME,
	view_settings = {
		allow_hud = true,
		class = "AuspexOverlayView",
		close_on_hotkey_pressed = false,
		disable_game_world = false,
		init_view_function = function()
			return true
		end,
		load_always = true,
		load_in_hub = false,
		package = "packages/ui/views/scanner_display_view/scanner_display_view",
		path = OVERLAY_VIEW_PATH,
		state_bound = false,
		use_transition_ui = false,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
		close_transition_time = nil,
		transition_time = nil,
	},
})

mod:hook_require("scripts/managers/ui/ui_view_handler", function(UIViewHandler)
	mod:hook(UIViewHandler, "allow_to_pass_input_for_view", function(func, self, view_name)
		if _is_auspex_helper_pass_through_view(view_name) then
			return true
		end

		return func(self, view_name)
	end)

	mod:hook(UIViewHandler, "allow_close_hotkey_for_view", function(func, self, view_name)
		if _is_auspex_helper_pass_through_view(view_name) then
			return false
		end

		return func(self, view_name)
	end)
end)

mod:hook_require("scripts/managers/ui/ui_manager", function(UIManager)
	local UIViews = require("scripts/ui/views/views")

	mod:hook(UIManager, "_update_view_hotkeys", function(func, self)
		if self._ui_constant_elements:using_input() then
			return
		end

		local view_handler = self._view_handler

		if view_handler:transitioning() then
			return
		end

		local views = view_handler:active_views()
		local filtered_views = {}

		for i = 1, #views do
			local view_name = views[i]

			if view_name and not _is_auspex_helper_pass_through_view(view_name) then
				filtered_views[#filtered_views + 1] = view_name
			end
		end

		if #filtered_views == #views then
			return func(self)
		end

		local input_service = self:input_service()
		local hotkey_settings = self._update_hotkeys
		local hotkeys = hotkey_settings.hotkeys
		local hotkey_lookup = hotkey_settings.lookup
		local gamepad_active = InputDevice.gamepad_active
		local num_views = #filtered_views

		if num_views > 0 then
			for i = num_views, 1, -1 do
				local active_view_name = filtered_views[i]

				if active_view_name then
					local settings = UIViews[active_view_name]

					if not settings then
						return func(self)
					end

					local hotkey = hotkey_lookup[active_view_name]
					local close_on_hotkey = settings.close_on_hotkey_pressed
					local close_on_gamepad = settings.close_on_hotkey_gamepad
					local can_close_with_hotkey = close_on_hotkey and (not gamepad_active or close_on_gamepad)
					local close_by_hotkey = hotkey and can_close_with_hotkey and input_service:get(hotkey)
					local close_action = self._close_view_input_action
					local close_by_action = view_handler:allow_close_hotkey_for_view(active_view_name) and input_service:get(close_action)
					local should_close_view = close_by_hotkey or close_by_action
					local can_close_view = view_handler:can_close(active_view_name)

					if should_close_view and can_close_view then
						self:close_view(active_view_name)

						return
					end

					local allow_to_pass_input = view_handler:allow_to_pass_input_for_view(active_view_name)

					if not allow_to_pass_input then
						return
					end
				end
			end
		else
			for hotkey, view_name in pairs(hotkeys) do
				if input_service:get(hotkey) then
					self:open_view(view_name)

					return
				end
			end
		end
	end)
end)

mod:add_require_path(OVERLAY_VIEW_PATH)
mod:io_dofile(OVERLAY_VIEW_PATH)

mod:hook_require("scripts/extension_systems/minigame/minigames/minigame_base", function(MinigameBase)
	mod:hook(MinigameBase, "_setup_sound", function(func, self, player, fx_source_name)
		local player_unit = player and player.player_unit

		if not player_unit or not Unit.alive(player_unit) then
			return
		end

		local visual_loadout_extension = ScriptUnit.has_extension(player_unit, "visual_loadout_system")
		local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")

		self._fx_extension = ScriptUnit.has_extension(player_unit, "fx_system")
		self._fx_source_name = nil

		if not visual_loadout_extension or not unit_data_extension then
			return
		end

		local inventory_component = unit_data_extension:read_component("inventory")
		local tried_slots = {}
		local slot_order = {
			inventory_component and inventory_component.wielded_slot,
			"slot_device",
			"slot_pocketable_small",
			"slot_primary",
			"slot_secondary",
		}

		for index = 1, #slot_order do
			local slot_name = slot_order[index]

			if slot_name and not tried_slots[slot_name] then
				tried_slots[slot_name] = true

				local fx_sources = visual_loadout_extension:source_fx_for_slot(slot_name)

				if type(fx_sources) == "table" then
					self._fx_source_name = fx_sources[fx_source_name]

					if not self._fx_source_name then
						for _, candidate_source_name in pairs(fx_sources) do
							self._fx_source_name = candidate_source_name

							break
						end
					end

					if self._fx_source_name then
						return
					end
				end
			end
		end
	end)
end)

mod:hook_require("scripts/extension_systems/character_state_machine/character_states/player_character_state_minigame", function(PlayerCharacterStateMinigame)
	mod:hook(PlayerCharacterStateMinigame, "_check_initialize_minigame_from_unit", function(func, self)
		local session = practice_session

		if not session or not session.item_mode or not session.minigame or self._unit ~= session.player_unit then
			local minigame_character_state = self._minigame_character_state_component
			local is_unit_synced = minigame_character_state and (minigame_character_state.interface_level_unit_id ~= NetworkConstants.invalid_level_unit_id or minigame_character_state.interface_game_object_id ~= NetworkConstants.invalid_game_object_id)

			if is_unit_synced and minigame_character_state and not minigame_character_state.pocketable_device_active then
				local inventory_component = self._inventory_component
				local wielded_slot = inventory_component and inventory_component.wielded_slot

				if wielded_slot == "slot_device" or wielded_slot == "slot_pocketable_small" then
					local visual_loadout_extension = self._visual_loadout_extension
					local weapon_template = visual_loadout_extension and visual_loadout_extension:weapon_template_from_slot(wielded_slot)

					if weapon_template and weapon_template.require_minigame and not weapon_template.not_player_wieldable then
						minigame_character_state.pocketable_device_active = true
					end
				end
			end

			return func(self)
		end

		local interface_unit = _practice_interface_unit(session.player_unit)

		if not _is_practice_interface_ready(interface_unit) then
			return false
		end

		session.interface_unit = interface_unit
		self._minigame = session.minigame
		session.item_minigame_bound = true

		_start_preview_minigame(session, self._player)

		return true
	end)
end)

mod:hook_require("scripts/extension_systems/scanner_display/scanner_display_extension", function(ScannerDisplayExtension)
	mod:hook(ScannerDisplayExtension, "_open_view", function(func, self, ui_manager, device_owner_unit, interface_unit)
		local session = practice_session

		if session and session.item_mode and session.context then
			local view_name = self._view_name
			local view_context = session.context

			view_context.auspex_unit = self._unit
			view_context.device_owner_unit = device_owner_unit or session.player_unit
			view_context.interface_unit = interface_unit or session.interface_unit
			session.auspex_unit = self._unit
			session.item_view_opened = true
			session.opened_at = _gameplay_time()

			if not ui_manager:view_active(view_name) and not ui_manager:is_view_closing(view_name) then
				ui_manager:open_view(view_name, nil, nil, nil, nil, view_context)
			end

			return
		end

		local use_overlay = _minigame_display_mode() == "overlay"
		local minigame_extension = interface_unit and ScriptUnit.has_extension(interface_unit, "minigame_system") or nil
		local minigame_type = minigame_extension and minigame_extension:minigame_type() or nil
		local live_minigame = _tag_minigame_type(_try_minigame_extension_minigame(minigame_extension), minigame_type)

		if live_minigame then
			mod._cached_live_minigame_type = minigame_type
		end

		if not use_overlay and interface_unit and minigame_extension and minigame_type and _is_minigame_enabled(minigame_type) and not _live_item_mode_supported_here() then
			use_overlay = true
			_notify_live_item_overlay_fallback()
		end

		if not use_overlay or not interface_unit then
			return func(self, ui_manager, device_owner_unit, interface_unit)
		end

		if not minigame_extension or not minigame_type or not _is_minigame_enabled(minigame_type) then
			return func(self, ui_manager, device_owner_unit, interface_unit)
		end

		if ui_manager:is_view_closing(OVERLAY_VIEW_NAME) then
			return
		end

		if ui_manager:view_active(STOCK_SCANNER_VIEW_NAME) then
			ui_manager:close_view(STOCK_SCANNER_VIEW_NAME, true)
		end

		if ui_manager:view_active(WORLD_SCAN_VIEW_NAME) then
			ui_manager:close_view(WORLD_SCAN_VIEW_NAME, true)
		end

		if ui_manager:view_active(WORLD_SCAN_ICONS_VIEW_NAME) then
			ui_manager:close_view(WORLD_SCAN_ICONS_VIEW_NAME, true)
		end

		if ui_manager:view_active(OVERLAY_VIEW_NAME) then
			ui_manager:close_view(OVERLAY_VIEW_NAME, true)
		end

		ui_manager:open_view(OVERLAY_VIEW_NAME, nil, false, false, nil, {
			auspex_unit = self._unit,
			auspex_helper_is_practice = false,
			device_owner_unit = device_owner_unit,
			minigame_extension = minigame_extension,
			minigame_type = minigame_type,
			wwise_world = self._wwise_world,
		}, {
			use_transition_ui = false,
		})
		_refresh_scanner_overlay_state()
	end)

	mod:hook_safe(ScannerDisplayExtension, "deactivate", function()
		mod._cached_live_minigame_type = nil

		local ui_manager = Managers.ui

		if ui_manager and ui_manager:view_active(OVERLAY_VIEW_NAME) then
			ui_manager:close_view(OVERLAY_VIEW_NAME)
		end
	end)
end)

function mod.toggle_preview()
	if not _is_mod_active() or not mod:get("enable_preview") then
		return
	end

	local ui_manager = Managers.ui

	if not ui_manager then
		return
	end

	if ui_manager.chat_using_input and ui_manager:chat_using_input() then
		return
	end

	if practice_session or preview_close_requested_at then
		_abort_preview_session()

		return
	end

	_open_preview_view()
end

mod:command("auspex_preview", "Toggle the AuspexHelper practice scanner.", function()
	mod.toggle_preview()
end)

mod:command("auspex_practice", "Toggle the AuspexHelper practice scanner.", function()
	mod.toggle_preview()
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "init", function()
	_refresh_scannable_units()

	if _world_scan_effective_active() then
		_set_world_scan_highlights(true)
	end
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "wield", function()
	scanner_world_helper_active = true

	_request_world_scan_refresh(true)
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "unwield", function()
	scanner_world_helper_active = false
	_set_scanner_searching_state(false)

	_request_world_scan_refresh(true)
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "destroy", function()
	scanner_world_helper_active = false
	_set_scanner_searching_state(false)

	_request_world_scan_refresh(true)
end)

mod:hook_require("scripts/extension_systems/mission_objective_zone/mission_objective_zone_system", function(MissionObjectiveZoneSystem)
	mod:hook_safe(MissionObjectiveZoneSystem, "activate_zone", function(self, unit)
		_request_world_scan_refresh(true)
	end)

	mod:hook_safe(MissionObjectiveZoneSystem, "rpc_event_mission_objective_zone_activate_zone", function(self, channel_id, level_unit_id)
		_request_world_scan_refresh(true)
	end)

	mod:hook_safe(MissionObjectiveZoneSystem, "register_scannable_unit", function(self, scannable_unit)
		_request_world_scan_refresh(false)
	end)
end)

mod:hook_require("scripts/extension_systems/mission_objective_zone_scannable/mission_objective_zone_scannable_extension", function(MissionObjectiveZoneScannableExtension)
	mod:hook_safe(MissionObjectiveZoneScannableExtension, "set_active", function(self, active)
		local unit = self._unit

		if not unit then
			return
		end

		if active then
			_request_world_scan_refresh(true)

			return
		end

		self:set_scanning_outline(false)
		self:set_scanning_highlight(false)

		if mod._world_scan_unit_color_signatures then
			mod._world_scan_unit_color_signatures[unit] = nil
		end

		if mod._world_scan_highlighted_units then
			mod._world_scan_highlighted_units[unit] = nil
		end

		if mod._world_scan_icon_units then
			mod._world_scan_icon_units[unit] = nil
			_refresh_world_scan_icons_view()
		end
	end)

	mod:hook_safe(MissionObjectiveZoneScannableExtension, "set_scanning_outline", function(self, active)
		if active then
			_apply_world_scan_outline_color_to_unit(self._unit)
		end
	end)

	mod:hook_safe(MissionObjectiveZoneScannableExtension, "set_scanning_highlight", function(self, active)
		if active then
			_apply_world_scan_outline_color_to_unit(self._unit)
		end
	end)
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "_run_searching_sfx_loop", function(self)
	if self._is_husk then
		return
	end

	_set_scanner_searching_state(true)
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "_stop_scan_units_effects", function(self)
	if self._is_husk then
		return
	end

	_set_scanner_searching_state(false)
end)

mod:hook_safe(CLASS.AuspexEffects, "wield", function(self)
	if self._is_husk then
		return
	end

	_set_scanner_equipped_state(true)
	_request_world_scan_refresh(true)
end)

mod:hook_safe(CLASS.AuspexEffects, "unwield", function(self)
	if self._is_husk then
		return
	end

	_set_scanner_equipped_state(false)
	_set_scanner_searching_state(false)
	_request_world_scan_refresh(true)
end)

mod:hook_require("scripts/ui/views/scanner_display_view/minigame_decode_symbols_view", function(MinigameDecodeSymbolsView)
	function MinigameDecodeSymbolsView:_create_symbol_widgets()
		local minigame_extension = self._minigame_extension
		local minigame = _resolve_decode_style_minigame(minigame_extension)

		if not minigame then
			return
		end

		local symbols = minigame:symbols()

		if #symbols <= 0 then
			return
		end

		local scenegraph_id = "center_pivot"
		local layout = _decode_layout(minigame)
		local stage_amount = layout.stage_amount
		local symbols_per_stage = MinigameSettings.decode_symbols_items_per_stage
		local widget_size = layout.widget_size
		local starting_offset_x = layout.starting_offset_x
		local starting_offset_y = layout.starting_offset_y
		local spacing = layout.spacing
		local material_path = "content/ui/materials/backgrounds/scanner/"
		local material_prefix = "scanner_decode_"
		local grid_widgets = {}

		for stage = 1, stage_amount do
			for symbol_index = 1, symbols_per_stage do
				local widget_name = "symbol_"
				local symbol_id = symbols[#grid_widgets + 1]

				if symbol_id < 10 then
					widget_name = widget_name .. "0" .. tostring(symbol_id)
				else
					widget_name = widget_name .. tostring(symbol_id)
				end

				local widget_definition = UIWidget.create_definition({
					{
						pass_type = "texture",
						value = material_path .. material_prefix .. widget_name,
						style = {
							hdr = true,
							color = {
								255,
								0,
								255,
								0,
							},
						},
					},
				}, scenegraph_id, nil, widget_size)
				local widget = UIWidget.init(widget_name, widget_definition)

				grid_widgets[#grid_widgets + 1] = widget

				local offset = widget.offset

				offset[1] = starting_offset_x + (widget_size[1] + spacing) * (symbol_index - 1)
				offset[2] = starting_offset_y + (widget_size[2] + spacing) * (stage - 1)
			end
		end

		self._grid_widgets = grid_widgets
	end

	function MinigameDecodeSymbolsView:_draw_cursor(widgets_by_name, decode_start_time, on_target, gameplay_time)
		local minigame_extension = self._minigame_extension
		local minigame = _resolve_decode_style_minigame(minigame_extension)

		if not minigame then
			return
		end

		local current_decode_stage = minigame:current_stage()
		local symbols_per_stage = MinigameSettings.decode_symbols_items_per_stage
		local cursor_position = self:_get_cursor_position_from_time(decode_start_time, gameplay_time)
		local widget_target = widgets_by_name.symbol_frame
		local layout = _decode_layout(minigame)
		local widget_size = layout.widget_size
		local spacing = layout.spacing
		local starting_offset_x = layout.starting_offset_x
		local starting_offset_y = layout.starting_offset_y

		widget_target.style.frame.offset[1] = starting_offset_x + (widget_size[1] + spacing) * ((symbols_per_stage - 1) * cursor_position)
		widget_target.style.frame.offset[2] = starting_offset_y + (widget_size[2] + spacing) * (current_decode_stage - 1)
		widget_target.style.frame.offset[3] = 1

		widget_target.style.frame.color = _ui_highlight_color()
	end

	function MinigameDecodeSymbolsView:_draw_targets(widgets_by_name, decode_start_time, on_target)
		local minigame_extension = self._minigame_extension
		local minigame = _resolve_decode_style_minigame(minigame_extension)

		if not minigame then
			return
		end

		local decode_target = minigame:current_decode_target()
		local current_decode_stage = minigame:current_stage()
		local widget_target = widgets_by_name.symbol_highlight
		local layout = _decode_layout(minigame)
		local widget_size = layout.widget_size
		local spacing = layout.spacing
		local starting_offset_x = layout.starting_offset_x
		local starting_offset_y = layout.starting_offset_y

		widget_target.style.highlight.offset[1] = starting_offset_x + (widget_size[1] + spacing) * (decode_target - 1)
		widget_target.style.highlight.offset[2] = starting_offset_y + (widget_size[2] + spacing) * (current_decode_stage - 1)
		widget_target.style.highlight.color = _ui_highlight_color()
	end
end)

mod:hook_safe(CLASS.MinigameDecodeSymbolsView, "_draw_targets", function(self, widgets_by_name)
	local highlight_widget = widgets_by_name and widgets_by_name.symbol_highlight

	if highlight_widget and highlight_widget.style and highlight_widget.style.highlight then
		highlight_widget.style.highlight.color = _ui_highlight_color()
	end

	local minigame_extension = self._minigame_extension
	local minigame = _resolve_decode_style_minigame(minigame_extension)
	local decode_targets = minigame and minigame._decode_targets or nil
	local current_stage = minigame and minigame:current_stage() or nil
	local reveal_future_rows = _decode_style_future_rows(minigame)

	if not current_stage or not decode_targets then
		self._auspex_helper_decode_visible_count = 0

		return
	end

	local last_stage = math.min(#decode_targets, current_stage + reveal_future_rows)
	local visible_count = last_stage - current_stage + 1
	local layout = _decode_layout(minigame)
	local widget_size = layout.widget_size
	local starting_offset_x = layout.starting_offset_x
	local starting_offset_y = layout.starting_offset_y
	local spacing = layout.spacing
	local widgets = _ensure_decode_overlay_widgets(self, visible_count, widget_size)

	if not widgets then
		self._auspex_helper_decode_visible_count = 0

		return
	end

	for stage = current_stage, last_stage do
		local widget_index = stage - current_stage + 1
		local widget = widgets[widget_index]
		local target = decode_targets[stage] or 1

		widget.style.highlight.color = _ui_highlight_color()
		widget.offset[1] = starting_offset_x + (widget_size[1] + spacing) * (target - 1)
		widget.offset[2] = starting_offset_y + (widget_size[2] + spacing) * (stage - 1)
		widget.offset[3] = 6
	end

	self._auspex_helper_decode_visible_count = visible_count
end)

mod:hook_safe(CLASS.MinigameDecodeSymbolsView, "draw_widgets", function(self, dt, t, input_service, ui_renderer)
	local widgets = self._auspex_helper_decode_widgets
	local visible_count = self._auspex_helper_decode_visible_count or 0

	if not widgets then
		return
	end

	for index = 1, visible_count do
		UIWidget.draw(widgets[index], ui_renderer)
	end
end)

mod:hook_safe(CLASS.MinigameDrillView, "_update_target", function(self, widgets_by_name, minigame)
	local stage = minigame and minigame:current_stage()
	local target_widgets = stage and self._target_widgets and self._target_widgets[stage]
	local correct_targets = minigame and minigame:correct_targets()
	local correct_target = correct_targets and correct_targets[stage]
	local widget = target_widgets and correct_target and target_widgets[correct_target]

	if _should_highlight_drill_targets() and widget and widget.style and widget.style.highlight then
		widget.style.highlight.color = _ui_highlight_color()
	end

	if _should_show_drill_direction_arrows() then
		_set_drill_direction_widgets(self, minigame)
	else
		_set_drill_direction_widgets(self, nil)
	end
end)

mod:hook_safe(CLASS.MinigameDrillView, "draw_widgets", function(self, dt, t, input_service, ui_renderer)
	local minigame_extension = self._minigame_extension
	local minigame = minigame_extension and minigame_extension:minigame(MinigameSettings.types.drill) or nil

	if _should_show_drill_direction_arrows() then
		_set_drill_direction_widgets(self, minigame)
	else
		_set_drill_direction_widgets(self, nil)
	end

	local widgets = self._auspex_helper_drill_direction_widgets

	if not widgets then
		return
	end

	for index = 1, #DRILL_DIRECTION_WIDGET_ORDER do
		local widget = widgets[DRILL_DIRECTION_WIDGET_ORDER[index]]

		if widget then
			UIWidget.draw(widget, ui_renderer)
		end
	end
end)

mod:hook_safe("MinigameBalanceView", "_update_cursor", function(self)
	if not _is_balance_autosolve_enabled() then
		return
	end

	local minigame_extension = self._minigame_extension
	local minigame = minigame_extension and minigame_extension:minigame(MinigameSettings.types.balance)
	local position = minigame and minigame:position()

	if not position then
		return
	end

	balance_cursor_x = position.x
	balance_cursor_y = position.y
	balance_distance = math.sqrt(balance_cursor_x * balance_cursor_x + balance_cursor_y * balance_cursor_y)
	balance_input_window = 0.05
end)

mod:hook_safe("MinigameBalance", "start", function()
	_reset_balance_autosolve()
end)

mod:hook_safe("MinigameBalance", "stop", function()
	_reset_balance_autosolve()
end)

mod:hook_safe("MinigameFrequency", "start", function()
	_reset_frequency_autosolve()
end)

mod:hook_safe("MinigameFrequency", "stop", function()
	_reset_frequency_autosolve()
end)

mod:hook_safe("MinigameDecodeSymbols", "start", function()
	_reset_decode_autosolve()
end)

mod:hook_safe("MinigameDecodeSymbols", "stop", function()
	_reset_decode_autosolve()
end)

local expedition_minigame_class_name = rawget(_G, "MinigameExpedition") and "MinigameExpedition" or rawget(_G, "MinigameScan") and "MinigameScan" or nil
local expedition_minigame_class = expedition_minigame_class_name and rawget(_G, expedition_minigame_class_name) or nil

if expedition_minigame_class_name then
	mod:hook_safe(expedition_minigame_class_name, "start", function(self)
		_tag_minigame_type(self, EXPEDITION_MINIGAME_TYPE)
		_reset_expedition_autosolve()
	end)

	mod:hook_safe(expedition_minigame_class_name, "stop", function()
		_reset_expedition_autosolve()
	end)
end

mod:hook_safe("MinigameDrill", "start", function()
	_reset_drill_autosolve()
end)

mod:hook_safe("MinigameDrill", "stop", function()
	_reset_drill_autosolve()
end)

mod:hook_safe("MinigameDecodeSymbols", "is_on_target", function(self, time)
	if not _is_decode_autosolve_enabled() or decode_autosolve_cooldown > 0 or decode_same_targets_count > 0 then
		return
	end

	if _is_decode_on_target(self, time) then
		decode_same_targets_count = _count_decode_same_targets(self)
	end
end)

if expedition_minigame_class_name and expedition_minigame_class and expedition_minigame_class.is_on_target then
	mod:hook_safe(expedition_minigame_class_name, "is_on_target", function(self, time)
		if not _is_expedition_autosolve_enabled() or expedition_autosolve_cooldown > 0 or expedition_same_targets_count > 0 then
			return
		end

		_tag_minigame_type(self, EXPEDITION_MINIGAME_TYPE)

		if _is_expedition_on_target(self, time) then
			expedition_same_targets_count = _count_expedition_same_targets(self)
		end
	end)
end

local PREVIEW_BLOCKED_BOOLEAN_ACTIONS = {
	action_one_hold = true,
	action_one_pressed = true,
	action_one_release = true,
	action_two_hold = true,
	action_two_pressed = true,
	action_two_release = true,
	combat_ability_hold = true,
	combat_ability_pressed = true,
	combat_ability_release = true,
	crouch = true,
	crouching = true,
	dodge = true,
	grenade_ability_hold = true,
	grenade_ability_pressed = true,
	grenade_ability_release = true,
	interact_hold = true,
	interact_primary_hold = true,
	interact_primary_pressed = true,
	interact_pressed = true,
	interact_secondary_hold = true,
	interact_secondary_pressed = true,
	jump = true,
	jump_held = true,
	jump_pressed = true,
	quick_wield = true,
	sprint = true,
	sprinting = true,
	weapon_extra_hold = true,
	weapon_extra_pressed = true,
	weapon_extra_release = true,
	weapon_reload_hold = true,
	weapon_reload_pressed = true,
	wield_1 = true,
	wield_2 = true,
	wield_3 = true,
	wield_3_gamepad = true,
	wield_4 = true,
	wield_5 = true,
	wield_scroll_down = true,
	wield_scroll_up = true,
}
local PREVIEW_BLOCKED_VECTOR_ACTIONS = {
	look = true,
	look_controller = true,
	look_controller_improved = true,
	look_controller_lunging = true,
	look_controller_ranged = true,
	look_ranged = true,
	look_ranged_alternate_fire = true,
	look_raw = true,
	move = true,
}
local PREVIEW_BLOCKED_FLOAT_ACTIONS = {
	move_backward = true,
	move_forward = true,
	move_left = true,
	move_right = true,
}
local PREVIEW_ALLOWED_MENU_ACTIONS = {
	back = true,
	cancel = true,
	hotkey_menu = true,
	ingame_menu = true,
	pause = true,
	toggle_menu = true,
	ui_back = true,
}

_should_block_overlay_practice_input = function()
	local session = practice_session

	return session ~= nil and not session.item_mode and not session.pending_item_mode and not preview_close_requested_at
end

_blocked_preview_input_value = function(action_name, result)
	if PREVIEW_ALLOWED_MENU_ACTIONS[action_name] then
		return result
	end

	if PREVIEW_BLOCKED_VECTOR_ACTIONS[action_name] then
		return Vector3.zero()
	elseif PREVIEW_BLOCKED_FLOAT_ACTIONS[action_name] then
		return 0
	elseif PREVIEW_BLOCKED_BOOLEAN_ACTIONS[action_name] then
		return false
	elseif action_name == "move" then
		return Vector3.zero()
	end

	return result
end

_stop_preview_input_simulation_on_service = function(input_service)
	if not input_service or input_service:is_null_service() then
		return
	end

	for action_name, _ in pairs(PREVIEW_BLOCKED_BOOLEAN_ACTIONS) do
		if input_service:has(action_name) then
			input_service:stop_simulate_action(action_name)
		end
	end

	for action_name, _ in pairs(PREVIEW_BLOCKED_VECTOR_ACTIONS) do
		if input_service:has(action_name) then
			input_service:stop_simulate_action(action_name)
		end
	end

	for action_name, _ in pairs(PREVIEW_BLOCKED_FLOAT_ACTIONS) do
		if input_service:has(action_name) then
			input_service:stop_simulate_action(action_name)
		end
	end
end

_set_preview_input_simulation = function(enabled)
	local input_manager = Managers.input
	local input_service = input_manager and input_manager:get_input_service("Ingame")

	if not enabled then
		_stop_preview_input_simulation_on_service(preview_input_simulation_service or input_service)

		preview_input_simulation_active = false
		preview_input_simulation_service = nil

		return
	end

	if not input_service or input_service:is_null_service() then
		return
	end

	if preview_input_simulation_active and preview_input_simulation_service == input_service then
		return
	end

	if preview_input_simulation_service and preview_input_simulation_service ~= input_service then
		_stop_preview_input_simulation_on_service(preview_input_simulation_service)
	end

	for action_name, _ in pairs(PREVIEW_BLOCKED_BOOLEAN_ACTIONS) do
		if input_service:has(action_name) then
			input_service:start_simulate_action(action_name, false)
		end
	end

	for action_name, _ in pairs(PREVIEW_BLOCKED_VECTOR_ACTIONS) do
		if input_service:has(action_name) then
			input_service:start_simulate_action(action_name, Vector3.zero())
		end
	end

	for action_name, _ in pairs(PREVIEW_BLOCKED_FLOAT_ACTIONS) do
		if input_service:has(action_name) then
			input_service:start_simulate_action(action_name, 0)
		end
	end

	preview_input_simulation_active = true
	preview_input_simulation_service = input_service
end

_raw_input_action_value = function(input_service, action_name)
	local actions = input_service and input_service._actions
	local action_rule = actions and actions[action_name]

	if not action_rule or action_rule.filter then
		return nil
	end

	local action_type = action_rule.type
	local action_type_settings = action_type and InputServiceClass.ACTION_TYPES[action_type]
	local combiner = action_type_settings and action_type_settings.combine_func
	local out = action_rule.default_func and action_rule.default_func() or nil

	if not combiner then
		return out
	end

	for _, callback_func in ipairs(action_rule.callbacks or {}) do
		out = combiner(out, callback_func())
	end

	return out
end

_read_preview_move_input = function(input_service)
	local controller_move = _raw_input_action_value(input_service, "move_controller") or Vector3.zero()
	local keyboard_move = Vector3(
		(_raw_input_action_value(input_service, "keyboard_move_right") or 0) - (_raw_input_action_value(input_service, "keyboard_move_left") or 0),
		(_raw_input_action_value(input_service, "keyboard_move_forward") or 0) - (_raw_input_action_value(input_service, "keyboard_move_backward") or 0),
		0
	)

	if Vector3.length(controller_move) > Vector3.length(keyboard_move) then
		return controller_move
	end

	return keyboard_move
end

_preview_primary_action_pressed = function(input_service)
	return not not (_raw_input_action_value(input_service, "action_one_pressed") or _raw_input_action_value(input_service, "interact_pressed") or _raw_input_action_value(input_service, "interact_primary_pressed") or _raw_input_action_value(input_service, "jump_pressed"))
end

_trigger_preview_primary_action = function(minigame, t)
	if not minigame or not minigame.action then
		return
	end

	if minigame._action_held == nil then
		minigame:action(false, t)
	end

	minigame:action(true, t)
	minigame:action(false, t)
end

_update_preview_autosolve = function(session, minigame, t, move_input)
	if _is_decode_autosolve_enabled() and minigame == (_active_decode_autosolve_minigame and _active_decode_autosolve_minigame() or nil) and decode_autosolve_cooldown <= 0 and _is_decode_on_target(minigame, t) then
		local current_stage = minigame._current_stage
		local targets = minigame._decode_targets or {}
		local same_next_target = current_stage and targets[current_stage] ~= nil and targets[current_stage] == targets[current_stage + 1]

		decode_autosolve_cooldown = same_next_target and 0.05 or _decode_autosolve_cooldown_seconds()
		_trigger_preview_primary_action(minigame, t)
	end

	if _is_expedition_autosolve_enabled() and minigame == (_active_expedition_autosolve_minigame and _active_expedition_autosolve_minigame() or nil) and expedition_autosolve_cooldown <= 0 and _is_expedition_on_target(minigame, t) then
		local current_stage = minigame._current_stage
		local targets = minigame._decode_targets or {}
		local same_next_target = current_stage and targets[current_stage] ~= nil and targets[current_stage] == targets[current_stage + 1]

		expedition_autosolve_cooldown = same_next_target and 0.05 or _expedition_autosolve_cooldown_seconds()
		_trigger_preview_primary_action(minigame, t)
	end

	if _is_drill_autosolve_enabled() and minigame == (_active_drill_autosolve_minigame and _active_drill_autosolve_minigame() or nil) then
		mod._sync_drill_autosolve_minigame(minigame)
		mod._sync_drill_autosolve_stage(minigame)

		local auto_move = _drill_autosolve_move_vector(minigame)

		if auto_move then
			local magnitude = math.sqrt((auto_move.x or 0) * (auto_move.x or 0) + (auto_move.y or 0) * (auto_move.y or 0))

			if magnitude <= 0.01 then
				move_input = auto_move
			elseif (mod._drill_autosolve_move_cooldown or 0) <= 0 then
				mod._drill_autosolve_move_cooldown = _drill_autosolve_step_delay()
				move_input = auto_move
			else
				move_input = Vector3.zero()
			end
		end

		if (mod._drill_autosolve_submit_cooldown or 0) <= 0 and _should_submit_drill_autosolve(minigame, t) then
			mod._drill_autosolve_submit_cooldown = _drill_autosolve_step_delay()
			_trigger_preview_primary_action(minigame, t)
		end
	end

	if _is_frequency_autosolve_enabled() and minigame == (_active_frequency_autosolve_minigame and _active_frequency_autosolve_minigame() or nil) then
		local auto_move = _frequency_autosolve_move_vector(minigame)

		if auto_move then
			move_input = auto_move
		end

		if frequency_autosolve_submit_cooldown <= 0 and minigame:is_visually_on_target() then
			frequency_autosolve_submit_cooldown = 0.12
			_trigger_preview_primary_action(minigame, t)
		end
	end

	if _is_balance_autosolve_enabled() and _looks_like_balance_minigame(minigame) then
		local auto_move = _balance_autosolve_move_vector(minigame)

		if auto_move then
			move_input = auto_move
		end
	end

	return move_input
end

_update_preview_input = function()
	local session = practice_session
	local minigame = session and session.minigame

	if not session or not minigame or preview_close_requested_at or session.pending_item_mode or session.item_mode then
		return
	end

	local input_manager = Managers.input
	local input_service = input_manager and input_manager:get_input_service("Ingame")

	if (not input_service or input_service:is_null_service()) and session.allow_missing_gameplay_timer then
		input_service = input_manager and input_manager:get_input_service("View")
	end

	if not input_service or input_service:is_null_service() then
		return
	end

	local t = _gameplay_time()

	preview_input_polling = true

	local action_two_pressed = input_service:_get("action_two_pressed")
	local primary_action_pressed = minigame.uses_action and minigame:uses_action() and _preview_primary_action_pressed(input_service)
	local move_input = minigame.uses_joystick and minigame:uses_joystick() and _read_preview_move_input(input_service) or Vector3.zero()

	preview_input_polling = false

	move_input = _update_preview_autosolve(session, minigame, t, move_input)

	if action_two_pressed then
		preview_reopen_requested = false
		_close_preview_view(false)

		return
	end

	if primary_action_pressed then
		_trigger_preview_primary_action(minigame, t)
	end

	if minigame.uses_joystick and minigame:uses_joystick() then
		minigame:on_axis_set(t, move_input.x or 0, move_input.y or 0)
	end
end

_update_live_autosolve_input = function(minigame, t)
	if not minigame or practice_session then
		return
	end

	if minigame.uses_joystick and minigame:uses_joystick() then
		local move_input = nil

		if _is_drill_autosolve_enabled() and _looks_like_drill_minigame(minigame) then
			mod._sync_drill_autosolve_stage(minigame)
			move_input = _drill_autosolve_move_vector(minigame)
		elseif _is_frequency_autosolve_enabled() and _looks_like_frequency_minigame(minigame) then
			move_input = _frequency_autosolve_move_vector(minigame)
		elseif _is_balance_autosolve_enabled() and _looks_like_balance_minigame(minigame) then
			move_input = _balance_autosolve_move_vector(minigame)
		end

		if move_input then
			minigame:on_axis_set(t, move_input.x or 0, move_input.y or 0)
		end
	end

	if _is_decode_autosolve_enabled() and _looks_like_decode_minigame(minigame) and decode_autosolve_cooldown <= 0 and decode_autosolve_press_deadline <= t and _is_decode_on_target(minigame, t) then
		local current_stage = minigame._current_stage
		local targets = minigame._decode_targets or {}
		local same_next_target = current_stage and targets[current_stage] ~= nil and targets[current_stage] == targets[current_stage + 1]
		local press_window = _decode_autosolve_press_window_seconds(minigame)

		decode_autosolve_press_deadline = t + press_window
		decode_autosolve_cooldown = press_window + (same_next_target and 0.05 or _decode_autosolve_cooldown_seconds())
		_trigger_preview_primary_action(minigame, t)
	end

	if _is_expedition_autosolve_enabled() and _looks_like_expedition_minigame(minigame) and expedition_autosolve_cooldown <= 0 and expedition_autosolve_press_deadline <= t and _is_expedition_on_target(minigame, t) then
		local current_stage = minigame._current_stage
		local targets = minigame._decode_targets or {}
		local same_next_target = current_stage and targets[current_stage] ~= nil and targets[current_stage] == targets[current_stage + 1]
		local press_window = _expedition_autosolve_press_window_seconds(minigame)

		expedition_autosolve_press_deadline = t + press_window
		expedition_autosolve_cooldown = press_window + (same_next_target and 0.05 or _expedition_autosolve_cooldown_seconds())
		_trigger_preview_primary_action(minigame, t)
	end

	if _is_drill_autosolve_enabled() and _looks_like_drill_minigame(minigame) and (mod._drill_autosolve_submit_cooldown or 0) <= 0 and _should_submit_drill_autosolve(minigame, t) then
		mod._drill_autosolve_submit_cooldown = _drill_autosolve_step_delay()
		_trigger_preview_primary_action(minigame, t)
	end

	if _is_frequency_autosolve_enabled() and _looks_like_frequency_minigame(minigame) and frequency_autosolve_submit_cooldown <= 0 and minigame.is_visually_on_target and minigame:is_visually_on_target() then
		frequency_autosolve_submit_cooldown = 0.12
		_trigger_preview_primary_action(minigame, t)
	end
end

_handle_preview_input = function(action_name, result)
	if not _should_block_overlay_practice_input() then
		return result
	end

	return _blocked_preview_input_value(action_name, result)
end

_input_get_hook = function(func, self, action_name)
	local result = func(self, action_name)

	if preview_input_polling then
		return result
	end

	if self and self.type == "Ingame" and PREVIEW_ALLOWED_MENU_ACTIONS[action_name] then
		local ui_manager = Managers.ui
		local world_scan_ui_active = scanner_searching_active
			or scanner_overlay_active
			or (ui_manager and (
				ui_manager:view_active(WORLD_SCAN_VIEW_NAME)
				or ui_manager:is_view_closing(WORLD_SCAN_VIEW_NAME)
				or ui_manager:view_active(WORLD_SCAN_ICONS_VIEW_NAME)
				or ui_manager:is_view_closing(WORLD_SCAN_ICONS_VIEW_NAME)
			))

		if world_scan_ui_active and result then
			_suppress_world_scan_views(0.35)
			_close_world_scan_views()

			if type(result) == "boolean" then
				return true
			end
		end
	end

	result = _handle_preview_input(action_name, result)

	if self and self.type == "Ingame" then
		result = _handle_expedition_autosolve_input(action_name, result)
		result = _handle_decode_autosolve_input(action_name, result)
		result = _handle_drill_autosolve_input(action_name, result)
		result = _handle_frequency_autosolve_input(action_name, result)
		result = _handle_balance_autosolve_input(action_name, result)
	end

	return result
end

mod:hook("InputService", "_get", _input_get_hook)
mod:hook("InputService", "_get_simulate", _input_get_hook)

mod:hook_require("scripts/extension_systems/input/player_unit_input_extension", function(PlayerUnitInputExtension)
	mod:hook(PlayerUnitInputExtension, "get", function(func, self, action)
		local result = func(self, action)

		if not _should_block_overlay_practice_input() then
			result = _handle_expedition_autosolve_input(action, result)
			result = _handle_decode_autosolve_input(action, result)
			result = _handle_drill_autosolve_input(action, result)
			result = _handle_frequency_autosolve_input(action, result)
			result = _handle_balance_autosolve_input(action, result)

			return result
		end

		return _blocked_preview_input_value(action, result)
	end)
end)

mod:hook_require("scripts/extension_systems/input/human_unit_input", function(HumanUnitInput)
	mod:hook(HumanUnitInput, "get", function(func, self, action)
		local result = func(self, action)

		if not _should_block_overlay_practice_input() then
			result = _handle_expedition_autosolve_input(action, result)
			result = _handle_decode_autosolve_input(action, result)
			result = _handle_drill_autosolve_input(action, result)
			result = _handle_frequency_autosolve_input(action, result)
			result = _handle_balance_autosolve_input(action, result)

			return result
		end

		return _blocked_preview_input_value(action, result)
	end)
end)

mod:hook_require("scripts/extension_systems/character_state_machine/character_states/player_character_state_minigame", function(PlayerCharacterStateMinigame)
	mod:hook(PlayerCharacterStateMinigame, "_update_input", function(func, self, t, fixed_frame, input_extension)
		if practice_session or not _is_drill_autosolve_enabled() then
			return func(self, t, fixed_frame, input_extension)
		end

		local minigame = self and self._minigame

		if not _looks_like_drill_minigame(minigame) then
			mod._sync_drill_autosolve_minigame(nil)

			return func(self, t, fixed_frame, input_extension)
		end

		mod._sync_drill_autosolve_minigame(minigame)
		mod._sync_drill_autosolve_stage(minigame)

		local action_one_hold = input_extension:get("action_one_hold")
		local interact_hold = input_extension:get("interact_hold")
		local jump_held = input_extension:get("jump_held")

		if action_one_hold ~= self._previous_action_one_hold then
			self._previous_action_one_hold = action_one_hold
			self._previous_input = action_one_hold
		elseif interact_hold ~= self._previous_interact_hold then
			self._previous_interact_hold = interact_hold
			self._previous_input = interact_hold
		elseif jump_held ~= self._previous_jump_held then
			self._previous_jump_held = jump_held
			self._previous_input = jump_held
		end

		local primary_input = self._previous_input
		local action_two_pressed = input_extension:get("action_two_pressed")
		local cancel = action_two_pressed
		local block_weapon_actions = false
		local animation_extension = self._animation_extension
		local auto_move = _drill_autosolve_move_vector(minigame)
		local should_submit = (mod._drill_autosolve_submit_cooldown or 0) <= 0 and _should_submit_drill_autosolve(minigame, t)
		local hold_submit = (mod._drill_autosolve_press_deadline or 0) > t or (mod._drill_autosolve_second_press_deadline or 0) > t and (mod._drill_autosolve_release_deadline or 0) <= t
		local release_submit = (mod._drill_autosolve_release_deadline or 0) > t and (mod._drill_autosolve_press_deadline or 0) <= t

		if not self:_is_wielding_minigame_device() then
			return true
		end

		if hold_submit or should_submit then
			primary_input = true
		elseif release_submit then
			primary_input = false
		elseif mod._drill_autosolve_force_release then
			primary_input = false
		end

		if minigame:uses_action() and minigame:action(primary_input, t) then
			animation_extension:anim_event_1p("button_press")

			if minigame:is_completed() then
				animation_extension:anim_event_1p("scan_end")
			end
		end

		if minigame:uses_joystick() then
			local move_input = auto_move or input_extension:get("move") or Vector3.zero()

			minigame:on_axis_set(t, move_input.x or 0, move_input.y or 0)

			if not Vector3.equal(move_input, Vector3.zero()) then
				if move_input.y > 0 or move_input.x > 0 then
					animation_extension:anim_event_1p("knob_turn_up")
				else
					animation_extension:anim_event_1p("knob_turn_down")
				end
			end
		end

		cancel = minigame:escape_action(action_two_pressed)
		block_weapon_actions = minigame:blocks_weapon_actions()

		if should_submit then
			mod._drill_autosolve_submit_cooldown = _drill_autosolve_step_delay()
			mod._drill_autosolve_press_deadline = t + 0.08
			mod._drill_autosolve_release_deadline = t + 0.12
			mod._drill_autosolve_second_press_deadline = t + 0.2
			mod._drill_autosolve_force_release = true
		elseif mod._drill_autosolve_force_release then
			mod._drill_autosolve_force_release = false
		end

		if not cancel and not block_weapon_actions then
			local weapon_extension = self._weapon_extension

			weapon_extension:update_weapon_actions(fixed_frame)
		end

		return cancel
	end)
end)

mod:hook_require("scripts/ui/views/scanner_display_view/scanner_display_view", function(ScannerDisplayView)
	local decoration_widget_names = {
		"decoration_inquisition",
		"decoration_left_mark",
		"decoration_right_mark",
		"decoration_eagle",
		"decoration_skull",
	}

	mod:hook_safe(ScannerDisplayView, "update", function(self)
		local widgets_by_name = self._widgets_by_name

		if not widgets_by_name then
			return
		end

		local show_decorations = mod:get("overlay_show_decorations") ~= false

		for i = 1, #decoration_widget_names do
			local widget = widgets_by_name[decoration_widget_names[i]]
			local style = widget and widget.style and widget.style.highlight
			local color = style and style.color

			if color then
				style.__auspex_helper_base_alpha = style.__auspex_helper_base_alpha or color[1] or 255
				color[1] = show_decorations and style.__auspex_helper_base_alpha or 0
			end
		end
	end)
end)

mod:hook_require("scripts/ui/views/scanner_display_view/minigame_drill_view", function(MinigameDrillView)
	mod:hook(MinigameDrillView, "draw_widgets", function(func, self, dt, t, input_service, ui_renderer)
		func(self, dt, t, input_service, ui_renderer)

		local minigame_extension = self._minigame_extension

		if not minigame_extension or not self._target_widgets then
			return
		end

		local minigame = minigame_extension and minigame_extension:minigame(MinigameSettings.types.drill)

		if not minigame or minigame.unit == nil or minigame:unit() ~= nil then
			return
		end

		if minigame:state() ~= MinigameSettings.game_states.transition then
			return
		end

		self:_update_target(EMPTY_WIDGETS_BY_NAME, minigame, t)

		local current_stage = minigame:current_stage()
		local target_widgets = current_stage and self._target_widgets[current_stage]

		if not target_widgets then
			return
		end

		for index = 1, #target_widgets do
			UIWidget.draw(target_widgets[index], ui_renderer)
		end
	end)
end)

function mod.on_setting_changed(setting_id)
	if setting_id == "enable_mod_override" then
		_apply_mod_override_state()
	elseif setting_id == "enable_world_scans" or setting_id == "world_scan_display_mode" or setting_id == "world_scan_always_show" or setting_id == "world_scan_through_walls" or setting_id == "world_scan_item_overlay" or setting_id == "world_scan_color_red" or setting_id == "world_scan_color_green" or setting_id == "world_scan_color_blue" or setting_id == "world_scan_color_alpha" then
		if setting_id == "world_scan_color_red" or setting_id == "world_scan_color_green" or setting_id == "world_scan_color_blue" or setting_id == "world_scan_color_alpha" then
			mod._world_scan_unit_color_signatures = {}
			mod._world_scan_outline_settings_signature = nil
		elseif setting_id == "world_scan_through_walls" then
			mod._world_scan_outline_settings_signature = nil
		end

		_set_world_scan_highlights(false)

		if setting_id == "world_scan_always_show" or setting_id == "world_scan_through_walls" or setting_id == "world_scan_item_overlay" then
			mod._world_scan_next_refresh_t = nil
			mod._world_scan_next_visibility_refresh_t = nil
		end

		_set_world_scan_highlights(_world_scan_effective_active())
		_refresh_world_scan_overlay_view()
		_refresh_world_scan_icons_view()
	elseif SCANNER_SETTING_IDS[setting_id] then
		if not _is_scanner_visibility_enabled() then
			_reset_scanner_fade_state()
		end

		_sync_scanner_hud_visibility()
	elseif setting_id == "enable_decode_autosolve" or setting_id == "decode_interact_cooldown" or setting_id == "decode_target_precision" then
		if not _is_decode_autosolve_enabled() then
			_reset_decode_autosolve()
		end
	elseif setting_id == "enable_decode_minigame" and not _is_decode_autosolve_enabled() then
		_reset_decode_autosolve()
	elseif setting_id == "enable_expedition_autosolve" or setting_id == "expedition_interact_cooldown" or setting_id == "expedition_target_precision" then
		if not _is_expedition_autosolve_enabled() then
			_reset_expedition_autosolve()
		end
	elseif setting_id == "enable_expedition_minigame" and not _is_expedition_autosolve_enabled() then
		_reset_expedition_autosolve()
	elseif setting_id == "enable_drill_autosolve" or setting_id == "drill_autosolve_speed" then
		if not _is_drill_autosolve_enabled() then
			_reset_drill_autosolve()
		end
	elseif setting_id == "enable_drill_minigame" and not _is_drill_autosolve_enabled() then
		_reset_drill_autosolve()
	elseif setting_id == "enable_frequency_autosolve" or setting_id == "frequency_autosolve_strength" then
		if not _is_frequency_autosolve_enabled() then
			_reset_frequency_autosolve()
		end
	elseif setting_id == "enable_frequency_minigame" and not _is_frequency_autosolve_enabled() then
		_reset_frequency_autosolve()
	elseif setting_id == "enable_balance_autosolve" or setting_id == "balance_autosolve_strength" then
		if not _is_balance_autosolve_enabled() then
			_reset_balance_autosolve()
		end
	elseif setting_id == "enable_balance_minigame" and not _is_balance_autosolve_enabled() then
		_reset_balance_autosolve()
	elseif setting_id == "enable_preview" and not mod:get("enable_preview") then
		preview_reopen_requested = false
		_close_preview_view(false)
	elseif MINIGAME_ENABLE_SETTINGS[mod:get("preview_type")] == setting_id and practice_session then
		preview_reopen_requested = false
		_close_preview_view(false)
	elseif practice_session and (setting_id == "preview_type" or setting_id == "live_display_mode") then
		local ui_manager = Managers.ui

		if ui_manager and not ui_manager:is_view_closing(_practice_view_name()) then
			preview_reopen_requested = true
			_close_preview_view(false)
		end
	end
end

function mod.update(dt)
	dt = dt or 0
	local t = _gameplay_time()

	mod._cached_local_player = nil
	mod._cached_local_player_unit = nil
	mod._cached_live_minigame = nil

	if mod._last_gameplay_time and t + 1 < mod._last_gameplay_time then
		_reset_decode_autosolve()
		_reset_expedition_autosolve()
		_reset_drill_autosolve()
		_reset_frequency_autosolve()
		_reset_balance_autosolve()
		_set_preview_input_simulation(false)
	end

	mod._last_gameplay_time = t

	if mod._preview_gameplay_timer_missing then
		mod._preview_gameplay_timer_missing = nil
		preview_reopen_requested = false
		_abort_preview_session()

		return
	end

	if _is_scanner_visibility_enabled() or scanner_overlay_active then
		_refresh_scanner_overlay_state()
	end

	if decode_autosolve_cooldown > 0 then
		decode_autosolve_cooldown = math.max(decode_autosolve_cooldown - dt, 0)
	end

	if expedition_autosolve_cooldown > 0 then
		expedition_autosolve_cooldown = math.max(expedition_autosolve_cooldown - dt, 0)
	end

	if frequency_autosolve_submit_cooldown > 0 then
		frequency_autosolve_submit_cooldown = math.max(frequency_autosolve_submit_cooldown - dt, 0)
	end

	if (mod._drill_autosolve_submit_cooldown or 0) > 0 then
		mod._drill_autosolve_submit_cooldown = math.max(mod._drill_autosolve_submit_cooldown - dt, 0)
	end

	if (mod._drill_autosolve_move_cooldown or 0) > 0 then
		mod._drill_autosolve_move_cooldown = math.max(mod._drill_autosolve_move_cooldown - dt, 0)
	end

	if _is_drill_autosolve_enabled() then
		mod._sync_drill_autosolve_minigame(_active_drill_autosolve_minigame and _active_drill_autosolve_minigame() or nil)
	end

	if balance_input_window > 0 then
		balance_input_window = math.max(balance_input_window - dt, 0)
	end

	balance_velocity_x = (balance_cursor_x - balance_previous_x) * dt * 10000
	balance_velocity_y = (balance_cursor_y - balance_previous_y) * dt * 10000
	balance_previous_x = balance_cursor_x
	balance_previous_y = balance_cursor_y

	if scanner_fade_target then
		local direction = scanner_fade_target > scanner_current_alpha and 1 or -1
		local step = scanner_fade_speed * dt * direction

		scanner_current_alpha = scanner_current_alpha + step

		if (direction > 0 and scanner_current_alpha >= scanner_fade_target) or (direction < 0 and scanner_current_alpha <= scanner_fade_target) then
			scanner_current_alpha = scanner_fade_target
			scanner_fade_target = nil
		end

		_apply_scanner_current_alpha()
	end

	if scanner_world_helper_active or scanner_equipped_active or scanner_searching_active then
		local search_input_active = _scanner_search_input_active()

		if search_input_active ~= scanner_searching_active then
			_set_scanner_searching_state(search_input_active)
		end
	end

	_set_preview_input_simulation(not not (practice_session and not practice_session.item_mode and _overlay_preview_view_is_active(practice_session)))
	if practice_session and practice_session.minigame and practice_session.minigame_started and not practice_session.pending_item_mode and not preview_close_requested_at then
		practice_session.minigame:update(dt, t)
	end

	_update_preview_input()

	local live_minigame = _active_live_minigame and _active_live_minigame() or nil

	_update_live_autosolve_input(live_minigame, t)

	if _world_scan_effective_active() and t >= (mod._world_scan_next_refresh_t or 0) then
		mod._world_scan_next_refresh_t = t + 0.5
		_set_world_scan_highlights(true)
	end

	if _world_scan_effective_active() and _world_scan_needs_visibility_refresh() and t >= (mod._world_scan_next_visibility_refresh_t or 0) then
		mod._world_scan_next_visibility_refresh_t = t + 0.15
		_set_world_scan_highlights(true, false)
	end

	if scanner_searching_active or scanner_overlay_active then
		_refresh_world_scan_overlay_view()
	end

	local ui_manager = Managers.ui

	if _world_scan_effective_active() or (ui_manager and (ui_manager:view_active(WORLD_SCAN_ICONS_VIEW_NAME) or ui_manager:is_view_closing(WORLD_SCAN_ICONS_VIEW_NAME))) then
		_refresh_world_scan_icons_view()
	end

	local session = practice_session

	if _abort_live_item_scanner_if_unsafe() then
		return
	end

	if session and not _has_gameplay_timer() and not _preview_supports_missing_gameplay_timer() then
		preview_reopen_requested = false
		_abort_preview_session()

		return
	end

	if session and session.pending_item_mode and not preview_close_requested_at then
		if not _try_open_pending_item_preview(session) and t - (session.opened_at or 0) > PRACTICE_ITEM_OPEN_TIMEOUT then
			_cleanup_preview_session()
			_open_overlay_preview_session(session, true)
		end
	end

	if session and session.item_mode and session.item_minigame_bound and not preview_close_requested_at then
		local character_state_machine_extension = session.player_unit and ScriptUnit.has_extension(session.player_unit, "character_state_machine_system")

		if character_state_machine_extension and character_state_machine_extension:current_state_name() ~= "minigame" then
			_abort_preview_session()

			return
		end
	end

	if practice_session and practice_session.minigame and practice_session.minigame:should_exit() and not preview_close_requested_at then
		preview_reopen_requested = false
		_abort_preview_session()
	end

	if ui_manager and practice_session and not practice_session.pending_item_mode and not preview_close_requested_at then
		local practice_view_name = practice_session.view_name
		local practice_active = ui_manager:view_active(practice_view_name)
		local practice_closing = ui_manager:is_view_closing(practice_view_name)
		local practice_open_elapsed = t - (practice_session.opened_at or 0)

		if not practice_session.item_mode and practice_active and not practice_closing then
			practice_session.overlay_view_ready = true

			if practice_session.minigame and not practice_session.minigame_started then
				_start_preview_minigame(practice_session)
			end
		elseif not practice_session.item_mode and not practice_active and not practice_closing and practice_open_elapsed <= PREVIEW_VIEW_OPEN_TIMEOUT and t >= (practice_session.next_view_open_retry_at or 0) then
			practice_session.next_view_open_retry_at = t + PREVIEW_VIEW_OPEN_RETRY_INTERVAL
			_open_preview_session_view(practice_session)
		end

		if practice_open_elapsed > PREVIEW_VIEW_OPEN_TIMEOUT and not practice_active and not practice_closing then
			_cleanup_preview_session()
		end
	end

	if not ui_manager or not preview_close_requested_at or not preview_close_view_name then
		return
	end

	local is_active = ui_manager:view_active(preview_close_view_name)
	local is_closing = ui_manager:is_view_closing(preview_close_view_name)

	if not is_active and not is_closing then
		_clear_preview_close_request()

		_cleanup_preview_session()

		if preview_reopen_requested and _is_mod_active() and mod:get("enable_preview") then
			preview_reopen_requested = false
			_open_preview_view()
		else
			preview_reopen_requested = false
		end

		return
	end

	if is_closing and t - preview_close_requested_at > PREVIEW_CLOSE_TIMEOUT then
		local view_name = preview_close_view_name

		_clear_preview_close_request()
		ui_manager:close_view(view_name, true)
		_cleanup_preview_session()
	end
end

function mod.on_enabled()
	_apply_mod_override_state()
end

local function _shutdown_runtime_state_for_unload()
	_reset_decode_autosolve()
	_reset_expedition_autosolve()
	_reset_drill_autosolve()
	_reset_frequency_autosolve()
	_reset_balance_autosolve()
	mod._cached_live_minigame_type = nil
	_clear_preview_close_request()
	preview_reopen_requested = false
	_set_preview_input_simulation(false)

	if practice_session then
		_abort_preview_session()
	end

	_force_cancel_local_minigame_state()

	scanner_equipped_active = false
	scanner_overlay_active = false
	scanner_searching_active = false
	_reset_scanner_fade_state()
	_apply_scanner_current_alpha()
	_set_world_scan_highlights(false)
	_close_view(PREVIEW_VIEW_NAME, true)
	_close_view(STOCK_SCANNER_VIEW_NAME, true)
	_close_preview_view(true)
	_close_view(OVERLAY_VIEW_NAME, true)
	_close_view(WORLD_SCAN_VIEW_NAME, true)
	_close_view(WORLD_SCAN_ICONS_VIEW_NAME, true)
	_cleanup_preview_session()
end

function mod.on_disabled()
	_shutdown_runtime_state_for_unload()
end

function mod.on_unload(exit_game)
	_shutdown_runtime_state_for_unload()
end
