local _, KM = ...
local ns = KM.Module("Reals", { title = "Reals", short = "Reals", db = "RealsKingDB" })

-- Reals (new in 2.13): Tarnished Undermine Reals from the level 55+ dungeon bosses. Each boss gives each character one
-- a day; this keeps track of which ones you've looted since the daily reset, and reminds you to loot a boss's Real.
--
-- Files:
--   Data.lua   generated (tools/build_reals.py): the dungeons and their bosses (npc ids, levels)
--   Core.lua   saved data, the daily reset, how many you hold, reading loot windows (which boss a Real came from),
--              boss kills and the reminders, learning bosses the data has wrong, /reals and the RealsKing API
--   UI.lua     the Reals page (dungeons green/red, a dungeon's bosses), the toast, Home, Settings
--
-- How a Real is recognised: a loot slot whose link is item 226404 or the Real's currency, or whose name is the Real's.
-- GetLootSourceInfo says which corpse the slot is from, so it's credited to that exact boss when the slot is taken
-- (LOOT_SLOT_CLEARED), or when the window closes and your Reals went up. Never the combat log.
--
-- Saved data (RealsKingDB, schema 1):
--   chars["First Last-Realm"] = { name, class, level, seen, dayEnd, got[npc] = time (today), held, cap, heldAt }
--   drops[npc] = n        Reals seen on that boss's corpse (any character): it drops them
--   misses[npc] = n       corpses looted with no Real while it was still due: after MISS_LIMIT and no drop ever, the
--                         boss is shown as "no Real seen" and stops counting
--   learned[npc] = { name, dungeon }   a boss a Real came from that the data didn't list
--   currency               the Real's currency id, once the game has shown it
--   settings = { notify, leave }   ui = { char, dungeon }

RealsKing = { API_VERSION = 1 }
local API = RealsKing
ns.API = API

ns.REAL_ITEM = 226404
ns.REAL_NAME = "Tarnished Undermine Real"
ns.MISS_LIMIT = 3
local DAY = 86400
local OLD = 90 * 86400

local plain = function(v) return KM.Plain and KM.Plain(v) or v end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end
ns.Call = call

function ns.Now() return KM.Now() end

---------------------------------------------------------------------------
-- The bosses
---------------------------------------------------------------------------

ns.BOSS = {}        -- [npc] = { npc, name, level, optional, dungeon, learned }
local function index()
    ns.BOSS = {}
    for _, d in ipairs(ns.DUNGEONS or {}) do
        d.bosses = d.bosses or {}
        for _, b in ipairs(d.bosses) do
            b.dungeon = d
            ns.BOSS[b.npc] = b
        end
    end
end

local function findDungeon(name)
    if not name then return nil end
    for _, d in ipairs(ns.DUNGEONS) do if d.name == name then return d end end
end

-- A boss the data didn't have joins its dungeon (made up from the instance's name when the data has none of it).
local function addLearned(npc, info)
    if ns.BOSS[npc] then return ns.BOSS[npc] end
    local d = findDungeon(info.dungeon)
    if not d then
        d = { name = info.dungeon or "Other", level = "", bosses = {}, learned = true }
        table.insert(ns.DUNGEONS, d)
    end
    local b = { npc = npc, name = info.name or ("Boss " .. npc), level = info.level, dungeon = d, learned = true }
    table.insert(d.bosses, b)
    ns.BOSS[npc] = b
    return b
end

-- A boss by an encounter's name (ENCOUNTER_END, BOSS_KILL): its own name, or one of a pair's ("Morphaz & Hazzas").
function ns.BossByName(name)
    name = plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local low = name:lower()
    for _, b in pairs(ns.BOSS) do if b.name:lower() == low then return b end end
    for _, b in pairs(ns.BOSS) do
        local n = b.name:lower()
        if n:find(low, 1, true) or low:find(n, 1, true) then return b end
    end
end

-- The dungeon you're in, by the instance's name: the data's dungeon of that name, or the first one that starts with
-- it ("Dire Maul" -> a Dire Maul wing). Second value: the instance name.
function ns.CurrentDungeon()
    if not (IsInInstance and plain(IsInInstance())) then return nil end
    local name = GetInstanceInfo and plain((GetInstanceInfo()))
    if type(name) ~= "string" or name == "" then return nil end
    if ns.visit and ns.visit.dungeon and ns.visit.dungeon.name:find(name, 1, true) == 1 then return ns.visit.dungeon, name end
    for _, d in ipairs(ns.DUNGEONS) do if d.name == name then return d, name end end
    for _, d in ipairs(ns.DUNGEONS) do if d.name:find(name, 1, true) == 1 then return d, name end end
    return nil, name
