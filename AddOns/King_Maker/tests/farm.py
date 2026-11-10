# Farm (was Farm King), with Scanner and a stand-in QuestieDB: kill and loot attribution, empty kills, recent
# kills, values and filters, the farm tracker HUD and its timer, the Mob Farming and White Items pages (list,
# tabs, item hunt, mob page, map pins), guild sync packing, the crown's quick actions, Home tile and settings.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

EXTRA = """
-- items: name, quality, vendor price, class, bind (1 = on pickup)
ITEM(2589, "Linen Cloth", { quality = 1, sell = 13, class = 7 })
ITEM(2318, "Light Leather", { quality = 1, sell = 15, class = 7 })
ITEM(4865, "Ruined Pelt", { quality = 0, sell = 5, class = 15 })
ITEM(6000, "Green Sword", { quality = 2, sell = 500, class = 2 })
ITEM(7000, "Soulbound Ring", { quality = 3, sell = 900, class = 4, bind = 1 })
ITEM(5000, "Quest Fang", { quality = 1, sell = 0, class = 12 })
ITEM(8000, "Rare Gem", { quality = 3, sell = 100, class = 7 })
PLAYER.map, PLAYER.x, PLAYER.y, PLAYER.level = 1429, 0.45, 0.62, 20
function G(npc, n) return "Creature-0-1-2-3-" .. npc .. "-" .. n end
-- You fight a mob (it has you on its threat list), then it dies on its nameplate.
function KILL(guid, name)
  UNITS.nameplate1 = { guid = guid, name = name, level = 2 }
  THREAT["player" .. guid] = 1; FIRE("UNIT_THREAT_LIST_UPDATE", "nameplate1"); THREAT["player" .. guid] = nil
  UNITS.nameplate1.dead = true; FIRE("UNIT_HEALTH", "nameplate1"); FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate1")
  UNITS.nameplate1 = nil
end
-- A loot window: { { link or nil (coin), qty, { guid, qty, guid, qty } }, ... }
function FLOOT(window)
  local slots = {}
  for i, w in ipairs(window) do slots[i] = { link = w[1], qty = w[2], sources = w[3] } end
  OPEN_LOOT(slots)
end
-- Finders: a KM.UI button by its label, a check by its label, a sidebar entry, the search box.
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function BTNS(text) local r = {} for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then r[#r+1] = f end end return r end
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetChecked and rawget(f, "mark") then return f end end end
function SIDE(text) for _, f in ipairs(FRAMES) do if rawget(f, "entry") and f.shown ~= false and f.label.text and f.label.text:find(text, 1, true) then return f end end end
function SEARCHBOX() for _, f in ipairs(FRAMES) do if type(rawget(f, "hint")) == "table" and f.hint.text and f.hint.text:find("^Search") and f.SetAutoFocus then return f end end end
function TYPE(text) local e = SEARCHBOX(); e:SetText(text); e.scripts.OnTextChanged(e, true) end
"""

QUESTIE = """
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
"""


def load(questie=False, **kw):
    L, KM = fresh(only=["Scanner", "Farm"], extra=EXTRA + (QUESTIE if questie else ""), **kw)
    return L, KM, KM.mods.Farm


def texts(L):
    return list(L.eval("TEXTS()").values())


def ids(ns):
    return [e.id for e in ns.CurrentList().values()]


def row(ns, mode, id_):
    for r in ns.tables[mode].rows.values():
        if r.data and r.data.id == id_ and r.shown != False:
            return r


def mobs(L): return L.eval("FarmKingDB.mobs")


