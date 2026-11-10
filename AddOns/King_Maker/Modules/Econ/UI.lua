local _, KM = ...
local ns = KM.Module("Econ")
local UI = KM.UI
local C = UI.C

-- The Price History page of the King Maker window (Auction House > Price History).
--   Left:  Favorites, Deals, All items, then every item category on the auction house. Click a category to
--          open its subcategories. The wheel scrolls the list.
--   Right: a search box and Ask guild, then the items in that tab, sortable by any column. Click an item for
--          its page (Item.lua), which takes the list's place; Back and the arrows there move you around.
-- Also here: the crown's quick action and tooltip line, and the Settings section.

local SIDE_W, SIDE_H, SIDE_ROWS = 160, 21, 25
local DEAL_DISCOUNT = -0.2       -- Deals: at least 20% under the 30-day average
local DEAL_MIN_DAYS = 5          -- ...with at least 5 days of history
local DEAL_FRESH = 2 * 86400     -- ...priced in the last 2 days
local SYNC_LIMIT = 400           -- more items than this without numbers: work them out in the background

local page, search, footer, listView, sideButtons, tbl
local tab, sub, sideOffset = "fav", nil, 0
local list = {}
local view = "list"
local warming = false
local reopened = true            -- the page was (re)opened: favorites first, or every item when there are none

---------------------------------------------------------------------------
-- What's in each tab
---------------------------------------------------------------------------

local function isDeal(s)
    return s and s.vs30 and s.vs30 <= DEAL_DISCOUNT and s.days >= DEAL_MIN_DAYS
        and s.priced and ns.Now() - s.priced <= DEAL_FRESH
end
ns.IsDeal = isDeal

local function inTab(id)
    if tab == "fav" then return ns.db.fav[id] end
    if tab == "deals" then return isDeal((ns.CachedStats(id))) end
    if tab == "all" then return true end
    local cls, sc = ns.ClassOf(id)
    return cls == tab and (sub == nil or sc == sub)
end

local function sortValue(e, key)
    if key == "name" then return e.name end
    local s = e.s
    if not s then return nil end
    if key == "seen" then return s.seen end
    if key == "listed" then return s.listed end
    return s[key]
end

local function searchText() return search and search:GetText() and search:GetText():lower() or "" end

local function build()
    wipe(list)
    local text = searchText()
    local candidates = {}
    for id in pairs(ns.db.items) do candidates[id] = true end
    for id in pairs(ns.db.fav) do candidates[id] = true end
    -- Numbers for everything we're about to show: right away if there are few
    -- to work out, otherwise in the background and the list fills in after.
    local missing = {}
    for id in pairs(candidates) do
        local _, miss = ns.CachedStats(id)
        if miss and (text ~= "" or tab == "deals" or inTab(id)) then table.insert(missing, id) end
    end
    if #missing <= SYNC_LIMIT then
        for _, id in ipairs(missing) do ns.Stats(id) end
    elseif not warming then
        warming = true
        ns.Background(missing, function(id) ns.Stats(id) end, function() warming = false; ns.Refresh() end)
    end
    local stats = function(id) return (ns.CachedStats(id)) end
    for id in pairs(candidates) do
        if text ~= "" then
            local name = ns.Info(id).name
            if name and name:lower():find(text, 1, true) then
                table.insert(list, { id = id, name = name, s = stats(id) })
            end
        elseif inTab(id) then
            table.insert(list, { id = id, name = ns.Name(id), s = stats(id) })
        end
    end
    local sortBy, sortDesc = tbl.sortKey or "market", tbl.sortDesc
    table.sort(list, function(a, b)
        local x, y = sortValue(a, sortBy), sortValue(b, sortBy)
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end -- blanks last either way
            return a.name < b.name
        end
        if x == y then return a.name < b.name end
        if sortDesc then return x > y end
        return x < y
    end)
end

function ns.CurrentList() return list end

---------------------------------------------------------------------------
-- The left side: tabs and categories
---------------------------------------------------------------------------

