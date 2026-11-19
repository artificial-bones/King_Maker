local _, KM = ...
local ns = KM.Module("Reputation")

-- What Supply Writs cost and pay. Prices come from Scanner (the lowest buyout from your last scan); what a crafted
-- item costs to make comes from Crafting Profits (Market's recipe and its Evaluate, materials at the cheaper of the
-- auction house and a vendor). Nothing here is saved.
--
--   ns.ItemCost(item)    -> cost (copper each, the cheaper way), how ("buy" | "craft"), buy, craft
--   ns.OrderCost(o)      -> cost for the whole order (count x each), how
--   ns.HeldRows(key)     -> the orders a character holds: { order, n, done, cost, how, net, perGold, cust }
--   ns.CheapestRep()     -> ways to buy rep today, cheapest gold per rep point first (the three sealed writ tiers and
--                           the receipt path)
--   ns.FavorRows(mode)   -> the faction's recipes for Merchant's Favor with Crafting Profits' profit per craft
--   ns.AllRows(filter)   -> every order with done today / held for the filterable list

local function market() local m = KM.mods.Market return (m and m.db and m.Evaluate) and m or nil end

function ns.Price(item)
    if not (item and ScannerKing and ScannerKing.GetPrice) then return nil end
    local p = ns.Call(ScannerKing.GetPrice, item)
    return type(p) == "number" and p > 0 and p or nil
end

-- product item -> { spell, ... } from Market's recipes (built once; Market's own learned recipes count too)
local byItem
local function recipesFor(item)
    local m = market()
    if not m then return nil end
    if not byItem then
        byItem = {}
        local list = ns.Call(m.Recipes) or {}
        for _, r in ipairs(list) do
            if r.item then
                byItem[r.item] = byItem[r.item] or {}
                table.insert(byItem[r.item], r)
            end
        end
    end
    return byItem[item]
end
function ns.ResetRecipeIndex() byItem = nil end

-- What one costs to craft (materials bought, the cheaper of auction and vendor each), or nil.
function ns.CraftCost(item)
    local m = market()
    local list = m and recipesFor(item)
    if not list then return nil end
    local best
    for _, r in ipairs(list) do
        local row = ns.Call(m.Evaluate, r, "buy", { noDE = true })
        if type(row) == "table" and not row.missing and row.cost and (r.made or 1) > 0 then
            local each = row.cost / (r.made or 1)
            if not best or each < best then best = each end
        end
    end
    return best
end

function ns.ItemCost(item)
    if not item or item == 0 then return nil end
    local buy, craft = ns.Price(item), ns.CraftCost(item)
    if buy and craft then
        if craft < buy then return craft, "craft", buy, craft end
        return buy, "buy", buy, craft
    end
    if buy then return buy, "buy", buy, craft end
    if craft then return craft, "craft", buy, craft end
    return nil, nil, buy, craft
end

function ns.OrderCost(o)
    local each, how, buy, craft = ns.ItemCost(o.item)
    if not each then return nil end
    return each * (o.count or 1), how, buy, craft
end

function ns.PouchAvg(tier)
    local t = ns.TIERS and ns.TIERS[tier]
    if not t or not t.pouch then return 0 end
    return ((t.pouch[1] or 0) + (t.pouch[2] or t.pouch[1] or 0)) / 2
end

-- Rep per gold for a cost net of the coin pouch: nil when unknown, math.huge when the pouch covers it.
function ns.PerGold(rep, net)
    if net == nil then return nil end
    if net <= 0 then return math.huge end
    return rep / (net / 10000)
end

---------------------------------------------------------------------------
-- Orders a character holds
---------------------------------------------------------------------------

function ns.HeldRows(key)
    local c = ns.db.chars[key or KM.Char()]
    local out = {}
    if not c then return out end
    for id, n in pairs(c.held or {}) do
        local o = ns.Order(id)
        if o and n > 0 then
            local cost, how = ns.OrderCost(o)
            local rep = ns.OrderRep(o)
            local net = cost and (cost - ns.PouchAvg(o.tier)) or nil
            out[#out + 1] = { order = o, n = n, done = ns.IsDone(c, o), cost = cost, how = how, net = net, rep = rep,
                perGold = ns.PerGold(rep, net), cust = ns.Customer(o) }
        end
    end
    table.sort(out, function(a, b)
        if a.done ~= b.done then return b.done end
        local x, y = a.perGold or -1, b.perGold or -1
        if x ~= y then return x > y end
        return a.order.title < b.order.title
    end)
    return out
end

---------------------------------------------------------------------------
-- The cheapest rep today
---------------------------------------------------------------------------

-- Average cost of what a tier's orders want (each order is as likely): copper, how many were priced, of how many.
function ns.TierAvgCost(tier)
    local sum, n, all = 0, 0, 0
    for _, o in ipairs(ns.ORDER_LIST) do
        if o.tier == tier then
            all = all + 1
            local cost = ns.OrderCost(o)
            if cost then sum, n = sum + cost, n + 1 end
        end
    end
    if n == 0 then return nil, 0, all end
    return sum / n, n, all
end

