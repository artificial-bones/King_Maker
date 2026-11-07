# Runs Farm King (with Scanner King, and a stand-in QuestieDB) against a stand-in for the game:
#   python3 tests/run.py . [path/to/Scanner_King]
import sys
from lupa import lua51
root = sys.argv[1]
sk_root = sys.argv[2] if len(sys.argv) > 2 else f"{root}/../scanner_king"

def toc_files(path, name):
    return [l.strip().replace("\\", "/") for l in open(f"{path}/{name}.toc") if l.strip() and not l.startswith("#")]

def fresh(questie):
    L = lua51.LuaRuntime()
    L.execute(open(f"{root}/tests/mock.lua").read())
    L.execute("""
C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }
function hooksecurefunc(t, k, fn) local old = t[k]; t[k] = function(...) local r = { old(...) }; fn(...); return unpack(r) end end
function strsplit(sep, s) local t = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do t[#t+1] = part end return unpack(t) end
-- items: name, quality, sell price, class, bind (1 = on pickup)
ITEMS = {
  [2589] = { "Linen Cloth", 1, 13, 7 }, [2318] = { "Light Leather", 1, 15, 7 }, [4865] = { "Ruined Pelt", 0, 5, 15 },
  [6000] = { "Green Sword", 2, 500, 2 }, [7000] = { "Soulbound Ring", 3, 900, 4, 1 }, [5000] = { "Quest Fang", 1, 0, 12 },
  [8000] = { "Rare Gem", 3, 100, 7 },
}
C_Item.GetItemInfo = function(id) local i = ITEMS[id]; if i then return i[1], "|Hitem:" .. id .. "|h", i[2], 10, 1, "", "", 20, "", 600 + id, i[3], i[4], 0, i[5] or 0 end end
C_Item.GetItemInfoInstant = function(id) local i = ITEMS[id]; if i then return id, "", "", "", 600 + id, i[4], 0 end end
-- the player and the world
GUIDS = { player = "Player-1-AAA", pet = nil }
UNITS = {}
function UnitGUID(u) return GUIDS[u] or (UNITS[u] and UNITS[u].guid) end
function UnitExists(u) return UNITS[u] ~= nil end
function UnitIsPlayer(u) return false end
function UnitCanAttack() return true end
function UnitName(u) if u == "player" then return "Jay" end return UNITS[u] and UNITS[u].name end
function UnitLevel(u) if u == "player" then return 20 end return UNITS[u] and UNITS[u].level end
function UnitClassification(u) return UNITS[u] and UNITS[u].class or "normal" end
function UnitCreatureType(u) return "Beast" end
function UnitIsDead(u) return UNITS[u] and UNITS[u].dead end
function UnitFactionGroup() return "Alliance" end
GROUP = false
function IsInGroup() return GROUP end
LOOTABLE = {}
function CanLootUnit(guid) return LOOTABLE[guid] or false end
-- Forever (Midnight client): the combat log is closed to addons. Registering it gets the addon blocked.
FORBIDDEN = {}
UNKNOWN_EVENTS.COMBAT_LOG_EVENT_UNFILTERED = true
function CombatLogGetCurrentEventInfo() FORBIDDEN[#FORBIDDEN+1] = "CombatLogGetCurrentEventInfo" end
THREAT = {}
function UnitThreatSituation(who, u) local g = UnitGUID(u); return g and THREAT[who .. g] end
-- loot window: { { link or nil (coin), qty, { guid, qty, guid, qty } } }
WINDOW = {}
function GetNumLootItems() return #WINDOW end
function GetLootSlotLink(i) return WINDOW[i][1] end
function GetLootSlotType(i) return WINDOW[i][1] and 1 or 2 end
function GetLootSlotInfo(i) return nil, WINDOW[i][1] and "x" or "5 Silver", WINDOW[i][2] end
function GetLootSourceInfo(i) return unpack(WINDOW[i][3]) end
C_Map.GetBestMapForUnit = function() return 1429 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.45, 0.62 end } end
C_Map.GetMapInfo = function(id) return { name = ({ [1429] = "Elwynn Forest", [1436] = "Westfall" })[id] or ("Map " .. id) } end
function G(npc, n) return "Creature-0-1-2-3-" .. npc .. "-" .. n end
-- You fight a mob (it has you on its threat list), then it dies on its nameplate.
function KILL(guid, name)
  UNITS.nameplate1 = { guid = guid, name = name, level = 2 }
  THREAT["player" .. guid] = 1; FIRE("UNIT_THREAT_LIST_UPDATE", "nameplate1"); THREAT["player" .. guid] = nil
  UNITS.nameplate1.dead = true; FIRE("UNIT_HEALTH", "nameplate1"); FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate1")
  UNITS.nameplate1 = nil
end
function LOOT(window) WINDOW = window FIRE("LOOT_OPENED") end
""")
    if questie:
        L.execute("""
-- A small QuestieDB: npc -> name, minLevel, maxLevel, rank, zoneID (area), friendlyToFaction, npcFlags, spawns
QNPC = {
  [299] = { "Young Wolf", 1, 2, 0, 12, nil, 0, { [12] = { { 40.5, 60.1 }, { 41.0, 61.2 } } } },
  [113] = { "Stonetusk Boar", 5, 6, 0, 12, nil, 0, { [12] = { { 50, 50 } } } },
  [500] = { "Riverpaw Gnoll", 10, 11, 1, 40, nil, 0, { [40] = { { 30, 30 } } } },
  [600] = { "Friendly Guard", 20, 20, 0, 12, "AH", 0, nil },
  [700] = { "Vendor Bob", 10, 10, 0, 12, nil, 128, nil },
  [1] = { "Waypoint (Only GM can see it)", 1, 1, 0, 0, nil, 0, nil },
}
QITEM = { [2318] = { 299, 113 }, [8000] = { 500 }, [2589] = { 500 } }
local function getter(field) return function(id) local n = QNPC[id]; if not n then return nil end; local v = n[field]; if v == nil and field ~= 6 and field ~= 8 then return 0 end; return v end end
NpcDB = { Exists = function(id) return QNPC[id] ~= nil end,
  GetAllIds = function() local t = {} for id in pairs(QNPC) do t[#t+1] = id end table.sort(t) return t end,
  name = getter(1), minLevel = getter(2), maxLevel = getter(3), rank = getter(4), zoneID = getter(5),
  friendlyToFaction = getter(6), npcFlags = getter(7), spawns = getter(8), subName = function() return nil end }
ItemDB = { GetAllIds = function() local t = {} for id in pairs(QITEM) do t[#t+1] = id end table.sort(t) return t end,
  npcDrops = function(id) return QITEM[id] end,
  name = function(id) return ({ [2318] = "Light Leather", [8000] = "Rare Gem", [2589] = "Linen Cloth" })[id] end }
LibQuestieDB = { Support = { Get = function(name) return { private = {
  areaIdToUiMapId = "return { [12] = 1429, [40] = 1436 }", areaIdToUiMapIdOverride = "return {}" } } end } }
""")
    skns = L.table()
    for fn in toc_files(sk_root, "Scanner_King"):
        L.execute(open(f"{sk_root}/{fn}").read(), "Scanner_King", skns)
    ns = L.table()
    for fn in toc_files(root, "Farm_King"):
        L.execute(open(f"{root}/{fn}").read(), "Farm_King", ns)
    L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("ADDON_LOADED", "Farm_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
    return L, ns

def mobs(L): return L.eval("FarmKingDB.mobs")
def last(L): return L.eval("OUTPUT[#OUTPUT]")

# ---------------------------------------------------------------- without QuestieDB
L, ns = fresh(False)
assert not ns.QuestieAvailable()
# nothing touches the combat log, which gets an addon blocked on Forever
assert not any(f.events["COMBAT_LOG_EVENT_UNFILTERED"] for f in L.eval("FRAMES").values())
# seeing a mob
L.execute('UNITS.target = { guid = G(299, 1), name = "Young Wolf", level = 2 }; FIRE("PLAYER_TARGET_CHANGED")')
m = mobs(L)[299]; assert m.name == "Young Wolf" and m.lmin == 2 and m.k == 0 and m.z[1429] == 1 and m.p[1] == "1429:0.450:0.620"
# kill and loot it: a pelt, two leather, 5 silver
L.execute('KILL(G(299, 1), "Young Wolf"); LOOTABLE[G(299, 1)] = true; RUN_TIMERS()')
assert mobs(L)[299].k == 0  # it has loot: counts when opened
L.execute('LOOT({ { "|Hitem:4865:0|h", 1, { G(299, 1), 1 } }, { "|Hitem:2318:0|h", 2, { G(299, 1), 2 } }, { nil, 0, { G(299, 1), 500 } } })')
m = mobs(L)[299]; assert m.k == 1 and m.c == 500 and m.i[4865][1] == 1 and m.i[2318][2] == 2
# opening it again (or skinning it) changes nothing
L.execute('LOOT({ { "|Hitem:2318:0|h", 3, { G(299, 1), 3 } } })'); assert mobs(L)[299].k == 1 and mobs(L)[299].i[2318][2] == 2
# looting two corpses in one window: each item goes to its own corpse
L.execute('LOOT({ { "|Hitem:2318:0|h", 3, { G(299, 2), 1, G(299, 3), 2 } }, { nil, 0, { G(299, 2), 300, G(299, 3), 100 } } })')
m = mobs(L)[299]; assert m.k == 3 and m.c == 900 and m.i[2318][1] == 3 and m.i[2318][2] == 5
# a kill with nothing to loot counts (solo)
L.execute('KILL(G(299, 4), "Young Wolf"); RUN_TIMERS()'); assert mobs(L)[299].k == 4
# ...but not in a group, where someone else may have the loot
L.execute('GROUP = true; KILL(G(299, 5), "Young Wolf"); RUN_TIMERS(); GROUP = false'); assert mobs(L)[299].k == 4
# fishing and gathering nodes are ignored
L.execute('IsFishingLoot = function() return true end; LOOT({ { "|Hitem:2589:0|h", 1, { G(299, 9), 1 } } }); IsFishingLoot = function() return false end')
L.execute('LOOT({ { "|Hitem:2589:0|h", 1, { "GameObject-0-1-2-3-1731-9", 1 } } })')
assert mobs(L)[299].k == 4 and mobs(L)[1731] is None
# a split stack from one corpse is one drop
L.execute('LOOT({ { "|Hitem:2589:0|h", 20, { G(113, 1), 20 } }, { "|Hitem:2589:0|h", 5, { G(113, 1), 5 } } })')
m = mobs(L)[113]; assert m.k == 1 and m.i[2589][1] == 1 and m.i[2589][2] == 25
# skinning a corpse you never looted (someone else's kill) adds nothing
L.execute('C_Spell.GetSpellName = function(id) return id == 8617 and "Skinning" or nil end')
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8617); LOOT({ { "|Hitem:2318:0|h", 1, { G(299, 50), 1 } } })')
assert mobs(L)[299].k == 4 and mobs(L)[299].i[2318][2] == 5
L.execute("GetTime = function() return 100 end")  # time moves on
# a mob someone else tagged isn't an empty kill of yours
L.execute('UNITS.target = { guid = G(299, 60), name = "Young Wolf", level = 2 }; UnitIsTapDenied = function() return true end; FIRE("PLAYER_TARGET_CHANGED")')
L.execute('KILL(G(299, 60), "Young Wolf"); RUN_TIMERS(); UnitIsTapDenied = function() return false end'); assert mobs(L)[299].k == 4
# counted as empty, then it turns out to have loot: the loot is added, the kill isn't counted again
L.execute('KILL(G(299, 61), "Young Wolf"); RUN_TIMERS()'); assert mobs(L)[299].k == 5
L.execute('LOOT({ { nil, 0, { G(299, 61), 40 } } })'); assert mobs(L)[299].k == 5 and mobs(L)[299].c == 940
# counted corpses survive a /reload
assert L.eval("FarmKingDB.corpses[G(299, 1)]")
# a mob that dies near you without ever fighting you isn't your kill
L.execute('UNITS.nameplate2 = { guid = G(299, 62), name = "Young Wolf", level = 2, dead = true }; FIRE("UNIT_HEALTH", "nameplate2"); RUN_TIMERS(); UNITS.nameplate2 = nil')
assert mobs(L)[299].k == 5
# your pet's fight counts
L.execute('GUIDS.pet = "Pet-1-PET"; UNITS.pet = { guid = GUIDS.pet }; UNITS.target = { guid = G(113, 2), name = "Stonetusk Boar", level = 5 }')
L.execute('THREAT["pet" .. G(113, 2)] = 1; FIRE("UNIT_THREAT_LIST_UPDATE", "target"); UNITS.target.dead = true; FIRE("UNIT_FLAGS", "target"); RUN_TIMERS()')
L.execute('UNITS.pet = nil; GUIDS.pet = nil; UNITS.target = nil')
assert mobs(L)[113].k == 2
assert len(L.eval("FORBIDDEN")) == 0
print("TRACKING OK")

