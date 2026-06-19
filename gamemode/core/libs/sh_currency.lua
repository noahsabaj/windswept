
--- A library representing the server's currency system.
-- MODIFIED: Physical currency system - money is inventory items, not numeric values
-- @module ws.currency

ws.currency = ws.currency or {}
ws.currency.symbol = ws.currency.symbol or "$"
ws.currency.singular = ws.currency.singular or "dollar"
ws.currency.plural = ws.currency.plural or "dollars"
ws.currency.model = ws.currency.model or "models/props_lab/box01a.mdl"

-- Constants for physical currency
ws.currency.CASH_ITEM = "cash"
ws.currency.COINS_ITEM = "coins"
ws.currency.MAX_STACK = 100
ws.currency.CENTS_PER_DOLLAR = 100

--- Sets the currency type.
-- @realm shared
-- @string symbol The symbol of the currency.
-- @string singular The name of the currency in it's singular form.
-- @string plural The name of the currency in it's plural form.
-- @string model The model of the currency entity.
function ws.currency.Set(symbol, singular, plural, model)
    ws.currency.symbol = symbol
    ws.currency.singular = singular
    ws.currency.plural = plural
    ws.currency.model = model
end

--- Returns a formatted string according to the current currency.
-- MODIFIED: Now handles cents (internal precision)
-- @realm shared
-- @number amount The amount of cash in CENTS being formatted.
-- @treturn string The formatted string.
function ws.currency.Get(amount)
    -- amount is in cents, format as dollars
    local dollars = math.floor(amount / 100)
    local cents = amount % 100

    if cents == 0 then
        return ws.currency.symbol .. dollars
    else
        return string.format("%s%d.%02d", ws.currency.symbol, dollars, cents)
    end
end

