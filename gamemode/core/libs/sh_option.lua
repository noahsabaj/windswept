
--[[--
Client-side configuration management.

The `option` library provides a cleaner way to manage any arbitrary data on the client without the hassle of managing CVars. It
is analagous to the `ws.config` library, but it only deals with data that needs to be stored on the client.

To get started, you'll need to define an option in a client realm so the framework can be aware of its existence. This can be
done in the `cl_init.lua` file of your schema, or in an `if (CLIENT) then` statement in the `sh_plugin.lua` file of your plugin:
	ws.option.Add("headbob", ws.type.bool, true)

If you need to get the value of an option on the server, you'll need to specify `true` for the `bNetworked` argument in
`ws.option.Add`. *NOTE:* You also need to define your option in a *shared* realm, since the server now also needs to be aware
of its existence. This makes it so that the client will send that option's value to the server whenever it changes, which then
means that the server can now retrieve the value that the client has the option set to. For example, if you need to get what
language a client is using, you can simply do the following:
	ws.option.Get(player.GetByID(1), "language", "english")

This will return the language of the player, or `"english"` if one isn't found. Note that `"language"` is a networked option
that is already defined in the framework, so it will always be available. All options will show up in the options menu on the
client, unless `hidden` returns `true` when using `ws.option.Add`.

Note that the labels for each option in the menu will use a language phrase to show the name. For example, if your option is
named `headbob`, then you'll need to define a language phrase called `optHeadbob` that will be used as the option title.
]]
-- @module ws.option

ws.option = ws.option or {}
ws.option.stored = ws.option.stored or {}
ws.option.categories = ws.option.categories or {}

--- Creates a client-side configuration option with the given information.
-- @realm shared
-- @string key Unique ID for this option
-- @wstype optionType Type of this option
-- @param default Default value that this option will have - this can be nil if needed
-- @tparam OptionStructure data Additional settings for this option
-- @usage ws.option.Add("animationScale", ws.type.number, 1, {
-- 	category = "appearance",
-- 	min = 0.3,
-- 	max = 2,
-- 	decimals = 1
-- })
function ws.option.Add(key, optionType, default, data)
	assert(isstring(key) and key:find("%S"), "expected a non-empty string for the key")

	data = data or {}

	local oldOption = ws.option.stored[key]
	local categories = ws.option.categories
	local category = data.category or "misc"
	local upperName = key:sub(1, 1):upper() .. key:sub(2)

	categories[category] = categories[category] or {}
	categories[category][key] = true

	-- using explicit nil comparisons so we don't get caught by a config's value being `false`
	if (oldOption != nil and oldOption.default != nil) then
		default = oldOption.default
	end

	--- You can specify additional optional arguments for `ws.option.Add` by passing in a table of specific fields as the fourth
	-- argument.
	-- @table OptionStructure
	-- @realm shared
	-- @field[type=string,opt="opt" .. key] phrase The phrase to use when displaying in the UI. The default value is your option
	-- key in UpperCamelCase, prefixed with `"opt"`. For example, if your key is `"exampleOption"`, the default phrase will be
	-- `"optExampleOption"`.
	-- @field[type=string,opt="optd" .. key] description The phrase to use in the tooltip when hovered in the UI. The default
	-- value is your option key in UpperCamelCase, prefixed with `"optd"`. For example, if your key is `"exampleOption"`, the
	-- default phrase will be `"optdExampleOption"`.
	-- @field[type=string,opt="misc"] category The category that this option should reside in. This is purely for
	-- aesthetic reasons when displaying the options in the options menu. When displayed in the UI, it will take the form of
	-- `L("category name")`. This means that you must create a language phrase for the category name - otherwise it will only
	-- show as the exact string you've specified. If no category is set, it will default to `"misc"`.
	-- @field[type=number,opt=0] min The minimum allowed amount when setting this option. This field is not
	-- applicable to any type other than `ws.type.number`.
	-- @field[type=number,opt=10] max The maximum allowed amount when setting this option. This field is not
	-- applicable to any type other than `ws.type.number`.
	-- @field[type=number,opt=0] decimals How many decimals to constrain to when using a number type. This field is not
	-- applicable to any type other than `ws.type.number`.
	-- @field[type=boolean,opt=false] bNetworked Whether or not the server should be aware of this option for each client.
	-- @field[type=function,opt] OnChanged The function to run when this option is changed - this includes whether it was set
	-- by the player, or through code using `ws.option.Set`.
	-- 	OnChanged = function(oldValue, value)
	-- 		print("new value is", value)
	-- 	end
	-- @field[type=function,opt] hidden The function to check whether the option should be hidden from the options menu.
	-- @field[type=function,opt] populate The function to run when the option needs to be added to the menu. This is a required
	-- field for any array options. It should return a table of entries where the key is the value to set in `ws.option.Set`,
	-- and the value is the display name for the entry. An example:
	--
	-- 	populate = function()
	-- 		return {
	-- 			["english"] = "English",
	-- 			["french"] = "French",
	-- 			["spanish"] = "Spanish"
	-- 		}
	-- 	end
	ws.option.stored[key] = {
		key = key,
		phrase = data.phrase or "opt" .. upperName,
		description = data.description or "optd" .. upperName,
		type = optionType,
		default = default,
		min = data.min or 0,
		max = data.max or 10,
		decimals = data.decimals or 0,
		category = data.category or "misc",
		bNetworked = data.bNetworked and true or false,
		hidden = data.hidden or nil,
		populate = data.populate or nil,
		OnChanged = data.OnChanged or nil
	}
