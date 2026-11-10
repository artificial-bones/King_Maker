local _, KM = ...
local ns = KM.Module("Inventory")
local API = ns.API

-- What it's all worth.
--
-- Each item is valued at Scanner King's market price (from a Deep Scan), or
-- its lowest buyout if you'd rather (/ik price lowest). An item the auction
-- house has no price for counts at what a vendor pays, unless you turn that
-- off (/ik vendor off). Soulbound items were never recorded.
--
-- Net worth = gold on every character + gold waiting in their mailboxes
--             + what every item is worth.

-- copper each, and where it came from: "market", "lowest", "vendor" (nil: no price).
function ns.Price(id)
    local p
    if ScannerKing then
        if ns.db.ui.price == "lowest" and ScannerKing.GetPrice then
            p = ScannerKing.GetPrice(id)
            if p then return p, "lowest" end
        end
        if ScannerKing.GetMarketPrice then
            local m, _, _, real = ScannerKing.GetMarketPrice(id)
            if m then return m, real and "market" or "lowest" end
        end
        if ScannerKing.GetPrice then
            p = ScannerKing.GetPrice(id)
            if p then return p, "lowest" end
        end
    end
    if ns.db.ui.vendor then
        local _, _, sell = ns.ItemInfo(id)
        if sell and sell > 0 then return sell, "vendor" end
    end
    return nil
end

-- Does a row pass the filter's search text? Matches the item's name, or its category.
local function matches(r, search)
    if not search or search == "" then return true end
    local name = ns.ItemInfo(r.item)
    if name and name:lower():find(search, 1, true) then return true end
    return ns.ClassName(r.cls):lower():find(search, 1, true) or ns.SubclassName(r.cls, r.sub):lower():find(search, 1, true)
end

-- The item list.
-- filter = { who = "Name-Realm" or "Warband" or nil (everyone), place = "bags"|"bank"|"mail"|"ah"|nil,
--            search = text, cls = classID, sub = subclassID, strategy = Mail King strategy }
-- Returns { rows = { row... }, value, count, unpriced, cats = { [cls] = { value, count, subs = { [sub] = {...} } } },
--           strategies = { [name] = { value, count } } } where a row is
--   { item, name, cls, sub, strategy, total, bags, bank, mail, ah, chars = { who = n },
--     where = { who = { bags = n, ... } }, each, src, value }.
-- cats and strategies count everything that passes who, place and search, so the sidebar can show
-- what's in each category whichever one is picked.
function ns.Items(filter)
    filter = filter or {}
    local search = filter.search and filter.search:lower():match("^%s*(.-)%s*$")
    local byItem = {}
    for who, s in pairs(ns.db.stock) do
        if not filter.who or who == filter.who then
            for _, place in ipairs(ns.PLACES) do
                if not filter.place or place == filter.place then
                    for id, n in pairs(s[place] or {}) do
                        local r = byItem[id]
                        if not r then
                            local cls, sub = ns.ClassOf(id)
                            r = { item = id, cls = cls, sub = sub, total = 0, bags = 0, bank = 0, mail = 0, ah = 0,
                                  chars = {}, where = {} }
                            byItem[id] = r
                        end
                        r[place], r.total = r[place] + n, r.total + n
                        r.chars[who] = (r.chars[who] or 0) + n
                        r.where[who] = r.where[who] or {}
                        r.where[who][place] = (r.where[who][place] or 0) + n
                    end
                end
            end
        end
    end
    local out = { rows = {}, value = 0, count = 0, unpriced = 0, cats = {}, strategies = {} }
    local function tally(t, r)
        t.value, t.count = t.value + (r.value or 0), t.count + r.total
    end
    for id, r in pairs(byItem) do
        if r.total > 0 and matches(r, search) then
            r.name = ns.ItemInfo(id)
            r.each, r.src = ns.Price(id)
            r.value = r.each and r.each * r.total or nil
            r.strategy = ns.Strategy(id)
            local c = out.cats[r.cls]
            if not c then c = { value = 0, count = 0, subs = {} }; out.cats[r.cls] = c end
            tally(c, r)
            c.subs[r.sub] = c.subs[r.sub] or { value = 0, count = 0 }
            tally(c.subs[r.sub], r)
            if r.strategy then
                out.strategies[r.strategy] = out.strategies[r.strategy] or { value = 0, count = 0 }
                tally(out.strategies[r.strategy], r)
            end
            if (not filter.cls or r.cls == filter.cls) and (not filter.sub or r.sub == filter.sub)
                and (not filter.strategy or r.strategy == filter.strategy) then
                table.insert(out.rows, r)
                tally(out, r)
                if not r.each then out.unpriced = out.unpriced + 1 end
            end
        end
    end
    table.sort(out.rows, function(a, b)
        if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
        return a.item < b.item
    end)
    return out
end

-- What one character's (or the warband bank's) items are worth.
local function assets(who)
    local total, count = 0, 0
    for _, place in ipairs(ns.PLACES) do
        for id, n in pairs((ns.db.stock[who] or {})[place] or {}) do
            local each = ns.Price(id)
            total, count = total + (each or 0) * n, count + n
        end
    end
    return total, count
end

-- Every character, richest first, and the warband bank last:
-- { { who, class, level, faction, gold, mail, assets, items, worth, seen, bankSeen } }
function ns.Characters()
    local out = {}
    for _, who in ipairs(ns.Known()) do
        local c = ns.db.chars[who] or {}
        local a, n = assets(who)
        local seen = ns.Seen(who)
        table.insert(out, { who = who, class = c.class, level = c.level, faction = c.faction,
            gold = c.gold or 0, mail = c.mail or 0, assets = a, items = n,
            worth = (c.gold or 0) + (c.mail or 0) + a, seen = c.seen or seen.bags, bankSeen = seen.bank })
    end
    table.sort(out, function(x, y)
        if (x.who == ns.WARBAND) ~= (y.who == ns.WARBAND) then return y.who == ns.WARBAND end
        if x.worth ~= y.worth then return x.worth > y.worth end
        return x.who < y.who
    end)
    return out
end

-- { total, gold (on characters), mail (in mailboxes), assets (items), items (how many), chars }
function ns.NetWorth()
    local w = { total = 0, gold = 0, mail = 0, assets = 0, items = 0, chars = 0 }
    for _, c in ipairs(ns.Characters()) do
        w.gold, w.mail, w.assets, w.items = w.gold + c.gold, w.mail + c.mail, w.assets + c.assets, w.items + c.items
        if c.who ~= ns.WARBAND then w.chars = w.chars + 1 end
    end
    w.total = w.gold + w.mail + w.assets
    return w
end

---------------------------------------------------------------------------
-- For other addons
---------------------------------------------------------------------------

-- How many of an item you own on every character: total, { ["Name-Realm"] = n }.
function API.GetCount(itemID)
    local total, by = 0, {}
    for who, s in pairs(ns.db and ns.db.stock or {}) do
        for _, place in ipairs(ns.PLACES) do
            local n = (s[place] or {})[itemID]
            if n then total = total + n; by[who] = (by[who] or 0) + n end
        end
    end
    return total, by
end

-- { total, gold, mail, assets, items, chars }, all in copper.
function API.NetWorth()
    if not ns.db then return nil end
    return ns.NetWorth()
end

-- Copies of every character's row (see ns.Characters).
function API.GetCharacters()
    if not ns.db then return {} end
    return ns.Characters()
end
