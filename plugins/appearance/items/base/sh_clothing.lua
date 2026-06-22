ITEM.name = "Clothing"
ITEM.description = "A piece of clothing."
ITEM.category = "Clothing"
ITEM.model = "models/props_junk/cardboard_box004a.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.outfitCategory = "clothing"
ITEM.base = "base_outfit"

-- The submaterial path this clothing applies (override in child items)
ITEM.clothingMaterial = nil

-- Mapping of model paths to their clothing submaterial index
ITEM.clothingIndices = {
    -- Group 01 Males
    ["models/humans/group01/male_01.mdl"] = 3,
    ["models/humans/group01/male_02.mdl"] = 2,
    ["models/humans/group01/male_03.mdl"] = 4,
    ["models/humans/group01/male_04.mdl"] = 4,
    ["models/humans/group01/male_05.mdl"] = 4,
    ["models/humans/group01/male_06.mdl"] = 4,
    ["models/humans/group01/male_07.mdl"] = 4,
    ["models/humans/group01/male_08.mdl"] = 0,
    ["models/humans/group01/male_09.mdl"] = 2,
    -- Group 01 Females
    ["models/humans/group01/female_01.mdl"] = 2,
    ["models/humans/group01/female_02.mdl"] = 3,
    ["models/humans/group01/female_03.mdl"] = 3,
    ["models/humans/group01/female_04.mdl"] = 1,
    ["models/humans/group01/female_06.mdl"] = 4,
    ["models/humans/group01/female_07.mdl"] = 2,
    -- Group 02 Males
    ["models/humans/group02/male_01.mdl"] = 2,
    ["models/humans/group02/male_02.mdl"] = 4,
    ["models/humans/group02/male_03.mdl"] = 3,
    ["models/humans/group02/male_04.mdl"] = 0,
    ["models/humans/group02/male_05.mdl"] = 4,
    ["models/humans/group02/male_06.mdl"] = 0,
    ["models/humans/group02/male_07.mdl"] = 0,
    ["models/humans/group02/male_08.mdl"] = 0,
    ["models/humans/group02/male_09.mdl"] = 1,
    -- Group 02 Females
    ["models/humans/group02/female_01.mdl"] = 2,
    ["models/humans/group02/female_02.mdl"] = 4,
    ["models/humans/group02/female_03.mdl"] = 0,
    ["models/humans/group02/female_04.mdl"] = 4,
    ["models/humans/group02/female_06.mdl"] = 3,
    ["models/humans/group02/female_07.mdl"] = 3,
}

-- Default material paths for restoring "naked" jumpsuit state
ITEM.defaultMaterials = {
    male = "models/humans/male/group01/citizen_sheet",
    female = "models/humans/female/group01/citizen_sheet",
    male_group02 = "models/humans/male/group02/citizen_sheet",
    female_group02 = "models/humans/female/group02/citizen_sheet",
}

function ITEM:GetClothingIndex(client)
    local model = client:GetModel():lower()
    return self.clothingIndices[model] or 0
end

function ITEM:GetDefaultMaterial(client)
    local model = client:GetModel():lower()
    if model:find("group02") then
        if model:find("female") then
            return self.defaultMaterials.female_group02
        else
            return self.defaultMaterials.male_group02
        end
    else
        if model:find("female") then
            return self.defaultMaterials.female
        else
            return self.defaultMaterials.male
        end
    end
end

function ITEM:CanEquipOutfit()
    local client = self.player
    if not IsValid(client) then return false end

    local model = client:GetModel():lower()

    -- Check gender compatibility
    if self.maleOnly and model:find("female") then
        return false
    end
    if self.femaleOnly and model:find("male") and not model:find("female") then
        return false
    end

    return true
end

function ITEM:OnEquipped()
    local client = self:GetOwner()
    if not IsValid(client) then return end

    local clothingIndex = self:GetClothingIndex(client)
    if self.clothingMaterial then
        client:SetSubMaterial(clothingIndex, self.clothingMaterial)
    end
end

function ITEM:OnUnequipped()
    local client = self:GetOwner()
    if not IsValid(client) then return end

    local clothingIndex = self:GetClothingIndex(client)
    local defaultMat = self:GetDefaultMaterial(client)
    client:SetSubMaterial(clothingIndex, defaultMat)
end
