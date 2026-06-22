
local panelMap = {
	[ws.type.bool] = "wsSettingsRowBool",
	[ws.type.array] = "wsSettingsRowArray",
	[ws.type.string] = "wsSettingsRowString",
	[ws.type.number] = "wsSettingsRowNumber",
	[ws.type.color] = "wsSettingsRowColor"
}

local function EmitChange(pitch)
	LocalPlayer():EmitSound("weapons/ar2/ar2_empty.wav", 75, pitch or 150, 0.25)
end

-- color setting
local PANEL = {}

AccessorFunc(PANEL, "padding", "Padding", FORCE_NUMBER)

function PANEL:Init()
	self.color = table.Copy(color_white)
	self.padding = 4

	self.panel = self:Add("Panel")
	self.panel:SetCursor("hand")
	self.panel:SetMouseInputEnabled(true)
	self.panel:Dock(RIGHT)
	self.panel.Paint = function(panel, width, height)
		local padding = self.padding

		surface.SetDrawColor(derma.GetColor("DarkerBackground", self))
		surface.DrawRect(0, 0, width, height)

		surface.SetDrawColor(self.color)
		surface.DrawRect(padding, padding, width - padding * 2, height - padding * 2)
	end

	self.panel.OnMousePressed = function(panel, key)
		if (key == MOUSE_LEFT) then
			self:OpenPicker()
		end
	end
end

function PANEL:OpenPicker()
	if (IsValid(self.picker)) then
		self.picker:Remove()
		return
	end

	self.picker = vgui.Create("wsSettingsRowColorPicker")
	self.picker:Attach(self)
	self.picker:SetValue(self.color)

	self.picker.OnValueChanged = function(panel)
		local newColor = panel:GetValue()

		if (newColor != self.color) then
			self.color = newColor
			self:OnValueChanged(newColor)
		end
	end

	self.picker.OnValueUpdated = function(panel)
		self.color = panel:GetValue()
	end
end

function PANEL:SetValue(value)
	self.color = Color(value.r or 255, value.g or 255, value.b or 255, value.a or 255)
end

function PANEL:GetValue()
	return self.color
end

function PANEL:PerformLayout(width, height)
	surface.SetFont("wsMenuButtonFont")
	local totalWidth = surface.GetTextSize("999")

	self.panel:SetSize(totalWidth + self.padding * 2, height)
end

vgui.Register("wsSettingsRowColor", PANEL, "wsSettingsRow")

-- color setting picker
DEFINE_BASECLASS("Panel")
PANEL = {}

AccessorFunc(PANEL, "bDeleteSelf", "DeleteSelf", FORCE_BOOL)

function PANEL:Init()
	self.m_bIsMenuComponent = true
	self.bDeleteSelf = true

	self.realHeight = 200
	self.height = 200
	self:SetSize(250, 200)
	self:DockPadding(4, 4, 4, 4)

	self.picker = self:Add("DColorMixer")
	self.picker:Dock(FILL)
	self.picker.ValueChanged = function()
		self:OnValueUpdated()
	end

	self:MakePopup()
	RegisterDermaMenuForClose(self)
end

function PANEL:SetValue(value)
	self.picker:SetColor(Color(value.r or 255, value.g or 255, value.b or 255, value.a or 255))
end

function PANEL:GetValue()
	return self.picker:GetColor()
end

function PANEL:Attach(panel)
	self.attached = panel
end

function PANEL:Think()
	local panel = self.attached

	if (IsValid(panel)) then
		local width, height = self:GetSize()
		local x, y = panel:LocalToScreen(0, 0)

		self:SetPos(
			math.Clamp(x + panel:GetWide() - width, 0, ScrW() - width),
			math.Clamp(y + panel:GetTall(), 0, ScrH() - height)
		)
	end
end

function PANEL:Paint(width, height)
	surface.SetDrawColor(derma.GetColor("DarkerBackground", self))
	surface.DrawRect(0, 0, width, height)
end

function PANEL:OnValueChanged()
end

function PANEL:OnValueUpdated()
end

