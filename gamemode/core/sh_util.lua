
--- Various useful helper functions.
-- @module ws.util

ws.type = ws.type or {
	[2] = "string",
	[4] = "text",
	[8] = "number",
	[16] = "player",
	[32] = "steamid",
	[64] = "character",
	[128] = "bool",
	[1024] = "color",
	[2048] = "vector",

	string = 2,
	text = 4,
	number = 8,
	player = 16,
	steamid = 32,
	character = 64,
	bool = 128,
	color = 1024,
	vector = 2048,

	optional = 256,
	array = 512
}

ws.blurRenderQueue = {}

-- Resolve the framework's own gamemode folder once, read from the path of this running
-- file. The framework folder is always whatever name the schema passes to
-- DeriveGamemode() ("windswept") -- GMod runs the derived base from gamemodes/<that>/ --
-- so we read it from the path rather than hardcoding it, and fall back to "windswept" if
-- the path can't be parsed. Note: engine.ActiveGamemode() returns the SCHEMA
-- (e.g. "windsweptrp"), not the framework, so it can't be used here.
if (!ws.FRAMEWORK_FOLDER) then
	local source = debug.getinfo(1, "S").source or ""
	ws.FRAMEWORK_FOLDER = source:match("gamemodes/([^/]+)/") or "windswept"
end

--- Includes a lua file based on the prefix of the file. This will automatically call `include` and `AddCSLuaFile` based on the
-- current realm. This function should always be called shared to ensure that the client will receive the file from the server.
-- @realm shared
-- @string fileName Path of the Lua file to include. The path is relative to the file that is currently running this function
-- @string[opt] realm Realm that this file should be included in. You should usually ignore this since it
-- will be automatically be chosen based on the `SERVER` and `CLIENT` globals. This value should either be `"server"` or
-- `"client"` if it is filled in manually
function ws.util.Include(fileName, realm)
	if (!fileName) then
		error("[Windswept] No file name specified for including.")
	end

	-- Only include server-side if we're on the server.
	if ((realm == "server" or fileName:find("sv_")) and SERVER) then
		return include(fileName)
	-- Shared is included by both server and client.
	elseif (realm == "shared" or fileName:find("shared.lua") or fileName:find("sh_")) then
		if (SERVER) then
			-- Send the file to the client if shared so they can run it.
			AddCSLuaFile(fileName)
		end

		return include(fileName)
	-- File is sent to client, included on client.
	elseif (realm == "client" or fileName:find("cl_")) then
		if (SERVER) then
			AddCSLuaFile(fileName)
		else
			return include(fileName)
		end
	end
end

--- Includes multiple files in a directory.
-- @realm shared
-- @string directory Directory to include files from
-- @bool[opt] bFromLua Whether or not to search from the base `lua/` folder, instead of contextually basing from `schema/`
-- or `gamemode/`
-- @see ws.util.Include
function ws.util.IncludeDir(directory, bFromLua)
	-- By default, we include relative to the framework's own gamemode folder
	-- (resolved dynamically above: "windswept" local / "windswept" live, never hardcoded).
	local baseDir = ws.FRAMEWORK_FOLDER

	-- If we're in a schema, include relative to the schema.
	if (Schema and Schema.folder and Schema.loading) then
		baseDir = Schema.folder.."/schema/"
	else
		baseDir = baseDir.."/gamemode/"
	end

	-- Find all of the files within the directory.
	for _, v in ipairs(file.Find((bFromLua and "" or baseDir)..directory.."/*.lua", "LUA")) do
		-- Include the file from the prefix.
		ws.util.Include(directory.."/"..v)
	end
end

--- Removes the realm prefix from a file name. The returned string will be unchanged if there is no prefix found.
-- @realm shared
-- @string name String to strip prefix from
-- @treturn string String stripped of prefix
-- @usage print(ws.util.StripRealmPrefix("sv_init.lua"))
-- > init.lua
function ws.util.StripRealmPrefix(name)
	local prefix = name:sub(1, 3)

	return (prefix == "sh_" or prefix == "sv_" or prefix == "cl_") and name:sub(4) or name
end


-- Standalone ws.util.* helpers split out for readability (PR-3). They load right
-- after the file-inclusion bootstrap above, so every helper is defined before
-- shared.lua and the core sweep run. Pure relocation; the public API is unchanged.
ws.util.Include("util/sh_util_value.lua")   -- color/type/string/player/value helpers
ws.util.Include("util/sh_util_render.lua")  -- client render/blur/3D2D helpers
ws.util.Include("util/sh_util_world.lua")   -- entity/world/space/sound helpers

ws.util.Include(ws.FRAMEWORK_FOLDER.."/gamemode/core/meta/sh_entity.lua")
ws.util.Include(ws.FRAMEWORK_FOLDER.."/gamemode/core/meta/sh_player.lua")
