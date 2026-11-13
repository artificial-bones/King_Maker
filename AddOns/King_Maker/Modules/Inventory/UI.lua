local _, KM = ...
local ns = KM.Module("Inventory")
local UI = KM.UI
local C = UI.C

-- The Inventory page of the King Maker window (Gold > Inventory), with two tabs:
--   Overview: net worth, gold on your characters and in their mailboxes, what your items are worth; net worth
--             over the last 30 days (gold and items stacked); every character, richest first. Click one to see
--             their items, right-click to forget one.
--   Items:    every item you own. Categories down the left (the auction house's, and the Sales Ledger's
--             strategies); pick whose and where at the top, search by name, click a column to sort.
-- Valued at (top right) picks market price or lowest buyout; Export gives everything as CSV.
-- Also here: the crown's quick action and tooltip line, the Home tile and the Settings section.

local SIDE_W, SIDE_H, SIDE_ROWS = 164, 21, 24
local DAYS = 30
local TILE_W, TILE_H = 146, 58
local CHART_H, BAR_H, SLOT = 132, 84, 24
local GREY = "|cff808080"

local page, tabs, priceBtn
local overview, tiles, bars, peakFS, charTable, overFooter
local itemsView, itemTable, sideButtons, whoBtn, whereBtn, searchBox, itemFooter
local tab, sideOffset = "overview", 0
local filter = {} -- who, place, search, cls, sub, strategy
local current = {} -- the item rows on show
local lastRes

local function grey(t) return GREY .. t .. "|r" end

local function ago(t)
    if not t then return grey("never") end
    local d = ns.Now() - t
    if d < 3600 then return "now" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    return math.floor(d / 86400) .. " days ago"
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- Menus: whose items, where, and how they're valued
---------------------------------------------------------------------------

local function menu(owner, gen)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        KM.Print(ns, "Menus need a newer client.")
        return
    end
    MenuUtil.CreateContextMenu(owner, gen)
end

local function whoText(who) return who and ns.CharText(who) or "All characters" end
local function whereText() return filter.place and ns.PLACE_NAMES[filter.place] or "Everywhere" end
local function priceText()
    return (ns.db and ns.db.ui.price == "lowest") and "Valued at: lowest buyout" or "Valued at: market price"
end

local function whoMenu(_, root)
    root:CreateTitle("Whose items")
    root:CreateRadio("All characters", function() return filter.who == nil end, function() ns.Filter("who", nil) end)
    for _, who in ipairs(ns.Known()) do
        root:CreateRadio(ns.CharText(who), function() return filter.who == who end, function() ns.Filter("who", who) end)
    end
end

local function whereMenu(_, root)
    root:CreateTitle("Where")
    root:CreateRadio("Everywhere", function() return filter.place == nil end, function() ns.Filter("place", nil) end)
    for _, p in ipairs(ns.PLACES) do
        root:CreateRadio(ns.PLACE_NAMES[p], function() return filter.place == p end, function() ns.Filter("place", p) end)
    end
end

function ns.SetPricing(price, vendor)
    if price then ns.db.ui.price = price end
    if vendor ~= nil then ns.db.ui.vendor = vendor end
    ns.Snapshot()
    ns.Refresh()
end

local function priceMenu(_, root)
    root:CreateTitle("Value items at")
    root:CreateRadio("Market price (Deep Scan)", function() return ns.db.ui.price == "market" end, function() ns.SetPricing("market") end)
    root:CreateRadio("Lowest buyout", function() return ns.db.ui.price == "lowest" end, function() ns.SetPricing("lowest") end)
    root:CreateCheckbox("No auction price: use the vendor price", function() return ns.db.ui.vendor end,
        function() ns.SetPricing(nil, not ns.db.ui.vendor) end)
end

function ns.CharMenu(owner) menu(owner, whoMenu) end
function ns.PlaceMenu(owner) menu(owner, whereMenu) end
function ns.PriceMenu(owner) menu(owner, priceMenu) end

