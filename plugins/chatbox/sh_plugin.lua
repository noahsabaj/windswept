
local PLUGIN = PLUGIN

PLUGIN.name = "Chatbox"
PLUGIN.author = "`impulse"
PLUGIN.description = "Replaces the chatbox to enable customization, autocomplete, and useful info."

if (CLIENT) then
	ws.chat.history = ws.chat.history or {} -- array of strings the player has entered into the chatbox
	ws.chat.currentCommand = ""
	ws.chat.currentArguments = {}

	ws.option.Add("chatNotices", ws.type.bool, false, {
		category = "chat"
	})

	ws.option.Add("chatTimestamps", ws.type.bool, false, {
		category = "chat"
	})

	ws.option.Add("chatFontScale", ws.type.number, 1, {
		category = "chat", min = 0.1, max = 2, decimals = 2,
		OnChanged = function()
			hook.Run("LoadFonts", ws.config.Get("font"), ws.config.Get("genericFont"))
			PLUGIN:CreateChat()
		end
	})

	ws.option.Add("chatOutline", ws.type.bool, false, {
		category = "chat"
	})

	-- tabs and their respective filters
	ws.option.Add("chatTabs", ws.type.string, "", {
		category = "chat",
		hidden = function()
			return true
		end
	})

	-- chatbox size and position
	ws.option.Add("chatPosition", ws.type.string, "", {
		category = "chat",
		hidden = function()
			return true
		end
	})

	function PLUGIN:CreateChat()
		if (IsValid(self.panel)) then
			self.panel:Remove()
		end

		self.panel = vgui.Create("wsChatbox")
		self.panel:SetupTabs(util.JSONToTable(ws.option.Get("chatTabs", "")))
		self.panel:SetupPosition(util.JSONToTable(ws.option.Get("chatPosition", "")))

		hook.Run("ChatboxCreated")
	end

	function PLUGIN:TabExists(id)
		if (!IsValid(self.panel)) then
			return false
		end

		return self.panel.tabs:GetTabs()[id] != nil
	end

	function PLUGIN:SaveTabs()
		local tabs = {}

		for id, panel in pairs(self.panel.tabs:GetTabs()) do
			tabs[id] = panel:GetFilter()
		end

		ws.option.Set("chatTabs", util.TableToJSON(tabs))
	end

	function PLUGIN:SavePosition()
		local x, y = self.panel:GetPos()
		local width, height = self.panel:GetSize()

		ws.option.Set("chatPosition", util.TableToJSON({x, y, width, height}))
	end

	function PLUGIN:InitPostEntity()
		self:CreateChat()
	end

	function PLUGIN:PlayerBindPress(client, bind, pressed)
		bind = bind:lower()

		if (bind:find("messagemode") and pressed) then
			self.panel:SetActive(true)

			return true
		end
	end

	function PLUGIN:OnPauseMenuShow()
		if (!IsValid(ws.gui.chat) or !ws.gui.chat:GetActive()) then
			return
		end

		ws.gui.chat:SetActive(false)

		return false
	end

	function PLUGIN:HUDShouldDraw(element)
		if (element == "CHudChat") then
			return false
		end
	end

	function PLUGIN:ScreenResolutionChanged(oldWidth, oldHeight)
		self:CreateChat()
	end

	function PLUGIN:ChatText(index, name, text, messageType)
		if (messageType == "none" and IsValid(self.panel)) then
			self.panel:AddMessage(text)
		end
	end

	-- luacheck: globals chat
	chat.wsAddText = chat.wsAddText or chat.AddText

	function chat.AddText(...)
		if (IsValid(PLUGIN.panel)) then
			PLUGIN.panel:AddMessage(...)
		end

		-- log chat message to console
		local text = {}

		for _, v in ipairs({...}) do
			if (istable(v) or isstring(v)) then
				text[#text + 1] = v
			elseif (isentity(v) and v:IsPlayer()) then
				text[#text + 1] = team.GetColor(v:Team())
				-- Steam name, never the character name: a Player entity reaching
				-- chat rendering must not leak IC identity (fog of war). (#53)
				text[#text + 1] = v:SteamName()
			elseif (type(v) != "IMaterial") then
				text[#text + 1] = tostring(v)
			end
		end

		text[#text + 1] = "\n"
		MsgC(unpack(text))
	end
else
	util.AddNetworkString("wsChatMessage")

	-- client->server chat submission. Single-string payload, no item/target/money.
	-- The inline wsNextChat cooldown (0.5s, only charged on ACCEPTED messages) becomes
	-- def.rateLimit, which ws.action charges only after onValidate passes -- so an empty
	-- message still doesn't burn the cooldown, matching the original. The whitespace/string
	-- gate moves to onValidate so a blank submission is rejected before the cooldown is set.
	-- NOTE: "wsChatMessage" is also used server->client in sh_chatbox.lua (server net.Start +
	-- client net.Receive); that is a different realm/direction sharing the net name and is
	-- unaffected -- ws.action only registers the SERVER-realm receive that lived here.
	ws.action.Register("wsChatMessage", {
		rateLimit = 0.5,
		read = function() return net.ReadString() end,
		onValidate = function(client, ctx)
			local text = ctx.data
			if (not isstring(text) or not text:find("%S")) then
				return false
			end
		end,
		run = function(client, ctx)
			local text = ctx.data
			local maxLength = ws.config.Get("chatMax")

			if (text:utf8len() > maxLength) then
				text = text:utf8sub(0, maxLength)
			end

			hook.Run("PlayerSay", client, text)
		end
	})
end
