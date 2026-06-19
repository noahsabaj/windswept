
util.AddNetworkString("wsAreaSync")
util.AddNetworkString("wsAreaAdd")
util.AddNetworkString("wsAreaRemove")
util.AddNetworkString("wsAreaChanged")

util.AddNetworkString("wsAreaEditStart")
util.AddNetworkString("wsAreaEditEnd")

ws.log.AddType("areaAdd", function(client, name)
	return string.format("%s has added area \"%s\".", client:Name(), tostring(name))
end)

ws.log.AddType("areaRemove", function(client, name)
	return string.format("%s has removed area \"%s\".", client:Name(), tostring(name))
end)

local function SortVector(first, second)
	return Vector(math.min(first.x, second.x), math.min(first.y, second.y), math.min(first.z, second.z)),
		Vector(math.max(first.x, second.x), math.max(first.y, second.y), math.max(first.z, second.z))
end

function ws.area.Create(name, type, startPosition, endPosition, bNoReplicate, properties)
	local min, max = SortVector(startPosition, endPosition)

	ws.area.stored[name] = {
		type = type or "area",
		startPosition = min,
		endPosition = max,
		bNoReplicate = bNoReplicate,
		properties = properties
	}

	-- network to clients if needed
	if (!bNoReplicate) then
		net.Start("wsAreaAdd")
			net.WriteString(name)
			net.WriteString(type)
			net.WriteVector(startPosition)
			net.WriteVector(endPosition)
			net.WriteTable(properties)
		net.Broadcast()
	end
end

function ws.area.Remove(name, bNoReplicate)
	ws.area.stored[name] = nil

	-- network to clients if needed
	if (!bNoReplicate) then
		net.Start("wsAreaRemove")
			net.WriteString(name)
		net.Broadcast()
	end
end