function PANEL:Remove()
	if (self.bClosing) then
		return
	end

	self:OnValueChanged()

	-- @todo open/close animations
	self.bClosing = true
	self:SetMouseInputEnabled(false)
	self:SetKeyboardInputEnabled(false)
	BaseClass.Remove(self)
end

vgui.Register("wsSettingsRowColorPicker", PANEL, "EditablePanel")

-- number setting
PANEL = {}

function PANEL:Init()
	self.setting = self:Add("wsNumSlider")
	self.setting.nextUpdate = 0
	self.setting:Dock(RIGHT)
	self.setting.OnValueChanged = function(panel)
		self:OnValueChanged(self:GetValue())
	end
	self.setting.OnValueUpdated = function(panel)
		local fraction = panel:GetFraction()

		if (fraction == 0) then
			EmitChange(75)
			return
		elseif (fraction == 1) then
			EmitChange(120)
			return
		end

		if (SysTime() > panel.nextUpdate) then
			EmitChange(85 + fraction * 15)
			panel.nextUpdate = SysTime() + 0.05
		end
	end

	local panel = self.setting:GetLabel()
	panel:SetCursor("hand")
	panel:SetMouseInputEnabled(true)
	panel.OnMousePressed = function(_, key)
		if (key == MOUSE_LEFT) then
			self:OpenEntry()
		end
	end
end

function PANEL:OpenEntry()
	if (IsValid(self.entry)) then
		self.entry:Remove()
		return
	end

	self.entry = vgui.Create("wsSettingsRowNumberEntry")
	self.entry:Attach(self)
	self.entry:SetValue(self:GetValue(), true)
	self.entry.OnValueChanged = function(panel)
		local value = math.Round(panel:GetValue(), self:GetDecimals())

		if (value != self:GetValue()) then
			self:SetValue(value, true)
			self:OnValueChanged(value)
		end
	end
end

function PANEL:SetValue(value, bNoNotify)
	self.setting:SetValue(value, bNoNotify)
end

function PANEL:GetValue()
	return self.setting:GetValue()
end

function PANEL:SetMin(value)
	self.setting:SetMin(value)
end

function PANEL:SetMax(value)
	self.setting:SetMax(value)
end

function PANEL:SetDecimals(value)
	self.setting:SetDecimals(value)
end

function PANEL:GetDecimals()
	return self.setting:GetDecimals()
end

function PANEL:PerformLayout(width, height)
	self.setting:SetWide(width * 0.5)
end

vgui.Register("wsSettingsRowNumber", PANEL, "wsSettingsRow")

-- number setting entry
DEFINE_BASECLASS("Panel")
PANEL = {}

AccessorFunc(PANEL, "bDeleteSelf", "DeleteSelf", FORCE_BOOL)

function PANEL:Init()
	surface.SetFont("wsMenuButtonFont")
	local width, height = surface.GetTextSize("999999")

	self.m_bIsMenuComponent = true
	self.bDeleteSelf = true

	self.realHeight = 200
	self.height = 200
	self:SetSize(width, height)
	self:DockPadding(4, 4, 4, 4)

	self.textEntry = self:Add("wsTextEntry")
	self.textEntry:SetNumeric(true)
	self.textEntry:SetFont("wsMenuButtonFont")
	self.textEntry:Dock(FILL)
	self.textEntry:RequestFocus()
	self.textEntry.OnEnter = function()
		self:Remove()
	end

	self:MakePopup()
	RegisterDermaMenuForClose(self)
end

function PANEL:SetValue(value, bInitial)
	value = tostring(value)
	self.textEntry:SetValue(value)

	if (bInitial) then
		self.textEntry:SetCaretPos(value:utf8len())
	end
end

function PANEL:GetValue()
	return tonumber(self.textEntry:GetValue()) or 0
end

function PANEL:Attach(panel)
	self.attached = panel
end

function PANEL:Think()
	local panel = self.attached

	if (IsValid(panel)) then
		local width, height = self:GetSize()
		local x, y = panel:LocalToScreen(0, 0)

		self:SetPos(
			math.Clamp(x + panel:GetWide() - width, 0, ScrW() - width),
			math.Clamp(y + panel:GetTall(), 0, ScrH() - height)
		)
	end
