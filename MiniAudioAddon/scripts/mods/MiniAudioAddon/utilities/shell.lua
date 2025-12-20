--[[
    File: utilities/shell.lua
    Description: Shell command execution with DLS/local fallback for MiniAudioAddon.
    Overall Release Version: 1.0.3
    File Version: 1.0.0
]]

local Shell = {}

-- Dependencies
local DLS = nil
local mod = nil
local debug_enabled = nil

function Shell.init(dependencies)
    DLS = dependencies.DLS
    mod = dependencies.mod
    debug_enabled = dependencies.debug_enabled
end

-- ============================================================================
-- SHELL COMMAND EXECUTION
-- ============================================================================

--[[
    Execute a shell command with DLS or local fallback
    
    Args:
        cmd: Shell command string
        why: Description of the command (for error logging)
        opts: Options table {
            prefer_local: Try os.execute first, then DLS
            local_only: Only use os.execute
            dls_only: Only use DLS
        }
    
    Returns:
        boolean: true if command executed successfully
]]
function Shell.run_command(cmd, why, opts)
    opts = opts or {}
    local ran = false

    local function try_dls()
        if ran or opts.local_only then
            return
        end

        if DLS and DLS.run_command then
            local ok = pcall(DLS.run_command, cmd)
            if ok then
                ran = true
            end
        end
    end

    local function try_local()
        if ran or opts.dls_only then
            return
        end

        local os_ok, os_result = pcall(os.execute, cmd)
        if os_ok and os_result then
            ran = true
        end
    end

    if opts.prefer_local then
        try_local()
        if not ran then
            try_dls()
        end
    else
        try_dls()
        if not ran then
            try_local()
        end
    end

    if not ran and why and debug_enabled and debug_enabled() and mod then
        mod:error("[Shell] Command failed (%s): %s", why, cmd)
    end

    return ran
end

return Shell
