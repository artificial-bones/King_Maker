local _, KM = ...
local ns = KM.Module("Tracker")
local UI = KM.UI
local C = UI.C

-- The Farming Ledger's Zones tab (King Maker 2.15.0): every saved farm in a zone, dungeon or raid added together, so
-- you can see where you do best.
--   Zones list   six tiles (places, best zone, best dungeon, most farmed, most time, last farmed), a filter (All /
--                Zones / Dungeons) and one row per place: sessions, time, farmed, gold per hour (time-weighted), the
--                best session's rate, mobs per hour and when you were last there. Click a row for that place.
--   A place      back, its name and what you did there; six tiles; gold per hour of each session there (click a bar
--                for the session); its sessions (click one for its details, Back comes here) and its top items.
-- A session's place is ns.Place (Session.lua): the dungeon it spent most of its time in, else its main zone. The
-- character filter and the period on the top bar apply; carried-over sessions never count.

local P = ns.P
local Z = {}          -- Zones frames
ns.Z = Z              -- (tests)
local BEST_MIN = 600  -- a gold per hour needs 10 active minutes
local DASH = "|cff808080-|r"
local KIND = { zone = "Zone", dungeon = "Dungeon", raid = "Raid" }
local FILTERS = { { id = "all", label = "All", w = 52 }, { id = "zone", label = "Zones", w = 64 },
    { id = "dungeon", label = "Dungeons", w = 84 } }

local function U() return ns.db.ui end
local function value(s) return U().revalue and ns.ValueNow(s) or (s.value or 0) end

---------------------------------------------------------------------------
-- The numbers (no frames: tests read these)
---------------------------------------------------------------------------

