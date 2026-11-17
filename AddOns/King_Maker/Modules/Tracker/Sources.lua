local _, KM = ...
local ns = KM.Module("Tracker")

-- Where a session's money comes from. Loot windows come from Core\Loot.lua (KM.OnLoot): every slot you actually
-- take is credited to the corpse, node, chest or box it came from. Coin counts as the money that actually arrived
-- (PLAYER_MONEY while the window is open, until 1.5 s after it closes); the coin slots only say which mob it came
-- from, so in a group your share is what counts. Money that isn't loot is filed by what you have open: a vendor
-- (sales, purchases, repairs), mail, the auction house, trade, a flight master, a trainer, the bank; quest rewards
-- by QUEST_TURNED_IN; a gain with nothing open while grouped is a party coin share. Group loot you win on a roll, and
-- master loot handed to you, arrive later as KM.OnLoot "won" (2.7.0): credited to the corpse once they reach your bags.
--
-- Containers (2.6.2): when a box window opens, the bag counts of everything in the session are noted; half a second
-- after it closes (or on BAG_UPDATE_DELAYED) the item that went down by one is the container you opened. If it was
-- looted in this session, ns.Unbox swaps it out, so a clam or a junkbox isn't counted once whole and again for what
-- was inside. A container from before the session simply adds its contents. (C_Item.GetItemIDByGUID would say which
-- item it was, but it's restricted to untainted code, so it isn't relied on.)

local plain = KM.Plain

