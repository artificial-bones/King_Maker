local _, KM = ...
local ns = KM.Module("Profit")

-- Replay: an item's lots, what used each one up and what's still open, worked out from its journal every time (and
-- cached until that journal or the method changes). Nothing derived is saved, so switching FIFO/LIFO, fixing a bug
-- or undoing a wrong guess recomputes everything.
--
--   ns.Replay(pool, id)       { lots = { lot... }, sales = { { e, parts, unQ } }, gone = { { e, parts, startup } }, deps }
--     lot  = { id, t, k, q0, left, c, v, w, s }      parts = { { lot, q } }
--   Rules: same second: a new lot (b l m o) first, then r, then sales (s n), deposits (d), gone (g). FIFO takes the
--   oldest open lot got at or before the event, LIFO the newest such lot. A sale short of lots takes back the newest
--   "gone" closures from the 30 days before it (they were that sale, read late); an "r" reopens the newest ones the
--   same way. Startup closures (the day-one shortfall) are never taken back or reopened.
--   Basis is applied afterwards: bought (b, m) and opening (o) lots at what they cost, farmed (l) lots at nothing or at
--   their value when looted (the setting); a purchase whose invoice never loaded counts at its worth then.
--   2.8: a crafted or disenchanted lot (k) costs what its inputs' uses (u, e) cost, worked out from the inputs' own
--   replays (so by the same method and setting): the lots each use took, plus any units no lot covered at their worth
--   then; a disenchanted mat gets its share of the item. A use with nothing made of it (an enchant, a bound product)
--   and mail to someone else are final "used or gone" closures; a trade in is a lot, a trade out a sale; mail to your
--   own character is in transit (Recon counts it) and uses nothing up.
--
-- Then the views over a pool, for a period (since) and optionally one character: ns.Summary, ns.Trades, ns.Buys,
-- ns.NotSold, ns.Holdings / ns.Holding, ns.Daily, ns.Sources, ns.ForMail, ns.BoughtHeld; and folding (ns.Fold):
-- detail older than keepDays becomes a checkpoint of the lots still open plus monthly totals.

local ORDER = { b = 1, l = 1, m = 1, o = 1, k = 1, r = 2, s = 3, n = 3, u = 3, e = 3, y = 3, d = 4, g = 5 }
local cache = {}
local gen = 0         -- goes up whenever any journal changes: a crafted lot's cost depends on other items' journals

function ns.Invalidate(pool, id) gen = gen + 1; if pool and id then cache[pool .. "|" .. id] = nil end end
function ns.ClearCache() gen = gen + 1; wipe(cache) end

-- Replay order of an event: a trade in is a new lot, a trade out a sale.
local function orderOf(e)
    if e.k == "t" then return tostring(e.s or ""):sub(1, 3) == "in/" and 1 or 3 end
    return ORDER[e.k] or 9
end
ns.OrderOf = orderOf

local function sortEvents(list)
    table.sort(list, function(a, b)
        if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
        local oa, ob = orderOf(a), orderOf(b)
        if oa ~= ob then return oa < ob end
        return (a.id or 0) < (b.id or 0)
    end)
end

