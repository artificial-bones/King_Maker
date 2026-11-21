local _, KM = ...
local ns = KM.Module("Econ", { title = "Econ King", short = "Econ", legacy = "Econ_King", db = "EconKingDB" })

-- Econ King: the long-term memory of the auction house. Every scan Scanner King
-- runs (Deep Scan, Material Scan, Market Scan) is kept as history, so for any
-- item you can see how its market price and the number listed have moved over
-- days, weeks and months, and spot what's cheap, what's drying up and what's
-- flooding the market.
--
-- Its public face is the global EconKing table:
--   EconKing.GetStats(itemID)   -> the numbers on the item's page (see History.lua), or nil
--   EconKing.GetHistory(itemID) -> { { t, market, lowest, listed, auctions, added, gone, scans }, ... } oldest first
--   EconKing.IsFavorite(itemID)
--   EconKing.SetFavorite(itemID, on) -> true when set (the same stars as the page and the Favorites panel at the AH)
--
-- In King Maker its window is the "history" page (UI.lua: the list, Item.lua: an item's page), opened from
-- Auction House > Price History, the crown's quick actions or /ek. At the auction house the favorites also sit in a
-- panel beside it (Panel.lua): click one to search it there, Graph for its history.

EconKing = { API_VERSION = 1 }
local API = EconKing
ns.API = API

function ns.Now()
    return ScannerKing and ScannerKing.Now and ScannerKing.Now() or (GetServerTime and GetServerTime()) or time()
end

function ns.Money(v)
    if not v then return "|cff808080-|r" end
    local s = ScannerKing and ScannerKing.FormatMoney(math.abs(v)) or tostring(math.floor(math.abs(v)))
    return v < 0 and ("-" .. s) or s
end

-- "+12%" in green or "-8%" in red (or the other way round when down is good).
function ns.Percent(x, downIsGood)
    if not x then return "|cff808080-|r" end
    local pct = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
    local good = (pct > 0) ~= (downIsGood or false)
    local color = pct == 0 and "|cffc0c0c0" or (good and "|cff40ff40" or "|cffff5050")
    return color .. (pct > 0 and "+" or "") .. pct .. "%|r"
end

function ns.Age(t)
    if not t then return "never" end
    return ScannerKing and ScannerKing.PriceAge and ScannerKing.PriceAge(t) or tostring(t)
end

---------------------------------------------------------------------------
-- Item names, quality and icons (the game loads names lazily)
---------------------------------------------------------------------------

-- The saved cache keeps names and quality only, as "quality:name" (the list sorts and searches by name before the
-- game has loaded them); icons come from GetItemInfoInstant, which is instant, so they're kept for the session only.
-- ns.Info hands out { name, q } tables made from those strings.
local icons, infos = {}, {}
function ns.Icon(id)
    if icons[id] == nil then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        icons[id] = inst and select(5, inst(id)) or false
    end
    return icons[id] or nil
end

local function unpackInfo(s)
    local q, name = s:match("^(%d*):(.*)$")
    if not name or name == "" then return {} end
    return { name = name, q = tonumber(q) }
end

-- Schema 1's { name, q, icon } entry into its string (History.lua's conversion calls this).
function ns.PackInfo(id)
    local c = ns.db.info[id]
    if type(c) ~= "table" then return end
    ns.db.info[id] = c.name and ((c.q or "") .. ":" .. c.name) or nil
end

function ns.Info(id)
    local c = infos[id]
    if c and c.name then return c end
    local saved = ns.db.info[id]
    if type(saved) == "string" then c = unpackInfo(saved)
    elseif type(saved) == "table" and saved.name then c = { name = saved.name, q = saved.q } end
    if c and c.name then infos[id] = c; return c end
    local name, quality
    if C_Item and C_Item.GetItemInfo then
        name, _, quality = C_Item.GetItemInfo(id)
    elseif GetItemInfo then
        name, _, quality = GetItemInfo(id)
    end
    if not name then
        -- arrives as GET_ITEM_INFO_RECEIVED; the King Maker window redraws the open page
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return c or {}
    end
    c = { name = name, q = quality }
    infos[id] = c
    ns.db.info[id] = (quality or "") .. ":" .. name
    return c
end

function ns.Name(id) return ns.Info(id).name or ("Item " .. id) end

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80" }
function ns.ColoredName(id)
    local i = ns.Info(id)
    return (QUALITY[i.q or 1] or "|cffffffff") .. (i.name or ("Item " .. id)) .. "|r"
end

---------------------------------------------------------------------------
-- Favorites
---------------------------------------------------------------------------

ns.STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

function API.IsFavorite(id) return ns.db and ns.db.fav[id] == true end

function ns.SetFavorite(id, on)
    ns.db.fav[id] = on and true or nil
    if ns.Refresh then ns.Refresh() end
    if ns.RefreshPanel then ns.RefreshPanel() end
end

-- For other modules: one shared set of stars.
function API.SetFavorite(id, on)
    id = tonumber(id)
    if not (ns.db and id) then return false end
    ns.SetFavorite(id, on)
    return true
end

