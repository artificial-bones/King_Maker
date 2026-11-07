local _, ns = ...
local API = ns.API

-- Adding up the ledger.
--
-- For any period (and all characters, or just this one):
--   income   = what sold for, minus the auction house cut
--   spent    = what you bought on the auction house
--   lost     = deposits on auctions that expired or were cancelled
--   profit   = income - spent - lost
-- broken down by strategy (Core.lua says how an item gets one) and by item,
-- by who bought from you (or sold to you), and what isn't selling.
--
-- Flips: an item you bought and then sold is a flip, so what you paid and what
-- it sold for land in the same row and its profit is the margin. Something you
-- bought and haven't sold (yet) counts under Purchases.

local FLIP_WINDOW = 30 * 86400 -- a purchase this long before a sale makes it a flip

ns.strategyOf = setmetatable({}, { __mode = "k" }) -- entry -> its strategy in the last Summary

local function key(e) return e.item or e.name end

-- itemKey -> sorted times of purchases, and of sales
local function index(entries)
    local buys, sales = {}, {}
    for _, e in ipairs(entries) do
        local t = e.k == "buy" and buys or e.k == "sale" and sales or nil
        if t and key(e) then
            t[key(e)] = t[key(e)] or {}
            table.insert(t[key(e)], e.t)
        end
    end
    return buys, sales
end

local function anyWithin(times, from, to)
    for _, t in ipairs(times or {}) do if t >= from and t <= to then return true end end
    return false
end

-- The strategy an entry counts under.
function ns.EntryStrategy(e, buys, sales)
    local own, chosen = ns.ItemStrategy(e.item, e.name)
    if chosen then return own end
    local k = key(e)
    if e.k == "buy" then
        if anyWithin(sales[k], e.t, e.t + FLIP_WINDOW) then return "Flips" end
        return "Purchases"
    end
    if anyWithin(buys[k], e.t - FLIP_WINDOW, e.t) then return "Flips" end
    return own
end

local function row(t, k)
    local r = t[k]
    if not r then
        r = { key = k, sales = 0, units = 0, gross = 0, cut = 0, income = 0, spent = 0, bought = 0, lost = 0,
              expired = 0, profit = 0, listSum = 0, listN = 0 }
        t[k] = r
    end
    return r
end

local function add(r, e)
    if e.k == "sale" then
        r.sales, r.units = r.sales + 1, r.units + (e.n or 1)
        r.gross, r.cut = r.gross + (e.g or 0), r.cut + (e.cut or 0)
        r.income = r.income + (e.g or 0) - (e.cut or 0)
        r.lastSale = math.max(r.lastSale or 0, e.t or 0)
    elseif e.k == "buy" then
        r.bought, r.spent = r.bought + (e.n or 1), r.spent + (e.g or 0)
    else
        r.expired, r.lost = r.expired + 1, r.lost + (e.dep or 0)
        r.lastExpired = math.max(r.lastExpired or 0, e.t or 0)
        if e.each then r.listSum, r.listN = r.listSum + e.each * (e.n or 1), r.listN + (e.n or 1) end
    end
    r.profit = r.income - r.spent - r.lost
end

-- since: server time to start from (0 = everything). onlyChar: "Name-Realm" or nil for all.
-- Returns { sales, gross, cut, income, spent, lost, expired, profit, strategies = { row... },
--           items = { row... }, entries = { entry... } (newest first) }
function ns.Summary(since, onlyChar)
    local all = ns.db.entries
    local buys, sales = index(all)
    local total = row({}, "total")
    local byStrategy, byItem, list = {}, {}, {}
    for _, e in ipairs(all) do
        if (e.t or 0) >= (since or 0) and (not onlyChar or e.c == onlyChar) then
            local s = ns.EntryStrategy(e, buys, sales)
            ns.strategyOf[e] = s -- for the lists; worked out fresh each time, never saved
            add(total, e)
            add(row(byStrategy, s), e)
            local ir = row(byItem, key(e) or "?")
            ir.item, ir.name, ir.strategy = ir.item or e.item, ir.name or e.name, s
            add(ir, e)
            table.insert(list, e)
        end
    end
    local function sorted(t)
        local out = {}
        for _, r in pairs(t) do table.insert(out, r) end
        table.sort(out, function(a, b)
            if a.profit ~= b.profit then return a.profit > b.profit end
            return tostring(a.key) < tostring(b.key)
        end)
        return out
    end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    total.strategies, total.items, total.entries = sorted(byStrategy), sorted(byItem), list
    return total
