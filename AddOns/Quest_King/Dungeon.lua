local _, ns = ...

-- Dungeon quests: for every dungeon in Data/Dungeons.lua, where you stand on
-- each of its quests, the levels that matter, and where to go.
--
-- Status of a quest, in order:
--   done     the game says you turned it in (or you ticked it off yourself)
--   active   it, or a step of its chain, is in your quest log
--   chain    you've done part of its chain
--   ready    you're high enough level to pick it up
--   low      not yet: it needs a higher level
--
-- QuestieDB (optional, the same one Farm King uses) adds:
--   * the level you can pick a quest up at (requiredLevel) and its exact quest level,
--   * quest IDs the dungeon log lacks, found by name,
--   * where the quest giver stands, from its spawn points, for a waypoint,
--   * where each dungeon's entrance is.
-- Without it the log's own levels and coordinates are used, and the pickup
-- level is estimated (shown with a ~).

local FULL_XP = 5 -- a quest gives full XP until you're this many levels above it

ns.SOURCES = {
    wh = { "WH", "Checked on Wowhead's Forever quest pages" },
    bc = { "BETA", "From the beta client's data" },
    cl = { "CLASSIC", "The Classic version, not yet confirmed on Forever" },
    fg = { "GUIDE", "Fan guide only: treat with caution" },
}

local function db() return QuestKingDB end

function ns.Level() return UnitLevel and UnitLevel("player") or 1 end

function ns.ClassToken()
    if not UnitClass then return nil end
    local _, token = UnitClass("player")
    return token
end

---------------------------------------------------------------------------
-- QuestieDB
---------------------------------------------------------------------------

function ns.HasQuestie()
    return QuestDB ~= nil and QuestDB.Exists ~= nil
end

local function num(v) return (type(v) == "number" and v ~= 0) and v or nil end

local function qget(id, field)
    if not (id and ns.HasQuestie() and QuestDB[field]) then return nil end
    local ok, v = pcall(QuestDB[field], id)
    if ok then return v end
end

-- The quest's ID: the log's, or QuestieDB's by name (the one nearest the quest's level).
local found = {}
function ns.QuestID(q)
    if q.id then return q.id end
    if found[q] ~= nil then return found[q] or nil end
    local best
    if ns.HasQuestie() and QuestDB.IdsByName then
        local ok, ids = pcall(QuestDB.IdsByName, q.name)
        local bestGap
        for _, id in ipairs(ok and ids or {}) do
            local gap = math.abs((num(qget(id, "questLevel")) or 0) - (q.level or 0))
            if not bestGap or gap < bestGap then best, bestGap = id, gap end
        end
    end
    found[q] = best or false
    return best
end

-- The first quest of its chain with an ID: where you pick the whole thing up.
local function firstID(q)
    for _, step in ipairs(q.chain or {}) do
        if step.ids and step.ids[1] then return step.ids[1] end
    end
    return ns.QuestID(q)
end

-- The level you can pick it up at, and whether that's only an estimate.
function ns.MinLevel(q)
    local need = num(qget(firstID(q), "requiredLevel")) or num(qget(ns.QuestID(q), "requiredLevel"))
    if need then return need, false end
    if not q.level then return nil end
    return math.max(1, q.level - 6), true -- the log: "usually 5 to 8 levels lower"
end

function ns.QuestLevel(q)
    return q.level or num(qget(ns.QuestID(q), "questLevel"))
end

-- Up to this level the quest gives full XP.
function ns.FullXPUntil(q)
    local lv = ns.QuestLevel(q)
    return lv and lv + FULL_XP
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function completed(id)
    return id and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
end

local function inLog(id)
    if not (id and C_QuestLog) then return false end
    if C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) and true or false end
    return C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) ~= nil or false
end

local function key(d, q) return d.key .. ":" .. q.name end

-- Your own tick for a quest: true (done), or nil.
function ns.Ticked(d, q) return db().dqDone[key(d, q)] end
function ns.SetTicked(d, q, v) db().dqDone[key(d, q)] = v or nil end

