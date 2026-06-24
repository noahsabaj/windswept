--[[
    Double-door partner linking (keyvalue slavename first, then strict
    same-frame proximity) so leaves share lock/breach state.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- ============================================================================
-- DOUBLE DOOR PARTNER LINKING
-- ============================================================================

-- Link double doors via wsPartner
-- Uses two methods:
-- 1. targetname/slavename keyvalues (if mapper set them up)
-- 2. Proximity detection (doors within 50 units with similar facing angles)
function ws.doors.LinkPartners()
    local linkedCount = 0
    local linkedByKeyvalue = 0
    local linkedByProximity = 0

    -- First pass: Try keyvalue-based linking (targetname/slavename)
    local byTargetname = {}
    for _, frameData in pairs(ws.doors.frames) do
        if frameData.hasDoor and IsValid(frameData.doorEntity) then
            local door = frameData.doorEntity
            local targetname = frameData.keyvalues and frameData.keyvalues.targetname
            if targetname and targetname ~= "" then
                byTargetname[targetname] = door
            end
        end
    end

    for _, frameData in pairs(ws.doors.frames) do
        if frameData.hasDoor and IsValid(frameData.doorEntity) then
            local door = frameData.doorEntity
            local slavename = frameData.keyvalues and frameData.keyvalues.slavename
            if slavename and slavename ~= "" then
                local partner = byTargetname[slavename]
                if IsValid(partner) and partner ~= door and not door.wsPartner then
                    door.wsPartner = partner
                    partner.wsPartner = door
                    linkedCount = linkedCount + 1
                    linkedByKeyvalue = linkedByKeyvalue + 1
                end
            end
        end
    end

    -- Second pass: Proximity-based linking for doors without partners.
    -- wsPartner is consumed by the lock/unlock/breach paths (via GetDoorPartner),
    -- so a sloppy heuristic would let an unrelated same-model door share lock state.
    -- Two doors are only treated as a double-door pair if ALL hold: (sc-doors-access-7)
    --   1. Same model
    --   2. Hung in the same frame (within 48 units) - real double doors share a frame
    --   3. Yaw aligned to ~0deg or ~180deg (leaves in one frame are parallel/mirrored)
    -- We also pick the CLOSEST qualifying candidate, never just the first found.
    local PROXIMITY_THRESHOLD = 48 * 48  -- DistToSqr comparison (was 100^2)
    local YAW_TOLERANCE = 10             -- degrees; leaves must be parallel or mirrored

    local allDoors = {}
    for _, frameData in pairs(ws.doors.frames) do
        if frameData.hasDoor and IsValid(frameData.doorEntity) then
            local door = frameData.doorEntity
            table.insert(allDoors, {
                door = door,
                pos = door:GetPos(),
                yaw = door:GetAngles().yaw,
                model = door:GetModel()
            })
        end
    end

    for i, data1 in ipairs(allDoors) do
        local door1 = data1.door

        -- Skip if already linked
        if door1.wsPartner then continue end

        local bestData, bestDist

        for j, data2 in ipairs(allDoors) do
            if i == j then continue end

            local door2 = data2.door

            -- Skip if already linked
            if door2.wsPartner then continue end

            -- Check same model
            if data2.model ~= data1.model then continue end

            -- Check tight proximity (same frame)
            local distSqr = data1.pos:DistToSqr(data2.pos)
            if distSqr > PROXIMITY_THRESHOLD then continue end

            -- Check yaw alignment: parallel (~0deg) or mirrored (~180deg).
            -- AngleDifference wraps into [-180, 180].
            local yawDelta = math.abs(math.AngleDifference(data1.yaw, data2.yaw))
            local alignedParallel = yawDelta <= YAW_TOLERANCE
            local alignedMirrored = math.abs(yawDelta - 180) <= YAW_TOLERANCE
            if not alignedParallel and not alignedMirrored then continue end

            -- Track the closest qualifying candidate
            if not bestDist or distSqr < bestDist then
                bestData = data2
                bestDist = distSqr
            end
        end

        if bestData then
            -- These are double doors!
            door1.wsPartner = bestData.door
            bestData.door.wsPartner = door1
            linkedCount = linkedCount + 1
            linkedByProximity = linkedByProximity + 1
        end
    end
end
