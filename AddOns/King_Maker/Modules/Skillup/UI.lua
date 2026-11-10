local _, KM = ...
local ns = KM.Module("Skillup")
local UI = KM.UI
local C = UI.C

-- The Skill-ups page of the King Maker window (Crafting > Skill-ups).
--   Top:   Plan / At my skill, and Scan prices (at the auction house).
--   Then:  the professions; your skill and level, From / To, and what counts as getting something back
--          (disenchanting, selling on the auction house), and whether patterns you don't have are allowed.
--   Plan:  from your skill to the target, what to make at each stretch, how many, and what it costs.
--          Trainer visits are on their own lines. Shopping list (bottom right) has every material.
--   At my skill: every recipe you can make right now, cheapest skill point first.
-- Also here: the crown's quick action and tooltip lines, and the Settings section.

local PAGE = "skillups"
local TABLE_Y = -100

local page, viewTabs, profTabs, info, fromBox, toBox, checks, tables, footer, shopBtn, scanBtn
local current, plan = {}, nil

local function grey(t) return "|cff808080" .. t .. "|r" end
local function pct(x) return string.format("%.0f%%", x * 100) end

local function prof() return ns.db.ui.prof end

local function target(p)
    ns.db.ui.to = ns.db.ui.to or {}
    return ns.db.ui.to[p] or ns.MAX_SKILL
end

local function start(p)
    ns.db.ui.from = ns.db.ui.from or {}
    return ns.db.ui.from[p] or ns.StartSkill(p)
end

local function recipeText(r)
    local name, color = ns.RecipeName(r)
    return (color or "|cffffffff") .. name .. "|r" .. (r.made > 1 and (" x" .. r.made) or "")
end

local function learnText(r)
    if not ns.PATTERNS[r.spell] then return "Trainer" end
    if ns.Char().known[r.spell] then return "|cff40bf40Known|r" end
    local p = ns.PatternPrice(r)
    return "|cffff8040Pattern|r " .. (p and ns.Money(p) or grey("not listed"))
end

---------------------------------------------------------------------------
-- The two tables
---------------------------------------------------------------------------

local COLS = {
    plan = {
        { key = "skill", label = "Skill", w = 66 },
        { key = "make", label = "Make", w = 214 },
        { key = "crafts", label = "Crafts", w = 52, justify = "RIGHT", tip = "How many, on average: yellow and green recipes don't always give a point." },
        { key = "each", label = "Each", w = 88, justify = "RIGHT", tip = "One craft: the materials, minus what you get back. Below zero, it makes money." },
        { key = "how", label = "Get back by", w = 82, tip = "The best of selling it, disenchanting it, or a vendor." },
        { key = "per", label = "Per point", w = 84, justify = "RIGHT" },
        { key = "total", label = "Total", w = 88, justify = "RIGHT" },
        { key = "learn", label = "Recipe", w = 0 },
    },
    now = {
        { key = "make", label = "Make", w = 214 },
        { key = "color", label = "Color", w = 56 },
        { key = "chance", label = "Chance", w = 56, justify = "RIGHT", tip = "The chance one craft gives a skill point." },
        { key = "mats", label = "Materials", w = 88, justify = "RIGHT", tip = "What the materials for one craft cost (auction house or vendor, the cheaper)." },
        { key = "back", label = "Get back", w = 88, justify = "RIGHT" },
        { key = "how", label = "By", w = 74 },
        { key = "per", label = "Per point", w = 84, justify = "RIGHT" },
        { key = "learn", label = "Recipe", w = 0 },
    },
}

local function planCell(s, key)
    if s.note then return key == "make" and ("|cffffd100" .. s.note .. "|r") or "" end
    if key == "skill" then return s.from .. " - " .. s.to end
    if s.gap then
        return key == "make" and grey("Nothing priced to make here: scan, or allow patterns you lack.") or ""
    end
    if key == "make" then return recipeText(s.r) end
    if key == "crafts" then return tostring(s.crafts) end
    if key == "each" then return ns.Money(s.each) end
    if key == "how" then return s.how or grey("-") end
    if key == "per" then return ns.Money(s.cost / math.max(s.to - s.from, 1)) end
    if key == "total" then return ns.Money(s.cost) end
    if key == "learn" then return learnText(s.r) end
    return ""
