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
        target     true          read an entity; verify IsValid (+ range if set)
        range      "interaction"|"close"  distance check between client and target
        rateLimit  number        per-client min seconds between accepted calls
        read       function() -> any   custom reader for remaining payload (returns ctx.data)
        onValidate function(client, ctx) -> bool   extra gate (return false to reject)
        run        function(client, ctx)           the action body
]]--

ws.action = ws.action or {}

if SERVER then
    function ws.action.Register(name, def)
        assert(isstring(name) and istable(def) and isfunction(def.run),
            "ws.action.Register requires (name, def with .run)")

        util.AddNetworkString(name)

        net.Receive(name, function(len, client)
            if not IsValid(client) then return end

            -- per-client rate limit
            if def.rateLimit then
                client._wsActionNext = client._wsActionNext or {}
                local nextT = client._wsActionNext[name]
                if nextT and CurTime() < nextT then return end
                client._wsActionNext[name] = CurTime() + def.rateLimit
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

            -- target entity argument (+ optional range)
            if def.target then
                local target = net.ReadEntity()
                if not IsValid(target) then return end
                if def.range == "close" then
                    if not ws.access.CanInteractClose(client, target) then return end
                elseif def.range == "interaction" then
                    if not ws.access.CanInteract(client, target) then return end
                end
                ctx.target = target
            end

            -- custom payload reader
            if def.read then ctx.data = def.read() end

            if def.onValidate and def.onValidate(client, ctx) == false then return end

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
