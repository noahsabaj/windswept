
--[[--
Helper library for loading/getting class information.

Classes are temporary assignments for characters - analogous to a "job" in a faction. For example, you may have a police faction
in your schema, and have "police recruit" and "police chief" as different classes in your faction. Anyone can join a class in
their faction by default, but you can restrict this as you need with `CLASS.CanSwitchTo`.
]]
-- @module ws.class

--- Class definition table returned by `ws.class.Get`.
-- @realm shared
-- @tab class Class definition table.
-- Default keys:
--
-- - `index` (number) - numeric class ID
-- - `uniqueID` (string) - stable identifier (e.g. `citizen`)
-- - `name` (string)
-- - `description` (string)
-- - `faction` (number) - Faction ID this class belongs to
-- - `isDefault` (boolean) - whether it is the default class for the faction
-- - `limit` (number) - maximum number of players allowed in this class (0 for unlimited)
-- - `CanSwitchTo` (function|nil) - optional callback to check if a player may switch


if (SERVER) then
	util.AddNetworkString("wsClassUpdate")
	util.AddNetworkString("wsClassListSync")
	util.AddNetworkString("wsClassCreated")
	util.AddNetworkString("wsClassUpdated")
	util.AddNetworkString("wsClassDeleted")
end

ws.class = ws.class or {}
ws.class.list = {}
ws.class.byDatabaseID = {}
ws.class.nextIndex = 1

local charMeta = ws.meta.character

--- Allocates a never-reused numeric class index.
-- Classes are stored on characters by index and `ws.class.Delete` leaves holes in
-- `ws.class.list`, so `#list + 1` could collide with a live class and silently overwrite
-- it. A monotonic counter avoids that; callers must iterate the (possibly sparse) list
-- with `pairs`, never `ipairs`. (fw-faction-class-3)
local function allocClassIndex()
	local index = ws.class.nextIndex
	ws.class.nextIndex = index + 1
	return index
end

--- Loads classes from a directory.
-- @realm shared
-- @internal
-- @string directory The path to the class files.
function ws.class.LoadFromDir(directory)
	for _, v in ipairs(file.Find(directory.."/*.lua", "LUA")) do
		-- Get the name without the "sh_" prefix and ".lua" suffix.
		local niceName = v:sub(4, -5)
		-- Determine a numeric identifier for this class.
		local index = allocClassIndex()
		local halt

		for _, v2 in pairs(ws.class.list) do
			if (v2.uniqueID == niceName) then
				halt = true

                break
			end
		end

		if (halt == true) then
			continue
		end

		-- Set up a global table so the file has access to the class table.
		CLASS = {index = index, uniqueID = niceName}
			CLASS.name = "Unknown"
			CLASS.description = "No description available."
			CLASS.limit = 0
			CLASS.rank = 255  -- File-loaded classes default to anchor rank
			CLASS.pay = 0
			CLASS.permissions = {}
			CLASS.isAnchor = true  -- File-loaded classes are anchors
			CLASS.isDefault = false

			-- For future use with plugins.
			if (PLUGIN) then
				CLASS.plugin = PLUGIN.uniqueID
			end

			ws.util.Include(directory.."/"..v, "shared")

			-- Why have a class without a faction?
			if (!CLASS.faction or !team.Valid(CLASS.faction)) then
				ErrorNoHalt("Class '"..niceName.."' does not have a valid faction!\n")
				CLASS = nil

				continue
			end

			-- Allow classes to be joinable by default.
			if (!CLASS.CanSwitchTo) then
				CLASS.CanSwitchTo = function(client)
					return true
				end
			end

			-- Set timestamps for file-loaded classes
			CLASS.createdAt = os.time()
			CLASS.updatedAt = os.time()

			ws.class.list[index] = CLASS
		CLASS = nil
	end
end

