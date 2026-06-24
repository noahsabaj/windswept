
-- luacheck: globals VENDOR_BUY VENDOR_SELL VENDOR_BOTH VENDOR_PRICE
-- luacheck: globals VENDOR_STOCK VENDOR_MODE VENDOR_MAXSTOCK VENDOR_SELLANDBUY VENDOR_SELLONLY VENDOR_BUYONLY VENDOR_TEXT

local PLUGIN = PLUGIN

PLUGIN.name = "Vendors"
PLUGIN.author = "Chessnut"
PLUGIN.description = "Adds NPC vendors that can sell things."

-- Conservation is a framework default: a vendor must not mint money or items. With this
-- off (the default), a vendor can only BUY from a player out of a finite money pool and
-- only SELL items it has finite stock of -- an unbacked vendor (infinite money, or an
-- item with no max stock) is refused rather than conjuring cash/items from nowhere. Turn
-- it on for an admin-shop / sandbox economy that may mint freely. (cons / layer-vendor)
ws.config.Add("vendorAllowInfinite", false,
	"Lets vendors mint money/items (admin-shop mode). Off = conservation: finite money + stock required.")

CAMI.RegisterPrivilege({
	Name = "Windswept - Manage Vendors",
	MinAccess = "admin"
})

VENDOR_BUY = 1
VENDOR_SELL = 2
VENDOR_BOTH = 3

-- Keys for item information.
VENDOR_PRICE = 1
VENDOR_STOCK = 2
VENDOR_MODE = 3
VENDOR_MAXSTOCK = 4

-- Sell and buy the item.
VENDOR_SELLANDBUY = 1
-- Only sell the item to the player.
VENDOR_SELLONLY = 2
-- Only buy the item from the player.
VENDOR_BUYONLY = 3

