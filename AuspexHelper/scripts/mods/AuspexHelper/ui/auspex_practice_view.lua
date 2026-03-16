--[[
	File: auspex_practice_view.lua
	Description: Centered overlay scanner view for Auspex Helper minigames.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	File Introduced in: 1.0.0
	Last Updated: 2026-03-14
	Author: LAUREHTE
]]

local MinigameBalanceView = require("scripts/ui/views/scanner_display_view/minigame_balance_view")
local MinigameDecodeSymbolsView = require("scripts/ui/views/scanner_display_view/minigame_decode_symbols_view")
local MinigameDrillView = require("scripts/ui/views/scanner_display_view/minigame_drill_view")
local MinigameFrequencyView = require("scripts/ui/views/scanner_display_view/minigame_frequency_view")
local MinigameNoneView = require("scripts/ui/views/scanner_display_view/minigame_none_view")
local MinigameSettings = require("scripts/settings/minigame/minigame_settings")
local ScannerDisplayViewBalanceSettings = require("scripts/ui/views/scanner_display_view/scanner_display_view_balance_settings")
local ScannerDisplayViewDecodeSymbolsSettings = require("scripts/ui/views/scanner_display_view/scanner_display_view_decode_symbols_settings")
local ScannerDisplayViewDrillSettings = require("scripts/ui/views/scanner_display_view/scanner_display_view_drill_settings")
local ScannerEquipTemplate = require("scripts/settings/equipment/weapon_templates/devices/scanner_equip")
local ScannerDisplayViewDefinitions = require("scripts/ui/views/scanner_display_view/scanner_display_view_definitions")
local ScannerDisplayViewFrequencySettings = require("scripts/ui/views/scanner_display_view/scanner_display_view_frequency_settings")
local Scanning = require("scripts/utilities/scanning")
local UIScenegraph = require("scripts/managers/ui/ui_scenegraph")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local mod = get_mod("AuspexHelper")
local OVERLAY_PANEL_SIZE = 1260
local OVERLAY_HORIZONTAL_FRAME_SIZE = {
	1096,
	150,
}
local OVERLAY_SIDE_FRAME_SIZE = {
	1096,
	150,
}
local OVERLAY_FRAME_MARGIN = -100
local OVERLAY_OUTLINE_SIZE = {
	1096,
	1096,
}
local OVERLAY_FREQUENCY_SIDE_PADDING = 35
local OVERLAY_FREQUENCY_WIDGET_SIZE = {}
local RENDER_SIZE = 1024
local BALANCE_PROGRESS_TEXTURE = "content/ui/materials/backgrounds/scanner/scanner_balance_progress"
local WORLD_SCAN_RING_TEXTURE = "content/ui/materials/backgrounds/scanner/scanner_drill_circle_empty"
local WORLD_SCAN_BLIP_TEXTURE = "content/ui/materials/backgrounds/scanner/scanner_drill_circle_filled"
local WORLD_SCAN_TARGET_TEXTURE = "content/ui/materials/backgrounds/scanner/scanner_drill_selection_cursor"
local WORLD_SCAN_ICON_TEXTURE = "content/ui/materials/hud/interactions/icons/objective_main"
local BALANCE_PROGRESS_MASK_COLOR = {
	200,
	0,
	0,
	0,
}
local WORLD_SCAN_SCAN_SETTINGS = ScannerEquipTemplate.actions and ScannerEquipTemplate.actions.action_scan and ScannerEquipTemplate.actions.action_scan.scan_settings
local WORLD_SCAN_RING_SIZES = {
	{
		220,
		220,
	},
	{
		380,
		380,
	},
	{
		540,
		540,
	},
}
local WORLD_SCAN_MAX_RADIUS = 320
local WORLD_SCAN_BLIP_SIZE = 30
local WORLD_SCAN_TARGET_SIZE = 44
local WORLD_SCAN_PLAYER_SIZE = 18
local WORLD_SCAN_MAX_BLIPS = 32
local WORLD_SCAN_ICON_SIZE = 100
local WORLD_SCAN_ICON_HIGHLIGHT_SIZE = 34
local DRILL_OVERLAY_SONAR_ALPHA_MULTIPLIER = 0.2
local OVERLAY_DECORATION_WIDGETS = {
	"decoration_inquisition",
	"decoration_left_mark",
	"decoration_right_mark",
	"decoration_eagle",
	"decoration_skull",
}
local OVERLAY_FRAME_WIDGETS = {
	"overlay_frame_top",
	"overlay_frame_bottom",
	"overlay_frame_left",
	"overlay_frame_right",
}
local HIDDEN_STOCK_WIDGETS = {
	edge_fade = true,
	noise_background = true,
	scanner_background = true,
}
local overlay_definitions = {}
local scenegraph_definition = {
	screen = table.clone(UIWorkspaceSettings.screen),
	overlay_panel = {
		horizontal_alignment = "center",
		parent = "screen",
		vertical_alignment = "center",
		size = {
			OVERLAY_PANEL_SIZE,
			OVERLAY_PANEL_SIZE,
		},
		position = {
			0,
			0,
			25,
		},
	},
	scanner_base = {
		horizontal_alignment = "center",
		parent = "overlay_panel",
		vertical_alignment = "center",
		size = {
			RENDER_SIZE,
			RENDER_SIZE,
		},
		position = {
			0,
			0,
			5,
		},
	},
	center_pivot = {
		horizontal_alignment = "center",
		parent = "scanner_base",
		vertical_alignment = "center",
		size = {
			0,
			0,
		},
		position = {
			0,
			0,
			1,
		},
	},
}

local function _overlay_color(alpha)
	local base_alpha = math.clamp(mod:get("overlay_color_alpha") or 255, 0, 255)
	local requested_alpha = math.clamp(alpha or 255, 0, 255)
	local final_alpha = math.floor(requested_alpha * (base_alpha / 255))

	return {
		final_alpha,
		mod:get("overlay_color_red") or 0,
		mod:get("overlay_color_green") or 255,
		mod:get("overlay_color_blue") or 110,
	}
end

local function _scanner_green(alpha)
	return _overlay_color(alpha)
end

local function _world_scan_overlay_color(alpha)
	return _overlay_color(alpha)
end

local function _world_scan_icon_color(alpha)
	local base_alpha = math.clamp(mod:get("world_scan_color_alpha") or 255, 0, 255)
	local requested_alpha = math.clamp(alpha or 255, 0, 255)
	local final_alpha = math.floor(requested_alpha * (base_alpha / 255))

	return {
		final_alpha,
		mod:get("world_scan_color_red") or 0,
		mod:get("world_scan_color_green") or 255,
		mod:get("world_scan_color_blue") or 110,
	}
end

local function _world_scan_overlay_target_color(alpha)
	local base_alpha = math.clamp(mod:get("overlay_color_alpha") or 255, 0, 255)
	local requested_alpha = math.clamp(alpha or 255, 0, 255)
	local final_alpha = math.floor(requested_alpha * (base_alpha / 255))

	return {
		final_alpha,
		255,
		170,
		50,
	}
end

local function _drill_helper_enabled()
	return mod:get("enable_drill_helper") ~= false
end

local function _drill_highlight_color()
	local alpha = math.clamp(mod:get("ui_color_alpha") or 210, 0, 255)

	return {
		alpha,
		mod:get("ui_color_red") or 255,
		mod:get("ui_color_green") or 165,
		mod:get("ui_color_blue") or 0,
	}
end

local function _scanner_scan_settings()
	return WORLD_SCAN_SCAN_SETTINGS or {
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

local function _create_world_scan_widget(name, material, size, z)
	return UIWidget.init(name, UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "icon",
			value = material,
			style = {
				color = _scanner_green(255),
				offset = {
					-size[1] * 0.5,
					-size[2] * 0.5,
					z or 10,
				},
				size = {
					size[1],
					size[2],
				},
			},
		},
	}, "center_pivot", nil, {
		size[1],
		size[2],
	}))
end

