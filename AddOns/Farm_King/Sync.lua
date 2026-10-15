local _, ns = ...
local API = ns.API

-- Sharing drop data with your guild, on request.
--   * "Ask guild" (on any list or mob page) asks for these mobs.
--   * Everyone running Farm King who has killed them answers with their own
--     totals: kills, coin, and per item how often it dropped and how many.
--   * Each guildmate's latest answer replaces their previous one, so asking
--     again never counts the same kills twice. Only your own kills are sent.
-- /fk share off stops you answering.
--
-- Messages (prefix FarmKing1), at most 250 characters, numbers packed like
-- Scanner King's (base 32, each number marks its own end):
--   "R" + npc ID differences                       a request
--   "D" + blocks: npcID, part, kills, coin, item count, then per item:
--       item ID minus the previous one, times dropped, units
-- A mob with a long loot table is split into parts; part 0 starts that
-- guildmate's data for the mob afresh, later parts add to it.

local PREFIX = "FarmKing1"
local MAX_LEN = 250
local SEND_INTERVAL = 1
local MAX_REQUEST = 500

local queue, sending = {}, false
local pending, answerScheduled = {}, false
local got, gotPending = {}, false
local lastPart = {}  -- "sender:npcID" -> the last part received, so a lost part 0 can't mix answers

local function enabled()
    return ns.db and IsInGuild and IsInGuild()
end

local function shortName(sender)
    if Ambiguate then return Ambiguate(sender, "none") end
    return (sender:gsub("%-.*$", ""))
end

---------------------------------------------------------------------------
-- Packing (the same scheme as Scanner King)
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuv"
local LAST = "wxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local digitOf, lastOf = {}, {}
for i = 1, 32 do
    digitOf[DIGITS:sub(i, i)] = i - 1
    lastOf[LAST:sub(i, i)] = i - 1
end

function ns.Pack(n)
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

function ns.Unpack(s)
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

-- mobs: { { id, k, c, i = { [itemID] = { n, q } } }, ... } -> "D" messages
function ns.PackDrops(mobs)
    local msgs, cur = {}, "D"
    local function flush()
        if #cur > 1 then table.insert(msgs, cur) end
        cur = "D"
    end
    for _, m in ipairs(mobs) do
        local items = {}
        for item, e in pairs(m.i or {}) do table.insert(items, { item, e[1] or 0, e[2] or 0 }) end
        table.sort(items, function(a, b) return a[1] < b[1] end)
        local part, idx = 0, 1
        repeat
            -- As many items as fit in what's left of this message (at least a header's worth of room).
            local head = ns.Pack(m.id) .. ns.Pack(part) .. ns.Pack(m.k or 0) .. ns.Pack(m.c or 0)
            if #cur + #head + 2 > MAX_LEN then flush() end
            local body, n, prev = {}, 0, 0
            local room = MAX_LEN - #cur - #head - 2
            while idx <= #items do
                local it = items[idx]
                local s = ns.Pack(it[1] - prev) .. ns.Pack(it[2]) .. ns.Pack(it[3])
                if #s > room then break end
                table.insert(body, s)
                room, prev, n, idx = room - #s, it[1], n + 1, idx + 1
            end
            if n == 0 and idx <= #items then
                flush() -- no room left for even one item: start a fresh message
            else
                cur = cur .. head .. ns.Pack(n) .. table.concat(body)
                part = part + 1
            end
        until idx > #items and part > 0
    end
    flush()
    return msgs
end

function ns.UnpackDrops(body)
    local nums = ns.Unpack(body)
    local out = {}
    if not nums then return out end
    local i = 1
    while i + 4 <= #nums do
        local block = { id = nums[i], part = nums[i + 1], k = nums[i + 2], c = nums[i + 3], i = {} }
        local count = nums[i + 4]
        i = i + 5
        local item = 0
        for _ = 1, count do
            if i + 2 > #nums then return out end
            item = item + nums[i]
            block.i[item] = { nums[i + 1], nums[i + 2] }
            i = i + 3
        end
        table.insert(out, block)
    end
    return out
