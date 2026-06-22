ITEM.name = "Document Folder"
ITEM.description = "A folder for organizing documents."
ITEM.model = "models/props_lab/binderblue.mdl"
ITEM.category = "Containers"
ITEM.base = "base_document_container"
ITEM.width = 2
ITEM.height = 2
-- Capped at 100 slots (was 25x10 = 250) to bound document-file growth and the
-- inventory-sync payload; still the largest container (2x the large envelope). (sc-items-currency-battery-6)
ITEM.invWidth = 10
ITEM.invHeight = 10
ITEM.containerLabel = "folder"
