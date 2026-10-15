local _, ns = ...

-- Guild sync: everyone in your guild running gather_king shares markers
-- automatically while online at the same time.
--   * A marker you add is sent to the guild right away.
--   * When you log in, you announce yourself and send your markers to the
--     guild; guildmates who are online whisper you theirs back.
-- Deletes stay personal: a marker you delete is remembered so sync never
-- brings it back to your map.

local PREFIX = "GatherKing1"
local MAX_LEN = 240
local SEND_INTERVAL = 1 -- the game allows a short burst, then about one addon message per second

local TYPE_CODE = { mine = "m", herb = "h", fish = "f", treasure = "t" }
local CODE_TYPE = {}
for k, v in pairs(TYPE_CODE) do CODE_TYPE[v] = k end

local queue, sending = {}, false
local repliedTo = {}
local received = {} -- sender -> count, for one summary line per sender

local function enabled()
    return ns.db and ns.db.sync.guild and IsInGuild and IsInGuild()
end

local function me()
    local name = UnitName("player")
    return name
end

local function shortName(sender)
    if Ambiguate then return Ambiguate(sender, "none") end
    return (sender:gsub("%-.*$", ""))
end

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

-- Export / import codes (Settings > Share with friends) use the same format.
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
        ns.Print("That doesn't look like a Gather King code. Codes start with " .. CODE_PREFIX)
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
    ns.Print("Imported " .. added .. " new marker(s) (" .. (total - added) .. " you already had).")
    ns.Refresh()
    return added
end

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

local function allStats()
    local entries = {}
    for mapID, list in pairs(ns.db.nodes) do
        for _, node in ipairs(list) do
            local e = encodeStats(mapID, node)
            if e then table.insert(entries, e) end
        end
    end
    return entries
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

local function allEntries()
    local entries = {}
    for mapID, list in pairs(ns.db.nodes) do
        for _, node in ipairs(list) do
            table.insert(entries, encode(mapID, node))
        end
    end
    return entries
end

function ns.ShareNode(mapID, node)
    if not enabled() then return end
    sendEntries({ encode(mapID, node) }, "GUILD")
end

function ns.SyncNow()
    if not ns.db.sync.guild then
        ns.Print("Guild sync is off. /gt sync on turns it on.")
        return
    end
    if not IsInGuild() then
        ns.Print("You're not in a guild, so there's no one to sync with.")
        return
    end
    enqueue("H", "GUILD")
    sendEntries(allEntries(), "GUILD")
    sendStats(allStats(), "GUILD")
end

local summaryPending = false
local function flushSummary()
    summaryPending = false
    for sender, n in pairs(received) do
        ns.Print("Got " .. n .. " new marker(s) from " .. sender .. ".")
    end
    wipe(received)
    ns.Refresh()
end

local function onMessage(text, channel, sender)
    local who = shortName(sender)
    if who == me() then return end
    local kind, body = text:sub(1, 1), text:sub(2)

    if kind == "H" then
        -- A guildmate just logged in: whisper them our markers, once per session.
        if repliedTo[who] then return end
        repliedTo[who] = true
        local entries, stats = allEntries(), allStats()
        if #entries > 0 then
            C_Timer.After(2 + math.random() * 6, function()
                sendEntries(entries, "WHISPER", sender)
                sendStats(stats, "WHISPER", sender)
            end)
        end
    elseif kind == "S" then
        receiveStats(body, who)
    elseif kind == "N" then
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
        -- Give the guild roster a moment to load before announcing ourselves.
        C_Timer.After(15, function()
            if enabled() then ns.SyncNow() end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix ~= PREFIX or not ns.db or not ns.db.sync.guild then return end
        if channel ~= "GUILD" and channel ~= "WHISPER" then return end
        pcall(onMessage, text, channel, sender)
    end
end)
