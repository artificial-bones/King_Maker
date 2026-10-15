local _, ns = ...

-- The Mail King window.
--   Top:     the tabs (Summary, Sales, Purchases, Expired, Items), the period
--            (Today, 7 days, 30 days, All) and whose mail (all characters or this one).
--   Summary: profit, income, the auction house cut, spent, deposits lost and
--            your gold on every character; profit per day for the last two weeks;
--            and every strategy, best first. Click a strategy for its items.
--   Lists:   every sale, purchase and expired auction, newest first.
--   Items:   every item you've traded: sold, average price, sell-through and
--            today's market price from Scanner King. Click a column to sort.
-- Right-click any item to choose its strategy (or make a new one).

local WIDTH, HEIGHT = 860, 560
local ROWS, ROW_H = 20, 18
local MAX_COLS = 11
local DAYS = 14
local PERIODS = { { 1, "Today" }, { 7, "7 days" }, { 30, "30 days" }, { 0, "All" } }
local TABS = { { "summary", "Summary" }, { "sale", "Sales" }, { "buy", "Purchases" }, { "expired", "Expired" }, { "items", "Items" }, { "stock", "Stock" } }

local frame, tabButtons, periodButtons, charBtn, footer
local summaryView, tiles, goldText, bars, stratTable
local listView, listTable
local tab, offset, strategyFilter = "summary", 0, nil
local sorts = { items = { key = "profit", desc = true }, stock = { key = "value", desc = true } } -- by column, per page
local current = {} -- the rows on show in the list

local function grey(t) return "|cff808080" .. t .. "|r" end
local function when(t) return date and date("%m-%d %H:%M", t) or tostring(t) end
local function pct(x) return x and string.format("%.0f%%", x * 100) or grey("-") end

local function since()
    local days = ns.db.ui.period
    if days == 0 then return 0 end
    if days == 1 then
        -- Today: since midnight.
        local now = ns.Now()
        local d = date and date("*t", now)
        if d then return now - (d.hour * 3600 + d.min * 60 + d.sec) end
    end
    return ns.Now() - days * 86400
end

local function onlyChar() return ns.db.ui.mine and ns.Char() or nil end

---------------------------------------------------------------------------
-- Choosing an item's strategy
---------------------------------------------------------------------------

StaticPopupDialogs.MAILKING_NEW_STRATEGY = {
    text = "Name the new strategy (a farm, a flip, a craft...):",
    button1 = OKAY or "OK",
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self, data)
        local box = self.editBox or self.EditBox
        local name = box and box:GetText()
        if name and name:match("%S") then ns.SetStrategy(data.item, data.name, name) end
    end,
    EditBoxOnEnterPressed = function(self, data)
        local name = self:GetText()
        if name and name:match("%S") then ns.SetStrategy(data.item, data.name, name) end
        self:GetParent():Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.StrategyMenu(owner, item, name)
    if not (item or name) then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Print("Right-click menus need a newer client.")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Strategy for " .. (name or ("item " .. item)))
        local chosen = ns.db.strategy[item or name] or (name and ns.db.strategy[name])
        root:CreateRadio("Automatic", function() return not chosen end, function() ns.SetStrategy(item, name, nil) end)
        for _, s in ipairs(ns.Strategies()) do
            root:CreateRadio(s, function() return chosen == s end, function() ns.SetStrategy(item, name, s) end)
        end
        root:CreateButton("New strategy...", function()
            StaticPopup_Show("MAILKING_NEW_STRATEGY", nil, nil, { item = item, name = name })
        end)
    end)
end

---------------------------------------------------------------------------
-- A table: headers you can click, rows of cells
---------------------------------------------------------------------------

