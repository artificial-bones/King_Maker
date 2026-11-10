local _, KM = ...
local ns = KM.Module("Shopping")

-- Searching and buying at the auction house.
--
-- Searching is not protected, so "Search all" may run a list's searches one after another. Buying is: every
-- purchase step here runs only from the player's own click (a Buy or Confirm button's OnClick), never from a timer,
-- an event or a loop, and nothing is bought above the entry's max price unless the player ticked the override.
--
--   commodities  Buy -> StartCommoditiesPurchase(id, qty) -> COMMODITY_PRICE_UPDATED(unit, total)
--                -> "Confirm: N for X (each Y)" -> Confirm -> ConfirmCommoditiesPurchase(id, qty)
--                -> COMMODITY_PURCHASE_SUCCEEDED | COMMODITY_PURCHASE_FAILED (| COMMODITY_PRICE_UNAVAILABLE)
--   other items  search -> the cheapest auctions -> Buy on a row -> PlaceBid(auctionID, buyout)
--                -> AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)
-- We only call C_AuctionHouse functions; we never hook or replace them (docs/gotchas.md 3).

local AH = function() return C_AuctionHouse end

-- The item the panel is working on.
ns.cur = { phase = "idle", rows = {} }
local searching            -- { id, token, select, onDone }
local token = 0
local pendingBids = {}     -- auctionID -> { id, list, qty }
local run                  -- Search all: { ids, i, waits }
local ahShown = false

function ns.AHOpen()
    local ah = AH()
    return ahShown and ah and ah.SendSearchQuery and AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false
end

local function ready()
    local ah = AH()
    if not (ah and ah.IsThrottledMessageSystemReady) then return true end
    local ok, r = pcall(ah.IsThrottledMessageSystemReady)
    return not ok or r and true or false
end
ns.ThrottleReady = ready

local THROTTLED = "The auction house is busy (throttled). Wait a moment and click again."

function ns.Say(text, color)
    ns.cur.msg, ns.cur.msgColor = text, color
    if ns.RefreshPanel then ns.RefreshPanel() end
end

local function sound()
    if not (ns.db and ns.db.settings.sound) then return end
    if PlaySound and SOUNDKIT then
        local s = SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        if s then pcall(PlaySound, s) end
    end
end

local function sorts()
    local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { { sortOrder = price, reverseSort = false } }
end

-- The entry the current item came from (for its max price and wanted quantity).
function ns.CurEntry()
    local c = ns.cur
    if not c.id then return nil end
    return ns.Find(c.list or ns.Active(), c.id)
end

-- The max that guards a purchase of the current item (nil = no limit).
function ns.CurMax()
    local e = ns.CurEntry()
    if e then return (ns.EffectiveMax(e)) end
    return nil
end

local function overMax(unit)
    local max = ns.CurMax()
    return unit and max and unit > max and not ns.cur.override
end
ns.OverMax = overMax

---------------------------------------------------------------------------
-- Selecting an item
---------------------------------------------------------------------------

function ns.Select(id, list)
    local c = ns.cur
    if c.phase == "pending" or c.phase == "confirm" then ns.CancelBuy(true) end
    c.override = false
    if c.id ~= id then
        c.rows, c.kind = {}, nil
        local live = ns.live[id]
        if live then c.kind = live.kind end
    end
    c.id, c.list, c.phase = id, list or ns.Active(), "idle"
    local e = ns.CurEntry()
    c.qty = (e and e.qty and e.qty > 0) and e.qty or 1
    c.msg = nil
    if ns.RefreshPanel then ns.RefreshPanel() end
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

local function finish(id)
    local s = searching
    if not s or s.id ~= id then return end
    searching = nil
    if s.onDone then KM.Safe(s.onDone, id) end
end

