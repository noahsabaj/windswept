--[[
    Photograph

    A photograph captured with a camera.
    Image data stored in server files (data/ws_photos/), item only holds reference ID.
    This prevents inventory sync overflow from large image data.
    Can be renamed ONCE by anyone who possesses it.
    Can be destroyed with confirmation.
]]--

ITEM.name = "Photograph"
ITEM.description = "A photograph."
ITEM.model = "models/props_c17/paper01.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Miscellaneous"

-- Photos don't stack
ITEM.noBusiness = true

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function ITEM:GetTitle()
    return self:GetData("title", "")
end

function ITEM:HasTitle()
    return self:GetData("titleSet", false)
end

function ITEM:GetPhotographer()
    return self:GetData("photographer", "Unknown")
end

function ITEM:GetTimestamp()
    return self:GetData("timestamp", 0)
end

function ITEM:GetPhotoID()
    return self:GetData("photoID", "")
end

-- Override GetName to show title if set
function ITEM:GetName()
    local title = self:GetTitle()
    if title and title ~= "" then
        return title
    end
    return self.name
end

-- Override GetDescription to show photographer and date
function ITEM:GetDescription()
    local photographer = self:GetPhotographer()
    local timestamp = self:GetTimestamp()

    if timestamp > 0 then
        local dateStr = os.date("%B %d, %Y", timestamp)
        return string.format("A photograph taken by %s on %s.", photographer, dateStr)
    end

    return self.description
end

-- Photos don't stack
function ITEM:CanStack(other)
    return false
end

-- ============================================================================
-- ITEM FUNCTIONS
-- ============================================================================

-- View: Opens the photo viewer
ITEM.functions.View = {
    name = "View",
    tip = "Look at this photograph.",
    icon = "icon16/picture.png",
    OnRun = function(item)
        return false  -- Don't consume
    end,
    OnClick = function(item)
        -- Request image data from server by photoID
        local photoID = item:GetData("photoID", "")
        if photoID == "" then
            LocalPlayer():ChatPrint("This photo has no image data.")
            return false
        end

        local title = item:GetTitle()
        if title == "" then title = "Untitled Photograph" end

        -- Store title keyed by photoID to avoid race conditions in multiplayer
        ws.photoRequestTitles = ws.photoRequestTitles or {}
        ws.photoRequestTitles[photoID] = title

        -- Request photo data from server
        ws.action.Send("wsPhotoRequest", nil, nil, function()
            net.WriteString(photoID)
        end)

        return false
    end,
    OnCanRun = function(item)
        return true
    end
}

