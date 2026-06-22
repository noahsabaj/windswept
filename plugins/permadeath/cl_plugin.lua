--[[
    Permadeath Plugin - Client Logic

    Handles knockout UI (black screen with timer),
    communication blocking, and audio effects.
]]--

-- Knockout state
local isKnockedOut = false
local knockoutStartTime = 0
local knockoutDuration = 0
local knockoutCount = 0

-- Memorial state
local memorialActive = false

-- ============================================================================
-- SUICIDE STATE MACHINE
-- ============================================================================

local suicideState = "idle"  -- idle, raising, raised
local suicideStartTime = 0
local suicideRaisedTime = 0
local suicideWasGDown = false
local suicideWasLMBDown = false
local SUICIDE_RAISE_DURATION = 5    -- Hold G for 5 seconds
local SUICIDE_TIMEOUT = 15          -- 15 seconds before auto-lower

-- Check if player has the right weapon equipped (no ammo check - can raise empty gun)
local function HasSuicideWeapon()
    local client = LocalPlayer()
    if not IsValid(client) then return false end
    if not client:Alive() then return false end

    local weapon = client:GetActiveWeapon()
    if not IsValid(weapon) then return false end
    if weapon:GetClass() ~= "tfa_ins2_wpn_38revolver" then return false end

    return true
end

local function ResetSuicideState()
    suicideState = "idle"
    suicideStartTime = 0
    suicideRaisedTime = 0
end

-- G key detection and state machine
hook.Add("Think", "wsSuicideGesture", function()
    local client = LocalPlayer()
    if not IsValid(client) then return end

    local gKeyDown = input.IsKeyDown(KEY_G)

    -- If weapon is switched/unequipped, always cancel
    if suicideState ~= "idle" and not HasSuicideWeapon() then
        ResetSuicideState()
        return
    end

    if suicideState == "idle" then
        -- Just need the weapon to start raising (no ammo check)
        if gKeyDown and HasSuicideWeapon() then
            suicideState = "raising"
            suicideStartTime = RealTime()
        end

    elseif suicideState == "raising" then
        -- Cancel only if released G
        if not gKeyDown then
            ResetSuicideState()
        elseif RealTime() - suicideStartTime >= SUICIDE_RAISE_DURATION then
            -- Completed raise
            suicideState = "raised"
            suicideRaisedTime = RealTime()
            ws.util.Notify("You have aimed the gun at your temple. Pull the trigger, or press G to lower the gun.")
        end

    elseif suicideState == "raised" then
        -- Check for G tap to lower
        if gKeyDown and not suicideWasGDown then
            ResetSuicideState()
            ws.util.Notify("You lower the gun.")
        elseif RealTime() - suicideRaisedTime >= SUICIDE_TIMEOUT then
            -- Check for timeout
            ResetSuicideState()
            ws.util.Notify("You lower the gun.")
        end

        -- Check for LMB - pull trigger (bang or click depending on ammo)
        if input.IsMouseDown(MOUSE_LEFT) and not suicideWasLMBDown then
            local weapon = client:GetActiveWeapon()
            if IsValid(weapon) and weapon:Clip1() >= 1 then
                -- Has ammo - execute suicide
                net.Start("wsSuicideExecute")
                net.SendToServer()
                ResetSuicideState()
            else
                -- No ammo - dry fire click, stay raised
                surface.PlaySound("weapons/clipempty_pistol.wav")
            end
        end
    end

    -- Track previous key states for edge detection
    suicideWasGDown = gKeyDown
    suicideWasLMBDown = input.IsMouseDown(MOUSE_LEFT)
end)

-- Vignette effect for suicide gesture
-- Optimized: reduced from 11 iterations (44 rects) to 4 iterations (16 rects)
hook.Add("HUDPaint", "wsSuicideVignette", function()
    if suicideState == "idle" then return end

    local alpha = 0

    if suicideState == "raising" then
        -- Progressive darkening over 5 seconds (0 to 180 alpha)
        local progress = math.Clamp((RealTime() - suicideStartTime) / SUICIDE_RAISE_DURATION, 0, 1)
        alpha = progress * 180
    elseif suicideState == "raised" then
        -- Stay dark
        alpha = 180
    end

    if alpha <= 0 then return end

    -- Draw vignette (darkening around edges)
    local scrW, scrH = ScrW(), ScrH()
    local minDim = math.min(scrW, scrH) * 0.3

    -- Draw gradient from edges (4 steps instead of 11 - visually similar, much faster)
    for i = 0, 3 do
        local frac = i / 3
        local edgeAlpha = alpha * frac
        local inset = (1 - frac) * minDim

        surface.SetDrawColor(0, 0, 0, edgeAlpha)
        -- Top
        surface.DrawRect(0, 0, scrW, inset)
        -- Bottom
        surface.DrawRect(0, scrH - inset, scrW, inset)
        -- Left
        surface.DrawRect(0, inset, inset, scrH - inset * 2)
        -- Right
        surface.DrawRect(scrW - inset, inset, inset, scrH - inset * 2)
    end
end)

