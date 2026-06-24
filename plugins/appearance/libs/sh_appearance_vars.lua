--[[
    The character appearance variables (ws.char.RegisterVar): age, height, weight,
    skin tone, hair, eyes, facial hair, birth date/location, and the description.

    Part of the framework appearance plugin (extracted from the Colony schema). The
    char-vars register unconditionally -- every Windswept character has a physical
    appearance; a schema fills the model/option content (ws.appearance.* tables).
]]--

ws.appearance = ws.appearance or {}

-- ============================================================================
-- CHARACTER VARIABLE REGISTRATION
-- ============================================================================

-- Age (18-128)
ws.char.RegisterVar("physAge", {
    field = "phys_age",
    fieldType = ws.type.number,
    default = 25,
    index = 10,
    category = "description",
    OnValidate = function(self, value, payload, client)
        value = tonumber(value)
        if not value or value < 18 or value > 128 then
            return false, "invalidAge"
        end
        return math.floor(value)
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalSlider")
        panel:Dock(TOP)
        panel:SetMin(18)
        panel:SetMax(128)
        panel:SetValue(payload.physAge or 25)
        panel:SetDecimals(0)
        panel:SetDisplayMode("age")
        panel.OnValueChanged = function(this)
            payload:Set("physAge", math.floor(this:GetValue()))
        end
        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physAge", math.floor(panel:GetValue()))
    end
})

-- Height (147-198 cm)
ws.char.RegisterVar("physHeight", {
    field = "phys_height",
    fieldType = ws.type.number,
    default = 170,
    index = 11,
    category = "description",
    OnValidate = function(self, value, payload, client)
        value = tonumber(value)
        if not value or value < 147 or value > 198 then
            return false, "invalidHeight"
        end
        return math.floor(value)
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalSlider")
        panel:Dock(TOP)
        panel:SetMin(147)
        panel:SetMax(198)
        panel:SetValue(payload.physHeight or 170)
        panel:SetDecimals(0)
        panel:SetDisplayMode("height")
        panel.OnValueChanged = function(this)
            payload:Set("physHeight", math.floor(this:GetValue()))
        end
        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physHeight", math.floor(panel:GetValue()))
    end
})

-- Weight (90-350 lbs)
ws.char.RegisterVar("physWeight", {
    field = "phys_weight",
    fieldType = ws.type.number,
    default = 160,
    index = 12,
    category = "description",
    OnValidate = function(self, value, payload, client)
        value = tonumber(value)
        if not value or value < 90 or value > 350 then
            return false, "invalidWeight"
        end
        return math.floor(value)
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalSlider")
        panel:Dock(TOP)
        panel:SetMin(90)
        panel:SetMax(350)
        panel:SetValue(payload.physWeight or 160)
        panel:SetDecimals(0)
        panel:SetDisplayMode("weight")
        panel.OnValueChanged = function(this)
            payload:Set("physWeight", math.floor(this:GetValue()))
        end
        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physWeight", math.floor(panel:GetValue()))
    end
})

-- Skin Tone (model-dependent)
ws.char.RegisterVar("physSkinTone", {
    field = "phys_skin_tone",
    fieldType = ws.type.string,
    default = "Medium",
    index = 13,
    category = "description",
    OnValidate = function(self, value, payload, client)
        -- Skin tones are model-dependent and can be empty for a model with no skin-tone content,
        -- so coerce a missing value to the default instead of blocking creation (cf. physBirthDay).
        if not value or value == "" then
            return "Medium"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)

        -- Get initial options based on current model
        local modelPath = ws.appearance.GetModelPath(payload.model or 1)
        local options = ws.appearance.GetSkinTonesForModel(modelPath)
        panel:SetOptions(options)

        panel.OnValueChanged = function(this)
            payload:Set("physSkinTone", this:GetValue())
        end

        -- Update options when model changes
        payload:AddHook("model", function(modelIndex)
            if not IsValid(panel) then return end
            local newModelPath = ws.appearance.GetModelPath(modelIndex)
            local newOptions = ws.appearance.GetSkinTonesForModel(newModelPath)
            panel:SetOptions(newOptions)
            payload:Set("physSkinTone", panel:GetValue())
        end)

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physSkinTone", panel:GetValue())
    end
})

