local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API
local UI = KM.UI

-- Scanning the auction house: the one Scan button, and the quick scan.
--
-- King Maker has one scan. A click on Scan (the auction house title bar, the Prices page, the crown's quick
-- action, /sk scan) runs ScannerKing.SmartScan():
--   * the full scan (Deep Scan, DeepScan.lua) when the game allows one (ReplicateItems, once every 15 minutes);
--   * otherwise a quick scan (QuickScan, MarketScan.lua) of everything King Maker cares about: Trade Goods,
--     every Watch() list and every scan provider's current selection (Crafting Profits' ticked professions).
--
-- On the modern auction house a quick scan is a handful of requests:
--   1. Browse the whole Trade Goods category. The auction house answers with
--      every item's lowest price, a page at a time.
--   2. Items other addons asked for (ScannerKing.Watch) that weren't in Trade
--      Goods are looked up together in one more search.
--   3. Only if one of those doesn't answer does it fall back to searching item
--      by item, which is slow because of Blizzard's search limit.
-- On a classic-style auction house window it scans the watched items one by one.

local TRADE_GOODS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local ITEM_TIMEOUT = 4   -- seconds to wait for one item before moving on
local PAGE_TIMEOUT = 15  -- seconds without a new page before giving up on a search

local KEY_CHUNK = 100     -- items per multi-item search

local scanning, phase, run = false, nil, 0
local kind = "material"   -- what started the running scan, for SCAN_RESULTS
local scanList = {}       -- items to price besides Trade Goods: watched ones plus any a caller asked for
local keyChunks, keysTotal = {}, 0
local found, seen, pages = 0, {}, 0
local queue, current, total = {}, nil, 0
local scanButton -- the button that started the running scan (shows its progress)
local buttons = {} -- title-bar buttons per auction house window, made the first time it opens

---------------------------------------------------------------------------
-- Which auction house is open
---------------------------------------------------------------------------

-- Both windows are load-on-demand, so they may not exist when AUCTION_HOUSE_SHOW fires.
local function modernAH()
    return C_AuctionHouse and C_AuctionHouse.SendSearchQuery and AuctionHouseFrame and AuctionHouseFrame:IsShown()
end
local function classicAH()
    return QueryAuctionItems and AuctionFrame and AuctionFrame:IsShown()
end
local function ahOpen() return modernAH() or classicAH() end
ns.AHOpen = ahOpen

local function throttleReady()
    if modernAH() then
        return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
    end
    return not CanSendAuctionQuery or CanSendAuctionQuery()
end

-- The last SCAN_PROGRESS text of any scan (quick or full), for the Scan button's tooltip.
local lastProgress = ""
local function progress(text)
    ns.Fire("SCAN_PROGRESS", text)
end
API.RegisterCallback("Scanner_King_progress", function(event, text)
    if event == "SCAN_PROGRESS" then lastProgress = text or "" end
end)

local function sorts()
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

---------------------------------------------------------------------------
-- Finishing
---------------------------------------------------------------------------

local function resetButton()
    if scanButton then scanButton:SetEnabled2(true); scanButton:SetLabel(scanButton.caption or "Scan") end
    scanButton = nil
end

-- Everything this scan priced, for SCAN_RESULTS: { [itemID] = { p = copper, q = quantity } }.
local function results()
    local r = {}
    for id in pairs(seen) do
        local pr = ns.db.prices[id]
        if pr then r[id] = { p = pr.p, q = pr.q } end
    end
    return r
end

local function finish()
    if not scanning then return end
    scanning, phase, current = false, nil, nil
    if pages > 0 then ns.db.lastScan = ns.Now() end
    ns.db.lastQuick = ns.Now()
    resetButton()
    progress("Scan done: " .. found .. " prices")
    KM.Print(ns, "Scan done: " .. found .. " items priced.")
    ns.Fire("SCAN_RESULTS", results(), kind)
    ns.Fire("SCAN_FINISHED", found)
    ns.Fire("PRICES_UPDATED")
    if found > 0 and ns.SharePrices then ns.SharePrices() end
end

local function stop(reason)
    if not scanning then return end
    scanning, phase, current = false, nil, nil
    resetButton()
    KM.Print(ns, reason)
    if found > 0 then ns.Fire("SCAN_RESULTS", results(), kind) end
    ns.Fire("SCAN_FINISHED", found)
    if found > 0 then
        ns.Fire("PRICES_UPDATED")
        if ns.SharePrices then ns.SharePrices() end
    end