-- Sends one item search. opts.select: the panel shows its auctions; opts.onDone(id) runs when it's answered (or
-- not, after 5 s); opts.quiet: no chat-line messages. Returns true if it was sent.
function ns.Search(id, opts)
    opts = opts or {}
    local ah = AH()
    if run and not opts.onDone then
        if not opts.quiet then ns.Say("Search all is running; click it again to stop it first.", KM.UI.C.warn) end
        return false
    end
    if not ns.AHOpen() then
        if not opts.quiet then ns.Say("Open the auction house to search.", KM.UI.C.warn) end
        return false
    end
    if not (ah.MakeItemKey and ah.SendSearchQuery) then return false end
    if not ready() then
        if not opts.quiet then ns.Say(THROTTLED, KM.UI.C.warn) end
        return false
    end
    token = token + 1
    local my = token
    local okKey, key = pcall(ah.MakeItemKey, id)
    if not okKey or not key then return false end
    searching = { id = id, token = my, select = opts.select, quiet = opts.quiet, onDone = opts.onDone }
    if opts.select and not opts.quiet then ns.Say("Searching for " .. ns.Name(id) .. "...", KM.UI.C.muted) end
    local ok = pcall(ah.SendSearchQuery, key, sorts(), false)
    if not ok then
        searching = nil
        if not opts.quiet then ns.Say("The search failed. Try again in a moment.", KM.UI.C.bad) end
        return false
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            if searching and searching.token == my then
                if searching.select and not searching.quiet then ns.Say("No answer from the auction house for " .. ns.Name(id) .. ".", KM.UI.C.warn) end
                finish(id)
            end
        end)
    end
    return true
end

local function store(id, kind, rows, listed)
    ns.live[id] = { p = rows[1] and rows[1].unit or nil, q = listed, t = KM.Now(), kind = kind }
    local c = ns.cur
    if c.id == id then
        c.kind, c.rows = kind, rows
        if searching and searching.select and not searching.quiet then
            if #rows == 0 then ns.Say("None listed right now.", KM.UI.C.muted)
            elseif overMax(rows[1].unit) then ns.Say("The cheapest is above your max (" .. KM.Money(ns.CurMax()) .. ").", KM.UI.C.warn)
            else ns.Say(nil) end
        end
    end
end

local function commodityResults(id)
    local ah = AH()
    local n = ah.GetNumCommoditySearchResults and select(2, pcall(ah.GetNumCommoditySearchResults, id)) or 0
    n = tonumber(n) or 0
    local rows, listed = {}, 0
    for i = 1, math.min(n, 50) do
        local ok, info = pcall(ah.GetCommoditySearchResultInfo, id, i)
        if ok and type(info) == "table" and info.unitPrice then
            listed = listed + (info.quantity or 0)
            if #rows < 6 then rows[#rows + 1] = { unit = info.unitPrice, qty = info.quantity or 0, auctionID = info.auctionID } end
        end
    end
    store(id, "commodity", rows, listed)
end

local function itemResults(key)
    local ah = AH()
    local id = key.itemID
    local n = ah.GetNumItemSearchResults and select(2, pcall(ah.GetNumItemSearchResults, key)) or 0
    n = tonumber(n) or 0
    local rows, listed = {}, 0
    for i = 1, math.min(n, 50) do
        local ok, info = pcall(ah.GetItemSearchResultInfo, key, i)
        if ok and type(info) == "table" and info.buyoutAmount and info.buyoutAmount > 0 then
            local q = math.max(1, info.quantity or 1)
            listed = listed + q
            rows[#rows + 1] = { unit = math.floor(info.buyoutAmount / q), buyout = info.buyoutAmount, qty = q,
                auctionID = info.auctionID, link = info.itemLink }
        end
    end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    for i = #rows, 9, -1 do rows[i] = nil end
    store(id, "item", rows, listed)
end

---------------------------------------------------------------------------
-- Search all: the active list's searches, one after another (buying stays one click each)
---------------------------------------------------------------------------

function ns.SearchAllRunning() return run ~= nil end

function ns.StopSearchAll(why)
    if not run then return end
    run = nil
    if why then ns.Say(why, KM.UI.C.muted) end
end