# Recent kills: each mob once, the latest first
assert list(L.eval("FarmKingDB.recent").values()) == [113, 299]
L.execute('KILL(G(299, 63), "Young Wolf"); RUN_TIMERS()')
assert list(L.eval("FarmKingDB.recent").values()) == [299, 113] and mobs(L)[299].k == 6
print("RECENT OK")

# Value of a kill: AH price after the cut, vendor for grey and soulbound, nothing for quest items
L.execute("""
ScannerKingDB.prices[2318] = { p = 100, m = 120, t = ScannerKing.Now(), q = 5 }
ScannerKingDB.prices[6000] = { p = 9000, t = ScannerKing.Now() }
ScannerKingDB.prices[7000] = { p = 99999, t = ScannerKing.Now() }
""")
assert ns.ItemValue(2318)[0] == 120 * 0.95 and ns.ItemValue(4865)[0] == 5 and ns.ItemValue(7000)[0] == 900 and ns.ItemValue(5000)[0] == 0
assert ns.ItemValue(2589)[0] == 13  # no auction price: vendor
v = ns.Value(299)
# 6 kills: 940 coin, 5 leather, 1 pelt
assert v.kills == 6 and abs(v.coin - 940 / 6) < 1e-9
assert abs(v.gold - (940 / 6 + 5 / 6 * 114 + 1 / 6 * 5)) < 1e-6, v.gold
assert v.best == 2318
# filters: no coin, no grey
L.execute("FarmKingDB.filter.coin = false; FarmKingDB.filter.q0 = false")
assert abs(ns.Value(299).gold - 5 / 6 * 114) < 1e-6
L.execute("FarmKingDB.filter.coin = true; FarmKingDB.filter.q0 = true")
print("VALUE OK")

