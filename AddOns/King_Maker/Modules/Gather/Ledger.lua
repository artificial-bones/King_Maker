local _, KM = ...
local ns = KM.Module("Gather")
local UI = KM.UI
local C = UI.C

-- Farming ledger: a small floating box (UI.HUD "GatherKingLedger") listing everything you've gathered
-- (mining, herbs, fishing) with its auction value.
--   * Collapse it to just the title bar with the -/+ button (the title then
--     shows your total, or gold per hour while the timer has run).
--   * Close it with x (/gt ledger, the crown's "Farming ledger" or the Gathering page brings it back).
--   * Reset clears it.
--   * The timer is optional: while it runs, the box also shows gold per hour
--     for what you gathered with the timer on. Without it you just see totals.
-- A second tab, Mat Prices, lists raw farmable materials (mining, herbs, skins,
-- cloth, enchanting) by their latest auction price, to help decide what's worth farming.
-- Its position is kept in ui.ledgerPos ({ point, relativePoint, x, y }, the 1.x shape).

local MAX_ROWS = 10
local PRICE_ROWS = 16
local ROW_H = 14
local WIDTH = 268
local TITLE = "Farming ledger"

local frame, body, rows, totalText, gphText, timerBtn, resetBtn, tabs
local priceBody, priceRows, priceFooter, subTabs
local priceOffset = 0

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

-- Total value of what's in the ledger, and gold per hour (nil while the timer has never run).
function ns.LedgerTotals()
    local led, secs = L(), elapsed()
    return valueOf(led.items), secs >= 1 and valueOf(led.timed) / secs * 3600 or nil, secs
end

---------------------------------------------------------------------------
-- Materials for the Mat Prices tab
---------------------------------------------------------------------------

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

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------

local function rowPair(parent, y)
    local left = UI.Text(parent, 11, C.text)
    left:SetPoint("TOPLEFT", 2, y)
    left:SetWidth(WIDTH - 100)
    local right = UI.Text(parent, 11, C.text, "RIGHT")
    right:SetPoint("TOPRIGHT", -2, y)
    return { left = left, right = right }
end

local function create()
    frame = UI.HUD("GatherKingLedger", TITLE, WIDTH, {
        getPos = function()
            local p = ns.db.ui.ledgerPos
            if type(p) == "table" and p[1] then return { point = p[1], x = p[3], y = p[4] } end
        end,
        setPos = function(p) ns.db.ui.ledgerPos = { p.point, p.point, p.x, p.y } end,
        onClose = function()
            ns.db.ui.ledger = false
            ns.UpdateLedger()
            if ns.RefreshSettings then ns.RefreshSettings() end
            KM.Print(ns, "Ledger hidden. /gt ledger shows it again.")
        end,
        onCollapse = function(collapsed) ns.db.ui.ledgerCollapsed = collapsed; ns.UpdateLedger() end,
    })
    if not ns.db.ui.ledgerPos then
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
    end
    frame:Hide()
    ns.ledgerFrame = frame
    local b = frame.body

    -- Top tabs: Farming | Mat Prices
    tabs = UI.Tabs(b, { { id = "farm", label = "Farming", w = 126 }, { id = "prices", label = "Mat Prices", w = 126 } }, function(id)
        ns.db.ui.ledgerTab = id
        ns.UpdateLedger()
    end, 20)
    tabs:SetPoint("TOPLEFT", 0, 0)

    -- Farming tab
    body = CreateFrame("Frame", nil, b)
    body:SetPoint("TOPLEFT", 0, -28)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    rows = {}
    for i = 1, MAX_ROWS do rows[i] = rowPair(body, -(i - 1) * ROW_H) end
    totalText = UI.Text(body, 11, C.accent)
    gphText = UI.Text(body, 11, C.accent)
    timerBtn = UI.Button(body, "Start timer", 100, 20, function() ns.LedgerToggleTimer() end, "primary")
    resetBtn = UI.Button(body, "Reset", 64, 20, function()
        StaticPopup_Show("GATHERKING_CONFIRM", "Reset the farming ledger?", nil, ns.LedgerReset)
    end)
    frame.resetBtn = resetBtn

    -- Mat Prices tab: one sub-tab per profession (ns.MAT_TABS), scroll with the mouse wheel
    priceBody = CreateFrame("Frame", nil, b)
    priceBody:SetPoint("TOPLEFT", 0, -28)
    priceBody:SetPoint("BOTTOMRIGHT", 0, 0)
    local items = {}
    for _, t in ipairs(ns.MAT_TABS) do items[#items + 1] = { id = t.key, label = t.label, w = 51 } end
    subTabs = UI.Tabs(priceBody, items, function(key)
        ns.db.ui.priceTab = key
        priceOffset = 0
        ns.UpdateLedger()
    end, 18)
    subTabs:SetPoint("TOPLEFT", 0, 0)
    priceRows = {}
    for i = 1, PRICE_ROWS do priceRows[i] = rowPair(priceBody, -24 - (i - 1) * ROW_H) end
    priceFooter = UI.Text(priceBody, 10, C.dim)
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
    local t
    for _, tab in ipairs(ns.MAT_TABS) do if tab.key == ns.db.ui.priceTab then t = tab.key end end
    t = t or "mine"
    subTabs:Select(t)
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
    priceFooter:SetPoint("TOPLEFT", 2, y)
    local note
    if newest then
        note = "Prices from " .. ns.PriceAge(newest)
    else
        note = ScannerKing and "Scan at the auction house to fill this in"
            or "The Scanner module scans prices"
    end
    if #list > PRICE_ROWS then
        note = note .. ". Scroll for more (" .. (priceOffset + 1) .. "-" .. (priceOffset + shown) .. " of " .. #list .. ")"
    end
    priceFooter:SetText(note)
    frame:SetBodyHeight(28 - y + 16)
end

function ns.UpdateLedger()
    if not ns.db then return end
    if not ns.db.ui.ledger then
        if frame then frame:Hide() end
        return
    end
    if not frame then create() end
    frame:Show()

    local collapsed = ns.db.ui.ledgerCollapsed and true or false
    if frame.collapsed ~= collapsed then frame:SetCollapsed(collapsed) end
    local onPrices = ns.db.ui.ledgerTab == "prices"
    tabs:Select(onPrices and "prices" or "farm")
    body:SetShown(not onPrices)
    priceBody:SetShown(onPrices)
    if collapsed then
        -- The title bar still says how it's going.
        local led, secs = L(), elapsed()
        local text = secs >= 1 and (ns.FormatMoney(valueOf(led.timed) / secs * 3600) .. "/hr")
            or ns.FormatMoney(valueOf(led.items))
        frame.title:SetText(TITLE .. "  |cffffffff" .. text .. "|r")
        return
    end
    frame.title:SetText(TITLE)
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
    totalText:SetPoint("TOPLEFT", 2, y)
    totalText:SetText("Total: " .. ns.FormatMoney(valueOf(led.items)))

    local t = led.timer
    local secs = elapsed()
    if t.running or secs > 0 then
        y = y - ROW_H
        gphText:ClearAllPoints()
        gphText:SetPoint("TOPLEFT", 2, y)
        local gph = secs >= 1 and valueOf(led.timed) / secs * 3600 or 0
        gphText:SetText(fmtTime(secs) .. (t.running and "" or " (paused)") .. "   " ..
            ns.FormatMoney(gph) .. "/hr")
        gphText:Show()
    else
        gphText:Hide()
    end
    timerBtn:SetLabel(t.running and "Pause timer" or (secs > 0 and "Resume timer" or "Start timer"))

    y = y - ROW_H - 6
    timerBtn:ClearAllPoints()
    timerBtn:SetPoint("TOPLEFT", 0, y)
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("LEFT", timerBtn, "RIGHT", 6, 0)
    frame:SetBodyHeight(28 - y + 22)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not ns.db then return end
    -- GetTime() restarts with the game, so a timer left running is paused on login.
    local t = ns.db.ledger.timer
    if t.running then
        t.running, t.startedAt = false, nil
    end
    ns.UpdateLedger()
end)
