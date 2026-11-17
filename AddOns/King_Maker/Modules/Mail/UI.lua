local _, KM = ...
local ns = KM.Module("Mail")
local UI = KM.UI
local C = UI.C

-- The Sales Ledger page of the King Maker window (Auction House > Sales Ledger).
--   Top:     the tabs (Summary, Sales, Purchases, Expired, Items, Not selling, Buyers) and Export; under them
--            whose mail (all characters or this one), Buyers/Sellers (on Buyers) and the period
--            (Today, 7 days, 30 days, All).
--   Summary: profit, income, the auction house cut, spent, deposits lost, sales; your best buyer and (with the
--            Inventory module) your net worth; profit per day for the last two weeks; and every strategy, best
--            first. Click a strategy for its items.
--   Lists:   every sale, purchase and expired auction, newest first; every item you've traded; what isn't
--            selling and why; who buys from you (or who you buy from). Click a column to sort.
-- Right-click any item to choose its strategy (or make a new one).
-- Also here: the crown's quick action and tooltip line, the Home tile and the Settings section.

local DAYS = 14
local TILE_W, TILE_H = 119, 58
local CHART_H, HALF = 112, 34
local PERIODS = { { 1, "Today" }, { 7, "7 days" }, { 30, "30 days" }, { 0, "All" } }
local TABS = { { id = "summary", label = "Summary" }, { id = "sale", label = "Sales" }, { id = "buy", label = "Purchases" },
    { id = "expired", label = "Expired" }, { id = "items", label = "Items" }, { id = "unsold", label = "Not selling" },
    { id = "buyers", label = "Buyers" } }
local DEFAULT_SORT = { sale = { "t", true }, buy = { "t", true }, expired = { "t", true }, items = { "profit", true },
    unsold = { "lost", true }, buyers = { "mails", true } }

local page, tabs, periodButtons, charBtn, sideBtn, footer
local summaryView, tiles, goldText, bars, stratTable
local listView, tables = nil, {}
local tab, strategyFilter, whoFilter = "summary", nil, nil
local sellers = false -- the Buyers page shows who you bought from instead
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

