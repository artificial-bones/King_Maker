local _, ns = ...

-- Prices come from Scanner King, the suite's auction house scanner, when it's
-- installed (Auctionator fills in otherwise). Gather King tells Scanner King
-- which items it cares about, so a scan always covers every ore, herb, skin,
-- cloth and enchanting material even if they aren't listed as Trade Goods.

local function SK() return ScannerKing and ScannerKing.API_VERSION and ScannerKing end

-- Returns copper each and when it was scanned (nil for Auctionator prices).
function ns.Price(itemID)
    if not itemID then return nil end
    if SK() then
        local p, t = SK().GetPrice(itemID)
        return p, t
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, copper = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "gather_king", itemID)
        if ok and copper and copper > 0 then return copper, nil end
    end
    return nil
end

function ns.FormatMoney(copper)
    if SK() then return SK().FormatMoney(copper) end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, "|cffffd700" .. g .. "g|r") end
    if s > 0 then table.insert(parts, "|cffc7c7cf" .. s .. "s|r") end
    if c > 0 or #parts == 0 then table.insert(parts, "|cffeda55f" .. c .. "c|r") end
    return table.concat(parts, " ")
end

function ns.PriceAge(t)
    if SK() then return SK().PriceAge(t) end
    if not t then return "Auctionator" end
    local now = GetServerTime and GetServerTime() or time()
    local mins = math.max(0, math.floor((now - t) / 60))
    if mins < 60 then return mins .. " min ago" end
    if mins < 60 * 48 then return math.floor(mins / 60) .. " h ago" end
    return math.floor(mins / 1440) .. " days ago"
end

function ns.ScanPrices()
    if SK() then return SK().Scan() end
    ns.Print("Price scanning lives in the Scanner King addon now. Install it next to Gather King to scan prices.")
end

-- Every material Gather King shows a price for.
function ns.PricedItems()
    local seen, list = {}, {}
    local function add(id) if id and not seen[id] then seen[id] = true; table.insert(list, id) end end
    for _, t in ipairs(ns.MAT_TABS) do
        for _, id in ipairs(ns.MaterialList(t.key)) do add(id) end
    end
    for id in pairs(ns.db.itemNames) do add(id) end -- anything looted from a node
    return list
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not SK() then return end
    -- Prices scanned by Gather King before Scanner King existed move over once.
    if ns.db.prices then
        for id, pr in pairs(ns.db.prices) do
            if pr.p and pr.t then SK().MergePrice(id, pr.p, pr.t, pr.from) end
        end
        ns.db.prices, ns.db.pricesScanned = nil, nil
    end
    SK().Watch("gather_king", ns.PricedItems) -- asked fresh at each scan
    SK().RegisterCallback("gather_king", function(event)
        if event == "PRICES_UPDATED" and ns.UpdateLedger then ns.UpdateLedger() end
    end)
end)
