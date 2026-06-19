
local entityMeta = FindMetaTable("Entity")
local playerMeta = FindMetaTable("Player")

ws.net = ws.net or {}
ws.net.globals = ws.net.globals or {}

net.Receive("wsGlobalVarSet", function()
	ws.net.globals[net.ReadString()] = net.ReadType()
end)

net.Receive("wsNetVarSet", function()
	local index = net.ReadUInt(16)

	ws.net[index] = ws.net[index] or {}
	ws.net[index][net.ReadString()] = net.ReadType()
end)

net.Receive("wsNetVarDelete", function()
	ws.net[net.ReadUInt(16)] = nil
end)

net.Receive("wsLocalVarSet", function()
	local key = net.ReadString()
	local var = net.ReadType()

	ws.net[LocalPlayer():EntIndex()] = ws.net[LocalPlayer():EntIndex()] or {}
	ws.net[LocalPlayer():EntIndex()][key] = var

	hook.Run("OnLocalVarSet", key, var)
end)

function GetNetVar(key, default) -- luacheck: globals GetNetVar
	local value = ws.net.globals[key]

	return value != nil and value or default
end

function entityMeta:GetNetVar(key, default)
	local index = self:EntIndex()

	if (ws.net[index] and ws.net[index][key] != nil) then
		return ws.net[index][key]
	end

	return default
end

playerMeta.GetLocalVar = entityMeta.GetNetVar
