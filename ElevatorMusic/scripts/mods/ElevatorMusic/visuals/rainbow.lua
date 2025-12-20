--[[
    File: visuals/rainbow.lua
    Description: ElevatorMusic-exclusive visualizer that draws line-object halos and
    animated flashlight emitters around each elevator speaker for debugging flair.
    Overall Release Version: 0.6
    File Version: 0.5.0
]]
local Managers = rawget(_G, "Managers")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local LineObject = rawget(_G, "LineObject")
local World = rawget(_G, "World")
local Unit = rawget(_G, "Unit")
local Light = rawget(_G, "Light")
local Color = rawget(_G, "Color")

local Rainbow = {}
local entries = {}
local TWO_PI = math.pi * 2
local LIGHT_UNIT = "content/weapons/player/attachments/flashlights/flashlight_01/flashlight_01"
local LIGHT_SUPPORT = Unit and Light and Vector3 and Quaternion and World and World.spawn_unit_ex
local MAX_TILT_RAD = math.rad(70)
local MAX_TILT_TAN = math.tan(MAX_TILT_RAD)

local ENABLE_LIGHTS = true
local function safe_line_reset(entry)
    if not entry or not entry.line_object or not LineObject then
        return false
    end
    local ok = pcall(LineObject.reset, entry.line_object)
    if not ok then
        entry.line_object = nil
        return false
    end
    return true
end

local function safe_line_dispatch(entry)
    if not entry or not entry.line_object or not entry.world or not LineObject then
        return false
    end
    local ok = pcall(LineObject.dispatch, entry.world, entry.line_object)
    if not ok then
        entry.line_object = nil
        return false
    end
    return true
end

local function safe_line_sphere(entry, color, position, radius)
    if not entry or not entry.line_object or not LineObject then
        return false
    end
    local ok = pcall(LineObject.add_sphere, entry.line_object, color, position, radius, 32, 24)
    if not ok then
        entry.line_object = nil
        return false
    end
    return true
end

local function hue_to_rgb(h)
    h = h % 1
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local q = 1 - f

    if i % 6 == 0 then
        r, g, b = 1, f, 0
    elseif i == 1 then
        r, g, b = q, 1, 0
    elseif i == 2 then
        r, g, b = 0, 1, f
    elseif i == 3 then
        r, g, b = 0, q, 1
    elseif i == 4 then
        r, g, b = f, 0, 1
    else
        r, g, b = 1, 0, q
    end

    return r, g, b
end

local function world_handle()
    if not Managers or not Managers.world then
        return nil
    end
    return Managers.world:world("level_world")
end

local function valid_entry(entry)
    return entry and entry.world and entry.line_object
end

local function default_options(options)
    options = options or {}
    return {
        speed = options.speed or 1,
        jitter = options.jitter or 0,
        radius = options.radius or 1.0,
        height = options.height or 2.0,
        light_count = math.max(2, math.floor(options.light_count or 16)),
        intensity = options.intensity or 40,
        spin_speed = options.spin_speed or 1.5,
        show_core = options.show_core ~= false,
        orbit_radius = math.max(0, options.orbit_radius or 0),
        orbit_speed = options.orbit_speed or 0,
        light_orbit_variance = math.max(0, options.light_orbit_variance or 0),
        light_vertical_variance = math.max(0, options.light_vertical_variance or 0),
        loop_speed = math.max(0, options.loop_speed or 0),
    }
end

local function apply_light_properties(entry)
    if not entry or not entry.lights then
        return
    end

    for _, light_data in ipairs(entry.lights) do
        local light = light_data.light
        if light then
            Light.set_enabled(light, true)
            Light.set_casts_shadows(light, true)
            Light.set_intensity(light, entry.options.intensity)
            Light.set_spot_angle_start(light, 1 / 180 * math.pi)
            Light.set_spot_angle_end(light, 65 / 180 * math.pi)
            Light.set_falloff_start(light, 0)
            Light.set_falloff_end(light, entry.options.radius * 10)
            Light.set_volumetric_intensity(light, 0.25)
        end
    end
end

