local _, KM = ...
local ns = KM.Module("Quest")
local UI = KM.UI
local C = UI.C

-- The Dungeon Quests page of the King Maker window (Characters > Dungeon Quests, /qk dungeons, /km dungeons).
--   Top:   Dungeons / Route tabs, and the Hide level 60 / Hide done checks.
--   Left:  every dungeon in level order with how many of its quests you've done.
--          Gold: right for your level. Green: all done.
--   Right: the dungeon's levels, entrance (Entrance waypoint) and best level to run it; its quests with your
--          status, quest level, pickup level and full-XP level, XP, giver and a map pin for each giver. Click a
--          quest for its chain, goal and reward in the pane below; right-click to tick it off yourself.
--   Route: the dungeons in level order with what to pick up, hub by hub, first.
-- Also here: the crown's quick action and tooltip line, the Home tile and the Settings section.

local LEFT_W, LIST_H = 206, 17
local INDENT = 12 -- per step of a chain
local DETAIL_H = 112

local page, tabs, checks, list, pane, routeView, routeText
local title, levelLine, bestLine, noteLine, tbl, detail, detailText
local selected, selectedQuest = nil, nil
local shown = {}     -- the quests on show
local lines = {}     -- the rows: each quest, and under it its chain, first step indented deepest
local collapsed = {} -- quest -> true/false once you fold or open its chain
-- Folded unless you opened it; done quests start folded.
function ns.Folded(q)
    if collapsed[q] ~= nil then return collapsed[q] end
    return q.state == "done"
end

local function grey(t) return UI.Hex(C.muted) .. t .. "|r" end
local function gold(t) return UI.Hex(C.accent) .. t .. "|r" end

local COLS = {
    { key = "status", label = "Status", w = 72 },
    { key = "quest", label = "Quest", w = 168 },
    { key = "level", label = "Level", w = 40, justify = "RIGHT", tip = "The quest's level." },
    { key = "pickup", label = "Pick up", w = 50, justify = "RIGHT", tip = "The level you can take it at. ~ means an estimate (QuestieDB gives the exact level)." },
    { key = "fullxp", label = "Full XP to", w = 64, justify = "RIGHT", tip = "Up to this level the quest gives full XP; after that, less each level." },
    { key = "xp", label = "XP", w = 52, justify = "RIGHT", tip = "XP at your level (from QuestieDB). Grey: less than full, you've outlevelled it." },
    { key = "giver", label = "Giver", w = 0 },
}

---------------------------------------------------------------------------
-- Text
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
    local out = {}
    local src = ns.SOURCES[q.src]
    table.insert(out, gold(q.name) .. (src and ("  " .. grey("[" .. src[1] .. "] " .. src[2])) or ""))
    local id = ns.QuestID(q)
    local min, guess = ns.MinLevel(q)
    table.insert(out, "Level " .. (ns.QuestLevel(q) or "?") .. ", pick up at " .. (min and ((guess and "~" or "") .. min) or "?")
        .. ", full XP to " .. (ns.FullXPUntil(q) or "?") .. (id and grey("   quest " .. id) or ""))
    local full, now = ns.QuestXP(q)
    if full then
        table.insert(out, "XP: " .. commas(full) .. (now ~= full and (" (" .. commas(now) .. " at your level)") or ""))
    end
    table.insert(out, "Giver: " .. q.giver)
    if q.goal and q.goal ~= "" then table.insert(out, "Goal: " .. q.goal) end
    if q.reward then table.insert(out, "Reward: " .. q.reward) end
    if q.warn then table.insert(out, UI.Hex(C.warn) .. q.warn .. "|r") end
    local m, x, y, from = ns.GiverPoint(q)
    table.insert(out, m and grey(string.format("Giver at %.1f, %.1f (from %s).", x, y, from)) or grey("No coordinates known for the giver."))
    return table.concat(out, "\n")
end

