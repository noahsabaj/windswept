--[[
    Wallet-aware currency routing (framework plugin).

    ws.currency.AddToInventoryWithWallet() routes incoming money to a player's wallet
    inventories before falling back to the main inventory, preserving the all-or-nothing
    deposit (no partial-success mint). Generic engine: the schema registers its wallet
    item + denominations through the seams (ws.wallet.itemID / cashID / coinID). Off by
    default (walletEnabled) -- when off, money goes straight to the main inventory.

    Moved from the Colony schema in the convergence program; logic byte-identical.
]]--

ws.wallet = ws.wallet or {}

-- Find all wallets in a player's main inventory
function ws.wallet.GetWallets(client)
    local character, inventory = ws.access.GetCharacterInventory(client)
    if not character or not inventory then return {} end

    local wallets = {}
    for _, item in pairs(inventory:GetItems()) do
        if item.uniqueID == ws.wallet.itemID then
            local invID = item:GetData("id")
            if invID then
                local walletInv = ws.item.inventories[invID]
                if walletInv then
                    table.insert(wallets, {
                        item = item,
                        inventory = walletInv,
                        designation = item:GetData("designation", "both")
                    })
                end
            end
        end
    end

    return wallets
end

-- Calculate total money in a wallet inventory
function ws.wallet.GetWalletMoney(walletInv)
    local total = 0
    for _, item in pairs(walletInv:GetItems()) do
        if item.isCurrency then
            local qty = item:GetData("quantity", 1)
            total = total + (qty * item.currencyValue)
        end
    end
    return total
end

-- Find best wallet for a currency type
-- Returns wallet inventory or nil
-- Priority: specialized wallet -> general (both) wallet
function ws.wallet.FindBestWallet(client, currencyType)
    local wallets = ws.wallet.GetWallets(client)
    if #wallets == 0 then return nil end

    -- Cache item definition lookup (avoid repeated table access)
    local itemClass = currencyType == ws.wallet.cashID and ws.wallet.cashID or ws.wallet.coinID
    local itemDef = ws.item.list[itemClass]
    if not itemDef then return nil end

    local itemWidth = itemDef.width or 1
    local itemHeight = itemDef.height or 1

    -- First pass: find specialized and general wallets with pre-calculated money
    local specialized = {}
    local general = {}

    for _, wallet in ipairs(wallets) do
        -- Cache money amount during categorization (avoids recalculating during sort)
        wallet.cachedMoney = ws.wallet.GetWalletMoney(wallet.inventory)

        if wallet.designation == currencyType then
            specialized[#specialized + 1] = wallet
        elseif wallet.designation == "both" then
            general[#general + 1] = wallet
        end
    end

    -- Sort by cached money amount (descending - most money first)
    -- Only sort if more than 1 wallet in category
    local function sortByMoney(a, b)
        return a.cachedMoney > b.cachedMoney
    end

    if #specialized > 1 then
        table.sort(specialized, sortByMoney)
    end
    if #general > 1 then
        table.sort(general, sortByMoney)
    end

    -- Try specialized first (coins-only for coins, cash-only for cash)
    for i = 1, #specialized do
        local x, y = specialized[i].inventory:FindEmptySlot(itemWidth, itemHeight)
        if x and y then
            return specialized[i].inventory
        end
    end

    -- Then try general (both) wallets
    for i = 1, #general do
        local x, y = general[i].inventory:FindEmptySlot(itemWidth, itemHeight)
        if x and y then
            return general[i].inventory
        end
    end

    return nil
end

-- Add money to inventory with wallet routing
-- This is the main function to use instead of ws.currency.AddToInventory
-- Routes to wallets first, then falls back to main inventory
function ws.currency.AddToInventoryWithWallet(client, cents)
    if cents <= 0 then return cents == 0 end

    local character, mainInv = ws.access.GetCharacterInventory(client)
    if not character or not mainInv then return false end

    -- Wallet routing disabled (or no wallet item registered): straight to main inventory. (layer-wallet)
    if not ws.config.Get("walletEnabled") or not ws.wallet.itemID then
        return ws.currency.AddToInventory(mainInv, cents)
    end

    -- Split into dollars and coins
    local dollars = math.floor(cents / 100)
    local coins = cents % 100

    -- Track applied portions so the whole operation is all-or-nothing. Without
    -- this, a partial success (dollars placed, coins overflow) would return
    -- false AFTER depositing the dollars, and the caller's refund would mint
    -- money. On any failure we roll back everything already added.
    local applied = {}

    local function place(amount, currencyType)
        if amount <= 0 then return true end

        local wallet = ws.wallet.FindBestWallet(client, currencyType)
        if wallet and ws.currency.AddToInventory(wallet, amount) then
            applied[#applied + 1] = {inv = wallet, amount = amount}
            return true
        end

        if ws.currency.AddToInventory(mainInv, amount) then
            applied[#applied + 1] = {inv = mainInv, amount = amount}
            return true
        end

        return false
    end

    if not place(dollars * 100, ws.wallet.cashID) or not place(coins, ws.wallet.coinID) then
        -- Roll back any portion already deposited (we just added these exact
        -- amounts, so RemoveFromInventory is guaranteed to succeed)
        for _, a in ipairs(applied) do
            ws.currency.RemoveFromInventory(a.inv, a.amount)
        end
        return false
    end

    return true
end