# ---------------------------------------------------------------- without QuestieDB
L, KM, ns = load()
fk = L.eval("SlashCmdList.FARMKING")
assert not ns.QuestieAvailable()
assert L.eval("FarmKing.API_VERSION") == 1
assert L.eval("FarmKingMinimapButton") is None and L.eval("FarmKingFrame") is None, "no window or button of its own"
assert L.eval("FarmKingDB.ui.button") is None
# nothing touches the combat log, which gets an addon blocked on Forever
assert not any(f.events["COMBAT_LOG_EVENT_UNFILTERED"] for f in L.eval("FRAMES").values())
# seeing a mob
L.execute('UNITS.target = { guid = G(299, 1), name = "Young Wolf", level = 2 }; FIRE("PLAYER_TARGET_CHANGED")')
m = mobs(L)[299]; assert m.name == "Young Wolf" and m.lmin == 2 and m.k == 0 and m.z[1429] == 1 and m.p[1] == "1429:0.450:0.620"
# kill and loot it: a pelt, two leather, 5 silver
L.execute('KILL(G(299, 1), "Young Wolf"); LOOTABLE[G(299, 1)] = true; RUN_TIMERS()')
assert mobs(L)[299].k == 0  # it has loot: counts when opened
L.execute('FLOOT({ { "|Hitem:4865:0|h", 1, { G(299, 1), 1 } }, { "|Hitem:2318:0|h", 2, { G(299, 1), 2 } }, { nil, 0, { G(299, 1), 500 } } })')
m = mobs(L)[299]; assert m.k == 1 and m.c == 500 and m.i[4865][1] == 1 and m.i[2318][2] == 2
# opening it again (or skinning it) changes nothing
L.execute('FLOOT({ { "|Hitem:2318:0|h", 3, { G(299, 1), 3 } } })'); assert mobs(L)[299].k == 1 and mobs(L)[299].i[2318][2] == 2
# looting two corpses in one window: each item goes to its own corpse
L.execute('FLOOT({ { "|Hitem:2318:0|h", 3, { G(299, 2), 1, G(299, 3), 2 } }, { nil, 0, { G(299, 2), 300, G(299, 3), 100 } } })')
m = mobs(L)[299]; assert m.k == 3 and m.c == 900 and m.i[2318][1] == 3 and m.i[2318][2] == 5
# a kill with nothing to loot counts (solo)
L.execute('KILL(G(299, 4), "Young Wolf"); RUN_TIMERS()'); assert mobs(L)[299].k == 4
# ...but not in a group, where someone else may have the loot
L.execute('GROUP = true; KILL(G(299, 5), "Young Wolf"); RUN_TIMERS(); GROUP = false'); assert mobs(L)[299].k == 4
# fishing and gathering nodes are ignored
L.execute('FISHING = true; FLOOT({ { "|Hitem:2589:0|h", 1, { G(299, 9), 1 } } }); FISHING = false')
L.execute('FLOOT({ { "|Hitem:2589:0|h", 1, { "GameObject-0-1-2-3-1731-9", 1 } } })')
assert mobs(L)[299].k == 4 and mobs(L)[1731] is None
# a split stack from one corpse is one drop
L.execute('FLOOT({ { "|Hitem:2589:0|h", 20, { G(113, 1), 20 } }, { "|Hitem:2589:0|h", 5, { G(113, 1), 5 } } })')
m = mobs(L)[113]; assert m.k == 1 and m.i[2589][1] == 1 and m.i[2589][2] == 25
# skinning a corpse you never looted (someone else's kill) adds nothing
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8617); FLOOT({ { "|Hitem:2318:0|h", 1, { G(299, 50), 1 } } })')
assert mobs(L)[299].k == 4 and mobs(L)[299].i[2318][2] == 5
L.execute("GetTime = function() return 100 end")  # time moves on
# a mob someone else tagged isn't an empty kill of yours
L.execute('UNITS.target = { guid = G(299, 60), name = "Young Wolf", level = 2 }; UnitIsTapDenied = function() return true end; FIRE("PLAYER_TARGET_CHANGED")')
L.execute('KILL(G(299, 60), "Young Wolf"); RUN_TIMERS(); UnitIsTapDenied = function() return false end'); assert mobs(L)[299].k == 4
# counted as empty, then it turns out to have loot: the loot is added, the kill isn't counted again
L.execute('KILL(G(299, 61), "Young Wolf"); RUN_TIMERS()'); assert mobs(L)[299].k == 5
L.execute('FLOOT({ { nil, 0, { G(299, 61), 40 } } })'); assert mobs(L)[299].k == 5 and mobs(L)[299].c == 940
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
gpk, gk = L.eval("FarmKing.GoldPerKill(299)"); assert abs(gpk - v.gold) < 1e-9 and gk == 6
# filters: no coin, no grey
L.execute("FarmKingDB.filter.coin = false; FarmKingDB.filter.q0 = false")
assert abs(ns.Value(299).gold - 5 / 6 * 114) < 1e-6
L.execute("FarmKingDB.filter.coin = true; FarmKingDB.filter.q0 = true")
print("VALUE OK")

