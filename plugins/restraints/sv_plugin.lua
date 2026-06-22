--[[
    Restraint System - Server Side

    Handles:
    - Ziptie restraining
    - Untying mechanics
    - Gagging mechanics
    - Drag mechanics
    - Leash mechanics (tie to surfaces)
]]--

util.AddNetworkString("wsDragStart")
util.AddNetworkString("wsDragStop")
util.AddNetworkString("wsLeashStart")
util.AddNetworkString("wsLeashStop")

-- Store reference to plugin for use in net.Receive handlers
-- (PLUGIN global is only available during initial load)
local restraintPlugin = PLUGIN

-- Track active drags for efficient Think iteration (avoid scanning all players)
PLUGIN.activeDrags = PLUGIN.activeDrags or {}

-- Give Hands Up weapon to all players on spawn
function PLUGIN:PostPlayerLoadout(client)
    client:Give("ws_handsup")
end

-- Handle untying when using a restricted player
-- Note: untie/unleash is an intentionally communal action -- any nearby,
-- unrestricted player can free a restrained prisoner (no authority/faction gate).
-- The CanInteractClose check below bounds it to arm's reach for symmetry with the
-- gag/drag/leash handlers. (sc-prisoner-restraints-6)
function PLUGIN:PlayerUse(client, entity)
    if not IsValid(entity) or not entity:IsPlayer() then return end
    if client:IsRestricted() then return end
    if not entity:IsRestricted() then return end
    if entity:GetNetVar("untying") then return end

    -- Explicit range re-check (PlayerUse already implies proximity). (sc-prisoner-restraints-6)
    if not ws.access.CanInteractClose(client, entity) then return end

    -- Check if target is leashed - offer unleash instead
    if entity:GetNetVar("leashed") then
        -- Unleash the player
        self:UnleashPlayer(entity)
        client:Notify("You have unleashed " .. entity:Name() .. ".")
        entity:Notify("You have been unleashed.")
        return
    end

    -- Start untie action
    entity:SetAction("@beingUntied", 5)
    entity:SetNetVar("untying", true)
    client:SetAction("@untying", 5)

    client:DoStaredAction(entity, function()
        -- Success - untie the player
        entity:SetRestricted(false)
        entity:SetNetVar("untying", nil)
        entity:SetNetVar("gagged", nil)
        entity:NotifyLocalized("unrestrained")

        -- Give the zip tie to the untier; if their inventory has no room, drop it
        -- to the ground so the recovered ziptie is never silently lost. (sc-prisoner-restraints-5)
        local _, inventory = ws.access.GetCharacterInventory(client)
        if inventory then
            local bSuccess = inventory:Add("ziptie", 1)

            if (bSuccess) then
                client:NotifyLocalized("zipTieRecovered")
            elseif IsValid(client) then
                ws.item.Spawn("ziptie", client:GetItemDropPos())
                client:NotifyLocalized("noFit")
            end
        end
    end, 5, function()
        -- Cancelled
        if IsValid(entity) then
            entity:SetNetVar("untying", nil)
            entity:SetAction()
        end
        if IsValid(client) then
            client:SetAction()
        end
    end)
end

-- Handle gagging when pressing R (reload) while looking at a restricted player
function PLUGIN:KeyPress(client, key)
    if key ~= IN_RELOAD then return end
    if client:IsRestricted() then return end

    local target = client:GetEyeTrace().Entity
    if not IsValid(target) or not target:IsPlayer() then return end
    if not target:IsRestricted() then return end

    -- Must be within interaction range
    if not ws.access.CanInteractClose(client, target) then return end

    -- Rate limit gag toggling to stop sound/notify spam. (sc-prisoner-restraints-4)
    if (target.wsNextGagToggle or 0) > CurTime() then return end
    target.wsNextGagToggle = CurTime() + 1

    -- Toggle gag state
    local gagged = target:GetNetVar("gagged", false)
    target:SetNetVar("gagged", not gagged)

    if not gagged then
        target:NotifyLocalized("gagged")
        client:Notify("You have gagged " .. target:Name() .. ".")
        target:EmitSound("physics/body/body_medium_impact_soft1.wav")
    else
        target:NotifyLocalized("ungagged")
        client:Notify("You have removed the gag from " .. target:Name() .. ".")
    end
end

-- Block gagged players from talking
function PLUGIN:PlayerCanHearPlayersVoice(listener, talker)
    if talker:GetNetVar("gagged") then
        return false, false
    end
end

-- Block chat for gagged players
function PLUGIN:PrePlayerMessageSend(speaker, chatType, text, anonymous, receivers)
    if speaker:GetNetVar("gagged") then
        speaker:NotifyLocalized("cannotSpeakGagged")
        return false
    end
end

