
--- Helper library for creating/setting config options.
-- @module ws.config

ws.config = ws.config or {}
ws.config.stored = ws.config.stored or {}

if (SERVER) then
	util.AddNetworkString("wsConfigList")
	util.AddNetworkString("wsConfigSet")
	util.AddNetworkString("wsConfigRequestUnloadedList")
	util.AddNetworkString("wsConfigUnloadedList")
	util.AddNetworkString("wsConfigPluginToggle")

	ws.config.server = ws.yaml.Read("gamemodes/helix/helix.yml") or {}
end

CAMI.RegisterPrivilege({
	Name = "Helix - Manage Config",
	MinAccess = "superadmin"
})

--- Creates a config option with the given information.
-- @realm shared
-- @string key Unique ID of the config
-- @param value Default value that this config will have
-- @string description Description of the config
-- @func[opt=nil] callback Function to call when config is changed
-- @tab[opt=nil] data Additional settings for this config option
-- @bool[opt=false] bNoNetworking Whether or not to prevent networking the config
-- @bool[opt=false] bSchemaOnly Whether or not the config is for the schema only
function ws.config.Add(key, value, description, callback, data, bNoNetworking, bSchemaOnly)
	data = istable(data) and data or {}

	local oldConfig = ws.config.stored[key]
	local type = data.type or ws.util.GetTypeFromValue(value)

	if (!type) then
		ErrorNoHalt("attempted to add config with invalid type\n")
		return
	end

	local default = value
	data.type = nil

	-- using explicit nil comparisons so we don't get caught by a config's value being `false`
	if (oldConfig != nil) then
		if (oldConfig.value != nil) then
			value = oldConfig.value
		end

		if (oldConfig.default != nil) then
			default = oldConfig.default
		end
	end

	ws.config.stored[key] = {
		type = type,
		data = data,
		value = value,
		default = default,
		description = description,
		bNoNetworking = bNoNetworking,
		global = !bSchemaOnly,
		callback = callback,
		hidden = data.hidden or nil
	}
end

--- Sets the default value for a config option.
-- @realm shared
-- @string key Unique ID of the config
-- @param value Default value for the config option
function ws.config.SetDefault(key, value)
	local config = ws.config.stored[key]

	if (config) then
		config.default = value
	else
		-- set up dummy config if we're setting default of config that doesn't exist yet (i.e schema setting framework default)
		ws.config.stored[key] = {
			value = value,
			default = value
		}
	end
end

function ws.config.ForceSet(key, value, noSave)
	local config = ws.config.stored[key]

	if (config) then
		config.value = value
	end

	if (noSave) then
		ws.config.Save()
	end
end

--- Sets the value of a config option.
-- @realm shared
-- @string key Unique ID of the config
-- @param value New value to assign to the config
function ws.config.Set(key, value)
	local config = ws.config.stored[key]

	if (config) then
		local oldValue = value
		config.value = value

		if (SERVER) then
			if (!config.bNoNetworking) then
				net.Start("wsConfigSet")
					net.WriteString(key)
					net.WriteType(value)
				net.Broadcast()
			end

			if (config.callback) then
				config.callback(oldValue, value)
			end

			ws.config.Save()
		end
	end
end

--- Retrieves a value of a config option. If it is not set, it'll return the default that you've specified.
-- @realm shared
-- @string key Unique ID of the config
-- @param default Default value to return if the config is not set
-- @return Value associated with the key, or the default that was given if it doesn't exist
function ws.config.Get(key, default)
	local config = ws.config.stored[key]

	-- ensure we aren't accessing a dummy value
	if (config and config.type) then
		if (config.value != nil) then
			return config.value
		elseif (config.default != nil) then
			return config.default
		end
	end

	return default
end

--- Loads all saved config options from disk.
-- @realm shared
-- @internal
function ws.config.Load()
	if (SERVER) then
		local globals = ws.data.Get("config", nil, true, true)
		local data = ws.data.Get("config", nil, false, true)

		if (globals) then
			for k, v in pairs(globals) do
				ws.config.stored[k] = ws.config.stored[k] or {}
				ws.config.stored[k].value = v
			end
		end

		if (data) then
			for k, v in pairs(data) do
				ws.config.stored[k] = ws.config.stored[k] or {}
				ws.config.stored[k].value = v
			end
		end
	end

	ws.util.Include("windswept/gamemode/config/sh_config.lua")

	if (SERVER or !IX_RELOADED) then
		hook.Run("InitializedConfig")
	end
end

