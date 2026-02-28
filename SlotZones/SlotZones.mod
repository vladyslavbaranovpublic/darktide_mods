return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`SlotZones` encountered an error loading the Darktide Mod Framework.")

		new_mod("SlotZones", {
			mod_script = "SlotZones/scripts/mods/SlotZones/SlotZones",
			mod_data = "SlotZones/scripts/mods/SlotZones/SlotZones_data",
			mod_localization = "SlotZones/scripts/mods/SlotZones/SlotZones_localization",
		})
	end,
	packages = {},
}
