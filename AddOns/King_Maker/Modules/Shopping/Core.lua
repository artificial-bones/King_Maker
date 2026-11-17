local _, KM = ...
local ns = KM.Module("Shopping", { title = "Shopping", short = "Shopping", db = "ShoppingKingDB" })

-- Shopping: lists of items you want to buy, and a panel beside the auction house to search for them and buy them,
-- one click per purchase step. The built-in "Favorites" list is Econ's favorites (the same stars as Price History);
-- every other list is the player's own.
--
-- Files: Core.lua (saved data, helpers, slash, crown, settings), Lists.lua (lists and the public API),
-- Buy.lua (searching and the purchase flows), Panel.lua (the panel at the auction house), Page.lua (the page).
--
-- Its public face is the global ShoppingKing table (Lists.lua):
--   ShoppingKing.Add(itemID, qty, maxPrice, listName) -> bool      listName nil = the "Shopping" list
--   ShoppingKing.Remove(itemID, listName)
--   ShoppingKing.Lists() -> { names }
--   ShoppingKing.Items(listName) -> { { itemID, qty, max, note } }
--   ShoppingKing.IsWanted(itemID) -> listName | nil
--   ShoppingKing.RegisterListProvider(name, { items = fn, bought = fn, owner = s, note = s }) -> bool   a live list
--   ShoppingKing.UnregisterListProvider(name), ShoppingKing.RefreshLists()        another addon supplies, never saved

ShoppingKing = { API_VERSION = 1 }
local API = ShoppingKing
ns.API = API

