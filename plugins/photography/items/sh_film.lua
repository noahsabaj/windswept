--[[
    Film Pack

    A pack of 10 instant photos for use in a camera.
    Once loaded into a camera, cannot be ejected until all shots are used.
]]--

ITEM.name = "Film Pack"
ITEM.description = "A pack of 10 instant photos for use in a camera."
ITEM.model = "models/props_lab/box01a.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"

-- Default shots per pack
ITEM.maxShots = 10

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function ITEM:GetShots()
    return self:GetData("shots", self.maxShots)
end

function ITEM:SetShots(shots)
    self:SetData("shots", math.Clamp(shots, 0, self.maxShots))
end

function ITEM:IsFull()
    return self:GetShots() >= self.maxShots
end

function ITEM:IsEmpty()
    return self:GetShots() <= 0
end

-- ============================================================================
-- STACKING
-- ============================================================================

-- Only full packs can stack together
function ITEM:CanStack(other)
    if self.uniqueID ~= other.uniqueID then return false end

    -- Only stack if both are full (10 shots)
    if not self:IsFull() then return false end
    if not other:IsFull() then return false end

    return true
end

-- ============================================================================
-- CLIENT VISUALS
-- ============================================================================

if CLIENT then
    function ITEM:PaintOver(item, w, h)
        local shots = item:GetData("shots", item.maxShots)
        local fraction = shots / item.maxShots

        -- The standard consumable fullness bar (same as batteries). The old "10/10"
        -- text clipped off a 1x1 icon and read as "0/10"; exact counts live in the
        -- hover tooltip. (#93)
        ws.constants.DrawDurabilityBar(w, h, fraction, ws.constants.GetChargeColor(fraction * 100))
    end

    function ITEM:PopulateTooltip(tooltip)
        local shots = self:GetData("shots", self.maxShots)

        local shotRow = tooltip:AddRow("shots")
        shotRow:SetText(string.format("Shots: %d / %d", shots, self.maxShots))

        if shots >= self.maxShots then
            shotRow:SetBackgroundColor(Color(50, 100, 50))
        elseif shots > 0 then
            shotRow:SetBackgroundColor(Color(100, 100, 50))
        else
            shotRow:SetBackgroundColor(Color(100, 50, 50))
        end

        shotRow:SizeToContents()
    end
end
