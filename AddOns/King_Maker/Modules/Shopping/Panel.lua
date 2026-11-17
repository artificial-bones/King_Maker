local _, KM = ...
local ns = KM.Module("Shopping")
local UI = KM.UI
local C = UI.C

-- The panel at the auction house: our own frame docked to the right edge of AuctionHouseFrame (anchored to it,
-- never parented to it or changing it), shown while the auction house is open. The active list on top, deals first,
-- each row with its lowest price, your max, how many you still need and a Find button; below, the selected item:
-- what's listed against your max, and its buy flow (a Keep item's need is what's missing from its stock) (Buy / Confirm for commodities, one Buy per auction for everything
-- else); at the bottom Next deal and what this visit spent. The "Shopping" toggle beside the auction house shows it
-- again after it is closed.

local W, H = 320, 540
local ROWS, ROW_H, ROW_TOP = 8, 22, -92
local AUCTION_ROWS, LADDER_LINES = 5, 4
local DASH = "|cff808080-|r"

local panel, toggle
local rows, offset = {}, 0
local d = {}          -- detail widgets
local list = {}       -- rows shown (ns.Row), deals first

local function anchorTo(frame, x, y)
    frame:ClearAllPoints()
    if AuctionHouseFrame then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", x or 2, y or 0)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
    end
end

local function hex(c) return UI.Hex(c) end

-- Column x positions inside a row (row width W - 16), right-aligned from the row's right edge.
local COL = { find = 38, need = 26, max = 50, lowest = 54, gap = 3 }
local function colRight(key)
    local x = -(COL.find + COL.gap)
    if key == "need" then return x end
    x = x - COL.need - COL.gap
    if key == "max" then return x end
    return x - COL.max - COL.gap
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function rowTip(self)
    local r = self.data
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, r.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Lowest " .. KM.Money(r.lowest) .. "   Your max " .. KM.Money(r.max) .. (r.fromMarket and " (market)" or ""), 1, 1, 1)
    if r.underQty then GameTooltip:AddLine(KM.Commas(r.underQty) .. " listed at or under your max (searched)", 0.6, 0.6, 0.6) end
    if r.keep then
        GameTooltip:AddLine("Keep " .. r.keep .. " in stock: you have " .. KM.Commas(r.owned or 0)
            .. ((r.coming or 0) > 0 and (", " .. r.coming .. " on the way") or "") .. ". Need is what's missing.", C.info[1], C.info[2], C.info[3], true)
    end
    if r.e.note then GameTooltip:AddLine(r.e.note, 0.6, 0.6, 0.6, true) end
    GameTooltip:AddLine("Click to look it up here. Find shows it in the auction house window too.", 0.42, 0.42, 0.44, true)
    GameTooltip:Show()
end

