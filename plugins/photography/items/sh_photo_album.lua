--[[
    Photo Album

    A container that holds up to 50 photographs.
    Only photo items can be stored in this album.
    Features a book-style viewer (two photos per spread).
    Can be renamed multiple times.
]]--

ITEM.name = "Photo Album"
ITEM.description = "A binder for storing and organizing photographs."
ITEM.model = "models/props_lab/binderblue.mdl"
ITEM.category = "Storage"
ITEM.base = "base_container"
ITEM.width = 1
ITEM.height = 1
ITEM.invWidth = 10
ITEM.invHeight = 5

ITEM.inventoryFlag = "isPhotoAlbum"
ITEM.allowedItemType = "photo"
ITEM.allowedItemNotify = "albumOnlyPhotos"
ITEM.viewSuffix = " - Photos"

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function ITEM:GetAlbumTitle()
    return self:GetData("title", "")
end

function ITEM:HasTitle()
    local title = self:GetAlbumTitle()
    return title and title ~= ""
end

function ITEM:GetName()
    if self:HasTitle() then
        return self:GetAlbumTitle()
    end
    return self.name
end

function ITEM:GetPhotos()
    local inv = self:GetInventory()
    if not inv then return {} end

    local photos = inv:GetItemsByUniqueID("photo", false)

    table.sort(photos, function(a, b)
        return (a:GetData("timestamp") or 0) < (b:GetData("timestamp") or 0)
    end)

    return photos
end

-- ============================================================================
-- ITEM FUNCTIONS
-- ============================================================================

-- Browse album in book-style viewer
ITEM.functions.Browse = {
    name = "Browse",
    tip = "Flip through the photographs in this album.",
    icon = "icon16/book_open.png",
    OnRun = function(item)
        return false
    end,
    OnClick = function(item)
        ws.action.Send("wsPhotoAlbumView", item:GetID())

        return false
    end,
    OnCanRun = function(item)
        return item:GetData("id") ~= nil
    end
}

-- Override View with custom name
ITEM.functions.View = {
    name = "Manage Photos",
    tip = "Add or remove photographs from the album.",
    icon = "icon16/folder.png",
    OnClick = ws.constants.OpenContainerPanel,
    OnCanRun = ws.constants.CanOpenContainerPanel
}

