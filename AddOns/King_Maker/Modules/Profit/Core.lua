local _, KM = ...
local ns = KM.Module("Profit", { title = "Profit & Loss", short = "P&L", db = "ProfitKingDB" })

-- Profit & Loss (King Maker 2.7): every sale matched to what those units cost you, and what you still hold valued
-- against what you paid. Everything that reaches you becomes a lot (an auction house purchase, loot, a vendor
-- purchase, stock you owned before tracking began); everything that leaves uses lots up, oldest first (FIFO) or
-- newest first (LIFO, a setting). A sale's P&L is what it brought after the 5% cut minus the cost of the units it used.
--
-- Files:
--   Core.lua     saved data, pools, the packed event format, ns.Add, settings, /pnl, the ProfitKing API
--   Journal.lua  what goes in the journal: the Sales Ledger (day one and every new mail), loot, vendors, opening
--                stock, first sightings, Adopt, values filled in once an item loads
--   Replay.lua   lots and their closing, replayed from the journal (never saved); periods, trades, holdings; folding
--   Recon.lua    the counts: what each pool really holds (Inventory), and the "used or gone" / "back again" rule
--   Moves.lua    2.8: crafting, disenchanting, quest rewards, mail you send and trades move cost instead of losing it
--   Page.lua     the Gold > Profit & Loss page, export, Home tile and note, crown line, item tooltip line
--
-- Saved data (ProfitKingDB, account-wide, version 2):
--   { version, start, seq, home, lastFold, settings = { method, basis, tooltip, keepDays }, ui = { ... },
--     pools = { [pool] = { chars = { charKey, ... }, items = { [itemID] = { e = { event... }, ck = { t, lots },
--       m = { ["YYYY-MM"] = month } } }, seen = { [charKey] = { bags, bank, mail } }, months = { [YYYY-MM] = month } } },
--     pend = { "pool|itemID|eventID" } }
-- A pool is one realm and faction ("Realm-Horde"): your characters there share their stock, so mail between alts is
-- not a sale and a sale on the bank alt uses up what the main bought.
-- An event is one packed string "id:t:k:q:c:v:w:s" (empty fields stay empty, trailing ones dropped):
--   b bought at the auction house (c = paid), l looted (c = 0, v = worth when looted, s = loot kind), m bought from a
--   vendor, o opening stock (c = v; s = start | bags | bank | mail | adopt), s sold at the auction house (c = what it
--   brought after the cut), n sold to a vendor, d deposit lost (c), g gone: the count fell with no event (s = startup
--   for the day-one shortfall), r back: the count rose while recent closures were open. w = the character's index in
--   the pool's chars list. The journal is append-only except: v filled in once an item loads, same-day loot growing in
--   place, and a vendor sale removed when you buy the same stack back in the same visit.
-- 2.8 adds (each links a use to what it made through a group id G, the id of the event that made the product):
--   k crafted or disenchanted into (a lot; s = "G/inputItemIDs" for a craft, "G/sourceItemID/share" for disenchanted
--     mats, share in ten-thousandths; c = nothing; v = worth then): its cost is what the inputs' uses cost, by the method
--   u used in a craft and e disenchanted (s = G, or "used" when nothing came of it: an enchant, a bound product; v = what
--     the units were worth, which is what units no lot covered count at)
--   y mailed away (s = "alt/charKey": in transit to your own character, nothing used up; "to/Name": someone else, used
--     up at once)
--   t traded (s = "in/Name": a lot, c = what you gave for it; "out/Name": a sale, c = what you got for it)
--   A fold keeps what each folded use cost under ck.used[G] = "paid:market:t" (its product may still be open), and a
--   folded crafted lot gets c = its cost (farmed free), v = its cost (farmed at value) and no link.

ProfitKing = { API_VERSION = 1 }
local API = ProfitKing
ns.API = API

