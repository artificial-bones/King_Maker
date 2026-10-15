local _, ns = ...
local API = ns.API

-- Every mob Farm King knows, and what a kill is worth.
--
-- A mob's numbers add up your kills and your guildmates' (each guildmate's
-- latest data, so nothing is counted twice). With the filters:
--   gold per kill = average coin + for each drop: (units dropped / kills) x what one is worth
-- Drops of a quality you've switched off, and quest items, are left out.

-- Every npcID worth listing: yours, your guild's, and QuestieDB's.
function ns.AllMobs()
    local all = {}
    for id, m in pairs(ns.db.mobs) do if m.name or (m.k or 0) > 0 then all[id] = true end end
    for _, g in pairs(ns.db.guild) do
        for id in pairs(g.mobs or {}) do all[id] = true end
    end
    if ns.QuestieReady() then
        for id in pairs(ns.QuestieMobs()) do all[id] = true end
    end
    return all
end

-- Name, levels, rank and zone: what you've seen first, QuestieDB for the rest.
-- Mobs only QuestieDB knows don't change, so their info is kept for the session.
local questieOnly = {}
function ns.MobInfo(id)
    if not ns.db.mobs[id] and questieOnly[id] then return questieOnly[id] end
    local info = ns.MobInfoFresh(id)
    -- Keep it only once QuestieDB's zones are loaded, so a zone isn't missed for the session.
    if not ns.db.mobs[id] and (not ns.QuestieAvailable() or ns.QuestieZones()) then questieOnly[id] = info end
    return info
end

function ns.MobInfoFresh(id)
    local m = ns.db.mobs[id] or {}
    local q = ns.QuestieMob(id) or {}
    local map = q.map
    if not map and m.z then
        local best = 0
        for z, n in pairs(m.z) do if n > best then map, best = z, n end end
    end
    return {
        name = m.name or q.name or ("Mob " .. id),
        lmin = m.lmin or q.lmin, lmax = m.lmax or q.lmax,
        skull = m.skull,
        rank = m.rank or q.rank,
        type = m.type,
        map = map,
        sub = q.sub,
    }
end

local mapNames = {}
function ns.MapName(map)
    if not map then return "" end
    if mapNames[map] == nil then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        mapNames[map] = info and info.name or ""
    end
    return mapNames[map]
end

function ns.LevelText(info)
    if info.skull then return "??" end
    if not info.lmin then return "" end
    if info.lmin == info.lmax then return tostring(info.lmin) end
    return info.lmin .. "-" .. info.lmax
end

---------------------------------------------------------------------------
-- Combined drop data
---------------------------------------------------------------------------

-- kills, coin total, items { [itemID] = { times dropped, units } }, your kills, guildmates who added data
function ns.Combined(id, withGuild)
    local m = ns.db.mobs[id]
    local kills, coin, items = 0, 0, {}
    local mine, mates = 0, 0
    local function add(k, c, i)
        kills, coin = kills + (k or 0), coin + (c or 0)
        for item, e in pairs(i or {}) do
            local t = items[item]
            if not t then t = { 0, 0 }; items[item] = t end
            t[1], t[2] = t[1] + (e[1] or 0), t[2] + (e[2] or 0)
        end
    end
    if m then
        add(m.k, m.c, m.i)
        mine = m.k or 0
    end
    if withGuild then
        for _, g in pairs(ns.db.guild) do
            local gm = g.mobs and g.mobs[id]
            if gm and (gm.k or 0) > 0 then
                add(gm.k, gm.c, gm.i)
                mates = mates + 1
            end
        end
    end
    return kills, coin, items, mine, mates
end