-- Clean up on disconnect
function PLUGIN:PlayerDisconnected(client)
    -- Stop any active drag (this player as dragger)
    self:StopDrag(client)

    -- Also check if this player was being dragged
    local draggedBy = client:GetNetVar("wsDraggedBy")
    if draggedBy then
        local dragger = Entity(draggedBy)
        if IsValid(dragger) then
            self:StopDrag(dragger)
        end
    end

    -- Unleash if leashed
    if client:GetNetVar("leashed") then
        self:UnleashPlayer(client)
    end
end

-- ============================================================================
-- DRAG MECHANIC
-- ============================================================================

-- Start dragging a restrained player
function PLUGIN:StartDrag(dragger, target)
    if not IsValid(dragger) or not IsValid(target) then return false end
    if not target:IsRestricted() then return false end
    if dragger:IsRestricted() then return false end

    -- Can't drag a leashed player
    if target:GetNetVar("leashed") then
        dragger:Notify("You must unleash them first.")
        return false
    end

    -- Must be holding ws_hands weapon
    local weapon = dragger:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "ws_hands" then return false end

    -- Hands must be lowered (not raised)
    if dragger:IsWepRaised() then return false end

    -- Check if dragger is already dragging someone
    if dragger:GetNetVar("wsDragging") then return false end

    -- Check if target is already being dragged
    if target:GetNetVar("wsDraggedBy") then return false end

    -- Check distance
    if not ws.access.CanInteractClose(dragger, target) then return false end

    -- Set drag state
    dragger:SetNetVar("wsDragging", target:EntIndex())
    target:SetNetVar("wsDraggedBy", dragger:EntIndex())

    -- Track in active drags table for efficient Think iteration
    self.activeDrags[dragger] = target

    -- Store original speeds to restore later
    dragger.wsOriginalRunSpeed = dragger:GetRunSpeed()
    target.wsOriginalWalkSpeed = target:GetWalkSpeed()
    target.wsOriginalRunSpeed = target:GetRunSpeed()

    -- Dragger can't sprint while dragging
    dragger:SetRunSpeed(dragger:GetWalkSpeed())

    -- Target moves at snail's pace
    target:SetWalkSpeed(30)
    target:SetRunSpeed(30)

    -- Play grab sound
    dragger:EmitSound("physics/body/body_medium_impact_soft2.wav", 60)

    return true
end

-- Stop dragging
function PLUGIN:StopDrag(dragger)
    if not IsValid(dragger) then return end

    local targetIndex = dragger:GetNetVar("wsDragging")
    if not targetIndex then return end

    local target = Entity(targetIndex)

    -- Remove from active drags tracking
    self.activeDrags[dragger] = nil

    -- Restore dragger speed
    if dragger.wsOriginalRunSpeed then
        dragger:SetRunSpeed(dragger.wsOriginalRunSpeed)
        dragger.wsOriginalRunSpeed = nil
    end

    -- Restore target speed (if still valid and restrained)
    if IsValid(target) then
        if target.wsOriginalWalkSpeed then
            target:SetWalkSpeed(target.wsOriginalWalkSpeed)
            target.wsOriginalWalkSpeed = nil
        end
        if target.wsOriginalRunSpeed then
            target:SetRunSpeed(target.wsOriginalRunSpeed)
            target.wsOriginalRunSpeed = nil
        end
        target:SetNetVar("wsDraggedBy", nil)
    end

    dragger:SetNetVar("wsDragging", nil)
end

-- Think hook for drag physics
-- Optimized: only iterate active drags instead of all players
function PLUGIN:Think()
    for dragger, target in pairs(self.activeDrags) do
        -- Validate dragger still valid
        if not IsValid(dragger) then
            self.activeDrags[dragger] = nil
        -- Validate target still valid and restrained
        elseif not IsValid(target) or not target:IsPlayer() or not target:IsRestricted() then
            self:StopDrag(dragger)
        -- Check dragger still has hands equipped and lowered
        elseif not IsValid(dragger:GetActiveWeapon()) or dragger:GetActiveWeapon():GetClass() ~= "ws_hands" then
            self:StopDrag(dragger)
        elseif dragger:IsWepRaised() then
            self:StopDrag(dragger)
        else
            local distance = dragger:GetPos():Distance(target:GetPos())

            -- Break drag if too far (150 units)
            if distance > 150 then
                self:StopDrag(dragger)
                dragger:Notify("You lost your grip.")
            elseif distance > 48 and target:IsOnGround() then
                -- Pull target toward dragger. Flatten the pull to the horizontal
                -- plane and only apply while grounded so the drag can't be used as
                -- a launch/clip exploit. (sc-prisoner-restraints-8)
                local direction = (dragger:GetPos() - target:GetPos())
                direction.z = 0
                direction:Normalize()
                local pullStrength = math.Clamp((distance - 48) * 3, 50, 200)
                target:SetVelocity(direction * pullStrength)
            end
        end
    end