if (SERVER) then
	util.AddNetworkString("wsVendorOpen")
	util.AddNetworkString("wsVendorClose")
	-- wsVendorTrade's networkstring is registered by ws.action.Register below.

	util.AddNetworkString("wsVendorEdit")
	util.AddNetworkString("wsVendorEditFinish")
	util.AddNetworkString("wsVendorEditor")
	util.AddNetworkString("wsVendorMoney")
	util.AddNetworkString("wsVendorStock")
	util.AddNetworkString("wsVendorAddItem")

	function PLUGIN:SaveData()
		local data = {}

		for _, entity in ipairs(ents.FindByClass("ws_vendor")) do
			local bodygroups = {}

			for _, v in ipairs(entity:GetBodyGroups() or {}) do
				bodygroups[v.id] = entity:GetBodygroup(v.id)
			end

			data[#data + 1] = {
				name = entity:GetDisplayName(),
				description = entity:GetDescription(),
				pos = entity:GetPos(),
				angles = entity:GetAngles(),
				model = entity:GetModel(),
				skin = entity:GetSkin(),
				bodygroups = bodygroups,
				bubble = entity:GetNoBubble(),
				items = entity.items,
				money = entity.money,
				scale = entity.scale
			}
		end

		self:SetData(data)
	end

	function PLUGIN:LoadData()
		for _, v in ipairs(self:GetData() or {}) do
			local entity = ents.Create("ws_vendor")
			entity:SetPos(v.pos)
			entity:SetAngles(v.angles)
			entity:Spawn()

			entity:SetModel(v.model)
			entity:SetSkin(v.skin or 0)
			entity:InitPhysObj()

			entity:SetNoBubble(v.bubble)
			entity:SetDisplayName(v.name)
			entity:SetDescription(v.description)

			for id, bodygroup in pairs(v.bodygroups or {}) do
				entity:SetBodygroup(id, bodygroup)
			end

			local items = {}

			for uniqueID, data in pairs(v.items) do
				items[tostring(uniqueID)] = data
			end

			entity.items = items
			-- Sanitize persisted money to the same [0, 65535] range SetMoney enforces, so a
			-- corrupted save can't load an out-of-range value (client reads it as UInt16).
			entity.money = v.money and math.Clamp(math.floor(v.money), 0, 65535) or nil
			entity.scale = v.scale or 0.5
		end
	end

	function PLUGIN:CanVendorSellItem(client, vendor, itemID)
		local tradeData = vendor.items[itemID]
		local char = client:GetCharacter()

		if (!tradeData or !char) then
			return false
		end

		if (!char:HasMoney(tradeData[1] or 0)) then
			return false
		end

		return true
	end

	ws.log.AddType("vendorUse", function(client, ...)
		local arg = {...}
		return string.format("%s used the '%s' vendor.", client:Name(), arg[1])
	end)

	ws.log.AddType("vendorBuy", function(client, ...)
		local arg = {...}

		return string.format("%s purchased a '%s' from the '%s' vendor for %s.", client:Name(), arg[1], arg[2], arg[3])
	end)

	ws.log.AddType("vendorSell", function(client, ...)
		local arg = {...}

		return string.format("%s sold a '%s' to the '%s' vendor for %s.", client:Name(), arg[1], arg[2], arg[3])
	end)

	net.Receive("wsVendorClose", function(length, client)
		local entity = client.wsVendor

		if (IsValid(entity)) then
			for k, v in ipairs(entity.receivers) do
				if (v == client) then
					table.remove(entity.receivers, k)

					break
				end
			end

			client.wsVendor = nil
		end
	end)

	local function UpdateEditReceivers(receivers, key, value)
		net.Start("wsVendorEdit")
			net.WriteString(key)
			net.WriteType(value)
		net.Send(receivers)
	end

	net.Receive("wsVendorEdit", function(length, client)
		if (!CAMI.PlayerHasAccess(client, "Windswept - Manage Vendors", nil)) then
			return
		end

		local entity = client.wsVendor

		if (!IsValid(entity)) then
			return
		end

		local key = net.ReadString()
		local data = net.ReadType()
		local feedback = true

		if (key == "name") then
			entity:SetDisplayName(data)
		elseif (key == "description") then
			entity:SetDescription(data)
		elseif (key == "bubble") then
			entity:SetNoBubble(data)
		elseif (key == "mode") then
			local uniqueID = data[1]

			entity.items[uniqueID] = entity.items[uniqueID] or {}
			entity.items[uniqueID][VENDOR_MODE] = data[2]

			UpdateEditReceivers(entity.receivers, key, data)
		elseif (key == "price") then
			local uniqueID = data[1]
			data[2] = tonumber(data[2])

			if (data[2]) then
				data[2] = math.Round(data[2])
			end

			entity.items[uniqueID] = entity.items[uniqueID] or {}
			entity.items[uniqueID][VENDOR_PRICE] = data[2]

			UpdateEditReceivers(entity.receivers, key, data)

			data = uniqueID
		elseif (key == "stockDisable") then
			local uniqueID = data[1]

			entity.items[data] = entity.items[uniqueID] or {}
			entity.items[data][VENDOR_MAXSTOCK] = nil

			UpdateEditReceivers(entity.receivers, key, data)
		elseif (key == "stockMax") then
			local uniqueID = data[1]
			data[2] = math.max(math.Round(tonumber(data[2]) or 1), 1)

			entity.items[uniqueID] = entity.items[uniqueID] or {}
			entity.items[uniqueID][VENDOR_MAXSTOCK] = data[2]
			entity.items[uniqueID][VENDOR_STOCK] = math.Clamp(entity.items[uniqueID][VENDOR_STOCK] or data[2], 1, data[2])

			data[3] = entity.items[uniqueID][VENDOR_STOCK]

			UpdateEditReceivers(entity.receivers, key, data)

			data = uniqueID
		elseif (key == "stock") then
			local uniqueID = data[1]

			entity.items[uniqueID] = entity.items[uniqueID] or {}

			if (!entity.items[uniqueID][VENDOR_MAXSTOCK]) then
				data[2] = math.max(math.Round(tonumber(data[2]) or 0), 0)
				entity.items[uniqueID][VENDOR_MAXSTOCK] = data[2]
			end

			data[2] = math.Clamp(math.Round(tonumber(data[2]) or 0), 0, entity.items[uniqueID][VENDOR_MAXSTOCK])
			entity.items[uniqueID][VENDOR_STOCK] = data[2]

			UpdateEditReceivers(entity.receivers, key, data)

			data = uniqueID
		elseif (key == "model") then
			entity:SetModel(data)
			entity:InitPhysObj()
			entity:SetAnim()
		elseif (key == "useMoney") then
			if (entity.money) then
				entity:SetMoney()
			else
				entity:SetMoney(0)
			end
		elseif (key == "money") then
			data = math.Round(math.abs(tonumber(data) or 0))

			entity:SetMoney(data)
			feedback = false
		elseif (key == "scale") then
			data = tonumber(data) or 0.5

			entity.scale = data

			UpdateEditReceivers(entity.receivers, key, data)
		end

		PLUGIN:SaveData()

		if (feedback) then
			local receivers = {}

			for _, v in ipairs(entity.receivers) do
				if (CAMI.PlayerHasAccess(v, "Windswept - Manage Vendors", nil)) then
					receivers[#receivers + 1] = v
				end
			end

			net.Start("wsVendorEditFinish")
				net.WriteString(key)
				net.WriteType(data)
			net.Send(receivers)
		end
	end)

	ws.action.Register("wsVendorTrade", {
		-- The vendor entity is supplied by the client (target). Authority is enforced
		-- in onValidate: it must be a ws_vendor within the original 192u reach and the
		-- caller must satisfy the vendor's access rule (entity:CanAccess).
		-- range = "none" because the legacy contract uses a 192u Distance check, not
		-- ws.access's 100u "interaction" range; we replicate the exact distance below.
		target = true,
		range = "none",
		rateLimit = 0.33,
		read = function()
			return {
				uniqueID = net.ReadString(),
				isSellingToVendor = net.ReadBool()
			}
		end,
		onValidate = function(client, ctx)
			local entity = ctx.target

			-- Must be an actual vendor (the entity now arrives from the client).
			if (entity:GetClass() != "ws_vendor") then
				return false
			end

			if (client:GetPos():Distance(entity:GetPos()) > 192) then
				return false
			end

			if (!entity:CanAccess(client)) then
				return false
			end
		end,
		run = function(client, ctx)
		local entity = ctx.target
		local uniqueID = ctx.data.uniqueID
		local isSellingToVendor = ctx.data.isSellingToVendor

		-- Conservation default: refuse trades that would mint. Unless vendorAllowInfinite
		-- is set, a vendor with infinite money (money == nil) can't BUY from a player, and a
		-- vendor with no configured max stock (GetStock == nil) can't SELL. (cons / layer-vendor)
		if (entity.items[uniqueID] and !ws.config.Get("vendorAllowInfinite")) then
			if (isSellingToVendor and entity.money == nil) then
				return client:NotifyLocalized("vendorCannotMint")
			elseif (!isSellingToVendor and entity:GetStock(uniqueID) == nil) then
				return client:NotifyLocalized("vendorCannotMint")
			end
		end

		if (entity.items[uniqueID] and
			hook.Run("CanPlayerTradeWithVendor", client, entity, uniqueID, isSellingToVendor) != false) then
			local price = entity:GetPrice(uniqueID, isSellingToVendor)

			if (isSellingToVendor) then
				local found = false
				local name

				if (!entity:HasMoney(price)) then
					return client:NotifyLocalized("vendorNoMoney")
				end

				local stock, max = entity:GetStock(uniqueID)

				if (stock and stock >= max) then
					return client:NotifyLocalized("vendorMaxStock")
				end

				-- Server-side vendor-mode enforcement, symmetric to the buy branch's
				-- CanSellToPlayer guard: a sell-only vendor must not buy from players.
				-- (The client UI hides this, but wsVendorTrade is attacker-reachable.)
				if (!entity:CanBuyFromPlayer(client, uniqueID)) then
					return
				end

				-- Locate the item to sell, but do NOT remove it yet. With physical
				-- currency GiveMoney can fail (no inventory space for the cash/coins),
				-- so we must pay first and only destroy the item once payment lands;
				-- otherwise the player loses the item and gets nothing.
				local sellItem

				for k, _ in client:GetCharacter():GetInventory():Iter() do
					if (k.uniqueID == uniqueID and k:GetID() != 0 and ws.item.instances[k:GetID()] and k:GetData("equip", false) == false) then
						sellItem = k
						found = true
						name = L(k.name, client)

						break
					end
				end

				if (!found) then
					return client:NotifyLocalized("itemNoExist")
				end

				-- Pay the seller first; abort (keep the item) if it cannot fit.
				if (price > 0 and !client:GetCharacter():GiveMoney(price)) then
					return client:NotifyLocalized("businessSellNoRoom")
				end

				-- Now destroy the sold item. If removal somehow fails, refund the
				-- payment so money isn't duplicated.
				if (!sellItem:Remove()) then
					if (price > 0) then
						client:GetCharacter():TakeMoney(price)
					end

					client:GetCharacter():GetInventory():Sync(client, true)
					return client:NotifyLocalized("tellAdmin", "trd!iid")
				end

				client:NotifyLocalized("businessSell", name, ws.currency.Get(price))
				entity:TakeMoney(price)
				entity:AddStock(uniqueID)

				ws.log.Add(client, "vendorSell", name, entity:GetDisplayName(), ws.currency.Get(price))
			else
				local stock = entity:GetStock(uniqueID)

				if (stock and stock < 1) then
					return client:NotifyLocalized("vendorNoStock")
				end

				if (!client:GetCharacter():HasMoney(price)) then
					return client:NotifyLocalized("canNotAfford")
				end

				if !entity:CanSellToPlayer(client, uniqueID) then
					return false
				end

				local name = L(ws.item.list[uniqueID].name, client)

				-- Abort if the money can't actually be taken (e.g. can't make change in a full
				-- inventory), or the player would receive the item and keep their money. (fw-currency-economy-5 ripple)
				if (!client:GetCharacter():TakeMoney(price, price == 0)) then
					return client:NotifyLocalized("canNotAfford")
				end

				client:NotifyLocalized("businessPurchase", name, ws.currency.Get(price))

				entity:GiveMoney(price)

				if (!client:GetCharacter():GetInventory():Add(uniqueID)) then
					ws.item.Spawn(uniqueID, client)
				else
					net.Start("wsVendorAddItem")
						net.WriteString(uniqueID)
					net.Send(client)
				end

				entity:TakeStock(uniqueID)

				ws.log.Add(client, "vendorBuy", name, entity:GetDisplayName(), ws.currency.Get(price))
			end

			PLUGIN:SaveData()
			hook.Run("CharacterVendorTraded", client, entity, uniqueID, isSellingToVendor)
		else
			client:NotifyLocalized("vendorNoTrade")
		end
		end
	})
