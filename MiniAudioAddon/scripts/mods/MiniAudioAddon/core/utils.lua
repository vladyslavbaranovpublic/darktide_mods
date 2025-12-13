local Utils = {}

local Managers = rawget(_G, "Managers")
local Vector3 = rawget(_G, "Vector3")
local Quaternion = rawget(_G, "Quaternion")
local Matrix4x4 = rawget(_G, "Matrix4x4")
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

function Utils.now()
    local ok, t = pcall(function()
        if Managers and Managers.time then
            return Managers.time:time("gameplay")
        end
    end)
    if ok and t then
        return t
    end
    return os.clock()
end

function Utils.realtime_now()
    local ok, t = pcall(function()
        if Managers and Managers.time then
            return Managers.time:time("ui") or Managers.time:time("gameplay")
        end
    end)
    if ok and t then
        return t
    end
    return os.clock()
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

function Utils.encode_json(payload)
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

local function safe_forward(rotation)
    if not Quaternion then
        return Vector3 and Vector3(0, 0, 1) or { 0, 0, 1 }
    end
    local forward = Quaternion.forward(rotation)
    return Vector3.normalize(forward)
end

local function safe_up(rotation)
    if not Quaternion then
        return Vector3 and Vector3(0, 1, 0) or { 0, 1, 0 }
    end
    local up = Quaternion.up(rotation)
    return Vector3.normalize(up)
end

local function listener_pose()
    if not Managers or not Managers.state or not Managers.state.camera or not Matrix4x4 then
        return nil, nil
    end

    local camera_manager = Managers.state.camera
    local player = Managers.player and Managers.player:local_player(1)
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
    local position, rotation = listener_pose()
    if not position or not rotation then
        return nil
    end

    return {
        position = Utils.vec3_to_array(position),
        forward = Utils.vec3_to_array(safe_forward(rotation)),
        up = Utils.vec3_to_array(safe_up(rotation)),
    }
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

return Utils
