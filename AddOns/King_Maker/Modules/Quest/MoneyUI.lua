local _, KM = ...
local ns = KM.Module("Quest")
local UI = KM.UI
local C = UI.C

-- The Quest Gold page of the King Maker window (Gold > Quest Gold, /qk gold, /km questgold).
--   Left:  the zones with quests of level 48+ for this character, most gold left first: quests left / total, and
--          what they're worth.
--   Right: the zone: levels, how many quests are left and their worth (gold + items - hand-ins); its quests, the ones you can do first, with status, level, gold (~ estimated), the best reward
--          and what it fetches, the hand-in cost and the total; the quest you click, in detail, below.
-- Also here: the crown's quick action and tooltip line, the Home tile and the Settings section.

local LEFT_W, LIST_H, MAX_ZONES = 230, 17, 40   -- zone rows: as many as the side panel holds, the wheel scrolls
local DETAIL_H = 104

local page, side, list, title, sumLine, noteLine, hideDone, tbl, detail, detailText
local selected, selectedQuest
local zones = {}
local zoneOffset = 0

local function grey(t) return UI.Hex(C.muted) .. t .. "|r" end
local function gold(t) return UI.Hex(C.accent) .. t .. "|r" end
local function money(c) return KM.Money(c - c % 100) end -- gold and silver; copper is noise here
local function moneyFull(c) return KM.Money(c) end

local STATES = {
    ready = { "Ready", C.good }, log = { "In your log", C.accent }, low = { "Level ", C.bad },
    locked = { "After another", C.muted }, done = { "Done", C.muted }, nodata = { "Not in Forever", C.muted },
}
local ORDER = { log = 1, ready = 2, low = 3, locked = 4, done = 5, nodata = 6 }

-- Every column has a fixed width and they add up to the pane (521 wide = 763 - LEFT_W - 12): the reward used to be a
-- middle w = 0 column, which UI.Table only stretches when it's last, so the money columns were drawn over it. Long
-- names truncate; the row's tooltip has them in full.
local function statusTip(tt)
    tt:AddLine("Status")
    local function line(st, text) tt:AddDoubleLine(UI.Hex(STATES[st][2]) .. STATES[st][1] .. "|r", text, 1, 1, 1, 1, 1, 1) end
    line("log", "in your quest log")
    line("ready", "you can pick it up")
    tt:AddDoubleLine(UI.Hex(C.bad) .. "Level 52|r", "you need that level first", 1, 1, 1, 1, 1, 1)
    line("locked", "comes after a quest you haven't done")
    line("done", "this character has done it")
    line("nodata", "the server doesn't know it: not counted")
end

local COLS = {
    { key = "status", label = "Status", w = 74, tip = statusTip },
    { key = "quest", label = "Quest", w = 112, tip = "Gold: still to do. dungeon or group: needs a dungeon or a group. Long names are cut short; hover a line for the full one." },
    { key = "level", label = "Lv", w = 24, justify = "RIGHT", tip = "The quest's level." },
    { key = "gold", label = "Gold", w = 56, justify = "RIGHT", tip = "What it pays. ~ means an estimate: King Maker hasn't seen Forever's real amount yet, so it uses the typical gold of quests within two levels it has seen (at least 1g)." },
    { key = "reward", label = "Best reward", w = 90, tip = "The reward item that fetches the most (auction house after its cut, or a vendor), and any item it always gives." },
    { key = "rvalue", label = "Item", w = 50, justify = "RIGHT", tip = "What the reward items fetch." },
    { key = "cost", label = "Hand in", w = 48, justify = "RIGHT", tip = "What the items you hand in would sell for (only ones with an auction price)." },
    { key = "worth", label = "Worth", w = 58, justify = "RIGHT", tip = "Gold + the best reward + items it always gives - the hand-in." },
}
ns.goldCols, ns.goldPaneW = COLS, 763 - LEFT_W - 12

local function itemText(id, count)
    local name, q
    if C_Item and C_Item.GetItemInfo then
        local ok, n, _, quality = pcall(C_Item.GetItemInfo, id)
        if ok then name, q = n, quality end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    local hex = UI.QUALITY and UI.QUALITY[q or 1] or "ffffff"
    return "|cff" .. hex .. (name or ("Item " .. id)) .. "|r" .. ((count or 1) > 1 and grey(" x" .. count) or "")
end

---------------------------------------------------------------------------
-- One zone
---------------------------------------------------------------------------

local function stateText(row)
    local st = STATES[row.state]
    local text = st[1]
    if row.state == "low" then text = text .. row.info.min end
    return UI.Hex(st[2]) .. text .. "|r"
end

