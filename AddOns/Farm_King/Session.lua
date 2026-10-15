local _, ns = ...

-- The mini tracker: a small movable box tallying what you're farming right now.
--   * Each mob you've killed, how many, and what its kills brought in.
--   * Each drop, how many, and what they're worth (Scanner King's price, or the
--     vendor, as everywhere in Farm King), plus the coin you looted.
--   * The timer is optional: while it runs, the box also shows gold per hour
--     for what you farmed with the timer on. Without it you just see totals.
--   * Collapse it to the title bar with -/+, close it with x; Reset clears it.
-- Open it with the Mini tracker button in the Farm King window, or /fk mini.

local MOB_ROWS, DROP_ROWS = 6, 8
local ROW_H = 14
local WIDTH = 268

local frame, title, collapseBtn, body, mobHead, dropHead, mobRows, dropRows, coinText, totalText, gphText, timerBtn, resetBtn

local function S()
    local s = ns.db.session
    s.mobs = s.mobs or {}   -- npcID -> { k = kills, c = coin, i = { [itemID] = units } }
    s.items = s.items or {} -- itemID -> units
    s.coin = s.coin or 0
    s.timed = s.timed or { c = 0, i = {} } -- what was looted with the timer on
    s.timer = s.timer or { elapsed = 0 }
    return s
end

local function elapsed()
    local t = S().timer
    return (t.elapsed or 0) + (t.running and (GetTime() - t.startedAt) or 0)
end

local function itemsValue(items)
    local total = 0
    for id, qty in pairs(items) do total = total + (ns.ItemValue(id) or 0) * qty end
    return total
end

local function fmtTime(sec)
    sec = math.floor(sec)
    return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

local function sessionMob(id)
    local s = S()
    local m = s.mobs[id]
    if not m then m = { k = 0, c = 0, i = {} }; s.mobs[id] = m end
    return m
end

local scheduled = false
local function update()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.1, function() scheduled = false; ns.UpdateMini() end)
end

-- Called by Tracker.lua for every kill it counts, and every coin and item looted from one.
function ns.SessionKill(id)
    if not ns.db then return end
    local m = sessionMob(id)
    m.k = m.k + 1
    update()
end

function ns.SessionLoot(id, coin, item, qty)
    if not ns.db then return end
    local s, m = S(), sessionMob(id)
    if coin and coin > 0 then
        m.c, s.coin = m.c + coin, s.coin + coin
        if s.timer.running then s.timed.c = s.timed.c + coin end
    end
    if item and qty then
        m.i[item] = (m.i[item] or 0) + qty
        s.items[item] = (s.items[item] or 0) + qty
        if s.timer.running then s.timed.i[item] = (s.timed.i[item] or 0) + qty end
    end
    update()
end

function ns.SessionReset()
    local s = S()
    wipe(s.mobs); wipe(s.items); wipe(s.timed.i)
    s.coin, s.timed.c = 0, 0
    s.timer.running, s.timer.elapsed, s.timer.startedAt, s.timer.last = false, 0, nil, 0
    ns.UpdateMini()
end

function ns.SessionToggleTimer()
    local t = S().timer
    if t.running then
        t.elapsed = elapsed()
        t.running, t.startedAt = false, nil
    else
        t.running, t.startedAt = true, GetTime()
    end
    t.last = t.elapsed
    ns.UpdateMini()
end

-- Total value so far, and gold per hour (nil while the timer has never run).
function ns.SessionTotals()
    local s = S()
    local total = s.coin + itemsValue(s.items)
    local secs = elapsed()
    local gph = secs >= 1 and (s.timed.c + itemsValue(s.timed.i)) / secs * 3600 or nil
    return total, gph, secs
end

function ns.SetMini(on)
    ns.db.ui.mini = on and true or false
    ns.UpdateMini()
    if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------

local function smallButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function rowPair(parent)
    local left = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    left:SetJustifyH("LEFT")
    left:SetWidth(WIDTH - 90)
    if left.SetWordWrap then left:SetWordWrap(false) end
    local right = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetJustifyH("RIGHT")
    return { left = left, right = right }
end

local function place(r, y)
    r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", 8, y)
    r.right:ClearAllPoints(); r.right:SetPoint("TOPRIGHT", -8, y)
    r.left:Show(); r.right:Show()
end

local function hide(r) r.left:Hide(); r.right:Hide() end

local function create()
    StaticPopupDialogs.FARMKING_CONFIRM = StaticPopupDialogs.FARMKING_CONFIRM or {
        text = "%s", button1 = YES, button2 = NO,
        OnAccept = function(_, fn) if fn then fn() end end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }

    frame = CreateFrame("Frame", "FarmKingMini", UIParent, "BackdropTemplate")
    ns.miniFrame = frame
    frame:SetSize(WIDTH, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.ui.miniPos = { point, rel, x, y }
    end)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.75)
        frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    local pos = ns.db.ui.miniPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, -120)
    end

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -7)
    title:SetText("Farm King")

    local closeBtn = smallButton(frame, "x", 20, function() ns.SetMini(false) end)
    closeBtn:SetPoint("TOPRIGHT", -5, -4)
    collapseBtn = smallButton(frame, "-", 20, function()
        ns.db.ui.miniCollapsed = not ns.db.ui.miniCollapsed
        ns.UpdateMini()
    end)
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -26)
    body:SetPoint("TOPRIGHT", 0, -26)
    body:SetHeight(1)

    mobHead = rowPair(body)
    mobHead.left:SetFontObject("GameFontNormalSmall")
    mobHead.right:SetFontObject("GameFontNormalSmall")
    mobRows = {}
    for i = 1, MOB_ROWS do mobRows[i] = rowPair(body) end
    dropHead = rowPair(body)
    dropHead.left:SetFontObject("GameFontNormalSmall")
    dropHead.right:SetFontObject("GameFontNormalSmall")
    dropRows = {}
    for i = 1, DROP_ROWS do dropRows[i] = rowPair(body) end
    coinText = rowPair(body)
    totalText = rowPair(body)
    totalText.left:SetFontObject("GameFontNormalSmall")
    totalText.right:SetFontObject("GameFontNormalSmall")
    gphText = rowPair(body)
    gphText.left:SetFontObject("GameFontNormalSmall")
    gphText.right:SetFontObject("GameFontNormalSmall")

    timerBtn = smallButton(body, "Start timer", 90, ns.SessionToggleTimer)
    resetBtn = smallButton(body, "Reset", 60, function()
        StaticPopup_Show("FARMKING_CONFIRM", "Reset the mini tracker?", nil, ns.SessionReset)
    end)
