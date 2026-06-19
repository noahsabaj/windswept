
--[[--
Multi-language phrase support.

Helix has support for multiple languages, and you can easily leverage this system for use in your own schema, plugins, etc.
Languages will be loaded from the schema and any plugins in `languages/sh_languagename.lua`, where `languagename` is the id of a
language (`english` for English, `french` for French, etc). The structure of a language file is a table of phrases with the key
as its phrase ID and the value as its translation for that language. For example, in `plugins/area/languages/sh_english.lua`:
	LANGUAGE = {
		area = "Area",
		areas = "Areas",
		areaEditMode = "Area Edit Mode",
		-- etc.
	}

The phrases defined in these language files can be used with the `L` global function:
	print(L("areaEditMode"))
	> Area Edit Mode

All phrases are formatted with `string.format`, so if you wish to add some info in a phrase you can use standard Lua string
formatting arguments:
	print(L("areaDeleteConfirm", "Test"))
	> Are you sure you want to delete the area "Test"?

Phrases are also usable on the server, but only when trying to localize a phrase based on a client's preferences. The server
does not have a set language. An example:
	Entity(1):ChatPrint(L("areaEditMode"))
	> -- "Area Edit Mode" will print in the player's chatbox
]]
-- @module ws.lang

ws.lang = ws.lang or {}
ws.lang.stored = ws.lang.stored or {}
ws.lang.names = ws.lang.names or {}

--- Loads language files from a directory.
-- @realm shared
-- @internal
-- @string directory Directory to load language files from
function ws.lang.LoadFromDir(directory)
	for _, v in ipairs(file.Find(directory.."/sh_*.lua", "LUA")) do
		local niceName = v:sub(4, -5):lower()

		ws.util.Include(directory.."/"..v, "shared")

		if (LANGUAGE) then
			if (NAME) then
				ws.lang.names[niceName] = NAME
				NAME = nil
			end

			ws.lang.AddTable(niceName, LANGUAGE)
			LANGUAGE = nil
		end
	end
end

--- Adds phrases to a language. This is used when you aren't adding entries through the files in the `languages/` folder. A
-- common use case is adding language phrases in a single-file plugin.
-- @realm shared
-- @string language The ID of the language
-- @tab data Language data to add to the given language
-- @usage ws.lang.AddTable("english", {
-- 	myPhrase = "My Phrase"
-- })
function ws.lang.AddTable(language, data)
	language = tostring(language):lower()
	ws.lang.stored[language] = table.Merge(ws.lang.stored[language] or {}, data)
end

if (SERVER) then
	-- luacheck: globals L
	function L(key, client, ...)
		local languages = ws.lang.stored
		local langKey = ws.option.Get(client, "language", "english")
		local info = languages[langKey] or languages.english

		return string.format(info and info[key] or languages.english[key] or key, ...)
	end

	-- luacheck: globals L2
	function L2(key, client, ...)
		local languages = ws.lang.stored
		local langKey = ws.option.Get(client, "language", "english")
		local info = languages[langKey] or languages.english

		if (info and info[key]) then
			return string.format(info[key], ...)
		end
	end
else
	function L(key, ...)
		local languages = ws.lang.stored
		local langKey = ws.option.Get("language", "english")
		local info = languages[langKey] or languages.english

		return string.format(info and info[key] or languages.english[key] or key, ...)
	end

	function L2(key, ...)
		local langKey = ws.option.Get("language", "english")
		local info = ws.lang.stored[langKey]

		if (info and info[key]) then
			return string.format(info[key], ...)
		end
	end
end