local function _ensure_world_scan_widgets(self)
	if self._world_scan_overlay_widgets then
		return self._world_scan_overlay_widgets
	end

	local widgets = {
		rings = {},
		blips = {},
		guides = {},
		player = _create_world_scan_widget("world_scan_player", WORLD_SCAN_BLIP_TEXTURE, {
			WORLD_SCAN_PLAYER_SIZE,
			WORLD_SCAN_PLAYER_SIZE,
		}, 12),
	}

	widgets.guides[1] = UIWidget.init("world_scan_guide_horizontal", UIWidget.create_definition({
		{
			pass_type = "rect",
			style_id = "line",
			style = {
				color = _scanner_green(64),
				offset = {
					-350,
					-1,
					8,
				},
			},
		},
	}, "center_pivot", nil, {
		700,
		2,
	}))
	widgets.guides[2] = UIWidget.init("world_scan_guide_vertical", UIWidget.create_definition({
		{
			pass_type = "rect",
			style_id = "line",
			style = {
				color = _scanner_green(64),
				offset = {
					-1,
					-350,
					8,
				},
			},
		},
	}, "center_pivot", nil, {
		2,
		700,
	}))

	for i = 1, #WORLD_SCAN_RING_SIZES do
		local size = WORLD_SCAN_RING_SIZES[i]

		widgets.rings[i] = _create_world_scan_widget("world_scan_ring_" .. i, WORLD_SCAN_RING_TEXTURE, size, 9)
	end

	for i = 1, WORLD_SCAN_MAX_BLIPS do
		widgets.blips[i] = _create_world_scan_widget("world_scan_blip_" .. i, WORLD_SCAN_BLIP_TEXTURE, {
			WORLD_SCAN_BLIP_SIZE,
			WORLD_SCAN_BLIP_SIZE,
		}, 11)
	end

	self._world_scan_overlay_widgets = widgets

	return widgets
end

local function _create_world_scan_icon_widget(name)
	return UIWidget.init(name, UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "icon",
			value = WORLD_SCAN_ICON_TEXTURE,
			style = {
				color = _world_scan_icon_color(255),
				offset = {
					-WORLD_SCAN_ICON_SIZE * 0.5,
					-WORLD_SCAN_ICON_SIZE * 0.5,
					20,
				},
				size = {
					WORLD_SCAN_ICON_SIZE,
					WORLD_SCAN_ICON_SIZE,
				},
			},
		},
	}, "screen", nil, {
		WORLD_SCAN_ICON_SIZE,
		WORLD_SCAN_ICON_SIZE,
	}))
end

local function _ensure_world_scan_icon_widgets(self)
	if self._world_scan_icon_widgets then
		return self._world_scan_icon_widgets
	end

	local widgets = {}

	for i = 1, WORLD_SCAN_MAX_BLIPS do
		widgets[i] = _create_world_scan_icon_widget("world_scan_screen_icon_" .. i)
	end

	self._world_scan_icon_widgets = widgets

	return widgets
end

local function _world_scan_overlay_context()
	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1) or nil
	local player_unit = player and player.player_unit or nil

	if not player_unit or not Unit.alive(player_unit) then
		return nil
	end

	local extension_manager = Managers.state.extension
	local mission_objective_zone_system = extension_manager and extension_manager:has_system("mission_objective_zone_system") and extension_manager:system("mission_objective_zone_system") or nil
	local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
	local interaction_extension = ScriptUnit.has_extension(player_unit, "interaction_system")
	local first_person = unit_data_extension and unit_data_extension:read_component("first_person")
	local physics_world = interaction_extension and interaction_extension._physics_world

	if not mission_objective_zone_system or not first_person then
		return nil
	end

	return player_unit, first_person, physics_world, mission_objective_zone_system
end

local function _cached_world_scan_highlight_unit(self, physics_world, first_person, scan_settings, t)
	if t >= (self._world_scan_next_highlight_refresh_t or 0) then
		self._world_scan_highlight_unit = physics_world and Scanning.find_scannable_unit(physics_world, first_person, scan_settings) or nil
		self._world_scan_next_highlight_refresh_t = t + 0.05
	end

	return self._world_scan_highlight_unit
end

local function _draw_world_scan_overlay(self, t, ui_renderer)
	local widgets = _ensure_world_scan_widgets(self)
	local _, first_person, physics_world, mission_objective_zone_system = _world_scan_overlay_context()

	if not first_person or not mission_objective_zone_system then
		return
	end

	local scan_settings = _scanner_scan_settings()
	local rotation = first_person.rotation
	local player_position = first_person.position
	local forward = rotation and Quaternion.forward(rotation) or Vector3(0, 1, 0)
	local right = rotation and Quaternion.right(rotation) or Vector3(1, 0, 0)
	local flat_forward = Vector3.flat(forward)
	local flat_right = Vector3.flat(right)

	if Vector3.length(flat_forward) <= 0.001 then
		flat_forward = Vector3(0, 1, 0)
	end

	if Vector3.length(flat_right) <= 0.001 then
		flat_right = Vector3(1, 0, 0)
	end

	flat_forward = Vector3.normalize(flat_forward)
	flat_right = Vector3.normalize(flat_right)

	self._world_scan_overlay_color = self._world_scan_overlay_color or {
		0,
		0,
		0,
		0,
	}
	self._world_scan_overlay_target_color = self._world_scan_overlay_target_color or {
		0,
		0,
		0,
		0,
	}
	self._world_scan_overlay_guide_color = self._world_scan_overlay_guide_color or {
		0,
		0,
		0,
		0,
	}
	self._world_scan_overlay_ring_color = self._world_scan_overlay_ring_color or {
		0,
		0,
		0,
		0,
	}
	local ring_pulse = 0.92 + math.sin(t * 2.5) * 0.06
	local highlight_unit = _cached_world_scan_highlight_unit(self, physics_world, first_person, scan_settings, t)

	_fill_overlay_color(self._world_scan_overlay_color, 180)
	_fill_world_scan_target_color(self._world_scan_overlay_target_color, 255)
	_fill_overlay_color(self._world_scan_overlay_guide_color, 64)

	for i = 1, #widgets.guides do
		local widget = widgets.guides[i]

		widget.style.line.color = self._world_scan_overlay_guide_color
		UIWidget.draw(widget, ui_renderer)
	end

	for i = 1, #widgets.rings do
		local widget = widgets.rings[i]

		widget.offset[1] = 0
		widget.offset[2] = 0
		_fill_overlay_color(self._world_scan_overlay_ring_color, math.floor((34 + i * 10) * ring_pulse))
		widget.style.icon.color = self._world_scan_overlay_ring_color
		UIWidget.draw(widget, ui_renderer)
	end

	widgets.player.offset[1] = 0
	widgets.player.offset[2] = 0
	_fill_overlay_color(self._world_scan_overlay_ring_color, 255)
	widgets.player.style.icon.color = self._world_scan_overlay_ring_color
	UIWidget.draw(widgets.player, ui_renderer)

	local scannable_units = mod._world_scan_scannable_units or mod._world_scan_icon_units or mission_objective_zone_system:scannable_units()

	if not scannable_units then
		return
	end

	local blip_index = 1
	local max_radius = math.min(WORLD_SCAN_MAX_RADIUS, OVERLAY_OUTLINE_SIZE[1] * 0.5 - 90, OVERLAY_OUTLINE_SIZE[2] * 0.5 - 90)

	for scannable_unit, _ in pairs(scannable_units) do
		if blip_index > #widgets.blips then
			break
		end

		if Unit.alive(scannable_unit) then
			local scannable_extension = ScriptUnit.has_extension(scannable_unit, "mission_objective_zone_scannable_system")

			if scannable_extension and (scannable_extension:is_active() or mod._world_scan_scannable_units ~= nil) then
				local scannable_position = Scanning.get_scannable_units_position(scannable_unit, scannable_extension)
				local to_scannable = scannable_position - player_position
				local flat_delta = Vector3.flat(to_scannable)
				local flat_length = Vector3.length(flat_delta)
				local dir = flat_length > 0.001 and Vector3.normalize(flat_delta) or Vector3(0, 0, 0)
				local normalized_distance = math.clamp01(math.ilerp(0, math.max(scan_settings.distance.far, 1), flat_length))
				local radius = math.min(max_radius, max_radius * normalized_distance)
				local offset_x = flat_length > 0.001 and Vector3.dot(dir, flat_right) * radius or 0
				local offset_y = flat_length > 0.001 and -Vector3.dot(dir, flat_forward) * radius or 0
				local is_highlight = scannable_unit == highlight_unit
				local icon_size = is_highlight and WORLD_SCAN_TARGET_SIZE or WORLD_SCAN_BLIP_SIZE
				local widget = widgets.blips[blip_index]

				blip_index = blip_index + 1
				widget.content.icon = is_highlight and WORLD_SCAN_TARGET_TEXTURE or WORLD_SCAN_BLIP_TEXTURE
				widget.content.size[1] = icon_size
				widget.content.size[2] = icon_size
				widget.style.icon.size[1] = icon_size
				widget.style.icon.size[2] = icon_size
				widget.offset[1] = offset_x
				widget.offset[2] = offset_y
				widget.style.icon.color = is_highlight and self._world_scan_overlay_target_color or self._world_scan_overlay_color

				UIWidget.draw(widget, ui_renderer)
			end
		end
	end
