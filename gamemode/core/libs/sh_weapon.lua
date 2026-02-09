--[[--
Weapon utility functions.

Available before gamemode entities load, so SWEPs can call these at file scope.
]]
-- @module ix.weapon

ix.weapon = ix.weapon or {}

if SERVER then
    --- Wrap a net.Receive handler that validates the player's active weapon class,
    -- then calls a method on it. Reduces 4-line boilerplate to 1 line per handler.
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
end