local function sideEntries()
    local entries = {
        { key = "fav", label = "|T" .. ns.STAR .. ":14|t Favorites" },
        { key = "deals", label = "Deals" },
        { key = "all", label = "All items" },
    }
    local count, subs = {}, {}
    for id in pairs(ns.db.items) do
        local cls, sc = ns.ClassOf(id)
        count[cls] = (count[cls] or 0) + 1
        if cls == tab then subs[sc] = (subs[sc] or 0) + 1 end
    end
    local order, listed = {}, {}
    for _, cls in ipairs(ns.CLASS_ORDER) do
        if count[cls] then table.insert(order, cls); listed[cls] = true end
    end
    for cls in pairs(count) do if not listed[cls] then table.insert(order, cls) end end
    for _, cls in ipairs(order) do
        table.insert(entries, { key = cls, label = ns.ClassName(cls), count = count[cls] })
        if cls == tab then
            local ss = {}
            for sc in pairs(subs) do table.insert(ss, sc) end
            table.sort(ss, function(a, b) return ns.SubclassName(cls, a) < ns.SubclassName(cls, b) end)
            if #ss > 1 then
                for _, sc in ipairs(ss) do
                    table.insert(entries, { key = cls, sub = sc, indent = true,
                        label = ns.SubclassName(cls, sc), count = subs[sc] })
                end
            end
        end
    end
    return entries
end

