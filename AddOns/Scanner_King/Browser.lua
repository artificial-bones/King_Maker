local _, ns = ...
local API = ns.API

-- The price browser: every item Scanner King has a price for, grouped the way
-- the auction house groups them (Metal & Stone, Herb, Cloth, ...), with search
-- and sorting. Opened from the minimap button or /sk show.

local ROWS = 18
local ROW_H = 18
local WIDTH, HEIGHT = 560, 470
local CAT_W = 130

local panel, rows, catButtons, search, footer, headers
local category, sortBy, sortDesc, offset, catOffset = "All", "price", true, 0, 0
local list = {}

---------------------------------------------------------------------------
-- Item info: name, icon and category, cached so the list works offline too
---------------------------------------------------------------------------

local pendingNames = false

local function info(id)
    local c = ns.db.items[id]
    if c and c.name then return c end
    c = c or {}
    local name, icon, classID, sub, typeName
    if C_Item and C_Item.GetItemInfoInstant then
        local _, itemType, itemSubType, _, tex, cls = C_Item.GetItemInfoInstant(id)
        typeName, sub, icon, classID = itemType, itemSubType, tex, cls
    end
    name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id) -- arrives as GET_ITEM_INFO_RECEIVED
        pendingNames = true
    end
    c.name = name
    c.icon = icon or c.icon
    if classID == 7 and sub then
        c.cat = sub -- Trade Goods: use its subcategory (Metal & Stone, Herb, Cloth...)
    elseif typeName then
        c.cat = typeName
    end
    ns.db.items[id] = c
    return c
end

local function categories()
    local seen, cats = {}, {}
    for id in pairs(ns.db.prices) do
        local cat = info(id).cat or "Other"
        if not seen[cat] then seen[cat] = true; table.insert(cats, cat) end
    end
    table.sort(cats)
    table.insert(cats, 1, "All")
    return cats
end

