
if (CLIENT) then
	ws.option.Add("animationScale", ws.type.number, 1, {
		category = "appearance", min = 0.3, max = 2, decimals = 1
	})

	ws.option.Add("24hourTime", ws.type.bool, false, {
		category = "appearance"
	})

	ws.option.Add("altLower", ws.type.bool, true, {
		category = "general"
	})

	ws.option.Add("alwaysShowBars", ws.type.bool, false, {
		category = "appearance"
	})

	ws.option.Add("minimalTooltips", ws.type.bool, false, {
		category = "appearance"
	})

	ws.option.Add("noticeDuration", ws.type.number, 8, {
		category = "appearance", min = 0.1, max = 20, decimals = 1
	})

	ws.option.Add("noticeMax", ws.type.number, 4, {
		category = "appearance", min = 1, max = 20
	})

	ws.option.Add("cheapBlur", ws.type.bool, false, {
		category = "performance"
	})

	ws.option.Add("disableAnimations", ws.type.bool, false, {
		category = "performance"
	})

	ws.option.Add("openBags", ws.type.bool, true, {
		category = "general"
	})

	ws.option.Add("showIntro", ws.type.bool, true, {
		category = "general"
	})

	ws.option.Add("escCloseMenu", ws.type.bool, false, {
		category = "general"
	})
end

ws.option.Add("language", ws.type.array, ws.config.language or "english", {
	category = "general",
	bNetworked = true,
	populate = function()
		local entries = {}

		for k, _ in SortedPairs(ws.lang.stored) do
			local name = ws.lang.names[k]
			local name2 = k:utf8sub(1, 1):utf8upper() .. k:utf8sub(2)

			if (name) then
				name = name .. " (" .. name2 .. ")"
			else
				name = name2
			end

			entries[k] = name
		end

		return entries
	end
})
