--[[
    EmitterManager - High-level API for managing spatial audio emitters
    
    Simplifies the create/update/stop workflow to just config tables.
    Handles all the boilerplate: tracker creation, movement patterns, listener updates, cleanup.
    
    Usage:
        local EmitterManager = require("scripts/mods/MiniAudioAddon/core/emitter_manager")
        
        -- Create emitter
        local emitter_id = EmitterManager.create({
            id = "my_orb",
            audio_path = "path/to/audio.mp3",
            offset_forward = 5,
            offset_right = 0,
            offset_up = 0,
            profile = AudioProfiles.MEDIUM_RANGE,
            has_movement = true,
            movement_pattern = "oscillate",  -- or nil for static
            oscillate_direction = "right",
            oscillate_amplitude = 7.5,
            oscillate_frequency = 0.5,
        })
        
        -- Update all emitters (call every frame)
        EmitterManager.update(dt)
        
        -- Stop specific emitter
        EmitterManager.stop("my_orb")
        
        -- Stop all emitters
        EmitterManager.stop_all()
]]

local mod = get_mod("MiniAudioAddon")
local EmitterManager = {}

-- Runtime emitter storage (per-session)
local emitters = {}

-- Persisted track ids survive DMF reloads so we can stop leftovers later
local persistent_state = mod and mod:persistent_table("emitter_manager_state") or {}
persistent_state.active_tracks = persistent_state.active_tracks or {}
local persisted_tracks = persistent_state.active_tracks

local function remember_track(emitter_id, track_id)
    if emitter_id and track_id then
        persisted_tracks[emitter_id] = track_id
    end
end

local function forget_track(emitter_id)
    if emitter_id then
        persisted_tracks[emitter_id] = nil
    end
end

local function finalize_stop(emitter_id, reason)
    local emitter = emitters[emitter_id]
    if not emitter then
        forget_track(emitter_id)
        return false
    end
    emitters[emitter_id] = nil
    forget_track(emitter_id)
    if emitter.config and emitter.config.on_finished then
        pcall(emitter.config.on_finished, emitter, reason or "manual")
    end
    return true
end

-- Required modules (will be injected via init)
local Utils = nil
local PoseTracker = nil
local DaemonBridge = nil
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")

local function cleanup_persisted_tracks()
    if not DaemonBridge or not DaemonBridge.stop_spatial_emitter then
        return
    end
    for emitter_id, track_id in pairs(persisted_tracks) do
        if track_id then
            DaemonBridge.stop_spatial_emitter({
                id = track_id,
                fade = 0,
            })
        end
        persisted_tracks[emitter_id] = nil
    end
end

--[[
    Initialize the EmitterManager with required dependencies
    
    Args:
        utils: MiniAudioUtils module
        pose_tracker: PoseTracker module
        daemon_bridge: DaemonBridge module
]]
function EmitterManager.init(dependencies)
    Utils = dependencies.Utils
    PoseTracker = dependencies.PoseTracker
    DaemonBridge = dependencies.DaemonBridge
    cleanup_persisted_tracks()
end

