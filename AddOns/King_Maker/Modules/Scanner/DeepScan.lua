local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API
local UI = KM.UI
local C = UI.C

-- Deep Scan: the whole auction house, every item.
--
--   1. C_AuctionHouse.ReplicateItems() sends every auction in one go. The game
--      allows it once every 15 minutes. From the individual auctions we work
--      out each item's market price, lowest buyout, how many are listed, in how
--      many auctions and from how many sellers.
--   2. If that isn't available, is on cooldown or doesn't answer, it browses
--      every category instead: each item's lowest price and quantity listed
--      (no market price: that needs the individual listings).
--
-- When it's done, callbacks get "SCAN_RESULTS" (results, "deep", method) with
-- every item it saw (see API.md), then "SCAN_FINISHED" and "PRICES_UPDATED".
--
-- This is the "full scan" half of King Maker's one Scan button (Scan.lua, ScannerKing.SmartScan): a click
-- runs it when the full dump is off cooldown (ns.FullScanWait() == 0) and shows its progress on the button.
-- /sk deep and ScannerKing.OpenDeepScan(true) force it (browsing every category while the dump is on
-- cooldown) and open a small King Maker dialog that follows it with a progress bar until it's done.

local REPLICATE_COOLDOWN = 15 * 60
local REPLICATE_TIMEOUT = 60  -- seconds to wait for the auction dump
local SETTLE = 0.5            -- seconds the auction count must hold still before it's read
local INFO_PASSES = 10        -- times to go back for auctions whose item info hadn't loaded
local INFO_WAIT = 1           -- seconds between those passes
local PAGE_TIMEOUT = 15       -- seconds without a new browse page before giving up
local BATCH = 2000            -- auctions read per frame, so the game doesn't freeze

local running, method, run, pages = false, nil, 0, 0
local startBrowse
local auctions = {}           -- itemID -> { { unit price, count }, ..., sellers = { [name] = true } }
local results = {}

function ns.DeepRunning() return running end

local function button() return ns.ScanButton and ns.ScanButton() end

-- Seconds until the game allows the next full dump (0 = now), or nil when this client has no ReplicateItems.
function ns.FullScanWait()
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return nil end
    local since = ns.db and ns.db.lastReplicate and (ns.Now() - ns.db.lastReplicate) or math.huge
    return math.max(0, math.ceil(REPLICATE_COOLDOWN - since))
end
API.FullScanReadyIn = ns.FullScanWait

-- frac: 0 to 1 for the progress bar, or nil when there's no telling how far along it is.
local function show(text, frac)
    ns.Fire("SCAN_PROGRESS", text)
    local b = button()
    if b and text then b:SetLabel(text) end
    if ns.DeepWindowProgress then ns.DeepWindowProgress(text, frac) end
end

---------------------------------------------------------------------------
-- Market price: the average of the cheapest 15-30% of what's listed, so one
-- cheap or silly listing doesn't decide it.
---------------------------------------------------------------------------

-- list: { { unit price, count }, ... } sorted cheapest first.
function ns.MarketValue(list)
    local total = 0
    for _, l in ipairs(list) do total = total + l[2] end
    if total == 0 then return nil end
    local low, high = total * 0.15, total * 0.30
    local picked, taken, prev = {}, 0, nil
    for _, l in ipairs(list) do
        -- Past 15%, stop at 30% or where the price jumps by more than a fifth.
        if taken >= low and (taken >= high or (prev and l[1] > prev * 1.2)) then break end
        table.insert(picked, l)
        taken, prev = taken + l[2], l[1]
    end
    local function mean(skipAbove)
        local sum, n = 0, 0
        for _, l in ipairs(picked) do
            if not skipAbove or l[1] <= skipAbove then sum, n = sum + l[1] * l[2], n + l[2] end
        end
        return n > 0 and sum / n or nil, n
    end
    local m, n = mean()
    if #picked > 1 then
        local var = 0
        for _, l in ipairs(picked) do var = var + (l[1] - m) ^ 2 * l[2] end
        local sd = math.sqrt(var / n)
        if sd > 0 then m = mean(m + 1.5 * sd) or m end
    end
    return math.floor(m + 0.5)
end

---------------------------------------------------------------------------
-- Finishing
---------------------------------------------------------------------------

local function resetButton()
    local b = button()
    if b then b:SetEnabled2(true); b:SetLabel(b.caption or "Scan") end
end