-- "     XP left: 12,300" (with a note when some quests have no XP data).
function ns.DungeonXPText(d)
    local xp, known, total = ns.DungeonXP(d)
    if total == 0 or known == 0 then return "" end
    return "     XP left: " .. gold(commas(xp)) .. (known < total and grey(" (" .. known .. " of " .. total .. " quests known)") or "")
end

---------------------------------------------------------------------------
-- One dungeon
---------------------------------------------------------------------------

local function questCell(cells, x, w)
    local fs = cells.quest
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(w)
end

local function pinFor(r)
    if r.pin then return r.pin end
    r.cells.giver:SetPoint("RIGHT", -26, 0) -- room for the pin
    local p = CreateFrame("Button", nil, r)
    p:SetSize(16, 16)
    p:SetPoint("RIGHT", -6, 0)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p:SetScript("OnClick", function()
        local line = r.data
        if not line then return end
        UI.Click()
        if line.step then ns.WaypointToStep(line.q, line.step, line.index) else ns.WaypointToGiver(line.q) end
    end)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.data and r.data.step and "Waypoint to where this step starts" or "Waypoint to the quest giver")
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.pin = p
    return p
end

local function fillRow(r, line, cells)
    local level = ns.Level()
    local q = line.q
    local pin = pinFor(r)
    if not line.step then
        local st = ns.STATES[q.state]
        local min, guess = ns.MinLevel(q)
        local lowNow = min and level < min
        cells.status:SetText(st[1] .. st[2] .. "|r")
        questCell(cells, COLS[2].x, COLS[2].w - 8)
        cells.quest:SetText((q.chain and grey(ns.Folded(q) and "[+] " or "[-] ") or "")
            .. (q.state == "done" and grey(q.name) or gold(q.name))
            .. (q.class and grey("  " .. q.class:sub(1, 1) .. q.class:sub(2):lower()) or ""))
        cells.level:SetText(tostring(ns.QuestLevel(q) or "?"))
        cells.pickup:SetText(min and ((lowNow and UI.Hex(C.bad) or "") .. (guess and "~" or "") .. min .. (lowNow and "|r" or "")) or grey("?"))
        local untilLv = ns.FullXPUntil(q)
        cells.fullxp:SetText(untilLv and (level > untilLv and grey(tostring(untilLv)) or tostring(untilLv)) or grey("?"))
        local full, now = ns.QuestXP(q)
        cells.xp:SetText(xpText(full, now, q.state == "done"))
        cells.giver:SetText(q.giver)
        pin:SetShown(ns.GiverPoint(q) ~= nil)
        r.zebra:SetShown(true)
    else
        local step = line.step
        local s = ns.StepState(q, step)
        local name, what = ns.StepText(step)
        cells.status:SetText(s == "done" and UI.Hex(C.good) .. "Done|r" or s == "active" and gold("In your log")
            or line.next and gold("Next >") or "")
        local indent = math.min(line.depth, 8) * INDENT
        questCell(cells, COLS[2].x + indent, COLS[2].w + COLS[3].w + COLS[4].w + COLS[5].w - 8 - indent)
        local color = s == "done" and UI.Hex(C.muted) or line.next and UI.Hex(C.accent) or "|cffffffff"
        cells.quest:SetText(grey("- ") .. color .. name .. "|r" .. (step.this and grey("  (the dungeon)") or ""))
        cells.level:SetText(""); cells.pickup:SetText(""); cells.fullxp:SetText("")
        local full, now = ns.StepXP(q, step)
        cells.xp:SetText(full and xpText(full, now, s == "done") or "")
        cells.giver:SetText(what and (s == "done" and grey(what) or what) or "")
        pin:SetShown(ns.StepPoint(q, step, line.index) ~= nil)
        r.zebra:SetShown(false)
    end
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
            .. "  You're " .. level .. (here and ("  " .. UI.Hex(C.good) .. "(now's the time)|r") or ""))
    else
        bestLine:SetText(grey("No quest levels known yet."))
    end
    noteLine:SetText(d.note and grey(d.note) or "")

    shown = ns.VisibleQuests(d)
    lines = {}
    local sel
    if selectedQuest and not tContains(shown, selectedQuest) then selectedQuest = nil end
    selectedQuest = selectedQuest or shown[1]
    for _, q in ipairs(shown) do
        local line = { q = q }
        if q == selectedQuest then sel = line end
        table.insert(lines, line)
        if q.chain and not ns.Folded(q) then
            local nextStep = ns.NextStep(q)
            for i = #q.chain, 1, -1 do -- last step first, so the first step sits deepest
                table.insert(lines, { q = q, step = q.chain[i], index = i, depth = #q.chain - i + 1, next = i == nextStep })
            end
        end
    end
    tbl.selected = sel
    tbl.emptyText = #d.quests == 0 and "No quests are known for this dungeon yet (it isn't in the beta)."
        or "Nothing to show: every quest is done or hidden by the filters above."
    tbl:SetRows(lines, fillRow)
    detailText:SetText(selectedQuest and detailFor(d, selectedQuest) or "")
    detail:SetContentHeight((detailText:GetStringHeight() or 0) + 8)
end

---------------------------------------------------------------------------
-- The route
---------------------------------------------------------------------------

local function refreshRoute()
    local out = { gold("Start these chains early"), " " }
    for _, e in ipairs(ns.EARLY_CHAINS) do table.insert(out, "- " .. e) end
    table.insert(out, " ")
    table.insert(out, gold("The route: in level order, with what to pick up before each run"))
    for _, t in ipairs(ns.ROUTE) do
        local progress = {}
        for _, d in ipairs(ns.DUNGEONS) do
            if t.title:find(d.name, 1, true) then
                local p = ns.Progress(d)
                if p.total > 0 then table.insert(progress, d.name .. " " .. p.done .. "/" .. p.total) end
            end
        end
        table.insert(out, " ")
        table.insert(out, gold("Level " .. t.levels .. "   " .. t.title) .. "   " .. grey(t.runs)
            .. (#progress > 0 and ("   " .. UI.Hex(C.good) .. table.concat(progress, ", ") .. " done|r") or ""))
        for _, p in ipairs(t.picks) do table.insert(out, "   " .. UI.Hex(C.info) .. p[1] .. ":|r " .. p[2]) end
        if t.tip then table.insert(out, "   " .. grey(t.tip)) end
    end
    routeText:SetText(table.concat(out, "\n"))
    routeView:SetContentHeight((routeText:GetStringHeight() or 0) + 20)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function refresh()
    if not page or not QuestKingDB then return end
    for key, c in pairs(checks) do c:SetChecked(QuestKingDB[key]) end
    local route = QuestKingDB.dqView == "route"
    tabs:Select(route and "route" or "dungeons")
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
            local color = (p.total > 0 and p.done == p.total) and UI.Hex(C.good) or d.fits and UI.Hex(C.accent) or "|cffffffff"
            b:SetLabel(color .. d.name .. "|r")
            b.count:SetText(p.total > 0 and (p.done .. "/" .. p.total) or grey("-"))
            b.lv:SetText(grey(d.min .. (d.max ~= d.min and ("-" .. d.max) or "")))
            b:SetActive(d == selected and not route)
            b:Show()
        else
            b:Hide()
        end
    end
    pane:SetShown(not route)
    routeView:SetShown(route)
    if route then refreshRoute() elseif selected then refreshDungeon(selected) end
end

-- Redraws the page if it's the one showing (bag and quest log changes call this).
function ns.RefreshDungeons() KM.Refresh("dungeons") end

-- Opens (true), closes (false) or toggles (nil) the page.
function ns.ToggleDungeons(show)
    if not QuestKingDB then return end
    if show == nil then show = not KM.IsShown("dungeons") end
    if show then KM.Show("dungeons") elseif KM.IsShown("dungeons") then KM.Toggle(false) end
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function setView(view)
    QuestKingDB.dqView = view
    ns.RefreshDungeons()
end

local function check(parent, key, label, tip)
    local cb = UI.CheckLabel(parent, label, function(v) QuestKingDB[key] = v and true or false; ns.RefreshDungeons() end, tip)
    checks[key] = cb
    return cb
end

local function dungeonButton(parent, i)
    local b = UI.Button(parent, "", LEFT_W - 12, LIST_H - 1, function(self)
        if not self.dungeon then return end
        selected, selectedQuest = self.dungeon, nil
        tbl.offset = 0
        setView("dungeons")
    end, "ghost")
    b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * LIST_H)
    b:SetPadding(6, 76)
    b.label:SetJustifyH("LEFT")
    UI.Font(b.label, 11)
    b.lv = UI.Text(b, 10, C.muted, "LEFT")
    b.lv:SetPoint("RIGHT", -34, 0)
    b.lv:SetWidth(40)
    b.count = UI.Text(b, 10, C.dim, "RIGHT")
    b.count:SetPoint("RIGHT", -6, 0)
    return b
end

local function buildPage(c)
    page = c
    checks = {}

    tabs = UI.Tabs(c, { { id = "dungeons", label = "Dungeons", w = 96 }, { id = "route", label = "Route", w = 80 } }, setView)
    tabs:SetPoint("TOPLEFT", 0, 0)
    local hideDone = check(c, "dqHideDone", "Hide done", "Leave out the quests you've done.")
    hideDone.frame:SetPoint("TOPRIGHT", 0, -3)
    local hide60 = check(c, "dqHide60", "Hide level 60", "Leave out the level 60 quests (raid attunements and the like).")
    hide60.frame:SetPoint("RIGHT", hideDone.frame, "LEFT", -18, 0)

    -- The dungeon list
    local side = CreateFrame("Frame", nil, c)
    side:SetPoint("TOPLEFT", 0, -34)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(LEFT_W)
    UI.Fill(side, { 0, 0, 0, 0.18 })
    UI.Border(side)
    list = {}
    for i = 1, #ns.DUNGEONS do list[i] = dungeonButton(side, i) end

    local right = CreateFrame("Frame", nil, c)
    right:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    -- One dungeon
    pane = CreateFrame("Frame", nil, right)
    pane:SetAllPoints(right)
    title = UI.Text(pane, 15, C.text)
    title:SetPoint("TOPLEFT", 0, -2)
    local entrance = UI.Button(pane, "Entrance waypoint", 140, 22, function() if selected then ns.WaypointToEntrance(selected) end end)
    entrance:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(entrance, "A waypoint to the dungeon's entrance (from QuestieDB; TomTom's arrow when you have it).")
    levelLine = UI.Text(pane, 11, C.text)
    levelLine:SetPoint("TOPLEFT", 0, -28)
    levelLine:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    bestLine = UI.Text(pane, 11, C.text)
    bestLine:SetPoint("TOPLEFT", 0, -44)
    bestLine:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    noteLine = UI.Para(pane, 10, C.muted, 540)
    noteLine:SetPoint("TOPLEFT", 0, -60)
    noteLine:SetHeight(28)

    tbl = UI.Table(pane, COLS, 20, {
        noSort = true, fontSize = 11,
        onClick = function(line, which)
            local q = line.q
            if which == "RightButton" then
                if line.step then ns.SetStepTicked(q, line.step, not ns.StepTicked(q, line.step))
                else ns.SetTicked(selected, q, not ns.Ticked(selected, q)) end
            elseif not line.step and q.chain and q == selectedQuest then
                collapsed[q] = not ns.Folded(q) -- clicking the selected quest folds or opens its chain
            end
            selectedQuest = q
            ns.RefreshDungeons()
        end,
        onEnter = function(r)
            local line = r.data
            if not line then return end
            local q = line.q
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
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
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, -94)
    tbl:SetPoint("BOTTOMRIGHT", 0, DETAIL_H + 8)
    tbl.fill = fillRow
    ns.table = tbl

    local box = UI.Panel(pane, C.panel)
    box:SetPoint("BOTTOMLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    box:SetHeight(DETAIL_H)
    detail = UI.Scroll(box)
    detail:SetPoint("TOPLEFT", 10, -8)
    detail:SetPoint("BOTTOMRIGHT", -10, 8)
    detailText = UI.Para(detail.child, 11, C.text, 520)
    detailText:SetPoint("TOPLEFT", 0, 0)
    if detailText.SetSpacing then detailText:SetSpacing(2) end
    ns.detailText = detailText

    -- The route
    routeView = UI.Scroll(right)
    routeView:SetPoint("TOPLEFT", 0, 0)
    routeView:SetPoint("BOTTOMRIGHT", 0, 0)
    routeText = UI.Para(routeView.child, 11, C.text, 530)
    routeText:SetPoint("TOPLEFT", 0, 0)
    if routeText.SetSpacing then routeText:SetSpacing(2) end
    routeView:Hide()
end

KM.RegisterPage({
    id = "dungeons", group = "char", label = "Dungeon Quests", icon = "Interface\\Icons\\INV_Misc_Note_02", order = 10,
    title = "Dungeon Quests",
    subtitle = "Every Horde dungeon quest from 13 to 60: what you've done, what's next and where to go.",
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

-- Dungeon quests you could pick up now, and those in your log.
local function counts()
    local ready, active = 0, 0
    for _, d in ipairs(ns.DungeonList()) do ready, active = ready + d.progress.ready, active + d.progress.active end
    return ready, active
end
ns.ReadyCounts = counts

KM.RegisterQuickAction({ id = "quest-dungeons", label = "Dungeon Quests", order = 50, func = function() ns.ToggleDungeons(true) end })

KM.RegisterTooltip(function(tt)
    if not QuestKingDB then return end
    local ready, active = counts()
    tt:AddLine("Dungeon quests: " .. ready .. " ready, " .. active .. " in your log.", 1, 1, 1)
end)

KM.RegisterHomeTile({ id = "quest", order = 50, get = function()
    if not QuestKingDB then return nil end
    local ready, active = counts()
    return "Dungeon quests", tostring(ready) .. " ready", active .. " in your log", ready > 0 and C.text or C.dim
end })

KM.RegisterSettings({ id = "quest", label = "Quest", order = 50, rows = {
    { type = "header", label = "Bags" },
    { type = "check", label = "Red X on quest items no quest needs", tip = "A small red X in the corner of a bag slot whose quest item no quest in your log needs.",
      get = function() return QuestKingDB.marks end, set = function(v) QuestKingDB.marks = v; ns.Refresh() end },
    { type = "check", label = "Say why in the item's tooltip", tip = "\"Quest King: safe to delete\" and the reason, on those items.",
      get = function() return QuestKingDB.tooltip end, set = function(v) QuestKingDB.tooltip = v end },
    { type = "header", label = "Dungeon Quests" },
    { type = "check", label = "Hide level 60 quests", get = function() return QuestKingDB.dqHide60 end,
      set = function(v) QuestKingDB.dqHide60 = v; ns.RefreshDungeons() end },
    { type = "check", label = "Hide quests you've done", get = function() return QuestKingDB.dqHideDone end,
      set = function(v) QuestKingDB.dqHideDone = v; ns.RefreshDungeons() end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/qk   list quest items you can delete\n/qk dungeons   the Dungeon Quests page\n/qk route   the dungeon route\n"
        .. "/qk marks on|off   the red X on bag slots\n/qk tooltip on|off   the tooltip line" },
} })