local function refreshSide()
    local entries = sideEntries()
    sideOffset = math.max(0, math.min(sideOffset, #entries - SIDE_ROWS))
    local searching = searchText() ~= ""
    for i, b in ipairs(sideButtons) do
        local e = entries[i + sideOffset]
        if e then
            b.entry = e
            b:SetLabel(e.label)
            b.count:SetText(e.count and tostring(e.count) or "")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", e.indent and 20 or 6, -6 - (i - 1) * SIDE_H)
            b:SetWidth(SIDE_W - 12 - (e.indent and 14 or 0))
            b.label:SetTextColor(e.indent and C.muted[1] or C.text[1], e.indent and C.muted[2] or C.text[2], e.indent and C.muted[3] or C.text[3])
            b:SetActive(e.key == tab and e.sub == sub and not searching)
            b:Show()
        else
            b.entry = nil
            b:Hide()
        end
    end
end

function ns.SelectTab(key, subKey)
    tab, sub = key, subKey
    tbl.offset = 0
    search:SetText("")
    search:ClearFocus()
    if key == "deals" then tbl:SetSort("vs30", false)
    elseif key == "fav" then tbl:SetSort("name", false)
    elseif tbl.sortKey == "vs30" and not tbl.sortDesc then tbl:SetSort("market", true) end
    ns.ShowList()
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function emptyText()
    if searchText() ~= "" then return "Nothing matches. Names load as you browse; try again in a moment." end
    if not next(ns.db.items) then return "No history yet. Click Scan at the auction house to start." end
    if tab == "fav" then return "No favorites yet. Click the star next to an item, or on its page." end
    if tab == "deals" and warming then return "Working out trends..." end
    if tab == "deals" then return "No deals right now: nothing is 20% under its 30-day average with 5+ days of history." end
    return "Nothing here yet."
end

local function linkFor(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local _, link = get(id)
    return link
end
ns.LinkFor = linkFor

local DASH = "|cff808080-|r"

local function fillRow(r, e, cells)
    local s = e.s or {}
    if not r.star then
        r.star = CreateFrame("Button", nil, r)
        r.star:SetSize(14, 14)
        r.star:SetPoint("LEFT", 29, 0)
        r.star.tex = r.star:CreateTexture(nil, "ARTWORK")
        r.star.tex:SetAllPoints()
        r.star.tex:SetTexture(ns.STAR)
        r.star:SetScript("OnClick", function()
            if r.data then UI.Click(); ns.SetFavorite(r.data.id, not ns.db.fav[r.data.id]) end
        end)
    end
    r.star.tex:SetAlpha(ns.db.fav[e.id] and 1 or 0.15)
    if r.icon then r.icon:SetTexture(ns.Info(e.id).icon) end
    cells.name:SetText(ns.ColoredName(e.id))
    cells.market:SetText(ns.Money(s.market))
    cells.vs30:SetText(ns.Percent(s.vs30, true))
    cells.trend7:SetText(ns.Percent(s.trend7))
    cells.listed:SetText(s.listed and KM.Commas(math.floor(s.listed + 0.5)) or DASH)
    cells.supply:SetText(ns.Percent(s.supply))
    cells.seen:SetText(s.seen and (UI.Hex(C.muted) .. ns.Age(s.seen) .. "|r") or "")
end

local function footerText()
    local tracked = 0
    for _ in pairs(ns.db.items) do tracked = tracked + 1 end
    local shownN = math.min(#list, tbl.visible or #list)
    footer:SetText((warming and (UI.Hex(C.warn) .. "Working out trends...|r  ") or "")
        .. (#list > 0 and ((tbl.offset + 1) .. "-" .. (tbl.offset + shownN) .. " of " .. #list .. ".  ") or "")
        .. tracked .. " items tracked.  Last full scan: " .. ns.Age(ns.db.lastDeep) .. ".")
end

local function refreshList()
    build()
    tbl.emptyText = emptyText()
    tbl:SetRows(list, fillRow)
end

local function indexOf(e)
    for i, x in ipairs(list) do if x == e then return i end end
end

local function refresh()
    if not ns.db or not page then return end
    if reopened then
        reopened = false
        -- Favorites first; with none yet, every item.
        if tab == "fav" and not next(ns.db.fav) and next(ns.db.items) then tab = "all"; tbl:SetSort("market", true) end
    end
    refreshSide()
    if view == "list" then refreshList() elseif ns.RefreshItem then ns.RefreshItem() end
end

-- Redraws the page if it's the one showing (scans, guild prices and favorites call this).
function ns.Refresh() KM.Refresh("history") end

function ns.ShowList()
    if not page then return end
    view = "list"
    if ns.HideItem then ns.HideItem() end
    listView:Show()
    ns.Refresh()
end

function ns.ShowItem(id, index)
    if not page then return end
    view = "item"
    listView:Hide()
    ns.OpenItem(id, index)
    refreshSide()
end

-- Opens (true), closes (false) or toggles (nil) the page.
function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("history") end
    if show then
        if not KM.IsShown("history") then reopened = true end
        KM.Show("history")
    elseif KM.IsShown("history") then
        KM.Toggle(false)
    end
end

-- Asks guildmates (through the Scanner module) for their latest prices of these items.
function ns.AskGuild(ids)
    if not (ScannerKing and ScannerKing.RequestPrices) then
        KM.Print(ns, "Asking the guild needs the Scanner module (Scanner King 1.5 or newer).")
        return
    end
    local n, msgs = ScannerKing.RequestPrices(ids)
    if not n then return end -- Scanner said why (sharing off, or no guild)
    if n == 0 then
        KM.Print(ns, "Nothing to ask: you scanned " .. (#ids == 1 and "it" or "all of these") .. " yourself in the last hour.")
    else
        KM.Print(ns, "Asked the guild about " .. n .. " item(s) in " .. msgs .. " message(s). Answers arrive over the next minute or so.")
    end
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function sideButton(parent)
    local b = UI.Button(parent, "", SIDE_W - 12, SIDE_H - 2, function(self)
        if self.entry then ns.SelectTab(self.entry.key, self.entry.sub) end
    end, "ghost")
    b.label:SetJustifyH("LEFT")
    -- Name on the left (cut short if it's long), count on the right, both inside the button.
    local function inset(dx, dy)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 6 + dx, dy)
        b.label:SetPoint("RIGHT", -34 + dx, dy)
    end
    inset(0, 0)
    b:SetScript("OnMouseDown", function() inset(1, -1) end)
    b:SetScript("OnMouseUp", function() inset(0, 0) end)
    b.count = UI.Text(b, 10, C.dim, "RIGHT")
    b.count:SetPoint("RIGHT", -6, 0)
    return b
end

local function buildPage(c)
    page = c

    local side = CreateFrame("Frame", nil, c)
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
        refreshSide()
    end)

    local right = CreateFrame("Frame", nil, c)
    right:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    listView = CreateFrame("Frame", nil, right)
    listView:SetAllPoints(right)

    search = UI.EditBox(listView, 260, 24, "Search every item", function(_, user)
        if not user then return end
        tbl.offset = 0
        if view ~= "list" then ns.ShowList() else ns.Refresh() end
    end)
    search:SetPoint("TOPLEFT", 0, 0)

    local ask = UI.Button(listView, "Ask guild", 110, 24, function()
        local ids = {}
        for _, e in ipairs(list) do table.insert(ids, e.id) end
        ns.AskGuild(ids)
    end)
    ask:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(ask, function(tt)
        tt:AddLine("Ask guild")
        tt:AddLine("Ask guildmates running King Maker (or Scanner King) for their latest prices of the " .. #list
            .. " item(s) in this list" .. (#list > 2000 and " (the first 2000)" or "") .. ". Answers fill in prices and history.", 1, 1, 1, true)
        tt:AddLine("Items you scanned yourself in the last hour are skipped. Asking for "
            .. math.min(#list, 2000) .. " items takes about " .. math.ceil(math.min(#list, 2000) / 100)
            .. " message(s); answers about one per 25 items.", 0.7, 0.7, 0.7, true)
    end)

    local function col(key, label, w, justify, tip)
        return { key = key, label = label, w = w, justify = justify, tip = tip, desc = key ~= "name",
                 sort = label ~= "" and function(e) return sortValue(e, key) end or nil }
    end
    local cols = {
        col("fav", "", 20),
        col("name", "Item", 160),
        col("market", "Market", 92, "RIGHT"),
        col("vs30", "vs 30d", 56, "RIGHT", "Market price now compared with its 30-day average. Below zero: cheaper than usual."),
        col("trend7", "7d trend", 58, "RIGHT", "Average market price this week compared with the week before."),
        col("listed", "Listed", 52, "RIGHT", "Units on the auction house at the last scan."),
        col("supply", "Supply", 56, "RIGHT", "Listed now compared with the 30-day average. Below zero: drying up."),
        col("seen", "Scanned", 0),
    }
    tbl = UI.Table(listView, cols, 20, {
        icon = true, noSort = true, fontSize = 11,
        onSort = function() tbl.offset = 0; refreshList() end,
        onClick = function(e, which)
            if which == "RightButton" then
                ns.SetFavorite(e.id, not ns.db.fav[e.id])
            elseif IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                local link = linkFor(e.id)
                if link then ChatEdit_InsertLink(link) end
            else
                ns.ShowItem(e.id, indexOf(e))
            end
        end,
        onEnter = function(r)
            if not r.data then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, r.data.id) end
            GameTooltip:AddLine("Click: price and supply history.  Right-click: favorite.  Shift-click: link.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, -34)
    tbl:SetPoint("BOTTOMRIGHT", 0, 22)
    tbl:SetSort("market", true)
    tbl.fill = fillRow
    tbl.onRedraw = footerText
    ns.table = tbl

    footer = UI.Text(listView, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", listView, "RIGHT", 0, 0)
    ns.footer = footer

    ns.CreateItemView(right)
end

KM.RegisterPage({
    id = "history", group = "ah", label = "Price History", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", order = 20,
    title = "Price History",
    subtitle = "Every scan kept: price and supply over days, weeks and months. Deals are 20% under their 30-day average.",
    build = buildPage, refresh = refresh, hide = function() reopened = true end,
})

---------------------------------------------------------------------------
-- The crown and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "econ-history", label = "Price History", order = 14, func = function() ns.Toggle(true) end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local n = 0
    for _ in pairs(ns.db.items) do n = n + 1 end
    tt:AddLine(KM.Commas(n) .. " items with price history.", 1, 1, 1)
end)

KM.RegisterSettings({ id = "econ", label = "Econ", order = 11, rows = {
    { type = "header", label = "Tooltips" },
    { type = "check", label = "Averages and trend in item tooltips", tip = "The 30-day average, today against it and the weekly trend, under the prices.",
      get = function() return ns.db.ui.tooltip end, set = function(v) ns.db.ui.tooltip = v end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/ek   open Price History\n/ek item [link]   an item's page\n/ek fav [link]   add or remove a favorite\n"
        .. "/ek status   how much history you have\n/ek tooltip on|off   lines in item tooltips" },
} })