StaticPopupDialogs.INVENTORYKING_FORGET = {
    text = "Forget %s? Their items, gold and history go. They come back next time you log in on them.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, who)
        ns.Forget(who)
        if KM.IsShown("settings") then KM.OpenSettings("inventory") end -- the Forget buttons there change
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.AskForget(who)
    if who then StaticPopup_Show("INVENTORYKING_FORGET", ns.Short(who), nil, who) end
end

function ns.CharacterMenu(owner, who)
    menu(owner, function(_, root)
        root:CreateTitle(ns.CharText(who))
        root:CreateButton("Show their items", function() ns.ShowItems({ who = who }) end)
        root:CreateButton("Forget this character", function() ns.AskForget(who) end)
    end)
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------

local TILES = {
    { "total", "Net worth", "Gold on every character, gold in their mailboxes, and what all your items are worth." },
    { "gold", "Gold on characters", "As of when you last played each one." },
    { "mail", "Gold in mailboxes", "Not collected yet: sales and other mail." },
    { "assets", "Items worth", "Everything you own that can be sold, at today's prices." },
    { "items", "Items", "Every item that can be sold, on every character and the warband bank." },
}

local function refreshOverview()
    local w = ns.NetWorth()
    tiles.total:Set("Net worth", ns.Money(w.total), "on " .. w.chars .. " character" .. (w.chars == 1 and "" or "s"), C.accent)
    tiles.gold:Set("Gold on characters", ns.Money(w.gold))
    tiles.mail:Set("Gold in mailboxes", ns.Money(w.mail), w.mail > 0 and "not collected yet" or nil)
    tiles.assets:Set("Items worth", ns.Money(w.assets), ns.db.ui.price == "lowest" and "at lowest buyouts" or "at market prices")
    tiles.items:Set("Items", KM.Commas(w.items))

    -- Net worth per day, gold at the bottom and items stacked on top.
    local days = ns.Series(DAYS)
    local top = 1
    for _, d in ipairs(days) do top = math.max(top, d.total) end
    for i, d in ipairs(days) do
        local b = bars[i]
        b.day = d
        local gh = d.gold / top * BAR_H
        local ah = d.assets / top * BAR_H
        b.gold:SetHeight(math.max(gh, 0.5))
        b.assets:SetHeight(math.max(ah, 0.5))
        b.gold:SetShown(d.gold > 0)
        b.assets:SetShown(d.assets > 0)
        b.none:SetShown(not d.known)
    end
    peakFS:SetText(top > 1 and ("peak " .. ns.Gold(top)) or "")

    local list = ns.Characters()
    charTable.total = w.total
    charTable.emptyText = "Nothing yet: log in on each of your characters, and open their bank once."
    charTable:SetRows(list)
    local missing = 0
    for _, c in ipairs(list) do if c.who ~= ns.WARBAND and not c.bankSeen then missing = missing + 1 end end
    overFooter:SetText(w.chars .. " characters.  Click one for their items, right-click to forget them."
        .. (missing > 0 and ("  " .. UI.Hex(C.warn) .. missing .. " bank" .. (missing == 1 and "" or "s")
            .. " not seen yet: open it once on that character.|r") or ""))
end

local function fillChar(r, c, cells)
    local isBank = c.who == ns.WARBAND
    local total = charTable.total or 0
    cells.who:SetText(ns.CharText(c.who))
    cells.level:SetText(c.level and tostring(c.level) or grey("-"))
    cells.gold:SetText(isBank and grey("-") or ns.Money(c.gold))
    cells.mail:SetText(c.mail > 0 and ns.Money(c.mail) or grey("-"))
    cells.assets:SetText(c.assets > 0 and ns.Money(c.assets) or grey("-"))
    cells.worth:SetText(ns.Money(c.worth))
    cells.share:SetText(total > 0 and string.format("%.0f%%", c.worth / total * 100) or grey("-"))
    cells.seen:SetText(isBank and grey("-") or ago(c.seen))
    cells.bank:SetText(c.bankSeen and ago(c.bankSeen) or (UI.Hex(C.warn) .. "not yet|r"))
    r.tip = function(tt)
        tt:AddLine(ns.CharText(c.who))
        tt:AddLine("Click: their items.  Right-click: forget them.", 0.6, 0.6, 0.6)
    end
end

local function buildOverview(parent)
    overview = CreateFrame("Frame", nil, parent)
    overview:SetPoint("TOPLEFT", 0, -34)
    overview:SetPoint("BOTTOMRIGHT", 0, 0)

    tiles = {}
    for i, t in ipairs(TILES) do
        local tile = UI.Tile(overview, TILE_W, TILE_H)
        tile:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 8), 0)
        tile:EnableMouse(true)
        UI.Tip(tile, function(tt) tt:AddLine(t[2]); tt:AddLine(t[3], 1, 1, 1, true) end)
        tiles[t[1]] = tile
    end

    local chart = UI.Panel(overview, C.panel)
    chart:SetPoint("TOPLEFT", 0, -(TILE_H + 10))
    chart:SetPoint("RIGHT", overview, "RIGHT", 0, 0)
    chart:SetHeight(CHART_H)
    local head = UI.Heading(chart, "Net worth, last " .. DAYS .. " days")
    head:SetPoint("TOPLEFT", 12, -10)
    local legend = UI.Text(chart, 10, C.muted, "RIGHT")
    legend:SetPoint("TOPRIGHT", -12, -10)
    legend:SetText(UI.Hex(C.accent) .. "gold|r   " .. UI.Hex(C.info) .. "items|r")
    peakFS = UI.Text(chart, 10, C.dim)
    peakFS:SetPoint("LEFT", head, "RIGHT", 12, 0)
    local axis = chart:CreateTexture(nil, "BORDER")
    axis:SetTexture(UI.WHITE)
    UI.SetColor(axis, C.border)
    axis:SetHeight(1)
    axis:SetPoint("BOTTOMLEFT", 12, 22)
    axis:SetPoint("BOTTOMRIGHT", -12, 22)
    bars = {}
    for i = 1, DAYS do
        local b = CreateFrame("Frame", nil, chart)
        b:SetSize(SLOT - 2, BAR_H)
        b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * SLOT, 23)
        b.gold = b:CreateTexture(nil, "ARTWORK")
        b.gold:SetTexture(UI.WHITE)
        UI.SetColor(b.gold, { C.accent[1], C.accent[2], C.accent[3], 0.85 })
        b.gold:SetWidth(SLOT - 8)
        b.gold:SetPoint("BOTTOM", b, "BOTTOM", 0, 0)
        b.assets = b:CreateTexture(nil, "ARTWORK")
        b.assets:SetTexture(UI.WHITE)
        UI.SetColor(b.assets, { C.info[1], C.info[2], C.info[3], 0.85 })
        b.assets:SetWidth(SLOT - 8)
        b.assets:SetPoint("BOTTOM", b.gold, "TOP", 0, 0)
        b.none = b:CreateTexture(nil, "BACKGROUND")
        b.none:SetTexture(UI.WHITE)
        UI.SetColor(b.none, C.zebra)
        b.none:SetPoint("TOPLEFT", 3, 0)
        b.none:SetPoint("BOTTOMRIGHT", -3, 0)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            local d = self.day
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(d.label)
            if not d.known then
                GameTooltip:AddLine("Before the Inventory module started counting.", 0.6, 0.6, 0.6)
            else
                GameTooltip:AddDoubleLine("Gold", ns.Money(d.gold), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Items", ns.Money(d.assets), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Net worth", ns.Money(d.total), 1, 0.82, 0, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bars[i] = b
        if i == 1 or i == DAYS or i == 16 then
            local lab = UI.Text(chart, 9, C.dim, "CENTER")
            lab:SetPoint("TOP", b, "BOTTOM", 0, -5)
            b.dateFS = lab
        end
    end
    local function money(key) return function(c) return c[key] end end
    local cols = {
        { key = "who", label = "Character", w = 140, desc = false, sort = function(c) return ns.Short(c.who) end },
        { key = "level", label = "Level", w = 40, justify = "RIGHT", sort = money("level") },
        { key = "gold", label = "Gold", w = 96, justify = "RIGHT", sort = money("gold"), tip = "Gold on the character, as of when you last played them." },
        { key = "mail", label = "Mailbox", w = 88, justify = "RIGHT", sort = money("mail"), tip = "Gold waiting in their mailbox (auction sales and other mail), as of their last visit to it." },
        { key = "assets", label = "Items worth", w = 96, justify = "RIGHT", sort = money("assets"), tip = "Everything they hold that can be sold, at today's prices." },
        { key = "worth", label = "Net worth", w = 100, justify = "RIGHT", sort = money("worth") },
        { key = "share", label = "Share", w = 48, justify = "RIGHT", sort = money("worth"), tip = "Of your total net worth." },
        { key = "seen", label = "Last seen", w = 78, justify = "RIGHT", sort = money("seen") },
        { key = "bank", label = "Bank", w = 0, justify = "RIGHT", sort = money("bankSeen"), tip = "When their bank was last opened. Until then it isn't counted." },
    }
    charTable = UI.Table(overview, cols, 22, {
        fontSize = 11,
        onClick = function(c, which, r)
            if which == "RightButton" then ns.CharacterMenu(r, c.who) else ns.ShowItems({ who = c.who }) end
        end,
    })
    charTable:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -10)
    charTable:SetPoint("BOTTOMRIGHT", 0, 20)
    charTable.fill = fillChar
    ns.charTable = charTable

    overFooter = UI.Text(overview, 10, C.muted)
    overFooter:SetPoint("BOTTOMLEFT", 0, 4)
    overFooter:SetPoint("RIGHT", overview, "RIGHT", 0, 0)
    ns.overFooter = overFooter
