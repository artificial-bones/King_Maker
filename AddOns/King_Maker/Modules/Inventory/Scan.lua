local _, KM = ...
local ns = KM.Module("Inventory")

-- Reading what each character owns, where it is:
--   bags   whenever your bags change (and at login)
--   bank   when you open the bank: the game only lets addons read it then
--   mail   items attached to mail in your mailbox, and the gold waiting there
--   ah     your auctions still up, whenever the auction house lists them
--   gold   whenever it changes
-- The warband bank is shared, so it's kept once under "Warband".
-- Soulbound items are left out: they can't be sold, so they aren't worth anything.

local WARBAND = ns.WARBAND
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
ns.PLACES = { "bags", "bank", "mail", "ah" }
ns.PLACE_NAMES = { bags = "Bags", bank = "Bank", mail = "Mailbox", ah = "On the auction house" }

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
            local i = C_Container.GetContainerItemInfo(bag, slot)
            if i and i.itemID and not i.isBound then
                out[i.itemID] = (out[i.itemID] or 0) + (i.stackCount or 1)
            end
        end
    end
    return out
end

local function note(who, place, items)
    local s = stockOf(who)
    s[place], s[place .. "T"] = items, ns.Now()
end

-- This character: class, level, faction, when last seen.
function ns.NoteChar()
    if not ns.db then return end
    local who = ns.Char()
    local c = ns.db.chars[who] or {}
    ns.db.chars[who] = c
    if UnitClass then c.class = select(2, UnitClass("player")) or c.class end
    c.level = UnitLevel and UnitLevel("player") or c.level
    c.faction = UnitFactionGroup and UnitFactionGroup("player") or c.faction
    c.seen = ns.Now()
    if GetMoney then c.gold, c.goldT = GetMoney(), ns.Now() end
    return c
end

function ns.ReadBags()
    if not ns.db then return end
    note(ns.Char(), "bags", read((bagIDs())))
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

-- Items attached to mail in the mailbox, and gold waiting there (not COD: that's money you'd pay).
function ns.ReadMail()
    if not (ns.db and GetInboxNumItems and GetInboxHeaderInfo) then return end
    local out, money = {}, 0
    for i = 1, GetInboxNumItems() or 0 do
        local _, _, _, _, m, cod = GetInboxHeaderInfo(i)
        if not cod or cod == 0 then
            money = money + (m or 0)
            for a = 1, ATTACHMENTS do
                local _, id, _, count = GetInboxItem(i, a)
                if id then out[id] = (out[id] or 0) + (count or 1) end
            end
        end
    end
    note(ns.Char(), "mail", out)
    local c = ns.NoteChar()
    c.mail, c.mailT = money, ns.Now()
end

-- Your auctions still up (sold ones are on their way as gold).
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

-- When this character's places were last seen: { bags = t, bank = t, mail = t, ah = t }.
function ns.Seen(who)
    local s = ns.db.stock[who or ns.Char()] or {}
    return { bags = s.bagsT, bank = s.bankT, mail = s.mailT, ah = s.ahT }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED", "OWNED_AUCTIONS_UPDATED",
    "MAIL_SHOW", "MAIL_INBOX_UPDATE", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end

-- Bags change in bursts (looting, selling, moving a stack): read once it settles.
local waiting = {}
local function soon(key, fn)
    if waiting[key] then return end
    waiting[key] = true
    C_Timer.After(0.5, function()
        waiting[key] = nil
        fn()
        if ns.Snapshot then ns.Snapshot() end
        if ns.Refresh then ns.Refresh() end
    end)
end
local function isBanker(kind)
    local P = Enum and Enum.PlayerInteractionType
    return P and kind and (kind == P.Banker or kind == P.AccountBanker)
end
local function bags() ns.ReadBags(); ns.ReadBank() end

f:SetScript("OnEvent", function(_, event, arg)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        ns.NoteChar()
        soon("bags", bags)
    elseif event == "PLAYER_MONEY" or event == "PLAYER_LEVEL_UP" then
        soon("char", ns.NoteChar)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if isBanker(arg) then bankOpen = true; soon("bags", bags) end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if isBanker(arg) then bankOpen = false end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ns.ReadBank()
        if ns.Snapshot then ns.Snapshot() end
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        soon("ah", ns.ReadAuctions)
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        soon("mail", ns.ReadMail)
    else
        soon("bags", bags)
    end
end)
