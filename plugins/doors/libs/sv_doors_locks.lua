--[[
    Lock state: queries (has/keyings/check), install/remove, lock/unlock,
    durability damage, and repair -- all syncing to the double-door partner.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- Check if a door has a lock installed
function ws.doors.HasLock(door)
    if not IsValid(door) then return false end
    return door.wsLockData ~= nil
end

-- Get lock keyings from a door
function ws.doors.GetLockKeyings(door)
    if not IsValid(door) or not door.wsLockData then return {} end
    return door.wsLockData.keyings or {}
end

-- Check if a keying matches the door's lock
function ws.doors.CheckKeying(door, keying)
    if not IsValid(door) or not door.wsLockData then return false end
    if not keying or keying == "" then return false end

    keying = string.upper(keying)
    for _, lockKeying in ipairs(door.wsLockData.keyings or {}) do
        if string.upper(lockKeying) == keying then
            return true
        end
    end
    return false
end

-- Install a lock on a door (syncs to partner for double doors)
function ws.doors.InstallLock(door, lockData, bIgnorePartner)
    if not IsValid(door) then return false end
    door.wsLockData = lockData

    -- Sync to partner door (double doors share the same lock)
    local partner = door:GetDoorPartner()
    if IsValid(partner) and not bIgnorePartner then
        ws.doors.InstallLock(partner, table.Copy(lockData), true)
    end

    ws.doors.Save()
    return true
end

-- Remove lock from a door (syncs to partner for double doors)
function ws.doors.RemoveLock(door, bIgnorePartner)
    if not IsValid(door) then return nil end
    local lockData = door.wsLockData
    door.wsLockData = nil
    door:Fire("unlock")

    -- Sync to partner door
    local partner = door:GetDoorPartner()
    if IsValid(partner) and not bIgnorePartner then
        ws.doors.RemoveLock(partner, true)
    end

    ws.doors.Save()
    return lockData
end

-- Lock a door (syncs to partner for double doors)
function ws.doors.LockDoor(door, bIgnorePartner)
    if not IsValid(door) then return false end
    if not door.wsLockData then return false end
    if door:IsLocked() then return true end  -- Already locked

    door:Fire("lock")

    -- Sync to partner door
    local partner = door:GetDoorPartner()
    if IsValid(partner) and not bIgnorePartner then
        ws.doors.LockDoor(partner, true)
    end

    return true
end

-- Unlock a door (syncs to partner for double doors)
function ws.doors.UnlockDoor(door, bIgnorePartner)
    if not IsValid(door) then return false end
    if not door.wsLockData then return false end
    if not door:IsLocked() then return true end  -- Already unlocked

    door:Fire("unlock")

    -- Sync to partner door
    local partner = door:GetDoorPartner()
    if IsValid(partner) and not bIgnorePartner then
        ws.doors.UnlockDoor(partner, true)
    end

    return true
end

-- Damage a door's lock (syncs to partner for double doors)
function ws.doors.DamageLock(door, amount, bIgnorePartner)
    if not IsValid(door) or not door.wsLockData then return false end

    door.wsLockData.durability = (door.wsLockData.durability or 100) - amount

    -- Sync damage to partner door
    local partner = door:GetDoorPartner()
    if IsValid(partner) and partner.wsLockData and not bIgnorePartner then
        partner.wsLockData.durability = door.wsLockData.durability
    end

    if door.wsLockData.durability <= 0 then
        -- Lock broken - permanently unlocked on both doors
        door:Fire("unlock")
        door:EmitSound("physics/metal/metal_box_break1.wav", 70)

        if IsValid(partner) and not bIgnorePartner then
            partner.wsLockData = nil
            partner:Fire("unlock")
        end

        door.wsLockData = nil
        ws.doors.Save()
        return true  -- Lock destroyed
    end

    ws.doors.Save()
    return false
end
-- Repair a lock to full durability (syncs to partner like DamageLock). (sc-doors-access-8)
function ws.doors.RepairLock(door, bIgnorePartner)
    if not IsValid(door) or not door.wsLockData then return false end
    door.wsLockData.durability = 100

    -- Sync durability to partner door (double doors share the same lock)
    local partner = door:GetDoorPartner()
    if IsValid(partner) and partner.wsLockData and not bIgnorePartner then
        partner.wsLockData.durability = 100
    end

    ws.doors.Save()
    return true
end
