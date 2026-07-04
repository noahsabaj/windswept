
ws.command.Add("Roll", {
	description = "@cmdRoll",
	arguments = bit.bor(ws.type.number, ws.type.optional),
	OnRun = function(self, client, maximum)
		maximum = math.Clamp(maximum or 100, 0, 1000000)

		local value = math.random(0, maximum)

		ws.chat.Send(client, "roll", tostring(value), nil, nil, {
			max = maximum
		})

		ws.log.Add(client, "roll", value, maximum)
	end
})

ws.command.Add("Event", {
	description = "@cmdEvent",
	arguments = ws.type.text,
	superAdminOnly = true,
	OnRun = function(self, client, text)
		ws.chat.Send(client, "event", text)
	end
})

ws.command.Add("CharGiveFlag", {
	description = "@cmdCharGiveFlag",
	privilege = "Manage Character Flags",
	superAdminOnly = true,
	arguments = {
		ws.type.character,
		bit.bor(ws.type.string, ws.type.optional)
	},
	OnRun = function(self, client, target, flags)
		-- show string request if no flags are specified
		if (!flags) then
			local available = ""

			-- sort and display flags the character already has
			for k, _ in SortedPairs(ws.flag.list) do
				if (!target:HasFlags(k)) then
					available = available .. k
				end
			end

			return client:RequestString("@flagGiveTitle", "@cmdCharGiveFlag", function(text)
				ws.command.Run(client, "CharGiveFlag", {target:GetName(), text})
			end, available)
		end

		target:GiveFlags(flags)

		-- Fog of war: the named phrase goes to command-privileged admins only. The target
		-- still learns what happened to them via a nameless variant -- never the acting
		-- admin's character name. Same pattern for every admin char command below. (#74)
		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("flagGive", client:GetName(), target:GetName(), flags)
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("flagGiveTarget", flags)
			end
		end
	end
})

ws.command.Add("CharTakeFlag", {
	description = "@cmdCharTakeFlag",
	privilege = "Manage Character Flags",
	superAdminOnly = true,
	arguments = {
		ws.type.character,
		bit.bor(ws.type.string, ws.type.optional)
	},
	OnRun = function(self, client, target, flags)
		if (!flags) then
			return client:RequestString("@flagTakeTitle", "@cmdCharTakeFlag", function(text)
				ws.command.Run(client, "CharTakeFlag", {target:GetName(), text})
			end, target:GetFlags())
		end

		target:TakeFlags(flags)

		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("flagTake", client:GetName(), flags, target:GetName())
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("flagTakeTarget", flags)
			end
		end
	end
})

ws.command.Add("ToggleRaise", {
	description = "@cmdToggleRaise",
	OnRun = function(self, client, arguments)
		if (!timer.Exists("wsToggleRaise" .. client:SteamID())) then
			timer.Create("wsToggleRaise" .. client:SteamID(), ws.config.Get("weaponRaiseTime"), 1, function()
				client:ToggleWepRaised()
			end)
		end
	end
})

ws.command.Add("CharSetModel", {
	description = "@cmdCharSetModel",
	superAdminOnly = true,
	arguments = {
		ws.type.character,
		ws.type.string
	},
	OnRun = function(self, client, target, model)
		target:SetModel(model)
		target:GetPlayer():SetupHands()

		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("cChangeModel", client:GetName(), target:GetName(), model)
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("cChangeModelTarget", model)
			end
		end
	end
})

ws.command.Add("CharSetSkin", {
	description = "@cmdCharSetSkin",
	adminOnly = true,
	arguments = {
		ws.type.character,
		bit.bor(ws.type.number, ws.type.optional)
	},
	OnRun = function(self, client, target, skin)
		target:SetData("skin", skin)
		target:GetPlayer():SetSkin(skin or 0)

		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("cChangeSkin", client:GetName(), target:GetName(), skin or 0)
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("cChangeSkinTarget", skin or 0)
			end
		end
	end
})

