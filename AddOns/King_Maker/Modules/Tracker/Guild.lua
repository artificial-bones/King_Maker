local _, KM = ...
local ns = KM.Module("Tracker")
local UI = KM.UI
local C = UI.C

-- Guild bests (King Maker 2.7): the best gold per hour at each farm (a zone and what you did there, as Trends defines
-- it) across your guild, on the Farming Ledger's Guild tab. Guildmates running King Maker share only their personal
-- bests, never sessions: each character's top 20 farms out of its sessions with 10+ active minutes (not carried
-- over) from the last 60 days (the "Forget guild bests after" setting).
--
-- Kept light on the guild channel (prefix KingMaker1, the version check's, guild channel only, never a whisper):
--   F<count><hash>[<digest>...]   my fingerprint: how many bests I share and a hash of them. Once, 25-45 s after
--                                 login, with a digest (a 4-character tag per guildmate whose bests I hold, made of
--                                 their name and the fingerprint I hold for them); again without one when a login
--                                 digest shows that guildmate is behind on me (at most every 10 minutes).
--   A<name>:<held><code><tag>...  "send me what differs": to name, from a guildmate whose copy doesn't match name's
--                                 fingerprint; held = the fingerprint they hold, then each farm they hold (zone and
--                                 activity code + a tag of its numbers). One asks (a random 2-8 s wait; whoever
--                                 hears an ask for the same name first stands down, and looks again once after it)
--   B<prev><new><part><parts><entries>   bests: a new personal best (sent 5 s after the session that set it is
--                                 saved; a session that sets none sends nothing), or the answer to an ask: only the
--                                 farms that differ. Each entry: code (mapID x 8 + activity), silver per hour, active
--                                 minutes, day, top item, level; silver 0 = "no longer one of mine". Whoever held
--                                 the fingerprint prev and gets every part now holds new.
-- Numbers are base-32 packed (guild-sync.md); every message <= 250 characters. At most 6 messages a minute leave
-- this client, a few answers per 10 minutes; anything sent more than 30 times a minute by one guildmate is ignored.
-- Only your own bests ever leave; nobody forwards a guildmate's.
--
-- Saved: TrackerKingDB.guild[guild-realm][name] = { t = last heard, f = fingerprint held, c = class,
--   farms = { ["1429:Mobs"] = { m = mapID, a = activity, g = copper/hr (whole silver), n = active minutes,
--   t = session day (midday, server time), i = top item, l = level } } }. Entries older than guildDays go, and so do
-- members who left the guild (when the roster has loaded). Your own bests are worked out from your sessions.
-- Settings > Farm Tracker: guildShare (send and answer), guildShow (read and show), guildDays. /farm guild.

local PREFIX = "KingMaker1"
local MAX_LEN = 250
local TOP = 20                        -- bests a character shares, and keeps of each guildmate
local PER_MIN = 6                     -- messages a minute this client sends, all kinds together
local QUEUE_MAX = 12
local LOGIN_DELAY, LOGIN_JITTER = 25, 20
local ASK_MIN, ASK_JITTER = 2, 6
local HOLD = 30                       -- someone else asked for that guildmate: wait for their answer
local REPOST_GAP = 600
local FLUSH_DELAY = 5
local ANSWER_MAX, ANSWER_WINDOW = 4, 600
local IN_MAX = 30                     -- messages a minute read from one guildmate
local DIGEST_MAX = 50
local P = 2147483629                  -- a prime under 2^31: every step of the hashes stays exact in a double
local TAG = 1048576                   -- 2^20: the short tags in asks and digests
local DAY = 86400
local DASH = "|cff808080-|r"

local ACTS = { "Mobs", "Mixed", "Mining", "Herbalism", "Fishing", "Treasure", "Containers" }
local ACT_CODE = {}
for i, a in ipairs(ACTS) do ACT_CODE[a] = i end
ns.GUILD_ACTS = ACTS

local function S() return ns.db.settings end
local function U() return ns.db.ui end
local function now() return GetTime and GetTime() or 0 end
local function days() return (ns.db and S().guildDays) or 60 end

local function inGuild() return IsInGuild and KM.Plain(IsInGuild()) and true or false end
local function sharing() return ns.db ~= nil and S().guildShare and inGuild() end
local function showing() return ns.db ~= nil and S().guildShow and true or false end
ns.GuildSharing, ns.GuildShowing = sharing, showing

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
ns.GuildPack, ns.GuildUnpack = pack, unpack32

---------------------------------------------------------------------------
-- Bests, fingerprints and tags
---------------------------------------------------------------------------

local function dayOf(t) return math.floor((t or 0) / DAY) end
local function bare(name) return (tostring(name or ""):gsub("%-.*$", "")):lower() end

-- The six numbers an entry travels as.
local function wire(e)
    return (e.m or 0) * 8 + (ACT_CODE[e.a] or 0), math.floor((e.g or 0) / 100 + 0.5), e.n or 0, dayOf(e.t), e.i or 0, e.l or 0
end

local function mix(v, x) return (v * 10007 + (x % P)) % P end

local function entryHash(e)
    local code, gs, n, d, i, l = wire(e)
    local v = code % P
    v = mix(mix(mix(mix(mix(v, gs), n), d), i), l)
    v = (v * 48271) % P
    return (v * 48271) % P
end

-- How many bests and a hash of them (a sum: the order doesn't matter).
local function fingerprint(farms)
    local n, h = 0, 0
    for _, e in pairs(farms or {}) do n, h = n + 1, (h + entryHash(e)) % P end
    return n, h
end
ns.GuildFingerprint = fingerprint

local function nameTag(name, f)
    local v = (f or 0) % P
    local s = bare(name)
    for i = 1, #s do v = (v * 31 + s:byte(i)) % P end
    return ((v * 48271) % P) % TAG
end

local function sortBests(list)
    table.sort(list, function(a, b)
        if (a.g or 0) ~= (b.g or 0) then return (a.g or 0) > (b.g or 0) end
        return a.key < b.key
    end)
end

local function topItem(s)
    local best, bestV
    for id, it in pairs(s.items or {}) do
        if (it.v or 0) > (bestV or 0) then best, bestV = id, it.v end
    end
    return best
end

-- A character's shared bests, worked out from its sessions: { [farmKey] = entry }, at most TOP.
function ns.MyBests(char)
    char = char or KM.Char()
    local cutoff = KM.Now() - days() * DAY
    local best = {}
    for _, s in ipairs(ns.db.sessions) do
        if s.c == char and (s.t1 or 0) >= cutoff then
            local g = ns.BestRate(s)
            local key, what
            if g then key, what = ns.FarmKey(s) end
            local map = key and ns.MainZone(s)
            if key and ACT_CODE[what] and map and map > 0 and (not best[key] or g > best[key].gph) then
                best[key] = { gph = g, s = s, what = what, map = map }
            end
        end
    end
    local list = {}
    for key, b in pairs(best) do
        local gs = math.floor(b.gph / 100 + 0.5)
        if gs >= 1 then
            list[#list + 1] = { key = key, m = b.map, a = b.what, g = gs * 100, n = math.floor((b.s.act or 0) / 60),
                t = dayOf(b.s.t1) * DAY + DAY / 2, i = topItem(b.s), l = tonumber(b.s.lvl) }
        end
    end
    sortBests(list)
    local out = {}
    for i = 1, math.min(TOP, #list) do
        local e = list[i]
        out[e.key] = e
        e.key = nil
    end
    return out
end

---------------------------------------------------------------------------
-- The store: guildmates' bests per guild
---------------------------------------------------------------------------

local function guildKey()
    if not inGuild() or not GetGuildInfo then return nil end
    local ok, name = pcall(GetGuildInfo, "player")
    name = ok and KM.Plain(name) or nil
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. ((GetRealmName and GetRealmName()) or "")
end

function ns.GuildStore(create)
    if not ns.db then return nil end
    local key = guildKey()
    if not key then return nil end
    ns.db.guild = ns.db.guild or {}
    if create and not ns.db.guild[key] then ns.db.guild[key] = {} end
    return ns.db.guild[key], key
end

-- The guild roster by lower-case name without realm: { class, level }; nil until it has loaded (you're always on it).
local rosterCache, rosterAt
local function roster()
    if rosterCache and now() - rosterAt < 60 then return rosterCache end
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
    local ok, n = pcall(GetNumGuildMembers)
    n = ok and tonumber(KM.Plain(n)) or 0
    if n <= 0 then return nil end
    local names, me = {}, false
    for i = 1, math.min(n, 2000) do
        local ok2, name, _, _, level, _, _, _, _, _, _, class = pcall(GetGuildRosterInfo, i)
        name = ok2 and KM.Plain(name) or nil
        if type(name) == "string" then
            names[bare(name)] = { class = KM.Plain(class), level = KM.Plain(level) }
            if KM.IsMe(name) then me = true end
        end
    end
    if not me then return nil end
    rosterCache, rosterAt = names, now()
    return names
end
function ns.GuildRosterReset() rosterCache = nil end

-- Forgets entries older than guildDays, and guildmates who left (once the roster has loaded).
function ns.GuildPrune()
    if not (ns.db and ns.db.guild) then return end
    local cutoff = KM.Now() - days() * DAY
    local _, current = ns.GuildStore()
    local list = current and roster()
    for gk, members in pairs(ns.db.guild) do
        if type(members) ~= "table" then
            ns.db.guild[gk] = nil
        else
            for name, m in pairs(members) do
                if type(m) ~= "table" then
                    members[name] = nil
                else
                    for key, e in pairs(m.farms or {}) do
                        if type(e) ~= "table" or (e.t or 0) < cutoff then m.farms[key] = nil end
                    end
                    local left = list and gk == current and not list[bare(name)]
                    if left or (next(m.farms or {}) == nil and (m.t or 0) < cutoff) then members[name] = nil end
                end
            end
            if next(members) == nil then ns.db.guild[gk] = nil end
        end
    end
end

-- Keeps a guildmate's best TOP, as they do.
local function capTop(farms)
    local list = {}
    for key, e in pairs(farms) do e.key = key; list[#list + 1] = e end
    sortBests(list)
    for i, e in ipairs(list) do
        if i > TOP then farms[e.key] = nil end
        e.key = nil
    end
end

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
    if #queue > 0 and not sharing() then wipe(queue) end   -- sharing turned off: nothing more leaves
    if #queue == 0 then
        if ticker then ticker:Cancel(); ticker = nil end
        return
    end
    if not budget() then return end                         -- the ticker comes back in a second
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
function ns.GuildQueue() return queue end

local function encodeEntry(e)
    local code, gs, n, d, i, l = wire(e)
    return pack(code) .. pack(gs) .. pack(n) .. pack(d) .. pack(i) .. pack(l)
end

local function encodeDrop(code) return pack(code) .. "wwwww" end   -- silver 0: no longer one of mine

-- B messages: entries split greedily, each message with the same prev/new and its part of parts. Returns the texts.
local function packBests(prev, new, entries)
    local head = "B" .. pack(prev) .. pack(new)
    local chunks, cur, len = {}, {}, #head + 2
    for _, s in ipairs(entries) do
        if len + #s > MAX_LEN and #cur > 0 then
            chunks[#chunks + 1] = cur
            cur, len = {}, #head + 2
        end
        cur[#cur + 1] = s
        len = len + #s
    end
    chunks[#chunks + 1] = cur
    local out = {}
    for i, c in ipairs(chunks) do out[i] = head .. pack(i) .. pack(#chunks) .. table.concat(c) end
    return out
end
ns.GuildPackBests = packBests

local function sendBests(prev, new, entries)
    for _, text in ipairs(packBests(prev, new, entries)) do enqueue(text) end
end

local announced, announcedHash        -- my bests as the guild last heard them from me, and their hash

local function snapshot()
    announced = ns.MyBests()
    local _, h = fingerprint(announced)
    announcedHash = h
    return announced, h
end

-- My fingerprint; withDigest adds a tag for each guildmate whose bests I hold (login only).
function ns.GuildHello(withDigest)
    if not sharing() then return nil end
    local mine, h = snapshot()
    local n = fingerprint(mine)
    local text = "F" .. pack(n) .. pack(h)
    if withDigest and showing() then
        local list = {}
        for name, m in pairs(ns.GuildStore() or {}) do if m.f then list[#list + 1] = { name = name, t = m.t or 0, f = m.f } end end
        table.sort(list, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.name < b.name end)
        for i = 1, math.min(DIGEST_MAX, #list) do
            local tag = pack(nameTag(list[i].name, list[i].f))
            if #text + #tag > MAX_LEN then break end
            text = text .. tag
        end
    end
    enqueue(text)
    return text
end

-- A session was saved: a new personal best goes out as one short B (a session that sets none sends nothing).
local flushPending = false
local function flush()
    flushPending = false
    if not sharing() then return end
    if not announced then snapshot() return end
    local mine = ns.MyBests()
    local _, h = fingerprint(mine)
    if h == announcedHash then return end
    local entries = {}
    for key, e in pairs(mine) do
        local old = announced[key]
        if not old or entryHash(old) ~= entryHash(e) then entries[#entries + 1] = encodeEntry(e) end
    end
    for key, e in pairs(announced) do
        if not mine[key] then entries[#entries + 1] = encodeDrop((wire(e))) end
    end
    local prev = announcedHash
    announced, announcedHash = mine, h
    if #entries > 0 then sendBests(prev, h, entries) end
end
ns.GuildFlush = flush

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local lastF = {}      -- who -> { n, h }: their latest fingerprint
local compared = {}   -- who -> the fingerprint we already asked about this session
local holds = {}      -- who -> GetTime() a guildmate asked for them
local waited = {}     -- who -> fingerprint we already waited out a guildmate's ask for
local asking = {}     -- who -> our ask's timer is running
local answered = {}   -- "asker:held:mine" -> true
local answers = {}    -- GetTime() of our recent answers
local partsOf = {}    -- who -> { prev, new, count, got, n, sync }
local inCount = {}    -- who -> { since, n }
local lastRepost = -REPOST_GAP
local records = {}    -- who -> { lines }: new guild records for one chat line after 5 s
local recordPending = false

local function short(sender)
    if type(sender) ~= "string" or (issecretvalue and issecretvalue(sender)) then return nil end
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

local redrawPending, redrawAfterCombat = false, false
local function redraw()
    if InCombatLockdown and InCombatLockdown() then redrawAfterCombat = true return end   -- no UI work in combat
    if redrawPending then return end
    redrawPending = true
    C_Timer.After(1, function()
        redrawPending = false
        if InCombatLockdown and InCombatLockdown() then redrawAfterCombat = true return end
        if ns.db and ns.Tab and ns.Tab() == "guild" then KM.Refresh("farming") end
    end)
end

local function heldFor(who)
    local store = ns.GuildStore()
    return store and store[who]
end

-- Is our copy of who's bests behind their fingerprint?
local function behind(who)
    local F = lastF[who]
    if not F then return false end
    local m = heldFor(who)
    if m and m.f == F.h then return false end
    local n, h = fingerprint(m and m.farms)
    return not (n == F.n and h == F.h)
end

local function sendAsk(who)
    local m = heldFor(who)
    local text = "A" .. who .. ":" .. pack(m and m.f or 0)
    local list = {}
    for key, e in pairs(m and m.farms or {}) do e.key = key; list[#list + 1] = e end
    sortBests(list)
    for _, e in ipairs(list) do
        e.key = nil
        local p = pack((wire(e))) .. pack(entryHash(e) % TAG)
        if #text + #p <= MAX_LEN then text = text .. p end
    end
    enqueue(text)
    return text
end

local checkBehind
checkBehind = function(who)
    if not (sharing() and showing()) or asking[who] then return end   -- asking sends: opted out, listen only
    local F = lastF[who]
    if not F or compared[who] == F.h or not behind(who) then return end
    asking[who] = true
    C_Timer.After(ASK_MIN + math.random() * ASK_JITTER, function()
        asking[who] = nil
        local F2 = lastF[who]
        if not F2 or compared[who] == F2.h or not behind(who) then return end
        local hold = holds[who]
        if hold and now() - hold < HOLD then
            -- a guildmate asked first: their answer goes to the whole guild; look once more after it
            if waited[who] ~= F2.h then
                waited[who] = F2.h
                C_Timer.After(HOLD, function() KM.Safe(checkBehind, who) end)
            end
            return
        end
        compared[who] = F2.h
        sendAsk(who)
    end)
end
ns.GuildCheckBehind = checkBehind

local function onHello(who, nums)
    local n, h = nums[1], nums[2]
    if not (n and h) or n > 100 or h >= P then return end
    if showing() then lastF[who] = { n = n, h = h } end
    -- a login digest: are they behind on us?
    if #nums > 2 and sharing() then
        local mine = ns.MyBests()
        local mn, mh = fingerprint(mine)
        if mn > 0 then
            local tag, found = nameTag(KM.PlayerName(), mh), false
            for j = 3, #nums do if nums[j] == tag then found = true break end end
            if not found and now() - lastRepost >= REPOST_GAP then
                lastRepost = now()
                C_Timer.After(ASK_MIN + math.random() * ASK_JITTER, function() KM.Safe(ns.GuildHello, false) end)
            end
        end
    end
    if showing() then checkBehind(who) end
end

-- An ask for our bests: send only what differs from the copy they hold.
local function answer(asker, nums)
    if not sharing() then return end
    local held = nums[1] or 0
    local mine = ns.MyBests()
    local _, h = fingerprint(mine)
    local key = asker .. ":" .. held .. ":" .. h
    if answered[key] then return end
    local t, keep = now(), {}
    for _, x in ipairs(answers) do if t - x < ANSWER_WINDOW then keep[#keep + 1] = x end end
    answers = keep
    if #answers >= ANSWER_MAX then return end
    answered[key] = true
    answers[#answers + 1] = t
    local theirs = {}
    for j = 2, #nums - 1, 2 do theirs[nums[j]] = nums[j + 1] end
    local entries, codes = {}, {}
    for _, e in pairs(mine) do
        local code = wire(e)
        codes[code] = true
        if theirs[code] ~= entryHash(e) % TAG then entries[#entries + 1] = encodeEntry(e) end
    end
    for code in pairs(theirs) do if not codes[code] then entries[#entries + 1] = encodeDrop(code) end end
    sendBests(held, h, entries)
end

local function guildBestBefore(key, except)
    local best
    for name, m in pairs(ns.GuildStore() or {}) do
        local e = name ~= except and m.farms and m.farms[key]
        if e and (not best or e.g > best) then best = e.g end
    end
    local mine = ns.MyBests()[key]
    if mine and (not best or mine.g > best) then best = mine.g end
    return best
end

local function flushRecords()
    recordPending = false
    for who, lines in pairs(records) do
        local more = #lines > 2 and ("  (and " .. (#lines - 2) .. " more)") or ""
        KM.Print(ns, who .. " set a new guild best: " .. lines[1] .. (lines[2] and ("; " .. lines[2]) or "") .. more .. ".")
    end
    wipe(records)
end

-- One entry off the wire, checked; nil for anything that doesn't look like a best.
local function readEntry(code, gs, n, d, i, l)
    local map, act = math.floor(code / 8), code % 8
    if map < 1 or map > 100000 or not ACTS[act] then return nil end
    local key = map .. ":" .. ACTS[act]
    if gs == 0 then return key, false end
    local today = dayOf(KM.Now())
    if gs > 10000000 or n < 10 or n > 100000 or d < today - 400 or d > today + 2 or i > 10000000 or l > 255 then return nil end
    return key, { m = map, a = ACTS[act], g = gs * 100, n = n, t = d * DAY + DAY / 2, i = i > 0 and i or nil, l = l > 0 and l or nil }
end

local function onBests(who, nums)
    local prev, new, part, count = nums[1], nums[2], nums[3], nums[4]
    if not (prev and new and part and count) or prev >= P or new >= P or count < 1 or count > 8 or part < 1 or part > count then return end
    if (#nums - 4) % 6 ~= 0 then return end
    local store = ns.GuildStore(true)
    if not store then return end
    local m = store[who]
    if not m then m = { farms = {} }; store[who] = m end
    m.farms = m.farms or {}
    m.t = KM.Now()
    local r = roster()
    local info = r and r[bare(who)]
    if info and type(info.class) == "string" then m.c = info.class end
    local p = partsOf[who]
    if not p or p.new ~= new or p.prev ~= prev then
        p = { prev = prev, new = new, count = count, got = {}, n = 0, sync = (m.f or 0) == prev }
        partsOf[who] = p
    end
    local cutoff = dayOf(KM.Now() - days() * DAY)
    for j = 5, #nums - 5, 6 do
        local key, e = readEntry(nums[j], nums[j + 1], nums[j + 2], nums[j + 3], nums[j + 4], nums[j + 5])
        if key then
            if e == false then
                m.farms[key] = nil
            elseif dayOf(e.t) >= cutoff then
                local before = dayOf(e.t) >= dayOf(KM.Now()) - 1 and guildBestBefore(key, who)
                m.farms[key] = e
                if before and e.g > before then
                    records[who] = records[who] or {}
                    table.insert(records[who], ns.ZoneName(e.m) .. " (" .. e.a .. ") " .. KM.Money(e.g) .. "/hr")
                    if not recordPending then recordPending = true; C_Timer.After(5, flushRecords) end
                end
            end
        end
    end
    if not p.got[part] then p.got[part], p.n = true, p.n + 1 end
    if p.n >= p.count then
        -- cut to their top 20 only once every part is in: a later part may drop a stale farm that would outrank one
        partsOf[who] = nil
        capTop(m.farms)
        local _, h = fingerprint(m.farms)
        if p.sync or h == new then m.f = new end
        if lastF[who] then lastF[who].h = new end
    else
        local n = fingerprint(m.farms)
        if n > 2 * TOP then capTop(m.farms) end   -- parts that never complete still can't grow it without end
    end
    redraw()
end

local function onMessage(text, channel, sender)
    if not ns.db then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender)) then return end
    if channel ~= "GUILD" or type(text) ~= "string" or #text < 2 or #text > 255 then return end
    local kind = text:sub(1, 1)
    if kind ~= "F" and kind ~= "A" and kind ~= "B" then return end   -- V and R are the version check's
    local who = short(sender)
    if not who or KM.IsMe(who) then return end                       -- your own message back
    if not allowIn(who) then return end
    if not select(2, ns.GuildStore()) then return end                 -- the guild isn't known yet
    local body = text:sub(2)
    if kind == "A" then
        local name, rest = body:match("^([^:]+):(.*)$")
        local nums = rest and unpack32(rest)
        if not (name and nums and nums[1]) or #name > 60 then return end
        if KM.IsMe(name) then answer(who, nums) else holds[name] = now() end
        return
    end
    local nums = unpack32(body)
    if not nums then return end
    if kind == "F" then onHello(who, nums)
    elseif kind == "B" and showing() then onBests(who, nums) end
end

---------------------------------------------------------------------------
-- Settings and /farm guild
---------------------------------------------------------------------------

-- Sharing turned on: say hello soon (once in 10 minutes), so guildmates catch up.
local lastOn = -REPOST_GAP
function ns.SetGuildShare(on)
    S().guildShare = on and true or false
    if on and sharing() and now() - lastOn >= REPOST_GAP then
        lastOn = now()
        C_Timer.After(ASK_MIN + math.random() * ASK_JITTER, function() KM.Safe(ns.GuildHello, true) end)
    end
    if not on then wipe(queue) end
    redraw()
end

function ns.SetGuildShow(on)
    S().guildShow = on and true or false
    if ns.db and ns.Tab and ns.Tab() == "guild" then KM.Refresh("farming") end
end

function ns.GuildCommand(arg)
    arg = (arg or ""):lower()
    local on
    if arg == "on" then on = true elseif arg == "off" then on = false else on = not S().guildShare end
    ns.SetGuildShare(on)
    ns.SetGuildShow(on)
    KM.Print(ns, "guild bests " .. (on and "on: sharing your best farms and showing your guild's (Farming Ledger > Guild)."
        or "off: nothing is sent, and guildmates' bests aren't read or shown."))
end

---------------------------------------------------------------------------
-- The board (no frames: tests read this): one row per farm
---------------------------------------------------------------------------

-- Zone levels from the mobs you've killed (Mob Farming's data): { [mapID] = { lo, hi } }.
function ns.ZoneLevels()
    local out = {}
    local mobs = FarmKingDB and FarmKingDB.mobs
    if type(mobs) ~= "table" then return out end
    for _, m in pairs(mobs) do
        if type(m) == "table" and m.lmin and m.lmax and not m.skull and (m.k or 0) > 0 and type(m.z) == "table" then
            for map in pairs(m.z) do
                local z = out[map]
                if not z then out[map] = { lo = m.lmin, hi = m.lmax }
                else z.lo, z.hi = math.min(z.lo, m.lmin), math.max(z.hi, m.lmax) end
            end
        end
    end
    return out
end

local function group(what)
    if what == "Mobs" then return "mobs" end
    if what == "Mixed" then return "mixed" end
    return "gathering"
end
ns.GuildGroup = group

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and { c.r, c.g, c.b } or nil
end

-- Every farm on the board: { key, map, what, best, you, entries = { { who, mine, class, g, n, t, i, l } }, levels }.
-- Yours come from your sessions (every character on the account); guildmates' from the store.
function ns.GuildBoard()
    local farms, byKey = {}, {}
    local function add(key, e, row)
        local fm = byKey[key]
        if not fm then
            fm = { key = key, map = e.m, what = e.a, entries = {} }
            byKey[key] = fm
            farms[#farms + 1] = fm
        end
        row.g, row.n, row.t, row.i, row.l = e.g, e.n, e.t, e.i, e.l
        fm.entries[#fm.entries + 1] = row
        if not fm.best or row.g > fm.best.g then fm.best = row end
        if row.mine and (not fm.you or row.g > fm.you.g) then fm.you = row end
    end
    local chars, mineNames = {}, {}
    for _, s in ipairs(ns.db.sessions) do if s.c and not chars[s.c] then chars[s.c] = true end end
    local _, myClass = nil, nil
    if UnitClass then _, myClass = UnitClass("player") end
    for c in pairs(chars) do
        local name = c:gsub("%-.*$", "")
        mineNames[bare(name)] = true
        for key, e in pairs(ns.MyBests(c)) do
            add(key, e, { who = name, mine = true, class = c == KM.Char() and KM.Plain(myClass) or nil })
        end
    end
    if showing() then
        local cutoff = KM.Now() - days() * DAY
        local r = roster()
        for name, m in pairs(ns.GuildStore() or {}) do
            if not mineNames[bare(name)] then
                local info = r and r[bare(name)]
                local class = (info and info.class) or m.c
                for key, e in pairs(m.farms or {}) do
                    if (e.t or 0) >= cutoff and e.g then add(key, e, { who = name, class = class }) end
                end
            end
        end
    end
    local levels = ns.ZoneLevels()
    for _, fm in ipairs(farms) do
        fm.levels = levels[fm.map]
        table.sort(fm.entries, function(a, b) if a.g ~= b.g then return a.g > b.g end return a.who < b.who end)
    end
    return farms
end

-- Is this farm near your level? The zone's mob levels (yours: from 5 under to 3 over), else the level the best
-- was set at; unknown counts as near.
function ns.GuildNear(fm, lvl)
    lvl = lvl or (UnitLevel and KM.Plain(UnitLevel("player"))) or 1
    if fm.levels then return fm.levels.hi >= lvl - 5 and fm.levels.lo <= lvl + 3 end
    local l = fm.best and fm.best.l
    if l then return l >= lvl - 5 and l <= lvl + 3 end
    return true
end

-- The board with the tab's filters: activity ("all" | "mobs" | "gathering" | "mixed") and near my level.
function ns.GuildRows(act, near)
    local out = {}
    for _, fm in ipairs(ns.GuildBoard()) do
        if (act == nil or act == "all" or group(fm.what) == act) and (not near or ns.GuildNear(fm)) then out[#out + 1] = fm end
    end
    table.sort(out, function(a, b) if a.best.g ~= b.best.g then return a.best.g > b.best.g end return a.key < b.key end)
    return out
end

---------------------------------------------------------------------------
-- The Guild tab
---------------------------------------------------------------------------

local PG = ns.P          -- the page's frames (Page.lua)
local G = {}
ns.G = G

local function whoText(row)
    local c = row.mine and C.accent or classColor(row.class) or C.text
    return UI.Hex(c) .. row.who .. "|r" .. (row.mine and (UI.Hex(C.muted) .. " (you)|r") or "")
end

local function levelsText(fm)
    if fm.levels then
        return fm.levels.lo == fm.levels.hi and tostring(fm.levels.lo) or (fm.levels.lo .. "-" .. fm.levels.hi)
    end
end

local function dateText(t) return t and (ns.Date("%d %b", t) or "?") or DASH end

local BOARD_COLS = {
    { key = "zone", label = "Zone", w = 140, sort = function(e) return ns.ZoneName(e.map):lower() end, desc = false },
    { key = "what", label = "Activity", w = 86, sort = function(e) return e.what end, desc = false },
    { key = "gph", label = "Guild best", tip = "The best gold per hour anyone in your guild has shared for this farm: one session of 10+ active minutes, loot at the market price after the 5% cut.", w = 92, justify = "RIGHT", sort = function(e) return e.best.g end },
    { key = "who", label = "Who", w = 118, sort = function(e) return e.best.who:lower() end, desc = false },
    { key = "date", label = "Date", w = 58, justify = "RIGHT", sort = function(e) return e.best.t or 0 end },
    { key = "item", label = "Top item", tip = "What made the most in that session.", w = 132, sort = function(e) return e.best.i and (KM.Item(e.best.i).name or "") or "" end, desc = false },
    { key = "you", label = "Your best", tip = "Your own best gold per hour here (any of your characters).", w = 0, justify = "RIGHT", sort = function(e) return e.you and e.you.g or -1 end },
}

local ROW_COLS = {
    { key = "who", label = "Who", w = 170, sort = function(e) return e.who:lower() end, desc = false },
    { key = "gph", label = "Gold/hr", w = 96, justify = "RIGHT", sort = function(e) return e.g end },
    { key = "act", label = "Active", tip = "Active time of that session.", w = 66, justify = "RIGHT", sort = function(e) return e.n or 0 end },
    { key = "date", label = "Date", w = 66, justify = "RIGHT", sort = function(e) return e.t or 0 end },
    { key = "lvl", label = "Level", tip = "Their level in that session.", w = 50, justify = "RIGHT", sort = function(e) return e.l or 0 end },
    { key = "item", label = "Top item", w = 0, sort = function(e) return e.i and (KM.Item(e.i).name or "") or "" end, desc = false },
}

local function fillBoard(r, fm, cells)
    local b = fm.best
    cells.zone:SetText(ns.ZoneName(fm.map))
    cells.what:SetText(UI.Hex(C.muted) .. fm.what .. "|r")
    cells.gph:SetText(KM.Money(b.g))
    cells.who:SetText(whoText(b))
    cells.date:SetText(dateText(b.t))
    cells.item:SetText(b.i and KM.ItemText(b.i) or DASH)
    local you = fm.you
    if you and you == b then cells.you:SetText(UI.Hex(C.accent) .. "yours|r")
    else cells.you:SetText(you and KM.Money(you.g) or DASH) end
    r.tip = function(tt)
        tt:AddLine(ns.ZoneName(fm.map) .. ", " .. fm.what, 1, 1, 1)
        local lv = levelsText(fm)
        if lv then tt:AddDoubleLine("Zone levels", lv, 0.8, 0.8, 0.8, 1, 1, 1) end
        tt:AddDoubleLine("Guild best", KM.Money(b.g) .. "/hr", 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("By", b.who .. (b.l and (", level " .. b.l) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("When", (dateText(b.t)) .. ", " .. ns.Dur((b.n or 0) * 60) .. " active", 0.8, 0.8, 0.8, 1, 1, 1)
        if b.i then tt:AddDoubleLine("Top item", KM.ItemText(b.i), 0.8, 0.8, 0.8, 1, 1, 1) end
        tt:AddDoubleLine("Your best", you and (KM.Money(you.g) .. "/hr") or "not farmed (10+ min)", 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Shared by", #fm.entries .. (#fm.entries == 1 and " character" or " characters"), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddLine("Click for everyone's best here.", 0.6, 0.6, 0.6)
    end
end

local function fillRow(r, e, cells)
    cells.who:SetText(whoText(e))
    cells.gph:SetText(KM.Money(e.g))
    cells.act:SetText(ns.Dur((e.n or 0) * 60))
    cells.date:SetText(dateText(e.t))
    cells.lvl:SetText(e.l and tostring(e.l) or DASH)
    cells.item:SetText(e.i and KM.ItemText(e.i) or DASH)
    r.tip = function(tt)
        tt:AddLine(e.who .. (e.mine and " (you)" or ""), 1, 1, 1)
        tt:AddDoubleLine("Gold per hour", KM.Money(e.g) .. "/hr", 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("Session", dateText(e.t) .. ", " .. ns.Dur((e.n or 0) * 60) .. " active", 0.8, 0.8, 0.8, 1, 1, 1)
        if e.i then tt:AddDoubleLine("Top item", KM.ItemText(e.i), 0.8, 0.8, 0.8, 1, 1, 1) end
        tt:AddLine(e.mine and "Worked out from your saved sessions." or "Their personal best here, as they shared it.", 0.6, 0.6, 0.6, true)
    end
end

local ACT_TABS = { { id = "all", label = "All", w = 54 }, { id = "mobs", label = "Mobs", w = 62 },
    { id = "gathering", label = "Gathering", w = 86 }, { id = "mixed", label = "Mixed", w = 62 } }

function ns.BuildGuild(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetAllPoints(c)
    v:Hide()
    PG.guild = v
    G.frame = v
    G.tileRow, G.tiles = ns.MakeTiles(v, -32)
    local function scope(tt)
        tt:AddLine("Each character's best session per farm (10+ active minutes) from the last " .. days() .. " days, yours and what guildmates running King Maker share.", 0.6, 0.6, 0.6, true)
    end
    G.tiles[1]:SetTip(function(tt) tt:AddLine("Farms (a zone and what you did there) on the board with the filters below.", 1, 1, 1, true); scope(tt) end)
    G.tiles[2]:SetTip(function(tt) tt:AddLine("The best gold per hour on the board, and who set it.", 1, 1, 1, true); scope(tt) end)
    G.tiles[3]:SetTip(function(tt) tt:AddLine("Your best gold per hour on the board (any of your characters).", 1, 1, 1, true); scope(tt) end)
    G.tiles[4]:SetTip(function(tt) tt:AddLine("Farms where you hold the guild's best, out of the farms you've farmed.", 1, 1, 1, true); scope(tt) end)
    G.tiles[5]:SetTip(function(tt)
        tt:AddLine("Guildmates whose bests you have, and when you last heard from one.", 1, 1, 1, true)
        tt:AddLine("Bests arrive when a guildmate saves a new one, and at login when your copy is behind theirs.", 0.6, 0.6, 0.6, true)
    end)
    G.tiles[6]:SetTip(function(tt)
        tt:AddLine("Share my best farms with my guild: your top " .. TOP .. " farms only, never your sessions. A new best is one short message; at login one fingerprint, and only what differs is exchanged.", 1, 1, 1, true)
        tt:AddLine("Settings > Farm Tracker, or /farm guild on|off.", 0.6, 0.6, 0.6, true)
    end)

    G.acts = UI.Tabs(v, ACT_TABS, function(id) U().guildAct = id; G.open = nil; KM.Refresh("farming") end, 22)
    G.acts:SetPoint("TOPLEFT", 0, -100)
    G.near = UI.CheckLabel(v, "Near my level", function(on) U().guildNear = on and true or false; KM.Refresh("farming") end,
        "Only farms whose zone's mobs (from Mob Farming) are from 5 levels under you to 3 over; with no mob data, the level the best was set at. Farms with neither always show.")
    G.near.frame:SetPoint("LEFT", G.acts, "RIGHT", 14, 0)
    G.back = UI.Button(v, "", 300, 22, function() G.open = nil; KM.Refresh("farming") end, "ghost")
    G.back:SetPoint("TOPRIGHT", 0, -100)
    G.back.label:SetJustifyH("RIGHT")
    UI.Tip(G.back, "Everyone's best at this farm. Click to see every farm again.")
    G.back:Hide()

    G.board = UI.Table(v, BOARD_COLS, 22, { onClick = function(fm) G.open = fm.key; KM.Refresh("farming") end })
    G.board:SetPoint("TOPLEFT", 0, -130)
    G.board:SetPoint("BOTTOMRIGHT", 0, 18)
    G.board:SetSort("gph", true)
    G.rows = UI.Table(v, ROW_COLS, 22, {})
    G.rows:SetPoint("TOPLEFT", 0, -130)
    G.rows:SetPoint("BOTTOMRIGHT", 0, 18)
    G.rows:SetSort("gph", true)
    G.rows.emptyText = "Nobody's best here any more."
    G.rows:Hide()
    G.footer = UI.Text(v, 10, C.dim)
    G.footer:SetPoint("BOTTOMLEFT", 0, 2)
end

function ns.RefreshGuild(c)
    local u = U()
    local w = (c and c:GetWidth()) or 763
    if w ~= G.width then
        G.width = w
        ns.LayoutTiles(G.tiles, w)
    end
    KM.Safe(ns.GuildPrune)
    local act = u.guildAct or "all"
    G.acts:Select(act)
    G.near:SetChecked(u.guildNear)
    local rows = ns.GuildRows(act, u.guildNear)
    G.list = rows

    -- tiles
    local top, yours, lead, farmed = rows[1], nil, 0, 0
    local mates, newest = 0, nil
    for _, fm in ipairs(rows) do
        if fm.you then
            farmed = farmed + 1
            if not yours or fm.you.g > yours.you.g then yours = fm end
            if fm.best == fm.you then lead = lead + 1 end
        end
    end
    if showing() then
        for _, m in pairs(ns.GuildStore() or {}) do
            if next(m.farms or {}) then mates = mates + 1 end
            if m.t and (not newest or m.t > newest) then newest = m.t end
        end
    end
    local TT = G.tiles
    TT[1]:Set("Farms", tostring(#rows), act == "all" and "on the board" or (act .. " only"))
    TT[2]:Set("Guild's best", top and KM.Money(top.best.g) or "-", top and (ns.ZoneName(top.map) .. ", " .. top.best.who) or "no farms yet")
    TT[3]:Set("Your best", yours and KM.Money(yours.you.g) or "-", yours and ns.ZoneName(yours.map) or "10+ active minutes")
    TT[4]:Set("You lead", tostring(lead), "of " .. farmed .. " you farmed")
    TT[5]:Set("Guildmates", tostring(mates), newest and ("heard " .. KM.Ago(newest) .. (KM.Ago(newest) == "now" and "" or " ago")) or "none heard yet")
    local share = sharing()
    TT[6]:Set("Sharing", not inGuild() and "No guild" or (share and "On" or "Off"),
        showing() and "showing guild bests" or "guild bests hidden", (inGuild() and not share) and C.warn or nil)

    -- one farm open, or the board
    local open
    if G.open then for _, fm in ipairs(rows) do if fm.key == G.open then open = fm end end end
    G.open = open and open.key or nil
    if open then
        G.board:Hide()
        G.rows:Show()
        G.rows:SetRows(open.entries, fillRow)
        G.back:SetLabel(UI.Hex(C.accent) .. ns.ZoneName(open.map) .. ", " .. open.what .. "|r   " .. UI.Hex(C.muted) .. "x  all farms|r")
        G.back:Show()
        G.footer:SetText(#open.entries .. (#open.entries == 1 and " character's best" or " characters' bests") .. " at this farm.")
    else
        G.rows:Hide()
        G.board:Show()
        G.back:Hide()
        if not inGuild() then G.board.emptyText = "Join a guild to compare your farms with your guildmates'."
        elseif not showing() then G.board.emptyText = "Guild bests are off: Settings > Farm Tracker > Show guild bests."
        else G.board.emptyText = "No farms yet: yours show once you save a session of 10+ active minutes, guildmates' when they share theirs." end
        G.board:SetRows(rows, fillBoard)
        G.footer:SetText(#rows > 0 and ("Click a farm for everyone's best there. Each character's top " .. TOP .. " farms, last " .. days() .. " days; guildmates' arrive from King Maker 2.7 and later.") or "")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

TrackerKing.RegisterCallback("King_Maker_TrackerGuild", function(event)
    if event == "SESSION_SAVED" and ns.db and sharing() and not flushPending then
        flushPending = true
        C_Timer.After(FLUSH_DELAY, function() KM.Safe(flush) end)
    end
end)

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        KM.Safe(ns.GuildPrune)
        KM.Safe(snapshot)
        C_Timer.After(LOGIN_DELAY + math.random() * LOGIN_JITTER, function() KM.Safe(ns.GuildHello, true) end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if redrawAfterCombat then redrawAfterCombat = false; redraw() end
    elseif event == "CHAT_MSG_ADDON" then
        if issecretvalue and issecretvalue(prefix) then return end
        if prefix ~= PREFIX then return end
        pcall(onMessage, text, channel, sender)   -- a malformed message is dropped quietly
    end
end)

-- Tests: the session-only state.
function ns.GuildState()
    return { lastF = lastF, compared = compared, holds = holds, announced = announced, announcedHash = announcedHash,
        answers = answers, sentAt = sentAt }
end
function ns.GuildResetSession()
    wipe(lastF); wipe(compared); wipe(holds); wipe(waited); wipe(asking); wipe(answered); wipe(answers); wipe(partsOf)
    wipe(inCount); wipe(queue); sentAt = {}; lastSend = -10; lastRepost = -REPOST_GAP; lastOn = -REPOST_GAP
    rosterCache = nil
end
