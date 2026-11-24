local _, KM = ...
local ns = KM.Module("Tracker", { title = "Farm Tracker", short = "Tracker", db = "TrackerKingDB" })

-- Farm Tracker (King Maker 2.6): one floating tracker for all mob farming and all gathering, and the Farming Ledger
-- page in the King Maker window. Every time you start and stop, the session is saved, and you can open it later and
-- see what it made. It replaces Farm's "Farm tracker" box and Gather's "Farming ledger" box.
--
--   Core.lua      this file: TrackerKingDB, the move from the two old boxes, /farm, the TrackerKing API, key bindings
--   Session.lua   the engine: idle / running / paused, the active-time clock, idle and AFK, crediting, saving
--   Sources.lua   turns loot windows (Core\Loot.lua) and money changes into credits
--   HUD.lua       the floating Farm Tracker (UI.HUD "KingMakerFarmTracker"): All, Mobs, Gathering, Prices
--   Page.lua      the Farming Ledger page (Sessions), quick actions, Home tile, crown tooltip, settings
--   Detail.lua    one saved session: tiles, charts, Items / Mobs / Gathering / Money
--   Trends.lua    the ledger's Trends tab and its export (2.6.2)
--
-- Saved data: TrackerKingDB (account-wide, version 1): live[char] = the session in progress per character,
-- sessions = finished ones (each tagged with its character), settings, ui. See the King Dashboard
-- contract.

TrackerKing = { API_VERSION = 1 }   -- functions only, never saved data (house style)
local API = TrackerKing
ns.API = API

local DEFAULTS = {
    settings = {
        startActions = 3, idlePause = 300, idleStop = 1200, offlineStop = 7200, minKeep = 120,
        keep = 200, detailDays = 45,
    },
    -- booleans, defaulted with `if s.x == nil then s.x = v end`
    flags = { autoStart = true, autoResume = true, countQuest = false, countDE = false, countShares = true, hudOnStart = true },
    ui = { hudTab = "all", priceTab = "mine", hudScale = 1, tab = "sessions", period = 30 },
    uiFlags = { hud = false, hudCollapsed = false, mine = false, revalue = false },
}

function ns.Settings() return ns.db.settings end

-- Runs when King Maker's saved variables load (after Farm's and Gather's InitDB: TOC order): safe twice.
function ns.InitDB()
    TrackerKingDB = TrackerKingDB or {}
    local db = TrackerKingDB
    db.version = 1
    db.nextId = db.nextId or 1
    db.settings = db.settings or {}
    db.ui = db.ui or {}
    db.live = db.live or {}
    db.sessions = db.sessions or {}
    db.migrated = db.migrated or {}
    -- 2.8.0's guild bests are gone (farms are your own): drop guildmates' bests and the settings that shared yours
    db.guild = nil
    for _, k in ipairs({ "guildDays", "guildShare", "guildShow" }) do db.settings[k] = nil end
    db.ui.guildAct, db.ui.guildNear = nil, nil
    if db.ui.tab == "guild" then db.ui.tab = "sessions" end
    for k, v in pairs(DEFAULTS.settings) do if db.settings[k] == nil then db.settings[k] = v end end
    for k, v in pairs(DEFAULTS.flags) do if db.settings[k] == nil then db.settings[k] = v end end
    for k, v in pairs(DEFAULTS.ui) do if db.ui[k] == nil then db.ui[k] = v end end
    for k, v in pairs(DEFAULTS.uiFlags) do if db.ui[k] == nil then db.ui[k] = v end end
    ns.db = db
    if ns.Prune then ns.Prune() end
    KM.Safe(ns.Migrate)
end

function ns.RenameChar(old, new)
    for _, s in ipairs(ns.db.sessions) do if s.c == old then s.c = new end end
    KM.MoveKey(ns.db.live, old, new)
    if ns.db.live[new] then ns.db.live[new].c = new end
end

---------------------------------------------------------------------------
-- The move from the two old boxes
---------------------------------------------------------------------------

