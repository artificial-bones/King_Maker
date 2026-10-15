local _, ns = ...

-- Farming ledger: a small movable box listing everything you've gathered
-- (mining, herbs, fishing) with its auction value.
--   * Collapse it to just the title bar with the -/+ button (the title then
--     shows your total, or gold per hour while the timer has run).
--   * Close it with x (/gt ledger or the settings page brings it back).
--   * Reset clears it.
--   * The timer is optional: while it runs, the box also shows gold per hour
--     for what you gathered with the timer on. Without it you just see totals.
-- A second tab, Mat Prices, lists raw farmable materials (mining, herbs, skins,
-- cloth, enchanting) by their latest auction price, to help decide what's worth farming.

local MAX_ROWS = 10
local ROW_H = 14
local WIDTH = 268

local frame, title, rows, totalText, gphText, body
local collapseBtn, timerBtn

local function L() return ns.db.ledger end

local function elapsed()
    local t = L().timer
    return (t.elapsed or 0) + (t.running and (GetTime() - t.startedAt) or 0)
end

local function valueOf(items)
    local total = 0
    for id, qty in pairs(items) do
        local price = ns.Price(id)
        if price then total = total + price * qty end
    end
    return total
end

local function fmtTime(sec)
    sec = math.floor(sec)
    return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

function ns.LedgerAdd(loot)
    if not ns.db then return end
    local led = L()
    for id, qty in pairs(loot) do
        led.items[id] = (led.items[id] or 0) + qty
        if led.timer.running then led.timed[id] = (led.timed[id] or 0) + qty end
    end
    if ns.UpdateLedger then ns.UpdateLedger() end
end

function ns.LedgerReset()
    local led = L()
    wipe(led.items)
    wipe(led.timed)
    led.timer.running, led.timer.elapsed, led.timer.startedAt = false, 0, nil
    ns.UpdateLedger()
end

function ns.LedgerToggleTimer()
    local t = L().timer
    if t.running then
        t.elapsed = elapsed()
        t.running, t.startedAt = false, nil
    else
        t.running, t.startedAt = true, GetTime()
    end
    ns.UpdateLedger()
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


local PRICE_ROWS = 16
local priceBody, priceRows, priceFooter, tabs, subTabs
local priceOffset = 0

-- Bonus drops that belong to each profession, for the Mat Prices tab.
local BONUS_TYPE = {
    [249391] = "mine", [249425] = "mine", [249426] = "mine",
    [2835] = "mine", [2836] = "mine", [2838] = "mine", [7912] = "mine", [12365] = "mine",
    [249399] = "herb", [249424] = "herb", [249274] = "herb",
    [268415] = "herb", [268416] = "herb", [268417] = "herb", [268418] = "herb",
}

