local _, KM = ...
local ns = KM.Module("Quest")

-- Quest Gold: what the quests of level 48 and up are worth, zone by zone, for the character you're on.
--
-- Data/Quests.lua lists them (CMaNGOS classic-db + ForeverDB.net). A quest is worth:
--   gold      Forever's real reward when King Maker has seen it (db.gold, learned below), else an estimate (~):
--             the typical amount seen for quests of that level, else at least 1g (Forever's Nov 2026 hotfix put gold
--             on most 48+ quests) or Classic's when that's more.
--   + reward  the best choice item (what one sells for: the auction house after its 5% cut, or a vendor, whichever
--             pays more) plus every item it always gives
--   - cost    what the items you hand in would sell for (only those with a price: dropped quest items have none)
--
-- Learning the real gold: the quest giver's offer and turn-in windows (GetRewardMoney), quests in your log
-- (GetQuestLogRewardMoney), what a turn-in actually paid (QUEST_TURNED_IN), and on request the server's quest data
-- for a whole zone (C_QuestLog.RequestLoadQuestByID -> QUEST_DATA_LOAD_RESULT), where the client allows it.

local CUT = 0.95
local FLOOR = 10000          -- 1g: the least an unseen 48+ quest is guessed to pay
local NEAR = 2               -- levels either side counted for the typical amount
local MIN_SAMPLES = 3

local function mods() return KM.mods.Scanner end

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------

-- What one of an item fetches: the auction house after its cut, or a vendor; nil when neither is known.
local function sellsFor(id)
    local sc = mods()
    local pr = sc and sc.db and sc.db.prices[id]
    local ah = pr and (pr.m or pr.p)
    local vendor
    if C_Item and C_Item.GetItemInfo then
        local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, id)
        if ok and name and type(sell) == "number" and sell > 0 then vendor = sell end
    end
    local best = ah and math.floor(ah * CUT)
    if vendor and (not best or vendor > best) then best = vendor end
    return best, ah ~= nil
end
ns.SellsFor = sellsFor

local function info(q)
    local r = ns.QUESTS[q]
    if not r then return nil end
    return { id = q, map = r[1], level = r[2], min = r[3], side = r[4], classic = r[5], choices = r[6], items = r[7],
             prev = r[8], flags = r[9], hands = r[10] or {}, classes = r[11] or 0, title = r[12] or ("Quest " .. q) }
end
ns.QuestInfo = info

