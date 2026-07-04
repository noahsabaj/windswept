--[[
    Camera SWEP

    Controls:
    - RMB (Hold): Enter viewfinder mode
    - LMB: Take photo (only while aiming)
    - Middle Mouse: Toggle flash ON/OFF
    - Scroll Wheel: Zoom in/out

    Requirements per photo:
    - Battery: 2up
    - Film: 1 shot
]]--

AddCSLuaFile()

SWEP.Base = "base_windswept_swep"
SWEP.PrintName = "Camera"
SWEP.Purpose = "Capture photographs."
SWEP.Instructions = "RMB: Aim | LMB: Photo | Middle Mouse: Flash | Scroll: Zoom"

SWEP.ViewModelFOV = 50
SWEP.ViewModel = Model("models/weapons/infra/c_camera.mdl")
SWEP.WorldModel = Model("models/weapons/infra/w_camera.mdl")
SWEP.HoldType = "camera"

-- INFRA Camera models: https://steamcommunity.com/sharedfiles/filedetails/?id=3410154200
if SERVER then
    resource.AddWorkshop("3410154200")
end

-- Configuration
SWEP.MinFOV = 10      -- Maximum zoom (lowest FOV)
SWEP.MaxFOV = 90      -- Minimum zoom (highest FOV)
SWEP.DefaultFOV = 70
SWEP.ZoomSpeed = 5

SWEP.FlashDuration = 0.25

-- ============================================================================
-- DATA TABLES
-- ============================================================================

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "Aiming")
    self:NetworkVar("Bool", 1, "FlashEnabled")
    self:NetworkVar("Float", 0, "CurrentFOV")

    self:SetAiming(false)
    self:SetFlashEnabled(false)
    self:SetCurrentFOV(self.DefaultFOV)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function SWEP:Deploy()
    self.BaseClass.Deploy(self)
    self:SetAiming(false)
    self:SetCurrentFOV(self.DefaultFOV)
    return true
end

function SWEP:Holster()
    self:SetAiming(false)
    return true
end

-- ============================================================================
-- PRIMARY ATTACK - Take Photo
-- ============================================================================

function SWEP:PrimaryAttack()
    -- Photo capture is handled in Think() using input.IsMouseDown(MOUSE_LEFT)
    -- because Windswept's weapon system doesn't call PrimaryAttack on CLIENT
    -- This stub prevents default weapon behavior
    if self:GetAiming() then
        self:SetNextPrimaryFire(CurTime() + 1)
    end
end

-- ============================================================================
-- SECONDARY ATTACK - Toggle Aiming
-- ============================================================================

function SWEP:SecondaryAttack()
    -- Handled in Think for hold behavior
end

-- ============================================================================
-- RELOAD - Not used (flash toggle is middle mouse)
-- ============================================================================

function SWEP:Reload()
    -- Intentionally empty - flash toggle moved to middle mouse
end