local function destroy_lights(entry)
    if not entry or not entry.lights then
        return
    end

    for _, light_data in ipairs(entry.lights) do
        if light_data.unit and entry.world and World and World.destroy_unit then
            pcall(World.destroy_unit, entry.world, light_data.unit)
        end
    end

    entry.lights = nil
end

local function ensure_lights(entry)
    if not ENABLE_LIGHTS or not entry or entry.lights or not LIGHT_SUPPORT then
        return
    end

    local world = entry.world
    if not world then
        return
    end

    entry.lights = {}
    local count = entry.options.light_count

    for index = 1, count do
        local ok, unit = pcall(World.spawn_unit_ex, world, LIGHT_UNIT, nil, entry.position or Vector3(0, 0, 0), Quaternion.identity())
        if ok and unit then
            local light = Unit.light(unit, 1)
            if light then
                entry.lights[index] = {
                    unit = unit,
                    light = light,
                    angle = math.random() * TWO_PI,  -- Random starting angle
                    spin = math.random() * TWO_PI,   -- Random initial spin
                    speed_mult = 0.5 + math.random() * 1.5,  -- Circular speed multiplier
                    radius_mult = 0.7 + math.random() * 0.6, -- Base radius multiplier
                    height_offset = (math.random() - 0.5) * 0.8, -- Static height offset
                    radial_phase = math.random() * TWO_PI,
                    vertical_phase = math.random() * TWO_PI,
                    loop_speed_mult = 0.5 + math.random() * 1.5,
                }
            else
                World.destroy_unit(world, unit)
            end
        end
    end

    apply_light_properties(entry)
end

local function update_center_position(entry, dt)
    if not entry or not entry.base_position then
        return nil
    end

    local opts = entry.options or default_options()
    local radius = opts.orbit_radius or 0
    local speed = opts.orbit_speed or 0
    dt = dt or 0

    if radius > 0 and speed ~= 0 and Vector3 then
        entry.orbit_phase = (entry.orbit_phase or math.random() * TWO_PI) + dt * speed
        local angle = entry.orbit_phase
        local offset = Vector3(radius * math.cos(angle), radius * math.sin(angle), 0)
        entry.position = entry.base_position + offset
    else
        entry.position = entry.base_position
    end

    return entry.position
end

local function update_light_positions(entry, dt)
    if not entry or not entry.lights or not Vector3 or not Quaternion then
        return
    end

    local center = entry.position or Vector3(0, 0, 0)
    local radius = entry.options.radius
    local height = entry.options.height
    local spin_speed = entry.options.spin_speed or 0
    local orbit_variance = entry.options.light_orbit_variance or 0
    local vertical_variance = entry.options.light_vertical_variance or 0
    local loop_speed = entry.options.loop_speed or 0

    for _, data in ipairs(entry.lights) do
        if data.unit and Unit.alive and Unit.alive(data.unit) then
            -- Each light has its own speed and orbit
            data.angle = (data.angle + dt * entry.options.speed * (data.speed_mult or 1)) % TWO_PI
            local loop_phase_speed = dt * loop_speed * (data.loop_speed_mult or 1)
            if loop_speed > 0 then
                data.radial_phase = ((data.radial_phase or 0) + loop_phase_speed) % TWO_PI
                data.vertical_phase = ((data.vertical_phase or 0) + loop_phase_speed * 1.2) % TWO_PI
            end

            local radial_scale = 1
            if orbit_variance > 0 then
                local s = math.sin(data.radial_phase or 0)
                radial_scale = math.max(0.1, 1 + s * orbit_variance)
            end

            local vertical_offset = data.height_offset or 0
            if vertical_variance > 0 then
                vertical_offset = vertical_offset + math.sin(data.vertical_phase or 0) * vertical_variance
            end

            local light_radius = radius * (data.radius_mult or 1) * radial_scale
            local light_height = height + vertical_offset
            local offset = Vector3(light_radius * math.cos(data.angle), light_radius * math.sin(data.angle), light_height)
            local position = center + offset
            Unit.set_local_position(data.unit, 1, position)

            local direction = center - position
            if Vector3 and Vector3.x then
                local dx = Vector3.x(direction)
                local dy = Vector3.y(direction)
                local horizontal_len = math.sqrt(dx * dx + dy * dy)
                if horizontal_len > 0 then
                    local vertical = Vector3.z(direction)
                    local abs_vertical = math.abs(vertical)
                    local min_vertical = horizontal_len / MAX_TILT_TAN
                    if abs_vertical < min_vertical then
                        local sign = vertical >= 0 and 1 or -1
                        if sign == 0 then
                            sign = -1
                        end
                        vertical = min_vertical * sign
                        direction = Vector3(dx, dy, vertical)
                    end
                end
            end
            local rotation = Quaternion.look(direction, Vector3.up())
            if spin_speed ~= 0 then
                data.spin = (data.spin or 0) + dt * spin_speed
                local axis = Vector3.normalize(direction)
                if axis then
                    local roll = Quaternion(axis, data.spin)
                    rotation = Quaternion.multiply(rotation, roll)
                end
            end
            Unit.set_local_rotation(data.unit, 1, rotation)

            if data.light then
                local hue = (entry.phase + data.angle / TWO_PI) % 1
                local r, g, b = hue_to_rgb(hue)
                Light.set_color_filter(data.light, Vector3(r, g, b))
            end
        end
    end
