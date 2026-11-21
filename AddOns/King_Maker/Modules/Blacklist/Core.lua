local _, KM = ...
local ns = KM.Module("Blacklist", { title = "Guild Blacklist", short = "Blacklist", db = "BlacklistKingDB" })

-- Guild Blacklist (King Maker 2.10): players your guild doesn't want to group with, shared with every guildmate
-- running King Maker. Anyone can add, edit or remove an entry. A listed player gets a red BLACKLISTED before their
-- name in chat, a line in their tooltip, a mark in the group finder, and a warning when they invite you or join
-- your group. Nothing is ever kicked or declined (those are protected): it warns and marks only.
--
--   Core.lua    saved data, names, the guild check, add / edit / remove, the BlacklistKing API, /bl
--   Sync.lua    guild sharing (prefix KingMaker1, kinds L Q W E)
--   Alerts.lua  right-click menus, group join and invite warnings, tooltips, the chat tag, the group finder
--   UI.lua      the Guild > Blacklist page, the add / edit dialog, Settings > Blacklist
--
-- Saved: BlacklistKingDB = {
--   version = 1,
--   lists = { [listKey] = { entries = { [key] = entry }, seen = { [key] = t }, heard = { [name] = t } } },
--   chars = { ["First Last-Realm"] = listKey },     the last list each character used (the guild loads late)
--   settings = { share, alertJoin, alertInvite, sound, chatTag, lfg, tooltip, purge },
--   ui = { sort, desc, selected } }
-- listKey = "<guild name>-<realm>" (so another guild's list never mixes in) or "personal" without a guild.
-- key = the lower-cased full name ("evil guy"); Forever names are unique by first and last name.
-- entry = { n = "Evil Guy", r = "scam" | "ninja" | "toxic" | "other", note, by = who added it, t = added,
--           e = last change (add, edit or removal), eb = who last changed it (nil = by), del = true (removed: a
--           tombstone, so a guildmate who missed the removal can't bring it back), g = their GUID (this client
--           only, for tooltips; never sent) }. Times are server time. seen = the last time they were in your group.

BlacklistKing = { API_VERSION = 1 }
local API = BlacklistKing
ns.API = API

ns.NOTE_MAX = 160          -- bytes; an entry must fit one 250-byte addon message (Sync.lua trims to fit)
ns.NAME_MAX = 40
ns.TOMB_DAYS = 60          -- removals are kept this long, then forgotten (the "purge" setting)
local DAY = 86400

ns.REASONS = {
    { id = "scam", label = "Scam", wire = "s", tip = "Took gold or items and didn't deliver, or a trade trick." },
    { id = "ninja", label = "Ninja loot", wire = "n", tip = "Rolled need on what wasn't theirs, or took loot and left." },
    { id = "toxic", label = "Toxic", wire = "t", tip = "Abuse, harassment, griefing." },
    { id = "other", label = "Other", wire = "o", tip = "Anything else: the note says what." },
}
ns.REASON = {}
ns.REASON_BY_WIRE = {}
for _, r in ipairs(ns.REASONS) do
    ns.REASON[r.id] = r
    ns.REASON_BY_WIRE[r.wire] = r
end
function ns.ReasonLabel(id) local r = ns.REASON[id or ""]; return r and r.label or "Other" end

ns.RED = "|cffff2020"
ns.TAG = "|cffff2020BLACKLISTED|r"

local function secret(v)
    if not issecretvalue then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end
ns.IsSecret = secret

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
ns.Call = call

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- Text safe to keep and send: no UI escape codes (|), none of Sync's separators (~ ^), no control characters,
-- spaces collapsed and trimmed.
function ns.Clean(s)
    if type(s) ~= "string" or secret(s) then return "" end
    s = s:gsub("[|~^]", ""):gsub("%c", " "):gsub("%s+", " ")
    return (s:gsub("^ ", ""):gsub(" $", ""))
end

-- Cuts s to at most n bytes without splitting a UTF-8 character.
function ns.Cut(s, n)
    if #s <= n then return s end
    s = s:sub(1, n)
    local i = #s
    while i > 0 do
        local b = s:byte(i)
        if b < 0x80 then break end
        if b >= 0xC0 then
            -- a lead byte: keep the character only if all its bytes are here
            local need = b >= 0xF0 and 4 or (b >= 0xE0 and 3 or 2)
            if #s - i + 1 < need then s = s:sub(1, i - 1) end
            break
        end
        i = i - 1
    end
    return s
end

-- A name as the game shows it: "Evil Guy" (the realm dropped, spaces tidied, each word capitalised when typed in
-- lower case). nil for anything that can't be a character name.
function ns.Name(name)
    if type(name) ~= "string" or secret(name) then return nil end
    name = ns.Clean(name:gsub("%-.*$", ""))
    if name == "" or #name > ns.NAME_MAX or name:find("%d") then return nil end
    if UNKNOWNOBJECT and name == UNKNOWNOBJECT then return nil end
    name = name:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b end)
    return name
