--[[
    Pencil (No Eraser)

    A wooden pencil without an eraser.
    Pencil writing can be erased by others with an eraser.
    NOT equippable - just needs to be in inventory to write.
]]--

ITEM.name = "Pencil"
ITEM.description = "A wooden pencil without an eraser."
ITEM.model = "models/props_lab/bindergreen.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"
ITEM.base = "base_writer"

-- Writer configuration
ITEM.resourceName = "lead"
ITEM.resourceNameDisplay = "Lead"
ITEM.maxResource = 500
ITEM.strokeColor = {150, 150, 150}
ITEM.hasEraser = false