end

local function _draw_world_scan_screen_icons(self, ui_renderer)
	local icon_units = mod._world_scan_icon_units

	if not icon_units or next(icon_units) == nil then
		return
	end

	local widgets = _ensure_world_scan_icon_widgets(self)
	local _, first_person, physics_world = _world_scan_overlay_context()
	local hud = Managers.ui and Managers.ui.get_hud and Managers.ui:get_hud() or nil
	local camera = hud and hud.player_camera and hud:player_camera() or nil

	if not first_person or not camera then
		return
	end

	local screen_offset = UIScenegraph.world_position(self._ui_scenegraph, "screen", 1)
	local screen_x, screen_y = Vector3.to_elements(screen_offset)
	local inverse_scale = ui_renderer.inverse_scale or 1
	local highlight_unit = _cached_world_scan_highlight_unit(self, physics_world, first_person, _scanner_scan_settings(), self:get_time())

	self._world_scan_icon_color = self._world_scan_icon_color or {
		0,
		0,
		0,
		0,
	}
	self._world_scan_icon_highlight_color = self._world_scan_icon_highlight_color or {
		0,
		0,
		0,
		0,
	}

	_fill_world_scan_icon_color(self._world_scan_icon_color, 255)
	_fill_world_scan_icon_color(self._world_scan_icon_highlight_color, 255)
	local drawn = 0

	for scannable_unit, _ in pairs(icon_units) do
		if drawn >= WORLD_SCAN_MAX_BLIPS then
			break
		end

		if Unit.alive(scannable_unit) then
			local scannable_extension = ScriptUnit.has_extension(scannable_unit, "mission_objective_zone_scannable_system")
			local world_position = scannable_extension and Scanning.get_scannable_units_position(scannable_unit, scannable_extension) or nil

			world_position = world_position or POSITION_LOOKUP[scannable_unit] or Unit.world_position(scannable_unit, 1)

			if world_position and Camera.inside_frustum(camera, world_position) > 0 then
				local world_to_screen = Camera.world_to_screen(camera, world_position)
				local widget = widgets[drawn + 1]
				local style = widget.style.icon
				local is_highlight = scannable_unit == highlight_unit
				local size = is_highlight and WORLD_SCAN_ICON_HIGHLIGHT_SIZE or WORLD_SCAN_ICON_SIZE

				widget.offset[1] = (world_to_screen.x - screen_x) * inverse_scale
				widget.offset[2] = (world_to_screen.y - screen_y) * inverse_scale
				style.offset[1] = -size * 0.5
				style.offset[2] = -size * 0.5
				style.size[1] = size
				style.size[2] = size
				style.color = is_highlight and self._world_scan_icon_highlight_color or self._world_scan_icon_color

				UIWidget.draw(widget, ui_renderer)

				drawn = drawn + 1
			end
		end
	end
end

local function _overlay_show_drill_sonar()
	return mod:get("enable_drill_overlay_sonar") == true
end

local function _set_color(color, a, r, g, b)
	color[1] = a
	color[2] = r
	color[3] = g
	color[4] = b

	return color
end

_fill_overlay_color = function(color, alpha)
	local base_alpha = math.clamp(mod:get("overlay_color_alpha") or 255, 0, 255)
	local requested_alpha = math.clamp(alpha or 255, 0, 255)
	local final_alpha = math.floor(requested_alpha * (base_alpha / 255))

	return _set_color(color, final_alpha, mod:get("overlay_color_red") or 0, mod:get("overlay_color_green") or 255, mod:get("overlay_color_blue") or 110)
end

_fill_world_scan_icon_color = function(color, alpha)
	local base_alpha = math.clamp(mod:get("world_scan_color_alpha") or 255, 0, 255)
	local requested_alpha = math.clamp(alpha or 255, 0, 255)
	local final_alpha = math.floor(requested_alpha * (base_alpha / 255))

	return _set_color(color, final_alpha, mod:get("world_scan_color_red") or 0, mod:get("world_scan_color_green") or 255, mod:get("world_scan_color_blue") or 110)
end

_fill_world_scan_target_color = function(color, alpha)
	local base_alpha = math.clamp(mod:get("overlay_color_alpha") or 255, 0, 255)
	local requested_alpha = math.clamp(alpha or 255, 0, 255)
	local final_alpha = math.floor(requested_alpha * (base_alpha / 255))

	return _set_color(color, final_alpha, 255, 170, 50)
end

local function _overlay_scale()
	return math.clamp(mod:get("overlay_display_scale") or 1, 0.1, 2)
end

local function _overlay_backdrop_alpha()
	return math.clamp(mod:get("overlay_background_opacity") or 0, 0, 255)
end

local function _overlay_show_decorations()
	return mod:get("overlay_show_decorations") ~= false
end

local function _has_gameplay_timer()
	local time_manager = Managers.time

	return time_manager ~= nil and time_manager.has_timer ~= nil and time_manager:has_timer("gameplay")
end

local function _preview_supports_missing_gameplay_timer()
	return mod._preview_allow_missing_gameplay_timer == true
end

