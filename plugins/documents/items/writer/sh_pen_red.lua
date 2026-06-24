--[[
    Pen (Red)

    A ballpoint pen with red ink.
    NOT equippable - just needs to be in inventory to write.
]]--

ITEM.name = "Pen (Red)"
ITEM.description = "A ballpoint pen with red ink."
ITEM.model = "models/props_lab/clipboard.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"
ITEM.base = "base_writer"

-- Writer configuration
ITEM.resourceName = "ink"
ITEM.resourceNameDisplay = "Ink"
ITEM.maxResource = 1000
ITEM.strokeColor = {200, 80, 80}
ITEM.canRefill = true
