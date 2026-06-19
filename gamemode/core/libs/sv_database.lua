
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

		local query = mysql:Update("ix_schema")
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

	query = mysql:Create("ix_schema")
		query:Create("table", "VARCHAR(64) NOT NULL")
		query:Create("columns", "TEXT NOT NULL")
		query:PrimaryKey("table")
	query:Execute()

	-- table structure will be populated with more fields when vars
	-- are registered using ws.char.RegisterVar
	query = mysql:Create("ix_characters")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:PrimaryKey("id")
	query:Execute()

	query = mysql:Create("ix_inventories")
		query:Create("inventory_id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("character_id", "INT(11) UNSIGNED NOT NULL")
		query:Create("inventory_type", "VARCHAR(150) DEFAULT NULL")
		query:PrimaryKey("inventory_id")
	query:Execute()

	query = mysql:Create("ix_items")
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

	query = mysql:Create("ix_players")
		query:Create("steamid", "VARCHAR(20) NOT NULL")
		query:Create("steam_name", "VARCHAR(32) NOT NULL")
		query:Create("play_time", "INT(11) UNSIGNED DEFAULT NULL")
		query:Create("address", "VARCHAR(15) DEFAULT NULL")
		query:Create("last_join_time", "INT(11) UNSIGNED DEFAULT NULL")
		query:Create("data", "TEXT")
		query:PrimaryKey("steamid")
	query:Execute()

	-- Faction governance tables
	query = mysql:Create("ix_faction_classes")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("faction", "VARCHAR(64) NOT NULL")
		query:Create("unique_id", "VARCHAR(64) NOT NULL")
		query:Create("name", "VARCHAR(64) NOT NULL")
		query:Create("description", "TEXT")
		query:Create("rank", "TINYINT UNSIGNED NOT NULL DEFAULT 1")
		query:Create("pay", "INT(11) NOT NULL DEFAULT 0")
		query:Create("class_limit", "INT(11) NOT NULL DEFAULT 0")
		query:Create("permissions", "TEXT")
		query:Create("is_anchor", "TINYINT(1) NOT NULL DEFAULT 0")
		query:Create("is_default", "TINYINT(1) NOT NULL DEFAULT 0")
		query:Create("created_by", "INT(11) UNSIGNED")
		query:Create("created_at", "INT(11) NOT NULL")
		query:Create("updated_at", "INT(11) NOT NULL")
		query:PrimaryKey("id")
	query:Execute()

	query = mysql:Create("ix_faction_votes")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("faction", "VARCHAR(64) NOT NULL")
		query:Create("vote_type", "VARCHAR(32) NOT NULL")
		query:Create("status", "VARCHAR(16) NOT NULL DEFAULT 'active'")
		query:Create("started_at", "INT(11) NOT NULL")
		query:Create("ends_at", "INT(11) NOT NULL")
		query:Create("candidates", "TEXT NOT NULL")
		query:Create("results", "TEXT")
		query:Create("winner_char_id", "INT(11) UNSIGNED")
		query:Create("departing_char_id", "INT(11) UNSIGNED")
		query:PrimaryKey("id")
	query:Execute()

	query = mysql:Create("ix_faction_ballots")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("vote_id", "INT(11) UNSIGNED NOT NULL")
		query:Create("char_id", "INT(11) UNSIGNED NOT NULL")
		query:Create("approvals", "TEXT NOT NULL")
		query:Create("cast_at", "INT(11) NOT NULL")
		query:PrimaryKey("id")
	query:Execute()

	query = mysql:Create("ix_faction_config")
		query:Create("faction", "VARCHAR(64) NOT NULL")
		query:Create("subordinate_of", "VARCHAR(64)")
		query:Create("anchor_class_id", "INT(11) UNSIGNED")
		query:Create("default_class_name", "VARCHAR(64) NOT NULL DEFAULT 'Unassigned'")
		query:Create("updated_at", "INT(11) NOT NULL")
		query:PrimaryKey("faction")
	query:Execute()

	-- populate schema table if rows don't exist
	query = mysql:InsertIgnore("ix_schema")
		query:Insert("table", "ix_characters")
		query:Insert("columns", util.TableToJSON({}))
	query:Execute()

	-- load schema from database
	query = mysql:Select("ix_schema")
		query:Callback(function(result)
			if (!istable(result)) then
				return
			end

			for _, v in pairs(result) do
				ws.db.schema[v.table] = util.JSONToTable(v.columns)
			end

			-- update schema if needed
			for i = 1, #ws.db.schemaQueue do
				local entry = ws.db.schemaQueue[i]
				ws.db.InsertSchema(entry[1], entry[2], entry[3])
			end
		end)
	query:Execute()
end

function ws.db.WipeTables(callback)
	local query

	query = mysql:Drop("ix_schema")
	query:Execute()

	query = mysql:Drop("ix_characters")
	query:Execute()

	query = mysql:Drop("ix_inventories")
	query:Execute()

	query = mysql:Drop("ix_items")
	query:Execute()

	query = mysql:Drop("ix_players")
		query:Callback(callback)
	query:Execute()
end

hook.Add("InitPostEntity", "wsDatabaseConnect", function()
	-- Connect to the database using SQLite, mysqoo, or tmysql4.
	ws.db.Connect()
end)

local resetCalled = 0

concommand.Add("ix_wipedb", function(client, cmd, arguments)
	-- can only be ran through the server's console
	if (!IsValid(client)) then
		if (resetCalled < RealTime()) then
			resetCalled = RealTime() + 3

			MsgC(Color(255, 0, 0),
				"[Helix] WIPING THE DATABASE WILL PERMENANTLY REMOVE ALL PLAYER, CHARACTER, ITEM, AND INVENTORY DATA.\n")
			MsgC(Color(255, 0, 0), "[Helix] THE SERVER WILL RESTART TO APPLY THESE CHANGES WHEN COMPLETED.\n")
			MsgC(Color(255, 0, 0), "[Helix] TO CONFIRM DATABASE RESET, RUN 'ix_wipedb' AGAIN WITHIN 3 SECONDS.\n")
		else
			resetCalled = 0
			MsgC(Color(255, 0, 0), "[Helix] DATABASE WIPE IN PROGRESS...\n")

			hook.Run("OnWipeTables")
			ws.db.WipeTables(function()
				MsgC(Color(255, 255, 0), "[Helix] DATABASE WIPE COMPLETED!\n")
				RunConsoleCommand("changelevel", game.GetMap())
			end)
		end
	end
end)
