--[[
    File: core/track_manager.lua
    Description: Track state management for MiniAudioAddon API.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local TrackManager = {}

-- Track state
local tracks = {}
local process_index = {}

-- Dependencies
local Utils = nil
local realtime_now = nil

function TrackManager.init(dependencies)
    Utils = dependencies.Utils
    realtime_now = dependencies.realtime_now or os.clock
end

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local function next_track_id()
    local stamp = math.floor(realtime_now() * 1000)
    local rand = math.random(1000, 9999)
    return string.format("mini_track_%d_%04d", stamp, rand)
end

local function bind_process(entry, process_id)
    if not process_id then
        return
    end

    process_index[process_id] = process_index[process_id] or {}
    process_index[process_id][entry.id] = true
    entry.process_id = process_id
end

local function touch_entry(entry, state)
    if not entry then
        return
    end
    entry.updated = realtime_now()
    if state then
        entry.state = state
    end
end

-- ============================================================================
-- TRACK LIFECYCLE
-- ============================================================================

function TrackManager.create_or_update(payload, state)
    local entry = tracks[payload.id] or { id = payload.id }
    entry.path = payload.path or entry.path
    entry.loop = payload.loop ~= false
    entry.volume = payload.volume or entry.volume or 1.0
    entry.profile = Utils.deepcopy(payload.profile) or entry.profile
    entry.source = Utils.deepcopy(payload.source) or entry.source
    entry.effects = Utils.deepcopy(payload.effects) or entry.effects
    entry.speed = payload.speed or entry.speed or 1.0
    entry.reverse = payload.reverse or entry.reverse or false
    entry.listener = Utils.deepcopy(payload.listener) or entry.listener
    entry.start_seconds = payload.start_seconds or entry.start_seconds
    entry.seek_seconds = payload.seek_seconds
    entry.skip_seconds = payload.skip_seconds
    entry.autoplay = payload.autoplay
    entry.state = state or entry.state or "pending"
    entry.created = entry.created or realtime_now()
    touch_entry(entry)
    tracks[payload.id] = entry
    bind_process(entry, payload.process_id)
    return entry
end

function TrackManager.remove(id)
    local entry = tracks[id]
    if not entry then
        return
    end

    if entry.process_id and process_index[entry.process_id] then
        process_index[entry.process_id][id] = nil
        if not next(process_index[entry.process_id]) then
            process_index[entry.process_id] = nil
        end
    end

    tracks[id] = nil
end

function TrackManager.touch(id, state)
    local entry = tracks[id]
    if entry then
        touch_entry(entry, state)
    end
end

-- ============================================================================
-- TRACK QUERIES
-- ============================================================================

function TrackManager.exists(id)
    return tracks[id] ~= nil
end

function TrackManager.get(id)
    local entry = tracks[id]
    return entry and Utils.deepcopy(entry) or nil
end

function TrackManager.get_state(id)
    local entry = tracks[id]
    return entry and entry.state or nil
end

function TrackManager.list(filter)
    if not filter then
        -- Return all tracks
        local list = {}
        for _, entry in pairs(tracks) do
            list[#list + 1] = Utils.deepcopy(entry)
        end
        return list
    end

    if filter.id then
        -- Return single track by ID
        return tracks[filter.id] and Utils.deepcopy(tracks[filter.id]) or nil
    end

    if filter.process_id then
        -- Return tracks by process ID
        local list = {}
        local ids = process_index[filter.process_id]
        if ids then
            for id in pairs(ids) do
                list[#list + 1] = Utils.deepcopy(tracks[id])
            end
        end
        return list
    end

    if filter.state then
        -- Return tracks by state
        local list = {}
        for _, entry in pairs(tracks) do
            if entry.state == filter.state then
                list[#list + 1] = Utils.deepcopy(entry)
            end
        end
        return list
    end

    return {}
end

function TrackManager.count(filter)
    local list = TrackManager.list(filter)
    return list and #list or 0
end

-- ============================================================================
-- PROCESS MANAGEMENT
-- ============================================================================

function TrackManager.get_process_tracks(process_id)
    local list = {}
    local ids = process_index[process_id]
    if ids then
        for id in pairs(ids) do
            local entry = tracks[id]
            if entry then
                list[#list + 1] = Utils.deepcopy(entry)
            end
        end
    end
    return list
end

function TrackManager.stop_all_by_process(process_id, callback)
    local ids = process_index[process_id]
    if not ids then
        return 0
    end

    local count = 0
    for id in pairs(ids) do
        local entry = tracks[id]
        if entry and entry.state ~= "stopped" and entry.state ~= "stopping" then
            touch_entry(entry, "stopping")
            if callback then
                callback(id)
            end
            count = count + 1
        end
    end

    return count
end

-- ============================================================================
-- UTILITY
-- ============================================================================

function TrackManager.generate_id()
    return next_track_id()
end

function TrackManager.clear()
    tracks = {}
    process_index = {}
end

return TrackManager
