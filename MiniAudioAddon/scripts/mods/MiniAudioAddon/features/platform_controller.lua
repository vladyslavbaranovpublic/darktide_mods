--[[
    File: features/platform_controller.lua
    Description: Shared platform emitter controller for mods that need idle/activation behaviour.
]]

local PlatformController = {}
PlatformController.__index = PlatformController

local Utils = nil
local EmitterManager = nil
local Sphere = nil
local PlaylistManager = nil
local ClientManager = nil
local MiniAudioMod = nil
local IOUtils = nil
local Unit = rawget(_G, "Unit")
local Vector3 = rawget(_G, "Vector3")
local Vector3Box = rawget(_G, "Vector3Box")

local function finite(value, default)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return default or 0
    end
    return value
end

local function clamp(value, min_value, max_value)
    if Utils and Utils.clamp then
        return Utils.clamp(value, min_value, max_value)
    end
    if min_value > max_value then
        min_value, max_value = max_value, min_value
    end
    return math.max(min_value, math.min(max_value, value))
end

local function clone_vector(vec)
    if not Vector3 or not vec then
        return vec
    end
    return Vector3(Vector3.x(vec), Vector3.y(vec), Vector3.z(vec))
end

function PlatformController.init(dependencies)
    Utils = dependencies.Utils
    EmitterManager = dependencies.EmitterManager
    Sphere = dependencies.Sphere
    PlaylistManager = dependencies.PlaylistManager
    ClientManager = dependencies.ClientManager
    MiniAudioMod = dependencies.MiniAudioMod
    IOUtils = dependencies.IOUtils
end

function PlatformController.new(config)
    local controller = setmetatable({
        mod = config.mod,
        playlist_id = config.playlist_id,
        get_setting = config.get_setting or function() return nil end,
        markers_setting = config.markers_setting,
        random_setting = config.random_setting,
        identifier = config.identifier or config.mod:get_name(),
        height_offset = config.height_offset or 3.0,
        idle_volume_scale = config.idle_volume_scale or 0.55,
        distance_scale = config.distance_scale or 0.8,
        fade_setting = config.fade_setting,
        activation_linger_setting = config.activation_linger_setting,
        idle_full_setting = config.idle_full_setting,
        idle_radius_setting = config.idle_radius_setting,
        idle_after_activation_setting = config.idle_after_activation_setting,
        idle_enabled_setting = config.idle_enabled_setting,
        play_activation_setting = config.play_activation_setting,
        sphere_color = config.sphere_color or {255, 220, 80},
        debug_setting = config.debug_setting or "elevatormusic_debug",
        state = {
            platforms = {},
            sequence = 0,
        },
    }, PlatformController)

    return controller
end

function PlatformController:_set_client_active(active)
    if ClientManager and ClientManager.set_active then
        ClientManager.set_active(self.identifier, active)
    elseif MiniAudioMod and MiniAudioMod.set_client_active then
        MiniAudioMod:set_client_active(self.identifier, active)
    end
end

function PlatformController:_idle_settings()
    local radius = clamp(finite(self.get_setting(self.idle_radius_setting) or 10, 10), 2, 40)
    local full = clamp(finite(self.get_setting(self.idle_full_setting) or 4, 4), 0.5, radius - 0.2)
    local hysteresis = math.max(0.5, radius * 0.2)
    return radius, radius + hysteresis, full
end

function PlatformController:_scaled_distance(value)
    if not value then
        return value
    end
    return value * self.distance_scale
end

function PlatformController:_base_volume()
    local percent = clamp(finite(self.get_setting("elevatormusic_volume_percent") or 100, 100), 5, 300)
    return clamp(percent / 100, 0.05, 3.0)
end

function PlatformController:_idle_volume(distance, radius, full)
    radius = self:_scaled_distance(radius or select(1, self:_idle_settings()))
    full = self:_scaled_distance(full or select(3, self:_idle_settings()))
    local scale = 1.0
    if distance and distance > full then
        local span = math.max(radius - full, 0.001)
        scale = clamp(1 - (distance - full) / span, 0, 1)
    end
    return self:_base_volume() * self.idle_volume_scale * scale
end

function PlatformController:_activation_volume(distance, radius, full)
    radius = self:_scaled_distance(radius or select(1, self:_idle_settings()))
    full = self:_scaled_distance(full or select(3, self:_idle_settings()))
    local limit = clamp(radius * 1.5, full + 0.5, math.max(radius * 2, full + 0.5))
    if not distance then
        return self:_base_volume()
    end
    if distance <= full then
        return self:_base_volume()
    end
    if distance >= limit then
        return 0
    end
    local frac = (distance - full) / (limit - full)
    return self:_base_volume() * (1 - frac)
