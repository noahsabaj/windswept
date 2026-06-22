AddCSLuaFile()

-- NOTE: the ix_* -> ws_* entity-class rename is an INTENTIONAL break. This is a
-- greenfield deploy (no live servers, no pre-rebrand saved maps/dupes/saves), so
-- no scripted_ents.Alias("ix_money", "ws_money") back-compat is registered. If a
-- pre-rebrand map/dupe ever needs to load, add the alias here. (layer-8)

ENT.Type = "anim"
ENT.PrintName = "Money"
ENT.Category = "Windswept"
ENT.Spawnable = false
ENT.ShowPlayerInteraction = true
ENT.bNoPersist = true

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Amount")
end

if (SERVER) then
	local invalidBoundsMin = Vector(-8, -8, -8)
	local invalidBoundsMax = Vector(8, 8, 8)

	function ENT:Initialize()
		self:SetModel(ws.currency.model)
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(true)
			physObj:Wake()
		else
			self:PhysicsInitBox(invalidBoundsMin, invalidBoundsMax)
			self:SetCollisionBounds(invalidBoundsMin, invalidBoundsMax)
		end
	end

	function ENT:Use(activator)
		if (self.wsSteamID and self.wsCharID) then
			local char = activator:GetCharacter()

			if (char and self.wsCharID != char:GetID() and self.wsSteamID == activator:SteamID()) then
				activator:NotifyLocalized("itemOwned")
				return false
			end
		end

		activator:PerformInteraction(ws.config.Get("itemPickupTime", 0.5), self, function(client)
			if not IsValid(self) then return end

			-- Use physical currency pickup handler
			if ws.currency.HandlePickup(client, self) then
				self:Remove()
			end
			-- If pickup failed (inventory full), entity stays on ground
		end)
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_PVS
	end
else
	ENT.PopulateEntityInfo = true

	function ENT:OnPopulateEntityInfo(container)
		local text = container:AddRow("name")
		text:SetImportant()
		-- GetAmount() returns dollars, ws.currency.Get() expects cents
		text:SetText(ws.currency.Get(self:GetAmount() * ws.currency.CENTS_PER_DOLLAR))
		text:SizeToContents()
	end
end
