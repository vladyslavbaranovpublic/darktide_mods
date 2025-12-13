return {
    run = function()
        fassert(rawget(_G, "new_mod"), "MiniAudioAddon requires the Darktide Mod Framework.")

        new_mod("MiniAudioAddon", {
            mod_script = "MiniAudioAddon/scripts/mods/MiniAudioAddon/MiniAudioAddon",
            mod_data = "MiniAudioAddon/scripts/mods/MiniAudioAddon/MiniAudioAddon_data",
            mod_localization = "MiniAudioAddon/scripts/mods/MiniAudioAddon/MiniAudioAddon_localization",
        })
    end,
    packages = {},
}
