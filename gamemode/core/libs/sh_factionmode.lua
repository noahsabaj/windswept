--[[
    Faction-optional capability (framework)

    Windswept's headline differentiator over Helix: factions are a CHOICE, not a
    requirement. A schema picks its model via the `factionMode` config:
        "required"  - every character must belong to a faction (Helix behaviour)  -- (layer-6)
        "optional"  - characters may be factionless
        "disabled"  - no factions at all
    `showFactionColors` decouples faction identity from UI tint (anti-metagaming).

    This file registers the config + query helpers. Enforcement points (character
    creation, whitelist, scoreboard/HUD tinting) consult these helpers so all three
    modes degrade gracefully.
]]--

ws.faction = ws.faction or {}

if (ws.config and ws.config.Add) then
    ws.config.Add("factionMode", "required",
        "Faction model: 'required' (every character picks a faction), 'optional' " ..
        "(factionless allowed), or 'disabled' (no factions).",
        nil, { category = "factions" })

    ws.config.Add("showFactionColors", true,
        "Tint UI (HUD name, scoreboard) by faction colour. Turn off for anti-metagaming schemas.",
        nil, { category = "factions" })
end

--- Current faction model ("required" | "optional" | "disabled").
function ws.faction.GetMode()
    return (ws.config and ws.config.Get("factionMode", "required")) or "required"
end

--- Must every character belong to a faction?
function ws.faction.IsRequired()
    return ws.faction.GetMode() == "required"
end

--- Are factions turned off entirely?
function ws.faction.IsDisabled()
    return ws.faction.GetMode() == "disabled"
end

--- May a character exist without a faction? (optional or disabled modes)
function ws.faction.AllowsFactionless()
    local mode = ws.faction.GetMode()
    return mode == "optional" or mode == "disabled"
end

--- Should the UI tint by faction colour?
function ws.faction.ShowColors()
    return ((ws.config and ws.config.Get("showFactionColors", true)) ~= false)
end
