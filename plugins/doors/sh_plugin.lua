--[[
    Doors — physical door, lock, and key system (framework plugin)

    Windswept's doors are physical, like its money: there is no abstract ownership
    or purchasable-door economy. This plugin replaces a map's doors with managed
    prop_door_rotating leaves that have health and a type (wood/metal/gate), can be
    fitted with physical locks keyed to physical keys, are opened/closed natively,
    can be battered down (with debris/breach VFX), and persist per-map. Double doors
    open in sync.

    Generic engine only: the ws.doors lib, server handlers, and client frame viz.
    The schema owns the CONTENT (door/key/lock items + the SWEPs that drive them)
    and wires it in through this plugin's seams: ws.doors.RegisterDamageSource(class,
    {fist|ram}) for what can damage a door, and ws.doors.installToolClass for the
    door-install tool that reveals empty frames.

    Off by default — a schema sets the doorsEnabled config to take over the map's
    doors (the InitPostEntity orchestrator in libs/sv_doors_init.lua early-returns
    while it is false, so the framework and a zero-plugin skeleton boot untouched).
]]--

local PLUGIN = PLUGIN

PLUGIN.name = "Doors"
PLUGIN.author = "Windswept"
PLUGIN.description = "Physical doors, locks, and keys: breakable managed doors with per-map persistence."

ws.doors = ws.doors or {}

ws.config.Add("doorsEnabled", false, "Replaces the map's doors with the physical door/lock system.")