# The farm tracker HUD: this session's kills, drops, coin, total; gold per hour while the timer runs
fk("mini")
mini = ns.miniFrame
assert mini is not None and mini.shown and L.eval("FarmKingDB.ui.mini") is True and L.eval("FarmKingMini.shown")
assert mini.collapse and mini.close and mini.body, "a UI.HUD: collapse, close, body"
t = texts(L)
assert "Kills: 8" in t, t  # 6 wolves, 2 boars
assert "Young Wolf x6" in t and "Stonetusk Boar x2" in t, t
assert any("Light Leather|r x5" in x for x in t) and "Coin" in t and "Total" in t, t
total, gph, secs = ns.SessionTotals()
assert abs(total - (940 + 5 * 114 + 5 + 25 * 13)) < 1e-6 and gph is None, total
# the timer: only loot taken while it runs counts toward gold per hour
L.execute('GetTime = function() return 200 end')
L.execute('BTN("Start timer"):Click()')
assert L.eval("FarmKingDB.session.timer.running") is True and L.eval('BTN("Pause timer")') is not None
L.execute('GetTime = function() return 200 + 1800 end')
L.execute('KILL(G(299, 64), "Young Wolf"); LOOTABLE[G(299, 64)] = true; FLOOT({ { nil, 0, { G(299, 64), 10000 } } }); RUN_TIMERS()')
total, gph, secs = ns.SessionTotals()
assert secs == 1800 and abs(gph - 20000) < 1e-6, (secs, gph)  # 1 gold in half an hour
L.execute("RUN_ONUPDATE(1)")
assert L.eval("FarmKingDB.session.timer.last") == 1800
L.execute('FIRE("PLAYER_LOGIN")')  # a /reload pauses it, keeping its time
assert L.eval("FarmKingDB.session.timer.running") == False and ns.SessionTotals()[2] == 1800
# collapse shows gold per hour in the title; the position is kept in ui.miniPos (the 1.x shape)
L.execute("FarmKingMini.collapse:Click()")
assert L.eval("FarmKingDB.ui.miniCollapsed") is True and mini.collapsed
assert mini.title.text.startswith("Farm tracker  ") and "/hr" in mini.title.text, mini.title.text
L.execute("FarmKingMini.collapse:Click()")
assert not L.eval("FarmKingDB.ui.miniCollapsed") and mini.title.text == "Farm tracker"
L.execute('FarmKingMini:ClearAllPoints(); FarmKingMini:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -60); FarmKingMini.scripts.OnDragStop(FarmKingMini)')
assert list(L.eval("FarmKingDB.ui.miniPos").values()) == ["TOPLEFT", "TOPLEFT", 50, -60]
L.execute('BTN("Reset"):Click(); RUN_TIMERS()')
assert L.eval("POPUPS[#POPUPS].name") == "FARMKING_CONFIRM"
assert ns.SessionTotals()[0] == 0 and "Nothing killed yet" in "".join(texts(L))
# x closes it (and turns it off)
L.execute("FarmKingMini.close:Click()")
assert not mini.shown and L.eval("FarmKingDB.ui.mini") is False
fk("mini on"); assert mini.shown
fk("mini off"); assert not mini.shown
print("MINI OK")

# The Mob Farming page without QuestieDB: mobs you've seen; Best farms needs enough kills
fk("")
assert KM.IsShown("mobs") and not KM.errorShown, last(L)
assert any("No QuestieDB: mobs you've seen." in x for x in texts(L)) and L.eval('BTN("Min kills: 5")') is not None
assert ids(ns) == [299]  # the only mob with 5+ kills
assert row(ns, "mobs", 299) is not None
L.execute("FarmKingDB.filter.minKills = 10"); KM.Refresh()
assert ids(ns) == [] and "No mob has 10+ kills" in ns.tables.mobs.empty.text
for label in ("Min kills: 10", "Min kills: 25", "Min kills: 50"):
    L.execute('BTN("%s"):Click()' % label)