ns.WINDOW = 30 * 86400          -- a guess ("used or gone") can be undone for this long: the life of any mail
ns.KEEP = { 60, 120, 365 }      -- sale-by-sale detail kept this many days, then monthly totals (never under 60)

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local function defaults(db)
    db.version = db.version or 2
    db.seq = db.seq or 1
    db.settings = db.settings or {}
    local s = db.settings
    if s.method ~= "lifo" then s.method = "fifo" end
    if s.basis ~= "market" then s.basis = "paid" end
    if s.tooltip == nil then s.tooltip = true end
    local keep = tonumber(s.keepDays) or 60
    s.keepDays = (keep >= 365 and 365) or (keep >= 120 and 120) or 60
    db.ui = db.ui or {}
    local u = db.ui
    u.tab = u.tab or "overview"
    u.sub = u.sub or "sale"
    u.filter = u.filter or "all"
    if u.period == nil then u.period = 30 end
    db.pools = db.pools or {}
    db.pend = db.pend or {}
end

-- Runs when King Maker's saved variables load: safe twice.
function ns.InitDB()
    ProfitKingDB = ProfitKingDB or {}
    local db = ProfitKingDB
    -- version 1 (King Maker 2.7.0) is the first; later versions migrate here, each with a comment naming it.
    -- version 2 (King Maker 2.8.0) adds event kinds (k u e y t) and ck.used: a 2.7 journal replays as it is.
    if db.version and db.version < 2 then db.version = 2 end
    defaults(db)
    ns.db = db
    if ns.ClearCache then ns.ClearCache() end
end

-- A character renamed to its full name (KM.RenameChar): its index in each pool keeps pointing at the new key.
function ns.RenameChar(old, new)
    for _, p in pairs(ns.db.pools) do
        for i, who in ipairs(p.chars or {}) do if who == old then p.chars[i] = new end end
        KM.MoveKey(p.seen, old, new)
    end
end

---------------------------------------------------------------------------
-- Pools: one per realm and faction
---------------------------------------------------------------------------

local poolCache = {}

-- "First Last-Realm" -> "Realm"
function ns.RealmOf(who)
    if type(who) ~= "string" then return nil end
    return who:match("^[^%-]+%-(.+)$")
end

local function invChars()
    local inv = KM.mods.Inventory
    return inv and inv.db and inv.db.chars or {}
end

-- The pool a character belongs to: "<realm>-<faction>". The warband bank belongs to the pool you started in.
function ns.PoolOf(who)
    if not who then return nil end
    if who == "Warband" then return ns.db.home or ns.PoolOf(KM.Char()) end
    if poolCache[who] then return poolCache[who] end
    local realm = ns.RealmOf(who) or (GetRealmName and GetRealmName()) or "?"
    local faction
    if who == KM.Char() and UnitFactionGroup then faction = UnitFactionGroup("player") end
    if not faction then
        local c = invChars()[who]
        faction = c and c.faction
    end
    if not faction then
        -- unknown: the realm's only faction among your characters, if there is just one
        local seen
        for k, c in pairs(invChars()) do
            if ns.RealmOf(k) == realm and c.faction then
                if seen and seen ~= c.faction then seen = nil; break end
                seen = c.faction
            end
        end
        faction = seen
    end
    local pool = realm .. "-" .. (faction or "?")
    if faction then poolCache[who] = pool end
    return pool
end

function ns.ClearPools() wipe(poolCache) end

-- The pool's saved table (made on first use).
function ns.Pool(pool, create)
    local p = ns.db.pools[pool]
    if not p and create then
        p = { chars = {}, items = {}, seen = {}, months = {} }
        ns.db.pools[pool] = p
    end
    return p
end

-- This character's pool.
function ns.MyPool() return ns.PoolOf(KM.Char()) end

-- A character's index in the pool's chars list (added on first use).
function ns.CharIndex(pool, who)
    local p = ns.Pool(pool, true)
    for i, k in ipairs(p.chars) do if k == who then return i end end
    table.insert(p.chars, who)
    return #p.chars
end

function ns.CharOf(pool, w)
    local p = ns.Pool(pool)
    return p and w and p.chars[w] or nil
end

