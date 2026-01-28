
--- A library representing the server's currency system.
-- MODIFIED: Physical currency system - money is inventory items, not numeric values
-- @module ix.currency

ix.currency = ix.currency or {}
ix.currency.symbol = ix.currency.symbol or "$"
ix.currency.singular = ix.currency.singular or "dollar"
ix.currency.plural = ix.currency.plural or "dollars"
ix.currency.model = ix.currency.model or "models/props_lab/box01a.mdl"

-- Constants for physical currency
ix.currency.CASH_ITEM = "cash"
ix.currency.COINS_ITEM = "coins"
ix.currency.MAX_STACK = 100
ix.currency.CENTS_PER_DOLLAR = 100

--- Sets the currency type.
-- @realm shared
-- @string symbol The symbol of the currency.
-- @string singular The name of the currency in it's singular form.
-- @string plural The name of the currency in it's plural form.
-- @string model The model of the currency entity.
function ix.currency.Set(symbol, singular, plural, model)
    ix.currency.symbol = symbol
    ix.currency.singular = singular
    ix.currency.plural = plural
    ix.currency.model = model
end

--- Returns a formatted string according to the current currency.
-- MODIFIED: Now handles cents (internal precision)
-- @realm shared
-- @number amount The amount of cash in CENTS being formatted.
-- @treturn string The formatted string.
function ix.currency.Get(amount)
    -- amount is in cents, format as dollars
    local dollars = math.floor(amount / 100)
    local cents = amount % 100

    if cents == 0 then
        return ix.currency.symbol .. dollars
    else
        return string.format("%s%d.%02d", ix.currency.symbol, dollars, cents)
    end
end

--- Spawns an amount of cash at a specific location on the map.
-- NOTE: amount is in DOLLARS for backwards compatibility with existing code
-- @realm shared
-- @vector pos The position of the money to be spawned.
-- @number amount The amount of cash being spawned (in dollars).
-- @angle[opt=angle_zero] angle The angle of the entity being spawned.
-- @treturn entity The spawned money entity.
function ix.currency.Spawn(pos, amount, angle)
    if (!amount or amount < 0) then
        print("[Helix] Can't create currency entity: Invalid Amount of money")
        return
    end

    local money = ents.Create("ix_money")
    money:Spawn()

    if (IsValid(pos) and pos:IsPlayer()) then
        pos = pos:GetItemDropPos(money)
    elseif (!isvector(pos)) then
        print("[Helix] Can't create currency entity: Invalid Position")

        money:Remove()
        return
    end

    money:SetPos(pos)
    -- double check for negative.
    money:SetAmount(math.Round(math.abs(amount)))
    money:SetAngles(angle or angle_zero)
    money:Activate()

    return money
end

-- ============================================================================
-- PHYSICAL CURRENCY HELPERS
-- ============================================================================

--- Count total cents in an inventory
-- @realm shared
-- @param inventory The inventory to count currency in
-- @treturn number Total value in cents
function ix.currency.CountInInventory(inventory)
    if not inventory then return 0 end

    local total = 0
    for _, item in pairs(inventory:GetItems()) do
        if item.isCurrency then
            local quantity = item:GetData("quantity", 1)
            local value = item.currencyValue or 0
            total = total + (quantity * value)
        end
    end
    return total
end

--- Find currency items in inventory (sorted by value ascending - coins first)
-- @realm shared
-- @param inventory The inventory to search
-- @treturn table Array of currency items
function ix.currency.FindCurrencyItems(inventory)
    if not inventory then return {} end

    local items = {}
    for _, item in pairs(inventory:GetItems()) do
        if item.isCurrency then
            table.insert(items, item)
        end
    end

    -- Sort by currency value (coins first, then cash)
    table.sort(items, function(a, b)
        return (a.currencyValue or 0) < (b.currencyValue or 0)
    end)

    return items
end

--- Find slots available for new currency items
-- @realm server
-- @param inventory The inventory to search
-- @param count Number of slots needed
-- @treturn table Array of {x, y} slot positions
function ix.currency.FindEmptySlots(inventory, count)
    if not inventory then return {} end

    local slots = {}
    local w, h = inventory:GetSize()

    for x = 1, w do
        for y = 1, h do
            if not inventory.slots[x] or not inventory.slots[x][y] then
                table.insert(slots, {x = x, y = y})
                if #slots >= count then
                    return slots
                end
            end
        end
    end

    return slots
end

