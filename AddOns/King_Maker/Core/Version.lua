local _, KM = ...

-- Version check: guildmates running King Maker tell each other which version they have, so nobody stays on an old
-- one without knowing. When someone in your guild has a newer King Maker, you get one line in chat:
--   King Maker 2.7.0 is out (Bob has it); you have 2.6.0. Update it in the CurseForge app.
-- once per session for each newer version seen.
--
-- Messages (prefix KingMaker1, guild channel only, a few bytes each):
--   V<version>   "this is my version": sent once, 15-25 s after login
--   R<version>   an answer to an older V: sent by one guildmate with a newer version (whoever's random 2-8 s
--                delay ends first; the others hear the answer and stand down), at most once a minute
-- The prefix is King Maker's one prefix; this file reads only V and R (2.8.0's guild bests also sent F, A and B:
-- those are ignored).
-- Nothing is sent outside a guild. KingMakerDB.newest keeps the newest version seen ({ v, who, t }) for /km version.
-- Settings > General: "Tell me when a guildmate has a newer King Maker" (KingMakerDB.ui.versionNotice, default on);
-- your own version is always announced, so the guild still hears about it.

local PREFIX = "KingMaker1"
local LOGIN_DELAY, LOGIN_JITTER = 15, 10
local REPLY_MIN, REPLY_JITTER, REPLY_GAP = 2, 6, 60

local told = {}          -- version -> true: told about it this session
local replyAt            -- the version a pending answer would beat, while one is pending
local lastReply = -REPLY_GAP

-- "2.10.1" -> { 2, 10, 1 }; nil for anything that isn't a version.
local function parts(v)
    if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
    if not v:match("^%d+[%.%d]*$") then return nil end
    local out = {}
    for n in v:gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

-- -1 when a is older than b, 1 when newer, 0 when the same; nil when either isn't a version.
function KM.CompareVersions(a, b)
    local x, y = parts(a), parts(b)
    if not (x and y) then return nil end
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p < q and -1 or 1 end
    end
    return 0
end

local function now() return GetTime and GetTime() or 0 end

local function send(kind)
    if not (IsInGuild and IsInGuild()) then return false end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    return pcall(C_ChatInfo.SendAddonMessage, PREFIX, kind .. KM.version, "GUILD")
end

local function short(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
    if Ambiguate then
        local ok, s = pcall(Ambiguate, name, "none")
        if ok and type(s) == "string" then return s end
    end
    return (name:gsub("%-.*$", ""))
end

local function isMe(sender)
    local me = UnitName and UnitName("player")
    return me and sender and (sender == me or sender:match("^([^%-]+)") == me)
end

local function heard(v, sender, kind)
    local cmp = KM.CompareVersions(v, KM.version)
    if not cmp then return end
    local db = KingMakerDB
    if cmp > 0 then
        if not db.newest or KM.CompareVersions(v, db.newest.v) == 1 then
            db.newest = { v = v, who = sender, t = (KM.Now and KM.Now()) or (GetServerTime and GetServerTime()) or 0 }
        end
        if db.ui.versionNotice ~= false and not told[v] then
            told[v] = true
            KM.Print("|cffffd200King Maker " .. v .. " is out|r (" .. sender .. " has it); you have " .. KM.version
                .. ". Update it in the CurseForge app.")
        end
    end
    -- someone at least as new as us has spoken: no need for our answer
    if replyAt and cmp >= 0 then replyAt = nil end
    -- an older version just said hello: answer it, unless a guildmate does first
    if kind == "V" and cmp < 0 and not replyAt and now() - lastReply >= REPLY_GAP then
        replyAt = v
        C_Timer.After(REPLY_MIN + math.random() * REPLY_JITTER, function()
            if not replyAt then return end
            replyAt = nil
            lastReply = now()
            send("R")
        end)
    end
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if not KingMakerDB then return end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
        C_Timer.After(LOGIN_DELAY + math.random() * LOGIN_JITTER, function() send("V") end)
        return
    end
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    local who = short(sender)
    if not who or isMe(sender) then return end
    local kind, v = text:match("^([VR])(.+)$")
    if kind then heard(v, who, kind) end
end)

-- For /km version: what you have and the newest a guildmate has been seen with.
function KM.VersionReport()
    local n = KingMakerDB and KingMakerDB.newest
    if n and KM.CompareVersions(n.v, KM.version) == 1 then
        return "you have " .. KM.version .. "; " .. (n.who or "a guildmate") .. " has " .. n.v .. ". Update it in the CurseForge app."
    end
    return "you have " .. KM.version .. ", the newest any guildmate has been seen with."
end
