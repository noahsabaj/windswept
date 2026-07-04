--[[
    Permadeath Plugin - Server Logic

    Handles damage interception, knockout state management,
    revival mechanics, and permadeath application.
]]--

-- Store reference to active knockout entities by SteamID64
PLUGIN.knockedEntities = PLUGIN.knockedEntities or {}

-- ============================================================================
-- LOG TYPE REGISTRATION (must happen before any logging calls)
-- ============================================================================

ws.log.AddType("knockout", function(client, knockoutCount, duration)
    return string.format("%s was knocked out (knockout #%d, %s remaining)",
        client:Name(), knockoutCount, duration)
end, FLAG_WARNING)

ws.log.AddType("revival", function(client, revivedName, health)
    return string.format("%s revived %s with %d HP",
        client:Name(), revivedName, health)
end, FLAG_SUCCESS)

ws.log.AddType("permadeath", function(client, charName, reason)
    return string.format("%s's character '%s' died permanently (%s)",
        client:Name(), charName, reason)
end, FLAG_DANGER)

-- Offline finalizations have no valid client to Name(); log the character only. (#75)
ws.log.AddType("permadeath_offline", function(client, charName, reason)
    return string.format("Offline character '%s' died permanently (%s)", charName, reason)
end, FLAG_DANGER)

ws.log.AddType("knockout_giveup", function(client)
    return string.format("%s gave up while knocked out", client:Name())
end, FLAG_WARNING)

ws.log.AddType("defibKnockout", function(client, victimName)
    return string.format("%s shocked %s with a defibrillator, knocking them out",
        client:Name(), victimName)
end, FLAG_WARNING)

ws.log.AddType("suicide", function(client, charName)
    return string.format("%s's character '%s' took their own life", client:Name(), charName)
end, FLAG_DANGER)

ws.log.AddType("cremation", function(client, charName)
    return string.format("Body of '%s' was cremated", charName)
end, FLAG_WARNING)

-- ============================================================================
-- DAMAGE INTERCEPTION (using EntityTakeDamage hook)
-- ============================================================================

-- Track hit groups for headshot detection
-- ScalePlayerDamage is called before damage is applied and gives us the hit group
function PLUGIN:ScalePlayerDamage(client, hitGroup, dmgInfo)
    client.wsLastHitGroup = hitGroup
end

-- Intercept lethal damage and convert to knockout
-- EntityTakeDamage allows us to modify/cancel damage before it's applied
function PLUGIN:EntityTakeDamage(entity, dmgInfo)
    -- Forward damage from prop_ragdoll to its linked ws_knocked entity
    if entity:GetClass() == "prop_ragdoll" and IsValid(entity.wsKnockedEntity) then
        entity.wsKnockedEntity:OnTakeDamage(dmgInfo)
        return
    end

    -- Only handle player damage
    if not entity:IsPlayer() then return end

    local client = entity
    local character = client:GetCharacter()
    if not character then return end

    -- If player is already knocked out, ignore (damage goes to entity instead)
    if IsValid(client.wsKnockedEntity) then return end

    -- Prevent race condition: if we're already processing lethal damage for this player
    -- (e.g., multiple bullets in same frame), ignore subsequent damage
    if client.wsProcessingLethalDamage then return end

    -- Check if this damage would be lethal
    local currentHealth = client:Health()
    local damage = dmgInfo:GetDamage()

    if currentHealth - damage > 0 then
        -- Not lethal, let normal damage through
        return
    end

    -- This would be lethal - intercept it

    -- Set flag to prevent race conditions with multiple damage events
    client.wsProcessingLethalDamage = true

    -- Scale damage to 0 to prevent death
    dmgInfo:ScaleDamage(0)

    -- Check for headshot - configurable chance of instant permadeath.
    -- Require bullet damage: wsLastHitGroup is only updated by ScalePlayerDamage (the bullet
    -- path) and is never cleared, so non-bullet lethal damage (fall/fire/explosion) must not
    -- inherit a stale head hitgroup. (sc-permadeath-4)
    if dmgInfo:IsBulletDamage() and self:IsHeadshot(client) then
        local headshotChance = ws.config.Get("permadeathHeadshotChance", 50) / 100
        if math.random() < headshotChance then
            -- Lost the coin flip - instant permadeath
            -- Create the knocked entity first so there's a body to leave behind
            local pos = client:GetPos()
            local ang = Angle(0, client:EyeAngles().y, 0)
            local knockedEntity = self:CreateKnockedEntity(client, character, pos, ang, 0)  -- (sc-permadeath-8)

            if knockedEntity then
                self:HideKnockedPlayer(client, knockedEntity)
            end

            self:ApplyPermadeath(client, character, "headshot_execution")
            client.wsProcessingLethalDamage = nil
            return
        end
    end

    -- Create knockout state instead of death
    self:CreateKnockout(client, character, dmgInfo)
    client.wsProcessingLethalDamage = nil
end

-- ============================================================================
-- COMMUNICATION ISOLATION (server-side enforcement)
-- ============================================================================
-- The cl_plugin chat/voice blocks are cosmetic and bypassable by a modified client;
-- enforce knockout isolation on the server too. (sc-permadeath-1)

function PLUGIN:PlayerCanHearPlayersVoice(listener, speaker)
    if IsValid(speaker.wsKnockedEntity) or IsValid(listener.wsKnockedEntity) then
        return false
    end
end

function PLUGIN:PlayerSay(client, text)
    if IsValid(client.wsKnockedEntity) then
        return ""
    end
end

-- Block normal respawn for knocked players
function PLUGIN:PlayerDeathThink(client)
    if IsValid(client.wsKnockedEntity) then
        return true  -- Block respawn
    end

    local character = client:GetCharacter()
    if character and character:GetData("permadead") then
        return true  -- Block respawn for permadead characters
    end
end

-- Prevent Windswept from creating competing ragdolls when player has knockout entity
-- Windswept's DoPlayerDeath checks this hook before calling client:CreateRagdoll()
function PLUGIN:ShouldSpawnClientRagdoll(client)
    if IsValid(client.wsKnockedEntity) then
        return false
    end
end

-- ============================================================================
-- KNOCKOUT HELPERS
-- ============================================================================

-- Collect all bodygroups from a player
function PLUGIN:CollectBodygroups(client)
    local bodygroups = {}
    for i = 0, client:GetNumBodyGroups() - 1 do
        bodygroups[i] = client:GetBodygroup(i)
    end
    return bodygroups
end

-- Collect all SubMaterials from a player (clothing system)
function PLUGIN:CollectSubMaterials(client)
    local submaterials = {}
    local materials = client:GetMaterials()
    for i = 0, #materials - 1 do
        local submat = client:GetSubMaterial(i)
        if submat and submat ~= "" then
            submaterials[i] = submat
        end
    end
    return submaterials
end

-- Check if a player entity is on fire (supports windswept_fire, vFire, and GMod native)
function PLUGIN:IsPlayerOnFire(client)
    if not IsValid(client) then return false end

    -- Prefer ws_fire API if available
    if ws_fire and ws_fire.IsOnFire then
        return ws_fire.IsOnFire(client)
    end

    -- Fallback: Check .fires table (works with vFire and windswept_fire)
    if client.fires and next(client.fires) then
        return true
    end

    -- Final fallback to GMod native
    return client:IsOnFire()
end

-- Create and configure an ws_knocked entity
function PLUGIN:CreateKnockedEntity(client, character, pos, ang, duration)
    local entity = ents.Create("ws_knocked")
    if not IsValid(entity) then
        ErrorNoHalt("[Permadeath] Failed to create ws_knocked entity!\n")
        return nil
    end

    entity:SetPos(pos)
    entity:SetAngles(ang)
    entity:Spawn()
    entity:Activate()

    -- Configure NetworkVars
    entity:SetKnockedModel(client:GetModel())
    entity:SetKnockedSkin(client:GetSkin())
    entity:SetOwningPlayer(client)
    entity:SetCharacterID(character:GetID())
    entity:SetCharacterName(character:GetName())
    entity:SetTimerStart(CurTime())
    entity:SetTimerDuration(duration)

    -- Link to character's inventory for looting
    local inventory = character:GetInventory()
    if inventory then
        entity:SetInventoryID(inventory:GetID())
    end

    -- Create the visible ragdoll
    local bodygroups = self:CollectBodygroups(client)
    local submaterials = self:CollectSubMaterials(client)
    entity:CreateRagdoll(client:GetModel(), client:GetSkin(), bodygroups, submaterials)

    -- Store references
    client.wsKnockedEntity = entity
    entity.wsOwner = client
    entity.wsSteamID64 = client:SteamID64()
    self.knockedEntities[entity.wsSteamID64] = entity

    -- Transfer cremation progress from alive player (if any)
    if client.wsCremationProgress and client.wsCremationProgress > 0 then
        entity:SetBurnProgress(client.wsCremationProgress)
        entity.wsLastBurnThink = CurTime()
        -- Clear from player
        client.wsCremationProgress = nil
        client.wsLastFireThink = nil
    end

    return entity
end

-- Drop the currently equipped weapon item next to the player (except protected
-- classes), clearing its equipped state so the dropped/looted item isn't stuck
-- "equipped". Shared by the knockout and suicide body flows. (#76)
function PLUGIN:DropActiveWeapon(client)
    local activeWeapon = client:GetActiveWeapon()
    if not IsValid(activeWeapon) then return end

    local class = activeWeapon:GetClass()
    local protected = {["ws_hands"] = true, ["ws_handsup"] = true}

    if not protected[class] and activeWeapon.wsItem then
        local item = activeWeapon.wsItem
        item:SetData("equipped", nil)
        item:Transfer(nil, nil, nil, client, client:GetPos() + Vector(0, 0, 10))
    end
end

-- Hide and freeze a knocked player
function PLUGIN:HideKnockedPlayer(client, entity)
    client:StripWeapons()
    client:SetNoDraw(true)
    client:SetNotSolid(true)
    client:Freeze(true)
    client:SetMoveType(MOVETYPE_NONE)
    client:SetPos(entity:GetPos() + Vector(0, 0, 10000))
    client:SetDSP(31)
end

-- Send knockout notification to client
function PLUGIN:SendKnockoutStart(client, duration, knockoutCount)
    net.Start("wsKnockoutStart")
        net.WriteFloat(duration)
        net.WriteUInt(knockoutCount, 8)
    net.Send(client)
end

-- Validate a knocked body interaction (loot, revive, etc.)
-- Returns entity if valid and in range, nil otherwise
function PLUGIN:ValidateKnockedInteraction(client, entity)
    if not IsValid(entity) or entity:GetClass() ~= "ws_knocked" then
        return nil
    end

    -- Check distance to ragdoll (the visible/draggable body), not ws_knocked entity
    -- The ws_knocked entity stays at the original knockout position, but the ragdoll can be dragged
    local checkPos = IsValid(entity.wsRagdoll) and entity.wsRagdoll:GetPos() or entity:GetPos()
    if client:GetPos():Distance(checkPos) > 96 then
        return nil
    end

    return entity
end

-- ============================================================================
-- KNOCKOUT CREATION
-- ============================================================================

function PLUGIN:CreateKnockout(client, character, dmgInfo)
    -- Increment knockout count (permanent, never resets)
    local knockoutCount = (character:GetData("knockoutCount") or 0) + 1
    character:SetData("knockoutCount", knockoutCount)

    -- Calculate duration based on knockout history
    local duration = self:GetKnockoutDuration(knockoutCount)

    -- Store knockout state for disconnect handling
    local expireTime = os.time() + math.ceil(duration)
    character:SetData("knockoutExpires", expireTime)
    character:SetData("knocked", true)

    -- Create the knocked entity (zeroes pitch/roll for ragdoll)
    local pos = client:GetPos()
    local ang = Angle(0, client:EyeAngles().y, 0)
    local entity = self:CreateKnockedEntity(client, character, pos, ang, duration)
    if not entity then return end

    self:DropActiveWeapon(client)
    self:HideKnockedPlayer(client, entity)
    self:SendKnockoutStart(client, duration, knockoutCount)

    -- Log the knockout
    ws.log.Add(client, "knockout", knockoutCount, self:FormatTime(duration))
end

-- ============================================================================
-- REVIVAL SYSTEM
-- ============================================================================

function PLUGIN:AttemptRevival(reviver, knockedEntity)
    if not IsValid(reviver) or not IsValid(knockedEntity) then
        return false
    end

    -- Check if entity is already permadead
    if knockedEntity:GetPermadead() then
        reviver:NotifyLocalized("knockedAlreadyDead")
        return false
    end

    -- Check if owner is online (can't revive disconnected players)
    if not IsValid(knockedEntity.wsOwner) then
        reviver:NotifyLocalized("knockedPlayerDisconnected")
        return false
    end

    -- Check if someone else is already reviving
    local currentReviver = knockedEntity:GetCurrentReviver()
    if IsValid(currentReviver) and currentReviver ~= reviver then
        reviver:NotifyLocalized("knockedAlreadyBeingRevived")
        return false
    end

    -- Lock the entity to this reviver
    knockedEntity:SetCurrentReviver(reviver)

    -- Track revival attempt time to prevent Use() from triggering loot during/after CPR
    knockedEntity.wsLastReviveAttempt = CurTime()

    -- Random progress duration (3-10 seconds by default)
    -- This is equipmentless CPR-style revival (no defib)
    local duration = self:GetRevivalDuration()

    -- Start the revival progress
    reviver:SetAction("@reviving", duration)

    -- IMPORTANT: Pass the ragdoll to DoStaredAction, not the ws_knocked entity
    -- The ws_knocked entity is invisible and hidden - player is looking at the ragdoll
    local stareTarget = IsValid(knockedEntity.wsRagdoll) and knockedEntity.wsRagdoll or knockedEntity

    -- Use DoStaredAction for progress-based revival (must look at target)
    -- Signature: DoStaredAction(entity, callback, time, onCancel, distance)
    reviver:DoStaredAction(stareTarget, function()
        -- Completed - attempt the revival (equipmentless, no defib)
        self:CompleteRevivalAttempt(reviver, knockedEntity, false, nil)
    end, duration, function()
        -- Cancelled (looked away, moved too far, etc.)
        knockedEntity:SetCurrentReviver(NULL)
        reviver:SetAction()
    end, 96)  -- 96 units max distance for revival

    return true
end

function PLUGIN:CompleteRevivalAttempt(reviver, knockedEntity, hasDefib, defibItem)
    -- Clear the reviver lock
    knockedEntity:SetCurrentReviver(NULL)

    -- Update revival attempt timestamp to prevent immediate loot after CPR
    knockedEntity.wsLastReviveAttempt = CurTime()

    -- Calculate success using probabilistic squared
    -- hasDefib is false for hold-E revival (CPR-style, low chance)
    local success = self:CalculateRevivalChance(hasDefib)

    if success then
        -- Revival succeeded!
        self:RevivePlayer(knockedEntity, reviver, hasDefib, defibItem)
    else
        -- Revival failed - can retry
        reviver:NotifyLocalized("revivalFailed")
    end
end

function PLUGIN:RevivePlayer(knockedEntity, reviver, usedDefib, defibItem)
    local owner = knockedEntity.wsOwner
    local charID = knockedEntity:GetCharacterID()

    -- Find the character
    local character
    if IsValid(owner) then
        character = owner:GetCharacter()
    else
        character = ws.char.loaded[charID]
    end

    if not character then
        ErrorNoHalt("[Permadeath] Cannot revive - character not found!\n")
        return
    end

    -- Random revival health: 1-50 HP
    local revivalHealth = math.random(1, 50)

    -- Clear knockout state
    character:SetData("knocked", nil)
    character:SetData("knockoutExpires", nil)

    -- If player is online, restore them
    if IsValid(owner) then
        -- Move player to ragdoll position (where the body actually is after potential dragging)
        local revivePos = IsValid(knockedEntity.wsRagdoll) and knockedEntity.wsRagdoll:GetPos() or knockedEntity:GetPos()
        local reviveAng = IsValid(knockedEntity.wsRagdoll) and knockedEntity.wsRagdoll:GetAngles() or knockedEntity:GetAngles()
        owner:SetPos(revivePos)
        owner:SetEyeAngles(reviveAng)

        -- Restore player state
        owner:SetNoDraw(false)
        owner:SetNotSolid(false)
        owner:Freeze(false)
        owner:SetMoveType(MOVETYPE_WALK)

        -- Set revival health
        owner:SetHealth(revivalHealth)

        -- Temporary no-collide to prevent clipping with reviver
        owner:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        timer.Simple(1.5, function()
            if IsValid(owner) then
                owner:SetCollisionGroup(COLLISION_GROUP_PLAYER)
            end
        end)

        -- Clear muffled audio
        owner:SetDSP(0)

        -- Give hands weapon back
        owner:Give("ws_hands")
        owner:SelectWeapon("ws_hands")

        -- Notify the revived player
        net.Start("wsKnockoutEnd")
            net.WriteBool(true)  -- Revived successfully
            net.WriteUInt(revivalHealth, 8)
        net.Send(owner)

        -- Clear knockout entity reference
        owner.wsKnockedEntity = nil

        -- Handle cremation state on revival
        if not self:IsPlayerOnFire(owner) then
            -- Not on fire after revival = reset cremation (body heals)
            owner.wsCremationProgress = nil
            owner.wsLastFireThink = nil
        else
            -- Still on fire after revival - transfer progress back from entity
            local burnProgress = knockedEntity:GetBurnProgress()
            if burnProgress and burnProgress > 0 then
                owner.wsCremationProgress = burnProgress
                owner.wsLastFireThink = CurTime()
            end
        end
    end

    -- Consume defib charge if used
    if usedDefib and IsValid(defibItem) then
        self:ConsumeDefibCharge(defibItem, reviver)
    end

    -- Notify reviver
    reviver:NotifyLocalized("revivalSuccess")

    -- Remove the knockout entity
    if knockedEntity.wsSteamID64 then
        self.knockedEntities[knockedEntity.wsSteamID64] = nil
    end
    knockedEntity:Remove()

    -- Log the revival
    ws.log.Add(reviver, "revival", character:GetName(), revivalHealth)
end

-- ============================================================================
-- PERMADEATH
-- ============================================================================

-- Delete a character from the database (replicates Windswept's deletion logic)
function PLUGIN:DeleteCharacter(client, character)
    local id = character:GetID()
    local steamID = client:SteamID64()

    -- Remove from player's character list
    for k, v in ipairs(client.wsCharList or {}) do
        if v == id then
            table.remove(client.wsCharList, k)
            break
        end
    end

    -- Run pre-delete hook
    hook.Run("PreCharacterDeleted", client, character)

    -- Remove from loaded characters
    ws.char.loaded[id] = nil

    -- Notify all clients about the deletion
    net.Start("wsCharacterDelete")
        net.WriteUInt(id, 32)
    net.Broadcast()

    -- Delete character from database
    local query = mysql:Delete("ws_characters")
        query:Where("id", id)
        query:Where("steamid", steamID)
    query:Execute()

    -- NOTE: We intentionally do NOT delete the inventory here!
    -- The dead body (ws_knocked entity) needs the inventory for looting.
    -- The inventory will be cleaned up when the body is removed.
    --
    -- But the rows must stop referencing the dead character id NOW: under SQLite
    -- (and MySQL <8 after restart) the next created character can REUSE this id,
    -- and ws.char.Restore selects ws_inventories by character_id -- which would
    -- hand the dead character's entire inventory (bags included) to the new one.
    -- Body looting is unaffected (in-memory instance; item/cleanup queries key on
    -- inventory_id), and if the body never despawns cleanly (crash) the rows are
    -- inert orphans instead of a resurrection. (#77)
    local invQuery = mysql:Update("ws_inventories")
        invQuery:Update("character_id", 0)
        invQuery:Where("character_id", id)
    invQuery:Execute()

    -- Item rows carry character_id as ownership attribution (world items /
    -- playerCharBelonging); restore keys on inventory_id, so this only strips the
    -- dead id's claim from a future character that reuses it. (#77)
    local itemQuery = mysql:Update("ws_items")
        itemQuery:Update("character_id", 0)
        itemQuery:Where("character_id", id)
    itemQuery:Execute()

    -- Run post-delete hook
    hook.Run("CharacterDeleted", client, id, true)

end

-- Delete a character when the player is offline (database only)
function PLUGIN:DeleteCharacterOffline(charID, steamID)
    -- Remove from loaded characters if still there
    ws.char.loaded[charID] = nil

    -- Notify all clients about the deletion
    net.Start("wsCharacterDelete")
        net.WriteUInt(charID, 32)
    net.Broadcast()

    -- Delete character from database, scoped to the owning steamid the same way
    -- DeleteCharacter does (the knocked entity stores wsSteamID64). (sc-permadeath-6)
    local query = mysql:Delete("ws_characters")
        query:Where("id", charID)
        if steamID then query:Where("steamid", steamID) end
    query:Execute()

    -- NOTE: We intentionally do NOT delete the inventory here!
    -- The dead body (ws_knocked entity) needs the inventory for looting.
    -- The inventory will be cleaned up when the body is removed.
    --
    -- Disassociate the rows from the (now reusable) character id so a future
    -- character created with the same id cannot inherit them -- see the same
    -- blocks in DeleteCharacter. (#77)
    local invQuery = mysql:Update("ws_inventories")
        invQuery:Update("character_id", 0)
        invQuery:Where("character_id", charID)
    invQuery:Execute()

    local itemQuery = mysql:Update("ws_items")
        itemQuery:Update("character_id", 0)
        itemQuery:Where("character_id", charID)
    itemQuery:Execute()

end

function PLUGIN:ApplyPermadeath(client, character, reason)
    -- Mark character as permanently dead
    character:SetData("permadead", true)
    character:SetData("permaDeathReason", reason)
    character:SetData("permaDeathTime", os.time())

    -- Clear knockout state
    character:SetData("knocked", nil)
    character:SetData("knockoutExpires", nil)

    -- If there's a knockout entity, mark it as permadead (stays for looting)
    if IsValid(client) and IsValid(client.wsKnockedEntity) then
        local knockedEntity = client.wsKnockedEntity
        if knockedEntity.wsSteamID64 then
            self.knockedEntities[knockedEntity.wsSteamID64] = nil
        end
        knockedEntity:SetPermadead(true)
        knockedEntity.wsOwner = nil
        client.wsKnockedEntity = nil
    end

    -- Log permadeath
    ws.log.Add(client, "permadeath", character:GetName(), reason)

    if IsValid(client) then
        -- Bots don't get memorial screens - just kick them from the server
        if client:IsBot() then
            -- Delete the bot's character
            local charID = character:GetID()
            ws.char.loaded[charID] = nil

            -- Kick the bot from the server
            client:Kick("Permadeath")
            return
        end

        -- Gather memorial data BEFORE deleting character
        local charName = character:GetName()
        local model = character:GetModel()
        -- Physical descriptors live on the character (the removed ID card only ever copied them).
        local physical = character:GetData("physical", {})

        local birthMonth = physical.birthMonth or 1
        local birthDay = physical.birthDay or 1
        local age = physical.age or 25
        local skin = physical.skin or client:GetSkin() or 0
        local bodygroups = physical.bodygroups or ""

        -- Convert bodygroups table to string if needed
        if istable(bodygroups) then
            local bgStr = ""
            for i = 0, 20 do
                bgStr = bgStr .. (bodygroups[i] or 0)
            end
            bodygroups = bgStr
        end

        -- Restore player state (make visible again for memorial)
        client:SetNoDraw(false)
        client:SetNotSolid(false)
        client:Freeze(true)  -- Keep frozen so they can't move
        client:SetMoveType(MOVETYPE_NONE)
        client:SetDSP(0)

        -- Delete the character NOW (before memorial - no escape)
        self:DeleteCharacter(client, character)

        -- Send memorial screen data
        net.Start("wsPermadeathScreen")
            net.WriteString(charName)
            net.WriteString(model)
            net.WriteUInt(skin, 8)
            net.WriteString(bodygroups)
            net.WriteUInt(birthMonth, 4)
            net.WriteUInt(birthDay, 5)
            net.WriteUInt(age, 8)
        net.Send(client)

        -- Mark the player as awaiting memorial acknowledgment. Only this real
        -- memorial flow sets the guard, so a client cannot fire wsPermadeathReady
        -- on its own to escape a knockout/combat (see FinishMemorial).
        client.wsAwaitingMemorial = true

        -- Start 60s timeout timer (in case client never responds)
        timer.Create("wsPermadeathTimeout_" .. client:SteamID64(), 60, 1, function()
            self:FinishMemorial(client)
        end)
    end
end

-- Finish the memorial flow: kick the player to the character menu and respawn.
-- Shared by the wsPermadeathReady handler and the 60s timeout fallback so both
-- behave identically. The wsAwaitingMemorial guard ensures this only runs for a
-- player the server actually placed in the memorial state.
function PLUGIN:FinishMemorial(client)
    if not IsValid(client) then return end
    if not client.wsAwaitingMemorial then return end
    client.wsAwaitingMemorial = nil

    -- Cancel the timeout timer (harmless no-op when the timeout itself is firing)
    timer.Remove("wsPermadeathTimeout_" .. client:SteamID64())

    -- Properly kick to character menu (replicating Windswept's character:Kick() logic)
    client:Freeze(false)
    client:KillSilent()

    -- Tell client to open character menu
    net.Start("wsCharacterKick")
        net.WriteBool(true)  -- isCurrentChar = true
    net.Send(client)

    -- Clear the character netvar and spawn
    client:SetNetVar("char", nil)
    client:Spawn()
end

-- Called when knockout timer expires
function PLUGIN:OnKnockoutExpired(knockedEntity)
    -- Cancel any active revival attempt (CPR in progress)
    local reviver = knockedEntity:GetCurrentReviver()
    if IsValid(reviver) then
        reviver:SetAction()  -- Clear action bar
        reviver:NotifyLocalized("cprCanceledPatientDied")
        knockedEntity:SetCurrentReviver(NULL)
    end

    -- Immediately set permadead to prevent multiple calls from Think()
    knockedEntity:SetPermadead(true)

    local charID = knockedEntity:GetCharacterID()
    local character = ws.char.loaded[charID]

    -- Clean up tracking table
    if knockedEntity.wsSteamID64 then
        self.knockedEntities[knockedEntity.wsSteamID64] = nil
    end

    if not character then
        return
    end

    local owner = knockedEntity.wsOwner

    if IsValid(owner) then
        self:ApplyPermadeath(owner, character, "timer_expired")
    else
        -- Player offline - apply permadeath and delete character
        local steamID = knockedEntity.wsSteamID64
        knockedEntity.wsOwner = nil

        -- Every finalization path leaves a log trace (the online path logs via
        -- ApplyPermadeath). (#75)
        ws.log.Add(nil, "permadeath_offline", character:GetName(), "timer_expired_offline")

        -- Delete the character from database (scoped to its owning steamid). (sc-permadeath-6)
        self:DeleteCharacterOffline(charID, steamID)
    end
end

-- ============================================================================
-- DEFIBRILLATOR HELPERS
-- ============================================================================

function PLUGIN:PlayerHasDefibReady(client)
    -- Check if player has a defibrillator equipped/ready with batteries
    if client.wsDefibReady and client.wsDefibItem then
        local item = client.wsDefibItem
        local batteries = item:GetData("batteries", {})
        for _, charge in ipairs(batteries) do
            if charge > 0 then return true, item end
        end
    end
    return false, nil
end

--- Deplete one full battery on the defib. Returns true only if a charge was actually
-- spent; false when there is nothing to spend, so the caller can refuse the shock instead
-- of delivering it for free (the H2 free-shock fix). (sc-permadeath-12)
function PLUGIN:ConsumeDefibCharge(item, client)
    local batteries = item:GetData("batteries", {})
    if #batteries == 0 then return false end

    -- Find first FULL battery (100up) and deplete it, tracking whether one was spent.
    local consumed = false
    for i, charge in ipairs(batteries) do
        if charge == 100 then
            batteries[i] = 0  -- Deplete, don't remove
            consumed = true
            break
        end
    end

    -- Nothing to spend (only depleted/partial batteries loaded): make no changes and
    -- signal the caller to abort the shock.
    if not consumed then return false end

    local _, inventory = ws.access.GetCharacterInventory(client)

    -- Auto-eject: remove non-full batteries if enabled (0up and partial).
    -- Transactional: only drop the slot from the array once the inventory Add has
    -- actually succeeded, so a full inventory / hook veto can't destroy the battery
    -- (room-before-remove, then verify Add). (sc-permadeath-5)
    if inventory and ws.option.Get(client, "batteryAutoEject", true) then
        for i = #batteries, 1, -1 do
            if batteries[i] < 100 then  -- Eject anything that's not full
                if inventory:FindEmptySlot(1, 1) then
                    local added = inventory:Add("battery", 1, {charge = batteries[i]})
                    if added ~= false then
                        table.remove(batteries, i)
                        client:NotifyLocalized("flashlightBatteryEjected")
                    end
                end
            end
        end
    end

    -- Auto-load: fill empty slots with 100up batteries
    if inventory and ws.option.Get(client, "batteryAutoLoad", true) then
        while #batteries < 4 do
            local fullBattery = item:FindFullBatteryInInventory(inventory)
            if fullBattery then
                table.insert(batteries, 100)
                fullBattery:Remove()
                client:NotifyLocalized("defibAutoLoaded")
            else
                break
            end
        end
    end

    item:SetData("batteries", batteries)

    -- Count usable (100up) batteries for notification
    local usableCount = 0
    for _, charge in ipairs(batteries) do
        if charge == 100 then usableCount = usableCount + 1 end
    end
    client:NotifyLocalized("defibBatteryUsed", usableCount)

    -- Warn if no usable batteries left
    if usableCount == 0 then
        client:NotifyLocalized("defibNoBattery")
    end

    return true
end

-- ============================================================================
-- CHARACTER LOADING / DISCONNECT HANDLING
-- ============================================================================

-- Block permadead characters from being used
function PLUGIN:CanPlayerUseCharacter(client, character)
    if character:GetData("permadead") then
        return false, "@characterPermadead"
    end
end

-- Check if character was knocked out and timer expired while offline
function PLUGIN:PlayerLoadedCharacter(client, character, lastChar)
    -- Defensive: a player who reached a character is no longer awaiting memorial.
    client.wsAwaitingMemorial = nil

    local knockoutExpires = character:GetData("knockoutExpires")

    if knockoutExpires then
        if knockoutExpires < os.time() then
            -- Timer expired while offline - permadeath
            timer.Simple(1, function()
                if IsValid(client) and client:GetCharacter() == character then
                    self:ApplyPermadeath(client, character, "timer_expired_offline")
                end
            end)
        else
            -- Still knocked - recreate the knockout state
            local remaining = knockoutExpires - os.time()
            timer.Simple(0.5, function()
                if IsValid(client) and client:GetCharacter() == character then
                    self:RestoreKnockoutState(client, character, remaining)
                end
            end)
        end
    end
end

-- Restore knockout state for player who reconnected while knocked
function PLUGIN:RestoreKnockoutState(client, character, remainingTime)
    -- Check if there's an existing entity for this character
    -- Use knockedEntities table lookup instead of ents.FindByClass iteration
    local existingEntity = self.knockedEntities[client:SteamID64()]

    -- Fallback: if not in table, search by character ID (handles edge cases)
    if not IsValid(existingEntity) then
        for _, ent in pairs(self.knockedEntities) do
            if IsValid(ent) and ent:GetCharacterID() == character:GetID() then
                existingEntity = ent
                break
            end
        end
    end

    if IsValid(existingEntity) then
        -- Reconnect to existing entity
        client.wsKnockedEntity = existingEntity
        existingEntity.wsOwner = client
        existingEntity:SetOwningPlayer(client)

        -- Ensure SteamID64 is stored (may be missing from older entities)
        if not existingEntity.wsSteamID64 then
            existingEntity.wsSteamID64 = client:SteamID64()
            self.knockedEntities[existingEntity.wsSteamID64] = existingEntity
        end

        -- Ensure character name is stored (may be missing from older entities)
        if not existingEntity:GetCharacterName() or existingEntity:GetCharacterName() == "" then
            existingEntity:SetCharacterName(character:GetName())
        end

        -- Ensure ragdoll exists (may have been removed)
        if not IsValid(existingEntity.wsRagdoll) then
            local bodygroups = self:CollectBodygroups(client)
            local submaterials = self:CollectSubMaterials(client)
            existingEntity:CreateRagdoll(client:GetModel(), client:GetSkin(), bodygroups, submaterials)
        end

        -- Recalculate timer
        existingEntity:SetTimerStart(CurTime())
        existingEntity:SetTimerDuration(remainingTime)
    else
        -- Entity was removed (server restart?) - recreate it
        local pos = client:GetPos()
        local ang = client:EyeAngles()
        self:CreateKnockedEntity(client, character, pos, ang, remainingTime)
    end

    self:HideKnockedPlayer(client, client.wsKnockedEntity)
    self:SendKnockoutStart(client, remainingTime, character:GetData("knockoutCount") or 1)
end

-- Handle player disconnect while knocked
function PLUGIN:PlayerDisconnected(client)
    -- Clean up memorial timeout timer
    timer.Remove("wsPermadeathTimeout_" .. client:SteamID64())

    local entity = client.wsKnockedEntity

    if IsValid(entity) then
        -- Clear owner reference but keep entity alive
        entity.wsOwner = nil
        entity:SetOwningPlayer(NULL)
        -- Timer continues via entity Think
    end
end

-- ============================================================================
-- PASSIVE HEALING
-- ============================================================================

function PLUGIN:InitializedPlugins()
    -- Start passive healing timer
    timer.Create("wsPassiveHealing", 60, 0, function()
        local healRate = ws.config.Get("permadeathPassiveHealRate", 1)
        local healCap = ws.config.Get("permadeathPassiveHealCap", 80) / 100

        for _, client in player.Iterator() do
            if not IsValid(client) then continue end

            local character = client:GetCharacter()
            if not character then continue end
            if not client:Alive() then continue end
            if IsValid(client.wsKnockedEntity) then continue end

            local maxHealth = client:GetMaxHealth()
            local capHealth = math.floor(maxHealth * healCap)
            local currentHealth = client:Health()

            if currentHealth < capHealth then
                local newHealth = math.min(currentHealth + healRate, capHealth)
                client:SetHealth(newHealth)
            end
        end
    end)

    -- Alive player cremation tracking (1.5s interval - cremation is not time-critical)
    timer.Create("wsAliveFireTracking", 1.5, 0, function()
        for _, client in player.Iterator() do
            if not IsValid(client) then continue end
            if not client:Alive() then continue end
            if IsValid(client.wsKnockedEntity) then continue end -- They're knocked, entity handles it

            local isOnFire = self:IsPlayerOnFire(client)

            if isOnFire then
                -- Initialize or continue tracking
                if not client.wsCremationProgress then
                    client.wsCremationProgress = 0
                end
                if not client.wsLastFireThink then
                    client.wsLastFireThink = CurTime()
                end

                -- Accumulate burn time
                local delta = CurTime() - client.wsLastFireThink
                client.wsCremationProgress = client.wsCremationProgress + delta
                client.wsLastFireThink = CurTime()
            else
                -- Fire extinguished while alive = RESET (body heals)
                if client.wsCremationProgress and client.wsCremationProgress > 0 then
                    client.wsCremationProgress = 0
                    client.wsLastFireThink = nil
                end
            end
        end
    end)
end

-- ============================================================================
-- GIVE UP HANDLER
-- ============================================================================

net.Receive("wsKnockoutGiveUp", function(len, client)
    -- Validate player is actually knocked out
    if not IsValid(client) then return end

    if not IsValid(client.wsKnockedEntity) then return end

    local entity = client.wsKnockedEntity
    if entity:GetPermadead() then return end

    -- Get current remaining time
    local remaining = entity:GetRemainingTime()

    -- Only reduce if timer is above 10 seconds (don't extend if already lower)
    if remaining > 10 then
        entity:SetTimerStart(CurTime())
        entity:SetTimerDuration(10)

        -- Persist the shortened deadline in the same (os.time) timebase the entity
        -- timer uses for live countdown, so a reconnect cannot resurrect the longer
        -- original timer from stale knockoutExpires. (sc-permadeath-9)
        local character = client:GetCharacter()
        if character then
            character:SetData("knockoutExpires", os.time() + 10)
        end

        -- Sync to client
        net.Start("wsKnockoutTimerSync")
            net.WriteFloat(10)
        net.Send(client)

        -- Log the give up
        ws.log.Add(client, "knockout_giveup")
    end
end)

-- ============================================================================
-- KNOCKED BODY INTERACTION (E tap = Loot, E hold = Revive)
-- ============================================================================

-- E tap: Search/loot body (works on both knocked and dead). Migrated to ws.action: target +
-- targetClass = "ws_knocked" gives an early class reject; range = "none" because the authoritative
-- distance is measured against the DRAGGED ragdoll inside ValidateKnockedInteraction, not the entity.
ws.action.Register("wsKnockoutLoot", {
    target = true,
    targetClass = "ws_knocked",
    range = "none",
    run = function(client, ctx)
        local plugin = ws.plugin.Get("permadeath")
        if not plugin then return end

        local entity = plugin:ValidateKnockedInteraction(client, ctx.target)
        if not entity then return end

        -- Block searching while CPR is in progress on this body, by anyone -- looting a
        -- patient mid-revival is not intended regardless of who the reviver is. (sc-permadeath-7)
        if IsValid(entity:GetCurrentReviver()) then
            client:NotifyLocalized("cprCannotSearchDuring")
            return
        end

        entity:OpenInventory(client)
    end
})

-- E hold: Attempt revival (only works on knocked, not dead). Migrated to ws.action: target +
-- targetClass = "ws_knocked"; range = "none" (distance is validated against the dragged ragdoll
-- inside ValidateKnockedInteraction, not the entity).
ws.action.Register("wsKnockoutRevive", {
    target = true,
    targetClass = "ws_knocked",
    range = "none",
    run = function(client, ctx)
        local plugin = ws.plugin.Get("permadeath")
        if not plugin then return end

        local entity = plugin:ValidateKnockedInteraction(client, ctx.target)
        if not entity then return end

        if entity:GetPermadead() then
            client:NotifyLocalized("knockedAlreadyDead")
            return
        end

        plugin:AttemptRevival(client, entity)
    end
})

-- ============================================================================
-- MEMORIAL ACKNOWLEDGMENT
-- ============================================================================

-- Client acknowledged memorial screen
net.Receive("wsPermadeathReady", function(len, client)
    if not IsValid(client) then return end

    -- FinishMemorial enforces (and clears) the wsAwaitingMemorial guard, so a
    -- client sending this without actually being on the memorial screen is ignored.
    local plugin = ws.plugin.Get("permadeath")
    if plugin then
        plugin:FinishMemorial(client)
    end
end)

-- ============================================================================
-- SUICIDE EXECUTION
-- ============================================================================

net.Receive("wsSuicideExecute", function(len, client)
    if not IsValid(client) then return end

    local character = client:GetCharacter()
    if not character then return end

    -- Validate weapon
    local weapon = client:GetActiveWeapon()
    if not IsValid(weapon) then return end
    if weapon:GetClass() ~= "tfa_ins2_wpn_38revolver" then return end

    -- Validate ammo (must have at least 1 in clip)
    if weapon:Clip1() < 1 then return end

    -- Consume the bullet
    weapon:SetClip1(weapon:Clip1() - 1)

    -- Play gunshot sound
    client:EmitSound("weapons/357/357_fire2.wav", 100, 100)

    -- Log suicide
    ws.log.Add(client, "suicide", character:GetName())

    -- Apply instant permadeath (bypass knockout)
    local plugin = ws.plugin.Get("permadeath")
    if plugin then
        -- A suicide must leave a body like every other death path.
        -- ApplyPermadeath's body block only marks an EXISTING wsKnockedEntity
        -- permadead, and DeleteCharacter intentionally keeps the inventory for the
        -- body to hold -- so with no body the character's items were orphaned in the
        -- DB forever, and suicide doubled as an instant loot-denial button for
        -- anyone about to be captured. Create the corpse first (drop the held
        -- weapon, hide the player, duration 0 -- every timer path is
        -- permadead-gated), then ApplyPermadeath marks it permadead and lootable
        -- exactly like an executed knocked body. (#76)
        local pos = client:GetPos()
        local ang = Angle(0, client:EyeAngles().y, 0)
        local entity = plugin:CreateKnockedEntity(client, character, pos, ang, 0)

        if entity then
            plugin:DropActiveWeapon(client)
            plugin:HideKnockedPlayer(client, entity)
        end

        plugin:ApplyPermadeath(client, character, "suicide")
    end
end)