---------------------------------------------------------------------------
-- Saved data, slash command
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Econ_King data is moved in: safe twice.
function ns.InitDB()
    EconKingDB = EconKingDB or {}
    local db = EconKingDB
    db.items = db.items or {}     -- itemID -> history: one packed string (History.lua)
    db.fav = db.fav or {}         -- itemID -> true
    db.info = db.info or {}       -- itemID -> "quality:name" (ns.Info)
    db.scans = db.scans or {}     -- { { t = time, k = kind, n = items, g = gap }, ... } newest last
    db.listings = db.listings or {} -- the last Deep Scan's listings per item, to see what sold between scans
    db.keep = db.keep or {}       -- days of each level of detail (History.lua, ns.KEEP)
    for k, d in pairs(ns.KEEP) do if db.keep[k] == nil then db.keep[k] = d[1] end end
    if db.v == nil and not next(db.items) then db.v = 2 end -- schema 2: packed strings; older data is converted at login
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    if db.ui.tooltip == nil then db.ui.tooltip = true end
    if db.ui.ahPanel == nil then db.ui.ahPanel = true end -- the Favorites panel beside the auction house (Panel.lua)
    ns.db = db
    wipe(infos)
    if ns.ClearStats then ns.ClearStats() end -- numbers worked out from data that was just replaced
end

-- /ek status and the Settings page: what's kept, how big it is, and the last time it shrank.
function ns.StatusLines()
    local db = ns.db
    local bytes, items, pts = ns.SavedSize(true)
    local keep = ns.Keep()
    local last = db.scans[#db.scans]
    local lines = {
        KM.Commas(items) .. " items tracked, " .. KM.Commas(pts[1] + pts[2] + pts[3] + pts[4]) .. " points ("
            .. KM.Commas(pts[4]) .. " scans, " .. KM.Commas(pts[3]) .. " days, " .. KM.Commas(pts[2] + pts[1]) .. " weeks), about "
            .. ns.FormatBytes(bytes) .. " saved.",
        "Kept: every scan for " .. keep.raw .. " days, a point a day to " .. keep.day .. " days, then a point a week ("
            .. "one per 4 weeks after a year). " .. (keep.forget > 0 and ("Items not seen for " .. keep.forget .. " days are forgotten.")
            or "Items are never forgotten."),
        #db.scans .. " scans recorded. Last scan: " .. (last and ns.Age(last.t) or "never") .. ". Last Deep Scan: " .. ns.Age(db.lastDeep) .. ".",
    }
    local running, mig = ns.Migrating()
    if mig and mig.total then
        lines[#lines + 1] = "Converting to the compact format: " .. KM.Commas(mig.done) .. " of " .. KM.Commas(mig.total) .. " items"
            .. (running and "" or " (carries on at login)") .. "."
    end
    local log = db.sizeLog
    if log and log.before and log.after then
        lines[#lines + 1] = (log.what == "convert" and "Converted " or "Last compacted ") .. ns.Age(log.t) .. ": about "
            .. ns.FormatBytes(log.before) .. " -> " .. ns.FormatBytes(log.after)
            .. ((log.forgot or 0) > 0 and (", " .. KM.Commas(log.forgot) .. " items forgotten") or "") .. "."
    end
    return lines
end

local function itemFrom(text)
    return tonumber((text or ""):match("item:(%d+)")) or tonumber((text or ""):match("^%s*(%d+)%s*$"))
end

SLASH_ECONKING1 = "/ek"
SLASH_ECONKING2 = "/econking"
SlashCmdList.ECONKING = function(msg)
    if not ns.db then return end
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "fav" or cmd == "favorite" then
        local id = itemFrom(rest)
        if not id then return KM.Print(ns, "/ek fav [item link or ID]   add or remove a favorite") end
        ns.SetFavorite(id, not API.IsFavorite(id))
        KM.Print(ns, ns.Name(id) .. (API.IsFavorite(id) and " added to favorites." or " removed from favorites."))
    elseif cmd == "item" then
        local id = itemFrom(rest)
        if id then ns.Toggle(true); ns.ShowItem(id) end
    elseif cmd == "tooltip" then
        ns.db.ui.tooltip = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.tooltip)
        KM.Print(ns, "Price history lines in item tooltips " .. (ns.db.ui.tooltip and "on." or "off."))
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "status" then
        for _, line in ipairs(ns.StatusLines()) do KM.Print(ns, line) end
    elseif cmd == "compact" then
        ns.CompactNow()
    elseif cmd == "panel" then
        ns.TogglePanel()
    else
        KM.Print(ns, "/ek   open the Price History page (or /km history)")
        KM.Print(ns, "/ek item [link]   open an item's page")
        KM.Print(ns, "/ek fav [link]   add or remove a favorite")
        KM.Print(ns, "/ek panel   show or hide the Favorites panel at the auction house")
        KM.Print(ns, "/ek status   how much history you have and how much space it takes")
        KM.Print(ns, "/ek compact   roll up old history and forget long-gone items now")
        KM.Print(ns, "/ek tooltip [on|off]   averages and trend in item tooltips")
    end
end