local lootWin          -- the open loot window (money gained while it's open is its coin)
local settlingWin      -- the last closed one, until its coin has settled
local corpses = {}     -- creature GUID -> true: looted this login (a corpse counts once)
local lastMoney
local ctx              -- { kind, closedAt }: what you have open
local quest            -- { at, money } from QUEST_TURNED_IN
local lastOther        -- { d, at }: money just filed as "other" (a quest reward that came first)
local repairBefore     -- GetRepairAllCost() at the merchant
local lastBuy          -- { d, at, before }: a purchase that may turn out to be a repair
local swap             -- { w, counts = { [itemID] = n in bags }, closed }: a box window being watched

---------------------------------------------------------------------------
-- Loot windows
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Containers swapped for their contents
---------------------------------------------------------------------------

local function bagCount(id)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not get then return nil end
    local ok, n = pcall(get, id)
    return ok and tonumber(plain(n)) or nil
end

local function watchBox(w)
    local s = ns.Live()
    if not s then swap = nil return end
    local counts, any = {}, false
    for id, it in pairs(s.items) do
        if (it.q or 0) > 0 then
            local n = bagCount(id)
            if n then counts[id], any = n, true end
        end
    end
    swap = any and { w = w, counts = counts } or nil
end

-- The one item that went down by exactly one (a Miscellaneous one, the class containers are, when several did).
local function checkSwap(try)
    local sw = swap
    if not sw or not sw.closed then return end
    local found = {}
    for id, before in pairs(sw.counts) do
        local now = bagCount(id)
        if now and before - now == 1 then found[#found + 1] = id end
    end
    if #found == 0 then
        -- try 1: half a second after the close; 2: two seconds after (bags can lag); 0: a bag update in between
        if try == 1 then C_Timer.After(1.5, function() if swap == sw then KM.Safe(checkSwap, 2) end end)
        elseif try == 2 then swap = nil end
        return
    end
    swap = nil
    table.sort(found)
    local pick = found[1]
    if #found > 1 then
        for _, id in ipairs(found) do if KM.Item(id).class == 15 then pick = id; break end end
    end
    ns.Unbox(pick)
end
ns.CheckSwap = checkSwap

local function nodeName(w, kind)
    if (kind == "mine" or kind == "herb") and w.cast and w.cast.target then return w.cast.target end
end

local function onOpen(w)
    w.money = 0
    lootWin = w
    if w.kind == "box" then watchBox(w) end
    local key
    for _, s in ipairs(w.slots) do
        for _, src in ipairs(s.src) do
            if not key and src.guid and src.gk ~= "Player" then key = src.guid end
        end
    end
    if w.farming then ns.Act(key, w.kind) end
    local farmKills = KM.mods.Farm and KM.mods.Farm.db
    local seen = {}
    for _, s in ipairs(w.slots) do
        for _, src in ipairs(s.src) do
            local k, id = src.kind or s.kind, src.id or 0
            local sk = (src.guid or "?") .. ":" .. k
            if not seen[sk] and k ~= "fish" then
                seen[sk] = true
                if k == "mob" then
                    if src.guid and not corpses[src.guid] then
                        corpses[src.guid] = true
                        -- without Farm's kill detection, a fresh corpse looted is the kill
                        if not farmKills then ns.Kill(id, src.guid) end
                        ns.Harvest("mob", id)
                    end
                else
                    ns.Harvest(k, id, nodeName(w, k))
                end
            end
        end
    end
    if w.kind == "fish" then ns.Harvest("fish", 0) end
end

local function onClear(w, slot)
    if slot.locked or slot.coin or not slot.item then return end
    local all = #slot.src > 0
    for _, src in ipairs(slot.src) do if not (src.qty and src.qty > 0) then all = false end end
    if all then
        for _, src in ipairs(slot.src) do ns.Credit(src.kind or slot.kind, src.id or 0, slot.item, src.qty) end
    else
        local src = slot.src[1]
        ns.Credit((src and src.kind) or slot.kind or w.kind, (src and src.id) or 0, slot.item, slot.qty or 1)
    end
end

-- A group loot roll you won, or master loot handed to you: Core\Loot.lua saw it reach your bags (once), with the
-- corpse whose window showed it (mob 0 when you never opened it).
local function onWon(slot)
    if not slot or not slot.item then return end
    local src = slot.src and slot.src[1]
    ns.Credit((src and src.kind) or slot.kind or "mob", (src and src.id) or 0, slot.item, slot.qty or 1)
end

-- The coin a window brought: the money that arrived, split over its coin slots' sources.
local function settle(w, try)
    if w.settled then return end
    local money = w.money or 0
    local parts, slotTotal = {}, 0
    for _, s in ipairs(w.slots) do
        if s.coin and not s.locked and (s.cleared or money > 0) then
            local any = false
            for _, src in ipairs(s.src) do
                if (src.qty or 0) > 0 then
                    any = true
                    parts[#parts + 1] = { kind = src.kind or s.kind, id = src.id or 0, c = src.qty }
                    slotTotal = slotTotal + src.qty
                end
            end
            if not any and (s.copper or 0) > 0 then
                parts[#parts + 1] = { kind = s.kind or w.kind, id = 0, c = s.copper }
                slotTotal = slotTotal + s.copper
            end
        end
    end
    if money <= 0 and slotTotal > 0 and try == 1 then
        -- latency: wait once more before falling back to what the slots said
        C_Timer.After(1.5, function() KM.Safe(settle, w, 2) end)
        return
    end
    w.settled = true
    if settlingWin == w then settlingWin = nil end
    local total = money > 0 and money or slotTotal
    if total <= 0 then return end
    if slotTotal <= 0 then return ns.CreditCoin(w.kind, 0, total) end
    local given = 0
    for i, p in ipairs(parts) do
        local c = (i == #parts) and (total - given) or math.floor(p.c * total / slotTotal + 0.5)
        given = given + c
        ns.CreditCoin(p.kind, p.id, c)
    end
end

local function onClose(w)
    if lootWin == w then lootWin = nil end
    settlingWin = w
    C_Timer.After(1.5, function() KM.Safe(settle, w, 1) end)
    if swap and swap.w == w and not swap.closed then
        swap.closed = GetTime()
        C_Timer.After(0.5, function() KM.Safe(checkSwap, 1) end)
    end
end

KM.OnLoot("Tracker", function(event, w, slot)
    if not ns.db then return end
    if event == "cast" then
        if slot and KM.FARMING_KINDS[slot.kind] then ns.Activity(slot.kind) end
    elseif event == "open" then onOpen(w)
    elseif event == "clear" then onClear(w, slot)
    elseif event == "won" then onWon(slot)
    elseif event == "close" then onClose(w) end
end)

---------------------------------------------------------------------------
-- Money that isn't loot
---------------------------------------------------------------------------

local CTX = {}
do
    local names = { TradePartner = "trade", Merchant = "merchant", TaxiNode = "taxi", Trainer = "trainer", Banker = "bank",
        GuildBanker = "bank", MailInfo = "mail", Auctioneer = "ah", AccountBanker = "bank" }
    local literal = { TradePartner = 1, Merchant = 5, TaxiNode = 6, Trainer = 7, Banker = 8, GuildBanker = 10,
        MailInfo = 17, Auctioneer = 21, AccountBanker = 68 }
    local enum = Enum and Enum.PlayerInteractionType
    for name, kind in pairs(names) do
        local v = (enum and enum[name]) or literal[name]
        if v then CTX[v] = kind end
    end
end
local CASH_KIND = { taxi = "travel", trainer = "train" }
local CLASSIC = { MERCHANT_SHOW = "merchant", MAIL_SHOW = "mail", AUCTION_HOUSE_SHOW = "ah", TRADE_SHOW = "trade",
    TAXIMAP_OPENED = "taxi", TRAINER_SHOW = "trainer", BANKFRAME_OPENED = "bank" }
local CLASSIC_CLOSE = { MERCHANT_CLOSED = "merchant", MAIL_CLOSED = "mail", AUCTION_HOUSE_CLOSED = "ah", TRADE_CLOSED = "trade",
    TAXIMAP_CLOSED = "taxi", TRAINER_CLOSED = "trainer", BANKFRAME_CLOSED = "bank" }

local function repairCost()
    if not GetRepairAllCost then return 0 end
    local ok, c = pcall(GetRepairAllCost)
    return ok and plain(c) or 0
end

local function openCtx(kind)
    ctx = { kind = kind }
    if kind == "merchant" then repairBefore = repairCost() end
end

local function closeCtx(kind)
    if ctx and (not kind or ctx.kind == kind) and not ctx.closedAt then ctx.closedAt = GetTime() end
end

local function currentCtx()
    if not ctx then return nil end
    if ctx.closedAt and GetTime() - ctx.closedAt > 1 then ctx = nil; return nil end   -- mail money can lag a moment
    return ctx.kind
end

local function onMoney()
    local now = plain(GetMoney and GetMoney())
    if not now then return end
    local d = lastMoney and (now - lastMoney) or 0
    lastMoney = now
    if d == 0 then return end
    local w = lootWin or settlingWin
    if w and d > 0 then w.money = (w.money or 0) + d; return end
    if not ns.Live() then return end
    if quest and GetTime() - quest.at < 2 and math.abs(d - quest.money) <= 1 then
        quest = nil
        return ns.Cash("quest", d)
    end
    local c = currentCtx()
    if c == "merchant" then
        if d > 0 then return ns.Cash("vendor", d) end
        local cost = repairCost()
        if repairBefore and -d <= repairBefore + 1 and cost <= repairBefore + d + 1 then
            repairBefore = cost
            return ns.Cash("repair", d)
        end
        lastBuy = { d = d, at = GetTime(), before = repairBefore }
        return ns.Cash("buy", d)
    elseif c then
        return ns.Cash(CASH_KIND[c] or c, d)
    elseif d > 0 and IsInGroup and plain(IsInGroup()) and ns.Settings().countShares then
        return ns.CreditCoin("share", 0, d)
    end
    lastOther = { d = d, at = GetTime() }
    ns.Cash("other", d)
end

local function onQuest(money)
    money = plain(money)
    if not money or money <= 0 then return end
    if lastOther and GetTime() - lastOther.at < 2 and math.abs(lastOther.d - money) <= 1 then
        ns.MoveCash("other", "quest", lastOther.d)   -- the money came before the event
        lastOther = nil
        return
    end
    quest = { at = GetTime(), money = money }
end

local function onDurability()
    if currentCtx() ~= "merchant" then return end
    local cost = repairCost()
    if lastBuy and GetTime() - lastBuy.at < 2 and lastBuy.before and cost <= lastBuy.before + lastBuy.d + 1 then
        ns.MoveCash("buy", "repair", lastBuy.d)   -- the durability update came after the money
        lastBuy = nil
        repairBefore = cost
    elseif repairBefore and cost > repairBefore then
        repairBefore = cost
    end
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
    "TRAINER_SHOW", "TRAINER_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "QUEST_TURNED_IN",
    "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_DISABLED", "BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not ns.db then return end
    if event == "PLAYER_MONEY" then
        KM.Safe(onMoney)
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        lastMoney = plain(GetMoney and GetMoney()) or lastMoney
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local kind = CTX[plain(a1) or -1]
        if kind then openCtx(kind) end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local kind = CTX[plain(a1) or -1]
        if kind then closeCtx(kind) end
    elseif CLASSIC[event] then
        if not (ctx and ctx.kind == CLASSIC[event] and not ctx.closedAt) then openCtx(CLASSIC[event]) end
    elseif CLASSIC_CLOSE[event] then
        closeCtx(CLASSIC_CLOSE[event])
    elseif event == "QUEST_TURNED_IN" then
        KM.Safe(onQuest, a3)
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        KM.Safe(onDurability)
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Activity("combat")
    elseif event == "BAG_UPDATE_DELAYED" then
        if swap and swap.closed then KM.Safe(checkSwap, 0) end
    end
end)
