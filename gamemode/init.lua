
-- Include features from the Sandbox gamemode.
DeriveGamemode("sandbox")
-- Define the global shared table.
ws = ws or {util = {}, meta = {}}

-- Send the following files to players.
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("core/sh_util.lua")
AddCSLuaFile("core/sh_data.lua")
AddCSLuaFile("shared.lua")

-- Include utility functions, data storage functions, and then shared.lua
include("core/sh_util.lua")
include("core/sh_data.lua")
include("shared.lua")

-- Resources required for players to download. These ship loose in this gamemode's
-- content/ folder (de-helixed: paths renamed helix/ -> windswept/; the Helix workshop
-- content pack is no longer a dependency — the assets are bundled with the framework).
resource.AddFile("materials/windswept/gui/vignette.png")
resource.AddFile("materials/windswept/gui/radial-gradient.png")
resource.AddFile("resource/fonts/fontello.ttf")
resource.AddFile("sound/windswept/intro.mp3")
resource.AddFile("sound/windswept/ui/press.wav")
resource.AddFile("sound/windswept/ui/rollover.wav")
resource.AddFile("sound/windswept/ui/whoosh1.wav")
resource.AddFile("sound/windswept/ui/whoosh2.wav")
resource.AddFile("sound/windswept/ui/whoosh3.wav")
resource.AddFile("sound/windswept/ui/whoosh4.wav")
resource.AddFile("sound/windswept/ui/whoosh5.wav")
resource.AddFile("sound/windswept/ui/whoosh6.wav")

cvars.AddChangeCallback("sbox_persist", function(name, old, new)
	-- A timer in case someone tries to rapily change the convar, such as addons with "live typing" or whatever
	timer.Create("sbox_persist_change_timer", 1, 1, function()
		hook.Run("PersistenceSave", old)

		if (new == "") then
			return
		end

		hook.Run("PersistenceLoad", new)
	end)
end, "sbox_persist_load")
