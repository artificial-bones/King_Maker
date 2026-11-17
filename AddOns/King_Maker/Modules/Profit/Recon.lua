local _, KM = ...
local ns = KM.Module("Profit")

-- Reconciliation: quantities come from counts, money and labels from events. The Inventory module counts what every
-- character holds (bags, bank, mailbox, auctions); when a pool holds fewer of an item than its open lots, the missing
-- units are closed as "used or gone" (provisional for 30 days: a sale mail read late takes them back, and units that
-- turn up again reopen them). When it holds more, the extra units are untraced: shown and valued, never given a cost
-- (unless you count them as opening stock, or it's the first time we see that bank or alt).
--
--   ns.Owned(pool, id)      how many the pool really holds: everyone's bags + bank + mail + what's still on the AH (the
--                           AH count is as of that character's last visit, so auctions whose sale, expiry or cancel mail
--                           is dated after it come off) + mail you sent your own characters that they haven't seen
--                           yet (2.8: in transit). nil without the Inventory module.
--   ns.Reconcile(pool, id, src)   the rule; src = a place name for a first sighting / "adopt": surplus -> opening lots
--   ns.Mark(pool, id)       reconcile this item once things settle (2 s after the last change, never while the auction
--                           house, mailbox, bank, guild bank, a merchant, trade or a loot window is open)

---------------------------------------------------------------------------
-- The owned count
---------------------------------------------------------------------------

local ended                 -- "who|itemID" -> { { t, n } }: Sales Ledger sales, expiries and cancels

local function addEnded(e)
    if not (e and e.c and (e.k == "sale" or e.k == "expired" or e.k == "cancelled")) then return end
    local id = ns.EntryItem and ns.EntryItem(e)
    if not id then return end
    local key = e.c .. "|" .. id
    ended[key] = ended[key] or {}
    table.insert(ended[key], { t = e.t or 0, n = e.n or 1 })
end

local function buildEnded()
    ended = {}
    local list = MailKing and MailKing.GetEntries and KM.Safe(MailKing.GetEntries) or {}
    for _, e in ipairs(list) do addEnded(e) end
end

function ns.NoteEnded(e) if ended then addEnded(e) end end
function ns.ResetEnded() ended = nil end

-- Units of that character's item whose auction ended (sold, expired, cancelled) after t.
function ns.EndedSince(who, id, t)
    if not ended then buildEnded() end
    local n = 0
    for _, x in ipairs(ended[who .. "|" .. id] or {}) do if x.t > t then n = n + x.n end end
    return n
end

local function invStock()
    local inv = KM.mods.Inventory
    return inv and inv.db and inv.db.stock or nil
end

-- Units mailed to your own characters that haven't reached a count yet: sent within 30 days, and the alt's mailbox not
-- read since (once it is, the units are in its mail or bags count).
function ns.InTransit(pool, id)
    local r = ns.Replay(pool, id)
    if #r.transit == 0 then return 0 end
    local now, n = KM.Now(), 0
    local stock = invStock() or {}
    for _, e in ipairs(r.transit) do
        local _, to = ns.MailTo(e.s)
        local s = to and stock[to]
        if now - (e.t or 0) < ns.WINDOW and (not s or (s.mailT or 0) <= (e.t or 0)) then n = n + (e.q or 0) end
    end
    return n
end

function ns.Owned(pool, id)
    if not (InventoryKing and InventoryKing.GetPlaces) then return nil end
    local places = KM.Safe(InventoryKing.GetPlaces, id)
    if not places then return nil end
    local total = 0
    for who, p in pairs(places) do
        if ns.PoolOf(who) == pool then
            local ah = p.ah or 0
            if ah > 0 then ah = math.max(0, ah - ns.EndedSince(who, id, p.ahT or 0)) end
            total = total + (p.bags or 0) + (p.bank or 0) + (p.mail or 0) + ah
        end
    end
    return total + ns.InTransit(pool, id)
end

-- Every item the pool's characters hold (from the Inventory module's counts).
function ns.OwnedIDs(pool)
    local out, seen = {}, {}
    for who, s in pairs(invStock() or {}) do
        if ns.PoolOf(who) == pool then
            for _, place in ipairs({ "bags", "bank", "mail", "ah" }) do
                for id, n in pairs(s[place] or {}) do
                    if (n or 0) > 0 and not seen[id] then seen[id] = true; out[#out + 1] = id end
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The rule
---------------------------------------------------------------------------

function ns.Reconcile(pool, id, src)
    if not (ns.db and ns.db.start) or ns.Excluded(id) then return end
    local owned = ns.Owned(pool, id)
    if not owned then return end
    local r = ns.Replay(pool, id)
    local open, recent = ns.OpenQ(r), ns.RecentGoneQ(r)
    if owned < open then
        ns.Add(pool, id, "g", { q = open - owned })               -- provisional: "used or gone"
    elseif owned > open then
        local back = math.min(owned - open, recent)
        if back > 0 then
            -- it turned up again: undo the newest closures (dated after them: in one second an r replays before a g)
            local after = 0
            for _, g in ipairs(r.gone) do after = math.max(after, (g.e.t or 0) + 1) end
            ns.Add(pool, id, "r", { q = back, t = math.max(KM.Now(), after) })
        end
        local rest = owned - open - back                          -- what's left is untraced (computed, not saved)...
        if src and rest > 0 then                                  -- ...unless this is a first sighting or Adopt
            local v = ns.ValueOf(id, rest)
            ns.Add(pool, id, "o", { q = rest, v = v, c = v, s = src })
        end
    end
end

-- Day one: history says you hold more than you do -> a startup closure (final, never in a period's P&L); you hold more
-- than history explains -> opening stock dated the day tracking began, at today's value.
function ns.Startup(pool, id)
    if ns.Excluded(id) then return end
    local owned = ns.Owned(pool, id)
    if not owned then return end
    local open = ns.OpenQ(ns.Replay(pool, id))
    if owned > open then
        local v = ns.ValueOf(id, owned - open)
        ns.Add(pool, id, "o", { t = ns.db.start, q = owned - open, v = v, c = v, s = "start" })
    elseif owned < open then
        ns.Add(pool, id, "g", { t = ns.db.start, q = open - owned, s = "startup" })
    end
end

-- Count every untraced unit in the pool as opening stock today (the Adopt button, /pnl adopt).
function ns.Adopt(pool)
    if not ns.db.start then return 0 end
    pool = pool or ns.MyPool()
    if not (InventoryKing and InventoryKing.GetPlaces) then
        KM.Print(ns, "counting what you hold needs the Inventory module.")
        return 0
    end
    local n, items = 0, 0
    for _, h in ipairs(ns.Holdings(pool)) do
        if (h.untraced or 0) > 0 then
            n, items = n + h.untraced, items + 1
            ns.Reconcile(pool, h.item, "adopt")
        end
    end
    KM.Print(ns, n > 0 and ("counted " .. KM.Commas(n) .. " untraced item" .. (n == 1 and "" or "s") .. " (" .. items
        .. " kind" .. (items == 1 and "" or "s") .. ") as opening stock at today's value.") or "nothing untraced to count.")
    return n
end

---------------------------------------------------------------------------
-- When it runs: deferred until things settle
---------------------------------------------------------------------------

local busy = {}           -- what's open: "ah", "mail", "bank", "merchant", "trade"
local marked = {}         -- "pool|id" -> true, or the place of a first sighting ("bags", "bank", "mail")
local scheduled = false
local snapshot            -- this character's per-item totals at the last STOCK

local BUSY_TYPES = {}
do
    local names = { TradePartner = "trade", Merchant = "merchant", Banker = "bank", GuildBanker = "bank", MailInfo = "mail",
        Auctioneer = "ah", AccountBanker = "bank" }
    local literal = { TradePartner = 1, Merchant = 5, Banker = 8, GuildBanker = 10, MailInfo = 17, Auctioneer = 21, AccountBanker = 68 }
    local enum = Enum and Enum.PlayerInteractionType
    for name, kind in pairs(names) do
        local v = (enum and enum[name]) or literal[name]
        if v then BUSY_TYPES[v] = kind end
    end
end
ns.BUSY_TYPES = BUSY_TYPES
local OPEN = { MERCHANT_SHOW = "merchant", MAIL_SHOW = "mail", AUCTION_HOUSE_SHOW = "ah", TRADE_SHOW = "trade",
    BANKFRAME_OPENED = "bank", GUILDBANKFRAME_OPENED = "gbank" }
local CLOSE = { MERCHANT_CLOSED = "merchant", MAIL_CLOSED = "mail", AUCTION_HOUSE_CLOSED = "ah", TRADE_CLOSED = "trade",
    BANKFRAME_CLOSED = "bank", GUILDBANKFRAME_CLOSED = "gbank" }

function ns.Busy()
    if KM.LootWindow and KM.LootWindow() then return true end
    if ns.Moving and ns.Moving() then return true end             -- a craft, disenchant or quest reward settling
    for _, on in pairs(busy) do if on then return true end end
    return false
end

local function runMarked()
    scheduled = false
    if not (ns.db and ns.db.start) then return end
    if ns.Busy() then return end                                  -- runs again when they close
    local list = marked
    marked = {}
    for key, how in pairs(list) do
        local pool, id = key:match("^(.*)|(%d+)$")
        if pool then KM.Safe(ns.Reconcile, pool, tonumber(id), how ~= true and how or nil) end
    end
end

function ns.Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(2, runMarked)
end

function ns.Mark(pool, id, place)
    if not (pool and id) then return end
    local key = pool .. "|" .. id
    if place or not marked[key] then marked[key] = place or true end
    ns.Schedule()
end

function ns.Pending() local n = 0 for _ in pairs(marked) do n = n + 1 end return n end

-- Every item with open lots or recent closures, everywhere (the login pass).
function ns.MarkAll()
    for pool, p in pairs(ns.db.pools) do
        for id in pairs(p.items) do
            local r = ns.Replay(pool, id)
            if ns.OpenQ(r) > 0 or ns.RecentGoneQ(r) > 0 then marked[pool .. "|" .. id] = marked[pool .. "|" .. id] or true end
        end
        for _, id in ipairs(ns.OwnedIDs(pool)) do marked[pool .. "|" .. id] = marked[pool .. "|" .. id] or true end
    end
    ns.Schedule()
end

local PLACES = { "bags", "bank", "mail" }

-- The first time we see a character's bags, bank or mailbox after tracking began: what's there becomes opening stock.
-- Not at once: with the rest, once things settle (a mailbox's purchase mails are read into lots first).
local function sightings(who)
    local s = (invStock() or {})[who]
    if not s then return end
    local pool = ns.PoolOf(who)
    local p = ns.Pool(pool, true)
    p.seen[who] = p.seen[who] or {}
    local seen = p.seen[who]
    for _, place in ipairs(PLACES) do
        if s[place .. "T"] and not seen[place] then
            seen[place] = s[place .. "T"]
            for id, n in pairs(s[place] or {}) do
                if (n or 0) > 0 then ns.Mark(pool, id, place) end
            end
        end
    end
end

-- Marks every place Inventory has read as seen (day one: opening stock covered them).
function ns.MarkSeen()
    for who, s in pairs(invStock() or {}) do
        local p = ns.Pool(ns.PoolOf(who), true)
        p.seen[who] = p.seen[who] or {}
        for _, place in ipairs(PLACES) do
            if s[place .. "T"] and not p.seen[who][place] then p.seen[who][place] = s[place .. "T"] end
        end
    end
end

local function totals(who)
    local out = {}
    local s = (invStock() or {})[who] or {}
    for _, place in ipairs({ "bags", "bank", "mail", "ah" }) do
        for id, n in pairs(s[place] or {}) do out[id] = (out[id] or 0) + n end
    end
    return out
end

-- Inventory re-read this character: mark what changed (and the warband bank's), look for first sightings.
function ns.OnStock()
    if not (ns.db and ns.db.start) then return end
    local who = KM.Char()
    local pool = ns.PoolOf(who)
    sightings(who)
    sightings("Warband")
    local now = totals(who)
    local wb = totals("Warband")
    for id, n in pairs(wb) do now[id] = (now[id] or 0) + n end
    if snapshot then
        for id, n in pairs(now) do if snapshot[id] ~= n then ns.Mark(pool, id) end end
        for id in pairs(snapshot) do if now[id] == nil then ns.Mark(pool, id) end end
    else
        for id in pairs(now) do ns.Mark(pool, id) end
    end
    snapshot = now
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SHOW",
    "TRADE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "LOOT_CLOSED")
f:SetScript("OnEvent", function(_, event, a1)
    if not ns.db then return end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local kind = BUSY_TYPES[KM.Plain(a1) or -1]
        if kind then busy[kind] = true end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local kind = BUSY_TYPES[KM.Plain(a1) or -1]
        if kind and busy[kind] then busy[kind] = nil; ns.Schedule() end
    elseif OPEN[event] then
        busy[OPEN[event]] = true
    elseif CLOSE[event] then
        -- the close events can fire twice: harmless
        if busy[CLOSE[event]] then busy[CLOSE[event]] = nil end
        if next(marked) then ns.Schedule() end
    elseif event == "LOOT_CLOSED" then
        if next(marked) then ns.Schedule() end
    end
end)