else
	VENDOR_TEXT = {}
	VENDOR_TEXT[VENDOR_SELLANDBUY] = "vendorBoth"
	VENDOR_TEXT[VENDOR_BUYONLY] = "vendorBuy"
	VENDOR_TEXT[VENDOR_SELLONLY] = "vendorSell"

	net.Receive("wsVendorOpen", function()
		local entity = net.ReadEntity()

		if (!IsValid(entity)) then
			return
		end

		entity.money = net.ReadUInt(16)
		entity.items = net.ReadTable()
		entity.scale = net.ReadFloat()

		ws.gui.vendor = vgui.Create("wsVendor")
		ws.gui.vendor:SetReadOnly(false)
		ws.gui.vendor:Setup(entity)
	end)

	net.Receive("wsVendorEditor", function()
		local entity = net.ReadEntity()

		if (!IsValid(entity) or !CAMI.PlayerHasAccess(LocalPlayer(), "Windswept - Manage Vendors", nil)) then
			return
		end

		entity.money = net.ReadUInt(16)
		entity.items = net.ReadTable()
		entity.scale = net.ReadFloat()

		ws.gui.vendor = vgui.Create("wsVendor")
		ws.gui.vendor:SetReadOnly(true)
		ws.gui.vendor:Setup(entity)
		ws.gui.vendorEditor = vgui.Create("wsVendorEditor")
	end)

	net.Receive("wsVendorEdit", function()
		local panel = ws.gui.vendor

		if (!IsValid(panel)) then
			return
		end

		local entity = panel.entity

		if (!IsValid(entity)) then
			return
		end

		local key = net.ReadString()
		local data = net.ReadType()

		if (key == "mode") then
			entity.items[data[1]] = entity.items[data[1]] or {}
			entity.items[data[1]][VENDOR_MODE] = data[2]

			if (!data[2]) then
				panel:removeItem(data[1])
			elseif (data[2] == VENDOR_SELLANDBUY) then
				panel:addItem(data[1])
			else
				panel:addItem(data[1], data[2] == VENDOR_SELLONLY and "selling" or "buying")
				panel:removeItem(data[1], data[2] == VENDOR_SELLONLY and "buying" or "selling")
			end
		elseif (key == "price") then
			local uniqueID = data[1]

			entity.items[uniqueID] = entity.items[uniqueID] or {}
			entity.items[uniqueID][VENDOR_PRICE] = tonumber(data[2])
		elseif (key == "stockDisable") then
			if (entity.items[data]) then
				entity.items[data][VENDOR_MAXSTOCK] = nil
			end
		elseif (key == "stockMax") then
			local uniqueID = data[1]
			local value = data[2]
			local current = data[3]

			entity.items[uniqueID] = entity.items[uniqueID] or {}
			entity.items[uniqueID][VENDOR_MAXSTOCK] = value
			entity.items[uniqueID][VENDOR_STOCK] = current
		elseif (key == "stock") then
			local uniqueID = data[1]
			local value = data[2]

			entity.items[uniqueID] = entity.items[uniqueID] or {}

			if (!entity.items[uniqueID][VENDOR_MAXSTOCK]) then
				entity.items[uniqueID][VENDOR_MAXSTOCK] = value
			end

			entity.items[uniqueID][VENDOR_STOCK] = value
		elseif (key == "scale") then
			entity.scale = data
		end
	end)

	net.Receive("wsVendorEditFinish", function()
		local panel = ws.gui.vendor
		local editor = ws.gui.vendorEditor

		if (!IsValid(panel) or !IsValid(editor)) then
			return
		end

		local entity = panel.entity

		if (!IsValid(entity)) then
			return
		end

		local key = net.ReadString()
		local data = net.ReadType()

		if (key == "name") then
			editor.name:SetText(data)
		elseif (key == "description") then
			editor.description:SetText(data)
		elseif (key == "bubble") then
			editor.bubble.noSend = true
			editor.bubble:SetValue(data and 1 or 0)
		elseif (key == "mode") then
			if (data[2] == nil) then
				editor.lines[data[1]]:SetValue(3, L"none")
			else
				editor.lines[data[1]]:SetValue(3, L(VENDOR_TEXT[data[2]]))
			end
		elseif (key == "price") then
			editor.lines[data]:SetValue(4, entity:GetPrice(data))
		elseif (key == "stockDisable") then
			editor.lines[data]:SetValue(5, "-")
		elseif (key == "stockMax" or key == "stock") then
			local current, max = entity:GetStock(data)

			editor.lines[data]:SetValue(5, current.."/"..max)
		elseif (key == "model") then
			editor.model:SetText(entity:GetModel())
		elseif (key == "scale") then
			editor.sellScale.noSend = true
			editor.sellScale:SetValue(data)
		end

		surface.PlaySound("buttons/button14.wav")
	end)

	net.Receive("wsVendorMoney", function()
		local panel = ws.gui.vendor

		if (!IsValid(panel)) then
			return
		end

		local entity = panel.entity

		if (!IsValid(entity)) then
			return
		end

		-- nil = infinite money (no cap); otherwise a 16-bit balance
		local value = net.ReadBool() and net.ReadUInt(16) or nil

		entity.money = value

		local editor = ws.gui.vendorEditor

		if (IsValid(editor)) then
			local useMoney = tonumber(value) != nil

			editor.money:SetDisabled(!useMoney)
			editor.money:SetEnabled(useMoney)
			editor.money:SetText(useMoney and value or "∞")
		end
	end)

	net.Receive("wsVendorStock", function()
		local panel = ws.gui.vendor

		if (!IsValid(panel)) then
			return
		end

		local entity = panel.entity

		if (!IsValid(entity)) then
			return
		end

		local uniqueID = net.ReadString()
		local amount = net.ReadUInt(16)

		entity.items[uniqueID] = entity.items[uniqueID] or {}
		entity.items[uniqueID][VENDOR_STOCK] = amount

		local editor = ws.gui.vendorEditor

		if (IsValid(editor)) then
			local _, max = entity:GetStock(uniqueID)

			editor.lines[uniqueID]:SetValue(4, amount .. "/" .. max)
		end
	end)

	net.Receive("wsVendorAddItem", function()
		local uniqueID = net.ReadString()

		if (IsValid(ws.gui.vendor)) then
			ws.gui.vendor:addItem(uniqueID, "buying")
		end
	end)