--- Add currency to inventory
-- @realm server
-- @param inventory The inventory to add to
-- @param cents Amount in cents to add
-- @treturn boolean True on success, false if no space
function ix.currency.AddToInventory(inventory, cents)
    if not inventory or cents <= 0 then return cents == 0 end

    local remaining = cents

    -- First, try to fill existing partial stacks
    local existingItems = ix.currency.FindCurrencyItems(inventory)

    -- Fill coin stacks first (for small amounts)
    for _, item in ipairs(existingItems) do
        if remaining <= 0 then break end

        local quantity = item:GetData("quantity", 1)
        local canAdd = ix.currency.MAX_STACK - quantity

        if canAdd > 0 and item.uniqueID == ix.currency.COINS_ITEM then
            local toAdd = math.min(canAdd, remaining)
            item:SetData("quantity", quantity + toAdd)
            remaining = remaining - toAdd
        end
    end

    -- Fill cash stacks (for larger amounts, convert cents to dollars)
    for _, item in ipairs(existingItems) do
        if remaining < ix.currency.CENTS_PER_DOLLAR then break end

        local quantity = item:GetData("quantity", 1)
        local canAdd = ix.currency.MAX_STACK - quantity

        if canAdd > 0 and item.uniqueID == ix.currency.CASH_ITEM then
            local dollarsToAdd = math.min(canAdd, math.floor(remaining / ix.currency.CENTS_PER_DOLLAR))
            if dollarsToAdd > 0 then
                item:SetData("quantity", quantity + dollarsToAdd)
                remaining = remaining - (dollarsToAdd * ix.currency.CENTS_PER_DOLLAR)
            end
        end
    end

    -- Calculate new stacks needed
    local dollarsNeeded = math.floor(remaining / ix.currency.CENTS_PER_DOLLAR)
    local centsNeeded = remaining % ix.currency.CENTS_PER_DOLLAR

    local cashStacksNeeded = math.ceil(dollarsNeeded / ix.currency.MAX_STACK)
    local coinStacksNeeded = centsNeeded > 0 and 1 or 0

    local totalSlotsNeeded = cashStacksNeeded + coinStacksNeeded
    local emptySlots = ix.currency.FindEmptySlots(inventory, totalSlotsNeeded)

    -- Check if we have enough space
    if #emptySlots < totalSlotsNeeded then
        return false  -- Not enough inventory space
    end

    local slotIndex = 1

    -- Create new cash stacks
    while dollarsNeeded > 0 and slotIndex <= #emptySlots do
        local stackSize = math.min(ix.currency.MAX_STACK, dollarsNeeded)
        local slot = emptySlots[slotIndex]

        inventory:Add(ix.currency.CASH_ITEM, 1, {
            quantity = stackSize
        }, slot.x, slot.y)

        dollarsNeeded = dollarsNeeded - stackSize
        slotIndex = slotIndex + 1
    end

    -- Create new coins stack if needed
    if centsNeeded > 0 and slotIndex <= #emptySlots then
        local slot = emptySlots[slotIndex]

        inventory:Add(ix.currency.COINS_ITEM, 1, {
            quantity = centsNeeded
        }, slot.x, slot.y)
    end

    return true
end

--- Remove currency from inventory
-- @realm server
-- @param inventory The inventory to remove from
-- @param cents Amount in cents to remove
-- @treturn boolean True on success, false if not enough money
function ix.currency.RemoveFromInventory(inventory, cents)
    if not inventory or cents <= 0 then return cents == 0 end

    local available = ix.currency.CountInInventory(inventory)
    if available < cents then
        return false  -- Not enough money
    end

    local remaining = cents
    local items = ix.currency.FindCurrencyItems(inventory)

    -- Remove from coins first (smaller denomination)
    for _, item in ipairs(items) do
        if remaining <= 0 then break end
        if item.uniqueID == ix.currency.COINS_ITEM then
            local quantity = item:GetData("quantity", 1)
            local value = quantity  -- 1 cent per coin

            if value <= remaining then
                -- Remove entire stack
                item:Remove()
                remaining = remaining - value
            else
                -- Partial removal
                item:SetData("quantity", quantity - remaining)
                remaining = 0
            end
        end
    end

    -- Remove from cash
    for _, item in ipairs(items) do
        if remaining <= 0 then break end
        if item.uniqueID == ix.currency.CASH_ITEM then
            local quantity = item:GetData("quantity", 1)
            local value = quantity * ix.currency.CENTS_PER_DOLLAR

            if value <= remaining then
                -- Remove entire stack
                item:Remove()
                remaining = remaining - value
            else
                -- Partial removal - need to calculate how many bills
                local centsToRemove = remaining
                local billsToRemove = math.ceil(centsToRemove / ix.currency.CENTS_PER_DOLLAR)
                local actualCentsRemoved = billsToRemove * ix.currency.CENTS_PER_DOLLAR
                local change = actualCentsRemoved - centsToRemove

                item:SetData("quantity", quantity - billsToRemove)

                -- If we removed more than needed, we need to give change as coins
                if change > 0 then
                    ix.currency.AddToInventory(inventory, change)
                end

                remaining = 0
            end
        end
    end

    return remaining == 0