-- { key, label, rep, writ (price), item (avg), pouch, perRep (copper per rep point), priced, of, favor, crate }
function ns.CheapestRep()
    local rows = {}
    for _, tk in ipairs(ns.TIER_ORDER or {}) do
        local t = ns.TIERS[tk]
        local writ = ns.Price(t.sealed)
        local avg, priced, of = ns.TierAvgCost(tk)
        local pouch = ns.PouchAvg(tk)
        local rep = math.floor(t.rep * (1 + 0.02 * ns.db.settings.diplomat) + 0.5)
        local per = (writ and avg) and (writ + avg - pouch) / rep or nil
        rows[#rows + 1] = { key = tk, label = t.name .. " writ", rep = rep, writ = writ, item = avg, pouch = pouch, perRep = per,
            priced = priced, of = of, sealed = t.sealed }
    end
    local R = ns.RECEIPT
    if R then
        local crate = ns.Price(R.crate)
        rows[#rows + 1] = { key = "receipt", label = "Receipt + crate", rep = R.rep, crate = crate, favor = R.favor, pouch = R.money,
            perRep = crate and (crate - R.money) / R.rep or nil, sealed = R.crate }
    end
    table.sort(rows, function(a, b)
        if (a.perRep == nil) ~= (b.perRep == nil) then return a.perRep ~= nil end
        if a.perRep and a.perRep ~= b.perRep then return a.perRep < b.perRep end
        return a.rep < b.rep
    end)
    return rows
end

-- Copper per rep point of the receipt path and of the cheapest writ tier (for the side-by-side line).
function ns.ReceiptVsWrits()
    local receipt, best
    for _, r in ipairs(ns.CheapestRep()) do
        if r.key == "receipt" then receipt = r elseif r.perRep and (not best or r.perRep < best.perRep) then best = r end
    end
    return receipt, best
end

---------------------------------------------------------------------------
-- Favor shopping
---------------------------------------------------------------------------

local function knowsProf(prof)
    local m = KM.mods.Market
    if not (m and m.db and m.Char) then return nil end
    local mc = ns.Call(m.Char)
    local v = mc and mc.skills and mc.skills[prof]
    if type(v) == "table" then return (v.cur or 0) > 0 end
    return false
end

-- { spell, favor, prof, skill, recipeItem, item, standing, name, profit, perFavor, missing, has, mine }
function ns.FavorRows(mode, mineOnly)
    local m = market()
    mode = mode or (m and m.db.mode == "farm" and "farm" or "buy")
    local out = {}
    for spell, d in pairs(ns.FAVOR_RECIPES or {}) do
        local row = { spell = spell, favor = d[1], prof = d[2], skill = d[3], recipeItem = d[4], item = d[5] ~= 0 and d[5] or nil,
            standing = ns.StandingForFavor(d[1]) }
        row.mine = knowsProf(row.prof)
        if not mineOnly or row.mine then
            local r = m and ns.Call(m.Recipe, spell)
            if r then
                local ev = ns.Call(m.Evaluate, r, mode, { noDE = true })
                if type(ev) == "table" then
                    row.missing = ev.missing
                    if not ev.missing and ev.craft then
                        row.profit = ev.gain or ev.craft   -- Crafting Profits' headline: what crafting beats the materials by
                        row.perFavor = row.profit / math.max(1, row.favor)
                    end
                end
                row.has = m.HasRecipe and ns.Call(m.HasRecipe, spell) or false
            end
            row.name = row.item and ns.ItemName(row.item) or (row.recipeItem and ns.ItemName(row.recipeItem)) or ("Spell " .. spell)
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if (a.profit == nil) ~= (b.profit == nil) then return a.profit ~= nil end
        if a.profit and a.profit ~= b.profit then return a.profit > b.profit end
        if a.favor ~= b.favor then return a.favor < b.favor end
        return a.spell < b.spell
    end)
    return out
end

---------------------------------------------------------------------------
-- Every order, filtered
---------------------------------------------------------------------------

-- filter = { tier, prof, held = bool, notDone = bool }; rows { order, done, held (n, this character), cost, how, rep, cust }
function ns.AllRows(filter)
    filter = filter or {}
    local c = ns.Me()
    local out = {}
    for _, o in ipairs(ns.ORDER_LIST) do
        local n = c.held[o.id] or 0
        local done = ns.IsDone(c, o)
        if (not filter.tier or o.tier == filter.tier) and (not filter.prof or o.prof == filter.prof)
            and (not filter.held or n > 0) and (not filter.notDone or not done) then
            out[#out + 1] = { order = o, done = done, held = n, rep = ns.OrderRep(o), cust = ns.Customer(o) }
        end
    end
    return out
end

-- Costs are worked out only for the rows on screen (Market's Evaluate isn't free).
function ns.CostRow(row)
    if row.costDone then return end
    row.costDone = true
    row.cost, row.how = ns.OrderCost(row.order)
    if row.cost then row.net = row.cost - ns.PouchAvg(row.order.tier) end
    row.perGold = ns.PerGold(row.rep, row.net)
end

---------------------------------------------------------------------------
-- A waypoint to a customer: TomTom when it's there, else the game's own map pin
---------------------------------------------------------------------------

function ns.Waypoint(cust, title)
    if not (cust and cust.map and cust.x and cust.y) then return false end
    if TomTom and TomTom.AddWaypoint then
        local ok = pcall(TomTom.AddWaypoint, TomTom, cust.map, cust.x / 100, cust.y / 100, { title = title or cust.name, from = "King Maker" })
        if ok then return "tomtom" end
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        if C_Map.CanSetUserWaypointOnMap and not ns.Call(C_Map.CanSetUserWaypointOnMap, cust.map) then return false end
        local point = ns.Call(UiMapPoint.CreateFromCoordinates, cust.map, cust.x / 100, cust.y / 100)
        if point and pcall(C_Map.SetUserWaypoint, point) then
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
            return "map"
        end
    end
    return false
end
