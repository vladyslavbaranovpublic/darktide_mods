return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`TalentPreview` encountered an error loading the Darktide Mod Framework.")

        new_mod("TalentPreview", {
            mod_script = "TalentPreview/scripts/mods/TalentPreview/TalentPreview",
            mod_data = "TalentPreview/scripts/mods/TalentPreview/TalentPreview_data",
            mod_localization = "TalentPreview/scripts/mods/TalentPreview/TalentPreview_localization",
        })
    end,
    packages = {},
}
