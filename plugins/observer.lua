
PLUGIN.name = "Observer"
PLUGIN.author = "Chessnut"
PLUGIN.description = "Adds on to the no-clip mode to prevent intrusion."

CAMI.RegisterPrivilege({
	Name = "Windswept - Observer",
	MinAccess = "admin"
})

ws.option.Add("observerTeleportBack", ws.type.bool, true, {
	bNetworked = true,
	category = "observer",
	hidden = function()
		return !CAMI.PlayerHasAccess(LocalPlayer(), "Windswept - Observer", nil)
	end
})

if (CLIENT) then
	ws.option.Add("observerESP", ws.type.bool, true, {
		category = "observer",
		hidden = function()
			return !CAMI.PlayerHasAccess(LocalPlayer(), "Windswept - Observer", nil)
		end
	})

	local dimDistance = 1024
	local aimLength = 128
	local barHeight = 2

	function PLUGIN:HUDPaint()
		local client = LocalPlayer()

		if (ws.option.Get("observerESP", true) and client:GetMoveType() == MOVETYPE_NOCLIP and
			!client:InVehicle() and CAMI.PlayerHasAccess(client, "Windswept - Observer", nil)) then
			local scrW, scrH = ScrW(), ScrH()

			for _, v in player.Iterator() do
				if (v == client or !v:GetCharacter() or client:GetAimVector():Dot((v:GetPos() - client:GetPos()):GetNormal()) < 0.65) then
					continue
				end

				local screenPosition = v:GetPos():ToScreen()
				local aimPosition = (v:GetPos() + v:GetAimVector() * aimLength):ToScreen()

				local marginX, marginY = scrH * .1, scrH * .1
				local x, y = math.Clamp(screenPosition.x, marginX, scrW - marginX), math.Clamp(screenPosition.y, marginY, scrH - marginY)
				local aimX, aimY = math.Clamp(aimPosition.x, marginX, scrW - marginX), math.Clamp(aimPosition.y, marginY, scrH - marginY)

				local teamColor = team.GetColor(v:Team())
				local distance = client:GetPos():Distance(v:GetPos())
				local factor = 1 - math.Clamp(distance / dimDistance, 0, 1)
				local size = math.max(10, 32 * factor)
				local alpha = math.max(255 * factor, 80)
				local aimAlpha = (1 - factor * 1.5) * 80

				surface.SetDrawColor(teamColor.r, teamColor.g, teamColor.b, alpha)
				surface.SetFont("wsGenericFont")

				local text = v:Name()
				local textWidth, textHeight = surface.GetTextSize(text)
				local barWidth = math.Clamp((v:Health() / v:GetMaxHealth()) * textWidth, 0, textWidth)

				surface.DrawRect(x - size / 2, y - size / 2, size, size)

				-- we can assume that if we're using cheap blur, we'd want to save some fps here
				if (!ws.option.Get("cheapBlur", false)) then
					local data = {}
					data.start = client:EyePos()
					data.endpos = v:EyePos()
					data.filter = {client, v}

					if (util.TraceLine(data).Hit) then
						aimAlpha = alpha
					else
						aimAlpha = (1 - factor * 4) * 80
					end
				end

				if (aimPosition.visible) then
					surface.SetDrawColor(teamColor.r * 1.2, teamColor.g * 1.2, teamColor.b * 1.2, aimAlpha)
					surface.DrawLine(x, y, aimX, aimY)
					surface.DrawLine(x, y + 1, aimX, aimY + 1)
				end

				surface.SetDrawColor(teamColor.r * 1.6, teamColor.g * 1.6, teamColor.b * 1.6, alpha)
				surface.DrawRect(x - barWidth / 2, y - size - textHeight / 2, barWidth, barHeight)

				ws.util.DrawText(text, x, y - size, ColorAlpha(teamColor, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, nil, alpha)
			end
		end
	end

	function PLUGIN:ShouldPopulateEntityInfo(entity)
		if (IsValid(entity)) then
			if ((entity:IsPlayer() or IsValid(entity:GetNetVar("player"))) and entity:GetMoveType() == MOVETYPE_NOCLIP) then
				return false
			end
		end
	end

	function PLUGIN:DrawPhysgunBeam(client, physgun, enabled, target, bone, hitPos)
		if (client != LocalPlayer() and client:GetMoveType() == MOVETYPE_NOCLIP) then
			return false
		end
	end

	function PLUGIN:PrePlayerDraw(client)
		if (client:GetMoveType() == MOVETYPE_NOCLIP and !client:InVehicle()) then
			return true
		end
	end
else
	ws.log.AddType("observerEnter", function(client, ...)
		return string.format("%s entered observer.", client:Name())
	end)

	ws.log.AddType("observerExit", function(client, ...)
		if (ws.option.Get(client, "observerTeleportBack", true)) then
			return string.format("%s exited observer.", client:Name())
		else
			return string.format("%s exited observer at their location.", client:Name())
		end
	end)

	function PLUGIN:CanPlayerEnterObserver(client)
		if (CAMI.PlayerHasAccess(client, "Windswept - Observer", nil)) then
			return true
		end
	end

	function PLUGIN:CanPlayerEnterVehicle(client, vehicle, role)
		if (client:GetMoveType() == MOVETYPE_NOCLIP) then
			return false
		end
	end

	function PLUGIN:PlayerNoClip(client, state)
		if (state) then
			-- Only the *enter* branch is gated on current observer access. (fw-plugins-world-10)
			if (!hook.Run("CanPlayerEnterObserver", client)) then
				return
			end

			client.wsObsData = {client:GetPos(), client:EyeAngles()}

			-- Hide them so they are not visible.
			client:SetNoDraw(true)
			client:SetNotSolid(true)
			client:DrawWorldModel(false)
			client:DrawShadow(false)
			client:GodEnable()
			client:SetNoTarget(true)

			hook.Run("OnPlayerObserve", client, state)

			return true
		end

		-- Always run exit/cleanup when leaving noclip with stored observer data,
		-- regardless of current observer access (it may have been revoked while
		-- they were observing). (fw-plugins-world-10)
		if (!client.wsObsData) then
			return
		end

		-- Move they player back if they want.
		if (ws.option.Get(client, "observerTeleportBack", true)) then
			local position, angles = client.wsObsData[1], client.wsObsData[2]

			-- Do it the next frame since the player can not be moved right now.
			timer.Simple(0, function()
				if (!IsValid(client)) then return end -- may disconnect within the frame (fw-low-observer)
				client:SetPos(position)
				client:SetEyeAngles(angles)
				client:SetVelocity(Vector(0, 0, 0))
			end)
		end

		client.wsObsData = nil

		-- Make the player visible again.
		client:SetNoDraw(false)
		client:SetNotSolid(false)
		client:DrawWorldModel(true)
		client:DrawShadow(true)
		client:GodDisable()
		client:SetNoTarget(false)

		hook.Run("OnPlayerObserve", client, state)

		return true
	end

	function PLUGIN:OnPlayerObserve(client, state)
		if (state) then
			ws.log.Add(client, "observerEnter")
		else
			ws.log.Add(client, "observerExit")
		end
	end
end
