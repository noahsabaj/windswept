--[[
    Pencil with Eraser

    A wooden pencil with an eraser on top.
    Can erase pencil writing from papers.
    NOT equippable - just needs to be in inventory to write/erase.
]]--

ITEM.name = "Pencil with Eraser"
ITEM.description = "A wooden pencil with an eraser on top."
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
ITEM.hasEraser = true
