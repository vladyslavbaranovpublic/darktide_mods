return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`AuspexHelper` encountered an error loading the Darktide Mod Framework.")

		new_mod("AuspexHelper", {
			mod_script = "AuspexHelper/scripts/mods/AuspexHelper/AuspexHelper",
			mod_data = "AuspexHelper/scripts/mods/AuspexHelper/AuspexHelper_data",
			mod_localization = "AuspexHelper/scripts/mods/AuspexHelper/AuspexHelper_localization",
		})
	end,
	packages = {},
}