end

local function store(id, copper, qty)
    if not seen[id] and ns.Store(id, copper, qty) then
        seen[id] = true
        found = found + 1
    end
end

---------------------------------------------------------------------------
-- Phase 3: item by item (slow fallback, and the classic auction house)
---------------------------------------------------------------------------

local itemNext

local function itemDone(id)
    if current ~= id then return end
    current = nil
    C_Timer.After(0.1, itemNext)
end

itemNext = function()
    if not scanning or phase ~= "items" then return end
    if not ahOpen() then return stop("Scan stopped because the auction house closed.") end
    if current then return end
    if not throttleReady() then
        C_Timer.After(0.1, itemNext)
        return
    end
    local id = table.remove(queue, 1)
    if not id then return finish() end
    local modern = modernAH()
    local name = (GetItemInfo and GetItemInfo(id)) or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
    if not modern and not name then return itemNext() end -- the classic search needs the name
    current = id
    local n = total - #queue
    progress("Scanning " .. n .. "/" .. total .. (name and (": " .. name) or ""))
    if scanButton then scanButton:SetLabel(math.floor(n / total * 100) .. "%") end
    if modern then
        C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(id), sorts(), false)
    else
        QueryAuctionItems(name, nil, nil, 0, false, nil, false, true)
    end
    C_Timer.After(ITEM_TIMEOUT, function() itemDone(id) end)
end

local function startItems(list)
    phase, queue, current = "items", {}, nil
    for _, id in ipairs(list) do
        if not seen[id] then table.insert(queue, id) end
    end
    total = #queue
    if total == 0 then return finish() end
    itemNext()
end

---------------------------------------------------------------------------
-- Phases 1 and 2: browse searches that return many items per page
---------------------------------------------------------------------------

local startKeys

-- Gives up on a browse search that stops sending pages.
local function watchdog(myRun, myPhase, lastPages)
    C_Timer.After(PAGE_TIMEOUT, function()
        if not scanning or run ~= myRun or phase ~= myPhase then return end
        if pages ~= lastPages then return watchdog(myRun, myPhase, pages) end
        if myPhase == "browse" then
            startKeys()
        else
            startItems(scanList)
        end
    end)
end

local function readBrowse()
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if ok and results then
        for _, r in ipairs(results) do
            local id = r.itemKey and r.itemKey.itemID
            if id and r.minPrice and r.minPrice > 0 then store(id, r.minPrice, r.totalQuantity) end
        end
    end
    pages = pages + 1
    if phase == "browse" then
        progress("Trade Goods: " .. found .. " items so far")
        if scanButton then scanButton:SetLabel(found .. " items") end
    end
    if C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() then
        if C_AuctionHouse.RequestMoreBrowseResults then C_AuctionHouse.RequestMoreBrowseResults() end
        return
    end
    if phase == "browse" then startKeys() else C_Timer.After(0.1, startKeys) end
end

-- Phase 2: items the Trade Goods browse didn't cover, KEY_CHUNK per search.
local function sendChunk()
    if not scanning then return end
    local chunk = table.remove(keyChunks, 1)
    if not chunk then return finish() end
    if not throttleReady() then
        table.insert(keyChunks, 1, chunk)
        C_Timer.After(0.2, sendChunk)
        return
    end
    phase = "keys"
    run = run + 1
    local keys = {}
    for _, id in ipairs(chunk) do table.insert(keys, C_AuctionHouse.MakeItemKey(id)) end
    local done = keysTotal - #keyChunks * KEY_CHUNK
    progress("Looking up items: " .. math.min(done, keysTotal) .. "/" .. keysTotal)
    if scanButton then scanButton:SetLabel(math.floor(math.min(done, keysTotal) / keysTotal * 100) .. "%") end
    if not pcall(C_AuctionHouse.SearchForItemKeys, keys, sorts()) then return startItems(scanList) end
    watchdog(run, "keys", pages)
end

