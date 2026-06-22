--- World/entity helpers: useable-entity caps, empty-space finding, queued sound
-- emission, safe table merge, look-at-player.
--
-- Split out of core/sh_util.lua for readability (PR-3); pure relocation, the public
-- ws.util.* API is unchanged. Loaded by sh_util.lua after its file-inclusion bootstrap.
-- @module ws.util


-- luacheck: globals FCAP_IMPULSE_USE FCAP_CONTINUOUS_USE FCAP_ONOFF_USE
-- luacheck: globals FCAP_DIRECTIONAL_USE FCAP_USE_ONGROUND FCAP_USE_IN_RADIUS
FCAP_IMPULSE_USE = 0x00000010
FCAP_CONTINUOUS_USE = 0x00000020
FCAP_ONOFF_USE = 0x00000040
FCAP_DIRECTIONAL_USE = 0x00000080
FCAP_USE_ONGROUND = 0x00000100
FCAP_USE_IN_RADIUS = 0x00000200

function ws.util.IsUseableEntity(entity, requiredCaps)
	if (IsValid(entity)) then
		local caps = entity:ObjectCaps()

		if (bit.band(caps, bit.bor(FCAP_IMPULSE_USE, FCAP_CONTINUOUS_USE, FCAP_ONOFF_USE, FCAP_DIRECTIONAL_USE))) then
			if (bit.band(caps, requiredCaps) == requiredCaps) then
				return true
			end
		end
	end
end

do
	local function IntervalDistance(x, x0, x1)
		-- swap so x0 < x1
		if (x0 > x1) then
			local tmp = x0

			x0 = x1
			x1 = tmp
		end

		if (x < x0) then
			return x0-x
		elseif (x > x1) then
			return x - x1
		end

		return 0
	end

	local NUM_TANGENTS = 8
	local tangents = {0, 1, 0.57735026919, 0.3639702342, 0.267949192431, 0.1763269807, -0.1763269807, -0.267949192431}
	local traceMin = Vector(-16, -16, -16)
	local traceMax = Vector(16, 16, 16)

	function ws.util.FindUseEntity(player, origin, forward)
		local tr
		local up = forward:Up()
		-- Search for objects in a sphere (tests for entities that are not solid, yet still useable)
		local searchCenter = origin

		-- NOTE: Some debris objects are useable too, so hit those as well
		-- A button, etc. can be made out of clip brushes, make sure it's +useable via a traceline, too.
		local useableContents = bit.bor(MASK_SOLID, CONTENTS_DEBRIS, CONTENTS_PLAYERCLIP)

		-- UNDONE: Might be faster to just fold this range into the sphere query
		local pObject

		local nearestDist = 1e37
		-- try the hit entity if there is one, or the ground entity if there isn't.
		local pNearest = NULL

		for i = 1, NUM_TANGENTS do
			-- The loop starts at 1, so the old `if (i == 0)` straight-traceline branch was
			-- dead code; removed. (fw-config-command-boot-15)
			local down = forward - tangents[i] * up
			down:Normalize()

			tr = util.TraceHull({
				start = searchCenter,
				endpos = searchCenter + down * 72,
				mins = traceMin,
				maxs = traceMax,
				mask = useableContents,
				filter = player
			})

			tr.EndPos = searchCenter + down * 72

			pObject = tr.Entity

			local bUsable = ws.util.IsUseableEntity(pObject, 0)

			while (IsValid(pObject) and !bUsable and pObject:GetMoveParent()) do
				pObject = pObject:GetMoveParent()
				bUsable = ws.util.IsUseableEntity(pObject, 0)
			end

			if (bUsable) then
				local delta = tr.EndPos - tr.StartPos
				local centerZ = origin.z - player:WorldSpaceCenter().z
				delta.z = IntervalDistance(tr.EndPos.z, centerZ - player:OBBMins().z, centerZ + player:OBBMaxs().z)
				local dist = delta:Length()

				if (dist < 80) then
					pNearest = pObject
				end
			end
		end

		-- check ground entity first
		-- if you've got a useable ground entity, then shrink the cone of this search to 45 degrees
		-- otherwise, search out in a 90 degree cone (hemisphere)
		if (IsValid(player:GetGroundEntity()) and ws.util.IsUseableEntity(player:GetGroundEntity(), FCAP_USE_ONGROUND)) then
			pNearest = player:GetGroundEntity()
		end

		if (IsValid(pNearest)) then
			-- estimate nearest object by distance from the view vector
			local point = pNearest:NearestPoint(searchCenter)
			nearestDist = util.DistanceToLine(searchCenter, forward, point)
		end

		for _, v in ipairs(ents.FindInSphere(searchCenter, 80)) do
			if (!ws.util.IsUseableEntity(v, FCAP_USE_IN_RADIUS)) then
				continue
			end

			-- see if it's more roughly in front of the player than previous guess
			local point = v:NearestPoint(searchCenter)

			local dir = point - searchCenter
			dir:Normalize()
			local dot = dir:Dot(forward)

			-- Need to be looking at the object more or less
			if (dot < 0.8) then
				continue
			end

			local dist = util.DistanceToLine(searchCenter, forward, point)

			if (dist < nearestDist) then
				-- Since this has purely been a radius search to this point, we now
				-- make sure the object isn't behind glass or a grate.
				local trCheckOccluded = {}

				util.TraceLine({
					start = searchCenter,
					endpos = point,
					mask = useableContents,
					filter = player,
					output = trCheckOccluded
				})

				if (trCheckOccluded.fraction == 1.0 or trCheckOccluded.Entity == v) then
					pNearest = v
					nearestDist = dist
				end
			end
		end

		return pNearest
	end
