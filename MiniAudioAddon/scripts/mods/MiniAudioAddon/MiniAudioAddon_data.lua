local mod = get_mod("MiniAudioAddon")

return {
    name = "MiniAudioAddon",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "miniaudioaddon_debug",
                type = "checkbox",
                default_value = false,
                tooltip = "miniaudioaddon_debug_desc",
            },
            {
                setting_id = "miniaudioaddon_debug_spheres",
                type = "checkbox",
                default_value = true,
                tooltip = "miniaudioaddon_debug_spheres_desc",
            },
            {
                setting_id = "miniaudioaddon_spatial_mode",
                type = "checkbox",
                default_value = true,
                tooltip = "miniaudioaddon_spatial_mode_desc",
            },
            {
                setting_id = "miniaudioaddon_spatial_rolloff",
                type = "dropdown",
                default_value = "linear",
                tooltip = "miniaudioaddon_spatial_rolloff_desc",
                options = {
                    { text = "miniaudioaddon_rolloff_linear", value = "linear" },
                    { text = "miniaudioaddon_rolloff_log", value = "logarithmic" },
                    { text = "miniaudioaddon_rolloff_exp", value = "exponential" },
                    { text = "miniaudioaddon_rolloff_none", value = "none" },
                },
            },
            {
                setting_id = "miniaudioaddon_spatial_occlusion",
                type = "numeric",
                default_value = 0,
                range = { 0, 1 },
                tooltip = "miniaudioaddon_spatial_occlusion_desc",
            },
            {
                setting_id = "miniaudioaddon_distance_scale",
                type = "numeric",
                default_value = 1.0,
                range = { 0.5, 4 },
                decimals_number = 1,
                tooltip = "miniaudioaddon_distance_scale_desc",
            },
        },
    },
}
