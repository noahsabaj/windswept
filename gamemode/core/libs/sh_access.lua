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
        if inv.owner and inv.owner == character:GetID() then return item end
        return nil
    end
end
