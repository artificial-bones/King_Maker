local _, ns = ...
local API = ns.API

-- Scanning the auction house.
--
-- On the modern auction house a full scan is a handful of requests:
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

local lastProgress = ""
local function progress(text)
    lastProgress = text or ""
    ns.Fire("SCAN_PROGRESS", text)
end

local function sorts()
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

---------------------------------------------------------------------------
-- Finishing
---------------------------------------------------------------------------

local function resetButton()
    if scanButton then scanButton:Enable(); scanButton:SetText(scanButton.label or "Material Scan") end
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
    resetButton()
    progress("Scan done: " .. found .. " prices")
    ns.Print("Scan done: " .. found .. " items priced.")
    ns.Fire("SCAN_RESULTS", results(), kind)
    ns.Fire("SCAN_FINISHED", found)
    ns.Fire("PRICES_UPDATED")
    if found > 0 and ns.SharePrices then ns.SharePrices() end
end

local function stop(reason)
    if not scanning then return end
    scanning, phase, current = false, nil, nil
    resetButton()
    ns.Print(reason)
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
    if scanButton then scanButton:SetText(math.floor(n / total * 100) .. "%") end
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
        if scanButton then scanButton:SetText(found .. " items") end
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
    if scanButton then scanButton:SetText(math.floor(math.min(done, keysTotal) / keysTotal * 100) .. "%") end
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
    if scanButton then scanButton:SetText("Scanning...") end
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

-- Scan(): Trade Goods plus watched items (the scan button and /sk scan).
-- Scan({ items = { itemID, ... } }): the same, plus these items. Market King
-- uses this for crafted items and everything that goes into them.
-- opts.kind names the scan in SCAN_RESULTS ("material" unless given; Market Scan passes "market").
function API.Scan(opts)
    if not ns.db then return end
    local extra = type(opts) == "table" and type(opts.items) == "table" and opts.items or nil
    if not ahOpen() then
        ns.Print("Open the auction house first, then click Material Scan or type /sk scan.")
        return
    end
    if API.IsScanning() then return end
    kind = type(opts) == "table" and opts.kind or "material"
    if not scanButton and ns.ahParent and buttons[ns.ahParent] then scanButton = buttons[ns.ahParent].mat end
    scanning, found, seen, pages, phase = true, 0, {}, 0, nil
    scanList = ns.WatchedItems()
    if extra then
        local have = {}
        for _, id in ipairs(scanList) do have[id] = true end
        for _, id in ipairs(extra) do
            if not have[id] then have[id] = true; table.insert(scanList, id) end
        end
    end
    if scanButton then scanButton:Disable() end
    ns.Fire("SCAN_STARTED")
    if modernAH() and C_AuctionHouse.SendBrowseQuery then
        ns.Print("Scanning every Trade Goods item. Keep the auction house open.")
        startBrowse()
    else
        ns.Print("Scanning " .. #scanList .. " items one at a time. Keep the auction house open.")
        startItems(scanList)
    end
end

---------------------------------------------------------------------------
-- The button on the auction house window
---------------------------------------------------------------------------

-- Three buttons in the auction house title bar:
--   Material Scan: Trade Goods plus watched items (the quick, raw-materials scan).
--   Market Scan:   opens a picker from an addon that registered one (Market King's
--                  professions), then scans everything it needs.
--   Deep Scan:     the whole auction house, every item (DeepScan.lua).

local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(self.label)
    GameTooltip:AddLine(self.help, 1, 1, 1, true)
    if scanning and lastProgress ~= "" then
        GameTooltip:AddLine(lastProgress, 0.4, 1, 0.4)
    elseif self.deep and ns.db.lastDeep then
        GameTooltip:AddLine("Last Deep Scan " .. API.PriceAge(ns.db.lastDeep), 0.7, 0.7, 0.7)
    elseif ns.db.lastScan then
        GameTooltip:AddLine("Last scan " .. API.PriceAge(ns.db.lastScan), 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function titleButton(parent, label, width, help, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b.label, b.help = label, help
    b:SetText(label)
    b:SetFrameStrata("HIGH")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

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
        local mat, market
        mat = titleButton(parent, "Material Scan", 120,
            "Prices every Trade Goods item: ores, herbs, leather, cloth, enchanting materials and more.",
            function() scanButton = mat; API.Scan() end)
        mat:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)
        market = titleButton(parent, "Market Scan", 110,
            "Pick professions and price everything they make and use. Needs Market King.",
            function() ns.ToggleMarketScan(parent) end)
        market:SetPoint("RIGHT", mat, "LEFT", -4, 0)
        local deep = titleButton(parent, "Deep Scan", 100,
            "Prices every item on the auction house: market price, lowest buyout and how many are listed. "
            .. "Shows in item tooltips, and Econ King keeps the history.",
            function() ns.ToggleDeepScan(parent) end)
        deep.deep = true
        deep:SetPoint("RIGHT", market, "LEFT", -4, 0)
        buttons[parent] = { mat = mat, market = market, deep = deep }
    end
    buttons[parent].market:SetShown(ns.HasScanProvider())
    ns.ahParent = parent
    return true
end
ns.SetScanButton = function(b) scanButton = b end
ns.MarketButton = function() return ns.ahParent and buttons[ns.ahParent] and buttons[ns.ahParent].market end
ns.DeepButton = function() return ns.ahParent and buttons[ns.ahParent] and buttons[ns.ahParent].deep end

local hinted = false
local function onShow()
    local ok, made = pcall(createButton)
    if ok and made then
        -- buttons are ready
    elseif not hinted then
        hinted = true
        ns.Print("Type /sk scan to scan prices.")
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