startKeys = function()
    if not scanning then return end
    if phase ~= "keys" then
        -- First time here: split what's still missing into chunks.
        local missing = {}
        for _, id in ipairs(scanList) do
            if not seen[id] then table.insert(missing, id) end
        end
        if #missing == 0 then return finish() end
        if not C_AuctionHouse.SearchForItemKeys then return startItems(missing) end
        keyChunks, keysTotal = {}, #missing
        for i = 1, #missing, KEY_CHUNK do
            local c = {}
            for j = i, math.min(i + KEY_CHUNK - 1, #missing) do table.insert(c, missing[j]) end
            table.insert(keyChunks, c)
        end
    end
    sendChunk()
end

local function startBrowse()
    if not scanning then return end
    if not throttleReady() then
        C_Timer.After(0.2, startBrowse)
        return
    end
    phase = "browse"
    run = run + 1
    progress("Scanning Trade Goods")
    if scanButton then scanButton:SetLabel("Scanning...") end
    local query = {
        searchString = "",
        sorts = sorts(),
        filters = {},
        itemClassFilters = { { classID = TRADE_GOODS } },
    }
    if not pcall(C_AuctionHouse.SendBrowseQuery, query) then return startKeys() end
    watchdog(run, "browse", pages)
end

---------------------------------------------------------------------------
-- Starting a scan
---------------------------------------------------------------------------

function API.IsScanning() return scanning or (ns.DeepRunning and ns.DeepRunning()) or false end

-- Scan(): Trade Goods plus watched items (/sk material; QuickScan adds the scan providers' items).
-- Scan({ items = { itemID, ... } }): the same, plus these items. Market King
-- uses this for crafted items and everything that goes into them.
-- opts.kind names the scan in SCAN_RESULTS ("material" unless given; QuickScan and MarketScan pass "market" with a provider's items).
function API.Scan(opts)
    if not ns.db then return end
    local extra = type(opts) == "table" and type(opts.items) == "table" and opts.items or nil
    if not ahOpen() then
        KM.Print(ns, "Open the auction house first, then click Scan or type /sk scan.")
        return
    end
    if API.IsScanning() then
        KM.Print(ns, "A scan is already running.")
        return
    end
    kind = type(opts) == "table" and opts.kind or "material"
    if not scanButton and ns.ahParent and buttons[ns.ahParent] then scanButton = buttons[ns.ahParent].scan end
    scanning, found, seen, pages, phase = true, 0, {}, 0, nil
    scanList = ns.WatchedItems()
    if extra then
        local have = {}
        for _, id in ipairs(scanList) do have[id] = true end
        for _, id in ipairs(extra) do
            if not have[id] then have[id] = true; table.insert(scanList, id) end
        end
    end
    if scanButton then scanButton:SetEnabled2(false) end
    ns.Fire("SCAN_STARTED")
    if modernAH() and C_AuctionHouse.SendBrowseQuery then
        KM.Print(ns, "Scanning every Trade Goods item. Keep the auction house open.")
        startBrowse()
    else
        KM.Print(ns, "Scanning " .. #scanList .. " items one at a time. Keep the auction house open.")
        startItems(scanList)
    end
end

---------------------------------------------------------------------------
-- The one scan: full when the game allows it, quick otherwise
---------------------------------------------------------------------------

-- What a click on Scan does right now: "full", "quick", or nil when the auction house isn't open.
function ns.ScanMode()
    if not ahOpen() then return nil end
    local wait = ns.FullScanWait and ns.FullScanWait()
    if wait == 0 and modernAH() then return "full" end
    return "quick"
end

-- The merged scan (the Scan button, /sk scan, the crown's Scan, Crafting Profits' Scan).
function API.SmartScan()
    if not ns.db then return end
    if not ahOpen() then
        KM.Print(ns, "Open the auction house first, then click Scan or type /sk scan.")
        return
    end
    if API.IsScanning() then
        KM.Print(ns, "A scan is already running.")
        return
    end
    if ns.ScanMode() == "full" then return API.DeepScan() end
    return API.QuickScan()
end

-- The text of the last SCAN_PROGRESS (quick or full scan), for tooltips.
function ns.LastProgress() return lastProgress end

-- The Scan button's tooltip (title bar and Prices page): what a click does right now, and when the last scans ran.
function ns.ScanTooltip(tt)
    tt:AddLine("Scan")
    local mode = ns.ScanMode()
    if API.IsScanning() then
        tt:AddLine(lastProgress ~= "" and lastProgress or "Scanning...", 0.4, 1, 0.4)
        tt:AddLine("Keep the auction house open until it's done.", 1, 1, 1, true)
    elseif not mode then
        tt:AddLine("Open the auction house to scan.", 1, 1, 1, true)
    elseif mode == "full" then
        tt:AddLine("Full scan ready: a click downloads every auction on the auction house.", 0.4, 1, 0.4, true)
        tt:AddLine("Market price, lowest buyout and how many are listed, for every item. About a minute. "
            .. "The game allows one every 15 minutes; in between, a click does a quick scan.", 1, 1, 1, true)
    else
        local plan = ns.QuickPlan()
        local wait = ns.FullScanWait and ns.FullScanWait()
        local what = "a quick scan of Trade Goods plus " .. KM.Commas(plan.total) .. " items"
        if wait then
            tt:AddLine("Full scan ready in " .. math.max(1, math.ceil(wait / 60)) .. " min; a click now does " .. what .. ".",
                1, 0.82, 0, true)
        else
            tt:AddLine("A click does " .. what .. ".", 1, 0.82, 0, true)
        end
        local parts = { "every Trade Goods item" }
        if plan.watched > 0 then table.insert(parts, KM.Commas(plan.watched) .. " watched by other pages") end
        if plan.prof > 0 then
            table.insert(parts, KM.Commas(plan.prof) .. " more for the " .. plan.profs .. " profession(s) ticked on Crafting Profits")
        end
        tt:AddLine("Quick scan: " .. table.concat(parts, ", ") .. ". Lowest prices only.", 1, 1, 1, true)
    end
    local db = ns.db
    tt:AddLine("Last full scan: " .. (db.lastDeep and API.PriceAge(db.lastDeep) or "never")
        .. ".  Last quick scan: " .. (db.lastQuick and API.PriceAge(db.lastQuick) or "never") .. ".", 0.7, 0.7, 0.7, true)
end

---------------------------------------------------------------------------
-- The button on the auction house window
---------------------------------------------------------------------------

-- One gold "primary" button in the auction house title bar. b.caption is its resting label; while a scan
-- runs (quick or full) the label shows its progress, and the tooltip says what a click will do right now.
local function createButton()
    local parent, x, y
    if modernAH() then
        parent, x, y = AuctionHouseFrame, -60, -1
    elseif classicAH() then
        parent, x, y = AuctionFrame, -40, -12
    else
        return false
    end
    if not buttons[parent] then
        local b = UI.Button(parent, "Scan", 130, 22, function(self) scanButton = self; API.SmartScan() end, "primary")
        b.caption = "Scan"
        b:SetFrameStrata("HIGH")
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            ns.ScanTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[parent] = { scan = b }
    end
    ns.ahParent = parent
    return true
end
ns.SetScanButton = function(b) scanButton = b end
-- The title-bar Scan button of the open auction house (nil until one has opened).
ns.ScanButton = function() return ns.ahParent and buttons[ns.ahParent] and buttons[ns.ahParent].scan end
ns.DeepButton = ns.ScanButton -- a full scan shows its progress on the same button
ns.TitleButtons = function() return ns.ahParent and buttons[ns.ahParent] end

local hinted = false
local function onShow()
    local ok, made = pcall(createButton)
    if ok and made then
        -- buttons are ready
    elseif not hinted then
        hinted = true
        KM.Print(ns, "Type /sk scan to scan prices.")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
-- Each client only knows the events of its own auction house, and registering
-- an unknown one is an error, so skip any this client doesn't have.
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ADDON_LOADED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        pcall(f.RegisterEvent, f, event)
    end
end
f:SetScript("OnEvent", function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        -- The game loads the auction house window in response to this same event.
        C_Timer.After(0, onShow)
        C_Timer.After(0.5, onShow)
    elseif event == "ADDON_LOADED" then
        if arg == "Blizzard_AuctionHouseUI" or arg == "Blizzard_AuctionUI" then C_Timer.After(0, onShow) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        stop("Scan stopped because the auction house closed.")
    elseif not scanning then
        return
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if phase == "browse" or phase == "keys" then readBrowse() end
    elseif phase ~= "items" or not current then
        return
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if arg ~= current then return end
        local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, current, 1)
        if ok and info then store(current, info.unitPrice, info.quantity) end
        itemDone(current)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if not arg or arg.itemID ~= current then return end
        local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, arg, 1)
        if ok and info and info.buyoutAmount then store(current, info.buyoutAmount, info.quantity) end
        itemDone(current)
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        local best, rows = nil, (GetNumAuctionItems("list")) or 0
        for i = 1, rows do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = GetAuctionItemInfo("list", i)
            if id == current and buyout and buyout > 0 and (count or 0) > 0 then
                local unit = buyout / count
                if not best or unit < best then best = unit end
            end
        end
        if best then store(current, math.floor(best + 0.5)) end
        if best or rows == 0 then itemDone(current) end -- otherwise the rows are still loading
    end
end)
