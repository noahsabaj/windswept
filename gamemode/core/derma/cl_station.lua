--[[
    Station Frame

    The standard window for deployable-station UIs (locksmith, typewriter,
    stationary radio, and any future usable entity that opens a panel), and
    for station-adjacent popups. One look and one behavior everywhere:

    - Windswept header bar (ws.constants.CreateHeaderBar) with title + close
    - opaque dark rounded body instead of the stock DFrame chrome
    - self.body: DPanel docked FILL between the header and any button bar --
      build the station's widgets in here
    - self:AddButtonBar(specs): standard bottom bar (ws.constants.CreateButtonBar)
    - self:AddTabs(): DPropertySheet filling the body, tabs restyled to match
      (the derma skin has no dark tab style)
    - ESC or the header button closes the panel

    Entity-backed behavior, enabled by SetStation(ent):
    - auto-close when the entity is removed, the local player dies, the player
      walks out of range (maxUseDistance; adopts ent.MaxUseDistance when the
      entity defines one), or the server hands the station to another user
    - closeMessage: ws.action message sent exactly once when the panel is
      removed, so the server frees the station's user session. When REPLACING
      an open panel with a fresh one for the same station (re-open), nil out
      closeMessage on the old panel before removing it -- otherwise its removal
      tells the server to end the session the new panel just started.

    Minimal station UI:

        local PANEL = {}

        function PANEL:Init()
            self:SetSize(450, 400)
            self:SetStationTitle("Locksmith")
            self:Center()
            self.closeMessage = "wsLocksmithClose"
            -- build widgets parented to self.body
        end

        function PANEL:OnStationSet(station)
            -- optional: populate from the entity
        end

        vgui.Register("wsLocksmithMenu", PANEL, "wsStationFrame")

        -- from the open net receiver:
        local old = ws.gui.locksmith
        if IsValid(old) then old.closeMessage = nil old:Remove() end
        ws.gui.locksmith = vgui.Create("wsLocksmithMenu")
        ws.gui.locksmith:SetStation(ent)

    A station that overrides Think or OnRemove must call the wsStationFrame
    implementation (vgui.GetControlTable("wsStationFrame").Think(self)) or it
    loses the auto-close / close-message behavior.

    Documented in docs/manual/station-uis.md.
]]--

