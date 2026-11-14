local _, KM = ...
local ns = KM.Module("Gather")

-- Guild sync: everyone in your guild running King Maker shares markers, and lists catch up with each other
-- without anyone resending everything.
--   * A marker you add is sent to the guild right away.
--   * At login, and every 30 minutes, you post a fingerprint of your list (how many spots, and a hash of where
--     they are). Guildmates whose fingerprint matches stay quiet.
--   * When it differs, one guildmate answers (whoever's timer fires first says so on the guild channel and the
--     rest stand down). They whisper you a fingerprint per zone; you send them your markers in the zones that
--     differ and ask for theirs there. Someone with no markers at all just gets the whole list.
--   * The same two lists aren't compared twice in a session, so a difference sync can't fix (a spot you
--     deleted that they never had) doesn't come back every half hour.
-- Deletes stay personal: a marker you delete is remembered so sync never brings it back to your map. The
-- remembered spots count in your fingerprint, so a deleted marker still matches a guildmate who has it.
--
-- Messages (prefix GatherKing1; gather_king 1.x and King Maker before 2.5 know N, S and H only):
--   N<entries>      markers                 S<entries>   harvest stats
--   Q<count>:<hash> my fingerprint (guild)  C<name>      I'm answering name (guild)
--   R<zones>        my zone fingerprints    E            end of them
--   W<mapIDs>       send me these zones     H            old hello: send me everything

local PREFIX = "GatherKing1"
local MAX_LEN = 240
local SEND_INTERVAL = 1 -- the game allows a short burst, then about one addon message per second
local RECHECK = 30 * 60 -- seconds between fingerprints
local CLAIM_HOLD = 30   -- seconds a "C" keeps the others quiet
local EXCHANGE = 300    -- seconds an exchange may take

local TYPE_CODE = { mine = "m", herb = "h", fish = "f", treasure = "t" }
local CODE_TYPE = {}
for k, v in pairs(TYPE_CODE) do CODE_TYPE[v] = k end
local TYPE_NUM = { mine = 1, herb = 2, fish = 3, treasure = 4 }

local queue, sending = {}, false
local repliedTo = {}  -- old hello answered, once per session
local received = {}   -- sender -> count, for one summary line per sender
local claims = {}     -- name -> GetTime() someone said they're answering them
local compared = {}   -- name -> "theirs/mine" fingerprints already compared
local serving = {}    -- name -> GetTime() we started answering them (their W is welcome)
local zonesFrom = {}  -- name -> zone fingerprints arriving in R messages
local askedAt         -- GetTime() of our last fingerprint (an answer is welcome)

local function enabled()
    return ns.db and ns.db.sync.guild and IsInGuild and IsInGuild()
end

local function shortName(sender)
    if Ambiguate then return Ambiguate(sender, "none") end
    return (sender:gsub("%-.*$", ""))
end

local function now() return GetTime and GetTime() or time() end

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

