local _, ns = ...

-- The Mail King window.
--   Top:     the tabs (Summary, Sales, Purchases, Expired, Items, Not selling, Buyers),
--            the period (Today, 7 days, 30 days, All) and whose mail (all characters or this one).
--   Summary: profit, income, the auction house cut, spent, deposits lost; your best
--            buyer and (with Inventory King) your net worth; profit per day for the
--            last two weeks; and every strategy, best first. Click a strategy for its items.
--   Lists:   every sale, purchase and expired auction, newest first.
--   Items:   every item you've traded: sold, average price, sell-through and
--            today's market price from Scanner King. Click a column to sort.
--   Not selling: what came back unsold, worst first, and why it might be.
--   Buyers:  who buys from you (or who you buy from): how often, how much, what.
--            Click one for their sales.
-- Right-click any item to choose its strategy (or make a new one).

local WIDTH, HEIGHT = 860, 560
local ROWS, ROW_H = 20, 18
local MAX_COLS = 11
local DAYS = 14
local PERIODS = { { 1, "Today" }, { 7, "7 days" }, { 30, "30 days" }, { 0, "All" } }
local TABS = { { "summary", "Summary" }, { "sale", "Sales" }, { "buy", "Purchases" }, { "expired", "Expired" }, { "items", "Items" },
    { "unsold", "Not selling" }, { "buyers", "Buyers" } }

local frame, tabButtons, periodButtons, charBtn, sideBtn, footer
local summaryView, tiles, goldText, bars, stratTable
local listView, listTable
local tab, offset, strategyFilter, whoFilter = "summary", 0, nil, nil
local sellers = false -- the Buyers page shows who you bought from instead
local sorts = { items = { key = "profit", desc = true }, unsold = { key = "lost", desc = true },
    buyers = { key = "mails", desc = true } } -- by column, per page
local buyerCount = {} -- buyer -> sale mails, all time, for the Sales tooltips
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
    local bits = {}
    local b = ns.Buyers(since(), onlyChar()).rows[1]
    if b then
        table.insert(bits, "Best buyer: " .. b.who .. ", " .. b.mails .. " sale" .. (b.mails == 1 and "" or "s")
            .. string.format(" (%.0f%%)", b.share * 100) .. " for " .. ns.Money(b.gold))
    end
    local w = InventoryKing and InventoryKing.NetWorth and InventoryKing.NetWorth()
    if w then table.insert(bits, "Net worth: " .. ns.Money(w.total)) end
    goldText:SetText(table.concat(bits, "     "))

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
    unsold = {
        { key = "name", label = "Item", w = 160 },
        { key = "strategy", label = "Strategy", w = 80 },
        { key = "units", label = "Sold", w = 42, justify = "RIGHT", tip = "Units sold." },
        { key = "expired", label = "Expired", w = 50, justify = "RIGHT", tip = "Auctions that came back, expired or cancelled." },
        { key = "through", label = "Sell-thru", w = 58, justify = "RIGHT", tip = "Of the auctions that ended, how many sold." },
        { key = "lost", label = "Deposits lost", w = 85, justify = "RIGHT" },
        { key = "listEach", label = "You asked", w = 80, justify = "RIGHT", tip = "Your average price each on the auctions that came back. Known for auctions posted while Mail King was running." },
        { key = "market", label = "Market now", w = 80, justify = "RIGHT", tip = "Scanner King's market price today, per unit." },
        { key = "lastSale", label = "Last sold", w = 70, justify = "RIGHT" },
        { key = "why", label = "Why", w = 115, tip = "Over market: you asked 10% or more over today's market price. Never sold: none sold in this period. Slow: under half sold." },
    },
    buyers = {
        { key = "who", label = "Buyer", w = 130 },
        { key = "mails", label = "Sales", w = 50, justify = "RIGHT", tip = "How many of your auctions they bought (one mail each)." },
        { key = "units", label = "Units", w = 50, justify = "RIGHT" },
        { key = "gold", label = "Paid you", w = 105, justify = "RIGHT", tip = "What they paid, before the auction house cut." },
        { key = "each", label = "Avg sale", w = 90, justify = "RIGHT" },
        { key = "share", label = "Share", w = 55, justify = "RIGHT", tip = "Of your sales in this period." },
        { key = "kinds", label = "Items", w = 45, justify = "RIGHT", tip = "How many different items." },
        { key = "name", label = "Favourite", w = 175, tip = "What they've spent the most on." },
        { key = "last", label = "Last", w = 90 },
    },
}

