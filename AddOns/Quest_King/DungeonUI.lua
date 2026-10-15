local _, ns = ...

-- The dungeon quest window (/qk dungeons, or the minimap button).
--   Left:  every dungeon in level order with how many of its quests you've done.
--          Gold: right for your level. Green: all done.
--   Right: the dungeon's levels, entrance and best level to run it; its quests with
--          your status, quest level, pickup level and full-XP level, and a map pin
--          for each giver. Click a quest for its chain, goal and reward;
--          right-click to tick it off yourself.
--   Route: the dungeons in level order with what to pick up, hub by hub, first.

local WIDTH, HEIGHT = 900, 580
local LEFT_W = 230
local ROWS, ROW_H = 16, 18
local INDENT = 12 -- per step of a chain

local frame, viewButtons, checks, list, pane, routeView, routeText
local title, levelLine, bestLine, noteLine, entranceBtn, headers, rows, detail, detailText, empty
local selected, selectedQuest, offset = nil, nil, 0
local shown = {}     -- the quests on show
local lines = {}     -- the rows: each quest, and under it its chain, first step indented deepest
local collapsed = {} -- quest -> true/false once you fold or open its chain
-- Folded unless you opened it; done quests start folded.
function ns.Folded(q)
    if collapsed[q] ~= nil then return collapsed[q] end
    return q.state == "done"
end

local function grey(t) return "|cff808080" .. t .. "|r" end
local function gold(t) return "|cffffd100" .. t .. "|r" end

local COLS = {
    { label = "Status", w = 72 },
    { label = "Quest", w = 190 },
    { label = "Level", w = 40, justify = "RIGHT", tip = "The quest's level." },
    { label = "Pick up", w = 50, justify = "RIGHT", tip = "The level you can take it at. ~ means an estimate (QuestieDB gives the exact level)." },
    { label = "Full XP to", w = 64, justify = "RIGHT", tip = "Up to this level the quest gives full XP; after that, less each level." },
    { label = "XP", w = 56, justify = "RIGHT", tip = "XP at your level (from QuestieDB). Grey: less than full, you've outlevelled it." },
    { label = "Giver", w = 142 },
}

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function commas(n)
    local s = tostring(math.floor(n))
    while true do
        local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end
ns.Commas = commas

-- An XP cell: at your level, grey when that's less than full.
local function xpText(full, now, done)
    if not full then return grey("?") end
    if done then return grey(commas(full)) end
    if now == 0 then return grey("0") end
    return now < full and grey(commas(now)) or commas(now)
end

local function detailFor(d, q)
    local lines = {}
    local src = ns.SOURCES[q.src]
    table.insert(lines, gold(q.name) .. (src and ("  " .. grey("[" .. src[1] .. "] " .. src[2])) or ""))
    local id = ns.QuestID(q)
    local min, guess = ns.MinLevel(q)
    table.insert(lines, "Level " .. (ns.QuestLevel(q) or "?") .. ", pick up at " .. (min and ((guess and "~" or "") .. min) or "?")
        .. ", full XP to " .. (ns.FullXPUntil(q) or "?") .. (id and grey("   quest " .. id) or ""))
    local full, now = ns.QuestXP(q)
    if full then
        table.insert(lines, "XP: " .. commas(full) .. (now ~= full and (" (" .. commas(now) .. " at your level)") or ""))
    end
    table.insert(lines, "Giver: " .. q.giver)
    if q.goal and q.goal ~= "" then table.insert(lines, "Goal: " .. q.goal) end
    if q.reward then table.insert(lines, "Reward: " .. q.reward) end
    if q.warn then table.insert(lines, "|cffff8040" .. q.warn .. "|r") end
    local m, x, y, from = ns.GiverPoint(q)
    table.insert(lines, m and grey(string.format("Giver at %.1f, %.1f (from %s).", x, y, from)) or grey("No coordinates known for the giver."))
    return table.concat(lines, "\n")
end

