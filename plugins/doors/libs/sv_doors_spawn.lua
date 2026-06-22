--[[
    Door entity lifecycle: spawn a prop_door_rotating at a frame (restoring
    saved health/lock/damage), the type-config accessor, and frame removal.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- Spawn a prop_door_rotating at a frame using the original model
function ws.doors.SpawnDoor(mapID, doorData)
    local frameData = ws.doors.frames[mapID]
    if not frameData then return nil end
    if frameData.disabled then return nil end
    if frameData.hasDoor then return nil end

    -- Create native prop_door_rotating
    local door = ents.Create("prop_door_rotating")
    if not IsValid(door) then return nil end

    door:SetPos(frameData.pos)
    door:SetAngles(frameData.ang)
    door:SetModel(frameData.originalModel)  -- Use ORIGINAL map model

    -- Apply keyvalues BEFORE spawning (critical for hardware/handle type)
    if frameData.keyvalues then
        for key, value in pairs(frameData.keyvalues) do
            door:SetKeyValue(key, tostring(value))
        end
    end

    door:Spawn()
    door:Activate()

    -- Apply all visual properties from the original map door (skin, color, bodygroups, etc.)
    if frameData.visualData then
        ws.doors.ApplyVisualData(door, frameData.visualData)
    end

    -- Initialize physics as static
    local phys = door:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end

    -- Store custom data on the entity
    door.wsFrameID = tostring(mapID)
    door.wsDoorType = frameData.defaultType
    door.wsIsWindsweptDoor = true  -- Mark as our managed door

    -- Apply saved data or defaults. Resolve the type config once with a wood
    -- fallback so an unexpected/stale defaultType can't nil-index here.
    local config = ws.doors.typeConfig[frameData.defaultType] or ws.doors.typeConfig.wood
    if doorData then
        door.wsHealth = doorData.health or config.maxHealth
        door.wsMaxHealth = doorData.maxHealth or config.maxHealth
        door.wsLockData = doorData.lockData
        if doorData.locked and door.wsLockData then
            door:Fire("lock")
        end
        -- Restore battering ram damage (persists until repaired)
        door.wsBatteringRamRequired = doorData.ramRequired
        door.wsBatteringRamHits = doorData.ramHits
    else
        -- Default: full health, no lock, no damage
        door.wsHealth = config.maxHealth
        door.wsMaxHealth = config.maxHealth
        door.wsLockData = nil
        door.wsBatteringRamRequired = nil
        door.wsBatteringRamHits = nil
    end

    -- Update frame
    frameData.hasDoor = true
    frameData.doorEntity = door

    -- Sync to clients
    ws.doors.SyncToAll()

    return door
end

-- Get door's type config
function ws.doors.GetTypeConfig(door)
    if not IsValid(door) then return ws.doors.typeConfig.wood end
    local doorType = door.wsDoorType or "wood"
    return ws.doors.typeConfig[doorType] or ws.doors.typeConfig.wood
end
-- Remove a door from a frame
function ws.doors.RemoveDoor(mapID)
    local frameData = ws.doors.frames[mapID]
    if not frameData then return false end

    if IsValid(frameData.doorEntity) then
        frameData.doorEntity:Remove()
    end

    frameData.hasDoor = false
    frameData.doorEntity = nil

    -- Sync to clients
    ws.doors.SyncToAll()

    return true
end
