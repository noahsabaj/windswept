
local PLUGIN = PLUGIN

PLUGIN.name = "Ammo Saver"
PLUGIN.author = "Black Tea"
PLUGIN.description = "Saves the ammo of a character."
PLUGIN.ammoList = {}

ws.ammo = ws.ammo or {}

function ws.ammo.Register(name)
	name = name:lower()

	if (!table.HasValue(PLUGIN.ammoList, name)) then
		PLUGIN.ammoList[#PLUGIN.ammoList + 1] = name
	end
end

-- Register Default HL2 Ammunition.
ws.ammo.Register("ar2")
ws.ammo.Register("pistol")
ws.ammo.Register("357")
ws.ammo.Register("smg1")
ws.ammo.Register("xbowbolt")
ws.ammo.Register("buckshot")
ws.ammo.Register("rpg_round")
ws.ammo.Register("smg1_grenade")
ws.ammo.Register("grenade")
ws.ammo.Register("ar2altfire")
ws.ammo.Register("slam")

-- Register Cut HL2 Ammunition.
ws.ammo.Register("alyxgun")
ws.ammo.Register("sniperround")
ws.ammo.Register("sniperpenetratedround")
ws.ammo.Register("thumper")
ws.ammo.Register("gravity")
ws.ammo.Register("battery")
ws.ammo.Register("gaussenergy")
ws.ammo.Register("combinecannon")
ws.ammo.Register("airboatgun")
ws.ammo.Register("striderminigun")
ws.ammo.Register("helicoptergun")

-- Called right before the character has its information save.
function PLUGIN:CharacterPreSave(character)
	-- Get the player from the character.
	local client = character:GetPlayer()

	-- Check to see if we can get the player's ammo.
	if (IsValid(client)) then
		local ammoTable = {}

		for _, v in ipairs(self.ammoList) do
			local ammo = client:GetAmmoCount(v)

			if (ammo > 0) then
				ammoTable[v] = ammo
			end
		end

		character:SetData("ammo", ammoTable)
	end
end

-- Called after the player's loadout has been set.
function PLUGIN:PlayerLoadedCharacter(client)
	timer.Simple(0.25, function()
		if (!IsValid(client)) then
			return
		end

		-- Get the saved ammo table from the character data.
		local character = client:GetCharacter()

		if (!character) then
			return
		end

		local ammoTable = character:GetData("ammo")

		-- Check if the ammotable is exists.
		if (ammoTable) then
			for k, v in pairs(ammoTable) do
				client:SetAmmo(v, tostring(k))
			end
		end
	end)
end
