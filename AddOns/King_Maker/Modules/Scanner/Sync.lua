local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API

-- Guild price sharing: everyone in your guild running King Maker shares the
-- prices they scanned, and the newest price for each item wins.
--   * After a scan, your Trade Goods prices (and the items other modules watch)
--     go to the guild.
--   * Everyone remembers the newest scan they hold, theirs or a guildmate's (the
--     scan stamp). At login you ask "Q": guildmates holding a newer scan answer,
--     the freshest first; the first claims you ("C") and the rest stand down. It
--     whispers you every price newer than your stamp, guildmates' too, in the
--     background, then "S" with its stamp. If your scan is the newest, guildmates
--     tell you ("N") and you send it to the guild once.
--   * So a scan reaches everyone who logs in later, as long as one guildmate
--     online has it, not only the people online when it ran.
--   * Anything else is shared only when someone asks (ScannerKing.RequestPrices,
--     Price History's "Ask guild" buttons, and what you loot: an item with no
--     price or one over 6 hours old is asked about once a session, in batches
--     every 30 s). Guildmates holding a price answer, theirs or passed on, and
--     stay quiet about items someone already answered as fresh.
-- Prices of the last two days are passed on; answers to requests go back a week.
-- Deep Scan prices outside Trade Goods stay with you unless "Share my full scans" is on.
--
-- Messages (prefix ScannerKing1), at most 250 characters each:
--   "Q" + packed time         who has a scan newer than this?
--   "C" + packed time + name  I'm catching this guildmate up (my scan is from this time)
--   "N" + packed time         your scan is newer than mine (this time): send it
--   "S" + packed time + name  the prices sent before this complete that guildmate's scan
--   "Z" + packed              prices you scanned
--   "Y" + name + ":" + packed prices that guildmate scanned, passed on
--   "R" + packed              a request for these item IDs
--   "H"                       hello from an older version (answered with "Z")
--   "P" id:copper:time;...    the old price format, still read
--
-- Packing: numbers are written in base 32 and mark their own end: every digit
-- but the last comes from DIGITS, the last one from LAST, so no separators.
-- A "Z" message is the newest scan time, then per item (sorted by ID):
--   ID minus the previous ID, lowest price, minutes older than that time,
--   market price minus lowest plus 1 (0 = none), number listed plus 1 (0 = unknown).
-- A "R" message is just ID differences. A price usually takes 8 to 10 characters.

local PREFIX = "ScannerKing1"
local MAX_LEN = 250
local SEND_INTERVAL = 1 -- the game allows a short burst, then about one addon message per second
local SHARE_AGE = 2 * 24 * 3600 -- prices older than this aren't passed on
local ANSWER_AGE = 7 * 24 * 3600
local FRESH = 3600       -- don't ask for items you scanned yourself in the last hour
local MAX_REQUEST = 2000 -- items per request

local function enabled()
    return ns.db and ns.db.sync.guild and IsInGuild and IsInGuild()
end

local function shortName(sender)
    if Ambiguate then return Ambiguate(sender, "none") end
    return (sender:gsub("%-.*$", ""))
end

---------------------------------------------------------------------------
-- Packing
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuv"
local LAST = "wxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local digitOf, lastOf = {}, {}
for i = 1, 32 do
    digitOf[DIGITS:sub(i, i)] = i - 1
    lastOf[LAST:sub(i, i)] = i - 1
end

function ns.PackNumber(n)
    n = math.max(0, math.floor(n + 0.5))
    local d = n % 32
    local out = LAST:sub(d + 1, d + 1)
    n = math.floor(n / 32)
    while n > 0 do
        d = n % 32
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = math.floor(n / 32)
    end
    return out
end

-- Every number in a packed string, or nil if it isn't one.
function ns.UnpackNumbers(s)
    local nums, v = {}, 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        local d = digitOf[ch]
        if d then
            v = v * 32 + d
        else
            local l = lastOf[ch]
            if not l then return nil end
            table.insert(nums, v * 32 + l)
            v = 0
        end
    end
    return nums
end

