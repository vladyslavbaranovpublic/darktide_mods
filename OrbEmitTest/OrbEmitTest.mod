return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`OrbEmitTest` encountered an error loading the Darktide Mod Framework.")

		new_mod("OrbEmitTest", {
			mod_script       = "OrbEmitTest/scripts/mods/OrbEmitTest/OrbEmitTest",
			mod_data         = "OrbEmitTest/scripts/mods/OrbEmitTest/OrbEmitTest_data",
			mod_localization = "OrbEmitTest/scripts/mods/OrbEmitTest/OrbEmitTest_localization",
		})
	end,
	packages = {},
}
