--[[
    Radio — physical radio voice system (framework plugin)

    Windswept's radio is physical: handheld and stationary radios transmit/receive on
    frequencies, voice carries by amplitude-scaled proximity, and anyone near a tuned-in
    receiver can eavesdrop. This plugin provides the generic voice ENGINE (frequency
    transmit/receive, amplitude proximity, eavesdropping, battery drain) and the
    frequency utilities; a schema supplies the radio CONTENT (the handheld/stationary
    items + their UI) and wires it in through the seams in libs/sh_radio.lua:
      ws.radio.itemID          -- the handheld radio item uniqueID
      ws.radio.stationaryClass -- the stationary radio entity class
      ws.radio.eavesdropBase   -- base eavesdrop range (tuning)

    Off by default: while radioEnabled is false (or no item is registered),
    PLUGIN:PlayerCanHearPlayersVoice returns nil and the framework's default proximity
    voice (GM:PlayerCanHearPlayersVoice) applies, so the framework and a zero-plugin
    skeleton keep vanilla voice. The knocked/gagged voice blocks from the permadeath and
    restraints plugins still take precedence (the engine defers to them).
]]--

local PLUGIN = PLUGIN

PLUGIN.name = "Radio"
PLUGIN.author = "Windswept"
PLUGIN.description = "Physical radio voice: frequency transmit/receive, amplitude proximity, eavesdropping."

ws.radio = ws.radio or {}

ws.config.Add("radioEnabled", false, "Enables the physical radio voice system (frequencies, eavesdropping).")
