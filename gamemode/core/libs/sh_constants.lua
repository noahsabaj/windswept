--[[
    Windswept Framework - Centralized Constants (values + shared/server helpers)

    Framework infrastructure (used by the documents/photography/power/restraints plugins),
    so it lives in core/libs and loads before plugins. Client UI / derma / SWEP-render
    helpers live in cl_constants.lua (same ws.constants namespace). A schema may override
    individual values after load.
    Import with: local C = ws.constants (after this file loads)

    NOTE: Windswept already defines ws.currency.MAX_STACK (100), ws.currency.CENTS_PER_DOLLAR (100),
    ws.currency.CASH_ITEM ("cash"), ws.currency.COINS_ITEM ("coins")
]]--

ws.constants = ws.constants or {}
local C = ws.constants

-- =============================================================================
-- UI COLORS
-- =============================================================================
-- Anti-metagaming: all UI uses a neutral gray (the framework has no factions/teams to color).

C.COLOR_UI_NEUTRAL = Color(200, 200, 200)       -- Standard text/UI color
C.COLOR_UI_NEUTRAL_ALPHA = Color(200, 200, 200, 200)  -- With transparency
C.COLOR_OUTLINE = Color(0, 0, 0)                -- Text outline color
C.COLOR_PROGRESS_BG = Color(50, 50, 50, 200)    -- Progress bar background
C.COLOR_PROGRESS_FG = Color(200, 200, 200, 255) -- Progress bar foreground

-- =============================================================================
-- INTERACTION RANGES (squared, for use with DistToSqr)
-- =============================================================================
-- Forward to the framework's canonical access layer (single source of truth). (layer-3)
C.RANGE_INTERACTION = ws.access.RANGE_INTERACTION            -- 10000 - standard player-to-player
C.RANGE_INTERACTION_CLOSE = ws.access.RANGE_INTERACTION_CLOSE -- 9216 - close range (drag, ziptie)
C.RANGE_SOUND_FAR = 1000 * 1000      -- 1000000 - Far sound audibility
C.RANGE_EAVESDROP_BASE = 400         -- Base eavesdrop range (scaled by volume * amplitude)

-- Linear distances (for reference/documentation)
C.DISTANCE_INTERACTION = 100         -- units
C.DISTANCE_INTERACTION_CLOSE = 96    -- units

-- =============================================================================
-- BATTERY SYSTEM
-- =============================================================================
-- "up" = units of power. A full battery has 100up.

C.BATTERY_FULL_CHARGE = 100          -- Full battery in up

-- Drain rates (up per second). Flashlight: 100up/1200s = 20min; Lantern: 100up/600s = 10min.
C.DRAIN_FLASHLIGHT = 100 / 1200      -- ~0.083 up/sec
C.DRAIN_LANTERN = 100 / 600          -- ~0.167 up/sec

-- =============================================================================
-- ITEM STACK LIMITS
-- =============================================================================
-- Currency uses ws.currency.MAX_STACK (100) from Windswept

C.STACK_KEY_BLANKS = 10
C.STACK_LOCK_BLANKS = 5
C.STACK_MATERIALS = 20               -- Wood planks, metal sheets

-- =============================================================================
-- TIMING (seconds)
-- =============================================================================

C.ITEM_PICKUP_HOLD_TIME = 0.5        -- Windswept default for holding E to pickup
C.DOOR_BREACH_COOLDOWN = 2           -- Cooldown between ram hits

-- =============================================================================
-- HELPER FUNCTIONS (shared / server)
-- =============================================================================

-- Range helpers forward to the framework's ws.access (single source of truth). The schema
-- previously duplicated identical bodies; ws.access additionally guards IsValid. (layer-3)
C.WithinRange = ws.access.WithinRange
C.CanInteract = ws.access.CanInteract
C.CanInteractClose = ws.access.CanInteractClose

-- Character/inventory and item ownership/accessibility checks forward to ws.access (the
-- framework's canonical, single-source-of-truth trust layer). (layer-3)
C.GetCharacterInventory = ws.access.GetCharacterInventory

if SERVER then
    C.VerifyItemOwnership = ws.access.VerifyItemOwnership
    C.VerifyItemAccessible = ws.access.VerifyItemAccessible
end

-- Find best toolkit in a player's inventory (returns hasToolkit, toolkitItem)
function C.FindBestToolkit(client)
    if not IsValid(client) then return false, nil end

    local character, inventory = C.GetCharacterInventory(client)
    if not character or not inventory then return false, nil end

    local bestToolkit = nil
    local bestSpeed = 0

    for _, item in pairs(inventory:GetItems()) do
        if item.uniqueID and string.find(item.uniqueID, "toolkit") then
            local speed = item.installSpeed or 1
            if speed > bestSpeed then
                bestSpeed = speed
                bestToolkit = item
            end
        end
    end

    return bestToolkit ~= nil, bestToolkit
end

-- Shared SWEP cancel action: check state, run cleanup, play cancel sound (SERVER only)
function C.CancelSWEPAction(weapon, checkFn, cleanupFn, soundVolume)
    if not checkFn() then return end
    cleanupFn()
    local owner = weapon:GetOwner()
    if IsValid(owner) and SERVER then
        owner:EmitSound("buttons/button10.wav", soundVolume or 50)
    end
end
