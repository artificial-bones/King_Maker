# Quest (was Quest King): bag marks, the tooltip line, /qk, dungeon quest logic (29 dungeons, chains, levels, XP,
# waypoints, QuestieDB) and the Dungeon Quests page.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# Forever doesn't have these Classic globals; touching them must fail loudly.
NO_CLASSIC = """
for _, name in ipairs({ "GetItemInfo", "GetContainerItemInfo", "GetContainerNumSlots", "GetQuestLogTitle" }) do _G[name] = nil end
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and rawget(f, "mark") then return f end end end
function DUNGEON_BTN(name) for _, f in ipairs(FRAMES) do if rawget(f, "dungeon") and f.dungeon.name == name then return f end end end
"""

L, KM = fresh(only=["Quest"], seed=NO_CLASSIC)
ns = KM.mods.Quest
qk = L.eval("SlashCmdList.QUESTKING")
L.globals().QNS = ns
assert L.eval("QuestKing == QNS"), "QuestKing is the module namespace, as in 1.x"
assert L.eval("QuestKingDB.marks") is True and L.eval("QuestKingDB.tooltip") is True
assert L.eval("QuestKingMinimapButton") is None and L.eval("QuestKingDungeons") is None, "no button or window of its own"


def out(n=10):
    o = L.eval("OUTPUT")
    return [o[i] for i in range(max(1, len(o) - n + 1), len(o) + 1)]


def marked(bag, slot, frame="ContainerFrameCombinedBags"):
    return L.eval(f'MARKED("{frame}", {bag}, {slot})')


L.execute("""
ITEM(100, "Wolf Fang", { class = 12 })          -- objective of a quest in the log
ITEM(101, "Gnoll Paw", { class = 12 })          -- leftover from a quest already turned in
ITEM(102, "Sealed Letter to Ag'tor", { class = 12 }) -- delivery item named in the description
ITEM(103, "Blackened Torch", { class = 12 })    -- usable quest item
ITEM(104, "Torn Note", { class = 12 })          -- starts a quest you haven't done
ITEM(105, "Old Map Scrap", { class = 12 })      -- starts a quest you already finished
ITEM(106, "Linen Cloth", { class = 7 })         -- trade goods, never touched
ITEM(107, "Mysterious Egg", { class = 15 })     -- not class Quest, but the client says it's a quest item
ITEM(108, "Crumpled Page", { class = 12 })      -- starts a quest that's in your log
ITEM(109, "Kobold Candle", { class = 12, sell = 25 }) -- leftover, but a vendor buys it: sell it, no X
LOG = {
  { isHeader = true, title = "Elwynn Forest" },
  { questID = 1, title = "Wolves Across the Border", objectives = { { text = "Wolf Fang: 3/8", type = "item" } } },
  { questID = 2, title = "Return to Ag'tor", desc = "Take the Sealed Letter to Ag'tor in Ashenvale." },
  { questID = 3, title = "Burn the Nests", special = 103, objectives = { { text = "Nest burned: 0/4" } } },
  { questID = 8, title = "The Crumpled Page" },
}
COMPLETED[5] = true
BAGS[0][1] = { id = 100, count = 3 }
BAGS[0][2] = { id = 101, count = 7 }
BAGS[0][3] = { id = 102 }
BAGS[0][4] = { id = 103 }
BAGS[1][1] = { id = 104, quest = { isQuestItem = true, questID = 4 } }
BAGS[1][2] = { id = 105, quest = { isQuestItem = true, questID = 5 } }
BAGS[1][3] = { id = 106, count = 20 }
BAGS[2][5] = { id = 107, quest = { isQuestItem = true } }
BAGS[2][6] = { id = 108, quest = { isQuestItem = true, questID = 8, isActive = true } }
BAGS[2][7] = { id = 109, count = 4 }
ContainerFrameCombinedBags:Show()
FIRE("BAG_UPDATE_DELAYED"); RUN_TIMERS()
""")
S = lambda b, s: L.eval(f"QuestKing.Status({b}, {s})")
assert S(0, 1) == "needed"      # objective
assert S(0, 2) == "unneeded"    # leftover
assert S(0, 3) == "needed"      # description
assert S(0, 4) == "needed"      # usable quest item
assert S(1, 1) == "starter"     # starts a quest: keep
assert S(1, 2) == "unneeded"    # starts a quest you already did
assert S(1, 3) is None          # not a quest item
assert S(2, 5) == "unneeded"    # quest item by the client's flag
assert S(2, 6) == "needed"      # its quest is active
assert S(2, 7) == "sell" and not marked(2, 7), "a vendor buys it: no X, you'll sell it"
assert marked(0, 2) and marked(1, 2) and marked(2, 5)
assert not marked(0, 1) and not marked(1, 1) and not marked(1, 3) and not marked(0, 3)
b = L.eval('BUTTON("ContainerFrameCombinedBags", 0, 2)')
assert b.QuestKingMark.texture == "Interface\\RaidFrame\\ReadyCheck-NotReady"
# Bagnon's bag window: its buttons carry the bag themselves (GetBag), and get the same marks
L.execute("""
local inv = CreateFrame("Frame", "BagnonInventoryFrame", UIParent)
Bagnon = { Frames = { Get = function(_, id) if id == "inventory" then return inv end end } }
local group = CreateFrame("Frame", nil, inv)
BAGNON = {}
for _, bs in ipairs({ { 0, 1 }, { 0, 2 }, { 2, 5 } }) do
  local b = CreateFrame("Button", nil, group); b.bag = bs[1]; b:SetID(bs[2])
  function b:GetBag() return self.bag end
  function b:GetBagID() return 99 end -- the game's template method: means something else in Bagnon
  BAGNON[bs[1] .. ":" .. bs[2]] = b
end
inv:Show()
""")
L.eval("QuestKing").UpdateBagButtons()
bm = lambda k: bool(L.eval("BAGNON['%s'].QuestKingMark and BAGNON['%s'].QuestKingMark:IsShown()" % (k, k)))
assert bm("0:2") and bm("2:5") and not bm("0:1"), "Bagnon slots marked like the game's"
L.execute("BagnonInventoryFrame:Hide(); Bagnon = nil")
print("STATUS + MARKS OK")

