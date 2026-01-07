return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`SlowMode` encountered an error loading the Darktide Mod Framework.")

		new_mod("SlowMode", {
			mod_script       = "SlowMode/scripts/mods/SlowMode/SlowMode",
			mod_data         = "SlowMode/scripts/mods/SlowMode/SlowMode_data",
			mod_localization = "SlowMode/scripts/mods/SlowMode/SlowMode_localization",
		})
	end,
	packages = {},
}
