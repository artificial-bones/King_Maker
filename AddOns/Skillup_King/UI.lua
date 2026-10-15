local _, ns = ...

-- The Skillup King window.
--   Top:   the professions, your skill and level, from / to, and what counts as
--          getting something back (disenchanting, selling on the auction house),
--          and whether patterns you don't have yet are allowed.
--   Plan:  from your skill to the target, what to make at each stretch, how many,
--          and what it costs. Trainer visits are on their own lines.
--   At my skill: every recipe you can make right now, cheapest skill point first.

local WIDTH, HEIGHT = 860, 560
local ROWS, ROW_H = 22, 18
local MAX_COLS = 8

local frame, profButtons, viewButtons, info, fromBox, toBox, checks, tbl, footer, empty, shopBtn
local offset = 0
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
-- The table
---------------------------------------------------------------------------

local COLS = {
    plan = {
        { key = "skill", label = "Skill", w = 70 },
        { key = "make", label = "Make", w = 235 },
        { key = "crafts", label = "Crafts", w = 55, justify = "RIGHT", tip = "How many, on average: yellow and green recipes don't always give a point." },
        { key = "each", label = "Each", w = 95, justify = "RIGHT", tip = "One craft: the materials, minus what you get back. Below zero, it makes money." },
        { key = "how", label = "Get back by", w = 85, tip = "The best of selling it, disenchanting it, or a vendor." },
        { key = "per", label = "Per point", w = 90, justify = "RIGHT" },
        { key = "total", label = "Total", w = 95, justify = "RIGHT" },
        { key = "learn", label = "Recipe", w = 95 },
    },
    now = {
        { key = "make", label = "Make", w = 235 },
        { key = "color", label = "Color", w = 55 },
        { key = "chance", label = "Chance", w = 55, justify = "RIGHT", tip = "The chance one craft gives a skill point." },
        { key = "mats", label = "Materials", w = 95, justify = "RIGHT", tip = "What the materials for one craft cost (auction house or vendor, the cheaper)." },
        { key = "back", label = "Get back", w = 95, justify = "RIGHT" },
        { key = "how", label = "By", w = 75 },
        { key = "per", label = "Per point", w = 90, justify = "RIGHT" },
        { key = "learn", label = "Recipe", w = 120 },
    },
}

local function makeTable(parent)
    local t = { headers = {}, rows = {} }
    for i = 1, MAX_COLS do
        local h = CreateFrame("Button", nil, parent)
        h:SetHeight(18)
        h:SetNormalFontObject("GameFontNormalSmall")
        h:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t.headers[i] = h
    end
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, parent)
        r:SetSize(WIDTH - 40, ROW_H)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.cells = {}
        for c = 1, MAX_COLS do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            r.cells[c] = fs
        end
        t.rows[i] = r
    end
    function t.layout(cols)
        local x = 0
        for i = 1, MAX_COLS do
            local col, h = cols[i], t.headers[i]
            if col then
                h.tip = col.tip
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", x, 0)
                h:SetWidth(col.w)
                h:SetText(col.label)
                local fs = h:GetFontString()
                if fs then fs:ClearAllPoints(); fs:SetPoint(col.justify or "LEFT", col.justify == "RIGHT" and -6 or 0, 0) end
                h:Show()
                for _, r in ipairs(t.rows) do
                    local c = r.cells[i]
                    c:ClearAllPoints()
                    c:SetPoint("LEFT", x, 0)
                    c:SetWidth(col.w - 6)
                    c:SetJustifyH(col.justify or "LEFT")
                    c:Show()
                end
                x = x + col.w
            else
                h:Hide()
                for _, r in ipairs(t.rows) do r.cells[i]:SetText(""); r.cells[i]:Hide() end
            end
        end
    end
    return t
