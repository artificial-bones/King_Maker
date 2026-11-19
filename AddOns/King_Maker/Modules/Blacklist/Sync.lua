local _, KM = ...
local ns = KM.Module("Blacklist")

-- Guild sharing: every guildmate running King Maker keeps the same list. Anyone may add, edit or remove; the latest
-- change to an entry wins (its e, server time; on a tie a removal wins, then the larger text, so every copy settles
-- on the same one). A removal travels as a tombstone and is kept 60 days, so a guildmate who missed it can't bring
-- the entry back.
--
-- Messages (prefix KingMaker1, the version check's; guild channel only, never a whisper; each <= 250 bytes):
--   L<count><hash>                 my list's fingerprint: how many entries (live and recent removals) and an
--                                  order-independent hash of them. Once, 25-45 s after login (and when sharing is
--                                  turned on). A guildmate whose fingerprint matches stays silent.
--   Q<name>:<part><parts><count><hash><tag>...   "here is what I hold": to name, from one guildmate whose list
--                                  differs (a random 2-8 s wait; whoever hears a Q for the same name first stands
--                                  down). A tag is 20 bits of one entry's hash. Several parts when the tags don't fit.
--                                  Asking someone whose list is empty sends no tags, and everything at once.
--   W<name>:<part><parts><tag>...  name's answer: "send me these" (the tags of yours I don't have), after name has
--                                  sent the entries of its own that weren't in the Q.
--   E<entry>^<entry>...            entries, as many as fit: a new add, edit or removal goes out at once; the
--                                  exchange above sends only the entries that differ.
--     entry = name~flag~<t><e>~by~editor~note   flag: s scam, n ninja loot, t toxic, o other, x removed. editor is
--             empty when it's the one who added it. Notes and names never contain | ~ ^ (stripped when typed).
-- Numbers are base-32 packed (docs/guild-sync.md). At most 6 messages a minute leave this client, a few answers per
-- 10 minutes; anything one guildmate sends more than 30 times a minute is ignored. Only messages on the guild
-- channel count. Nothing but the list itself is ever sent (no farming data, nothing personal); a player's GUID
-- stays on this client. Without a guild the list is personal and nothing is sent.

local PREFIX = "KingMaker1"
local MAX_LEN = 250
local PER_MIN = 6
local QUEUE_MAX = 80
local LOGIN_DELAY, LOGIN_JITTER = 25, 20
local ASK_MIN, ASK_JITTER = 2, 6
local HOLD = 30
local ANSWER_MAX, ANSWER_WINDOW = 4, 600
local IN_MAX = 30
local SUMMARY_DELAY = 5
local REPOST_GAP = 600
local P = 2147483629          -- a prime under 2^31: every step of the hashes stays exact in a double
local TAG = 1048576           -- 2^20
local DAY = 86400

local function now() return GetTime and GetTime() or 0 end
local function S() return ns.db.settings end

local function sharing()
    return ns.db ~= nil and S().share and ns.InGuild() and ns.GuildKey() ~= nil
end
ns.Sharing = sharing

