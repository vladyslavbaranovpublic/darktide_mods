local mod = get_mod("MiniAudioExample")

return {
    name = "MiniAudioExample",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "mae_keybind_group",
                type = "group",
                title = "mae_keybind_group",
                sub_widgets = {
                    {
                        setting_id = "mae_toggle_window_keybind",
                        type = "keybind",
                        title = "mae_toggle_window_keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "keybind_toggle_window",
                    },
                },
            },
            {
                setting_id = "mae_auto_open",
                type = "checkbox",
                default_value = false,
                title = "mae_auto_open",
                tooltip = "mae_auto_open_desc",
            },
            {
                setting_id = "mae_debug_logging",
                type = "checkbox",
                default_value = false,
                title = "mae_debug_logging",
                tooltip = "mae_debug_logging_desc",
            },
        },
    },
}
