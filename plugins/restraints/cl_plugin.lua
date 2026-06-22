--[[
    Restraint System - Client Side

    Handles:
    - Blindness effect when gagged
    - Restrained player status indicators
    - Drag input detection
    - Leash input detection
    - Leash visual indicator
]]--

-- Blindness effect when gagged (like a bag over the head)
-- Knockout screen takes priority - gag persists but blindness yields to knockout UI
function PLUGIN:RenderScreenspaceEffects()
    if not LocalPlayer():GetNetVar("gagged") then return end

    -- Check if knocked out - knockout screen takes priority
    local permadeath = ws.plugin.list["permadeath"]
    if permadeath and permadeath.IsLocalPlayerKnockedOut and permadeath:IsLocalPlayerKnockedOut() then
        return
    end

    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = -1,
        ["$pp_colour_contrast"] = 0,
        ["$pp_colour_colour"] = 0,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    })
end

-- Block HUD when gagged (knockout screen takes priority)
function PLUGIN:HUDShouldDraw(name)
    if not LocalPlayer():GetNetVar("gagged") then return end

    -- Check if knocked out - knockout handles its own HUD blocking
    local permadeath = ws.plugin.list["permadeath"]
    if permadeath and permadeath.IsLocalPlayerKnockedOut and permadeath:IsLocalPlayerKnockedOut() then
        return
    end

    if name ~= "CHudGMod" then
        return false
    end
end

-- ============================================================================
-- RESTRAINED PLAYER STATUS & ACTION HINTS
-- ============================================================================