-- One item's record in a pool: { e = journal, ck = checkpoint, m = months }.
function ns.ItemRec(pool, id, create)
    local p = ns.Pool(pool, create)
    if not p then return nil end
    local r = p.items[id]
    if not r and create then
        r = { e = {} }
        p.items[id] = r
    end
    return r
end

---------------------------------------------------------------------------
-- Events: "id:t:k:q:c:v:w:s"
---------------------------------------------------------------------------

local FIELDS = { "id", "t", "k", "q", "c", "v", "w", "s" }
local NUM = { id = true, t = true, q = true, c = true, v = true, w = true }

local function int(x) return x and math.floor(x + 0.5) or nil end

function ns.Pack(e)
    local parts = {}
    for i, f in ipairs(FIELDS) do
        local v = e[f]
        if NUM[f] then v = int(v) end
        parts[i] = v ~= nil and tostring(v) or ""
    end
    local n = #parts
    while n > 3 and parts[n] == "" do parts[n] = nil; n = n - 1 end
    return table.concat(parts, ":")
end

function ns.Unpack(str)
    local e, i, n = {}, 1, 0
    while true do
        n = n + 1
        local j = str:find(":", i, true)
        local part = j and str:sub(i, j - 1) or str:sub(i)
        local f = FIELDS[n]
        if f and part ~= "" then e[f] = NUM[f] and tonumber(part) or part end
        if not j then break end
        i = j + 1
    end
    e.raw = str
    return e
end

-- Items that never become lots: grey, soulbound and quest items (Inventory doesn't count bound items, so their lots
-- could never be checked; greys are vendor trash, not stock). Unknown until the item has loaded.
function ns.Excluded(id)
    local i = KM.Item(id)
    if i.class == 12 then return true end
    if i.name and (i.q == 0 or i.bop) then return true end
    return false
end

-- What q of an item are worth now (KM.ItemValue: market after the cut, vendor floor); nil while it's loading.
function ns.ValueOf(id, q)
    local v = KM.ItemValue(id)
    if v == nil then return nil end
    return int(v * (q or 1))
end

local changedSoon = false
local callbacks = {}

local function fire()
    changedSoon = false
    for _, fn in pairs(callbacks) do pcall(fn, "CHANGED") end
    KM.Refresh("profit")
end

-- The journal changed: forget that item's replay, tell listeners (once, half a second later).
function ns.Changed(pool, id)
    if ns.Invalidate then ns.Invalidate(pool, id) end
    if not changedSoon then
        changedSoon = true
        C_Timer.After(0.5, fire)
    end
end

-- Kinds whose worth is filled in once the item loads.
local PENDING = { b = true, l = true, m = true, o = true, k = true, u = true, e = true }

-- An event id for a group of events written together (a craft, a disenchant), used as the product's own id.
function ns.Reserve()
    local id = ns.db.seq
    ns.db.seq = ns.db.seq + 1
    return id
end

-- Appends one event; fields { t, q, c, v, who, s, id (a reserved one) }. Same-day loot of the same kind by the same character grows the
-- day's lot instead. Returns the event id (or the grown one's).
function ns.Add(pool, id, k, f)
    if not (pool and id and k) then return nil end
    local rec = ns.ItemRec(pool, id, true)
    local t = int(f.t or KM.Now())
    local w = f.who and ns.CharIndex(pool, f.who) or f.w
    if k == "l" then
        local day = math.floor(t / 86400)
        for i = #rec.e, math.max(1, #rec.e - 40), -1 do
            local o = ns.Unpack(rec.e[i])
            if o.k == "l" and o.w == w and o.s == f.s and math.floor(o.t / 86400) == day then
                o.q = (o.q or 0) + (f.q or 0)
                local wasPending = o.v == nil
                o.v = (o.v and f.v) and (o.v + f.v) or nil
                o.c = 0
                rec.e[i] = ns.Pack(o)
                if o.v == nil and not wasPending then table.insert(ns.db.pend, pool .. "|" .. id .. "|" .. o.id) end
                ns.Changed(pool, id)
                return o.id
            end
        end
    end
    local e = { id = f.id or ns.db.seq, t = t, k = k, q = f.q or 0, c = f.c, v = f.v, w = w, s = f.s }
    if not f.id then ns.db.seq = ns.db.seq + 1 end
    table.insert(rec.e, ns.Pack(e))
    if e.v == nil and (PENDING[k] or (k == "t" and tostring(f.s or ""):sub(1, 3) == "in/")) then
        table.insert(ns.db.pend, pool .. "|" .. id .. "|" .. e.id)
    end
    ns.Changed(pool, id)
    return e.id
