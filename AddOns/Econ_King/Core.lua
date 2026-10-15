local _, ns = ...

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

EconKing = { API_VERSION = 1 }
local API = EconKing
ns.API = API

local PREFIX = "|cff7fd36bEcon King|r: "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

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

local waiting = false

function ns.Info(id)
    local c = ns.db.info[id]
    if c and c.name then return c end
    c = c or {}
    local name, quality, icon
    if C_Item and C_Item.GetItemInfo then
        name, _, quality = C_Item.GetItemInfo(id)
    elseif GetItemInfo then
        name, _, quality = GetItemInfo(id)
    end
    if not c.icon then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if inst then c.icon = select(5, inst(id)) end
    end
    if name then
        c.name, c.q = name, quality
    else
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        waiting = true
    end
    ns.db.info[id] = c
    return c
end

function ns.Name(id) return ns.Info(id).name or ("Item " .. id) end

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80" }
function ns.ColoredName(id)
    local i = ns.Info(id)
    return (QUALITY[i.q or 1] or "|cffffffff") .. (i.name or ("Item " .. id)) .. "|r"
end

function ns.TakeWaiting()
    local w = waiting
    waiting = false
    return w
end

---------------------------------------------------------------------------
-- Favorites
---------------------------------------------------------------------------

function API.IsFavorite(id) return ns.db and ns.db.fav[id] == true end

function ns.SetFavorite(id, on)
    ns.db.fav[id] = on and true or nil
    if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Saved data, slash command
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= "Econ_King" then return end
    EconKingDB = EconKingDB or {}
    local db = EconKingDB
    db.items = db.items or {}     -- itemID -> history (History.lua)
    db.fav = db.fav or {}         -- itemID -> true
    db.info = db.info or {}       -- itemID -> { name, q = quality, icon }
    db.scans = db.scans or {}     -- { { t = time, k = kind, n = items }, ... } newest last
    db.listings = db.listings or {} -- the last Deep Scan's listings per item, to see what sold between scans
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
    if db.ui.tooltip == nil then db.ui.tooltip = true end
    ns.db = db
end)

local function itemFrom(text)
    return tonumber((text or ""):match("item:(%d+)")) or tonumber((text or ""):match("^%s*(%d+)%s*$"))
end

SLASH_ECONKING1 = "/ek"
SLASH_ECONKING2 = "/econking"
SlashCmdList.ECONKING = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "fav" or cmd == "favorite" then
        local id = itemFrom(rest)
        if not id then return ns.Print("/ek fav [item link or ID]   add or remove a favorite") end
        ns.SetFavorite(id, not API.IsFavorite(id))
        ns.Print(ns.Name(id) .. (API.IsFavorite(id) and " added to favorites." or " removed from favorites."))
    elseif cmd == "item" then
        local id = itemFrom(rest)
        if id then ns.Toggle(true); ns.ShowItem(id) end
    elseif cmd == "tooltip" then
        ns.db.ui.tooltip = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.tooltip)
        ns.Print("Econ King tooltip lines " .. (ns.db.ui.tooltip and "on." or "off."))
    elseif cmd == "button" then
        ns.db.ui.button = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.button)
        ns.UpdateMinimapButton()
    elseif cmd == "status" then
        local items, points = 0, 0
        for _, it in pairs(ns.db.items) do
            items = items + 1
            points = points + #(it.r or {}) + #(it.d or {}) + #(it.w or {})
        end
        local last = ns.db.scans[#ns.db.scans]
        ns.Print(items .. " items tracked, " .. points .. " data points, " .. #ns.db.scans .. " scans recorded. Last scan: "
            .. (last and ns.Age(last.t) or "never") .. ". Last Deep Scan: " .. ns.Age(ns.db.lastDeep) .. ".")
    else
        ns.Print("/ek   open Econ King (or click the minimap button)")
        ns.Print("/ek item [link]   open an item's page")
        ns.Print("/ek fav [link]   add or remove a favorite")
        ns.Print("/ek status   how much history you have")
        ns.Print("/ek tooltip [on|off]   averages and trend in item tooltips")
        ns.Print("/ek button [on|off]   minimap button")
    end
end
