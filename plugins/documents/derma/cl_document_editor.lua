--[[
    Document Editor

    Panel for writing on paper documents.
    Supports append-only writing, signatures (pen only), and ink/lead tracking.
]]--

local PANEL = {}

function PANEL:Init()
    self:SetSize(550, 600)
    self:Center()
    self:MakePopup()
    self:SetTitle("Write Document")
    self:SetDraggable(true)
    self:ShowCloseButton(true)

    self.paperItem = nil
    self.toolType = "pen"  -- "pen" or "pencil"
    self.resourceRemaining = 1000
    self.maxResource = 1000
    self.signatureData = nil
    self.existingContent = ""
    self.hasExistingContent = false
    self.strokeColor = {100, 100, 200}  -- Default blue

    -- Existing content section (read-only)
    self.existingLabel = vgui.Create("DLabel", self)
    self.existingLabel:Dock(TOP)
    self.existingLabel:DockMargin(10, 5, 10, 0)
    self.existingLabel:SetText("Existing content:")
    self.existingLabel:SetTextColor(Color(150, 150, 150))
    self.existingLabel:SetVisible(false)

    self.existingScroll = vgui.Create("DScrollPanel", self)
    self.existingScroll:Dock(TOP)
    self.existingScroll:DockMargin(10, 5, 10, 10)
    self.existingScroll:SetTall(120)
    self.existingScroll:SetVisible(false)

    self.existingText = vgui.Create("DLabel", self.existingScroll)
    self.existingText:Dock(TOP)
    self.existingText:SetWrap(true)
    self.existingText:SetAutoStretchVertical(true)
    self.existingText:SetTextColor(Color(180, 180, 180))

    -- New content label
    self.newLabel = vgui.Create("DLabel", self)
    self.newLabel:Dock(TOP)
    self.newLabel:DockMargin(10, 5, 10, 0)
    self.newLabel:SetText("Write new content:")
    self.newLabel:SetTextColor(ws.constants.COLOR_UI_NEUTRAL)

    -- New content text entry
    self.content = vgui.Create("DTextEntry", self)
    self.content:Dock(FILL)
    self.content:DockMargin(10, 5, 10, 10)
    self.content:SetMultiline(true)
    self.content:SetPlaceholderText("Begin writing...")
    self.content.OnChange = function()
        self:UpdateResourceCounter()
    end

    -- Bottom panel
    local bottomPanel = vgui.Create("DPanel", self)
    bottomPanel:Dock(BOTTOM)
    bottomPanel:SetTall(90)
    bottomPanel.Paint = function() end

    -- Resource counter
    self.resourceCounter = vgui.Create("DLabel", bottomPanel)
    self.resourceCounter:Dock(TOP)
    self.resourceCounter:DockMargin(10, 5, 10, 0)
    self.resourceCounter:SetText("Ink: 1000 remaining")
    self.resourceCounter:SetTextColor(ws.constants.COLOR_UI_NEUTRAL)

    -- Signature status
    self.sigStatus = vgui.Create("DLabel", bottomPanel)
    self.sigStatus:Dock(TOP)
    self.sigStatus:DockMargin(10, 2, 10, 5)
    self.sigStatus:SetText("")
    self.sigStatus:SetTextColor(Color(150, 200, 150))

    -- Button panel
    local btnPanel, btns = ws.constants.CreateButtonBar(bottomPanel, {
        {"Add Signature", 100, LEFT, function() self:OpenSignaturePad() end},
        {"Use Saved", 90, LEFT, function() self:UseSavedSignature() end},
        {"Cancel", 80, RIGHT, function() self:Remove() end},
        {"Save", 80, RIGHT, function() self:SaveDocument() end},
    })
    self.signBtn = btns[1]
    self.useSavedBtn = btns[2]

    -- Check if character has a saved signature
    local char = LocalPlayer():GetCharacter()
    local savedSig = char and char:GetData("savedSignature")
    self.useSavedBtn:SetEnabled(savedSig ~= nil)
    if not savedSig then
        self.useSavedBtn:SetTooltip("No saved signature")
    end
end

function PANEL:SetPaper(paperItem)
    -- Guard against a stale/removed item (e.g. dropped or transferred between the
    -- click and the panel build). Windswept items aren't entities, so check the table.
    if not paperItem or not paperItem.GetID or not ws.item.instances[paperItem:GetID()] then
        self:Remove()
        return
    end

    self.paperItem = paperItem

    -- Check for existing content
    if paperItem:HasContent() then
        self.hasExistingContent = true
        self.existingLabel:SetVisible(true)
        self.existingScroll:SetVisible(true)
        self.existingText:SetText("Loading...")

        -- Request existing content from server
        -- Store reference for callback
        ws.gui.documentEditor = self

        ws.action.Send("wsDocumentRead", paperItem:GetID(), nil, function() net.WriteBool(true) end)  -- for editor
    end
end

function PANEL:SetExistingContent(content)
    self.existingContent = content or ""
    self.existingText:SetText(content or "(empty)")
    self.existingText:SizeToContentsY()