end

-- Does this boss still count? Bosses that never showed a Real after MISS_LIMIT looted kills don't.
function ns.NoDrop(b)
    if not (ns.db and b) then return false end
    return (ns.db.drops[b.npc] or 0) == 0 and (ns.db.misses[b.npc] or 0) >= ns.MISS_LIMIT
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local function charTables(c) c.got = c.got or {} end

function ns.InitDB()
    RealsKingDB = RealsKingDB or {}
    local db = RealsKingDB
    if not db.version then db.version = 1 end
    db.chars = db.chars or {}
    db.drops = db.drops or {}
    db.misses = db.misses or {}
    db.learned = db.learned or {}
    db.settings = db.settings or {}
    local s = db.settings
    if s.notify == nil then s.notify = true end
    if s.leave == nil then s.leave = true end
    db.ui = db.ui or {}
    for _, c in pairs(db.chars) do charTables(c) end
    ns.db = db
    index()
    for npc, info in pairs(db.learned) do addLearned(npc, info) end
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
    if ns.db.ui.char == old then ns.db.ui.char = new end
end

function ns.Forget(key)
    if not (ns.db and key and ns.db.chars[key]) or key == KM.Char() then return false end
    ns.db.chars[key] = nil
    if ns.db.ui.char == key then ns.db.ui.char = nil end
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

-- The character the page shows: the one picked, else you.
function ns.Shown()
    local key = ns.db.ui.char
    if key and ns.db.chars[key] then return ns.db.chars[key], key end
    return ns.Me()
end

---------------------------------------------------------------------------
-- The daily reset: 10 a.m. New York time (KM.SecondsToDailyReset, Core.lua)
---------------------------------------------------------------------------

-- Second value: true when guessed (never, since 2.14.0; kept for callers).
function ns.SecondsToReset()
    return KM.SecondsToDailyReset(ns.Now()), false
end

function ns.IsToday(c) return c and c.dayEnd and c.dayEnd > ns.Now() or false end

-- Rolls a character over to a new day once the reset has passed. True when it rolled.
function ns.CheckDay(c)
    c = c or ns.Me()
    local now = ns.Now()
    local fresh = now + math.floor(ns.SecondsToReset() + 0.5)
    if not c.dayEnd or c.dayEnd <= now then
        c.got, c.dayEnd = {}, fresh
        return true
    end
    if fresh < c.dayEnd - 300 then c.dayEnd = fresh end
    return false
end

-- Looted today from this boss (a character from saved data: nothing once its day is over).
function ns.Got(c, npc) return ns.IsToday(c) and c.got[npc] or nil end

---------------------------------------------------------------------------
-- How many you hold: the currency once its id is known, else the item
---------------------------------------------------------------------------

local function isRealName(n) n = plain(n) return type(n) == "string" and n == ns.REAL_NAME end

-- Finds the Real on the currency tab: its id (also from a link), or nil.
function ns.FindCurrency()
    if ns.db.currency then return ns.db.currency end
    local ci = C_CurrencyInfo
    if not (ci and ci.GetCurrencyListSize and ci.GetCurrencyListInfo) then return nil end
    local n = plain(call(ci.GetCurrencyListSize)) or 0
    for i = 1, n do
        local info = call(ci.GetCurrencyListInfo, i)
        if type(info) == "table" and isRealName(info.name) then
            local id = tonumber(info.currencyID)
            if not id and ci.GetCurrencyListLink then
                local link = plain(call(ci.GetCurrencyListLink, i))
                id = type(link) == "string" and tonumber(link:match("currency:(%d+)"))
            end
            if id then ns.db.currency = id end
            return id
        end
    end
end

-- Reals held and the cap (nil when unknown), read from the game.
function ns.ReadHeld()
    local id = ns.FindCurrency()
    if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = call(C_CurrencyInfo.GetCurrencyInfo, id)
        local q = type(info) == "table" and plain(info.quantity)
        if type(q) == "number" then
            local cap = plain(info.maxQuantity)
            return q, (type(cap) == "number" and cap > 0) and cap or nil
        end
    end
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    local n = plain(call(get, ns.REAL_ITEM, true))
    if type(n) == "number" and (n > 0 or not id) then return n, nil end
    return nil
