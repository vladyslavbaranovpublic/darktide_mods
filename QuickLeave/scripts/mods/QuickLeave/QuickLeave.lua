--[[
	File: QuickLeave.lua
	Description: Main mod logic for cutscene button and cursor handling.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	File Introduced in: 1.0.0
	Last Updated: 2026-02-06
	Author: LAUREHTE
]]
local mod = get_mod("QuickLeave")

-- Show a Quick Leave button during cutscenes and force a usable cursor.

local UIWidget = mod:original_require("scripts/managers/ui/ui_widget")
local UISoundEvents = mod:original_require("scripts/settings/ui/ui_sound_events")
local ButtonPassTemplates = mod:original_require("scripts/ui/pass_templates/button_pass_templates")
local CinematicSceneSettings = mod:original_require("scripts/settings/cinematic_scene/cinematic_scene_settings")
local Definitions = mod:original_require("scripts/ui/views/cutscene_view/cutscene_view_definitions")
local UIResolution = mod:original_require("scripts/managers/ui/ui_resolution")

local CLASS = CLASS
local Managers = Managers
local callback = callback
local table_clone = table.clone
local table_remove = table.remove
local utf8_upper = Utf8.upper

local BUTTON_PACKAGE = "packages/ui/views/options_view/options_view"
local PACKAGE_WAIT_WARN_AFTER = 8
local PACKAGE_WAIT_WARN_INTERVAL = 5

local function get_setting(setting_id, default_value)
	if mod.get then
		local value = mod:get(setting_id)
		if value ~= nil then
			return value
		end
	end

	return default_value
end

local function dbg(message)
	if not get_setting("debug_enabled", false) then
		return
	end
	if mod.echo then
		mod:echo(message)
	end
	if mod.info then
		mod:info(message)
	end
end

local function main_time()
	local time_manager = Managers.time
	if time_manager and time_manager.time then
		return time_manager:time("main")
	end

	return 0
end

local function schedule_leave(reason)
	mod._ql_pending_leave = true
	mod._ql_pending_leave_reason = reason or "leave_mission"

	mod._ql_pending_leave_t = main_time() + 0.1
end

local function perform_leave(reason)
	local left = false

	local multiplayer_session = Managers.multiplayer_session
	if multiplayer_session and multiplayer_session.leave then
		multiplayer_session:leave(reason or "leave_mission")
		left = true
	end

	local party_immaterium = Managers.party_immaterium
	if party_immaterium and party_immaterium.leave_party then
		party_immaterium:leave_party()
		left = true
	end

	if not left then
		dbg("QL action: no leave method available")
	end
end

local function force_cursor(input_manager)
	if not input_manager then
		return
	end

	if input_manager._set_allow_cursor_rendering then
		input_manager:_set_allow_cursor_rendering(true)
	else
		local cursor_stack_data = input_manager._cursor_stack_data
		if cursor_stack_data then
			cursor_stack_data.allow_cursor_rendering = true
		end
	end

	input_manager._show_cursor = true
	input_manager._software_cursor_active = false

	if InputDevice.gamepad_active then
		InputDevice.gamepad_active = false
	end

	if Window and Window.set_show_cursor then
		Window.set_show_cursor(true)
	end
	if Window and Window.set_clip_cursor then
		Window.set_clip_cursor(false)
	end
end

local function clear_cursor_restore_cache()
	mod._ql_cursor_owner = nil
	mod._ql_cursor_pushed = nil
	mod._ql_cursor_push_count = nil
	mod._ql_prev_gamepad_active = nil
	mod._ql_prev_allow_cursor = nil
	mod._ql_prev_show_cursor = nil
	mod._ql_prev_software_cursor = nil
end

