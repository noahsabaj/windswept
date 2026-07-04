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

-- No prop_ragdoll cache: nothing in the codebase ever sets wsCharID on a ragdoll
-- (only on dropped item entities), so the old GetRagdollRadio path could never find a
-- radio -- while paying an all-inventories walk per ragdoll per pair-call if it ever
-- had. Body eavesdropping is fully served by the ws_knocked path: in this gamemode a
-- body IS a ws_knocked entity plus its visual ragdoll. (#79)
ws.radio.entityCache = ws.radio.entityCache or {
    knockedBodies = {},      -- ws_knocked entities
    stationaryRadios = {},   -- ws_stationary_radio entities
}
ws.radio.entityCache.ragdolls = nil

-- Helper to add entity to cache
local function CacheEntity(ent, cacheTable)
    cacheTable[ent] = true
end

-- Cache entities on creation
hook.Add("OnEntityCreated", "wsRadioEntityCache", function(ent)
    if not IsValid(ent) then return end

    -- Only the relevant classes are worth deferring; skip the timer churn for
    -- every other entity created on the map. (sc-schema-glue-3)
    local class = ent:GetClass()
    if (class ~= "ws_knocked" and class ~= ws.radio.stationaryClass) then
        return
    end

    -- Delay slightly to ensure entity is fully initialized
    timer.Simple(0, function()
        if not IsValid(ent) then return end

        if class == "ws_knocked" then
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
    ws.radio.entityCache.knockedBodies[ent] = nil
    ws.radio.entityCache.stationaryRadios[ent] = nil
end)

-- Rebuild cache on map cleanup (fallback safety)
hook.Add("PostCleanupMap", "wsRadioEntityCacheRebuild", function()
    ws.radio.entityCache.knockedBodies = {}
    ws.radio.entityCache.stationaryRadios = {}

    -- Repopulate caches
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

        -- Transmitter record contract: handhelds store `frequency` (one
        -- string); stationary consoles store `frequencies` (a set of
        -- freq -> volume, keyed by an entity, isStationary = true). Reading
        -- only the singular field crashed this timer the moment a console
        -- mic went live (#70). Normalize to a set and test the receiver's
        -- own frequency against it.
        local frequencies = txData.frequencies
        if frequencies == nil and txData.frequency ~= nil then
            frequencies = {[txData.frequency] = true}
        end
        if frequencies == nil then continue end

        -- Find all receivers tuned to any frequency this transmitter is on
        for _, ply in ipairs(player.GetAll()) do
            if ply == transmitter then continue end

            local radio = GetActiveRadio(ply)
            if radio then
                local plyFreq = radio:GetData("frequency", "100.0")

                if frequencies[plyFreq] ~= nil then
                    local drainKey = ply:SteamID64() .. "_" .. plyFreq
                    if not frequencyDrained[drainKey] then
                        -- Drain 1 second of active usage
                        radio:DrainActive(1)
                        frequencyDrained[drainKey] = true
                    end
                end
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

-- Helper: Check if listener is at a stationary radio receiving on any of these frequencies
local function IsListenerAtStationaryRadioReceiving(listener, frequencies)
    for _, txData in pairs(ws.radio.transmitters) do
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

-- ============================================================================
-- VOICE SNAPSHOT CACHE
--
-- PlayerCanHearPlayersVoice runs per (listener, speaker) PAIR on the engine's
-- ~0.3s voice-mask cadence -- O(players^2) calls, continuously. The old code did
-- its full radio scan (every player's inventory via GetActiveRadio, every cached
-- body, every stationary RX table) inside each pair-call, i.e. O(n^2 x n x
-- inventory) during any transmission, plus 2 table allocations per call even
-- when nobody transmitted. All of that work is pair-independent: it depends
-- only on world state. Snapshot it here at most once per interval and let every
-- pair-call in the window read the same tables. Staleness is bounded by the
-- interval, which matches the voice-mask cadence itself. (#79)
-- ============================================================================

local VOICE_CACHE_INTERVAL = 0.25

local voiceCache = {
    builtAt = -1,
    playerRadios = {},   -- [player] = {freq, volume} for enabled+operable handhelds
    worldReceivers = {}, -- flat {pos, freq, volume} list: body radios + stationary RX
    speakerFreqs = {},   -- per-speaker broadcast-frequency memo, lazy within a window
}

local function RebuildVoiceCache()
    local now = CurTime()
    if (now - voiceCache.builtAt) < VOICE_CACHE_INTERVAL then return end

    voiceCache.builtAt = now
    voiceCache.speakerFreqs = {}

    -- One GetActiveRadio (inventory walk) per PLAYER per interval -- the old code
    -- did one per player per pair-call.
    local playerRadios = {}
    for _, ply in player.Iterator() do
        local radio = GetActiveRadio(ply)
        if radio then
            playerRadios[ply] = {
                freq = radio:GetData("frequency", "100.0"),
                volume = radio:GetData("volume", 50) / 100,
            }
        end
    end
    voiceCache.playerRadios = playerRadios

    -- Every powered world receiver an eavesdropper could stand next to.
    local receivers = {}

    for ent in pairs(ws.radio.entityCache.knockedBodies) do
        if IsValid(ent) and ent.GetInventory then
            local inv = ent:GetInventory()
            if inv then
                local radios = inv:GetItemsByUniqueID(ws.radio.itemID, true)
                for _, radio in ipairs(radios) do
                    if radio:GetData("enabled") and radio:CanOperate() then
                        receivers[#receivers + 1] = {
                            pos = ent:GetPos(),
                            freq = radio:GetData("frequency", "100.0"),
                            volume = radio:GetData("volume", 50) / 100,
                        }
                        break
                    end
                end
            end
        end
    end

    for ent in pairs(ws.radio.entityCache.stationaryRadios) do
        if IsValid(ent) then
            local pos = ent:GetPos()
            for freq, volume in pairs(ent:GetRXFrequencies()) do
                receivers[#receivers + 1] = {pos = pos, freq = freq, volume = volume / 100}
            end
        end
    end

    voiceCache.worldReceivers = receivers
end

-- All frequencies this speaker is being broadcast on (handheld TX + stationary
-- mic pickup), memoized per speaker within the cache window so the stationary
-- range checks and the table run once per SPEAKER, not once per pair. Returns
-- false (memo-able) when the speaker is not on the air.
local function GetSpeakerBroadcastFreqs(speaker, speakerAmplitude)
    local cached = voiceCache.speakerFreqs[speaker]
    if cached ~= nil then return cached end

    local freqs = false

    local txData = ws.radio.transmitters[speaker]
    if txData and not txData.isStationary then
        freqs = {[txData.frequency] = true}
    end

    for _, tx in pairs(ws.radio.transmitters) do
        if tx.isStationary and IsValid(tx.entity)
        and IsSpeakerInRangeOfPosition(speaker, tx.entity:GetPos(), speakerAmplitude) then
            for freq in pairs(tx.frequencies) do
                freqs = freqs or {}
                freqs[freq] = true
            end
        end
    end

    voiceCache.speakerFreqs[speaker] = freqs
    return freqs
end

-- Normal proximity voice with amplitude scaling.
-- Whisper (0.0-0.2): 100-200 units / Normal: 200-400 / Loud: 400-600 / Yell: 600-800
local function CanHearProximity(listener, speaker, speakerAmplitude)
    local distance = listener:EyePos():Distance(speaker:EyePos())
    local voiceRange = 100 + (speakerAmplitude * 700)

    return distance <= voiceRange, false
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

    -- Fast path: nobody anywhere is on the air -> pure proximity voice, zero
    -- allocations (the common case; the old code allocated 2 tables per pair-call
    -- even here). (#79)
    if next(ws.radio.transmitters) == nil then
        return CanHearProximity(listener, speaker, speakerAmplitude)
    end

    RebuildVoiceCache()

    local broadcastFreqs = GetSpeakerBroadcastFreqs(speaker, speakerAmplitude)

    -- If speaker is being broadcast on any frequency, check if listener can receive
    if broadcastFreqs then
        -- Direct reception on the listener's handheld (cached; no inventory walk)
        local listenerRadio = voiceCache.playerRadios[listener]
        if listenerRadio and broadcastFreqs[listenerRadio.freq] then
            return true, false  -- Direct radio reception
        end

        -- Check if listener is at a stationary radio receiving on any broadcast frequency
        local atStationary = IsListenerAtStationaryRadioReceiving(listener, broadcastFreqs)
        if atStationary then
            return true, false  -- Receiving via stationary radio
        end

        -- Eavesdropping: listener near someone/something with a receiving radio.
        -- Both source sets come from the snapshot -- only radio HOLDERS are
        -- iterated, and no inventories are touched in the pair-call.
        local listenerPos = listener:GetPos()
        local closestReceiverDist = math.huge
        local closestReceiverVolume = 0

        for ply, radio in pairs(voiceCache.playerRadios) do
            if ply ~= speaker and ply ~= listener and IsValid(ply) and broadcastFreqs[radio.freq] then
                local dist = listenerPos:Distance(ply:GetPos())
                if dist < closestReceiverDist then
                    closestReceiverDist = dist
                    closestReceiverVolume = radio.volume
                end
            end
        end

        for _, rx in ipairs(voiceCache.worldReceivers) do
            if broadcastFreqs[rx.freq] then
                local dist = listenerPos:Distance(rx.pos)
                if dist < closestReceiverDist then
                    closestReceiverDist = dist
                    closestReceiverVolume = rx.volume
                end
            end
        end

        -- Calculate eavesdrop range: base * receiver_volume * transmitter_amplitude
        local eavesdropRange = ws.radio.eavesdropBase * closestReceiverVolume * speakerAmplitude

        if closestReceiverDist < eavesdropRange then
            return true, false  -- Can hear via eavesdrop
        end

        -- If speaker was ONLY broadcasting via radio (not also speaking locally), stop
        -- here. Handheld TX suppresses local voice; talking near a stationary mic does not.
        local txData = ws.radio.transmitters[speaker]
        if txData and not txData.isStationary then
            return false, false
        end
    end

    return CanHearProximity(listener, speaker, speakerAmplitude)
end
