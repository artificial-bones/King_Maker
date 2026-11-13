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

local function withRealm(name)
    local realm = GetRealmName and GetRealmName() or ""
    return realm ~= "" and (name .. "-" .. realm) or name
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
    for _, m in ipairs(KM.order) do
        if m.RenameChar and m.db then KM.Safe(m.RenameChar, old, new) end
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

---------------------------------------------------------------------------
-- Bag buttons (for marks on bag slots: Quest's "safe to delete", Inventory's cheapest stack)
---------------------------------------------------------------------------
-- Works with Bagnon and the game's own bags, and only ever decorates their buttons.

-- The bag and slot a bag button shows. Bagnon's own GetBag (or .bag) first: its buttons are built on the game's
-- bag button template, whose GetBagID reads the parent frame and means something else there.
function KM.ButtonSlot(b)
    local bag
    if b.GetBag then local ok, v = pcall(b.GetBag, b); if ok then bag = v end end
    if type(bag) ~= "number" then bag = rawget(b, "bag") end
    if type(bag) ~= "number" and b.GetBagID then local ok, v = pcall(b.GetBagID, b); if ok then bag = v end end
    if type(bag) ~= "number" and b.GetParent then
        local p = b:GetParent()
        local name = p and p.GetName and p:GetName()
        if name and name:match("^ContainerFrame%d+$") then bag = p:GetID() end
    end
    if type(bag) ~= "number" or not b.GetID then return nil end
    return bag, b:GetID()
end

-- The bag windows: Bagnon's (once it has made it: until then its registry holds a plain table), then the game's.
function KM.BagRoots()
    local out = {}
    if Bagnon and Bagnon.Frames and Bagnon.Frames.Get then
        local ok, f = pcall(Bagnon.Frames.Get, Bagnon.Frames, "inventory")
        if ok and type(f) == "table" and f.GetChildren then out[#out + 1] = f end
    end
    if ContainerFrameCombinedBags then out[#out + 1] = ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then out[#out + 1] = f end
    end
    return out
end

local function walkButtons(f, fn, depth)
    if depth > 6 or not (f and f.GetChildren) then return end
    for _, c in ipairs({ f:GetChildren() }) do
        local bag, slot = KM.ButtonSlot(c)
        if bag then fn(c, bag, slot) else walkButtons(c, fn, depth + 1) end
    end
end

-- fn(button, bag, slot) for every bag button in an open bag window showing your own bags (Bagnon can show
-- another character's: those are skipped). Empty slots too, so a mark can be taken off.
function KM.EachBagButton(fn)
    for _, root in ipairs(KM.BagRoots()) do
        if root.IsShown and root:IsShown() then
            walkButtons(root, function(b, bag, slot)
                local cached = false
                if b.IsCached then local ok, v = pcall(b.IsCached, b); cached = ok and v end
                if not cached then fn(b, bag, slot) end
            end, 0)
        end
    end
end

function KM.BagsOpen()
    for _, root in ipairs(KM.BagRoots()) do
        if root.IsShown and root:IsShown() then return true end
    end
    return false
end

-- Bag windows lay their buttons out again on their own (sorting, searching, Bagnon redrawing): while one is open,
-- every registered marker runs about once a second, and right away when a bag window opens.
local markers = {}
function KM.RegisterBagMarker(fn) markers[#markers + 1] = fn end
function KM.RunBagMarkers() for _, fn in ipairs(markers) do KM.Safe(fn) end end
do
    local ticker, check, since, wasOpen = CreateFrame("Frame"), 0, 0, false
    ticker:SetScript("OnUpdate", function(_, dt)
        check, since = check + dt, since + dt
        if check < 0.25 then return end
        check = 0
        local open = #markers > 0 and KM.BagsOpen()
        if open and (not wasOpen or since >= 1) then since = 0; KM.RunBagMarkers() end
        wasOpen = open
    end)
end
