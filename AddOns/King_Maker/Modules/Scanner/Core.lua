local _, KM = ...
local ns = KM.Module("Scanner", { title = "Scanner King", short = "Scanner", legacy = "Scanner_King", db = "ScannerKingDB" })

-- Scanner King keeps one table of auction prices that every other module reads.
-- Its public face is the global ScannerKing table (see API.md):
--
--   ScannerKing.GetPrice(itemID)       -> copper each, scanned at (server time), quantity listed
--   ScannerKing.Watch(owner, itemIDs or function) -> also scan these, even if they aren't Trade Goods
--   ScannerKing.SmartScan()            -> the one scan: the full dump when the game allows it, else a quick scan
--   ScannerKing.Scan([{ items = ids }]) -> a Trade Goods + watched scan (auction house must be open), optionally with extra items
--   ScannerKing.RegisterCallback(owner, fn)   fn(event, ...) for
--       "SCAN_STARTED", "SCAN_PROGRESS" (text), "SCAN_FINISHED" (found), "PRICES_UPDATED"
--
-- In King Maker it has no window or minimap button of its own: the price list is the "prices" page
-- (Browser.lua), the Scan is a quick action on the King Maker crown, and its settings are a section of
-- the Settings page. The auction house title bar has one Scan button; the Deep Scan dialog is for /sk deep.

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

---------------------------------------------------------------------------
-- The neutral auction house (Gadgetzan, Booty Bay, Everlook)
---------------------------------------------------------------------------

-- A scan at a neutral auction house goes into its own book, db.neutral = { prices, lastScan, lastQuick, lastDeep }
-- (the same shapes as the faction ones), so every value in King Maker (crafting, inventory, profit) keeps using your
-- own side's prices. Neutral scans fire NEUTRAL_RESULTS instead of SCAN_RESULTS (Price History stays faction only)
-- and aren't shared with the guild. ns.house is the house of the scan running (or the last one).
ns.house = "faction"

-- Called as a scan starts: which book it writes to.
function ns.StartHouse()
    ns.house = KM.AuctionHouse and KM.AuctionHouse() or "faction"
    return ns.house
end

-- The book a scan writes to: db (faction) or db.neutral.
function ns.Book(house)
    if (house or ns.house) == "neutral" then return ns.db.neutral end
    return ns.db
end

-- A scan's results, to the callback that matches its house.
function ns.FireResults(results, kind, method)
    if ns.house == "neutral" then ns.Fire("NEUTRAL_RESULTS", results, kind, method)
    else ns.Fire("SCAN_RESULTS", results, kind, method) end
end

-- After a scan: only faction prices go to the guild.
function ns.ShareAfterScan()
    if ns.house ~= "neutral" and ns.SharePrices then ns.SharePrices() end
end

-- The neutral auction house's price: lowest buyout, scanned at, listed, market price (nil without one).
function API.GetNeutralPrice(itemID)
    local p = ns.db and ns.db.neutral.prices[itemID]
    if p then return p.p, p.t, p.q, p.m end
    return nil
end

function API.GetAllNeutralPrices() return ns.db and ns.db.neutral.prices or {} end
function API.LastNeutralScan() return ns.db and ns.db.neutral.lastScan end

-- Whether you've ever scanned a neutral auction house (the neutral views stay hidden until you have).
function API.HasNeutral() return ns.db ~= nil and next(ns.db.neutral.prices) ~= nil end

-- Which house the auction house you're at is: "neutral" or "faction".
function API.AuctionHouse() return KM.AuctionHouse() end

-- Neutral against faction for one item, by market price (else lowest): neutral, faction, (neutral - faction) / faction.
function ns.Compare(id)
    local n = ns.db.neutral.prices[id]
    local f = ns.db.prices[id]
    local nv = n and (n.m or n.p)
    local fv = f and (f.m or f.p)
    if not (nv and fv and fv > 0) then return nv, fv, nil end
    return nv, fv, (nv - fv) / fv
end

