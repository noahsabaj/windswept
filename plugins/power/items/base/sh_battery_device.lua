--[[
    Base Battery Device

    Base class for all battery-powered equipment (flashlight, lantern, camera, defibrillator).
    Provides common battery management, equip/unequip, and UI rendering.

    Override these properties in child items:
    - ITEM.weaponClass          (string)  SWEP class name, e.g., "ws_flashlight"
    - ITEM.playerItemKey        (string)  Player variable, e.g., "wsFlashlightItem"
    - ITEM.maxBatteries         (number)  Battery slot count, default 1
    - ITEM.equipSound           (string)  Sound on equip
    - ITEM.unequipSound         (string)  Sound on unequip (optional, uses equipSound at lower pitch)
    - ITEM.notifyPrefix         (string)  Localization prefix, e.g., "flashlight" -> "flashlightBatteryLoaded"
    - ITEM.requireFullBattery   (bool)    Only accept 100up batteries (defibrillator)
    - ITEM.hasLightToggle       (bool)    Has SetLight() method on weapon (flashlight, lantern)
]]--

ITEM.name = "Battery Device"
ITEM.description = "A battery-powered device."
ITEM.category = "Equipment"

-- Default configuration (override in children)
ITEM.maxBatteries = 1
ITEM.weaponClass = nil
ITEM.playerItemKey = nil
ITEM.equipSound = "items/battery_pickup.wav"
ITEM.unequipSound = nil  -- Uses equipSound at pitch 90 if nil
ITEM.notifyPrefix = "device"
ITEM.requireFullBattery = false
ITEM.hasLightToggle = false

-- ============================================================================
-- BATTERY HELPER FUNCTIONS
-- ============================================================================

function ITEM:GetBatteries()
    return self:GetData("batteries", {})
end

function ITEM:SetBatteries(batteries)
    self:SetData("batteries", batteries)
end

function ITEM:GetBatteryCount()
    return #self:GetBatteries()
end

function ITEM:HasBattery()
    return self:GetBatteryCount() > 0
end

function ITEM:HasUsableCharge()
    local batteries = self:GetBatteries()
    for _, charge in ipairs(batteries) do
        if self.requireFullBattery then
            if charge == 100 then return true end
        else
            if charge > 0 then return true end
        end
    end
    return false
end

function ITEM:GetFirstBatteryCharge()
    local batteries = self:GetBatteries()
    return batteries[1] or 0
end

-- Find the best battery in inventory
-- For requireFullBattery devices: finds any 100up battery
-- For normal devices: finds highest charge battery
-- Optimized: Uses GetItemsByUniqueID to avoid full inventory scan
function ITEM:FindBestBatteryInInventory(inventory)
    local batteries = inventory:GetItemsByUniqueID("battery", false)  -- false = don't check bags
    if #batteries == 0 then return nil, -1 end

    local bestBattery = nil
    local bestCharge = -1

    for i = 1, #batteries do
        local invItem = batteries[i]
        local charge = invItem:GetData("charge", 100)

        if self.requireFullBattery then
            -- Only accept full batteries - return immediately when found
            if charge == 100 then
                return invItem, 100
            end
        else
            -- Accept any, prefer highest
            if charge > bestCharge then
                bestCharge = charge
                bestBattery = invItem
            end
        end
    end

    return bestBattery, bestCharge
end

-- Alias for defibrillator compatibility
-- Optimized: Uses GetItemsByUniqueID and early exit
function ITEM:FindFullBatteryInInventory(inventory)
    local batteries = inventory:GetItemsByUniqueID("battery", false)

    for i = 1, #batteries do
        if batteries[i]:GetData("charge", 100) == 100 then
            return batteries[i]
        end
    end

    return nil
end

-- Auto-eject depleted batteries if enabled
function ITEM:AutoEjectDepleted(client)
    if not ws.option.Get(client, "batteryAutoEject", true) then
        return false
    end

    local batteries = self:GetBatteries()
    local character, inventory = ws.access.GetCharacterInventory(client)
    if not character or not inventory then return false end

    local ejected = false

    -- For requireFullBattery devices, eject anything < 100
    -- For normal devices, eject only 0up batteries
    local threshold = self.requireFullBattery and 100 or 0

    for i = #batteries, 1, -1 do
        if batteries[i] < threshold or batteries[i] <= 0 then
            if inventory:FindEmptySlot(1, 1) then
                -- Verify the inventory Add committed before dropping the slot from the
                -- array, so a full inventory / hook veto can't silently destroy the
                -- battery (transactional eject). (sc-items-currency-battery-8)
                local added = inventory:Add("battery", 1, {charge = batteries[i]})
                if added ~= false then
                    table.remove(batteries, i)
                    ejected = true
                end
            end
        end
    end

    if ejected then
        self:SetBatteries(batteries)
        client:NotifyLocalized(self.notifyPrefix .. "BatteryEjected")
    end

    return ejected