-- ============================================================================
-- THINK - Handle Aiming and Zoom
-- ============================================================================

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    -- CRITICAL: Only handle input-based logic on CLIENT
    -- Server doesn't have input context (KeyDown returns false), which causes state flicker
    if CLIENT then
        -- Weapon must be raised to use camera features
        local isRaised = owner:IsWepRaised()

        -- Handle aiming (RMB hold) - only when weapon is raised
        local shouldAim = isRaised and owner:KeyDown(IN_ATTACK2)

        if shouldAim ~= self:GetAiming() then
            self:SetAiming(shouldAim)
            net.Start("wsCameraSetAiming")
                net.WriteBool(shouldAim)
            net.SendToServer()
        end

        -- Handle photo capture (LMB) - only when aiming
        -- NOTE: We handle this in Think() instead of PrimaryAttack because Windswept's
        -- weapon system doesn't call PrimaryAttack on CLIENT (only SERVER)
        if self:GetAiming() then
            local lmbDown = input.IsMouseDown(MOUSE_LEFT)

            if lmbDown and not self.wasLMBDown then
                -- LMB just pressed while aiming
                if not self.nextPhotoTime or self.nextPhotoTime <= CurTime() then
                    self.nextPhotoTime = CurTime() + 1
                    net.Start("wsCameraRequestPhoto")
                    net.SendToServer()
                end
            end

            self.wasLMBDown = lmbDown
        else
            self.wasLMBDown = false
        end

        -- Handle flash toggle (middle mouse) - only when weapon is raised
        if isRaised then
            local middleMouseDown = input.IsMouseDown(MOUSE_MIDDLE)

            if middleMouseDown and not self.wasMiddleMouseDown then
                -- Middle mouse just pressed
                if not self.nextFlashToggle or self.nextFlashToggle <= CurTime() then
                    self.nextFlashToggle = CurTime() + 0.3
                    net.Start("wsCameraToggleFlash")
                    net.SendToServer()
                end
            end

            self.wasMiddleMouseDown = middleMouseDown
        else
            self.wasMiddleMouseDown = false
        end

        -- Suppress weapon select UI while aiming
        if self:GetAiming() then
            local wepselect = ws.plugin.Get("wepselect")
            if wepselect then
                wepselect.alpha = 0
                wepselect.alphaDelta = 0

                local weapons = owner:GetWeapons()
                for i, w in ipairs(weapons) do
                    if w == self then
                        wepselect.index = i
                        wepselect.deltaIndex = i
                        break
                    end
                end
            end
        end
    end
end

