local _, KM = ...
local ns = KM.Module("Mail")

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
-- Postings: when you put something up, Mail King notes the deposit and your
-- price, so an auction that comes back expired shows what it cost you and what
-- you were asking (to compare with the market).

local KEEP_SEEN = 35 * 86400   -- mail keys kept (mail lasts 30 days)
local KEEP_POSTS = 3 * 86400   -- postings kept (auctions last at most 48 hours)
local MAIL_DAYS = 30           -- auction house mail lasts this long
local BUCKET = 60              -- seconds: a mail's expiry, to the minute, is part of its key
local LEGACY_BUCKET = 600      -- 2.5.x keys held the expiry to 10 minutes

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

local function itemAt(loc)
    if not (loc and C_Item and C_Item.GetItemID) then return nil end
    local ok, id = pcall(C_Item.GetItemID, loc)
    if not ok or not id then return nil end
    local okName, name = pcall(C_Item.GetItemName, loc)
    return id, okName and name or nil
end

local function deposit(fn, ...)
    if not (C_AuctionHouse and C_AuctionHouse[fn]) then return nil end
    local ok, d = pcall(C_AuctionHouse[fn], ...)
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

-- Watching the sell window's Post button, not the auction house functions:
-- hooking C_AuctionHouse.PostItem (even with hooksecurefunc) taints it, and the
-- game then blocks the real post and blames Mail King. A script hook on the
-- button is safe. The window is read as you press the button (before it
-- clears), and the post is noted when the click goes through.

local function call(frame, method)
    if type(frame[method]) ~= "function" then return nil end
    local ok, v = pcall(frame[method], frame)
    if ok then return v end
end

local function snapshot(frame, commodity)
    local btn = frame.PostButton
    if btn and btn.IsEnabled and not btn:IsEnabled() then return nil end
    local loc = call(frame, "GetItem")
    local id, name = itemAt(loc)
    if not id then return nil end
    local n = call(frame, "GetQuantity") or 1
    local duration = call(frame, "GetDuration") or 1
    local dep = call(frame, "GetDepositAmount")
    local each
    if commodity then
        each = call(frame, "GetUnitPrice")
        dep = dep or deposit("CalculateCommodityDeposit", id, duration, n)
    else
        local buyout = call(frame, "GetBuyout")
        each = buyout and n > 0 and buyout / n or nil
        dep = dep or deposit("CalculateItemDeposit", loc, duration, n)
    end
    return { id = id, name = name, n = n, dep = dep, each = each }
end

local watched = {}
local function watch(frame, commodity)
    local btn = frame and frame.PostButton
    if not btn or watched[btn] or not btn.HookScript then return end
    watched[btn] = true
    local pendingPost
    btn:HookScript("OnMouseDown", function() pendingPost = snapshot(frame, commodity) end)
    btn:HookScript("OnClick", function()
        local p = pendingPost or snapshot(frame, commodity)
        pendingPost = nil
        if p and ns.db then pcall(post, p.id, p.name, p.n, p.dep, p.each) end
    end)
end

function ns.WatchPosting()
    local ah = AuctionHouseFrame
    if not ah then return end
    watch(ah.CommoditiesSellFrame, true)
    watch(ah.ItemSellFrame, false)
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

local visit = { sale = 0, buy = 0, expired = 0, income = 0, spent = 0, sold = {} }

