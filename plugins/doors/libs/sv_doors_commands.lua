--[[
    Admin commands to disable/enable a frame and reset all doors.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- ============================================================================
-- ADMIN COMMANDS
-- ============================================================================

ws.command.Add("DoorDisableFrame", {
    description = "Disable a door frame (prevents door installation).",
    adminOnly = true,
    OnRun = function(self, client)
        local tr = client:GetEyeTrace()
        local pos = tr.HitPos

        -- Find nearest frame
        local nearestID = nil
        local nearestDist = 128

        for mapID, frameData in pairs(ws.doors.frames) do
            local dist = pos:Distance(frameData.pos)
            if dist < nearestDist then
                nearestDist = dist
                nearestID = mapID
            end
        end

        if not nearestID then
            return "@doorNoFrameNearby"
        end

        ws.doors.frames[nearestID].disabled = true

        -- Remove door if present
        if ws.doors.frames[nearestID].hasDoor then
            ws.doors.RemoveDoor(nearestID)
        end

        ws.doors.Save()
        return "@doorFrameDisabled"
    end
})

ws.command.Add("DoorEnableFrame", {
    description = "Enable a previously disabled door frame.",
    adminOnly = true,
    OnRun = function(self, client)
        local tr = client:GetEyeTrace()
        local pos = tr.HitPos

        local nearestID = nil
        local nearestDist = 128

        for mapID, frameData in pairs(ws.doors.frames) do
            local dist = pos:Distance(frameData.pos)
            if dist < nearestDist then
                nearestDist = dist
                nearestID = mapID
            end
        end

        if not nearestID then
            return "@doorNoFrameNearby"
        end

        ws.doors.frames[nearestID].disabled = false
        ws.doors.Save()
        return "@doorFrameEnabled"
    end
})

ws.command.Add("DoorResetAll", {
    description = "Reset all doors to default state (admin only).",
    adminOnly = true,
    superAdminOnly = true,
    OnRun = function(self, client)
        -- Remove all custom doors
        for mapID, frameData in pairs(ws.doors.frames) do
            if frameData.hasDoor then
                ws.doors.RemoveDoor(mapID)
            end
            frameData.disabled = false
        end

        -- Delete save file
        if file.Exists(ws.doors.GetSavePath(), "DATA") then
            file.Delete(ws.doors.GetSavePath())
        end

        return "@doorAllReset"
    end
})