local function makeTable(parent, nrows, onHeader)
    local t = { headers = {}, rows = {} }
    for i = 1, MAX_COLS do
        local h = CreateFrame("Button", nil, parent)
        h:SetHeight(18)
        h:SetNormalFontObject("GameFontNormalSmall")
        h:SetText("")
        h:SetScript("OnClick", function(self) if onHeader and self.key then onHeader(self.key) end end)
        h:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t.headers[i] = h
    end
    for i = 1, nrows do
        local r = CreateFrame("Button", nil, parent)
        r:SetSize(WIDTH - 40, ROW_H)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.cells = {}
        for c = 1, MAX_COLS do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            r.cells[c] = fs
        end
        t.rows[i] = r
    end
    function t.layout(cols)
        local x = 0
        for i = 1, MAX_COLS do
            local col, h = cols[i], t.headers[i]
            if col then
                h.key, h.label, h.tip = col.key, col.label, col.tip
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", x, 0)
                h:SetWidth(col.w)
                local fs = h:GetFontString()
                if fs then fs:ClearAllPoints(); fs:SetPoint(col.justify or "LEFT", (col.justify == "RIGHT") and -6 or 0, 0) end
                h:SetText(col.label)
                h:Show()
                for _, r in ipairs(t.rows) do
                    local c = r.cells[i]
                    c:ClearAllPoints()
                    c:SetPoint("LEFT", x, 0)
                    c:SetWidth(col.w - 6)
                    c:SetJustifyH(col.justify or "LEFT")
                    c:Show()
                end
                x = x + col.w
            else
                h.key = nil
                h:Hide()
                for _, r in ipairs(t.rows) do r.cells[i]:SetText(""); r.cells[i]:Hide() end
            end
        end
    end
    return t
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

local STRAT_COLS = {
    { key = "key", label = "Strategy", w = 170 },
    { key = "sales", label = "Sales", w = 60, justify = "RIGHT" },
    { key = "income", label = "Income", w = 120, justify = "RIGHT", tip = "What it sold for, minus the auction house cut." },
    { key = "spent", label = "Spent", w = 110, justify = "RIGHT", tip = "What you bought on the auction house." },
    { key = "lost", label = "Deposits lost", w = 110, justify = "RIGHT", tip = "Deposits on auctions that expired or were cancelled." },
    { key = "profit", label = "Profit", w = 120, justify = "RIGHT" },
    { key = "through", label = "Sell-through", w = 90, justify = "RIGHT", tip = "Of the auctions that ended, how many sold." },
}

local function through(r)
    local ended = r.sales + r.expired
    return ended > 0 and r.sales / ended or nil
end