end

-- Rewrites one event in place (fn gets the unpacked event and changes it; return false to delete it).
function ns.Edit(pool, id, evid, fn)
    local rec = ns.ItemRec(pool, id)
    if not rec then return false end
    for i, raw in ipairs(rec.e) do
        if tonumber(raw:match("^(%d+):")) == evid then
            local e = ns.Unpack(raw)
            if fn(e) == false then table.remove(rec.e, i) else rec.e[i] = ns.Pack(e) end
            ns.Changed(pool, id)
            return true
        end
    end
    return false
end

-- Is an event like this (same kind, time, units and money) already in the item's journal?
function ns.Has(pool, id, k, t, q, c)
    local rec = ns.ItemRec(pool, id)
    if not rec then return false end
    t, q, c = int(t), int(q), int(c)
    for _, raw in ipairs(rec.e) do
        local e = ns.Unpack(raw)
        if e.k == k and e.t == t and (e.q or 0) == (q or 0) and (e.c or 0) == (c or 0) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

function ns.Settings() return ns.db.settings end

function ns.SetMethod(m)
    ns.db.settings.method = m == "lifo" and "lifo" or "fifo"
    if ns.ClearCache then ns.ClearCache() end
    KM.Print(ns, ns.db.settings.method == "lifo" and "sales now use up your newest stock first (LIFO). Every number is worked out again."
        or "sales now use up your oldest stock first (FIFO). Every number is worked out again.")
    fire()
end

function ns.SetBasis(b)
    ns.db.settings.basis = b == "market" and "market" or "paid"
    KM.Print(ns, ns.db.settings.basis == "market" and "farmed items now cost their value when looted."
        or "farmed items now cost nothing: selling them is all profit.")
    fire()
end