end

function PlatformController:_volume_for_mode(mode, distance, radius, full)
    if mode == "activation" then
        return self:_activation_volume(distance, radius, full)
    end
    return self:_idle_volume(distance, radius, full)
end

function PlatformController:_build_profile(mode, radius, full)
    radius = self:_scaled_distance(radius or select(1, self:_idle_settings()))
    full = self:_scaled_distance(full or select(3, self:_idle_settings()))
    local rolloff = self.get_setting("elevatormusic_spatial_rolloff") or "linear"
    if mode == "activation" then
        local min_distance = clamp(full * 0.75, 0.5, 25)
        local max_distance = clamp(radius * 3.0, min_distance + 1, 150)
        return { min_distance = min_distance, max_distance = max_distance, rolloff = rolloff }
    end
    local min_distance = clamp(full * 0.6, 0.35, radius - 0.5)
    local max_distance = clamp(radius * 1.8, min_distance + 1, 90)
    return { min_distance = min_distance, max_distance = max_distance, rolloff = rolloff }
end

function PlatformController:_toggle_marker(entry, position, force_off)
    if not Sphere or not entry then
        return
    end

    if force_off or not self.get_setting(self.markers_setting) then
        entry.marker_position = nil
        entry.marker_position_box = nil
        Sphere.toggle(entry.key, false)
        return
    end

    local final_position = position

    if not final_position and entry.marker_position_box and entry.marker_position_box.unbox then
        local ok, stored = pcall(function() return entry.marker_position_box:unbox() end)
        if ok then
            final_position = stored
        end
    elseif not final_position and entry.marker_position then
        final_position = entry.marker_position
    end

    if not final_position and entry.unit and Unit and Unit.alive and Unit.alive(entry.unit) then
        local ok, world_pos = pcall(Unit.world_position, entry.unit, 1)
        if ok and world_pos then
            final_position = Vector3 and (world_pos + Vector3(0, 0, self.height_offset)) or world_pos
        end
    end

    if final_position then
        if Vector3Box and Vector3 then
            if entry.marker_position_box then
                entry.marker_position_box:store(final_position)
            else
                entry.marker_position_box = Vector3Box(final_position)
            end
            entry.marker_position = nil
            local ok, unboxed = pcall(function() return entry.marker_position_box:unbox() end)
            final_position = ok and unboxed or final_position
        else
            entry.marker_position_box = nil
            entry.marker_position = clone_vector(final_position)
            final_position = entry.marker_position
        end
        Sphere.toggle(entry.key, true, final_position, self.sphere_color, 0.45)
    else
        Sphere.toggle(entry.key, false)
    end
end

function PlatformController:_pick_track()
    if not PlaylistManager then
        return nil
    end
    local random = self.random_setting and self.get_setting(self.random_setting)
    local track = PlaylistManager.next(self.playlist_id, { random = random })
    if track and IOUtils and IOUtils.expand_track_path then
        local expanded = IOUtils.expand_track_path(track)
        if expanded then
            track = expanded
        end
    end
    return track
end