-- What each drop of this mob is worth per kill, with the current filters.
-- Returns { gold per kill, coin per kill, kills, rows = { { item, chance, avgQty, unit, perKill, included } },
--           best = itemID with the highest share, incomplete = some prices aren't known yet }
function ns.Value(id, filter)
    filter = filter or ns.db.filter
    local kills, coin, items, mine, mates = ns.Combined(id, filter.guild)
    local s = { kills = kills, mine = mine, mates = mates, rows = {} }
    if kills > 0 then
        s.coin = coin / kills
        s.gold = filter.coin and s.coin or 0
    end
    local bestShare = 0
    for item, e in pairs(items) do
        local unit, from = ns.ItemValue(item)
        local i = ns.Item(item)
        local q = i.q or 1
        local included = filter["q" .. math.min(q, 4)] ~= false and from ~= "quest"
        local row = { item = item, chance = kills > 0 and e[1] / kills or nil, avg = e[1] > 0 and e[2] / e[1] or nil,
                      unit = unit, from = from, included = included }
        if kills > 0 and unit then
            row.perKill = e[2] / kills * unit
            if included then
                s.gold = (s.gold or 0) + row.perKill
                if row.perKill > bestShare then s.best, bestShare = item, row.perKill end
            end
        elseif not unit and included then
            s.incomplete = true
        end
        table.insert(s.rows, row)
    end
    -- Drops QuestieDB knows about that nobody has seen yet.
    local seen = {}
    for _, r in ipairs(s.rows) do seen[r.item] = true end
    for _, item in ipairs(ns.QuestieDrops(id) or {}) do
        if not seen[item] then
            local unit, from = ns.ItemValue(item)
            table.insert(s.rows, { item = item, unit = unit, from = from, possible = true })
        end
    end
    table.sort(s.rows, function(a, b)
        if (a.perKill ~= nil) ~= (b.perKill ~= nil) then return a.perKill ~= nil end
        if a.perKill and b.perKill and a.perKill ~= b.perKill then return a.perKill > b.perKill end
        return a.item < b.item
    end)
    return s
end

---------------------------------------------------------------------------
-- Hunting an item: which mobs drop it
---------------------------------------------------------------------------

-- { [npcID] = true } for every mob known to drop the item: from your kills,
-- your guild's, and QuestieDB's drop lists.
function ns.DroppedBy(item)
    local out = {}
    for id, m in pairs(ns.db.mobs) do if m.i and m.i[item] then out[id] = true end end
    for _, g in pairs(ns.db.guild) do
        for id, gm in pairs(g.mobs or {}) do if gm.i and gm.i[item] then out[id] = true end end
    end
    for _, id in ipairs(ns.QuestieDroppedBy(item) or {}) do out[id] = true end
    return out
end

-- Chance this mob drops the item (with the Guild data filter), and the kills behind it.
function ns.Chance(id, item)
    local kills, _, items = ns.Combined(id, ns.db.filter.guild)
    if kills == 0 then return nil, 0 end
    local e = items[item]
    return (e and e[1] or 0) / kills, kills
end

-- Items whose name contains text: { { item, name }, ... }, at most limit of them.
function ns.SearchItems(text, limit)
    text = text:lower()
    local seen, out = {}, {}
    local function consider(item, name)
        if seen[item] or not name then return end
        seen[item] = true
        if name:lower():find(text, 1, true) then table.insert(out, { item = item, name = name }) end
    end
    for _, m in pairs(ns.db.mobs) do
        for item in pairs(m.i or {}) do consider(item, ns.Item(item).name) end
    end
    for _, g in pairs(ns.db.guild) do
        for _, gm in pairs(g.mobs or {}) do
            for item in pairs(gm.i or {}) do consider(item, ns.Item(item).name) end
        end
    end
    for item, name in pairs(ns.QuestieItemNames()) do consider(item, name) end
    table.sort(out, function(a, b) return a.name < b.name end)
    while limit and #out > limit do table.remove(out) end
    return out
end

function API.GoldPerKill(id) local s = ns.Value(id); return s.gold, s.kills end

-- Whether mobs drop this item: you or your guild have looted it, or QuestieDB
-- lists a hostile mob for it. (Mail King files its sales under "Mob drops".)
local dropSet, dropSetAt
function API.IsDrop(item)
    if not (item and ns.db) then return false end
    local now = GetTime()
    if not dropSet or now - dropSetAt > 10 then
        dropSet, dropSetAt = {}, now
        for _, m in pairs(ns.db.mobs) do for i in pairs(m.i or {}) do dropSet[i] = true end end
        for _, g in pairs(ns.db.guild) do
            for _, gm in pairs(g.mobs or {}) do for i in pairs(gm.i or {}) do dropSet[i] = true end end
        end
    end
    if dropSet[item] then return true end
    local q = ns.QuestieDroppedBy(item)
    return q ~= nil and #q > 0
end
