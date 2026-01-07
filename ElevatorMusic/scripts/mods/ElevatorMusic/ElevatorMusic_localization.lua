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
    elevatormusic_valk_enable = {
        en = "Enable gunship/Valkyrie music",
    },
    elevatormusic_valk_enable_desc = {
        en = "Attach the same playlist, volume, and disco logic to Valkyrie drop-ships so the emitter follows the transport as it moves.",
    },
    elevatormusic_valk_idle_distance = {
        en = "Gunship idle radius (meters)",
    },
    elevatormusic_valk_idle_distance_desc = {
        en = "How close you must be to the Valkyrie for its idle speaker to spin up. Increase this if you want the ship to start playing while you are farther down the ramp.",
    },
    elevatormusic_valk_idle_full_distance = {
        en = "Gunship full-volume distance (meters)",
    },
    elevatormusic_valk_idle_full_distance_desc = {
        en = "Inside this distance the Valkyrie track hits full volume. Beyond it the controller fades the music down smoothly.",
    },
    elevatormusic_activation_linger = {
        en = "Linger after ride (seconds)",
    },
    elevatormusic_activation_linger_desc = {
        en = "Only used when “Play while you wait nearby” is disabled; keeps the ride track alive for this many seconds before fading out.",
    },
    elevatormusic_activation_only = {
        en = "Play only during movement",
    },
    elevatormusic_activation_only_desc = {
        en = "Override idle playback so audio only plays while the elevator is moving. When the ride ends it fades out after the configured linger delay.",
    },
    elevatormusic_idle_after_activation = {
        en = "Return to idle music after rides",
    },
    elevatormusic_idle_after_activation_desc = {
        en = "If on, once the ride ends (and you are still nearby) the idle speaker spins back up automatically.",
    },
    elevatormusic_shuffle_on_end = {
        en = "Switch tracks when one finishes",
    },
    elevatormusic_shuffle_on_end_desc = {
        en = "Instead of looping the same song forever, stop after a single play and pick another random track automatically.",
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
    elevatormusic_spatial_rolloff_exp = {
        en = "Exponential",
    },
    elevatormusic_spatial_rolloff_none = {
        en = "None",
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
    elevatormusic_visuals_halo_count = {
        en = "Halos per emitter",
    },
    elevatormusic_visuals_halo_count_desc = {
        en = "Draw several concentric halos for a denser disco effect.",
    },
    elevatormusic_visuals_radius_min = {
        en = "Minimum halo radius (meters)",
    },
    elevatormusic_visuals_radius_min_desc = {
        en = "Smallest size any halo in the stack can be.",
    },
    elevatormusic_visuals_radius_max = {
        en = "Maximum halo radius (meters)",
    },
    elevatormusic_visuals_radius_max_desc = {
        en = "Largest size any halo in the stack can be.",
    },
    elevatormusic_visuals_light_count = {
        en = "Lights per halo",
    },
    elevatormusic_visuals_light_count_desc = {
        en = "How many animated flashlight beams orbit each halo (higher values cost more performance).",
    },
    elevatormusic_visuals_light_orbit_variance = {
        en = "Light orbit variance",
    },
    elevatormusic_visuals_light_orbit_variance_desc = {
        en = "Adds in/out sway to every light so the paths look like drifting snowflakes instead of perfect circles.",
    },
    elevatormusic_visuals_light_vertical_variance = {
        en = "Light vertical variance",
    },
    elevatormusic_visuals_light_vertical_variance_desc = {
        en = "How far each light bobs up and down while it travels around the halo.",
    },
    elevatormusic_visuals_loop_speed = {
        en = "Light loop speed",
    },
    elevatormusic_visuals_loop_speed_desc = {
        en = "Controls how fast those in/out/vertical motions evolve (set to 0 for static lights).",
    },
    elevatormusic_visuals_spin_randomness = {
        en = "Spin randomness",
    },
    elevatormusic_visuals_spin_randomness_desc = {
        en = "Adds extra variance to each halo's spin speed so they rotate at different rates.",
    },
    elevatormusic_visuals_show_core = {
        en = "Show core sphere",
    },
    elevatormusic_visuals_show_core_desc = {
        en = "Toggle the solid debug orb while keeping the animated halo lights on.",
    },
    elevatormusic_visuals_orbit_radius = {
        en = "Center orbit radius (meters)",
    },
    elevatormusic_visuals_orbit_radius_desc = {
        en = "How far the halo's center drifts around the elevator source.",
    },
    elevatormusic_visuals_orbit_speed = {
        en = "Center orbit speed",
    },
    elevatormusic_visuals_orbit_speed_desc = {
        en = "Speed multiplier for the center drift (set to 0 for a stationary halo).",
    },
    elevatormusic_visuals_scatter_enable = {
        en = "Enable sprinkle lights",
    },
    elevatormusic_visuals_scatter_enable_desc = {
        en = "Spawns small floating spheres at random positions instead of a single orbit ring.",
    },
    elevatormusic_visuals_scatter_count = {
        en = "Sprinkle count",
    },
    elevatormusic_visuals_scatter_count_desc = {
        en = "How many independent sprinkle spheres to spawn around each emitter.",
    },
    elevatormusic_visuals_scatter_distance = {
        en = "Sprinkle spread radius (meters)",
    },
    elevatormusic_visuals_scatter_distance_desc = {
        en = "Maximum distance from the emitter that sprinkle spheres can spawn.",
    },
    elevatormusic_visuals_scatter_size_min = {
        en = "Sprinkle size (min meters)",
    },
    elevatormusic_visuals_scatter_size_min_desc = {
        en = "Smallest radius for a sprinkle sphere.",
    },
    elevatormusic_visuals_scatter_size_max = {
        en = "Sprinkle size (max meters)",
    },
    elevatormusic_visuals_scatter_size_max_desc = {
        en = "Largest radius for a sprinkle sphere.",
    },
    elevatormusic_visuals_scatter_speed = {
        en = "Sprinkle drift speed",
    },
    elevatormusic_visuals_scatter_speed_desc = {
        en = "Controls how fast sprinkle spheres sway using sine/cosine motion.",
    },
    elevatormusic_visuals_scatter_hover = {
        en = "Sprinkle hover amplitude",
    },
    elevatormusic_visuals_scatter_hover_desc = {
        en = "Vertical bob amount applied to sprinkle spheres (set to 0 for static height).",
    },
    elevatormusic_visuals_scatter_sway = {
        en = "Sprinkle sway distance",
    },
    elevatormusic_visuals_scatter_sway_desc = {
        en = "Horizontal jitter radius for sprinkle spheres so they drift left/right instead of only moving vertically.",
    },
    elevatormusic_visuals_scatter_vertical_offset = {
        en = "Sprinkle vertical offset (meters)",
    },
    elevatormusic_visuals_scatter_vertical_offset_desc = {
        en = "Moves the center of the sprinkle cloud up or down relative to the emitter (negative values lower it).",
    },
}
