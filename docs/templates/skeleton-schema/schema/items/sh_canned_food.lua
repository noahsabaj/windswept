-- One trivial custom item, so a fresh schema has something of its own from the start.
-- Items live under schema/items/ and are swept automatically. Drop the ITEM.base line to
-- make a plain item, or set it to a framework base (base_container, base_outfit, the power
-- plugin's base_battery_device, etc.) to inherit behaviour.
ITEM.name = "Canned Food"
ITEM.description = "A simple ration -- your schema's first custom item."
ITEM.model = "models/props_junk/garbage_metalcan001a.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Supplies"
