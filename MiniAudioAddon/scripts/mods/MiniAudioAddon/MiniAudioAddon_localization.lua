return {
    mod_description = {
        en = "Provides a shared miniaudio daemon interface plus spatial audio test utilities for other mods.",
    },
    miniaudioaddon_debug = {
        en = "Enable verbose debug logging",
    },
    miniaudioaddon_debug_desc = {
        en = "Print extra information about daemon launches, pipe commands, and test payloads.",
    },
    miniaudioaddon_debug_spheres = {
        en = "Show debug spheres/labels for test emitters",
    },
    miniaudioaddon_debug_spheres_desc = {
        en = "Toggles the floating helper unit + world text that indicate where builtin tests spawn their sounds.",
    },
    miniaudioaddon_spatial_mode = {
        en = "Enable spatial daemon mode by default",
    },
    miniaudioaddon_spatial_mode_desc = {
        en = "When enabled the addon keeps the JSON pipe open for spatialized playback. Individual mods can override this at runtime.",
    },
    miniaudioaddon_spatial_rolloff = {
        en = "Default rolloff curve",
    },
    miniaudioaddon_spatial_rolloff_desc = {
        en = "Default attenuation profile used by builtin tests when a mod does not provide one.",
    },
    miniaudioaddon_spatial_occlusion = {
        en = "Default occlusion",
    },
    miniaudioaddon_spatial_occlusion_desc = {
        en = "Mix-in occlusion factor used by builtin tests (0 = disabled, 1 = fully muffled).",
    },
    miniaudioaddon_distance_scale = {
        en = "Default spatial distance scale",
    },
    miniaudioaddon_distance_scale_desc = {
        en = "Multiplies the min/max distances used by MiniAudioAddon tests when no profile is provided. Increase to hear debug audio earlier (e.g. 2.5 = ~150%% of the old range).",
    },
    miniaudioaddon_rolloff_linear = { en = "Linear" },
    miniaudioaddon_rolloff_log = { en = "Logarithmic" },
    miniaudioaddon_rolloff_exp = { en = "Exponential" },
    miniaudioaddon_rolloff_none = { en = "None" },
    miniaudioaddon_clear_logs = {
        en = "Reset daemon log automatically",
    },
    miniaudioaddon_clear_logs_desc = {
        en = "When enabled the miniaudio_dt_log.txt file is cleared on load/gameplay enter. Disable to preserve the full log across sessions.",
    },
    miniaudioaddon_api_log = {
        en = "Enable API file logging",
    },
    miniaudioaddon_api_log_desc = {
        en = "Write every MiniAudio API call and echo message to miniaudio_api_log.txt for troubleshooting. Disable to avoid large log files.",
    },
}
