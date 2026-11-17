local _, KM = ...
local ns = KM.Module("Mail", { title = "Mail King", short = "Mail", legacy = "Mail_King", db = "MailKingDB" })

-- Mail King: the money side of the King suite. Every auction house mail you
-- open (sales, purchases, expired and cancelled auctions) goes in a ledger,
-- so you can see what you actually made, where it came from, and which of
-- your farms and strategies are paying off, who your best customers are, and
-- what isn't selling. What you own (and your net worth) is Inventory King's.
--
-- Files:
--   Core.lua     saved data, money and item helpers, strategies, slash command
--   Mail.lua     reads the mailbox, and auction postings (for deposits and prices)
--   Ledger.lua   adds it all up: periods, strategies, items, buyers, what isn't selling
--   UI.lua       the Sales Ledger page (Auction House > Sales Ledger), the crown's quick action and tooltip line,
--                Home, Settings
--   Alts.lua     My characters: your alts beside the mailbox, click one to send it mail
--
-- In King Maker it has no window or minimap button of its own: /mlk and the crown open the "ledger" page.

MailKing = { API_VERSION = 1 }
local API = MailKing
ns.API = API

-- Change callbacks for other addons: MailKing.RegisterCallback("ENTRY" | "RESET", fn, owner).
--   "ENTRY"  fn("ENTRY", entry) right after a mail is recorded (a copy, in GetEntries' shape)
--   "RESET"  fn("RESET") after the ledger is cleared (/mlk reset yes)
-- Each runs in a pcall; nothing runs when no addon registers.
local callbacks = { ENTRY = {}, RESET = {} }

function API.RegisterCallback(event, fn, owner)
    if not callbacks[event] or type(fn) ~= "function" then return false end
    callbacks[event][owner or fn] = fn
    return true
end

function API.UnregisterCallback(event, owner)
    if callbacks[event] then callbacks[event][owner] = nil end
end

function ns.Fire(event, ...)
    for _, fn in pairs(callbacks[event] or {}) do pcall(fn, event, ...) end
end

-- Your auction postings still remembered (Mail.lua keeps them 3 days; auctions last at most 48 hours), newest first,
-- as copies: { id, name, n, dep, each, t, c }. itemID: that item's only. Profit & Loss reads the asking price here.
function API.GetPosts(itemID)
    local out = {}
    if not (ns.db and ns.db.posts) then return out end
    for i = #ns.db.posts, 1, -1 do
        local p = ns.db.posts[i]
        if not itemID or p.id == itemID then
            local c = {}
            for k, v in pairs(p) do c[k] = v end
            out[#out + 1] = c
        end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

function ns.Now()
    return ScannerKing and ScannerKing.Now and ScannerKing.Now() or (GetServerTime and GetServerTime()) or time()
end

-- "1g 23s 45c" with coin colours (King Maker's one money format); nil is a grey dash, negative a red minus.
function ns.Money(v) return KM.Money(v) end

-- The character this is, as "First Last-Realm" (KM.Char: Forever names have a surname).
function ns.Char() return KM.Char() end

-- 2.3.0 keys characters by their full name: this character's mail and postings under its first name move over.
function ns.RenameChar(old, new)
    for _, e in ipairs(ns.db.entries) do if e.c == old then e.c = new end end
    for _, p in ipairs(ns.db.posts) do if p.c == old then p.c = new end end
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

-- Before 2.6.0 one mail could be recorded two or three times (Mail.lua). Run once: the same character, kind, item,
-- count, price, cut and deposit within 5 seconds is one mail; the copy with the buyer's name is kept, dated the
-- earliest. Returns how many copies were removed.
function ns.Dedupe()
    local list = ns.db.entries
    local order = {}
    for i in ipairs(list) do order[i] = i end
    table.sort(order, function(a, b)
        local ta, tb = list[a].t or 0, list[b].t or 0
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    local groups, drop, removed = {}, {}, 0
    for _, i in ipairs(order) do
        local e = list[i]
        local sig = table.concat({ tostring(e.c), tostring(e.k), tostring(e.name), tostring(e.n), tostring(e.g),
            tostring(e.cut), tostring(e.dep) }, "|")
        local g = groups[sig]
        if not g then g = {}; groups[sig] = g end
        local last = g[#g]
        if last and (e.t or 0) - last.t <= 5 then
            local keep, gone = list[last.i], e
            if (keep.who or "") == "" and (e.who or "") ~= "" then
                drop[last.i], last.i = true, i
                keep, gone = e, keep
            else
                drop[i] = true
            end
            keep.t = last.t
            for k, v in pairs(gone) do if keep[k] == nil then keep[k] = v end end
            removed = removed + 1
        else
            table.insert(g, { t = e.t or 0, i = i })
        end
    end
    if removed > 0 then
        local out = {}
        for i, e in ipairs(list) do if not drop[i] then table.insert(out, e) end end
        wipe(list)
        for i, e in ipairs(out) do list[i] = e end
    end
    return removed
end

-- Runs when King Maker's saved variables load, and again after old Mail_King data is moved in: safe twice.
function ns.InitDB()
    MailKingDB = MailKingDB or {}
    local db = MailKingDB
    db.entries = db.entries or {}   -- the ledger (Mail.lua): { t, k, item, name, n, g, cut, dep, each, who, c }
    -- db.dedupe = 1 once 2.6.0's cleanup of mails recorded twice has run (ns.Dedupe)
    db.seen = db.seen or {}         -- mail key -> when it was recorded, so a mail counts once
    db.posts = db.posts or {}       -- your auctions still up: what they cost to post
    db.names = db.names or {}       -- item name -> itemID
    db.strategy = db.strategy or {} -- itemID (or name) -> your strategy for it
    db.custom = db.custom or {}     -- strategies you made up
    -- 1.1 kept gold and stock here (db.gold, db.stock): Inventory King brings them over and clears them.
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    db.ui.period = db.ui.period or 7
    if db.ui.alts == nil then db.ui.alts = true end -- My characters beside the mailbox
    db.altNames = db.altNames or {} -- "First-Realm" (an alt saved before 2.3.0) -> "First Last", learned from mail
    ns.db = db
    if ns.Prune then ns.Prune() end
    if db.dedupe ~= 1 then -- 2.6.0: the copies older versions recorded go, once
        local ok, removed = pcall(ns.Dedupe)
        if ok then
            db.dedupe = 1
            if removed > 0 then
                KM.Print(ns, ("Sales Ledger: removed %d %s that had been counted twice."):format(removed,
                    removed == 1 and "mail" or "mails"))
            end
        end
    end
    -- Old 1.1 stock and gold may have just arrived (moved in from a Mail_King folder): the Inventory module takes them.
    local inv = KM.mods.Inventory
    if inv and inv.ImportMailKing then KM.Safe(inv.ImportMailKing) end
end

-- Blocked-action reports: one guard for every module lives in Core\Boot.lua.

-- Clears the whole ledger (/mlk reset yes, or the button in Settings). Strategies you chose stay.
function ns.Reset()
    wipe(ns.db.entries); wipe(ns.db.seen); wipe(ns.db.posts)
    KM.Print(ns, "Ledger cleared.")
    ns.Fire("RESET")
    if ns.Refresh then ns.Refresh() end
end

SLASH_MAILKING1 = "/mlk" -- /mk is Market King's
SLASH_MAILKING2 = "/mailking"
SlashCmdList.MAILKING = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if not ns.db then return end
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "export" then
        ns.Export()
    elseif cmd == "status" then
        local s = ns.Summary(0)
        KM.Print(ns, #ns.db.entries .. " mails recorded. All time: " .. s.sales .. " sales, profit " .. ns.Money(s.profit) .. ".")
    elseif cmd == "reset" and rest:lower() == "yes" then
        ns.Reset()
    elseif cmd == "alts" then
        local v = rest:lower()
        ns.SetAlts(v == "on" or (v ~= "off" and not ns.db.ui.alts))
        KM.Print(ns, "My characters beside the mailbox: " .. (ns.db.ui.alts and "on." or "off."))
    else
        KM.Print(ns, "/mlk   open the Sales Ledger (or /km ledger)")
        KM.Print(ns, "/mlk status   what's been recorded")
        KM.Print(ns, "/mlk export   the ledger as text to copy into a spreadsheet")
        KM.Print(ns, "/mlk alts [on|off]   your characters beside the mailbox, click one to mail it")
        KM.Print(ns, "/mlk reset yes   clear the whole ledger")
    end
end
