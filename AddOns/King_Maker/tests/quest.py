# Quest (was Quest King): /qk and Quest Gold (the 48+ quests' worth per zone for this
# character, learning Forever's real quest gold, the lookup when you enter a zone) and its page.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# Forever doesn't have these Classic globals; touching them must fail loudly.
NO_CLASSIC = """
for _, name in ipairs({ "GetItemInfo", "GetContainerItemInfo", "GetContainerNumSlots", "GetQuestLogTitle" }) do _G[name] = nil end
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and rawget(f, "mark") then return f end end end
"""

L, KM = fresh(only=["Quest"], seed=NO_CLASSIC)
ns = KM.mods.Quest
qk = L.eval("SlashCmdList.QUESTKING")
L.globals().QNS = ns
assert L.eval("QuestKing == QNS"), "QuestKing is the module namespace, as in 1.x"
assert L.eval("QuestKingDB.marks") is None and L.eval("QuestKingDB.tooltip") is None, "bag cleanup is gone"
assert L.eval("QuestKingMinimapButton") is None and L.eval("QuestKingDungeons") is None, "no button or window of its own"



# /qk opens Quest Gold; the bag cleanup commands say it's gone; no tooltip line, no bag events
qk(""); assert KM.IsShown("questgold"), "/qk opens Quest Gold"
qk(""); assert not KM.IsShown()
qk("list"); assert "Bag cleanup is gone" in last(L), last(L)
qk("tooltip off"); assert "Bag cleanup is gone" in last(L)
qk("help"); assert "/qk" in last(L) and "Quest Gold" in last(L)
assert L.eval("QuestKing.Status") is None and L.eval("QuestKing.UnneededReason") is None and L.eval("QuestKing.QUEST_ITEMS") is None
print("SLASH OK")

# ---------------------------------------------------------------- Quest Gold
QG = NO_CLASSIC + """
PLAYER.level, PLAYER.class, PLAYER.classID, PLAYER.faction = 55, "WARRIOR", 1, "Horde"
MAPS = MAPS or {}; MAPS[1446] = "Tanaris"; MAPS[1422] = "Western Plaguelands"
ITEM(5001, "Sand Blade", { sell = 500 }); ITEM(5002, "Sand Ring", { sell = 3000 }); ITEM(5003, "Sand Potion", { sell = 10 })
ITEM(5004, "Thorium Bar", { sell = 100 })
ScannerKingDB = { prices = { [5001] = { p = 20000, t = 1 }, [5003] = { p = 1000, t = 1 }, [5004] = { p = 500, t = 1 } } }
"""
L, KM = fresh(only=["Scanner", "Quest"], seed=QG)
ns = KM.mods.Quest
qk = L.eval("SlashCmdList.QUESTKING")
assert len(list(ns.QUESTS)) > 500, "the generated data loads"
writs = [q for q, d in ns.QUESTS.items() if str(d[12]).startswith("Craftsman's Writ")]
assert not writs and ns.QUESTS[94212] is None, "Supply Writs are repeatable profession dailies: not Quest Gold's (2.10)"
assert ns.QUESTS[98247] is not None, "the one-time Shipping Label stays"
L.globals().QNS = ns
L.execute("""
QNS.QUESTS = {
  [9001] = { 1446, 50, 45, "", 0, { 5001, 1, 5002, 1 }, {}, 0, "", {}, 0, "Sand Quest" },
  [9002] = { 1446, 52, 45, "A", 0, {}, {}, 0, "", {}, 0, "Alliance Only" },
  [9003] = { 1446, 52, 45, "", 7000, {}, { 5003, 2 }, 9001, "", { 5004, 5 }, 0, "Second Sand Quest" },
  [9004] = { 1422, 58, 50, "", 0, {}, {}, 0, "e", {}, 1, "Warriors Only" },
  [9005] = { 1422, 60, 58, "", 0, {}, {}, 0, "", {}, 0, "Too High" },
  [9006] = { 1422, 59, 50, "", 0, {}, {}, 0, "", {}, 256, "Warlocks Only" },
}
""")
# values: an unseen quest's gold is at least 1g; the best choice by what it fetches (AH after the cut vs vendor)
v = ns.QuestValue(9001)
assert v.gold == 10000 and v.guess and v.best.item == 5001 and v.best.value == 19000 and v.worth == 29000, (v.gold, v.worth)
v = ns.QuestValue(9003)
assert v.gold == 10000 and v["items"] == 1900 and v.cost == 2375 and v.worth == 10000 + 1900 - 2375, (v["items"], v.cost, v.worth)
# this character: faction and class; states
assert ns.ForMe(9001) and not ns.ForMe(9002) and ns.ForMe(9004) and not ns.ForMe(9006)
assert ns.QuestState(9001) == "ready" and ns.QuestState(9003) == "locked" and ns.QuestState(9005) == "low"
L.execute("LOG = { { questID = 9004 } }"); assert ns.QuestState(9004) == "log"
# zones: Horde warrior sees 2 in Tanaris, 2 in Western Plaguelands; most worth first
Z = ns.Zones()
assert [Z[i].name for i in range(1, len(Z) + 1)] == ["Tanaris", "Western Plaguelands"], [Z[i].name for i in range(1, len(Z) + 1)]
assert Z[1].total == 2 and Z[1].left == 2 and Z[1].guesses == 2 and Z[1].worth == 29000 + 9525

