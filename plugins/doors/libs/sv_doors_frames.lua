--[[
    Map-door frame detection: capture each map door's visuals/keyvalues, build
    the frame table, and hide the original map doors.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- Capture all visual properties from an entity
function ws.doors.CaptureVisualData(ent)
    local data = {
        model = ent:GetModel() or "",
        skin = ent:GetSkin() or 0,
        color = ent:GetColor(),
        material = ent:GetMaterial() or "",
        renderMode = ent:GetRenderMode(),
    }

    -- Capture submaterials (per-part texture overrides)
    local materials = ent:GetMaterials()
    if istable(materials) then
        data.subMaterials = {}
        for k, _ in pairs(materials) do
            local subMat = ent:GetSubMaterial(k - 1)
            if subMat and subMat ~= "" then
                data.subMaterials[k] = subMat
            end
        end
        if table.IsEmpty(data.subMaterials) then
            data.subMaterials = nil
        end
    end

    -- Capture bodygroups (visible variants of multi-part models)
    local bodyGroups = ent:GetBodyGroups()
    if istable(bodyGroups) then
        data.bodyGroups = {}
        for _, v in pairs(bodyGroups) do
            local bgValue = ent:GetBodygroup(v.id)
            if bgValue and bgValue > 0 then
                data.bodyGroups[v.id] = bgValue
            end
        end
        if table.IsEmpty(data.bodyGroups) then
            data.bodyGroups = nil
        end
    end

    return data
end

-- Capture door-specific keyvalues from a prop_door_rotating
function ws.doors.CaptureDoorKeyvalues(ent)
    local keyvalues = {}

    -- Get all keyvalues from the entity
    local allKV = ent:GetKeyValues()

    -- Door identity (critical for double door master/slave relationships)
    if allKV.targetname and allKV.targetname ~= "" then
        keyvalues.targetname = allKV.targetname
    end

    -- Slave door link (makes double doors open/close together)
    if allKV.slavename and allKV.slavename ~= "" then
        keyvalues.slavename = allKV.slavename
    end

    -- Hardware type (0=none, 1=lever/handle, 2=push bar, 3=keypad)
    -- This is CRITICAL for door handles to appear
    if allKV.hardware then
        keyvalues.hardware = allKV.hardware
    end

    -- Spawn flags
    local spawnFlags = ent:GetSpawnFlags()
    if spawnFlags and spawnFlags > 0 then
        keyvalues.spawnflags = spawnFlags
    end

    -- Door rotation settings
    if allKV.distance then
        keyvalues.distance = allKV.distance
    end

    if allKV.speed then
        keyvalues.speed = allKV.speed
    end

    -- Return delay (-1 = never auto-close)
    if allKV.returndelay then
        keyvalues.returndelay = allKV.returndelay
    end

    -- Open direction
    if allKV.opendir then
        keyvalues.opendir = allKV.opendir
    end

    -- Sound overrides
    if allKV.soundopenoverride and allKV.soundopenoverride ~= "" then
        keyvalues.soundopenoverride = allKV.soundopenoverride
    end

    if allKV.soundcloseoverride and allKV.soundcloseoverride ~= "" then
        keyvalues.soundcloseoverride = allKV.soundcloseoverride
    end

    if allKV.soundmoveoverride and allKV.soundmoveoverride ~= "" then
        keyvalues.soundmoveoverride = allKV.soundmoveoverride
    end

    if allKV.soundlockedoverride and allKV.soundlockedoverride ~= "" then
        keyvalues.soundlockedoverride = allKV.soundlockedoverride
    end

    if allKV.soundunlockedoverride and allKV.soundunlockedoverride ~= "" then
        keyvalues.soundunlockedoverride = allKV.soundunlockedoverride
    end

    return keyvalues
end

-- Apply visual data to an entity
function ws.doors.ApplyVisualData(ent, visualData)
    if not IsValid(ent) or not visualData then return end

    -- Apply skin
    if visualData.skin then
        ent:SetSkin(visualData.skin)
    end

    -- Apply color
    if visualData.color then
        ent:SetColor(visualData.color)
    end

    -- Apply material override
    if visualData.material and visualData.material ~= "" then
        ent:SetMaterial(visualData.material)
    end

    -- Apply render mode
    if visualData.renderMode then
        ent:SetRenderMode(visualData.renderMode)
    end

    -- Apply submaterials
    if visualData.subMaterials then
        for k, subMat in pairs(visualData.subMaterials) do
            ent:SetSubMaterial(k - 1, subMat)
        end
    end

    -- Apply bodygroups
    if visualData.bodyGroups then
        for bgID, bgValue in pairs(visualData.bodyGroups) do
            ent:SetBodygroup(bgID, bgValue)
        end
    end
end

-- Detect all map doors and create frame data
function ws.doors.DetectFrames()
    ws.doors.frames = {}
    local skippedBrush = 0

    for _, ent in ipairs(ents.GetAll()) do
        if ws.doors.IsDoor(ent) then
            local mapID = ent:MapCreationID()
            if mapID and mapID > 0 then
                local model = ent:GetModel() or ""

                -- Skip brush-based doors (func_door, func_door_rotating)
                -- These have models like "*90", "*57" - BSP brush references
                -- We can only replace prop_door_rotating which use actual model files
                if string.sub(model, 1, 1) == "*" then
                    skippedBrush = skippedBrush + 1
                    continue
                end

                local defaultType = ws.doors.DetectTypeFromModel(model)

                -- Capture all visual properties from the map door
                local visualData = ws.doors.CaptureVisualData(ent)

                -- Capture door-specific keyvalues (hardware, sounds, etc.)
                local keyvalues = ws.doors.CaptureDoorKeyvalues(ent)

                ws.doors.frames[mapID] = {
                    pos = ent:GetPos(),
                    ang = ent:GetAngles(),
                    originalModel = model,
                    defaultType = defaultType,
                    visualData = visualData,  -- Store all visual properties
                    keyvalues = keyvalues,    -- Store door keyvalues (hardware, sounds, etc.)
                    disabled = false,
                    hasDoor = false,
                    doorEntity = nil,
                    mapEntity = ent
                }
            end
        end
    end

end

-- Hide all map doors (make them invisible and non-solid)
function ws.doors.HideMapDoors()
    for mapID, frameData in pairs(ws.doors.frames) do
        local mapDoor = frameData.mapEntity

        if IsValid(mapDoor) then
            mapDoor:SetNoDraw(true)
            mapDoor:SetNotSolid(true)
            mapDoor:Fire("unlock")  -- Prevent "locked door" sounds
            mapDoor:Fire("open")    -- Ensure door is open (no collision)
        end

        -- mapEntity is never read again after hiding; drop the hard reference
        -- so we don't pin the map door entity for the whole map. (sc-doors-access-12)
        frameData.mapEntity = nil
    end

end
