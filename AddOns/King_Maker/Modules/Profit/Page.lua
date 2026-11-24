local _, KM = ...
local ns = KM.Module("Profit")
local UI = KM.UI
local C = UI.C

-- The Gold > Profit & Loss page (764 x 560, laid out from the container's size: the window zooms, it never reflows).
--   Top, on every tab: Overview / Trades / Holdings and Export; whose (all characters or this one), the counting menu
--   (FIFO or LIFO, farmed items free or at their value), the period (Today, 7 days, 30 days, All; not on Holdings) and,
--   on Trades and Holdings, a search by item name (2.8).
--   Overview: four tiles (profit, sales, stock, if sold now), one muted line with what's kept out of profit (sold
--             with cost unknown, used or gone), realized per day, where it came from, and every item you sold
--             (2.18.0: holdings columns moved out; they're the Holdings tab).
--   Trades:   by sale (each sale and the lots it used), by buy (each lot and what used it), or what left unsold.
--   Holdings: what you hold, at cost and at today's price, the underwater ones marked; untraced stock and Adopt.
-- Also here: the Home tile and note, the crown line, the item tooltip line and the export window.

local R = "RIGHT"
local PERIODS = { { id = 1, label = "Today", w = 64 }, { id = 7, label = "7 days", w = 64 }, { id = 30, label = "30 days", w = 64 },
    { id = 0, label = "All", w = 64 } }
local TILE_H, GAP, ASIDE_H = 58, 10, 18
local DAY = 86400

local P = {}
ns.P = P

local function U() return ns.db.ui end
local function grey(t) return "|cff808080" .. t .. "|r" end
local function hex(c) return UI.Hex(c) end

local function since()
    local days = U().period or 30
    if days == 0 then return 0 end
    local now = KM.Now()
    if days == 1 then
        local d = date and date("*t", now)
        if d then return now - (d.hour * 3600 + d.min * 60 + d.sec) end
    end
    return now - days * DAY
end

local function charKey() return U().mine and KM.Char() or nil end

-- "+3g 45s" in green, "-51s" in red, "0c" muted (compact); exact = KM.Money's full form.
local function signed(c, exact)
    if c == nil then return grey("-") end
    local r = math.floor(c + 0.5)
    local body = exact and KM.Money(math.abs(r), true) or KM.MoneyShort(math.abs(r), true)
    if r == 0 then return hex(C.muted) .. body .. "|r" end
    return (r > 0 and (hex(C.good) .. "+") or (hex(C.bad) .. "-")) .. body .. "|r"
end
ns.Signed = signed
local function signedPlain(c)
    if c == nil then return "-" end
    local r = math.floor(c + 0.5)
    return (r > 0 and "+" or (r < 0 and "-" or "")) .. KM.MoneyShort(math.abs(r), true)
end
local function tone(c) if not c then return C.text end c = math.floor(c + 0.5) return c > 0 and C.good or (c < 0 and C.bad or C.text) end
local function pct(x)
    if x == nil then return grey("-") end
    local n = math.floor(math.abs(x) * 100 + 0.5)
    if n == 0 then return hex(C.muted) .. "0%|r" end
    return (x > 0 and (hex(C.good) .. "+") or (hex(C.bad) .. "-")) .. n .. "%|r"
end
local function pctPlain(x)
    if x == nil then return "" end
    local n = math.floor(math.abs(x) * 100 + 0.5)
    return (x > 0 and "+" or (x < 0 and "-" or "")) .. n .. "%"
end
local function ageText(sec)
    if not sec then return grey("-") end
    if sec < 3600 then return math.max(0, math.floor(sec / 60)) .. "m" end
    if sec < DAY then return math.floor(sec / 3600) .. "h" end
    return math.floor(sec / DAY) .. "d"
end
local function first(who) return who and who:match("^[^%-]+") or grey("-") end
local function dl(tt, l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
local function icon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return KM.Item(id).icon
end
local function nameOf(id) return KM.Item(id).name or ("Item " .. id) end
local function periodWords()
    local d = U().period or 30
    return d == 0 and "all time" or (d == 1 and "today" or ("the last " .. d .. " days"))
end
local function scopeLine(tt)
    tt:AddLine((U().mine and "This character" or "All your characters on this realm and faction") .. ", " .. periodWords() .. ". "
        .. (ns.db.settings.method == "lifo" and "Sales use up your newest stock first." or "Sales use up your oldest stock first.")
        .. (ns.db.settings.basis == "market" and " Farmed items cost their value when looted." or " Farmed items count as free."), 0.6, 0.6, 0.6, true)
end

local function hasInventory() return InventoryKing and InventoryKing.GetPlaces and true or false end

-- The search box's text (lower case), or nil: Trades and Holdings show only items whose name has it.
local function matches(id)
    if not P.search then return true end
    return nameOf(id):lower():find(P.search, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Top bar
---------------------------------------------------------------------------

local function countingMenu(_, root)
    root:CreateTitle("How Profit & Loss counts")
    root:CreateRadio("Sales use up: oldest stock first (FIFO)", function() return ns.db.settings.method == "fifo" end, function() ns.SetMethod("fifo") end)
    root:CreateRadio("Sales use up: newest stock first (LIFO)", function() return ns.db.settings.method == "lifo" end, function() ns.SetMethod("lifo") end)
    root:CreateRadio("Farmed items cost: nothing", function() return ns.db.settings.basis == "paid" end, function() ns.SetBasis("paid") end)
    root:CreateRadio("Farmed items cost: their value when looted", function() return ns.db.settings.basis == "market" end, function() ns.SetBasis("market") end)
end

local function buildTop(c)
    P.tabs = UI.Tabs(c, { { id = "overview", label = "Overview", w = 96 }, { id = "trades", label = "Trades", w = 96 },
        { id = "holdings", label = "Holdings", w = 96 } }, function(id) ns.SelectTab(id) end)
    P.tabs:SetPoint("TOPLEFT", 0, 0)
    P.export = UI.Button(c, "Export", 70, 24, function() ns.Export() end)
    P.export:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(P.export, "Every trade and every lot as comma-separated text, for a spreadsheet. Also /pnl export.")
    P.charBtn = UI.Button(c, "All characters", 120, 24, function() U().mine = not U().mine; KM.Refresh("profit") end)
    P.charBtn:SetPoint("TOPLEFT", 0, -32)
    UI.Tip(P.charBtn, function(tt)
        tt:AddLine("Whose")
        tt:AddLine("All your characters on this realm and faction (they share their stock: mail between them isn't a sale), or only this one: its sales, and what it holds at the pool's average cost. Click to switch.", 1, 1, 1, true)
    end)
    P.counting = UI.MenuButton(c, 196, function() return ns.CountingText() end, countingMenu)
    P.counting:SetPoint("LEFT", P.charBtn, "RIGHT", 6, 0)
    UI.Tip(P.counting, function(tt)
        tt:AddLine("How it counts")
        tt:AddLine("Oldest first (FIFO): a sale uses up the units you've had longest. Newest first (LIFO): the last thing you bought is what you sold. Switching works every number out again; the total over time is the same, only how much is realized now changes.", 1, 1, 1, true)
        tt:AddLine("Farmed free: loot cost you nothing, so selling it is all profit. At value: loot costs what it was worth when looted, so P&L shows only what selling added on top of the Farming Ledger.", 1, 1, 1, true)
    end)
    P.periods = UI.Tabs(c, PERIODS, function(id) U().period = id; KM.Refresh("profit") end)
    P.periods:SetPoint("TOPRIGHT", 0, -32)
    P.searchBox = UI.EditBox(c, 150, 24, "Search items", function(text, user)
        if not user then return end
        text = (text or ""):lower():match("^%s*(.-)%s*$")
        local s = text ~= "" and text or nil
        if s ~= P.search then
            P.search = s
            for _, t in ipairs({ P.saleTable, P.buyTable, P.goneTable, P.holdTable }) do if t then t.offset = 0 end end
            KM.Refresh("profit")
        end
    end)
    P.searchBox:SetPoint("LEFT", P.counting, "RIGHT", 6, 0)
    P.footer = UI.Text(c, 10, C.muted)
    P.footer:SetPoint("BOTTOMLEFT", 0, 4)
    P.footer:SetPoint("RIGHT", c, "RIGHT", -230, 0)
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------

local function col(key, label, w, justify, sort, tip, desc)
    return { key = key, label = label, w = w, justify = justify, sort = sort, tip = tip, desc = desc }
end
local function byName(r) return nameOf(r.item):lower() end

-- A faint red tint and a red left edge on an underwater row.
local function tint(r, on)
    if not r.pnlTint then
        r.pnlTint = UI.Fill(r, { C.bad[1], C.bad[2], C.bad[3], 0.07 }, "BACKGROUND", 1)
        r.pnlEdge = r:CreateTexture(nil, "OVERLAY")
        r.pnlEdge:SetTexture(UI.WHITE)
        r.pnlEdge:SetPoint("TOPLEFT")
        r.pnlEdge:SetPoint("BOTTOMLEFT")
        r.pnlEdge:SetWidth(2)
        UI.SetColor(r.pnlEdge, C.bad)
    end
    r.pnlTint:SetShown(on and true or false)
    r.pnlEdge:SetShown(on and true or false)
end

local function flagText(h)
    if not h then return "" end
    if h.under then return hex(C.bad) .. "UNDER|r" end
    if (h.held or 0) > 0 and not h.each then return grey("NO PRICE") end
    if h.stale then return hex(C.warn) .. "STALE|r" end
    return ""
end

local function sortOf(name, default)
    local s = U().sort and U().sort[name]
    if s then return s[1], s[2] end
    return default[1], default[2]
end

local function makeTable(parent, name, cols, rowH, default, fill, onEnter, onClick)
    local t
    t = UI.Table(parent, cols, rowH, { icon = true, fontSize = 11, onEnter = onEnter, onClick = onClick,
        onSort = function(key, desc) U().sort = U().sort or {}; U().sort[name] = { key, desc } end })
    t:SetSort(sortOf(name, default))
    t.fill = fill
    t.name = name
    return t
end

-- Item tooltip lines for one holding.
local function holdingLines(tt, h)
    if not h then return end
    local mode = ns.db.settings.basis
    if (h.held or 0) > 0 then
        dl(tt, "You hold", KM.Commas(h.held) .. (h.avg and (" at " .. KM.Money(h.avg) .. " each") or ""))
        if h.each then
            dl(tt, "Worth now, after the cut", KM.Money(h.each) .. " each, " .. KM.Money(h.worth))
            dl(tt, "If sold now", signed(h.ifSold, true) .. (h.roi and ("  " .. pctPlain(h.roi)) or ""))
        else
            tt:AddLine("No price: scan at the auction house to value it.", 0.6, 0.6, 0.6, true)
        end
        for i, L in ipairs(h.lots) do
            if i > 6 then tt:AddLine("  and " .. (#h.lots - 6) .. " more lots", 0.6, 0.6, 0.6) break end
            local cost = (L.k == "l" and mode ~= "market") and "free" or ("at " .. KM.Money(ns.UnitBasis(L, mode)))
            local got = (L.k == "l" and (L.s == "quest" and "got" or "farmed")) or (L.k == "o" and "owned")
                or (L.k == "k" and "made") or (L.k == "t" and "traded for") or "bought"
            tt:AddLine("  " .. L.left .. " " .. got .. " " .. ns.Day(L.t) .. " " .. cost .. " (" .. ns.HowLong(L) .. ")", 1, 1, 1)
        end
    end
    local where = {}
    for who, n in pairs(h.where or {}) do where[#where + 1] = { who, n } end
    table.sort(where, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    if #where > 0 then
        local parts = {}
        for i, x in ipairs(where) do if i <= 4 then parts[#parts + 1] = first(x[1]) .. " " .. x[2] end end
        dl(tt, "Who holds it", table.concat(parts, ", ") .. (#where > 4 and ", ..." or ""))
    end
    if (h.onAH or 0) > 0 then dl(tt, "On the auction house", tostring(h.onAH)) end
    if h.listedEach then
        local text = "listed at " .. KM.Money(math.floor(h.listedEach + 0.5))
        if h.listedROI then text = text .. ": " .. pctPlain(h.listedROI) .. " if they sell" end
        tt:AddLine((h.listed < (h.onAH or 0) and (h.listed .. " of them ") or "") .. text .. ".",
            h.listedROI and h.listedROI < 0 and C.bad[1] or 0.85, h.listedROI and h.listedROI < 0 and C.bad[2] or 0.85,
            h.listedROI and h.listedROI < 0 and C.bad[3] or 0.85, true)
    end
    if (h.untraced or 0) > 0 then
        tt:AddLine(h.untraced .. " more with no lot (untraced): valued, never given a cost. Adopt counts them as opening stock.", 0.7, 0.7, 0.7, true)
    end
    if h.breakEven then
        tt:AddLine("List at " .. KM.Money(math.ceil(h.breakEven)) .. " or more to cover what you paid and the cut.", C.accent[1], C.accent[2], C.accent[3], true)
    end
    if h.stale then tt:AddLine("The market price is over a week old: scan again.", C.warn[1], C.warn[2], C.warn[3], true) end
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------

local ITEM_COLS = {
    col("name", "Item", 196, nil, byName, nil, false),
    col("sold", "Sold", 50, R, function(r) return r.sold end, "Units sold in this period."),
    col("price", "Avg price", 80, R, function(r) return r.avgPrice end, "What one sold for on average, after the 5% cut."),
    col("cost", "Avg cost", 80, R, function(r) return r.avgCost end, "What one of the sold units cost you on average (the lots the sales used). Farmed units are free unless you count them at their value."),
    col("realized", "Profit", 90, R, function(r) return r.realized end, "What the sales brought after the cut, minus what those units cost you."),
    col("roi", "ROI", 60, R, function(r) return r.roi end, "Profit against what the sold units cost. Free (farmed) units show free."),
    col("held", "Held", 56, R, function(r) return r.heldAvg end, "How long you held a unit before it sold, on average: how fast this item turns your gold over."),
    col("stock", "In stock", 0, R, function(r) return r.hold end, "How many you still hold. Red: worth less now than they cost you (underwater). Holdings has the details."),
}

local function fillItem(r, row, cells)
    r.icon:SetTexture(icon(row.item))
    cells.name:SetText(KM.ItemText(row.item))
    cells.sold:SetText(KM.Commas(row.sold))
    cells.price:SetText(row.avgPrice and KM.MoneyShort(row.avgPrice) or grey("-"))
    local free = row.matchedQ > 0 and (row.basis or 0) == 0
    cells.cost:SetText(free and (hex(C.muted) .. "free|r") or (row.avgCost and KM.MoneyShort(row.avgCost) or grey("no cost")))
    cells.realized:SetText(row.realized and signed(row.realized) or grey("-"))
    cells.roi:SetText(row.roi and pct(row.roi) or (free and (hex(C.muted) .. "free|r") or grey("-")))
    cells.held:SetText(row.heldAvg and ageText(row.heldAvg) or grey("-"))
    local hold = row.hold or 0
    cells.stock:SetText(hold > 0 and ((row.under and hex(C.bad) or "") .. KM.Commas(hold) .. (row.under and "|r" or "")) or grey("-"))
    tint(r, row.under)
end

local function itemEnter(r)
    local row = r.data
    if not row then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, row.item) else GameTooltip:AddLine(KM.ItemText(row.item)) end
    GameTooltip:AddLine(" ")
    if row.sold > 0 then
        dl(GameTooltip, "Sold in this period", row.sold .. " in " .. row.sales .. " sale" .. (row.sales == 1 and "" or "s"))
        if row.realized then dl(GameTooltip, "Realized", signed(row.realized, true)) end
    end
    holdingLines(GameTooltip, row.h)
    GameTooltip:AddLine("Click: its lots (Trades > By buy).  Right-click: more.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function itemMenu(owner, id)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(nameOf(id))
        root:CreateButton("Its lots (Trades > By buy)", function() ns.ShowItemLots(id) end)
        local econ = KM.mods.Econ
        if econ and econ.ShowItem then
            root:CreateButton("Price History", function()
                if econ.Toggle then KM.Safe(econ.Toggle, true) end
                KM.Safe(econ.ShowItem, id)
            end)
        end
        root:CreateButton("Print its lots in chat", function() for _, l in ipairs(ns.ItemReport(id)) do KM.Print(ns, l) end end)
    end)
end

local function itemClick(row, which, r)
    if which == "RightButton" then itemMenu(r, row.item) else ns.ShowItemLots(row.item) end
end

local TILE_KEYS = { "realized", "sales", "stock", "ifsold" }

local function buildOverview(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetPoint("TOPLEFT", 0, -64)
    v:SetPoint("BOTTOMRIGHT", 0, 0)
    P.ov = v
    P.tiles = {}
    for i, key in ipairs(TILE_KEYS) do
        local t = UI.Tile(v, 119, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (119 + GAP), 0)
        P.tiles[key] = t
        P.tiles[i] = t
    end
    local T = P.tiles
    T.realized:SetTip(function(tt)
        local S = P.S or {}
        tt:AddLine("Profit you've taken: what your sales brought after the 5% cut, minus what those units cost you, minus deposits on auctions that came back.", 1, 1, 1, true)
        dl(tt, "Brought in (units with a cost)", KM.Money(S.proceeds or 0))
        dl(tt, "What those units cost", "-" .. KM.Money(S.basis or 0))
        dl(tt, "Deposits lost", "-" .. KM.Money(S.deposits or 0))
        dl(tt, "Profit", signed(S.realized, true))
        if S.roi then dl(tt, "Return on cost", pctPlain(S.roi)) end
        tt:AddLine("Everything, with sales of unknown cost and stock used or gone: " .. signedPlain(S.allIn) .. ".", 0.8, 0.8, 0.8, true)
        if (S.folded or 0) > 0 then tt:AddLine(S.folded .. " older month" .. (S.folded == 1 and "" or "s") .. " counted from monthly totals.", 0.6, 0.6, 0.6, true) end
        scopeLine(tt)
    end)
    T.sales:SetTip(function(tt)
        local S = P.S or {}
        tt:AddLine("Everything your sales brought in this period, after the 5% cut: auction house, vendors and trades.", 1, 1, 1, true)
        dl(tt, "Sales", (S.sales or 0) .. " (" .. KM.Commas(S.units or 0) .. " units)")
        dl(tt, "Brought in", KM.Money((S.proceeds or 0) + (S.unknownP or 0)))
        if (S.unknownP or 0) > 0 then dl(tt, "  of it with no cost known", KM.Money(S.unknownP)) end
        if S.heldAvg then dl(tt, "Held before selling, on average", ageText(S.heldAvg)) end
        scopeLine(tt)
    end)
    T.stock:SetTip(function(tt)
        local S = P.S or {}
        tt:AddLine("What the stock you hold is worth now (market price after the cut), against what it cost you: bought items at what you paid, opening stock at its value the day tracking began, farmed items free (or at their value when looted).", 1, 1, 1, true)
        dl(tt, "Units held (in lots)", KM.Commas(S.held or 0))
        dl(tt, "Worth now", KM.Money(S.worth or 0))
        dl(tt, "Cost", KM.Money(S.cost or 0))
        if (S.noPrice or 0) > 0 then tt:AddLine(S.noPrice .. " item" .. (S.noPrice == 1 and "" or "s") .. " with no price left out of Worth: scan at the auction house.", 0.7, 0.7, 0.7, true) end
        if (S.untraced or 0) > 0 then
            tt:AddLine(KM.Commas(S.untraced) .. " more you own have no lot (untraced, worth " .. KM.Money(S.untracedWorth or 0) .. "): valued, never given a cost. Holdings > Count them as opening stock.", 0.7, 0.7, 0.7, true)
        end
    end)
    T.ifsold:SetTip(function(tt)
        local S = P.S or {}
        tt:AddLine("Profit you haven't taken yet: what selling everything you hold right now would make, at today's market price after the cut, minus what it cost you.", 1, 1, 1, true)
        dl(tt, "If sold now", signed(S.ifSold, true))
        dl(tt, "Underwater", (S.underwater or 0) .. " item" .. ((S.underwater or 0) == 1 and "" or "s") .. ((S.underwater or 0) > 0 and (", " .. signedPlain(S.underwaterLoss)) or ""))
        tt:AddLine("Underwater: worth less now than it cost you. Holdings marks them UNDER with the price that breaks even. Click for Holdings.", 0.7, 0.7, 0.7, true)
    end)
    T.ifsold:SetScript("OnMouseUp", function() UI.Click(); ns.SelectTab("holdings") end)
    T.stock:SetScript("OnMouseUp", function() UI.Click(); ns.SelectTab("holdings") end)

    -- What's kept out of profit, on purpose: one muted line, the details on hover.
    P.aside = CreateFrame("Frame", nil, v)
    P.aside:SetPoint("TOPLEFT", 0, -(TILE_H + 4))
    P.aside:SetPoint("TOPRIGHT", 0, -(TILE_H + 4))
    P.aside:SetHeight(ASIDE_H)
    P.asideText = UI.Text(P.aside, 10, C.muted)
    P.asideText:SetPoint("LEFT", 2, 0)
    P.asideText:SetPoint("RIGHT", -2, 0)
    UI.Tip(P.aside, function(tt)
        local S = P.S or {}
        tt:AddLine("Kept out of profit")
        tt:AddLine("Sold, cost unknown: what sales brought for units no lot covered (given to you, or made while King Maker couldn't see it).", 1, 1, 1, true)
        dl(tt, "  Brought in", KM.Money(S.unknownP or 0) .. ", " .. KM.Commas(S.unknownQ or 0) .. " units")
        tt:AddLine("Used or gone: what stock that left without a sale had cost you (used, eaten, equipped, mailed away, used in a craft that made nothing to sell).", 1, 1, 1, true)
        dl(tt, "  Pending (under 30 days)", KM.Money(S.gonePending or 0))
        dl(tt, "  Final", KM.Money(S.goneFinal or 0))
        tt:AddLine("Pending is undone if the units turn up again (mail to an alt, a bank not opened) or a late sale mail explains them.", 0.7, 0.7, 0.7, true)
        scopeLine(tt)
    end)

    local cp = UI.Panel(v, C.panel)
    cp:SetPoint("TOPLEFT", 0, -(TILE_H + ASIDE_H + GAP))
    cp:SetHeight(150)
    P.chartPanel = cp
    local head = UI.Heading(cp, "Realized per day")
    head:SetPoint("TOPLEFT", 10, -8)
    P.chartHead = head
    P.chartTotal = UI.Text(cp, 11, C.text, "RIGHT")
    P.chartTotal:SetPoint("TOPRIGHT", -10, -8)
    P.chart = UI.Chart(cp, 458, 118)
    P.chart.frame:SetPoint("TOPLEFT", 6, -24)

    local sp = UI.Panel(v, C.panel)
    sp:SetPoint("TOPRIGHT", 0, -(TILE_H + ASIDE_H + GAP))
    sp:SetSize(284, 150)
    P.srcPanel = sp
    local sh = UI.Heading(sp, "Where it came from")
    sh:SetPoint("TOPLEFT", 10, -8)
    P.hbars = UI.HBars(sp, 264, 17, 6)
    P.hbars:SetPoint("TOPLEFT", 10, -26)
    for _, row in ipairs(P.hbars.rows) do
        row:SetScript("OnClick", function(self)
            if self.data and self.data.kind then P.from = self.data.kind; U().tab = "trades"; U().sub = "sale"; U().filter = "all"; KM.Refresh("profit") end
        end)
    end
    P.srcNote = UI.Text(sp, 10, C.muted)
    P.srcNote:SetPoint("BOTTOMLEFT", 10, 8)
    P.srcNote:SetPoint("RIGHT", sp, "RIGHT", -10, 0)

    P.itemTable = makeTable(v, "items", ITEM_COLS, 22, { "realized", true }, fillItem, itemEnter, itemClick)
    P.itemTable:SetPoint("TOPLEFT", 0, -(TILE_H + ASIDE_H + GAP + 160))
    P.itemTable:SetPoint("BOTTOMRIGHT", 0, 20)
end

local SOURCES = { { "b", "Auction buys" }, { "l", "Farmed" }, { "k", "Crafted" }, { "o", "Opening stock" }, { "mt", "Vendor, trades" } }
local SOURCE_WORDS = { b = "auction house purchases", l = "loot and quest rewards", k = "crafting and disenchanting",
    o = "stock you owned before tracking began", mt = "vendors and trades" }
local function sourceOf(k) return (k == "m" or k == "t") and "mt" or k end

local function drawChart(sinceT, mine)
    local week = (U().period or 30) == 0
    local days = ns.Daily(sinceT, mine, nil, week)
    local now = KM.Now()
    local tmin = sinceT
    if tmin == 0 then tmin = (days[1] and days[1].t) or (now - 30 * DAY) end
    local pts, total, n = {}, 0, 0
    for _, d in ipairs(days) do
        local col = d.pl >= 0 and { C.good[1], C.good[2], C.good[3], d.pl ~= 0 and 0.85 or 0.25 } or { C.bad[1], C.bad[2], C.bad[3], 0.85 }
        pts[#pts + 1] = { d.t + (week and 3.5 * DAY or DAY / 2), d.pl, col, d }
        total, n = total + d.pl, n + 1
    end
    local span = math.max(1, math.ceil((now - tmin) / (week and 7 * DAY or DAY)))
    local avg = span > 1 and total / span or nil
    P.chartHead:SetText(week and "REALIZED PER WEEK" or "REALIZED PER DAY")
    P.chartTotal:SetText(signed(total))
    P.chart:Draw({
        tmin = tmin, tmax = now + (week and 7 * DAY or DAY),
        series = { { pts = pts, style = "bars", agg = "none" } },
        format = function(y) return KM.MoneyShort(y, true) end,
        xformat = function(x) return ns.Day(x) end,
        ref = (avg and n > 0) and { y = avg, label = "avg " .. signedPlain(avg) } or nil,
        hover = function(_, p)
            local d = p and p[4]
            if not d then return end
            GameTooltip:AddLine((week and "Week of " or "") .. (date and date("%a %d %b", d.t) or ns.Day(d.t)))
            dl(GameTooltip, "Realized", signed(d.pl, true))
            dl(GameTooltip, "Sales", tostring(d.sales))
            if d.best then dl(GameTooltip, "Best trade", nameOf(d.best.item) .. " " .. signedPlain(d.best.pl)) end
            if d.pl < 0 then GameTooltip:AddLine("Red: a losing " .. (week and "week" or "day") .. ".", 0.6, 0.6, 0.6) end
        end,
        emptyText = "No sales in this period yet",
    })
end

local function drawSources(sinceT, mine)
    local src = ns.Sources(sinceT, mine)
    src.mt, src.n.mt = src.m + src.t, src.n.m + src.n.t
    local rows, top = {}, 1
    for _, s in ipairs(SOURCES) do top = math.max(top, math.abs(src[s[1]])) end
    top = math.max(top, src.dep)
    for _, s in ipairs(SOURCES) do
        local v = src[s[1]]
        rows[#rows + 1] = { label = s[2], value = signed(v), frac = math.abs(v) / top, color = v >= 0 and C.good or C.bad, kind = s[1],
            tip = function(tt)
                tt:AddLine(s[2])
                tt:AddLine("Realized on units that came from " .. SOURCE_WORDS[s[1]] .. ": " .. signedPlain(v) .. " on " .. KM.Commas(src.n[s[1]]) .. " units.", 1, 1, 1, true)
                tt:AddLine("Click: those trades.", 0.6, 0.6, 0.6)
            end }
    end
    rows[#rows + 1] = { label = "Deposits lost", value = signed(-src.dep), frac = src.dep / top, color = C.bad,
        tip = "Deposits on auctions that came back expired or cancelled: a cost of trading, taken off Realized." }
    P.hbars:SetRows(rows)
    P.srcNote:SetText(ns.db.settings.basis == "market" and "Farmed items cost their value when looted." or "Farmed items count as free.")
end

local function refreshOverview(w)
    local s, mine = since(), charKey()
    local S = ns.Summary(s, mine)
    P.S = S
    local T = P.tiles
    T.realized:Set("Profit", signedPlain(S.realized), S.roi and (pctPlain(S.roi) .. " on cost") or "nothing sold at a cost yet", tone(S.realized))
    local brought = S.proceeds + S.unknownP
    T.sales:Set("Sales", KM.MoneyShort(brought, true), S.sales .. " sale" .. (S.sales == 1 and "" or "s")
        .. (S.sales > 0 and (", avg " .. KM.MoneyShort(brought / S.sales, true)) or ""))
    T.stock:Set("Stock worth", KM.MoneyShort(S.worth, true), KM.Commas(S.held) .. " held, cost " .. KM.MoneyShort(S.cost, true))
    T.ifsold:Set("If sold now", signedPlain(S.ifSold), S.underwater > 0 and (hex(C.bad) .. S.underwater .. " underwater " .. signedPlain(S.underwaterLoss) .. "|r") or "nothing underwater", tone(S.ifSold))
    local gone = S.gonePending + S.goneFinal
    P.asideText:SetText("Kept out of profit:  sold with cost unknown " .. KM.MoneyShort(S.unknownP, true) .. " (" .. KM.Commas(S.unknownQ) .. " units)"
        .. "   |   used or gone " .. (gone > 0 and ("-" .. KM.MoneyShort(gone, true)) or "0c")
        .. (S.gonePending > 0 and (" (" .. KM.MoneyShort(S.gonePending, true) .. " pending)") or "") .. "   |   hover for what these are")
    drawChart(s, mine)
    drawSources(s, mine)
    local empty = S.sales == 0 and S.held == 0 and (S.untraced or 0) == 0
    P.itemTable.emptyText = empty and "Nothing to match yet. Buy or sell something at the auction house and open your mailbox: every purchase becomes a lot, and every sale is matched to what you paid."
        or "Nothing sold in this period. What you hold is on Holdings."
    local sold = {}
    for _, r in ipairs(ns.ByItem(s, mine)) do if r.sold > 0 then sold[#sold + 1] = r end end
    P.itemTable:SetRows(sold)
    if not hasInventory() then
        P.footer:SetText("Counts are off: what you hold isn't checked (no Inventory module).")
    else
        P.footer:SetText(#sold .. " item" .. (#sold == 1 and "" or "s") .. " sold.  " .. (ns.db.start and ("Tracking since " .. ns.Day(ns.db.start) .. ".  ") or "")
            .. "Click one for its lots.")
    end
end

---------------------------------------------------------------------------
-- Trades
---------------------------------------------------------------------------

local SALE_COLS = {
    col("t", "Sold", 92, nil, function(r) return r.t end),
    col("name", "Item", 168, nil, byName, nil, false),
    col("q", "Qty", 38, R, function(r) return r.q end),
    col("each", "Each", 68, R, function(r) return r.each end, "What each unit brought, after the 5% cut."),
    col("costEach", "Cost ea", 68, R, function(r) return r.costEach end, "What each unit cost you (the lots it used)."),
    col("pl", "P&L", 80, R, function(r) return r.pl end, "What the sale brought after the cut minus what those units cost. \"no cost\": no lot covered it (given to you, or made while the module couldn't see it)."),
    col("roi", "ROI", 50, R, function(r) return r.roi end, "P&L against what the units cost."),
    col("held", "Held", 44, R, function(r) return r.held end, "How long you held the units before they sold, on average."),
    col("char", "Char", 70, nil, function(r) return r.char or "" end, "The character whose auction it was.", false),
    col("from", "From", 0, nil, nil, "Where the units came from: AH, farmed, crafted, vendor, a trade, or how many lots. Hover the sale for when."),
}
local BUY_COLS = {
    col("t", "Got", 76, nil, function(r) return r.t end),
    col("name", "Item", 150, nil, byName, nil, false),
    col("how", "How", 56, nil, function(r) return r.how end, "AH: bought at the auction house. Farmed: looted. Quest: a quest reward. Crafted: made from your mats (it costs what they cost). DE: disenchanted (a share of the item's cost). Trade: got in a trade. Vendor: bought from one. Opening: owned before tracking began (or adopted).", false),
    col("q", "Qty", 36, R, function(r) return r.q end),
    col("each", "Each", 72, R, function(r) return r.each end, "What each unit cost you."),
    col("sold", "Sold", 40, R, function(r) return r.sold end, "Units of this lot that sales used up."),
    col("left", "Left", 40, R, function(r) return r.left end, "Units of this lot still open."),
    col("realized", "Realized", 78, R, function(r) return r.realized end, "P&L on the units of this lot that sold."),
    col("openPL", "Open P&L", 78, R, function(r) return r.openPL end, "What the units left would make if sold now, after the cut."),
    col("status", "Status", 0, nil, function(r) return r.status end, "CLOSED: all used up. PART: some used. OPEN: none yet. Then its age.", false),
}
local GONE_COLS = {
    col("t", "When", 76, nil, function(r) return r.t end),
    col("name", "Item", 170, nil, byName, nil, false),
    col("q", "Qty", 40, R, function(r) return r.q end),
    col("cost", "Cost", 80, R, function(r) return r.cost end, "What those units had cost you."),
    col("from", "From", 90, nil, nil, "The lots they came from."),
    col("char", "Char", 80, nil, function(r) return r.char or "" end, nil, false),
    col("status", "Status", 0, nil, function(r) return r.state end, "Pending: undone if they turn up again or a sale mail explains them, within 30 days. Used or gone: final. Before tracking: what your history said you held on day one but you didn't.", false),
}

local function fillSale(r, x, cells)
    r.icon:SetTexture(icon(x.item))
    cells.t:SetText(ns.When(x.t))
    cells.name:SetText(KM.ItemText(x.item))
    cells.q:SetText(tostring(x.q))
    cells.each:SetText(KM.MoneyShort(x.each))
    cells.costEach:SetText(x.costEach and KM.MoneyShort(x.costEach) or grey("-"))
    cells.pl:SetText(x.pl and signed(x.pl) or grey("no cost"))
    cells.roi:SetText(x.pl and (x.basis > 0 and pct(x.roi) or hex(C.muted) .. "free|r") or grey("-"))
    cells.held:SetText(x.held and ageText(x.held) or grey("-"))
    cells.char:SetText(first(x.char))
    local from = (x.from or "-"):gsub(" %d+ %a+$", "")  -- "AH 22 Nov" -> "AH": the date is in the tooltip
    if x.kind == "n" then from = "vendor sale"
    elseif x.kind == "t" then from = "trade" .. (x.partner and x.partner ~= "" and (" to " .. first(x.partner)) or "") end
    cells.from:SetText(from == "-" and grey("-") or from)
    tint(r, false)
end

local function saleEnter(r)
    local x = r.data
    if not x then return end
    local tt = GameTooltip
    tt:SetOwner(r, "ANCHOR_RIGHT")
    tt:AddLine(KM.ItemText(x.item))
    local how = (x.kind == "n" and "Sold to a vendor ") or (x.kind == "t" and ("Traded to " .. (x.partner or "someone") .. " "))
        or "Sold at the auction house "
    tt:AddLine(how .. ns.When(x.t) .. ": " .. x.q .. " for " .. KM.Money(x.proceeds)
        .. (x.kind == "s" and " after the cut" or (x.kind == "t" and " (what you got for them)" or "")), 1, 1, 1, true)
    for _, p in ipairs(x.parts) do if p.q > 0 then tt:AddLine(ns.PartText(x.pool, p), 0.85, 0.85, 0.85, true) end end
    if x.unQ > 0 then tt:AddLine(x.unQ .. " unit" .. (x.unQ == 1 and "" or "s") .. " no lot covered: " .. KM.Money(x.unP) .. " of the sale, outside Realized (cost unknown).", 0.7, 0.7, 0.7, true) end
    if x.pl then
        tt:AddLine("P&L " .. signedPlain(x.pl) .. (x.roi and (" (" .. pctPlain(x.roi) .. ")") or (x.basis == 0 and " (free)" or ""))
            .. (x.held and (", held " .. ageText(x.held) .. " on average") or "") .. ".", 1, 1, 1, true)
    end
    tt:AddLine("Right-click: more.", 0.6, 0.6, 0.6)
    tt:Show()
end

local function fillBuy(r, b, cells)
    r.icon:SetTexture(icon(b.item))
    cells.t:SetText(ns.When(b.t))
    cells.name:SetText(KM.ItemText(b.item))
    cells.how:SetText(b.how)
    cells.q:SetText(tostring(b.q))
    cells.each:SetText((b.k == "l" and ns.db.settings.basis ~= "market") and (hex(C.muted) .. "free|r") or KM.MoneyShort(b.each))
    cells.sold:SetText(b.sold > 0 and tostring(b.sold) or grey("-"))
    cells.left:SetText(b.left > 0 and tostring(b.left) or grey("0"))
    cells.realized:SetText(b.realized and signed(b.realized) or grey("-"))
    cells.openPL:SetText(b.openPL and signed(b.openPL) or grey("-"))
    local word = b.status == "closed" and (hex(C.dim) .. "CLOSED|r") or (b.status == "part" and (hex(C.info) .. "PART|r") or (hex(C.accent) .. "OPEN|r"))
    cells.status:SetText(word .. "  " .. ageText(b.age))
    tint(r, false)
end

local function buyEnter(r)
    local b = r.data
    if not b then return end
    local tt = GameTooltip
    tt:SetOwner(r, "ANCHOR_RIGHT")
    tt:AddLine(KM.ItemText(b.item))
    local free = b.k == "l" and ns.db.settings.basis ~= "market"
    local word = (b.k == "l" and (b.src == "quest" and "Quest reward " or "Farmed ")) or (b.k == "o" and "Owned ")
        or (b.k == "k" and (b.how == "DE" and "Disenchanted " or "Crafted ")) or (b.k == "t" and "Traded for ") or "Bought "
    tt:AddLine(word .. ns.When(b.t) .. ": " .. b.q
        .. (free and " (free)" or (" at " .. KM.Money(b.each) .. " each, " .. KM.Money(b.cost))) .. " (" .. ns.HowLong(b.lot)
        .. (b.char and (", " .. first(b.char)) or "") .. ")", 1, 1, 1, true)
    if b.k == "k" then
        tt:AddLine(b.how == "DE" and "Its cost is its share of what the disenchanted item cost, by what the mats are worth."
            or "Its cost is what the mats that went into it cost (by the method you chose); mats with no lot count at their worth then.", 0.7, 0.7, 0.7, true)
    end
    if b.valueThen and b.k ~= "o" then dl(tt, "Worth when you got it", KM.Money(b.valueThen)) end
    for i, u in ipairs(b.uses) do
        if i > 8 then tt:AddLine("  ...", 0.6, 0.6, 0.6) break end
        if u.kind == "s" or u.kind == "n" then
            tt:AddLine("  " .. u.q .. " sold " .. ns.Day(u.t) .. " at " .. KM.Money(u.each) .. " each" .. (u.kind == "n" and " (vendor)" or ""), 0.85, 0.85, 0.85)
        elseif u.text then
            tt:AddLine("  " .. u.q .. " " .. u.text .. " " .. ns.Day(u.t), 0.7, 0.7, 0.7)
        else
            tt:AddLine("  " .. u.q .. (u.kind == "startup" and " before tracking" or (" used or gone " .. ns.Day(u.t) .. (u.pending and " (pending)" or ""))), 0.7, 0.7, 0.7)
        end
    end
    if b.realized then dl(tt, "Realized", signed(b.realized, true)) end
    if b.openPL then tt:AddLine("If the rest sold now: " .. signedPlain(b.openPL) .. ".", 1, 1, 1) end
    tt:Show()
end

local function fillGone(r, g, cells)
    r.icon:SetTexture(icon(g.item))
    cells.t:SetText(ns.When(g.t))
    cells.name:SetText(KM.ItemText(g.item))
    cells.q:SetText(tostring(g.q))
    cells.cost:SetText(KM.MoneyShort(g.cost))
    cells.from:SetText(g.from)
    cells.char:SetText(first(g.char))
    cells.status:SetText(g.state == "pending" and (hex(C.warn) .. g.status .. "|r") or (g.state == "startup" and grey(g.status) or g.status))
    tint(r, false)
end

local function goneEnter(r)
    local g = r.data
    if not g then return end
    local tt = GameTooltip
    tt:SetOwner(r, "ANCHOR_RIGHT")
    tt:AddLine(KM.ItemText(g.item))
    tt:AddLine(g.q .. " left with no sale " .. ns.When(g.t) .. ", costing " .. KM.Money(g.cost) .. ".", 1, 1, 1, true)
    for _, p in ipairs(g.parts) do if p.q > 0 then tt:AddLine(ns.PartText(g.pool, p), 0.85, 0.85, 0.85, true) end end
    if g.kind == "y" then
        tt:AddLine("Mailed to someone who isn't one of your characters on this realm and faction: gone at once.", 0.7, 0.7, 0.7, true)
    elseif g.kind == "u" then
        tt:AddLine("Used in a craft that made nothing you can sell (an enchant, or a product that binds): their cost is used up.", 0.7, 0.7, 0.7, true)
    elseif g.state == "pending" then
        tt:AddLine("Your characters hold fewer than your lots say. If they turn up again (mail to an alt, a bank not yet opened) or a sale mail explains them, this is undone. " .. g.daysLeft .. " day" .. (g.daysLeft == 1 and "" or "s") .. " left.", 0.7, 0.7, 0.7, true)
    elseif g.state == "startup" then
        tt:AddLine("On day one your Sales Ledger said you still held these, but you didn't. Never counted in a period.", 0.7, 0.7, 0.7, true)
    else
        tt:AddLine("Final: used, crafted with, eaten, equipped or given away. Beside your profit, never in it.", 0.7, 0.7, 0.7, true)
    end
    tt:Show()
end

local FILTERS = { { id = "all", label = "All", w = 48 }, { id = "wins", label = "Wins", w = 56 }, { id = "losses", label = "Losses", w = 64 },
    { id = "unknown", label = "Cost unknown", w = 104 }, { id = "gone", label = "Not sold", w = 76 } }

local function buildTrades(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetPoint("TOPLEFT", 0, -64)
    v:SetPoint("BOTTOMRIGHT", 0, 0)
    P.tr = v
    P.sub = UI.Tabs(v, { { id = "sale", label = "By sale", w = 84 }, { id = "buy", label = "By buy", w = 84 } }, function(id)
        if U().sub == id then P.from, P.only = nil, nil end
        U().sub = id
        if id == "buy" and U().filter == "unknown" then U().filter = "all" end
        KM.Refresh("profit")
    end)
    P.sub:SetPoint("TOPLEFT", 0, 0)
    P.filter = UI.Tabs(v, FILTERS, function(id) U().filter = id; KM.Refresh("profit") end)
    P.filter:SetPoint("LEFT", P.sub, "RIGHT", 12, 0)
    P.trSum = UI.Text(v, 11, C.text, "RIGHT")
    P.trSum:SetPoint("TOPRIGHT", 0, -6)
    local saleMenu = function(x, which, r) if which == "RightButton" then itemMenu(r, x.item) end end
    P.saleTable = makeTable(v, "sale", SALE_COLS, 20, { "t", true }, fillSale, saleEnter, saleMenu)
    P.buyTable = makeTable(v, "buy", BUY_COLS, 20, { "t", true }, fillBuy, buyEnter, saleMenu)
    P.goneTable = makeTable(v, "gone", GONE_COLS, 20, { "t", true }, fillGone, goneEnter, saleMenu)
    for _, t in ipairs({ P.saleTable, P.buyTable, P.goneTable }) do
        t:SetPoint("TOPLEFT", 0, -32)
        t:SetPoint("BOTTOMRIGHT", 0, 20)
        t.onRedraw = function(self) ns.TradesFooter(self) end
    end
end

local function fromOK(x)
    if not P.from then return true end
    for _, p in ipairs(x.parts or {}) do if p.q > 0 and sourceOf(p.lot.k) == P.from then return true end end
    return false
end

function ns.TradesFooter(t)
    if not (t and t:IsShown()) then return end
    local n = #t.data
    local shown = math.min(n, t.visible or n)
    local what = t == P.saleTable and "sales" or (t == P.buyTable and "lots" or "closures")
    local hint = t == P.saleTable and "Hover a sale for the lots it used; right-click for Price History."
        or (t == P.buyTable and "Hover a lot for every sale and closure that used it." or "Hover one for what it means.")
    local filt = ""
    if P.from then
        for _, s in ipairs(SOURCES) do if s[1] == P.from then filt = "From: " .. s[2] .. " (click By sale again for all).  " end end
    end
    if P.only then filt = filt .. nameOf(P.only) .. " only (click the tab again for all).  " end
    P.footer:SetText((n > 0 and ((t.offset + 1) .. "-" .. (t.offset + shown) .. " of " .. n .. " " .. what .. ".  ") or "") .. filt .. hint)
end

local function refreshTrades()
    local s, mine = since(), charKey()
    local sub, filter = U().sub or "sale", U().filter or "all"
    P.sub:Select(sub)
    P.filter:Select(filter)
    P.filter.buttons.unknown:SetShown(sub == "sale")
    local show
    if filter == "gone" then
        show = P.goneTable
        local rows = {}
        for _, g in ipairs(ns.NotSold(s, mine)) do if (not P.only or g.item == P.only) and matches(g.item) then rows[#rows + 1] = g end end
        local cost = 0
        for _, g in ipairs(rows) do cost = cost + g.cost end
        P.trSum:SetText(#rows .. " closure" .. (#rows == 1 and "" or "s") .. "  " .. hex(C.muted) .. KM.MoneyShort(cost, true) .. " cost|r")
        show.emptyText = "Nothing left without a sale in this period."
        show.pending = rows
    elseif sub == "buy" then
        show = P.buyTable
        local rows, realized = {}, 0
        for _, b in ipairs(ns.Buys(s, mine)) do
            local ok = (not P.only or b.item == P.only) and matches(b.item)
                and (filter == "all" or (filter == "wins" and (b.realized or 0) > 0) or (filter == "losses" and (b.realized or 0) < 0))
            if ok then rows[#rows + 1] = b; realized = realized + (b.realized or 0) end
        end
        P.trSum:SetText(#rows .. " lot" .. (#rows == 1 and "" or "s") .. "  " .. signed(realized))
        show.emptyText = "No lots got in this period."
        show.pending = rows
    else
        show = P.saleTable
        local rows, pl = {}, 0
        for _, x in ipairs(ns.Trades(s, mine)) do
            local ok = (not P.only or x.item == P.only) and fromOK(x) and matches(x.item)
                and (filter == "all" or (filter == "wins" and (x.pl or 0) > 0) or (filter == "losses" and (x.pl or 0) < 0)
                    or (filter == "unknown" and x.unQ > 0))
            if ok then rows[#rows + 1] = x; pl = pl + (x.pl or 0) end
        end
        P.trSum:SetText(#rows .. " sale" .. (#rows == 1 and "" or "s") .. "  " .. signed(pl))
        show.emptyText = "No sales in this period. Every auction house sale you read in your mailbox lands here, matched to what you paid."
        show.pending = rows
    end
    for _, t in ipairs({ P.saleTable, P.buyTable, P.goneTable }) do t:SetShown(t == show) end
    show:SetRows(show.pending)
end

-- Trades > By buy, filtered to one item.
function ns.ShowItemLots(id)
    P.only, P.from = id, nil
    U().tab, U().sub, U().filter = "trades", "buy", "all"
    if KM.IsShown("profit") then KM.Refresh("profit") else KM.Show("profit") end
end

---------------------------------------------------------------------------
-- Holdings
---------------------------------------------------------------------------

local HOLD_COLS = {
    col("name", "Item", 170, nil, byName, nil, false),
    col("held", "Held", 44, R, function(h) return h.held end, "Units you hold that have a lot."),
    col("avg", "Avg cost", 76, R, function(h) return h.avg end, "What they cost you, on average."),
    col("cost", "Cost", 78, R, function(h) return h.cost end, "What they cost you in all."),
    col("each", "Now each", 72, R, function(h) return h.each end, "What one would bring now, after the 5% cut (or a vendor's price if that pays more)."),
    col("worth", "Worth", 78, R, function(h) return h.worth end, "What they'd bring now, after the cut."),
    col("ifSold", "If sold", 82, R, function(h) return h.ifSold end, "Worth minus cost."),
    col("roi", "ROI", 50, R, function(h) return h.roi end, "If sold, against cost."),
    col("age", "Age", 40, R, function(h) return h.age end, "How long you've held the oldest of them."),
    col("flag", "", 0),
}

local function fillHold(r, h, cells)
    r.icon:SetTexture(icon(h.item))
    cells.name:SetText(KM.ItemText(h.item))
    cells.held:SetText(h.held > 0 and KM.Commas(h.held) or grey("0"))
    cells.avg:SetText(h.avg and KM.MoneyShort(h.avg) or grey("-"))
    cells.cost:SetText(h.held > 0 and KM.MoneyShort(h.cost) or grey("-"))
    cells.each:SetText(h.each and KM.MoneyShort(h.each) or grey("-"))
    cells.worth:SetText(h.worth and h.held > 0 and KM.MoneyShort(h.worth) or grey("-"))
    cells.ifSold:SetText(h.ifSold and h.held > 0 and signed(h.ifSold) or grey("-"))
    cells.roi:SetText(h.held > 0 and pct(h.roi) or grey("-"))
    cells.age:SetText(h.held > 0 and ageText(h.age) or grey("-"))
    local f = flagText(h)
    if f == "" and (h.untraced or 0) > 0 then f = grey("+" .. h.untraced) end
    cells.flag:SetText(f)
    tint(r, h.under)
end

local function holdEnter(r)
    local h = r.data
    if not h then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, h.item) else GameTooltip:AddLine(KM.ItemText(h.item)) end
    GameTooltip:AddLine(" ")
    holdingLines(GameTooltip, h)
    GameTooltip:AddLine("Click: its lots.  Right-click: more.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Price History's favorites as a set { [itemID] = true }, or nil without Price History.
local function favorites()
    local e = KM.mods.Econ
    local fav = e and e.db and e.db.fav
    if type(fav) ~= "table" then return nil end
    local out = {}
    for id, on in pairs(fav) do if on then out[id] = true end end
    return out
end

-- The holdings filter: nil (all items) or "Favorites". Older saves may hold a Shopping list's name: all items.
local function listFilter()
    return U().list == "Favorites" and favorites() and "Favorites" or nil
end

local function listMenu(_, root)
    root:CreateTitle("Show")
    root:CreateRadio("All items", function() return listFilter() == nil end, function() U().list = nil; KM.Refresh("profit") end)
    if favorites() then
        root:CreateRadio("Favorites", function() return U().list == "Favorites" end, function() U().list = "Favorites"; KM.Refresh("profit") end)
    end
end

local function buildHoldings(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetPoint("TOPLEFT", 0, -64)
    v:SetPoint("BOTTOMRIGHT", 0, 0)
    P.ho = v
    local strip = CreateFrame("Frame", nil, v)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetSize(390, 24)
    P.hText = UI.Text(strip, 11, C.text)
    P.hText:SetPoint("LEFT", 0, 0)
    P.hText:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    UI.Tip(strip, function(tt)
        local S = P.HS or {}
        tt:AddLine("What you hold")
        dl(tt, "Units held (in lots)", KM.Commas(S.held or 0))
        dl(tt, "What they cost", KM.Money(S.cost or 0))
        dl(tt, "Worth now, after the cut", KM.Money(S.worth or 0))
        dl(tt, "If sold now", signed(S.ifSold, true))
        dl(tt, "Underwater", (S.under or 0) .. " item" .. ((S.under or 0) == 1 and "" or "s") .. ", " .. signedPlain(S.underLoss or 0))
        if (S.noPrice or 0) > 0 then tt:AddLine(S.noPrice .. " with no price aren't in Worth.", 0.7, 0.7, 0.7, true) end
    end)
    P.ageLabel = UI.Text(v, 10, C.muted)
    P.ageLabel:SetPoint("LEFT", strip, "RIGHT", 10, 0)
    P.ageLabel:SetText("age")
    P.ageBar = UI.SplitBar(v, 120, 8)
    P.ageBar:SetPoint("LEFT", P.ageLabel, "RIGHT", 6, 0)
    local ageHover = CreateFrame("Frame", nil, v)
    ageHover:SetPoint("TOPLEFT", P.ageBar, "TOPLEFT", -2, 8)
    ageHover:SetPoint("BOTTOMRIGHT", P.ageBar, "BOTTOMRIGHT", 2, -8)
    UI.Tip(ageHover, function(tt)
        local a = (P.HS or {}).ages or { 0, 0, 0 }
        tt:AddLine("How long you've held it")
        tt:AddLine("Units held, by age: the bright part is under a week, the middle 7 to 30 days, the faint part over 30 days.", 1, 1, 1, true)
        dl(tt, "Under 7 days", KM.Commas(a[1]))
        dl(tt, "7 to 30 days", KM.Commas(a[2]))
        dl(tt, "Over 30 days", KM.Commas(a[3]))
    end)
    P.listBtn = UI.MenuButton(v, 150, function() return listFilter() and "Show: Favorites" or "Show: All items" end, listMenu)
    P.listBtn:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(P.listBtn, function(tt)
        tt:AddLine("Which items")
        tt:AddLine("Everything, or only your Price History favorites.", 1, 1, 1, true)
    end)
    P.holdTable = makeTable(v, "hold", HOLD_COLS, 20, { "ifSold", true }, fillHold, holdEnter,
        function(h, which, r) if which == "RightButton" then itemMenu(r, h.item) else ns.ShowItemLots(h.item) end end)
    P.holdTable:SetPoint("TOPLEFT", 0, -32)
    P.holdTable:SetPoint("BOTTOMRIGHT", 0, 30)
    P.adopt = UI.Button(c, "Count them as opening stock", 200, 20, function()
        if ns.Adopt then ns.Adopt() end
        KM.Refresh("profit")
    end)
    P.adopt:SetPoint("BOTTOMRIGHT", -8, 2)
    UI.Tip(P.adopt, "Every item you own beyond its lots becomes a lot at today's value, as if tracking began today for those units. Also /pnl adopt.")
end

local function refreshHoldings()
    local mine = charKey()
    local only = listFilter() and favorites() or nil
    local rows = {}
    for _, h in ipairs(ns.Holdings(nil, mine, only)) do if matches(h.item) then rows[#rows + 1] = h end end
    local S = { held = 0, cost = 0, worth = 0, ifSold = 0, under = 0, underLoss = 0, untraced = 0, untracedWorth = 0, noPrice = 0, ages = { 0, 0, 0 } }
    for _, h in ipairs(rows) do
        S.held, S.cost = S.held + h.held, S.cost + h.cost
        for i = 1, 3 do S.ages[i] = S.ages[i] + (h.ages[i] or 0) end
        if h.each then
            S.worth, S.ifSold = S.worth + (h.worth or 0), S.ifSold + (h.ifSold or 0)
            if h.under then S.under, S.underLoss = S.under + 1, S.underLoss + h.ifSold end
        elseif h.held > 0 then S.noPrice = S.noPrice + 1 end
        if (h.untraced or 0) > 0 then
            S.untraced = S.untraced + h.untraced
            S.untracedWorth = S.untracedWorth + (h.each and h.each * h.untraced or 0)
        end
    end
    P.HS = S
    P.hText:SetText(KM.Commas(S.held) .. " held - cost " .. KM.MoneyShort(S.cost) .. " - worth " .. KM.MoneyShort(S.worth)
        .. " - " .. signed(S.ifSold) .. " if sold" .. (S.under > 0 and (" - " .. hex(C.bad) .. S.under .. " under|r") or ""))
    local total = math.max(1, S.ages[1] + S.ages[2] + S.ages[3])
    local a = C.accent
    P.ageBar:Set({ { S.ages[1] / total, { a[1], a[2], a[3], 1 } }, { S.ages[2] / total, { a[1], a[2], a[3], 0.6 } }, { S.ages[3] / total, { a[1], a[2], a[3], 0.3 } } })
    P.listBtn:Refresh()
    P.holdTable.emptyText = (P.search and "Nothing you hold matches the search.") or (listFilter() and "You hold none of your favorites.")
        or "You hold nothing with a lot yet. Purchases, loot and opening stock land here."
    P.holdTable:SetRows(rows)
    local inv = hasInventory()
    P.adopt:SetShown(inv and S.untraced > 0 and not mine)
    if not inv then
        P.footer:SetText("Counts are off: what you hold isn't checked (no Inventory module). Lots stay open until a sale uses them.")
    elseif S.untraced > 0 then
        P.footer:SetText(KM.Commas(S.untraced) .. " untraced item" .. (S.untraced == 1 and "" or "s") .. " worth " .. KM.MoneyShort(S.untracedWorth) .. " have no cost known.")
    else
        P.footer:SetText("Every item you hold has a lot. Hover one for its lots and the price that breaks even.")
    end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function layout(c)
    local w = c and c:GetWidth() or 0
    if not w or w < 400 then w = 764 end
    if w == P.width then return end
    P.width = w
    local n = #P.tiles
    local tw = math.floor((w - (n - 1) * GAP) / n)
    for i, t in ipairs(P.tiles) do
        t:SetSize(tw, TILE_H)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", (i - 1) * (tw + GAP), 0)
    end
    local cw = w - 284 - GAP
    P.chartPanel:SetWidth(cw)
    P.chart:SetSize(cw - 12, 118)
end

local function build(c)
    P.container = c
    buildTop(c)
    buildOverview(c)
    buildTrades(c)
    buildHoldings(c)
    c:SetScript("OnSizeChanged", function(self) if self:IsShown() then KM.Refresh("profit") end end)
end

local function refresh(c)
    if not (ns.db and P.container) then return end
    layout(c)
    local tab = U().tab or "overview"
    P.tabs:Select(tab)
    P.periods:Select(U().period or 30)
    P.periods:SetShown(tab ~= "holdings")
    P.searchBox:SetShown(tab ~= "overview")
    P.charBtn:SetLabel(U().mine and "This character" or "All characters")
    P.charBtn:SetActive(U().mine and true or false)
    P.counting:Refresh()
    P.ov:SetShown(tab == "overview")
    P.tr:SetShown(tab == "trades")
    P.ho:SetShown(tab == "holdings")
    P.adopt:SetShown(false)
    if tab == "trades" then refreshTrades()
    elseif tab == "holdings" then refreshHoldings()
    else refreshOverview() end
end

function ns.SelectTab(id)
    if U().tab == id and id == "trades" then P.only, P.from = nil, nil end
    U().tab = id
    for _, t in ipairs({ P.saleTable, P.buyTable, P.goneTable, P.holdTable, P.itemTable }) do if t then t.offset = 0 end end
    KM.Refresh("profit")
end

function ns.Refresh() KM.Refresh("profit") end

-- Coin 01 is the Farming Ledger's and 02 the Prices page's (sidebar icons stay unique); 03 is a vanilla icon too.
local ICON = "Interface\\Icons\\INV_Misc_Coin_04"
if not (GetFileIDFromPath and GetFileIDFromPath(ICON)) then ICON = "Interface\\Icons\\INV_Misc_Coin_03" end

KM.RegisterPage({
    id = "profit", group = "gold", label = "Profit & Loss", icon = ICON, order = 5,
    title = "Profit & Loss",
    subtitle = "Every sale matched to what you paid, and what you still hold is worth.",
    build = build, refresh = refresh,
})

---------------------------------------------------------------------------
-- Export: trades and lots as comma-separated text
---------------------------------------------------------------------------

local exportWin

function ns.ExportText()
    local function q(v) v = tostring(v or ""); return v:find("[,\"]") and ('"' .. v:gsub('"', '""') .. '"') or v end
    local function d(t) return date and date("%Y-%m-%d %H:%M", t) or tostring(t) end
    local lines = { "trades", "date,item,quantity,proceeds,cost,pl,unknown_qty,held_days,character,from" }
    local trades = ns.Trades(0)
    for i = #trades, 1, -1 do
        local x = trades[i]
        lines[#lines + 1] = table.concat({ d(x.t), q(nameOf(x.item)), x.q, math.floor(x.proceeds + 0.5), math.floor(x.basis + 0.5),
            x.pl and math.floor(x.pl + 0.5) or "", x.unQ, x.held and string.format("%.1f", x.held / DAY) or "", q(x.char), q(x.from) }, ",")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "lots"
    lines[#lines + 1] = "got,item,how,quantity,cost,left,sold,used,character,source,made"
    local buys = ns.Buys(0)
    for i = #buys, 1, -1 do
        local b = buys[i]
        lines[#lines + 1] = table.concat({ d(b.t), q(nameOf(b.item)), b.how, b.q, math.floor(b.cost + 0.5), b.left, b.sold, b.used,
            q(b.char), q(b.src), b.made or 0 }, ",")
    end
    return table.concat(lines, "\n"), #trades, #buys
end

function ns.Export()
    if not ns.db then return end
    local text, nt, nb = ns.ExportText()
    if not exportWin then
        exportWin = UI.Window("KingMakerProfitExport", "Profit & Loss export", 600, 400)
        local hint = UI.Text(exportWin.body, 11, C.muted)
        hint:SetPoint("TOPLEFT", 0, 0)
        hint:SetText("Press Ctrl+A, then Ctrl+C, and paste it into a spreadsheet.")
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
        eb:SetWidth(552)
        eb:SetScript("OnEscapePressed", function() exportWin:Hide() end)
        box:EnableMouse(true)
        box:SetScript("OnMouseDown", function() eb:SetFocus() end)
        exportWin.box, exportWin.scroll = eb, sc
    end
    local eb = exportWin.box
    eb:SetText(text)
    local _, n = text:gsub("\n", "\n")
    local h = (n + 1) * 14 + 10
    eb:SetHeight(h)
    exportWin.scroll:SetContentHeight(h)
    exportWin.scroll:SetPos(0)
    exportWin:Show()
    if eb.HighlightText then eb:HighlightText(); eb:SetFocus() end
    KM.Print(ns, "Exported " .. nt .. " trades and " .. nb .. " lots.")
    return exportWin
end

---------------------------------------------------------------------------
-- Home, the crown, item tooltips
---------------------------------------------------------------------------

-- Realized P&L per day over the last n days, oldest first (0 on days with no sale): Home's spark and chart.
local function dailyPL(n)
    local now = KM.Now()
    local by = {}
    for _, d in ipairs(ns.Daily(now - n * DAY)) do by[math.floor((d.t + DAY / 2) / DAY)] = d end
    local out, today = {}, math.floor(now / DAY)
    for day = today - n + 1, today do
        local d = by[day]
        out[#out + 1] = { t = day * DAY + DAY / 2, pl = d and d.pl or 0, sales = d and d.sales or 0, best = d and d.best }
    end
    return out
end

KM.RegisterHomeTile({ id = "profit", order = 20, page = "profit", spark = function()
    if not (ns.db and ns.db.start) then return nil end
    local v = {}
    for _, d in ipairs(dailyPL(30)) do v[#v + 1] = d.pl end
    return v, C.good
end, get = function()
    if not (ns.db and ns.db.start) then return nil end
    local S = ns.Summary(KM.Now() - 7 * DAY)
    return "P&L, 7 days", signedPlain(S.realized), "if sold now " .. signedPlain(S.ifSold)
        .. (S.underwater > 0 and (" - " .. S.underwater .. " underwater") or ""), tone(S.realized)
end, tip = function(tt)
    local S = ns.Summary(KM.Now() - 7 * DAY)
    tt:AddLine("Realized profit over the last 7 days, on your characters on this realm and faction: what sales brought after the 5% cut, minus what those units cost you, minus deposits lost.", 1, 1, 1, true)
    dl(tt, "Realized", signed(S.realized, true))
    dl(tt, "Sales", tostring(S.sales))
    dl(tt, "If you sold what you hold now", signed(S.ifSold, true))
    if S.underwater > 0 then dl(tt, "Underwater", S.underwater .. " items, " .. signedPlain(S.underwaterLoss)) end
    tt:AddLine("Not counted: stock used or gone, and sales no purchase or loot covered. Open Profit & Loss for those and any period.", 0.7, 0.7, 0.7, true)
end })

-- Home: stock worth less than you paid (more than 1g in all), and the daily P&L chart.
KM.RegisterHomeCard({ kind = "attention", id = "profit-underwater", order = 30, get = function()
    if not (ns.db and ns.db.start) then return nil end
    local S = ns.Summary(KM.Now() - 7 * DAY)
    if S.underwater == 0 or S.underwaterLoss >= -10000 then return nil end
    return { { text = S.underwater .. " holding" .. (S.underwater == 1 and "" or "s") .. " underwater", color = C.warn,
        value = signedPlain(S.underwaterLoss), page = "profit", tab = function() ns.SelectTab("holdings") end,
        tip = S.underwater .. " item" .. (S.underwater == 1 and "" or "s") .. " you hold " .. (S.underwater == 1 and "is" or "are")
            .. " worth less than you paid: " .. KM.Money(S.underwaterLoss) .. " if you sold now. Click for Profit & Loss > Holdings and the break-even prices." } }
end })

KM.RegisterHomeCard({ kind = "chart", id = "daily", order = 20, label = "Daily profit", title = "Realized profit per day, 30 days",
    emptyText = "No sales in the last 30 days yet: open your mail after an auction sells.",
    shown = function() return ns.db and ns.db.start and true or false end,
    get = function()
        local pts, any = {}, false
        for _, d in ipairs(dailyPL(30)) do
            if d.sales > 0 or d.pl ~= 0 then any = true end
            pts[#pts + 1] = { d.t, d.pl, d.pl < 0 and C.bad or C.good, d }
        end
        if not any then return nil end
        return { series = { { pts = pts, style = "bars", agg = "none" } }, zero = true,
            format = function(v) return KM.MoneyShort(v, true) end,
            xformat = function(x) return date and date("%d %b", x) or tostring(x) end,
            hover = function(x, p)
                local d = p and p[4] or {}
                GameTooltip:AddLine(date and date("%d %b", x) or "", C.accent[1], C.accent[2], C.accent[3])
                GameTooltip:AddDoubleLine("Realized", signed(d.pl, true), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Sales", tostring(d.sales or 0), 1, 1, 1, 1, 1, 1)
                if d.best and d.best.pl then GameTooltip:AddDoubleLine("Best", (KM.ItemText and KM.ItemText(d.best.item) or "") .. " " .. signedPlain(d.best.pl), 0.8, 0.8, 0.8, 1, 1, 1) end
            end }
    end })

-- Home's numbers and top items, over the period Home asks for (30 days).
KM.RegisterHomeCard({ kind = "stats", id = "profit", order = 20, get = function(since)
    if not (ns.db and ns.db.start) then return nil end
    local S = ns.Summary(since)
    if S.sales == 0 and (S.held or 0) == 0 then return nil end -- nothing sold or held yet: no zeros
    local out = { { label = "Realized profit", value = signedPlain(S.realized), color = tone(S.realized),
        sub = S.sales .. " sale" .. (S.sales == 1 and "" or "s"), page = "profit",
        tip = "What your sales brought after the 5% cut, minus what those units cost you, minus deposits lost, over the last 30 days. Click for Profit & Loss." } }
    if S.roi then
        local held = S.heldAvg and (S.heldAvg >= DAY and (string.format("%.1f", S.heldAvg / DAY) .. " days to sell")
            or (math.max(1, math.floor(S.heldAvg / 3600 + 0.5)) .. " h to sell")) or nil
        out[#out + 1] = { order = 30, label = "Return on cost", value = (S.roi > 0 and "+" or "") .. math.floor(S.roi * 100 + 0.5) .. "%",
            color = tone(S.roi), sub = held and ("avg " .. held) or nil, page = "profit",
            tip = "Profit on what you sold as a share of what it cost you: " .. KM.Money(S.proceeds - S.basis) .. " on "
                .. KM.Money(S.basis) .. ". The average time from buying (or looting) to selling: how fast your gold turns over." }
    end
    if (S.held or 0) > 0 and S.ifSold then
        out[#out + 1] = { order = 80, label = "If sold now", value = signedPlain(S.ifSold), color = tone(S.ifSold),
            sub = KM.Commas(S.held) .. " held" .. (S.underwater > 0 and (", " .. S.underwater .. " underwater") or ""),
            page = "profit", tab = function() ns.SelectTab("holdings") end,
            tip = "What the stock you hold would make over what it cost you, sold today at its market price after the cut (unrealized). Click for Holdings." }
    end
    return out
end })

KM.RegisterHomeCard({ kind = "top", id = "profit", order = 10, get = function(since)
    if not (ns.db and ns.db.start) then return nil end
    local out = {}
    for _, r in ipairs(ns.ByItem(since)) do
        if r.realized and r.realized > 0 then
            out[#out + 1] = { item = r.item, value = r.realized, sub = "x" .. r.sold, page = "profit",
                tip = KM.Money(r.realized) .. " realized on " .. r.sold .. " sold" .. (r.roi and (", " .. math.floor(r.roi * 100 + 0.5) .. "% on cost") or "")
                    .. ", last 30 days. Click for Profit & Loss." }
            if #out >= 6 then break end
        end
    end
    return out
end })

KM.RegisterTooltip(function(tt)
    if not (ns.db and ns.db.start) then return end
    local S = ns.Summary(KM.Now() - 7 * DAY)
    tt:AddDoubleLine("P&L, last 7 days", KM.Money(S.realized) .. "  |cff8c8c8c(if sold now " .. signedPlain(S.ifSold) .. ")|r", 1, 1, 1, 1, 1, 1)
end)

-- "Your cost: 2g 10s each (40) - +45% if sold" (green or red) in item tooltips.
function ns.AddTooltipLines(tt, id)
    if not (ns.db and ns.db.start and ns.db.settings.tooltip and tt and id) then return end
    local h = ns.Holding(ns.MyPool(), id)
    if not h or h.held <= 0 or not h.avg then return end
    local text = KM.Money(h.avg) .. " each (" .. KM.Commas(h.held) .. ")"
    if h.roi then text = text .. "  " .. (h.roi >= 0 and hex(C.good) or hex(C.bad)) .. pctPlain(h.roi) .. " if sold|r" end
    local row = ScannerKing and ScannerKing.TooltipLine
    if row then row(tt, "Your cost", text) else tt:AddDoubleLine("Your cost", text, 0.78, 0.78, 0.78, 1, 1, 1) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if ScannerKing and ScannerKing.AddTooltipProvider then
        ScannerKing.AddTooltipProvider("Profit", function(tt, id) KM.Safe(ns.AddTooltipLines, tt, id) end)
    end
end)
