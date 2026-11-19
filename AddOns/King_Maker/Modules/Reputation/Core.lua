local _, KM = ...
local ns = KM.Module("Reputation", { title = "Reputation King", short = "Reputation", db = "ReputationKingDB" })

-- Reputation (new in 2.10): a sidebar section for the factions that pay in gold, recipes and Favor. The first is the
-- supply faction of your side (Azeroth Commerce Authority / Durotar Supply and Logistics) and its Supply Writs.
--
-- Files:
--   Data/Writs.lua  generated (tools/build_writs.py): the 150 orders, customers, tiers, sealed writs, receipts,
--                   standing unlocks, the faction's recipes and their Merchant's Favor costs
--   Core.lua        saved data, the faction registry, reading standings, Favor, the daily reset, writs done today
--                   (the quest flag and QUEST_TURNED_IN), orders held, daily snapshots, the badge, the login reminder,
--                   /rep and the ReputationKing API
--   Writs.lua       what things cost: orders you hold, rep per gold, the cheapest rep today, Favor shopping, receipts
--   UI.lua          the Reputation overview page, the Supply Writs page, Home cards, Settings
--
-- Saved data (ReputationKingDB, schema 1):
--   chars["First Last-Realm"] = { name, realm, class, side, level, seen,
--       rep[factionID] = { v = rep from Neutral (the game's bar value), s = standing 1-8, at },
--       favor, favorAt,                Merchant's Favor (currency 3402) when last read
--       dayEnd,                        server time this character's "today" ends (the daily reset)
--       done[questID] = time,          writ orders turned in today (cleared at the reset)
--       dayStart[factionID] = v,       rep at the first reading of the day (rep earned today = now - this)
--       held[orderItem] = n,           orders in bags and bank; sealed[tier] = n sealed writs
--       snaps[factionID] = { { t, v } }  one per day (the last reading of that day), for the 7-day pace
--       log = { { t, questID, rep } } }  recent turn-ins
--   learned[questID] = { name, map, x, y }   customers the data didn't know, seen when you turned an order in
--   settings = { remind, badge, diplomat }   ui = { tab, tier, prof, held, notDone, mine }

ReputationKing = { API_VERSION = 1 }
local API = ReputationKing
ns.API = API

local SNAPS_MAX, LOG_MAX, OLD = 90, 200, 90 * 86400
local DAY = 86400

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end
ns.Call = call

local function secret(v)
    if not issecretvalue then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end

function ns.Now() return KM.Now() end

---------------------------------------------------------------------------
-- The data: orders by item and by quest
---------------------------------------------------------------------------

ns.ORDER_LIST, ns.QUEST_ORDER = {}, {}
-- { id, quest, tier, rep, item, count, prof, cust, title }
function ns.Order(id)
    local o = ns.orderCache and ns.orderCache[id]
    if o then return o end
    local d = ns.ORDERS and ns.ORDERS[id]
    if not d then return nil end
    ns.orderCache = ns.orderCache or {}
    o = { id = id, quest = d[1], tier = d[2], rep = d[3], item = d[4], count = d[5] or 1, prof = d[6], cust = d[7], title = d[8] }
    ns.orderCache[id] = o
    return o
end

local function buildIndex()
    if #ns.ORDER_LIST > 0 or not ns.ORDERS then return end
    for id in pairs(ns.ORDERS) do
        local o = ns.Order(id)
        ns.ORDER_LIST[#ns.ORDER_LIST + 1] = o
        ns.QUEST_ORDER[o.quest] = o
    end
    table.sort(ns.ORDER_LIST, function(a, b) return a.id < b.id end)
end
ns.BuildIndex = buildIndex

-- A customer: { name, map, x, y, side, learned } from the data, else from what you saw in game, or nil.
function ns.Customer(o)
    if not o then return nil end
    local c = o.cust ~= nil and ns.CUSTOMERS and ns.CUSTOMERS[o.cust]
    if c then
        return { name = c[1], map = (c[2] or 0) > 0 and c[2] or nil, x = c[3], y = c[4], side = c[5] }
    end
    local l = ns.db and ns.db.learned[o.quest]
    if l then return { name = l.name, map = l.map, x = l.x, y = l.y, learned = true } end
    return nil
end

function ns.ZoneName(map)
    if not map then return nil end
    if C_Map and C_Map.GetMapInfo then
        local info = call(C_Map.GetMapInfo, map)
        if type(info) == "table" and type(info.name) == "string" and not info.name:match("^Map %d") then return info.name end
    end
    return ns.ZONES and ns.ZONES[map] or ("Map " .. map)
end

ns.PROF_NAMES = { [1] = "First Aid", [2] = "Blacksmithing", [3] = "Leatherworking", [4] = "Alchemy", [6] = "Cooking",
    [7] = "Mining", [8] = "Tailoring", [9] = "Engineering", [10] = "Enchanting" }
function ns.ProfName(id) return ns.PROF_NAMES[id] or "?" end

function ns.ItemName(id)
    if not id or id == 0 then return "?" end
    local m = KM.mods.Market
    if m and m.db and m.ItemName then
        local n = call(m.ItemName, id)
        if n and not n:match("^Item %d") then return n end
    end
    if C_Item and C_Item.GetItemNameByID then
        local n = call(C_Item.GetItemNameByID, id)
        if n then return n end
    end
    if C_Item and C_Item.GetItemInfo then
        local n = call(C_Item.GetItemInfo, id)
        if n then return n end
        if C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
    end
    return "Item " .. id
end

function ns.ItemIcon(id)
    if id and C_Item and C_Item.GetItemIconByID then return call(C_Item.GetItemIconByID, id) end
end

---------------------------------------------------------------------------
-- Standings
---------------------------------------------------------------------------

-- Rep from Neutral where each standing starts (the classic thresholds; Exalted ends at 42,999).
ns.STARTS = { [1] = -42000, [2] = -6000, [3] = -3000, [4] = 0, [5] = 3000, [6] = 9000, [7] = 21000, [8] = 42000 }
ns.LABELS = { [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral", [5] = "Friendly", [6] = "Honored",
    [7] = "Revered", [8] = "Exalted" }
local TOP = 42999

function ns.StandingName(s)
    local g = _G["FACTION_STANDING_LABEL" .. tostring(s)]
    if type(g) == "string" and g ~= "" then return g end
    return ns.LABELS[s] or "?"
end

-- Where a rep value stands: { standing, into (rep into it), size (of the standing), toNext, frac, total = value }.
function ns.Standing(v)
    v = math.max(ns.STARTS[1], math.min(TOP, math.floor(tonumber(v) or 0)))
    local s = 1
    for i = 8, 1, -1 do if v >= ns.STARTS[i] then s = i break end end
    local lo = ns.STARTS[s]
    local hi = ns.STARTS[s + 1] or (TOP + 1)
    local size = hi - lo
    local into = v - lo
    return { standing = s, into = into, size = size, toNext = s < 8 and (hi - v) or 0, frac = s < 8 and into / size or 1,
        value = v, toExalted = math.max(0, ns.STARTS[8] - v) }
end

-- Reads a faction from the game: { name, value, standing } or nil (unknown faction, or no API).
function ns.ReadFaction(id)
    if not id then return nil end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local d = call(C_Reputation.GetFactionDataByID, id)
        if type(d) == "table" and d.name and not secret(d.currentStanding) then
            local v = tonumber(d.currentStanding)
            if v then return { name = d.name, value = v, standing = tonumber(d.reaction) or ns.Standing(v).standing } end
        end
    end
    if GetFactionInfoByID then
        local name, _, standing, _, _, value = call(GetFactionInfoByID, id)
        if type(name) == "string" and name ~= "" and not secret(value) and tonumber(value) then
            return { name = name, value = tonumber(value), standing = tonumber(standing) or ns.Standing(value).standing }
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- The faction registry: the overview page lists every faction registered here that applies to your side
---------------------------------------------------------------------------
--   ns.RegisterFaction{ id, order, name = string | fn(side), factionID = number | fn(side) -> id, sides = { Alliance =
--                       true } (nil: both), page = "<page id>", unlocks = fn(standing) -> { { text, favor } },
--                       currency = id }

ns.factions = {}
function ns.RegisterFaction(f)
    if type(f) ~= "table" or not f.id then return end
    for i, old in ipairs(ns.factions) do
        if old.id == f.id then ns.factions[i] = f; return end
    end
    ns.factions[#ns.factions + 1] = f
    table.sort(ns.factions, function(a, b) return (a.order or 50) < (b.order or 50) end)
end
API.RegisterFaction = function(f) return ns.RegisterFaction(f) end

function ns.Side(c)
    if c then return c.side end
    if UnitFactionGroup then
        local s = UnitFactionGroup("player")
        if s == "Alliance" or s == "Horde" then return s end
    end
    return nil
end

local function resolve(v, side) if type(v) == "function" then return call(v, side) end return v end

-- The factions tracked for a side: { { def, factionID, name } }.
function ns.Tracked(side)
    side = side or ns.Side()
    local out = {}
    for _, f in ipairs(ns.factions) do
        if not f.sides or (side and f.sides[side]) then
            local fid = resolve(f.factionID, side)
            if fid then out[#out + 1] = { def = f, factionID = fid, name = resolve(f.name, side) or ("Faction " .. fid) } end
        end
    end
    return out
end

-- The supply faction for a side ("Alliance" | "Horde"): ns.SIDES entry, or nil.
function ns.Supply(side)
    side = side or ns.Side()
    return side and ns.SIDES and ns.SIDES[side] or nil
end

-- The supply faction's standing unlocks; Favor recipes go in by their cost (the guides put 30-45 at Neutral,
-- 60-120 at Friendly, 180+ at Honored).
function ns.StandingForFavor(favor)
    favor = favor or 0
    if favor >= 180 then return 6 elseif favor >= 60 then return 5 end
    return 4
end

function ns.Unlocks(standing) return ns.STANDINGS and ns.STANDINGS[standing] or {} end

-- What the next standing up brings: standing id and its list, or nil at Exalted.
function ns.NextUnlock(standing)
    for s = math.max(4, (standing or 4) + 1), 8 do
        local list = ns.Unlocks(s)
        if #list > 0 then return s, list end
    end
end

ns.RegisterFaction({
    id = "supply", order = 10, page = "writs", currency = 3402,
    name = function(side) local s = ns.Supply(side) return s and s.name end,
    factionID = function(side) local s = ns.Supply(side) return s and s.faction end,
    unlocks = function(standing) return ns.Unlocks(standing) end,
})

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local function charTables(c)
    c.rep = c.rep or {}
    c.done = c.done or {}
    c.dayStart = c.dayStart or {}
    c.held = c.held or {}
    c.sealed = c.sealed or {}
    c.snaps = c.snaps or {}
    c.log = c.log or {}
end

function ns.InitDB()
    ReputationKingDB = ReputationKingDB or {}
    local db = ReputationKingDB
    if not db.version then db.version = 1 end
    db.chars = db.chars or {}
    db.learned = db.learned or {}
    db.settings = db.settings or {}
    local s = db.settings
    if s.remind == nil then s.remind = true end
    if s.badge == nil then s.badge = true end
    s.diplomat = math.max(0, math.min(5, math.floor(tonumber(s.diplomat) or 0)))
    db.ui = db.ui or {}
    local u = db.ui
    if u.tab ~= "held" and u.tab ~= "cheap" and u.tab ~= "favor" and u.tab ~= "all" and u.tab ~= "chars" then u.tab = "held" end
    if u.held == nil then u.held = false end
    if u.notDone == nil then u.notDone = false end
    if u.mine == nil then u.mine = false end
    for _, c in pairs(db.chars) do charTables(c) end
    ns.db = db
    buildIndex()
end

function ns.Me()
    local key = KM.Char()
    local c = ns.db.chars[key]
    if not c then
        c = {}
        ns.db.chars[key] = c
    end
    charTables(c)
    return c, key
end

function ns.RenameChar(old, new)
    KM.MoveKey(ns.db.chars, old, new)
    local c = ns.db.chars[new]
    if c then c.name = KM.PlayerName() end
end

function ns.Forget(key)
    if not (ns.db and key and ns.db.chars[key]) or key == KM.Char() then return false end
    ns.db.chars[key] = nil
    ns.Changed()
    return true
end

function ns.FindChar(text)
    if not text or text == "" then return nil end
    local q = text:lower()
    for key in pairs(ns.db.chars) do if key:lower() == q then return key end end
    for key, c in pairs(ns.db.chars) do
        if (c.name or ""):lower() == q or ((c.name or key):lower():match("^(%S+)")) == q then return key end
    end
end

function ns.CharName(c, key) return (c and c.name) or (key and key:match("^(.-)%-")) or key or "?" end

---------------------------------------------------------------------------
-- The daily reset
---------------------------------------------------------------------------

-- Seconds until the daily quest reset, from the game (never hard-coded). Second value: true when guessed.
function ns.SecondsToReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local s = call(C_DateAndTime.GetSecondsUntilDailyReset)
        if type(s) == "number" and s > 0 and not secret(s) then return s, false end
    end
    if GetQuestResetTime then
        local s = call(GetQuestResetTime)
        if type(s) == "number" and s > 0 and not secret(s) then return s, false end
    end
    local now = ns.Now()
    return (math.floor(now / DAY) + 1) * DAY - now, true   -- no API: the next UTC midnight, a guess
end

function ns.DayEnd()
    local s = ns.SecondsToReset()
    return ns.Now() + math.floor(s + 0.5)
end

-- Is this character's "today" still today (saved before the last reset or not)?
function ns.IsToday(c) return c and c.dayEnd and c.dayEnd > ns.Now() or false end

-- Rolls this character over to a new day when the reset has passed: done and the day's start are cleared.
-- Returns true when it rolled.
function ns.CheckDay(c)
    c = c or ns.Me()
    local now = ns.Now()
    local rolled = false
    if not c.dayEnd or c.dayEnd <= now then
        c.done, c.dayStart = {}, {}
        c.dayEnd = ns.DayEnd()
        rolled = true
    else
        local fresh = ns.DayEnd()
        if fresh < c.dayEnd - 300 then c.dayEnd = fresh end   -- the game knows better than an old guess
    end
    return rolled
end

---------------------------------------------------------------------------
-- Reading the character you're on
---------------------------------------------------------------------------

local function itemCount(id)
    if C_Item and C_Item.GetItemCount then
        local n = call(C_Item.GetItemCount, id, true)
        if type(n) == "number" and not secret(n) then return n end
    elseif GetItemCount then
        local n = call(GetItemCount, id, true)
        if type(n) == "number" then return n end
    end
    return nil
end
ns.ItemCount = itemCount

function ns.ReadFavor(c)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return end
    local info = call(C_CurrencyInfo.GetCurrencyInfo, ns.CURRENCY or 3402)
    if type(info) == "table" and type(info.quantity) == "number" and not secret(info.quantity) then
        c.favor, c.favorAt = info.quantity, ns.Now()
    end
end

-- Orders and sealed writs in bags and bank. True when the game answered.
function ns.ReadHeld(c)
    if not ns.ORDERS then return false end
    local held, any = {}, false
    for id in pairs(ns.ORDERS) do
        local n = itemCount(id)
        if n == nil then return false end
        any = true
        if n > 0 then held[id] = n end
    end
    if not any then return false end
    c.held = held
    local sealed = {}
    for id, tier in pairs(ns.SEALED or {}) do
        local n = itemCount(id)
        if n and n > 0 then sealed[tier] = (sealed[tier] or 0) + n end
    end
    c.sealed = sealed
    return true
end

-- Writ quests the game says are done today (its flag lags a turn-in, so QUEST_TURNED_IN records too).
function ns.ReadDone(c)
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return end
    local now = ns.Now()
    for q in pairs(ns.QUEST_ORDER) do
        if not c.done[q] and call(C_QuestLog.IsQuestFlaggedCompleted, q) == true then c.done[q] = now end
    end
end

local function snap(c, fid, v)
    local list = c.snaps[fid] or {}
    c.snaps[fid] = list
    local last = list[#list]
    if last and last.d == c.dayEnd then
        last.v, last.t = v, ns.Now()
    else
        list[#list + 1] = { t = ns.Now(), v = v, d = c.dayEnd }
        while #list > SNAPS_MAX do table.remove(list, 1) end
    end
end

function ns.ReadRep(c)
    for _, f in ipairs(ns.Tracked(c.side)) do
        local r = ns.ReadFaction(f.factionID)
        if r then
            local e = c.rep[f.factionID] or {}
            c.rep[f.factionID] = e
            e.v, e.s, e.at, e.name = r.value, r.standing, ns.Now(), r.name
            if c.dayStart[f.factionID] == nil then c.dayStart[f.factionID] = r.value end
            snap(c, f.factionID, r.value)
        end
    end
end

-- Reads everything for the character you're on. Returns it.
function ns.Snapshot()
    if not ns.db then return end
    local c, key = ns.Me()
    c.name = KM.PlayerName()
    c.realm = (GetRealmName and GetRealmName()) or c.realm or ""
    if UnitClass then
        local _, class = UnitClass("player")
        c.class = class or c.class
    end
    c.side = ns.Side() or c.side
    if UnitLevel then c.level = UnitLevel("player") or c.level end
    c.seen = ns.Now()
    ns.CheckDay(c)
    ns.ReadDone(c)
    ns.ReadRep(c)
    ns.ReadFavor(c)
    ns.ReadHeld(c)
    return c, key
end

---------------------------------------------------------------------------
-- What a character did and holds
---------------------------------------------------------------------------

-- Writ orders done today: count, rep (data rep x Diplomat).
function ns.DoneToday(c)
    if not ns.IsToday(c) then return 0, 0 end
    local n, rep = 0, 0
    for q in pairs(c.done or {}) do
        local o = ns.QUEST_ORDER[q]
        if o then n, rep = n + 1, rep + ns.OrderRep(o) end
    end
    return n, rep
end

function ns.IsDone(c, o) return ns.IsToday(c) and c.done[o.quest] ~= nil end

-- Rep earned today with the supply faction: what the bar moved since the first reading today, or the writs' rep
-- when that's more (you turned some in before King Maker first read the bar today).
function ns.RepToday(c)
    if not ns.IsToday(c) then return 0 end
    local s = ns.Supply(c.side)
    local fid = s and s.faction
    local e = fid and c.rep[fid]
    local moved = (e and c.dayStart[fid]) and math.max(0, e.v - c.dayStart[fid]) or 0
    local _, writs = ns.DoneToday(c)
    return math.max(moved, writs)
end

-- Orders this character holds that it can still turn in today: { order, n }, sorted by tier then name.
function ns.HeldNotDone(c)
    c = c or ns.Me()
    local out = {}
    for id, n in pairs(c.held or {}) do
        local o = ns.Order(id)
        if o and n > 0 and not ns.IsDone(c, o) then out[#out + 1] = { order = o, n = n } end
    end
    local rank = { J = 1, E = 2, A = 3 }
    table.sort(out, function(a, b)
        if a.order.tier ~= b.order.tier then return (rank[a.order.tier] or 9) < (rank[b.order.tier] or 9) end
        return a.order.title < b.order.title
    end)
    return out
end

-- Expected rep for an order: its tier's rep, with the Diplomat perk (2% a rank) from Settings.
function ns.OrderRep(o)
    local bonus = 1 + 0.02 * ((ns.db and ns.db.settings.diplomat) or 0)
    return math.floor((o.rep or 0) * bonus + 0.5)
end

-- The supply faction's standing for a character from saved data: ns.Standing table plus at, or nil.
function ns.CharStanding(c)
    local s = ns.Supply(c and c.side)
    local e = s and c.rep[s.faction]
    if not e then return nil end
    local st = ns.Standing(e.v)
    st.at = e.at
    return st
end

-- Rep a day over the last `days` (default 7), from the daily snapshots: per day, days covered; nil without two.
function ns.Pace(c, fid, days)
    days = days or 7
    local list = c and c.snaps[fid]
    if not list or #list < 2 then return nil end
    local last = list[#list]
    local since = last.t - days * DAY
    local first
    for _, p in ipairs(list) do
        if p.t >= since - 3600 then first = p break end
    end
    if not first or first == last then first = list[math.max(1, #list - 1)] end
    local span = math.max(1, (last.t - first.t) / DAY)
    if last.t - first.t < 3600 then return nil end
    return math.max(0, (last.v - first.v) / span), span
end

-- Days to the next standing at that pace, or nil.
function ns.ETA(st, pace)
    if not (st and pace and pace > 0) or st.standing >= 8 then return nil end
    return st.toNext / pace
end

-- One row per character: { key, c, me, side, done, doneRep, today (rep), held (not done), standing, favor, old }.
function ns.CharRows()
    local out, now, me = {}, ns.Now(), KM.Char()
    for key, c in pairs(ns.db and ns.db.chars or {}) do
        local done, doneRep = ns.DoneToday(c)
        local st = ns.CharStanding(c)
        if st or done > 0 or next(c.held or {}) then
            out[#out + 1] = { key = key, c = c, me = key == me, side = c.side, done = done, doneRep = doneRep,
                today = ns.RepToday(c), held = #ns.HeldNotDone(c), standing = st, favor = c.favor,
                old = (c.seen or 0) < now - OLD, stale = not ns.IsToday(c) }
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if a.old ~= b.old then return b.old end
        local av, bv = a.standing and a.standing.value or -1e9, b.standing and b.standing.value or -1e9
        if av ~= bv then return av > bv end
        return a.key < b.key
    end)
    return out
end

---------------------------------------------------------------------------
-- Turn-ins: recorded at QUEST_TURNED_IN (the flag can lag); a customer the data doesn't know is learned here
---------------------------------------------------------------------------

local pendingNpc   -- { quest, name, map, x, y } from QUEST_COMPLETE (the turn-in window is open there)

function ns.OnQuestComplete()
    pendingNpc = nil
    local q = GetQuestID and call(GetQuestID)
    if not (q and ns.QUEST_ORDER[q]) then return end
    local name = UnitName and call(UnitName, "npc")
    local map = C_Map and C_Map.GetBestMapForUnit and call(C_Map.GetBestMapForUnit, "player")
    local x, y
    if map and C_Map.GetPlayerMapPosition then
        local pos = call(C_Map.GetPlayerMapPosition, map, "player")
        if pos and pos.GetXY then x, y = pos:GetXY() end
    end
    pendingNpc = { quest = q, name = name, map = map, x = x and math.floor(x * 1000 + 0.5) / 10, y = y and math.floor(y * 1000 + 0.5) / 10 }
end

function ns.OnTurnedIn(q)
    local o = q and ns.QUEST_ORDER[q]
    if not (o and ns.db) then return false end
    local c = ns.Me()
    ns.CheckDay(c)
    local now = ns.Now()
    c.done[q] = now
    table.insert(c.log, { t = now, q = q, rep = ns.OrderRep(o) })
    while #c.log > LOG_MAX do table.remove(c.log, 1) end
    if pendingNpc and pendingNpc.quest == q and pendingNpc.name and not (ns.CUSTOMERS and o.cust ~= nil and ns.CUSTOMERS[o.cust]) then
        ns.db.learned[q] = { name = pendingNpc.name, map = pendingNpc.map, x = pendingNpc.x, y = pendingNpc.y }
    end
    pendingNpc = nil
    ns.Changed()
    return true
end

---------------------------------------------------------------------------
-- The badge, reminders, other addons
---------------------------------------------------------------------------

function ns.Badge()
    if not (ns.db and ns.db.settings.badge) then return nil end
    local list = ns.HeldNotDone()
    if #list == 0 then return nil end
    local names, rep = {}, 0
    for _, h in ipairs(list) do
        names[#names + 1] = h.order.title
        rep = rep + ns.OrderRep(h.order)
    end
    local tip = "You hold " .. #list .. " writ order" .. (#list == 1 and "" or "s") .. " you can still turn in today (+"
        .. KM.Commas(rep) .. " rep): " .. table.concat(names, ", ") .. "."
    if KM.BadgeTables then return { count = #list, color = "red", tip = tip } end
    return tostring(#list)
end

function ns.LoginLine()
    if not (ns.db and ns.db.settings.remind) then return nil end
    local list = ns.HeldNotDone()
    if #list == 0 then return nil end
    local names, rep = {}, 0
    for i, h in ipairs(list) do
        if i <= 5 then names[#names + 1] = h.order.title end
        rep = rep + ns.OrderRep(h.order)
    end
    if #list > 5 then names[#names + 1] = "and " .. (#list - 5) .. " more" end
    local text = "you hold " .. #list .. " writ order" .. (#list == 1 and "" or "s") .. " not turned in today (+"
        .. KM.Commas(rep) .. " rep): " .. table.concat(names, ", ") .. ". /rep"
    KM.Print(ns, text)
    return text
end

local callbacks = {}
function API.RegisterCallback(owner, fn)
    if owner == nil or type(fn) ~= "function" then return false end
    callbacks[owner] = fn
    return true
end
function API.UnregisterCallback(owner) if owner ~= nil then callbacks[owner] = nil end end

local lastBadge
function ns.Changed()
    local b = ns.Badge()
    local sig = type(b) == "table" and (b.count .. (b.tip or "")) or tostring(b)
    if sig ~= lastBadge then
        lastBadge = sig
        if KM.RefreshBadges then KM.Safe(KM.RefreshBadges) end
    end
    if KM.IsShown("writs") then KM.Refresh("writs") end
    if KM.IsShown("reputation") then KM.Refresh("reputation") end
    for _, fn in pairs(callbacks) do pcall(fn, "CHANGED") end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local pend = {}
local function soon(key, delay, fn)
    if pend[key] then return end
    pend[key] = true
    C_Timer.After(delay, function() pend[key] = nil; KM.Safe(fn) end)
end

local ticker
function ns.Tick()
    if not ns.db then return end
    local c = ns.db.chars[KM.Char()]
    if c and ns.CheckDay(c) then
        ns.ReadDone(c)
        ns.ReadRep(c)
        ns.Changed()
    end
end

local function refreshAll() ns.Snapshot(); ns.Changed() end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "PLAYER_LOGOUT", "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE", "QUEST_TURNED_IN",
    "QUEST_COMPLETE", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "CURRENCY_DISPLAY_UPDATE")
f:SetScript("OnEvent", function(_, event, a1)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        KM.Safe(ns.Snapshot)
        C_Timer.After(3, function() KM.Safe(refreshAll) end)            -- quest flags and rep can come late
        C_Timer.After(8, function() KM.Safe(ns.LoginLine) end)
        if not ticker and C_Timer.NewTicker then ticker = C_Timer.NewTicker(60, function() KM.Safe(ns.Tick) end) end
    elseif event == "PLAYER_LOGOUT" then
        local c = ns.db.chars[KM.Char()]
        if c then c.seen = ns.Now() end
    elseif event == "QUEST_COMPLETE" then
        KM.Safe(ns.OnQuestComplete)
    elseif event == "QUEST_TURNED_IN" then
        if not secret(a1) and type(a1) == "number" and ns.QUEST_ORDER[a1] then
            KM.Safe(ns.OnTurnedIn, a1)
            soon("held", 1, refreshAll)
        end
    elseif event == "UPDATE_FACTION" or event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        soon("rep", 1, function() local c = ns.Me(); ns.CheckDay(c); ns.ReadRep(c); ns.Changed() end)
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        soon("favor", 1, function() ns.ReadFavor(ns.Me()); if KM.IsShown("writs") then KM.Refresh("writs") end end)
    else -- bags and bank
        soon("held", 1, function() local c = ns.Me(); if ns.ReadHeld(c) then ns.Changed() end end)
    end
end)

---------------------------------------------------------------------------
-- The API (functions only)
---------------------------------------------------------------------------

-- Standing with a faction (default: your supply faction) for the character you're on, from saved data:
-- standing id, rep into it, its size, rep from Neutral; nil when never read.
function API.GetStanding(factionID)
    if not ns.db then return nil end
    local c = ns.Me()
    local s = ns.Supply(c.side)
    factionID = factionID or (s and s.faction)
    local e = factionID and c.rep[factionID]
    if not e then return nil end
    local st = ns.Standing(e.v)
    return st.standing, st.into, st.size, st.value
end

-- Writ orders done today and the rep they gave, for a character key (default: you).
function API.DoneToday(key)
    if not ns.db then return 0, 0 end
    local c = ns.db.chars[key or KM.Char()]
    if not c then return 0, 0 end
    return ns.DoneToday(c)
end

-- Is this writ quest (or order item) done today on the character you're on?
function API.IsDoneToday(id)
    if not ns.db then return false end
    local o = ns.Order(id) or ns.QUEST_ORDER[id]
    return o and ns.IsDone(ns.Me(), o) or false
end

-- How many orders you hold that you can still turn in today.
function API.HeldCount()
    if not ns.db then return 0 end
    return #ns.HeldNotDone()
end

-- An order by its item id: { quest, tier, rep, item, count, prof, title } (a copy), or nil.
function API.GetOrder(id)
    local o = ns.Order(id)
    if not o then return nil end
    return { quest = o.quest, tier = o.tier, rep = o.rep, item = o.item, count = o.count, prof = o.prof, title = o.title }
end

-- Merchant's Favor on a character (default: you), from the last reading.
function API.GetFavor(key)
    local c = ns.db and ns.db.chars[key or KM.Char()]
    return c and c.favor or nil
end

function API.SecondsToReset() return (ns.SecondsToReset()) end

---------------------------------------------------------------------------
-- /rep
---------------------------------------------------------------------------

function ns.Toggle(show, page)
    if not ns.db then return end
    page = page or "writs"
    if show == nil then show = not KM.IsShown(page) end
    if show then KM.Show(page) elseif KM.IsShown(page) then KM.Toggle(false) end
end

function ns.Duration(s)
    if not s then return "-" end
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
    if d > 0 then return d .. "d" .. (h > 0 and (" " .. h .. "h") or "") end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

function ns.PrintStatus()
    local c = ns.Snapshot()
    local s = ns.Supply(c.side)
    if not s then KM.Print(ns, "no supply faction for this character (Alliance or Horde only).") return end
    local st = ns.CharStanding(c)
    local done = ns.DoneToday(c)
    KM.Print(ns, s.name .. ": " .. (st and (ns.StandingName(st.standing) .. " " .. KM.Commas(st.into) .. "/" .. KM.Commas(st.size)) or "not met yet")
        .. "; " .. done .. " writ" .. (done == 1 and "" or "s") .. " done today, +" .. KM.Commas(ns.RepToday(c)) .. " rep; Merchant's Favor "
        .. tostring(c.favor or "?") .. "; reset in " .. ns.Duration((ns.SecondsToReset())) .. ".")
    local list = ns.HeldNotDone(c)
    for _, h in ipairs(list) do
        local cust = ns.Customer(h.order)
        KM.Print(ns, "  " .. h.order.title .. " (" .. (ns.TIERS[h.order.tier] and ns.TIERS[h.order.tier].name or "?") .. ", +" .. ns.OrderRep(h.order)
            .. "): deliver " .. h.order.count .. "x " .. ns.ItemName(h.order.item) .. (cust and (" to " .. (cust.name or "?") .. (cust.map and (" in " .. ns.ZoneName(cust.map)) or "")) or ""))
    end
end

function ns.Debug()
    local c = ns.Me()
    local s = ns.Supply(c.side)
    KM.Print(ns, "side " .. tostring(c.side) .. ", faction " .. tostring(s and s.faction) .. "; C_Reputation " .. tostring(C_Reputation ~= nil)
        .. ", GetFactionInfoByID " .. tostring(GetFactionInfoByID ~= nil) .. ", C_DateAndTime " .. tostring(C_DateAndTime ~= nil)
        .. ", GetQuestResetTime " .. tostring(GetQuestResetTime ~= nil) .. ", C_CurrencyInfo " .. tostring(C_CurrencyInfo ~= nil))
    local r = s and ns.ReadFaction(s.faction)
    KM.Print(ns, "faction reads: " .. (r and (r.name .. " " .. r.value .. " (standing " .. r.standing .. ")") or "nothing"))
    local secs, guessed = ns.SecondsToReset()
    KM.Print(ns, "reset in " .. math.floor(secs) .. "s" .. (guessed and " (guessed: no API)" or "") .. "; day ends " .. tostring(c.dayEnd))
    local n = 0
    for q in pairs(c.done) do n = n + 1; if n <= 10 then KM.Print(ns, "done today: " .. q .. " " .. (ns.QUEST_ORDER[q] and ns.QUEST_ORDER[q].title or "")) end end
    local held = 0
    for _ in pairs(c.held) do held = held + 1 end
    KM.Print(ns, n .. " done today; " .. held .. " different orders held; favor " .. tostring(c.favor))
end

local function help()
    KM.Print(ns, "/rep   open the Supply Writs page (or /km writs)")
    KM.Print(ns, "/rep overview   every tracked faction")
    KM.Print(ns, "/rep status   standing, writs done today and the orders you hold, in chat")
    KM.Print(ns, "/rep remind on|off   the login reminder about orders you hold")
    KM.Print(ns, "/rep badge on|off   the red count on the sidebar")
    KM.Print(ns, "/rep forget First Last   forget a character")
    KM.Print(ns, "/rep debug   what the game reports (for bug reports)")
end

SLASH_REPUTATIONKING1 = "/rep"
SLASH_REPUTATIONKING2 = "/reputation"
SlashCmdList.REPUTATIONKING = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local function onOff(cur) return rest:lower() == "on" or (rest:lower() ~= "off" and not cur) end
    if cmd == "" or cmd == "writs" or cmd == "show" then
        ns.Toggle(nil, "writs")
    elseif cmd == "overview" or cmd == "factions" then
        ns.Toggle(nil, "reputation")
    elseif cmd == "status" or cmd == "list" then
        ns.PrintStatus()
    elseif cmd == "remind" then
        ns.db.settings.remind = onOff(ns.db.settings.remind)
        KM.Print(ns, "login reminder " .. (ns.db.settings.remind and "on." or "off."))
    elseif cmd == "badge" then
        ns.db.settings.badge = onOff(ns.db.settings.badge)
        ns.Changed()
        KM.Print(ns, "sidebar count " .. (ns.db.settings.badge and "on." or "off."))
    elseif cmd == "forget" and rest ~= "" then
        local key = ns.FindChar(rest)
        if key and ns.Forget(key) then KM.Print(ns, "forgot " .. key .. ".") else KM.Print(ns, "no other character called " .. rest .. ".") end
    elseif cmd == "debug" then
        ns.Debug()
    else
        help()
    end
end
