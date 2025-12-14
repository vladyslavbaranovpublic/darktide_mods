local Unit = rawget(_G, "Unit")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local Vector3Box = rawget(_G, "Vector3Box")
local QuaternionBox = rawget(_G, "QuaternionBox")

local function vec3_to_array(value)
    if Vector3 and value then
        return { Vector3.x(value), Vector3.y(value), Vector3.z(value) }
    end
    if type(value) == "table" then
        return { value[1] or 0, value[2] or 0, value[3] or 0 }
    end
    return { 0, 0, 0 }
end

local function store_vec3(box, value)
    if not value then
        return box
    end
    if Vector3Box then
        if box and box.store then
            local ok = pcall(box.store, box, value)
            if ok then
                return box
            end
        end
        return Vector3Box(value)
    end
    return value
end

local function unbox_vec3(box)
    if Vector3Box and box and box.unbox then
        local ok, value = pcall(box.unbox, box)
        if ok then
            return value
        end
        return nil
    end
    return box
end

local function store_quat(box, value)
    if not value then
        return box
    end
    if QuaternionBox then
        if box and box.store then
            local ok = pcall(box.store, box, value)
            if ok then
                return box
            end
        end
        return QuaternionBox(value)
    end
    return value
end

local function unbox_quat(box)
    if QuaternionBox and box and box.unbox then
        local ok, value = pcall(box.unbox, box)
        if ok then
            return value
        end
        return nil
    end
    return box
end

local function default_forward(rotation)
    if Quaternion and rotation and Quaternion.forward then
        local ok, forward = pcall(Quaternion.forward, rotation)
        if ok and forward then
            return forward
        end
    end
    if Vector3 and Vector3.forward then
        return Vector3.forward()
    end
    return Vector3 and Vector3(0, 0, 1) or { 0, 0, 1 }
end

local PoseTracker = {}
PoseTracker.__index = PoseTracker

function PoseTracker.new(options)
    local tracker = {
        height_offset = options and options.height_offset or 0,
        pose_box = nil,
        rotation_box = nil,
        forward_box = nil,
        anchor_box = nil,
    }
    return setmetatable(tracker, PoseTracker)
end

function PoseTracker:reset()
    self.pose_box = nil
    self.rotation_box = nil
    self.forward_box = nil
    self.anchor_box = nil
end

local function elevated_position(tracker, anchor)
    if not Vector3 then
        return anchor
    end
    local value = anchor
    if tracker.height_offset and tracker.height_offset ~= 0 then
        value = anchor + Vector3(0, 0, tracker.height_offset)
    end
    return value
end

function PoseTracker:set_manual(position, forward, rotation)
    if not position then
        return false
    end

    local pose = elevated_position(self, position)
    self.anchor_box = store_vec3(self.anchor_box, position)
    self.pose_box = store_vec3(self.pose_box, pose)
    self.rotation_box = store_quat(self.rotation_box, rotation)
    self.forward_box = store_vec3(self.forward_box, forward or default_forward(rotation))
    return true
end

function PoseTracker:sample_unit(unit)
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return false
    end

    local ok_pos, anchor = pcall(Unit.world_position, unit, 1)
    local ok_rot, rotation = pcall(Unit.world_rotation, unit, 1)
    if not ok_pos or not ok_rot or not anchor or not rotation then
        return false
    end

    local forward = default_forward(rotation)
    return self:set_manual(anchor, forward, rotation)
end

function PoseTracker:source_payload()
    local position = unbox_vec3(self.pose_box)
    if not position then
        return nil
    end

    local rotation = unbox_quat(self.rotation_box)
    local forward = unbox_vec3(self.forward_box) or default_forward(rotation)

    local source = {
        position = vec3_to_array(position),
        forward = vec3_to_array(forward),
        velocity = { 0, 0, 0 },
    }

    return source, position, rotation
end

return {
    new = PoseTracker.new,
}
--[[
    File: core/pose_tracker.lua
    Description: Lightweight helper for sampling unit/world poses and converting them
    into MiniAudio-compatible source payloads for emitters.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
]]
