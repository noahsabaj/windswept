
util.AddNetworkString("wsDoorMenu")
util.AddNetworkString("wsDoorPermission")

-- Variables for door data.
local variables = {
	-- Whether or not the door will be disabled.
	"disabled",
	-- The name of the door.
	"name",
	-- Price of the door.
	"price",
	-- If the door is ownable.
	"ownable",
	-- The factions that own a door (table of faction indices).
	"factions",
	-- The class that owns a door.
	"class",
	-- Whether or not the door will be hidden.
	"visible"
}

function PLUGIN:CallOnDoorChildren(entity, callback)
	local parent

	if (entity.wsChildren) then
		parent = entity
	elseif (entity.wsParent) then
		parent = entity.wsParent
	end

	if (IsValid(parent)) then
		callback(parent)

		for k, _ in pairs(parent.wsChildren) do
			local child = ents.GetMapCreatedEntity(k)

			if (IsValid(child)) then
				callback(child)
			end
		end
	end
end

function PLUGIN:CopyParentDoor(child)
	local parent = child.wsParent

	if (IsValid(parent)) then
		for _, v in ipairs(variables) do
			local value = parent:GetNetVar(v)

			if (child:GetNetVar(v) != value) then
				child:SetNetVar(v, value)
			end
		end
	end
end

-- Called after the entities have loaded.
function PLUGIN:LoadData()
	-- Restore the saved door information.
	local data = self:GetData()

	if (!data) then
		return
	end

	-- Loop through all of the saved doors.
	for k, v in pairs(data) do
		-- Get the door entity from the saved ID.
		local entity = ents.GetMapCreatedEntity(k)

		-- Check it is a valid door in-case something went wrong.
		if (IsValid(entity) and entity:IsDoor()) then
			-- Loop through all of our door variables.
			for k2, v2 in pairs(v) do
				if (k2 == "children") then
					entity.wsChildren = v2

					for index, _ in pairs(v2) do
						local door = ents.GetMapCreatedEntity(index)

						if (IsValid(door)) then
							door.wsParent = entity
						end
					end
				elseif (k2 == "factions") then
					-- New multi-faction format
					local factionIDs = {}
					local factionIndices = {}
					for _, uniqueID in ipairs(v2) do
						local factionData = ws.faction.teams[uniqueID]
						if (factionData) then
							table.insert(factionIDs, uniqueID)
							table.insert(factionIndices, factionData.index)
						end
					end
					if (#factionIDs > 0) then
						entity.wsFactionIDs = factionIDs
						entity:SetNetVar("factions", factionIndices)
					end
				elseif (k2 == "faction") then
					-- Backwards compatibility: convert old single-faction format to multi-faction
					local factionData = ws.faction.teams[v2]
					if (factionData) then
						entity.wsFactionIDs = {v2}
						entity:SetNetVar("factions", {factionData.index})
					end
				else
					entity:SetNetVar(k2, v2)
				end
			end
		end
	end
end

-- Called before the gamemode shuts down.
function PLUGIN:SaveDoorData()
	-- Create an empty table to save information in.
	local data = {}
		local doors = {}

		for _, v in ents.Iterator() do
			if (v:IsDoor()) then
				doors[v:MapCreationID()] = v
			end
		end

		local doorData

		-- Loop through doors with information.
		for k, v in pairs(doors) do
			-- Another empty table for actual information regarding the door.
			doorData = {}

			-- Save all of the needed variables to the doorData table.
			for _, v2 in ipairs(variables) do
				local value = v:GetNetVar(v2)

				if (value) then
					doorData[v2] = v:GetNetVar(v2)
				end
			end

			if (v.wsChildren) then
				doorData.children = v.wsChildren
			end

			if (v.wsClassID) then
				doorData.class = v.wsClassID
			end

			if (v.wsFactionIDs and #v.wsFactionIDs > 0) then
				doorData.factions = v.wsFactionIDs
			end

			-- Add the door to the door information.
			if (!table.IsEmpty(doorData)) then
				data[k] = doorData
			end
		end
	-- Save all of the door information.
	self:SetData(data)
end

function PLUGIN:CanPlayerUseDoor(client, entity)
	if (entity:GetNetVar("disabled")) then
		return false
	end
end

-- Whether or not a player a player has any abilities over the door, such as locking.
function PLUGIN:CanPlayerAccessDoor(client, door, access)
	local factions = door:GetNetVar("factions")

	-- If the door has factions set, check if the client is a member of any of them.
	if (factions) then
		for _, factionIndex in ipairs(factions) do
			if (client:Team() == factionIndex) then
				return true
			end
		end
	end

	local class = door:GetNetVar("class")

	-- If the door has a faction set which the client is a member of, allow access.
	local classData = ws.class.list[class]
	local charClass = client:GetCharacter():GetClass()
	local classData2 = ws.class.list[charClass]

	if (class and classData and classData2) then
		if (classData.team) then
			if (classData.team != classData2.team) then
				return false
			end
		else
			if (charClass != class) then
				return false
			end
		end

		return true
	end
end

function PLUGIN:ShowTeam(client)
	local data = {}
		data.start = client:GetShootPos()
		data.endpos = data.start + client:GetAimVector() * 96
		data.filter = client
	local trace = util.TraceLine(data)
	local entity = trace.Entity

	local factions = entity:GetNetVar("factions")
	if (IsValid(entity) and entity:IsDoor() and (!factions or #factions == 0) and !entity:GetNetVar("class")) then
		if (entity:CheckDoorAccess(client, DOOR_TENANT)) then
			local door = entity

			if (IsValid(door.wsParent)) then
				door = door.wsParent
			end

			net.Start("wsDoorMenu")
				net.WriteEntity(door)
				net.WriteTable(door.wsAccess)
				net.WriteEntity(entity)
			net.Send(client)
		elseif (!IsValid(entity:GetDTEntity(0))) then
			ws.command.Run(client, "doorbuy")
		else
			client:NotifyLocalized("notAllowed")
		end

		return true
	end
end

function PLUGIN:PlayerLoadedCharacter(client, curChar, prevChar)
	if (prevChar) then
		local doors = prevChar:GetVar("doors") or {}

		for _, v in ipairs(doors) do
			if (IsValid(v) and v:IsDoor() and v:GetDTEntity(0) == client) then
				v:RemoveDoorAccessData()
			end
		end

		prevChar:SetVar("doors", nil)
	end
end

function PLUGIN:PlayerDisconnected(client)
	local character = client:GetCharacter()

	if (character) then
		local doors = character:GetVar("doors") or {}

		for _, v in ipairs(doors) do
			if (IsValid(v) and v:IsDoor() and v:GetDTEntity(0) == client) then
				v:RemoveDoorAccessData()
			end
		end

		character:SetVar("doors", nil)
	end
end

net.Receive("wsDoorPermission", function(length, client)
	local door = net.ReadEntity()
	local target = net.ReadEntity()
	local access = net.ReadUInt(4)

	if (IsValid(target) and target:GetCharacter() and door.wsAccess and door:GetDTEntity(0) == client and target != client) then
		access = math.Clamp(access or 0, DOOR_NONE, DOOR_TENANT)

		if (access == door.wsAccess[target]) then
			return
		end

		door.wsAccess[target] = access

		local recipient = {}

		for k, v in pairs(door.wsAccess) do
			if (v > DOOR_GUEST) then
				recipient[#recipient + 1] = k
			end
		end

		if (#recipient > 0) then
			net.Start("wsDoorPermission")
				net.WriteEntity(door)
				net.WriteEntity(target)
				net.WriteUInt(access, 4)
			net.Send(recipient)
		end
	end
end)