-- Draw [RESTRAINED] status and action hints when looking at restrained player
hook.Add("HUDDrawTargetID", "wsRestrainedTargetID", function()
    local client = LocalPlayer()
    local trace = client:GetEyeTrace()
    local target = trace.Entity

    -- Must be looking at a valid player
    if not IsValid(target) or not target:IsPlayer() then return end

    -- Must be within interaction range (96 units like Windswept default)
    if trace.HitPos:Distance(client:GetShootPos()) > 96 then return end

    -- Must be restrained
    if not target:IsRestricted() then return end

    -- Get screen position (use EyePos for head level, then offset up a bit)
    local worldPos = target:EyePos() + Vector(0, 0, 10)
    local pos = worldPos:ToScreen()
    if not pos.visible then return end

    -- Draw [RESTRAINED] status
    local statusText = "[RESTRAINED]"
    local statusColor = Color(255, 150, 50)  -- Orange
    draw.SimpleTextOutlined(statusText, "wsMediumFont", pos.x, pos.y, statusColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))

    local yOffset = 30

    -- Draw [GAGGED] if gagged
    if target:GetNetVar("gagged") then
        draw.SimpleTextOutlined("[GAGGED]", "wsSmallFont", pos.x, pos.y + yOffset, Color(200, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
        yOffset = yOffset + 25
    end

    -- Draw [LEASHED] if leashed
    if target:GetNetVar("leashed") then
        draw.SimpleTextOutlined("[LEASHED]", "wsSmallFont", pos.x, pos.y + yOffset, Color(150, 150, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
        yOffset = yOffset + 25
    end

    -- Don't show action hints if we're also restrained
    if client:IsRestricted() then return end

    -- Draw action hints
    local gagText = target:GetNetVar("gagged") and "Ungag" or "Gag"
    local isLeashed = target:GetNetVar("leashed")

    -- Check if we're currently dragging this target
    local isDragging = client:GetNetVar("wsDragging") == target:EntIndex()

    if isDragging then
        draw.SimpleTextOutlined("Release LMB: Stop dragging", "wsSmallFont", pos.x, pos.y + yOffset, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
    elseif isLeashed then
        -- Leashed player - show unleash hint
        draw.SimpleTextOutlined("E: Unleash | R: " .. gagText, "wsSmallFont", pos.x, pos.y + yOffset, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
    else
        -- Not leashed - show untie/drag/leash hints
        draw.SimpleTextOutlined("E: Untie | R: " .. gagText, "wsSmallFont", pos.x, pos.y + yOffset, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
        yOffset = yOffset + 25

        -- Show drag/leash hint only if holding hands and lowered
        local weapon = client:GetActiveWeapon()
        if IsValid(weapon) and weapon:GetClass() == "ws_hands" and not client:IsWepRaised() then
            draw.SimpleTextOutlined("Hold LMB: Drag | Hold RMB: Leash", "wsSmallFont", pos.x, pos.y + yOffset, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
        end
    end
end)

-- ============================================================================
-- LEASH VISUAL INDICATOR
-- ============================================================================

-- Draw a rope/chain line from leashed players to their anchor point
hook.Add("PostDrawOpaqueRenderables", "wsLeashVisual", function()
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetNetVar("leashed") then
            local leashPos = ply:GetNetVar("leashPos")
            if leashPos then
                -- Draw a simple line (chain effect)
                local playerPos = ply:GetPos() + Vector(0, 0, 40)  -- Chest height

                render.SetMaterial(Material("cable/rope"))
                render.DrawBeam(playerPos, leashPos, 2, 0, 1, Color(100, 80, 60, 255))
            end
        end
    end
end)

-- ============================================================================
-- DRAG INPUT DETECTION
-- ============================================================================

local wasLMBDown = false
local wasRMBDown = false
local currentDragTarget = nil
local cachedDraggingState = nil  -- Cache to avoid GetNetVar every frame
local lastDragCheckTime = 0
local DRAG_CHECK_INTERVAL = 0.1  -- Only check NetVar every 0.1 seconds

-- Leash action tracking
local leashHoldStart = nil
local LEASH_HOLD_TIME = 1.0  -- Hold RMB for 1 second to leash

hook.Add("Think", "wsDragInput", function()
    local client = LocalPlayer()
    if not IsValid(client) then return end

    -- Don't process input if UI is open
    if vgui.CursorVisible() then
        wasLMBDown = false
        wasRMBDown = false
        leashHoldStart = nil
        return
    end

    -- Can't drag/leash if we're restrained
    if client:IsRestricted() then
        wasLMBDown = false
        wasRMBDown = false
        leashHoldStart = nil
        return
    end

    -- Must be holding ws_hands weapon
    local weapon = client:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "ws_hands" then
        wasLMBDown = false
        wasRMBDown = false
        leashHoldStart = nil
        return
    end

    -- Hands must be lowered (not raised)
    if client:IsWepRaised() then
        wasLMBDown = false
        wasRMBDown = false
        leashHoldStart = nil
        return
    end

    local lmbDown = input.IsMouseDown(MOUSE_LEFT)
    local rmbDown = input.IsMouseDown(MOUSE_RIGHT)

    -- Throttle NetVar lookup - only check periodically or on input change
    local now = CurTime()
    if lmbDown ~= wasLMBDown or now - lastDragCheckTime > DRAG_CHECK_INTERVAL then
        cachedDraggingState = client:GetNetVar("wsDragging")
        lastDragCheckTime = now
    end

    -- ==================== DRAG (LMB) ====================
    if lmbDown then
        if not wasLMBDown and not cachedDraggingState then
            -- Just pressed LMB - check if looking at restrained player
            local trace = client:GetEyeTrace()
            local target = trace.Entity

            if IsValid(target) and target:IsPlayer() and target:IsRestricted() then
                if trace.HitPos:Distance(client:GetShootPos()) <= 96 then
                    -- Can't drag if leashed
                    if not target:GetNetVar("leashed") then
                        -- Start dragging
                        currentDragTarget = target
                        ws.action.Send("wsDragStart", nil, target)
                        cachedDraggingState = target:EntIndex()  -- Optimistic update
                    end
                end
            end
        end
    else
        if wasLMBDown and cachedDraggingState then
            -- Released LMB while dragging - stop
            ws.action.Send("wsDragStop")
            currentDragTarget = nil
            cachedDraggingState = nil  -- Optimistic update
        end
    end

    -- ==================== LEASH (RMB Hold) ====================
    if rmbDown then
        if not wasRMBDown then
            -- Just pressed RMB - check if looking at restrained player
            local trace = client:GetEyeTrace()
            local target = trace.Entity

            if IsValid(target) and target:IsPlayer() and target:IsRestricted() and not target:GetNetVar("leashed") then
                if trace.HitPos:Distance(client:GetShootPos()) <= 96 then
                    -- Start leash hold
                    leashHoldStart = now
                end
            else
                leashHoldStart = nil
            end
        elseif leashHoldStart then
            -- Holding RMB - check if hold time reached
            if now - leashHoldStart >= LEASH_HOLD_TIME then
                -- Leash the target
                local trace = client:GetEyeTrace()
                local target = trace.Entity

                if IsValid(target) and target:IsPlayer() and target:IsRestricted() then
                    ws.action.Send("wsLeashStart", nil, target)
                end

                leashHoldStart = nil  -- Reset so we don't spam
            end
        end
    else
        leashHoldStart = nil
    end

    wasLMBDown = lmbDown
    wasRMBDown = rmbDown
end)

-- ============================================================================
-- LEASH PROGRESS INDICATOR
-- ============================================================================

hook.Add("HUDPaint", "wsLeashProgress", function()
    if not leashHoldStart then return end

    local client = LocalPlayer()
    local weapon = client:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "ws_hands" then return end
    if client:IsWepRaised() then return end

    local progress = (CurTime() - leashHoldStart) / LEASH_HOLD_TIME
    progress = math.Clamp(progress, 0, 1)

    -- Draw progress bar at center bottom
    local barW = 200
    local barH = 10
    local x = (ScrW() - barW) / 2
    local y = ScrH() * 0.6

    -- Background
    surface.SetDrawColor(30, 30, 30, 200)
    surface.DrawRect(x - 2, y - 2, barW + 4, barH + 4)

    -- Progress fill
    surface.SetDrawColor(150, 150, 200, 255)
    surface.DrawRect(x, y, barW * progress, barH)

    -- Text
    draw.SimpleText("Leashing...", "wsSmallFont", ScrW() / 2, y - 15, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end)
