
--[[--
Persistent date and time handling.

All of Lua's time functions are dependent on the Unix epoch, which means we can't have dates that go further than 1970. This
library remedies this problem. Time/date is represented by a `date` object that is queried, instead of relying on the seconds
since the epoch.

## Futher documentation
This library makes use of a third-party date library found at https://github.com/Tieske/date - you can find all documentation
regarding the `date` object and its methods there.
]]
-- @module ix.date

ix.date = ix.date or {}
ix.date.lib = ix.date.lib or include("thirdparty/sh_date.lua")
ix.date.timeScale = ix.date.timeScale or ix.config.Get("secondsPerMinute", 60) -- seconds per minute
ix.date.current = ix.date.current or ix.date.lib() -- current in-game date/time
ix.date.start = ix.date.start or CurTime() -- arbitrary start time for calculating date/time offset
ix.date.yearOffset = 174 -- offset from real year (2026 + 174 = 2200)

if (SERVER) then
	util.AddNetworkString("ixDateSync")

	--- Initializes the date from real-world time with year offset.
	-- @realm server
	-- @internal
	function ix.date.Initialize()
		-- Always sync with real-world date, applying year offset
		-- Real year 2026 + offset 174 = in-game year 2200
		local realYear = tonumber(os.date("%Y")) or 2026
		local currentDate = {
			year = realYear + ix.date.yearOffset,
			month = tonumber(os.date("%m")) or 1,
			day = tonumber(os.date("%d")) or 1,
			hour = tonumber(os.date("%H")) or 0,
			min = tonumber(os.date("%M")) or 0,
			sec = tonumber(os.date("%S")) or 0
		}

		ix.date.timeScale = ix.config.Get("secondsPerMinute", 60)
		ix.date.current = ix.date.lib(currentDate)

		-- Update config to reflect actual date (for display purposes)
		ix.date.bSaving = true
		ix.config.Set("year", currentDate.year)
		ix.config.Set("month", currentDate.month)
		ix.config.Set("day", currentDate.day)
		ix.date.bSaving = nil
	end

	--- Updates the internal in-game date/time representation and resets the offset.
	-- @realm server
	-- @internal
	function ix.date.ResolveOffset()
		ix.date.current = ix.date.Get()
		ix.date.start = CurTime()
	end

	--- Updates the time scale of the in-game date/time. The time scale is given in seconds per minute (i.e how many real life
	-- seconds it takes for an in-game minute to pass). You should avoid using this function and use the in-game config menu to
	-- change the time scale instead.
	-- @realm server
	-- @internal
	-- @number secondsPerMinute New time scale
	function ix.date.UpdateTimescale(secondsPerMinute)
		ix.date.ResolveOffset()
		ix.date.timeScale = secondsPerMinute
	end

	--- Sends the current date to a player. This is done automatically when the player joins the server.
	-- @realm server
	-- @internal
	-- @player[opt=nil] client Player to send the date to, or `nil` to send to everyone
	function ix.date.Send(client)
		net.Start("ixDateSync")

		net.WriteFloat(ix.date.timeScale)
		net.WriteTable(ix.date.current)
		net.WriteFloat(ix.date.start)

		if (client) then
			net.Send(client)
		else
			net.Broadcast()
		end
	end

	--- Updates config to reflect current date (no disk persistence needed since we sync from real time).
	-- @realm server
	-- @internal
	function ix.date.Save()
		ix.date.bSaving = true
		ix.date.ResolveOffset()

		-- Update config to reflect current date for display purposes
		ix.config.Set("year", ix.date.current:getyear())
		ix.config.Set("month", ix.date.current:getmonth())
		ix.config.Set("day", ix.date.current:getday())

		ix.date.bSaving = nil
	end
else
	net.Receive("ixDateSync", function()
		local timeScale = net.ReadFloat()
		local currentDate = ix.date.lib.construct(net.ReadTable())
		local startTime = net.ReadFloat()

		ix.date.timeScale = timeScale
		ix.date.current = currentDate
		ix.date.start = startTime
	end)
end

--- Returns the currently set date.
-- @realm shared
-- @treturn date Current in-game date
function ix.date.Get()
	local minutesSinceStart = (CurTime() - ix.date.start) / ix.date.timeScale

	return ix.date.current:copy():addminutes(minutesSinceStart)
end

--- Returns a string formatted version of a date.
-- @realm shared
-- @string format Format string
-- @date[opt=nil] currentDate Date to format. If nil, it will use the currently set date
-- @treturn string Formatted date
function ix.date.GetFormatted(format, currentDate)
	return (currentDate or ix.date.Get()):fmt(format)
end

--- Returns a serialized version of a date. This is useful when you need to network a date to clients, or save a date to disk.
-- @realm shared
-- @date[opt=nil] currentDate Date to serialize. If nil, it will use the currently set date
-- @treturn table Serialized date
function ix.date.GetSerialized(currentDate)
	return ix.date.lib.serialize(currentDate or ix.date.Get())
end

--- Returns a date object from a table or serialized date.
-- @realm shared
-- @param currentDate Date to construct
-- @treturn date Constructed date object
function ix.date.Construct(currentDate)
	return ix.date.lib.construct(currentDate)
end
