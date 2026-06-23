
-- You can change the default language by setting this in your schema.
ws.config.language = "english"

--[[
	DO NOT CHANGE ANYTHING BELOW THIS.

	This is the Windswept main configuration file.
	This file DOES NOT set any configurations, instead it just prepares them.
	To set the configuration, there is a "Config" tab in the F1 menu for super admins and above.
	Use the menu to change the variables, not this file.
--]]

ws.config.Add("maxCharacters", 1, "The maximum number of characters a player can have.", nil, {
	data = {min = 1, max = 50},
	category = "characters"
})
ws.config.Add("font", "Roboto Th", "The font used to display titles.", function(oldValue, newValue)
	if (CLIENT) then
		hook.Run("LoadFonts", newValue, ws.config.Get("genericFont"))
	end
end, {category = "appearance"})

ws.config.Add("color", Color(75, 119, 190, 255), "The main color theme for the framework.", function(oldValue, newValue)
	if (newValue.a != 255) then
		ws.config.Set("color", ColorAlpha(newValue, 255))
		return
	end

	if (CLIENT) then
		hook.Run("ColorSchemeChanged", newValue)
	end
end, {category = "appearance"})

ws.config.Add("genericFont", "Roboto", "The font used to display generic texts.", function(oldValue, newValue)
	if (CLIENT) then
		hook.Run("LoadFonts", ws.config.Get("font"), newValue)
	end
end, {category = "appearance"})

