
util.AddNetworkString("wsPlayerDeath")

function GM:PlayerInitialSpawn(client)
	client.wsJoinTime = RealTime()

	if (client:IsBot()) then
		local botID = os.time() + client:EntIndex()

		-- Bots are factionless like regular new characters
		local models = ws.config.Get("factionlessModels") or {"models/gman.mdl"}
		local model = models[math.random(#models)]
		if (istable(model)) then model = model[1] end
		if (!isstring(model)) then model = "models/gman.mdl" end

		local character = ws.char.New({
			name = client:Name(),
			faction = nil,
			model = model,
		}, botID, client, client:SteamID64())
		character.isBot = true

		local inventory = ws.inventory.Create(ws.config.Get("inventoryWidth"), ws.config.Get("inventoryHeight"), botID)
		inventory:SetOwner(botID)
		inventory.noSave = true

		character.vars.inv = {inventory}

		ws.char.loaded[botID] = character

		character:Setup()
		client:Spawn()

		ws.chat.Send(nil, "connect", client:SteamName())

		return
	end

	ws.config.Send(client)
	ws.date.Send(client)

	client:LoadData(function(data)
		if (!IsValid(client)) then return end

		-- Don't use the character cache if they've connected to another server using the same database
		local address = ws.util.GetAddress()
		local bNoCache = client:GetData("lastIP", address) != address
		client:SetData("lastIP", address)

		net.Start("wsDataSync")
			net.WriteTable(data or {})
			net.WriteUInt(client.wsPlayTime or 0, 32)
		net.Send(client)

		ws.char.Restore(client, function(charList)
			if (!IsValid(client)) then return end

			MsgN("Loaded (" .. table.concat(charList, ", ") .. ") for " .. client:Name())

			for _, v in ipairs(charList) do
				ws.char.loaded[v]:Sync(client)
			end

			client.wsCharList = charList

			net.Start("wsCharacterMenu")
			net.WriteUInt(#charList, 6)

			for _, v in ipairs(charList) do
				net.WriteUInt(v, 32)
			end

			net.Send(client)

			client.wsLoaded = true
			client:SetData("intro", true)

			for _, v in player.Iterator() do
				if (v:GetCharacter()) then
					v:GetCharacter():Sync(client)
				end
			end
		end, bNoCache)

		ws.chat.Send(nil, "connect", client:SteamName())
	end)

	client:SetNoDraw(true)
	client:SetNotSolid(true)
	client:Lock()
	client:SyncVars()

	timer.Simple(1, function()
		if (!IsValid(client)) then
			return
		end

		client:KillSilent()
		client:StripAmmo()
	end)
end

function GM:PlayerUse(client, entity)
	if (client:IsRestricted() or (isfunction(entity.GetEntityMenu) and entity:GetClass() != "ix_item")) then
		return false
	end

	return true
end

function GM:KeyPress(client, key)
	if (key == IN_RELOAD) then
		timer.Create("wsToggleRaise"..client:SteamID(), ws.config.Get("weaponRaiseTime"), 1, function()
			if (IsValid(client)) then
				client:ToggleWepRaised()
			end
		end)
	elseif (key == IN_USE) then
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector() * 96
			data.filter = client
		local entity = util.TraceLine(data).Entity

		if (IsValid(entity) and hook.Run("PlayerUse", client, entity)) then
			if (entity:IsDoor()) then
				local result = hook.Run("CanPlayerUseDoor", client, entity)

				if (result != false) then
					hook.Run("PlayerUseDoor", client, entity)
				end
			end
		end
	end
end

function GM:KeyRelease(client, key)
	if (key == IN_RELOAD) then
		timer.Remove("wsToggleRaise" .. client:SteamID())
	elseif (key == IN_USE) then
		timer.Remove("wsCharacterInteraction" .. client:SteamID())
	end
end

function GM:CanPlayerInteractEntity(client, entity, option, data)
	return entity:GetPos():DistToSqr(client:GetPos()) <= 96 ^ 2
end

function GM:CanPlayerInteractItem(client, action, item, data)
	if (client:IsRestricted()) then
		return false
	end

	if (IsValid(client.wsRagdoll)) then
		client:NotifyLocalized("notNow")
		return false
	end

	if (action == "drop" and hook.Run("CanPlayerDropItem", client, item) == false) then
		return false
	end

	if (action == "take" and hook.Run("CanPlayerTakeItem", client, item) == false) then
		return false
	end

	if (action == "combine") then
		local other = data[1]

		if (hook.Run("CanPlayerCombineItem", client, item, other) == false) then
			return false
		end

		local combineItem = ws.item.instances[other]

		if (combineItem and combineItem.invID != 0) then
			local combineInv = ws.item.inventories[combineItem.invID]

			if (!combineInv:OnCheckAccess(client)) then
				return false
			end
		else
			return false
		end
	end

	if (isentity(item) and item.wsSteamID and item.wsCharID
	and item.wsSteamID == client:SteamID() and item.wsCharID != client:GetCharacter():GetID()
	and !item:GetItemTable().bAllowMultiCharacterInteraction) then
		client:NotifyLocalized("itemOwned")
		return false
	end

	return client:Alive()
end

function GM:CanPlayerDropItem(client, item)

end

function GM:CanPlayerTakeItem(client, item)

end

function GM:CanPlayerCombineItem(client, item, other)

end

function GM:PlayerShouldTakeDamage(client, attacker)
	return client:GetCharacter() != nil
end

function GM:GetFallDamage(client, speed)
	return (speed - 580) * (100 / 444)
end

function GM:EntityTakeDamage(entity, dmgInfo)
	local inflictor = dmgInfo:GetInflictor()

	if (IsValid(inflictor) and inflictor:GetClass() == "ix_item") then
		dmgInfo:SetDamage(0)
		return
	end

	if (IsValid(entity.wsPlayer)) then
		if (IsValid(entity.wsHeldOwner)) then
			dmgInfo:SetDamage(0)
			return
		end

		if (dmgInfo:IsDamageType(DMG_CRUSH)) then
			if ((entity.wsFallGrace or 0) < CurTime()) then
				if (dmgInfo:GetDamage() <= 10) then
					dmgInfo:SetDamage(0)
				end

				entity.wsFallGrace = CurTime() + 0.5
			else
				return
			end
		end

		entity.wsPlayer:TakeDamageInfo(dmgInfo)
	end
end

function GM:PrePlayerLoadedCharacter(client, character, lastChar)
	-- Reset all bodygroups
	client:ResetBodygroups()

	-- Remove all skins
	client:SetSkin(0)
end

function GM:PlayerLoadedCharacter(client, character, lastChar)
	local query = mysql:Update("ix_characters")
		query:Where("id", character:GetID())
		query:Update("last_join_time", math.floor(os.time()))
	query:Execute()

	if (lastChar) then
		local charEnts = lastChar:GetVar("charEnts") or {}

		for _, v in ipairs(charEnts) do
			if (v and IsValid(v)) then
				v:Remove()
			end
		end

		lastChar:SetVar("charEnts", nil)
	end

	if (character) then
		for _, v in pairs(ws.class.list) do
			if (v.faction == client:Team() and v.isDefault) then
				character:SetClass(v.index)

				break
			end
		end
	end

	if (IsValid(client.wsRagdoll)) then
		client.wsRagdoll.wsNoReset = true
		client.wsRagdoll.wsIgnoreDelete = true
		client.wsRagdoll:Remove()
	end

	local faction = ws.faction.indices[character:GetFaction()]
	local uniqueID = "wsSalary" .. client:SteamID64()

	if (faction and faction.pay and faction.pay > 0) then
		timer.Create(uniqueID, faction.payTime or 300, 0, function()
			if (IsValid(client)) then
				if (hook.Run("CanPlayerEarnSalary", client, faction) != false) then
					local pay = hook.Run("GetSalaryAmount", client, faction) or faction.pay

					character:GiveMoney(pay)
					client:NotifyLocalized("salary", ws.currency.Get(pay))
				end
			else
				timer.Remove(uniqueID)
			end
		end)
	elseif (timer.Exists(uniqueID)) then
		timer.Remove(uniqueID)
	end

	hook.Run("PlayerLoadout", client)
end

function GM:CharacterLoaded(character)
	local client = character:GetPlayer()

	if (IsValid(client)) then
		local uniqueID = "wsSaveChar"..client:SteamID()

		timer.Create(uniqueID, ws.config.Get("saveInterval"), 0, function()
			if (IsValid(client) and client:GetCharacter()) then
				client:GetCharacter():Save()
			else
				timer.Remove(uniqueID)
			end
		end)
	end
end

function GM:PlayerSay(client, text)
	local chatType, message, anonymous = ws.chat.Parse(client, text, true)

	if (chatType == "ic") then
		if (ws.command.Parse(client, message)) then
			return ""
		end
	end

	text = ws.chat.Send(client, chatType, message, anonymous)

	if (isstring(text) and chatType != "ic") then
		ws.log.Add(client, "chat", chatType and chatType:utf8upper() or "??", text)
	end

	hook.Run("PostPlayerSay", client, chatType, message, anonymous)
	return ""
end

function GM:CanAutoFormatMessage(client, chatType, message)
	return chatType == "ic" or chatType == "w" or chatType == "y"
end

function GM:PlayerSpawn(client)
	client:SetNoDraw(false)
	client:UnLock()
	client:SetNotSolid(false)
	client:SetMoveType(MOVETYPE_WALK)
	client:SetRagdolled(false)
	client:SetAction()
	client:SetDSP(1)

	hook.Run("PlayerLoadout", client)
end

-- Shortcuts for (super)admin only things.
local function IsAdmin(_, client)
	return client:IsAdmin()
end

-- Set the gamemode hooks to the appropriate shortcuts.
GM.PlayerGiveSWEP = IsAdmin
GM.PlayerSpawnEffect = IsAdmin
GM.PlayerSpawnSENT = IsAdmin

function GM:PlayerSpawnNPC(client, npcType, weapon)
	return client:IsAdmin() or client:GetCharacter():HasFlags("n")
end

function GM:PlayerSpawnSWEP(client, weapon, info)
	return client:IsAdmin()
end

function GM:PlayerSpawnProp(client)
	if (client:GetCharacter() and client:GetCharacter():HasFlags("e")) then
		return true
	end

	return false
end

function GM:PlayerSpawnRagdoll(client)
	if (client:GetCharacter() and client:GetCharacter():HasFlags("r")) then
		return true
	end

	return false
end

function GM:PlayerSpawnVehicle(client, model, name, data)
	if (client:GetCharacter()) then
		if (data.Category == "Chairs") then
			return client:GetCharacter():HasFlags("c")
		else
			return client:GetCharacter():HasFlags("C")
		end
	end

	return false
end

function GM:PlayerSpawnedEffect(client, model, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

function GM:PlayerSpawnedNPC(client, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

function GM:PlayerSpawnedProp(client, model, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

function GM:PlayerSpawnedRagdoll(client, model, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

function GM:PlayerSpawnedSENT(client, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

function GM:PlayerSpawnedSWEP(client, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

function GM:PlayerSpawnedVehicle(client, entity)
	entity:SetNetVar("owner", client:GetCharacter():GetID())
end

ws.allowedHoldableClasses = {
	["ix_item"] = true,
	["ix_money"] = true,
	["ix_shipment"] = true,
	["prop_physics"] = true,
	["prop_physics_override"] = true,
	["prop_physics_multiplayer"] = true,
	["prop_ragdoll"] = true
}

function GM:CanPlayerHoldObject(client, entity)
	if (ws.allowedHoldableClasses[entity:GetClass()]) then
		return true
	end
end

local voiceDistance = 360000
local function CalcPlayerCanHearPlayersVoice(listener)
	if (!IsValid(listener)) then
		return
	end

	listener.wsVoiceHear = listener.wsVoiceHear or {}

	local eyePos = listener:EyePos()
	for _, speaker in player.Iterator() do
		local speakerEyePos = speaker:EyePos()
		listener.wsVoiceHear[speaker] = eyePos:DistToSqr(speakerEyePos) < voiceDistance
	end
end

function GM:InitializedConfig()
	ws.date.Initialize()

	voiceDistance = ws.config.Get("voiceDistance")
	voiceDistance = voiceDistance * voiceDistance
end

function GM:VoiceToggled(bAllowVoice)
	for _, v in player.Iterator() do
		local uniqueID = v:SteamID64() .. "wsCanHearPlayersVoice"

		if (bAllowVoice) then
			timer.Create(uniqueID, 0.5, 0, function()
				CalcPlayerCanHearPlayersVoice(v)
			end)
		else
			timer.Remove(uniqueID)

			v.wsVoiceHear = nil
		end
	end
end

function GM:VoiceDistanceChanged(distance)
	voiceDistance = distance * distance
end

-- Called when weapons should be given to a player.
function GM:PlayerLoadout(client)
	if (client.wsSkipLoadout) then
		client.wsSkipLoadout = nil

		return
	end

	client:SetWeaponColor(Vector(client:GetInfo("cl_weaponcolor")))
	client:StripWeapons()
	client:StripAmmo()
	client:SetLocalVar("blur", nil)

	local character = client:GetCharacter()

	-- Check if they have loaded a character.
	if (character) then
		client:SetupHands()
		-- Set their player model to the character's model.
		client:SetModel(character:GetModel())
		client:Give("ix_hands")
		client:SetWalkSpeed(ws.config.Get("walkSpeed"))
		client:SetRunSpeed(ws.config.Get("runSpeed"))
		client:SetHealth(character:GetData("health", client:GetMaxHealth()))

		local faction = ws.faction.indices[client:Team()]

		if (faction) then
			-- If their faction wants to do something when the player spawns, let it.
			if (faction.OnSpawn) then
				faction:OnSpawn(client)
			end

			-- @todo add docs for player:Give() failing if player already has weapon - which means if a player is given a weapon
			-- here due to the faction weapons table, the weapon's :Give call in the weapon base will fail since the player
			-- will already have it by then. This will cause issues for weapons that have pac data since the parts are applied
			-- only if the weapon returned by :Give() is valid

			-- If the faction has default weapons, give them to the player.
			if (faction.weapons) then
				for _, v in ipairs(faction.weapons) do
					client:Give(v)
				end
			end
		end

		-- Ditto, but for classes.
		local class = ws.class.list[client:GetCharacter():GetClass()]

		if (class) then
			if (class.OnSpawn) then
				class:OnSpawn(client)
			end

			if (class.weapons) then
				for _, v in ipairs(class.weapons) do
					client:Give(v)
				end
			end
		end

		-- Apply any flags as needed.
		ws.flag.OnSpawn(client)
		ws.attributes.Setup(client)

		hook.Run("PostPlayerLoadout", client)

		client:SelectWeapon("ix_hands")
	else
		client:SetNoDraw(true)
		client:Lock()
		client:SetNotSolid(true)
	end
end

function GM:PostPlayerLoadout(client)
	-- Reload All Attrib Boosts
	local character = client:GetCharacter()

	if (character:GetInventory()) then
		for k, _ in character:GetInventory():Iter() do
			k:Call("OnLoadout", client)

			if (k:GetData("equipped") and k.attribBoosts) then
				for attribKey, attribValue in pairs(k.attribBoosts) do
					character:AddBoost(k.uniqueID, attribKey, attribValue)
				end
			end
		end
	end

	if (ws.config.Get("allowVoice")) then
		timer.Create(client:SteamID64() .. "wsCanHearPlayersVoice", 0.5, 0, function()
			CalcPlayerCanHearPlayersVoice(client)
		end)
	end
end

local deathSounds = {
	Sound("vo/npc/male01/pain07.wav"),
	Sound("vo/npc/male01/pain08.wav"),
	Sound("vo/npc/male01/pain09.wav")
}

function GM:DoPlayerDeath(client, attacker, damageinfo)
	client:AddDeaths(1)

	if (hook.Run("ShouldSpawnClientRagdoll", client) != false) then
		client:CreateRagdoll()
	end

	if (IsValid(attacker) and attacker:IsPlayer()) then
		if (client == attacker) then
			attacker:AddFrags(-1)
		else
			attacker:AddFrags(1)
		end
	end

	net.Start("wsPlayerDeath")
	net.Send(client)

	client:SetAction("@respawning", ws.config.Get("spawnTime", 5))
	client:SetDSP(31)
end

function GM:PlayerDeath(client, inflictor, attacker)
	local character = client:GetCharacter()

	if (character) then
		if (IsValid(client.wsRagdoll)) then
			client.wsRagdoll.wsIgnoreDelete = true
			client:SetLocalVar("blur", nil)

			if (hook.Run("ShouldRemoveRagdollOnDeath", client) != false) then
				client.wsRagdoll:Remove()
			end
		end

		client:SetNetVar("deathStartTime", CurTime())
		client:SetNetVar("deathTime", CurTime() + ws.config.Get("spawnTime", 5))

		character:SetData("health", nil)

		local deathSound = hook.Run("GetPlayerDeathSound", client)

		if (deathSound != false) then
			deathSound = deathSound or deathSounds[math.random(1, #deathSounds)]

			if (client:IsFemale() and !deathSound:find("female")) then
				deathSound = deathSound:gsub("male", "female")
			end

			client:EmitSound(deathSound)
		end

		local weapon = attacker:IsPlayer() and attacker:GetActiveWeapon()

		ws.log.Add(client, "playerDeath",
			attacker:GetName() ~= "" and attacker:GetName() or attacker:GetClass(), IsValid(weapon) and weapon:GetClass())
	end
end

local painSounds = {
	Sound("vo/npc/male01/pain01.wav"),
	Sound("vo/npc/male01/pain02.wav"),
	Sound("vo/npc/male01/pain03.wav"),
	Sound("vo/npc/male01/pain04.wav"),
	Sound("vo/npc/male01/pain05.wav"),
	Sound("vo/npc/male01/pain06.wav")
}

local drownSounds = {
	Sound("player/pl_drown1.wav"),
	Sound("player/pl_drown2.wav"),
	Sound("player/pl_drown3.wav"),
}

function GM:GetPlayerPainSound(client)
	if (client:WaterLevel() >= 3) then
		return drownSounds[math.random(1, #drownSounds)]
	end
end

function GM:PlayerHurt(client, attacker, health, damage)
	if ((client.wsNextPain or 0) < CurTime() and health > 0) then
		local painSound = hook.Run("GetPlayerPainSound", client) or painSounds[math.random(1, #painSounds)]

		if (client:IsFemale() and !painSound:find("female")) then
			painSound = painSound:gsub("male", "female")
		end

		client:EmitSound(painSound)
		client.wsNextPain = CurTime() + 0.33
	end

	ws.log.Add(client, "playerHurt", damage, attacker:GetName() ~= "" and attacker:GetName() or attacker:GetClass())
end

function GM:PlayerDeathThink(client)
	if (client:GetCharacter()) then
		local deathTime = client:GetNetVar("deathTime")

		if (deathTime and deathTime <= CurTime()) then
			client:Spawn()
		end
	end

	return false
end

function GM:PlayerDisconnected(client)
	client:SaveData()

	local character = client:GetCharacter()

	if (character) then
		local charEnts = character:GetVar("charEnts") or {}

		for _, v in ipairs(charEnts) do
			if (v and IsValid(v)) then
				v:Remove()
			end
		end

		hook.Run("OnCharacterDisconnect", client, character)
			character:Save()
		ws.chat.Send(nil, "disconnect", client:SteamName())
	end

	if (IsValid(client.wsRagdoll)) then
		client.wsRagdoll:Remove()
	end

	client:ClearNetVars()

	if (!client.wsVoiceHear) then
		return
	end

	for _, v in player.Iterator() do
		if (!v.wsVoiceHear) then
			continue
		end

		v.wsVoiceHear[client] = nil
	end

	timer.Remove(client:SteamID64() .. "wsCanHearPlayersVoice")
end

function GM:InitPostEntity()
	local doors = ents.FindByClass("prop_door_rotating")

	for _, v in ipairs(doors) do
		local parent = v:GetOwner()

		if (IsValid(parent)) then
			v.wsPartner = parent
			parent.wsPartner = v
		else
			for _, v2 in ipairs(doors) do
				if (v2:GetOwner() == v) then
					v2.wsPartner = v
					v.wsPartner = v2

					break
				end
			end
		end
	end

	timer.Simple(2, function()
		ws.entityDataLoaded = true
	end)
end

function GM:SaveData()
	ws.date.Save()
end

function GM:ShutDown()
	ws.shuttingDown = true
	ws.config.Save()

	hook.Run("SaveData")

	for _, v in player.Iterator() do
		v:SaveData()

		if (v:GetCharacter()) then
			v:GetCharacter():Save()
		end
	end
end

function GM:GetGameDescription()
	return "IX: "..(Schema and Schema.name or "Unknown")
end

function GM:OnPlayerUseBusiness(client, item)
	-- You can manipulate purchased items with this hook.
	-- does not requires any kind of return.
	-- ex) item:SetData("businessItem", true)
	-- then every purchased item will be marked as Business Item.
end

function GM:PlayerDeathSound()
	return true
end

function GM:InitializedSchema()
	game.ConsoleCommand("sbox_persist ix_"..Schema.folder.."\n")
end

function GM:PlayerCanHearPlayersVoice(listener, speaker)
	if (!speaker:Alive()) then
		return false
	end

	local bCanHear = listener.wsVoiceHear and listener.wsVoiceHear[speaker]
	return bCanHear, true
end

function GM:PlayerCanPickupWeapon(client, weapon)
	local data = {}
		data.start = client:GetShootPos()
		data.endpos = data.start + client:GetAimVector() * 96
		data.filter = client
	local trace = util.TraceLine(data)

	if (trace.Entity == weapon and client:KeyDown(IN_USE)) then
		return true
	end

	return client.wsWeaponGive
end

function GM:OnPhysgunFreeze(weapon, physObj, entity, client)
    -- Validate the physObj, to prevent errors on entities who have no physics object
    if (!IsValid(physObj)) then return false end

	-- Object is already frozen (!?)
	if (!physObj:IsMoveable()) then return false end
	if (entity:GetUnFreezable()) then return false end

	physObj:EnableMotion(false)

	-- With the jeep we need to pause all of its physics objects
	-- to stop it spazzing out and killing the server.
	if (entity:GetClass() == "prop_vehicle_jeep") then
		local objects = entity:GetPhysicsObjectCount()

		for i = 0, objects - 1 do
			entity:GetPhysicsObjectNum(i):EnableMotion(false)
		end
	end

	-- Add it to the player's frozen props
	client:AddFrozenPhysicsObject(entity, physObj)
	client:SendHint("PhysgunUnfreeze", 0.3)
	client:SuppressHint("PhysgunFreeze")

	return true
end

function GM:CanPlayerSuicide(client)
	return false
end

function GM:AllowPlayerPickup(client, entity)
	return false
end

function GM:PreCleanupMap()
	hook.Run("SaveData")
	hook.Run("PersistenceSave")
end

function GM:PostCleanupMap()
	ws.plugin.RunLoadData()
end

function GM:CharacterPreSave(character)
	local client = character:GetPlayer()

	for k, _ in character:GetInventory():Iter() do
		if (k.OnSave) then
			k:Call("OnSave", client)
		end
	end

	character:SetData("health", client:Alive() and client:Health() or nil)
end

timer.Create("wsLifeGuard", 1, 0, function()
	for _, v in player.Iterator() do
		if (v:GetCharacter() and v:Alive() and hook.Run("ShouldPlayerDrowned", v) != false) then
			if (v:WaterLevel() >= 3) then
				if (!v.drowningTime) then
					v.drowningTime = CurTime() + 30
					v.nextDrowning = CurTime()
					v.drownDamage = v.drownDamage or 0
				end

				if (v.drowningTime < CurTime()) then
					if (v.nextDrowning < CurTime()) then
						v:ScreenFade(1, Color(0, 0, 255, 100), 1, 0)
						v:TakeDamage(10)
						v.drownDamage = v.drownDamage + 10
						v.nextDrowning = CurTime() + 1
					end
				end
			else
				if (v.drowningTime) then
					v.drowningTime = nil
					v.nextDrowning = nil
					v.nextRecover = CurTime() + 2
				end

				if (v.nextRecover and v.nextRecover < CurTime() and v.drownDamage > 0) then
					v.drownDamage = v.drownDamage - 10
					v:SetHealth(math.Clamp(v:Health() + 10, 0, v:GetMaxHealth()))
					v.nextRecover = CurTime() + 1
				end
			end
		end
	end
end)

net.Receive("wsStringRequest", function(length, client)
	local time = net.ReadUInt(32)
	local text = net.ReadString()

	if (client.wsStrReqs and client.wsStrReqs[time]) then
		client.wsStrReqs[time](text)
		client.wsStrReqs[time] = nil
	end
end)

function GM:GetPreferredCarryAngles(entity)
	if (entity:GetClass() == "ix_item") then
		local itemTable = entity:GetItemTable()

		if (itemTable) then
			local preferedAngle = itemTable.preferedAngle

			if (preferedAngle) then -- I don't want to return something
				return preferedAngle
			end
		end
	end
end

function GM:PluginShouldLoad(uniqueID)
	return !ws.plugin.unloaded[uniqueID]
end

function GM:DatabaseConnected()
	-- Create the SQL tables if they do not exist.
	ws.db.LoadTables()
	ws.log.LoadTables()

	MsgC(Color(0, 255, 0), "Database Type: " .. ws.db.config.adapter .. ".\n")

	timer.Create("wsDatabaseThink", 0.5, 0, function()
		mysql:Think()
	end)

	ws.plugin.RunLoadData()
end