end

function PANEL:Paint(width, height)
	surface.SetDrawColor(derma.GetColor("DarkerBackground", self))
	surface.DrawRect(0, 0, width, height)
end

function PANEL:OnValueChanged()
end

function PANEL:OnValueUpdated()
end

function PANEL:Remove()
	if (self.bClosing) then
		return
	end

	self:OnValueChanged()

	-- @todo open/close animations
	self.bClosing = true
	self:SetMouseInputEnabled(false)
	self:SetKeyboardInputEnabled(false)
	BaseClass.Remove(self)
end

vgui.Register("wsSettingsRowNumberEntry", PANEL, "EditablePanel")

-- string setting
PANEL = {}

function PANEL:Init()
	self.setting = self:Add("wsTextEntry")
	self.setting:Dock(RIGHT)
	self.setting:SetFont("wsMenuButtonFont")
	self.setting:SetBackgroundColor(derma.GetColor("DarkerBackground", self))
	self.setting.OnEnter = function()
		self:OnValueChanged(self:GetValue())
	end
end

function PANEL:SetValue(value)
	self.setting:SetValue(tostring(value))
end

function PANEL:GetValue()
	return self.setting:GetValue()
end

function PANEL:PerformLayout(width, height)
	self.setting:SetWide(width * 0.5)
end

vgui.Register("wsSettingsRowString", PANEL, "wsSettingsRow")

-- bool setting
PANEL = {}

function PANEL:Init()
	self.setting = self:Add("wsCheckBox")
	self.setting:Dock(RIGHT)
	self.setting.DoClick = function(panel)
		self:OnValueChanged(self:GetValue())
	end
end

function PANEL:SetValue(bValue)
	bValue = tobool(bValue)

	self.setting:SetChecked(bValue, true)
end

function PANEL:GetValue()
	return self.setting:GetChecked()
end

vgui.Register("wsSettingsRowBool", PANEL, "wsSettingsRow")

-- array setting
PANEL = {}

function PANEL:Init()
	self.array = {}

	self.setting = self:Add("DComboBox")
	self.setting:Dock(RIGHT)
	self.setting:SetFont("wsMenuButtonFont")
	self.setting:SetTextColor(color_white)
	self.setting.OnSelect = function(panel)
		self:OnValueChanged(self:GetValue())

		panel:SizeToContents()
		panel:SetWide(panel:GetWide() + 12) -- padding for arrow (nice)

		if (!self.bInitial) then
			EmitChange()
		end
	end
end

function PANEL:Populate(key, info)
	if (!isfunction(info.populate)) then
		ErrorNoHalt(string.format("expected populate function for array option '%s'", key))
		return
	end

	local entries = info.populate()
	local i = 1

	for k, v in pairs(entries) do
		self.setting:AddChoice(v, k)
		self.array[k] = i

		i = i + 1
	end
end

function PANEL:SetValue(value)
	self.bInitial = true
		self.setting:ChooseOptionID(self.array[value])
	self.bInitial = false
end

function PANEL:GetValue()
	return select(2, self.setting:GetSelected())
end

vgui.Register("wsSettingsRowArray", PANEL, "wsSettingsRow")

-- settings row
PANEL = {}

AccessorFunc(PANEL, "backgroundIndex", "BackgroundIndex", FORCE_NUMBER)
AccessorFunc(PANEL, "bShowReset", "ShowReset", FORCE_BOOL)

function PANEL:Init()
	self:DockPadding(4, 4, 4, 4)

	self.text = self:Add("DLabel")
	self.text:Dock(LEFT)
	self.text:SetFont("wsMenuButtonFont")
	self.text:SetExpensiveShadow(1, color_black)

	self.backgroundIndex = 0
end