local function isShared(id, watched)
    -- Only Trade Goods and watched items go to the guild; a whole auction house would flood it.
    if watched[id] then return true end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local classID = inst and select(6, inst(id))
    return classID == 7
end

local function finish()
    if not running then return end
    running = false
    local now, found = ns.Now(), 0
    local watched = {}
    for _, id in ipairs(ns.WatchedItems()) do watched[id] = true end
    for id, r in pairs(results) do
        ns.db.prices[id] = { p = r.p, m = r.m, q = r.q, n = r.n, t = now, d = (not isShared(id, watched)) or nil }
        found = found + 1
    end
    ns.db.lastScan, ns.db.lastDeep = now, now
    resetButton()
    local summary = "Deep Scan done: " .. found .. " items priced"
        .. (method == "browse" and " (lowest prices only)." or method == "partial" and " (the auction house stopped answering partway)." or ".")
    KM.Print(ns, summary)
    ns.Fire("SCAN_PROGRESS", "Deep Scan done: " .. found .. " items")
    if ns.DeepWindowDone then ns.DeepWindowDone(summary, true) end
    ns.Fire("SCAN_RESULTS", results, "deep", method)
    ns.Fire("SCAN_FINISHED", found)
    ns.Fire("PRICES_UPDATED")
    if ns.SharePrices then ns.SharePrices() end
end

local function stop(reason)
    if not running then return end
    running = false
    resetButton()
    KM.Print(ns, reason)
    if ns.DeepWindowDone then ns.DeepWindowDone(reason, false) end
    ns.Fire("SCAN_FINISHED", 0)
end
ns.StopDeep = stop

---------------------------------------------------------------------------
-- 1. Every auction at once
---------------------------------------------------------------------------

local function summarize()
    results = {}
    for id, list in pairs(auctions) do
        table.sort(list, function(a, b) return a[1] < b[1] end)
        local q, sellers = 0, 0
        for _, l in ipairs(list) do q = q + l[2] end
        for _ in pairs(list.sellers) do sellers = sellers + 1 end
        local plain = {}
        for i, l in ipairs(list) do plain[i] = l end
        results[id] = { p = math.floor(list[1][1] + 0.5), m = ns.MarketValue(list), q = q, n = #list,
                        s = sellers > 0 and sellers or nil, l = plain }
    end
    auctions = {}
    method = "replicate"
    finish()
end

-- Reads auctions from..to (or the indexes in list). The game sends an auction before
-- its item's details have loaded: those (hasAllInfo false, or no item yet) go in missing
-- to be read again once the details arrive, instead of being dropped.
local function readRange(from, to, missing, list)
    local get = C_AuctionHouse.GetReplicateItemInfo
    for n = from, to do
        local i = list and list[n] or n
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo = get(i)
        if not itemID or hasAllInfo == false then
            table.insert(missing, i)
            if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
        elseif buyout and buyout > 0 and count and count > 0 then
            local l = auctions[itemID]
            if not l then l = { sellers = {} }; auctions[itemID] = l end
            table.insert(l, { buyout / count, count })
            if owner and owner ~= "" then l.sellers[owner] = true end
        end
    end
end

local function numReplicate()
    return C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetNumReplicateItems() or 0
end