--- Determines if a player is allowed to join a specific class.
-- @realm shared
-- @player client Player to check
-- @number class Index of the class
-- @treturn bool Whether or not the player can switch to the class.
-- @treturn string The reason why the player cannot switch (if applicable).
-- @usage -- Check if a player can join class ID 2.
-- -- For our example, they can't- because they are in the wrong faction.
-- local canJoin, reason = ws.class.CanSwitchTo(player, 2)
-- if (!canJoin) then
--     print("Player cannot join class: "..reason)
-- end
-- > Player cannot join class: not correct team
function ws.class.CanSwitchTo(client, class)
	-- Get the class table by its numeric identifier.
	local info = ws.class.list[class]

	-- See if the class exists.
	if (!info) then
		return false, "no info"
	end

	-- Factionless players cannot join any class
	local playerFaction = client:Team()
	if (playerFaction == TEAM_UNASSIGNED) then
		return false, "noFaction"
	end

	-- If the player's faction matches the class's faction.
	if (playerFaction != info.faction) then
		return false, "not correct team"
	end

	local character = client:GetCharacter()
	if (!character) then
		return false, "no character"
	end

	if (character:GetClass() == class) then
		return false, "same class request"
	end

	if (info.limit > 0) then
		if (#ws.class.GetPlayers(info.index) >= info.limit) then
			return false, "class is full"
		end
	end

	if (hook.Run("CanPlayerJoinClass", client, class, info) == false) then
		return false
	end

	-- See if the class allows the player to join it.
	return info:CanSwitchTo(client)
end

--- Gets a class definition table by numeric identifier.
-- @realm shared
-- @tparam number identifier Numeric class identifier.
-- @treturn table|nil Class definition table (see `class` table docs).
-- @usage -- Print the name of class ID 1
-- print(ws.class.Get(1).name)
-- > Citizen
function ws.class.Get(identifier)
	return ws.class.list[identifier]
end

--- Retrieves all players currently assigned to a specific class.
-- @realm shared
-- @number class Index of the class
-- @treturn table Numerically indexed table of players in the class, or an empty table if none are found.
-- @usage -- Print all players in class ID 1
-- for _, ply in ipairs(ws.class.GetPlayers(1)) do
--     print(ply:GetName())
-- end
-- > Player1
-- > Player2
-- > etc
function ws.class.GetPlayers(class)
	local players = {}

	for _, v in player.Iterator() do
		local char = v:GetCharacter()

		if (char and char:GetClass() == class) then
			table.insert(players, v)
		end
	end

	return players
end

--- Retrieves all classes for a specific faction.
-- @realm shared
-- @number factionID Faction team ID
-- @treturn table Array of class data tables for this faction
function ws.class.GetByFaction(factionID)
	local classes = {}

	for _, classData in pairs(ws.class.list) do
		if classData.faction == factionID then
			table.insert(classes, classData)
		end
	end

	return classes
end

--- Retrieves all classes at a specific rank within a faction.
-- @realm shared
-- @number factionID Faction team ID
-- @number rank Target rank (0-255)
-- @treturn table Array of class data tables at this rank
function ws.class.GetByRank(factionID, rank)
	local classes = {}

	for _, classData in pairs(ws.class.list) do
		if classData.faction == factionID and classData.rank == rank then
			table.insert(classes, classData)
		end
	end

	return classes
end

--- Retrieves all players at a specific rank within a faction.
-- @realm shared
-- @number factionID Faction team ID
-- @number rank Target rank (0-255)
-- @treturn table Array of {player, character} tables
function ws.class.GetPlayersAtRank(factionID, rank)
	local results = {}

	for _, ply in player.Iterator() do
		if ply:Team() == factionID then
			local char = ply:GetCharacter()
			if char then
				local classID = char:GetClass()
				local classData = ws.class.Get(classID)
				if classData and classData.rank == rank then
					table.insert(results, {player = ply, character = char})
				end
			end
		end
	end

	return results
end

--- Finds the next highest occupied rank below the given rank in a faction.
-- Used for succession to find candidates.
-- @realm shared
-- @number factionID Faction team ID
-- @number fromRank Starting rank to search down from
-- @treturn number|nil The next rank with players, or nil if none found
function ws.class.FindNextRankDown(factionID, fromRank)
	-- Build sorted list of ranks with players
	local ranksWithPlayers = {}

	for _, classData in pairs(ws.class.list) do
		if classData.faction == factionID and classData.rank < fromRank and classData.rank > 0 then
			local players = ws.class.GetPlayers(classData.index)
			if #players > 0 then
				ranksWithPlayers[classData.rank] = true
			end
		end
	end

	-- Find highest rank below fromRank
	local highestRank = nil
	for rank, _ in pairs(ranksWithPlayers) do
		if not highestRank or rank > highestRank then
			highestRank = rank
		end
	end

	return highestRank
end

--- Gets a class by its database ID.
-- @realm shared
-- @number databaseID Database row ID
-- @treturn table|nil Class data table
function ws.class.GetByDatabaseID(databaseID)
	return ws.class.byDatabaseID[databaseID]
end

if (SERVER) then
	--- Character class methods
	-- @classmod Character

	--- Makes this character join a class. This automatically calls `KickClass` for you.
	-- @realm server
	-- @number class Index of the class to join
	-- @treturn bool Whether or not the character has successfully joined the class
	function charMeta:JoinClass(class)
		if (!class) then
			self:KickClass()
			return false
		end

		local oldClass = self:GetClass()
		local client = self:GetPlayer()

		if (ws.class.CanSwitchTo(client, class)) then
			self:SetClass(class)
			hook.Run("PlayerJoinedClass", client, class, oldClass)

			return true
		end

		return false
	end

	--- Kicks this character out of the class they are currently in.
	-- @realm server
	function charMeta:KickClass()
		local client = self:GetPlayer()

		if (!IsValid(client)) then
			return
		end

		local playerFaction = client:Team()

		-- Factionless players just have no class
		if (playerFaction == TEAM_UNASSIGNED) then
			self:SetClass(nil)
			return
		end

		local goClass

		for k, v in pairs(ws.class.list) do
			if (v.faction == playerFaction and v.isDefault) then
				goClass = k
				break
			end
		end

		if (!goClass) then
			-- No default class found - just clear class
			self:SetClass(nil)
			return
		end

		-- JoinClass already fires the PlayerJoinedClass hook; don't double-fire it.
		self:JoinClass(goClass)
	end

	function GM:PlayerJoinedClass(client, class, oldClass)
		local info = ws.class.list[class]
		local info2 = ws.class.list[oldClass]

		if (info and info.OnSet) then
			info:OnSet(client)
		end

		if (info2 and info2.OnLeave) then
			info2:OnLeave(client)
		end

		net.Start("wsClassUpdate")
			net.WriteEntity(client)
		net.Broadcast()
	end

	--- Creates a new class in the database and memory.
	-- @realm server
	-- @tparam table data Class data table with: faction, name, description, rank, pay, permissions, createdBy
	-- @treturn table|nil Created class data, or nil on failure
	function ws.class.Create(data)
		if not data.faction or not data.name then
			return nil
		end

		local now = os.time()
		local index = allocClassIndex()

		-- Generate a stable, unique uniqueID from the name. uniqueID is a persisted
		-- identifier, so it must be collision-free and is never recomputed on rename.
		-- (fw-faction-class-5)
		local baseUniqueID = string.lower(string.gsub(data.name, "%s+", "_"))
		local uniqueID = baseUniqueID
		local suffix = 1

		local function uniqueIDTaken(id)
			for _, c in pairs(ws.class.list) do
				if (c.uniqueID == id) then
					return true
				end
			end

			return false
		end

		while (uniqueIDTaken(uniqueID)) do
			suffix = suffix + 1
			uniqueID = baseUniqueID .. "_" .. suffix
		end

		-- Get faction data for team ID
		local factionData = ws.faction.teams[data.faction]
		if not factionData then
			return nil
		end

		local classData = {
			index = index,
			uniqueID = uniqueID,
			name = data.name,
			description = data.description or "",
			faction = factionData.index,
			rank = data.rank or 1,
			pay = data.pay or 0,
			limit = data.classLimit or 0,
			permissions = data.permissions or {},
			isAnchor = false,
			isDefault = false,
			createdBy = data.createdBy,
			createdAt = now,
			updatedAt = now,
		}

		-- Add CanSwitchTo function
		classData.CanSwitchTo = function(self, client)
			return true
		end

		-- Insert into database
		local query = mysql:Insert("ws_faction_classes")
		query:Insert("faction", data.faction)
		query:Insert("unique_id", uniqueID)
		query:Insert("name", data.name)
		query:Insert("description", data.description or "")
		query:Insert("rank", data.rank or 1)
		query:Insert("pay", data.pay or 0)
		query:Insert("class_limit", data.classLimit or 0)
		query:Insert("permissions", util.TableToJSON(data.permissions or {}))
		query:Insert("is_anchor", 0)
		query:Insert("is_default", 0)
		query:Insert("created_by", data.createdBy)
		query:Insert("created_at", now)
		query:Insert("updated_at", now)
		query:Callback(function(result, status, lastID)
			if lastID then
				classData.id = lastID
				ws.class.byDatabaseID[lastID] = classData

				-- Network to clients
				net.Start("wsClassCreated")
					net.WriteTable(classData)
				net.Broadcast()
			end
		end)
		query:Execute()

		-- Add to memory immediately
		ws.class.list[index] = classData

		return classData
	end

	--- Updates a class in the database and memory.
	-- @realm server
	-- @number databaseID Database row ID of the class
	-- @tparam table updates Table of fields to update
	-- @treturn bool Success
	function ws.class.Update(databaseID, updates)
		local classData = ws.class.byDatabaseID[databaseID]
		if not classData then
			return false
		end

		local now = os.time()

		-- Update memory
		for key, value in pairs(updates) do
			if key == "classLimit" then
				classData.limit = value
			else
				classData[key] = value
			end
		end
		classData.updatedAt = now

		-- Update database
		local query = mysql:Update("ws_faction_classes")

		if updates.name then
			query:Update("name", updates.name)
			-- uniqueID is a persisted stable identifier; only the display name changes on
			-- rename, never the uniqueID. (fw-faction-class-5)
		end
		if updates.description then
			query:Update("description", updates.description)
		end
		if updates.rank then
			query:Update("rank", updates.rank)
		end
		if updates.pay then
			query:Update("pay", updates.pay)
		end
		if updates.classLimit then
			query:Update("class_limit", updates.classLimit)
		end
		if updates.permissions then
			query:Update("permissions", util.TableToJSON(updates.permissions))
		end

		query:Update("updated_at", now)
		query:Where("id", databaseID)
		query:Execute()

		-- Network to clients
		net.Start("wsClassUpdated")
			net.WriteUInt(databaseID, 32)
			net.WriteTable(updates)
		net.Broadcast()

		return true
	end

	--- Deletes a class from the database and memory.
	-- @realm server
	-- @number databaseID Database row ID of the class
	-- @treturn bool Success
	function ws.class.Delete(databaseID)
		local classData = ws.class.byDatabaseID[databaseID]
		if not classData then
			return false
		end

		-- Cannot delete anchor or default classes
		if classData.isAnchor or classData.isDefault then
			return false
		end

		-- Check for members
		local members = ws.class.GetPlayers(classData.index)
		if #members > 0 then
			return false
		end

		-- Remove from memory
		ws.class.list[classData.index] = nil
		ws.class.byDatabaseID[databaseID] = nil

		-- Remove from database
		local query = mysql:Delete("ws_faction_classes")
		query:Where("id", databaseID)
		query:Execute()

		-- Network to clients
		net.Start("wsClassDeleted")
			net.WriteUInt(databaseID, 32)
		net.Broadcast()

		return true
	end

	--- Loads all classes from the database.
	-- WIP: the DB-backed class system is not yet wired into boot. To activate it, call
	-- ws.class.LoadFromDatabase() after factions load on server init, and
	-- ws.class.SyncToClients(client) on PlayerInitialSpawn (the file-loaded classes from
	-- LoadFromDir remain the active path until then). (fw-faction-class-6)
	-- @realm server
	function ws.class.LoadFromDatabase()
		local query = mysql:Select("ws_faction_classes")
		query:Callback(function(result)
			if not result then return end

			for _, row in ipairs(result) do
				local factionData = ws.faction.teams[row.faction]
				if factionData then
					local index = allocClassIndex()

					local classData = {
						id = row.id,
						index = index,
						uniqueID = row.unique_id,
						name = row.name,
						description = row.description or "",
						faction = factionData.index,
						rank = row.rank,
						pay = row.pay,
						limit = row.class_limit or 0,
						permissions = util.JSONToTable(row.permissions or "{}") or {},
						isAnchor = row.is_anchor == 1,
						isDefault = row.is_default == 1,
						createdBy = row.created_by,
						createdAt = row.created_at,
						updatedAt = row.updated_at,
					}

					-- Add CanSwitchTo function
					classData.CanSwitchTo = function(self, client)
						return true
					end

					ws.class.list[index] = classData
					ws.class.byDatabaseID[row.id] = classData
				end
			end

			print("[Windswept] Loaded " .. #result .. " classes from database")

			-- Sync to all connected clients
			ws.class.SyncToClients()
		end)
		query:Execute()
	end

	--- Syncs the class list to all clients.
	-- @realm server
	-- @player[opt] client Specific client to sync to, or nil for all
	function ws.class.SyncToClients(client)
		-- Prepare class data for networking (strip functions)
		local syncData = {}
		for index, classData in pairs(ws.class.list) do
			syncData[index] = {
				id = classData.id,
				index = classData.index,
				uniqueID = classData.uniqueID,
				name = classData.name,
				description = classData.description,
				faction = classData.faction,
				rank = classData.rank,
				pay = classData.pay,
				limit = classData.limit,
				permissions = classData.permissions,
				isAnchor = classData.isAnchor,
				isDefault = classData.isDefault,
			}
		end

		net.Start("wsClassListSync")
			net.WriteTable(syncData)
		if client then
			net.Send(client)
		else
			net.Broadcast()
		end
	end
end

-- Client-side network receivers
if CLIENT then
	net.Receive("wsClassListSync", function()
		local syncData = net.ReadTable()

		for index, classData in pairs(syncData) do
			-- Add CanSwitchTo function
			classData.CanSwitchTo = function(self, client)
				return true
			end

			ws.class.list[index] = classData
			if classData.id then
				ws.class.byDatabaseID[classData.id] = classData
			end
		end
	end)

	net.Receive("wsClassCreated", function()
		local classData = net.ReadTable()

		-- Add CanSwitchTo function
		classData.CanSwitchTo = function(self, client)
			return true
		end

		ws.class.list[classData.index] = classData
		if classData.id then
			ws.class.byDatabaseID[classData.id] = classData
		end
	end)

	net.Receive("wsClassUpdated", function()
		local databaseID = net.ReadUInt(32)
		local updates = net.ReadTable()

		local classData = ws.class.byDatabaseID[databaseID]
		if classData then
			for key, value in pairs(updates) do
				if key == "classLimit" then
					classData.limit = value
				else
					classData[key] = value
				end
			end
		end
	end)

	net.Receive("wsClassDeleted", function()
		local databaseID = net.ReadUInt(32)

		local classData = ws.class.byDatabaseID[databaseID]
		if classData then
			ws.class.list[classData.index] = nil
			ws.class.byDatabaseID[databaseID] = nil
		end
	end)
end
