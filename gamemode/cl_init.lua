
-- unix systems are case-sensitive, are missing fonts, or use different naming conventions
if (!system.IsWindows()) then
	local fontOverrides = {
		["Roboto"] = "Roboto Regular",
		["Roboto Th"] = "Roboto Thin",
		["Roboto Lt"] = "Roboto Light",
		["Roboto Bk"] = "Roboto Black",
		["coolvetica"] = "Coolvetica",
		["tahoma"] = "Tahoma",
		["Harmonia Sans Pro Cyr"] = "Roboto Regular",
		["Harmonia Sans Pro Cyr Light"] = "Roboto Light",
		["Century Gothic"] = "Roboto Regular"
	}

	if (system.IsOSX()) then
		fontOverrides["Consolas"] = "Monaco"
	else
		fontOverrides["Consolas"] = "Courier New"
	end

	local wsCreateFont = surface.CreateFont

	function surface.CreateFont(name, info) -- luacheck: globals surface
		local font = info.font

		if (font and fontOverrides[font]) then
			info.font = fontOverrides[font]
		end

		wsCreateFont(name, info)
	end
end

DeriveGamemode("sandbox")
-- Windswept framework global table (`ws`); `ix` is a temporary transition alias.
ws = ws or {util = {}, gui = {}, meta = {}}
ix = ws

-- Include core files.
include("core/sh_util.lua")
include("core/sh_data.lua")
include("shared.lua")

-- Sandbox stuff
CreateConVar("cl_weaponcolor", "0.30 1.80 2.10", {
	FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD
}, "The value is a Vector - so between 0-1 - not between 0-255")

timer.Remove("HintSystem_OpeningMenu")
timer.Remove("HintSystem_Annoy1")
timer.Remove("HintSystem_Annoy2")
