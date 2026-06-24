
--[[--
Character creation and management.

**NOTE:** For the most part you shouldn't use this library unless you know what you're doing. You can very easily corrupt
character data using these functions!
]]
-- @module ws.char

ws.char = ws.char or {}

--- Characters that are currently loaded into memory. This is **not** a table of characters that players are currently using.
-- Characters are automatically loaded when a player joins the server. Entries are not cleared once the player disconnects, as
-- some data is needed after the player has disconnected. Clients will also keep their own version of this table, so don't
-- expect it to be the same as the server's.
--
-- The keys in this table are the IDs of characters, and the values are the `Character` objects that the ID corresponds to.
-- @realm shared
-- @table ws.char.loaded
-- @usage print(ws.char.loaded[1])
-- > character[1]
ws.char.loaded = ws.char.loaded or {}

--- Variables that are stored on characters. This table is populated automatically by `ws.char.RegisterVar`.
-- @realm shared
-- @table ws.char.vars
-- @usage print(ws.char.vars["name"])
-- > table: 0xdeadbeef
ws.char.vars = ws.char.vars or {}

--- Functions similar to `ws.char.loaded`, but is serverside only. This contains a table of all loaded characters grouped by
-- the SteamID64 of the player that owns them.
-- @realm server
-- @table ws.char.cache
ws.char.cache = ws.char.cache or {}

ws.util.Include(ws.FRAMEWORK_FOLDER.."/gamemode/core/meta/sh_character.lua")