end

-- Profit per day for the last n days, oldest first: { { day = "10-11", profit, income } }.
function ns.Daily(n, onlyChar)
    local now = ns.Now()
    local today = math.floor(now / 86400)
    local days = {}
    for i = n - 1, 0, -1 do
        local d = today - i
        table.insert(days, { d = d, day = date and date("%m-%d", d * 86400) or tostring(d), profit = 0, income = 0 })
    end
    local s = ns.Summary((today - n + 1) * 86400, onlyChar)
    for _, e in ipairs(s.entries) do
        local slot = days[math.floor(e.t / 86400) - (today - n + 1) + 1]
        if slot then
            local r = row({}, "x"); add(r, e)
            slot.profit, slot.income = slot.profit + r.profit, slot.income + r.income
        end
    end
    return days
end

local function market(id)
    if not (id and ScannerKing and ScannerKing.GetMarketPrice) then return nil end
    return (ScannerKing.GetMarketPrice(id))
end
ns.Market = market

---------------------------------------------------------------------------
-- Buyers: who buys from you (and who you buy from)
---------------------------------------------------------------------------

-- kind "sale": the people who bought from you; "buy": the people you bought from.
-- Returns { rows = { { who, mails, units, gold, first, last, share, goldShare, regular,
--   fav = { item, name, mails, units, gold }, items = { [key] = {...} } } } (most mails first),
--   mails, gold, unknown = mails with no name on them }.
ns.REGULAR = 3 -- this many mails or more makes someone a regular
function ns.Buyers(since, onlyChar, kind)
    kind = kind or "sale"
    local s = ns.Summary(since, onlyChar)
    local by, out = {}, { rows = {}, mails = 0, gold = 0, unknown = 0 }
    for _, e in ipairs(s.entries) do
        if e.k == kind then
            if not e.who or e.who == "" then
                out.unknown = out.unknown + 1
            else
                local r = by[e.who]
                if not r then
                    r = { who = e.who, mails = 0, units = 0, gold = 0, first = e.t, last = e.t, items = {} }
                    by[e.who] = r
                end
                r.mails, r.units, r.gold = r.mails + 1, r.units + (e.n or 1), r.gold + (e.g or 0)
                r.first, r.last = math.min(r.first, e.t), math.max(r.last, e.t)
                local k = key(e) or "?"
                local it = r.items[k]
                if not it then it = { item = e.item, name = e.name, mails = 0, units = 0, gold = 0 }; r.items[k] = it end
                it.mails, it.units, it.gold = it.mails + 1, it.units + (e.n or 1), it.gold + (e.g or 0)
                out.mails, out.gold = out.mails + 1, out.gold + (e.g or 0)
            end
        end
    end
    for _, r in pairs(by) do
        r.share = out.mails > 0 and r.mails / out.mails or 0
        r.goldShare = out.gold > 0 and r.gold / out.gold or 0
        r.each = r.mails > 0 and r.gold / r.mails or 0
        r.regular = r.mails >= ns.REGULAR
        local n = 0
        for _, it in pairs(r.items) do
            n = n + 1
            if not r.fav or it.gold > r.fav.gold or (it.gold == r.fav.gold and it.mails > r.fav.mails) then r.fav = it end
        end
        r.kinds = n
        r.name = r.fav and r.fav.name -- for sorting by favourite
        table.insert(out.rows, r)
    end
    table.sort(out.rows, function(a, b)
        if a.mails ~= b.mails then return a.mails > b.mails end
        if a.gold ~= b.gold then return a.gold > b.gold end
        return a.who < b.who
    end)
    return out
