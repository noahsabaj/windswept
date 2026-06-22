--[[
    Door health: applying damage (fist/ram aware), destruction, and full repair.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- Damage a door
function ws.doors.DamageDoor(door, damage, attacker, inflictor)
    if not IsValid(door) then return end

    local config = ws.doors.GetTypeConfig(door)

    -- Classify the damage source via the schema-registered registry (no hardcoded
    -- weapon class names in the engine). (layer-doors)
    local source = ws.doors.damageSources[IsValid(inflictor) and inflictor:GetClass() or ""] or {}

    -- Check if fist damage (and if allowed)
    if source.fist then
        if not config.fistDamageable then
            if IsValid(attacker) and attacker:IsPlayer() then
                attacker:NotifyLocalized("doorCantPunch")
            end
            door:EmitSound("physics/metal/metal_solid_impact_hard1.wav", 50)
            return
        end
        damage = 1  -- 1 HP per punch
    end

    -- Check if battering ram
    if source.ram then
        damage = damage * config.ramResistance
    end

    -- Apply damage
    door.wsHealth = (door.wsHealth or config.maxHealth) - damage

    -- Damage sound
    if config.material == "wood" then
        door:EmitSound("physics/wood/wood_plank_impact_hard" .. math.random(1, 4) .. ".wav", 60)
    else
        door:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 60)
    end

    -- Check for destruction
    if door.wsHealth <= 0 then
        ws.doors.DestroyDoor(door, attacker)
    else
        ws.doors.Save()
    end
end

-- Destroy a door
function ws.doors.DestroyDoor(door, attacker)
    if not IsValid(door) then return end

    local config = ws.doors.GetTypeConfig(door)

    -- Play destruction sound
    if config.material == "wood" then
        door:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 5) .. ".wav", 80)
    else
        door:EmitSound("physics/metal/metal_box_break" .. math.random(1, 2) .. ".wav", 80)
    end

    -- Spawn debris effect
    local effectData = EffectData()
    effectData:SetOrigin(door:GetPos())
    effectData:SetScale(1)
    util.Effect("propspawn", effectData)

    -- Clear frame reference
    local frameID = door.wsFrameID
    if frameID then
        local mapID = tonumber(frameID)
        if mapID and ws.doors.frames[mapID] then
            ws.doors.frames[mapID].hasDoor = false
            ws.doors.frames[mapID].doorEntity = nil
        end
    end

    -- Remove door
    door:Remove()

    -- Sync and save
    ws.doors.SyncToAll()
    ws.doors.Save()
end
-- Repair a door to full health (also resets battering ram hit counter)
function ws.doors.RepairDoor(door)
    if not IsValid(door) then return false end
    local config = ws.doors.GetTypeConfig(door)
    door.wsHealth = config.maxHealth

    -- Reset battering ram damage - door is fully repaired
    door.wsBatteringRamRequired = nil
    door.wsBatteringRamHits = nil

    ws.doors.Save()
    return true
end