local market = ns.Market
local WHY = { over = "|cffff6060over market|r", never = "|cffff6060never sold|r", slow = "|cffffd100slow|r" }

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
    elseif tab == "unsold" then
        for _, r in ipairs(ns.NotSelling(since(), onlyChar())) do
            if not strategyFilter or r.strategy == strategyFilter then table.insert(current, r) end
        end
        table.sort(current, ns.Sorter("unsold"))
    elseif tab == "buyers" then
        local b = ns.Buyers(since(), onlyChar(), sellers and "buy" or "sale")
        for _, r in ipairs(b.rows) do table.insert(current, r) end
        current.unknown = b.unknown
        table.sort(current, ns.Sorter("buyers"))
    else
        for _, e in ipairs(s.entries) do
            if (e.k == tab or (tab == "expired" and e.k == "cancelled")) and (not whoFilter or e.who == whoFilter) then
                table.insert(current, e)
            end
        end
        if tab == "sale" then
            wipe(buyerCount)
            for _, e in ipairs(ns.db.entries) do
                if e.k == "sale" and e.who then buyerCount[e.who] = (buyerCount[e.who] or 0) + 1 end
            end
        end
    end
end

function ns.Sorter(page)
    local sort = sorts[page]
    return function(a, b)
        local x, y = a[sort.key], b[sort.key]
        if sort.key == "name" or sort.key == "strategy" or sort.key == "who" or sort.key == "why" then x, y = a[sort.key] or "", b[sort.key] or "" end
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
    if key == "strategy" then return (tab == "items" or tab == "unsold") and e.strategy or (ns.strategyOf[e] or "") end
    if tab == "buyers" then
        if key == "who" then return e.regular and ("|cffffd100" .. e.who .. "|r") or e.who end
        if key == "gold" or key == "each" then return ns.Money(e[key]) end
        if key == "share" then return pct(e.share) end
        if key == "name" then return e.fav and (ns.ItemText(e.fav.item, e.fav.name) .. grey(" x" .. e.fav.units)) or grey("-") end
        if key == "last" then return when(e.last) end
        return tostring(e[key] or 0)
    end
    if tab == "unsold" then
        if key == "listEach" then
            if not e.listEach then return grey("unknown") end
            local over = e.vsMarket and e.vsMarket >= 0.1
            return (over and "|cffff6060" or "") .. ns.Money(e.listEach) .. (over and "|r" or "")
        end
        if key == "lastSale" then return e.lastSale and date and date("%m-%d", e.lastSale) or grey("never") end
        if key == "lost" then return e.lost > 0 and ns.Money(e.lost) or grey("-") end
        if key == "why" then
            if e.why == "over" and e.vsMarket then return WHY.over .. string.format(" +%.0f%%", e.vsMarket * 100) end
            return WHY[e.why] or ""
        end
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
            r.item, r.name, r.buyer, r.entry = e.item, e.name, tab == "buyers" and e or nil, e
            if tab == "buyers" then r.item, r.name = nil, nil end
            for c, col in ipairs(cols) do r.cells[c]:SetText(cell(e, col.key)) end
            r:Show()
        else
            r.item, r.name, r.buyer, r.entry = nil, nil, nil, nil
            r:Hide()
        end
    end
    local sort = sorts[tab]
    if sort then
        for i, col in ipairs(cols) do
            listTable.headers[i]:SetText(col.label .. (sort.key == col.key and (sort.desc and " v" or " ^") or ""))
        end
    end
    local what = tab == "sale" and "sales" or tab == "buy" and "purchases" or tab == "expired" and "expired or cancelled auctions"
        or tab == "unsold" and "items that came back unsold" or tab == "buyers" and (sellers and "sellers" or "buyers") or "items"
    listView.empty:SetText(#current == 0 and ("No " .. what .. " in this period.") or "")
    local hint
    if tab == "buyers" then
        hint = "Gold: " .. ns.REGULAR .. "+ " .. (sellers and "purchases" or "sales") .. ". Click one for their "
            .. (sellers and "purchases." or "sales.")
            .. ((current.unknown or 0) > 0 and ("  " .. current.unknown .. " with no name on the mail.") or "")
    else
        hint = "Right-click an item to choose its strategy."
    end
    footer:SetText((#current > 0 and ((offset + 1) .. "-" .. (offset + math.min(#current, ROWS)) .. " of " .. #current .. " " .. what .. ".  ") or "")
        .. (strategyFilter and (tab == "items" or tab == "unsold") and ("Strategy: " .. strategyFilter .. " (click the tab again for all).  ") or "")
        .. (whoFilter and (tab == "sale" or tab == "buy") and ((tab == "sale" and "Buyer: " or "Seller: ") .. whoFilter .. " (click the tab again for all).  ") or "")
        .. hint)
end

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    for _, b in ipairs(tabButtons) do if b.key == tab then b:LockHighlight() else b:UnlockHighlight() end end
    for _, b in ipairs(periodButtons) do if b.days == ns.db.ui.period then b:LockHighlight() else b:UnlockHighlight() end end
    charBtn:SetText(ns.db.ui.mine and "This character" or "All characters")
    sideBtn:SetShown(tab == "buyers")
    sideBtn:SetText(sellers and "Sellers" or "Buyers")
    summaryView:SetShown(tab == "summary")
    listView:SetShown(tab ~= "summary")
    if tab == "summary" then refreshSummary() else refreshList() end
end

-- strategy: only that strategy's items (Items, Not selling). who: only that buyer or seller (Sales, Purchases).
function ns.SelectTab(key, strategy, who)
    if key == tab and not strategy and not who then strategyFilter, whoFilter = nil, nil end
    if key ~= tab and not strategy then strategyFilter = nil end
    if key ~= tab and not who then whoFilter = nil end
    if strategy then strategyFilter = strategy end
    if who then whoFilter = who end
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

-- A buyer (or seller): what they bought, best first.
local function buyerTip(b)
    GameTooltip:AddLine(b.who .. (b.regular and "  |cffffd100regular|r" or ""))
    GameTooltip:AddDoubleLine(b.mails .. (sellers and " purchases, " or " sales, ") .. b.units .. " units", ns.Money(b.gold), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("First / last", when(b.first) .. "  /  " .. when(b.last), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    for i, it in ipairs(ns.BuyerItems(b)) do
        if i > 10 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6); break end
        GameTooltip:AddDoubleLine(ns.ItemText(it.item, it.name) .. "  x" .. it.units .. "  (" .. it.mails .. ")", ns.Money(it.gold), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(sellers and "Click: their purchases." or "Click: their sales.", 0.6, 0.6, 0.6)
end

-- Why an item isn't selling, in words.
local function unsoldTip(e)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Sold / came back", e.sales .. " / " .. e.expired, 1, 1, 1, 1, 1, 1)
    if e.soldEach then GameTooltip:AddDoubleLine("Sold for, each", ns.Money(e.soldEach), 1, 1, 1, 1, 1, 1) end
    if e.listEach then GameTooltip:AddDoubleLine("You asked, each", ns.Money(e.listEach), 1, 1, 1, 1, 1, 1) end
    if e.market then GameTooltip:AddDoubleLine("Market now", ns.Money(e.market), 1, 1, 1, 1, 1, 1) end
    if e.held then GameTooltip:AddDoubleLine("You still have", tostring(e.held), 1, 1, 1, 1, 1, 1) end
    if e.why == "over" then
        GameTooltip:AddLine(string.format("You're asking %.0f%% over the market: try nearer %s.", e.vsMarket * 100, ns.Money(e.market)), 1, 0.4, 0.4, true)
    elseif e.why == "never" then
        GameTooltip:AddLine("None sold in this period. Check the price, or whether anyone's buying.", 1, 0.4, 0.4, true)
    elseif e.why == "slow" then
        GameTooltip:AddLine("Under half of these sell. A little cheaper, or fewer at once, may help.", 1, 0.82, 0, true)
    end
end

local function rowScripts(r)
    r:SetScript("OnEnter", function(self)
        if self.buyer then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            buyerTip(self.buyer)
            GameTooltip:Show()
            return
        end
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) end
        local e = self.entry
        if tab == "unsold" and e then unsoldTip(e) end
        if tab == "sale" and e and e.who and buyerCount[e.who] then
            local n = buyerCount[e.who]
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(e.who .. " has bought from you " .. n .. " time" .. (n == 1 and "" or "s") .. ".", 1, 0.82, 0)
        end
        GameTooltip:AddLine("Right-click: choose its strategy.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, which)
        if self.buyer then
            ns.SelectTab(sellers and "buy" or "sale", nil, self.buyer.who)
        elseif which == "RightButton" then
            ns.StrategyMenu(self, self.item, self.name)
        end
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
    sideBtn = button(frame, "Buyers", 90, function() sellers = not sellers; offset = 0; ns.Refresh() end)
    sideBtn:SetPoint("LEFT", charBtn, "RIGHT", 4, 0)
    sideBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Buyers or sellers")
        GameTooltip:AddLine("The people who buy from you, or the people you buy from. Click to switch.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sideBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    goldHolder:SetSize(700, 16)
    goldText = goldHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldText:SetPoint("LEFT")
    goldHolder:EnableMouse(true)
    goldHolder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local top = ns.Buyers(since(), onlyChar()).rows
        GameTooltip:AddLine("Your best buyers")
        for i = 1, math.min(5, #top) do
            GameTooltip:AddDoubleLine(top[i].who .. "  (" .. top[i].mails .. ")", ns.Money(top[i].gold), 1, 1, 1, 1, 1, 1)
        end
        if #top == 0 then GameTooltip:AddLine("No sales in this period.", 0.6, 0.6, 0.6) end
        local w = InventoryKing and InventoryKing.NetWorth and InventoryKing.NetWorth()
        if w then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Net worth (Inventory King)", ns.Money(w.total))
            GameTooltip:AddDoubleLine("Gold", ns.Money(w.gold + w.mail), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Items", ns.Money(w.assets), 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Install Inventory King for your gold, items and net worth.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    goldHolder:SetScript("OnMouseUp", function() ns.SelectTab("buyers") end)
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
        if sort.key == key then sort.desc = not sort.desc else sort.key, sort.desc = key, key ~= "name" and key ~= "strategy" and key ~= "who" and key ~= "why" end
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
            local w = InventoryKing and InventoryKing.NetWorth and InventoryKing.NetWorth()
            if w then GameTooltip:AddDoubleLine("Net worth", ns.Money(w.total), 1, 1, 1, 1, 1, 1) end
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
