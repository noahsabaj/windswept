--[[--
Helper library for faction permission checking and delegation.

Provides a 9-permission system with rank-scoped authority for faction governance.
Rank 255 (anchor) classes always have all permissions.
Rank 0 (default) classes never have permissions.
Ranks 1-254 have configurable permissions via /grantperm and /revokeperm.
]]
-- @module ix.factionperms

ix.factionperms = ix.factionperms or {}

--- Permission constants
-- @realm shared
ix.factionperms.FACTION_INVITE = "faction_invite"
ix.factionperms.FACTION_REMOVE = "faction_remove"
ix.factionperms.FACTION_INFO = "faction_info"
ix.factionperms.CLASS_CREATE = "class_create"
ix.factionperms.CLASS_UPDATE = "class_update"
ix.factionperms.CLASS_DELETE = "class_delete"
ix.factionperms.CLASS_ASSIGN = "class_assign"
ix.factionperms.PERM_GRANT = "perm_grant"
ix.factionperms.PERM_REVOKE = "perm_revoke"

--- All permission keys as an array for iteration.
-- @realm shared
ix.factionperms.ALL = {
    ix.factionperms.FACTION_INVITE,
    ix.factionperms.FACTION_REMOVE,
    ix.factionperms.FACTION_INFO,
    ix.factionperms.CLASS_CREATE,
    ix.factionperms.CLASS_UPDATE,
    ix.factionperms.CLASS_DELETE,
    ix.factionperms.CLASS_ASSIGN,
    ix.factionperms.PERM_GRANT,
    ix.factionperms.PERM_REVOKE,
}

--- Check if a character has a specific permission.
-- Rank 255 always has all permissions, rank 0 never has any.
-- @realm shared
-- @character character The character to check
-- @string permKey The permission key to check (e.g., "faction_invite")
-- @treturn bool Whether the character has the permission
function ix.factionperms.HasPermission(character, permKey)
    if not character then return false end

    local classID = character:GetClass()
    if not classID then return false end

    local classData = ix.class.Get(classID)
    if not classData then return false end

    -- Rank 255 (anchor) always has all permissions
    if classData.rank == 255 then return true end

    -- Rank 0 (default) never has permissions
    if classData.rank == 0 then return false end

    -- Check class permissions table
    local perms = classData.permissions or {}
    return perms[permKey] == true
end

--- Check if a character can affect a target rank.
-- A character can only affect ranks strictly below their own.
-- @realm shared
-- @character character The character performing the action
-- @number targetRank The rank being affected
-- @treturn bool Whether the character can affect the target rank
function ix.factionperms.CanAffectRank(character, targetRank)
    if not character then return false end

    local classID = character:GetClass()
    if not classID then return false end

    local classData = ix.class.Get(classID)
    if not classData then return false end

    return targetRank < classData.rank
end

--- Get a character's current rank.
-- @realm shared
-- @character character The character to check
-- @treturn number The character's rank, or -1 if not in a class
function ix.factionperms.GetRank(character)
    if not character then return -1 end

    local classID = character:GetClass()
    if not classID then return -1 end

    local classData = ix.class.Get(classID)
    if not classData then return -1 end

    return classData.rank
end

--- Get the maximum rank a character can create or assign to.
-- This is always their own rank minus 1.
-- @realm shared
-- @character character The character to check
-- @treturn number The maximum assignable rank, or -1 if cannot assign
function ix.factionperms.GetMaxAssignableRank(character)
    local rank = ix.factionperms.GetRank(character)
    if rank <= 0 then return -1 end
    return rank - 1
end

--- Check if a character can grant a specific permission to others.
-- You can only grant permissions you have.
-- @realm shared
-- @character character The character attempting to grant
-- @string permKey The permission key to grant
-- @treturn bool Whether the character can grant this permission
function ix.factionperms.CanGrantPermission(character, permKey)
    return ix.factionperms.HasPermission(character, permKey) and
           ix.factionperms.HasPermission(character, ix.factionperms.PERM_GRANT)
end

--- Get all permissions a character currently has.
-- @realm shared
-- @character character The character to check
-- @treturn table Array of permission keys the character has
function ix.factionperms.GetPermissions(character)
    if not character then return {} end

    local classID = character:GetClass()
    if not classID then return {} end

    local classData = ix.class.Get(classID)
    if not classData then return {} end

    -- Rank 255 has all permissions
    if classData.rank == 255 then
        return table.Copy(ix.factionperms.ALL)
    end

    -- Rank 0 has no permissions
    if classData.rank == 0 then
        return {}
    end

    -- Build list from class permissions
    local result = {}
    local perms = classData.permissions or {}
    for _, permKey in ipairs(ix.factionperms.ALL) do
        if perms[permKey] == true then
            table.insert(result, permKey)
        end
    end

    return result
end

--- Check if a permission key is valid.
-- @realm shared
-- @string permKey The permission key to validate
-- @treturn bool Whether the key is a valid permission
function ix.factionperms.IsValidPermission(permKey)
    for _, perm in ipairs(ix.factionperms.ALL) do
        if perm == permKey then
            return true
        end
    end
    return false
end
