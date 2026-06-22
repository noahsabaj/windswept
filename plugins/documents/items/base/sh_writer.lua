--[[
    Base Writer

    Base class for handheld writing tools (pens, pencils).
    Provides shared resource management (ink/lead), UI rendering, and description.

    Child items should set:
        ITEM.resourceName = "ink" or "lead"
        ITEM.resourceNameDisplay = "Ink" or "Lead"
        ITEM.maxResource = 1000 (capacity)
        ITEM.strokeColor = {r, g, b} (color for writing/signatures)

    Optional:
        ITEM.hasEraser = true/false (for pencils)
        ITEM.canRefill = true/false (for pens with ink cartridge)
]]--

ITEM.name = "Writing Tool"
ITEM.description = "A writing tool."
ITEM.model = "models/props_lab/clipboard.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"

-- Resource defaults (override in child items)
ITEM.resourceName = "ink"
ITEM.resourceNameDisplay = "Ink"
ITEM.maxResource = 1000
ITEM.strokeColor = {200, 200, 200}

-- Optional features
ITEM.hasEraser = false
ITEM.canRefill = false

-- ============================================================================
-- RESOURCE MANAGEMENT
-- ============================================================================

function ITEM:GetResource()
    return self:GetData(self.resourceName, self.maxResource)
end

function ITEM:HasResource()
    return self:GetResource() > 0
end

function ITEM:UseResource(amount)
    local current = self:GetResource()
    local newAmount = math.max(0, current - amount)
    self:SetData(self.resourceName, newAmount)
    return newAmount
end

function ITEM:RefillResource(amount)
    local current = self:GetResource()
    local newAmount = math.min(self.maxResource, current + amount)
    self:SetData(self.resourceName, newAmount)
    return newAmount
end

function ITEM:GetResourcePercent()
    return self:GetResource() / self.maxResource
end

function ITEM:GetStrokeColor()
    return self.strokeColor
end

-- Semantic aliases: pens use "ink", pencils use "lead"
function ITEM:GetInk()
    return self:GetResource()
end

function ITEM:HasInk()
    return self:HasResource()
end

function ITEM:UseInk(amount)
    return self:UseResource(amount)
end

function ITEM:Refill(amount)
    return self:RefillResource(amount)
end

function ITEM:GetInkColor()
    return self:GetStrokeColor()
end

function ITEM:GetLead()
    return self:GetResource()
end

function ITEM:HasLead()
    return self:HasResource()
end

function ITEM:UseLead(amount)
    return self:UseResource(amount)
end

function ITEM:CanErase()
    return self.hasEraser == true
end

-- ============================================================================
-- DESCRIPTION
-- ============================================================================

function ITEM:GetDescription()
    local resource = self:GetResource()
    local desc = self.description .. "\n"

    if resource == 0 then
        desc = desc .. self.resourceNameDisplay .. ": EMPTY"
        if self.canRefill then
            desc = desc .. " (needs refill)"
        end
    else
        desc = desc .. string.format("%s: %d/%d characters",
            self.resourceNameDisplay, resource, self.maxResource)
    end

    if self.hasEraser then
        desc = desc .. "\n\nCan erase pencil writing."
    end

    return desc
end

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        local percent = item:GetData(item.resourceName, item.maxResource) / item.maxResource
        local color = item:GetStrokeColor()
        ws.constants.DrawDurabilityBar(w, h, percent, Color(color[1], color[2], color[3], 255), "thin")

        if item.hasEraser then
            surface.SetDrawColor(255, 150, 180, 200)
            surface.DrawRect(6, 6, 6, 6)
        end
    end
end

-- ============================================================================
-- INK CARTRIDGE REFILL (for pens)
-- ============================================================================

ITEM.functions.combine = {
    OnRun = function(item, data)
        -- Only pens can be refilled
        if not item.canRefill then
            return false
        end

        local targetItem = ws.item.instances[data[1]]
        if not targetItem then return false end

        -- Only allow ink cartridge
        if targetItem.uniqueID ~= "ink_cartridge" then
            return false
        end

        -- Refill pen
        local current = item:GetResource()
        if current >= item.maxResource then
            if item.player then
                item.player:NotifyLocalized("penAlreadyFull")
            end
            return false
        end

        -- Refill and consume cartridge
        item:RefillResource(item.maxResource)
        targetItem:Remove()

        if item.player then
            item.player:NotifyLocalized("penRefilled")
        end

        return false
    end,
    OnCanRun = function(item, data)
        if not item.canRefill then return false end

        local targetItem = ws.item.instances[data[1]]
        if not targetItem then return false end
        return targetItem.uniqueID == "ink_cartridge"
    end
}
