--[[
    File: debug_visuals/sphere.lua
    Description: Debug visual for rendering spheres in MiniAudioAddon.
    Overall Release Version: 1.0.2
    File Version: 1.0.0
]]
local Managers = rawget(_G, "Managers")
local Vector3 = rawget(_G, "Vector3")
local LineObject = rawget(_G, "LineObject")
local World = rawget(_G, "World")
local Color = rawget(_G, "Color")
local Sphere = {}

-- Required modules (will be injected via init)
local Utils = nil

-- Shared state for sphere rendering (single LineObject for all spheres)
local sphere_renderer = {
    line_object = nil,
    line_world = nil,
    spheres = {}  -- List of spheres to draw: {position, color, radius}
}

--[[
    Initialize the Sphere module with required dependencies
    
    Args:
        utils: MiniAudioUtils module
]]
function Sphere.init(dependencies)
    Utils = dependencies.Utils
end

--[[
    HELPER: Draw visual sphere marker at position
    
    Uses engine LineObject API to draw a wireframe sphere in 3D space.
    This lets you SEE where the audio emitter is positioned. Based on the
    same technique used by MiniAudioAddon and ElevatorMusic for debugging.
    
    Args:
        orb_state: Table with {line_object, line_world} or nil
        position: Vector3 world position to draw sphere
        color_rgb: Optional table {r, g, b} with values 0-255
        radius: Optional float radius in meters (default 0.5)
    Returns: Updated orb_state table
]]
function Sphere.add(sphere_id, position, color_rgb, radius)
    if not position then
        return
    end
    
    -- Store sphere data for batch rendering
    sphere_renderer.spheres[sphere_id] = {
        position = position,
        color = color_rgb or {80, 200, 255},
        radius = radius or 0.5
    }
end


--[[
    HELPER: Remove sphere from rendering
]]
function Sphere.remove(sphere_id)
    sphere_renderer.spheres[sphere_id] = nil
end

--[[
    Conditionally add or remove a sphere based on enabled state
    
    Convenience function that either adds or removes a sphere based on a boolean condition.
    Simplifies common pattern of toggling debug visualization.
    
    Args:
        sphere_id: Unique identifier for the sphere
        enabled: Boolean - if true, adds sphere; if false, removes it
        position: Vector3 world position (required if enabled=true)
        color_rgb: {r, g, b} color table (required if enabled=true)
        radius: Number radius in meters (optional, default 0.5 if enabled=true)
    
    Example:
        Sphere.toggle("orb2", show_sphere, current_position, {80, 200, 255}, 0.5)
]]
function Sphere.toggle(sphere_id, enabled, position, color_rgb, radius)
    if enabled and position then
        Sphere.add(sphere_id, position, color_rgb, radius or 0.5)
    else
        Sphere.remove(sphere_id)
    end
end


