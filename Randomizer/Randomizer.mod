--[[
    File: Randomizer.mod
    Description: Mod registration file for the Randomizer mod.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Randomizer` encountered an error loading the Darktide Mod Framework.")

        new_mod("Randomizer", {
            mod_script       = "Randomizer/scripts/mods/Randomizer/Randomizer",
            mod_data         = "Randomizer/scripts/mods/Randomizer/Randomizer_data",
            mod_localization = "Randomizer/scripts/mods/Randomizer/Randomizer_localization",
        })
    end,
    packages = {},
}