-- first: ahead of anything already waiting (a claim has to beat the others' timers).
local function enqueue(text, channel, target, first)
    if first then table.insert(queue, 1, { text, channel, target })
    else table.insert(queue, { text, channel, target }) end
    if not sending then
        sending = true
        pump()
    end
end

-- One marker as "mapID,type,x,y,name[,itemID]" with x/y in hundredths of a
-- percent. The item ID (for the icon) is only sent for names we don't know.
local function encode(mapID, node)
    local name = node.n and node.n:gsub("[,;]", "") or ""
    local _, known = ns.LookupKnown(node.n)
    local item = (node.item and not known) and ("," .. node.item) or ""
    return string.format("%d,%s,%d,%d,%s%s", mapID, TYPE_CODE[node.t] or "m",
        math.floor(node.x * 10000 + 0.5), math.floor(node.y * 10000 + 0.5), name, item)
end

local function decode(entry)
    local mapID, code, x, y, rest = entry:match("^(%d+),(%a),(%d+),(%d+),(.*)$")
    if not mapID or not CODE_TYPE[code] then return nil end
    local name, item = rest:match("^(.*),(%d+)$")
    if not name then name = rest end
    if name == "" then name = nil end
    return tonumber(mapID), CODE_TYPE[code], tonumber(x) / 10000, tonumber(y) / 10000, name, tonumber(item)
end

---------------------------------------------------------------------------
-- Fingerprints
---------------------------------------------------------------------------

local P = 2147483629 -- a prime under 2^31: every step below stays exact in a double

local function spotHash(mapID, t, x, y)
    local v = (mapID * 5 + (TYPE_NUM[t] or 0)) % P
    v = (v * 10007 + math.floor(x * 10000 + 0.5)) % P
    v = (v * 10007 + math.floor(y * 10000 + 0.5)) % P
    v = (v * 48271) % P
    return (v * 48271) % P
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    if n == 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    end
    return s
end

-- Per zone { n = markers + deleted spots, h = hash of where they are }, and the totals as "count:hash".
-- The order of the lists doesn't matter (the hash is a sum).
function ns.SyncFingerprint()
    local zones = {}
    local function add(mapID, t, x, y)
        local z = zones[mapID]
        if not z then z = { n = 0, h = 0 }; zones[mapID] = z end
        z.n = z.n + 1
        z.h = (z.h + spotHash(mapID, t, x, y)) % P
    end
    for mapID, list in pairs(ns.db.nodes) do
        for _, node in ipairs(list) do add(mapID, node.t, node.x, node.y) end
    end
    for mapID, list in pairs(ns.db.deleted) do
        for _, d in ipairs(list) do add(mapID, d.t, d.x, d.y) end
    end
    local n, h = 0, 0
    for _, z in pairs(zones) do n, h = n + z.n, (h + z.h) % P end
    return zones, b36(n) .. ":" .. b36(h), n
end

---------------------------------------------------------------------------
-- Export / import codes (Settings > Share with friends) use the marker format.
---------------------------------------------------------------------------

local CODE_PREFIX = "GK1:"

function ns.ExportCode(mapID)
    local entries = {}
    for id, list in pairs(ns.db.nodes) do
        if not mapID or id == mapID then
            for _, node in ipairs(list) do table.insert(entries, encode(id, node)) end
        end
    end
    return CODE_PREFIX .. table.concat(entries, ";"), #entries
end

function ns.ImportCode(code)
    code = code and code:gsub("%s+", "") or ""
    if code:sub(1, #CODE_PREFIX) ~= CODE_PREFIX then
        KM.Print(ns, "That doesn't look like a Gather King code. Codes start with " .. CODE_PREFIX)
        return 0
    end
    local added, total = 0, 0
    for entry in code:sub(#CODE_PREFIX + 1):gmatch("[^;]+") do
        local mapID, t, x, y, name, item = decode(entry)
        if mapID then
            total = total + 1
            if ns.MergeShared(mapID, t, x, y, name, "an import", true, item) then added = added + 1 end
        end
    end
    KM.Print(ns, "Imported " .. added .. " new marker(s) (" .. (total - added) .. " you already had).")
    ns.Refresh()
    return added
end

---------------------------------------------------------------------------
-- Sending markers and stats
---------------------------------------------------------------------------

-- Packs entries into as few messages as possible.
local function sendPacked(kind, sep, entries, channel, target)
    local buf = kind
    for _, e in ipairs(entries) do
        if #buf + #e + 1 > MAX_LEN then
            enqueue(buf, channel, target)
            buf = kind
        end
        buf = buf .. (buf == kind and "" or sep) .. e
    end
    if buf ~= kind then enqueue(buf, channel, target) end
end

local function sendEntries(entries, channel, target)
    sendPacked("N", ";", entries, channel, target)
end

-- Loot stats: "S" + entries joined by "~", each
-- "mapID,type,x,y,harvests,itemID:times:amount/itemID:times:amount".
-- Only your own harvests are sent; receivers store them under your name.
local function encodeStats(mapID, node)
    local st = node.stats
    if not st or st.h == 0 then return nil end
    local items = {}
    for id, it in pairs(st.items) do table.insert(items, id .. ":" .. it.n .. ":" .. it.q) end
    table.sort(items)
    local e = string.format("%d,%s,%d,%d,%d,%s", mapID, TYPE_CODE[node.t] or "m",
        math.floor(node.x * 10000 + 0.5), math.floor(node.y * 10000 + 0.5), st.h, table.concat(items, "/"))
    if #e > MAX_LEN - 2 then e = e:sub(1, MAX_LEN - 2):gsub("/[^/]*$", "") end
    return e
end

local function sendStats(entries, channel, target)
    sendPacked("S", "~", entries, channel, target)
end

local function receiveStats(body, who)
    for entry in body:gmatch("[^~]+") do
        local mapID, code, x, y, h, items = entry:match("^(%d+),(%a),(%d+),(%d+),(%d+),(.*)$")
        local t = code and CODE_TYPE[code]
        if t then
            local node = ns.FindNode(tonumber(mapID), t, tonumber(x) / 10000, tonumber(y) / 10000)
            if node then
                local st = { h = tonumber(h), items = {} }
                for id, n, q in items:gmatch("(%d+):(%d+):(%d+)") do
                    st.items[tonumber(id)] = { n = tonumber(n), q = tonumber(q) }
                end
                node.guild = node.guild or {}
                node.guild[who] = st
            end
        end
    end
end

function ns.ShareStats(mapID, node)
    if not enabled() then return end
    local e = encodeStats(mapID, node)
    if e then sendStats({ e }, "GUILD") end
end

-- Markers and your harvest stats, in every zone or only the zones in the set.
local function collect(zones)
    local entries, stats = {}, {}
    for mapID, list in pairs(ns.db.nodes) do
        if not zones or zones[mapID] then
            for _, node in ipairs(list) do
                table.insert(entries, encode(mapID, node))
                local s = encodeStats(mapID, node)
                if s then table.insert(stats, s) end
            end
        end
    end
    return entries, stats
end

local function sendZones(zones, target)
    local entries, stats = collect(zones)
    sendEntries(entries, "WHISPER", target)
    sendStats(stats, "WHISPER", target)
end

function ns.ShareNode(mapID, node)
    if not enabled() then return end
    sendEntries({ encode(mapID, node) }, "GUILD")
end

-- Posts our fingerprint; guildmates whose lists differ answer. quiet: the login and half-hour checks.
function ns.SyncNow(quiet)
    if not ns.db.sync.guild then
        if not quiet then KM.Print(ns, "Guild sync is off. /gt sync on turns it on.") end
        return
    end
    if not IsInGuild() then
        if not quiet then KM.Print(ns, "You're not in a guild, so there's no one to sync with.") end
        return
    end
    local _, total = ns.SyncFingerprint()
    askedAt = now()
    enqueue("Q" .. total, "GUILD")
    if not quiet then
        KM.Print(ns, "Asked guildmates online for markers you're missing (and sending them yours).")
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local summaryPending = false
local function flushSummary()
    summaryPending = false
    for sender, n in pairs(received) do
        KM.Print(ns, "Got " .. n .. " new marker(s) from " .. sender .. ".")
    end
    wipe(received)
    ns.Refresh()
end

-- After a short random wait, answer someone unless a guildmate said they're on it.
local function answerLater(who, fn)
    C_Timer.After(1 + math.random() * 4, function()
        local c = claims[who]
        if c and now() - c < CLAIM_HOLD then return end
        claims[who] = now()
        enqueue("C" .. who, "GUILD", nil, true)
        fn()
    end)
end

-- A guildmate's fingerprint.
local function onFingerprint(theirs, who, sender)
    local zones, mine, count = ns.SyncFingerprint()
    if theirs == mine or count == 0 then return end
    local key = theirs .. "/" .. mine
    if compared[who] == key then return end
    answerLater(who, function()
        compared[who] = key
        serving[who] = now()
        if theirs:match("^0:") then
            sendZones(nil, sender) -- nothing at all yet: everything, no comparing
            return
        end
        local list = {}
        for mapID, z in pairs(zones) do table.insert(list, mapID .. ":" .. b36(z.n) .. ":" .. b36(z.h)) end
        table.sort(list)
        sendPacked("R", ";", list, "WHISPER", sender)
        enqueue("E", "WHISPER", sender)
    end)
end

-- Someone answering our fingerprint sent theirs per zone: send ours where they differ, ask for theirs.
local function compareZones(theirs, sender)
    local mine = ns.SyncFingerprint()
    local give, want = {}, {}
    for mapID, z in pairs(mine) do
        local t = theirs[mapID]
        if not t or t.n ~= z.n or t.h ~= z.h then give[mapID] = true end
    end
    for mapID, t in pairs(theirs) do
        local z = mine[mapID]
        if not z or t.n ~= z.n or t.h ~= z.h then table.insert(want, tostring(mapID)) end
    end
    table.sort(want)
    sendPacked("W", ",", want, "WHISPER", sender)
    if next(give) then sendZones(give, sender) end
end

local function onMessage(text, channel, sender)
    local who = shortName(sender)
    if KM.IsMe(who) then return end -- your own message back (full name: Forever has surnames)
    local kind, body = text:sub(1, 1), text:sub(2)

    if kind == "N" then
        local added = 0
        for entry in body:gmatch("[^;]+") do
            local mapID, t, x, y, name, item = decode(entry)
            if mapID and ns.MergeShared(mapID, t, x, y, name, who, nil, item) then
                added = added + 1
            end
        end
        if added > 0 then
            received[who] = (received[who] or 0) + added
            if not summaryPending then
                summaryPending = true
                C_Timer.After(5, flushSummary)
            end
        end
    elseif kind == "S" then
        receiveStats(body, who)
    elseif kind == "C" and channel == "GUILD" then
        claims[shortName(body)] = now()
    elseif kind == "Q" and channel == "GUILD" then
        if body:match("^%w+:%w+$") then onFingerprint(body, who, sender) end
    elseif kind == "R" and channel == "WHISPER" then
        if askedAt and now() - askedAt < EXCHANGE then
            local zones = zonesFrom[who] or {}
            zonesFrom[who] = zones
            for mapID, n, h in body:gmatch("(%d+):(%w+):(%w+)") do
                zones[tonumber(mapID)] = { n = tonumber(n, 36), h = tonumber(h, 36) }
            end
        end
    elseif kind == "E" and channel == "WHISPER" then
        local zones = zonesFrom[who]
        zonesFrom[who] = nil
        if zones and askedAt and now() - askedAt < EXCHANGE then compareZones(zones, sender) end
    elseif kind == "W" and channel == "WHISPER" then
        if serving[who] and now() - serving[who] < EXCHANGE then
            local zones = {}
            for mapID in body:gmatch("%d+") do zones[tonumber(mapID)] = true end
            if next(zones) then sendZones(zones, sender) end
        end
    elseif kind == "H" then
        -- gather_king 1.x or an older King Maker logged in: one of us whispers them everything, once.
        if repliedTo[who] or not next(ns.db.nodes) then return end
        answerLater(who, function()
            repliedTo[who] = true
            sendZones(nil, sender)
        end)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        -- Give the guild roster a moment to load before asking.
        C_Timer.After(15, function()
            if enabled() then ns.SyncNow(true) end
        end)
        C_Timer.NewTicker(RECHECK, function()
            if enabled() then ns.SyncNow(true) end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix ~= PREFIX or not ns.db or not ns.db.sync.guild then return end
        if channel ~= "GUILD" and channel ~= "WHISPER" then return end
        pcall(onMessage, text, channel, sender)
    end
end)