-- Rename album (can rename multiple times)
ITEM.functions.Rename = {
    name = "Rename Album",
    tip = "Change the name of this album.",
    icon = "icon16/pencil.png",
    OnRun = function(item, data)
        return false
    end,
    OnClick = function(item)
        local currentTitle = item:GetAlbumTitle()

        Derma_StringRequest(
            "Rename Album",
            "Enter a name for this album (max 64 characters):",
            currentTitle,
            function(text)
                if text then
                    ws.action.Send("wsPhotoAlbumRename", item:GetID(), nil, function()
                        net.WriteString(string.sub(text, 1, 64))
                    end)
                end
            end,
            function() end,
            "Confirm",
            "Cancel"
        )
        return false
    end,
    OnCanRun = function(item)
        return not IsValid(item.entity)
    end
}

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOverExtra(w, h)
        local photos = self:GetPhotos()
        local count = #photos

        if count > 0 then
            local text = tostring(count)
            surface.SetFont("wsSmallFont")
            local textW, textH = surface.GetTextSize(text)

            surface.SetDrawColor(50, 100, 150, 200)
            surface.DrawRect(w - textW - 8, 2, textW + 6, textH + 2)

            surface.SetTextColor(255, 255, 255)
            surface.SetTextPos(w - textW - 5, 3)
            surface.DrawText(text)
        end
    end

    function ITEM:PopulateTooltip(tooltip)
        local photos = self:GetPhotos()

        local bgColor = #photos >= 45 and Color(150, 100, 50) or (#photos > 0 and Color(50, 100, 100) or Color(100, 100, 100))
        ws.constants.AddTooltipRow(tooltip, "photos", string.format("Photos: %d / 50", #photos), bgColor)
    end
end

-- ============================================================================
-- SERVER: Networking
-- ============================================================================

if SERVER then
    -- Albums can legitimately live inside an owned bag, so resolve via
    -- VerifyItemAccessible (main inventory OR an owned container) rather than the
    -- main-inventory-only VerifyOwnership. (sc-photography-5)
    ws.action.Register("wsPhotoAlbumRename", {
        item = "photo_album",
        read = function() return net.ReadString() end,
        run = function(client, ctx)
            local item = ctx.item
            local title = string.sub(ctx.data, 1, 64)

            item:SetData("title", title)

            client:NotifyLocalized("albumRenamed", title)
        end
    })

    -- Accessible (main inventory OR owned bag), matching Rename. (sc-photography-5)
    ws.action.Register("wsPhotoAlbumView", {
        item = "photo_album",
        run = function(client, ctx)
            local item = ctx.item

            local photos = item:GetPhotos()
            local title = item:GetName()

            -- Grant short-lived access so the client can fetch these photos' images.
            local ids = {}
            for _, photo in ipairs(photos) do
                ids[#ids + 1] = photo:GetData("photoID", "")
            end
            ws.photo.GrantPhotoAccess(client, ids)

            net.Start("wsPhotoAlbumViewData")
                net.WriteString(title)
                net.WriteUInt(#photos, 8)
                for _, photo in ipairs(photos) do
                    net.WriteString(photo:GetData("photoID", ""))
                    net.WriteString(photo:GetData("title", ""))
                end
            net.Send(client)
        end
    })
end

-- ============================================================================
-- CLIENT: Album Viewer (inherits wsPhotoViewerBase)
-- ============================================================================

if CLIENT then
    ws.albumPhotoCache = ws.albumPhotoCache or {}
    ws.albumPhotoLoading = ws.albumPhotoLoading or {}

    local PANEL = {}

    function PANEL:Init()
        self.BaseClass.Init(self)

        self.albumTitle = "Photo Album"
        self.photoMetadata = {}
        self.currentIndex = 1
        self.totalPhotos = 0
    end

    function PANEL:SetAlbumMetadata(title, metadata)
        self.albumTitle = title or "Photo Album"
        self.photoMetadata = metadata or {}
        self.totalPhotos = #self.photoMetadata
        self.currentIndex = 1

        self:RequestCurrentPhoto()
    end

    function PANEL:RequestCurrentPhoto()
        local metadata = self.photoMetadata[self.currentIndex]
        if metadata and metadata.photoID and metadata.photoID ~= "" then
            self:RequestPhoto(metadata.photoID)
        end
    end

    function PANEL:RequestPhoto(photoID)
        if ws.albumPhotoCache[photoID] then return end
        if ws.albumPhotoLoading[photoID] then return end

        ws.albumPhotoLoading[photoID] = true

        ws.action.Send("wsPhotoRequest", nil, nil, function()
            net.WriteString(photoID)
        end)
    end

    function PANEL:GoToPhoto(index)
        if index < 1 or index > self.totalPhotos then return end

        self.currentIndex = index
        self:RequestCurrentPhoto()
    end

    function PANEL:GetPhotoMat()
        local metadata = self.photoMetadata[self.currentIndex]
        if not metadata or not metadata.photoID or metadata.photoID == "" then
            return nil
        end

        local cached = ws.albumPhotoCache[metadata.photoID]
        if cached and cached ~= false and not cached:IsError() then
            return cached
        end

        return nil
    end

    function PANEL:GetPhotoTitle()
        local metadata = self.photoMetadata[self.currentIndex]
        if metadata then
            local title = metadata.title or ""
            if title == "" then title = "Untitled" end
            return title
        end
        return ""
    end

    function PANEL:IsPhotoLoading()
        local metadata = self.photoMetadata[self.currentIndex]
        if metadata and metadata.photoID then
            return ws.albumPhotoLoading[metadata.photoID] == true
        end
        return false
    end

    function PANEL:GetEmptyText()
        if self.totalPhotos == 0 then
            return "Album Empty"
        end
        return "No Image"
    end

    function PANEL:GetCloseText()
        return "Arrow keys to navigate | WASD or LMB to close"
    end

    function PANEL:DrawExtraContent(w, h, imgSize, imgX, imgY)
        draw.SimpleText(self.albumTitle, "wsMediumFont", w / 2, 30, ws.constants.COLOR_UI_NEUTRAL, TEXT_ALIGN_CENTER)

        local arrowY = h / 2
        local arrowColor = Color(255, 255, 255, 150)
        local arrowDisabledColor = Color(100, 100, 100, 80)

        local leftColor = self.currentIndex > 1 and arrowColor or arrowDisabledColor
        draw.SimpleText("\xE2\x97\x84", "wsMediumFont", imgX - 60, arrowY, leftColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local rightColor = self.currentIndex < self.totalPhotos and arrowColor or arrowDisabledColor
        draw.SimpleText("\xE2\x96\xBA", "wsMediumFont", imgX + imgSize + 60, arrowY, rightColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if self.totalPhotos > 0 then
            draw.SimpleText(string.format("Photo %d of %d", self.currentIndex, self.totalPhotos), "wsSmallFont", w / 2, imgY + imgSize + 60, Color(150, 150, 150), TEXT_ALIGN_CENTER)
        end
    end

    function PANEL:OnExtraKeyPress(key)
        if key == KEY_LEFT then
            self:GoToPhoto(self.currentIndex - 1)
            return true
        elseif key == KEY_RIGHT then
            self:GoToPhoto(self.currentIndex + 1)
            return true
        end
        return false
    end

    function PANEL:OnCleanup()
        for photoID, _ in pairs(ws.albumPhotoCache) do
            ws.photo.CleanupTempFile("wsphoto_album_" .. photoID .. ".jpg")
        end

        ws.albumPhotoCache = {}
        ws.albumPhotoLoading = {}
        ws.gui.photoAlbumViewer = nil
    end

    vgui.Register("wsPhotoAlbumViewer", PANEL, "wsPhotoViewerBase")

    -- Receive album metadata from server
    net.Receive("wsPhotoAlbumViewData", function()
        local title = net.ReadString()
        local photoCount = net.ReadUInt(8)

        local metadata = {}
        for i = 1, photoCount do
            local photoID = net.ReadString()
            local photoTitle = net.ReadString()
            table.insert(metadata, {
                photoID = photoID,
                title = photoTitle
            })
        end

        if IsValid(ws.gui.photoAlbumViewer) then
            ws.gui.photoAlbumViewer:Remove()
        end

        ws.gui.photoAlbumViewer = vgui.Create("wsPhotoAlbumViewer")
        ws.gui.photoAlbumViewer:SetAlbumMetadata(title, metadata)
    end)

    -- Hook into existing wsPhotoData to update album cache
    hook.Add("wsPhotoDataReceived", "wsPhotoAlbumCache", function(photoID, imageData)
        ws.albumPhotoLoading[photoID] = nil

        if imageData and imageData ~= "" then
            local mat = ws.photo.LoadMaterial(imageData, "album_" .. photoID)
            if mat then
                ws.albumPhotoCache[photoID] = mat
            else
                ws.albumPhotoCache[photoID] = false
            end
        else
            ws.albumPhotoCache[photoID] = false
        end
    end)
end

-- ============================================================================
-- ENTITY USE (View from ground)
-- ============================================================================

if SERVER then
    hook.Add("PlayerUse", "wsPhotoAlbumGroundView", function(client, entity)
        if not IsValid(entity) then return end

        local item = entity.wsItem
        if not item then return end
        if item.uniqueID ~= "photo_album" then return end

        local photos = item:GetPhotos()
        local title = item:GetName()

        -- Proximity ground view: grant short-lived access to fetch these images.
        local ids = {}
        for _, photo in ipairs(photos) do
            ids[#ids + 1] = photo:GetData("photoID", "")
        end
        ws.photo.GrantPhotoAccess(client, ids)

        net.Start("wsPhotoAlbumViewFromGround")
            net.WriteString(title)
            net.WriteUInt(#photos, 8)
            for _, photo in ipairs(photos) do
                net.WriteString(photo:GetData("photoID", ""))
                net.WriteString(photo:GetData("title", ""))
            end
        net.Send(client)
    end)
end

if CLIENT then
    net.Receive("wsPhotoAlbumViewFromGround", function()
        local title = net.ReadString()
        local photoCount = net.ReadUInt(8)

        local metadata = {}
        for i = 1, photoCount do
            local photoID = net.ReadString()
            local photoTitle = net.ReadString()
            table.insert(metadata, {
                photoID = photoID,
                title = photoTitle
            })
        end

        if IsValid(ws.gui.photoAlbumViewer) then
            ws.gui.photoAlbumViewer:Remove()
        end

        ws.gui.photoAlbumViewer = vgui.Create("wsPhotoAlbumViewer")
        ws.gui.photoAlbumViewer:SetAlbumMetadata(title, metadata)
    end)
end
