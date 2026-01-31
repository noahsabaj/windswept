
--- Helper library for loading/getting faction information.
-- @module ix.faction

ix.faction = ix.faction or {}
ix.faction.teams = ix.faction.teams or {}
ix.faction.indices = ix.faction.indices or {}

local CITIZEN_MODELS = {
	"models/humans/group01/male_01.mdl",
	"models/humans/group01/male_02.mdl",
	"models/humans/group01/male_04.mdl",
	"models/humans/group01/male_05.mdl",
	"models/humans/group01/male_06.mdl",
	"models/humans/group01/male_07.mdl",
	"models/humans/group01/male_08.mdl",
	"models/humans/group01/male_09.mdl",
	"models/humans/group02/male_01.mdl",
	"models/humans/group02/male_03.mdl",
	"models/humans/group02/male_05.mdl",
	"models/humans/group02/male_07.mdl",
	"models/humans/group02/male_09.mdl",
	"models/humans/group01/female_01.mdl",
	"models/humans/group01/female_02.mdl",
	"models/humans/group01/female_03.mdl",
	"models/humans/group01/female_06.mdl",
	"models/humans/group01/female_07.mdl",
	"models/humans/group02/female_01.mdl",
	"models/humans/group02/female_03.mdl",
	"models/humans/group02/female_06.mdl",
	"models/humans/group01/female_04.mdl"
}

--- Loads factions from a directory.
-- @realm shared
-- @string directory The path to the factions files.
function ix.faction.LoadFromDir(directory)
	for _, v in ipairs(file.Find(directory.."/*.lua", "LUA")) do
		local niceName = v:sub(4, -5)

		FACTION = ix.faction.teams[niceName] or {index = table.Count(ix.faction.teams) + 1, isDefault = false}
			if (PLUGIN) then
				FACTION.plugin = PLUGIN.uniqueID
			end

			ix.util.Include(directory.."/"..v, "shared")

			if (!FACTION.name) then
				FACTION.name = "Unknown"
				ErrorNoHalt("Faction '"..niceName.."' is missing a name. You need to add a FACTION.name = \"Name\"\n")
			end

			if (!FACTION.color) then
				FACTION.color = Color(150, 150, 150)
				ErrorNoHalt("Faction '"..niceName.."' is missing a color. You need to add FACTION.color = Color(1, 2, 3)\n")
			end

			team.SetUp(FACTION.index, FACTION.name or "Unknown", FACTION.color or Color(125, 125, 125))

			FACTION.models = FACTION.models or CITIZEN_MODELS
			FACTION.uniqueID = FACTION.uniqueID or niceName

			for _, v2 in pairs(FACTION.models) do
				if (isstring(v2)) then
					util.PrecacheModel(v2)
				elseif (istable(v2)) then
					util.PrecacheModel(v2[1])
				end
			end

			if (!FACTION.GetModels) then
				function FACTION:GetModels(client)
					return self.models
				end
			end

			ix.faction.indices[FACTION.index] = FACTION
			ix.faction.teams[niceName] = FACTION
		FACTION = nil
	end
end

--- Retrieves a faction table.
-- @realm shared
-- @param identifier Index or name of the faction
-- @treturn table Faction table
-- @usage print(ix.faction.Get(Entity(1):Team()).name)
-- > "Citizen"
function ix.faction.Get(identifier)
	return ix.faction.indices[identifier] or ix.faction.teams[identifier]
end

--- Retrieves a faction index.
-- @realm shared
-- @string uniqueID Unique ID of the faction
-- @treturn number Faction index
function ix.faction.GetIndex(uniqueID)
	for k, v in ipairs(ix.faction.indices) do
		if (v.uniqueID == uniqueID) then
			return k
		end
	end
end

--- Retrieves all factions that are subordinate to the given faction.
-- @realm shared
-- @param identifier Faction index or uniqueID
-- @treturn table Array of subordinate faction data tables
function ix.faction.GetSubordinates(identifier)
	local parentFaction = ix.faction.Get(identifier)
	if not parentFaction then return {} end

	local subordinates = {}
	local parentUniqueID = parentFaction.uniqueID

	for _, factionData in pairs(ix.faction.teams) do
		if factionData.subordinateOf == parentUniqueID then
			table.insert(subordinates, factionData)
		end
	end

	return subordinates
end

--- Retrieves the parent faction of the given faction.
-- @realm shared
-- @param identifier Faction index or uniqueID
-- @treturn table|nil Parent faction data table, or nil if none
function ix.faction.GetParent(identifier)
	local faction = ix.faction.Get(identifier)
	if not faction or not faction.subordinateOf then
		return nil
	end

	return ix.faction.teams[faction.subordinateOf]
end

--- Checks if a faction can appoint the leader of another faction.
-- This follows the subordinate hierarchy: a faction's leader can appoint
-- the anchor (rank 255) of their subordinate factions.
-- @realm shared
-- @param appointerFaction Faction index or uniqueID of the appointer
-- @param targetFaction Faction index or uniqueID of the faction to appoint to
-- @treturn bool Whether the appointer can appoint the target faction's leader
function ix.faction.CanAppoint(appointerFaction, targetFaction)
	local appointer = ix.faction.Get(appointerFaction)
	local target = ix.faction.Get(targetFaction)

	if not appointer or not target then
		return false
	end

	-- Check if target is subordinate of appointer
	if target.subordinateOf == appointer.uniqueID then
		return true
	end

	return false
end

--- Gets the anchor class (rank 255) for a faction.
-- @realm shared
-- @param identifier Faction index or uniqueID
-- @treturn table|nil Anchor class data table, or nil if none found
function ix.faction.GetAnchorClass(identifier)
	local faction = ix.faction.Get(identifier)
	if not faction then return nil end

	for _, classData in pairs(ix.class.list) do
		if classData.faction == faction.index and classData.rank == 255 then
			return classData
		end
	end

	return nil
end

--- Gets the default class (rank 0) for a faction.
-- @realm shared
-- @param identifier Faction index or uniqueID
-- @treturn table|nil Default class data table, or nil if none found
function ix.faction.GetDefaultClass(identifier)
	local faction = ix.faction.Get(identifier)
	if not faction then return nil end

	for _, classData in pairs(ix.class.list) do
		if classData.faction == faction.index and classData.isDefault then
			return classData
		end
	end

	return nil
end

if (CLIENT) then
	--- Returns true if a faction requires a whitelist.
	-- @realm client
	-- @number faction Index of the faction
	-- @treturn bool Whether or not the faction requires a whitelist
	function ix.faction.HasWhitelist(faction)
		-- Factionless is always allowed
		if (faction == nil) then
			return true
		end

		local data = ix.faction.indices[faction]

		if (data) then
			if (data.isDefault) then
				return true
			end

			local ixData = ix.localData and ix.localData.whitelists or {}

			return ixData[Schema.folder] and ixData[Schema.folder][data.uniqueID] == true or false
		end

		return false
	end
end