# learning the real gold: what a turn-in paid; the quest is done and drops out of what's left
L.execute("COMPLETED[9001] = true; FIRE('QUEST_TURNED_IN', 9001, 0, 15500)")
assert L.eval("QuestKingDB.gold[9001]") == 15500
v = ns.QuestValue(9001); assert v.gold == 15500 and not v.guess
assert ns.QuestState(9003) == "ready", "the quest before it is done"
Z = ns.Zones(); tan = [Z[i] for i in range(1, len(Z) + 1) if Z[i].name == "Tanaris"][0]
assert tan.left == 1 and Z[1].name == "Western Plaguelands", "Tanaris has less left now: it drops below"
# the quest giver's window (offer or turn-in)
L.execute("GetQuestID = function() return 9004 end; GetRewardMoney = function() return 21000 end; FIRE('QUEST_DETAIL')")
assert L.eval("QuestKingDB.gold[9004]") == 21000
# with 3 real amounts near a level, unseen quests there use their median
L.execute("QuestKingDB.gold[9005] = 30000"); ns.LearnGold(9006, 18000)
L.execute('QNS.QUESTS[9007] = { 1422, 59, 50, "", 0, {}, {}, 0, "", {}, 0, "Unseen 59" }')
assert L.eval("(QNS.QuestGold(9007))") == 21000, "median of 18000, 21000, 30000 (levels 57-61)"
assert L.eval("(QNS.QuestGold(9003))") == 10000, "level 52: one real amount nearby is too few, so 1g"

