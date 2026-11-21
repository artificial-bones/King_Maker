local _, KM = ...
local ns = KM.Module("Profession")

-- The panel docked to the profession window: a "This recipe" card (money first) for the selected recipe and an
-- "All crafts" table of every recipe you know, with the Buy mats / Use my mats switch in its header.
-- Our own frame, parented to UIParent and anchored beside the game's window; it never touches that window.

local UI = KM.UI
local C = UI.C
local W, HEAD, CW = 460, 30, 440   -- panel width, header height, content width
local MIN_H, MAX_H = 420, 720
local LINES = 12                    -- money lines on the card
local TOOLBAR, FOOTER = 32, 24      -- All crafts: the search row above the table, the price-age line under it
local DASH = "|cff808080-|r"

local panel, body, tabs, modeTabs, collapseBtn, summary, emptyFS
local card, all = {}, {}
local lastKey, elapsed = nil, 0
ns.ui = { card = card, all = all } -- for the tests

-- 12345 -> "1g 23s" (two units at most, so money fits a narrow column).
local function short(c)
    if c == nil then return DASH end
    c = math.floor(c + 0.5)
    local neg = c < 0
    if neg then c = -c end
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out
    if g > 0 then out = KM.Commas(g) .. "|cffffd700g|r" .. (s > 0 and (" " .. s .. "|cffc7c7cfs|r") or "")
    elseif s > 0 then out = s .. "|cffc7c7cfs|r" .. (k > 0 and (" " .. k .. "|cffeda55fc|r") or "")
    else out = k .. "|cffeda55fc|r" end
    return neg and ("|cffff5050-|r" .. out) or out
end
ns.Short = short

local function signed(c, fmt)
    if c == nil then return DASH end
    fmt = fmt or KM.Money
    if c > 0 then return UI.Hex(C.good) .. "+|r" .. fmt(c) end
    return fmt(c)
end

local function pct(x)
    if not x then return DASH end
    local p = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
    local col = p > 0 and C.good or (p < 0 and C.bad or C.muted)
    return UI.Hex(col) .. (p > 0 and "+" or "") .. p .. "%|r"
end

local function dim(s) return UI.Hex(C.dim) .. s .. "|r" end