end

ALWAYS_RAISED = {}
ALWAYS_RAISED["weapon_physgun"] = true
ALWAYS_RAISED["gmod_tool"] = true
ALWAYS_RAISED["ws_poshelper"] = true

function ws.util.FindEmptySpace(entity, filter, spacing, size, height, tolerance)
	spacing = spacing or 32
	size = size or 3
	height = height or 36
	tolerance = tolerance or 5

	local position = entity:GetPos()
	local mins, maxs = Vector(-spacing * 0.5, -spacing * 0.5, 0), Vector(spacing * 0.5, spacing * 0.5, height)
	local output = {}

	for x = -size, size do
		for y = -size, size do
			local origin = position + Vector(x * spacing, y * spacing, 0)

			local data = {}
				data.start = origin + mins + Vector(0, 0, tolerance)
				data.endpos = origin + maxs
				data.filter = filter or entity
			local trace = util.TraceLine(data)

			data.start = origin + Vector(-maxs.x, -maxs.y, tolerance)
			data.endpos = origin + Vector(mins.x, mins.y, height)

			local trace2 = util.TraceLine(data)

			if (trace.StartSolid or trace.Hit or trace2.StartSolid or trace2.Hit or !util.IsInWorld(origin)) then
				continue
			end

			output[#output + 1] = origin
		end
	end

	table.sort(output, function(a, b)
		return a:DistToSqr(position) < b:DistToSqr(position)
	end)

	return output
end

-- Time related stuff.
do
	--- Gets the current time in the UTC time-zone.
	-- @realm shared
	-- @treturn number Current time in UTC
	function ws.util.GetUTCTime()
		local date = os.date("!*t")
		local localDate = os.date("*t")
		localDate.isdst = false

		return os.difftime(os.time(date), os.time(localDate))
	end

	-- Setup for time strings.
	local TIME_UNITS = {}
	TIME_UNITS["s"] = 1						-- Seconds
	TIME_UNITS["m"] = 60					-- Minutes
	TIME_UNITS["h"] = 3600					-- Hours
	TIME_UNITS["d"] = TIME_UNITS["h"] * 24	-- Days
	TIME_UNITS["w"] = TIME_UNITS["d"] * 7	-- Weeks
	TIME_UNITS["mo"] = TIME_UNITS["d"] * 30	-- Months
	TIME_UNITS["y"] = TIME_UNITS["d"] * 365	-- Years

	--- Gets the amount of seconds from a given formatted string. If no time units are specified, it is assumed minutes.
	-- The valid values are as follows:
	--
	-- - `s` - Seconds
	-- - `m` - Minutes
	-- - `h` - Hours
	-- - `d` - Days
	-- - `w` - Weeks
	-- - `mo` - Months
	-- - `y` - Years
	-- @realm shared
	-- @string text Text to interpret a length of time from
	-- @treturn[1] number Amount of seconds from the length interpreted from the given string
	-- @treturn[2] 0 If the given string does not have a valid time
	-- @usage print(ws.util.GetStringTime("5y2d7w"))
	-- > 162086400 -- 5 years, 2 days, 7 weeks
	function ws.util.GetStringTime(text)
		local minutes = tonumber(text)

		if (minutes) then
			return math.abs(minutes * 60)
		end

		local time = 0

		for amount, unit in text:lower():gmatch("(%d+)(%a+)") do
			amount = tonumber(amount)

			if (amount and TIME_UNITS[unit]) then
				time = time + math.abs(amount * TIME_UNITS[unit])
			end
		end

		return time
	end
end

--[[
	Credit to TFA for figuring this mess out.
	Original: https://steamcommunity.com/sharedfiles/filedetails/?id=903541818
]]

if (system.IsLinux()) then
	local cache = {}

	-- Helper Functions
	local function GetSoundPath(path, gamedir)
		if (!gamedir) then
			path = "sound/" .. path
			gamedir = "GAME"
		end

		return path, gamedir
	end

	local function f_IsWAV(f)
		f:Seek(8)

		return f:Read(4) == "WAVE"
	end

	-- WAV functions
	local function f_SampleDepth(f)
		f:Seek(34)
		local bytes = {}

		for i = 1, 2 do
			bytes[i] = f:ReadByte(1)
		end

		local num = bit.lshift(bytes[2], 8) + bit.lshift(bytes[1], 0)

		return num
	end

	local function f_SampleRate(f)
		f:Seek(24)
		local bytes = {}

		for i = 1, 4 do
			bytes[i] = f:ReadByte(1)
		end

		local num = bit.lshift(bytes[4], 24) + bit.lshift(bytes[3], 16) + bit.lshift(bytes[2], 8) + bit.lshift(bytes[1], 0)

		return num
	end

	local function f_Channels(f)
		f:Seek(22)
		local bytes = {}

		for i = 1, 2 do
			bytes[i] = f:ReadByte(1)
		end

		local num = bit.lshift(bytes[2], 8) + bit.lshift(bytes[1], 0)

		return num
	end

	local function f_Duration(f)
		return (f:Size() - 44) / (f_SampleDepth(f) / 8 * f_SampleRate(f) * f_Channels(f))
	end

	wsSoundDuration = wsSoundDuration or SoundDuration -- luacheck: globals wsSoundDuration

	function SoundDuration(str) -- luacheck: globals SoundDuration
		local path, gamedir = GetSoundPath(str)
		local f = file.Open(path, "rb", gamedir)

		if (!f) then return 0 end --Return nil on invalid files

		local ret

		if (cache[str]) then
			ret = cache[str]
		elseif (f_IsWAV(f)) then
			ret = f_Duration(f)
		else
			ret = wsSoundDuration(str)
		end

		f:Close()

		return ret
	end
end

local ADJUST_SOUND = SoundDuration("npc/metropolice/pain1.wav") > 0 and "" or "../../hl2/sound/"

--- Emits sounds one after the other from an entity.
-- @realm shared
-- @entity entity Entity to play sounds from
-- @tab sounds Sound paths to play
-- @number delay[opt=0] How long to wait before starting to play the sounds
-- @number spacing[opt=0.1] How long to wait between playing each sound
-- @number volume[opt=75] The sound level of each sound
-- @number pitch[opt=100] Pitch percentage of each sound
-- @treturn number How long the entire sequence of sounds will take to play
function ws.util.EmitQueuedSounds(entity, sounds, delay, spacing, volume, pitch)
	-- Let there be a delay before any sound is played.
	delay = delay or 0
	spacing = spacing or 0.1

	-- Loop through all of the sounds.
	for _, v in ipairs(sounds) do
		local postSet, preSet = 0, 0

		-- Determine if this sound has special time offsets.
		if (istable(v)) then
			postSet, preSet = v[2] or 0, v[3] or 0
			v = v[1]
		end

		-- Get the length of the sound.
		local length = SoundDuration(ADJUST_SOUND..v)
		-- If the sound has a pause before it is played, add it here.
		delay = delay + preSet

		-- Have the sound play in the future.
		timer.Simple(delay, function()
			-- Check if the entity still exists and play the sound.
			if (IsValid(entity)) then
				entity:EmitSound(v, volume, pitch)
			end
		end)

		-- Add the delay for the next sound.
		delay = delay + length + postSet + spacing
	end

	-- Return how long it took for the whole thing.
	return delay
end

--- Merges the contents of the second table with the content in the first one. The destination table will be modified.
--- If element is table but not metatable object, value's elements will be changed only.
-- @realm shared
-- @tab destination The table you want the source table to merge with
-- @tab source The table you want to merge with the destination table
-- @return table
function ws.util.MetatableSafeTableMerge(destination, source)
	for k, v in pairs(source) do
		if (istable(v) and istable(destination[k]) and getmetatable(v) == nil) then
			-- don't overwrite one table with another
			-- instead merge them recurisvely
			ws.util.MetatableSafeTableMerge(destination[k], v);
		else
			destination[ k ] = v;
		end
	end
	return destination;
end

--- Returns the player the given client is aiming at within range.
-- @realm shared
-- @player client The player whose aim to trace
-- @number[opt=96] maxRange Maximum trace distance in units
-- @treturn player|nil The player being aimed at, or nil
function ws.util.GetLookAtPlayer(client, maxRange)
	maxRange = maxRange or 96

	local data = {}
	data.start = client:GetShootPos()
	data.endpos = data.start + client:GetAimVector() * maxRange
	data.filter = client

	local target = util.TraceLine(data).Entity

	if IsValid(target) and target:IsPlayer() then
		return target
	end

	return nil
end

