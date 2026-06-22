--- Value/format helpers: color checks, type sanitization, player lookup, string
-- matching, named-format strings, grid snapping.
--
-- Split out of core/sh_util.lua for readability (PR-3); pure relocation, the public
-- ws.util.* API is unchanged. Loaded by sh_util.lua after its file-inclusion bootstrap.
-- @module ws.util

--- Returns `true` if the given input is a color table. This is necessary since the engine `IsColor` function only checks for
-- color metatables - which are not used for regular Lua color types.
-- @realm shared
-- @param input Input to check
-- @treturn bool Whether or not the input is a color
function ws.util.IsColor(input)
	return istable(input) and
		isnumber(input.a) and isnumber(input.g) and isnumber(input.b) and (input.a and isnumber(input.a) or input.a == nil)
end

--- Returns a dimmed version of the given color by the given scale.
-- @realm shared
-- @color color Color to dim
-- @number multiplier What to multiply the red, green, and blue values by
-- @number[opt=255] alpha Alpha to use in dimmed color
-- @treturn color Dimmed color
-- @usage print(ws.util.DimColor(Color(100, 100, 100, 255), 0.5))
-- > 50 50 50 255
function ws.util.DimColor(color, multiplier, alpha)
	return Color(color.r * multiplier, color.g * multiplier, color.b * multiplier, alpha or 255)
end

--- Sanitizes an input value with the given type. This function ensures that a valid type is always returned. If a valid value
-- could not be found, it will return the default value for the type. This only works for simple types - e.g it does not work
-- for player, character, or Steam ID types.
-- @realm shared
-- @wstype type Type to check for
-- @param input Value to sanitize
-- @return Sanitized value
-- @see ws.type
-- @usage print(ws.util.SanitizeType(ws.type.number, "123"))
-- > 123
-- print(ws.util.SanitizeType(ws.type.bool, 1))
-- > true
function ws.util.SanitizeType(type, input)
	if (type == ws.type.string) then
		return tostring(input)
	elseif (type == ws.type.text) then
		return tostring(input)
	elseif (type == ws.type.number) then
		return tonumber(input or 0) or 0
	elseif (type == ws.type.bool) then
		return tobool(input)
	elseif (type == ws.type.color) then
		return istable(input) and
			Color(tonumber(input.r) or 255, tonumber(input.g) or 255, tonumber(input.b) or 255, tonumber(input.a) or 255) or
			color_white
	elseif (type == ws.type.vector) then
		return isvector(input) and input or vector_origin
	elseif (type == ws.type.array) then
		return input
	else
		error("attempted to sanitize " .. (ws.type[type] and ("invalid type " .. ws.type[type]) or "unknown type " .. type))
	end
end

do
	local typeMap = {
		string = ws.type.string,
		number = ws.type.number,
		Player = ws.type.player,
		boolean = ws.type.bool,
		Vector = ws.type.vector
	}

	local tableMap = {
		[ws.type.character] = function(value)
			return getmetatable(value) == ws.meta.character
		end,

		[ws.type.color] = function(value)
			return ws.util.IsColor(value)
		end,

		[ws.type.steamid] = function(value)
			return isstring(value) and (value:match("STEAM_(%d+):(%d+):(%d+)")) != nil
		end
	}

	--- Returns the `ws.type` of the given value.
	-- @realm shared
	-- @param value Value to get the type of
	-- @treturn ws.type Type of value
	-- @see ws.type
	-- @usage print(ws.util.GetTypeFromValue("hello"))
	-- > 2 -- i.e the value of ws.type.string
	function ws.util.GetTypeFromValue(value)
		local result = typeMap[type(value)]

		if (result) then
			return result
		end

		if (istable(value)) then
			for k, v in pairs(tableMap) do
				if (v(value)) then
					return k
				end
			end
		end
	end
end

function ws.util.Bind(self, callback)
	return function(_, ...)
		return callback(self, ...)
	end
end

-- Returns the address:port of the server.
function ws.util.GetAddress()
	return game.GetIPAddress()
end

--- Returns a cached copy of the given material, or creates and caches one if it doesn't exist. This is a quick helper function
-- if you aren't locally storing a `Material()` call.
-- @realm shared
-- @string materialPath Path to the material
-- @treturn[1] material The cached material
-- @treturn[2] nil If the material doesn't exist in the filesystem
function ws.util.GetMaterial(materialPath)
	-- Cache the material.
	ws.util.cachedMaterials = ws.util.cachedMaterials or {}
	ws.util.cachedMaterials[materialPath] = ws.util.cachedMaterials[materialPath] or Material(materialPath)

	return ws.util.cachedMaterials[materialPath]
