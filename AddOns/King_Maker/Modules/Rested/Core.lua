local _, KM = ...
local ns = KM.Module("Rested", { title = "Rested King", short = "Rested", legacy = "Rested_King", db = "RestedKingDB" })

-- Rested King: every character's rested XP on one page of the King Maker window (Characters > Rested XP).
--
-- Log in on a character once and Rested King notes its level, XP, rested XP,
-- and whether it's resting (in an inn or a city). From then on it works out
-- how much rest each character has built up since you logged it out, using
-- the game's own rules:
--
--   * In an inn or a city: 5% of the character's current level every 8 hours.
--   * Logged out anywhere else: a quarter of that (5% every 32 hours).
--   * It stops at 150% of the current level (30 "bubbles" on the XP bar).
--   * The Well Rested legacy perk adds 4% per rank to both the rate and the cap.
--
-- Rest is counted in XP for the level you logged out at, so it's exact until
-- you play the character again, and every login replaces the estimate with
-- the real number from the game.
--
-- Files:
--   Core.lua   saved data, the rested XP sums, events, slash command
--   UI.lua     the Rested XP page, the crown's quick action and tooltip lines, the Home tile, Settings

RestedKing = { API_VERSION = 1 }
local API = RestedKing
ns.API = API

ns.HOURS_PER_STEP = 8   -- hours for one step of rest in an inn or city
ns.STEP = 0.05          -- one step: 5% of the level
ns.OUTSIDE = 0.25       -- logged out outside an inn or city: a quarter of the rate
ns.CAP = 1.5            -- most rest you can have: 150% of the level
ns.PERK = 0.04          -- Well Rested: +4% rate and cap per rank
ns.PERK_RANKS = 5
ns.MAX_LEVEL = 60

function ns.Now() return (GetServerTime and GetServerTime()) or time() end

-- The character this is, as "Name-Realm".
function ns.Char()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    return realm ~= "" and (name .. "-" .. realm) or name
end

function ns.MaxLevel()
    local m = GetMaxPlayerLevel and GetMaxPlayerLevel()
    return (m and m > 0) and m or ns.MAX_LEVEL
end

---------------------------------------------------------------------------
-- The sums
---------------------------------------------------------------------------

local function perkMult(c) return 1 + ns.PERK * (c.perk or 0) end

-- Rest gained per second for a character, in XP.
function ns.Rate(c)
    if not c.xpMax or c.xpMax <= 0 then return 0 end
    local r = c.xpMax * ns.STEP / (ns.HOURS_PER_STEP * 3600) * perkMult(c)
    if not c.resting then r = r * ns.OUTSIDE end
    return r
end

-- The most rest a character can hold, in XP.
function ns.Cap(c)
    if not c.xpMax or c.xpMax <= 0 then return 0 end
    return math.floor(c.xpMax * ns.CAP * perkMult(c))
end

function ns.IsMax(c) return (c.level or 0) >= (c.maxLevel or ns.MaxLevel()) or not c.xpMax or c.xpMax <= 0 end

-- How a character's rest stands right now:
-- { rested, cap, pct (of a level), bubbles, full (true when capped),
--   fullIn (seconds until capped), toLevel (XP left this level), estimated }
function ns.Estimate(c, now)
    now = now or ns.Now()
    if ns.IsMax(c) then return { max = true } end
    local cap = ns.Cap(c)
    local rested = c.rested or 0
    local estimated = false
    if not c.online then
        local elapsed = math.max(0, now - (c.t or now))
        rested = rested + elapsed * ns.Rate(c)
        estimated = elapsed > 0
    end
    rested = math.floor(math.min(rested, cap))
    local rate = ns.Rate(c)
    local full = rested >= cap
    local fullIn
    if full then
        -- when it filled up (the rest gained after that was wasted)
        local filledAt = c.online and nil or (c.t + math.max(0, (cap - (c.rested or 0))) / math.max(rate, 1e-9))
        return { rested = rested, cap = cap, pct = rested / c.xpMax, bubbles = rested / c.xpMax * 20,
                 full = true, fullSince = filledAt, toLevel = c.xpMax - (c.xp or 0), estimated = estimated }
    end
    if rate > 0 then fullIn = (cap - rested) / rate end
    return { rested = rested, cap = cap, pct = rested / c.xpMax, bubbles = rested / c.xpMax * 20,
             full = false, fullIn = fullIn, toLevel = c.xpMax - (c.xp or 0), estimated = estimated }
end

-- "3d 4h", "5h 12m", "40m"
function ns.Duration(s)
    if not s then return "-" end
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
    if d > 0 then return d .. "d " .. h .. "h" end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