assert L.eval("FarmKingDB.filter.minKills") == 1
assert sorted(ids(ns)) == [113, 299], ids(ns)
b = L.eval('SIDE("Elwynn Forest")'); assert b and b.count.text == "2"
L.execute('SIDE("All mobs"):Click()'); assert len(ids(ns)) == 2
assert L.eval('SIDE("All mobs")').active, "the open tab is highlighted"
# the filter checks write the filter
L.execute('CHECK("Coin"):Click()'); assert L.eval("FarmKingDB.filter.coin") is False
L.execute('CHECK("Coin"):Click()'); assert L.eval("FarmKingDB.filter.coin") is True
# sorting by a column header
ns.tables.mobs.headers["kills"].scripts.OnClick(ns.tables.mobs.headers["kills"])
assert ids(ns) == [299, 113], ids(ns)  # 7 wolf kills, 2 boar kills, most first
ns.tables.mobs.headers["kills"].scripts.OnClick(ns.tables.mobs.headers["kills"])
assert ids(ns) == [113, 299], ids(ns)
# right-click: favorite
row(ns, "mobs", 113).Click(row(ns, "mobs", 113), "RightButton")
assert L.eval("FarmKingDB.fav[113]") is True
L.execute('SIDE("Favorites"):Click()'); assert ids(ns) == [113]
# Recent kills: the latest first
L.execute('SIDE("Recent kills"):Click()'); assert ids(ns) == [299, 113]
L.execute('KILL(G(113, 3), "Stonetusk Boar"); RUN_TIMERS()'); assert ids(ns) == [113, 299]
L.execute('SIDE("All mobs"):Click()')
# a mob's page, inside the window
r = row(ns, "mobs", 299); r.Click(r, "LeftButton")
assert ns.CurrentMob() == 299
t = texts(L)
assert "Young Wolf" in t and "GOLD PER KILL" in t and "< Back" in t and "Track on map" in t and "Light Leather" in "".join(t), t
assert "Seen at 9 spots." in t, [x for x in t if "spot" in x]
assert "Favorite" in "".join(t)
# track it: pins on the world map from where it was seen
L.execute('CHECK("Track on map"):Click()')
assert L.eval("FarmKingDB.track[299]")
pins = L.eval("(function() local n = 0 for _, f in ipairs(FRAMES) do if f.mob == 299 and f.shown then n = n + 1 end end return n end)()")
assert pins == 9, pins  # two sightings, seven kills
L.execute('BTN("< Back"):Click()')
assert ns.CurrentMob() is None and len(ids(ns)) == 2
L.execute('SIDE("Tracked on map"):Click()'); assert ids(ns) == [299]
L.execute('SIDE("All mobs"):Click()')
print("UI OK")

# Guild: ask, answer, and add a guildmate's kills without double counting
L.execute("SENT = {}")
L.execute('local b = BTNS("Ask guild"); b[#b]:Click(); RUN_TIMERS()')   # the list's (the mob page has its own)
req = [L.eval("SENT")[i].text for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].prefix == "FarmKing1"]
assert len(req) == 1 and req[0][0] == "R" and list(ns.Unpack(req[0][1:]).values()) == [113, 299 - 113], req
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
assert any("Got drop data for 1 mob(s) from Bob." in o for o in outputs(L))
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
fk("share off"); L.execute("SENT = {}")
L.execute('FIRE("CHAT_MSG_ADDON", "FarmKing1", "' + req[0] + '", "GUILD", "Amy-Realm"); RUN_TIMERS()')
assert len([1 for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].prefix == "FarmKing1"]) == 0
fk("share on"); assert L.eval("FarmKingDB.answer") is True
# /fk forget guild
fk("forget guild"); assert L.eval("next(FarmKingDB.guild)") is None and "Forgot" in last(L)
print("GUILD OK")

