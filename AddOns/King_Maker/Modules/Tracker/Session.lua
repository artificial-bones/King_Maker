local _, KM = ...
local ns = KM.Module("Tracker")

-- The engine: one live session per character, idle / running / paused, the active-time clock, idle and AFK
-- handling, the timeline, saving, pruning. Everything that earns gold comes in through ns.Credit (an item),
-- ns.CreditCoin (coin), ns.Kill (Farm's kill detection) and ns.Cash (vendor, repairs, mail, quest gold, ...).
--
--   Start(why, firstAt)  idle -> running (auto-start passes the first action's GetTime, so the clock starts there)
--   Pause(why)           running -> paused; "idle" and "afk" take the idle minutes back off the clock
--   Resume(why)          paused -> running (farming again resumes it when autoResume is on)
--   Stop(why, chat)      save it to the ledger (an auto-started session too short or worth nothing is dropped,
--                        unless you pressed Stop yourself); Split = Stop + Start; Discard throws it away; a new best
--                        gold per hour for its farm (zone + activity) says so in chat (CheckRecord)
--   Unbox(itemID)        a container looted this session was opened: it stops counting, its contents count instead
--   SetCountDE(on)       the disenchanting setting; each session keeps how it counted (s.countDE)
--
-- Active time: s.act (banked) plus, while running, GetTime() - since (memory only). A 1 s ticker checks idle and,
-- every 10 s, checkpoints s.act and s.tick (server time) so a /reload or a crash loses at most 10 seconds.
-- GetTime() is machine uptime: only ever used for deltas inside one login; everything saved is server time.

local MAX_BUCKETS = 120
local PRE_WINDOW = 300           -- auto-start: actions within 5 minutes
local RELOAD_GAP = 180           -- a /reload or quick relog keeps a running session running

local since, bank, lastAct, zoneAt   -- memory: when the clock last started, s.act then, last activity, zone clock
local killed = {}                    -- creature GUID -> true: counted this login (Farm and the loot fallback)
local lastDeath = 0

local function newPre() return { entries = {}, actions = {}, seen = {} } end
local pre = newPre()

local MOB_KINDS = { mob = true, skin = true, pick = true, share = true }
local GATHER_KINDS = { mine = true, herb = true, fish = true, chest = true, box = true }
ns.MOB_KINDS, ns.GATHER_KINDS = MOB_KINDS, GATHER_KINDS
ns.KIND_LABEL = { mob = "Mob drops", skin = "Skinning", pick = "Pickpocketing", mine = "Mining", herb = "Herbalism",
    fish = "Fishing", chest = "Treasure", box = "Containers", de = "Disenchanting", share = "Party coin shares",
    unknown = "Other loot", quest = "Quest gold" }
ns.KIND_ORDER = { "mob", "skin", "pick", "share", "mine", "herb", "fish", "chest", "box", "unknown", "de", "quest" }
ns.COST_KINDS = { "repair", "buy", "travel", "train" }

local function S() return ns.db.settings end

-- Is this kind's value part of "farmed"?
function ns.Counts(kind)
    if kind == "de" then return S().countDE and true or false end
    if kind == "share" then return S().countShares and true or false end
    if kind == "quest" then return S().countQuest and true or false end
    return true
end

-- The same for one session. Disenchanting is decided per session (s.countDE, set when the session starts and when the
-- setting changes while it runs), so a saved session reads the way it was counted, whatever the setting says now.
function ns.CountsIn(s, kind)
    if kind == "de" then return (s and s.countDE) == true end
    return ns.Counts(kind)
end

function ns.Live()
    return ns.db and ns.db.live[KM.Char()] or nil
end

function ns.State()
    local s = ns.Live()
    return s and s.state or "idle"
end

function ns.Active(s)
    s = s or ns.Live()
    if not s then return 0 end
    if s.state == "running" and since and s == ns.Live() then return (bank or 0) + math.max(0, GetTime() - since) end
    return s.act or 0
end

local function round(v) return math.floor((v or 0) + 0.5) end

local function curMap()
    local m = C_Map and C_Map.GetBestMapForUnit and KM.Plain(C_Map.GetBestMapForUnit("player"))
    return m
end

-- The dungeon or raid you're in (its name and "party" / "raid"), or nil outside one. Recorded per session (s.zi,
-- since 2.15.0) because the game gives some dungeons no map, or the whole continent's.
local function curInstance()
    if not (IsInInstance and GetInstanceInfo) then return nil end
    local inside, kind = IsInInstance()
    inside, kind = KM.Plain(inside), KM.Plain(kind)
    if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
    local name = KM.Plain((GetInstanceInfo()))
    if type(name) ~= "string" or name == "" then return nil end
    return name, kind
end

local function addZone(s, sec)
    if not sec or sec <= 0 then return end
    local inst, kind = curInstance()
    if inst then
        s.zi = s.zi or {}
        s.zi[inst] = round((s.zi[inst] or 0) + sec)
        s.zk = s.zk or {}
        s.zk[inst] = kind
    end
    local m = curMap()
    if not m then return end
    s.z = s.z or {}
    s.z[m] = round((s.z[m] or 0) + sec)
end

---------------------------------------------------------------------------
-- The record
---------------------------------------------------------------------------

function ns.NewSession(char, t0)
    local db = ns.db
    local s = { id = db.nextId, c = char, lvl = UnitLevel and KM.Plain(UnitLevel("player")) or nil, t0 = t0, act = 0,
        idle = 0, paused = 0, z = {}, value = 0, coin = 0, iv = 0, kills = 0, deaths = 0, src = {}, items = {}, mobs = {},
        nodes = {}, cash = {}, tl = { bw = 60, v = {}, a = {} }, countDE = S().countDE and true or nil }
    db.nextId = db.nextId + 1
    s.gold0 = GetMoney and KM.Plain(GetMoney()) or nil
    s.gold1 = s.gold0
    return s
end

local function src(s, kind)
    local e = s.src[kind]
    if not e then e = { n = 0, v = 0, c = 0, i = {} }; s.src[kind] = e end
    e.i = e.i or {}
    return e
end

local function mob(s, npc)
    npc = npc or 0
    local m = s.mobs[npc]
    if not m then m = { k = 0, c = 0, v = 0, sv = 0, sn = 0, i = {} }; s.mobs[npc] = m end
    m.i = m.i or {}
    return m
end

-- Timeline: buckets of bw active seconds (value credited, actions); at 121 buckets pairs merge and bw doubles.
local function merge(tl)
    local v, a = {}, {}
    for j = 1, #tl.v, 2 do
        v[#v + 1] = tl.v[j] + (tl.v[j + 1] or 0)
        a[#a + 1] = tl.a[j] + (tl.a[j + 1] or 0)
    end
    tl.v, tl.a, tl.bw = v, a, tl.bw * 2
end

local function bucket(s, copper, actions)
    local tl = s.tl
    if type(tl) ~= "table" then return end
    local act = ns.Active(s)
    local i = math.floor(act / tl.bw) + 1
    while i > MAX_BUCKETS do merge(tl); i = math.floor(act / tl.bw) + 1 end
    for j = #tl.v + 1, i do tl.v[j], tl.a[j] = 0, 0 end
    tl.v[i] = tl.v[i] + round(copper or 0)
    tl.a[i] = tl.a[i] + (actions or 0)
end
ns.Bucket = bucket

-- Takes value back off the timeline (a container swapped for its contents, disenchanting no longer counted): from the
-- newest buckets backwards, never below zero.
local function unbucket(s, copper)
    local tl = s.tl
    if type(tl) ~= "table" then return end
    copper = round(copper)
    for i = #tl.v, 1, -1 do
        if copper <= 0 then return end
        local take = math.min(tl.v[i] or 0, copper)
        tl.v[i], copper = (tl.v[i] or 0) - take, copper - take
    end
end

function ns.Pack(tl)
    if type(tl) ~= "table" then return tl end
    local v, a = {}, {}
    for i = 1, #tl.v do v[i] = tostring(round(tl.v[i])); a[i] = tostring(tl.a[i] or 0) end
    return tl.bw .. "|" .. table.concat(v, ",") .. "|" .. table.concat(a, ",")
end

function ns.Unpack(tl)
    if type(tl) == "table" then return tl end
    if type(tl) ~= "string" then return nil end
    local bw, vs, as = tl:match("^(%d+)|([^|]*)|(.*)$")
    if not bw then return nil end
    local out = { bw = tonumber(bw), v = {}, a = {} }
    for n in vs:gmatch("[^,]+") do out.v[#out.v + 1] = tonumber(n) or 0 end
    for n in as:gmatch("[^,]+") do out.a[#out.a + 1] = tonumber(n) or 0 end
    return out
end

local function addValue(s, kind, id, item, v)
    v = round(v)
    if v == 0 then return end
    local it = s.items[item]
    if it then it.v = (it.v or 0) + v end
    local e = src(s, kind)
    e.v = e.v + v
    if kind == "mob" or kind == "pick" then local m = mob(s, id); m.v = m.v + v
    elseif kind == "skin" then local m = mob(s, id); m.sv = m.sv + v end
    if ns.CountsIn(s, kind) then
        s.iv = s.iv + v
        s.value = s.value + v
        bucket(s, v, 0)
    end
end

-- No AH price, no vendor price, not grey, not a quest item: worth 0 until a scan prices it.
local function unpriced(item, unit, from)
    if unit == nil then return true end
    if unit > 0 or from == "quest" then return false end
    local i = KM.Item(item)
    return not (i.q == 0 or i.bop)
end

function ns.AddItem(s, kind, id, item, qty, unit, from)
    qty = qty or 1
    id = id or 0
    local e = src(s, kind)
    e.i[item] = (e.i[item] or 0) + qty
    local it = s.items[item]
    if not it then it = { q = 0, v = 0 }; s.items[item] = it end
    it.q = it.q + qty
    if kind == "mob" or kind == "pick" or kind == "skin" then local m = mob(s, id); m.i[item] = (m.i[item] or 0) + qty end
    if unpriced(item, unit, from) then
        -- valued when its info loads (GET_ITEM_INFO_RECEIVED) or a scan prices it (PRICES_UPDATED)
        it.np = (it.np or 0) + qty
        s.later = s.later or {}
        table.insert(s.later, { item, qty, kind, id })
    else
        addValue(s, kind, id, item, (unit or 0) * qty)
    end
end

function ns.AddCoin(s, kind, id, copper)
    copper = round(copper)
    if copper == 0 then return end
    local e = src(s, kind)
    e.c = e.c + copper
    if kind == "mob" or kind == "pick" then local m = mob(s, id); m.c = m.c + copper end
    if ns.CountsIn(s, kind) then
        s.coin = s.coin + copper
        s.value = s.value + copper
        bucket(s, copper, 0)
    end
end

function ns.AddKills(s, npc, n)
    n = n or 1
    s.kills = (s.kills or 0) + n
    local m = mob(s, npc)
    m.k = m.k + n
    bucket(s, 0, n)
end

-- One action of a kind: a corpse looted, a skin, a node, a catch, a chest, a box. node = the node's name.
function ns.AddHarvest(s, kind, id, node)
    local e = src(s, kind)
    e.n = e.n + 1
    if kind == "skin" then local m = mob(s, id); m.sn = m.sn + 1 end
    if node then s.nodes[node] = (s.nodes[node] or 0) + 1 end
    if kind ~= "mob" and kind ~= "share" then bucket(s, 0, 1) end
end

---------------------------------------------------------------------------
-- Auto-start buffer: farming before a session exists, replayed into it once 3 actions happen within 5 minutes
---------------------------------------------------------------------------

local function prunePre(now)
    local keep = {}
    for _, t in ipairs(pre.actions) do if now - t <= PRE_WINDOW then keep[#keep + 1] = t end end
    pre.actions = keep
    local ent = {}
    for _, e in ipairs(pre.entries) do if now - e.at <= PRE_WINDOW then ent[#ent + 1] = e end end
    pre.entries = ent
    for k, t in pairs(pre.seen) do if now - t > PRE_WINDOW then pre.seen[k] = nil end end
end

local function buffer(what, kind, ...)
    if not (S().autoStart and (KM.FARMING_KINDS[kind] or what == "kill")) then return end
    table.insert(pre.entries, { at = GetTime(), what = what, kind = kind, args = { ... } })
end

local function replay(s, e)
    local a = e.args
    if e.what == "item" then ns.AddItem(s, e.kind, a[1], a[2], a[3], KM.ItemValue(a[2]))
    elseif e.what == "coin" then ns.AddCoin(s, e.kind, a[1], a[2])
    elseif e.what == "kill" then ns.AddKills(s, a[1], 1)
    elseif e.what == "harvest" then ns.AddHarvest(s, e.kind, a[1], a[2]) end
end

---------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------

local function checkpoint(s)
    s = s or ns.Live()
    if not s then return end
    if s.state == "running" and since then
        s.act = ns.Active(s)
        local now = GetTime()
        addZone(s, now - (zoneAt or now))
        zoneAt = now
        bucket(s, 0, 0)
    end
    s.tick = KM.Now()
    s.gold1 = GetMoney and KM.Plain(GetMoney()) or s.gold1
end
ns.Checkpoint = checkpoint

function ns.Start(why, firstAt)
    if not ns.db then return end
    local s = ns.Live()
    if s then
        if s.state == "paused" then ns.Resume(why) end
        return s
    end
    local now = GetTime()
    local back = firstAt and math.max(0, now - firstAt) or 0
    s = ns.NewSession(KM.Char(), KM.Now() - math.floor(back))
    s.state, s.tick = "running", KM.Now()
    if why == "auto" then s.auto = true end
    ns.db.live[KM.Char()] = s
    since, bank, lastAct, zoneAt = firstAt or now, 0, now, firstAt or now
    local entries = pre.entries
    pre = newPre()
    if why == "auto" then for _, e in ipairs(entries) do replay(s, e) end end
    ns.Fire("SESSION_STARTED", ns.Summary(s))
    if S().hudOnStart and ns.SetHUD then ns.SetHUD(true, true) end
    ns.Changed()
    return s
end

function ns.Pause(why)
    local s = ns.Live()
    if not s or s.state ~= "running" then return end
    local now = GetTime()
    if since then
        local stop = now
        if (why == "idle" or why == "afk") and lastAct then
            -- take the idle minutes back off the clock: keep 30 s after the last thing you did
            stop = math.min(now, math.max(lastAct + 30, since))
            s.idle = round((s.idle or 0) + (now - stop))
        end
        s.act = (bank or 0) + math.max(0, stop - since)
        addZone(s, stop - (zoneAt or stop))
        if zoneAt and stop < zoneAt and s.z then
            local m = curMap()
            if m and s.z[m] then s.z[m] = math.max(0, round(s.z[m] - (zoneAt - stop))) end
        end
        local inst = curInstance()
        if zoneAt and stop < zoneAt and inst and s.zi and s.zi[inst] then
            s.zi[inst] = math.max(0, round(s.zi[inst] - (zoneAt - stop)))
        end
    end
    since, bank, zoneAt = nil, nil, nil
    s.state, s.why, s.pausedAt, s.tick = "paused", why or "manual", KM.Now(), KM.Now()
    ns.Changed()
end

function ns.Resume(why)
    local s = ns.Live()
    if not s or s.state ~= "paused" then return end
    s.paused = round((s.paused or 0) + math.max(0, KM.Now() - (s.pausedAt or KM.Now())))
    s.state, s.why, s.pausedAt = "running", nil, nil
    local now = GetTime()
    since, bank, lastAct, zoneAt = now, s.act or 0, now, now
    ns.Changed()
end

-- Strips the live-only fields and packs what gets saved.
local function finish(s)
    s.state, s.why, s.pausedAt, s.tick, s.later = nil, nil, nil, nil, nil
    s.act = round(s.act)
    s.map = ns.MainZone(s)
    if type(s.tl) == "table" then
        -- idle minutes taken back off the clock can leave empty buckets past the end
        local n = math.max(1, math.ceil(s.act / s.tl.bw))
        for i = #s.tl.v, n + 1, -1 do
            if (s.tl.v[i] or 0) == 0 and (s.tl.a[i] or 0) == 0 then s.tl.v[i], s.tl.a[i] = nil, nil else break end
        end
        s.tl = ns.Pack(s.tl)
    end
    local Farm = KM.mods.Farm
    for npc, m in pairs(s.mobs or {}) do
        if not m.name and npc ~= 0 then
            local info = Farm and Farm.MobInfo and KM.Safe(Farm.MobInfo, npc)
            m.name = info and info.name or (FarmKingDB and FarmKingDB.mobs and FarmKingDB.mobs[npc] and FarmKingDB.mobs[npc].name)
        end
        for _, k in ipairs({ "k", "c", "v", "sv", "sn" }) do if m[k] == 0 then m[k] = nil end end
        if m.i and next(m.i) == nil then m.i = nil end
    end
    for _, e in pairs(s.src or {}) do
        for _, k in ipairs({ "n", "v", "c" }) do if e[k] == 0 then e[k] = nil end end
        if e.i and next(e.i) == nil then e.i = nil end
    end
    if s.nodes and next(s.nodes) == nil then s.nodes = nil end
    if s.cash and next(s.cash) == nil then s.cash = nil end
    if s.z and next(s.z) == nil then s.z = nil end
    if s.zi and next(s.zi) == nil then s.zi, s.zk = nil, nil end
end

-- Appends a finished session to the history (oldest first) and prunes.
function ns.SaveRecord(s)
    s.t1 = s.t1 or KM.Now()
    finish(s)
    table.insert(ns.db.sessions, s)
    ns.Prune()
    return s
end

function ns.Stop(why, chat)
    local s = ns.Live()
    if not s then return end
    if why == "offline" then
        s.t1 = s.tick or KM.Now()          -- saved as of the last checkpoint: the time spent offline isn't paused time
    elseif s.state == "running" then
        checkpoint(s)
    end
    if why == "offline" then
        -- (nothing more: no pause to add)
    elseif s.state == "paused" and s.pausedAt then
        s.paused = round((s.paused or 0) + math.max(0, KM.Now() - s.pausedAt))
    end
    ns.db.live[KM.Char()] = nil
    since, bank, zoneAt = nil, nil, nil
    s.gold1 = GetMoney and KM.Plain(GetMoney()) or s.gold1
    local short = (s.act or 0) < S().minKeep or (s.value or 0) <= 0
    if s.auto and why ~= "manual" and short then
        ns.Changed()
        return nil
    end
    ns.SaveRecord(s)
    ns.Fire("SESSION_SAVED", ns.Summary(s))
    if chat then KM.Print(ns, "saved to the Farming Ledger: " .. ns.SessionLine(s)) end
    KM.Safe(ns.CheckRecord, s)
    ns.Changed()
    return s
end

function ns.Split()
    if not ns.Live() then return ns.Start("manual") end
    local rec = ns.Stop("manual")
    local n = ns.Start("manual")
    if rec and n then n.prev = rec.id end
    return n
end

function ns.Discard(now)
    if not ns.Live() then return end
    local function go()
        if not ns.Live() then return end
        ns.db.live[KM.Char()] = nil
        since, bank, zoneAt = nil, nil, nil
        KM.Print(ns, "threw the current farming session away.")
        ns.Changed()
    end
    if now then go() else ns.Confirm("Throw the current farming session away? Nothing of it is saved.", go) end
end

function ns.Toggle()
    if ns.Live() then return ns.Stop("manual", true) end
    return ns.Start("manual")
end

---------------------------------------------------------------------------
-- Credits (from Sources.lua and Farm)
---------------------------------------------------------------------------

-- Farming again: notes the activity and resumes a paused session (autoResume).
local function wake(kind)
    lastAct = GetTime()
    local s = ns.Live()
    if s and s.state == "paused" and KM.FARMING_KINDS[kind] and S().autoResume then ns.Resume("auto") end
    return ns.Live()
end

-- Activity that isn't loot: a gathering cast, entering combat. Farming kinds also resume a paused session.
function ns.Activity(kind)
    if not ns.db then return end
    if KM.FARMING_KINDS[kind] then wake(kind) else lastAct = GetTime() end
end

-- One farming action (a loot window, a kill). key de-duplicates (a corpse's kill and its loot are one action).
-- While idle, 3 of them within 5 minutes start a session (autoStart) with what they looted replayed into it.
function ns.Act(key, kind)
    if not ns.db or not KM.FARMING_KINDS[kind] then return end
    local now = GetTime()
    lastAct = now
    if ns.Live() then wake(kind); return end
    if not S().autoStart then return end
    prunePre(now)
    if key then
        if pre.seen[key] then return end
        pre.seen[key] = now
    end
    table.insert(pre.actions, now)
    if #pre.actions >= (S().startActions or 3) then ns.Start("auto", pre.actions[1]) end
end

function ns.Credit(kind, id, item, qty)
    if not ns.db or not item then return end
    local s = ns.Live()
    if not s then return buffer("item", kind, id or 0, item, qty or 1) end
    s = wake(kind) or s
    ns.AddItem(s, kind, id or 0, item, qty or 1, KM.ItemValue(item))
    ns.Changed()
end

function ns.CreditCoin(kind, id, copper)
    if not ns.db or not copper or copper <= 0 then return end
    local s = ns.Live()
    if not s then return buffer("coin", kind, id or 0, copper) end
    s = wake(kind) or s
    ns.AddCoin(s, kind, id or 0, copper)
    ns.Changed()
end

function ns.Harvest(kind, id, node)
    if not ns.db then return end
    local s = ns.Live()
    if not s then return buffer("harvest", kind, id or 0, node) end
    ns.AddHarvest(s, kind, id or 0, node)
    ns.Changed()
end

-- A kill (Farm's threat + death detection, or a fresh corpse looted when Farm isn't loaded).
function ns.Kill(npc, guid)
    if not ns.db then return end
    guid = KM.Plain(guid)
    if guid then
        if killed[guid] then return end
        killed[guid] = true
    end
    npc = tonumber(npc) or 0
    ns.Act(guid, "mob")
    local s = ns.Live()
    if not s then return buffer("kill", "mob", npc) end
    ns.AddKills(s, npc, 1)
    ns.Changed()
end

function ns.Killed(guid) return guid ~= nil and killed[guid] == true end

-- Money that isn't loot: vendor, repairs, mail, AH, trade, flights, training, bank, quest gold, other.
function ns.Cash(kind, copper)
    local s = ns.Live()
    if not s or not copper or copper == 0 then return end
    s.cash = s.cash or {}
    s.cash[kind] = (s.cash[kind] or 0) + copper
    s.gold1 = GetMoney and KM.Plain(GetMoney()) or s.gold1
    if kind == "quest" and copper > 0 and S().countQuest then ns.AddCoin(s, "quest", 0, copper) end
    ns.Changed()
end

-- Moves a cash entry (money that turned out to be a quest reward after all).
function ns.MoveCash(from, to, copper)
    local s = ns.Live()
    if not s or not s.cash or not s.cash[from] then return end
    s.cash[from] = s.cash[from] - copper
    if s.cash[from] == 0 then s.cash[from] = nil end
    ns.Cash(to, copper)
end

function ns.Death()
    local s = ns.Live()
    if not s or GetTime() - lastDeath < 5 then return end   -- PLAYER_DEAD can fire twice
    lastDeath = GetTime()
    s.deaths = (s.deaths or 0) + 1
    ns.Changed()
end

-- Units waiting for item info or a price get their value now, if they have one.
function ns.ValueLater()
    local s = ns.Live()
    if not s or not s.later then return end
    local changed = false
    for i = #s.later, 1, -1 do
        local e = s.later[i]
        local unit, from = KM.ItemValue(e[1])
        if not unpriced(e[1], unit, from) then
            local it = s.items[e[1]]
            if it and it.np then it.np = it.np - e[2]; if it.np <= 0 then it.np = nil end end
            addValue(s, e[3], e[4], e[1], (unit or 0) * e[2])
            table.remove(s.later, i)
            changed = true
        end
    end
    if #s.later == 0 then s.later = nil end
    if changed then ns.Changed() end
end

-- Settings > Farm Tracker > Count disenchanting. The running session follows at once (what it disenchanted so far
-- goes into, or comes out of, farmed); saved sessions stay as they were counted.
function ns.SetCountDE(on)
    if not ns.db then return end
    S().countDE = on and true or false
    local s = ns.Live()
    if s and (s.countDE == true) ~= S().countDE then
        local e = s.src and s.src.de
        local v, c = round(e and e.v or 0), round(e and e.c or 0)
        if S().countDE then
            s.iv, s.coin, s.value = s.iv + v, s.coin + c, s.value + v + c
            bucket(s, v + c, 0)
        else
            s.iv, s.coin, s.value = s.iv - v, s.coin - c, s.value - v - c
            unbucket(s, v + c)
        end
        s.countDE = S().countDE or nil
    end
    ns.Changed()
end

-- A container looted earlier in this session was opened (Sources.lua spots it): its contents are credited as they're
-- looted, so the container itself stops counting. One unit moves from items[id] to opened[id], and its value at loot
-- time comes off the session (its kind, its mob, iv, value and the timeline). Returns the copper taken off, or nil.
function ns.Unbox(id)
    local s = ns.Live()
    local it = s and s.items[id]
    if not it or (it.q or 0) <= 0 then return nil end
    local unit = 0
    if (it.np or 0) > 0 then
        -- an unpriced unit was worth nothing: just stop it waiting for a price
        it.np = it.np - 1
        if it.np <= 0 then it.np = nil end
        for i, e in ipairs(s.later or {}) do
            if e[1] == id then
                e[2] = e[2] - 1
                if e[2] <= 0 then table.remove(s.later, i) end
                break
            end
        end
        if s.later and #s.later == 0 then s.later = nil end
    else
        unit = round((it.v or 0) / it.q)
    end
    it.q = it.q - 1
    it.v = math.max(0, (it.v or 0) - unit)
    local kind
    for _, k in ipairs(ns.KIND_ORDER) do
        local e = s.src[k]
        if e and e.i and (e.i[id] or 0) > 0 then kind = k; break end
    end
    if kind then
        local e = s.src[kind]
        e.i[id] = e.i[id] - 1
        if e.i[id] <= 0 then e.i[id] = nil end
        e.v = math.max(0, (e.v or 0) - unit)
        if kind == "mob" or kind == "pick" or kind == "skin" then
            for _, m in pairs(s.mobs) do
                if m.i and (m.i[id] or 0) > 0 then
                    m.i[id] = m.i[id] - 1
                    if m.i[id] <= 0 then m.i[id] = nil end
                    if kind == "skin" then m.sv = math.max(0, (m.sv or 0) - unit) else m.v = math.max(0, (m.v or 0) - unit) end
                    break
                end
            end
        end
        if ns.CountsIn(s, kind) then
            s.iv, s.value = s.iv - unit, s.value - unit
            unbucket(s, unit)
        end
    end
    if it.q <= 0 then s.items[id] = nil end
    s.opened = s.opened or {}
    s.opened[id] = (s.opened[id] or 0) + 1
    ns.Changed()
    return unit
end

---------------------------------------------------------------------------
-- Reading a session
---------------------------------------------------------------------------

function ns.MainZone(s)
    if s.map then return s.map end
    local best, bestT
    for m, t in pairs(s.z or {}) do if not bestT or t > bestT then best, bestT = m, t end end
    return best or (s == ns.Live() and curMap() or nil)
end

-- Where a session was farmed (the Zones tab, Best farms, a session's title): the dungeon or raid it spent at least
-- half its time in (s.zi, recorded since 2.15.0), else its main zone. One saved before then whose map is a dungeon,
-- a continent or unknown (the game gives some dungeons no map) is placed by the mobs it looted (Farm's zone for each).
-- key ("i:Stratholme", "m:1423", "m:0"), name, kind ("dungeon", "raid", "zone").
local MAP_ZONE, MAP_DUNGEON = 3, 4      -- Enum.UIMapType
local function mapInfo(map)
    return map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map) or nil
end

-- The dungeon and raid maps QuestieDB places their mobs on (every floor), named as GetInstanceInfo names them so a
-- session placed by its mobs joins the ones that recorded the instance.
local INSTANCES, RAIDS = {
    ["Ragefire Chasm"] = { 213 }, ["Zul'Farrak"] = { 219 }, ["The Temple of Atal'Hakkar"] = { 220 },
    ["Blackfathom Deeps"] = { 221, 222, 223 }, ["The Stockade"] = { 225 }, ["Gnomeregan"] = { 226, 227, 228, 229 },
    ["Uldaman"] = { 230, 231 }, ["Dire Maul"] = { 234, 235, 236, 237, 238, 239, 240 },
    ["Blackrock Depths"] = { 242, 243 }, ["Blackrock Spire"] = { 250, 251, 252, 253, 254, 255, 256 },
    ["Wailing Caverns"] = { 279 }, ["Maraudon"] = { 280, 281 }, ["The Deadmines"] = { 291, 292 },
    ["Razorfen Downs"] = { 300 }, ["Razorfen Kraul"] = { 301 }, ["Scarlet Monastery"] = { 302, 303, 304, 305 },
    ["Scholomance"] = { 306, 307, 308, 309 }, ["Shadowfang Keep"] = { 310, 311, 312, 313, 314, 315, 316 },
    ["Stratholme"] = { 317, 318 },
    ["Naxxramas"] = { 162, 163, 164, 165, 166, 167 }, ["Molten Core"] = { 232 }, ["Zul'Gurub"] = { 233 },
    ["Ruins of Ahn'Qiraj"] = { 247 }, ["Onyxia's Lair"] = { 248 }, ["Blackwing Lair"] = { 287, 288, 289, 290 },
    ["Temple of Ahn'Qiraj"] = { 319, 320, 321 },
}, { ["Naxxramas"] = true, ["Molten Core"] = true, ["Zul'Gurub"] = true, ["Ruins of Ahn'Qiraj"] = true,
     ["Onyxia's Lair"] = true, ["Blackwing Lair"] = true, ["Temple of Ahn'Qiraj"] = true }
local INSTANCE_MAP = {}
for name, maps in pairs(INSTANCES) do
    for _, m in ipairs(maps) do INSTANCE_MAP[m] = name end
end

-- name, "dungeon" / "raid" when map is inside an instance
local function instanceOf(map, info)
    local name = map and INSTANCE_MAP[map]
    if name then return name, RAIDS[name] and "raid" or "dungeon" end
    info = info or mapInfo(map)
    if info and info.mapType == MAP_DUNGEON and info.name then return info.name, "dungeon" end
end

local function mobsMap(s)
    local Farm = KM.mods.Farm
    if not (Farm and Farm.MobInfo and s.mobs) then return nil end
    local by, best, bn = {}, nil, 0
    for npc, m in pairs(s.mobs) do
        if npc ~= 0 then
            local info = KM.Safe(Farm.MobInfo, npc)
            local map = info and info.map
            if map then
                by[map] = (by[map] or 0) + math.max(m.k or 0, m.c or 0, 1)
                if by[map] > bn then best, bn = map, by[map] end
            end
        end
    end
    return best
end

-- QuestieDB's zones aren't loaded yet, so mobs have no zone: a place worked out now is a guess
local function mobsPending()
    local Farm = KM.mods.Farm
    if not (Farm and Farm.QuestieAvailable and Farm.QuestieZones) then return false end
    return KM.Safe(Farm.QuestieAvailable) and not KM.Safe(Farm.QuestieZones) or false
end

local function place(s)
    if s.zi then
        local best, bt, total = nil, 0, 0
        for name, t in pairs(s.zi) do if t > bt then best, bt = name, t end end
        for _, t in pairs(s.z or {}) do total = total + t end
        if best and bt * 2 >= total then
            return "i:" .. best, best, (s.zk and s.zk[best] == "raid") and "raid" or "dungeon"
        end
    end
    local map = ns.MainZone(s)
    local info = mapInfo(map)
    local iname, ikind = instanceOf(map, info)
    if iname then return "i:" .. iname, iname, ikind end
    -- The game gives no map inside most dungeons, so a session that spent most of its time with none (or one on a
    -- continent) was in one: its mobs say which.
    local mapped = 0
    for _, t in pairs(s.z or {}) do mapped = mapped + t end
    local unmapped = mapped * 2 < (s.act or 0)
    if unmapped or not info or (info.mapType or MAP_ZONE) < MAP_ZONE then
        local m2 = mobsMap(s)
        local i2 = mapInfo(m2)
        iname, ikind = instanceOf(m2, i2)
        if iname then return "i:" .. iname, iname, ikind end
        if not info or (info.mapType or MAP_ZONE) < MAP_ZONE then
            if i2 and i2.name and (i2.mapType or MAP_ZONE) == MAP_ZONE then return "m:" .. m2, i2.name, "zone" end
            if not map then return "m:0", "Unknown zone", "zone", mobsPending() end
            return "m:" .. map, ns.ZoneName(map), "zone", mobsPending()
        end
        if not m2 then return "m:" .. map, ns.ZoneName(map), "zone", mobsPending() end
    end
    return "m:" .. map, ns.ZoneName(map), "zone"
end

local placeCache = setmetatable({}, { __mode = "k" })
function ns.Place(s)
    local c = placeCache[s]
    if c then return c[1], c[2], c[3] end
    local key, name, kind, unsure = place(s)
    -- a guess (no mob zones known yet: QuestieDB still loading) is worked out again next time
    if not unsure and s ~= ns.Live() then placeCache[s] = { key, name, kind } end
    return key, name, kind
end
function ns.PlaceName(s) return (select(2, ns.Place(s))) end

-- mobs / gathering / mixed, and a label for the top kind.
function ns.Classify(s)
    local per, m, g, total = {}, 0, 0, 0
    for kind, e in pairs(s.src or {}) do
        if ns.CountsIn(s, kind) then
            local v = (e.v or 0) + (e.c or 0)
            per[kind] = v
            total = total + v
            if MOB_KINDS[kind] then m = m + v elseif GATHER_KINDS[kind] then g = g + v end
        end
    end
    if total <= 0 then
        if (s.kills or 0) > 0 then return "mobs", "Mobs", per end
        return "none", "Nothing yet", per
    end
    if m >= total * 0.7 then
        return "mobs", ((per.skin or 0) >= total * 0.25) and "Mobs & Skinning" or "Mobs", per
    end
    if g >= total * 0.7 then
        local top, topV
        for kind in pairs(GATHER_KINDS) do if (per[kind] or 0) > (topV or 0) then top, topV = kind, per[kind] end end
        return "gathering", ns.KIND_LABEL[top or "mine"], per
    end
    return "mixed", "Mixed", per
end

-- What the session's loot is worth at today's prices (a view; never saved).
function ns.ValueNow(s)
    local v = s.coin or 0
    if s.compact then
        for id, it in pairs(s.items or {}) do v = v + (it.q or 0) * (KM.ItemValue(id) or 0) end
        return v + (s.rest and s.rest.v or 0)
    end
    for kind, e in pairs(s.src or {}) do
        if ns.CountsIn(s, kind) and e.i then
            for id, q in pairs(e.i) do v = v + q * (KM.ItemValue(id) or 0) end
        end
    end
    return round(v)
end

function ns.Costs(s)
    local c = 0
    for _, k in ipairs(ns.COST_KINDS) do c = c + ((s.cash and s.cash[k]) or 0) end
    return c
end

-- The last ten minutes as gold per hour (live sessions).
function ns.Pace(s)
    local tl = ns.Unpack(s.tl)
    if not tl or #tl.v == 0 then return nil end
    local act = ns.Active(s)
    if act < 60 then return nil end
    local n = math.ceil(600 / tl.bw)
    local sum = 0
    for i = math.max(1, #tl.v - n + 1), #tl.v do sum = sum + (tl.v[i] or 0) end
    local span = math.min(n * tl.bw, act)
    return span > 0 and sum / span * 3600 or nil
end

function ns.Totals(s, revalue)
    local act = ns.Active(s)
    local value = revalue and ns.ValueNow(s) or (s.value or 0)
    local costs = ns.Costs(s)
    local activity, label = ns.Classify(s)
    return {
        act = act, value = value, coin = s.coin or 0, iv = s.iv or 0,
        gph = act >= 60 and value / act * 3600 or nil,
        pace = s.state and ns.Pace(s) or nil,
        costs = costs, net = value + costs,
        wallet = (s.gold1 and s.gold0) and (s.gold1 - s.gold0) or nil,
        activity = activity, label = label,
    }
end

-- date() that never errors (nil for a time it can't show)
function ns.Date(fmt, t)
    if not (t and date) then return nil end
    local ok, d = pcall(date, fmt, t)
    return ok and d or nil
end

-- "Felwood, 15 Nov . 0:48:40 . 78g 5s . 96g 10s/hr"
function ns.SessionLine(s)
    local t = ns.Totals(s)
    local when = ns.Date("%d %b", s.t1)
    when = when and (" " .. when) or ""
    return (s.name or ns.PlaceName(s)) .. "," .. when .. "  " .. ns.Clock(t.act) .. "  " .. KM.Money(t.value)
        .. (t.gph and ("  " .. KM.Money(t.gph) .. "/hr") or "")
end

function ns.Find(id)
    for i, s in ipairs(ns.db.sessions) do if s.id == id then return s, i end end
end

---------------------------------------------------------------------------
-- Farms: a zone and what you did there (Mobs, Mining, Herbalism, ...). "Best here" is the best gold per hour of a
-- farm, out of its sessions with 10+ active minutes; carried-over sessions never count (they have no real time).
---------------------------------------------------------------------------

local BEST_MIN = 600

-- "1441:mobs" and its label ("Mobs", "Herbalism", "Mixed"), or nil for a session with nothing farmed.
function ns.FarmKey(s)
    local activity, label = ns.Classify(s)
    if activity == "none" then return nil end
    local what = activity == "gathering" and label or (activity == "mobs" and "Mobs" or "Mixed")
    return ns.Place(s) .. ":" .. what, what
end

local function rate(s)
    if s.legacy or (s.act or 0) < BEST_MIN then return nil end
    return (s.value or 0) / s.act * 3600
end
ns.BestRate = rate

-- { [sessionID] = true }: each farm's best session, when the farm has two or more sessions to compare (the BEST pill).
function ns.BestIDs()
    local best, count = {}, {}
    for _, s in ipairs(ns.db.sessions) do
        local g = rate(s)
        local key = g and ns.FarmKey(s)
        if key then
            count[key] = (count[key] or 0) + 1
            if not best[key] or g > best[key].g then best[key] = { g = g, id = s.id } end
        end
    end
    local out = {}
    for key, b in pairs(best) do if count[key] >= 2 then out[b.id] = true end end
    return out
end

-- Just saved: a new best gold per hour for its farm (beating an earlier session there) says so once, in chat.
function ns.CheckRecord(s)
    local g = rate(s)
    if not g then return nil end
    local key, what = ns.FarmKey(s)
    if not key then return nil end
    local before
    for _, o in ipairs(ns.db.sessions) do
        local og = o ~= s and rate(o)
        if og and ns.FarmKey(o) == key and (not before or og > before) then before = og end
    end
    if not before or g <= before then return nil end
    local line = "new best gold per hour here: " .. ns.PlaceName(s) .. " (" .. what .. "), "
        .. KM.Money(g) .. "/hr, beating " .. KM.Money(before) .. "/hr."
    KM.Print(ns, line)
    return line
end

function ns.Rename(id, text)
    local s = ns.Find(id)
    if not s then return end
    text = text and strtrim and strtrim(text) or text
    s.name = (text and text ~= "") and text or nil
    ns.Changed()
end

function ns.Star(id, on)
    local s = ns.Find(id)
    if not s then return end
    s.star = on and true or nil
    ns.Changed()
end

function ns.Delete(id)
    local s, i = ns.Find(id)
    if not s then return end
    table.remove(ns.db.sessions, i)
    ns.Changed()
end

---------------------------------------------------------------------------
-- Retention: the newest `keep` unstarred sessions; detail compacted after `detailDays`; starred kept as they are
---------------------------------------------------------------------------

function ns.Compact(s)
    if s.compact then return end
    s.tl = nil
    for _, m in pairs(s.mobs or {}) do m.i = nil end
    for _, e in pairs(s.src or {}) do e.i = nil end
    local list = {}
    for id, it in pairs(s.items or {}) do list[#list + 1] = { id = id, it = it } end
    table.sort(list, function(a, b) return (a.it.v or 0) > (b.it.v or 0) end)
    if #list > 25 then
        local rest = { n = 0, q = 0, v = 0 }
        for i = 26, #list do
            rest.n, rest.q, rest.v = rest.n + 1, rest.q + (list[i].it.q or 0), rest.v + (list[i].it.v or 0)
            s.items[list[i].id] = nil
        end
        s.rest = rest
    end
    s.compact = true
end

function ns.Prune()
    local db = ns.db
    if not db then return end
    local st = db.settings
    local keep, unstarred = st.keep or 200, 0
    for i = #db.sessions, 1, -1 do
        local s = db.sessions[i]
        if not s.star then
            unstarred = unstarred + 1
            if unstarred > keep then table.remove(db.sessions, i) end
        end
    end
    local cutoff = KM.Now() - (st.detailDays or 45) * 86400
    for _, s in ipairs(db.sessions) do
        if not s.star and not s.compact and (s.t1 or 0) < cutoff then ns.Compact(s) end
    end
end

---------------------------------------------------------------------------
-- Redraws (debounced)
---------------------------------------------------------------------------

local scheduled = false
function ns.Changed()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.1, function()
        scheduled = false
        if ns.UpdateHUD then KM.Safe(ns.UpdateHUD) end
        KM.Refresh("farming")
        KM.Refresh("home")
        ns.Fire("SESSION_CHANGED")
    end)
end

---------------------------------------------------------------------------
-- Clock, idle, login and logout
---------------------------------------------------------------------------

local ticks = 0
local function tick()
    if not ns.db then return end
    ticks = ticks + 1
    local s = ns.Live()
    if s then
        local st = S()
        if s.state == "running" then
            if (st.idlePause or 0) > 0 and lastAct and GetTime() - lastAct >= st.idlePause then
                ns.Pause("idle")
            elseif ticks % 10 == 0 then
                checkpoint(s)
            end
        elseif s.state == "paused" and (s.why == "idle" or s.why == "afk") and (st.idleStop or 0) > 0
            and KM.Now() - (s.pausedAt or KM.Now()) >= st.idleStop then
            ns.Stop("idle")
        end
    end
    if ns.HUDTick then KM.Safe(ns.HUDTick) end
end

local function login()
    local s = ns.Live()
    if not s then return end
    local gap = KM.Now() - (s.tick or s.t0 or KM.Now())
    local st = S()
    if (st.offlineStop or 0) > 0 and gap >= st.offlineStop then
        local rec = ns.Stop("offline")
        if rec then KM.Print(ns, "saved your farming session from earlier: " .. ns.SessionLine(rec) .. ".") end
    elseif s.state == "running" and gap <= RELOAD_GAP then
        local now = GetTime()
        since, bank, lastAct, zoneAt = now, s.act or 0, now, now   -- a /reload: keep running
    elseif s.state == "running" then
        s.state, s.why, s.pausedAt = "paused", "logout", s.tick or KM.Now()
    end
end

function ns.PriceWatch()
    local ids, seen = {}, {}
    local s = ns.Live()
    for id, it in pairs(s and s.items or {}) do
        if it.np and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    return ids
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_DEAD", "GET_ITEM_INFO_RECEIVED")
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("PLAYER_FLAGS_CHANGED") then
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "PLAYER_FLAGS_CHANGED", "player") else pcall(f.RegisterEvent, f, "PLAYER_FLAGS_CHANGED") end
end
local itemPending = false
f:SetScript("OnEvent", function(_, event, a1)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        ns.loggedIn = true
        KM.Safe(ns.Migrate)
        KM.Safe(login)
        if ns.migratedNow and not ns.toldMigration then
            ns.toldMigration = true
            KM.Print("the farm tracker and the farming ledger are one |cfff0c44dFarm Tracker|r now (/farm). "
                .. "What they held is saved in the Farming Ledger as 'Carried over'.")
        end
        if not ns.ticker and C_Timer and C_Timer.NewTicker then ns.ticker = C_Timer.NewTicker(1, function() KM.Safe(tick) end) end
        if ScannerKing and ScannerKing.RegisterCallback then
            KM.Safe(ScannerKing.RegisterCallback, "King_Maker_Tracker", function(e)
                if e == "PRICES_UPDATED" or e == "SCAN_FINISHED" or e == "GUILD_PRICES" then
                    KM.Safe(ns.ValueLater)
                    ns.Changed()
                end
            end)
        end
        if ScannerKing and ScannerKing.Watch then KM.Safe(ScannerKing.Watch, "King_Maker_Tracker", ns.PriceWatch) end
        if ns.UpdateHUD then KM.Safe(ns.UpdateHUD) end
    elseif event == "PLAYER_LOGOUT" then
        KM.Safe(checkpoint)   -- before SavedVariables are written
    elseif event == "PLAYER_DEAD" then
        KM.Safe(ns.Death)
    elseif event == "PLAYER_FLAGS_CHANGED" then
        if KM.Plain(a1) == "player" and UnitIsAFK and KM.Plain(UnitIsAFK("player")) then KM.Safe(ns.Pause, "afk") end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local s = ns.Live()
        if s and s.later and not itemPending then
            itemPending = true
            C_Timer.After(0.2, function() itemPending = false; KM.Safe(ns.ValueLater) end)
        end
    end
end)

-- Tests and the HUD: the in-memory clock state.
function ns.ClockState() return since, bank, lastAct end
