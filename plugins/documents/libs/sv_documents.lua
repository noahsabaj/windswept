--[[
    Server-Side Document Handlers

    Network handlers for the document system.
    Handles writing, reading, erasing, and signatures.
]]--

-- Network strings owned by this plugin, so it is self-contained: a schema that includes the
-- documents plugin gets these without having to register them itself. util.AddNetworkString is
-- idempotent, so this is safe even if a schema also registers them. (fw-low-docnet)
util.AddNetworkString("wsDocumentData")   -- Server->Client: send document content
util.AddNetworkString("wsSignatureSave")  -- Client->Server: save signature to character

-- ============================================================================
-- DOCUMENT WRITE HANDLER
-- ============================================================================

-- Migrated to ws.action: item = "paper" + access = "owned" preserves the original paper ownership
-- check (MAIN inventory + "paper" uniqueID); the empty-write check and the writing-tool ownership
-- move into onValidate; the remaining wire fields (tool id, content, signature) read in def.read.
ws.action.Register("wsDocumentWrite", {
    item = "paper",
    access = "owned",
    read = function()
        -- Remaining payload after def.item consumes the paper id (UInt32), in original wire order.
        local toolItemID = net.ReadUInt(32)
        local content = net.ReadString()
        local hasSignature = net.ReadBool()
        local signatureJSON = hasSignature and net.ReadString() or nil
        return {
            toolItemID = toolItemID,
            content = content,
            hasSignature = hasSignature,
            signatureJSON = signatureJSON
        }
    end,
    onValidate = function(client, ctx)
        local char = client:GetCharacter()
        if not char then return false end

        -- Check if there's content to write
        if ctx.data.content == "" and not ctx.data.hasSignature then
            return false
        end

        -- Validate writing tool ownership
        local toolItem = ws.access.VerifyItemOwnership(client, ctx.data.toolItemID)
        if not toolItem then
            client:NotifyLocalized("needWritingTool")
            return false
        end

        ctx.char = char
        ctx.toolItem = toolItem
        return true
    end,
    run = function(client, ctx)
        local item = ctx.item
        local toolItem = ctx.toolItem
        local content = ctx.data.content
        local hasSignature = ctx.data.hasSignature
        local signatureJSON = ctx.data.signatureJSON

        -- Determine tool type, resource, and color
        local toolType
        local resourceKey
        local strokeColor

        -- Check if it's a pen (base pen or colored variants)
        local isPen = toolItem.uniqueID == "pen" or
                      toolItem.uniqueID == "pen_black" or
                      toolItem.uniqueID == "pen_red" or
                      toolItem.uniqueID == "pen_green"

        if isPen then
            toolType = "handwritten"
            resourceKey = "ink"
            strokeColor = toolItem:GetInkColor()
        elseif toolItem.uniqueID == "pencil" or toolItem.uniqueID == "pencil_eraser" then
            toolType = "pencil"
            resourceKey = "lead"
            strokeColor = {150, 150, 150}  -- Gray for pencil
        else
            client:NotifyLocalized("needWritingTool")
            return
        end

        -- Limit content length BEFORE costing it (so ink/lead isn't charged for text
        -- that gets discarded by truncation)
        if #content > ws.documents.MAX_CONTENT_LENGTH then
            content = string.sub(content, 1, ws.documents.MAX_CONTENT_LENGTH)
        end

        -- Get or create paper ID
        local paperID = item:GetPaperID()
        local isNewDocument = not paperID

        if isNewDocument then
            paperID = ws.documents.GenerateID()
        end

        -- Load existing document or create new
        local docData = ws.documents.Load(paperID) or {
            content = "",
            entries = {}
        }

        -- Cap the TOTAL accumulated document size (not just each write), BEFORE costing, so a
        -- player can't grow one document file without bound by writing repeatedly. (sc-schema-glue-1)
        if content ~= "" and #docData.content + #content > ws.documents.MAX_DOCUMENT_LENGTH then
            local room = ws.documents.MAX_DOCUMENT_LENGTH - #docData.content

            if room <= 0 then
                client:NotifyLocalized("documentFull")
                return
            end

            content = string.sub(content, 1, room)
        end

        -- Calculate resource cost
        local contentCost = #content
        local signatureCost = hasSignature and 50 or 0
        local totalCost = contentCost + signatureCost

        -- Check resource availability
        local currentResource
        if resourceKey == "ink" then
            currentResource = toolItem:GetInk()
        else
            currentResource = toolItem:GetLead()
        end

        if totalCost > currentResource then
            client:NotifyLocalized("notEnough" .. (resourceKey == "ink" and "Ink" or "Lead"))
            return
        end

        -- Append new content
        if content ~= "" then
            -- Add entry record with color. Fog-of-war: do NOT record the writer's character
            -- name. Authorship comes ONLY from a signature or the writer physically typing their
            -- name into the content; otherwise the document is anonymous. (sc-schema-glue-2)
            table.insert(docData.entries, {
                timestamp = os.time(),
                type = toolType,
                color = strokeColor,
                length = #content
            })

            -- Append to content
            if docData.content ~= "" then
                docData.content = docData.content .. "\n\n" .. content
            else
                docData.content = content
            end
        end

        -- Add signature (supports multiple signatures). Validate/limit stroke data so
        -- this path can't bypass the caps enforced by wsSignatureSave.
        if hasSignature and signatureJSON then
            local sigData = ws.documents.ValidateSignature(util.JSONToTable(signatureJSON))
            if sigData then
                -- Initialize signatures array if not present
                docData.signatures = docData.signatures or {}

                -- Add new signature with color
                -- Fog of war: the drawn strokes ARE the signature -- the mark the character
                -- physically made. We do NOT store the character's real name, so nothing on
                -- the wire links a signature to an identity. (fw-fogofwar-1)
                table.insert(docData.signatures, {
                    strokes = sigData,
                    timestamp = os.time(),
                    color = strokeColor,
                    type = toolType  -- "handwritten" for pen, "pencil" for pencil
                })
            end
        end

        -- Save document file
        if not ws.documents.Save(paperID, docData) then
            client:NotifyLocalized("documentSaveFailed")
            return
        end

        -- Update item data
        item:SetData("paperID", paperID)

        -- Only set document type on first write. Fog-of-war: don't store the author's character
        -- name (anonymous unless signed or self-identified in the content). (sc-schema-glue-2)
        if isNewDocument then
            item:SetData("documentType", toolType)
            item:SetData("timestamp", os.time())
        end

        item:SetData("wordCount", ws.documents.CountWords(docData.content))
        item:SetData("lastEdited", os.time())

        if hasSignature then
            item:SetData("hasSignature", true)
            -- Store count of signatures for display
            item:SetData("signatureCount", #(docData.signatures or {}))
        end

        -- Consume resource from tool through the atomic kernel (consistency + never
        -- mint from nothing). Falls back to the item helper if the key is unknown. (sc-schema-glue-7)
        if not ws.resource.Consume(toolItem, toolItem.resourceName, totalCost, toolItem.maxResource) then
            if resourceKey == "ink" then
                toolItem:UseInk(totalCost)
            else
                toolItem:UseLead(totalCost)
            end
        end

        client:NotifyLocalized("documentSaved")
    end
})

-- ============================================================================
-- DOCUMENT READ HANDLER
-- ============================================================================

-- Migrated to ws.action: def.item="paper" performs the accessibility check (main inv or an
-- owned container) by construction, replacing the hand-rolled net.Receive. (fw-core-security-1 / layer-1)
ws.action.Register("wsDocumentRead", {
    item = "paper",
    read = function() return net.ReadBool() end,  -- forEditor
    run = function(client, ctx)
        local item = ctx.item
        local forEditor = ctx.data

        local paperID = item:GetPaperID()
        if not paperID then return end

        -- Load document
        local docData = ws.documents.Load(paperID)
        if not docData then return end

        -- Fog-of-war: the response carries NO author identity. A reader learns who wrote a
        -- document only from its signatures, or if the writer typed their name into the
        -- content. (sc-schema-glue-2)
        local response = {
            content = docData.content or "",
            documentType = item:GetDocumentType(),
            wordCount = item:GetWordCount(),
            signatures = docData.signatures or {},
            entries = docData.entries or {}
        }

        net.Start("wsDocumentData")
            net.WriteBool(forEditor)
            net.WriteString(util.TableToJSON(response))
        net.Send(client)
    end
})

-- ============================================================================
-- DOCUMENT ERASE HANDLER
-- ============================================================================

-- Migrated to ws.action: def.item="paper" + access="owned" enforces main-inventory ownership
-- by construction. (fw-core-security-1 / layer-1)
ws.action.Register("wsDocumentErase", {
    item = "paper",
    access = "owned",
    run = function(client, ctx)
    local item = ctx.item

    -- Check if document is erasable (pencil only)
    if item:GetDocumentType() ~= "pencil" then
        client:NotifyLocalized("cannotErasePen")
        return
    end

    -- Find eraser in inventory (standalone eraser or pencil with eraser)
    local _, inv = ws.access.GetCharacterInventory(client)
    if not inv then return end

    local eraserItem = nil
    for _, invItem in pairs(inv:GetItems()) do
        if invItem.uniqueID == "eraser" and invItem:GetDurability() > 0 then
            eraserItem = invItem
            break
        elseif invItem.uniqueID == "pencil_eraser" then
            eraserItem = invItem
            break
        end
    end

    if not eraserItem then
        client:NotifyLocalized("needEraser")
        return
    end

    -- Get document data for eraser cost calculation
    local paperID = item:GetPaperID()
    if not paperID then return end

    local docData = ws.documents.Load(paperID)
    if not docData then return end

    local contentLength = #(docData.content or "")

    -- Check and consume eraser durability (if standalone eraser)
    if eraserItem.uniqueID == "eraser" then
        local durability = eraserItem:GetDurability()
        if durability < contentLength then
            client:NotifyLocalized("eraserNotEnoughDurability")
            return
        end

        -- Consume durability through the atomic kernel for consistency. (sc-schema-glue-7)
        if not ws.resource.Consume(eraserItem, "durability", contentLength, eraserItem.maxDurability) then
            eraserItem:UseDurability(contentLength)
        end
    end
    -- Pencil with eraser has unlimited erasing (no durability cost)

    -- Delete the document file
    ws.documents.Delete(paperID)

    -- Reset item data to blank paper
    item:SetData("paperID", nil)
    item:SetData("documentType", nil)
    item:SetData("author", nil)
    item:SetData("wordCount", nil)
    item:SetData("hasSignature", nil)
    item:SetData("signatureAuthor", nil)
    item:SetData("timestamp", nil)
    item:SetData("lastEdited", nil)

    client:NotifyLocalized("documentErased")
    end
})

-- ============================================================================
-- PEN REFILL HANDLER
-- ============================================================================

-- ============================================================================
-- DOCUMENT DESTROY HANDLER
-- ============================================================================

-- Migrated to ws.action: item="paper" + access="owned" enforces ownership by construction.
-- (fw-core-security-1 / layer-1)
ws.action.Register("wsDocumentDestroy", {
    item = "paper",
    access = "owned",
    run = function(client, ctx)
        local item = ctx.item

        -- Delete document file if exists
        local paperID = item:GetPaperID()
        if paperID then
            ws.documents.Delete(paperID)
        end

        -- Remove the item
        item:Remove()

        client:NotifyLocalized("documentDestroyed")
    end
})

-- ============================================================================
-- CONTAINER RENAME HANDLER (envelopes, folders)
-- ============================================================================

-- Rename an envelope/folder container. Migrated to ws.action: item = true + access = "owned"
-- reproduces VerifyItemOwnership (main-inventory ownership, no uniqueID filter); the container
-- whitelist and the writing-tool requirement move into onValidate; rateLimit replaces the
-- hand-rolled wsNextRename gate (and only charges once all guards pass). (sc-schema-glue-12)
ws.action.Register("wsContainerRename", {
    item = true,
    access = "owned",
    rateLimit = 1,
    read = function() return net.ReadString() end,  -- newName
    onValidate = function(client, ctx)
        -- Only envelopes/folders may be renamed.
        local validContainers = {
            envelope_small = true,
            envelope_large = true,
            folder = true
        }
        if not validContainers[ctx.item.uniqueID] then return false end

        -- Require a writing tool in inventory.
        if not ws.documents.HasWritingTool(client) then
            client:NotifyLocalized("needWritingTool")
            return false
        end
        return true
    end,
    run = function(client, ctx)
        local newName = ctx.data

        -- Set the custom name (empty string clears it)
        if newName == "" then
            ctx.item:SetData("customName", nil)
        else
            ctx.item:SetData("customName", string.sub(newName, 1, 32))
        end

        client:NotifyLocalized("containerRenamed")
    end
})

-- ============================================================================
-- SIGNATURE SAVE HANDLER
-- ============================================================================

net.Receive("wsSignatureSave", function(len, client)
    if not IsValid(client) then return end

    -- Rate-limit and size-bound before the JSON parse: signature saves are a rare, deliberate
    -- action, so drop spam and oversized payloads cheaply. `len` is the message size in bits;
    -- ~37 KB is far above any real signature and well under GMod's 64 KB net cap. (fw-low-signature)
    if client.wsNextSigSave and client.wsNextSigSave > CurTime() then return end
    if len > 300000 then return end
    client.wsNextSigSave = CurTime() + 1

    local signatureJSON = net.ReadString()

    -- Validate character
    local char = client:GetCharacter()
    if not char then return end

    -- Parse signature data (silent return on malformed JSON)
    local parsed = util.JSONToTable(signatureJSON)
    if type(parsed) ~= "table" then return end

    -- Validate and limit stroke data (prevent abuse)
    local strokes = ws.documents.ValidateSignature(parsed)
    if not strokes then
        client:NotifyLocalized("signatureTooComplex")
        return
    end

    -- Save to character data
    char:SetData("savedSignature", strokes)

    client:NotifyLocalized("signatureSaved")
end)

-- NOTE: pen refilling is handled by the writer base's `combine` function
-- (schema/items/base/sh_writer.lua), which is properly ownership-checked. The old
-- wsPenRefill net handler here was dead (no client ever sent it) and broken
-- (referenced a non-existent maxInk field), so it was removed along with its
-- network string in sv_netstrings.lua.
