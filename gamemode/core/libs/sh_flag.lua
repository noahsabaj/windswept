
--[[--
Grants abilities to characters.

Flags are a simple way of adding/removing certain abilities to players on a per-character basis. Windswept comes with a few flags
by default, for example to restrict spawning of props, usage of the physgun, etc. All flags will be listed in the
`Flags` section of the `Help` menu. Flags are usually used when server validation is required to allow a player to do something
on their character. However, it's usually preferable to use in-character methods over flags when possible (i.e restricting
the business menu to characters that have a permit item, rather than using flags to determine availability).

Flags are a single alphanumeric character that can be checked on the server. Serverside callbacks can be used to provide
functionality whenever the flag is added or removed. For example:
	ws.flag.Add("z", "Access to some cool stuff.", function(client, bGiven)
		print("z flag given:", bGiven)
	end)

	Entity(1):GetCharacter():GiveFlags("z")
	> z flag given: true

	Entity(1):GetCharacter():TakeFlags("z")
	> z flag given: false

	print(Entity(1):GetCharacter():HasFlags("z"))
	> false

Check out `Character:GiveFlags` and `Character:TakeFlags` for additional info.
]]
-- @module ws.flag

ws.flag = ws.flag or {}
ws.flag.list = ws.flag.list or {}

--- Creates a flag. This should be called shared in order for the client to be aware of the flag's existence.
-- @realm shared
-- @string flag Alphanumeric character to use for the flag
-- @string description Description of the flag
-- @func callback Function to call when the flag is given or taken from a player
function ws.flag.Add(flag, description, callback)
	ws.flag.list[flag] = {
		description = description,
		callback = callback
	}
end

if (SERVER) then
	-- Called to apply flags when a player has spawned.
	-- @realm server
	-- @internal
	-- @player client Player to setup flags for
	function ws.flag.OnSpawn(client)
		-- Check if they have a valid character.
		if (client:GetCharacter()) then
			-- Get all of the character's flags.
			local flags = client:GetCharacter():GetFlags()

			for i = 1, #flags do
				-- Get each individual flag.
				local flag = flags[i]
				local info = ws.flag.list[flag]

				-- Check if the flag has a callback.
				if (info and info.callback) then
					-- Run the callback, passing the player and true so they get whatever benefits.
					info.callback(client, true)
				end
			end
		end
	end
end

do
	local character = ws.meta.character

	if (SERVER) then
		--- Flag util functions for character
		-- @classmod Character

		--- Sets this character's accessible flags. Note that this method overwrites **all** flags instead of adding them.
		-- @realm server
		-- @string flags Flag(s) this charater is allowed to have
		-- @see GiveFlags
		function character:SetFlags(flags)
			self:SetData("f", flags)
		end

		--- Adds a flag to the list of this character's accessible flags. This does not overwrite existing flags.
		-- @realm server
		-- @string flags Flag(s) this character should be given
		-- @usage character:GiveFlags("pet")
		-- -- gives p, e, and t flags to the character
		-- @see HasFlags
		function character:GiveFlags(flags)
			local addedFlags = ""

			-- Get the individual flags within the flag string.
			for i = 1, #flags do
				local flag = flags[i]
				local info = ws.flag.list[flag]

				-- Only act (and fire the callback) when the flag actually changes from
				-- not-present to present; firing on an already-held flag re-runs side
				-- effects like re-Giving a weapon. (fw-faction-class-9)
				if (info and !self:HasFlags(flag)) then
					addedFlags = addedFlags..flag

					if (info.callback) then
						-- Pass the player and true (true for the flag being given.)
						info.callback(self:GetPlayer(), true)
					end
				end
			end

			-- Only change the flag string if it is different.
			if (addedFlags != "") then
				self:SetFlags(self:GetFlags()..addedFlags)
			end
		end

		--- Removes this character's access to the given flags.
		-- @realm server
		-- @string flags Flag(s) to remove from this character
		-- @usage -- for a character with "pet" flags
		-- character:TakeFlags("p")
		-- -- character now has e, and t flags
		function character:TakeFlags(flags)
			local oldFlags = self:GetFlags()
			local newFlags = oldFlags

			-- Get the individual flags within the flag string.
			for i = 1, #flags do
				local flag = flags[i]
				local info = ws.flag.list[flag]

				-- Only act (and fire the callback) when the character actually has the
				-- flag being removed; firing on an absent flag re-runs StripWeapon and
				-- the like. Use plain-text replacement (no Lua patterns) to match
				-- HasFlags' literal find. (fw-faction-class-9)
				if (self:HasFlags(flag)) then
					if (info and info.callback) then
						-- Pass the player and false (false since the flag is being taken)
						info.callback(self:GetPlayer(), false)
					end

					newFlags = newFlags:gsub(flag:PatternSafe(), "")
				end
			end

			if (newFlags != oldFlags) then
				self:SetFlags(newFlags)
			end
		end
	end

	--- Returns all of the flags this character has.
	-- @realm shared
	-- @treturn string Flags this character has represented as one string. You can access individual flags by iterating through
	-- the string letter by letter
	function character:GetFlags()
		return self:GetData("f", "")
	end

	--- Returns `true` if the character has the given flag(s).
	-- @realm shared
	-- @string flags Flag(s) to check access for
	-- @treturn bool Whether or not this character has access to the given flag(s)
	function character:HasFlags(flags)
		local bHasFlag = hook.Run("CharacterHasFlags", self, flags)

		if (bHasFlag == true) then
			return true
		end

		local flagList = self:GetFlags()

		for i = 1, #flags do
			if (flagList:find(flags[i], 1, true)) then
				return true
			end
		end

		return false
	end
end

do
	ws.flag.Add("p", "Access to the physgun.", function(client, isGiven)
		if (isGiven) then
			client:Give("weapon_physgun")
			client:SelectWeapon("weapon_physgun")
		else
			client:StripWeapon("weapon_physgun")
		end
	end)

	ws.flag.Add("t", "Access to the toolgun", function(client, isGiven)
		if (isGiven) then
			client:Give("gmod_tool")
			client:SelectWeapon("gmod_tool")
		else
			client:StripWeapon("gmod_tool")
		end
	end)

	ws.flag.Add("c", "Access to spawn chairs.")
	ws.flag.Add("C", "Access to spawn vehicles.")
	ws.flag.Add("r", "Access to spawn ragdolls.")
	ws.flag.Add("e", "Access to spawn props.")
	ws.flag.Add("n", "Access to spawn NPCs.")
end
