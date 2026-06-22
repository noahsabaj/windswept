--[[
    Server-side character description generation from appearance data.

    Part of the framework appearance plugin (extracted from the Colony schema). The
    char-vars register unconditionally -- every Windswept character has a physical
    appearance; a schema fills the model/option content (ws.appearance.* tables).
]]--

ws.appearance = ws.appearance or {}

-- ============================================================================
-- DESCRIPTION GENERATION (SERVER ONLY)
-- ============================================================================
function ws.appearance.GenerateDescription(data)
    -- Determine article for build
    local buildArticle = (data.build == "average") and "An" or "A"

    -- Build hair description
    local hairDesc
    if data.hairLength == "Bald" then
        hairDesc = "a bald head"
    else
        hairDesc = string.lower(data.hairLength) .. ", " ..
                   string.lower(data.hairType) .. " " ..
                   string.lower(data.hairColor) .. " hair"
    end

    -- Build facial hair description
    local facialHairDesc = ""
    if data.facialHair and data.facialHair ~= "None" then
        if data.facialHair == "Stubble" then
            facialHairDesc = " with stubble on their face"
        else
            facialHairDesc = " with a " .. string.lower(data.facialHair)
        end
    end

    -- Convert height to imperial for description
    local feet, inches = ws.appearance.CmToImperial(data.height)
    local heightStr = string.format("%d'%d\"", feet, inches)

    -- Get age descriptor
    local ageDesc = ws.appearance.GetAgeDescriptor(data.age)

    -- Determine article for skin tone
    local skinArticle = string.sub(data.skinTone, 1, 1):match("[AEIOUaeiou]") and "an" or "a"

    -- Generate the description (gender-neutral)
    local description = string.format(
        "%s %s-built person with %s and %s eyes. They have %s %s complexion%s. They stand around %s and appear to be in their %s.",
        buildArticle,
        data.build,
        hairDesc,
        string.lower(data.eyeColor),
        skinArticle,
        string.lower(data.skinTone),
        facialHairDesc,
        heightStr,
        ageDesc
    )

    return description
end
