
ENT.Type = "anim"
ENT.PrintName = "Container"
ENT.Category = "Windswept"
ENT.Spawnable = false
ENT.bNoPersist = true

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "ID")
	self:NetworkVar("Bool", 0, "Locked")
	self:NetworkVar("String", 0, "DisplayName")
end

if (SERVER) then
	function ENT:Initialize()
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self.receivers = {}

		local definition = ws.container.stored[self:GetModel():lower()]

		if (definition) then
			self:SetDisplayName(definition.name)
		end

		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(true)
			physObj:Wake()
		end
	end

	function ENT:SetInventory(inventory)
		if (inventory) then
			self:SetID(inventory:GetID())
		end
	end

	-- REMOVED: Physical currency system
	-- Containers hold cash/coins as inventory items, not numeric money
	-- function ENT:SetMoney(amount) removed
	-- function ENT:GetMoney() removed

	function ENT:OnRemove()
		local index = self:GetID()

		if (!ws.shuttingDown and !self.wsIsSafe and ws.entityDataLoaded and index) then
			local inventory = ws.item.inventories[index]

			if (inventory) then
				ws.item.inventories[index] = nil

				local query = mysql:Delete("ws_items")
					query:Where("inventory_id", index)
				query:Execute()

				query = mysql:Delete("ws_inventories")
					query:Where("inventory_id", index)
				query:Execute()

				hook.Run("ContainerRemoved", self, inventory)
			end
		end
	end

	function ENT:OpenInventory(activator)
		local inventory = self:GetInventory()

		if (inventory) then
			local name = self:GetDisplayName()
			local definition = ws.container.stored[self:GetModel():lower()]

			ws.storage.Open(activator, inventory, {
				name = name,
				entity = self,
				searchTime = ws.config.Get("containerOpenTime", 0.7),
				data = {},  -- Physical currency: no money data, cash is inventory items
				OnPlayerOpen = function()
					if (definition.OnOpen) then
					    definition.OnOpen(self, activator)
					end
				end,
				OnPlayerClose = function()
					if (definition.OnClose) then
						definition.OnClose(self, activator)
					end

					ws.log.Add(activator, "closeContainer", name, inventory:GetID())
				end
			})

			if (self:GetLocked()) then
				self.Sessions[activator:GetCharacter():GetID()] = true
			end

			ws.log.Add(activator, "openContainer", name, inventory:GetID())
		end
	end

	function ENT:Use(activator)
		local inventory = self:GetInventory()

		if (inventory and (activator.wsNextOpen or 0) < CurTime()) then
			local character = activator:GetCharacter()

			if (character) then
				local definition = ws.container.stored[self:GetModel():lower()]

				if (self:GetLocked() and !self.Sessions[character:GetID()]) then
					self:EmitSound(definition.locksound or "doors/default_locked.wav")

					if (!self.keypad) then
						net.Start("wsContainerPassword")
							net.WriteEntity(self)
						net.Send(activator)
					end
				else
					self:OpenInventory(activator)
				end
			end

			activator.wsNextOpen = CurTime() + 1
		end
	end
else
	ENT.PopulateEntityInfo = true

	local COLOR_LOCKED = Color(200, 38, 19, 200)
	local COLOR_UNLOCKED = Color(135, 211, 124, 200)

	function ENT:OnPopulateEntityInfo(tooltip)
		local definition = ws.container.stored[self:GetModel():lower()]
		local bLocked = self:GetLocked()

		surface.SetFont("wsIconsSmall")

		local iconText = bLocked and "P" or "Q"
		local iconWidth, iconHeight = surface.GetTextSize(iconText)

		-- minimal tooltips have centered text so we'll draw the icon above the name instead
		if (tooltip:IsMinimal()) then
			local icon = tooltip:AddRow("icon")
			icon:SetFont("wsIconsSmall")
			icon:SetTextColor(bLocked and COLOR_LOCKED or COLOR_UNLOCKED)
			icon:SetText(iconText)
			icon:SizeToContents()
		end

		local title = tooltip:AddRow("name")
		title:SetImportant()
		title:SetText(self:GetDisplayName())
		title:SetBackgroundColor(ws.config.Get("color"))
		title:SetTextInset(iconWidth + 8, 0)
		title:SizeToContents()

		if (!tooltip:IsMinimal()) then
			title.Paint = function(panel, width, height)
				panel:PaintBackground(width, height)

				surface.SetFont("wsIconsSmall")
				surface.SetTextColor(bLocked and COLOR_LOCKED or COLOR_UNLOCKED)
				surface.SetTextPos(4, height * 0.5 - iconHeight * 0.5)
				surface.DrawText(iconText)
			end
		end

		local description = tooltip:AddRow("description")
		description:SetText(definition.description)
		description:SizeToContents()
	end
end

function ENT:GetInventory()
	return ws.item.inventories[self:GetID()]
end
