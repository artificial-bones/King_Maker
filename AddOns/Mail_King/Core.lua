local _, ns = ...

-- Mail King: the money side of the King suite. Every auction house mail you
-- open (sales, purchases, expired and cancelled auctions) goes in a ledger,
-- so you can see what you actually made, where it came from, and which of
-- your farms and strategies are paying off.
--
-- Files:
--   Core.lua     saved data, money and item helpers, strategies, slash command
--   Mail.lua     reads the mailbox, auction postings (for deposits) and your gold
--   Ledger.lua   adds it all up: periods, strategies, items
--   Stock.lua    what's in every character's bags, bank, mail and auctions, and its worth
--   UI.lua       the window and the minimap button

MailKing = { API_VERSION = 1 }
local API = MailKing
ns.API = API

local PREFIX = "|cffe0c040Mail King|r: "
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

-- The character this is, as "Name-Realm".
function ns.Char()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    return realm ~= "" and (name .. "-" .. realm) or name
end

---------------------------------------------------------------------------
-- Items: names to IDs (a sale mail only names the item)
---------------------------------------------------------------------------

function ns.LearnItem(name, id)
    if name and id and name ~= "" then ns.db.names[name] = id end
end

function ns.ItemID(name)
    if not name then return nil end
    local id = ns.db.names[name]
    if id then return id end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if inst then
        local ok, found = pcall(inst, name)
        if ok and found then ns.db.names[name] = found; return found end
    end
    return nil
end

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }
function ns.ItemText(id, name)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local q
    if id and get then
        local n, _, quality = get(id)
        name, q = n or name, quality
    end
    return (QUALITY[q or 1] or "|cffffffff") .. (name or (id and ("Item " .. id)) or "?") .. "|r"
end

local function classOf(id)
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (id and inst) then return nil end
    local _, _, _, _, _, classID, subclassID = inst(id)
    return classID, subclassID
end

---------------------------------------------------------------------------
-- Strategies: where an item's money comes from
---------------------------------------------------------------------------

-- What every item falls under unless you say otherwise, in this order:
--   1. your own choice for that item (right-click it in any list),
--   2. Flips: you bought it on the auction house before selling it,
--   3. raw materials by type: Mining, Herbalism, Skinning, Cloth, Enchanting,
--      Cooking, Elemental,
--   4. Mob drops: Farm King has seen it drop,
--   5. Gear, Consumables, Recipes, or Other.
ns.STRATEGIES = { "Mining", "Herbalism", "Skinning", "Cloth", "Enchanting", "Cooking", "Elemental",
    "Mob drops", "Flips", "Gear", "Consumables", "Recipes", "Purchases", "Other" }

local TRADE = { [5] = "Cloth", [6] = "Skinning", [7] = "Mining", [8] = "Cooking", [9] = "Herbalism",
    [10] = "Elemental", [12] = "Enchanting" }
local CLASS = { [0] = "Consumables", [2] = "Gear", [4] = "Gear", [9] = "Recipes" }

-- The strategy for an item with no history: your choice, its type, Farm King.
function ns.ItemStrategy(id, name)
    local o = ns.db.strategy[id or name] or (name and ns.db.strategy[name])
    if o then return o, true end
    local classID, sub = classOf(id)
    if classID == 7 and TRADE[sub] then return TRADE[sub] end
    if id and FarmKing and FarmKing.IsDrop and FarmKing.IsDrop(id) then return "Mob drops" end
    return classID and CLASS[classID] or "Other"
end

-- Your choice for an item (nil goes back to automatic).
function ns.SetStrategy(id, name, strategy)
    local key = id or name
    if not key then return end
    ns.db.strategy[key] = strategy
    if name and id then ns.db.strategy[name] = nil end
    if strategy then
        local known = false
        for _, s in ipairs(ns.Strategies()) do if s == strategy then known = true end end
        if not known then table.insert(ns.db.custom, strategy) end
    end
    if ns.Refresh then ns.Refresh() end
end

-- Built-in strategies, then the ones you made up.
function ns.Strategies()
    local out = {}
    for _, s in ipairs(ns.STRATEGIES) do table.insert(out, s) end
    for _, s in ipairs(ns.db.custom) do table.insert(out, s) end
    return out
end

---------------------------------------------------------------------------
-- Saved data, slash command
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= "Mail_King" then return end
    MailKingDB = MailKingDB or {}
    local db = MailKingDB
    db.entries = db.entries or {}   -- the ledger (Mail.lua): { t, k, item, name, n, g, cut, dep, who, c }
    db.seen = db.seen or {}         -- mail key -> when it was recorded, so a mail counts once
    db.posts = db.posts or {}       -- your auctions still up: what they cost to post
    db.names = db.names or {}       -- item name -> itemID
    db.strategy = db.strategy or {} -- itemID (or name) -> your strategy for it
    db.custom = db.custom or {}     -- strategies you made up
    db.gold = db.gold or {}         -- "Name-Realm" -> { m = copper, t = when }
    db.stock = db.stock or {}       -- "Name-Realm" (or "Warband") -> { bags, bank, mail, ah = { itemID = n }, bagsT... }
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
    db.ui.period = db.ui.period or 7
    ns.db = db
    if ns.Prune then ns.Prune() end
end)

-- If the game ever stops Mail King from doing something, say what it was, so it can be fixed.
local guard = CreateFrame("Frame")
guard:RegisterEvent("ADDON_ACTION_FORBIDDEN")
guard:RegisterEvent("ADDON_ACTION_BLOCKED")
guard:SetScript("OnEvent", function(_, event, addon, what)
    if addon == "Mail_King" then
        ns.Print("the game blocked Mail King from " .. tostring(what) .. " (" .. event .. "). Please send this line along.")
    end
end)

SLASH_MAILKING1 = "/mlk" -- /mk is Market King's
SLASH_MAILKING2 = "/mailking"
SlashCmdList.MAILKING = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "button" then
        ns.db.ui.button = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.button)
        ns.UpdateMinimapButton()
    elseif cmd == "export" then
        ns.Export()
    elseif cmd == "status" then
        local s = ns.Summary(0)
        ns.Print(#ns.db.entries .. " mails recorded. All time: " .. s.sales .. " sales, profit " .. ns.Money(s.profit) .. ".")
    elseif cmd == "reset" and rest:lower() == "yes" then
        wipe(ns.db.entries); wipe(ns.db.seen); wipe(ns.db.posts)
        ns.Print("Ledger cleared.")
        if ns.Refresh then ns.Refresh() end
    else
        ns.Print("/mlk   open Mail King (or click the minimap button)")
        ns.Print("/mlk status   what's been recorded")
        ns.Print("/mlk export   the ledger as text to copy into a spreadsheet")
        ns.Print("/mlk button [on|off]   minimap button")
        ns.Print("/mlk reset yes   clear the whole ledger")
    end
end