end

function ns.Snapshot()
    if not ns.db then return end
    local c, key = ns.Me()
    c.name = KM.PlayerName()
    if UnitClass then local _, class = UnitClass("player"); c.class = class or c.class end
    if UnitLevel then c.level = UnitLevel("player") or c.level end
    c.seen = ns.Now()
    ns.CheckDay(c)
    local held, cap = ns.ReadHeld()
    if held then c.held, c.cap, c.heldAt = held, cap or c.cap, ns.Now() end
    return c, key
end

---------------------------------------------------------------------------
-- Where you stand: per dungeon and per character
---------------------------------------------------------------------------

-- A dungeon for a character: { d, bosses = { { b, got, noDrop } }, total, done, left }. Optional bosses and bosses
-- with no Real seen only count once looted.
function ns.DungeonState(c, d)
    local st = { d = d, bosses = {}, total = 0, done = 0, left = 0 }
    for _, b in ipairs(d.bosses) do
        local got = ns.Got(c, b.npc)
        local no = ns.NoDrop(b)
        st.bosses[#st.bosses + 1] = { b = b, got = got, noDrop = no }
        if got then
            st.total, st.done = st.total + 1, st.done + 1
        elseif not (no or b.optional) then
            st.total, st.left = st.total + 1, st.left + 1
        end
    end
    return st
end

function ns.States(c)
    local out = {}
    for _, d in ipairs(ns.DUNGEONS) do
        if #d.bosses > 0 then out[#out + 1] = ns.DungeonState(c, d) end
    end
    return out
end

-- Reals looted today and bosses still to loot, for a character.
function ns.Totals(c)
    local got, left, dungeonsLeft = 0, 0, 0
    for _, st in ipairs(ns.States(c)) do
        got, left = got + st.done, left + st.left
        if st.left > 0 then dungeonsLeft = dungeonsLeft + 1 end
    end
    return got, left, dungeonsLeft
end

function ns.CharRows()
    local out, now, me = {}, ns.Now(), KM.Char()
    for key, c in pairs(ns.db.chars) do
        local got = ns.Totals(c)
        out[#out + 1] = { key = key, c = c, me = key == me, got = got, old = (c.seen or 0) < now - OLD }
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if a.old ~= b.old then return b.old end
        return a.key < b.key
    end)
    return out
end

---------------------------------------------------------------------------
-- Loot windows: which corpse a Real is on, and whether you took it
---------------------------------------------------------------------------

local win          -- the open window: { reals = { [slot] = { npcs, guids } }, heldBefore, cleared = {} }
local missSeen = {}   -- corpse guids already counted as a miss
ns.hasClearEvent = C_EventUtils == nil or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("LOOT_SLOT_CLEARED")

local function sources(i)
    local out = {}
    if not GetLootSourceInfo then return out end
    local r = { GetLootSourceInfo(i) }
    for j = 1, #r, 2 do
        local guid = plain(r[j])
        local kind, id = KM.GuidInfo(guid)
        if (kind == "Creature" or kind == "Vehicle") and id then out[#out + 1] = { guid = guid, npc = id } end
    end
    return out
end

local function slotIsReal(i)
    local link = plain(GetLootSlotLink and GetLootSlotLink(i))
    if type(link) == "string" then
        local cur = tonumber(link:match("currency:(%d+)"))
        if link:find("item:" .. ns.REAL_ITEM .. ":", 1, true) or link:find("item:" .. ns.REAL_ITEM .. "|", 1, true) then return true end
        if link:find("[" .. ns.REAL_NAME .. "]", 1, true) then
            if cur and not ns.db.currency then ns.db.currency = cur end
            return true
        end
        if cur and ns.db.currency and cur == ns.db.currency then return true end
    end
    local _, name = GetLootSlotInfo(i)
    return isRealName(name)
end

-- The name of a corpse we can see (target, mouseover, focus), for a boss the data doesn't know.
local function nameOf(guid)
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        if UnitGUID and plain(UnitGUID(u)) == guid then return plain(UnitName(u)), plain(UnitLevel and UnitLevel(u)) end
    end
end

function ns.OnLootOpen()
    if win or not ns.db then return end
    local n = plain(GetNumLootItems and GetNumLootItems()) or 0
    win = { reals = {}, cleared = {}, heldBefore = ns.ReadHeld() }
    local withReal, corpses = {}, {}
    for i = 1, n do
        local src = sources(i)
        for _, s in ipairs(src) do corpses[s.guid] = s.npc end
        if slotIsReal(i) then
            win.reals[i] = src
            for _, s in ipairs(src) do withReal[s.guid] = true end
        end
    end
    local c = ns.Me()
    ns.CheckDay(c)
    for guid, npc in pairs(corpses) do
        local b = ns.BOSS[npc]
        if withReal[guid] then
            if not b then
                local name, level = nameOf(guid)
                local _, inst = ns.CurrentDungeon()
                local d = ns.visit and ns.visit.dungeon
                ns.db.learned[npc] = { name = name or (ns.visit and ns.visit.lastName), dungeon = (d and d.name) or inst }
                b = addLearned(npc, ns.db.learned[npc])
                b.level = level
            end
            ns.db.drops[npc] = (ns.db.drops[npc] or 0) + 1
            ns.db.misses[npc] = nil
            if ns.visit then ns.visit.killed[npc] = true; ns.visit.dungeon = ns.visit.dungeon or b.dungeon end
        elseif b and not ns.Got(c, npc) and not missSeen[guid] then
            missSeen[guid] = true                        -- a boss corpse with loot but no Real for you
            ns.db.misses[npc] = (ns.db.misses[npc] or 0) + 1
        end
    end
    if next(win.reals) then ns.Changed() end
end

local function credit(src)
    local c = ns.Me()
    ns.CheckDay(c)
    local now, any = ns.Now(), false
    for _, s in ipairs(src) do
        if ns.BOSS[s.npc] and not c.got[s.npc] then
            c.got[s.npc] = now
            any = true
            if ns.visit then ns.visit.killed[s.npc] = nil end
        end
    end
    return any
end

function ns.OnSlotCleared(i)
    i = plain(i)
    if not (win and i and win.reals[i]) or win.cleared[i] then return end
    win.cleared[i] = true
    if credit(win.reals[i]) then ns.Changed() end
end

function ns.OnLootClosed()
    local w = win
    win = nil
    if not (w and next(w.reals)) then return end
    local after = ns.ReadHeld()
    local rose = after and w.heldBefore and after > w.heldBefore
    local left = {}
    for i, src in pairs(w.reals) do
        if not w.cleared[i] then
            if rose or (after == nil and not ns.hasClearEvent) then
                credit(src)
            else
                for _, s in ipairs(src) do
                    local b = ns.BOSS[s.npc]
                    if b and not ns.Got(ns.Me(), s.npc) then left[#left + 1] = b.name end
                end
            end
        end
    end
    if #left > 0 and ns.db.settings.notify then
        ns.Alert("You left a Real on " .. table.concat(left, ", ") .. ": open the corpse again to take it.")
    end
    ns.Snapshot()
    ns.Changed()
end

---------------------------------------------------------------------------
-- Boss kills: "loot your Real" while you're there, a reminder when you leave
---------------------------------------------------------------------------

ns.visit = nil   -- while in an instance: { dungeon, killed[npc] = true (down, its Real not taken), told[npc], lastName }

function ns.Alert(text, sub)
    KM.Print(ns, text)
    if ns.Toast then KM.Safe(ns.Toast, text, sub) end
end

-- A boss on the list is down: if its Real is still due today, say so (once a visit).
function ns.OnBossDown(b)
    if not (b and ns.db) then return false end
    local c = ns.Me()
    ns.CheckDay(c)
    if ns.Got(c, b.npc) or ns.NoDrop(b) then return false end
    ns.visit = ns.visit or { killed = {}, told = {} }
    ns.visit.killed[b.npc] = true
    ns.visit.dungeon = ns.visit.dungeon or b.dungeon
    if ns.visit.told[b.npc] or not ns.db.settings.notify then return false end
    ns.visit.told[b.npc] = true
    local sure = (ns.db.drops[b.npc] or 0) > 0
    ns.Alert(sure and ("A Real dropped on " .. b.name .. ": don't forget to loot it!") or (b.name .. " may have a Real for you: loot the corpse."))
    return true
end

function ns.OnEncounter(name, success)
    if success ~= nil and plain(success) ~= 1 and plain(success) ~= true then return end
    if ns.visit then ns.visit.lastName = plain(name) end
    local b = ns.BossByName(name)
    if b then ns.OnBossDown(b) end
end

-- A dead boss you target or mouse over: still lootable by you and its Real due? (Kills without encounter events.)
function ns.CheckUnit(unit)
    if not (UnitGUID and UnitIsDead and plain(UnitIsDead(unit))) then return end
    local guid = plain(UnitGUID(unit))
    local kind, npc = KM.GuidInfo(guid)
    local b = (kind == "Creature" or kind == "Vehicle") and npc and ns.BOSS[npc]
    if not b then return end
    if CanLootUnit then
        local has = plain(call(CanLootUnit, guid))
        if not has then return end
    end
    ns.OnBossDown(b)
end

-- Entering or leaving an instance: a new visit, or the reminder for bosses left unlooted.
function ns.OnZone()
    local inside = IsInInstance and plain(IsInInstance()) and true or false
    if inside then
        local d = ns.CurrentDungeon()
        if not ns.visit then ns.visit = { killed = {}, told = {} } end
        ns.visit.dungeon = ns.visit.dungeon or d
        return
    end
    local v = ns.visit
    ns.visit = nil
    if not (v and ns.db) then return end
    local c = ns.Me()
    local names = {}
    for npc in pairs(v.killed) do
        local b = ns.BOSS[npc]
        if b and not ns.Got(c, npc) and not ns.NoDrop(b) then names[#names + 1] = b.name end
    end
    table.sort(names)
    if #names > 0 and ns.db.settings.leave then
        ns.Alert("You left without looting " .. #names .. " Real" .. (#names == 1 and "" or "s") .. ": " .. table.concat(names, ", ") .. ".")
    end
end

---------------------------------------------------------------------------
-- Other addons, and redraws
---------------------------------------------------------------------------

local callbacks = {}
function API.RegisterCallback(owner, fn)
    if owner == nil or type(fn) ~= "function" then return false end
    callbacks[owner] = fn
    return true
end
function API.UnregisterCallback(owner) if owner ~= nil then callbacks[owner] = nil end end

function ns.Changed()
    if KM.IsShown and KM.IsShown("reals") then KM.Refresh("reals") end
    for _, fn in pairs(callbacks) do pcall(fn, "CHANGED") end
end

-- Has a character (default: you) looted today's Real from this boss?
function API.GotToday(npc, key)
    local c = ns.db and ns.db.chars[key or KM.Char()]
    return c and ns.Got(c, npc) ~= nil or false
end

-- Reals looted today, bosses still to loot today, dungeons with any left (default: you).
function API.Today(key)
    local c = ns.db and ns.db.chars[key or KM.Char()]
    if not c then return 0, 0, 0 end
    return ns.Totals(c)
end

-- Reals held and the cap, from the last reading (default: you).
function API.Held(key)
    local c = ns.db and ns.db.chars[key or KM.Char()]
    return c and c.held or nil, c and c.cap or nil
end

function API.SecondsToReset() return (ns.SecondsToReset()) end

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
local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "LOOT_READY",
    "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "CURRENCY_DISPLAY_UPDATE", "BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, event, a1, a2, _, _, a5)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        KM.Safe(ns.Snapshot)
        C_Timer.After(3, function() KM.Safe(ns.Snapshot); ns.Changed() end)   -- the currency list can come late
        if not ticker and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(60, function() if ns.CheckDay(ns.Me()) then ns.Changed() end end)
        end
    elseif event == "PLAYER_LOGOUT" then
        local c = ns.db.chars[KM.Char()]
        if c then c.seen = ns.Now() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        KM.Safe(ns.OnZone)
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        KM.Safe(ns.OnLootOpen)
    elseif event == "LOOT_SLOT_CLEARED" then
        KM.Safe(ns.OnSlotCleared, a1)
    elseif event == "LOOT_CLOSED" then
        KM.Safe(ns.OnLootClosed)
    elseif event == "ENCOUNTER_END" then
        KM.Safe(ns.OnEncounter, a2, a5)
    elseif event == "BOSS_KILL" then
        KM.Safe(ns.OnEncounter, a2)
    elseif event == "PLAYER_TARGET_CHANGED" then
        KM.Safe(ns.CheckUnit, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        KM.Safe(ns.CheckUnit, "mouseover")
    else -- currency and bags
        soon("held", 1, function() ns.Snapshot(); ns.Changed() end)
    end
end)

---------------------------------------------------------------------------
-- /reals
---------------------------------------------------------------------------

function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("reals") end
    if show then KM.Show("reals") elseif KM.IsShown("reals") then KM.Toggle(false) end
end

function ns.Duration(s)
    s = math.max(0, math.floor(s or 0))
    local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

function ns.PrintStatus()
    local c = ns.Snapshot()
    local got, left, dl = ns.Totals(c)
    KM.Print(ns, got .. " Real" .. (got == 1 and "" or "s") .. " looted today; " .. left .. " boss" .. (left == 1 and "" or "es")
        .. " left in " .. dl .. " dungeon" .. (dl == 1 and "" or "s") .. "; holding " .. tostring(c.held or "?")
        .. (c.cap and ("/" .. c.cap) or "") .. "; reset in " .. ns.Duration((ns.SecondsToReset())) .. ".")
    for _, st in ipairs(ns.States(c)) do
        if st.done > 0 or st.left > 0 then
            local todo = {}
            for _, e in ipairs(st.bosses) do
                if not e.got and not e.noDrop and not e.b.optional then todo[#todo + 1] = e.b.name end
            end
            KM.Print(ns, "  " .. st.d.name .. ": " .. st.done .. "/" .. st.total .. (#todo > 0 and (", left: " .. table.concat(todo, ", ")) or ", all looted"))
        end
    end
end

function ns.Debug()
    local held, cap = ns.ReadHeld()
    KM.Print(ns, "currency id " .. tostring(ns.db.currency) .. ", held " .. tostring(held) .. ", cap " .. tostring(cap)
        .. ", item count " .. tostring(plain(call((C_Item and C_Item.GetItemCount) or GetItemCount, ns.REAL_ITEM, true))))
    local secs, guessed = ns.SecondsToReset()
    KM.Print(ns, "reset in " .. math.floor(secs) .. "s" .. (guessed and " (guessed)" or "") .. "; LOOT_SLOT_CLEARED " .. tostring(ns.hasClearEvent)
        .. "; ENCOUNTER_END " .. tostring(not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("ENCOUNTER_END")))
    local d, inst = ns.CurrentDungeon()
    KM.Print(ns, "instance " .. tostring(inst) .. " -> " .. tostring(d and d.name) .. "; visit " .. tostring(ns.visit ~= nil))
    local n = 0
    for npc, k in pairs(ns.db.drops) do n = n + 1; if n <= 8 then KM.Print(ns, "drops " .. (ns.BOSS[npc] and ns.BOSS[npc].name or npc) .. ": " .. k) end end
    for npc, info in pairs(ns.db.learned) do KM.Print(ns, "learned " .. npc .. " " .. tostring(info.name) .. " in " .. tostring(info.dungeon)) end
end

local function help()
    KM.Print(ns, "/reals   open the Reals page (or /km reals)")
    KM.Print(ns, "/reals status   what's left today, in chat")
    KM.Print(ns, "/reals notify on|off   the \"loot your Real\" pop-up")
    KM.Print(ns, "/reals leave on|off   the reminder when you leave a dungeon with Reals unlooted")
    KM.Print(ns, "/reals forget First Last   forget a character")
    KM.Print(ns, "/reals debug   what the game reports (for bug reports)")
end

SLASH_REALSKING1 = "/reals"
SLASH_REALSKING2 = "/real"
SlashCmdList.REALSKING = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local function onOff(cur) return rest:lower() == "on" or (rest:lower() ~= "off" and not cur) end
    local s = ns.db.settings
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "status" or cmd == "list" then
        ns.PrintStatus()
    elseif cmd == "notify" or cmd == "notifications" then
        s.notify = onOff(s.notify)
        KM.Print(ns, "\"loot your Real\" pop-ups " .. (s.notify and "on." or "off."))
        ns.Changed()
    elseif cmd == "leave" then
        s.leave = onOff(s.leave)
        KM.Print(ns, "leaving reminder " .. (s.leave and "on." or "off."))
    elseif cmd == "forget" and rest ~= "" then
        local key = ns.FindChar(rest)
        if key and ns.Forget(key) then KM.Print(ns, "forgot " .. key .. ".") else KM.Print(ns, "no other character called " .. rest .. ".") end
    elseif cmd == "debug" then
        ns.Debug()
    else
        help()
    end
end
