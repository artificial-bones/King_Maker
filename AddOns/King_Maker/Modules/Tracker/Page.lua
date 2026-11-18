local _, KM = ...
local ns = KM.Module("Tracker")
local UI = KM.UI
local C = UI.C

-- The Farming Ledger page (Farming > Farming Ledger, /km farming, /farm ledger) and the Farm Tracker's place in the
-- shell: crown quick actions, the Home tile, a crown tooltip line, the sidebar status line and Settings > Farm Tracker.
-- The page has three tabs on one top bar (with Export, the character filter and the period): Sessions (here),
-- Trends and Mat Prices (Trends.lua); a session opens in the list's place (Detail.lua).

---------------------------------------------------------------------------
-- Sums over sessions (time-weighted: gold per hour is total value over total active time, never an average of rates)
---------------------------------------------------------------------------

-- Saved sessions (newest first) since t (nil = all), for char (nil = every character); legacy ones left out unless
-- withLegacy.
function ns.SessionsSince(since, char, withLegacy)
    local out = {}
    local list = ns.db and ns.db.sessions or {}
    for i = #list, 1, -1 do
        local s = list[i]
        if (not since or (s.t1 or 0) >= since) and (not char or s.c == char) and (withLegacy or not s.legacy) then
            out[#out + 1] = s
        end
    end
    return out
end

function ns.Aggregate(list, revalue)
    local a = { n = 0, value = 0, act = 0, coin = 0, costs = 0, paused = 0, auto = 0, best = nil, bestS = nil }
    for _, s in ipairs(list) do
        if not s.legacy then
            local v = revalue and ns.ValueNow(s) or (s.value or 0)
            a.n = a.n + 1
            a.value = a.value + v
            a.act = a.act + (s.act or 0)
            a.coin = a.coin + (s.coin or 0)
            a.costs = a.costs + ns.Costs(s)
            a.paused = a.paused + (s.paused or 0)
            if s.auto then a.auto = a.auto + 1 end
            if (s.act or 0) >= 600 then
                local g = v / s.act * 3600
                if not a.best or g > a.best then a.best, a.bestS = g, s end
            end
        end
    end
    a.gph = a.act >= 60 and a.value / a.act * 3600 or nil
    return a
end

---------------------------------------------------------------------------
-- Crown quick actions, Home, tooltip, status
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "tracker-hud", label = "Farm Tracker", order = 42,
    func = function() TrackerKing.ToggleHUD() end, shown = function() return ns.db ~= nil end })
KM.RegisterQuickAction({ id = "tracker-startstop", order = 43,
    label = function() return ns.Live() and "Stop farming (save)" or "Start farming" end,
    func = function() ns.Toggle() end, shown = function() return ns.db ~= nil end })
KM.RegisterQuickAction({ id = "tracker-ledger", label = "Farming Ledger", order = 44,
    func = function() TrackerKing.OpenLedger() end, shown = function() return ns.db ~= nil end })

