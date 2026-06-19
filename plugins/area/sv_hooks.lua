
function PLUGIN:LoadData()
	hook.Run("SetupAreaProperties")
	ws.area.stored = self:GetData() or {}

	timer.Create("wsAreaThink", ws.config.Get("areaTickTime"), 0, function()
		self:AreaThink()
	end)
end

function PLUGIN:SaveData()
	self:SetData(ws.area.stored)
end

function PLUGIN:PlayerInitialSpawn(client)
	timer.Simple(1, function()
		if (IsValid(client)) then
			local json = util.TableToJSON(ws.area.stored)
			local compressed = util.Compress(json)
			local length = compressed:len()

			net.Start("wsAreaSync")
				net.WriteUInt(length, 32)
				net.WriteData(compressed, length)
			net.Send(client)
		end
	end)
end

function PLUGIN:PlayerLoadedCharacter(client)
	client.wsArea = ""
	client.wsInArea = nil
end

function PLUGIN:PlayerSpawn(client)
	client.wsArea = ""
	client.wsInArea = nil
end

function PLUGIN:AreaThink()
	for _, client in player.Iterator() do
		local character = client:GetCharacter()

		if (!client:Alive() or !character) then
			continue
		end

		local overlappingBoxes = {}
		local position = client:GetPos() + client:OBBCenter()

		for id, info in pairs(ws.area.stored) do
			if (position:WithinAABox(info.startPosition, info.endPosition)) then
				overlappingBoxes[#overlappingBoxes + 1] = id
			end
		end

		if (#overlappingBoxes > 0) then
			local oldID = client:GetArea()
			local id = overlappingBoxes[1]

			if (oldID != id) then
				hook.Run("OnPlayerAreaChanged", client, client.wsArea, id)
				client.wsArea = id
			end

			client.wsInArea = true
		else
			client.wsInArea = false
		end
	end
end

function PLUGIN:OnPlayerAreaChanged(client, oldID, newID)
	net.Start("wsAreaChanged")
		net.WriteString(oldID)
		net.WriteString(newID)
	net.Send(client)
end

net.Receive("wsAreaAdd", function(length, client)
	if (!client:Alive() or !CAMI.PlayerHasAccess(client, "Helix - AreaEdit", nil)) then
		return
	end

	local id = net.ReadString()
	local type = net.ReadString()
	local startPosition, endPosition = net.ReadVector(), net.ReadVector()
	local properties = net.ReadTable()

	if (!ws.area.types[type]) then
		client:NotifyLocalized("areaInvalidType")
		return
	end

	if (ws.area.stored[id]) then
		client:NotifyLocalized("areaAlreadyExists")
		return
	end

	for k, v in pairs(properties) do
		if (!isstring(k) or !ws.area.properties[k]) then
			continue
		end

		properties[k] = ws.util.SanitizeType(ws.area.properties[k].type, v)
	end

	ws.area.Create(id, type, startPosition, endPosition, nil, properties)
	ws.log.Add(client, "areaAdd", id)
end)

net.Receive("wsAreaRemove", function(length, client)
	if (!client:Alive() or !CAMI.PlayerHasAccess(client, "Helix - AreaEdit", nil)) then
		return
	end

	local id = net.ReadString()

	if (!ws.area.stored[id]) then
		client:NotifyLocalized("areaDoesntExist")
		return
	end

	ws.area.Remove(id)
	ws.log.Add(client, "areaRemove", id)
end)
