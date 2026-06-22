--[[
    Wallet — wallet-aware currency routing (framework plugin)

    An optional convenience over the core physical-money system: when a player receives
    money, route it into their wallet inventories (by cash/coin designation, most-full
    first) before the main inventory, with an all-or-nothing deposit that cannot mint on
    partial failure. The currency kernel itself stays in framework core; this only adds
    the routing.

    Generic engine: the schema provides the wallet item + denominations and wires them in
    via the seams below. Off by default (walletEnabled); when off (or no wallet item is
    registered) money goes straight to the main inventory.
]]--

local PLUGIN = PLUGIN

PLUGIN.name = "Wallet"
PLUGIN.author = "Windswept"
PLUGIN.description = "Wallet-aware currency routing: money flows into wallet items before the main inventory."

ws.wallet = ws.wallet or {}

ws.config.Add("walletEnabled", false, "Routes received money into wallet items before the main inventory.")

-- Content seams (a schema sets itemID to its wallet item; cash/coin denomination
-- uniqueIDs default to the common names but can be overridden).
ws.wallet.itemID = ws.wallet.itemID or nil
ws.wallet.cashID = ws.wallet.cashID or "cash"
ws.wallet.coinID = ws.wallet.coinID or "coins"
