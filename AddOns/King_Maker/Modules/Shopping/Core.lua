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

ShoppingKing = { API_VERSION = 1 }
local API = ShoppingKing
ns.API = API

ns.FAV = "Favorites"
ns.DEFAULT = "Shopping"
ns.ORACLE = "Oracle"

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- ShoppingKingDB = {
--   version = 1,
--   lists = { [name] = { items = { { id = itemID, qty = n|nil, max = copper|nil, note = s|nil }, ... }, created = t } },
--   order = { name, ... },               -- the player's lists in the order they were made (Favorites is not stored)
--   favMeta = { [itemID] = { qty, max, note } },   -- extra fields for Econ's favorites
--   fav = { [itemID] = true },           -- only used when Econ is not loaded
--   active = name,                       -- the list the page and the panel show
--   settings = { autoPanel = true, defaultMax = "market" | "none", sound = true },
--   panel = { shown = true },
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
    db.panel = db.panel or {}
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
            local n = type(v) == "table" and v[field]
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

---------------------------------------------------------------------------
-- Prices: Scanner's numbers, plus what the panel saw on the auction house just now
---------------------------------------------------------------------------

ns.live = {}   -- itemID -> { p = lowest copper each, q = quantity listed, t = time, kind = "commodity" | "item" }

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

-- The max price that applies to an entry: its own, or the market price when the setting says so.
function ns.EffectiveMax(e)
    if e and e.max then return e.max, false end
    if ns.db and ns.db.settings.defaultMax == "market" and e then
        local market = ns.Prices(e.id)
        if market then return market, true end
    end
    return nil, false
end

-- "under", "over", "noprice", "done", "nomax"
function ns.Status(e)
    if e.qty and e.qty <= 0 then return "done" end
    local _, lowest = ns.Prices(e.id)
    local max = ns.EffectiveMax(e)
    if not lowest then return "noprice" end
    if not max then return "nomax" end
    if lowest <= max then return "under" end
    return "over"
end

function ns.StatusText(e)
    local C = KM.UI.C
    local s = ns.Status(e)
    if s == "under" then return KM.UI.Hex(C.good) .. "under max!|r" end
    if s == "over" then return KM.UI.Hex(C.muted) .. "above max|r" end
    if s == "done" then return KM.UI.Hex(C.info) .. "done|r" end
    if s == "nomax" then return KM.UI.Hex(C.muted) .. "listed|r" end
    return KM.UI.Hex(C.dim) .. "no price|r"
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

KM.RegisterHomeTile({ id = "shopping", order = 45, get = function()
    if not ns.db or not ns.AllWanted then return nil end
    local ids = ns.AllWanted()
    if #ids == 0 then return nil end
    local n = ns.UnderMaxCount()
    return "Shopping", n .. " under max", #ids .. " items on your lists", n > 0 and KM.UI.C.good or nil
end })

if ScannerKing and ScannerKing.Watch then
    -- the merged scan prices every item on every list, even ones outside Trade Goods
    ScannerKing.Watch("Shopping_King", function() return ns.AllWanted and ns.AllWanted() or {} end)
end

KM.RegisterSettings({ id = "shopping", label = "Shopping", order = 15, rows = {
    { type = "header", label = "Auction house" },
    { type = "check", label = "Show the Shopping panel when the auction house opens",
      tip = "The panel docks to the right of the auction house. Its Shopping button shows or hides it either way.",
      get = function() return ns.db.settings.autoPanel end, set = function(v) ns.db.settings.autoPanel = v end },
    { type = "choice", label = "Items without a max price", options = { { "market", "Max = market" }, { "none", "No limit" } },
      get = function() return ns.db.settings.defaultMax end, set = function(v) ns.db.settings.defaultMax = v end },
    { type = "check", label = "Play a sound when a purchase goes through",
      get = function() return ns.db.settings.sound end, set = function(v) ns.db.settings.sound = v end },
    { type = "text", label = "Buying is always one click per step: Buy asks the auction house for the price, Confirm buys. "
        .. "Nothing is bought above an item's max price unless you tick \"Buy above my max\" for that purchase." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/shop   open the Shopping page\n/shop add [item] [qty] [max]   add to the Shopping list\n"
        .. "/shop remove [item]   remove from the Shopping list\n/shop list [name]   your lists, or one list's items\n/shop panel   show or hide the auction house panel" },
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
                KM.Print(ns, "  " .. ns.Name(e.itemID) .. (e.qty and ("  want " .. e.qty) or "") .. (e.max and ("  max " .. KM.Money(e.max)) or ""))
            end
        else
            for _, name in ipairs(API.Lists()) do KM.Print(ns, name .. ": " .. #API.Items(name) .. " items.") end
        end
    elseif cmd == "panel" then
        if ns.TogglePanel then ns.TogglePanel() end
    else
        KM.Print(ns, "/shop   open the Shopping page (or /km shopping)")
        KM.Print(ns, "/shop add [item] [qty] [max]   add to the Shopping list (max like 1g50s)")
        KM.Print(ns, "/shop remove [item]   remove from the Shopping list")
        KM.Print(ns, "/shop list [name]   your lists, or one list's items")
        KM.Print(ns, "/shop panel   show or hide the panel at the auction house")
    end
end