local function _frame_widgets()
	return {
		overlay_backdrop = UIWidget.create_definition({
			{
				pass_type = "texture",
				style_id = "background",
				value = "content/ui/materials/backgrounds/default_square",
				style = {
					color = {
						0,
						0,
						0,
						0,
					},
					offset = {
						(RENDER_SIZE - OVERLAY_OUTLINE_SIZE[1]) / 2,
						(RENDER_SIZE - OVERLAY_OUTLINE_SIZE[2]) / 2,
						1,
					},
				},
			},
		}, "scanner_base", nil, {
			OVERLAY_OUTLINE_SIZE[1],
			OVERLAY_OUTLINE_SIZE[2],
		}),
		overlay_frame_top = UIWidget.create_definition({
			{
				pass_type = "rotated_texture",
				style_id = "frame",
				value = "content/ui/materials/dividers/horizontal_frame_big_lower",
				style = {
					angle = math.rad(180),
					color = _scanner_green(144),
					offset = {
						(RENDER_SIZE - OVERLAY_HORIZONTAL_FRAME_SIZE[1]) / 2,
						OVERLAY_FRAME_MARGIN,
						7,
					},
					pivot = {},
				},
			},
		}, "scanner_base", nil, {
			OVERLAY_HORIZONTAL_FRAME_SIZE[1],
			OVERLAY_HORIZONTAL_FRAME_SIZE[2],
		}),
		overlay_frame_bottom = UIWidget.create_definition({
			{
				pass_type = "texture",
				style_id = "frame",
				value = "content/ui/materials/dividers/horizontal_frame_big_lower",
				style = {
					color = _scanner_green(144),
					offset = {
						(RENDER_SIZE - OVERLAY_HORIZONTAL_FRAME_SIZE[1]) / 2,
						RENDER_SIZE - OVERLAY_HORIZONTAL_FRAME_SIZE[2] - OVERLAY_FRAME_MARGIN,
						7,
					},
				},
			},
		}, "scanner_base", nil, {
			OVERLAY_HORIZONTAL_FRAME_SIZE[1],
			OVERLAY_HORIZONTAL_FRAME_SIZE[2],
		}),
		overlay_frame_left = UIWidget.create_definition({
			{
				pass_type = "rotated_texture",
				style_id = "frame",
				value = "content/ui/materials/dividers/horizontal_frame_big_lower",
				style = {
					angle = math.rad(-90),
					color = _scanner_green(144),
					offset = {
						OVERLAY_FRAME_MARGIN + OVERLAY_SIDE_FRAME_SIZE[2] / 2 - OVERLAY_SIDE_FRAME_SIZE[1] / 2,
						(RENDER_SIZE - OVERLAY_SIDE_FRAME_SIZE[2]) / 2,
						7,
					},
					pivot = {},
				},
			},
		}, "scanner_base", nil, {
			OVERLAY_SIDE_FRAME_SIZE[1],
			OVERLAY_SIDE_FRAME_SIZE[2],
		}),
		overlay_frame_right = UIWidget.create_definition({
			{
				pass_type = "rotated_texture",
				style_id = "frame",
				value = "content/ui/materials/dividers/horizontal_frame_big_lower",
				style = {
					angle = math.rad(90),
					color = _scanner_green(144),
					offset = {
						RENDER_SIZE - OVERLAY_FRAME_MARGIN - OVERLAY_SIDE_FRAME_SIZE[2] / 2 - OVERLAY_SIDE_FRAME_SIZE[1] / 2,
						(RENDER_SIZE - OVERLAY_SIDE_FRAME_SIZE[2]) / 2,
						7,
					},
					pivot = {},
				},
			},
		}, "scanner_base", nil, {
			OVERLAY_SIDE_FRAME_SIZE[1],
			OVERLAY_SIDE_FRAME_SIZE[2],
		}),
		overlay_outline = UIWidget.create_definition({
			{
				pass_type = "texture",
				style_id = "frame",
				value = "content/ui/materials/frames/frame_tile_2px",
				style = {
					color = _scanner_green(70),
					scale_to_material = true,
					offset = {
						(RENDER_SIZE - OVERLAY_OUTLINE_SIZE[1]) / 2,
						(RENDER_SIZE - OVERLAY_OUTLINE_SIZE[2]) / 2,
						6,
					},
				},
			},
		}, "scanner_base", nil, {
			OVERLAY_OUTLINE_SIZE[1],
			OVERLAY_OUTLINE_SIZE[2],
		}),
	}
end

local FRAME_WIDGET_DEFINITIONS = _frame_widgets()
local WORLD_SCAN_ICON_VIEW_DEFINITIONS = {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = {},
}

local function _overlay_frequency_visible_width()
	return math.max(OVERLAY_OUTLINE_SIZE[1] - OVERLAY_FREQUENCY_SIDE_PADDING * 2, 0)
end

local function _decode_frame_widget_definition()
	return UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "frame",
			value = "content/ui/materials/backgrounds/scanner/scanner_decode_symbol_frame",
			style = {
				hdr = true,
				color = _drill_highlight_color(),
				offset = {
					0,
					0,
					-1,
				},
			},
		},
	}, "center_pivot", nil, ScannerDisplayViewDecodeSymbolsSettings.decode_symbol_widget_size)
end

local function _decode_highlight_widget_definition()
	return UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "highlight",
			value = "content/ui/materials/backgrounds/scanner/scanner_decode_symbol_highlight",
			style = {
				hdr = true,
				color = _drill_highlight_color(),
			},
		},
	}, "center_pivot", nil, ScannerDisplayViewDecodeSymbolsSettings.decode_symbol_widget_size)
end

local function _definitions_for(minigame_type)
	local definitions = overlay_definitions[minigame_type]

	if definitions then
		return definitions
	end

	local stock_definitions = ScannerDisplayViewDefinitions[minigame_type] or ScannerDisplayViewDefinitions[MinigameSettings.types.none]
	local widget_definitions = {}

	for name, definition in pairs(FRAME_WIDGET_DEFINITIONS) do
		widget_definitions[name] = definition
	end

	for name, definition in pairs(stock_definitions.widget_definitions) do
		if not HIDDEN_STOCK_WIDGETS[name] then
			widget_definitions[name] = definition
		end
	end

	if minigame_type == MinigameSettings.types.decode_symbols then
		widget_definitions.symbol_frame = _decode_frame_widget_definition()
		widget_definitions.symbol_highlight = _decode_highlight_widget_definition()
	end

	definitions = {
		scenegraph_definition = scenegraph_definition,
		widget_definitions = widget_definitions,
	}
	overlay_definitions[minigame_type] = definitions

	return definitions
end

local AuspexOverlayView = class("AuspexOverlayView", "BaseView")

AuspexOverlayView.MINIGAMES = {
	[MinigameSettings.types.none] = MinigameNoneView,
	[MinigameSettings.types.balance] = MinigameBalanceView,
	[MinigameSettings.types.decode_symbols] = MinigameDecodeSymbolsView,
	[MinigameSettings.types.drill] = MinigameDrillView,
	[MinigameSettings.types.frequency] = MinigameFrequencyView,
}

local STOCK_DRAW_DRILL_WIDGETS = MinigameDrillView.draw_widgets
local STOCK_DRAW_FREQUENCY_WIDGETS = MinigameFrequencyView._auspex_helper_stock_draw_widgets or MinigameFrequencyView.draw_widgets
MinigameFrequencyView._auspex_helper_stock_draw_widgets = STOCK_DRAW_FREQUENCY_WIDGETS
local STOCK_DRAW_FREQUENCY = MinigameFrequencyView._auspex_helper_stock_draw_frequency or MinigameFrequencyView._draw_frequency
MinigameFrequencyView._auspex_helper_stock_draw_frequency = STOCK_DRAW_FREQUENCY
local STOCK_UPDATE_BALANCE_WIDGETS = MinigameBalanceView.update
local STOCK_DRAW_BALANCE_WIDGETS = MinigameBalanceView.draw_widgets

local function _scanner_view_time()
	local time_manager = Managers.time

	if time_manager and time_manager.has_timer and time_manager:has_timer("gameplay") then
		return time_manager:time("gameplay")
	end

	if time_manager and time_manager.has_timer and time_manager:has_timer("main") then
		return time_manager:time("main")
	end

	return 0
end

local FREQUENCY_DIRECTION_ARROW_MATERIAL = "content/ui/materials/buttons/arrow_01"
local FREQUENCY_DIRECTION_ARROW_SIZE = {
	120,
	120,
}
local FREQUENCY_DIRECTION_ARROW_TOP_Y = 205
local FREQUENCY_DIRECTION_ARROW_DEPTH = 7
local FREQUENCY_DIRECTION_ARROW_COLOR = {
	255,
	255,
	165,
	0,
}
local FREQUENCY_DIRECTION_ARROW_HIDDEN_COLOR = {
	0,
	255,
	165,
	0,
}
local FREQUENCY_DIRECTION_WIDGET_SPECS = {
	x = {
		offset = { -385, FREQUENCY_DIRECTION_ARROW_TOP_Y, FREQUENCY_DIRECTION_ARROW_DEPTH },
	},
	y = {
		offset = { -240, FREQUENCY_DIRECTION_ARROW_TOP_Y, FREQUENCY_DIRECTION_ARROW_DEPTH },
	},
}

local function _should_show_frequency_direction_arrows()
	return mod:get("enable_frequency_direction_arrows") ~= false
end

local function _ensure_frequency_direction_widgets(view)
	local widgets = view._auspex_helper_frequency_direction_widgets

	if widgets and widgets.x and widgets.y and not widgets.left and not widgets.right and not widgets.up and not widgets.down then
		return widgets
	end

	widgets = {}

	for axis, spec in pairs(FREQUENCY_DIRECTION_WIDGET_SPECS) do
		local widget_definition = UIWidget.create_definition({
			{
				pass_type = "rotated_texture",
				style_id = "arrow",
				value = FREQUENCY_DIRECTION_ARROW_MATERIAL,
				style = {
					hdr = true,
					angle = 0,
					color = table.clone(FREQUENCY_DIRECTION_ARROW_HIDDEN_COLOR),
					offset = {
						spec.offset[1],
						spec.offset[2],
						spec.offset[3],
					},
					pivot = {},
				},
			},
		}, "center_pivot", nil, FREQUENCY_DIRECTION_ARROW_SIZE)

		widgets[axis] = UIWidget.init("auspex_helper_frequency_arrow_" .. axis, widget_definition)
	end

	view._auspex_helper_frequency_direction_widgets = widgets

	return widgets