local function at(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", region.anchorTo or card.child, "TOPLEFT", x, y)
end

-- The verdict words, for the pill's and the Do column's tooltips.
local function verdictLines(tt)
    local function line(word, text)
        local v = ns.VERDICTS[word]
        local c = C[v[2]] or C.muted
        tt:AddDoubleLine(v[1] .. (v[3] ~= v[1] and ("  (" .. v[3] .. ")") or ""), text, c[1], c[2], c[3], 1, 1, 1)
    end
    line("craft", "craft it and sell it")
    line("disenchant", "craft it, disenchant it, sell the mats")
    line("sellraw", ns.ModeLabel("farm") .. ": selling the mats raw pays more")
    line("skip", ns.ModeLabel("buy") .. ": crafting it loses money")
    line("noprice", "a material or the item has no price yet")
end

local function verdictText(word, useShort)
    local v = word and ns.VERDICTS[word]
    if not v then return "" end
    return UI.Hex(C[v[2]] or C.muted) .. (useShort and v[3] or v[1]) .. "|r"
end

local function verdictPill(pill, word)
    local v = word and ns.VERDICTS[word]
    if not v then pill:Hide(); return end
    pill:SetWidth(math.max(46, 12 + 6 * #v[1]))
    pill:SetCustom(v[1], C[v[2]] or C.muted)
end

local function modeTip(mode)
    if mode == "farm" then
        return "You already have the materials: a craft has to beat selling them raw. Vendor reagents are still a cost."
    end
    return "Materials are a cost: a craft has to make more than you pay for them."
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildCard(parent)
    local sc = UI.Scroll(parent)
    sc:SetPoint("TOPLEFT", 10, -6)
    sc:SetPoint("BOTTOMRIGHT", -10, 8)
    card.scroll, card.child = sc, sc.child
    local ch = sc.child
    ch:SetWidth(CW)

    card.icon = ch:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(32, 32)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.name = UI.Text(ch, 13, C.text)
    card.name:SetWidth(CW - 40)
    card.sub = UI.Text(ch, 10, C.muted)
    card.sub:SetWidth(CW - 40)

    -- the headline: profit per craft, the verdict, the margin
    card.profit = UI.Text(ch, 18, C.text)
    card.profit:SetWidth(200)
    card.profitHover = CreateFrame("Frame", nil, ch)
    card.profitHover:SetAllPoints(card.profit)
    UI.Tip(card.profitHover, function(tt)
        local mode = ns.Mode()
        tt:AddLine("Profit per craft, " .. ns.ModeLabel(mode), 1, 0.82, 0)
        if mode == "farm" then
            tt:AddLine("The better of selling the craft or disenchanting it (after the 5% cut), minus vendor reagents, minus what the materials would fetch raw.", 1, 1, 1, true)
        else
            tt:AddLine("The better of selling the craft or disenchanting it (after the 5% cut), minus what the materials cost.", 1, 1, 1, true)
        end
    end)
    card.pill = UI.Pill(ch)
    UI.Tip(card.pill, function(tt)
        local mode = ns.Mode()
        tt:AddLine(ns.ModeLabel(mode), 1, 0.82, 0)
        tt:AddLine(modeTip(mode), 1, 1, 1, true)
        verdictLines(tt)
    end)
    card.margin = UI.Text(ch, 12, C.text, "RIGHT")
    card.margin:SetWidth(130)
    card.marginHover = CreateFrame("Frame", nil, ch)
    card.marginHover:SetAllPoints(card.margin)
    UI.Tip(card.marginHover, "Margin: the profit over what the materials cost you (Use my mats: what they'd fetch raw, plus vendor reagents).")
    card.other = UI.Text(ch, 10, C.dim)
    card.other:SetWidth(CW)

    card.craftsLabel = UI.Text(ch, 11, C.muted)
    card.craftsLabel:SetText("Crafts")
    card.minus = UI.Button(ch, "-", 20, 18, function() ns.SetCrafts((ns.db.crafts or 1) - (IsShiftKeyDown and IsShiftKeyDown() and 5 or 1)) end)
    card.count = UI.Text(ch, 12, C.accent, "CENTER")
    card.count:SetWidth(34)
    card.plus = UI.Button(ch, "+", 20, 18, function() ns.SetCrafts((ns.db.crafts or 1) + (IsShiftKeyDown and IsShiftKeyDown() and 5 or 1)) end)
    UI.Tip(card.minus, "Materials for fewer crafts (shift: 5 at a time).")
    UI.Tip(card.plus, "Materials for this many crafts (shift: 5 at a time).")

    card.mats = UI.Table(ch, {
        { key = "name", label = "Reagent", w = 140 },
        { key = "need", label = "Need", w = 40, justify = "RIGHT" },
        { key = "have", label = "Have", w = 56, justify = "RIGHT",
          tip = "How many this character has in bags and bank: green when it's enough. Grey +n: more on your other characters." },
        { key = "each", label = "Each", w = 80, justify = "RIGHT",
          tip = "One, at the cheaper of the lowest buyout and a vendor (v: the vendor's price)." },
        { key = "line", label = "Cost", w = 0, justify = "RIGHT" },
    }, 18, { icon = true, fontSize = 11, noSort = true })
    card.mats:SetWidth(CW)
    card.mats.emptyText = "No reagents."

    card.lines = {}
    for i = 1, LINES do
        local l = UI.Text(ch, 11, C.muted)
        l:SetWidth(170)
        local v = UI.Text(ch, 11, C.text, "RIGHT")
        v:SetWidth(CW - 170)
        -- a hover area over the label; drawCard sets its tip for the line it shows
        local hover = CreateFrame("Frame", nil, ch)
        hover:SetAllPoints(l)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card.lines[i] = { l = l, v = v, hover = hover }
    end

    -- sparkline: up to 30 bars drawn with the white texture
    card.spark = CreateFrame("Frame", nil, ch)
    card.spark:SetSize(CW, 30)
    card.spark.bg = UI.Fill(card.spark, { 0, 0, 0, 0.25 })
    card.spark.bars = {}
    for i = 1, 30 do
        local t = card.spark:CreateTexture(nil, "ARTWORK")
        t:SetTexture(UI.WHITE)
        UI.SetColor(t, { C.accent[1], C.accent[2], C.accent[3], 0.7 })
        t:Hide()
        card.spark.bars[i] = t
    end
    card.sparkLabel = UI.Text(ch, 9, C.dim)

    card.fav = UI.Button(ch, "", 26, 22, function() ns.ToggleFavorite() end)
    card.fav.icon = card.fav:CreateTexture(nil, "OVERLAY")
    card.fav.icon:SetSize(14, 14)
    card.fav.icon:SetPoint("CENTER", 0, 0)
    card.fav.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    UI.Tip(card.fav, "Favorite in Price History (Econ).")
    card.hist = UI.Button(ch, "History", 66, 22, function() ns.OpenHistory() end)
    UI.Tip(card.hist, "Open this item in Price History.")

    emptyFS = UI.Para(parent, 12, C.dim, CW - 20)
    emptyFS:SetPoint("TOP", 0, -40)
    emptyFS:SetJustifyH("CENTER")
end

local function buildAll(parent)
    all.frame = CreateFrame("Frame", nil, parent)
    all.frame:SetAllPoints(parent)
    local f = all.frame
    all.search = UI.EditBox(f, 150, 20, "Search", function(text, user)
        if not user then return end
        ns.db.search = text or ""
        ns.Refresh()
    end)
    all.search:SetPoint("TOPLEFT", 10, -6)
    all.search:SetText(ns.db.search or "")
    UI.Tip(all.search, "Only recipes whose item name has this in it.")
    all.canMake = UI.CheckLabel(f, "Can make now", function(on)
        ns.db.canMake = on and true or false
        ns.Refresh()
    end, "Only recipes your materials cover at least once.")
    all.canMake.frame:SetPoint("TOPLEFT", 172, -7)
    all.prof = UI.Text(f, 10, C.dim, "RIGHT")
    all.prof:SetPoint("TOPRIGHT", -10, -10)
    all.prof:SetWidth(150)

    all.tbl = UI.Table(f, {
        { key = "name", label = "Item", w = 90, desc = false, sort = function(r) return (r.name or ""):lower() end },
        { key = "gain", label = "Profit", w = 56, justify = "RIGHT", sort = function(r) return r.gain end, tip = function(tt)
            if ns.Mode() == "farm" then
                tt:AddLine("One craft, " .. ns.ModeLabel("farm") .. ": the better of selling the craft or disenchanting it (after the 5% cut), minus vendor reagents, minus what the mats would fetch raw.", 1, 1, 1, true)
            else
                tt:AddLine("One craft, " .. ns.ModeLabel("buy") .. ": the better of selling the craft or disenchanting it (after the 5% cut), minus the materials.", 1, 1, 1, true)
            end
        end },
        { key = "margin", label = "Margin", w = 42, justify = "RIGHT", sort = function(r) return r.margin end,
          tip = "Profit over what the materials cost you." },
        { key = "can", label = "Can make", w = 44, justify = "RIGHT", sort = function(r) return r.can end,
          tip = "How many crafts the materials in your bags cover (the game's count when it gives one)." },
        { key = "listed", label = "Listed", w = 38, justify = "RIGHT", sort = function(r) return r.listed end,
          tip = "How many are on the auction house now (your last scan)." },
        { key = "make", label = "Make", w = 34, justify = "RIGHT", sort = function(r) return r.make end,
          tip = "How many to craft to sell: a quarter of what's listed, and no more than one day of units leaving the auction house. Nothing listed: make 1 to test the market." },
        { key = "now", label = "Profit now", w = 60, justify = "RIGHT", sort = function(r) return r.now end,
          tip = "What crafting it makes you now: profit each times Make. Disenchant: one craft. Nothing for sell raw or skip." },
        { key = "verdict", label = "Do", w = 0, justify = "RIGHT", sort = function(r) return ns.VORDER[r.verdict] end,
          tip = function(tt) verdictLines(tt) end },
    }, 18, { icon = true, fontSize = 11, onClick = function(row) ns.Pin(row.spell) end,
        onSort = function(key, desc) ns.db.sortKey, ns.db.sortDesc = key, desc and true or false end })
    all.tbl:SetPoint("TOPLEFT", 10, -TOOLBAR)
    all.tbl:SetSize(CW, MIN_H - HEAD - TOOLBAR - FOOTER)
    all.tbl:SetSort(ns.db.sortKey, ns.db.sortDesc)
    all.foot = UI.Text(f, 10, C.dim)
    all.foot:SetPoint("BOTTOMLEFT", 10, 8)
    all.foot:SetWidth(CW)
end

local function setCollapsed(on)
    ns.db.collapsed = on and true or false
    collapseBtn:SetLabel(ns.db.collapsed and "+" or "-")
    body:SetShown(not ns.db.collapsed)
    tabs:SetShown(not ns.db.collapsed)
    modeTabs:SetShown(not ns.db.collapsed)
    summary:SetShown(ns.db.collapsed)
    ns.Place()
    ns.Refresh()
end

local function build()
    if panel then return end
    panel = CreateFrame("Frame", "KingMakerProfessionPanel", UIParent)
    panel:SetSize(W, MIN_H)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    UI.Fill(panel, C.bg)
    UI.Border(panel, { 1, 1, 1, 0.10 })
    UI.GoldEdge(panel)
    panel:Hide()

    local title = UI.Text(panel, 12, C.accent)
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("King Maker")
    tabs = UI.Tabs(panel, { { id = "card", label = "This recipe", w = 78 }, { id = "all", label = "All crafts", w = 72 } }, function(id)
        ns.db.tab = id
        ns.Refresh()
    end, 20)
    tabs:SetPoint("TOPLEFT", 88, -5)
    UI.Tip(tabs.buttons.card, "The selected recipe: what it makes you and what it needs.")
    UI.Tip(tabs.buttons.all, "Every recipe you know in this profession, ranked by what you'd make now.")
    modeTabs = UI.Tabs(panel, { { id = "buy", label = ns.ModeLabel("buy"), w = 64 }, { id = "farm", label = ns.ModeLabel("farm"), w = 80 } },
        function(id) ns.SetMode(id) end, 20)
    modeTabs:SetPoint("TOPLEFT", 244, -5)
    for _, id in ipairs({ "buy", "farm" }) do
        UI.Tip(modeTabs.buttons[id], function(tt)
            tt:AddLine(ns.ModeLabel(id), 1, 0.82, 0)
            tt:AddLine(modeTip(id), 1, 1, 1, true)
            if ns.db.mode == "market" then
                tt:AddLine("Changes Crafting Profits' mode too (Settings > Profession window follows it).", 0.7, 0.7, 0.7, true)
            end
        end)
    end
    summary = UI.Text(panel, 11, C.text)
    summary:SetPoint("TOPLEFT", 88, -9)
    summary:SetWidth(W - 126)
    summary:Hide()
    collapseBtn = UI.Button(panel, "-", 20, 20, function() setCollapsed(not ns.db.collapsed) end)
    collapseBtn:SetPoint("TOPRIGHT", -6, -5)
    UI.Tip(collapseBtn, "Collapse or expand the King Maker panel.")

    body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 0, -HEAD)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    card.frame = CreateFrame("Frame", nil, body)
    card.frame:SetAllPoints(body)
    buildCard(card.frame)
    buildAll(body)

    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < ns.CHECK_EVERY then return end
        elapsed = 0
        ns.Poll()
    end)
    ns.panel = panel
    setCollapsed(ns.db.collapsed)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawSpark(vals, y)
    local s = card.spark
    if not vals or #vals < 2 then
        s:Hide(); card.sparkLabel:Hide()
        return y
    end
    local lo, hi = math.huge, -math.huge
    for _, v in ipairs(vals) do lo = math.min(lo, v); hi = math.max(hi, v) end
    local n = #vals
    local bw = math.floor(CW / n)
    for i, t in ipairs(s.bars) do
        local v = vals[i]
        if v then
            local frac = hi > lo and (v - lo) / (hi - lo) or 0.5
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", (i - 1) * bw, 0)
            t:SetSize(math.max(1, bw - 1), 3 + frac * 26)
            t:Show()
        else
            t:Hide()
        end
    end
    at(card.sparkLabel, 0, y)
    card.sparkLabel:SetText("PRICE, LAST " .. n .. " POINTS   " .. short(lo) .. " - " .. short(hi))
    card.sparkLabel:Show()
    at(s, 0, y - 13)
    s:Show()
    return y - 13 - 34
end

-- The money lines under the reagents: { label, value, tip }.
local function moneyLines(c)
    local rows = {}
    local function add(l, v, tip) rows[#rows + 1] = { l, v, tip } end
    add(c.crafts > 1 and ("Materials (x" .. c.crafts .. ")") or "Materials",
        c.missingPrice and (UI.Hex(C.bad) .. "no price for " .. ns.ItemText(c.missingPrice) .. "|r") or KM.Money(c.costAll),
        "The reagents for the crafts above, each at the cheaper of the lowest buyout and a vendor.")
    if not c.item then
        add("Sells for", dim("an enchant: nothing to sell"))
        return rows
    end
    add("Sells for, after the 5% cut", (c.sale and KM.Money(c.sale) or DASH)
        .. (c.made > 1 and dim(" for " .. c.made) or "") .. (c.marketReal and c.market and dim("  (market " .. short(c.market) .. " each)") or ""),
        "Everything one craft makes at the lowest buyout, minus the auction house's 5%. In grey: the market price from a full scan.")
    if c.de then
        add("Disenchant instead", (c.deSale and KM.Money(c.deSale) or DASH) .. dim("  (" .. short(c.de) .. " a disenchant)"),
            "What one craft's disenchant materials fetch after the 5% cut, on average; in grey, one disenchant's worth.")
    end
    add("30-day avg  /  7-day trend", KM.Money(c.avg30) .. "  /  " .. pct(c.trend7),
        "From Price History: the average market price over 30 days, and this week's average against last week's.")
    add("Listed  /  lowest", (c.listed and KM.Commas(c.listed) or DASH) .. dim("  /  ") .. KM.Money(c.lowest),
        "How many were on the auction house at your last scan, and the cheapest buyout.")
    if c.gone then
        add("Sells a day", "~" .. (c.gone >= 10 and KM.Commas(math.floor(c.gone + 0.5)) or string.format("%.1f", c.gone)),
            "Units leaving the auction house a day over the last week (Price History). It counts cancels and expiries too, so real sales are a bit lower.")
    end
    if c.make then
        local v = c.verdict and c.verdict[c.mode]
        local extra = (v == "craft" and c.head) and (dim("  (") .. signed(c.head * c.make, short) .. dim(" if they all sell)")) or ""
        add("Make", tostring(c.make) .. extra,
            "How many to craft so you don't flood the auction house: a quarter of what's listed, and no more than one day of units leaving it. Nothing listed: make 1 to test the market.")
    end
    -- a crafting cooldown (Cooldowns module): ready or time left, and what it's worth a week at that pace
    local cdText = c.spell and CooldownKing and CooldownKing.PanelText and KM.Safe(CooldownKing.PanelText, c.spell, c.profit)
    if cdText then add("Cooldown", cdText, "The recipe has a cooldown: READY or how long is left, and what it makes in a week if you craft it every time it's ready.") end
    if c.paid then
        add("At what you paid", signed(c.paid.profit) .. dim("  (" .. c.paid.covered .. " of " .. c.paid.units .. " mats from your stock)"),
            "Profit & Loss: one craft's profit with the materials you hold counted at what you paid for them (farmed ones by P&L's farmed setting), the rest at today's price.")
    end
    if c.sales then
        local s = c.sales
        add("Your last sales", s.q > 0 and (KM.Commas(s.q) .. " sold" .. dim(", avg ") .. KM.Money(s.each) .. dim(" each")) or dim("none in 7 days"),
            "Profit & Loss: how many you sold in the last 7 days and what they brought each after the 5% cut.")
    end
    return rows
end

local function drawCard()
    local sel = ns.Selection()
    local c = sel and ns.Card(sel)
    ns.card = c
    card.scroll:SetShown(c ~= nil)
    if not c then
        emptyFS:SetText(ns.Active() and "Pick a recipe in the profession window." or "Open a profession window.")
        emptyFS:Show()
        summary:SetText("|cff808080no recipe selected|r")
        return
    end
    emptyFS:Hide()
    local mode = c.mode
    local y = 0
    at(card.icon, 0, y)
    card.icon:SetTexture(c.icon)
    at(card.name, 40, y - 2)
    card.name:SetText(c.item and ns.ItemText(c.item, c.name) or (UI.Hex(C.accent) .. c.name .. "|r"))
    at(card.sub, 40, y - 19)
    local subParts = {}
    local pname = c.prof and ns.ProfName(c.prof)
    if pname then subParts[#subParts + 1] = pname .. (c.skill and (" " .. c.skill .. (c.maxSkill and ("/" .. c.maxSkill) or "")) or "") end
    if c.made > 1 then subParts[#subParts + 1] = "makes " .. c.made end
    if c.source == "data" then subParts[#subParts + 1] = "picked in All crafts" end
    card.sub:SetText(table.concat(subParts, "  |cff505050/|r  "))
    y = y - 40

    -- headline
    at(card.profit, 0, y)
    at(card.pill, 206, y - 3)
    at(card.margin, CW - 130, y - 3)
    local v = c.verdict and c.verdict[mode]
    if c.item then
        local col = (c.head or 0) > 0 and C.good or ((c.head or 0) < 0 and C.bad or C.muted)
        card.profit:SetText(c.head and (UI.Hex(col) .. (c.head > 0 and "+" or "") .. "|r" .. KM.Money(c.head)) or DASH)
        verdictPill(card.pill, v)
        card.margin:SetText(c.margin and (dim("margin ") .. pct(c.margin)) or "")
        local other = mode == "farm" and "buy" or "farm"
        local ov = c.verdict and c.verdict[other]
        card.other:SetText("per craft, " .. ns.ModeLabel(mode) .. (ov and ("   |cff505050/|r   " .. ns.ModeLabel(other) .. ": " .. verdictText(ov)) or ""))
    else
        card.profit:SetText(c.missingPrice and DASH or KM.Money(c.cost))
        card.pill:Hide()
        card.margin:SetText("")
        card.other:SetText("materials per craft: an enchant, nothing to sell")
    end
    y = y - 24
    at(card.other, 0, y)
    y = y - 20

    at(card.craftsLabel, 0, y - 3)
    at(card.minus, 44, y)
    card.count:ClearAllPoints()
    card.count:SetPoint("LEFT", card.minus, "RIGHT", 2, 0)
    card.count:SetText(tostring(c.crafts))
    card.plus:ClearAllPoints()
    card.plus:SetPoint("LEFT", card.count, "RIGHT", 2, 0)
    y = y - 26

    local th = 20 + 18 * math.max(1, #c.mats)
    at(card.mats, 0, y)
    card.mats:SetHeight(th)
    card.mats:Layout()
    card.mats:SetRows(c.mats, function(r, m, cells)
        r.item = m.id
        if r.icon then r.icon:SetTexture(ns.ItemInfo(m.id).icon) end
        cells.name:SetText(ns.ItemText(m.id))
        cells.need:SetText(tostring(m.need))
        local ok = (m.have or 0) >= m.need
        cells.have:SetText(UI.Hex(ok and C.good or C.bad) .. tostring(m.have or 0) .. "|r" .. ((m.alts or 0) > 0 and UI.Hex(C.dim) .. "+" .. m.alts .. "|r" or ""))
        cells.each:SetText(short(m.unit) .. (m.vendor and UI.Hex(C.dim) .. " v|r" or ""))
        cells.line:SetText(short(m.line))
    end)
    y = y - th - 8

    local rows = moneyLines(c)
    for i, l in ipairs(card.lines) do
        local r = rows[i]
        if r then
            at(l.l, 0, y); at(l.v, 170, y)
            l.l:SetText(r[1]); l.v:SetText(r[2])
            l.l:Show(); l.v:Show()
            l.hover.tip = r[3]; l.hover:Show()
            y = y - 16
        else
            l.l:Hide(); l.v:Hide(); l.hover:Hide()
        end
    end
    y = y - 8

    y = drawSpark(c.history, y)

    local x = 0
    local canFav = c.item and EconKing and EconKing.IsFavorite and KM.mods.Econ and KM.mods.Econ.SetFavorite
    card.fav:SetShown(canFav and true or false)
    if canFav then
        at(card.fav, x, y)
        local on = EconKing.IsFavorite(c.item)
        card.fav:SetActive(on)
        card.fav.icon:SetDesaturated(not on)
        x = x + 32
    end
    local canHist = c.item and KM.pages and KM.pages.history
    card.hist:SetShown(canHist and true or false)
    if canHist then at(card.hist, x, y) end
    y = y - 30

    card.child:SetHeight(-y)
    card.scroll:SetContentHeight(-y)

    summary:SetText(ns.ItemText(c.item, c.name) .. "  " .. (c.head and signed(c.head) or "") .. "  " .. verdictText(v))
end

-- The open profession's id: the window's, else the selected recipe's.
local function openProfID()
    local a = ns.Active()
    local sel = ns.Selection()
    local profName, skill, maxSkill
    if a and a.profession then profName, skill, maxSkill = a.profession() end
    local profID = ns.ProfID(profName) or (sel and (sel.prof or ns.ProfID(sel.profName)))
    if not skill or skill <= 0 then skill, maxSkill = ns.SkillFor(nil, profID) end
    return profID, skill, maxSkill
end

local function drawAll()
    local profID, skill, maxSkill = openProfID()
    all.prof:SetText((ns.ProfName(profID) or "") .. (skill and (" " .. skill .. (maxSkill and ("/" .. maxSkill) or "")) or ""))
    all.canMake:SetChecked(ns.db.canMake)
    local h = (panel:GetHeight() or MIN_H) - HEAD - TOOLBAR - FOOTER
    all.tbl:SetHeight(math.max(20 + 18 * 4, h))
    all.tbl:Layout()
    all.rowsAll = ns.AllCrafts(profID)
    all.rows = ns.FilterCrafts(all.rowsAll)
    all.tbl.emptyText = #all.rowsAll == 0 and "Nothing priced yet: scan at the auction house." or "No recipe matches."
    all.tbl:SetRows(all.rows, function(r, row, cells)
        r.item = row.item
        if r.icon then r.icon:SetTexture(ns.ItemInfo(row.item).icon) end
        cells.name:SetText(ns.ItemText(row.item, row.name))
        cells.gain:SetText(signed(row.gain, short))
        cells.margin:SetText(pct(row.margin))
        cells.can:SetText(row.can and (UI.Hex(row.can > 0 and C.good or C.dim) .. KM.Commas(row.can) .. "|r") or DASH)
        cells.listed:SetText(row.listed and KM.Commas(row.listed) or DASH)
        cells.make:SetText(row.make and tostring(row.make) or DASH)
        cells.now:SetText(signed(row.now, short))
        cells.verdict:SetText(verdictText(row.verdict, true))
    end)
    local age, stale = ns.PriceAgeText()
    local count = #all.rows .. " of " .. #all.rowsAll .. " recipes, " .. ns.ModeLabel(ns.Mode()) .. ".  "
    all.foot:SetText(count .. (stale and (UI.Hex(C.warn) .. age .. " Scan at the auction house for fresh ones.|r") or age))
end

-- Redraws the open tab (cheap enough to run on every change).
function ns.Refresh()
    if not (panel and panel:IsShown()) then return end
    local a = ns.Active()
    if not a then ns.HidePanel(); return end
    local key = a:current()
    if key ~= lastKey then lastKey = key; ns.pinned = nil end
    local tab = ns.db.tab
    tabs:Select(tab)
    modeTabs:Select(ns.Mode())
    card.frame:SetShown(tab == "card")
    all.frame:SetShown(tab == "all")
    -- the card also feeds the collapsed summary, so it is worked out on either tab
    drawCard()
    if tab == "all" and not ns.db.collapsed then drawAll() end
end

-- Called a few times a second while the panel is open: notices a new selection even without a callback.
function ns.Poll()
    local a = ns.Active()
    if not a then ns.HidePanel(); return end
    if a:current() ~= lastKey then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Showing, placing
---------------------------------------------------------------------------

-- How far things stick out past the window's right (or left) edge: the profession window's side tabs and help
-- button hang outside it. Checks the window's own children and frames parented to UIParent that sit against that
-- edge; capped so a stray wide frame can't push the panel off the screen.
local function outer(r, side, edge) return side == "left" and (edge - (r:GetLeft() or edge)) or ((r:GetRight() or edge) - edge) end
local function besideEdge(r, f, side)
    local top, bottom = f:GetTop(), f:GetBottom()
    local rt, rb, rl, rr = r:GetTop(), r:GetBottom(), r:GetLeft(), r:GetRight()
    if not (top and bottom and rt and rb and rl and rr) then return false end
    if rb > top or rt < bottom or (rr - rl) > 120 then return false end
    if side == "left" then return rr >= f:GetLeft() - 4 and rr <= f:GetLeft() + 40 end
    return rl <= f:GetRight() + 4 and rl >= f:GetRight() - 40
end
function ns.Overhang(f, side)
    if not (f.GetRight and f:GetRight() and f:GetLeft()) then return 0 end
    local edge = side == "left" and f:GetLeft() or f:GetRight()
    local most = 0
    local function look(r, deep)
        if r == panel or (r.IsForbidden and r:IsForbidden()) or not (r.IsShown and r:IsShown()) then return end
        local o = outer(r, side, edge)
        if o > most and o <= 120 then most = o end
        if deep and r.GetChildren then for _, c in ipairs({ r:GetChildren() }) do look(c, false) end end
    end
    -- one frame that can't be read (forbidden, or no position yet) is skipped, never an error
    local function try(c, deep, check)
        pcall(function()
            if c.IsForbidden and c:IsForbidden() then return end
            if check and not (c ~= f and c ~= panel and c.IsShown and c:IsShown() and besideEdge(c, f, side)) then return end
            look(c, deep)
        end)
    end
    if f.GetChildren then for _, c in ipairs({ f:GetChildren() }) do try(c, true) end end
    if UIParent and UIParent.GetChildren then
        for _, c in ipairs({ UIParent:GetChildren() }) do try(c, true, true) end
    end
    return math.floor(most + 0.5)
end

function ns.Place()
    if not panel then return end
    local _, f = ns.Active()
    if not f then return end
    panel:ClearAllPoints()
    local ok, over = pcall(ns.Overhang, f, ns.db.side == "left" and "left" or "right")
    local gap = 4 + (ok and over or 0)
    if ns.db.side == "left" then
        panel:SetPoint("TOPRIGHT", f, "TOPLEFT", -gap, 0)
    else
        panel:SetPoint("TOPLEFT", f, "TOPRIGHT", gap, 0)
    end
    local h = (f.GetHeight and f:GetHeight()) or MIN_H
    panel:SetHeight(ns.db.collapsed and HEAD or math.max(MIN_H, math.min(MAX_H, h)))
    if f.GetFrameStrata then panel:SetFrameStrata(f:GetFrameStrata() or "MEDIUM") end
    if f.GetFrameLevel then panel:SetFrameLevel((f:GetFrameLevel() or 1) + 10) end
end

function ns.ShowPanel()
    if not (ns.db and ns.db.show) then return end
    local a = ns.Active()
    if not a then return end
    build()
    lastKey = a:current()
    ns.Place()
    panel:Show()
    ns.Refresh()
    -- the window's side tabs can appear a moment after it does: place again once they're up
    if C_Timer and C_Timer.After then C_Timer.After(0.2, function() if panel:IsShown() then ns.Place() end end) end
end

function ns.HidePanel()
    if panel then panel:Hide() end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function ns.SetCrafts(n)
    ns.db.crafts = math.max(1, math.min(200, math.floor(tonumber(n) or 1)))
    ns.Refresh()
end

-- Shows a recipe from All crafts on the card; selects it in the game's window too when the client has a safe call.
function ns.Pin(spell)
    if not spell then return end
    local sel = ns.SelectionFromSpell(spell)
    if not sel then return end
    ns.db.tab = "card"
    local T = C_TradeSkillUI
    local selected = false
    if ns.active == "modern" and T and type(T.OpenRecipe) == "function" then
        local info = ns.Call(T.GetRecipeInfo, spell)
        if type(info) == "table" and info.learned then selected = pcall(T.OpenRecipe, spell) end
    end
    local a = ns.Active()
    lastKey = a and a:current() or lastKey
    ns.pinned = sel
    ns.pinnedSelected = selected
    ns.Refresh()
end

function ns.ToggleFavorite()
    local c, E = ns.card, KM.mods.Econ
    if not (c and c.item and E and E.SetFavorite and EconKing) then return end
    KM.Safe(E.SetFavorite, c.item, not EconKing.IsFavorite(c.item))
    ns.Refresh()
end

function ns.OpenHistory()
    local c, E = ns.card, KM.mods.Econ
    if not (c and c.item) then return end
    if E and E.Toggle and E.ShowItem then
        KM.Safe(E.Toggle, true)
        KM.Safe(E.ShowItem, c.item)
    else
        KM.Show("history")
    end
end
