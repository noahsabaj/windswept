--[[
    Gamemode integration for managed doors: route the +use key and incoming damage,
    and synchronize double-door opening. These bridge the engine to the framework's
    door-use / damage / CanPlayerUseDoor hooks.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- Allow native prop_door_rotating +use on managed doors; block use of a hidden map door
-- (its frame has been taken over and its managed leaf is the real door). (layer-doors)
hook.Add("PlayerUse", "wsDoorsUse", function(client, entity)
    if not ws.config.Get("doorsEnabled") then return end
    if not IsValid(entity) then return end

    if entity.wsIsWindsweptDoor then
        return true
    end

    if entity:IsDoor() and entity:GetNoDraw() then
        return false
    end
end)

-- Managed doors only take damage from schema-registered sources (battering ram, fists),
-- routed through the durability/breach engine; all other damage to them is ignored. (layer-doors)
hook.Add("EntityTakeDamage", "wsDoorsDamage", function(target, dmgInfo)
    if not ws.config.Get("doorsEnabled") then return end
    if not target.wsIsWindsweptDoor then return end

    local inflictor = dmgInfo:GetInflictor()
    local source = ws.doors.damageSources[IsValid(inflictor) and inflictor:GetClass() or ""]
    if source then
        ws.doors.DamageDoor(target, dmgInfo:GetDamage(), dmgInfo:GetAttacker(), inflictor)
    end

    return true
end)

-- Double doors: open/close both leaves together for perfect sync. Single doors return
-- nil so the native +use handling takes over. (sc-schema-glue-11)
local doorActivatorCounter = 0

hook.Add("CanPlayerUseDoor", "wsDoorsDoubleSync", function(client, door)
    if not ws.config.Get("doorsEnabled") then return end
    if not IsValid(door) then return end

    -- Get the partner door (double doors are linked via wsPartner)
    local partner = door:GetDoorPartner()

    -- Single door - let native handling work
    if not IsValid(partner) then return end

    -- Double door - we handle it ourselves for perfect sync.
    -- m_eDoorState: 0=closed, 1=opening, 2=open, 3=closing
    local doorState = door:GetInternalVariable("m_eDoorState")
    if doorState == nil then return end

    if doorState == 0 then
        -- Both doors closed - open both away from the player
        local tempTarget = ents.Create("info_target")
        if IsValid(tempTarget) then
            doorActivatorCounter = doorActivatorCounter + 1 -- unique within the 0.1s window
            tempTarget:SetPos(client:GetPos())
            tempTarget:SetName("ws_door_activator_" .. client:EntIndex() .. "_" .. doorActivatorCounter)
            tempTarget:Spawn()

            door:Fire("OpenAwayFrom", tempTarget:GetName())
            partner:Fire("OpenAwayFrom", tempTarget:GetName())

            timer.Simple(0.1, function()
                if IsValid(tempTarget) then
                    tempTarget:Remove()
                end
            end)
        else
            -- Fallback: just fire open on both
            door:Fire("open")
            partner:Fire("open")
        end
    elseif doorState == 2 then
        -- Both doors open - close both
        door:Fire("close")
        partner:Fire("close")
    elseif doorState == 1 or doorState == 3 then
        -- Door is in motion (opening or closing) - ignore
        return false
    end

    -- Return false to PREVENT native door use - we handled it ourselves
    return false
end)