end

local function _set_frequency_direction_widgets(view, minigame)
	local widgets = _ensure_frequency_direction_widgets(view)
	local active = _should_show_frequency_direction_arrows()
		and minigame
		and minigame.frequency
		and minigame.target_frequency
		and minigame.current_stage
		and minigame:current_stage()
		and not minigame:is_completed()
	local x_angle = 0
	local y_angle = 0
	local x_active = false
	local y_active = false

	if active then
		local current = minigame:frequency()
		local target = minigame:target_frequency()
		local margin = (MinigameSettings.frequency_success_margin or 0.1) * 0.35
		local delta_x = target.x - current.x
		local delta_y = target.y - current.y

		if delta_x > margin then
			x_active = true
			x_angle = 0
		elseif delta_x < -margin then
			x_active = true
			x_angle = math.rad(180)
		end

		if delta_y < -margin then
			y_active = true
			y_angle = math.rad(-90)
		elseif delta_y > margin then
			y_active = true
			y_angle = math.rad(90)
		end
	end

	local x_widget = widgets.x

	if x_widget then
		x_widget.style.arrow.color = x_active and FREQUENCY_DIRECTION_ARROW_COLOR or FREQUENCY_DIRECTION_ARROW_HIDDEN_COLOR
		x_widget.style.arrow.angle = x_angle
	end

	local y_widget = widgets.y

	if y_widget then
		y_widget.style.arrow.color = y_active and FREQUENCY_DIRECTION_ARROW_COLOR or FREQUENCY_DIRECTION_ARROW_HIDDEN_COLOR
		y_widget.style.arrow.angle = y_angle
	end
end

local function _draw_frequency_direction_widgets(self, ui_renderer)
	local widgets = self._auspex_helper_frequency_direction_widgets

	if not widgets or not widgets.x or not widgets.y then
		return
	end

	local x_widget = widgets.x

	if x_widget.style.arrow.color[1] > 0 then
		UIWidget.draw(x_widget, ui_renderer)
	end

	local y_widget = widgets.y

	if y_widget.style.arrow.color[1] > 0 then
		UIWidget.draw(y_widget, ui_renderer)
	end
end

local function _reset_frequency_direction_widgets(self)
	if not self then
		return
	end

	self._auspex_helper_frequency_direction_widgets = nil
end

local original_frequency_init = MinigameFrequencyView._auspex_helper_stock_init or MinigameFrequencyView.init
MinigameFrequencyView._auspex_helper_stock_init = original_frequency_init

MinigameFrequencyView.init = function(self, context)
	original_frequency_init(self, context)
	_reset_frequency_direction_widgets(self)
end

local original_frequency_destroy = MinigameFrequencyView._auspex_helper_stock_destroy or MinigameFrequencyView.destroy
MinigameFrequencyView._auspex_helper_stock_destroy = original_frequency_destroy

MinigameFrequencyView.destroy = function(self)
	_reset_frequency_direction_widgets(self)

	if original_frequency_destroy then
		return original_frequency_destroy(self)
	end
end

local function _sync_frequency_direction_widget_state(self, minigame)
	_ensure_frequency_direction_widgets(self)
	_set_frequency_direction_widgets(self, minigame)
end

local function _create_balance_progress_mask_widget(name, offset_x, offset_y, z, min_u, max_u, min_v, max_v, width, height)
	local definition = UIWidget.create_definition({
		{
			pass_type = "texture_uv",
			style_id = "progress_mask",
			value = BALANCE_PROGRESS_TEXTURE,
			style = {
				hdr = true,
				color = table.clone(BALANCE_PROGRESS_MASK_COLOR),
				offset = {
					offset_x,
					offset_y,
					z,
				},
				size = {
					width,
					height,
				},
				uvs = {
					{
						min_u,
						min_v,
					},
					{
						max_u,
						max_v,
					},
				},
			},
		},
	}, "center_pivot", nil, {
		width,
		height,
	})

	local widget = UIWidget.init(name, definition)
	local style = widget.style.progress_mask

	style.__base_offset_y = offset_y
	style.__base_height = height
	style.__base_min_u = min_u
	style.__base_max_u = max_u
	style.__base_min_v = min_v
	style.__base_max_v = max_v

	return widget
end

function MinigameDecodeSymbolsView:update(dt, t, widgets_by_name)
	local minigame_extension = self._minigame_extension
	local minigame = minigame_extension and minigame_extension:minigame(MinigameSettings.types.decode_symbols)

	if not minigame or minigame:is_completed() then
		return
	end

	local decode_start_time = minigame:start_time()

	if #self._grid_widgets == 0 then
		self:_create_symbol_widgets()
	end

	if #self._grid_widgets > 0 and decode_start_time then
		local t_view = _scanner_view_time()
		local on_target = minigame:is_on_target(t_view)

		self:_draw_cursor(widgets_by_name, decode_start_time, on_target, t_view)
		self:_draw_targets(widgets_by_name, decode_start_time, on_target)
	end
end

function MinigameDrillView:_update_background(widgets_by_name, minigame)
	local stage = minigame:current_stage()
	local targets = minigame:targets()
	local correct_targets = minigame:correct_targets()

	if not stage or #correct_targets == 0 then
		return
	end

	local widget_size = ScannerDisplayViewDrillSettings.background_rings_size
	local starting_offset_x = ScannerDisplayViewDrillSettings.board_starting_offset_x
	local starting_offset_y = ScannerDisplayViewDrillSettings.board_starting_offset_y
	local state = minigame:state()
	local in_transition = state ~= MinigameSettings.game_states.gameplay
	local scale_percentage = 1
	local previous_pos = {
		x = 0,
		y = 0,
	}
	local current_pos = {
		x = 0,
		y = 0,
	}

	if stage > 2 then
		local s = stage - 2

		previous_pos = targets[s][correct_targets[s]]
	end

	if stage > 1 then
		local s = stage - 1

		current_pos = targets[s][correct_targets[s]]
	end

	local x_pos, y_pos

	if in_transition then
		local t_view = _scanner_view_time()
		local transition_percentage = minigame:transition_percentage(t_view)
		local move_percentage = math.clamp(transition_percentage * 2, 0, 1)

		x_pos = math.lerp(previous_pos.x, current_pos.x, move_percentage)
		y_pos = math.lerp(previous_pos.y, current_pos.y, move_percentage)
		scale_percentage = math.clamp(transition_percentage * 2 - 1, 0, 1)
	else
		x_pos = current_pos.x
		y_pos = current_pos.y
	end

	x_pos = starting_offset_x + x_pos * ScannerDisplayViewDrillSettings.board_width
	y_pos = starting_offset_y + y_pos * ScannerDisplayViewDrillSettings.board_height

	local background_widgets = self._background_widgets

	for i = 1, #background_widgets do
		local widget = background_widgets[i]
		local size = widget.content.size
		local scale = (i - 1 + scale_percentage) / 3

		size[1] = widget_size[1] * scale
		size[2] = widget_size[2] * scale
		widget.offset[1] = x_pos - size[1] / 2
		widget.offset[2] = y_pos - size[2] / 2
	end
end

