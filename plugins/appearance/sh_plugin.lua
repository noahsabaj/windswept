--[[
    Appearance — physical character appearance (framework plugin)

    Every Windswept character has a physical body, so this is fundamental, not opt-in: it
    registers the appearance character variables unconditionally (age, height, weight, skin
    tone, hair, eyes, facial hair, birth date/place) and generates an objective, auto-written
    description from them. It also ships base_clothing -- the outfit equip / material-
    application base that outfit items derive (it in turn derives the core base_outfit).

    Generic engine: the model->skin-tone map, the hair/eye/build option lists, and the
    concrete outfit items are CONTENT the schema supplies -- it fills the ws.appearance.*
    tables (see the Colony schema's libs/sh_appearance_config.lua) and ships the outfit
    items under items/clothing/. A schema with no appearance content still boots to
    character creation; the dropdowns are simply empty (the tables default to {}).
]]--

local PLUGIN = PLUGIN

PLUGIN.name = "Appearance"
PLUGIN.author = "Windswept"
PLUGIN.description = "Physical character appearance: age/height/build/skin/hair/eyes + auto-description, and the clothing base."

ws.appearance = ws.appearance or {}
