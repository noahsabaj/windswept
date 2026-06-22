--[[
    Document Library

    File-based storage for document content (like the photo system).
    Documents are stored in data/ws_documents/ as JSON files.
    Items only store reference IDs, preventing inventory sync overflow.

    Document data structure:
    {
        content = "Text content of the document",
        entries = {
            {
                -- fog-of-war: entries carry NO author identity (sc-schema-glue-2)
                timestamp = 1234567890,
                type = "handwritten" | "pencil" | "typed",
                length = 42
            },
            ...
        },
        signatures = {
            {
                strokes = {{x=0.1, y=0.2}, ...},
                authorName = "Signer Name",
                color = {200, 200, 200},
                timestamp = 1234567890
            },
            ...
        }
    }
]]--

ws.documents = ws.documents or {}

-- Document storage directory
ws.documents.STORAGE_DIR = "ws_documents"

-- Maximum content length per write (prevents abuse)
ws.documents.MAX_CONTENT_LENGTH = 10000

-- Maximum total accumulated content per document. Without this, a player can grow a single
-- document file without bound by writing repeatedly to the same paperID (disk + net DoS).
-- (sc-schema-glue-1)
ws.documents.MAX_DOCUMENT_LENGTH = 100000

-- ============================================================================
-- ID GENERATION AND VALIDATION
-- ============================================================================

-- Generate unique document ID (timestamp + random)
function ws.documents.GenerateID()
    return os.time() .. "_" .. math.random(10000, 99999)
end

-- Validate document ID format (prevents path traversal)
function ws.documents.ValidateID(id)
    return isstring(id) and id:match("^%d+_%d+$") ~= nil
end

-- Get file path for document
function ws.documents.GetFilePath(documentID)
    if not ws.documents.ValidateID(documentID) then return nil end
    return ws.documents.STORAGE_DIR .. "/" .. documentID .. ".json"
end

-- ============================================================================
-- SERVER-SIDE FILE OPERATIONS
-- ============================================================================

if SERVER then
    -- Ensure storage directory exists
    file.CreateDir(ws.documents.STORAGE_DIR)

    -- Save document content to file
    -- @param documentID string The document's unique ID
    -- @param data table The document data to save
    -- @return boolean Success
    function ws.documents.Save(documentID, data)
        if not ws.documents.ValidateID(documentID) then return false end

        local path = ws.documents.GetFilePath(documentID)
        if not path then return false end

        local json = util.TableToJSON(data, true)
        if not json then return false end

        file.Write(path, json)
        return true
    end

    -- Load document content from file
    -- @param documentID string The document's unique ID
    -- @return table|nil The document data or nil if not found
    function ws.documents.Load(documentID)
        if not ws.documents.ValidateID(documentID) then return nil end

        local path = ws.documents.GetFilePath(documentID)
        if not path then return nil end

        if not file.Exists(path, "DATA") then return nil end

        local content = file.Read(path, "DATA")
        if not content then return nil end

        return util.JSONToTable(content)
    end

    -- Delete document file
    -- @param documentID string The document's unique ID
    -- @return boolean Success
    function ws.documents.Delete(documentID)
        if not ws.documents.ValidateID(documentID) then return false end

        local path = ws.documents.GetFilePath(documentID)
        if not path then return false end

        if file.Exists(path, "DATA") then
            file.Delete(path)
            return true
        end

        return false
    end

    -- Check if document exists
    -- @param documentID string The document's unique ID
    -- @return boolean Exists
    function ws.documents.Exists(documentID)
        if not ws.documents.ValidateID(documentID) then return false end

        local path = ws.documents.GetFilePath(documentID)
        if not path then return false end

        return file.Exists(path, "DATA")
    end
end

-- ============================================================================
-- SHARED UTILITY FUNCTIONS
-- ============================================================================

-- Check if a player has a writing tool (pen with ink or pencil with lead) in inventory
-- @param client Player The player to check
-- @return boolean Has a usable writing tool
function ws.documents.HasWritingTool(client)
    local char = client:GetCharacter()
    if not char then return false end

    local inv = char:GetInventory()
    if not inv then return false end

    local penTypes = {pen = true, pen_black = true, pen_red = true, pen_green = true}

    for _, invItem in pairs(inv:GetItems()) do
        if penTypes[invItem.uniqueID] and invItem:GetInk() > 0 then
            return true
        elseif (invItem.uniqueID == "pencil" or invItem.uniqueID == "pencil_eraser") and invItem:GetLead() > 0 then
            return true
        end
    end

    return false
end

-- Signature limits (shared by the signature-save and document-write paths)
ws.documents.MAX_SIGNATURE_STROKES = 50
ws.documents.MAX_SIGNATURE_POINTS = 500

-- Validate and sanitize signature stroke data parsed from client JSON.
-- Truncates to MAX_SIGNATURE_STROKES, coerces non-table strokes to empty, and
-- rejects (returns nil) if total points exceed MAX_SIGNATURE_POINTS. Used by both
-- wsSignatureSave and wsDocumentWrite so neither path can bypass the caps.
-- @param strokes table Parsed stroke array
-- @return table|nil Sanitized strokes, or nil if invalid/too complex
function ws.documents.ValidateSignature(strokes)
    if type(strokes) ~= "table" then return nil end

    -- Truncate to max strokes
    if #strokes > ws.documents.MAX_SIGNATURE_STROKES then
        local truncated = {}
        for i = 1, ws.documents.MAX_SIGNATURE_STROKES do
            truncated[i] = strokes[i]
        end
        strokes = truncated
    end

    -- Coerce invalid strokes and count total points
    local totalPoints = 0
    for i, stroke in ipairs(strokes) do
        if type(stroke) ~= "table" then
            strokes[i] = {}
        else
            totalPoints = totalPoints + #stroke
        end
    end

    if totalPoints > ws.documents.MAX_SIGNATURE_POINTS then
        return nil
    end

    return strokes
end

-- Count words in text
-- @param text string The text to count words in
-- @return number Word count
function ws.documents.CountWords(text)
    if not text or text == "" then return 0 end

    local count = 0
    for _ in text:gmatch("%S+") do
        count = count + 1
    end

    return count
end

-- Check if content type is erasable (pencil only)
-- @param contentType string "handwritten", "pencil", or "typed"
-- @return boolean Erasable
function ws.documents.IsErasable(contentType)
    return contentType == "pencil"
end

-- Format document type for display
-- @param docType string The document type
-- @return string Formatted name
function ws.documents.FormatType(docType)
    local types = {
        handwritten = "Handwritten",
        pencil = "Pencil",
        typed = "Typed"
    }
    return types[docType] or "Unknown"
end
