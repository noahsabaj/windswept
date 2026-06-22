
local PLUGIN = PLUGIN

local function DrawTextBackground(x, y, text, font, backgroundColor, padding)
	font = font or "wsSubTitleFont"
	padding = padding or 8
	backgroundColor = backgroundColor or Color(88, 88, 88, 255)

	surface.SetFont(font)
	local textWidth, textHeight = surface.GetTextSize(text)
	local width, height = textWidth + padding * 2, textHeight + padding * 2

	ws.util.DrawBlurAt(x, y, width, height)
	surface.SetDrawColor(0, 0, 0, 40)
	surface.DrawRect(x, y, width, height)

	derma.SkinFunc("DrawImportantBackground", x, y, width, height, backgroundColor)

	surface.SetTextColor(color_white)
	surface.SetTextPos(x + padding, y + padding)
	surface.DrawText(text)

	return height
end

function PLUGIN:InitPostEntity()
	hook.Run("SetupAreaProperties")
end

function PLUGIN:ChatboxCreated()
	if (IsValid(self.panel)) then
		self.panel:Remove()
	end

	self.panel = vgui.Create("wsArea")
end

function PLUGIN:ChatboxPositionChanged(x, y, width, height)
	if (!IsValid(self.panel)) then
		return
	end

	self.panel:SetSize(width, y)
	self.panel:SetPos(32, 0)
end

function PLUGIN:ShouldDrawCrosshair()
	if (ws.area.bEditing) then
		return true
	end
end

function PLUGIN:PlayerBindPress(client, bind, bPressed)
	if (!ws.area.bEditing) then
		return
	end

	if ((bind:find("invnext") or bind:find("invprev")) and bPressed) then
		return true
	elseif (bind:find("attack2") and bPressed) then
		self:EditRightClick()
		return true
	elseif (bind:find("attack") and bPressed) then
		self:EditClick()
		return true
	elseif (bind:find("reload") and bPressed) then
		self:EditReload()
		return true
	end
end

function PLUGIN:HUDPaint()
	if (!ws.area.bEditing) then
		return
	end

	local id = LocalPlayer():GetArea()
	local area = ws.area.stored[id]
	local height = ScrH()

	local y = 64
	y = y + DrawTextBackground(64, y, L("areaEditMode"), nil, ws.config.Get("color"))

	if (!self.editStart) then
		y = y + DrawTextBackground(64, y, L("areaEditTip"), "wsSmallTitleFont")
		DrawTextBackground(64, y, L("areaRemoveTip"), "wsSmallTitleFont")
	else
		DrawTextBackground(64, y, L("areaFinishTip"), "wsSmallTitleFont")
	end

	if (area) then
		DrawTextBackground(64, height - 64 - ScreenScale(12), id, "wsSmallTitleFont", area.properties.color)
	end
end