end

-- Fills rows from list ({ left, right }), with a "+N more" last row when it doesn't fit.
local function fill(rowsList, list, y, emptyText)
    for i, r in ipairs(rowsList) do
        local e = list[i]
        if #list > #rowsList and i == #rowsList then
            local rest = 0
            for j = i, #list do rest = rest + list[j].value end
            r.left:SetText("|cffa0a0a0+" .. (#list - i + 1) .. " more|r")
            r.right:SetText(ns.Money(rest))
            place(r, y); y = y - ROW_H
        elseif e then
            r.left:SetText(e.left)
            r.right:SetText(e.right)
            place(r, y); y = y - ROW_H
        elseif i == 1 and emptyText then
            r.left:SetText("|cff808080" .. emptyText .. "|r")
            r.right:SetText("")
            place(r, y); y = y - ROW_H
        else
            hide(r)
        end
    end
    return y
end

local function byValue(a, b)
    if a.value ~= b.value then return a.value > b.value end
    if a.n ~= b.n then return a.n > b.n end
    return a.left < b.left
end

function ns.UpdateMini()
    if not ns.db then return end
    if not ns.db.ui.mini then
        if frame then frame:Hide() end
        return
    end
    if not frame then create() end
    frame:Show()

    local collapsed = ns.db.ui.miniCollapsed
    collapseBtn:SetText(collapsed and "+" or "-")
    body:SetShown(not collapsed)
    local s = S()
    local total, gph, secs = ns.SessionTotals()
    if collapsed then
        -- The title bar still says how it's going.
        title:SetText("Farm King  |cffffffff" .. ns.Money(gph or total) .. (gph and "/hr" or "") .. "|r")
        frame:SetHeight(26)
        return
    end
    title:SetText("Farm King")

    -- Mobs: kills and what they brought in
    local mobs, kills = {}, 0
    for id, m in pairs(s.mobs) do
        local value = m.c + itemsValue(m.i)
        kills = kills + m.k
        table.insert(mobs, { n = m.k, value = value, left = ns.MobInfo(id).name .. " x" .. m.k, right = ns.Money(value) })
    end
    table.sort(mobs, byValue)
    local y = 0
    mobHead.left:SetText("Kills: " .. kills)
    mobHead.right:SetText("")
    place(mobHead, y); y = y - ROW_H
    y = fill(mobRows, mobs, y, "Nothing killed yet")

    -- Drops: how many and what they're worth
    local drops = {}
    for id, qty in pairs(s.items) do
        local unit = ns.ItemValue(id)
        local value = (unit or 0) * qty
        table.insert(drops, { n = qty, value = value, left = ns.ItemText(id) .. " x" .. qty,
            right = unit and ns.Money(value) or "|cff808080no price|r" })
    end
    table.sort(drops, byValue)
    y = y - 4
    dropHead.left:SetText("Drops")
    dropHead.right:SetText("")
    place(dropHead, y); y = y - ROW_H
    y = fill(dropRows, drops, y, "No drops yet")
    coinText.left:SetText("Coin")
    coinText.right:SetText(ns.Money(s.coin))
    place(coinText, y); y = y - ROW_H

    y = y - 4
    totalText.left:SetText("Total")
    totalText.right:SetText(ns.Money(total))
    place(totalText, y); y = y - ROW_H

    local t = s.timer
    if t.running or secs > 0 then
        gphText.left:SetText(fmtTime(secs) .. (t.running and "" or " (paused)"))
        gphText.right:SetText(ns.Money(gph or 0) .. "/hr")
        place(gphText, y); y = y - ROW_H
    else
        hide(gphText)
    end
    timerBtn:SetText(t.running and "Pause timer" or (secs > 0 and "Resume timer" or "Start timer"))

    y = y - 4
    timerBtn:ClearAllPoints()
    timerBtn:SetPoint("TOPLEFT", 6, y)
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("LEFT", timerBtn, "RIGHT", 4, 0)
    frame:SetHeight(26 - y + 24)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- Keep the timer and gold per hour ticking while it runs, even with the box closed,
-- and note how long it has run so a /reload or logout doesn't lose that time.
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 or not ns.db then return end
    acc = 0
    local t = S().timer
    if not t.running then return end
    t.last = elapsed()
    if frame and frame:IsShown() then ns.UpdateMini() end
end)
f:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        -- A timer left running is paused on login, at the time it last showed.
        local t = S().timer
        if t.running then t.elapsed, t.running, t.startedAt = t.last or t.elapsed or 0, false, nil end
        ns.UpdateMini()
    elseif frame and frame:IsShown() then
        update() -- a drop's name or price just loaded
    end
end)
