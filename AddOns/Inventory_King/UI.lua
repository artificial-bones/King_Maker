local _, ns = ...

-- The Inventory King window.
--   Overview: net worth, gold on your characters and in their mailboxes, what
--             your items are worth; net worth over the last 30 days; every
--             character, richest first. Click one to see their items.
--   Items:    every item you own. Categories down the left (the auction
--             house's, and Mail King's strategies when it's installed); pick
--             whose and where at the top, search by name, click a column to sort.

local WIDTH, HEIGHT = 900, 580
local ROWS, ROW_H = 22, 18
local CHAR_ROWS = 13
local SIDE_W, SIDE_ROWS = 176, 25
local MAX_COLS = 10
local DAYS = 30
local GREY = "|cff808080"

local frame, tabButtons, footer, priceBtn
local overview, tiles, bars, charTable
local itemsView, itemTable, side, charBtn, placeBtn, searchBox
local tab, offset, sideOffset = "overview", 0, 0
local filter = {} -- who, place, search, cls, sub, strategy
local sort = { key = "value", desc = true }
local current = {} -- the rows on show

local function grey(t) return GREY .. t .. "|r" end

local function ago(t)
    if not t then return grey("never") end
    local d = ns.Now() - t
    if d < 3600 then return "now" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    return math.floor(d / 86400) .. " days ago"
end

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function tip(owner, lines)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for i, l in ipairs(type(lines) == "function" and lines() or lines) do
            if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- A table: headers you can click, rows of cells
---------------------------------------------------------------------------

local function makeTable(parent, nrows, width, onHeader)
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
        r:SetSize(width, ROW_H)
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
-- Menus: whose items, where, and how they're valued
---------------------------------------------------------------------------

local function menu(owner, fn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Print("Menus need a newer client.")
        return
    end
    MenuUtil.CreateContextMenu(owner, fn)
end

local function whoText(who) return who and ns.CharText(who) or "All characters" end

function ns.CharMenu(owner)
    menu(owner, function(_, root)
        root:CreateTitle("Whose items")
        root:CreateRadio("All characters", function() return filter.who == nil end, function() ns.Filter("who", nil) end)
        for _, who in ipairs(ns.Known()) do
            root:CreateRadio(ns.CharText(who), function() return filter.who == who end, function() ns.Filter("who", who) end)
        end
    end)
end

function ns.PlaceMenu(owner)
    menu(owner, function(_, root)
        root:CreateTitle("Where")
        root:CreateRadio("Everywhere", function() return filter.place == nil end, function() ns.Filter("place", nil) end)
        for _, p in ipairs(ns.PLACES) do
            root:CreateRadio(ns.PLACE_NAMES[p], function() return filter.place == p end, function() ns.Filter("place", p) end)
        end
    end)
end

function ns.PriceMenu(owner)
    menu(owner, function(_, root)
        root:CreateTitle("Value items at")
        root:CreateRadio("Market price (Deep Scan)", function() return ns.db.ui.price == "market" end,
            function() ns.db.ui.price = "market"; ns.Snapshot(); ns.Refresh() end)
        root:CreateRadio("Lowest buyout", function() return ns.db.ui.price == "lowest" end,
            function() ns.db.ui.price = "lowest"; ns.Snapshot(); ns.Refresh() end)
        root:CreateCheckbox("No auction price: use the vendor price", function() return ns.db.ui.vendor end,
            function() ns.db.ui.vendor = not ns.db.ui.vendor; ns.Snapshot(); ns.Refresh() end)
    end)
end

StaticPopupDialogs.INVENTORYKING_FORGET = {
    text = "Forget %s? Their items, gold and history go. They come back next time you log in on them.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, who) ns.Forget(who) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.CharacterMenu(owner, who)
    menu(owner, function(_, root)
        root:CreateTitle(ns.CharText(who))
        root:CreateButton("Show their items", function() ns.ShowItems({ who = who }) end)
        root:CreateButton("Forget this character", function()
            StaticPopup_Show("INVENTORYKING_FORGET", ns.Short(who), nil, who)
        end)
    end)
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------

local CHAR_COLS = {
    { key = "who", label = "Character", w = 160 },
    { key = "level", label = "Level", w = 45, justify = "RIGHT" },
    { key = "gold", label = "Gold", w = 115, justify = "RIGHT", tip = "Gold on the character, as of when you last played them." },
    { key = "mail", label = "Mailbox", w = 105, justify = "RIGHT", tip = "Gold waiting in their mailbox (auction sales and other mail), as of their last visit to it." },
    { key = "assets", label = "Items worth", w = 115, justify = "RIGHT", tip = "Everything they hold that can be sold, at today's prices." },
    { key = "worth", label = "Net worth", w = 115, justify = "RIGHT" },
    { key = "share", label = "Share", w = 55, justify = "RIGHT", tip = "Of your total net worth." },
    { key = "seen", label = "Last seen", w = 90, justify = "RIGHT" },
    { key = "bank", label = "Bank", w = 66, justify = "RIGHT", tip = "When their bank was last opened. Until then it isn't counted." },
}

local function refreshOverview()
    local w = ns.NetWorth()
    tiles.total:SetText(ns.Money(w.total))
    tiles.gold:SetText(ns.Money(w.gold))
    tiles.mail:SetText(ns.Money(w.mail))
    tiles.assets:SetText(ns.Money(w.assets))
    tiles.items:SetText(tostring(w.items))

    local days = ns.Series(DAYS)
    local top = 1
    for _, d in ipairs(days) do top = math.max(top, d.total) end
    for i, d in ipairs(days) do
        local b = bars[i]
        b.day = d
        local gh = d.gold / top * 100
        local ah = d.assets / top * 100
        b.gold:SetHeight(math.max(gh, 0.5))
        b.assets:SetHeight(math.max(ah, 0.5))
        b.gold:SetShown(d.gold > 0)
        b.assets:SetShown(d.assets > 0)
    end

    local list = ns.Characters()
    for i, r in ipairs(charTable.rows) do
        local c = list[i]
        if c then
            r.who = c.who
            local cells, isBank = r.cells, c.who == ns.WARBAND
            cells[1]:SetText(ns.CharText(c.who))
            cells[2]:SetText(c.level and tostring(c.level) or grey("-"))
            cells[3]:SetText(isBank and grey("-") or ns.Money(c.gold))
            cells[4]:SetText(c.mail > 0 and ns.Money(c.mail) or grey("-"))
            cells[5]:SetText(c.assets > 0 and ns.Money(c.assets) or grey("-"))
            cells[6]:SetText(ns.Money(c.worth))
            cells[7]:SetText(w.total > 0 and string.format("%.0f%%", c.worth / w.total * 100) or grey("-"))
            cells[8]:SetText(isBank and grey("-") or ago(c.seen))
            cells[9]:SetText(c.bankSeen and ago(c.bankSeen) or "|cffff8040not yet|r")
            r:Show()
        else
            r.who = nil
            r:Hide()
        end
    end
    overview.empty:SetText(#list == 0 and "Nothing yet: log in on each of your characters, and open their bank once." or "")
    local missing = 0
    for _, c in ipairs(list) do if c.who ~= ns.WARBAND and not c.bankSeen then missing = missing + 1 end end
    footer:SetText(w.chars .. " characters.  Click one for their items, right-click to forget them."
        .. (missing > 0 and ("  |cffff8040" .. missing .. " bank" .. (missing == 1 and "" or "s") .. " not seen yet: open it once on that character.|r") or ""))
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

local ITEM_COLS = {
    { key = "name", label = "Item", w = 200 },
    { key = "bags", label = "Bags", w = 48, justify = "RIGHT" },
    { key = "bank", label = "Bank", w = 48, justify = "RIGHT", tip = "As of when each bank was last opened (and the warband bank)." },
    { key = "mail", label = "Mail", w = 48, justify = "RIGHT", tip = "Attached to mail in the mailbox." },
    { key = "ah", label = "On AH", w = 48, justify = "RIGHT", tip = "Your auctions still up, as of when you last looked." },
    { key = "total", label = "Total", w = 50, justify = "RIGHT" },
    { key = "chars", label = "Chars", w = 44, justify = "RIGHT", tip = "How many characters hold it. Hover an item for who." },
    { key = "each", label = "Each", w = 90, justify = "RIGHT", tip = "Scanner King's price. Grey: a vendor price, as the auction house has none." },
    { key = "value", label = "Worth", w = 100, justify = "RIGHT" },
}

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end

local function sorter(a, b)
    local k = sort.key
    local x, y
    if k == "name" then x, y = a.name or "", b.name or ""
    elseif k == "chars" then x, y = count(a.chars), count(b.chars)
    else x, y = a[k], b[k] end
    if x == nil or y == nil then
        if x ~= nil or y ~= nil then return x ~= nil end
        return (a.name or "") < (b.name or "")
    end
    if x == y then return (a.name or "") < (b.name or "") end
    if sort.desc then return x > y end
    return x < y
end

local function itemCell(r, key)
    if key == "name" then return ns.ItemText(r.item) end
    if key == "chars" then return tostring(count(r.chars)) end
    if key == "each" or key == "value" then
        local v = r[key]
        if not v then return grey("no price") end
        return r.src == "vendor" and (GREY .. "(vendor) |r" .. ns.Money(v)) or ns.Money(v)
    end
    local v = r[key]
    if key == "total" then return tostring(v) end
    return v and v > 0 and tostring(v) or grey("-")
end

-- The sidebar: All items, the categories with something in them (the picked one opened up),
-- then Mail King's strategies.
local function sideEntries(res)
    local out = { { label = "All items", value = res.allValue, count = res.allCount, pick = {} } }
    for _, cls in ipairs(ns.CLASS_ORDER) do
        local c = res.cats[cls]
        if c then
            table.insert(out, { label = ns.ClassName(cls), value = c.value, count = c.count, pick = { cls = cls } })
            if filter.cls == cls then
                local subs = {}
                for sub, s in pairs(c.subs) do table.insert(subs, { sub = sub, s = s }) end
                table.sort(subs, function(a, b) return a.s.value > b.s.value end)
                for _, s in ipairs(subs) do
                    table.insert(out, { label = "   " .. ns.SubclassName(cls, s.sub), value = s.s.value, count = s.s.count,
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
        table.sort(strategies, function(a, b) return a.s.value > b.s.value end)
        table.insert(out, { header = "Mail King strategies" })
        for _, s in ipairs(strategies) do
            table.insert(out, { label = s.name, value = s.s.value, count = s.s.count, pick = { strategy = s.name } })
        end
    end
    return out
end

local function picked(p)
    return p and (p.cls == filter.cls and p.sub == filter.sub and p.strategy == filter.strategy)
end

local function refreshSide(res)
    local list = sideEntries(res)
    sideOffset = math.max(0, math.min(sideOffset, #list - SIDE_ROWS))
    for i, b in ipairs(side.buttons) do
        local e = list[i + sideOffset]
        b.entry = e
        if e then
            if e.header then
                b.label:SetText("|cffffd100" .. e.header .. "|r")
                b.value:SetText("")
            else
                b.label:SetText(picked(e.pick) and ("|cff60c0ff" .. e.label .. "|r") or e.label)
                b.value:SetText(e.value > 0 and ns.Gold(e.value) or grey(tostring(e.count)))
            end
            if picked(e.pick) then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
        else
            b:Hide()
        end
    end
end

local function refreshItems()
    local res = ns.Items(filter)
    -- totals for "All items" under the same who / where / search
    local all = 0
    for _, c in pairs(res.cats) do all = all + c.value end
    local allCount = 0
    for _, c in pairs(res.cats) do allCount = allCount + c.count end
    res.allValue, res.allCount = all, allCount
    refreshSide(res)

    current = res.rows
    table.sort(current, sorter)
    itemTable.layout(ITEM_COLS)
    offset = math.max(0, math.min(offset, #current - ROWS))
    for i, r in ipairs(itemTable.rows) do
        local e = current[i + offset]
        r.row = e
        if e then
            for c, col in ipairs(ITEM_COLS) do r.cells[c]:SetText(itemCell(e, col.key)) end
            r:Show()
        else
            r:Hide()
        end
    end
    for i, col in ipairs(ITEM_COLS) do
        itemTable.headers[i]:SetText(col.label .. (sort.key == col.key and (sort.desc and " v" or " ^") or ""))
    end
    charBtn:SetText(whoText(filter.who))
    placeBtn:SetText(filter.place and ns.PLACE_NAMES[filter.place] or "Everywhere")
    itemsView.empty:SetText(#current == 0 and "Nothing here. Try All items, all characters, everywhere, or clear the search." or "")
    footer:SetText((#current > 0 and ((offset + 1) .. "-" .. (offset + math.min(#current, ROWS)) .. " of " .. #current .. " items.  ") or "")
        .. "Worth " .. ns.Money(res.value) .. "."
        .. (res.unpriced > 0 and ("  " .. res.unpriced .. " with no price.") or "")
        .. "  Shift-click to link.")
end

local function rowScripts(r)
    r:SetScript("OnEnter", function(self)
        local e = self.row
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.item) end
        GameTooltip:AddLine(" ")
        local list = {}
        for who, n in pairs(e.chars) do table.insert(list, { who, n }) end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for _, c in ipairs(list) do
            local bits = {}
            for _, p in ipairs(ns.PLACES) do
                local n = e.where[c[1]][p]
                if n then table.insert(bits, ns.PLACE_NAMES[p]:lower():gsub("on the auction house", "on AH") .. " " .. n) end
            end
            GameTooltip:AddDoubleLine(ns.CharText(c[1]) .. "  " .. c[2], table.concat(bits, ", "), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        if e.strategy then GameTooltip:AddLine("Mail King strategy: " .. e.strategy, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        local e = self.row
        if e and IsShiftKeyDown and IsShiftKeyDown() then
            local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local link = get and select(2, get(e.item))
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end
    end)
end

---------------------------------------------------------------------------
-- Refreshing, tabs and filters
---------------------------------------------------------------------------

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    for _, b in ipairs(tabButtons) do if b.key == tab then b:LockHighlight() else b:UnlockHighlight() end end
    priceBtn:SetText(ns.db.ui.price == "lowest" and "Valued at: lowest buyout" or "Valued at: market price")
    overview:SetShown(tab == "overview")
    itemsView:SetShown(tab == "items")
    if tab == "overview" then refreshOverview() else refreshItems() end
end

function ns.SelectTab(key)
    tab, offset = key, 0
    ns.Refresh()
end

-- Change one filter: who, place, search, or the category (cls/sub/strategy).
function ns.Filter(key, value)
    filter[key] = value
    offset = 0
    ns.Refresh()
end

-- The Items tab with these filters (the rest cleared).
function ns.ShowItems(f)
    filter = f or {}
    if searchBox then searchBox:SetText(filter.search or "") end
    ns.Toggle(true)
    ns.SelectTab("items")
end

function ns.GetFilter() return filter end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function create()
    frame = CreateFrame("Frame", "InventoryKingFrame", UIParent, "BackdropTemplate")
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
    if UISpecialFrames then table.insert(UISpecialFrames, "InventoryKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Inventory King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    tabButtons = {}
    local prev = title
    for _, t in ipairs({ { "overview", "Overview" }, { "items", "Items" } }) do
        local b = button(frame, t[2], 90, function() ns.SelectTab(t[1]) end)
        b.key = t[1]
        b:SetPoint("LEFT", prev, "RIGHT", prev == title and 16 or 2, 0)
        table.insert(tabButtons, b)
        prev = b
    end
    priceBtn = button(frame, "Valued at: market price", 170, function(self) ns.PriceMenu(self) end)
    priceBtn:SetPoint("TOPRIGHT", -36, -12)
    tip(priceBtn, { "How items are valued", "Scanner King's market price (from a Deep Scan) or the lowest buyout. "
        .. "Items the auction house has no price for can count at what a vendor pays. Click to change." })

    -- Overview
    overview = CreateFrame("Frame", nil, frame)
    overview:SetPoint("TOPLEFT", 16, -44)
    overview:SetPoint("BOTTOMRIGHT", -16, 36)
    tiles = {}
    for i, t in ipairs({ { "total", "Net worth", "Gold on every character, gold in their mailboxes, and what all your items are worth." },
                         { "gold", "Gold on characters" }, { "mail", "Gold in mailboxes", "Not collected yet: sales and other mail." },
                         { "assets", "Items worth", "Everything you own that can be sold, at today's prices." },
                         { "items", "Items" } }) do
        local holder = CreateFrame("Frame", nil, overview)
        holder:SetPoint("TOPLEFT", (i - 1) * 172, 0)
        holder:SetSize(168, 34)
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 0, 0)
        label:SetText(t[2])
        local v = holder:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormalLarge" or "GameFontHighlight")
        v:SetPoint("TOPLEFT", 0, -14)
        tiles[t[1]] = v
        if t[3] then holder:EnableMouse(true); tip(holder, { t[2], t[3] }) end
    end

    local barsLabel = overview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barsLabel:SetPoint("TOPLEFT", 0, -44)
    barsLabel:SetText("Net worth, last " .. DAYS .. " days:  |cffffd700gold|r  |cff4090ffitems|r")
    bars = {}
    for i = 1, DAYS do
        local b = CreateFrame("Frame", nil, overview)
        b:SetSize(26, 102)
        b:SetPoint("TOPLEFT", (i - 1) * 28, -60)
        local axis = b:CreateTexture(nil, "BACKGROUND")
        axis:SetColorTexture(1, 1, 1, 0.15)
        axis:SetHeight(1)
        axis:SetPoint("BOTTOMLEFT")
        axis:SetPoint("BOTTOMRIGHT")
        b.gold = b:CreateTexture(nil, "ARTWORK")
        b.gold:SetWidth(22)
        b.gold:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
        b.gold:SetColorTexture(1, 0.84, 0, 0.85)
        b.assets = b:CreateTexture(nil, "ARTWORK")
        b.assets:SetWidth(22)
        b.assets:SetPoint("BOTTOM", b.gold, "TOP", 0, 0)
        b.assets:SetColorTexture(0.25, 0.56, 1, 0.85)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            local d = self.day
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(d.label)
            if not d.known then
                GameTooltip:AddLine("Before Inventory King started counting.", 0.6, 0.6, 0.6)
            else
                GameTooltip:AddDoubleLine("Gold", ns.Money(d.gold), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Items", ns.Money(d.assets), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Net worth", ns.Money(d.total), 1, 0.82, 0, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bars[i] = b
    end

    local charHolder = CreateFrame("Frame", nil, overview)
    charHolder:SetPoint("TOPLEFT", 0, -172)
    charHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    charTable = makeTable(charHolder, CHAR_ROWS, WIDTH - 40)
    charTable.layout(CHAR_COLS)
    for _, r in ipairs(charTable.rows) do
        r:SetScript("OnClick", function(self, which)
            if not self.who then return end
            if which == "RightButton" then ns.CharacterMenu(self, self.who) else ns.ShowItems({ who = self.who }) end
        end)
        tip(r, function()
            return { ns.CharText(r.who or "?"), "Click: their items.  Right-click: forget them." }
        end)
    end
    overview.empty = overview:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    overview.empty:SetPoint("TOP", charHolder, "TOP", 0, -50)
    overview.empty:SetWidth(600)

    -- Items
    itemsView = CreateFrame("Frame", nil, frame)
    itemsView:SetPoint("TOPLEFT", 16, -42)
    itemsView:SetPoint("BOTTOMRIGHT", -16, 36)

    charBtn = button(itemsView, "All characters", 140, function(self) ns.CharMenu(self) end)
    charBtn:SetPoint("TOPLEFT", SIDE_W + 8, 0)
    tip(charBtn, { "Whose items", "Everyone's (and the warband bank), or one character's. Click to pick." })
    placeBtn = button(itemsView, "Everywhere", 120, function(self) ns.PlaceMenu(self) end)
    placeBtn:SetPoint("LEFT", charBtn, "RIGHT", 4, 0)
    tip(placeBtn, { "Where", "Bags, bank, mailbox, auction house, or everywhere. Click to pick." })
    searchBox = CreateFrame("EditBox", "InventoryKingSearch", itemsView, "InputBoxTemplate")
    searchBox:SetSize(170, 20)
    searchBox:SetPoint("LEFT", placeBtn, "RIGHT", 12, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text ~= (filter.search or "") then ns.Filter("search", text ~= "" and text or nil) end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local searchLabel = itemsView:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchLabel:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    searchLabel:SetText("search")

    -- the sidebar
    side = CreateFrame("Frame", nil, itemsView)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetSize(SIDE_W, SIDE_ROWS * ROW_H)
    side.buttons = {}
    for i = 1, SIDE_ROWS do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE_W - 4, ROW_H)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("LEFT", 4, 0)
        b.label:SetJustifyH("LEFT")
        b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.value:SetPoint("RIGHT", -4, 0)
        b.value:SetJustifyH("RIGHT")
        b:SetScript("OnClick", function(self)
            local e = self.entry
            if not e or e.header then return end
            -- clicking the open category again closes it
            if e.pick.cls and not e.pick.sub and filter.cls == e.pick.cls and not filter.sub then e = { pick = {} } end
            filter.cls, filter.sub, filter.strategy = e.pick.cls, e.pick.sub, e.pick.strategy
            offset = 0
            ns.Refresh()
        end)
        side.buttons[i] = b
    end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        sideOffset = math.max(0, sideOffset - delta * 3)
        ns.Refresh()
    end)

    local tableHolder = CreateFrame("Frame", nil, itemsView)
    tableHolder:SetPoint("TOPLEFT", SIDE_W + 8, -26)
    tableHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    itemTable = makeTable(tableHolder, ROWS, WIDTH - SIDE_W - 48, function(key)
        if sort.key == key then sort.desc = not sort.desc else sort.key, sort.desc = key, key ~= "name" end
        offset = 0
        ns.Refresh()
    end)
    for _, r in ipairs(itemTable.rows) do rowScripts(r) end
    itemsView.empty = itemsView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    itemsView.empty:SetPoint("TOP", tableHolder, "TOP", 0, -60)
    tableHolder:EnableMouseWheel(true)
    tableHolder:SetScript("OnMouseWheel", function(_, delta)
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
-- Export: items and characters as comma-separated text, for a spreadsheet
---------------------------------------------------------------------------

local exportFrame, exportBox

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

function ns.Export()
    if not ns.db then return end
    local text, n = ns.ExportText()
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "InventoryKingExport", UIParent, "BackdropTemplate")
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
        if UISpecialFrames then table.insert(UISpecialFrames, "InventoryKingExport") end
        local t = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 16, -14)
        t:SetText("Inventory King export: press Ctrl+A, then Ctrl+C, and paste into a spreadsheet")
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
    ns.Print("Exported " .. n .. " items and your characters.")
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db or not Minimap then return end
    if not mini then
        mini = CreateFrame("Button", "InventoryKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
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
            local w = ns.NetWorth()
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Inventory King")
            GameTooltip:AddDoubleLine("Net worth", ns.Money(w.total), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gold (with mailboxes)", ns.Money(w.gold + w.mail), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Items worth", ns.Money(w.assets), 1, 1, 1, 1, 1, 1)
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
