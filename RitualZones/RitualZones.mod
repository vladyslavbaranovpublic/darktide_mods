return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`RitualZones` encountered an error loading the Darktide Mod Framework.")

		new_mod("RitualZones", {
			mod_script       = "RitualZones/scripts/mods/RitualZones/RitualZones",
			mod_data         = "RitualZones/scripts/mods/RitualZones/RitualZones_data",
			mod_localization = "RitualZones/scripts/mods/RitualZones/RitualZones_localization",
		})
	end,
	packages = {},
}