end

local function refreshDates()
    for _, b in ipairs(bars) do
        if b.dateFS then b.dateFS:SetText(b.day and b.day.label or "") end
    end
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

local function sortValue(r, key)
    if key == "name" then return r.name or "" end
    if key == "chars" then return count(r.chars) end
    return r[key]
end

local function sorter(a, b)
    local key, desc = itemTable.sortKey or "value", itemTable.sortDesc
    local x, y = sortValue(a, key), sortValue(b, key)
    if x == nil or y == nil then
        if x ~= nil or y ~= nil then return x ~= nil end -- blanks last either way
        return (a.name or "") < (b.name or "")
    end
    if x == y then return (a.name or "") < (b.name or "") end
    if desc then return x > y end
    return x < y
end

local function icon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return inst and select(5, inst(id)) or nil
end

local function fillItem(r, e, cells)
    if r.icon then r.icon:SetTexture(icon(e.item)) end
    cells.name:SetText(ns.ItemText(e.item))
    for _, p in ipairs(ns.PLACES) do
        local v = e[p]
        cells[p]:SetText(v and v > 0 and tostring(v) or grey("-"))
    end
    cells.total:SetText(tostring(e.total))
    cells.chars:SetText(tostring(count(e.chars)))
    if not e.each then
        cells.each:SetText(grey("no price"))
        cells.value:SetText(grey("no price"))
    else
        cells.each:SetText((e.src == "vendor" and (GREY .. "(v)|r ") or "") .. ns.Money(e.each))
        cells.value:SetText(ns.Money(e.value))
    end