# The mini tracker: this session's kills, drops, coin, total; gold per hour while the timer runs
L.eval("SlashCmdList.FARMKING")("mini")
mini = ns.miniFrame
def minitexts():
    fs = L.eval("FONTS"); return [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
t = minitexts()
assert mini.shown and "Kills: 8" in t, t  # 6 wolves, 2 boars
assert "Young Wolf x6" in t and "Stonetusk Boar x2" in t, t
assert any("Light Leather|r x5" in x for x in t) and "Coin" in t and "Total" in t, t
total, gph, secs = ns.SessionTotals()
assert abs(total - (940 + 5 * 114 + 5 + 25 * 13)) < 1e-6 and gph is None, total
# the timer: only loot taken while it runs counts toward gold per hour
L.execute('GetTime = function() return 200 end')
timer = [f for f in L.eval("FRAMES").values() if f.text == "Start timer"][0]; timer.scripts.OnClick(timer)
L.execute('GetTime = function() return 200 + 1800 end')
L.execute('KILL(G(299, 64), "Young Wolf"); LOOTABLE[G(299, 64)] = true; LOOT({ { nil, 0, { G(299, 64), 10000 } } }); RUN_TIMERS()')
total, gph, secs = ns.SessionTotals()
assert secs == 1800 and abs(gph - 20000) < 1e-6, (secs, gph)  # 1 gold in half an hour
tick = [f for f in L.eval("FRAMES").values() if f.scripts.OnUpdate][0]; tick.scripts.OnUpdate(tick, 1)
L.execute('FIRE("PLAYER_LOGIN")')  # a /reload pauses it, keeping its time
assert L.eval("FarmKingDB.session.timer.running") == False and ns.SessionTotals()[2] == 1800
# collapse shows gold per hour in the title; reset clears it
col = [f for f in L.eval("FRAMES").values() if f.text == "-"][0]; col.scripts.OnClick(col)
assert any(x.startswith("Farm King  ") and "/hr" in x for x in minitexts())
col.scripts.OnClick(col)
rs = [f for f in L.eval("FRAMES").values() if f.text == "Reset"][0]; rs.scripts.OnClick(rs); L.execute("RUN_TIMERS()")
assert ns.SessionTotals()[0] == 0 and "Nothing killed yet" in "".join(minitexts())
L.eval("SlashCmdList.FARMKING")("mini off"); assert not mini.shown
print("MINI OK")

# The window without QuestieDB: mobs you've seen; Best farms needs enough kills
def texts():
    fs = L.eval("FONTS"); out = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
    fr = L.eval("FRAMES"); out += [fr[i].text for i in range(1, len(fr) + 1) if fr[i].text and fr[i].shown != False]
    return out
def rows(): return [r for r in L.eval("FRAMES").values() if r.id and r.shown and r.cells and len(r.cells) == 8]  # the mob list (White Items rows have 7)
def side(label):
    return L.eval("(function() for _, f in ipairs(FRAMES) do if f.entry and f.shown and f.text and f.text:find('%s', 1, true) then return f end end end)()" % label)
def button(label):
    return L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' then return f end end end)()" % label)
L.eval("SlashCmdList.FARMKING")("")
t = texts()
assert any("No QuestieDB: mobs you've seen." in x for x in t) and "Min kills: 5" in t, t
assert [x.id for x in rows()] == [299]  # the only mob with 5+ kills
L.execute("FarmKingDB.filter.minKills = 10"); L.eval("SlashCmdList.FARMKING")(""); L.eval("SlashCmdList.FARMKING")("")
assert rows() == [] and any("No mob has 10+ kills" in x for x in texts())
mk = button("Min kills: 10"); [mk.scripts.OnClick(mk) for _ in range(3)]
assert L.eval("FarmKingDB.filter.minKills") == 1
r = rows(); assert sorted(x.id for x in r) == [113, 299], [x.id for x in r]
b = side("Elwynn Forest"); assert b and b.count.text == "2"
b = side("All mobs"); b.scripts.OnClick(b); assert len(rows()) == 2
# Recent kills: the latest first
b = side("Recent kills"); b.scripts.OnClick(b); assert [x.id for x in rows()] == [299, 113]
L.execute('KILL(G(113, 3), "Stonetusk Boar"); RUN_TIMERS()'); assert [x.id for x in rows()] == [113, 299]
b = side("All mobs"); b.scripts.OnClick(b)
# a mob's page
r = [x for x in rows() if x.id == 299][0]; r.scripts.OnClick(r, "LeftButton")
t = texts()
assert "Young Wolf" in t and "Gold per kill" in t and "< Back" in t and "Track on map" in t and "Light Leather" in "".join(t), t
assert "Seen at 9 spots." in t, [x for x in t if "spot" in x]
# track it: pins from where it was seen
L.execute("""
WorldMapFrame = CreateFrame("Frame"); WorldMapFrame.shown = true
WorldMapFrame.GetMapID = function() return 1429 end
CANVAS = CreateFrame("Frame"); CANVAS.GetWidth = function() return 1000 end; CANVAS.GetHeight = function() return 700 end
WorldMapFrame.GetCanvas = function() return CANVAS end
""")
tc = [f for f in L.eval("FRAMES").values() if f.scripts.OnClick and f.checked is not None and f.key is None][-1]
tc.SetChecked(tc, True); tc.scripts.OnClick(tc)
assert L.eval("FarmKingDB.track[299]")
pins = [f for f in L.eval("FRAMES").values() if f.mob == 299 and f.shown]
assert len(pins) == 9, len(pins)  # two sightings, seven kills
back = button("< Back"); back.scripts.OnClick(back)
print("UI OK")

# Guild: ask, answer, and add a guildmate's kills without double counting
L.execute("SENT = {}")
ask = button("Ask guild"); ask.scripts.OnClick(ask); L.execute("RUN_TIMERS()")
req = [L.eval("SENT")[i].text for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].prefix == "FarmKing1"]
assert len(req) == 1 and req[0][0] == "R" and list(ns.Unpack(req[0][1:]).values()) == [113, 299 - 113]
# Amy asks us: we answer with our own data
L.execute("SENT = {}")
L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + req[0] + '", "GUILD", "Amy-Realm"); RUN_TIMERS()')
ans = [L.eval("SENT")[i].text for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].prefix == "FarmKing1"]
blocks = [b for a in ans for b in ns.UnpackDrops(a[1:]).values()]
wolf = [b for b in blocks if b.id == 299][0]
assert wolf.k == 7 and wolf.c == 10940 and wolf.i[2318][1] == 3 and wolf.i[2318][2] == 5
# Bob answers with 6 kills of his own
bob = list(ns.PackDrops(L.eval("{ { id = 299, k = 6, c = 600, i = { [2318] = { 2, 2 } } } }")).values())[0]
for _ in range(2):  # twice: his latest replaces his earlier answer
    L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + bob + '", "GUILD", "Bob-Realm"); RUN_TIMERS()')