-- A crafted lot's link: "G/2589,2320" -> { g = G, ins = { 2589, 2320 } }; a disenchanted mat's "G/12345/4500" also
-- has share = 4500 (ten-thousandths of the item's cost). nil for anything else (a folded lot keeps no link).
function ns.ParseLink(s)
    if type(s) ~= "string" then return nil end
    local g, ins, share = s:match("^(%d+)/([%d,]*)/?(%d*)$")
    if not g then return nil end
    local out = { g = tonumber(g), ins = {}, share = tonumber(share) }
    for id in ins:gmatch("%d+") do out.ins[#out.ins + 1] = tonumber(id) end
    return out
end

-- Where a mail or trade went: "alt/charKey" -> "alt", charKey; "to/Name" -> "to", Name; "out/Name" -> "out", Name.
function ns.MailTo(s)
    local how, who = tostring(s or ""):match("^(%a+)/(.*)$")
    return how, who
end

-- The item's journal unpacked, the checkpoint's open lots first, sorted for replay.
function ns.Events(pool, id)
    local rec = ns.ItemRec(pool, id)
    local out = {}
    if not rec then return out end
    if rec.ck and rec.ck.lots then
        for _, raw in ipairs(rec.ck.lots) do
            local e = ns.Unpack(raw)
            e.ck = true
            out[#out + 1] = e
        end
    end
    for _, raw in ipairs(rec.e) do out[#out + 1] = ns.Unpack(raw) end
    sortEvents(out)
    return out
end

local function addPart(parts, lot, n)
    for _, p in ipairs(parts) do if p.lot == lot then p.q = p.q + n; return end end
    parts[#parts + 1] = { lot = lot, q = n }
end

-- Replays events (sorted) with a method; the pure core, also used by folding.
--   r.used = { { e, parts, unQ, g = G or nil } }: uses (u, e) and mail to someone else (y); r.byLink[G] = the use
--   r.transit = { e }: mail to your own characters
local function run(evs, lifo, pool, id)
    local r = { lots = {}, sales = {}, gone = {}, deps = {}, used = {}, byLink = {}, transit = {} }
    local function take(e, q)
        local parts = {}
        while q > 0 do
            local pick
            for _, L in ipairs(r.lots) do                         -- r.lots is in time order
                if L.left > 0 and L.t <= e.t then
                    pick = L
                    if not lifo then break end                    -- FIFO: the first open one; LIFO: keep looking
                end
            end
            if not pick then break end
            local n = math.min(q, pick.left)
            pick.left, q = pick.left - n, q - n
            addPart(parts, pick, n)
        end
        return parts, q
    end
    -- the newest closures in the 30 days up to e, units given to fn(part, n) until q runs out
    local function walkBack(e, q, fn)
        for i = #r.gone, 1, -1 do
            if q <= 0 then break end
            local g = r.gone[i]
            if not g.startup and g.e.t <= e.t and g.e.t >= e.t - ns.WINDOW then
                for j = #g.parts, 1, -1 do
                    if q <= 0 then break end
                    local p = g.parts[j]
                    local n = math.min(q, p.q)
                    if n > 0 then p.q = p.q - n; q = q - n; fn(p, n) end
                end
            end
        end
        return q
    end
    for _, e in ipairs(evs) do
        local k = e.k
        if orderOf(e) == 1 then
            if (e.q or 0) > 0 then
                r.lots[#r.lots + 1] = { id = e.id, t = e.t or 0, k = k, q0 = e.q, left = e.q, c = e.c, v = e.v, w = e.w, s = e.s, ck = e.ck,
                    pool = pool, item = id, link = k == "k" and ns.ParseLink(e.s) or nil }
            end
        elseif k == "y" and ns.MailTo(e.s) == "alt" then
            r.transit[#r.transit + 1] = e                         -- to your own character: nothing used up
        elseif k == "u" or k == "e" or k == "y" then
            local parts, short = take(e, e.q or 0)
            if short > 0 then short = walkBack(e, short, function(p, n) addPart(parts, p.lot, n) end) end
            local u = { e = e, parts = parts, unQ = short, g = k ~= "y" and tonumber(e.s) or nil }
            r.used[#r.used + 1] = u
            if u.g then r.byLink[u.g] = u end
        elseif k == "s" or k == "n" or k == "t" then
            local parts, short = take(e, e.q or 0)
            if short > 0 then short = walkBack(e, short, function(p, n) addPart(parts, p.lot, n) end) end
            r.sales[#r.sales + 1] = { e = e, parts = parts, unQ = short }
        elseif k == "g" then
            local parts = take(e, e.q or 0)
            r.gone[#r.gone + 1] = { e = e, parts = parts, startup = e.s == "startup" }
        elseif k == "r" then
            walkBack(e, e.q or 0, function(p, n) p.lot.left = p.lot.left + n end)
        elseif k == "d" then
            r.deps[#r.deps + 1] = e
        end
    end
    return r
end

function ns.Replay(pool, id)
    local key = pool .. "|" .. id
    local method = ns.db.settings.method
    local r = cache[key]
    if r and r.method == method then return r end
    r = run(ns.Events(pool, id), method == "lifo", pool, id)
    r.method = method
    cache[key] = r
    return r
end

---------------------------------------------------------------------------
-- Basis and the numbers of one sale
---------------------------------------------------------------------------

-- What a lot's units cost you, in all.
function ns.LotBasis(L, mode, depth)
    mode = mode or ns.db.settings.basis
    if L.k == "l" then return mode == "market" and (L.v or 0) or 0 end
    if L.k == "b" and (L.c or 0) == 0 and L.v then return L.v end   -- the invoice never loaded: its worth then
    if L.k == "k" then
        if L.link then return ns.CraftBasis(L, mode, depth) end
        return mode == "market" and (L.v or L.c or 0) or (L.c or 0)  -- folded: both costs kept, no link
    end
    return L.c or L.v or 0
end

function ns.UnitBasis(L, mode, depth)
    return (L.q0 or 0) > 0 and ns.LotBasis(L, mode, depth) / L.q0 or 0
end

-- What one use (u, e, y) cost: the lots it took, plus (unless lotsOnly) units no lot covered at their worth then,
-- which is what they put into a product.
function ns.UsedBasis(u, mode, depth, lotsOnly)
    local b = 0
    for _, p in ipairs(u.parts) do b = b + p.q * ns.UnitBasis(p.lot, mode, depth) end
    local q = u.e.q or 0
    if not lotsOnly and (u.unQ or 0) > 0 and q > 0 and u.e.v then b = b + u.e.v * u.unQ / q end
    return b
end

-- A folded use's cost (ck.used[G] = "paid:market:t"), or nil.
function ns.FrozenUse(pool, id, g, mode)
    local rec = ns.ItemRec(pool, id)
    local str = rec and rec.ck and rec.ck.used and rec.ck.used[g]
    if not str then return nil end
    local paid, market = tostring(str):match("^(%-?[%d%.]+):(%-?[%d%.]+)")
    return tonumber(mode == "market" and market or paid)
end

-- A crafted (or disenchanted) lot's cost: its inputs' uses, by the method, worked out from their own replays; a
-- disenchanted mat gets its share of the item. Remembered until any journal changes.
function ns.CraftBasis(L, mode, depth)
    depth = (depth or 0) + 1
    local link = L.link
    if not link or depth > 8 then return L.v or 0 end           -- a loop or a very deep chain: its worth then
    L.memo = L.memo or {}
    local m = L.memo[mode]
    if m and m[1] == gen then return m[2] end
    local total, found = 0, false
    for _, inId in ipairs(link.ins) do
        local u = ns.Replay(L.pool, inId).byLink[link.g]
        if u then
            total, found = total + ns.UsedBasis(u, mode, depth), true
        else
            local frozen = ns.FrozenUse(L.pool, inId, link.g, mode)
            if frozen then total, found = total + frozen, true end
        end
    end
    if not found then total = L.v or 0 end                      -- its inputs are gone from the journal: its worth then
    if link.share then total = total * link.share / 10000 end
    total = total + (L.c or 0)
    L.memo[mode] = { gen, total }
    return total
end

function ns.OpenQ(r)
    local n = 0
    for _, L in ipairs(r.lots) do n = n + L.left end
    return n
end

local function partsQ(parts)
    local n = 0
    for _, p in ipairs(parts) do n = n + p.q end
    return n
end

function ns.RecentGoneQ(r, now)
    now = now or KM.Now()
    local n = 0
    for _, g in ipairs(r.gone) do
        if not g.startup and now - (g.e.t or 0) < ns.WINDOW then n = n + partsQ(g.parts) end
    end
    return n
end

-- { q, proceeds, matchedQ, matchedP, unQ, unP, basis, pl, roi, held }
function ns.SaleInfo(sale, mode)
    local e = sale.e
    local q, P = e.q or 0, e.c or 0
    local mq, basis, secs = 0, 0, 0
    for _, p in ipairs(sale.parts) do
        mq = mq + p.q
        basis = basis + p.q * ns.UnitBasis(p.lot, mode)
        secs = secs + p.q * math.max(0, (e.t or 0) - p.lot.t)
    end
    local mp = q > 0 and P * mq / q or 0
    local x = { q = q, proceeds = P, matchedQ = mq, matchedP = mp, unQ = q - mq, unP = P - mp, basis = basis }
    if mq > 0 then
        x.pl = mp - basis
        x.roi = basis > 0 and x.pl / basis or nil
        x.held = secs / mq
        x.secs = secs
    end
    return x
end

function ns.GoneBasis(g, mode)
    local b = 0
    for _, p in ipairs(g.parts) do b = b + p.q * ns.UnitBasis(p.lot, mode) end
    return b
end

---------------------------------------------------------------------------
-- Words for lots
---------------------------------------------------------------------------

local fmt = date or (os and os.date)
function ns.Day(t) return fmt and fmt("%d %b", t) or tostring(t) end
function ns.When(t) return fmt and fmt("%d %b %H:%M", t) or tostring(t) end

ns.HOW = { b = "AH", l = "Farmed", m = "Vendor", o = "Opening", k = "Crafted", t = "Trade" }
ns.HOW_LONG = { b = "auction house", l = "farmed", m = "vendor", o = "opening stock", k = "crafted", t = "trade" }

-- How a lot came: the short word ("AH", "Quest", "DE") and the long one ("quest reward", "disenchanted").
function ns.How(L)
    if L.k == "l" and L.s == "quest" then return "Quest" end
    if L.k == "k" and L.link and L.link.share then return "DE" end
    return ns.HOW[L.k] or L.k
end
function ns.HowLong(L)
    if L.k == "l" and L.s == "quest" then return "quest reward" end
    if L.k == "k" and L.link and L.link.share then return "disenchanted" end
    return ns.HOW_LONG[L.k] or L.k
end

-- What a use or mail did with its units: "used in a craft", "crafted with", "disenchanted", "mailed to Bob".
function ns.UseText(u)
    local k = u.e.k
    if k == "y" then
        local _, who = ns.MailTo(u.e.s)
        return "mailed to " .. (who and who ~= "" and who or "someone")
    end
    if k == "e" then return "disenchanted" end
    return u.g and "crafted with" or "used in a craft"
end

-- "AH 7 Nov", "farmed", "opening", "crafted 9 Nov", "2 lots", "-"
function ns.FromText(parts)
    local live = {}
    for _, p in ipairs(parts) do if p.q > 0 then live[#live + 1] = p end end
    if #live == 0 then return "-" end
    if #live > 1 then return #live .. " lots" end
    local L = live[1].lot
    if L.k == "b" then return "AH " .. ns.Day(L.t) end
    if L.k == "m" then return "vendor " .. ns.Day(L.t) end
    if L.k == "t" then return "trade " .. ns.Day(L.t) end
    if L.k == "k" then return (L.link and L.link.share and "DE " or "crafted ") .. ns.Day(L.t) end
    if L.k == "l" then return L.s == "quest" and "quest" or "farmed" end
    return "opening"
end

-- "20 of 20 bought 3 Nov at 1s each (auction house, Jay)"
function ns.PartText(pool, p, mode)
    local L = p.lot
    local who = ns.CharOf(pool, L.w)
    who = who and who:match("^[^%-]+") or nil
    local got = L.k == "l" and (L.s == "quest" and "got" or "farmed") or (L.k == "o" and "owned")
        or (L.k == "k" and (L.link and L.link.share and "disenchanted" or "crafted")) or (L.k == "t" and "traded for") or "bought"
    local each = ns.UnitBasis(L, mode)
    local cost = (L.k == "l" and (mode or ns.db.settings.basis) ~= "market") and "free"
        or ("at " .. KM.Money(each) .. " each")
    if L.k == "o" then cost = "at " .. KM.Money(each) .. " each (its value then)" end
    if L.k == "k" then cost = "at " .. KM.Money(each) .. " each (what went into it)" end
    return p.q .. " of " .. L.q0 .. " " .. got .. " " .. ns.Day(L.t) .. " " .. cost
        .. " (" .. ns.HowLong(L) .. (who and (", " .. who) or "") .. ")"
end

---------------------------------------------------------------------------
-- Views over a pool
---------------------------------------------------------------------------

-- Every item a pool has a journal for, minus the ones left out (grey, soulbound, quest).
function ns.ItemIDs(pool)
    local p = ns.Pool(pool)
    local out = {}
    if not p then return out end
    for id in pairs(p.items) do if not ns.Excluded(id) then out[#out + 1] = id end end
    table.sort(out)
    return out
end

local function charIndex(pool, charKey)
    if not charKey then return nil end
    local p = ns.Pool(pool)
    if not p then return -1 end
    for i, k in ipairs(p.chars) do if k == charKey then return i end end
    return -1
end

-- "YYYY-MM" for a time (UTC), and that month's first second.
function ns.MonthKey(t) return fmt and fmt("!%Y-%m", t) or "?" end
local function daysFromCivil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
function ns.MonthStart(key)
    local y, m = tostring(key):match("^(%d+)%-(%d+)$")
    if not y then return nil end
    return daysFromCivil(tonumber(y), tonumber(m), 1) * 86400
end

-- Month strings: "sales:units:proceeds:basisPaid:basisMarket:unknownQ:unknownP:gonePaid:goneMarket:deposits:heldUnitSecs"
local MONTH = { "sales", "units", "proceeds", "basisPaid", "basisMarket", "unknownQ", "unknownP", "gonePaid", "goneMarket",
    "deposits", "secs" }
function ns.UnpackMonth(s)
    local out, i = {}, 0
    for part in (tostring(s or "") .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if MONTH[i] then out[MONTH[i]] = tonumber(part) or 0 end
    end
    for _, k in ipairs(MONTH) do out[k] = out[k] or 0 end
    return out
end
function ns.PackMonth(m)
    local parts = {}
    for i, k in ipairs(MONTH) do parts[i] = tostring(math.floor((m[k] or 0) + 0.5)) end
    return table.concat(parts, ":")
end
local function addMonth(t, key, add)
    local m = ns.UnpackMonth(t[key])
    for k, v in pairs(add) do m[k] = (m[k] or 0) + v end
    t[key] = ns.PackMonth(m)
end

-- Totals for a period: { realized, proceeds, basis, sales, units, deposits, depositN, unknownP, unknownQ, unknownSales,
--   gonePending, goneFinal, goneStartup, allIn, roi, held (units), cost, worth, ifSold, underwater, underwaterLoss,
--   untraced, untracedWorth, noPrice, folded = months counted }. charKey: that character's sales and deposits only.
function ns.Summary(since, charKey, pool)
    pool = pool or ns.MyPool()
    since = since or 0
    local mode = ns.db.settings.basis
    local w = charIndex(pool, charKey)
    local now = KM.Now()
    local S = { realized = 0, proceeds = 0, basis = 0, sales = 0, units = 0, deposits = 0, depositN = 0, unknownP = 0,
        unknownQ = 0, unknownSales = 0, gonePending = 0, goneFinal = 0, goneStartup = 0, goneUsed = 0, secs = 0, matchedQ = 0,
        held = 0, cost = 0, worth = 0, ifSold = 0, underwater = 0, underwaterLoss = 0, untraced = 0, untracedWorth = 0,
        noPrice = 0, folded = 0 }
    for _, id in ipairs(ns.ItemIDs(pool)) do
        local r = ns.Replay(pool, id)
        for _, sale in ipairs(r.sales) do
            local e = sale.e
            if (e.t or 0) >= since and (not w or e.w == w) then
                local x = ns.SaleInfo(sale, mode)
                S.sales, S.units = S.sales + 1, S.units + x.q
                if x.matchedQ > 0 then
                    S.proceeds, S.basis = S.proceeds + x.matchedP, S.basis + x.basis
                    S.matchedQ, S.secs = S.matchedQ + x.matchedQ, S.secs + x.secs
                end
                if x.unQ > 0 then S.unknownP, S.unknownQ, S.unknownSales = S.unknownP + x.unP, S.unknownQ + x.unQ, S.unknownSales + 1 end
            end
        end
        for _, d in ipairs(r.deps) do
            if (d.t or 0) >= since and (not w or d.w == w) then S.deposits, S.depositN = S.deposits + (d.c or 0), S.depositN + 1 end
        end
        for _, g in ipairs(r.gone) do
            local gt = g.e.t or 0
            local b = ns.GoneBasis(g, mode)
            if g.startup then
                if since == 0 then S.goneStartup = S.goneStartup + b end
            elseif gt >= since then
                if now - gt < ns.WINDOW then S.gonePending = S.gonePending + b else S.goneFinal = S.goneFinal + b end
            end
        end
        -- 2.8: used with nothing to show for it (an enchant, a bound product) and mail to someone else: final at once
        for _, u in ipairs(r.used) do
            if not u.g and (u.e.t or 0) >= since and (not w or u.e.w == w) then
                local b = ns.UsedBasis(u, mode, nil, true)
                S.goneFinal, S.goneUsed = S.goneFinal + b, S.goneUsed + b
            end
        end
    end
    -- folded months (all characters only)
    local p = ns.Pool(pool)
    if p and not charKey then
        for key, str in pairs(p.months or {}) do
            local ms = ns.MonthStart(key)
            if ms and ms >= since then
                local m = ns.UnpackMonth(str)
                S.folded = S.folded + 1
                S.sales, S.units = S.sales + m.sales, S.units + m.units + m.unknownQ
                S.proceeds = S.proceeds + m.proceeds
                S.basis = S.basis + (mode == "market" and m.basisMarket or m.basisPaid)
                S.matchedQ, S.secs = S.matchedQ + m.units, S.secs + m.secs
                S.unknownQ, S.unknownP = S.unknownQ + m.unknownQ, S.unknownP + m.unknownP
                S.goneFinal = S.goneFinal + (mode == "market" and m.goneMarket or m.gonePaid)
                S.deposits = S.deposits + m.deposits
            end
        end
    end
    S.realized = S.proceeds - S.basis - S.deposits
    S.roi = S.basis > 0 and (S.proceeds - S.basis) / S.basis or nil
    S.heldAvg = S.matchedQ > 0 and S.secs / S.matchedQ or nil
    S.allIn = S.realized + S.unknownP - S.gonePending - S.goneFinal
    -- what you hold now (period-free)
    for _, h in ipairs(ns.Holdings(pool, charKey)) do
        S.held, S.cost = S.held + h.held, S.cost + h.cost
        if h.each then
            S.worth, S.ifSold = S.worth + h.worth, S.ifSold + h.ifSold
            if h.under then S.underwater, S.underwaterLoss = S.underwater + 1, S.underwaterLoss + h.ifSold end
        elseif h.held > 0 then
            S.noPrice = S.noPrice + 1
        end
        if (h.untraced or 0) > 0 then
            S.untraced = S.untraced + h.untraced
            S.untracedWorth = S.untracedWorth + (h.each and h.each * h.untraced or 0)
        end
    end
    return S
end

-- Every sale in the period, newest first.
function ns.Trades(since, charKey, pool)
    pool = pool or ns.MyPool()
    local mode = ns.db.settings.basis
    local w = charIndex(pool, charKey)
    local out = {}
    for _, id in ipairs(ns.ItemIDs(pool)) do
        local r = ns.Replay(pool, id)
        for _, sale in ipairs(r.sales) do
            local e = sale.e
            if (e.t or 0) >= (since or 0) and (not w or e.w == w) then
                local x = ns.SaleInfo(sale, mode)
                x.t, x.item, x.pool, x.kind, x.w = e.t, id, pool, e.k, e.w
                x.char = ns.CharOf(pool, e.w)
                if e.k == "t" then x.partner = select(2, ns.MailTo(e.s)) end
                x.parts = sale.parts
                x.each = x.q > 0 and x.proceeds / x.q or nil
                x.costEach = x.matchedQ > 0 and x.basis / x.matchedQ or nil
                x.from = ns.FromText(sale.parts)
                x.partsOut = {}
                for _, p in ipairs(sale.parts) do
                    x.partsOut[#x.partsOut + 1] = { t = p.lot.t, kind = p.lot.k, q = p.q, cost = p.q * ns.UnitBasis(p.lot, mode),
                        char = ns.CharOf(pool, p.lot.w) }
                end
                out[#out + 1] = x
            end
        end
    end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.item < b.item end)
    return out
end

-- Every lot got in the period (the per-buy ledger), newest first.
function ns.Buys(since, charKey, pool)
    pool = pool or ns.MyPool()
    local mode = ns.db.settings.basis
    local w = charIndex(pool, charKey)
    local out = {}
    for _, id in ipairs(ns.ItemIDs(pool)) do
        local r = ns.Replay(pool, id)
        local each = ns.ValueOf(id, 1)
        local info = {}
        for _, L in ipairs(r.lots) do info[L] = { sold = 0, used = 0, made = 0, realized = 0, uses = {} } end
        for _, sale in ipairs(r.sales) do
            local x = ns.SaleInfo(sale, mode)
            local per = x.matchedQ > 0 and x.matchedP / x.matchedQ or 0
            for _, p in ipairs(sale.parts) do
                local i = info[p.lot]
                if i and p.q > 0 then
                    i.sold = i.sold + p.q
                    i.realized = i.realized + p.q * (per - ns.UnitBasis(p.lot, mode))
                    i.uses[#i.uses + 1] = { t = sale.e.t, q = p.q, kind = sale.e.k, each = per }
                end
            end
        end
        for _, g in ipairs(r.gone) do
            for _, p in ipairs(g.parts) do
                local i = info[p.lot]
                if i and p.q > 0 then
                    i.used = i.used + p.q
                    i.uses[#i.uses + 1] = { t = g.e.t, q = p.q, kind = g.startup and "startup" or "g", pending = not g.startup and KM.Now() - g.e.t < ns.WINDOW }
                end
            end
        end
        for _, u in ipairs(r.used) do
            for _, p in ipairs(u.parts) do
                local i = info[p.lot]
                if i and p.q > 0 then
                    if u.g then i.made = i.made + p.q else i.used = i.used + p.q end
                    i.uses[#i.uses + 1] = { t = u.e.t, q = p.q, kind = u.e.k, linked = u.g ~= nil, text = ns.UseText(u) }
                end
            end
        end
        for _, L in ipairs(r.lots) do
            if L.t >= (since or 0) and (not w or L.w == w) then
                local i = info[L]
                local unit = ns.UnitBasis(L, mode)
                local row = { item = id, pool = pool, t = L.t, k = L.k, how = ns.How(L), q = L.q0, left = L.left,
                    each = unit, cost = ns.LotBasis(L, mode), sold = i.sold, used = i.used, made = i.made, realized = i.sold > 0 and i.realized or nil,
                    uses = i.uses, char = ns.CharOf(pool, L.w), src = L.s, lot = L, valueThen = L.v }
                if L.left > 0 and each then row.openPL = L.left * (each - unit) end
                row.status = L.left <= 0 and "closed" or (L.left < L.q0 and "part" or "open")
                row.age = KM.Now() - L.t
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.item < b.item end)
    return out
end

-- Stock that left with no sale, in the period (startup closures only with since = 0), newest first.
function ns.NotSold(since, charKey, pool)
    pool = pool or ns.MyPool()
    local mode = ns.db.settings.basis
    local now = KM.Now()
    local out = {}
    for _, id in ipairs(ns.ItemIDs(pool)) do
        local r = ns.Replay(pool, id)
        for _, g in ipairs(r.gone) do
            local gt = g.e.t or 0
            local q = partsQ(g.parts)
            local inPeriod = g.startup and (since or 0) == 0 or (not g.startup and gt >= (since or 0))
            if q > 0 and inPeriod then
                local row = { item = id, pool = pool, t = gt, q = q, cost = ns.GoneBasis(g, mode), from = ns.FromText(g.parts),
                    parts = g.parts }
                local whoW
                for _, p in ipairs(g.parts) do if p.q > 0 then whoW = whoW or p.lot.w end end
                row.char = ns.CharOf(pool, whoW)
                if g.startup then row.status, row.state = "before tracking", "startup"
                elseif now - gt < ns.WINDOW then
                    local left = math.ceil((ns.WINDOW - (now - gt)) / 86400)
                    row.status, row.state, row.daysLeft = "pending: " .. left .. " day" .. (left == 1 and "" or "s") .. " left", "pending", left
                else row.status, row.state = "used or gone", "final" end
                if not charKey or row.char == charKey then out[#out + 1] = row end
            end
        end
        for _, u in ipairs(r.used) do
            local q = partsQ(u.parts)
            local ut = u.e.t or 0
            if not u.g and q > 0 and ut >= (since or 0) then
                local row = { item = id, pool = pool, t = ut, q = q, cost = ns.UsedBasis(u, mode, nil, true), from = ns.FromText(u.parts),
                    parts = u.parts, char = ns.CharOf(pool, u.e.w), status = ns.UseText(u), state = "final", kind = u.e.k }
                if not charKey or row.char == charKey then out[#out + 1] = row end
            end
        end
    end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.item < b.item end)
    return out
end

local STALE = 7 * 86400

-- One item you hold: { item, held, cost, avg, each, worth, ifSold, roi, oldest, age, ages = { <7d, 7-30d, >30d },
--   owned, untraced, onAH, under, stale, lots }. charKey: that character's count at the pool's average cost.
function ns.Holding(pool, id, charKey)
    if not (pool and id) then return nil end
    local mode = ns.db.settings.basis
    local r = ns.Replay(pool, id)
    local now = KM.Now()
    local h = { item = id, pool = pool, held = 0, cost = 0, ages = { 0, 0, 0 }, lots = {} }
    for _, L in ipairs(r.lots) do
        if L.left > 0 then
            h.held = h.held + L.left
            h.cost = h.cost + L.left * ns.UnitBasis(L, mode)
            h.oldest = math.min(h.oldest or L.t, L.t)
            local age = now - L.t
            local b = age < 7 * 86400 and 1 or (age < 30 * 86400 and 2 or 3)
            h.ages[b] = h.ages[b] + L.left
            h.lots[#h.lots + 1] = L
        end
    end
    h.avg = h.held > 0 and h.cost / h.held or nil
    h.owned = ns.Owned and ns.Owned(pool, id) or nil
    if h.owned then h.untraced = math.max(0, h.owned - h.held) end
    local places = InventoryKing and InventoryKing.GetPlaces and KM.Safe(InventoryKing.GetPlaces, id) or nil
    h.onAH, h.where = 0, {}
    for who, pl in pairs(places or {}) do
        if ns.PoolOf(who) == pool then
            local n = (pl.bags or 0) + (pl.bank or 0) + (pl.mail or 0) + (pl.ah or 0)
            h.onAH = h.onAH + (pl.ah or 0)
            if n > 0 then h.where[who] = n end
        end
    end
    if charKey then
        local mine = h.where[charKey] or 0
        local avg = h.avg or 0
        h.held, h.cost, h.untraced = mine, mine * avg, 0
        h.ages = { mine, 0, 0 }
    end
    local v, src = KM.ItemValue(id)
    if v and v > 0 then                       -- no auction price and nothing from a vendor: "no price", outside the totals
        h.each, h.src = v, src
        h.worth = v * h.held
        h.ifSold = h.worth - h.cost
        h.roi = h.cost > 0 and h.ifSold / h.cost or nil
        h.under = h.held > 0 and h.avg ~= nil and v < h.avg - 0.5
        h.breakEven = h.avg and h.avg / KM.AH_CUT or nil
    end
    if src == "ah" and ScannerKing and ScannerKing.GetMarketPrice then
        local _, t = ScannerKing.GetMarketPrice(id)
        h.scanned = t
        h.stale = t and now - t > STALE or false
    end
    -- 2.8: what you asked for what's on the auction house (the Sales Ledger's postings, newest first: the ones that add
    -- up to what's listed, posted by this pool's characters in the last two days)
    if h.onAH > 0 and MailKing and MailKing.GetPosts then
        local units, value = 0, 0
        for _, p in ipairs(KM.Safe(MailKing.GetPosts, id) or {}) do
            if units >= h.onAH then break end
            if (p.each or 0) > 0 and p.c and ns.PoolOf(p.c) == pool and now - (p.t or 0) < 2 * 86400 then
                local n = math.min(p.n or 1, h.onAH - units)
                units, value = units + n, value + n * p.each
            end
        end
        if units > 0 then
            h.listed, h.listedEach = units, value / units
            if h.avg and h.avg > 0 then h.listedROI = (h.listedEach * KM.AH_CUT - h.avg) / h.avg end
        end
    end
    h.age = h.oldest and now - h.oldest or nil
    return h
end

-- Every item you hold (or own untraced) in the pool, by what you'd make selling it now.
-- only: a set { [itemID] = true } (your favorites) to keep.
function ns.Holdings(pool, charKey, only)
    pool = pool or ns.MyPool()
    local out, seen = {}, {}
    local function consider(id)
        if seen[id] or ns.Excluded(id) or (only and not only[id]) then return end
        seen[id] = true
        local h = ns.Holding(pool, id, charKey)
        if h and (h.held > 0 or (h.untraced or 0) > 0) then out[#out + 1] = h end
    end
    for _, id in ipairs(ns.ItemIDs(pool)) do consider(id) end
    if not charKey then
        for _, id in ipairs(ns.OwnedIDs and ns.OwnedIDs(pool) or {}) do consider(id) end
    end
    table.sort(out, function(a, b)
        local x, y = a.ifSold or -math.huge, b.ifSold or -math.huge
        if x ~= y then return x > y end
        return a.item < b.item
    end)
    return out
end

-- Realized per day in the period: { { t = day start, pl, sales, best = trade } }, oldest first. week = true buckets weeks.
function ns.Daily(since, charKey, pool, week)
    local size = week and 7 * 86400 or 86400
    local by, order = {}, {}
    local function slot(t)
        local d
        if week then
            d = math.floor(t / size) * size
        else
            local tt = fmt and fmt("*t", t)
            d = tt and (t - (tt.hour * 3600 + tt.min * 60 + tt.sec)) or math.floor(t / size) * size
        end
        local s = by[d]
        if not s then s = { t = d, pl = 0, sales = 0 }; by[d] = s; order[#order + 1] = s end
        return s
    end
    for _, x in ipairs(ns.Trades(since, charKey, pool)) do
        local s = slot(x.t)
        s.sales = s.sales + 1
        if x.pl then
            s.pl = s.pl + x.pl
            if not s.best or x.pl > (s.best.pl or -math.huge) then s.best = x end
        end
    end
    pool = pool or ns.MyPool()
    local w = charIndex(pool, charKey)
    for _, id in ipairs(ns.ItemIDs(pool)) do
        for _, d in ipairs(ns.Replay(pool, id).deps) do
            if (d.t or 0) >= (since or 0) and (not w or d.w == w) then
                local s = slot(d.t)
                s.pl = s.pl - (d.c or 0)
            end
        end
    end
    table.sort(order, function(a, b) return a.t < b.t end)
    return order
end

-- Realized in the period by where the units came from: { b, l, m, o, k, t = P&L, dep = deposits lost }.
function ns.Sources(since, charKey, pool)
    local out = { b = 0, l = 0, m = 0, o = 0, k = 0, t = 0, dep = 0, n = { b = 0, l = 0, m = 0, o = 0, k = 0, t = 0 } }
    local mode = ns.db.settings.basis
    for _, x in ipairs(ns.Trades(since, charKey, pool)) do
        if x.matchedQ > 0 then
            local per = x.matchedP / x.matchedQ
            for _, p in ipairs(x.parts) do
                local k = p.lot.k
                if out[k] and p.q > 0 then
                    out[k] = out[k] + p.q * (per - ns.UnitBasis(p.lot, mode))
                    out.n[k] = out.n[k] + p.q
                end
            end
        end
    end
    pool = pool or ns.MyPool()
    local w = charIndex(pool, charKey)
    for _, id in ipairs(ns.ItemIDs(pool)) do
        for _, d in ipairs(ns.Replay(pool, id).deps) do
            if (d.t or 0) >= (since or 0) and (not w or d.w == w) then out.dep = out.dep + (d.c or 0) end
        end
    end
    return out
end

-- Per item in the period: { item, sold (units), realized, sales, proceeds (everything the sales brought), matchedQ
-- (units a lot covered), basis, heldAvg (seconds, over the covered units) } merged with what you hold.
function ns.ByItem(since, charKey, pool)
    pool = pool or ns.MyPool()
    local by = {}
    local function row(id)
        local r = by[id]
        if not r then r = { item = id, sold = 0, sales = 0, proceeds = 0, matchedQ = 0, secs = 0 }; by[id] = r end
        return r
    end
    for _, x in ipairs(ns.Trades(since, charKey, pool)) do
        local r = row(x.item)
        r.sold, r.sales = r.sold + x.q, r.sales + 1
        r.proceeds = r.proceeds + (x.proceeds or 0)
        r.matchedQ, r.secs = r.matchedQ + (x.matchedQ or 0), r.secs + (x.secs or 0)
        if x.pl then r.realized = (r.realized or 0) + x.pl; r.basis = (r.basis or 0) + x.basis end
    end
    for _, h in ipairs(ns.Holdings(pool, charKey)) do
        local r = row(h.item)
        r.hold = h.held
        r.avg, r.each, r.ifSold, r.age, r.under, r.stale, r.h = h.avg, h.each, h.ifSold, h.age, h.under, h.stale, h
    end
    local out = {}
    for _, r in pairs(by) do
        r.roi = (r.realized and (r.basis or 0) > 0) and r.realized / r.basis or nil
        r.avgPrice = r.sold > 0 and r.proceeds / r.sold or nil
        r.avgCost = r.matchedQ > 0 and (r.basis or 0) / r.matchedQ or nil
        r.heldAvg = r.matchedQ > 0 and r.secs > 0 and r.secs / r.matchedQ or nil
        if r.sold > 0 or (r.hold or 0) > 0 then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        local x, y = a.realized or -math.huge, b.realized or -math.huge
        if x ~= y then return x > y end
        x, y = a.ifSold or -math.huge, b.ifSold or -math.huge
        if x ~= y then return x > y end
        return a.item < b.item
    end)
    return out
end

-- Every lot of an item, newest first, for /pnl item and the API.
function ns.Lots(pool, id)
    local mode = ns.db.settings.basis
    local r = ns.Replay(pool, id)
    local uses = {}
    for _, s in ipairs(r.sales) do for _, p in ipairs(s.parts) do if p.q > 0 then uses[p.lot] = (uses[p.lot] or 0) + 1 end end end
    for _, g in ipairs(r.gone) do for _, p in ipairs(g.parts) do if p.q > 0 then uses[p.lot] = (uses[p.lot] or 0) + 1 end end end
    for _, u in ipairs(r.used) do for _, p in ipairs(u.parts) do if p.q > 0 then uses[p.lot] = (uses[p.lot] or 0) + 1 end end end
    local out = {}
    for i = #r.lots, 1, -1 do
        local L = r.lots[i]
        out[#out + 1] = { t = L.t, kind = L.k, q = L.q0, left = L.left, cost = ns.LotBasis(L, mode), value = L.v,
            char = ns.CharOf(pool, L.w), src = L.s, uses = uses[L] or 0 }
    end
    return out
end

-- The P&L of one Sales Ledger sale: { pl, basis, unknownQ, matchedQ, parts, text } or nil (not in the journal).
function ns.ForMail(entry)
    if entry.k ~= "sale" then return nil end
    local id = entry.item or (ns.EntryItem and ns.EntryItem(entry))
    if not id then return nil end
    local pool = ns.PoolOf(entry.c or KM.Char())
    if not ns.ItemRec(pool, id) then return nil end
    local proceeds = math.floor((entry.g or 0) - (entry.cut or 0) + 0.5)
    local t, q = math.floor((entry.t or 0) + 0.5), entry.n or 1
    local mode = ns.db.settings.basis
    for _, sale in ipairs(ns.Replay(pool, id).sales) do
        local e = sale.e
        if e.k == "s" and e.t == t and (e.q or 0) == q and (e.c or 0) == proceeds then
            local x = ns.SaleInfo(sale, mode)
            local parts, lines = {}, {}
            for _, p in ipairs(sale.parts) do
                if p.q > 0 then
                    parts[#parts + 1] = { t = p.lot.t, kind = p.lot.k, q = p.q, cost = p.q * ns.UnitBasis(p.lot, mode) }
                    lines[#lines + 1] = ns.PartText(pool, p, mode)
                end
            end
            return { pl = x.pl, basis = x.basis, unknownQ = x.unQ, matchedQ = x.matchedQ, roi = x.roi, held = x.held,
                parts = parts, lines = lines }
        end
    end
    return nil
end

-- What you bought at the auction house since a time and still hold (the Sales Ledger's Still holding tile).
function ns.BoughtHeld(since, charKey)
    local pool = charKey and ns.PoolOf(charKey) or ns.MyPool()
    local w = charIndex(pool, charKey)
    local mode = ns.db.settings.basis
    local out = { held = 0, worth = 0, unpriced = 0, units = 0 }
    for _, id in ipairs(ns.ItemIDs(pool)) do
        local r = ns.Replay(pool, id)
        local each
        for _, L in ipairs(r.lots) do
            if L.k == "b" and L.left > 0 and L.t >= (since or 0) and (not w or L.w == w) then
                local cost = L.left * ns.UnitBasis(L, mode)
                out.held, out.units = out.held + cost, out.units + L.left
                if each == nil then each = KM.ItemValue(id) or false end
                if each and each > 0 then out.worth = out.worth + math.floor(each * L.left)
                else out.worth, out.unpriced = out.worth + cost, out.unpriced + L.left end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Folding: detail older than keepDays -> a checkpoint of the open lots + monthly totals
---------------------------------------------------------------------------

local CAP = 400       -- an item with more events than this folds early
local MAX_MONTHS = 24 -- per-item months kept (the pool's totals stay forever)

-- Folds one item's events older than cutoff. The method in use now is the one the folded months keep.
function ns.Fold(pool, id, cutoff)
    local rec = ns.ItemRec(pool, id)
    if not rec then return false end
    local old, keep = {}, {}
    for _, raw in ipairs(rec.e) do
        local t = tonumber(raw:match("^%d+:(%d+):")) or 0
        if t < cutoff then old[#old + 1] = raw else keep[#keep + 1] = raw end
    end
    if #old == 0 then return false end
    local evs = {}
    if rec.ck and rec.ck.lots then for _, raw in ipairs(rec.ck.lots) do local e = ns.Unpack(raw); e.ck = true; evs[#evs + 1] = e end end
    for _, raw in ipairs(old) do evs[#evs + 1] = ns.Unpack(raw) end
    sortEvents(evs)
    local r = run(evs, ns.db.settings.method == "lifo", pool, id)
    local p = ns.Pool(pool, true)
    p.months = p.months or {}
    rec.m = rec.m or {}
    local function add(t, fields)
        local key = ns.MonthKey(t)
        addMonth(rec.m, key, fields)
        addMonth(p.months, key, fields)
    end
    for _, sale in ipairs(r.sales) do
        local paid, market = ns.SaleInfo(sale, "paid"), ns.SaleInfo(sale, "market")
        add(sale.e.t, { sales = 1, units = paid.matchedQ, proceeds = paid.matchedP, basisPaid = paid.basis,
            basisMarket = market.basis, unknownQ = paid.unQ, unknownP = paid.unP, secs = paid.secs or 0 })
    end
    for _, g in ipairs(r.gone) do
        if not g.startup then add(g.e.t, { gonePaid = ns.GoneBasis(g, "paid"), goneMarket = ns.GoneBasis(g, "market") }) end
    end
    for _, d in ipairs(r.deps) do add(d.t, { deposits = d.c or 0 }) end
    -- 2.8: a use whose product may still be open keeps its cost; a use with nothing made of it is a closure
    local used = {}
    for g, str in pairs(rec.ck and rec.ck.used or {}) do
        local t = tonumber(tostring(str):match(":(%d+)$")) or 0
        if t >= cutoff - 31 * 86400 then used[g] = str end        -- by then its product has folded too
    end
    for _, u in ipairs(r.used) do
        if u.g then
            used[u.g] = string.format("%d:%d:%d", math.floor(ns.UsedBasis(u, "paid") + 0.5),
                math.floor(ns.UsedBasis(u, "market") + 0.5), u.e.t or 0)
        else
            add(u.e.t, { gonePaid = ns.UsedBasis(u, "paid", nil, true), goneMarket = ns.UsedBasis(u, "market", nil, true) })
        end
    end
    local lots = {}
    for _, L in ipairs(r.lots) do
        if L.left > 0 then
            local f = L.left / L.q0
            local c, v, s = L.c and L.c * f or nil, L.v and L.v * f or nil, L.s
            if L.k == "k" and L.link then                         -- a crafted lot keeps its cost, not its link
                c, v, s = ns.LotBasis(L, "paid") * f, ns.LotBasis(L, "market") * f, nil
            end
            lots[#lots + 1] = ns.Pack({ id = L.id, t = L.t, k = L.k, q = L.left, c = c, v = v, w = L.w, s = s })
        end
    end
    rec.ck = { t = cutoff, lots = lots, used = next(used) and used or nil }
    rec.e = keep
    -- per-item months beyond two years go; the pool's totals stay
    local keys = {}
    for k in pairs(rec.m) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys - MAX_MONTHS do rec.m[keys[i]] = nil end
    ns.Invalidate(pool, id)
    return true
end

-- Folds every item that has detail older than keepDays (or more than CAP events), a few hundred items a frame.
function ns.FoldAll(now)
    now = now or KM.Now()
    local cutoff = now - ns.db.settings.keepDays * 86400
    local jobs = {}
    for pool, p in pairs(ns.db.pools) do
        for id, rec in pairs(p.items) do
            local due = false
            for _, raw in ipairs(rec.e) do
                if (tonumber(raw:match("^%d+:(%d+):")) or 0) < cutoff then due = true; break end
            end
            local c = cutoff
            if not due and #rec.e > CAP then
                -- too many events: fold all but the newest 300, never anything under 31 days old
                local ts = {}
                for _, raw in ipairs(rec.e) do ts[#ts + 1] = tonumber(raw:match("^%d+:(%d+):")) or 0 end
                table.sort(ts)
                c = math.min(ts[#ts - 300] or cutoff, now - 31 * 86400)
                due = c > cutoff
            end
            if due then jobs[#jobs + 1] = { pool, id, c } end
        end
    end
    ns.db.lastFold = now
    if #jobs == 0 then return 0 end
    ns.Background(jobs, function(j) ns.Fold(j[1], j[2], j[3]) end, function() ns.Changed(jobs[1][1], jobs[1][2]) end)
    return #jobs
end

---------------------------------------------------------------------------
-- Background work: a few hundred items per frame (Econ's pattern)
---------------------------------------------------------------------------

local BATCH = 150
local jobs, jobRunning = {}, false
local function runJobs()
    local job = jobs[1]
    if not job then jobRunning = false; return end
    C_Timer.After(0, runJobs)   -- always come back next frame, even if one item's data is bad
    local n = 0
    while n < BATCH and job.i <= #job.list do
        pcall(job.fn, job.list[job.i])
        job.i, n = job.i + 1, n + 1
    end
    if job.i > #job.list then
        table.remove(jobs, 1)
        if job.done then pcall(job.done) end
    end
end
function ns.Background(list, fn, done)
    table.insert(jobs, { list = list, fn = fn, done = done, i = 1 })
    if not jobRunning then jobRunning = true; C_Timer.After(0, runJobs) end
end

---------------------------------------------------------------------------
-- Words: /pnl status, /pnl item
---------------------------------------------------------------------------

function ns.StatusLine()
    local S = ns.Summary(KM.Now() - 7 * 86400)
    return "realized, last 7 days " .. KM.Money(S.realized) .. " (" .. S.sales .. " sale" .. (S.sales == 1 and "" or "s")
        .. "). If sold now " .. KM.Money(S.ifSold) .. " on " .. KM.Commas(S.held) .. " items held (cost " .. KM.Money(S.cost)
        .. ")." .. (S.underwater > 0 and (" " .. S.underwater .. " underwater, " .. KM.Money(S.underwaterLoss) .. ".") or "")
end

function ns.ItemReport(id)
    local pool = ns.MyPool()
    local h = ns.Holding(pool, id)
    local lines = { KM.ItemText(id) .. ": " .. (h.held > 0 and (h.held .. " held at " .. KM.Money(h.avg) .. " each"
        .. (h.each and (", worth " .. KM.Money(h.each) .. " each now after the cut") or ", no price")) or "none held") .. "." }
    if (h.untraced or 0) > 0 then lines[#lines + 1] = h.untraced .. " more you own have no lot (untraced)." end
    local r = ns.Replay(pool, id)
    local mode = ns.db.settings.basis
    for i = #r.lots, math.max(1, #r.lots - 9), -1 do
        local L = r.lots[i]
        local uses = {}
        for _, s in ipairs(r.sales) do
            for _, p in ipairs(s.parts) do if p.lot == L and p.q > 0 then uses[#uses + 1] = p.q .. " sold " .. ns.Day(s.e.t) end end
        end
        for _, g in ipairs(r.gone) do
            for _, p in ipairs(g.parts) do if p.lot == L and p.q > 0 then uses[#uses + 1] = p.q .. (g.startup and " before tracking" or " used or gone") end end
        end
        for _, u in ipairs(r.used) do
            for _, p in ipairs(u.parts) do if p.lot == L and p.q > 0 then uses[#uses + 1] = p.q .. " " .. ns.UseText(u) .. " " .. ns.Day(u.e.t) end end
        end
        lines[#lines + 1] = "  " .. ns.How(L) .. " " .. ns.Day(L.t) .. ": " .. L.q0 .. " at "
            .. KM.Money(ns.UnitBasis(L, mode)) .. ", " .. L.left .. " left" .. (#uses > 0 and (" (" .. table.concat(uses, ", ") .. ")") or "")
    end
    if #r.lots == 0 then lines[#lines + 1] = "  No lots yet." end
    return lines
end