local function makeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 8, ROW_TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    r.zebra = UI.Fill(r, C.zebra)
    r.zebra:SetShown(i % 2 == 0)
    r.good = UI.Fill(r, { C.good[1], C.good[2], C.good[3], 0.10 }, "ARTWORK")
    r.good:Hide()
    r.bar = r:CreateTexture(nil, "OVERLAY")
    r.bar:SetTexture(UI.WHITE)
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(2)
    UI.SetColor(r.bar, C.good)
    r.bar:Hide()
    r.sel = UI.Fill(r, C.sel, "ARTWORK")
    r.sel:Hide()
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(ROW_H - 6, ROW_H - 6)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = UI.Text(r, 11, C.text)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", colRight("lowest") - COL.lowest - COL.gap, 0)
    r.price = UI.Text(r, 11, C.text, "RIGHT")
    r.price:SetPoint("RIGHT", colRight("lowest"), 0)
    r.price:SetWidth(COL.lowest)
    r.max = UI.Text(r, 11, C.text, "RIGHT")
    r.max:SetPoint("RIGHT", colRight("max"), 0)
    r.max:SetWidth(COL.max)
    r.need = UI.Text(r, 11, C.text, "RIGHT")
    r.need:SetPoint("RIGHT", colRight("need"), 0)
    r.need:SetWidth(COL.need)
    -- Find: Blizzard's search bar gets the name and runs (buy in Blizzard's window), then the panel looks the item
    -- up too (its price, max and buy buttons) once the shared AH throttle allows.
    r.search = UI.Button(r, "Find", COL.find, ROW_H - 4, function()
        if r.data then ns.FindItem(r.data.id) end
    end)
    r.search:SetPoint("RIGHT", 0, 0)
    UI.Tip(r.search, "Show it in the auction house window too, so you can buy there.")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- a row click picks the item and looks it up for the panel (one search; searching isn't protected)
    r:SetScript("OnClick", function(self)
        if not self.data then return end
        UI.Click()
        local id = self.data.id
        ns.Select(id, ns.Active())
        ns.Search(id, { select = true })
    end)
    r:SetScript("OnEnter", rowTip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function buildDetail(p)
    local top = ROW_TOP - ROWS * ROW_H - 6
    local line = p:CreateTexture(nil, "BORDER")
    line:SetTexture(UI.WHITE)
    UI.SetColor(line, C.border)
    line:SetPoint("TOPLEFT", 8, top)
    line:SetPoint("TOPRIGHT", -8, top)
    line:SetHeight(1)

    d.icon = p:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(22, 22)
    d.icon:SetPoint("TOPLEFT", 10, top - 6)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.status = UI.Text(p, 11, C.good, "RIGHT")
    d.status:SetPoint("TOPRIGHT", -12, top - 10)
    d.name = UI.Text(p, 13, C.text)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 7, -3)
    d.name:SetPoint("RIGHT", d.status, "LEFT", -6, 0)
    d.info = UI.Text(p, 10, C.muted)
    d.info:SetPoint("TOPLEFT", 12, top - 32)
    d.info:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    d.under = UI.Text(p, 10, C.muted)
    d.under:SetPoint("TOPLEFT", 12, top - 46)
    d.under:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    d.empty = UI.Para(p, 11, C.dim, W - 24)
    d.empty:SetPoint("TOPLEFT", 12, top - 10)

    -- the ladder: what's listed, cheapest first, with a line where your max falls
    local ly = top - 64
    d.ladderLines = {}
    for i = 1, LADDER_LINES do
        local fs = UI.Text(p, 11, C.text)
        fs:SetPoint("TOPLEFT", 16, ly - (i - 1) * 14)
        fs:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        d.ladderLines[i] = fs
    end
    d.ladder = d.ladderLines[1]   -- (kept for older tests: the first line)

    -- commodities: quantity, Buy (with the estimate), Confirm (with the real price), Cancel
    local y = ly - LADDER_LINES * 14 - 6
    d.qtyLabel = UI.Text(p, 11, C.muted)
    d.qtyLabel:SetPoint("TOPLEFT", 12, y - 5)
    d.qtyLabel:SetText("Qty")
    d.qty = UI.NumberBox(p, 44, function(n)
        if n and n > 0 then ns.cur.qty = math.floor(n); ns.cur.qtyTouched = true end
        ns.RefreshPanel()
    end)
    d.qty:SetPoint("TOPLEFT", 38, y)
    d.buy = UI.Button(p, "Buy", 170, 22, function() ns.StartBuy(tonumber(d.qty:GetText() or "") or ns.cur.qty) end, "primary")
    d.buy:SetPoint("LEFT", d.qty, "RIGHT", 8, 0)
    d.confirm = UI.Button(p, "Confirm", 170, 22, function() ns.ConfirmBuy() end, "primary")
    d.confirm:SetPoint("TOPLEFT", d.buy, "BOTTOMLEFT", 0, -4)
    d.cancel = UI.Button(p, "Cancel", 60, 22, function() ns.CancelBuy() end)
    d.cancel:SetPoint("LEFT", d.confirm, "RIGHT", 6, 0)
    UI.Tip(d.buy, "Asks the auction house what Qty costs, cheapest first. Nothing is bought yet: Confirm does that.")
    UI.Tip(d.confirm, "Buys at the price shown. Above your max it stops, unless you tick \"Allow one buy above my max\".")

    -- other items: the cheapest auctions, one Buy each
    d.auctions = {}
    for i = 1, AUCTION_ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", 10, ly - (i - 1) * 19)
        r:SetPoint("RIGHT", p, "RIGHT", -10, 0)
        r.bg = UI.Fill(r, C.zebra)
        r.text = UI.Text(r, 11, C.text)
        r.text:SetPoint("LEFT", 6, 0)
        r.text:SetPoint("RIGHT", -60, 0)
        r.buy = UI.Button(r, "Buy", 52, 17, function() if r.row then ns.BuyItem(r.row) end end, "primary")
        r.buy:SetPoint("RIGHT", -2, 0)
        d.auctions[i] = r
    end

    d.override = UI.CheckLabel(p, "Allow one buy above my max", function(v) ns.cur.override = v; ns.RefreshPanel() end,
        "For one purchase: lets Buy go through even when the price is above the max. It unticks itself after a purchase or when you pick an item.")
    d.override.frame:SetPoint("TOPLEFT", 12, y - 54)

    local fy = y - 80
    local line2 = p:CreateTexture(nil, "BORDER")
    line2:SetTexture(UI.WHITE)
    UI.SetColor(line2, C.border)
    line2:SetPoint("TOPLEFT", 8, fy)
    line2:SetPoint("TOPRIGHT", -8, fy)
    line2:SetHeight(1)
    d.next = UI.Button(p, "Next deal >", 96, 22, function() ns.GoNextDeal() end)
    d.next:SetPoint("TOPLEFT", 10, fy - 6)
    UI.Tip(d.next, function(tt)
        tt:AddLine(ns.NextDeal() and "Pick the next item under your max and look it up. It never buys: Buy and Confirm are yours."
            or "No more deals on this list.", 1, 1, 1, true)
    end)
    d.spent = UI.Text(p, 10, C.muted, "RIGHT")
    d.spent:SetPoint("LEFT", d.next, "RIGHT", 8, 0)
    d.spent:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    d.msg = UI.Para(p, 11, C.muted, W - 24)
    d.msg:SetPoint("TOPLEFT", 12, fy - 34)
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
    -- Page: the Shopping page, on the item the panel is working on
    panel.page = UI.Button(panel, "Page", 52, 20, function()
        local id = ns.cur.id
        KM.Show("shopping")
        if id and ns.SelectItem then ns.SelectItem(id) end
    end, "ghost")
    panel.page:SetPoint("RIGHT", panel.close, "LEFT", -4, 0)

    panel.pick = UI.MenuButton(panel, 196, function()
        local a = ns.Active()
        local n = ns.Summary(a).deals
        return a .. (n > 0 and ("  (" .. n .. ")") or "")
    end, function(_, root)
        for _, name in ipairs(ns.ListNames()) do
            local n = ns.Summary(name).deals
            root:CreateRadio(name .. (n > 0 and ("  (" .. n .. ")") or ""), function(x) return x == ns.Active() end,
                function(x) offset = 0; ns.SetActive(x) end, name)
        end
    end)
    panel.pick:SetPoint("TOPLEFT", 8, -36)
    panel.all = UI.Button(panel, "Search all", 100, 24, function() ns.SearchAll() end, "primary")
    panel.all:SetPoint("TOPRIGHT", -8, -36)
    UI.Tip(panel.all, "Searches every item on this list at the auction house, one after another, for live prices, then picks the best deal. Click again to stop. It never buys.")
    panel.summary = UI.Text(panel, 10, C.muted)
    panel.summary:SetPoint("TOPLEFT", 12, -66)
    panel.summary:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

    -- column headers
    local function head(text, key, w)
        local fs = UI.Text(panel, 9, C.muted, key == "name" and "LEFT" or "RIGHT")
        if key == "name" then fs:SetPoint("TOPLEFT", 35, ROW_TOP + 13)
        else
            fs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8 + colRight(key), ROW_TOP + 13)
            fs:SetWidth(w)
        end
        fs:SetText(text)
        return fs
    end
    head("ITEM", "name"); head("LOWEST", "lowest", COL.lowest); head("MAX", "max", COL.max); head("NEED", "need", COL.need + 6)

    for i = 1, ROWS do rows[i] = makeRow(panel, i) end
    panel.emptyText = UI.Para(panel, 11, C.dim, W - 24)
    panel.emptyText:SetPoint("TOPLEFT", 12, ROW_TOP - 10)
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
    list = ns.ActiveRows()
    offset = math.max(0, math.min(offset, #list - ROWS))
    local cur = ns.cur
    local deals, cost = 0, 0
    for _, r in ipairs(list) do
        if r.status == "under" then deals = deals + 1; cost = cost + (r.cost or 0) end
    end
    for i, f in ipairs(rows) do
        local r = list[i + offset]
        f.data = r
        f.entry = r and r.e or nil
        if r then
            local deal, dim = r.status == "under", r.status ~= "under" and r.status ~= "nomax"
            f.icon:SetTexture(ns.Icon(r.id))
            f.name:SetText(ns.ColoredName(r.id))
            f.name:SetAlpha(dim and 0.7 or 1)
            f.price:SetText(r.lowest and ns.Short(r.lowest, dim) or DASH)
            local pc = deal and C.good or (dim and C.dim or C.text)
            f.price:SetTextColor(pc[1], pc[2], pc[3], 1)
            f.max:SetText(r.max and (ns.Short(r.max, true) .. (r.fromMarket and "*" or "")) or DASH)
            local mc = (r.fromMarket or dim) and C.dim or C.text
            f.max:SetTextColor(mc[1], mc[2], mc[3], 1)
            f.need:SetText(r.qty and tostring(r.qty) or DASH)
            local nc = dim and C.dim or C.text
            f.need:SetTextColor(nc[1], nc[2], nc[3], 1)
            f.good:SetShown(deal)
            f.bar:SetShown(deal)
            f.sel:SetShown(cur.id == r.id)
            f.search:SetEnabled2(ns.AHOpen() and not ns.SearchAllRunning())
            f:Show()
        else
            f:Hide()
        end
    end
    panel.emptyText:SetText(#list == 0 and (ns.Active() == ns.FAV
        and "No favorites yet. Star items in Price History, or add them on the Shopping page."
        or "This list is empty. Add items on the Shopping page (/shop) or with /shop add.") or "")
    panel.pick:Refresh()
    panel.all:SetLabel(ns.SearchAllRunning() and "Stop" or "Search all")
    local i, n = ns.SearchAllProgress()
    local spentText = ns.session.spent > 0 and ("   spent " .. ns.Short(ns.session.spent)) or ""
    if i then
        panel.summary:SetText("Searching " .. i .. " of " .. n .. "...")
    elseif #list > 0 then
        panel.summary:SetText((deals > 0 and (hex(C.good) .. deals .. " deal" .. (deals == 1 and "" or "s") .. "|r") or "No deals")
            .. " of " .. #list .. (deals > 0 and ("   ~" .. ns.Short(cost)) or "") .. spentText)
    else
        panel.summary:SetText(spentText)
    end
    return deals, cost
end

-- The ladder lines: listings at or under your max, a "your max" line, then what's above it (dim).
local function ladderText(c, max)
    local lines, divided = {}, false
    for _, r in ipairs(c.rows) do
        if #lines >= LADDER_LINES then break end
        local over = max and r.unit > max
        if over and not divided and max then
            divided = true
            lines[#lines + 1] = hex(C.warn) .. "------  your max " .. ns.Short(max, true) .. "  ------|r"
            if #lines >= LADDER_LINES then break end
        end
        lines[#lines + 1] = (over and hex(C.dim) or "") .. ns.Short(r.unit, over) .. "  x " .. KM.Commas(r.qty)
            .. (over and "|r" or (max and ("   " .. hex(C.good) .. "ok|r") or ""))
    end
    return lines
end

local function drawDetail(deals, cost)
    local c = ns.cur
    local has = c.id ~= nil
    local e = has and ns.CurEntry() or nil
    local r = e and ns.Row(e) or nil
    d.icon:SetShown(has); d.name:SetShown(has); d.info:SetShown(has); d.under:SetShown(has); d.status:SetShown(has)
    d.empty:SetShown(not has)
    local commodity = has and c.kind == "commodity"
    local item = has and c.kind == "item"
    for _, w in ipairs({ d.qtyLabel, d.qty, d.buy, d.confirm, d.cancel }) do w:SetShown(commodity) end
    for _, fs in ipairs(d.ladderLines) do fs:SetShown(commodity) end
    d.override.frame:SetShown(commodity or item)
    if not has then
        d.empty:SetText(#list == 0 and "" or ((deals > 0
            and (deals .. " deal" .. (deals == 1 and "" or "s") .. " on this list, about " .. ns.Short(cost) .. ". ")
            or "Nothing under your max in the last scan. ")
            .. "Search all looks every item up; click an item to look it up."))
    end
    if has then
        d.icon:SetTexture(ns.Icon(c.id))
        d.name:SetText(ns.ColoredName(c.id))
        local max = r and r.max or nil
        if r then
            local text, col = ns.StatusLabel(r)
            if r.status == "over" then text, col = "OVER", C.muted end
            d.status:SetText(hex(col) .. text .. "|r" .. ((r.pct and text ~= "DONE") and ("  " .. ns.Pct(r.pct)) or ""))
            d.info:SetText("Max " .. (max and (ns.Short(max) .. (r.fromMarket and " (market)" or "")) or "none")
                .. "   Need " .. (r.qty and tostring(r.qty) or "-") .. (r.keep and (" (keep " .. r.keep .. ")") or "")
                .. (r.avg7 and ("   7d " .. ns.Short(r.avg7) .. " (" .. ns.Trend(r.trend7) .. ")") or "")
                .. ((r.basis and r.basis.avg) and ("   Hold " .. r.basis.held .. " at " .. ns.Short(r.basis.avg)) or ""))
        else
            d.status:SetText("")
            d.info:SetText("Not on " .. ns.Active() .. " any more.")
        end
        local under = ns.UnderQty(c.id, max)
        local lv = ns.live[c.id]
        if under and max then
            d.under:SetText((under > 0 and hex(C.good) or hex(C.muted)) .. KM.Commas(under) .. " listed at or under your max|r"
                .. (lv and lv.q and ("  (of " .. KM.Commas(lv.q) .. ")") or ""))
        elseif lv and lv.q then
            d.under:SetText(KM.Commas(lv.q) .. " listed (searched " .. KM.Ago(lv.t) .. ")")
        else
            d.under:SetText(r and r.listed and (KM.Commas(r.listed) .. " listed in the last scan. Click the item to look it up.")
                or "Click the item to look it up.")
        end
    end
    if commodity then
        if not d.qty.focused then d.qty:SetText(tostring(c.qty or 1)) end
        local cheapest = c.rows[1] and c.rows[1].unit
        local idle = c.phase == "idle" or c.phase == "blocked"
        local over = ns.OverMax(cheapest)
        d.buy:SetEnabled2(idle and ns.AHOpen() and #c.rows > 0 and not over)
        local q = tonumber(d.qty:GetText() or "") or c.qty or 1
        local est = ns.LadderCost(c.id, q)
        if #c.rows > 0 and over then d.buy:SetLabel("None under your max")
        else d.buy:SetLabel("Buy " .. q .. (est and (" ~ " .. ns.Short(est, true)) or "")) end
        d.confirm:SetEnabled2(c.phase == "confirm" and not ns.OverMax(c.unit))
        if c.phase == "confirm" and c.total then
            d.confirm:SetLabel((ns.Armed() and "Click again: " or "Confirm ") .. ns.Short(c.total, true))
        else
            d.confirm:SetLabel("Confirm")
        end
        d.cancel:SetEnabled2(c.phase == "pending" or c.phase == "confirm" or c.phase == "blocked")
        local lines = ladderText(c, r and r.max)
        for i, fs in ipairs(d.ladderLines) do fs:SetText(lines[i] or "") end
    end
    if commodity or item then d.override:SetChecked(c.override) end
    for i, f in ipairs(d.auctions) do
        local row = item and c.rows[i]
        f.row = row or nil
        if row then
            local over = ns.OverMax(row.unit)
            f.text:SetText((over and hex(C.dim) or "") .. ns.Short(row.buyout, over)
                .. (row.qty > 1 and ("  (" .. row.qty .. " x " .. ns.Short(row.unit, true) .. ")") or "")
                .. (over and "  over max|r" or ""))
            f.buy:SetEnabled2(ns.AHOpen() and not over)
            f:Show()
        else
            f:Hide()
        end
    end
    d.next:SetEnabled2(ns.NextDeal() ~= nil and not ns.SearchAllRunning())
    local s = ns.session
    d.spent:SetText(s.buys > 0 and ("spent this visit " .. ns.Short(s.spent)) or "")
    local msg = c.msg
    if not msg and item and #c.rows == 0 then msg = "None listed right now." end
    d.msg:SetText(msg or "")
    local mc = c.msgColor or C.muted
    d.msg:SetTextColor(mc[1], mc[2], mc[3], 1)
end

function ns.RefreshPanel()
    if not (panel and panel:IsShown() and ns.db) then return end
    local deals, cost = drawRows()
    drawDetail(deals, cost)
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
