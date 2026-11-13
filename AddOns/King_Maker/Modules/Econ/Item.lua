local _, KM = ...
local ns = KM.Module("Econ")
local UI = KM.UI
local C = UI.C

-- An item's page, drawn inside the Price History page where the list was: where its price and supply stand
-- now (a card of twenty numbers), how they've moved, and two graphs over time: market price (with the lowest
-- buyout) and how many are listed (with how many left the auction house between Deep Scans).
-- Back returns to the list; the arrows step through the list without leaving.

local DAY = 86400
local RANGES = { { 7, "7D" }, { 30, "30D" }, { 90, "90D" }, { 365, "1Y" }, { 0, "All" } }

local W = 592                   -- the page is ~764 wide; the category list takes the rest
local view, back, prevBtn, nextBtn, pos, icon, name, kind, star, starLabel
local cells, rangeTabs, priceGraph, supplyGraph, priceLegend, supplyLegend, note
local current, index
local range = 30
local series = {}

local F = ns.F

local function units(v)
    if not v then return "|cff808080-|r" end
    if v >= 100 then return tostring(math.floor(v + 0.5)) end
    return (string.format("%.1f", v):gsub("%.0$", ""))
end

local GRID = {
    { { "Market price", "market", "money" }, { "Lowest buyout", "lowest", "money" }, { "Listed now", "listed", "units" }, { "Auctions", "auctions", "units" } },
    { { "7-day average", "avg7", "money" }, { "30-day average", "avg30", "money" }, { "Now vs 30-day", "vs30", "pctDown" }, { "7-day trend", "trend7", "pct" } },
    { { "30-day low", "low30", "money" }, { "30-day high", "high30", "money" }, { "Volatility", "vol30", "vol" }, { "Avg listed (30d)", "listed30", "units" } },
    { { "Gone per day", "gonePerDay", "units" }, { "Supply vs 30-day", "supply", "pct" }, { "Tracking since", "first", "date" }, { "Scans behind it", "points", "units" } },
    { { "Avg listed (7d)", "listed7", "units" }, { "Supply vs 7-day", "supply7", "pct" }, { "Price vs supply", "corr", "corr" }, { "Last scanned", "seen", "ago" } },
}

local function format(kindOf, v)
    if kindOf == "money" then return ns.Money(v) end
    if kindOf == "pct" then return ns.Percent(v) end
    if kindOf == "pctDown" then return ns.Percent(v, true) end
    if kindOf == "corr" then
        if not v then return "|cff808080-|r" end
        local a = math.abs(v)
        local word = a >= 0.6 and "strong" or a >= 0.3 and "some" or "no link"
        return string.format("%+.2f", v) .. " |cffa0a0a0" .. word .. "|r"
    end
    if kindOf == "ago" then return v and ns.Age(v) or "|cff808080-|r" end
    if kindOf == "vol" then return v and ("+/-" .. math.floor(v * 100 + 0.5) .. "%") or "|cff808080-|r" end
    if kindOf == "date" then
        if not v then return "|cff808080-|r" end
        local d = date or (os and os.date)
        return d and d("%d %b %Y", v) or tostring(v)
    end
    return units(v)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function nearest(t)
    local best, bestD
    for _, v in ipairs(series) do
        local d = math.abs(v[F.T] - t)
        if not bestD or d < bestD then best, bestD = v, d end
    end
    return best
end

local function hoverLines(t)
    local v = nearest(t)
    if not v then return end
    local function line(l, r) GameTooltip:AddDoubleLine(l, r, 1, 0.82, 0, 1, 1, 1) end
    if v[F.M] then line("Market price", ns.Money(v[F.M])) end
    if v[F.P] then line("Lowest buyout", ns.Money(v[F.P])) end
    if v[F.Q] then line("Listed", units(v[F.Q]) .. (v[F.N] and (" in " .. units(v[F.N]) .. " auctions") or "")) end
    if v[F.A] then line("Newly listed", units(v[F.A])) end
    if v[F.R] then line("Gone (sold, cancelled or expired)", units(v[F.R])) end
    if (v[F.C] or 1) > 1 then GameTooltip:AddLine("Average of " .. v[F.C] .. " scans", 0.6, 0.6, 0.6) end
