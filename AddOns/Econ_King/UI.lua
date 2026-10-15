local _, ns = ...

-- The Econ King window.
--   Left:  Favorites, Deals, All items, then every item category on the
--          auction house. Click a category to open its subcategories.
--   Right: the items in that tab, sortable by any column. Click an item for its
--          page (Item.lua); Back and the arrows there move you around.

local WIDTH, HEIGHT = 860, 580
local SIDE_W, SIDE_ROWS, SIDE_H = 160, 24, 20
local ROWS, ROW_H = 24, 18
local DEAL_DISCOUNT = -0.2       -- Deals: at least 20% under the 30-day average
local DEAL_MIN_DAYS = 5          -- ...with at least 5 days of history
local DEAL_FRESH = 2 * 86400     -- ...priced in the last 2 days

local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
ns.STAR = STAR

local frame, search, footer, listView, sideButtons, rows, headers
local tab, sub, sortBy, sortDesc, offset, sideOffset = "fav", nil, "market", true, 0, 0
local list = {}
local view = "list"
local SYNC_LIMIT = 400          -- more items than this without numbers: work them out in the background
local warming = false

local COLS = {
    { key = "fav", label = "", w = 20 },
    { key = "name", label = "Item", w = 206, justify = "LEFT" },
    { key = "market", label = "Market", w = 96, justify = "RIGHT" },
    { key = "vs30", label = "vs 30d", w = 58, justify = "RIGHT", tip = "Market price now compared with its 30-day average. Below zero: cheaper than usual." },
    { key = "trend7", label = "7d trend", w = 60, justify = "RIGHT", tip = "Average market price this week compared with the week before." },
    { key = "listed", label = "Listed", w = 56, justify = "RIGHT", tip = "Units on the auction house at the last scan." },
    { key = "supply", label = "Supply", w = 62, justify = "RIGHT", tip = "Listed now compared with the 30-day average. Below zero: drying up." },
    { key = "seen", label = "Scanned", w = 90, justify = "LEFT" },
}

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

local function build()
    wipe(list)
    local text = search and search:GetText() and search:GetText():lower() or ""
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
        { key = "fav", label = "|T" .. STAR .. ":14|t Favorites" },
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
    for i, b in ipairs(sideButtons) do
        local e = entries[i + sideOffset]
        if e then
            b.entry = e
            b:SetText(e.label)
            b.count:SetText(e.count and tostring(e.count) or "")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", e.indent and 26 or 12, -44 - (i - 1) * SIDE_H)
            b:SetWidth(e.indent and SIDE_W - 14 or SIDE_W)
            local on = e.key == tab and e.sub == sub and (search:GetText() or "") == ""
            if on then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
        else
            b.entry = nil
            b:Hide()
        end
    end
end

function ns.SelectTab(key, subKey)
    tab, sub, offset = key, subKey, 0
    search:SetText("")
    search:ClearFocus()
    if key == "deals" then sortBy, sortDesc = "vs30", false
    elseif key == "fav" then sortBy, sortDesc = "name", false
    elseif sortBy == "vs30" and not sortDesc then sortBy, sortDesc = "market", true end
    ns.ShowList()
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function emptyText()
    if (search:GetText() or "") ~= "" then return "Nothing matches. Names load as you browse; try again in a moment." end
    if not next(ns.db.items) then return "No history yet. Click Deep Scan at the auction house (from Scanner King) to start." end
    if tab == "fav" then return "No favorites yet. Click the star next to an item, or on its page." end
    if tab == "deals" and warming then return "Working out trends..." end
    if tab == "deals" then return "No deals right now: nothing is 20% under its 30-day average with 5+ days of history." end
    return "Nothing here yet."
end