end

-- A buyer's items, best first: { { item, name, mails, units, gold } }.
function ns.BuyerItems(r)
    local list = {}
    for _, it in pairs(r.items) do table.insert(list, it) end
    table.sort(list, function(a, b)
        if a.gold ~= b.gold then return a.gold > b.gold end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

---------------------------------------------------------------------------
-- What isn't selling
---------------------------------------------------------------------------

-- Every item that came back expired or cancelled in the period, worst first (most deposits lost):
-- the item rows of ns.Summary plus
--   through   sell-through: of the auctions that ended, how many sold
--   listEach  your average asking price each on the ones that came back (known for auctions
--             posted while Mail King was running)
--   soldEach  average price each when it did sell
--   market    Scanner King's market price today
--   vsMarket  listEach against the market: 0.25 = asking 25% over it
--   why       "over" (asking 10%+ over the market), "never" (none sold), "slow" (under half sold), or nil
--   held      how many you still have (Inventory King)
function ns.NotSelling(since, onlyChar)
    local s = ns.Summary(since, onlyChar)
    local out = {}
    for _, r in ipairs(s.items) do
        if r.expired > 0 then
            local ended = r.sales + r.expired
            r.through = r.sales / ended
            r.listEach = r.listN > 0 and r.listSum / r.listN or nil
            r.soldEach = r.units > 0 and r.gross / r.units or nil
            r.market = market(r.item)
            r.vsMarket = (r.listEach and r.market and r.market > 0) and (r.listEach / r.market - 1) or nil
            if r.vsMarket and r.vsMarket >= 0.1 then r.why = "over"
            elseif r.sales == 0 then r.why = "never"
            elseif r.through < 0.5 then r.why = "slow"
            else r.why = nil end
            if r.item and InventoryKing and InventoryKing.GetCount then
                local ok, n = pcall(InventoryKing.GetCount, r.item)
                r.held = ok and n or nil
            end
            table.insert(out, r)
        end
    end
    table.sort(out, function(a, b)
        if a.lost ~= b.lost then return a.lost > b.lost end
        if a.expired ~= b.expired then return a.expired > b.expired end
        return tostring(a.key) < tostring(b.key)
    end)
    return out
end

---------------------------------------------------------------------------
-- For other addons
---------------------------------------------------------------------------

-- Copies of the ledger entries: { t, k = "sale"|"buy"|"expired"|"cancelled", item, name, n, g, cut, dep, each, who, c }
function API.GetEntries()
    local out = {}
    for i, e in ipairs(ns.db and ns.db.entries or {}) do
        local c = {}
        for k, v in pairs(e) do c[k] = v end
        out[i] = c
    end
    return out
end

-- Totals since a server time (0 = all): income, spent, lost, profit, sales.
function API.Summary(since)
    local s = ns.Summary(since or 0)
    return { income = s.income, spent = s.spent, lost = s.lost, profit = s.profit, sales = s.sales }
end

function API.StrategyOf(itemID) return (ns.ItemStrategy(itemID)) end

-- Who bought from you since a server time (0 = all): { { who, mails, units, gold, last } }, most mails first.
function API.Buyers(since)
    local out = {}
    for i, r in ipairs(ns.Buyers(since or 0).rows) do
        out[i] = { who = r.who, mails = r.mails, units = r.units, gold = r.gold, last = r.last }
    end
    return out
end

-- Stock moved to Inventory King: how many you hold across every character, when it's installed.
function API.Stock(itemID)
    if InventoryKing and InventoryKing.GetCount then return (InventoryKing.GetCount(itemID)) end
    return 0
end