function PlatformController:_start_emitter(entry, mode, distance)
    if not self.get_setting("elevatormusic_enable") then
        return
    end
    if not EmitterManager then
        return
    end
    local path = self:_pick_track()
    if not path then
        return
    end

    if self.get_setting and self.get_setting(self.debug_setting) then
        local position = entry and entry.unit and Unit.world_position and Unit.world_position(entry.unit, 1)
        local prefix = string.format("[ElevatorMusic] Platform %s (%s)", tostring(entry.key), mode)
        local dist_num = distance or 0
        local vol_num = self:_base_volume()
        if volume then
            vol_num = volume
        end
        self.mod:echo("%s path=%s distance=%.2f volume=%.2f", prefix, tostring(path), dist_num, vol_num)
        if position then
            local x = position.x or position[1] or 0
            local y = position.y or position[2] or 0
            local z = position.z or position[3] or 0
            self.mod:echo("%s position=(%.1f, %.1f, %.1f)", prefix, x, y, z)
        end
    end
    local radius, _, full = self:_idle_settings()
    local volume = self:_volume_for_mode(mode, distance, radius, full)
    self.state.sequence = self.state.sequence + 1
    local emitter_id = string.format("%s_%s_%d", self.identifier, tostring(entry.key), self.state.sequence)
    local config = {
        id = emitter_id,
        audio_path = path,
        profile = self:_build_profile(mode, radius, full),
        volume = volume,
        loop = true,
        require_listener = true,
        provider_context = entry,
        position_provider = function(context)
            local unit = context and context.unit
            if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
                return nil
            end
            local position = Unit.world_position(unit, 1)
            if Vector3 then
                position = position + Vector3(0, 0, self.height_offset)
            end
            local rotation = Unit.world_rotation(unit, 1)
            return position, rotation
        end,
        payload_override = function(emitter_state)
            local ctx = emitter_state and emitter_state.provider_context
            if not ctx or not ctx.emitter then
                return { volume = 0 }
            end
            return {
                volume = ctx.emitter.current_volume or 0,
                profile = ctx.emitter.current_profile,
            }
        end,
        provider_grace = 1.5,
    }
    local created, create_err = EmitterManager.create(config)
    if not created then
        if self.mod and self.get_setting and self.get_setting(self.debug_setting) then
            self.mod:echo("[ElevatorMusic] Failed to create emitter (%s): %s", mode, tostring(create_err or "unknown error"))
        end
        return
    end
    entry.emitter = {
        id = created,
        mode = mode,
        path = path,
        current_volume = volume,
        current_profile = config.profile,
        linger_until = nil,
        linger_total = nil,
        next_update = 0,
    }
    self:_set_client_active(true)
end

function PlatformController:_stop_emitter(entry, reason)
    if not EmitterManager or not entry or not entry.emitter then
        return
    end
    local fade = Utils and Utils.clamp and Utils.clamp(finite(self.get_setting(self.fade_setting) or 1.5, 1.5), 0, 10) or 0
    EmitterManager.stop(entry.emitter.id, fade)
    entry.emitter = nil
    self:_toggle_marker(entry, nil, true)
    self:_set_client_active(false)
end

function PlatformController:_idle_allowed(distance)
    if not self.get_setting(self.idle_enabled_setting) then
        return false
    end
    if not distance then
        return false
    end
    local radius = select(1, self:_idle_settings())
    return distance <= radius
end

function PlatformController:_update_emitter(entry, distance)
    local emitter = entry and entry.emitter
    if not emitter then
        return
    end
    if emitter.next_update and emitter.next_update > Utils.realtime_now() then
        return
    end
    emitter.next_update = Utils.realtime_now() + Utils.clamp(finite(self.get_setting("elevatormusic_update_interval") or 0.1, 0.1), 0.02, 0.5)
    local radius, _, full = self:_idle_settings()
    local target_volume = self:_volume_for_mode(emitter.mode, distance, radius, full)
    if emitter.mode == "activation" and not entry.moving then
        if emitter.linger_until then
            local remaining = emitter.linger_until - Utils.realtime_now()
            if remaining <= 0 then
                emitter.linger_until = nil
                emitter.linger_total = nil
                if self.get_setting(self.idle_after_activation_setting) and self:_idle_allowed(distance) then
                    emitter.mode = "idle"
                    target_volume = self:_volume_for_mode("idle", distance, radius, full)
                else
                    self:_stop_emitter(entry, "activation_complete")
                    return
                end
            else
                local span = emitter.linger_total or 1
                target_volume = target_volume * Utils.clamp(remaining / span, 0, 1)
            end
        else
            if self.get_setting(self.idle_after_activation_setting) and self:_idle_allowed(distance) then
                emitter.mode = "idle"
                target_volume = self:_volume_for_mode("idle", distance, radius, full)
            else
                self:_stop_emitter(entry, "activation_stop")
                return
            end
        end
    end
    emitter.current_volume = target_volume
    emitter.current_profile = self:_build_profile(emitter.mode, radius, full)
    local marker_position = nil
    if EmitterManager and EmitterManager.get_position then
        marker_position = EmitterManager.get_position(emitter.id)
    end
    self:_toggle_marker(entry, marker_position)
end

function PlatformController:_ensure_entry(extension)
    local unit = extension and extension._unit
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return nil
    end
    local key = Unit and Unit.id_string and Unit.id_string(unit) or tostring(unit)
    if not key then
        return nil
    end
    local entry = self.state.platforms[key]
    if not entry then
        entry = {
            key = key,
            unit = unit,
            extension = extension,
            direction = "none",
            moving = false,
            emitter = nil,
            last_distance = nil,
            marker_position = nil,
            marker_position_box = nil,
        }
        self.state.platforms[key] = entry
    else
        entry.unit = unit
        entry.extension = extension
    end
    return entry
