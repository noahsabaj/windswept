
--[[--
Entity menu manipulation.

The `menu` library allows you to open up a context menu of arbitrary options whose callbacks will be ran when they are selected
from the panel that shows up for the player.
]]
-- @module ws.menu

--- You'll need to pass a table of options to `ws.menu.Open` to populate the menu. This table consists of strings as its keys
-- and functions as its values. These correspond to the text displayed in the menu and the callback to run, respectively.
--
-- Example usage:
-- 	ws.menu.Open({
-- 		Drink = function()
-- 			print("Drink option selected!")
-- 		end,
-- 		Take = function()
-- 			print("Take option selected!")
-- 		end
-- 	}, ents.GetByIndex(1))
-- This opens a menu with the options `"Drink"` and `"Take"` which will print a message when you click on either of the options.
-- @realm client
-- @table MenuOptionsStructure

ws.menu = ws.menu or {}

if (CLIENT) then
	--- Opens up a context menu for the given entity.
	-- @realm client
	-- @tparam MenuOptionsStructure options Data describing what options to display
	-- @entity[opt] entity Entity to send commands to
	-- @treturn boolean Whether or not the menu opened successfully. It will fail when there is already a menu open.
	function ws.menu.Open(options, entity)
		if (IsValid(ws.menu.panel)) then
			return false
		end

		local panel = vgui.Create("wsEntityMenu")
		panel:SetEntity(entity)
		panel:SetOptions(options)

		return true
	end

	--- Checks whether or not an entity menu is currently open.
	-- @realm client
	-- @treturn boolean Whether or not an entity menu is open
	function ws.menu.IsOpen()
		return IsValid(ws.menu.panel)
	end

	--- Notifies the server of an option that was chosen for the given entity.
	-- @realm client
	-- @entity entity Entity to call option on
	-- @string choice Option that was chosen
	-- @param data Extra data to send to the entity
	function ws.menu.NetworkChoice(entity, choice, data)
		if (IsValid(entity)) then
			ws.action.Send("wsEntityMenuSelect", nil, entity, function()
				net.WriteString(choice)
				net.WriteType(data)
			end)
		end
	end
else
	util.AddNetworkString("wsEntityMenuSelect")

	-- range = "none": this handler does NOT use a fixed framework distance gate;
	-- it delegates range (and all other interaction rules) to the overridable
	-- CanPlayerInteractEntity hook below, exactly as the inline handler did. The
	-- default hook impl enforces a 96u check, but per-entity overrides may widen it,
	-- so a built-in "close" check would change behavior. (preserves fw-derma-1 contract)
	ws.action.Register("wsEntityMenuSelect", {
		target = true,
		range = "none",
		read = function()
			return {option = net.ReadString(), data = net.ReadType()}
		end,
		run = function(client, ctx)
			local entity = ctx.target
			local option = ctx.data.option
			local data = ctx.data.data

			if (!isstring(option)
				or hook.Run("CanPlayerInteractEntity", client, entity, option, data) == false
			) then
				return
			end

			hook.Run("PlayerInteractEntity", client, entity, option, data)

			local callbackName = "OnSelect" .. option:gsub("%s", "")

			if (entity[callbackName]) then
				entity[callbackName](entity, client, data)
			else
				entity:OnOptionSelected(client, option, data)
			end
		end
	})
end

do
	local PLAYER = FindMetaTable("Player")

	if (CLIENT) then
		function PLAYER:GetEntityMenu()
			local options = {}

			hook.Run("GetPlayerEntityMenu", self, options)
			return options
		end
	else
		function PLAYER:OnOptionSelected(client, option)
			hook.Run("OnPlayerOptionSelected", self, client, option)
		end
	end
end

