# Station UIs

Any usable entity that opens a window — a locksmith machine, a typewriter, a
dispatch console, whatever you build next — uses **one** panel base:
`wsStationFrame` (`gamemode/core/derma/cl_station.lua`). Don't hand-roll a
`DFrame` for a deployable. The base gives every station the same look and the
same lifecycle, so a new station UI is just its widgets.

## What the base provides

**Look** — Windswept header bar (title + close button), opaque dark rounded
body, standard bottom button bar. All of it built on the shared helpers in
`ws.constants` (`CreateHeaderBar`, `CreateButtonBar`), so stations match the
rest of the UI for free.

**Lifecycle** — with `SetStation(ent)` the panel closes itself when:

- the entity is removed,
- the local player dies,
- the player walks out of range (`maxUseDistance`, default 200; the base
  adopts `ent.MaxUseDistance` when the entity defines one — keep it in sync
  with whatever range the server enforces),
- the server hands the station to another user (checked via `ent:GetUser()`,
  only after we've been the user once, so the netvar race on open can't
  insta-close the panel).

**Session close** — set `self.closeMessage = "wsMyStationClose"` and the base
sends that `ws.action` message exactly once when the panel is removed, however
it died (close button, ESC, range, entity gone). The server frees the user
session in that one place.

## Building a station UI

```lua
local PANEL = {}

function PANEL:Init()
    self:SetSize(450, 400)
    self:SetStationTitle("Locksmith")
    self:Center()
    self.closeMessage = "wsLocksmithClose"

    -- widgets go in self.body (a DPanel docked FILL under the header)
    self.tabs = self:AddTabs()          -- dark-styled DPropertySheet, optional

    self:AddButtonBar({                 -- standard bottom bar, optional
        {"Cancel", 80, RIGHT, function() self:Remove() end},
        {"Save", 80, RIGHT, function() self:Save() end},
    })
end

function PANEL:OnStationSet(station)
    -- optional: populate from the entity (called by SetStation)
end

vgui.Register("wsLocksmithMenu", PANEL, "wsStationFrame")
```

Opening it from the server's "open" net message:

```lua
net.Receive("wsLocksmithOpen", function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end

    -- Re-open replaces the old panel. Nil closeMessage FIRST: the old panel's
    -- removal must not tell the server to end the session we just started.
    local old = ws.gui.locksmith
    if IsValid(old) then
        old.closeMessage = nil
        old:Remove()
    end

    ws.gui.locksmith = vgui.Create("wsLocksmithMenu")
    ws.gui.locksmith:SetStation(ent)
end)
```

## Rules

- Widgets parent to `self.body`, not to the frame — the frame's top is the
  header and its bottom belongs to the button bar.
- Don't override `Think` or `OnRemove` unless you must; if you must, call the
  base first: `vgui.GetControlTable("wsStationFrame").Think(self)`. The
  pre-standard station UIs overrode `Think` bare and silently broke DFrame
  dragging.
- Popups that belong to a station but aren't entity-backed (result dialogs,
  pickers) still use `wsStationFrame` — just never call `SetStation`, and the
  lifecycle checks stay off.
- The cross-repo CI panel guard (`tools/check-panels.sh`) knows about base
  classes: a schema registering panels on `wsStationFrame` passes because the
  framework registers it.

Reference ports: the colony schema's locksmith, typewriter, stationary-radio,
and radio-frequency panels (windswept-colony `schema/derma/`).
