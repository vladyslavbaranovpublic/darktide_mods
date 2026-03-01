--[[
    File: seed.lua
    Description: Deterministic RNG and seed initialization utilities.
    Overall Release Version: 1.0.0
    File Version: 1.0.0
    File Introduced in: 1.0.0
    Last Updated: 2026-02-28
    Author: LAUREHTE
]]

local Seed = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271
local MAX_USER_SEED = MODULUS - 1

local function _normalize_seed(value, fallback)
    local numeric_value = tonumber(value)

    if not numeric_value then
        numeric_value = tonumber(fallback) or 1
    end

    numeric_value = math.floor(math.abs(numeric_value))

    if numeric_value == 0 then
        numeric_value = 1
    end

    if numeric_value > MAX_USER_SEED then
        numeric_value = numeric_value % MAX_USER_SEED

        if numeric_value == 0 then
            numeric_value = 1
        end
    end

    return numeric_value
end

function Seed.generate_seed()
    local unix_time = os.time()
    local clock_fraction = math.floor((os.clock() % 1) * 1000000)
    local random_term = math.random(1, MAX_USER_SEED)

    local mixed_seed = (unix_time * 1103515245 + clock_fraction * 12345 + random_term) % MAX_USER_SEED

    if mixed_seed == 0 then
        mixed_seed = 1
    end

    return mixed_seed
end

function Seed.resolve_seed(mod, config, state, reason, force_new)
    local selected_seed

    if config.random_every_mission and reason == "mission_start" then
        selected_seed = Seed.generate_seed()
    elseif force_new then
        if not config.use_random_seed and config.seed_value > 0 then
            selected_seed = config.seed_value
        else
            selected_seed = Seed.generate_seed()
        end
    elseif state.active_seed and state.active_seed > 0 then
        selected_seed = state.active_seed
    elseif not config.use_random_seed and config.seed_value > 0 then
        selected_seed = config.seed_value
    else
        selected_seed = Seed.generate_seed()
    end

    selected_seed = _normalize_seed(selected_seed, 1)

    state.active_seed = selected_seed
    state.rng_state = selected_seed
    state.last_seed_reason = reason

    if config and config.debug_mode == true and mod and mod.echo then
        mod:echo(string.format("[Randomizer] Seed set to %d (%s)", selected_seed, tostring(reason)))
    end

    return selected_seed
end

function Seed.reset_rng(state)
    if state and state.active_seed then
        state.rng_state = _normalize_seed(state.active_seed, 1)
    end
end

function Seed.next_raw(state)
    local current_seed = _normalize_seed(state.rng_state or state.active_seed, 1)
    local next_seed = (current_seed * MULTIPLIER) % MODULUS

    if next_seed == 0 then
        next_seed = 1
    end

    state.rng_state = next_seed

    return next_seed
end

function Seed.next_float(state)
    return Seed.next_raw(state) / MODULUS
end

function Seed.next_int(state, min_value, max_value)
    local a = math.floor(tonumber(min_value) or 0)
    local b = math.floor(tonumber(max_value) or 0)

    if a > b then
        a, b = b, a
    end

    if a == b then
        return a
    end

    local span = b - a + 1
    local value = Seed.next_float(state)

    return a + math.floor(value * span)
end

function Seed.choose_index(state, count)
    local pool_size = math.floor(tonumber(count) or 0)

    if pool_size <= 0 then
        return nil
    end

    return Seed.next_int(state, 1, pool_size)
end

return Seed