# The crown: quick actions, tooltip line; Home tile; Settings section; slash leftovers
L.execute('KingMakerMinimapButton:Click("RightButton")')
for label in ("Mob Farming", "This zone's mobs", "Farm tracker"):
    assert L.eval('MENU_ITEM("%s") ~= nil' % label), label
L.execute('MENU_ITEM("Farm tracker").fn()'); assert mini.shown and L.eval("FarmKingDB.ui.mini") is True
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("Farm tracker").fn()'); assert not mini.shown
KM.Show("home")
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("This zone\'s mobs").fn()')
assert KM.CurrentPage() == "mobs" and L.eval('SIDE("This zone")').active
assert sorted(ids(ns)) == [113, 299]  # both seen in Elwynn
L.execute('KingMakerMinimapButton.scripts.OnEnter(KingMakerMinimapButton)')
assert any("kills recorded." in str(x) for x in L.eval("GameTooltip.lines").values())
KM.Show("home")
assert "FARM SESSION" in texts(L), "a session exists: the Home tile shows it"
KM.OpenSettings("farm")
assert not KM.errorShown, last(L)
t = texts(L); assert "Show the farm tracker" in t and "Forget every guildmate's drop data" in t
fk("button"); assert "/km button" in last(L)
fk("status"); assert "mobs seen" in last(L)
fk("help"); assert any("/fk mini" in o for o in outputs(L))
fk("white"); assert KM.CurrentPage() == "whites"
fk("mob 299"); assert KM.CurrentPage() == "mobs" and ns.CurrentMob() == 299
assert not KM.errorShown, last(L)
print("SHELL OK")

# ---------------------------------------------------------------- with QuestieDB
L, KM, ns = load(questie=True)
fk = L.eval("SlashCmdList.FARMKING")
assert ns.QuestieAvailable() and not ns.QuestieReady()
fk("")
L.execute("RUN_TIMERS()")
assert ns.QuestieReady()
qm = ns.QuestieMobs()
assert qm[299] and qm[113] and qm[500] and not qm[600] and not qm[700] and not qm[1]  # hostile mobs only
assert list(ns.QuestieDrops(299).values()) == [2318] and sorted(ns.QuestieDrops(500).values()) == [2589, 8000]
info = ns.MobInfo(500); assert info.name == "Riverpaw Gnoll" and info.lmin == 10 and info.rank == "elite" and info.map == 1436
L.execute("FarmKingDB.filter.minKills = 1")
L.execute('SIDE("All mobs"):Click()')
assert sorted(ids(ns)) == [113, 299, 500]
L.execute('SIDE("Westfall"):Click()'); assert ids(ns) == [500]
assert any("QuestieDB: every mob." in x for x in texts(L))
# the gnoll's page lists drops nobody has seen yet, and its spawn points come from QuestieDB
r = row(ns, "mobs", 500); r.Click(r, "LeftButton")
t = texts(L)
assert "Riverpaw Gnoll |cffffd100(elite)|r" in t and "1 spawn points from QuestieDB." in t, t
assert t.count("|cff808080not seen|r") == 2
spots = ns.Spots(500)[0]; assert spots[1][1] == 1436 and abs(spots[1][2] - 0.3) < 1e-9
# killing a QuestieDB mob you've never targeted still works
L.execute('FLOOT({ { "|Hitem:8000:0|h", 1, { G(500, 1), 1 } } })')
assert mobs(L)[500].k == 1 and ns.Value(500).kills == 1
print("QUESTIEDB OK")

