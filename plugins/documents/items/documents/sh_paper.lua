--[[
    Paper

    A sheet of paper that can be written on with pen or pencil.
    Content is stored in server files (data/ws_documents/), item only holds reference ID.
    This prevents inventory sync overflow from large text data.

    Data structure (stored on item):
        paperID: string (file reference)
        documentType: "handwritten" | "pencil" | "typed"
        author: string (first writer's name)
        wordCount: number
        hasSignature: boolean
        signatureAuthor: string
        timestamp: number (creation time)
        lastEdited: number (last edit time)
]]--

ITEM.name = "Paper"
ITEM.description = "A blank sheet of paper."
ITEM.model = "models/props_c17/paper01.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Documents"
ITEM.noBusiness = true

-- Blank papers stack up to 20
ITEM.maxStack = 20

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function ITEM:GetPaperID()
    return self:GetData("paperID")
end

function ITEM:HasContent()
    return self:GetPaperID() ~= nil
end

function ITEM:GetAuthor()
    return self:GetData("author", "Unknown")
end

function ITEM:GetDocumentType()
    return self:GetData("documentType", "handwritten")
end

function ITEM:GetWordCount()
    return self:GetData("wordCount", 0)
end

function ITEM:HasSignature()
    return self:GetData("hasSignature", false)
end

function ITEM:GetSignatureCount()
    return self:GetData("signatureCount", 0)
end

function ITEM:GetTimestamp()
    return self:GetData("timestamp", 0)
end

-- Check if paper content can be erased (pencil only)
function ITEM:IsErasable()
    return self:GetDocumentType() == "pencil"
end

-- Override GetName to show if written
function ITEM:GetName()
    if self:HasContent() then
        return "Written Paper"
    end

    return self.name
end

-- Override GetDescription to show document info
function ITEM:GetDescription()
    local paperID = self:GetPaperID()
    if not paperID then
        return "A blank sheet of paper, ready to be written on."
    end

    -- NO author shown (fog of war)
    local docType = ws.documents.FormatType(self:GetDocumentType())
    local wordCount = self:GetWordCount()

    local desc = string.format("%s document.\nWords: %d", docType, wordCount)

    if self:HasSignature() then
        local sigCount = self:GetSignatureCount()
        if sigCount > 1 then
            desc = desc .. string.format("\nSignatures: %d", sigCount)
        else
            desc = desc .. "\nSigned"
        end
    end

    return desc
end

-- Only blank papers can stack (written papers are unique)
function ITEM:CanStack(other)
    -- Both must be blank (no paperID) to stack
    return not self:HasContent() and not other:HasContent()
end

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        -- Show indicator if paper has content
        if item:GetData("paperID") then
            -- Small written indicator in corner
            surface.SetDrawColor(200, 200, 200, 200)
            surface.DrawRect(w - 14, h - 14, 8, 8)
        end

        -- Show signature indicator
        if item:GetData("hasSignature") then
            surface.SetDrawColor(150, 150, 200, 200)
            surface.DrawRect(w - 14, 6, 8, 8)
        end
    end
end

-- ============================================================================
-- ITEM FUNCTIONS
-- ============================================================================

-- Read: View the document contents
ITEM.functions.Read = {
    name = "Read",
    tip = "Read the contents of this paper.",
    icon = "icon16/page_white_text.png",
    OnClick = function(item)
        ws.action.Send("wsDocumentRead", item:GetID(), nil, function() net.WriteBool(false) end)  -- not for editor
        return false
    end,
    OnCanRun = function(item)
        return item:GetData("paperID") ~= nil
    end
}

-- Write: Open editor to write on paper (requires pen/pencil in inventory)
ITEM.functions.Write = {
    name = "Write",
    tip = "Write on this paper.",
    icon = "icon16/pencil.png",
    OnClick = function(item)
        local client = LocalPlayer()
        local char = client:GetCharacter()
        if not char then return false end

        local inv = char:GetInventory()
        if not inv then return false end

        -- Find writing tool in inventory (pen or pencil with ink/lead)
        local toolType = nil
        local toolItem = nil

        -- Check if item is a pen type (base or colored variants)
        local function isPenType(uniqueID)
            return uniqueID == "pen" or uniqueID == "pen_black" or
                   uniqueID == "pen_red" or uniqueID == "pen_green"
        end

        for _, invItem in pairs(inv:GetItems()) do
            if isPenType(invItem.uniqueID) and invItem:GetInk() > 0 then
                toolType = "pen"
                toolItem = invItem
                break  -- Prefer pen
            elseif (invItem.uniqueID == "pencil" or invItem.uniqueID == "pencil_eraser") and invItem:GetLead() > 0 then
                if not toolType then  -- Only use pencil if no pen found
                    toolType = "pencil"
                    toolItem = invItem
                end
            end
        end

        if not toolType then
            client:NotifyLocalized("needWritingTool")
            return false
        end

        -- Open editor
        local editor = vgui.Create("wsDocumentEditor")
        editor:SetPaper(item)
        editor:SetWritingTool(toolType, toolItem)

        return false
    end,
    OnCanRun = function(item)
        if IsValid(item.entity) then return false end
        if not CLIENT then return true end

        local client = LocalPlayer()
        local char = client:GetCharacter()
        if not char then return false end

        local inv = char:GetInventory()
        if not inv then return false end

        -- Check if item is a pen type (base or colored variants)
        local function isPenType(uniqueID)
            return uniqueID == "pen" or uniqueID == "pen_black" or
                   uniqueID == "pen_red" or uniqueID == "pen_green"
        end

        -- Check for any writing tool with resource
        for _, invItem in pairs(inv:GetItems()) do
            if isPenType(invItem.uniqueID) and invItem:GetInk() > 0 then
                return true
            elseif (invItem.uniqueID == "pencil" or invItem.uniqueID == "pencil_eraser") and invItem:GetLead() > 0 then
                return true
            end
        end

        return false
    end
}

-- Erase: Erase pencil content (requires eraser in inventory)
ITEM.functions.Erase = {
    name = "Erase",
    tip = "Erase the pencil writing from this paper.",
    icon = "icon16/page_white_delete.png",
    OnClick = function(item)
        local client = LocalPlayer()
        local char = client:GetCharacter()
        if not char then return false end

        local inv = char:GetInventory()
        if not inv then return false end

        -- Check for eraser in inventory (standalone or pencil with eraser)
        local hasEraser = false
        for _, invItem in pairs(inv:GetItems()) do
            if invItem.uniqueID == "eraser" and invItem:GetDurability() > 0 then
                hasEraser = true
                break
            elseif invItem.uniqueID == "pencil_eraser" then
                hasEraser = true
                break
            end
        end

        if not hasEraser then
            client:NotifyLocalized("needEraser")
            return false
        end

        Derma_Query(
            "Are you sure you want to erase all pencil writing from this paper?",
            "Erase Paper",
            "Yes, Erase",
            function()
                ws.action.Send("wsDocumentErase", item:GetID())
            end,
            "Cancel",
            function() end
        )

        return false
    end,
    OnCanRun = function(item)
        -- Can only erase if paper has pencil content
        if not item:GetData("paperID") then return false end
        if item:GetDocumentType() ~= "pencil" then return false end
        if IsValid(item.entity) then return false end
        if not CLIENT then return true end

        local client = LocalPlayer()
        local char = client:GetCharacter()
        if not char then return false end

        local inv = char:GetInventory()
        if not inv then return false end

        -- Check for eraser in inventory
        for _, invItem in pairs(inv:GetItems()) do
            if invItem.uniqueID == "eraser" and invItem:GetDurability() > 0 then
                return true
            elseif invItem.uniqueID == "pencil_eraser" then
                return true
            end
        end

        return false
    end
}

-- Destroy: Remove the paper permanently
ITEM.functions.Destroy = {
    name = "Destroy",
    tip = "Destroy this paper permanently.",
    icon = "icon16/cross.png",
    OnClick = function(item)
        local confirmText = "Are you sure you want to destroy this paper? This cannot be undone."

        Derma_Query(
            confirmText,
            "Destroy Paper",
            "Yes, Destroy",
            function()
                ws.action.Send("wsDocumentDestroy", item:GetID())
            end,
            "Cancel",
            function() end
        )

        return false
    end,
    OnCanRun = function(item)
        if IsValid(item.entity) then return false end
        return true
    end
}

-- ============================================================================
-- SERVER HOOKS
-- ============================================================================

if SERVER then
    -- Delete document file when paper is removed
    function ITEM:OnRemoved()
        local paperID = self:GetPaperID()
        if paperID then
            ws.documents.Delete(paperID)
        end
    end
end

-- ============================================================================
-- ENTITY USE (View from ground)
-- ============================================================================

function ITEM:OnEntityCreated(entity)
    if SERVER then
        entity:SetUseType(SIMPLE_USE)
    end
end

-- Hook for viewing paper on ground
hook.Add("PlayerUse", "wsPaperGroundView", function(client, entity)
    if not SERVER then return end
    if not IsValid(entity) then return end

    local item = entity.wsItem
    if not item then return end
    if item.uniqueID ~= "paper" then return end

    local paperID = item:GetPaperID()
    if not paperID then
        -- Blank paper, nothing to view
        client:NotifyLocalized("paperBlank")
        return
    end

    -- Load and send document data
    local docData = ws.documents.Load(paperID)
    if not docData then return end

    -- Fog-of-war: no author identity in the response; signatures / typed name only. (sc-schema-glue-2)
    local response = {
        content = docData.content or "",
        documentType = item:GetDocumentType(),
        wordCount = item:GetWordCount(),
        signatures = docData.signatures or {},
        entries = docData.entries or {},
        fromGround = true
    }

    net.Start("wsDocumentData")
        net.WriteBool(false)  -- Not for editor
        net.WriteString(util.TableToJSON(response))
    net.Send(client)
end)