end

local function packIDs(ids)
    table.sort(ids)
    local msgs, i = {}, 1
    while i <= #ids do
        local parts, len, prev = { "R" }, 1, 0
        while i <= #ids do
            local s = ns.Pack(ids[i] - prev)
            if len + #s > MAX_LEN then break end
            table.insert(parts, s)
            len, prev, i = len + #s, ids[i], i + 1
        end
        table.insert(msgs, table.concat(parts))
    end
    return msgs
end

---------------------------------------------------------------------------
-- Sending, one message a second
---------------------------------------------------------------------------

local function send(text, channel)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return true end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
    local R = Enum and Enum.SendAddonMessageResult
    return not (ok and R and R.AddonMessageThrottle and result == R.AddonMessageThrottle)
end

local function pump()
    local item = table.remove(queue, 1)
    if not item then sending = false; return end
    if not send(item[1], item[2]) then
        table.insert(queue, 1, item)
        C_Timer.After(SEND_INTERVAL * 2, pump)
        return
    end
    C_Timer.After(SEND_INTERVAL, pump)
end

local function enqueue(text, channel)
    table.insert(queue, { text, channel })
    if not sending then sending = true; pump() end
end

-- Asks the guild for drop data on these mobs. Returns mobs asked about and messages, or nil.
function API.RequestDrops(ids)
    if not enabled() then
        ns.Print("You're not in a guild.")
        return nil
    end
    local ask, seen = {}, {}
    for _, id in ipairs(ids or {}) do
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            table.insert(ask, id)
            if #ask >= MAX_REQUEST then break end
        end
    end
    if #ask == 0 then return 0, 0 end
    local msgs = packIDs(ask)
    for _, m in ipairs(msgs) do enqueue(m, "GUILD") end
    return #ask, #msgs
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function answer()
    answerScheduled = false
    local list = {}
    for id in pairs(pending) do
        local m = ns.db.mobs[id]
        if m and (m.k or 0) > 0 then table.insert(list, { id = id, k = m.k, c = m.c, i = m.i }) end
    end
    wipe(pending)
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, msg in ipairs(ns.PackDrops(list)) do enqueue(msg, "GUILD") end
end

local function flushGot()
    gotPending = false
    for who, n in pairs(got) do ns.Print("Got drop data for " .. n .. " mob(s) from " .. who .. ".") end
    wipe(got)
    if ns.Refresh then ns.Refresh() end
end

local function onMessage(text, sender)
    local who = shortName(sender)
    if who == UnitName("player") then return end
    local kind, body = text:sub(1, 1), text:sub(2)
    if kind == "R" then
        if not ns.db.answer then return end
        local id = 0
        for _, d in ipairs(ns.Unpack(body) or {}) do
            id = id + d
            local m = ns.db.mobs[id]
            if m and (m.k or 0) > 0 then pending[id] = true end
        end
        if next(pending) and not answerScheduled then
            answerScheduled = true
            C_Timer.After(1 + math.random() * 4, answer)
        end
    elseif kind == "D" then
        local g = ns.db.guild[who]
        if not g then g = { mobs = {} }; ns.db.guild[who] = g end
        g.t = ns.Now()
        for _, b in ipairs(ns.UnpackDrops(body)) do
            local key = who .. ":" .. b.id
            if b.part == 0 then
                g.mobs[b.id] = { k = b.k, c = b.c, i = {} }
                got[who] = (got[who] or 0) + 1
            elseif lastPart[key] ~= b.part - 1 then
                b = nil -- the start of this answer was missed: keep what we had
            end
            if b then
                lastPart[key] = b.part
                for item, e in pairs(b.i) do g.mobs[b.id].i[item] = e end
            end
        end
        if not gotPending then
            gotPending = true
            C_Timer.After(5, flushGot)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    else
        local prefix, text, channel, sender = ...
        -- Guild chat only: anyone can whisper an addon message.
        if prefix == PREFIX and channel == "GUILD" and sender and ns.db then pcall(onMessage, text, sender) end
    end
end)
