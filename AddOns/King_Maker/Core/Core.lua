local addonName, KM = ...

-- King Maker 2.0: every King addon in one. This file is the module system every other file leans on.
--
-- A module is one of the old King addons (Scanner, Econ, Market, ...). It keeps its own private namespace, its own
-- saved variable (ScannerKingDB, ...) and its own public global (ScannerKing, ...), so other addons and the King
-- Dashboard see the same data as before. What it gives up is its own window, minimap button and settings panel:
-- it registers pages, quick actions and settings with the shell instead (Shell.lua, Settings.lua).
--
--   local _, KM = ...
--   local ns = KM.Module("Scanner", { title = "Scanner King", legacy = "Scanner_King", db = "ScannerKingDB" })
--   function ns.InitDB() ... end    -- (re)initialise ns.db from _G.ScannerKingDB; must be safe to run twice
--
-- Boot.lua calls every module's InitDB in .toc order when King Maker's saved variables have loaded, and again for
-- one module after its old data has been moved in from a legacy folder (Migrate.lua).

KM.name = addonName
KM.mods, KM.order = {}, {}

local function meta(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addonName, field)
    return ok and v or nil
end
KM.version = meta("Version") or "2"

-- The public API: functions only, never saved data (house style).
KingMaker = KingMaker or {}
KingMaker.API_VERSION = 2
KingMaker.version = KM.version
KM.API = KingMaker

-- Returns the module's private namespace, creating it on first use. Every file of a module calls this with the
-- same key; the first call should pass info.
function KM.Module(key, info)
    local m = KM.mods[key]
    if not m then
        m = { KM = KM, key = key, info = {} }
        KM.mods[key] = m
        table.insert(KM.order, m)
    end
    if info then for k, v in pairs(info) do m.info[k] = v end end
    return m
end

function KM.Each(fn)
    for _, m in ipairs(KM.order) do fn(m) end
end

-----
-- Chat
-----

KM.COLOR = "f0c44d"

-- KM.Print(text) or KM.Print(module, text): "King Maker: text" / "King Maker Scanner: text".
function KM.Print(a, b)
    local label, text = "King Maker", a
    if type(a) == "table" then
        label = "King Maker |cffb8b2a6" .. ((a.info and a.info.short) or a.key or "") .. "|r"
        text = b
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff" .. KM.COLOR .. label .. ":|r " .. tostring(text))
end

-----
-- Shared helpers (one copy for every module)
-----

function KM.Now() return (GetServerTime and GetServerTime()) or time() end

-- 12345 -> "1g 23s 45c" with coin colours; nil -> grey dash. Negative amounts get a red minus.
function KM.Money(c, plain)
    if c == nil then return "|cff808080-|r" end
    c = math.floor(c + 0.5)
    local neg = c < 0
    if neg then c = -c end
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if plain then
        if g > 0 then parts[#parts + 1] = g .. "g" end
        if s > 0 then parts[#parts + 1] = s .. "s" end
        if k > 0 or #parts == 0 then parts[#parts + 1] = k .. "c" end
    else
        if g > 0 then parts[#parts + 1] = KM.Commas(g) .. "|cffffd700g|r" end
        if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
        if k > 0 or #parts == 0 then parts[#parts + 1] = k .. "|cffeda55fc|r" end
    end
    local out = table.concat(parts, " ")
    if neg then out = (plain and "-" or "|cffff5050-|r") .. out end
    return out
end

function KM.Commas(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

-- Seconds ago -> "now", "5m", "3h", "2d".
function KM.Ago(t)
    if not t then return "never" end
    local d = KM.Now() - t
    if d < 60 then return "now" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    return math.floor(d / 86400) .. "d"
end

function KM.ItemID(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)")) or tonumber(link)
end

-- Registers events on f behind the Forever guard (unknown events error on this client).
function KM.Register(f, ...)
    for i = 1, select("#", ...) do
        local e = select(i, ...)
        if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
            pcall(f.RegisterEvent, f, e)
        end
    end
end

-- Runs fn and reports an error once instead of breaking the caller (calls across modules go through this).
function KM.Safe(fn, ...)
    if not fn then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    if not KM.errorShown then
        KM.errorShown = true
        KM.Print("|cffff6060error:|r " .. tostring(a))
    end
end
