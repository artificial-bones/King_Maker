local _, KM = ...
local ns = KM.Module("Profession")

-- The numbers behind the panel. Everything comes from the other modules' public data:
--   Market (recipes, prices, ns.Evaluate / ns.Rank: the same math as Crafting Profits, MODE_LABELS, Skill),
--   ScannerKing (prices, listings), EconKing (averages, trend, units gone a day, history, favorites), InventoryKing
--   (counts), ProfitKing (what you paid for the materials you hold, your recent sales).
-- Market has no public global, so its module namespace is read through KM.mods (same addon). Every call into another
-- module is pcall'd or KM.Safe'd: a missing or broken module hides a line, never the panel.

local CUT = 0.95
ns.CUT = CUT
local call = ns.Call
local DAY = 86400

local function market() local m = KM.mods.Market; return m and m.db and m.Evaluate and m or nil end

---------------------------------------------------------------------------
-- Items, professions, recipes
---------------------------------------------------------------------------

function ns.ItemInfo(id)
    if not id then return {} end
    local get = C_Item and C_Item.GetItemInfo
    local name, _, q, _, _, _, _, _, _, icon
    if get then name, _, q, _, _, _, _, _, _, icon = call(get, id) end
    if not icon and C_Item and C_Item.GetItemIconByID then icon = call(C_Item.GetItemIconByID, id) end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
    return { name = name, q = q, icon = icon }
end

function ns.ItemText(id, fallback)
    local i = ns.ItemInfo(id)
    local hex = KM.UI.QUALITY[i.q or 1] or "ffffff"
    return "|cff" .. hex .. (i.name or fallback or ("Item " .. tostring(id))) .. "|r"
end

local function spellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then return call(C_Spell.GetSpellName, id) end
end
ns.SpellName = spellName

-- "Blacksmithing" (or "Classic Blacksmithing", "Mining") -> Market's profession id.
function ns.ProfID(name)
    local m = market()
    if not (m and name) then return nil end
    local p = m.PROF_BY_NAME[name]
    if p then return p.id end
    for pname, prof in pairs(m.PROF_BY_NAME) do
        if name:find(pname, 1, true) then return prof.id end
    end
end

function ns.ProfName(id)
    local m = market()
    local p = m and m.PROF_BY_ID[id]
    return p and p.name
end

-- Market's recipe for a spell: { spell, item, prof, skill, reagents, made } or nil.
function ns.MarketRecipe(spell)
    local m = market()
    if not (m and spell) then return nil end
    if m.Recipe then return m.Recipe(spell) end
    local r = m.RECIPES[spell] or m.db.learned[spell]
    if not r then return nil end
    return { spell = spell, item = r[1], prof = r[2], skill = r[3] or 0, reagents = r[4], made = r[5] or 1 }
end

