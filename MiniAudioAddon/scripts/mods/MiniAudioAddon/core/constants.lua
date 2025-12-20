--[[
    File: core/constants.lua
    Description: Central constants registry for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local Constants = {}

-- ============================================================================
-- DAEMON CONSTANTS
-- ============================================================================

Constants.MIN_TRANSPORT_SPEED = 0.125
Constants.MAX_TRANSPORT_SPEED = 4.0

Constants.DAEMON_WATCHDOG_WINDOW = 5.0
Constants.DAEMON_WATCHDOG_COOLDOWN = 0.35
Constants.DAEMON_STATUS_POLL_INTERVAL = 1.0

Constants.PIPE_RETRY_MAX_ATTEMPTS = 60
Constants.PIPE_RETRY_GRACE = 4.0
Constants.PIPE_RETRY_DELAY = 0.05

-- ============================================================================
-- TRACK IDS
-- ============================================================================

Constants.TRACK_IDS = {
    manual = "__miniaudio_manual",
    emitter = "__miniaudio_emitter",
}

-- ============================================================================
-- MARKER SETTINGS
-- ============================================================================

Constants.MARKER_SETTINGS = {
    emitter_unit = "core/units/cube",
    update_interval = 0.15,
    emitter_text = "miniaudio_emitter",
    emitter_label = "MiniAudio Emit",
    spatial_text = "miniaudio_spatial",
    spatial_label = "MiniAudio Spatial",
    default_color = nil,  -- Will be set after Vector3 is available
}

-- ============================================================================
-- SIMPLE TEST TRACKS
-- ============================================================================

Constants.SIMPLE_TEST = {
    tracks = {
        mp3 = "Audio\\test\\Free_Test_Data_2MB_MP3.mp3",
        wav = "Audio\\test\\Free_Test_Data_2MB_WAV.wav",
    },
    default = "mp3",
}

-- ============================================================================
-- AUDIO EXTENSIONS / PLAYLIST DEFAULTS
-- ============================================================================

Constants.AUDIO_EXTENSIONS = {
    [".mp3"] = true,
    [".wav"] = true,
    [".flac"] = true,
}

Constants.UNSUPPORTED_AUDIO_EXTENSIONS = {
    [".ogg"] = "Ogg Vorbis",
    [".opus"] = "Opus",
}

Constants.DEFAULT_AUDIO_FALLBACKS = {
    "elevator_music.mp3",
    "elevator_music.wav",
    "Darktide Elevator Music 2025-12-04 09_14_fixed.mp3",
}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize constants that depend on engine globals
function Constants.init()
    local Vector3 = rawget(_G, "Vector3")
    if Vector3 then
        Constants.MARKER_SETTINGS.default_color = Vector3(255, 220, 80)
    end
end

return Constants
