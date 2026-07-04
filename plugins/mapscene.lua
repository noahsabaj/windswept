
local PLUGIN = PLUGIN

PLUGIN.name = "Map Scenes"
PLUGIN.author = "Chessnut"
PLUGIN.description = "Adds areas of the map that are visible during character selection."
PLUGIN.scenes = PLUGIN.scenes or {}

local x3, y3 = 0, 0
local realOrigin = Vector(0, 0, 0)
local realAngles = Angle(0, 0, 0)
local view = {}

if (CLIENT) then
	PLUGIN.ordered = PLUGIN.ordered or {}

	function PLUGIN:CalcView(client, origin, angles, fov)
		local scenes = self.scenes

		if (IsValid(ws.gui.characterMenu) and !IsValid(ws.gui.menu) and !ws.gui.characterMenu:IsClosing() and
			!table.IsEmpty(scenes)) then
			local key = self.index
			local value = scenes[self.index]

			if (!self.index or !value) then
				value, key = table.Random(scenes)
				self.index = key
			end

			if (self.orderedIndex or value.origin or isvector(key)) then
				local curTime = CurTime()

				self.orderedIndex = self.orderedIndex or 1

				local ordered = self.ordered[self.orderedIndex]

				if (ordered) then
					key = ordered[1]
					value = ordered[2]
				end

				if (!self.startTime) then
					self.startTime = curTime
					self.finishTime = curTime + 30
				end

				local fraction = math.min(math.TimeFraction(self.startTime, self.finishTime, CurTime()), 1)

				if (value) then
					realOrigin = LerpVector(fraction, key, value[1])
					realAngles = LerpAngle(fraction, value[2], value[3])
				end

				if (fraction >= 1) then
					self.startTime = curTime
					self.finishTime = curTime + 30

					if (ordered) then
						self.orderedIndex = self.orderedIndex + 1

						if (self.orderedIndex > #self.ordered) then
							self.orderedIndex = 1
						end
					else
						-- Re-pick any random scene by its (stable integer) key. (fw-medium-M5)
						local _, sceneKey = table.Random(scenes)
						self.index = sceneKey
					end
				end
			elseif (value) then
				realOrigin = value[1]
				realAngles = value[2]
			end

			local x, y = gui.MousePos()
			local x2, y2 = ScrW() * 0.5, ScrH() * 0.5
			local frameTime = FrameTime() * 0.5

			y3 = Lerp(frameTime, y3, math.Clamp((y - y2) / y2, -1, 1) * -6)
			x3 = Lerp(frameTime, x3, math.Clamp((x - x2) / x2, -1, 1) * 6)

			view.origin = realOrigin + realAngles:Up()*y3 + realAngles:Right()*x3
			view.angles = realAngles + Angle(y3 * -0.5, x3 * -0.5, 0)

			return view
		end
	end

	function PLUGIN:PreDrawViewModel(viewModel, client, weapon)
		if (IsValid(ws.gui.characterMenu) and !ws.gui.characterMenu:IsClosing()) then
			return true
		end
	end

	-- Add/remove are admin-only and rare, so the server broadcasts the full scene list on every
	-- change (single wsMapSceneSync) instead of incremental per-item add/remove messages. This
	-- removes the old client/server key mismatch (pairs were Vector-keyed on the client but
	-- integer-keyed on the server, so they could never be removed) and the array holes that
	-- corrupted the save round-trip. (fw-medium-M5)
	net.Receive("wsMapSceneSync", function()
		local length = net.ReadUInt(32)
		local data = net.ReadData(length)
		local uncompressed = util.Decompress(data)

		if (!uncompressed) then
			ErrorNoHalt("[Windswept] Unable to decompress map scene data!\n")
			return
		end

		PLUGIN.scenes = util.JSONToTable(uncompressed) or {}
		PLUGIN.ordered = {}
		PLUGIN.index = nil
		PLUGIN.orderedIndex = nil

		-- Rebuild the moving-camera cycle from the pair scenes (identified by .origin).
		for _, v in pairs(PLUGIN.scenes) do
			if (v.origin) then
				table.insert(PLUGIN.ordered, {v.origin, v})
			end
		end
	end)
else
	util.AddNetworkString("wsMapSceneSync")

	function PLUGIN:SaveScenes()
		self:SetData(self.scenes)
	end

	function PLUGIN:LoadData()
		self.scenes = self:GetData() or {}
	end

	-- Broadcast the full scene list, or send it to a single receiver. (fw-medium-M5)
	function PLUGIN:SyncScenes(receiver)
		local json = util.TableToJSON(self.scenes)
		local compressed = util.Compress(json)
		local length = compressed:len()

		net.Start("wsMapSceneSync")
			net.WriteUInt(length, 32)
			net.WriteData(compressed, length)

		if (receiver) then
			net.Send(receiver)
		else
			net.Broadcast()
		end
	end

	function PLUGIN:PlayerInitialSpawn(client)
		self:SyncScenes(client)
	end

	function PLUGIN:AddScene(position, angles, position2, angles2)
		if (position2) then
			self.scenes[#self.scenes + 1] = {origin = position, position2, angles, angles2}
		else
			self.scenes[#self.scenes + 1] = {position, angles}
		end

		self:SaveScenes()
		self:SyncScenes()
	end
end

ws.command.Add("MapSceneAdd", {
	description = "@cmdMapSceneAdd",
	privilege = "Manage Map Scenes",
	adminOnly = true,
	arguments = bit.bor(ws.type.bool, ws.type.optional),
	OnRun = function(self, client, bIsPair)
		local position, angles = client:EyePos(), client:EyeAngles()

		-- This scene is in a pair for moving scenes.
		if (tobool(bIsPair) and !client.wsScnPair) then
			client.wsScnPair = {position, angles}

			return "@mapRepeat"
		else
			if (client.wsScnPair) then
				PLUGIN:AddScene(client.wsScnPair[1], client.wsScnPair[2], position, angles)
				client.wsScnPair = nil
			else
				PLUGIN:AddScene(position, angles)
			end

			return "@mapAdd"
		end
	end
})

ws.command.Add("MapSceneRemove", {
	description = "@cmdMapSceneRemove",
	privilege = "Manage Map Scenes",
	adminOnly = true,
	arguments = bit.bor(ws.type.number, ws.type.optional),
	OnRun = function(self, client, radius)
		radius = radius or 280

		local position = client:GetPos()
		local toRemove = {}

		for k, v in pairs(PLUGIN.scenes) do
			-- single: v[1] = position. pair: v.origin = start, v[1] = end position.
			local origin = v.origin or v[1]
			local endPos = v.origin and v[1]

			if ((origin and origin:Distance(position) <= radius) or
				(endPos and endPos:Distance(position) <= radius)) then
				toRemove[#toRemove + 1] = k
			end
		end

		-- Remove the highest index first so table.remove doesn't shift the lower indices,
		-- keeping the array contiguous (clean save + sync). (fw-medium-M5)
		table.sort(toRemove, function(a, b) return a > b end)

		for _, k in ipairs(toRemove) do
			table.remove(PLUGIN.scenes, k)
		end

		if (#toRemove > 0) then
			PLUGIN:SaveScenes()
			PLUGIN:SyncScenes()
		end

		return "@mapDel", #toRemove
	end
})
