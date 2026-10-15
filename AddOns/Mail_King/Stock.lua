local _, ns = ...
local API = ns.API

-- Stock: what you're sitting on, on every character, and what it's worth.
--
-- Each character's items are noted where they are:
--   bags   whenever your bags change
--   bank   when you open the bank (it can't be read anywhere else)
--   mail   items still attached to mail in your mailbox
--   ah     your auctions still up, when the auction house lists them
-- The warband bank is shared, so it's kept once under "Warband".
-- Soulbound items are left out: they can't be sold.
-- Worth is Scanner King's market price today.

local WARBAND = "Warband"
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
ns.PLACES = { "bags", "bank", "mail", "ah" }

local function bagIDs()
    local bags, bank, warband, seen = {}, {}, {}, {}
    local function add(t, id) if id and not seen[id] then seen[id] = true; table.insert(t, id) end end
    for id = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do add(bags, id) end
    local E = Enum and Enum.BagIndex
    if E then
        for name, id in pairs(E) do
            if type(id) == "number" then
                if name:find("^AccountBankTab") then add(warband, id)
                elseif name == "Bank" or name == "Reagentbank" or name:find("^BankBag") or name:find("^CharacterBankTab") then add(bank, id) end
            end
        end
    else
        add(bank, BANK_CONTAINER or -1)
        local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
        for id = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(bank, id) end
    end
    return bags, bank, warband
end

local function stockOf(who)
    local s = ns.db.stock[who]
    if not s then s = {}; ns.db.stock[who] = s end
    return s
end

local function read(ids)
    local out = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    for _, bag in ipairs(ids) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return out
end

local function note(who, place, items)
    local s = stockOf(who)
    s[place], s[place .. "T"] = items, ns.Now()
end

function ns.ReadBags()
    if not ns.db then return end
    local bags = bagIDs()
    note(ns.Char(), "bags", read(bags))
end

local bankOpen = false
function ns.ReadBank()
    if not ns.db or not bankOpen then return end
    local _, bank, warband = bagIDs()
    note(ns.Char(), "bank", read(bank))
    if #warband > 0 then
        local w = read(warband)
        -- The warband bank reads empty until its tab has loaded: keep what was seen before.
        if next(w) or not ns.db.stock[WARBAND] then note(WARBAND, "bank", w) end
    end
end

-- Items still attached to mail in the mailbox (called with each inbox read).
function ns.ReadMailItems()
    if not (ns.db and GetInboxNumItems and GetInboxItem) then return end
    local out = {}
    for i = 1, GetInboxNumItems() or 0 do
        local _, _, _, _, _, cod = GetInboxHeaderInfo(i)
        if not cod or cod == 0 then
            for a = 1, ATTACHMENTS do
                local name, id, _, count = GetInboxItem(i, a)
                if id then
                    ns.LearnItem(name, id)
                    out[id] = (out[id] or 0) + (count or 1)
                end
            end
        end
    end
    note(ns.Char(), "mail", out)
end

-- Your auctions still up.
function ns.ReadAuctions()
    if not (ns.db and C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return end
    local out = {}
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
        local id = a and a.itemKey and a.itemKey.itemID
        if id and (a.status or 0) == 0 then out[id] = (out[id] or 0) + (a.quantity or 1) end
    end
    note(ns.Char(), "ah", out)
end

local function price(id)
    if not ScannerKing then return nil end
    local p = ScannerKing.GetMarketPrice and ScannerKing.GetMarketPrice(id)
    if not p and ScannerKing.GetPrice then p = ScannerKing.GetPrice(id) end
    return p
end

-- onlyChar: "Name-Realm", or nil for everyone (the warband bank included).
-- Returns { value, count, priced, items = { { item, total, bags, bank, mail, ah, chars = { who = n },
--   each, value, strategy } } (most valuable first) }.
function ns.Stock(onlyChar)
    local byItem, out = {}, { value = 0, count = 0, items = {} }
    for who, s in pairs(ns.db.stock) do
        if not onlyChar or who == onlyChar then
            for _, place in ipairs(ns.PLACES) do
                for id, n in pairs(s[place] or {}) do
                    local r = byItem[id]
                    if not r then
                        r = { item = id, total = 0, bags = 0, bank = 0, mail = 0, ah = 0, chars = {} }
                        byItem[id] = r
                    end
                    r[place], r.total = r[place] + n, r.total + n
                    r.chars[who] = (r.chars[who] or 0) + n
                end
            end
        end
    end
    for id, r in pairs(byItem) do
        r.each = price(id)
        r.value = r.each and r.each * r.total or nil
        r.strategy = ns.ItemStrategy(id)
        out.count = out.count + r.total
        out.value = out.value + (r.value or 0)
        table.insert(out.items, r)
    end
    table.sort(out.items, function(a, b)
        if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
        return a.item < b.item
    end)
    return out
end

-- When this character's places were last seen: { bags = t, bank = t, mail = t, ah = t }.
function ns.StockSeen(who)
    local s = ns.db.stock[who or ns.Char()] or {}
    return { bags = s.bagsT, bank = s.bankT, mail = s.mailT, ah = s.ahT }
end

function API.Stock(itemID)
    local total = 0
    for _, s in pairs(ns.db and ns.db.stock or {}) do
        for _, place in ipairs(ns.PLACES) do total = total + ((s[place] or {})[itemID] or 0) end
    end
    return total
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED", "OWNED_AUCTIONS_UPDATED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end
local pending = false
local function soon(fn)
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; fn() end)
end
local function isBanker(kind)
    local P = Enum and Enum.PlayerInteractionType
    return P and kind and (kind == P.Banker or kind == P.AccountBanker)
end
f:SetScript("OnEvent", function(_, event, arg)
    if not ns.db then return end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if isBanker(arg) then bankOpen = true; soon(ns.ReadBank) end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if isBanker(arg) then bankOpen = false end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ns.ReadBank()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        ns.ReadAuctions()
    else
        soon(function() ns.ReadBags(); ns.ReadBank(); if ns.Refresh then ns.Refresh() end end)
    end
end)
