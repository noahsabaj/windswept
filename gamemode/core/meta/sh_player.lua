
--[[--
Physical representation of connected player.

`Player`s are a type of `Entity`. They are a physical representation of a `Character` - and can possess at most one `Character`
object at a time that you can interface with.

See the [Garry's Mod Wiki](https://wiki.garrysmod.com/page/Category:Player) for all other methods that the `Player` class has.
]]
-- @classmod Player

local meta = FindMetaTable("Player")

if (SERVER) then
	--- Returns the amount of time the player has played on the server.
	-- @realm shared
	-- @treturn number Number of seconds the player has played on the server
	function meta:GetPlayTime()
		return self.wsPlayTime + (RealTime() - (self.wsJoinTime or RealTime()))
	end
else
	ws.playTime = ws.playTime or 0

	function meta:GetPlayTime()
		return ws.playTime + (RealTime() - ws.joinTime or 0)
	end
end

--- Returns `true` if the player has their weapon raised.
-- @realm shared
-- @treturn bool Whether or not the player has their weapon raised
function meta:IsWepRaised()
	return self:GetNetVar("raised", false)
end

--- Returns `true` if the player is restricted - that is to say that they are considered "bound" and cannot interact with
-- objects normally (e.g hold weapons, use items, etc). An example of this would be a player in handcuffs.
-- @realm shared
-- @treturn bool Whether or not the player is restricted
function meta:IsRestricted()
	return self:GetNetVar("restricted", false)
end

--- Returns `true` if the player is able to shoot their weapon.
-- @realm shared
-- @treturn bool Whether or not the player can shoot their weapon
function meta:CanShootWeapon()
	return self:GetNetVar("canShoot", true)
end

local vectorLength2D = FindMetaTable("Vector").Length2D

--- Returns `true` if the player is running. Running in this case means that their current speed is greater than their
-- regularly set walk speed.
-- @realm shared
-- @treturn bool Whether or not the player is running
function meta:IsRunning()
	return vectorLength2D(self:GetVelocity()) > (self:GetWalkSpeed() + 10)
end

--- Returns `true` if the player currently has a female model. This checks if the model has `female`, `alyx` or `mossman` in its
-- name, or if the player's model class is `citizen_female`.
-- @realm shared
-- @treturn bool Whether or not the player has a female model
function meta:IsFemale()
	local model = self:GetModel():lower()

	return (model:find("female") or model:find("alyx") or model:find("mossman")) != nil or
		ws.anim.GetModelClass(model) == "citizen_female"
end

--- Whether or not this player is stuck and cannot move.
-- @realm shared
-- @treturn bool Whether or not this player is stuck
function meta:IsStuck()
	return util.TraceEntity({
		start = self:GetPos(),
		endpos = self:GetPos(),
		filter = self
	}, self).StartSolid
end

--- Returns a good position in front of the player for an entity to be placed. This is usually used for item entities.
-- @realm shared
-- @entity entity Entity to get a position for
-- @treturn vector Best guess for a good drop position in front of the player
-- @usage local position = client:GetItemDropPos(entity)
-- entity:SetPos(position)
function meta:GetItemDropPos(entity)
	local data = {}
	local trace

	data.start = self:GetShootPos()
	data.endpos = self:GetShootPos() + self:GetAimVector() * 86
	data.filter = self

	if (IsValid(entity)) then
		-- use a hull trace if there's a valid entity to avoid collisions
		local mins, maxs = entity:GetRotatedAABB(entity:OBBMins(), entity:OBBMaxs())

		data.mins = mins
		data.maxs = maxs
		data.filter = {entity, self}
		trace = util.TraceHull(data)
	else
		-- trace along the normal for a few units so we can attempt to avoid a collision
		trace = util.TraceLine(data)

		data.start = trace.HitPos
		data.endpos = data.start + trace.HitNormal * 48
		trace = util.TraceLine(data)
	end

	return trace.HitPos
end

--- Performs a time-delay action that requires this player to look at an entity. If this player looks away from the entity
-- before the action timer completes, the action is cancelled. This is usually used in conjunction with `SetAction` to display
-- progress to the player.
-- @realm shared
-- @entity entity that this player must look at
-- @func callback Function to call when the timer completes
-- @number time How much time in seconds this player must look at the entity for
-- @func[opt=nil] onCancel Function to call when the timer has been cancelled
-- @number[opt=96] distance Maximum distance a player can move away from the entity before the action is cancelled
-- @see SetAction
-- @usage client:SetAction("Searching...", 4) -- for displaying the progress bar
-- client:DoStaredAction(entity, function()
-- 	print("hello!")
-- end)
-- -- prints "hello!" after looking at the entity for 4 seconds
function meta:DoStaredAction(entity, callback, time, onCancel, distance)
	local uniqueID = "wsStare"..self:SteamID64()
	local data = {}
	data.filter = self

	timer.Create(uniqueID, 0.1, time / 0.1, function()
		if (IsValid(self) and IsValid(entity)) then
			data.start = self:GetShootPos()
			data.endpos = data.start + self:GetAimVector()*(distance or 96)

			if (util.TraceLine(data).Entity != entity) then
				timer.Remove(uniqueID)

				if (onCancel) then
					onCancel()
				end
			elseif (callback and timer.RepsLeft(uniqueID) == 0) then
				callback()
			end
		else
			timer.Remove(uniqueID)

			if (onCancel) then
				onCancel()
			end
		end
	end)
end

--- Resets all bodygroups this player's model has to their defaults (`0`).
-- @realm shared
function meta:ResetBodygroups()
	for i = 0, (self:GetNumBodyGroups() - 1) do
		self:SetBodygroup(i, 0)
	end
end

if (SERVER) then
	util.AddNetworkString("wsActionBar")
	util.AddNetworkString("wsActionBarReset")
	util.AddNetworkString("wsStringRequest")

	--- Sets whether or not this player's current weapon is raised.
	-- @realm server
	-- @bool bState Whether or not the raise the weapon
	-- @entity[opt=GetActiveWeapon()] weapon Weapon to raise or lower. You should pass this argument if you already have a
	-- reference to this player's current weapon to avoid an expensive lookup for this player's current weapon.
	function meta:SetWepRaised(bState, weapon)
		weapon = weapon or self:GetActiveWeapon()

		if (IsValid(weapon)) then
			local bCanShoot = !bState and weapon.FireWhenLowered or bState
			self:SetNetVar("raised", bState)

			if (bCanShoot) then
				-- delay shooting while the raise animation is playing
				timer.Create("wsWeaponRaise" .. self:SteamID64(), 1, 1, function()
					if (IsValid(self)) then
						self:SetNetVar("canShoot", true)
					end
				end)
			else
				timer.Remove("wsWeaponRaise" .. self:SteamID64())
				self:SetNetVar("canShoot", false)
			end
		else
			timer.Remove("wsWeaponRaise" .. self:SteamID64())
			self:SetNetVar("raised", false)
			self:SetNetVar("canShoot", false)
		end
	end

	--- Inverts this player's weapon raised state. You should use `SetWepRaised` instead of this if you already have a reference
	-- to this player's current weapon.
	-- @realm server
	function meta:ToggleWepRaised()
		local weapon = self:GetActiveWeapon()

		if (!IsValid(weapon) or
			weapon.IsAlwaysRaised or ALWAYS_RAISED[weapon:GetClass()] or
			weapon.IsAlwaysLowered or weapon.NeverRaised) then
			return
		end

		self:SetWepRaised(!self:IsWepRaised(), weapon)

		if (self:IsWepRaised() and weapon.OnRaised) then
			weapon:OnRaised()
		elseif (!self:IsWepRaised() and weapon.OnLowered) then
			weapon:OnLowered()
		end
	end

	--- Performs a delayed action that requires this player to hold use on an entity. This is displayed to this player as a
	-- closing ring over their crosshair.
	-- @realm server
	-- @number time How much time in seconds this player has to hold use for
	-- @entity entity Entity that this player must be looking at
	-- @func callback Function to run when the timer completes. It will be ran right away if `time` is `0`. Returning `false` in
	-- the callback will not mark this interaction as dirty if you're managing the interaction state manually.
	function meta:PerformInteraction(time, entity, callback)
		if (!IsValid(entity) or entity.wsInteractionDirty) then
			return
		end

		if (time > 0) then
			self.wsInteractionTarget = entity
			self.wsInteractionCharacter = self:GetCharacter():GetID()

			timer.Create("wsCharacterInteraction" .. self:SteamID(), time, 1, function()
				if (IsValid(self) and IsValid(entity) and IsValid(self.wsInteractionTarget) and
					self.wsInteractionCharacter == self:GetCharacter():GetID()) then
					local useEntity = self:GetUseEntity()

					if (IsValid(useEntity) and useEntity == self.wsInteractionTarget and !useEntity.wsInteractionDirty) then
						if (callback(self) != false) then
							useEntity.wsInteractionDirty = true
						end
					end
				end
			end)
		else
			if (callback(self) != false) then
				entity.wsInteractionDirty = true
			end
		end
	end

	--- Displays a progress bar for this player that takes the given amount of time to complete.
	-- @realm server
	-- @string text Text to display above the progress bar
	-- @number[opt=5] time How much time in seconds to wait before the timer completes
	-- @func callback Function to run once the timer completes
	-- @number[opt=CurTime()] startTime Game time in seconds that the timer started. If you are using `time`, then you shouldn't
	-- use this argument
	-- @number[opt=startTime + time] finishTime Game time in seconds that the timer should complete at. If you are using `time`,
	-- then you shouldn't use this argument
	function meta:SetAction(text, time, callback, startTime, finishTime)
		if (time and time <= 0) then
			if (callback) then
				callback(self)
			end

			return
		end

		-- Default the time to five seconds.
		time = time or 5
		startTime = startTime or CurTime()
		finishTime = finishTime or (startTime + time)

		if (text == false) then
			timer.Remove("wsAct"..self:SteamID64())

			net.Start("wsActionBarReset")
			net.Send(self)

			return
		end

		if (!text) then
			net.Start("wsActionBarReset")
			net.Send(self)
		else
			net.Start("wsActionBar")
				net.WriteFloat(startTime)
				net.WriteFloat(finishTime)
				net.WriteString(text)
			net.Send(self)
		end

		-- If we have provided a callback, run it delayed.
		if (callback) then
			-- Create a timer that runs once with a delay.
			timer.Create("wsAct"..self:SteamID64(), time, 1, function()
				-- Call the callback if the player is still valid.
				if (IsValid(self)) then
					callback(self)
				end
			end)
		end
	end

	--- Opens up a text box on this player's screen for input and returns the result. Remember to sanitize the user's input if
	-- it's needed!
	-- @realm server
	-- @string title Title to display on the panel
	-- @string subTitle Subtitle to display on the panel
	-- @func callback Function to run when this player enters their input. Callback is ran with the user's input string.
	-- @string[opt=nil] default Default value to put in the text box.
	-- @usage client:RequestString("Hello", "Please enter your name", function(text)
	-- 	client:ChatPrint("Hello, " .. text)
	-- end)
	-- -- prints "Hello, <text>" in the player's chat
	function meta:RequestString(title, subTitle, callback, default)
		local time = math.floor(os.time())

		self.wsStrReqs = self.wsStrReqs or {}
		self.wsStrReqs[time] = callback

		net.Start("wsStringRequest")
			net.WriteUInt(time, 32)
			net.WriteString(title)
			net.WriteString(subTitle)
			net.WriteString(default or "")
		net.Send(self)
	end

	--- Sets this player's restricted status.
	-- @realm server
	-- @bool bState Whether or not to restrict this player
	-- @bool bNoMessage Whether or not to suppress the restriction notification
	function meta:SetRestricted(bState, bNoMessage)
		if (bState) then
			self:SetNetVar("restricted", true)

			if (bNoMessage) then
				self:SetLocalVar("restrictNoMsg", true)
			end

			self.wsRestrictWeps = self.wsRestrictWeps or {}

			for _, v in ipairs(self:GetWeapons()) do
				self.wsRestrictWeps[#self.wsRestrictWeps + 1] = {
					class = v:GetClass(),
					item = v.wsItem,
					clip = v:Clip1()
				}

				v:Remove()
			end

			hook.Run("OnPlayerRestricted", self)
		else
			self:SetNetVar("restricted")

			if (self:GetLocalVar("restrictNoMsg")) then
				self:SetLocalVar("restrictNoMsg")
			end

			if (self.wsRestrictWeps) then
				for _, v in ipairs(self.wsRestrictWeps) do
					local weapon = self:Give(v.class, true)

					if (v.item) then
						weapon.wsItem = v.item
					end

					weapon:SetClip1(v.clip)
				end

				self.wsRestrictWeps = nil
			end

			hook.Run("OnPlayerUnRestricted", self)
		end
	end

	--- Creates a ragdoll entity of this player that will be synced with clients. This does **not** affect the player like
	-- `SetRagdolled` does.
	-- @realm server
	-- @bool[opt=false] bDontSetPlayer Whether or not to avoid setting the ragdoll's owning player
	-- @treturn entity Created ragdoll entity
	function meta:CreateServerRagdoll(bDontSetPlayer)
		local entity = ents.Create("prop_ragdoll")
		entity:SetPos(self:GetPos())
		entity:SetAngles(self:EyeAngles())
		entity:SetModel(self:GetModel())
		entity:SetSkin(self:GetSkin())

		for i = 0, (self:GetNumBodyGroups() - 1) do
			entity:SetBodygroup(i, self:GetBodygroup(i))
		end

		entity:Spawn()

		if (!bDontSetPlayer) then
			entity:SetNetVar("player", self)
		end

		entity:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		entity:Activate()

		local velocity = self:GetVelocity()

		for i = 0, entity:GetPhysicsObjectCount() - 1 do
			local physObj = entity:GetPhysicsObjectNum(i)

			if (IsValid(physObj)) then
				physObj:SetVelocity(velocity)

				local index = entity:TranslatePhysBoneToBone(i)

				if (index) then
					local position, angles = self:GetBonePosition(index)

					physObj:SetPos(position)
					physObj:SetAngles(angles)
				end
			end
		end

		return entity
	end

	--- Sets this player's ragdoll status.
	-- @realm server
	-- @bool bState Whether or not to ragdoll this player
	-- @number[opt=0] time How long this player should stay ragdolled for. Set to `0` if they should stay ragdolled until they
	-- get back up manually
	-- @number[opt=5] getUpGrace How much time in seconds to wait before the player is able to get back up manually. Set to
	-- the same number as `time` to disable getting up manually entirely
	function meta:SetRagdolled(bState, time, getUpGrace)
		if (!self:Alive()) then
			return
		end

		getUpGrace = getUpGrace or time or 5

		if (bState) then
			if (IsValid(self.wsRagdoll)) then
				self.wsRagdoll:Remove()
			end

			local entity = self:CreateServerRagdoll()

			entity:CallOnRemove("fixer", function()
				if (IsValid(self)) then
					self:SetLocalVar("blur", nil)
					self:SetLocalVar("ragdoll", nil)

					if (!entity.wsNoReset) then
						self:SetPos(entity:GetPos())
					end

					self:SetNoDraw(false)
					self:SetNotSolid(false)
					self:SetMoveType(MOVETYPE_WALK)
					self:SetLocalVelocity(IsValid(entity) and entity.wsLastVelocity or vector_origin)
				end

				if (IsValid(self) and !entity.wsIgnoreDelete) then
					if (entity.wsWeapons) then
						for _, v in ipairs(entity.wsWeapons) do
							if (v.class) then
								local weapon = self:Give(v.class, true)

								if (v.item) then
									weapon.wsItem = v.item
								end

								self:SetAmmo(v.ammo, weapon:GetPrimaryAmmoType())
								weapon:SetClip1(v.clip)
							elseif (v.item and v.invID == v.item.invID) then
								v.item:Equip(self, true, true)
								self:SetAmmo(v.ammo, self.carryWeapons[v.item.weaponCategory]:GetPrimaryAmmoType())
							end
						end
					end

					if (entity.wsActiveWeapon) then
						if (self:HasWeapon(entity.wsActiveWeapon)) then
							self:SetActiveWeapon(self:GetWeapon(entity.wsActiveWeapon))
						else
							local weapons = self:GetWeapons()
							if (#weapons > 0) then
								self:SetActiveWeapon(weapons[1])
							end
						end
					end

					if (self:IsStuck()) then
						entity:DropToFloor()
						self:SetPos(entity:GetPos() + Vector(0, 0, 16))

						local positions = ws.util.FindEmptySpace(self, {entity, self})

						for _, v in ipairs(positions) do
							self:SetPos(v)

							if (!self:IsStuck()) then
								return
							end
						end
					end
				end
			end)

			self:SetLocalVar("blur", 25)
			self.wsRagdoll = entity

			entity.wsWeapons = {}
			entity.wsPlayer = self

			if (getUpGrace) then
				entity.wsGrace = CurTime() + getUpGrace
			end

			if (time and time > 0) then
				entity.wsStart = CurTime()
				entity.wsFinish = entity.wsStart + time

				self:SetAction("@wakingUp", nil, nil, entity.wsStart, entity.wsFinish)
			end

			if (IsValid(self:GetActiveWeapon())) then
				entity.wsActiveWeapon = self:GetActiveWeapon():GetClass()
			end

			for _, v in ipairs(self:GetWeapons()) do
				if (v.wsItem and v.wsItem.Equip and v.wsItem.Unequip) then
					entity.wsWeapons[#entity.wsWeapons + 1] = {
						item = v.wsItem,
						invID = v.wsItem.invID,
						ammo = self:GetAmmoCount(v:GetPrimaryAmmoType())
					}
					v.wsItem:Unequip(self, false)
				else
					local clip = v:Clip1()
					local reserve = self:GetAmmoCount(v:GetPrimaryAmmoType())
					entity.wsWeapons[#entity.wsWeapons + 1] = {
						class = v:GetClass(),
						item = v.wsItem,
						clip = clip,
						ammo = reserve
					}
				end
			end

			self:GodDisable()
			self:StripWeapons()
			self:SetMoveType(MOVETYPE_OBSERVER)
			self:SetNoDraw(true)
			self:SetNotSolid(true)

			local uniqueID = "wsUnRagdoll" .. self:SteamID()

			if (time) then
				timer.Create(uniqueID, 0.33, 0, function()
					if (IsValid(entity) and IsValid(self) and self.wsRagdoll == entity) then
						local velocity = entity:GetVelocity()
						entity.wsLastVelocity = velocity

						self:SetPos(entity:GetPos())

						if (velocity:Length2D() >= 8) then
							if (!entity.wsPausing) then
								self:SetAction()
								entity.wsPausing = true
							end

							return
						elseif (entity.wsPausing) then
							self:SetAction("@wakingUp", time)
							entity.wsPausing = false
						end

						time = time - 0.33

						if (time <= 0) then
							entity:Remove()
						end
					else
						timer.Remove(uniqueID)
					end
				end)
			else
				timer.Create(uniqueID, 0.33, 0, function()
					if (IsValid(entity) and IsValid(self) and self.wsRagdoll == entity) then
						self:SetPos(entity:GetPos())
					else
						timer.Remove(uniqueID)
					end
				end)
			end

			self:SetLocalVar("ragdoll", entity:EntIndex())
			hook.Run("OnCharacterFallover", self, entity, true)
		elseif (IsValid(self.wsRagdoll)) then
			self.wsRagdoll:Remove()

			hook.Run("OnCharacterFallover", self, nil, false)
		end
	end
end
