--[[
    File: core/utils.lua
    Description: Utility functions for MiniAudioAddon.
    Overall Release Version: 1.0.1
    File Version: 1.0.1
]]

local Utils = {}

local Managers = rawget(_G, "Managers")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local Matrix4x4 = rawget(_G, "Matrix4x4")
local Unit = rawget(_G, "Unit")
local Mods = rawget(_G, "Mods")
local cjson = rawget(_G, "cjson")
if not cjson then
    local ok, lib = pcall(require, "cjson")
    if ok then
        cjson = lib
    end
end

function Utils.clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

function Utils.adaptive_clamp(value, min_value, max_value)
    if min_value > max_value then
        min_value, max_value = max_value, min_value
    end
    return math.max(min_value, math.min(max_value, value))
end

-- Deep copy a table (recursive)
function Utils.deepcopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Utils.deepcopy(v)
    end
    return copy
end

function Utils.now()
    if Managers and Managers.time and type(Managers.time.time) == "function" then
        local ok, t = pcall(Managers.time.time, Managers.time, "gameplay")
        if ok and t then
            return t
        end
    end
    return os.clock()
end

function Utils.realtime_now()
    if Managers and Managers.time and type(Managers.time.time) == "function" then
        local ok, t = pcall(Managers.time.time, Managers.time, "ui")
        if ok and t then
            return t
        end
        ok, t = pcall(Managers.time.time, Managers.time, "gameplay")
        if ok and t then
            return t
        end
    end
    return os.clock()
end


local function resolve_local_player()
    if not Managers or not Managers.player then
        return nil
    end

    local manager = Managers.player

    local function try_call(method, ...)
        local target = manager[method]
        if type(target) ~= "function" then
            return nil
        end
        local ok, player = pcall(target, manager, ...)
        if ok and player then
            return player
        end
        return nil
    end

    local player = try_call("local_player", 1)
        or try_call("local_player_safe", 1)
        or try_call("local_player")
        or try_call("local_player_safe")
    if player then
        return player
    end

    local function first_entry(container)
        if type(container) ~= "table" then
            return nil
        end
        for _, value in pairs(container) do
            if value then
                return value
            end
        end
        return nil
    end

    return first_entry(manager._players) or first_entry(manager._human_players)
end

