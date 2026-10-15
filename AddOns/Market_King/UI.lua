local _, ns = ...

-- The Market King window.
--   Top: which professions to scan, buying or farming mats, and the scan button.
--   Tabs: Best (every selected profession together), then one per profession.
--   List: most profitable first, with a red line where crafting stops beating
--   selling the raw materials.

local ROWS = 16
local ROW_H = 18
local WIDTH, HEIGHT = 780, 540

local frame, rows, redLine, footer, tabButtons, modeButtons, checks, headers
local deCheck, deOnlyButton, procCheck, recipesButton
local tab, offset = "best", 0
local shown, above = {}, 0

local COLS = {
    { key = "item", label = "Item", w = 200, justify = "LEFT" },
    { key = "skill", label = "Skill", w = 60, justify = "LEFT" },
    { key = "mats", label = "Mat cost", w = 85, justify = "RIGHT" },
    { key = "craft", label = "Craft", w = 85, justify = "RIGHT" },
    { key = "de", label = "Disenchant", w = 85, justify = "RIGHT" },
    { key = "listed", label = "Listed", w = 50, justify = "RIGHT" },
    { key = "best", label = "Best", w = 70, justify = "CENTER" },
    { key = "gain", label = "Gain", w = 85, justify = "RIGHT" },
}

local function money(v)
    if not v then return "|cff808080-|r" end
    local s = ScannerKing and ScannerKing.FormatMoney(math.abs(v)) or tostring(math.floor(math.abs(v)))
    return v < 0 and ("|cffff4040-|r" .. s) or s
end

-- The recipes button cycles through these.
local RECIPES_VIEW = {
    { key = "all", label = "All recipes", hint = "Every recipe. Patterns you don't have are greyed out." },
    { key = "mine", label = "My recipes", hint = "Trainer recipes and the patterns you have." },
    { key = "missing", label = "Patterns I lack", hint = "Only patterns you don't have: what would be worth getting." },
}

local BEST_LABEL = {
    craft = "|cff40ff40Craft|r",
    de = "|cffb070ffDisenchant|r",
}


