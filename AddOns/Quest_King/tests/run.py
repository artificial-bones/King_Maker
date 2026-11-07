# Runs Quest King against a stand-in for the Forever client: python3 tests/run.py .
import sys
from lupa import lua51
root = sys.argv[1]
FILES = [l.strip().replace("\\", "/") for l in open(f"{root}/Quest_King.toc") if l.strip() and not l.startswith("#")]

def fresh(setup=""):
    L = lua51.LuaRuntime()
    L.execute(open(f"{root}/tests/mock.lua").read())
    L.execute(setup)
    ns = L.table()
    for fn in FILES:
        L.execute(open(f"{root}/{fn}").read(), "Quest_King", ns)
    L.execute('FIRE("ADDON_LOADED", "Quest_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
    return L

L = fresh()
qk = L.eval("SlashCmdList.QUESTKING")
def out(n=10):
    o = L.eval("OUTPUT"); return [o[i] for i in range(max(1, len(o) - n + 1), len(o) + 1)]
def marked(bag, slot, frame="ContainerFrameCombinedBags"): return L.eval(f'MARKED("{frame}", {bag}, {slot})')

L.execute("""
ITEMS = {
  [100] = {"Wolf Fang", 12},          -- objective of a quest in the log
  [101] = {"Gnoll Paw", 12},          -- leftover from a quest already turned in
  [102] = {"Sealed Letter to Ag'tor", 12}, -- delivery item named in the description
  [103] = {"Blackened Torch", 12},    -- usable quest item
  [104] = {"Torn Note", 12},          -- starts a quest you haven't done
  [105] = {"Old Map Scrap", 12},      -- starts a quest you already finished
  [106] = {"Linen Cloth", 7},         -- trade goods, never touched
  [107] = {"Mysterious Egg", 15},     -- not class Quest, but the client says it's a quest item
  [108] = {"Crumpled Page", 12},      -- starts a quest that's in your log
}
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
assert marked(0, 2) and marked(1, 2) and marked(2, 5)
assert not marked(0, 1) and not marked(1, 1) and not marked(1, 3) and not marked(0, 3)
b = L.eval('BUTTON("ContainerFrameCombinedBags", 0, 2)')
assert b.QuestKingMark.texture == "Interface\\RaidFrame\\ReadyCheck-NotReady"
print("STATUS + MARKS OK")

line = L.eval("HOVER(101)"); print(line); assert "safe to delete" in line
assert L.eval("HOVER(100)") is None and L.eval("HOVER(106)") is None
print("TOOLTIP OK")

qk(""); print("\n".join(out(4)))
o = out(4); assert "3 quest items you can delete" in o[0] and "[Gnoll Paw]" in o[1] and "x7" in o[1]
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
qk("list"); print(out(1)[0]); assert "Expand" in out(1)[0]
L.execute("LOG[1].isCollapsed = false; FIRE('QUEST_LOG_UPDATE'); RUN_TIMERS()")
assert S(0, 1) == "unneeded"
print("COLLAPSED OK")

qk("marks off"); assert not marked(0, 1); qk("marks on"); assert marked(0, 1)
qk("tooltip off"); assert L.eval("HOVER(101)") is None; qk("tooltip on")
qk("help"); assert "/qk marks" in "".join(out(3))
print("SLASH OK")

# Bag opened after the scan gets marked on show
L.execute("ContainerFrameCombinedBags:Hide(); BUTTON('ContainerFrameCombinedBags', 0, 1).QuestKingMark.shown = false; ContainerFrameCombinedBags:Show()")
assert marked(0, 1)
print("ON SHOW OK")

# Older-style bag frames (ContainerFrame1Item1.., ContainerFrame_Update) and tooltip script
L2 = fresh("""
ContainerFrameCombinedBags = nil
for i = 1, 13 do local f = _G["ContainerFrame" .. i]; f.EnumerateValidItems = false; f.UpdateItems = false end
ContainerFrame1.id = 0
for s = 1, 16 do local b = CreateFrame("Button", "ContainerFrame1Item" .. s); b.id = s end
function ContainerFrame_Update(frame) end
TooltipDataProcessor = nil
GameTooltip.HasScript = function(self, k) return k == "OnTooltipSetItem" end
GameTooltip.HookScript = function(self, k, fn) self.setItem = fn end
GameTooltip.GetItem = function() return "Gnoll Paw", LINK(101) end
ITEMS = { [101] = {"Gnoll Paw", 12} }
BAGS[0][2] = { id = 101 }
""")
L2.execute("ContainerFrame1:Show(); ContainerFrame_Update(ContainerFrame1)")
assert L2.eval("ContainerFrame1Item2.QuestKingMark.shown") == True
assert L2.eval("ContainerFrame1Item1.QuestKingMark") is None
L2.execute("GameTooltip.lines = {}; GameTooltip.setItem(GameTooltip)")
assert "safe to delete" in L2.eval("GameTooltip.lines[1]")
print("CLASSIC BAGS OK")


# ---------------------------------------------------------------- dungeon quests
UI = """
FONTS = {}
local base = CreateFrame
function CreateFrame(kind, name, parent, template)
  local f = base(kind, name, parent, template)
  local function fs()
    local t = setmetatable({}, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    function t:SetText(s) self.text = s end
    function t:GetStringHeight() return 100 end
    FONTS[#FONTS + 1] = t
    return t
  end
  f.CreateFontString = fs
  local label = fs()
  function f:GetFontString() return label end
  function f:SetText(s) label.text = s end
  function f:SetShown(v) self.shown = not not v end
  function f:GetChecked() return self.checked end
  function f:SetChecked(v) self.checked = v end
  f.CreateMaskTexture = f.CreateTexture
  return f
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
function Minimap:GetWidth() return 140 end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
LEVEL, CLASS = 16, "WARRIOR"
function UnitLevel() return LEVEL end
function UnitClass() return "Warrior", CLASS end
C_Map = {
  GetMapChildrenInfo = function(root) if root == 1414 then return { { mapID = 1454, name = "Orgrimmar" }, { mapID = 1456, name = "Thunder Bluff" },
    { mapID = 1413, name = "The Barrens" } } end if root == 1415 then return { { mapID = 1458, name = "Undercity" }, { mapID = 1420, name = "Tirisfal Glades" },
    { mapID = 1421, name = "Silverpine Forest" } } end return {} end,
  GetMapInfo = function(id) return { name = ({ [1458] = "Undercity", [1420] = "Tirisfal Glades", [1413] = "The Barrens" })[id] or "Map" } end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) WAYPOINT = p end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) TRACKED = v end }
"""
L = fresh(UI)
ns = L.eval("QuestKing")
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
L.execute("LEVEL = 8"); assert ns.QuestState(rfc, slay) == "low"; L.execute("LEVEL = 16")
f, t, n, tot = ns.BestLevels(rfc)
assert (n, tot) == (5, 5) and f == 10 and t == 20, (f, t, n, tot)
# class quests only for that class; endgame ones can be hidden
assert not any(q["class"] for q in ns.VisibleQuests(D["bfd"]).values())
L.execute('CLASS = "WARLOCK"'); assert any(q["class"] == "WARLOCK" for q in ns.VisibleQuests(D["sfk"]).values()); L.execute('CLASS = "WARRIOR"')
strat = D["strat"]; n60 = len(ns.VisibleQuests(strat))
L.execute("QuestKingDB.dqHide60 = true"); assert len(ns.VisibleQuests(strat)) < n60; L.execute("QuestKingDB.dqHide60 = false")
p = ns.Progress(rfc); assert p.total == 5 and p.done == 1 and p.ready == 4, (p.total, p.done, p.ready)
# waypoints from the log's coordinates: the last place named before them
lj = quests(rol)["Light's Justice"]
m, x, y, src = ns.GiverPoint(lj); assert (m, x, y) == (1458, 57.8, 89.7) and src == "the dungeon log", (m, x, y, src)
rath = quests(rol)["The Wrath of Rath'mael"]
assert ns.GiverPoint(rath)[0] == 1420  # "between Undercity and Brill, Tirisfal (65.2, 60.1)"
ns.WaypointToGiver(lj); assert L.eval("WAYPOINT.m") == 1458 and L.eval("TRACKED") == True
assert "Waypoint: Light's Justice, Undercity 57.8, 89.7" in L.eval("OUTPUT[#OUTPUT]"), L.eval("OUTPUT[#OUTPUT]")
ns.WaypointToGiver(slay); assert "No coordinates" in L.eval("OUTPUT[#OUTPUT]")
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
L.execute("LEVEL = 23"); assert tuple(ns.QuestXP(slay)) == (1050, 625); L.execute("LEVEL = 16")
L.execute("COMPLETED = {}; COMPLETED[5726] = true")
xp, known, total = ns.DungeonXP(rfc)
assert xp == 350 + 1150 + 400 + 1050 and known == 4, (xp, known, total)
assert "XP left" in ns.DungeonXPText(rfc) and "1,050" not in ns.DungeonXPText(rfc) and "2,950" in ns.DungeonXPText(rfc), ns.DungeonXPText(rfc)
assert ns.Commas(1234567) == "1,234,567"
# the window: both views, a click, a right-click tick
L.execute('SlashCmdList.QUESTKING("dungeons")')
assert L.eval("QuestKingDungeons.shown") == True
texts = lambda: [t.text or "" for t in L.eval("FONTS").values()]
assert any(x.startswith("Best at level") for x in texts())
assert any("Ragefire Chasm" in x for x in texts())
L.execute('SlashCmdList.QUESTKING("route")'); assert any("Start these chains early" in x for x in texts())
L.execute('QuestKingDB.dqView = "dungeons"'); ns.RefreshDungeons()
# chains inline: under the quest, last step first, the step to do next marked, a pin per step
L.execute('COMPLETED = {}; COMPLETED[5726] = true')
ns.VisibleQuests(rfc); assert ns.NextStep(he) == 2, ns.NextStep(he)
assert ns.StepText(he.chain[1])[0] != he.chain[1][1] or ":" not in he.chain[1][1]
ns.RefreshDungeons()
assert any("Next >" in x for x in texts()), "no next step marked"
step1 = ns.StepText(he.chain[1])[0]
assert any(step1 in x for x in texts())
ns.SetStepTicked(he, he.chain[2], True); assert ns.StepState(he, he.chain[2]) == "done" and ns.NextStep(he) == 3
ns.SetStepTicked(he, he.chain[2], False)
assert ns.StepPoint(he, he.chain[1], 1) is not None or ns.GiverPoint(he) is None
L.execute('FIRE("PLAYER_LEVEL_UP"); RUN_TIMERS()')
L.execute('SlashCmdList.QUESTKING("button off")'); assert L.eval("QuestKingDB.button") == False
print("DUNGEONS OK")
print("ALL TESTS PASSED")
