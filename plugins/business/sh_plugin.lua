PLUGIN.name = "Business"
PLUGIN.author = "Windswept"
PLUGIN.description = "Order items via deliverable shipments. Off by default."

ws.business = ws.business or {}

-- Off by default: the business menu spawns items from nothing, which the physical-currency
-- economy avoids (items should come from vendors / crafting / players). A schema opts in via
-- this config. Relocated from framework core into this plugin. (layer-7)
ws.config.Add("businessEnabled", false, "Enables the business/shipment ordering menu.")

if (SERVER) then
	util.AddNetworkString("wsBusinessBuy")
	util.AddNetworkString("wsBusinessResponse")
	util.AddNetworkString("wsShipmentUse")
	util.AddNetworkString("wsShipmentOpen")
	util.AddNetworkString("wsShipmentClose")

	net.Receive("wsBusinessBuy", function(length, client)
		-- Off unless the schema enables it (spawns items from nothing). (layer-7)
		if (!ws.config.Get("businessEnabled")) then
			client:NotifyLocalized("businessDisabled")
			return
		end

		if (client.wsNextBusiness and client.wsNextBusiness > CurTime()) then
			client:NotifyLocalized("businessTooFast")
			return
		end

		local char = client:GetCharacter()

		if (!char) then
			return
		end

		-- Overall caps so a crafted payload (or a huge admin/item price) can't request an
		-- unbounded number of distinct items or run up an unbounded shipment cost. (fw-currency-economy-7)
		local MAX_DISTINCT_ITEMS = 16
		local MAX_TOTAL_COST = 1000000

		local indicies = math.min(net.ReadUInt(8), MAX_DISTINCT_ITEMS)
		local items = {}

		for _ = 1, indicies do
			items[net.ReadString()] = net.ReadUInt(8)
		end

		if (table.IsEmpty(items)) then
			return
		end

		local cost = 0

		for k, v in pairs(items) do
			local itemTable = ws.item.list[k]

			if (itemTable and hook.Run("CanPlayerUseBusiness", client, k) != false) then
				local amount = math.Clamp(tonumber(v) or 0, 0, 10)
				items[k] = amount

				if (amount == 0) then
					items[k] = nil
				else
					cost = cost + (amount * (itemTable.price or 0))
				end
			else
				items[k] = nil
			end
		end

		if (table.IsEmpty(items)) then
			return
		end

		-- Reject the whole order if it exceeds the total-cost ceiling. (fw-currency-economy-7)
		if (cost > MAX_TOTAL_COST) then
			return
		end

		if (char:HasMoney(cost)) then
			-- Abort if the money can't actually be removed (e.g. can't make change in a full
			-- inventory), or the player would get a free shipment. (fw-currency-economy-5 ripple)
			if (!char:TakeMoney(cost)) then
				return
			end

			local entity = ents.Create("ws_shipment")
			entity:Spawn()
			entity:SetPos(client:GetItemDropPos(entity))
			entity:SetItems(items)
			entity:SetNetVar("owner", char:GetID())

			local shipments = char:GetVar("charEnts") or {}
			table.insert(shipments, entity)
			char:SetVar("charEnts", shipments, true)

			net.Start("wsBusinessResponse")
			net.Send(client)

			hook.Run("CreateShipment", client, entity)

			client.wsNextBusiness = CurTime() + 0.5
		end
	end)

	net.Receive("wsShipmentUse", function(length, client)
		local uniqueID = net.ReadString()
		local drop = net.ReadBool()

		local entity = client.wsShipment
		local itemTable = ws.item.list[uniqueID]

		if (itemTable and IsValid(entity)) then
			-- Range check via ws.access (interaction range) instead of a magic 128u. (fw-currency-economy-8)
			if (!ws.access.CanInteract(client, entity)) then
				client.wsShipment = nil

				return
			end

			local amount = entity.items[uniqueID]

			-- The dead inner `entity.items[uniqueID] <= 0` branch was removed; the
			-- post-decrement GetItemCount() < 1 check below cleans up the shipment. (tb-7)
			if (amount and amount > 0) then
				if (drop) then
					ws.item.Spawn(uniqueID, entity:GetPos() + Vector(0, 0, 16), function(item, itemEntity)
						if (IsValid(client)) then
							itemEntity.wsSteamID = client:SteamID()
							itemEntity.wsCharID = client:GetCharacter():GetID()
						end
					end)
				else
					local status, _ = client:GetCharacter():GetInventory():Add(uniqueID)

					if (!status) then
						return client:NotifyLocalized("noFit")
					end
				end

				hook.Run("ShipmentItemTaken", client, uniqueID, amount)

				entity.items[uniqueID] = entity.items[uniqueID] - 1

				if (entity:GetItemCount() < 1) then
					entity:GibBreakServer(Vector(0, 0, 0.5))
					entity:Remove()
				end
			end
		end
	end)

	net.Receive("wsShipmentClose", function(length, client)
		local entity = client.wsShipment

		if (IsValid(entity)) then
			entity.wsInteractionDirty = false
			client.wsShipment = nil
		end
	end)
else
	net.Receive("wsShipmentOpen", function()
		local entity = net.ReadEntity()
		local items = net.ReadTable()

		ws.gui.shipment = vgui.Create("wsShipment")
		ws.gui.shipment:SetItems(entity, items)
	end)
end
