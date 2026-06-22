--[[
    Camera

    A camera with battery and film slots.
    - Battery: Powers the camera (2up per photo)
    - Film: Captures photos (1 shot per photo, 10 shots per pack)

    Film cannot be ejected once loaded - must use all 10 shots.
    When film is empty, it is automatically removed.
]]--

ITEM.name = "Camera"
ITEM.description = "A camera for taking photographs. Requires film."
ITEM.model = "models/weapons/infra/w_camera.mdl"
ITEM.width = 2
ITEM.height = 2
ITEM.category = "Equipment"
ITEM.noBusiness = true

-- Weapon configuration
ITEM.weaponClass = "ws_camera"
ITEM.equipSound = "items/flashlight1.wav"
ITEM.unequipSound = "items/flashlight1.wav"
ITEM.notifyPrefix = "camera"

-- Camera-specific configuration
ITEM.maxFilm = 1

-- ============================================================================
-- FILM HELPER FUNCTIONS (camera-specific)
-- ============================================================================

function ITEM:GetFilm()
    return self:GetData("film", nil)
end

function ITEM:SetFilm(film)
    self:SetData("film", film)
end

function ITEM:HasFilm()
    local film = self:GetFilm()
    return film ~= nil and film.shots > 0
end

function ITEM:GetFilmShots()
    local film = self:GetFilm()
    return film and film.shots or 0
end

function ITEM:ConsumeFilmShot()
    local film = self:GetFilm()
    if not film then return false end

    film.shots = film.shots - 1

    if film.shots <= 0 then
        self:SetFilm(nil)
        return true, true  -- success, film exhausted
    else
        self:SetFilm(film)
        return true, false  -- success, film not exhausted
    end
end

-- ============================================================================
-- CLIENT VISUALS (override to show film)
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        local film = item:GetData("film", nil)
        local isEquipped = item:GetData("equipped")

        -- Draw equipped indicator (green dot)
        if isEquipped then
            ws.constants.DrawEquippedIndicator(w, h)
        end

        local barY = h - 6
        local barHeight = 4

        -- Draw battery bar (optional, if using Windswept bridge)
        local batteries
        if item.GetBatteries then
            batteries = item:GetData("batteries", {})
        end

        if batteries and #batteries > 0 then
            barY = h - 12
            local charge = batteries[1]
            surface.SetDrawColor(30, 30, 30, 200)
            surface.DrawRect(4, barY - barHeight - 2, w - 8, barHeight)

            local chargeWidth = ((w - 8) / 100) * charge
            -- Optional helper for charge colors (use fallback if missing)
            local function GetChargeColor(c)
                if ws.constants and ws.constants.GetChargeColor then return ws.constants.GetChargeColor(c) end
                return c >= 20 and Color(100, 255, 100) or Color(255, 100, 100)
            end
            surface.SetDrawColor(GetChargeColor(charge))
            surface.DrawRect(4, barY - barHeight - 2, chargeWidth, barHeight)
        end

        -- Draw film indicator (bottom)
        if film then
            surface.SetDrawColor(30, 30, 30, 200)
            surface.DrawRect(4, barY, w - 8, barHeight)

            local shotWidth = ((w - 8) / 10) * film.shots
            surface.SetDrawColor(50, 150, 200)
            surface.DrawRect(4, barY, shotWidth, barHeight)
        end
    end

    function ITEM:PopulateTooltip(tooltip)
        local film = self:GetData("film", nil)

        -- Battery row (optional, if using Windswept bridge)
        local batteries
        if self.GetBatteries then
            batteries = self:GetData("batteries", {})
        end

        if batteries then
            local batteryRow = tooltip:AddRow("battery")
            if #batteries == 0 then
                batteryRow:SetText("No battery inserted.")
                batteryRow:SetBackgroundColor(Color(100, 100, 100))
            else
                local charge = batteries[1]
                batteryRow:SetText(string.format("Battery: %dup / 100up", charge))
                
                local function GetChargeColorDark(c)
                    if ws.constants and ws.constants.GetChargeColorDark then return ws.constants.GetChargeColorDark(c) end
                    return c >= 20 and Color(50, 150, 50) or Color(150, 50, 50)
                end
                
                batteryRow:SetBackgroundColor(GetChargeColorDark(charge))
            end
            batteryRow:SizeToContents()
        end

        -- Film row
        local filmRow = tooltip:AddRow("film")
        if not film then
            filmRow:SetText("No film loaded.")
            filmRow:SetBackgroundColor(Color(100, 100, 100))
        else
            filmRow:SetText(string.format("Film: %d / 10 shots", film.shots))
            if film.shots >= 5 then
                filmRow:SetBackgroundColor(Color(50, 100, 100))
            elseif film.shots >= 2 then
                filmRow:SetBackgroundColor(Color(100, 100, 50))
            else
                filmRow:SetBackgroundColor(Color(150, 100, 50))
            end
        end
        filmRow:SizeToContents()
    end
end

-- ============================================================================
-- ITEM FUNCTIONS - FILM (camera-specific)
-- ============================================================================