local function fillRow(r, row, cells)
    local v, i = row.value, row.info
    local dim = row.state == "done" or row.state == "nodata"
    cells.status:SetText(stateText(row))
    cells.quest:SetText((dim and grey(i.title) or gold(i.title))
        .. (i.flags:find("d") and grey("  dungeon") or i.flags:find("e") and grey("  group") or ""))
    cells.level:SetText(tostring(i.level))
    cells.gold:SetText((v.guess and grey("~") or "") .. money(v.gold))
    local rw = v.rewards
    local reward = rw.best and itemText(rw.best.item, rw.best.count) or ""
    if #rw.items > 0 then
        reward = reward .. (reward ~= "" and grey(" + ") or "") .. itemText(rw.items[1].item, rw.items[1].count)
            .. (#rw.items > 1 and grey(" +" .. (#rw.items - 1)) or "")
    end
    cells.reward:SetText(reward ~= "" and reward or grey("-"))
    local items = (rw.best and rw.best.value or 0) + v.items
    cells.rvalue:SetText(items > 0 and money(items) or grey("-"))
    cells.cost:SetText(v.cost > 0 and (UI.Hex(C.bad) .. money(v.cost) .. "|r") or grey("-"))
    cells.worth:SetText(dim and grey(money(v.worth)) or money(v.worth))
end

local function detailFor(row)
    local i, v = row.info, row.value
    local out = { gold(i.title) .. grey("   quest " .. i.id .. ", level " .. i.level .. ", from level " .. (i.min or "?")) }
    table.insert(out, "Gold: " .. moneyFull(v.gold) .. (v.guess and grey("  (estimate: looked up when you enter the zone, or learned when you pick it up or hand it in)") or grey("  (Forever's real amount)")))
    local rw = v.rewards
    if #rw.choices > 0 then
        local parts = {}
        for _, e in ipairs(rw.choices) do
            parts[#parts + 1] = itemText(e.item, e.count) .. " " .. (e.value and money(e.value) or grey("?"))
        end
        table.insert(out, "Choose one: " .. table.concat(parts, ",  "))
    end
    if #rw.items > 0 then
        local parts = {}
        for _, e in ipairs(rw.items) do parts[#parts + 1] = itemText(e.item, e.count) .. " " .. (e.value and money(e.value) or grey("?")) end
        table.insert(out, "Also gives: " .. table.concat(parts, ",  "))
    end
    if #i.hands > 0 then
        local parts = {}
        for k = 1, #i.hands, 2 do
            local each, priced = ns.SellsFor(i.hands[k])
            parts[#parts + 1] = itemText(i.hands[k], i.hands[k + 1]) .. " " .. (priced and each and money(each * (i.hands[k + 1] or 1)) or grey("quest item"))
        end
        table.insert(out, "Hand in: " .. table.concat(parts, ",  "))
    end
    if i.prev ~= 0 then
        local p = ns.QuestInfo(i.prev)
        table.insert(out, "After: " .. (p and p.title or ("quest " .. i.prev)) .. (ns.QuestDone(i.prev) and grey("  (done)") or ""))
    end
    table.insert(out, "Worth: " .. gold(moneyFull(v.worth)) .. grey("  = gold + best reward + other items - hand-in"))
    return table.concat(out, "\n")
end

local function refreshZone(z)
    title:SetText(z.name)
    sumLine:SetText("Level " .. z.lo .. (z.hi ~= z.lo and ("-" .. z.hi) or "") .. "     "
        .. z.left .. " of " .. z.total .. " quests left, worth " .. gold(money(z.worth))
        .. grey("  (gold " .. money(z.gold) .. ")"))
    noteLine:SetText((z.guesses > 0 and grey(z.guesses .. " of those use an estimated gold amount (~): the real ones are looked up when you enter the zone.")
        or grey("Every gold amount here is Forever's real one."))
        .. (z.missing > 0 and grey("  " .. z.missing .. " more the game has no data on (not in Forever yet): listed last, not counted.") or ""))

    local rows = {}
    for _, q in ipairs(z.quests) do
        local state = ns.QuestState(q)
        if not (ns.db.qgHideDone and state == "done") then
            rows[#rows + 1] = { id = q, info = ns.QuestInfo(q), value = ns.QuestValue(q), state = state }
        end
    end
    table.sort(rows, function(a, b)
        if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
        if a.value.worth ~= b.value.worth then return a.value.worth > b.value.worth end
        return a.id < b.id
    end)
    local sel
    for _, row in ipairs(rows) do if row.id == selectedQuest then sel = row end end
    sel = sel or rows[1]
    selectedQuest = sel and sel.id
    tbl.selected = sel
    tbl.emptyText = "Every quest here is done (or hidden by Hide done)."
    tbl:SetRows(rows, fillRow)
    detailText:SetText(sel and detailFor(sel) or "")
    detail:SetContentHeight((detailText:GetStringHeight() or 0) + 8)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

-- How many zone rows fit the side panel (it is the page's full height: 557 in the window).
local function zoneRows()
    local h = side and side:GetHeight() or 0
    if not h or h <= 0 then h = 557 end
    return math.max(1, math.min(MAX_ZONES, math.floor((h - 12) / LIST_H)))
end
ns.QuestZoneRows = zoneRows

local function drawZones()
    local rows = zoneRows()
    zoneOffset = math.max(0, math.min(zoneOffset, #zones - rows))
    for k, b in ipairs(list) do
        local e = k <= rows and zones[k + zoneOffset]
        b.zone = e or nil
        if e then
            local color = e.left == 0 and UI.Hex(C.good) or "|cffffffff"
            b:SetLabel(color .. e.name .. "|r")
            b.count:SetText(e.left .. "/" .. e.total)
            b.worth:SetText(e.left > 0 and money(e.worth) or grey("done"))
            b:SetActive(e.map == selected)
            b:Show()
        else
            b:Hide()
        end
    end
end

local function refresh()
    if not page or not ns.db then return end
    hideDone:SetChecked(ns.db.qgHideDone)
    zones = ns.Zones()
    local z
    for _, e in ipairs(zones) do if e.map == selected then z = e end end
    z = z or zones[1]
    selected = z and z.map
    drawZones()
    if z then refreshZone(z) end
end

function ns.RefreshQuestGold() if page then KM.Refresh("questgold") end end

function ns.ToggleQuestGold(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("questgold") end
    if show then KM.Show("questgold") elseif KM.IsShown("questgold") then KM.Toggle(false) end
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function zoneButton(parent, k)
    local b = UI.Button(parent, "", LEFT_W - 12, LIST_H - 1, function(self)
        if not self.zone then return end
        selected, selectedQuest = self.zone.map, nil
        tbl.offset = 0
        ns.RefreshQuestGold()
    end, "ghost")
    b:SetPoint("TOPLEFT", 6, -6 - (k - 1) * LIST_H)
    b:SetPadding(6, 100)
    b.label:SetJustifyH("LEFT")
    UI.Font(b.label, 11)
    b.count = UI.Text(b, 10, C.muted, "RIGHT")
    b.count:SetPoint("RIGHT", -66, 0)
    b.count:SetWidth(34)
    b.worth = UI.Text(b, 10, C.text, "RIGHT")
    b.worth:SetPoint("RIGHT", -6, 0)
    b.worth:SetWidth(58)
    UI.Tip(b, function(tt)
        local z = b.zone
        if not z then return end
        tt:AddLine(z.name)
        tt:AddLine(z.left .. " of " .. z.total .. " quests left for this character, worth " .. money(z.worth) .. ": gold + rewards - hand-ins.", 1, 1, 1, true)
        tt:AddLine("Zones are sorted by what's left to earn.", 0.6, 0.6, 0.6)
    end)
    return b
end

local function buildPage(c)
    page = c
    side = CreateFrame("Frame", nil, c)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(LEFT_W)
    if side.SetClipsChildren then side:SetClipsChildren(true) end
    UI.Fill(side, { 0, 0, 0, 0.18 })
    UI.Border(side)
    list = {}
    for k = 1, MAX_ZONES do list[k] = zoneButton(side, k) end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, d)
        zoneOffset = zoneOffset - d * 3
        drawZones()
    end)
    side:SetScript("OnSizeChanged", function() if page and #zones > 0 then drawZones() end end)
    ns.goldSide = side

    local pane = CreateFrame("Frame", nil, c)
    pane:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    pane:SetPoint("BOTTOMRIGHT", 0, 0)
    title = UI.Text(pane, 15, C.text)
    title:SetPoint("TOPLEFT", 0, -2)
    hideDone = UI.CheckLabel(pane, "Hide done", function(v) ns.db.qgHideDone = v and true or false; ns.RefreshQuestGold() end,
        "Leave out the quests this character has done.")
    hideDone.frame:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -3)
    sumLine = UI.Text(pane, 11, C.text)
    sumLine:SetPoint("TOPLEFT", 0, -28)
    sumLine:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    noteLine = UI.Text(pane, 10, C.muted)
    noteLine:SetPoint("TOPLEFT", 0, -44)
    noteLine:SetPoint("RIGHT", pane, "RIGHT", 0, 0)

    tbl = UI.Table(pane, COLS, 20, {
        noSort = true, fontSize = 11,
        onClick = function(row)
            selectedQuest = row.id
            ns.RefreshQuestGold()
        end,
        onEnter = function(r)
            local row = r.data
            if not row then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:AddLine(row.info.title)
            GameTooltip:AddLine(stateText(row), 1, 1, 1)
            local rw = row.value.rewards
            if rw.best then
                GameTooltip:AddDoubleLine("Best reward", itemText(rw.best.item, rw.best.count), 0.78, 0.78, 0.78, 1, 1, 1)
            end
            for _, e in ipairs(rw.items) do
                GameTooltip:AddDoubleLine("Also gives", itemText(e.item, e.count), 0.78, 0.78, 0.78, 1, 1, 1)
            end
            GameTooltip:AddLine("Click for the details below.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, -62)
    tbl:SetPoint("BOTTOMRIGHT", 0, DETAIL_H + 8)
    tbl.fill = fillRow
    ns.goldTable = tbl

    local box = UI.Panel(pane, C.panel)
    box:SetPoint("BOTTOMLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    box:SetHeight(DETAIL_H)
    detail = UI.Scroll(box)
    detail:SetPoint("TOPLEFT", 10, -8)
    detail:SetPoint("BOTTOMRIGHT", -10, 8)
    detailText = UI.Para(detail.child, 11, C.text, 560)
    detailText:SetPoint("TOPLEFT", 0, 0)
    if detailText.SetSpacing then detailText:SetSpacing(2) end
    ns.goldDetail = detailText
end

KM.RegisterPage({
    id = "questgold", group = "gold", label = "Quest Gold", icon = "Interface\\Icons\\INV_Scroll_03", order = 20,
    title = "Quest Gold",
    subtitle = "Every quest from level 48 up, zone by zone: what's left for this character and what it's worth.",
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

-- The best zone for this character: name, quests left, worth.
local function best()
    local z = ns.Zones()[1]
    if not z or z.left == 0 then return nil end
    return z.name, z.left, z.worth
end
ns.BestQuestZone = best

KM.RegisterQuickAction({ id = "quest-gold", label = "Quest Gold", order = 50, func = function() ns.ToggleQuestGold(true) end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local name, left, worth = best()
    if name then tt:AddLine("Quest gold: " .. name .. ", " .. left .. " quests worth " .. money(worth) .. ".", 1, 1, 1) end
end)

-- Home: the best zone (Best right now) and what's left in the zone you're in (Needs your attention).
local VALUE_TIP = "Quest gold is the reward gold of quests from level 48 up this character hasn't done, plus what the best reward item sells for (auction house after the cut, or a vendor), minus what the items you hand in would sell for."

KM.RegisterHomeCard({ kind = "best", id = "quest", order = 40, get = function()
    if not ns.db then return nil end
    local name, left, worth = best()
    if not name then return nil end
    return { label = "Quests", sub = name .. ", " .. left .. " left", value = money(worth), icon = "Interface\Icons\INV_Misc_Note_01",
        page = "questgold", tip = "The zone where this character has the most quest gold left: " .. name .. ", " .. left .. " quests worth "
            .. moneyFull(worth) .. ". " .. VALUE_TIP .. " Click for Quest Gold." }
end })

KM.RegisterHomeCard({ kind = "attention", id = "quest-here", order = 60, get = function()
    if not (ns.db and C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local maps = { [map] = true }
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if info and info.parentMapID then maps[info.parentMapID] = true end
    for _, z in ipairs(ns.Zones()) do
        if maps[z.map] and z.left > 0 and z.worth > 0 then
            return { { text = z.name .. ": " .. z.left .. " quest" .. (z.left == 1 and "" or "s") .. " left here", color = C.info,
                value = money(z.worth), page = "questgold",
                tip = "You're in " .. z.name .. ": " .. z.left .. " quests worth " .. moneyFull(z.worth) .. " left for this character. " .. VALUE_TIP } }
        end
    end
end })

KM.RegisterSettings({ id = "quest", label = "Quest", order = 50, rows = {
    { type = "header", label = "Quest Gold" },
    { type = "check", label = "Hide quests you've done", get = function() return ns.db.qgHideDone end,
      set = function(v) ns.db.qgHideDone = v; ns.RefreshQuestGold() end },
    { type = "check", label = "Look up quest gold when you enter a zone", tip = "The first time each character enters a zone, King Maker asks the server for the real gold of that zone's quests (the amounts marked ~). Quietly, never in combat.",
      get = function() return ns.db.autoAsk end, set = function(v) ns.db.autoAsk = v; if v then ns.AutoAsk() end end },
    { type = "header", label = "Data" },
    { type = "text", label = "Quests, levels and rewards: CMaNGOS classic-db (GPL-3.0). Zones and Forever's own quests: data from ForeverDB.net (GPL-3.0). Forever's real quest gold: learned in game by King Maker players." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/qk   the Quest Gold page (or /km questgold)" },
} })