local function stepKey(q, step) return "step:" .. q.name .. ":" .. step[1] end
function ns.StepTicked(q, step) return db().dqDone[stepKey(q, step)] end
function ns.SetStepTicked(q, step, v) db().dqDone[stepKey(q, step)] = v or nil end

-- Each chain step: "done", "active" or nil.
function ns.StepState(q, step)
    if ns.StepTicked(q, step) then return "done" end
    local ids = step.ids or (step.this and { ns.QuestID(q) }) or {}
    for _, id in ipairs(ids) do if completed(id) then return "done" end end
    for _, id in ipairs(ids) do if inLog(id) then return "active" end end
    return nil
end

function ns.QuestState(d, q)
    local id = ns.QuestID(q)
    if ns.Ticked(d, q) or completed(id) then return "done" end
    if inLog(id) then return "active" end
    local started = false
    for _, step in ipairs(q.chain or {}) do
        local s = ns.StepState(q, step)
        if s == "active" then return "active" end
        if s == "done" then started = true end
    end
    if started then return "chain" end
    local min = ns.MinLevel(q)
    if min and ns.Level() < min then return "low" end
    return "ready"
end

-- The step to do next: the first one not done (nil when the quest is done).
function ns.NextStep(q)
    if not q.chain or q.state == "done" then return nil end
    for i, step in ipairs(q.chain) do
        if ns.StepState(q, step) ~= "done" then return i end
    end
end

-- A step's quest name, and what to do ("Hidden Enemies (5726): get the insignia" -> both halves).
function ns.StepText(step)
    local name, what = step[1]:match("^(.-):%s*(.+)$")
    if name and #name < 60 then return name, what end
    return step[1], nil
end

ns.STATES = {
    done = { "|cff40c040", "Done" },
    active = { "|cffffd100", "In your log" },
    chain = { "|cff4fc3f7", "Chain started" },
    ready = { "|cffffffff", "Ready" },
    low = { "|cff808080", "Too low" },
}

-- Quests that count for this character: its class, and level 60 ones unless hidden.
function ns.Visible(q)
    if q.class and q.class ~= ns.ClassToken() then return false end
    if q.endgame and db().dqHide60 then return false end
    if q.also then return false end -- listed under another dungeon too
    return true
end

function ns.VisibleQuests(d)
    local out = {}
    for _, q in ipairs(d.quests) do
        if ns.Visible(q) then
            q.state = ns.QuestState(d, q)
            if not (db().dqHideDone and q.state == "done") then table.insert(out, q) end
        end
    end
    return out
end

-- { total, done, active, ready, low } over the quests that count.
function ns.Progress(d)
    local p = { total = 0, done = 0, active = 0, ready = 0, low = 0, chain = 0 }
    for _, q in ipairs(d.quests) do
        if ns.Visible(q) then
            local s = ns.QuestState(d, q)
            p.total = p.total + 1
            p[s] = p[s] + 1
        end
    end
    return p
end

-- The levels where you can pick up the most of a dungeon's quests and still get
-- full XP for every one: from, to, how many, of how many.
function ns.BestLevels(d)
    local quests = {}
    for _, q in ipairs(d.quests) do
        if ns.Visible(q) and ns.QuestLevel(q) then table.insert(quests, q) end
    end
    if #quests == 0 then return nil end
    local best, from, to = 0, nil, nil
    for level = 1, 60 do
        local n = 0
        for _, q in ipairs(quests) do
            local min = ns.MinLevel(q)
            if min <= level and level <= ns.FullXPUntil(q) then n = n + 1 end
        end
        if n > best then best, from, to = n, level, level
        elseif n == best and n > 0 and to == level - 1 then to = level end
    end
    return from, to, best, #quests
end

---------------------------------------------------------------------------
-- Where to go
---------------------------------------------------------------------------

