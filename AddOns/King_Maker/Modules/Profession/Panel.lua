local _, KM = ...
local ns = KM.Module("Profession")

-- The panel docked to the profession window: a "Recipe" card for the selected recipe and a "Best now" tab.
-- Our own frame, parented to UIParent and anchored beside the game's window; it never touches that window.

local UI = KM.UI
local C = UI.C
local W, HEAD, CW = 400, 30, 380   -- panel width, header height, content width
local MIN_H, MAX_H = 420, 720

local panel, body, tabs, collapseBtn, summary, emptyFS
local card, best = {}, {}
local lastKey, elapsed = nil, 0

-- 12345 -> "1g 23s" (two units at most, so money fits a narrow column).
local function short(c)
    if c == nil then return "|cff808080-|r" end
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

local function signed(c)
    if c == nil then return "|cff808080-|r" end
    if c > 0 then return UI.Hex(C.good) .. "+|r" .. KM.Money(c) end
    return KM.Money(c)
end

local function pct(x)
    if not x then return "|cff808080-|r" end
    local p = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
    local col = p > 0 and C.good or (p < 0 and C.bad or C.muted)
    return UI.Hex(col) .. (p > 0 and "+" or "") .. p .. "%|r"
end

local function at(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", region.anchorTo or card.child, "TOPLEFT", x, y)
end

local function verdictPill(pill, word)
    local v = word and ns.VERDICTS[word]
    if not v then pill:SetCustom("-", C.dim); return end
    pill:SetWidth(math.max(46, 12 + 6 * #v[1]))
    pill:SetCustom(v[1], C[v[2]] or C.muted)
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
    card.skill = UI.Text(ch, 11, C.text)
    card.skill:SetWidth(CW)

    card.craftsLabel = UI.Text(ch, 11, C.muted)
    card.craftsLabel:SetText("Crafts")
    card.minus = UI.Button(ch, "-", 20, 18, function() ns.SetCrafts((ns.db.crafts or 1) - (IsShiftKeyDown and IsShiftKeyDown() and 5 or 1)) end)
    card.count = UI.Text(ch, 12, C.accent, "CENTER")
    card.count:SetWidth(34)
    card.plus = UI.Button(ch, "+", 20, 18, function() ns.SetCrafts((ns.db.crafts or 1) + (IsShiftKeyDown and IsShiftKeyDown() and 5 or 1)) end)
    UI.Tip(card.plus, "Materials for this many crafts (shift: 5 at a time).")

    card.mats = UI.Table(ch, {
        { key = "name", label = "Reagent", w = 100 },
        { key = "need", label = "Need", w = 32, justify = "RIGHT" },
        { key = "have", label = "Have", w = 36, justify = "RIGHT" },
        { key = "each", label = "Each", w = 60, justify = "RIGHT" },
        { key = "line", label = "Cost", w = 0, justify = "RIGHT" },
    }, 18, { icon = true, fontSize = 11, noSort = true })
    card.mats:SetWidth(CW)
    card.mats.emptyText = "No reagents."

    card.lines = {}
    for i = 1, 8 do
        local l = UI.Text(ch, 11, C.muted)
        l:SetWidth(150)
        local v = UI.Text(ch, 11, C.text, "RIGHT")
        v:SetWidth(CW - 150)
        card.lines[i] = { l = l, v = v }
    end

    card.vLabel1 = UI.Text(ch, 10, C.muted)
    card.vLabel1:SetText("BOUGHT")
    card.vPill1 = UI.Pill(ch)
    card.vLabel2 = UI.Text(ch, 10, C.muted)
    card.vLabel2:SetText("FARMED")
    card.vPill2 = UI.Pill(ch)

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

    card.shop = UI.Button(ch, "Add missing to Shopping", 170, 22, function() ns.ShopMissing() end, "primary")
    UI.Tip(card.shop, "Adds the materials you're short of (for the crafts above) to the Shopping list \"Crafting\", at today's price as the most to pay. Vendor items are left out.")
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

local function buildBest(parent)
    best.frame = CreateFrame("Frame", nil, parent)
    best.frame:SetAllPoints(parent)
    local f = best.frame
    best.head1 = UI.Heading(f, "Best crafts now")
    best.head1:SetPoint("TOPLEFT", 10, -8)
    best.mode = UI.Text(f, 10, C.dim, "RIGHT")
    best.mode:SetPoint("TOPRIGHT", -10, -8)
    best.mode:SetWidth(160)
    best.crafts = UI.Table(f, {
        { key = "name", label = "Item", w = 130 },
        { key = "gain", label = "Profit", w = 72, justify = "RIGHT" },
        { key = "listed", label = "Listed", w = 44, justify = "RIGHT", tip = "How many are on the auction house now (your last scan)." },
        { key = "make", label = "Make", w = 36, justify = "RIGHT",
          tip = "How many to craft to sell: a quarter of what's listed, and no more than one day of units leaving the auction house. Nothing listed: make 1 to test the market." },
        { key = "verdict", label = "Do", w = 0, justify = "RIGHT" },
    }, 18, { icon = true, fontSize = 11, noSort = true, onClick = function(row) ns.Pin(row.spell) end })
    best.crafts:SetPoint("TOPLEFT", 10, -24)
    best.crafts:SetSize(CW, 20 + 18 * 10)
    best.crafts.emptyText = "Nothing priced yet: run a Market Scan."
    best.head2 = UI.Heading(f, "Next skill-ups")
    best.head2:SetPoint("TOPLEFT", 10, -24 - (20 + 18 * 10) - 12)
    best.steps = UI.Table(f, {
        { key = "skill", label = "Skill", w = 58 },
        { key = "name", label = "Make", w = 140 },
        { key = "crafts", label = "x", w = 34, justify = "RIGHT" },
        { key = "cost", label = "Costs", w = 0, justify = "RIGHT" },
    }, 18, { fontSize = 11, noSort = true, onClick = function(row) if row.spell then ns.Pin(row.spell) end end })
    best.steps:SetPoint("TOPLEFT", 10, -24 - (20 + 18 * 10) - 28)
    best.steps:SetSize(CW, 20 + 18 * 8)
    best.steps.emptyText = "No skill-up plan (Skillup needs prices and your skill)."
end

local function setCollapsed(on)
    ns.db.collapsed = on and true or false
    collapseBtn:SetLabel(ns.db.collapsed and "+" or "-")
    body:SetShown(not ns.db.collapsed)
    tabs:SetShown(not ns.db.collapsed)
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
    tabs = UI.Tabs(panel, { { id = "card", label = "Recipe", w = 70 }, { id = "best", label = "Best now", w = 80 } }, function(id)
        ns.db.tab = id
        ns.Refresh()
    end, 20)
    tabs:SetPoint("TOPLEFT", 92, -5)
    summary = UI.Text(panel, 11, C.text)
    summary:SetPoint("TOPLEFT", 92, -9)
    summary:SetWidth(W - 130)
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
    buildBest(body)

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
    local y = 0
    at(card.icon, 0, y)
    card.icon:SetTexture(c.icon)
    at(card.name, 40, y - 2)
    card.name:SetText(c.item and ns.ItemText(c.item, c.name) or (UI.Hex(C.accent) .. c.name .. "|r"))
    at(card.sub, 40, y - 19)
    local subParts = {}
    if c.prof and ns.ProfName(c.prof) then subParts[#subParts + 1] = ns.ProfName(c.prof) end
    if c.made > 1 then subParts[#subParts + 1] = "makes " .. c.made end
    if c.source == "data" then subParts[#subParts + 1] = "picked in Best now" end
    card.sub:SetText(table.concat(subParts, "  |cff505050/|r  "))
    y = y - 38

    local Sk = KM.mods.Skillup
    local hex = c.color and Sk and Sk.COLORS and Sk.COLORS[c.color] or "|cffffffff"
    local skillText
    if c.color then
        skillText = "Skill-up: " .. hex .. c.color .. "|r"
        if c.chance then skillText = skillText .. "  " .. math.floor(c.chance * 100 + 0.5) .. "% chance" end
        if c.skill then skillText = skillText .. UI.Hex(C.dim) .. "  at " .. c.skill .. (c.grey and (", grey at " .. c.grey) or "") .. "|r" end
    else
        skillText = UI.Hex(C.dim) .. "Skill-up: unknown (open the window once so Skillup sees your skill)|r"
    end
    at(card.skill, 0, y)
    card.skill:SetText(skillText)
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

    local rows = {}
    local function add(l, v) rows[#rows + 1] = { l, v } end
    local mode = ns.Mode()
    add(c.crafts > 1 and ("Materials (x" .. c.crafts .. ")") or "Materials",
        c.missingPrice and (UI.Hex(C.bad) .. "no price for " .. ns.ItemText(c.missingPrice) .. "|r") or KM.Money(c.costAll))
    if c.item then
        add("Sells for" .. (c.marketReal and " (market)" or ""), KM.Money(c.market) .. (c.made > 1 and UI.Hex(C.dim) .. " each|r" or ""))
        add("Lowest  /  listed", KM.Money(c.lowest) .. UI.Hex(C.dim) .. "  /  " .. (c.listed and KM.Commas(c.listed) or "-") .. "|r")
        add("30-day avg  /  7-day trend", KM.Money(c.avg30) .. "  /  " .. pct(c.trend7))
        add("Profit each, after 5% cut", signed(c.profit))
        if mode == "farm" and c.farm then add("Beats selling raw by", signed(c.farm.gain)) end
        add("Disenchant", c.de and (KM.Money(c.de) .. UI.Hex(C.dim) .. "  (" .. short(c.deSale) .. " after cut)|r") or UI.Hex(C.dim) .. "-|r")
    else
        add("Sells for", UI.Hex(C.dim) .. "an enchant: nothing to sell|r")
    end
    for i, l in ipairs(card.lines) do
        local r = rows[i]
        if r then
            at(l.l, 0, y); at(l.v, 150, y)
            l.l:SetText(r[1]); l.v:SetText(r[2])
            l.l:Show(); l.v:Show()
            y = y - 16
        else
            l.l:Hide(); l.v:Hide()
        end
    end
    y = y - 6

    at(card.vLabel1, 0, y - 3)
    at(card.vPill1, 48, y)
    verdictPill(card.vPill1, c.verdict and c.verdict.buy)
    at(card.vLabel2, 150, y - 3)
    at(card.vPill2, 198, y)
    verdictPill(card.vPill2, c.verdict and c.verdict.farm)
    for _, w in ipairs({ card.vLabel1, card.vPill1, card.vLabel2, card.vPill2 }) do w:SetShown(c.item ~= nil) end
    if c.item then y = y - 26 end

    y = drawSpark(c.history, y)

    local x = 0
    local canShop = ns.ShoppingAvailable()
    card.shop:SetShown(canShop)
    if canShop then
        at(card.shop, 0, y)
        local ah = ns.Missing(c)
        card.shop:SetEnabled2(#ah > 0)
        x = 176
    end
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

    local head, hm = ns.Headline(c, mode)
    summary:SetText(ns.ItemText(c.item, c.name) .. "  " .. (head and signed(head) or "") .. "  " ..
        ((c.verdict and ns.VERDICTS[c.verdict[hm]] and ns.VERDICTS[c.verdict[hm]][1]) or ""))
end

local function drawBest()
    local a = ns.Active()
    local sel = ns.Selection()
    local profName, skill, maxSkill
    if a and a.profession then profName, skill, maxSkill = a.profession() end
    local profID = ns.ProfID(profName) or (sel and (sel.prof or ns.ProfID(sel.profName)))
    if not skill or skill <= 0 then skill, maxSkill = ns.SkillFor(nil, profID) end
    local mode = ns.Mode()
    best.mode:SetText((ns.ProfName(profID) or "") .. (mode == "farm" and "  /  farmed mats" or "  /  bought mats"))
    best.rows = ns.BestCrafts(profID, 10)
    best.crafts:SetRows(best.rows, function(r, row, cells)
        r.item = row.item
        if r.icon then r.icon:SetTexture(ns.ItemInfo(row.item).icon) end
        cells.name:SetText(ns.ItemText(row.item))
        cells.gain:SetText(signed(row.gain))
        local dash = "|cff808080-|r"
        cells.listed:SetText(row.listed and KM.Commas(row.listed) or dash)
        cells.make:SetText(row.make and tostring(row.make) or dash)
        local v = ns.VERDICTS[row.verdict]
        cells.verdict:SetText(v and (UI.Hex(C[v[2]] or C.muted) .. v[1] .. "|r") or "")
    end)
    best.head2:SetText(("Next skill-ups" .. (skill and (" from " .. skill) or "")):upper())
    best.stepRows = ns.NextSkillups(profID, skill, maxSkill, 8)
    best.steps:SetRows(best.stepRows, function(r, row, cells)
        if row.note then
            cells.skill:SetText(""); cells.crafts:SetText(""); cells.cost:SetText("")
            cells.name:SetText(UI.Hex(C.warn) .. row.note .. "|r")
            r.item = nil
            r.tip = row.note
            return
        end
        r.item = row.item
        cells.skill:SetText(row.from .. "-" .. row.to)
        local name = row.item and ns.ItemText(row.item)
        if not name then
            local sn = C_Spell and C_Spell.GetSpellName and ns.Call(C_Spell.GetSpellName, row.spell)
            name = UI.Hex(C.accent) .. (sn or ("Spell " .. row.spell)) .. "|r"
        end
        cells.name:SetText(name)
        cells.crafts:SetText(tostring(row.crafts or ""))
        cells.cost:SetText(short(row.cost))
    end)
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
    card.frame:SetShown(tab == "card")
    best.frame:SetShown(tab == "best")
    -- the card also feeds the collapsed summary, so it is worked out on either tab
    drawCard()
    if tab == "best" then drawBest() end
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

-- Shows a recipe from Best now on the card; selects it in the game's window too when the client has a safe call.
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

function ns.ShopMissing()
    local c = ns.card
    if not c then return end
    local added, vendor = ns.AddMissing(c)
    local msg = added > 0 and ("added " .. added .. " material(s) for " .. ns.ItemText(c.item, c.name) .. " to the Shopping list \"Crafting\".")
        or "nothing to add: you have every auction house material."
    if #vendor > 0 then
        local names = {}
        for _, v in ipairs(vendor) do names[#names + 1] = v.n .. "x " .. ns.ItemText(v.id) end
        msg = msg .. " From a vendor: " .. table.concat(names, ", ") .. "."
    end
    KM.Print(ns, msg)
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
