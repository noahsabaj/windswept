
--[[--
Persistent date and time handling.

All of Lua's time functions are dependent on the Unix epoch, which means we can't have dates that go further than 1970. This
library remedies this problem. Time/date is represented by a `date` object that is queried, instead of relying on the seconds
since the epoch.

## Futher documentation
This library makes use of a third-party date library found at https://github.com/Tieske/date - you can find all documentation
regarding the `date` object and its methods there.
]]
-- @module ws.date

ws.date = ws.date or {}
ws.date.lib = ws.date.lib or include("thirdparty/sh_date.lua")
ws.date.timeScale = ws.date.timeScale or ws.config.Get("secondsPerMinute", 60) -- seconds per minute
ws.date.current = ws.date.current or ws.date.lib() -- current in-game date/time
ws.date.start = ws.date.start or CurTime() -- arbitrary start time for calculating date/time offset
ws.date.yearOffset = 174 -- offset from real year (2026 + 174 = 2200)

if (SERVER) then
	util.AddNetworkString("wsDateSync")

	--- Initializes the date from real-world time with year offset.
	-- @realm server
	-- @internal
	function ws.date.Initialize()
		-- Always sync with real-world date, applying year offset
		-- Real year 2026 + offset 174 = in-game year 2200
		local realYear = tonumber(os.date("%Y")) or 2026
		local currentDate = {
			year = realYear + ws.date.yearOffset,
			month = tonumber(os.date("%m")) or 1,
			day = tonumber(os.date("%d")) or 1,
			hour = tonumber(os.date("%H")) or 0,
			min = tonumber(os.date("%M")) or 0,
			sec = tonumber(os.date("%S")) or 0
		}

		ws.date.timeScale = ws.config.Get("secondsPerMinute", 60)
		ws.date.current = ws.date.lib(currentDate)

		-- Update config to reflect actual date (for display purposes)
		ws.date.bSaving = true
		ws.config.Set("year", currentDate.year)
		ws.config.Set("month", currentDate.month)
		ws.config.Set("day", currentDate.day)
		ws.date.bSaving = nil
	end

	--- Updates the internal in-game date/time representation and resets the offset.
	-- @realm server
	-- @internal
	function ws.date.ResolveOffset()
		ws.date.current = ws.date.Get()
		ws.date.start = CurTime()
	end

	--- Updates the time scale of the in-game date/time. The time scale is given in seconds per minute (i.e how many real life
	-- seconds it takes for an in-game minute to pass). You should avoid using this function and use the in-game config menu to
	-- change the time scale instead.
	-- @realm server
	-- @internal
	-- @number secondsPerMinute New time scale
	function ws.date.UpdateTimescale(secondsPerMinute)
		ws.date.ResolveOffset()
		ws.date.timeScale = secondsPerMinute
	end

	--- Sends the current date to a player. This is done automatically when the player joins the server.
	-- @realm server
	-- @internal
	-- @player[opt=nil] client Player to send the date to, or `nil` to send to everyone
	function ws.date.Send(client)
		net.Start("wsDateSync")

		net.WriteFloat(ws.date.timeScale)
		net.WriteTable(ws.date.current)
		net.WriteFloat(ws.date.start)

		if (client) then
			net.Send(client)
		else
			net.Broadcast()
		end
	end

	--- Updates config to reflect current date (no disk persistence needed since we sync from real time).
	-- @realm server
	-- @internal
	function ws.date.Save()
		ws.date.bSaving = true
		ws.date.ResolveOffset()

		-- Update config to reflect current date for display purposes
		ws.config.Set("year", ws.date.current:getyear())
		ws.config.Set("month", ws.date.current:getmonth())
		ws.config.Set("day", ws.date.current:getday())

		ws.date.bSaving = nil
	end
else
	net.Receive("wsDateSync", function()
		local timeScale = net.ReadFloat()
		local currentDate = ws.date.lib.construct(net.ReadTable())
		local startTime = net.ReadFloat()

		ws.date.timeScale = timeScale
		ws.date.current = currentDate
		ws.date.start = startTime
	end)
end

--- Returns the currently set date.
-- @realm shared
-- @treturn date Current in-game date
function ws.date.Get()
	local minutesSinceStart = (CurTime() - ws.date.start) / ws.date.timeScale

	return ws.date.current:copy():addminutes(minutesSinceStart)
end

--- Returns a string formatted version of a date.
-- @realm shared
-- @string format Format string
-- @date[opt=nil] currentDate Date to format. If nil, it will use the currently set date
-- @treturn string Formatted date
function ws.date.GetFormatted(format, currentDate)
	return (currentDate or ws.date.Get()):fmt(format)
end

--- Returns a serialized version of a date. This is useful when you need to network a date to clients, or save a date to disk.
-- @realm shared
-- @date[opt=nil] currentDate Date to serialize. If nil, it will use the currently set date
-- @treturn table Serialized date
function ws.date.GetSerialized(currentDate)
	return ws.date.lib.serialize(currentDate or ws.date.Get())
end

--- Returns a date object from a table or serialized date.
-- @realm shared
-- @param currentDate Date to construct
-- @treturn date Constructed date object
function ws.date.Construct(currentDate)
	return ws.date.lib.construct(currentDate)
end