v = ns.Value(299); assert v.kills == 13 and v.mine == 7 and v.mates == 1 and abs(v.coin - 11540 / 13) < 1e-9
L.execute("FarmKingDB.filter.guild = false"); assert ns.Value(299).kills == 7
L.execute("FarmKingDB.filter.guild = true")
# a long loot table splits into parts and comes back whole
big = "{ { id = 77, k = 100, c = 12345, i = {" + ",".join("[%d] = { %d, %d }" % (10000 + i * 37, i, i * 3) for i in range(1, 80)) + "} } }"
msgs = list(ns.PackDrops(L.eval(big)).values())
assert len(msgs) > 1 and all(len(m) <= 250 for m in msgs)
L.execute("FarmKingDB.guild = {}")
for m_ in msgs:
    L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + m_ + '", "GUILD", "Cat-Realm")')
L.execute("RUN_TIMERS()")
cat = L.eval("FarmKingDB.guild.Cat.mobs[77]")
assert cat.k == 100 and cat.c == 12345 and len(list(cat.i.keys())) == 79 and cat.i[10000 + 37 * 50][2] == 150
# a later part whose start was missed doesn't mix into old data
L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + msgs[-1] + '", "GUILD", "Dan-Realm"); RUN_TIMERS()')
assert L.eval("FarmKingDB.guild.Dan.mobs[77]") is None
# whispers aren't trusted
L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + bob + '", "WHISPER", "Eve-Realm"); RUN_TIMERS()')
assert L.eval("FarmKingDB.guild.Eve") is None
# /fk share off: no answers
L.eval("SlashCmdList.FARMKING")("share off"); L.execute("SENT = {}")
L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + req[0] + '", "GUILD", "Amy-Realm"); RUN_TIMERS()')
assert len([1 for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].prefix == "FarmKing1"]) == 0
print("GUILD OK")