-- Hair Color
ws.char.RegisterVar("physHairColor", {
    field = "phys_hair_color",
    fieldType = ws.type.string,
    default = "Brown",
    index = 14,
    category = "description",
    OnValidate = function(self, value, payload, client)
        -- Allow any value if bald (will be ignored in description)
        if payload.physHairLength == "Bald" then
            return value or "Brown"
        end
        -- Coerce a missing/invalid value to the default instead of rejecting, so an empty
        -- hairColors list (content-less boot) or a crafted payload can't block creation.
        if not value or not table.HasValue(ws.appearance.hairColors, value) then
            return "Brown"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)
        panel:SetOptions(ws.appearance.hairColors)
        panel:SetValue("Brown")

        panel.OnValueChanged = function(this)
            payload:Set("physHairColor", this:GetValue())
        end

        -- Hide when bald
        payload:AddHook("physHairLength", function(hairLength)
            if not IsValid(panel) then return end
            ws.charCreate.SetFieldVisible(panel, hairLength ~= "Bald")
        end)

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        -- Check if model is bald-locked
        local modelPath = ws.appearance.GetModelPath(payload.model or 1)
        if ws.appearance.IsBaldModel(modelPath) then
            ws.charCreate.SetFieldVisible(panel, false)
        end
        payload:Set("physHairColor", panel:GetValue())
    end
})

-- Hair Type
ws.char.RegisterVar("physHairType", {
    field = "phys_hair_type",
    fieldType = ws.type.string,
    default = "Straight",
    index = 15,
    category = "description",
    OnValidate = function(self, value, payload, client)
        -- Allow any value if bald (will be ignored in description)
        if payload.physHairLength == "Bald" then
            return value or "Straight"
        end
        -- Coerce a missing/invalid value to the default instead of rejecting (see physHairColor).
        if not value or not table.HasValue(ws.appearance.hairTypes, value) then
            return "Straight"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)
        panel:SetOptions(ws.appearance.hairTypes)
        panel:SetValue("Straight")

        panel.OnValueChanged = function(this)
            payload:Set("physHairType", this:GetValue())
        end

        -- Hide when bald
        payload:AddHook("physHairLength", function(hairLength)
            if not IsValid(panel) then return end
            ws.charCreate.SetFieldVisible(panel, hairLength ~= "Bald")
        end)

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        -- Check if model is bald-locked
        local modelPath = ws.appearance.GetModelPath(payload.model or 1)
        if ws.appearance.IsBaldModel(modelPath) then
            ws.charCreate.SetFieldVisible(panel, false)
        end
        payload:Set("physHairType", panel:GetValue())
    end
})

-- Hair Length
ws.char.RegisterVar("physHairLength", {
    field = "phys_hair_length",
    fieldType = ws.type.string,
    default = "Medium",
    index = 16,
    category = "description",
    OnValidate = function(self, value, payload, client)
        -- Coerce a missing/invalid value to the default instead of rejecting, so an empty
        -- hairLengths list can't block creation.
        if not value or not table.HasValue(ws.appearance.hairLengths, value) then
            return "Medium"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)
        panel:SetOptions(ws.appearance.hairLengths)
        panel:SetValue("Medium")

        panel.OnValueChanged = function(this)
            payload:Set("physHairLength", this:GetValue())
        end

        -- Lock to bald for bald models
        payload:AddHook("model", function(modelIndex)
            if not IsValid(panel) then return end
            local modelPath = ws.appearance.GetModelPath(modelIndex)
            if ws.appearance.IsBaldModel(modelPath) then
                panel:SetOptions({"Bald"})
                panel:SetEnabled(false)
                payload:Set("physHairLength", "Bald")
            else
                local currentValue = panel:GetValue()
                panel:SetOptions(ws.appearance.hairLengths)
                panel:SetEnabled(true)
                -- If was "Bald" (from bald model), default to "Medium", otherwise preserve
                if currentValue == "Bald" then
                    panel:SetValue("Medium")
                else
                    panel:SetValue(currentValue)
                end
            end
        end)

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        -- Check if model is bald-locked
        local modelPath = ws.appearance.GetModelPath(payload.model or 1)
        if ws.appearance.IsBaldModel(modelPath) then
            panel:SetOptions({"Bald"})
            panel:SetEnabled(false)
            payload:Set("physHairLength", "Bald")
        else
            payload:Set("physHairLength", panel:GetValue())
        end
    end
})