end

-- Auto-load battery from inventory if enabled
function ITEM:AutoLoadFromInventory(client)
    if not ws.option.Get(client, "batteryAutoLoad", true) then
        return false
    end

    local batteries = self:GetBatteries()
    if #batteries >= self.maxBatteries then
        return false
    end

    local character, inventory = ws.access.GetCharacterInventory(client)
    if not character or not inventory then return false end

    local bestBattery, bestCharge = self:FindBestBatteryInInventory(inventory)
    if not bestBattery then return false end

    -- For normal devices, don't auto-load 0up batteries
    if not self.requireFullBattery and bestCharge <= 0 then
        return false
    end

    table.insert(batteries, bestCharge)
    self:SetBatteries(batteries)
    bestBattery:Remove()

    client:NotifyLocalized(self.notifyPrefix .. "AutoLoaded", bestCharge)
    return true
end

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        local batteries = item:GetData("batteries", {})
        local maxBatteries = item.maxBatteries
        local isEquipped = item:GetData("equipped")

        -- Draw equipped indicator (green dot)
        if isEquipped then
            ws.constants.DrawEquippedIndicator(w, h)
        end

        -- Draw battery bar(s)
        if maxBatteries == 1 then
            -- Single battery: continuous bar
            if #batteries > 0 then
                local charge = batteries[1]

                -- Background bar
                surface.SetDrawColor(30, 30, 30, 200)
                surface.DrawRect(4, h - 12, w - 8, 8)

                -- Charge fill with granular colors
                local chargeWidth = ((w - 8) / 100) * charge
                surface.SetDrawColor(ws.constants.GetChargeColor(charge))
                surface.DrawRect(4, h - 12, chargeWidth, 8)
            end
        else
            -- Multiple slots: segmented display
            surface.SetDrawColor(30, 30, 30, 200)
            surface.DrawRect(4, h - 12, w - 8, 8)

            local slotWidth = (w - 8) / maxBatteries
            for i = 1, maxBatteries do
                local charge = batteries[i]
                if charge then
                    if charge == 100 then
                        surface.SetDrawColor(50, 200, 50)
                    elseif charge > 0 then
                        surface.SetDrawColor(200, 200, 50)
                    else
                        surface.SetDrawColor(200, 50, 50)
                    end
                    surface.DrawRect(4 + slotWidth * (i - 1), h - 12, slotWidth, 8)
                end
            end

            -- Draw separators
            surface.SetDrawColor(0, 0, 0, 255)
            for i = 1, maxBatteries - 1 do
                local x = 4 + slotWidth * i
                surface.DrawRect(x - 1, h - 12, 2, 8)
            end
        end
    end

    function ITEM:PopulateTooltip(tooltip)
        local batteries = self:GetData("batteries", {})

        local batteryRow = tooltip:AddRow("battery")

        if #batteries == 0 then
            batteryRow:SetText("No battery inserted.")
            batteryRow:SetBackgroundColor(Color(100, 100, 100))
        elseif self.maxBatteries == 1 then
            -- Single battery display
            local charge = batteries[1]
            batteryRow:SetText(string.format("Battery: %dup / 100up", charge))

            batteryRow:SetBackgroundColor(ws.constants.GetChargeColorDark(charge))
        else
            -- Multiple battery display (defibrillator style)
            local fullCount, partialCount, depletedCount = 0, 0, 0
            for _, charge in ipairs(batteries) do
                if charge == 100 then fullCount = fullCount + 1
                elseif charge > 0 then partialCount = partialCount + 1
                else depletedCount = depletedCount + 1 end
            end

            batteryRow:SetText(string.format("Batteries: %d full, %d partial, %d depleted",
                fullCount, partialCount, depletedCount))

            if fullCount == 0 then
                batteryRow:SetBackgroundColor(Color(150, 50, 50))
            elseif fullCount <= 1 then
                batteryRow:SetBackgroundColor(Color(150, 100, 50))
            else
                batteryRow:SetBackgroundColor(Color(50, 100, 50))
            end
        end

        batteryRow:SizeToContents()

        -- Add requirement note for full-battery devices
        if self.requireFullBattery then
            ws.constants.AddTooltipRow(tooltip, "requirement", "Requires fully charged batteries (100up)", Color(75, 75, 100))
        end
    end
end

-- ============================================================================
-- ITEM FUNCTIONS - BATTERY MANAGEMENT
-- ============================================================================