# ---------------------------------------------------------------- with QuestieDB
L, ns = fresh(True)
assert ns.QuestieAvailable() and not ns.QuestieReady()
L.eval("SlashCmdList.FARMKING")("")
L.execute("RUN_TIMERS()")
assert ns.QuestieReady()
qm = ns.QuestieMobs()
assert qm[299] and qm[113] and qm[500] and not qm[600] and not qm[700] and not qm[1]  # hostile mobs only
assert list(ns.QuestieDrops(299).values()) == [2318] and sorted(ns.QuestieDrops(500).values()) == [2589, 8000]
info = ns.MobInfo(500); assert info.name == "Riverpaw Gnoll" and info.lmin == 10 and info.rank == "elite" and info.map == 1436
L.execute("FarmKingDB.filter.minKills = 1")
b = side("All mobs"); b.scripts.OnClick(b)
assert sorted(r.id for r in rows()) == [113, 299, 500]
b = side("Westfall"); b.scripts.OnClick(b); assert [r.id for r in rows()] == [500]
t = texts(); assert any("QuestieDB: every mob." in x for x in t)
# the gnoll's page lists drops nobody has seen yet, and its spawn points come from QuestieDB
r = rows()[0]; r.scripts.OnClick(r, "LeftButton")
t = texts()
assert "Riverpaw Gnoll |cffffd100(elite)|r" in t and "1 spawn points from QuestieDB." in t, t
assert t.count("|cff808080not seen|r") == 2
spots = ns.Spots(500)[0]; assert spots[1][1] == 1436 and abs(spots[1][2] - 0.3) < 1e-9
# killing a QuestieDB mob you've never targeted still works
L.execute('LOOT({ { "|Hitem:8000:0|h", 1, { G(500, 1), 1 } } })')
assert mobs(L)[500].k == 1 and ns.Value(500).kills == 1
print("QUESTIEDB OK")

