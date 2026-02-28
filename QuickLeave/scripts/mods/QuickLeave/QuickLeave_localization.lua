--[[
	File: QuickLeave_localization.lua
	Description: Localization strings for UI and settings.
	Overall Release Version: 1.1.0
	File Version: 1.1.0
	File Introduced in: 1.0.0
	Last Updated: 2026-02-06
	Author: LAUREHTE
]]
return {
	mod_title = {
		en = "{#color(255,80,80)}\xEE\x83\x89 Quick Leave \xEE\x83\x89{#reset()}",
	},
	mod_name = {
		en = "{#color(255,80,80)}\xEE\x83\x89 Quick Leave \xEE\x83\x89{#reset()}",
	},
	mod_description = {
		en = "{#color(255,110,110)}Release 1.0.0{#reset()} | Author: LAUREHTE\n{#color(255,130,130)}Shows a leave button during intro, victory, and defeat cutscenes so you can exit immediately.{#reset()}",
	},
	loc_quick_leave_button = {
		en = "Leave Mission",
	},
	show_in_intro = {
		en = "Show button in intro cutscenes",
	},
	show_in_intro_description = {
		en = "Displays the Quick Leave button during mission intro cutscenes.",
	},
	show_in_outro = {
		en = "Show button in victory/defeat cutscenes",
	},
	show_in_outro_description = {
		en = "Displays the Quick Leave button during victory and defeat cutscenes.",
	},
	leave_party_with_quick_leave = {
		en = "Leave party too",
	},
	leave_party_with_quick_leave_description = {
		en = "If enabled, Quick Leave uses normal mission leave (also leaves party). If disabled, it uses stay-in-party mission leave.",
	},
	use_safe_button_template = {
		en = "Use safe button style",
	},
	use_safe_button_template_description = {
		en = "Uses a simple material-free button style. Enable this if the default button material fails to load.",
	},
	debug_enabled = {
		en = "Debug mode",
	},
	debug_enabled_description = {
		en = "Prints QuickLeave debug messages to chat/log.",
	},
	quick_leave_hotkey = {
		en = "Quick leave hotkey",
	},
	quick_leave_hotkey_description = {
		en = "Press to leave immediately at any time.",
	},
}
