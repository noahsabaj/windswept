
local PLUGIN = PLUGIN

PLUGIN.name = "Spawns"
PLUGIN.description = "A flat list of spawn points; players spawn at a random one."
PLUGIN.author = "Chessnut"
PLUGIN.spawns = PLUGIN.spawns or {}

function PLUGIN:PlayerLoadout(client)
	if (self.spawns and !table.IsEmpty(self.spawns)) then
		local position = self.spawns[math.random(#self.spawns)]

		if (position) then
			client:SetPos(position)
		end
	end
end

function PLUGIN:LoadData()
	self.spawns = self:GetData() or {}
end

function PLUGIN:SaveSpawns()
	self:SetData(self.spawns)
end

ws.command.Add("SpawnAdd", {
	description = "@cmdSpawnAdd",
	privilege = "Manage Spawn Points",
	adminOnly = true,
	OnRun = function(self, client)
		table.insert(PLUGIN.spawns, client:GetPos())
		PLUGIN:SaveSpawns()

		return "@spawnAdded", tostring(#PLUGIN.spawns)
	end
})

ws.command.Add("SpawnRemove", {
	description = "@cmdSpawnRemove",
	privilege = "Manage Spawn Points",
	adminOnly = true,
	arguments = bit.bor(ws.type.number, ws.type.optional),
	OnRun = function(self, client, radius)
		radius = radius or 120

		local position = client:GetPos()
		local kept = {}
		local removed = 0

		-- Rebuild the list densely so the array never develops holes.
		for _, v in ipairs(PLUGIN.spawns) do
			if (v:Distance(position) <= radius) then
				removed = removed + 1
			else
				kept[#kept + 1] = v
			end
		end

		if (removed > 0) then
			PLUGIN.spawns = kept
			PLUGIN:SaveSpawns()
		end

		return "@spawnDeleted", removed
	end
})