StaticPopupDialogs.MAILKING_RESET = {
    text = "Clear the whole Sales Ledger? Every sale, purchase and expired auction goes. Your strategies stay.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() ns.Reset() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.StrategyMenu(owner, item, name)
    if not (item or name) then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        KM.Print(ns, "Right-click menus need a newer client.")
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
-- Summary
---------------------------------------------------------------------------

local function through(r)
    local ended = r.sales + r.expired
    return ended > 0 and r.sales / ended or nil
end

local function refreshSummary()
    local s = ns.Summary(since(), onlyChar())
    local bw = ns.BoughtWorth(since(), onlyChar())
    local function tone(v) return v < 0 and C.bad or (v > 0 and C.good or C.text) end
    local net = s.profit + bw.worth
    local diff = bw.worth - bw.held
    tiles.net:Set("Net if sold now", ns.Money(net), "cash + what you still hold", tone(net))
    tiles.profit:Set("Net cash", ns.Money(s.profit), "sales - purchases - deposits", tone(s.profit))
    tiles.income:Set("Income", ns.Money(s.income), "after " .. ns.Money(s.cut) .. " AH cut")
    tiles.spent:Set("Spent", ns.Money(s.spent), s.lost > 0 and (ns.Money(s.lost) .. " deposits lost") or "on the AH")
    tiles.held:Set("Still holding", ns.Money(bw.worth), bw.held > 0 and ((diff >= 0 and "+" or "-") .. ns.Money(math.abs(diff)) .. " vs paid") or "nothing bought held",
        bw.held > 0 and tone(diff) or C.text)
    tiles.sales:Set("Sales", tostring(s.sales), s.expired > 0 and (s.expired .. " expired") or nil)
    local bits = {}
    local b = ns.Buyers(since(), onlyChar()).rows[1]
    if b then
        table.insert(bits, "Best buyer: " .. b.who .. ", " .. b.mails .. " sale" .. (b.mails == 1 and "" or "s")
            .. string.format(" (%.0f%%)", b.share * 100) .. " for " .. ns.Money(b.gold))
    end
    local w = InventoryKing and InventoryKing.NetWorth and InventoryKing.NetWorth()
    if w then table.insert(bits, "Net worth: " .. ns.Money(w.total)) end
    goldText:SetText(#bits > 0 and table.concat(bits, "     ") or grey("No sales in this period yet."))
    -- Realized P&L for the period, from the Profit & Loss module (click: that page)
    local pnl = ProfitKing and ProfitKing.Summary and KM.Safe(ProfitKing.Summary, since(), onlyChar())
    if pnl and ns.pnlBtn then
        local v = math.floor((pnl.realized or 0) + 0.5)
        local c = v > 0 and C.good or (v < 0 and C.bad or C.muted)
        ns.pnlBtn:SetLabel("Realized P&L, period: " .. UI.Hex(c) .. (v > 0 and "+" or (v < 0 and "-" or "")) .. KM.MoneyShort(math.abs(v), true) .. "|r")
        ns.pnlBtn.summary = pnl
        ns.pnlBtn:Show()
    elseif ns.pnlBtn then
        ns.pnlBtn:Hide()
    end
    -- the best-buyer line stops short of the P&L button
    goldText:ClearAllPoints()
    goldText:SetPoint("LEFT", goldText:GetParent(), "LEFT", 2, 0)
    if ns.pnlBtn and ns.pnlBtn:IsShown() then goldText:SetPoint("RIGHT", ns.pnlBtn, "LEFT", -8, 0) end

    -- Profit per day: green up from the middle line, red down.
    local days = ns.Daily(DAYS, onlyChar())
    local top = 1
    for _, d in ipairs(days) do top = math.max(top, math.abs(d.profit)) end
    for i, d in ipairs(days) do
        local bar = bars[i]
        bar.day = d
        bar.fill:SetHeight(math.max(1, math.abs(d.profit) / top * HALF))
        bar.fill:ClearAllPoints()
        if d.profit >= 0 then
            bar.fill:SetPoint("BOTTOM", bar, "CENTER", 0, 0)
            UI.SetColor(bar.fill, { C.good[1], C.good[2], C.good[3], d.profit ~= 0 and 0.9 or 0.25 })
        else
            bar.fill:SetPoint("TOP", bar, "CENTER", 0, 0)
            UI.SetColor(bar.fill, { C.bad[1], C.bad[2], C.bad[3], 0.9 })
        end
        if bar.dateFS then bar.dateFS:SetText(d.day) end
    end

    stratTable.emptyText = "Nothing in the ledger for this period yet. Open your mailbox: every auction house mail is recorded, sales dated when they sold."
    stratTable:SetRows(s.strategies)
    footer:SetText(#ns.db.entries .. " mails recorded.  Click a strategy for its items; right-click an item in any list to choose its strategy.")
end

local function fillStrategy(r, e, cells)
    cells.key:SetText(e.key)
    cells.sales:SetText(e.sales > 0 and tostring(e.sales) or grey("-"))
    cells.income:SetText(e.income ~= 0 and ns.Money(e.income) or grey("-"))
    cells.spent:SetText(e.spent ~= 0 and ns.Money(e.spent) or grey("-"))
    cells.lost:SetText(e.lost ~= 0 and ns.Money(e.lost) or grey("-"))
    cells.profit:SetText(ns.Money(e.profit))
    cells.through:SetText(pct(through(e)))
    r.tip = function(tt) tt:AddLine(e.key); tt:AddLine("Click: its items.", 0.6, 0.6, 0.6) end
end

---------------------------------------------------------------------------
-- Lists and items
---------------------------------------------------------------------------

local function col(key, label, w, justify, tip)
    local text = key == "name" or key == "strategy" or key == "who" or key == "why" or key == "k"
    return { key = key, label = label, w = w, justify = justify, tip = tip, desc = not text }
end
local R = "RIGHT"

local LIST_COLS = {
    sale = {
        col("t", "Sold", 80), col("name", "Item", 150), col("n", "Qty", 36, R), col("each", "Each", 80, R),
        col("g", "Price", 86, R), col("cut", "AH cut", 64, R), col("who", "Buyer", 90),
        col("pl", "P&L", 80, R, "What this sale made (Profit & Loss): what it brought after the cut, minus what those units cost you. \"no cost\": no purchase or loot covered it. \"-\": older than Profit & Loss's detail, or the module is off."),
        col("strategy", "Strategy", 0),
    },
    buy = {
        col("t", "Bought", 84), col("name", "Item", 196), col("n", "Qty", 36, R), col("each", "Each", 96, R),
        col("g", "Paid", 100, R), col("who", "Seller", 110), col("strategy", "Strategy", 0),
    },
    expired = {
        col("t", "Returned", 84), col("name", "Item", 220), col("n", "Qty", 36, R), col("k", "", 76),
        col("dep", "Deposit lost", 110, R, "Known when the Sales Ledger saw you post it."), col("strategy", "Strategy", 0),
    },
    items = {
        col("name", "Item", 140), col("strategy", "Strategy", 76), col("units", "Sold", 38, R, "Units sold."),
        col("each", "Avg each", 78, R, "Average price per unit, before the cut."), col("income", "Income", 82, R),
        col("spent", "Spent", 74, R), col("expired", "Expired", 46, R),
        col("through", "Sell-thru", 52, R, "Of the auctions that ended, how many sold."),
        col("market", "Market now", 78, R, "The Scanner module's market price today, per unit."),
        col("profit", "Profit", 0, R, "Income minus what you spent on it and deposits lost, in this period."),
    },
    unsold = {
        col("name", "Item", 140), col("strategy", "Strategy", 72), col("units", "Sold", 38, R, "Units sold."),
        col("expired", "Expired", 46, R, "Auctions that came back, expired or cancelled."),
        col("through", "Sell-thru", 52, R, "Of the auctions that ended, how many sold."), col("lost", "Deposits lost", 80, R),
        col("listEach", "You asked", 80, R, "Your average price each on the auctions that came back. Known for auctions posted while the Sales Ledger was running."),
        col("market", "Market now", 78, R, "The Scanner module's market price today, per unit."), col("lastSale", "Last sold", 58, R),
        col("why", "Why", 0, nil, "Over market: you asked 10% or more over today's market price. Never sold: none sold in this period. Slow: under half sold."),
    },
    buyers = {
        col("who", "Buyer", 110, nil, "Gold name: a regular, " .. ns.REGULAR .. " or more in this period."), col("mails", "Sales", 44, R, "How many of your auctions they bought (one mail each)."),
        col("units", "Units", 46, R), col("gold", "Paid you", 92, R, "What they paid, before the auction house cut."),
        col("each", "Avg sale", 84, R, "What they paid per auction, before the cut."), col("share", "Share", 48, R, "Of your sales in this period."),
        col("kinds", "Items", 42, R, "How many different items."), col("name", "Favourite", 170, nil, "What they've spent the most on."),
        col("last", "Last", 0),
    },
}
local ICONS = { sale = true, buy = true, expired = true }

local market = ns.Market
local WHY = { over = "|cffff6060over market|r", never = "|cffff6060never sold|r", slow = "|cffffd100slow|r" }
local isEntries = { sale = true, buy = true, expired = true }

-- What a column sorts by on a page.
local function sortValue(page2, e, key)
    if isEntries[page2] then
        if key == "each" then return e.g and e.g / math.max(e.n or 1, 1) or nil end
        if key == "strategy" then return ns.strategyOf[e] or "" end
        if key == "n" then return e.n or 1 end
        if key == "pl" then local x = ns.SalePL(e); return x and x.pl end
    end
    if key == "name" or key == "strategy" or key == "who" or key == "why" or key == "k" then return e[key] or "" end
    return e[key]
end

function ns.Sorter(page2)
    local t, d = tables[page2], DEFAULT_SORT[page2]
    local key, desc = (t and t.sortKey) or d[1], t and t.sortKey and t.sortDesc
    if desc == nil then desc = d[2] end
    return function(a, b)
        local x, y = sortValue(page2, a, key), sortValue(page2, b, key)
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end
            return (a.name or "") < (b.name or "")
        end
        if x == y then
            if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
            return (a.name or "") < (b.name or "")
        end
        if desc then return x > y end
        return x < y
    end
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
    elseif tab == "unsold" then
        for _, r in ipairs(ns.NotSelling(since(), onlyChar())) do
            if not strategyFilter or r.strategy == strategyFilter then table.insert(current, r) end
        end
    elseif tab == "buyers" then
        local b = ns.Buyers(since(), onlyChar(), sellers and "buy" or "sale")
        for _, r in ipairs(b.rows) do table.insert(current, r) end
        current.unknown = b.unknown
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
    table.sort(current, ns.Sorter(tab))
end

function ns.CurrentList() return current end

-- A sale's P&L from the Profit & Loss module (nil: no module, or the sale isn't in its detail). Cached per redraw.
local plCache = setmetatable({}, { __mode = "k" })
function ns.SalePL(e)
    if not (e and e.k == "sale" and ProfitKing and ProfitKing.ForMail) then return nil end
    local c = plCache[e]
    if c == nil then
        c = KM.Safe(ProfitKing.ForMail, e) or false
        plCache[e] = c
    end
    return c or nil
end
function ns.ClearPL() wipe(plCache) end

local function cell(e, key)
    if key == "t" then return when(e.t) end
    if key == "name" and tab ~= "buyers" then return ns.ItemText(e.item, e.name) end
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
    if key == "pl" then
        local x = ns.SalePL(e)
        if not x then return grey("-") end
        if not x.pl then return grey("no cost") end
        local v = math.floor(x.pl + 0.5)
        local body = KM.MoneyShort(math.abs(v), true)
        if v == 0 then return UI.Hex(C.muted) .. body .. "|r" end
        return (v > 0 and (UI.Hex(C.good) .. "+") or (UI.Hex(C.bad) .. "-")) .. body .. "|r"
    end
    if key == "dep" then return e.dep and ns.Money(e.dep) or grey("unknown") end
    if key == "who" then return e.who or grey("-") end
    if key == "k" then return e.k == "cancelled" and "cancelled" or "expired" end
    if key == "units" then return e.units > 0 and tostring(e.units) or grey("-") end
    if key == "expired" then return e.expired > 0 and tostring(e.expired) or grey("-") end
    if key == "through" then return pct(e.through) end
    return ""
end

local function icon(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return inst and select(5, inst(id)) or nil
end

local function fillRow(r, e, cells)
    if r.icon then r.icon:SetTexture(icon(e.item)) end
    for _, c in ipairs(LIST_COLS[tab]) do cells[c.key]:SetText(cell(e, c.key)) end
end

local function whatText()
    return tab == "sale" and "sales" or tab == "buy" and "purchases" or tab == "expired" and "expired or cancelled auctions"
        or tab == "unsold" and "items that came back unsold" or tab == "buyers" and (sellers and "sellers" or "buyers") or "items"
end

local function listFooter()
    local t = tables[tab]
    if not t then return end
    local what = whatText()
    local hint
    if tab == "buyers" then
        hint = "Gold: " .. ns.REGULAR .. "+ " .. (sellers and "purchases" or "sales") .. ". Click one for their "
            .. (sellers and "purchases." or "sales.")
            .. ((current.unknown or 0) > 0 and ("  " .. current.unknown .. " with no name on the mail.") or "")
    else
        hint = "Right-click an item to choose its strategy."
    end
    local shown = math.min(#current, t.visible or #current)
    footer:SetText((#current > 0 and ((t.offset + 1) .. "-" .. (t.offset + shown) .. " of " .. #current .. " " .. what .. ".  ") or "")
        .. (strategyFilter and (tab == "items" or tab == "unsold") and ("Strategy: " .. strategyFilter .. " (click the tab again for all).  ") or "")
        .. (whoFilter and (tab == "sale" or tab == "buy") and ((tab == "sale" and "Buyer: " or "Seller: ") .. whoFilter .. " (click the tab again for all).  ") or "")
        .. hint)
end

local function refreshList()
    if ns.ClearPL then ns.ClearPL() end
    build()
    for id, t in pairs(tables) do t:SetShown(id == tab) end
    local t = tables[tab]
    t.emptyText = "No " .. whatText() .. " in this period."
    t:SetRows(current, fillRow)
end

---------------------------------------------------------------------------
-- Tooltips on list rows
---------------------------------------------------------------------------

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

local function rowEnter(r)
    local e = r.data
    if not e then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if tab == "buyers" then
        buyerTip(e)
        GameTooltip:Show()
        return
    end
    if e.item and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, e.item)
    else GameTooltip:AddLine(ns.ItemText(e.item, e.name)) end
    if tab == "unsold" then unsoldTip(e) end
    if tab == "sale" then
        local x = ns.SalePL(e)
        if x then
            GameTooltip:AddLine(" ")
            if x.pl then
                GameTooltip:AddDoubleLine("P&L", KM.Money(x.pl) .. (x.roi and string.format("  (%+.0f%%)", x.roi * 100) or ""), 1, 0.82, 0, 1, 1, 1)
            else
                GameTooltip:AddLine("No purchase or loot covered this sale: cost unknown.", 0.7, 0.7, 0.7, true)
            end
            for i, line in ipairs(x.lines or {}) do
                if i > 5 then break end
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
            end
            if (x.unknownQ or 0) > 0 and x.pl then GameTooltip:AddLine(x.unknownQ .. " of them had no cost known.", 0.7, 0.7, 0.7, true) end
        end
    end
    if tab == "sale" and e.who and buyerCount[e.who] then
        local n = buyerCount[e.who]
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(e.who .. " has bought from you " .. n .. " time" .. (n == 1 and "" or "s") .. ".", 1, 0.82, 0)
    end
    GameTooltip:AddLine("Right-click: choose its strategy.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function rowClick(e, which, r)
    if tab == "buyers" then
        ns.SelectTab(sellers and "buy" or "sale", nil, e.who)
    elseif which == "RightButton" then
        ns.StrategyMenu(r, e.item, e.name)
    end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function refresh()
    if not page or not ns.db then return end
    tabs:Select(tab)
    for _, b in ipairs(periodButtons) do b:SetActive(b.days == ns.db.ui.period) end
    charBtn:SetLabel(ns.db.ui.mine and "This character" or "All characters")
    sideBtn:SetShown(tab == "buyers")
    sideBtn:SetLabel(sellers and "Sellers" or "Buyers")
    summaryView:SetShown(tab == "summary")
    listView:SetShown(tab ~= "summary")
    if tab == "summary" then refreshSummary() else refreshList() end
end

-- Redraws the page if it's the one showing (the mailbox and strategy changes call this).
function ns.Refresh() KM.Refresh("ledger") end

-- strategy: only that strategy's items (Items, Not selling). who: only that buyer or seller (Sales, Purchases).
function ns.SelectTab(key, strategy, who)
    if key == tab and not strategy and not who then strategyFilter, whoFilter = nil, nil end
    if key ~= tab and not strategy then strategyFilter = nil end
    if key ~= tab and not who then whoFilter = nil end
    if strategy then strategyFilter = strategy end
    if who then whoFilter = who end
    tab = key
    if tables[key] then tables[key].offset = 0 end
    ns.Refresh()
end

function ns.CurrentTab() return tab end

function ns.SetPeriod(days)
    ns.db.ui.period = days
    for _, t in pairs(tables) do t.offset = 0 end
    ns.Refresh()
end

-- Opens (true), closes (false) or toggles (nil) the page.
function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("ledger") end
    if show then KM.Show("ledger") elseif KM.IsShown("ledger") then KM.Toggle(false) end
end

local function buildSummary(parent)
    summaryView = CreateFrame("Frame", nil, parent)
    summaryView:SetPoint("TOPLEFT", 0, -64)
    summaryView:SetPoint("BOTTOMRIGHT", 0, 20)
    tiles = {}
    for i, key in ipairs({ "net", "profit", "income", "spent", "held", "sales" }) do
        local t = UI.Tile(summaryView, TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), 0)
        tiles[key] = t
    end
    tiles.net:SetTip("Where you'd stand if you sold everything you bought in this period and still hold: net cash plus what those items fetch today (market price after the 5% cut). A week of stocking up no longer reads as a loss: only a drop in price does.")
    tiles.profit:SetTip("Gold in from auction sales minus gold out on auction purchases and lost deposits. Mats you bought and haven't sold yet count against it. Gold mailed between your characters isn't counted.")
    tiles.income:SetTip(function(tt)
        local s = ns.Summary(since(), onlyChar())
        tt:AddLine("What your auctions sold for in this period, after the auction house's 5% cut.", 1, 1, 1, true)
        tt:AddDoubleLine("Sold for", ns.Money(s.gross), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Auction house cut", "-" .. ns.Money(s.cut), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Income", ns.Money(s.income), 0.8, 0.8, 0.8, 1, 1, 1)
    end)
    tiles.spent:SetTip(function(tt)
        local s = ns.Summary(since(), onlyChar())
        tt:AddLine("Gold you paid for auction house purchases in this period. Deposits lost on auctions that came back are counted apart.", 1, 1, 1, true)
        tt:AddDoubleLine("Purchases (" .. s.bought .. " bought)", ns.Money(s.spent), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Deposits lost", ns.Money(s.lost), 0.8, 0.8, 0.8, 1, 1, 1)
    end)
    tiles.sales:SetTip(function(tt)
        local s = ns.Summary(since(), onlyChar())
        local ended = s.sales + s.expired
        tt:AddLine("Auctions that sold in this period (one mail each), and the ones that came back expired or cancelled.", 1, 1, 1, true)
        tt:AddDoubleLine("Sold", s.sales .. " (" .. s.units .. " units)", 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Came back", tostring(s.expired), 0.8, 0.8, 0.8, 1, 1, 1)
        if ended > 0 then tt:AddDoubleLine("Sell-through", string.format("%.0f%%", s.sales / ended * 100), 0.8, 0.8, 0.8, 1, 1, 1) end
    end)
    tiles.held:SetTip(function(tt)
        local bw = ns.BoughtWorth(since(), onlyChar())
        tt:AddLine("What you bought in this period and still have (counted on your characters by the Inventory module, newest purchases first), at today's market price after the cut.", 1, 1, 1, true)
        tt:AddDoubleLine("Cost of what you hold", ns.Money(bw.held), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Worth now", ns.Money(bw.worth), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Used, crafted, sold or mailed away", ns.Money(bw.gone), 0.8, 0.8, 0.8, 1, 1, 1)
        if bw.unpriced > 0 then tt:AddLine(bw.unpriced .. " held with no market price: counted at what you paid.", 0.7, 0.7, 0.7, true) end
        if bw.fromPnL then
            tt:AddLine("From Profit & Loss: the units of these purchases still in your lots (sales and stock used up take them, by its method).", 0.6, 0.6, 0.6, true)
        else
            tt:AddLine("An estimate: the newest purchases that add up to what you own. Turn on the Profit & Loss module for real lots.", 0.6, 0.6, 0.6, true)
        end
    end)

    local goldHolder = CreateFrame("Button", nil, summaryView)
    goldHolder:SetPoint("TOPLEFT", 0, -(TILE_H + 8))
    goldHolder:SetPoint("RIGHT", summaryView, "RIGHT", 0, 0)
    goldHolder:SetHeight(20)
    goldText = UI.Text(goldHolder, 12, C.text)
    goldText:SetPoint("LEFT", 2, 0)
    goldHolder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local top = ns.Buyers(since(), onlyChar()).rows
        GameTooltip:AddLine("Your best buyers")
        for i = 1, math.min(5, #top) do
            GameTooltip:AddDoubleLine(top[i].who .. "  (" .. top[i].mails .. ")", ns.Money(top[i].gold), 1, 1, 1, 1, 1, 1)
        end
        if #top == 0 then GameTooltip:AddLine("No sales in this period.", 0.6, 0.6, 0.6) end
        local w = InventoryKing and InventoryKing.NetWorth and InventoryKing.NetWorth()
        GameTooltip:AddLine(" ")
        if w then
            GameTooltip:AddDoubleLine("Net worth (Inventory)", ns.Money(w.total))
            GameTooltip:AddDoubleLine("Gold", ns.Money(w.gold + w.mail), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Items", ns.Money(w.assets), 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine("Your gold, items and net worth come from the Inventory module.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine("Click: the Buyers tab.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    goldHolder:SetScript("OnClick", function() ns.SelectTab("buyers") end)
    goldHolder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- the accrual view beside the cash one: realized P&L for the period (Profit & Loss module)
    local pnlBtn = UI.Button(summaryView, "", 220, 20, function() KM.Show("profit") end, "ghost")
    pnlBtn:SetPoint("TOPRIGHT", summaryView, "TOPRIGHT", 0, -(TILE_H + 8))
    pnlBtn.label:SetJustifyH("RIGHT")
    pnlBtn:SetFrameLevel(goldHolder:GetFrameLevel() + 2)
    UI.Tip(pnlBtn, function(tt)
        local p = pnlBtn.summary or {}
        tt:AddLine("Realized P&L")
        tt:AddLine("Profit, not cash: what your sales in this period brought after the cut, minus what those units cost you (whenever you bought them), minus deposits lost. Stock you bought and still hold isn't a loss here.", 1, 1, 1, true)
        tt:AddDoubleLine("Realized", ns.Money(p.realized), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Sales", tostring(p.sales or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddLine("Click: the Profit & Loss page.", 0.6, 0.6, 0.6)
    end)
    pnlBtn:Hide()
    ns.pnlBtn = pnlBtn

    local chart = UI.Panel(summaryView, C.panel)
    chart:SetPoint("TOPLEFT", 0, -(TILE_H + 34))
    chart:SetPoint("RIGHT", summaryView, "RIGHT", 0, 0)
    chart:SetHeight(CHART_H)
    local head = UI.Heading(chart, "Net cash per day, last " .. DAYS .. " days")
    head:SetPoint("TOPLEFT", 12, -10)
    local mid = CreateFrame("Frame", nil, chart)
    mid:SetPoint("TOPLEFT", 12, -26)
    mid:SetPoint("BOTTOMRIGHT", -12, 18)
    local axis = mid:CreateTexture(nil, "BORDER")
    axis:SetTexture(UI.WHITE)
    UI.SetColor(axis, C.border)
    axis:SetHeight(1)
    axis:SetPoint("LEFT", mid, "LEFT", 0, 0)
    axis:SetPoint("RIGHT", mid, "RIGHT", 0, 0)
    bars = {}
    local slot = 52
    for i = 1, DAYS do
        local b = CreateFrame("Frame", nil, mid)
        b:SetSize(slot - 4, HALF * 2)
        b:SetPoint("LEFT", (i - 1) * slot, 0)
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetTexture(UI.WHITE)
        b.fill:SetWidth(slot - 16)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.day then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.day.day)
            GameTooltip:AddDoubleLine("Income", ns.Money(self.day.income), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Net cash", ns.Money(self.day.profit), 1, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if i == 1 or i == DAYS or i == 8 then
            b.dateFS = UI.Text(chart, 9, C.dim, "CENTER")
            b.dateFS:SetPoint("BOTTOM", chart, "BOTTOMLEFT", 12 + (i - 1) * slot + (slot - 4) / 2, 5)
        end
        bars[i] = b
    end

    local cols = {
        { key = "key", label = "Strategy", w = 170, desc = false, sort = function(r) return r.key end },
        { key = "sales", label = "Sales", w = 60, justify = R, sort = function(r) return r.sales end },
        { key = "income", label = "Income", w = 110, justify = R, tip = "What it sold for, minus the auction house cut.", sort = function(r) return r.income end },
        { key = "spent", label = "Spent", w = 100, justify = R, tip = "What you bought on the auction house.", sort = function(r) return r.spent end },
        { key = "lost", label = "Deposits lost", w = 100, justify = R, tip = "Deposits on auctions that expired or were cancelled.", sort = function(r) return r.lost end },
        { key = "profit", label = "Profit", w = 110, justify = R, tip = "Income minus spent and deposits lost, for that strategy in this period. Flips pair a purchase with its sale (within 30 days), so their profit is the margin.", sort = function(r) return r.profit end },
        { key = "through", label = "Sell-through", w = 0, justify = R, tip = "Of the auctions that ended, how many sold.", sort = function(r) return through(r) end },
    }
    stratTable = UI.Table(summaryView, cols, 22, {
        fontSize = 11,
        onClick = function(r) ns.SelectTab("items", r.key) end,
    })
    stratTable:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -10)
    stratTable:SetPoint("BOTTOMRIGHT", 0, 0)
    stratTable.fill = fillStrategy
    ns.stratTable = stratTable
end

local function buildLists(parent)
    listView = CreateFrame("Frame", nil, parent)
    listView:SetPoint("TOPLEFT", 0, -64)
    listView:SetPoint("BOTTOMRIGHT", 0, 20)
    for id, cols in pairs(LIST_COLS) do
        for _, c in ipairs(cols) do
            local key = c.key
            c.sort = function(e) return sortValue(id, e, key) end
        end
        local t
        t = UI.Table(listView, cols, 20, {
            icon = ICONS[id], noSort = true, fontSize = 11,
            onSort = function() t.offset = 0; refreshList() end,
            onClick = rowClick, onEnter = rowEnter,
        })
        t:SetAllPoints(listView)
        t:SetSort(DEFAULT_SORT[id][1], DEFAULT_SORT[id][2])
        t.fill = fillRow
        t.onRedraw = listFooter
        t:Hide()
        tables[id] = t
    end
    ns.tables = tables
end

local function buildPage(c)
    page = c
    tabs = UI.Tabs(c, TABS, function(id) ns.SelectTab(id) end)
    tabs:SetPoint("TOPLEFT", 0, 0)
    ns.tabs = tabs
    local export = UI.Button(c, "Export", 70, 24, function() ns.Export() end)
    export:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(export, "The whole ledger as comma-separated text, for a spreadsheet.")

    charBtn = UI.Button(c, "All characters", 120, 24, function() ns.db.ui.mine = not ns.db.ui.mine; ns.Refresh() end)
    charBtn:SetPoint("TOPLEFT", 0, -32)
    UI.Tip(charBtn, function(tt) tt:AddLine("Whose mail"); tt:AddLine("Every character's auction mail, or only this character's. Click to switch.", 1, 1, 1, true) end)
    sideBtn = UI.Button(c, "Buyers", 90, 24, function()
        sellers = not sellers
        if tables.buyers then tables.buyers.offset = 0 end
        ns.Refresh()
    end)
    sideBtn:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
    UI.Tip(sideBtn, function(tt) tt:AddLine("Buyers or sellers"); tt:AddLine("The people who buy from you, or the people you buy from. Click to switch.", 1, 1, 1, true) end)
    ns.charBtn, ns.sideBtn = charBtn, sideBtn

    periodButtons = {}
    local prev
    for i = #PERIODS, 1, -1 do
        local p = PERIODS[i]
        local b = UI.Button(c, p[2], 66, 24, function() ns.SetPeriod(p[1]) end, "ghost")
        b.days = p[1]
        if prev then b:SetPoint("RIGHT", prev, "LEFT", 1, 0) else b:SetPoint("TOPRIGHT", 0, -32) end
        prev = b
        table.insert(periodButtons, b)
    end
    ns.periodButtons = periodButtons

    buildSummary(c)
    buildLists(c)

    footer = UI.Text(c, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    ns.footer = footer
end

KM.RegisterPage({
    id = "ledger", group = "ah", label = "Sales Ledger", icon = "Interface\\Icons\\INV_Letter_15", order = 30,
    title = "Sales Ledger",
    subtitle = "Every auction house mail you open: what sold, what you bought, what came back, and who's buying.",
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- Export: the ledger as comma-separated text, for a spreadsheet
---------------------------------------------------------------------------

local exportWin

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

local function exportWindow(text)
    if not exportWin then
        exportWin = UI.Window("MailKingExport", "Sales Ledger export", 600, 400)
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
    return exportWin
end

function ns.Export()
    if not ns.db then return end
    local text, n = ns.ExportText()
    exportWindow(text)
    KM.Print(ns, "Exported " .. n .. " ledger lines.")
end

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "ledger", label = "Sales Ledger", order = 15, func = function() ns.Toggle(true) end })

KM.RegisterTooltip(function(tt)
    if not ns.db or (ProfitKing and ProfitKing.IsTracking and ProfitKing.IsTracking()) then return end -- P&L's line replaces it
    local week = ns.Summary(ns.Now() - 7 * 86400)
    tt:AddDoubleLine("Profit, last 7 days", ns.Money(week.profit), 1, 1, 1, 1, 1, 1)
end)

-- With the Profit & Loss module, Home's profit tile is its realized P&L (its own tile); this cash one steps aside.
local function pnlTracks() return ProfitKing and ProfitKing.IsTracking and ProfitKing.IsTracking() end

KM.RegisterHomeTile({ id = "ledger-profit", order = 20, page = "ledger", spark = function()
    if not ns.db or pnlTracks() then return nil end
    local v = {}
    for _, d in ipairs(ns.Daily(30)) do v[#v + 1] = d.profit end
    return v, C.good
end, get = function()
    if not ns.db or (ProfitKing and ProfitKing.IsTracking and ProfitKing.IsTracking()) then return nil end
    local week = ns.Summary(ns.Now() - 7 * 86400)
    return "Profit, 7 days", ns.Money(week.profit), week.sales .. " sale" .. (week.sales == 1 and "" or "s")
        .. (week.lost > 0 and (", " .. ns.Money(week.lost) .. " deposits lost") or ""),
        week.profit < 0 and C.bad or (week.profit > 0 and C.good or C.text)
end, tip = function(tt)
    local week = ns.Summary(ns.Now() - 7 * 86400)
    tt:AddLine("Auction gold in minus auction gold out over the last 7 days, on all your characters.", 1, 1, 1, true)
    tt:AddDoubleLine("Sales, after the 5% cut", ns.Money(week.income), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Bought on the auction house", ns.Money(-week.spent), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Deposits lost on expired auctions", ns.Money(-week.lost), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddLine("Green: up. Red: you spent more than you made. Open the Sales Ledger for any period.", 0.7, 0.7, 0.7, true)
end })

-- Home: auction sales by strategy (where your gold came from), items that don't sell, and the daily chart while the
-- Profit & Loss module isn't tracking (its realized chart replaces this cash one).
KM.RegisterHomeCard({ kind = "income", id = "ledger-sales", order = 10, get = function(since)
    if not ns.db then return nil end
    local out = {}
    for _, r in ipairs(ns.Summary(since).strategies) do
        if r.income > 0 then
            out[#out + 1] = { label = tostring(r.key), value = r.income, page = "ledger",
                tip = "Auction house sales under the strategy " .. tostring(r.key) .. ", after the 5% cut: " .. r.sales
                    .. " sale" .. (r.sales == 1 and "" or "s") .. ", " .. KM.Money(r.income) .. "." }
        end
    end
    return out
end })

KM.RegisterHomeCard({ kind = "attention", id = "ledger-unsold", order = 40, get = function()
    if not ns.db then return nil end
    local n, lost, names = 0, 0, {}
    for _, r in ipairs(ns.NotSelling(ns.Now() - 30 * 86400)) do
        if r.why and (r.held == nil or r.held > 0) then
            n, lost = n + 1, lost + (r.lost or 0)
            if #names < 5 then names[#names + 1] = (r.name or tostring(r.key)) .. (r.why == "over" and " (priced over the market)" or (r.why == "never" and " (never sold)" or " (sells slowly)")) end
        end
    end
    if n == 0 then return nil end
    return { { text = n .. " item" .. (n == 1 and "" or "s") .. " not selling", color = C.warn, value = lost > 0 and ("-" .. KM.MoneyShort(lost, true)) or nil,
        page = "ledger", tab = function() ns.SelectTab("unsold") end,
        tip = function(tt)
            tt:AddLine("Auctions that keep expiring in the last 30 days (" .. KM.Money(lost) .. " in deposits lost):", 1, 1, 1, true)
            for _, s in ipairs(names) do tt:AddLine(s, 0.8, 0.8, 0.8, true) end
            tt:AddLine("Click for the Sales Ledger's Not selling tab.", 0.6, 0.6, 0.6)
        end } }
end })

KM.RegisterHomeCard({ kind = "chart", id = "ledger-daily", order = 21, label = "Daily profit", title = "Auction profit per day, 30 days",
    emptyText = "No auction mail in the last 30 days yet: open your mailbox after something sells.",
    shown = function() return ns.db ~= nil and not pnlTracks() end,
    get = function()
        local pts, any = {}, false
        for _, d in ipairs(ns.Daily(30)) do
            if d.profit ~= 0 or d.income ~= 0 then any = true end
            pts[#pts + 1] = { d.d * 86400 + 43200, d.profit, d.profit < 0 and C.bad or C.good, d }
        end
        if not any then return nil end
        return { series = { { pts = pts, style = "bars", agg = "none" } }, zero = true,
            format = function(v) return KM.MoneyShort(v, true) end,
            xformat = function(x) return date and date("%d %b", x) or tostring(x) end,
            hover = function(x, p)
                local d = p and p[4] or {}
                GameTooltip:AddLine(date and date("%d %b", x) or "", C.accent[1], C.accent[2], C.accent[3])
                GameTooltip:AddDoubleLine("Profit", KM.Money(d.profit), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Sales after the cut", KM.Money(d.income), 0.8, 0.8, 0.8, 1, 1, 1)
            end }
    end })

KM.RegisterSettings({ id = "mail", label = "Sales Ledger", order = 15, rows = {
    { type = "header", label = "Sales Ledger" },
    { type = "choice", label = "Period", options = { { 1, "Today" }, { 7, "7 days" }, { 30, "30 days" }, { 0, "All" } },
      get = function() return ns.db.ui.period end, set = function(v) ns.SetPeriod(v) end },
    { type = "check", label = "Only this character's mail", tip = "Every character's auction mail, or only the one you're on.",
      get = function() return ns.db.ui.mine end, set = function(v) ns.db.ui.mine = v; ns.Refresh() end },
    { type = "text", label = "Every auction house mail you open is recorded once: sales (dated when they sold), purchases, and expired or cancelled auctions with the deposit lost. Right-click any item on the Sales Ledger to choose its strategy." },
    { type = "check", label = "My characters beside the mailbox", tip = "A list of your other characters next to the mailbox: click one to put its name in Send Mail's To: box.",
      get = function() return ns.db.ui.alts end, set = function(v) ns.SetAlts(v) end },
    { type = "button", label = "Export the ledger", func = function() ns.Export() end, tip = "The whole ledger as comma-separated text, for a spreadsheet." },
    { type = "button", label = "Clear the whole ledger", func = function() StaticPopup_Show("MAILKING_RESET") end, tip = "Deletes every recorded sale, purchase and expired auction, for all your characters; it can't be undone. Asks first. Your strategies stay." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/mlk   open the Sales Ledger\n/mlk status   what's been recorded\n/mlk export   the ledger for a spreadsheet\n/mlk alts   your characters beside the mailbox\n/mlk reset yes   clear the whole ledger" },
} })