local function json_escape(str)
    if not str then
        return ""
    end

    return (tostring(str)
        :gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r"))
end

local function simple_json_encode(value)
    local value_type = type(value)
    if value_type == "table" then
        local is_array = true
        local max_index = 0

        for key in pairs(value) do
            if type(key) ~= "number" then
                is_array = false
                break
            end
            if key > max_index then
                max_index = key
            end
        end

        if is_array then
            local parts = {}
            for i = 1, max_index do
                parts[i] = simple_json_encode(value[i])
            end
            return string.format("[%s]", table.concat(parts, ","))
        end

        local entries = {}
        for k, v in pairs(value) do
            entries[#entries + 1] = string.format("\"%s\":%s", json_escape(k), simple_json_encode(v))
        end
        table.sort(entries)
        return string.format("{%s}", table.concat(entries, ","))
    elseif value_type == "string" then
        return string.format("\"%s\"", json_escape(value))
    elseif value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end

    return "null"
end

function Utils.encode_json_payload(payload)
    if cjson and cjson.encode then
        local ok, result = pcall(cjson.encode, payload)
        if ok then
            return true, result
        end

        local fallback = simple_json_encode(payload)
        return true, fallback, result
    end

    return true, simple_json_encode(payload)
end

--[[
    Decode JSON payload string to Lua table
    
    Args:
        payload: String JSON or already-decoded value
    Returns: decoded_value, error_string (error is nil on success)
]]
function Utils.decode_json_payload(payload)
    if type(payload) ~= "string" then
        return payload, nil
    end

    if not (cjson and cjson.decode) then
        return nil, "cjson module unavailable"
    end

    local ok, decoded = pcall(cjson.decode, payload)
    if not ok then
        return nil, decoded or "decode failed"
    end

    return decoded, nil
end

function Utils.direct_write_file(path, contents)
    local io_variants = {}
    local mods_io = Mods and Mods.lua and Mods.lua.io
    if mods_io then
        io_variants[#io_variants + 1] = mods_io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        io_variants[#io_variants + 1] = global_io
    end

    for _, io_api in ipairs(io_variants) do
        if type(io_api) == "table" and type(io_api.open) == "function" then
            local ok, file_or_err = pcall(io_api.open, path, "wb")
            if ok and file_or_err then
                local file = file_or_err
                local wrote = pcall(function()
                    file:write(contents)
                    if file.flush then
                        file:flush()
                    end
                end)
                pcall(function()
                    if file.close then
                        file:close()
                    end
                end)
                if wrote then
                    return true
                end
            end
        end
    end

    return false
end

function Utils.locate_popen()
    local io_variants = {}
    local mods_io = Mods and Mods.lua and Mods.lua.io
    if mods_io then
        io_variants[#io_variants + 1] = mods_io
    end
    local global_io = rawget(_G, "io")
    if global_io then
        io_variants[#io_variants + 1] = global_io
    end

    for _, io_api in ipairs(io_variants) do
        if type(io_api) == "table" and type(io_api.popen) == "function" then
            return function(cmd, mode)
                return io_api.popen(cmd, mode or "r")
            end
        end
    end

    return nil
end

function Utils.vec3_to_array(v)
    if not v or not Vector3 then
        return { 0, 0, 0 }
    end
    return { Vector3.x(v), Vector3.y(v), Vector3.z(v) }
end

function Utils.safe_forward(rotation)
    if not Quaternion then
        return Vector3 and Vector3(0, 0, 1) or { 0, 0, 1 }
    end
    local forward = Quaternion.forward(rotation)
    return Vector3.normalize(forward)
end

function Utils.safe_up(rotation)
    if not Quaternion then
        return Vector3 and Vector3(0, 1, 0) or { 0, 1, 0 }
    end
    local up = Quaternion.up(rotation)
    return Vector3.normalize(up)
end

function Utils.listener_pose()
    if not Managers or not Managers.state or not Managers.state.camera or not Matrix4x4 then
        return nil, nil
    end

    local camera_manager = Managers.state.camera
    local player = resolve_local_player()
    if not player then
        return nil, nil
    end

    local viewport_name = player.viewport_name
    if not viewport_name then
        return nil, nil
    end

    local pose = camera_manager:listener_pose(viewport_name)
    if not pose then
        return nil, nil
    end

    local position = Matrix4x4.translation(pose)
    local rotation = Matrix4x4.rotation(pose)

    return position, rotation
end

function Utils.build_listener_payload()
    local position, rotation = Utils.listener_pose()
    if not position or not rotation then
        return nil
    end

    return {
        position = Utils.vec3_to_array(position),
        forward = Utils.vec3_to_array(Utils.safe_forward(rotation)),
        up = Utils.vec3_to_array(Utils.safe_up(rotation)),
    }
end

-- Ensure listener is available, with fallback options
function Utils.ensure_listener(listener)
    -- If listener is already provided, return it
    if listener then
        return listener
    end
    
    -- Build listener from current player pose
    return Utils.build_listener_payload()
end

function Utils.sanitize_for_format(value)
    if not value then
        return ""
    end
    return tostring(value):gsub("%%", "%%%%")
end

function Utils.sanitize_for_ps_single(value)
    if not value then
        return ""
    end
    return tostring(value):gsub("'", "''")
end

--[[
    HELPER: Get player camera position and orientation
    
    This function retrieves the player's current view (camera) position and rotation,
    along with the forward and right direction vectors. Used to spawn orbs relative
    to where the player is looking.
    
    Returns: Table with {position, rotation, forward, right} or nil if unavailable
]]
function Utils.get_player_pose()
    -- Check if player manager exists
    if not Managers or not Managers.player then
        return nil
    end
    
    -- Get local player (player 1 = you, the person playing)
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit or not Unit.alive(player.player_unit) then
        return nil
    end
    
    -- Get camera manager to access view position/rotation
    local camera_manager = Managers.state and Managers.state.camera
    if not camera_manager then
        return nil
    end
    
    -- Extract camera position and rotation from player's viewport
    local viewport_name = player.viewport_name
    if not viewport_name then
        return nil
    end
    
    -- Safely get camera position and rotation (can fail if viewport not ready)
    local ok_pos, position = pcall(camera_manager.camera_position, camera_manager, viewport_name)
    local ok_rot, rotation = pcall(camera_manager.camera_rotation, camera_manager, viewport_name)
    
    if not ok_pos or not ok_rot or not position or not rotation then
        return nil
    end
    
    -- Return pose data with direction vectors
    return {
        position = position,                      -- Vector3: Where the camera is
        rotation = rotation,                      -- Quaternion: Which way camera is facing
        forward = Quaternion.forward(rotation),   -- Vector3: Forward direction (where you're looking)
        right = Quaternion.right(rotation),       -- Vector3: Right direction (perpendicular to forward)
    }
end

--[[
    HELPER: Get listener context for MiniAudio
    
    Builds the listener payload required by MiniAudio.play(). The listener represents
    where the player's ears are located and which direction they're facing.
    
    Returns: Table with {listener = {position, forward, up}} or nil if unavailable
]]
function Utils.get_listener_context()
    if not Managers or not Managers.state or not Managers.state.camera then
        return nil
    end
    
    local camera_manager = Managers.state.camera
    local player = Managers.player and Managers.player:local_player(1)
    if not player or not player.viewport_name then
        return nil
    end
    
    -- Get the listener pose from camera manager
    local pose = camera_manager:listener_pose(player.viewport_name)
    if not pose then
        return nil
    end
    
    -- Extract position and rotation from the pose matrix
    local position = Matrix4x4.translation(pose)
    local rotation = Matrix4x4.rotation(pose)
    if not position or not rotation then
        return nil
    end
    
    -- Get direction vectors from rotation
    local forward = Quaternion.forward(rotation)
    local up = Quaternion.up(rotation)
    if not forward or not up then
        return nil
    end
 
    -- Return listener context in the format expected by MiniAudio.play
    return {
        listener = {
            position = Utils.vec3_to_array(position),
            forward = Utils.vec3_to_array(forward),
            up = Utils.vec3_to_array(up),
        }
    }
end

--[[
    HELPER: Calculate position offset from a base world position
    
    This is used for Orb 2's movement. Instead of moving relative to the player,
    it moves relative to a fixed world position (where it spawned). This keeps
    the orb in world space rather than following the player.
    
    Args:
        base_position: The fixed world position (Vector3)
        direction_vector: Direction vector to move along (Vector3) - can be right, forward, up, or any custom direction
        offset: How far to move in that direction (float) - negative values move in opposite direction
    Returns: Vector3 offset position in world space, or nil if invalid parameters
    
    Example usage:
        -- Move 5m to the right:
        Utils.position_with_offset(position, right_vector, 5)
        -- Move 10m forward:
        Utils.position_with_offset(position, forward_vector, 10)
        -- Move 3m up:
        Utils.position_with_offset(position, up_vector, 3)
]]
function Utils.position_with_offset(base_position, direction_vector, offset)
    -- Fast validation: check essentials only
    if not base_position or not Vector3 or not direction_vector then
        return nil
    end
    
    -- Validate offset is finite (not inf or nan)
    if type(offset) ~= "number" or offset ~= offset or math.abs(offset) == math.huge then
        return nil
    end
    
    -- Vector math: base + (direction * offset)
    -- Example: If base is (0,0,0), direction is (1,0,0), offset is 3
    --          Result would be (3,0,0) - 3 meters in that direction
    local result = base_position + (direction_vector * offset)
    
    -- Quick NaN check on result (NaN != NaN)
    local x, y, z = Vector3.x(result), Vector3.y(result), Vector3.z(result)
    if x ~= x or y ~= y or z ~= z then
        return nil
    end
    
    return result
end

--[[
    Calculate a position in front of a pose
    
    Common helper for spawning objects/emitters relative to player view.
    Takes a pose (position + forward direction) and calculates where something
    should be placed at the specified offset from pose.
    
    Args:
        pose: Table with {position=Vector3, forward=Vector3, right=Vector3, up=Vector3}
        forward: Meters forward (positive) or backward (negative)
        right: Meters to the right (positive) or left (negative) - optional, default 0
        up: Meters up (positive) or down (negative) - optional, default 0
    Returns: Vector3 world position or nil
    
    Example:
        local pose = Utils.get_player_pose()
        local pos = Utils.position_relative_to_player(pose, 5.0, 0, 0)  -- 5m ahead
        local pos = Utils.position_relative_to_player(pose, 3.0, 2.0, 0)  -- 3m ahead, 2m right
]]
function Utils.position_relative_to_player(forward, right, up)
    local pose = Utils.get_player_pose()
    if not pose or not pose.position or not pose.forward then
        -- Return default position at origin if pose unavailable
        return Vector3 and Vector3(0, 0, 0) or {0, 0, 0}
    end
    
    right = right or 0
    up = up or 0
    
    if type(forward) ~= "number" or forward ~= forward or math.abs(forward) == math.huge then
        return nil
    end
    if type(right) ~= "number" or right ~= right or math.abs(right) == math.huge then
        return nil
    end
    if type(up) ~= "number" or up ~= up or math.abs(up) == math.huge then
        return nil
    end
    
    local offset = pose.forward * forward
    if right ~= 0 and pose.right then
        offset = offset + (pose.right * right)
    end
    if up ~= 0 and pose.up then
        offset = offset + (pose.up * up)
    end
    
    return pose.position + offset
end

--[[
    Build a path relative to a mod's directory
    
    Constructs the full path to a file within a mod's directory structure.
    Handles path separators correctly for Windows.
    
    Args:
        mod_instance: The mod object (from get_mod("ModName"))
        relative_path: Path relative to mod root (e.g., "audio/sound.mp3")
    
    Returns: 
        Full absolute path string, or relative_path if mod path unavailable
    
    Example:
        local path = Utils.build_mod_path(mod, "audio/test.mp3")
        -- Returns: "G:/SteamLibrary/.../mods/MyMod/audio/test.mp3"
]]
function Utils.build_mod_path(mod_instance, relative_path)
    if not mod_instance or not relative_path then
        return relative_path or ""
    end
    
    local mod_path = nil
    local mod_name = nil
    
    -- Get mod name first
    if type(mod_instance.get_name) == "function" then
        local ok, name = pcall(mod_instance.get_name, mod_instance)
        if ok and name then
            mod_name = name
        end
    end
    
    -- Try method 1: Use _path field directly
    if mod_instance._path and mod_instance._path ~= "" then
        mod_path = mod_instance._path
    end
    
    -- Try method 2: get_mod_path() function
    if not mod_path and type(mod_instance.get_mod_path) == "function" then
        local ok, path = pcall(mod_instance.get_mod_path, mod_instance)
        if ok and path and path ~= "" then
            mod_path = path
        end
    end
    
    -- Try method 3: Use Mods global to get mod info
    if not mod_path and Mods and mod_name then
        if Mods.mods and Mods.mods[mod_name] then
            local mod_data = Mods.mods[mod_name]
            if mod_data.path then
                mod_path = mod_data.path
            elseif mod_data._path then
                mod_path = mod_data._path
            end
        end
    end
    
    -- If we couldn't get mod path, return relative path as fallback
    if not mod_path or mod_path == "" then
        return relative_path
    end
    
    -- Normalize path separators: convert forward slashes to backslashes for Windows
    local normalized_relative = relative_path:gsub("/", "\\")
    
    -- Ensure mod_path has trailing backslash
    if not mod_path:match("\\$") then
        mod_path = mod_path .. "\\"
    end
    
    return mod_path .. normalized_relative
end

--[[
    Store a Vector3 as a plain table to prevent corruption
    
    Vector3 objects can become corrupted when stored directly in tables over time.
    This function extracts the x, y, z components into a plain Lua table.
    
    Args:
        vector: Vector3 object to store
    
    Returns:
        Table {x=number, y=number, z=number} or nil if invalid
    
    Example:
        local pos = Vector3(10, 20, 30)
        orb_data.position = Utils.store_vector3(pos)  -- {x=10, y=20, z=30}
]]
function Utils.store_vector3(vector)
    if not vector then
        return nil
    end

    if not Vector3 then
        return nil
    end
    
    local x, y, z = Vector3.x(vector), Vector3.y(vector), Vector3.z(vector)
    
    -- Validate numbers
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil
    end
    if x ~= x or y ~= y or z ~= z then  -- NaN check
        return nil
    end
    
    return {x = x, y = y, z = z}
end

--[[
    Restore a Vector3 from a stored table
    
    Reconstructs a Vector3 object from a table created by store_vector3.
    
    Args:
        table: Table with {x=number, y=number, z=number} fields
    
    Returns:
        Vector3 object or nil if invalid
    
    Example:
        local pos = Utils.restore_vector3(orb_data.position)  -- Vector3(10, 20, 30)
]]
function Utils.restore_vector3(table)
    if not table or type(table) ~= "table" then
        return nil
    end
    
    local x, y, z = table.x, table.y, table.z
    
    -- Validate all components exist and are numbers
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil
    end
    if x ~= x or y ~= y or z ~= z then  -- NaN check
        return nil
    end

    if not Vector3 then
        return nil
    end
    
    return Vector3(x, y, z)
end

--[[ 
    Safely unbox a Vector3Box (if available) or return the original value.
    
    Args:
        box: Vector3Box or plain value
    Returns:
        Unboxed Vector3 value or the original input
]]
function Utils.unbox_vector(box)
    if Vector3Box and box and box.unbox then
        local ok, value = pcall(box.unbox, box)
        if ok then
            return value
        end
        return nil
    end
    return box
end

--[[
    Generate a unique track ID for audio emitters
    
    Creates a unique identifier combining prefix, high-precision timestamp, and random number.
    This prevents ID collisions when multiple tracks are created in quick succession.
    
    Args:
        prefix: Optional string prefix for the ID (default: "track")
    
    Returns:
        Unique string ID (e.g., "track_1234567890_abc_8f3a")
    
    Example:
        local id = Utils.generate_track_id("orb_test")  -- "orb_test_1702745123_456_7a2b"
]]
function Utils.generate_track_id(prefix)
    prefix = prefix or "track"
    
    -- Use os.time() for seconds since epoch
    local timestamp = os.time()
    
    -- Use os.clock() for high-precision subsecond timing (milliseconds)
    local subsec = math.floor((os.clock() % 1) * 1000)
    
    -- Generate random hex string for additional uniqueness
    local random_hex = string.format("%04x", math.random(0, 0xFFFF))
    
    return string.format("%s_%d_%03d_%s", prefix, timestamp, subsec, random_hex)
end

--[[
    Periodically log debug messages based on time intervals
    
    Checks if enough time has passed to print a debug message. Useful for avoiding
    spam in update loops while still getting periodic status information.
    
    Args:
        time_value: Accumulated time (e.g., state.orb2_time)
        interval: Seconds between messages (e.g., 3.0 for every 3 seconds)
        dt: Delta time since last frame
        mod_instance: Mod instance to call :echo() on
        format: String format for the message
        ...: Arguments for string.format
    
    Returns:
        true if message was logged, false otherwise
    
    Example:
        Utils.debug_periodic(state.time, 3.0, dt, mod, 
            "[ORB%d] offset=%.2f, pos=(%.1f, %.1f, %.1f)", 
            orb_num, offset, position_vector)  -- Vector3 auto-expanded to x, y, z
]]
function Utils.debug_periodic(time_value, interval, dt, mod_instance, format, ...)
    if not time_value or not interval or not dt or not mod_instance then
        return false
    end
    
    -- Check if we've crossed an interval boundary
    if time_value % interval < dt then
        -- Expand Vector3 objects in arguments to their x, y, z components
        local args = {...}
        local expanded_args = {}
        
        for i, arg in ipairs(args) do
            -- Check if this is a Vector3 by attempting direct component access
            if Vector3 and type(arg) == "userdata" then
                -- Try to get x component directly (no pcall needed)
                local x = Vector3.x(arg)
                if type(x) == "number" then
                    -- It's a Vector3, expand it to x, y, z
                    table.insert(expanded_args, x)
                    table.insert(expanded_args, Vector3.y(arg))
                    table.insert(expanded_args, Vector3.z(arg))
                else
                    -- Not a Vector3, keep as-is
                    table.insert(expanded_args, arg)
                end
            else
                -- Not userdata, keep as-is
                table.insert(expanded_args, arg)
            end
        end
        
        local message = string.format(format, table.unpack(expanded_args))
        if mod_instance.echo then
            mod_instance:echo(message)
        end
        return true
    end
    
    return false
end

--[[
    Throttle function execution based on time intervals
    
    Checks if enough time has passed since the last execution and updates the timestamp.
    Useful for rate limiting operations like audio updates to ~50Hz.
    
    Args:
        state_table: Table containing the timestamp key
        key: String key in state_table to store the last execution time
        interval: Minimum seconds between executions (e.g., 0.02 for 50Hz)
    
    Returns:
        false if throttled (too soon), true if enough time has passed
    
    Example:
        -- Returns false if called more than 50 times per second
        if not Utils.throttle(state, "orb2_last_update", 0.02) then
            return  -- Skip this update
        end
        -- Proceed with update...
]]
function Utils.throttle(state_table, key, interval)
    if not state_table or not key or not interval then
        return true  -- Allow execution if parameters invalid
    end
    
    local now = os.clock()
    local last_time = state_table[key] or 0
    
    -- Check if enough time has passed
    if now - last_time < interval then
        return false  -- Throttled
    end
    
    -- Update timestamp and allow execution
    state_table[key] = now
    return true
end

--[[
    Check if all values are truthy (not nil and not false)
    
    Useful for dependency checks and validation. Returns true only if ALL
    arguments are truthy (non-nil and non-false).
    
    Args:
        ...: Variable number of values to check
    
    Returns:
        true if all values are truthy, false otherwise
    
    Example:
        if not Utils.all_truthy(MiniAudio, DaemonBridge, PoseTracker) then
            return  -- Missing dependencies
        end
]]
function Utils.all_truthy(...)
    local args = {...}
    for i = 1, #args do
        if not args[i] then
            return false
        end
    end
    return true
end

--[[
    Calculate oscillating position using sine wave movement
    
    Generates smooth back-and-forth motion along a specified direction vector.
    Useful for creating dynamic audio emitters that move in predictable patterns.
    
    Args:
        time_value: Accumulated time in seconds (continuously increasing)
        frequency: Oscillation frequency (default: 0.5, slower = lower values)
                  Period = 2π / frequency seconds (0.5 → ~12.5 second period)
        amplitude: Maximum distance from center in meters (default: 7.5)
                  Total range = amplitude * 2 (7.5 → 15 meters total travel)
        direction_vector: Vector3 direction to oscillate along (e.g., pose.right)
        base_position: Vector3 center position for oscillation
    
    Returns:
        new_position (Vector3): Calculated position at current time
        offset (number): Current offset from base (-amplitude to +amplitude)
    
    Example:
        local pos, offset = Utils.calculate_oscillation(
            state.time, 0.5, 7.5, pose.right, base_pos
        )
]]
function Utils.calculate_oscillation(time_value, frequency, amplitude, direction_vector, base_position)
    if not time_value or not direction_vector or not base_position then
        return nil, 0
    end
    
    -- Use default values if not provided
    frequency = frequency or 0.5
    amplitude = amplitude or 7.5
    
    -- Calculate offset using sine wave
    -- sin(time * frequency) produces smooth oscillation
    local offset = math.sin(time_value * frequency) * amplitude
    
    -- Calculate new position by offsetting from base along direction
    local new_position = Utils.position_with_offset(base_position, direction_vector, offset)
    
    return new_position, offset
end

return Utils
