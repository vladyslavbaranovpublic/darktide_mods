--[[
    File: core/client_manager.lua
    Description: Client tracking and keepalive management for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local ClientManager = {}

-- Active clients tracking
local active_clients = {}

-- Callbacks
local generation_callback = nil
local reset_callback = nil

-- Dependencies
local daemon_is_active = nil
local daemon_start = nil

function ClientManager.init(dependencies)
    daemon_is_active = dependencies.daemon_is_active
    daemon_start = dependencies.daemon_start
end

-- ============================================================================
-- CLIENT ID INFERENCE
-- ============================================================================

local function infer_client_id()
    local dbg = debug and debug.getinfo
    if not dbg then
        return nil
    end

    local mod = get_mod("MiniAudioAddon")
    for level = 3, 8 do
        local info = dbg(level, "S")
        local src = info and info.source
        if type(src) == "string" then
            local cleaned = src:gsub("^@", "")
            local mod_name = cleaned:match("mods[/\\]([^/\\]+)")
            if mod_name and mod_name ~= (mod and mod:get_name() or "MiniAudioAddon") then
                return mod_name
            end
        end
    end

    return nil
end

-- ============================================================================
-- CLIENT MANAGEMENT
-- ============================================================================

function ClientManager.set_active(client_id, has_active)
    client_id = client_id or infer_client_id() or "default"
    if has_active then
        active_clients[client_id] = true
    else
        active_clients[client_id] = nil
    end
end

function ClientManager.is_active(client_id)
    return active_clients[client_id] ~= nil
end

function ClientManager.has_any_clients()
    return next(active_clients) ~= nil
end

function ClientManager.get_active_clients()
    local clients = {}
    for client_id in pairs(active_clients) do
        clients[#clients + 1] = client_id
    end
    return clients
end

function ClientManager.clear_all()
    active_clients = {}
end

-- ============================================================================
-- KEEPALIVE MANAGEMENT
-- ============================================================================

local keepalive_flag = false

function ClientManager.set_keepalive(active)
    keepalive_flag = active and true or false
    ClientManager.set_active("MiniAudioAddon_keepalive", keepalive_flag)
end

function ClientManager.is_keepalive_active()
    return keepalive_flag
end

function ClientManager.ensure_daemon_keepalive()
    ClientManager.set_keepalive(true)
    if daemon_is_active and not daemon_is_active() then
        if daemon_start then
            daemon_start("", 1.0, 0.0)
        end
    end
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

function ClientManager.set_generation_callback(callback)
    generation_callback = callback
end

function ClientManager.set_reset_callback(callback)
    reset_callback = callback
end

function ClientManager.notify_generation_reset(generation, reason)
    if generation_callback then
        local ok, err = pcall(generation_callback, generation, reason)
        if not ok then
            local mod = get_mod("MiniAudioAddon")
            if mod then
                mod:error("[ClientManager] generation callback failed: %s", tostring(err))
            end
        end
    end
end

function ClientManager.notify_daemon_reset(reason)
    if reset_callback then
        pcall(reset_callback, reason)
    end
end

return ClientManager
