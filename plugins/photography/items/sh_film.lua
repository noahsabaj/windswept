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
        local maxShots = item.maxShots

        -- Draw shot count in corner
        local text = string.format("%d/%d", shots, maxShots)

        surface.SetFont("wsSmallFont")
        local textW, textH = surface.GetTextSize(text)

        -- Background
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(w - textW - 8, h - textH - 4, textW + 6, textH + 2)

        -- Text color based on shots remaining
        local color
        if shots >= maxShots then
            color = Color(50, 200, 50)      -- GREEN (full)
        elseif shots >= maxShots / 2 then
            color = Color(200, 200, 50)     -- YELLOW
        elseif shots > 0 then
            color = Color(200, 100, 50)     -- ORANGE
        else
            color = Color(150, 50, 50)      -- RED (empty)
        end

        surface.SetTextColor(color)
        surface.SetTextPos(w - textW - 5, h - textH - 3)
        surface.DrawText(text)
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
