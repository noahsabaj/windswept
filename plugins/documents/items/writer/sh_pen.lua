--[[
    Pen (Blue)

    A ballpoint pen with blue ink.
    NOT equippable - just needs to be in inventory to write.
]]--

ITEM.name = "Pen (Blue)"
ITEM.description = "A ballpoint pen with blue ink."
ITEM.model = "models/props_lab/clipboard.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"
ITEM.base = "base_writer"

-- Writer configuration
ITEM.resourceName = "ink"
ITEM.resourceNameDisplay = "Ink"
ITEM.maxResource = 1000
ITEM.strokeColor = {100, 100, 200}
ITEM.canRefill = true