-- Goes back for auctions whose item details hadn't loaded, a few times, then summarizes.
local function readMissing(missing, total, myRun, pass)
    if #missing == 0 or pass > INFO_PASSES then
        if #missing > 0 then KM.Print(ns, #missing .. " auctions never sent their item details and were skipped.") end
        return summarize()
    end
    show("Loading item details: " .. #missing .. " left", (total - #missing) / math.max(total, 1))
    C_Timer.After(INFO_WAIT, function()
        if not running or run ~= myRun then return end
        if not (ns.AHOpen and ns.AHOpen()) then return stop("Deep Scan stopped because the auction house closed.") end
        local still = {}
        if not pcall(readRange, 1, #missing, still, missing) then still = {} end
        readMissing(still, total, myRun, pass + 1)
    end)
end

local function readReplicate(total)
    if total == 0 then
        KM.Print(ns, "The auction house sent an empty list; browsing every category instead.")
        return startBrowse()
    end
    auctions = {}
    local missing = {}
    local i = 0 -- the game numbers them from 0
    local myRun = run
    local function batch()
        if not running or run ~= myRun then return end
        if not (ns.AHOpen and ns.AHOpen()) then return stop("Deep Scan stopped because the auction house closed.") end
        local last = math.min(i + BATCH, total) - 1
        if last >= i and not pcall(readRange, i, last, missing) then
            KM.Print(ns, "Couldn't read the auction list; some auctions were skipped.")
        end
        i = last + 1
        show("Reading " .. math.floor(math.min(i, total) / math.max(total, 1) * 100) .. "%", math.min(i, total) / math.max(total, 1))
        if i < total then C_Timer.After(0, batch) else readMissing(missing, total, myRun, 1) end
    end
    batch()
end

-- The list can still be arriving when the game says it's ready: wait until its size holds still.
local function settle(myRun, last)
    if not running or run ~= myRun then return end
    local now = numReplicate()
    if now == last then return readReplicate(now) end
    show("Downloading: " .. now .. " auctions", nil)
    C_Timer.After(SETTLE, function() settle(myRun, now) end)
end

---------------------------------------------------------------------------
-- 2. Browsing every category
---------------------------------------------------------------------------

local function sorts()
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

local function watchdog(myRun, lastPages)
    C_Timer.After(PAGE_TIMEOUT, function()
        if not running or run ~= myRun or method ~= "browse" then return end
        if pages ~= lastPages then return watchdog(myRun, pages) end
        -- Keep what arrived, but say it's partial so nobody reads missing items as sold out.
        if next(results) then method = "partial"; finish() else stop("Deep Scan stopped: the auction house didn't answer.") end
    end)
end

local function readBrowse()
    local ok, list = pcall(C_AuctionHouse.GetBrowseResults)
    if ok and list then
        -- The list holds every page so far; an item can show up once per item level or suffix.
        results = {}
        for _, r in ipairs(list) do
            local id = r.itemKey and r.itemKey.itemID
            if id and r.minPrice and r.minPrice > 0 then
                local e = results[id]
                -- Lowest price only: browsing doesn't show the listings a market price needs.
                if not e then
                    results[id] = { p = r.minPrice, q = r.totalQuantity or 0 }
                else
                    e.p = math.min(e.p, r.minPrice)
                    e.q = e.q + (r.totalQuantity or 0)
                end
            end
        end
    end
    pages = pages + 1
    local n = 0
    for _ in pairs(results) do n = n + 1 end
    show("Browsing: " .. n .. " items", nil)
    if C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() then
        if C_AuctionHouse.RequestMoreBrowseResults then C_AuctionHouse.RequestMoreBrowseResults() end
        return
    end
    finish()
end

startBrowse = function()
    if not running then return end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(0.2, startBrowse)
        return
    end
    if not C_AuctionHouse.SendBrowseQuery then return stop("Deep Scan couldn't search the auction house.") end
    method, pages, results = "browse", 0, {}
    run = run + 1
    show("Browsing every category...", nil)
    local query = { searchString = "", sorts = sorts(), filters = {}, itemClassFilters = {} }
    if not pcall(C_AuctionHouse.SendBrowseQuery, query) then return stop("Deep Scan couldn't search the auction house.") end
    watchdog(run, pages)
end

---------------------------------------------------------------------------
-- Starting
---------------------------------------------------------------------------

function API.DeepScan()
    if not ns.db then return end
    if not (ns.AHOpen and ns.AHOpen()) then
        KM.Print(ns, "Open the auction house first, then click Scan or type /sk deep.")
        return
    end
    if not (C_AuctionHouse and (C_AuctionHouse.ReplicateItems or C_AuctionHouse.SendBrowseQuery)) then
        KM.Print(ns, "Deep Scan needs the modern auction house.")
        return
    end
    if API.IsScanning() then
        KM.Print(ns, "A scan is already running.")
        return
    end
    running, results = true, {}
    local b = button()
    if b then b:SetEnabled2(false) end
    ns.Fire("SCAN_STARTED")
    local wait = ns.FullScanWait()
    if wait == 0 then
        method = "replicate"
        run = run + 1
        ns.db.lastReplicate = ns.Now()
        KM.Print(ns, "Deep Scan: downloading every auction. This can take a minute; keep the auction house open.")
        show("Downloading every auction...", nil)
        if not pcall(C_AuctionHouse.ReplicateItems) then return startBrowse() end
        local myRun = run
        C_Timer.After(REPLICATE_TIMEOUT, function()
            if running and run == myRun and method == "replicate" then
                KM.Print(ns, "The auction house didn't send its full list; browsing every category instead.")
                startBrowse()
            end
        end)
    else
        if wait then
            KM.Print(ns, "The full auction list can be downloaded again in " .. math.ceil(wait / 60)
                .. " min. Browsing every category instead (lowest prices only).")
        end
        startBrowse()
    end
end

function API.LastDeepScan() return ns.db and ns.db.lastDeep end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local win, modeText, bar, status, lastText, scanBtn
local reported = false -- the window already shows how the last start ended
local GREEN, GOLD, RED = UI.Hex(C.good), UI.Hex(C.accent), UI.Hex(C.bad)

-- Which scan a click gives you right now.
local function modeLine()
    local w = ns.FullScanWait()
    if w == 0 then
        return GREEN .. "Full scan ready.|r Downloads every auction: market price, lowest buyout and how many are listed. About a minute."
    end
    local wait = w and ("Full scan ready again in " .. math.ceil(w / 60) .. " min (the game allows one every 15). ") or ""
    return GOLD .. wait .. "|rScanning now browses every category instead: lowest prices only."
end

local function refreshWindow()
    if not win then return end
    modeText:SetText(modeLine())
    lastText:SetText(ns.db.lastDeep and ("Last Deep Scan " .. API.PriceAge(ns.db.lastDeep)) or "No Deep Scan yet.")
    scanBtn:SetEnabled2(not API.IsScanning())
end

local function createWindow()
    win = UI.Window("ScannerKingDeepScan", "Deep Scan", 320, 230)
    local body = win.body
    local help = UI.Para(body, 11, C.muted, 292)
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetText("Prices every item on the auction house. Keep the auction house open until it's done.")
    modeText = UI.Para(body, 11, C.text, 292)
    modeText:SetPoint("TOPLEFT", 0, -34)

    status = UI.Text(body, 11, C.text, "CENTER")
    status:SetPoint("BOTTOMLEFT", 0, 80)
    status:SetPoint("BOTTOMRIGHT", 0, 80)
    bar = UI.Bar(body, 8)
    bar:SetPoint("BOTTOMLEFT", 0, 64)
    bar:SetPoint("BOTTOMRIGHT", 0, 64)
    bar:Set(0)
    lastText = UI.Text(body, 10, C.dim, "CENTER")
    lastText:SetPoint("BOTTOMLEFT", 0, 46)
    lastText:SetPoint("BOTTOMRIGHT", 0, 46)

    scanBtn = UI.Button(body, "Scan", 130, 26, function() ns.StartDeepFromWindow() end, "primary")
    scanBtn:SetPoint("BOTTOM", 0, 4)
end

function ns.StartDeepFromWindow()
    status:SetText("Starting...")
    bar:Set(0)
    reported = false
    API.DeepScan()
    if not running and not reported then
        status:SetText(RED .. "Couldn't start; the reason is in chat.|r")
    end
    refreshWindow()
end

-- While it runs: what it's doing, and how far along (frac nil = can't tell, so the bar pulses).
local pulse = 0
function ns.DeepWindowProgress(text, frac)
    if not win then return end
    status:SetText(text or "")
    if frac then
        bar:Set(frac)
    else
        pulse = (pulse + 0.1) % 1
        bar:Set(pulse, C.info)
    end
    scanBtn:SetEnabled2(false)
end

function ns.DeepWindowDone(summary, ok)
    if not win then return end
    reported = true
    status:SetText(ok and (GREEN .. summary .. "|r") or (RED .. summary .. "|r"))
    bar:Set(ok and 1 or 0, ok and C.good or C.bad)
    scanBtn:SetLabel("Scan again")
    refreshWindow()
end

function ns.ToggleDeepScan(anchor, show)
    if not ns.db then return end
    if not win then createWindow() end
    if show == nil then show = not win:IsShown() end
    if show then
        win:ClearAllPoints()
        if anchor and anchor:IsShown() then
            win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
        else
            win:SetPoint("CENTER")
        end
        if not running then
            status:SetText("")
            bar:Set(0)
            scanBtn:SetLabel("Scan")
        end
        refreshWindow()
    end
    win:SetShown(show)
end

-- Opens the window and starts the scan (/sk deep, and other addons).
function API.OpenDeepScan(start)
    ns.ToggleDeepScan(ns.ahParent, true)
    if start and not running then ns.StartDeepFromWindow() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_CLOSED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        pcall(f.RegisterEvent, f, event)
    end
end
f:SetScript("OnEvent", function(_, event)
    if not running then return end
    if event == "AUCTION_HOUSE_CLOSED" then
        stop("Deep Scan stopped because the auction house closed.")
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if method == "replicate" then
            method = "replicate-reading"
            settle(run, -1)
        end
    elseif method == "browse" then
        readBrowse()
    end
end)