-- 2.6.0: one mail, one entry. The old key held two things that change while a mail sits in the inbox (the buyer's
-- name, which the invoice fills in a moment later, and the money, which goes when you take it), so the same sale
-- could be recorded two or three times. The key is now kind|name|n|amount| + the expiry to the minute (daysLeft is
-- fractional, so a mail's expiry is exact to about a second), where amount is a sale's own figure (the invoice's
-- bid - cut + deposit, which is the money it brought) and 0 for every other kind; n is the subject's count (the
-- invoice's can change as it loads). Identical mails in the inbox together are told apart by their order: "#2", "#3".
-- A mail recorded under the old key (2.5.x) is still recognised.

local recorded = {} -- this session: seen key -> its entry, so a buyer's name that loads later goes on that entry

-- The seen key matching base + bucket (or the minute either side) + suffix, if there is one.
local function isSeen(base, bucket, suffix)
    local s = ns.db.seen
    for b = bucket - 1, bucket + 1 do
        local key = base .. b .. suffix
        if s[key] then return key end
    end
end

-- The distinct values given, nils left out.
local function variants(...)
    local out, have = {}, {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and not have[v] then have[v] = true; table.insert(out, v) end
    end
    return out
end

-- A 2.5.x key: kind|name|n|money|who| + the expiry to 10 minutes. The name, count, money and buyer the mail had
-- when it was recorded may each have changed since, so every combination it could have had is tried.
local function legacySeen(kind, names, counts, moneys, whos, expiry)
    local bucket = math.floor(expiry / LEGACY_BUCKET)
    for _, name in ipairs(names) do
        for _, n in ipairs(counts) do
            for _, m in ipairs(moneys) do
                for _, who in ipairs(whos) do
                    if isSeen(table.concat({ kind, name, n, m, who, "" }, "|"), bucket, "") then return true end
                end
            end
        end
    end
    return false
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
-- met: this read of the inbox's tally of keys so far (ReadInbox passes one), which numbers identical mails.
function ns.ReadMail(i, met)
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

    local amount = 0 -- a sale's own figure, for its key: what it brought
    if kind == "sale" then
        e.name, e.who = inv.name or name, inv.who
        if inv.n and inv.n > 0 then e.n = inv.n end -- commodity invoices can say 0
        if inv.type == "seller" and inv.bid then
            e.g, e.cut, e.dep = inv.bid, inv.cut or 0, inv.dep
            amount = inv.bid - (inv.cut or 0) + (inv.dep or 0)
        else
            if money <= 0 then return nil end -- no invoice and the gold already taken: nothing to learn from it
            e.g, e.cut = money, 0 -- no invoice: what arrived (the deposit back included)
            amount = money
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

    -- A mail's expiry doesn't change, so (to the minute) it tells this mail from another just like it.
    local expiry = now + (daysLeft or 0) * 86400
    local base = table.concat({ kind, name or "", n or 1, amount, "" }, "|")
    local bucket = math.floor(expiry / BUCKET)
    -- Which of the mails just like it (same key, expiry within a minute) in this read of the inbox it is.
    met = met or {}
    local buckets = met[base] or {}
    met[base] = buckets
    local nth = 1
    for _, b in ipairs(buckets) do if math.abs(b - bucket) <= 1 then nth = nth + 1 end end
    table.insert(buckets, bucket)
    local suffix = nth > 1 and ("#" .. nth) or ""
    local key = base .. bucket .. suffix

    local found = isSeen(base, bucket, suffix)
    if found then
        -- Recorded before the invoice named the buyer: the name goes on that entry.
        local old = recorded[found]
        if old and (old.who or "") == "" and e.who and e.who ~= "" then old.who = e.who end
        return nil
    end
    if legacySeen(kind, variants(e.name or "", name or ""), variants(e.n, n or 1), variants(money, amount),
        variants(e.who or "", ""), expiry) then
        ns.db.seen[key] = now
        return nil
    end
    ns.db.seen[key] = now
    recorded[key] = e

    if kind == "expired" or kind == "cancelled" then
        local p = takePost(e.item, e.name, e.n)
        e.dep, e.each = p and p.dep, p and p.each
    end
    local sent = (daysLeft and daysLeft > 0) and (expiry - MAIL_DAYS * 86400) or now
    e.t = math.floor(math.max(now - MAIL_DAYS * 86400, math.min(now, sent)))
    table.insert(ns.db.entries, e)

    if kind == "sale" then
        visit.sale, visit.income = visit.sale + 1, visit.income + (e.g - (e.cut or 0))
        table.insert(visit.sold, e)
    elseif kind == "buy" then
        visit.buy, visit.spent = visit.buy + 1, visit.spent + e.g
    else
        visit.expired = visit.expired + 1
    end
    if ns.Fire then
        local copy = {}
        for k, v in pairs(e) do copy[k] = v end
        ns.Fire("ENTRY", copy)
    end
    return e
end

function ns.ReadInbox()
    if not ns.db or not GetInboxNumItems then return end
    local n = GetInboxNumItems() or 0
    local added, met = 0, {}
    for i = 1, n do
        local ok, e = pcall(ns.ReadMail, i, met)
        if ok and e then added = added + 1 end
    end
    if ns.Refresh then ns.Refresh() end
    return added
end

-- Leaving the mailbox: what this visit added, in one line.
local function sayVisit()
    if visit.sale + visit.buy + visit.expired > 0 then
        local bits = {}
        if visit.sale > 0 then
            -- with Profit & Loss, what those sales made (the ones it could match to a cost)
            local pl, any = 0, false
            if ProfitKing and ProfitKing.ForMail then
                for _, e in ipairs(visit.sold) do
                    local x = KM.Safe(ProfitKing.ForMail, e)
                    if x and x.pl then pl, any = pl + x.pl, true end
                end
            end
            table.insert(bits, visit.sale .. " sold for " .. ns.Money(visit.income) .. (any and (" (P&L " .. (pl >= 0 and "+" or "") .. ns.Money(pl) .. ")") or ""))
        end
        if visit.buy > 0 then table.insert(bits, visit.buy .. " bought for " .. ns.Money(visit.spent)) end
        if visit.expired > 0 then table.insert(bits, visit.expired .. " expired") end
        KM.Print(ns, table.concat(bits, ", ") .. ". /mlk for the ledger.")
    end
    visit = { sale = 0, buy = 0, expired = 0, income = 0, spent = 0, sold = {} }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "ADDON_LOADED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end
local pending = false
f:SetScript("OnEvent", function(_, event, arg)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        pcall(ns.WatchPosting)
    elseif event == "AUCTION_HOUSE_SHOW" or (event == "ADDON_LOADED" and arg == "Blizzard_AuctionHouseUI") then
        pcall(ns.WatchPosting)
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
