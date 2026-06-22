--[[
    Radio voice ENGINE (framework plugin) -- the Windswept physical-radio voice model:
    frequency transmit/receive on handheld + stationary radios, amplitude-scaled
    proximity voice, and eavesdropping near any receiver. Extracted from the Colony
    schema sv_hooks in the convergence program.

    Off unless a schema enables radioEnabled AND registers its radio content via the
    seams in sh_radio.lua (ws.radio.itemID / stationaryClass / eavesdropBase). When
    disabled, PlayerCanHearPlayersVoice returns nil and the framework's default
    proximity voice (GM:PlayerCanHearPlayersVoice) applies.

    The shared transmitter table is ws.radio.transmitters (the stationary-radio entity,
    Colony content, writes to it). All references to Colony content are via the seams.
]]--

ws.radio = ws.radio or {}

-- Client->server voice net strings (a schema's handheld radio item net.Start's these).
util.AddNetworkString("wsRadioVoiceStart")
util.AddNetworkString("wsRadioVoiceStop")
util.AddNetworkString("wsVoiceAmplitude")

-- Track who is currently transmitting on radio
ws.radio.transmitters = ws.radio.transmitters or {}

-- Voice distance scaling uses ws.radio.eavesdropBase

-- ============================================================================
-- ENTITY CACHING FOR VOICE SYSTEM PERFORMANCE
-- Cache radio-related entities to avoid ents.FindByClass() in voice hooks
-- ============================================================================

ws.radio.entityCache = ws.radio.entityCache or {
    ragdolls = {},           -- prop_ragdoll entities
    knockedBodies = {},      -- ws_knocked entities
    stationaryRadios = {},   -- ws_stationary_radio entities
}

-- Helper to add entity to cache
local function CacheEntity(ent, cacheTable)
    cacheTable[ent] = true
end

-- Cache entities on creation
hook.Add("OnEntityCreated", "wsRadioEntityCache", function(ent)
    if not IsValid(ent) then return end

    -- Only the 3 relevant classes are worth deferring; skip the timer churn for
    -- every other entity created on the map. (sc-schema-glue-3)
    local class = ent:GetClass()
    if (class ~= "prop_ragdoll" and class ~= "ws_knocked" and class ~= ws.radio.stationaryClass) then
        return
    end

    -- Delay slightly to ensure entity is fully initialized
    timer.Simple(0, function()
        if not IsValid(ent) then return end

        if class == "prop_ragdoll" then
            CacheEntity(ent, ws.radio.entityCache.ragdolls)
        elseif class == "ws_knocked" then
            CacheEntity(ent, ws.radio.entityCache.knockedBodies)
        elseif class == ws.radio.stationaryClass then
            CacheEntity(ent, ws.radio.entityCache.stationaryRadios)
        end
    end)
end)

-- Remove entities from cache on removal
hook.Add("EntityRemoved", "wsRadioEntityUncache", function(ent)
    if not ent then return end

    -- Remove from all caches (cheaper than checking class)
    ws.radio.entityCache.ragdolls[ent] = nil
    ws.radio.entityCache.knockedBodies[ent] = nil
    ws.radio.entityCache.stationaryRadios[ent] = nil
end)

-- Rebuild cache on map cleanup (fallback safety)
hook.Add("PostCleanupMap", "wsRadioEntityCacheRebuild", function()
    ws.radio.entityCache.ragdolls = {}
    ws.radio.entityCache.knockedBodies = {}
    ws.radio.entityCache.stationaryRadios = {}

    -- Repopulate caches
    for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
        CacheEntity(ent, ws.radio.entityCache.ragdolls)
    end
    for _, ent in ipairs(ents.FindByClass("ws_knocked")) do
        CacheEntity(ent, ws.radio.entityCache.knockedBodies)
    end
    for _, ent in ipairs(ents.FindByClass(ws.radio.stationaryClass)) do
        CacheEntity(ent, ws.radio.entityCache.stationaryRadios)
    end
end)

-- Initialize caches on server start
hook.Add("InitPostEntity", "wsRadioEntityCacheInit", function()
    timer.Simple(1, function()
        for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
            CacheEntity(ent, ws.radio.entityCache.ragdolls)
        end
        for _, ent in ipairs(ents.FindByClass("ws_knocked")) do
            CacheEntity(ent, ws.radio.entityCache.knockedBodies)
        end
        for _, ent in ipairs(ents.FindByClass(ws.radio.stationaryClass)) do
            CacheEntity(ent, ws.radio.entityCache.stationaryRadios)
        end
    end)
end)

