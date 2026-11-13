local _, KM = ...
local ns = KM.Module("Inventory")

-- The cheapest thing in your bags: the stack you lose least by deleting when you need the space. It always has a
-- red X in the bottom-left corner of its bag slot (Bagnon or the game's own bags) and a line in its tooltip.
--
-- A stack is worth what you could get for it: the vendor price or the auction house price after the 5% cut,
-- whichever is more (soulbound: the vendor price only), times how many are in it.
-- Never marked: quest items and keys, profession tools, anything with no price at all (a Hearthstone, a quest
-- drop: we can't tell what it's worth to you), and items you've told it to keep (/ik keep <item>).
--
-- Only decorates the bag buttons; it never touches the items. /ik cheapest off turns it off.

ns.CUT = 0.05
-- Tools a profession needs in your bags, which a vendor values at next to nothing.
ns.TOOLS = {
    [7005] = true,  -- Skinning Knife
    [2901] = true,  -- Mining Pick
    [5956] = true,  -- Blacksmith Hammer
    [6219] = true,  -- Arclight Spanner
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- enchanting rods
    [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true, [19022] = true, [19970] = true, -- fishing poles
    [4471] = true,  -- Flint and Tinder
    [5060] = true,  -- Thieves' Tools
    [6948] = true,  -- Hearthstone
}
local SKIP_CLASS = { [12] = true, [13] = true } -- Quest, Key

local cheapest -- { bag, slot, item, count, each, value } or nil

local function bagIDs()
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local out = {}
    for b = 0, last do out[#out + 1] = b end
    return out
end

-- Copper each you'd get for an item in this slot, or nil when it has no price or must never be marked.
function ns.DeleteValue(info, bag, slot)
    local id = info and info.itemID
    if not id or ns.TOOLS[id] or (ns.db.ui.keepCheap and ns.db.ui.keepCheap[id]) then return nil end
    if SKIP_CLASS[(ns.ClassOf(id))] then return nil end
    if C_Container.GetContainerItemQuestInfo then
        local q = C_Container.GetContainerItemQuestInfo(bag, slot)
        if q and (q.isQuestItem or q.questID) then return nil end
    end
    local _, _, sell = ns.ItemInfo(id)
    local vendor = (not info.hasNoValue and sell and sell > 0) and sell or 0
    local ah = 0
    if not info.isBound and ScannerKing then
        local p = ScannerKing.GetMarketPrice and ScannerKing.GetMarketPrice(id)
        if not p and ScannerKing.GetPrice then p = ScannerKing.GetPrice(id) end
        if p then ah = math.floor(p * (1 - ns.CUT)) end
    end
    local each = math.max(vendor, ah)
    if each <= 0 then return nil end
    return each
end

-- Works out the cheapest stack in your bags (nil when there's nothing that can be marked).
function ns.FindCheapest()
    local best
    for _, bag in ipairs(bagIDs()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local each = info and ns.DeleteValue(info, bag, slot)
            if each then
                local count = info.stackCount or 1
                local v = each * count
                if not best or v < best.value or (v == best.value and (info.quality or 1) < best.quality) then
                    best = { bag = bag, slot = slot, item = info.itemID, count = count, each = each, value = v, quality = info.quality or 1 }
                end
            end
        end
    end
    return best
end

function ns.Cheapest() return cheapest end

---------------------------------------------------------------------------
-- The mark on the bag button
---------------------------------------------------------------------------

ns.MARK = "Interface/RaidFrame/ReadyCheck-NotReady" -- a red X, bottom left (top left is Quest's X: a quest item you can delete)

local marked = setmetatable({}, { __mode = "k" }) -- buttons we've put a mark on

local function setMark(b, on)
    if on and not b.kmCheap then
        local t = b:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(ns.MARK)
        t:SetSize(16, 16)
        t:SetPoint("BOTTOMLEFT", 1, 1)
        b.kmCheap = t
    end
    if b.kmCheap then b.kmCheap:SetShown(on and true or false) end
    marked[b] = on or nil
end

-- Puts the mark on the cheapest stack's button and takes it off every other.
function ns.MarkCheapest()
    for b in pairs(marked) do setMark(b, false) end
    ns.markedCount = 0
    if not (ns.db and ns.db.ui.cheapest and cheapest) then return end
    KM.EachBagButton(function(b, bag, slot)
        if bag == cheapest.bag and slot == cheapest.slot and not (b.IsShown and not b:IsShown()) then
            setMark(b, true)
            ns.markedCount = ns.markedCount + 1
        end
    end)
end
KM.RegisterBagMarker(function() if cheapest then ns.MarkCheapest() end end)

function ns.UpdateCheapest()
    if not ns.db then return end
    cheapest = ns.db.ui.cheapest and ns.FindCheapest() or nil
    KM.Safe(ns.MarkCheapest)
end

-- A line in the marked item's tooltip.
function ns.CheapestTooltip(tt, id)
    if not (ns.db and ns.db.ui.cheapest and cheapest and cheapest.item == id and tt) then return end
    tt:AddLine("|T" .. ns.MARK .. ":12:12|t Cheapest thing in your bags: " .. ns.Money(cheapest.value)
        .. (cheapest.count > 1 and (" for " .. cheapest.count) or ""), 1, 0.45, 0.45)
end

---------------------------------------------------------------------------
-- Keeping it current
---------------------------------------------------------------------------

local pending
local function soon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = nil; ns.UpdateCheapest() end)
end
ns.SoonCheapest = soon

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if ScannerKing and ScannerKing.RegisterCallback then
            ScannerKing.RegisterCallback("Inventory_Cheapest", function(e) if e == "PRICES_UPDATED" then soon() end end)
        end
    end
    soon()
end)

-- /ik keep <item>: never mark this item (again to allow it).
function ns.ToggleKeep(id)
    ns.db.ui.keepCheap = ns.db.ui.keepCheap or {}
    ns.db.ui.keepCheap[id] = (not ns.db.ui.keepCheap[id]) or nil
    ns.UpdateCheapest()
    return ns.db.ui.keepCheap[id] and true or false
end