if (SERVER) then
	--- Creates a character object with its assigned properties and saves it to the database.
	-- @realm server
	-- @tab data Properties to assign to this character. If fields are missing from the table, then it will use the default
	-- value for that property
	-- @func callback Function to call after the character saves
	function ws.char.Create(data, callback)
		local timeStamp = math.floor(os.time())

		data.money = data.money or ws.config.Get("defaultMoney", 0)
		data.schema = Schema and Schema.folder or "windswept"
		data.createTime = timeStamp
		data.lastJoinTime = timeStamp

		local query = mysql:Insert("ws_characters")
			query:Insert("name", data.name or "")
			query:Insert("description", data.description or "")
			query:Insert("model", data.model or "models/error.mdl")
			query:Insert("schema", Schema and Schema.folder or "windswept")
			query:Insert("create_time", data.createTime)
			query:Insert("last_join_time", data.lastJoinTime)
			query:Insert("steamid", data.steamID)
			query:Insert("money", data.money)
			query:Insert("data", util.TableToJSON(data.data or {}))
			query:Callback(function(result, status, lastID)
				local invQuery = mysql:Insert("ws_inventories")
					invQuery:Insert("character_id", lastID)
					invQuery:Callback(function(invResult, invStats, invLastID)
						local client = player.GetBySteamID64(data.steamID)

						ws.char.RestoreVars(data, data)

						local w, h = ws.config.Get("inventoryWidth"), ws.config.Get("inventoryHeight")
						local character = ws.char.New(data, lastID, client, data.steamID)
						local inventory = ws.inventory.Create(w, h, invLastID)

						character.vars.inv = {inventory}
						inventory:SetOwner(lastID)

						ws.char.loaded[lastID] = character
						table.insert(ws.char.cache[data.steamID], lastID)

						if (callback) then
							callback(lastID)
						end
					end)
				invQuery:Execute()
			end)
		query:Execute()
	end

	--- Loads all of a player's characters into memory.
	-- @realm server
	-- @player client Player to load the characters for
	-- @func[opt=nil] callback Function to call when the characters have been loaded
	-- @bool[opt=false] bNoCache Whether or not to skip the cache; players that leave and join again later will already have
	-- their characters loaded which will skip the database query and load quicker
	-- @number[opt=nil] id The ID of a specific character to load instead of all of the player's characters
	function ws.char.Restore(client, callback, bNoCache, id)
		local steamID64 = client:SteamID64()
		local cache = ws.char.cache[steamID64]

		if (cache and !bNoCache) then
			for _, v in ipairs(cache) do
				local character = ws.char.loaded[v]

				if (character and !IsValid(character.client)) then
					character.player = client
				end
			end

			if (callback) then
				callback(cache)
			end

			return
		end

		local query = mysql:Select("ws_characters")
			query:Select("id")

			ws.char.RestoreVars(query)

			query:Where("schema", Schema.folder)
			query:Where("steamid", steamID64)

			if (id) then
				query:Where("id", id)
			end

			query:Callback(function(result)
				local characters = {}

				for _, v in ipairs(result or {}) do
					local charID = tonumber(v.id)

					if (charID) then
						local data = {
							steamID = steamID64
						}

						ws.char.RestoreVars(data, v)

						characters[#characters + 1] = charID
						local character = ws.char.New(data, charID, client)

						hook.Run("CharacterRestored", character)
						character.vars.inv = {
							[1] = -1,
						}

						local invQuery = mysql:Select("ws_inventories")
							invQuery:Select("inventory_id")
							invQuery:Select("inventory_type")
							invQuery:Where("character_id", charID)
							invQuery:Callback(function(info)
								if (istable(info) and #info > 0) then
									local inventories = {}

									for _, v2 in pairs(info) do
										if (v2.inventory_type and isstring(v2.inventory_type) and v2.inventory_type == "NULL") then
											v2.inventory_type = nil
										end

										if (hook.Run("ShouldRestoreInventory", charID, v2.inventory_id, v2.inventory_type) != false) then
											local w, h = ws.config.Get("inventoryWidth"), ws.config.Get("inventoryHeight")
											local invType

											if (v2.inventory_type) then
												invType = ws.item.inventoryTypes[v2.inventory_type]

												if (invType) then
													w, h = invType.w, invType.h
												end
											end

											inventories[tonumber(v2.inventory_id)] = {w, h, v2.inventory_type}
										end
									end

									ws.inventory.Restore(inventories, nil, nil, function(inventory)
										local inventoryType = inventories[inventory:GetID()][3]

										if (inventoryType) then
											inventory.vars.isBag = inventoryType
											table.insert(character.vars.inv, inventory)
										else
											character.vars.inv[1] = inventory
										end

										inventory:SetOwner(charID)
									end, true)
								else
									local insertQuery = mysql:Insert("ws_inventories")
										insertQuery:Insert("character_id", charID)
										insertQuery:Callback(function(_, status, lastID)
											local w, h = ws.config.Get("inventoryWidth"), ws.config.Get("inventoryHeight")
											local inventory = ws.inventory.Create(w, h, lastID)
											inventory:SetOwner(charID)

											character.vars.inv = {
												inventory
											}
										end)
									insertQuery:Execute()
								end
							end)
						invQuery:Execute()

						ws.char.loaded[charID] = character
					else
						ErrorNoHalt("[Windswept] Attempt to load character with invalid ID '" .. tostring(id) .. "'!")
					end
				end

				if (callback) then
					callback(characters)
				end

				ws.char.cache[steamID64] = characters
			end)
		query:Execute()
	end

	--- Adds character properties to a table. This is done automatically by `ws.char.Restore`, so that should be used instead if
	-- you are loading characters.
	-- @realm server
	-- @internal
	-- @tab data Table of fields to apply to the table. If this is an SQL query object, it will instead populate the query with
	-- `SELECT` statements for each applicable character var in `ws.char.vars`.
	-- @tab characterInfo Table to apply the properties to. This can be left as `nil` if an SQL query object is passed in `data`
	function ws.char.RestoreVars(data, characterInfo)
		if (data.queryType) then
			-- populate query
			for _, v in pairs(ws.char.vars) do
				if (v.field and v.fieldType and !v.bSaveLoadInitialOnly) then
					data:Select(v.field)

					-- if FilterValues is used, any rows that contain a value in the column that isn't in the valid values table
					-- will be ignored entirely (i.e the character will not load if it has an invalid value)
					if (v.FilterValues) then
						data:WhereIn(v.field, v:FilterValues())
					end
				end
			end
		else
			-- populate character data
			for k, v in pairs(ws.char.vars) do
				if (v.field and characterInfo[v.field] and !v.bSaveLoadInitialOnly) then
					local value = characterInfo[v.field]

					if (isnumber(v.default)) then
						value = tonumber(value) or v.default
					elseif (isstring(v.default)) then
						value = tostring(value) == "NULL" and v.default or tostring(value or v.default)
					elseif (isbool(v.default)) then
						if (tostring(value) != "NULL") then
							value = tobool(value)
						else
							value = v.default
						end
					elseif (istable(v.default)) then
						value = istable(value) and value or util.JSONToTable(value) or v.default
					end

					data[k] = value
				end
			end
		end
	end
end

--- Creates a new empty `Character` object. If you are looking to create a usable character, see `ws.char.Create`.
-- @realm shared
-- @internal
-- @tab data Character vars to assign
-- @number id Unique ID of the character
-- @player client Player that will own the character
-- @string[opt=client:SteamID64()] steamID SteamID64 of the player that will own the character
function ws.char.New(data, id, client, steamID)
	if (data.name) then
		data.name = data.name:gsub("#", "#​")
	end

	if (data.description) then
		data.description = data.description:gsub("#", "#​")
	end

	local character = setmetatable({vars = {}}, ws.meta.character)
		for k, v in pairs(data) do
			if (v != nil) then
				character.vars[k] = v
			end
		end

		character.id = id or 0
		character.player = client

		if (SERVER and IsValid(client) or steamID) then
			character.steamID = IsValid(client) and client:SteamID64() or steamID
		end
	return character
end

ws.char.varHooks = ws.char.varHooks or {}
function ws.char.HookVar(varName, hookName, func)
	ws.char.varHooks[varName] = ws.char.varHooks[varName] or {}

	ws.char.varHooks[varName][hookName] = func
end

do
	--- Default character vars
	-- @classmod Character

	--- Sets this character's name. This is automatically networked.
	-- @realm server
	-- @string name New name for the character
	-- @function SetName

	--- Returns this character's name
	-- @realm shared
	-- @treturn string This character's current name
	-- @function GetName
	ws.char.RegisterVar("name", {
		field = "name",
		fieldType = ws.type.string,
		default = "John Doe",
		index = 1,
		OnValidate = function(self, value, payload, client)
			if (!value) then
				return false, "invalid", "name"
			end

			value = tostring(value):gsub("\r\n", ""):gsub("\n", "")
			value = string.Trim(value)

			local minLength = ws.config.Get("minNameLength", 4)
			local maxLength = ws.config.Get("maxNameLength", 32)

			if (value:utf8len() < minLength) then
				return false, "nameMinLen", minLength
			elseif (!value:find("%S")) then
				return false, "invalid", "name"
			elseif (value:gsub("%s", ""):utf8len() > maxLength) then
				return false, "nameMaxLen", maxLength
			end

			return hook.Run("GetDefaultCharacterName", client) or value:utf8sub(1, 70)
		end,
		OnPostSetup = function(self, panel, payload)
			local name, disabled = hook.Run("GetDefaultCharacterName", LocalPlayer())

			if (name) then
				panel:SetText(name)
				payload:Set("name", name)
			end

			if (disabled) then
				panel:SetDisabled(true)
				panel:SetEditable(false)
			end
		end
	})

	--- Sets this character's physical description. This is automatically networked.
	-- @realm server
	-- @string description New description for this character
	-- @function SetDescription

	--- Returns this character's physical description.
	-- @realm shared
	-- @treturn string This character's current description
	-- @function GetDescription
	ws.char.RegisterVar("description", {
		field = "description",
		fieldType = ws.type.text,
		default = "",
		index = 2,
		OnValidate = function(self, value, payload)
			value = string.Trim((tostring(value):gsub("\r\n", ""):gsub("\n", "")))
			local minLength = ws.config.Get("minDescriptionLength", 16)

			if (value:utf8len() < minLength) then
				return false, "descMinLen", minLength
			elseif (!value:find("%s+") or !value:find("%S")) then
				return false, "invalid", "description"
			end

			return value
		end,
		OnPostSetup = function(self, panel, payload)
			panel:SetMultiline(true)
			panel:SetFont("wsMenuButtonFont")
			panel:SetTall(panel:GetTall() * 2 + 6) -- add another line
			panel.AllowInput = function(_, character)
				if (character == "\n" or character == "\r") then
					return true
				end
			end
		end,
		alias = "Desc"
	})

	--- Sets this character's model. This sets the player's current model to the given one, and saves it to the character.
	-- It is automatically networked.
	-- @realm server
	-- @string model New model for the character
	-- @function SetModel

	--- Returns this character's model.
	-- @realm shared
	-- @treturn string This character's current model
	-- @function GetModel
	ws.char.RegisterVar("model", {
		field = "model",
		fieldType = ws.type.string,
		default = "models/error.mdl",
		index = 3,
		OnSet = function(character, value)
			local client = character:GetPlayer()

			if (IsValid(client) and client:GetCharacter() == character) then
				client:SetModel(value)
			end

			character.vars.model = value
		end,
		OnGet = function(character, default)
			return character.vars.model or default
		end,
		OnDisplay = function(self, container, payload)
			local scroll = container:Add("DScrollPanel")
			scroll:Dock(TOP)
			scroll:SetTall(140) -- Fixed height to allow other panels below
			scroll.Paint = function(panel, width, height)
				surface.SetDrawColor(derma.GetColor("DarkerBackground", panel))
				surface.DrawRect(0, 0, width, height)
			end

			local layout = scroll:Add("DIconLayout")
			layout:Dock(FILL)
			layout:SetSpaceX(1)
			layout:SetSpaceY(1)

			local models = ws.config.Get("defaultModels") or {}

			for k, v in SortedPairs(models) do
				local icon = layout:Add("SpawnIcon")
				icon:SetSize(64, 128)
				icon:InvalidateLayout(true)
				icon.DoClick = function(this)
					payload:Set("model", k)
				end
				icon.PaintOver = function(this, w, h)
					if (payload.model == k) then
						local color = ws.config.Get("color", color_white)

						surface.SetDrawColor(color.r, color.g, color.b, 200)

						for i = 1, 3 do
							local i2 = i * 2
							surface.DrawOutlinedRect(i, i, w - i2, h - i2)
						end
					end
				end

				if (isstring(v)) then
					icon:SetModel(v)
				else
					icon:SetModel(v[1], v[2] or 0, v[3])
				end
			end

			return scroll
		end,
		OnPostSetup = function(self, panel, payload)
			-- The faction step used to seed a default model; with factions removed, seed the
			-- first model here so the preview isn't left on models/error.mdl and the create
			-- button isn't blocked until the user picks one. (idempotent; defaultModels is an
			-- array, and index 1 is the first icon shown via SortedPairs.)
			if (payload.model) then return end

			local models = ws.config.Get("defaultModels") or {}

			if (models[1]) then
				payload:Set("model", 1)
			end
		end,
		OnValidate = function(self, value, payload, client)
			local models = ws.config.Get("defaultModels") or {}

			if (!payload.model or !models[payload.model]) then
				return false, "needModel"
			end
		end,
		OnAdjust = function(self, client, data, value, newData)
			local models = ws.config.Get("defaultModels") or {}

			local model = models[value]

			if (isstring(model)) then
				newData.model = model
			elseif (istable(model)) then
				newData.model = model[1]

				-- save skin/bodygroups to character data
				local bodygroups = {}

				for i = 1, #model[3] do
					bodygroups[i - 1] = tonumber(model[3][i]) or 0
				end

				newData.data = newData.data or {}
				newData.data.skin = model[2] or 0
				newData.data.groups = bodygroups
			end
		end,
		ShouldDisplay = function(self, container, payload)
			local models = ws.config.Get("defaultModels") or {}

			return models and #models > 1 or false
		end
	})

	-- attribute manipulation should be done with methods from the ws.attributes library
	ws.char.RegisterVar("attributes", {
		field = "attributes",
		fieldType = ws.type.text,
		default = {},
		index = 4,
		category = "attributes",
		isLocal = true,
		OnDisplay = function(self, container, payload)
			local maximum = hook.Run("GetDefaultAttributePoints", LocalPlayer(), payload) or 10

			if (maximum < 1) then
				return
			end

			local attributes = container:Add("DPanel")
			attributes:Dock(TOP)

			local y
			local total = 0

			payload.attributes = {}

			-- total spendable attribute points
			local totalBar = attributes:Add("wsAttributeBar")
			totalBar:SetMax(maximum)
			totalBar:SetValue(maximum)
			totalBar:Dock(TOP)
			totalBar:DockMargin(2, 2, 2, 2)
			totalBar:SetText(L("attribPointsLeft"))
			totalBar:SetReadOnly(true)
			totalBar:SetColor(Color(20, 120, 20, 255))

			y = totalBar:GetTall() + 4

			for k, v in SortedPairsByMemberValue(ws.attributes.list, "name") do
				payload.attributes[k] = 0

				local bar = attributes:Add("wsAttributeBar")
				bar:SetMax(v.maxValue or maximum)
				bar:Dock(TOP)
				bar:DockMargin(2, 2, 2, 2)
				bar:SetText(L(v.name))
				bar.OnChanged = function(this, difference)
					if ((total + difference) > maximum) then
						return false
					end

					total = total + difference
					payload.attributes[k] = payload.attributes[k] + difference

					totalBar:SetValue(totalBar.value - difference)
				end

				if (v.noStartBonus) then
					bar:SetReadOnly()
				end

				y = y + bar:GetTall() + 4
			end

			attributes:SetTall(y)
			return attributes
		end,
		OnValidate = function(self, value, data, client)
			if (value != nil) then
				if (!istable(value)) then
					return false, "unknownError"
				end

				local count = 0

				for key, v in pairs(value) do
					-- The creation payload is attacker-controlled and written directly into the
					-- persisted attributes table, so validate every entry: known attribute key,
					-- non-negative integer, within the attribute's own max. (fw-character-item-5)
					local attribute = ws.attributes.list[key]

					if (!attribute or !isnumber(v) or v < 0 or v != math.floor(v)) then
						return false, "unknownError"
					end

					if (attribute.maxValue and v > attribute.maxValue) then
						return false, "unknownError"
					end

					count = count + v
				end

				if (count > (hook.Run("GetDefaultAttributePoints", client, count) or 10)) then
					return false, "unknownError"
				end
			end
		end,
		ShouldDisplay = function(self, container, payload)
			return !table.IsEmpty(ws.attributes.list)
		end
	})

	--- Sets this character's current money. Money is only networked to the player that owns this character.
	-- @realm server
	-- @number money New amount of money this character should have
	-- @function SetMoney

	--- Returns this character's money. This is only valid on the server and the owning client.
	-- @realm shared
	-- @treturn number Current money of this character
	-- @function GetMoney
	ws.char.RegisterVar("money", {
		field = "money",
		fieldType = ws.type.number,
		default = 0,
		isLocal = true,
		bNoDisplay = true
	})

	--- Sets a data field on this character. This is useful for storing small bits of data that you need persisted on this
	-- character. This is networked only to the owning client. If you are going to be accessing this data field frequently with
	-- a getter/setter, consider using `ws.char.RegisterVar` instead.
	-- @realm server
	-- @string key Name of the field that holds the data
	-- @param value Any value to store in the field, as long as it's supported by GMod's JSON parser
	-- @function SetData

	--- Returns a data field set on this character. If it doesn't exist, it will return the given default or `nil`. This is only
	-- valid on the server and the owning client.
	-- @realm shared
	-- @string key Name of the field that's holding the data
	-- @param default Value to return if the given key doesn't exist, or is `nil`
	-- @return[1] Data stored in the field
	-- @treturn[2] nil If the data doesn't exist, or is `nil`
	-- @function GetData
	ws.char.RegisterVar("data", {
		default = {},
		isLocal = true,
		bNoDisplay = true,
		field = "data",
		fieldType = ws.type.text,
		OnSet = function(character, key, value, noReplication, receiver)
			local data = character:GetData()
			local client = character:GetPlayer()

			data[key] = value

			if (!noReplication and IsValid(client)) then
				net.Start("wsCharacterData")
					net.WriteUInt(character:GetID(), 32)
					net.WriteString(key)
					net.WriteType(value)
				net.Send(receiver or client)
			end

			character.vars.data = data
		end,
		OnGet = function(character, key, default)
			local data = character.vars.data or {}

			if (key) then
				if (!data) then
					return default
				end

				local value = data[key]

				return value == nil and default or value
			else
				return default or data
			end
		end
	})

	ws.char.RegisterVar("var", {
		default = {},
		bNoDisplay = true,
		OnSet = function(character, key, value, noReplication, receiver)
			local data = character:GetVar()
			local client = character:GetPlayer()

			data[key] = value

			if (!noReplication and IsValid(client)) then
				local id

				if (client:GetCharacter() and client:GetCharacter():GetID() == character:GetID()) then
					id = client:GetCharacter():GetID()
				else
					id = character:GetID()
				end

				net.Start("wsCharacterVar")
					net.WriteUInt(id, 32)
					net.WriteString(key)
					net.WriteType(value)
				net.Send(receiver or client)
			end

			character.vars.vars = data
		end,
		OnGet = function(character, key, default)
			character.vars.vars = character.vars.vars or {}
			local data = character.vars.vars or {}

			if (key) then
				if (!data) then
					return default
				end

				local value = data[key]

				return value == nil and default or value
			else
				return default or data
			end
		end
	})

	--- Returns the Unix timestamp of when this character was created (i.e the value of `os.time()` at the time of creation).
	-- @realm server
	-- @treturn number Unix timestamp of when this character was created
	-- @function GetCreateTime
	ws.char.RegisterVar("createTime", {
		field = "create_time",
		fieldType = ws.type.number,
		bNoDisplay = true,
		bNoNetworking = true,
		bNotModifiable = true
	})

	--- Returns the Unix timestamp of when this character was last used by its owning player.
	-- @realm server
	-- @treturn number Unix timestamp of when this character was last used
	-- @function GetLastJoinTime
	ws.char.RegisterVar("lastJoinTime", {
		field = "last_join_time",
		fieldType = ws.type.number,
		bNoDisplay = true,
		bNoNetworking = true,
		bNotModifiable = true,
		bSaveLoadInitialOnly = true
	})

	--- Returns the schema that this character belongs to. This is useful if you are running multiple schemas off of the same
	-- database, and need to differentiate between them.
	-- @realm server
	-- @treturn string Schema this character belongs to
	-- @function GetSchema
	ws.char.RegisterVar("schema", {
		field = "schema",
		fieldType = ws.type.string,
		bNoDisplay = true,
		bNoNetworking = true,
		bNotModifiable = true,
		bSaveLoadInitialOnly = true
	})

	--- Returns the 64-bit Steam ID of the player that owns this character.
	-- @realm server
	-- @treturn string Owning player's Steam ID
	-- @function GetSteamID
	ws.char.RegisterVar("steamID", {
		field = "steamid",
		fieldType = ws.type.steamid,
		bNoDisplay = true,
		bNoNetworking = true,
		bNotModifiable = true,
		bSaveLoadInitialOnly = true
	})
end

-- Networking information here.
do
	if (SERVER) then
		util.AddNetworkString("wsCharacterMenu")
		util.AddNetworkString("wsCharacterChoose")
		util.AddNetworkString("wsCharacterCreate")
		util.AddNetworkString("wsCharacterDelete")
		util.AddNetworkString("wsCharacterLoaded")
		util.AddNetworkString("wsCharacterLoadFailure")

		util.AddNetworkString("wsCharacterAuthed")
		util.AddNetworkString("wsCharacterAuthFailed")

		util.AddNetworkString("wsCharacterInfo")
		util.AddNetworkString("wsCharacterData")
		util.AddNetworkString("wsCharacterKick")
		util.AddNetworkString("wsCharacterSet")
		util.AddNetworkString("wsCharacterVar")
		util.AddNetworkString("wsCharacterVarChanged")

		net.Receive("wsCharacterChoose", function(length, client)
			local id = net.ReadUInt(32)

			if (client:GetCharacter() and client:GetCharacter():GetID() == id) then
				net.Start("wsCharacterLoadFailure")
					net.WriteString("@usingChar")
				net.Send(client)
				return
			end

			local character = ws.char.loaded[id]

			if (character and character:GetPlayer() == client) then
				local status, result = hook.Run("CanPlayerUseCharacter", client, character)

				if (status == false) then
					net.Start("wsCharacterLoadFailure")
						net.WriteString(result or "")
					net.Send(client)
					return
				end

				local currentChar = client:GetCharacter()

				if (currentChar) then
					currentChar:Save()

					for _, v in ipairs(currentChar:GetInventory(true)) do
						if (istable(v)) then
							v:RemoveReceiver(client)
						end
					end
				end

				hook.Run("PrePlayerLoadedCharacter", client, character, currentChar)
				character:Setup()
				client:Spawn()

				hook.Run("PlayerLoadedCharacter", client, character, currentChar)
			else
				net.Start("wsCharacterLoadFailure")
					net.WriteString("@unknownError")
				net.Send(client)

				ErrorNoHalt("[Windswept] Attempt to load invalid character '" .. id .. "'\n")
			end
		end)

		net.Receive("wsCharacterCreate", function(length, client)
			if ((client.wsNextCharacterCreate or 0) > RealTime()) then
				return
			end

			local maxChars = hook.Run("GetMaxPlayerCharacter", client) or ws.config.Get("maxCharacters", 5)
			local charList = client.wsCharList
			local charCount = table.Count(charList)

			if (charCount >= maxChars) then
				net.Start("wsCharacterAuthFailed")
					net.WriteString("maxCharacters")
					net.WriteTable({})
				net.Send(client)

				return
			end

			client.wsNextCharacterCreate = RealTime() + 1

			local indicies = net.ReadUInt(8)
			local payload = {}

			for _ = 1, indicies do
				payload[net.ReadString()] = net.ReadType()
			end

			local newPayload = {}
			local results = {hook.Run("CanPlayerCreateCharacter", client, payload)}

			if (table.remove(results, 1) == false) then
				net.Start("wsCharacterAuthFailed")
					net.WriteString(table.remove(results, 1) or "unknownError")
					net.WriteTable(results)
				net.Send(client)

				return
			end

			for k, _ in pairs(payload) do
				local info = ws.char.vars[k]

				-- Only let the client seed vars that are explicitly part of character
				-- creation: either a displayed (creation-menu) var, or one flagged
				-- bCreatable. Inferring editability from OnValidate+bNoDisplay let a
				-- client seed otherwise-hidden vars that happened to have an
				-- OnValidate. (fw-character-item-13)
				if (!info or (info.bNoDisplay and !info.bCreatable)) then
					payload[k] = nil
				end
			end

			for k, v in SortedPairsByMemberValue(ws.char.vars, "index") do
				local value = payload[k]

				if (v.OnValidate) then
					local result = {v:OnValidate(value, payload, client)}

					if (result[1] == false) then
						local fault = result[2]

						table.remove(result, 2)
						table.remove(result, 1)

						net.Start("wsCharacterAuthFailed")
							net.WriteString(fault)
							net.WriteTable(result)
						net.Send(client)

						return
					else
						if (result[1] != nil) then
							payload[k] = result[1]
						end

						if (v.OnAdjust) then
							v:OnAdjust(client, payload, value, newPayload)
						end
					end
				end
			end

			payload.steamID = client:SteamID64()
				hook.Run("AdjustCreationPayload", client, payload, newPayload)
			payload = table.Merge(payload, newPayload)

			ws.char.Create(payload, function(id)
				if (IsValid(client)) then
					ws.char.loaded[id]:Sync(client)

					net.Start("wsCharacterAuthed")
					net.WriteUInt(id, 32)
					net.WriteUInt(#client.wsCharList, 6)

					for _, v in ipairs(client.wsCharList) do
						net.WriteUInt(v, 32)
					end

					net.Send(client)

					MsgN("Created character '" .. id .. "' for " .. client:SteamName() .. ".")
					hook.Run("OnCharacterCreated", client, ws.char.loaded[id])
				end
			end)
		end)

		net.Receive("wsCharacterDelete", function(length, client)
			local id = net.ReadUInt(32)
			local character = ws.char.loaded[id]
			local steamID = client:SteamID64()
			local isCurrentChar = client:GetCharacter() and client:GetCharacter():GetID() == id

			if (character and character.steamID == steamID) then
				for k, v in ipairs(client.wsCharList or {}) do
					if (v == id) then
						table.remove(client.wsCharList, k)
					end
				end

				hook.Run("PreCharacterDeleted", client, character)
				ws.char.loaded[id] = nil

				net.Start("wsCharacterDelete")
					net.WriteUInt(id, 32)
				net.Broadcast()

				-- remove character from database
				local query = mysql:Delete("ws_characters")
					query:Where("id", id)
					query:Where("steamid", client:SteamID64())
				query:Execute()

				-- DBTODO: setup relations instead
				-- remove inventory from database
				query = mysql:Select("ws_inventories")
					query:Select("inventory_id")
					query:Where("character_id", id)
					query:Callback(function(result)
						if (istable(result)) then
							-- remove associated items from database
							for _, v in ipairs(result) do
								local itemQuery = mysql:Delete("ws_items")
									itemQuery:Where("inventory_id", v.inventory_id)
								itemQuery:Execute()

								ws.item.inventories[tonumber(v.inventory_id)] = nil
							end
						end

						local invQuery = mysql:Delete("ws_inventories")
							invQuery:Where("character_id", id)
						invQuery:Execute()
					end)
				query:Execute()

				-- other plugins might need to deal with deleted characters.
				hook.Run("CharacterDeleted", client, id, isCurrentChar)

				if (isCurrentChar) then
					client:SetNetVar("char", nil)
					client:KillSilent()
					client:StripAmmo()
				end
			end
		end)
	else
		net.Receive("wsCharacterInfo", function()
			local data = net.ReadTable()
			local id = net.ReadUInt(32)
			local client = net.ReadUInt(8)

			ws.char.loaded[id] = ws.char.New(data, id, client)
		end)

		net.Receive("wsCharacterVarChanged", function()
			local id = net.ReadUInt(32)
			local character = ws.char.loaded[id]

			if (character) then
				local key = net.ReadString()
				local value = net.ReadType()

				character.vars[key] = value
			end
		end)

		-- Used for setting random access vars on the "var" character var (really stupid).
		-- Clean this up someday.
		net.Receive("wsCharacterVar", function()
			local id = net.ReadUInt(32)
			local character = ws.char.loaded[id]

			if (character) then
				local key = net.ReadString()
				local value = net.ReadType()
				local oldVar = character:GetVar()[key]
				character:GetVar()[key] = value

				hook.Run("CharacterVarChanged", character, key, oldVar, value)
			end
		end)

		net.Receive("wsCharacterMenu", function()
			local indices = net.ReadUInt(6)
			local charList = {}

			for _ = 1, indices do
				charList[#charList + 1] = net.ReadUInt(32)
			end

			if (charList) then
				ws.characters = charList
			end

			vgui.Create("wsCharMenu")
		end)

		net.Receive("wsCharacterLoadFailure", function()
			local message = net.ReadString()

			if (isstring(message) and message:sub(1, 1) == "@") then
				message = L(message:sub(2))
			end

			message = message != "" and message or L("unknownError")

			if (IsValid(ws.gui.characterMenu)) then
				ws.gui.characterMenu:OnCharacterLoadFailed(message)
			else
				ws.util.Notify(message)
			end
		end)

		net.Receive("wsCharacterData", function()
			local id = net.ReadUInt(32)
			local key = net.ReadString()
			local value = net.ReadType()
			local character = ws.char.loaded[id]

			if (character) then
				character.vars.data = character.vars.data or {}
				character:GetData()[key] = value
			end
		end)

		net.Receive("wsCharacterDelete", function()
			local id = net.ReadUInt(32)
			local isCurrentChar = LocalPlayer():GetCharacter() and LocalPlayer():GetCharacter():GetID() == id
			local character = ws.char.loaded[id]

			ws.char.loaded[id] = nil

			for k, v in ipairs(ws.characters) do
				if (v == id) then
					table.remove(ws.characters, k)

					if (IsValid(ws.gui.characterMenu)) then
						ws.gui.characterMenu:OnCharacterDeleted(character)
					end
				end
			end

			if (isCurrentChar and !IsValid(ws.gui.characterMenu)) then
				vgui.Create("wsCharMenu")
			end
		end)

		net.Receive("wsCharacterKick", function()
			local isCurrentChar = net.ReadBool()

			if (ws.gui.menu and ws.gui.menu:IsVisible()) then
				ws.gui.menu:Remove()
			end

			if (!IsValid(ws.gui.characterMenu)) then
				vgui.Create("wsCharMenu")
			elseif (ws.gui.characterMenu:IsClosing()) then
				ws.gui.characterMenu:Remove()
				vgui.Create("wsCharMenu")
			end

			if (isCurrentChar) then
				ws.gui.characterMenu.mainPanel:UpdateReturnButton(false)
			end
		end)

		net.Receive("wsCharacterLoaded", function()
			hook.Run("CharacterLoaded", ws.char.loaded[net.ReadUInt(32)])
		end)
	end
end

do
	--- Character util functions for player
	-- @classmod Player

	local playerMeta = FindMetaTable("Player")
	playerMeta.SteamName = playerMeta.SteamName or playerMeta.Name

	--- Returns this player's currently possessed `Character` object if it exists.
	-- @realm shared
	-- @treturn[1] Character Currently loaded character
	-- @treturn[2] nil If this player has no character loaded
	function playerMeta:GetCharacter()
		return ws.char.loaded[self:GetNetVar("char")]
	end

	playerMeta.GetChar = playerMeta.GetCharacter

	--- Returns this player's current name.
	-- @realm shared
	-- @treturn[1] string Name of this player's currently loaded character
	-- @treturn[2] string Steam name of this player if the player has no character loaded
	function playerMeta:GetName()
		local character = self:GetCharacter()

		return character and character:GetName() or self:SteamName()
	end

	playerMeta.Nick = playerMeta.GetName
	playerMeta.Name = playerMeta.GetName
end