-- 1234567 -> "1,234,567"
function ns.Num(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

---------------------------------------------------------------------------
-- Reading the character you're on
---------------------------------------------------------------------------

function ns.Snapshot(loggingOut)
    if not ns.db then return end
    local key = ns.Char()
    local c = ns.db.chars[key] or {}
    ns.db.chars[key] = c
    local name, realm = key:match("^(.-)%-(.+)$")
    c.name = name or key
    c.realm = realm or ""
    local _, class = UnitClass("player")
    c.class = class or c.class
    c.level = UnitLevel("player") or c.level
    c.maxLevel = ns.MaxLevel()
    c.xp = (UnitXP and UnitXP("player")) or 0
    c.xpMax = (UnitXPMax and UnitXPMax("player")) or 0
    c.rested = (GetXPExhaustion and GetXPExhaustion()) or 0
    c.resting = IsResting and IsResting() and true or false
    c.zone = (GetRealZoneText and GetRealZoneText()) or c.zone
    c.t = ns.Now()
    c.online = not loggingOut
    if ns.Refresh then ns.Refresh() end
end

-- Characters, sorted for the window.
function ns.Characters(sortKey, desc, showMax)
    local now = ns.Now()
    local out = {}
    for key, c in pairs(ns.db.chars) do
        if showMax or not ns.IsMax(c) then
            table.insert(out, { key = key, c = c, e = ns.Estimate(c, now) })
        end
    end
    local function val(r)
        if sortKey == "name" then return r.c.name:lower() end
        if sortKey == "level" then return (r.c.level or 0) + (r.c.xpMax and r.c.xpMax > 0 and (r.c.xp or 0) / r.c.xpMax or 0) end
        if sortKey == "full" then
            if r.e.max then return math.huge end
            if r.e.full then return -(now - (r.e.fullSince or now)) end -- wasting longest first
            return r.e.fullIn or math.huge
        end
        if sortKey == "seen" then return r.c.t or 0 end
        return r.e.max and -1 or r.e.pct -- "rested"
    end
    table.sort(out, function(a, b)
        local va, vb = val(a), val(b)
        if va == vb then return a.key < b.key end
        if desc then return va > vb end
        return va < vb
    end)
    return out
end

function ns.Forget(key)
    if ns.db.chars[key] then
        ns.db.chars[key] = nil
        KM.Print(ns, "forgot " .. key .. ".")
        if ns.Refresh then ns.Refresh() end
    end
end

function ns.SetPerk(key, rank)
    local c = ns.db.chars[key]
    if not c then return end
    -- When the character is offline, bank the rest built so far at the old
    -- rate before changing it.
    if not c.online then
        local e = ns.Estimate(c)
        if not e.max then c.rested, c.t = e.rested, ns.Now() end
    end
    c.perk = math.max(0, math.min(ns.PERK_RANKS, rank))
    if ns.Refresh then ns.Refresh() end
end

-- For other addons: a character's rest as estimated now.
function API.Get(key) local c = ns.db and ns.db.chars[key or ns.Char()]; return c and ns.Estimate(c) end

---------------------------------------------------------------------------
-- Saved data, events, slash command
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Rested_King data is moved in: safe twice.
function ns.InitDB()
    RestedKingDB = RestedKingDB or {}
    local db = RestedKingDB
    db.chars = db.chars or {} -- "Name-Realm" -> { name, realm, class, level, xp, xpMax, rested, resting, zone, t, perk }
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    db.ui.sort = db.ui.sort or "rested"
    if db.ui.desc == nil then db.ui.desc = true end
    -- Nobody is online until they log in (a crash skips PLAYER_LOGOUT).
    for _, c in pairs(db.chars) do c.online = nil end
    ns.db = db
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGOUT" then
        ns.Snapshot(true)
    elseif event == "PLAYER_LEVEL_UP" then
        -- the new level's numbers aren't in yet
        C_Timer.After(1, function() ns.Snapshot() end)
    else
        ns.Snapshot()
    end
end)

SLASH_RESTEDKING1 = "/rk"
SLASH_RESTEDKING2 = "/restedking"
SlashCmdList.RESTEDKING = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "perk" and tonumber(rest) then
        if not ns.db.chars[ns.Char()] then ns.Snapshot() end
        ns.SetPerk(ns.Char(), tonumber(rest))
        KM.Print(ns, "Well Rested rank " .. (ns.db.chars[ns.Char()].perk or 0) .. " on " .. ns.Char() .. ".")
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "forget" and rest ~= "" then
        local found
        for key in pairs(ns.db.chars) do
            if key:lower() == rest:lower() or key:lower():match("^" .. rest:lower():gsub("%p", "%%%0") .. "%-") then found = key end
        end
        if found then ns.Forget(found) else KM.Print(ns, "no character called " .. rest .. ".") end
    else
        KM.Print(ns, "/rk   open the Rested XP page (or /km rested)")
        KM.Print(ns, "/rk perk 0-5   your Well Rested legacy perk rank on this character")
        KM.Print(ns, "/rk forget Name   stop tracking a character (or right-click it on the page)")
    end
end