# asking the server: one request per unknown quest in the zone, answers fill the gold in
L.execute("""
ASKED = {}
C_QuestLog.RequestLoadQuestByID = function(q) ASKED[#ASKED + 1] = q end
GetQuestLogRewardMoney = function(q) return q == 9003 and 12000 or 0 end
QuestKingDB.gold[9003] = nil
""")
assert ns.CanAsk()
n = ns.AskZone(1446); L.execute("RUN_TIMERS()")
assert n == 1 and L.eval("ASKED[1]") == 9003, n
L.execute("FIRE('QUEST_DATA_LOAD_RESULT', 9003, true)")
assert L.eval("QuestKingDB.gold[9003]") == 12000
# the server knows nothing about a quest: set aside, out of the zone's totals; one that says 0 pays 0 for real
L.execute("QNS.QUESTS[9008] = { 1446, 60, 55, '', 0, {}, {}, 0, '', {}, 0, 'Not Out Yet' }; QNS.QUESTS[9009] = { 1446, 60, 55, '', 0, {}, {}, 0, '', {}, 0, 'Pays Nothing' }")
L.execute("GetQuestLogRewardMoney = function(q) return 0 end; HaveQuestRewardData = function() return true end")
before = [z for z in ns.Zones().values() if z.name == "Tanaris"][0].total
ns.AskZone(1446); L.execute("RUN_TIMERS(); FIRE('QUEST_DATA_LOAD_RESULT', 9008, false); FIRE('QUEST_DATA_LOAD_RESULT', 9009, true)")
assert L.eval("QuestKingDB.noData[9008]") is True and L.eval("QuestKingDB.gold[9008]") is None
assert L.eval("QuestKingDB.gold[9009]") == 0 and ns.QuestState(9008) == "nodata"
tan = [z for z in ns.Zones().values() if z.name == "Tanaris"][0]
assert tan.total == before - 1 and tan.missing == 1, (before, tan.total, tan.missing)
# seeing it for real later (picked up, gold shown) brings it back
ns.LearnGold(9008, 20000); assert L.eval("QuestKingDB.noData[9008]") is None
# entering a zone: one lookup per character and zone (per King Maker version), never in combat, nothing printed
L.execute("ASKED = {}; QuestKingDB.gold[9003] = nil; QuestKingDB.asked = {}; PLAYER.map = 1446")
assert ns.AutoAsk() >= 1 and (L.execute("RUN_TIMERS()") or L.eval("ASKED[1]")) == 9003
assert ns.AutoAsk() == 0, "the second visit doesn't ask again"
L.execute("FIRE('QUEST_DATA_LOAD_RESULT', 9003, true)")
# a new King Maker version asks again; the entering-world event does it by itself after the map settles
L.execute("for _, t in pairs(QuestKingDB.asked) do for m in pairs(t) do t[m] = 'old' end end; ASKED = {}; QuestKingDB.gold[9003] = nil")
L.execute("FIRE('ZONE_CHANGED_NEW_AREA'); RUN_TIMERS()")
assert L.eval("ASKED[1]") == 9003, "entering the zone after an update asks again"
L.execute("FIRE('QUEST_DATA_LOAD_RESULT', 9003, true)")
# in combat: put off until combat ends
L.execute("QuestKingDB.asked = {}; ASKED = {}; QuestKingDB.gold[9003] = nil; InCombatLockdown = function() return true end")
assert ns.AutoAsk() == 0 and L.eval("ASKED[1]") is None
L.execute("InCombatLockdown = function() return false end; FIRE('PLAYER_REGEN_ENABLED'); RUN_TIMERS()")
assert L.eval("ASKED[1]") == 9003, "asked once combat ended"
L.execute("FIRE('QUEST_DATA_LOAD_RESULT', 9003, true)")
# a sub-map (a town in the zone) climbs to its zone; the setting turns it off
L.execute("QuestKingDB.asked = {}; ASKED = {}; QuestKingDB.gold[9003] = nil; PLAYER.map = 99901")
L.execute("local get = C_Map.GetMapInfo; C_Map.GetMapInfo = function(m) if m == 99901 then return { mapID = m, name = 'Gadgetzan', parentMapID = 1446 } end return get and get(m) end")
assert ns.AutoAsk() >= 1 and (L.execute("RUN_TIMERS()") or L.eval("ASKED[1]")) == 9003, "Gadgetzan counts as Tanaris"
L.execute("FIRE('QUEST_DATA_LOAD_RESULT', 9003, true)")
L.execute("QuestKingDB.asked = {}; ASKED = {}; QuestKingDB.gold[9003] = nil; QuestKingDB.autoAsk = false")
assert ns.AutoAsk() == 0 and L.eval("ASKED[1]") is None, "setting off: no lookup"
L.execute("QuestKingDB.autoAsk = true; QuestKingDB.gold[9003] = 12000; PLAYER.map = 1423")
# the amounts shipped with King Maker count as real; one learned in game wins; shipped "not in Forever" too
L.execute("QNS.QUESTS[9010] = { 1446, 55, 50, '', 0, {}, {}, 0, '', {}, 0, 'Shipped' }; QNS.QUEST_GOLD[9010] = 15000")
g, guess = L.eval("QNS.QuestGold(9010)")
assert g == 15000 and not guess, (g, guess)
L.execute("ASKED = {}; QuestKingDB.asked = {}; PLAYER.map = 1446"); ns.AutoAsk(); L.execute("RUN_TIMERS()")
assert 9010 not in list(L.eval("ASKED").values()), "a shipped amount isn't asked for"
ns.LearnGold(9010, 16000); assert L.eval("(QNS.QuestGold(9010))") == 16000
L.execute("QNS.QUESTS[9011] = { 1446, 55, 50, '', 0, {}, {}, 0, '', {}, 0, 'Shipped none' }; QNS.QUEST_NODATA[9011] = true")
assert ns.QuestState(9011) == "nodata"
ns.LearnGold(9011, 9000); assert ns.QuestState(9011) != "nodata", "learned for real: back in"
assert L.eval("QNS.QUEST_GOLD ~= nil and next(QNS.QUEST_GOLD) ~= nil"), "the shipped amounts load"
L.execute("QNS.QUESTS[9010], QNS.QUESTS[9011], QuestKingDB.gold[9010], QuestKingDB.gold[9011] = nil, nil, nil, nil; PLAYER.map = 1423")
print("QUEST GOLD LOGIC OK")