-- entries: { { id =, p =, t =, m =, q = }, ... } -> list of "Z" messages (or messages starting with kind).
function ns.PackPrices(entries, kind)
    table.sort(entries, function(a, b) return a.id < b.id end)
    local base = 0
    for _, e in ipairs(entries) do base = math.max(base, e.t) end
    local msgs, i = {}, 1
    local head = (kind or "Z") .. ns.PackNumber(base)
    while i <= #entries do
        local parts, len, prev = { head }, #head, 0
        while i <= #entries do
            local e = entries[i]
            local part = ns.PackNumber(e.id - prev) .. ns.PackNumber(e.p) .. ns.PackNumber((base - e.t) / 60)
                .. ns.PackNumber(e.m and (math.max(0, e.m - e.p) + 1) or 0) .. ns.PackNumber(e.q and (e.q + 1) or 0)
            if len + #part > MAX_LEN then break end
            table.insert(parts, part)
            len, prev, i = len + #part, e.id, i + 1
        end
        table.insert(msgs, table.concat(parts))
    end
    return msgs
end

function ns.UnpackPrices(body)
    local nums = ns.UnpackNumbers(body)
    local out = {}
    if not nums or #nums < 1 then return out end
    local base, id = nums[1], 0
    for j = 2, #nums - 4, 5 do
        id = id + nums[j]
        local p = nums[j + 1]
        table.insert(out, { id = id, p = p, t = base - nums[j + 2] * 60,
            m = nums[j + 3] > 0 and (p + nums[j + 3] - 1) or nil,
            q = nums[j + 4] > 0 and (nums[j + 4] - 1) or nil })
    end
    return out
end

local function packIDs(ids)
    table.sort(ids)
    local msgs, i = {}, 1
    while i <= #ids do
        local parts, len, prev = { "R" }, 1, 0
        while i <= #ids do
            local part = ns.PackNumber(ids[i] - prev)
            if len + #part > MAX_LEN then break end
            table.insert(parts, part)
            len, prev, i = len + #part, ids[i], i + 1
        end
        table.insert(msgs, table.concat(parts))
    end
    return msgs
end


---------------------------------------------------------------------------
-- Sending, one message a second
---------------------------------------------------------------------------

-- Two queues: answers and requests go first, bulk handoffs (catching a guildmate up) trickle behind them.
local queue, bulk, sending = {}, {}, false

-- Returns false if the game throttled the message, so it can be retried.
local function send(text, channel, target)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return true end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel, target)
    local R = Enum and Enum.SendAddonMessageResult
    if ok and R and R.AddonMessageThrottle and result == R.AddonMessageThrottle then
        return false
    end
    return true
end

local function pump()
    local q = queue[1] and queue or bulk
    local item = table.remove(q, 1)
    if not item then
        sending = false
        return
    end
    if not send(item[1], item[2], item[3]) then
        table.insert(q, 1, item)
        C_Timer.After(SEND_INTERVAL * 2, pump)
        return
    end
    C_Timer.After(SEND_INTERVAL, pump)
end

local function enqueue(text, channel, target, background)
    table.insert(background and bulk or queue, { text, channel, target })
    if not sending then
        sending = true
        pump()
    end
end

local function entry(id, pr)
    return { id = id, p = pr.p, t = pr.t, m = pr.m, q = pr.q }
end

---------------------------------------------------------------------------
-- The scan stamp: the newest scan you hold, yours or a guildmate's
---------------------------------------------------------------------------

-- db.sync.stamp = { t = when that scan ran (server time), by = who scanned it }
function ns.Stamp()
    local s = ns.db.sync.stamp
    if not s and ns.db.lastScan then
        s = { t = ns.db.lastScan, by = KM.PlayerName() }
        ns.db.sync.stamp = s
    end
    return s or { t = 0 }
end
API.GuildStamp = function() local s = ns.Stamp() return s.t > 0 and s.t or nil, s.by end

local function setStamp(t, by)
    if t and t > ns.Stamp().t then ns.db.sync.stamp = { t = t, by = by } end
end

---------------------------------------------------------------------------
-- What goes out
---------------------------------------------------------------------------

-- Every price newer than `since` that you may pass on: your own and guildmates' (each keeps who scanned it).
-- Deep Scan prices outside Trade Goods only when "Share my full scans" is on, and then after the rest.
-- Returns { [origin or false] = { entries } } for the shared set and the same for the rest of a full scan.
local function collect(since, ownOnly)
    local now, full = ns.Now(), ns.db.sync.full
    local main, rest, n = {}, {}, 0
    since = math.max(since or 0, now - SHARE_AGE)
    for id, pr in pairs(ns.db.prices) do
        if pr.t and pr.t > since and pr.p and pr.p > 0 and not (ownOnly and pr.from) and (full or not pr.d) then
            local into = pr.d and rest or main
            local key = pr.from or false
            into[key] = into[key] or {}
            table.insert(into[key], entry(id, pr))
            n = n + 1
        end
    end
    return main, rest, n
