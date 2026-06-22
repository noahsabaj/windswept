--- Physical-currency inventory helpers: counting, finding currency items + empty
-- slots, and the all-or-nothing AddToInventory / RemoveFromInventory.
--
-- Split out of core/libs/sh_currency.lua for readability (PR-12); pure relocation,
-- the public ws.currency.* API is unchanged. The currency kernel stays in core.
-- @module ws.currency

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

