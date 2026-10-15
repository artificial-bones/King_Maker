local _, ns = ...
local API = ns.API

-- Adding up the ledger.
--
-- For any period (and all characters, or just this one):
--   income   = what sold for, minus the auction house cut
--   spent    = what you bought on the auction house
--   lost     = deposits on auctions that expired or were cancelled
--   profit   = income - spent - lost
-- broken down by strategy (Core.lua says how an item gets one) and by item.
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
              expired = 0, profit = 0 }
        t[k] = r
    end
    return r
end

local function add(r, e)
    if e.k == "sale" then
        r.sales, r.units = r.sales + 1, r.units + (e.n or 1)
        r.gross, r.cut = r.gross + (e.g or 0), r.cut + (e.cut or 0)
        r.income = r.income + (e.g or 0) - (e.cut or 0)
    elseif e.k == "buy" then
        r.bought, r.spent = r.bought + (e.n or 1), r.spent + (e.g or 0)
    else
        r.expired, r.lost = r.expired + 1, r.lost + (e.dep or 0)
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

-- Gold on every character, and the total.
function ns.Gold()
    local list, total = {}, 0
    for who, g in pairs(ns.db.gold) do
        table.insert(list, { who = who, m = g.m or 0, t = g.t })
        total = total + (g.m or 0)
    end
    table.sort(list, function(a, b) return a.m > b.m end)
    return total, list
end

---------------------------------------------------------------------------
-- For other addons
---------------------------------------------------------------------------

-- Copies of the ledger entries: { t, k = "sale"|"buy"|"expired"|"cancelled", item, name, n, g, cut, dep, who, c }
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
