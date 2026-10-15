local _, ns = ...
local API = ns.API

-- Guild price sharing: everyone in your guild running Scanner King shares the
-- prices they scanned, and the newest price for each item wins.
--   * After a scan, your Trade Goods prices (and the raw materials Gather King
--     watches) go to the guild.
--   * When you log in you say hello; guildmates online whisper you theirs.
--   * Anything else is shared only when someone asks (ScannerKing.RequestPrices,
--     Econ King's "Ask guild" buttons). Guildmates who scanned those items
--     answer, and stay quiet about items someone already answered as fresh.
-- Only prices you scanned yourself are sent: the last two days when sharing,
-- the last week when answering. Guildmates' prices are never passed on.
--
-- Messages (prefix ScannerKing1), at most 250 characters each:
--   "H"            hello
--   "Z" + packed   prices
--   "R" + packed   a request for these item IDs
--   "P" id:copper:time;...   the old price format, still read
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
local SHARE_AGE = 2 * 24 * 3600
local ANSWER_AGE = 7 * 24 * 3600
local FRESH = 3600       -- don't ask for items you scanned yourself in the last hour
local MAX_REQUEST = 2000 -- items per request

local queue, sending = {}, false
local repliedTo = {}
local received, receivedFrom, summaryPending = {}, {}, false
local pending, answerScheduled = {}, false -- items we'll answer a request for, unless someone beats us to it

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

-- entries: { { id =, p =, t =, m =, q = }, ... } -> list of "Z" messages.
function ns.PackPrices(entries)
    table.sort(entries, function(a, b) return a.id < b.id end)
    local base = 0
    for _, e in ipairs(entries) do base = math.max(base, e.t) end
    local msgs, i = {}, 1
    local head = "Z" .. ns.PackNumber(base)
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
    local item = table.remove(queue, 1)
    if not item then
        sending = false
        return
    end
    if not send(item[1], item[2], item[3]) then
        table.insert(queue, 1, item)
        C_Timer.After(SEND_INTERVAL * 2, pump)
        return
    end
    C_Timer.After(SEND_INTERVAL, pump)
end

local function enqueue(text, channel, target)
    table.insert(queue, { text, channel, target })
    if not sending then
        sending = true
        pump()
    end
end

local function entry(id, pr)
    return { id = id, p = pr.p, t = pr.t, m = pr.m, q = pr.q }
end

-- Your own recent Trade Goods and watched prices (Deep Scan prices for other items stay with you).
local function sendPrices(channel, target)
    local now, list = ns.Now(), {}
    for id, pr in pairs(ns.db.prices) do
        if not pr.from and not pr.d and pr.t and now - pr.t <= SHARE_AGE then table.insert(list, entry(id, pr)) end
    end
    for _, msg in ipairs(ns.PackPrices(list)) do enqueue(msg, channel, target) end
    return #list
end

function ns.SharePrices(verbose)
    if not enabled() then
        if verbose then ns.Print("Guild sharing is off or you're not in a guild.") end
        return
    end
    local n = sendPrices("GUILD")
    if verbose then ns.Print("Sending " .. n .. " prices to the guild.") end
end

-- Asks the guild for these items. Returns how many were asked for (items you
-- scanned yourself in the last hour are skipped) and how many messages that
-- takes, or nil when sharing is off or you're not in a guild.
function API.RequestPrices(ids)
    if not enabled() then
        ns.Print("Guild sharing is off or you're not in a guild.")
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

local function flushSummary()
    summaryPending = false
    for who, n in pairs(receivedFrom) do
        ns.Print("Got " .. n .. " newer price(s) from " .. who .. ".")
    end
    local batch = received
    received, receivedFrom = {}, {}
    ns.Fire("GUILD_PRICES", batch)
    ns.Fire("PRICES_UPDATED")
end

local function noteReceived(who, id)
    local pr = ns.db.prices[id]
    received[id] = { p = pr.p, m = pr.m, q = pr.q, t = pr.t, from = who }
    receivedFrom[who] = (receivedFrom[who] or 0) + 1
    if not summaryPending then
        summaryPending = true
        C_Timer.After(5, flushSummary)
    end
end

-- Keeps a guildmate's price if it's newer than ours.
local function merge(who, e)
    if not (e.id and e.p and e.p > 0 and e.t) then return end
    -- Someone answered a request with a price at least as fresh as ours: no need to send it too.
    local mine = ns.db.prices[e.id]
    if pending[e.id] and mine and e.t >= mine.t - 60 then pending[e.id] = nil end
    if mine and e.t <= mine.t then return end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    ns.db.prices[e.id] = { p = e.p, m = e.m, q = e.q, t = e.t, from = who,
                           d = (inst and select(6, inst(e.id)) ~= 7) or nil }
    noteReceived(who, e.id)
end

local function answer()
    answerScheduled = false
    if not enabled() then return end
    local list = {}
    for id in pairs(pending) do
        local pr = ns.db.prices[id]
        if pr and not pr.from then table.insert(list, entry(id, pr)) end
    end
    wipe(pending)
    for _, msg in ipairs(ns.PackPrices(list)) do enqueue(msg, "GUILD") end
end

local function onMessage(text, sender)
    local who = shortName(sender)
    if who == UnitName("player") then return end
    local kind, body = text:sub(1, 1), text:sub(2)
    if kind == "H" then
        if repliedTo[who] then return end
        repliedTo[who] = true
        C_Timer.After(2 + math.random() * 6, function() sendPrices("WHISPER", sender) end)
    elseif kind == "Z" then
        for _, e in ipairs(ns.UnpackPrices(body)) do merge(who, e) end
    elseif kind == "R" then
        local now, id = ns.Now(), 0
        for _, d in ipairs(ns.UnpackNumbers(body) or {}) do
            id = id + d
            local pr = ns.db.prices[id]
            if pr and not pr.from and pr.t and now - pr.t <= ANSWER_AGE then pending[id] = true end
        end
        -- Wait a moment: if a guildmate answers first with prices as fresh, we skip those.
        if next(pending) and not answerScheduled then
            answerScheduled = true
            C_Timer.After(1 + math.random() * 4, answer)
        end
    elseif kind == "P" then
        for id, p, t in body:gmatch("(%d+):(%d+):(%d+)") do
            merge(who, { id = tonumber(id), p = tonumber(p), t = tonumber(t) })
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        C_Timer.After(10, function()
            if enabled() then enqueue("H", "GUILD") end
        end)
    else
        local prefix, text, channel, sender = ...
        if prefix == PREFIX and sender and ns.db and ns.db.sync.guild then
            onMessage(text, sender)
        end
    end
end)
