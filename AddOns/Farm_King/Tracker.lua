local _, ns = ...

-- Recording what you see and loot.
--
-- Mobs you see (target, mouse over, nameplates): name, level, elite/rare, type,
-- and where you were when you saw them.
--
-- Kills: every item in a loot window is credited to the corpse it came from
-- (GetLootSourceInfo), so looting several corpses at once still adds up.
-- A corpse counts as one kill the first time you open it (remembered for an
-- hour, through /reload). Skinning, herb gathering, mining, fishing,
-- pickpocketing and gathering nodes are ignored, even on corpses you never
-- looted (someone else's kill you skin, for example).
-- Mobs you kill that have nothing to loot count too when you're solo, so drop
-- rates aren't inflated by only counting corpses with loot. In a group, where
-- someone else may get the loot, only corpses you open count.
--
-- Forever runs the Midnight client, where the combat log is closed to addons:
-- registering COMBAT_LOG_EVENT_UNFILTERED makes the game block the addon at
-- login. So a kill is spotted without it: a mob that had you (or your pet) on
-- its threat list, seen dead as your target or nameplate, untagged by others.

local POSITIONS = 40          -- spots remembered per mob
local SIGHT_GAP = 30          -- seconds between position notes for one mob
local EMPTY_CHECK = 1.5       -- seconds after a kill to ask whether the corpse has loot
local CORPSE_KEEP = 3600      -- seconds a counted corpse is remembered
local GATHER_WINDOW = 3       -- loot this soon after a gathering cast isn't a kill's loot

-- Casts whose loot isn't a kill's: pickpocketing and gathering (by spell ID, and by
-- name for ranks and clients we don't know the IDs of).
local GATHER_IDS = { [921] = true, [8613] = true, [8617] = true, [8618] = true, [10768] = true,
    [2366] = true, [2368] = true, [3570] = true, [11993] = true, [2575] = true, [2576] = true,
    [3564] = true, [10248] = true }
local GATHER_NAMES = { ["Pick Pocket"] = true, ["Skinning"] = true, ["Herb Gathering"] = true, ["Mining"] = true }

local pending = {}            -- corpse GUID -> npcID: killed by you, loot not opened yet
local emptyKills = {}         -- corpse GUID -> true: counted as a kill with nothing to loot
local tapDenied = {}          -- creature GUID -> true: tagged by someone else when you saw it
local engaged = {}            -- creature GUID -> true: you or your pet were on its threat list
local lastSight = {}          -- npcID -> GetTime() of the last position note
local gatherAt = 0

-- Corpses already counted: saved, so a /reload doesn't count one twice.
local function counted() return ns.db.corpses end

function ns.PruneCorpses()
    local now = ns.Now()
    for guid, t in pairs(ns.db.corpses) do
        if now - t > CORPSE_KEEP then ns.db.corpses[guid] = nil end
    end
end

-- "Creature-0-1-2-3-<npcID>-<spawn>" -> npcID (creatures only; not players, pets, objects)
function ns.NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

local function mob(id)
    local m = ns.db.mobs[id]
    if not m then
        m = { k = 0, c = 0, i = {}, z = {}, p = {} }
        ns.db.mobs[id] = m
    end
    return m
end
ns.MobRecord = mob

local function playerPosition()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos:GetXY()
    return map, x, y
end

local function notePosition(m, map, x, y)
    if not map then return end
    m.z[map] = (m.z[map] or 0) + 1
    if not (x and y) or (x == 0 and y == 0) then return end
    local p = string.format("%d:%.3f:%.3f", map, x, y)
    if #m.p >= POSITIONS then table.remove(m.p, 1) end
    table.insert(m.p, p)
end

---------------------------------------------------------------------------
-- Seeing mobs
---------------------------------------------------------------------------

local CLASS = { worldboss = "boss", rareelite = "rare elite", elite = "elite", rare = "rare" }

local function see(unit)
    if not (UnitExists and UnitExists(unit)) or UnitIsPlayer(unit) then return end
    if UnitCanAttack and not UnitCanAttack("player", unit) then return end
    local guid = UnitGUID(unit)
    local id = ns.NpcID(guid)
    if not id then return end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then tapDenied[guid] = true end
    local m = mob(id)
    m.name = UnitName(unit) or m.name
    local lvl = UnitLevel(unit)
    if lvl and lvl > 0 then
        m.lmin = math.min(m.lmin or lvl, lvl)
        m.lmax = math.max(m.lmax or lvl, lvl)
    elseif lvl == -1 then
        m.skull = true
    end
    local cls = UnitClassification and UnitClassification(unit)
    if cls then m.rank = CLASS[cls] end
    m.type = UnitCreatureType and UnitCreatureType(unit) or m.type
    m.t = ns.Now()
    local now = GetTime()
    if not lastSight[id] or now - lastSight[id] >= SIGHT_GAP then
        lastSight[id] = now
        notePosition(m, playerPosition())
    end
end
ns.See = see

---------------------------------------------------------------------------
-- Looting
---------------------------------------------------------------------------

local RECENT = 25             -- mobs kept under Recent kills
ns.RECENT = RECENT

-- Recent kills: npcIDs, the latest first, each once.
local function noteRecent(id)
    local r = ns.db.recent
    for i = #r, 1, -1 do if r[i] == id then table.remove(r, i) end end
    table.insert(r, 1, id)
    while #r > RECENT do table.remove(r) end
end

local function countKill(guid, id)
    if counted()[guid] then return false end
    counted()[guid] = ns.Now()
    pending[guid] = nil
    engaged[guid] = nil
    mob(id).k = mob(id).k + 1
    noteRecent(id)
    if ns.SessionKill then ns.SessionKill(id) end
    return true
end

-- Coin text in a loot slot ("5 Silver, 3 Copper") when the source doesn't say how much.
local function coinFromText(text)
    if not text then return 0 end
    local g = tonumber(text:match("(%d+) [Gg]old")) or 0
    local s = tonumber(text:match("(%d+) [Ss]ilver")) or 0
    local c = tonumber(text:match("(%d+) [Cc]opper")) or 0
    return g * 10000 + s * 100 + c
end

-- Pairs of (GUID, quantity) a loot slot came from.
local function sources(slot)
    if GetLootSourceInfo then
        local r = { GetLootSourceInfo(slot) }
        if #r >= 2 then return r end
    end
    -- Older clients: the dead target you're looting.
    if UnitExists("target") and UnitIsDead("target") then return { UnitGUID("target"), 0 } end
    return {}
end

function ns.OnLootOpened()
    if IsFishingLoot and IsFishingLoot() then return end
    if GetTime() - gatherAt < GATHER_WINDOW then return end
    local fresh = {}   -- corpses in this window not counted before it
    local dropped = {} -- guid -> itemID -> true, so one corpse's split stacks count as one drop
    local touched = false
    for slot = 1, (GetNumLootItems() or 0) do
        local src = sources(slot)
        local kind = GetLootSlotType and GetLootSlotType(slot) or nil
        local link = GetLootSlotLink(slot)
        local item = link and tonumber(link:match("item:(%d+)"))
        local _, _, slotQty = GetLootSlotInfo(slot)
        local coin = (kind == 2 or (not item and not kind))
        for j = 1, #src, 2 do
            local guid, qty = src[j], src[j + 1]
            local id = ns.NpcID(guid)
            -- New corpses, and ones counted as empty that turn out to have loot after all.
            if id and (not counted()[guid] or emptyKills[guid]) then
                fresh[guid] = id
                local m = mob(id)
                if coin then
                    local copper = (qty and qty > 0) and qty or coinFromText(select(2, GetLootSlotInfo(slot)))
                    m.c = m.c + copper
                    if ns.SessionLoot then ns.SessionLoot(id, copper) end
                    touched = true
                elseif item then
                    local q = (qty and qty > 0) and qty or slotQty or 1
                    local e = m.i[item]
                    if not e then e = { 0, 0 }; m.i[item] = e end
                    dropped[guid] = dropped[guid] or {}
                    if not dropped[guid][item] then e[1] = e[1] + 1; dropped[guid][item] = true end
                    e[2] = e[2] + q
                    if ns.SessionLoot then ns.SessionLoot(id, 0, item, q) end
                    touched = true
                end
            end
        end
    end
    local map, x, y = playerPosition()
    for guid, id in pairs(fresh) do
        if emptyKills[guid] then
            emptyKills[guid] = nil -- already counted as a kill; its loot is added above
        elseif countKill(guid, id) then
            notePosition(mob(id), map, x, y)
        end
        touched = true
    end
    if touched and ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Kills with nothing to loot
---------------------------------------------------------------------------

local function checkEmpty(guid, id)
    if counted()[guid] or not pending[guid] then return end
    if IsInGroup and IsInGroup() then return end -- a groupmate may have the loot
    if tapDenied[guid] then return end           -- someone else's kill: not your loot to see
    if not CanLootUnit then return end            -- can't tell; only looted corpses count
    local ok, hasLoot = pcall(CanLootUnit, guid)
    if ok and hasLoot == false then
        countKill(guid, id)
        emptyKills[guid] = true
        local m = mob(id)
        notePosition(m, playerPosition())
        if ns.Refresh then ns.Refresh() end
    end
    -- With loot, it counts when you open it.
end

-- A value the client may hide from addons (Midnight's "secret" values) is treated as unknown.
local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function onThreatList(unit)
    if not (UnitExists and UnitExists(unit)) then return end
    local guid = plain(UnitGUID(unit))
    if not ns.NpcID(guid) or (UnitIsDead and UnitIsDead(unit)) then return end
    local mine = UnitThreatSituation and (plain(UnitThreatSituation("player", unit))
        or (UnitExists("pet") and plain(UnitThreatSituation("pet", unit))))
    if mine then engaged[guid] = true end
end

-- A mob you fought, now dead: a kill of yours unless someone else tagged it.
function ns.OnUnitDead(unit)
    if not (UnitExists and UnitExists(unit)) or not plain(UnitIsDead(unit)) then return end
    local guid = plain(UnitGUID(unit))
    local id = ns.NpcID(guid)
    if not id or not engaged[guid] then return end
    engaged[guid] = nil
    if counted()[guid] or pending[guid] then return end
    if (UnitIsTapDenied and plain(UnitIsTapDenied(unit))) or tapDenied[guid] then return end
    pending[guid] = id
    local m = mob(id)
    m.name = m.name or UnitName(unit)
    C_Timer.After(EMPTY_CHECK, function() checkEmpty(guid, id) end)
end

-- Forgets the fights going on now (not ones started after).
local function forgetEngaged()
    local old = {}
    for guid in pairs(engaged) do old[guid] = true end
    return function() for guid in pairs(old) do engaged[guid] = nil end end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
-- Never COMBAT_LOG_EVENT_UNFILTERED: on Forever that gets the addon blocked.
for _, e in ipairs({ "LOOT_OPENED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_HEALTH", "UNIT_FLAGS", "PLAYER_REGEN_ENABLED",
    "UNIT_SPELLCAST_SUCCEEDED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if not ns.db then return end
    if event == "LOOT_OPENED" then
        pcall(ns.OnLootOpened)
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        pcall(onThreatList, arg1)
    elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "NAME_PLATE_UNIT_REMOVED" then
        if arg1 == "target" or (arg1 and arg1:find("^nameplate")) then pcall(ns.OnUnitDead, arg1) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Out of combat: give mobs that died out of sight a moment to be seen, then forget the fight.
        C_Timer.After(EMPTY_CHECK * 2, forgetEngaged())
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(see, "target")
        pcall(ns.OnUnitDead, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        pcall(see, "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        pcall(see, arg1)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        local name = arg3 and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(arg3)) or (GetSpellInfo and GetSpellInfo(arg3)))
        if GATHER_IDS[arg3] or (name and GATHER_NAMES[name]) then gatherAt = GetTime() end
    end
end)
