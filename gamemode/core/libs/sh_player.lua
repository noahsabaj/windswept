local playerMeta = FindMetaTable("Player")

-- wsData information for the player.
do
	if (SERVER) then
		function playerMeta:GetData(key, default)
			if (key == true) then
				return self.wsData
			end

			local data = self.wsData and self.wsData[key]

			if (data == nil) then
				return default
			else
				return data
			end
		end
	else
		function playerMeta:GetData(key, default)
			local data = ws.localData and ws.localData[key]

			if (data == nil) then
				return default
			else
				return data
			end
		end

		net.Receive("wsDataSync", function()
			ws.localData = net.ReadTable()
			ws.playTime = net.ReadUInt(32)
		end)

		net.Receive("wsData", function()
			ws.localData = ws.localData or {}
			ws.localData[net.ReadString()] = net.ReadType()
		end)
	end
end

-- Whitelist networking information here.
do
	function playerMeta:HasWhitelist(faction)
		-- Factionless is always allowed
		if (faction == nil) then
			return true
		end

		local data = ws.faction.indices[faction]

		if (data) then
			if (data.isDefault) then
				return true
			end

			local wsData = self:GetData("whitelists", {})

			return wsData[Schema.folder] and wsData[Schema.folder][data.uniqueID] == true or false
		end

		return false
	end

	function playerMeta:GetItems()
		local char = self:GetCharacter()

		if (char) then
			local inv = char:GetInventory()

			if (inv) then
				return inv:GetItems()
			end
		end
	end

	function playerMeta:GetClassData()
		local char = self:GetCharacter()

		if (char) then
			local class = char:GetClass()

			if (class) then
				local classData = ws.class.list[class]

				return classData
			end
		end
	end
end

do
	if (SERVER) then
		util.AddNetworkString("PlayerModelChanged")
		util.AddNetworkString("PlayerSelectWeapon")

		local entityMeta = FindMetaTable("Entity")

		entityMeta.wsSetModel = entityMeta.wsSetModel or entityMeta.SetModel
		playerMeta.wsSelectWeapon = playerMeta.wsSelectWeapon or playerMeta.SelectWeapon

		function entityMeta:SetModel(model)
			local oldModel = self:GetModel()

			if (self:IsPlayer()) then
				hook.Run("PlayerModelChanged", self, model, oldModel)

				net.Start("PlayerModelChanged")
					net.WriteEntity(self)
					net.WriteString(model)
					net.WriteString(oldModel)
				net.Broadcast()
			end

			return self:wsSetModel(model)
		end

		function playerMeta:SelectWeapon(className)
			net.Start("PlayerSelectWeapon")
				net.WriteEntity(self)
				net.WriteString(className)
			net.Broadcast()

			return self:wsSelectWeapon(className)
		end
	else
		net.Receive("PlayerModelChanged", function(length)
			hook.Run("PlayerModelChanged", net.ReadEntity(), net.ReadString(), net.ReadString())
		end)

		net.Receive("PlayerSelectWeapon", function(length)
			local client = net.ReadEntity()
			local className = net.ReadString()

			if (!IsValid(client)) then
				hook.Run("PlayerWeaponChanged", client, NULL)
				return
			end

			for _, v in ipairs(client:GetWeapons()) do
				if (v:GetClass() == className) then
					hook.Run("PlayerWeaponChanged", client, v)
					break
				end
			end
		end)
	end
end