-- King Maker 2.6: the farm tracker (FarmKingDB.session) and the farming ledger (GatherKingDB.ledger) were two
-- tallies with two timers. What they held becomes one saved "Carried over" session; their two boxes become the one
-- Farm Tracker. Runs from InitDB and again at PLAYER_LOGIN (a 1.x Farm_King / gather_king stub moves its old data in
-- after King Maker's ADDON_LOADED). It only acts when the old keys hold something.

local function gatherKind(id)
    local G = KM.mods.Gather
    if G then
        local key = G.ITEM_TO_KEY and G.ITEM_TO_KEY[id]
        local known = key and G.KNOWN and G.KNOWN[key]
        local t = known and known[1] or (G.BONUS_TYPE and G.BONUS_TYPE[id])
        if t == "mine" or t == "herb" or t == "fish" then return t end
    end
    return "chest"
end

function ns.Migrate()
    local db = ns.db
    if not db then return end
    local F, G = FarmKingDB, GatherKingDB
    local fs = F and F.session
    local gl = G and G.ledger
    local hasF = type(fs) == "table" and ((fs.coin or 0) > 0 or next(fs.items or {}) ~= nil or next(fs.mobs or {}) ~= nil)
    local hasG = type(gl) == "table" and next(gl.items or {}) ~= nil
    local did = false
    if hasF or hasG then
        local s = ns.NewSession(KM.Char(), KM.Now())
        s.legacy, s.auto, s.name = true, nil, "Carried over from the old trackers"
        if hasF then
            for npc, m in pairs(fs.mobs or {}) do
                npc = tonumber(npc) or 0
                if (m.k or 0) > 0 then ns.AddKills(s, npc, m.k) end
                for item, q in pairs(m.i or {}) do ns.AddItem(s, "mob", npc, item, q, KM.ItemValue(item)) end
                if (m.c or 0) > 0 then ns.AddCoin(s, "mob", npc, m.c) end
                if s.src.mob then s.src.mob.n = (s.src.mob.n or 0) + (m.k or 0) end
            end
            -- coin looted but not tied to a mob row
            local tied = s.src.mob and s.src.mob.c or 0
            if (fs.coin or 0) > tied then ns.AddCoin(s, "mob", 0, fs.coin - tied) end
        end
        if hasG then
            for item, q in pairs(gl.items or {}) do ns.AddItem(s, gatherKind(item), 0, item, q, KM.ItemValue(item)) end
        end
        local ft = hasF and fs.timer or nil
        local gt = hasG and gl.timer or nil
        s.act = math.floor(math.max(ft and (ft.last or ft.elapsed) or 0, gt and gt.elapsed or 0))
        s.t1 = KM.Now()
        s.t0 = s.t1 - s.act
        s.tl = nil
        ns.SaveRecord(s)
        did = true
    end
    -- the box: shown if either old box was on, at the position of the one that was showing
    local fu, gu = (F and F.ui) or {}, (G and G.ui) or {}
    if fu.mini ~= nil or fu.miniPos or gu.ledger ~= nil or gu.ledgerPos then
        local u = db.ui
        local function pos(p) if type(p) == "table" and p[1] then return { point = p[1], x = p[3], y = p[4] } end end
        if fu.mini then u.hudPos, u.hudCollapsed = pos(fu.miniPos), fu.miniCollapsed and true or false
        elseif gu.ledger then u.hudPos, u.hudCollapsed = pos(gu.ledgerPos), gu.ledgerCollapsed and true or false end
        u.hud = (fu.mini == true) or (gu.ledger == true)
        u.priceTab = gu.priceTab or u.priceTab
        did = true
    end
    if F then F.session = nil; if F.ui then F.ui.mini, F.ui.miniPos, F.ui.miniCollapsed = nil, nil, nil end end
    if G then
        G.ledger = nil
        if G.ui then G.ui.ledger, G.ui.ledgerPos, G.ui.ledgerCollapsed, G.ui.ledgerTab, G.ui.priceTab = nil, nil, nil, nil, nil end
    end
    if did then
        db.migrated.farm = db.migrated.farm or KM.Now()
        db.migrated.gather = db.migrated.gather or KM.Now()
        ns.migratedNow = true
        if ns.loggedIn and ns.UpdateHUD then ns.UpdateHUD() end
    end
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

function ns.Money(c) return KM.Money(c) end

-- 3733 -> "1:02:13"
function ns.Clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

-- 24180 -> "6h 43m"; under an hour "43m"
function ns.Dur(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

-- Gold per hour as text, or an em-dash-like "-" before a minute of active time.
function ns.GphText(gph)
    if not gph then return "|cff808080-|r" end
    return KM.Money(gph) .. "/hr"
end

function ns.ZoneName(map)
    if not map then return "Unknown zone" end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or ("Zone " .. map)
end

---------------------------------------------------------------------------
-- The TrackerKing API (copies only: mutating what it returns never touches saved data)
---------------------------------------------------------------------------

local callbacks = {}
function API.RegisterCallback(owner, fn) callbacks[owner] = fn end
function API.UnregisterCallback(owner) callbacks[owner] = nil end
function ns.Fire(event, ...)
    for _, fn in pairs(callbacks) do pcall(fn, event, ...) end
end

local function summary(s)
    if not s then return nil end
    local t = ns.Totals(s)
    return { id = s.id, c = s.c, t0 = s.t0, t1 = s.t1, act = math.floor(ns.Active(s)), value = t.value, coin = s.coin,
        gph = t.gph, kills = s.kills, deaths = s.deaths, map = s.map or ns.MainZone(s), legacy = s.legacy, star = s.star,
        name = s.name, activity = t.activity, label = t.label, costs = t.costs, auto = s.auto, state = s.state }
end
ns.Summary = summary

function API.State() return ns.State() end
function API.Live() return summary(ns.Live()) end
function API.Sessions(since, char)
    local out = {}
    local list = ns.db and ns.db.sessions or {}
    for i = #list, 1, -1 do
        local s = list[i]
        if (not since or (s.t1 or 0) >= since) and (not char or s.c == char) then out[#out + 1] = summary(s) end
    end
    return out
end
function API.Start() return ns.Start("manual") end
function API.Stop() return ns.Stop("manual") and true or false end
function API.Pause() return ns.Pause("manual") end
function API.Resume() return ns.Resume("manual") end
function API.Split() return ns.Split() end
function API.Toggle() return ns.Toggle() end
function API.ToggleHUD() return ns.SetHUD(not ns.HUDShown()) end
function API.SetHUD(on) return ns.SetHUD(on) end
function API.HUDShown() return ns.HUDShown() end
function API.OpenLedger(id)
    if id and ns.ShowSession then KM.Show("farming"); return ns.ShowSession(id) end
    KM.Show("farming")
end
function API.PauseOrResume()
    if ns.State() == "running" then return ns.Pause("manual") end
    if ns.State() == "paused" then return ns.Resume("manual") end
    return ns.Start("manual")
end

---------------------------------------------------------------------------
-- Key bindings (Bindings.xml) and the confirm popup
---------------------------------------------------------------------------

BINDING_NAME_KINGMAKER_TOGGLE = "Open or close King Maker"
BINDING_NAME_KINGMAKER_FARM_HUD = "Show or hide the Farm Tracker"
BINDING_NAME_KINGMAKER_FARM_STARTSTOP = "Start or stop (save) a farming session"
BINDING_NAME_KINGMAKER_FARM_PAUSE = "Pause or resume the farming clock"
BINDING_NAME_KINGMAKER_FARM_SPLIT = "Save this session and start the next"
BINDING_NAME_KINGMAKER_FARM_LEDGER = "Open the Farming Ledger"

-- An entry in Blizzard's table, never a reassignment of it.
StaticPopupDialogs["KINGMAKER_TRACKER_CONFIRM"] = {
    text = "%s", button1 = YES, button2 = NO,
    OnAccept = function(_, fn) if fn then fn() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns.Confirm(text, fn)
    if StaticPopup_Show then StaticPopup_Show("KINGMAKER_TRACKER_CONFIRM", text, nil, fn) else fn() end
end

---------------------------------------------------------------------------
-- /farm (long alias /farmtracker)
---------------------------------------------------------------------------

local function status()
    local s = ns.Live()
    if not s then
        local last = ns.db.sessions[#ns.db.sessions]
        KM.Print(ns, "not farming right now." .. (last and ("  Last: " .. ns.SessionLine(last)) or ""))
        return
    end
    local t = ns.Totals(s)
    KM.Print(ns, (ns.State() == "paused" and "paused" or "farming") .. ": " .. ns.PlaceName(s) .. ", "
        .. ns.Clock(ns.Active(s)) .. ", " .. KM.Money(t.value) .. " (" .. (t.gph and (KM.Money(t.gph) .. "/hr") or "under a minute") .. ").")
end

local function help()
    KM.Print(ns, "commands:")
    print("  /farm [on|off]   show or hide the Farm Tracker")
    print("  /farm start   start (or resume) a session")
    print("  /farm stop   stop and save it to the Farming Ledger")
    print("  /farm pause   pause or resume the clock")
    print("  /farm split   save this session and start the next one straight away")
    print("  /farm discard   throw the current session away (asks first)")
    print("  /farm ledger   open the Farming Ledger (also /km farming)")
    print("  /farm export   the ledger's sessions as text for a spreadsheet")
    print("  /farm auto on|off   start sessions by themselves when you farm")
    print("  /farm status   state, time, farmed, gold per hour")
end

SLASH_KINGMAKERFARM1 = "/farm"
SLASH_KINGMAKERFARM2 = "/farmtracker"
SlashCmdList.KINGMAKERFARM = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd, rest = (cmd or ""):lower(), (rest or ""):lower()
    if cmd == "on" or cmd == "off" then
        ns.SetHUD(cmd == "on")
    elseif cmd == "" or cmd == "show" or cmd == "hud" then
        ns.SetHUD(rest == "on" or (rest ~= "off" and not ns.HUDShown()))
    elseif cmd == "start" then
        if ns.State() == "running" then KM.Print(ns, "already farming.") else ns.Start("manual") end
    elseif cmd == "stop" or cmd == "save" then
        if not ns.Live() then KM.Print(ns, "not farming right now.") else ns.Stop("manual", true) end
    elseif cmd == "pause" or cmd == "resume" then
        API.PauseOrResume()
    elseif cmd == "split" then
        ns.Split()
    elseif cmd == "discard" then
        ns.Discard()
    elseif cmd == "ledger" or cmd == "history" then
        API.OpenLedger()
    elseif cmd == "export" or cmd == "csv" then
        if ns.Export then ns.Export() end
    elseif cmd == "auto" then
        local st = ns.Settings()
        st.autoStart = rest == "on" or (rest ~= "off" and not st.autoStart)
        KM.Print(ns, "sessions start by themselves when you farm: " .. (st.autoStart and "on." or "off."))
    elseif cmd == "status" then
        status()
    else
        help()
    end
end