-- Handle zoom through global CreateMove hook (SWEP:CreateMove doesn't exist in GMod)
if CLIENT then
    hook.Add("CreateMove", "wsCameraZoom", function(cmd)
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local weapon = ply:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "ws_camera" then return end

        local wheel = cmd:GetMouseWheel()
        if wheel == 0 then return end
        if not weapon:GetAiming() then return end

        local newFOV = weapon:GetCurrentFOV() - (wheel * weapon.ZoomSpeed)
        newFOV = math.Clamp(newFOV, weapon.MinFOV, weapon.MaxFOV)

        -- Update locally for smooth response
        weapon:SetCurrentFOV(newFOV)

        -- Sync to server
        net.Start("wsCameraSetZoom")
            net.WriteFloat(newFOV)
        net.SendToServer()
    end)
end

-- Block weapon select from consuming scroll wheel while aiming
-- Must inject into HOOKS_CACHE to run BEFORE Windswept's wepselect plugin
if CLIENT then
    local function SetupCameraScrollBlock()
        -- Create a fake plugin entry to insert into HOOKS_CACHE
        local cameraInputPlugin = {
            uniqueID = "ws_camera_input",
            name = "Camera Input Handler"
        }

        -- Ensure the hook cache exists
        HOOKS_CACHE["PlayerBindPress"] = HOOKS_CACHE["PlayerBindPress"] or {}

        -- Check if already added
        for plugin, _ in pairs(HOOKS_CACHE["PlayerBindPress"]) do
            if plugin.uniqueID == "ws_camera_input" then
                return
            end
        end

        -- Insert our hook into the plugin-level cache
        HOOKS_CACHE["PlayerBindPress"][cameraInputPlugin] = function(self, client, bind, pressed)
            local weapon = client:GetActiveWeapon()
            if not IsValid(weapon) or weapon:GetClass() ~= "ws_camera" then return end
            if not weapon:GetAiming() then return end

            bind = bind:lower()

            -- Block scroll wheel binds while aiming
            if bind:find("invprev") or bind:find("invnext") then
                return true  -- Consume input, prevent weapon select
            end
        end
    end

    -- Try to set up immediately if HOOKS_CACHE exists (player joined late)
    if HOOKS_CACHE then
        SetupCameraScrollBlock()
    end

    -- Also set up on InitializedPlugins for fresh server start
    hook.Add("InitializedPlugins", "wsCameraSetupScrollBlock", function()
        SetupCameraScrollBlock()
    end)
end

-- ============================================================================
-- FOV OVERRIDE
-- ============================================================================

function SWEP:TranslateFOV(fov)
    if self:GetAiming() then
        return self:GetCurrentFOV()
    end
    return fov
end

-- ============================================================================
-- CLIENT: HUD
-- ============================================================================

if CLIENT then
    -- Helper function to find the camera item from player's inventory
    -- Cached to avoid inventory scan every frame
    function SWEP:GetCameraItem()
        -- Check cache validity (refresh every 0.5s or if item became invalid)
        local now = CurTime()
        if self._cameraItemCache and self._cameraItemCacheTime and (now - self._cameraItemCacheTime) < 0.5 then
            return self._cameraItemCache
        end

        local owner = self:GetOwner()
        if not IsValid(owner) then
            self._cameraItemCache = nil
            self._cameraItemCacheTime = now
            return nil
        end

        local character, inventory = ws.access.GetCharacterInventory(owner)
        if not character or not inventory then
            self._cameraItemCache = nil
            self._cameraItemCacheTime = now
            return nil
        end

        -- Use GetItemsByUniqueID for faster filtering
        local cameras = inventory:GetItemsByUniqueID("camera", true)
        for _, item in ipairs(cameras) do
            if item:GetData("equipped") then
                self._cameraItemCache = item
                self._cameraItemCacheTime = now
                return item
            end
        end

        self._cameraItemCache = nil
        self._cameraItemCacheTime = now
        return nil
    end

    function SWEP:DrawHUD()
        if not self:GetAiming() then return end

        local scrW, scrH = ScrW(), ScrH()
        local item = self:GetCameraItem()

        -- Square viewfinder frame - purely cosmetic framing overlay.
        -- CapturePhoto() uses render.RenderView() with the same FOV, so the
        -- full visible scene inside this frame is what ends up in the photo.
        local borderSize = 80
        local maxViewfinderW = scrW - (borderSize * 2)
        local maxViewfinderH = scrH - (borderSize * 2)
        local squareSize = math.min(maxViewfinderW, maxViewfinderH)
        local squareX = (scrW - squareSize) / 2
        local squareY = (scrH - squareSize) / 2

        -- Draw black overlay covering everything EXCEPT the square viewfinder
        surface.SetDrawColor(0, 0, 0, 220)
        -- Top strip
        surface.DrawRect(0, 0, scrW, squareY)
        -- Bottom strip
        surface.DrawRect(0, squareY + squareSize, scrW, scrH - (squareY + squareSize))
        -- Left strip
        surface.DrawRect(0, squareY, squareX, squareSize)
        -- Right strip
        surface.DrawRect(squareX + squareSize, squareY, scrW - (squareX + squareSize), squareSize)

        -- Viewfinder frame (white border around square)
        surface.SetDrawColor(255, 255, 255, 150)
        surface.DrawOutlinedRect(squareX, squareY, squareSize, squareSize, 2)

        -- Crosshair (circle + square) - centered
        local cx, cy = scrW / 2, scrH / 2

        -- Outer circle
        surface.DrawCircle(cx, cy, 30, 255, 255, 255, 150)
        -- Inner square
        surface.SetDrawColor(255, 255, 255, 150)
        surface.DrawOutlinedRect(cx - 10, cy - 10, 20, 20, 1)

        -- Corner brackets (scale based on viewfinder size)
        local bracketSize = math.max(20, squareSize * 0.02)
        local bracketOffset = squareSize * 0.15
        surface.SetDrawColor(255, 255, 255, 200)

        -- Top-left
        surface.DrawRect(cx - bracketOffset, cy - bracketOffset, bracketSize, 2)
        surface.DrawRect(cx - bracketOffset, cy - bracketOffset, 2, bracketSize)
        -- Top-right
        surface.DrawRect(cx + bracketOffset - bracketSize, cy - bracketOffset, bracketSize, 2)
        surface.DrawRect(cx + bracketOffset - 2, cy - bracketOffset, 2, bracketSize)
        -- Bottom-left
        surface.DrawRect(cx - bracketOffset, cy + bracketOffset - 2, bracketSize, 2)
        surface.DrawRect(cx - bracketOffset, cy + bracketOffset - bracketSize, 2, bracketSize)
        -- Bottom-right
        surface.DrawRect(cx + bracketOffset - bracketSize, cy + bracketOffset - 2, bracketSize, 2)
        surface.DrawRect(cx + bracketOffset - 2, cy + bracketOffset - bracketSize, 2, bracketSize)

        -- Info bar at bottom of viewfinder (inside the square)
        local infoY = squareY + squareSize - 30

        -- Semi-transparent background for info bar
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(squareX, infoY - 5, squareSize, 40)

        -- Battery indicator (optional, if using Windswept bridge)
        local hasBatterySystem = false
        local batteryCharge = 0

        if item and item.GetBatteries then
            hasBatterySystem = true
            local batteries = item:GetData("batteries", {})
            batteryCharge = batteries[1] or 0
        end

        local flashText = self:GetFlashEnabled() and "FLASH: ON" or "FLASH: OFF"
        local zoomPercent = math.Round(100 - ((self:GetCurrentFOV() - self.MinFOV) / (self.MaxFOV - self.MinFOV)) * 100)
        local flashColor = self:GetFlashEnabled() and Color(255, 255, 100) or ws.constants.COLOR_UI_NEUTRAL
        local infoText = string.format("[%s | Zoom: %d%%]", flashText, zoomPercent)

        if hasBatterySystem then
            local batteryColor = batteryCharge >= 20 and Color(100, 255, 100) or Color(255, 100, 100)
            draw.SimpleText(string.format("⚡ %dup", batteryCharge), "wsMediumFont", squareX + 20, infoY, batteryColor, TEXT_ALIGN_LEFT)
            
            -- Show tools in center
            draw.SimpleText(infoText, "wsMediumFont", cx, infoY, flashColor, TEXT_ALIGN_CENTER)
        else
            -- No battery, shift tools to left
            draw.SimpleText(infoText, "wsMediumFont", squareX + 20, infoY, flashColor, TEXT_ALIGN_LEFT)
        end

        -- Film indicator (right)
        local filmShots = 0
        if item then
            local film = item:GetData("film", nil)
            filmShots = film and film.shots or 0
        end

        local filmColor = filmShots > 0 and Color(100, 200, 255) or Color(255, 100, 100)
        draw.SimpleText(string.format("%d/10", filmShots), "wsMediumFont", squareX + squareSize - 20, infoY, filmColor, TEXT_ALIGN_RIGHT)
    end

    -- Hide default crosshair when aiming
    function SWEP:DoDrawCrosshair(x, y)
        return self:GetAiming()
    end

    -- ========================================================================
    -- CLIENT: Photo Capture
    -- ========================================================================

    net.Receive("wsCameraApprovePhoto", function()
        local weapon = LocalPlayer():GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "ws_camera" then return end

        -- The flash must light the CAPTURE, so it is client-side: a dlight
        -- created here (net processing runs before this frame renders) is in
        -- the renderer's light list when CapturePhoto's PostRender RenderView
        -- draws the world -- the photo gets real flash lighting with distance
        -- falloff. The old server-side light_dynamic never showed up in
        -- photos (#108). dietime outlasts the capture so the shooter also
        -- sees the world lit briefly, matching the screen flash.
        if weapon:GetFlashEnabled() then
            local owner = LocalPlayer()
            local dl = DynamicLight(owner:EntIndex())
            if dl then
                dl.pos = owner:EyePos() + owner:GetAimVector() * 8
                dl.r = 255
                dl.g = 255
                dl.b = 255
                dl.brightness = 5
                dl.size = 600
                dl.decay = 2400
                dl.dietime = CurTime() + 0.25
            end
        end

        -- Capture the photo
        weapon:CapturePhoto()
    end)

    -- Render target for photo capture (768x768, created once and reused)
    local photoRT = GetRenderTarget("wsCameraPhoto", 768, 768)

    function SWEP:CapturePhoto()
        local owner = self:GetOwner()
        if not IsValid(owner) then return end

        -- Calculate the effective FOV of the viewfinder square BEFORE the PostRender
        -- hook fires, so we capture exactly what the player sees framed.
        --
        -- The viewfinder is a square crop of the widescreen view. Source treats the
        -- camera FOV as horizontal FOV. The viewfinder square is height-limited
        -- (squareSize = scrH - 160 on widescreen), so it spans squareSize/scrW of
        -- the horizontal FOV. We need the angular extent of that square so the 1:1
        -- render target matches it exactly.
        local scrW, scrH = ScrW(), ScrH()
        local borderSize = 80
        local squareSize = math.min(scrW - borderSize * 2, scrH - borderSize * 2)
        local hFOV = self:GetCurrentFOV()
        local viewfinderFOV = math.deg(2 * math.atan(
            math.tan(math.rad(hFOV / 2)) * (squareSize / scrW)
        ))

        hook.Add("PostRender", "wsCameraCapture", function()
            hook.Remove("PostRender", "wsCameraCapture")

            if not IsValid(self) or not IsValid(owner) then return end

            render.PushRenderTarget(photoRT)
                render.Clear(0, 0, 0, 255)
                render.RenderView({
                    origin = owner:EyePos(),
                    angles = owner:EyeAngles(),
                    x = 0, y = 0,
                    w = 768, h = 768,
                    fov = viewfinderFOV,
                    drawviewmodel = false,
                })

                -- Adaptive quality: try high quality first, reduce if scene is too complex.
                -- Raw binary (no base64) gives us ~60KB of actual JPEG budget.
                local data
                for _, quality in ipairs({70, 50, 35}) do
                    data = render.Capture({
                        format = "jpeg",
                        quality = quality,
                        x = 0, y = 0,
                        w = 768, h = 768
                    })
                    if not data then break end
                    if #data <= 60000 then break end
                end
            render.PopRenderTarget()

            if data and #data > 0 then
                if #data > 60000 then
                    LocalPlayer():NotifyLocalized("cameraImageTooLarge")
                    return
                end

                net.Start("wsCameraPhotoData")
                    net.WriteUInt(#data, 32)
                    net.WriteData(data, #data)
                net.SendToServer()

                surface.PlaySound("buttons/lightswitch2.wav")
            end
        end)
    end

    -- Cycling reserved dlight indices for bystander flashes (entity indices
    -- belong to the shooters' own capture lights / muzzle flashes, and a
    -- single fixed index would drop one of two simultaneous flashes).
    local flashLightIndex = 0

    -- Flash effect received from server
    net.Receive("wsCameraFlashEffect", function()
        local pos = net.ReadVector()

        -- Create screen flash effect for local player if nearby
        local localPlayer = LocalPlayer()
        if localPlayer:GetPos():Distance(pos) < 500 then
            -- Real light in the world, not just a screen overlay (#108).
            -- Skip for our own flash -- the capture path already lit it.
            if localPlayer:GetPos():DistToSqr(pos) > 100 then
                flashLightIndex = (flashLightIndex + 1) % 8
                local dl = DynamicLight(8000 + flashLightIndex)
                if dl then
                    dl.pos = pos + Vector(0, 0, 60) -- camera height above feet
                    dl.r = 255
                    dl.g = 255
                    dl.b = 255
                    dl.brightness = 5
                    dl.size = 600
                    dl.decay = 2400
                    dl.dietime = CurTime() + 0.25
                end
            end

            -- Brief white flash on screen
            local flash = vgui.Create("DPanel")
            flash:SetSize(ScrW(), ScrH())
            flash:SetPos(0, 0)
            flash.startTime = RealTime()
            flash.Paint = function(pnl, w, h)
                local alpha = 255 * (1 - (RealTime() - pnl.startTime) / 0.15)
                if alpha <= 0 then
                    pnl:Remove()
                    return
                end
                surface.SetDrawColor(255, 255, 255, alpha)
                surface.DrawRect(0, 0, w, h)
            end
        end
    end)

    -- Flash toggle feedback
    net.Receive("wsCameraFlashToggled", function()
        local enabled = net.ReadBool()
        local weapon = LocalPlayer():GetActiveWeapon()
        if IsValid(weapon) and weapon:GetClass() == "ws_camera" then
            weapon:SetFlashEnabled(enabled)
        end

        if enabled then
            LocalPlayer():NotifyLocalized("cameraFlashOn")
        else
            LocalPlayer():NotifyLocalized("cameraFlashOff")
        end
    end)
end

-- ============================================================================
-- SERVER: Networking
-- ============================================================================

if SERVER then
    -- Network strings registered in schema/sv_netstrings.lua

    -- Forward declaration for ProcessCompletePhoto (defined below)
    local ProcessCompletePhoto

    -- Handle photo request. ws.weapon.NetReceive supplies the active-weapon class check + a
    -- 0.5s rate limit (each request can trigger a flash net broadcast); the
    -- aiming / film / approval logic stays in the method. (sc-photography-2)
    ws.weapon.NetReceive("wsCameraRequestPhoto", "ws_camera", "NetRequestPhoto", { rateLimit = 0.5 })

    function SWEP:NetRequestPhoto()
        local weapon = self
        local client = self:GetOwner()
        if not IsValid(client) then return end

        if not weapon:GetAiming() then return end

        local item = weapon.wsItem
        if not item then return end

        -- Check film
        local film = item:GetData("film", nil)
        if not film or film.shots <= 0 then
            client:NotifyLocalized("cameraNoFilm")
            return
        end

        -- Call hook to see if any other plugins block this photo (e.g. Battery bridge)
        -- Passing 'false' as 3rd arg means "just check, don't drain"
        if hook.Run("wsCameraCanTakePhoto", client, item, false) == false then
            return
        end

        -- Issue a one-shot, short-lived approval. wsCameraPhotoData requires it, so
        -- a client can't upload an arbitrary photo we never asked for.
        client.wsCameraApproval = CurTime()

        -- Resources OK. Flash lighting is entirely client-side (#108): the
        -- capturing client creates its own dlight in the capture frame (the
        -- old server light_dynamic never appeared in photos), and nearby
        -- clients build a world dlight + screen flash from this effect
        -- message. No wait-for-light delay needed -- approve immediately.
        if weapon:GetFlashEnabled() then
            local nearby = ents.FindInSphere(client:GetPos(), 500)
            for _, ent in ipairs(nearby) do
                if ent:IsPlayer() then
                    net.Start("wsCameraFlashEffect")
                        net.WriteVector(client:GetPos())
                    net.Send(ent)
                end
            end
        end

        net.Start("wsCameraApprovePhoto")
        net.Send(client)
    end

    -- Handle photo data from client
    -- Raw JPEG binary with adaptive quality, fits in single message (<64KB)
    net.Receive("wsCameraPhotoData", function(len, client)
        local dataLen = net.ReadUInt(32)

        -- Bound the declared size before reading (defends against an absurd dataLen)
        if dataLen <= 0 or dataLen > ws.photo.MAX_PHOTO_BYTES then return end

        local imageData = net.ReadData(dataLen)

        if not imageData or #imageData == 0 then
            return
        end

        ProcessCompletePhoto(client, imageData)
    end)

    -- Shared function to process complete photo data
    ProcessCompletePhoto = function(client, imageData)
        local weapon = client:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "ws_camera" then return end

        local item = weapon.wsItem
        if not item then return end

        -- Require a recent one-shot approval issued by wsCameraRequestPhoto, so a
        -- client can't push an arbitrary photo by calling this directly.
        if not client.wsCameraApproval or CurTime() - client.wsCameraApproval > 5 then
            return
        end
        client.wsCameraApproval = nil

        local capChar = client:GetCharacter()
        if not capChar then return end

        -- Enforce configurable anti-spam caps BEFORE consuming film/battery.
        local diskCapMB = ws.config.Get("maxPhotoDiskMB", 512)
        if diskCapMB > 0 and (ws.photo.GetDiskUsage() + #imageData) > diskCapMB * 1024 * 1024 then
            client:NotifyLocalized("cameraStorageFull")
            return
        end

        local photoCap = ws.config.Get("maxPhotosPerChar", 100)
        if photoCap > 0 and ws.photo.CountCharacterPhotos(capChar) >= photoCap then
            client:NotifyLocalized("cameraTooManyPhotos")
            return
        end

        local film = item:GetData("film", nil)
        if not film or film.shots <= 0 then
            return
        end

        -- Hook verification (re-run draining/blocking logic)
        -- Passing 'true' as 3rd arg means "really drain"
        if hook.Run("wsCameraCanTakePhoto", client, item, true) == false then 
            return
        end

        -- Consume film shot
        film.shots = film.shots - 1
        if film.shots <= 0 then
            item:SetData("film", nil)
            client:NotifyLocalized("cameraFilmEmpty")
        else
            item:SetData("film", film)
        end

        -- Flash lighting happened client-side in the capture frame (#108)

        -- Create photo item
        local character, inventory = ws.access.GetCharacterInventory(client)
        if not character or not inventory then return end

        -- Generate unique photo ID and save image to file
        -- This prevents inventory sync overflow (storing ~25KB per photo in item data would crash)
        -- Regenerate on the small chance the timestamp+random pair collides with an existing
        -- file, so a new photo can't overwrite/leak another's image. Keeps the "%d+_%d+"
        -- format the ReadPhotoFile path-traversal guard relies on. (sc-photography-6)
        local photoID
        for _ = 1, 8 do
            photoID = os.time() .. "_" .. math.random(10000, 99999)
            if ws.photo.ReadPhotoFile(photoID) == nil then break end
        end

        -- Save raw JPEG binary to file (centralized so disk usage stays tracked)
        ws.photo.WritePhotoFile(photoID, imageData)

        -- Item only stores the ID reference, not the actual image data.
        -- Fog of war: no photographer name -- item data networks wholesale to whoever
        -- holds the item, so a stored character name would travel with every trade,
        -- drop and loot. The image itself is the only identity a photo carries. (#72)
        local photoData = {
            photoID = photoID,  -- Reference to file, NOT the actual image
            timestamp = os.time(),
            title = "",
            titleSet = false
        }

        -- Try to add to inventory
        local success = inventory:Add("photo", 1, photoData)

        if success then
            client:NotifyLocalized("cameraPhotoTaken")
        else
            -- Drop on ground
            local dropPos = client:GetPos() + Vector(0, 0, 16)
            ws.item.Spawn("photo", dropPos, nil, nil, photoData)
            client:NotifyLocalized("cameraInventoryFull")
        end

        -- Play shutter sound for others
        client:EmitSound("buttons/lightswitch2.wav", 60)
    end

    -- Handle aiming state. Light rate-limit (0.05s): normal play only sends on state change;
    -- this caps a spamming/modified client. ws.weapon.NetReceive does the class check + limit,
    -- then calls SetAiming(bool) (the networked-var setter).
    ws.weapon.NetReceive("wsCameraSetAiming", "ws_camera", "SetAiming", {
        rateLimit = 0.05,
        read = function() return net.ReadBool() end,
    })

    -- Handle zoom (0.05s rate-limit). The FOV clamp moves into NetSetZoom so the wrapper only
    -- needs the class check + limit + payload. ws.weapon.NetReceive supplies those.
    ws.weapon.NetReceive("wsCameraSetZoom", "ws_camera", "NetSetZoom", {
        rateLimit = 0.05,
        read = function() return net.ReadFloat() end,
    })

    function SWEP:NetSetZoom(fov)
        fov = math.Clamp(fov, self.MinFOV, self.MaxFOV)
        self:SetCurrentFOV(fov)
    end

    -- Handle flash toggle. ws.weapon.NetReceive does the active-weapon class check; the toggle
    -- + ack move into NetToggleFlash.
    ws.weapon.NetReceive("wsCameraToggleFlash", "ws_camera", "NetToggleFlash")

    function SWEP:NetToggleFlash()
        local enabled = not self:GetFlashEnabled()
        self:SetFlashEnabled(enabled)

        net.Start("wsCameraFlashToggled")
            net.WriteBool(enabled)
        net.Send(self:GetOwner())
    end
end

-- ============================================================================
-- HOOKS
-- ============================================================================

ws.weapon.RegisterCleanupHooks("ws_camera", "wsCamera", function(weapon)
    weapon:SetAiming(false)
end)