---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function rowTooltip(self)
    local row = self.row
    if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(row.item) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Makes " .. row.made .. (row.recipe.learned and "  (learned from your trade skill window)" or ""), 1, 0.82, 0)
    if row.pattern then
        local names = {}
        for _, id in ipairs(row.pattern) do
            local n = ns.ItemName(id)
            if not names[n] then names[n] = true; table.insert(names, n) end
        end
        GameTooltip:AddLine("Needs " .. table.concat(names, " or "), 1, 1, 1, true)
        local p = ns.AHPrice(row.pattern[1])
        if p then GameTooltip:AddDoubleLine("  on the auction house", money(p), 0.8, 0.8, 0.8, 1, 1, 1) end
    else
        GameTooltip:AddLine("Taught by a trainer", 0.8, 0.8, 0.8)
    end
    if row.has then
        GameTooltip:AddLine("You have this recipe. Right-click to mark it as one you don't.", 0.4, 1, 0.4, true)
    else
        GameTooltip:AddLine("You don't have this recipe. Right-click to mark it as one you do.", 1, 0.5, 0.3, true)
    end
    for _, m in ipairs(row.mats) do
        local cost = m.unit and money(m.unit * m.count) or "|cffff4040no price|r"
        GameTooltip:AddDoubleLine("  " .. m.count .. "x " .. ns.ItemName(m.id) .. (m.vendor and " (vendor)" or ""), cost, 1, 1, 1, 1, 1, 1)
    end
    -- The same figures as the row's columns, so the two always agree.
    local gold, white = { 1, 0.82, 0 }, { 1, 1, 1 }
    local function line(label, value) GameTooltip:AddDoubleLine(label, value, gold[1], gold[2], gold[3], white[1], white[2], white[3]) end
    if row.mode == "farm" then
        line("Raw value (farmed mats sold, after 5% cut)", money(row.raw))
        if row.vendorCost > 0 then line("Vendor reagents to buy", money(row.vendorCost)) end
    else
        line("Mat cost", money(row.cost))
    end
    line("Sells for", row.price and (money(row.price) .. " each") or "|cff808080not on the auction house|r")
    if row.craftSale then line("Craft sells (after 5% cut)", money(row.craftSale)) end
    if row.deSale then line(row.noProcs and "DE sells (no procs, after 5% cut)" or "DE sells (after 5% cut)", money(row.deSale)) end
    if row.gain then
        local label = row.mode == "farm" and "Gain vs raw" or "Profit"
        line(label, (row.gain > 0 and "|cff40ff40" or "|cffff4040") .. money(row.gain) .. "|r")
    end
    if row.listed then
        GameTooltip:AddDoubleLine("Listed on the auction house", tostring(row.listed), 1, 0.82, 0, 1, 1, 1)
    end
    if row.deResults then
        GameTooltip:AddDoubleLine("Disenchants into (average)", row.deEach and money(row.deEach) or "|cff808080some mats unpriced|r", 1, 0.82, 0, 1, 1, 1)
        -- Each mat: average amount, its price, and what it adds to the average.
        for _, d in ipairs(row.deResults) do
            local p = ns.AHPrice(d[1])
            local left = string.format("  %.2f x %s", d[2], ns.ItemName(d[1]))
                .. (d[3] and " |cffff9900(proc)|r" or "")
                .. (p and ("  @ " .. money(p)) or "")
            GameTooltip:AddDoubleLine(left, p and money(p * d[2]) or "|cffff4040no price|r", 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if row.deBaseEach and row.deBaseEach ~= row.deEach then
            line("Average without procs", money(row.deBaseEach))
        end
        -- Disenchant profit both ways: the long-run average, and without counting on procs.
        if row.deSaleProcs then
            local base = (row.mode == "farm" and row.vendorCost or row.cost) + row.raw
            local label = row.mode == "farm" and "DE gain vs raw" or "DE profit"
            local function colored(v) return (v > 0 and "|cff40ff40" or "|cffff4040") .. money(v) .. "|r" end
            line(label .. " (with procs)", colored(row.deSaleProcs - base))
            line(label .. " (no procs)", colored(row.deSaleBase - base))
        end
    end
    if row.missing then
        GameTooltip:AddLine("Missing a price for " .. ns.ItemName(row.missing) .. ". Scan again or visit a vendor.", 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    local mode = ns.db.mode
    for key, b in pairs(modeButtons) do
        if key == mode then b:LockHighlight() else b:UnlockHighlight() end
    end
    deCheck:SetChecked(ns.db.includeDE)
    deCheck:SetEnabled(not ns.db.deOnly)
    if ns.db.deOnly then deOnlyButton:LockHighlight() else deOnlyButton:UnlockHighlight() end
    procCheck:SetChecked(ns.db.deNoProcs)
    procCheck:SetShown(ns.db.deOnly)
    for _, v in ipairs(RECIPES_VIEW) do
        if v.key == ns.db.recipes then recipesButton:SetText(v.label) end
    end
    headers.craft:SetText(ns.db.deOnly and "" or "Craft sells")
    headers.de:SetText(ns.db.deOnly and ns.db.deNoProcs and "DE (no procs)" or (ns.db.includeDE or ns.db.deOnly) and "DE sells" or "")
    for _, c in pairs(checks) do c:SetChecked(ns.Selected(c.prof)) end

    -- Tabs: Best, then each selected profession
    local tabs = { { key = "best", label = "Best", short = "Best" } }
    for _, p in ipairs(ns.PROFESSIONS) do
        if ns.Selected(p.id) then table.insert(tabs, { key = p.id, label = p.name, short = p.short }) end
    end
    local tabOK = false
    for _, t in ipairs(tabs) do if t.key == tab then tabOK = true end end
    if not tabOK then tab = "best" end
    -- Size each tab to its name; switch to short names if they'd run off the window.
    local function fit(useShort)
        local total = 0
        for i, b in ipairs(tabButtons) do
            local t = tabs[i]
            if t then
                b:SetText(useShort and t.short or t.label)
                local fs = b.GetFontString and b:GetFontString()
                local w = fs and fs.GetStringWidth and fs:GetStringWidth()
                w = math.max(50, (w or #(useShort and t.short or t.label) * 7) + 24)
                b:SetWidth(w)
                total = total + w + 2
            end
        end
        return total
    end
    if fit(false) > WIDTH - 32 then fit(true) end
    for i, b in ipairs(tabButtons) do
        local t = tabs[i]
        if t then
            b.key = t.key
            b:Show()
            if t.key == tab then b:LockHighlight() else b:UnlockHighlight() end
        else
            b:Hide()
        end
    end

    headers.mats:SetText(mode == "farm" and "Raw value" or "Mat cost")
    headers.gain:SetText(mode == "farm" and "Gain vs raw" or "Profit")

    if not next(ns.db.profs) then
        shown, above = {}, 0
    else
        shown, above = ns.Rank(tab ~= "best" and tab or nil, mode,
            { noDE = not ns.db.includeDE, deOnly = ns.db.deOnly, noProcs = ns.db.deOnly and ns.db.deNoProcs, recipes = ns.db.recipes })
    end
    offset = math.max(0, math.min(offset, #shown - ROWS))

    redLine:Hide()
    for i = 1, ROWS do
        local r, row = rows[i], shown[i + offset]
        if row then
            r.row = row
            local info = ns.ItemInfo(row.item)
            r.icon:SetTexture(info.icon)
            local color = ({ [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee" })[info.q or 1] or "|cffffffff"
            r.cells.item:SetText(color .. ns.ItemName(row.item) .. "|r" .. (row.made > 1 and (" x" .. row.made) or ""))
            local p = ns.PROF_BY_ID[row.prof]
            r.cells.skill:SetText((tab == "best" and p and (p.name:sub(1, 4) .. " ") or "") .. (row.skill > 0 and row.skill or ""))
            r.cells.mats:SetText(row.missing and "|cffff4040missing|r" or money(mode == "farm" and row.raw or row.cost))
            r.cells.craft:SetText(money(row.craftSale))
            r.cells.de:SetText(money(row.deSale))
            r.cells.listed:SetText(row.listed and tostring(row.listed) or "|cff808080-|r")
            if row.missing then
                r.cells.best:SetText("|cff808080?|r")
            elseif not row.gain or row.gain <= 0 then
                r.cells.best:SetText(mode == "farm" and "|cffffd100Sell raw|r" or "|cff808080Skip|r")
            else
                r.cells.best:SetText(BEST_LABEL[row.best] or "")
            end
            local g = row.gain
            r.cells.gain:SetText(g and ((g > 0 and "|cff40ff40" or "|cffff4040") .. money(g) .. "|r") or "|cff808080-|r")
            -- Patterns you don't have stay in the list but greyed out
            r:SetAlpha((row.has or ns.db.recipes == "missing") and 1 or 0.45)
            r:Show()
            -- The red line sits under the last row that beats selling raw.
            if i + offset == above and above < #shown then
                redLine:ClearAllPoints()
                redLine:SetPoint("TOPLEFT", r, "BOTTOMLEFT", 0, 1)
                redLine:SetPoint("TOPRIGHT", r, "BOTTOMRIGHT", 0, 1)
                redLine:Show()
            end
        else
            r.row = nil
            r:Hide()
        end
    end
    if above == 0 and #shown > 0 and offset == 0 then
        redLine:ClearAllPoints()
        redLine:SetPoint("BOTTOMLEFT", rows[1], "TOPLEFT", 0, 0)
        redLine:SetPoint("BOTTOMRIGHT", rows[1], "TOPRIGHT", 0, 0)
        redLine:Show()
    end

    local last = ScannerKing and ScannerKing.LastScan and ScannerKing.LastScan()
    if not next(ns.db.profs) then
        footer:SetText("Tick the professions to show. Click Market Scan on the auction house (Scanner King) to get prices.")
    else
        footer:SetText(#shown .. " recipes, " .. above .. " beat " .. (mode == "farm" and "selling raw" or "not crafting")
            .. " (above the red line).  Prices from " .. (last and ScannerKing.PriceAge(last) or "no scan yet")
            .. (#shown > ROWS and ".  Scroll for more." or "."))
    end
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

local function create()
    frame = CreateFrame("Frame", "MarketKingFrame", UIParent, "BackdropTemplate")
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
    if UISpecialFrames then table.insert(UISpecialFrames, "MarketKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Market King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Profession checkboxes
    checks = {}
    local allBtn = button(frame, "All", 40, function()
        local all = true
        for _, p in ipairs(ns.PROFESSIONS) do if not ns.Selected(p.id) then all = false end end
        for _, p in ipairs(ns.PROFESSIONS) do ns.db.profs[p.id] = (not all) or nil end
        ns.Refresh()
    end)
    allBtn:SetPoint("TOPLEFT", 16, -42)
    for i, p in ipairs(ns.PROFESSIONS) do
        -- two rows of five, so every name fits
        local col, line = (i - 1) % 5, math.floor((i - 1) / 5)
        local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        c:SetSize(22, 22)
        c:SetPoint("TOPLEFT", 66 + col * 140, -40 - line * 22)
        c.prof = p.id
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", c, "RIGHT", 0, 1)
        label:SetText(p.name)
        c:SetScript("OnClick", function(self)
            ns.db.profs[self.prof] = self:GetChecked() and true or nil
            ns.Refresh()
        end)
        checks[p.id] = c
    end

    -- Buying or farming, and scanning
    modeButtons = {
        buy = button(frame, "Yrgna Special", 120, function() ns.db.mode = "buy"; ns.Refresh() end),
        farm = button(frame, "Ethical Gaming", 120, function() ns.db.mode = "farm"; ns.Refresh() end),
    }
    modeButtons.buy:SetPoint("TOPLEFT", 16, -90)
    modeButtons.farm:SetPoint("LEFT", modeButtons.buy, "RIGHT", 4, 0)
    local function hint(b, text)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    hint(modeButtons.buy, "Buying mats. Materials are a cost: shows what's worth buying mats for (flips).")
    hint(modeButtons.farm, "Farming mats. You gathered the materials: compares crafting with just selling them.")

    -- Disenchanting: include it in the comparison, or show only what's worth disenchanting
    deCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    deCheck:SetSize(22, 22)
    deCheck:SetPoint("LEFT", modeButtons.farm, "RIGHT", 16, 0)
    local deLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deLabel:SetPoint("LEFT", deCheck, "RIGHT", 0, 1)
    deLabel:SetText("Include disenchanting")
    deCheck:SetScript("OnClick", function(self)
        ns.db.includeDE = self:GetChecked() and true or false
        ns.Refresh()
    end)
    deOnlyButton = button(frame, "DE only", 80, function()
        ns.db.deOnly = not ns.db.deOnly
        offset = 0
        ns.Refresh()
    end)
    deOnlyButton:SetPoint("LEFT", deLabel, "RIGHT", 12, -1)
    hint(deOnlyButton, "Show only items that can be disenchanted, ranked by what crafting and disenchanting them makes.")

    -- DE only: value disenchants without rare procs, to see what's profitable on the baseline alone
    procCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    procCheck:SetSize(22, 22)
    procCheck:SetPoint("LEFT", deOnlyButton, "RIGHT", 10, 0)
    local procLabel = procCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    procLabel:SetPoint("LEFT", procCheck, "RIGHT", 0, 1)
    procLabel:SetText("No procs")
    procCheck:SetScript("OnClick", function(self)
        ns.db.deNoProcs = self:GetChecked() and true or false
        offset = 0
        ns.Refresh()
    end)
    -- Which recipes: all, only the ones you have, or only patterns you lack
    recipesButton = button(frame, "", 120, function()
        for i, v in ipairs(RECIPES_VIEW) do
            if v.key == ns.db.recipes then
                ns.db.recipes = RECIPES_VIEW[i % #RECIPES_VIEW + 1].key
                break
            end
        end
        offset = 0
        ns.Refresh()
    end)
    recipesButton:SetPoint("TOPRIGHT", -16, -90)
    recipesButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for _, v in ipairs(RECIPES_VIEW) do
            local on = v.key == ns.db.recipes
            GameTooltip:AddLine((on and "> " or "   ") .. v.label .. ": " .. v.hint, on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Recipes you know are picked up when you open your trade skill window. Right-click any row to mark it as had or not.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    recipesButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    hint(procCheck, "Value disenchants without rare procs (the 5% shard on greens, the Nexus Crystal on blues), so you only see what's profitable on the dust and essences you can count on.")

    -- Tabs
    tabButtons = {}
    for i = 1, 10 do
        local b = button(frame, "", 72, function(self) tab, offset = self.key, 0; ns.Refresh() end)
        if i == 1 then b:SetPoint("TOPLEFT", 16, -132) else b:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 2, 0) end
        b:Hide()
        tabButtons[i] = b
    end

    -- Column headers and rows
    headers = {}
    local hx = 36
    for _, col in ipairs(COLS) do
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", hx, -160)
        h:SetWidth(col.w - 6)
        h:SetJustifyH(col.justify)
        h:SetText(col.label)
        headers[col.key] = h
        hx = hx + col.w
    end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, frame)
        r:SetSize(WIDTH - 40, ROW_H)
        r:SetPoint("TOPLEFT", 16, -176 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 0, 0)
        r.cells = {}
        local cx = 20
        for _, col in ipairs(COLS) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.w - 6)
            fs:SetJustifyH(col.justify)
            r.cells[col.key] = fs
            cx = cx + col.w
        end
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, which)
            if which ~= "RightButton" or not self.row then return end
            ns.SetHasRecipe(self.row.recipe.spell, not self.row.has)
            ns.Refresh()
            if self:IsShown() and self.row then rowTooltip(self) end
        end)
        r:SetScript("OnEnter", rowTooltip)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    redLine = frame:CreateTexture(nil, "OVERLAY")
    redLine:SetHeight(2)
    redLine:SetColorTexture(1, 0.1, 0.1, 0.9)
    redLine:Hide()

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 4)
        ns.Refresh()
    end)

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 16)
    footer:SetJustifyH("LEFT")

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
-- Minimap button
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 165)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if not mini then
        mini = CreateFrame("Button", "MarketKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function(_, which)
            if which == "RightButton" then ns.OpenMarketScan() else ns.Toggle() end
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
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Market King")
            GameTooltip:AddLine("Left-click: open", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: Market Scan (at the auction house)", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(ns.db.ui.button)
end

function ns.OpenMarketScan()
    if ScannerKing and ScannerKing.OpenMarketScan then
        ScannerKing.OpenMarketScan()
    else
        ns.Print("Market Scan needs Scanner King 1.3 or newer.")
    end
end