end

-- The sidebar: All items, the categories with something in them (the picked one opened up), then the Sales
-- Ledger's strategies.
local function sideEntries(res)
    local out = { { label = "All items", value = res.allValue, count = res.allCount, pick = {} } }
    for _, cls in ipairs(ns.CLASS_ORDER) do
        local c = res.cats[cls]
        if c then
            table.insert(out, { label = ns.ClassName(cls), value = c.value, count = c.count, pick = { cls = cls } })
            if filter.cls == cls then
                local subs = {}
                for sub, s in pairs(c.subs) do table.insert(subs, { sub = sub, s = s }) end
                table.sort(subs, function(a, b)
                    if a.s.value ~= b.s.value then return a.s.value > b.s.value end
                    return a.sub < b.sub
                end)
                for _, s in ipairs(subs) do
                    table.insert(out, { label = ns.SubclassName(cls, s.sub), indent = true, value = s.s.value, count = s.s.count,
                        pick = { cls = cls, sub = s.sub } })
                end
            end
        end
    end
    for cls, c in pairs(res.cats) do -- anything outside the usual classes
        local known = false
        for _, k in ipairs(ns.CLASS_ORDER) do if k == cls then known = true end end
        if not known then table.insert(out, { label = ns.ClassName(cls), value = c.value, count = c.count, pick = { cls = cls } }) end
    end
    local strategies = {}
    for name, s in pairs(res.strategies) do table.insert(strategies, { name = name, s = s }) end
    if #strategies > 0 then
        table.sort(strategies, function(a, b)
            if a.s.value ~= b.s.value then return a.s.value > b.s.value end
            return a.name < b.name
        end)
        table.insert(out, { header = "Ledger strategies" })
        for _, s in ipairs(strategies) do
            table.insert(out, { label = s.name, value = s.s.value, count = s.s.count, pick = { strategy = s.name } })
        end
    end
    return out
