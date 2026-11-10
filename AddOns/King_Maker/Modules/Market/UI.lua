local _, KM = ...
local ns = KM.Module("Market")
local UI = KM.UI
local C = UI.C

-- The Crafting Profits page of the King Maker window (Crafting > Crafting Profits).
--   Top:    which professions to show (and All), Market Scan (the Scanner's dialog).
--   Then:   Yrgna Special (buying mats) or Ethical Gaming (farming mats), disenchanting options, and which
--           recipes to show (all, mine, patterns I lack).
--   Tabs:   Best (every ticked profession together), then one per ticked profession.
--   List:   most profitable first, with a red line where crafting stops beating selling the raw materials.
--           Hover a row for the full breakdown; right-click it to mark the recipe as had or not had.
-- Also here: the crown's quick action and the Settings section.

local PAGE = "crafting"
local PAGE_W = 764               -- the page container is about 764 x 560
local CHECK_W, CHECK_H = 116, 22
local TAB_Y, TABLE_Y = -88, -122

local page, tbl, footer, redLine, checks, modeButtons, deCheck, deOnlyButton, procCheck, recipesButton, tabsHolder
local tabs, tabSig = nil, nil
local tabCache = {}
local tab = "best"
local shown, above = {}, 0

-- The recipes button cycles through these.
local RECIPES_VIEW = {
    { key = "all", label = "All recipes", hint = "Every recipe. Patterns you don't have are greyed out." },
    { key = "mine", label = "My recipes", hint = "Trainer recipes and the patterns you have." },
    { key = "missing", label = "Patterns I lack", hint = "Only patterns you don't have: what would be worth getting." },
}

local MODES = {
    buy = { label = "Yrgna Special", hint = "Buying mats. Materials are a cost: shows what's worth buying mats for (flips)." },
    farm = { label = "Ethical Gaming", hint = "Farming mats. You gathered the materials: compares crafting with just selling them." },
}

local function money(v) return KM.Money(v) end
local function colored(v) return (v > 0 and UI.Hex(C.good) or UI.Hex(C.bad)) .. KM.Money(v) .. "|r" end
local DASH = "|cff808080-|r"

---------------------------------------------------------------------------
-- The row tooltip: every figure behind the row
---------------------------------------------------------------------------

local function rowTooltip(r)
    local row = r.data
    if not row then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, row.item) end
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
    local function line(label, value) GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1) end
    if row.mode == "farm" then
        line("Raw value (farmed mats sold, after 5% cut)", money(row.raw))
        if row.vendorCost > 0 then line("Vendor reagents to buy", money(row.vendorCost)) end
    else
        line("Mat cost", money(row.cost))
    end
    line("Sells for", row.price and (money(row.price) .. " each") or "|cff808080not on the auction house|r")
    if row.craftSale then line("Craft sells (after 5% cut)", money(row.craftSale)) end
    if row.deSale then line(row.noProcs and "DE sells (no procs, after 5% cut)" or "DE sells (after 5% cut)", money(row.deSale)) end
    if row.gain then line(row.mode == "farm" and "Gain vs raw" or "Profit", colored(row.gain)) end
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
            line(label .. " (with procs)", colored(row.deSaleProcs - base))
            line(label .. " (no procs)", colored(row.deSaleBase - base))
        end
    end
    if row.missing then
        GameTooltip:AddLine("Missing a price for " .. ns.ItemName(row.missing) .. ". Scan again or visit a vendor.", 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function bestPill(r, x)
    if not r.best then
        r.best = UI.Pill(r)
        r.best:SetSize(66, 16)
        r.best:SetPoint("LEFT", x, 0)
    end
    return r.best
end

local function fillRow(r, row, cells)
    local mode = ns.db.mode
    local info = ns.ItemInfo(row.item)
    if r.icon then r.icon:SetTexture(info.icon) end
    local color = UI.QUALITY[info.q or 1] or "ffffff"
    cells.item:SetText("|cff" .. color .. ns.ItemName(row.item) .. "|r" .. (row.made > 1 and (" x" .. row.made) or ""))
    local p = ns.PROF_BY_ID[row.prof]
    cells.skill:SetText((tab == "best" and p and (p.name:sub(1, 4) .. " ") or "") .. (row.skill > 0 and row.skill or ""))
    cells.mats:SetText(row.missing and "|cffff4040missing|r" or money(mode == "farm" and row.raw or row.cost))
    cells.craft:SetText(money(row.craftSale))
    cells.de:SetText(money(row.deSale))
    cells.listed:SetText(row.listed and tostring(row.listed) or DASH)
    cells.best:SetText("")
    local pill = bestPill(r, tbl.cols[7].x + 2)
    if row.missing then
        pill:SetCustom("?", C.muted)
    elseif not row.gain or row.gain <= 0 then
        if mode == "farm" then pill:SetCustom("SELL RAW", C.warn) else pill:SetCustom("SKIP", C.dim) end
    elseif row.best == "de" then
        pill:SetCustom("DISENCHANT", C.violet)
    else
        pill:SetCustom("CRAFT", C.good)
    end
    cells.gain:SetText(row.gain and colored(row.gain) or DASH)
    -- Patterns you don't have stay in the list but greyed out
    r:SetAlpha((row.has or ns.db.recipes == "missing") and 1 or 0.45)
end

-- The red line sits under the last row that beats selling raw (or above the first when none do).
local function placeRedLine()
    redLine:Hide()
    if #shown == 0 then return end
    local i = above - tbl.offset
    local r
    if above == 0 then
        if tbl.offset == 0 then r = tbl.rows[1] end
        if r then
            redLine:ClearAllPoints()
            redLine:SetPoint("BOTTOMLEFT", r, "TOPLEFT", 0, 0)
            redLine:SetPoint("BOTTOMRIGHT", r, "TOPRIGHT", 0, 0)
            redLine:Show()
        end
    elseif above < #shown and i >= 1 and i <= (tbl.visible or 0) then
        r = tbl.rows[i]
        redLine:ClearAllPoints()
        redLine:SetPoint("TOPLEFT", r, "BOTTOMLEFT", 0, 1)
        redLine:SetPoint("TOPRIGHT", r, "BOTTOMRIGHT", 0, 1)
        redLine:Show()
    end
end

local function footerText()
    local mode = ns.db.mode
    local last = ScannerKing and ScannerKing.LastScan and ScannerKing.LastScan()
    if not next(ns.db.profs) then
        footer:SetText("Tick the professions to show. Click Market Scan at the auction house to get prices.")
    else
        local n = math.min(#shown, tbl.visible or #shown)
        footer:SetText(#shown .. " recipes, " .. above .. " beat " .. (mode == "farm" and "selling raw" or "not crafting")
            .. " (above the red line).  Prices from " .. (last and ScannerKing.PriceAge(last) or "no scan yet")
            .. (#shown > n and ".  Scroll for more." or "."))
    end
end

-- Tabs: Best, then each ticked profession. A UI.Tabs strip is fixed, so one is made per set of professions.
local function refreshTabs()
    local items = { { id = "best", label = "Best", short = "Best" } }
    local sig = "best"
    for _, p in ipairs(ns.PROFESSIONS) do
        if ns.Selected(p.id) then
            table.insert(items, { id = p.id, label = p.name, short = p.short })
            sig = sig .. ":" .. p.id
        end
    end
    local ok = false
    for _, it in ipairs(items) do if it.id == tab then ok = true end end
    if not ok then tab = "best" end
    if sig ~= tabSig then
        if tabs then tabs:Hide() end
        tabs = tabCache[sig]
        if not tabs then
            -- Full names, or short ones when they'd run off the page.
            local width = 0
            for _, it in ipairs(items) do width = width + math.max(64, 18 + 7 * #it.label) - 1 end
            local useShort = width > PAGE_W
            local list = {}
            for _, it in ipairs(items) do list[#list + 1] = { id = it.id, label = useShort and it.short or it.label } end
            tabs = UI.Tabs(tabsHolder, list, function(id) tab = id; tbl.offset = 0; ns.Refresh() end)
            tabs:SetPoint("TOPLEFT", 0, 0)
            tabCache[sig] = tabs
        end
        tabs:Show()
        tabSig = sig
    end
    tabs:Select(tab)
end

local function refreshControls()
    local db = ns.db
    for key, b in pairs(modeButtons) do b:SetActive(key == db.mode) end
    deCheck:SetChecked(db.includeDE)
    deCheck.label:SetTextColor(db.deOnly and C.dim[1] or C.text[1], db.deOnly and C.dim[2] or C.text[2], db.deOnly and C.dim[3] or C.text[3])
    deOnlyButton:SetActive(db.deOnly)
    procCheck:SetChecked(db.deNoProcs)
    procCheck.frame:SetShown(db.deOnly)
    for _, v in ipairs(RECIPES_VIEW) do
        if v.key == db.recipes then recipesButton:SetLabel(v.label) end
    end
    for id, c in pairs(checks) do c:SetChecked(ns.Selected(id)) end
end

local function setHeaders()
    local db = ns.db
    local cols = tbl.cols
    cols[3].label = db.mode == "farm" and "Raw value" or "Mat cost"
    cols[4].label = db.deOnly and "" or "Craft sells"
    cols[5].label = db.deOnly and db.deNoProcs and "DE (no procs)" or (db.includeDE or db.deOnly) and "DE sells" or ""
    cols[8].label = db.mode == "farm" and "Gain vs raw" or "Profit"
end

local function refresh()
    if not ns.db or not page then return end
    refreshControls()
    refreshTabs()
    setHeaders()
    local db = ns.db
    if not next(db.profs) then
        shown, above = {}, 0
    else
        shown, above = ns.Rank(tab ~= "best" and tab or nil, db.mode,
            { noDE = not db.includeDE and not db.deOnly, deOnly = db.deOnly, noProcs = db.deOnly and db.deNoProcs, recipes = db.recipes })
    end
    tbl.emptyText = not next(db.profs) and "Tick a profession above to see what it's worth crafting."
        or "Nothing to show for these professions and filters."
    tbl:SetRows(shown, fillRow)
end

-- Redraws the page if it's the one showing.
function ns.Refresh() KM.Refresh(PAGE) end

-- Opens (true), closes (false) or toggles (nil) the page.
function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown(PAGE) end
    if show then KM.Show(PAGE) elseif KM.IsShown(PAGE) then KM.Toggle(false) end
end

function ns.OpenMarketScan()
    if ScannerKing and ScannerKing.OpenMarketScan then
        ScannerKing.OpenMarketScan()
    else
        KM.Print(ns, "Market Scan needs the Scanner module.")
    end
end

function ns.CurrentRows() return shown, above end
function ns.Page() return page end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function buildPage(c)
    page = c

    -- Professions: All, then two rows of five ticks so every name fits.
    local all = UI.Button(c, "All", 50, 22, function()
        local everything = true
        for _, p in ipairs(ns.PROFESSIONS) do if not ns.Selected(p.id) then everything = false end end
        for _, p in ipairs(ns.PROFESSIONS) do ns.db.profs[p.id] = (not everything) or nil end
        ns.Refresh()
    end)
    all:SetPoint("TOPLEFT", 0, 0)
    UI.Tip(all, "Tick every profession, or untick them all.")
    checks = {}
    for i, p in ipairs(ns.PROFESSIONS) do
        local col, line = (i - 1) % 5, math.floor((i - 1) / 5)
        local cb = UI.CheckLabel(c, p.name, function(on)
            ns.db.profs[p.id] = on or nil
            ns.Refresh()
        end)
        cb.frame:SetPoint("TOPLEFT", 64 + col * CHECK_W, -2 - line * CHECK_H)
        cb.prof = p.id
        checks[p.id] = cb
    end
    local scan = UI.Button(c, "Market Scan", 104, 24, function() ns.OpenMarketScan() end, "primary")
    scan:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(scan, "At the auction house: pick professions and price everything they make and use. Opens the Scanner's Market Scan window.")

    -- How to count, disenchanting, which recipes.
    local y = -52
    modeButtons = {}
    local x = 0
    for _, key in ipairs({ "buy", "farm" }) do
        local m = MODES[key]
        local b = UI.Button(c, m.label, 112, 24, function() ns.db.mode = key; ns.Refresh() end)
        b:SetPoint("TOPLEFT", x, y)
        UI.Tip(b, m.hint)
        modeButtons[key] = b
        x = x + 116
    end
    deCheck = UI.CheckLabel(c, "Include disenchanting", function(on)
        if ns.db.deOnly then deCheck:SetChecked(ns.db.includeDE) return end -- DE only always counts disenchanting
        ns.db.includeDE = on and true or false
        ns.Refresh()
    end, "Count crafting the item, disenchanting it and selling the enchanting materials as an option.")
    deCheck.frame:SetPoint("TOPLEFT", x + 10, y - 3)
    deOnlyButton = UI.Button(c, "DE only", 70, 24, function()
        ns.db.deOnly = not ns.db.deOnly
        tbl.offset = 0
        ns.Refresh()
    end)
    deOnlyButton:SetPoint("TOPLEFT", x + 176, y)
    UI.Tip(deOnlyButton, "Show only items that can be disenchanted, ranked by what crafting and disenchanting them makes.")
    procCheck = UI.CheckLabel(c, "No procs", function(on)
        ns.db.deNoProcs = on and true or false
        tbl.offset = 0
        ns.Refresh()
    end, "Value disenchants without rare procs (the 5% shard on greens, the Nexus Crystal on blues), so you only see what's profitable on the dust and essences you can count on.")
    procCheck.frame:SetPoint("TOPLEFT", x + 256, y - 3)
    recipesButton = UI.Button(c, "", 128, 24, function()
        for i, v in ipairs(RECIPES_VIEW) do
            if v.key == ns.db.recipes then
                ns.db.recipes = RECIPES_VIEW[i % #RECIPES_VIEW + 1].key
                break
            end
        end
        tbl.offset = 0
        ns.Refresh()
    end)
    recipesButton:SetPoint("TOPRIGHT", 0, y)
    UI.Tip(recipesButton, function(tt)
        for _, v in ipairs(RECIPES_VIEW) do
            local on = v.key == ns.db.recipes
            tt:AddLine((on and "> " or "   ") .. v.label .. ": " .. v.hint, on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7, true)
        end
        tt:AddLine(" ")
        tt:AddLine("Click to switch. Recipes you know are picked up when you open your trade skill window. Right-click any row to mark it as had or not.", 1, 1, 1, true)
    end)

    -- Profession tabs (made in refreshTabs).
    tabsHolder = CreateFrame("Frame", nil, c)
    tabsHolder:SetPoint("TOPLEFT", 0, TAB_Y)
    tabsHolder:SetPoint("TOPRIGHT", 0, TAB_Y)
    tabsHolder:SetHeight(24)

    -- The ranked list.
    local cols = {
        { key = "item", label = "Item", w = 196 },
        { key = "skill", label = "Skill", w = 64 },
        { key = "mats", label = "Mat cost", w = 84, justify = "RIGHT" },
        { key = "craft", label = "Craft sells", w = 84, justify = "RIGHT", tip = "What the crafted item(s) sell for, after the 5% auction cut." },
        { key = "de", label = "DE sells", w = 84, justify = "RIGHT", tip = "Average disenchant value of the item(s), after the cut." },
        { key = "listed", label = "Listed", w = 50, justify = "RIGHT",
          tip = "How many of the crafted item are on the auction house: supply, not sales. Lots listed means competition." },
        { key = "best", label = "Best", w = 74 },
        { key = "gain", label = "Profit", w = 0, justify = "RIGHT" },
    }
    tbl = UI.Table(c, cols, 20, {
        icon = true, noSort = true, fontSize = 11,
        onEnter = rowTooltip,
        onClick = function(row, which, r)
            if which ~= "RightButton" then return end
            ns.SetHasRecipe(row.recipe.spell, not row.has)
            ns.Refresh()
            if r:IsShown() and r.data then rowTooltip(r) end
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, TABLE_Y)
    tbl:SetPoint("BOTTOMRIGHT", 0, 22)
    tbl.fill = fillRow
    tbl.onRedraw = function() placeRedLine(); footerText() end
    ns.table = tbl

    local lineHolder = CreateFrame("Frame", nil, tbl)
    lineHolder:SetAllPoints(tbl)
    lineHolder:SetFrameLevel((tbl:GetFrameLevel() or 1) + 5)
    redLine = lineHolder:CreateTexture(nil, "OVERLAY")
    redLine:SetTexture(UI.WHITE)
    redLine:SetHeight(2)
    redLine:SetVertexColor(C.bad[1], C.bad[2], C.bad[3], 0.9)
    redLine:Hide()
    ns.redLine = redLine

    footer = UI.Text(c, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    ns.footer = footer
end

KM.RegisterPage({
    id = PAGE, group = "craft", label = "Crafting Profits", icon = "Interface\\Icons\\INV_Misc_Bag_10", order = 10,
    title = "Crafting Profits",
    subtitle = function()
        if ns.db and ns.db.mode == "farm" then
            return "Ethical Gaming: your own materials. Is crafting worth more than selling them raw?"
        end
        return "Yrgna Special: materials are a cost. What's worth buying the mats for and crafting (flips)?"
    end,
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- The crown and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "market-crafting", label = "Crafting Profits", order = 20, func = function() ns.Toggle(true) end })

local function viewChoices()
    local out = {}
    for _, v in ipairs(RECIPES_VIEW) do out[#out + 1] = { v.key, v.key == "all" and "All" or (v.key == "mine" and "Mine" or v.label) } end
    return out
end

KM.RegisterSettings({ id = "market", label = "Market", order = 20, rows = {
    { type = "header", label = "Crafting Profits" },
    { type = "choice", label = "Count materials as", options = { { "buy", "Yrgna Special" }, { "farm", "Ethical Gaming" } },
      get = function() return ns.db.mode end, set = function(v) ns.db.mode = v; ns.Refresh() end },
    { type = "text", label = "Yrgna Special: you buy the materials, so they're a cost (flips). Ethical Gaming: you gathered them, so crafting is compared with selling them raw. Vendor reagents are a cost either way." },
    { type = "check", label = "Include disenchanting", tip = "Count crafting, disenchanting and selling the enchanting materials as an option.",
      get = function() return ns.db.includeDE end, set = function(v) ns.db.includeDE = v; ns.Refresh() end },
    { type = "check", label = "Disenchanting only", tip = "Show only items that can be disenchanted.",
      get = function() return ns.db.deOnly end, set = function(v) ns.db.deOnly = v; ns.Refresh() end },
    { type = "check", label = "No procs (disenchanting only)", tip = "Value disenchants without the rare shard and crystal procs.",
      get = function() return ns.db.deNoProcs end, set = function(v) ns.db.deNoProcs = v; ns.Refresh() end },
    { type = "choice", label = "Recipes to show", options = viewChoices(),
      get = function() return ns.db.recipes end, set = function(v) ns.db.recipes = v; ns.Refresh() end },
    { type = "button", label = "Clear my have/don't-have marks", func = function() SlashCmdList.MARKETKING("recipes reset") end,
      tip = "Back to what your trade skill windows show, for this character." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/mk   open Crafting Profits\n/mk scan   Market Scan (at the auction house)\n/mk mode buy|farm   Yrgna Special or Ethical Gaming\n"
        .. "/mk recipes all|mine|missing   which recipes to show\n/mk recipes reset   clear your have/don't-have marks" },
} })