ITEM.functions.LoadBattery = {
    name = "Load Battery",
    tip = "Insert a battery.",
    icon = "icon16/lightning_add.png",
    isMulti = true,
    multiOptions = function(item, client)
        local options = {}
        local character, inventory = ws.access.GetCharacterInventory(client)
        if not character or not inventory then return options end

        local filterEmpty = ws.option.Get(client, "batteryFilterEmpty", true)

        for _, invItem in pairs(inventory:GetItems()) do
            if invItem.uniqueID == "battery" then
                local charge = invItem:GetData("charge", 100)

                local showBattery = true
                if item.requireFullBattery then
                    showBattery = (charge == 100)
                elseif filterEmpty then
                    showBattery = (charge > 0)
                end

                if showBattery then
                    local name = item.requireFullBattery
                        and "Battery (100up - Full)"
                        or string.format("Battery (%dup)", charge)

                    table.insert(options, {
                        name = name,
                        data = {batteryID = invItem:GetID(), charge = charge}
                    })
                end
            end
        end

        -- Sort by charge (highest first)
        table.sort(options, function(a, b)
            return (a.data.charge or 0) > (b.data.charge or 0)
        end)

        return options
    end,
    OnRun = function(item, data)
        local client = item.player
        if not IsValid(client) then return false end

        local batteryID = data and data.batteryID
        if not batteryID then return false end

        -- Validate the battery belongs to the caller. Windswept only ownership-checks
        -- the acting item (the device); arbitrary data fields like batteryID are
        -- attacker-controlled, so without this a crafted ID could consume another
        -- player's (or a dropped) battery.
        local batteryItem = ws.access.VerifyItemAccessible(client, batteryID, "battery")
        if not batteryItem then
            return false
        end

        local charge = batteryItem:GetData("charge", 100)

        -- Verify full charge if required
        if item.requireFullBattery and charge ~= 100 then
            client:NotifyLocalized(item.notifyPrefix .. "RequiresFull")
            return false
        end

        local batteries = item:GetBatteries()
        if #batteries >= item.maxBatteries then
            client:NotifyLocalized(item.notifyPrefix .. "SlotFull")
            return false
        end

        -- Load the battery
        table.insert(batteries, charge)
        item:SetBatteries(batteries)
        batteryItem:Remove()

        client:NotifyLocalized(item.notifyPrefix .. "BatteryLoaded", charge)
        client:EmitSound("items/battery_pickup.wav", 50)

        return false
    end,
    OnCanRun = function(item)
        if item:GetBatteryCount() >= item.maxBatteries then return false end
        if IsValid(item.entity) then return false end

        local client = item.player
        if not IsValid(client) then return false end

        local character, inventory = ws.access.GetCharacterInventory(client)
        if not character or not inventory then return false end

        for _, invItem in pairs(inventory:GetItems()) do
            if invItem.uniqueID == "battery" then
                if item.requireFullBattery then
                    if invItem:GetData("charge", 100) == 100 then
                        return true
                    end
                else
                    return true
                end
            end
        end

        return false
    end
}

ITEM.functions.EjectBattery = {
    name = "Eject Battery",
    tip = "Remove a battery.",
    icon = "icon16/lightning_delete.png",
    OnRun = function(item)
        local client = item.player
        local batteries = item:GetBatteries()

        if #batteries == 0 then
            return false
        end

        -- If equipped and has light toggle, turn it off first
        if item:GetData("equipped") and item.hasLightToggle and item.weaponClass then
            local weapon = client:GetWeapon(item.weaponClass)
            if IsValid(weapon) and weapon.SetLight then
                weapon:SetLight(false)
            end
        end

        -- For multi-battery devices: eject lowest charge first
        local ejectIndex = 1
        if #batteries > 1 then
            local lowestCharge = batteries[1]
            for i, charge in ipairs(batteries) do
                if charge < lowestCharge then
                    lowestCharge = charge
                    ejectIndex = i
                end
            end
        end

        -- Ensure the ejected battery has a free slot BEFORE removing it from the device;
        -- otherwise a full inventory silently destroys the battery. (sc-items-currency-battery-1)
        local character = client:GetCharacter()
        local inventory = character and character:GetInventory()

        if not inventory or not inventory:FindEmptySlot(1, 1) then
            client:NotifyLocalized("inventoryFull")
            return false
        end

        -- Add the ejected battery to the inventory FIRST and confirm it committed;
        -- only then drop it from the device array, so a failed Add can't destroy the
        -- charge (transactional eject). (sc-items-currency-battery-8)
        local charge = batteries[ejectIndex]
        local added = inventory:Add("battery", 1, {charge = charge})
        if added == false then
            client:NotifyLocalized("inventoryFull")
            return false
        end

        table.remove(batteries, ejectIndex)
        item:SetBatteries(batteries)

        client:NotifyLocalized(item.notifyPrefix .. "BatteryEjected")
        client:EmitSound("items/battery_pickup.wav", 50, 90)

        return false
    end,
    OnCanRun = function(item)
        if not item:HasBattery() then return false end
        if IsValid(item.entity) then return false end
        return true
    end
}

