return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`MiniAudioExample` requires the Darktide Mod Framework.")

        new_mod("MiniAudioExample", {
            mod_script = "MiniAudioExample/scripts/mods/MiniAudioExample/MiniAudioExample",
            mod_data = "MiniAudioExample/scripts/mods/MiniAudioExample/MiniAudioExample_data",
            mod_localization = "MiniAudioExample/scripts/mods/MiniAudioExample/MiniAudioExample_localization",
        })
    end,
    packages = {},
}
