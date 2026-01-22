--[[
	File: lobby/talent_preview_lobby.lua
	Description: Label, icon logic file
	Overall Release Version: 1.1.0
	File Version: 1.1.0
	Last Updated: 2026-01-21
	Author: LAUREHTE
]]

local mod = get_mod("TalentPreview")

local UIWidget = require("scripts/managers/ui/ui_widget")
local NodeLayout
local success_node_layout, node_layout_module = pcall(require, "scripts/ui/views/node_builder_view_base/utilities/node_layout")
if success_node_layout then
    NodeLayout = node_layout_module
end
local TalentBuilderViewSettings = require("scripts/ui/views/talent_builder_view/talent_builder_view_settings")
local TalentLayoutParser = require("scripts/ui/views/talent_builder_view/utilities/talent_layout_parser")
local ContentBlueprints = require("scripts/ui/views/lobby_view/lobby_view_content_blueprints")

local TALENT_VIEW_PACKAGE = "packages/ui/views/talent_builder_view/talent_builder_view"
local BROKER_STIMM_VIEW_PACKAGE = "packages/ui/views/broker_stimm_builder_view/broker_stimm_builder_view"
local MAIN_MENU_VIEW_PACKAGE = "packages/ui/views/main_menu_view/main_menu_view"
local ICON_LOAD_REFERENCE = "TalentPreview"

local CATEGORY_ORDER = {
    "keystone",
    "stat",
    "default",
    "blitz",
    "modifier",
}

local NODE_CATEGORY = {
    keystone = "keystone",
    keystone_modifier = "keystone",
    stat = "stat",
    default = "default",
    iconic = "default",   
    ability = "modifier",
    ability_modifier = "modifier",
    tactical = "blitz",
    tactical_modifier = "blitz",
    aura = "modifier",
    aura_modifier = "modifier",
    broker_stimm = "default",
}

local SKIP_NODE_TYPE = {
    start = true,
}

local EMPTY_TABLE = {}
local loaded_archetypes = {}
local loading_archetypes = {}
local talent_packages_loaded = false
local loaded_packages = {}

local function _is_lobby_view_active()
    local ui_manager = Managers.ui

    if not ui_manager or not ui_manager.view_active then
        return false
    end

    return ui_manager:view_active("lobby_view")
end

local function _ensure_preview_packages()
    local package_manager = Managers.package
    if not package_manager then
        return
    end

    if not loaded_packages[TALENT_VIEW_PACKAGE] then
        loaded_packages[TALENT_VIEW_PACKAGE] = package_manager:load(TALENT_VIEW_PACKAGE, ICON_LOAD_REFERENCE, nil, true) or true
    end

    if not loaded_packages[BROKER_STIMM_VIEW_PACKAGE] then
        loaded_packages[BROKER_STIMM_VIEW_PACKAGE] = package_manager:load(BROKER_STIMM_VIEW_PACKAGE, ICON_LOAD_REFERENCE, nil, true) or true
    end

    if mod:get("preview_background_character") and not loaded_packages[MAIN_MENU_VIEW_PACKAGE] then
        loaded_packages[MAIN_MENU_VIEW_PACKAGE] = package_manager:load(MAIN_MENU_VIEW_PACKAGE, ICON_LOAD_REFERENCE, nil, true) or true
    end
end

local function _on_archetype_icons_loaded(archetype_name)
    loaded_archetypes[archetype_name] = true
    loading_archetypes[archetype_name] = nil
    mod._pending_refresh = true
end

local function _ensure_talent_icon_packages(profile)
    local talents_service = Managers.data_service and Managers.data_service.talents
    if not talents_service then
        return
    end

    if not talent_packages_loaded then
        _ensure_preview_packages()
        talent_packages_loaded = true
    end

    if not talents_service.load_icons_for_profile then
        return
    end

    local archetype = profile and profile.archetype
    local archetype_name = archetype and archetype.name

    if not archetype_name or loaded_archetypes[archetype_name] or loading_archetypes[archetype_name] then
        return
    end

    local on_loaded = callback(_on_archetype_icons_loaded, archetype_name)
    loading_archetypes[archetype_name] = talents_service:load_icons_for_profile(profile, ICON_LOAD_REFERENCE, on_loaded, true) or true
