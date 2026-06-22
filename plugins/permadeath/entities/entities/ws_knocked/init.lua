--[[
    ws_knocked Entity - Server

    Handles timer management, damage (execution),
    revival triggering, and inventory looting.
]]--

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    -- This entity is invisible - we use a prop_ragdoll for visuals
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetUseType(SIMPLE_USE)

    -- Initialize state
    self:SetPermadead(false)
    self:SetCurrentReviver(NULL)
end

-- Create the ragdoll visual for this knocked entity
function ENT:CreateRagdoll(model, skin, bodygroups, submaterials)
    -- Remove existing ragdoll if any
    if IsValid(self.wsRagdoll) then
        self.wsRagdoll:Remove()
    end

    -- Create prop_ragdoll for proper ragdoll physics
    local ragdoll = ents.Create("prop_ragdoll")
    ragdoll:SetPos(self:GetPos())
    ragdoll:SetAngles(self:GetAngles())
    ragdoll:SetModel(model)
    ragdoll:SetSkin(skin or 0)

    -- Copy bodygroups
    if bodygroups then
        for i, v in pairs(bodygroups) do
            ragdoll:SetBodygroup(i, v)
        end
    end

    ragdoll:Spawn()
    ragdoll:Activate()
    ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    -- CRITICAL: Prevent Citizen Clothing Overhaul addon from randomizing our ragdoll's clothing
    -- The addon checks this flag before applying random outfits to prop_ragdoll entities
    ragdoll._ClothingHandled = true

    -- Copy SubMaterials (clothing system)
    if submaterials then
        for i, mat in pairs(submaterials) do
            ragdoll:SetSubMaterial(i, mat)
        end
    end

    -- Link ragdoll to this entity (server-side)
    ragdoll.wsKnockedEntity = self
    self.wsRagdoll = ragdoll

    -- Store reference for closure
    local knockedEntity = self

    -- Delay SetNetVar by one frame to ensure both entities are fully networked
    -- This prevents race condition where client receives ragdoll before NetVar propagates
    timer.Simple(0, function()
        -- Validate both entities still exist
        if not IsValid(ragdoll) or not IsValid(knockedEntity) then
            -- Clean up orphaned ragdoll if ws_knocked was removed
            if IsValid(ragdoll) and not IsValid(knockedEntity) then
                ragdoll:Remove()
            end
            return
        end

        -- Network the link to clients using Windswept's SetNetVar
        ragdoll:SetNetVar("wsKnockedEntity", knockedEntity)
    end)

    -- Make ragdoll useable and forward Use to our entity
    ragdoll:SetUseType(SIMPLE_USE)
    ragdoll.Use = function(rag, activator, caller)
        if IsValid(self) then
            self:Use(activator, caller)
        end
    end

    -- Forward GetEntityMenu to our entity for right-click menu
    ragdoll.GetEntityMenu = function(rag, client)
        if IsValid(self) then
            return self:GetEntityMenu(client)
        end
        return {}
    end

    -- Keep our entity position synced with ragdoll
    self:SetPos(ragdoll:GetPos())

    return ragdoll
end

-- ============================================================================
-- CREMATION SYSTEM
-- ============================================================================

-- Check if ragdoll is on fire (uses windswept_fire API with GMod native fallback)
function ENT:IsRagdollOnFire()
    local ragdoll = self.wsRagdoll
    if not IsValid(ragdoll) then return false end

    -- Prefer ws_fire API if available
    if ws_fire and ws_fire.IsOnFire then
        return ws_fire.IsOnFire(ragdoll)
    end

    -- Fallback: Check .fires table (windswept_fire maintains this for compatibility)
    if ragdoll.fires and next(ragdoll.fires) then
        return true
    end

    -- Final fallback to GMod native
    return ragdoll:IsOnFire()
end

-- Check if inside cremation oven (future feature)
function ENT:IsInCremationOven()
    -- TODO: Implement cremation oven proximity detection
    return false
end

-- Get cremation duration based on location
function ENT:GetCremationDuration()
    return self:IsInCremationOven() and 60 or 240
end

