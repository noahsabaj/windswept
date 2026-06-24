
ws.db = ws.db or {
	schema = {},
	schemaQueue = {},
	type = {
		-- TODO: more specific types, lengths, and defaults
		-- i.e INT(11) UNSIGNED, SMALLINT(4), LONGTEXT, VARCHAR(350), NOT NULL, DEFAULT NULL, etc
		[ws.type.string] = "VARCHAR(255)",
		[ws.type.text] = "TEXT",
		[ws.type.number] = "INT(11)",
		[ws.type.steamid] = "VARCHAR(20)",
		[ws.type.bool] = "TINYINT(1)"
	}
}

ws.db.config = ws.config.server.database or {}

function ws.db.Connect()
	ws.db.config.adapter = ws.db.config.adapter or "sqlite"

	local dbmodule = ws.db.config.adapter
	local hostname = ws.db.config.hostname
	local username = ws.db.config.username
	local password = ws.db.config.password
	local database = ws.db.config.database
	local port = ws.db.config.port

	mysql:SetModule(dbmodule)
	mysql:Connect(hostname, username, password, database, port)
end

function ws.db.AddToSchema(schemaType, field, fieldType)
	if (!ws.db.type[fieldType]) then
		error(string.format("attempted to add field in schema with invalid type '%s'", fieldType))
		return
	end

	if (!mysql:IsConnected() or !ws.db.schema[schemaType]) then
		ws.db.schemaQueue[#ws.db.schemaQueue + 1] = {schemaType, field, fieldType}
		return
	end

	ws.db.InsertSchema(schemaType, field, fieldType)
end

-- this is only ever used internally
function ws.db.InsertSchema(schemaType, field, fieldType)
	local schema = ws.db.schema[schemaType]

	if (!schema) then
		error(string.format("attempted to insert into schema with invalid schema type '%s'", schemaType))
		return
	end

	if (!schema[field]) then
		schema[field] = true

		-- Ensure a ws_schema row exists for this schemaType so the columns UPDATE
		-- below actually lands (a missing row would silently no-op). (fw-persistence-db-5)
		local query = mysql:InsertIgnore("ws_schema")
			query:Insert("table", schemaType)
			query:Insert("columns", util.TableToJSON({}))
		query:Execute()

		query = mysql:Update("ws_schema")
			query:Update("columns", util.TableToJSON(schema))
			query:Where("table", schemaType)
		query:Execute()

		query = mysql:Alter(schemaType)
			query:Add(field, ws.db.type[fieldType])
		query:Execute()
	end
end

function ws.db.LoadTables()
	local query

	query = mysql:Create("ws_schema")
		query:Create("table", "VARCHAR(64) NOT NULL")
		query:Create("columns", "TEXT NOT NULL")
		query:PrimaryKey("table")
	query:Execute()

	-- table structure will be populated with more fields when vars
	-- are registered using ws.char.RegisterVar
	query = mysql:Create("ws_characters")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:PrimaryKey("id")
	query:Execute()

	query = mysql:Create("ws_inventories")
		query:Create("inventory_id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("character_id", "INT(11) UNSIGNED NOT NULL")
		query:Create("inventory_type", "VARCHAR(150) DEFAULT NULL")
		query:PrimaryKey("inventory_id")
	query:Execute()

	query = mysql:Create("ws_items")
		query:Create("item_id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("inventory_id", "INT(11) UNSIGNED NOT NULL")
		query:Create("unique_id", "VARCHAR(60) NOT NULL")
		query:Create("character_id", "INT(11) UNSIGNED DEFAULT NULL")
		query:Create("player_id", "VARCHAR(20) DEFAULT NULL")
		query:Create("data", "TEXT DEFAULT NULL")
		query:Create("x", "SMALLINT(4) NOT NULL")
		query:Create("y", "SMALLINT(4) NOT NULL")
		query:PrimaryKey("item_id")
	query:Execute()

	query = mysql:Create("ws_players")
		query:Create("steamid", "VARCHAR(20) NOT NULL")
		query:Create("steam_name", "VARCHAR(32) NOT NULL")
		query:Create("play_time", "INT(11) UNSIGNED DEFAULT NULL")
		query:Create("address", "VARCHAR(15) DEFAULT NULL")
		query:Create("last_join_time", "INT(11) UNSIGNED DEFAULT NULL")
		query:Create("data", "TEXT")
		query:PrimaryKey("steamid")
	query:Execute()

	-- populate schema table if rows don't exist
	query = mysql:InsertIgnore("ws_schema")
		query:Insert("table", "ws_characters")
		query:Insert("columns", util.TableToJSON({}))
	query:Execute()

	-- load schema from database
	query = mysql:Select("ws_schema")
		query:Callback(function(result)
			if (!istable(result)) then
				return
			end

			for _, v in pairs(result) do
				ws.db.schema[v.table] = util.JSONToTable(v.columns)
			end

			-- update schema if needed, then clear the queue so a second drain
			-- (e.g. a reconnect) can't replay these entries. (fw-persistence-db-5)
			for i = 1, #ws.db.schemaQueue do
				local entry = ws.db.schemaQueue[i]
				ws.db.InsertSchema(entry[1], entry[2], entry[3])
			end

			ws.db.schemaQueue = {}
		end)
	query:Execute()
end

function ws.db.WipeTables(callback)
	local query

	query = mysql:Drop("ws_schema")
	query:Execute()

	query = mysql:Drop("ws_characters")
	query:Execute()

	query = mysql:Drop("ws_inventories")
	query:Execute()

	query = mysql:Drop("ws_items")
	query:Execute()

	query = mysql:Drop("ws_players")
		query:Callback(callback)
	query:Execute()
end

hook.Add("InitPostEntity", "wsDatabaseConnect", function()
	-- Connect to the database using SQLite, mysqoo, or tmysql4.
	ws.db.Connect()
end)

-- Confirm token for ws_wipedb. Tying the second invocation to a one-shot nonce
-- (instead of a shared time window) removes the re-arm race where an unrelated or
-- automated double-invocation could trip the wipe. (fw-persistence-db-9)
local wipeToken = nil
local wipeTokenExpires = 0

concommand.Add("ws_wipedb", function(client, cmd, arguments)
	-- can only be ran through the server's console
	if (IsValid(client)) then return end

	local provided = arguments and arguments[1]

	if (wipeToken and provided == wipeToken and RealTime() < wipeTokenExpires) then
		wipeToken = nil
		wipeTokenExpires = 0

		MsgC(Color(255, 0, 0), "[Windswept] DATABASE WIPE IN PROGRESS...\n")

		hook.Run("OnWipeTables")
		ws.db.WipeTables(function()
			MsgC(Color(255, 255, 0), "[Windswept] DATABASE WIPE COMPLETED!\n")
			RunConsoleCommand("changelevel", game.GetMap())
		end)
	else
		wipeToken = tostring(math.random(100000, 999999))
		wipeTokenExpires = RealTime() + 30

		MsgC(Color(255, 0, 0),
			"[Windswept] WIPING THE DATABASE WILL PERMENANTLY REMOVE ALL PLAYER, CHARACTER, ITEM, AND INVENTORY DATA.\n")
		MsgC(Color(255, 0, 0), "[Windswept] THE SERVER WILL RESTART TO APPLY THESE CHANGES WHEN COMPLETED.\n")
		MsgC(Color(255, 0, 0), string.format(
			"[Windswept] TO CONFIRM DATABASE RESET, RUN 'ws_wipedb %s' WITHIN 30 SECONDS.\n", wipeToken))
	end
end)