end

--- Attempts to find a player by matching their name or Steam ID.
-- @realm shared
-- @string identifier Search query
-- @bool[opt=false] bAllowPatterns Whether or not to accept Lua patterns in `identifier`
-- @treturn player Player that matches the given search query - this will be `nil` if a player could not be found
function ws.util.FindPlayer(identifier, bAllowPatterns)
	if (#identifier == 0) then return end

	if (string.find(identifier, "STEAM_(%d+):(%d+):(%d+)")) then
		return player.GetBySteamID(identifier)
	end

	if (!bAllowPatterns) then
		identifier = string.PatternSafe(identifier)
	end

	for _, v in player.Iterator() do
		if (ws.util.StringMatches(v:Name(), identifier)) then
			return v
		end
	end
end

--- Checks to see if two strings are equivalent using a fuzzy manner. Both strings will be lowered, and will return `true` if
-- the strings are identical, or if `b` is a substring of `a`.
-- @realm shared
-- @string a First string to check
-- @string b Second string to check
-- @treturn bool Whether or not the strings are equivalent
function ws.util.StringMatches(a, b)
	if (a and b) then
		local a2, b2 = a:utf8lower(), b:utf8lower()

		-- Check if the actual letters match.
		if (a == b) then return true end
		if (a2 == b2) then return true end

		-- Be less strict and search.
		if (a:find(b)) then return true end
		if (a2:find(b2)) then return true end
	end

	return false
end

--- Returns a string that has the named arguments in the format string replaced with the given arguments.
-- @realm shared
-- @string format Format string
-- @tparam tab|... Arguments to pass to the formatted string. If passed a table, it will use that table as the lookup table for
-- the named arguments. If passed multiple arguments, it will replace the arguments in the string in order.
-- @usage print(ws.util.FormatStringNamed("Hi, my name is {name}.", {name = "Bobby"}))
-- > Hi, my name is Bobby.
-- @usage print(ws.util.FormatStringNamed("Hi, my name is {name}.", "Bobby"))
-- > Hi, my name is Bobby.
function ws.util.FormatStringNamed(format, ...)
	local arguments = {...}
	local bArray = false -- Whether or not the input has numerical indices or named ones
	local input

	-- If the first argument is a table, we can assumed it's going to specify which
	-- keys to fill out. Otherwise we'll fill in specified arguments in order.
	if (istable(arguments[1])) then
		input = arguments[1]
	else
		input = arguments
		bArray = true
	end

	local i = 0
	local result = format:gsub("{(%w-)}", function(word)
		i = i + 1
		return tostring((bArray and input[i] or input[word]) or word)
	end)

	return result
end

do
	local upperMap = {
		["ooc"] = true,
		["looc"] = true,
		["afk"] = true,
		["url"] = true
	}
	--- Returns a string that is the given input with spaces in between each CamelCase word. This function will ignore any words
	-- that do not begin with a capital letter. The words `ooc`, `looc`, `afk`, and `url` will be automatically transformed
	-- into uppercase text. This will not capitalize non-ASCII letters due to limitations with Lua's pattern matching.
	-- @realm shared
	-- @string input String to expand
	-- @bool[opt=false] bNoUpperFirst Whether or not to avoid capitalizing the first character. This is useful for lowerCamelCase
	-- @treturn string Expanded CamelCase string
	-- @usage print(ws.util.ExpandCamelCase("HelloWorld"))
	-- > Hello World
	function ws.util.ExpandCamelCase(input, bNoUpperFirst)
		input = bNoUpperFirst and input or input:utf8sub(1, 1):utf8upper() .. input:utf8sub(2)

		-- extra parentheses to select first return value of gsub
		return string.TrimRight((input:gsub("%u%l+", function(word)
			if (upperMap[word:utf8lower()]) then
				word = word:utf8upper()
			end

			return word .. " "
		end)))
	end
end

function ws.util.GridVector(vec, gridSize)
	if (gridSize <= 0) then
		gridSize = 1
	end

	for i = 1, 3 do
		vec[i] = vec[i] / gridSize
		vec[i] = math.Round(vec[i])
		vec[i] = vec[i] * gridSize
	end

	return vec
end

