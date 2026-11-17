local _, KM = ...
local ns = KM.Module("Shopping")

-- Searching and buying at the auction house.
--
-- Searching is not protected, so "Search all", Next deal and the auto-advance after a purchase may search from a
-- timer. Buying is: every purchase step here runs only from the player's own click (a Buy or Confirm button's
-- OnClick), never from a timer, an event or a loop, and nothing is bought above the entry's max price unless the
-- player ticked the override.
--
--   commodities  Buy -> StartCommoditiesPurchase(id, qty) -> COMMODITY_PRICE_UPDATED(unit, total)
--                -> "Confirm: N for X (each Y)" -> Confirm -> ConfirmCommoditiesPurchase(id, qty)
--                -> COMMODITY_PURCHASE_SUCCEEDED | COMMODITY_PURCHASE_FAILED (| COMMODITY_PRICE_UNAVAILABLE)
--                (a purchase of a quarter of your gold or more: the first Confirm click only arms it, setting)
--   other items  search -> the cheapest auctions -> Buy on a row -> PlaceBid(auctionID, buyout)
--                -> AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)   (no answer in 6 s: dropped, searched again)
-- We only call C_AuctionHouse functions; we never hook or replace them (docs/gotchas.md 3).

local AH = function() return C_AuctionHouse end

-- The item the panel is working on.
ns.cur = { phase = "idle", rows = {} }
-- What this visit to the auction house bought (never saved; Sales Ledger keeps the real record from the mail).
ns.session = { spent = 0, buys = 0 }
local searching            -- { id, token, select, quiet, onDone, after }
local token = 0
local pendingBids = {}     -- auctionID -> { id, list, qty, cost }
local run                  -- Search all: { ids, i, waits }
local ahShown = false
local ARM_SECONDS = 4      -- the big-spend second click must come within this
local BIG_SPEND = 0.25     -- of the gold you carry
local LIVE_ROWS_FRESH = 120 -- seconds a search's auctions stay usable when the item is picked again

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

local function money()
    if not GetMoney then return nil end
    local ok, m = pcall(GetMoney)
    return ok and tonumber(m) or nil
end
ns.GoldCarried = money

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
-- The live ladder: every listing a search read, cheapest first
---------------------------------------------------------------------------

-- Units listed at or under max, from this visit's search (nil when not searched, or no max).
function ns.UnderQty(id, max)
    local lv = ns.live[id]
    if not (lv and lv.ladder and max) then return nil end
    local n = 0
    for _, s in ipairs(lv.ladder) do
        if s[1] <= max then n = n + (s[2] or 0) else break end
    end
    return n
end

-- About what the cheapest n cost from the ladder, and whether n were listed (the auction house's own price, after
-- Buy, is the real one: commodities get dearer as the cheap ones sell). nil when not searched.
function ns.LadderCost(id, n)
    local lv = ns.live[id]
    if not (lv and lv.ladder and n and n > 0) then return nil end
    local left, total = n, 0
    for _, s in ipairs(lv.ladder) do
        local take = math.min(left, s[2] or 0)
        total = total + take * s[1]
        left = left - take
        if left <= 0 then return total, true end
    end
    return total, false
end

