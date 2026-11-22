local _, KM = ...
local ns = KM.Module("Cooldowns")

-- Cooldowns: saved data, reading the game's timers, which reading wins, events, the badge, reminders, /cdk and the
-- CooldownKing API.
--
-- A reading is turned into an absolute server-time "ready" timestamp (KM.Now() + seconds left), so it survives
-- logout and is right for alts. Sources, most trusted first:
--   recipe   C_TradeSkillUI.GetRecipeCooldown, while that profession's window is open (also finds new cooldowns)
--   item     C_Container.GetItemCooldown, for the Salt Shaker
--   spell    C_Spell.GetSpellCooldown(recipe spell), anywhere; its "ready" is only believed once it has shown it
--            knows crafting cooldowns at all (db.trust.spell), so it can't erase a timer we know
--   cast     UNIT_SPELLCAST_SUCCEEDED: "now + length" as an estimate until the game's own number replaces it
-- Nothing is read in combat; secret values are skipped.

CooldownKing = { API_VERSION = 1 }
local API = CooldownKing
ns.API = API

local WRAP = 2 ^ 32 / 1000   -- start times from before the computer last restarted come back "in the future"
local GCD = 60               -- anything shorter is the global cooldown, never a crafting cooldown
local LOG_MAX, IDLE_MAX = 60, 20
local OLD = 90 * 86400       -- characters not seen for this long are greyed and sorted last

function ns.Now() return KM.Now() end
function ns.Char() return KM.Char() end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
ns.Call = call

local function secret(v)
    if not issecretvalue then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end
ns.IsSecret = secret

local function round(x) return math.floor(x + 0.5) end

function ns.ItemName(id)
    if not id then return "?" end
    local m = KM.mods.Market
    if m and m.db and m.ItemName then
        local n = call(m.ItemName, id)
        if n then return n end
    end
    if C_Item and C_Item.GetItemInfo then
        local n = call(C_Item.GetItemInfo, id)
        if n then return n end
    end
    return "Item " .. id
end