end

local function _safe_number(value, fallback)
    if type(value) ~= "number" or value ~= value then
        return fallback
    end

    return value
end

local function _get_icon_size()
    return math.floor(_safe_number(mod:get("icon_size"), 36))
end

local function _get_icons_per_row()
    local value = math.floor(_safe_number(mod:get("icons_per_row"), 6))

    if value < 1 then
        return 1
    end

    return value
end

local function _get_preview_offset_y()
    local value = math.floor(_safe_number(mod:get("preview_offset_y"), 80))

    if value < 0 then
        return 0
    end

    return value
end

local function _get_preview_offset_x()
    local value = math.floor(_safe_number(mod:get("preview_offset_x"), 0))

    return value
end

local function _category_enabled(category)
    if category == "keystone" then
        return mod:get("show_keystone") ~= false
    elseif category == "stat" then
        return mod:get("show_stat") ~= false
    elseif category == "default" then
        return mod:get("show_default") ~= false
    elseif category == "blitz" then
        return mod:get("show_blitz") ~= false
    elseif category == "modifier" then
        return mod:get("show_modifiers") ~= false
    end

    return true
end

local function _collect_selected_nodes(profile)
    if not profile or not profile.archetype or not profile.archetype.talents then
        return nil, ""
    end

    local archetype = profile.archetype
    local selected_talents = profile.talents or EMPTY_TABLE
    local fallback_icon = NodeLayout and NodeLayout.fallback_icon and NodeLayout.fallback_icon()
        or "content/ui/textures/icons/talents/psyker/psyker_ability_discharge"
    local entries_by_category = {
        keystone = {},
        stat = {},
        default = {},
        blitz = {},
        modifier = {},
    }
    local signature_parts = {}
    local order = 0

    local function add_node(node)
        local node_type = node.type

        if SKIP_NODE_TYPE[node_type] then
            return
        end

        local talent_name = node.talent
        if not talent_name or talent_name == "not_selected" then
            return
        end

        local tier = selected_talents[talent_name]
        if not tier or tier <= 0 then
            return
        end

        if node_type == "aura" and mod:get("show_aura") == false then
            return
        end

        if node_type == "ability_modifier" and mod:get("show_ability_modifiers") == false then
            return
        end

        if node_type == "broker_stimm" and mod:get("show_broker_stimm") == false then
            return
        end

        local category = NODE_CATEGORY[node_type]
        if not category or not _category_enabled(category) then
            return
        end

        local talent = archetype.talents[talent_name]
        if not talent then
            return
        end

        order = order + 1

        local icon = node.icon or talent.large_icon or talent.icon
        if type(icon) == "string" then
            if icon == "" or icon:find("icon here", 1, true) or not icon:match("^content/") then
                icon = nil
            end
        else
            icon = nil
        end
        if not icon or icon == "" then
            icon = fallback_icon
        end

        entries_by_category[category][#entries_by_category[category] + 1] = {
            talent = talent,
            talent_name = talent_name,
            node_type = node_type,
            icon = icon,
            points_spent = tier,
            order = order,
        }

        signature_parts[#signature_parts + 1] = string.format("%s:%s:%s", talent_name, node_type, tostring(tier))
    end

    local function process_layout(layout_path)
        if not layout_path then
            return
        end

        local layout = require(layout_path)
        local nodes = layout and layout.nodes

        if not nodes then
            return
        end

        for i = 1, #nodes do
            add_node(nodes[i])
        end
    end

    process_layout(archetype.talent_layout_file_path)
    process_layout(archetype.specialization_talent_layout_file_path)

    for _, category in ipairs(CATEGORY_ORDER) do
        table.sort(entries_by_category[category], function(a, b)
            return a.order < b.order
        end)
    end

    table.sort(signature_parts)

    return entries_by_category, table.concat(signature_parts, "|")
end

local function _clear_preview_widgets(self, spawn_slot)
    if not spawn_slot then
        return
    end

    if spawn_slot.talent_preview_background then
        self:_unregister_widget_name(spawn_slot.talent_preview_background.name)
        spawn_slot.talent_preview_background = nil
    end

    local widgets = spawn_slot.talent_preview_widgets
    if not widgets then
        spawn_slot.talent_preview_signature = nil
        spawn_slot.talent_preview_widgets = {}
        return
    end

    for i = 1, #widgets do
        local widget = widgets[i]
        self:_unregister_widget_name(widget.name)
    end

    spawn_slot.talent_preview_widgets = {}
    spawn_slot.talent_preview_signature = nil
end

local function _build_preview_widgets(self, spawn_slot, entries_by_category)
    local icon_size = _get_icon_size()
    local icons_per_row = _get_icons_per_row()
    local margin = math.max(4, math.floor(icon_size * 0.15))
    local row_gap = math.max(3, math.floor(icon_size * 0.075))
    local start_margin = 20
    local base_offset_x = _get_preview_offset_x()
    local base_offset_y = -(ContentBlueprints.talent.size[2] + 8) - _get_preview_offset_y()
    local row_height = icon_size + row_gap
    local column_width = icon_size + margin
    local scenegraph_id = "loadout"
    local settings_by_node_type = TalentBuilderViewSettings.settings_by_node_type
    local template = ContentBlueprints.talent
    local size = {
        icon_size,
        icon_size,
    }

    local current_offset_y = base_offset_y
    local widget_index = 0
    local min_x, max_x, min_y, max_y

    for _, category in ipairs(CATEGORY_ORDER) do
        local entries = entries_by_category[category]

        if #entries > 0 then
            local rows = math.ceil(#entries / icons_per_row)

            for i = 1, #entries do
                local entry = entries[i]
                local row = math.floor((i - 1) / icons_per_row)
                local col = (i - 1) % icons_per_row
                local offset_width = start_margin + column_width * col + base_offset_x
                local offset_height = current_offset_y - row_height * row
                local widget_definition
                local config
                local node_type_settings

                node_type_settings = settings_by_node_type[entry.node_type] or settings_by_node_type.default
                config = {
                    loadout = {
                        icon = entry.icon,
                    },
                    node_type_settings = node_type_settings,
                    loadout_id = entry.node_type,
                }
                local pass_template_function = template.pass_template_function
                local pass_template = pass_template_function and pass_template_function(self, config) or template.pass_template
                local optional_style = template.style or {}
                widget_definition = pass_template and UIWidget.create_definition(pass_template, scenegraph_id, nil, size, optional_style)

                if widget_definition then
                    widget_index = widget_index + 1

                    local name_talent = string.format("talent_preview_%s_%s", spawn_slot.index, widget_index)
                    local talent_widget = self:_create_widget(name_talent, widget_definition)
                    local init = template.init

                    if init then
                        init(self, talent_widget, config)
                    end

                    local talent_style = talent_widget.style and talent_widget.style.talent
                    local material_values = talent_style and talent_style.material_values
                    if material_values and node_type_settings then
                        material_values.frame = node_type_settings.frame or material_values.frame
                        material_values.icon_mask = node_type_settings.icon_mask or material_values.icon_mask
                        material_values.gradient_map = node_type_settings.gradient_map or material_values.gradient_map
                    end

                    if entry.node_type == "default" or entry.node_type == "stat" or entry.node_type == "iconic" then
                        talent_widget.content.frame_selected_talent = "content/ui/materials/frames/talents/circular_frame_selected"

                        local highlight_style = talent_widget.style.frame_selected_talent
                        if highlight_style then
                            highlight_style.size = {
                                icon_size + 6,
                                icon_size + 6,
                            }
                            highlight_style.offset[3] = -1
                        end
                    end

                    talent_widget.original_offset = {
                        offset_width,
                        offset_height,
                        0,
                    }
                    talent_widget.offset = {
                        offset_width,
                        offset_height,
                        0,
                    }
                    talent_widget.content.talent_preview_data = {
                        talent = entry.talent,
                        node_type = entry.node_type,
                        points_spent = entry.points_spent,
                        is_talent_preview = true,
                    }
                    spawn_slot.talent_preview_widgets[#spawn_slot.talent_preview_widgets + 1] = talent_widget

                    local x1 = offset_width
                    local y1 = offset_height
                    local x2 = offset_width + icon_size
                    local y2 = offset_height + icon_size

                    min_x = min_x and math.min(min_x, x1) or x1
                    max_x = max_x and math.max(max_x, x2) or x2
                    min_y = min_y and math.min(min_y, y1) or y1
                    max_y = max_y and math.max(max_y, y2) or y2
                end
            end

            current_offset_y = current_offset_y - rows * row_height - row_gap
        end
    end

    local use_fancy_background = mod:get("preview_background_character") == true
    local use_black_background = mod:get("preview_background") == true

    if (use_black_background or use_fancy_background) and min_x and max_x and min_y and max_y then
        if use_fancy_background then
            _ensure_preview_packages()
        end
        local padding = math.max(6, math.floor(icon_size * 0.2))
        local width = (max_x - min_x) + padding * 2
        local height = (max_y - min_y) + padding * 2
        local pass_template

        if use_fancy_background then
            pass_template = {
                {
                    pass_type = "texture",
                    style_id = "background",
                    value = "content/ui/materials/backgrounds/terminal_basic",
                    style = {
                        horizontal_alignment = "center",
                        vertical_alignment = "center",
                        scale_to_material = true,
                        color = Color.terminal_grid_background(nil, true),
                        offset = {
                            0,
                            0,
                            0,
                        },
                    },
                },
            }
        else
            pass_template = {
                {
                    pass_type = "rect",
                    style_id = "background",
                    style = {
                        color = {
                            160,
                            0,
                            0,
                            0,
                        },
                    },
                },
            }
        end

        local widget_definition = UIWidget.create_definition(pass_template, scenegraph_id, nil, {width, height}, {})
        local name_bg = string.format("talent_preview_bg_%s", spawn_slot.index)
        local bg_widget = self:_create_widget(name_bg, widget_definition)

        bg_widget.original_offset = {
            min_x - padding,
            min_y - padding,
            -3,
        }
        bg_widget.offset = {
            min_x - padding,
            min_y - padding,
            -3,
        }

        spawn_slot.talent_preview_background = bg_widget
    end
end

local function _update_slot_preview(self, spawn_slot)
    if not spawn_slot then
        return
    end

    if not spawn_slot.occupied or not spawn_slot.player then
        _clear_preview_widgets(self, spawn_slot)
        return
    end

    local profile = spawn_slot.player:profile()
    if not profile then
        _clear_preview_widgets(self, spawn_slot)
        return
    end

    _ensure_talent_icon_packages(profile)

    local entries_by_category, signature = _collect_selected_nodes(profile)

    if signature == spawn_slot.talent_preview_signature then
        return
    end

    _clear_preview_widgets(self, spawn_slot)

    if not entries_by_category or signature == "" then
        return
    end

    _build_preview_widgets(self, spawn_slot, entries_by_category)
    spawn_slot.talent_preview_signature = signature
end

local function _update_all_slots(self)
    local spawn_slots = self._spawn_slots

    if not spawn_slots then
        return
    end

    if mod._pending_clear then
        for i = 1, #spawn_slots do
            _clear_preview_widgets(self, spawn_slots[i])
        end

        mod._pending_clear = false
        return
    end

    if mod._pending_refresh then
        for i = 1, #spawn_slots do
            local slot = spawn_slots[i]
            if slot then
                slot.talent_preview_signature = nil
            end
        end

        mod._pending_refresh = false
    end

    for i = 1, #spawn_slots do
        _update_slot_preview(self, spawn_slots[i])
    end
end

function mod.on_setting_changed(setting_id)
    if setting_id == "enable_in_lobby" then
        if not mod:get("enable_in_lobby") then
            mod._pending_clear = true
        else
            mod._pending_refresh = true
        end
        return
    end

    if setting_id == "icon_size" or setting_id == "icons_per_row" then
        mod._pending_refresh = true
        return
    end

    if setting_id == "preview_offset_y" or setting_id == "preview_offset_x" then
        mod._pending_refresh = true
        return
    end

    if setting_id == "show_keystone"
        or setting_id == "show_stat"
        or setting_id == "show_default"
        or setting_id == "show_modifiers"
        or setting_id == "show_aura"
        or setting_id == "show_blitz"
        or setting_id == "show_ability_modifiers"
        or setting_id == "show_broker_stimm"
        or setting_id == "preview_background"
        or setting_id == "preview_background_character" then
        mod._pending_refresh = true
    end
end

function mod.on_unload(exit_game)
    if not exit_game then
        return
    end

    local package_manager = Managers.package
    if not package_manager or not package_manager.has_loaded_id then
        return
    end

    for _, load_id in pairs(loaded_packages) do
        if load_id and load_id ~= true and package_manager:has_loaded_id(load_id) then
            package_manager:release(load_id)
        end
    end
end

mod:hook_safe("LobbyView", "_setup_spawn_slots", function(self)
    if not mod:get("enable_in_lobby") then
        return
    end

    local spawn_slots = self._spawn_slots
    if not spawn_slots then
        return
    end

    for i = 1, #spawn_slots do
        local slot = spawn_slots[i]
        slot.talent_preview_widgets = slot.talent_preview_widgets or {}
        slot.talent_preview_signature = nil
    end
end)

mod:hook_safe("LobbyView", "_assign_player_to_slot", function(self, player, slot)
    if not mod:get("enable_in_lobby") then
        return
    end

    _update_slot_preview(self, slot)
end)

mod:hook("LobbyView", "_check_loadout_changes", function(func, self)
    func(self)

    if not mod:get("enable_in_lobby") and not mod._pending_clear then
        return
    end

    if not _is_lobby_view_active() then
        return
    end

    _update_all_slots(self)
end)

mod:hook_safe("LobbyView", "_reset_spawn_slot", function(self, slot)
    _clear_preview_widgets(self, slot)
end)

mod:hook_safe("LobbyView", "_destroy_spawn_slots", function(self)
    local spawn_slots = self._spawn_slots

    if not spawn_slots then
        return
    end

    for i = 1, #spawn_slots do
        _clear_preview_widgets(self, spawn_slots[i])
    end
end)

mod:hook("LobbyView", "_draw_widgets", function(func, self, dt, t, input_service, ui_renderer)
    func(self, dt, t, input_service, ui_renderer)

    if not mod:get("enable_in_lobby") then
        return
    end

    if not _is_lobby_view_active() then
        return
    end

    if not self._world_initialized or self._show_weapons then
        return
    end

    local spawn_slots = self._spawn_slots
    local hovered_slot
    local hovered_data

    for i = 1, #spawn_slots do
        local slot = spawn_slots[i]

        if slot.occupied and slot.profile_spawner and slot.profile_spawner:spawned() then
            local widget_offset_x = slot.panel_widget.offset[1] - 30
            local preview_widgets = slot.talent_preview_widgets
            local bg_widget = slot.talent_preview_background

            if bg_widget then
                bg_widget.offset[1] = bg_widget.original_offset[1] + widget_offset_x + 35
                bg_widget.offset[2] = bg_widget.original_offset[2]

                UIWidget.draw(bg_widget, ui_renderer)
            end

            if preview_widgets then
                for j = 1, #preview_widgets do
                    local talent_widget = preview_widgets[j]

                    talent_widget.offset[1] = talent_widget.original_offset[1] + widget_offset_x + 35
                    talent_widget.offset[2] = talent_widget.original_offset[2]

                    UIWidget.draw(talent_widget, ui_renderer)

                    local hotspot = talent_widget.content.hotspot
                    local is_hover = not hovered_slot and hotspot and (hotspot.is_hover or hotspot.is_selected)

                    if is_hover then
                        hovered_slot = slot
                        hovered_data = talent_widget.content.talent_preview_data
                        self._hovered_tooltip_panel_widget = talent_widget
                    end
                end
            end
        end
    end

    local current_hover = self._hovered_slot_talent_data
    local has_base_hover = current_hover and not current_hover.is_talent_preview

    if hovered_data then
        if not has_base_hover and (not current_hover or current_hover ~= hovered_data) then
            self:_on_tooltip_hover_stop()
            self:_on_tooltip_hover_start(hovered_slot, hovered_data)
        end

        if not has_base_hover then
            local tooltip = self._widgets_by_name and self._widgets_by_name.talent_tooltip
            if tooltip then
                tooltip.content.visible = true
                tooltip.alpha_multiplier = 1
                self._tooltip_alpha_multiplier = 1
                self._tooltip_draw_delay = 0
            end
        end
    elseif current_hover and current_hover.is_talent_preview then
        self._hovered_tooltip_panel_widget = nil
        self:_on_tooltip_hover_stop()
    end
end)

mod:hook("LobbyView", "_setup_tooltip_info", function(func, self, talent_hover_data)
    if not talent_hover_data or not talent_hover_data.is_talent_preview then
        return func(self, talent_hover_data)
    end

    local widgets_by_name = self._widgets_by_name
    local widget = widgets_by_name.talent_tooltip
    local content = widget.content
    local style = widget.style

    content.title = "title"
    content.description = "<<UNASSIGNED TALENT NODE>>"

    local talent = talent_hover_data.talent

    if talent then
        local text_vertical_offset = 14
        local node_type = talent_hover_data.node_type
        local node_settings = TalentBuilderViewSettings.settings_by_node_type[node_type] or TalentBuilderViewSettings.settings_by_node_type.default

        content.talent_type_title = node_settings and (Localize(node_settings.display_name) or "") or ""

        local talent_type_title_height = self:_get_text_height(content.talent_type_title, style.talent_type_title, {400, 20})

        style.talent_type_title.offset[2] = text_vertical_offset
        style.talent_type_title.size[2] = talent_type_title_height
        text_vertical_offset = text_vertical_offset + talent_type_title_height

        local points_spent = talent_hover_data.points_spent or 1
        local description = TalentLayoutParser.talent_description(talent, points_spent, Color.ui_terminal(255, true))
        local localized_title = TalentLayoutParser.talent_title(talent, points_spent, Color.ui_terminal(255, true))

        content.title = localized_title
        content.description = description

        local widget_width, _ = self:_scenegraph_size(widget.scenegraph_id, self._ui_scenegraph)
        local text_size_addition = style.title.size_addition
        local dummy_size = {
            widget_width + text_size_addition[1],
            20,
        }

        local title_height = self:_get_text_height(content.title, style.title, dummy_size)

        style.title.offset[2] = text_vertical_offset
        style.title.size[2] = title_height
        text_vertical_offset = text_vertical_offset + title_height + 10

        local description_height = self:_get_text_height(content.description, style.description, dummy_size)

        style.description.offset[2] = text_vertical_offset
        style.description.size[2] = description_height
        text_vertical_offset = text_vertical_offset + description_height + 20
        content.exculsive_group_description = ""

        self:_set_scenegraph_size(widget.scenegraph_id, nil, text_vertical_offset, self._ui_scenegraph)
    end
end)

mod:hook("LobbyView", "_update_talent_tooltip_position", function(func, self)
    local hovered_data = self._hovered_slot_talent_data
    local hovered_widget = self._hovered_tooltip_panel_widget

    if hovered_data and hovered_data.is_talent_preview and hovered_widget then
        local ui_scenegraph = self._ui_scenegraph
        local tooltip_widget = self._widgets_by_name and self._widgets_by_name.talent_tooltip

        if tooltip_widget then
            local parent_scenegraph_id = hovered_widget.scenegraph_id
            local parent_position = self:_scenegraph_world_position(parent_scenegraph_id)
            local widget_offset = hovered_widget.offset
            local tooltip_offset = tooltip_widget.offset
            local tooltip_width, tooltip_height = self:_scenegraph_size(tooltip_widget.scenegraph_id, ui_scenegraph)
            local icon_size = _get_icon_size()

            tooltip_offset[1] = parent_position[1] + widget_offset[1] + icon_size * 0.5 - tooltip_width * 0.5 + _get_preview_offset_x()
            tooltip_offset[2] = parent_position[2] + widget_offset[2] + icon_size + 8
        end

        return
    end

    return func(self)
end)
