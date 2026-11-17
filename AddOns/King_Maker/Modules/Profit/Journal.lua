local _, KM = ...
local ns = KM.Module("Profit")

-- What goes in the journal, and when:
--   Day one (PLAYER_LOGIN + 5 s, once): the whole Sales Ledger, duplicates dropped (same character, kind, item,
--     count, price, cut and deposit within 5 s: the copy naming the buyer is kept), becomes b / s / d events; then
--     every item with events or stock is reconciled once: what you own beyond the history is opening stock at today's
--     value, what history says you hold but don't is a "before tracking" closure.
--   Every new mail: MailKing's ENTRY callback (an event already in the item's journal is skipped).
--   Loot: KM.OnLoot "clear" (only slots you took) and "won" (a roll or master loot that reached your bags): one lot per
--     item, kind, character and day, cost 0. Disenchanted mats go to Moves.lua instead when it saw the cast (2.8).
--   Vendors: at a merchant, the settled bag counts against your gold. Items gone + money in at their vendor price ->
--     a vendor sale; items in + money out at the merchant's price -> a vendor purchase; buying the same stack back in
--     the same visit removes the sale; a repair (money out, nothing in) records nothing. No hook on BuyMerchantItem
--     or UseContainerItem (on Forever that gets an addon blocked).
--   Values: an item that hadn't loaded has its worth filled in on GET_ITEM_INFO_RECEIVED.

---------------------------------------------------------------------------
-- The Sales Ledger
---------------------------------------------------------------------------

-- The item a Sales Ledger entry is about (a sale mail only names it).
function ns.EntryItem(e)
    if e.item then return e.item end
    local mail = KM.mods.Mail
    local id = mail and mail.db and mail.db.names and e.name and mail.db.names[e.name]
    if id then return id end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if inst and e.name then
        local ok, found = pcall(inst, e.name)
        if ok and found then return found end
    end
    return nil
end