-- ============================================================================
-- ITEM FUNCTIONS - EQUIP/UNEQUIP
-- ============================================================================

ITEM.functions.Equip = {
    name = "Equip",
    tip = "Hold this item in your hands.",
    icon = "icon16/tick.png",
    OnRun = function(item)
        local client = item.player

        if not item.weaponClass or not item.playerItemKey then
            ErrorNoHalt("[Battery Device] Missing weaponClass or playerItemKey on " .. item.uniqueID .. "\n")
            return false
        end

        -- Unequip any existing item of this type from this player
        local existingItem = client[item.playerItemKey]
        if existingItem and existingItem ~= item then
            existingItem:SetData("equipped", nil)
        end

        -- Strip existing SWEP if any
        if client:HasWeapon(item.weaponClass) then
            client:StripWeapon(item.weaponClass)
        end

        -- Give the SWEP
        local weapon = client:Give(item.weaponClass)
        if IsValid(weapon) then
            weapon.wsItem = item
            client:SelectWeapon(item.weaponClass)
        end

        client[item.playerItemKey] = item
        item:SetData("equipped", true)

        client:EmitSound(item.equipSound, 50)

        return false
    end,
    OnCanRun = function(item)
        if IsValid(item.entity) then return false end
        if item:GetData("equipped") then return false end
        if not item.weaponClass then return false end
        return true
    end
}

ITEM.functions.Unequip = {
    name = "Unequip",
    tip = "Put this item away.",
    icon = "icon16/cross.png",
    OnRun = function(item)
        local client = item.player

        if not item.weaponClass or not item.playerItemKey then
            return false
        end

        local weapon = client:GetWeapon(item.weaponClass)
        if IsValid(weapon) then
            -- Turn off light first if applicable
            if item.hasLightToggle and weapon.SetLight then
                weapon:SetLight(false)
            end
            client:StripWeapon(item.weaponClass)
        end

        client[item.playerItemKey] = nil
        item:SetData("equipped", nil)

        local sound = item.unequipSound or item.equipSound
        local pitch = item.unequipSound and 100 or 90
        client:EmitSound(sound, 50, pitch)

        return false
    end,
    OnCanRun = function(item)
        return item:GetData("equipped") == true
    end
}

-- ============================================================================
-- HOOKS
-- ============================================================================

function ITEM.postHooks.drop(item, result)
    if item:GetData("equipped") and item.weaponClass and item.playerItemKey then
        local client = item:GetOwner()
        if IsValid(client) then
            local weapon = client:GetWeapon(item.weaponClass)
            if IsValid(weapon) then
                if item.hasLightToggle and weapon.SetLight then
                    weapon:SetLight(false)
                end
                client:StripWeapon(item.weaponClass)
            end
            client[item.playerItemKey] = nil
        end
        item:SetData("equipped", nil)
    end
end

function ITEM:OnTransferred(oldInventory, newInventory)
    if self:GetData("equipped") and self.weaponClass and self.playerItemKey then
        local oldOwner = oldInventory and oldInventory.GetOwner and oldInventory:GetOwner()
        if IsValid(oldOwner) then
            local weapon = oldOwner:GetWeapon(self.weaponClass)
            if IsValid(weapon) then
                if self.hasLightToggle and weapon.SetLight then
                    weapon:SetLight(false)
                end
                oldOwner:StripWeapon(self.weaponClass)
            end
            oldOwner[self.playerItemKey] = nil
        end
        self:SetData("equipped", nil)
    end
end

function ITEM:CanTransfer(oldInventory, newInventory)
    if newInventory and self:GetData("equipped") then
        local owner = self:GetOwner()
        if IsValid(owner) then
            owner:NotifyLocalized(self.notifyPrefix .. "Equipped")
        end
        return false
    end
    return true
end

function ITEM:OnLoadout()
    if self:GetData("equipped") and self.weaponClass and self.playerItemKey then
        local client = self.player
        if not IsValid(client) then return end

        local weapon = client:Give(self.weaponClass, true)
        if IsValid(weapon) then
            weapon.wsItem = self
            client[self.playerItemKey] = self

            -- Ensure light is off on loadout
            if self.hasLightToggle and weapon.SetLight then
                weapon:SetLight(false)
            end
        end
    end
end
