--[[
    Base Document Container

    Intermediate base for paper-holding containers (envelopes, folders).
    Inherits from base_container (bag infrastructure).

    Child items configure via properties:
        ITEM.containerLabel     -- Label for UI text (e.g., "envelope", "folder")

    Provides:
        - GetName() with customName support
        - GetDescription() with paper count
        - OnRemoveContents() for document file cleanup
        - Rename function (requires writing tool)
]]--

ITEM.name = "Document Container"
ITEM.description = "A container for documents."
ITEM.model = "models/props_c17/paper01.mdl"
ITEM.category = "Containers"
ITEM.base = "base_container"
ITEM.width = 1
ITEM.height = 1
ITEM.invWidth = 5
ITEM.invHeight = 1

ITEM.inventoryFlag = "isDocumentContainer"
ITEM.allowedItemType = "paper"
ITEM.containerLabel = "container"

-- ============================================================================
-- NAME & DESCRIPTION
-- ============================================================================

function ITEM:GetName()
    local customName = self:GetData("customName")
    if customName and customName ~= "" then
        return customName
    end
    return self.name
end

function ITEM:GetDescription()
    local desc = self.description
    local invID = self:GetData("id")

    if invID then
        local inv = ws.item.inventories[invID]
        if inv then
            local count = 0
            for _ in pairs(inv:GetItems()) do
                count = count + 1
            end
            desc = desc .. string.format("\n\nContains: %d paper(s)", count)
        end
    end

    return desc
end

-- ============================================================================
-- DOCUMENT FILE CLEANUP
-- ============================================================================

function ITEM:OnRemoveContents(inv)
    for _, containedItem in pairs(inv:GetItems()) do
        if containedItem.uniqueID == "paper" then
            local paperID = containedItem:GetPaperID()
            if paperID then
                ws.documents.Delete(paperID)
            end
        end
    end
end

-- ============================================================================
-- RENAME (requires pen/pencil in inventory)
-- ============================================================================

ITEM.functions.Rename = {
    name = "Name",
    tip = "writeTip",
    icon = "icon16/textfield_rename.png",
    OnRun = function(item)
        return false
    end,
    OnClick = function(item)
        local label = item.containerLabel or "container"
        local currentName = item:GetData("customName", "")

        Derma_StringRequest(
            "Name " .. label:sub(1, 1):upper() .. label:sub(2),
            "Write a name on this " .. label .. " (max 32 characters):",
            currentName,
            function(text)
                if text then
                    ws.action.Send("wsContainerRename", item:GetID(), nil, function()
                        net.WriteString(string.sub(text, 1, 32))
                    end)
                end
            end,
            function() end,
            "Write",
            "Cancel"
        )
        return false
    end,
    OnCanRun = function(item)
        if IsValid(item.entity) then return false end
        if not CLIENT then return true end

        return ws.documents.HasWritingTool(LocalPlayer())
    end
}