# Hunting an item: search items, pick one, every mob that drops it, highest level first
L.execute('KILL(G(299, 70), "Young Wolf"); LOOTABLE[G(299, 70)] = true; FLOOT({ { "|Hitem:2318:0|h", 1, { G(299, 70), 1 } } })')
L.execute('BTN("< Back"):Click()')
L.execute('BTN("Mobs"):Click()')
assert L.eval('BTN("Items")') is not None and ns.CurrentMode() == "mobs"
L.execute('TYPE("leather")')
assert ns.CurrentMode() == "items" and ids(ns) == [2318], ids(ns)
t = texts(L); assert "DROPPED BY" in t and "BEST CHANCE" in t
assert any("Light Leather" in x for x in t) and "2" in t and "100%" in t, t
L.execute("SEARCHBOX():SetText('')")
r = row(ns, "items", 2318); r.Click(r, "LeftButton")
assert ns.CurrentMode() == "hunt" and ids(ns) == [113, 299], ids(ns)  # boar (5-6) above wolf (1-2)
t = texts(L); assert "SPAWNS" in t and "CHANCE" in t
assert any("dropped by 2 mobs, levels 1-6, 3 spawn points" in x for x in t), [x for x in t if "dropped" in x]
# its mob page, then back to the hunt
r = row(ns, "hunt", 299); r.Click(r, "LeftButton"); assert "Young Wolf" in texts(L) and ns.CurrentMob() == 299
L.execute('BTN("< Back"):Click()'); assert ids(ns) == [113, 299]
# a shift-clicked link in the search box hunts that item
L.execute("TYPE('|Hitem:8000::|h[Rare Gem]|h')")
assert ids(ns) == [500]
# other modules (Econ) open it straight on an item
KM.Toggle(False)
L.eval("FarmKing").ShowItem(2318); assert KM.IsShown("mobs") and ids(ns) == [113, 299]
# a tab goes back to mobs
L.execute('SIDE("All mobs"):Click()'); assert len(ids(ns)) == 3
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
KM.Show("whites")
assert not KM.errorShown, last(L)
t = texts(L); assert "BEST CHANCE" in t and any("Score: price x square root" in x for x in t) and any("Linen Cloth" in x for x in t), t
assert [e.id for e in ns.WhiteList().values()] == [2589, 2318]
wrow = None
for r_ in ns.whiteTable.rows.values():
    if r_.data and r_.data.id == 2318: wrow = r_
assert wrow and wrow.cells.score.text == "|cffffd100" + str(w[1].score) + "|r"
# sort by price, cheapest first after a second click
ns.whiteTable.headers["price"].scripts.OnClick(ns.whiteTable.headers["price"])
assert [e.id for e in ns.WhiteList().values()] == [2589, 2318]
ns.whiteTable.headers["price"].scripts.OnClick(ns.whiteTable.headers["price"])
assert [e.id for e in ns.WhiteList().values()] == [2318, 2589]
# click an item: every mob that drops it, on the Mob Farming page; click a mob: its page
for r_ in ns.whiteTable.rows.values():
    if r_.data and r_.data.id == 2318: wrow = r_
wrow.Click(wrow, "LeftButton")
assert KM.CurrentPage() == "mobs" and ids(ns) == [113, 299]
r = row(ns, "hunt", 299); r.Click(r, "LeftButton"); assert "Young Wolf" in texts(L)
KM.Show("whites"); assert any("Score: price x square root" in x for x in texts(L))
assert L.eval("FarmKing.IsDrop(2318)") and not L.eval("FarmKing.IsDrop(12345)")
print("WHITE OK")

# Moving 1.x data in from a Farm_King stub folder: the shape is kept, the old button settings go
OLD = ("FarmKingDB = { mobs = { [299] = { k = 3, c = 90, i = { [2318] = { 1, 2 } }, z = {}, p = {}, name = 'Young Wolf' } }, "
       "ui = { button = true, buttonAngle = 115, mini = true, miniPos = { 'CENTER', 'CENTER', 10, 20 } }, filter = { minKills = 10 } }")
L, KM, ns = load(stubs={"Farm_King": OLD})
assert L.eval("KingMakerDB.moved.FarmKingDB") is not None
assert L.eval("FarmKingDB.mobs[299].k") == 3 and L.eval("FarmKingDB.filter.minKills") == 10 and L.eval("FarmKingDB.filter.q0") is True
assert L.eval("FarmKingDB.ui.button") is None and L.eval("FarmKingDB.ui.buttonAngle") is None
assert ns.db.mobs[299].k == 3 and ns.Value(299).kills == 3
L.execute('FIRE("PLAYER_LOGIN")')   # the tracker was on in 1.x: it comes back where it was
mini = L.eval("FarmKingMini")
assert mini and mini.shown and mini.points[1][1] == "CENTER" and mini.points[1][4] == 10
print("MIGRATION OK")

print("farm: ok")
