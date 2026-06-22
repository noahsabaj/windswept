--[[
    Power — battery-powered-device base library (framework plugin)

    Ships the generic battery engine any schema would want:
      - base_battery_device : the item base every battery-powered device extends
                              (load/eject/equip/unequip, auto-load/eject, charge UI).
      - battery             : the universal rechargeable power cell item.

    This is a base-LIBRARY plugin (like `salary`): the bases are always available and inert
    until an item uses them, so there is no enable flag. A schema's flashlight / lantern /
    radio / camera / defibrillator simply set `ITEM.base = "base_battery_device"`; the base
    resolves because framework plugins load before the schema.

    Look-and-feel is the schema's: the base's render path calls ws.constants.GetChargeColor /
    DrawEquippedIndicator / AddTooltipRow at draw time, so each schema controls the palette
    (the skeleton schema ships neutral defaults). Logic uses framework-native ws.access.*.
]]--

local PLUGIN = PLUGIN

PLUGIN.name = "Power"
PLUGIN.author = "Windswept"
PLUGIN.description = "Battery base library: base_battery_device + the battery item."

ws.power = ws.power or {}
