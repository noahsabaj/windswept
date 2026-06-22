--[[
    Gavel SWEP

    A wooden gavel prop for roleplay.
    - Primary: Gavel slam sound (makes noise)
]]--

AddCSLuaFile()

SWEP.Base = "base_windswept_swep"

if CLIENT then
    SWEP.PrintName = "Gavel"
    SWEP.Slot = 0
    SWEP.SlotPos = 2
end

SWEP.Instructions = "Primary: Slam gavel to make noise."
SWEP.Purpose = "Making authoritative noise."

SWEP.ViewModel = ""
SWEP.WorldModel = Model("models/judge gavels & more/judge_gavel.mdl")
SWEP.UseHands = false
SWEP.HoldType = "melee"

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "NextIdle")
end

function SWEP:CanDeploy()
    return true
end

-- Primary attack: Gavel slam (anyone can do this)
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1)
    self:SetNextSecondaryFire(CurTime() + 0.5)

    -- Play slam sound
    if SERVER then
        self:EmitSound("physics/wood/wood_crate_impact_hard2.wav", 100, math.random(95, 105))
    end
end

function SWEP:Reload()
    -- Do nothing
end

if CLIENT then
    function SWEP:DrawWorldModel()
        ws.constants.DrawWorldModelBone(self, {3, 3, -5}, {{"Forward", -90}, {"Up", 180}}, true)
    end

    -- Simple crosshair
    function SWEP:DoDrawCrosshair(x, y)
        local size = 8
        surface.SetDrawColor(255, 255, 255, 200)
        surface.DrawLine(x - size, y, x + size, y)
        surface.DrawLine(x, y - size, x, y + size)
        return true
    end
end
