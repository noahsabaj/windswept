--[[
    ws_knocked Entity - Client

    Handles rendering and tooltip display.
    Timer is hidden from non-owners.
]]--

include("shared.lua")

-- Enable entity info popup
ENT.PopulateEntityInfo = true

function ENT:Initialize()
    -- Nothing special needed client-side
end

function ENT:Draw()
    self:DrawModel()
end

-- ============================================================================
-- ENTITY INFO TOOLTIP
-- ============================================================================

function ENT:OnPopulateEntityInfo(tooltip)
    -- Title row (no name - fog of war, check their ID if you want to know who they are)
    local title = tooltip:AddRow("name")
    title:SetImportant()

    local burnProgress = self:GetBurnProgress()
    local isBurning = burnProgress and burnProgress > 0

    if self:GetPermadead() then
        if isBurning then
            title:SetText("[BURNING]")
            title:SetBackgroundColor(Color(200, 100, 0))
        else
            title:SetText("[DEAD]")
            title:SetBackgroundColor(Color(139, 0, 0))
        end
    else
        if isBurning then
            title:SetText("[KNOCKED OUT - BURNING]")
            title:SetBackgroundColor(Color(200, 100, 0))
        else
            title:SetText("[KNOCKED OUT]")
            title:SetBackgroundColor(Color(139, 69, 19))
        end
    end
    title:SizeToContents()

    -- Cremation progress (if burning)
    if isBurning then
        local duration = 240
        local cremationRow = tooltip:AddRow("cremation")
        cremationRow:SetText(string.format("Cremation: %d/%ds", math.floor(burnProgress), duration))
        cremationRow:SetBackgroundColor(Color(150, 75, 0))
        cremationRow:SizeToContents()
    end

    -- Instructions (no search when burning)
    if not isBurning then
        local instructions = tooltip:AddRow("instructions")
        if self:GetPermadead() then
            instructions:SetText("E: Search body")
        else
            instructions:SetText("E: Search body | Hold E: Attempt CPR")
        end
        instructions:SizeToContents()
    end
end

-- ============================================================================
-- TARGET ID (when looking at entity)
-- ============================================================================

function ENT:OnShouldDrawEntityInfo()
    return true
end

-- Helper to get the ws_knocked entity from a trace entity
-- Could be the ws_knocked entity directly or a prop_ragdoll linked to it
local function GetKnockedEntity(ent)
    if not IsValid(ent) then return nil end

    -- Direct ws_knocked entity
    if ent:GetClass() == "ws_knocked" then
        return ent
    end

    -- prop_ragdoll linked to ws_knocked (via networked variable)
    if ent:GetClass() == "prop_ragdoll" then
        local knockedEnt = ent:GetNetVar("wsKnockedEntity")
        if IsValid(knockedEnt) then
            return knockedEnt
        end
    end

    return nil
end

-- Track E key hold state for tap vs hold detection
local useKeyDownTime = nil
local useKeyTarget = nil
local reviveSent = false  -- Prevent sending multiple revive requests