local function refreshList()
    build()
    offset = math.max(0, math.min(offset, #list - ROWS))
    for i = 1, ROWS do
        local r, e = rows[i], list[i + offset]
        if e then
            local s = e.s or {}
            r.id = e.id
            r.icon:SetTexture(ns.Info(e.id).icon)
            r.star:SetAlpha(ns.db.fav[e.id] and 1 or 0.15)
            r.cells.name:SetText(ns.ColoredName(e.id))
            r.cells.market:SetText(ns.Money(s.market))
            r.cells.vs30:SetText(ns.Percent(s.vs30, true))
            r.cells.trend7:SetText(ns.Percent(s.trend7))
            r.cells.listed:SetText(s.listed and tostring(math.floor(s.listed + 0.5)) or "|cff808080-|r")
            r.cells.supply:SetText(ns.Percent(s.supply))
            r.cells.seen:SetText(s.seen and ("|cffa0a0a0" .. ns.Age(s.seen) .. "|r") or "")
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    listView.empty:SetText(#list == 0 and emptyText() or "")
    for _, col in ipairs(COLS) do
        local h = headers[col.key]
        if h and col.label ~= "" then h:SetText(col.label .. (sortBy == col.key and (sortDesc and " v" or " ^") or "")) end
    end
    local tracked = 0
    for _ in pairs(ns.db.items) do tracked = tracked + 1 end
    local shownN = math.min(#list, ROWS)
    footer:SetText((warming and "|cffffd100Working out trends...|r  " or "")
        .. (#list > 0 and ((offset + 1) .. "-" .. (offset + shownN) .. " of " .. #list .. ".  ") or "")
        .. tracked .. " items tracked.  Last Deep Scan: " .. ns.Age(ns.db.lastDeep) .. ".")
end

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    refreshSide()
    if view == "list" then refreshList() elseif ns.RefreshItem then ns.RefreshItem() end
end

function ns.ShowList()
    view = "list"
    if ns.HideItem then ns.HideItem() end
    listView:Show()
    ns.Refresh()
end

function ns.ShowItem(id, index)
    if not frame then return end
    view = "item"
    listView:Hide()
    ns.OpenItem(id, index)
    refreshSide()
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function header(key, label, width, x, justify, tip)
    local h = CreateFrame("Button", nil, listView)
    h:SetSize(width, 18)
    h:SetPoint("TOPLEFT", x, 0)
    h:SetNormalFontObject("GameFontNormalSmall")
    h:SetText(label)
    local fs = h:GetFontString()
    if fs and justify then fs:ClearAllPoints(); fs:SetPoint(justify, justify == "RIGHT" and -6 or 0, 0) end
    h:SetScript("OnClick", function()
        if sortBy == key then sortDesc = not sortDesc else sortBy, sortDesc = key, key ~= "name" end
        offset = 0
        ns.Refresh()
    end)
    if tip then
        h:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    headers[key] = h
end

-- Asks guildmates (through Scanner King) for their latest prices of these items.
function ns.AskGuild(ids)
    if not (ScannerKing and ScannerKing.RequestPrices) then
        ns.Print("Asking the guild needs Scanner King 1.5 or newer.")
        return
    end
    local n, msgs = ScannerKing.RequestPrices(ids)
    if not n then return end -- Scanner King said why (sharing off, or no guild)
    if n == 0 then
        ns.Print("Nothing to ask: you scanned " .. (#ids == 1 and "it" or "all of these") .. " yourself in the last hour.")
    else
        ns.Print("Asked the guild about " .. n .. " item(s) in " .. msgs .. " message(s). Answers arrive over the next minute or so.")
    end
end

local function linkFor(id)
    local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id))
    return link
end
ns.LinkFor = linkFor

local function create()
    frame = CreateFrame("Frame", "EconKingFrame", UIParent, "BackdropTemplate")
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
    if UISpecialFrames then table.insert(UISpecialFrames, "EconKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Econ King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(180, 20)
    search:SetPoint("TOPRIGHT", -40, -12)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        offset = 0
        if view ~= "list" then ns.ShowList() else ns.Refresh() end
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
    searchLabel:SetText("Search every item")

    -- Left side
    sideButtons = {}
    for i = 1, SIDE_ROWS do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(SIDE_W, SIDE_H - 1)
        b:SetPoint("TOPLEFT", 12, -44 - (i - 1) * SIDE_H)
        b:SetScript("OnClick", function(self)
            if self.entry then ns.SelectTab(self.entry.key, self.entry.sub) end
        end)
        -- Name on the left (cut short with "..." if it's long), count on the right, both inside the button.
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.count:SetPoint("RIGHT", -8, 0)
        b.count:SetJustifyH("RIGHT")
        local fs = b.GetFontString and b:GetFontString()
        if fs and fs.SetJustifyH then
            fs:SetJustifyH("LEFT")
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", 8, 0)
            fs:SetPoint("RIGHT", -38, 0)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
        end
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta)
            sideOffset = math.max(0, sideOffset - delta * 3)
            refreshSide()
        end)
        sideButtons[i] = b
    end

    -- Right side: the list
    listView = CreateFrame("Frame", nil, frame)
    listView:SetPoint("TOPLEFT", SIDE_W + 24, -44)
    listView:SetPoint("BOTTOMRIGHT", -14, 40)
    ns.content = CreateFrame("Frame", nil, frame)
    ns.content:SetPoint("TOPLEFT", SIDE_W + 24, -44)
    ns.content:SetPoint("BOTTOMRIGHT", -14, 40)
    headers = {}
    local x = 0
    for _, col in ipairs(COLS) do
        if col.label ~= "" then header(col.key, col.label, col.w, x, col.justify, col.tip) end
        x = x + col.w
    end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, listView)
        r:SetSize(x, ROW_H)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local star = CreateFrame("Button", nil, r)
        star:SetSize(14, 14)
        star:SetPoint("LEFT", 2, 0)
        star:SetNormalTexture(STAR)
        star:SetScript("OnClick", function()
            if r.id then ns.SetFavorite(r.id, not ns.db.fav[r.id]) end
        end)
        r.star = star
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 20, 0)
        r.cells = {}
        local cx = 0
        for _, col in ipairs(COLS) do
            if col.key ~= "fav" then
                local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                local inset = col.key == "name" and 20 or 0
                fs:SetPoint("LEFT", cx + inset, 0)
                fs:SetWidth(col.w - 6 - inset)
                fs:SetJustifyH(col.justify)
                if fs.SetWordWrap then fs:SetWordWrap(false) end
                r.cells[col.key] = fs
            end
            cx = cx + col.w
        end
        r:SetScript("OnClick", function(self, which)
            if not self.id then return end
            if which == "RightButton" then
                ns.SetFavorite(self.id, not ns.db.fav[self.id])
            elseif IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                local link = linkFor(self.id)
                if link then ChatEdit_InsertLink(link) end
            else
                ns.ShowItem(self.id, i + offset)
            end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:AddLine("Click: price and supply history.  Right-click: favorite.  Shift-click: link.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    listView.empty = listView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    listView.empty:SetPoint("TOP", 0, -60)
    listView.empty:SetWidth(520)
    listView:EnableMouseWheel(true)
    listView:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 5)
        ns.Refresh()
    end)

    local ask = CreateFrame("Button", nil, listView, "UIPanelButtonTemplate")
    ask:SetSize(110, 22)
    ask:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", 0, -30)
    ask:SetText("Ask guild")
    ask:SetScript("OnClick", function()
        local ids = {}
        for _, e in ipairs(list) do table.insert(ids, e.id) end
        ns.AskGuild(ids)
    end)
    ask:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Ask guild")
        GameTooltip:AddLine("Ask guildmates running Scanner King for their latest prices of the " .. #list
            .. " item(s) in this list" .. (#list > 2000 and " (the first 2000)" or "") .. ". Answers fill in prices and history.", 1, 1, 1, true)
        GameTooltip:AddLine("Items you scanned yourself in the last hour are skipped. Asking for "
            .. math.min(#list, 2000) .. " items takes about " .. math.ceil(math.min(#list, 2000) / 100)
            .. " message(s); answers about one per 25 items.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    ask:SetScript("OnLeave", function() GameTooltip:Hide() end)

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", SIDE_W + 24, 16)
    footer:SetJustifyH("LEFT")
    ns.footer = footer

    ns.CreateItemView(ns.content)
    frame:SetScript("OnShow", ns.Refresh)
    frame:Hide()
end

function ns.Toggle(show)
    if not ns.db then return end
    if not frame then create() end
    if show == nil then show = not frame:IsShown() end
    frame:SetShown(show)
    if show then
        -- Favorites first; with none yet, every item.
        if tab == "fav" and not next(ns.db.fav) and next(ns.db.items) then tab, sortBy, sortDesc = "all", "market", true end
        ns.Refresh()
    end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 140)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if not mini then
        mini = CreateFrame("Button", "EconKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function(_, which)
            if which == "RightButton" then
                if ScannerKing and ScannerKing.DeepScan then ScannerKing.DeepScan() end
            else
                ns.Toggle()
            end
        end)
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
            local n = 0
            for _ in pairs(ns.db.items) do n = n + 1 end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Econ King")
            GameTooltip:AddLine(n .. " items tracked. Last Deep Scan: " .. ns.Age(ns.db.lastDeep), 1, 1, 1)
            GameTooltip:AddLine("Left-click: open", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: Deep Scan (at the auction house)", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(ns.db.ui.button)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        ns.UpdateMinimapButton()
    elseif ns.TakeWaiting() and not pending then
        -- Names trickle in one item at a time; redraw once they settle.
        pending = true
        C_Timer.After(0.5, function() pending = false; ns.Refresh() end)
    end
end)