end

function PlatformController:drop_platform(unit)
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        return
    end
    local key = Unit.id_string and Unit.id_string(unit) or tostring(unit)
    if not key then
        return
    end
    local entry = self.state.platforms[key]
    if not entry then
        return
    end
    self:_stop_emitter(entry, "platform_removed")
    self:_toggle_marker(entry, nil)
    self.state.platforms[key] = nil
end

function PlatformController:on_platform_update(extension)
    return self:_ensure_entry(extension)
end

function PlatformController:on_direction_event(extension, direction_index)
    if not self.get_setting("elevatormusic_enable") then
        return
    end
    local entry = self:_ensure_entry(extension)
    if not entry then
        return
    end
    local lookup = rawget(_G, "NetworkLookup")
    local direction_name = lookup and lookup.moveable_platform_direction and lookup.moveable_platform_direction[direction_index] or "none"
    entry.direction = direction_name
    entry.moving = direction_name ~= "none"
    if entry.emitter and entry.emitter.mode == "activation" and not entry.moving then
        local linger = Utils.clamp(finite(self.get_setting(self.activation_linger_setting) or 0, 0), 0, 20)
        if linger > 0 then
            entry.emitter.linger_total = linger
            entry.emitter.linger_until = Utils.realtime_now() + linger
        end
    elseif entry.moving and self.get_setting(self.play_activation_setting) then
        if entry.emitter then
            entry.emitter.mode = "activation"
            entry.emitter.linger_until = nil
            entry.emitter.linger_total = nil
        else
            self:_start_emitter(entry, "activation", entry.last_distance)
        end
    end
end

function PlatformController:update(listener_position)
    if not self.get_setting("elevatormusic_enable") then
        self:stop_all("disabled")
        return
    end
    if not listener_position then
        self:stop_all("no_listener")
        return
    end
    for _, entry in pairs(self.state.platforms) do
        self:_update_platform(entry, listener_position)
    end
end

function PlatformController:_update_platform(entry, listener_position)
    local unit = entry.unit
    if not unit or not Unit or not Unit.alive or not Unit.alive(unit) then
        self:drop_platform(entry.unit)
        return
    end
    if entry.extension and entry.extension.story_direction then
        local dir = entry.extension:story_direction()
        local lookup = rawget(_G, "NetworkLookup")
        entry.direction = lookup and lookup.moveable_platform_direction and lookup.moveable_platform_direction[dir] or "none"
        entry.moving = entry.direction ~= "none"
    end
    local distance = nil
    if listener_position and Vector3 and Vector3.distance then
        local ok, dist = pcall(Vector3.distance, Unit.world_position(unit, 1), listener_position)
        if ok then
            distance = dist
        end
    end
    entry.last_distance = distance
    local wants_activation = entry.moving and self.get_setting(self.play_activation_setting)
    if wants_activation then
        if not entry.emitter then
            self:_start_emitter(entry, "activation", distance)
        else
            entry.emitter.mode = "activation"
            entry.emitter.linger_until = nil
            entry.emitter.linger_total = nil
        end
        self:_update_emitter(entry, distance)
        return
    end
    if entry.emitter and entry.emitter.mode == "activation" then
        self:_update_emitter(entry, distance)
        return
    end
    if not self.get_setting(self.idle_enabled_setting) then
        if entry.emitter and entry.emitter.mode == "idle" then
            self:_stop_emitter(entry, "idle_disabled")
        end
        return
    end
    local start_radius, stop_radius = self:_idle_settings()
    local inside = distance and distance <= start_radius
    local outside = (not distance) or distance >= stop_radius
    if entry.emitter and entry.emitter.mode == "idle" then
        if outside then
            self:_stop_emitter(entry, "idle_out_of_range")
            return
        end
        self:_update_emitter(entry, distance)
        return
    end
    if inside then
        if not entry.emitter then
            self:_start_emitter(entry, "idle", distance)
        else
            entry.emitter.mode = "idle"
        end
        self:_update_emitter(entry, distance)
    end
end

function PlatformController:stop_all(reason)
    for _, entry in pairs(self.state.platforms) do
        self:_stop_emitter(entry, reason)
    end
    self:_set_client_active(false)
end

function PlatformController:get_platforms()
    return self.state.platforms
end

return PlatformController
