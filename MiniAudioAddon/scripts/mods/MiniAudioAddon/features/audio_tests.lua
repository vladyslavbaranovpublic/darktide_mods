--[[
    File: features/audio_tests.lua
    Description: Unified audio testing feature - manual playback, emitters, and spatial tests.
    Reuses EmitterManager and Sphere for all test modes.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local AudioTests = {}

-- Test state (unified for all test types)
local active_tests = {}  -- { [test_id] = { mode, emitter_id, stop_pending, ... } }
local manual_track = nil  -- Simple manual playback (no spatial)

-- Dependencies
local mod = nil
local EmitterManager = nil
local Sphere = nil
local DaemonBridge = nil
local Constants = nil

function AudioTests.init(dependencies)
    mod = dependencies.mod
    EmitterManager = dependencies.EmitterManager
    Sphere = dependencies.Sphere
    DaemonBridge = dependencies.DaemonBridge
    Constants = dependencies.Constants
end

-- ============================================================================
-- MANUAL PLAYBACK (Non-spatial)
-- ============================================================================

function AudioTests.play_manual(path)
    if not path or not DaemonBridge then
        return false
    end

    if manual_track then
        AudioTests.stop_manual(true)
        if manual_track then
            if mod then mod:echo("[AudioTests] Wait for previous manual track to stop.") end
            return false
        end
    end

    local track_id = Constants and Constants.TRACK_IDS and Constants.TRACK_IDS.manual or "__miniaudio_manual"
    local listener = mod and mod.utils and mod.utils.build_listener_payload()
    if not listener then
        return false
    end

    local ok, queued = DaemonBridge.play({
        id = track_id,
        path = path,
        loop = true,
        volume = 1.0,
        listener = listener,
        source = { position = listener.position, forward = listener.forward, velocity = {0,0,0} },
    })

    if ok then
        manual_track = { track_id = track_id, path = path, stop_pending = false }
        if mod then mod:echo("[AudioTests] Manual playback started: %s", path) end
        return true
    end

    return false
end

function AudioTests.stop_manual(silent)
    if not manual_track then
        if not silent and mod then mod:echo("[AudioTests] No manual track active.") end
        return false
    end

    if manual_track.stop_pending then
        if not silent and mod then mod:echo("[AudioTests] Manual stop already pending.") end
        return true
    end

    local ok, queued = DaemonBridge.stop(manual_track.track_id, 0.35)
    if not ok then
        if not silent and mod then mod:echo("[AudioTests] Failed to stop manual track.") end
        return false
    end

    if queued then
        manual_track.stop_pending = true
        if not silent and mod then mod:echo("[AudioTests] Waiting for manual track to stop...") end
    else
        manual_track = nil
        if not silent and mod then mod:echo("[AudioTests] Manual track stopped.") end
    end

    return true
end

function AudioTests.is_manual_active()
    return manual_track ~= nil
end

-- ============================================================================
-- EMITTER TEST (Fixed position with sphere marker)
-- ============================================================================

function AudioTests.create_emitter(test_id, path, distance, absolute_profile)
    if not EmitterManager or not Sphere or not mod then
        return false
    end

    if active_tests[test_id] then
        AudioTests.stop_test(test_id, true)
        if active_tests[test_id] then
            if mod then mod:echo("[AudioTests] Wait for previous %s to stop.", test_id) end
            return false
        end
    end

    local listener_pos, listener_rot = mod.utils and mod.utils.listener_pose()
    if not listener_pos or not listener_rot then
        if mod then mod:echo("[AudioTests] Enter gameplay before running emitter tests.") end
        return false
    end

    local dist = math.max(0.5, math.min(distance or 3, 25))
    local forward = mod.utils.safe_forward(listener_rot)
    local position = listener_pos + forward * dist

    -- Create emitter using EmitterManager
    local profile = absolute_profile and {
        min_distance = math.max(0.35, mod:spatial_distance_scale()),
        max_distance = math.min(200, 30 * mod:spatial_distance_scale()),
    } or {
        min_distance = dist * 0.25 * mod:spatial_distance_scale(),
        max_distance = dist * 5.0 * mod:spatial_distance_scale(),
    }

    local emitter_id = EmitterManager.create({
        id_prefix = test_id,
        path = path,
        position = position,
        rotation = listener_rot,
        profile = profile,
        loop = true,
        volume = 1.0,
    })

    if not emitter_id then
        if mod then mod:echo("[AudioTests] Failed to create emitter.") end
        return false
    end

    -- Add sphere marker if debug enabled
    if mod:debug_markers_enabled() then
        local color = Constants and Constants.MARKER_SETTINGS and Constants.MARKER_SETTINGS.emitter_color or {255, 255, 0}
        local radius = Constants and Constants.MARKER_SETTINGS and Constants.MARKER_SETTINGS.emitter_radius or 0.4
        Sphere.toggle(test_id, true, position, color, radius)
    end

    active_tests[test_id] = {
        mode = "emitter",
        emitter_id = emitter_id,
        stop_pending = false,
        distance = dist,
    }

    if mod then
        mod:echo("[AudioTests] Emitter '%s' spawned %.1fm ahead.", test_id, dist)
    end

    return true
end

-- ============================================================================
-- SPATIAL TEST (Animated emitter with orbit/loop/spin/etc)
-- ============================================================================

function AudioTests.create_spatial(test_id, mode_config)
    if not EmitterManager or not Sphere or not mod then
        return false
    end

    if active_tests[test_id] then
        AudioTests.stop_test(test_id, true)
        if active_tests[test_id] then
            if mod then mod:echo("[AudioTests] Wait for previous %s to stop.", test_id) end
            return false
        end
    end

    local listener_pos, listener_rot = mod.utils and mod.utils.listener_pose()
    if not listener_pos or not listener_rot then
        if mod then mod:echo("[AudioTests] Enter gameplay before running spatial tests.") end
        return false
    end

    -- Create emitter with mode-specific tracker
    local emitter_id = EmitterManager.create({
        id_prefix = test_id,
        path = mode_config.path,
        position = listener_pos,  -- Will be updated by mode
        profile = mode_config.profile or {},
        loop = true,
        volume = 1.0,
        mode = mode_config.mode,  -- orbit, follow, loop, spin, directional
        mode_config = mode_config,  -- radius, period, etc.
    })

    if not emitter_id then
        if mod then mod:echo("[AudioTests] Failed to create spatial emitter.") end
        return false
    end

    -- Add sphere marker if debug enabled
    if mod:debug_markers_enabled() then
        local color = Constants and Constants.MARKER_SETTINGS and Constants.MARKER_SETTINGS.spatial_color or {255, 0, 255}
        local radius = Constants and Constants.MARKER_SETTINGS and Constants.MARKER_SETTINGS.spatial_radius or 0.3
        Sphere.toggle(test_id, true, listener_pos, color, radius)
    end

    active_tests[test_id] = {
        mode = "spatial",
        emitter_id = emitter_id,
        stop_pending = false,
        config = mode_config,
    }

    if mod then
        mod:echo("[AudioTests] Spatial test '%s' mode '%s' started.", test_id, mode_config.mode)
    end

    return true
end

-- ============================================================================
-- UNIFIED STOP
-- ============================================================================

function AudioTests.stop_test(test_id, silent)
    local test = active_tests[test_id]
    if not test then
        if not silent and mod then mod:echo("[AudioTests] Test '%s' not active.", test_id) end
        return false
    end

    if test.stop_pending then
        if not silent and mod then mod:echo("[AudioTests] Stop already pending for '%s'.", test_id) end
        return true
    end

    -- Stop emitter
    if test.emitter_id and EmitterManager then
        local ok = EmitterManager.stop(test.emitter_id, 0.35)
        if not ok then
            if not silent and mod then mod:echo("[AudioTests] Failed to stop '%s'.", test_id) end
            return false
        end
        test.stop_pending = true
    end

    -- Clear sphere marker
    if Sphere then
        Sphere.toggle(test_id, false)
    end

    if not test.emitter_id then
        active_tests[test_id] = nil
        if not silent and mod then mod:echo("[AudioTests] Test '%s' stopped.", test_id) end
    else
        if not silent and mod then mod:echo("[AudioTests] Waiting for '%s' to stop...", test_id) end
    end

    return true
end

function AudioTests.stop_all()
    local stopped_any = false

    if manual_track then
        AudioTests.stop_manual(true)
        stopped_any = true
    end

    for test_id, _ in pairs(active_tests) do
        AudioTests.stop_test(test_id, true)
        stopped_any = true
    end

    if not stopped_any and mod then
        mod:echo("[AudioTests] No tests active.")
    end
end

-- ============================================================================
-- UPDATE (delegates to EmitterManager)
-- ============================================================================

function AudioTests.update(dt)
    if not EmitterManager then
        return
    end

    -- Update all active emitters (EmitterManager handles spatial tests automatically)
    EmitterManager.update(dt)

    -- Update sphere markers for active tests
    if Sphere and mod and mod:debug_markers_enabled() then
        for test_id, test in pairs(active_tests) do
            if test.emitter_id then
                local emitter = EmitterManager.get(test.emitter_id)
                if emitter and emitter.tracker then
                    local pos = emitter.tracker:position()
                    if pos then
                        local color = test.mode == "spatial" 
                            and (Constants and Constants.MARKER_SETTINGS and Constants.MARKER_SETTINGS.spatial_color or {255, 0, 255})
                            or (Constants and Constants.MARKER_SETTINGS and Constants.MARKER_SETTINGS.emitter_color or {255, 255, 0})
                        local radius = test.mode == "spatial" and 0.3 or 0.4
                        Sphere.toggle(test_id, true, pos, color, radius)
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function AudioTests.handle_stop_delivery(info)
    if not info or info.cmd ~= "stop" then
        return false
    end

    -- Check manual track
    if manual_track and info.id == manual_track.track_id then
        manual_track = nil
        return true
    end

    -- Check active tests
    for test_id, test in pairs(active_tests) do
        if test.emitter_id and info.id:find(test.emitter_id, 1, true) then
            active_tests[test_id] = nil
            if Sphere then Sphere.toggle(test_id, false) end
            return true
        end
    end

    return false
end

function AudioTests.handle_play_failure(info)
    if not info or info.cmd ~= "play" then
        return false
    end

    -- Check manual track
    if manual_track and info.id == manual_track.track_id then
        manual_track = nil
        if mod then mod:echo("[AudioTests] Manual track start failed.") end
        return true
    end

    -- Check active tests
    for test_id, test in pairs(active_tests) do
        if test.emitter_id and info.id:find(test.emitter_id, 1, true) then
            active_tests[test_id] = nil
            if Sphere then Sphere.toggle(test_id, false) end
            if mod then mod:echo("[AudioTests] Test '%s' start failed.", test_id) end
            return true
        end
    end

    return false
end

function AudioTests.handle_stop_failure(info)
    if not info or info.cmd ~= "stop" then
        return false
    end

    -- Check manual track
    if manual_track and manual_track.stop_pending and info.id == manual_track.track_id then
        manual_track.stop_pending = false
        return true
    end

    -- Check active tests
    for test_id, test in pairs(active_tests) do
        if test.stop_pending and test.emitter_id and info.id:find(test.emitter_id, 1, true) then
            test.stop_pending = false
            return true
        end
    end

    return false
end

-- ============================================================================
-- CLEAR ON RESET
-- ============================================================================

function AudioTests.clear(reason)
    manual_track = nil
    
    for test_id, _ in pairs(active_tests) do
        if Sphere then Sphere.toggle(test_id, false) end
    end
    
    active_tests = {}

    if mod and mod:get("miniaudioaddon_debug") then
        mod:echo("[AudioTests] All tests cleared (%s).", tostring(reason or "reset"))
    end
end

-- ============================================================================
-- HELPER: Resolve simple test track
-- ============================================================================

function AudioTests.resolve_simple_track(choice)
    if not Constants or not Constants.SIMPLE_TEST then
        return nil
    end
    
    local key = choice and choice:lower()
    local relative = Constants.SIMPLE_TEST.tracks[key] or Constants.SIMPLE_TEST.tracks[Constants.SIMPLE_TEST.default]
    if not relative then
        return nil
    end

    local resolved = mod and mod.api and mod.api.expand_track_path and mod.api.expand_track_path(relative)
    if not resolved and mod then
        mod:echo("[AudioTests] Simple test file missing: %s", relative)
    end
    return resolved
end

return AudioTests