-- Fully opaque: at 250 the world bled through visibly across large panels
-- (windswept-colony#57).
local COLOR_BACKGROUND = Color(35, 35, 35, 255)
local COLOR_OUTLINE = Color(60, 60, 60, 255)
local COLOR_TAB_ACTIVE = Color(50, 50, 50, 255)
local COLOR_TAB_INACTIVE = Color(38, 38, 38, 255)

-- Live frames, closed on lua auto-refresh (their scripts were just replaced).
local openFrames = setmetatable({}, {__mode = "k"})

local PANEL = {}

function PANEL:Init()
    self:SetTitle("")
    self:ShowCloseButton(false)
    self:SetDraggable(true)
    self:MakePopup()

    -- Stock DFrame reserves its 24px title strip UNCONDITIONALLY via
    -- DockPadding(5, 24 + 5, 5, 5) (dframe.lua:65) -- even with an empty title
    -- and no close button. Left in place it shrinks the dock area, leaving a
    -- dead band above our docked header and clipping the last-docked child
    -- (windswept#104).
    self:DockPadding(0, 0, 0, 0)

    self.header, self.headerClose = ws.constants.CreateHeaderBar(self, "", nil, function()
        self:Remove()
    end)

    self.body = vgui.Create("DPanel", self)
    self.body:Dock(FILL)
    self.body:DockMargin(8, 8, 8, 8)
    self.body:SetPaintBackground(false)

    self.station = nil
    self.maxUseDistance = 200
    self.closeMessage = nil

    openFrames[self] = true
end

function PANEL:SetStationTitle(text)
    self.header.text = text
end

-- Track the entity backing this UI; enables the auto-close checks in Think.
function PANEL:SetStation(station)
    self.station = station
    self.wasStationUser = false

    if IsValid(station) and isnumber(station.MaxUseDistance) then
        self.maxUseDistance = station.MaxUseDistance
    end

    if self.OnStationSet then
        self:OnStationSet(station)
    end
end

function PANEL:AddButtonBar(buttons)
    return ws.constants.CreateButtonBar(self, buttons)
end

-- DPropertySheet docked FILL in the body, with tabs restyled to the station
-- look. Content panels keep their own backgrounds.
function PANEL:AddTabs()
    local sheet = vgui.Create("DPropertySheet", self.body)
    sheet:Dock(FILL)
    sheet.Paint = function() end

    local addSheet = sheet.AddSheet
    sheet.AddSheet = function(pnl, label, contents, icon, ...)
        local data = addSheet(pnl, label, contents, icon, ...)

        if data and IsValid(data.Tab) then
            local tab = data.Tab
            tab.Paint = function(t, w, h)
                local color = t:IsActive() and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE
                draw.RoundedBoxEx(4, 0, 0, w, h, color, true, true, false, false)
            end
            tab.UpdateColours = function(t)
                if t:IsActive() then
                    t:SetTextStyleColor(color_white)
                else
                    t:SetTextStyleColor(ws.constants.COLOR_UI_NEUTRAL)
                end
            end
        end

        return data
    end

    return sheet
end

function PANEL:Paint(w, h)
    draw.RoundedBox(4, 0, 0, w, h, COLOR_BACKGROUND)
    surface.SetDrawColor(COLOR_OUTLINE)
    surface.DrawOutlinedRect(0, 0, w, h)
end

function PANEL:Think()
    -- DFrame's Think does the drag/size processing; replacing Think without
    -- this call silently breaks dragging (the pre-standard station UIs did).
    vgui.GetControlTable("DFrame").Think(self)

    local station = self.station
    if station == nil then return end

    if not IsValid(station) then
        self:Remove()
        return
    end

    local client = LocalPlayer()
    if not client:Alive() then
        self:Remove()
        return
    end

    if self.maxUseDistance > 0
    and client:GetPos():DistToSqr(station:GetPos()) > self.maxUseDistance * self.maxUseDistance then
        self:Remove()
        return
    end

    -- Close when the server hands the station to someone else. Only enforced
    -- after we have seen ourselves as the user once -- the user netvar can
    -- arrive a tick after the open message.
    if station.GetUser then
        local user = station:GetUser()
        if user == client then
            self.wasStationUser = true
        elseif self.wasStationUser then
            self:Remove()
        end
    end
end

function PANEL:OnKeyCodePressed(key)
    if key == KEY_ESCAPE then
        self:Remove()
        return true
    end
end

function PANEL:OnRemove()
    if self.closeMessage and IsValid(self.station) then
        ws.action.Send(self.closeMessage, nil, self.station)
        self.closeMessage = nil
    end
end

vgui.Register("wsStationFrame", PANEL, "DFrame")

hook.Add("OnReloaded", "wsStationFrame", function()
    for panel in pairs(openFrames) do
        if IsValid(panel) then
            panel:Remove()
        end
    end
end)

--[[
    wsStationSlider

    Dark slider for station UIs, with an API that separates programmatic
    updates from user input -- stock DSlider:SetSlideX() unconditionally
    fires OnValueChanged (dslider.lua:173), so reflecting a netvar into a
    stock slider every Think echoes a server action per frame and saturates
    the action's rate limit, starving every other control on that action
    (windswept-colony#52).

    - SetFraction(f)   -- position the slider WITHOUT firing any event.
                          Ignored mid-drag so it never fights the user.
    - GetFraction()    -- current 0..1 position
    - OnUserChanged(f) -- fires only from real user input, throttled to one
                          call per 0.25s while dragging, with a guaranteed
                          final fire when the drag ends.
]]--

local SLIDER = {}

local COLOR_SLIDER_TRACK = Color(25, 25, 25, 255)
local COLOR_SLIDER_FILL = Color(30, 58, 95, 255) -- header-bar blue
local COLOR_SLIDER_KNOB = Color(200, 200, 200, 255)
local COLOR_SLIDER_KNOB_DRAG = Color(255, 255, 255, 255)

SLIDER.userThrottle = 0.25

function SLIDER:Init()
    self:SetLockY(0.5)
    self.lastUserSend = 0
    self.pendingFraction = nil

    self.Knob:SetSize(10, 16)
    self.Knob.Paint = function(knob, w, h)
        local color = self:IsEditing() and COLOR_SLIDER_KNOB_DRAG or COLOR_SLIDER_KNOB
        draw.RoundedBox(3, 0, 0, w, h, color)
    end
end

function SLIDER:Paint(w, h)
    local trackY = h / 2 - 2
    draw.RoundedBox(2, 0, trackY, w, 4, COLOR_SLIDER_TRACK)

    local frac = self:GetSlideX() or 0
    if frac > 0 then
        draw.RoundedBox(2, 0, trackY, w * frac, 4, COLOR_SLIDER_FILL)
    end
end

-- Position the slider without firing OnUserChanged (netvar reflection path).
function SLIDER:SetFraction(frac)
    if self:IsEditing() then return end
    self.suppressEvent = true
    self:SetSlideX(math.Clamp(tonumber(frac) or 0, 0, 1))
    self.suppressEvent = nil
end

function SLIDER:GetFraction()
    return math.Clamp(self:GetSlideX() or 0, 0, 1)
end

function SLIDER:OnValueChanged(x)
    if self.suppressEvent then return end

    self.pendingFraction = math.Clamp(tonumber(x) or 0, 0, 1)

    if RealTime() - self.lastUserSend >= self.userThrottle then
        self:FlushUserChange()
    end
end

function SLIDER:FlushUserChange()
    if self.pendingFraction == nil then return end

    self.lastUserSend = RealTime()
    local frac = self.pendingFraction
    self.pendingFraction = nil

    if self.OnUserChanged then
        self:OnUserChanged(frac)
    end
end

function SLIDER:OnMouseReleased(code)
    vgui.GetControlTable("DSlider").OnMouseReleased(self, code)
    self:FlushUserChange()
end

function SLIDER:Think()
    vgui.GetControlTable("DSlider").Think(self)

    -- Trailing flush: covers drags that end without our OnMouseReleased
    -- (e.g. released over the knob, which has its own capture).
    if self.pendingFraction ~= nil and not self:IsEditing() then
        self:FlushUserChange()
    end
end

vgui.Register("wsStationSlider", SLIDER, "DSlider")

--[[
    wsStationToggle

    ON/OFF chip for station UIs (TX/RX/mic style states).
    - SetStateText(onText, offText)
    - SetState(bool)  -- display only, no events; wire DoClick yourself
    - GetState()
    - .onColor        -- per-instance ON color (default green)
]]--

local TOGGLE = {}

local COLOR_TOGGLE_BG = Color(45, 45, 45, 255)
local COLOR_TOGGLE_BG_HOVER = Color(55, 55, 55, 255)

function TOGGLE:Init()
    self.state = false
    self.onText = "ON"
    self.offText = "OFF"
    self.onColor = Color(110, 255, 110)
    self:SetText("OFF")
    self:SetTextColor(ws.constants.COLOR_UI_NEUTRAL)
end

function TOGGLE:SetStateText(onText, offText)
    self.onText = onText
    self.offText = offText
    self:ApplyState()
end

function TOGGLE:SetState(on)
    on = tobool(on)
    if self.state == on then return end
    self.state = on
    self:ApplyState()
end

function TOGGLE:GetState()
    return self.state
end

function TOGGLE:ApplyState()
    self:SetText(self.state and self.onText or self.offText)
    self:SetTextColor(self.state and self.onColor or ws.constants.COLOR_UI_NEUTRAL)
end

function TOGGLE:Paint(w, h)
    draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and COLOR_TOGGLE_BG_HOVER or COLOR_TOGGLE_BG)

    if self.state then
        surface.SetDrawColor(self.onColor.r, self.onColor.g, self.onColor.b, 160)
    else
        surface.SetDrawColor(0, 0, 0, 180)
    end
    surface.DrawOutlinedRect(0, 0, w, h)
end

vgui.Register("wsStationToggle", TOGGLE, "DButton")
