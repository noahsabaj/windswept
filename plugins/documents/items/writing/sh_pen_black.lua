--[[
    Pen (Black)

    A ballpoint pen with black ink.
    NOT equippable - just needs to be in inventory to write.
]]--

ITEM.name = "Pen (Black)"
ITEM.description = "A ballpoint pen with black ink."
ITEM.model = "models/props_lab/clipboard.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"
ITEM.base = "base_writer"

-- Writer configuration
ITEM.resourceName = "ink"
ITEM.resourceNameDisplay = "Ink"
ITEM.maxResource = 1000
ITEM.strokeColor = {40, 40, 40}
ITEM.canRefill = true