-- Towns and spots the log names, and the zone they're in.
local HUBS = {
    ["Crossroads"] = "The Barrens", ["Ratchet"] = "The Barrens", ["Camp Taurajo"] = "The Barrens",
    ["Brill"] = "Tirisfal Glades", ["Sepulcher"] = "Silverpine Forest", ["Tarren Mill"] = "Hillsbrad Foothills",
    ["Stonard"] = "Swamp of Sorrows", ["Kargath"] = "Badlands", ["Caer Darrow"] = "Western Plaguelands",
    ["Light's Hope"] = "Eastern Plaguelands", ["Gadgetzan"] = "Tanaris", ["Camp Mojache"] = "Feralas",
    ["Freewind Post"] = "Thousand Needles", ["Splintertree"] = "Ashenvale", ["Zoram'gar"] = "Ashenvale",
    ["Sen'jin"] = "Durotar", ["Razor Hill"] = "Durotar", ["Grom'gol"] = "Stranglethorn Vale",
    ["Booty Bay"] = "Stranglethorn Vale", ["Everlook"] = "Winterspring", ["Cenarion Hold"] = "Silithus",
    ["Shadowprey"] = "Desolace", ["Brackenwall"] = "Dustwallow Marsh", ["Thorium Point"] = "Searing Gorge",
    ["Hammerfall"] = "Arathi Highlands", ["Revantusk"] = "The Hinterlands", ["Bloodvenom Post"] = "Felwood",
    ["Marshal's Refuge"] = "Un'Goro Crater", ["Sunrock Retreat"] = "Stonetalon Mountains",
    ["Bloodhoof Village"] = "Mulgore", ["Flame Crest"] = "Burning Steppes", ["Chillwind Camp"] = "Western Plaguelands",
    ["Tirisfal"] = "Tirisfal Glades", ["Silverpine"] = "Silverpine Forest", ["Hillsbrad"] = "Hillsbrad Foothills",
    ["Hinterlands"] = "The Hinterlands", ["Barrens"] = "The Barrens", ["Stranglethorn"] = "Stranglethorn Vale",
    ["Stonetalon"] = "Stonetalon Mountains", ["Dustwallow"] = "Dustwallow Marsh", ["Un'Goro"] = "Un'Goro Crater",
    ["Swamp of Sorrows"] = "Swamp of Sorrows", ["Western Plaguelands"] = "Western Plaguelands",
    ["Eastern Plaguelands"] = "Eastern Plaguelands", ["Burning Steppes"] = "Burning Steppes",
}

-- Map names -> uiMapID, from the game's own map list.
local mapByName
local function maps()
    if mapByName then return mapByName end
    mapByName = {}
    if C_Map and C_Map.GetMapChildrenInfo then
        for _, root in ipairs({ 1414, 1415, 947 }) do
            local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
            for _, m in ipairs(ok and list or {}) do
                if m.name and not mapByName[m.name:lower()] then mapByName[m.name:lower()] = m.mapID end
            end
        end
    end
    return mapByName
end
function ns.MapByName(name) return name and maps()[name:lower()] end