--- Spawns an amount of cash at a specific location on the map.
-- NOTE: amount is in DOLLARS for backwards compatibility with existing code
-- @realm shared
-- @vector pos The position of the money to be spawned.
-- @number amount The amount of cash being spawned (in dollars).
-- @angle[opt=angle_zero] angle The angle of the entity being spawned.
-- @treturn entity The spawned money entity.
function ws.currency.Spawn(pos, amount, angle)
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
function ws.currency.CountInInventory(inventory)
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
function ws.currency.FindCurrencyItems(inventory)
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
function ws.currency.FindEmptySlots(inventory, count)
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
function ws.currency.AddToInventory(inventory, cents)
    if not inventory then return false end
    if cents <= 0 then return cents == 0 end

    local remaining = cents
    local existingItems = ws.currency.FindCurrencyItems(inventory)

    -- PHASE 1: PLAN ONLY (no mutation yet). We must verify the ENTIRE amount fits
    -- before changing anything, otherwise a partial add that returns false lets
    -- callers' refund paths create money out of nothing.
    local topups = {}  -- { {item = , newQty = }, ... }

    -- Plan top-ups into existing coin stacks first (1 cent each)
    for _, item in ipairs(existingItems) do
        if remaining <= 0 then break end

        if item.uniqueID == ws.currency.COINS_ITEM then
            local quantity = item:GetData("quantity", 1)
            local canAdd = ws.currency.MAX_STACK - quantity
            if canAdd > 0 then
                local toAdd = math.min(canAdd, remaining)
                topups[#topups + 1] = {item = item, newQty = quantity + toAdd}
                remaining = remaining - toAdd
            end
        end
    end

    -- Plan top-ups into existing cash stacks (100 cents each)
    for _, item in ipairs(existingItems) do
        if remaining < ws.currency.CENTS_PER_DOLLAR then break end

        if item.uniqueID == ws.currency.CASH_ITEM then
            local quantity = item:GetData("quantity", 1)
            local canAdd = ws.currency.MAX_STACK - quantity
            if canAdd > 0 then
                local dollarsToAdd = math.min(canAdd, math.floor(remaining / ws.currency.CENTS_PER_DOLLAR))
                if dollarsToAdd > 0 then
                    topups[#topups + 1] = {item = item, newQty = quantity + dollarsToAdd}
                    remaining = remaining - (dollarsToAdd * ws.currency.CENTS_PER_DOLLAR)
                end
            end
        end
    end

    -- New stacks needed for the leftover (top-ups don't consume empty slots, so
    -- the empty-slot count is accurate even though we haven't mutated yet)
    local dollarsNeeded = math.floor(remaining / ws.currency.CENTS_PER_DOLLAR)
    local centsNeeded = remaining % ws.currency.CENTS_PER_DOLLAR
    local cashStacksNeeded = math.ceil(dollarsNeeded / ws.currency.MAX_STACK)
    local coinStacksNeeded = centsNeeded > 0 and 1 or 0
    local totalSlotsNeeded = cashStacksNeeded + coinStacksNeeded

    local emptySlots = ws.currency.FindEmptySlots(inventory, totalSlotsNeeded)
    if #emptySlots < totalSlotsNeeded then
        return false  -- Not enough space; NOTHING has been mutated -> safe to refund
    end

    -- PHASE 2: APPLY (all checks passed, this cannot partially fail)
    for _, t in ipairs(topups) do
        t.item:SetData("quantity", t.newQty)
    end

    local slotIndex = 1

    while dollarsNeeded > 0 and slotIndex <= #emptySlots do
        local stackSize = math.min(ws.currency.MAX_STACK, dollarsNeeded)
        local slot = emptySlots[slotIndex]

        inventory:Add(ws.currency.CASH_ITEM, 1, {
            quantity = stackSize
        }, slot.x, slot.y)

        dollarsNeeded = dollarsNeeded - stackSize
        slotIndex = slotIndex + 1
    end

    if centsNeeded > 0 and slotIndex <= #emptySlots then
        local slot = emptySlots[slotIndex]

        inventory:Add(ws.currency.COINS_ITEM, 1, {
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
function ws.currency.RemoveFromInventory(inventory, cents)
    if not inventory then return false end
    if cents <= 0 then return cents == 0 end

    local available = ws.currency.CountInInventory(inventory)
    if available < cents then
        return false  -- Not enough money
    end

    local remaining = cents
    local items = ws.currency.FindCurrencyItems(inventory)

    -- Remove from coins first (smaller denomination)
    for _, item in ipairs(items) do
        if remaining <= 0 then break end
        if item.uniqueID == ws.currency.COINS_ITEM then
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
        if item.uniqueID == ws.currency.CASH_ITEM then
            local quantity = item:GetData("quantity", 1)
            local value = quantity * ws.currency.CENTS_PER_DOLLAR

            if value <= remaining then
                -- Remove entire stack
                item:Remove()
                remaining = remaining - value
            else
                -- Partial removal - need to calculate how many bills
                local centsToRemove = remaining
                local billsToRemove = math.ceil(centsToRemove / ws.currency.CENTS_PER_DOLLAR)
                local actualCentsRemoved = billsToRemove * ws.currency.CENTS_PER_DOLLAR
                local change = actualCentsRemoved - centsToRemove

                item:SetData("quantity", quantity - billsToRemove)

                -- If we removed more than needed, we need to give change as coins
                if change > 0 then
                    ws.currency.AddToInventory(inventory, change)
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
    function ws.currency.HandlePickup(client, moneyEntity)
        local amount = moneyEntity:GetAmount()
        local character = client:GetCharacter()

        if not character then return false end

        local inventory = character:GetInventory()
        if not inventory then return false end

        -- Convert dollars to cents
        local cents = amount * ws.currency.CENTS_PER_DOLLAR

        if ws.currency.AddToInventory(inventory, cents) then
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
        -- This is now handled by ws.currency.HandlePickup in the entity Use function
        -- Kept for backwards compatibility if called directly
        local character = client:GetCharacter()
        if not character then return end

        local amount = moneyEntity:GetAmount()
        local cents = amount * ws.currency.CENTS_PER_DOLLAR
        character:GiveMoney(cents)
    end
end

-- ============================================================================
-- CHARACTER MONEY METHODS (REWRITTEN FOR PHYSICAL CURRENCY)
-- ============================================================================

do
    local character = ws.meta.character

    --- Checks if character has at least the specified amount
    -- @realm shared
    -- @number amount Amount in CENTS to check for
    -- @treturn boolean True if character has enough
    function character:HasMoney(amount)
        if (amount < 0) then
            print("Negative Money Check Received.")
        end

        local inventory = self:GetInventory()
        return ws.currency.CountInInventory(inventory) >= amount
    end

    --- Returns the character's total money
    -- @realm shared
    -- @treturn number Total money in CENTS
    function character:GetMoney()
        local inventory = self:GetInventory()
        return ws.currency.CountInInventory(inventory)
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

            local success = ws.currency.AddToInventory(inventory, amount)

            if success and not bNoLog then
                ws.log.Add(self:GetPlayer(), "money", amount)
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

            local success = ws.currency.RemoveFromInventory(inventory, amount)

            if success and not bNoLog then
                ws.log.Add(self:GetPlayer(), "money", -amount)
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

            -- Snapshot the current balance so we can restore it if the new amount
            -- doesn't fit (otherwise we'd wipe their money and add nothing back).
            local original = ws.currency.CountInInventory(inventory)

            -- Remove all existing currency
            for _, item in pairs(inventory:GetItems()) do
                if item.isCurrency then
                    item:Remove()
                end
            end

            if amount <= 0 then return true end

            if ws.currency.AddToInventory(inventory, amount) then
                return true
            end

            -- New amount didn't fit; restore the original balance so money isn't
            -- silently destroyed, and report failure.
            if original > 0 then
                ws.currency.AddToInventory(inventory, original)
            end

            return false
        end
    end
end

-- ============================================================================
-- CURRENCY SPLIT NETWORKING
-- ============================================================================

if SERVER then
    util.AddNetworkString("wsCurrencySplit")
    util.AddNetworkString("wsCurrencySplitConfirm")

    net.Receive("wsCurrencySplitConfirm", function(len, client)
        local itemID = net.ReadUInt(32)
        local splitAmount = net.ReadUInt(16)

        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        local item = ws.item.instances[itemID]
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
        local emptySlots = ws.currency.FindEmptySlots(inventory, 1)
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
    net.Receive("wsCurrencySplit", function()
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

                net.Start("wsCurrencySplitConfirm")
                    net.WriteUInt(itemID, 32)
                    net.WriteUInt(splitAmount, 16)
                net.SendToServer()
            end,
            nil,
            "Split",
            "Cancel"
        )
    end)

    net.Receive("wsCurrencyMergeSelect", function()
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
                net.Start("wsCurrencyMergeSelectConfirm")
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
    util.AddNetworkString("wsCurrencyMergeAll")
    util.AddNetworkString("wsCurrencyMergeSelect")
    util.AddNetworkString("wsCurrencyMergeSelectConfirm")

    -- Merge all same-type currency stacks into this one
    net.Receive("wsCurrencyMergeAll", function(len, client)
        local itemID = net.ReadUInt(32)

        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        local item = ws.item.instances[itemID]
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
        local maxStack = ws.currency.MAX_STACK
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
    function ws.currency.SendMergeSelectList(client, item)
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

        local currencyType = item.uniqueID == ws.currency.CASH_ITEM and "cash" or "coins"

        net.Start("wsCurrencyMergeSelect")
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
    net.Receive("wsCurrencyMergeSelectConfirm", function(len, client)
        local sourceItemID = net.ReadUInt(32)
        local targetItemID = net.ReadUInt(32)

        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        local sourceItem = ws.item.instances[sourceItemID]
        local targetItem = ws.item.instances[targetItemID]

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
        local maxStack = ws.currency.MAX_STACK

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

-- ============================================================================
-- CURRENCY GIVE/DESTROY NETWORKING
-- ============================================================================

if SERVER then
    util.AddNetworkString("wsMoneyGive")
    util.AddNetworkString("wsMoneyDestroy")

    -- Check if a currency item belongs to the player (main inventory or owned bag)
    local function IsOwnedCurrencyItem(item, character, inventory)
        local itemInvID = item.invID
        if itemInvID == inventory:GetID() then return true end

        local itemInv = ws.item.inventories[itemInvID]
        return itemInv and itemInv:GetOwner() == character:GetID()
    end

    net.Receive("wsMoneyGive", function(len, client)
        local itemID = net.ReadUInt(32)
        local amount = net.ReadUInt(32)
        local target = net.ReadEntity()

        -- Validate item
        local item = ws.item.instances[itemID]
        if not item or not item.isCurrency then return end

        -- Validate giver
        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        -- Check item ownership
        if not IsOwnedCurrencyItem(item, character, inventory) then return end

        -- Validate target
        if not IsValid(target) or not target:IsPlayer() then return end
        if not target:Alive() then return end
        if client:GetPos():DistToSqr(target:GetPos()) > 10000 then return end

        local targetChar = target:GetCharacter()
        if not targetChar then return end

        -- Validate amount
        local currentQty = item:GetData("quantity", 1)
        amount = math.min(amount, currentQty)
        if amount <= 0 then return end

        -- Calculate cents to give
        local centsToGive = amount * item.currencyValue

        -- Try to add to target's inventory
        local targetInv = targetChar:GetInventory()
        if not targetInv then
            client:Notify("Target has no inventory.")
            return
        end

        local success = ws.currency.AddToInventory(targetInv, centsToGive)
        if not success then
            client:Notify("Target's inventory is full.")
            return
        end

        -- Remove from giver
        if amount >= currentQty then
            item:Remove()
        else
            item:SetData("quantity", currentQty - amount)
        end

        -- Notify both parties
        local moneyStr = item:FormatAmount(amount)
        client:Notify("Gave " .. moneyStr .. " to " .. target:Nick() .. ".")
        target:Notify("Received " .. moneyStr .. " from " .. client:Nick() .. ".")
    end)

    net.Receive("wsMoneyDestroy", function(len, client)
        local itemID = net.ReadUInt(32)
        local amount = net.ReadUInt(32)

        local item = ws.item.instances[itemID]
        if not item or not item.isCurrency then return end
        if not item.canDestroy then return end

        -- Validate ownership
        local character = client:GetCharacter()
        if not character then return end

        local inventory = character:GetInventory()
        if not inventory then return end

        if not IsOwnedCurrencyItem(item, character, inventory) then return end

        local currentQty = item:GetData("quantity", 1)
        amount = math.min(amount, currentQty)
        if amount <= 0 then return end

        if amount >= currentQty then
            item:Remove()
        else
            item:SetData("quantity", currentQty - amount)
        end

        client:Notify("Destroyed " .. item:FormatAmount(amount) .. ".")
    end)
end