-- Custom target ID drawing for knocked bodies (works with ragdolls)
hook.Add("HUDDrawTargetID", "wsKnockedTargetID", function()
    local client = LocalPlayer()
    local trace = client:GetEyeTrace()
    local knockedEnt = GetKnockedEntity(trace.Entity)

    if not knockedEnt then return end
    if trace.HitPos:Distance(client:GetShootPos()) > 200 then return end

    local pos = trace.Entity:GetPos():ToScreen()
    if not pos.visible then return end

    -- Draw status (no name - fog of war, check their ID if you want to know who they are)
    local burnProgress = knockedEnt:GetBurnProgress()
    local isBurning = burnProgress and burnProgress > 0

    local text, color
    if knockedEnt:GetPermadead() then
        if isBurning then
            text = "[BURNING]"
            color = Color(255, 150, 50)
        else
            text = "[DEAD]"
            color = Color(200, 50, 50)
        end
    else
        if isBurning then
            text = "[KNOCKED OUT - BURNING]"
            color = Color(255, 150, 50)
        else
            text = "[KNOCKED OUT]"
            color = Color(200, 150, 50)
        end
    end

    draw.SimpleTextOutlined(text, "wsMediumFont", pos.x, pos.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))

    -- Add cremation progress if burning
    if isBurning then
        local duration = 240
        local progressText = string.format("Cremation: %d/%ds", math.floor(burnProgress), duration)
        draw.SimpleTextOutlined(progressText, "wsSmallFont", pos.x, pos.y + 30, Color(255, 200, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
    else
        -- Draw action hints (only when not burning - can't search a burning body)
        local yOffset = 30
        draw.SimpleTextOutlined("E: Search body", "wsSmallFont", pos.x, pos.y + yOffset, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))

        -- Show CPR hint only if not dead and holding hands lowered
        if not knockedEnt:GetPermadead() then
            local weapon = client:GetActiveWeapon()
            if IsValid(weapon) and weapon:GetClass() == "ws_hands" and not client:IsWepRaised() then
                draw.SimpleTextOutlined("Hold LMB: Attempt CPR", "wsSmallFont", pos.x, pos.y + yOffset + 30, Color(100, 200, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
            end
        end
    end

    -- Draw hold progress bar if holding LMB for CPR on a knocked (not dead) target
    if useKeyDownTime and useKeyTarget == knockedEnt and not knockedEnt:GetPermadead() then
        local plugin = ws.plugin.Get("permadeath")
        local holdTime = plugin and plugin.reviveHoldTime or 1.5
        local progress = math.Clamp((RealTime() - useKeyDownTime) / holdTime, 0, 1)

        if progress > 0 and progress < 1 then
            local barWidth = 100
            local barHeight = 8
            local barX = pos.x - barWidth / 2
            local barY = pos.y + 90  -- Below all text hints

            -- Background
            surface.SetDrawColor(0, 0, 0, 200)
            surface.DrawRect(barX, barY, barWidth, barHeight)

            -- Progress fill
            surface.SetDrawColor(100, 200, 100, 255)
            surface.DrawRect(barX + 1, barY + 1, (barWidth - 2) * progress, barHeight - 2)

            -- Border
            surface.SetDrawColor(255, 255, 255, 100)
            surface.DrawOutlinedRect(barX, barY, barWidth, barHeight)
        end
    end
end)

-- ============================================================================
-- INTERACTION HANDLING (E = Loot, Hold LMB with hands = CPR)
-- ============================================================================

-- Track LMB state for CPR
local wasLMBDown = false
local cprTarget = nil
local cprStartTime = nil
local cprSent = false

-- Think hook for CPR (Hold LMB with hands lowered)
hook.Add("Think", "wsKnockedCPR", function()
    local client = LocalPlayer()
    if not IsValid(client) then return end

    -- Don't process input if UI is open
    if vgui.CursorVisible() then
        wasLMBDown = false
        cprTarget = nil
        cprStartTime = nil
        return
    end

    -- Trace to see what we're looking at
    local data = {
        start = client:GetShootPos(),
        endpos = client:GetShootPos() + client:GetAimVector() * 96,
        filter = client
    }
    local trace = util.TraceLine(data)
    local knockedEnt = GetKnockedEntity(trace.Entity)

    -- Check if looking at valid target within range
    local validTarget = IsValid(knockedEnt) and not knockedEnt:GetPermadead()

    -- Must be holding ws_hands weapon and lowered for CPR
    local weapon = client:GetActiveWeapon()
    local hasHandsLowered = IsValid(weapon) and weapon:GetClass() == "ws_hands" and not client:IsWepRaised()

    local lmbDown = input.IsMouseDown(MOUSE_LEFT)

    if lmbDown and validTarget and hasHandsLowered then
        if not wasLMBDown then
            -- Just started holding LMB
            cprStartTime = RealTime()
            cprTarget = knockedEnt
            cprSent = false
            -- Update the shared variables for HUD drawing
            useKeyDownTime = cprStartTime
            useKeyTarget = cprTarget
            reviveSent = false
        elseif cprTarget == knockedEnt then
            -- Still holding on same target
            local plugin = ws.plugin.Get("permadeath")
            local holdTime = plugin and plugin.reviveHoldTime or 1.5
            local heldDuration = RealTime() - cprStartTime

            -- Check if held long enough
            if heldDuration >= holdTime and not cprSent then
                -- Threshold reached, send revive request
                ws.action.Send("wsKnockoutRevive", nil, knockedEnt)

                cprSent = true
                reviveSent = true
            end
        else
            -- Changed target, reset
            cprStartTime = RealTime()
            cprTarget = knockedEnt
            cprSent = false
            useKeyDownTime = cprStartTime
            useKeyTarget = cprTarget
            reviveSent = false
        end
    else
        if wasLMBDown or not validTarget or not hasHandsLowered then
            -- Released LMB or lost target or switched weapon, reset
            cprStartTime = nil
            cprTarget = nil
            cprSent = false
            useKeyDownTime = nil
            useKeyTarget = nil
            reviveSent = false
        end
    end

    wasLMBDown = lmbDown
end)

-- ============================================================================
-- E KEY FOR LOOTING (via net message, since Windswept blocks PlayerUse for entities with GetEntityMenu)
-- ============================================================================

local wasUseDown = false
local lastLootTime = 0

hook.Add("Think", "wsKnockedLoot", function()
    local client = LocalPlayer()
    if not IsValid(client) then return end

    -- Don't process input if UI is open
    if vgui.CursorVisible() then
        wasUseDown = false
        return
    end

    local useDown = input.IsKeyDown(KEY_E)

    -- Edge detection: only trigger on press, not hold
    if useDown and not wasUseDown then
        -- Rate limit to prevent spam
        if RealTime() - lastLootTime < 0.5 then
            wasUseDown = useDown
            return
        end

        -- Trace to see what we're looking at
        local data = {
            start = client:GetShootPos(),
            endpos = client:GetShootPos() + client:GetAimVector() * 96,
            filter = client
        }
        local trace = util.TraceLine(data)
        local knockedEnt = GetKnockedEntity(trace.Entity)

        if IsValid(knockedEnt) then
            -- Send loot request
            ws.action.Send("wsKnockoutLoot", nil, knockedEnt)
            lastLootTime = RealTime()
        end
    end

    wasUseDown = useDown
end)

-- ============================================================================
-- CREMATION VISUAL FEEDBACK (Body Darkening)
-- ============================================================================

-- Cache for knocked ragdolls only (not ALL ragdolls)
-- Structure: { ragdoll = knockedEntity, ... }
local knockedRagdollCache = {}
local knockedRagdollCount = 0
local lastRagdollUpdate = 0
local RAGDOLL_CACHE_INTERVAL = 0.5

-- Pre-allocate color object to avoid GC pressure
local COLOR_WHITE = Color(255, 255, 255)
local CREMATION_DURATION = 240

-- Darken burning ragdolls based on cremation progress
hook.Add("PreDrawOpaqueRenderables", "wsKnockedBurnDarkening", function()
    local curTime = RealTime()

    -- Update cache periodically - only find KNOCKED ragdolls, not all ragdolls
    if curTime - lastRagdollUpdate > RAGDOLL_CACHE_INTERVAL then
        -- Clear old cache
        knockedRagdollCache = {}
        knockedRagdollCount = 0

        -- Only iterate ragdolls once per cache interval
        for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
            if IsValid(ragdoll) then
                local knockedEnt = ragdoll:GetNetVar("wsKnockedEntity")
                if IsValid(knockedEnt) then
                    knockedRagdollCache[ragdoll] = knockedEnt
                    knockedRagdollCount = knockedRagdollCount + 1
                end
            end
        end

        lastRagdollUpdate = curTime
    end

    -- Early return if no knocked ragdolls (common case - saves per-frame iteration)
    if knockedRagdollCount == 0 then return end

    -- Only process knocked ragdolls (not all ragdolls on map)
    for ragdoll, knockedEnt in pairs(knockedRagdollCache) do
        if not IsValid(ragdoll) or not IsValid(knockedEnt) then
            -- Stale cache entry, will be cleaned on next cache update
            continue
        end

        local burnProgress = knockedEnt:GetBurnProgress()
        if burnProgress and burnProgress > 0 then
            local progress = math.Clamp(burnProgress / CREMATION_DURATION, 0, 1)
            local darkness = 255 - (progress * 225)
            ragdoll:SetColor(Color(darkness, darkness, darkness))
        else
            -- Reset color if not burning (check first to avoid unnecessary SetColor)
            local curColor = ragdoll:GetColor()
            if curColor.r ~= 255 then
                ragdoll:SetColor(COLOR_WHITE)
            end
        end
    end
end)
