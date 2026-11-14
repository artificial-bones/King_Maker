# Quest (was Quest King): bag marks, the tooltip line, /qk, and Quest Gold (the 48+ quests' worth per zone for this
# character, learning Forever's real quest gold, Ask the game) and its page.
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

# Ask the game: one request per unknown quest in the zone, answers fill the gold in
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
print("QUEST GOLD LOGIC OK")


# ---------------------------------------------------------------- the Quest Gold page
def texts():
    fs = L.eval("FONTS")
    return [str(fs[i].text) for i in range(1, len(fs) + 1) if fs[i].text]


qk("gold")
assert KM.IsShown("questgold") and not KM.errorShown, last(L)
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
qk("dungeons"); assert "Quest Gold took its place" in last(L)
qk("gold"); assert not KM.IsShown(), "/qk gold toggles it closed"
print("PAGE OK")

# The crown: quick action and tooltip line; Home tile; Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Quest Gold") ~= nil') and L.eval('MENU_ITEM("Dungeon Quests") == nil')
L.execute('MENU_ITEM("Quest Gold").fn()'); assert KM.IsShown("questgold")
L.execute('GameTooltip.lines = {}; KingMakerMinimapButton:RunScript("OnEnter")')
assert any("Quest gold:" in str(x) for x in L.eval("GameTooltip.lines").values())
KM.Show("home"); assert "QUEST GOLD" in texts() and not KM.errorShown, last(L)
KM.OpenSettings("quest"); assert "Hide quests you've done" in texts() and not KM.errorShown
print("SHELL OK")

# InitDB is safe twice and keeps the table; the 1.x button keys and Dungeon Quests' keys go
L3, KM3 = fresh(only=["Quest"], seed=NO_CLASSIC + "QuestKingDB = { marks = false, button = true, buttonAngle = 250, dqDone = { ['rfc:Slaying the Beast'] = true }, dqView = 'route' }")
L3.execute("HELD = QuestKingDB"); KM3.mods.Quest.InitDB()
assert L3.eval("QuestKingDB == HELD") and L3.eval("QuestKingDB.marks") is False and L3.eval("QuestKingDB.tooltip") is True
assert L3.eval("QuestKingDB.button") is None and L3.eval("QuestKingDB.buttonAngle") is None
assert L3.eval("QuestKingDB.dqDone") is None and L3.eval("QuestKingDB.dqView") is None and L3.eval("QuestKingDB.gold") is not None
KM3.Show("questgold"); assert not KM3.errorShown, last(L3)
print("INITDB OK")

print("quest: ok")