-- The dashboard's rule: the same character, kind, item, count, price, cut and deposit within 5 seconds is one mail;
-- the copy that names the buyer is kept.
function ns.DedupeEntries(list)
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    local groups, out = {}, {}
    for _, e in ipairs(list) do
        local sig = table.concat({ tostring(e.c), tostring(e.k), tostring(e.name), tostring(e.n), tostring(e.g),
            tostring(e.cut), tostring(e.dep) }, "|")
        local last = groups[sig]
        if last and (e.t or 0) - (last.t or 0) <= 5 then
            if (last.who or "") == "" and (e.who or "") ~= "" then last.who = e.who end
        else
            groups[sig] = e
            out[#out + 1] = e
        end
    end
    return out
end

-- One entry into the journal: "added", "dup", "unknown" (no item ID) or "skip" (nothing to record, or left out).
function ns.ImportEntry(e)
    local id = ns.EntryItem(e)
    if not id then return "unknown" end
    if ns.Excluded(id) then return "skip" end
    local pool = ns.PoolOf(e.c or KM.Char())
    local t = math.floor((e.t or KM.Now()) + 0.5)
    if e.k == "buy" then
        local q, c = e.n or 1, e.g or 0
        if ns.Has(pool, id, "b", t, q, c) then return "dup" end
        ns.Add(pool, id, "b", { t = t, q = q, c = c, v = ns.ValueOf(id, q), who = e.c })
    elseif e.k == "sale" then
        local q, c = e.n or 1, (e.g or 0) - (e.cut or 0)
        if ns.Has(pool, id, "s", t, q, c) then return "dup" end
        ns.Add(pool, id, "s", { t = t, q = q, c = c, who = e.c })
    elseif e.k == "expired" or e.k == "cancelled" then
        local dep = e.dep or 0
        if dep <= 0 then return "skip" end
        if ns.Has(pool, id, "d", t, 0, dep) then return "dup" end
        ns.Add(pool, id, "d", { t = t, q = 0, c = dep, who = e.c, s = e.k == "expired" and "x" or "c" })
    else
        return "skip"
    end
    return "added"
end

-- The whole Sales Ledger into the journal, duplicates dropped; what's already there is skipped, so running it again
-- changes nothing. Returns counts { mails, copies, added, dup, unknown, skip, sales, buys }.
function ns.ImportLedger()
    local list = MailKing and MailKing.GetEntries and KM.Safe(MailKing.GetEntries) or {}
    local raw = #list
    list = ns.DedupeEntries(list)
    local n = { mails = raw, copies = raw - #list, added = 0, dup = 0, unknown = 0, skip = 0, sales = 0, buys = 0 }
    for _, e in ipairs(list) do
        local r = ns.ImportEntry(e)
        n[r] = (n[r] or 0) + 1
        if r == "added" and e.k == "sale" then n.sales = n.sales + 1 end
        if r == "added" and e.k == "buy" then n.buys = n.buys + 1 end
    end
    return n
end

-- Day one. Safe to call again: it does nothing once tracking has begun.
function ns.FirstRun()
    if not ns.db or ns.db.start then return end
    ns.db.start = KM.Now()
    ns.db.home = ns.MyPool()
    ns.Pool(ns.db.home, true)
    ns.ResetEnded()
    local n = ns.ImportLedger()
    ns.db.import = { mails = n.mails, copies = n.copies, added = n.added, unknown = n.unknown, sales = n.sales, buys = n.buys }
    -- startup reconciliation: every item with events or stock, in every pool
    local todo, seen = {}, {}
    local function add(pool, id)
        local key = pool .. "|" .. id
        if not seen[key] then seen[key] = true; todo[#todo + 1] = { pool, id } end
    end
    for pool, p in pairs(ns.db.pools) do for id in pairs(p.items) do add(pool, id) end end
    local inv = KM.mods.Inventory
    for who in pairs(inv and inv.db and inv.db.stock or {}) do
        local pool = ns.PoolOf(who)
        for _, id in ipairs(ns.OwnedIDs(pool)) do add(pool, id) end
    end
    for _, j in ipairs(todo) do KM.Safe(ns.Startup, j[1], j[2]) end
    ns.MarkSeen()
    if n.added > 0 or n.unknown > 0 then
        KM.Print(ns, "Profit & Loss is tracking now: " .. n.buys .. " purchases and " .. n.sales .. " sales from your Sales Ledger"
            .. " matched" .. (n.unknown > 0 and ("; " .. n.unknown .. " old mail" .. (n.unknown == 1 and "" or "s") .. " couldn't be matched to an item") or "")
            .. ". /pnl opens it.")
    end
    ns.Changed(ns.db.home, 0)
end

-- A mail the Sales Ledger just recorded.
local function onEntry(_, e)
    if not (ns.db and ns.db.start and type(e) == "table") then return end
    ns.NoteEnded(e)
    local r = ns.ImportEntry(e)
    local id = ns.EntryItem(e)
    if id then ns.Mark(ns.PoolOf(e.c or KM.Char()), id) end
    return r
end
ns.OnEntry = onEntry

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------

KM.OnLoot("Profit", function(event, window, slot)
    if not (ns.db and ns.db.start) then return end
    if event == "close" then
        if window and window.kind == "de" and ns.DEClose then ns.DEClose(window) end
        return
    end
    if event ~= "clear" and event ~= "won" then return end
    if not slot or not slot.item or slot.coin or slot.quest then return end
    local id = slot.item
    if ns.Excluded(id) then return end
    local q = slot.qty or 1
    if slot.kind == "de" and ns.DEMat and ns.DEMat(id, q) then return end      -- 2.8: the item's cost goes into them
    ns.Add(ns.MyPool(), id, "l", { q = q, c = 0, v = ns.ValueOf(id, q), who = KM.Char(), s = slot.kind or "unknown" })
end)

---------------------------------------------------------------------------
-- Vendors: bags against gold while a merchant is open
---------------------------------------------------------------------------

local merchant      -- { prices = { [id] = copper each }, bags, money, sold = { { id, q, c, evid, pool } }, repaired }

-- What's in this character's bags, by item (bound items left out, as Inventory does).
local function bagSnapshot()
    local out = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local i = C_Container.GetContainerItemInfo(bag, slot)
            if i and i.itemID and not KM.Plain(i.isBound) then
                out[i.itemID] = (out[i.itemID] or 0) + (KM.Plain(i.stackCount) or 1)
            end
        end
    end
    return out
end
ns.BagSnapshot = bagSnapshot

local function merchantPrices()
    local out = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
            if ok and type(info) == "table" then price, stack = info.price, info.stackCount end
        end
        if not price and GetMerchantItemInfo then
            local _, _, p, q = GetMerchantItemInfo(i)
            price, stack = p, q
        end
        if id and price and price > 0 then out[id] = price / math.max(1, stack or 1) end
    end
    return out
end

local function vendorPrice(id)
    if merchant and merchant.prices[id] then return merchant.prices[id] end
    local mk = KM.mods.Market
    return mk and mk.db and mk.db.vendor and mk.db.vendor[id] or nil
end

local function money() return KM.Plain(GetMoney and GetMoney()) or 0 end

function ns.MerchantOpen()
    if merchant then return end
    merchant = { prices = merchantPrices(), bags = bagSnapshot(), money = money(), sold = {} }
end

function ns.MerchantClose() merchant = nil end

-- The bags and gold settled: what (if anything) was bought or sold.
function ns.MerchantSettle()
    if not (merchant and ns.db and ns.db.start) then return end
    if not next(merchant.prices) then merchant.prices = merchantPrices() end
    local now, m = bagSnapshot(), money()
    local dm = m - merchant.money
    local up, down, nUp, nDown = {}, {}, 0, 0
    for id, n in pairs(now) do
        local d = n - (merchant.bags[id] or 0)
        if d > 0 then up[id], nUp = d, nUp + 1 elseif d < 0 then down[id], nDown = -d, nDown + 1 end
    end
    for id, n in pairs(merchant.bags) do if not now[id] then down[id], nDown = n, nDown + 1 end end
    if nUp == 0 and nDown == 0 then
        merchant.money, merchant.repaired = m, nil              -- a repair, or something else: not stock
        return
    end
    if dm == 0 then
        -- the bags moved but the gold hasn't yet: wait for it once, then let it go (moving stacks, destroying one)
        merchant.waits = (merchant.waits or 0) + 1
        if merchant.waits >= 2 then merchant.bags, merchant.waits = now, 0 end
        return
    end
    merchant.waits = 0
    local pool, who = ns.MyPool(), KM.Char()
    if dm > 0 and nDown > 0 and nUp == 0 then
        -- sold: the gold must match the vendor prices within a copper per unit
        local expect, units = 0, 0
        for id, n in pairs(down) do expect, units = expect + (KM.Item(id).sell or 0) * n, units + n end
        if expect > 0 and math.abs(dm - expect) <= units then
            for id, n in pairs(down) do
                local sell = KM.Item(id).sell or 0
                if sell > 0 and not ns.Excluded(id) then
                    local evid = ns.Add(pool, id, "n", { q = n, c = sell * n, who = who })
                    table.insert(merchant.sold, { id = id, q = n, c = sell * n, evid = evid, pool = pool })
                end
            end
        end
    elseif dm < 0 and nUp > 0 and nDown == 0 then
        local paid = -dm
        local done = false
        if nUp == 1 then
            local id, n = next(up)
            for i, s in ipairs(merchant.sold) do
                if s.id == id and s.q == n and math.abs(s.c - paid) <= n then
                    ns.Edit(s.pool, id, s.evid, function() return false end)   -- bought back: the sale never happened
                    table.remove(merchant.sold, i)
                    done = true
                    break
                end
            end
            if not done and not ns.Excluded(id) then
                local unit = vendorPrice(id)
                if (unit and math.abs(unit * n - paid) <= n) or (not unit and not merchant.repaired) then
                    ns.Add(pool, id, "m", { q = n, c = paid, v = ns.ValueOf(id, n), who = who })
                end
            end
        else
            local expect, units, known = 0, 0, true
            for id, n in pairs(up) do
                local unit = vendorPrice(id)
                if not unit then known = false; break end
                expect, units = expect + unit * n, units + n
            end
            if known and math.abs(expect - paid) <= units then
                for id, n in pairs(up) do
                    if not ns.Excluded(id) then ns.Add(pool, id, "m", { q = n, c = vendorPrice(id) * n, v = ns.ValueOf(id, n), who = who }) end
                end
            end
        end
    end
    merchant.bags, merchant.money, merchant.repaired = now, m, nil
end

local settleSoon = false
local function settle()
    if settleSoon then return end
    settleSoon = true
    C_Timer.After(0.3, function() settleSoon = false; KM.Safe(ns.MerchantSettle) end)
end

---------------------------------------------------------------------------
-- Values filled in once an item loads
---------------------------------------------------------------------------

function ns.FillPending()
    if not ns.db or #ns.db.pend == 0 then return end
    local keep = {}
    for _, key in ipairs(ns.db.pend) do
        local pool, id, evid = key:match("^(.*)|(%d+)|(%d+)$")
        id, evid = tonumber(id), tonumber(evid)
        if id and KM.ItemValue(id) ~= nil then
            ns.Edit(pool, id, evid, function(e)
                if e.v == nil then
                    e.v = ns.ValueOf(id, e.q or 0)
                    if e.k == "o" and e.c == nil then e.c = e.v end
                end
            end)
        elseif id then
            keep[#keep + 1] = key
        end
    end
    wipe(ns.db.pend)
    for i, k in ipairs(keep) do ns.db.pend[i] = k end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local MERCHANT = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Merchant) or 5
local infoSoon = false
local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GET_ITEM_INFO_RECEIVED",
    "UPDATE_INVENTORY_DURABILITY")
f:SetScript("OnEvent", function(_, event, a1)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        if MailKing and MailKing.RegisterCallback then
            MailKing.RegisterCallback("ENTRY", function(ev, e) KM.Safe(onEntry, ev, e) end, "Profit")
            MailKing.RegisterCallback("RESET", function() ns.ResetEnded(); KM.Refresh("profit") end, "Profit")
        end
        if InventoryKing and InventoryKing.RegisterCallback then
            InventoryKing.RegisterCallback("STOCK", function() KM.Safe(ns.OnStock) end, "Profit")
        end
        if ScannerKing and ScannerKing.RegisterCallback then
            ScannerKing.RegisterCallback("Profit", function(ev) if ev == "PRICES_UPDATED" then KM.Refresh("profit") end end)
        end
        C_Timer.After(5, function()
            if not ns.db.start then KM.Safe(ns.FirstRun) end
            C_Timer.After(5, function() KM.Safe(ns.MarkAll) end)                 -- the login pass (+10 s)
            C_Timer.After(25, function()                                         -- folding (+30 s, once a day)
                if KM.Now() - (ns.db.lastFold or 0) > 86400 then KM.Safe(ns.FoldAll) end
            end)
        end)
    elseif event == "MERCHANT_SHOW" then
        ns.MerchantOpen()
    elseif event == "MERCHANT_CLOSED" then
        if merchant then KM.Safe(ns.MerchantSettle) end
        ns.MerchantClose()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if KM.Plain(a1) == MERCHANT then ns.MerchantOpen() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if KM.Plain(a1) == MERCHANT then
            if merchant then KM.Safe(ns.MerchantSettle) end
            ns.MerchantClose()
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        if merchant then settle() end
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        if merchant then merchant.repaired = true end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if #ns.db.pend > 0 and not infoSoon then
            infoSoon = true
            C_Timer.After(0.5, function() infoSoon = false; KM.Safe(ns.FillPending) end)
        end
    end
end)