function PLUGIN:PostDrawTranslucentRenderables(bDepth, bSkybox)
	if (bSkybox or !ws.area.bEditing) then
		return
	end

	-- draw all areas
	for k, v in pairs(ws.area.stored) do
		-- Guard against malformed entries from an attacker-shaped sync. (fw-plugins-net-6)
		if (!istable(v) or !v.startPosition or !v.endPosition) then
			continue
		end

		local properties = istable(v.properties) and v.properties or {}
		local center, min, max = self:GetLocalAreaPosition(v.startPosition, v.endPosition)
		local color = ColorAlpha(properties.color or ws.config.Get("color"), 255)

		render.DrawWireframeBox(center, angle_zero, min, max, color)

		cam.Start2D()
			local centerScreen = center:ToScreen()
			local _, textHeight = draw.SimpleText(
				k, "BudgetLabel", centerScreen.x, centerScreen.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			if (v.type and v.type != "area") then
				draw.SimpleText(
					"(" .. L(v.type) .. ")", "BudgetLabel",
					centerScreen.x, centerScreen.y + textHeight, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
				)
			end
		cam.End2D()
	end

	-- draw currently edited area
	if (self.editStart) then
		local center, min, max = self:GetLocalAreaPosition(self.editStart, self:GetPlayerAreaTrace().HitPos)
		local color = Color(255, 255, 255, 25 + (1 + math.sin(SysTime() * 6)) * 115)

		render.DrawWireframeBox(center, angle_zero, min, max, color)

		cam.Start2D()
			local centerScreen = center:ToScreen()

			draw.SimpleText(L("areaNew"), "BudgetLabel",
				centerScreen.x, centerScreen.y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cam.End2D()
	end
end

function PLUGIN:EditRightClick()
	if (self.editStart) then
		self.editStart = nil
	else
		self:StopEditing()
	end
end

function PLUGIN:EditClick()
	if (!self.editStart) then
		self.editStart = LocalPlayer():GetEyeTraceNoCursor().HitPos
	elseif (self.editStart and !self.editProperties) then
		self.editProperties = true

		local panel = vgui.Create("wsAreaEdit")
		panel:MakePopup()
	end
end

function PLUGIN:EditReload()
	if (self.editStart) then
		return
	end

	local id = LocalPlayer():GetArea()
	local area = ws.area.stored[id]

	if (!area) then
		return
	end

	Derma_Query(L("areaDeleteConfirm", id), L("areaDelete"),
		L("no"), nil,
		L("yes"), function()
			-- No item/target; the id string goes through writeExtra to match server read().
			ws.action.Send("wsAreaRemove", nil, nil, function()
				net.WriteString(id)
			end)
		end
	)
end

function PLUGIN:ShouldDisplayArea(id)
	if (ws.area.bEditing) then
		return false
	end
end

function PLUGIN:OnAreaChanged(oldID, newID)
	local client = LocalPlayer()
	client.wsArea = newID

	local area = ws.area.stored[newID]

	-- Guard against a malformed/missing entry from an attacker-shaped sync. (fw-plugins-net-6)
	if (!istable(area) or !istable(area.properties)) then
		client.wsInArea = false
		return
	end

	client.wsInArea = true

	if (hook.Run("ShouldDisplayArea", newID) == false or !area.properties.display) then
		return
	end

	local format = newID .. (ws.option.Get("24hourTime", false) and ", %H:%M." or ", %I:%M %p.")
	format = ws.date.GetFormatted(format)

	self.panel:AddEntry(format, area.properties.color)
end

net.Receive("wsAreaEditStart", function()
	PLUGIN:StartEditing()
end)

net.Receive("wsAreaEditEnd", function()
	PLUGIN:StopEditing()
end)

net.Receive("wsAreaAdd", function()
	local name = net.ReadString()
	local type = net.ReadString()
	local startPosition, endPosition = net.ReadVector(), net.ReadVector()
	local properties = net.ReadTable()

	if (name != "") then
		ws.area.stored[name] = {
			type = type,
			startPosition = startPosition,
			endPosition = endPosition,
			properties = istable(properties) and properties or {} -- (fw-plugins-net-6)
		}
	end
end)

net.Receive("wsAreaRemove", function()
	local name = net.ReadString()

	if (ws.area.stored[name]) then
		ws.area.stored[name] = nil
	end
end)

net.Receive("wsAreaSync", function()
	local length = net.ReadUInt(32)
	local data = net.ReadData(length)
	local uncompressed = util.Decompress(data)

	if (!uncompressed) then
		ErrorNoHalt("[Windswept] Unable to decompress area data!\n")
		return
	end

	-- Set the list of texts to the ones provided by the server. Guard against a
	-- malformed/non-table payload so renderers don't index a nil. (fw-plugins-net-6)
	local stored = util.JSONToTable(uncompressed)

	if (!istable(stored)) then
		ErrorNoHalt("[Windswept] Received malformed area data!\n")
		return
	end

	ws.area.stored = stored
end)

net.Receive("wsAreaChanged", function()
	local oldID, newID = net.ReadString(), net.ReadString()

	hook.Run("OnAreaChanged", oldID, newID)
end)
