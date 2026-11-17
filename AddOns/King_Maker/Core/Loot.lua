local _, KM = ...

-- Loot: reads every loot window once and says what it was (mob, skinning, pickpocket, mining, herbs, fishing, a chest
-- or object, a container, disenchanting), so a module can credit what you took without its own loot reader.
--
--   KM.OnLoot(owner, fn)   fn(event, window, slot): "open" (window), "clear" (window, slot), "close" (window),
--                          and "cast" (nil, cast) when you cast a gathering/fishing/skinning/pickpocket spell;
--                          "won" (window or nil, slot) when a rolled or master-looted item reached your bags later
--                          (slot = { item, qty, kind, won = "bags" | "chat", src = { { guid, gk, id, qty, kind } } })
--   KM.LootWindow()        the open window or nil
--   KM.GuidInfo(guid)      "Creature" | "Vehicle" | "GameObject" | "Item" | "Player" | ..., and the npc/object id
--   KM.RecentCast(sec)     the last such cast within sec seconds: { kind, name, spell, target, at }
--
-- window = { kind, farming, fromItem, at, cast, slots = { [i] = slot } }
-- slot   = { i, item, qty, copper, coin, locked, quest, quality, ml, kind, src = { { guid, gk, id, qty, kind }, ... }, cleared }
--
-- The window is read at LOOT_READY (before fast auto-loot takes anything) or LOOT_OPENED, whichever comes first; a
-- slot counts as taken on LOOT_SLOT_CLEARED (locked slots, group rolls, never do: see "won" below). If the client has no
-- LOOT_SLOT_CLEARED, every unlocked slot counts at open; if a window closes with no clears at all, the slots whose
-- item went up in your bags count. Every value read here goes through KM.Plain (Forever hides some in instances).
-- Never the combat log: on Forever that gets the addon blocked.

local plain = KM.Plain

-- Spells by name first (Forever-specific ranks keep working), the known IDs as a fallback.
local CAST_KIND = { ["Skinning"] = "skin", ["Pick Pocket"] = "pick", ["Mining"] = "mine", ["Herb Gathering"] = "herb",
    ["Herbalism"] = "herb", ["Disenchant"] = "de", ["Opening"] = "open", ["Fishing"] = "fish" }
