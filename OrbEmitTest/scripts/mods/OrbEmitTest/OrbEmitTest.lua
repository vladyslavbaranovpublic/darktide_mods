--[[
    OrbEmitTest - MiniAudioAddon High-Level API Demonstration
    
    This mod demonstrates how to use the MiniAudioAddon high-level API to create 3D spatial
    audio emitters in the game world. It creates three "orbs":
    
    - Orb 1: "In head" audio (no spatial positioning, constant volume) - demonstrates non-spatial audio
    - Orb 2: Moving emitter that oscillates left/right with visual sphere - demonstrates dynamic spatial audio
    - Orb 3: Static spatial audio emitter ahead with visual sphere - demonstrates static spatial audio
    
    Key API Features Demonstrated:
    1. DaemonBridge.create_spatial_emitter() - High-level emitter creation
    2. DaemonBridge.update_spatial_audio() - Simplified position/listener updates
    3. DaemonBridge.stop_spatial_emitter() - Clean shutdown with fade support
    4. AudioProfiles - Predefined audio profile presets
    5. Utils.calculate_oscillation() - Reusable movement patterns
    6. Utils.throttle() - Rate limiting for performance
    7. Sphere.toggle() - Conditional visual debugging
]]

local mod = get_mod("OrbEmitTest")
local MiniAudio = get_mod("MiniAudioAddon")

-- Build path relative to mods folder - expand_track_path will resolve it
local relative_audio_path = "OrbEmitTest/audio/test_audio.mp3"
local audio_path = MiniAudio.IOUtils.expand_track_path and MiniAudio.IOUtils.expand_track_path(relative_audio_path) or relative_audio_path
if not audio_path or audio_path == relative_audio_path then
    mod:echo("[ERROR] Could not find audio file: %s", relative_audio_path)
    return
end

-- Audio profile - uses MEDIUM_RANGE preset (1m-20m, logarithmic rolloff)
local AUDIO_PROFILE = MiniAudio and MiniAudio.audio_profiles and MiniAudio.audio_profiles.MEDIUM_RANGE or {min_distance = 1.0, max_distance = 20.0, rolloff = "logarithmic",}

-- Debug logging wrapper - controlled by "debug_logging" setting
local function debug_echo(format, ...)
    if mod:get("debug_logging") then
        mod:echo(format, ...)
    end
end

-- Helper function to build config with current offset settings
local function build_orb_config(orb_name, base_config)
    local config = {}
    for k, v in pairs(base_config) do
        config[k] = v
    end
    
    -- Read offset values from settings
    config.offset_forward = mod:get(orb_name .. "_offset_forward") or config.offset_forward
    config.offset_right = mod:get(orb_name .. "_offset_right") or config.offset_right
    config.offset_up = mod:get(orb_name .. "_offset_up") or config.offset_up
    
    return config
end

-- Base orb configurations using EmitterManager API
-- Offsets are read from settings to allow user control
local ORB_CONFIGS_BASE = {
    orb1 = {
        id = "orb1",
        setting_key = "orb1_enabled",
        audio_path = audio_path,
        offset_forward = 0,    -- At player head position
        offset_right = 0,
        offset_up = 0,
        profile = MiniAudio.audio_profiles.IN_HEAD,  -- No distance attenuation
        has_movement = false,
        require_listener = false,  -- Don't update listener = stays "in head"
    },
    orb2 = {
        id = "orb2",
        setting_key = "orb2_enabled",
        audio_path = audio_path,
        offset_forward = 7,    -- Default values (overridden by settings)
        offset_right = 0,
        offset_up = 0,
        profile = AUDIO_PROFILE,
        has_movement = true,
        movement_pattern = "oscillate",
        oscillate_direction = "right",
        oscillate_amplitude = 7.5,
        oscillate_frequency = 0.5,
        sphere_setting_key = "orb2_show_sphere",
        sphere_color = {80, 200, 255},  -- Cyan
    },
    orb3 = {
        id = "orb3",
        setting_key = "orb3_enabled",
        audio_path = audio_path,
        offset_forward = 3,    -- Default values (overridden by settings)
        offset_right = 0,
        offset_up = 0,
        profile = AUDIO_PROFILE,
        has_movement = false,
        require_listener = true,  -- Proper spatial audio with listener updates
        sphere_setting_key = "orb3_show_sphere",
        sphere_color = {255, 80, 80},  -- Red
    },
}

