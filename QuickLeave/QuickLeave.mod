--[[
	File: QuickLeave.mod
	Description: Mod entrypoint registration for DMF.
	Overall Release Version: 1.0.0
	File Version: 1.0.0
	File Introduced in: 1.0.0
	Last Updated: 2026-02-06
	Author: Vlad
]]
return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`QuickLeave` encountered an error loading the Darktide Mod Framework.")

		new_mod("QuickLeave", {
			mod_script       = "QuickLeave/scripts/mods/QuickLeave/QuickLeave",
			mod_data         = "QuickLeave/scripts/mods/QuickLeave/QuickLeave_data",
			mod_localization = "QuickLeave/scripts/mods/QuickLeave/QuickLeave_localization",
		})
	end,
	packages = {},
}