end

function ns.RefreshItem()
    if not current or not view:IsShown() then return end
    local id = current
    local info = ns.Info(id)
    icon:SetTexture(info.icon)
    name:SetText(ns.ColoredName(id))
    local cls, sc = ns.ClassOf(id)
    kind:SetText(ns.ClassName(cls) .. " - " .. ns.SubclassName(cls, sc))
    star.tex:SetAlpha(ns.db.fav[id] and 1 or 0.2)
    starLabel:SetText(ns.db.fav[id] and "Favorite" or "Add to favorites")
    local list = ns.CurrentList()
    if index and list[index] and list[index].id == id then
        pos:SetText(index .. " of " .. #list)
        prevBtn:SetEnabled2(index > 1)
        nextBtn:SetEnabled2(index < #list)
    else
        pos:SetText("")
        prevBtn:SetEnabled2(false)
        nextBtn:SetEnabled2(false)
    end

    local s = ns.Stats(id) or {}
    for r, line in ipairs(GRID) do
        for c, cell in ipairs(line) do
            local text = format(cell[3], s[cell[2]])
            if cell[2] == "trend7" and s.trendDays then text = text .. " |cffa0a0a0over " .. s.trendDays .. "d|r" end
            if cell[2] == "auctions" and s.auctions and s.auctionsAt and s.seen and s.auctionsAt < s.seen then
                text = text .. " |cffa0a0a0" .. ns.Age(s.auctionsAt) .. "|r"
            end
            cells[r][c]:SetText(text)
        end
    end

    series = ns.Series(id)
    local now = ns.Now()
    local tmin = range > 0 and (now - range * DAY) or ((series[1] and series[1][F.T]) or now) - DAY / 2
    local tmax = now
    rangeTabs:Select(range)
    local market, lowest, listed, gone = {}, {}, {}, {}
    for _, v in ipairs(series) do
        local t = v[F.T]
        if v[F.M] then table.insert(market, { t, v[F.M] }) end
        if v[F.P] then table.insert(lowest, { t, v[F.P] }) end
        if v[F.Q] then table.insert(listed, { t, v[F.Q] }) end
        if v[F.R] then table.insert(gone, { t, v[F.R] }) end
    end
    local moneyLabel = function(v) return ns.Money(v) end
    priceGraph:Draw({
        tmin = tmin, tmax = tmax, format = moneyLabel, hover = hoverLines,
        emptyText = #series == 0 and "No scans of this item yet" or nil,
        series = {
            { pts = market, color = C.accent, style = "line" },
            { pts = lowest, color = { C.muted[1], C.muted[2], C.muted[3], 0.8 }, style = "line" },
        },
    })
    local supplySeries = { { pts = listed, color = { C.info[1], C.info[2], C.info[3], 0.75 }, style = "bars" } }
    if #gone > 0 then table.insert(supplySeries, { pts = gone, color = C.bad, style = "line" }) end
    supplyGraph:Draw({
        tmin = tmin, tmax = tmax, zero = true, format = units, hover = hoverLines,
        emptyText = #series == 0 and "No scans of this item yet" or nil,
        series = supplySeries,
    })
    supplyLegend:SetText(UI.Hex(C.info) .. "Listed|r" .. (#gone > 0 and ("   " .. UI.Hex(C.bad) .. "Gone (sold, cancelled or expired)|r") or ""))
    note:SetText(s.lowestOnly and "No full Deep Scan has priced this in 30 days, so these figures use the lowest buyout. A Deep Scan gives the market price."
        or s.gonePerDay and "Gone = units that left the auction house between Deep Scans: sold, cancelled or expired. A rough measure of demand."
        or "Deep Scans less than two days apart also show how many units sold or were pulled.")
end

function ns.OpenItem(id, i)
    current, index = id, i
    view:Show()
    ns.RefreshItem()
end

function ns.HideItem()
    if view then view:Hide() end
end

local function step(d)
    local list = ns.CurrentList()
    if not index or not list[index + d] then return end
    index = index + d
    current = list[index].id
    ns.RefreshItem()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

function ns.CreateItemView(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    view:Hide()

    -- Top row: back and the arrows on the left; favorite, link and Ask guild on the right.
    back = UI.Button(view, "< Back", 70, 22, function() ns.ShowList() end, "ghost")
    back:SetPoint("TOPLEFT", 0, 0)
    prevBtn = UI.Button(view, "<", 26, 22, function() step(-1) end)
    prevBtn:SetPoint("LEFT", back, "RIGHT", 6, 0)
    nextBtn = UI.Button(view, ">", 26, 22, function() step(1) end)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    pos = UI.Text(view, 10, C.dim)
    pos:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)

    local ask = UI.Button(view, "Ask guild", 86, 22, function() if current then ns.AskGuild({ current }) end end)
    ask:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(ask, "Ask guildmates running King Maker (or Scanner King) for their latest price of this item.")
    local link = UI.Button(view, "Link", 54, 22, function()
        local l = current and ns.LinkFor(current)
        if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end
    end)
    link:SetPoint("RIGHT", ask, "LEFT", -6, 0)
    star = CreateFrame("Button", nil, view)
    star:SetSize(18, 18)
    star:SetPoint("RIGHT", link, "LEFT", -118, 0)
    star.tex = star:CreateTexture(nil, "ARTWORK")
    star.tex:SetAllPoints()
    star.tex:SetTexture(ns.STAR)
    star:SetScript("OnClick", function() if current then UI.Click(); ns.SetFavorite(current, not ns.db.fav[current]) end end)
    starLabel = UI.Text(view, 11, C.muted)
    starLabel:SetPoint("LEFT", star, "RIGHT", 5, 0)

    -- The item.
    icon = view:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 0, -32)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = CreateFrame("Frame", nil, view)
    ring:SetPoint("TOPLEFT", icon, -1, 1)
    ring:SetPoint("BOTTOMRIGHT", icon, 1, -1)
    UI.Border(ring, { 1, 1, 1, 0.14 })
    name = UI.Text(view, 15, C.text)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    name:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    kind = UI.Text(view, 10, C.muted)
    kind:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)

    -- Numbers: a card of four columns of five.
    local card = UI.Panel(view, C.panel)
    card:SetPoint("TOPLEFT", 0, -76)
    card:SetSize(W, #GRID * 30 + 12)
    local colW = (W - 24) / 4
    cells = {}
    for r, line in ipairs(GRID) do
        cells[r] = {}
        for c, cell in ipairs(line) do
            local x, y = 12 + (c - 1) * colW, -8 - (r - 1) * 30
            local label = UI.Text(card, 9, C.muted)
            label:SetPoint("TOPLEFT", x, y)
            label:SetText(cell[1]:upper())
            local value = UI.Text(card, 12, C.text)
            value:SetPoint("TOPLEFT", x, y - 12)
            value:SetWidth(colW - 8)
            cells[r][c] = value
        end
    end

    -- Range tabs and the price graph.
    local items = {}
    for i, r in ipairs(RANGES) do items[i] = { id = r[1], label = r[2], w = 44 } end
    rangeTabs = UI.Tabs(view, items, function(days) range = days; ns.RefreshItem() end, 20)
    rangeTabs:SetPoint("TOPRIGHT", 0, -248)

    local priceTitle = UI.Heading(view, "Market price")
    priceTitle:SetPoint("TOPLEFT", 0, -252)
    priceLegend = UI.Text(view, 10, C.muted)
    priceLegend:SetPoint("LEFT", priceTitle, "RIGHT", 12, 0)
    priceLegend:SetText(UI.Hex(C.accent) .. "Market|r   " .. UI.Hex(C.muted) .. "Lowest buyout|r")
    priceGraph = ns.CreateGraph(view, W, 112)
    priceGraph.frame:SetPoint("TOPLEFT", 0, -272)

    local supplyTitle = UI.Heading(view, "Supply")
    supplyTitle:SetPoint("TOPLEFT", 0, -394)
    supplyLegend = UI.Text(view, 10, C.muted)
    supplyLegend:SetPoint("LEFT", supplyTitle, "RIGHT", 12, 0)
    supplyGraph = ns.CreateGraph(view, W, 90)
    supplyGraph.frame:SetPoint("TOPLEFT", 0, -410)

    note = UI.Para(view, 10, C.dim, W)
    note:SetPoint("TOPLEFT", 0, -504)
end
