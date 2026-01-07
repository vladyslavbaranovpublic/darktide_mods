--[[
    File: features/playlist_manager.lua
    Description: Shared playlist discovery and iteration helper for MiniAudioAddon clients.
]]

local PlaylistManager = {}

local Utils = nil
local IOUtils = nil
local ConstantsModule = nil

local sources = {}

local function describe_state(state)
    if not state then
        return 0, nil
    end

    local count = #state.playlist
    if count == 0 then
        return 0, string.format("%s No supported audio files found in %s.", state.log_prefix or "[Playlist]", state.folder or "unknown folder")
    end

    return count, string.format("%s Found %d track%s.", state.log_prefix or "[Playlist]", count, count == 1 and "" or "s")
end
local DEFAULT_EXTENSIONS = {
    [".mp3"] = true,
    [".wav"] = true,
    [".flac"] = true,
}

local DEFAULT_UNSUPPORTED_EXTENSIONS = {
    [".ogg"] = "Ogg Vorbis",
    [".opus"] = "Opus",
}

local DEFAULT_FALLBACKS = {
    "elevator_music.mp3",
    "elevator_music.wav",
    "Darktide Elevator Music 2025-12-04 09_14_fixed.mp3",
}

local function sanitize_path(path)
    if not path then
        return nil
    end
    path = tostring(path)
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then
        return nil
    end
    return path
end

local function extension_of(path)
    local dot = path:match("^.*(%.[^%.]+)$")
    return dot and dot:lower() or ""
end

local function get_current_time()
    if Utils and Utils.realtime_now then
        return Utils.realtime_now()
    end
    return os.clock()
end

local function resolve_folder(state)
    if state.folder then
        return state.folder
    end

    if state.resolve_folder then
        local ok, folder = pcall(state.resolve_folder)
        if ok and folder then
            folder = sanitize_path(folder)
            state.folder = folder
            return folder
        end
    end

    return nil
end

local function log_once(state, message, ...)
    if state.mod and message then
        state.mod:echo(message, ...)
    end
end