-- Every material for one profession: known ores/herbs, their bonus drops, and
-- anything else your (or your guild's) nodes of that type have dropped, like gems.
local function materials(t)
    local seen, list = {}, {}
    local function add(id) if id and not seen[id] then seen[id] = true; table.insert(list, id) end end
    for _, v in pairs(ns.KNOWN) do if v[1] == t then add(v[3]) end end
    for id, bt in pairs(BONUS_TYPE) do if bt == t then add(id) end end
    for _, e in ipairs(ns.MATS[t] or {}) do add(e[1]) end
    for _, zone in pairs(ns.db.nodes) do
        for _, node in ipairs(zone) do
            if node.t == t then
                if node.stats then for id in pairs(node.stats.items) do add(id) end end
                for _, g in pairs(node.guild or {}) do
                    for id in pairs(g.items or {}) do add(id) end
                end
            end
        end
    end
    return list
end
ns.LedgerMaterials = materials
ns.MaterialList = materials

local function setTab(button, active)
    if active then button:LockHighlight() else button:UnlockHighlight() end
end

local function create()
    frame = CreateFrame("Frame", "GatherKingLedger", UIParent, "BackdropTemplate")
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
        ns.db.ui.ledgerPos = { point, rel, x, y }
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
    local pos = ns.db.ui.ledgerPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
    end

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -7)
    title:SetText("Gather King")

    local closeBtn = smallButton(frame, "x", 20, function()
        ns.db.ui.ledger = false
        ns.UpdateLedger()
        if ns.RefreshSettings then ns.RefreshSettings() end
        ns.Print("Ledger hidden. /gt ledger shows it again.")
    end)
    closeBtn:SetPoint("TOPRIGHT", -5, -4)
    collapseBtn = smallButton(frame, "-", 20, function()
        ns.db.ui.ledgerCollapsed = not ns.db.ui.ledgerCollapsed
        ns.UpdateLedger()
    end)
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)

    -- Top tabs: Farming | Mat Prices
    tabs = {
        farm = smallButton(frame, "Farming", 123, function() ns.db.ui.ledgerTab = "farm"; ns.UpdateLedger() end),
        prices = smallButton(frame, "Mat Prices", 123, function() ns.db.ui.ledgerTab = "prices"; ns.UpdateLedger() end),
    }
    tabs.farm:SetPoint("TOPLEFT", 8, -26)
    tabs.prices:SetPoint("LEFT", tabs.farm, "RIGHT", 6, 0)

    -- Farming tab
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -50)
    body:SetPoint("TOPRIGHT", 0, -50)
    body:SetHeight(1)

    rows = {}
    for i = 1, MAX_ROWS do
        local left = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", 8, -(i - 1) * ROW_H)
        left:SetJustifyH("LEFT")
        local right = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("TOPRIGHT", -8, -(i - 1) * ROW_H)
        right:SetJustifyH("RIGHT")
        rows[i] = { left = left, right = right }
    end
    totalText = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetJustifyH("LEFT")
    gphText = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gphText:SetJustifyH("LEFT")

    timerBtn = smallButton(body, "Start timer", 90, ns.LedgerToggleTimer)
    local resetBtn = smallButton(body, "Reset", 60, function()
        StaticPopup_Show("GATHERKING_CONFIRM", "Reset the farming ledger?", nil, ns.LedgerReset)
    end)
    frame.resetBtn = resetBtn

    -- Mat Prices tab: one sub-tab per profession (ns.MAT_TABS), scroll with the mouse wheel
    priceBody = CreateFrame("Frame", nil, frame)
    priceBody:SetPoint("TOPLEFT", 0, -50)
    priceBody:SetPoint("TOPRIGHT", 0, -50)
    priceBody:SetHeight(1)
    subTabs = {}
    local prev
    for _, tab in ipairs(ns.MAT_TABS) do
        local key = tab.key
        local b = smallButton(priceBody, tab.label, 48, function()
            ns.db.ui.priceTab = key
            priceOffset = 0
            ns.UpdateLedger()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 8, 0) end
        subTabs[key], prev = b, b
    end
    priceRows = {}
    for i = 1, PRICE_ROWS do
        local left = priceBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", 8, -24 - (i - 1) * ROW_H)
        left:SetJustifyH("LEFT")
        local right = priceBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("TOPRIGHT", -8, -24 - (i - 1) * ROW_H)
        right:SetJustifyH("RIGHT")
        priceRows[i] = { left = left, right = right }
    end
    priceFooter = priceBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    priceFooter:SetJustifyH("LEFT")
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        if ns.db.ui.ledgerTab ~= "prices" or ns.db.ui.ledgerCollapsed then return end
        priceOffset = math.max(0, priceOffset - delta * 3)
        ns.UpdateLedger()
    end)

    -- Keep the timer and gold per hour ticking while it runs.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc >= 1 then
            acc = 0
            if L().timer.running and (ns.db.ui.ledgerTab ~= "prices" or ns.db.ui.ledgerCollapsed) then ns.UpdateLedger() end
        end
    end)
end