end

function PANEL:SetWritingTool(toolType, toolItem)
    self.toolType = toolType
    self.toolItem = toolItem

    if toolType == "pen" then
        if toolItem then
            self.resourceRemaining = toolItem:GetInk()
            self.maxResource = toolItem.maxInk or 1000
            self.strokeColor = toolItem:GetInkColor()
        else
            self.strokeColor = {100, 100, 200}  -- Default blue
        end
        self.signBtn:SetEnabled(true)
        self.signBtn:SetText("Add Signature")
    else
        if toolItem then
            self.resourceRemaining = toolItem:GetLead()
            self.maxResource = toolItem.maxLead or 500
        end
        self.strokeColor = {150, 150, 150}  -- Gray for pencil
        -- Pencils CAN sign (but signature will be erasable)
        self.signBtn:SetEnabled(true)
        self.signBtn:SetText("Add Signature")
    end

    self:UpdateResourceCounter()
end

function PANEL:UpdateResourceCounter()
    local contentLength = #self.content:GetValue()
    local signatureCost = self.signatureData and 50 or 0
    local totalCost = contentLength + signatureCost
    local remaining = self.resourceRemaining - totalCost

    local resourceName = self.toolType == "pen" and "Ink" or "Lead"

    self.resourceCounter:SetText(string.format("%s: %d remaining (using %d)",
        resourceName, remaining, totalCost))

    if remaining < 0 then
        self.resourceCounter:SetTextColor(Color(255, 100, 100))
    elseif remaining < self.maxResource * 0.1 then
        self.resourceCounter:SetTextColor(Color(255, 200, 100))
    else
        self.resourceCounter:SetTextColor(ws.constants.COLOR_UI_NEUTRAL)
    end
end

function PANEL:OpenSignaturePad()
    if IsValid(self.sigPad) then
        self.sigPad:Remove()
    end

    self.sigPad = vgui.Create("wsSignaturePad")
    self.sigPad:SetStrokeColor(self.strokeColor)
    self.sigPad.OnConfirm = function(strokes)
        self:ApplySignature(strokes)
    end
end

function PANEL:UseSavedSignature()
    local char = LocalPlayer():GetCharacter()
    if not char then return end

    local savedSig = char:GetData("savedSignature")
    if not savedSig then
        LocalPlayer():NotifyLocalized("noSavedSignature")
        return
    end

    self:ApplySignature(savedSig)
end

function PANEL:ApplySignature(strokes)
    self.signatureData = strokes
    self.sigStatus:SetText("Signature added")
    self.signBtn:SetText("Signed")
    self.signBtn:SetEnabled(false)
    self.useSavedBtn:SetEnabled(false)
    self:UpdateResourceCounter()
end

function PANEL:SaveDocument()
    -- Guard against the paper item having been removed while the editor was open
    -- (server re-validates too, but this avoids a client-side nil error).
    if not self.paperItem or not self.paperItem.GetID or not ws.item.instances[self.paperItem:GetID()] then
        self:Remove()
        return
    end

    local content = self.content:GetValue()

    -- Check if there's anything to save
    if content == "" and not self.signatureData then
        LocalPlayer():NotifyLocalized("documentEmpty")
        return
    end

    -- Check resource availability
    local contentLength = #content
    local signatureCost = self.signatureData and 50 or 0
    local totalCost = contentLength + signatureCost

    if totalCost > self.resourceRemaining then
        LocalPlayer():NotifyLocalized("notEnough" .. (self.toolType == "pen" and "Ink" or "Lead"))
        return
    end

    -- Send to server (paper id via the item arg; tool id + content + signature follow)
    ws.action.Send("wsDocumentWrite", self.paperItem:GetID(), nil, function()
        net.WriteUInt(self.toolItem and self.toolItem:GetID() or 0, 32)  -- Tool item ID
        net.WriteString(content)
        net.WriteBool(self.signatureData ~= nil)
        if self.signatureData then
            net.WriteString(util.TableToJSON(self.signatureData))
        end
    end)

    self:Remove()
end

function PANEL:OnRemove()
    if IsValid(self.sigPad) then
        self.sigPad:Remove()
    end

    if ws.gui.documentEditor == self then
        ws.gui.documentEditor = nil
    end
end

vgui.Register("wsDocumentEditor", PANEL, "DFrame")

-- ============================================================================
-- NETWORK RECEIVER FOR EDITOR CONTENT
-- ============================================================================

net.Receive("wsDocumentData", function()
    local forEditor = net.ReadBool()
    local jsonData = net.ReadString()
    local data = util.JSONToTable(jsonData)

    if not data then return end

    if forEditor then
        -- Update editor with existing content
        if IsValid(ws.gui.documentEditor) then
            ws.gui.documentEditor:SetExistingContent(data.content or "")
        end
    else
        -- Open viewer
        local viewer = vgui.Create("wsDocumentViewer")
        viewer:SetDocument(data)
    end
end)