local function log_unsupported(state, skipped)
    if not skipped or not next(skipped) then
        state.unsupported_signature = nil
        return
    end

    local parts = {}
    local items = {}
    local total = 0
    for ext, count in pairs(skipped) do
        total = total + count
        parts[#parts + 1] = string.format("%s=%d", ext, count)

        local label = state.unsupported_extensions[ext]
        if label then
            items[#items + 1] = string.format("%s (%s) x%d", label, ext, count)
        else
            items[#items + 1] = string.format("%s x%d", ext, count)
        end
    end

    table.sort(parts)
    table.sort(items)

    local signature = table.concat(parts, "|")
    if signature == state.unsupported_signature then
        return
    end
    state.unsupported_signature = signature

    if state.mod then
        local prefix = state.log_prefix or "[Playlist]"
        local plural = total == 1 and "" or "s"
        state.mod:echo(
            "%s Skipped %d unsupported audio file%s (%s). Convert them to supported formats.",
            prefix,
            total,
            plural,
            table.concat(items, ", ")
        )
    end
end

local function fallback_track_path(state, folder)
    if not folder or not state.fallback_filenames then
        return nil
    end

    local open_fn = nil
    local mods_io = Mods and Mods.lua and Mods.lua.io
    if mods_io and mods_io.open then
        open_fn = mods_io.open
    elseif io and io.open then
        open_fn = io.open
    end
    if not open_fn then
        return nil
    end

    for _, name in ipairs(state.fallback_filenames) do
        local candidate = string.format("%s\\%s", folder, name)
        local ok, file = pcall(open_fn, candidate, "rb")
        if ok and file then
            if file.close then
                file:close()
            end
            return candidate
        end
    end

    return nil
end

local function scan_playlist(state, force)
    local folder = resolve_folder(state)
    if not folder then
        return
    end

    local now = get_current_time()
    if not force and (now - state.last_scan_t) < state.scan_interval then
        return
    end

    local popen = Utils and Utils.locate_popen and Utils.locate_popen()
    if not popen then
        if not state.warned_files and state.mod then
            state.mod:echo("%s IO.popen unavailable; cannot enumerate audio files.", state.log_prefix or "[Playlist]")
            state.warned_files = true
        end
        return
    end

    local pipe = popen(string.format('cmd /S /C "dir /b /a-d \"%s\""', folder))
    if not pipe then
        return
    end

    state.playlist = {}
    state.durations = {}
    state.last_scan_t = now
    state.next_index = 1

    local skipped = {}
    for line in pipe:lines() do
        local trimmed = line and line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local ext = extension_of(trimmed)
            if state.allowed_extensions[ext] then
                local candidate = string.format("%s\\%s", folder, trimmed)
                if IOUtils and IOUtils.expand_track_path then
                    candidate = IOUtils.expand_track_path(candidate) or candidate
                end
                state.playlist[#state.playlist + 1] = candidate
                if IOUtils and IOUtils.get_media_duration then
                    local duration = IOUtils.get_media_duration(candidate)
                    if duration and duration > 0 then
                        state.durations[candidate] = duration
                    end
                end
            elseif state.unsupported_extensions[ext] then
                skipped[ext] = (skipped[ext] or 0) + 1
            end
        end
    end
    pipe:close()

    log_unsupported(state, skipped)

    if #state.playlist == 0 then
        local fallback = fallback_track_path(state, folder)
        if fallback then
            state.playlist[1] = fallback
            if not state.warned_files and state.mod then
                local name = fallback:match("([^/\\]+)$") or fallback
                state.mod:echo("%s No custom playlist found; using fallback '%s'.", state.log_prefix or "[Playlist]", name)
                state.warned_files = true
            end
        elseif not state.warned_files and state.mod then
            state.mod:echo("%s Place supported audio files under %s to enable playback.", state.log_prefix or "[Playlist]", folder)
            state.warned_files = true
        end
    else
        if state.warned_files and state.mod then
            state.mod:echo("%s Found %d track(s).", state.log_prefix or "[Playlist]", #state.playlist)
        end
        state.warned_files = false
    end
end

function PlaylistManager.init(dependencies)
    Utils = dependencies.Utils
    IOUtils = dependencies.IOUtils
    ConstantsModule = dependencies.Constants

    if ConstantsModule then
        if ConstantsModule.AUDIO_EXTENSIONS then
            DEFAULT_EXTENSIONS = ConstantsModule.AUDIO_EXTENSIONS
        end
        if ConstantsModule.UNSUPPORTED_AUDIO_EXTENSIONS then
            DEFAULT_UNSUPPORTED_EXTENSIONS = ConstantsModule.UNSUPPORTED_AUDIO_EXTENSIONS
        end
        if ConstantsModule.DEFAULT_AUDIO_FALLBACKS then
            DEFAULT_FALLBACKS = ConstantsModule.DEFAULT_AUDIO_FALLBACKS
        end
    end
end

function PlaylistManager.register(source_id, config)
    if not source_id then
        return nil, "missing_source_id"
    end

    sources[source_id] = {
        mod = config.mod,
        resolve_folder = config.resolve_folder,
        log_prefix = config.log_prefix or "[Playlist]",
        allowed_extensions = config.allowed_extensions or DEFAULT_EXTENSIONS,
        unsupported_extensions = config.unsupported_extensions or DEFAULT_UNSUPPORTED_EXTENSIONS,
        fallback_filenames = config.fallback_filenames or DEFAULT_FALLBACKS,
        scan_interval = config.scan_interval or 2,
        random = config.random or false,
        playlist = {},
        last_scan_t = 0,
        next_index = 1,
        warned_files = false,
        warned_missing = false,
        durations = {},
    }

    return true
end

function PlaylistManager.duration(source_id, path)
    local state = sources[source_id]
    if not state or not path then
        return nil
    end
    return state.durations[path]
end

function PlaylistManager.force_scan(source_id)
    local state = sources[source_id]
    if not state then
        return false, "unregistered"
    end
    scan_playlist(state, true)
    return true, describe_state(state)
end

local function next_random_track(state)
    if #state.playlist == 0 then
        return nil
    end
    local index = math.random(1, #state.playlist)
    return state.playlist[index]
end

local function next_sequential_track(state)
    if #state.playlist == 0 then
        return nil
    end
    local path = state.playlist[state.next_index]
    state.next_index = state.next_index + 1
    if state.next_index > #state.playlist then
        state.next_index = 1
    end
    return path
end

function PlaylistManager.next(source_id, opts)
    local state = sources[source_id]
    if not state then
        return nil, "unregistered"
    end

    if opts and opts.force_scan then
        scan_playlist(state, true)
    else
        scan_playlist(state, false)
    end

    if #state.playlist == 0 then
        return nil, "empty"
    end

    local use_random = state.random
    if opts and opts.random ~= nil then
        use_random = opts.random
    end

    if use_random then
        return next_random_track(state)
    end

    return next_sequential_track(state)
end

function PlaylistManager.describe(source_id)
    local state = sources[source_id]
    if not state then
        return 0, nil
    end
    return describe_state(state)
end

return PlaylistManager
