--[[
    File: constants.lua
    Description: Shared slot constants, type settings, and default colors.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local SlotTypeSettings = require("scripts/settings/slot/slot_type_settings")

local SLOT_TYPES = {}
for slot_type, _ in pairs(SlotTypeSettings) do
	SLOT_TYPES[#SLOT_TYPES + 1] = slot_type
end

table.sort(SLOT_TYPES, function(a, b)
	local pa = SlotTypeSettings[a] and SlotTypeSettings[a].priority or 0
	local pb = SlotTypeSettings[b] and SlotTypeSettings[b].priority or 0
	if pa == pb then
		return a < b
	end
	return pa < pb
end)

local COLORS = {
	origin = { 230, 230, 230 },
	free = { 120, 255, 140 },
	occupied = { 255, 170, 70 },
	moving = { 255, 220, 90 },
	released = { 255, 230, 120 },
	blocked = { 150, 150, 150 },
	queue = { 90, 160, 255 },
	queue_next = { 255, 110, 255 },
	ghost = { 140, 200, 255 },
	user_line = { 210, 210, 210 },
}

local DEFAULT_SLOT_COLORS = {
	normal = {
		free = { 120, 255, 140 },
		occupied = { 255, 170, 70 },
		moving = { 255, 220, 90 },
	},
	medium = {
		free = { 90, 160, 255 },
		occupied = { 255, 110, 255 },
		moving = { 160, 110, 255 },
	},
	large = {
		free = { 255, 200, 90 },
		occupied = { 255, 80, 80 },
		moving = { 255, 99, 71 },
	},
}

return {
	SlotTypeSettings = SlotTypeSettings,
	SLOT_TYPES = SLOT_TYPES,
	COLORS = COLORS,
	DEFAULT_SLOT_COLORS = DEFAULT_SLOT_COLORS,
}
