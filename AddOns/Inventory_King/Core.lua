local _, ns = ...

-- Inventory King: the asset side of the King suite. Everything you own on
-- every character (bags, bank, warband bank, mailbox and auctions still up),
-- what it's worth at Scanner King's prices, and your net worth: the gold on
-- every character (and waiting in their mailboxes) plus those items.
--
-- Files:
--   Core.lua     saved data, money, items and categories, slash command
--   Scan.lua     reads each character's bags, bank, mail, auctions and gold
--   Worth.lua    prices, the item list (filtered), characters and net worth
--   History.lua  net worth per character, one point a day
--   Tooltip.lua  how many you own, on which character, in item tooltips
--   UI.lua       the window and the minimap button

InventoryKing = { API_VERSION = 1 }
local API = InventoryKing
ns.API = API

local PREFIX = "|cff60c0ffInventory King|r: "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

function ns.Now()
    return ScannerKing and ScannerKing.Now and ScannerKing.Now() or (GetServerTime and GetServerTime()) or time()
end

-- "1g 23s 45c" with colors, Scanner King's when it's there.
function ns.Money(v)
    if not v then return "|cff808080-|r" end
    local a = math.floor(math.abs(v) + 0.5)
    local s
    if ScannerKing and ScannerKing.FormatMoney then
        s = ScannerKing.FormatMoney(a)
    else
        local g, sv, c = math.floor(a / 10000), math.floor(a / 100) % 100, a % 100
        s = (g > 0 and (g .. "g ") or "") .. ((g > 0 or sv > 0) and (sv .. "s ") or "") .. c .. "c"
    end
    return v < 0 and ("|cffff6060-|r" .. s) or s
end

-- Just the gold, for big numbers: "1,234g".
function ns.Gold(v)
    if not v then return "|cff808080-|r" end
    local g = tostring(math.floor(math.abs(v) / 10000))
    g = g:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (v < 0 and "-" or "") .. g .. "|cffffd700g|r"
end

ns.WARBAND = "Warband"

-- The character this is, as "Name-Realm".
function ns.Char()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    return realm ~= "" and (name .. "-" .. realm) or name
end

-- "Jay-Forever" -> "Jay" (the realm only when it isn't yours).
function ns.Short(who)
    if not who then return "?" end
    local name, realm = who:match("^(.-)%-(.+)$")
    if not name then return who end
    local mine = GetRealmName and GetRealmName() or ""
    return realm == mine and name or who
end

-- A character's name in its class color.
function ns.CharText(who)
    if who == ns.WARBAND then return "|cff60c0ffWarband bank|r" end
    local c = ns.db and ns.db.chars[who]
    local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local name = ns.Short(who)
    if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
    return name
end

---------------------------------------------------------------------------
-- Items: names, quality, vendor price, category
---------------------------------------------------------------------------

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80" }

local info = {}
-- name, quality, vendor price (copper each); nil name while the game is still loading it.
function ns.ItemInfo(id)
    local i = info[id]
    if i then return i[1], i[2], i[3] end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not (id and get) then return nil end
    local name, _, quality, _, _, _, _, _, _, _, sell = get(id)
    if name then info[id] = { name, quality, sell } end
    return name, quality, sell
end

function ns.ItemText(id)
    local name, q = ns.ItemInfo(id)
    return (QUALITY[q or 1] or "|cffffffff") .. (name or ("Item " .. id)) .. "|r"
end

-- Categories are the auction house's: item class (Trade Goods...) and subclass (Herb...).
-- Tab order: what people trade most first.
ns.CLASS_ORDER = { 7, 0, 4, 2, 9, 5, 15, 1, 6, 11, 3, 8, 12, 13, 16, 17 }
local FALLBACK = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor", [5] = "Reagent",
    [6] = "Projectile", [7] = "Trade Goods", [8] = "Item Enhancement", [9] = "Recipe", [11] = "Quiver",
    [12] = "Quest", [13] = "Key", [15] = "Miscellaneous", [16] = "Glyph", [17] = "Battle Pets",
}

local classOf = {}
-- classID, subclassID
function ns.ClassOf(id)
    local c = classOf[id]
    if c then return c[1], c[2] end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local cls, sub
    if inst then cls, sub = select(6, inst(id)) end
    c = { cls or 15, sub or 0 }
    classOf[id] = c
    return c[1], c[2]
end

local names = {}
function ns.ClassName(cls)
    if names[cls] then return names[cls] end
    local n
    if C_Item and C_Item.GetItemClassInfo then n = C_Item.GetItemClassInfo(cls)
    elseif GetItemClassInfo then n = GetItemClassInfo(cls) end
    names[cls] = (n and n ~= "") and n or FALLBACK[cls] or ("Class " .. cls)
    return names[cls]
end

local subNames = {}
function ns.SubclassName(cls, sub)
    local key = cls .. ":" .. sub
    if subNames[key] then return subNames[key] end
    local n
    if C_Item and C_Item.GetItemSubClassInfo then n = C_Item.GetItemSubClassInfo(cls, sub)
    elseif GetItemSubClassInfo then n = GetItemSubClassInfo(cls, sub) end
    subNames[key] = (n and n ~= "") and n or "Other"
    return subNames[key]