--[[
    HELPER: Render all registered spheres
    
    Call this once per frame to draw all spheres together. Sorts spheres by distance
    from camera and draws back-to-front for proper visual occlusion (painter's algorithm).
]]
function Sphere.render_all()
    if not LineObject or not World or not Color then
        return
    end
    
    -- Get level world
    local world = Managers and Managers.world and Managers.world:world("level_world")
    if not world then
        return
    end
    
    -- Create line object if needed or world changed
    if not sphere_renderer.line_object or sphere_renderer.line_world ~= world then
        local ok, line_obj = pcall(World.create_line_object, world)
        if ok and line_obj then
            sphere_renderer.line_object = line_obj
            sphere_renderer.line_world = world
        else
            return
        end
    end
    
    local line_object = sphere_renderer.line_object
    
    -- Reset line object
    local ok = pcall(LineObject.reset, line_object)
    if not ok then
        sphere_renderer.line_object = nil
        sphere_renderer.line_world = nil
        return
    end
    
    -- Get camera position for distance sorting
    local camera_pos = nil
    local pose = Utils and Utils.get_player_pose()
    if pose then
        camera_pos = pose.position
    end
    
    -- Build sorted list of spheres (farthest to nearest for back-to-front rendering)
    local sphere_list = {}
    for sphere_id, sphere_data in pairs(sphere_renderer.spheres) do
        local distance = 0
        if camera_pos and sphere_data.position then
            local dx = Vector3.x(sphere_data.position) - Vector3.x(camera_pos)
            local dy = Vector3.y(sphere_data.position) - Vector3.y(camera_pos)
            local dz = Vector3.z(sphere_data.position) - Vector3.z(camera_pos)
            distance = math.sqrt(dx*dx + dy*dy + dz*dz)
        end
        sphere_list[#sphere_list + 1] = {
            id = sphere_id,
            data = sphere_data,
            distance = distance
        }
    end
    
    -- Sort by distance (farthest first for proper occlusion)
    table.sort(sphere_list, function(a, b) return a.distance > b.distance end)
    
    -- Draw all spheres in sorted order (back to front)
    for _, sphere_entry in ipairs(sphere_list) do
        local sphere_data = sphere_entry.data
        local rgb = sphere_data.color
        local sphere_color = Color(255, rgb[1], rgb[2], rgb[3])
        LineObject.add_sphere(line_object, sphere_color, sphere_data.position, sphere_data.radius, 32, 24)
    end
    
    -- Dispatch once for all spheres
    LineObject.dispatch(world, line_object)
end

-- ============================================================================
-- MARKER SYSTEM (Extended functionality for debug markers with labels/arrows)
-- ============================================================================

-- Marker state storage: {marker_id -> {position, rotation, label, text_category, text_color}}
local marker_states = {}

--[[
    Destroy spawned unit (for physical debug markers)
    
    Cleans up debug units spawned into the world for visualization.
    
    Args:
        unit: Unit handle to destroy
]]
function Sphere.destroy_unit(unit)
    if not unit then
        return
    end

    local Unit = rawget(_G, "Unit")
    local spawner = Managers and Managers.state and Managers.state.unit_spawner
    if spawner and spawner.mark_for_deletion then
        local ok = pcall(spawner.mark_for_deletion, spawner, unit)
        if ok then
            return
        end
    end

    local world = Managers and Managers.world and Managers.world:world("level_world")
    if world and World and Unit and Unit.alive and Unit.alive(unit) then
        pcall(World.destroy_unit, world, unit)
    end
end

--[[
    Spawn debug unit at position (for physical debug markers)
    
    Creates a 3D unit in the world for visualization (e.g., cube markers).
    
    Args:
        unit_name: String name of unit to spawn (e.g., "core/units/cube")
        position: Vector3 spawn position
        rotation: Quaternion spawn rotation
    Returns: Unit handle or nil
]]
function Sphere.spawn_unit(unit_name, position, rotation)
    if not unit_name then
        return nil
    end

    local spawner = Managers and Managers.state and Managers.state.unit_spawner
    if spawner and spawner.spawn_unit then
        local ok, unit = pcall(spawner.spawn_unit, spawner, unit_name, position, rotation)
        if ok and unit then
            return unit
        end
    end

    if not Managers or not Managers.world or not World then
        return nil
    end

    local world = Managers.world:world("level_world")
    if not world then
        return nil
    end

    local ok, unit = pcall(World.spawn_unit_ex, world, unit_name, nil, position, rotation)
    if ok then
        return unit
    end

    return nil
end

--[[
    Draw debug marker with sphere, direction arrow, and text label
    
    Advanced marker that shows position (sphere), orientation (arrow), and label.
    Reuses existing sphere rendering infrastructure for efficiency.
    
    Args:
        marker_id: Unique identifier for this marker
        position: Vector3 world position
        rotation: Optional Quaternion for direction arrow
        label: Optional string text label (default "MiniAudio Marker")
        text_category: Optional string category for debug text system
        text_color: Optional Vector3 color (r, g, b) range 0-255
        sphere_color_rgb: Optional table {r, g, b} for sphere (default {255, 200, 80})
        sphere_radius: Optional float radius (default 0.3)
]]
function Sphere.draw_marker(marker_id, position, rotation, label, text_category, text_color, sphere_color_rgb, sphere_radius)
    if not position then
        Sphere.clear_marker(marker_id)
        return
    end

    -- Store marker state
    marker_states[marker_id] = {
        position = position,
        rotation = rotation,
        label = label or "MiniAudio Marker",
        text_category = text_category,
        text_color = text_color or (Vector3 and Vector3(255, 220, 80) or nil),
        sphere_color = sphere_color_rgb or {255, 200, 80},
        sphere_radius = sphere_radius or 0.3
    }

    -- Add sphere using existing system
    Sphere.add(marker_id, position, sphere_color_rgb or {255, 200, 80}, sphere_radius or 0.3)

    -- Draw direction arrow if rotation provided
    if rotation and LineObject and Vector3 and Vector3.normalize then
        local world = Managers and Managers.world and Managers.world:world("level_world")
        if not world then
            return
        end

        -- Create separate line object for arrows (rendered after spheres)
        local arrow_line = nil
        local ok, line_obj = pcall(World.create_line_object, world)
        if ok and line_obj then
            arrow_line = line_obj
        else
            return
        end

        -- Draw direction arrow
        local forward = Utils.safe_forward(rotation)
        local up = Utils.safe_up(rotation)
        local right = Vector3.normalize(Vector3.cross(forward, up))
        local tip = position + forward * 0.6
        local left_tip = tip - right * 0.15
        local right_tip = tip + right * 0.15
        
        local arrow_color = Color and Color(255, 255, 140, 40) or nil
        if arrow_color then
            LineObject.add_line(arrow_line, arrow_color, position, tip)
            LineObject.add_line(arrow_line, arrow_color, tip, left_tip)
            LineObject.add_line(arrow_line, arrow_color, tip, right_tip)
            LineObject.dispatch(world, arrow_line)
        end
    end

    -- Draw text label if debug text system available
    local debug_text = Managers and Managers.state and Managers.state.debug_text
    if debug_text and debug_text.output_world_text and Vector3 and text_category then
        local label_position = position + Vector3(0, 0, 0.45)
        debug_text:output_world_text(label, 0.08, label_position, 0.12, text_category, text_color or Vector3(255, 220, 80))
    end
end

--[[
    Clear/remove debug marker
    
    Removes marker sphere, arrow, and text label from rendering.
    
    Args:
        marker_id: Unique identifier for marker to remove
]]
function Sphere.clear_marker(marker_id)
    -- Remove from marker state
    marker_states[marker_id] = nil
    
    -- Remove sphere
    Sphere.remove(marker_id)
    
    -- Clear debug text if present
    local marker = marker_states[marker_id]
    if marker and marker.text_category then
        local debug_text = Managers and Managers.state and Managers.state.debug_text
        if debug_text and debug_text.clear_world_text then
            debug_text:clear_world_text(marker.text_category)
        end
    end
end

return Sphere