local function refreshSummary()
    local s = ns.Summary(since(), onlyChar())
    tiles.profit:SetText(ns.Money(s.profit))
    tiles.income:SetText(ns.Money(s.income))
    tiles.cut:SetText(ns.Money(s.cut))
    tiles.spent:SetText(ns.Money(s.spent))
    tiles.lost:SetText(ns.Money(s.lost))
    tiles.sales:SetText(s.sales .. (s.expired > 0 and ("  " .. grey("(" .. s.expired .. " expired)")) or ""))
    local gold = ns.Gold()
    local stock = ns.Stock()
    goldText:SetText("Gold on your characters: " .. ns.Money(gold) .. "     Stock worth: " .. ns.Money(stock.value)
        .. "     Together: " .. ns.Money(gold + stock.value))

    -- Profit per day
    local days = ns.Daily(DAYS, onlyChar())
    local top = 1
    for _, d in ipairs(days) do top = math.max(top, math.abs(d.profit)) end
    for i, d in ipairs(days) do
        local b = bars[i]
        b.day = d
        local h = math.max(1, math.abs(d.profit) / top * 60)
        b.fill:SetHeight(h)
        b.fill:ClearAllPoints()
        if d.profit >= 0 then
            b.fill:SetPoint("BOTTOM", b, "CENTER", 0, 0)
            b.fill:SetColorTexture(0.3, 0.85, 0.3, d.profit ~= 0 and 0.9 or 0.25)
        else
            b.fill:SetPoint("TOP", b, "CENTER", 0, 0)
            b.fill:SetColorTexture(0.9, 0.3, 0.3, 0.9)
        end
    end

    -- Strategies
    local list = s.strategies
    for i, r in ipairs(stratTable.rows) do
        local e = list[i]
        if e then
            r.strategy = e.key
            local cells = r.cells
            cells[1]:SetText(e.key)
            cells[2]:SetText(e.sales > 0 and tostring(e.sales) or grey("-"))
            cells[3]:SetText(e.income ~= 0 and ns.Money(e.income) or grey("-"))
            cells[4]:SetText(e.spent ~= 0 and ns.Money(e.spent) or grey("-"))
            cells[5]:SetText(e.lost ~= 0 and ns.Money(e.lost) or grey("-"))
            cells[6]:SetText(ns.Money(e.profit))
            cells[7]:SetText(pct(through(e)))
            r:Show()
        else
            r.strategy = nil
            r:Hide()
        end
    end
    summaryView.empty:SetText(#list == 0 and ("Nothing in the ledger for this period yet. Open your mailbox: every auction house "
        .. "mail is recorded, sales dated when they sold.") or "")
    footer:SetText(#ns.db.entries .. " mails recorded.  Right-click an item in any list to choose its strategy.")
end

---------------------------------------------------------------------------
-- Lists and items
---------------------------------------------------------------------------

local LIST_COLS = {
    sale = {
        { key = "t", label = "Sold", w = 90 },
        { key = "name", label = "Item", w = 200 },
        { key = "n", label = "Qty", w = 40, justify = "RIGHT" },
        { key = "each", label = "Each", w = 100, justify = "RIGHT" },
        { key = "g", label = "Price", w = 110, justify = "RIGHT" },
        { key = "cut", label = "AH cut", w = 90, justify = "RIGHT" },
        { key = "who", label = "Buyer", w = 100 },
        { key = "strategy", label = "Strategy", w = 90 },
    },
    buy = {
        { key = "t", label = "Bought", w = 90 },
        { key = "name", label = "Item", w = 220 },
        { key = "n", label = "Qty", w = 40, justify = "RIGHT" },
        { key = "each", label = "Each", w = 110, justify = "RIGHT" },
        { key = "g", label = "Paid", w = 120, justify = "RIGHT" },
        { key = "who", label = "Seller", w = 110 },
        { key = "strategy", label = "Strategy", w = 110 },
    },
    expired = {
        { key = "t", label = "Returned", w = 90 },
        { key = "name", label = "Item", w = 240 },
        { key = "n", label = "Qty", w = 40, justify = "RIGHT" },
        { key = "k", label = "", w = 80 },
        { key = "dep", label = "Deposit lost", w = 120, justify = "RIGHT", tip = "Known when Mail King saw you post it." },
        { key = "strategy", label = "Strategy", w = 120 },
    },
    items = {
        { key = "name", label = "Item", w = 165 },
        { key = "strategy", label = "Strategy", w = 85 },
        { key = "units", label = "Sold", w = 45, justify = "RIGHT", tip = "Units sold." },
        { key = "each", label = "Avg each", w = 80, justify = "RIGHT", tip = "Average price per unit, before the cut." },
        { key = "income", label = "Income", w = 90, justify = "RIGHT" },
        { key = "spent", label = "Spent", w = 80, justify = "RIGHT" },
        { key = "expired", label = "Expired", w = 55, justify = "RIGHT" },
        { key = "through", label = "Sell-thru", w = 60, justify = "RIGHT", tip = "Of the auctions that ended, how many sold." },
        { key = "market", label = "Market now", w = 80, justify = "RIGHT", tip = "Scanner King's market price today, per unit." },
        { key = "profit", label = "Profit", w = 80, justify = "RIGHT" },
    },
    stock = {
        { key = "name", label = "Item", w = 210 },
        { key = "strategy", label = "Strategy", w = 100 },
        { key = "bags", label = "Bags", w = 55, justify = "RIGHT" },
        { key = "bank", label = "Bank", w = 55, justify = "RIGHT", tip = "Seen when you last opened each character's bank (and the warband bank)." },
        { key = "mail", label = "Mail", w = 55, justify = "RIGHT", tip = "Still attached to mail in your mailbox." },
        { key = "ah", label = "On AH", w = 55, justify = "RIGHT", tip = "Your auctions still up, as of when you last looked at them." },
        { key = "total", label = "Total", w = 60, justify = "RIGHT" },
        { key = "each", label = "Market each", w = 95, justify = "RIGHT", tip = "Scanner King's market price today." },
        { key = "value", label = "Worth", w = 105, justify = "RIGHT" },
    },
}

local function market(id)
    if not (id and ScannerKing and ScannerKing.GetMarketPrice) then return nil end
    return (ScannerKing.GetMarketPrice(id))
end

local function build()
    local s = ns.Summary(since(), onlyChar())
    current = {}
    if tab == "items" then
        for _, r in ipairs(s.items) do
            if (r.sales > 0 or r.bought > 0 or r.expired > 0) and (not strategyFilter or r.strategy == strategyFilter) then
                r.each = r.units > 0 and r.gross / r.units or nil
                r.through = through(r)
                r.market = market(r.item)
                table.insert(current, r)
            end
        end
        table.sort(current, ns.Sorter("items"))
    elseif tab == "stock" then
        local st = ns.Stock(onlyChar())
        for _, r in ipairs(st.items) do
            if not strategyFilter or r.strategy == strategyFilter then
                r.name = r.name or ((C_Item and C_Item.GetItemInfo or GetItemInfo)(r.item))
                table.insert(current, r)
            end
        end
        current.stock = st
        table.sort(current, ns.Sorter("stock"))
    else
        for _, e in ipairs(s.entries) do
            if e.k == tab or (tab == "expired" and e.k == "cancelled") then table.insert(current, e) end
        end
    end
end

function ns.Sorter(page)
    local sort = sorts[page]
    return function(a, b)
        local x, y = a[sort.key], b[sort.key]
        if sort.key == "name" or sort.key == "strategy" then x, y = a[sort.key] or "", b[sort.key] or "" end
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end
            return (a.name or "") < (b.name or "")
        end
        if x == y then return (a.name or "") < (b.name or "") end
        if sort.desc then return x > y end
        return x < y
    end
end

local function cell(e, key)
    if key == "t" then return when(e.t) end
    if key == "name" then return ns.ItemText(e.item, e.name) end
    if key == "strategy" then return (tab == "items" or tab == "stock") and e.strategy or (ns.strategyOf[e] or "") end
    if tab == "stock" then
        if key == "each" or key == "value" then return e[key] and ns.Money(e[key]) or grey("no price") end
        if key == "total" then return tostring(e.total) end
        local v = e[key]
        if v then return v > 0 and tostring(v) or grey("-") end
    end
    if key == "n" then return tostring(e.n or 1) end
    if key == "each" then
        if tab == "items" then return e.each and ns.Money(e.each) or grey("-") end
        return e.g and ns.Money(e.g / math.max(e.n or 1, 1)) or grey("-")
    end
    if key == "g" or key == "income" or key == "spent" or key == "profit" or key == "market" then
        local v = e[key]
        if (key == "income" or key == "spent") and v == 0 then return grey("-") end
        return v and ns.Money(v) or grey("-")
    end
    if key == "cut" then return e.cut and ns.Money(e.cut) or grey("-") end
    if key == "dep" then return e.dep and ns.Money(e.dep) or grey("unknown") end
    if key == "who" then return e.who or grey("-") end
    if key == "k" then return e.k == "cancelled" and "cancelled" or "expired" end
    if key == "units" then return e.units > 0 and tostring(e.units) or grey("-") end
    if key == "expired" then return e.expired > 0 and tostring(e.expired) or grey("-") end
    if key == "through" then return pct(e.through) end
    return ""
end

local function refreshList()
    build()
    local cols = LIST_COLS[tab]
    listTable.layout(cols)
    offset = math.max(0, math.min(offset, #current - ROWS))
    for i, r in ipairs(listTable.rows) do
        local e = current[i + offset]
        if e then
            r.item, r.name, r.chars = e.item, e.name, e.chars
            for c, col in ipairs(cols) do r.cells[c]:SetText(cell(e, col.key)) end
            r:Show()
        else
            r.item, r.name, r.chars = nil, nil, nil
            r:Hide()
        end
    end
    local sort = sorts[tab]
    if sort then
        for i, col in ipairs(cols) do
            listTable.headers[i]:SetText(col.label .. (sort.key == col.key and (sort.desc and " v" or " ^") or ""))
        end
    end
    local what = tab == "sale" and "sales" or tab == "buy" and "purchases" or tab == "expired" and "expired or cancelled auctions" or tab == "stock" and "items in stock" or "items"
    listView.empty:SetText(#current == 0 and ("No " .. what .. " in this period.") or "")
    footer:SetText((#current > 0 and ((offset + 1) .. "-" .. (offset + math.min(#current, ROWS)) .. " of " .. #current .. " " .. what .. ".  ") or "")
        .. (strategyFilter and (tab == "items" or tab == "stock") and ("Strategy: " .. strategyFilter .. " (click the tab again for all).  ") or "")
        .. (tab == "stock" and current.stock and ("Worth " .. ns.Money(current.stock.value) .. ".  "
            .. (ns.StockSeen().bank and "" or "Open your bank once to add it.  ")) or "")
        .. "Right-click an item to choose its strategy.")
end

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    for _, b in ipairs(tabButtons) do if b.key == tab then b:LockHighlight() else b:UnlockHighlight() end end
    for _, b in ipairs(periodButtons) do if b.days == ns.db.ui.period then b:LockHighlight() else b:UnlockHighlight() end end
    charBtn:SetText(ns.db.ui.mine and "This character" or "All characters")
    summaryView:SetShown(tab == "summary")
    listView:SetShown(tab ~= "summary")
    if tab == "summary" then refreshSummary() else refreshList() end
end

function ns.SelectTab(key, strategy)
    if key == tab and sorts[key] and not strategy then strategyFilter = nil end
    if key ~= tab and not strategy then strategyFilter = nil end
    if strategy then strategyFilter = strategy end
    tab, offset = key, 0
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function rowScripts(r)
    r:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) end
        if self.chars then
            local list = {}
            for who, n in pairs(self.chars) do table.insert(list, { who, n }) end
            table.sort(list, function(a, b) return a[2] > b[2] end)
            GameTooltip:AddLine(" ")
            for _, c in ipairs(list) do GameTooltip:AddDoubleLine(c[1], c[2], 1, 1, 1, 1, 1, 1) end
        end
        GameTooltip:AddLine("Right-click: choose its strategy.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, which)
        if which == "RightButton" then ns.StrategyMenu(self, self.item, self.name) end
    end)
end

local function create()
    frame = CreateFrame("Frame", "MailKingFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "MailKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Mail King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    tabButtons = {}
    local prev = title
    for _, t in ipairs(TABS) do
        local b = button(frame, t[2], 84, function() ns.SelectTab(t[1]) end)
        b.key = t[1]
        b:SetPoint("LEFT", prev, "RIGHT", prev == title and 16 or 2, 0)
        table.insert(tabButtons, b)
        prev = b
    end

    periodButtons = {}
    local x = -36
    for i = #PERIODS, 1, -1 do
        local p = PERIODS[i]
        local b = button(frame, p[2], 64, function() ns.db.ui.period = p[1]; offset = 0; ns.Refresh() end)
        b.days = p[1]
        b:SetPoint("TOPRIGHT", x, -40)
        x = x - 66
        table.insert(periodButtons, b)
    end
    charBtn = button(frame, "All characters", 110, function() ns.db.ui.mine = not ns.db.ui.mine; ns.Refresh() end)
    charBtn:SetPoint("TOPLEFT", 16, -40)
    charBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Whose mail")
        GameTooltip:AddLine("Every character's auction mail, or only this character's. Click to switch.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    charBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Summary
    summaryView = CreateFrame("Frame", nil, frame)
    summaryView:SetPoint("TOPLEFT", 16, -72)
    summaryView:SetPoint("BOTTOMRIGHT", -16, 36)
    tiles = {}
    for i, t in ipairs({ { "profit", "Profit" }, { "income", "Income" }, { "cut", "AH cut" }, { "spent", "Spent" },
                         { "lost", "Deposits lost" }, { "sales", "Sales" } }) do
        local tx = (i - 1) * 136
        local label = summaryView:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", tx, 0)
        label:SetText(t[2])
        local v = summaryView:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormalLarge" or "GameFontHighlight")
        v:SetPoint("TOPLEFT", tx, -14)
        tiles[t[1]] = v
    end
    local goldHolder = CreateFrame("Frame", nil, summaryView)
    goldHolder:SetPoint("TOPLEFT", 0, -40)
    goldHolder:SetSize(400, 16)
    goldText = goldHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldText:SetPoint("LEFT")
    goldHolder:EnableMouse(true)
    goldHolder:SetScript("OnEnter", function(self)
        local total, list = ns.Gold()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddDoubleLine("Gold on your characters", ns.Money(total))
        for _, g in ipairs(list) do GameTooltip:AddDoubleLine(g.who, ns.Money(g.m), 1, 1, 1, 1, 1, 1) end
        GameTooltip:Show()
    end)
    goldHolder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local barsLabel = summaryView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barsLabel:SetPoint("TOPLEFT", 0, -64)
    barsLabel:SetText("Profit per day, last " .. DAYS .. " days")
    bars = {}
    for i = 1, DAYS do
        local b = CreateFrame("Frame", nil, summaryView)
        b:SetSize(36, 124)
        b:SetPoint("TOPLEFT", (i - 1) * 40, -80)
        local axis = b:CreateTexture(nil, "BACKGROUND")
        axis:SetColorTexture(1, 1, 1, 0.15)
        axis:SetHeight(1)
        axis:SetPoint("LEFT", b, "LEFT")
        axis:SetPoint("RIGHT", b, "RIGHT")
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetWidth(28)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.day then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.day.day)
            GameTooltip:AddDoubleLine("Income", ns.Money(self.day.income), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Profit", ns.Money(self.day.profit), 1, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bars[i] = b
    end

    local stratHolder = CreateFrame("Frame", nil, summaryView)
    stratHolder:SetPoint("TOPLEFT", 0, -214)
    stratHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    stratTable = makeTable(stratHolder, 13)
    stratTable.layout(STRAT_COLS)
    for _, r in ipairs(stratTable.rows) do
        r:SetScript("OnClick", function(self) if self.strategy then ns.SelectTab("items", self.strategy) end end)
        r:SetScript("OnEnter", function(self)
            if not self.strategy then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.strategy)
            GameTooltip:AddLine("Click: its items.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    summaryView.empty = summaryView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    summaryView.empty:SetPoint("TOP", stratHolder, "TOP", 0, -40)
    summaryView.empty:SetWidth(600)

    -- Lists
    listView = CreateFrame("Frame", nil, frame)
    listView:SetPoint("TOPLEFT", 16, -72)
    listView:SetPoint("BOTTOMRIGHT", -16, 36)
    listTable = makeTable(listView, ROWS, function(key)
        local sort = sorts[tab]
        if not sort then return end
        if sort.key == key then sort.desc = not sort.desc else sort.key, sort.desc = key, key ~= "name" and key ~= "strategy" end
        offset = 0
        ns.Refresh()
    end)
    for _, r in ipairs(listTable.rows) do rowScripts(r) end
    listView.empty = listView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    listView.empty:SetPoint("TOP", 0, -60)
    listView:EnableMouseWheel(true)
    listView:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 5)
        ns.Refresh()
    end)

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 16)
    footer:SetJustifyH("LEFT")
    local export = button(frame, "Export", 70, function() ns.Export() end)
    export:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:SetScript("OnShow", ns.Refresh)
    frame:Hide()
end

function ns.Toggle(show)
    if not ns.db then return end
    if not frame then create() end
    if show == nil then show = not frame:IsShown() end
    frame:SetShown(show)
    if show then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Export: the ledger as comma-separated text, for a spreadsheet
---------------------------------------------------------------------------

local exportFrame, exportBox

function ns.ExportText()
    local s = ns.Summary(0)
    local lines = { "date,kind,item,quantity,price,ah_cut,deposit,buyer_or_seller,character,strategy" }
    local function q(v) v = tostring(v or ""); return v:find("[,\"]") and ('"' .. v:gsub('"', '""') .. '"') or v end
    for i = #s.entries, 1, -1 do -- oldest first
        local e = s.entries[i]
        table.insert(lines, table.concat({ date and date("%Y-%m-%d %H:%M", e.t) or e.t, e.k, q(e.name), e.n or 1,
            e.g or "", e.cut or "", e.dep or "", q(e.who), q(e.c), q(ns.strategyOf[e]) }, ","))
    end
    return table.concat(lines, "\n"), #s.entries
end

function ns.Export()
    if not ns.db then return end
    local text, n = ns.ExportText()
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "MailKingExport", UIParent, "BackdropTemplate")
        exportFrame:SetSize(560, 360)
        exportFrame:SetPoint("CENTER")
        exportFrame:SetFrameStrata("DIALOG")
        exportFrame:EnableMouse(true)
        if exportFrame.SetBackdrop then
            exportFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        if UISpecialFrames then table.insert(UISpecialFrames, "MailKingExport") end
        local t = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 16, -14)
        t:SetText("Mail King export: press Ctrl+A, then Ctrl+C, and paste into a spreadsheet")
        local close = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -40)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        exportBox = CreateFrame("EditBox", nil, scroll)
        exportBox:SetMultiLine(true)
        exportBox:SetFontObject("ChatFontSmall")
        exportBox:SetWidth(500)
        exportBox:SetAutoFocus(false)
        exportBox:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
        scroll:SetScrollChild(exportBox)
    end
    exportBox:SetText(text)
    exportBox.text = text
    exportFrame:Show()
    if exportBox.HighlightText then exportBox:HighlightText(); exportBox:SetFocus() end
    ns.Print("Exported " .. n .. " ledger lines.")
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db or not Minimap then return end
    if not mini then
        mini = CreateFrame("Button", "MailKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Letter_15")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function() ns.Toggle() end)
        mini:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                ns.db.ui.buttonAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
                place()
            end)
        end)
        mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        mini:SetScript("OnEnter", function(self)
            local week = ns.Summary(ns.Now() - 7 * 86400)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Mail King")
            GameTooltip:AddDoubleLine("Profit, last 7 days", ns.Money(week.profit), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gold on your characters", ns.Money((ns.Gold())), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Stock worth", ns.Money(ns.Stock().value), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddLine("Click: open. Drag: move this button.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(ns.db.ui.button)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if ns.db then ns.UpdateMinimapButton() end
end)
