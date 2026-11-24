local _, KM = ...
local ns = KM.Module("Tracker")
local UI = KM.UI
local C = UI.C

-- The Farming Ledger's Trends tab and its export (King Maker 2.6.2; the Mat Prices tab was removed in 2.18.0):
--   Trends      six tiles, farmed per day (one bar a day), Best farms (a zone and what you did there, time-weighted
--               gold per hour; click one to see only its sessions) and the top items farmed
--   Export      the sessions shown as comma-separated text (UI.Window, Ctrl+C), also /farm export
-- Carried-over sessions (legacy, act = 0) never count in a trend or a rate. The tab lays out from the container's
-- size (the window zooms), like the Sessions tab.

local P = ns.P
local T = {}          -- Trends frames
ns.T = T              -- (tests)
local DAY = 86400
local BEST_MIN = 600  -- a farm's gold per hour needs 10 active minutes in all
local DASH = "|cff808080-|r"

local function U() return ns.db.ui end

local function pctText(frac)
    if frac <= 0 then return "" end
    if frac < 0.01 then return "<1%" end
    return math.floor(frac * 100 + 0.5) .. "%"
end

local function colOf(cols, key) for _, c in ipairs(cols) do if c.key == key then return c end end end

local function shareBar(r, col, frac, color)
    if not r.bar then
        r.bar = UI.Bar(r, 6)
        r.bar:SetWidth(60)
    end
    r.bar:ClearAllPoints()
    r.bar:SetPoint("LEFT", r, "LEFT", col.x + 36, 0)
    r.bar:Set(frac, color)
end

---------------------------------------------------------------------------
-- The numbers (no frames: tests and the export read these)
---------------------------------------------------------------------------