# ---------------------------------------------------------------- the Quest Gold page
def texts():
    fs = L.eval("FONTS")
    return [str(fs[i].text) for i in range(1, len(fs) + 1) if fs[i].text]


qk("gold")
assert KM.IsShown("questgold") and not KM.errorShown, last(L)
assert L.eval('BTN("Ask the game")') is None, "no Ask the game button: it looks up by itself"
ns.goldTable.SetHeight(ns.goldTable, 600); ns.goldTable.Layout(ns.goldTable)
assert any("Western Plaguelands" in x for x in texts()), "opens on the zone with the most left"
L.execute('for _, f in ipairs(FRAMES) do if rawget(f, "zone") and f.zone.name == "Tanaris" then f:Click() end end')
T = texts()
assert any("Tanaris" in x for x in T) and any("quests left, worth" in x for x in T), [x for x in T if "Tanaris" in x][:3]
assert any("Second Sand Quest" in x for x in T) and any("Sand Blade" in x or "Sand Potion" in x for x in T)
assert any(x == "Done" or "Done" in x for x in T) and any("Ready" in x for x in T)
assert not any("Alliance Only" in x for x in T) and not any("Warlocks Only" in x for x in T)
L.execute("QuestKingDB.qgHideDone = true"); ns.RefreshQuestGold()
rows = ns.goldTable.data
assert [rows[i].id for i in range(1, len(rows) + 1)] == [9008, 9003, 9009] and not KM.errorShown, last(L)  # Sand Quest (done) hidden; most worth first
L.execute("QuestKingDB.qgHideDone = false")

# The columns never overlap and fit the pane (the reward used to be a middle w = 0 column under the money columns).
cols = ns.goldCols
x = 8
for i in range(1, len(cols) + 1):
    c = cols[i]
    assert c.w > 0 and c.x == x, (c.key, c.w, c.x, x)
    x += c.w
assert x <= ns.goldPaneW, (x, ns.goldPaneW)

