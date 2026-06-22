--[[
    ws.access — generic ownership / reachability checks (framework)

    Promoted out of schema-level constants so the framework (and ws.action) can
    enforce the trust boundary without depending on any schema. These are the
    canonical checks; schemas should use ws.access.* rather than rolling their own.
]]--

ws.access = ws.access or {}

-- Interaction ranges (squared, for DistToSqr).
ws.access.RANGE_INTERACTION = 100 * 100        -- standard player<->player / player<->entity
ws.access.RANGE_INTERACTION_CLOSE = 96 * 96     -- close-quarters (restrain, etc.)

--- Get a player's character and main inventory, or nil, nil.
function ws.access.GetCharacterInventory(client)
    if not IsValid(client) then return nil, nil end
    local character = client:GetCharacter()
    if not character then return nil, nil end
    return character, character:GetInventory()
end

--- Are two entities within a squared range of each other?
function ws.access.WithinRange(a, b, rangeSquared)
    if not IsValid(a) or not IsValid(b) then return false end
    return a:GetPos():DistToSqr(b:GetPos()) <= (rangeSquared or ws.access.RANGE_INTERACTION)
end

function ws.access.CanInteract(client, target)
    return ws.access.WithinRange(client, target, ws.access.RANGE_INTERACTION)
end

function ws.access.CanInteractClose(client, target)
    return ws.access.WithinRange(client, target, ws.access.RANGE_INTERACTION_CLOSE)
end

--- Enforce single-character item ownership. Returns whether `client` may interact with
--- `item` under the multi-character rule, optionally claiming an unowned item for the
--- caller's character (first-pickup assignment). Consolidates the checks that were
--- duplicated across Transfer / PerformInventoryAction / inventory Add. (fw-character-item-10)
--- @return bool ok, string|nil reason ("itemOwned" when denied)
function ws.access.EnsureItemOwnership(client, item, bAssign)
    if not item or item.bAllowMultiCharacterInteraction then return true end
    if not IsValid(client) then return true end

    local character = client:GetCharacter()
    if not character then return true end

    local itemPlayerID = item:GetPlayerID()
    local itemCharacterID = item:GetCharacterID()

    if itemPlayerID and itemCharacterID then
        if itemPlayerID == client:SteamID64() and itemCharacterID ~= character:GetID() then
            return false, "itemOwned"
        end
    elseif bAssign and SERVER then
        -- Unowned item: claim it for this character (persisted, like the old Transfer path).
        item.characterID = character:GetID()
        item.playerID = client:SteamID64()

        local query = mysql:Update("ws_items")
            query:Update("character_id", character:GetID())
            query:Update("player_id", client:SteamID64())
            query:Where("item_id", item:GetID())
        query:Execute()
    end

    return true
end

if SERVER then
    --- Verify a client owns an item in their MAIN inventory.
    -- @return item or nil
    function ws.access.VerifyItemOwnership(client, itemID, expectedUniqueID)
        local item = ws.item.instances[itemID]
        if not item then return nil end
        if expectedUniqueID and item.uniqueID ~= expectedUniqueID then return nil end

        local character, inventory = ws.access.GetCharacterInventory(client)
        if not character or not inventory then return nil end

        for _, invItem in pairs(inventory:GetItems()) do
            if invItem:GetID() == itemID then return item end
        end
        return nil
    end

    --- Verify a client can ACCESS an item: in their main inventory OR in a bag /
    -- container inventory they own (one level deep; bags don't nest). Use this for
    -- items that legitimately live inside owned containers.
    -- @return item or nil
    function ws.access.VerifyItemAccessible(client, itemID, expectedUniqueID)
        local item = ws.item.instances[itemID]
        if not item then return nil end
        if expectedUniqueID and item.uniqueID ~= expectedUniqueID then return nil end

        local character = client:GetCharacter()
        if not character then return nil end

        local mainInv = character:GetInventory()
        local inv = ws.item.inventories[item.invID]
        if not inv or not mainInv then return nil end

        if inv:GetID() == mainInv:GetID() then return item end

        -- A stale inv.owner could widen access on edge transfer paths, so anchor
        -- accessibility to a container the caller can actually reach: the bag item
        -- whose inventory this is must currently live in the caller's MAIN inventory.
        -- inv.owner is still required (single source of truth), but the bag-item
        -- lookup makes a possibly-stale owner field insufficient on its own. (fw-core-security-8)
        if inv.owner and inv.owner == character:GetID() then
            local invID = inv:GetID()

            for _, bagItem in pairs(mainInv:GetItems()) do
                if (bagItem.base == "base_bags" or bagItem.isBag) and bagItem.data and bagItem.data.id == invID then
                    return item
                end
            end
        end

        return nil
    end
end