function PANEL:SetShowReset(value, name, default)
	value = tobool(value)

	if (value and !IsValid(self.reset)) then
		self.reset = self:Add("DButton")
		self.reset:SetFont("wsSmallTitleIcons")
		self.reset:SetText("x")
		self.reset:SetTextColor(ColorAlpha(derma.GetColor("Warning", self), 100))
		self.reset:Dock(LEFT)
		self.reset:DockMargin(4, 0, 0, 0)
		self.reset:SizeToContents()
		self.reset.Paint = nil
		self.reset.DoClick = function()
			self:OnResetClicked()
		end
		self.reset:SetWindsweptTooltip(function(tooltip)
			local title = tooltip:AddRow("title")
			title:SetImportant()
			title:SetText(L("resetDefault"))
			title:SetBackgroundColor(derma.GetColor("Warning", self))
			title:SizeToContents()

			local description = tooltip:AddRow("description")
			description:SetText(L("resetDefaultDescription", tostring(name), tostring(default)))
			description:SizeToContents()
		end)
	elseif (!value and IsValid(self.reset)) then
		self.reset:Remove()
	end

	self.bShowReset = value
end

function PANEL:Think()
	if (IsValid(self.reset)) then
		self.reset:SetVisible(self:IsHovered() or self:IsOurChild(vgui.GetHoveredPanel()))
	end
end

function PANEL:OnResetClicked()
end

function PANEL:GetLabel()
	return self.text
end

function PANEL:SetText(text)
	self.text:SetText(text)
	self:SizeToContents()
end

function PANEL:GetText()
	return self.text:GetText()
end

-- implemented by row types
function PANEL:GetValue()
end

function PANEL:SetValue(value)
end

-- meant for array types to populate combo box values
function PANEL:Populate(key, info)
end

-- called when value is changed by user
function PANEL:OnValueChanged(newValue)
end

function PANEL:SizeToContents()
	local _, top, _, bottom = self:GetDockPadding()

	self.text:SizeToContents()
	self:SetTall(self.text:GetTall() + top + bottom)
	self.wsRealHeight = self:GetTall()
	self.wsHeight = self.wsRealHeight
end

function PANEL:Paint(width, height)
	derma.SkinFunc("PaintSettingsRowBackground", self, width, height)
end

vgui.Register("wsSettingsRow", PANEL, "EditablePanel")

-- settings panel
PANEL = {}

function PANEL:Init()
	self:Dock(FILL)
	self.rows = {}
	self.categories = {}

	-- scroll panel
	DEFINE_BASECLASS("DScrollPanel")

	self.canvas = self:Add("DScrollPanel")
	self.canvas:Dock(FILL)
	self.canvas.PerformLayout = function(panel)
		BaseClass.PerformLayout(panel)

		if (!panel.VBar.Enabled) then
			panel.pnlCanvas:SetWide(panel:GetWide() - panel.VBar:GetWide())
		end
	end
end

function PANEL:GetRowPanelName(type)
	return panelMap[type] or "wsSettingsRow"
end

function PANEL:AddCategory(name)
	local panel = self.categories[name]

	if (!IsValid(panel)) then
		panel = self.canvas:Add("wsCategoryPanel")
		panel:SetText(name)
		panel:Dock(TOP)
		panel:DockMargin(0, 8, 0, 0)

		self.categories[name] = panel
		return panel
	end
end

