
--- A library representing the server's currency system.
-- MODIFIED: Physical currency system - money is inventory items, not numeric values
-- @module ws.currency

ws.currency = ws.currency or {}
ws.currency.symbol = ws.currency.symbol or "$"
ws.currency.singular = ws.currency.singular or "dollar"
ws.currency.plural = ws.currency.plural or "dollars"
ws.currency.model = ws.currency.model or "models/props_lab/box01a.mdl"

-- Denomination registry. Schemas register their currency items via RegisterDenomination
-- (see windswept-colony/schema/sh_configs.lua); the framework's add/remove logic reads this
-- registry instead of hardcoding any schema-specific item IDs. (layer-2)
ws.currency.denominations = ws.currency.denominations or {}  -- uniqueID -> {uniqueID, value, maxStack}
ws.currency.denomOrder = ws.currency.denomOrder or {}        -- array, sorted DESC by value

-- Back-compat conveniences, kept in sync by RegisterDenomination for code that still reads
-- them: CASH_ITEM = largest (primary) denomination, COINS_ITEM = smallest (base) denomination,
-- CENTS_PER_DOLLAR = primary value, MAX_STACK = primary stack cap. Generic dollars/cents
-- defaults until a schema registers.
ws.currency.MAX_STACK = ws.currency.MAX_STACK or 100
ws.currency.CENTS_PER_DOLLAR = ws.currency.CENTS_PER_DOLLAR or 100
ws.currency.CASH_ITEM = ws.currency.CASH_ITEM
ws.currency.COINS_ITEM = ws.currency.COINS_ITEM

