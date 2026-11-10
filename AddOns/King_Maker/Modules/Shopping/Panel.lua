local _, KM = ...
local ns = KM.Module("Shopping")
local UI = KM.UI
local C = UI.C

-- The panel at the auction house: our own frame docked to the right edge of AuctionHouseFrame (anchored to it,
-- never parented to it or changing it), shown while the auction house is open. The active list on top, each item
-- with a Search button; below, the selected item's buy flow (Buy / Confirm for commodities, one Buy per auction
-- for everything else). The "Shopping" toggle beside the auction house shows it again after it is closed.

local W, H = 300, 540
local ROWS, ROW_H = 9, 24
local AUCTION_ROWS = 5

local panel, toggle
local rows, offset = {}, 0
local d = {}          -- detail widgets
local list = {}       -- entries shown, sorted

local function anchorTo(frame, x, y)
    frame:ClearAllPoints()
    if AuctionHouseFrame then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", x or 2, y or 0)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
    end
end

local function sortedEntries()
    local out = {}
    for _, e in ipairs(ns.Entries(ns.Active()) or {}) do out[#out + 1] = e end
    local rank = { under = 1, nomax = 2, over = 3, noprice = 4, done = 5 }
    local st, nm = {}, {}
    for _, e in ipairs(out) do st[e] = rank[ns.Status(e)] or 9; nm[e] = ns.Name(e.id) end
    table.sort(out, function(a, b)
        if st[a] ~= st[b] then return st[a] < st[b] end
        return nm[a] < nm[b]
    end)
    return out
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function makeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 8, -66 - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    r.zebra = UI.Fill(r, C.zebra)
    r.zebra:SetShown(i % 2 == 0)
    r.good = UI.Fill(r, { C.good[1], C.good[2], C.good[3], 0.10 }, "ARTWORK")
    r.good:Hide()
    r.sel = UI.Fill(r, C.sel, "ARTWORK")
    r.sel:Hide()
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(ROW_H - 6, ROW_H - 6)
    r.icon:SetPoint("LEFT", 3, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = UI.Text(r, 11, C.text)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetWidth(118)
    r.price = UI.Text(r, 11, C.text, "RIGHT")
    r.price:SetPoint("RIGHT", -60, 0)
    r.price:SetWidth(80)
    r.search = UI.Button(r, "Search", 54, ROW_H - 4, function(self)
        if r.entry then ns.Select(r.entry.id, ns.Active()); ns.Search(r.entry.id, { select = true }) end
    end)
    r.search:SetPoint("RIGHT", 0, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self)
        if self.entry then UI.Click(); ns.Select(self.entry.id, ns.Active()) end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.id) end
        if self.entry.note then GameTooltip:AddLine(self.entry.note, 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function buildDetail(p)
    local top = -66 - ROWS * ROW_H - 10
    local line = p:CreateTexture(nil, "BORDER")
    line:SetTexture(UI.WHITE)
    UI.SetColor(line, C.border)
    line:SetPoint("TOPLEFT", 8, top + 4)
    line:SetPoint("TOPRIGHT", -8, top + 4)
    line:SetHeight(1)

    d.icon = p:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(28, 28)
    d.icon:SetPoint("TOPLEFT", 10, top - 4)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.name = UI.Text(p, 13, C.text)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, 0)
    d.name:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    d.info = UI.Text(p, 10, C.muted)
    d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.info:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    d.empty = UI.Para(p, 11, C.dim, W - 24)
    d.empty:SetPoint("TOPLEFT", 12, top - 8)
    d.empty:SetText("Click Search on an item to see its auctions and buy it here.")

    -- commodities: quantity, Buy, Confirm, Cancel, override
    local y = top - 44
    d.qtyLabel = UI.Text(p, 11, C.muted)
    d.qtyLabel:SetPoint("TOPLEFT", 12, y - 5)
    d.qtyLabel:SetText("Qty")
    d.qty = UI.NumberBox(p, 52, function(n) if n and n > 0 then ns.cur.qty = math.floor(n) end; ns.RefreshPanel() end)
    d.qty:SetPoint("TOPLEFT", 38, y)
    d.buy = UI.Button(p, "Buy", 60, 22, function() ns.StartBuy(tonumber(d.qty:GetText() or "") or ns.cur.qty) end, "primary")
    d.buy:SetPoint("LEFT", d.qty, "RIGHT", 8, 0)
    d.confirm = UI.Button(p, "Confirm", 70, 22, function() ns.ConfirmBuy() end, "primary")
    d.confirm:SetPoint("LEFT", d.buy, "RIGHT", 6, 0)
    d.cancel = UI.Button(p, "Cancel", 56, 22, function() ns.CancelBuy() end)
    d.cancel:SetPoint("LEFT", d.confirm, "RIGHT", 6, 0)
    d.override = UI.CheckLabel(p, "Buy above my max", function(v) ns.cur.override = v; ns.RefreshPanel() end,
        "For one purchase: lets Buy go through even when the price is above the max. It unticks itself after a purchase or when you pick an item.")
    d.override.frame:SetPoint("TOPLEFT", 12, y - 30)
    d.ladder = UI.Para(p, 11, C.text, W - 24)
    d.ladder:SetPoint("TOPLEFT", 12, y - 56)

    -- other items: the cheapest auctions, one Buy each
    d.auctions = {}
    for i = 1, AUCTION_ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetHeight(24)
        r:SetPoint("TOPLEFT", 10, y - (i - 1) * 26)
        r:SetPoint("RIGHT", p, "RIGHT", -10, 0)
        r.bg = UI.Fill(r, C.zebra)
        r.text = UI.Text(r, 11, C.text)
        r.text:SetPoint("LEFT", 6, 0)
        r.text:SetPoint("RIGHT", -70, 0)
        r.buy = UI.Button(r, "Buy", 60, 20, function() if r.row then ns.BuyItem(r.row) end end, "primary")
        r.buy:SetPoint("RIGHT", -2, 0)
        d.auctions[i] = r
    end
    d.msg = UI.Para(p, 11, C.muted, W - 24)
    d.msg:SetPoint("BOTTOMLEFT", 12, 12)
end

local function build()
    if panel then return end
    panel = CreateFrame("Frame", "KingMakerShoppingPanel", UIParent)
    panel:SetSize(W, H)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    UI.Fill(panel, C.bg)
    UI.Border(panel, { 1, 1, 1, 0.10 })
    UI.GoldEdge(panel)
    panel:Hide()
    local title = UI.Text(panel, 13, C.accent)
    title:SetPoint("TOPLEFT", 12, -11)
    title:SetText("Shopping")
    panel.close = UI.CloseButton(panel, function() ns.ShowPanel(false) end)
    panel.close:SetPoint("TOPRIGHT", -6, -6)
    panel.page = UI.Button(panel, "Lists", 52, 20, function() KM.Show("shopping") end, "ghost")
    panel.page:SetPoint("RIGHT", panel.close, "LEFT", -4, 0)

    panel.pick = UI.MenuButton(panel, 176, function() return ns.Active() end, function(_, root)
        for _, name in ipairs(ns.ListNames()) do
            root:CreateRadio(name, function(n) return n == ns.Active() end, function(n) offset = 0; ns.SetActive(n) end, name)
        end
    end)
    panel.pick:SetPoint("TOPLEFT", 8, -36)
    panel.all = UI.Button(panel, "Search all", 100, 24, function() ns.SearchAll() end, "primary")
    panel.all:SetPoint("TOPRIGHT", -8, -36)

    for i = 1, ROWS do rows[i] = makeRow(panel, i) end
    panel.emptyText = UI.Para(panel, 11, C.dim, W - 24)
    panel.emptyText:SetPoint("TOPLEFT", 12, -76)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta * 3, #list - ROWS))
        ns.RefreshPanel()
    end)
    buildDetail(panel)
    ns.detail, ns.panelRows = d, rows
    ns.panel = panel

    toggle = UI.Button(UIParent, "Shopping", 84, 22, function() ns.ShowPanel(true) end, "primary")
    toggle:SetFrameStrata("HIGH")
    toggle:Hide()
    ns.toggle = toggle