end

local function picked(p)
    return p ~= nil and p.cls == filter.cls and p.sub == filter.sub and p.strategy == filter.strategy
end

local function refreshSide(res)
    local list = sideEntries(res)
    sideOffset = math.max(0, math.min(sideOffset, #list - SIDE_ROWS))
    for i, b in ipairs(sideButtons) do
        local e = list[i + sideOffset]
        b.entry = e
        if e then
            local x = e.indent and 20 or 6
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -6 - (i - 1) * SIDE_H)
            b:SetWidth(SIDE_W - 6 - x)
            if e.header then
                b:SetLabel(UI.Hex(C.accent) .. e.header:upper() .. "|r")
                b.value:SetText("")
                b:SetActive(false)
            else
                b:SetLabel(e.label)
                local col = e.indent and C.muted or C.text
                b:SetActive(picked(e.pick))
                if not picked(e.pick) then b.label:SetTextColor(col[1], col[2], col[3]) end
                b.value:SetText(e.value > 0 and ns.Gold(e.value) or grey(tostring(e.count)))
            end
            b:Show()
        else
            b:Hide()
        end
    end
end

local function itemFooterText()
    if not lastRes then return end
    local shown = math.min(#current, itemTable.visible or #current)
    itemFooter:SetText((#current > 0 and ((itemTable.offset + 1) .. "-" .. (itemTable.offset + shown) .. " of " .. #current .. " items.  ") or "")
        .. "Worth " .. ns.Money(lastRes.value) .. "."
        .. (lastRes.unpriced > 0 and ("  " .. lastRes.unpriced .. " with no price.") or "")
        .. "  Shift-click to link.")
end

local function refreshItems()
    local res = ns.Items(filter)
    -- totals for "All items" under the same who / where / search
    local all, allCount = 0, 0
    for _, c in pairs(res.cats) do all, allCount = all + c.value, allCount + c.count end
    res.allValue, res.allCount = all, allCount
    lastRes = res
    refreshSide(res)
    current = res.rows
    table.sort(current, sorter)
    whoBtn:Refresh()
    whereBtn:Refresh()
    itemTable.emptyText = "Nothing here. Try All items, all characters, everywhere, or clear the search."
    itemTable:SetRows(current, fillItem)
end

function ns.CurrentItems() return current end

local function itemTip(r)
    local e = r.data
    if not e then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, e.item) end
    GameTooltip:AddLine(" ")
    local list = {}
    for who, n in pairs(e.chars) do table.insert(list, { who, n }) end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    for _, c in ipairs(list) do
        local bits = {}
        for _, p in ipairs(ns.PLACES) do
            local n = e.where[c[1]][p]
            if n then table.insert(bits, (p == "ah" and "on AH" or ns.PLACE_NAMES[p]:lower()) .. " " .. n) end
        end
        GameTooltip:AddDoubleLine(ns.CharText(c[1]) .. "  " .. c[2], table.concat(bits, ", "), 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if e.src == "vendor" then GameTooltip:AddLine("Valued at the vendor price: the auction house has none.", 0.6, 0.6, 0.6, true) end
    if e.strategy then GameTooltip:AddLine("Ledger strategy: " .. e.strategy, 0.6, 0.6, 0.6) end
    GameTooltip:AddLine("Shift-click: link it in chat.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function linkFor(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local _, link = get(id)
    return link
end

local function sideButton(parent)
    local b = UI.Button(parent, "", SIDE_W - 12, SIDE_H - 2, function(self)
        local e = self.entry
        if not e or e.header then return end
        -- clicking the open category again closes it
        if e.pick.cls and not e.pick.sub and filter.cls == e.pick.cls and not filter.sub then e = { pick = {} } end
        filter.cls, filter.sub, filter.strategy = e.pick.cls, e.pick.sub, e.pick.strategy
        itemTable.offset = 0
        ns.Refresh()
    end, "ghost")
    b.label:SetJustifyH("LEFT")
    b:SetPadding(6, 64)
    b.value = UI.Text(b, 10, C.dim, "RIGHT")
    b.value:SetPoint("RIGHT", -6, 0)
    return b
end

local function buildItems(parent)
    itemsView = CreateFrame("Frame", nil, parent)
    itemsView:SetPoint("TOPLEFT", 0, -34)
    itemsView:SetPoint("BOTTOMRIGHT", 0, 0)

    local side = CreateFrame("Frame", nil, itemsView)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDE_W)
    UI.Fill(side, { 0, 0, 0, 0.18 })
    UI.Border(side)
    sideButtons = {}
    for i = 1, SIDE_ROWS do sideButtons[i] = sideButton(side) end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        sideOffset = math.max(0, sideOffset - delta * 3)
        ns.Refresh()
    end)
    ns.sideButtons = sideButtons

    local right = CreateFrame("Frame", nil, itemsView)
    right:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    whoBtn = UI.MenuButton(right, 160, function() return whoText(filter.who) end, whoMenu)
    whoBtn:SetPoint("TOPLEFT", 0, 0)
    UI.Tip(whoBtn, function(tt) tt:AddLine("Whose items"); tt:AddLine("Everyone's (and the warband bank), or one character's.", 1, 1, 1, true) end)
    whereBtn = UI.MenuButton(right, 150, whereText, whereMenu)
    whereBtn:SetPoint("LEFT", whoBtn, "RIGHT", 6, 0)
    UI.Tip(whereBtn, function(tt) tt:AddLine("Where"); tt:AddLine("Bags, bank, mailbox, auction house, or everywhere.", 1, 1, 1, true) end)
    searchBox = UI.EditBox(right, 180, 24, "Search items or categories", function(text, user)
        if not user then return end
        if text ~= (filter.search or "") then ns.Filter("search", text ~= "" and text or nil) end
    end)
    searchBox:SetPoint("LEFT", whereBtn, "RIGHT", 6, 0)
    ns.whoBtn, ns.whereBtn, ns.searchBox = whoBtn, whereBtn, searchBox

    local function col(key, label, w, tip)
        return { key = key, label = label, w = w, tip = tip, justify = key ~= "name" and "RIGHT" or nil, desc = key ~= "name",
                 sort = function(r) return sortValue(r, key) end }
    end
    local cols = {
        col("name", "Item", 150),
        col("bags", "Bags", 40),
        col("bank", "Bank", 40, "As of when each bank was last opened (and the warband bank)."),
        col("mail", "Mail", 40, "Attached to mail in the mailbox."),
        col("ah", "On AH", 46, "Your auctions still up, as of when you last looked."),
        col("total", "Total", 44),
        col("chars", "Chars", 40, "How many characters hold it. Hover an item for who."),
        col("each", "Each", 88, "The Scanner module's price. (v): a vendor price, as the auction house has none."),
        col("value", "Worth", 0),
    }
    itemTable = UI.Table(right, cols, 20, {
        icon = true, noSort = true, fontSize = 11,
        onSort = function() itemTable.offset = 0; refreshItems() end,
        onClick = function(e)
            if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                local link = linkFor(e.item)
                if link then ChatEdit_InsertLink(link) end
            end
        end,
        onEnter = itemTip,
    })
    itemTable:SetPoint("TOPLEFT", 0, -32)
    itemTable:SetPoint("BOTTOMRIGHT", 0, 20)
    itemTable:SetSort("value", true)
    itemTable.fill = fillItem
    itemTable.onRedraw = itemFooterText
    ns.itemTable = itemTable

    itemFooter = UI.Text(right, 10, C.muted)
    itemFooter:SetPoint("BOTTOMLEFT", 0, 4)
    itemFooter:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    ns.itemFooter = itemFooter
end

---------------------------------------------------------------------------
-- The page: tabs, filters, refreshing
---------------------------------------------------------------------------

local function refresh()
    if not page or not ns.db then return end
    tabs:Select(tab)
    priceBtn:Refresh()
    overview:SetShown(tab == "overview")
    itemsView:SetShown(tab == "items")
    if tab == "overview" then refreshOverview(); refreshDates() else refreshItems() end
end

-- Redraws the page if it's the one showing (scans, bag changes and filters call this).
function ns.Refresh() KM.Refresh("inventory") end

function ns.SelectTab(key)
    tab = key
    if itemTable then itemTable.offset = 0 end
    ns.Refresh()
end

-- Change one filter: who, place, search, or the category (cls/sub/strategy).
function ns.Filter(key, value)
    filter[key] = value
    if itemTable then itemTable.offset = 0 end
    ns.Refresh()
end

-- The Items tab with these filters (the rest cleared).
function ns.ShowItems(f)
    filter = f or {}
    if searchBox then searchBox:SetText(filter.search or "") end
    tab = "items"
    if itemTable then itemTable.offset = 0 end
    ns.Toggle(true)
    ns.Refresh()
end

function ns.GetFilter() return filter end
function ns.CurrentTab() return tab end

-- Opens (true), closes (false) or toggles (nil) the page.
function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("inventory") end
    if show then KM.Show("inventory") elseif KM.IsShown("inventory") then KM.Toggle(false) end
end

local function buildPage(c)
    page = c
    tabs = UI.Tabs(c, { { id = "overview", label = "Overview", w = 96 }, { id = "items", label = "Items", w = 96 } }, function(id) ns.SelectTab(id) end)
    tabs:SetPoint("TOPLEFT", 0, 0)
    ns.tabs = tabs

    local export = UI.Button(c, "Export", 70, 24, function() ns.Export() end)
    export:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(export, "Every item and every character as comma-separated text, for a spreadsheet.")
    priceBtn = UI.MenuButton(c, 190, priceText, priceMenu)
    priceBtn:SetPoint("RIGHT", export, "LEFT", -6, 0)
    UI.Tip(priceBtn, function(tt)
        tt:AddLine("How items are valued")
        tt:AddLine("The Scanner module's market price (from a Deep Scan) or the lowest buyout. Items the auction house "
            .. "has no price for can count at what a vendor pays.", 1, 1, 1, true)
    end)
    ns.priceBtn = priceBtn

    buildOverview(c)
    buildItems(c)
end

KM.RegisterPage({
    id = "inventory", group = "gold", label = "Inventory", icon = "Interface\\Icons\\INV_Misc_Bag_08", order = 10,
    title = "Inventory",
    subtitle = "Everything you own on every character, what it's worth, and your net worth.",
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- Export: items and characters as comma-separated text, for a spreadsheet
---------------------------------------------------------------------------

local exportWin

function ns.ExportText()
    local function q(v) v = tostring(v or ""); return v:find("[,\"]") and ('"' .. v:gsub('"', '""') .. '"') or v end
    local lines = { "item,item_id,category,subcategory,bags,bank,mail,on_ah,total,each,worth,price_from,characters" }
    local res = ns.Items({})
    for _, r in ipairs(res.rows) do
        local who = {}
        for c, n in pairs(r.chars) do table.insert(who, c .. ":" .. n) end
        table.sort(who)
        table.insert(lines, table.concat({ q(r.name or ("Item " .. r.item)), r.item, q(ns.ClassName(r.cls)),
            q(ns.SubclassName(r.cls, r.sub)), r.bags, r.bank, r.mail, r.ah, r.total, r.each or "",
            r.value and math.floor(r.value) or "", r.src or "", q(table.concat(who, " ")) }, ","))
    end
    local nItems = #res.rows
    table.insert(lines, "")
    table.insert(lines, "character,level,gold,mailbox,items_worth,net_worth")
    for _, c in ipairs(ns.Characters()) do
        table.insert(lines, table.concat({ q(c.who), c.level or "", c.gold, c.mail, math.floor(c.assets), math.floor(c.worth) }, ","))
    end
    return table.concat(lines, "\n"), nItems
end

local function exportWindow(text)
    if not exportWin then
        exportWin = UI.Window("InventoryKingExport", "Inventory export", 600, 400)
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
    KM.Print(ns, "Exported " .. n .. " items and your characters.")
end

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "inventory", label = "Inventory", order = 30, func = function() ns.Toggle(true) end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local w = ns.NetWorth()
    tt:AddDoubleLine("Net worth", ns.Money(w.total), 1, 1, 1, 1, 1, 1)
end)

KM.RegisterHomeTile({ id = "inventory-worth", order = 30, get = function()
    if not ns.db then return nil end
    local w = ns.NetWorth()
    return "Net worth", ns.Money(w.total), "gold " .. ns.Gold(w.gold + w.mail) .. ", items " .. ns.Gold(w.assets), C.accent
end })

KM.RegisterSettings({ id = "inventory", label = "Inventory", order = 30, rows = function()
    local rows = {
        { type = "header", label = "Tooltips" },
        { type = "check", label = "How many you own, in item tooltips", tip = "Every character holding it, and where: bags, bank, mail, on the auction house.",
          get = function() return ns.db.ui.tooltip end, set = function(v) ns.db.ui.tooltip = v end },
        { type = "header", label = "Bags" },
        { type = "check", label = "Mark the cheapest stack in your bags", tip = "A red X in the bottom-left corner of the stack you'd lose least by deleting when you need space: vendor or auction price (after the cut), whichever is more, times the stack. Quest items, keys, tools and items with no price are never marked; /ik keep <item> protects one.",
          get = function() return ns.db.ui.cheapest end, set = function(v) ns.db.ui.cheapest = v; ns.UpdateCheapest() end },
        { type = "header", label = "What it's worth" },
        { type = "choice", label = "Value items at", options = { { "market", "Market price" }, { "lowest", "Lowest buyout" } },
          get = function() return ns.db.ui.price end, set = function(v) ns.SetPricing(v) end },
        { type = "check", label = "No auction price: count the vendor price", tip = "Otherwise an item the auction house has no price for counts as nothing.",
          get = function() return ns.db.ui.vendor end, set = function(v) ns.SetPricing(nil, v) end },
        { type = "header", label = "Characters" },
    }
    local known = ns.db and ns.Known() or {}
    if #known == 0 then
        rows[#rows + 1] = { type = "text", label = "No characters yet: log in on each one, and open their bank once." }
    else
        rows[#rows + 1] = { type = "text", label = "Forget a character you've deleted, renamed or moved: their items, gold and history go." }
        for _, who in ipairs(known) do
            local label = who == ns.WARBAND and "Forget the warband bank" or ("Forget " .. ns.Short(who))
            rows[#rows + 1] = { type = "button", label = label, func = function() ns.AskForget(who) end }
        end
    end
    rows[#rows + 1] = { type = "header", label = "Commands" }
    rows[#rows + 1] = { type = "text", label = "/ik   open Inventory\n/ik status   your net worth in one line\n/ik price market|lowest   how items are valued\n"
        .. "/ik vendor on|off   vendor prices for items with no auction price\n/ik tooltip on|off   counts in item tooltips\n"
        .. "/ik forget Name-Realm   forget a character\n/ik export   items and characters for a spreadsheet" }
    return rows
end })
