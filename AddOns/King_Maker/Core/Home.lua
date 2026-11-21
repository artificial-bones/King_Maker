local _, KM = ...

-- Home: the overview, everything at a glance. Modules supply the numbers; this file only draws them (2.7).
--
--   +-- hero tiles (KM.RegisterHomeTile) ---------------------------------------------------------------+
--   +-- chart (kind "chart", tabs) ----------------------+ +-- needs your attention (kind "attention") --+
--   +-- where your gold came from (kind "income") ------+ +-- best right now (kind "best") --------------+
--   +-- characters (kind "chars") --------------------------------------------------------------------- +
--   notes (KM.RegisterHomeNote)
--
-- Registration (Shell.lua holds the lists, so modules can register while they load):
--   KM.RegisterHomeTile{ id, order, get = fn() -> label, value, sub, color, tip = text | fn(tt),
--                        page = "id" (a click opens it), spark = fn() -> values, color }       (get returns nil to hide)
--   KM.RegisterHomeNote(fn() -> text | nil)                                                   (a line at the bottom)
--   KM.RegisterHomeCard{ kind, id, order, get, ... }:
--     "attention"  get() -> { { text, color, count, value, page, tab = fn, tip } } | nil
--                  red (C.bad) rows first, then C.warn, then the rest; a click runs tab() and opens page
--     "chart"      label, title, shown = fn() -> bool, get() -> a UI.Chart spec (only the chosen tab is worked out)
--     "income"     get(since) -> { { label, value (copper), page, tip } } | nil       (the last 30 days)
--     "best"       get() -> { label, value, sub, icon, color, page, tip } | nil
--     "chars"      get() -> { [charKey] = { text, color, tip, worth, class, level, primary = bool } } | nil
-- Every get runs through KM.Safe, only while Home is open (on show and on KM.Refresh). Empty sections say how to fill
-- them. The page is laid out from the container's size (763 x 557 at any zoom: the window scales whole).

local UI = KM.UI
local C = UI.C
local tiles, notes, cards = KM.homeTiles, KM.homeNotes, KM.homeCards

local GAP, RIGHT_W, PAD = 10, 280, 12
local TILE_H, SOURCES_H, CHARS_H = 84, 128, 80
local ROW_H, BEST_H = 22, 24
local W0, H0 = 763, 557
local DAY = 86400
local TEAL = { 0.36, 0.78, 0.74, 1 }
local SERIES = { C.accent, C.info, C.violet, TEAL }       -- categorical, in this order; "Other" is C.muted
local PRIO = { [C.bad] = 1, [C.warn] = 2 }

local H = { tiles = {} }
KM.home = H            -- the built frames (tests read them)

local function list(kind) return cards[kind] or {} end

local function open(page, tab)
    if tab then KM.Safe(tab) end
    if page then KM.Show(page) end
end

local function setColor(fs, c) c = c or C.text; fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- A bordered card with a gold caps heading (hover it for what the card shows) and a muted text on the right.
local function card(parent, title, tip)
    local p = UI.Panel(parent, C.panel)
    p.head = UI.Heading(p, title)
    p.head:SetPoint("TOPLEFT", PAD, -10)
    p.right = UI.Text(p, 10, C.muted, "RIGHT")
    p.right:SetPoint("TOPRIGHT", -PAD, -10)
    if tip then
        local hit = CreateFrame("Frame", nil, p)
        hit:SetPoint("TOPLEFT", 0, 0)
        hit:SetSize(220, 26)
        UI.Tip(hit, tip)
    end
    return p
end