function MinigameDrillView:_update_target(widgets_by_name, minigame, t)
	local stage = minigame:current_stage()

	if not stage or stage > #self._target_widgets then
		return
	end

	local on_target = minigame:is_on_target()
	local selected_index = minigame:selected_index()
	local correct_target = minigame:correct_targets()[stage]
	local positions = minigame:targets()[stage]
	local target_position = positions[correct_target]
	local is_searching = minigame:is_searching()
	local t_view = _scanner_view_time()
	local search_percentage = minigame:search_percentage(t_view)
	local target_widgets = self._target_widgets[stage]
	local helper_enabled = _drill_helper_enabled()
	local highlight_color = helper_enabled and _drill_highlight_color() or nil

	for i = 1, #target_widgets do
		local widget = target_widgets[i]

		if selected_index == i and is_searching and search_percentage >= 1 then
			if on_target then
				widget.style.highlight.color = {
					255,
					255,
					255,
					255,
				}
			else
				widget.style.highlight.color = {
					255,
					255,
					0,
					0,
				}
			end
		elseif highlight_color and i == correct_target then
			local pulse_alpha = math.clamp(0.7 + math.cos(t * 4) * 0.3, 0, 1)

			widget.style.highlight.color = {
				math.floor(highlight_color[1] * pulse_alpha),
				highlight_color[2],
				highlight_color[3],
				highlight_color[4],
			}
		else
			if helper_enabled then
				widget.style.highlight.color = {
					110,
					0,
					160,
					0,
				}
			else
				local target = positions[i]
				local distance = math.sqrt((target_position.x - target.x) * (target_position.x - target.x) + (target_position.y - target.y) * (target_position.y - target.y))
				local alpha = math.clamp(0.55 + math.cos(t + distance * 3) * 0.45, 0, 1)

				widget.style.highlight.color = {
					alpha * 255,
					0,
					255,
					0,
				}
			end
		end
	end
end

function MinigameDrillView:_update_search(widgets_by_name, minigame)
	local cursor_position = minigame:cursor_position()

	if not cursor_position then
		return
	end

	local state = minigame:state()
	local on_target = minigame:is_on_target()
	local t_view = _scanner_view_time()
	local is_searching = minigame:is_searching()
	local search_percentage = minigame:search_percentage(t_view)
	local starting_offset_x = ScannerDisplayViewDrillSettings.board_starting_offset_x
	local starting_offset_y = ScannerDisplayViewDrillSettings.board_starting_offset_y
	local widget = widgets_by_name.search_fade

	widget.style.frame.offset[1] = starting_offset_x + cursor_position.x * ScannerDisplayViewDrillSettings.board_width - widget.content.size[1] / 2
	widget.style.frame.offset[2] = starting_offset_y + cursor_position.y * ScannerDisplayViewDrillSettings.board_height - widget.content.size[2] / 2
	widget.style.frame.offset[3] = 3

	if state ~= MinigameSettings.game_states.gameplay then
		widget.style.frame.color = {
			0,
			0,
			0,
			0,
		}
	elseif is_searching then
		if search_percentage >= 1 then
			if on_target then
				widget.style.frame.color = {
					255,
					255,
					255,
					255,
				}
			else
				widget.style.frame.color = {
					255,
					255,
					0,
					0,
				}
			end
		else
			local alpha = search_percentage * 255

			widget.style.frame.color = {
				alpha,
				0,
				255,
				0,
			}
		end
	else
		widget.style.frame.color = {
			0,
			0,
			0,
			0,
		}
	end
end

function MinigameDrillView:_update_cursor(widgets_by_name, minigame)
	local cursor_position = minigame:cursor_position()

	if not cursor_position then
		return
	end

	local state = minigame:state()
	local on_target = minigame:is_on_target()
	local t_view = _scanner_view_time()
	local selected_index = minigame:selected_index()
	local search_percentage = minigame:search_percentage(t_view)
	local starting_offset_x = ScannerDisplayViewDrillSettings.board_starting_offset_x
	local starting_offset_y = ScannerDisplayViewDrillSettings.board_starting_offset_y
	local widget = widgets_by_name.cursor

	widget.style.frame.offset[1] = starting_offset_x + cursor_position.x * ScannerDisplayViewDrillSettings.board_width - widget.content.size[1] / 2
	widget.style.frame.offset[2] = starting_offset_y + cursor_position.y * ScannerDisplayViewDrillSettings.board_height - widget.content.size[2] / 2
	widget.style.frame.offset[3] = 5

	if state ~= MinigameSettings.game_states.gameplay then
		widget.style.frame.color = {
			0,
			0,
			0,
			0,
		}
	elseif not selected_index then
		widget.style.frame.color = {
			255,
			255,
			255,
			255,
		}
	elseif search_percentage >= 1 then
		if on_target then
			widget.style.frame.color = {
				255,
				255,
				255,
				255,
			}
		else
			widget.style.frame.color = {
				255,
				255,
				0,
				0,
			}
		end
	else
		local alpha = 255 - search_percentage * 255

		widget.style.frame.color = {
			alpha,
			255,
			255,
			255,
		}
	end
end

local function _ensure_overlay_balance_progress_widgets(self)
	local source_widget = self._auspex_helper_balance_progress_widget

	if not source_widget or not source_widget.style or not source_widget.style.progress_texture or not source_widget.content or not source_widget.content.size then
		return nil
	end

	local source_style = source_widget.style.progress_texture
	local source_size = source_widget.content.size
	local width = source_size[1] * 0.5
	local source_height = source_size[2]
	local height = ScannerDisplayViewBalanceSettings.progress_widget_size[2]
	local offset_x = source_style.offset[1]
	local offset_y = ScannerDisplayViewBalanceSettings.progress_starting_offset_y
	local offset_z = (source_style.offset[3] or 0) + 1
	local active_top = offset_y - source_style.offset[2]
	local min_v = math.clamp(active_top / source_height, 0, 1)
	local max_v = math.clamp((active_top + height) / source_height, 0, 1)
	local widgets = self._auspex_helper_overlay_balance_progress_widgets
	local widgets_match_source = widgets
		and self._auspex_helper_overlay_balance_width == width
		and self._auspex_helper_overlay_balance_height == height
		and self._auspex_helper_overlay_balance_offset_x == offset_x
		and self._auspex_helper_overlay_balance_offset_y == offset_y
		and self._auspex_helper_overlay_balance_offset_z == offset_z
		and self._auspex_helper_overlay_balance_min_v == min_v
		and self._auspex_helper_overlay_balance_max_v == max_v

	if widgets_match_source then
		return widgets
	end

	self._auspex_helper_overlay_balance_width = width
	self._auspex_helper_overlay_balance_height = height
	self._auspex_helper_overlay_balance_offset_x = offset_x
	self._auspex_helper_overlay_balance_offset_y = offset_y
	self._auspex_helper_overlay_balance_offset_z = offset_z
	self._auspex_helper_overlay_balance_min_v = min_v
	self._auspex_helper_overlay_balance_max_v = max_v
	self._auspex_helper_overlay_balance_progress_widgets = {
		_create_balance_progress_mask_widget("balance_overlay_progress_01", offset_x, offset_y, offset_z, 0, 0.5, min_v, max_v, width, height),
		_create_balance_progress_mask_widget("balance_overlay_progress_02", offset_x + width, offset_y, offset_z, 0.5, 1, min_v, max_v, width, height),
	}

	return self._auspex_helper_overlay_balance_progress_widgets
end

local function _draw_overlay_balance_progress(self, progress, ui_renderer)
	local widgets = _ensure_overlay_balance_progress_widgets(self)

	if not widgets then
		return
	end

	local visible_ratio = math.clamp(1 - progress, 0, 1)

	if visible_ratio <= 0 then
		return
	end

	for i = 1, #widgets do
		local widget = widgets[i]
		local style = widget.style.progress_mask
		local visible_height = style.__base_height * visible_ratio
		local uvs = style.uvs
		local vertical_uv_range = style.__base_max_v - style.__base_min_v

		style.size[2] = visible_height
		style.offset[2] = style.__base_offset_y
		uvs[1][1] = style.__base_min_u
		uvs[1][2] = style.__base_min_v
		uvs[2][1] = style.__base_max_u
		uvs[2][2] = style.__base_min_v + vertical_uv_range * visible_ratio

		UIWidget.draw(widget, ui_renderer)
	end
end

