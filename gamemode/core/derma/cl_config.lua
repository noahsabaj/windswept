
-- config manager
local PANEL = {}

function PANEL:Init()
	self:Dock(FILL)
	self:SetSearchEnabled(true)

	self:Populate()
end

function PANEL:Populate()
	-- gather categories
	local categories = {}
	local categoryIndices = {}

	for k, v in pairs(ws.config.stored) do
		local index = v.data and v.data.category or "misc"

		categories[index] = categories[index] or {}
		categories[index][k] = v
	end

	-- sort by category phrase
	for k, _ in pairs(categories) do
		categoryIndices[#categoryIndices + 1] = k
	end

	table.sort(categoryIndices, function(a, b)
		return L(a) < L(b)
	end)

	-- add panels
	for _, category in ipairs(categoryIndices) do
		local categoryPhrase = L(category)
		self:AddCategory(categoryPhrase)

		-- we can use sortedpairs since configs don't have phrases to account for
		for k, v in SortedPairs(categories[category]) do
			if (isfunction(v.hidden) and v.hidden()) then
				continue
			end

			local data = v.data.data
			local type = v.type
			local value = ws.util.SanitizeType(type, ws.config.Get(k))

			local row = self:AddRow(type, categoryPhrase)
			row:SetText(ws.util.ExpandCamelCase(k))
			row:Populate(k, v.data)

			-- type-specific properties
			if (type == ws.type.number) then
				row:SetMin(data and data.min or 0)
				row:SetMax(data and data.max or 1)
				row:SetDecimals(data and data.decimals or 0)
			end

			row:SetValue(value, true)
			row:SetShowReset(value != v.default, k, v.default)

			row.OnValueChanged = function(panel)
				local newValue = ws.util.SanitizeType(type, panel:GetValue())

				panel:SetShowReset(newValue != v.default, k, v.default)

				ws.action.Send("wsConfigSet", nil, nil, function()
					net.WriteString(k)
					net.WriteType(newValue)
				end)
			end

			row.OnResetClicked = function(panel)
				panel:SetValue(v.default, true)
				panel:SetShowReset(false)

				ws.action.Send("wsConfigSet", nil, nil, function()
					net.WriteString(k)
					net.WriteType(v.default)
				end)
			end

			row:GetLabel():SetWindsweptTooltip(function(tooltip)
				local title = tooltip:AddRow("name")
				title:SetImportant()
				title:SetText(k)
				title:SizeToContents()
				title:SetMaxWidth(math.max(title:GetMaxWidth(), ScrW() * 0.5))

				local description = tooltip:AddRow("description")
				description:SetText(v.description)
				description:SizeToContents()
			end)
		end
	end

	self:SizeToContents()
end

vgui.Register("wsConfigManager", PANEL, "wsSettings")

-- plugin manager
PANEL = {}

function PANEL:Init()
	self:Dock(FILL)
	self:SetSearchEnabled(true)

	self.loadedCategory = L("loadedPlugins")
	self.unloadedCategory = L("unloadedPlugins")

	if (!ws.gui.bReceivedUnloadedPlugins) then
		ws.action.Send("wsConfigRequestUnloadedList")
	end

	self:Populate()
end

function PANEL:OnPluginToggled(uniqueID, bEnabled)
	ws.action.Send("wsConfigPluginToggle", nil, nil, function()
		net.WriteString(uniqueID)
		net.WriteBool(bEnabled)
	end)
end

function PANEL:Populate()
	self:AddCategory(self.loadedCategory)
	self:AddCategory(self.unloadedCategory)

	-- add loaded plugins
	for k, v in SortedPairsByMemberValue(ws.plugin.list, "name") do
		local row = self:AddRow(ws.type.bool, self.loadedCategory)
		row.id = k

		row.setting:SetEnabledText(L("on"):utf8upper())
		row.setting:SetDisabledText(L("off"):utf8upper())
		row.setting:SizeToContents()

		-- if this plugin is not in the unloaded list currently, then it's queued for an unload
		row:SetValue(!ws.plugin.unloaded[k], true)
		row:SetText(v.name)

		row.OnValueChanged = function(panel, bEnabled)
			self:OnPluginToggled(k, bEnabled)
		end

		row:GetLabel():SetWindsweptTooltip(function(tooltip)
			local title = tooltip:AddRow("name")
			title:SetImportant()
			title:SetText(v.name)
			title:SizeToContents()
			title:SetMaxWidth(math.max(title:GetMaxWidth(), ScrW() * 0.5))

			local description = tooltip:AddRow("description")
			description:SetText(v.description)
			description:SizeToContents()
		end)
	end

	self:UpdateUnloaded(true)
	self:SizeToContents()
end

function PANEL:UpdatePlugin(uniqueID, bEnabled)
	for _, v in pairs(self:GetRows()) do
		if (v.id == uniqueID) then
			v:SetValue(bEnabled, true)
		end
	end
end

-- called from Populate and from the wsConfigUnloadedList net message
function PANEL:UpdateUnloaded(bNoSizeToContents)
	for _, v in pairs(self:GetRows()) do
		if (ws.plugin.unloaded[v.id]) then
			v:SetValue(false, true)
		end
	end

	for k, v in SortedPairs(ws.plugin.unloaded) do
		if (ws.plugin.list[k]) then
			-- if this plugin is in the loaded plugins list then it's queued for an unload - don't display it in this category
			continue
		end

		local row = self:AddRow(ws.type.bool, self.unloadedCategory)
		row.id = k

		row.setting:SetEnabledText(L("on"):utf8upper())
		row.setting:SetDisabledText(L("off"):utf8upper())
		row.setting:SizeToContents()

		row:SetText(k)
		row:SetValue(!v, true)

		row.OnValueChanged = function(panel, bEnabled)
			self:OnPluginToggled(k, bEnabled)
		end
	end

	if (!bNoSizeToContents) then
		self:SizeToContents()
	end
end

vgui.Register("wsPluginManager", PANEL, "wsSettings")