function ns.Store(itemID, copper, quantity)
    if not (itemID and copper and copper > 0) then return false end
    ns.Book().prices[itemID] = { p = copper, t = ns.Now(), q = quantity }
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
    if mins < 1 then return "just now" end
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
    db.neutral = db.neutral or {} -- 2.18.0: the neutral auction house's own prices and scan times
    db.neutral.prices = db.neutral.prices or {}
    if db.house ~= "neutral" and db.house ~= "faction" then db.house = nil end -- /sk house: nil = tell by the zone
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    if db.ui.tooltip == nil then db.ui.tooltip = true end
    if db.ui.sources == nil then db.ui.sources = true end -- tooltip: Vendor, Drops, Used in
    if db.ui.neutral == nil then db.ui.neutral = true end -- tooltip: the neutral auction house's price, once you have one
    db.ui.tip = db.ui.tip or {} -- tooltip rows: best crafts, craft cost, recipe items, disenchant, short
    for k, v in pairs({ crafts = false, make = true, pattern = true, de = true, short = false }) do
        if db.ui.tip[k] == nil then db.ui.tip[k] = v end
    end
    db.ui.tip.goal = nil -- 2.14.0: the Shopping list row went with Shopping
    if (db.ui.tipVersion or 1) < 2 then -- 2.5.0: the 3 best crafts under Used in crowded the tooltip; off by default
        db.ui.tip.crafts = false
        db.ui.tipVersion = 2
    end
    db.sync = db.sync or {}
    if db.sync.guild == nil then db.sync.guild = true end
    if db.sync.full == nil then db.sync.full = false end
    if db.sync.loot == nil then db.sync.loot = true end -- 2.12: ask the guild for prices of what you loot -- 2.11: pass on whole Deep Scans, not only Trade Goods
    -- db.sync.stamp = { t, by }: the newest scan you hold (Sync.lua), set on the first scan or sync
    ns.db = db
    API.ready = true
end

