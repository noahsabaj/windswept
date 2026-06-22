--[[
    State, door-type/model-pattern config tables, and shared pure helpers
    (type detection, door-state checks, eye-trace door lookup). Loaded first;
    every other fragment runtime-references the ws.doors.* it defines here.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}
ws.doors.frames = ws.doors.frames or {}
ws.doors.dirty = ws.doors.dirty or false  -- (sc-doors-access-9)

-- Damage-source registry: a schema registers which weapon classes can damage doors and
-- how, so this generic engine carries no game-specific weapon class names. (layer-doors)
--   RegisterDamageSource(class, { fist = true })  -> 1 HP, gated by the type's fistDamageable
--   RegisterDamageSource(class, { ram  = true })  -> damage scaled by the type's ramResistance
ws.doors.damageSources = ws.doors.damageSources or {}

function ws.doors.RegisterDamageSource(class, opts)
    ws.doors.damageSources[class] = opts or {}
end

-- The active-weapon class that reveals empty door frames (a schema's door-install tool);
-- left as-is so the schema can set ws.doors.installToolClass. nil = no frame pulse.

-- Door type configurations (for health/damage, not models)
ws.doors.typeConfig = {
    wood = {
        maxHealth = 100,
        ramResistance = 1.0,
        fistDamageable = true,
        material = "wood"
    },
    metal = {
        maxHealth = 250,
        ramResistance = 0.4,
        fistDamageable = false,
        material = "metal"
    },
    gate = {
        maxHealth = 175,
        ramResistance = 0.65,
        fistDamageable = false,
        material = "metal"
    }
}

-- Model path patterns to detect door types
ws.doors.modelPatterns = {
    wood = {
        "door01",
        "door02",
        "wooddoor",
        "door_wood",
        "apartment_door"
    },
    metal = {
        "door03",
        "metaldoor",
        "door_metal",
        "security",
        "industrial"
    },
    gate = {
        "gate",
        "fence",
        "barrier"
    }
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Detect door type from model path
function ws.doors.DetectTypeFromModel(model)
    model = string.lower(model or "")

    for doorType, patterns in pairs(ws.doors.modelPatterns) do
        for _, pattern in ipairs(patterns) do
            if string.find(model, pattern) then
                return doorType
            end
        end
    end

    return "wood"  -- Default to wood
end

-- Check if an entity is a valid door
function ws.doors.IsDoor(ent)
    if not IsValid(ent) then return false end
    return ent:IsDoor()
end

-- Check if a door is fully closed (not open or in motion)
-- prop_door_rotating uses m_eDoorState: 0=closed, 1=opening, 2=open, 3=closing
function ws.doors.IsDoorClosed(door)
    if not IsValid(door) then return false end

    local doorState = door:GetInternalVariable("m_eDoorState")
    return doorState == 0  -- DOOR_STATE_CLOSED
end

-- Check if a door is open or ajar (not fully closed)
function ws.doors.IsDoorOpen(door)
    return not ws.doors.IsDoorClosed(door)
end

-- Trace from a player's eyes to find a Windswept-managed door within maxDist
-- Used by key, keyring, lock, lockpick, lockbreaker SWEPs
function ws.doors.GetTargetDoor(owner, maxDist)
    if not IsValid(owner) then return nil end

    local tr = util.TraceLine({
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * maxDist,
        filter = owner
    })

    local ent = tr.Entity
    if IsValid(ent) and ent.wsIsWindsweptDoor then
        return ent
    end

    return nil
end