function PANEL:AddRow(type, category)
	category = self.categories[category]
	local id = panelMap[type]

	if (!id) then
		ErrorNoHalt("attempted to create row with unimplemented type '" .. tostring(ws.type[type]) .. "'\n")
		id = "wsSettingsRow"
	end

	local panel = (IsValid(category) and category or self.canvas):Add(id)
	panel:Dock(TOP)
	panel:SetBackgroundIndex(#self.rows % 2)

	self.rows[#self.rows + 1] = panel
	return panel
end

function PANEL:GetRows()
	return self.rows
end

function PANEL:Clear()
	for _, v in ipairs(self.rows) do
		if (IsValid(v)) then
			v:Remove()
		end
	end

	self.rows = {}
end

function PANEL:SetSearchEnabled(bValue)
	if (!bValue) then
		if (IsValid(self.searchEntry)) then
			self.searchEntry:Remove()
		end

		return
	end

	-- search entry
	self.searchEntry = self:Add("wsIconTextEntry")
	self.searchEntry:Dock(TOP)
	self.searchEntry:SetEnterAllowed(false)

	self.searchEntry.OnChange = function(entry)
		self:FilterRows(entry:GetValue())
	end
end

function PANEL:FilterRows(query)
	query = string.PatternSafe(query:lower())

	local bEmpty = query == ""

	for categoryName, category in pairs(self.categories) do
		category.size = 0
		category:CreateAnimation(0.5, {
			index = 21,
			target = {size = 1},

			Think = function(animation, panel)
				panel:SizeToContents()
			end
		})

		for _, row in ipairs(category:GetChildren()) do
			local bFound = bEmpty or row:GetText():lower():find(query) or categoryName:lower():find(query)

			row:SetVisible(true)
			row:CreateAnimation(0.5, {
				index = 21,
				target = {wsHeight = bFound and row.wsRealHeight or 0},
				easing = "outQuint",

				Think = function(animation, panel)
					panel:SetTall(bFound and math.min(panel.wsHeight + 2, panel.wsRealHeight) or math.max(panel.wsHeight - 2, 0))
				end,

				OnComplete = function(animation, panel)
					panel:SetVisible(bFound)

					-- need this so categories are sized properly when animations are disabled - there is no guaranteed order
					-- that animations will think so we SizeToContents here. putting it here will result in redundant calls but
					-- I guess we have the performance to spare
					if (ws.option.Get("disableAnimations", false)) then
						category:SizeToContents()
					end
				end
			})
		end
	end
end

function PANEL:Paint(width, height)
end

function PANEL:SizeToContents()
	for _, v in pairs(self.categories) do
		v:SizeToContents()
	end
end

vgui.Register("wsSettings", PANEL, "Panel")

hook.Add("CreateMenuButtons", "wsSettings", function(tabs)
	tabs["settings"] = {
		PopulateTabButton = function(info, button)
			local menu = ws.gui.menu

			if (!IsValid(menu)) then
				return
			end

			DEFINE_BASECLASS("wsMenuButton")
			button:SetZPos(9999)
			button.Paint = function(panel, width, height)
				BaseClass.Paint(panel, width, height)

				surface.SetDrawColor(255, 255, 255, 33)
				surface.DrawRect(0, 0, width, 1)
			end
		end,

		Create = function(info, container)
			local panel = container:Add("wsSettings")
			panel:SetSearchEnabled(true)

			for category, options in SortedPairs(ws.option.GetAllByCategories(true)) do
				category = L(category)
				panel:AddCategory(category)

				-- sort options by language phrase rather than the key
				table.sort(options, function(a, b)
					return L(a.phrase) < L(b.phrase)
				end)

				for _, data in pairs(options) do
					local key = data.key
					local row = panel:AddRow(data.type, category)
					local value = ws.util.SanitizeType(data.type, ws.option.Get(key))

					row:SetText(L(data.phrase))
					row:Populate(key, data)

					-- type-specific properties
					if (data.type == ws.type.number) then
						row:SetMin(data.min or 0)
						row:SetMax(data.max or 10)
						row:SetDecimals(data.decimals or 0)
					end

					row:SetValue(value, true)
					row:SetShowReset(value != data.default, key, data.default)
					row.OnValueChanged = function()
						local newValue = row:GetValue()

						row:SetShowReset(newValue != data.default, key, data.default)
						ws.option.Set(key, newValue)
					end

					row.OnResetClicked = function()
						row:SetShowReset(false)
						row:SetValue(data.default, true)

						ws.option.Set(key, data.default)
					end

					row:GetLabel():SetWindsweptTooltip(function(tooltip)
						local title = tooltip:AddRow("name")
						title:SetImportant()
						title:SetText(key)
						title:SizeToContents()
						title:SetMaxWidth(math.max(title:GetMaxWidth(), ScrW() * 0.5))

						local description = tooltip:AddRow("description")
						description:SetText(L(data.description))
						description:SizeToContents()
					end)
				end
			end

			panel:SizeToContents()
			container.panel = panel
		end,

		OnSelected = function(info, container)
			container.panel.searchEntry:RequestFocus()
		end
	}
end)
