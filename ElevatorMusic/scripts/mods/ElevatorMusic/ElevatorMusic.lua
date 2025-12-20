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
local Rainbow = nil
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
end
local active_visuals = {}
local controller = nil
local playlist_id           = "ElevatorMusic_playlist"
local TEST_EMITTER_ID       = "__ElevatorMusicTest__"
local test_emitter_manual   = false

local function visuals_enabled()
    return Rainbow and mod:get("elevatormusic_visuals_enable")
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

    local platforms = controller.get_platforms and controller:get_platforms()
    if not platforms or not next(platforms) then
        clear_visuals()
        return
    end

    local base_options = rainbow_options()
    local halo_count = base_options.halo_count or 1
    local seen = {}

    local function halo_id(platform_key, index)
        return string.format("%s#halo_%02d", platform_key, index)
    end

    local function halo_options(id)
        local entry = active_visuals[id]
        if not entry then
            entry = {}
            active_visuals[id] = entry
        end

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

        entry.options = entry.options or {}
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
            else
                for halo_index = 1, halo_count do
                    remove_visual(halo_id(key, halo_index))
                end
            end
        else
            for halo_index = 1, halo_count do
                remove_visual(halo_id(key, halo_index))
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

-- Construct the shared platform controller; ElevatorMusic simply describes which settings
-- control each behaviour (markers, randomness, idle distance, etc.). The heavy lifting
-- happens in MiniAudioAddon/features/platform_controller.lua.
controller = PlatformController.new({
    mod = mod,
    playlist_id = playlist_id,
    identifier = mod:get_name(),
    get_setting = function(key)
        return mod:get(key)
    end,
    markers_setting = "elevatormusic_show_markers",
    random_setting = "elevatormusic_random_order",
    fade_setting = "elevatormusic_fade_seconds",
    activation_linger_setting = "elevatormusic_activation_linger",
    idle_full_setting = "elevatormusic_idle_full_distance",
    idle_radius_setting = "elevatormusic_idle_distance",
    idle_after_activation_setting = "elevatormusic_idle_after_activation",
    idle_enabled_setting = "elevatormusic_idle_enabled",
    play_activation_setting = "elevatormusic_play_activation",
    debug_setting = "elevatormusic_debug",
})

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

mod.update = function(dt)
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
    render_debug_spheres()
    update_platform_visuals(dt)
end

-- Trigger a rescan whenever the mod is enabled (handles audio file changes while disabled).
mod.on_enabled = function()
    if MiniAudio and MiniAudio.ensure_daemon_keepalive then
        MiniAudio:ensure_daemon_keepalive()
    end
    PlaylistManager.force_scan(playlist_id)
end

-- Stop emitters whenever ElevatorMusic is disabled (via DMF settings or mod setting).
mod.on_disabled = function()
    controller:stop_all("mod_disabled")
    test_emitter_manual = false
    stop_test_emitter()
    clear_visuals()
end

-- Ensure emitters are dropped on hot unloads/reloads to avoid lingering sounds.
mod.on_unload = function()
    controller:stop_all("unload")
    test_emitter_manual = false
    stop_test_emitter()
    clear_visuals()
end

-- Re-scan when the master toggle changes so new tracks are picked up immediately.
mod.on_setting_changed = function(setting_id)
    if setting_id == "elevatormusic_enable" then
        PlaylistManager.force_scan(playlist_id)
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
        or setting_id == "elevatormusic_visuals_orbit_speed" then
        clear_visuals()
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