-- The recipe spells that make an item in a profession (built once from Market's data).
local byItem
function ns.SpellForItem(profID, item)
    local m = market()
    if not (m and item) then return nil end
    if not byItem then
        byItem = {}
        for spell, r in pairs(m.RECIPES) do
            local key = r[2] .. ":" .. r[1]
            if not byItem[key] or spell < byItem[key] then byItem[key] = spell end
        end
    end
    if profID and byItem[profID .. ":" .. item] then return byItem[profID .. ":" .. item] end
    for spell, r in pairs(m.db.learned) do
        if r[1] == item and (not profID or r[2] == profID) then return spell end
    end
    if not profID then
        for key, spell in pairs(byItem) do
            if key:match(":(%d+)$") == tostring(item) then return spell end
        end
    end
end

---------------------------------------------------------------------------
-- What you own
---------------------------------------------------------------------------

local function charKey() return KM.Char() end -- "First Last-Realm", Inventory's key

local function bagCount(id)
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local n = 0
    for bag = 0, 4 do
        for slot = 1, call(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id then n = n + (info.stackCount or 1) end
        end
    end
    return n
end

-- This character's count (bags and bank when the client says so) and the count on every character.
function ns.Owned(id)
    local mine
    if C_Item and C_Item.GetItemCount then mine = call(C_Item.GetItemCount, id, true) end
    local total, by
    if InventoryKing and InventoryKing.GetCount then total, by = call(InventoryKing.GetCount, id) end
    if mine == nil and type(by) == "table" then mine = by[charKey()] end
    if mine == nil then mine = bagCount(id) end
    mine = mine or 0
    return mine, math.max(total or 0, mine)
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- What one reagent costs: Market's rule (the cheaper of the lowest listing and a vendor), and whether a vendor sells it.
function ns.UnitCost(id)
    local m = market()
    if m then return m.BuyCost(id) end
    if ScannerKing and ScannerKing.GetPrice then return (ScannerKing.GetPrice(id)), false end
end

local function marketOpts()
    local m = market()
    local d = m and m.db or {}
    return { noDE = not d.includeDE and not d.deOnly, deOnly = d.deOnly, noProcs = d.deOnly and d.deNoProcs }
end
ns.MarketOpts = marketOpts

-- Market's verdict for an evaluated row: "craft", "disenchant", "sellraw", "skip" or "noprice".
function ns.Verdict(row, mode)
    if not row then return nil end
    if row.missing or (not row.craft and not row.de) then return "noprice" end
    if row.best == "craft" then return "craft" end
    if row.best == "de" then return "disenchant" end
    return mode == "farm" and "sellraw" or "skip"
end

-- { word, colour, short word for the All crafts table }
ns.VERDICTS = {
    craft = { "CRAFT", "violet", "CRAFT" }, disenchant = { "DISENCHANT", "info", "DE" }, sellraw = { "SELL RAW", "good", "RAW" },
    skip = { "SKIP", "bad", "SKIP" }, noprice = { "NO PRICE", "dim", "N/A" },
}

-- Profit over what the materials cost you in that mode: Buy mats, their price; Use my mats, what they'd fetch raw
-- plus the vendor reagents. nil when there's nothing to divide by.
function ns.Margin(row)
    if not (row and row.gain) then return nil end
    local base = row.mode == "farm" and ((row.raw or 0) + (row.vendorCost or 0)) or row.cost
    if not base or base <= 0 then return nil end
    return row.gain / base
end

-- When the prices were last refreshed (a full or quick scan), or nil.
function ns.PriceTime()
    local sc = KM.mods.Scanner
    local t = sc and sc.db and math.max(tonumber(sc.db.lastDeep) or 0, tonumber(sc.db.lastQuick) or 0) or 0
    return t > 0 and t or nil
end

ns.STALE = 12 * 3600 -- prices older than this get a "scan at the auction house" nudge

function ns.PriceAgeText()
    local t = ns.PriceTime()
    local age = t and ((ScannerKing and ScannerKing.PriceAge and KM.Safe(ScannerKing.PriceAge, t)) or "a while ago")
    local stale = not t or (KM.Now() - t) > ns.STALE
    return (t and ("Prices from " .. age .. ".") or "No price scan yet."), stale
end

---------------------------------------------------------------------------
-- Profit & Loss (optional): what you paid, what you sold
---------------------------------------------------------------------------

function ns.Tracking()
    if not (type(ProfitKing) == "table" and type(ProfitKing.IsTracking) == "function") then return false end
    local ok, on = pcall(ProfitKing.IsTracking)
    return ok and on == true
end

local function basis(id)
    if type(ProfitKing.Basis) ~= "function" then return nil end
    local ok, b = pcall(ProfitKing.Basis, id)
    return ok and type(b) == "table" and b or nil
end

-- One craft's profit at what you paid: for each reagent, the units Profit & Loss says you hold count at their average
-- cost (farmed lots are free, or worth what they were when looted, by P&L's setting), the rest at today's price.
-- { profit (one craft), cost (the card's crafts), covered, units } or nil (not tracking, or no reagent held).
function ns.PaidProfit(c)
    if not (c and c.item and c.buy and ns.Tracking()) then return nil end
    local sale = math.max(c.buy.craftSale or -math.huge, c.buy.deSale or -math.huge)
    if sale == -math.huge then return nil end
    local total, covered, units = 0, 0, 0
    for _, m in ipairs(c.mats) do
        local b = basis(m.id)
        local held, avg = b and tonumber(b.held) or 0, b and tonumber(b.avg)
        local use = avg and math.max(0, math.min(m.need, held)) or 0
        local rest = m.need - use
        if rest > 0 and not m.unit then return nil end
        total = total + use * (avg or 0) + rest * (m.unit or 0)
        covered, units = covered + use, units + m.need
    end
    if covered <= 0 then return nil end
    return { profit = sale - total / c.crafts, cost = total, covered = covered, units = units }
end

-- Your sales of an item in the last 7 days, from Profit & Loss: { sales, q, proceeds (after the cut), each } or nil.
-- The trade list is read at most once a minute (or when P&L says its journal changed).
function ns.RecentSales(item)
    if not (item and ns.Tracking() and type(ProfitKing.Trades) == "function") then return nil end
    local now = KM.Now()
    if not ns.tradesAt or now - ns.tradesAt > 60 or now < ns.tradesAt then
        local ok, list = pcall(ProfitKing.Trades, now - 7 * DAY)
        ns.trades, ns.tradesAt = (ok and type(list) == "table") and list or {}, now
    end
    local out = { sales = 0, q = 0, proceeds = 0 }
    for _, s in ipairs(ns.trades) do
        if type(s) == "table" and s.item == item and (s.t or 0) >= now - 7 * DAY then
            out.sales, out.q, out.proceeds = out.sales + 1, out.q + (s.q or 0), out.proceeds + (s.proceeds or 0)
        end
    end
    out.each = out.q > 0 and out.proceeds / out.q or nil
    return out
end

---------------------------------------------------------------------------
-- The selection and its card
---------------------------------------------------------------------------

-- A selection built from the recipe data (All crafts clicks), not the game's window.
function ns.SelectionFromSpell(spell)
    local r = ns.MarketRecipe(spell)
    if not r then return nil end
    local a = ns.Active()
    local sel = { key = "p:" .. spell, source = "data", spell = spell, item = r.item, made = r.made or 1,
        reagents = r.reagents, have = {}, prof = r.prof }
    if a and a.profession then sel.profName, sel.skill, sel.maxSkill = a.profession() end
    return sel
end

-- What the panel shows now: a recipe picked in All crafts, else the window's selection.
function ns.Selection()
    if ns.pinned then return ns.pinned end
    local a = ns.Active()
    if a then return a:read() end
end

-- Your skill in a profession: the open window's, else what Market saw last for this character.
function ns.SkillFor(sel, profID)
    if sel and sel.skill and sel.skill > 0 then return sel.skill, sel.maxSkill end
    local m = KM.mods.Market
    if m and type(m.Skill) == "function" and profID then
        local ok, cur, max = pcall(m.Skill, profID)
        if ok and cur and cur > 0 then return cur, max end
    end
    return nil
end

-- How many to craft to sell without flooding the auction house: a quarter of what's listed now, and no more than one
-- day of units leaving it (gone per day counts sales, cancels and expiries, so it overstates sales). Nothing listed:
-- 1, to test the market. Returns listed, make, gone per day (nil when the item has never been scanned).
ns.BATCH_SHARE = 0.25
function ns.Batch(item)
    if not (item and ScannerKing and ScannerKing.GetPrice) then return nil end
    local _, _, listed = ScannerKing.GetPrice(item)
    if not listed then return nil end
    if listed <= 0 then return 0, 1, nil end
    local make = math.ceil(listed * ns.BATCH_SHARE)
    local st = EconKing and EconKing.GetStats and call(EconKing.GetStats, item)
    local gone = st and st.gonePerDay
    if gone then make = math.min(make, math.floor(gone)) end
    return listed, math.max(1, make), gone
end

-- Every number for one selection:
--   spell, item, name, q, icon, prof, made, crafts, skill, maxSkill, mode
--   mats = { { id, count, need, have, alts, unit, vendor, line } }, cost (one craft), costAll (crafts), missingPrice
--   market, lowest, listed, avg30, trend7, gone (units a day), make, history = { values }
--   buy, farm (Market rows), verdict = { buy, farm }, profit (one craft, Buy mats, after the cut), sale, de, deSale
--   head (profit for the mode), margin, paid (ns.PaidProfit), sales (ns.RecentSales)
function ns.Card(sel, opts)
    if not sel then return nil end
    opts = opts or {}
    local m = market()
    -- Classic's trade skill list names the item, not always the recipe spell: find it in the data
    if not sel.spell and sel.item then sel.spell = ns.SpellForItem(sel.prof or ns.ProfID(sel.profName), sel.item) end
    local mr = ns.MarketRecipe(sel.spell)
    local profID = sel.prof or ns.ProfID(sel.profName) or (mr and mr.prof)
    local reagents = (sel.reagents and #sel.reagents > 0) and sel.reagents or (mr and mr.reagents) or {}
    local c = { spell = sel.spell, item = sel.item or (mr and mr.item), prof = profID, made = sel.made or (mr and mr.made) or 1,
        crafts = math.max(1, ns.db and ns.db.crafts or 1), mats = {}, cost = 0, source = sel.source, key = sel.key,
        mode = ns.Mode() }
    if c.item then
        local info = ns.ItemInfo(c.item)
        c.name, c.q, c.icon = info.name or sel.name, info.q, info.icon or sel.icon
    else
        c.name, c.icon = sel.name or spellName(sel.spell), sel.icon
    end
    c.name = c.name or (sel.spell and ("Recipe " .. sel.spell)) or "?"
    c.skill, c.maxSkill = ns.SkillFor(sel, profID)

    -- reagents
    for i = 1, #reagents, 2 do
        local id, count = reagents[i], reagents[i + 1] or 1
        local unit, vendor = ns.UnitCost(id)
        local have, total = ns.Owned(id)
        if sel.have and sel.have[id] then have = sel.have[id]; total = math.max(total or 0, have) end
        local need = count * c.crafts
        local mat = { id = id, count = count, need = need, have = have, alts = math.max(0, (total or have) - have),
            unit = unit, vendor = vendor, line = unit and unit * need }
        table.insert(c.mats, mat)
        if unit then c.cost = c.cost + unit * count else c.missingPrice = c.missingPrice or id end
    end
    c.costAll = c.cost * c.crafts

    -- what it sells for
    if c.item then
        if ScannerKing and ScannerKing.GetPrice then
            local low, _, listed = ScannerKing.GetPrice(c.item)
            c.lowest, c.listed = low, listed
            local mp, _, _, real = ScannerKing.GetMarketPrice(c.item)
            c.market, c.marketReal = mp, real
        end
        local st = EconKing and EconKing.GetStats and call(EconKing.GetStats, c.item)
        if type(st) == "table" then
            c.avg30, c.trend7, c.gone = st.avg30, st.trend7, st.gonePerDay
            c.market = c.market or st.market
        end
        local _, make = ns.Batch(c.item)
        c.make = make
        if not opts.noHistory and EconKing and EconKing.GetHistory then
            local h = call(EconKing.GetHistory, c.item) or {}
            local vals = {}
            for i = math.max(1, #h - 29), #h do
                local v = h[i]
                local p = v and (v[2] or v[3])
                if p then vals[#vals + 1] = p end
            end
            c.history = vals
        end
        if m then
            local r = { spell = sel.spell or 0, item = c.item, prof = profID, skill = (mr and mr.skill) or 0, reagents = reagents, made = c.made }
            local mo = marketOpts()
            c.buy = m.Evaluate(r, "buy", mo)
            c.farm = m.Evaluate(r, "farm", mo)
            c.verdict = { buy = ns.Verdict(c.buy, "buy"), farm = ns.Verdict(c.farm, "farm") }
            c.profit = c.buy.craft
            c.sale = c.buy.craftSale
            c.de, c.deSale = c.buy.deEach, c.buy.deSale
            c.head = ns.Headline(c, c.mode)
            c.margin = ns.Margin(c.mode == "farm" and c.farm or c.buy)
        end
        if not opts.noPL then
            c.paid = ns.PaidProfit(c)
            c.sales = ns.RecentSales(c.item)
        end
    end
    return c
end

-- The headline number for the chosen mode: Buy mats = the better of selling or disenchanting minus the materials;
-- Use my mats = how much that beats selling the materials raw.
function ns.Headline(c, mode)
    if not c then return nil end
    mode = mode or ns.Mode()
    if mode == "farm" then return c.farm and c.farm.gain, "farm" end
    return c.buy and (c.buy.gain or c.buy.craft), "buy"
end

---------------------------------------------------------------------------
-- Shopping
---------------------------------------------------------------------------

-- What you're short of for the card's crafts: auction house items, and vendor items (bought from a vendor instead).
function ns.Missing(c)
    local ah, vendor = {}, {}
    for _, m in ipairs(c and c.mats or {}) do
        local short = m.need - (m.have or 0)
        if short > 0 then
            table.insert(m.vendor and vendor or ah, { id = m.id, n = short, unit = m.unit })
        end
    end
    return ah, vendor
end

function ns.ShoppingAvailable()
    return type(ShoppingKing) == "table" and type(ShoppingKing.Add) == "function"
end

-- Adds the missing auction house materials to the Shopping list "Crafting". Returns items added, vendor items skipped.
function ns.AddMissing(c)
    if not ns.ShoppingAvailable() then return 0, {} end
    local ah, vendor = ns.Missing(c)
    local added = 0
    for _, m in ipairs(ah) do
        local ok = pcall(ShoppingKing.Add, m.id, m.n, m.unit and math.ceil(m.unit) or nil, "Crafting")
        if ok then added = added + 1 end
    end
    return added, vendor
end

---------------------------------------------------------------------------
-- All crafts: every recipe you know in this profession, ranked by what you'd make now
---------------------------------------------------------------------------

ns.ALL_CAP = 200 -- rows at most (the table scrolls)

-- What the open window lists, for "Can make" and for which recipes you know. Modern windows are asked per recipe
-- (C_TradeSkillUI.GetRecipeInfo: learned, numAvailable); classic ones are walked once (GetTradeSkillInfo's and
-- GetCraftInfo's numAvailable), keyed by recipe spell and by item. A count the client doesn't give is true.
function ns.WindowCounts()
    local w = { bySpell = {}, byItem = {}, any = false }
    local a = ns.Active()
    local key = a and a.key
    if key == "modern" then
        w.modern = C_TradeSkillUI and type(C_TradeSkillUI.GetRecipeInfo) == "function" or false
        w.any = w.modern
    elseif key == "classic" or key == "craft" then
        local classic = key == "classic"
        local num = classic and _G.GetNumTradeSkills or _G.GetNumCrafts
        for i = 1, call(num) or 0 do
            local name, kind, n, _
            if classic then name, kind, n = call(_G.GetTradeSkillInfo, i)
            else name, _, kind, n = call(_G.GetCraftInfo, i) end
            if name and kind ~= "header" and kind ~= "subheader" then
                local link = call(classic and _G.GetTradeSkillItemLink or _G.GetCraftItemLink, i)
                local rlink = call(classic and _G.GetTradeSkillRecipeLink or _G.GetCraftRecipeLink, i)
                local spell = ns.IDFrom(rlink, "enchant") or ns.IDFrom(link, "enchant") or ns.IDFrom(link, "spell")
                local item = ns.IDFrom(link, "item")
                local v = type(n) == "number" and n or true
                if spell then w.bySpell[spell] = v end
                if item then w.byItem[item] = v end
                w.any = true
            end
        end
    end
    return w
end

-- The window's entry for a recipe: a count, true (listed, no count), or nil (not listed / not learned).
local function windowEntry(w, spell, item)
    if w.modern then
        local info = call(C_TradeSkillUI.GetRecipeInfo, spell)
        if type(info) ~= "table" or info.learned == false then return nil end
        return type(info.numAvailable) == "number" and info.numAvailable or true
    end
    local v = spell and w.bySpell[spell]
    if v == nil and item then v = w.byItem[item] end
    return v
end

-- How many crafts your reagents cover: the window's own count when it gives one, else your bags and bank.
local function canMake(entry, reagents, owned)
    if type(entry) == "number" then return math.max(0, entry) end
    if not reagents or #reagents == 0 then return nil end
    local n = math.huge
    for i = 1, #reagents, 2 do
        local id, count = reagents[i], math.max(1, reagents[i + 1] or 1)
        if owned[id] == nil then owned[id] = (ns.Owned(id)) end
        n = math.min(n, math.floor(owned[id] / count))
    end
    return n
end

-- What crafting it is worth now: CRAFT, the profit of each times how many to make (1 when there's no listing count);
-- DISENCHANT, one craft's profit; anything else, nothing.
local function profitNow(r)
    if not r.gain then return nil end
    if r.verdict == "craft" then return r.gain * (r.make or 1) end
    if r.verdict == "disenchant" then return r.gain end
    return nil
end

local VORDER = { craft = 5, disenchant = 4, sellraw = 3, skip = 2, noprice = 1 }
ns.VORDER = VORDER

local function byNow(a, b)
    if (a.now ~= nil) ~= (b.now ~= nil) then return a.now ~= nil end
    if a.now and a.now ~= b.now then return a.now > b.now end
    if (a.gain ~= nil) ~= (b.gain ~= nil) then return a.gain ~= nil end
    if a.gain and a.gain ~= b.gain then return a.gain > b.gain end
    return (a.spell or 0) < (b.spell or 0)
end

-- Rows for a profession in the current mode, Profit now first:
--   { spell, item, name, gain (profit each), margin, can, listed, make, gone, now (profit now), verdict, row }
-- Which recipes: the ones the open window lists when it can say; Market's "mine" (trainer recipes count) otherwise.
function ns.AllCrafts(profID)
    local m = market()
    if not (m and profID) then return {} end
    local mode = ns.Mode()
    local opts = marketOpts()
    opts.recipes = "mine"
    local ok, rows = pcall(m.Rank, profID, mode, opts)
    rows = ok and type(rows) == "table" and rows or {}
    local win = ns.WindowCounts()
    local entries, useWin = {}, false
    if win.any then
        for i, row in ipairs(rows) do
            entries[i] = windowEntry(win, row.recipe and row.recipe.spell, row.item)
            if entries[i] ~= nil then useWin = true end
        end
    end
    local out, owned = {}, {}
    for i, row in ipairs(rows) do
        if not useWin or entries[i] ~= nil then
            local spell = row.recipe and row.recipe.spell
            local r = { spell = spell, item = row.item, gain = row.gain, verdict = ns.Verdict(row, mode), row = row, mode = mode }
            r.name = ns.ItemInfo(row.item).name or spellName(spell) or ""
            r.margin = ns.Margin(row)
            r.listed, r.make, r.gone = ns.Batch(row.item)
            if r.verdict ~= "craft" then r.make = nil end
            r.can = canMake(entries[i], row.recipe and row.recipe.reagents, owned)
            r.now = profitNow(r)
            out[#out + 1] = r
        end
    end
    table.sort(out, byNow)
    while #out > ns.ALL_CAP do table.remove(out) end
    return out
end

-- The rows the table shows: the "Can make now" and search filters from the saved settings.
function ns.FilterCrafts(rows)
    local db = ns.db or {}
    local q = ((db.search or ""):lower()):match("^%s*(.-)%s*$")
    local out = {}
    for _, r in ipairs(rows or {}) do
        local keep = (not db.canMake or (r.can or 0) > 0) and (q == "" or (r.name or ""):lower():find(q, 1, true) ~= nil)
        if keep then out[#out + 1] = r end
    end
    return out
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------

function ns.TooltipLines(kind, id)
    local a = ns.Active()
    if not a then return nil end
    local profName = a.profession and select(1, a.profession())
    local profID = ns.ProfID(profName)
    local spell
    if kind == "spell" then
        if ns.MarketRecipe(id) then spell = id end
    else
        local cur = ns.Selection()
        if cur and cur.item == id and cur.spell then spell = cur.spell end
        spell = spell or ns.SpellForItem(profID, id)
    end
    if not spell then return nil end
    local sel = ns.SelectionFromSpell(spell)
    if not sel then return nil end
    local saved = ns.db.crafts
    ns.db.crafts = 1
    local ok, c = pcall(ns.Card, sel, { noHistory = true, noPL = true })
    ns.db.crafts = saved
    if not ok or not c then return nil end
    local gold = "|cff" .. KM.COLOR
    local head, mode = ns.Headline(c)
    local parts = { "cost " .. (c.missingPrice and "?" or KM.Money(c.cost)) }
    if head then parts[#parts + 1] = (mode == "farm" and "vs raw " or "profit ") .. KM.Money(head) end
    local v = c.verdict and c.verdict[mode]
    if v and ns.VERDICTS[v] then parts[#parts + 1] = ns.VERDICTS[v][1]:lower() end
    return { gold .. "King Maker|r " .. table.concat(parts, ", ") }
end