end

--- Sets the default value for a user option.
-- @realm shared
-- @string key Unique ID of the option
-- @param value Default value for the user option
function ws.option.SetDefault(key, value)
	local option = ws.option.stored[key]

	if (option) then
		option.default = value
	else
		-- set up dummy option if we're setting default of option that doesn't exist yet (i.e schema setting framework default)
		ws.option.stored[key] = {
			default = value
		}
	end
end

--- Loads all saved options from disk.
-- @realm shared
-- @internal
function ws.option.Load()
	ws.util.Include(ws.FRAMEWORK_FOLDER.."/gamemode/config/sh_options.lua")

	if (CLIENT) then
		local options = ws.data.Get("options", nil, true, true)

		if (options) then
			for k, v in pairs(options) do
				ws.option.client[k] = v
			end
		end

		ws.option.Sync()
	end
end

--- Returns all of the available options. Note that this does contain the actual values of the options, just their properties.
-- @realm shared
-- @treturn table Table of all options
-- @usage PrintTable(ws.option.GetAll())
-- > language:
-- >	bNetworked = true
-- >	default = english
-- >	type = 512
-- -- etc.
function ws.option.GetAll()
	return ws.option.stored
end


--- Returns all of the available options grouped by their categories. The returned table contains category tables, that contain
-- all the options in that category as an array (this is so you can sort them if you'd like).
-- @realm shared
-- @bool[opt=false] bRemoveHidden Remove entries that are marked as hidden
-- @treturn table Table of all options
-- @usage PrintTable(ws.option.GetAllByCategories())
-- > general:
-- >	1:
-- >		key = language
-- >		bNetworked = true
-- >		default = english
-- >		type = 512
-- -- etc.
function ws.option.GetAllByCategories(bRemoveHidden)
	local result = {}

	for k, v in pairs(ws.option.categories) do
		for k2, _ in pairs(v) do
			local option = ws.option.stored[k2]

			if (bRemoveHidden and isfunction(option.hidden) and option.hidden()) then
				continue
			end

			-- we create the category table here because it could contain all hidden options which makes the table empty
			result[k] = result[k] or {}
			result[k][#result[k] + 1] = option
		end
	end

	return result
end

--- Validates and clamps a value against an option definition. Shared by the client
-- `Set` and the server receivers so the same type/range rules apply everywhere.
-- Returns the sanitized value, or nil if the value's type does not match the option
-- (caller should then reject it). (fw-config-command-boot-3) (tb-5)
-- @realm shared
-- @tparam table option Stored option definition
-- @param value Untrusted value to validate
-- @return Sanitized value, or nil if the type is mismatched
function ws.option.ValidateValue(option, value)
	if (!istable(option) or option.type == nil) then return nil end

	if (option.type == ws.type.number) then
		if (!isnumber(value)) then return nil end

		-- reject NaN / +-inf before rounding/clamping
		if (value != value or value == math.huge or value == -math.huge) then return nil end

		value = math.Clamp(math.Round(value, option.decimals or 0), option.min or 0, option.max or 10)
	else
		-- For non-number types, the runtime type must map back to the option's type.
		if (ws.util.GetTypeFromValue(value) != option.type) then return nil end
	end

	return value
end

if (CLIENT) then
	ws.option.client = ws.option.client or {}

	--- Sets an option value for the local player.
	-- This function will error when an invalid key is passed.
	-- @realm client
	-- @string key Unique ID of the option
	-- @param value New value to assign to the option
	-- @bool[opt=false] bNoSave Whether or not to avoid saving
	function ws.option.Set(key, value, bNoSave)
		local option = assert(ws.option.stored[key], "invalid option key \"" .. tostring(key) .. "\"")

		-- Run through the shared validator (clamps numbers; rejects type mismatches). (fw-config-command-boot-3)
		local validated = ws.option.ValidateValue(option, value)
		if (validated != nil) then
			value = validated
		elseif (option.type == ws.type.number) then
			value = math.Clamp(math.Round(value, option.decimals), option.min, option.max)
		else
			-- Validator rejected a type-mismatched value; drop it rather than store an
			-- unvalidated value the server would reject (avoids client/server desync).
			return
		end

		local oldValue = ws.option.client[key]
		ws.option.client[key] = value

		if (option.bNetworked) then
			ws.action.Send("wsOptionSet", nil, nil, function()
				net.WriteString(key)
				net.WriteType(value)
			end)
		end

		if (!bNoSave) then
			ws.option.Save()
		end

		if (isfunction(option.OnChanged)) then
			option.OnChanged(oldValue, value)
		end
	end

	--- Retrieves an option value for the local player. If it is not set, it'll return the default that you've specified.
	-- @realm client
	-- @string key Unique ID of the option
	-- @param default Default value to return if the option is not set
	-- @return[1] Value associated with the key
	-- @return[2] The given default if the option is not set
	function ws.option.Get(key, default)
		local option = ws.option.stored[key]

		if (option) then
			local localValue = ws.option.client[key]

			if (localValue != nil) then
				return localValue
			end

			return option.default
		end

		return default
	end

	--- Saves all options to disk.
	-- @realm client
	-- @internal
	function ws.option.Save()
		ws.data.Set("options", ws.option.client, true, true)
	end

	--- Syncs all networked options to the server.
	-- @realm client
	function ws.option.Sync()
		local options = {}

		for k, v in pairs(ws.option.stored) do
			if (v.bNetworked) then
				options[#options + 1] = {k, ws.option.client[k]}
			end
		end

		if (#options > 0) then
			ws.action.Send("wsOptionSync", nil, nil, function()
				net.WriteUInt(#options, 8)

				for _, v in ipairs(options) do
					net.WriteString(v[1])
					net.WriteType(v[2])
				end
			end)
		end
	end
else
	util.AddNetworkString("wsOptionSet")
	util.AddNetworkString("wsOptionSync")

	ws.option.clients = ws.option.clients or {}

	--- Retrieves an option value from the specified player. If it is not set, it'll return the default that you've specified.
	-- This function will error when an invalid player is passed.
	-- @realm server
	-- @player client Player to retrieve option value from
	-- @string key Unique ID of the option
	-- @param default Default value to return if the option is not set
	-- @return[1] Value associated with the key
	-- @return[2] The given default if the option is not set
	function ws.option.Get(client, key, default)
		assert(IsValid(client) and client:IsPlayer(), "expected valid player for argument #1")

		local option = ws.option.stored[key]

		if (option) then
			local clientOptions = ws.option.clients[client:SteamID64()]

			if (clientOptions) then
				local clientOption = clientOptions[key]

				if (clientOption != nil) then
					return clientOption
				end
			end

			return option.default
		end

		return default
	end

	-- sent whenever a client's networked option has changed
	ws.action.Register("wsOptionSet", {
		read = function()
			return {key = net.ReadString(), value = net.ReadType()}
		end,
		run = function(client, ctx)
			local key = ctx.data.key
			local value = ctx.data.value

			local steamID = client:SteamID64()
			local option = ws.option.stored[key]

			if (option) then
				-- The value is attacker-controlled; validate/clamp against the option
				-- definition and drop type mismatches. (fw-config-command-boot-3) (tb-5)
				local validated = ws.option.ValidateValue(option, value)
				if (validated == nil) then return end

				ws.option.clients[steamID] = ws.option.clients[steamID] or {}
				ws.option.clients[steamID][key] = validated
			else
				ErrorNoHalt(string.format(
					"'%s' attempted to set option with invalid key '%s'\n", tostring(client) .. client:SteamID(), key
				))
			end
		end
	})

	-- sent on first load to sync all networked option values
	ws.action.Register("wsOptionSync", {
		read = function()
			local indices = net.ReadUInt(8)
			local data = {}

			for _ = 1, indices do
				data[net.ReadString()] = net.ReadType()
			end

			return data
		end,
		run = function(client, ctx)
			local data = ctx.data

			local steamID = client:SteamID64()
			ws.option.clients[steamID] = ws.option.clients[steamID] or {}

			for k, v in pairs(data) do
				local option = ws.option.stored[k]

				if (option) then
					-- Validate/clamp each synced value the same way as wsOptionSet. (fw-config-command-boot-3) (tb-5)
					local validated = ws.option.ValidateValue(option, v)
					if (validated != nil) then
						ws.option.clients[steamID][k] = validated
					end
				else
					return ErrorNoHalt(string.format(
						"'%s' attempted to sync option with invalid key '%s'\n", tostring(client) .. client:SteamID(), k
					))
				end
			end
		end
	})

	-- Clear the per-client option cache on disconnect so it doesn't leak memory
	-- across the session (keyed by SteamID64, never otherwise cleared). (fw-config-command-boot-4)
	hook.Add("PlayerDisconnected", "wsOptionClientCleanup", function(client)
		ws.option.clients[client:SteamID64()] = nil
	end)
end