KM.RegisterHomeTile({ id = "farming", order = 30, page = "farming", spark = function()
    if not (ns.db and ns.Days) then return nil end
    local now = KM.Now()
    local list = ns.SessionsSince(now - 30 * 86400)
    if #list == 0 then return nil end
    local v = {}
    for _, d in ipairs(ns.Days(list, now - 29 * 86400)) do v[#v + 1] = d.value end
    return v, C.accent
end, get = function()
    if not ns.db then return nil end
    local s = ns.Live()
    if s then
        local t = ns.Totals(s)
        return "Farming now", t.gph and (KM.Money(t.gph) .. "/hr") or KM.Money(t.value),
            ns.Clock(t.act) .. "  .  " .. KM.Money(t.value) .. " farmed" .. (s.state == "paused" and "  (paused)" or ""),
            s.state == "paused" and C.warn or nil
    end
    local a = ns.Aggregate(ns.SessionsSince(KM.Now() - 7 * 86400))
    if a.n == 0 then return "Farming", "-", "no sessions this week: /farm start", C.dim end
    return "Farmed, 7 days", a.gph and (KM.MoneyShort(a.gph) .. "/hr") or KM.MoneyShort(a.value),
        ns.Dur(a.act) .. "  .  " .. KM.MoneyShort(a.value) .. " farmed"
end, tip = function(tt)
    if ns.Live() then
        tt:AddLine("The farming session running now: gold per hour of active time (the big number), the clock and what it has made so far. Yellow: paused.", 1, 1, 1, true)
    else
        tt:AddLine("Gold per hour of active time over your saved farming sessions from the last 7 days, on all your characters (the big number), with their active time and what they made. The bars: farmed per day, 30 days.", 1, 1, 1, true)
    end
    tt:AddLine("Coin plus loot, each item at the better of its market price after the 5% cut or a vendor's price when it dropped (grey and soulbound loot at the vendor price). Paused and idle time doesn't count.", 0.7, 0.7, 0.7, true)
end })

-- Home: what farming brought in (where your gold came from) and your best farm by gold per hour.
KM.RegisterHomeCard({ kind = "income", id = "tracker", order = 20, get = function(since)
    if not ns.db then return nil end
    local a = ns.Aggregate(ns.SessionsSince(since))
    if a.n == 0 or a.value <= 0 then return nil end
    return { { label = "Farming", value = a.value, page = "farming",
        tip = a.n .. " farming session" .. (a.n == 1 and "" or "s") .. " (" .. ns.Dur(a.act) .. " active): coin and loot at its value when it dropped, "
            .. KM.Money(a.value) .. ". Loot you sold since also counts under its auction strategy." } }
end })

KM.RegisterHomeCard({ kind = "best", id = "tracker-farm", order = 20, get = function()
    if not (ns.db and ns.Farms) then return nil end
    local f = ns.Farms(ns.SessionsSince(KM.Now() - 30 * 86400))[1]
    if not (f and f.gph) then return nil end
    local where = f.map and ns.ZoneName(f.map) or "?"
    return { label = "Farm", sub = where .. " (" .. f.label .. ")", value = KM.MoneyShort(f.gph) .. "/hr", icon = "Interface\\Icons\\INV_Misc_Bag_08",
        page = "farming", tab = function() ns.db.ui.tab = "trends" end,
        tip = "Your best farm in the last 30 days by gold per hour of active time: " .. where .. " (" .. f.label .. "), " .. f.n .. " session"
            .. (f.n == 1 and "" or "s") .. ", " .. ns.Dur(f.act) .. ", " .. KM.Money(f.value) .. ". Click for the Farming Ledger's Trends." }
end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local s = ns.Live()
    if s then
        local t = ns.Totals(s)
        tt:AddLine("Farming: " .. ns.Clock(t.act) .. ", " .. KM.Money(t.value)
            .. (t.gph and (" (" .. KM.Money(t.gph) .. "/hr)") or "") .. (s.state == "paused" and ", paused." or "."), 1, 1, 1)
        return
    end
    local a = ns.Aggregate(ns.SessionsSince(KM.Now() - 7 * 86400))
    if a.n > 0 then
        tt:AddLine("Farmed this week: " .. KM.Money(a.value) .. (a.gph and (" (" .. KM.Money(a.gph) .. "/hr)") or "") .. ".", 1, 1, 1)
    end
end)

KM.RegisterStatus(function()
    if not ns.db then return nil end
    local s = ns.Live()
    if not s or s.state ~= "running" then return nil end
    local t = ns.Totals(s)
    local secs = math.floor(t.act)
    return "Farming " .. string.format("%d:%02d", math.floor(secs / 3600), math.floor(secs / 60) % 60)
        .. (t.gph and ("  .  " .. KM.Money(t.gph, true) .. "/hr") or "")
end)

---------------------------------------------------------------------------
-- Settings > Farm Tracker
---------------------------------------------------------------------------

local function S() return ns.db.settings end

KM.RegisterSettings({ id = "tracker", label = "Farm Tracker", order = 42, rows = {
    { type = "check", label = "Show the Farm Tracker", tip = "The floating box for the session you're farming now. Also /farm.",
      get = function() return ns.HUDShown() end, set = function(v) ns.SetHUD(v) end },
    { type = "check", label = "Show it when a session starts", get = function() return S().hudOnStart end,
      set = function(v) S().hudOnStart = v end },
    { type = "range", label = "Farm Tracker size", min = 0.7, max = 1.4, step = 0.05,
      get = function() return ns.db.ui.hudScale or 1 end,
      set = function(v)
          ns.db.ui.hudScale = math.floor(v * 20 + 0.5) / 20
          if ns.hudFrame then ns.hudFrame:SetScale(ns.db.ui.hudScale) end
      end,
      fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
      tip = "Ctrl + mouse wheel over the Farm Tracker does the same." },
    { type = "header", label = "Sessions" },
    { type = "check", label = "Start a session by itself when I farm",
      tip = "After 3 kills, nodes, catches or skins within five minutes. One that runs under two minutes, or makes nothing, is dropped.",
      get = function() return S().autoStart end, set = function(v) S().autoStart = v end },
    { type = "choice", label = "Pause the clock when idle for", options = { { 120, "2 min" }, { 300, "5 min" }, { 600, "10 min" }, { 0, "Never" } },
      get = function() return S().idlePause end, set = function(v) S().idlePause = v end },
    { type = "check", label = "Resume when I farm again", tip = "A paused session's clock starts again on your next kill, node, catch or skin.", get = function() return S().autoResume end,
      set = function(v) S().autoResume = v end },
    { type = "choice", label = "Save an idle session after", options = { { 600, "10 min" }, { 1200, "20 min" }, { 3600, "60 min" }, { 0, "Never" } },
      get = function() return S().idleStop end, set = function(v) S().idleStop = v end },
    { type = "check", label = "Count party coin shares", tip = "Coin that arrives while you're grouped with nothing open: your share of a groupmate's loot.",
      get = function() return S().countShares end, set = function(v) S().countShares = v end },
    { type = "check", label = "Count quest gold", tip = "Quest rewards always show on a session's Money tab; ticked, they also count as farmed.",
      get = function() return S().countQuest end, set = function(v) S().countQuest = v end },
    { type = "check", label = "Count disenchanting", tip = "Disenchanting turns an item you already had into mats, so counting it can count the same gold twice. The session you're farming follows at once; saved sessions keep how they were counted.",
      get = function() return S().countDE end, set = function(v) ns.SetCountDE(v) end },
    { type = "header", label = "Ledger" },
    { type = "choice", label = "Keep", options = { { 100, "100" }, { 200, "200" }, { 500, "500" } },
      get = function() return S().keep end, set = function(v) S().keep = v; ns.Prune() end },
    { type = "text", label = "Sessions older than 45 days keep their totals and top 25 items; starred (kept) sessions stay as they are." },
    { type = "button", label = "Open the Farming Ledger", func = function() TrackerKing.OpenLedger() end },
    { type = "button", label = "Save the current session now", func = function() if ns.Live() then ns.Stop("manual", true) end end },
    { type = "button", label = "Discard the current session", tip = "Throws the session you're farming now away: nothing of it is saved. Asks first.", func = function() ns.Discard() end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/farm   show or hide the Farm Tracker\n/farm start | stop | pause | split | discard\n"
        .. "/farm ledger   the Farming Ledger (also /km farming)\n/farm export   the sessions as text for a spreadsheet\n"
        .. "/farm auto on|off   start sessions by themselves\n/farm status\n"
        .. "Key bindings: Esc > Options > Key Bindings > AddOns > King Maker." },
} })

---------------------------------------------------------------------------
-- The Farming Ledger page: Sessions (six tiles, gold per hour for each session, the session table); a click opens
-- one session (Detail.lua) in the list's place. It lays out from its container's size (the window zooms).
---------------------------------------------------------------------------

local PERIODS = { { 7, "7 days" }, { 30, "30 days" }, { 0, "All" } }
local TILE_H, GAP = 58, 10
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12|t"
ns.STAR = STAR

-- An 8 px colour swatch inline in text.
function ns.Swatch(c)
    c = c or C.dim
    return string.format("|TInterface\\Buttons\\WHITE8X8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t",
        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local P = {}            -- the page's frames, shared with Detail.lua and Trends.lua
ns.P = P

local SHORT = { mobs = "MOBS", mixed = "MIXED", none = "-" }
local GATHER_SHORT = { Mining = "MINING", Herbalism = "HERBS", Fishing = "FISHING", Treasure = "TREASURE", Containers = "BOXES" }
function ns.ActivityText(s)
    local activity, label = ns.Classify(s)
    if activity == "gathering" then return GATHER_SHORT[label] or "GATHERING", activity, label end
    if activity == "mobs" and label == "Mobs & Skinning" then return "MOBS & SKINS", activity, label end
    return SHORT[activity] or "MIXED", activity, label
end

function ns.SessionTitle(s)
    return s.name or ns.ZoneName(ns.MainZone(s))
end

local function U() return ns.db.ui end
local function char() return U().mine and KM.Char() or nil end
local function since(days)
    days = days or U().period or 30
    if days == 0 then return nil end
    return KM.Now() - days * 86400
end

-- The filtered list, newest first (legacy sessions included: they show with a pill, and stay out of the sums).
-- P.farm (a Best farms row clicked on Trends) narrows it to one farm: { key, label }.
function ns.ListSessions()
    local list = ns.SessionsSince(since(), char(), true)
    if not P.farm then return list end
    local out = {}
    for _, s in ipairs(list) do if not s.legacy and ns.FarmKey(s) == P.farm.key then out[#out + 1] = s end end
    return out
end
ns.Since, ns.CharFilter = since, char

function ns.Gathered(s)
    local n = 0
    for kind in pairs(ns.GATHER_KINDS) do local e = s.src and s.src[kind]; n = n + (e and e.n or 0) end
    return n
end

local function pct(a, b)
    if not (a and b) or b <= 0 then return nil end
    return (a - b) / b * 100
end

function ns.Delta(p, what)
    if not p then return what or "" end
    local c = p >= 0 and C.good or C.bad
    return UI.Hex(c) .. (p >= 0 and "+" or "") .. math.floor(p + 0.5) .. "%|r " .. (what or "")
end

local function tileWidth(w)
    return math.max(110, math.floor(((w or 763) - 5 * GAP) / 6))
end
ns.TileWidth = tileWidth

function ns.LayoutTiles(tiles, w)
    local tw = tileWidth(w)
    for i, t in ipairs(tiles) do
        t:SetSize(tw, TILE_H)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", (i - 1) * (tw + GAP), 0)
    end
end

function ns.MakeTiles(parent, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(TILE_H)
    local tiles = {}
    for i = 1, 6 do tiles[i] = UI.Tile(row, 119, TILE_H) end
    ns.LayoutTiles(tiles, 763)
    return row, tiles
end

-- Rename (a popup with an edit box), keep, delete: the row menu and the detail's buttons.
StaticPopupDialogs["KINGMAKER_TRACKER_RENAME"] = {
    text = "Name this farming session (empty: back to its zone):", button1 = OKAY or "OK", button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self, id)
        local s = ns.Find(id)
        local box = self.editBox or self.EditBox
        if box and s then box:SetText(s.name or "") end
    end,
    OnAccept = function(self, id)
        local box = self.editBox or self.EditBox
        ns.Rename(id, box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self, id) ns.Rename(id, self:GetText() or ""); self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.AskRename(id) if StaticPopup_Show then StaticPopup_Show("KINGMAKER_TRACKER_RENAME", nil, nil, id) end end

function ns.AskDelete(id, after)
    local s = ns.Find(id)
    if not s then return end
    ns.Confirm("Delete the session " .. ns.SessionTitle(s) .. " from the Farming Ledger?", function()
        ns.Delete(id)
        if after then after() end
    end)
end

function ns.SessionMenu(owner, id)
    local s = ns.Find(id)
    if not s or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.SessionTitle(s))
        root:CreateButton("Open", function() ns.ShowSession(id) end)
        root:CreateButton("Rename", function() ns.AskRename(id) end)
        root:CreateButton(s.star and "Don't keep" or "Keep (never pruned)", function() ns.Star(id, not s.star) end)
        root:CreateButton("Delete", function() ns.AskDelete(id) end)
    end)
end

local P_COLS = {
    { key = "date", label = "Date", w = 92, sort = function(e) return e.t1 or 0 end },
    { key = "name", label = "Session", w = 236, sort = function(e) return ns.SessionTitle(e):lower() end, desc = false },
    { key = "act", label = "Active", tip = "Time the clock ran: paused and idle time left out.", w = 68, justify = "RIGHT", sort = function(e) return e.act or 0 end },
    { key = "value", label = "Farmed", tip = "Coin plus loot. Each item at the higher of its market price after the 5% cut or its vendor price, as it was when looted (or today's, with Prices: Today on a session).", w = 92, justify = "RIGHT", sort = function(e) return e.value or 0 end },
    { key = "gph", label = "Gold/hr", tip = "Farmed divided by active time. Blank under a minute.", w = 92, justify = "RIGHT", sort = function(e) return ns.Totals(e).gph or -1 end },
    { key = "kills", label = "Kills", w = 50, justify = "RIGHT", sort = function(e) return e.kills or 0 end },
    { key = "gath", label = "Gathered", tip = "Nodes mined or picked, fish caught, chests and boxes opened.", w = 66, justify = "RIGHT", sort = function(e) return ns.Gathered(e) end },
    { key = "char", label = "", w = 0 },
}

local function fillRow(r, s, cells)
    local t = ns.Totals(s, U().revalue)
    local short, activity = ns.ActivityText(s)
    cells.date:SetText(ns.Date("%d %b %H:%M", s.t1) or "?")
    local name = ns.SessionTitle(s)
    local tag = s.legacy and (UI.Hex(C.dim) .. "carried over|r") or (UI.Hex(C.muted) .. short .. "|r")
    if P.bestIDs and P.bestIDs[s.id] then tag = tag .. "  " .. UI.Hex(C.accent) .. "BEST|r" end
    cells.name:SetText((s.star and (STAR .. " ") or "") .. ns.Swatch(s.legacy and C.dim or ns.ACTIVITY_COLOR[activity])
        .. " " .. name .. "  " .. tag)
    cells.act:SetText(ns.Clock(s.act))
    cells.value:SetText(KM.Money(t.value))
    cells.gph:SetText(t.gph and KM.Money(t.gph) or "|cff808080-|r")
    cells.kills:SetText((s.kills or 0) > 0 and tostring(s.kills) or "|cff808080-|r")
    local g = ns.Gathered(s)
    cells.gath:SetText(g > 0 and tostring(g) or "|cff808080-|r")
    cells.char:SetText(U().mine and "" or (UI.Hex(C.muted) .. ((s.c or ""):gsub("%-.*$", "")) .. "|r"))
    local dim = s.legacy and C.dim or C.text
    for _, k in ipairs({ "date", "act", "value", "gph", "kills", "gath" }) do cells[k]:SetTextColor(dim[1], dim[2], dim[3], 1) end
    r.tip = function(tt)
        tt:AddLine(name, 1, 1, 1)
        tt:AddLine(ns.SessionLine(s), 0.8, 0.8, 0.8, true)
        if t.costs ~= 0 then
            tt:AddLine("Net after costs: " .. KM.Money(t.net) .. (t.act >= 60 and ("  (" .. KM.Money(t.net / t.act * 3600) .. "/hr)") or ""), 0.8, 0.8, 0.8)
        end
        if s.legacy then tt:AddLine("Carried over from the old trackers: left out of the totals and the chart.", 0.6, 0.6, 0.6, true) end
        if P.bestIDs and P.bestIDs[s.id] then tt:AddLine("BEST: your best gold per hour for this farm (zone and activity), 10+ active minutes.", C.accent[1], C.accent[2], C.accent[3], true) end
        tt:AddLine("Click for its details; right-click to rename, keep or delete.", 0.6, 0.6, 0.6)
    end
end

-- The top bar the three tabs share: Sessions | Trends | Mat Prices, Export, the character filter and the period.
local TABS = { { id = "sessions", label = "Sessions", w = 82 }, { id = "trends", label = "Trends", w = 72 },
    { id = "prices", label = "Mat Prices", w = 90 } }

function ns.Tab()
    local t = U().tab
    if t ~= "trends" and t ~= "prices" then t = "sessions" end
    return t
end

local function buildTop(c)
    local top = CreateFrame("Frame", nil, c)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(24)
    P.top = top
    P.tabs = UI.Tabs(top, TABS, function(id) U().tab = id; KM.Refresh("farming") end, 24)
    P.tabs:SetPoint("TOPLEFT", 0, 0)
    UI.Tip(P.tabs.buttons.trends, "What you farmed per day, your best farms and the items that made the most.")
    UI.Tip(P.tabs.buttons.prices, "Gathering mats: what they sell for now, against what they're worth to you (how fast you farm them and your gold per hour when you do).")
    local items = {}
    for _, p in ipairs(PERIODS) do items[#items + 1] = { id = p[1], label = p[2], w = 70 } end
    P.periods = UI.Tabs(top, items, function(id) U().period = id; KM.Refresh("farming") end, 24)
    P.periods:SetPoint("TOPRIGHT", 0, 0)
    P.charBtn = UI.Button(top, "All characters", 120, 24, function()
        U().mine = not U().mine
        KM.Refresh("farming")
    end)
    P.charBtn:SetPoint("RIGHT", P.periods, "LEFT", -10, 0)
    UI.Tip(P.charBtn, "Every character's sessions, or only this character's.")
    P.export = UI.Button(top, "Export", 64, 24, function() if ns.Export then ns.Export() end end)
    P.export:SetPoint("RIGHT", P.charBtn, "LEFT", -10, 0)
    UI.Tip(P.export, "The sessions shown (this period, these characters) as comma-separated text, for a spreadsheet. Also /farm export.")
end

local function buildList(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetAllPoints(c)
    P.list = v

    P.tileRow, P.tiles = ns.MakeTiles(v, -32)
    local function dl(tt, l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
    local function scope(tt)
        tt:AddLine((U().mine and "This character" or "Every character") .. ", the sessions in this period. Carried-over sessions aren't counted.", 0.6, 0.6, 0.6, true)
    end
    local T = P.tiles
    T[1]:SetTip(function(tt)
        local a = P.agg or ns.Aggregate({})
        tt:AddLine("Coin plus loot from your sessions. Each item at the higher of its market price after the 5% cut or its vendor price (greys and soulbound at vendor), "
            .. (U().revalue and "at today's prices." or "as it was when looted."), 1, 1, 1, true)
        dl(tt, "Coin", KM.Money(a.coin)); dl(tt, "Items", KM.Money(a.value - a.coin))
        scope(tt)
    end)
    T[2]:SetTip(function(tt)
        local a = P.agg or ns.Aggregate({})
        tt:AddLine("All farmed gold over all active time, so a long session counts for more than a short one. The line under it compares with the same number of days before.", 1, 1, 1, true)
        dl(tt, "Farmed", KM.Money(a.value)); dl(tt, "Active time", ns.Dur(a.act))
        scope(tt)
    end)
    T[3]:SetTip(function(tt)
        tt:AddLine("Active time: the clock runs while you farm and stops when you pause or go idle. Paused time is shown under it and left out of gold per hour.", 1, 1, 1, true)
        scope(tt)
    end)
    T[4]:SetTip(function(tt)
        tt:AddLine("Saved sessions in this period. Started by themselves: Settings > Farm Tracker > Start a session by itself.", 1, 1, 1, true)
        scope(tt)
    end)
    T[5]:SetTip(function(tt)
        tt:AddLine("Your best gold per hour in one session, out of those with at least 10 active minutes. Its name is under it.", 1, 1, 1, true)
        scope(tt)
    end)
    T[6]:SetTip(function(tt)
        local by = {}
        for _, k in ipairs(ns.COST_KINDS) do by[k] = 0 end
        for _, s in ipairs(P.listed or {}) do
            if not s.legacy then for _, k in ipairs(ns.COST_KINDS) do by[k] = by[k] + ((s.cash and s.cash[k]) or 0) end end
        end
        local a = P.agg or ns.Aggregate({})
        tt:AddLine("Gold spent while farming. Net is farmed minus these.", 1, 1, 1, true)
        dl(tt, "Repairs", KM.Money(-by.repair)); dl(tt, "Bought from vendors", KM.Money(-by.buy))
        dl(tt, "Flight paths", KM.Money(-by.travel)); dl(tt, "Training", KM.Money(-by.train))
        dl(tt, "Net farmed", KM.Money(a.value + a.costs))
        scope(tt)
    end)

    local panel = UI.Panel(v, C.panel)
    panel:SetPoint("TOPLEFT", 0, -100)
    panel:SetPoint("TOPRIGHT", 0, -100)
    panel:SetHeight(124)
    P.chartPanel = panel
    local ch = UI.Heading(panel, "Gold per hour, each session")
    ch:SetPoint("TOPLEFT", 10, -8)
    local legend = UI.Text(panel, 10, C.muted, "RIGHT")
    legend:SetPoint("TOPRIGHT", -10, -8)
    legend:SetText(ns.Swatch(ns.ORANGE) .. " Mobs    " .. ns.Swatch(ns.AQUA) .. " Gathering    " .. ns.Swatch(ns.BLUE) .. " Mixed")
    P.chart = UI.Chart(panel, 740, 96)
    P.chart.frame:SetPoint("TOPLEFT", 6, -24)

    P.table = UI.Table(v, P_COLS, 22, {
        onClick = function(s, button, row)
            if button == "RightButton" then ns.SessionMenu(row, s.id) else ns.ShowSession(s.id) end
        end,
    })
    P.table:SetPoint("TOPLEFT", 0, -232)
    P.table:SetPoint("BOTTOMRIGHT", 0, 18)
    P.table:SetSort("date", true)
    P.table.emptyText = "No sessions yet. Press Start on the Farm Tracker, or just start farming: a session starts by itself after a few kills or nodes."
    P.footer = UI.Text(v, 10, C.dim)
    P.footer:SetPoint("BOTTOMLEFT", 0, 2)
    -- one farm only (a Best farms row on Trends): its name, and a click shows every session again
    P.farmBtn = UI.Button(v, "", 260, 16, function() P.farm = nil; KM.Refresh("farming") end, "ghost")
    P.farmBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    P.farmBtn.label:SetJustifyH("RIGHT")
    UI.Tip(P.farmBtn, "Only this farm's sessions (picked on Trends). Click to show every session again.")
    P.farmBtn:Hide()
end

local function drawChart(list, a)
    local pts, chrono = {}, {}
    for _, s in ipairs(list) do if not s.legacy then chrono[#chrono + 1] = s end end
    table.sort(chrono, function(x, y) return (x.t1 or 0) < (y.t1 or 0) end)
    for i, s in ipairs(chrono) do
        local t = ns.Totals(s, U().revalue)
        local _, activity = ns.ActivityText(s)
        pts[#pts + 1] = { i, t.gph or 0, ns.ACTIVITY_COLOR[activity] or C.dim, s }
    end
    P.chart:Draw({
        tmin = 0.5, tmax = #chrono + 0.5,
        series = { { pts = pts, style = "bars", agg = "none" } },
        format = function(y) return KM.Money(y, true) end,
        xformat = function(x)
            local s = chrono[math.max(1, math.min(#chrono, math.floor(x + 0.5)))]
            return s and ns.Date("%d %b", s.t1) or ""
        end,
        ref = a.gph and { y = a.gph, label = "avg " .. KM.Money(a.gph, true) } or nil,
        hover = function(_, p)
            local s = p and p[4]
            if not s then return end
            GameTooltip:AddLine(ns.SessionTitle(s), 1, 1, 1)
            GameTooltip:AddLine(ns.SessionLine(s), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Click to open it.", 0.6, 0.6, 0.6)
        end,
        click = function(_, p) if p and p[4] then ns.ShowSession(p[4].id) end end,
        emptyText = "No sessions in this period yet",
    })
    P.chartSessions = chrono
end

function ns.RefreshList(c)
    local u = U()
    local w = (c and c:GetWidth()) or 763
    if w ~= P.width then
        P.width = w
        ns.LayoutTiles(P.tiles, w)
        P.chart:SetSize(math.max(300, w - 12), 96)
    end
    local list = ns.ListSessions()
    local a = ns.Aggregate(list, u.revalue)
    P.agg, P.listed = a, list
    P.bestIDs = ns.BestIDs()
    -- the same length of time before, for the change in gold per hour
    local prevA
    if (u.period or 30) > 0 then
        local days = u.period
        local prev = {}
        for _, s in ipairs(ns.SessionsSince(KM.Now() - 2 * days * 86400, char())) do
            if (s.t1 or 0) < KM.Now() - days * 86400 then prev[#prev + 1] = s end
        end
        prevA = ns.Aggregate(prev, u.revalue)
    end
    local T = P.tiles
    T[1]:Set("Farmed", KM.Money(a.value), KM.Money(a.coin, true) .. " coin")
    T[2]:Set("Gold/hr", a.gph and KM.Money(a.gph) or "-",
        prevA and prevA.gph and a.gph and ns.Delta(pct(a.gph, prevA.gph), "vs the " .. u.period .. " days before") or "time-weighted")
    T[3]:Set("Time", ns.Dur(a.act), a.paused > 0 and ("+" .. ns.Dur(a.paused) .. " paused") or "active time")
    T[4]:Set("Sessions", tostring(a.n), a.auto .. " started by themselves")
    T[5]:Set("Best", a.best and (KM.Money(a.best) .. "/hr") or "-", a.bestS and ns.SessionTitle(a.bestS) or "10+ active minutes")
    T[6]:Set("Costs", KM.Money(a.costs), "net " .. KM.Money(a.value + a.costs, true), a.costs < 0 and C.bad or nil)
    drawChart(list, a)
    P.table:SetRows(list, fillRow)
    local ids = {}
    for _, s in ipairs(P.table.data) do ids[#ids + 1] = s.id end
    P.order = ids
    P.footer:SetText(#list > 0 and (#list .. " session" .. (#list == 1 and "" or "s") .. ". Click one for its details; right-click to rename, keep or delete.") or "")
    if P.farm then
        P.farmBtn:SetLabel(UI.Hex(C.accent) .. P.farm.label .. "|r   " .. UI.Hex(C.muted) .. "x  show all|r")
        P.farmBtn:Show()
    else
        P.farmBtn:Hide()
    end
end

local function build(c)
    P.container = c
    buildTop(c)
    buildList(c)
    if ns.BuildDetail then ns.BuildDetail(c) end
    if ns.BuildTrends then ns.BuildTrends(c) end
    if ns.BuildPrices then ns.BuildPrices(c) end
    c:SetScript("OnSizeChanged", function(self) if self:IsShown() then KM.Refresh("farming") end end)
end

local function refreshTop()
    local u = U()
    local tab = ns.Tab()
    P.tabs:Select(tab)
    P.periods:Select(u.period or 30)
    P.periods:SetShown(tab ~= "prices")
    P.export:SetShown(tab ~= "prices")
    P.charBtn:SetLabel(u.mine and "This character" or "All characters")
    P.charBtn:SetActive(u.mine and true or false)
    P.charBtn:ClearAllPoints()
    if tab == "prices" then P.charBtn:SetPoint("TOPRIGHT", 0, 0) else P.charBtn:SetPoint("RIGHT", P.periods, "LEFT", -10, 0) end
end

local function refresh(c)
    if not ns.db then return end
    local show
    if P.view == "detail" and ns.RefreshDetail and ns.Find(P.sessionID or -1) then
        show = P.detail
        P.top:Hide()
    else
        P.view = "list"
        P.top:Show()
        refreshTop()
        local tab = ns.Tab()
        show = (tab == "trends" and P.trends) or (tab == "prices" and P.prices) or P.list
    end
    for _, f in ipairs({ P.list, P.detail, P.trends, P.prices }) do if f ~= show then f:Hide() end end
    show:Show()
    if show == P.detail then ns.RefreshDetail(c)
    elseif show == P.trends then ns.RefreshTrends(c)
    elseif show == P.prices then ns.RefreshPrices(c)
    else ns.RefreshList(c) end
end

function ns.ShowList()
    P.view = "list"
    if ns.db and ns.Tab() ~= "sessions" then U().tab = "sessions" end
    if KM.IsShown("farming") then KM.Refresh("farming") else KM.Show("farming") end
end

function ns.ShowSession(id)
    if not ns.Find(id) then return end
    P.view, P.sessionID = "detail", id
    if KM.IsShown("farming") then KM.Refresh("farming") else KM.Show("farming") end
end

function ns.Refresh() KM.Refresh("farming") end

KM.RegisterPage({
    id = "farming", group = "farm", label = "Farming Ledger", icon = "Interface\\Icons\\INV_Misc_Coin_01", order = 5,
    title = "Farming Ledger",
    subtitle = function()
        if P.view == "detail" then return "One farming session: what you looted, where it came from and what it made per hour." end
        if ns.db and ns.Tab() == "trends" then return "Your farming over time: gold per day, your best farms and what made the most." end
        if ns.db and ns.Tab() == "prices" then return "What gathering mats sell for, and what they're worth to you: how fast you farm them and what that pays." end
        return "Every farming session: what you looted, what it's worth and your gold per hour."
    end,
    badge = function() return ns.State() == "running" and "LIVE" or "" end,
    build = build, refresh = refresh,
    resize = function() KM.Refresh("farming") end,
})