-- Reset suicide state when weapon changes
hook.Add("HUDWeaponPickedUp", "wsSuicideWeaponChange", function()
    if suicideState ~= "idle" then
        ResetSuicideState()
    end
end)

hook.Add("PlayerSwitchWeapon", "wsSuicideWeaponSwitch", function(ply, oldWeapon, newWeapon)
    if ply == LocalPlayer() and suicideState ~= "idle" then
        ResetSuicideState()
    end
end)

-- ============================================================================
-- KNOCKOUT SCREEN PANEL
-- ============================================================================

local PANEL = {}

function PANEL:Init()
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    -- Enable mouse for the Give Up button, but don't use MakePopup() to allow ESC
    self:SetMouseInputEnabled(true)
    -- Show mouse cursor
    gui.EnableScreenClicker(true)

    self.startTime = RealTime()
    self.duration = 300
    self.knockoutNum = 1

    -- Create Give Up button (subtle, at bottom)
    self.giveUpButton = vgui.Create("DButton", self)
    self.giveUpButton:SetText(L("giveUp"))
    self.giveUpButton:SetFont("wsSmallFont")
    self.giveUpButton:SetSize(120, 30)
    self.giveUpButton:SetPos(ScrW() / 2 - 60, ScrH() - 160)
    self.giveUpButton:SetTextColor(Color(150, 150, 150))
    self.giveUpButton.Paint = function(btn, w, h)
        -- Subtle dark button
        surface.SetDrawColor(40, 40, 40, 200)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(80, 80, 80, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    self.giveUpButton.DoClick = function()
        self:ShowGiveUpConfirmation()
    end
end

function PANEL:ShowGiveUpConfirmation()
    -- Don't show if already showing
    if IsValid(self.confirmDialog) then return end

    -- Get text for sizing
    local confirmText = L("giveUpConfirm")
    local yesText = L("giveUpYes")
    local noText = L("giveUpNo")

    -- Calculate button sizes based on text
    surface.SetFont("wsSmallFont")
    local yesW = surface.GetTextSize(yesText) + 20  -- padding
    local noW = surface.GetTextSize(noText) + 20

    -- Calculate dialog width based on buttons
    local buttonPadding = 20
    local dialogWidth = math.max(350, yesW + noW + buttonPadding * 3)

    -- Create confirmation dialog (positioned below center so timer is visible)
    self.confirmDialog = vgui.Create("DPanel", self)
    self.confirmDialog:SetSize(dialogWidth, 120)
    self.confirmDialog:SetPos(ScrW() / 2 - dialogWidth / 2, ScrH() / 2 + 80)
    self.confirmDialog.Paint = function(pnl, w, h)
        surface.SetDrawColor(20, 20, 20, 250)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(100, 100, 100, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    -- Confirmation text
    local label = vgui.Create("DLabel", self.confirmDialog)
    label:SetText(confirmText)
    label:SetFont("wsMediumFont")
    label:SetTextColor(ws.constants.COLOR_UI_NEUTRAL)
    label:SizeToContents()
    label:SetPos(dialogWidth / 2 - label:GetWide() / 2, 20)

    -- Yes button
    local yesBtn = vgui.Create("DButton", self.confirmDialog)
    yesBtn:SetText(yesText)
    yesBtn:SetFont("wsSmallFont")
    yesBtn:SetSize(yesW, 30)
    yesBtn:SetPos(buttonPadding, 70)
    yesBtn:SetTextColor(Color(200, 100, 100))
    yesBtn.Paint = function(btn, w, h)
        surface.SetDrawColor(60, 30, 30, 255)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(120, 60, 60, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    yesBtn.DoClick = function()
        -- Send give up request to server
        net.Start("wsKnockoutGiveUp")
        net.SendToServer()

        -- Hide the Give Up button (can't give up twice)
        if IsValid(self.giveUpButton) then
            self.giveUpButton:Remove()
        end

        -- Close dialog
        if IsValid(self.confirmDialog) then
            self.confirmDialog:Remove()
            self.confirmDialog = nil
        end
    end

    -- No button
    local noBtn = vgui.Create("DButton", self.confirmDialog)
    noBtn:SetText(noText)
    noBtn:SetFont("wsSmallFont")
    noBtn:SetSize(noW, 30)
    noBtn:SetPos(dialogWidth - noW - buttonPadding, 70)
    noBtn:SetTextColor(Color(150, 150, 150))
    noBtn.Paint = function(btn, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(80, 80, 80, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    noBtn.DoClick = function()
        -- Close dialog
        if IsValid(self.confirmDialog) then
            self.confirmDialog:Remove()
            self.confirmDialog = nil
        end
    end
end

function PANEL:OnRemove()
    -- Hide mouse cursor
    gui.EnableScreenClicker(false)
    -- Clean up confirmation dialog if open
    if IsValid(self.confirmDialog) then
        self.confirmDialog:Remove()
        self.confirmDialog = nil
    end
end

function PANEL:SetKnockoutData(duration, knockoutNum)
    self.duration = duration
    self.knockoutNum = knockoutNum
    self.startTime = RealTime()
end

function PANEL:SyncTimer(newDuration)
    -- Timer was halved from damage - sync it
    self.duration = newDuration
    self.startTime = RealTime()
end

function PANEL:GetRemainingTime()
    local elapsed = RealTime() - self.startTime
    return math.max(0, self.duration - elapsed)
end

function PANEL:Paint(w, h)
    -- Full black background
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, w, h)

    -- Calculate remaining time
    local remaining = self:GetRemainingTime()
    local minutes = math.floor(remaining / 60)
    local seconds = math.floor(remaining % 60)
    local timeText = string.format("%02d:%02d", minutes, seconds)

    -- Draw centered timer
    surface.SetFont("wsMenuButtonHugeFont")
    local tw, th = surface.GetTextSize(timeText)
    surface.SetTextColor(255, 255, 255, 255)
    surface.SetTextPos(w / 2 - tw / 2, h / 2 - th / 2)
    surface.DrawText(timeText)

    -- Draw instruction at bottom
    local instructionText = "You are knocked out. Wait for rescue or death."
    surface.SetFont("wsSmallFont")
    local iw, ih = surface.GetTextSize(instructionText)
    surface.SetTextColor(100, 100, 100, 255)
    surface.SetTextPos(w / 2 - iw / 2, h - 100)
    surface.DrawText(instructionText)
end

function PANEL:Think()
    -- Keep panel on top
    self:MoveToFront()

    -- Timer expired (GetRemainingTime() <= 0): nothing to do client-side here;
    -- the server handles permadeath and sends wsKnockoutEnd.
end

vgui.Register("wsKnockoutScreen", PANEL, "DPanel")

-- ============================================================================
-- DEATH MEMORIAL SCREEN
-- ============================================================================

local MEMORIAL = {}

function MEMORIAL:Init()
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:MakePopup()
    self:SetKeyboardInputEnabled(true)

    memorialActive = true

    self.startTime = RealTime()
    self.canDismiss = false
    self.dismissed = false

    -- Data (set via SetMemorialData)
    self.charName = "Unknown"
    self.birthDate = "Unknown"
    self.deathDate = ws.birthdata.GetCurrentDate()
    self.model = "models/player/group01/male_01.mdl"
    self.skin = 0
    self.bodygroups = ""

    -- Calculate sizes based on fonts
    surface.SetFont("wsMediumFont")
    local _, headerH = surface.GetTextSize("You have died.")
    self.headerHeight = headerH

    surface.SetFont("wsBigFont")
    local _, nameH = surface.GetTextSize("W")
    self.nameHeight = nameH

    surface.SetFont("wsSmallFont")
    local _, smallH = surface.GetTextSize("W")
    self.smallHeight = smallH

    self.sectionGap = ScreenScale(16)
    self.modelSize = ScrH() * 0.35

    -- Calculate total content height for vertical centering
    -- Content: header + gap + model + gap + name + gap + lifespan
    self.totalContentHeight = self.headerHeight + self.sectionGap + self.modelSize + self.sectionGap + self.nameHeight + self.sectionGap + self.smallHeight
    self.contentStartY = (ScrH() - self.totalContentHeight) / 2
end

function MEMORIAL:SetMemorialData(charName, model, skin, bodygroups, birthMonth, birthDay, age)
    self.charName = charName
    self.model = model
    self.skin = skin
    self.bodygroups = bodygroups

    -- Format birth date
    self.birthDate = ws.birthdata.FormatDate(birthMonth, birthDay, age)
    self.deathDate = ws.birthdata.GetCurrentDate()

    -- Create model panel
    if IsValid(self.modelPanel) then
        self.modelPanel:Remove()
    end

    self.modelPanel = vgui.Create("wsModelPanel", self)
    self.modelPanel:SetModel(model, skin, bodygroups)
    self.modelPanel:SetSize(self.modelSize, self.modelSize)

    -- Center the model panel (vertically centered with content block)
    local modelX = (ScrW() - self.modelSize) / 2
    local modelY = self.contentStartY + self.headerHeight + self.sectionGap
    self.modelPanel:SetPos(modelX, modelY)

    -- Disable mouse interaction on model panel
    self.modelPanel:SetMouseInputEnabled(false)
end

function MEMORIAL:Paint(w, h)
    -- Pure black background
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, w, h)

    local centerX = w / 2
    local y = self.contentStartY  -- Vertically centered

    -- "You have died."
    surface.SetFont("wsMediumFont")
    local headerText = "You have died."
    local headerW, headerH = surface.GetTextSize(headerText)
    surface.SetTextColor(200, 200, 200, 255)
    surface.SetTextPos(centerX - headerW / 2, y)
    surface.DrawText(headerText)

    y = y + headerH + self.sectionGap + self.modelSize + self.sectionGap

    -- Character name
    surface.SetFont("wsBigFont")
    local nameW, nameH = surface.GetTextSize(self.charName)
    surface.SetTextColor(255, 255, 255, 255)
    surface.SetTextPos(centerX - nameW / 2, y)
    surface.DrawText(self.charName)

    y = y + nameH + self.sectionGap

    -- Lifespan
    surface.SetFont("wsSmallFont")
    local lifespanText = self.birthDate .. "  —  " .. self.deathDate
    local lifespanW, lifespanH = surface.GetTextSize(lifespanText)
    surface.SetTextColor(180, 180, 180, 255)
    surface.SetTextPos(centerX - lifespanW / 2, y)
    surface.DrawText(lifespanText)

    -- "Press any key to continue..." (only after 5 seconds)
    if self.canDismiss and not self.dismissed then
        local elapsed = RealTime() - self.startTime
        local promptAlpha = math.Clamp((elapsed - 5) * 255, 0, 255)  -- Fade in over 1 second

        surface.SetFont("wsSmallFont")
        local promptText = "Press any key to continue..."
        local promptW, promptH = surface.GetTextSize(promptText)
        surface.SetTextColor(150, 150, 150, promptAlpha)
        surface.SetTextPos(centerX - promptW / 2, h - self.sectionGap - promptH)
        surface.DrawText(promptText)
    end
end

function MEMORIAL:Think()
    local elapsed = RealTime() - self.startTime

    -- Enable dismissal after 5 seconds
    if elapsed >= 5 and not self.canDismiss then
        self.canDismiss = true
    end

    -- Keep panel on top
    self:MoveToFront()
end

function MEMORIAL:OnKeyCodePressed(key)
    if self.canDismiss and not self.dismissed then
        self.dismissed = true

        -- Notify server we're ready
        net.Start("wsPermadeathReady")
        net.SendToServer()

        -- Remove panel
        self:Remove()
        return true
    end
    return true  -- Block all keys regardless
end

function MEMORIAL:OnMousePressed(key)
    if self.canDismiss and not self.dismissed then
        self.dismissed = true

        net.Start("wsPermadeathReady")
        net.SendToServer()

        self:Remove()
    end
end

function MEMORIAL:OnRemove()
    memorialActive = false
end

vgui.Register("wsDeathMemorial", MEMORIAL, "EditablePanel")

-- ============================================================================
-- NETWORK RECEIVERS
-- ============================================================================

local knockoutPanel = nil

net.Receive("wsKnockoutStart", function()
    local duration = net.ReadFloat()
    local count = net.ReadUInt(8)

    isKnockedOut = true
    knockoutStartTime = RealTime()
    knockoutDuration = duration
    knockoutCount = count

    -- Remove existing panel if any
    if IsValid(knockoutPanel) then
        knockoutPanel:Remove()
    end

    -- Create knockout screen
    knockoutPanel = vgui.Create("wsKnockoutScreen")
    if IsValid(knockoutPanel) then
        knockoutPanel:SetKnockoutData(duration, count)
    end
end)

net.Receive("wsKnockoutTimerSync", function()
    local newDuration = net.ReadFloat()

    knockoutDuration = newDuration
    knockoutStartTime = RealTime()

    -- Sync the panel if it exists
    if IsValid(knockoutPanel) then
        knockoutPanel:SyncTimer(newDuration)
    end
end)

-- Force cleanup of all knockout UI state
local function CleanupKnockoutUI()
    isKnockedOut = false
    knockoutStartTime = 0
    knockoutDuration = 0
    knockoutCount = 0

    if IsValid(knockoutPanel) then
        knockoutPanel:Remove()
        knockoutPanel = nil
    end

    -- Re-enable screen clicker in case it was left on
    gui.EnableScreenClicker(false)
end

net.Receive("wsKnockoutEnd", function()
    local revived = net.ReadBool()
    local health = net.ReadUInt(8)

    -- Force cleanup all knockout state
    CleanupKnockoutUI()

    -- Show appropriate notification
    if revived then
        ws.util.Notify(L("revivalSuccess"))
        ws.util.Notify(string.format("You regained consciousness with %d HP.", health))
    else
        ws.util.Notify(L("characterPermadead"))
    end
end)

-- Receive permadeath memorial data
net.Receive("wsPermadeathScreen", function()
    local charName = net.ReadString()
    local model = net.ReadString()
    local skin = net.ReadUInt(8)
    local bodygroups = net.ReadString()
    local birthMonth = net.ReadUInt(4)
    local birthDay = net.ReadUInt(5)
    local age = net.ReadUInt(8)

    -- Clean up any existing knockout panel
    if IsValid(knockoutPanel) then
        knockoutPanel:Remove()
        knockoutPanel = nil
    end

    -- Reset knockout state
    isKnockedOut = false
    gui.EnableScreenClicker(false)

    -- Create memorial panel
    local memorial = vgui.Create("wsDeathMemorial")
    memorial:SetMemorialData(charName, model, skin, bodygroups, birthMonth, birthDay, age)
end)

-- Clean up knockout UI when character is kicked/unloaded
function PLUGIN:CharacterLoaded(character)
    -- Clean up any leftover knockout UI from previous character
    CleanupKnockoutUI()
end

-- Also clean up when player spawns (covers edge cases)
function PLUGIN:PlayerSpawn(client)
    if client == LocalPlayer() then
        CleanupKnockoutUI()
    end
end

-- ============================================================================
-- COMMUNICATION BLOCKING
-- ============================================================================

-- Block chat while knocked out
function PLUGIN:CanPlayerChat(client, text)
    if isKnockedOut then
        return false
    end
end

-- Block voice while knocked out
function PLUGIN:PlayerStartVoice(client)
    if client == LocalPlayer() and isKnockedOut then
        return false
    end
end

-- Hide chat messages while knocked out (optional - creates isolation)
function PLUGIN:ChatboxShouldShowMessage(data)
    if isKnockedOut then
        return false
    end
end

-- ============================================================================
-- VIEW / RENDERING OVERRIDES
-- ============================================================================

-- Override the view to prevent death camera from showing
function PLUGIN:CalcView(client, pos, angles, fov)
    if isKnockedOut then
        -- Return a view that shows nothing (underground)
        return {
            origin = Vector(0, 0, -10000),
            angles = Angle(0, 0, 0),
            fov = 1,  -- Minimal FOV
            drawviewer = false
        }
    end
end

-- Force black screen even if panel fails
function PLUGIN:HUDPaint()
    if isKnockedOut and not IsValid(knockoutPanel) then
        -- Fallback black screen
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, ScrW(), ScrH())

        -- Draw timer
        local elapsed = RealTime() - knockoutStartTime
        local remaining = math.max(0, knockoutDuration - elapsed)
        local minutes = math.floor(remaining / 60)
        local seconds = math.floor(remaining % 60)
        local timeText = string.format("%02d:%02d", minutes, seconds)

        surface.SetFont("wsMenuButtonHugeFont")
        local tw, th = surface.GetTextSize(timeText)
        surface.SetTextColor(255, 255, 255, 255)
        surface.SetTextPos(ScrW() / 2 - tw / 2, ScrH() / 2 - th / 2)
        surface.DrawText(timeText)
    end
end

-- Block HUD elements while knocked out or memorial active
function PLUGIN:HUDShouldDraw(element)
    if isKnockedOut or memorialActive then
        return false
    end
end

-- Block scoreboard while knocked out
function PLUGIN:ScoreboardShow()
    if isKnockedOut then
        return false
    end
end

-- Block context menu while knocked out
function PLUGIN:ContextMenuOpen()
    if isKnockedOut then
        return false
    end
end

-- ============================================================================
-- INPUT BLOCKING
-- ============================================================================

-- Block movement commands
function PLUGIN:StartCommand(client, cmd)
    if client == LocalPlayer() and (isKnockedOut or memorialActive) then
        cmd:ClearButtons()
        cmd:ClearMovement()
    end
end

-- ============================================================================
-- UTILITY
-- ============================================================================

-- Expose knockout state for other systems
function PLUGIN:IsLocalPlayerKnockedOut()
    return isKnockedOut
end

