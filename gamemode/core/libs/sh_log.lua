
--[[--
Logging helper functions.

Predefined flags:
	FLAG_NORMAL
	FLAG_SUCCESS
	FLAG_WARNING
	FLAG_DANGER
	FLAG_SERVER
	FLAG_DEV
]]
-- @module ws.log

-- luacheck: globals FLAG_NORMAL FLAG_SUCCESS FLAG_WARNING FLAG_DANGER FLAG_SERVER FLAG_DEV
FLAG_NORMAL = 0
FLAG_SUCCESS = 1
FLAG_WARNING = 2
FLAG_DANGER = 3
FLAG_SERVER = 4
FLAG_DEV = 5

ws.log = ws.log or {}
ws.log.color = {
	[FLAG_NORMAL] = Color(200, 200, 200),
	[FLAG_SUCCESS] = Color(50, 200, 50),
	[FLAG_WARNING] = Color(255, 255, 0),
	[FLAG_DANGER] = Color(255, 50, 50),
	[FLAG_SERVER] = Color(200, 200, 220),
	[FLAG_DEV] = Color(200, 200, 220),
}

CAMI.RegisterPrivilege({
	Name = "Windswept - Logs",
	MinAccess = "admin"
})

local consoleColor = Color(50, 200, 50)

if (SERVER) then
	if (!ws.db) then
		include("sv_database.lua")
	end

	util.AddNetworkString("wsLogStream")

	function ws.log.LoadTables()
		ws.log.CallHandler("Load")
	end

	ws.log.types = ws.log.types or {}

	--- Registers a log type for `ws.log.Add`.
	-- `format` is either a format string or a function `(client, ...) -> string`.
	--
	-- `flag` is a display/severity tag (see `FLAG_*`). If omitted, it behaves like a normal log.
	-- @realm server
	-- @tparam string logType Type name used when calling `ws.log.Add`.
	-- @tparam string|function format Format string or formatter function.
	-- @tparam[opt] number flag One of the `FLAG_*` constants.
	-- @usage
	-- ws.log.AddType("charMoneyGive", "%s gave %s %d tokens.", FLAG_SUCCESS)
	function ws.log.AddType(logType, format, flag)
		ws.log.types[logType] = {format = format, flag = flag}
	end

	--- Turns a log type + args into `(message, flag)`.
	-- Missing type falls back to a warning string. No formatter returns `-1` (caller bails).
	-- @internal
	-- @realm server
	-- @tparam Player|nil client Player tied to the log.
	-- @tparam string logType Log type name.
	-- @param ... Arguments for the formatter.
	-- @treturn string|number Message string, or -1 to skip logging.
	-- @treturn number Flag from the registered type.
	function ws.log.Parse(client, logType, ...)
		local info = ws.log.types[logType]

		if (!info) then
			ErrorNoHalt("attempted to add entry to non-existent log type \"" .. tostring(logType) .. "\"\n")
			local fallback = logType.." : "
			if (client) then
				fallback = fallback..client:Name().." - "
			end
			for _, v in ipairs({...}) do
				fallback = fallback..tostring(v).." "
			end
			return fallback, FLAG_WARNING
		end

		local text = info and info.format

		if (text) then
			if (isfunction(text)) then
				text = text(client, ...)
			end
		else
			text = -1
		end

		return text, info.flag
	end

	--- Adds a log entry without using a log type.
	-- Sends the message to admins with log access, prints it to the server console,
	-- and writes it through log handlers unless `bNoSave` is true.
	-- @realm server
	-- @tparam string logString Pre-formatted log message.
	-- @tparam[opt] boolean bNoSave If true, skips handler output (e.g. file logging).
	-- @usage ws.log.AddRaw("Server is restarting in 5 minutes.")
	-- @see ws.log.Add
	function ws.log.AddRaw(logString, bNoSave)
		CAMI.GetPlayersWithAccess("Windswept - Logs", function(receivers)
			ws.log.Send(receivers, logString)
		end)

		Msg("[LOG] ", logString .. "\n")

		if (!bNoSave) then
			ws.log.CallHandler("Write", nil, logString)
		end
	end

	--- Adds a typed log entry.
	-- The entry is visible to admins with log access, printed to the server console,
	-- and written through the logging system.
	-- @realm server
	-- @tparam Player|nil client Player tied to the log (can be nil).
	-- @tparam string logType Type registered with `ws.log.AddType`.
	-- @param ... Arguments for the formatter.
	-- @usage ws.log.Add(client, "charMoneyGive", giverName, receiverName, amount)
	-- @see ws.log.AddType
	-- @see ws.log.AddRaw
	function ws.log.Add(client, logType, ...)
		local logString, logFlag = ws.log.Parse(client, logType, ...)
		if (logString == -1) then return end

		CAMI.GetPlayersWithAccess("Windswept - Logs", function(receivers)
			ws.log.Send(receivers, logString, logFlag)
		end)

		Msg("[LOG] ", logString .. "\n")

		ws.log.CallHandler("Write", client, logString, logFlag, logType, {...})
	end

	--- Sends a log entry to clients.
	-- @internal
	-- @realm server
	-- @tparam Player|table receivers Target player(s).
	-- @tparam string logString Log message.
	-- @tparam[opt] number flag `FLAG_*` value (defaults to normal).
	function ws.log.Send(receivers, logString, flag)
		net.Start("wsLogStream")
			net.WriteString(logString)
			net.WriteUInt(flag or 0, 4)
		net.Send(receivers)
	end

	ws.log.handlers = ws.log.handlers or {}

	--- Calls a specific event on all registered log handlers.
	-- @realm server
	-- @internal
	function ws.log.CallHandler(event, ...)
		for _, v in pairs(ws.log.handlers) do
			if (isfunction(v[event])) then
				v[event](...)
			end
		end
	end

	-- Register a log handler
	-- @realm server
	-- @internal
	function ws.log.RegisterHandler(name, data)
		data.name = string.gsub(name, "%s", "")
			name = name:lower()
		data.uniqueID = name

		ws.log.handlers[name] = data
	end

	do
		local HANDLER = {}

		function HANDLER.Load()
			file.CreateDir("windswept/logs")
		end

		function HANDLER.Write(client, message)
			file.Append("windswept/logs/" .. os.date("%x"):gsub("/", "-") .. ".txt", "[" .. os.date("%X") .. "]\t" .. message .. "\r\n")
		end

		ws.log.RegisterHandler("File", HANDLER)
	end
else
	net.Receive("wsLogStream", function(length)
		local logString = net.ReadString()
		local flag = net.ReadUInt(4)

		if (isstring(logString) and isnumber(flag)) then
			MsgC(consoleColor, "[SERVER] ", ws.log.color[flag], logString .. "\n")
		end
	end)
end

