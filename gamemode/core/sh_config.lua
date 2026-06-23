
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

	ws.config.server = ws.yaml.Read("gamemodes/"..ws.FRAMEWORK_FOLDER.."/windswept.yml") or {}
end

CAMI.RegisterPrivilege({
	Name = "Windswept - Manage Config",
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

	-- noSave: callers pass true to skip the disk write; persist otherwise. (fw-config-command-boot-10)
	if (!noSave) then
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
		local oldValue = config.value
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

	ws.util.Include(ws.FRAMEWORK_FOLDER.."/gamemode/config/sh_config.lua")

	if (SERVER or !WS_RELOADED) then
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
		-- Strip non-networkable configs so they're never sent to a client, matching the
		-- per-value Set() broadcast guard (!config.bNoNetworking). (fw-config-command-boot-14)
		local data = ws.config.GetChangedValues()

		for k in pairs(data) do
			local stored = ws.config.stored[k]

			if (stored and stored.bNoNetworking) then
				data[k] = nil
			end
		end

		net.Start("wsConfigList")
			net.WriteTable(data)
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

	-- These config-admin actions are registered in a server post-load hook, NOT at file scope:
	-- sh_config.lua is included (shared.lua:83) BEFORE core/libs (shared.lua:84) where ws.action
	-- is defined, so ws.action does not exist yet here. InitPostEntity fires after all core files
	-- load (ws.action exists), and registration only needs to be in place before a client opens
	-- the config menu — long after boot. (Do not reorder shared.lua: core/libs/sh_date.lua reads
	-- ws.config at its own load time, so libs must stay loaded after sh_config.) (fw-config-load-order)
	hook.Add("InitPostEntity", "wsConfigActions", function()
	ws.action.Register("wsConfigSet", {
		read = function()
			return { key = net.ReadString(), value = net.ReadType() }
		end,

		onValidate = function(client, ctx)
			-- Guard against an unknown key (stored[key] is nil -> .default would error in the
			-- net thread). Also reject dummy/non-networkable configs (no real .type, or
			-- bNoNetworking) so a crafted packet can't poke them. (fw-config-command-boot-2) (tb-3)
			local config = ws.config.stored[ctx.data.key]

			if (!(config and config.type != nil and !config.bNoNetworking and
				CAMI.PlayerHasAccess(client, "Windswept - Manage Config", nil) and
				type(config.default) == type(ctx.data.value))) then
				return false
			end
		end,

		run = function(client, ctx)
			local key = ctx.data.key
			local value = ctx.data.value
			local config = ws.config.stored[key]

			-- The client value is attacker-controlled; re-apply the same sanitize/clamp the
			-- client UI does (cl_config.lua), so out-of-range / NaN / oversized values cannot
			-- be injected via a crafted net.Start. (fw-config-command-boot-1)
			value = ws.util.SanitizeType(config.type, value)

			if (config.type == ws.type.number) then
				-- reject NaN / +-inf
				if (value != value or value == math.huge or value == -math.huge) then
					return
				end

				local cdata = istable(config.data) and config.data or {}
				value = math.Round(value, cdata.decimals or 0)

				if (isnumber(cdata.min)) then value = math.max(value, cdata.min) end
				if (isnumber(cdata.max)) then value = math.min(value, cdata.max) end
			elseif (config.type == ws.type.string or config.type == ws.type.text) then
				if (#value > 4096) then value = string.sub(value, 1, 4096) end
			end

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
	})

	ws.action.Register("wsConfigRequestUnloadedList", {
		onValidate = function(client)
			if (!CAMI.PlayerHasAccess(client, "Windswept - Manage Config", nil)) then
				return false
			end
		end,

		run = function(client)
			net.Start("wsConfigUnloadedList")
				net.WriteTable(ws.plugin.unloaded)
			net.Send(client)
		end
	})

	ws.action.Register("wsConfigPluginToggle", {
		read = function()
			return { uniqueID = net.ReadString(), bShouldEnable = net.ReadBool() }
		end,

		onValidate = function(client, ctx)
			if (!CAMI.PlayerHasAccess(client, "Windswept - Manage Config", nil)) then
				return false
			end

			-- Reject uniqueIDs that aren't real plugins (and aren't already a legitimately-unloaded
			-- plugin), so a superadmin can't inject arbitrary keys into the persisted unloaded table.
			-- (fw-config-command-boot-5)
			if (!ws.plugin.list[ctx.data.uniqueID] and ws.plugin.unloaded[ctx.data.uniqueID] == nil) then
				return false
			end
		end,

		run = function(client, ctx)
			local uniqueID = ctx.data.uniqueID
			local bShouldEnable = ctx.data.bShouldEnable

			local bUnloaded = !!ws.plugin.unloaded[uniqueID]

			if ((bShouldEnable and bUnloaded) or (!bShouldEnable and !bUnloaded)) then
				ws.plugin.SetUnloaded(uniqueID, !bShouldEnable) -- flip bool since we're setting unloaded, not enabled

				ws.util.NotifyLocalized(bShouldEnable and "pluginLoaded" or "pluginUnloaded", nil, client:GetName(), uniqueID)
				ws.log.Add(client, bShouldEnable and "pluginLoaded" or "pluginUnloaded", uniqueID)

				net.Start("wsConfigPluginToggle")
					net.WriteString(uniqueID)
					net.WriteBool(bShouldEnable)
				net.Broadcast()
			end
		end
	})
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
		if (!CAMI.PlayerHasAccess(LocalPlayer(), "Windswept - Manage Config", nil)) then
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
