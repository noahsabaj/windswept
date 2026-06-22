--[[
    ws_knocked Entity - Shared

    Represents a knocked out player's body.
    Can be revived, looted, dragged, and executed.
]]--

ENT.Type = "anim"
ENT.Base = "base_entity"
ENT.PrintName = "Knocked Out Body"
ENT.Category = "Windswept"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.RenderGroup = RENDERGROUP_BOTH

-- Network variables
function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "OwningPlayer")      -- Player who owns this body
    self:NetworkVar("Entity", 1, "CurrentReviver")    -- Player currently attempting revival
    self:NetworkVar("Int", 0, "CharacterID")          -- Character database ID
    self:NetworkVar("Int", 1, "InventoryID")          -- Inventory ID for looting
    self:NetworkVar("Int", 2, "KnockedSkin")          -- Player's skin
    self:NetworkVar("Float", 0, "TimerStart")         -- When knockout started (CurTime)
    self:NetworkVar("Float", 1, "TimerDuration")      -- Total duration
    self:NetworkVar("String", 0, "KnockedModel")      -- Player's model
    self:NetworkVar("String", 1, "CharacterName")     -- Character name (permanent, survives deletion)
    self:NetworkVar("Bool", 0, "Permadead")           -- Whether character is permanently dead
    self:NetworkVar("Float", 2, "BurnProgress")       -- Cremation progress in seconds (0-240)
end

-- Get remaining time on knockout timer
function ENT:GetRemainingTime()
    local elapsed = CurTime() - self:GetTimerStart()
    return math.max(0, self:GetTimerDuration() - elapsed)
end

-- Format remaining time as MM:SS
function ENT:GetFormattedTime()
    local remaining = self:GetRemainingTime()
    local minutes = math.floor(remaining / 60)
    local seconds = math.floor(remaining % 60)
    return string.format("%02d:%02d", minutes, seconds)
end

-- Check if someone is currently reviving this body
function ENT:IsBeingRevived()
    return IsValid(self:GetCurrentReviver())
end

-- Add to holdable classes for hands dragging
hook.Add("InitPostEntity", "wsKnockedHoldable", function()
    if ws and ws.allowedHoldableClasses then
        ws.allowedHoldableClasses["ws_knocked"] = true
    end
end)

-- Also add on entity creation in case InitPostEntity already fired
hook.Add("OnEntityCreated", "wsKnockedHoldableCheck", function(ent)
    if ent:GetClass() == "ws_knocked" then
        timer.Simple(0, function()
            if ws and ws.allowedHoldableClasses then
                ws.allowedHoldableClasses["ws_knocked"] = true
            end
        end)
    end
end)
