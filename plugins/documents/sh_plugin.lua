--[[
    Documents — handwriting / paper system (framework plugin)

    The generic document engine any RP schema would want:
      - ws.documents lib    : file-backed document storage (data/ws_documents), id generation,
                              signature validation, length caps.
      - server handlers     : write / read / erase / destroy + container-rename, all on ws.action.
      - item bases          : base_documents, base_document_container (folders/envelopes),
                              base_writer (pens/pencils consuming ink/lead via ws.resource).
      - standard content    : paper, folder, envelopes, pen (+ black/red/green), pencil, eraser.
      - derma               : the document editor, viewer, and signature pad.

    Base-library plugin (no enable flag): inert unless a schema includes writeable items.
    Logic uses framework-native ws.access.*; the schema owns look/strings (the bases call
    ws.constants UI helpers + localized keys at runtime, supplied by the schema).
]]--

local PLUGIN = PLUGIN

PLUGIN.name = "Documents"
PLUGIN.author = "Windswept"
PLUGIN.description = "Handwriting system: paper, pens, folders, envelopes, signatures."

ws.documents = ws.documents or {}
