--[[
    Restraint System Plugin

    Physical restraint mechanics for emergent justice/conflict:
    - Hands Up weapon for surrender indication
    - Zip Ties for restraining players
    - Gag system for silencing/blinding restrained players
    - Drag mechanic to move restrained players
    - Leash mechanic to anchor players to surfaces
    - Gavel tool for making noise (RP prop)
]]--

PLUGIN.name = "Restraint System"
PLUGIN.author = "Windswept"
PLUGIN.description = "Physical restraint mechanics: zipties, gagging, dragging, leashing."

ws.util.Include("sv_plugin.lua")
ws.util.Include("cl_plugin.lua")