end

-- ============================================================================
-- LEASH MECHANIC
-- ============================================================================

-- Leash a restrained player to a surface
function PLUGIN:LeashPlayer(client, target, hitPos, hitNormal)
    if not IsValid(target) or not target:IsPlayer() then return false end
    if not target:IsRestricted() then return false end
    if target:GetNetVar("leashed") then return false end

    -- Stop any active drag first
    local draggedBy = target:GetNetVar("wsDraggedBy")
    if draggedBy then
        local dragger = Entity(draggedBy)
        if IsValid(dragger) then
            self:StopDrag(dragger)
        end
    end

    -- Store leash data
    target:SetNetVar("leashed", true)
    target:SetNetVar("leashPos", hitPos)
    target:SetNetVar("leashNormal", hitNormal)

    -- Freeze movement completely
    target:SetMoveType(MOVETYPE_NONE)

    -- Position them near the leash point
    local offset = hitNormal * 40
    target:SetPos(hitPos + offset)

    -- Face away from wall
    local ang = hitNormal:Angle()
    ang.p = 0
    target:SetEyeAngles(ang)

    target:EmitSound("physics/metal/chain_impact_soft1.wav")
    return true
end

-- Release a leashed player
function PLUGIN:UnleashPlayer(target)
    if not IsValid(target) or not target:IsPlayer() then return false end
    if not target:GetNetVar("leashed") then return false end

    target:SetNetVar("leashed", nil)
    target:SetNetVar("leashPos", nil)
    target:SetNetVar("leashNormal", nil)

    -- Restore movement (still restricted, just not anchored)
    target:SetMoveType(MOVETYPE_WALK)

    target:EmitSound("physics/metal/chain_impact_soft2.wav")
    return true
end

-- ============================================================================
-- HOOKS
-- ============================================================================

-- Stop drag and unleash when target is unrestrained
hook.Add("OnPlayerUnRestricted", "wsStopDragOnUnrestrain", function(target)
    local plugin = ws.plugin.Get("prisoner")
    if not plugin then return end

    -- Stop drag
    local draggedBy = target:GetNetVar("wsDraggedBy")
    if draggedBy then
        local dragger = Entity(draggedBy)
        if IsValid(dragger) then
            plugin:StopDrag(dragger)
        end
    end

    -- Unleash if leashed
    if target:GetNetVar("leashed") then
        plugin:UnleashPlayer(target)
    end
end)

-- ============================================================================
-- NETWORK RECEIVERS
-- ============================================================================

-- Rate limit drag initiation. (sc-prisoner-restraints-1)
-- target=true + range="close" replaces the inline ReadEntity + range checks inside
-- StartDrag (which still re-validates as defense-in-depth).
ws.action.Register("wsDragStart", {
    target = true,
    range = "close",
    rateLimit = 0.3,
    run = function(client, ctx)
        if restraintPlugin then
            restraintPlugin:StartDrag(client, ctx.target)
        end
    end
})

-- Stop drag operates on the dragger's own netvar; no target is sent over the wire.
ws.action.Register("wsDragStop", {
    run = function(client, ctx)
        if restraintPlugin then
            restraintPlugin:StopDrag(client)
        end
    end
})

ws.action.Register("wsLeashStart", {
    target = true,
    range = "close",
    -- Rate limit: prevents spam-leashing a target. (sc-prisoner-restraints-1)
    rateLimit = 0.5,
    onValidate = function(client, ctx)
        if client:IsRestricted() then return false end
        if not ctx.target:IsPlayer() then return false end
    end,
    run = function(client, ctx)
        local target = ctx.target

        -- Trace from client to find surface
        local tr = util.TraceLine({
            start = client:EyePos(),
            endpos = client:EyePos() + client:GetAimVector() * 200,
            filter = {client, target}
        })

        if not tr.Hit then
            client:Notify("No surface found to leash to.")
            return
        end

        if restraintPlugin:LeashPlayer(client, target, tr.HitPos, tr.HitNormal) then
            client:Notify("You have leashed " .. target:Name() .. " to the surface.")
            target:Notify("You have been leashed to a surface.")
        end
    end
})

ws.action.Register("wsLeashStop", {
    target = true,
    range = "close",
    onValidate = function(client, ctx)
        if client:IsRestricted() then return false end
        if not ctx.target:IsPlayer() then return false end
    end,
    run = function(client, ctx)
        local target = ctx.target

        if restraintPlugin:UnleashPlayer(target) then
            client:Notify("You have unleashed " .. target:Name() .. ".")
            target:Notify("You have been unleashed.")
        end
    end
})
