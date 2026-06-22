--[[
    Photo System Library

    Shared utilities and base VGUI panel for the photo and photo album systems.
    Provides: ownership verification, file I/O, material loading, and a base
    fullscreen photo viewer panel that both wsPhotoViewer and wsPhotoAlbumViewer
    inherit from.
]]--

ws.photo = ws.photo or {}

-- ============================================================================
-- SERVER UTILITIES
-- ============================================================================

if SERVER then
    -- Storage directory + hard size cap for a single photo (matches the client's
    -- ~60KB adaptive-quality cap, with a little headroom).
    ws.photo.DIR = "ws_photos"
    ws.photo.MAX_PHOTO_BYTES = 65536

    --- Verify that a client owns an item in their inventory.
    -- Thin wrapper around ws.access.VerifyItemOwnership for API compatibility.
    -- @param client Player to check
    -- @param itemID Numeric item ID
    -- @param expectedUniqueID Optional uniqueID to validate (e.g., "photo")
    -- @return item if found and valid, nil otherwise
    function ws.photo.VerifyOwnership(client, itemID, expectedUniqueID)
        return ws.access.VerifyItemOwnership(client, itemID, expectedUniqueID)
    end

    --- Cached total disk usage (bytes) of the photo directory. Computed lazily once
    --- then kept in sync by WritePhotoFile/DeletePhotoFile so the disk cap check
    --- doesn't rescan the directory on every capture.
    function ws.photo.GetDiskUsage()
        if ws.photo.diskUsage then return ws.photo.diskUsage end

        local total = 0
        for _, f in ipairs(file.Find(ws.photo.DIR .. "/*.dat", "DATA") or {}) do
            total = total + (file.Size(ws.photo.DIR .. "/" .. f, "DATA") or 0)
        end

        ws.photo.diskUsage = total
        return total
    end

    --- Write a photo file, keeping cached disk usage in sync.
    -- @return boolean Success
    function ws.photo.WritePhotoFile(photoID, data)
        if not photoID or not photoID:match("^%d+_%d+$") then return false end
        if not data or #data == 0 then return false end

        if not file.IsDir(ws.photo.DIR, "DATA") then
            file.CreateDir(ws.photo.DIR)
        end

        file.Write(ws.photo.DIR .. "/" .. photoID .. ".dat", data)
        ws.photo.GetDiskUsage()  -- ensure cache initialized before incrementing
        ws.photo.diskUsage = ws.photo.diskUsage + #data
        return true
    end

    --- Read a photo file by ID with path traversal protection.
    -- @param photoID The photo identifier (format: "timestamp_random")
    -- @return imageData Raw binary JPEG data if found, nil otherwise
    function ws.photo.ReadPhotoFile(photoID)
        if not photoID or photoID == "" then return nil end

        -- Validate format to prevent path traversal
        if not photoID:match("^%d+_%d+$") then return nil end

        return file.Read(ws.photo.DIR .. "/" .. photoID .. ".dat", "DATA")
    end

    --- Delete a photo file by ID, keeping cached disk usage in sync.
    -- @param photoID The photo identifier
    function ws.photo.DeletePhotoFile(photoID)
        if not photoID or photoID == "" then return end
        if not photoID:match("^%d+_%d+$") then return end

        local path = ws.photo.DIR .. "/" .. photoID .. ".dat"
        if file.Exists(path, "DATA") then
            if ws.photo.diskUsage then
                ws.photo.diskUsage = math.max(0, ws.photo.diskUsage - (file.Size(path, "DATA") or 0))
            end
            file.Delete(path)
        end
    end

    -- Run fn(item) on each photo item in a character's accessible inventories
    -- (main inventory + one level of bags/albums, since bags can't nest). Returns
    -- true as soon as fn returns true; otherwise false.
    local function forEachAccessiblePhoto(character, fn)
        local inv = character and character:GetInventory()
        if not inv then return false end

        for _, item in pairs(inv:GetItems()) do
            if item.uniqueID == "photo" and fn(item) then
                return true
            end

            -- Descend into owned bag/album inventories (one level deep)
            if item.isBag and isfunction(item.GetInventory) then
                local sub = item:GetInventory()
                if sub and sub ~= inv then
                    for _, subItem in pairs(sub:GetItems()) do
                        if subItem.uniqueID == "photo" and fn(subItem) then
                            return true
                        end
                    end
                end
            end
        end

        return false
    end

    --- Does a character possess a photo item referencing this photoID? (main
    --- inventory or any owned bag/album).
    function ws.photo.CharacterHasPhotoID(character, photoID)
        if not photoID or photoID == "" then return false end
        return forEachAccessiblePhoto(character, function(item)
            return item:GetData("photoID") == photoID
        end)
    end

    --- Count photo items a character holds across accessible inventories.
    function ws.photo.CountCharacterPhotos(character)
        local count = 0
        forEachAccessiblePhoto(character, function()
            count = count + 1
            return false  -- keep scanning
        end)
        return count
    end

    --- Temporarily grant a client permission to fetch these photoIDs. Used when
    --- the server legitimately reveals photos (browsing an album, proximity ground
    --- view). Short-lived so photo IDs can't be enumerated.
    function ws.photo.GrantPhotoAccess(client, photoIDs)
        client.wsPhotoGrants = client.wsPhotoGrants or {}
        local expiry = CurTime() + 60
        for _, id in ipairs(photoIDs) do
            if id and id ~= "" then
                client.wsPhotoGrants[id] = expiry
            end
        end
    end

    --- May this client fetch this photoID? True if they possess the photo item, or
    --- hold an unexpired grant from a legitimate reveal.
    function ws.photo.CanAccessPhoto(client, photoID)
        if not photoID or photoID == "" then return false end

        if ws.photo.CharacterHasPhotoID(client:GetCharacter(), photoID) then
            return true
        end

        local grants = client.wsPhotoGrants
        if grants and grants[photoID] and grants[photoID] > CurTime() then
            return true
        end

        return false
    end
end

-- ============================================================================
-- CLIENT UTILITIES
-- ============================================================================

if CLIENT then
    --- Create a Material from raw JPEG binary data.
    -- Writes to a unique temp file to avoid Material() cache returning stale textures.
    -- @param imageData Raw JPEG binary string
    -- @param identifier Unique string for temp file naming
    -- @return material IMaterial or nil
    -- @return tempPath String path to temp file (for cleanup), or nil
    function ws.photo.LoadMaterial(imageData, identifier)
        if not imageData or #imageData == 0 then return nil, nil end

        local tempPath = "wsphoto_" .. (identifier or SysTime()) .. ".jpg"
        file.Write(tempPath, imageData)

        return Material("../data/" .. tempPath, "smooth"), tempPath
    end

    --- Delete a temp photo file.
    -- @param path Data-relative path to delete
    function ws.photo.CleanupTempFile(path)
        if path and file.Exists(path, "DATA") then
            file.Delete(path)
        end
    end
end

-- ============================================================================
-- CLIENT: Base Photo Viewer Panel
-- ============================================================================

if CLIENT then
    local PANEL = {}

    function PANEL:Init()
        self:SetSize(ScrW(), ScrH())
        self:SetPos(0, 0)
        self:MakePopup()
        self:SetKeyboardInputEnabled(true)

        self.closeKeys = {KEY_W, KEY_A, KEY_S, KEY_D}
    end

    -- Override these in child panels
    function PANEL:GetPhotoMat() return nil end
    function PANEL:GetPhotoTitle() return "Untitled Photograph" end
    function PANEL:IsPhotoLoading() return false end
    function PANEL:GetEmptyText() return "No Image" end
    function PANEL:GetCloseText() return "Press LMB or WASD to close" end
    function PANEL:DrawExtraContent(w, h, imgSize, imgX, imgY) end
    function PANEL:OnExtraKeyPress(key) return false end
    function PANEL:OnCleanup() end

    function PANEL:Paint(w, h)
        -- Dark background
        surface.SetDrawColor(0, 0, 0, 240)
        surface.DrawRect(0, 0, w, h)

        -- Scale photo to 65% of screen height
        local imgSize = math.floor(h * 0.65)
        local imgX = (w - imgSize) / 2
        local imgY = (h - imgSize) / 2 - 30

        -- White border
        surface.SetDrawColor(255, 255, 255)
        surface.DrawOutlinedRect(imgX - 4, imgY - 4, imgSize + 8, imgSize + 8, 2)

        -- Draw photo, loading state, or empty state
        local mat = self:GetPhotoMat()

        if mat and not mat:IsError() then
            surface.SetMaterial(mat)
            surface.SetDrawColor(255, 255, 255)
            surface.DrawTexturedRect(imgX, imgY, imgSize, imgSize)
        else
            surface.SetDrawColor(40, 40, 40)
            surface.DrawRect(imgX, imgY, imgSize, imgSize)

            if self:IsPhotoLoading() then
                draw.SimpleText("Loading...", "wsMediumFont", w / 2, imgY + imgSize / 2, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(self:GetEmptyText(), "wsMediumFont", w / 2, imgY + imgSize / 2, Color(100, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        -- Title below image
        draw.SimpleText(self:GetPhotoTitle(), "wsMediumFont", w / 2, imgY + imgSize + 30, Color(255, 255, 255), TEXT_ALIGN_CENTER)

        -- Let child panels draw extra content (navigation arrows, counters, etc.)
        self:DrawExtraContent(w, h, imgSize, imgX, imgY)

        -- Close instructions
        draw.SimpleText(self:GetCloseText(), "wsSmallFont", w / 2, h - 40, Color(100, 100, 100), TEXT_ALIGN_CENTER)
    end

    function PANEL:OnKeyCodePressed(key)
        -- Let child handle first (e.g., arrow navigation)
        if self:OnExtraKeyPress(key) then return end

        for _, closeKey in ipairs(self.closeKeys) do
            if key == closeKey then
                self:Remove()
                return
            end
        end
    end

    function PANEL:OnMousePressed(mouseCode)
        if mouseCode == MOUSE_LEFT then
            self:Remove()
        end
    end

    function PANEL:OnRemove()
        self:OnCleanup()
    end

    vgui.Register("wsPhotoViewerBase", PANEL, "DPanel")
end
