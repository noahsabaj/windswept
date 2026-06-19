--[[
    ws.resource — conserved-resource kernel (framework)

    A single transactional primitive for any numeric quantity stored on an item
    that MOVES and must never be duplicated: battery charge, pen ink / pencil lead,
    tool/lock durability, etc. (Currency is multi-stack and multi-inventory, so it
    keeps its own atomic implementation in ws.currency.)

    All operations are all-or-nothing: on failure they make NO change, so callers'
    refund/rollback logic can never mint resource out of nothing — the bug class
    that produced the money-dupe vectors.
]]--

ws.resource = ws.resource or {}

--- Current amount of a resource under `key` on `item`.
function ws.resource.Get(item, key, default)
    if not item then return 0 end
    return item:GetData(key, default or 0)
end

--- Consume `amount`. Returns true only if the full amount was available (and was
--- removed); false makes no change.
function ws.resource.Consume(item, key, amount, default)
    if not item or amount == nil then return false end
    if amount <= 0 then return amount == 0 end

    local current = item:GetData(key, default or 0)
    if current < amount then return false end

    item:SetData(key, current - amount)
    return true
end

--- Replenish toward `max` (max optional = uncapped). Returns the amount actually
--- added (0..amount).
function ws.resource.Replenish(item, key, amount, max, default)
    if not item or not amount or amount <= 0 then return 0 end

    local current = item:GetData(key, default or 0)
    local target = max and math.min(current + amount, max) or (current + amount)
    local added = target - current
    if added > 0 then item:SetData(key, target) end
    return added
end

--- Move `amount` from src to dst (same key). Atomic: if dst can't take the full
--- amount, the partial is rolled back onto src and the move fails.
function ws.resource.Transfer(src, dst, key, amount, max, default)
    if not ws.resource.Consume(src, key, amount, default) then return false end

    local added = ws.resource.Replenish(dst, key, amount, max, default)
    if added < amount then
        -- dst couldn't take it all; restore what was removed and fail.
        ws.resource.Replenish(src, key, amount - added, nil, default)
        if added > 0 then
            -- pull back the partial we did add to dst so nothing is duplicated
            ws.resource.Consume(dst, key, added, default)
            ws.resource.Replenish(src, key, added, nil, default)
        end
        return false
    end
    return true
end