-- How many the panel suggests buying: what you still want (a Keep entry: what's missing from its stock), but no more
-- than are listed under your max.
local function defaultQty()
    local c = ns.cur
    local e = ns.CurEntry()
    local need = e and ns.Row(e, true).need or 1
    if not c.override and c.id then
        local under = ns.UnderQty(c.id, ns.CurMax())
        if under and under > 0 then return math.min(need, under) end
    end
    return need
end

---------------------------------------------------------------------------
-- Selecting an item
---------------------------------------------------------------------------

function ns.Select(id, list)
    local c = ns.cur
    if c.phase == "pending" or c.phase == "confirm" then ns.CancelBuy(true) end
    c.override, c.armedUntil, c.qtyTouched = false, nil, false
    if c.id ~= id then
        c.rows, c.kind = {}, nil
        local live = ns.live[id]
        if live then
            c.kind = live.kind
            -- a search a moment ago (Search all) already has its auctions: no second query needed
            if live.rows and KM.Now() - (live.t or 0) <= LIVE_ROWS_FRESH then c.rows = live.rows end
        end
    end
    c.id, c.list, c.phase = id, list or ns.Active(), "idle"
    c.qty = defaultQty()
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
    if s.after then KM.Safe(s.after, id) end
end

-- Sends one item search. opts.select: the panel shows its auctions; opts.onDone(id) runs when it's answered (or
-- not, after 5 s) (Search all's step); opts.after(id) the same for anything else; opts.quiet: no messages.
-- Returns true if it was sent.
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
    searching = { id = id, token = my, select = opts.select, quiet = opts.quiet, onDone = opts.onDone, after = opts.after }
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

-- Searches as soon as the shared auction house throttle allows (a few tries, half a second apart); the last try
-- searches anyway so a busy auction house says so. Only searches: never buys.
local function searchWhenReady(id, opts, wait)
    local tries = 0
    local function go()
        if ns.cur.id ~= id or not ns.AHOpen() or run then return end
        tries = tries + 1
        if ready() or tries >= 5 then ns.Search(id, opts)
        else C_Timer.After(0.5, go) end
    end
    if wait then C_Timer.After(0.5, go) else go() end
end

-- Fills Blizzard's own auction house search bar with the item's name and runs that search, so its results show in
-- Blizzard's window and the player can buy there too (clicking a result opens Blizzard's buy window). Runs only from
-- the player's click (Find, or the page's right-click menu). Searching isn't protected; nothing here buys. Returns
-- true if the search was started.
function ns.SearchInAH(id)
    local f = AuctionHouseFrame
    local bar = type(f) == "table" and rawget(f, "SearchBar") or nil
    local box = type(bar) == "table" and rawget(bar, "SearchBox") or nil
    if not (ns.AHOpen() and type(box) == "table" and box.SetText) then return false end
    local name = ns.Name(id)
    if not name or name:find("^Item %d+$") then return false end
    if not pcall(box.SetText, box, name) then return false end
    if type(bar.StartSearch) == "function" and pcall(bar.StartSearch, bar) then return true end
    local btn = rawget(bar, "SearchButton")
    if type(btn) == "table" and btn.Click and pcall(btn.Click, btn) then return true end
    return false
end

-- Find: pick the item, show it in Blizzard's window, then look it up for the panel too once the throttle allows.
function ns.FindItem(id)
    ns.Select(id, ns.Active())
    if not ns.SearchInAH(id) then return ns.Search(id, { select = true }) end
    searchWhenReady(id, { select = true }, true)
    return true
end

-- The page and the badge show live prices: redraw once shortly after a burst of searches.
local refreshSoon = false
local function refreshPageSoon()
    if refreshSoon or not (C_Timer and C_Timer.After) then return end
    refreshSoon = true
    C_Timer.After(0.5, function()
        refreshSoon = false
        if KM.IsShown and KM.IsShown("shopping") then KM.Refresh("shopping") end
        if KM.RefreshBadges then KM.RefreshBadges() end
    end)
end

local function store(id, kind, rows, listed, ladder)
    ns.live[id] = { p = rows[1] and rows[1].unit or nil, q = listed, t = KM.Now(), kind = kind, ladder = ladder, rows = rows }
    local c = ns.cur
    if c.id == id then
        c.kind, c.rows = kind, rows
        if c.phase == "idle" and not c.qtyTouched then c.qty = defaultQty() end
        if searching and searching.select and not searching.quiet then
            if #rows == 0 then ns.Say("None listed right now.", KM.UI.C.muted)
            elseif overMax(rows[1].unit) then ns.Say("The cheapest is above your max (" .. KM.Money(ns.CurMax()) .. ").", KM.UI.C.warn)
            else ns.Say(nil) end
        end
    end
    refreshPageSoon()
end

