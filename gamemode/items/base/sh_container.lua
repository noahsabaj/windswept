--[[
    Base Container Item

    Common bag infrastructure for all container items.
    Child items configure via properties and optionally override hook methods.

    Required child properties:
        ITEM.invWidth           -- Internal inventory width
        ITEM.invHeight          -- Internal inventory height
        ITEM.inventoryFlag      -- Inventory variable name (e.g., "isDocumentContainer")

    Optional child properties:
        ITEM.allowedItemType    -- Restrict to this uniqueID (e.g., "paper", "photo", "key")
        ITEM.allowedItemNotify  -- Notification key for wrong item type in combine
        ITEM.viewSuffix         -- Suffix for View panel title (e.g., " - Keys")

    Optional child overrides:
        ITEM:OnRemoveContents(inv)              -- Called before DB cleanup in OnRemoved
        ITEM:OnDropExtra()                      -- Called after standard drop handling
        ITEM:CanTransferExtra(old, new)         -- Return false to block transfer
        ITEM:OnTransferExtra(curInv, inventory) -- Called after standard transfer handling
        ITEM:PaintOverExtra(item, w, h)         -- Called after standard PaintOver
]]--

ITEM.name = "Container"
ITEM.description = "A container for items."
ITEM.category = "Storage"
ITEM.model = "models/props_c17/paper01.mdl"
ITEM.width = 1
ITEM.height = 1

ITEM.isBag = true
ITEM.noBusiness = true

-- Override in child items
ITEM.invWidth = 5
ITEM.invHeight = 1
ITEM.inventoryFlag = "isContainer"
ITEM.allowedItemType = nil
ITEM.allowedItemNotify = nil
ITEM.viewSuffix = nil

-- ============================================================================
-- BAG SYSTEM
-- ============================================================================

function ITEM:OnInstanced(invID, x, y)
    local inventory = ws.item.inventories[invID]

    ws.inventory.New(inventory and inventory.owner or 0, self.uniqueID, function(inv)
        local client = inv:GetOwner()

        inv.vars.isBag = self.uniqueID
        inv.vars[self.inventoryFlag] = true
        self:SetData("id", inv:GetID())

        if IsValid(client) then
            inv:AddReceiver(client)
        end
    end)
end

function ITEM:GetInventory()
    local index = self:GetData("id")
    if index then
        return ws.item.inventories[index]
    end
end

ITEM.GetInv = ITEM.GetInventory

function ITEM:OnSendData()
    local index = self:GetData("id")

    if index then
        local inventory = ws.item.inventories[index]

        if inventory then
            inventory.vars.isBag = self.uniqueID
            inventory.vars[self.inventoryFlag] = true
            inventory:Sync(self.player)
            inventory:AddReceiver(self.player)
        else
            local owner = self.player:GetCharacter():GetID()

            ws.inventory.Restore(self:GetData("id"), self.invWidth, self.invHeight, function(inv)
                inv.vars.isBag = self.uniqueID
                inv.vars[self.inventoryFlag] = true
                inv:SetOwner(owner, true)

                if not inv.owner then
                    return
                end

                for client, character in ws.util.GetCharacters() do
                    if character:GetID() == inv.owner then
                        inv:AddReceiver(client)
                        break
                    end
                end
            end)
        end
    else
        ws.inventory.New(self.player:GetCharacter():GetID(), self.uniqueID, function(inv)
            inv.vars[self.inventoryFlag] = true
            self:SetData("id", inv:GetID())
        end)
    end
end

function ITEM.postHooks.drop(item, result)
    local index = item:GetData("id")

    local query = mysql:Update("ws_inventories")
        query:Update("character_id", 0)
        query:Where("inventory_id", index)
    query:Execute()

    if SERVER then
        net.Start("wsBagDrop")
            net.WriteUInt(index, 32)
        net.Send(item.player)
    end

    if item.OnDropExtra then
        item:OnDropExtra()
    end
end

function ITEM:OnRemoved()
    local index = self:GetData("id")

    if index then
        if self.OnRemoveContents then
            local inv = ws.item.inventories[index]
            if inv then
                self:OnRemoveContents(inv)
            end
        end

        local query = mysql:Delete("ws_items")
            query:Where("inventory_id", index)
        query:Execute()

        query = mysql:Delete("ws_inventories")
            query:Where("inventory_id", index)
        query:Execute()
    end