end
ns.BuildPanel = build

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawRows()
    list = sortedEntries()
    offset = math.max(0, math.min(offset, #list - ROWS))
    local cur = ns.cur
    for i, r in ipairs(rows) do
        local e = list[i + offset]
        r.entry = e
        if e then
            r.icon:SetTexture(ns.Icon(e.id))
            r.name:SetText(ns.ColoredName(e.id))
            local _, lowest = ns.Prices(e.id)
            local status = ns.Status(e)
            r.price:SetText(lowest and KM.Money(lowest) or (UI.Hex(C.dim) .. "-|r"))
            r.good:SetShown(status == "under")
            r.sel:SetShown(cur.id == e.id)
            r.search:SetEnabled2(ns.AHOpen() and not ns.SearchAllRunning())
            r:Show()
        else
            r:Hide()
        end
    end
    panel.emptyText:SetText(#list == 0 and (ns.Active() == ns.FAV
        and "No favorites yet. Star items in Price History, or add them on the Shopping page."
        or "This list is empty. Add items on the Shopping page (/shop) or with /shop add.") or "")
    panel.pick:Refresh()
    panel.all:SetLabel(ns.SearchAllRunning() and "Stop" or "Search all")
end

local function drawDetail()
    local c = ns.cur
    local has = c.id ~= nil
    d.icon:SetShown(has); d.name:SetShown(has); d.info:SetShown(has)
    d.empty:SetShown(not has)
    local commodity = has and c.kind == "commodity"
    local item = has and c.kind == "item"
    for _, w in ipairs({ d.qtyLabel, d.qty, d.buy, d.confirm, d.cancel, d.override.frame, d.ladder }) do w:SetShown(commodity) end
    if has then
        d.icon:SetTexture(ns.Icon(c.id))
        d.name:SetText(ns.ColoredName(c.id))
        local e = ns.CurEntry()
        local max, fromMarket = nil, false
        if e then max, fromMarket = ns.EffectiveMax(e) end
        local market, _, listed = ns.Prices(c.id)
        d.info:SetText("Max " .. (max and (KM.Money(max) .. (fromMarket and " (market)" or "")) or "none")
            .. "   Want " .. ((e and e.qty) and tostring(e.qty) or "-")
            .. "   Listed " .. (listed and KM.Commas(listed) or "-")
            .. (market and ("   Market " .. KM.Money(market)) or ""))
    end
    if commodity then
        if not d.qty.focused then d.qty:SetText(tostring(c.qty or 1)) end
        local cheapest = c.rows[1] and c.rows[1].unit
        local idle = c.phase == "idle" or c.phase == "blocked"
        d.buy:SetEnabled2(idle and ns.AHOpen() and #c.rows > 0 and not ns.OverMax(cheapest))
        d.confirm:SetEnabled2(c.phase == "confirm" and not ns.OverMax(c.unit))
        d.cancel:SetEnabled2(c.phase == "pending" or c.phase == "confirm" or c.phase == "blocked")
        d.override:SetChecked(c.override)
        local lines = {}
        for i, r in ipairs(c.rows) do
            if i > 4 then break end
            local col = ns.OverMax(r.unit) and UI.Hex(C.muted) or ""
            lines[#lines + 1] = col .. KM.Money(r.unit) .. " each  x " .. KM.Commas(r.qty) .. (col ~= "" and "|r" or "")
        end
        d.ladder:SetText(#lines > 0 and table.concat(lines, "\n") or "")
    end
    for i, r in ipairs(d.auctions) do
        local row = item and c.rows[i]
        r.row = row or nil
        if row then
            local over = ns.OverMax(row.unit)
            r.text:SetText((over and UI.Hex(C.muted) or "") .. KM.Money(row.buyout)
                .. (row.qty > 1 and ("  (" .. row.qty .. " x " .. KM.Money(row.unit) .. ")") or "") .. (over and "  above max|r" or ""))
            r.buy:SetEnabled2(ns.AHOpen() and not over)
            r:Show()
        else
            r:Hide()
        end
    end
    local msg = c.msg
    if not msg and item and #c.rows == 0 then msg = "None listed right now." end
    d.msg:SetText(msg or "")
    local mc = c.msgColor or C.muted
    d.msg:SetTextColor(mc[1], mc[2], mc[3], 1)
end

function ns.RefreshPanel()
    if not (panel and panel:IsShown() and ns.db) then return end
    drawRows()
    drawDetail()
end

---------------------------------------------------------------------------
-- Showing and hiding with the auction house
---------------------------------------------------------------------------

function ns.ShowPanel(on)
    build()
    ns.db.panel.shown = on and true or false
    if on and ns.AHOpen() then
        anchorTo(panel, 2, 0)
        panel:Show()
        toggle:Hide()
        ns.RefreshPanel()
    else
        panel:Hide()
        if ns.AHOpen() then anchorTo(toggle, 2, -4); toggle:Show() else toggle:Hide() end
    end
end

function ns.TogglePanel()
    if not ns.AHOpen() then return KM.Print(ns, "open the auction house first; the panel sits beside it.") end
    ns.ShowPanel(not (panel and panel:IsShown()))
end

function ns.OnAHShow()
    if not AuctionHouseFrame then
        -- the auction house UI loads on demand: try again once it's there
        if C_Timer and C_Timer.After then C_Timer.After(0.2, function() if AuctionHouseFrame and ns.AHOpen() then ns.OnAHShow() end end) end
        return
    end
    build()
    local show = ns.db.settings.autoPanel and ns.db.panel.shown
    -- ShowPanel stores the choice; keep the stored one when the setting is what hides it
    local keep = ns.db.panel.shown
    ns.ShowPanel(show)
    ns.db.panel.shown = keep
end

function ns.OnAHClosed()
    if panel then panel:Hide() end
    if toggle then toggle:Hide() end
end
