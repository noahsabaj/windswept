
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


-- The inventory helpers and the networking/character-money handlers are split out for
-- readability (PR-12). They load here (during the core/libs sweep) right after the
-- registry + RegisterDenomination above, so the kernel is whole before the schema's
-- boot-time RegisterDenomination and the wallet plugin's wrapping run. Pure relocation.
ws.util.Include("currency/sh_currency_inventory.lua")  -- count/find/add/remove helpers
ws.util.Include("currency/sh_currency_net.lua")        -- pickup, character money, split/merge/give networking

