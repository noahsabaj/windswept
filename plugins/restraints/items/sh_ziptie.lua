--[[
    Zip Tie Item

    Used to restrain players.
    - Equip to hold the zip tie
    - Raise weapon (R) then LMB on target
    - 5 second progress bar to restrain
    - Consumed on successful restraint
    - Untying returns zip tie to untier's inventory
]]--

ITEM.name = "Zip Tie"
ITEM.description = "A plastic zip-tie used to restrain people."
ITEM.model = "models/items/crossbowrounds.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.price = 10
ITEM.category = "Equipment"

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        if item:GetData("equipped") then
            surface.SetDrawColor(110, 255, 110, 200)
            surface.DrawRect(w - 14, h - 14, 8, 8)
        end
    end
end

-- ============================================================================
-- ITEM FUNCTIONS
-- ============================================================================

ITEM.functions.Equip = {
    name = "Equip",
    tip = "Hold the zip tie in your hands.",
    icon = "icon16/tick.png",
    OnRun = function(item)
        local client = item.player

        -- Check if already has a zip tie equipped
        if client.wsZipTieItem and client.wsZipTieItem ~= item then
            local oldItem = client.wsZipTieItem
            oldItem:SetData("equipped", nil)
        end

        -- Strip existing zip tie SWEP if any
        if client:HasWeapon("ws_ziptie") then
            client:StripWeapon("ws_ziptie")
        end

        -- Give the SWEP
        local weapon = client:Give("ws_ziptie")
        if IsValid(weapon) then
            weapon.wsItem = item
            client:SelectWeapon("ws_ziptie")
        end

        client.wsZipTieItem = item
        item:SetData("equipped", true)

        return false
    end,
    OnCanRun = function(item)
        -- Can't equip if on ground
        if IsValid(item.entity) then return false end
        -- Can't equip if already equipped
        if item:GetData("equipped") then return false end

        return true
    end
}

ITEM.functions.Unequip = {
    name = "Unequip",
    tip = "Put the zip tie away.",
    icon = "icon16/cross.png",
    OnRun = function(item)
        local client = item.player

        -- Remove SWEP
        if client:HasWeapon("ws_ziptie") then
            client:StripWeapon("ws_ziptie")
        end

        client.wsZipTieItem = nil
        item:SetData("equipped", nil)

        return false
    end,
    OnCanRun = function(item)
        return item:GetData("equipped") == true
    end
}

-- ============================================================================
-- HOOKS
-- ============================================================================

-- Unequip when dropped
function ITEM.postHooks.drop(item, result)
    if item:GetData("equipped") then
        local client = item:GetOwner()
        if IsValid(client) then
            if client:HasWeapon("ws_ziptie") then
                client:StripWeapon("ws_ziptie")
            end
            client.wsZipTieItem = nil
        end
        item:SetData("equipped", nil)
    end
end

-- Handle transfer
function ITEM:OnTransferred(oldInventory, newInventory)
    if self:GetData("equipped") then
        local oldOwner = oldInventory and oldInventory.GetOwner and oldInventory:GetOwner()
        if IsValid(oldOwner) then
            if oldOwner:HasWeapon("ws_ziptie") then
                oldOwner:StripWeapon("ws_ziptie")
            end
            oldOwner.wsZipTieItem = nil
        end
        self:SetData("equipped", nil)
    end
end

-- Can't transfer while equipped
function ITEM:CanTransfer(oldInventory, newInventory)
    if newInventory and self:GetData("equipped") then
        return false
    end
    return true
end

-- Restore equipped state on character load
function ITEM:OnLoadout()
    if self:GetData("equipped") then
        local client = self.player
        if not IsValid(client) then return end

        local weapon = client:Give("ws_ziptie", true)
        if IsValid(weapon) then
            weapon.wsItem = self
            client.wsZipTieItem = self
        end
    end
end
