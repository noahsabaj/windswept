
local PLUGIN = PLUGIN

ix.command.Add("DoorSell", {
	description = "@cmdDoorSell",
	OnRun = function(self, client, arguments)
		-- Get the entity 96 units infront of the player.
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector() * 96
			data.filter = client
		local trace = util.TraceLine(data)
		local entity = trace.Entity

		-- Check if the entity is a valid door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			-- Check if the player owners the door.
			if (client == entity:GetDTEntity(0)) then
				entity = IsValid(entity.ixParent) and entity.ixParent or entity

				-- Get the price that the door is sold for.
				local price = math.Round(entity:GetNetVar("price", ix.config.Get("doorCost")) * ix.config.Get("doorSellRatio"))
				local character = client:GetCharacter()

				-- Remove old door information.
				entity:RemoveDoorAccessData()

				local doors = character:GetVar("doors") or {}

				for k, v in ipairs(doors) do
					if (v == entity) then
						table.remove(doors, k)
					end
				end

				character:SetVar("doors", doors, true)

				-- Take their money and notify them.
				character:GiveMoney(price)
				hook.Run("OnPlayerPurchaseDoor", client, entity, false, PLUGIN.CallOnDoorChildren)

				ix.log.Add(client, "selldoor")
				return "@dSold", ix.currency.Get(price)
			else
				-- Otherwise tell them they can not.
				return "@notOwner"
			end
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorBuy", {
	description = "@cmdDoorBuy",
	OnRun = function(self, client, arguments)
		-- Get the entity 96 units infront of the player.
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector() * 96
			data.filter = client
		local trace = util.TraceLine(data)
		local entity = trace.Entity

		-- Check if the entity is a valid door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			local factions = entity:GetNetVar("factions")
			if (!entity:GetNetVar("ownable") or (factions and #factions > 0) or entity:GetNetVar("class")) then
				return "@dNotAllowedToOwn"
			end

			if (IsValid(entity:GetDTEntity(0))) then
				return "@dOwnedBy", entity:GetDTEntity(0):Name()
			end

			entity = IsValid(entity.ixParent) and entity.ixParent or entity

			-- Get the price that the door is bought for.
			local price = entity:GetNetVar("price", ix.config.Get("doorCost"))
			local character = client:GetCharacter()

			-- Check if the player can actually afford it.
			if (character:HasMoney(price)) then
				-- Set the door to be owned by this player.
				entity:SetDTEntity(0, client)
				entity.ixAccess = {
					[client] = DOOR_OWNER
				}

				PLUGIN:CallOnDoorChildren(entity, function(child)
					child:SetDTEntity(0, client)
				end)

				local doors = character:GetVar("doors") or {}
					doors[#doors + 1] = entity
				character:SetVar("doors", doors, true)

				-- Take their money and notify them.
				character:TakeMoney(price)
				hook.Run("OnPlayerPurchaseDoor", client, entity, true, PLUGIN.CallOnDoorChildren)

				ix.log.Add(client, "buydoor")
				return "@dPurchased", ix.currency.Get(price)
			else
				-- Otherwise tell them they can not.
				return "@canNotAfford"
			end
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetUnownable", {
	description = "@cmdDoorSetUnownable",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = ix.type.text,
	OnRun = function(self, client, name)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			-- Set it so it is unownable.
			entity:SetNetVar("ownable", nil)

			-- Change the name of the door if needed.
			if (name:find("%S")) then
				entity:SetNetVar("name", name)
			end

			PLUGIN:CallOnDoorChildren(entity, function(child)
				child:SetNetVar("ownable", nil)

				if (name:find("%S")) then
					child:SetNetVar("name", name)
				end
			end)

			-- Save the door information.
			PLUGIN:SaveDoorData()
			return "@dMadeUnownable"
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetOwnable", {
	description = "@cmdDoorSetOwnable",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = ix.type.text,
	OnRun = function(self, client, name)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			-- Set it so it is ownable.
			entity:SetNetVar("ownable", true)
			entity:SetNetVar("visible", true)

			-- Update the name.
			if (name:find("%S")) then
				entity:SetNetVar("name", name)
			end

			PLUGIN:CallOnDoorChildren(entity, function(child)
				child:SetNetVar("ownable", true)
				child:SetNetVar("visible", true)

				if (name:find("%S")) then
					child:SetNetVar("name", name)
				end
			end)

			-- Save the door information.
			PLUGIN:SaveDoorData()
			return "@dMadeOwnable"
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

-- Add a faction to the door
ix.command.Add("DoorAddFaction", {
	description = "@cmdDoorAddFaction",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = ix.type.text,
	OnRun = function(self, client, name)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (!IsValid(entity) or !entity:IsDoor() or entity:GetNetVar("disabled")) then
			return "@dNotValid"
		end

		-- Find the faction
		local faction
		for k, v in pairs(ix.faction.teams) do
			if (ix.util.StringMatches(k, name) or ix.util.StringMatches(L(v.name, client), name)) then
				faction = v
				break
			end
		end

		if (!faction) then
			return "@invalidFaction"
		end

		-- Initialize or get existing factions
		entity.ixFactionIDs = entity.ixFactionIDs or {}
		local factions = entity:GetNetVar("factions") or {}

		-- Check if already added
		for _, id in ipairs(entity.ixFactionIDs) do
			if (id == faction.uniqueID) then
				return "@dFactionAlreadyAdded"
			end
		end

		-- Add the faction
		table.insert(entity.ixFactionIDs, faction.uniqueID)
		table.insert(factions, faction.index)
		entity:SetNetVar("factions", factions)

		-- Apply to children
		PLUGIN:CallOnDoorChildren(entity, function(child)
			child.ixFactionIDs = table.Copy(entity.ixFactionIDs)
			child:SetNetVar("factions", table.Copy(factions))
		end)

		PLUGIN:SaveDoorData()
		return "@dAddedFaction", L(faction.name, client)
	end
})

-- Remove a faction from the door
ix.command.Add("DoorRemoveFaction", {
	description = "@cmdDoorRemoveFaction",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = ix.type.text,
	OnRun = function(self, client, name)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (!IsValid(entity) or !entity:IsDoor() or entity:GetNetVar("disabled")) then
			return "@dNotValid"
		end

		-- Find the faction
		local faction
		for k, v in pairs(ix.faction.teams) do
			if (ix.util.StringMatches(k, name) or ix.util.StringMatches(L(v.name, client), name)) then
				faction = v
				break
			end
		end

		if (!faction) then
			return "@invalidFaction"
		end

		entity.ixFactionIDs = entity.ixFactionIDs or {}
		local factions = entity:GetNetVar("factions") or {}

		-- Find and remove
		local found = false
		for i, id in ipairs(entity.ixFactionIDs) do
			if (id == faction.uniqueID) then
				table.remove(entity.ixFactionIDs, i)
				table.remove(factions, i)
				found = true
				break
			end
		end

		if (!found) then
			return "@dFactionNotOnDoor"
		end

		entity:SetNetVar("factions", #factions > 0 and factions or nil)

		-- Apply to children
		PLUGIN:CallOnDoorChildren(entity, function(child)
			child.ixFactionIDs = table.Copy(entity.ixFactionIDs)
			child:SetNetVar("factions", #factions > 0 and table.Copy(factions) or nil)
		end)

		PLUGIN:SaveDoorData()
		return "@dRemovedFaction", L(faction.name, client)
	end
})

-- Clear all factions from the door
ix.command.Add("DoorClearFactions", {
	description = "@cmdDoorClearFactions",
	privilege = "Manage Doors",
	adminOnly = true,
	OnRun = function(self, client)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (!IsValid(entity) or !entity:IsDoor() or entity:GetNetVar("disabled")) then
			return "@dNotValid"
		end

		entity.ixFactionIDs = nil
		entity:SetNetVar("factions", nil)

		-- Apply to children
		PLUGIN:CallOnDoorChildren(entity, function(child)
			child.ixFactionIDs = nil
			child:SetNetVar("factions", nil)
		end)

		PLUGIN:SaveDoorData()
		return "@dClearedFactions"
	end
})

ix.command.Add("DoorSetDisabled", {
	description = "@cmdDoorSetDisabled",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = ix.type.bool,
	OnRun = function(self, client, bDisabled)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor()) then
			-- Set it so it is ownable.
			entity:SetNetVar("disabled", bDisabled)

			PLUGIN:CallOnDoorChildren(entity, function(child)
				child:SetNetVar("disabled", bDisabled)
			end)

			PLUGIN:SaveDoorData()

			-- Tell the player they have made the door (un)disabled.
			return "@dSet" .. (bDisabled and "" or "Not") .. "Disabled"
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetTitle", {
	description = "@cmdDoorSetTitle",
	arguments = ix.type.text,
	OnRun = function(self, client, name)
		-- Get the door infront of the player.
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector() * 96
			data.filter = client
		local trace = util.TraceLine(data)
		local entity = trace.Entity

		-- Validate the door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			-- Make sure the name contains actual characters.
			if (!name:find("%S")) then
				return "@invalidArg", 1
			end

			--[[
				NOTE: Here, we are setting two different networked names.
				The title is a temporary name, while the other name is the
				default name for the door. The reason for this is so when the
				server closes while someone owns the door, it doesn't save THEIR
				title, which could lead to unwanted things.
			--]]

			name = name:utf8sub(1, 24)

			-- Check if they are allowed to change the door's name.
			if (entity:CheckDoorAccess(client, DOOR_TENANT)) then
				entity:SetNetVar("title", name)
			elseif (CAMI.PlayerHasAccess(client, "Helix - Manage Doors", nil)) then
				entity:SetNetVar("name", name)

				PLUGIN:CallOnDoorChildren(entity, function(child)
					child:SetNetVar("name", name)
				end)
			else
				-- Otherwise notify the player he/she can't.
				return "@notOwner"
			end
		else
			-- Notification of the door not being valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetParent", {
	description = "@cmdDoorSetParent",
	privilege = "Manage Doors",
	adminOnly = true,
	OnRun = function(self, client, arguments)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			client.ixDoorParent = entity
			return "@dSetParentDoor"
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetChild", {
	description = "@cmdDoorSetChild",
	privilege = "Manage Doors",
	adminOnly = true,
	OnRun = function(self, client, arguments)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			if (client.ixDoorParent == entity) then
				return "@dCanNotSetAsChild"
			end

			-- Check if the player has set a door as a parent.
			if (IsValid(client.ixDoorParent)) then
				-- Add the door to the parent's list of children.
				client.ixDoorParent.ixChildren = client.ixDoorParent.ixChildren or {}
				client.ixDoorParent.ixChildren[entity:MapCreationID()] = true

				-- Set the door's parent to the parent.
				entity.ixParent = client.ixDoorParent

				-- Save the door information.
				PLUGIN:SaveDoorData()
				PLUGIN:CopyParentDoor(entity)

				return "@dAddChildDoor"
			else
				-- Tell the player they do not have a door parent.
				return "@dNoParentDoor"
			end
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorRemoveChild", {
	description = "@cmdDoorRemoveChild",
	privilege = "Manage Doors",
	adminOnly = true,
	OnRun = function(self, client, arguments)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			if (client.ixDoorParent == entity) then
				PLUGIN:CallOnDoorChildren(entity, function(child)
					child.ixParent = nil
				end)

				entity.ixChildren = nil
				return "@dRemoveChildren"
			end

			-- Check if the player has set a door as a parent.
			if (IsValid(entity.ixParent) and entity.ixParent.ixChildren) then
				-- Remove the door from the list of children.
				entity.ixParent.ixChildren[entity:MapCreationID()] = nil
				-- Remove the variable for the parent.
				entity.ixParent = nil

				PLUGIN:SaveDoorData()
				return "@dRemoveChildDoor"
			end
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetHidden", {
	description = "@cmdDoorSetHidden",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = ix.type.bool,
	OnRun = function(self, client, bHidden)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor()) then
			entity:SetNetVar("visible", !bHidden)

			PLUGIN:CallOnDoorChildren(entity, function(child)
				child:SetNetVar("visible", !bHidden)
			end)

			PLUGIN:SaveDoorData()

			-- Tell the player they have made the door (un)hidden.
			return "@dSet" .. (bHidden and "" or "Not") .. "Hidden"
		else
			-- Tell the player the door isn't valid.
			return "@dNotValid"
		end
	end
})

ix.command.Add("DoorSetClass", {
	description = "@cmdDoorSetClass",
	privilege = "Manage Doors",
	adminOnly = true,
	arguments = bit.bor(ix.type.text, ix.type.optional),
	OnRun = function(self, client, name)
		-- Get the door the player is looking at.
		local entity = client:GetEyeTrace().Entity

		-- Validate it is a door.
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			if (!name or name == "") then
				entity:SetNetVar("class", nil)

				PLUGIN:CallOnDoorChildren(entity, function()
					entity:SetNetVar("class", nil)
				end)

				PLUGIN:SaveDoorData()
				return "@dRemoveClass"
			end

			local class, classData

			for k, v in pairs(ix.class.list) do
				if (ix.util.StringMatches(v.name, name) or ix.util.StringMatches(L(v.name, client), name)) then
					class, classData = k, v

					break
				end
			end

			-- Check if a faction was found.
			if (class) then
				entity.ixClassID = class
				entity:SetNetVar("class", class)

				PLUGIN:CallOnDoorChildren(entity, function()
					entity.ixClassID = class
					entity:SetNetVar("class", class)
				end)

				PLUGIN:SaveDoorData()
				return "@dSetClass", L(classData.name, client)
			else
				return "@invalidClass"
			end
		end
	end
})