local CAST_IDS = { [8613] = "skin", [8617] = "skin", [8618] = "skin", [10768] = "skin", [921] = "pick",
    [2575] = "mine", [2576] = "mine", [3564] = "mine", [10248] = "mine",
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb", [13262] = "de", [7620] = "fish" }
KM.CAST_KIND, KM.CAST_IDS = CAST_KIND, CAST_IDS

-- The kinds that count as farming (auto-start, activity, auto-resume).
KM.FARMING_KINDS = { mob = true, skin = true, pick = true, mine = true, herb = true, fish = true }

local subs = {}       -- owner -> fn
local current         -- the open window
local cast            -- the last farming cast
local sentTarget      -- { target, at } from UNIT_SPELLCAST_SENT

function KM.OnLoot(owner, fn) subs[owner] = fn end
function KM.LootWindow() return current end

local function fire(event, window, slot)
    for _, fn in pairs(subs) do KM.Safe(fn, event, window, slot) end
end

-- "Creature-0-1-2-3-<npcID>-<spawn>" -> "Creature", npcID. Item GUIDs carry no item id we can use.
function KM.GuidInfo(guid)
    guid = plain(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then return kind, tonumber(id) end
    return kind
end

function KM.RecentCast(sec)
    if cast and GetTime() - cast.at <= (sec or 3) then return cast end
end

local function spellKind(spellID)
    spellID = plain(spellID)
    if not spellID then return nil end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
    name = plain(name)
    return (name and CAST_KIND[name]) or CAST_IDS[spellID], name
end

local function onCast(unit, spellID)
    if plain(unit) ~= "player" then return end
    local kind, name = spellKind(spellID)
    if not kind then return end
    cast = { kind = kind, name = name, spell = spellID, at = GetTime(),
        target = sentTarget and GetTime() - sentTarget.at < 15 and sentTarget.target or nil }
    sentTarget = nil
    fire("cast", nil, cast)
end

local function onSent(unit, target, _, spellID)
    if plain(unit) ~= "player" then return end
    if not spellKind(spellID) then return end
    target = plain(target)
    if type(target) ~= "string" or target == "" then target = nil end
    sentTarget = target and { target = target, at = GetTime() } or nil
end

-- Coin text in a loot slot ("5 Silver\n3 Copper") when the source doesn't say how much.
local function coinFromText(text)
    text = plain(text)
    if type(text) ~= "string" then return 0 end
    local g = tonumber(text:match("(%d+) [Gg]old")) or 0
    local s = tonumber(text:match("(%d+) [Ss]ilver")) or 0
    local c = tonumber(text:match("(%d+) [Cc]opper")) or 0
    return g * 10000 + s * 100 + c
end
KM.CoinFromText = coinFromText

local function itemCount(id)
    if C_Item and C_Item.GetItemCount then local ok, n = pcall(C_Item.GetItemCount, id); if ok then return plain(n) end end
    if GetItemCount then local ok, n = pcall(GetItemCount, id); if ok then return plain(n) end end
end

-- What one slot source is, given the window's cast and kind.
local function sourceKind(window, gk)
    if window.kind == "fish" then return "fish" end
    local c = window.cast and window.cast.kind
    if gk == "Creature" or gk == "Vehicle" then
        if c == "skin" or c == "pick" then return c end
        return "mob"
    elseif gk == "GameObject" then
        if c == "mine" or c == "herb" then return c end
        return "chest"
    elseif gk == "Item" then
        if c == "de" then return "de" end
        return "box"
    end
    return window.kind
end

-- The window's own kind: fishing, then a recent cast, then containers, objects and creatures.
local function classify(window)
    local has = {}
    for _, s in ipairs(window.slots) do for _, src in ipairs(s.src) do if src.gk then has[src.gk] = true end end end
    local c = window.cast and window.cast.kind
    local creature = has.Creature or has.Vehicle
    if IsFishingLoot and plain(IsFishingLoot()) then return "fish" end
    if c == "de" and (has.Item or window.fromItem) then return "de" end
    if (c == "pick" or c == "skin") and creature then return c end
    if (c == "mine" or c == "herb") and (has.GameObject or not (creature or has.Item)) then return c end
    if window.fromItem or has.Item then return "box" end
    if has.GameObject then return "chest" end
    if creature then return "mob" end
    return "unknown"
end

local function readSlot(i)
    local link = plain(GetLootSlotLink and GetLootSlotLink(i))
    local item = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    local _, name, qty, _, quality, locked, quest, _, _, isCoin = GetLootSlotInfo(i)
    local stype = GetLootSlotType and plain(GetLootSlotType(i))
    local s = { i = i, item = item, qty = plain(qty) or 1, locked = plain(locked) and true or false,
        quest = plain(quest) and true or false, quality = tonumber(plain(quality)), src = {} }
    s.coin = plain(isCoin) == true or stype == 2 or (not item and not stype)
    if GetLootSourceInfo then
        local r = { GetLootSourceInfo(i) }
        for j = 1, #r, 2 do
            local guid, n = plain(r[j]), plain(r[j + 1])
            local gk, id = KM.GuidInfo(guid)
            s.src[#s.src + 1] = { guid = guid, gk = gk, id = id, qty = tonumber(n) or 0 }
        end
    end
    if s.coin then
        local total = 0
        for _, src in ipairs(s.src) do total = total + src.qty end
        if total <= 0 then
            total = coinFromText(name)
            if s.src[1] then s.src[1].qty = total end
        end
        s.copper = total
    end
    return s
end

local function kinds(w)
    w.kind = classify(w)
    w.farming = KM.FARMING_KINDS[w.kind] or false
    for _, s in ipairs(w.slots) do
        s.kind = w.kind
        for _, src in ipairs(s.src) do src.kind = sourceKind(w, src.gk) end
        if s.src[1] then s.kind = s.src[1].kind end
    end
end

---------------------------------------------------------------------------
-- Items that reach you later: group loot rolls and master loot
---------------------------------------------------------------------------
-- A slot at or above the group's loot threshold is locked in your window (a Need/Greed roll, or the master looter's
-- to hand out) and never clears for you: the winner gets it straight into their bags. So each one you see, and each
-- roll that starts (START_LOOT_ROLL, even for a corpse you never opened), is an expectation; if that item's bag count
-- goes up within EXPECT_FOR seconds it's yours and subscribers hear "won" once, credited to the corpse it came from
-- (or 0 when no window showed it). The bag count is the source of truth (chat can be secret in instances); your own
-- "You receive loot" line is only a fallback. What other players win never raises your bags, so it never counts.
-- A slot the master looter (you) clears above the threshold may have gone to someone else: it waits for the bags too.

local EXPECT_FOR = 300
local RECEIPT_FOR = 20
local ENDED_FOR = 90     -- a roll lasts up to a minute after you've chosen
local expects = {}    -- oldest first: { item, qty, kind, src, before, at, roll, guid, window }
local receipts = {}   -- { item, n, at }: items just credited, for a "You receive loot" line that comes after

local function plainCount(id) return tonumber(itemCount(id)) end

-- The group's loot method is master loot (C_PartyInfo first, the old global as a fallback).
local function masterLoot()
    if not (IsInGroup and plain(IsInGroup())) then return false end
    local get = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
    if not get then return false end
    local ok, m = pcall(get)
    m = ok and plain(m) or nil
    if m == "master" then return true end
    if type(m) == "number" then
        local enum = Enum and Enum.LootMethod
        return m == ((enum and (enum.Masterlooter or enum.MasterLooter)) or 2)
    end
    return false
end

local function threshold()
    if not GetLootThreshold then return 2 end
    local ok, t = pcall(GetLootThreshold)
    return ok and tonumber(plain(t)) or 2
end

local function bump(item, n, except)
    for _, e in ipairs(expects) do
        if e.item == item and e ~= except then e.before = e.before + n end
    end
end

local function receipt(item, n)
    local now = GetTime()
    for i = #receipts, 1, -1 do if now - receipts[i].at > RECEIPT_FOR then table.remove(receipts, i) end end
    receipts[#receipts + 1] = { item = item, n = n or 1, at = now }
end

-- A locked slot, a master-looted slot or a roll: one expectation per corpse and item, and a roll and the locked slot
-- it's for are the same expectation (whichever came first).
local function expect(item, qty, before, w, s, roll)
    if not item then return end
    local src = s and s.src[1]
    local guid = src and src.guid
    for _, e in ipairs(expects) do
        if e.item == item then
            if guid and e.guid == guid then
                return e
            elseif roll and not e.roll and e.guid then
                e.roll = roll
                return e
            elseif guid and not e.guid and e.roll then
                e.guid, e.src, e.kind, e.window = guid, { src }, src.kind or s.kind, w
                return e
            end
        end
    end
    local e = { item = item, qty = qty or 1, before = before or plainCount(item) or 0, at = GetTime(), roll = roll,
        guid = guid, window = w, kind = (src and src.kind) or (s and s.kind) or "mob", src = src and { src } or {} }
    expects[#expects + 1] = e
    return e
end

local function won(e, n, via)
    e.done = true
    for i, x in ipairs(expects) do if x == e then table.remove(expects, i); break end end
    local src = e.src[1]
    local slot = { item = e.item, qty = n, kind = e.kind, won = via, roll = e.roll,
        src = { { guid = src and src.guid, gk = src and src.gk, id = (src and src.id) or 0, qty = n, kind = e.kind } } }
    fire("won", e.window, slot)
end

-- Bag counts against the expectations, oldest first. Not while a loot window is open (its own slots are rising then);
-- the close checks again.
local function check()
    if #expects == 0 then return end
    local now = GetTime()
    for i = #expects, 1, -1 do
        local e = expects[i]
        if now - e.at > EXPECT_FOR or (e.ended and now - e.ended > ENDED_FOR) then table.remove(expects, i) end
    end
    for i = #receipts, 1, -1 do if now - receipts[i].at > RECEIPT_FOR then table.remove(receipts, i) end end
    if current then return end
    local i = 1
    while expects[i] do
        local e = expects[i]
        local n = plainCount(e.item)
        if n and n < e.before then
            e.before = n                                   -- sold, used or banked meanwhile
            i = i + 1
        elseif n and n > e.before then
            local got = math.min(e.qty, n - e.before)
            bump(e.item, got, e)
            receipt(e.item, got)
            won(e, got, "bags")                             -- removes e: the next one is at i now
        else
            i = i + 1
        end
    end
end

local function checkSoon()
    if #expects == 0 then return end
    C_Timer.After(0.5, function() pcall(check) end)
    C_Timer.After(2, function() pcall(check) end)
end

-- A roll that's over (CANCEL_LOOT_ROLL, or every roll of its loot done): the winner has it within moments, so its
-- expectation only waits ENDED_FOR seconds more for the bags.
local function rollOver(rollID, handle)
    rollID, handle = plain(rollID), plain(handle)
    for _, e in ipairs(expects) do
        if (rollID and e.roll == rollID) or (handle and e.handle == handle) then e.ended = e.ended or GetTime() end
    end
    checkSoon()
end

local function onRoll(rollID, handle)
    rollID = plain(rollID)
    if not rollID or not GetLootRollItemLink then return end
    local link = plain(GetLootRollItemLink(rollID))
    local item = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if not item then return end
    local qty = 1
    if GetLootRollItemInfo then
        local ok, _, _, count = pcall(GetLootRollItemInfo, rollID)
        if ok then qty = tonumber(plain(count)) or 1 end
    end
    local e = expect(item, qty, nil, nil, nil, rollID)
    if e then e.handle = plain(handle) end
end

-- "You receive loot: %s." and friends as patterns, multiples first; built once from the client's own strings.
local selfPatterns
local function patterns()
    if selfPatterns then return selfPatterns end
    selfPatterns = {}
    for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
        local fmt = _G[key]
        if type(fmt) == "string" and fmt ~= "" then
            local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
            selfPatterns[#selfPatterns + 1] = "^" .. p .. "$"
        end
    end
    return selfPatterns
end

-- Your own loot line, as a fallback for a bag update that hasn't come: it credits an expectation only, never ordinary
-- loot (that came through the window), and never someone else's line.
local function onChat(text)
    text = plain(text)
    if type(text) ~= "string" or current or #expects == 0 then return end
    local link, n
    for _, p in ipairs(patterns()) do
        link, n = text:match(p)
        if link then break end
    end
    local item = link and tonumber(link:match("item:(%d+)"))
    if not item then return end
    n = tonumber(n) or 1
    for i, r in ipairs(receipts) do
        if r.item == item and GetTime() - r.at <= RECEIPT_FOR then
            r.n = r.n - n                                   -- the bags (or the window) already counted it
            if r.n <= 0 then table.remove(receipts, i) end
            return
        end
    end
    for _, e in ipairs(expects) do
        if e.item == item then
            local got = math.min(e.qty, n)
            bump(item, got, e)
            won(e, got, "chat")
            return
        end
    end
end

-- Tests: what's waiting.
function KM.LootExpects() return expects end

local function open(fromItem)
    local w = { at = GetTime(), fromItem = plain(fromItem) and true or false, slots = {}, cleared = 0, counts = {}, got = {} }
    w.cast = KM.RecentCast(3)
    for i = 1, (plain(GetNumLootItems()) or 0) do
        local ok, s = pcall(readSlot, i)
        if ok and s then w.slots[i] = s end
    end
    for _, s in ipairs(w.slots) do
        if s.item and not w.counts[s.item] then w.counts[s.item] = itemCount(s.item) end
    end
    kinds(w)
    w.master = masterLoot()
    local th = w.master and threshold()
    for _, s in ipairs(w.slots) do
        if s.item and not s.coin then
            if s.locked then
                pcall(expect, s.item, s.qty, w.counts[s.item], w, s)
            elseif th and (s.quality or 0) >= th then
                s.ml = true                                  -- yours to hand out: it counts when it reaches your bags
            end
        end
    end
    current = w
    return w
end

-- Subscribers hear "open" once per window: at LOOT_OPENED (which may say it's a container), or before the first
-- clear or the close if LOOT_OPENED never comes.
local function announce(w)
    if w and not w.announced then
        w.announced = true
        fire("open", w)
    end
end

local function clear(slotIndex)
    local w = current
    local s = w and w.slots[plain(slotIndex) or 0]
    if not s or s.cleared or s.locked then return end
    if s.item and not s.coin then receipt(s.item, s.qty or 1) end
    announce(w)
    s.cleared = true
    w.cleared = w.cleared + 1
    if s.ml then
        -- master loot handed out: maybe to you, maybe to someone else; the bags will say
        expect(s.item, s.qty, (w.counts[s.item] or plainCount(s.item) or 0) + (w.got[s.item] or 0), w, s)
        return
    end
    if s.item and not s.coin then
        w.got[s.item] = (w.got[s.item] or 0) + (s.qty or 1)
        bump(s.item, s.qty or 1)
    end
    fire("clear", w, s)
end

local noClearEvent = C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid("LOOT_SLOT_CLEARED")

local function close()
    local w = current
    if not w then return end
    announce(w)
    current = nil
    w.closed = GetTime()
    if w.cleared == 0 and next(w.counts) then
        -- No clears seen (a client without the event, or an addon that raced us): count what went up in your bags.
        C_Timer.After(0.5, function()
            local rose = {}
            for id, before in pairs(w.counts) do
                local now = itemCount(id)
                if before and now and now > before then rose[id] = now - before end
            end
            if next(rose) then
                for _, s in ipairs(w.slots) do
                    if s.item and not s.locked and not s.cleared and (rose[s.item] or 0) > 0 then
                        rose[s.item] = rose[s.item] - s.qty
                        s.cleared = true
                        w.cleared = w.cleared + 1
                        fire("clear", w, s)
                    end
                end
            end
            fire("close", w)
            checkSoon()
        end)
        return
    end
    fire("close", w)
    checkSoon()
end

local f = CreateFrame("Frame")
KM.Register(f, "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "START_LOOT_ROLL", "CANCEL_LOOT_ROLL",
    "LOOT_ITEM_ROLL_WON", "LOOT_ROLLS_COMPLETE", "BAG_UPDATE_DELAYED", "CHAT_MSG_LOOT")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
        if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, e, "player") else pcall(f.RegisterEvent, f, e) end
    end
end
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        if current and event == "LOOT_OPENED" and current.via == "LOOT_READY" and not current.paired then
            -- the second of the pair: LOOT_OPENED's isFromItem may tell us it's a container
            current.paired = true
            if plain(a2) and not current.fromItem and not current.announced then
                current.fromItem = true
                kinds(current)
            end
            announce(current)
            return
        end
        if current then pcall(close) end   -- a new window without LOOT_CLOSED for the last one
        local ok, w = pcall(open, event == "LOOT_OPENED" and a2 or nil)
        if ok and w then
            w.via = event
            if event == "LOOT_OPENED" then announce(w) end
        end
        if ok and w and noClearEvent then
            for _, s in ipairs(w.slots) do pcall(clear, s.i) end
        end
    elseif event == "LOOT_SLOT_CLEARED" then
        pcall(clear, a1)
    elseif event == "LOOT_CLOSED" then
        pcall(close)
    elseif event == "START_LOOT_ROLL" then
        pcall(onRoll, a1, a3)
    elseif event == "CANCEL_LOOT_ROLL" then
        pcall(rollOver, a1, nil)
    elseif event == "LOOT_ROLLS_COMPLETE" then
        pcall(rollOver, nil, a1)
    elseif event == "LOOT_ITEM_ROLL_WON" then
        checkSoon()
    elseif event == "BAG_UPDATE_DELAYED" then
        if #expects > 0 then pcall(check) end
    elseif event == "CHAT_MSG_LOOT" then
        pcall(onChat, a1)
    elseif event == "UNIT_SPELLCAST_SENT" then
        pcall(onSent, a1, a2, a3, a4)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        pcall(onCast, a1, a3)
    end
end)
