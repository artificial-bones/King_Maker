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

-- The daily reset (Supply Writs, Reals): 10:00 in New York, so 15:00 UTC in winter and 14:00 UTC under US daylight
-- saving (2 a.m. on the second Sunday of March to 2 a.m. on the first Sunday of November). Worked out from the
-- server's clock, not asked of the game: GetQuestResetTime doesn't match when Forever's dailies reset.
KM.RESET_HOUR = 10
local DAY = 86400

local function daysFromCivil(y, m, d) -- days since 1970-01-01 (Howard Hinnant's algorithm)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function yearOf(t) -- the UTC year of epoch seconds t
    local z = math.floor(t / DAY) + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    return yoe + era * 400 + ((mp >= 10) and 1 or 0)
end

local function nthSunday(y, m, n) -- day number of the nth Sunday of a month
    local first = daysFromCivil(y, m, 1)
    local wd = (first + 4) % 7 -- 0 = Sunday (day 0, 1970-01-01, was a Thursday)
    return first + (7 - wd) % 7 + 7 * (n - 1)
end

-- Hours New York is behind UTC at epoch seconds t: 4 under daylight saving, else 5.
function KM.EasternOffset(t)
    local y = yearOf(t)
    local from = nthSunday(y, 3, 2) * DAY + 7 * 3600  -- 2 a.m. EST
    local to = nthSunday(y, 11, 1) * DAY + 6 * 3600   -- 2 a.m. EDT
    return (t >= from and t < to) and 4 or 5
end

-- Server time of the next daily reset after now (default: the server's clock).
function KM.NextDailyReset(now)
    now = now or KM.Now()
    local off = KM.EasternOffset(now)
    local localNow = now - off * 3600
    local at = math.floor(localNow / DAY) * DAY + KM.RESET_HOUR * 3600
    if at <= localNow then at = at + DAY end
    local t = at + KM.EasternOffset(at + off * 3600) * 3600 -- the offset on the reset's own day
    if t <= now then t = t + DAY end
    return t
end

function KM.SecondsToDailyReset(now)
    now = now or KM.Now()
    return KM.NextDailyReset(now) - now
end

-----
-- Your character's name
-----
-- Forever characters have a first and a last name ("Slum Bum"), and that full name is what chat, mail, invoices and
-- guild addon messages use. UnitName("player") returns them separately: the second value is the surname, not a
-- realm. Every module keys per-character data by KM.Char(), "First Last-Realm"; before 2.3.0 that was "First-Realm",
-- and KM.RenameChar moves this character's old entries over (Boot.lua, at load and at login).

-- "Slum Bum" (just the first name when there is no surname, or before the game knows it).
function KM.PlayerName()
    local first, last = UnitName("player")
    first = first or "?"
    if type(last) == "string" and last ~= "" then return first .. " " .. last end
    return first
end

-- The realm's name. Since the November 2026 hotfix (realm IDs hidden to stop layer-hopping addons) GetRealmName can
-- come back empty, so the last one the game told us is kept in KingMakerDB.realm. With none saved yet (the hotfix
-- landed before this was kept), it's read back from this character's own saved keys ("First Last-Realm") in the
-- modules. nil when nothing knows it (a brand-new install after the hotfix): keys then have no realm part.
local function savedRealm()
    if type(KingMakerDB) ~= "table" then return nil end
    if type(KingMakerDB.realm) == "string" and KingMakerDB.realm ~= "" then return KingMakerDB.realm end
    local me = KM.PlayerName() .. "-"
    for _, m in ipairs(KM.order or {}) do
        local chars = type(m.db) == "table" and m.db.chars
        if type(chars) == "table" then
            for k in pairs(chars) do
                if type(k) == "string" and k:sub(1, #me) == me and #k > #me then
                    KingMakerDB.realm = k:sub(#me + 1)
                    return KingMakerDB.realm
                end
            end
        end
    end
end

function KM.Realm()
    local live = GetRealmName and GetRealmName()
    if type(live) == "string" and live ~= "" then
        if type(KingMakerDB) == "table" then KingMakerDB.realm = live end
        return live
    end
    return savedRealm()
end

local function withRealm(name)
    local realm = KM.Realm()
    return realm and (name .. "-" .. realm) or name
end

-- This character as "First Last-Realm".
function KM.Char() return withRealm(KM.PlayerName()) end

-- The key before 2.3.0: "First-Realm".
function KM.OldChar() return withRealm((UnitName("player")) or "?") end

-- Is this name (from chat, an addon message, an invoice; realm or not) the character you're on?
function KM.IsMe(name)
    if type(name) ~= "string" then return false end
    name = name:gsub("%-.*$", "")
    return name:lower() == KM.PlayerName():lower()
end

-- Fills what dst lacks from src, at every depth (dst's own values win).
local function fill(dst, src, depth)
    for k, v in pairs(src) do
        local d = dst[k]
        if d == nil then dst[k] = v
        elseif depth < 6 and type(d) == "table" and type(v) == "table" then fill(d, v, depth + 1) end
    end
end

-- t[old] -> t[new]. When both exist (data saved under the new key already), what only the old entry has is kept.
function KM.MoveKey(t, old, new)
    if type(t) ~= "table" or old == new or t[old] == nil then return end
    local o, n = t[old], t[new]
    if n == nil then
        t[new] = o
    elseif type(o) == "table" and type(n) == "table" then
        fill(n, o, 0)
    end
    t[old] = nil
end

-- Moves this character's data from its old first-name key to its full name, in every module that has a RenameChar.
function KM.RenameChar()
    local first, last = UnitName("player")
    if not first or first == "Unknown" or type(last) ~= "string" or last == "" then return end
    local old, new = KM.OldChar(), KM.Char()
    -- Saved while the realm came back empty (the November 2026 hotfix): "First Last" and "First Last-".
    local bare = KM.PlayerName()
    local strays = KM.Realm() and { bare, bare .. "-" } or {}
    for _, m in ipairs(KM.order) do
        if m.RenameChar and m.db then
            KM.Safe(m.RenameChar, old, new)
            for _, s in ipairs(strays) do
                if s ~= new then KM.Safe(m.RenameChar, s, new) end
            end
        end
    end
end

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

-- Compact money for tables and tiles (tooltips use the exact KM.Money):
--   nil -> grey dash; >= 1000g -> "1,234g"; >= 1g -> "3g 45s" (rounded to the silver, "0s" left out);
--   >= 1s -> "45s 9c"; less -> "9c"; negative -> a leading minus. plain = no coin colours.
local COIN = { g = "|cffffd700g|r", s = "|cffc7c7cfs|r", c = "|cffeda55fc|r" }
function KM.MoneyShort(c, plain)
    if c == nil then return plain and "-" or "|cff808080-|r" end
    c = math.floor(c + 0.5)
    local neg = c < 0
    if neg then c = -c end
    local function u(k) return plain and k or COIN[k] end
    local out
    if c >= 10000 then
        local silver = math.floor(c / 100 + 0.5)
        local g, sv = math.floor(silver / 100), silver % 100
        if g >= 1000 then out = KM.Commas(math.floor(c / 10000)) .. u("g")
        else out = g .. u("g") .. (sv > 0 and (" " .. sv .. u("s")) or "") end
    elseif c >= 100 then
        local sv, k = math.floor(c / 100), c % 100
        out = sv .. u("s") .. (k > 0 and (" " .. k .. u("c")) or "")
    else
        out = c .. u("c")
    end
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