local function cleanup_without_view(reason)
	local has_cached_state = mod._ql_force_cursor or mod._ql_cursor_pushed or (mod._ql_cursor_push_count or 0) > 0 or mod._ql_prev_gamepad_active ~= nil or mod._ql_prev_allow_cursor ~= nil or mod._ql_prev_show_cursor ~= nil or mod._ql_prev_software_cursor ~= nil
	if not has_cached_state then
		return false
	end

	local input_manager = Managers.input
	if input_manager and mod._ql_cursor_owner and input_manager.pop_cursor then
		local push_count = mod._ql_cursor_push_count or (mod._ql_cursor_pushed and 1 or 0)
		while push_count > 0 do
			local ok = pcall(function()
				input_manager:pop_cursor(mod._ql_cursor_owner)
			end)
			if not ok then
				break
			end
			push_count = push_count - 1
		end
	end

	if input_manager and mod._ql_prev_allow_cursor ~= nil and input_manager._set_allow_cursor_rendering then
		input_manager:_set_allow_cursor_rendering(mod._ql_prev_allow_cursor)
	end

	if input_manager and mod._ql_prev_show_cursor ~= nil then
		input_manager._show_cursor = mod._ql_prev_show_cursor
	end

	if input_manager and mod._ql_prev_software_cursor ~= nil then
		input_manager._software_cursor_active = mod._ql_prev_software_cursor
	end

	if mod._ql_prev_gamepad_active ~= nil then
		InputDevice.gamepad_active = mod._ql_prev_gamepad_active
	end

	mod._ql_force_cursor = nil
	clear_cursor_restore_cache()
	dbg(string.format("QL cleanup fallback: %s", tostring(reason)))

	return true
end

local function push_cursor_for_view(self, input_manager)
	if not input_manager then
		return
	end

	input_manager:push_cursor(self.__class_name)
	self._cursor_pushed = true
	self._ql_cursor_push_count = (self._ql_cursor_push_count or 0) + 1

	mod._ql_cursor_owner = self.__class_name
	mod._ql_cursor_pushed = true
	mod._ql_cursor_push_count = (mod._ql_cursor_push_count or 0) + 1
end

local function cleanup_runtime_state(reason)
	local ui_manager = Managers.ui
	local cutscene_view = ui_manager and ui_manager:view_instance("cutscene_view")
	if cutscene_view and cutscene_view._ql_cleanup then
		cutscene_view:_ql_cleanup(reason)
		return true
	end

	return cleanup_without_view(reason)
end

local function use_safe_button_template()
	return get_setting("use_safe_button_template", false)
end

local function button_pass_template()
	if use_safe_button_template() then
		return ButtonPassTemplates.simple_button
	end

	return ButtonPassTemplates.default_button
end

local function apply_button_definition(definitions)
	local button_size = { 374, 76 }

	definitions.scenegraph_definition.quick_leave_button = {
		vertical_alignment = "bottom",
		parent = "screen",
		horizontal_alignment = "center",
		size = button_size,
		position = { 0, -20, 1 },
	}

	definitions.widget_definitions.quick_leave_button = UIWidget.create_definition(table_clone(button_pass_template()), "quick_leave_button", {
		gamepad_action = "confirm_pressed",
		text = utf8_upper(mod:localize("loc_quick_leave_button")),
		hotspot = {
			on_pressed_sound = UISoundEvents.weapons_skin_confirm,
		},
	})

	definitions.widget_definitions.quick_leave_button.content.original_text = utf8_upper(mod:localize("loc_quick_leave_button"))
end

local function ensure_button_package()
	if use_safe_button_template() then
		return true
	end

	local package_manager = Managers.package
	if not package_manager then
		return false
	end

	if package_manager:has_loaded(BUTTON_PACKAGE) then
		return true
	end

	if not mod._ql_button_package_id and not package_manager:is_loading(BUTTON_PACKAGE) then
		local reference_name = (mod.get_name and mod:get_name()) or "QuickLeave"
		mod._ql_button_package_id = package_manager:load(BUTTON_PACKAGE, reference_name)
	end

	return false
end

local function current_cinematic_name()
	local state = Managers.state
	local name = CinematicSceneSettings.CINEMATIC_NAMES.none

	if not state or not state.extension then
		return mod._ql_last_cinematic_name or name
	end

	local cinematic_scene_system = state.extension:system("cinematic_scene_system")
	if not cinematic_scene_system then
		return mod._ql_last_cinematic_name or name
	end

	return cinematic_scene_system:current_cinematic_name() or name
end

local function should_show_button()
	local show_intro = get_setting("show_in_intro", true)
	local show_outro = get_setting("show_in_outro", true)

	local name = current_cinematic_name()
	if name == CinematicSceneSettings.CINEMATIC_NAMES.none then
		return false
	end

	local is_intro = name == CinematicSceneSettings.CINEMATIC_NAMES.intro_abc
	local is_outro_fail = name == CinematicSceneSettings.CINEMATIC_NAMES.outro_fail
	local is_outro_win = name == CinematicSceneSettings.CINEMATIC_NAMES.outro_win
	local is_outro = is_outro_fail or is_outro_win

	return (show_outro and is_outro) or (show_intro and is_intro)
end

apply_button_definition(Definitions)

mod:hook_require("scripts/ui/views/cutscene_view/cutscene_view_definitions", function(instance)
	apply_button_definition(instance)
end)

