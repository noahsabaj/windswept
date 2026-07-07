
--[[--
Contains information about a player's current game state.

Characters are a fundamental object type in Windswept. They are distinct from players, where players are the representation of a
person's existence in the server that owns a character, and their character is their currently selected persona. All the
characters that a player owns will be loaded into memory once they connect to the server. Characters are saved during a regular
interval, and during specific events (e.g when the owning player switches away from one character to another).

They contain all information that is not persistent with the player; names, descriptions, model, currency, etc. For the most
part, you'll want to keep all information stored on the character since it will probably be different or change if the
player switches to another character. An easy way to do this is to use `ws.char.RegisterVar` to easily create accessor functions
for variables that automatically save to the character object.
]]
-- @classmod Character

local CHAR = ws.meta.character or {}
CHAR.__index = CHAR
CHAR.id = CHAR.id or 0
CHAR.vars = CHAR.vars or {}

-- @todo not this
if (!ws.db) then
	ws.util.Include("../libs/sv_database.lua")
end

--- Returns a string representation of this character
-- @realm shared
-- @treturn string String representation
-- @usage print(ws.char.loaded[1])
-- > "character[1]"
function CHAR:__tostring()
	return "character["..(self.id or 0).."]"
end

--- Returns true if this character is equal to another character. Internally, this checks character IDs.
-- @realm shared
-- @char other Character to compare to
-- @treturn bool Whether or not this character is equal to the given character
-- @usage print(ws.char.loaded[1] == ws.char.loaded[2])
-- > false
function CHAR:__eq(other)
	return self:GetID() == other:GetID()
end

--- Returns this character's database ID. This is guaranteed to be unique.
-- @realm shared
-- @treturn number Unique ID of character
function CHAR:GetID()
	return self.id
end

