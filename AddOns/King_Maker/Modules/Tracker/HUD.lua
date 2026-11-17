local _, KM = ...
local ns = KM.Module("Tracker")
local UI = KM.UI
local C = UI.C

-- The Farm Tracker: one floating box (UI.HUD "KingMakerFarmTracker") for the session you're farming now.
--   All         total, gold per hour, the last ten minutes' pace, the Mobs | Gathering split, a sparkline, top items
--   Mobs        kills and each mob's value and value per kill, then the top drops (skins included)
--   Gathering   mining, herbs, fishing, treasure and containers with value per action, then the top materials
--   Prices      Mat Prices: what raw materials sell for (was the farming ledger's second tab)
-- The title bar keeps the clock and gold per hour, also when folded with -. x hides the box; the session keeps
-- recording. Wheel scrolls the lists; Ctrl+wheel zooms the box (70-140%). L opens the Farming Ledger.
-- The lists are as long as what they hold, up to the rows the player allows: drag the dots in the bottom-right corner
-- (taller = more rows, wider = room for names; double-click = back to 280 wide and 8 rows). Saved in
-- TrackerKingDB.ui.hudW / hudRows (nil = the default). Past that height the wheel scrolls them.

local W_DEFAULT, W_MIN = 280, 280
local ROWS_DEFAULT, ROWS_MIN = 8, 3          -- the All tab's item rows; every other list moves with it
local W = W_DEFAULT                          -- the box's width right now (ns.HUDWidth)
local ROW_H = 14
ns.ORANGE = { 0.851, 0.349, 0.149, 1 }   -- Mobs     #D95926   (validated palette: Mobs / Gathering / Mixed)
ns.AQUA = { 0.098, 0.620, 0.439, 1 }     -- Gathering #199E70
ns.BLUE = { 0.224, 0.529, 0.898, 1 }     -- Mixed    #3987E5
ns.ACTIVITY_COLOR = { mobs = ns.ORANGE, gathering = ns.AQUA, mixed = ns.BLUE, none = C.dim }

local frame, content, tabs, priceTabs
local big, gphFS, paceFS, unpricedFS, split, legend, spark, countsFS, footer
local btnPause, btnStop, btnSplit, btnStart, btnLedger, autoCheck
local headHit, splitHit   -- hover areas over the headline numbers and the mobs/gathering bar
local rows, used, y = {}, 0, 0
local itemOffset, priceOffset = 0, 0
local drag0       -- { w, rows } when a grip drag started
local justSaved   -- { s, at }

local function U() return ns.db.ui end

function ns.HUDShown() return ns.db and ns.db.ui.hud and true or false end

---------------------------------------------------------------------------
-- Size: width and rows from the corner grip, kept inside the screen
---------------------------------------------------------------------------

local function boxScale() return (frame and frame:GetScale()) or U().hudScale or 1 end

local function maxWidth()
    local uw = UIParent and UIParent:GetWidth() or 0
    if uw <= 0 then return 800 end
    return math.max(W_MIN, math.floor(uw / boxScale() - 20))
end

-- Rows that still fit on the screen under the All tab's headline, split bar, sparkline and buttons.
local function maxRows()
    local uh = UIParent and UIParent:GetHeight() or 0
    if uh <= 0 then return 40 end
    return math.max(ROWS_MIN, math.floor((uh / boxScale() - 230) / ROW_H))
end

function ns.HUDWidth() return math.max(W_MIN, math.min(maxWidth(), math.floor(tonumber(U().hudW) or W_DEFAULT))) end
function ns.HUDRows() return math.max(ROWS_MIN, math.min(maxRows(), math.floor(tonumber(U().hudRows) or ROWS_DEFAULT))) end

-- Each tab's list keeps its old length at the default and moves row for row with the grip.
local function moreRows() return ns.HUDRows() - ROWS_DEFAULT end
local function priceRows() return math.max(ROWS_MIN, 16 + moreRows()) end
local function gatherRows() return math.max(ROWS_MIN, 6 + moreRows()) end

-- Two lists sharing budget rows: each gets half, and what one doesn't need goes to the other.
local function share(budget, a, b)
    local half = math.floor(budget / 2)
    local x = math.max(1, math.min(a, math.max(half, budget - b)))
    return x, math.max(1, budget - x)
end

-- The last list drawn: how many item rows it shows and its cap (tests and the readout read it).
ns.hudList = { rows = 0, cap = 0, total = 0 }

---------------------------------------------------------------------------
-- Rows: pooled lines with a left, middle and right text; item rows have a tooltip and shift-click links
---------------------------------------------------------------------------

local function rowEnter(self)
    if not (self.item or self.tip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.item and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.item) end
    if type(self.tip) == "function" then self.tip(GameTooltip) elseif self.tip then GameTooltip:AddLine(self.tip, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function row(leftColor)
    used = used + 1
    local r = rows[used]
    if not r then
        r = CreateFrame("Button", nil, content)
        r:SetHeight(ROW_H)
        r.left = UI.Text(r, 11, C.text)
        r.left:SetPoint("LEFT", 2, 0)
        r.right = UI.Text(r, 11, C.text, "RIGHT")
        r.right:SetPoint("RIGHT", -2, 0)
        r.mid = UI.Text(r, 10, C.muted, "RIGHT")
        r.mid:SetPoint("RIGHT", -74, 0)
        r:RegisterForClicks("LeftButtonUp")
        r:SetScript("OnEnter", rowEnter)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            if self.item and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(self.item)
                if link then pcall(ChatEdit_InsertLink, link) end
            end
        end)
        rows[used] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r:SetPoint("TOPRIGHT", 0, y)
    r.left:SetWidth(W - 110)
    local c = leftColor or C.text
    r.left:SetTextColor(c[1], c[2], c[3], 1)
    r.right:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    r.left:SetText(""); r.right:SetText(""); r.mid:SetText("")
    r.item, r.tip = nil, nil
    r:Show()
    y = y - ROW_H
    return r
end

local function heading(text)
    local r = row(C.accent)
    r.left:SetText(text)
    return r
end

local function place(w, h, x)
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", x or 0, y)
    w:Show()
    y = y - (h or w:GetHeight() or 14)
end

---------------------------------------------------------------------------
-- What the rows say
---------------------------------------------------------------------------

local function icon(id)
    local i = KM.Item(id)
    return i.icon and ("|T" .. i.icon .. ":12:12:0:0|t ") or ""
end

-- "From: Skinning 112, drops 20 (Plainstrider 14, Cougar 6)" and where the value came from.
local function itemTip(s, id)
    return function(tt)
        local parts = {}
        for _, kind in ipairs(ns.KIND_ORDER) do
            local e = s.src[kind]
            local q = e and e.i and e.i[id]
            if q then
                local text = (kind == "mob" and "drops" or ns.KIND_LABEL[kind]) .. " " .. q
                if kind == "mob" then
                    local mobs = {}
                    for npc, m in pairs(s.mobs) do if m.i and m.i[id] then mobs[#mobs + 1] = { n = m.i[id], npc = npc } end end
                    table.sort(mobs, function(a, b) return a.n > b.n end)
                    local names = {}
                    for i = 1, math.min(3, #mobs) do names[i] = ns.MobName(mobs[i].npc, s) .. " " .. mobs[i].n end
                    if #names > 0 then text = text .. " (" .. table.concat(names, ", ") .. ")" end
                end
                parts[#parts + 1] = text
            end
        end
        if #parts > 0 then tt:AddLine("From: " .. table.concat(parts, ", "), 0.8, 0.8, 0.8, true) end
        local unit, from = KM.ItemValue(id)
        local it = s.items[id]
        if it and it.np then tt:AddLine("No price yet: scan at the auction house.", 1, 0.72, 0.22)
        elseif from == "ah" then tt:AddLine("Worth: AH price, after the 5% cut (" .. KM.Money(unit) .. " each)", 0.8, 0.8, 0.8)
        elseif from == "vendor" then tt:AddLine("Worth: vendor price (" .. KM.Money(unit) .. " each)", 0.8, 0.8, 0.8)
        elseif from == "quest" then tt:AddLine("A quest item: not counted.", 0.6, 0.6, 0.6) end
    end
end

function ns.MobName(npc, s)
    local m = s and s.mobs and s.mobs[npc]
    if m and m.name then return m.name end
    if npc == 0 then return "Unknown mob" end
    local Farm = KM.mods.Farm
    local info = Farm and Farm.MobInfo and KM.Safe(Farm.MobInfo, npc)
    return (info and info.name) or (FarmKingDB and FarmKingDB.mobs and FarmKingDB.mobs[npc] and FarmKingDB.mobs[npc].name) or ("Mob " .. npc)
end

-- Hidden from the list and counted on the "quest items" line: only quest items worth nothing (one that sells shows).
local function isQuest(id) return KM.IsQuestItem(id) end

-- Items from these kinds (nil = all), by value: { id, q, v }
function ns.ItemList(s, kinds)
    local list = {}
    if kinds then
        local q, v = {}, {}
        for kind in pairs(kinds) do
            local e = s.src[kind]
            for id, n in pairs(e and e.i or {}) do
                local it = s.items[id]
                local share = it and it.q > 0 and (it.v or 0) * n / it.q or 0
                q[id], v[id] = (q[id] or 0) + n, (v[id] or 0) + share
            end
        end
        for id, n in pairs(q) do list[#list + 1] = { id = id, q = n, v = v[id], np = s.items[id] and s.items[id].np } end
    else
        for id, it in pairs(s.items or {}) do list[#list + 1] = { id = id, q = it.q or 0, v = it.v or 0, np = it.np } end
    end
    table.sort(list, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        if a.q ~= b.q then return a.q > b.q end
        return a.id < b.id
    end)
    return list
end

local function itemRows(s, list, max)
    local shown, hiddenQuest = {}, 0
    for _, e in ipairs(list) do
        if isQuest(e.id) then hiddenQuest = hiddenQuest + 1 else shown[#shown + 1] = e end
    end
    itemOffset = math.max(0, math.min(itemOffset, #shown - max))
    ns.hudList = { rows = math.min(max, #shown), cap = max, total = #shown }
    if #shown == 0 then
        local r = row(C.dim)
        r.left:SetText("Nothing looted yet")
    end
    for i = 1, math.min(max, #shown) do
        local e = shown[i + itemOffset]
        local r = row()
        if #shown > max and i == max then
            local rest = 0
            for j = i + itemOffset, #shown do rest = rest + shown[j].v end
            r.left:SetText("|cffa0a0a0+" .. (#shown - i - itemOffset + 1) .. " more|r")
            r.right:SetText(KM.Money(rest))
        elseif e then
            r.left:SetText(icon(e.id) .. KM.ItemText(e.id) .. " x" .. e.q)
            r.right:SetText(e.np and "|cff808080no price|r" or KM.Money(e.v))
            r.item, r.tip = e.id, itemTip(s, e.id)
        end
    end
    -- Sized by hand (or being dragged now): the box keeps that height, blank rows below the items. Never sized:
    -- it follows the items, up to the default.
    if U().hudRows or drag0 then
        local used = math.max(1, math.min(max, #shown))
        for _ = used + 1, max do row() end
        ns.hudList.pad = max - used
    end
    return hiddenQuest
end

local function listed(list)
    local n = 0
    for _, e in ipairs(list) do if not isQuest(e.id) then n = n + 1 end end
    return n
end

local function perHour(n, act) return act >= 60 and math.floor(n / act * 3600 + 0.5) or nil end

local function shares(s)
    local _, _, per = ns.Classify(s)
    local m, g = 0, 0
    for kind, v in pairs(per) do
        if ns.MOB_KINDS[kind] then m = m + v elseif ns.GATHER_KINDS[kind] then g = g + v end
    end
    return m, g
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------

local function swatch(parent, color)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(UI.WHITE)
    t:SetSize(8, 8)
    t:SetVertexColor(color[1], color[2], color[3], 1)
    return t
end

local function stopMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Farm Tracker")
        root:CreateButton("Stop & save", function() ns.Stop("manual", true) end)
        root:CreateButton("Split (save and start the next)", function() ns.Split() end)
        root:CreateButton("Discard", function() ns.Discard() end)
    end)
end

local function create()
    frame = UI.HUD("KingMakerFarmTracker", "Farm Tracker", W, {
        status = true,
        buttons = { { label = "L", tip = "Open the Farming Ledger", onClick = function() TrackerKing.OpenLedger() end } },
        getPos = function() return U().hudPos end,
        setPos = function(p) U().hudPos = p end,
        onClose = function() ns.SetHUD(false) end,
        onCollapse = function(collapsed) U().hudCollapsed = collapsed; ns.UpdateHUD() end,
        onWheel = function(delta)
            if U().hudTab == "prices" then priceOffset = math.max(0, priceOffset - delta * 3)
            else itemOffset = math.max(0, itemOffset - delta) end
            ns.UpdateHUD()
        end,
        zoom = { get = function() return U().hudScale or 1 end, set = function(z) U().hudScale = z end },
        resize = {
            start = function() drag0 = { w = ns.HUDWidth(), rows = ns.HUDRows() } end,
            drag = function(dx, dy)
                drag0 = drag0 or { w = ns.HUDWidth(), rows = ns.HUDRows() }
                local w = math.max(W_MIN, math.min(maxWidth(), math.floor(drag0.w + dx + 0.5)))
                local n = math.max(ROWS_MIN, math.min(maxRows(), drag0.rows + math.floor(dy / ROW_H + 0.5)))
                U().hudW = w ~= W_DEFAULT and w or nil
                U().hudRows = n ~= ROWS_DEFAULT and n or nil
                ns.UpdateHUD()
                return "up to " .. n .. " rows"
            end,
            stop = function() drag0 = nil; ns.UpdateHUD() end,
            reset = function() U().hudW, U().hudRows = nil, nil; ns.UpdateHUD() end,
            tip = function(tt)
                tt:AddLine("Farm Tracker size", C.accent[1], C.accent[2], C.accent[3])
                tt:AddLine("Drag down for a taller box, right for wider names. Once you've sized it, it keeps that size; until then it grows with what you loot.", 1, 1, 1, true)
                tt:AddLine("Double-click: back to " .. W_DEFAULT .. " wide, growing with your loot. Ctrl + wheel zooms the whole box.", 0.6, 0.6, 0.6, true)
            end,
        },
    })
    ns.hudFrame = frame
    frame:Hide()
    local b = frame.body

    local items = { { id = "all", label = "All", w = 66 }, { id = "mobs", label = "Mobs", w = 66 },
        { id = "gathering", label = "Gathering", w = 70 } }
    if KM.mods.Gather and KM.mods.Gather.MAT_TABS then items[#items + 1] = { id = "prices", label = "Prices", w = 64 } end
    tabs = UI.Tabs(b, items, function(id) U().hudTab = id; itemOffset = 0; ns.UpdateHUD() end, 20)
    tabs:SetPoint("TOPLEFT", 0, 0)
    if tabs.buttons.prices then UI.Tip(tabs.buttons.prices, "What gathering mats fetch right now, best first: market price after the 5% cut, or vendor price if that's higher.") end

    content = CreateFrame("Frame", nil, b)
    content:SetPoint("TOPLEFT", 0, -26)
    content:SetPoint("BOTTOMRIGHT", 0, 0)

    big = UI.Text(content, 16, C.text)
    gphFS = UI.Text(content, 12, C.accent, "RIGHT")
    paceFS = UI.Text(content, 10, C.dim)
    unpricedFS = UI.Text(content, 10, C.warn, "RIGHT")
    split = UI.SplitBar(content, W - 16, 6)
    legend = CreateFrame("Frame", nil, content)
    legend:SetSize(W - 16, 12)
    legend.sm = swatch(legend, ns.ORANGE); legend.sm:SetPoint("LEFT", 0, 0)
    legend.tm = UI.Text(legend, 10, C.muted); legend.tm:SetPoint("LEFT", legend.sm, "RIGHT", 4, 0)
    legend.sg = swatch(legend, ns.AQUA); legend.sg:SetPoint("LEFT", legend.tm, "RIGHT", 12, 0)
    legend.tg = UI.Text(legend, 10, C.muted); legend.tg:SetPoint("LEFT", legend.sg, "RIGHT", 4, 0)
    spark = UI.Spark(content, W - 16, 18, 30)
    countsFS = UI.Text(content, 10, C.muted)
    footer = UI.Text(content, 10, C.dim)

    headHit = CreateFrame("Frame", nil, content)
    headHit:SetPoint("TOPLEFT", big, "TOPLEFT", 0, 0)
    headHit:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    headHit:SetPoint("BOTTOM", paceFS, "BOTTOM", 0, 0)
    UI.Tip(headHit, function(tt)
        local s = ns.Live()
        if not s then return end
        local t = ns.Totals(s)
        tt:AddLine("This session", 1, 0.82, 0)
        tt:AddLine("Coin plus loot, each item at the higher of its market price after the 5% cut or its vendor price.", 1, 1, 1, true)
        tt:AddDoubleLine("Coin", KM.Money(t.coin), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Items", KM.Money(t.value - t.coin), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Active time", ns.Clock(t.act), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddLine("/hr: farmed over active time (paused and idle time left out). Recent 10 min: the pace over your last ten active minutes.", 0.8, 0.8, 0.8, true)
        tt:AddLine("Unpriced: no AH or vendor price yet, worth nothing until a scan or the item's info comes in.", 0.6, 0.6, 0.6, true)
    end)
    splitHit = CreateFrame("Frame", nil, content)
    splitHit:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 2)
    splitHit:SetPoint("BOTTOMRIGHT", legend, "BOTTOMRIGHT", 0, 0)
    UI.Tip(splitHit, "Where the value came from. Mobs: drops, skins, pickpocketing and party coin. Gathering: mining, herbs, fishing, chests and boxes.")

    btnPause = UI.Button(content, "Pause", 74, 20, function() TrackerKing.PauseOrResume() end, "primary")
    btnStop = UI.Button(content, "Stop & save", 92, 20, function(_, which)
        if which == "RightButton" then return stopMenu(btnStop) end
        ns.Stop("manual", true)
    end)
    UI.Tip(btnStop, "Saves this session to the Farming Ledger. Right-click: split or discard.")
    btnSplit = UI.Button(content, "Split", 74, 20, function() ns.Split() end)
    UI.Tip(btnSplit, "Saves this session and starts the next one straight away.")
    btnStart = UI.Button(content, "Start", 80, 20, function() ns.Start("manual") end, "primary")
    btnLedger = UI.Button(content, "Open the ledger", 120, 20, function() TrackerKing.OpenLedger() end)
    autoCheck = UI.CheckLabel(content, "Start by itself when I farm", function(v) ns.Settings().autoStart = v end,
        "A session starts by itself after a few kills, nodes or catches within five minutes.")

    local pitems = {}
    for _, t in ipairs((KM.mods.Gather and KM.mods.Gather.MAT_TABS) or {}) do pitems[#pitems + 1] = { id = t.key, label = t.label, w = 53 } end
    priceTabs = UI.Tabs(content, pitems, function(key) U().priceTab = key; priceOffset = 0; ns.UpdateHUD() end, 18)
end

local function hideAll()
    for i = 1, #rows do rows[i]:Hide() end
    used, y = 0, 0
    for _, w in ipairs({ big, gphFS, paceFS, unpricedFS, split, legend, spark, countsFS, footer, btnPause, btnStop,
        btnSplit, btnStart, btnLedger, autoCheck.frame, priceTabs, headHit, splitHit }) do w:Hide() end
end

local function buttons(s)
    y = y - 4
    btnPause:SetLabel(s.state == "paused" and "Resume" or "Pause")
    place(btnPause, 20)
    btnStop:ClearAllPoints(); btnStop:SetPoint("LEFT", btnPause, "RIGHT", 6, 0); btnStop:Show()
    btnSplit:ClearAllPoints(); btnSplit:SetPoint("LEFT", btnStop, "RIGHT", 6, 0); btnSplit:Show()
end

local function counts(s, t, extra)
    local parts = {}
    local kh = perHour(s.kills or 0, t.act)
    if (s.kills or 0) > 0 then parts[#parts + 1] = "Kills " .. s.kills .. (kh and (" (" .. kh .. "/hr)") or "") end
    local skin = s.src.skin
    if skin and (skin.n or 0) > 0 then parts[#parts + 1] = "Skins " .. skin.n end
    if (s.deaths or 0) > 0 then parts[#parts + 1] = "Deaths " .. s.deaths end
    if extra and extra > 0 then parts[#parts + 1] = extra .. " quest item" .. (extra == 1 and "" or "s") end
    if #parts == 0 then return end
    y = y - 2
    countsFS:SetText(table.concat(parts, "   "))
    place(countsFS, 14, 2)
end

local function drawAll(s, t)
    big:SetText(KM.Money(t.value))
    place(big, 20, 2)
    gphFS:ClearAllPoints(); gphFS:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -2); gphFS:Show()
    gphFS:SetText(t.gph and (KM.Money(t.gph) .. " /hr") or "|cff808080- /hr|r")
    local np = 0
    for _, it in pairs(s.items) do if it.np then np = np + 1 end end
    paceFS:SetText(t.pace and ("recent 10 min: " .. KM.Money(t.pace, true) .. "/hr") or "")
    unpricedFS:SetText(np > 0 and (np .. " item" .. (np == 1 and "" or "s") .. " unpriced") or "")
    unpricedFS:ClearAllPoints(); unpricedFS:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y); unpricedFS:Show()
    place(paceFS, 14, 2)
    headHit:Show()
    local m, g = shares(s)
    if m + g > 0 then
        y = y - 2
        split:Set({ { m / (m + g), ns.ORANGE }, { g / (m + g), ns.AQUA } })
        place(split, 8)
        legend.tm:SetText("Mobs " .. math.floor(m / (m + g) * 100 + 0.5) .. "%")
        legend.tg:SetText("Gathering " .. math.floor(g / (m + g) * 100 + 0.5) .. "%")
        place(legend, 14)
        splitHit:Show()
    end
    local tl = ns.Unpack(s.tl)
    if tl and #tl.v > 1 then
        y = y - 2
        spark:Set(tl.v, C.accent)
        place(spark, 22)
    end
    local quest = itemRows(s, ns.ItemList(s), ns.HUDRows())
    if (s.coin or 0) > 0 then
        local r = row()
        r.left:SetText("Coin")
        r.right:SetText(KM.Money(s.coin))
    end
    counts(s, t, quest)
    buttons(s)
end

local function drawMobs(s, t)
    local kh = perHour(s.kills or 0, t.act)
    local r = heading("Kills " .. (s.kills or 0) .. (kh and ("  .  " .. kh .. "/hr") or ""))
    r.right:SetText("|cffa0a0a0per kill|r")
    local list = {}
    for npc, m in pairs(s.mobs) do
        local v = (m.v or 0) + (m.c or 0) + (m.sv or 0)
        list[#list + 1] = { npc = npc, k = m.k or 0, v = v }
    end
    table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.k > b.k end)
    if #list == 0 then local e = row(C.dim); e.left:SetText("Nothing killed yet") end
    local drops = ns.ItemList(s, { mob = true, skin = true, pick = true })
    local mobRows, dropRows = share(12 + moreRows(), #list, listed(drops))
    for i = 1, math.min(mobRows, #list) do
        local e = list[i]
        local rr = row()
        rr.left:SetWidth(W - 160)
        rr.left:SetText(ns.MobName(e.npc, s) .. " x" .. e.k)
        rr.mid:SetText(KM.Money(e.v))
        rr.right:SetText(e.k > 0 and KM.Money(e.v / e.k) or "")
    end
    y = y - 4
    heading("TOP DROPS (incl. skins)")
    local quest = itemRows(s, drops, dropRows)
    counts(s, t, quest)
    buttons(s)
end

local GATHER_ROWS = { { "mine", "Mining", "node" }, { "herb", "Herbalism", "node" }, { "fish", "Fishing", "catch" },
    { "chest", "Treasure", "chest" }, { "box", "Containers", "box" } }

local function drawGathering(s, t)
    local any = false
    for _, g in ipairs(GATHER_ROWS) do
        local e = s.src[g[1]]
        if e and ((e.n or 0) > 0 or (e.v or 0) + (e.c or 0) > 0) then
            any = true
            local v = (e.v or 0) + (e.c or 0)
            local r = row()
            r.left:SetWidth(W - 160)
            local unit = g[3] .. ((e.n or 0) == 1 and "" or (g[3] == "box" and "es" or (g[3] == "catch" and "es" or "s")))
            r.left:SetText(g[2] .. "  |cffa0a0a0" .. (e.n or 0) .. " " .. unit .. "|r")
            r.mid:SetText(KM.Money(v))
            r.right:SetText((e.n or 0) > 0 and ("|cffa0a0a0" .. KM.Money(v / e.n) .. "|r") or "")
        end
    end
    local de = s.src.de
    if de then
        local counted = ns.CountsIn(s, "de")
        local r = row(counted and C.text or C.dim)
        r.left:SetText(counted and "Disenchanted" or "Disenchanted (not counted)")
        r.right:SetText(counted and KM.Money(de.v or 0) or ("|cff808080" .. KM.Money(de.v or 0) .. "|r"))
        r.tip = "Settings > Farm Tracker > Count disenchanting. It turns an item you already had into mats, so counting it can count the same gold twice."
    end
    if not any then local e = row(C.dim); e.left:SetText("Nothing gathered yet") end
    y = y - 4
    heading("TOP MATERIALS")
    local quest = itemRows(s, ns.ItemList(s, ns.GATHER_KINDS), gatherRows())
    local nodes = {}
    for name, n in pairs(s.nodes or {}) do nodes[#nodes + 1] = name .. " " .. n end
    table.sort(nodes)
    if #nodes > 0 then
        local r = row(C.muted)
        r.left:SetWidth(W - 20)
        r.left:SetText(table.concat(nodes, "  .  "))
    end
    counts(s, t, quest)
    buttons(s)
end

local function drawPrices()
    local G = KM.mods.Gather
    if not (G and G.MAT_TABS and G.MaterialList) then return end
    local key
    for _, tab in ipairs(G.MAT_TABS) do if tab.key == U().priceTab then key = tab.key end end
    key = key or "mine"
    priceTabs:Select(key)
    place(priceTabs, 24)
    local list = {}
    for _, id in ipairs(KM.Safe(G.MaterialList, key) or {}) do
        local value = KM.ItemValue(id)
        local market, when
        if ScannerKing and ScannerKing.GetMarketPrice then market, when = ScannerKing.GetMarketPrice(id) end
        if not value and market then value = market * KM.AH_CUT end   -- item info not loaded yet: the AH side of the rule
        list[#list + 1] = { id = id, price = value or 0, name = (G.ItemName and KM.Safe(G.ItemName, id)) or KM.Item(id).name or ("Item " .. id), when = when }
    end
    table.sort(list, function(a, b) if a.price ~= b.price then return a.price > b.price end return a.name < b.name end)
    local PRICE_ROWS = priceRows()
    priceOffset = math.max(0, math.min(priceOffset, #list - PRICE_ROWS))
    ns.hudList = { rows = math.min(PRICE_ROWS, #list), cap = PRICE_ROWS, total = #list }
    local newest
    for _, e in ipairs(list) do if e.when and (not newest or e.when > newest) then newest = e.when end end
    for i = 1, math.min(PRICE_ROWS, #list) do
        local e = list[i + priceOffset]
        local r = row()
        r.left:SetText(e.name)
        r.right:SetText(e.price > 0 and KM.Money(e.price) or "|cff808080no price|r")
        r.item = e.id
    end
    local note
    if newest then
        note = "Prices from " .. ((G.PriceAge and KM.Safe(G.PriceAge, newest)) or KM.Ago(newest)) .. ", after the AH cut"
    else
        note = ScannerKing and "Scan at the auction house to fill this in" or "The Scanner module scans prices"
    end
    if #list > PRICE_ROWS then
        note = note .. ". Scroll for more (" .. (priceOffset + 1) .. "-" .. (priceOffset + math.min(PRICE_ROWS, #list)) .. " of " .. #list .. ")"
    end
    y = y - 2
    footer:SetText(note)
    place(footer, 14, 2)
end

local function drawIdle()
    local r = row(C.muted)
    r.left:SetText("Not farming right now.")
    local list = ns.db.sessions
    if justSaved and GetTime() - justSaved.at < 30 then
        local s = row(C.text)
        s.left:SetWidth(W - 20)
        s.left:SetText("Saved: " .. ns.SessionLine(justSaved.s))
    end
    local last = list[#list]
    if last and not (justSaved and justSaved.s == last and GetTime() - justSaved.at < 30) then
        local l = row(C.dim)
        l.left:SetWidth(W - 20)
        l.left:SetText("Last: " .. ns.SessionLine(last))
    end
    y = y - 6
    place(btnStart, 20)
    btnLedger:ClearAllPoints(); btnLedger:SetPoint("LEFT", btnStart, "RIGHT", 6, 0); btnLedger:Show()
    y = y - 6
    autoCheck:SetChecked(ns.Settings().autoStart)
    place(autoCheck.frame, 18)
end

-- The status, its colour, and a short form for a narrow box (the square's colour already says paused).
local function titleFor(s)
    if not s then return "Farm Tracker", nil, "Farm Tracker" end
    if s.state == "paused" then
        if s.why == "idle" then return "Paused (idle)", C.warn, "Idle" end
        if s.why == "afk" then return "Paused (AFK)", C.warn, "AFK" end
        return "Paused", C.warn, "Paused"
    end
    return "Farming", C.good, "Farming"
end
ns.TitleFor = titleFor

-- Money for the title bar: "12g 34s", "1,234g", "56s 7c", "8c" (KM.Money without the copper once there's gold).
local function compact(c)
    c = math.floor((c or 0) + 0.5)
    if c >= 10000000 then return KM.Commas(math.floor(c / 10000)) .. "|cffffd700g|r" end
    if c >= 10000 then
        local g, sv = math.floor(c / 10000), math.floor(c / 100) % 100
        return g .. "|cffffd700g|r" .. (sv > 0 and (" " .. sv .. "|cffc7c7cfs|r") or "")
    end
    return KM.Money(c)
end

function ns.UpdateHUD()
    if not ns.db then return end
    if not U().hud then
        if frame then frame:Hide() end
        return
    end
    if not frame then create() end
    frame:Show()
    local collapsed = U().hudCollapsed and true or false
    if frame.collapsed ~= collapsed then frame:SetCollapsed(collapsed) end
    W = ns.HUDWidth()
    frame:SetWidth(W)
    local s = ns.Live()
    local title, color, short = titleFor(s)
    frame:SetStatus(color)
    local t = s and ns.Totals(s)
    if s then
        frame:SetTitleParts(title, ns.Clock(t.act), t.gph and (compact(t.gph) .. "/hr") or compact(t.value), short)
    else
        frame:SetTitleParts(title, nil, nil, short)
    end
    if collapsed then return end
    split:SetWidth(W - 16); legend:SetWidth(W - 16); spark:SetWidth(W - 16)
    local tab = U().hudTab or "all"
    if tab == "prices" and not (KM.mods.Gather and KM.mods.Gather.MAT_TABS) then tab = "all" end
    tabs:Select(tab)
    hideAll()
    if tab == "prices" then drawPrices()
    elseif not s then drawIdle()
    elseif tab == "mobs" then drawMobs(s, t)
    elseif tab == "gathering" then drawGathering(s, t)
    else drawAll(s, t) end
    frame:SetBodyHeight(26 - y + 4)
end

-- The 1 s clock: only the title while shown.
function ns.HUDTick()
    if not (frame and frame:IsShown()) then return end
    local s = ns.Live()
    if s and s.state == "running" then ns.UpdateHUD() end
end

-- The one toggle every entry point uses (x, /farm, /fk mini, /gt ledger, the crown, the key, the page buttons).
function ns.SetHUD(on, quiet)
    if not ns.db then return end
    local was = U().hud
    U().hud = on and true or false
    ns.UpdateHUD()
    if was and not on and not quiet and not U().toldClose then
        U().toldClose = true
        KM.Print(ns, "the Farm Tracker keeps recording; /farm shows it again.")
    end
    KM.Refresh()
end

TrackerKing.RegisterCallback("King_Maker_HUD", function(event, rec)
    if event == "SESSION_SAVED" and rec then
        justSaved = { s = ns.Find(rec.id) or rec, at = GetTime() }
    end
end)