-- The zone a piece of the log's text points at: the last place it names.
function ns.ZoneIn(text)
    local bestAt, bestMap, bestName
    local function try(name, zone)
        local s, e = 1, nil
        while true do
            local a, b = text:find(name, s, true)
            if not a then break end
            e, s = b, b + 1
        end
        if e and (not bestAt or e > bestAt) then
            local m = ns.MapByName(zone)
            if m then bestAt, bestMap, bestName = e, m, zone end
        end
    end
    for hub, zone in pairs(HUBS) do try(hub, zone) end
    for name in pairs(maps()) do
        -- map names are lowercased; match them without case
        local a = text:lower():find(name, 1, true)
        if a then try(text:sub(a, a + #name - 1), name) end
    end
    return bestMap, bestName
end

local areaToMap
local function zoneDB()
    if not (LibQuestieDB and LibQuestieDB.Support and LibQuestieDB.Support.Get) then return nil end
    local ok, z = pcall(LibQuestieDB.Support.Get, "ZoneDB")
    return ok and type(z) == "table" and z or nil
end

local function areaMap(area)
    if not areaToMap then
        areaToMap = {}
        local z = zoneDB()
        local function load(s)
            if type(s) == "table" then return s end
            local fn = type(s) == "string" and loadstring(s)
            local ok, t = pcall(fn or function() end)
            return ok and type(t) == "table" and t or {}
        end
        if z and z.private then
            for k, v in pairs(load(z.private.areaIdToUiMapId)) do areaToMap[k] = v end
            for k, v in pairs(load(z.private.areaIdToUiMapIdOverride)) do areaToMap[k] = v end
        end
    end
    return areaToMap[area]
end

-- Where the quest giver is: mapID, x, y (0-100), and how we know.
local function pointForQuest(id)
    local starters = qget(id, "startedBy")
    local npcs = type(starters) == "table" and starters[1]
    if type(npcs) == "table" and NpcDB and NpcDB.spawns then
        for _, npc in ipairs(npcs) do
            local ok, spawns = pcall(NpcDB.spawns, npc)
            for area, points in pairs(ok and spawns or {}) do
                local p = points[1]
                local m = areaMap(area)
                if m and p and p[1] and p[1] >= 0 then return m, p[1], p[2], "QuestieDB" end
            end
        end
    end
    return nil
end

local function pointInText(text)
    local x, y = text:match("%((%d+%.?%d*),%s*(%d+%.?%d*)%)")
    if not x then return nil end
    local m = ns.ZoneIn(text)
    if m then return m, tonumber(x), tonumber(y), "the dungeon log" end
end

function ns.GiverPoint(q)
    local m, x, y, from = pointForQuest(firstID(q))
    if m then return m, x, y, from end
    if q.x and q.y then
        m = ns.ZoneIn(q.giver)
        if m then return m, q.x, q.y, "the dungeon log" end
    end
    return nil
end

-- Where a chain step starts: its quest's giver (QuestieDB), coordinates in its
-- text, or for the first step and the dungeon step, the quest's giver.
function ns.StepPoint(q, step, index)
    local id = (step.ids and step.ids[1]) or (step.this and ns.QuestID(q))
    local m, x, y, from = pointForQuest(id)
    if m then return m, x, y, from end
    m, x, y, from = pointInText(step[1])
    if m then return m, x, y, from end
    if index == 1 or step.this then return ns.GiverPoint(q) end
    return nil
end

function ns.WaypointToStep(q, step, index)
    local m, x, y = ns.StepPoint(q, step, index)
    local name = ns.StepText(step)
    if not ns.Waypoint(m, x, y, name) then ns.Print("No coordinates for this step: " .. step[1]) end
end

-- Where the dungeon's entrance is (QuestieDB's dungeon list): mapID, x, y.
function ns.EntrancePoint(d)
    local z = zoneDB()
    local list = z and ((z.private and z.private.dungeons) or z.dungeons)
    if type(list) ~= "table" then return nil end
    for _, entry in pairs(list) do
        if type(entry) == "table" and entry[1] and entry[1]:lower() == d.name:lower() and type(entry[4]) == "table" then
            local loc = entry[4][1]
            local m = loc and areaMap(loc[1])
            if m then return m, loc[2], loc[3] end
        end
    end
    return nil
end

-- A waypoint: TomTom's arrow when you have it, and the game's own map pin.
function ns.Waypoint(mapID, x, y, title)
    if not (mapID and x and y) then return false end
    local set = false
    if TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, mapID, x / 100, y / 100, { title = title, persistent = false, minimap = true, world = true })
        set = true
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
        if ok then
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
            set = true
        end
    end
    if set then
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        ns.Print(string.format("Waypoint: %s, %s %.1f, %.1f", title, info and info.name or "?", x, y))
    end
    return set
end

function ns.WaypointToGiver(q)
    local m, x, y = ns.GiverPoint(q)
    if not ns.Waypoint(m, x, y, q.name) then
        ns.Print("No coordinates for " .. q.name .. ": " .. q.giver)
    end
end

function ns.WaypointToEntrance(d)
    local m, x, y = ns.EntrancePoint(d)
    if not ns.Waypoint(m, x, y, d.name) then ns.Print(d.name .. ": " .. d.at) end
end

---------------------------------------------------------------------------
-- For you: what's worth doing at your level
---------------------------------------------------------------------------

-- Dungeons in level order with their progress; .fits when your level is in the range.
function ns.DungeonList()
    local out, level = {}, ns.Level()
    for _, d in ipairs(ns.DUNGEONS) do
        d.progress = ns.Progress(d)
        d.fits = level >= d.min - 2 and level <= d.max
        table.insert(out, d)
    end
    return out
end