-- A clickable list row: hover wash, gold edge mark, tooltip from row.tip, click opens row.page.
local function rowButton(parent, h)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(h)
    r.hl = UI.Fill(r, C.hover, "ARTWORK")
    r.hl:Hide()
    r:SetScript("OnEnter", function(self)
        if self.page or self.tab then self.hl:Show() end
        local tip = self.tip
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(tip) == "function" then tip(GameTooltip, self) else GameTooltip:AddLine(tip, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if not (self.page or self.tab) then return end
        UI.Click()
        open(self.page, self.tab)
    end)
    return r
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function build(c)
    H.c = c
    H.hero = CreateFrame("Frame", nil, c)
    H.hero:SetPoint("TOPLEFT")

    H.chart = card(c, "Gold, last 30 days", "Your gold over the last 30 days. Pick what the chart shows on the right; hover it for each day.")
    H.graph = UI.Chart(H.chart, 400, 150)
    H.graph.frame:SetPoint("TOPLEFT", 4, -32)

    H.att = card(c, "Needs your attention", "What you could do right now: cooldowns ready, stock losing money, auctions that don't sell, old prices. Click a row to go there.")
    H.att.rows = {}
    H.att.empty = UI.Text(H.att, 13, C.good, "CENTER")
    H.att.empty:SetPoint("CENTER", 0, 8)
    H.att.empty2 = UI.Para(H.att, 10, C.muted, RIGHT_W - 40)
    H.att.empty2:SetJustifyH("CENTER")
    H.att.empty2:SetPoint("TOP", H.att.empty, "BOTTOM", 0, -6)

    H.src = card(c, "Where your gold came from, 30 days", "What you made in the last 30 days, by where it came from: auction house sales (after the cut) by strategy from the Sales Ledger, what your farming sessions brought in (coin and loot at its value), and cooldown crafts (an estimate at today's prices). Loot you farmed and later sold can show under both farming and sales.")
    H.src.split = UI.SplitBar(H.src, 300, 6)
    H.src.split:SetPoint("TOPLEFT", PAD, -30)
    H.src.bars = UI.HBars(H.src, 300, 18, 4)
    H.src.bars:SetPoint("TOPLEFT", PAD, -44)
    H.src.empty = UI.Para(H.src, 11, C.dim, 400)
    H.src.empty:SetPoint("TOPLEFT", PAD, -36)

    H.best = card(c, "Best right now", "The best opportunity from each part of King Maker: the most profitable craft you know, your best farm by gold per hour, the white item most worth hunting, and the zone with the most quest gold left. Click one to open its page.")
    H.best.rows = {}
    H.best.empty = UI.Para(H.best, 11, C.dim, RIGHT_W - 2 * PAD)
    H.best.empty:SetPoint("TOPLEFT", PAD, -36)

    H.chars = card(c, "Characters", "Every character King Maker knows, richest first: gold and items (Inventory), rested XP and cooldowns ready. Click one to open Inventory.")
    H.chars.cells = {}

    H.notes = UI.Para(c, 10, C.muted, W0)
end

---------------------------------------------------------------------------
-- Hero tiles
---------------------------------------------------------------------------

local function heroTile(i)
    local f = H.tiles[i]
    if f then return f end
    f = UI.Tile(H.hero, 180, TILE_H)
    f.spark = UI.Spark(f, 160, 14, 30)
    f.spark:SetPoint("BOTTOMLEFT", 10, 9)
    f.go = UI.Text(f, 10, C.dim, "RIGHT")
    f.go:SetPoint("TOPRIGHT", -8, -8)
    f:SetScript("OnMouseUp", function(self) if self.page then UI.Click(); KM.Show(self.page) end end)
    H.tiles[i] = f
    return f
end

local function drawTiles(W)
    local shown = {}
    for _, t in ipairs(tiles) do
        local label, value, sub, color = KM.Safe(t.get)
        if label then shown[#shown + 1] = { t = t, label = label, value = value, sub = sub, color = color } end
    end
    local n = #shown
    local per = n <= 6 and math.max(n, 1) or 4
    local w = math.floor((W - (per - 1) * GAP) / per)
    for i, s in ipairs(shown) do
        local f = heroTile(i)
        local row, col = math.floor((i - 1) / per), (i - 1) % per
        f:SetSize(w, TILE_H)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", H.hero, "TOPLEFT", col * (w + GAP), -row * (TILE_H + GAP))
        f:Set(s.label, s.value, s.sub, s.color)
        f:SetTip(s.t.tip)
        f.page = s.t.page
        f.go:SetText(s.t.page and ">" or "")
        local values, sc
        if s.t.spark then values, sc = KM.Safe(s.t.spark) end
        if type(values) == "table" and #values > 0 then
            f.spark:SetSize(w - 20, 14)
            f.spark:Set(values, sc or C.accent)
            f.spark:Show()
        else
            f.spark:Hide()
        end
        f:Show()
    end
    for i = n + 1, #H.tiles do H.tiles[i]:Hide() end
    local rows = n > 0 and math.ceil(n / per) or 0
    local h = rows > 0 and (rows * TILE_H + (rows - 1) * GAP) or 0
    H.hero:SetSize(W, math.max(h, 1))
    H.hero:SetShown(n > 0)
    return h, n
end

---------------------------------------------------------------------------
-- The chart, with a tab per chart provider
---------------------------------------------------------------------------

local function chartTabs(shown)
    local key = {}
    for _, ch in ipairs(shown) do key[#key + 1] = ch.id .. "=" .. (ch.label or ch.id) end
    key = table.concat(key, ";")
    if H.tabsKey == key then return end
    H.tabsKey = key
    if H.tabs then H.tabs:Hide() end
    H.tabs = nil
    if #shown < 2 then return end
    local items = {}
    for _, ch in ipairs(shown) do items[#items + 1] = { id = ch.id, label = ch.label or ch.id } end
    H.tabs = UI.Tabs(H.chart, items, function(id)
        if KingMakerDB and KingMakerDB.ui then KingMakerDB.ui.homeChart = id end
        KM.Refresh("home")
    end, 20)
    H.tabs:SetPoint("TOPRIGHT", -8, -6)
end

local function drawChart(w, h)
    local shown = {}
    for _, ch in ipairs(list("chart")) do
        if not ch.shown or KM.Safe(ch.shown) then shown[#shown + 1] = ch end
    end
    chartTabs(shown)
    local want = KingMakerDB and KingMakerDB.ui and KingMakerDB.ui.homeChart
    local pick = shown[1]
    for _, ch in ipairs(shown) do if ch.id == want then pick = ch end end
    H.chartPick = pick and pick.id
    if H.tabs and pick then H.tabs:Select(pick.id) end
    H.chart.head:SetText(((pick and pick.title) or "Gold, last 30 days"):upper())
    H.chart.right:SetText("")
    H.graph:SetSize(w - 12, h - 40)
    local spec = pick and KM.Safe(pick.get)
    if type(spec) ~= "table" then
        spec = { series = {}, emptyText = pick and pick.emptyText
            or "Your net worth over time shows here once Inventory has seen your characters for a day." }
    end
    H.graph:Draw(spec)
    if not H.tabs and spec.note then H.chart.right:SetText(spec.note) end
end

---------------------------------------------------------------------------
-- Needs your attention
---------------------------------------------------------------------------

local function attentionItems()
    local out = {}
    for pi, p in ipairs(list("attention")) do
        local items = KM.Safe(p.get)
        if type(items) == "table" then
            for ii, it in ipairs(items) do
                if type(it) == "table" and it.text then
                    it.prio = PRIO[it.color] or (it.color == C.info and 4 or 3)
                    it.po, it.ii = pi, ii
                    out[#out + 1] = it
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.po ~= b.po then return a.po < b.po end
        return a.ii < b.ii
    end)
    return out
end

local function attRow(i)
    local r = H.att.rows[i]
    if r then return r end
    r = rowButton(H.att, ROW_H)
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetTexture(UI.WHITE)
    r.mark:SetSize(6, 6)
    r.mark:SetPoint("LEFT", 6, 0)
    r.text = UI.Text(r, 11, C.text)
    r.text:SetPoint("LEFT", 18, 0)
    r.go = UI.Text(r, 10, C.dim, "RIGHT")
    r.go:SetPoint("RIGHT", -6, 0)
    r.value = UI.Text(r, 10, C.muted, "RIGHT")
    r.value:SetPoint("RIGHT", -18, 0)
    H.att.rows[i] = r
    return r
end

local function drawAttention(w, h)
    local items = attentionItems()
    H.attItems = items
    local fit = math.max(1, math.floor((h - 34) / ROW_H))
    local show = #items > fit and fit - 1 or #items
    local used = 0
    for i = 1, show do
        local it, r = items[i], attRow(i)
        used = i
        r.data, r.page, r.tab, r.tip = it, it.page, it.tab, it.tip
        UI.SetColor(r.mark, it.color or C.accent)
        r.mark:Show()
        r.value:SetText(it.value or (it.count and tostring(it.count)) or "")
        local vw = (it.value or it.count) and math.min(90, (r.value:GetStringWidth() or 30) + 6) or 0
        r.text:SetWidth(math.max(40, w - 18 - 18 - vw - 6))
        r.text:SetText(it.text)
        setColor(r.text, C.text)
        r.go:SetText((it.page or it.tab) and ">" or "")
    end
    if #items > show then           -- the rest, in one row's tooltip
        used = show + 1
        local r = attRow(used)
        local rest = {}
        for i = show + 1, #items do rest[#rest + 1] = items[i] end
        r.data, r.page, r.tab = nil, nil, nil
        r.tip = function(tt)
            tt:AddLine("Also needs your attention", C.accent[1], C.accent[2], C.accent[3])
            for _, it in ipairs(rest) do tt:AddLine(it.text, 1, 1, 1, true) end
        end
        r.mark:Hide()
        r.value:SetText("")
        r.go:SetText("")
        r.text:SetWidth(w - 24)
        r.text:SetText("and " .. #rest .. " more (hover)")
        setColor(r.text, C.muted)
    end
    for i, r in ipairs(H.att.rows) do
        if i <= used then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", H.att, "TOPLEFT", 4, -28 - (i - 1) * ROW_H)
            r:SetWidth(w - 8)
            r:Show()
        else
            r:Hide()
        end
    end
    H.att.right:SetText(#items > 0 and tostring(#items) or "")
    local none = #items == 0
    H.att.empty:SetText(none and "All clear" or "")
    H.att.empty2:SetText(none and "Nothing needs you right now. Ready cooldowns, stock losing money and old prices show up here." or "")
end

---------------------------------------------------------------------------
-- Where your gold came from
---------------------------------------------------------------------------

local function drawIncome(w)
    local since = KM.Now() - 30 * DAY
    local rows = {}
    for _, p in ipairs(list("income")) do
        local got = KM.Safe(p.get, since)
        if type(got) == "table" then
            for _, r in ipairs(got) do
                if type(r) == "table" and (r.value or 0) > 0 then rows[#rows + 1] = r end
            end
        end
    end
    table.sort(rows, function(a, b) if a.value ~= b.value then return a.value > b.value end return tostring(a.label) < tostring(b.label) end)
    if #rows > 4 then              -- a 5th source folds into Other
        local other = { label = "Other", value = 0, parts = {} }
        for i = 4, #rows do other.value = other.value + rows[i].value; other.parts[#other.parts + 1] = rows[i] end
        for i = #rows, 4, -1 do rows[i] = nil end
        rows[4] = other
    end
    -- colours follow the source, not its rank: the sources shown, in name order, take the palette in order
    local names = {}
    for _, r in ipairs(rows) do if r.label ~= "Other" then names[#names + 1] = r.label end end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
    local colorOf = {}
    for i, n in ipairs(names) do colorOf[n] = SERIES[i] end
    local total, top = 0, 0
    for _, r in ipairs(rows) do total, top = total + r.value, math.max(top, r.value) end
    H.incomeRows = rows
    local split, bars = {}, {}
    for _, r in ipairs(rows) do
        local color = r.label == "Other" and C.muted or colorOf[r.label]
        split[#split + 1] = { r.value / total, color }
        local tip = r.tip
        if r.parts then
            tip = function(tt) for _, p in ipairs(r.parts) do tt:AddDoubleLine(p.label, KM.Money(p.value), 1, 1, 1, 1, 1, 1) end end
        end
        bars[#bars + 1] = { label = r.label, value = KM.MoneyShort(r.value) .. "  |cff8c8c8c" .. math.floor(r.value / total * 100 + 0.5) .. "%|r",
            frac = r.value / top, color = color, tip = tip }
    end
    H.src.split:SetSize(w - 2 * PAD, 6)
    H.src.bars:SetSize(w - 2 * PAD, 18 * 4)
    H.src.split:Set(split)
    H.src.bars:SetRows(bars)
    H.src.split:SetShown(#rows > 0)
    H.src.right:SetText(#rows > 0 and (KM.MoneyShort(total) .. " in 30 days") or "")
    H.src.empty:SetWidth(w - 2 * PAD)
    H.src.empty:SetText(#rows == 0 and "Nothing earned in the last 30 days yet. Auction house sales (open your mail to record them), farming sessions and cooldown crafts add up here." or "")
end

---------------------------------------------------------------------------
-- Best right now
---------------------------------------------------------------------------

local function bestRow(i)
    local r = H.best.rows[i]
    if r then return r end
    r = rowButton(H.best, BEST_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.label = UI.Text(r, 9, C.muted)
    r.label:SetPoint("LEFT", 30, 0)
    r.label:SetWidth(56)
    r.name = UI.Text(r, 11, C.text)
    r.name:SetPoint("LEFT", 88, 0)
    r.value = UI.Text(r, 11, C.text, "RIGHT")
    r.value:SetPoint("RIGHT", -6, 0)
    H.best.rows[i] = r
    return r
end

local function drawBest(w, h)
    local got = {}
    for _, p in ipairs(list("best")) do
        local b = KM.Safe(p.get)
        if type(b) == "table" and b.label then got[#got + 1] = b end
    end
    local fit = math.max(1, math.floor((h - 32) / BEST_H))
    local n = math.min(#got, fit)
    H.bestItems = got
    for i = 1, n do
        local b, r = got[i], bestRow(i)
        r.data, r.page, r.tab, r.tip = b, b.page, b.tab, b.tip
        r.icon:SetTexture(b.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.label:SetText((b.label or ""):upper())
        r.value:SetText(b.value or "")
        setColor(r.value, b.color or C.accent)
        local vw = math.min(110, (r.value:GetStringWidth() or 50) + 8)
        r.name:SetWidth(math.max(30, w - 8 - 88 - vw - 6))
        r.name:SetText(b.sub or "")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", H.best, "TOPLEFT", 4, -28 - (i - 1) * BEST_H)
        r:SetWidth(w - 8)
        r:Show()
    end
    for i = n + 1, #H.best.rows do H.best.rows[i]:Hide() end
    H.best.empty:SetText(n == 0 and "Scan the auction house, pick your professions on Crafting Profits and save a farming session: the best craft, farm, white item and quest zone show here." or "")
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------

local function charList()
    local by, out = {}, {}
    for _, p in ipairs(list("chars")) do
        local got = KM.Safe(p.get)
        if type(got) == "table" then
            for key, fact in pairs(got) do
                if type(fact) == "table" then
                    local ch = by[key]
                    if not ch then ch = { key = key, facts = {}, worth = 0 }; by[key] = ch; out[#out + 1] = ch end
                    if fact.worth then ch.worth = math.max(ch.worth, fact.worth) end
                    ch.class = ch.class or fact.class
                    ch.level = ch.level or fact.level
                    if fact.primary then ch.primary = fact else ch.facts[#ch.facts + 1] = fact end
                end
            end
        end
    end
    local me = KM.Char()
    table.sort(out, function(a, b)
        if a.worth ~= b.worth then return a.worth > b.worth end
        if (a.key == me) ~= (b.key == me) then return a.key == me end
        return a.key < b.key
    end)
    return out
end

local function charCell(i)
    local f = H.chars.cells[i]
    if f then return f end
    f = rowButton(H.chars, 48)
    f.bg = UI.Fill(f, { 0, 0, 0, 0.18 })
    f.name = UI.Text(f, 11, C.text)
    f.name:SetPoint("TOPLEFT", 8, -5)
    f.name:SetPoint("RIGHT", -6, 0)
    f.main = UI.Text(f, 13, C.text)
    f.main:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.main:SetPoint("RIGHT", -6, 0)
    f.facts = UI.Text(f, 10, C.muted)
    f.facts:SetPoint("TOPLEFT", f.main, "BOTTOMLEFT", 0, -3)
    f.facts:SetPoint("RIGHT", -6, 0)
    H.chars.cells[i] = f
    return f
end

local function classHex(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.r then return string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) end
    return nil
end

local function drawChars(w, chars)
    local MAX = math.max(1, math.floor((w - 2 * PAD + 8) / 128))
    local more = #chars > MAX and (#chars - MAX + 1) or 0
    local n = more > 0 and MAX or #chars
    local cw = math.floor((w - 2 * PAD - (n - 1) * 8) / math.max(n, 1))
    H.charsShown = {}
    for i = 1, n do
        local f = charCell(i)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", H.chars, "TOPLEFT", PAD + (i - 1) * (cw + 8), -26)
        f:SetWidth(cw)
        f.page, f.tab = "inventory", function() local m = KM.mods.Inventory; if m and m.SelectTab then m.SelectTab("overview") end end
        if more > 0 and i == n then
            local rest = {}
            for j = n, #chars do rest[#rest + 1] = chars[j] end
            f.name:SetText("+" .. more .. " more")
            setColor(f.name, C.muted)
            f.main:SetText("")
            f.facts:SetText("hover for the list")
            f.tip = function(tt)
                for _, ch in ipairs(rest) do
                    tt:AddDoubleLine((ch.key:gsub("%-.*$", "")), ch.primary and ch.primary.text or "", 1, 1, 1, 1, 1, 1)
                end
            end
        else
            local ch = chars[i]
            H.charsShown[#H.charsShown + 1] = ch
            local name = ch.key:gsub("%-.*$", "")
            local hex = classHex(ch.class)
            f.name:SetText((hex and (hex .. name .. "|r") or name) .. (ch.level and ("  |cff8c8c8c" .. ch.level .. "|r") or ""))
            setColor(f.name, C.text)
            f.main:SetText(ch.primary and ch.primary.text or "-")
            setColor(f.main, ch.primary and ch.primary.color or C.dim)
            local parts = {}
            for _, fact in ipairs(ch.facts) do
                if fact.text and fact.text ~= "" then
                    parts[#parts + 1] = fact.color and (UI.Hex(fact.color) .. fact.text .. "|r") or fact.text
                end
            end
            f.facts:SetText(#parts > 0 and table.concat(parts, ", ") or "")
            f.tip = function(tt)
                tt:AddLine(ch.key, C.accent[1], C.accent[2], C.accent[3])
                if ch.primary and ch.primary.tip then tt:AddLine(ch.primary.tip, 1, 1, 1, true) end
                for _, fact in ipairs(ch.facts) do tt:AddLine(fact.tip or fact.text, 1, 1, 1, true) end
                tt:AddLine("Click: Inventory.", 0.6, 0.6, 0.6)
            end
        end
        f:Show()
    end
    for i = n + 1, #H.chars.cells do H.chars.cells[i]:Hide() end
    H.chars.right:SetText(#chars > 0 and (#chars .. (#chars == 1 and " character" or " characters")) or "")
end

---------------------------------------------------------------------------
-- Refresh: work the numbers out, lay out from the container's size, draw
---------------------------------------------------------------------------

local function refresh(c)
    local W, Hh = c:GetWidth() or 0, c:GetHeight() or 0
    if W < 300 then W = W0 end
    if Hh < 300 then Hh = H0 end
    local LW = W - RIGHT_W - GAP

    local heroH = drawTiles(W)
    local y = heroH > 0 and (heroH + GAP + 2) or 0

    local lines = {}
    for _, fn in ipairs(notes) do
        local s = KM.Safe(fn)
        if s and s ~= "" then lines[#lines + 1] = s end
        if #lines >= 2 then break end
    end
    H.notes:SetWidth(W)
    H.notes:SetText(table.concat(lines, "\n"))
    local notesH = #lines > 0 and (#lines * 14 + 2) or 0

    local chars = charList()
    local charsH = #chars > 0 and CHARS_H or 0
    local below = SOURCES_H + GAP + (charsH > 0 and (charsH + GAP) or 0) + (notesH > 0 and (notesH + 6) or 0)
    local chartH = math.max(150, Hh - y - GAP - below)

    H.chart:ClearAllPoints(); H.chart:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y); H.chart:SetSize(LW, chartH)
    H.att:ClearAllPoints(); H.att:SetPoint("TOPLEFT", c, "TOPLEFT", LW + GAP, -y); H.att:SetSize(RIGHT_W, chartH)
    y = y + chartH + GAP
    H.src:ClearAllPoints(); H.src:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y); H.src:SetSize(LW, SOURCES_H)
    H.best:ClearAllPoints(); H.best:SetPoint("TOPLEFT", c, "TOPLEFT", LW + GAP, -y); H.best:SetSize(RIGHT_W, SOURCES_H)
    y = y + SOURCES_H + GAP
    H.chars:SetShown(charsH > 0)
    if charsH > 0 then
        H.chars:ClearAllPoints(); H.chars:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y); H.chars:SetSize(W, charsH)
        y = y + charsH + GAP
    end
    H.notes:ClearAllPoints(); H.notes:SetPoint("TOPLEFT", c, "TOPLEFT", 2, -(y - 4))
    H.notes:SetShown(notesH > 0)

    drawChart(LW, chartH)
    drawAttention(RIGHT_W, chartH)
    drawIncome(LW)
    drawBest(RIGHT_W, SOURCES_H)
    if charsH > 0 then drawChars(W, chars) end
end

KM.RegisterPage({ id = "home", group = "home", label = "Home", icon = "Interface\\Icons\\INV_Crown_01", order = 1,
    title = "King Maker", subtitle = function()
        return "Welcome back, " .. KM.PlayerName() .. ". Your gold at a glance."
    end, build = build, refresh = refresh })