local function _draw_overlay_drill_background(self, ui_renderer)
	if not _overlay_show_drill_sonar() then
		return
	end

	local background_widgets = self._background_widgets

	if not background_widgets or #background_widgets == 0 then
		return
	end

	local outline_half_width = OVERLAY_OUTLINE_SIZE[1] * 0.5
	local outline_half_height = OVERLAY_OUTLINE_SIZE[2] * 0.5

	for i = 1, #background_widgets do
		local widget = background_widgets[i]
		local size = widget.content and widget.content.size
		local offset = widget.offset

		if size and offset then
			local center_x = offset[1] + size[1] * 0.5
			local center_y = offset[2] + size[2] * 0.5
			local max_half_width = math.max(0, outline_half_width - math.abs(center_x))
			local max_half_height = math.max(0, outline_half_height - math.abs(center_y))
			local max_size = math.max(0, math.min(max_half_width * 2, max_half_height * 2))

			if max_size > 1 then
				local draw_size = math.min(size[1], size[2], max_size)
				local style = widget.style and widget.style.highlight

				if style and style.size then
					style.size[1] = draw_size
					style.size[2] = draw_size
				end

				if style and style.color then
					if style.__auspex_helper_base_alpha == nil then
						style.__auspex_helper_base_alpha = style.color[1] or 255
					end

					style.color[1] = math.floor(style.__auspex_helper_base_alpha * DRILL_OVERLAY_SONAR_ALPHA_MULTIPLIER)
				end

				offset[1] = center_x - draw_size * 0.5
				offset[2] = center_y - draw_size * 0.5
				size[1] = draw_size
				size[2] = draw_size

				UIWidget.draw(widget, ui_renderer)
			end
		end
	end
end

local function _draw_stock_drill_background(self, ui_renderer)
	if not _overlay_show_drill_sonar() then
		return
	end

	local background_widgets = self._background_widgets

	if not background_widgets or #background_widgets == 0 then
		return
	end

	for i = 1, #background_widgets do
		local widget = background_widgets[i]

		if widget then
			UIWidget.draw(widget, ui_renderer)
		end
	end
end

local function _draw_drill_direction_widgets(self, ui_renderer)
	local widgets = self._auspex_helper_drill_direction_widgets

	if not widgets then
		return
	end

	local draw_order = self._auspex_helper_drill_direction_widget_order or {
		"left",
		"right",
		"up",
		"down",
	}

	for index = 1, #draw_order do
		local widget = widgets[draw_order[index]]

		if widget then
			UIWidget.draw(widget, ui_renderer)
		end
	end
end

MinigameDrillView.draw_widgets = function (self, dt, t, input_service, ui_renderer)
	if not self._auspex_helper_overlay_drill then
		local minigame_extension = self._minigame_extension

		if not minigame_extension or not self._target_widgets or not self._stage_widgets then
			return
		end

		local minigame = minigame_extension:minigame(MinigameSettings.types.drill)
		local current_stage = minigame:current_stage()
		local state = minigame:state()

		if mod._set_drill_direction_widgets then
			mod._set_drill_direction_widgets(self, minigame)
		end

		_draw_stock_drill_background(self, ui_renderer)

		if not current_stage or current_stage > #self._target_widgets then
			_draw_drill_direction_widgets(self, ui_renderer)

			return
		end

		if state == MinigameSettings.game_states.gameplay then
			local target_widgets = self._target_widgets[current_stage]

			for i = 1, #target_widgets do
				local widget = target_widgets[i]

				UIWidget.draw(widget, ui_renderer)
			end
		end

		local stage_widgets = self._stage_widgets

		for i = 1, #stage_widgets do
			local widget = stage_widgets[i]

			if i < current_stage or i == current_stage and t % 1 > 0.5 then
				widget.style.highlight.color = {
					255,
					0,
					255,
					0,
				}
			else
				widget.style.highlight.color = {
					255,
					0,
					64,
					0,
				}
			end

			UIWidget.draw(widget, ui_renderer)
		end

		_draw_drill_direction_widgets(self, ui_renderer)

		return
	end

	local minigame_extension = self._minigame_extension

	if not minigame_extension or not self._target_widgets or not self._stage_widgets then
		return
	end

	local minigame = minigame_extension:minigame(MinigameSettings.types.drill)
	local current_stage = minigame:current_stage()
	local state = minigame:state()

	if mod._set_drill_direction_widgets then
		mod._set_drill_direction_widgets(self, minigame)
	end

	if not current_stage or current_stage > #self._target_widgets then
		return
	end

	_draw_overlay_drill_background(self, ui_renderer)

	if state == MinigameSettings.game_states.gameplay or state == MinigameSettings.game_states.transition then
		local target_widgets = self._target_widgets[current_stage]

		for i = 1, #target_widgets do
			UIWidget.draw(target_widgets[i], ui_renderer)
		end
	end

	local stage_widgets = self._stage_widgets

	for i = 1, #stage_widgets do
		local widget = stage_widgets[i]

		if i < current_stage or i == current_stage and t % 1 > 0.5 then
			widget.style.highlight.color = {
				255,
				0,
				255,
				0,
			}
		else
			widget.style.highlight.color = {
				255,
				0,
				64,
				0,
			}
		end

		UIWidget.draw(widget, ui_renderer)
	end

	_draw_drill_direction_widgets(self, ui_renderer)
end