end

local function queueGroups(groups, channel, target, background)
    -- your own first ("Z"), then each guildmate's ("Y<name>:")
    if groups[false] then
        for _, msg in ipairs(ns.PackPrices(groups[false])) do enqueue(msg, channel, target, background) end
    end
    for origin, list in pairs(groups) do
        if origin then
            for _, msg in ipairs(ns.PackPrices(list, "Y" .. origin .. ":")) do enqueue(msg, channel, target, background) end
        end
    end
end

-- Sends everything newer than `since`, then the "S" stamp that says the batch is complete.
local function sendSince(since, channel, target, background, ownOnly)
    local main, rest, n = collect(since, ownOnly)
    if n == 0 then return 0 end
    queueGroups(main, channel, target, background)
    queueGroups(rest, channel, target, true)
    local s = ns.Stamp()
    if s.t > 0 then enqueue("S" .. ns.PackNumber(s.t) .. (s.by or ""), channel, target, true) end
    return n
end

-- After your own scan: the prices from it go to the guild.
function ns.SharePrices(verbose)
    if not enabled() then
        if verbose then KM.Print(ns, "Guild sharing is off or you're not in a guild.") end
        return
    end
    local n = sendSince(0, "GUILD", nil, false, true)
    if verbose then KM.Print(ns, "Sending " .. n .. " prices to the guild.") end
end

-- Your scans move your stamp; the share itself is called by the scan.
API.RegisterCallback("ScannerSync", function(event, found)
    if event == "SCAN_FINISHED" and (found or 0) > 0 and ns.db then setStamp(ns.Now(), KM.PlayerName()) end
end)

-- Asks the guild for these items. Returns how many were asked for (items you
-- scanned yourself in the last hour are skipped) and how many messages that
-- takes, or nil when sharing is off or you're not in a guild.
function API.RequestPrices(ids)
    if not enabled() then
        KM.Print(ns, "Guild sharing is off or you're not in a guild.")
        return nil
    end
    local now, ask, seen = ns.Now(), {}, {}
    for _, id in ipairs(ids or {}) do
        local pr = ns.db.prices[id]
        if type(id) == "number" and not seen[id] and not (pr and not pr.from and pr.t and now - pr.t < FRESH) then
            seen[id] = true
            table.insert(ask, id)
            if #ask >= MAX_REQUEST then break end
        end
    end
    if #ask == 0 then return 0, 0 end
    local msgs = packIDs(ask)
    for _, msg in ipairs(msgs) do enqueue(msg, "GUILD") end
    return #ask, #msgs
end

-- How many messages sharing these items' prices would take (for the curious).
function API.ShareCost(ids)
    local list = {}
    for _, id in ipairs(ids) do
        local pr = ns.db.prices[id]
        if pr then table.insert(list, entry(id, pr)) end
    end
    return #ns.PackPrices(list), #list
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local received, receivedFrom, summaryPending = {}, {}, false
local pending, answerScheduled = {}, false -- items we'll answer a request for, unless someone beats us to it
local stamps = {} -- sender -> { t, by } from their "S", for the summary line

local function flushSummary()
    summaryPending = false
    for who, n in pairs(receivedFrom) do
        local s = stamps[who]
        if s and s.by and s.by ~= "" and not KM.IsMe(s.by) then
            local whose = (s.by == who) and "their scan" or (s.by .. "'s scan")
            KM.Print(ns, "Synced " .. n .. " newer price(s) from " .. who .. " (" .. whose .. ", " .. API.PriceAge(s.t) .. ").")
        else
            KM.Print(ns, "Got " .. n .. " newer price(s) from " .. who .. ".")
        end
    end
    local batch = received
    received, receivedFrom = {}, {}
    ns.Fire("GUILD_PRICES", batch)
    ns.Fire("PRICES_UPDATED")
end

local function noteReceived(sender, id)
    local pr = ns.db.prices[id]
    received[id] = { p = pr.p, m = pr.m, q = pr.q, t = pr.t, from = pr.from }
    receivedFrom[sender] = (receivedFrom[sender] or 0) + 1
    if not summaryPending then
        summaryPending = true
        C_Timer.After(5, flushSummary)
    end
end