ws.config.Add("maxAttributes", 100, "The maximum amount each attribute can be.", nil, {
	data = {min = 0, max = 100},
	category = "characters"
})
ws.config.Add("chatAutoFormat", true, "Whether or not to automatically capitalize and punctuate in-character text.", nil, {
	category = "Chat"
})
ws.config.Add("chatRange", 280, "The maximum distance a person's IC chat message goes to.", nil, {
	data = {min = 10, max = 5000, decimals = 1},
	category = "chat"
})
ws.config.Add("chatMax", 256, "The maximum amount of characters that can be sent in chat.", nil, {
	data = {min = 32, max = 1024},
	category = "chat"
})
ws.config.Add("chatColor", Color(255, 255, 150), "The default color for IC chat.", nil, {category = "chat"})
ws.config.Add("chatListenColor", Color(175, 255, 150), "The color for IC chat if you are looking at the speaker.", nil, {
	category = "chat"
})
ws.config.Add("oocDelay", 10, "The delay before a player can use OOC chat again in seconds.", nil, {
	data = {min = 0, max = 10000},
	category = "chat"
})
ws.config.Add("allowGlobalOOC", true, "Whether or not Global OOC is enabled.", nil, {
	category = "chat"
})
ws.config.Add("loocDelay", 0, "The delay before a player can use LOOC chat again in seconds.", nil, {
	data = {min = 0, max = 10000},
	category = "chat"
})
ws.config.Add("spawnTime", 5, "The time it takes to respawn.", nil, {
	data = {min = 0, max = 10000},
	category = "characters"
})
ws.config.Add("inventoryWidth", 6, "How many slots in a row there is in a default inventory.", nil, {
	data = {min = 0, max = 20},
	category = "characters"
})
ws.config.Add("inventoryHeight", 6, "How many slots in a column there is in a default inventory.", nil, {
	data = {min = 0, max = 20},
	category = "characters"
})
ws.config.Add("minNameLength", 1, "The minimum number of characters in a name.", nil, {
	data = {min = 1, max = 64},
	category = "characters"
})
ws.config.Add("maxNameLength", 32, "The maximum number of characters in a name.", nil, {
	data = {min = 16, max = 128},
	category = "characters"
})
ws.config.Add("minDescriptionLength", 0, "The minimum number of characters in a description.", nil, {
	data = {min = 0, max = 300},
	category = "characters"
})
ws.config.Add("defaultModels", {
	"models/humans/group01/male_01.mdl",
	"models/humans/group01/male_02.mdl",
	"models/humans/group01/male_03.mdl",
	"models/humans/group01/male_04.mdl",
	"models/humans/group01/male_05.mdl",
	"models/humans/group01/male_06.mdl",
	"models/humans/group01/male_07.mdl",
	"models/humans/group01/male_08.mdl",
	"models/humans/group01/male_09.mdl",
	"models/humans/group01/female_01.mdl",
	"models/humans/group01/female_02.mdl",
	"models/humans/group01/female_03.mdl",
	"models/humans/group01/female_04.mdl",
	"models/humans/group01/female_06.mdl",
	"models/humans/group01/female_07.mdl"
}, "The models available to characters during character creation.", nil, {
	category = "characters",
	type = ws.type.array,
	hidden = function() return true end
})
ws.config.Add("saveInterval", 300, "How often characters save in seconds.", nil, {
	data = {min = 60, max = 3600},
	category = "characters"
})
ws.config.Add("walkSpeed", 130, "How fast a player normally walks.", function(oldValue, newValue)
	for _, v in player.Iterator()	do
		v:SetWalkSpeed(newValue)
	end
end, {
	data = {min = 75, max = 500},
	category = "characters"
})
ws.config.Add("runSpeed", 235, "How fast a player normally runs.", function(oldValue, newValue)
	for _, v in player.Iterator()	do
		v:SetRunSpeed(newValue)
	end
end, {
	data = {min = 75, max = 500},
	category = "characters"
})
ws.config.Add("walkRatio", 0.5, "How fast one goes when holding ALT.", nil, {
	data = {min = 0, max = 1, decimals = 1},
	category = "characters"
})
ws.config.Add("intro", false, "Whether or not the Windswept intro is enabled for new players.", nil, {
	category = "appearance"
})
ws.config.Add("music", "music/hl2_song2.mp3", "The default music played in the character menu.", nil, {
	category = "appearance"
})
ws.config.Add("communityURL", "https://nebulous.cloud/", "The URL to navigate to when the community button is clicked.", nil, {
	category = "appearance"
})
ws.config.Add("communityText", "@community",
	"The text to display on the community button. You can use language phrases by prefixing with @", nil, {
	category = "appearance"
})
ws.config.Add("vignette", true, "Whether or not the vignette is shown.", nil, {
	category = "appearance"
})
ws.config.Add("scoreboardRecognition", false, "Whether or not recognition is used in the scoreboard.", nil, {
	category = "characters"
})
ws.config.Add("defaultMoney", 0, "The amount of money that players start with.", nil, {
	category = "characters",
	data = {min = 0, max = 1000}
})
ws.config.Add("minMoneyDropAmount", 1, "The minimum amount of money that can be dropped.", nil, {
	category = "characters",
	data = {min = 1, max = 1000}
})
ws.config.Add("allowVoice", true, "Whether or not voice chat is allowed.", function(oldValue, newValue)
	if (SERVER) then
		hook.Run("VoiceToggled", newValue)
	end
end, {
	category = "server"
})
ws.config.Add("voiceDistance", 600.0, "How far can the voice be heard.", function(oldValue, newValue)
	if (SERVER) then
		hook.Run("VoiceDistanceChanged", newValue)
	end
end, {
	category = "server",
	data = {min = 0, max = 5000, decimals = 1}
})
ws.config.Add("weaponAlwaysRaised", false, "Whether or not weapons are always raised.", nil, {
	category = "server"
})
ws.config.Add("weaponRaiseTime", 0.3, "The time it takes for a weapon to raise.", nil, {
	data = {min = 0.1, max = 60, decimals = 1},
	category = "server"
})
ws.config.Add("allowBusiness", true, "Whether or not business is enabled.", nil, {
	category = "server"
})
ws.config.Add("maxHoldWeight", 100, "The maximum weight that a player can carry in their hands.", nil, {
	data = {min = 1, max = 500},
	category = "interaction"
})
ws.config.Add("throwForce", 732, "How hard a player can throw the item that they're holding.", nil, {
	data = {min = 0, max = 8192},
	category = "interaction"
})
ws.config.Add("allowPush", true, "Whether or not pushing with hands is allowed.", nil, {
	category = "interaction"
})
ws.config.Add("itemPickupTime", 1, "How long it takes to pick up and put an item in your inventory.", nil, {
	data = {min = 0, max = 5, decimals = 1},
	category = "interaction"
})
ws.config.Add("year", 2200,
	"The current in-game year. Auto-syncs from real year + offset on server start.",
	function(oldValue, newValue)
	if (SERVER and !ws.date.bSaving) then
		ws.date.ResolveOffset()
		ws.date.current:setyear(newValue)
		ws.date.Send()
	end
end, {
	data = {min = 1, max = 9999},
	category = "date"
})
ws.config.Add("month", 1, "The current in-game month. Auto-syncs from real month on server start.", function(oldValue, newValue)
	if (SERVER and !ws.date.bSaving) then
		ws.date.ResolveOffset()
		ws.date.current:setmonth(newValue)
		ws.date.Send()
	end
end, {
	data = {min = 1, max = 12},
	category = "date"
})
ws.config.Add("day", 1, "The current in-game day. Auto-syncs from real day on server start.", function(oldValue, newValue)
	if (SERVER and !ws.date.bSaving) then
		ws.date.ResolveOffset()
		ws.date.current:setday(newValue)
		ws.date.Send()
	end
end, {
	data = {min = 1, max = 31},
	category = "date"
})
ws.config.Add("secondsPerMinute", 60, "How many seconds it takes for a minute to pass in-game.", function(oldValue, newValue)
	if (SERVER and !ws.date.bSaving) then
		ws.date.UpdateTimescale(newValue)
		ws.date.Send()
	end
end, {
	data = {min = 0.01, max = 120},
	category = "date"
})