SLASH_SCANNERKING1 = "/sk"
SLASH_SCANNERKING2 = "/scannerking"
SlashCmdList.SCANNERKING = function(msg)
    if not ns.db then return end
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "scan" then
        API.SmartScan()
    elseif cmd == "deep" or cmd == "full" then
        API.OpenDeepScan(true)
    elseif cmd == "material" then
        API.Scan()
    elseif cmd == "market" then
        if ns.AHOpen and not ns.AHOpen() then
            KM.Print(ns, "Open the auction house first, then type /sk market.")
        else
            API.MarketScan()
        end
    elseif cmd == "tooltip" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        if arg == "on" then ns.db.ui.tooltip = true elseif arg == "off" then ns.db.ui.tooltip = false
        else ns.db.ui.tooltip = not ns.db.ui.tooltip end
        KM.Print(ns, "Prices in item tooltips " .. (ns.db.ui.tooltip and "on." or "off."))
    elseif cmd == "tip" then
        local key, arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)%s*(%S*)")
        if key and ns.db.ui.tip[key] ~= nil then
            if arg == "on" then ns.db.ui.tip[key] = true elseif arg == "off" then ns.db.ui.tip[key] = false
            else ns.db.ui.tip[key] = not ns.db.ui.tip[key] end
            KM.Print(ns, "Tooltip " .. key .. ": " .. (ns.db.ui.tip[key] and "on." or "off."))
        else
            KM.Print(ns, "/sk tip crafts|make|pattern|de|short [on|off]")
        end
    elseif cmd == "house" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        if arg == "neutral" or arg == "faction" then ns.db.house = arg
        elseif arg == "auto" then ns.db.house = nil end
        KM.Print(ns, "Auction house: " .. (ns.db.house and (ns.db.house .. " (set by you; /sk house auto to tell by the zone)")
            or ("told by the zone (here: " .. KM.AuctionHouse() .. ")")) .. ". Neutral = Gadgetzan, Booty Bay, Everlook.")
    elseif cmd == "neutral" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        if arg == "clear" then
            wipe(ns.db.neutral.prices)
            ns.db.neutral.lastScan, ns.db.neutral.lastQuick, ns.db.neutral.lastDeep = nil, nil, nil
            KM.Print(ns, "Neutral auction house prices cleared.")
            ns.Fire("PRICES_UPDATED", "neutral")
        else
            if arg == "on" then ns.db.ui.neutral = true elseif arg == "off" then ns.db.ui.neutral = false
            else ns.db.ui.neutral = not ns.db.ui.neutral end
            KM.Print(ns, "Neutral auction house prices in item tooltips " .. (ns.db.ui.neutral and "on." or "off."))
        end
    elseif cmd == "sources" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        if arg == "on" then ns.db.ui.sources = true elseif arg == "off" then ns.db.ui.sources = false
        else ns.db.ui.sources = not ns.db.ui.sources end
        KM.Print(ns, "Vendor, drops and recipes in item tooltips " .. (ns.db.ui.sources and "on." or "off."))
    elseif cmd == "sync" then
        local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
        local arg2 = (msg or ""):lower():match("^%s*%S+%s+%S+%s+(%S+)")
        if arg == "on" or arg == "off" then
            ns.db.sync.guild = arg == "on"
            KM.Print(ns, "Guild price sharing is " .. arg .. ".")
        elseif arg == "full" then
            if arg2 == "on" then ns.db.sync.full = true elseif arg2 == "off" then ns.db.sync.full = false
            else ns.db.sync.full = not ns.db.sync.full end
            KM.Print(ns, "Sharing full scans (every item, not only Trade Goods) is " .. (ns.db.sync.full and "on." or "off."))
        elseif arg == "loot" then
            if arg2 == "on" then ns.db.sync.loot = true elseif arg2 == "off" then ns.db.sync.loot = false
            else ns.db.sync.loot = not ns.db.sync.loot end
            KM.Print(ns, "Asking the guild for prices of what you loot is " .. (ns.db.sync.loot and "on." or "off."))
        elseif arg == "pull" then
            ns.AskNewest()
            KM.Print(ns, "Asking the guild for a newer scan than yours.")
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
        local wait = ns.FullScanWait and ns.FullScanWait()
        local s = ns.Stamp and ns.Stamp()
        KM.Print(ns, n .. " prices stored. Last full scan: " .. (ns.db.lastDeep and API.PriceAge(ns.db.lastDeep) or "never")
            .. ". Last quick scan: " .. (ns.db.lastQuick and API.PriceAge(ns.db.lastQuick) or "never") .. "."
            .. (wait and (wait == 0 and " Full scan ready." or (" Full scan ready in " .. math.ceil(wait / 60) .. " min.")) or "")
            .. ((s and s.t > 0) and (" Newest scan you hold: " .. (s.by or "?") .. ", " .. API.PriceAge(s.t) .. ".") or ""))
        if API.HasNeutral() then
            local nn = 0
            for _ in pairs(ns.db.neutral.prices) do nn = nn + 1 end
            local nb = ns.db.neutral
            KM.Print(ns, "Neutral auction house: " .. nn .. " prices. Last full scan: " .. (nb.lastDeep and API.PriceAge(nb.lastDeep) or "never")
                .. ". Last quick scan: " .. (nb.lastQuick and API.PriceAge(nb.lastQuick) or "never") .. ".")
        end
    else
        KM.Print(ns, "/sk show   open the Prices page (or /km prices)")
        KM.Print(ns, "/sk scan   Scan (at the auction house): a full scan when the game allows one (every 15 min), else a quick scan")
        KM.Print(ns, "/sk deep   force a full scan, with its progress window (browses every category while the full one is on cooldown)")
        KM.Print(ns, "/sk material   force a quick scan of Trade Goods and watched items only")
        KM.Print(ns, "/sk market   force a quick scan of those plus the professions ticked on Crafting Profits")
        KM.Print(ns, "/sk tooltip [on|off]   prices in item tooltips")
        KM.Print(ns, "/sk sources [on|off]   vendor price, drops and recipes in item tooltips")
        KM.Print(ns, "/sk tip crafts|make|pattern|de|short [on|off]   more tooltip rows; short = details with Shift")
        KM.Print(ns, "/sk status   how many prices you have and how old")
        KM.Print(ns, "/sk neutral [on|off|clear]   neutral auction house prices in tooltips; clear forgets them")
        KM.Print(ns, "/sk house auto|neutral|faction   which auction house you're at (told by the zone unless you set it)")
        KM.Print(ns, "/sk sync [on|off]   share prices with your guild now, or turn sharing on/off")
        KM.Print(ns, "/sk sync pull   ask the guild for a newer scan than yours (done by itself at login)")
        KM.Print(ns, "/sk sync loot [on|off]   ask the guild for prices of what you loot")
        KM.Print(ns, "/sk sync full [on|off]   also pass on every item of a full scan, not only Trade Goods (slower)")
    end
end