-- Get player's active radio item
local function GetActiveRadio(client)
    if not IsValid(client) then return nil end

    local character = client:GetCharacter()
    if not character then return nil end

    -- Quick check using cached flag
    if not character:GetData("wsHasActiveRadio") then return nil end

    local inventory = character:GetInventory()
    if not inventory then return nil end

    local radios = inventory:GetItemsByUniqueID(ws.radio.itemID, true)
    for _, radio in ipairs(radios) do
        if radio:GetData("enabled") and radio:CanOperate() then
            return radio
        end
    end

    return nil
end

-- Get radio on a ragdoll entity (dead player)
local function GetRagdollRadio(ragdoll)
    if not IsValid(ragdoll) then return nil end

    -- Check if this is a Windswept ragdoll with inventory
    local charID = ragdoll.wsCharID
    if not charID then return nil end

    -- Find inventory by character ID
    for _, inv in pairs(ws.item.inventories) do
        if inv:GetOwner() == charID then
            local radios = inv:GetItemsByUniqueID(ws.radio.itemID, true)
            for _, radio in ipairs(radios) do
                if radio:GetData("enabled") and radio:CanOperate() then
                    return radio
                end
            end
            break
        end
    end

    return nil
end

-- Net receiver: Player started transmitting
net.Receive("wsRadioVoiceStart", function(len, client)
    if not IsValid(client) then return end

    -- Check player can transmit
    if not client:Alive() then return end
    if client:GetNetVar("wsKnocked") then return end
    if client:GetNetVar("gagged") then return end
    if client:GetNetVar("wsRestricted") then return end

    local radio = GetActiveRadio(client)
    if not radio then return end

    -- Store transmission state
    ws.radio.transmitters[client] = {
        frequency = radio:GetData("frequency", "100.0"),
        startTime = CurTime(),
        radio = radio
    }
end)

-- Net receiver: Player stopped transmitting
net.Receive("wsRadioVoiceStop", function(len, client)
    if not IsValid(client) then return end

    local txData = ws.radio.transmitters[client]
    if txData then
        -- Calculate transmission duration and drain battery
        local duration = CurTime() - txData.startTime
        if txData.radio and duration > 0 then
            txData.radio:DrainActive(duration)
        end

        ws.radio.transmitters[client] = nil
    end
end)


-- Clean up transmitter on disconnect
hook.Add("PlayerDisconnected", "wsRadioTransmitCleanup", function(client)
    ws.radio.transmitters[client] = nil

    -- Drop stale voice-amplitude entry so the table doesn't leak keys. (sc-schema-glue-4)
    if (ws.radio.amplitudes) then
        ws.radio.amplitudes[client] = nil
    end
end)

-- Drain battery for voice receivers (runs every second while transmissions are active)
timer.Create("wsRadioVoiceReceiverDrain", 1, 0, function()
    -- Skip if no active transmitters
    if table.IsEmpty(ws.radio.transmitters) then return end

    -- For each frequency being transmitted on, find all receivers and drain their batteries
    local frequencyDrained = {}  -- Track which player+frequency combos we've drained

    for transmitter, txData in pairs(ws.radio.transmitters) do
        if not IsValid(transmitter) then
            ws.radio.transmitters[transmitter] = nil
            continue
        end

        local frequency = txData.frequency

        -- Find all receivers on this frequency
        for _, ply in ipairs(player.GetAll()) do
            if ply == transmitter then continue end

            local drainKey = ply:SteamID64() .. "_" .. frequency
            if frequencyDrained[drainKey] then continue end  -- Already drained this player for this frequency

            local radio = GetActiveRadio(ply)
            if radio and radio:GetData("frequency", "100.0") == frequency then
                -- Drain 1 second of active usage
                radio:DrainActive(1)
                frequencyDrained[drainKey] = true
            end
        end
    end
end)

-- ============================================================================
-- VOICE SYSTEM OVERRIDE
-- Handles: radio transmission, amplitude-based distance, eavesdropping
-- ============================================================================

-- Store voice amplitude per player for distance calculations
ws.radio.amplitudes = ws.radio.amplitudes or {}

-- Track voice amplitude when player speaks
hook.Add("PlayerStartVoice", "wsTrackVoiceAmplitude", function(client)
    -- Reset amplitude tracking
    ws.radio.amplitudes[client] = 0.5  -- Default to medium
end)