end

-- The list key for a name: the lower-cased full name.
function ns.Key(name)
    local n = ns.Name(name)
    return n and n:lower() or nil
end

-- "Evil Guy" from a unit (UnitNameUnmodified returns the first name and surname on Forever).
function ns.UnitFullName(unit)
    if not unit then return nil end
    local first, last
    if UnitNameUnmodified then
        local ok, a, b = pcall(UnitNameUnmodified, unit)
        if ok then first, last = a, b end
    end
    if first == nil and UnitName then
        local ok, a, b = pcall(UnitName, unit)
        if ok then first, last = a, b end
    end
    if secret(first) or secret(last) or type(first) ~= "string" then return nil end
    if type(last) == "string" and last ~= "" and last ~= (GetNormalizedRealmName and GetNormalizedRealmName()) then
        first = first .. " " .. last
    end
    return ns.Name(first)
end

function ns.IsMe(name)
    local n = ns.Name(name)
    return n ~= nil and KM.IsMe(n)
end

---------------------------------------------------------------------------
-- The guild
---------------------------------------------------------------------------

local function inGuild() return IsInGuild and KM.Plain(IsInGuild()) and true or false end
ns.InGuild = inGuild

-- "Kings-Forever", or nil when you aren't in a guild or the game doesn't know its name yet.
function ns.GuildKey()
    if not inGuild() or not GetGuildInfo then return nil end
    local ok, name = pcall(GetGuildInfo, "player")
    name = ok and KM.Plain(name) or nil
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. (KM.Realm() or "")
end

-- KM.RenameChar: this character's entry moves to its new key. Lists saved while the realm came back empty (the
-- November 2026 hotfix made "Kings-") fold into the guild's real list once the realm is known.
function ns.RenameChar(old, new)
    KM.MoveKey(ns.db.chars, old, new)
    local realm = KM.Realm()
    if not realm then return end
    local strays = {}
    for key in pairs(ns.db.lists) do
        if type(key) == "string" and key ~= "personal" and key:sub(-1) == "-" then strays[#strays + 1] = key end
    end
    for _, key in ipairs(strays) do KM.MoveKey(ns.db.lists, key, key .. realm) end
    for who, key in pairs(ns.db.chars) do
        if type(key) == "string" and key ~= "personal" and key:sub(-1) == "-" then ns.db.chars[who] = key .. realm end
    end
end

-- Which list this character uses now: the guild's, "personal" without a guild, or (in a guild whose name hasn't
-- loaded yet) the one it used last time.
function ns.ListKey()
    local g = ns.GuildKey()
    local char = KM.Char()
    if g then
        if ns.db then ns.db.chars[char] = g end
        return g
    end
    if inGuild() then return ns.db and ns.db.chars[char] or nil end
    return "personal"
end

function ns.IsPersonal() return ns.ListKey() == "personal" end

local function listOf(key)
    if not (ns.db and key) then return nil end
    local l = ns.db.lists[key]
    if not l then
        l = {}
        ns.db.lists[key] = l
    end
    l.entries = l.entries or {}
    l.seen = l.seen or {}
    l.heard = l.heard or {}
    return l
end

-- The current list ({ entries, seen, heard }), or nil while it can't be known.
function ns.List() return listOf(ns.ListKey()) end
function ns.Entries() local l = ns.List(); return l and l.entries or {} end