end

-- ============================================================================
-- PICKUP HANDLER
-- ============================================================================

if SERVER then
    --- Called when player picks up ix_money entity
    -- @realm server
    -- @param client The player picking up money
    -- @param moneyEntity The money entity being picked up
    -- @treturn boolean True if pickup succeeded
    function ix.currency.HandlePickup(client, moneyEntity)
        local amount = moneyEntity:GetAmount()
        local character = client:GetCharacter()

        if not character then return false end

        local inventory = character:GetInventory()
        if not inventory then return false end

        -- Convert dollars to cents
        local cents = amount * ix.currency.CENTS_PER_DOLLAR

        if ix.currency.AddToInventory(inventory, cents) then
            return true
        else
            client:NotifyLocalized("inventoryFull")
            return false
        end
    end
end

-- Hook for backwards compatibility
function GM:OnPickupMoney(client, moneyEntity)
    if (IsValid(moneyEntity)) then
        -- This is now handled by ix.currency.HandlePickup in the entity Use function
        -- Kept for backwards compatibility if called directly
        local amount = moneyEntity:GetAmount()
        local cents = amount * ix.currency.CENTS_PER_DOLLAR
        client:GetCharacter():GiveMoney(cents)
    end
end

-- ============================================================================
-- CHARACTER MONEY METHODS (REWRITTEN FOR PHYSICAL CURRENCY)
-- ============================================================================

do
    local character = ix.meta.character

    --- Checks if character has at least the specified amount
    -- @realm shared
    -- @number amount Amount in CENTS to check for
    -- @treturn boolean True if character has enough
    function character:HasMoney(amount)
        if (amount < 0) then
            print("Negative Money Check Received.")
        end

        local inventory = self:GetInventory()
        return ix.currency.CountInInventory(inventory) >= amount
    end

    --- Returns the character's total money
    -- @realm shared
    -- @treturn number Total money in CENTS
    function character:GetMoney()
        local inventory = self:GetInventory()
        return ix.currency.CountInInventory(inventory)
    end

    if SERVER then
        --- Gives money to the character by adding currency items
        -- @realm server
        -- @number amount Amount in CENTS to give
        -- @bool[opt=false] bNoLog Skip logging
        -- @treturn boolean True on success, false if inventory full
        function character:GiveMoney(amount, bNoLog)
            if amount <= 0 then return true end

            local inventory = self:GetInventory()
            if not inventory then return false end

            local success = ix.currency.AddToInventory(inventory, amount)

            if success and not bNoLog then
                ix.log.Add(self:GetPlayer(), "money", amount)
            end

            return success
        end

        --- Takes money from the character by removing currency items
        -- @realm server
        -- @number amount Amount in CENTS to take
        -- @bool[opt=false] bNoLog Skip logging
        -- @treturn boolean True on success, false if not enough money
        function character:TakeMoney(amount, bNoLog)
            if amount <= 0 then return true end

            local inventory = self:GetInventory()
            if not inventory then return false end

            local success = ix.currency.RemoveFromInventory(inventory, amount)

            if success and not bNoLog then
                ix.log.Add(self:GetPlayer(), "money", -amount)
            end

            return success
        end

        --- Sets character's money to exact amount (clears existing, adds new)
        -- @realm server
        -- @number amount Amount in CENTS to set
        -- @treturn boolean True on success
        function character:SetMoney(amount)
            local inventory = self:GetInventory()
            if not inventory then return false end

            -- Remove all existing currency
            for _, item in pairs(inventory:GetItems()) do
                if item.isCurrency then
                    item:Remove()
                end
            end

            -- Add new amount
            if amount > 0 then
                return ix.currency.AddToInventory(inventory, amount)
            end

            return true
        end
    end
