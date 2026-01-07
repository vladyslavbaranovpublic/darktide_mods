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
    
    -- Debug logging
    debug_logging = {
        en = "Enable Debug Logging",
    },
    debug_logging_tooltip = {
        en = "Show debug messages in chat (orb creation, updates, errors). Disable for cleaner chat",
    },
    
    -- Orb 1 - "In Head" audio (no spatial audio)
    orb1_enabled = {
        en = "Enable Orb 1 ('In Head' Audio - No Spatial)",
    },
    orb1_tooltip = {
        en = "Audio at player position with no distance attenuation or panning - sounds 'in your head'",
    },
    orb1_offset_forward = {
        en = "Orb 1 - Forward Offset (meters)",
    },
    orb1_offset_forward_tooltip = {
        en = "Distance forward from player. Positive = ahead, Negative = behind",
    },
    orb1_offset_right = {
        en = "Orb 1 - Right Offset (meters)",
    },
    orb1_offset_right_tooltip = {
        en = "Distance right from player. Positive = right, Negative = left",
    },
    orb1_offset_up = {
        en = "Orb 1 - Up Offset (meters)",
    },
    orb1_offset_up_tooltip = {
        en = "Distance up from player. Positive = up, Negative = down",
    },
    
    -- Orb 2 - Moving spatial audio with visual
    orb2_enabled = {
        en = "Enable Orb 2 (Moving Spatial Audio)",
    },
    orb2_tooltip = {
        en = "Moving audio oscillating 15m left/right. Listener updated - PROPER 3D spatial audio",
    },
    orb2_show_sphere = {
        en = "Show Orb 2 Visual Sphere",
    },
    orb2_show_sphere_tooltip = {
        en = "Draw a cyan wireframe sphere showing where Orb 2's audio emitter is positioned",
    },
    orb2_offset_forward = {
        en = "Orb 2 - Forward Offset (meters)",
    },
    orb2_offset_forward_tooltip = {
        en = "Starting distance forward from player before oscillation",
    },
    orb2_offset_right = {
        en = "Orb 2 - Right Offset (meters)",
    },
    orb2_offset_right_tooltip = {
        en = "Starting distance right from player before oscillation",
    },
    orb2_offset_up = {
        en = "Orb 2 - Up Offset (meters)",
    },
    orb2_offset_up_tooltip = {
        en = "Starting distance up from player before oscillation",
    },
    
    -- Orb 3 - Static spatial audio with visual
    orb3_enabled = {
        en = "Enable Orb 3 (Static Spatial Audio)",
    },
    orb3_tooltip = {
        en = "Static audio 5m ahead. Listener updated every frame - PROPER 3D spatial audio",
    },
    orb3_show_sphere = {
        en = "Show Orb 3 Visual Sphere",
    },
    orb3_show_sphere_tooltip = {
        en = "Draw a red wireframe sphere showing where Orb 3's audio emitter is positioned",
    },
    orb3_offset_forward = {
        en = "Orb 3 - Forward Offset (meters)",
    },
    orb3_offset_forward_tooltip = {
        en = "Distance forward from player. Positive = ahead, Negative = behind",
    },
    orb3_offset_right = {
        en = "Orb 3 - Right Offset (meters)",
    },
    orb3_offset_right_tooltip = {
        en = "Distance right from player. Positive = right, Negative = left",
    },
    orb3_offset_up = {
        en = "Orb 3 - Up Offset (meters)",
    },
    orb3_offset_up_tooltip = {
        en = "Distance up from player. Positive = up, Negative = down",
    },
}
