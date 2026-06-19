
local PLUGIN = PLUGIN

PLUGIN.name = "Areas"
PLUGIN.author = "`impulse"
PLUGIN.description = "Provides customizable area definitions."

ws.area = ws.area or {}
ws.area.types = ws.area.types or {}
ws.area.properties = ws.area.properties or {}
ws.area.stored = ws.area.stored or {}

ws.config.Add("areaTickTime", 1, "How many seconds between each time a character's current area is calculated.",
	function(oldValue, newValue)
		if (SERVER) then
			timer.Adjust("wsAreaThink", newValue)
		end
	end,
	{
		data = {min = 0.1, max = 4},
		category = "areas"
	}
)

function ws.area.AddProperty(name, type, default, data)
	ws.area.properties[name] = {
		type = type,
		default = default,
		data = data or {}
	}
end

function ws.area.AddType(type, name)
	name = name or type

	-- only store localized strings on the client
	ws.area.types[type] = CLIENT and name or true
end

function PLUGIN:SetupAreaProperties()
	ws.area.AddType("area")

	ws.area.AddProperty("color", ws.type.color, ws.config.Get("color"))
	ws.area.AddProperty("display", ws.type.bool, true)
end

ws.util.Include("sv_plugin.lua")
ws.util.Include("cl_plugin.lua")
ws.util.Include("sv_hooks.lua")
ws.util.Include("cl_hooks.lua")

-- return world center, local min, and local max from world start/end positions
function PLUGIN:GetLocalAreaPosition(startPosition, endPosition)
	local center = LerpVector(0.5, startPosition, endPosition)
	local min = WorldToLocal(startPosition, angle_zero, center, angle_zero)
	local max = WorldToLocal(endPosition, angle_zero, center, angle_zero)

	return center, min, max
end

do
	local COMMAND = {}
	COMMAND.description = "@cmdAreaEdit"
	COMMAND.adminOnly = true

	function COMMAND:OnRun(client)
		client:SetWepRaised(false)

		net.Start("wsAreaEditStart")
		net.Send(client)
	end

	ws.command.Add("AreaEdit", COMMAND)
end

do
	local PLAYER = FindMetaTable("Player")

	-- returns the current area the player is in, or the last valid one if the player is not in an area
	function PLAYER:GetArea()
		return self.wsArea
	end

	-- returns true if the player is in any area, this does not use the last valid area like GetArea does
	function PLAYER:IsInArea()
		return self.wsInArea
	end
end
