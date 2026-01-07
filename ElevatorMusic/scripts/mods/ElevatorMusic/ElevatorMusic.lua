--[[
    ElevatorMusic - Slim coordinator that delegates playlist scanning, listener handling,
    and emitter lifecycle management to MiniAudioAddon shared modules.

    Responsibilities in this file:
    1. Validate MiniAudioAddon dependencies and register ElevatorMusic's playlist.
    2. Configure the shared PlatformController with Elevator-only settings and hooks.
    3. Forward platform lifecycle events to MiniAudioAddon so emitters can be spawned/stopped.
    4. Keep the playlist refreshed when the mod is toggled or on demand via a console command.
]]

local mod = get_mod("ElevatorMusic")
local MiniAudio = get_mod("MiniAudioAddon")
if not MiniAudio or not MiniAudio.playlist_manager or not MiniAudio.platform_controller then
    mod:error("[ElevatorMusic] MiniAudioAddon 1.0.3+ with playlist/platform modules is required.")
    return
end

if MiniAudio.ensure_daemon_keepalive then
    MiniAudio:ensure_daemon_keepalive()
end

local PlaylistManager       = MiniAudio.playlist_manager
local PlatformController    = MiniAudio.platform_controller
local EmitterManager        = MiniAudio.emitter_manager
local Listener              = MiniAudio.listener
local Constants             = MiniAudio.constants
local IOUtils               = MiniAudio.IOUtils
local Vector3               = rawget(_G, "Vector3")
local Unit                  = rawget(_G, "Unit")
local World                 = rawget(_G, "World")
local Level                 = rawget(_G, "Level")
local Rainbow = nil
local CinematicSceneSettings = nil
local CINEMATIC_NONE = nil
do
    local ok, module_or_error = pcall(function()
        return mod:io_dofile("ElevatorMusic/scripts/mods/ElevatorMusic/visuals/rainbow")
    end)
    if ok then
        Rainbow = module_or_error
    else
        mod:echo("[ElevatorMusic] Failed to load visuals module: %s", module_or_error)
        Rainbow = nil
    end
    local success, settings = pcall(function()
        return require("scripts/settings/cinematic_scene/cinematic_scene_settings")
    end)
    if success then
        CinematicSceneSettings = settings
        if CinematicSceneSettings and CinematicSceneSettings.CINEMATIC_NAMES then
            CINEMATIC_NONE = CinematicSceneSettings.CINEMATIC_NAMES.none
        end
    end
end
local active_visuals = {}
local controller = nil
local gunship_controller = nil
local PLATFORM_PROCESS_ID = string.format("%s_platform", mod:get_name())
local playlist_id           = "ElevatorMusic_playlist"
local TEST_EMITTER_ID       = "__ElevatorMusicTest__"
local test_emitter_manual   = false
local pending_state_enter_cleanup = false
local gunships = {
    entries = {},
    rescan_in = 0,
    scan_interval = 1.5,
    active = false,
    cinematic = false,
}

local function stop_all_gunship_audio(reason)
    if gunship_controller and gunship_controller.stop_all then
        gunship_controller:stop_all(reason or "gunship_reset")
        if gunship_controller.set_emitters_suppressed then
            gunship_controller:set_emitters_suppressed(false)
        end
    end
    if EmitterManager and EmitterManager.stop_by_prefix then
        EmitterManager.stop_by_prefix(string.format("%s_valk_", mod:get_name()), 0)
    end
    gunships.entries = {}
    gunships.rescan_in = 0
    gunships.active = false
    gunships.cinematic = false
end

local function stop_all_elevator_audio(reason)
    if EmitterManager and EmitterManager.stop_by_prefix then
        EmitterManager.stop_by_prefix(mod:get_name() .. "_", 0)
    end
    if MiniAudio and MiniAudio.api and MiniAudio.api.stop_process then
        pcall(MiniAudio.api.stop_process, PLATFORM_PROCESS_ID, { reason = reason or "reset", fade = 0 })
    end
    stop_all_gunship_audio(reason)
