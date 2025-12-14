return {
    mod_name = {
        en = "Elevator Music",
    },
    mod_description = {
        en = "Plays one of the tracks from mods/ElevatorMusic/audio whenever a moveable platform or airlock is active. Powered purely by MiniAudioAddon’s API.",
    },
    elevatormusic_group = {
        en = "Elevator Music",
    },
    elevatormusic_enable = {
        en = "Enable elevator music",
    },
    elevatormusic_enable_desc = {
        en = "Master toggle. Turn this off to silence every elevator/airlock without removing the mod.",
    },
    elevatormusic_play_activation = {
        en = "Play during elevator movement",
    },
    elevatormusic_play_activation_desc = {
        en = "When enabled, a track is started (or promoted from the idle speaker) as soon as the platform begins moving.",
    },
    elevatormusic_activation_linger = {
        en = "Linger after ride (seconds)",
    },
    elevatormusic_activation_linger_desc = {
        en = "How long to keep the activation track alive after the platform stops before fading out.",
    },
    elevatormusic_idle_enabled = {
        en = "Play while you wait nearby",
    },
    elevatormusic_idle_enabled_desc = {
        en = "Start a quiet “lobby” mix whenever you stand close to a platform that is not moving.",
    },
    elevatormusic_idle_after_activation = {
        en = "Return to idle music after rides",
    },
    elevatormusic_idle_after_activation_desc = {
        en = "If on, once the ride ends (and you are still nearby) the idle speaker spins back up automatically.",
    },
    elevatormusic_idle_distance = {
        en = "Idle radius (meters)",
    },
    elevatormusic_idle_distance_desc = {
        en = "Start/keep the idle speaker while you are within this many meters of the platform.",
    },
    elevatormusic_idle_full_distance = {
        en = "Idle full volume distance (meters)",
    },
    elevatormusic_idle_full_distance_desc = {
        en = "Idle music fades up as you approach the platform. Inside this distance it reaches full volume.",
    },
    elevatormusic_random_order = {
        en = "Randomize track order",
    },
    elevatormusic_random_order_desc = {
        en = "Shuffle the playlist each time instead of cycling in alphabetical order.",
    },
    elevatormusic_volume_percent = {
        en = "Overall volume (%%)",
    },
    elevatormusic_volume_percent_desc = {
        en = "Linear gain applied to every track before it is sent to MiniAudio (100%% = unchanged).",
    },
    elevatormusic_fade_seconds = {
        en = "Fade-out duration (seconds)",
    },
    elevatormusic_fade_seconds_desc = {
        en = "Optional fade that is applied whenever a track stops. Set to 0 for an instant cut.",
    },
    elevatormusic_spatial_rolloff = {
        en = "Spatial rolloff curve",
    },
    elevatormusic_spatial_rolloff_desc = {
        en = "Choose how volume decays with distance when MiniAudioAddon spatializes the source.",
    },
    elevatormusic_spatial_rolloff_linear = {
        en = "Linear",
    },
    elevatormusic_spatial_rolloff_log = {
        en = "Logarithmic",
    },
    elevatormusic_show_markers = {
        en = "Show debug spheres on elevators",
    },
    elevatormusic_show_markers_desc = {
        en = "Draws the same wireframe sphere used by MiniAudioAddon tests so you can see exactly where the sound source sits for each platform.",
    },
    elevatormusic_test_emitter = {
        en = "Diagnostic MiniAudio test sphere",
    },
    elevatormusic_test_emitter_desc = {
        en = "Spawns a standalone MiniAudio emitter near you that glides back and forth so you can verify spatial audio and inspect the daemon log without riding a lift.",
    },
    elevatormusic_debug = {
        en = "Debug: echo actions",
    },
    elevatormusic_debug_desc = {
        en = "Print every play/stop/update request to the chat log for troubleshooting.",
    },
    elevatormusic_visuals_group = {
        en = "Emitter Visuals",
    },
    elevatormusic_visuals_group_desc = {
        en = "Optional rainbow halo inspired by Disco Aquila that follows each elevator emitter.",
    },
    elevatormusic_visuals_enable = {
        en = "Enable rainbow halo",
    },
    elevatormusic_visuals_enable_desc = {
        en = "Shows a colorful animated aura around every elevator speaker. Requires MiniAudioAddon 1.3+.",
    },
    elevatormusic_visuals_speed = {
        en = "Color cycle speed",
    },
    elevatormusic_visuals_speed_desc = {
        en = "How fast the rainbow sweeps through the color spectrum (higher values spin faster).",
    },
    elevatormusic_visuals_randomness = {
        en = "Random sparkle",
    },
    elevatormusic_visuals_randomness_desc = {
        en = "Adds a little random hue jitter each frame so the halo glitters like Disco Aquila.",
    },
    elevatormusic_visuals_radius = {
        en = "Halo radius (meters)",
    },
    elevatormusic_visuals_radius_desc = {
        en = "Size of the rainbow sphere that marks the emitter.",
    },
}
