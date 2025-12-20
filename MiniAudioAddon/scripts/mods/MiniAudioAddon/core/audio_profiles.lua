--[[
    File: core/audio_profiles.lua
    Description: Predefined audio profile configurations for common use cases.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
    
    Usage:
        local AudioProfiles = MiniAudio.audio_profiles
        
        -- Use a preset directly
        profile = AudioProfiles.MEDIUM_RANGE
        
        -- Or customize a copy
        local my_profile = AudioProfiles.copy(AudioProfiles.AMBIENT)
        my_profile.max_distance = 200.0
]]

local AudioProfiles = {}

--[[
    Predefined audio profiles optimized for different scenarios
    
    Rolloff modes:
        "linear" - Linear falloff (predictable, even dropoff)
        "logarithmic" - Logarithmic falloff (realistic, slower at distance)
        "exponential" - Exponential falloff (dramatic, fast dropoff)
        "none" - No distance-based falloff (constant volume)
]]

-- Close range audio (e.g., pickups, small objects, footsteps)
AudioProfiles.CLOSE_RANGE = {
    min_distance = 0.5,
    max_distance = 5.0,
    rolloff = "linear",
}

-- Medium range audio (e.g., weapons, abilities, effects) - DEFAULT
AudioProfiles.MEDIUM_RANGE = {
    min_distance = 1.0,
    max_distance = 20.0,
    rolloff = "logarithmic",
}

-- Long range audio (e.g., explosions, alarms, distant sounds)
AudioProfiles.LONG_RANGE = {
    min_distance = 2.0,
    max_distance = 50.0,
    rolloff = "logarithmic",
}

-- Ambient audio (e.g., music, environmental loops, background)
AudioProfiles.AMBIENT = {
    min_distance = 0.0,
    max_distance = 100.0,
    rolloff = "exponential",
}

-- Voice audio (e.g., dialogue, callouts, speech)
AudioProfiles.VOICE = {
    min_distance = 0.3,
    max_distance = 15.0,
    rolloff = "linear",
}

-- Interior audio (e.g., indoor spaces, rooms)
AudioProfiles.INTERIOR = {
    min_distance = 0.5,
    max_distance = 12.0,
    rolloff = "linear",
}

-- Exterior audio (e.g., outdoor spaces, open areas)
AudioProfiles.EXTERIOR = {
    min_distance = 1.5,
    max_distance = 35.0,
    rolloff = "logarithmic",
}

AudioProfiles.IN_HEAD = {
    min_distance = 1,
    max_distance = 1,  -- Same as min = no attenuation
    rolloff = "none",
}

--[[
    Create a copy of a profile for customization
    
    Args:
        profile: Audio profile table to copy
    
    Returns:
        Deep copy of the profile
    
    Example:
        local custom = AudioProfiles.copy(AudioProfiles.VOICE)
        custom.max_distance = 25.0
]]
function AudioProfiles.copy(profile)
    if not profile then
        return nil
    end
    
    return {
        min_distance = profile.min_distance,
        max_distance = profile.max_distance,
        rolloff = profile.rolloff,
    }
end

--[[
    Get profile by name (case-insensitive)
    
    Args:
        name: Profile name string (e.g., "medium_range", "VOICE")
    
    Returns:
        Profile table or nil if not found
    
    Example:
        local profile = AudioProfiles.get("medium_range")
]]
function AudioProfiles.get(name)
    if not name or type(name) ~= "string" then
        return nil
    end
    
    local key = name:upper():gsub(" ", "_")
    return AudioProfiles[key]
end

return AudioProfiles
