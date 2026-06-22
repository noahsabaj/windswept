--[[
    Radio utilities + content seams (framework plugin).

    Generic frequency helpers any radio content uses, plus the seams a schema sets to
    wire its radio CONTENT into the voice engine (sv_radio_voice.lua). Loaded before the
    voice engine (sh_ sorts before sv_) so the engine can read ws.radio.* at runtime.
]]--

ws.radio = ws.radio or {}

-- Frequency constraints
ws.radio.FREQ_MIN = 100.0
ws.radio.FREQ_MAX = 999.9
ws.radio.FREQ_STEP = 0.1

-- ============================================================================
-- CONTENT SEAMS (a schema sets these; nil itemID/stationaryClass = engine dormant)
-- ============================================================================

-- Inventory uniqueID of the handheld radio item (read by GetActiveRadio).
ws.radio.itemID = ws.radio.itemID or nil
-- Entity class of the stationary radio (cached + scanned by the voice engine).
ws.radio.stationaryClass = ws.radio.stationaryClass or nil
-- Base eavesdrop range in units, scaled by receiver volume * speaker amplitude.
ws.radio.eavesdropBase = ws.radio.eavesdropBase or 400

-- Validate frequency format (###.#)
function ws.radio.ValidateFrequency(freq)
    if not freq then return false end

    -- Must be string in ###.# format
    if not string.match(tostring(freq), "^%d%d%d%.%d$") then
        return false
    end

    local num = tonumber(freq)
    if not num then return false end

    return num >= ws.radio.FREQ_MIN and num <= ws.radio.FREQ_MAX
end

-- Format frequency to ensure ###.# format
function ws.radio.FormatFrequency(freq)
    local num = tonumber(freq)
    if not num then return "100.0" end

    -- Clamp to valid range
    num = math.Clamp(num, ws.radio.FREQ_MIN, ws.radio.FREQ_MAX)

    -- Round to nearest 0.1
    num = math.Round(num, 1)

    -- Format as ###.#
    return string.format("%05.1f", num)
end

-- Increment frequency by step
function ws.radio.IncrementFrequency(freq)
    local num = tonumber(freq) or ws.radio.FREQ_MIN
    num = num + ws.radio.FREQ_STEP

    if num > ws.radio.FREQ_MAX then
        num = ws.radio.FREQ_MIN -- Wrap around
    end

    return ws.radio.FormatFrequency(num)
end

-- Decrement frequency by step
function ws.radio.DecrementFrequency(freq)
    local num = tonumber(freq) or ws.radio.FREQ_MIN
    num = num - ws.radio.FREQ_STEP

    if num < ws.radio.FREQ_MIN then
        num = ws.radio.FREQ_MAX -- Wrap around
    end

    return ws.radio.FormatFrequency(num)
end

-- Get default channel configuration for stationary radio
function ws.radio.GetDefaultChannels()
    return {
        {freq = "100.0", tx = false, rx = false, vol = 50},
        {freq = "100.0", tx = false, rx = false, vol = 50},
        {freq = "100.0", tx = false, rx = false, vol = 50},
        {freq = "100.0", tx = false, rx = false, vol = 50}
    }
end