-- "Oldest first - farmed free" (the counting button's label)
function ns.CountingText()
    local s = ns.db.settings
    return (s.method == "lifo" and "Newest first" or "Oldest first") .. " - farmed " .. (s.basis == "market" and "at value" or "free")
end

StaticPopupDialogs.KINGMAKER_PROFIT_RESET = {
    text = "Start Profit & Loss over? It forgets every lot and match, then reads your Sales Ledger again. Farmed and vendor lots from before are lost.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() ns.Reset() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Wipes the pools and runs day one again from the Sales Ledger.
function ns.Reset()
    wipe(ns.db.pools); wipe(ns.db.pend)
    ns.db.start, ns.db.home, ns.db.lastFold = nil, nil, nil
    if ns.ClearCache then ns.ClearCache() end
    KM.Print(ns, "started over.")
    if ns.FirstRun then ns.FirstRun() end
    fire()
end

KM.RegisterSettings({ id = "profit", label = "Profit & Loss", order = 16, rows = {
    { type = "header", label = "Profit & Loss" },
    { type = "choice", label = "Sales use up", options = {
        { "fifo", "Oldest first (FIFO)", "A sale uses up the units you've had longest. What you still hold is what you bought most recently." },
        { "lifo", "Newest first (LIFO)", "A sale uses up the units you got most recently: the last thing you bought is what you sold." } },
      get = function() return ns.db.settings.method end, set = function(v) ns.SetMethod(v) end },
    { type = "choice", label = "Farmed items cost", options = {
        { "paid", "Nothing", "What you loot cost you nothing, so selling it is all profit." },
        { "market", "Value when looted", "What you loot costs what it was worth when you looted it, so P&L shows only what selling added on top of the Farming Ledger." } },
      get = function() return ns.db.settings.basis end, set = function(v) ns.SetBasis(v) end },
    { type = "check", label = "Your cost in item tooltips", tip = "A line in item tooltips: what the units you hold cost you, and how that compares with selling them now.",
      get = function() return ns.db.settings.tooltip end, set = function(v) ns.db.settings.tooltip = v and true or false end },
    { type = "choice", label = "Keep sale-by-sale detail for", options = { { 60, "60 days" }, { 120, "120 days" }, { 365, "365 days" } },
      tip = "Older sales are folded into monthly totals, so your saved data stays small. The King Dashboard keeps everything.",
      get = function() return ns.db.settings.keepDays end, set = function(v) ns.db.settings.keepDays = v end },
    { type = "text", label = "Every auction house purchase and everything you loot becomes a lot. Each sale uses up lots (oldest first, or newest first) and its profit is what it brought after the 5% cut minus what those units cost. Crafting and disenchanting move what the mats cost into what they make; mail to your own characters moves nothing. Stock that leaves without a sale (used, eaten, given away) is \"used or gone\", shown beside your profit, never in it, and undone if it turns up again within 30 days. Items you own that no lot explains are \"untraced\": valued, never given a made-up cost." },
    { type = "button", label = "Count untraced items as opening stock", tip = "Every item you own beyond its lots becomes a lot at today's value, as if tracking began today for those units.",
      func = function() if ns.Adopt then ns.Adopt() end end },
    { type = "button", label = "Start the ledger over", tip = "Forgets every lot and match and reads your Sales Ledger again. Asks first.",
      func = function() StaticPopup_Show("KINGMAKER_PROFIT_RESET") end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/pnl   open Profit & Loss (or /km profit)\n/pnl status   realized 7 days, if sold now, items held, underwater\n/pnl item [link]   an item's lots\n/pnl fifo | lifo   how sales use up your stock\n/pnl farmed free | value\n/pnl adopt   count untraced items as opening stock\n/pnl export   trades and lots as text\n/pnl reset yes   start the ledger over" },
} })

---------------------------------------------------------------------------
-- /pnl
---------------------------------------------------------------------------

SLASH_PROFITKING1 = "/pnl"
SLASH_PROFITKING2 = "/profitloss"
SlashCmdList.PROFITKING = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if not ns.db then return end
    if cmd == "" or cmd == "show" then
        if KM.IsShown("profit") then KM.Toggle(false) else KM.Show("profit") end
    elseif cmd == "status" then
        KM.Print(ns, ns.StatusLine and ns.StatusLine() or "nothing yet.")
    elseif cmd == "item" then
        local id = KM.ItemID(rest)
        if not id and rest ~= "" and KM.mods.Mail and KM.mods.Mail.ItemID then id = KM.Safe(KM.mods.Mail.ItemID, rest) end
        if not id then KM.Print(ns, "/pnl item [link]: shift-click an item into the line.") return end
        for _, line in ipairs(ns.ItemReport and ns.ItemReport(id) or {}) do KM.Print(ns, line) end
    elseif cmd == "fifo" or cmd == "lifo" then
        ns.SetMethod(cmd)
    elseif cmd == "farmed" then
        local r = rest:lower()
        if r == "free" or r == "nothing" then ns.SetBasis("paid")
        elseif r == "value" or r == "market" then ns.SetBasis("market")
        else KM.Print(ns, "/pnl farmed free | value") end
    elseif cmd == "adopt" then
        if ns.Adopt then ns.Adopt() end
    elseif cmd == "export" then
        if ns.Export then ns.Export() end
    elseif cmd == "reset" and rest:lower() == "yes" then
        ns.Reset()
    else
        KM.Print(ns, "/pnl   open Profit & Loss (or /km profit)")
        KM.Print(ns, "/pnl status   realized 7 days, if sold now, items held, underwater")
        KM.Print(ns, "/pnl item [link]   an item's lots: held, average cost, every lot and what used it")
        KM.Print(ns, "/pnl fifo | lifo   sales use up your oldest (FIFO) or newest (LIFO) stock first")
        KM.Print(ns, "/pnl farmed free | value   farmed items cost nothing, or their value when looted")
        KM.Print(ns, "/pnl adopt   count untraced items as opening stock")
        KM.Print(ns, "/pnl export   trades and lots as comma-separated text")
        KM.Print(ns, "/pnl reset yes   start the ledger over from the Sales Ledger")
    end
end

---------------------------------------------------------------------------
-- For other addons (functions only; every table returned is a copy)
---------------------------------------------------------------------------

local function copy(t, depth)
    if type(t) ~= "table" then return t end
    depth = depth or 0
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" and depth < 4 then out[k] = copy(v, depth + 1)
        elseif type(v) ~= "table" then out[k] = v end
    end
    return out
end
ns.Copy = copy

-- fn("CHANGED") after the journal changed (debounced 0.5 s); pcall'd. Registering again with the same owner replaces it.
function API.RegisterCallback(owner, fn)
    if type(fn) ~= "function" then return false end
    callbacks[owner or fn] = fn
    return true
end
function API.UnregisterCallback(owner) callbacks[owner] = nil end

-- True once tracking has begun (day one has run): Home's profit tile and the crown line are P&L's from then on.
function API.IsTracking() return ns.db and ns.db.start ~= nil or false end

-- { held, cost, avg, each (value now), worth, ifSold, oldest, untraced, onAH, listed, listedEach } for an item you
-- hold, or nil. listed / listedEach (2.8): units on the auction house and the price you asked for them, from postings.
function API.Basis(itemID, pool)
    if not (ns.db and ns.Holding) then return nil end
    local h = ns.Holding(pool or ns.MyPool(), tonumber(itemID))
    if not h or (h.held or 0) <= 0 then return nil end
    return { held = h.held, cost = h.cost, avg = h.avg, each = h.each, worth = h.worth, ifSold = h.ifSold,
        oldest = h.oldest, untraced = h.untraced, onAH = h.onAH, listed = h.listed, listedEach = h.listedEach }
end

-- Totals since a server time (0 = everything), for all characters or one.
function API.Summary(since, charKey)
    if not (ns.db and ns.Summary) then return nil end
    return copy(ns.Summary(since or 0, charKey, charKey and ns.PoolOf(charKey) or nil), 0)
end

-- Every lot of an item, newest first: { t, kind, q, left, cost, value, char, src, uses }.
function API.Lots(itemID, pool)
    if not (ns.db and ns.Lots) then return {} end
    return copy(ns.Lots(pool or ns.MyPool(), tonumber(itemID)))
end

-- Every sale since a server time, newest first: { t, item, q, proceeds, basis, pl, roi, held, char, parts }.
function API.Trades(since, charKey)
    if not (ns.db and ns.Trades) then return {} end
    local out = {}
    for i, s in ipairs(ns.Trades(since or 0, charKey, charKey and ns.PoolOf(charKey) or nil)) do
        out[i] = { t = s.t, item = s.item, q = s.q, proceeds = s.proceeds, basis = s.basis, pl = s.pl, roi = s.roi,
            held = s.held, char = s.char, unknownQ = s.unQ, parts = copy(s.partsOut) }
    end
    return out
end

-- { pl, basis, unknownQ, parts } for a Sales Ledger sale entry (MailKing.GetEntries' shape), or nil.
function API.ForMail(entry)
    if not (ns.db and ns.ForMail and type(entry) == "table") then return nil end
    local r = ns.ForMail(entry)
    return r and copy(r) or nil
end

-- What you bought at the auction house since a server time and still hold: { held = cost of it, worth = at today's
-- price after the cut, unpriced = units with no price (counted at cost), units }. charKey: bought by that character.
function API.BoughtHeld(since, charKey)
    if not (ns.db and ns.BoughtHeld) then return nil end
    return copy(ns.BoughtHeld(since or 0, charKey))
end
