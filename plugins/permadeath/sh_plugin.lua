--[[
    Permadeath Plugin for Windswept

    A knockout/permadeath system where lethal damage triggers a knockout state
    instead of instant death. Players can be revived within a time window,
    with permanent character death if the timer expires.
]]--

PLUGIN.name = "Permadeath"
PLUGIN.author = "Windswept Team"
PLUGIN.description = "Knockout and permadeath system with revival mechanics."

-- Configuration defaults
ws.config.Add("permadeathBaseTime", 300, "Base knockout timer in seconds (5 minutes).", nil, {
    data = {min = 30, max = 1800},
    category = "Permadeath"
})

ws.config.Add("permadeathHeadshotChance", 50, "Percent chance a headshot causes instant permadeath.", nil, {
    data = {min = 0, max = 100},
    category = "Permadeath"
})

ws.config.Add("permadeathRevivalTimeMin", 3, "Minimum revival progress time in seconds.", nil, {
    data = {min = 1, max = 30},
    category = "Permadeath"
})

ws.config.Add("permadeathRevivalTimeMax", 10, "Maximum revival progress time in seconds.", nil, {
    data = {min = 1, max = 60},
    category = "Permadeath"
})

ws.config.Add("permadeathPassiveHealRate", 1, "HP gained per minute from passive healing.", nil, {
    data = {min = 0, max = 10},
    category = "Permadeath"
})

ws.config.Add("permadeathPassiveHealCap", 80, "Maximum health percentage from passive healing.", nil, {
    data = {min = 0, max = 100},
    category = "Permadeath"
})

-- Network strings (server will register these)
if SERVER then
    util.AddNetworkString("wsKnockoutStart")
    util.AddNetworkString("wsKnockoutTimerSync")
    util.AddNetworkString("wsKnockoutEnd")
    util.AddNetworkString("wsKnockoutGiveUp")
    util.AddNetworkString("wsRevivalProgress")
    util.AddNetworkString("wsSuicideExecute")  -- Suicide with gun
    util.AddNetworkString("wsPermadeathScreen")  -- Server → Client: show memorial
    util.AddNetworkString("wsPermadeathReady")   -- Client → Server: player acknowledged
end

-- Hold E duration to trigger revival (in seconds)
PLUGIN.reviveHoldTime = 1.5

-- Shared utility functions

-- Calculate knockout duration based on knockout count
-- Each knockout halves the timer: 300 -> 150 -> 75 -> 37.5 -> 18.75...
function PLUGIN:GetKnockoutDuration(knockoutCount)
    local base = ws.config.Get("permadeathBaseTime", 300)
    knockoutCount = math.max(1, knockoutCount or 1)
    return base / math.pow(2, knockoutCount - 1)
end

-- Check if the last hit was a headshot (stored from ScalePlayerDamage)
function PLUGIN:IsHeadshot(client)
    return client.wsLastHitGroup == HITGROUP_HEAD
end

-- Probabilistic squared calculation for revival chance
-- First rolls to determine the actual percentage, then rolls against it
-- Returns: success (bool), actualChance (number 0-100, for logging only)
function PLUGIN:CalculateRevivalChance(hasDefib)
    local chanceRange
    if hasDefib then
        chanceRange = {45, 95}  -- Defibrillator: 45-95%
    else
        chanceRange = {5, 15}   -- Bare hands: 5-15%
    end

    -- Roll the actual chance (the player never sees this)
    local actualChance = math.random(chanceRange[1], chanceRange[2])

    -- Roll against the determined chance
    local roll = math.random(1, 100)
    local success = roll <= actualChance

    return success, actualChance
end

-- Get CPR revival progress bar duration (fixed 10 seconds)
function PLUGIN:GetRevivalDuration()
    return 10
end

-- Format time as MM:SS
function PLUGIN:FormatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", minutes, secs)
end

-- Include server and client files
ws.util.Include("sv_plugin.lua")
ws.util.Include("cl_plugin.lua")
