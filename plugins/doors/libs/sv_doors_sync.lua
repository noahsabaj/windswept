--[[
    Server->client frame sync (full broadcast + per-player on join).

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- Frame state is broadcast server->client over this string (received in cl_doors_frames.lua).
util.AddNetworkString("wsDoorsSync")

-- Sync frame data to a client
function ws.doors.SyncToPlayer(ply)
    local count = table.Count(ws.doors.frames)
    if count == 0 then return end

    net.Start("wsDoorsSync")
        net.WriteUInt(count, 16)
        for mapID, frameData in pairs(ws.doors.frames) do
            net.WriteUInt(mapID, 32)
            net.WriteVector(frameData.pos)
            net.WriteAngle(frameData.ang)
            net.WriteBool(frameData.hasDoor or false)
            net.WriteBool(frameData.disabled or false)
        end
    net.Send(ply)
end

-- Sync frame data to all clients
function ws.doors.SyncToAll()
    local count = table.Count(ws.doors.frames)
    if count == 0 then return end

    net.Start("wsDoorsSync")
        net.WriteUInt(count, 16)
        for mapID, frameData in pairs(ws.doors.frames) do
            net.WriteUInt(mapID, 32)
            net.WriteVector(frameData.pos)
            net.WriteAngle(frameData.ang)
            net.WriteBool(frameData.hasDoor or false)
            net.WriteBool(frameData.disabled or false)
        end
    net.Broadcast()
end

-- Sync when player joins
hook.Add("PlayerInitialSpawn", "wsDoorsSyncOnJoin", function(ply)
    -- Delay to ensure everything is loaded
    timer.Simple(3, function()
        if IsValid(ply) then
            ws.doors.SyncToPlayer(ply)
        end
    end)
end)
