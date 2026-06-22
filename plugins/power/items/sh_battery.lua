--[[
    Universal Battery

    A rechargeable power cell that can be loaded into devices.
    Charge: 0-100up (units of power)

    Stacking: batteries do NOT stack - each battery (regardless of charge level)
    occupies its own slot, since charge is per-instance data. (sc-items-currency-battery-9)
]]--

ITEM.name = "Battery"
ITEM.description = "A rechargeable power cell."
ITEM.model = "models/items/battery.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Equipment"
ITEM.noBusiness = true  -- Can't spawn from business menu

-- Default to full charge when created
function ITEM:OnInstanced(invID, x, y)
    if self:GetData("charge") == nil then
        self:SetData("charge", 100)
    end
end

-- Batteries don't stack - each battery takes 1 slot
function ITEM:CanStack(other)
    return false
end

-- CLIENT: Visual charge bar and tooltip
if CLIENT then
    function ITEM:PaintOver(item, w, h)
        local charge = item:GetData("charge", 100)

        -- Background bar
        surface.SetDrawColor(30, 30, 30, 200)
        surface.DrawRect(4, h - 12, w - 8, 8)

        -- Charge fill with color based on level
        local chargeWidth = ((w - 8) / 100) * charge
        local color
        if charge > 50 then
            color = Color(50, 200, 50)  -- Green
        elseif charge > 25 then
            color = Color(200, 200, 50)  -- Yellow
        else
            color = Color(200, 50, 50)  -- Red
        end

        surface.SetDrawColor(color)
        surface.DrawRect(4, h - 12, chargeWidth, 8)
    end

    function ITEM:PopulateTooltip(tooltip)
        local charge = self:GetData("charge", 100)

        local chargeRow = tooltip:AddRow("charge")
        chargeRow:SetText(string.format("Charge: %dup / 100up", charge))

        -- Color based on charge level
        if charge <= 0 then
            chargeRow:SetBackgroundColor(Color(100, 100, 100))  -- Gray for empty
        elseif charge <= 25 then
            chargeRow:SetBackgroundColor(Color(150, 50, 50))  -- Red for low
        elseif charge <= 50 then
            chargeRow:SetBackgroundColor(Color(150, 100, 50))  -- Orange for medium
        else
            chargeRow:SetBackgroundColor(Color(50, 100, 50))  -- Green for good
        end

        chargeRow:SizeToContents()
    end
end