-- The guild roster's names (lower case, no realm), cached a minute; nil until it has loaded.
local rosterCache, rosterAt
local function roster()
    local now = GetTime and GetTime() or 0
    if rosterCache and now - rosterAt < 60 then return rosterCache end
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
    local ok, n = pcall(GetNumGuildMembers)
    n = ok and tonumber(KM.Plain(n)) or 0
    if n <= 0 then return nil end
    local names = {}
    for i = 1, math.min(n, 2000) do
        local ok2, name = pcall(GetGuildRosterInfo, i)
        name = ok2 and KM.Plain(name) or nil
        local k = type(name) == "string" and ns.Key(name)
        if k then names[k] = true end
    end
    rosterCache, rosterAt = names, now
    return names
end
function ns.RosterReset() rosterCache = nil end

-- Is this player in your guild? (unit when you have one: the most reliable).
function ns.IsGuildmate(name, unit)
    if not inGuild() then return false end
    if unit and UnitIsInMyGuild then
        local ok, v = pcall(UnitIsInMyGuild, unit)
        if ok and KM.Plain(v) then return true end
    end
    local n = ns.Name(name)
    if not n then return false end
    if C_GuildInfo and C_GuildInfo.MemberExistsByName then
        local ok, v = pcall(C_GuildInfo.MemberExistsByName, n)
        if ok and KM.Plain(v) then return true end
    end
    local r = roster()
    return r ~= nil and r[n:lower()] == true
end

---------------------------------------------------------------------------
-- Looking up
---------------------------------------------------------------------------

-- The live entry for a name (nil when not listed, or removed).
function ns.Get(name)
    local key = ns.Key(name)
    if not key then return nil end
    local e = ns.Entries()[key]
    if e and not e.del then return e, key end
end

