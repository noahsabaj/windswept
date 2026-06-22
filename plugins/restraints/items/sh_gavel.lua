--[[
    Gavel Item

    A wooden gavel prop for roleplay.
    Equip to slam and make authoritative noise.
]]--

ITEM.name = "Gavel"
ITEM.description = "A wooden gavel. Slam it on a surface to make an authoritative noise."
ITEM.model = Model("models/judge gavels & more/judge_gavel.mdl")
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"
ITEM.noBusiness = true

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
    tip = "Hold the gavel in your hands.",
    icon = "icon16/tick.png",
    OnRun = function(item)
        local client = item.player

        -- Check if already has a gavel equipped
        if client.wsGavelItem and client.wsGavelItem ~= item then
            local oldItem = client.wsGavelItem
            oldItem:SetData("equipped", nil)
        end

        -- Strip existing gavel SWEP if any
        if client:HasWeapon("ws_gavel") then
            client:StripWeapon("ws_gavel")
        end

        -- Give the SWEP
        local weapon = client:Give("ws_gavel")
        if IsValid(weapon) then
            weapon.wsItem = item
            client:SelectWeapon("ws_gavel")
        end

        client.wsGavelItem = item
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
    tip = "Put the gavel away.",
    icon = "icon16/cross.png",
    OnRun = function(item)
        local client = item.player

        -- Remove SWEP
        if client:HasWeapon("ws_gavel") then
            client:StripWeapon("ws_gavel")
        end

        client.wsGavelItem = nil
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
            if client:HasWeapon("ws_gavel") then
                client:StripWeapon("ws_gavel")
            end
            client.wsGavelItem = nil
        end
        item:SetData("equipped", nil)
    end
end

-- Handle transfer
function ITEM:OnTransferred(oldInventory, newInventory)
    if self:GetData("equipped") then
        local oldOwner = oldInventory and oldInventory.GetOwner and oldInventory:GetOwner()
        if IsValid(oldOwner) then
            if oldOwner:HasWeapon("ws_gavel") then
                oldOwner:StripWeapon("ws_gavel")
            end
            oldOwner.wsGavelItem = nil
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

        local weapon = client:Give("ws_gavel", true)
        if IsValid(weapon) then
            weapon.wsItem = self
            client.wsGavelItem = self
        end
    end
end