MinigameFrequencyView._draw_frequency = function (self, frequency, color, t, ui_renderer)
	if not self._auspex_helper_overlay_frequency then
		return STOCK_DRAW_FREQUENCY(self, frequency, color, t, ui_renderer)
	end

	if not self._frequency_widgets or #self._frequency_widgets == 0 then
		return
	end

	local visible_width = _overlay_frequency_visible_width()
	local widget_width = ScannerDisplayViewFrequencySettings.frequency_widget_size[1] * frequency.x
	local widget_height = ScannerDisplayViewFrequencySettings.frequency_widget_size[2] * frequency.y

	if visible_width <= 0 or widget_width <= 0 or widget_height <= 0 then
		return
	end

	OVERLAY_FREQUENCY_WIDGET_SIZE[1] = widget_width
	OVERLAY_FREQUENCY_WIDGET_SIZE[2] = widget_height

	local left_edge = -visible_width * 0.5
	local right_edge = visible_width * 0.5
	local starting_offset_y = ScannerDisplayViewFrequencySettings.frequency_starting_offset_y
	local scroll_fraction = t * MinigameSettings.frequency_speed % 1
	local max_widgets = math.min(#self._frequency_widgets, math.ceil(visible_width / widget_width) + 3)

	for i = 1, max_widgets do
		local widget = self._frequency_widgets[i]
		local offset_x = left_edge + widget_width * (i - 1 - scroll_fraction)
		local right = offset_x + widget_width

		if offset_x >= left_edge and right <= right_edge then
			widget.content.size = OVERLAY_FREQUENCY_WIDGET_SIZE
			widget.style.style_id_1.color = color
			widget.offset[1] = offset_x
			widget.offset[2] = starting_offset_y - widget_height * 0.5
			widget.offset[3] = 1

			UIWidget.draw(widget, ui_renderer)
		end
	end
end

MinigameFrequencyView.draw_widgets = function (self, dt, t, input_service, ui_renderer)
	STOCK_DRAW_FREQUENCY_WIDGETS(self, dt, t, input_service, ui_renderer)

	local minigame_extension = self._minigame_extension
	local minigame = minigame_extension and minigame_extension:minigame(MinigameSettings.types.frequency) or nil

	_sync_frequency_direction_widget_state(self, minigame)
	_draw_frequency_direction_widgets(self, ui_renderer)
end

MinigameBalanceView.update = function (self, dt, t, widgets_by_name)
	if self._auspex_helper_overlay_balance and widgets_by_name then
		self._auspex_helper_balance_progress_widget = widgets_by_name.balance_progress
	end

	return STOCK_UPDATE_BALANCE_WIDGETS(self, dt, t, widgets_by_name)
end

MinigameBalanceView.draw_widgets = function (self, dt, t, input_service, ui_renderer)
	if not self._auspex_helper_overlay_balance then
		return STOCK_DRAW_BALANCE_WIDGETS(self, dt, t, input_service, ui_renderer)
	end

	local minigame_extension = self._minigame_extension

	if not minigame_extension then
		return
	end

	local minigame = minigame_extension:minigame(MinigameSettings.types.balance)

	if not minigame or minigame:is_completed() then
		return
	end

	_draw_overlay_balance_progress(self, minigame:progression(), ui_renderer)
end

function AuspexOverlayView:init(settings, context)
	local minigame_type = context.minigame_type or MinigameSettings.types.none
	local is_world_scan_icons = context.auspex_helper_world_scan_icons == true
	local definitions = is_world_scan_icons and WORLD_SCAN_ICON_VIEW_DEFINITIONS or _definitions_for(minigame_type)

	AuspexOverlayView.super.init(self, definitions, settings, context)

	self._base_render_scale = nil
	self._is_practice = context.auspex_helper_is_practice == true
	self._is_world_scan_overlay = context.auspex_helper_world_scan_overlay == true
	self._is_world_scan_icons = is_world_scan_icons
	self._last_backdrop_alpha = false
	self._last_show_decorations = nil
	self._minigame_type = minigame_type
	self._overlay_scale = nil
	self._backdrop_color = {
		0,
		0,
		0,
		0,
	}
	self._frame_color = _scanner_green(128)
	self._outline_color = _scanner_green(70)
	self._decoration_color = _scanner_green(255)
	self._hidden_color = {
		0,
		0,
		0,
		0,
	}

	if self._is_practice or self._is_world_scan_overlay or self._is_world_scan_icons then
		-- Practice/world-scan input is handled outside the view itself, so these
		-- overlay views must not block menu/back input from reaching the normal
		-- UI stack.
		self._pass_input = true
	end

	if self._is_world_scan_overlay or self._is_world_scan_icons then
		return
	end

	local minigame_class = AuspexOverlayView.MINIGAMES[minigame_type] or AuspexOverlayView.MINIGAMES[MinigameSettings.types.none]

	self._minigame = minigame_class:new(context)

	if minigame_type == MinigameSettings.types.drill and self._minigame then
		self._minigame._auspex_helper_overlay_drill = true
	end

	if minigame_type == MinigameSettings.types.frequency and self._minigame then
		self._minigame._auspex_helper_overlay_frequency = true
	end

	if minigame_type == MinigameSettings.types.balance and self._minigame then
		self._minigame._auspex_helper_overlay_balance = true
	end
end

function AuspexOverlayView:on_enter()
	self._base_render_scale = Managers.ui:view_render_scale()

	if self._is_world_scan_icons then
		return
	end

	self:_refresh_overlay_scale(true)
	self:_refresh_frame_style(true)
end

function AuspexOverlayView:is_using_input()
	return false
end

function AuspexOverlayView:_refresh_overlay_scale(force)
	local overlay_scale = _overlay_scale()

	if not force and overlay_scale == self._overlay_scale then
		return
	end

	self._overlay_scale = overlay_scale
	self:set_render_scale((self._base_render_scale or 1) * overlay_scale)

	if self._ui_scenegraph and next(self._ui_scenegraph) ~= nil then
		self:trigger_resolution_update()
	end
end

function AuspexOverlayView:_refresh_frame_style(force)
	local widgets_by_name = self._widgets_by_name
	local backdrop_alpha = _overlay_backdrop_alpha()
	local show_decorations = _overlay_show_decorations()
	local overlay_red = mod:get("overlay_color_red") or 0
	local overlay_green = mod:get("overlay_color_green") or 255
	local overlay_blue = mod:get("overlay_color_blue") or 110
	local overlay_alpha = math.clamp(mod:get("overlay_color_alpha") or 255, 0, 255)
	local backdrop_widget = widgets_by_name.overlay_backdrop
	local outline_widget = widgets_by_name.overlay_outline

	if not force
		and backdrop_alpha == self._last_backdrop_alpha
		and show_decorations == self._last_show_decorations
		and overlay_red == self._last_overlay_color_red
		and overlay_green == self._last_overlay_color_green
		and overlay_blue == self._last_overlay_color_blue
		and overlay_alpha == self._last_overlay_color_alpha then
		return
	end

	self._last_backdrop_alpha = backdrop_alpha
	self._last_show_decorations = show_decorations
	self._last_overlay_color_red = overlay_red
	self._last_overlay_color_green = overlay_green
	self._last_overlay_color_blue = overlay_blue
	self._last_overlay_color_alpha = overlay_alpha

	_set_color(self._backdrop_color, backdrop_alpha, 0, 0, 0)
	_set_color(self._frame_color, math.floor(128 * (overlay_alpha / 255)), overlay_red, overlay_green, overlay_blue)
	_set_color(self._outline_color, math.floor(70 * (overlay_alpha / 255)), overlay_red, overlay_green, overlay_blue)
	_set_color(self._decoration_color, overlay_alpha, overlay_red, overlay_green, overlay_blue)

	if backdrop_widget and backdrop_widget.style and backdrop_widget.style.background then
		backdrop_widget.style.background.color = self._backdrop_color
	end

	if outline_widget and outline_widget.style and outline_widget.style.frame then
		outline_widget.style.frame.color = self._outline_color
	end

	for index = 1, #OVERLAY_FRAME_WIDGETS do
		local widget = widgets_by_name[OVERLAY_FRAME_WIDGETS[index]]

		if widget and widget.style and widget.style.frame then
			widget.style.frame.color = self._frame_color
		end
	end

	for index = 1, #OVERLAY_DECORATION_WIDGETS do
		local widget = widgets_by_name[OVERLAY_DECORATION_WIDGETS[index]]

		if widget and widget.style and widget.style.highlight then
			widget.style.highlight.color = show_decorations and self._decoration_color or self._hidden_color
		end
	end
end

function AuspexOverlayView:update(dt, t, input_service)
	if self._auspex_helper_renderer_missing then
		local ui_manager = Managers.ui

		self._auspex_helper_renderer_missing = nil

		if ui_manager and self.view_name and (ui_manager:view_active(self.view_name) or ui_manager:is_view_closing(self.view_name)) then
			ui_manager:close_view(self.view_name, true)
		end

		return
	end

	if not _has_gameplay_timer() and not (self._is_practice and _preview_supports_missing_gameplay_timer()) then
		local ui_manager = Managers.ui

		if self._is_practice then
			mod._preview_gameplay_timer_missing = true
		end

		if ui_manager and self.view_name and (ui_manager:view_active(self.view_name) or ui_manager:is_view_closing(self.view_name)) then
			ui_manager:close_view(self.view_name, true)
		end

		return
	end

	if self._is_world_scan_icons then
		return AuspexOverlayView.super.update(self, dt, t, input_service)
	end

	self:_refresh_overlay_scale(false)
	self:_refresh_frame_style(false)

	if self._minigame and self._minigame.update then
		self._minigame:update(dt, t, self._widgets_by_name)
	end

	return AuspexOverlayView.super.update(self, dt, t, input_service)
end

function AuspexOverlayView:draw(dt, t, input_service, layer)
	local ui_renderer = self._ui_renderer

	if not ui_renderer then
		self._auspex_helper_renderer_missing = true
		return
	end

	return AuspexOverlayView.super.draw(self, dt, t, input_service, layer)
end

function AuspexOverlayView:_draw_widgets(dt, t, input_service, ui_renderer, render_settings)
	if not ui_renderer or not ui_renderer.gui then
		return
	end

	AuspexOverlayView.super._draw_widgets(self, dt, t, input_service, ui_renderer, render_settings)

	if self._is_world_scan_icons then
		_draw_world_scan_screen_icons(self, ui_renderer)

		return
	end

	if self._is_world_scan_overlay then
		_draw_world_scan_overlay(self, t, ui_renderer)

		return
	end

	if self._minigame and self._minigame.draw_widgets then
		self._minigame:draw_widgets(dt, t, input_service, ui_renderer)
	end
end

function AuspexOverlayView:destroy()
	self._world_scan_overlay_widgets = nil
	self._world_scan_icon_widgets = nil
	self._elements = self._elements or {}
	self._elements_array = self._elements_array or {}

	if self._minigame then
		self._minigame:delete()
		self._minigame = nil
	end

	local renderer_name = self.__class_name and (self.__class_name .. "_ui_renderer") or nil
	local ui_manager = Managers.ui
	local has_registered_renderer = renderer_name and ui_manager and ui_manager._renderers and ui_manager._renderers[renderer_name] ~= nil

	if not self._ui_renderer or not has_registered_renderer then
		self._elements = nil
		self._elements_array = nil
		self._ui_renderer = nil
		return
	end

	AuspexOverlayView.super.destroy(self)
end

return AuspexOverlayView
