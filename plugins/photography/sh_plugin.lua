local PLUGIN = PLUGIN

PLUGIN.name = "Photography"
PLUGIN.author = "Windswept"
PLUGIN.description = "A comprehensive photography system featuring working cameras, film, photos, and albums."

ws.photo = ws.photo or {}

-- Anti-spam / disk caps (0 = unlimited). Enforced in ProcessCompletePhoto.
ws.config.Add("maxPhotosPerChar", 100, "Maximum photographs a single character may hold (0 = unlimited).", nil, {
    data = {min = 0, max = 1000},
    category = "Photography"
})

ws.config.Add("maxPhotoDiskMB", 512, "Maximum total disk space (MB) for stored photos before new captures are blocked (0 = unlimited).", nil, {
    data = {min = 0, max = 10000},
    category = "Photography"
})

ws.util.Include("libs/sh_photo.lua")
ws.util.Include("sv_plugin.lua")