line = L.eval("(HOVER(101))"); assert "safe to delete" in line, line
line = L.eval("(HOVER(109))"); assert "sell it to a vendor" in line, line
assert L.eval("(HOVER(100))") is None and L.eval("(HOVER(106))") is None
print("TOOLTIP OK")

qk("")
o = out(4); assert "3 quest items you can delete" in o[0] and "[Gnoll Paw]" in o[1] and "x7" in o[1], o
assert "King Maker" in o[0]
print("LIST OK")

# Turning in the wolf quest frees the fangs
L.execute("table.remove(LOG, 2); FIRE('QUEST_REMOVED', 1); RUN_TIMERS()")
assert S(0, 1) == "unneeded" and marked(0, 1)
# Picking up a quest that wants the gnoll paws un-marks them
L.execute("table.insert(LOG, { questID = 9, title = 'Paws', objectives = { { text = 'Gnoll Paw: 7/10' } } }); FIRE('QUEST_ACCEPTED', 9); RUN_TIMERS()")
assert S(0, 2) == "needed" and not marked(0, 2)
# Moving an item clears the old slot's mark
L.execute("BAGS[0][3], BAGS[0][9] = nil, BAGS[0][2]; BAGS[0][2] = nil; FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert not marked(0, 3) and not marked(0, 2) and S(0, 9) == "needed"
print("UPDATES OK")

# A collapsed header hides quests: mark nothing rather than risk a needed item
L.execute("LOG[1].isCollapsed = true; FIRE('QUEST_LOG_UPDATE'); RUN_TIMERS()")
assert S(0, 1) is None and not marked(0, 1)
assert S(1, 2) == "unneeded"   # starter items are judged by quest ID, not the log text
qk("list"); assert "Expand" in out(1)[0]
L.execute("LOG[1].isCollapsed = false; FIRE('QUEST_LOG_UPDATE'); RUN_TIMERS()")
assert S(0, 1) == "unneeded"
print("COLLAPSED OK")

qk("marks off"); assert not marked(0, 1); qk("marks on"); assert marked(0, 1)
qk("tooltip off"); assert L.eval("(HOVER(101))") is None; qk("tooltip on")
qk("help"); assert "/qk marks" in "".join(out(5))
qk("button"); assert "crown" in last(L), last(L)
print("SLASH OK")

# Bag opened after the scan gets marked on show
L.execute("ContainerFrameCombinedBags:Hide(); BUTTON('ContainerFrameCombinedBags', 0, 1).QuestKingMark.shown = false; ContainerFrameCombinedBags:Show()")
assert marked(0, 1)
print("ON SHOW OK")

# Settings: the bag rows drive the same switches
KM.OpenSettings("quest"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
cb = L.eval('CHECK("Red X on quest items no quest needs")'); assert cb and cb.checked
cb.GetScript(cb, "OnClick")(cb)
assert L.eval("QuestKingDB.marks") is False and not marked(0, 1)
cb.GetScript(cb, "OnClick")(cb); assert marked(0, 1)
print("SETTINGS OK")

# Older-style bag frames (ContainerFrame1Item1.., ContainerFrame_Update) and the tooltip script
L2, KM2 = fresh(only=["Quest"], seed=NO_CLASSIC + """
ContainerFrameCombinedBags = nil
for i = 1, 13 do local f = _G["ContainerFrame" .. i]; f.EnumerateValidItems = false; f.UpdateItems = false end
ContainerFrame1.id = 0
for s = 1, 16 do local b = CreateFrame("Button", "ContainerFrame1Item" .. s); b.id = s end
function ContainerFrame_Update(frame) end
TooltipDataProcessor = nil
GameTooltip.HasScript = function(self, k) return k == "OnTooltipSetItem" end
GameTooltip.HookScript = function(self, k, fn) self.setItem = fn end
GameTooltip.GetItem = function() return "Gnoll Paw", LINK(101) end
ITEM(101, "Gnoll Paw", { class = 12 })
BAGS[0][2] = { id = 101 }
""")
L2.execute("FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS(); ContainerFrame1:Show(); ContainerFrame_Update(ContainerFrame1)")
assert L2.eval("ContainerFrame1Item2.QuestKingMark.shown") is True
assert L2.eval("ContainerFrame1Item1.QuestKingMark") is None
L2.execute("GameTooltip.lines = {}; GameTooltip.setItem(GameTooltip)")
assert "safe to delete" in L2.eval("GameTooltip.lines[1]")
print("CLASSIC BAGS OK")


# ---------------------------------------------------------------- dungeon quests
DQ = NO_CLASSIC + """
PLAYER.level, PLAYER.class = 16, "WARRIOR"
MAP_CHILDREN[1414] = { { mapID = 1454, name = "Orgrimmar" }, { mapID = 1456, name = "Thunder Bluff" }, { mapID = 1413, name = "The Barrens" } }
MAP_CHILDREN[1415] = { { mapID = 1458, name = "Undercity" }, { mapID = 1420, name = "Tirisfal Glades" }, { mapID = 1421, name = "Silverpine Forest" } }
"""
L, KM = fresh(only=["Quest"], seed=DQ)
ns = L.eval("QuestKing")
qk = L.eval("SlashCmdList.QUESTKING")
D = {d.key: d for d in ns.DUNGEONS.values()}
assert len(D) == 29
rfc, rol = D["rfc"], D["rol"]
quests = lambda d: {q.name: q for q in d.quests.values()}
he = quests(rfc)["Hidden Enemies"]
# status: ready, in the log, a chain step in the log, done, ticked off
assert ns.QuestState(rfc, he) == "ready"
L.execute('LOG = { { questID = 5726, title = "Hidden Enemies" } }')
assert ns.QuestState(rfc, he) == "active"
assert [ns.StepState(he, st) for st in he.chain.values()][:2] == ["active", None]
L.execute('LOG = {}; COMPLETED[5726] = true; COMPLETED[5727] = true')
assert ns.QuestState(rfc, he) == "chain"
L.execute('COMPLETED[5728] = true'); assert ns.QuestState(rfc, he) == "done"
slay = quests(rfc)["Slaying the Beast"]
ns.SetTicked(rfc, slay, True); assert ns.QuestState(rfc, slay) == "done"
ns.SetTicked(rfc, slay, False); assert ns.QuestState(rfc, slay) == "ready"
# levels: without QuestieDB the pickup level is an estimate
assert tuple(ns.MinLevel(slay)) == (10, True) and ns.FullXPUntil(slay) == 21
L.execute("PLAYER.level = 8"); assert ns.QuestState(rfc, slay) == "low"; L.execute("PLAYER.level = 16")
f, t, n, tot = ns.BestLevels(rfc)
assert (n, tot) == (5, 5) and f == 10 and t == 20, (f, t, n, tot)
# class quests only for that class; endgame ones can be hidden
assert not any(q["class"] for q in ns.VisibleQuests(D["bfd"]).values())
L.execute('PLAYER.class = "WARLOCK"'); assert any(q["class"] == "WARLOCK" for q in ns.VisibleQuests(D["sfk"]).values()); L.execute('PLAYER.class = "WARRIOR"')
strat = D["strat"]; n60 = len(ns.VisibleQuests(strat))
L.execute("QuestKingDB.dqHide60 = true"); assert len(ns.VisibleQuests(strat)) < n60; L.execute("QuestKingDB.dqHide60 = false")
p = ns.Progress(rfc); assert p.total == 5 and p.done == 1 and p.ready == 4, (p.total, p.done, p.ready)
# waypoints from the log's coordinates: the last place named before them
lj = quests(rol)["Light's Justice"]
m, x, y, src = ns.GiverPoint(lj); assert (m, x, y) == (1458, 57.8, 89.7) and src == "the dungeon log", (m, x, y, src)
rath = quests(rol)["The Wrath of Rath'mael"]
assert ns.GiverPoint(rath)[0] == 1420  # "between Undercity and Brill, Tirisfal (65.2, 60.1)"
ns.WaypointToGiver(lj); assert L.eval("WAYPOINT.m") == 1458 and L.eval("TRACKED") is True
assert "Waypoint: Light's Justice, Undercity 57.8, 89.7" in last(L), last(L)
ns.WaypointToGiver(slay); assert "No coordinates" in last(L)
# QuestieDB: exact pickup level, IDs by name, the giver's spawn point, the dungeon entrance
L.execute('''
QuestDB = { Exists = function(id) return QDATA[id] ~= nil end,
  requiredLevel = function(id) return QDATA[id] and QDATA[id].min or 0 end,
  questLevel = function(id) return QDATA[id] and QDATA[id].lv or 0 end,
  startedBy = function(id) return QDATA[id] and QDATA[id].by or {} end,
  IdsByName = function(name) return NAMES[name] end }
QDATA = { [5761] = { min = 9, lv = 16, by = { { 3216 } } }, [2418] = { min = 35, lv = 40 }, [9999] = { min = 20, lv = 25 } }
NAMES = {}
NpcDB = { spawns = function(id) if id == 3216 then return { [1637] = { { 49.6, 50.4 } } } end end }
XPDB = { [5726] = { 16, 300 }, [5727] = { 16, 350 }, [5728] = { 16, 1150 }, [5729] = { 16, 400 }, [5761] = { 16, 1050 } }
LibQuestieDB = { Support = { Get = function(n) if n == "QuestXP" then return { db = XPDB } end return { private = { areaIdToUiMapId = "return { [1637] = 1454, [1337] = 1418 }",
  dungeons = { [1337] = { "Uldaman", nil, 3, { { 1337, 44.4, 12.2 } } } } } } end } }
''')
assert tuple(ns.MinLevel(slay)) == (9, False)
assert tuple(ns.GiverPoint(slay)) == (1454, 49.6, 50.4, "QuestieDB")
ulda = D["ulda"]
uq = list(ulda.quests.values())[0]
L.execute("NAMES[...] = { 9999, 2418 }", uq.name)
assert ns.QuestID(uq) in (9999, 2418)
ns.WaypointToEntrance(ulda); assert L.eval("WAYPOINT.m") == 1418
# XP: the game's rule for outlevelled quests, rounded like the game; per quest, per step, per dungeon
assert ns.AdjustXP(1150, 16, 16) == 1150 and ns.AdjustXP(1150, 16, 21) == 1150
assert ns.AdjustXP(1150, 16, 22) == 925 and ns.AdjustXP(1150, 16, 26) == 120 and ns.AdjustXP(1150, 16, 40) == 120
assert ns.AdjustXP(1150, 16, 60) == 0 and ns.AdjustXP(87, 10, 16) == 70
assert tuple(ns.QuestXP(slay)) == (1050, 1050)
L.execute("PLAYER.level = 23"); assert tuple(ns.QuestXP(slay)) == (1050, 625); L.execute("PLAYER.level = 16")
L.execute("COMPLETED = {}; COMPLETED[5726] = true")
xp, known, total = ns.DungeonXP(rfc)
assert xp == 350 + 1150 + 400 + 1050 and known == 4, (xp, known, total)
assert "XP left" in ns.DungeonXPText(rfc) and "1,050" not in ns.DungeonXPText(rfc) and "2,950" in ns.DungeonXPText(rfc), ns.DungeonXPText(rfc)
assert ns.Commas(1234567) == "1,234,567"
print("DUNGEON LOGIC OK")


# ---------------------------------------------------------------- the Dungeon Quests page
def texts():
    fs = L.eval("FONTS")
    return [str(fs[i].text) for i in range(1, len(fs) + 1) if fs[i].text]


def click(b, which="LeftButton"):
    b.RunScript(b, "OnClick", which)


qk("dungeons")
assert KM.IsShown("dungeons") and not KM.errorShown, last(L)
ns.table.SetHeight(ns.table, 600); ns.table.Layout(ns.table)  # the mock's frames don't size themselves: room for every row
assert any(x.startswith("Best at level") for x in texts())
assert any("Ragefire Chasm" in x for x in texts())
assert L.eval('BTN("Dungeons")') and L.eval('BTN("Route")') and L.eval('BTN("Entrance waypoint")')
assert L.eval('CHECK("Hide level 60")') and L.eval('CHECK("Hide done")')
qk("route"); assert any("Start these chains early" in x for x in texts())
assert L.eval('BTN("Route")').active and ns.table.parent.shown is False, "the route takes the dungeon's place"
click(L.eval('BTN("Dungeons")')); assert L.eval("QuestKingDB.dqView") == "dungeons"
# chains inline: under the quest, last step first, the step to do next marked, a pin per step
L.execute('COMPLETED = {}; COMPLETED[5726] = true')
ns.VisibleQuests(rfc); assert ns.NextStep(he) == 2, ns.NextStep(he)
assert ns.StepText(he.chain[1])[0] != he.chain[1][1] or ":" not in he.chain[1][1]
click(L.eval('DUNGEON_BTN("Ragefire Chasm")'))
assert L.eval('DUNGEON_BTN("Ragefire Chasm")').active
rows = lambda: [r for r in ns.table.rows.values() if r.data and r.shown]
hrow = [r for r in rows() if r.data.q.name == he.name and not r.data.step][0]
click(hrow)  # select it
click(hrow)  # click again: its chain opens (not done, so it starts open; this folds it)
assert not any(r.data.step for r in rows() if r.data.q.name == he.name), "folded"
hrow = [r for r in rows() if r.data.q.name == he.name and not r.data.step][0]
click(hrow)  # open again
assert any("Next >" in x for x in texts()), "no next step marked"
step1 = ns.StepText(he.chain[1])[0]
assert any(step1 in x for x in texts())
steps = [r for r in rows() if r.data.q.name == he.name and r.data.step]
assert len(steps) == len(list(he.chain.values())) and steps[-1].data.index == 1, "the first step sits last (deepest)"
# a pin per row; the giver pin sets a waypoint
assert hrow.pin is not None
# right-click ticks a quest off, and a step
srow = [r for r in rows() if r.data.q.name == he.name and r.data.step and r.data.index == 2][0]
click(srow, "RightButton"); assert ns.StepState(he, he.chain[2]) == "done" and ns.NextStep(he) == 3
srow = [r for r in rows() if r.data.q.name == he.name and r.data.step and r.data.index == 2][0]
click(srow, "RightButton"); assert ns.StepState(he, he.chain[2]) != "done"
slayrow = [r for r in rows() if r.data.q.name == slay.name][0]
click(slayrow, "RightButton"); assert ns.QuestState(rfc, slay) == "done" and "Slaying the Beast" in ns.detailText.text
click([r for r in rows() if r.data.q.name == slay.name][0], "RightButton"); assert ns.QuestState(rfc, slay) == "ready"
# the giver pin of a quest with coordinates
click(L.eval('DUNGEON_BTN("Ruins of Lordaeron")'))
ljrow = [r for r in rows() if r.data.q.name == lj.name][0]
assert ljrow.pin.shown is not False
L.execute("WAYPOINT = nil"); click(ljrow.pin); assert L.eval("WAYPOINT.m") == 1458
# the filters
hd = L.eval('CHECK("Hide done")'); hd.GetScript(hd, "OnClick")(hd); assert L.eval("QuestKingDB.dqHideDone") is True
hd.GetScript(hd, "OnClick")(hd); assert L.eval("QuestKingDB.dqHideDone") is False
assert ns.StepPoint(he, he.chain[1], 1) is not None or ns.GiverPoint(he) is None
L.execute('FIRE("PLAYER_LEVEL_UP"); RUN_TIMERS()')
assert not KM.errorShown, last(L)
qk("dungeons"); assert not KM.IsShown(), "/qk dungeons toggles it closed"
print("PAGE OK")

# The crown: quick action and tooltip line; Home tile; Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Dungeon Quests") ~= nil')
L.execute('MENU_ITEM("Dungeon Quests").fn()'); assert KM.IsShown("dungeons")
L.execute('GameTooltip.lines = {}; KingMakerMinimapButton:RunScript("OnEnter")')
assert any("Dungeon quests:" in str(x) and "ready" in str(x) for x in L.eval("GameTooltip.lines").values())
KM.Show("home"); assert "DUNGEON QUESTS" in texts() and not KM.errorShown, last(L)
KM.OpenSettings("quest"); assert "Hide level 60 quests" in texts() and not KM.errorShown
print("SHELL OK")

# InitDB is safe twice and keeps the table; the 1.x button keys go
L3, KM3 = fresh(only=["Quest"], seed=NO_CLASSIC + "QuestKingDB = { marks = false, button = true, buttonAngle = 250, dqDone = { ['rfc:Slaying the Beast'] = true } }")
L3.execute("HELD = QuestKingDB"); KM3.mods.Quest.InitDB()
assert L3.eval("QuestKingDB == HELD") and L3.eval("QuestKingDB.marks") is False and L3.eval("QuestKingDB.tooltip") is True
assert L3.eval("QuestKingDB.button") is None and L3.eval("QuestKingDB.buttonAngle") is None
assert L3.eval("QuestKingDB.dqDone['rfc:Slaying the Beast']") is True
KM3.Show("dungeons"); assert not KM3.errorShown, last(L3)
print("INITDB OK")

print("quest: ok")