---------------------------------------------------------------------------
-- Packing (Scanner's base-32 scheme: each number marks its own end)
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuv"
local LAST = "wxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local digitOf, lastOf = {}, {}
for i = 1, 32 do
    digitOf[DIGITS:sub(i, i)] = i - 1
    lastOf[LAST:sub(i, i)] = i - 1
end

local function pack(n)
    n = math.max(0, math.floor((n or 0) + 0.5))
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

local function unpack32(s)
    local nums, v = {}, 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        local d = digitOf[ch]
        if d then
            v = v * 32 + d
            if v > 1e15 then return nil end
        else
            local l = lastOf[ch]
            if not l then return nil end
            nums[#nums + 1] = v * 32 + l
            v = 0
        end
    end
    return nums
end
ns.Pack, ns.Unpack = pack, unpack32

---------------------------------------------------------------------------
-- Entries on the wire, hashes, the fingerprint
---------------------------------------------------------------------------

local function flagOf(e)
    if e.del then return "x" end
    local r = ns.REASON[e.r or ""]
    return r and r.wire or "o"
end

-- One entry as it travels (and as it is hashed: every copy of the same entry gives the same string).
local function wire(e)
    local eb = (e.eb and e.eb ~= e.by) and e.eb or ""
    return (e.n or "") .. "~" .. flagOf(e) .. "~" .. pack(e.t) .. pack(e.e) .. "~" .. (e.by or "") .. "~" .. eb .. "~"
        .. (e.del and "" or (e.note or ""))
end
ns.Wire = wire

-- The note gives way when a long name, adder and editor would push the entry past one message.
function ns.FitNote(e)
    local room = MAX_LEN - 1 - #wire(e) + #(e.note or "")
    if #(e.note or "") > room then e.note = ns.Cut(e.note, math.max(0, room)) end
end

local function strHash(s)
    local v = 7
    for i = 1, #s do v = (v * 31 + s:byte(i)) % P end
    v = (v * 48271) % P
    return (v * 48271) % P
end

local function entryHash(e) return strHash(wire(e)) end
local function tagOf(e) return entryHash(e) % TAG end

-- Counted in the fingerprint and the exchange: live entries, and removals younger than TOMB_DAYS (older ones are
-- forgotten, so a guildmate who already forgot one still matches).
local function counted(e)
    if not e.del then return true end
    return (e.e or 0) >= KM.Now() - ns.TOMB_DAYS * DAY
end

local function fingerprint(entries)
    local n, h = 0, 0
    for _, e in pairs(entries or ns.Entries()) do
        if counted(e) then n, h = n + 1, (h + entryHash(e)) % P end
    end
    return n, h
end
ns.Fingerprint = fingerprint

-- Which of two copies of an entry wins: the later change; a removal on a tie; then the larger text.
local function wins(a, b)
    if (a.e or 0) ~= (b.e or 0) then return (a.e or 0) > (b.e or 0) end
    if (a.del and true or false) ~= (b.del and true or false) then return a.del and true or false end
    return wire(a) > wire(b)
end
ns.Wins = wins

-- "name~flag~te~by~editor~note" -> key, entry; nil when it doesn't look like one.
local function readEntry(s)
    local name, flag, times, by, eb, note = s:match("^([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
    if not name then return nil end
    local n = ns.Name(name)
    if not n or n ~= name then return nil end
    local nums = unpack32(times)
    if not nums or #nums ~= 2 then return nil end
    local t, e = nums[1], nums[2]
    local limit = KM.Now() + DAY
    if t > limit or e > limit then return nil end
    if #by > ns.NAME_MAX or #eb > ns.NAME_MAX or #note > MAX_LEN then return nil end
    if ns.Clean(by) ~= by or ns.Clean(eb) ~= eb or ns.Clean(note) ~= note then return nil end
    local entry = { n = n, t = t, e = e, by = by ~= "" and by or nil, eb = (eb ~= "" and eb ~= by) and eb or nil }
    if flag == "x" then
        entry.del = true
    else
        local r = ns.REASON_BY_WIRE[flag]
        if not r or note == "" then return nil end
        entry.r, entry.note = r.id, note
    end
    return n:lower(), entry
end
ns.ReadEntry = readEntry

-- Takes a guildmate's copy if it wins over ours. Returns "added" | "edited" | "removed" | nil.
local function merge(key, inc)
    local l = ns.List()
    if not l then return nil end
    if inc.del and not counted(inc) then return nil end     -- a removal so old we've forgotten them
    local mine = l.entries[key]
    if mine and not wins(inc, mine) then return nil end
    if mine and wire(mine) == wire(inc) then return nil end
    inc.g = mine and mine.g or nil
    l.entries[key] = inc
    if inc.del then return (mine and not mine.del) and "removed" or nil end
    if not mine or mine.del then return "added" end
    return "edited"
end
ns.Merge = merge

---------------------------------------------------------------------------
-- Sending: one queue, guild channel only, at most PER_MIN a minute
---------------------------------------------------------------------------

local queue, sentAt, lastSend, ticker = {}, {}, -10, nil

local function budget()
    local t, keep = now(), {}
    for _, x in ipairs(sentAt) do if t - x < 60 then keep[#keep + 1] = x end end
    sentAt = keep
    return #sentAt < PER_MIN and t - lastSend >= 1
end

-- false when the game throttled it (it stays queued).
local function send(text)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return true end
    local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "GUILD")
    local R = Enum and Enum.SendAddonMessageResult
    return not (ok and R and R.AddonMessageThrottle and r == R.AddonMessageThrottle)
end

local function pump()
    if #queue > 0 and not sharing() then wipe(queue) end
    if #queue == 0 then
        if ticker then ticker:Cancel(); ticker = nil end
        return
    end
    if not budget() then return end
    if send(queue[1]) then
        table.remove(queue, 1)
        lastSend = now()
        sentAt[#sentAt + 1] = lastSend
    end
end

local function enqueue(text)
    if not sharing() or #text > MAX_LEN or #queue >= QUEUE_MAX then return false end
    queue[#queue + 1] = text
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, function() KM.Safe(pump) end) end
    KM.Safe(pump)
    return true
end
ns.SyncQueue = function() return queue end

-- E messages: as many entries as fit in each.
local function sendEntries(list)
    local cur = "E"
    for _, e in ipairs(list) do
        local w = wire(e)
        if #cur > 1 and #cur + 1 + #w > MAX_LEN then
            enqueue(cur)
            cur = "E"
        end
        if 1 + #w <= MAX_LEN then cur = cur .. (#cur > 1 and "^" or "") .. w end
    end
    if #cur > 1 then enqueue(cur) end
end

-- A local add, edit or removal goes out at once.
function ns.SendEntry(key, e)
    if not sharing() or not e then return end
    sendEntries({ e })
end

-- Tagged messages (Q, W) split into parts: head .. part .. parts .. extra .. tags.
local function sendTagged(head, extra, tags)
    local chunks, cur = {}, {}
    local room = MAX_LEN - #head - 4 - #extra   -- part and parts take at most 2 characters each
    local len = 0
    for _, t in ipairs(tags) do
        local p = pack(t)
        if len + #p > room and #cur > 0 then
            chunks[#chunks + 1] = cur
            cur, len = {}, 0
        end
        cur[#cur + 1] = p
        len = len + #p
    end
    chunks[#chunks + 1] = cur
    if #chunks > 30 then return 0 end
    for i, c in ipairs(chunks) do enqueue(head .. pack(i) .. pack(#chunks) .. extra .. table.concat(c)) end
    return #chunks
end

local lastHello = -REPOST_GAP

-- My fingerprint (login, and when sharing is turned on).
function ns.Hello()
    if not sharing() then return nil end
    lastHello = now()
    local n, h = fingerprint()
    local text = "L" .. pack(n) .. pack(h)
    enqueue(text)
    return text
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local lastL = {}      -- who -> { n, h }: their latest fingerprint
local compared = {}   -- "who:theirs:mine" -> true: asked about this pair already this session
local holds = {}      -- who -> GetTime() a guildmate sent them a Q
local asking = {}     -- who -> our ask's timer is running
local answered = {}   -- "asker:hash:mine" -> true
local answers = {}    -- GetTime() of our recent answers
local partsOf = {}    -- "Q:who" / "W:who" -> { h, parts, got, n, tags }
local inCount = {}    -- who -> { since, n }
local summary = {}    -- who -> { added, edited, removed, names }
local summaryPending = false

local function short(sender)
    if type(sender) ~= "string" or ns.IsSecret(sender) then return nil end
    if Ambiguate then
        local ok, s = pcall(Ambiguate, sender, "none")
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return (sender:gsub("%-.*$", ""))
end

local function allowIn(who)
    local t = now()
    local c = inCount[who]
    if not c or t - c[1] >= 60 then c = { t, 0 }; inCount[who] = c end
    c[2] = c[2] + 1
    return c[2] <= IN_MAX
end

local function heard(who)
    local l = ns.List()
    if l then l.heard[who] = KM.Now() end
end

local function flushSummary()
    summaryPending = false
    for who, s in pairs(summary) do
        local total = s.added + s.edited + s.removed
        if total == 1 then
            local it = s.list[1]
            local verb = it.how == "added" and "added" or (it.how == "removed" and "removed" or "edited")
            KM.Print(ns, who .. " " .. verb .. " " .. ns.RED .. it.name .. "|r" .. (it.how == "added" and " (" .. ns.ReasonLabel(it.r) .. ")" or "")
                .. (it.how == "removed" and " from" or (it.how == "added" and " to" or " on")) .. " the guild blacklist.")
        elseif total > 1 then
            local parts = {}
            if s.added > 0 then parts[#parts + 1] = s.added .. " added" end
            if s.edited > 0 then parts[#parts + 1] = s.edited .. " edited" end
            if s.removed > 0 then parts[#parts + 1] = s.removed .. " removed" end
            KM.Print(ns, "the guild blacklist caught up from " .. who .. ": " .. table.concat(parts, ", ") .. ".")
        end
    end
    wipe(summary)
end

local function noteChange(who, key, how, e)
    local s = summary[who]
    if not s then s = { added = 0, edited = 0, removed = 0, list = {} }; summary[who] = s end
    s[how] = s[how] + 1
    s.list[#s.list + 1] = { how = how, name = e.n, r = e.r }
    if not summaryPending then
        summaryPending = true
        C_Timer.After(SUMMARY_DELAY, flushSummary)
    end
    ns.Changed(key, how, who)
end

local function onEntries(who, body)
    for part in body:gmatch("[^%^]+") do
        local key, e = readEntry(part)
        if key and not KM.IsMe(e.n) then
            local how = merge(key, e)
            if how then noteChange(who, key, how, e) end
        elseif key then
            -- someone listed you: keep the copy so fingerprints match, but say nothing
            merge(key, e)
        end
    end
end

-- Our entries sorted by key, each with its tag (the order is only for stable output).
local function myTagged()
    local list = {}
    for key, e in pairs(ns.Entries()) do
        if counted(e) then list[#list + 1] = { key = key, e = e, tag = tagOf(e) } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local function sendAsk(who)
    local n, h = fingerprint()
    local F = lastL[who]
    local tags = {}
    local dumpAll = F and F.n == 0
    if not dumpAll then
        for _, it in ipairs(myTagged()) do tags[#tags + 1] = it.tag end
    end
    sendTagged("Q" .. who .. ":", pack(n) .. pack(h), tags)
    if dumpAll then
        local list = {}
        for _, it in ipairs(myTagged()) do list[#list + 1] = it.e end
        sendEntries(list)
    end
end

local function differs(who)
    local F = lastL[who]
    if not F then return false end
    local n, h = fingerprint()
    return not (n == F.n and h == F.h)
end

local function checkAsk(who)
    if not sharing() or asking[who] then return end
    local F = lastL[who]
    if not F or not differs(who) then return end
    local _, mine = fingerprint()
    local pair = who .. ":" .. F.h .. ":" .. mine
    if compared[pair] then return end
    asking[who] = true
    C_Timer.After(ASK_MIN + math.random() * ASK_JITTER, function()
        asking[who] = nil
        if not sharing() or not differs(who) then return end
        local hold = holds[who]
        if hold and now() - hold < HOLD then return end   -- a guildmate asked first; their exchange reaches us too
        local F2 = lastL[who]
        local _, mine2 = fingerprint()
        local pair2 = who .. ":" .. F2.h .. ":" .. mine2
        if compared[pair2] then return end
        compared[pair2] = true
        KM.Safe(sendAsk, who)
    end)
end
ns.CheckAsk = checkAsk

local function onHello(who, nums)
    local n, h = nums[1], nums[2]
    if not (n and h) or h >= P or n > 100000 then return end
    lastL[who] = { n = n, h = h }
    checkAsk(who)
end

local function canAnswer(key)
    if answered[key] then return false end
    local t, keep = now(), {}
    for _, x in ipairs(answers) do if t - x < ANSWER_WINDOW then keep[#keep + 1] = x end end
    answers = keep
    if #answers >= ANSWER_MAX then return false end
    answered[key] = true
    answers[#answers + 1] = t
    return true
end

-- Collects the parts of a Q or W; returns the whole tag set once every part is in.
local function collect(kind, who, h, part, parts, tags)
    local id = kind .. ":" .. who
    local p = partsOf[id]
    if not p or p.h ~= h or p.parts ~= parts then
        p = { h = h, parts = parts, got = {}, n = 0, tags = {} }
        partsOf[id] = p
    end
    if p.got[part] then return nil end
    p.got[part], p.n = true, p.n + 1
    for _, t in ipairs(tags) do p.tags[t] = true end
    if p.n < p.parts then return nil end
    partsOf[id] = nil
    return p.tags
end

-- A Q to us: send the entries of ours they don't hold, then ask (W) for the ones of theirs we don't.
local function onAsk(asker, nums)
    local part, parts, n, h = nums[1], nums[2], nums[3], nums[4]
    if not (part and parts and n and h) or parts < 1 or parts > 30 or part < 1 or part > parts or h >= P then return end
    local tags = {}
    for j = 5, #nums do tags[#tags + 1] = nums[j] end
    local theirs = collect("Q", asker, h, part, parts, tags)
    if not theirs or not sharing() then return end
    local _, mine = fingerprint()
    if mine == h then return end
    if not canAnswer(asker .. ":" .. h .. ":" .. mine) then return end
    local send, have = {}, {}
    for _, it in ipairs(myTagged()) do
        have[it.tag] = true
        if not theirs[it.tag] then send[#send + 1] = it.e end
    end
    sendEntries(send)
    local want = {}
    for t in pairs(theirs) do if not have[t] then want[#want + 1] = t end end
    table.sort(want)
    if #want > 0 then sendTagged("W" .. asker .. ":", "", want) end
end

-- A W to us: send the entries they asked for (if we still hold them as they were).
local function onWant(who, nums)
    local part, parts = nums[1], nums[2]
    if not (part and parts) or parts < 1 or parts > 30 or part < 1 or part > parts then return end
    local tags = {}
    for j = 3, #nums do tags[#tags + 1] = nums[j] end
    local want = collect("W", who, 0, part, parts, tags)
    if not want or not sharing() then return end
    local send = {}
    for _, it in ipairs(myTagged()) do if want[it.tag] then send[#send + 1] = it.e end end
    sendEntries(send)
end

local function onMessage(text, channel, sender)
    if not ns.db then return end
    if ns.IsSecret(text) or ns.IsSecret(channel) or ns.IsSecret(sender) then return end
    if channel ~= "GUILD" or type(text) ~= "string" or #text < 2 or #text > 255 then return end
    local kind = text:sub(1, 1)
    if kind ~= "L" and kind ~= "Q" and kind ~= "W" and kind ~= "E" then return end   -- V R: the version check
    if not (S().share and ns.GuildKey()) then return end                              -- sharing off: not read
    local who = short(sender)
    if not who or KM.IsMe(who) then return end                                        -- your own message back
    if not allowIn(who) then return end
    heard(who)
    local body = text:sub(2)
    if kind == "E" then onEntries(who, body) return end
    if kind == "Q" or kind == "W" then
        local name, rest = body:match("^([^:]+):(.*)$")
        local nums = rest and unpack32(rest)
        if not (name and nums) or #name > ns.NAME_MAX then return end
        if not KM.IsMe(name) then
            if kind == "Q" then holds[name] = now() end
            return
        end
        if kind == "Q" then onAsk(who, nums) else onWant(who, nums) end
        return
    end
    local nums = unpack32(body)
    if nums then onHello(who, nums) end
end

---------------------------------------------------------------------------
-- Settings, events, tests
---------------------------------------------------------------------------

function ns.SetShare(on)
    S().share = on and true or false
    if not on then wipe(queue) return end
    if sharing() and now() - lastHello >= REPOST_GAP then
        C_Timer.After(ASK_MIN + math.random() * ASK_JITTER, function() KM.Safe(ns.Hello) end)
    end
end

-- Guildmates heard from (name -> last time), for the page.
function ns.Heard()
    local l = ns.List()
    return l and l.heard or {}
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
        KM.Safe(ns.Purge)
        C_Timer.After(LOGIN_DELAY + math.random() * LOGIN_JITTER, function() KM.Safe(ns.Hello) end)
    elseif event == "CHAT_MSG_ADDON" then
        if ns.IsSecret(prefix) or prefix ~= PREFIX then return end
        pcall(onMessage, text, channel, sender)   -- a malformed message is dropped quietly
    end
end)

function ns.SyncState()
    return { lastL = lastL, compared = compared, holds = holds, answers = answers, sentAt = sentAt, queue = queue }
end
function ns.SyncReset()
    wipe(lastL); wipe(compared); wipe(holds); wipe(asking); wipe(answered); wipe(partsOf); wipe(inCount)
    wipe(queue); wipe(summary); answers = {}; sentAt = {}; lastSend = -10; lastHello = -REPOST_GAP
end
ns.TagOf = tagOf