-- One row per place, best gold per hour first:
-- { key, name, kind, n, act, value, gph (nil under 10 active minutes), best, bestS, kills, corpses, mph, last, top,
--   acts = { "Mobs", "Herbalism" } }
function ns.Places(list)
    local by, out = {}, {}
    for _, s in ipairs(ns.TrendSessions(list)) do
        local key, name, kind = ns.Place(s)
        local p = by[key]
        if not p then
            p = { key = key, name = name, kind = kind, n = 0, act = 0, value = 0, kills = 0, corpses = 0, last = 0,
                  acts = {}, seen = {}, items = {} }
            by[key] = p
            out[#out + 1] = p
        end
        local v = value(s)
        p.n, p.act, p.value = p.n + 1, p.act + (s.act or 0), p.value + v
        p.kills = p.kills + (s.kills or 0)
        p.corpses = p.corpses + ((s.src and s.src.mob and s.src.mob.n) or 0)
        p.last = math.max(p.last, s.t1 or 0)
        if s.act >= BEST_MIN then
            local g = v / s.act * 3600
            if not p.best or g > p.best then p.best, p.bestS = g, s end
        end
        local _, label = ns.FarmKey(s)
        if label and not p.seen[label] then p.seen[label] = true; p.acts[#p.acts + 1] = label end
        for id, it in pairs(s.items or {}) do
            p.items[id] = (p.items[id] or 0) + (U().revalue and (it.q or 0) * (KM.ItemValue(id) or 0) or (it.v or 0))
        end
    end
    for _, p in ipairs(out) do
        p.gph = p.act >= BEST_MIN and p.value / p.act * 3600 or nil
        local mobs = math.max(p.kills, p.corpses)
        p.mph = (mobs > 0 and p.act >= 60) and mobs / p.act * 3600 or nil
        local topV = 0
        for id, v in pairs(p.items) do if v > topV or (v == topV and p.top and id < p.top) then p.top, topV = id, v end end
        table.sort(p.acts)
        p.seen, p.items = nil, nil
    end
    table.sort(out, function(a, b)
        if (a.gph or -1) ~= (b.gph or -1) then return (a.gph or -1) > (b.gph or -1) end
        return a.name < b.name
    end)
    return out
end

-- The counted sessions at one place, newest first.
function ns.PlaceSessions(list, key)
    local out = {}
    for _, s in ipairs(ns.TrendSessions(list)) do if ns.Place(s) == key then out[#out + 1] = s end end
    return out
end

---------------------------------------------------------------------------
-- The Zones list
---------------------------------------------------------------------------

local function kindText(kind)
    local c = (kind == "zone") and C.muted or C.accent
    return UI.Hex(c) .. (KIND[kind] or "Zone") .. "|r"
end

local PLACE_COLS = {
    { key = "name", label = "Place", w = 158, sort = function(e) return e.name:lower() end, desc = false },
    { key = "kind", label = "Type", w = 64, sort = function(e) return e.kind end, desc = false },
    { key = "n", label = "Sess", tip = "Saved sessions there.", w = 40, justify = "RIGHT", sort = function(e) return e.n end },
    { key = "act", label = "Time", tip = "Active time there, all sessions together.", w = 62, justify = "RIGHT", sort = function(e) return e.act end },
    { key = "value", label = "Farmed", tip = "Coin plus loot from every session there.", w = 92, justify = "RIGHT", sort = function(e) return e.value end },
    { key = "gph", label = "G/hr", tip = "All it made over all its active time, so a long session counts for more than a short one. Blank under 10 active minutes in all.", w = 86, justify = "RIGHT", sort = function(e) return e.gph or -1 end },
    { key = "best", label = "Best", tip = "The best gold per hour of one session there (10+ active minutes).", w = 86, justify = "RIGHT", sort = function(e) return e.best or -1 end },
    { key = "mph", label = "Mobs/hr", tip = "Mobs killed (or corpses looted, when more) per active hour.", w = 60, justify = "RIGHT", sort = function(e) return e.mph or -1 end },
    { key = "last", label = "Last", tip = "When you last farmed there.", w = 0, justify = "RIGHT", sort = function(e) return e.last end },
}

local function fillPlace(r, p, cells)
    cells.name:SetText(p.name)
    cells.kind:SetText(kindText(p.kind))
    cells.n:SetText(p.n)
    cells.act:SetText(ns.Dur(p.act))
    cells.value:SetText(KM.Money(p.value))
    cells.gph:SetText(p.gph and KM.Money(p.gph) or DASH)
    cells.best:SetText(p.best and KM.Money(p.best) or DASH)
    cells.mph:SetText(p.mph and string.format("%.0f", p.mph) or DASH)
    cells.last:SetText(p.last > 0 and (ns.Date("%d %b", p.last) or "?") or DASH)
    r.tip = function(tt)
        tt:AddLine(p.name .. "  " .. kindText(p.kind), 1, 1, 1)
        tt:AddDoubleLine("Farmed", KM.Money(p.value), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Active time", ns.Dur(p.act) .. " in " .. p.n .. " session" .. (p.n == 1 and "" or "s"), 0.8, 0.8, 0.8, 1, 1, 1)
        if #p.acts > 0 then tt:AddDoubleLine("What you did", table.concat(p.acts, ", "), 0.8, 0.8, 0.8, 1, 1, 1) end
        if p.top then tt:AddDoubleLine("Made the most", KM.ItemText(p.top), 0.8, 0.8, 0.8, 1, 1, 1) end
        if p.bestS then tt:AddDoubleLine("Best session", ns.Date("%d %b", p.bestS.t1) or "?", 0.8, 0.8, 0.8, 1, 1, 1) end
        tt:AddLine("Click for everything you farmed there.", 0.6, 0.6, 0.6)
    end
end

local function filterKey()
    local f = U().zoneFilter
    if f ~= "zone" and f ~= "dungeon" then f = "all" end
    return f
end

local function buildList(v)
    local lv = CreateFrame("Frame", nil, v)
    lv:SetAllPoints(v)
    Z.listView = lv
    Z.tileRow, Z.tiles = ns.MakeTiles(lv, -32)
    local function scope(tt)
        tt:AddLine((U().mine and "This character" or "Every character") .. ", this period. Carried-over sessions aren't counted.", 0.6, 0.6, 0.6, true)
    end
    Z.tiles[1]:SetTip(function(tt) tt:AddLine("Zones, dungeons and raids you farmed in.", 1, 1, 1, true); scope(tt) end)
    Z.tiles[2]:SetTip(function(tt) tt:AddLine("The zone with your best gold per hour (time-weighted, 10+ active minutes in all).", 1, 1, 1, true); scope(tt) end)
    Z.tiles[3]:SetTip(function(tt) tt:AddLine("The dungeon or raid with your best gold per hour (time-weighted, 10+ active minutes in all).", 1, 1, 1, true); scope(tt) end)
    Z.tiles[4]:SetTip(function(tt) tt:AddLine("Where you farmed the most gold in all.", 1, 1, 1, true); scope(tt) end)
    Z.tiles[5]:SetTip(function(tt) tt:AddLine("Where you spent the most active time.", 1, 1, 1, true); scope(tt) end)
    Z.tiles[6]:SetTip(function(tt) tt:AddLine("Where you farmed last.", 1, 1, 1, true); scope(tt) end)
    Z.filter = UI.Tabs(lv, FILTERS, function(id) U().zoneFilter = id; KM.Refresh("farming") end, 22)
    Z.filter:SetPoint("TOPLEFT", 0, -100)
    Z.note = UI.Text(lv, 10, C.muted, "RIGHT")
    Z.note:SetPoint("LEFT", Z.filter, "RIGHT", 12, 0)
    Z.note:SetPoint("RIGHT", lv, "RIGHT", 0, 0)
    Z.table = UI.Table(lv, PLACE_COLS, 22, { onClick = function(p) ns.ShowPlace(p.key) end })
    Z.table:SetPoint("TOPLEFT", 0, -130)
    Z.table:SetPoint("BOTTOMRIGHT", 0, 18)
    Z.table:SetSort("gph", true)
    Z.table.emptyText = "No farms here yet: sessions show here once saved."
    Z.footer = UI.Text(lv, 10, C.dim)
    Z.footer:SetPoint("BOTTOMLEFT", 0, 2)
end

local function bestOf(places, test, field)
    local best
    for _, p in ipairs(places) do
        local v = p[field]
        if v and (not test or test(p)) and (not best or v > best[field]) then best = p end
    end
    return best
end

local function refreshList(w)
    if w ~= Z.width then Z.width = w; ns.LayoutTiles(Z.tiles, w) end
    local all = ns.Places(ns.SessionsSince(ns.Since(), ns.CharFilter()))
    local f = filterKey()
    Z.filter:Select(f)
    local rows = {}
    for _, p in ipairs(all) do
        if f == "all" or (f == "zone" and p.kind == "zone") or (f == "dungeon" and p.kind ~= "zone") then rows[#rows + 1] = p end
    end
    Z.all, Z.rows = all, rows
    local zone = bestOf(all, function(p) return p.kind == "zone" end, "gph")
    local dungeon = bestOf(all, function(p) return p.kind ~= "zone" end, "gph")
    local most, longest, last = bestOf(all, nil, "value"), bestOf(all, nil, "act"), bestOf(all, nil, "last")
    local nz, nd = 0, 0
    for _, p in ipairs(all) do if p.kind == "zone" then nz = nz + 1 else nd = nd + 1 end end
    local T = Z.tiles
    T[1]:Set("Places", tostring(#all), nz .. " zone" .. (nz == 1 and "" or "s") .. ", " .. nd .. " dungeon" .. (nd == 1 and "" or "s"))
    T[2]:Set("Best zone", zone and zone.name or "-", zone and (KM.Money(zone.gph, true) .. "/hr") or "10+ active minutes")
    T[3]:Set("Best dungeon", dungeon and dungeon.name or "-", dungeon and (KM.Money(dungeon.gph, true) .. "/hr") or "none farmed yet")
    T[4]:Set("Most farmed", most and most.name or "-", most and KM.Money(most.value, true) or "")
    T[5]:Set("Most time", longest and longest.name or "-", longest and ns.Dur(longest.act) or "")
    T[6]:Set("Last farmed", last and last.name or "-", last and last.last > 0 and (ns.Date("%d %b", last.last) or "") or "")
    Z.note:SetText(#all > 0 and "Every session in a place added together" or "")
    Z.table:SetRows(rows, fillPlace)
    Z.footer:SetText(#rows > 0 and "Click a place for its sessions, items and best runs. Carried-over sessions aren't counted." or "")
end

---------------------------------------------------------------------------
-- One place
---------------------------------------------------------------------------

local S_COLS = {
    { key = "date", label = "Date", w = 84, sort = function(e) return e.t1 or 0 end },
    { key = "what", label = "Activity", w = 84, sort = function(e) return (select(2, ns.FarmKey(e))) or "" end, desc = false },
    { key = "act", label = "Active", w = 60, justify = "RIGHT", sort = function(e) return e.act or 0 end },
    { key = "value", label = "Farmed", w = 86, justify = "RIGHT", sort = function(e) return value(e) end },
    { key = "gph", label = "Gold/hr", w = 84, justify = "RIGHT", sort = function(e) return ns.Totals(e, U().revalue).gph or -1 end },
    { key = "char", label = "", w = 0 },
}

local I_COLS = {
    { key = "item", label = "Item", w = 132, sort = function(e) return KM.Item(e.id).name or "" end, desc = false },
    { key = "qty", label = "Qty", w = 46, justify = "RIGHT", sort = function(e) return e.q end },
    { key = "value", label = "Value", w = 0, justify = "RIGHT", sort = function(e) return e.v end },
}

local function fillSession(r, s, cells)
    local t = ns.Totals(s, U().revalue)
    local _, activity, label = ns.ActivityText(s)
    cells.date:SetText(ns.Date("%d %b %H:%M", s.t1) or "?")
    local best = Z.place and Z.place.bestS == s
    cells.what:SetText(ns.Swatch(ns.ACTIVITY_COLOR[activity]) .. " " .. UI.Hex(C.muted) .. (label or "") .. "|r"
        .. (best and ("  " .. UI.Hex(C.accent) .. "BEST|r") or ""))
    cells.act:SetText(ns.Clock(s.act))
    cells.value:SetText(KM.Money(t.value))
    cells.gph:SetText(t.gph and KM.Money(t.gph) or DASH)
    cells.char:SetText(U().mine and "" or (UI.Hex(C.muted) .. ((s.c or ""):gsub("%-.*$", "")) .. "|r"))
    r.tip = function(tt)
        tt:AddLine(ns.SessionTitle(s), 1, 1, 1)
        tt:AddLine(ns.SessionLine(s), 0.8, 0.8, 0.8, true)
        if best then tt:AddLine("BEST: your best gold per hour here (10+ active minutes).", C.accent[1], C.accent[2], C.accent[3], true) end
        tt:AddLine("Click for its details; Back comes here.", 0.6, 0.6, 0.6)
    end
end

local function fillItem(r, e, cells)
    if r.icon then r.icon:SetTexture(KM.Item(e.id).icon) end
    r.item = e.id
    cells.item:SetText(KM.ItemText(e.id))
    cells.qty:SetText(KM.Commas(e.q))
    cells.value:SetText(KM.Money(e.v))
end

local function openSession(s)
    local ids = {}
    for _, o in ipairs(Z.sessions.data or {}) do ids[#ids + 1] = o.id end
    P.order = ids               -- previous / next walk this place's sessions
    P.backTab = "zones"         -- and Back comes here (ns.ShowList)
    ns.ShowSession(s.id)
end

local function buildPlace(v)
    local pv = CreateFrame("Frame", nil, v)
    pv:SetAllPoints(v)
    pv:Hide()
    Z.placeView = pv
    Z.back = UI.Button(pv, "< All places", 96, 22, function() ns.ShowPlace(nil) end)
    Z.back:SetPoint("TOPLEFT", 0, -32)
    Z.title = UI.Text(pv, 14, C.text)
    Z.title:SetPoint("LEFT", Z.back, "RIGHT", 12, 0)
    Z.what = UI.Text(pv, 10, C.muted, "RIGHT")
    Z.what:SetPoint("LEFT", Z.title, "RIGHT", 12, 0)
    Z.what:SetPoint("RIGHT", pv, "RIGHT", 0, 0)
    Z.ptileRow, Z.ptiles = ns.MakeTiles(pv, -62)
    local T = Z.ptiles
    T[1]:SetTip(function(tt) tt:AddLine("Coin plus loot from every session here.", 1, 1, 1, true) end)
    T[2]:SetTip(function(tt) tt:AddLine("All it made over all its active time. The line under it compares with your farming everywhere in this period.", 1, 1, 1, true) end)
    T[3]:SetTip(function(tt) tt:AddLine("Active time here: paused and idle time left out.", 1, 1, 1, true) end)
    T[4]:SetTip(function(tt) tt:AddLine("Saved sessions here in this period.", 1, 1, 1, true) end)
    T[5]:SetTip(function(tt) tt:AddLine("Your best gold per hour in one session here (10+ active minutes). Its date is under it.", 1, 1, 1, true) end)
    T[6]:SetTip(function(tt) tt:AddLine("Mobs killed (or corpses looted, when more) per active hour here.", 1, 1, 1, true) end)

    local panel = UI.Panel(pv, C.panel)
    panel:SetPoint("TOPLEFT", 0, -130)
    panel:SetPoint("TOPRIGHT", 0, -130)
    panel:SetHeight(112)
    local h = UI.Heading(panel, "Gold per hour, each session here")
    h:SetPoint("TOPLEFT", 10, -8)
    Z.chart = UI.Chart(panel, 740, 84)
    Z.chart.frame:SetPoint("TOPLEFT", 6, -24)

    Z.sessHead = UI.Heading(pv, "Sessions")
    Z.sessHead:SetPoint("TOPLEFT", 0, -250)
    Z.sessions = UI.Table(pv, S_COLS, 20, { onClick = function(s, button, row)
        if button == "RightButton" then ns.SessionMenu(row, s.id) else openSession(s) end
    end })
    Z.sessions:SetPoint("TOPLEFT", 0, -266)
    Z.sessions:SetPoint("BOTTOMLEFT", 0, 18)
    Z.sessions:SetWidth(450)
    Z.sessions:SetSort("date", true)
    Z.sessions.emptyText = "No sessions here in this period."
    Z.itemHead = UI.Heading(pv, "Top items here")
    Z.items = UI.Table(pv, I_COLS, 20, { icon = true })
    Z.items:SetPoint("TOPLEFT", Z.sessions, "TOPRIGHT", 10, 0)
    Z.items:SetPoint("BOTTOMRIGHT", 0, 18)
    Z.itemHead:SetPoint("BOTTOMLEFT", Z.items, "TOPLEFT", 0, 4)
    Z.items:SetSort("value", true)
    Z.items.emptyText = "Coin only."
    Z.pfooter = UI.Text(pv, 10, C.dim)
    Z.pfooter:SetPoint("BOTTOMLEFT", 0, 2)
end

local function pct(a, b)
    if not (a and b) or b <= 0 then return nil end
    return (a - b) / b * 100
end

local function refreshPlace(w, key)
    if w ~= Z.pwidth then
        Z.pwidth = w
        ns.LayoutTiles(Z.ptiles, w)
        Z.chart:SetSize(math.max(300, w - 12), 84)
        Z.sessions:SetWidth(math.max(300, math.floor((w - 10) * 0.62)))
    end
    local list = ns.SessionsSince(ns.Since(), ns.CharFilter())
    local p
    for _, x in ipairs(ns.Places(list)) do if x.key == key then p = x end end
    local sessions = ns.PlaceSessions(list, key)
    Z.place, Z.placeSessions = p, sessions
    local everywhere = ns.Aggregate(list, U().revalue)
    local T = Z.ptiles
    if not p then
        -- nothing here in this period (the period or the character changed): say so, keep the way back
        local name = select(2, ns.Place(ns.Find(Z.lastID or -1) or {})) or "This place"
        Z.title:SetText(name)
        Z.what:SetText("")
        for i = 1, 6 do T[i]:Set(({ "Farmed", "Gold/hr", "Time", "Sessions", "Best", "Mobs/hr" })[i], "-", "") end
    else
        Z.title:SetText(p.name .. "  " .. kindText(p.kind))
        local farms = ns.Farms(sessions)
        local parts = {}
        for _, f in ipairs(farms) do
            parts[#parts + 1] = f.label .. " " .. f.n .. "x" .. (f.gph and (" " .. KM.Money(f.gph, true) .. "/hr") or "")
        end
        Z.what:SetText(table.concat(parts, "   "))
        T[1]:Set("Farmed", KM.Money(p.value), p.top and ("most from " .. (KM.Item(p.top).name or ("Item " .. p.top))) or "coin")
        T[2]:Set("Gold/hr", p.gph and KM.Money(p.gph) or "-",
            (p.gph and everywhere.gph) and ns.Delta(pct(p.gph, everywhere.gph), "vs everywhere") or "10+ active minutes")
        T[3]:Set("Time", ns.Dur(p.act), "active time")
        T[4]:Set("Sessions", tostring(p.n), p.last > 0 and ("last " .. (ns.Date("%d %b", p.last) or "")) or "")
        T[5]:Set("Best", p.best and (KM.Money(p.best) .. "/hr") or "-", p.bestS and (ns.Date("%d %b", p.bestS.t1) or "") or "10+ active minutes")
        T[6]:Set("Mobs/hr", p.mph and string.format("%.0f", p.mph) or "-", math.max(p.kills, p.corpses) .. " mobs")
        Z.lastID = sessions[1] and sessions[1].id or Z.lastID
    end

    local chrono = {}
    for _, s in ipairs(sessions) do chrono[#chrono + 1] = s end
    table.sort(chrono, function(a, b) return (a.t1 or 0) < (b.t1 or 0) end)
    local pts = {}
    for i, s in ipairs(chrono) do
        local t = ns.Totals(s, U().revalue)
        local _, activity = ns.ActivityText(s)
        pts[#pts + 1] = { i, t.gph or 0, ns.ACTIVITY_COLOR[activity] or C.dim, s }
    end
    Z.chart:Draw({
        tmin = 0.5, tmax = #chrono + 0.5,
        series = { { pts = pts, style = "bars", agg = "none" } },
        format = function(y) return KM.Money(y, true) end,
        xformat = function(x)
            local s = chrono[math.max(1, math.min(#chrono, math.floor(x + 0.5)))]
            return s and ns.Date("%d %b", s.t1) or ""
        end,
        ref = (p and p.gph) and { y = p.gph, label = "here " .. KM.Money(p.gph, true) } or nil,
        hover = function(_, pt)
            local s = pt and pt[4]
            if not s then return end
            GameTooltip:AddLine(ns.SessionTitle(s), 1, 1, 1)
            GameTooltip:AddLine(ns.SessionLine(s), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Click to open it.", 0.6, 0.6, 0.6)
        end,
        click = function(_, pt) if pt and pt[4] then openSession(pt[4]) end end,
        emptyText = "No sessions here in this period",
    })
    Z.chartSessions = chrono
    Z.sessions:SetRows(sessions, fillSession)
    Z.items:SetRows(ns.TopItems(sessions), fillItem)
    Z.pfooter:SetText(#sessions > 0 and "Click a session (or a bar) for its details; Back comes here. Right-click to rename, keep or delete." or "")
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

function ns.BuildZones(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetAllPoints(c)
    v:Hide()
    P.zones = v
    Z.frame = v
    buildList(v)
    buildPlace(v)
end

function ns.RefreshZones(c)
    local w = (c and c:GetWidth()) or 763
    local key = P.place
    Z.listView:SetShown(not key)
    Z.placeView:SetShown(key and true or false)
    if key then refreshPlace(w, key) else refreshList(w) end
end

-- Opens one place on the Zones tab (nil: back to the list of places).
function ns.ShowPlace(key)
    P.place = key
    P.view = "list"
    if ns.db then U().tab = "zones" end
    if KM.IsShown("farming") then KM.Refresh("farming") else KM.Show("farming") end
end
