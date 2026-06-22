PLUGIN.name = "Spawn Saver"
PLUGIN.author = "Chessnut"
PLUGIN.description = "Saves the position of a character."

-- Called right before the character has its information save.
function PLUGIN:CharacterPreSave(character)
	-- Get the player from the character.
	local client = character:GetPlayer()

	-- Check to see if we can get the player's position.
	if (IsValid(client)) then
		local position, eyeAngles = client:GetPos(), client:EyeAngles()
		-- Use pre-observer position to prevent spawning in the air.
		if (client.wsObsData) then
			position, eyeAngles = client.wsObsData[1], client.wsObsData[2]
		end
		-- Store the position in the character's data.
		character:SetData("pos", {position, eyeAngles, game.GetMap()})
	end
end

-- Called after the player's loadout has been set.
function PLUGIN:PlayerLoadedCharacter(client, character, lastChar)
	timer.Simple(0, function()
		if (IsValid(client)) then
			-- Get the saved position from the character data.
			local position = character:GetData("pos")

			-- Check if the position was set.
			if (position) then
				if (position[3] and position[3]:lower() == game.GetMap():lower()) then
					-- Restore the player to that position. Validate types first so a
					-- malformed/legacy entry can't error on a nil/non-vector deref. (fw-plugins-world-9)
					if (isvector(position[1])) then
						client:SetPos(position[1])
					end

					if (isangle(position[2])) then
						client:SetEyeAngles(position[2])
					end
				end

				-- Remove the position data since it is no longer needed.
				character:SetData("pos", nil)
			end
		end
	end)
end