ITEM.functions.LoadFilm = {
    name = "Load Film",
    tip = "Insert a film pack into the camera.",
    icon = "icon16/picture_add.png",
    isMulti = true,
    multiOptions = function(item, client)
        local options = {}
        local character, inventory = ws.access.GetCharacterInventory(client)
        if not character or not inventory then return options end

        for _, invItem in pairs(inventory:GetItems()) do
            if invItem.uniqueID == "film" then
                local shots = invItem:GetData("shots", 10)
                if shots > 0 then
                    table.insert(options, {
                        name = string.format("Film Pack (%d shots)", shots),
                        data = {filmID = invItem:GetID(), shots = shots}
                    })
                end
            end
        end

        table.sort(options, function(a, b)
            return (a.data.shots or 0) > (b.data.shots or 0)
        end)

        return options
    end,
    OnRun = function(item, data)
        local client = item.player
        local filmID = data and data.filmID

        if not filmID then return false end

        -- filmID comes from the attacker-controlled net payload; verify the caller actually
        -- has access to that film (main inventory or an owned bag), exactly as LoadBattery
        -- does. Without this a crafted ID could load/consume another player's or a dropped
        -- film. (sc-photography-1)
        if not IsValid(client) then return false end

        local filmItem = ws.access.VerifyItemAccessible(client, filmID, "film")
        if not filmItem then
            return false
        end

        if item:HasFilm() then
            client:NotifyLocalized("cameraFilmSlotFull")
            return false
        end

        -- Clamp shots: the value is copied from item data and must not be trusted blindly.
        local shots = math.Clamp(math.floor(tonumber(filmItem:GetData("shots", 10)) or 0), 0, 100)
        item:SetFilm({shots = shots})
        filmItem:Remove()

        client:NotifyLocalized("cameraFilmLoaded", shots)
        client:EmitSound("items/ammocrate_open.wav", 50)

        return false
    end,
    OnCanRun = function(item)
        if item:HasFilm() then return false end
        if IsValid(item.entity) then return false end

        local client = item.player
        if not IsValid(client) then return false end

        local character, inventory = ws.access.GetCharacterInventory(client)
        if not character or not inventory then return false end

        for _, invItem in pairs(inventory:GetItems()) do
            if invItem.uniqueID == "film" then
                local shots = invItem:GetData("shots", 10)
                if shots > 0 then
                    return true
                end
            end
        end

        return false
    end
}

-- ============================================================================
-- EQUIP/UNEQUIP FUNCTIONS (Replacing base_battery_device)
-- ============================================================================

ITEM.functions.Equip = {
    name = "Equip",
    tip = "Hold this item in your hands.",
    icon = "icon16/tick.png",
    OnRun = function(item)
        local client = item.player

        if not item.weaponClass then
            return false
        end

        local existingItem = client.wsCameraItem
        if existingItem and existingItem ~= item then
            existingItem:SetData("equipped", nil)
        end

        if client:HasWeapon(item.weaponClass) then
            client:StripWeapon(item.weaponClass)
        end

        local weapon = client:Give(item.weaponClass)
        if IsValid(weapon) then
            weapon.wsItem = item
            client:SelectWeapon(item.weaponClass)
        end

        client.wsCameraItem = item
        item:SetData("equipped", true)

        client:EmitSound(item.equipSound, 50)
        return false
    end,
    OnCanRun = function(item)
        if IsValid(item.entity) then return false end
        if item:GetData("equipped") then return false end
        if not item.weaponClass then return false end
        return true
    end
}

ITEM.functions.Unequip = {
    name = "Unequip",
    tip = "Put this item away.",
    icon = "icon16/cross.png",
    OnRun = function(item)
        local client = item.player
        if not item.weaponClass then return false end

        local weapon = client:GetWeapon(item.weaponClass)
        if IsValid(weapon) then
            client:StripWeapon(item.weaponClass)
        end

        client.wsCameraItem = nil
        item:SetData("equipped", nil)

        local pitch = item.unequipSound and 100 or 90
        client:EmitSound(item.unequipSound or item.equipSound, 50, pitch)

        return false
    end,
    OnCanRun = function(item)
        return item:GetData("equipped") == true
    end
}

-- ============================================================================
-- BACKEND HOOKS
-- ============================================================================

function ITEM.postHooks.drop(item, result)
    if item:GetData("equipped") and item.weaponClass then
        local client = item:GetOwner()
        if IsValid(client) then
            local weapon = client:GetWeapon(item.weaponClass)
            if IsValid(weapon) then
                client:StripWeapon(item.weaponClass)
            end
            client.wsCameraItem = nil
        end
        item:SetData("equipped", nil)
    end
end

function ITEM:OnTransferred(oldInventory, newInventory)
    if self:GetData("equipped") and self.weaponClass then
        local oldOwner = oldInventory and oldInventory.GetOwner and oldInventory:GetOwner()
        if IsValid(oldOwner) then
            local weapon = oldOwner:GetWeapon(self.weaponClass)
            if IsValid(weapon) then
                oldOwner:StripWeapon(self.weaponClass)
            end
            oldOwner.wsCameraItem = nil
        end
        self:SetData("equipped", nil)
    end
end

function ITEM:CanTransfer(oldInventory, newInventory)
    if newInventory and self:GetData("equipped") then
        local owner = self:GetOwner()
        if IsValid(owner) then
            owner:NotifyLocalized(self.notifyPrefix .. "Equipped")
        end
        return false
    end
    return true
end

function ITEM:OnLoadout()
    if self:GetData("equipped") and self.weaponClass then
        local client = self.player
        if not IsValid(client) then return end

        local weapon = client:Give(self.weaponClass, true)
        if IsValid(weapon) then
            weapon.wsItem = self
            client.wsCameraItem = self
        end
    end
end