-- Keeps a guildmate's price if it's newer than ours. origin = who scanned it, sender = who sent it.
local function merge(origin, e, sender)
    if not (e.id and e.p and e.p > 0 and e.t) then return end
    if e.t > ns.Now() + 300 then return end -- a clock from the future would win forever
    -- Someone answered a request with a price at least as fresh as ours: no need to send it too.
    local mine = ns.db.prices[e.id]
    if pending[e.id] and mine and e.t >= mine.t - 60 then pending[e.id] = nil end
    if mine and e.t <= mine.t then return end
    if KM.IsMe(origin) then return end -- our own old price coming back
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    ns.db.prices[e.id] = { p = e.p, m = e.m, q = e.q, t = e.t, from = origin,
                           d = (inst and select(6, inst(e.id)) ~= 7) or nil }
    noteReceived(sender or origin, e.id)
end

local function answer()
    answerScheduled = false
    if not enabled() then return end
    -- yours as "Z", guildmates' you hold as "Y<name>:" (2.12: anyone with the price can answer, not only the scanner)
    local groups = {}
    for id in pairs(pending) do
        local pr = ns.db.prices[id]
        if pr and pr.p and pr.t then
            local key = pr.from or false
            groups[key] = groups[key] or {}
            table.insert(groups[key], entry(id, pr))
        end
    end
    wipe(pending)
    queueGroups(groups, "GUILD")
end

---------------------------------------------------------------------------
-- Prices for what you loot (2.12)
---------------------------------------------------------------------------

-- Drops in dungeons and farms are mostly items only a full scan prices. When you loot one you have no price for,
-- or only an old one, King Maker asks the guild for it: collected for half a minute, then one small request.
local LOOT_STALE = 6 * 3600 -- a price older than this is worth asking about
local LOOT_BATCH = 30       -- seconds to collect drops before asking
local lootAsked, lootWant, lootScheduled = {}, {}, false

local function lootPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    -- "%s" (the item link) becomes a capture, "%d" (how many) a number; the escapes above left both alone
    fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
    return "^" .. fmt .. "$"
end
local LOOT_PATTERNS = {}
for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
    local pat = lootPattern(_G[g])
    if pat then table.insert(LOOT_PATTERNS, pat) end
end

-- Worth asking the guild about: can go on the auction house, and you have no fresh price.
local function wantsPrice(id)
    if lootAsked[id] then return false end
    local pr = ns.db.prices[id]
    if pr and pr.t and ns.Now() - pr.t < LOOT_STALE then return false end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if quality == 0 then return false end -- grey: vendor trash
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local classID = inst and select(6, inst(id))
    if classID == 12 then return false end -- quest items
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local bind = info and select(14, info(id))
    if bind == 1 or bind == 4 then return false end -- binds when picked up, quest
    return true
end

local function askLoot()
    lootScheduled = false
    local ids = {}
    for id in pairs(lootWant) do table.insert(ids, id) end
    wipe(lootWant)
    if #ids == 0 or not enabled() or not ns.db.sync.loot then return end
    API.RequestPrices(ids)
end

function ns.OnLoot(text)
    if not (ns.db and ns.db.sync.loot and enabled()) or type(text) ~= "string" then return end
    local link
    for _, pat in ipairs(LOOT_PATTERNS) do
        link = text:match(pat)
        if link then break end
    end
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id or not wantsPrice(id) then return end
    lootAsked[id] = true -- once a session
    lootWant[id] = true
    if not lootScheduled then
        lootScheduled = true
        C_Timer.After(LOOT_BATCH, askLoot)
    end
end

-- Catching up a guildmate who logged in ("Q"): only those holding a newer scan answer, the freshest
-- first, and the first to answer claims it ("C") so the rest stand down.
local serving = {}   -- asker -> { sender =, since = } waiting to answer
local repliedTo = {} -- old-version hello: asker -> when we last answered
local behind = { since = nil, scheduled = false } -- guildmates who told us they're behind our scan

local function serve(asker)
    local job = serving[asker]
    serving[asker] = nil
    if not job or not enabled() then return end
    enqueue("C" .. ns.PackNumber(ns.Stamp().t) .. asker, "GUILD")
    sendSince(job.since, "WHISPER", job.sender, true)
end

local function broadcastNewer()
    behind.scheduled = false
    local since = behind.since
    behind.since = nil
    if since and enabled() then sendSince(since, "GUILD", nil, true) end
end

