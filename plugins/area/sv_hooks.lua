
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

-- Admin world-editor add. No item/target; the admin gate (alive + CAMI) lives in
-- onValidate and the multi-field payload is read in read(). Migrated to ws.action so
-- the dispatch is guard-by-construction. (Client sender: derma/cl_areaedit.lua Submit.)
ws.action.Register("wsAreaAdd", {
	read = function()
		return {
			id = net.ReadString(),
			type = net.ReadString(),
			startPosition = net.ReadVector(),
			endPosition = net.ReadVector(),
			properties = net.ReadTable()
		}
	end,
	onValidate = function(client)
		-- Mirror the original gate exactly; return strict false on denial so a CAMI
		-- result of nil (some admin mods) is treated as deny, not allow. The wrapper
		-- only rejects on a literal false. (fw-plugins-net-5)
		if (!client:Alive() or !CAMI.PlayerHasAccess(client, "Windswept - AreaEdit", nil)) then
			return false
		end
	end,
	run = function(client, ctx)
		local data = ctx.data
		local type = data.type
		local startPosition, endPosition = data.startPosition, data.endPosition
		local properties = data.properties

		-- Clamp/reject the untrusted id: bound the length and require a non-empty id
		-- so a hostile client can't store a giant or blank key. (fw-plugins-net-5)
		local id = isstring(data.id) and data.id:utf8sub(1, 32) or ""

		if (id == "" or !id:find("%S")) then
			client:NotifyLocalized("areaInvalidType")
			return
		end

		if (!ws.area.types[type]) then
			client:NotifyLocalized("areaInvalidType")
			return
		end

		-- Reject non-finite or out-of-bounds vectors before storing them. (fw-plugins-net-5)
		local function isFiniteInWorld(vec)
			if (!isvector(vec)) then return false end

			for _, axis in ipairs({vec.x, vec.y, vec.z}) do
				-- NaN != itself; reject NaN and infinities, then bound to source map limits.
				if (axis != axis or math.abs(axis) > 16384) then
					return false
				end
			end

			return true
		end

		if (!isFiniteInWorld(startPosition) or !isFiniteInWorld(endPosition)) then
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
	end
})

-- Admin world-editor remove. No item/target; admin gate in onValidate, id payload in
-- read(). (Client sender: cl_hooks.lua EditReload.)
ws.action.Register("wsAreaRemove", {
	read = function()
		return net.ReadString()
	end,
	onValidate = function(client)
		-- Strict false on denial (see wsAreaAdd note). (fw-plugins-net-5)
		if (!client:Alive() or !CAMI.PlayerHasAccess(client, "Windswept - AreaEdit", nil)) then
			return false
		end
	end,
	run = function(client, ctx)
		local id = ctx.data

		if (!ws.area.stored[id]) then
			client:NotifyLocalized("areaDoesntExist")
			return
		end

		ws.area.Remove(id)
		ws.log.Add(client, "areaRemove", id)
	end
})