# The zone list: as many rows as the side panel holds (557 in the window), the wheel scrolls the rest; nothing is
# drawn below the panel.
L.execute("""
QNS._Zones = QNS.Zones
QNS.Zones = function()
  local t = {}
  for i = 1, 40 do t[i] = { map = 5000 + i, name = "Zone " .. i, left = 1, total = 2, worth = 50000 - i, gold = 100, lo = 50, hi = 52,
    guesses = 0, missing = 0, quests = {} } end
  return t
end""")
side = ns.goldSide
L.globals().QSIDE = side
L.execute("RESIZE(QSIDE, 230, 557)"); ns.RefreshQuestGold()
assert ns.QuestZoneRows() == 32, ns.QuestZoneRows()
shown = L.eval("(function() local n, low = 0, 0 for _, f in ipairs(FRAMES) do if rawget(f, 'zone') and f:IsShown() and f.parent == QSIDE then n = n + 1; low = math.max(low, -f.point[3] + f.h) end end return n, low end)()")
assert shown[0] == 32 and shown[1] <= 557, shown
assert any(x == "|cffffffffZone 1|r" for x in [str(f) for f in L.eval("(function() local t = {} for _, f in ipairs(FRAMES) do if rawget(f, 'zone') then t[#t+1] = f.label.text end end return t end)()").values()])
L.execute("QSIDE:RunScript('OnMouseWheel', -1); QSIDE:RunScript('OnMouseWheel', -1); QSIDE:RunScript('OnMouseWheel', -1)")
names = [f for f in L.eval("(function() local t = {} for _, f in ipairs(FRAMES) do if rawget(f, 'zone') and f:IsShown() then t[#t+1] = f.zone.name end end return t end)()").values()]
assert names[0] == "Zone 9" and names[-1] == "Zone 40" and len(names) == 32, (names[:2], names[-1], len(names))
L.execute("QSIDE:RunScript('OnMouseWheel', 5)")
names = [f for f in L.eval("(function() local t = {} for _, f in ipairs(FRAMES) do if rawget(f, 'zone') and f:IsShown() then t[#t+1] = f.zone.name end end return t end)()").values()]
assert names[0] == "Zone 1", names[:2]
L.execute("QNS.Zones = QNS._Zones"); ns.RefreshQuestGold()
assert not KM.errorShown, last(L)
print("ZONE LIST OK")
qk("dungeons"); assert "Quest Gold took its place" in last(L)
qk("gold"); assert not KM.IsShown(), "/qk gold toggles it closed"
print("PAGE OK")

# The crown: quick action and tooltip line; Home tile; Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Quest Gold") ~= nil') and L.eval('MENU_ITEM("Dungeon Quests") == nil')
L.execute('MENU_ITEM("Quest Gold").fn()'); assert KM.IsShown("questgold")
L.execute('GameTooltip.lines = {}; KingMakerMinimapButton:RunScript("OnEnter")')
assert any("Quest gold:" in str(x) for x in L.eval("GameTooltip.lines").values())
KM.Show("home"); assert not KM.errorShown, last(L)
best = [b for b in KM.home.bestItems.values() if b.label == "Quests"]
assert best and "Western Plaguelands" in best[0].sub and best[0].page == "questgold", "Home: the best quest zone"
assert not [a for a in KM.home.attItems.values() if a.page == "questgold"], "not in a quest zone: no attention row"
L.execute("PLAYER.map = 1446"); KM.Refresh()
here = [a for a in KM.home.attItems.values() if a.page == "questgold"]
assert here and here[0].text.startswith("Tanaris: ") and "left here" in here[0].text, "in Tanaris: what's left here"
L.execute("PLAYER.map = nil")
KM.OpenSettings("quest"); assert "Hide quests you've done" in texts() and not KM.errorShown
print("SHELL OK")

# InitDB is safe twice and keeps the table; the 1.x button keys and Dungeon Quests' keys go
L3, KM3 = fresh(only=["Quest"], seed=NO_CLASSIC + "QuestKingDB = { marks = false, tooltip = true, button = true, buttonAngle = 250, dqDone = { ['rfc:Slaying the Beast'] = true }, dqView = 'route' }")
L3.execute("HELD = QuestKingDB"); KM3.mods.Quest.InitDB()
assert L3.eval("QuestKingDB == HELD") and L3.eval("QuestKingDB.marks") is None and L3.eval("QuestKingDB.tooltip") is None, "bag cleanup's settings go"
assert L3.eval("QuestKingDB.button") is None and L3.eval("QuestKingDB.buttonAngle") is None
assert L3.eval("QuestKingDB.dqDone") is None and L3.eval("QuestKingDB.dqView") is None and L3.eval("QuestKingDB.gold") is not None
KM3.Show("questgold"); assert not KM3.errorShown, last(L3)
print("INITDB OK")

print("quest: ok")
