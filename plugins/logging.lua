
PLUGIN.name = "Logging"
PLUGIN.author = "Black Tea"
PLUGIN.description = "You can modfiy the logging text/lists on this plugin."

if (SERVER) then
	local L = Format

	ws.log.AddType("chat", function(client, ...)
		local arg = {...}
		return L("[%s] %s: %s", arg[1], client:Name(), arg[2])
	end)

	ws.log.AddType("command", function(client, ...)
		local arg = {...}

		if (arg[2] and #arg[2] > 0) then
			return L("%s used command '%s %s'.", client:Name(), arg[1], arg[2])
		else
			return L("%s used command '%s'.", client:Name(), arg[1])
		end
	end)

	ws.log.AddType("cfgSet", function(client, ...)
		local arg = {...}
		return L("%s set %s to '%s'.", client:Name(), arg[1], arg[2])
	end, FLAG_DANGER)

	ws.log.AddType("connect", function(client, ...)
		return L("%s has connected.", client:SteamName())
	end, FLAG_NORMAL)

	ws.log.AddType("disconnect", function(client, ...)
		if (client:IsTimingOut()) then
			return L("%s (%s) has disconnected (timed out).", client:SteamName(), client:SteamID())
		else
			return L("%s (%s) has disconnected.", client:SteamName(), client:SteamID())
		end
	end, FLAG_NORMAL)

	ws.log.AddType("charCreate", function(client, ...)
		local arg = {...}
		return L("%s created the character '%s'", client:SteamName(), arg[1])
	end, FLAG_SERVER)

	ws.log.AddType("charLoad", function(client, ...)
		local arg = {...}
		return L("%s loaded the character '%s'", client:SteamName(), arg[1])
	end, FLAG_SERVER)

	ws.log.AddType("charDelete", function(client, ...)
		local arg = {...}
		return L("%s (%s) deleted character '%s'", client:SteamName(), client:SteamID(), arg[1])
	end, FLAG_SERVER)

	ws.log.AddType("itemAction", function(client, ...)
		local arg = {...}
		local item = arg[2]
		return L("%s ran '%s' on item '%s' (#%s)", client:Name(), arg[1], item:GetName(), item:GetID())
	end, FLAG_NORMAL)

	ws.log.AddType("itemDestroy", function(client, itemName, itemID)
		local name = client:GetName() ~= "" and client:GetName() or client:GetClass()
		return L("%s destroyed a '%s' #%d.", name, itemName, itemID)
	end, FLAG_WARNING)

	ws.log.AddType("shipmentTake", function(client, ...)
		local arg = {...}
		return L("%s took '%s' from the shipment", client:Name(), arg[1])
	end, FLAG_WARNING)

	ws.log.AddType("shipmentOrder", function(client, ...)
		return L("%s ordered a shipment", client:Name())
	end, FLAG_SUCCESS)

	ws.log.AddType("buy", function(client, ...)
		local arg = {...}
		return L("%s purchased '%s' from the NPC", client:Name(), arg[1])
	end, FLAG_SUCCESS)

	ws.log.AddType("buydoor", function(client, ...)
		return L("%s has purchased a door.", client:Name())
	end, FLAG_SUCCESS)

	ws.log.AddType("selldoor", function(client, ...)
		return L("%s has sold a door.", client:Name())
	end, FLAG_SUCCESS)

	ws.log.AddType("playerHurt", function(client, ...)
		local arg = {...}
		return L("%s has taken %d damage from %s.", client:Name(), arg[1], arg[2])
	end, FLAG_WARNING)

	ws.log.AddType("playerDeath", function(client, ...)
		local arg = {...}
		return L("%s has killed %s%s.", arg[1], client:Name(), arg[2] and (" with " .. arg[2]) or "")
	end, FLAG_DANGER)

	ws.log.AddType("money", function(client, amount)
		return L("%s has %s %s.", client:Name(), amount < 0 and "lost" or "gained", ws.currency.Get(math.abs(amount)))
	end, FLAG_SUCCESS)

	ws.log.AddType("inventoryAdd", function(client, characterName, itemName, itemID)
		return L("%s has gained a '%s' #%d.", characterName, itemName, itemID)
	end, FLAG_WARNING)

	ws.log.AddType("inventoryRemove", function(client, characterName, itemName, itemID)
		return L("%s has lost a '%s' #%d.", characterName, itemName, itemID)
	end, FLAG_WARNING)

	ws.log.AddType("storageMoneyTake", function(client, entity, amount, total)
		local name = entity.GetDisplayName and entity:GetDisplayName() or entity:GetName()

		return string.format("%s has taken %d %s from '%s' #%d (%d %s left).",
			client:GetName(), amount, ws.currency.plural, name,
			entity:GetInventory():GetID(), total, ws.currency.plural)
	end)

	ws.log.AddType("storageMoneyGive", function(client, entity, amount, total)
		local name = entity.GetDisplayName and entity:GetDisplayName() or entity:GetName()

		return string.format("%s has given %d %s to '%s' #%d (%d %s left).",
			client:GetName(), amount, ws.currency.plural, name,
			entity:GetInventory():GetID(), total, ws.currency.plural)
	end)

	ws.log.AddType("roll", function(client, value, max)
		return string.format("%s rolled %d out of %d.", client:Name(), value, max)
	end)

	ws.log.AddType("pluginLoaded", function(client, uniqueID)
		return string.format("%s has enabled the %s plugin for next restart.", client:GetName(), uniqueID)
	end)

	ws.log.AddType("pluginUnloaded", function(client, uniqueID)
		return string.format("%s has disabled the %s plugin for next restart.", client:GetName(), uniqueID)
	end)

	function PLUGIN:PlayerInitialSpawn(client)
		ws.log.Add(client, "connect")
	end

	function PLUGIN:PlayerDisconnected(client)
		ws.log.Add(client, "disconnect")
	end

	function PLUGIN:OnCharacterCreated(client, character)
		ws.log.Add(client, "charCreate", character:GetName())
	end

	function PLUGIN:CharacterLoaded(character)
		local client = character:GetPlayer()
		ws.log.Add(client, "charLoad", character:GetName())
	end

	function PLUGIN:PreCharacterDeleted(client, character)
		ws.log.Add(client, "charDelete", character:GetName())
	end

	function PLUGIN:ShipmentItemTaken(client, itemClass, amount)
		local itemTable = ws.item.list[itemClass]
		ws.log.Add(client, "shipmentTake", itemTable:GetName())
	end

	function PLUGIN:CreateShipment(client, shipmentEntity)
		ws.log.Add(client, "shipmentOrder")
	end

	function PLUGIN:CharacterVendorTraded(client, vendor, x, y, invID, price, isSell)
	end

	function PLUGIN:PlayerInteractItem(client, action, item)
		if (isentity(item)) then
			if (IsValid(item)) then
				local itemID = item.wsItemID
				item = ws.item.instances[itemID]
			else
				return
			end
		elseif (isnumber(item)) then
			item = ws.item.instances[item]
		end

		if (!item) then
			return
		end

		ws.log.Add(client, "itemAction", action, item)
	end

	function PLUGIN:InventoryItemAdded(oldInv, inventory, item)
		if (!inventory.owner or (oldInv and oldInv.owner == inventory.owner)) then
			return
		end

		local character = ws.char.loaded[inventory.owner]

		ws.log.Add(character:GetPlayer(), "inventoryAdd", character:GetName(), item:GetName(), item:GetID())

		if (item.isBag) then
			local bagInventory = item:GetInventory()

			if (!bagInventory) then
				return
			end

			for k, _ in bagInventory:Iter() do
				ws.log.Add(character:GetPlayer(), "inventoryAdd", character:GetName(), k:GetName(), k:GetID())
			end
		end
	end

	function PLUGIN:InventoryItemRemoved(inventory, item)
		if (!inventory.owner) then
			return
		end

		local character = ws.char.loaded[inventory.owner]

		ws.log.Add(character:GetPlayer(), "inventoryRemove", character:GetName(), item:GetName(), item:GetID())

		if (item.isBag) then
			for k, _ in item:GetInventory():Iter() do
				ws.log.Add(character:GetPlayer(), "inventoryRemove", character:GetName(), k:GetName(), k:GetID())
			end
		end
	end
end
