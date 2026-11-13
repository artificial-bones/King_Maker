local _, KM = ...
local ns = KM.Module("Inventory", { title = "Inventory King", short = "Inventory", legacy = "Inventory_King", db = "InventoryKingDB" })

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
--   UI.lua       the Inventory page (Gold > Inventory), the crown's quick action and tooltip line, Home, Settings
--
-- In King Maker it has no window or minimap button of its own: /ik and the crown open the "inventory" page.

InventoryKing = { API_VERSION = 1 }
local API = InventoryKing
ns.API = API


function ns.Now()
    return ScannerKing and ScannerKing.Now and ScannerKing.Now() or (GetServerTime and GetServerTime()) or time()
end

-- "1g 23s 45c" with coin colours (King Maker's one money format); nil is a grey dash.
function ns.Money(v) return KM.Money(v) end

-- Just the gold, for big numbers: "1,234g".
function ns.Gold(v)
    if not v then return "|cff808080-|r" end
    return (v < 0 and "-" or "") .. KM.Commas(math.floor(math.abs(v) / 10000)) .. "|cffffd700g|r"
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

-- Mail King 1.1 kept stock and gold itself: bring them over once, so nothing is lost. In King Maker the old
-- MailKingDB can arrive after this module's InitDB (Boot moves a Mail_King folder's data in when that stub loads),
-- so this runs again from the Mail module's InitDB and at login. It only counts as done once there was something
-- to bring over.
function ns.ImportMailKing()
    local db = ns.db
    if not db or db.imported or type(MailKingDB) ~= "table" then return end
    if type(MailKingDB.stock) ~= "table" and type(MailKingDB.gold) ~= "table" then return end
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
    if n > 0 then KM.Print(ns, "brought over what Mail King knew about " .. n .. " characters.") end
end

-- Runs when King Maker's saved variables load, and again after old Inventory_King data is moved in: safe twice.
function ns.InitDB()
    InventoryKingDB = InventoryKingDB or {}
    local db = InventoryKingDB
    db.stock = db.stock or {}     -- "Name-Realm" (or "Warband") -> { bags, bank, mail, ah = { itemID = n }, bagsT... }
    db.chars = db.chars or {}     -- "Name-Realm" -> { gold, goldT, mail (copper in the mailbox), class, level, faction, seen }
    db.history = db.history or {} -- day -> { "Name-Realm" -> { g = gold, a = items' worth } }
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    if db.ui.tooltip == nil then db.ui.tooltip = true end
    if db.ui.vendor == nil then db.ui.vendor = true end
    if db.ui.cheapest == nil then db.ui.cheapest = true end -- a red X (bottom left) on the cheapest stack in your bags
    db.ui.price = db.ui.price or "market"
    ns.db = db
    ns.ImportMailKing()
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() ns.ImportMailKing() end)

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
    if not ns.db then return end
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "tooltip" then
        ns.db.ui.tooltip = onoff(ns.db.ui.tooltip)
        KM.Print(ns, "item tooltips " .. (ns.db.ui.tooltip and "on." or "off."))
    elseif cmd == "vendor" then
        ns.db.ui.vendor = onoff(ns.db.ui.vendor)
        KM.Print(ns, "items with no auction price " .. (ns.db.ui.vendor and "count at their vendor price." or "count as nothing."))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "price" and (rest == "market" or rest == "lowest") then
        ns.db.ui.price = rest
        KM.Print(ns, "items valued at the " .. (rest == "market" and "market price." or "lowest buyout."))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "forget" and rest ~= "" then
        local who = rest
        if not who:find("-") and GetRealmName then who = who .. "-" .. GetRealmName() end
        KM.Print(ns, ns.Forget(who) and ("forgot " .. who .. ".") or ("no character called " .. who .. "."))
    elseif cmd == "cheapest" then
        ns.db.ui.cheapest = onoff(ns.db.ui.cheapest)
        ns.UpdateCheapest()
        KM.Print(ns, "marking the cheapest stack in your bags " .. (ns.db.ui.cheapest and "on." or "off."))
        local c = ns.Cheapest()
        if c then
            KM.Print(ns, "cheapest now: " .. ns.ItemText(c.item) .. (c.count > 1 and (" x" .. c.count) or "") .. ", worth " .. ns.Money(c.value)
                .. " (bag " .. c.bag .. ", slot " .. c.slot .. "); marked on " .. (ns.markedCount or 0) .. " open bag button(s).")
        elseif ns.db.ui.cheapest then
            KM.Print(ns, "nothing in your bags can be marked (no prices, or only quest items, tools and kept items).")
        end
    elseif cmd == "keep" and rest ~= "" then
        local id = tonumber(rest:match("item:(%d+)") or rest)
        if not id then
            local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local link = get and select(2, get(rest))
            id = link and tonumber(link:match("item:(%d+)"))
        end
        if not id then KM.Print(ns, "no item called " .. rest .. " (shift-click it into the chat box).") return end
        KM.Print(ns, ns.ItemText(id) .. (ns.ToggleKeep(id) and " won't be marked as cheapest any more." or " can be marked as cheapest again."))
    elseif cmd == "export" then
        ns.Export()
    elseif cmd == "status" then
        local w = ns.NetWorth()
        KM.Print(ns, "net worth " .. ns.Money(w.total) .. ": gold " .. ns.Money(w.gold + w.mail) .. ", items " .. ns.Money(w.assets)
            .. " on " .. w.chars .. " characters.")
    else
        KM.Print(ns, "/ik   open the Inventory page (or /km inventory)")
        KM.Print(ns, "/ik status   your net worth in one line")
        KM.Print(ns, "/ik price market|lowest   value items at the market price or the lowest buyout")
        KM.Print(ns, "/ik vendor [on|off]   items with no auction price count at their vendor price")
        KM.Print(ns, "/ik tooltip [on|off]   how many you own, in item tooltips")
        KM.Print(ns, "/ik cheapest [on|off]   a red X (bottom left) on the cheapest stack in your bags")
        KM.Print(ns, "/ik keep <item>   never mark that item as cheapest (again to undo)")
        KM.Print(ns, "/ik forget Name-Realm   forget a deleted or moved character")
        KM.Print(ns, "/ik export   items and characters as text for a spreadsheet")
    end
end