-- ============================== EMITTER MANAGEMENT ==============================================
-- All emitter management is now handled by EmitterManager API

-- ========================== SETTING CHANGES ============================
mod.on_setting_changed = function(setting_id)
    if not MiniAudio or not MiniAudio.emitter_manager then return end
    
    -- Handle offset changes - recreate emitter with new position
    if setting_id:match("_offset_") then
        local orb_name = setting_id:match("^(.+)_offset_")
        local base_config = ORB_CONFIGS_BASE[orb_name]
        
        if base_config and mod:get(base_config.setting_key) and MiniAudio.emitter_manager.exists(base_config.id) then
            -- Stop existing emitter
            MiniAudio.emitter_manager.stop(base_config.id)
            
            -- Recreate with new offsets
            local config = build_orb_config(orb_name, base_config)
            local emitter_id, error_msg = MiniAudio.emitter_manager.create(config)
            if emitter_id then
                debug_echo("Recreated emitter %s at new position", emitter_id)
            else
                debug_echo("Failed to recreate emitter %s: %s", base_config.id, error_msg or "unknown error")
            end
        end
        return
    end
    
    -- Handle enable/disable
    local orb_name = setting_id:gsub("_enabled", "")
    local base_config = ORB_CONFIGS_BASE[orb_name]
    if not base_config then return end
    
    if mod:get(base_config.setting_key) then
        -- Create emitter using EmitterManager with current offset settings
        local config = build_orb_config(orb_name, base_config)
        local emitter_id, error_msg = MiniAudio.emitter_manager.create(config)
        if emitter_id then
            debug_echo("Created emitter: %s", emitter_id)
        else
            debug_echo("Failed to create emitter %s: %s", config.id, error_msg or "unknown error")
        end
    else
        -- Stop emitter using EmitterManager
        if MiniAudio.emitter_manager.stop(base_config.id) then
            debug_echo("Stopped emitter: %s", base_config.id)
        end
    end
end

-- ========================== CLEANUP ============================
local function cleanup_all_orbs()
    if MiniAudio and MiniAudio.emitter_manager then
        MiniAudio.emitter_manager.stop_all()
    end
    if MiniAudio and MiniAudio.api then
        MiniAudio.api.register_client(mod:get_name(), false)
    end
end

mod.on_disabled = cleanup_all_orbs
mod.on_unload = cleanup_all_orbs

-- ========================== MOD UPDATE ============================
mod.update = function(dt)
    -- Update all emitters managed by EmitterManager, you can take those methods out to have more control
    if MiniAudio and MiniAudio.emitter_manager then
        MiniAudio.emitter_manager.update(dt)
    end
    
    -- Render spheres for emitters with sphere_setting_key
    if MiniAudio and MiniAudio.sphere and MiniAudio.emitter_manager then
        for orb_name, base_config in pairs(ORB_CONFIGS_BASE) do
            if base_config.sphere_setting_key and mod:get(base_config.setting_key) then
                local show_sphere = mod:get(base_config.sphere_setting_key)
                local position = MiniAudio.emitter_manager.get_position(base_config.id)
                
                if position and show_sphere then
                    MiniAudio.sphere.toggle(base_config.id, true, position, base_config.sphere_color, 0.5)
                end
            end
        end
        MiniAudio.sphere.render_all()
    end
end


-- ========================== INITIALIZATION ============================
mod.on_all_mods_loaded = function()
    -- Verify MiniAudioAddon dependency
    if not MiniAudio or not MiniAudio.emitter_manager then
        mod:echo("[ERROR] MiniAudioAddon or EmitterManager not available!")
        return
    end
    
    -- Enable spatial mode (required for 3D audio)
    if MiniAudio.set_spatial_mode then
        pcall(MiniAudio.set_spatial_mode, MiniAudio, true)
    end
    
    -- Register as API client
    if MiniAudio.api then
        MiniAudio.api.register_client(mod:get_name(), true)
    end
    
    debug_echo("OrbEmitTest loaded - using EmitterManager API")
end