local function onQuery(who, sender, theirs)
    local mine = ns.Stamp().t
    if mine > theirs + 60 then
        if serving[who] then return end
        serving[who] = { sender = sender, since = theirs }
        -- fresher scans answer sooner: 1 s for a scan from the last hour, up to 5 s for older ones
        local age = math.min(4, (ns.Now() - mine) / 3600)
        C_Timer.After(1 + age + math.random(), function() serve(who) end)
    elseif theirs > mine + 60 then
        -- they hold a newer scan than ours: tell them, and they send it to the guild once
        C_Timer.After(1 + math.random() * 3, function()
            if enabled() then enqueue("N" .. ns.PackNumber(mine), "WHISPER", sender) end
        end)
    end
end

local function onMessage(text, sender)
    local who = shortName(sender)
    if KM.IsMe(who) then return end -- your own message back (full name: Forever has surnames)
    local kind, body = text:sub(1, 1), text:sub(2)
    if kind == "Q" then
        local nums = ns.UnpackNumbers(body)
        if nums and nums[1] then onQuery(who, sender, nums[1]) end
    elseif kind == "C" then
        -- someone claimed this asker; stand down unless our scan is clearly newer than theirs
        local t = body:match("^[0-9a-v]*[w-zA-Z+/]")
        local asker = t and body:sub(#t + 1)
        local claimed = t and ns.UnpackNumbers(t)
        if asker and serving[asker] and claimed and claimed[1] + 300 >= ns.Stamp().t then serving[asker] = nil end
    elseif kind == "N" then
        local nums = ns.UnpackNumbers(body)
        if nums and nums[1] then
            behind.since = math.min(behind.since or nums[1], nums[1])
            if not behind.scheduled then
                behind.scheduled = true
                C_Timer.After(6, broadcastNewer) -- one broadcast for everyone who answered
            end
        end
    elseif kind == "S" then
        local t = body:match("^[0-9a-v]*[w-zA-Z+/]")
        local nums = t and ns.UnpackNumbers(t)
        if nums and nums[1] and nums[1] <= ns.Now() + 300 then
            local by = body:sub(#t + 1)
            if by == "" then by = who end
            stamps[who] = { t = nums[1], by = by }
            setStamp(nums[1], by)
        end
    elseif kind == "H" then
        -- a guildmate on an older version logging in: whisper what we have, once a minute at most
        if repliedTo[who] and ns.Now() - repliedTo[who] < 60 then return end
        repliedTo[who] = ns.Now()
        C_Timer.After(2 + math.random() * 6, function()
            if enabled() then
                local main = collect(0)
                local all = {}
                for _, list in pairs(main) do for _, e in ipairs(list) do table.insert(all, e) end end
                for _, msg in ipairs(ns.PackPrices(all)) do enqueue(msg, "WHISPER", sender, true) end
            end
        end)
    elseif kind == "Z" then
        for _, e in ipairs(ns.UnpackPrices(body)) do merge(who, e, who) end
    elseif kind == "Y" then
        local origin, packed = body:match("^([^:]+):(.*)$")
        if origin then
            for _, e in ipairs(ns.UnpackPrices(packed)) do merge(origin, e, who) end
        end
    elseif kind == "R" then
        local now, id = ns.Now(), 0
        for _, d in ipairs(ns.UnpackNumbers(body) or {}) do
            id = id + d
            local pr = ns.db.prices[id]
            if pr and pr.t and now - pr.t <= ANSWER_AGE and not (pr.from and pr.from == who) then pending[id] = true end
        end
        -- Wait a moment: if a guildmate answers first with prices as fresh, we skip those.
        if next(pending) and not answerScheduled then
            answerScheduled = true
            C_Timer.After(1 + math.random() * 4, answer)
        end
    elseif kind == "P" then
        for id, p, t in body:gmatch("(%d+):(%d+):(%d+)") do
            merge(who, { id = tonumber(id), p = tonumber(p), t = tonumber(t) }, who)
        end
    end
end

-- Asks who holds a newer scan than ours (at login, and with /sk sync pull).
function ns.AskNewest()
    if enabled() then enqueue("Q" .. ns.PackNumber(ns.Stamp().t), "GUILD") end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("CHAT_MSG_LOOT")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        ns.OnLoot((...))
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        C_Timer.After(10, ns.AskNewest)
    else
        local prefix, text, channel, sender = ...
        if prefix == PREFIX and sender and ns.db and ns.db.sync.guild then
            onMessage(text, sender)
        end
    end
end)
