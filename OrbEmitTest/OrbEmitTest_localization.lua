--[[
    OrbEmitTest Localization (English)
]]

return {
    mod_name = {
        en = "Orb Emit Test",
    },
    mod_description = {
        en = "MiniAudioAddon API demonstration with spatial audio examples",
    },
    
    -- Orb 1 - "In Head" static example
    orb1_enabled = {
        en = "Enable Orb 1 (Static 'In Head' Example)",
    },
    orb1_tooltip = {
        en = "Static audio 5m ahead. Listener NOT updated - sounds 'in your head' (wrong approach)",
    },
    
    -- Orb 2 - "In Head" moving example
    orb2_enabled = {
        en = "Enable Orb 2 (Moving 'In Head' Example)",
    },
    orb2_tooltip = {
        en = "Moving audio left/right. Listener NOT updated - sounds 'in your head' (wrong approach)",
    },
    
    -- Orb 3 - Proper spatial audio
    orb3_enabled = {
        en = "Enable Orb 3 (Proper Spatial Audio)",
    },
    orb3_tooltip = {
        en = "Static audio 5m ahead. Listener updated every frame - PROPER 3D spatial audio",
    },
}