--- Registers a currency denomination (its item uniqueID and value in base units/cents).
-- @realm shared
-- @string uniqueID The currency item's uniqueID (e.g. "cash").
-- @number value The denomination's value in base units (cents).
-- @number[opt=100] maxStack Max quantity per stack.
function ws.currency.RegisterDenomination(uniqueID, value, maxStack)
    ws.currency.denominations[uniqueID] = {
        uniqueID = uniqueID,
        value = value,
        maxStack = maxStack or 100,
    }

    -- Rebuild the descending-by-value order.
    ws.currency.denomOrder = {}
    for _, d in pairs(ws.currency.denominations) do
        ws.currency.denomOrder[#ws.currency.denomOrder + 1] = d
    end
    table.sort(ws.currency.denomOrder, function(a, b) return a.value > b.value end)

    -- Keep the back-compat conveniences in sync (primary = largest, base = smallest).
    local primary = ws.currency.denomOrder[1]
    local base = ws.currency.denomOrder[#ws.currency.denomOrder]

    if primary then
        ws.currency.CASH_ITEM = primary.uniqueID
        ws.currency.CENTS_PER_DOLLAR = primary.value
        ws.currency.MAX_STACK = primary.maxStack
    end

    if base then
        ws.currency.COINS_ITEM = base.uniqueID
    end
end

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
    -- amount is in cents, format as dollars. Handle the sign explicitly: Lua's floor +
    -- modulo mis-format negatives (e.g. -150 -> -2.50), so format the magnitude and
    -- prefix '-' before the symbol. (fw-currency-economy-10)
    local neg = amount < 0
    amount = math.abs(amount)

    local dollars = math.floor(amount / 100)
    local cents = amount % 100
    local sign = neg and "-" or ""

    if cents == 0 then
        return sign .. ws.currency.symbol .. dollars
    else
        return string.format("%s%s%d.%02d", sign, ws.currency.symbol, dollars, cents)
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
        print("[Windswept] Can't create currency entity: Invalid Amount of money")
        return
    end

    local money = ents.Create("ws_money")
    money:Spawn()

    if (IsValid(pos) and pos:IsPlayer()) then
        pos = pos:GetItemDropPos(money)
    elseif (!isvector(pos)) then
        print("[Windswept] Can't create currency entity: Invalid Position")

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
    if (#ws.currency.denomOrder == 0) then return false end  -- no denominations registered yet

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

    -- PHASE 1: PLAN (no mutation). FindCurrencyItems returns items ascending by value, so
    -- we remove the smallest denominations first and only ever break ONE larger stack for
    -- change. Denomination-agnostic: uses item.currencyValue, not hardcoded cash/coins. (layer-2)
    local remaining = cents
    local items = ws.currency.FindCurrencyItems(inventory)
    local plan = {}        -- { {item=, remove=true} | {item=, newQty=} }
    local freedSlots = 0   -- slots freed by full-stack removals
    local changeOwed = 0

    for _, item in ipairs(items) do
        if remaining <= 0 then break end

        local denomValue = item.currencyValue or 0
        if denomValue <= 0 then continue end

        local quantity = item:GetData("quantity", 1)
        local value = quantity * denomValue

        if value <= remaining then
            plan[#plan + 1] = {item = item, remove = true}
            freedSlots = freedSlots + 1
            remaining = remaining - value
        else
            -- Break this stack: remove the minimal whole units to cover `remaining`; the
            -- overshoot is change to give back.
            local unitsToRemove = math.ceil(remaining / denomValue)
            local newQty = quantity - unitsToRemove
            changeOwed = (unitsToRemove * denomValue) - remaining
            remaining = 0

            if newQty <= 0 then
                -- Removing the whole stack (don't leave a 0-quantity ghost); frees a slot.
                plan[#plan + 1] = {item = item, remove = true}
                freedSlots = freedSlots + 1
            else
                plan[#plan + 1] = {item = item, newQty = newQty}
            end
        end
    end

    if remaining > 0 then return false end  -- safety (the CountInInventory guard makes this unreachable)

    -- Change-loss fix (fw-currency-economy-3): verify any change can be placed BEFORE
    -- mutating, so we never destroy value while reporting success. Change is smaller than the
    -- broken denomination's value; estimate the needed slots conservatively (a refused op
    -- mutates nothing, so over-estimating is safe).
    if changeOwed > 0 then
        local baseDenom = ws.currency.denomOrder[#ws.currency.denomOrder]
        local baseMax = (baseDenom and baseDenom.maxStack) or ws.currency.MAX_STACK or 100
        local changeSlotsNeeded = math.ceil(changeOwed / baseMax)
        local emptyNow = #ws.currency.FindEmptySlots(inventory, changeSlotsNeeded)

        if changeSlotsNeeded > (emptyNow + freedSlots) then
            return false  -- can't return change; fail with NOTHING removed
        end
    end

    -- PHASE 2: APPLY (all checks passed; this cannot partially fail in a value-losing way)
    for _, p in ipairs(plan) do
        if p.remove then
            p.item:Remove()
        else
            p.item:SetData("quantity", p.newQty)
        end
    end

    if changeOwed > 0 then
        ws.currency.AddToInventory(inventory, changeOwed)
    end

    return true
end

-- ============================================================================
-- PICKUP HANDLER
-- ============================================================================

if SERVER then
    --- Called when player picks up ws_money entity
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

-- Hook for backwards compatibility. Delegates to the single authoritative pickup path
-- (ws.currency.HandlePickup) so a stray call can't mint/lose money via an unchecked
-- GiveMoney (HandlePickup verifies space and notifies on failure). (fw-currency-economy-11)
function GM:OnPickupMoney(client, moneyEntity)
    if (SERVER and IsValid(moneyEntity)) then
        ws.currency.HandlePickup(client, moneyEntity)
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

-- Shared cooldown (seconds) for the currency net actions -- used as the ws.action rateLimit on
-- currency split/merge/give/destroy (replay/DoS + give-spam griefing surface). (fw-currency-economy-6)
local CURRENCY_NET_COOLDOWN = 0.25

if SERVER then
    util.AddNetworkString("wsCurrencySplit")

    -- Migrated to ws.action (was a hand-rolled net.Receive). The wire contract is unchanged:
    -- ws.action reads item (UInt32 id) then read() (UInt16 splitAmount), matching the client's
    -- writes (both the in-scope item caller and the schema cl_schema.lua caller). access="owned"
    -- preserves the original main-inventory ownership check (item.invID == main inventory). The
    -- 0.25s rateLimit replaces the shared CurrencyRateLimited window with a per-action one.
    ws.action.Register("wsCurrencySplitConfirm", {
        item = true,
        access = "owned",
        rateLimit = CURRENCY_NET_COOLDOWN,
        read = function() return net.ReadUInt(16) end,
        onValidate = function(client, ctx)
            if not ctx.item.isCurrency then
                client:Notify("This item cannot be split.")
                return false
            end

            local splitAmount = ctx.data
            local currentQuantity = ctx.item:GetData("quantity", 1)
            if splitAmount < 1 or splitAmount >= currentQuantity then
                client:Notify("Invalid split amount.")
                return false
            end
        end,
        run = function(client, ctx)
            local item = ctx.item
            local splitAmount = ctx.data
            local currentQuantity = item:GetData("quantity", 1)

            local character = client:GetCharacter()
            if not character then return end

            local inventory = character:GetInventory()
            if not inventory then return end

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
        end
    })
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

                ws.action.Send("wsCurrencySplitConfirm", itemID, nil, function()
                    net.WriteUInt(splitAmount, 16)
                end)
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
        menu:SetSkin("windswept")

        for label, stackID in SortedPairs(options) do
            menu:AddOption(label, function()
                ws.action.Send("wsCurrencyMergeSelectConfirm", sourceItemID, nil, function()
                    net.WriteUInt(stackID, 32)
                end)
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
    util.AddNetworkString("wsCurrencyMergeSelect")
    -- wsCurrencyMergeSelectConfirm is now registered via ws.action.Register below.

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

    -- Handle merge select confirmation.
    -- Migrated to ws.action (was hand-rolled). Wire contract unchanged: source itemID (UInt32),
    -- then target itemID (UInt32). The source is resolved via ws.action's item=true + the default
    -- access="accessible" (VerifyItemAccessible, so bag stacks merge). The target is read by read()
    -- and resolved/verified accessible in onValidate, preserving (fw-currency-economy-4)'s
    -- both-accessible + both-currency + same-uniqueID gates. 0.25s per-action rateLimit replaces
    -- the shared CurrencyRateLimited window.
    ws.action.Register("wsCurrencyMergeSelectConfirm", {
        item = true,
        access = "accessible",
        rateLimit = CURRENCY_NET_COOLDOWN,
        read = function() return net.ReadUInt(32) end,  -- targetItemID
        onValidate = function(client, ctx)
            local sourceItem = ctx.item

            -- Resolve via VerifyItemAccessible so bag stacks (offered by SendMergeSelectList
            -- when it iterates owned inventories) can actually be merged, and so both items
            -- are confirmed currency owned by this character. (fw-currency-economy-4)
            local targetItem = ws.access.VerifyItemAccessible(client, ctx.data)

            if not sourceItem or not targetItem then
                client:Notify("Item not found.")
                return false
            end

            if not sourceItem.isCurrency or not targetItem.isCurrency then
                client:Notify("These items cannot be merged.")
                return false
            end

            if sourceItem.uniqueID != targetItem.uniqueID then
                client:Notify("Cannot merge different currency types.")
                return false
            end

            -- Stash the resolved target for run() (avoid re-resolving).
            ctx.targetItem = targetItem
        end,
        run = function(client, ctx)
            local sourceItem = ctx.item
            local targetItem = ctx.targetItem

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
        end
    })
end

-- ============================================================================
-- CURRENCY GIVE/DESTROY NETWORKING
-- ============================================================================

if SERVER then
    -- Migrated to ws.action (was hand-rolled). IMPORTANT wire-order change: the old contract was
    -- itemID, amount, target; ws.action.Send writes itemID, target, then writeExtra(amount), so the
    -- server now reads item (UInt32), target (Entity), then read() (UInt32 amount). The client caller
    -- below was updated to the new order to stay in sync. access="accessible" matches the original
    -- IsOwnedCurrencyItem (main inventory OR owned bag). range="interaction" (RANGE_INTERACTION=100^2)
    -- exactly reproduces the original DistToSqr>10000 check. 0.25s per-action rateLimit replaces the
    -- shared CurrencyRateLimited window.
    ws.action.Register("wsMoneyGive", {
        item = true,
        access = "accessible",
        target = true,
        range = "interaction",
        rateLimit = CURRENCY_NET_COOLDOWN,
        read = function() return net.ReadUInt(32) end,  -- amount
        onValidate = function(client, ctx)
            -- Validate item
            if not ctx.item.isCurrency then return false end

            -- Validate target
            if not ctx.target:IsPlayer() then return false end
            if not ctx.target:Alive() then return false end

            -- Validate amount
            local currentQty = ctx.item:GetData("quantity", 1)
            local amount = math.min(ctx.data, currentQty)
            if amount <= 0 then return false end
        end,
        run = function(client, ctx)
            local item = ctx.item
            local target = ctx.target

            local targetChar = target:GetCharacter()
            if not targetChar then return end

            -- Validate amount
            local currentQty = item:GetData("quantity", 1)
            local amount = math.min(ctx.data, currentQty)
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
        end
    })

    -- Migrated to ws.action (was hand-rolled). Wire contract unchanged: itemID (UInt32) then
    -- amount (UInt32). access="accessible" matches the original IsOwnedCurrencyItem (main inventory
    -- OR owned bag) -- note this is intentionally NOT "owned"/main-inventory-only, which would
    -- regress destroying currency held in an owned bag. 0.25s per-action rateLimit replaces the
    -- shared CurrencyRateLimited window.
    ws.action.Register("wsMoneyDestroy", {
        item = true,
        access = "accessible",
        rateLimit = CURRENCY_NET_COOLDOWN,
        read = function() return net.ReadUInt(32) end,  -- amount
        onValidate = function(client, ctx)
            if not ctx.item.isCurrency then return false end
            if not ctx.item.canDestroy then return false end

            local currentQty = ctx.item:GetData("quantity", 1)
            local amount = math.min(ctx.data, currentQty)
            if amount <= 0 then return false end
        end,
        run = function(client, ctx)
            local item = ctx.item

            local currentQty = item:GetData("quantity", 1)
            local amount = math.min(ctx.data, currentQty)
            if amount <= 0 then return end

            if amount >= currentQty then
                item:Remove()
            else
                item:SetData("quantity", currentQty - amount)
            end

            client:Notify("Destroyed " .. item:FormatAmount(amount) .. ".")
        end
    })
end