end

properties.Add("vendor_edit", {
	MenuLabel = "Edit Vendor",
	Order = 999,
	MenuIcon = "icon16/user_edit.png",

	Filter = function(self, entity, client)
		if (!IsValid(entity)) then return false end
		if (entity:GetClass() != "ws_vendor") then return false end
		if (!gamemode.Call( "CanProperty", client, "vendor_edit", entity)) then return false end

		return CAMI.PlayerHasAccess(client, "Windswept - Manage Vendors", nil)
	end,

	Action = function(self, entity)
		self:MsgStart()
			net.WriteEntity(entity)
		self:MsgEnd()
	end,

	Receive = function(self, length, client)
		local entity = net.ReadEntity()

		if (!IsValid(entity)) then return end
		if (!self:Filter(entity, client)) then return end

		entity.receivers[#entity.receivers + 1] = client

		local itemsTable = {}

		for k, v in pairs(entity.items) do
			if (!table.IsEmpty(v)) then
				itemsTable[k] = v
			end
		end

		client.wsVendor = entity

		net.Start("wsVendorEditor")
			net.WriteEntity(entity)
			net.WriteUInt(entity.money or 0, 16)
			net.WriteTable(itemsTable)
			net.WriteFloat(entity.scale or 0.5)
		net.Send(client)
	end
})
