--[[
    Battering-ram breach: gib/debris spawning, particle effects, and the
    explosive BreachDoor that permanently destroys a door leaf.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- ============================================================================
-- DOOR BREACH (Battering Ram) - Explosive destruction with debris
-- ============================================================================

-- Gib models for debris
ws.doors.gibs = {
    wood = {
        "models/gibs/wood_gib01a.mdl",
        "models/gibs/wood_gib01b.mdl",
        "models/gibs/wood_gib01c.mdl",
        "models/gibs/wood_gib01d.mdl",
        "models/gibs/wood_gib01e.mdl"
    },
    metal = {
        "models/gibs/metal_gib1.mdl",
        "models/gibs/metal_gib2.mdl",
        "models/gibs/metal_gib3.mdl",
        "models/gibs/metal_gib4.mdl",
        "models/gibs/metal_gib5.mdl"
    }
}

-- Spawn debris gibs flying in a direction
function ws.doors.SpawnDebris(pos, velocity, material, count)
    local gibModels = ws.doors.gibs[material] or ws.doors.gibs.wood
    count = count or 6

    for _ = 1, count do
        local gib = ents.Create("prop_physics")
        if not IsValid(gib) then continue end

        gib:SetModel(gibModels[math.random(#gibModels)])
        gib:SetPos(pos + VectorRand() * 20)
        gib:SetAngles(AngleRand())
        gib:Spawn()
        gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        local phys = gib:GetPhysicsObject()
        if IsValid(phys) then
            -- Add randomized velocity based on blast direction
            local gibVel = velocity + VectorRand() * 150
            gibVel.z = gibVel.z + math.random(50, 150)  -- Add upward force
            phys:SetVelocity(gibVel)
            phys:AddAngleVelocity(VectorRand() * 500)
        end

        -- Gibs fade and remove after a delay
        local fadeTime = math.random(8, 15)
        timer.Simple(fadeTime, function()
            if IsValid(gib) then
                local alpha = 255
                local color = gib:GetColor()
                timer.Create("gibFade" .. gib:EntIndex() .. "_" .. CurTime(), 0.05, 50, function()
                    if IsValid(gib) then
                        alpha = alpha - 5
                        gib:SetColor(ColorAlpha(color, math.max(0, alpha)))
                        if alpha <= 0 then
                            gib:Remove()
                        end
                    end
                end)
            end
        end)
    end
end

-- Spawn dust/debris particle effect
function ws.doors.SpawnBreachEffect(pos, material)
    -- Dust cloud effect
    local effectData = EffectData()
    effectData:SetOrigin(pos)
    effectData:SetScale(2)
    effectData:SetMagnitude(3)

    if material == "wood" then
        util.Effect("GlassImpact", effectData)
        util.Effect("WheelDust", effectData)
    else
        util.Effect("MetalSpark", effectData)
        util.Effect("cball_bounce", effectData)
    end

    -- Additional debris effect
    effectData:SetScale(1.5)
    util.Effect("propspawn", effectData)
end

-- Breach a door with explosive force (battering ram)
-- PERMANENTLY DESTROYS the door - creates debris, effects, and fading dummy debris
-- Door frame is left empty until a new door is installed
function ws.doors.BreachDoor(door, velocity, bIgnorePartner)
    if not IsValid(door) then return end
    if not door:IsDoor() then return end

    velocity = velocity or Vector(0, 0, 0)

    -- Handle partner door (double doors breach together)
    local partner = door:GetDoorPartner()
    if IsValid(partner) and not bIgnorePartner then
        ws.doors.BreachDoor(partner, velocity, true)
    end

    -- Get door properties before destruction
    local pos = door:GetPos()
    local ang = door:GetAngles()
    local model = door:GetModel()
    local color = door:GetColor()
    local doorMaterial = door:GetMaterial()
    local skin = door:GetSkin() or 0
    local config = ws.doors.GetTypeConfig(door)
    local matType = config.material or "wood"
    local frameID = door.wsFrameID

    -- Spawn debris gibs
    ws.doors.SpawnDebris(pos + Vector(0, 0, 40), velocity, matType, math.random(5, 8))

    -- Spawn particle effects
    ws.doors.SpawnBreachEffect(pos + Vector(0, 0, 40), matType)

    -- Create damaged dummy prop (debris flying off - NOT the actual door)
    local dummy = ents.Create("prop_physics")
    if IsValid(dummy) then
        dummy:SetModel(model)
        dummy:SetPos(pos)
        dummy:SetAngles(ang)
        dummy:Spawn()
        dummy:SetSkin(skin)
        dummy:SetMaterial(doorMaterial)
        dummy:SetRenderMode(RENDERMODE_TRANSALPHA)
        dummy:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        -- Darken the dummy to look damaged/destroyed
        local damagedColor = Color(
            math.max(0, color.r - 80),
            math.max(0, color.g - 80),
            math.max(0, color.b - 80),
            color.a
        )
        dummy:SetColor(damagedColor)

        -- Copy bodygroups
        for _, v in ipairs(door:GetBodyGroups() or {}) do
            dummy:SetBodygroup(v.id, door:GetBodygroup(v.id))
        end

        -- Apply velocity - door flies away from the breach
        local phys = dummy:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(velocity)
            phys:AddAngleVelocity(VectorRand() * 150)
        end

        -- Dummy is just debris - fades and disappears after 20-30 seconds
        local fadeDelay = math.random(20, 30)
        timer.Simple(fadeDelay, function()
            if IsValid(dummy) then
                local fadeAlpha = 255
                timer.Create("dummyFade" .. dummy:EntIndex(), 0.1, 50, function()
                    if IsValid(dummy) then
                        fadeAlpha = fadeAlpha - 5
                        dummy:SetColor(ColorAlpha(damagedColor, math.max(0, fadeAlpha)))
                        if fadeAlpha <= 0 then
                            dummy:Remove()
                        end
                    end
                end)
            end
        end)
    end

    -- Clear frame reference - door is DESTROYED, frame is now empty
    if frameID then
        local mapID = tonumber(frameID)
        if mapID and ws.doors.frames[mapID] then
            ws.doors.frames[mapID].hasDoor = false
            ws.doors.frames[mapID].doorEntity = nil
        end
    end

    -- Remove the actual door entity
    door:Remove()

    -- Sync and save - frame is now empty
    ws.doors.SyncToAll()
    ws.doors.Save()

    return dummy
end