local function build()
    wipe(list)
    local text = search and search:GetText() and search:GetText():lower() or ""
    for id, pr in pairs(ns.db.prices) do
        local i = info(id)
        local name = i.name or ("Item " .. id)
        if (category == "All" or (i.cat or "Other") == category)
            and (text == "" or name:lower():find(text, 1, true)) then
            table.insert(list, { id = id, name = name, icon = i.icon, p = pr.p, q = pr.q, t = pr.t, from = pr.from })
        end
    end
    table.sort(list, function(a, b)
        local x, y
        if sortBy == "name" then x, y = a.name, b.name
        elseif sortBy == "qty" then x, y = a.q or 0, b.q or 0
        elseif sortBy == "age" then x, y = a.t or 0, b.t or 0
        else x, y = a.p, b.p end
        if x == y then return a.name < b.name end
        if sortDesc then return x > y end
        return x < y
    end)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function refreshCategories()
    local cats = categories()
    local known = false
    for _, c in ipairs(cats) do if c == category then known = true end end
    if not known then category = "All" end
    -- After a Deep Scan there can be more categories than buttons: the wheel scrolls them.
    catOffset = math.max(0, math.min(catOffset, #cats - #catButtons))
    for i, b in ipairs(catButtons) do
        local cat = cats[i + catOffset]
        if cat then
            b.cat = cat
            b:SetText(cat)
            b:Show()
            if cat == category then b:LockHighlight() else b:UnlockHighlight() end
        else
            b:Hide()
        end
    end
end

function ns.UpdateBrowser()
    if not panel or not panel:IsShown() then return end
    refreshCategories()
    build()
    offset = math.max(0, math.min(offset, #list - ROWS))
    for i = 1, ROWS do
        local r, e = rows[i], list[i + offset]
        if e then
            r.id = e.id
            r.icon:SetTexture(e.icon)
            r.name:SetText(e.name)
            r.price:SetText(API.FormatMoney(e.p))
            r.qty:SetText(e.q and tostring(e.q) or "")
            r.age:SetText(API.PriceAge(e.t) .. (e.from and (" (" .. e.from .. ")") or ""))
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    local total = 0
    for _ in pairs(ns.db.prices) do total = total + 1 end
    local shown = math.min(#list, ROWS)
    footer:SetText((#list > 0 and ((offset + 1) .. "-" .. (offset + shown) .. " of " .. #list) or "No items")
        .. (#list ~= total and (" (" .. total .. " in all)") or "")
        .. ".  Last full scan: " .. (ns.db.lastScan and API.PriceAge(ns.db.lastScan) or "never"))
    for key, h in pairs(headers) do
        h:SetText(h.label .. (sortBy == key and (sortDesc and " v" or " ^") or ""))
    end
end

local function header(parent, key, label, width, x, justify)
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(width, 18)
    h:SetPoint("TOPLEFT", x, 0)
    h:SetNormalFontObject("GameFontNormalSmall")
    h:SetText(label)
    h.label = label
    local fs = h:GetFontString()
    if fs and justify then fs:ClearAllPoints(); fs:SetPoint(justify, 0, 0) end
    h:SetScript("OnClick", function()
        if sortBy == key then sortDesc = not sortDesc else sortBy, sortDesc = key, key ~= "name" end
        offset = 0
        ns.UpdateBrowser()
    end)
    headers[key] = h
    return h
end

local function create()
    panel = CreateFrame("Frame", "ScannerKingBrowser", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "ScannerKingBrowser") end -- Escape closes it

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Scanner King")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    search:SetSize(160, 20)
    search:SetPoint("TOPRIGHT", -40, -12)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() offset = 0; ns.UpdateBrowser() end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
    searchLabel:SetText("Search")

    -- Category list down the left
    catButtons = {}
    for i = 1, 22 do
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(CAT_W, 18)
        b:SetPoint("TOPLEFT", 12, -44 - (i - 1) * 19)
        b:SetScript("OnClick", function(self)
            category, offset = self.cat, 0
            ns.UpdateBrowser()
        end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta)
            catOffset = math.max(0, catOffset - delta * 3)
            ns.UpdateBrowser()
        end)
        catButtons[i] = b
    end

    -- Item list
    local listArea = CreateFrame("Frame", nil, panel)
    listArea:SetPoint("TOPLEFT", CAT_W + 22, -44)
    listArea:SetPoint("BOTTOMRIGHT", -14, 40)
    headers = {}
    header(listArea, "name", "Item", 170, 0, "LEFT")
    header(listArea, "price", "Price", 100, 170, "RIGHT")
    header(listArea, "qty", "Listed", 50, 275, "RIGHT")
    header(listArea, "age", "Scanned", 90, 330, "LEFT")

    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, listArea)
        r:SetSize(WIDTH - CAT_W - 40, ROW_H)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 0, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 20, 0)
        r.name:SetWidth(150)
        r.name:SetJustifyH("LEFT")
        r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.price:SetPoint("RIGHT", r, "LEFT", 270, 0)
        r.price:SetJustifyH("RIGHT")
        r.qty = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.qty:SetPoint("RIGHT", r, "LEFT", 325, 0)
        r.qty:SetJustifyH("RIGHT")
        r.age = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.age:SetPoint("LEFT", 330, 0)
        r.age:SetJustifyH("LEFT")
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 5)
        ns.UpdateBrowser()
    end)

    footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", CAT_W + 22, 16)

    local scan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scan:SetSize(100, 22)
    scan:SetPoint("BOTTOMRIGHT", -14, 12)
    scan:SetText("Scan now")
    scan:SetScript("OnClick", API.Scan)

    panel:SetScript("OnShow", ns.UpdateBrowser)
    panel:Hide()
end

function API.ToggleBrowser(show)
    if not ns.db then return end
    if not panel then create() end
    if show == nil then show = not panel:IsShown() end
    panel:SetShown(show)
    if show then ns.UpdateBrowser() end
end

---------------------------------------------------------------------------
-- Minimap button: left-click opens the browser, right-click scans
---------------------------------------------------------------------------

local button

local function position()
    local angle = math.rad(ns.db.ui.buttonAngle or 190)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.ui.buttonAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    position()
end

local function createButton()
    button = CreateFrame("Button", "ScannerKingMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    local mask = button:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then API.Scan() else API.ToggleBrowser() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        local n = 0
        for _ in pairs(ns.db.prices) do n = n + 1 end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Scanner King")
        GameTooltip:AddLine(n .. " prices. Last scan: " .. (ns.db.lastScan and API.PriceAge(ns.db.lastScan) or "never"), 1, 1, 1)
        GameTooltip:AddLine("Left-click: price list", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: scan (at the auction house)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if not button then createButton() end
    position()
    button:SetShown(ns.db.ui.button)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

API.RegisterCallback("Scanner_King_browser", function(event)
    if event == "PRICES_UPDATED" or event == "SCAN_FINISHED" then ns.UpdateBrowser() end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.UpdateMinimapButton()
    elseif pendingNames then
        -- Names trickle in one item at a time; redraw once they've settled.
        pendingNames = false
        C_Timer.After(0.3, ns.UpdateBrowser)
    end
end)