end

-- Mail King's strategy for an item (Herbalism, Mob drops, Flips...), when it's installed.
function ns.Strategy(id)
    if MailKing and MailKing.StrategyOf then
        local ok, s = pcall(MailKing.StrategyOf, id)
        if ok then return s end
    end
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- Mail King 1.1 kept stock and gold itself: bring them over once, so nothing is lost.
local function importMailKing(db)
    if db.imported or type(MailKingDB) ~= "table" then return end
    db.imported = true
    local n = 0
    for who, s in pairs(MailKingDB.stock or {}) do
        if not db.stock[who] then db.stock[who] = s; n = n + 1 end
    end
    for who, g in pairs(MailKingDB.gold or {}) do
        local c = db.chars[who] or {}
        db.chars[who] = c
        if not c.goldT or (g.t or 0) > c.goldT then c.gold, c.goldT = g.m, g.t end
        c.seen = c.seen or g.t
    end
    MailKingDB.stock, MailKingDB.gold = nil, nil
    if n > 0 then ns.Print("brought over what Mail King knew about " .. n .. " characters.") end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= "Inventory_King" then return end
    InventoryKingDB = InventoryKingDB or {}
    local db = InventoryKingDB
    db.stock = db.stock or {}     -- "Name-Realm" (or "Warband") -> { bags, bank, mail, ah = { itemID = n }, bagsT... }
    db.chars = db.chars or {}     -- "Name-Realm" -> { gold, goldT, mail (copper in the mailbox), class, level, faction, seen }
    db.history = db.history or {} -- day -> { "Name-Realm" -> { g = gold, a = items' worth } }
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
    if db.ui.tooltip == nil then db.ui.tooltip = true end
    if db.ui.vendor == nil then db.ui.vendor = true end
    db.ui.price = db.ui.price or "market"
    ns.db = db
    importMailKing(db)
end)

-- Forget a character (deleted, renamed, transferred): its items, gold and history.
function ns.Forget(who)
    if not (ns.db and who) then return false end
    local known = ns.db.stock[who] or ns.db.chars[who]
    ns.db.stock[who], ns.db.chars[who] = nil, nil
    for _, day in pairs(ns.db.history) do day[who] = nil end
    if ns.Refresh then ns.Refresh() end
    return known ~= nil
end

-- Every character (and the warband bank) Inventory King knows, by name.
function ns.Known()
    local seen, out = {}, {}
    for who in pairs(ns.db.chars) do seen[who] = true end
    for who in pairs(ns.db.stock) do seen[who] = true end
    for who in pairs(seen) do table.insert(out, who) end
    table.sort(out, function(a, b)
        if (a == ns.WARBAND) ~= (b == ns.WARBAND) then return b == ns.WARBAND end
        return a < b
    end)
    return out
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_INVENTORYKING1 = "/ik"
SLASH_INVENTORYKING2 = "/inventoryking"
SlashCmdList.INVENTORYKING = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local function onoff(v) local r = rest:lower(); if r == "on" then return true elseif r == "off" then return false end return not v end
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "button" then
        ns.db.ui.button = onoff(ns.db.ui.button)
        ns.UpdateMinimapButton()
    elseif cmd == "tooltip" then
        ns.db.ui.tooltip = onoff(ns.db.ui.tooltip)
        ns.Print("item tooltips " .. (ns.db.ui.tooltip and "on." or "off."))
    elseif cmd == "vendor" then
        ns.db.ui.vendor = onoff(ns.db.ui.vendor)
        ns.Print("items with no auction price " .. (ns.db.ui.vendor and "count at their vendor price." or "count as nothing."))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "price" and (rest == "market" or rest == "lowest") then
        ns.db.ui.price = rest
        ns.Print("items valued at the " .. (rest == "market" and "market price." or "lowest buyout."))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "forget" and rest ~= "" then
        local who = rest
        if not who:find("-") and GetRealmName then who = who .. "-" .. GetRealmName() end
        ns.Print(ns.Forget(who) and ("forgot " .. who .. ".") or ("no character called " .. who .. "."))
    elseif cmd == "export" then
        ns.Export()
    elseif cmd == "status" then
        local w = ns.NetWorth()
        ns.Print("net worth " .. ns.Money(w.total) .. ": gold " .. ns.Money(w.gold + w.mail) .. ", items " .. ns.Money(w.assets)
            .. " on " .. w.chars .. " characters.")
    else
        ns.Print("/ik   open Inventory King (or click the minimap button)")
        ns.Print("/ik status   your net worth in one line")
        ns.Print("/ik price market|lowest   value items at the market price or the lowest buyout")
        ns.Print("/ik vendor [on|off]   items with no auction price count at their vendor price")
        ns.Print("/ik tooltip [on|off]   how many you own, in item tooltips")
        ns.Print("/ik forget Name-Realm   forget a deleted or moved character")
        ns.Print("/ik export   items and characters as text for a spreadsheet")
        ns.Print("/ik button [on|off]   minimap button")
    end
end