-- Re-ignite the ragdoll (body is fuel - fire sustains until cremation complete)
function ENT:ReigniteRagdoll()
    local ragdoll = self.wsRagdoll
    if not IsValid(ragdoll) then return end

    -- Reset burn think time to prevent gap accumulation
    -- (in case re-ignition doesn't immediately stick, e.g., body in water)
    self.wsLastBurnThink = CurTime()

    -- Prefer ws_fire API if available (better particles and performance)
    if ws_fire and ws_fire.constants then
        local c = ws_fire.constants
        ws_fire.CreateOnEntity(ragdoll, {
            life = c.CREMATION_FIRE_LIFE,
            feed = c.CREMATION_FIRE_FEED,
            state = ws_fire.STATE_SMALL  -- Campfire-sized, not inferno
        })
    elseif ws_fire and ws_fire.CreateOnEntity then
        -- Fallback if constants not loaded yet
        ws_fire.CreateOnEntity(ragdoll, {
            life = 10,
            feed = 5,
            state = ws_fire.STATE_SMALL
        })
    else
        -- Fallback: Use GMod native ignite
        ragdoll:Ignite(30)
    end
end

-- Sustain fire at consistent intensity (body is fuel)
-- Call periodically to prevent fire from dying down
-- Uses windswept_fire API with GMod native fallback
function ENT:SustainFire()
    local ragdoll = self.wsRagdoll
    if not IsValid(ragdoll) then return end

    local curTime = CurTime()

    -- Get sustain interval from constants or use default
    local sustainInterval = (ws_fire and ws_fire.constants) and ws_fire.constants.CREMATION_SUSTAIN_INTERVAL or 2

    -- Sustain periodically to keep fire consistently burning
    if self.wsNextFireSustain and curTime < self.wsNextFireSustain then
        return
    end
    self.wsNextFireSustain = curTime + sustainInterval

    -- Get target values from constants
    local targetLife = (ws_fire and ws_fire.constants) and ws_fire.constants.CREMATION_FIRE_LIFE or 10
    local targetFeed = (ws_fire and ws_fire.constants) and ws_fire.constants.CREMATION_FIRE_FEED or 5

    -- Check for fires via .fires table (windswept_fire maintains this)
    if ragdoll.fires and next(ragdoll.fires) then
        for fire, _ in pairs(ragdoll.fires) do
            if IsValid(fire) then
                -- Boost fire to maintain cremation intensity (body is fuel)
                -- windswept_fire exposes .life and .feed as direct properties
                if fire.life ~= nil and fire.life < targetLife then
                    fire.life = targetLife
                end
                if fire.feed ~= nil and fire.feed < targetFeed then
                    fire.feed = targetFeed
                end
            end
        end
    else
        -- No fires table - create fire using ws_fire or native fallback
        if ws_fire and ws_fire.CreateOnEntity then
            ws_fire.CreateOnEntity(ragdoll, {
                life = targetLife,
                feed = targetFeed,
                state = ws_fire.STATE_SMALL
            })
        else
            -- Native GMod fire fallback
            ragdoll:Ignite(30)
        end
    end
end

-- Handle cremation progress tracking
function ENT:HandleCremation()
    -- Safety: If ragdoll was removed externally, abort cremation
    if not IsValid(self.wsRagdoll) then
        self.wsBurnStartTime = nil
        self.wsLastBurnThink = nil
        return
    end

    local curTime = CurTime()

    -- Initialize burn tracking
    if not self.wsBurnStartTime then
        self.wsBurnStartTime = curTime
    end

    -- Calculate burn progress
    local burnProgress = self:GetBurnProgress() + (curTime - (self.wsLastBurnThink or curTime))
    self.wsLastBurnThink = curTime

    -- Update networked progress (for client-side darkening)
    self:SetBurnProgress(burnProgress)

    -- Sustain fire at consistent intensity (body is fuel)
    self:SustainFire()

    -- Play burning sounds periodically
    if not self.wsNextBurnSound or curTime >= self.wsNextBurnSound then
        local ragdoll = self.wsRagdoll
        if IsValid(ragdoll) then
            sound.Play("ambient/fire/mtov_flame2.wav", ragdoll:GetPos(), 60, math.random(90, 110), 0.7)
        end
        self.wsNextBurnSound = curTime + math.random(4, 6)
    end

    -- Check if cremation complete
    if burnProgress >= self:GetCremationDuration() then
        self:CompleteCremation()
    end
end

-- Handle cremation completion
function ENT:CompleteCremation()
    local charName = self:GetCharacterName() or "Unknown"
    local pos = IsValid(self.wsRagdoll) and self.wsRagdoll:GetPos() or self:GetPos()

    -- Log cremation
    ws.log.Add(nil, "cremation", charName)

    -- Destroy inventory (items burn with body)
    local invID = self:GetInventoryID()
    if invID and invID > 0 then
        -- Remove from memory
        ws.item.inventories[invID] = nil

        -- Delete items from database
        local itemQuery = mysql:Delete("ws_items")
            itemQuery:Where("inventory_id", invID)
        itemQuery:Execute()

        -- Delete inventory from database
        local invQuery = mysql:Delete("ws_inventories")
            invQuery:Where("inventory_id", invID)
        invQuery:Execute()
    end

    -- Mark inventory as already cleaned so OnRemove doesn't try again
    self:SetInventoryID(0)

    -- Spawn Human Remains item
    ws.item.Spawn("human_remains", pos, function(item, entity)
        if item then
            -- Store original character name as data (but not displayed - fog of war)
            item:SetData("originalCharacter", charName)
        end
    end)

    -- Remove this entity (OnRemove handles ragdoll cleanup)
    self:Remove()
end

-- Set the player model and create the ragdoll
-- Note: NetworkVar "KnockedModel" (String) handles networking via SetupDataTables
function ENT:SetKnockedModel(model)
    -- Store in NetworkVar for client access
    self.dt.KnockedModel = model
end

-- Set the player skin
-- Note: NetworkVar "KnockedSkin" (Int) handles networking via SetupDataTables
function ENT:SetKnockedSkin(skin)
    self:SetSkin(skin)
    -- Store in NetworkVar for client access (auto-generated setter from SetupDataTables)
    self.dt.KnockedSkin = skin
end

-- Override SetPermadead to track when body became permadead (for decay timer)
function ENT:SetPermadead(value)
    self.dt.Permadead = value
    if value then
        self.wsPermadeadTime = CurTime()
    end
end

-- ============================================================================
-- TIMER MANAGEMENT
-- ============================================================================

function ENT:Think()
    -- Dead bodies persist indefinitely until players dispose of them
    -- (burial, cremation, disposal, etc.)
    if self:GetPermadead() then
        -- Check for cremation (burning)
        local isOnFire = self:IsRagdollOnFire()
        local burnProgress = self:GetBurnProgress()

        if isOnFire then
            self:HandleCremation()
        elseif burnProgress > 0 then
            -- Cremation started but fire went out - body is fuel, reignite!
            self:ReigniteRagdoll()
            self:HandleCremation()
        end
        -- Note: if never ignited (burnProgress == 0), don't auto-ignite

        self:NextThink(CurTime() + 0.5)
        return true
    end

    -- Check for cremation on knocked (alive but unconscious) bodies
    local isOnFire = self:IsRagdollOnFire()
    local burnProgress = self:GetBurnProgress()

    if isOnFire then
        self:HandleCremation()
        -- Fire also halves knockout timer periodically
        if not self.wsLastFireDamage or CurTime() - self.wsLastFireDamage >= 2 then
            self:HalveTimer()
            self.wsLastFireDamage = CurTime()
        end
    elseif burnProgress > 0 then
        -- Cremation started but fire went out - body is fuel, reignite!
        self:ReigniteRagdoll()
        self:HandleCremation()
    end
    -- Note: if never ignited (burnProgress == 0), don't auto-ignite

    -- Check knockout timer expiration (for knocked but not dead bodies)
    local remaining = self:GetRemainingTime()
    if remaining <= 0 then
        local plugin = ws.plugin.Get("permadeath")
        if plugin then
            plugin:OnKnockoutExpired(self)
        end
    end

    self:NextThink(CurTime() + 0.5)
    return true
end

-- Halve the remaining timer (from damage)
function ENT:HalveTimer()
    if self:GetPermadead() then return end

    local remaining = self:GetRemainingTime()
    local newDuration = remaining / 2

    self:SetTimerStart(CurTime())
    self:SetTimerDuration(newDuration)

    -- Sync to knocked player
    local owner = self:GetOwningPlayer()
    if IsValid(owner) then
        net.Start("wsKnockoutTimerSync")
            net.WriteFloat(newDuration)
        net.Send(owner)
    end
end

-- ============================================================================
-- DAMAGE HANDLING (EXECUTION)
-- ============================================================================

function ENT:OnTakeDamage(dmgInfo)
    if self:GetPermadead() then return end

    local attacker = dmgInfo:GetAttacker()
    local plugin = ws.plugin.Get("permadeath")
    if not plugin then return end

    -- Determine if headshot via damage position relative to ragdoll head bone
    local isHeadshot = false
    local damagePos = dmgInfo:GetDamagePosition()

    if damagePos and damagePos ~= Vector(0, 0, 0) and IsValid(self.wsRagdoll) then
        -- Get the actual head bone position from the ragdoll
        local headBone = self.wsRagdoll:LookupBone("ValveBiped.Bip01_Head1")
        if headBone then
            local headPos = self.wsRagdoll:GetBonePosition(headBone)
            if headPos then
                local distToHead = damagePos:Distance(headPos)
                -- Consider it a headshot if damage is within 12 units of head bone
                isHeadshot = distToHead < 12
            end
        end
    end

    if isHeadshot then
        -- 50% instant execution, 50% halve timer
        if math.random() < 0.5 then
            -- Execution
            local charID = self:GetCharacterID()
            local character = ws.char.loaded[charID]

            if character then
                local owner = self:GetOwningPlayer()
                if IsValid(owner) then
                    plugin:ApplyPermadeath(owner, character, "executed_headshot")
                else
                    -- Offline execution
                    character:SetData("permadead", true)
                    character:SetData("permaDeathReason", "executed_headshot_offline")
                    character:SetData("permaDeathTime", os.time())
                    character:SetData("knocked", nil)
                    character:SetData("knockoutExpires", nil)
                    self:SetPermadead(true)
                end
            else
                self:SetPermadead(true)
            end
        else
            -- Survived headshot - halve timer
            self:HalveTimer()
        end
    else
        -- Body shot - halve timer
        self:HalveTimer()
    end
end

-- ============================================================================
-- USE / REVIVAL
-- ============================================================================

-- Note: Primary interaction is now handled via net messages (wsKnockoutLoot/wsKnockoutRevive)
-- This Use function is kept as a fallback and for compatibility
function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    -- Block Use for 2 seconds after revival attempt to prevent CPR from triggering loot
    if self.wsLastReviveAttempt and CurTime() - self.wsLastReviveAttempt < 2 then
        return
    end

    -- Also block if this player has an active DoStaredAction
    if activator:GetAction() and activator:GetAction() ~= "" then
        return
    end

    -- Default Use action is to loot (matches E tap behavior)
    -- Revival requires holding E (handled via client-side detection)
    self:OpenInventory(activator)
end

-- ============================================================================
-- ENTITY MENU (Right-click options)
-- ============================================================================

function ENT:GetEntityMenu(client)
    local options = {}

    if not self:GetPermadead() then
        -- Revive option
        options[L("attemptRevival")] = function()
            local plugin = ws.plugin.Get("permadeath")
            if plugin then
                plugin:AttemptRevival(client, self)
            end
        end
    end

    -- Loot option (not available when on fire)
    if not self:IsRagdollOnFire() then
        options[L("searchBody")] = function()
            self:OpenInventory(client)
        end
    end

    return options
end

-- ============================================================================
-- INVENTORY / LOOTING
-- ============================================================================

-- Sound effects for looting (rustling through clothes/gear)
local lootSounds = {
    "npc/combine_soldier/gear1.wav",
    "npc/combine_soldier/gear2.wav",
    "npc/combine_soldier/gear3.wav",
    "npc/combine_soldier/gear4.wav",
    "npc/combine_soldier/gear5.wav",
    "npc/combine_soldier/gear6.wav"
}

function ENT:OpenInventory(client)
    -- Cannot search a body that is on fire
    if self:IsRagdollOnFire() then
        client:NotifyLocalized("bodyOnFire")
        return
    end

    local invID = self:GetInventoryID()
    if not invID or invID == 0 then
        client:NotifyLocalized("noInventory")
        return
    end

    local inventory = ws.item.inventories[invID]
    if not inventory then
        client:NotifyLocalized("noInventory")
        return
    end

    -- Play looting sound (rustling through gear)
    local ragdoll = self.wsRagdoll
    local soundPos = IsValid(ragdoll) and ragdoll:GetPos() or self:GetPos()
    sound.Play(lootSounds[math.random(#lootSounds)], soundPos, 60, 100, 0.8)

    -- Get character name for display (stored permanently on entity)
    local name = self:GetCharacterName()
    if not name or name == "" then
        name = "Unknown"
    end

    -- Use Windswept storage system
    -- IMPORTANT: Pass the ragdoll as the entity, not self (ws_knocked is invisible)
    -- DoStaredAction traces to check if player is looking at the entity,
    -- so we need to pass the visible ragdoll they're actually looking at
    local stareEntity = IsValid(ragdoll) and ragdoll or self
    ws.storage.Open(client, inventory, {
        name = name .. "'s Body",
        entity = stareEntity,
        searchTime = 1,
        bMultipleUsers = true
    })
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

function ENT:OnRemove()
    -- Remove the ragdoll
    if IsValid(self.wsRagdoll) then
        self.wsRagdoll:Remove()
    end

    -- Clear any revival in progress
    local reviver = self:GetCurrentReviver()
    if IsValid(reviver) then
        reviver:SetAction()
    end

    -- Clear reference from owner
    local owner = self:GetOwningPlayer()
    if IsValid(owner) then
        owner.wsKnockedEntity = nil
    end

    -- Clean up from plugin tracking table to prevent memory leaks
    if self.wsSteamID64 then
        local plugin = ws.plugin.Get("permadeath")
        if plugin and plugin.knockedEntities then
            plugin.knockedEntities[self.wsSteamID64] = nil
        end
    end

    -- Clean up inventory when permadead body is removed (not when revived)
    if self:GetPermadead() then
        local invID = self:GetInventoryID()
        if invID and invID > 0 then
            -- Remove from memory
            ws.item.inventories[invID] = nil

            -- Delete items from database
            local itemQuery = mysql:Delete("ws_items")
                itemQuery:Where("inventory_id", invID)
            itemQuery:Execute()

            -- Delete inventory from database
            local invQuery = mysql:Delete("ws_inventories")
                invQuery:Where("inventory_id", invID)
            invQuery:Execute()
        end
    end
end