# Hunting an item: search items, pick one, every mob that drops it, highest level first
L.execute('KILL(G(299, 70), "Young Wolf"); LOOTABLE[G(299, 70)] = true; LOOT({ { "|Hitem:2318:0|h", 1, { G(299, 70), 1 } } })')
mode = button("Mobs"); mode.scripts.OnClick(mode)
assert button("Items")
L.execute("(function() for _, f in ipairs(FRAMES) do if f.SetAutoFocus and f.scripts.OnTextChanged then SEARCH = f; f.GetText = function() return 'leather' end; f.scripts.OnTextChanged(f, true) end end end)()")
r = rows(); assert [x.id for x in r] == [2318], [x.id for x in r]
t = texts(); assert "Dropped by" in t and "Best chance" in t
assert any("Light Leather" in x for x in t) and "2" in t and "100%" in t, t
L.execute("SEARCH.GetText = function() return '' end")
r[0].scripts.OnClick(r[0], "LeftButton")
r = rows(); assert [x.id for x in r] == [113, 299], [x.id for x in r]  # boar (5-6) above wolf (1-2)
t = texts(); assert "Spawns" in t and "Chance" in t
assert any("dropped by 2 mobs, levels 1-6, 3 spawn points" in x for x in t), [x for x in t if "dropped" in x]
# its mob page, then back to the hunt
r[1].scripts.OnClick(r[1], "LeftButton"); assert "Young Wolf" in texts()
back = button("< Back"); back.scripts.OnClick(back); assert [x.id for x in rows()] == [113, 299]
# a shift-clicked link in the search box hunts that item
L.execute("SEARCH.GetText = function() return SEARCH.text end; SEARCH.text = '|Hitem:8000::|h[Rare Gem]|h'; SEARCH.scripts.OnTextChanged(SEARCH, true)")
assert [x.id for x in rows()] == [500]
# other addons (Econ King) open it straight on an item
L.execute("FarmKingFrame = nil"); L.eval("FarmKing").ShowItem(2318); assert [x.id for x in rows()] == [113, 299]
# a tab goes back to mobs
b = side("All mobs"); b.scripts.OnClick(b); assert len(rows()) == 3
print("HUNT OK")