-- Receive amplitude from client (VoiceVolume() is CLIENT-only)
net.Receive("wsVoiceAmplitude", function(len, client)
    if not IsValid(client) then return end

    -- Per-client min-interval to harden against amplitude spam. (sc-schema-glue-8)
    if ((client.wsNextVoiceAmp or 0) > CurTime()) then return end
    client.wsNextVoiceAmp = CurTime() + 0.1

    local amp = net.ReadFloat()
    -- Clamp to valid range
    amp = math.Clamp(amp, 0, 1)
    ws.radio.amplitudes[client] = amp
end)

-- Helper: Check if speaker is within voice range of a position (for stationary radio pickup)
local function IsSpeakerInRangeOfPosition(speaker, pos, speakerAmplitude)
    local voiceRange = 100 + (speakerAmplitude * 700)
    local distSqr = speaker:GetPos():DistToSqr(pos)
    return distSqr <= (voiceRange * voiceRange)
end

-- Helper: Get all frequencies a speaker is being broadcast on (via stationary radios)
local function GetStationaryRadioBroadcastFrequencies(speaker, speakerAmplitude)
    local frequencies = {}

    for source, txData in pairs(ws.radio.transmitters) do
        if txData.isStationary and IsValid(txData.entity) then
            -- Check if speaker is within voice range of the stationary radio
            if IsSpeakerInRangeOfPosition(speaker, txData.entity:GetPos(), speakerAmplitude) then
                -- Add all TX frequencies from this stationary radio
                for freq, _ in pairs(txData.frequencies) do
                    frequencies[freq] = txData.entity
                end
            end
        end
    end

    return frequencies
end

-- Helper: Check if listener is at a stationary radio receiving on any of these frequencies
local function IsListenerAtStationaryRadioReceiving(listener, frequencies)
    for source, txData in pairs(ws.radio.transmitters) do
        if txData.isStationary and IsValid(txData.entity) and txData.user == listener then
            -- Listener is at this stationary radio - check RX frequencies
            local rxFreqs = txData.entity:GetRXFrequencies()
            for freq, volume in pairs(rxFreqs) do
                if frequencies[freq] then
                    return true, volume
                end
            end
        end
    end
    return false, 0
end

