local _, KM = ...
local ns = KM.Module("Market")
local UI = KM.UI
local C = UI.C

-- The Crafting Profits page of the King Maker window (Crafting > Crafting Profits).
--   Top:    profession tabs (All, then one per profession: which to show and price), Scan (the Scanner's one scan,
--           at the auction house). With every profession lit, clicking one shows just it; after that each click turns
--           a profession on or off (ns.ClickProf). All lights them all again.
--   Then:   Buy mats (the materials are a cost) or Use my mats (you already have them), disenchanting options, and
--           Hide unlearned (otherwise patterns you don't have show greyed out).
--   Search: only items whose name has the typed text in it, anywhere (not saved).
--   List:   most profitable first, with a red line where crafting stops beating selling the raw materials.
--           Hover a row for the full breakdown; right-click it to mark the recipe as had or not had.
-- Also here: the crown's quick action and the Settings section.

local PAGE = "crafting"
local ROW2_Y, SEARCH_Y, TABLE_Y = -32, -64, -96

local page, tbl, footer, redLine, profTabs, allTab, modeButtons, deCheck, deOnlyButton, procCheck, hideCheck, search
local query = ""          -- the search box's text; this session only
local multi = true        -- more than one profession showing: the Skill column names the profession
local shown, above = {}, 0

local MODES = {
    buy = { label = ns.MODE_LABELS.buy, hint = "The materials are a cost: what's worth buying the mats for and crafting (flips)." },
    farm = { label = ns.MODE_LABELS.farm, hint = "You already have the materials (farmed or bought earlier): is crafting worth more than selling them raw? Vendor reagents are still a cost." },
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
    -- a recipe with a crafting cooldown (Cooldowns module) can't be made at will: a violet "CD 4d" tag says so
    local cd = row.recipe and CooldownKing and CooldownKing.Length and KM.Safe(CooldownKing.Length, row.recipe.spell)
    local cdTag = cd and (UI.Hex(C.violet) .. "  CD " .. (cd >= 86400 and (math.floor(cd / 86400 + 0.5) .. "d") or (math.floor(cd / 3600 + 0.5) .. "h")) .. "|r") or ""
    cells.item:SetText("|cff" .. color .. ns.ItemName(row.item) .. "|r" .. (row.made > 1 and (" x" .. row.made) or "") .. cdTag)
    local p = ns.PROF_BY_ID[row.prof]
    cells.skill:SetText((multi and p and (p.name:sub(1, 4) .. " ") or "") .. (row.skill > 0 and row.skill or ""))
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
    r:SetAlpha(row.has and 1 or 0.45)
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
    local n = math.min(#shown, tbl.visible or #shown)
    footer:SetText(#shown .. " recipes, " .. above .. " beat " .. (mode == "farm" and "selling raw" or "not crafting")
        .. " (above the red line).  Prices from " .. (last and ScannerKing.PriceAge(last) or "no scan yet")
        .. (#shown > n and ".  Scroll for more." or "."))
end

local function refreshControls()
    local db = ns.db
    for key, b in pairs(modeButtons) do b:SetActive(key == db.mode) end
    deCheck:SetChecked(db.includeDE)
    deCheck.label:SetTextColor(db.deOnly and C.dim[1] or C.text[1], db.deOnly and C.dim[2] or C.text[2], db.deOnly and C.dim[3] or C.text[3])
    deOnlyButton:SetActive(db.deOnly)
    procCheck:SetChecked(db.deNoProcs)
    procCheck.frame:SetShown(db.deOnly)
    hideCheck:SetChecked(db.recipes == "mine")
    allTab:SetActive(ns.AllSelected())
    for id, b in pairs(profTabs) do b:SetActive(ns.Selected(id)) end
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
    if not next(ns.db.profs) then ns.SelectAll() end
    refreshControls()
    setHeaders()
    local db = ns.db
    local count = 0
    for _, p in ipairs(ns.PROFESSIONS) do if ns.Selected(p.id) then count = count + 1 end end
    multi = count > 1
    shown, above = ns.Rank(nil, db.mode, { noDE = not db.includeDE and not db.deOnly, deOnly = db.deOnly,
        noProcs = db.deOnly and db.deNoProcs, recipes = db.recipes, search = query })
    tbl.emptyText = query:match("%S") and ("No item names with \"" .. query .. "\" in them for these professions and filters.")
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
        KM.Print(ns, "Scanning needs the Scanner module.")
    end
end

function ns.CurrentRows() return shown, above end
function ns.Page() return page end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function buildPage(c)
    page = c

    -- Profession tabs: All, then one per profession (short names so they fit; the tip has the full one).
    local function tabTip(b, text)
        UI.Tip(b, function(tt)
            tt:AddLine(text, 1, 1, 1)
            tt:AddLine("With every profession lit, clicking one shows just it. After that, each click adds or removes a "
                .. "profession. All lights them all again. Scan prices the lit ones.", 0.7, 0.7, 0.7, true)
        end)
    end
    allTab = UI.Button(c, "All", 54, 24, function() ns.SelectAll(); tbl.offset = 0; ns.Refresh() end, "ghost")
    allTab:SetPoint("TOPLEFT", 0, 0)
    tabTip(allTab, "Every profession")
    local x = 53
    profTabs = {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local w = math.max(62, 18 + 7 * #p.short)
        local b = UI.Button(c, p.short, w, 24, function() ns.ClickProf(p.id); tbl.offset = 0; ns.Refresh() end, "ghost")
        b:SetPoint("TOPLEFT", x, 0)
        b.prof = p.id
        tabTip(b, p.name)
        profTabs[p.id] = b
        x = x + w - 1
    end
    local scan = UI.Button(c, "Scan", 90, 24, function() ns.OpenMarketScan() end, "primary")
    scan:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(scan, "At the auction house: King Maker's one Scan. A full scan when the game allows one (every 15 minutes), "
        .. "otherwise a quick scan of Trade Goods plus everything the lit professions make and use.")

    -- How to count, disenchanting, unlearned recipes.
    local y = ROW2_Y
    modeButtons = {}
    x = 0
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
    hideCheck = UI.CheckLabel(c, "Hide unlearned", function(on)
        ns.db.recipes = on and "mine" or "all"
        tbl.offset = 0
        ns.Refresh()
    end, function(tt)
        tt:AddLine("Hide recipes you don't have. Off, they show greyed out, so you can see which patterns are worth getting.", 1, 1, 1, true)
        tt:AddLine("Trainer recipes always count as yours; patterns count once you open that profession's window. "
            .. "Right-click any row to mark it as had or not.", 0.7, 0.7, 0.7, true)
    end)
    hideCheck.frame:SetPoint("TOPRIGHT", 0, y - 3)

    -- Search: item names with the text anywhere in them.
    search = UI.EditBox(c, 260, 24, "Search items (any part of the name)", function(text)
        text = text or ""
        if text == query then return end
        query = text
        tbl.offset = 0
        ns.Refresh()
    end)
    search:SetPoint("TOPLEFT", 0, SEARCH_Y)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    UI.Tip(search, "Type part of an item's name: \"cloak\" finds every cloak, \"iron\" finds Iron Buckle and Green Iron "
        .. "Bracers. Escape clears it.")
    ns.search = search

    -- The ranked list.
    local function farm() return ns.db.mode == "farm" end
    local cols = {
        { key = "item", label = "Item", w = 196,
          tip = "Greyed out: a pattern you don't have. A violet CD tag: the recipe has a cooldown (how long), so you can't make it at will. Hover a row for every figure behind it." },
        { key = "skill", label = "Skill", w = 64, tip = "The skill the recipe needs. With more than one profession showing, the profession comes first, cut to four letters." },
        { key = "mats", label = "Mat cost", w = 84, justify = "RIGHT", tip = function(tt)
            if farm() then
                tt:AddLine("Raw value: what the auction-house materials would sell for raw, at the lowest buyout after the 5% cut. Vendor reagents aren't in it: they come off the profit instead.", 1, 1, 1, true)
            else
                tt:AddLine("What the materials cost, each at the cheaper of the lowest buyout and a vendor. \"missing\": a material has no price yet.", 1, 1, 1, true)
            end
        end },
        { key = "craft", label = "Craft sells", w = 84, justify = "RIGHT", tip = "What the crafted item(s) sell for: the lowest buyout times how many one craft makes, after the 5% auction cut." },
        { key = "de", label = "DE sells", w = 84, justify = "RIGHT", tip = "Average disenchant value of the item(s), after the cut." },
        { key = "listed", label = "Listed", w = 50, justify = "RIGHT",
          tip = "How many of the crafted item are on the auction house: supply, not sales. Lots listed means competition." },
        { key = "best", label = "Best", w = 74, tip = function(tt)
            tt:AddLine("The best thing to do with the materials:", 1, 1, 1, true)
            tt:AddDoubleLine("CRAFT", "craft it and sell it", C.good[1], C.good[2], C.good[3], 1, 1, 1)
            tt:AddDoubleLine("DISENCHANT", "craft it, disenchant it, sell the mats", C.violet[1], C.violet[2], C.violet[3], 1, 1, 1)
            if farm() then
                tt:AddDoubleLine("SELL RAW", "crafting doesn't beat selling the mats", C.warn[1], C.warn[2], C.warn[3], 1, 1, 1)
            else
                tt:AddDoubleLine("SKIP", "crafting it loses money", C.dim[1], C.dim[2], C.dim[3], 1, 1, 1)
            end
            tt:AddDoubleLine("?", "a material has no price yet", C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
        end },
        { key = "gain", label = "Profit", w = 0, justify = "RIGHT", tip = function(tt)
            if farm() then
                tt:AddLine("Gain vs raw: the better of Craft sells and DE sells, minus vendor reagents, minus what the materials would fetch sold raw. Above zero, crafting beats selling them.", 1, 1, 1, true)
            else
                tt:AddLine("The better of Craft sells and DE sells, minus the material cost. Above zero, buying the mats and crafting makes money.", 1, 1, 1, true)
            end
            tt:AddLine("The list is sorted by it; the red line sits under the last row worth doing.", 0.7, 0.7, 0.7, true)
        end },
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
            return "Use my mats: is crafting worth more than selling your materials raw?"
        end
        return "Buy mats: the materials are a cost. What's worth buying the mats for and crafting (flips)?"
    end,
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- The crown and Settings
---------------------------------------------------------------------------

-- Your profession skills, on one line under the crown's title (2.9: was Skill-ups').
KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local parts = {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local cur, max = ns.Skill(p.id)
        if cur > 0 then parts[#parts + 1] = (p.id == 7 and "Mining" or p.name) .. " " .. cur .. "/" .. max end
    end
    if #parts > 0 then tt:AddLine("Skills: " .. table.concat(parts, ", "), 1, 1, 1, true) end
end)

KM.RegisterQuickAction({ id = "market-crafting", label = "Crafting Profits", order = 20, func = function() ns.Toggle(true) end })

KM.RegisterSettings({ id = "market", label = "Market", order = 20, rows = {
    { type = "header", label = "Crafting Profits" },
    { type = "choice", label = "Count materials as", options = { { "buy", MODES.buy.label, MODES.buy.hint }, { "farm", MODES.farm.label, MODES.farm.hint } },
      get = function() return ns.db.mode end, set = function(v) ns.db.mode = v; ns.Refresh() end },
    { type = "text", label = "Buy mats: you buy the materials, so they're a cost (flips). Use my mats: you already have them, so crafting is compared with selling them raw. Vendor reagents are a cost either way." },
    { type = "check", label = "Include disenchanting", tip = "Count crafting, disenchanting and selling the enchanting materials as an option.",
      get = function() return ns.db.includeDE end, set = function(v) ns.db.includeDE = v; ns.Refresh() end },
    { type = "check", label = "Disenchanting only", tip = "Show only items that can be disenchanted.",
      get = function() return ns.db.deOnly end, set = function(v) ns.db.deOnly = v; ns.Refresh() end },
    { type = "check", label = "No procs (disenchanting only)", tip = "Value disenchants without the rare shard and crystal procs.",
      get = function() return ns.db.deNoProcs end, set = function(v) ns.db.deNoProcs = v; ns.Refresh() end },
    { type = "check", label = "Hide unlearned recipes", tip = "Show only trainer recipes and the patterns you have. Off: every recipe, the ones you don't have greyed out.",
      get = function() return ns.db.recipes == "mine" end, set = function(v) ns.db.recipes = v and "mine" or "all"; ns.Refresh() end },
    { type = "button", label = "Clear my have/don't-have marks", func = function() SlashCmdList.MARKETKING("recipes reset") end,
      tip = "Back to what your trade skill windows show, for this character." },
    { type = "header", label = "Recipe data" },
    { type = "text", label = "Every WoW: Forever recipe and its reagents: data from ForeverDB.net (foreverdb.net, GPL-3.0)." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/mk   open Crafting Profits\n/mk scan   Scan (at the auction house): prices the lit professions\n/mk mode buy|mine   Buy mats or Use my mats\n"
        .. "/mk recipes all|mine   show every recipe, or hide unlearned\n/mk recipes reset   clear your have/don't-have marks" },
} })