function ns.ItemIcon(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then return call(C_Item.GetItemIconByID, id) end
end

-- "3d 4h", "5h 12m", "40m"
function ns.Duration(s)
    if not s then return "-" end
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
    if d > 0 then return d .. "d" .. (h > 0 and (" " .. h .. "h") or "") end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- A group key we still know: a catalogue group, or "r:<spell>" for a discovered or split recipe.
function ns.ValidGroup(key)
    if ns.GROUPS[key] then return true end
    local spell = type(key) == "string" and tonumber(key:match("^r:(%d+)$"))
    local l = spell and ns.db.learned[spell]
    return l ~= nil and (l.group == key or l.split == true)
end

local function charTables(c)
    c.cds = c.cds or {}
    c.pick = c.pick or {}
    c.hide = c.hide or {}
    c.log = c.log or {}
    c.profs = c.profs or {}
    c.tools = c.tools or {}
    c.unread = c.unread or {}
    c.read = c.read or {}
end

-- Runs when King Maker's saved variables load: safe twice.
function ns.InitDB()
    CooldownKingDB = CooldownKingDB or {}
    local db = CooldownKingDB
    if not db.version then db.version = 1 end
    db.chars = db.chars or {}      -- "First Last-Realm" -> { name, realm, class, faction, level, seen, profs, tools, cds, ... }
    db.learned = db.learned or {}  -- [spell] = { dur = real length, group = "r:<spell>" (discovered), prof, split }
    db.trust = db.trust or {}      -- spell = when the spell API first reported a crafting cooldown
    db.settings = db.settings or {}
    local s = db.settings
    if s.badge ~= "here" and s.badge ~= "here+alts" and s.badge ~= "any" then s.badge = "here+alts" end
    if s.noToolCounts == nil then s.noToolCounts = false end
    if s.chat == nil then s.chat = true end
    if s.toast == nil then s.toast = true end
    if s.sound == nil then s.sound = true end
    if s.login == nil then s.login = true end
    if s.altChat == nil then s.altChat = false end
    s.days = math.max(1, math.min(14, math.floor(tonumber(s.days) or 7)))
    db.ui = db.ui or {}
    local u = db.ui
    if u.view ~= "all" and u.view ~= "here" then u.view = "all" end
    u.sort = u.sort or "status"
    if u.desc == nil then u.desc = false end
    if u.readyOnly == nil then u.readyOnly = false end
    ns.db = db
    for _, c in pairs(db.chars) do
        charTables(c)
        -- a data change can retire a group: drop what we can no longer describe
        for g in pairs(c.cds) do if not ns.ValidGroup(g) then c.cds[g] = nil end end
        for g in pairs(c.unread) do if not ns.ValidGroup(g) then c.unread[g] = nil end end
    end
end

-- This character's record (made on first use).
function ns.Me()
    local key = KM.Char()
    local c = ns.db.chars[key]
    if not c then
        c = {}
        ns.db.chars[key] = c
    end
    charTables(c)
    return c, key
end

-- 2.3.0-style rename (Boot's KM.RenameChar calls every module's).
function ns.RenameChar(old, new)
    KM.MoveKey(ns.db.chars, old, new)
    local c = ns.db.chars[new]
    if c then c.name = KM.PlayerName() end
end

function ns.Forget(key)
    if not (ns.db and key and ns.db.chars[key]) then return false end
    ns.db.chars[key] = nil
    ns.Changed(true)
    return true
end

-- Finds a character by "First Last", "First Last-Realm" or a first name.
function ns.FindChar(text)
    if not text or text == "" then return nil end
    local q = text:lower()
    for key in pairs(ns.db.chars) do if key:lower() == q then return key end end
    for key, c in pairs(ns.db.chars) do
        if (c.name or ""):lower() == q or key:lower():match("^" .. q:gsub("%p", "%%%0") .. "%-") then return key end
    end
    for key, c in pairs(ns.db.chars) do
        if ((c.name or key):lower():match("^(%S+)")) == q then return key end
    end
end

-- Characters not seen for 90 days. Returns how many were forgotten.
function ns.ForgetOld()
    local now, me, n = ns.Now(), KM.Char(), 0
    for key, c in pairs(ns.db.chars) do
        if key ~= me and (c.seen or 0) < now - OLD then ns.db.chars[key] = nil; n = n + 1 end
    end
    if n > 0 then ns.Changed(true) end
    return n
end

---------------------------------------------------------------------------
-- The character you're on: professions, tools, what it knows
---------------------------------------------------------------------------

-- Reads professions; true when the game answered with at least one. A profession that's gone takes its groups
-- with it (only here, only when the game listed others, so a slow login can't wipe anything).
function ns.ReadProfs(c)
    if not (GetProfessions and GetProfessionInfo) then return false end
    local res = { pcall(GetProfessions) }
    if not res[1] then return false end
    local profs, any = {}, false
    for i, idx in pairs(res) do
        if i ~= 1 and idx and not secret(idx) then
            local name, _, cur = call(GetProfessionInfo, idx)
            if type(name) == "string" then
                any = true
                local id = ns.PROF_IDS[name]
                if id then profs[id] = tonumber(cur) or 0 end
            end
        end
    end
    if not any then return false end
    c.profs = profs
    ns.profsRead = true   -- this session the game listed them: a profession missing from the list is gone
    for gk in pairs(c.cds) do
        local g = ns.Group(gk)
        if g and g.prof and not profs[g.prof] then c.cds[gk] = nil end
    end
    for gk in pairs(c.unread) do
        local g = ns.Group(gk)
        if g and g.prof and not profs[g.prof] then c.unread[gk] = nil end
    end
    return true
end

-- Tools owned (bags or bank): true / false; left alone when nothing can tell.
function ns.ReadTools(c)
    for id in pairs(ns.TOOLS) do
        local n
        if C_Item and C_Item.GetItemCount then n = call(C_Item.GetItemCount, id, true) end
        if n == nil and InventoryKing and InventoryKing.GetCount then
            local _, by = call(InventoryKing.GetCount, id)
            if type(by) == "table" then n = by[KM.Char()] or 0 end
        end
        if type(n) == "number" and not secret(n) then c.tools[id] = n > 0 end
    end
end

function ns.Snapshot()
    if not ns.db then return end
    local c, key = ns.Me()
    c.name = KM.PlayerName()
    c.realm = KM.Realm() or (c.realm ~= "" and c.realm) or ""
    if UnitClass then
        local _, class = UnitClass("player")
        c.class = class or c.class
    end
    if UnitFactionGroup then c.faction = UnitFactionGroup("player") or c.faction end
    if UnitLevel then c.level = UnitLevel("player") or c.level end
    c.seen = ns.Now()
    ns.ReadProfs(c)
    ns.ReadTools(c)
    return c, key
end

-- Skill in a profession: the game's, else the one Crafting Profits saved (this character only).
function ns.Skill(c, prof)
    if not prof then return nil end
    if c.profs and c.profs[prof] then return c.profs[prof] end
    if c == ns.db.chars[KM.Char()] then
        if ns.profsRead then return 0 end
        local m = KM.mods.Market
        if m and m.db and m.Char then
            local mc = call(m.Char)
            local v = mc and mc.skills and mc.skills[prof]
            if type(v) == "table" and v.cur then return v.cur end
        end
    end
    return nil
end

-- true / false, or nil when nothing says.
function ns.HasProf(c, g)
    local s = ns.Skill(c, g.prof)
    if s == nil then return nil end
    return s >= (g.skill or 1)
end

-- Does the character you're on know this recipe, and by which test.
function ns.Knows(spell)
    local c = ns.Me()
    local cat = ns.CATALOGUE[spell]
    if cat and cat.item then   -- the Salt Shaker: the profession at the skill, and the shaker itself
        local g = ns.GROUPS[cat.group]
        if c.tools[g.tool] ~= true then return false end
        local s = ns.Skill(c, g.prof)
        return s == nil or s >= g.skill, "tool"
    end
    for _, e in pairs(c.cds) do
        if e.known and e.known[spell] then return true, "seen" end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if call(C_SpellBook.IsSpellKnown, spell) then return true, "spellbook" end
    elseif IsPlayerSpell then
        if call(IsPlayerSpell, spell) then return true, "spellbook" end
    end
    local m = KM.mods.Market
    if m and m.db and m.Char then
        local mc = call(m.Char)
        if mc and mc.known and mc.known[spell] then return true, "market" end
    end
    return false
end

-- Works out which groups this character tracks; returns nothing. A group is tracked when the character has the
-- profession (or nothing says otherwise) and knows a member; the "open your window once" hint is for a character
-- with the profession at the skill whose window we have never read.
function ns.UpdateTracking(c)
    for _, gk in ipairs(ns.GroupKeys()) do
        local g = ns.Group(gk)
        if g then
            local has = ns.HasProf(c, g)
            local known = {}
            for _, spell in ipairs(ns.Members(gk)) do
                if ns.Knows(spell) then known[spell] = true end
            end
            local any = next(known) ~= nil
            if g.needTool and c.tools[g.tool] == false then
                any = false
                c.cds[gk] = nil
            end
            if any and has ~= false then
                local e = c.cds[gk] or {}
                c.cds[gk] = e
                e.known = e.known or {}
                for s in pairs(known) do e.known[s] = true end
                c.unread[gk] = nil
            elseif has == true and not c.cds[gk] and not g.discovered and not g.needTool and not c.read[g.prof] then
                c.unread[gk] = true
            else
                c.unread[gk] = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Readings
---------------------------------------------------------------------------

-- Length in seconds: what the game showed (db.learned), else the catalogue's.
function ns.Dur(spell)
    local l = ns.db and ns.db.learned[spell]
    if l and l.dur and l.dur > 0 then return l.dur end
    local c = ns.CATALOGUE[spell]
    return c and c.dur or 86400
end

-- The longest believable "seconds left" for a spell (a bad wrap correction gives nonsense).
function ns.Cap(spell)
    if ns.CATALOGUE[spell] then return 1.5 * ns.Dur(spell) end
    return ns.MAX_DISCOVERED
end

-- Seconds left from a start/duration pair in GetTime() units; 0 when not on cooldown; nil when unusable.
function ns.Left(start, duration)
    if secret(start) or secret(duration) then return nil end          -- restricted (combat, instances)
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if start <= 0 or duration < GCD then return 0 end                  -- not on cooldown (or just the GCD)
    local now = GetTime()
    if start > now + 1 then start = start - WRAP end                   -- WoWUIBugs #47
    return math.max(0, start + duration - now)
end

local lastCast   -- { spell, t }: the last tracked craft this session

function ns.ReadSpell(spell)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, a, b = pcall(C_Spell.GetSpellCooldown, spell)
    if not ok or a == nil or secret(a) then return nil end
    local start, duration
    if type(a) == "table" then start, duration = a.startTime, a.duration else start, duration = a, b end
    local left = ns.Left(start, duration)
    if left == nil then return nil end
    if left > 0 and not ns.db.trust.spell then ns.db.trust.spell = ns.Now() end
    return { spell = spell, left = left, src = "spell", dur = left > 0 and duration or nil }
end

-- The Salt Shaker: the item's cooldown, else its use spell.
function ns.ReadItem(spell)
    local cat = ns.CATALOGUE[spell]
    local item = cat and cat.item
    local start, duration
    if item and C_Container and C_Container.GetItemCooldown then
        start, duration = call(C_Container.GetItemCooldown, item)
    elseif item and C_Item and C_Item.GetItemCooldown then
        start, duration = call(C_Item.GetItemCooldown, item)
    end
    local left = ns.Left(start, duration)
    if left == nil then
        local r = ns.ReadSpell(spell)
        if r then r.src = "item" end
        return r
    end
    return { spell = spell, left = left, src = "item", dur = left > 0 and duration or nil }
end

local function learnDur(spell, dur)
    if not (spell and dur and dur >= GCD) then return end
    local l = ns.db.learned[spell] or {}
    ns.db.learned[spell] = l
    l.dur = math.floor(dur / 60 + 0.5) * 60
end

local function pushIdle(e, now)
    if not e.readySince then return end
    e.idle = e.idle or {}
    table.insert(e.idle, { e.readySince, now })
    while #e.idle > IDLE_MAX do table.remove(e.idle, 1) end
    e.readySince = nil
end

-- Entries whose stored timer an item/spell "ready" contradicts: entry -> when that was first seen (this session).
local doubt = setmetatable({}, { __mode = "k" })
local DOUBT = 600

-- Writes one reading into a group's entry; true when the stored timer moved.
function ns.SetReady(c, gk, ready, r)
    local e = c.cds[gk]
    if not e then return false end
    local now = ns.Now()
    local was = e.ready
    local changed = false
    if ready <= now then
        if was == nil then
            e.ready, e.readySince = now, now   -- first reading ever: ready since we don't know when; no reminder
            changed = true
        elseif was > now then
            e.ready = now                      -- came ready (early, or the estimate was long): CheckFlips reminds
            changed = true
        end
    else
        doubt[e] = nil
        pushIdle(e, now)
        if was == nil or math.abs(was - ready) > 2 then changed = true end
        e.ready = ready
    end
    e.spell = r.spell or e.spell
    e.src, e.at, e.est, e.day = r.src, now, nil, r.day or nil
    if ready > now then
        e.dur = (r.dur and r.dur >= GCD and r.dur) or ns.Dur(e.spell)
        if r.src == "spell" or r.src == "item" then learnDur(r.spell, r.dur) end
    end
    return changed
end

-- Applies a group's readings: the longest "on cooldown" wins (a shared group's cooldown is the latest over its
-- members); a "ready" from the spell API counts only once that API has proven itself (db.trust.spell), or when
-- what we stored has run out anyway.
function ns.ApplyGroup(c, gk, readings, reason)
    local e = c.cds[gk]
    if not e then return false end
    local now = ns.Now()
    local best, ready
    for _, r in ipairs(readings) do
        if r.left > 0 then
            if r.left <= ns.Cap(r.spell) and (not best or r.left > best.left) then best = r end
        elseif not ready or ready.src == "spell" then
            ready = r
        end
    end
    -- Split detection: the member just crafted reads a long cooldown while another member reads ready, on a client
    -- whose spell API we trust: that member doesn't share the group's cooldown. It gets its own row from now on.
    local g = ns.Group(gk)
    if best and ready and g and g.shared and ns.db.trust.spell and reason ~= "cast1" and lastCast
        and lastCast.spell == best.spell and now - lastCast.t <= 60 and best.left >= 1800 then
        local spell = best.spell
        local l = ns.db.learned[spell] or {}
        ns.db.learned[spell] = l
        l.split = true
        local own = "r:" .. spell
        c.cds[own] = c.cds[own] or { known = { [spell] = true } }
        if e.known then e.known[spell] = nil end
        ns.SetReady(c, own, now + round(best.left), best)
        KM.Print(ns, ns.Group(own).label .. " has a cooldown of its own (not shared with the other transmutes): shown on its own line now.")
        best = nil
        e.ready, e.est = now, nil   -- the estimate came from that craft
    end
    if best then
        return ns.SetReady(c, gk, now + round(best.left), best)
    elseif ready then
        local fresh = e.est and e.ready and e.ready > now and now - (e.at or 0) < 600   -- the API lags a craft
        local accept = ready.src ~= "spell" or ((ns.db.trust.spell or not e.ready or e.ready <= now) and not fresh)
        -- A "ready" from the item or spell API against a timer the game itself gave us (not a craft estimate) is a
        -- blip until it holds: right after a loading screen those APIs read 0 for a moment. Believed once it has
        -- held for DOUBT seconds with no "on cooldown" reading in between (the recipe window is always believed).
        if accept and ready.src ~= "recipe" and not e.est and e.ready and e.ready > now + 60 then
            doubt[e] = doubt[e] or now
            accept = now - doubt[e] >= DOUBT
        end
        if accept then
            doubt[e] = nil
            return ns.SetReady(c, gk, now, ready)
        end
    end
    return false
end

local deferred, deferredWindow = false, false

-- Reads every tracked recipe of the character you're on (spell and item APIs).
function ns.ReadAll(reason)
    if not ns.db then return end
    if InCombatLockdown and InCombatLockdown() then deferred = true return end
    deferred = false
    local c = ns.Snapshot()
    ns.UpdateTracking(c)
    local keys = {}
    for gk in pairs(c.cds) do keys[#keys + 1] = gk end
    local changed = false
    for _, gk in ipairs(keys) do
        local e = c.cds[gk]
        local readings = {}
        for spell in pairs(e and e.known or {}) do
            if ns.GroupOf(spell) == gk then
                local cat = ns.CATALOGUE[spell]
                local r = (cat and cat.item) and ns.ReadItem(spell) or ns.ReadSpell(spell)
                if r then readings[#readings + 1] = r end
            end
        end
        if ns.ApplyGroup(c, gk, readings, reason) then changed = true end
    end
    ns.AfterRead(changed)
    return changed
end

-- Reads the open profession window: authoritative timers, what's learned, and new cooldowns (discovery).
function ns.ReadWindow()
    if not ns.db then return end
    if InCombatLockdown and InCombatLockdown() then deferredWindow = true return end
    deferredWindow = false
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
    if T.IsTradeSkillLinked and call(T.IsTradeSkillLinked) then return end    -- someone else's window
    local info = call(T.GetBaseProfessionInfo)
    local prof = type(info) == "table" and info.professionName and ns.PROF_IDS[info.professionName]
    local ids = call(T.GetAllRecipeIDs)
    if type(ids) ~= "table" then return end
    local c = ns.Snapshot()
    local now = ns.Now()
    if prof then c.read[prof] = now end
    local byGroup, found = {}, 0
    for _, id in ipairs(ids) do
        local ri = call(T.GetRecipeInfo, id)
        if type(ri) == "table" and ri.learned then
            local cd, isDay
            if T.GetRecipeCooldown then cd, isDay = call(T.GetRecipeCooldown, id) end
            local ok = not secret(cd) and (cd == nil or type(cd) == "number")
            if not ok then cd = nil end
            local gk = ns.GroupOf(id)
            if not gk and ok and cd and cd >= ns.MIN_TRACKED and cd <= ns.MAX_DISCOVERED then
                local l = ns.db.learned[id] or {}
                ns.db.learned[id] = l
                l.group, l.prof = "r:" .. id, l.prof or prof
                l.dur = l.dur or math.ceil(cd / 3600) * 3600   -- a first guess; the spell API or a craft corrects it
                gk = l.group
                found = found + 1
            end
            local cat = ns.CATALOGUE[id]
            if gk and not (cat and cat.item) then
                local e = c.cds[gk] or {}
                c.cds[gk] = e
                e.known = e.known or {}
                e.known[id] = true
                c.unread[gk] = nil
                if ok then
                    byGroup[gk] = byGroup[gk] or {}
                    table.insert(byGroup[gk], { spell = id, left = (cd and cd > 0) and cd or 0, src = "recipe", day = isDay and true or nil })
                    if cd and cd > 0 and lastCast and lastCast.spell == id and now - lastCast.t <= 60 then
                        learnDur(id, cd + (now - lastCast.t))
                    end
                end
            end
        end
    end
    if found > 0 then
        KM.Print(ns, "found " .. found .. " more crafting cooldown" .. (found == 1 and "" or "s") .. " in your " .. ns.ProfName(prof) .. " window: tracking " .. (found == 1 and "it" or "them") .. " too.")
    end
    local changed = found > 0
    for gk, list in pairs(byGroup) do
        if ns.ApplyGroup(c, gk, list, "window") then changed = true end
    end
    ns.AfterRead(changed)
end

-- A craft we track: log it, and estimate "now + length" until the game's own number replaces it.
function ns.OnCast(unit, spell)
    if not ns.db or unit ~= "player" or secret(spell) or type(spell) ~= "number" then return end
    local gk = ns.GroupOf(spell)
    if not gk then return end
    local c = ns.Me()
    local now = ns.Now()
    local e = c.cds[gk] or {}
    c.cds[gk] = e
    e.known = e.known or {}
    e.known[spell] = true
    c.hide[gk] = nil
    c.unread[gk] = nil
    table.insert(c.log, { now, gk, spell })
    while #c.log > LOG_MAX do table.remove(c.log, 1) end
    lastCast = { spell = spell, t = now }
    pushIdle(e, now)
    local dur = ns.Dur(spell)
    e.ready, e.dur, e.spell, e.src, e.at, e.est, e.day = now + dur, dur, spell, "cast", now, true, nil
    C_Timer.After(1, function() ns.ReadAll("cast1") end)
    C_Timer.After(3, function() ns.ReadAll("cast3") end)
    ns.AfterRead(true)
end

function ns.LastCast() return lastCast end

---------------------------------------------------------------------------
-- What's ready, the badge
---------------------------------------------------------------------------

-- Does this (character, group) count as ready for the badge and reminders.
function ns.Counts(c, gk, e, now)
    if not (e and e.ready) or e.ready > (now or ns.Now()) then return false end
    if c.hide and c.hide[gk] then return false end
    local g = ns.Group(gk)
    if not g then return false end
    if g.tool and not g.needTool and not ns.db.settings.noToolCounts and c.tools and c.tools[g.tool] == false then return false end
    return true
end

local function charName(c, key) return c.name or (key and key:match("^(.-)%-")) or key or "?" end
ns.CharName = charName

-- What's ready: here = { item }, alts = { item }; item = { key, c, gk, e, label, name }.
function ns.ReadyList()
    local now, me = ns.Now(), KM.Char()
    local here, alts = {}, {}
    for key, c in pairs(ns.db and ns.db.chars or {}) do
        for gk, e in pairs(c.cds or {}) do
            if ns.Counts(c, gk, e, now) then
                local item = { key = key, c = c, gk = gk, e = e, label = ns.Group(gk).label, name = charName(c, key) }
                table.insert(key == me and here or alts, item)
            end
        end
    end
    local function order(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.key < b.key
    end
    table.sort(here, order)
    table.sort(alts, order)
    return here, alts
end

-- The sidebar badge: { count, color = "red" | "gold", tip } (a plain count string on a Shell that predates count
-- badges), or nil. Red = ready on the character you're on; gold = only alts have one (setting "here+alts").
function ns.Badge()
    if not ns.db then return nil end
    local here, alts = ns.ReadyList()
    local mode = ns.db.settings.badge
    local n, color, list = 0, nil, nil
    if mode == "any" then
        n, color = #here + #alts, "red"
        list = {}
        for _, it in ipairs(here) do list[#list + 1] = it end
        for _, it in ipairs(alts) do list[#list + 1] = it end
    elseif #here > 0 then
        n, color, list = #here, "red", here
    elseif mode == "here+alts" and #alts > 0 then
        n, color, list = #alts, "gold", alts
    end
    if n == 0 then return nil end
    local parts = {}
    for _, it in ipairs(list) do
        local g = ns.Group(it.gk)
        parts[#parts + 1] = it.label .. " is ready on " .. it.name .. ((g and g.where) and (" (" .. g.where .. ")") or "") .. "."
    end
    local tip = table.concat(parts, " ")
    if KM.BadgeTables then return { count = n, color = color, tip = tip } end
    return tostring(n)
end

function API.ReadyCount(scope)
    if not ns.db then return 0 end
    local here, alts = ns.ReadyList()
    if scope == "here" then return #here elseif scope == "alts" then return #alts end
    return #here + #alts
end

-- Redraws the badges when they changed (cheap to call after every reading).
local lastBadge
function ns.Badges(force)
    local b = ns.Badge()
    local sig = type(b) == "table" and (b.count .. b.color .. (b.tip or "")) or tostring(b)
    if not force and sig == lastBadge then return end
    lastBadge = sig
    if KM.RefreshBadges then KM.Safe(KM.RefreshBadges) else KM.Refresh() end
end

---------------------------------------------------------------------------
-- Reminders
---------------------------------------------------------------------------

-- Turns expired timers into "ready" (readySince) and reminds for the ones that came ready just now. silent: at
-- login, for what ran out while you were away (the login line covers those).
function ns.CheckFlips(silent)
    if not ns.db then return false end
    local now, me = ns.Now(), KM.Char()
    local flips = {}
    for key, c in pairs(ns.db.chars) do
        for gk, e in pairs(c.cds or {}) do
            if e.ready and e.ready <= now and not e.readySince then
                e.readySince = math.min(e.ready, now)
                e.est = nil
                if not silent and ns.Counts(c, gk, e, now) then flips[#flips + 1] = { key = key, c = c, gk = gk, e = e } end
            end
        end
    end
    for _, f in ipairs(flips) do
        if f.key == me then ns.Remind(f) elseif ns.db.settings.altChat then ns.RemindAlt(f) end
    end
    return #flips > 0
end

function ns.Remind(f)
    local s = ns.db.settings
    local g = ns.Group(f.gk)
    local label = g and g.label or f.gk
    if s.chat then
        local text = label .. " is ready" .. ((g and g.where) and (" (" .. g.where .. ")") or "") .. "."
        local pick = ns.Pick and ns.Pick(f.key, f.gk)
        if pick then
            local v = ns.Value and ns.Value(pick)
            text = text .. " Best: " .. ns.ItemName(ns.Product(pick)) .. (v and v.profit and (", " .. KM.Money(v.profit) .. " profit") or "") .. "."
        end
        KM.Print(ns, text)
    end
    if s.toast and ns.Toast then KM.Safe(ns.Toast, label .. " is ready", g and g.icon) end
    if s.sound and PlaySound and SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND then pcall(PlaySound, SOUNDKIT.LOOT_WINDOW_COIN_SOUND) end
end

function ns.RemindAlt(f)
    local g = ns.Group(f.gk)
    KM.Print(ns, (g and g.label or f.gk) .. " is ready on " .. charName(f.c, f.key) .. ".")
end

-- One line at login: what's ready on your alts (and here). Nothing when nothing is.
function ns.LoginLine()
    if not (ns.db and ns.db.settings.login) then return end
    local here, alts = ns.ReadyList()
    if #here == 0 and #alts == 0 then return end
    local a, h = {}, {}
    for _, it in ipairs(alts) do a[#a + 1] = it.label .. " (" .. it.name .. ")" end
    for _, it in ipairs(here) do h[#h + 1] = it.label end
    local text = (#a > 0 and ("Ready on your alts: " .. table.concat(a, ", ") .. ".") or "")
    if #h > 0 then text = text .. (#a > 0 and " " or "") .. "Here: " .. table.concat(h, ", ") .. "." end
    KM.Print(ns, text)
end

---------------------------------------------------------------------------
-- After a reading: badges, the page, other addons
---------------------------------------------------------------------------

local callbacks = {}

function API.RegisterCallback(owner, fn)
    if owner == nil or type(fn) ~= "function" then return false end
    callbacks[owner] = fn
    return true
end
function API.UnregisterCallback(owner) if owner ~= nil then callbacks[owner] = nil end end

local function fire(event) for _, fn in pairs(callbacks) do pcall(fn, event) end end

-- Something changed (a reading, forgetting, a setting): redraw what shows it and tell other addons.
function ns.Changed(changed)
    ns.Badges(changed)
    if KM.IsShown("cooldowns") then KM.Refresh("cooldowns") end
    if changed then
        fire("CHANGED")
    end
end

function ns.AfterRead(changed)
    local flipped = ns.CheckFlips(false)
    ns.Changed(changed or flipped)
end

---------------------------------------------------------------------------
-- Rows for the page
---------------------------------------------------------------------------

-- One (character, group): { key, c, gk, g, e, me, ready, left, idle, frac, est, noTool, unread, old }.
function ns.Row(key, c, gk, e, now)
    local g = ns.Group(gk)
    local row = { key = key, c = c, gk = gk, g = g, e = e, me = key == KM.Char(), old = (c.seen or 0) < now - OLD }
    if not e then row.unread = true return row end
    row.noTool = g and g.tool and not g.needTool and c.tools and c.tools[g.tool] == false or false
    row.est = e.est
    if e.ready and e.ready <= now then
        row.ready = true
        row.idle = now - (e.readySince or e.ready)
        row.frac = 1
    elseif e.ready then
        row.left = e.ready - now
        local dur = e.dur or ns.Dur(e.spell)
        row.frac = math.max(0, math.min(1, 1 - row.left / math.max(1, dur)))
    else
        row.unread = true   -- known, never read: a craft or the window fills it in
    end
    return row
end

-- view "all" | "here"; prof = a Market profession id or nil; readyOnly.
function ns.Entries(view, prof, readyOnly)
    local now, me = ns.Now(), KM.Char()
    local out = {}
    for key, c in pairs(ns.db.chars) do
        if view ~= "here" or key == me then
            for gk, e in pairs(c.cds or {}) do
                local g = ns.Group(gk)
                if g and not c.hide[gk] and (not prof or g.prof == prof) then
                    local row = ns.Row(key, c, gk, e, now)
                    if not readyOnly or row.ready then out[#out + 1] = row end
                end
            end
            if not readyOnly then
                for gk in pairs(c.unread or {}) do
                    local g = ns.Group(gk)
                    if g and not c.cds[gk] and (not prof or g.prof == prof) then out[#out + 1] = ns.Row(key, c, gk, nil, now) end
                end
            end
        end
    end
    return out
end

-- Sorts rows: "status" = ready first (longest idle first), then soonest; this character first among equals.
function ns.SortRows(rows, key, desc)
    local function status(r)
        if r.unread then return 3e9 end
        if r.ready then return -(r.idle or 0) end
        return r.left or 2e9
    end
    local function val(r)
        if key == "name" then return (r.g and r.g.label or r.gk):lower() end
        if key == "char" then return charName(r.c, r.key):lower() end
        if key == "each" or key == "week" then
            local v = r[key]
            return v and -v or math.huge
        end
        return status(r)
    end
    table.sort(rows, function(a, b)
        if a.old ~= b.old then return b.old end
        local x, y = val(a), val(b)
        if x ~= y then if desc then return x > y end return x < y end
        if a.me ~= b.me then return a.me end
        if a.key ~= b.key then return a.key < b.key end
        return a.gk < b.gk
    end)
    return rows
end

function API.GetAll()
    if not ns.db then return {} end
    local out, now = {}, ns.Now()
    for key, c in pairs(ns.db.chars) do
        for gk, e in pairs(c.cds or {}) do
            local g = ns.Group(gk)
            if g then
                out[#out + 1] = { char = key, group = gk, label = g.label, ready = e.ready, left = e.ready and math.max(0, e.ready - now) or nil,
                    dur = e.dur, pick = ns.Pick and ns.Pick(key, gk) or nil, est = e.est, src = e.src }
            end
        end
    end
    return out
end

-- The cooldown length of a recipe we track (seconds), or nil: Crafting Profits' "CD" tag uses it.
function API.Length(spell)
    if not ns.db or type(spell) ~= "number" or not ns.GroupOf(spell) then return nil end
    return ns.Dur(spell)
end

-- The group's state for the character you're on: "ready" | seconds left | nil (not tracked here).
function API.State(spell)
    if not ns.db then return nil end
    local gk = type(spell) == "number" and ns.GroupOf(spell)
    local e = gk and ns.Me().cds[gk]
    if not (e and e.ready) then return nil end
    local left = e.ready - ns.Now()
    if left <= 0 then return "ready" end
    return left
end

-- The Profession panel's "Cooldown" line for a recipe: "READY  (4d; +32g a week)", or nil when it has none.
function API.PanelText(spell, profit)
    local dur = API.Length(spell)
    if not dur then return nil end
    local st = API.State(spell)
    local C = KM.UI.C
    local s = st == "ready" and (KM.UI.Hex(C.good) .. "READY|r") or (type(st) == "number" and ns.Duration(st)) or "-"
    local extra = ns.Duration(dur)
    if profit then extra = extra .. "; " .. KM.Money(profit * 7 * 86400 / dur) .. " a week" end
    return s .. KM.UI.Hex(C.dim) .. "  (" .. extra .. ")|r"
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local pend = {}
local function soon(key, delay, fn)
    if pend[key] then return end
    pend[key] = true
    C_Timer.After(delay, function() pend[key] = nil; KM.Safe(fn) end)
end

local spellsSeen, ticker = false, nil

function ns.Tick()
    if not ns.db then return end
    if ns.CheckFlips(false) then ns.Changed(true) end
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",
    "BAG_UPDATE_DELAYED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE")
f:SetScript("OnEvent", function(_, event, a1)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        ns.Snapshot()
        ns.CheckFlips(true)   -- what ran out while you were away: ready, no pop-ups (the login line says it)
        C_Timer.After(2, function() KM.Safe(ns.ReadAll, "login") end)
        if ns.RegisterIntegrations then KM.Safe(ns.RegisterIntegrations) end
        if not ticker and C_Timer.NewTicker then ticker = C_Timer.NewTicker(15, function() KM.Safe(ns.Tick) end) end
        C_Timer.After(6, function() KM.Safe(ns.LoginLine) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        soon("pew", 3, function() ns.ReadAll("world") end)   -- spell data can arrive late on first login
    elseif event == "PLAYER_LOGOUT" then
        local c = ns.db.chars[KM.Char()]
        if c then c.seen = ns.Now() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if deferredWindow then soon("window", 0.3, ns.ReadWindow) end
        if deferred then soon("read", 0.5, function() ns.ReadAll("combat") end) end
    elseif event == "SPELLS_CHANGED" then
        if not spellsSeen then spellsSeen = true; soon("read", 1, function() ns.ReadAll("spells") end) end
    elseif event == "NEW_RECIPE_LEARNED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        local spell = type(a1) == "number" and not secret(a1) and a1 or nil
        local gk = spell and ns.GroupOf(spell)
        if gk then
            local c = ns.Me()
            local e = c.cds[gk] or {}
            c.cds[gk] = e
            e.known = e.known or {}
            e.known[spell] = true
        end
        soon("read", 1, function() ns.ReadAll("learned") end)
    elseif event == "SKILL_LINES_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        soon("read", 1, function() ns.ReadAll("skills") end)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        if InCombatLockdown and InCombatLockdown() then deferred = true return end   -- fires on every GCD: nothing in combat
        soon("read", 0.5, function() ns.ReadAll("spell") end)
    else -- the profession window
        soon("window", 0.3, ns.ReadWindow)
    end
end)

-- Crafts: the player's own casts only (RegisterUnitEvent when the client has it).
local castFrame = CreateFrame("Frame")
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("UNIT_SPELLCAST_SUCCEEDED") then
    local ok = castFrame.RegisterUnitEvent and pcall(castFrame.RegisterUnitEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    if not ok then KM.Register(castFrame, "UNIT_SPELLCAST_SUCCEEDED") end
end
castFrame:SetScript("OnEvent", function(_, _, unit, _, spell) KM.Safe(ns.OnCast, unit, spell) end)

function ns.IsDeferred() return deferred end

---------------------------------------------------------------------------
-- /cdk
---------------------------------------------------------------------------

function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("cooldowns") end
    if show then KM.Show("cooldowns") elseif KM.IsShown("cooldowns") then KM.Toggle(false) end
end

local function statusText(row)
    if row.unread then return "open " .. ns.ProfName(row.g and row.g.prof) .. " once to read" end
    if row.ready then return "READY" .. ((row.idle or 0) >= 3600 and (" (" .. ns.Duration(row.idle) .. " idle)") or "") end
    return ns.Duration(row.left) .. (row.est and " est" or "")
end
ns.StatusPlain = statusText

function ns.PrintList()
    local rows = ns.SortRows(ns.Entries("all"), "status")
    if #rows == 0 then
        KM.Print(ns, "nothing tracked yet. Log in on each crafter and open its profession window once.")
        return
    end
    for _, r in ipairs(rows) do
        KM.Print(ns, (r.g and r.g.label or r.gk) .. " - " .. charName(r.c, r.key) .. ": " .. statusText(r))
    end
end

function ns.Debug()
    local c = ns.Me()
    KM.Print(ns, "trust.spell: " .. tostring(ns.db.trust.spell) .. "; profs: " .. (function()
        local t = {} for id, s in pairs(c.profs) do t[#t + 1] = ns.ProfName(id) .. " " .. s end return table.concat(t, ", ") end)())
    for _, spell in ipairs(ns.AllSpells()) do
        local known, how = ns.Knows(spell)
        local cat = ns.CATALOGUE[spell]
        local r = (cat and cat.item) and ns.ReadItem(spell) or ns.ReadSpell(spell)
        local rc
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown then rc = call(C_TradeSkillUI.GetRecipeCooldown, spell) end
        if known or (r and r.left > 0) then
            KM.Print(ns, spell .. " " .. (ns.GroupOf(spell) or "?") .. ": known " .. tostring(known) .. (how and (" (" .. how .. ")") or "")
                .. ", " .. (r and (r.src .. " " .. math.floor(r.left) .. "s left" .. (r.dur and (" of " .. math.floor(r.dur)) or "")) or "no reading")
                .. ", recipe API " .. tostring(rc) .. ", length " .. ns.Dur(spell))
        end
    end
end

local function help()
    KM.Print(ns, "/cdk   open the Cooldowns page (or /km cooldowns)")
    KM.Print(ns, "/cdk list   every character's cooldowns, ready ones first")
    KM.Print(ns, "/cdk scan   read every cooldown now")
    KM.Print(ns, "/cdk badge here|alts|any   what the sidebar count counts")
    KM.Print(ns, "/cdk remind on|off   chat line, pop-up and sound when one is ready")
    KM.Print(ns, "/cdk forget First Last   stop tracking a character")
    KM.Print(ns, "/cdk debug   what the game reports for each recipe (for bug reports)")
end

SLASH_COOLDOWNKING1 = "/cdk"
SLASH_COOLDOWNKING2 = "/cooldownking"
SlashCmdList.COOLDOWNKING = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "list" then
        ns.PrintList()
    elseif cmd == "scan" or cmd == "read" then
        local changed = ns.ReadAll("slash")
        if InCombatLockdown and InCombatLockdown() then KM.Print(ns, "in combat: reading after the fight.")
        else KM.Print(ns, changed and "read your cooldowns: something changed." or "read your cooldowns: nothing new.") end
    elseif cmd == "badge" then
        local map = { here = "here", alts = "here+alts", any = "any" }
        local v = map[rest:lower()]
        if v then
            ns.db.settings.badge = v
            ns.Changed(true)
            KM.Print(ns, "the sidebar count now counts " .. (v == "here" and "this character only." or v == "any" and "every character, in red." or "this character, and alts in gold when nothing is ready here."))
        else
            KM.Print(ns, "/cdk badge here|alts|any")
        end
    elseif cmd == "remind" then
        local on = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.settings.chat)
        local s = ns.db.settings
        s.chat, s.toast, s.sound = on, on, on
        KM.Print(ns, "reminders " .. (on and "on." or "off."))
    elseif cmd == "forget" and rest ~= "" then
        local key = ns.FindChar(rest)
        if key and ns.Forget(key) then KM.Print(ns, "forgot " .. key .. ".") else KM.Print(ns, "no character called " .. rest .. ".") end
    elseif cmd == "debug" then
        ns.Debug()
    else
        help()
    end
end
