--[[
    Skeleton configuration.

    This schema enables ZERO framework plugins, so it boots on the framework defaults --
    the proof that every plugin's default-off path is clean. The framework plugins are all
    disabled-by-default; turn the ones you want on here. Each is gated by a config flag:

        hook.Add("InitializedConfig", "myschemaPlugins", function()
            ws.config.Set("doorsEnabled", true)     -- physical doors, locks, keys
            ws.config.Set("radioEnabled", true)      -- physical radio voice (needs radio items)
            ws.config.Set("walletEnabled", true)     -- route money into wallet items first
            ws.config.Set("businessEnabled", true)   -- the business / shipment ordering menu
            ws.config.Set("vendorAllowInfinite", true)-- opt OUT of conservation (admin-shop vendors)
        end)

    Plugins that are inert until your content uses them (power batteries, documents,
    restraints, photography, permadeath) need no flag -- just add the items/SWEPs that
    build on their bases. The doors/radio/wallet engines also need their content seams set
    (e.g. ws.radio.itemID, ws.wallet.itemID); see windswept-colony for examples.
]]--

-- Factions are a CHOICE in Windswept (this is the headline difference from Helix). The
-- framework defaults to "optional" (factionless characters allowed). This skeleton turns
-- them off entirely; use "optional" or "required" instead if your schema has factions.
hook.Add("InitializedConfig", "skeletonConfig", function()
    ws.config.Set("factionMode", "disabled")
end)

-- Physical money is optional. To use it, register your currency denominations (cents):
-- ws.currency.RegisterDenomination("cash", 100, 100)  -- $1 note (100c), stacks of 100
-- ws.currency.RegisterDenomination("coins", 1, 100)   -- 1c coin, stacks of 100
