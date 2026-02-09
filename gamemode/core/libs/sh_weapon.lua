--[[--
Weapon utility functions.

Available before gamemode entities load, so SWEPs can call these at file scope.
Both functions are shared (defined on client and server) because SWEP files
load on both realms. NetReceive calls should be wrapped in `if SERVER then`
by the caller; RegisterCleanupHooks works correctly on both realms.
]]
-- @module ix.weapon

ix.weapon = ix.weapon or {}

--- Wrap a net.Receive handler that validates the player's active weapon class,
-- then calls a method on it. Reduces 4-line boilerplate to 1 line per handler.
-- Callers must wrap in `if SERVER then` since net.Receive callbacks differ by realm.
-- @string netString The network string to listen for
-- @string weaponClass The expected SWEP class (e.g., "ix_key")
-- @string methodName The SWEP method to call (e.g., "StartLock")
function ix.weapon.NetReceive(netString, weaponClass, methodName)
    net.Receive(netString, function(len, ply)
        local weapon = ply:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= weaponClass then return end
        weapon[methodName](weapon)
    end)
end

--- Register PlayerDeath and ixPlayerKnockedOut cleanup hooks for a weapon class.
-- The cleanup function receives the valid weapon entity.
-- @string weaponClass The SWEP class to find on the dying/knocked player
-- @string hookPrefix Unique prefix for hook names (e.g., "ixFlashlight")
-- @func cleanupFn Called with the weapon entity when the player dies or is knocked out
function ix.weapon.RegisterCleanupHooks(weaponClass, hookPrefix, cleanupFn)
    local function onCleanup(client)
        local weapon = client:GetWeapon(weaponClass)
        if IsValid(weapon) then
            cleanupFn(weapon)
        end
    end

    hook.Add("PlayerDeath", hookPrefix .. "Death", onCleanup)
    hook.Add("ixPlayerKnockedOut", hookPrefix .. "Knockout", onCleanup)
end