local function commodityResults(id)
    local ah = AH()
    local n = ah.GetNumCommoditySearchResults and select(2, pcall(ah.GetNumCommoditySearchResults, id)) or 0
    n = tonumber(n) or 0
    local rows, ladder, listed = {}, {}, 0
    for i = 1, math.min(n, 50) do
        local ok, info = pcall(ah.GetCommoditySearchResultInfo, id, i)
        if ok and type(info) == "table" and info.unitPrice then
            listed = listed + (info.quantity or 0)
            ladder[#ladder + 1] = { info.unitPrice, info.quantity or 0 }
            if #rows < 6 then rows[#rows + 1] = { unit = info.unitPrice, qty = info.quantity or 0, auctionID = info.auctionID } end
        end
    end
    table.sort(ladder, function(a, b) return a[1] < b[1] end)
    store(id, "commodity", rows, listed, ladder)
end

-- How many of an item fit in one stack (nil when the game hasn't loaded the item yet).
local function maxStack(id)
    if C_Item and C_Item.GetItemMaxStackByID then
        local ok, n = pcall(C_Item.GetItemMaxStackByID, id)
        if ok and tonumber(n) and n > 0 then return n end
    end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info then
        local r = { pcall(info, id) }
        local n = r[1] and tonumber(r[9])
        if n and n > 0 then return n end
    end
end

-- Forever can report an item auction's quantity as the count of matching auctions (24 Pattern: Big Voodoo Cloak at
-- 14s came back as one row of quantity 24, so 14s / 24 showed 58c). An auction never holds more than one stack,
-- so the unit price divides by at most the item's stack size: 1 for patterns and gear.
local function itemResults(key)
    local ah = AH()
    local id = key.itemID
    local n = ah.GetNumItemSearchResults and select(2, pcall(ah.GetNumItemSearchResults, key)) or 0
    n = tonumber(n) or 0
    local rows, listed = {}, 0
    local stack = maxStack(id)
    for i = 1, math.min(n, 50) do
        local ok, info = pcall(ah.GetItemSearchResultInfo, key, i)
        if ok and type(info) == "table" and info.buyoutAmount and info.buyoutAmount > 0 then
            local raw = math.max(1, info.quantity or 1)
            local q = stack and math.min(raw, stack) or raw
            listed = listed + raw
            rows[#rows + 1] = { unit = math.floor(info.buyoutAmount / q), buyout = info.buyoutAmount, qty = q,
                auctionID = info.auctionID, link = info.itemLink }
        end
    end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    for i = #rows, 9, -1 do rows[i] = nil end
    local ladder = {}
    for i, r in ipairs(rows) do ladder[i] = { r.unit, r.qty } end
    store(id, "item", rows, listed, ladder)
end

---------------------------------------------------------------------------
-- Deals on the active list, and moving between them (selecting and searching only; never buying)
---------------------------------------------------------------------------

-- The active list's rows, deals first (ns.SortRows).
function ns.ActiveRows()
    local rows = {}
    for _, e in ipairs(ns.Entries(ns.Active()) or {}) do rows[#rows + 1] = ns.Row(e, true) end
    return ns.SortRows(rows)
end

-- The deal after the current item in that order (wrapping), or the best one when the current item isn't a deal.
-- nil when there is no other deal.
function ns.NextDeal()
    local deals = {}
    for _, r in ipairs(ns.ActiveRows()) do if r.status == "under" then deals[#deals + 1] = r.id end end
    if #deals == 0 then return nil end
    local cur = ns.cur.id
    for i, id in ipairs(deals) do
        if id == cur then
            local nxt = deals[i % #deals + 1]
            return nxt ~= cur and nxt or nil
        end
    end
    return deals[1]
end

-- The Next deal button (and the auto-advance after a purchase): select the next deal and look it up.
function ns.GoNextDeal(auto)
    local id = ns.NextDeal()
    if not id then
        if not auto then ns.Say("No more deals on this list.", KM.UI.C.muted) end
        return false
    end
    ns.Select(id, ns.Active())
    ns.Say("Next deal: " .. ns.Name(id) .. ". Looking it up...", KM.UI.C.muted)
    searchWhenReady(id, { select = true, quiet = true })
    return true
end

-- After a purchase: look the item up again (a second later); when it's done or no longer under the max and the
-- setting is on, move to the next deal. Every purchase is still the player's own click.
local function maybeAdvance(id)
    local c = ns.cur
    if c.id ~= id or c.phase ~= "idle" or run or not (ns.db and ns.db.settings.autoNext) then return end
    local e = ns.CurEntry()
    if e and ns.Row(e, true).status == "under" then return end
    ns.GoNextDeal(true)
end
ns.MaybeAdvance = maybeAdvance

local function afterPurchase(id)
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(1, function()
        if ns.cur.id ~= id or ns.cur.phase ~= "idle" then return end
        if not ns.Search(id, { select = true, quiet = true, after = maybeAdvance }) then maybeAdvance(id) end
    end)
end

local function spent(cost)
    local s = ns.session
    s.spent, s.buys = s.spent + (cost or 0), s.buys + 1
end

---------------------------------------------------------------------------
-- Search all: the active list's searches, one after another (buying stays one click each)
---------------------------------------------------------------------------

function ns.SearchAllRunning() return run ~= nil end
function ns.SearchAllProgress() if run then return run.i, #run.ids end end

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
            -- the best deal is picked with its auctions from the search just made: no extra query
            local rows, deals = ns.ActiveRows(), 0
            for _, r in ipairs(rows) do if r.status == "under" then deals = deals + 1 end end
            if deals > 0 then ns.Select(rows[1].id, ns.Active()) end
            ns.Say("Searched " .. #me.ids .. " items: " .. (deals == 0 and "nothing under your max."
                or (deals .. " deal" .. (deals == 1 and "" or "s") .. ". Buy below, or Next deal.")),
                deals > 0 and KM.UI.C.good or KM.UI.C.muted)
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
-- Buying a commodity: two clicks (three for a big spend)
---------------------------------------------------------------------------

local function share(total)
    local m = money()
    if not (m and m > 0 and total) then return nil end
    return total / m
end

-- Is the big-spend second click armed (the first Confirm click came less than 4 seconds ago)?
function ns.Armed()
    local c = ns.cur
    return c.armedUntil ~= nil and GetTime() <= c.armedUntil
end

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
    local est = ns.LadderCost(c.id, qty) or (cheapest and cheapest * qty)
    local m = money()
    if est and m and est > m then
        ns.Say("That's about " .. KM.Money(est) .. "; you carry " .. KM.Money(m) .. ".", KM.UI.C.warn)
        return false
    end
    if not ready() then ns.Say(THROTTLED, KM.UI.C.warn) return false end
    local ok, err = pcall(ah.StartCommoditiesPurchase, c.id, qty)
    if not ok then ns.Say("The auction house refused: " .. tostring(err), KM.UI.C.bad) return false end
    c.qty, c.phase, c.unit, c.total, c.armedUntil = qty, "pending", nil, nil, nil
    c.buyID, c.buyQty, c.estUnit = c.id, qty, est and est / qty or nil
    ns.Say("Asking the auction house for the price of " .. qty .. "...", KM.UI.C.muted)
    return true
end

-- Click 2 (the Confirm button's OnClick). Returns true if the purchase was sent.
function ns.ConfirmBuy()
    local c, ah = ns.cur, AH()
    if c.phase ~= "confirm" or c.buyID ~= c.id or not c.unit then return false end
    if overMax(c.unit) then
        c.phase = "blocked"
        ns.Say("Above your max: tick \"Allow one buy above my max\" to allow it.", KM.UI.C.warn)
        return false
    end
    if not ns.AHOpen() then ns.Say("Open the auction house to buy.", KM.UI.C.warn) return false end
    local part = share(c.total)
    if ns.db.settings.bigSpend and part and part >= BIG_SPEND and not ns.Armed() then
        -- a big spend: this click only arms Confirm; the purchase needs a second click of the player's own
        c.armedUntil = GetTime() + ARM_SECONDS
        ns.Say("That's " .. math.floor(part * 100 + 0.5) .. "% of your gold. Click Confirm again to buy "
            .. c.buyQty .. " for " .. KM.Money(c.total) .. ".", KM.UI.C.warn)
        if C_Timer and C_Timer.After then
            C_Timer.After(ARM_SECONDS + 0.1, function() if ns.RefreshPanel then ns.RefreshPanel() end end)
        end
        return false
    end
    if not ready() then ns.Say(THROTTLED, KM.UI.C.warn) return false end
    local ok, err = pcall(ah.ConfirmCommoditiesPurchase, c.buyID, c.buyQty)
    c.armedUntil = nil
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
    c.phase, c.unit, c.total, c.armedUntil = "idle", nil, nil, nil
    if not silent then ns.Say("Cancelled.", KM.UI.C.muted)
    elseif ns.RefreshPanel then ns.RefreshPanel() end
end

---------------------------------------------------------------------------
-- Buying one auction of a non-commodity item: one click per auction
---------------------------------------------------------------------------

local function purchaseEventKnown()
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("AUCTION_HOUSE_PURCHASE_COMPLETED")
end

function ns.PendingBids()
    local n = 0
    for _ in pairs(pendingBids) do n = n + 1 end
    return n
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
    local m = money()
    if m and row.buyout > m then
        ns.Say("That's " .. KM.Money(row.buyout) .. "; you carry " .. KM.Money(m) .. ".", KM.UI.C.warn)
        return false
    end
    if not ready() then ns.Say(THROTTLED, KM.UI.C.warn) return false end
    local ok, err = pcall(ah.PlaceBid, row.auctionID, row.buyout)
    if not ok then ns.Say("The purchase failed: " .. tostring(err), KM.UI.C.bad) return false end
    for i, r in ipairs(c.rows) do if r == row then table.remove(c.rows, i) break end end
    c.override = false
    local p = { id = c.id, list = c.list or ns.Active(), qty = row.qty or 1, cost = row.buyout }
    if purchaseEventKnown() then
        local aid = row.auctionID
        pendingBids[aid] = p
        ns.Say("Buying for " .. KM.Money(row.buyout) .. "...", KM.UI.C.muted)
        if C_Timer and C_Timer.After then
            -- no answer (outbid, sold, not enough gold): drop it and look again rather than wait forever
            C_Timer.After(6, function()
                if pendingBids[aid] ~= p then return end
                pendingBids[aid] = nil
                ns.Say("No answer for that auction (it may have sold). Search again.", KM.UI.C.warn)
                if ns.cur.id == p.id and ns.cur.phase == "idle" then ns.Search(p.id, { select = true, quiet = true }) end
            end)
        end
    else
        -- no completion event on this client: count it now
        ns.Bought(p.list, p.id, p.qty)
        spent(p.cost)
        sound()
        ns.Say("Bought " .. ns.Name(p.id) .. " for " .. KM.Money(p.cost) .. ".", KM.UI.C.good)
        afterPurchase(p.id)
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
        ns.session = { spent = 0, buys = 0 }
        if ns.OnAHShow then KM.Safe(ns.OnAHShow) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- can fire twice: everything here is idempotent (the visit's total prints once, then it's zero)
        ahShown = false
        searching, run = nil, nil
        if c.phase ~= "idle" then c.phase, c.unit, c.total = "idle", nil, nil end
        c.armedUntil = nil
        wipe(pendingBids)
        c.msg = nil
        local s = ns.session
        if s.buys > 0 then
            KM.Print(ns, s.buys .. " buy" .. (s.buys == 1 and "" or "s") .. ", " .. KM.Money(s.spent) .. " this visit.")
        end
        ns.session = { spent = 0, buys = 0 }
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
        local m = money()
        if overMax(a) then
            c.phase = "blocked"
            local ah = AH()
            if ah.CancelCommoditiesPurchase then pcall(ah.CancelCommoditiesPurchase) end
            ns.Say(c.buyQty .. " cost " .. KM.Money(b) .. " (" .. KM.Money(a) .. " each), above your max "
                .. KM.Money(ns.CurMax()) .. ". Tick \"Allow one buy above my max\" and click Buy again to allow it.", KM.UI.C.warn)
        elseif m and b and b > m then
            c.phase = "blocked"
            local ah = AH()
            if ah.CancelCommoditiesPurchase then pcall(ah.CancelCommoditiesPurchase) end
            ns.Say("That's " .. KM.Money(b) .. "; you carry " .. KM.Money(m) .. ". Buy fewer.", KM.UI.C.warn)
        else
            c.phase = "confirm"
            local part = share(b)
            local text = "Confirm: " .. c.buyQty .. " for " .. KM.Money(b) .. " (each " .. KM.Money(a) .. ")."
                .. (part and (" That's " .. math.max(1, math.floor(part * 100 + 0.5)) .. "% of your gold.") or "")
            local color = KM.UI.C.accent
            if c.estUnit and a and a > c.estUnit * 1.1 then
                text = text .. " Dearer than the search showed (" .. ns.Short(c.estUnit, true) .. " -> " .. ns.Short(a, true) .. " each)."
                color = KM.UI.C.warn
            end
            ns.Say(text, color)
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if c.phase == "pending" or c.phase == "confirm" then
            c.phase = "idle"
            ns.Say("No price: there may not be that many listed any more. Search again.", KM.UI.C.warn)
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if c.phase ~= "buying" then return end
        local id, n, cost = c.buyID, c.buyQty, c.total
        c.phase, c.unit, c.total, c.override, c.qtyTouched = "idle", nil, nil, false, false
        ns.Bought(c.list or ns.Active(), id, n)
        spent(cost)
        c.qty = defaultQty()
        sound()
        ns.Say("Bought " .. n .. " " .. ns.Name(id) .. " for " .. KM.Money(cost) .. ".", KM.UI.C.good)
        afterPurchase(id)
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if c.phase ~= "buying" and c.phase ~= "confirm" then return end
        c.phase, c.unit, c.total = "idle", nil, nil
        ns.Say("The purchase failed (someone may have bought them first, or not enough gold). Search again.", KM.UI.C.bad)
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local p = pendingBids[a]
        if not p then return end
        pendingBids[a] = nil
        ns.Bought(p.list, p.id, p.qty)
        spent(p.cost)
        sound()
        ns.Say("Bought " .. ns.Name(p.id) .. " for " .. KM.Money(p.cost) .. ".", KM.UI.C.good)
        if ns.cur.id == p.id then afterPurchase(p.id) end
    end
end)
