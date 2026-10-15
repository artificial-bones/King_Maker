local _, ns = ...

-- Reading the mailbox.
--
-- Every time the mailbox opens or changes, each auction house mail in it is
-- recorded once (it's remembered, so opening the mailbox again or leaving the
-- mail there changes nothing):
--   sale       "Auction successful": the price, the auction house cut, the buyer
--   buy        "Auction won": what you paid, the seller
--   expired    "Auction expired", and cancelled "Auction cancelled": the deposit
--              you lost, when Mail King saw you post it
-- Auction house mail lasts 30 days, so the time left on a mail tells when it was
-- sent: a sale is dated when it sold, even if you only check your mail days later.
--
-- Postings: when you put something up, Mail King notes what the deposit was,
-- so an auction that comes back expired shows what it cost you.
--
-- Your gold: each character's gold is noted whenever it changes, for the total
-- across your characters.

local KEEP_SEEN = 35 * 86400   -- mail keys kept (mail lasts 30 days)
local KEEP_POSTS = 3 * 86400   -- postings kept (auctions last at most 48 hours)
local MAIL_DAYS = 30           -- auction house mail lasts this long
local BUCKET = 600             -- seconds: a mail's expiry, rounded, is part of its key

local KINDS = {
    { "sale", AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s" },
    { "buy", AUCTION_WON_MAIL_SUBJECT, "Auction won: %s" },
    { "expired", AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s" },
    { "cancelled", AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s" },
    { "outbid", AUCTION_OUTBID_MAIL_SUBJECT, "Outbid on %s" },
}

-- "Auction successful: %s" -> "^Auction successful: (.+)$"
local function pattern(fmt)
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end
local PATTERNS = {}
for _, k in ipairs(KINDS) do
    table.insert(PATTERNS, { k[1], pattern(k[2] or k[3]) })
    if k[2] and k[2] ~= k[3] then table.insert(PATTERNS, { k[1], pattern(k[3]) }) end
end

-- The kind of auction house mail, the item name and how many ("Linen Cloth (20)").
function ns.ParseSubject(subject)
    if not subject then return nil end
    for _, p in ipairs(PATTERNS) do
        local rest = subject:match(p[2])
        if rest then
            local name, n = rest:match("^(.-) %((%d+)%)$")
            return p[1], name or rest, tonumber(n)
        end
    end
    return nil
end

function ns.Prune()
    local now = ns.Now()
    for _, e in ipairs(ns.db.entries) do
        if e.n and e.n <= 0 then e.n = 1 end -- 1.0 read commodity sales as 0 sold
    end
    for key, t in pairs(ns.db.seen) do if now - t > KEEP_SEEN then ns.db.seen[key] = nil end end
    for i = #ns.db.posts, 1, -1 do
        if now - (ns.db.posts[i].t or 0) > KEEP_POSTS then table.remove(ns.db.posts, i) end
    end
end

---------------------------------------------------------------------------
-- Postings: the deposit each auction cost
---------------------------------------------------------------------------

local quote        -- the last item the auction house priced a deposit for: { id, name }
local quoting = false

local function itemAt(loc)
    if not (loc and C_Item and C_Item.GetItemID) then return nil end
    local ok, id = pcall(C_Item.GetItemID, loc)
    if not ok or not id then return nil end
    local okName, name = pcall(C_Item.GetItemName, loc)
    return id, okName and name or nil
end

local function deposit(fn, ...)
    if not (C_AuctionHouse and C_AuctionHouse[fn]) then return nil end
    quoting = true
    local ok, d = pcall(C_AuctionHouse[fn], ...)
    quoting = false
    return ok and d or nil
end

local function post(id, name, n, dep, each)
    if not id and not name then return end
    if not name then
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        name = get and get(id) or nil
    end
    ns.LearnItem(name, id)
    table.insert(ns.db.posts, { id = id, name = name, n = n or 1, dep = dep, each = each, t = ns.Now(), c = ns.Char() })
end

local function hookPosting()
    if not (C_AuctionHouse and hooksecurefunc) then return end
    -- The sell window asks for the deposit while the item is still in your bags.
    if C_AuctionHouse.CalculateCommodityDeposit then
        hooksecurefunc(C_AuctionHouse, "CalculateCommodityDeposit", function(id)
            if not quoting and id then quote = { id = id } end
        end)
    end
    if C_AuctionHouse.CalculateItemDeposit then
        hooksecurefunc(C_AuctionHouse, "CalculateItemDeposit", function(loc)
            if quoting then return end
            local id, name = itemAt(loc)
            if id then quote = { id = id, name = name } end
        end)
    end
    if C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(loc, duration, quantity, unitPrice)
            if not ns.db then return end
            local id, name = itemAt(loc)
            if not id and quote then id, name = quote.id, quote.name end
            pcall(post, id, name, quantity, id and deposit("CalculateCommodityDeposit", id, duration, quantity), unitPrice)
        end)
    end
    if C_AuctionHouse.PostItem then
        hooksecurefunc(C_AuctionHouse, "PostItem", function(loc, duration, quantity, bid, buyout)
            if not ns.db then return end
            local id, name = itemAt(loc)
            local dep = id and deposit("CalculateItemDeposit", loc, duration, quantity)
            if not id and quote then id, name = quote.id, quote.name end
            pcall(post, id, name, quantity, dep, buyout and quantity and quantity > 0 and buyout / quantity or nil)
        end)
    end
end

-- The posting an expired or cancelled auction came from: the oldest of that item,
-- the same size if there is one. It's taken off the list.
local function takePost(id, name, n)
    local best
    for i, p in ipairs(ns.db.posts) do
        if (id and p.id == id) or (name and p.name == name) then
            if p.n == n then best = i; break end
            best = best or i
        end
    end
    if best then return table.remove(ns.db.posts, best) end
end

---------------------------------------------------------------------------
-- The mailbox
---------------------------------------------------------------------------

local visit = { sale = 0, buy = 0, expired = 0, income = 0, spent = 0 }

local function isSeen(base, bucket)
    local s = ns.db.seen
    return s[base .. bucket] or s[base .. (bucket - 1)] or s[base .. (bucket + 1)]
end

local function attachment(i)
    if not GetInboxItem then return nil end
    local name, id, _, count = GetInboxItem(i, 1)
    if not id and GetInboxItemLink then
        local link = GetInboxItemLink(i, 1)
        id = link and tonumber(link:match("item:(%d+)"))
    end
    return name, id, count
end

-- Records mail i if it's an auction house mail not recorded before. Returns the entry.
function ns.ReadMail(i)
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    local kind, name, n = ns.ParseSubject(subject)
    if not kind or kind == "outbid" then return nil end -- an outbid refund is your own money back
    money = money or 0
    local now = ns.Now()
    local e = { k = kind, name = name, n = n or 1, c = ns.Char() }

    local inv = {}
    if GetInboxInvoiceInfo then
        local ok, a, b, c, d, e2, f, g, _, _, h = pcall(GetInboxInvoiceInfo, i)
        if ok then inv = { type = a, name = b, who = c, bid = d, buyout = e2, dep = f, cut = g, n = h } end
    end
    if inv.type == "seller_temp_invoice" then return nil end -- sold, but the money isn't here yet

    if kind == "sale" then
        e.name, e.who = inv.name or name, inv.who
        if inv.n and inv.n > 0 then e.n = inv.n end -- commodity invoices can say 0
        if inv.type == "seller" and inv.bid then
            e.g, e.cut, e.dep = inv.bid, inv.cut or 0, inv.dep
        else
            e.g, e.cut = money, 0 -- no invoice: what arrived (the deposit back included)
        end
        e.item = ns.ItemID(e.name)
    elseif kind == "buy" then
        local aName, aID, aCount = attachment(i)
        e.name, e.who = inv.name or aName or name, inv.who
        e.n = (inv.n and inv.n > 0 and inv.n) or aCount or e.n
        e.g = inv.bid or 0
        e.item = aID or ns.ItemID(e.name)
        ns.LearnItem(e.name, e.item)
    else -- expired or cancelled: the item comes back, the deposit doesn't
        local aName, aID, aCount = attachment(i)
        e.name = aName or name
        e.n = aCount or e.n
        e.item = aID or ns.ItemID(e.name)
        ns.LearnItem(e.name, e.item)
    end

    -- A mail's expiry doesn't change, so (rounded) it tells this mail from another just like it.
    local expiry = now + (daysLeft or 0) * 86400
    local base = table.concat({ kind, e.name or "", e.n, money, e.who or "", "" }, "|")
    local bucket = math.floor(expiry / BUCKET)
    if isSeen(base, bucket) then return nil end
    ns.db.seen[base .. bucket] = now

    if kind == "expired" or kind == "cancelled" then
        local p = takePost(e.item, e.name, e.n)
        e.dep = p and p.dep
    end
    local sent = (daysLeft and daysLeft > 0) and (expiry - MAIL_DAYS * 86400) or now
    e.t = math.floor(math.max(now - MAIL_DAYS * 86400, math.min(now, sent)))
    table.insert(ns.db.entries, e)

    if kind == "sale" then
        visit.sale, visit.income = visit.sale + 1, visit.income + (e.g - (e.cut or 0))
    elseif kind == "buy" then
        visit.buy, visit.spent = visit.buy + 1, visit.spent + e.g
    else
        visit.expired = visit.expired + 1
    end
    return e
end

function ns.ReadInbox()
    if not ns.db or not GetInboxNumItems then return end
    local n = GetInboxNumItems() or 0
    local added = 0
    for i = 1, n do
        local ok, e = pcall(ns.ReadMail, i)
        if ok and e then added = added + 1 end
    end
    if ns.ReadMailItems then pcall(ns.ReadMailItems) end
    if ns.Refresh then ns.Refresh() end
    return added
end

-- Leaving the mailbox: what this visit added, in one line.
local function sayVisit()
    if visit.sale + visit.buy + visit.expired > 0 then
        local bits = {}
        if visit.sale > 0 then table.insert(bits, visit.sale .. " sold for " .. ns.Money(visit.income)) end
        if visit.buy > 0 then table.insert(bits, visit.buy .. " bought for " .. ns.Money(visit.spent)) end
        if visit.expired > 0 then table.insert(bits, visit.expired .. " expired") end
        ns.Print(table.concat(bits, ", ") .. ". /mlk for the ledger.")
    end
    visit = { sale = 0, buy = 0, expired = 0, income = 0, spent = 0 }
end

---------------------------------------------------------------------------
-- Your gold
---------------------------------------------------------------------------

function ns.NoteGold()
    if not ns.db or not GetMoney then return end
    ns.db.gold[ns.Char()] = { m = GetMoney(), t = ns.Now() }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "PLAYER_MONEY" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end
local pending = false
f:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        pcall(hookPosting)
        ns.NoteGold()
    elseif event == "PLAYER_MONEY" then
        ns.NoteGold()
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        -- The inbox updates several times as it fills: read it once things settle.
        if not pending then
            pending = true
            C_Timer.After(0.3, function() pending = false; ns.ReadInbox() end)
        end
    elseif event == "MAIL_CLOSED" then
        sayVisit()
    end
end)