end

local function gunship_enabled()
    return mod:get("elevatormusic_enable") and mod:get("elevatormusic_valk_enable")
end

local function gunship_cinematic_active()
    local cinematic_system = Managers and Managers.state and Managers.state.cinematic_scene
    if not cinematic_system then
        return false
    end
    local is_active = false
    if cinematic_system.is_active then
        local ok, active = pcall(function()
            return cinematic_system:is_active()
        end)
        is_active = ok and active or false
    end
    if not is_active then
        return false
    end
    if cinematic_system.current_cinematic_name then
        local ok, current = pcall(function()
            return cinematic_system:current_cinematic_name()
        end)
        if ok and current then
            if CINEMATIC_NONE and current == CINEMATIC_NONE then
                return false
            end
            return true
        end
    end
    return true
end

local function unit_key(unit)
    if not unit then
        return nil
    end
    local key = Unit and Unit.id_string and Unit.id_string(unit) or nil
    if not key or key == "" or key == "0000000000000000" then
        key = tostring(unit)
    end
    return key
end

local function resolve_gunship_body_unit(unit)
    if not Unit or not unit then
        return unit
    end
    if Unit.alive and not Unit.alive(unit) then
        return nil
    end
    if Unit.get_data then
        local ok, body = pcall(Unit.get_data, unit, "body_index", 1)
        if ok and body and Unit.alive(body) then
            return body
        end
    end
    return unit
end