function ns.SearchAll()
    if run then return ns.StopSearchAll("Search all stopped.") end
    if not ns.AHOpen() then return ns.Say("Open the auction house to search.", KM.UI.C.warn) end
    if ScannerKing and ScannerKing.IsScanning and KM.Safe(ScannerKing.IsScanning) then
        return ns.Say("A scan is running; Search all waits for it to finish.", KM.UI.C.warn)
    end
    local ids = {}
    for _, e in ipairs(ns.Entries(ns.Active()) or {}) do ids[#ids + 1] = e.id end
    if #ids == 0 then return ns.Say("This list is empty.", KM.UI.C.muted) end
    token = token + 1
    run = { ids = ids, i = 0, waits = 0 }
    local me = run
    local step
    step = function()
        if run ~= me then return end
        if not ns.AHOpen() then return ns.StopSearchAll() end
        if not ready() then
            me.waits = me.waits + 1
            if me.waits > 100 then return ns.StopSearchAll("The auction house stayed busy; Search all stopped.") end
            return C_Timer.After(0.2, step)
        end
        me.waits = 0
        me.i = me.i + 1
        local id = me.ids[me.i]
        if not id then
            run = nil
            local under = 0
            for _, x in ipairs(me.ids) do
                local e = ns.Find(ns.Active(), x)
                if e and ns.Status(e) == "under" then under = under + 1 end
            end
            ns.Say("Searched " .. #me.ids .. " items: " .. under .. " under your max.", under > 0 and KM.UI.C.good or KM.UI.C.muted)
            if KM.IsShown("shopping") then KM.Refresh("shopping") end
            return
        end
        ns.Say("Searching " .. me.i .. " of " .. #me.ids .. ": " .. ns.Name(id) .. "...", KM.UI.C.muted)
        local sent = ns.Search(id, { quiet = true, onDone = function() C_Timer.After(0.3, step) end })
        if not sent then C_Timer.After(0.5, step) end
    end
    step()
end

---------------------------------------------------------------------------
-- Buying a commodity: two clicks
---------------------------------------------------------------------------

-- Click 1 (the Buy button's OnClick). Returns true if the auction house was asked for the price.
function ns.StartBuy(qty)
    local c, ah = ns.cur, AH()
    if not c.id then return false end
    if c.phase == "pending" or c.phase == "confirm" or c.phase == "buying" then return false end
    if not ns.AHOpen() then ns.Say("Open the auction house to buy.", KM.UI.C.warn) return false end
    if not (ah.StartCommoditiesPurchase and ah.ConfirmCommoditiesPurchase) then
        ns.Say("This client can't buy commodities from an addon; use the auction house window.", KM.UI.C.bad) return false
    end
    qty = math.floor(tonumber(qty or c.qty) or 0)
    if qty < 1 then ns.Say("Set how many to buy.", KM.UI.C.warn) return false end
    local cheapest = c.rows[1] and c.rows[1].unit
    if overMax(cheapest) then
        ns.Say("The cheapest is " .. KM.Money(cheapest) .. " each, above your max " .. KM.Money(ns.CurMax()) .. ".", KM.UI.C.warn)
        return false
    end
    if not ready() then ns.Say(THROTTLED, KM.UI.C.warn) return false end
    local ok, err = pcall(ah.StartCommoditiesPurchase, c.id, qty)
    if not ok then ns.Say("The auction house refused: " .. tostring(err), KM.UI.C.bad) return false end
    c.qty, c.phase, c.unit, c.total = qty, "pending", nil, nil
    c.buyID, c.buyQty = c.id, qty
    ns.Say("Asking the auction house for the price of " .. qty .. "...", KM.UI.C.muted)
    return true
end

-- Click 2 (the Confirm button's OnClick). Returns true if the purchase was sent.
function ns.ConfirmBuy()
    local c, ah = ns.cur, AH()
    if c.phase ~= "confirm" or c.buyID ~= c.id or not c.unit then return false end
    if overMax(c.unit) then
        c.phase = "blocked"
        ns.Say("Above your max: tick \"Buy above my max\" to allow it.", KM.UI.C.warn)
        return false
    end
    if not ns.AHOpen() then ns.Say("Open the auction house to buy.", KM.UI.C.warn) return false end
    if not ready() then ns.Say(THROTTLED, KM.UI.C.warn) return false end
    local ok, err = pcall(ah.ConfirmCommoditiesPurchase, c.buyID, c.buyQty)
    if not ok then c.phase = "idle"; ns.Say("The purchase failed: " .. tostring(err), KM.UI.C.bad) return false end
    c.phase = "buying"
    ns.Say("Buying " .. c.buyQty .. " for " .. KM.Money(c.total) .. "...", KM.UI.C.muted)
    return true
end

function ns.CancelBuy(silent)
    local c, ah = ns.cur, AH()
    if c.phase == "pending" or c.phase == "confirm" or c.phase == "blocked" then
        if ah and ah.CancelCommoditiesPurchase then pcall(ah.CancelCommoditiesPurchase) end
    end
    c.phase, c.unit, c.total = "idle", nil, nil
    if not silent then ns.Say("Cancelled.", KM.UI.C.muted) end
end

---------------------------------------------------------------------------
-- Buying one auction of a non-commodity item: one click per auction
---------------------------------------------------------------------------

local function purchaseEventKnown()
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("AUCTION_HOUSE_PURCHASE_COMPLETED")
end

-- The Buy button's OnClick on one auction row.
function ns.BuyItem(row)
    local c, ah = ns.cur, AH()
    if not (c.id and row and row.auctionID and row.buyout) then return false end
    if not ns.AHOpen() then ns.Say("Open the auction house to buy.", KM.UI.C.warn) return false end
    if not ah.PlaceBid then ns.Say("This client can't buy from an addon; use the auction house window.", KM.UI.C.bad) return false end
    if overMax(row.unit) then
        ns.Say(KM.Money(row.unit) .. " each is above your max " .. KM.Money(ns.CurMax()) .. ".", KM.UI.C.warn)
        return false
    end
    if not ready() then ns.Say(THROTTLED, KM.UI.C.warn) return false end
    local ok, err = pcall(ah.PlaceBid, row.auctionID, row.buyout)
    if not ok then ns.Say("The purchase failed: " .. tostring(err), KM.UI.C.bad) return false end
    for i, r in ipairs(c.rows) do if r == row then table.remove(c.rows, i) break end end
    c.override = false
    local p = { id = c.id, list = c.list or ns.Active(), qty = row.qty or 1, cost = row.buyout }
    if purchaseEventKnown() then
        pendingBids[row.auctionID] = p
        ns.Say("Buying for " .. KM.Money(row.buyout) .. "...", KM.UI.C.muted)
    else
        -- no completion event on this client: count it now
        ns.Bought(p.list, p.id, p.qty)
        sound()
        ns.Say("Bought " .. ns.Name(p.id) .. " for " .. KM.Money(p.cost) .. ".", KM.UI.C.good)
    end
    return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
KM.Register(f, "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED")
f:SetScript("OnEvent", function(_, event, a, b)
    if not ns.db then return end
    local c = ns.cur
    if event == "AUCTION_HOUSE_SHOW" then
        ahShown = true
        if ns.OnAHShow then KM.Safe(ns.OnAHShow) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- can fire twice: everything here is idempotent
        ahShown = false
        searching, run = nil, nil
        if c.phase ~= "idle" then c.phase, c.unit, c.total = "idle", nil, nil end
        wipe(pendingBids)
        c.msg = nil
        if ns.OnAHClosed then KM.Safe(ns.OnAHClosed) end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if searching and searching.id == a then
            KM.Safe(commodityResults, a)
            finish(a)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if searching and type(a) == "table" and a.itemID == searching.id then
            KM.Safe(itemResults, a)
            finish(a.itemID)
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        if c.phase ~= "pending" then return end
        c.unit, c.total = a, b
        if overMax(a) then
            c.phase = "blocked"
            local ah = AH()
            if ah.CancelCommoditiesPurchase then pcall(ah.CancelCommoditiesPurchase) end
            ns.Say(c.buyQty .. " cost " .. KM.Money(b) .. " (" .. KM.Money(a) .. " each), above your max "
                .. KM.Money(ns.CurMax()) .. ". Tick \"Buy above my max\" and click Buy again to allow it.", KM.UI.C.warn)
        else
            c.phase = "confirm"
            ns.Say("Confirm: " .. c.buyQty .. " for " .. KM.Money(b) .. " (each " .. KM.Money(a) .. ")", KM.UI.C.accent)
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if c.phase == "pending" or c.phase == "confirm" then
            c.phase = "idle"
            ns.Say("No price: there may not be that many listed any more. Search again.", KM.UI.C.warn)
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if c.phase ~= "buying" then return end
        local id, n, cost = c.buyID, c.buyQty, c.total
        c.phase, c.unit, c.total, c.override = "idle", nil, nil, false
        ns.Bought(c.list or ns.Active(), id, n)
        local e = ns.CurEntry()
        c.qty = (e and e.qty and e.qty > 0) and e.qty or 1
        sound()
        ns.Say("Bought " .. n .. " " .. ns.Name(id) .. " for " .. KM.Money(cost) .. ".", KM.UI.C.good)
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if ns.cur.id == id and ns.cur.phase == "idle" then ns.Search(id, { select = true, quiet = true }) end end)
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if c.phase ~= "buying" and c.phase ~= "confirm" then return end
        c.phase, c.unit, c.total = "idle", nil, nil
        ns.Say("The purchase failed (someone may have bought them first, or not enough gold). Search again.", KM.UI.C.bad)
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local p = pendingBids[a]
        if not p then return end
        pendingBids[a] = nil
        ns.Bought(p.list, p.id, p.qty)
        sound()
        ns.Say("Bought " .. ns.Name(p.id) .. " for " .. KM.Money(p.cost) .. ".", KM.UI.C.good)
    end
end)
