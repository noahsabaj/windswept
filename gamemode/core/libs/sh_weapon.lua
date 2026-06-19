--[[--
Weapon utility functions.

Available before gamemode entities load, so SWEPs can call these at file scope.
Both functions are shared (defined on client and server) because SWEP files
load on both realms. NetReceive calls should be wrapped in `if SERVER then`
by the caller; RegisterCleanupHooks works correctly on both realms.
]]
-- @module ws.weapon

ws.weapon = ws.weapon or {}

--- Wrap a net.Receive handler that validates the player's active weapon class,
-- then calls a method on it. Reduces 4-line boilerplate to 1 line per handler.
-- Callers must wrap in `if SERVER then` since net.Receive callbacks differ by realm.
-- @string netString The network string to listen for
-- @string weaponClass The expected SWEP class (e.g., "ix_key")
-- @string methodName The SWEP method to call (e.g., "StartLock")
function ws.weapon.NetReceive(netString, weaponClass, methodName)
    net.Receive(netString, function(len, ply)
        local weapon = ply:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= weaponClass then return end
        weapon[methodName](weapon)
    end)
end

--- Register PlayerDeath and wsPlayerKnockedOut cleanup hooks for a weapon class.
-- The cleanup function receives the valid weapon entity.
-- @string weaponClass The SWEP class to find on the dying/knocked player
-- @string hookPrefix Unique prefix for hook names (e.g., "wsFlashlight")
-- @func cleanupFn Called with the weapon entity when the player dies or is knocked out
function ws.weapon.RegisterCleanupHooks(weaponClass, hookPrefix, cleanupFn)
    local function onCleanup(client)
        local weapon = client:GetWeapon(weaponClass)
        if IsValid(weapon) then
            cleanupFn(weapon)
        end
    end

    hook.Add("PlayerDeath", hookPrefix .. "Death", onCleanup)
    hook.Add("wsPlayerKnockedOut", hookPrefix .. "Knockout", onCleanup)
end

--- Check if a SWEP's saved target is still valid (same entity, exists, in range).
-- Used in Think() loops to validate ongoing actions like locking, installing, breaking.
-- @entity owner The player performing the action
-- @entity currentTarget The entity currently being aimed at (e.g., from GetTargetDoor())
-- @entity savedTarget The entity stored when the action started (e.g., self.targetDoor)
-- @number maxDistance Maximum interaction distance (e.g., self.MaxUseDistance)
-- @number[opt=32] buffer Extra distance tolerance beyond maxDistance
-- @treturn bool Whether the target is still valid
-- @treturn string|nil Reason if invalid: "looked_away", "invalid", or "too_far"
function ws.weapon.IsTargetValid(owner, currentTarget, savedTarget, maxDistance, buffer)
    if currentTarget ~= savedTarget then return false, "looked_away" end
    if not IsValid(savedTarget) then return false, "invalid" end
    if owner:GetPos():Distance(savedTarget:GetPos()) > maxDistance + (buffer or 32) then
        return false, "too_far"
    end
    return true
end