-- By GUID (tooltips that hand over a GUID only).
function ns.GetByGUID(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    for key, e in pairs(ns.Entries()) do
        if e.g == guid and not e.del then return e, key end
    end
end

function ns.IsListed(name) return ns.Get(name) ~= nil end

-- Live entries, newest first: { { key, e }, ... }.
function ns.Sorted()
    local out = {}
    for key, e in pairs(ns.Entries()) do
        if not e.del then out[#out + 1] = { key = key, e = e } end
    end
    table.sort(out, function(a, b)
        if (a.e.t or 0) ~= (b.e.t or 0) then return (a.e.t or 0) > (b.e.t or 0) end
        return a.key < b.key
    end)
    return out
end

function ns.Count()
    local n = 0
    for _, e in pairs(ns.Entries()) do if not e.del then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
-- Callbacks (other modules and addons)
---------------------------------------------------------------------------

local callbacks = {}
function ns.Fire(event, ...)
    for _, fn in pairs(callbacks) do pcall(fn, event, ...) end
end

-- Something on the list changed (here or from a guildmate): page, badge, other modules. A guildmate's catch-up can
-- bring many entries at once, so their redraw waits a moment and happens once.
local redrawPending = false
function ns.Changed(key, how, from)
    if ns.ClearLookups then ns.ClearLookups() end
    ns.Fire("CHANGED", key, how, from)
    if not ns.Refresh then return end
    if not from then ns.Refresh() return end
    if redrawPending then return end
    redrawPending = true
    C_Timer.After(0.5, function() redrawPending = false; KM.Safe(ns.Refresh) end)
end

---------------------------------------------------------------------------
-- Adding, editing, removing
---------------------------------------------------------------------------

local function me() return KM.PlayerName() end

-- Adds a player, or edits their entry. Returns ok, message, how ("added" | "edited").
-- opts: { guid = their GUID, unit = a unit token for the guild check }
function ns.Save(name, reason, note, opts)
    opts = opts or {}
    if not ns.db then return false, "not ready yet." end
    local n = ns.Name(name)
    if not n then return false, "that isn't a character name." end
    if KM.IsMe(n) or (opts.unit and UnitIsUnit and call(UnitIsUnit, opts.unit, "player")) then
        return false, "you can't blacklist yourself."
    end
    if ns.IsGuildmate(n, opts.unit) then return false, n .. " is in your guild: guildmates can't be blacklisted." end
    local l = ns.List()
    if not l then return false, "your guild hasn't loaded yet; try again in a moment." end
    if not ns.REASON[reason or ""] then reason = "other" end
    note = ns.Clean(note)
    if note == "" then return false, "say why in the note (it's what your guild will read)." end
    local key = n:lower()
    local old = l.entries[key]
    local now = KM.Now()
    local e
    local how
    if old and not old.del then
        e = old
        how = "edited"
        e.eb = me()
        if e.eb == e.by then e.eb = nil end
    else
        e = { by = me(), t = now }
        how = "added"
        l.entries[key] = e
    end
    e.n, e.r, e.del = n, reason, nil
    e.e = math.max(now, (old and old.e or 0) + (old and 1 or 0))   -- a change always moves e forward
    e.note = ns.Cut(note, ns.NOTE_MAX)
    if ns.FitNote then ns.FitNote(e) end                            -- long names: the note gives way
    if opts.guid and type(opts.guid) == "string" and not secret(opts.guid) then e.g = opts.guid
    elseif old and old.g then e.g = old.g end
    if ns.SendEntry then KM.Safe(ns.SendEntry, key, e) end
    ns.Changed(key, how, nil)
    return true, (how == "added" and ("added " .. n .. " to the blacklist.") or ("updated " .. n .. "'s entry.")), how
end

-- Removes a player (a tombstone, shared like an edit). Returns ok, message.
function ns.Remove(name)
    if not ns.db then return false, "not ready yet." end
    local e, key = ns.Get(name)
    if not e then return false, (ns.Name(name) or tostring(name)) .. " isn't on the blacklist." end
    local now = KM.Now()
    e.del = true
    e.r, e.note = nil, nil
    e.e = math.max(now, (e.e or 0) + 1)
    e.eb = me()
    if e.eb == e.by then e.eb = nil end
    if ns.SendEntry then KM.Safe(ns.SendEntry, key, e) end
    ns.Changed(key, "removed", nil)
    return true, "removed " .. e.n .. " from the blacklist."
end

-- Removals older than TOMB_DAYS are forgotten (setting "purge"); a guildmate sending one that old is ignored.
function ns.Purge()
    if not ns.db or not ns.db.settings.purge then return 0 end
    local cutoff, n = KM.Now() - ns.TOMB_DAYS * DAY, 0
    for _, l in pairs(ns.db.lists) do
        for key, e in pairs(l.entries or {}) do
            if type(e) ~= "table" or (e.del and (e.e or 0) < cutoff) then
                l.entries[key] = nil
                if l.seen then l.seen[key] = nil end
                n = n + 1
            end
        end
    end
    return n
end

-- They were in your group just now (Alerts.lua).
function ns.Seen(key)
    local l = ns.List()
    if l and key then l.seen[key] = KM.Now() end
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load: safe twice.
function ns.InitDB()
    BlacklistKingDB = BlacklistKingDB or {}
    local db = BlacklistKingDB
    if not db.version then db.version = 1 end
    db.lists = type(db.lists) == "table" and db.lists or {}
    db.chars = type(db.chars) == "table" and db.chars or {}
    db.settings = db.settings or {}
    local s = db.settings
    for _, k in ipairs({ "share", "alertJoin", "alertInvite", "sound", "chatTag", "lfg", "tooltip", "purge" }) do
        if s[k] == nil then s[k] = true end
    end
    db.ui = db.ui or {}
    local u = db.ui
    u.sort = u.sort or "added"
    if u.desc == nil then u.desc = true end
    for key, l in pairs(db.lists) do
        if type(l) ~= "table" then db.lists[key] = nil
        else
            l.entries = type(l.entries) == "table" and l.entries or {}
            l.seen = type(l.seen) == "table" and l.seen or {}
            l.heard = type(l.heard) == "table" and l.heard or {}
            for k, e in pairs(l.entries) do
                if type(e) ~= "table" or type(e.n) ~= "string" then l.entries[k] = nil end
            end
        end
    end
    ns.db = db
end

---------------------------------------------------------------------------
-- The API (functions only, never the saved data)
---------------------------------------------------------------------------

local function copy(e, key)
    return { name = e.n, key = key, reason = e.r, reasonLabel = ns.ReasonLabel(e.r), note = e.note, by = e.by,
        added = e.t, changed = e.e, changedBy = e.eb or e.by }
end

-- Is this player on your guild's blacklist (or your own, without a guild)? name: "First Last", realm or not.
function API.IsListed(name) return ns.db ~= nil and ns.IsListed(name) end

-- A copy of their entry: { name, reason, reasonLabel, note, by, added, changed, changedBy }, or nil.
function API.Get(name)
    if not ns.db then return nil end
    local e, key = ns.Get(name)
    return e and copy(e, key) or nil
end

-- Every live entry, newest first (copies).
function API.GetAll()
    local out = {}
    if not ns.db then return out end
    for _, it in ipairs(ns.Sorted()) do out[#out + 1] = copy(it.e, it.key) end
    return out
end

-- fn(event, ...) with event "CHANGED" (key, "added" | "edited" | "removed", fromGuildmate or nil). Registering
-- again with the same owner replaces the old function.
function API.RegisterCallback(owner, fn)
    if owner == nil or type(fn) ~= "function" then return end
    callbacks[owner] = fn
end
function API.UnregisterCallback(owner) if owner ~= nil then callbacks[owner] = nil end end

---------------------------------------------------------------------------
-- /bl
---------------------------------------------------------------------------

-- "/bl add Evil Guy: took my gold" -> "Evil Guy", "took my gold". Without a colon: the first two words are the name
-- when the second starts with a capital (Forever names are "First Last"), else the first word.
function ns.ParseAdd(rest)
    rest = ns.Clean(rest or "")
    if rest == "" then return nil, "" end
    local a, b = rest:match("^([^:]+):%s*(.*)$")
    if a then return strtrim and strtrim(a) or a, b end
    local q, after = rest:match('^"([^"]+)"%s*(.*)$')
    if q then return q, after end
    local w1, w2, more = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
    if w1 and w2:match("^%u") then return w1 .. " " .. w2, more end
    local one, note = rest:match("^(%S+)%s*(.*)$")
    return one, note
end

local function targetName()
    if not (UnitExists and call(UnitExists, "target")) then return nil end
    if UnitIsPlayer and not call(UnitIsPlayer, "target") then return nil end
    return ns.UnitFullName("target"), UnitGUID and KM.Plain(call(UnitGUID, "target"))
end

local function help()
    KM.Print(ns, "commands:")
    KM.Print(ns, "/bl   open the Blacklist page")
    KM.Print(ns, "/bl add First Last: note   add a player (no note: opens the dialog; no name: your target)")
    KM.Print(ns, "/bl remove First Last   take a player off")
    KM.Print(ns, "/bl list   everyone on the list, in chat")
    KM.Print(ns, "/bl share on|off   share the list with your guild")
    KM.Print(ns, "Right-click a player (chat, portrait, party, raid, the Who list) for Add to Blacklist; Alt-click a group finder listing to blacklist its leader.")
end

SLASH_KINGMAKERBLACKLIST1 = "/bl"
SLASH_KINGMAKERBLACKLIST2 = "/blacklist"
SlashCmdList.KINGMAKERBLACKLIST = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if KM.IsShown("blacklist") then KM.Toggle(false) else KM.Show("blacklist") end
    elseif cmd == "add" then
        local name, note = ns.ParseAdd(rest)
        local guid
        if not name then name, guid = targetName() end
        if not name then KM.Print(ns, "/bl add First Last: note (or target a player first).") return end
        if not note or note == "" then
            if ns.OpenDialog then ns.OpenDialog({ name = name, guid = guid }) end
            return
        end
        local _, text = ns.Save(name, "other", note, { guid = guid })
        KM.Print(ns, text)
    elseif cmd == "remove" or cmd == "del" or cmd == "delete" then
        local name = rest ~= "" and rest or targetName()
        if not name then KM.Print(ns, "/bl remove First Last") return end
        local _, text = ns.Remove(name)
        KM.Print(ns, text)
    elseif cmd == "list" then
        local list = ns.Sorted()
        KM.Print(ns, #list == 0 and "the blacklist is empty." or (#list .. " on the " .. (ns.IsPersonal() and "list" or "guild's list") .. ":"))
        for _, it in ipairs(list) do
            KM.Print(ns, ns.RED .. it.e.n .. "|r  " .. ns.ReasonLabel(it.e.r) .. ": " .. (it.e.note or "") .. "  |cff808080(" .. (it.e.by or "?") .. ")|r")
        end
    elseif cmd == "share" then
        local r = rest:lower()
        local on = r == "on" or (r ~= "off" and not ns.db.settings.share)
        if ns.SetShare then ns.SetShare(on) else ns.db.settings.share = on end
        KM.Print(ns, on and "sharing with your guild: adds, edits and removals go to guildmates running King Maker, and theirs come to you."
            or "sharing off: nothing is sent, and guildmates' changes aren't read.")
        KM.Refresh("blacklist")
    else
        help()
    end
end