# White Items: white items with an auction price that some mob drops, by price x sqrt(spawn points)
L.execute("""
local now = ScannerKing.Now()
ScannerKingDB.prices[2318] = { p = 100, m = 120, t = now, q = 50 }   -- Light Leather: wolves (2 spawns) and boars (1)
ScannerKingDB.prices[2589] = { p = 400, t = now, q = 10 }            -- Linen Cloth: the gnoll (1 spawn)
ScannerKingDB.prices[8000] = { p = 9000, t = now }                   -- Rare Gem: blue, not listed
ScannerKingDB.prices[4865] = { p = 50, t = now }                     -- Ruined Pelt: grey, not listed
ScannerKingDB.prices[5000] = { p = 50, t = now }                     -- Quest Fang: quest item, not listed
""")
w = sorted(ns.WhiteItems()[0].values(), key=lambda e: -e.score)
assert [e.id for e in w] == [2589, 2318], [e.id for e in w]
assert w[0].score == 100 and w[1].score == round(114 * 3 ** 0.5 / 380 * 100) and w[1].spawns == 3 and w[1].mobs == 2 and w[1].listed == 50
tab = button("White Items"); tab.scripts.OnClick(tab)
t = texts(); assert "Best chance" in t and any("Score: price x square root" in x for x in t) and any("Linen Cloth" in x for x in t), t
wrow = L.eval("(function() for _, f in ipairs(FRAMES) do if f.id == 2318 and f.cells and #f.cells == 7 and f.shown then return f end end end)()")
assert wrow and wrow.cells[7].text == "|cffffd100" + str(w[1].score) + "|r"
# click an item: every mob that drops it; click a mob: its page
wrow.scripts.OnClick(wrow)
assert [x.id for x in rows()] == [113, 299]
r = rows()[1]; r.scripts.OnClick(r, "LeftButton"); assert "Young Wolf" in texts()
tab.scripts.OnClick(tab); assert any("Score: price x square root" in x for x in texts())
mt = button("Mob Farming"); mt.scripts.OnClick(mt)
assert L.eval("FarmKing.IsDrop(2318)") and not L.eval("FarmKing.IsDrop(12345)")
print("WHITE OK")
print("ALL TESTS PASSED")
