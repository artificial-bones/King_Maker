local _, KM = ...
local ns = KM.Module("Scanner", { title = "Scanner King", short = "Scanner", legacy = "Scanner_King", db = "ScannerKingDB" })

-- Scanner King keeps one table of auction prices that every other module reads.
-- Its public face is the global ScannerKing table (see API.md):
--
--   ScannerKing.GetPrice(itemID)       -> copper each, scanned at (server time), quantity listed
--   ScannerKing.Watch(owner, itemIDs or function) -> also scan these, even if they aren't Trade Goods
--   ScannerKing.Scan([{ items = ids }]) -> start a scan (auction house must be open), optionally with extra items
--   ScannerKing.RegisterCallback(owner, fn)   fn(event, ...) for
--       "SCAN_STARTED", "SCAN_PROGRESS" (text), "SCAN_FINISHED" (found), "PRICES_UPDATED"
--
-- In King Maker it has no window or minimap button of its own: the price list is the "prices" page
-- (Browser.lua), the scans are quick actions on the King Maker crown, and its settings are a section of
-- the Settings page. The auction house title-bar buttons and the Deep Scan / Market Scan dialogs stay.

local API = { API_VERSION = 1 }
ScannerKing = API
ns.API = API

function ns.Now()
    return GetServerTime and GetServerTime() or time() -- same clock for every guildmate
end
API.Now = ns.Now

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------

local callbacks = {}

function API.RegisterCallback(owner, fn)
    callbacks[owner] = fn
end

function API.UnregisterCallback(owner)
    callbacks[owner] = nil
end

function ns.Fire(event, ...)
    for _, fn in pairs(callbacks) do
        pcall(fn, event, ...)
    end
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- db.prices[itemID] = { p = copper each (lowest buyout), t = server time scanned, q = quantity listed,
--                      from = guildmate or nil,
--                      m = market price, n = auctions (Deep Scan only),
--                      d = true when it came from a Deep Scan and isn't shared with the guild }

function API.GetPrice(itemID)
    local p = ns.db and ns.db.prices[itemID]
    if p then return p.p, p.t, p.q end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, copper = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "Scanner_King", itemID)
        if ok and copper and copper > 0 then return copper, nil end
    end
    return nil
end

-- Market price from the last full Deep Scan (the average of the cheapest
-- listings), or the lowest price when that's all we have. Returns copper, scan time,
-- quantity listed, and whether it's a true market price.
function API.GetMarketPrice(itemID)
    local p = ns.db and ns.db.prices[itemID]
    if p and p.m then return p.m, p.t, p.q, true end
    local copper, t, q = API.GetPrice(itemID)
    return copper, t, q, false
end

-- Read-only view of every stored price, for addons that list the whole market.
function API.GetAllPrices()
    return ns.db and ns.db.prices or {}
end

function API.LastScan()
    return ns.db and ns.db.lastScan
end

function ns.Store(itemID, copper, quantity)
    if not (itemID and copper and copper > 0) then return false end
    ns.db.prices[itemID] = { p = copper, t = ns.Now(), q = quantity }
    return true
end

-- Keeps a price from a guildmate (or another addon) if it's newer than ours.
function API.MergePrice(itemID, copper, t, from)
    if not ns.db or not (itemID and copper and copper > 0 and t) then return false end
    local mine = ns.db.prices[itemID]
    if not mine or t > mine.t then
        ns.db.prices[itemID] = { p = copper, t = t, from = from }
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Watched items: other addons ask for items outside Trade Goods
---------------------------------------------------------------------------

local watched = {} -- owner -> { itemID, ... } or a function returning one

-- ids can be a list, or a function that returns the list when a scan starts.
function API.Watch(owner, ids)
    watched[owner] = ids
end

function ns.WatchedItems()
    local seen, list = {}, {}
    for _, ids in pairs(watched) do
        if type(ids) == "function" then
            local ok, r = pcall(ids)
            ids = ok and type(r) == "table" and r or {}
        end
        for _, id in ipairs(ids) do
            if id and not seen[id] then seen[id] = true; table.insert(list, id) end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Formatting helpers (shared so every addon in the suite looks the same)
---------------------------------------------------------------------------

function API.FormatMoney(copper)
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, "|cffffd700" .. g .. "g|r") end
    if s > 0 then table.insert(parts, "|cffc7c7cf" .. s .. "s|r") end
    if c > 0 or #parts == 0 then table.insert(parts, "|cffeda55f" .. c .. "c|r") end
    return table.concat(parts, " ")
end

function API.PriceAge(t)
    if not t then return "Auctionator" end
    local mins = math.max(0, math.floor((ns.Now() - t) / 60))
    if mins < 60 then return mins .. " min ago" end
    if mins < 60 * 48 then return math.floor(mins / 60) .. " h ago" end
    return math.floor(mins / 1440) .. " days ago"
end

---------------------------------------------------------------------------
-- Saved data and slash command
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Scanner_King data is moved in: safe twice.
function ns.InitDB()
    ScannerKingDB = ScannerKingDB or {}
    local db = ScannerKingDB
    db.prices = db.prices or {}
    db.items = db.items or {} -- name, icon and category per item, for the price list
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    if db.ui.tooltip == nil then db.ui.tooltip = true end
    db.sync = db.sync or {}
    if db.sync.guild == nil then db.sync.guild = true end
    ns.db = db
    API.ready = true
end

SLASH_SCANNERKING1 = "/sk"
SLASH_SCANNERKING2 = "/scannerking"
SlashCmdList.SCANNERKING = function(msg)
    if not ns.db then return end
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "scan" then
        API.Scan()
    elseif cmd == "deep" then
        API.OpenDeepScan(true)
    elseif cmd == "market" then
        API.OpenMarketScan()
    elseif cmd == "tooltip" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        if arg == "on" then ns.db.ui.tooltip = true elseif arg == "off" then ns.db.ui.tooltip = false
        else ns.db.ui.tooltip = not ns.db.ui.tooltip end
        KM.Print(ns, "Prices in item tooltips " .. (ns.db.ui.tooltip and "on." or "off."))
    elseif cmd == "sync" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        if arg == "on" or arg == "off" then
            ns.db.sync.guild = arg == "on"
            KM.Print(ns, "Guild price sharing is " .. arg .. ".")
        else
            ns.SharePrices(true)
        end
    elseif cmd == "" or cmd == "show" or cmd == "list" then
        API.ToggleBrowser()
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "status" then
        local n = 0
        for _ in pairs(ns.db.prices) do n = n + 1 end
        KM.Print(ns, n .. " prices stored. Last scan: " .. (ns.db.lastScan and API.PriceAge(ns.db.lastScan) or "never")
            .. ". Last Deep Scan: " .. (ns.db.lastDeep and API.PriceAge(ns.db.lastDeep) or "never") .. ".")
    else
        KM.Print(ns, "/sk show   open the Prices page (or /km prices)")
        KM.Print(ns, "/sk scan   Material Scan (the auction house must be open)")
        KM.Print(ns, "/sk deep   Deep Scan: every item on the auction house")
        KM.Print(ns, "/sk market   Market Scan: pick professions to price")
        KM.Print(ns, "/sk tooltip [on|off]   prices in item tooltips")
        KM.Print(ns, "/sk status   how many prices you have and how old")
        KM.Print(ns, "/sk sync [on|off]   share prices with your guild now, or turn sharing on/off")
    end
end