end

function ITEM:CanTransfer(oldInventory, newInventory)
    if self.CanTransferExtra and self:CanTransferExtra(oldInventory, newInventory) == false then
        return false
    end

    local index = self:GetData("id")

    if newInventory then
        if newInventory.vars and newInventory.vars.isBag then
            return false
        end

        local index2 = newInventory:GetID()

        if index == index2 then
            return false
        end

        local bagInv = self:GetInventory()
        if bagInv then
            for k, _ in bagInv:Iter() do
                if k:GetData("id") == index2 then
                    return false
                end
            end
        end
    end

    return not newInventory or newInventory:GetID() ~= oldInventory:GetID() or newInventory.vars.isBag
end

function ITEM:OnTransferred(curInv, inventory)
    local bagInventory = self:GetInventory()
    if not bagInventory then return end

    if isfunction(curInv.GetOwner) then
        local owner = curInv:GetOwner()
        if IsValid(owner) then
            bagInventory:RemoveReceiver(owner)
        end
    end

    if isfunction(inventory.GetOwner) then
        local owner = inventory:GetOwner()
        if IsValid(owner) then
            bagInventory:AddReceiver(owner)
            bagInventory:SetOwner(owner)
        end
    else
        bagInventory:SetOwner(nil)
    end

    if self.OnTransferExtra then
        self:OnTransferExtra(curInv, inventory)
    end
end

function ITEM:OnRegistered()
    ws.inventory.Register(self.uniqueID, self.invWidth, self.invHeight, true)

    -- Auto-register container item type restriction
    if self.inventoryFlag and self.allowedItemType then
        ws.containerRestrictions[self.inventoryFlag] = self.allowedItemType
    end
end

-- ============================================================================
-- VIEW FUNCTION (Windswept auto-bag-open)
-- ============================================================================

ITEM.functions.View = {
    name = "Open",
    tip = "View the contents.",
    icon = "icon16/folder.png",
    OnClick = ws.constants.OpenContainerPanel,
    OnCanRun = ws.constants.CanOpenContainerPanel
}

-- ============================================================================
-- COMBINE (drag items into bag)
-- ============================================================================

ITEM.functions.combine = {
    OnRun = function(item, data)
        if not item.allowedItemType then return false end

        local targetItem = ws.item.instances[data[1]]
        if not targetItem then return false end

        if targetItem.uniqueID ~= item.allowedItemType then
            if item.player and item.allowedItemNotify then
                item.player:NotifyLocalized(item.allowedItemNotify)
            end
            return false
        end

        targetItem:Transfer(item:GetData("id"), nil, nil, item.player)
        return false
    end,
    OnCanRun = function(item, data)
        if not item.allowedItemType then return false end

        local index = item:GetData("id", "")
        if index then
            local inventory = ws.item.inventories[index]
            if inventory then return true end
        end
        return false
    end
}

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        local panel = ws.gui["inv" .. item:GetData("id", "")]

        if IsValid(panel) and vgui.GetHoveredPanel() == self then
            panel:SetHighlighted(true)
        elseif IsValid(panel) then
            panel:SetHighlighted(false)
        end

        if item.PaintOverExtra then
            item:PaintOverExtra(w, h)
        end
    end

    net.Receive("wsBagDrop", function()
        local index = net.ReadUInt(32)
        local panel = ws.gui["inv"..index]

        if panel and panel:IsVisible() then
            panel:Close()
        end
    end)
end

-- ============================================================================
-- CONTAINER RESTRICTION SYSTEM
-- ============================================================================

-- Centralized container item type restrictions (replaces per-item hooks)
ws.containerRestrictions = ws.containerRestrictions or {}

hook.Add("CanTransferItem", "wsContainerRestriction", function(item, curInv, inventory)
    if not inventory or not inventory.vars then return end

    for flag, allowedType in pairs(ws.containerRestrictions) do
        if inventory.vars[flag] then
            if item.uniqueID ~= allowedType then
                return false
            end
        end
    end
end)
