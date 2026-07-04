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

local COLOR_BACKGROUND = Color(35, 35, 35, 250)
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