local function updatePrices()
    local t = subTabs[ns.db.ui.priceTab] and ns.db.ui.priceTab or "mine"
    for key, b in pairs(subTabs) do setTab(b, key == t) end
    local list = {}
    for _, id in ipairs(materials(t)) do
        local price, when = ns.Price(id)
        table.insert(list, { id = id, price = price or 0, name = ns.ItemName(id), when = when })
    end
    table.sort(list, function(a, b)
        if a.price ~= b.price then return a.price > b.price end
        return a.name < b.name
    end)
    priceOffset = math.max(0, math.min(priceOffset, #list - PRICE_ROWS))
    local newest
    for _, e in ipairs(list) do
        if e.when and (not newest or e.when > newest) then newest = e.when end
    end
    for i = 1, PRICE_ROWS do
        local r, e = priceRows[i], list[i + priceOffset]
        if e then
            r.left:SetText(e.name)
            r.right:SetText(e.price > 0 and ns.FormatMoney(e.price) or "|cff808080no price|r")
            r.left:Show(); r.right:Show()
        else
            r.left:Hide(); r.right:Hide()
        end
    end
    local shown = math.min(#list, PRICE_ROWS)
    local y = -24 - shown * ROW_H - 4
    priceFooter:ClearAllPoints()
    priceFooter:SetPoint("TOPLEFT", 8, y)
    local note
    if newest then
        note = "Prices from " .. ns.PriceAge(newest)
    else
        note = ScannerKing and "Scan at the auction house to fill this in"
            or "Install Scanner King to scan prices"
    end
    if #list > PRICE_ROWS then
        note = note .. ". Scroll for more (" .. (priceOffset + 1) .. "-" .. (priceOffset + shown) .. " of " .. #list .. ")"
    end
    priceFooter:SetText(note)
    frame:SetHeight(50 - y + 22)
end

function ns.UpdateLedger()
    if not ns.db then return end
    if not ns.db.ui.ledger then
        if frame then frame:Hide() end
        return
    end
    if not frame then create() end
    frame:Show()

    local collapsed = ns.db.ui.ledgerCollapsed
    local onPrices = ns.db.ui.ledgerTab == "prices"
    collapseBtn:SetText(collapsed and "+" or "-")
    tabs.farm:SetShown(not collapsed)
    tabs.prices:SetShown(not collapsed)
    setTab(tabs.farm, not onPrices)
    setTab(tabs.prices, onPrices)
    body:SetShown(not collapsed and not onPrices)
    priceBody:SetShown(not collapsed and onPrices)
    if collapsed then
        -- The title bar still says how it's going.
        local led, secs = L(), elapsed()
        local text = secs >= 1 and (ns.FormatMoney(valueOf(led.timed) / secs * 3600) .. "/hr")
            or ns.FormatMoney(valueOf(led.items))
        title:SetText("Gather King  |cffffffff" .. text .. "|r")
        frame:SetHeight(26)
        return
    end
    title:SetText("Gather King")
    if onPrices then return updatePrices() end

    local led = L()
    local list = {}
    for id, qty in pairs(led.items) do
        local price = ns.Price(id)
        table.insert(list, { id = id, qty = qty, value = price and price * qty or 0 })
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.qty > b.qty
    end)

    local shown = math.min(#list, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local r, e = rows[i], list[i]
        if e then
            r.left:SetText(ns.ItemName(e.id) .. " x" .. e.qty)
            r.right:SetText(e.value > 0 and ns.FormatMoney(e.value) or "|cff808080no price|r")
            r.left:Show(); r.right:Show()
        else
            r.left:Hide(); r.right:Hide()
        end
    end
    if #list == 0 then
        rows[1].left:SetText("|cff808080Nothing gathered yet|r")
        rows[1].left:Show()
        shown = 1
    end

    local y = -(shown * ROW_H) - 6
    if #list > MAX_ROWS then
        local extra = rows[MAX_ROWS]
        extra.left:SetText("+" .. (#list - MAX_ROWS + 1) .. " more items")
        extra.right:SetText("")
    end
    totalText:ClearAllPoints()
    totalText:SetPoint("TOPLEFT", 8, y)
    totalText:SetText("Total: " .. ns.FormatMoney(valueOf(led.items)))

    local t = led.timer
    local secs = elapsed()
    if t.running or secs > 0 then
        y = y - ROW_H
        gphText:ClearAllPoints()
        gphText:SetPoint("TOPLEFT", 8, y)
        local gph = secs >= 1 and valueOf(led.timed) / secs * 3600 or 0
        gphText:SetText(fmtTime(secs) .. (t.running and "" or " (paused)") .. "   " ..
            ns.FormatMoney(gph) .. "/hr")
        gphText:Show()
    else
        gphText:Hide()
    end
    timerBtn:SetText(t.running and "Pause timer" or (secs > 0 and "Resume timer" or "Start timer"))

    y = y - ROW_H - 4
    timerBtn:ClearAllPoints()
    timerBtn:SetPoint("TOPLEFT", 6, y)
    frame.resetBtn:ClearAllPoints()
    frame.resetBtn:SetPoint("LEFT", timerBtn, "RIGHT", 4, 0)
    frame:SetHeight(50 - y + 24)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- GetTime() restarts with the game, so a timer left running is paused on login.
    local t = ns.db.ledger.timer
    if t.running then
        t.running, t.startedAt = false, nil
    end
    ns.UpdateLedger()
end)