end

-- ============================================================================
-- CURRENCY SPLIT NETWORKING
-- ============================================================================

if SERVER then
    util.AddNetworkString("ixCurrencySplit")
    util.AddNetworkString("ixCurrencySplitConfirm")

    net.Receive("ixCurrencySplitConfirm", function(len, client)
        local itemID = net.ReadUInt(32)
        local splitAmount = net.ReadUInt(16)

        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        local item = ix.item.instances[itemID]
        if not item then
            client:Notify("Item not found.")
            return
        end

        -- Verify item belongs to this player's inventory
        if item.invID != inventory:GetID() then
            client:Notify("You don't own this item.")
            return
        end

        -- Verify item is currency
        if not item.isCurrency then
            client:Notify("This item cannot be split.")
            return
        end

        local currentQuantity = item:GetData("quantity", 1)
        if splitAmount < 1 or splitAmount >= currentQuantity then
            client:Notify("Invalid split amount.")
            return
        end

        -- Find an empty slot for the new stack
        local emptySlots = ix.currency.FindEmptySlots(inventory, 1)
        if #emptySlots < 1 then
            client:Notify("Not enough inventory space.")
            return
        end

        local slot = emptySlots[1]

        -- Reduce original stack
        item:SetData("quantity", currentQuantity - splitAmount)

        -- Create new stack directly (don't use AddToInventory which consolidates)
        local bSuccess = inventory:Add(item.uniqueID, 1, {
            quantity = splitAmount
        }, slot.x, slot.y)

        if not bSuccess then
            -- Rollback
            item:SetData("quantity", currentQuantity)
            client:Notify("Failed to create new stack.")
            return
        end

        client:Notify("Split " .. splitAmount .. " from stack.")
    end)
end

if CLIENT then
    net.Receive("ixCurrencySplit", function()
        local itemID = net.ReadUInt(32)
        local quantity = net.ReadUInt(16)
        local currencyType = net.ReadString()

        local unitLabel = currencyType == "cash" and "bills" or "coins"

        Derma_StringRequest(
            "Split Stack",
            "Enter amount to split (1-" .. (quantity - 1) .. " " .. unitLabel .. "):",
            tostring(math.floor(quantity / 2)),
            function(text)
                local splitAmount = tonumber(text)
                if not splitAmount then
                    LocalPlayer():Notify("Invalid number.")
                    return
                end

                splitAmount = math.floor(splitAmount)
                if splitAmount < 1 or splitAmount >= quantity then
                    LocalPlayer():Notify("Amount must be between 1 and " .. (quantity - 1) .. ".")
                    return
                end

                net.Start("ixCurrencySplitConfirm")
                    net.WriteUInt(itemID, 32)
                    net.WriteUInt(splitAmount, 16)
                net.SendToServer()
            end,
            nil,
            "Split",
            "Cancel"
        )
    end)

    net.Receive("ixCurrencyMergeSelect", function()
        local sourceItemID = net.ReadUInt(32)
        local stackCount = net.ReadUInt(8)

        local stacks = {}
        for i = 1, stackCount do
            stacks[i] = {
                id = net.ReadUInt(32),
                quantity = net.ReadUInt(16)
            }
        end

        local currencyType = net.ReadString()
        local unitLabel = currencyType == "cash" and "$" or "¢"

        -- Build menu options
        local options = {}
        for _, stack in ipairs(stacks) do
            local label = unitLabel .. stack.quantity
            options[label] = stack.id
        end

        -- Create selection menu
        local menu = DermaMenu()
        menu:SetSkin("helix")

        for label, stackID in SortedPairs(options) do
            menu:AddOption(label, function()
                net.Start("ixCurrencyMergeSelectConfirm")
                    net.WriteUInt(sourceItemID, 32)
                    net.WriteUInt(stackID, 32)
                net.SendToServer()
            end)
        end

        menu:AddSpacer()
        menu:AddOption("Cancel", function() end)
        menu:Open()
    end)
end

-- ============================================================================
-- CURRENCY MERGE NETWORKING
-- ============================================================================

if SERVER then
    util.AddNetworkString("ixCurrencyMergeAll")
    util.AddNetworkString("ixCurrencyMergeSelect")
    util.AddNetworkString("ixCurrencyMergeSelectConfirm")

    -- Merge all same-type currency stacks into this one
    net.Receive("ixCurrencyMergeAll", function(len, client)
        local itemID = net.ReadUInt(32)

        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        local item = ix.item.instances[itemID]
        if not item then
            client:Notify("Item not found.")
            return
        end

        if item.invID != inventory:GetID() then
            client:Notify("You don't own this item.")
            return
        end

        if not item.isCurrency then
            client:Notify("This item cannot be merged.")
            return
        end

        local currentQuantity = item:GetData("quantity", 1)
        local maxStack = ix.currency.MAX_STACK
        local canAdd = maxStack - currentQuantity

        if canAdd <= 0 then
            client:Notify("This stack is already full.")
            return
        end

        -- Find other stacks of the same currency type
        local mergedTotal = 0
        local itemsToRemove = {}

        for _, otherItem in pairs(inventory:GetItems()) do
            if otherItem.uniqueID == item.uniqueID and otherItem:GetID() != item:GetID() then
                local otherQuantity = otherItem:GetData("quantity", 1)

                if canAdd >= otherQuantity then
                    -- Merge entire stack
                    mergedTotal = mergedTotal + otherQuantity
                    canAdd = canAdd - otherQuantity
                    table.insert(itemsToRemove, otherItem)
                elseif canAdd > 0 then
                    -- Partial merge
                    mergedTotal = mergedTotal + canAdd
                    otherItem:SetData("quantity", otherQuantity - canAdd)
                    canAdd = 0
                    break
                end

                if canAdd <= 0 then break end
            end
        end

        if mergedTotal == 0 then
            client:Notify("No stacks to merge.")
            return
        end

        -- Update main stack
        item:SetData("quantity", currentQuantity + mergedTotal)

        -- Remove empty stacks
        for _, otherItem in ipairs(itemsToRemove) do
            otherItem:Remove()
        end

        client:Notify("Merged " .. mergedTotal .. " into stack.")
    end)

    -- Handle merge select request (send list to client)
    --- Called from item function to initiate merge select
    function ix.currency.SendMergeSelectList(client, item)
        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        -- Find other stacks of the same currency type
        local stacks = {}
        for _, otherItem in pairs(inventory:GetItems()) do
            if otherItem.uniqueID == item.uniqueID and otherItem:GetID() != item:GetID() then
                table.insert(stacks, {
                    id = otherItem:GetID(),
                    quantity = otherItem:GetData("quantity", 1)
                })
            end
        end

        if #stacks == 0 then
            client:Notify("No other stacks to merge with.")
            return
        end

        -- Sort by quantity descending
        table.sort(stacks, function(a, b) return a.quantity > b.quantity end)

        local currencyType = item.uniqueID == ix.currency.CASH_ITEM and "cash" or "coins"

        net.Start("ixCurrencyMergeSelect")
            net.WriteUInt(item:GetID(), 32)
            net.WriteUInt(#stacks, 8)
            for _, stack in ipairs(stacks) do
                net.WriteUInt(stack.id, 32)
                net.WriteUInt(stack.quantity, 16)
            end
            net.WriteString(currencyType)
        net.Send(client)
    end

    -- Handle merge select confirmation
    net.Receive("ixCurrencyMergeSelectConfirm", function(len, client)
        local sourceItemID = net.ReadUInt(32)
        local targetItemID = net.ReadUInt(32)

        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        local sourceItem = ix.item.instances[sourceItemID]
        local targetItem = ix.item.instances[targetItemID]

        if not sourceItem or not targetItem then
            client:Notify("Item not found.")
            return
        end

        if sourceItem.invID != inventory:GetID() or targetItem.invID != inventory:GetID() then
            client:Notify("You don't own these items.")
            return
        end

        if sourceItem.uniqueID != targetItem.uniqueID then
            client:Notify("Cannot merge different currency types.")
            return
        end

        local sourceQuantity = sourceItem:GetData("quantity", 1)
        local targetQuantity = targetItem:GetData("quantity", 1)
        local maxStack = ix.currency.MAX_STACK

        local canAdd = maxStack - sourceQuantity
        if canAdd <= 0 then
            client:Notify("Source stack is already full.")
            return
        end

        local toMerge = math.min(canAdd, targetQuantity)

        -- Update source stack
        sourceItem:SetData("quantity", sourceQuantity + toMerge)

        -- Update or remove target stack
        if toMerge >= targetQuantity then
            targetItem:Remove()
        else
            targetItem:SetData("quantity", targetQuantity - toMerge)
        end

        client:Notify("Merged " .. toMerge .. " into stack.")
    end)
end