ws.command.Add("CharSetBodygroup", {
	description = "@cmdCharSetBodygroup",
	adminOnly = true,
	arguments = {
		ws.type.character,
		ws.type.string,
		bit.bor(ws.type.number, ws.type.optional)
	},
	OnRun = function(self, client, target, bodygroup, value)
		local index = target:GetPlayer():FindBodygroupByName(bodygroup)

		if (index > -1) then
			if (value and value < 1) then
				value = nil
			end

			local groups = target:GetData("groups", {})
				groups[index] = value
			target:SetData("groups", groups)
			target:GetPlayer():SetBodygroup(index, value or 0)

			-- Was a full net.Broadcast (nil recipient) -- the only bodygroup command that
			-- told every client. Scoped like its siblings. (#74)
			for _, v in player.Iterator() do
				if (self:OnCheckAccess(v)) then
					v:NotifyLocalized("cChangeGroups", client:GetName(), target:GetName(), bodygroup, value or 0)
				elseif (v == target:GetPlayer()) then
					v:NotifyLocalized("cChangeGroupsTarget", bodygroup, value or 0)
				end
			end
		else
			return "@invalidArg", 2
		end
	end
})

ws.command.Add("CharSetAttribute", {
	description = "@cmdCharSetAttribute",
	privilege = "Manage Character Attributes",
	adminOnly = true,
	arguments = {
		ws.type.character,
		ws.type.string,
		ws.type.number
	},
	OnRun = function(self, client, target, attributeName, level)
		for k, v in pairs(ws.attributes.list) do
			if (ws.util.StringMatches(L(v.name, client), attributeName) or ws.util.StringMatches(k, attributeName)) then
				target:SetAttrib(k, math.abs(level))
				return "@attributeSet", target:GetName(), L(v.name, client), math.abs(level)
			end
		end

		return "@attributeNotFound"
	end
})

ws.command.Add("CharAddAttribute", {
	description = "@cmdCharAddAttribute",
	privilege = "Manage Character Attributes",
	adminOnly = true,
	arguments = {
		ws.type.character,
		ws.type.string,
		ws.type.number
	},
	OnRun = function(self, client, target, attributeName, level)
		for k, v in pairs(ws.attributes.list) do
			if (ws.util.StringMatches(L(v.name, client), attributeName) or ws.util.StringMatches(k, attributeName)) then
				target:UpdateAttrib(k, math.abs(level))
				return "@attributeUpdate", target:GetName(), L(v.name, client), math.abs(level)
			end
		end

		return "@attributeNotFound"
	end
})

ws.command.Add("CharSetName", {
	description = "@cmdCharSetName",
	adminOnly = true,
	arguments = {
		ws.type.character,
		bit.bor(ws.type.text, ws.type.optional)
	},
	OnRun = function(self, client, target, newName)
		-- display string request panel if no name was specified
		if (newName:len() == 0) then
			return client:RequestString("@chgName", "@chgNameDesc", function(text)
				ws.command.Run(client, "CharSetName", {target:GetName(), text})
			end, target:GetName())
		end

		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("cChangeName", client:GetName(), target:GetName(), newName)
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("cChangeNameTarget", newName)
			end
		end

		target:SetName(newName:gsub("#", "#​"))
	end
})

ws.command.Add("CharGiveItem", {
	description = "@cmdCharGiveItem",
	superAdminOnly = true,
	arguments = {
		ws.type.character,
		ws.type.string,
		bit.bor(ws.type.number, ws.type.optional)
	},
	OnRun = function(self, client, target, item, amount)
		local uniqueID = item:lower()

		if (!ws.item.list[uniqueID]) then
			for k, v in SortedPairs(ws.item.list) do
				if (ws.util.StringMatches(v.name, uniqueID)) then
					uniqueID = k

					break
				end
			end
		end

		local itemTable = ws.item.list[uniqueID]
		if (!itemTable) then
			return "@invalidItem"
		end

		amount = amount or 1

		-- Handle currency items specially - use stacking system
		if (itemTable.isCurrency and ws.currency) then
			local cents = amount * (itemTable.currencyValue or 1)
			local bSuccess = target:GiveMoney(cents)

			if (bSuccess) then
				target:GetPlayer():NotifyLocalized("itemCreated")

				if (target != client:GetCharacter()) then
					return "@itemCreated"
				end
			else
				return "@inventoryFull"
			end
		else
			-- Standard item handling
			local bSuccess, error = target:GetInventory():Add(uniqueID, amount)

			if (bSuccess) then
				target:GetPlayer():NotifyLocalized("itemCreated")

				if (target != client:GetCharacter()) then
					return "@itemCreated"
				end
			else
				return "@" .. tostring(error)
			end
		end
	end
})

ws.command.Add("CharKick", {
	description = "@cmdCharKick",
	adminOnly = true,
	arguments = ws.type.character,
	OnRun = function(self, client, target)
		target:Save(function()
			target:Kick()
		end)

		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("charKick", client:GetName(), target:GetName())
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("charKickTarget")
			end
		end
	end
})

ws.command.Add("CharBan", {
	description = "@cmdCharBan",
	privilege = "Ban Character",
	arguments = {
		ws.type.character,
		bit.bor(ws.type.number, ws.type.optional)
	},
	adminOnly = true,
	OnRun = function(self, client, target, minutes)
		if (minutes) then
			minutes = minutes * 60
		end

		target:Ban(minutes)
		target:Save()

		for _, v in player.Iterator() do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("charBan", client:GetName(), target:GetName())
			elseif (v == target:GetPlayer()) then
				v:NotifyLocalized("charBanTarget")
			end
		end
	end
})

ws.command.Add("CharUnban", {
	description = "@cmdCharUnban",
	privilege = "Ban Character",
	arguments = ws.type.text,
	adminOnly = true,
	OnRun = function(self, client, name)
		if ((client.wsNextSearch or 0) >= CurTime()) then
			return L("charSearching", client)
		end

		for _, v in pairs(ws.char.loaded) do
			if (ws.util.StringMatches(v:GetName(), name)) then
				if (v:GetData("banned")) then
					v:SetData("banned")
				else
					return "@charNotBanned"
				end

				for _, v2 in player.Iterator() do
					if (self:OnCheckAccess(v2)) then
						v2:NotifyLocalized("charUnBan", client:GetName(), v:GetName())
					elseif (v2 == v:GetPlayer()) then
						v2:NotifyLocalized("charUnBanTarget")
					end
				end

				return
			end
		end

		client.wsNextSearch = CurTime() + 15

		local query = mysql:Select("ws_characters")
			query:Select("id")
			query:Select("name")
			query:Select("data")
			query:WhereLike("name", name)
			query:Limit(1)
			query:Callback(function(result)
				if (istable(result) and #result > 0) then
					local characterID = tonumber(result[1].id)
					local data = util.JSONToTable(result[1].data or "[]")
					name = result[1].name

					client.wsNextSearch = 0

					if (!data.banned) then
						return client:NotifyLocalized("charNotBanned")
					end

					data.banned = nil

					local updateQuery = mysql:Update("ws_characters")
						updateQuery:Update("data", util.TableToJSON(data))
						updateQuery:Where("id", characterID)
					updateQuery:Execute()

					for _, v in player.Iterator() do
						if (self:OnCheckAccess(v)) then
							v:NotifyLocalized("charUnBan", client:GetName(), name)
						end
					end
				end
			end)
		query:Execute()
	end
})

do
	hook.Add("InitializedConfig", "wsMoneyCommands", function()
		local MONEY_NAME = string.gsub(ws.util.ExpandCamelCase(ws.currency.plural), "%s", "")

		ws.command.Add("Give" .. MONEY_NAME, {
			alias = {"GiveMoney"},
			description = "@cmdGiveMoney",
			arguments = ws.type.number,
			OnRun = function(self, client, amount)
				-- User enters dollars, internal system uses cents
				amount = math.floor(amount)

				if (amount <= 0) then
					return L("invalidArg", client, 1)
				end

				local data = {}
					data.start = client:GetShootPos()
					data.endpos = data.start + client:GetAimVector() * 96
					data.filter = client
				local target = util.TraceLine(data).Entity

				if (IsValid(target) and target:IsPlayer() and target:GetCharacter()) then
					local cents = amount * ws.currency.CENTS_PER_DOLLAR
					local giverChar = client:GetCharacter()

					if (!giverChar:HasMoney(cents)) then
						return
					end

					-- Debit the giver FIRST and only credit the target if it succeeded; a failed
					-- removal (e.g. can't make change in a full inventory) would otherwise mint
					-- money since the target was already credited. (fw-currency-economy-5)
					if (!giverChar:TakeMoney(cents)) then
						client:NotifyLocalized("inventoryFull")
						return
					end

					-- Target had no room; refund the giver so money isn't destroyed.
					if (!target:GetCharacter():GiveMoney(cents)) then
						giverChar:GiveMoney(cents)
						client:NotifyLocalized("inventoryFull")
						return
					end

					target:NotifyLocalized("moneyTaken", ws.currency.Get(cents))
					client:NotifyLocalized("moneyGiven", ws.currency.Get(cents))
				end
			end
		})

		ws.command.Add("CharSet" .. MONEY_NAME, {
			alias = {"CharSetMoney"},
			description = "@cmdCharSetMoney",
			superAdminOnly = true,
			arguments = {
				ws.type.character,
				ws.type.number
			},
			OnRun = function(self, client, target, amount)
				-- User enters dollars, internal system uses cents. Floor (not round) so the
				-- set amount never exceeds what was typed, consistent with Give/Drop.
				-- (fw-config-command-boot-12)
				amount = math.floor(amount)

				if (amount <= 0) then
					return "@invalidArg", 2
				end

				local cents = amount * ws.currency.CENTS_PER_DOLLAR
				target:SetMoney(cents)
				client:NotifyLocalized("setMoney", target:GetName(), ws.currency.Get(cents))
			end
		})

		ws.command.Add("Drop" .. MONEY_NAME, {
			alias = {"DropMoney"},
			description = "@cmdDropMoney",
			arguments = ws.type.number,
			OnRun = function(self, client, amount)
				-- User enters dollars, internal system uses cents. Floor (not round) so a player
				-- never drops more than they typed. (fw-config-command-boot-12)
				amount = math.floor(amount)

				local minDropAmount = ws.config.Get("minMoneyDropAmount", 1)

				if (amount < minDropAmount) then
					return "@belowMinMoneyDrop", minDropAmount
				end

				-- Convert to cents for internal checks
				local cents = amount * ws.currency.CENTS_PER_DOLLAR

				local character = client:GetCharacter()

				if (!character:HasMoney(cents)) then
					return "@insufficientMoney"
				end

				-- Only spawn the pickup if the money was actually removed; a failed removal
				-- would otherwise mint a free money entity. (fw-currency-economy-5 / cons-2)
				if (!character:TakeMoney(cents)) then
					client:NotifyLocalized("inventoryFull")
					return
				end

				-- Spawn money entity (amount in dollars for ws.currency.Spawn)
				local money = ws.currency.Spawn(client, amount)
				money.wsCharID = character:GetID()
				money.wsSteamID = client:SteamID()
			end
		})
	end)
end

ws.command.Add("CharGetUp", {
	description = "@cmdCharGetUp",
	OnRun = function(self, client, arguments)
		local entity = client.wsRagdoll

		if (IsValid(entity) and entity.wsGrace and entity.wsGrace < CurTime() and
			entity:GetVelocity():Length2D() < 8 and !entity.wsWakingUp) then
			entity.wsWakingUp = true
			entity:CallOnRemove("CharGetUp", function()
				client:SetAction()
			end)

			client:SetAction("@gettingUp", 5, function()
				if (!IsValid(entity)) then
					return
				end

				hook.Run("OnCharacterGetup", client, entity)
				entity:Remove()
			end)
		end
	end
})

ws.command.Add("CharFallOver", {
	description = "@cmdCharFallOver",
	arguments = bit.bor(ws.type.number, ws.type.optional),
	OnRun = function(self, client, time)
		if (!client:Alive() or client:GetMoveType() == MOVETYPE_NOCLIP) then
			return "@notNow"
		end

		if (time and time > 0) then
			time = math.Clamp(time, 1, 60)
		end

		if (!IsValid(client.wsRagdoll)) then
			client:SetRagdolled(true, time)
		end
	end
})

ws.command.Add("CharDesc", {
	description = "@cmdCharDesc",
	arguments = bit.bor(ws.type.text, ws.type.optional),
	OnRun = function(self, client, description)
		if (!description:find("%S")) then
			return client:RequestString("@cmdCharDescTitle", "@cmdCharDescDescription", function(text)
				ws.command.Run(client, "CharDesc", {text})
			end, client:GetCharacter():GetDescription())
		end

		local info = ws.char.vars.description
		local result, fault, count = info:OnValidate(description)

		if (result == false) then
			return "@" .. fault, count
		end

		client:GetCharacter():SetDescription(description)
		return "@descChanged"
	end
})

ws.command.Add("MapRestart", {
	description = "@cmdMapRestart",
	adminOnly = true,
	arguments = bit.bor(ws.type.number, ws.type.optional),
	OnRun = function(self, client, delay)
		delay = delay or 10
		ws.util.NotifyLocalized("mapRestarting", nil, delay)

		timer.Simple(delay, function()
			RunConsoleCommand("changelevel", game.GetMap())
		end)
	end
})
