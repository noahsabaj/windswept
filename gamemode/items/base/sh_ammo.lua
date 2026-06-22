
ITEM.name = "Ammo Base"
ITEM.model = "models/Items/BoxSRounds.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.ammo = "pistol" -- type of the ammo
ITEM.ammoAmount = 30 -- amount of the ammo
ITEM.description = "A Box that contains %s of Pistol Ammo"
ITEM.category = "Ammunition"
ITEM.useSound = "items/ammo_pickup.wav"

function ITEM:GetDescription()
	local rounds = self:GetData("rounds", self.ammoAmount)
	return Format(self.description, rounds)
end

if (CLIENT) then
	function ITEM:PaintOver(item, w, h)
		draw.SimpleText(
			item:GetData("rounds", item.ammoAmount), "DermaDefault", w - 5, h - 5,
			color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, color_black
		)
	end
end

-- On player uneqipped the item, Removes a weapon from the player and keep the ammo in the item.
ITEM.functions.use = {
	name = "Load",
	tip = "useTip",
	icon = "icon16/add.png",
	OnRun = function(item)
		local client = item.player

		-- Per-client rate limit to blunt action spam (sound spam / minor DoS); the
		-- action itself is non-duplicating. (fw-items-entities-11)
		if (IsValid(client)) then
			if ((client.wsNextAmmoUse or 0) > CurTime()) then
				return false
			end

			client.wsNextAmmoUse = CurTime() + 0.5
		end

		local rounds = item:GetData("rounds", item.ammoAmount)

		item.player:GiveAmmo(rounds, item.ammo)
		item.player:EmitSound(item.useSound, 110)

		return true
	end,
}

-- Called after the item is registered into the item tables.
function ITEM:OnRegistered()
	if (ws.ammo) then
		ws.ammo.Register(self.ammo)
	end
end
