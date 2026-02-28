--[[
    File: runtime.lua
    Description: Lazy runtime API reference resolver for engine globals.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Runtime = {
	refs = {
		LineObject = nil,
		World = nil,
		Gui = nil,
		Vector3 = nil,
		Vector3Box = nil,
		Quaternion = nil,
		Matrix4x4 = nil,
		Unit = nil,
		Color = nil,
	},
}

function Runtime.resolve()
	local refs = Runtime.refs
	if not refs.LineObject then
		refs.LineObject = rawget(_G, "LineObject")
	end
	if not refs.World then
		refs.World = rawget(_G, "World")
	end
	if not refs.Gui then
		refs.Gui = rawget(_G, "Gui")
	end
	if not refs.Vector3 then
		refs.Vector3 = rawget(_G, "Vector3")
	end
	if not refs.Vector3Box then
		refs.Vector3Box = rawget(_G, "Vector3Box")
	end
	if not refs.Quaternion then
		refs.Quaternion = rawget(_G, "Quaternion")
	end
	if not refs.Matrix4x4 then
		refs.Matrix4x4 = rawget(_G, "Matrix4x4")
	end
	if not refs.Unit then
		refs.Unit = rawget(_G, "Unit")
	end
	if not refs.Color then
		refs.Color = rawget(_G, "Color")
	end
	return refs
end

return Runtime