-- Sessions that count in a trend: not carried over, with real active time.
local function counted(list)
    local out = {}
    for _, s in ipairs(list) do if not s.legacy and (s.act or 0) > 0 then out[#out + 1] = s end end
    return out
end
ns.TrendSessions = counted

local function dayKey(t) return ns.Date("%Y-%m-%d", t) or tostring(math.floor(t / DAY)) end

-- Farmed per day from `from` (server time; nil = the oldest session) to now, one entry a day, empty days included:
-- { { t (midday), key, value, act, n }, ... } oldest first.
function ns.Days(list, from)
    list = counted(list)
    local now = KM.Now()
    if not from then
        from = now
        for _, s in ipairs(list) do from = math.min(from, s.t1 or now) end
    end
    local by = {}
    for _, s in ipairs(list) do
        local k = dayKey(s.t1 or now)
        local d = by[k]
        if not d then d = { value = 0, act = 0, n = 0 }; by[k] = d end
        d.value = d.value + (U().revalue and ns.ValueNow(s) or (s.value or 0))
        d.act = d.act + (s.act or 0)
        d.n = d.n + 1
    end
    local days, seen = {}, {}
    local t = from - (from % DAY) + DAY / 2
    while t <= now + DAY / 2 do
        local k = dayKey(t)
        if not seen[k] then
            seen[k] = true
            local d = by[k] or { value = 0, act = 0, n = 0 }
            days[#days + 1] = { t = t, key = k, value = d.value, act = d.act, n = d.n }
        end
        t = t + DAY
    end
    return days
end

-- Best farms: one row per zone and activity, gold per hour over all their active time (time-weighted), best first.
-- { key, map, where (the place's name: a zone, dungeon or raid), kind, label, n, act, value, gph (nil under 10 minutes),
--   corpses, kills, best }
function ns.Farms(list)
    local by, out = {}, {}
    for _, s in ipairs(counted(list)) do
        local key, label = ns.FarmKey(s)
        if key then
            local f = by[key]
            if not f then
                local _, where, kind = ns.Place(s)
                f = { key = key, map = ns.MainZone(s), where = where, kind = kind, label = label, n = 0, act = 0, value = 0, corpses = 0, kills = 0 }
                by[key] = f
                out[#out + 1] = f
            end
            local v = U().revalue and ns.ValueNow(s) or (s.value or 0)
            f.n, f.act, f.value = f.n + 1, f.act + (s.act or 0), f.value + v
            f.kills = f.kills + (s.kills or 0)
            -- corpses looted: kills can be 0 when Farm's kill detection missed them, the corpses are still there
            f.corpses = f.corpses + ((s.src and s.src.mob and s.src.mob.n) or 0)
            if (s.act or 0) >= BEST_MIN then
                local g = v / s.act * 3600
                if not f.best or g > f.best then f.best = g end
            end
        end
    end
    for _, f in ipairs(out) do f.gph = f.act >= BEST_MIN and f.value / f.act * 3600 or nil end
    table.sort(out, function(a, b)
        if (a.gph or -1) ~= (b.gph or -1) then return (a.gph or -1) > (b.gph or -1) end
        return a.key < b.key
    end)
    return out
end

-- The items farmed most (by value), with each one's share of all item value: { id, q, v, frac }.
function ns.TopItems(list)
    local by, out, total = {}, {}, 0
    for _, s in ipairs(counted(list)) do
        for id, it in pairs(s.items or {}) do
            local v = U().revalue and (it.q or 0) * (KM.ItemValue(id) or 0) or (it.v or 0)
            local e = by[id]
            if not e then e = { id = id, q = 0, v = 0 }; by[id] = e; out[#out + 1] = e end
            e.q, e.v = e.q + (it.q or 0), e.v + v
            total = total + v
        end
    end
    for _, e in ipairs(out) do e.frac = total > 0 and e.v / total or 0 end
    table.sort(out, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.id < b.id end)
    return out
end

local function sumSince(from, to, char)
    local v, act = 0, 0
    for _, s in ipairs(counted(ns.SessionsSince(from, char))) do
        if (s.t1 or 0) < to then v, act = v + (U().revalue and ns.ValueNow(s) or (s.value or 0)), act + (s.act or 0) end
    end
    return v, act
end

---------------------------------------------------------------------------
-- Trends tab
---------------------------------------------------------------------------

local FARM_COLS = {
    { key = "zone", label = "Zone", w = 150, sort = function(e) return (e.where or ""):lower() end, desc = false },
    { key = "what", label = "Activity", w = 96, sort = function(e) return e.label end, desc = false },
    { key = "n", label = "Sess", tip = "Sessions at this farm.", w = 44, justify = "RIGHT", sort = function(e) return e.n end },
    { key = "act", label = "Time", tip = "Active time farmed there, all sessions together.", w = 64, justify = "RIGHT", sort = function(e) return e.act end },
    { key = "gph", label = "G/hr", tip = "All it made over all its active time (a long session counts for more than a short one). Blank under 10 active minutes in all.", w = 0, justify = "RIGHT", sort = function(e) return e.gph or -1 end },
}

local ITEM_COLS = {
    { key = "item", label = "Item", w = 132, sort = function(e) return KM.Item(e.id).name or "" end, desc = false },
    { key = "qty", label = "Qty", w = 50, justify = "RIGHT", sort = function(e) return e.q end },
    { key = "value", label = "Value", w = 76, justify = "RIGHT", sort = function(e) return e.v end },
    { key = "share", label = "Share", tip = "Its part of all the items farmed in this period.", w = 0 },
}

local function fillFarm(r, f, cells)
    cells.zone:SetText(f.where)
    cells.what:SetText(UI.Hex(C.muted) .. f.label .. "|r")
    cells.n:SetText(f.n)
    cells.act:SetText(ns.Dur(f.act))
    cells.gph:SetText(f.gph and KM.Money(f.gph) or DASH)
    r.tip = function(tt)
        tt:AddLine(f.where .. ", " .. f.label, 1, 1, 1)
        tt:AddDoubleLine("Farmed", KM.Money(f.value), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Active time", ns.Dur(f.act), 0.8, 0.8, 0.8, 1, 1, 1)
        if f.best then tt:AddDoubleLine("Best session", KM.Money(f.best) .. "/hr", 0.8, 0.8, 0.8, 1, 1, 1) end
        local mobs = math.max(f.kills, f.corpses)
        if mobs > 0 and f.act >= 60 then
            tt:AddDoubleLine("Mobs per hour", string.format("%.0f", mobs / f.act * 3600), 0.8, 0.8, 0.8, 1, 1, 1)
            if f.corpses > f.kills then tt:AddLine("Counted by corpses looted: some kills weren't seen.", 0.6, 0.6, 0.6, true) end
        end
        tt:AddLine("Click to see only these sessions.", 0.6, 0.6, 0.6)
    end
end

local function fillTop(r, e, cells)
    if r.icon then r.icon:SetTexture(KM.Item(e.id).icon) end
    r.item = e.id
    cells.item:SetText(KM.ItemText(e.id))
    cells.qty:SetText(KM.Commas(e.q))
    cells.value:SetText(KM.Money(e.v))
    cells.share:SetText(pctText(e.frac))
    shareBar(r, colOf(ITEM_COLS, "share"), e.frac, C.accent)
end

function ns.BuildTrends(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetAllPoints(c)
    v:Hide()
    P.trends = v
    T.frame = v
    T.tileRow, T.tiles = ns.MakeTiles(v, -32)
    local function scope(tt)
        tt:AddLine((U().mine and "This character" or "Every character") .. ", this period. Carried-over sessions aren't counted.", 0.6, 0.6, 0.6, true)
    end
    T.tiles[1]:SetTip(function(tt) tt:AddLine("Coin plus loot from your sessions in this period.", 1, 1, 1, true); scope(tt) end)
    T.tiles[2]:SetTip(function(tt) tt:AddLine("All farmed gold over all active time, so a long session counts for more than a short one. The line under it compares with the same number of days before.", 1, 1, 1, true); scope(tt) end)
    T.tiles[3]:SetTip(function(tt) tt:AddLine("Active time: paused and idle time left out.", 1, 1, 1, true); scope(tt) end)
    T.tiles[4]:SetTip(function(tt) tt:AddLine("Your best farm (a zone and what you did there) by gold per hour, with at least 10 active minutes in all.", 1, 1, 1, true); scope(tt) end)
    T.tiles[5]:SetTip(function(tt) tt:AddLine("The item that made the most in this period, and how many you farmed.", 1, 1, 1, true); scope(tt) end)
    T.tiles[6]:SetTip(function(tt)
        tt:AddLine("Farmed in the last 7 days, against the 7 days before them (whatever the period above).", 1, 1, 1, true)
        tt:AddDoubleLine("Last 7 days", KM.Money(T.week or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("The 7 before", KM.Money(T.lastWeek or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    end)

    local panel = UI.Panel(v, C.panel)
    panel:SetPoint("TOPLEFT", 0, -100)
    panel:SetPoint("TOPRIGHT", 0, -100)
    panel:SetHeight(124)
    local h = UI.Heading(panel, "Farmed per day")
    h:SetPoint("TOPLEFT", 10, -8)
    T.chart = UI.Chart(panel, 740, 96)
    T.chart.frame:SetPoint("TOPLEFT", 6, -24)

    T.farmHead = UI.Heading(v, "Best farms")
    T.farmHead:SetPoint("TOPLEFT", 0, -236)
    T.farms = UI.Table(v, FARM_COLS, 20, {
        onClick = function(f)
            P.farm = { key = f.key, label = f.where .. ", " .. f.label }
            U().tab = "sessions"
            KM.Refresh("farming")
        end,
    })
    T.farms:SetPoint("TOPLEFT", 0, -252)
    T.farms:SetPoint("BOTTOMLEFT", 0, 18)
    T.farms:SetWidth(450)
    T.farms:SetSort("gph", true)
    T.farms.emptyText = "No farms yet: sessions show here once saved."
    T.itemHead = UI.Heading(v, "Top items farmed")
    T.items = UI.Table(v, ITEM_COLS, 20, { icon = true })
    T.items:SetPoint("TOPLEFT", T.farms, "TOPRIGHT", 10, 0)
    T.items:SetPoint("BOTTOMRIGHT", 0, 18)
    T.itemHead:SetPoint("BOTTOMLEFT", T.items, "TOPLEFT", 0, 4)
    T.items:SetSort("value", true)
    T.items.emptyText = "Nothing farmed in this period."
    T.footer = UI.Text(v, 10, C.dim)
    T.footer:SetPoint("BOTTOMLEFT", 0, 2)
end

local function pct(a, b)
    if not (a and b) or b <= 0 then return nil end
    return (a - b) / b * 100
end

function ns.RefreshTrends(c)
    local u = U()
    local w = (c and c:GetWidth()) or 763
    if w ~= T.width then
        T.width = w
        ns.LayoutTiles(T.tiles, w)
        T.chart:SetSize(math.max(300, w - 12), 96)
        T.farms:SetWidth(math.max(300, math.floor((w - 10) * 0.596)))
    end
    local list = ns.SessionsSince(ns.Since(), ns.CharFilter())
    local a = ns.Aggregate(list, u.revalue)
    local farms = ns.Farms(list)
    local items = ns.TopItems(list)
    T.list, T.farmRows, T.itemRows = list, farms, items
    local prevA
    if (u.period or 30) > 0 then
        local prev = {}
        for _, s in ipairs(ns.SessionsSince(KM.Now() - 2 * u.period * DAY, ns.CharFilter())) do
            if (s.t1 or 0) < KM.Now() - u.period * DAY then prev[#prev + 1] = s end
        end
        prevA = ns.Aggregate(prev, u.revalue)
    end
    local best
    for _, f in ipairs(farms) do if f.gph and (not best or f.gph > best.gph) then best = f end end
    local now = KM.Now()
    T.week = sumSince(now - 7 * DAY, now + 1, ns.CharFilter())
    T.lastWeek = sumSince(now - 14 * DAY, now - 7 * DAY, ns.CharFilter())
    local TT = T.tiles
    TT[1]:Set("Farmed", KM.Money(a.value), KM.Money(a.coin, true) .. " coin")
    TT[2]:Set("Avg gold/hr", a.gph and KM.Money(a.gph) or "-",
        prevA and prevA.gph and a.gph and ns.Delta(pct(a.gph, prevA.gph), "vs the " .. u.period .. " days before") or "time-weighted")
    TT[3]:Set("Time farmed", ns.Dur(a.act), a.n .. " session" .. (a.n == 1 and "" or "s"))
    TT[4]:Set("Best zone", best and best.where or "-", best and (KM.Money(best.gph, true) .. "/hr  " .. best.label) or "10+ active minutes")
    local top = items[1]
    TT[5]:Set("Top item", top and (KM.Item(top.id).name or ("Item " .. top.id)) or "-", top and (KM.Money(top.v, true) .. " from " .. KM.Commas(top.q)) or "")
    TT[6]:Set("This week", KM.Money(T.week), T.lastWeek > 0 and ns.Delta(pct(T.week, T.lastWeek), "vs last week") or "nothing the week before")

    local days = ns.Days(list, ns.Since())
    T.days = days
    local pts = {}
    for _, d in ipairs(days) do pts[#pts + 1] = { d.t, d.value, nil, d } end
    T.chart:Draw({
        series = { { pts = pts, style = "bars", color = C.accent, agg = "sum" } },
        tmin = days[1] and days[1].t - DAY / 2 or nil, tmax = days[#days] and days[#days].t + DAY / 2 or nil,
        format = function(y) return KM.Money(y, true) end,
        xformat = function(x) return ns.Date("%d %b", x) or "" end,
        hover = function(x, p)
            local d = p and p[4]
            GameTooltip:AddLine(ns.Date("%a %d %b", x) or "", 1, 1, 1)
            if not d then return end
            GameTooltip:AddDoubleLine("Farmed", KM.Money(d.value), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Time farmed", ns.Dur(d.act), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gold per hour", d.act >= 60 and (KM.Money(d.value / d.act * 3600) .. "/hr") or "-", 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Sessions", tostring(d.n), 0.8, 0.8, 0.8, 1, 1, 1)
        end,
        emptyText = "Nothing farmed in this period yet",
    })
    T.farms:SetRows(farms, fillFarm)
    T.items:SetRows(items, fillTop)
    T.footer:SetText(#farms > 0 and "Click a farm to see only its sessions. Carried-over sessions aren't counted." or "")
end

---------------------------------------------------------------------------
-- Export: the sessions shown, as comma-separated text for a spreadsheet (the Sales Ledger's window)
---------------------------------------------------------------------------

-- A CSV field: quoted when it holds a comma, a quote or a line break (quotes doubled). Colour codes are stripped.
local function csv(v)
    if v == nil then return "" end
    v = tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if v:find('[,"\r\n]') then return '"' .. v:gsub('"', '""') .. '"' end
    return v
end
ns.CSV = csv

local HEADER = "start,end,character,level,zone,name,activity,active_sec,idle_sec,paused_sec,farmed_copper,coin_copper,"
    .. "items_copper,gold_per_hour_copper,kills,corpses_looted,deaths,gathered,costs_copper,net_copper,wallet_copper,"
    .. "containers_opened,carried_over,kept,auto"

-- The text and how many sessions it holds; list defaults to what the Sessions tab shows (oldest first in the text).
function ns.ExportText(list)
    list = list or ns.ListSessions()
    local lines = { HEADER }
    for i = #list, 1, -1 do
        local s = list[i]
        local t = ns.Totals(s)
        local _, activity, label = ns.ActivityText(s)
        local opened = 0
        for _, n in pairs(s.opened or {}) do opened = opened + n end
        lines[#lines + 1] = table.concat({
            csv(ns.Date("%Y-%m-%d %H:%M", s.t0)), csv(ns.Date("%Y-%m-%d %H:%M", s.t1)), csv(s.c), s.lvl or "",
            csv(ns.PlaceName(s)), csv(s.name), csv(activity == "none" and "" or label),
            math.floor(s.act or 0), math.floor(s.idle or 0), math.floor(s.paused or 0),
            math.floor(s.value or 0), math.floor(s.coin or 0), math.floor(s.iv or 0),
            t.gph and math.floor(t.gph + 0.5) or "", s.kills or 0, (s.src and s.src.mob and s.src.mob.n) or 0,
            s.deaths or 0, ns.Gathered(s), math.floor(t.costs), math.floor(t.net), t.wallet or "", opened,
            s.legacy and 1 or 0, s.star and 1 or 0, s.auto and 1 or 0,
        }, ",")
    end
    return table.concat(lines, "\n"), #list
end

local exportWin

local function exportWindow(text, n)
    if not exportWin then
        exportWin = UI.Window("KingMakerFarmingExport", "Farming Ledger export", 640, 400)
        local hint = UI.Text(exportWin.body, 11, C.muted)
        hint:SetPoint("TOPLEFT", 0, 0)
        hint:SetText("Press Ctrl+A, then Ctrl+C, and paste it into a spreadsheet. Money is in copper, times in seconds.")
        local box = UI.Panel(exportWin.body, { 0, 0, 0, 0.35 })
        box:SetPoint("TOPLEFT", 0, -20)
        box:SetPoint("BOTTOMRIGHT", 0, 0)
        local sc = UI.Scroll(box)
        sc:SetPoint("TOPLEFT", 8, -6)
        sc:SetPoint("BOTTOMRIGHT", -8, 6)
        local eb = CreateFrame("EditBox", nil, sc.child)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetPoint("TOPLEFT", 0, 0)
        eb:SetWidth(592)
        eb:SetScript("OnEscapePressed", function() exportWin:Hide() end)
        box:EnableMouse(true)
        box:SetScript("OnMouseDown", function() eb:SetFocus() end)
        exportWin.box, exportWin.scroll = eb, sc
    end
    exportWin:SetTitle("Farming Ledger export: " .. n .. " session" .. (n == 1 and "" or "s"))
    local eb = exportWin.box
    eb:SetText(text)
    local _, lines = text:gsub("\n", "\n")
    local h = (lines + 1) * 14 + 10
    eb:SetHeight(h)
    exportWin.scroll:SetContentHeight(h)
    exportWin.scroll:SetPos(0)
    exportWin:Show()
    if eb.HighlightText then eb:HighlightText(); eb:SetFocus() end
    return exportWin
end

function ns.Export()
    if not ns.db then return end
    local text, n = ns.ExportText()
    exportWindow(text, n)
    KM.Print(ns, "exported " .. n .. " farming session" .. (n == 1 and "" or "s") .. ".")
end