-- "     XP left: 12,300" (with a note when some quests have no XP data).
function ns.DungeonXPText(d)
    local xp, known, total = ns.DungeonXP(d)
    if total == 0 or known == 0 then return "" end
    return "     XP left: " .. gold(commas(xp)) .. (known < total and grey(" (" .. known .. " of " .. total .. " quests known)") or "")
end

local function refreshDungeon(d)
    title:SetText(d.name .. (d.new and grey("  new in Forever") or ""))
    local p = d.progress or ns.Progress(d)
    levelLine:SetText("Level " .. d.min .. (d.max ~= d.min and ("-" .. d.max) or "") .. "     Entrance: " .. d.at
        .. "     " .. (p.total > 0 and (p.done .. " of " .. p.total .. " done") or grey("no quests known yet"))
        .. ns.DungeonXPText(d))
    local from, to, n, total = ns.BestLevels(d)
    local level = ns.Level()
    if from then
        local here = level >= from and level <= to
        bestLine:SetText("Best at level " .. from .. (to ~= from and ("-" .. to) or "") .. ": "
            .. (n == total and ("all " .. total) or (n .. " of " .. total)) .. " quests can be picked up and give full XP."
            .. "  You're " .. level .. (here and "  |cff40c040(now's the time)|r" or ""))
    else
        bestLine:SetText(grey("No quest levels known yet."))
    end
    noteLine:SetText(d.note and grey(d.note) or "")

    shown = ns.VisibleQuests(d)
    lines = {}
    for _, q in ipairs(shown) do
        table.insert(lines, { q = q })
        if q.chain and not ns.Folded(q) then
            local nextStep = ns.NextStep(q)
            for i = #q.chain, 1, -1 do -- last step first, so the first step sits deepest
                table.insert(lines, { q = q, step = q.chain[i], index = i, depth = #q.chain - i + 1, next = i == nextStep })
            end
        end
    end
    offset = math.max(0, math.min(offset, #lines - ROWS))
    for i, r in ipairs(rows) do
        local line = lines[i + offset]
        r.line = line
        r.quest = line and line.q
        if line and not line.step then
            local q = line.q
            local st = ns.STATES[q.state]
            local min, guess = ns.MinLevel(q)
            local lowNow = min and level < min
            r.cells[1]:SetText(st[1] .. st[2] .. "|r")
            r.cells[2]:ClearAllPoints()
            r.cells[2]:SetPoint("LEFT", COLS[1].w, 0)
            r.cells[2]:SetWidth(COLS[2].w - 6)
            r.cells[2]:SetText((q.chain and grey(ns.Folded(q) and "[+] " or "[-] ") or "")
                .. (q.state == "done" and grey(q.name) or gold(q.name))
                .. (q.class and grey("  " .. q.class:sub(1, 1) .. q.class:sub(2):lower()) or ""))
            r.cells[3]:SetText(tostring(ns.QuestLevel(q) or "?"))
            r.cells[4]:SetText(min and ((lowNow and "|cffff6060" or "") .. (guess and "~" or "") .. min .. (lowNow and "|r" or "")) or grey("?"))
            local full = ns.FullXPUntil(q)
            r.cells[5]:SetText(full and ((level > full and "|cff808080" or "") .. full .. (level > full and "|r" or "")) or grey("?"))
            local full, now = ns.QuestXP(q)
            r.cells[6]:SetText(xpText(full, now, q.state == "done"))
            r.cells[7]:SetText(q.giver)
            r.pin:SetShown(ns.GiverPoint(q) ~= nil)
            r.bg:SetShown(true)
            if q == selectedQuest then r:LockHighlight() else r:UnlockHighlight() end
            r:Show()
        elseif line then
            local q, step = line.q, line.step
            local s = ns.StepState(q, step)
            local name, what = ns.StepText(step)
            r.cells[1]:SetText(s == "done" and "|cff40c040Done|r" or s == "active" and "|cffffd100In your log|r"
                or line.next and "|cffffd100Next >|r" or "")
            local indent = math.min(line.depth, 8) * INDENT
            r.cells[2]:ClearAllPoints()
            r.cells[2]:SetPoint("LEFT", COLS[1].w + indent, 0)
            r.cells[2]:SetWidth(COLS[2].w + COLS[3].w + COLS[4].w + COLS[5].w - 6 - indent)
            local color = s == "done" and "|cff808080" or line.next and "|cffffd100" or "|cffffffff"
            r.cells[2]:SetText(grey("- ") .. color .. name .. "|r" .. (step.this and grey("  (the dungeon)") or ""))
            r.cells[3]:SetText(""); r.cells[4]:SetText(""); r.cells[5]:SetText("")
            local full, now = ns.StepXP(q, step)
            r.cells[6]:SetText(full and xpText(full, now, s == "done") or "")
            r.cells[7]:SetText(what and (s == "done" and grey(what) or what) or "")
            r.pin:SetShown(ns.StepPoint(q, step, line.index) ~= nil)
            r.bg:SetShown(false)
            r:UnlockHighlight()
            r:Show()
        else
            r:Hide()
        end
    end
    if selectedQuest and not tContains(shown, selectedQuest) then selectedQuest = nil end
    selectedQuest = selectedQuest or shown[1]
    detailText:SetText(selectedQuest and detailFor(d, selectedQuest) or "")
    detail.child:SetHeight(math.max(detailText:GetStringHeight() + 8, 10))
    empty:SetText(#d.quests == 0 and "No quests are known for this dungeon yet (it isn't in the beta)."
        or #shown == 0 and "Nothing to show: every quest is done or hidden by the filters above." or "")
end

local function refreshRoute()
    local lines = { gold("Start these chains early"), " " }
    for _, e in ipairs(ns.EARLY_CHAINS) do table.insert(lines, "- " .. e) end
    table.insert(lines, " ")
    table.insert(lines, gold("The route: in level order, with what to pick up before each run"))
    for _, t in ipairs(ns.ROUTE) do
        local progress = {}
        for _, d in ipairs(ns.DUNGEONS) do
            if t.title:find(d.name, 1, true) then
                local p = ns.Progress(d)
                if p.total > 0 then table.insert(progress, d.name .. " " .. p.done .. "/" .. p.total) end
            end
        end
        table.insert(lines, " ")
        table.insert(lines, gold("Level " .. t.levels .. "   " .. t.title) .. "   " .. grey(t.runs)
            .. (#progress > 0 and ("   |cff40c040" .. table.concat(progress, ", ") .. " done|r") or ""))
        for _, p in ipairs(t.picks) do table.insert(lines, "   " .. "|cff4fc3f7" .. p[1] .. ":|r " .. p[2]) end
        if t.tip then table.insert(lines, "   " .. grey(t.tip)) end
    end
    routeText:SetText(table.concat(lines, "\n"))
    routeView.child:SetHeight(routeText:GetStringHeight() + 20)
end

function ns.RefreshDungeons()
    if not frame or not frame:IsShown() or not QuestKingDB then return end
    for key, c in pairs(checks) do c:SetChecked(QuestKingDB[key]) end
    local route = QuestKingDB.dqView == "route"
    for _, b in ipairs(viewButtons) do
        if (b.key == "route") == route then b:LockHighlight() else b:UnlockHighlight() end
    end
    local dungeons = ns.DungeonList()
    if not selected then
        for _, d in ipairs(dungeons) do
            if d.fits and d.progress.total > d.progress.done then selected = d break end
        end
        selected = selected or dungeons[1]
    end
    for i, b in ipairs(list) do
        local d = dungeons[i]
        b.dungeon = d
        if d then
            local p = d.progress
            local color = (p.total > 0 and p.done == p.total) and "|cff40c040" or d.fits and "|cffffd100" or "|cffffffff"
            b.name:SetText(color .. d.name .. "|r")
            b.count:SetText(p.total > 0 and (p.done .. "/" .. p.total) or grey("-"))
            b.lv:SetText(grey(d.min .. (d.max ~= d.min and ("-" .. d.max) or "")))
            if d == selected and not route then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
        else
            b:Hide()
        end
    end
    pane:SetShown(not route)
    routeView:SetShown(route)
    if route then refreshRoute() else refreshDungeon(selected) end
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

local function check(parent, key, label)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", c, "RIGHT", 0, 1)
    t:SetText(label)
    c:SetScript("OnClick", function(self) QuestKingDB[key] = self:GetChecked() and true or false; ns.RefreshDungeons() end)
    checks[key] = c
    return c
end

local function scrollText(parent)
    local s = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, s)
    child:SetSize(10, 10)
    s:SetScrollChild(child)
    s.child = child
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if fs.SetSpacing then fs:SetSpacing(2) end
    return s, fs
end

local function create()
    checks = {}
    frame = CreateFrame("Frame", "QuestKingDungeons", UIParent, "BackdropTemplate")
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
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestKingDungeons") end

    local head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 16, -14)
    head:SetText("Quest King: Dungeon Quests")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    viewButtons = {}
    local prev = head
    for _, v in ipairs({ { "dungeons", "Dungeons" }, { "route", "Route" } }) do
        local b = button(frame, v[2], 90, function() QuestKingDB.dqView = v[1]; ns.RefreshDungeons() end)
        b.key = v[1]
        b:SetPoint("LEFT", prev, "RIGHT", prev == head and 16 or 2, 0)
        table.insert(viewButtons, b)
        prev = b
    end
    local c1 = check(frame, "dqHide60", "Hide level 60")
    c1:SetPoint("TOPRIGHT", -250, -12)
    local c2 = check(frame, "dqHideDone", "Hide done")
    c2:SetPoint("LEFT", c1, "RIGHT", 90, 0)

    -- The dungeon list
    list = {}
    for i = 1, #ns.DUNGEONS do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(LEFT_W, 16)
        b:SetPoint("TOPLEFT", 16, -46 - (i - 1) * 16.5)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetPoint("LEFT", 2, 0)
        b.name:SetWidth(150)
        b.name:SetJustifyH("LEFT")
        if b.name.SetWordWrap then b.name:SetWordWrap(false) end
        b.lv = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.lv:SetPoint("LEFT", 152, 0)
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.count:SetPoint("RIGHT", -2, 0)
        b:SetScript("OnClick", function(self)
            selected, selectedQuest, offset = self.dungeon, nil, 0
            QuestKingDB.dqView = "dungeons"
            ns.RefreshDungeons()
        end)
        list[i] = b
    end

    -- One dungeon
    local x0 = 16 + LEFT_W + 16
    pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", x0, -44)
    pane:SetPoint("BOTTOMRIGHT", -16, 16)
    title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, -2)
    entranceBtn = button(pane, "Entrance waypoint", 130, function() if selected then ns.WaypointToEntrance(selected) end end)
    entranceBtn:SetPoint("TOPRIGHT", 0, 0)
    levelLine = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    levelLine:SetPoint("TOPLEFT", 0, -26)
    bestLine = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bestLine:SetPoint("TOPLEFT", 0, -42)
    noteLine = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteLine:SetPoint("TOPLEFT", 0, -58)
    noteLine:SetWidth(WIDTH - x0 - 16)
    noteLine:SetHeight(42)
    noteLine:SetJustifyH("LEFT")
    noteLine:SetJustifyV("TOP")

    local top = -104
    headers = {}
    local x = 0
    for i, col in ipairs(COLS) do
        local h = CreateFrame("Button", nil, pane)
        h:SetSize(col.w, 18)
        h:SetPoint("TOPLEFT", x, top)
        h:SetNormalFontObject("GameFontNormalSmall")
        h:SetText(col.label)
        local fs = h:GetFontString()
        if fs then fs:ClearAllPoints(); fs:SetPoint(col.justify or "LEFT", col.justify == "RIGHT" and -6 or 0, 0) end
        if col.tip then
            h:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(col.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        headers[i] = h
        x = x + col.w
    end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, pane)
        r:SetSize(x + 24, ROW_H)
        r:SetPoint("TOPLEFT", 0, top - 20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.cells = {}
        local cx = 0
        for c, col in ipairs(COLS) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.w - 6)
            fs:SetJustifyH(col.justify or "LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            r.cells[c] = fs
            cx = cx + col.w
        end
        r.pin = CreateFrame("Button", nil, r)
        r.pin:SetSize(16, 16)
        r.pin:SetPoint("LEFT", cx + 2, 0)
        r.pin:SetNormalTexture("Interface\\Icons\\INV_Misc_Map_01")
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.04)
        r.pin:SetScript("OnClick", function()
            local line = r.line
            if not line then return end
            if line.step then ns.WaypointToStep(line.q, line.step, line.index) else ns.WaypointToGiver(line.q) end
        end)
        r.pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.line and r.line.step and "Waypoint to where this step starts" or "Waypoint to the quest giver")
            GameTooltip:Show()
        end)
        r.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self, which)
            local line = self.line
            if not line then return end
            local q = line.q
            if which == "RightButton" then
                if line.step then ns.SetStepTicked(q, line.step, not ns.StepTicked(q, line.step))
                else ns.SetTicked(selected, q, not ns.Ticked(selected, q)) end
            elseif not line.step and q.chain and q == selectedQuest then
                collapsed[q] = not ns.Folded(q) -- clicking the selected quest folds or opens its chain
            end
            selectedQuest = q
            ns.RefreshDungeons()
        end)
        r:SetScript("OnEnter", function(self)
            local line = self.line
            if not line then return end
            local q = line.q
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if line.step then
                GameTooltip:AddLine("Step " .. line.index .. " of " .. #q.chain .. ": " .. q.name)
                GameTooltip:AddLine(line.step[1], 1, 1, 1, true)
                GameTooltip:AddLine("Start at the deepest step and work up. Right-click: tick this step off.", 0.6, 0.6, 0.6, true)
            else
                GameTooltip:AddLine(q.name)
                if q.goal and q.goal ~= "" then GameTooltip:AddLine(q.goal, 1, 1, 1, true) end
                GameTooltip:AddLine((q.chain and "Click again: fold or open its chain. " or "Click: details. ")
                    .. "Right-click: tick it off (or un-tick it).", 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        ns.RefreshDungeons()
    end)
    empty = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 0, top - 40)

    detail, detailText = scrollText(pane)
    detail:SetPoint("TOPLEFT", 0, top - 28 - ROWS * ROW_H)
    detail:SetPoint("BOTTOMRIGHT", -24, 0)
    detailText:SetWidth(WIDTH - x0 - 60)
    detail.child:SetWidth(WIDTH - x0 - 60)

    -- The route
    routeView, routeText = scrollText(frame)
    routeView:SetPoint("TOPLEFT", x0, -48)
    routeView:SetPoint("BOTTOMRIGHT", -36, 16)
    routeText:SetWidth(WIDTH - x0 - 60)
    routeView.child:SetWidth(WIDTH - x0 - 60)

    frame:SetScript("OnShow", ns.RefreshDungeons)
    frame:Hide()
end

function ns.ToggleDungeons(show)
    if not QuestKingDB then return end
    if not frame then create() end
    if show == nil then show = not frame:IsShown() end
    frame:SetShown(show)
    if show then ns.RefreshDungeons() end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(QuestKingDB.buttonAngle or 250)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not QuestKingDB or not Minimap then return end
    if not mini then
        mini = CreateFrame("Button", "QuestKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function() ns.ToggleDungeons() end)
        mini:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                QuestKingDB.buttonAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
                place()
            end)
        end)
        mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        mini:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Quest King: Dungeon Quests")
            local ready = 0
            for _, d in ipairs(ns.DungeonList()) do ready = ready + d.progress.ready + d.progress.active end
            GameTooltip:AddLine(ready .. " dungeon quests ready or in your log.", 1, 1, 1)
            GameTooltip:AddLine("Click: open. Drag: move this button.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(QuestKingDB.button)
end
