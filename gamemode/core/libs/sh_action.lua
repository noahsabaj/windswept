--[[
    ws.action — validated client->server action dispatch (framework)

    The one sanctioned way to register a client->server action. It declares its
    guards, and the wrapper enforces them BEFORE run() — so it is structurally
    impossible to ship a handler that forgets an ownership / range / bounds check
    (the class of bug behind the "read any document" / "load anyone's battery"
    holes). Treat every client payload as hostile.

    Usage:
        ws.action.Register("document.read", {
            item   = "paper",          -- reads UInt32 id; verifies accessibility (+uniqueID)
            run    = function(client, ctx) ... ctx.item ... end,
        })

    def fields:
        item       string|true   read a UInt32 item id; verify via ws.access (uniqueID match if string)
        access     "accessible"|"owned"  ownership rule for `item` (default "accessible")
        target     true          read an entity; verify IsValid (+ distance check)
        targetClass string       require ctx.target:GetClass() == this (needs target)
        range      "close"(default)|"interaction"|"none"|number  distance check when target is set
                                 (omit = "close"; "none" opts out for non-physical targets;
                                  a number = linear units, e.g. 200 for open-UI session reach)
        session    true          require ctx.target:GetUser() == client — the "you have this
                                 UI open" authority for session entities (needs target)
        rateLimit  number        per-client min seconds between accepted calls
        read       function() -> any   custom reader for remaining payload (returns ctx.data)
        onValidate function(client, ctx) -> bool   extra gate (return false to reject)
        run        function(client, ctx)           the action body
]]--

ws.action = ws.action or {}

if SERVER then
    -- Track registered action names so re-registering a name surfaces a collision
    -- instead of silently stacking a second net.Receive. (fw-core-security-9)
    ws.action.registered = ws.action.registered or {}

    function ws.action.Register(name, def)
        assert(isstring(name) and istable(def) and isfunction(def.run),
            "ws.action.Register requires (name, def with .run)")
        -- An invalid/typo'd range string would silently disable the distance check,
        -- so reject anything other than the known values. "none" is the explicit opt-out
        -- for non-physical targets; nil defaults to a "close" check below. (fw-core-security-3)
        local validRange = def.range == nil or def.range == "close" or def.range == "interaction"
            or def.range == "none" or isnumber(def.range)
        assert(validRange, "ws.action.Register: def.range must be nil, 'close', 'interaction', " ..
            "'none', or a number (got " .. tostring(def.range) .. ")")
        -- session / targetClass authority only make sense against a target entity. (session shape)
        assert(not def.session or def.target, "ws.action.Register: def.session requires def.target")
        assert(not def.targetClass or def.target, "ws.action.Register: def.targetClass requires def.target")

        if ws.action.registered[name] then
            ErrorNoHalt("ws.action.Register: duplicate registration of '" .. name .. "' (collision)\n") -- (fw-core-security-9)
        end
        ws.action.registered[name] = true

        util.AddNetworkString(name)

        net.Receive(name, function(len, client)
            if not IsValid(client) then return end

            -- per-client rate limit. Only check here; the timestamp is written AFTER all
            -- guards pass so a rejected/spoofed payload can't consume a legit caller's
            -- cooldown window. (fw-core-security-2)
            if def.rateLimit then
                client._wsActionNext = client._wsActionNext or {}
                local nextT = client._wsActionNext[name]
                if nextT and CurTime() < nextT then return end
            end

            local ctx = {}

            -- item argument
            if def.item then
                local itemID = net.ReadUInt(32)
                local expected = (def.item ~= true) and def.item or nil
                local item
                if def.access == "owned" then
                    item = ws.access.VerifyItemOwnership(client, itemID, expected)
                else
                    item = ws.access.VerifyItemAccessible(client, itemID, expected)
                end
                if not item then return end
                ctx.item = item
            end

            -- target entity argument (+ range). When def.target is set, a distance check
            -- runs by default ("close"); pass range='none' to opt out for non-physical
            -- targets, so a missing range can't become silent action-at-a-distance. (fw-core-security-3)
            if def.target then
                local target = net.ReadEntity()
                if not IsValid(target) then return end
                -- reject a crafted entity of the wrong class before any further checks. (session shape)
                if def.targetClass and target:GetClass() ~= def.targetClass then return end
                if def.range == "interaction" then
                    if not ws.access.CanInteract(client, target) then return end
                elseif isnumber(def.range) then
                    -- numeric range = linear units (e.g. open-UI session reach). (session shape)
                    if not ws.access.WithinRange(client, target, def.range * def.range) then return end
                elseif def.range ~= "none" then
                    -- nil or "close" both fall through to the close-range check
                    if not ws.access.CanInteractClose(client, target) then return end
                end
                -- session authority: the player must currently have this entity's UI open
                -- (the entity tracked them via ent:SetUser when it opened). (session shape)
                if def.session and not (target.GetUser and target:GetUser() == client) then return end
                ctx.target = target
            end

            -- custom payload reader
            if def.read then ctx.data = def.read() end

            if def.onValidate and def.onValidate(client, ctx) == false then return end

            -- All guards passed: now charge the rate limit so only accepted calls
            -- consume the cooldown window. (fw-core-security-2)
            if def.rateLimit then
                client._wsActionNext[name] = CurTime() + def.rateLimit
            end

            def.run(client, ctx)
        end)
    end
else
    -- Client helper: fire an action with the standard argument order
    -- (item id first, then target, then extra writer).
    function ws.action.Send(name, itemID, target, writeExtra)
        net.Start(name)
            if itemID ~= nil then net.WriteUInt(itemID, 32) end
            if target ~= nil then net.WriteEntity(target) end
            if writeExtra then writeExtra() end
        net.SendToServer()
    end
end