-- Rename: Set a title for the photo (once only)
ITEM.functions.Rename = {
    name = "Name Photo",
    tip = "Give this photograph a title.",
    icon = "icon16/pencil.png",
    OnRun = function(item)
        return false  -- Don't consume, handled via net message
    end,
    OnClick = function(item)
        -- Open a text entry dialog on client
        Derma_StringRequest(
            "Name Photo",
            "Enter a title for this photograph (max 64 characters):",
            "",
            function(text)
                if text and text ~= "" then
                    -- Send to server
                    ws.action.Send("wsPhotoRename", item:GetID(), nil, function()
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
        -- Can only rename if not already named
        if item:HasTitle() then return false end
        -- Must be in inventory (not on ground as entity)
        if IsValid(item.entity) then return false end
        return true
    end
}

-- Destroy: Remove the photo with confirmation
ITEM.functions.Destroy = {
    name = "Destroy",
    tip = "Destroy this photograph permanently.",
    icon = "icon16/cross.png",
    OnRun = function(item)
        return false  -- Don't consume, handled via net message
    end,
    OnClick = function(item)
        -- Show confirmation dialog
        local confirmText = L("photoDestroyConfirm")

        Derma_Query(
            confirmText,
            "Destroy Photo",
            "Yes, Destroy",
            function()
                -- Send destroy request to server
                ws.action.Send("wsPhotoDestroy", item:GetID())
            end,
            "Cancel",
            function() end
        )

        return false
    end,
    OnCanRun = function(item)
        -- Can't destroy if on ground
        if IsValid(item.entity) then return false end
        return true
    end
}

-- Clean up the backing image file when the photo item is truly destroyed.
-- (Dropping to the ground keeps the same item instance, so OnRemoved does not
-- fire there and the photo is preserved.)
function ITEM:OnRemoved()
    if SERVER then
        ws.photo.DeletePhotoFile(self:GetData("photoID", ""))
    end
end

-- ============================================================================
-- CLIENT: Photo Viewer Panel (inherits wsPhotoViewerBase)
-- ============================================================================

if CLIENT then
    local PANEL = {}

    function PANEL:SetPhotoData(imageData, title)
        self.title = title or "Untitled Photograph"
        self.loading = false
        self.material, self.tempPath = ws.photo.LoadMaterial(imageData, "view_" .. SysTime())
    end

    function PANEL:SetLoading(title)
        self.title = title or "Loading..."
        self.loading = true
        self.material = nil
    end

    function PANEL:GetPhotoMat() return self.material end
    function PANEL:GetPhotoTitle() return self.title or "Untitled Photograph" end
    function PANEL:IsPhotoLoading() return self.loading end

    function PANEL:OnCleanup()
        ws.photo.CleanupTempFile(self.tempPath)
        ws.gui.photoViewer = nil
    end

    vgui.Register("wsPhotoViewer", PANEL, "wsPhotoViewerBase")

    -- ========================================================================
    -- CLIENT NETWORKING
    -- ========================================================================

    -- Receive photo data from server (raw JPEG binary)
    net.Receive("wsPhotoData", function()
        local photoID = net.ReadString()
        -- Clamp length to the server's hard cap before allocating (defense-in-depth). (sc-photography-8)
        local dataLen = math.min(net.ReadUInt(32), ws.photo.MAX_PHOTO_BYTES)
        local imageData = net.ReadData(dataLen)

        -- Fire hook for album viewer cache (and any other listeners)
        hook.Run("wsPhotoDataReceived", photoID, imageData)

        -- Look up title from our request table (avoids race conditions)
        ws.photoRequestTitles = ws.photoRequestTitles or {}
        local title = ws.photoRequestTitles[photoID] or "Untitled Photograph"

        -- Only open photo viewer if this was a direct view request (has title in queue)
        -- Album requests don't add to photoRequestTitles, so they won't open the viewer
        if ws.photoRequestTitles[photoID] then
            ws.photoRequestTitles[photoID] = nil  -- Clean up

            if IsValid(ws.gui.photoViewer) then
                ws.gui.photoViewer:SetPhotoData(imageData, title)
            else
                ws.gui.photoViewer = vgui.Create("wsPhotoViewer")
                ws.gui.photoViewer:SetPhotoData(imageData, title)
            end
        end
    end)

    -- Receive photo from ground viewing (raw JPEG binary)
    net.Receive("wsPhotoViewFromGround", function()
        -- Clamp length to the server's hard cap before allocating (defense-in-depth). (sc-photography-8)
        local dataLen = math.min(net.ReadUInt(32), ws.photo.MAX_PHOTO_BYTES)
        local imageData = net.ReadData(dataLen)
        local title = net.ReadString()

        if IsValid(ws.gui.photoViewer) then
            ws.gui.photoViewer:Remove()
        end

        ws.gui.photoViewer = vgui.Create("wsPhotoViewer")
        ws.gui.photoViewer:SetPhotoData(imageData, title)
    end)
end

-- ============================================================================
-- SERVER: Networking
-- ============================================================================

if SERVER then
    -- Client requests photo data by ID (sends raw JPEG binary).
    -- Not an item= action: the client sends a String photoID with custom access
    -- (CanAccessPhoto), so we read it via read() and gate it via onValidate().
    ws.action.Register("wsPhotoRequest", {
        -- Light per-client rate limit so an owner can't spam disk reads + ~60KB sends. (sc-photography-7)
        rateLimit = 0.5,
        read = function() return net.ReadString() end,
        -- Only serve photos the client owns or was legitimately shown (album browse
        -- / ground view grant). Prevents fetching arbitrary photos by ID.
        onValidate = function(client, ctx)
            return ws.photo.CanAccessPhoto(client, ctx.data)
        end,
        run = function(client, ctx)
            local photoID = ctx.data

            local imageData = ws.photo.ReadPhotoFile(photoID)

            if imageData then
                net.Start("wsPhotoData")
                    net.WriteString(photoID)
                    net.WriteUInt(#imageData, 32)
                    net.WriteData(imageData, #imageData)
                net.Send(client)
            end
        end
    })

    -- Allow renaming photos held in main inventory or one level of owned bags
    -- (e.g. inside an album), consistent with viewing/access. (sc-photography-4)
    ws.action.Register("wsPhotoRename", {
        item = "photo",
        read = function() return net.ReadString() end,
        run = function(client, ctx)
            local item = ctx.item
            local title = ctx.data

            -- Reject implausibly long titles outright (truncated to 64 below anyway). (sc-photography-11)
            if #title > 256 then return end

            -- Check if already named
            if item:GetData("titleSet", false) then
                client:NotifyLocalized("photoAlreadyNamed")
                return
            end

            -- Set the title
            title = string.sub(title, 1, 64)
            item:SetData("title", title)
            item:SetData("titleSet", true)

            client:NotifyLocalized("photoRenamed", title)
        end
    })

    -- Allow destroying photos held in main inventory or one level of owned bags
    -- (e.g. inside an album), consistent with viewing/access. (sc-photography-4)
    ws.action.Register("wsPhotoDestroy", {
        item = "photo",
        run = function(client, ctx)
            local item = ctx.item

            -- Delete the photo file
            local photoID = item:GetData("photoID", "")
            if photoID ~= "" then
                ws.photo.DeletePhotoFile(photoID)
            end

            -- Destroy the item
            item:Remove()
            client:NotifyLocalized("photoDestroyed")
        end
    })
end

-- ============================================================================
-- ENTITY USE (View from ground)
-- ============================================================================

function ITEM:OnEntityCreated(entity)
    if SERVER then
        entity:SetUseType(SIMPLE_USE)
    end
end

hook.Add("PlayerUse", "wsPhotoGroundView", function(client, entity)
    if not IsValid(entity) then return end

    local item = entity.wsItem
    if not item then return end
    if item.uniqueID ~= "photo" then return end

    if SERVER then
        local photoID = item:GetData("photoID", "")
        local title = item:GetData("title", "")
        if title == "" then title = "Untitled Photograph" end

        local imageData = ws.photo.ReadPhotoFile(photoID) or ""

        net.Start("wsPhotoViewFromGround")
            net.WriteUInt(#imageData, 32)
            net.WriteData(imageData, #imageData)
            net.WriteString(title)
        net.Send(client)
    end
end)