end

function Rainbow.spawn(id, options)
    if not id then
        return
    end

    local entry = entries[id]
    if entry then
        entry.options = default_options(options or entry.options)
        return entry
    end

    local world = world_handle()
    if not world or not World or not LineObject or not World.create_line_object then
        return nil
    end

    local ok, line_object = pcall(World.create_line_object, world)
    if not ok or not line_object then
        return nil
    end

    entry = {
        world = world,
        line_object = line_object,
        options = default_options(options),
        phase = math.random(),
        position = nil,
        base_position = nil,
        orbit_phase = math.random() * TWO_PI,
    }
    ensure_lights(entry)
    entries[id] = entry
    return entry
end

function Rainbow.configure(id, options)
    local entry = entries[id]
    if entry then
        local previous = entry.options
        entry.options = default_options(options or entry.options)
        if not entry.lights or not previous or previous.light_count ~= entry.options.light_count then
            destroy_lights(entry)
            ensure_lights(entry)
        else
            apply_light_properties(entry)
        end
    end
end

function Rainbow.set_position(id, position)
    local entry = entries[id]
    if entry then
        entry.base_position = position
        entry.position = position
        entry.orbit_phase = entry.orbit_phase or math.random() * TWO_PI
        update_center_position(entry, 0)
        if entry.lights then
            update_light_positions(entry, 0)
        end
    end
end

function Rainbow.remove(id)
    local entry = entries[id]
    if not entry then
        return
    end
    if entry.line_object and entry.world and LineObject then
        safe_line_reset(entry)
        safe_line_dispatch(entry)
    end
    destroy_lights(entry)
    entries[id] = nil
end

function Rainbow.remove_all()
    for id in pairs(entries) do
        Rainbow.remove(id)
    end
end

function Rainbow.update(dt)
    if not dt or not LineObject or not Color then
        return
    end

    for id, entry in pairs(entries) do
        if not valid_entry(entry) or not entry.base_position then
            Rainbow.remove(id)
        else
            local opts = entry.options or default_options()
            update_center_position(entry, dt)

            if not entry.position then
                Rainbow.remove(id)
                goto continue
            end

            entry.phase = (entry.phase + dt * opts.speed + (math.random() - 0.5) * opts.jitter * dt) % 1
            local r, g, b = hue_to_rgb(entry.phase)
            local color = Color(math.floor(200 + 55 * math.random()), math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
            local radius = opts.radius or 0.55

            if not safe_line_reset(entry) then
                goto continue
            end
            if opts.show_core then
                if not safe_line_sphere(entry, color, entry.position, radius) then
                    goto continue
                end
            end
            safe_line_dispatch(entry)
            
            if ENABLE_LIGHTS then
                ensure_lights(entry)
                update_light_positions(entry, dt)
            elseif entry.lights then
                destroy_lights(entry)
            end
        end
        ::continue::
    end
end

return Rainbow