if (SERVER) then
	--- Saves this character's info to the database.
	-- @realm server
	-- @func[opt=nil] callback Function to call when the save has completed.
	-- @usage ws.char.loaded[1]:Save(function()
	-- 	print("done!")
	-- end)
	-- > done! -- after a moment
	function CHAR:Save(callback)
		-- Do not save if the character is for a bot.
		if (self.isBot) then
			return
		end

		-- Let plugins/schema determine if the character should be saved.
		local shouldSave = hook.Run("CharacterPreSave", self)

		if (shouldSave != false) then
			-- Run a query to save the character to the database.
			local query = mysql:Update("ws_characters")
				-- Update all character vars
				-- Optimization: Cache previous values and only update changed fields
				local prevValues = self._savedVars or {}
				local hasChanges = false

				for k, v in pairs(ws.char.vars) do
					if (v.field and self.vars[k] != nil and !v.bSaveLoadInitialOnly) then
						local value = self.vars[k]
						local serialized = istable(value) and util.TableToJSON(value) or tostring(value)

						-- Only update if value changed since last save
						if (prevValues[k] != serialized) then
							query:Update(v.field, serialized)
							prevValues[k] = serialized
							hasChanges = true
						end
					end
				end

				-- Store for next comparison
				self._savedVars = prevValues

				-- Only execute if there are actual changes
				if (hasChanges) then
					query:Where("id", self:GetID())
					query:Callback(function()
						if (callback) then
							callback()
						end

						hook.Run("CharacterPostSave", self)
					end)
					query:Execute()
				elseif (callback) then
					callback()
				end
		end
	end

	--- Networks this character's information to its owning player. Fog of war: a character's data and
	-- its persistent id are sent ONLY to the owner; other players learn nothing off the wire. Passing
	-- a non-owner receiver is a no-op. This is done automatically by the framework.
	-- @internal
	-- @realm server
	-- @player[opt=nil] receiver Player to send the information to. Only the owner is ever sent data; a
	-- `nil` receiver syncs the owner alone.
	function CHAR:Sync(receiver)
		-- Fog of war: a character's data AND its persistent database id are networked ONLY to the
		-- owning client. Non-owners are told nothing off the wire -- identity (and any stable handle
		-- to it) is reconstructed in-world, never read from a packet. A nil receiver therefore syncs
		-- the owner alone rather than every player, and a request to sync a non-owner is a no-op.
		-- name/description/attributes/money/data are already isLocal; this closes the last channel
		-- (the raw id) that reached other clients. (fw-fogofwar-1)
		local owner = self.player

		if (!IsValid(owner)) then return end
		if (receiver != nil and receiver != owner) then return end

		local data = {}

		for k, v in pairs(self.vars) do
			if (ws.char.vars[k] != nil and !ws.char.vars[k].bNoNetworking) then
				data[k] = v
			end
		end

		net.Start("wsCharacterInfo")
			net.WriteTable(data)
			net.WriteUInt(self:GetID(), 32)
			net.WriteUInt(owner:EntIndex(), 8)
		net.Send(owner)
	end

	-- Sets up the "appearance" related inforomation for the character.
	--- Applies the character's appearance and synchronizes information to the owning player.
	-- @realm server
	-- @internal
	-- @bool[opt] bNoNetworking Whether or not to sync the character info to other players
	function CHAR:Setup(bNoNetworking)
		local client = self:GetPlayer()

		if (IsValid(client)) then
			-- Set the model and character index for the player. Everyone shares one team.
			local model = self:GetModel()

			-- Fog of war: scope the character id netvar to its owner. Other clients must not
			-- learn a player's persistent character id (a stable identity beacon that survives
			-- model/skin/disguise changes). The server still stores it locally, so server-side
			-- GetNetVar("char") lookups are unaffected. (fw-fogofwar-1)
			client:SetNetVar("char", self:GetID(), client)
			client:SetTeam(TEAM_PLAYER)
			client:SetModel(istable(model) and model[1] or model)

			-- Apply saved body groups.
			for k, v in pairs(self:GetData("groups", {})) do
				client:SetBodygroup(k, v)
			end

			-- Apply a saved skin.
			client:SetSkin(self:GetData("skin", 0))

			-- Synchronize the character if we should.
			if (!bNoNetworking) then
				if (client:IsBot()) then
					timer.Simple(0.33, function()
						self:Sync()
					end)
				else
					self:Sync()
				end

				for _, v in ipairs(self:GetInventory(true)) do
					if (istable(v)) then
						v:AddReceiver(client)
						v:Sync(client)
					end
				end
			end

			local id = self:GetID()

			hook.Run("CharacterLoaded", ws.char.loaded[id])

			net.Start("wsCharacterLoaded")
				net.WriteUInt(id, 32)
			net.Send(client)

			self.firstTimeLoaded = true
		end
	end

	--- Forces a player off their current character, and sends them to the character menu to select a character.
	-- @realm server
	function CHAR:Kick()
		-- Kill the player so they are not standing anywhere.
		local client = self:GetPlayer()
		client:KillSilent()

		local steamID = client:SteamID64()
		local id = self:GetID()
		local isCurrentChar = self and self:GetID() == id

		-- Return the player to the character menu.
		if (self and self.steamID == steamID) then
			net.Start("wsCharacterKick")
				net.WriteBool(isCurrentChar)
			net.Send(client)

			if (isCurrentChar) then
				client:SetNetVar("char", nil)
				client:Spawn()
			end
		end
	end

	--- Forces a player off their current character, and prevents them from using the character for the specified amount of time.
	-- @realm server
	-- @number[opt] time Amount of seconds to ban the character for. If left as `nil`, the character will be banned permanently
	function CHAR:Ban(time)
		time = tonumber(time)

		if (time) then
			-- If time is provided, adjust it so it becomes the un-ban time.
			time = os.time() + math.max(math.ceil(time), 60)
		end

		-- Mark the character as banned and kick the character back to menu.
		self:SetData("banned", time or true)
		self:Kick()
	end
end

-- Global SteamID64 -> Player lookup cache for O(1) GetPlayer() lookups
-- Populated by player connect/disconnect hooks
ws.char.playerBySteamID = ws.char.playerBySteamID or {}

