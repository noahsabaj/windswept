--[[
    Per-map persistence: debounced dirty-flush to disk, load + first-run
    bootstrap of default doors.

    Physical door plugin (framework). Extracted from the Colony schema in the
    convergence program; inert unless a schema enables the doorsEnabled config.
]]--

ws.doors = ws.doors or {}

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

local SAVE_PATH = "windswept/doors/"

function ws.doors.GetSavePath()
    local mapName = game.GetMap()
    return SAVE_PATH .. mapName .. ".json"
end

-- Write the full door state to disk immediately. Most callers should use
-- ws.doors.Save() (debounced) instead of calling this directly. (sc-doors-access-9)
function ws.doors.Flush()
    ws.doors.dirty = false

    local data = {
        frames = {},
        doors = {}
    }

    -- Save frame settings
    for mapID, frameData in pairs(ws.doors.frames) do
        data.frames[tostring(mapID)] = {
            disabled = frameData.disabled
        }

        -- Save door data if exists
        if frameData.hasDoor and IsValid(frameData.doorEntity) then
            local door = frameData.doorEntity
            data.doors[tostring(mapID)] = {
                health = door.wsHealth,
                maxHealth = door.wsMaxHealth,
                lockData = door.wsLockData,
                locked = door:IsLocked(),
                -- Battering ram damage persists until repaired
                ramRequired = door.wsBatteringRamRequired,
                ramHits = door.wsBatteringRamHits
            }
        end
    end

    -- Ensure directory exists
    file.CreateDir(SAVE_PATH)

    -- Save to file
    local json = util.TableToJSON(data, true)
    file.Write(ws.doors.GetSavePath(), json)
end

-- Debounced save: mark the state dirty instead of rewriting the whole JSON on
-- every door mutation. A periodic flush timer writes at most once per interval,
-- which removes the per-change disk-write hot path. (sc-doors-access-9)
function ws.doors.Save()
    ws.doors.dirty = true
end

-- Frequent flush of pending changes (only writes when dirty).
timer.Create("wsDoorsDirtyFlush", 5, 0, function()
    if ws.doors.dirty then
        ws.doors.Flush()
    end
end)

function ws.doors.Load()
    local path = ws.doors.GetSavePath()

    if not file.Exists(path, "DATA") then
        -- First run: bootstrap all frames with default doors
        ws.doors.BootstrapDefaultDoors()
        return
    end

    local json = file.Read(path, "DATA")
    if not json then return end

    local data = util.JSONToTable(json)
    if not data then return end

    -- Apply frame settings
    if data.frames then
        for mapIDStr, frameSettings in pairs(data.frames) do
            local mapID = tonumber(mapIDStr)
            if mapID and ws.doors.frames[mapID] then
                ws.doors.frames[mapID].disabled = frameSettings.disabled or false
            end
        end
    end

    -- Spawn doors
    if data.doors then
        for mapIDStr, doorData in pairs(data.doors) do
            local mapID = tonumber(mapIDStr)
            if mapID and ws.doors.frames[mapID] and not ws.doors.frames[mapID].hasDoor then
                ws.doors.SpawnDoor(mapID, doorData)
            end
        end
    end

end

-- Bootstrap: spawn default doors for all frames on first run
function ws.doors.BootstrapDefaultDoors()
    local count = 0
    for mapID, frameData in pairs(ws.doors.frames) do
        if not frameData.disabled and not frameData.hasDoor then
            local door = ws.doors.SpawnDoor(mapID, nil)  -- nil = use default type
            if IsValid(door) then
                count = count + 1
            end
        end
    end

    -- Save the initial state so next load uses persistence
    ws.doors.Save()
end