--[[
    Create a spatial audio emitter with automatic management
    
    Args:
        config: Configuration table with:
            id = string                    -- Unique identifier
            audio_path = string            -- Path to audio file
            offset_forward = number        -- Position offset (meters forward from player)
            offset_right = number          -- Position offset (meters right from player)
            offset_up = number             -- Position offset (meters up from player)
            profile = table                -- Audio profile (AudioProfiles.MEDIUM_RANGE, etc)
            volume = number (optional)     -- Volume (default: 1.0)
            loop = boolean (optional)      -- Loop audio (default: true)
            has_movement = boolean         -- Whether emitter moves
            movement_pattern = string      -- "oscillate" or nil for static
            oscillate_direction = string   -- "right", "forward", "up"
            oscillate_amplitude = number   -- Movement distance in meters
            oscillate_frequency = number   -- Movement speed in Hz
            require_listener = boolean     -- Update listener context (default: true for movement, false for static)
    
    Returns:
        emitter_id (string) on success, nil on failure
]]
function EmitterManager.create(config)
    if not Utils or not PoseTracker or not DaemonBridge then
        return nil, "EmitterManager not initialized. Call EmitterManager.init() first"
    end
    
    -- Validate required fields
    if not config.id or not config.audio_path then
        return nil, "Missing required fields: id, audio_path"
    end
    
    -- Check if emitter already exists
    if emitters[config.id] then
        return nil, "Emitter with id '" .. config.id .. "' already exists"
    end
    
    -- Resolve initial pose
    local pose = Utils.get_player_pose()
    if not pose then
        pose = {
            position = Vector3 and Vector3(0, 0, 0) or { 0, 0, 0 },
            rotation = Quaternion and Quaternion.identity() or { 0, 0, 0, 1 },
            forward = Vector3 and Vector3(0, 0, 1) or { 0, 0, 1 },
            right = Vector3 and Vector3(1, 0, 0) or { 1, 0, 0 },
        }
    end

    local initial_position = nil
    local initial_rotation = nil
    local has_provider = config.position_provider ~= nil

    if has_provider then
        local tracker_preview = {
            provider_context = config.provider_context,
        }
        local ok, position, rotation = pcall(config.position_provider, config.provider_context, tracker_preview)
        if ok and position then
            initial_position = position
            initial_rotation = rotation
        else
            return nil, "position_unavailable"
        end
    else
        initial_position = Utils.position_relative_to_player(
            config.offset_forward or 0,
            config.offset_right or 0,
            config.offset_up or 0
        )
        initial_rotation = config.has_movement and pose.forward or pose.rotation
    end
    
    -- Determine listener requirement (movement needs listener updates)
    local require_listener = config.require_listener
    if require_listener == nil then
        require_listener = config.has_movement or false
    end
    
    -- Create spatial emitter
    local ok, tracker, track_id, error_msg = DaemonBridge.create_spatial_emitter({
        id_prefix = config.id,
        path = config.audio_path,
        position = initial_position,
        forward = has_provider and nil or (config.has_movement and pose.forward or nil),
        rotation = has_provider and initial_rotation or (not config.has_movement and pose.rotation or nil),
        profile = config.profile,
        loop = config.loop ~= false,  -- Default true
        volume = config.volume or 1.0,
        autoplay = true,
        require_listener = require_listener,
        process_id = "EmitterManager",
    }, Utils, PoseTracker)
    
    if not ok or not tracker or not track_id then
        return nil, error_msg or "Failed to create emitter"
    end
    
    -- Build emitter state
    local emitter_state = {
        id = track_id,
        tracker = tracker,
        config = config,
        time = 0,
        last_update = 0,
        current_position = initial_position,
        position_provider = config.position_provider,
        provider_context = config.provider_context,
        payload_override = config.payload_override,
        provider_grace = config.provider_grace or 0.5,
        on_provider_missing = config.on_provider_missing,
    }
    
    -- Store movement data if needed
    if config.has_movement then
        emitter_state.base_position = Utils.store_vector3(initial_position)
        emitter_state.forward_direction = Utils.store_vector3(pose.forward)
        
        -- Store direction vector for movement
        if config.oscillate_direction == "right" then
            emitter_state.movement_direction = Utils.store_vector3(pose.right)
        elseif config.oscillate_direction == "forward" then
            emitter_state.movement_direction = Utils.store_vector3(pose.forward)
        elseif config.oscillate_direction == "up" then
            emitter_state.movement_direction = Utils.store_vector3(Vector3.up())
        else
            emitter_state.movement_direction = Utils.store_vector3(pose.right)  -- Default
        end
    else
        -- Static emitter - just store position
        emitter_state.position = Utils.store_vector3(initial_position)
    end
    
    -- Store in active emitters
    emitters[config.id] = emitter_state
    remember_track(config.id, track_id)
    
    return config.id
end