-- Hook to update lookup table (runs in Windswept core after this file loads)
hook.Add("PlayerAuthed", "wsCharPlayerLookup", function(client, steamID, uniqueID)
	ws.char.playerBySteamID[client:SteamID64()] = client
end)

hook.Add("PlayerDisconnected", "wsCharPlayerLookup", function(client)
	ws.char.playerBySteamID[client:SteamID64()] = nil
end)

--- Returns the player that owns this character.
-- @realm shared
-- @treturn player Player that owns this character
function CHAR:GetPlayer()
	-- Set the player from entity index.
	if (isnumber(self.player)) then
		local client = Entity(self.player)

		if (IsValid(client)) then
			self.player = client

			return client
		end
	-- Return the player from cache.
	elseif (IsValid(self.player)) then
		return self.player
	-- Search for which player owns this character using O(1) lookup.
	elseif (self.steamID) then
		local client = ws.char.playerBySteamID[self.steamID]
		if (IsValid(client)) then
			self.player = client
			return client
		end
	end
end

-- Sets up a new character variable.
function ws.char.RegisterVar(key, data)
	-- Store information for the variable.
	ws.char.vars[key] = data
	data.index = data.index or table.Count(ws.char.vars)

	local upperName = key:sub(1, 1):upper() .. key:sub(2)

	if (SERVER) then
		if (data.field) then
			ws.db.AddToSchema("ws_characters", data.field, data.fieldType or ws.type.string)
		end

		-- Provide functions to change the variable if allowed.
		if (!data.bNotModifiable) then
			-- Overwrite the set function if desired.
			if (data.OnSet) then
				CHAR["Set"..upperName] = data.OnSet
			-- Have the set function only set on the server if no networking.
			elseif (data.bNoNetworking) then
				CHAR["Set"..upperName] = function(self, value)
					self.vars[key] = value
				end
			-- If the variable is a local one, only send the variable to the local player.
			elseif (data.isLocal) then
				CHAR["Set"..upperName] = function(self, value)
					local oldVar = self.vars[key]
					self.vars[key] = value

					net.Start("wsCharacterVarChanged")
						net.WriteUInt(self:GetID(), 32)
						net.WriteString(key)
						net.WriteType(value)
					net.Send(self.player)

					hook.Run("CharacterVarChanged", self, key, oldVar, value)
				end
			-- Otherwise network the variable to everyone.
			else
				CHAR["Set"..upperName] = function(self, value)
					local oldVar = self.vars[key]
					self.vars[key] = value

					net.Start("wsCharacterVarChanged")
						net.WriteUInt(self:GetID(), 32)
						net.WriteString(key)
						net.WriteType(value)
					net.Broadcast()

					hook.Run("CharacterVarChanged", self, key, oldVar, value)
				end
			end
		end
	end

	-- The get functions are shared.
	-- Overwrite the get function if desired.
	if (data.OnGet) then
		CHAR["Get"..upperName] = data.OnGet
	-- Otherwise return the character variable or default if it does not exist.
	else
		CHAR["Get"..upperName] = function(self, default)
			local value = self.vars[key]

			if (value != nil) then
				return value
			end

			if (default == nil) then
				return ws.char.vars[key] and (istable(ws.char.vars[key].default) and table.Copy(ws.char.vars[key].default)
					or ws.char.vars[key].default)
			end

			return default
		end
	end

	local alias = data.alias

	if (alias) then
		if (istable(alias)) then
			for _, v in ipairs(alias) do
				local aliasName = v:sub(1, 1):upper()..v:sub(2)

				CHAR["Get"..aliasName] = CHAR["Get"..upperName]
				CHAR["Set"..aliasName] = CHAR["Set"..upperName]
			end
		elseif (isstring(alias)) then
			local aliasName = alias:sub(1, 1):upper()..alias:sub(2)

			CHAR["Get"..aliasName] = CHAR["Get"..upperName]
			CHAR["Set"..aliasName] = CHAR["Set"..upperName]
		end
	end

	-- Add the variable default to the character object.
	CHAR.vars[key] = data.default
end

-- Allows access to the character metatable using ws.meta.character
ws.meta.character = CHAR