-- Eye Color
ws.char.RegisterVar("physEyeColor", {
    field = "phys_eye_color",
    fieldType = ws.type.string,
    default = "Brown",
    index = 17,
    category = "description",
    OnValidate = function(self, value, payload, client)
        if not value or not table.HasValue(ws.appearance.eyeColors, value) then
            return false, "invalidEyeColor"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)
        panel:SetOptions(ws.appearance.eyeColors)
        panel:SetValue("Brown")

        panel.OnValueChanged = function(this)
            payload:Set("physEyeColor", this:GetValue())
        end

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physEyeColor", panel:GetValue())
    end
})

-- Facial Hair
ws.char.RegisterVar("physFacialHair", {
    field = "phys_facial_hair",
    fieldType = ws.type.string,
    default = "None",
    index = 18,
    category = "description",
    OnValidate = function(self, value, payload, client)
        if not value or not table.HasValue(ws.appearance.facialHairOptions, value) then
            return false, "invalidFacialHair"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)
        panel:SetOptions(ws.appearance.facialHairOptions)
        panel:SetValue("None")

        panel.OnValueChanged = function(this)
            payload:Set("physFacialHair", this:GetValue())
        end

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physFacialHair", panel:GetValue())
    end
})

-- Birth Month (1-12)
ws.char.RegisterVar("physBirthMonth", {
    field = "phys_birth_month",
    fieldType = ws.type.number,
    default = 1,
    index = 19,
    category = "description",
    OnValidate = function(self, value, payload, client)
        value = tonumber(value)
        if not value or value < 1 or value > 12 then
            return false, "invalidBirthMonth"
        end
        return math.floor(value)
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsBirthDatePicker")
        panel:Dock(TOP)

        -- Store reference to update day validation when age changes
        payload:AddHook("physAge", function(age)
            if not IsValid(panel) then return end
            panel:SetAge(age)
        end)

        panel.OnValueChanged = function(this)
            payload:Set("physBirthMonth", this:GetMonth())
            payload:Set("physBirthDay", this:GetDay())
        end

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        panel:SetAge(payload.physAge or 25)
        payload:Set("physBirthMonth", panel:GetMonth())
        payload:Set("physBirthDay", panel:GetDay())
    end
})

-- Birth Day (1-31, handled by month's picker)
ws.char.RegisterVar("physBirthDay", {
    field = "phys_birth_day",
    fieldType = ws.type.number,
    default = 1,
    index = 20,
    category = "description",
    bNoDisplay = true, -- Handled by physBirthMonth's picker
    OnValidate = function(self, value, payload, client)
        -- Birth day is a value DERIVED from the month/age picker, not free user input, so clamp
        -- it into the valid range instead of rejecting. The untouched default (e.g. January 1)
        -- only flows through the picker's OnPostSetup, never its change handler, so a missing or
        -- out-of-range day must fall back to a valid day rather than block character creation.
        -- ws.birthdata.ValidateDay clamps to 1..GetMaxDay(month, age) (Feb 29 only in a leap year).
        local month = tonumber(payload.physBirthMonth) or 1
        local age = tonumber(payload.physAge) or 25
        return ws.birthdata.ValidateDay(month, value, age)
    end
})

-- Birth Location
ws.char.RegisterVar("physBirthLocation", {
    field = "phys_birth_location",
    fieldType = ws.type.string,
    default = "Unspecified",
    index = 21,
    category = "description",
    OnValidate = function(self, value, payload, client)
        if not value or not ws.birthdata.IsValidLocation(value) then
            return false, "invalidBirthLocation"
        end
        return value
    end,
    OnDisplay = function(self, container, payload)
        local panel = container:Add("wsPhysicalDropdown")
        panel:Dock(TOP)
        panel:SetOptions(ws.birthdata.locations)
        panel:SetValue("Unspecified")

        panel.OnValueChanged = function(this)
            payload:Set("physBirthLocation", this:GetValue())
        end

        return panel
    end,
    OnPostSetup = function(self, panel, payload)
        if not IsValid(panel) then return end
        payload:Set("physBirthLocation", panel:GetValue())
    end
})

-- Override the default description variable to be non-editable
-- The description will be generated server-side from physical attributes
ws.char.RegisterVar("description", {
    field = "description",
    fieldType = ws.type.text,
    default = "",
    index = 99, -- Put at end (we don't show it anyway)
    bNoDisplay = true, -- Hide from character creation UI
    OnValidate = function(self, value, payload, client)
        -- Description is generated server-side, accept any value here
        -- It will be overwritten in AdjustCreationPayload
        return value or ""
    end
})
