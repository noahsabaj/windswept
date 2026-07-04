--- Server pickup handler, character money methods, and the split / merge /
-- give-destroy currency networking.
--
-- Split out of core/libs/sh_currency.lua for readability (PR-12); pure relocation,
-- the public ws.currency.* API is unchanged. The currency kernel stays in core.
-- @module ws.currency

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

            -- Notify both parties (no names -- fog of war; it's a face-to-face hand-off)
            local moneyStr = item:FormatAmount(amount)
            client:Notify("Gave " .. moneyStr .. ".")
            target:Notify("Received " .. moneyStr .. ".")
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