mod:hook_require("scripts/ui/views/cutscene_view/cutscene_view", function(instance)
	instance.init_custom = function(self)
		self._widgets = self._widgets or {}
		self._widgets_by_name = self._widgets_by_name or {}
	end

	instance._ql_reset_button_widget = function(self)
		local widgets_by_name = self._widgets_by_name
		local widget = widgets_by_name and widgets_by_name.quick_leave_button
		if not widget then
			return
		end

		widget.visible = false
		widgets_by_name.quick_leave_button = nil

		local widgets = self._widgets
		if widgets then
			for i = #widgets, 1, -1 do
				if widgets[i] == widget then
					table_remove(widgets, i)
					break
				end
			end
		end

		self._ql_waiting_for_package = nil
		self._ql_package_wait_start_t = nil
		self._ql_package_wait_warn_t = nil
	end

	instance._ql_try_create_button = function(self)
		if self._widgets_by_name.quick_leave_button then
			return true
		end

		if not ensure_button_package() then
			return false
		end

		local widget = self:_create_widget("quick_leave_button", Definitions.widget_definitions.quick_leave_button)
		self._widgets_by_name.quick_leave_button = widget
		self._widgets[#self._widgets + 1] = widget
		widget.content.hotspot.pressed_callback = callback(self, "cb_quick_leave_pressed")
		widget.visible = true

		self._ql_waiting_for_package = nil
		self._ql_package_wait_start_t = nil
		self._ql_package_wait_warn_t = nil

		return true
	end

	instance._ql_cleanup = function(self, reason)
		local had_active_state = self._ql_active ~= nil
		local had_cursor_state = self._cursor_pushed or (self._ql_cursor_push_count or 0) > 0 or self._ql_prev_gamepad_active ~= nil or self._ql_prev_allow_cursor ~= nil or self._ql_prev_show_cursor ~= nil or self._ql_prev_software_cursor ~= nil

		if not had_active_state and not had_cursor_state then
			return
		end

		dbg(string.format("QL cleanup: %s", tostring(reason)))

		self._ql_active = nil
		self._ql_leaving = nil
		self._ql_waiting_for_package = nil
		self._ql_package_wait_start_t = nil
		self._ql_package_wait_warn_t = nil
		mod._ql_force_cursor = nil

		if self._ql_prev_gamepad_active ~= nil then
			InputDevice.gamepad_active = self._ql_prev_gamepad_active
			self._ql_prev_gamepad_active = nil
			mod._ql_prev_gamepad_active = nil
		end

		local input_manager = Managers.input
		if input_manager and self._cursor_pushed then
			local push_count = self._ql_cursor_push_count or 1
			while push_count > 0 do
				local ok = pcall(function()
					input_manager:pop_cursor(self.__class_name)
				end)
				if not ok then
					break
				end
				push_count = push_count - 1
			end
			self._cursor_pushed = nil
			self._ql_cursor_push_count = nil
			mod._ql_cursor_pushed = nil
			mod._ql_cursor_push_count = nil
			mod._ql_cursor_owner = nil
		end

		if input_manager and self._ql_prev_allow_cursor ~= nil and input_manager._set_allow_cursor_rendering then
			input_manager:_set_allow_cursor_rendering(self._ql_prev_allow_cursor)
			self._ql_prev_allow_cursor = nil
			mod._ql_prev_allow_cursor = nil
		end

		if input_manager and self._ql_prev_show_cursor ~= nil then
			input_manager._show_cursor = self._ql_prev_show_cursor
			self._ql_prev_show_cursor = nil
			mod._ql_prev_show_cursor = nil
		end

		if input_manager and self._ql_prev_software_cursor ~= nil then
			input_manager._software_cursor_active = self._ql_prev_software_cursor
			self._ql_prev_software_cursor = nil
			mod._ql_prev_software_cursor = nil
		end

		local widgets = self._widgets_by_name
		if widgets and widgets.quick_leave_button then
			widgets.quick_leave_button.visible = false
		end
	end

	instance.cb_quick_leave_pressed = function(self)
		dbg("QL action: leave pressed")
		self:_ql_cleanup("leave_pressed")

		schedule_leave("leave_mission")
	end

	instance.custom_enter = function(self, should_show)
		if should_show == nil then
			should_show = should_show_button()
		end

		self._ql_active = should_show
		mod._ql_force_cursor = self._ql_active

		dbg(string.format(
			"QL enter: active=%s cinematic=%s",
			tostring(self._ql_active),
			tostring(current_cinematic_name())
		))

		if not self._ql_active then
			return
		end

		ensure_button_package()

		local input_manager = Managers.input
		self._ql_prev_gamepad_active = self._ql_prev_gamepad_active or InputDevice.gamepad_active
		mod._ql_prev_gamepad_active = mod._ql_prev_gamepad_active or InputDevice.gamepad_active
		if InputDevice.gamepad_active then
			InputDevice.gamepad_active = false
		end

		self._no_cursor = false
		if input_manager and not self._cursor_pushed then
			push_cursor_for_view(self, input_manager)
		end

		if not self._widgets_by_name.quick_leave_button then
			if not self:_ql_try_create_button() then
				self._ql_waiting_for_package = true
				self._ql_package_wait_start_t = main_time()
				self._ql_package_wait_warn_t = nil
				return
			end
		end

		self._widgets_by_name.quick_leave_button.visible = true

		if input_manager and self._ql_prev_allow_cursor == nil then
			local cursor_stack_data = input_manager._cursor_stack_data
			self._ql_prev_allow_cursor = cursor_stack_data and cursor_stack_data.allow_cursor_rendering
			self._ql_prev_show_cursor = input_manager._show_cursor
			self._ql_prev_software_cursor = input_manager._software_cursor_active
			mod._ql_prev_allow_cursor = self._ql_prev_allow_cursor
			mod._ql_prev_show_cursor = self._ql_prev_show_cursor
			mod._ql_prev_software_cursor = self._ql_prev_software_cursor
		end
	end

	instance.update_custom = function(self, dt, t, input_service)
		local should_show = should_show_button()

		if not self._ql_active then
			if should_show then
				self:custom_enter(should_show)
			end
			if not self._ql_active then
				return
			end
		end

		if not should_show then
			self:_ql_cleanup("cinematic_end")
			return
		end

		local input_manager = Managers.input
		if input_manager then
			force_cursor(input_manager)

			if not input_manager:cursor_active() then
				if self._cursor_pushed then
					self._cursor_pushed = nil
					self._ql_cursor_push_count = nil
					mod._ql_cursor_pushed = nil
					mod._ql_cursor_push_count = nil
				end
				push_cursor_for_view(self, input_manager)
			end
		end

		local widget = self._widgets_by_name.quick_leave_button
		if not widget then
			if self._ql_waiting_for_package then
				local now = main_time()
				self._ql_package_wait_start_t = self._ql_package_wait_start_t or now

				if not self:_ql_try_create_button() then
					local elapsed = now - self._ql_package_wait_start_t
					if elapsed >= PACKAGE_WAIT_WARN_AFTER and (not self._ql_package_wait_warn_t or now - self._ql_package_wait_warn_t >= PACKAGE_WAIT_WARN_INTERVAL) then
						self._ql_package_wait_warn_t = now
						dbg(string.format("QL package wait: %s still loading (%.1fs)", BUTTON_PACKAGE, elapsed))
					end

					return
				end
				widget = self._widgets_by_name.quick_leave_button
			else
				return
			end
		end

		if not widget or not widget.visible then
			return
		end

		local click_input = (input_manager and input_manager:get_input_service("View")) or input_service
		if not click_input then
			return
		end

		local left_pressed = click_input:get("left_pressed")
		if left_pressed and not self._ql_leaving then
			local cursor = click_input:get("cursor")
			local cursor_type = cursor and Script.type_name(cursor)
			if cursor and (cursor_type == "Vector3" or cursor_type == "Vector2") then
				local render_scale = self._render_scale or 1
				local inverse_scale = 1 / render_scale
				local cursor_position = UIResolution and UIResolution.inverse_scale_vector and UIResolution.inverse_scale_vector(cursor, inverse_scale) or cursor

				local scenegraph_id = widget.scenegraph_id
				local pos = self:_scenegraph_world_position(scenegraph_id, render_scale)
				local size_x, size_y = self:_scenegraph_size(scenegraph_id)
				local is_hover = math.point_is_inside_2d_box(cursor_position, pos, { size_x, size_y })
				local hotspot = widget.content and widget.content.hotspot
				local hotspot_hover = hotspot and (hotspot.is_hover or hotspot.internal_is_hover)

				if is_hover or hotspot_hover then
					self._ql_leaving = true
					self:cb_quick_leave_pressed()
					return
				end
			end
		end
	end

	instance.custom_exit = function(self)
		self:_ql_cleanup("view_exit")
	end
end)

mod:hook(CLASS.CutsceneView, "init", function(func, self, settings, context, ...)
	func(self, settings, context, ...)
	self:init_custom()
end)

mod:hook(CLASS.CutsceneView, "on_enter", function(func, self, ...)
	func(self, ...)
	self:custom_enter()
end)

mod:hook(CLASS.CutsceneView, "on_exit", function(func, self, ...)
	self:custom_exit()
	func(self, ...)
end)

mod:hook(CLASS.CutsceneView, "update", function(func, self, dt, t, input_service, ...)
	func(self, dt, t, input_service, ...)
	self:update_custom(dt, t, input_service)
end)

mod:hook_require("scripts/extension_systems/cinematic_scene/cinematic_scene_system", function(instance)
	local original = instance._set_cinematic_name
	instance._set_cinematic_name = function(self, cinematic_name, ...)
		mod._ql_last_cinematic_name = cinematic_name
		return original(self, cinematic_name, ...)
	end
end)

mod:hook(CLASS.InputManager, "update", function(func, self, dt, t, ...)
	if mod._ql_force_cursor then
		force_cursor(self)
	end

	if mod._ql_pending_leave then
		local time_manager = Managers.time
		local now = time_manager and time_manager.time and time_manager:time("main") or 0
		if not mod._ql_pending_leave_t or now >= mod._ql_pending_leave_t then
			mod._ql_pending_leave = nil
			mod._ql_pending_leave_t = nil
			local reason = mod._ql_pending_leave_reason or "leave_mission"
			mod._ql_pending_leave_reason = nil
			perform_leave(reason)
		end
	end

	return func(self, dt, t, ...)
end)

mod.on_enabled = function(initial_call)
	if get_setting("debug_enabled", false) and mod.echo then
		mod:echo(string.format("QuickLeave enabled (initial=%s)", tostring(initial_call)))
	end
end

mod.on_disabled = function()
	if get_setting("debug_enabled", false) and mod.echo then
		mod:echo("QuickLeave disabled")
	end

	cleanup_runtime_state("mod_disabled")

	mod._ql_pending_leave = nil
	mod._ql_pending_leave_t = nil
	mod._ql_pending_leave_reason = nil

	local package_manager = Managers.package
	if package_manager and mod._ql_button_package_id then
		package_manager:release(mod._ql_button_package_id)
		mod._ql_button_package_id = nil
	end
end

mod.on_setting_changed = function(setting_id)
	if setting_id == "debug_enabled" and mod.echo then
		mod:echo(string.format("QuickLeave debug setting = %s", tostring(mod.get and mod:get("debug_enabled"))))
	end
	if setting_id == "debug_enabled" then
		cleanup_runtime_state("debug_toggle")
	end

	if setting_id == "use_safe_button_template" then
		apply_button_definition(Definitions)

		local ui_manager = Managers.ui
		local cutscene_view = ui_manager and ui_manager:view_instance("cutscene_view")
		if cutscene_view and cutscene_view._ql_reset_button_widget then
			cutscene_view:_ql_reset_button_widget()

			if cutscene_view._ql_active then
				if not cutscene_view:_ql_try_create_button() then
					cutscene_view._ql_waiting_for_package = true
					cutscene_view._ql_package_wait_start_t = main_time()
					cutscene_view._ql_package_wait_warn_t = nil
				end
			end
		end

		if use_safe_button_template() then
			local package_manager = Managers.package
			if package_manager and mod._ql_button_package_id then
				package_manager:release(mod._ql_button_package_id)
				mod._ql_button_package_id = nil
			end
		end

		dbg(string.format("QuickLeave button style = %s", use_safe_button_template() and "safe" or "default"))
	end
end

if mod.command then
	mod:command("ql_clean_cursor", "Force QuickLeave cursor cleanup and cursor state reset.", function()
		local cleaned = cleanup_runtime_state("manual_command")
		if mod.echo then
			mod:echo(cleaned and "QuickLeave cursor cleanup requested" or "QuickLeave cursor cleanup: nothing active")
		end
	end)
end

mod.quick_leave_hotkey = function()
	local ui_manager = Managers.ui
	local cutscene_view = ui_manager and ui_manager:view_instance("cutscene_view")
	if cutscene_view and cutscene_view._ql_active and not cutscene_view._ql_leaving then
		cutscene_view._ql_leaving = true
		cutscene_view:cb_quick_leave_pressed()
		return
	end

	dbg("QL hotkey: leave requested")
	schedule_leave("leave_mission")
end