end

local function nowCell(o, key)
    local c = o.craft
    if key == "make" then return recipeText(o.r) .. ((o.usable or o.has) and "" or grey("  (pattern)")) end
    if key == "color" then return ns.COLORS[o.color] .. o.color .. "|r" end
    if key == "chance" then return o.chance > 0 and pct(o.chance) or grey("-") end
    if key == "mats" then return c.missing and grey("no price") or ns.Money(c.cost) end
    if key == "back" then return c.back > 0 and ns.Money(c.back) or grey("-") end
    if key == "how" then return c.how or grey("-") end
    if key == "per" then return o.perPoint and ns.Money(o.perPoint) or grey("-") end
    if key == "learn" then return learnText(o.r) end
    return ""
end

local function fillPlan(_, e, cells)
    for _, col in ipairs(COLS.plan) do cells[col.key]:SetText(planCell(e, col.key)) end
end

local function fillNow(_, e, cells)
    for _, col in ipairs(COLS.now) do cells[col.key]:SetText(nowCell(e, col.key)) end
end

local function recipeTooltip(row)
    local e = row.data
    local r = e and e.r
    if not r then return end
    local c = ns.Craft(r)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(recipeText(r))
    GameTooltip:AddLine(ns.COLORS.orange .. r.orange .. "|r  " .. ns.COLORS.yellow .. r.yellow .. "|r  "
        .. ns.COLORS.green .. r.green .. "|r  " .. ns.COLORS.grey .. r.grey .. "|r")
    GameTooltip:AddLine(" ")
    for _, m in ipairs(c.mats) do
        GameTooltip:AddDoubleLine(m.n .. " x " .. ns.ItemText(m.id) .. (m.vendor and grey("  vendor") or ""),
            m.unit and ns.Money(m.unit * m.n) or grey("no price"), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Materials", ns.Money(c.cost))
    if c.how then GameTooltip:AddDoubleLine("Get back (" .. c.how .. ")", ns.Money(c.back)) end
    if c.listed then GameTooltip:AddDoubleLine("Listed on the auction house", tostring(c.listed), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7) end
    GameTooltip:AddDoubleLine("Each craft", ns.Money(c.net))
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function rankName(max)
    for _, r in ipairs(ns.RANKS) do if max and max <= r.cap then return r.name end end
    return ns.RANKS[#ns.RANKS].name
end

-- The profession to open on: the one asked for, or the last one, or your first.
local function pickProfession(profID)
    if profID then ns.db.ui.prof = profID return end
    if ns.db.ui.prof then return end
    for _, p in ipairs(ns.PROFESSIONS) do
        if ns.Skill(p.id) > 0 then ns.db.ui.prof = p.id return end
    end
    ns.db.ui.prof = ns.PROFESSIONS[1].id
end

local function ahOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false end

local function refresh()
    if not ns.db or not page then return end
    pickProfession()
    ns.ClearCache()
    local p = prof()
    profTabs:Select(p)
    viewTabs:Select(ns.db.ui.view)
    for key, c in pairs(checks) do c:SetChecked(ns.db.ui[key]) end
    scanBtn:SetEnabled2(ahOpen() and not (ScannerKing and ScannerKing.IsScanning and ScannerKing.IsScanning()))

    local cur, max = ns.Skill(p)
    info:SetText(ns.PROF_BY_ID[p].name .. ": " .. (cur > 0 and (cur .. " / " .. max .. "  " .. grey(rankName(max)))
        or grey("not learned here")) .. "    " .. grey("Level " .. ns.Level()))
    local from, to = start(p), target(p)
    if not fromBox.focused then fromBox:SetText(tostring(from)) end
    if not toBox.focused then toBox:SetText(tostring(to)) end

    local view = ns.db.ui.view == "now" and "now" or "plan"
    local tbl = tables[view]
    tables.plan:SetShown(view == "plan")
    tables.now:SetShown(view == "now")
    if view == "plan" then
        plan = ns.Plan(p, from, to)
        current = plan.steps
    else
        plan = nil
        current = ns.Options(p, from)
    end
    local text
    if not ScannerKing then
        text = "Skill-ups needs the Scanner module for prices."
    else
        text = view == "plan" and "Nothing to plan: pick a target above your skill." or "Nothing you can make at this skill."
    end
    tbl.emptyText = text
    tbl:SetRows(current)

    local last = ScannerKing and ScannerKing.LastScan and ScannerKing.LastScan()
    local age = ScannerKing and ("Prices " .. (last and ScannerKing.PriceAge(last) or "not scanned yet") .. ".")
        or (UI.Hex(C.bad) .. "Skill-ups needs the Scanner module for prices.|r")
    if plan then
        footer:SetText(from .. " to " .. to .. ": about " .. ns.Money(plan.cost) .. " over " .. math.floor(plan.crafts + 0.5)
            .. " crafts" .. (plan.gaps > 0 and ("  |cffff6060" .. plan.gaps .. " points with nothing priced|r") or "")
            .. ".  " .. age)
        shopBtn:Show()
    else
        footer:SetText("At skill " .. from .. ", cheapest skill point first.  " .. age)
        shopBtn:Hide()
    end
end

-- Redraws the page if it's the one showing (scans, trade skill windows and skill changes call this).
function ns.Refresh() KM.Refresh(PAGE) end

-- Opens (true), closes (false) or toggles (nil) the page, optionally on a profession.
function ns.Toggle(show, profID)
    if not ns.db then return end
    pickProfession(profID)
    if show == nil then show = not KM.IsShown(PAGE) end
    if show then
        if KM.IsShown(PAGE) then ns.Refresh() else KM.Show(PAGE) end
    elseif KM.IsShown(PAGE) then
        KM.Toggle(false)
    end
end

-- The materials for the whole plan, most expensive first.
function ns.ShoppingList()
    pickProfession()
    local p = prof()
    local pl = ns.Plan(p, start(p), target(p))
    local out = {}
    for _, m in ipairs(pl.mats) do
        table.insert(out, { id = m.id, n = m.n, cost = m.unit and m.unit * m.n, vendor = m.vendor })
    end
    return out
end

function ns.PrintShoppingList()
    pickProfession()
    local p = prof()
    KM.Print(ns, "Shopping list, " .. ns.PROF_BY_ID[p].name .. " " .. start(p) .. " to " .. target(p) .. ":")
    for _, m in ipairs(ns.ShoppingList()) do
        DEFAULT_CHAT_FRAME:AddMessage("   " .. m.n .. " x " .. ns.ItemText(m.id) .. "  " .. (m.cost and ns.Money(m.cost) or "no price"))
    end
end

-- Prices for one profession: at the auction house, a Scanner scan of everything it uses and makes.
function ns.ScanPrices()
    if not (ScannerKing and ScannerKing.Scan) then KM.Print(ns, "Scanning needs the Scanner module.") return end
    if not ahOpen() then
        KM.Print(ns, "Open the auction house to scan prices (or run a Deep Scan there for everything).")
        return
    end
    pickProfession()
    local list = ns.ItemsToScan(prof())
    ScannerKing.Scan({ items = list })
    KM.Print(ns, "Scanning " .. #list .. " items for " .. ns.PROF_BY_ID[prof()].name .. ".")
end

function ns.Page() return page end
function ns.Tables() return tables end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function numberBox(parent, current, onSet)
    local e = UI.NumberBox(parent, 44, onSet)
    if e.SetMaxLetters then e:SetMaxLetters(3) end
    -- Escape puts the saved value back (the focus loss that follows then commits it unchanged).
    e:SetScript("OnEscapePressed", function(self) self:SetText(tostring(current())); self:ClearFocus() end)
    return e
end

local function makeTable(parent, view)
    local t = UI.Table(parent, COLS[view], 20, { noSort = true, fontSize = 11, onEnter = recipeTooltip })
    t:SetPoint("TOPLEFT", 0, TABLE_Y)
    t:SetPoint("BOTTOMRIGHT", 0, 30)
    t.fill = view == "plan" and fillPlan or fillNow
    return t
end

local function buildPage(c)
    page = c
    checks = {}

    viewTabs = UI.Tabs(c, { { id = "plan", label = "Plan", w = 96 }, { id = "now", label = "At my skill", w = 110 } }, function(id)
        ns.db.ui.view = id
        tables.plan.offset, tables.now.offset = 0, 0
        ns.Refresh()
    end)
    viewTabs:SetPoint("TOPLEFT", 0, 0)
    scanBtn = UI.Button(c, "Scan prices", 110, 24, function() ns.ScanPrices() end, "primary")
    scanBtn:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(scanBtn, function(tt)
        tt:AddLine("Scan prices")
        tt:AddLine("At the auction house: scans everything this profession uses and makes, its patterns and the disenchanting materials. A Deep Scan covers everything too.", 1, 1, 1, true)
        if not ahOpen() then tt:AddLine("Open the auction house first.", C.warn[1], C.warn[2], C.warn[3], true) end
    end)

    local items = {}
    for _, p in ipairs(ns.PROFESSIONS) do items[#items + 1] = { id = p.id, label = p.short, w = 85 } end
    profTabs = UI.Tabs(c, items, function(id)
        ns.db.ui.prof = id
        tables.plan.offset, tables.now.offset = 0, 0
        ns.Refresh()
    end)
    profTabs:SetPoint("TOPLEFT", 0, -34)

    local y = -70
    info = UI.Text(c, 12, C.text)
    info:SetPoint("TOPLEFT", 0, y - 5)
    info:SetWidth(250)

    local fromLabel = UI.Text(c, 11, C.muted)
    fromLabel:SetPoint("TOPLEFT", 260, y - 6)
    fromLabel:SetText("From")
    fromBox = numberBox(c, function() return start(prof()) end, function(n)
        local p = prof()
        ns.db.ui.from = ns.db.ui.from or {}
        n = n and n > 0 and math.min(n, ns.MAX_SKILL - 1) or nil
        if ns.db.ui.from[p] == nil and n == ns.StartSkill(p) then n = nil end -- unchanged: keep following your skill
        ns.db.ui.from[p] = n -- empty: your skill
        ns.Refresh()
    end)
    fromBox:SetPoint("TOPLEFT", 292, y)
    local toLabel = UI.Text(c, 11, C.muted)
    toLabel:SetPoint("TOPLEFT", 342, y - 6)
    toLabel:SetText("to")
    toBox = numberBox(c, function() return target(prof()) end, function(n)
        ns.db.ui.to = ns.db.ui.to or {}
        n = n and n > 1 and math.min(n, ns.MAX_SKILL) or nil
        ns.db.ui.to[prof()] = n ~= ns.MAX_SKILL and n or nil
        ns.Refresh()
    end)
    toBox:SetPoint("TOPLEFT", 358, y)
    UI.Tip(fromBox, "Where the plan starts. Empty: your skill.")
    UI.Tip(toBox, "Where the plan ends. Empty: " .. ns.MAX_SKILL .. ".")

    local x = 420
    for _, ck in ipairs({
        { "de", "Disenchant", "Count disenchanting what you make and selling the materials (you or a friend need Enchanting)." },
        { "sell", "Sell on AH", "Count selling what you make on the auction house. Off: only a vendor (or disenchanting) gets anything back." },
        { "lack", "Patterns I lack", "Also use recipes taught by patterns you don't have yet. Their pattern's price shows in the Recipe column." },
    }) do
        local key = ck[1]
        local cb = UI.CheckLabel(c, ck[2], function(on) ns.db.ui[key] = on and true or false; ns.Refresh() end, ck[3])
        cb.frame:SetPoint("TOPLEFT", x, y - 3)
        cb.key = key
        checks[key] = cb
        x = x + (key == "de" and 102 or 100)
    end

    tables = { plan = makeTable(c, "plan"), now = makeTable(c, "now") }
    tables.now:Hide()

    footer = UI.Text(c, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 8)
    footer:SetPoint("RIGHT", c, "RIGHT", -126, 0)
    ns.footer = footer
    shopBtn = UI.Button(c, "Shopping list", 116, 24, function() ns.PrintShoppingList() end)
    shopBtn:SetPoint("BOTTOMRIGHT", 0, 2)
    UI.Tip(shopBtn, function(tt)
        tt:AddLine("Everything the plan needs")
        local total = 0
        for _, m in ipairs(ns.ShoppingList()) do
            total = total + (m.cost or 0)
            tt:AddDoubleLine(m.n .. " x " .. ns.ItemText(m.id) .. (m.vendor and grey("  vendor") or ""),
                m.cost and ns.Money(m.cost) or grey("no price"), 1, 1, 1, 1, 1, 1)
        end
        tt:AddDoubleLine("Total to buy", ns.Money(total))
        tt:AddLine("Click: print it in chat.", 0.6, 0.6, 0.6)
    end)
end

KM.RegisterPage({
    id = PAGE, group = "craft", label = "Skill-ups", icon = "Interface\\Icons\\INV_Misc_Book_11", order = 20,
    title = "Skill-ups",
    subtitle = "The cheapest way to level a profession: what to make at every skill point, and what it costs (or makes).",
    build = buildPage, refresh = refresh,
})

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if ScannerKing and ScannerKing.RegisterCallback then
        ScannerKing.RegisterCallback("Skillup_King", function(e)
            if e == "PRICES_UPDATED" or e == "SCAN_STARTED" or e == "SCAN_FINISHED" then ns.Refresh() end
        end)
    end
end)

---------------------------------------------------------------------------
-- The crown (quick action, tooltip) and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "skillup-plan", label = "Skill-ups", order = 21, func = function() ns.Toggle(true) end })

-- Your profession skills, on one line under the crown's title.
KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local parts = {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local cur, max = ns.Skill(p.id)
        if cur > 0 then parts[#parts + 1] = p.name .. " " .. cur .. "/" .. max end
    end
    if #parts > 0 then tt:AddLine("Skills: " .. table.concat(parts, ", "), 1, 1, 1, true) end
end)

KM.RegisterSettings({ id = "skillup", label = "Skillup", order = 21, rows = {
    { type = "header", label = "What counts as getting something back" },
    { type = "check", label = "Disenchant what you make", tip = "Count disenchanting it and selling the materials (you or a friend need Enchanting).",
      get = function() return ns.db.ui.de end, set = function(v) ns.db.ui.de = v; ns.Refresh() end },
    { type = "check", label = "Sell what you make on the auction house", tip = "Off: only a vendor (or disenchanting) gets anything back.",
      get = function() return ns.db.ui.sell end, set = function(v) ns.db.ui.sell = v; ns.Refresh() end },
    { type = "header", label = "Recipes" },
    { type = "check", label = "Use patterns I don't have yet", tip = "Their pattern's price shows in the Recipe column.",
      get = function() return ns.db.ui.lack end, set = function(v) ns.db.ui.lack = v; ns.Refresh() end },
    { type = "choice", label = "Open on", options = { { "plan", "Plan" }, { "now", "At my skill" } },
      get = function() return ns.db.ui.view end, set = function(v) ns.db.ui.view = v; ns.Refresh() end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/suk   open Skill-ups\n/suk tailoring   open it on a profession (first aid, smelting, ...)" },
} })