--[[
    Update all active emitters
    
    Should be called every frame from mod.update(dt)
    
    Args:
        dt: Delta time (seconds since last frame)
]]
function EmitterManager.update(dt)
    if not Utils or not DaemonBridge then
        return
    end
    
    for emitter_id, emitter in pairs(emitters) do
        local config = emitter.config
        local current_position = nil
        local provider_missing = false

        if emitter.position_provider then
            local ok, position, rotation = pcall(emitter.position_provider, emitter.provider_context, emitter)
            if not ok or not position then
                emitter.provider_miss_time = (emitter.provider_miss_time or 0) + (dt or 0)
                if emitter.provider_miss_time >= emitter.provider_grace then
                    provider_missing = true
                end
            else
                emitter.provider_miss_time = nil
                emitter.tracker:set_manual(position, nil, rotation)
                emitter.current_position = position
                current_position = position
            end
        end

        if provider_missing then
            if emitter.on_provider_missing then
                pcall(emitter.on_provider_missing, emitter)
            end
            EmitterManager.stop(config.id, config.provider_fail_fade)
            goto continue
        end
        
        -- Handle movement
        if not emitter.position_provider and config.has_movement and config.movement_pattern == "oscillate" then
            -- Accumulate time
            emitter.time = emitter.time + dt
            
            -- Reconstruct vectors
            local base_position = Utils.restore_vector3(emitter.base_position)
            local movement_direction = Utils.restore_vector3(emitter.movement_direction)
            local forward_direction = Utils.restore_vector3(emitter.forward_direction)
            
            if base_position and movement_direction and forward_direction then
                -- Calculate oscillating position
                local amplitude = config.oscillate_amplitude or 7.5
                local frequency = config.oscillate_frequency or 0.5
                
                current_position = Utils.calculate_oscillation(
                    emitter.time,
                    frequency,
                    amplitude,
                    movement_direction,
                    base_position
                )
                
                -- Update tracker
                emitter.tracker:set_manual(current_position, forward_direction, nil)
                
                -- Store current position for sphere rendering
                emitter.current_position = current_position
            end
        elseif not emitter.position_provider then
            -- Static emitter
            current_position = Utils.restore_vector3(emitter.position)
            emitter.current_position = current_position
        end
        
        -- Throttle daemon updates to ~50Hz
        if not Utils.throttle(emitter, "last_update", 0.02) then
            goto continue
        end
        
        -- Update spatial audio
        local payload = {
            id = emitter.id,
            tracker = emitter.tracker,
            profile = config.profile,
            volume = config.volume or 1.0,
            loop = config.loop ~= false,
        }

        if emitter.payload_override then
            local ok, overrides = pcall(emitter.payload_override, emitter, payload)
            if ok and overrides then
                if overrides.volume ~= nil then
                    payload.volume = overrides.volume
                end
                if overrides.profile ~= nil then
                    payload.profile = overrides.profile
                end
                if overrides.loop ~= nil then
                    payload.loop = overrides.loop
                end
            elseif ok == false then
                payload = payload
            end
        end

        local ok, err = DaemonBridge.update_spatial_audio(payload, Utils)
        if not ok then
            finalize_stop(config.id, "daemon")
            goto continue
        end
        
        ::continue::
    end
end

--[[
    Stop a specific emitter
    
    Args:
        emitter_id: Unique identifier passed to create()
        fade: Fade out time in seconds (default: 0)
    
    Returns:
        true on success, false if emitter doesn't exist
]]
function EmitterManager.stop(emitter_id, fade)
    local emitter = emitters[emitter_id]
    if not emitter then
        return false
    end
    
    -- Stop audio
    if DaemonBridge and emitter.id then
        DaemonBridge.stop_spatial_emitter({
            id = emitter.id,
            fade = fade or 0,
        })
    end
    
    -- Remove from active emitters
    finalize_stop(emitter_id, "manual")
    return true
end

--[[
    Stop all active emitters
    
    Useful for cleanup in on_disabled/on_unload
    
    Args:
        fade: Fade out time in seconds (default: 0)
]]
function EmitterManager.stop_all(fade)
    for emitter_id, _ in pairs(emitters) do
        EmitterManager.stop(emitter_id, fade)
    end
end

-- Stop emitters whose config id starts with the provided prefix
function EmitterManager.stop_by_prefix(prefix, fade)
    if not prefix or prefix == "" then
        return 0
    end
    local matches = {}
    for emitter_id in pairs(emitters) do
        if string.sub(emitter_id, 1, #prefix) == prefix then
            matches[#matches + 1] = emitter_id
        end
    end
    for _, emitter_id in ipairs(matches) do
        EmitterManager.stop(emitter_id, fade)
    end
    return #matches
end

--[[
    Get count of active emitters
    
    Returns:
        number of active emitters
]]
function EmitterManager.get_count()
    local count = 0
    for _ in pairs(emitters) do
        count = count + 1
    end
    return count
end

--[[
    Check if an emitter exists
    
    Args:
        emitter_id: Unique identifier
    
    Returns:
        true if emitter exists, false otherwise
]]
function EmitterManager.exists(emitter_id)
    return emitters[emitter_id] ~= nil
end

--[[
    Retrieve an emitter state by id (used by feature modules for debug markers)
]]
function EmitterManager.get(emitter_id)
    return emitters[emitter_id]
end

--[[
    Get current position of an emitter
    
    Args:
        emitter_id: Unique identifier
    
    Returns:
        Vector3 position if emitter exists, nil otherwise
]]
function EmitterManager.get_position(emitter_id)
    local emitter = emitters[emitter_id]
    return emitter and emitter.current_position or nil
end

function EmitterManager.handle_daemon_stop(track_id)
    if not track_id then
        return false
    end
    for emitter_id, emitter in pairs(emitters) do
        if emitter.id == track_id then
            finalize_stop(emitter_id, "daemon")
            return true
        end
    end
    return false
end

return EmitterManager
