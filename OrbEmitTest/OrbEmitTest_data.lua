--[[
    OrbEmitTest Settings Configuration
    
    Defines the mod's settings that appear in the mod configuration menu.
]]

local mod = get_mod("OrbEmitTest")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "orb1_enabled",
                type = "checkbox",
                default_value = false,
                tooltip = "orb1_tooltip",
            },
            {
                setting_id = "orb2_enabled",
                type = "checkbox",
                default_value = false,
                tooltip = "orb2_tooltip",
            },
            {
                setting_id = "orb3_enabled",
                type = "checkbox",
                default_value = false,
                tooltip = "orb3_tooltip",
            },
        }
    }
}
