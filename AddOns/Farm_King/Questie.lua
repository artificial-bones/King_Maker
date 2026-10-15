local _, ns = ...

-- QuestieDB, when it's installed: every hostile mob in the game (name, levels,
-- elite/rare, zone, spawn points) and every item's list of mobs that drop it.
-- We read it through its public API (LibQuestieDB, NpcDB, ItemDB) and copy
-- nothing into our own saved data. Without it, Farm King lists only the mobs
-- you've seen, which still works.
--
-- The mob list and the "what can drop from this mob" index are built in the
-- background the first time they're needed, a few hundred entries per frame.

local BATCH = 250
local ready, building = false, false
local mobs = {}        -- npcID -> true: hostile mobs worth listing
local drops = {}       -- npcID -> { itemID, ... } possible drops
local itemNames = {}   -- itemID -> name, for items some mob drops (item search)
local areaToMap        -- AreaTable ID -> uiMapID
local progress = ""

function ns.QuestieAvailable()
    return LibQuestieDB ~= nil and NpcDB ~= nil and NpcDB.GetAllIds ~= nil and ItemDB ~= nil
end

function ns.QuestieReady() return ready end
function ns.QuestieBuilding() return building, progress end
function ns.QuestieMobs() return mobs end

local function myFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- Mobs you'd fight: not friendly to your faction, not a vendor or trainer,
-- not one of the database's placeholder entries.
local function hostile(id, faction)
    local name = NpcDB.name(id)
    if not name or name == "" or name:find("[%[%(]") then return false end
    local friendly = NpcDB.friendlyToFaction(id)
    if friendly and faction and friendly:find(faction, 1, true) then return false end
    local flags = NpcDB.npcFlags(id)
    if flags and flags ~= 0 then return false end
    local maxLevel = NpcDB.maxLevel(id)
    return maxLevel ~= nil and maxLevel > 0
end

local function loadZones()
    local ok, zones = pcall(LibQuestieDB.Support.Get, "ZoneDB")
    if not ok or type(zones) ~= "table" or not zones.private then return end
    local function load(s)
        if type(s) == "table" then return s end
        if type(s) ~= "string" then return {} end
        local fn = loadstring(s)
        local ok2, t = pcall(fn or function() end)
        return ok2 and type(t) == "table" and t or {}
    end
    areaToMap = load(zones.private.areaIdToUiMapId)
    for k, v in pairs(load(zones.private.areaIdToUiMapIdOverride)) do areaToMap[k] = v end
end

-- Runs fn over list a batch per frame, then done().
local function batches(list, fn, done, label)
    local i = 1
    local function step()
        local stop = math.min(i + BATCH - 1, #list)
        for j = i, stop do pcall(fn, list[j]) end
        i = stop + 1
        progress = label .. " " .. math.floor(math.min(i, #list) / math.max(#list, 1) * 100) .. "%"
        if i <= #list then C_Timer.After(0, step) else done() end
    end
    C_Timer.After(0, step)
end

function ns.BuildQuestie(onDone)
    if ready or building or not ns.QuestieAvailable() then return end
    building = true
    pcall(loadZones)
    local faction = myFaction()
    local npcs = NpcDB.GetAllIds() or {}
    batches(npcs, function(id) if hostile(id, faction) then mobs[id] = true end end, function()
        local items = ItemDB.GetAllIds() or {}
        batches(items, function(item)
            local list = ItemDB.npcDrops(item)
            if not list then return end
            local any = false
            for _, npc in ipairs(list) do
                if mobs[npc] then any = true end
            end
            if any then itemNames[item] = ItemDB.name(item) end
            for _, npc in ipairs(list) do
                if mobs[npc] then
                    drops[npc] = drops[npc] or {}
                    table.insert(drops[npc], item)
                end
            end
        end, function()
            ready, building, progress = true, false, ""
            if onDone then onDone() end
        end, "Reading drops")
    end, "Reading mobs")
end

---------------------------------------------------------------------------
-- Per mob
---------------------------------------------------------------------------

function ns.QuestieDrops(id) return drops[id] end
function ns.QuestieItemNames() return itemNames end

-- Mobs QuestieDB says drop this item (hostile ones only).
function ns.QuestieDroppedBy(item)
    if not ready then return nil end
    local list = ItemDB.npcDrops(item)
    if not list then return nil end
    local out = {}
    for _, npc in ipairs(list) do if mobs[npc] then table.insert(out, npc) end end
    return out
end

-- Zones are needed for pins and zone names even before the mob list is built.
local function zones()
    if not areaToMap and ns.QuestieAvailable() then pcall(loadZones) end
    return areaToMap
end
ns.QuestieZones = zones

-- { name, lmin, lmax, rank, map } or nil
local RANK = { [1] = "elite", [2] = "rare elite", [3] = "boss", [4] = "rare" }
function ns.QuestieMob(id)
    if not ns.QuestieAvailable() or not NpcDB.Exists(id) then return nil end
    local zone, maps = NpcDB.zoneID(id), zones()
    local lmin, lmax = NpcDB.minLevel(id), NpcDB.maxLevel(id)
    lmin, lmax = lmin ~= 0 and lmin or nil, lmax ~= 0 and lmax or nil
    local map = zone and zone ~= 0 and maps and maps[zone] or nil
    return {
        name = NpcDB.name(id),
        lmin = lmin or lmax,
        lmax = lmax or lmin,
        rank = RANK[NpcDB.rank(id)],
        map = map ~= 0 and map or nil,
        sub = NpcDB.subName(id),
    }
end

-- Spawn points as { { uiMapID, x, y }, ... } with x and y from 0 to 1.
function ns.QuestieSpawns(id)
    if not ns.QuestieAvailable() then return nil end
    local spawns, maps = NpcDB.spawns(id), zones()
    if not spawns or not maps then return nil end
    local out = {}
    for area, points in pairs(spawns) do
        local map = maps[area]
        if map and map ~= 0 then
            for _, p in ipairs(points) do
                if p[1] and p[1] >= 0 and p[2] and p[2] >= 0 then table.insert(out, { map, p[1] / 100, p[2] / 100 }) end
            end
        end
    end
    return out
end
