local playerMeta = FindMetaTable("Player")

-- Player data (outside of characters) handling.
do
	util.AddNetworkString("wsData")
	util.AddNetworkString("wsDataSync")

	function playerMeta:LoadData(callback)
		local name = self:SteamName()
		local steamID64 = self:SteamID64()
		local timestamp = math.floor(os.time())
		local ip = self:IPAddress():match("%d+%.%d+%.%d+%.%d+")

		local query = mysql:Select("ix_players")
			query:Select("data")
			query:Select("play_time")
			query:Where("steamid", steamID64)
			query:Callback(function(result)
				if (IsValid(self) and istable(result) and #result > 0 and result[1].data) then
					local updateQuery = mysql:Update("ix_players")
						updateQuery:Update("last_join_time", timestamp)
						updateQuery:Update("address", ip)
						updateQuery:Where("steamid", steamID64)
					updateQuery:Execute()

					self.wsPlayTime = tonumber(result[1].play_time) or 0
					self.wsData = util.JSONToTable(result[1].data)

					if (callback) then
						callback(self.wsData)
					end
				else
					local insertQuery = mysql:Insert("ix_players")
						insertQuery:Insert("steamid", steamID64)
						insertQuery:Insert("steam_name", name)
						insertQuery:Insert("play_time", 0)
						insertQuery:Insert("address", ip)
						insertQuery:Insert("last_join_time", timestamp)
						insertQuery:Insert("data", util.TableToJSON({}))
					insertQuery:Execute()

					if (callback) then
						callback({})
					end
				end
			end)
		query:Execute()
	end

	function playerMeta:SaveData()
		if (self:IsBot()) then return end

		local name = self:SteamName()
		local steamID64 = self:SteamID64()

		local query = mysql:Update("ix_players")
			query:Update("steam_name", name)
			query:Update("play_time", math.floor((self.wsPlayTime or 0) + (RealTime() - (self.wsJoinTime or RealTime() - 1))))
			query:Update("data", util.TableToJSON(self.wsData))
			query:Where("steamid", steamID64)
		query:Execute()
	end

	function playerMeta:SetData(key, value, bNoNetworking)
		self.wsData = self.wsData or {}
		self.wsData[key] = value

		if (!bNoNetworking) then
			net.Start("wsData")
				net.WriteString(key)
				net.WriteType(value)
			net.Send(self)
		end
	end
end

-- Whitelisting information for the player.
do
	function playerMeta:SetWhitelisted(faction, whitelisted)
		if (!whitelisted) then
			whitelisted = nil
		end

		local data = ws.faction.indices[faction]

		if (data) then
			local whitelists = self:GetData("whitelists", {})
			whitelists[Schema.folder] = whitelists[Schema.folder] or {}
			whitelists[Schema.folder][data.uniqueID] = whitelisted and true or nil

			self:SetData("whitelists", whitelists)
			self:SaveData()

			return true
		end

		return false
	end
end

do
	playerMeta.wsGive = playerMeta.wsGive or playerMeta.Give

	function playerMeta:Give(className, bNoAmmo)
		local weapon

		self.wsWeaponGive = true
			weapon = self:wsGive(className, bNoAmmo)
		self.wsWeaponGive = nil

		return weapon
	end
end
