--[[
    Lifecycle orchestrator: the single InitPostEntity sequence
    (DetectFrames -> HideMapDoors -> Load -> LinkPartners), shutdown flush,
    and the periodic autosave safety net.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

hook.Add("InitPostEntity", "wsDoorsInit", function()
    -- Kill-switch: only take over the map's doors when a schema opts in. (layer-doors)
    if not ws.config.Get("doorsEnabled") then return end

    -- Wait a tick for all entities to spawn
    timer.Simple(0.1, function()
        ws.doors.DetectFrames()
        ws.doors.HideMapDoors()
        ws.doors.Load()

        -- Link double door partners (required for BlastDoor and lock sync)
        ws.doors.LinkPartners()

        -- Sync to all connected players
        timer.Simple(1, function()
            ws.doors.SyncToAll()
        end)
    end)
end)

-- Save on map cleanup (force an immediate flush so nothing is lost). (sc-doors-access-9)
hook.Add("ShutDown", "wsDoorsSave", function()
    ws.doors.Flush()
    timer.Remove("wsDoorsAutosave")
    timer.Remove("wsDoorsDirtyFlush")
end)

-- Periodic autosave (force flush as a safety net even if the dirty flush missed)
timer.Create("wsDoorsAutosave", 300, 0, function()
    ws.doors.Flush()
end)