end

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

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function rankName(max)
    for _, r in ipairs(ns.RANKS) do if max and max <= r.cap then return r.name end end
    return ns.RANKS[#ns.RANKS].name
end

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    ns.ClearCache()
    local p = prof()
    for _, b in ipairs(profButtons) do if b.id == p then b:LockHighlight() else b:UnlockHighlight() end end
    for _, b in ipairs(viewButtons) do if b.key == ns.db.ui.view then b:LockHighlight() else b:UnlockHighlight() end end
    for key, c in pairs(checks) do c:SetChecked(ns.db.ui[key]) end

    local cur, max = ns.Skill(p)
    info:SetText(ns.PROF_BY_ID[p].name .. ": " .. (cur > 0 and (cur .. " / " .. max .. "  " .. grey(rankName(max)))
        or grey("not learned on this character")) .. "     Level " .. ns.Level())
    local from, to = start(p), target(p)
    if not fromBox:HasFocus() then fromBox:SetText(tostring(from)) end
    if not toBox:HasFocus() then toBox:SetText(tostring(to)) end

    local view = ns.db.ui.view
    local cols = COLS[view]
    tbl.layout(cols)
    if view == "plan" then
        plan = ns.Plan(p, from, to)
        current = plan.steps
    else
        plan = nil
        current = ns.Options(p, from)
    end
    offset = math.max(0, math.min(offset, #current - ROWS))
    for i, r in ipairs(tbl.rows) do
        local e = current[i + offset]
        r.entry = e
        if e then
            for c, col in ipairs(cols) do r.cells[c]:SetText(view == "plan" and planCell(e, col.key) or nowCell(e, col.key)) end
            r:Show()
        else
            r:Hide()
        end
    end

    local text
    if not ScannerKing then
        text = "Skillup King needs Scanner King for prices."
    elseif #current == 0 then
        text = view == "plan" and "Nothing to plan: pick a target above your skill." or "Nothing you can make at this skill."
    end
    empty:SetText(text or "")
    local last = ScannerKing and ScannerKing.LastScan and ScannerKing.LastScan()
    local age = "Prices " .. (last and ScannerKing.PriceAge(last) or "not scanned yet") .. "."
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

local function numberBox(parent, onSet)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(40, 20)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(3)
    local function done(self)
        local n = tonumber(self:GetText())
        self:ClearFocus()
        onSet(n)
    end
    e:SetScript("OnEnterPressed", done)
    e:SetScript("OnEditFocusLost", function(self) local n = tonumber(self:GetText()); onSet(n) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.Refresh() end)
    return e
end

local function check(parent, key, label, tip)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", c, "RIGHT", 0, 1)
    t:SetText(label)
    c:SetScript("OnClick", function(self) ns.db.ui[key] = self:GetChecked() and true or false; ns.Refresh() end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(label)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    checks[key] = c
    return c
end

-- The materials for the whole plan, most expensive first.
function ns.ShoppingList()
    local p = prof()
    local pl = ns.Plan(p, start(p), target(p))
    local out = {}
    for _, m in ipairs(pl.mats) do
        table.insert(out, { id = m.id, n = m.n, cost = m.unit and m.unit * m.n, vendor = m.vendor })
    end
    return out
end

local function recipeTooltip(self)
    local e = self.entry
    local r = e and (e.r)
    if not r then return end
    local c = ns.Craft(r)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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

local function create()
    checks = {}
    frame = CreateFrame("Frame", "SkillupKingFrame", UIParent, "BackdropTemplate")
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
    if UISpecialFrames then table.insert(UISpecialFrames, "SkillupKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Skillup King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    viewButtons = {}
    local prev = title
    for _, v in ipairs({ { "plan", "Plan" }, { "now", "At my skill" } }) do
        local b = button(frame, v[2], 96, function() ns.db.ui.view = v[1]; offset = 0; ns.Refresh() end)
        b.key = v[1]
        b:SetPoint("LEFT", prev, "RIGHT", prev == title and 16 or 2, 0)
        table.insert(viewButtons, b)
        prev = b
    end
    local scan = button(frame, "Scan prices", 100, function() ns.ScanPrices() end)
    scan:SetPoint("TOPRIGHT", -36, -12)

    profButtons = {}
    for i, p in ipairs(ns.PROFESSIONS) do
        local b = button(frame, p.short, 90, function() ns.db.ui.prof = p.id; offset = 0; ns.Refresh() end)
        b.id = p.id
        b:SetPoint("TOPLEFT", 16 + (i - 1) * 92, -40)
        table.insert(profButtons, b)
    end

    info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", 16, -72)
    info:SetWidth(300)
    info:SetJustifyH("LEFT")

    local fromLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fromLabel:SetPoint("TOPLEFT", 330, -72)
    fromLabel:SetText("From")
    fromBox = numberBox(frame, function(n)
        local p = prof()
        ns.db.ui.from = ns.db.ui.from or {}
        ns.db.ui.from[p] = n and n > 0 and math.min(n, ns.MAX_SKILL - 1) or nil -- empty: your skill
        ns.Refresh()
    end)
    fromBox:SetPoint("LEFT", fromLabel, "RIGHT", 8, 0)
    local toLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toLabel:SetPoint("LEFT", fromBox, "RIGHT", 8, 0)
    toLabel:SetText("to")
    toBox = numberBox(frame, function(n)
        ns.db.ui.to = ns.db.ui.to or {}
        ns.db.ui.to[prof()] = n and n > 1 and math.min(n, ns.MAX_SKILL) or nil
        ns.Refresh()
    end)
    toBox:SetPoint("LEFT", toLabel, "RIGHT", 8, 0)

    local c1 = check(frame, "de", "Disenchant", "Count disenchanting what you make and selling the materials (you or a friend need Enchanting).")
    c1:SetPoint("TOPLEFT", 500, -66)
    local c2 = check(frame, "sell", "Sell on AH", "Count selling what you make on the auction house. Off: only a vendor (or disenchanting) gets anything back.")
    c2:SetPoint("LEFT", c1, "RIGHT", 70, 0)
    local c3 = check(frame, "lack", "Patterns I lack", "Also use recipes taught by patterns you don't have yet. Their pattern's price shows in the Recipe column.")
    c3:SetPoint("LEFT", c2, "RIGHT", 70, 0)

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetPoint("TOPLEFT", 16, -96)
    holder:SetPoint("BOTTOMRIGHT", -16, 36)
    tbl = makeTable(holder)
    for _, r in ipairs(tbl.rows) do
        r:SetScript("OnEnter", recipeTooltip)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    empty = holder:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -60)
    empty:SetWidth(600)
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 5)
        ns.Refresh()
    end)

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 16)
    footer:SetWidth(WIDTH - 160)
    footer:SetJustifyH("LEFT")
    shopBtn = button(frame, "Shopping list", 110, function() ns.PrintShoppingList() end)
    shopBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    shopBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Everything the plan needs")
        local total = 0
        for _, m in ipairs(ns.ShoppingList()) do
            total = total + (m.cost or 0)
            GameTooltip:AddDoubleLine(m.n .. " x " .. ns.ItemText(m.id) .. (m.vendor and grey("  vendor") or ""),
                m.cost and ns.Money(m.cost) or grey("no price"), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Total to buy", ns.Money(total))
        GameTooltip:AddLine("Click: print it in chat.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    shopBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame:SetScript("OnShow", ns.Refresh)
    frame:Hide()
end

function ns.PrintShoppingList()
    local p = prof()
    ns.Print("Shopping list, " .. ns.PROF_BY_ID[p].name .. " " .. start(p) .. " to " .. target(p) .. ":")
    for _, m in ipairs(ns.ShoppingList()) do
        DEFAULT_CHAT_FRAME:AddMessage("   " .. m.n .. " x " .. ns.ItemText(m.id) .. "  " .. (m.cost and ns.Money(m.cost) or "no price"))
    end
end

-- Prices for one profession: at the auction house, a Scanner King scan of everything it uses and makes.
function ns.ScanPrices()
    if not (ScannerKing and ScannerKing.Scan) then ns.Print("Scanning needs Scanner King.") return end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns.Print("Open the auction house to scan prices (or run a Deep Scan there for everything).")
        return
    end
    local list = ns.ItemsToScan(prof())
    ScannerKing.Scan({ items = list })
    ns.Print("Scanning " .. #list .. " items for " .. ns.PROF_BY_ID[prof()].name .. ".")
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

function ns.Toggle(show, profID)
    if not ns.db then return end
    if not frame then create() end
    pickProfession(profID)
    if show == nil then show = not frame:IsShown() end
    frame:SetShown(show)
    if show then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Minimap button, and fresh prices
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 230)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db or not Minimap then return end
    if not mini then
        mini = CreateFrame("Button", "SkillupKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function() ns.Toggle() end)
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
            GameTooltip:AddLine("Skillup King")
            for _, p in ipairs(ns.PROFESSIONS) do
                local cur, max = ns.Skill(p.id)
                if cur > 0 then GameTooltip:AddDoubleLine(p.name, cur .. " / " .. max, 1, 1, 1, 1, 1, 1) end
            end
            GameTooltip:AddLine("Click: open. Drag: move this button.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(ns.db.ui.button)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if ScannerKing and ScannerKing.RegisterCallback then
        ScannerKing.RegisterCallback("Skillup_King", function() ns.Refresh() end)
    end
end)