-- Main voice hearing logic
function PLUGIN:PlayerCanHearPlayersVoice(listener, speaker)
    -- Disabled (or no radio item registered): return nil so the framework's default
    -- proximity voice (GM:PlayerCanHearPlayersVoice) handles it. PLUGIN hooks run before
    -- the GM method, so returning non-nil below shadows it exactly as the schema used to. (layer-radio)
    if not ws.config.Get("radioEnabled") or not ws.radio.itemID then return end

    if not IsValid(listener) or not IsValid(speaker) then return false, false end
    if listener == speaker then return true, false end  -- Always hear yourself

    -- Defer to the permadeath (knocked) and restraints (gagged) voice blocks: return nil
    -- so those plugins' methods decide, regardless of plugin-hook iteration order. The
    -- schema relied on those running before its voice logic; this preserves that
    -- precedence now that radio shares their hook slot. Defensive: nil/false if absent. (layer-radio)
    if IsValid(speaker.wsKnockedEntity) or IsValid(listener.wsKnockedEntity) then return end
    if speaker:GetNetVar("gagged") then return end

    -- Dead players can't speak
    if not speaker:Alive() then return false, false end

    -- Get speaker's current voice amplitude
    local speakerAmplitude = ws.radio.amplitudes[speaker] or 0.5

    -- Check if speaker is transmitting on handheld radio
    local txData = ws.radio.transmitters[speaker]
    local handheldFrequency = nil

    if txData and not txData.isStationary then
        -- Speaker is transmitting on handheld radio
        handheldFrequency = txData.frequency
    end

    -- Check if speaker is being picked up by any stationary radios with MIC on
    local stationaryFrequencies = GetStationaryRadioBroadcastFrequencies(speaker, speakerAmplitude)

    -- Combine all frequencies speaker is being broadcast on
    local allBroadcastFrequencies = {}
    if handheldFrequency then
        allBroadcastFrequencies[handheldFrequency] = true
    end
    for freq, _ in pairs(stationaryFrequencies) do
        allBroadcastFrequencies[freq] = true
    end

    -- If speaker is being broadcast on any frequency, check if listener can receive
    if not table.IsEmpty(allBroadcastFrequencies) then
        -- Check if listener has handheld radio on any broadcast frequency
        local listenerRadio = GetActiveRadio(listener)
        if listenerRadio then
            local listenerFreq = listenerRadio:GetData("frequency", "100.0")
            if allBroadcastFrequencies[listenerFreq] then
                return true, false  -- Direct radio reception
            end
        end

        -- Check if listener is at a stationary radio receiving on any broadcast frequency
        local atStationary = IsListenerAtStationaryRadioReceiving(listener, allBroadcastFrequencies)
        if atStationary then
            return true, false  -- Receiving via stationary radio
        end

        -- Check eavesdropping: listener is near someone/something with a receiving radio
        local listenerPos = listener:GetPos()
        local closestReceiverDist = math.huge
        local closestReceiverVolume = 0

        -- Check living players with handheld radios
        for _, ply in ipairs(player.GetAll()) do
            if ply ~= speaker and ply ~= listener then
                local radio = GetActiveRadio(ply)
                if radio then
                    local radioFreq = radio:GetData("frequency", "100.0")
                    if allBroadcastFrequencies[radioFreq] then
                        local dist = listenerPos:Distance(ply:GetPos())
                        if dist < closestReceiverDist then
                            closestReceiverDist = dist
                            closestReceiverVolume = radio:GetData("volume", 50) / 100
                        end
                    end
                end
            end
        end

        -- Check ragdolls (knocked/dead) - uses cached entities
        for ent, _ in pairs(ws.radio.entityCache.ragdolls) do
            if IsValid(ent) then
                local radio = GetRagdollRadio(ent)
                if radio then
                    local radioFreq = radio:GetData("frequency", "100.0")
                    if allBroadcastFrequencies[radioFreq] then
                        local dist = listenerPos:Distance(ent:GetPos())
                        if dist < closestReceiverDist then
                            closestReceiverDist = dist
                            closestReceiverVolume = radio:GetData("volume", 50) / 100
                        end
                    end
                end
            end
        end

        -- Check ws_knocked entities - uses cached entities
        for ent, _ in pairs(ws.radio.entityCache.knockedBodies) do
            if IsValid(ent) and ent.GetInventory then
                local inv = ent:GetInventory()
                if inv then
                    local radios = inv:GetItemsByUniqueID(ws.radio.itemID, true)
                    for _, radio in ipairs(radios) do
                        if radio:GetData("enabled") and radio:CanOperate() then
                            local radioFreq = radio:GetData("frequency", "100.0")
                            if allBroadcastFrequencies[radioFreq] then
                                local dist = listenerPos:Distance(ent:GetPos())
                                if dist < closestReceiverDist then
                                    closestReceiverDist = dist
                                    closestReceiverVolume = radio:GetData("volume", 50) / 100
                                end
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Check stationary radios (eavesdrop from their speaker) - uses cached entities
        for ent, _ in pairs(ws.radio.entityCache.stationaryRadios) do
            if IsValid(ent) then
                local rxFreqs = ent:GetRXFrequencies()
                for freq, volume in pairs(rxFreqs) do
                    if allBroadcastFrequencies[freq] then
                        local dist = listenerPos:Distance(ent:GetPos())
                        if dist < closestReceiverDist then
                            closestReceiverDist = dist
                            closestReceiverVolume = volume / 100
                        end
                    end
                end
            end
        end

        -- Calculate eavesdrop range: base * receiver_volume * transmitter_amplitude
        local eavesdropRange = ws.radio.eavesdropBase * closestReceiverVolume * speakerAmplitude

        if closestReceiverDist < eavesdropRange then
            return true, false  -- Can hear via eavesdrop
        end

        -- If speaker was ONLY broadcasting via radio (not also speaking locally), stop here
        if handheldFrequency then
            return false, false
        end
    end

    -- Normal proximity voice with amplitude scaling
    local listenerPos = listener:EyePos()
    local speakerPos = speaker:EyePos()
    local distance = listenerPos:Distance(speakerPos)

    -- Scale voice range by amplitude
    -- Whisper (0.0-0.2): 100-200 units
    -- Normal (0.2-0.5): 200-400 units
    -- Loud (0.5-0.8): 400-600 units
    -- Yelling (0.8-1.0): 600-800 units
    local voiceRange = 100 + (speakerAmplitude * 700)

    if distance <= voiceRange then
        return true, false
    end

    return false, false
end
