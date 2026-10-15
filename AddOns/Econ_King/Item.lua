local _, ns = ...

-- An item's page: where its price and supply stand now, how they've moved,
-- and two graphs over time: market price (with the lowest buyout) and how
-- many are listed (with how many left the auction house between Deep Scans).
-- Back returns to the list; the arrows step through the list without leaving.

local DAY = 86400
local RANGES = { { 7, "7D" }, { 30, "30D" }, { 90, "90D" }, { 365, "1Y" }, { 0, "All" } }

local view, back, prevBtn, nextBtn, pos, icon, name, kind, star, starLabel
local cells, rangeButtons, priceGraph, supplyGraph, priceLegend, supplyLegend, note
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
}

local function format(kindOf, v)
    if kindOf == "money" then return ns.Money(v) end
    if kindOf == "pct" then return ns.Percent(v) end
    if kindOf == "pctDown" then return ns.Percent(v, true) end
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
    local starTex = star:GetNormalTexture()
    if starTex then starTex:SetAlpha(ns.db.fav[id] and 1 or 0.2) end
    starLabel:SetText(ns.db.fav[id] and "Favorite" or "Add to favorites")
    local list = ns.CurrentList()
    if index and list[index] and list[index].id == id then
        pos:SetText(index .. " of " .. #list)
        prevBtn:SetEnabled(index > 1)
        nextBtn:SetEnabled(index < #list)
    else
        pos:SetText("")
        prevBtn:SetEnabled(false)
        nextBtn:SetEnabled(false)
    end

    local s = ns.Stats(id) or {}
    for r, line in ipairs(GRID) do
        for c, cell in ipairs(line) do
            cells[r][c]:SetText(format(cell[3], s[cell[2]]))
        end
    end

    series = ns.Series(id)
    local now = ns.Now()
    local tmin = range > 0 and (now - range * DAY) or ((series[1] and series[1][F.T]) or now) - DAY / 2
    local tmax = now
    for _, b in ipairs(rangeButtons) do
        if b.days == range then b:LockHighlight() else b:UnlockHighlight() end
    end
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
            { pts = market, color = { 1, 0.82, 0 }, style = "line" },
            { pts = lowest, color = { 0.6, 0.6, 0.6, 0.8 }, style = "line" },
        },
    })
    local supplySeries = { { pts = listed, color = { 0.3, 0.6, 1, 0.85 }, style = "bars" } }
    if #gone > 0 then table.insert(supplySeries, { pts = gone, color = { 1, 0.35, 0.3 }, style = "line" }) end
    supplyGraph:Draw({
        tmin = tmin, tmax = tmax, zero = true, format = units, hover = hoverLines,
        emptyText = #series == 0 and "No scans of this item yet" or nil,
        series = supplySeries,
    })
    supplyLegend:SetText("|cff4d99ffListed|r" .. (#gone > 0 and "   |cffff5a4dGone (sold, cancelled or expired)|r" or ""))
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

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function ns.CreateItemView(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    view:Hide()

    back = button(view, "< Back", 70, function() ns.ShowList() end)
    back:SetPoint("TOPLEFT", 0, 0)
    prevBtn = button(view, "<", 26, function() step(-1) end)
    prevBtn:SetPoint("LEFT", back, "RIGHT", 6, 0)
    nextBtn = button(view, ">", 26, function() step(1) end)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    pos = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pos:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)

    icon = view:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 0, -28)
    name = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    kind = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    kind:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)

    star = CreateFrame("Button", nil, view)
    star:SetSize(18, 18)
    star:SetPoint("TOPRIGHT", -110, -2)
    star:SetNormalTexture(ns.STAR)
    star:SetScript("OnClick", function() if current then ns.SetFavorite(current, not ns.db.fav[current]) end end)
    starLabel = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    starLabel:SetPoint("LEFT", star, "RIGHT", 4, 0)
    local link = button(view, "Link", 50, function()
        local l = current and ns.LinkFor(current)
        if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end
    end)
    link:SetPoint("TOPRIGHT", -110, -24)
    local ask = button(view, "Ask guild", 80, function() if current then ns.AskGuild({ current }) end end)
    ask:SetPoint("LEFT", link, "RIGHT", 4, 0)
    ask:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Ask guildmates running Scanner King for their latest price of this item.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ask:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Numbers: four columns of four
    cells = {}
    for r, line in ipairs(GRID) do
        cells[r] = {}
        for c, cell in ipairs(line) do
            local x, y = (c - 1) * 164, -68 - (r - 1) * 26
            local label = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetPoint("TOPLEFT", x, y)
            label:SetText(cell[1])
            local value = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            value:SetPoint("TOPLEFT", x, y - 11)
            cells[r][c] = value
        end
    end

    -- Range
    rangeButtons = {}
    local prev
    for i = #RANGES, 1, -1 do
        local r = RANGES[i]
        local b = button(view, r[2], 44, function(self) range = self.days; ns.RefreshItem() end)
        b.days = r[1]
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -2, 0) else b:SetPoint("TOPRIGHT", 0, -176) end
        prev = b
        table.insert(rangeButtons, b)
    end

    local priceTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priceTitle:SetPoint("TOPLEFT", 0, -180)
    priceTitle:SetText("Market price")
    priceLegend = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    priceLegend:SetPoint("LEFT", priceTitle, "RIGHT", 12, 0)
    priceLegend:SetText("|cffffd100Market|r   |cff999999Lowest buyout|r")
    priceGraph = ns.CreateGraph(view, 660, 150)
    priceGraph.frame:SetPoint("TOPLEFT", 0, -198)

    local supplyTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supplyTitle:SetPoint("TOPLEFT", 0, -354)
    supplyTitle:SetText("Supply")
    supplyLegend = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    supplyLegend:SetPoint("LEFT", supplyTitle, "RIGHT", 12, 0)
    supplyGraph = ns.CreateGraph(view, 660, 100)
    supplyGraph.frame:SetPoint("TOPLEFT", 0, -372)

    note = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 0, -478)
    note:SetWidth(660)
    note:SetJustifyH("LEFT")
end