ns.FAV = "Favorites"
ns.DEFAULT = "Shopping"
ns.ORACLE = "Oracle"   -- a saved list name kept from the old Oracle import (before 2.6.0); a provider may not take it

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- ShoppingKingDB = {
--   version = 1,
--   lists = { [name] = { items = { { id = itemID, qty = n|nil, max = copper|nil, note = s|nil,
--                                     keep = n|nil,                        -- "Keep n in stock" (2.6.2): qty unused
--                                     transit = { n, own, t }|nil },       -- bought in Keep mode, not counted yet
--                                   ... }, created = t } },
--   order = { name, ... },               -- the player's lists in the order they were made (Favorites is not stored)
--   favMeta = { [itemID] = { qty, max, note, keep, transit } },   -- extra fields for Econ's favorites
--   fav = { [itemID] = true },           -- only used when Econ is not loaded
--   active = name,                       -- the list the page and the panel show
--   settings = { autoPanel = true, defaultMax = "market" | "none", sound = true,
--                autoNext = true,                 -- after a purchase, go to the next deal (selects and searches only)
--                bigSpend = true,                 -- a purchase of 25%+ of your gold needs a second Confirm click
--                dealLine = true },               -- after a scan, one chat line when the deals changed (2.6.0)
--   panel = { shown = true },
--   ui = { sort = { key = "status", desc = false } },   -- the page table's sort
-- }
-- Runs when King Maker's saved variables load, and again if Boot ever re-runs it: safe twice.
function ns.InitDB()
    ShoppingKingDB = ShoppingKingDB or {}
    local db = ShoppingKingDB
    db.version = 1
    db.lists = db.lists or {}
    db.order = db.order or {}
    db.favMeta = db.favMeta or {}
    db.fav = db.fav or {}
    db.settings = db.settings or {}
    local s = db.settings
    if s.autoPanel == nil then s.autoPanel = true end
    if s.sound == nil then s.sound = true end
    if s.defaultMax ~= "market" and s.defaultMax ~= "none" then s.defaultMax = "market" end
    if s.autoNext == nil then s.autoNext = true end
    if s.bigSpend == nil then s.bigSpend = true end
    if s.dealLine == nil then s.dealLine = true end
    db.panel = db.panel or {}
    if type(db.ui) ~= "table" then db.ui = {} end
    if type(db.ui.sort) ~= "table" or type(db.ui.sort.key) ~= "string" then db.ui.sort = { key = "status", desc = false } end
    if db.panel.shown == nil then db.panel.shown = true end
    -- order and lists agree: drop names without a list, add lists missing from the order
    local seen, order = {}, {}
    for _, name in ipairs(db.order) do
        if db.lists[name] and not seen[name] and name ~= ns.FAV then seen[name] = true; order[#order + 1] = name end
    end
    local extra = {}
    for name, l in pairs(db.lists) do
        if type(l) ~= "table" or name == ns.FAV then db.lists[name] = nil
        else
            l.items = l.items or {}
            if not seen[name] then extra[#extra + 1] = name end
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do order[#order + 1] = name end
    db.order = order
    if not db.active or (db.active ~= ns.FAV and not db.lists[db.active]) then db.active = ns.FAV end
    ns.db = db
end

---------------------------------------------------------------------------
-- Items: names, icons, links (names load lazily; never block on them)
---------------------------------------------------------------------------

local function getInfo(x)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local ok, name, link, quality, _, _, _, _, stack = pcall(get, x)
    if ok then return name, link, quality, stack end
end

function ns.Name(id)
    local name = getInfo(id)
    if name then return name end
    local sk = ScannerKingDB and ScannerKingDB.items and ScannerKingDB.items[id]
    if type(sk) == "table" and sk.name then return sk.name end
    local ek = EconKingDB and EconKingDB.info and EconKingDB.info[id]
    if type(ek) == "table" and ek.name then return ek.name end
    if type(ek) == "string" then local n = ek:match("^%d*:(.+)$"); if n then return n end end -- Econ's "quality:name"
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "Item " .. tostring(id)
end

function ns.ColoredName(id)
    local _, _, q = getInfo(id)
    local hex = KM.UI.QUALITY[q or 1] or "ffffff"
    return "|cff" .. hex .. ns.Name(id) .. "|r"
end

function ns.Icon(id)
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if inst then
        local ok, _, _, _, _, icon = pcall(inst, id)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.Link(id)
    local _, link = getInfo(id)
    return link
end

-- Stack size > 1 is a good first guess for "commodity" until a search says which it is.
function ns.Stackable(id)
    local _, _, _, stack = getInfo(id)
    return (tonumber(stack) or 1) > 1
end

-- Text -> itemID: an item link, a number, or a name (from the game cache, then the price and history lists).
function ns.ItemFrom(text)
    if type(text) == "number" then return text end
    text = strtrim and strtrim(text or "") or (text or "")
    if text == "" then return nil end
    local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^(%d+)$"))
    if id then return id end
    local low = text:lower()
    local _, link = getInfo(text)
    if link then return tonumber(link:match("item:(%d+)")) end
    local partial
    local function look(t, field)
        for i, v in pairs(t or {}) do
            local n = type(v) == "table" and v[field] or (type(v) == "string" and v:match("^%d*:(.+)$")) -- Econ: "quality:name"
            if type(n) == "string" then
                local nl = n:lower()
                if nl == low then return i end
                if not partial and nl:find(low, 1, true) then partial = i end
            end
        end
    end
    local hit = look(ScannerKingDB and ScannerKingDB.items, "name") or look(EconKingDB and EconKingDB.info, "name")
    return hit or partial
end

---------------------------------------------------------------------------
-- Money: "12g 50s", "1g2s3c", "75s", "3.5" (a bare number is gold) -> copper
---------------------------------------------------------------------------

function ns.ParseMoney(text)
    if type(text) == "number" then return math.floor(text) end
    text = (text or ""):lower():gsub("%s+", "")
    if text == "" then return nil end
    local bare = tonumber(text)
    if bare then return math.floor(bare * 10000 + 0.5) end
    local total, any = 0, false
    for n, unit in text:gmatch("([%d%.]+)([gsc])") do
        local v = tonumber(n)
        if not v then return nil end
        any = true
        total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    if not any then return nil end
    local rest = text:gsub("[%d%.]+[gsc]", "")
    if rest ~= "" then return nil end
    return math.floor(total + 0.5)
end

function ns.Money(c) return KM.Money(c) end

-- Compact money for tables and the panel (tooltips, the detail facts and Confirm text use the exact KM.Money):
--   nil -> grey dash; >= 1000g -> "1,234g"; >= 1g -> "3g 45s" (rounded to the silver, "0s" left out);
--   >= 1s -> "45s 9c"; less -> "9c"; negative -> a leading minus. plain = no coin colours.
-- Promoted to Core in 2.7 (KM.MoneyShort) so Profit & Loss formats money the same way.
function ns.Short(c, plain) return KM.MoneyShort(c, plain) end

-- A fraction as a signed percent: 0.13 -> "+13%", -0.334 -> "-33%", 0 -> "0%".
-- "You hold 7 at 3g 02s each; 2g 85s now after the cut (-17s each)" from Profit & Loss (nil when there's nothing held).
function ns.BasisText(b)
    if not (b and (b.held or 0) > 0 and b.avg) then return nil end
    local s = "You hold " .. KM.Commas(b.held) .. " at " .. KM.Money(b.avg) .. " each"
    if b.each then
        local d = b.each - b.avg
        s = s .. "; " .. KM.Money(b.each) .. " now after the cut (" .. (d >= 0 and "+" or "-") .. KM.Money(math.abs(d), true) .. " each)"
    end
    return s
end

function ns.Pct(p)
    if p == nil then return nil end
    local n = math.floor(math.abs(p) * 100 + 0.5)
    if n == 0 then return "0%" end
    return (p < 0 and "-" or "+") .. n .. "%"
end

-- A price change, coloured for a buyer: down is good (green), up is muted. nil -> grey dash.
function ns.Trend(x)
    local t = ns.Pct(x)
    if not t then return "|cff808080-|r" end
    local C = KM.UI.C
    return KM.UI.Hex((x < 0 and t ~= "0%") and C.good or C.muted) .. t .. "|r"
end

---------------------------------------------------------------------------
-- Prices: Scanner's numbers, plus what the panel saw on the auction house just now
---------------------------------------------------------------------------

-- itemID -> { p = lowest copper each, q = quantity listed, t = time, kind = "commodity" | "item",
--             ladder = { { unit, qty }, ... } every listing read (cheapest first), rows = what the panel draws }
-- Session only, never saved.
ns.live = {}

function ns.Prices(id)
    local market, lowest, listed, t
    local sk = ScannerKing
    if sk and sk.GetMarketPrice then
        local m, mt, mq, real = KM.Safe(sk.GetMarketPrice, id)
        if real then market = m end
        t = mt
        listed = mq
    end
    if sk and sk.GetPrice then
        local p, pt, pq = KM.Safe(sk.GetPrice, id)
        lowest = p
        t = pt or t
        listed = pq or listed
        if not market then market = p end
    end
    local live = ns.live[id]
    if live and live.p and (not t or live.t >= t) then
        lowest, listed, t = live.p, live.q or listed, live.t
    end
    return market, lowest, listed, t
end

local function maxFrom(e, market)
    if e and e.max then return e.max, false end
    if e and market and ns.db and ns.db.settings.defaultMax == "market" then return market, true end
    return nil, false
end

-- The max price that applies to an entry: its own, or the market price when the setting says so.
function ns.EffectiveMax(e)
    if e and e.max then return e.max, false end
    if not e then return nil, false end
    return maxFrom(e, (ns.Prices(e.id)))
end

-- Price History's numbers for an item (nil without Econ). Econ caches them per scan.
function ns.Stats(id)
    if not (EconKing and EconKing.GetStats) then return nil end
    local s = KM.Safe(EconKing.GetStats, id)
    return type(s) == "table" and s or nil
end

-- Owned on every character (Inventory): total, { ["Name-Realm"] = n }.
function ns.Own(id)
    if not (InventoryKing and InventoryKing.GetCount) then return nil end
    local n, by = KM.Safe(InventoryKing.GetCount, id)
    return tonumber(n), type(by) == "table" and by or nil
end

---------------------------------------------------------------------------
-- Keep N in stock (2.6.2): an entry with keep = N needs N minus what you own, and never counts down; owning more
-- lowers the need, using them raises it again. What you own is counted where it can reach this character: your
-- characters on this realm and faction, and the warband bank (Inventory; another realm's stock can't be mailed here).
-- Bought items go to the mailbox, where Inventory only sees them once it's opened, so a purchase is held as
-- `transit` and taken off the need until the count catches up (or the mailbox is read, or two days pass).
---------------------------------------------------------------------------

local TRANSIT_MAX = 2 * 86400

-- Each character's faction, as Inventory noted it ("Name-Realm" -> "Alliance" | "Horde"). Read from the module
-- itself: InventoryKing.GetCharacters works out every character's worth, far too much for each table row.
local function factions()
    local inv = KM.mods.Inventory
    local chars = inv and inv.db and inv.db.chars
    return type(chars) == "table" and chars or {}
end

-- Owned here (this realm and faction, and the warband bank): total, { ["Name-Realm"] = n }; nil without Inventory.
function ns.OwnHere(id)
    local total, by = ns.Own(id)
    if not by then return total, nil end
    local realm = GetRealmName and GetRealmName() or ""
    local mine = UnitFactionGroup and UnitFactionGroup("player") or nil
    local fac = factions()
    local n, here = 0, {}
    for who, c in pairs(by) do
        c = tonumber(c) or 0
        local sameRealm = realm == "" or who == "Warband" or who:sub(-(#realm + 1)) == "-" .. realm or not who:find("-", 1, true)
        local f = type(fac[who]) == "table" and fac[who].faction or nil
        local sameFaction = who == "Warband" or not mine or not f or f == mine
        if sameRealm and sameFaction and c > 0 then n, here[who] = n + c, c end
    end
    return n, here
end

-- Units bought in Keep mode that the count doesn't show yet.
local function transitLeft(e, owned)
    local tr = e.transit
    if type(tr) ~= "table" or not tonumber(tr.n) then return 0 end
    if KM.Now() - (tr.t or 0) > TRANSIT_MAX then return 0 end
    if InventoryKing and InventoryKing.GetPlaces then
        local places = KM.Safe(InventoryKing.GetPlaces, e.id)
        local me = type(places) == "table" and places[KM.Char()]
        if type(me) == "table" and (me.mailT or 0) > (tr.t or 0) then return 0 end   -- the mailbox was read since
    end
    return math.max(0, tr.n - math.max(0, (owned or 0) - (tr.own or 0)))
end
ns.TransitLeft = transitLeft

-- For a Keep entry: how many to buy now, what you own here, and what's still on its way. nil for a Buy entry.
function ns.KeepNeed(e)
    local keep = e and tonumber(e.keep)
    if not keep or e.virtual then return nil end
    local owned = ns.OwnHere(e.id) or 0
    local coming = transitLeft(e, owned)
    return math.max(0, keep - owned - coming), owned, coming
end

-- Does this entry still want any? (Buy: qty not yet 0; Keep: below its stock.)
function ns.StillWanted(e)
    if not e then return false end
    local need = ns.KeepNeed(e)
    if need then return need > 0 end
    return not (e.qty and e.qty <= 0)
end

ns.RANK = { under = 1, nomax = 2, over = 3, noprice = 4, done = 5 }

-- Everything a table row, a panel row, a tooltip, the totals and the badge need about one entry, worked out once:
--   e, id, name, market, lowest, listed, t, live (the lowest came from a search this visit), max, fromMarket,
--   qty (still to buy), need (qty, or 1), status "under" | "nomax" | "over" | "noprice" | "done",
--   keep, owned, coming (Keep N in stock: qty = N - owned here - still on its way; done when stocked),
--   diff = lowest - max, pct = diff / max, cost = need x lowest, costMax = need x max, save (deals only),
--   underQty (listed at or under max, from this visit's search), virtual
--   and unless light: avg7, avg30, trend7, low30, high30, lowestOnly (Econ), own, ownBy (Inventory),
--   basis = { held, avg, each, ... } what the units you hold cost you (Profit & Loss's ProfitKing.Basis, 2.7).
function ns.Row(e, light)
    local id = e.id
    local market, lowest, listed, t = ns.Prices(id)
    local max, fromMarket = maxFrom(e, market)
    local lv = ns.live[id]
    local r = { e = e, id = id, name = ns.Name(id), market = market, lowest = lowest, listed = listed, t = t,
        live = (lv and lv.p and lv.p == lowest and lv.t == t) and true or false,
        max = max, fromMarket = fromMarket, qty = e.qty, virtual = e.virtual }
    local keepNeed, owned, coming = ns.KeepNeed(e)
    if keepNeed then r.keep, r.owned, r.coming, r.qty = tonumber(e.keep), owned, coming, keepNeed end
    r.need = (r.qty and r.qty > 0) and r.qty or 1
    if r.qty and r.qty <= 0 then r.status = "done"
    elseif not lowest then r.status = "noprice"
    elseif not max then r.status = "nomax"
    elseif lowest <= max then r.status = "under"
    else r.status = "over" end
    if lowest and max then
        r.diff = lowest - max
        if max > 0 then r.pct = r.diff / max end
    end
    r.cost = lowest and r.need * lowest or nil
    r.costMax = max and r.need * max or nil
    if r.status == "under" then r.save = r.need * (max - lowest) end
    if ns.UnderQty then r.underQty = ns.UnderQty(id, max) end
    if not light then
        local s = ns.Stats(id)
        if s then
            r.avg7, r.avg30, r.trend7, r.low30, r.high30, r.lowestOnly = s.avg7, s.avg30, s.trend7, s.low30, s.high30, s.lowestOnly
        end
        r.own, r.ownBy = ns.Own(id)
        if ProfitKing and ProfitKing.Basis then r.basis = KM.Safe(ProfitKing.Basis, id) end
    end
    return r
end

-- Ascending sort key: deals first (biggest saving first), then no max, then over max (closest first), no price, done.
function ns.SortKey(r)
    local p = r.pct and math.max(-0.999, math.min(9.99, r.pct)) or 9.99
    return (ns.RANK[r.status] or 9) * 1000 + (p + 1) * 10   -- the percent part stays under 110: rank dominates
end

-- Sorts rows by SortKey, then name, then ID (a stable order for the panel, Next deal and /shop deals).
function ns.SortRows(rows)
    local key = {}
    for _, r in ipairs(rows) do key[r] = ns.SortKey(r) end
    table.sort(rows, function(a, b)
        if key[a] ~= key[b] then return key[a] < key[b] end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

-- "under", "over", "noprice", "done", "nomax"
function ns.Status(e) return ns.Row(e, true).status end

-- The status word a row shows, and its colour: DEAL, <= MKT (a deal against the market price, no max of your own),
-- DONE, NO MAX, NO SCAN; over max shows nothing (the dimmed row says it).
function ns.StatusLabel(r)
    local C = KM.UI.C
    if r.status == "under" then
        if r.fromMarket then return "<= MKT", C.info end
        return "DEAL", C.good
    end
    if r.status == "done" then return r.keep and "STOCKED" or "DONE", C.info end
    if r.status == "nomax" then return "NO MAX", C.muted end
    if r.status == "noprice" then return "NO SCAN", C.dim end
    return "", C.dim
end

function ns.StatusText(e)
    local text, c = ns.StatusLabel(ns.Row(e, true))
    if text == "" then return "" end
    return KM.UI.Hex(c) .. text .. "|r"
end

-- Something outside Shopping changed (a scan, bags): redraw once, half a second later, however often it fires.
local soon = false
function ns.ChangedSoon()
    if soon then return end
    soon = true
    C_Timer.After(0.5, function()
        soon = false
        if ns.db and ns.Changed then ns.Changed() end
    end)
end

---------------------------------------------------------------------------
-- The crown, Home, Settings, the scanner
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "shopping", label = "Shopping", order = 16, func = function() KM.Show("shopping") end })

KM.RegisterTooltip(function(tt)
    if not ns.db or not ns.UnderMaxCount then return end
    local n = ns.UnderMaxCount()
    if n > 0 then tt:AddLine("Shopping: " .. n .. " item" .. (n == 1 and "" or "s") .. " under your max", 1, 1, 1) end
end)

-- Home: a row when items on your lists are at or under your max, with what buying them all costs.
KM.RegisterHomeCard({ kind = "attention", id = "shopping", order = 20, get = function()
    if not ns.db or not ns.AllSummary then return nil end
    local a = ns.AllSummary()
    if a.deals == 0 then return nil end
    return { { text = a.deals .. " shopping deal" .. (a.deals == 1 and "" or "s") .. " under your max", color = KM.UI.C.good,
        value = KM.MoneyShort(a.dealsCost, true), page = "shopping", tip = function(tt)
            tt:AddLine("Items on your shopping lists whose lowest buyout is at or under your max price"
                .. (ns.db.settings.defaultMax == "market" and " (an item's own max, or its market price when it has none)." or " (an item with no max of its own isn't counted).")
                .. " An item on two lists counts once.", 1, 1, 1, true)
            tt:AddDoubleLine("Cost to buy them", KM.Money(a.dealsCost), 0.8, 0.8, 0.8, 1, 1, 1)
            tt:AddDoubleLine("Under your max by", KM.Money(a.dealsSave), 0.8, 0.8, 0.8, 1, 1, 1)
            tt:AddLine("Click for Shopping.", 0.6, 0.6, 0.6)
        end } }
end })

if ScannerKing and ScannerKing.Watch then
    -- the merged scan prices every item on every list, even ones outside Trade Goods
    ScannerKing.Watch("Shopping_King", function() return ns.AllWanted and ns.AllWanted() or {} end)
end
---------------------------------------------------------------------------
-- The deal line: one chat line after a scan, when the deals on your lists changed
---------------------------------------------------------------------------
--   Scan done: 3 Shopping items under your max (Fel Leather 8s 82c, Linen Cloth 1s 5c, Copper Ore 5s 20c)
-- Only when the number of deals changed or an item became a deal since the last check (this session), so a scan that
-- finds the same deals says nothing. Never in combat: that scan is skipped and the next one compares as if it hadn't
-- happened. Settings > Shopping, /shop notify.

local lastDeals          -- { [itemID] = true } at the last check; nil before the first scan this session
local DEAL_NAMES = 3

-- The line to print now, or nil (and remembers the deals it saw). Called a moment after SCAN_FINISHED.
function ns.DealLine()
    if not (ns.db and ns.db.settings.dealLine) then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local s = ns.AllSummary()
    local now, changed = {}, false
    for _, r in ipairs(s.dealRows) do now[r.id] = true end
    if lastDeals then
        local before = 0
        for _ in pairs(lastDeals) do before = before + 1 end
        if before ~= s.deals then changed = true end
        for id in pairs(now) do if not lastDeals[id] then changed = true end end
    else
        changed = true
    end
    lastDeals = now
    if not changed or s.deals == 0 then return nil end
    local rows = ns.SortRows(s.dealRows)
    local parts = {}
    for i = 1, math.min(DEAL_NAMES, #rows) do
        local r = rows[i]
        parts[i] = (ns.Link(r.id) or ns.Name(r.id)) .. " " .. ns.Short(r.lowest)
    end
    if #rows > DEAL_NAMES then parts[#parts + 1] = "+" .. (#rows - DEAL_NAMES) .. " more" end
    return "Scan done: " .. s.deals .. " Shopping item" .. (s.deals == 1 and "" or "s") .. " under your max ("
        .. table.concat(parts, ", ") .. ")"
end

local dealSoon = false
local function dealLineSoon()
    if dealSoon then return end
    dealSoon = true
    C_Timer.After(0.6, function()      -- after the scan's own "Scan done" line and the price refresh
        dealSoon = false
        local line = ns.DealLine()
        if line then KM.Print(ns, line) end
    end)
end

-- A scan finished or prices changed: the page's prices, "Last scan", the badge and the panel follow.
if ScannerKing and ScannerKing.RegisterCallback then
    ScannerKing.RegisterCallback("Shopping_King", function(event, found)
        if event == "PRICES_UPDATED" or event == "SCAN_FINISHED" then ns.ChangedSoon() end
        if event == "SCAN_FINISHED" and found ~= 0 then dealLineSoon() end
    end)
end
-- Bags, bank or mail recounted: the Own column follows (only redrawn while something shows it). A Keep entry's need
-- moves with what you own, so with one on a list the badge and the panel follow too.
if InventoryKing and InventoryKing.RegisterCallback then
    InventoryKing.RegisterCallback("STOCK", function()
        if (KM.IsShown and KM.IsShown("shopping")) or (ns.HasKeep and ns.HasKeep()) then ns.ChangedSoon() end
    end, "Shopping_King")
end

KM.RegisterSettings({ id = "shopping", label = "Shopping", order = 15, rows = {
    { type = "header", label = "Auction house" },
    { type = "check", label = "Show the Shopping panel when the auction house opens",
      tip = "The panel docks to the right of the auction house. Its Shopping button shows or hides it either way.",
      get = function() return ns.db.settings.autoPanel end, set = function(v) ns.db.settings.autoPanel = v end },
    { type = "choice", label = "Items without a max price", options = { { "market", "Max = market" }, { "none", "No limit" } },
      tip = "Max = market: an item with no max of its own counts as a deal at or under its market price (shown as <= MKT). No limit: it never counts as a deal and shows NO MAX.",
      get = function() return ns.db.settings.defaultMax end, set = function(v) ns.db.settings.defaultMax = v end },
    { type = "check", label = "After a purchase, go to the next deal",
      tip = "Only selects the next item under your max and searches it; buying it is still your click.",
      get = function() return ns.db.settings.autoNext end, set = function(v) ns.db.settings.autoNext = v end },
    { type = "check", label = "Ask twice before spending a quarter of your gold",
      tip = "A purchase of 25% or more of the gold you carry needs a second click on Confirm (within 4 seconds).",
      get = function() return ns.db.settings.bigSpend end, set = function(v) ns.db.settings.bigSpend = v end },
    { type = "check", label = "Play a sound when a purchase goes through",
      get = function() return ns.db.settings.sound end, set = function(v) ns.db.settings.sound = v end },
    { type = "check", label = "Say in chat when a scan finds deals",
      tip = "After a price scan, one line naming up to three items now under your max. Only when the deals changed since the last line. /shop notify.",
      get = function() return ns.db.settings.dealLine end, set = function(v) ns.db.settings.dealLine = v end },
    { type = "text", label = "Buying is always one click per step: Buy asks the auction house for the price, Confirm buys. "
        .. "Nothing is bought above an item's max price unless you tick \"Allow one buy above my max\" for that purchase. "
        .. "Search all, then Buy, Confirm, Next deal, Buy, Confirm... works through a list's deals one click at a time." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/shop   open the Shopping page\n/shop add [item] [qty] [max]   add to the Shopping list\n"
        .. "/shop remove [item]   remove from the Shopping list\n/shop keep [item] [n|off]   keep n in stock (Shopping list)\n"
        .. "/shop list [name]   your lists, or one list's items\n"
        .. "/shop deals   what's under your max right now, best first\n/shop panel   show or hide the auction house panel\n"
        .. "/shop notify [on|off]   a chat line when a scan finds deals" },
} })

---------------------------------------------------------------------------
-- /shop
---------------------------------------------------------------------------

-- "[link] 20 1g50s" or "Linen Cloth 20 1g50s": the item, then optional qty and max.
function ns.ParseAdd(rest)
    rest = strtrim and strtrim(rest or "") or (rest or "")
    local link, after = rest:match("^(|c%x+|H.-|h.-|h|r)%s*(.-)$")
    local itemText
    if link then itemText = link else after = rest end
    local words = {}
    for w in (after or ""):gmatch("%S+") do words[#words + 1] = w end
    local qty, max
    -- trailing numbers: qty then max; with only one, a money-looking word is the max
    while #words > 0 do
        local w = words[#words]
        if not max and w:find("[gsc]$") and ns.ParseMoney(w) then max = ns.ParseMoney(w); table.remove(words)
        elseif not qty and w:match("^%d+$") and (#words > 1 or link) then qty = tonumber(w); table.remove(words)
        else break end
    end
    if not itemText then itemText = table.concat(words, " ") end
    return ns.ItemFrom(itemText), qty, max
end

-- /shop deals: every item under its max on any list (each item once), best first, at most 10 lines and a total.
function ns.PrintDeals()
    local s = ns.AllSummary()
    if s.deals == 0 then
        local last = ScannerKing and ScannerKing.LastScan and KM.Safe(ScannerKing.LastScan)
        return KM.Print(ns, "No deals right now (last scan " .. (last and KM.Ago(last) or "never") .. ").")
    end
    local rows = ns.SortRows(s.dealRows)
    for i, r in ipairs(rows) do
        if i > 10 then KM.Print(ns, "  ...and " .. (#rows - 10) .. " more on the Shopping page.") break end
        KM.Print(ns, "  " .. ns.Name(r.id) .. "  " .. ns.Short(r.lowest) .. " (max " .. ns.Short(r.max)
            .. (r.fromMarket and " market" or "") .. ", " .. (ns.Pct(r.pct) or "0%") .. ")  want " .. r.need
            .. " ~ " .. ns.Short(r.cost) .. "  [" .. r.list .. "]")
    end
    KM.Print(ns, s.deals .. " deal" .. (s.deals == 1 and "" or "s") .. ", about " .. KM.Money(s.dealsCost)
        .. " in all (saves " .. KM.Money(s.dealsSave) .. " against your max).")
end

SLASH_SHOPPINGKING1 = "/shop"
SLASH_SHOPPINGKING2 = "/shopping"
SlashCmdList.SHOPPINGKING = function(msg)
    if not ns.db then return end
    msg = strtrim and strtrim(msg or "") or (msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        KM.Show("shopping")
    elseif cmd == "add" then
        local id, qty, max = ns.ParseAdd(rest)
        if not id then return KM.Print(ns, "/shop add [item link, ID or name] [qty] [max, like 1g50s]") end
        API.Add(id, qty, max)
        KM.Print(ns, ns.Name(id) .. " is on your Shopping list" .. (qty and (", want " .. qty) or "")
            .. (max and (", max " .. KM.Money(max)) or "") .. ".")
    elseif cmd == "remove" or cmd == "rm" then
        local id = ns.ItemFrom(rest)
        if not id then return KM.Print(ns, "/shop remove [item link, ID or name]") end
        API.Remove(id)
        KM.Print(ns, ns.Name(id) .. " removed from your Shopping list.")
    elseif cmd == "list" or cmd == "lists" then
        if rest ~= "" then
            local name = ns.FindList(rest)
            if not name then return KM.Print(ns, "no list called '" .. rest .. "'.") end
            local items = API.Items(name)
            KM.Print(ns, name .. ": " .. #items .. " items.")
            for _, e in ipairs(items) do
                KM.Print(ns, "  " .. ns.Name(e.itemID) .. (e.keep and ("  keep " .. e.keep) or (e.qty and ("  want " .. e.qty) or ""))
                    .. (e.max and ("  max " .. KM.Money(e.max)) or ""))
            end
        else
            for _, name in ipairs(API.Lists()) do KM.Print(ns, name .. ": " .. #API.Items(name) .. " items.") end
        end
    elseif cmd == "keep" then
        -- "[item] 20" keeps 20 in stock; "[item] off" (or 0) goes back to buying a fixed number
        local body = strtrim and strtrim(rest or "") or (rest or "")
        local itemText, n = body:match("^(.-)%s+(%S+)$")
        local count = n and (n:lower() == "off" and 0 or tonumber(n:match("^%d+$") or ""))
        local id = count and ns.ItemFrom(itemText)
        if not id then return KM.Print(ns, "/shop keep [item link, ID or name] [how many | off]") end
        local name = ns.FindList(ns.DEFAULT) or ns.DEFAULT
        if not ns.Find(name, id) then
            if count == 0 then return KM.Print(ns, ns.Name(id) .. " isn't on your Shopping list.") end
            ns.AddTo(name, id)
            name = ns.FindList(ns.DEFAULT) or name
        end
        ns.SetKeep(name, id, count > 0 and count or false)
        if count > 0 then
            local need, owned = ns.KeepNeed(ns.Find(name, id))
            KM.Print(ns, "keeping " .. count .. " " .. ns.Name(id) .. " in stock: you have " .. (owned or 0)
                .. (InventoryKing and " here" or "") .. ", " .. (need or count) .. " to buy.")
        else
            KM.Print(ns, ns.Name(id) .. " is back to buying a set number.")
        end
    elseif cmd == "panel" then
        if ns.TogglePanel then ns.TogglePanel() end
    elseif cmd == "deals" or cmd == "deal" then
        ns.PrintDeals()
    elseif cmd == "notify" or cmd == "alert" or cmd == "alerts" then
        local st, arg = ns.db.settings, rest:lower()
        st.dealLine = arg == "on" or (arg ~= "off" and not st.dealLine)
        KM.Print(ns, "a chat line when a scan finds deals: " .. (st.dealLine and "on." or "off."))
        KM.Refresh("settings")
    else
        KM.Print(ns, "/shop   open the Shopping page (or /km shopping)")
        KM.Print(ns, "/shop add [item] [qty] [max]   add to the Shopping list (max like 1g50s)")
        KM.Print(ns, "/shop remove [item]   remove from the Shopping list")
        KM.Print(ns, "/shop keep [item] [n|off]   keep n in stock: the need is n minus what you own, and refills as you use them")
        KM.Print(ns, "/shop list [name]   your lists, or one list's items")
        KM.Print(ns, "/shop deals   what's under your max right now, best first")
        KM.Print(ns, "/shop panel   show or hide the panel at the auction house")
        KM.Print(ns, "/shop notify [on|off]   a chat line when a scan finds deals")
    end
end