local function fetch_valkyrie_units()
    local extension_manager = Managers and Managers.state and Managers.state.extension
    if not extension_manager or not extension_manager.system then
        return {}
    end
    local ok_system, component_system = pcall(extension_manager.system, extension_manager, "component_system")
    if not ok_system or not component_system or not component_system.get_units_from_component_name then
        return {}
    end
    local ok_units, collection = pcall(component_system.get_units_from_component_name, component_system, "ValkyrieCustomization")
    if not ok_units or not collection then
        return {}
    end

    local units = {}
    if type(collection) == "table" then
        if #collection > 0 then
            for _, unit in ipairs(collection) do
                units[#units + 1] = unit
            end
        else
            for key, value in pairs(collection) do
                if Unit and Unit.alive and Unit.alive(key) then
                    units[#units + 1] = key
                elseif Unit and Unit.alive and Unit.alive(value) then
                    units[#units + 1] = value
                end
            end
        end
    end

    return units
end

local function refresh_gunship_entries()
    if not gunship_controller or not gunship_enabled() then
        return
    end

    local units = fetch_valkyrie_units()
    local seen = {}

    for _, unit in ipairs(units) do
        if Unit and Unit.alive and Unit.alive(unit) then
            local key = unit_key(unit)
            if key then
                seen[key] = true
                local stub = gunships.entries[key]
                local body_unit = resolve_gunship_body_unit(unit)
                if body_unit then
                    if not stub then
                        stub = {}
                        gunships.entries[key] = stub
                    end
                    stub.anchor_unit = unit
                    stub._unit = body_unit
                    stub._anchor_key = key
                    stub._body_key = unit_key(body_unit)
                    stub._elevator_override_key = string.format("valk_%s", key)
                    if Unit.alive(body_unit) then
                        gunship_controller:on_platform_update(stub)
                    end
                end
            end
        end
    end

    for key, stub in pairs(gunships.entries) do
        if not seen[key] then
            if stub._unit then
                gunship_controller:drop_platform(stub._unit)
            end
            gunships.entries[key] = nil
        end
    end
end

local function update_gunships(dt, listener_pos)
    if not gunship_controller then
        return
    end

    if not gunship_enabled() then
        if gunships.active then
            stop_all_gunship_audio("gunship_disabled")
        end
        return
    end

    local cinematic_active = gunship_cinematic_active()
    gunships.cinematic = cinematic_active
    if gunship_controller.set_emitters_suppressed then
        gunship_controller:set_emitters_suppressed(cinematic_active)
    end

    gunships.active = true
    if not cinematic_active then
        gunships.rescan_in = (gunships.rescan_in or 0) - (dt or 0)
        if gunships.rescan_in <= 0 then
            gunships.rescan_in = gunships.scan_interval
            refresh_gunship_entries()
        else
            for _, stub in pairs(gunships.entries) do
                if not stub._unit or (Unit and Unit.alive and not Unit.alive(stub._unit)) then
                    local body = resolve_gunship_body_unit(stub.anchor_unit)
                    stub._unit = body
                end
                if stub._unit then
                    gunship_controller:on_platform_update(stub)
                end
            end
        end
    end

    gunship_controller:update(listener_pos)
end

local function visuals_enabled()
    return Rainbow and mod:get("elevatormusic_visuals_enable")
end

local function random_between(min_value, max_value)
    if not max_value or max_value <= min_value then
        return min_value
    end
    return min_value + math.random() * (max_value - min_value)
end

local function rainbow_options()
    local radius_min = mod:get("elevatormusic_visuals_radius_min")
    local radius_max = mod:get("elevatormusic_visuals_radius_max")
    local legacy_radius = mod:get("elevatormusic_visuals_radius") or 0.55
    radius_min = radius_min or legacy_radius
    radius_max = radius_max or legacy_radius
    if radius_max < radius_min then
        radius_min, radius_max = radius_max, radius_min
    end
    local scatter_enabled = mod:get("elevatormusic_visuals_scatter_enable")
    local scatter_size_min = mod:get("elevatormusic_visuals_scatter_size_min") or 0.08
    local scatter_size_max = mod:get("elevatormusic_visuals_scatter_size_max") or scatter_size_min
    if scatter_size_max < scatter_size_min then
        scatter_size_min, scatter_size_max = scatter_size_max, scatter_size_min
    end
    return {
        speed = mod:get("elevatormusic_visuals_speed") or 1,
        jitter = mod:get("elevatormusic_visuals_randomness") or 0,
        halo_count = math.max(1, math.floor(mod:get("elevatormusic_visuals_halo_count") or 1)),
        radius_min = radius_min,
        radius_max = radius_max,
        light_count = math.max(2, math.floor(mod:get("elevatormusic_visuals_light_count") or 16)),
        light_orbit_variance = math.max(0, mod:get("elevatormusic_visuals_light_orbit_variance") or 0),
        light_vertical_variance = math.max(0, mod:get("elevatormusic_visuals_light_vertical_variance") or 0),
        loop_speed = math.max(0, mod:get("elevatormusic_visuals_loop_speed") or 0),
        spin_randomness = math.max(0, mod:get("elevatormusic_visuals_spin_randomness") or 0),
        base_spin_speed = 1.5,
        height = 2.0,
        show_core = mod:get("elevatormusic_visuals_show_core") ~= false,
        orbit_radius = math.max(0, mod:get("elevatormusic_visuals_orbit_radius") or 0),
        orbit_speed = mod:get("elevatormusic_visuals_orbit_speed") or 0,
        scatter = {
            enabled = scatter_enabled,
            count = math.max(0, math.floor(mod:get("elevatormusic_visuals_scatter_count") or 0)),
            distance = math.max(0, mod:get("elevatormusic_visuals_scatter_distance") or 0),
            size_min = scatter_size_min,
            size_max = scatter_size_max,
            speed = math.max(0, mod:get("elevatormusic_visuals_scatter_speed") or 0),
            hover = math.max(0, mod:get("elevatormusic_visuals_scatter_hover") or 0),
            sway = math.max(0, mod:get("elevatormusic_visuals_scatter_sway") or 0),
            vertical_offset = mod:get("elevatormusic_visuals_scatter_vertical_offset") or -0.5,
        },
    }
end

local function remove_visual(id)
    if Rainbow and active_visuals[id] then
        Rainbow.remove(id)
        active_visuals[id] = nil
    end
end

local function clear_visuals()
    if Rainbow then
        Rainbow.remove_all()
    end
    active_visuals = {}
end

local function entry_position(entry)
    if not entry then
        return nil
    end

    if entry.emitter and EmitterManager and EmitterManager.get_position then
        local pos = EmitterManager.get_position(entry.emitter.id)
        if pos then
            return pos
        end
    end

    if entry.marker_position_box and entry.marker_position_box.unbox then
        local ok, stored = pcall(function()
            return entry.marker_position_box:unbox()
        end)
        if ok and stored then
            return stored
        end
    end

    if entry.marker_position then
        return entry.marker_position
    end

    if entry.unit and Unit and Unit.alive and Unit.alive(entry.unit) then
        local ok, pos = pcall(Unit.world_position, entry.unit, 1)
        if ok and pos then
            if Vector3 then
                local offset = controller and controller.height_offset or 3.0
                return pos + Vector3(0, 0, offset)
            end
            return pos
        end
    end

    return nil
end

local function update_platform_visuals(dt)
    if not Rainbow then
        return
    end

    if not visuals_enabled() then
        clear_visuals()
        return
    end

    local platforms = {}
    if controller and controller.get_platforms then
        for key, entry in pairs(controller:get_platforms()) do
            platforms[key] = entry
        end
    end
    if gunship_controller and gunship_enabled() and gunship_controller.get_platforms then
        for key, entry in pairs(gunship_controller:get_platforms()) do
            platforms[string.format("valk_%s", key)] = entry
        end
    end

    if not next(platforms) then
        clear_visuals()
        return
    end

    local base_options = rainbow_options()
    local halo_count = base_options.halo_count or 1
    local scatter_config = base_options.scatter or {}
    local seen = {}

    local function halo_id(platform_key, index)
        return string.format("%s#halo_%02d", platform_key, index)
    end

    local function scatter_id(platform_key, index)
        return string.format("%s#scatter_%02d", platform_key, index)
    end

    local function get_visual_entry(id)
        local entry = active_visuals[id]
        if not entry then
            entry = {}
            active_visuals[id] = entry
        end
        entry.options = entry.options or {}
        return entry
    end

    local function halo_options(id)
        local entry = get_visual_entry(id)

        if not entry.radius then
            local min_r = base_options.radius_min or 0.5
            local max_r = base_options.radius_max or min_r
            local span = math.max(0, max_r - min_r)
            entry.radius = min_r + span * math.random()
        end

        if not entry.spin_speed then
            local jitter = base_options.spin_randomness or 0
            local delta = (math.random() * 2 - 1) * jitter
            entry.spin_speed = math.max(0, (base_options.base_spin_speed or 1.5) + delta)
        end

        local opts = entry.options
        opts.speed = base_options.speed
        opts.jitter = base_options.jitter
        opts.radius = entry.radius
        opts.light_count = base_options.light_count
        opts.spin_speed = entry.spin_speed
        opts.height = base_options.height
        opts.show_core = base_options.show_core
        opts.orbit_radius = base_options.orbit_radius
        opts.orbit_speed = base_options.orbit_speed
        opts.light_orbit_variance = base_options.light_orbit_variance
        opts.light_vertical_variance = base_options.light_vertical_variance
        opts.loop_speed = base_options.loop_speed
        return opts
    end

    local function scatter_options(id)
        local entry = get_visual_entry(id)
        local opts = entry.options
        if not entry.radius then
            entry.radius = random_between(scatter_config.size_min or 0.05, scatter_config.size_max or (scatter_config.size_min or 0.05))
        end
        opts.speed = base_options.speed
        opts.jitter = base_options.jitter
        opts.radius = entry.radius
        opts.light_count = 0
        opts.show_core = true
        opts.scatter = true
        opts.scatter_count = 1
        opts.scatter_distance = scatter_config.distance or 0
        opts.scatter_size_min = scatter_config.size_min or 0.05
        opts.scatter_size_max = scatter_config.size_max or opts.scatter_size_min
        opts.scatter_speed = scatter_config.speed or 0
        opts.scatter_hover = scatter_config.hover or 0
        opts.scatter_sway = scatter_config.sway or 0
        opts.scatter_vertical_offset = scatter_config.vertical_offset or 0
        return opts
    end

    for key, entry in pairs(platforms) do
        if entry.emitter then
            local pos = entry_position(entry)
            if pos then
                for halo_index = 1, halo_count do
                    local id = halo_id(key, halo_index)
                    local opts = halo_options(id)
                    Rainbow.spawn(id, opts)
                    Rainbow.configure(id, opts)
                    Rainbow.set_position(id, pos)
                    seen[id] = true
                end
                if scatter_config.enabled and scatter_config.count and scatter_config.count > 0 then
                    for scatter_index = 1, scatter_config.count do
                        local id = scatter_id(key, scatter_index)
                        local opts = scatter_options(id)
                        Rainbow.spawn(id, opts)
                        Rainbow.configure(id, opts)
                        Rainbow.set_position(id, pos)
                        seen[id] = true
                    end
                    -- remove unused scatter entries above current count
                    local cleanup_index = scatter_config.count + 1
                    while true do
                        local id = scatter_id(key, cleanup_index)
                        if not active_visuals[id] then
                            break
                        end
                        remove_visual(id)
                        cleanup_index = cleanup_index + 1
                    end
                else
                    local idx = 1
                    while true do
                        local id = scatter_id(key, idx)
                        if not active_visuals[id] then
                            break
                        end
                        remove_visual(id)
                        idx = idx + 1
                    end
                end
            else
                for halo_index = 1, halo_count do
                    remove_visual(halo_id(key, halo_index))
                end
                local idx = 1
                while true do
                    local id = scatter_id(key, idx)
                    if not active_visuals[id] then
                        break
                    end
                    remove_visual(id)
                    idx = idx + 1
                end
            end
        else
            for halo_index = 1, halo_count do
                remove_visual(halo_id(key, halo_index))
            end
            local idx = 1
            while true do
                local id = scatter_id(key, idx)
                if not active_visuals[id] then
                    break
                end
                remove_visual(id)
                idx = idx + 1
            end
        end
    end

    for id in pairs(active_visuals) do
        if not seen[id] then
            remove_visual(id)
        end
    end

    if Rainbow.update then
        Rainbow.update(dt or 0)
    end
end

-- Register ElevatorMusic's playlist so MiniAudioAddon can scan supported files
-- and expose them through playlist_manager.select_next() calls.
PlaylistManager.register(playlist_id, {
    mod = mod,
    resolve_folder = function()
        if IOUtils and IOUtils.resolve_mod_audio_folder then
            local folder = IOUtils.resolve_mod_audio_folder(mod, "audio")
            if folder then
                return folder
            end
        end
        return string.format("mods/%s/audio", mod:get_name())
    end,
    allowed_extensions = Constants and Constants.AUDIO_EXTENSIONS or nil,
    unsupported_extensions = Constants and Constants.UNSUPPORTED_AUDIO_EXTENSIONS or nil,
    fallback_filenames = Constants and Constants.DEFAULT_AUDIO_FALLBACKS or nil,
    log_prefix = "[ElevatorMusic]",
})

local function controller_setting(key)
    if not key then
        return nil
    end
    return mod:get(key)
end

local function gunship_setting(key)
    if key == "elevatormusic_enable" then
        return gunship_enabled()
    end
    if not key then
        return nil
    end
    return mod:get(key)
end

-- Construct the shared platform controller; ElevatorMusic simply describes which settings
-- control each behaviour (markers, randomness, idle distance, etc.). The heavy lifting
-- happens in MiniAudioAddon/features/platform_controller.lua.
controller = PlatformController.new({
    mod = mod,
    playlist_id = playlist_id,
    identifier = mod:get_name(),
    get_setting = controller_setting,
    markers_setting = "elevatormusic_show_markers",
    random_setting = "elevatormusic_random_order",
    fade_setting = "elevatormusic_fade_seconds",
    activation_linger_setting = "elevatormusic_activation_linger",
    idle_full_setting = "elevatormusic_idle_full_distance",
    idle_radius_setting = "elevatormusic_idle_distance",
    idle_after_activation_setting = "elevatormusic_idle_after_activation",
    activation_only_setting = "elevatormusic_activation_only",
    reshuffle_setting = "elevatormusic_shuffle_on_end",
    debug_setting = "elevatormusic_debug",
})

gunship_controller = PlatformController.new({
    mod = mod,
    playlist_id = playlist_id,
    identifier = string.format("%s_valk", mod:get_name()),
    get_setting = gunship_setting,
    markers_setting = "elevatormusic_show_markers",
    random_setting = "elevatormusic_random_order",
    fade_setting = "elevatormusic_fade_seconds",
    activation_linger_setting = "elevatormusic_activation_linger",
    idle_full_setting = "elevatormusic_valk_idle_full_distance",
    idle_radius_setting = "elevatormusic_valk_idle_distance",
    idle_after_activation_setting = "elevatormusic_idle_after_activation",
    activation_only_setting = "elevatormusic_activation_only",
    reshuffle_setting = "elevatormusic_shuffle_on_end",
    debug_setting = "elevatormusic_debug",
    height_offset = 5.0,
})

-- Stop any leftover daemon tracks or emitters from previous reloads.
stop_all_elevator_audio("boot")

--[[
    Acquire the latest listener position. ElevatorMusic prefers the high-level listener
    module, but falls back to the API entry point to handle early boot when listener
    injection hasn't occurred yet.
]]
local function current_listener_position()
    if Listener and Listener.get_pose then
        local pos = Listener.get_pose()
        if pos then
            return pos
        end
    end

    if MiniAudio.api and MiniAudio.api.listener_pose then
        local ok, pos = pcall(MiniAudio.api.listener_pose)
        if ok and pos then
            return pos
        end
    end

    return nil
end

-- Forward platform updates so the shared controller can run its emitter state machine.
mod:hook_safe("MoveablePlatformExtension", "update", function(self)
    controller:on_platform_update(self)
end)

-- Remove tracked platforms when the extension is destroyed.
mod:hook_safe("MoveablePlatformExtension", "destroy", function(self)
    controller:drop_platform(self._unit)
end)

-- Helper to keep direction hooks DRY.
local function handle_direction(self, direction)
    controller:on_direction_event(self, direction)
end

mod:hook_safe("MoveablePlatformExtension", "_set_direction", handle_direction)
mod:hook_safe("MoveablePlatformExtension", "set_direction_husk", handle_direction)

-- ========================== MOD UPDATE ==========================
--[[
    Mod update:
    1. Advance the shared emitter manager (so fades/markers progress consistently).
    2. Stop all emitters if the feature is disabled.
    3. Provide the listener position to the controller so it can compute idle/activation logic.
]]
local function pick_test_track()
    if PlaylistManager and PlaylistManager.next then
        local candidate = PlaylistManager.next(playlist_id, { random = true, force_scan = true })
        if type(candidate) == "string" and candidate ~= "" then
            return candidate
        end
    end

    if IOUtils and IOUtils.expand_track_path then
        local fallback = IOUtils.expand_track_path("ElevatorMusic/audio/test_audio.mp3")
            or IOUtils.expand_track_path("OrbEmitTest/audio/test_audio.mp3")
        if fallback then
            return fallback
        end
    end

    return nil
end

local function render_debug_spheres()
    if MiniAudio and MiniAudio.sphere and MiniAudio.sphere.render_all then
        MiniAudio.sphere.render_all()
    end
end

local function stop_test_emitter()
    if MiniAudio and MiniAudio.emitter_manager and MiniAudio.emitter_manager.exists then
        if MiniAudio.emitter_manager.exists(TEST_EMITTER_ID) and MiniAudio.emitter_manager.stop then
            MiniAudio.emitter_manager.stop(TEST_EMITTER_ID)
        end
    end
    if MiniAudio and MiniAudio.sphere and MiniAudio.sphere.toggle then
        MiniAudio.sphere.toggle(TEST_EMITTER_ID, false)
    end
end

local function reset_controller(reason)
    if controller and controller.reset then
        controller:reset(reason)
    elseif controller then
        controller:stop_all(reason, true)
    end
    if gunship_controller and gunship_controller.reset then
        gunship_controller:reset(reason)
    elseif gunship_controller then
        gunship_controller:stop_all(reason, true)
    end
    gunships.entries = {}
    gunships.rescan_in = 0
end

local function perform_state_enter_cleanup()
    pending_state_enter_cleanup = false
    reset_controller("state_enter")
    stop_all_elevator_audio("state_enter")
    stop_test_emitter()
    clear_visuals()
end

local function update_test_emitter()
    if not MiniAudio or not MiniAudio.emitter_manager then
        return
    end

    local manager = MiniAudio.emitter_manager
    local wants_test = (mod:get("elevatormusic_debug") and mod:get("elevatormusic_test_emitter")) or test_emitter_manual

    if wants_test then
        if manager.exists and manager.create and not manager.exists(TEST_EMITTER_ID) then
            local test_path = pick_test_track()

            if test_path then
                manager.create({
                    id = TEST_EMITTER_ID,
                    audio_path = test_path,
                    offset_forward = 0,
                    offset_right = 0,
                    offset_up = 0,
                    profile = MiniAudio.audio_profiles and MiniAudio.audio_profiles.MEDIUM_RANGE,
                    sphere_setting_key = nil,
                })
            else
                mod:echo("[ElevatorMusic] Test emitter could not find a playlist track; add audio files under mods/%s/audio.", mod:get_name())
            end
        end

        if manager.get_position and MiniAudio.sphere and MiniAudio.sphere.toggle then
            local pos = manager.get_position(TEST_EMITTER_ID)
            if pos then
                MiniAudio.sphere.toggle(TEST_EMITTER_ID, true, pos, {255, 120, 80}, 0.7)
            end
        end
    else
        stop_test_emitter()
    end
end

local function player_unit_position()
    if not Managers or not Managers.player then
        return nil
    end
    local player_manager = Managers.player
    local player = nil
    if player_manager.local_player_safe then
        player = player_manager:local_player_safe(1)
    end
    player = player or player_manager:local_player(1)
    if not player then
        return nil
    end
    local unit = player.player_unit
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return nil
    end
    local ok, pos = pcall(Unit.world_position, unit, 1)
    if ok then
        return pos
    end
    return nil
end

mod.update = function(dt)
    if pending_state_enter_cleanup then
        perform_state_enter_cleanup()
    end
    update_test_emitter()
    if EmitterManager and EmitterManager.update then
        EmitterManager.update(dt)
    end

    if not mod:get("elevatormusic_enable") then
        controller:stop_all("disabled")
        render_debug_spheres()
        clear_visuals()
        return
    end

    local listener_pos = current_listener_position()
    controller:update(listener_pos)
    update_gunships(dt, listener_pos)
    render_debug_spheres()
    update_platform_visuals(dt)
end

-- Trigger a rescan whenever the mod is enabled (handles audio file changes while disabled).
mod.on_enabled = function()
    if MiniAudio and MiniAudio.ensure_daemon_keepalive then
        MiniAudio:ensure_daemon_keepalive()
    end
    stop_all_elevator_audio("enabled")
    PlaylistManager.force_scan(playlist_id)
end

-- Stop emitters whenever ElevatorMusic is disabled (via DMF settings or mod setting).
mod.on_disabled = function()
    controller:stop_all("mod_disabled")
    if gunship_controller then
        gunship_controller:stop_all("mod_disabled")
    end
    stop_all_elevator_audio("disabled")
    test_emitter_manual = false
    stop_test_emitter()
    clear_visuals()
end

-- Ensure emitters are dropped on hot unloads/reloads to avoid lingering sounds.
mod.on_unload = function()
    controller:stop_all("unload")
    if gunship_controller then
        gunship_controller:stop_all("unload")
    end
    stop_all_elevator_audio("unload")
    test_emitter_manual = false
    stop_test_emitter()
    clear_visuals()
end

-- Clear any lingering audio when entering gameplay (mission loads/reset)
function mod.on_game_state_changed(status, state_name)
    if state_name ~= "StateGameplay" then
        return
    end

    if status == "exit" then
        reset_controller("state_exit")
        stop_all_elevator_audio("state_exit")
        stop_test_emitter()
        clear_visuals()
        pending_state_enter_cleanup = true
    elseif status == "enter" then
        pending_state_enter_cleanup = true
    end
end

-- Re-scan when the master toggle changes so new tracks are picked up immediately.
mod.on_setting_changed = function(setting_id)
    if setting_id == "elevatormusic_enable" then
        PlaylistManager.force_scan(playlist_id)
    elseif setting_id == "elevatormusic_valk_enable" then
        if not gunship_enabled() then
            stop_all_gunship_audio("gunship_toggle")
        else
            gunships.rescan_in = 0
        end
    elseif setting_id == "elevatormusic_visuals_enable"
        or setting_id == "elevatormusic_visuals_speed"
        or setting_id == "elevatormusic_visuals_randomness"
        or setting_id == "elevatormusic_visuals_radius"
        or setting_id == "elevatormusic_visuals_halo_count"
        or setting_id == "elevatormusic_visuals_radius_min"
        or setting_id == "elevatormusic_visuals_radius_max"
        or setting_id == "elevatormusic_visuals_light_count"
        or setting_id == "elevatormusic_visuals_light_orbit_variance"
        or setting_id == "elevatormusic_visuals_light_vertical_variance"
        or setting_id == "elevatormusic_visuals_loop_speed"
        or setting_id == "elevatormusic_visuals_spin_randomness"
        or setting_id == "elevatormusic_visuals_show_core"
        or setting_id == "elevatormusic_visuals_orbit_radius"
        or setting_id == "elevatormusic_visuals_orbit_speed"
        or setting_id == "elevatormusic_visuals_scatter_enable"
        or setting_id == "elevatormusic_visuals_scatter_count"
        or setting_id == "elevatormusic_visuals_scatter_distance"
        or setting_id == "elevatormusic_visuals_scatter_size_min"
        or setting_id == "elevatormusic_visuals_scatter_size_max"
        or setting_id == "elevatormusic_visuals_scatter_speed"
        or setting_id == "elevatormusic_visuals_scatter_hover"
        or setting_id == "elevatormusic_visuals_scatter_sway"
        or setting_id == "elevatormusic_visuals_scatter_vertical_offset" then
        clear_visuals()
    elseif setting_id == "elevatormusic_shuffle_on_end" then
        controller:stop_all("reshuffle_toggle")
    elseif setting_id == "elevatormusic_activation_only" then
        controller:stop_all("activation_toggle", true)
        if EmitterManager and EmitterManager.stop_by_prefix then
            EmitterManager.stop_by_prefix(mod:get_name() .. "_", 0)
        end
        if not mod:get("elevatormusic_activation_only") then
            controller:refresh_idle(current_listener_position())
        end
    end
end

mod:command("elevatormusic_test", "Toggle a one-off debug emitter that plays a random ElevatorMusic track.", function()
    test_emitter_manual = not test_emitter_manual

    if not test_emitter_manual then
        stop_test_emitter()
    end

    mod:echo("[ElevatorMusic] Debug test emitter %s.", test_emitter_manual and "enabled" or "disabled")
end)

-- Console command for forcing an immediate rescan after changing files on disk.
mod:command("elevatormusic_refresh", "Rescan mods/ElevatorMusic/audio for new files.", function()
    local ok, err = PlaylistManager.force_scan(playlist_id)
    if ok then
        local count, message = PlaylistManager.describe(playlist_id)
        if message then
            mod:echo("[ElevatorMusic] %s", message)
        end
        mod:echo("[ElevatorMusic] Playlist refresh complete; %d track(s) available.", count or 0)
    else
        mod:echo("[ElevatorMusic] Failed to rescan playlist: %s", err or "unknown error")
    end
end)
