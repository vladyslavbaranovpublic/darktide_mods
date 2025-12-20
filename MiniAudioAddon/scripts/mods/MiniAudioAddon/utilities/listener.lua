--[[
    File: utilities/listener.lua
    Description: Listener pose and payload building for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local Listener = {}

-- Dependencies
local mod = nil
local Utils = nil

-- Engine globals
local Managers = nil
local Vector3 = nil

function Listener.init(dependencies)
    mod = dependencies.mod
    Utils = dependencies.Utils
    Managers = rawget(_G, "Managers")
    Vector3 = rawget(_G, "Vector3")
end

-- ============================================================================
-- LISTENER POSE
-- ============================================================================

function Listener.get_pose()
    if not Managers or not Managers.state or not Managers.state.camera then
        return nil, nil
    end

    local camera_manager = Managers.state.camera
    if type(camera_manager) ~= "table" and type(camera_manager) ~= "userdata" then
        return nil, nil
    end

    local viewport_name_fn = camera_manager.viewport_name
    if type(viewport_name_fn) ~= "function" then
        return nil, nil
    end

    local viewport_name = viewport_name_fn(camera_manager)
    if not viewport_name or viewport_name == "" then
        return nil, nil
    end

    local camera_viewport_fn = camera_manager.camera_viewport
    if type(camera_viewport_fn) ~= "function" then
        return nil, nil
    end

    local viewport = camera_viewport_fn(camera_manager, viewport_name)
    if not viewport or not viewport.world or not viewport.camera then
        return nil, nil
    end

    local camera_unit = viewport.camera
    local camera_pos = Utils and Utils.safe_unit_local_position and Utils.safe_unit_local_position(camera_unit, 1)
    local camera_rot = Utils and Utils.safe_unit_local_rotation and Utils.safe_unit_local_rotation(camera_unit, 1)

    if not camera_pos or not camera_rot then
        return nil, nil
    end

    return camera_pos, camera_rot
end

-- ============================================================================
-- LISTENER PAYLOAD
-- ============================================================================

function Listener.build_payload()
    local pose_pos, pose_rot = Listener.get_pose()
    if not pose_pos or not pose_rot then
        return nil
    end

    if not Utils then
        return nil
    end

    local forward = Utils.safe_forward and Utils.safe_forward(pose_rot)
    if not forward then
        return nil
    end

    local velocity = Vector3 and Vector3(0, 0, 0) or {0, 0, 0}

    return {
        position = Utils.vec3_to_array and Utils.vec3_to_array(pose_pos) or pose_pos,
        forward = Utils.vec3_to_array and Utils.vec3_to_array(forward) or forward,
        velocity = Utils.vec3_to_array and Utils.vec3_to_array(velocity) or velocity,
    }
end

-- ============================================================================
-- LISTENER CONTEXT (with validation)
-- ============================================================================

function Listener.get_context()
    local listener = Listener.build_payload()
    if not listener then
        return nil
    end

    return {
        listener = listener,
        valid = true,
    }
end

-- ============================================================================
-- ENSURE LISTENER (with fallback)
-- ============================================================================

function Listener.ensure(provided_listener)
    if provided_listener then
        return provided_listener
    end
    
    return Listener.build_payload()
end

return Listener