if (SERVER) then
	function ws.config.GetChangedValues()
		local data = {}

		for k, v in pairs(ws.config.stored) do
			if (v.default != v.value) then
				data[k] = v.value
			end
		end

		return data
	end

	function ws.config.Send(client)
		net.Start("wsConfigList")
			net.WriteTable(ws.config.GetChangedValues())
		net.Send(client)
	end

	--- Saves all config options to disk.
	-- @realm server
	-- @internal
	function ws.config.Save()
		local globals = {}
		local data = {}

		for k, v in pairs(ws.config.GetChangedValues()) do
			if (ws.config.stored[k].global) then
				globals[k] = v
			else
				data[k] = v
			end
		end

		-- Global and schema data set respectively.
		ws.data.Set("config", globals, true, true)
		ws.data.Set("config", data, false, true)
	end

	net.Receive("wsConfigSet", function(length, client)
		local key = net.ReadString()
		local value = net.ReadType()

		if (CAMI.PlayerHasAccess(client, "Helix - Manage Config", nil) and
			type(ws.config.stored[key].default) == type(value)) then
			ws.config.Set(key, value)

			if (ws.util.IsColor(value)) then
				value = string.format("[%d, %d, %d]", value.r, value.g, value.b)
			elseif (istable(value)) then
				local value2 = "["
				local count = table.Count(value)
				local i = 1

				for _, v in SortedPairs(value) do
					value2 = value2 .. v .. (i == count and "]" or ", ")
					i = i + 1
				end

				value = value2
			elseif (isstring(value)) then
				value = string.format("\"%s\"", tostring(value))
			elseif (isbool(value)) then
				value = string.format("[%s]", tostring(value))
			end

			ws.util.NotifyLocalized("cfgSet", nil, client:Name(), key, tostring(value))
			ws.log.Add(client, "cfgSet", key, value)
		end
	end)

	net.Receive("wsConfigRequestUnloadedList", function(length, client)
		if (!CAMI.PlayerHasAccess(client, "Helix - Manage Config", nil)) then
			return
		end

		net.Start("wsConfigUnloadedList")
			net.WriteTable(ws.plugin.unloaded)
		net.Send(client)
	end)

	net.Receive("wsConfigPluginToggle", function(length, client)
		if (!CAMI.PlayerHasAccess(client, "Helix - Manage Config", nil)) then
			return
		end

		local uniqueID = net.ReadString()
		local bUnloaded = !!ws.plugin.unloaded[uniqueID]
		local bShouldEnable = net.ReadBool()

		if ((bShouldEnable and bUnloaded) or (!bShouldEnable and !bUnloaded)) then
			ws.plugin.SetUnloaded(uniqueID, !bShouldEnable) -- flip bool since we're setting unloaded, not enabled

			ws.util.NotifyLocalized(bShouldEnable and "pluginLoaded" or "pluginUnloaded", nil, client:GetName(), uniqueID)
			ws.log.Add(client, bShouldEnable and "pluginLoaded" or "pluginUnloaded", uniqueID)

			net.Start("wsConfigPluginToggle")
				net.WriteString(uniqueID)
				net.WriteBool(bShouldEnable)
			net.Broadcast()
		end
	end)
else
	net.Receive("wsConfigList", function()
		local data = net.ReadTable()

		for k, v in pairs(data) do
			if (ws.config.stored[k]) then
				ws.config.stored[k].value = v
			end
		end

		hook.Run("InitializedConfig", data)
	end)

	net.Receive("wsConfigSet", function()
		local key = net.ReadString()
		local value = net.ReadType()
		local config = ws.config.stored[key]

		if (config) then
			if (config.callback) then
				config.callback(config.value, value)
			end

			config.value = value

			local properties = ws.gui.properties

			if (IsValid(properties)) then
				local row = properties:GetCategory(L(config.data and config.data.category or "misc")):GetRow(key)

				if (IsValid(row)) then
					if (istable(value) and value.r and value.g and value.b) then
						value = Vector(value.r / 255, value.g / 255, value.b / 255)
					end

					row:SetValue(value)
				end
			end
		end
	end)

	net.Receive("wsConfigUnloadedList", function()
		ws.plugin.unloaded = net.ReadTable()
		ws.gui.bReceivedUnloadedPlugins = true

		if (IsValid(ws.gui.pluginManager)) then
			ws.gui.pluginManager:UpdateUnloaded()
		end
	end)

	net.Receive("wsConfigPluginToggle", function()
		local uniqueID = net.ReadString()
		local bEnabled = net.ReadBool()

		if (bEnabled) then
			ws.plugin.unloaded[uniqueID] = false
		else
			ws.plugin.unloaded[uniqueID] = true
		end

		if (IsValid(ws.gui.pluginManager)) then
			ws.gui.pluginManager:UpdatePlugin(uniqueID, bEnabled)
		end
	end)

	hook.Add("CreateMenuButtons", "wsConfig", function(tabs)
		if (!CAMI.PlayerHasAccess(LocalPlayer(), "Helix - Manage Config", nil)) then
			return
		end

		tabs["config"] = {
			Create = function(info, container)
				container.panel = container:Add("wsConfigManager")
			end,

			OnSelected = function(info, container)
				container.panel.searchEntry:RequestFocus()
			end,

			Sections = {
				plugins = {
					Create = function(info, container)
						ws.gui.pluginManager = container:Add("wsPluginManager")
					end,

					OnSelected = function(info, container)
						ws.gui.pluginManager.searchEntry:RequestFocus()
					end
				}
			}
		}
	end)
end