-- The typical gold of quests near this level that King Maker has seen paying (median), or nil.
local typicalCache
local function typical(level)
    if not typicalCache then
        typicalCache = {}
        local by = {}
        for q, g in pairs(ns.db.gold) do
            local r = ns.QUESTS[q]
            if r and g > 0 then
                by[r[2]] = by[r[2]] or {}
                table.insert(by[r[2]], g)
            end
        end
        for lvl = 48, 60 do
            local all = {}
            for l = lvl - NEAR, lvl + NEAR do for _, g in ipairs(by[l] or {}) do all[#all + 1] = g end end
            if #all >= MIN_SAMPLES then
                table.sort(all)
                typicalCache[lvl] = all[math.ceil(#all / 2)]
            end
        end
    end
    return typicalCache[math.max(48, math.min(60, level))]
end

-- Gold for a quest: copper, and whether it's an estimate.
function ns.QuestGold(q)
    local seen = ns.db.gold[q]
    if seen then return seen, false end
    local i = info(q)
    if not i then return 0, true end
    local guess = typical(i.level) or FLOOR
    return math.max(guess, i.classic or 0), true
end

-- The items: { best = { item, count, value } or nil, fixed = value, items = { { item, count, value }, ... } }.
function ns.QuestRewards(q)
    local i = info(q)
    local out = { fixed = 0, choices = {}, items = {} }
    if not i then return out end
    for k = 1, #i.choices, 2 do
        local id, n = i.choices[k], i.choices[k + 1] or 1
        local each = sellsFor(id)
        local e = { item = id, count = n, value = each and each * n }
        table.insert(out.choices, e)
        if e.value and (not out.best or e.value > out.best.value) then out.best = e end
    end
    if not out.best and out.choices[1] then out.best = out.choices[1] end
    for k = 1, #i.items, 2 do
        local id, n = i.items[k], i.items[k + 1] or 1
        local each = sellsFor(id)
        table.insert(out.items, { item = id, count = n, value = each and each * n })
        out.fixed = out.fixed + (each and each * n or 0)
    end
    return out
end

-- What the items you hand in would sell for (only priced ones).
function ns.QuestCost(q)
    local i = info(q)
    if not i then return 0 end
    local cost = 0
    for k = 1, #i.hands, 2 do
        local each, priced = sellsFor(i.hands[k])
        if each and priced then cost = cost + each * (i.hands[k + 1] or 1) end
    end
    return cost
end

-- Everything about a quest's value: { gold, guess, best, items (value of the fixed items), cost, worth }.
function ns.QuestValue(q)
    local gold, guess = ns.QuestGold(q)
    local rw = ns.QuestRewards(q)
    local cost = ns.QuestCost(q)
    local best = rw.best and rw.best.value or 0
    return { gold = gold, guess = guess, best = rw.best, items = rw.fixed, rewards = rw, cost = cost,
             worth = gold + best + rw.fixed - cost }
end

---------------------------------------------------------------------------
-- The character you're on
---------------------------------------------------------------------------

local function done(q)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, q)
        if ok then return v and true or false end
    end
    return false
end
ns.QuestDone = done

local function inLog(q)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, v = pcall(C_QuestLog.IsOnQuest, q)
        if ok and v then return true end
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, v = pcall(C_QuestLog.GetLogIndexForQuestID, q)
        if ok and v then return true end
    end
    return false
end

local function side()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

local function classBit()
    local _, _, id = UnitClass("player")
    return id and 2 ^ (id - 1) or 0
end

-- Can this character ever do it (faction, class)?
function ns.ForMe(q)
    local i = info(q)
    if not i then return false end
    local s = side()
    if i.side ~= "" and s and i.side ~= s then return false end
    if i.classes ~= 0 then
        local bit = classBit()
        if bit == 0 or math.floor(i.classes / bit) % 2 == 0 then return false end
    end
    return true
end

-- "done", "log" (in your quest log), "ready", "low" (your level's too low), "locked" (the quest before it isn't done),
-- "nodata" (the server knows nothing about it: not in Forever yet).
function ns.QuestState(q)
    if done(q) then return "done" end
    if ns.db.noData[q] and not inLog(q) then return "nodata" end
    if inLog(q) then return "log" end
    local i = info(q)
    if i.prev ~= 0 and not done(i.prev) then return "locked" end
    if (UnitLevel("player") or 0) < (i.min or 0) then return "low" end
    return "ready"
end

-- Every zone with quests for you: { { map, name, quests = { ids }, total, left, worth (left), gold (left), guesses,
-- lo, hi } }, most gold left first.
local zoneNames = {}
local function zoneName(map)
    if zoneNames[map] == nil then
        local i = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        zoneNames[map] = i and i.name or ("Zone " .. map)
    end
    return zoneNames[map]
end
ns.ZoneName = zoneName

function ns.Zones()
    local by, out = {}, {}
    for q, r in pairs(ns.QUESTS) do
        if ns.ForMe(q) then
            local z = by[r[1]]
            if not z then
                z = { map = r[1], name = zoneName(r[1]), quests = {}, total = 0, left = 0, worth = 0, gold = 0, guesses = 0,
                      missing = 0, lo = r[2], hi = r[2] }
                by[r[1]] = z
                out[#out + 1] = z
            end
            table.insert(z.quests, q)
            local missing = ns.db.noData[q] and not done(q) and not inLog(q)
            if missing then
                z.missing = z.missing + 1 -- listed (greyed), but not counted: the server says it isn't in Forever
            else
                z.total = z.total + 1
                z.lo, z.hi = math.min(z.lo, r[2]), math.max(z.hi, r[2])
            end
            if not done(q) and not missing then
                local v = ns.QuestValue(q)
                z.left = z.left + 1
                z.worth = z.worth + v.worth
                z.gold = z.gold + v.gold
                if v.guess then z.guesses = z.guesses + 1 end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.worth ~= b.worth then return a.worth > b.worth end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- Learning Forever's real gold
---------------------------------------------------------------------------

local function learn(q, copper)
    if not (ns.db and q and ns.QUESTS[q] and type(copper) == "number" and copper >= 0) then return false end
    ns.db.noData[q] = nil -- it's real after all
    if ns.db.gold[q] == copper then return false end
    ns.db.gold[q] = copper
    typicalCache = nil
    if ns.RefreshQuestGold then ns.RefreshQuestGold() end
    return true
end
ns.LearnGold = learn

local function fromLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and GetQuestLogRewardMoney) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local e = C_QuestLog.GetInfo(i)
        local q = e and not e.isHeader and e.questID
        if q and ns.QUESTS[q] then
            local ok, money = pcall(GetQuestLogRewardMoney, q)
            if ok and type(money) == "number" and money > 0 then learn(q, money) end
        end
    end
end

-- Asks the server for every quest in a zone the gold isn't known for; returns how many were asked, or nil when the
-- client can't. Answers arrive as QUEST_DATA_LOAD_RESULT.
local asking, askQueue = {}, {}
function ns.AskZone(map)
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID and GetQuestLogRewardMoney) then return nil end
    local n = 0
    for q, r in pairs(ns.QUESTS) do
        if r[1] == map and ns.db.gold[q] == nil and not asking[q] and ns.ForMe(q) then
            asking[q] = true
            askQueue[#askQueue + 1] = q
            n = n + 1
        end
    end
    local function step()
        for _ = 1, 5 do
            local q = table.remove(askQueue, 1)
            if not q then return end
            pcall(C_QuestLog.RequestLoadQuestByID, q)
        end
        C_Timer.After(0.2, step)
    end
    if n > 0 then step() end
    return n
end
function ns.CanAsk() return C_QuestLog and C_QuestLog.RequestLoadQuestByID and GetQuestLogRewardMoney and true or false end

-- The server's answer. No data at all: the quest isn't in Forever (yet), set aside (db.noData) and left out of the
-- totals. Data that says 0: it really pays nothing (once the client says its reward data is in).
local function answer(q, success)
    if not asking[q] then return end
    asking[q] = nil
    if not success then
        if not ns.db.noData[q] then
            ns.db.noData[q] = true
            if ns.RefreshQuestGold then ns.RefreshQuestGold() end
        end
        return
    end
    local ok, money = pcall(GetQuestLogRewardMoney, q)
    if not (ok and type(money) == "number") then return end
    if money > 0 then
        learn(q, money)
    elseif not HaveQuestRewardData or select(2, pcall(HaveQuestRewardData, q)) then
        learn(q, 0)
    end
end

local function questID()
    if GetQuestID then
        local ok, q = pcall(GetQuestID)
        if ok and q and q > 0 then return q end
    end
end

local f = CreateFrame("Frame")
KM.Register(f, "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_DATA_LOAD_RESULT")
local logPending
f:SetScript("OnEvent", function(_, event, a, b, c)
    if not ns.db then return end
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        local q = questID()
        if q and GetRewardMoney then
            local ok, money = pcall(GetRewardMoney)
            if ok and type(money) == "number" then learn(q, money) end
        end
    elseif event == "QUEST_TURNED_IN" then
        -- questID, xp, money: what it actually paid (0 is a real answer here)
        if type(c) == "number" then learn(a, c) end
        if ns.RefreshQuestGold then ns.RefreshQuestGold() end
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        answer(a, b)
    elseif event == "QUEST_LOG_UPDATE" and not logPending then
        logPending = true
        C_Timer.After(1, function() logPending = nil; pcall(fromLog) end)
    end
end)
