# Farm Tracker (King Maker 2.6), with Scanner, Farm, Gather and Econ: the loot reader (Core\Loot.lua), crediting,
# coin, classification, values, the clock, idle and AFK, auto-start, stop/split/discard, /reload, cash, the
# timeline, retention, the move from the two old boxes, the HUD, /farm, the crown, Home, settings, key bindings,
# the TrackerKing API, and the Farming Ledger page.
import os, sys, re; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
from km import fresh, last, outputs, open_every_page, ROOT

EXTRA = """
ITEM(2318, "Light Leather", { quality = 1, sell = 15, class = 7 })
ITEM(4865, "Ruined Pelt", { quality = 0, sell = 5, class = 15 })
ITEM(5000, "Quest Fang", { quality = 1, sell = 0, class = 12 })
ITEM(7000, "Soulbound Ring", { quality = 3, sell = 900, class = 4, bind = 1 })
ITEM(2770, "Copper Ore", { quality = 1, sell = 5, class = 7 })
ITEM(2447, "Peacebloom", { quality = 1, sell = 4, class = 7 })
ITEM(6358, "Oily Blackmouth", { quality = 1, sell = 1, class = 7 })
ITEM(16882, "Battered Junkbox", { quality = 1, sell = 0, class = 15 })
ITEM(10940, "Strange Dust", { quality = 1, sell = 10, class = 7 })
ITEM(9998, "New Forever Herb", { quality = 1, sell = 0, class = 7 })
PLAYER.map, PLAYER.level = 1429, 30
function G(npc, n) return "Creature-0-1-2-3-" .. npc .. "-" .. n end
function OBJ(id, n) return "GameObject-0-1-2-3-" .. id .. "-" .. n end
function IGUID(n) return "Item-0-1-2-3-" .. n end
-- A loot window: { { link or nil (coin), qty, { guid, qty, ... }, locked = bool, quest = bool }, ... }
function WIN(window, fromItem)
  local slots = {}
  for i, w in ipairs(window) do slots[i] = { link = w[1], qty = w[2], sources = w[3], locked = w.locked, quest = w.quest, quality = w.quality } end
  OPEN_LOOT(slots, nil, fromItem)
end
function L_(id) return "|Hitem:" .. id .. ":0|h" end
function CAST(id, target) if target then FIRE("UNIT_SPELLCAST_SENT", "player", target, "c", id) end FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "c", id) end
function UNDER(f, root) while f do if f == root then return true end f = f.parent end return false end
function BTN(text, root) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel and (not root or UNDER(f, root)) then return f end end end
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetChecked and rawget(f, "mark") then return f end end end
"""

ONLY = ["Scanner", "Farm", "Gather", "Tracker", "Econ"]
ME = "Jay-Forever"


def load(**kw):
    L, KM = fresh(only=kw.pop("only", ONLY), extra=EXTRA + kw.pop("extra", ""), **kw)
    return L, KM, KM.mods.Tracker


def live(L):
    return L.eval("TrackerKingDB.live['%s']" % ME)


def texts(L):
    return [str(x) for x in L.eval("TEXTS()").values()]


def run(L, code):
    L.execute(code + "; RUN_TIMERS()")


def money(L, d):
    run(L, "SET_MONEY(MONEY + %d)" % d)


# ---------------------------------------------------------------- 1. loads, guards, defaults
L, KM, ns = load()
assert not KM.errorShown, last(L)
assert not any(f.events["COMBAT_LOG_EVENT_UNFILTERED"] for f in L.eval("FRAMES").values()), "never the combat log"
assert L.eval("TrackerKing.API_VERSION") == 1 and L.eval("TrackerKing.State()") == "idle"
db = L.eval("TrackerKingDB")
assert db.version == 1 and db.nextId == 1 and db.settings.autoStart is True and db.settings.startActions == 3
assert db.settings.idlePause == 300 and db.settings.idleStop == 1200 and db.settings.offlineStop == 7200 and db.settings.minKeep == 120
assert db.settings.countQuest is False and db.settings.countDE is False and db.settings.countShares is True and db.settings.hudOnStart is True
assert db.settings.keep == 200 and db.settings.detailDays == 45 and db.ui.hud is False and db.ui.hudTab == "all" and db.ui.priceTab == "mine"
assert L.eval("KingMakerFarmTracker") is None, "nobody had an old box on: no tracker until a session starts"
L.execute("HELD = TrackerKingDB")
ns.InitDB(); ns.InitDB()
assert L.eval("HELD == TrackerKingDB") and L.eval("#TrackerKingDB.sessions") == 0, "InitDB twice is harmless"
# an optional event the client doesn't know: the guard keeps it loading, and slots count at open without LOOT_SLOT_CLEARED
L2, KM2, ns2 = load(extra="UNKNOWN_EVENTS.LOOT_SLOT_CLEARED = true; UNKNOWN_EVENTS.PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true")
assert not KM2.errorShown, last(L2)
L2.eval("SlashCmdList.KINGMAKERFARM")("start")
run(L2, 'WIN({ { L_(2318), 2, { G(299, 1), 2 } } })')
assert L2.eval("TrackerKingDB.live['%s'].src.mob.i[2318]" % ME) == 2, "no LOOT_SLOT_CLEARED: credited at open"
print("LOAD OK")

# ---------------------------------------------------------------- 3. the move from the two old boxes
OLD_F = ("FarmKingDB = { mobs = {}, session = { mobs = { [299] = { k = 3, c = 90, i = { [2318] = 4 } } }, items = { [2318] = 4 }, coin = 90, "
         "timer = { elapsed = 600, last = 600 } }, ui = { mini = true, miniPos = { 'TOPLEFT', 'TOPLEFT', 50, -60 }, miniCollapsed = false } }")
OLD_G = ("GatherKingDB = { version = 3, nodes = {}, ledger = { items = { [2447] = 7, [2770] = 5, [16882] = 1 }, timed = {}, timer = { elapsed = 300 } }, "
         "ui = { ledger = true, ledgerPos = { 'TOP', 'TOP', 5, -5 }, priceTab = 'herb', ledgerTab = 'prices' } }")
L, KM, ns = load(seed=OLD_F + "; " + OLD_G)
assert not KM.errorShown, last(L)
assert L.eval("#TrackerKingDB.sessions") == 1
s = L.eval("TrackerKingDB.sessions[1]")
assert s.legacy is True and s.auto is None and s.name == "Carried over from the old trackers" and s.c == ME
assert s.mobs[299].k == 3 and s.mobs[299].c == 90 and s.src.mob.i[2318] == 4 and s.kills == 3
assert s.src.herb.i[2447] == 7 and s.src.mine.i[2770] == 5 and s.src.chest.i[16882] == 1, "gathering filed by Gather's lists"
assert s.act == 600 and s.t0 == s.t1 - 600 and s.state is None and s.tl is None
assert s.coin == 90 and s.value == 90 + 4 * 15 + 7 * 4 + 5 * 5, s.value   # valued at today's prices (vendor here)
hud = L.eval("KingMakerFarmTracker")
assert hud and hud.shown and hud.points[1][1] == "TOPLEFT" and hud.points[1][4] == 50, "shown where the farm tracker box was"
assert L.eval("TrackerKingDB.ui.hud") is True and L.eval("TrackerKingDB.ui.priceTab") == "herb"
for path in ["FarmKingDB.session", "FarmKingDB.ui.mini", "FarmKingDB.ui.miniPos", "GatherKingDB.ledger", "GatherKingDB.ui.ledger",
             "GatherKingDB.ui.ledgerPos", "GatherKingDB.ui.priceTab", "GatherKingDB.ui.ledgerTab"]:
    assert L.eval(path) is None, path
assert any("one |cfff0c44dFarm Tracker|r now" in o for o in outputs(L)), outputs(L)
assert L.eval("TrackerKingDB.migrated.farm") is not None
run(L, 'FIRE("PLAYER_LOGIN")'); ns.InitDB()
assert L.eval("#TrackerKingDB.sessions") == 1, "the second login adds nothing"
# only the gather box was on: the tracker shows where it was
L, KM, ns = load(seed=OLD_G)
hud = L.eval("KingMakerFarmTracker"); assert hud and hud.shown and hud.points[1][1] == "TOP"
# both boxes off: no tracker, but the data still moves
L, KM, ns = load(seed=OLD_G.replace("ledger = true", "ledger = false"))
assert L.eval("TrackerKingDB.ui.hud") is False and L.eval("#TrackerKingDB.sessions") == 1
# the stub path: Farm_King's data arrives after King Maker's ADDON_LOADED and moves at PLAYER_LOGIN
L, KM, ns = load(stubs={"Farm_King": OLD_F})
assert L.eval("KingMakerDB.moved.FarmKingDB") is not None and L.eval("FarmKingDB.session") is None
assert L.eval("#TrackerKingDB.sessions") == 1 and L.eval("TrackerKingDB.sessions[1].mobs[299].k") == 3
assert L.eval("KingMakerFarmTracker.shown")
print("MIGRATION OK")

# ---------------------------------------------------------------- 4/5. crediting and coin
L, KM, ns = load()
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("start")
assert L.eval("TrackerKing.State()") == "running" and live(L).auto is None and live(L).gold0 == L.eval("MONEY")
assert L.eval("KingMakerFarmTracker.shown"), "a session started: the tracker shows (hudOnStart)"
# Farm's kill detection: a wolf you fought dies; its corpse has loot
L.execute('KILL = function(guid, name) UNITS.nameplate1 = { guid = guid, name = name, level = 2 }; THREAT["player" .. guid] = 1; '
          'FIRE("UNIT_THREAT_LIST_UPDATE", "nameplate1"); THREAT["player" .. guid] = nil; UNITS.nameplate1.dead = true; '
          'FIRE("UNIT_HEALTH", "nameplate1"); UNITS.nameplate1 = nil end')
run(L, 'KILL(G(299, 1), "Young Wolf"); LOOTABLE[G(299, 1)] = true')
run(L, 'WIN({ { L_(2318), 2, { G(299, 1), 2 } }, { L_(4865), 1, { G(299, 1), 1 }, locked = true }, { nil, 0, { G(299, 1), 500 } } })')
assert live(L).kills == 1 and live(L).mobs[299].k == 1, "the kill counts once (Farm counts it when the corpse opens)"
assert live(L).src.mob.i[2318] is None, "nothing counts until you take it"
money(L, 500)
run(L, "LOOT_ALL()")
s = live(L)
assert s.src.mob.i[2318] == 2 and s.src.mob.i[4865] is None, "only cleared slots count; locked (rolled) ones never do"
assert s.mobs[299].c == 500 and s.coin == 500 and s.mobs[299].v == 30 and s.value == 530 and s.src.mob.n == 1
assert L.eval("FarmKingDB.mobs[299].k") == 1, "Farm's own tally still counts"
# re-opening a corpse later (bags were full) credits the slots taken then
run(L, 'WIN({ { L_(2318), 1, { G(299, 2), 1 } }, { L_(10940), 3, { G(299, 2), 3 } } }); FIRE("LOOT_SLOT_CLEARED", 1); CLOSE_LOOT()')
assert live(L).src.mob.i[2318] == 3 and live(L).src.mob.i[10940] is None
run(L, 'WIN({ { L_(10940), 3, { G(299, 2), 3 } } }); LOOT_ALL()')
assert live(L).src.mob.i[10940] == 3 and live(L).src.mob.n == 2, "a re-opened corpse isn't a second corpse"
# AoE loot: one window, two corpses, split per corpse
run(L, 'WIN({ { L_(2318), 3, { G(299, 3), 1, G(113, 1), 2 } } }); LOOT_ALL()')
assert live(L).mobs[113].i[2318] == 2 and live(L).mobs[299].i[2318] == 4
# coin: grouped, the smaller share that arrives wins; with no PLAYER_MONEY the slot amount is the fallback
L.execute("GROUP = true")
c0 = live(L).coin
run(L, 'WIN({ { nil, 0, { G(299, 4), 1000 } } })'); money(L, 250); run(L, "LOOT_ALL()")
assert live(L).coin == c0 + 250 and live(L).mobs[299].c == 750, live(L).coin
run(L, 'WIN({ { nil, 0, { G(299, 5), 400 } } }); LOOT_ALL()')
assert live(L).coin == c0 + 650, "no money arrived: the slot's 400"
money(L, 77)
assert live(L).src.share.c == 77 and live(L).coin == c0 + 727, "a gain with nothing open while grouped is a party share"
L.execute("GROUP = false")
money(L, 33)
assert live(L).cash.other == 33 and live(L).coin == c0 + 727, "solo, unexplained money is 'other', not farmed"
print("CREDIT OK")

# ---------------------------------------------------------------- 6. classification
L.execute("ADVANCE(4)")
run(L, 'CAST(8613); WIN({ { L_(2318), 2, { G(299, 9), 2 } } }); LOOT_ALL(); ADVANCE(4)')
s = live(L); assert s.src.skin.i[2318] == 2 and s.mobs[299].sv == 30 and s.mobs[299].sn == 1 and s.src.skin.n == 1
run(L, 'CAST(921); WIN({ { L_(16882), 1, { G(500, 1), 1 } }, { nil, 0, { G(500, 1), 120 } } }); LOOT_ALL(); ADVANCE(4)')
assert live(L).src.pick.i[16882] == 1 and live(L).src.pick.c == 120 and live(L).src.pick.n == 1
run(L, 'CAST(2575, "Copper Vein"); WIN({ { L_(2770), 3, { OBJ(1731, 1), 3 } } }); LOOT_ALL(); ADVANCE(4)')
assert live(L).src.mine.i[2770] == 3 and live(L).nodes["Copper Vein"] == 1 and live(L).src.mine.n == 1
run(L, 'CAST(2366); WIN({ { L_(2447), 2, { OBJ(1617, 1), 2 } } }); LOOT_ALL(); ADVANCE(4)')
assert live(L).src.herb.i[2447] == 2
run(L, 'FISHING = true; WIN({ { L_(6358), 1, { OBJ(0, 0), 1 } } }); LOOT_ALL(); FISHING = false')
assert live(L).src.fish.i[6358] == 1 and live(L).src.fish.n == 1
run(L, 'WIN({ { L_(10940), 1, { OBJ(2843, 1), 1 } } }); LOOT_ALL()')
assert live(L).src.chest.i[10940] == 1, "an object with no gathering cast is a chest"
run(L, 'WIN({ { L_(2318), 1, { "Player-1-AAA", 1 } } }, true); LOOT_ALL()')
assert live(L).src.box.i[2318] == 1, "LOOT_OPENED's isFromItem: a container"
run(L, 'WIN({ { L_(10940), 2, { IGUID(5), 2 } } }); LOOT_ALL()')
assert live(L).src.box.i[10940] == 2, "an Item- source: a container"
v0 = live(L).value
run(L, 'CAST(13262); WIN({ { L_(10940), 4, { IGUID(6), 4 } } }); LOOT_ALL(); ADVANCE(4)')
assert live(L).src.de.i[10940] == 4 and live(L).src.de.v == 40 and live(L).value == v0, "disenchanting is recorded, not counted"
print("CLASSIFY OK")

# ---------------------------------------------------------------- 7. values
L.execute("ScannerKingDB.prices[2318] = { p = 150, m = 200, t = ScannerKing.Now(), q = 5 }")
before = live(L)["items"][2318].v
run(L, 'WIN({ { L_(2318), 1, { G(299, 20), 1 } } }); LOOT_ALL()')
assert live(L)["items"][2318].v == before + 190, "snapshot at loot time: the market price after the 5% cut"
v1 = live(L).value
L.execute("ScannerKingDB.prices[2318].m = 400")
assert live(L).value == v1, "a later price change never changes what was credited"
assert ns.ValueNow(live(L)) > v1, "'Today' revalues it"
# quest items are worth 0; grey and bind-on-pickup get the vendor price
run(L, 'WIN({ { L_(5000), 1, { G(299, 21), 1 }, quest = true }, { L_(7000), 1, { G(299, 21), 1 } }, { L_(4865), 2, { G(299, 21), 2 } } }); LOOT_ALL()')
assert live(L)["items"][5000].v == 0 and live(L)["items"][7000].v == 900 and live(L)["items"][4865].v == 10
# an item the client hasn't loaded yet waits, and is valued when its info arrives
run(L, 'WIN({ { L_(9999), 2, { G(299, 22), 2 } } }); LOOT_ALL()')
assert live(L)["items"][9999].np == 2 and live(L)["items"][9999].v == 0
v2 = live(L).value
run(L, 'ITEM(9999, "Late Item", { quality = 1, sell = 50, class = 7 }); FIRE("GET_ITEM_INFO_RECEIVED", 9999)')
assert live(L)["items"][9999].v == 100 and live(L)["items"][9999].np is None and live(L).value == v2 + 100
# an unpriced item (no AH price, no vendor price) is valued when a scan prices it
run(L, 'WIN({ { L_(9998), 3, { OBJ(1617, 9), 3 } } }); LOOT_ALL()')
assert live(L)["items"][9998].np == 3
assert 9998 in list(ns.PriceWatch().values()), "unpriced items are watched, so the next scan prices them"
L.execute("ScannerKingDB.prices[9998] = { p = 1000, m = 1000, t = ScannerKing.Now() }")
KM.mods.Scanner.Fire("PRICES_UPDATED"); L.execute("RUN_TIMERS()")
assert live(L)["items"][9998].v == 2850 and live(L)["items"][9998].np is None
print("VALUES OK")

# ---------------------------------------------------------------- 8. clock and gold per hour
L, KM, ns = load()
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("start")
t = ns.Totals(live(L))
assert t.gph is None, "no gold per hour under a minute"
run(L, 'WIN({ { nil, 0, { G(299, 1), 3600 } } }); LOOT_ALL()')
L.execute("ADVANCE(120)")
s = live(L)
assert abs(ns.Active(s) - 120) < 1e-6 and abs(ns.Totals(s).gph - 3600 * 30) < 1e-6, ns.Totals(s).gph
farm("pause"); assert L.eval("TrackerKing.State()") == "paused" and live(L).why == "manual"
L.execute("ADVANCE(100)")
assert abs(ns.Active(live(L)) - 120) < 1e-6, "the clock stops while paused"
farm("pause"); assert L.eval("TrackerKing.State()") == "running" and live(L).paused == 100
L.execute("ADVANCE(10)")
assert abs(ns.Active(live(L)) - 130) < 1e-6
assert live(L).act == 130 or live(L).act >= 120, "checkpointed every 10 seconds"
assert live(L).tick == L.eval("NOW")
print("CLOCK OK")

# ---------------------------------------------------------------- 9. idle, auto-resume, AFK, auto-save
L.execute("ADVANCE(289)")   # 299 s since the last thing you did (the resume)
assert L.eval("TrackerKing.State()") == "running"
L.execute("ADVANCE(2)")
s = live(L)
assert s.state == "paused" and s.why == "idle", s.state
assert abs(s.act - 150) < 1e-6 and s.idle == 270, (s.act, s.idle)   # the clock rewinds to 30 s after the last action
run(L, 'WIN({ { L_(2318), 1, { G(299, 30), 1 } } }); LOOT_ALL()')
assert L.eval("TrackerKing.State()") == "running", "farming again resumes it (autoResume)"
run(L, 'AFK = true; FIRE("PLAYER_FLAGS_CHANGED", "player")')
assert live(L).state == "paused" and live(L).why == "afk"
L.execute("AFK = false")
n0 = L.eval("#TrackerKingDB.sessions")
L.execute("ADVANCE(1199)"); assert live(L) is not None
L.execute("ADVANCE(2); RUN_TIMERS()")
assert live(L) is None and L.eval("#TrackerKingDB.sessions") == n0 + 1, "an idle-paused session is saved after 20 minutes"
# a manual pause never auto-saves
farm("start"); farm("pause"); L.execute("ADVANCE(3000)")
assert live(L) is not None and live(L).state == "paused"
farm("discard"); assert live(L) is None and L.eval("POPUPS[#POPUPS].name") == "KINGMAKER_TRACKER_CONFIRM"
print("IDLE OK")

# ---------------------------------------------------------------- 10. auto-start
L, KM, ns = load()
k = KM.mods.Tracker.Kill
n0 = L.eval("NOW")
k(299, L.eval("G(299, 1)")); assert L.eval("TrackerKing.State()") == "idle", "one kill (a quest mob) never starts a session"
L.execute("ADVANCE(10)")
run(L, 'WIN({ { L_(2318), 1, { G(299, 1), 1 } } }); LOOT_ALL()')
assert L.eval("TrackerKing.State()") == "idle", "a corpse's kill and its loot are one action"
k(299, L.eval("G(299, 2)")); L.execute("ADVANCE(10)")
assert L.eval("TrackerKing.State()") == "idle"
k(299, L.eval("G(299, 3)"))
s = live(L)
assert s and s.state == "running" and s.auto is True and s.t0 == n0, (s and s.t0, n0)
assert s.kills == 3 and s.src.mob.i[2318] == 1, "what came before it is replayed into it"
assert abs(ns.Active(s) - 20) < 1e-6, "the clock starts at the first action"
assert ns.Stop("idle") is None and L.eval("#TrackerKingDB.sessions") == 0, "a short auto session is dropped"
L.execute("ADVANCE(400)")
for i in range(4, 7): k(299, L.eval("G(299, %d)" % i))
assert live(L).auto is True
rec = L.eval("TrackerKing.Stop()"); assert rec is True and L.eval("#TrackerKingDB.sessions") == 1, "Stop pressed by hand always keeps it"
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("auto off"); assert L.eval("TrackerKingDB.settings.autoStart") is False
for i in range(7, 12): k(299, L.eval("G(299, %d)" % i))
assert live(L) is None, "auto-start off"
farm("auto on")
# old actions fall out of the five-minute window
k(299, L.eval("G(299, 20)")); k(299, L.eval("G(299, 21)")); L.execute("ADVANCE(301)"); k(299, L.eval("G(299, 22)"))
assert live(L) is None
print("AUTOSTART OK")

# ---------------------------------------------------------------- 11. stop, split, discard
L, KM, ns = load()
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("start")
run(L, 'WIN({ { L_(2318), 2, { G(299, 1), 2 } }, { nil, 0, { G(299, 1), 100 } } }); LOOT_ALL()')
L.execute("ADVANCE(90)")
farm("split")
assert L.eval("#TrackerKingDB.sessions") == 1
rec = L.eval("TrackerKingDB.sessions[1]")
assert rec.id == 1 and rec.c == ME and rec.lvl == 30 and rec.act == 90 and rec.value == 130 and rec.coin == 100 and rec.iv == 30
assert rec.state is None and rec.tick is None and rec.later is None and rec.map == 1429 and rec.z[1429] == 90
assert isinstance(rec.tl, str) and rec.tl.startswith("60|") and rec.t1 == L.eval("NOW") and rec.t0 == rec.t1 - 90
assert rec.mobs[299].name is None or isinstance(rec.mobs[299].name, str)
assert live(L).prev == 1 and live(L).id == 2 and live(L).state == "running", "split: saved, and the next one already runs"
farm("discard")
assert live(L) is None and L.eval("#TrackerKingDB.sessions") == 1, "discard keeps nothing"
farm("stop"); assert "not farming" in last(L)
farm("start"); L.execute("ADVANCE(5)"); farm("stop")
assert L.eval("#TrackerKingDB.sessions") == 2 and "saved to the Farming Ledger" in last(L), "a manual session is kept, however short"
farm("status"); assert "not farming right now" in last(L)
farm("bogus"); assert any("/farm split" in o for o in outputs(L))
print("STOP OK")

# ---------------------------------------------------------------- 12. /reload and relog
LIVE = ("TrackerKingDB = { version = 1, nextId = 6, settings = {}, ui = {}, sessions = {}, live = { ['Jay-Forever'] = { id = 5, c = 'Jay-Forever', "
        "t0 = 400, act = 300, idle = 0, paused = 0, state = 'running', tick = %d, value = 1000, coin = 1000, iv = 0, kills = 2, deaths = 0, "
        "src = { mob = { n = 2, v = 0, c = 1000, i = {} } }, items = {}, mobs = {}, nodes = {}, cash = {}, z = { [1429] = 300 }, "
        "tl = { bw = 60, v = { 1000, 0, 0, 0, 0 }, a = { 2, 0, 0, 0, 0 } } } } }")
L, KM, ns = load(seed=LIVE % 940)       # NOW = 1000: a minute ago
assert live(L).state == "running" and L.eval("TrackerKing.State()") == "running", "a /reload keeps it running"
L.execute("ADVANCE(30)"); assert abs(ns.Active(live(L)) - 330) < 1e-6
L, KM, ns = load(seed=LIVE % 400)       # ten minutes ago
assert live(L).state == "paused" and live(L).why == "logout" and live(L).pausedAt == 400
L, KM, ns = load(seed=LIVE % -7000)     # over two hours ago: saved, with a chat line
assert live(L) is None and L.eval("#TrackerKingDB.sessions") == 1 and L.eval("TrackerKingDB.sessions[1].t1") == -7000
assert any("saved your farming session from earlier" in o for o in outputs(L)), outputs(L)
print("RELOAD OK")

# ---------------------------------------------------------------- 13. cash: vendor, repairs, mail, AH, trade, flights, training, quest
L, KM, ns = load()
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("start")
g0 = live(L).gold0
L.execute("REPAIR = 500")
run(L, 'FIRE("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)')
money(L, 300); money(L, -200)
L.execute("REPAIR = 0"); money(L, -500)
c = live(L).cash
assert c.vendor == 300 and c.buy == -200 and c.repair == -500, (c.vendor, c.buy, c.repair)
run(L, 'FIRE("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5); ADVANCE(2)')
for kind, pim, d in [("mail", 17, 1000), ("ah", 21, -60), ("trade", 1, 70), ("travel", 6, -50), ("train", 7, -100), ("bank", 8, -1)]:
    run(L, 'FIRE("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", %d)' % pim); money(L, d)
    run(L, 'FIRE("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", %d); ADVANCE(2)' % pim)
    assert live(L).cash[kind] == d, (kind, live(L).cash[kind])
# the classic events work as a fallback
run(L, 'FIRE("MERCHANT_SHOW")'); money(L, 5); run(L, 'FIRE("MERCHANT_CLOSED"); ADVANCE(2)')
assert live(L).cash.vendor == 305
run(L, 'FIRE("QUEST_TURNED_IN", 123, 500, 2000)'); money(L, 2000)
assert live(L).cash.quest == 2000 and live(L).value == 0, "quest gold is shown, not farmed"
money(L, 300); run(L, 'FIRE("QUEST_TURNED_IN", 124, 0, 300)')
assert live(L).cash.quest == 2300 and live(L).cash.other is None and live(L).value == 0, "money first, then the event: moved to quest"
L.execute("TrackerKingDB.settings.countQuest = true")
run(L, 'FIRE("QUEST_TURNED_IN", 125, 0, 400)'); money(L, 400)
assert live(L).value == 400 and live(L).src.quest.c == 400, "Count quest gold: it counts"
assert ns.Costs(live(L)) == -200 - 500 - 50 - 100
farm("stop")
rec = L.eval("TrackerKingDB.sessions[1]")
assert rec.gold0 == g0 and rec.gold1 == L.eval("MONEY") and ns.Totals(rec).wallet == rec.gold1 - rec.gold0
assert ns.Totals(rec).net == rec.value + ns.Costs(rec)
print("CASH OK")

# ---------------------------------------------------------------- 14. timeline
L, KM, ns = load()
L.execute("TrackerKingDB.settings.idlePause = 0")
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("start")
run(L, 'WIN({ { nil, 0, { G(299, 1), 100 } } }); LOOT_ALL()')
L.execute("ADVANCE(61)")
run(L, 'WIN({ { nil, 0, { G(299, 2), 50 } } }); LOOT_ALL()')
tl = live(L).tl
assert tl.bw == 60 and tl.v[1] == 100 and tl.v[2] == 50 and tl.a[1] == 1, "Farm counted the looted corpse as a kill"
ns.Kill(299, L.eval("G(299, 3)"))
assert live(L).tl.a[2] == 2, "a kill is an action"
packed = ns.Pack(live(L).tl)
back = ns.Unpack(packed)
assert packed == "60|100,50|1,2" and back.bw == 60 and list(back.v.values()) == [100, 50] and list(back.a.values()) == [1, 2], packed
assert ns.Pace(live(L)) is not None
L.execute("NOW = NOW + 7260; UPTIME = UPTIME + 7260")      # two hours later: bucket 123 needs merging
run(L, 'WIN({ { nil, 0, { G(299, 4), 10 } } }); LOOT_ALL()')
tl = live(L).tl
assert tl.bw == 120 and len(tl.v) <= 120 and tl.v[1] == 150 and sum(tl.v.values()) == 160, (tl.bw, len(tl.v))
print("TIMELINE OK")

# ---------------------------------------------------------------- 15/16. retention and RenameChar
L, KM, ns = load()
L.globals().TRK = ns
L.execute("""
local T = TRK
for i = 1, 6 do
  local s = T.NewSession('Jay-Forever', NOW - 100 * 86400 + i)
  s.act, s.value = 600, i * 1000
  for id = 1, 30 do s.items[20000 + id] = { q = 1, v = id } end
  s.mobs[299] = { k = 1, i = { [2318] = 1 } }; s.src.mob = { n = 1, v = 10, i = { [2318] = 1 } }
  s.tl = '60|1|0'
  s.t1 = NOW - 100 * 86400 + i
  if i == 1 then s.star = true end
  table.insert(TrackerKingDB.sessions, s)
end
local new = T.NewSession('Jay-Forever', NOW); new.t1 = NOW; new.tl = '60|1|0'; table.insert(TrackerKingDB.sessions, new)
TrackerKingDB.settings.keep = 3
""")
ns.Prune()
ss = L.eval("TrackerKingDB.sessions")
vals = [ss[i].value for i in range(1, len(ss) + 1)]
assert vals == [1000, 5000, 6000, 0], vals    # the starred one, then the newest 3 unstarred
old = ss[2]
assert old.compact is True and old.tl is None and old.mobs[299].i is None and old.src.mob.i is None
assert len(list(old["items"].keys())) == 25 and old.rest.n == 5 and old.rest.q == 5 and old.rest.v == 15, "top 25 by value, the rest folded"
assert ss[1].compact is None and ss[1].tl == "60|1|0", "starred: kept as it is"
assert ss[4].compact is None, "recent: full detail"
# RenameChar moves c and the live key
farm = L.eval("SlashCmdList.KINGMAKERFARM"); farm("start")
ns.RenameChar(ME, "Jay Stone-Forever")
assert L.eval("TrackerKingDB.live['Jay Stone-Forever'].c") == "Jay Stone-Forever" and live(L) is None
assert L.eval("TrackerKingDB.sessions[1].c") == "Jay Stone-Forever"
print("RETENTION OK")

# ---------------------------------------------------------------- 17. the HUD and every way to open it
L, KM, ns = load()
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm(""); hud = L.eval("KingMakerFarmTracker")
assert hud.shown and L.eval("TrackerKingDB.ui.hud") is True
t = texts(L)
assert "Not farming right now." in t and "Start by itself when I farm" in t and L.eval('BTN("Start", KingMakerFarmTracker)') is not None
assert hud.title.text == "Farm Tracker" and hud.right.text == "" and hud.timer.text == "" and hud.rate.text == ""
L.execute('BTN("Start", KingMakerFarmTracker):Click(); RUN_TIMERS()')
assert L.eval("TrackerKing.State()") == "running" and hud.title.text == "Farming"
run(L, 'WIN({ { L_(2318), 3, { G(299, 1), 3 } }, { L_(5000), 1, { G(299, 1), 1 } }, { nil, 0, { G(299, 1), 2500 } } }); LOOT_ALL()')
run(L, 'CAST(2575, "Copper Vein"); WIN({ { L_(2770), 2, { OBJ(1731, 1), 2 } } }); LOOT_ALL(); ADVANCE(4)')
L.execute("ADVANCE(120)")
t = texts(L)
assert any("Light Leather|r x3" in x for x in t) and "Coin" in t and any("1 quest item" in x for x in t), t
assert any(x.startswith("Mobs ") and x.endswith("%") for x in t) and any(x.startswith("Gathering ") for x in t)
assert ":" in hud.timer.text and "/hr" in hud.rate.text, (hud.timer.text, hud.rate.text)
# tabs persist
L.execute('BTN("Mobs", KingMakerFarmTracker):Click()'); assert L.eval("TrackerKingDB.ui.hudTab") == "mobs"
assert any(x.startswith("Kills ") for x in texts(L)) and any("TOP DROPS" in x for x in texts(L))
L.execute('BTN("Gathering", KingMakerFarmTracker):Click()'); assert L.eval("TrackerKingDB.ui.hudTab") == "gathering"
assert any(x.startswith("Mining") for x in texts(L)) and any("Copper Vein 1" in x for x in texts(L))
L.execute('BTN("All", KingMakerFarmTracker):Click()')
# pause / resume / split from the buttons; right-click Stop opens a menu
L.execute('BTN("Pause", KingMakerFarmTracker):Click(); RUN_TIMERS()')
assert L.eval("TrackerKing.State()") == "paused" and hud.title.text == "Paused" and L.eval('BTN("Resume", KingMakerFarmTracker)') is not None
L.execute('BTN("Resume", KingMakerFarmTracker):Click(); RUN_TIMERS()'); assert L.eval("TrackerKing.State()") == "running"
L.execute('BTN("Stop & save", KingMakerFarmTracker):Click("RightButton")')
assert L.eval('MENU_ITEM("Discard") ~= nil') and L.eval('MENU_ITEM("Stop & save") ~= nil')
# collapse: the title keeps the clock and gold per hour; position persists in UI.HUD's own shape
L.execute("KingMakerFarmTracker.collapse:Click(); RUN_TIMERS()")
assert L.eval("TrackerKingDB.ui.hudCollapsed") is True and hud.collapsed and "/hr" in hud.rate.text
L.execute("KingMakerFarmTracker.collapse:Click(); RUN_TIMERS()"); assert not hud.collapsed
L.execute('KingMakerFarmTracker:ClearAllPoints(); KingMakerFarmTracker:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -60); KingMakerFarmTracker.scripts.OnDragStop(KingMakerFarmTracker)')
pos = L.eval("TrackerKingDB.ui.hudPos"); assert pos.point == "TOPLEFT" and pos.x == 50 and pos.y == -60
# Ctrl+wheel zooms it
L.execute("CTRL = true; KingMakerFarmTracker.scripts.OnMouseWheel(KingMakerFarmTracker, 1); CTRL = false")
assert abs(L.eval("TrackerKingDB.ui.hudScale") - 1.05) < 1e-9
L.execute('BTN("Stop & save", KingMakerFarmTracker):Click(); RUN_TIMERS()')
assert L.eval("TrackerKing.State()") == "idle" and any(x.startswith("Saved: ") for x in texts(L)), "the idle box shows what was just saved"
# x hides it; the session keeps recording
farm("start")
L.execute("KingMakerFarmTracker.close:Click()")
assert not hud.shown and L.eval("TrackerKing.State()") == "running" and "/farm shows it again" in last(L)
farm("on"); assert hud.shown
farm("off"); assert not hud.shown
# /fk mini and /gt ledger drive the same box
L.eval("SlashCmdList.FARMKING")("mini on"); assert hud.shown
L.eval("SlashCmdList.GATHERKING")("ledger off"); assert not hud.shown
L.eval("SlashCmdList.GATHERKING")("ledger timer"); assert L.eval("TrackerKing.State()") == "paused"
L.eval("SlashCmdList.GATHERKING")("ledger reset"); assert L.eval("TrackerKing.State()") == "idle" and "Saved the session" in last(L)
# the crown: Farm Tracker, Start / Stop farming (dynamic label), Farming Ledger
L.execute('KingMakerMinimapButton:Click("RightButton")')
for label in ("Farm Tracker", "Start farming", "Farming Ledger"):
    assert L.eval('MENU_ITEM("%s") ~= nil' % label), label
L.execute('MENU_ITEM("Start farming").fn(); RUN_TIMERS()'); assert L.eval("TrackerKing.State()") == "running"
L.execute('KingMakerMinimapButton:Click("RightButton")'); assert L.eval('MENU_ITEM("Stop farming (save)") ~= nil')
L.execute('MENU_ITEM("Stop farming (save)").fn(); RUN_TIMERS()'); assert L.eval("TrackerKing.State()") == "idle"
assert hud.shown, "starting showed it (hudOnStart)"
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("Farm Tracker").fn()'); assert not hud.shown
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("Farm Tracker").fn()'); assert hud.shown
# Mob Farming's button
KM.Show("mobs"); L.execute('BTN("Farm tracker"):Click()'); assert not hud.shown
L.execute('BTN("Farm tracker"):Click()'); assert hud.shown and L.eval('BTN("Farm tracker")').active
assert not KM.errorShown, last(L)
print("HUD OK")

# ---------------------------------------------------------------- 19. settings, Home, crown tooltip, status
KM.OpenSettings("tracker"); assert not KM.errorShown, last(L)
t = texts(L)
for label in ("Show the Farm Tracker", "Start a session by itself when I farm", "Count party coin shares", "Count quest gold",
              "Count disenchanting", "Open the Farming Ledger", "Save the current session now", "Farm Tracker size"):
    assert label in t, label
L.execute('CHECK("Count disenchanting"):Click()'); assert L.eval("TrackerKingDB.settings.countDE") is True
L.execute('CHECK("Count disenchanting"):Click()')
KM.Show("home")
assert "FARMED, 7 DAYS" in texts(L), "idle with sessions this week"
farm("start"); run(L, 'WIN({ { nil, 0, { G(299, 50), 5000 } } }); LOOT_ALL()'); KM.Show("home")
assert "FARMING NOW" in texts(L)
L.execute("GameTooltip.lines = {}; KingMakerMinimapButton.scripts.OnEnter(KingMakerMinimapButton)")
assert any(str(x).startswith("Farming: 0:") for x in L.eval("GameTooltip.lines").values())
KM.Refresh()
assert any("Farming 0:" in x for x in texts(L)), "the sidebar status line"
farm("stop")
L.execute("GameTooltip.lines = {}; KingMakerMinimapButton.scripts.OnEnter(KingMakerMinimapButton)")
assert any(str(x).startswith("Farmed this week") for x in L.eval("GameTooltip.lines").values())
print("SHELL OK")

# ---------------------------------------------------------------- 20. Bindings.xml
tree = ET.parse(os.path.join(ROOT, "Bindings.xml"))
binds = tree.getroot().findall("Binding")
assert len(binds) == 6 and all(b.get("category") == "King Maker" for b in binds)
toc = open(os.path.join(ROOT, "King_Maker.toc"), encoding="utf-8").read()
assert "Bindings.xml" not in toc, "the client loads Bindings.xml by itself; it must not be in the TOC"
for b in binds:
    assert isinstance(L.eval("BINDING_NAME_" + b.get("name")), str), b.get("name")
    for obj, fn in re.findall(r"(TrackerKing|KingMaker)\.(\w+)\(", b.text):
        assert L.eval("type(%s.%s)" % (obj, fn)) == "function", (obj, fn)
L.execute(binds[2].text + "; RUN_TIMERS()"); assert L.eval("TrackerKing.State()") == "running", "the start/stop key"
L.execute(binds[3].text); assert L.eval("TrackerKing.State()") == "paused", "the pause key"
L.execute(binds[3].text); assert L.eval("TrackerKing.State()") == "running"
L.execute(binds[4].text); assert L.eval("TrackerKing.State()") == "running" and live(L).prev is not None, "the split key"
print("BINDINGS OK")

# ---------------------------------------------------------------- 21. API copies
lv = L.eval("TrackerKing.Live()")
lv.value = 99999999; lv.kills = 777
assert live(L).value != 99999999 and live(L).kills != 777
sess = L.eval("TrackerKing.Sessions()")
assert len(sess) >= 1 and sess[1].id == L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions].id"), "newest first"
sess[1].value = -1
assert L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions].value") != -1
got = []
L.globals().GOT = L.table()
L.execute('TrackerKing.RegisterCallback("test", function(e) GOT[#GOT + 1] = e end)')
farm("stop"); farm("start"); L.execute("RUN_TIMERS()")
assert "SESSION_SAVED" in list(L.eval("GOT").values()) and "SESSION_STARTED" in list(L.eval("GOT").values())
L.execute('TrackerKing.RegisterCallback("bad", function() error("boom") end)'); farm("stop")
assert not KM.errorShown, "a callback that errors doesn't break the tracker"
print("API OK")

# ---------------------------------------------------------------- 18. the Farming Ledger page
L, KM, ns = load()
L.execute("TrackerKingDB.settings.idlePause = 0")
farm = L.eval("SlashCmdList.KINGMAKERFARM")
def session(window, secs):
    farm("start")
    run(L, window + "; LOOT_ALL()")
    L.execute("ADVANCE(%d)" % secs)
    farm("stop")
session('WIN({ { L_(2318), 4, { G(299, 1), 4 } }, { nil, 0, { G(299, 1), 6000 } } })', 1200)
session('CAST(2575, "Copper Vein"); WIN({ { L_(2770), 10, { OBJ(1731, 1), 10 } } }); ADVANCE(4)', 900)
session('WIN({ { nil, 0, { G(299, 2), 2000 } } })', 600)
L.execute("TrackerKingDB.sessions[1].t1 = NOW - 10 * 86400; TrackerKingDB.sessions[1].t0 = NOW - 10 * 86400 - 1200")
L.execute("TrackerKingDB.sessions[3].c = 'Alt-Forever'")
L.globals().TRK = ns   # a carried-over session too, as the old boxes leave one
L.execute("local s = TRK.NewSession('Jay-Forever', NOW - 5000); s.legacy = true; s.name = 'Carried over from the old trackers'; s.act = 3000; s.value = 99999; s.coin = 99999; s.t1 = NOW - 2000; s.tl = nil; TRK.SaveRecord(s)")
L.eval("SlashCmdList.KINGMAKER")("farming")
assert KM.CurrentPage() == "farming" and not KM.errorShown, last(L)
P = ns.P
t = texts(L)
for label in ("FARMED", "GOLD/HR", "TIME", "SESSIONS", "BEST", "COSTS", "GOLD PER HOUR, EACH SESSION"):
    assert label in t, label
assert len(list(P.table.data.values())) == 4, "30 days, every character: 3 sessions and the carried-over one"
assert len(list(P.table.data.values())) == len(list(ns.ListSessions().values()))
assert P.chart.bars.used == 3, "a bar per session, carried over left out"
assert P.tiles[4].value.text == "3", P.tiles[4].value.text
assert any("carried over" in x for x in t), "the carried-over pill"
assert P.chart.refLine.shown and "avg" in P.chart.refText.text
# the character filter and the period filter
L.execute("TRK.P.charBtn:Click()")
assert L.eval("TrackerKingDB.ui.mine") is True and len(list(P.table.data.values())) == 3 and P.charBtn.label.text == "This character"
L.execute("TRK.P.periods.buttons[7]:Click()")
assert L.eval("TrackerKingDB.ui.period") == 7 and len(list(P.table.data.values())) == 2, "7 days: the 10-day-old one goes"
L.execute("TRK.P.periods.buttons[0]:Click(); TRK.P.charBtn:Click()")
assert len(list(P.table.data.values())) == 4
# right-click a row: its menu; click: its details
row = [r for r in P.table.rows.values() if r.data and r.shown != False][0]
row.Click(row, "RightButton"); assert L.eval('MENU_ITEM("Rename") ~= nil') and L.eval('MENU_ITEM("Delete") ~= nil')
row.Click(row, "LeftButton")
D = ns.D
assert P.view == "detail" and P.detail.shown and not P.list.shown and not KM.errorShown, last(L)
first = P.sessionID
assert D.pos.text == "1 of 4" and D.title.text, D.pos.text
t = texts(L)
for label in ("FARMED", "GOLD/HR", "ACTIVE", "COIN", "KILLS", "NET", "GOLD OVER TIME", "WHERE IT CAME FROM"):
    assert label in t, label
# back and the arrows
L.execute("TRK.D.next:Click()"); assert P.sessionID != first and D.pos.text == "2 of 4"
L.execute("TRK.D.prev:Click()"); assert P.sessionID == first
L.execute("TRK.D.back:Click()"); assert P.view == "list" and P.list.shown
# open the mob session from the chart
mobS = [s for s in L.eval("TrackerKingDB.sessions").values() if s.kills and s.kills > 0 and not s.legacy][0]
pt = [p for p in P.chart.hoverPts.values() if p[3][4].id == mobS.id][0]
P.chart.spec.click(pt[1], pt[3])
assert P.view == "detail" and P.sessionID == mobS.id
KM.Refresh("farming")
assert L.eval("LINES") > 0 and D.chart.lines.used > 0 and D.chart.bars.used > 0, "gold over time: a line with a wash under it"
assert D.chart.endDot.shown and D.chart.endText.text, "the end value is labelled"
assert D.bars.rows[1].shown and D.bars.rows[1].label.text in ("Mob drops", "Coin") and D.bars.rows[2].shown
# the tabs
assert any("Light Leather" in x for x in texts(L)) and len(list(D["items"].data.values())) == 1
L.execute('TRK.D.tabs.buttons.mobs:Click()'); assert D.mobs.shown and len(list(D.mobs.data.values())) == 1
L.execute('TRK.D.tabs.buttons.gathering:Click()'); assert D.gather.shown
L.execute('TRK.D.tabs.buttons.money:Click()')
t = texts(L); assert "WALLET" in t and "COSTS AND NET" in t and "Net farmed" in t and "= At end" in t
L.execute('TRK.D.tabs.buttons.items:Click()')
# rename, keep, revalue
L.execute('TRK.D.rename:Click(); TRK.D.renameBox:SetText("Wolf run"); TRK.D.renameBox.scripts.OnEnterPressed(TRK.D.renameBox); RUN_TIMERS()')
assert ns.Find(mobS.id)[0].name == "Wolf run" and D.title.text == "Wolf run"
L.execute('TRK.D.keep:Click(); RUN_TIMERS()'); assert ns.Find(mobS.id)[0].star is True and D.keep.label.text == "Kept"
L.execute("ScannerKingDB.prices[2318] = { p = 1000, m = 1000, t = ScannerKing.Now() }")
L.execute('TRK.D.prices.buttons.today:Click()')
assert L.eval("TrackerKingDB.ui.revalue") is True and D.tiles[1].sub.text == "at today's prices"
assert ns.Totals(ns.Find(mobS.id)[0], True).value == 6000 + 4 * 950
L.execute('TRK.D.prices.buttons.looted:Click()')
# delete: asks, then back to the list
n = L.eval("#TrackerKingDB.sessions")
L.execute('TRK.D.del:Click(); RUN_TIMERS()')
assert L.eval("POPUPS[#POPUPS].name") == "KINGMAKER_TRACKER_CONFIRM" and L.eval("#TrackerKingDB.sessions") == n - 1 and P.view == "list"
# the live badge, TrackerKing.OpenLedger(id), /farm ledger
farm("start"); assert KM.pages.farming.badge() == "LIVE"
farm("stop"); assert KM.pages.farming.badge() == ""
sid = L.eval("TrackerKingDB.sessions[1].id")
L.execute("TrackerKing.OpenLedger(%d)" % sid); assert P.view == "detail" and P.sessionID == sid
farm("ledger"); assert KM.CurrentPage() == "farming"
# an empty ledger says how to start
L.execute("TrackerKingDB.sessions = {}"); ns.ShowList()
assert "No sessions yet" in P.table.empty.text
open_every_page(L, KM)
assert not KM.errorShown, last(L)
print("PAGE OK")

# ---------------------------------------------------------------- 22. the title bar never overlaps; lists size themselves; the corner grip
L, KM, ns = load(extra="""
for i = 1, 30 do ITEM(30000 + i, "Farmed Thing Number " .. i, { quality = 1, sell = 1000 - i, class = 7 }) end
""")
farm = L.eval("SlashCmdList.KINGMAKERFARM")
farm("start"); farm("on")
hud = L.eval("KingMakerFarmTracker")
L.globals().TRK = ns
TW = lambda fs: L.eval("function(fs) return fs:GetStringWidth() end")(fs)


def loot(ids):
    run(L, "WIN({ %s }); LOOT_ALL()" % ", ".join("{ L_(%d), 1, { G(299, %d), 1 } }" % (30000 + i, i) for i in ids))


def title_ok(label=""):
    lay = hud.titleLayout
    parts = [(lay.statusL, lay.statusL + TW(hud.title), "status", lay.statusW)]
    if hud.timer.text:
        parts.append((lay.timerL, lay.timerL + lay.timerW, "timer", lay.timerW))
        assert TW(hud.timer) <= lay.timerW, (label, "timer text wider than its space")
    if hud.rate.text:
        parts.append((lay.rateL, lay.rateL + lay.rateW, "rate", lay.rateW))
        assert TW(hud.rate) <= lay.rateW, (label, "rate text wider than its space")
    assert TW(hud.title) <= lay.statusW, (label, hud.title.text, TW(hud.title), lay.statusW)
    for (a0, a1, an, _), (b0, b1, bn, _) in zip(parts, parts[1:]):
        assert a1 <= b0, (label, an, "runs into", bn, a1, b0)
    assert parts[-1][1] <= lay.buttonsL, (label, "runs under the buttons")
    assert hud.right.text == "", "the old one-piece right text stays empty"
    return lay


# every status the tracker shows, with a long clock and a big gold per hour, at the narrowest width
for state, why, full, short in (("running", None, "Farming", "Farming"), ("paused", None, "Paused", "Paused"),
                               ("paused", "idle", "Paused (idle)", "Idle"), ("paused", "afk", "Paused (AFK)", "AFK")):
    L.execute("local s = TrackerKingDB.live['%s']; s.state = '%s'; s.why = %s" % (ME, state, ("'%s'" % why) if why else "nil"))
    ns.UpdateHUD()
    title_ok(full)
    assert hud.title.text in (full, short) or hud.title.text.endswith("..."), hud.title.text
    assert ns.TitleFor(L.eval("TrackerKingDB.live['%s']" % ME))[2] == short
    # the worst case: a 12-hour clock and a four-digit gold per hour
    hud.SetTitleParts(hud, full, "12:34:56", "1,234|cffffd700g|r 56|cffc7c7cfs|r/hr", short)
    title_ok(full + " long")
    assert hud.timer.text == "12:34:56", "the clock always has its own space"
L.execute("TrackerKingDB.live['%s'].state = 'running'; TrackerKingDB.live['%s'].why = nil" % (ME, ME))
# a wider box: the full status and the rate come back
hud.SetWidth(hud, 420); hud.SetTitleParts(hud, "Paused (idle)", "12:34:56", "1,234g 56s/hr", "Idle")
title_ok("wide"); assert hud.title.text == "Paused (idle)" and hud.rate.text == "1,234g 56s/hr"
# far too narrow: the status is cut with "...", the rate goes, nothing overlaps
hud.SetWidth(hud, 200); hud.SetTitleParts(hud, "Paused (idle)", "12:34:56", "1,234g 56s/hr", None)
lay = title_ok("narrow"); assert hud.title.text == "Paus..." and hud.rate.text == "", hud.title.text
# another UI.HUD without SetTitleParts keeps its one-piece right text
L.execute('P2 = KingMaker.UI.HUD("PlainHUD2", "Plain", 268); P2:SetRightText("0:01:00")')
assert L.eval("P2.right.text") == "0:01:00" and L.eval("P2.titleLayout") is None and L.eval("P2.grip") is None
ns.UpdateHUD()
print("TITLE OK")

# the item list grows with what's looted, up to 8 rows (the default), then scrolls
assert ns.hudList.rows == 0 and "Nothing looted yet" in texts(L)
loot([1, 2, 3]); h3 = hud.h
assert ns.hudList.rows == 3 and ns.hudList.cap == 8
loot([4, 5, 6, 7, 8]); h8 = hud.h
assert ns.hudList.rows == 8 and h8 - h3 == 5 * 14, (h3, h8)
assert not any("more|r" in x for x in texts(L)), "8 items in 8 rows: no '+N more'"
loot([9, 10, 11, 12])
assert ns.hudList.rows == 8 and ns.hudList.total == 12 and hud.h == h8, "capped at the allowed height"
assert any("+5 more" in x for x in texts(L))
L.execute("KingMakerFarmTracker.scripts.OnMouseWheel(KingMakerFarmTracker, -1)")
assert any("+4 more" in x for x in texts(L)), "the wheel still scrolls past the allowed height"
L.execute("KingMakerFarmTracker.scripts.OnMouseWheel(KingMakerFarmTracker, 1)")
print("AUTOSIZE OK")

# the grip: same dots as the window's zoom grip; drag down 3 rows and 40 px right
g = hud.grip
assert g and len(list(g.dots.values())) == 6 and g.shown is not False
def drag(dx, dy, up=True):
    L.execute("CURSOR_X, CURSOR_Y = 500, 400; local g = KingMakerFarmTracker.grip; g.scripts.OnMouseDown(g, 'LeftButton')")
    L.execute("CURSOR_X, CURSOR_Y = 500 + (%f), 400 - (%f); local g = KingMakerFarmTracker.grip; g.scripts.OnUpdate(g, 0.1)" % (dx, dy))
    if up:
        L.execute("local g = KingMakerFarmTracker.grip; g.scripts.OnMouseUp(g, 'LeftButton')")
drag(40, 3 * 14, up=False)
assert g.readout.text == "up to 11 rows" and g.readout.shown
L.execute("local g = KingMakerFarmTracker.grip; g.scripts.OnMouseUp(g, 'LeftButton')")
assert not g.readout.shown
ui = L.eval("TrackerKingDB.ui")
assert ui.hudRows == 11 and ui.hudW == 320, (ui.hudRows, ui.hudW)
assert hud.w == 320 and ns.hudList.rows == 11 and hud.h == h8 + 3 * 14, (hud.w, ns.hudList.rows, hud.h)
assert any("+2 more" in x for x in texts(L))
names = L.eval("""(function() local t = {} for _, f in ipairs(FRAMES) do
  if f.shown ~= false and rawget(f, "item") and type(rawget(f, "left")) == "table" then t[#t + 1] = f.left.w end end return t end)()""")
assert names and all(w == 320 - 110 for w in names.values()), "the name column gets the room"
assert ui.hudPos.point == "TOPLEFT", "the grip keeps the top-left corner where it is"
title_ok("after the grip")
# a small press without moving doesn't resize (so a double-click can't)
drag(1, 1)
assert ui.hudRows == 11 and ui.hudW == 320
# sized by hand: fewer items (a split starts an empty session) keep the box at the height you dragged it to
ns.Split(); L.execute("RUN_TIMERS()"); ns.UpdateHUD()
assert ns.hudList.rows == 0 and ns.hudList.pad == 10 and hud.h > h8 and ui.hudRows == 11, (hud.h, h8)
loot([1, 2]); assert ns.hudList.rows == 2 and ns.hudList.cap == 11 and ns.hudList.pad == 9, "two items, nine blank rows: the list keeps the size you dragged"
# min and max: 3 rows and 280 wide at least; at most what fits on the screen
drag(-500, -500)
assert ui.hudRows == 3 and ui.hudW is None and hud.w == 280, "the smallest: 3 rows, today's 280 wide"
drag(5000, 5000)
cap = (768 - 230) // 14
assert ui.hudRows == cap and ui.hudW == 1024 - 20, (ui.hudRows, ui.hudW)
# 2.18.0: no Prices tab on the box any more
assert L.eval('BTN("Prices", KingMakerFarmTracker)') is None
# double-click the grip: back to 280 wide and 8 rows
L.execute("local g = KingMakerFarmTracker.grip; g.scripts.OnDoubleClick(g)")
assert ui.hudRows is None and ui.hudW is None and hud.w == 280 and ns.hudList.cap == 8
# Ctrl+wheel zoom still scales the whole box, and the grip still measures in the box's own units
L.execute("CTRL = true; KingMakerFarmTracker.scripts.OnMouseWheel(KingMakerFarmTracker, 1); KingMakerFarmTracker.scripts.OnMouseWheel(KingMakerFarmTracker, 1); CTRL = false")
assert abs(ui.hudScale - 1.1) < 1e-9 and abs(hud.scale - 1.1) < 1e-9
drag(0, 2 * 14 * 1.1)
assert ui.hudRows == 10, ui.hudRows
# folded: no grip
L.execute("KingMakerFarmTracker.collapse:Click(); RUN_TIMERS()"); assert g.shown is False
L.execute("KingMakerFarmTracker.collapse:Click(); RUN_TIMERS()"); assert g.shown is True
assert not KM.errorShown, last(L)
# saved: a /reload comes back at the size it was
L, KM, ns = load(seed="TrackerKingDB = { ui = { hud = true, hudW = 400, hudRows = 5 } }")
hud = L.eval("KingMakerFarmTracker")
assert hud.w == 400 and ns.HUDRows() == 5 and ns.HUDWidth() == 400
assert not KM.errorShown, last(L)
print("GRIP OK")

# ---------------------------------------------------------------- 23. 2.6.2: best gold/hr, Trends, Mat Prices, export, disenchanting, containers
L, KM, ns = load(seed="NOW = 10 * 86400 + 43200")
L.execute("TrackerKingDB.settings.idlePause = 0")
L.globals().TRK = ns
farm = L.eval("SlashCmdList.KINGMAKERFARM")
n_mob = [0]


def coin_session(copper, secs, zone=1429):
    n_mob[0] += 1
    L.execute("PLAYER.map = %d" % zone)
    farm("start")
    run(L, 'WIN({ { nil, 0, { G(299, %d), %d } } })' % (n_mob[0], copper))
    money(L, copper)
    run(L, "LOOT_ALL()")
    L.execute("ADVANCE(%d)" % secs)
    farm("stop")
    return L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions]")


def best_lines():
    return [o for o in outputs(L) if "new best gold per hour here" in o]


s1 = coin_session(6000, 1200)
assert best_lines() == [], "the first session at a farm beats nothing"
s2 = coin_session(12000, 1200)
lines = best_lines()
assert len(lines) == 1 and "Elwynn Forest (Mobs)" in lines[0] and "beating" in lines[0], lines
s3 = coin_session(6000, 1200)
assert len(best_lines()) == 1, "slower than the record: nothing"
s4 = coin_session(50000, 1200, zone=1436)
assert len(best_lines()) == 1, "first session in another zone: nothing"
s5 = coin_session(60000, 300)
assert len(best_lines()) == 1, "under 10 active minutes never sets a record"
best = ns.BestIDs()
assert best[s2.id] and not best[s1.id] and not best[s4.id] and not best[s5.id], "BEST: the record holder of a farm with 2+ sessions"
# carried over (act 0) and an empty-clock session are never in trends or rates
L.execute("local s = TRK.NewSession('Jay-Forever', NOW - 50); s.legacy = true; s.name = 'Carried over'; s.act = 0; "
          "s.value = 99999; s.coin = 99999; s.t1 = NOW; s.tl = nil; s.src = { mob = { n = 3, c = 99999 } }; TRK.SaveRecord(s)")
L.execute("TrackerKingDB.sessions[1].t1 = NOW - 2 * 86400")      # s1: two days ago
lst = ns.SessionsSince(None, None, True)
farms = list(ns.Farms(lst).values())
assert [f.label for f in farms] == ["Mobs", "Mobs"] and farms[0].map == 1436, [(f.map, f.label) for f in farms]
elwynn = farms[1]
assert elwynn.n == 4 and elwynn.act == 3900 and elwynn.value == 84000, (elwynn.n, elwynn.act, elwynn.value)
assert abs(elwynn.gph - 84000 / 3900 * 3600) < 1e-6 and abs(elwynn.best - 36000) < 1e-6, "time-weighted; best of 10+ min sessions"
assert elwynn.corpses == 4, "corpses looted count even when no kill was seen"
days = list(ns.Days(lst, L.eval("NOW") - 6 * 86400).values())
assert len(days) == 7 and sum(d.value for d in days) == 6000 + 12000 + 6000 + 50000 + 60000, [d.value for d in days]
assert days[-3].value == 6000 and days[-3].n == 1 and days[-1].n == 4, [(d.key, d.value, d.n) for d in days]
assert ns.Aggregate(lst).value == 134000, "carried over and act 0 stay out of the sums too"
top = list(ns.TopItems(lst).values())
assert top == [], "coin only: no items"
print("BEST OK")

# the Trends tab
L.eval("SlashCmdList.KINGMAKER")("farming")
P, T = ns.P, ns.T
L.execute("TRK.P.tabs.buttons.trends:Click()")
assert L.eval("TrackerKingDB.ui.tab") == "trends" and P.trends.shown and not P.list.shown and not KM.errorShown, last(L)
t = texts(L)
for label in ("FARMED", "AVG GOLD/HR", "TIME FARMED", "BEST ZONE", "TOP ITEM", "THIS WEEK", "FARMED PER DAY", "BEST FARMS", "TOP ITEMS FARMED"):
    assert label in t, label
assert T.tiles[4].value.text == "Westfall" and T.tiles[3].sub.text == "5 sessions", (T.tiles[4].value.text, T.tiles[3].sub.text)
assert T.chart.bars.used >= 2 and len(list(T.farms.data.values())) == 2
assert any("Elwynn Forest" in x for x in t)
# a Best farms row: the Sessions tab, only that farm's sessions
row = [r for r in T.farms.rows.values() if r.data and r.data.map == 1429][0]
row.Click(row, "LeftButton")
assert L.eval("TrackerKingDB.ui.tab") == "sessions" and P.list.shown and P.farmBtn.shown
assert len(list(P.table.data.values())) == 4 and "Elwynn Forest, Mobs" in P.farmBtn.label.text
assert any("BEST|r" in x for x in texts(L)), "the BEST pill in the session table"
L.execute("TRK.P.farmBtn:Click()")
assert not P.farmBtn.shown and len(list(P.table.data.values())) == 6
# the detail's BEST pill
ns.ShowSession(s2.id); assert ns.D.best.shown and ns.D.best.text.text == "BEST"
ns.ShowSession(s3.id); assert not ns.D.best.shown
ns.ShowList()
print("TRENDS OK")

# CSV export: the sessions shown, quoted where needed
assert ns.CSV("plain") == "plain" and ns.CSV("a,b") == '"a,b"' and ns.CSV('say "hi"') == '"say ""hi"""'
assert ns.CSV("two\nlines") == '"two\nlines"' and ns.CSV("|cffff0000red|r") == "red" and ns.CSV(None) == ""
ns.Rename(s2.id, 'Wolves, "big" run')
text, count = ns.ExportText()
lines = text.split("\n")
assert count == 6 and len(lines) == 7 and lines[0].startswith("start,end,character,level,zone,name,activity,active_sec"), lines[0]
row2 = [x for x in lines if "Wolves" in x][0]
assert '"Wolves, ""big"" run"' in row2 and ",Elwynn Forest," in row2, row2
cols = lines[0].split(",")
legacy_row = [x for x in lines[1:] if "Carried over" in x][0]
assert legacy_row.split(",")[cols.index("carried_over")] == "1"
f2 = row2.replace('"Wolves, ""big"" run"', "NAME").split(",")
assert f2[cols.index("farmed_copper")] == "12000" and f2[cols.index("active_sec")] == "1200" and f2[cols.index("gold_per_hour_copper")] == "36000", f2
assert f2[cols.index("corpses_looted")] == "1"
L.execute("TRK.P.export:Click()")
win = L.eval("KingMakerFarmingExport")
assert win.shown and win.box.GetText(win.box).startswith("start,end,") and "exported 6 farming sessions" in last(L)
win.Hide(win)
farm("export"); assert win.shown
print("EXPORT OK")

# 2.18.0: the Mat Prices tab is gone; a saved tab of "prices" opens Sessions
assert L.eval("TRK.P.tabs.buttons.prices") is None and ns.M is None
L.execute("TrackerKingDB.ui.tab = 'prices'"); assert ns.Tab() == "sessions"
L.execute("TrackerKingDB.ui.hudTab = 'prices'"); ns.UpdateHUD(); assert not KM.errorShown, last(L)
L.execute("TrackerKingDB.ui.hudTab = 'all'")

# disenchanting: off by default; the setting moves the running session at once, a saved one keeps how it counted
farm("start")
run(L, 'ADVANCE(4); CAST(13262); WIN({ { L_(10940), 4, { IGUID(6), 4 } } }); LOOT_ALL(); ADVANCE(4)')
s = live(L)
v0 = s.value
assert s.src.de.v == 40 and s.countDE is None and not ns.CountsIn(s, "de")
KM.OpenSettings("tracker")
L.execute('CHECK("Count disenchanting"):Click()')
s = live(L)
assert L.eval("TrackerKingDB.settings.countDE") is True and s.countDE is True and s.value == v0 + 40 and s.iv == 40
ns.SetCountDE(False); s = live(L)
assert s.countDE is None and s.value == v0 and s.iv == 0
ns.SetCountDE(True)
L.execute("ADVANCE(200)"); farm("stop")
saved = L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions]")
assert saved.countDE is True and saved.value == 40 and ns.CountsIn(saved, "de")
ns.SetCountDE(False)
assert saved.value == 40 and ns.CountsIn(saved, "de") and ns.ValueNow(saved) == 40, "a saved session reads as it was counted"
farm("start"); assert live(L).countDE is None, "a new session takes the setting as it is now"
farm("discard"); L.execute("RUN_TIMERS()")
assert L.eval("TrackerKing.State()") == "idle"
print("DISENCHANT OK")

# a container looted this session is swapped for what was inside; one from before simply adds its contents
L.execute("ScannerKingDB.prices[16882] = { p = 2000, m = 2000, t = NOW }")
farm("start")
run(L, 'ADVANCE(4); CAST(921); WIN({ { L_(16882), 1, { G(500, 77), 1 } } }); LOOT_ALL(); ADVANCE(4)')
s = live(L)
box_v = 1900
assert s["items"][16882].q == 1 and s["items"][16882].v == box_v and s.src.pick.v == box_v and s.value == box_v
L.execute("BAGS[0][1] = { id = 16882, count = 1 }")
run(L, 'WIN({ { L_(2318), 3, { IGUID(9), 3 } } }, true)')
L.execute("BAGS[0][1] = nil")                                       # opened: it leaves the bags
run(L, "LOOT_ALL()")
s = live(L)
assert s["items"][16882] is None and s.opened[16882] == 1, "swapped out"
assert s.src.pick.v == 0 and s.src.pick.i[16882] is None and s.mobs[500].v == 0
assert s.src.box.i[2318] == 3 and s.value == 3 * 15 and s.iv == 45, (s.value, s.iv)
tl = ns.Unpack(s.tl); assert sum(tl.v.values()) == s.value, "the timeline follows"
# a box from before the session: its count drops, but it isn't in the session, so nothing is taken off
L.execute("BAGS[0][2] = { id = 9000, count = 1 }")
v1 = live(L).value
run(L, 'WIN({ { L_(2318), 2, { IGUID(10), 2 } } }, true)')
L.execute("BAGS[0][2] = nil")
run(L, "LOOT_ALL()")
assert live(L).value == v1 + 30 and live(L).opened[16882] == 1
# two of a container, bags slow to update: BAG_UPDATE_DELAYED catches it
run(L, 'CAST(921); WIN({ { L_(16882), 2, { G(500, 78), 2 } } }); LOOT_ALL(); ADVANCE(4)')
L.execute("BAGS[0][1] = { id = 16882, count = 2 }")
L.execute('WIN({ { L_(2318), 1, { IGUID(11), 1 } } }, true); LOOT_ALL()')
L.execute("BAGS[0][1].count = 1; FIRE('BAG_UPDATE_DELAYED')")
s = live(L)
assert s["items"][16882].q == 1 and s.opened[16882] == 2 and s["items"][16882].v == box_v, (s["items"][16882].q, s.opened[16882])
L.execute("RUN_TIMERS()")
assert live(L).opened[16882] == 2, "counted once"
L.execute("ADVANCE(200)"); farm("stop")
saved = L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions]")
assert saved.opened[16882] == 2 and saved["items"][16882].q == 1
ns.ShowSession(saved.id)
assert "2 containers opened" in ns.D.meta.text, ns.D.meta.text
assert not KM.errorShown, last(L)
print("CONTAINERS OK")

# ---------------------------------------------------------------- group loot rolls and master loot (2.7.0)
# Stratholme: greens you won on a Need/Greed roll never cleared from your window, so they never counted.
ROLL_ITEMS = ('ITEM(10070, "Heros Gauntlets", { quality = 2, sell = 600, class = 4 }); '
              'ITEM(10071, "Other Green", { quality = 2, sell = 700, class = 4 }); '
              'ITEM(12811, "Righteous Orb", { quality = 2, sell = 2000, class = 12 })')
L, KM, ns = load(extra=ROLL_ITEMS)
farm = L.eval("SlashCmdList.KINGMAKERFARM")
L.execute('GROUP = true; LOOT_METHOD = "group"')
farm("start")
mobi = lambda npc, item: (live(L).mobs[npc] and live(L).mobs[npc].i[item])
# a corpse with a white you take and a green that's rolled on (locked); you win the roll
run(L, 'WIN({ { L_(2318), 2, { G(10391, 1), 2 } }, { L_(10070), 1, { G(10391, 1), 1 }, locked = true, quality = 2 } }); '
       'START_ROLL(1, 10070); LOOT_ALL()')
assert live(L).src.mob.i[2318] == 2 and live(L).src.mob.i[10070] is None, "the locked slot doesn't count on its own"
assert L.eval("FarmKingDB.mobs[10391].i[10070][1]") == 1, "Farm's drop rates count what the window showed, whoever wins"
run(L, 'FIRE("LOOT_ITEM_ROLL_WON", LINK(10070), 1, 1, 87); GIVE(10070, 1)')
assert live(L).src.mob.i[10070] == 1 and mobi(10391, 10070) == 1, "the roll you won counts, to the corpse"
assert live(L)["items"][10070].v == 600
run(L, "SELF_LOOT_LINE(10070); GIVE(10071, 1)")
assert live(L).src.mob.i[10070] == 1, "the bags and the loot line are one item"
assert live(L)["items"][10071] is None, "a bag rise with no roll or window behind it isn't loot"
assert L.eval("FarmKingDB.mobs[10391].i[10070][1]") == 1, "and Farm doesn't count it twice"
# someone else wins: nothing, whatever the chat says
run(L, 'WIN({ { L_(10071), 1, { G(10391, 2), 1 }, locked = true, quality = 2 } }); START_ROLL(2, 10071); CLOSE_LOOT(); '
       'FIRE("CHAT_MSG_LOOT", format(LOOT_ITEM, "Fried Nug", LINK(10071)), "Fried Nug"); FIRE("CANCEL_LOOT_ROLL", 2)')
assert live(L)["items"][10071] is None, "another player's win never counts"
run(L, "ADVANCE(91); GIVE(10071, 1)")
assert live(L)["items"][10071] is None, "a roll that's over stops waiting (a trade later isn't loot)"
# a roll for a corpse you never opened, then you open it: the corpse it came from is learned
run(L, 'START_ROLL(3, 10070); WIN({ { L_(10070), 1, { G(10392, 1), 1 }, locked = true, quality = 2 } }); CLOSE_LOOT(); GIVE(10070, 1)')
assert live(L).src.mob.i[10070] == 2 and mobi(10392, 10070) == 1
# a Righteous Orb roll you never saw the corpse of; your loot line comes before the bags
run(L, "START_ROLL(4, 12811); SELF_LOOT_LINE(12811)")
assert live(L).src.mob.i[12811] == 1 and mobi(0, 12811) == 1, "credited once, to an unknown mob"
run(L, "GIVE(12811, 1)")
assert live(L).src.mob.i[12811] == 1, "the bags after the line don't count it again"
# a Quest-class item that sells is ordinary loot (worth its price, listed on the HUD); one that doesn't stays hidden
assert not KM.IsQuestItem(12811) and KM.IsQuestItem(5000)
assert tuple(KM.ItemValue(12811)) == (2000, "vendor") and live(L)["items"][12811].v == 2000
run(L, 'WIN({ { L_(5000), 1, { G(10391, 3), 1 }, quest = true } }); LOOT_ALL()')
assert live(L).src.mob.i[5000] == 1
ns.SetHUD(True); ns.UpdateHUD()
tx = texts(L)
assert any("Righteous Orb" in t for t in tx), "the orb shows on the tracker"
assert any("1 quest item" in t for t in tx) and not any("2 quest items" in t for t in tx), [t for t in tx if "quest" in t]
# master loot, someone else is the looter: the locked green counts when it's handed to you
L.execute('LOOT_METHOD = "master"')
run(L, 'WIN({ { L_(10071), 1, { G(10393, 1), 1 }, locked = true, quality = 2 } }); CLOSE_LOOT(); GIVE(10071, 1)')
assert live(L).src.mob.i[10071] == 1 and mobi(10393, 10071) == 1, "master loot handed to you"
# you're the master looter: a green you hand to someone else doesn't count; one you give yourself does; whites as usual
run(L, 'WIN({ { L_(10070), 1, { G(10393, 2), 1 }, quality = 2 }, { L_(2318), 1, { G(10393, 2), 1 } } }); LOOT_ALL()')
assert live(L).src.mob.i[10070] == 2 and live(L).src.mob.i[2318] == 3, "handed to someone else: only the white"
run(L, 'WIN({ { L_(10070), 1, { G(10393, 3), 1 }, quality = 2 } }); FIRE("LOOT_SLOT_CLEARED", 1); GIVE(10070, 1); CLOSE_LOOT()')
assert live(L).src.mob.i[10070] == 3 and mobi(10393, 10070) == 1, "given to yourself"
# a roll that never reaches you is forgotten after a while
run(L, "START_ROLL(5, 10071); ADVANCE(301); GIVE(10071, 1)")
assert live(L).src.mob.i[10071] == 1
assert len(list(KM.LootExpects().values())) == 0, "old expectations are pruned"
assert not KM.errorShown, last(L)
print("ROLLS OK")

# guild bests are gone (2.8.1): a 2.8.0 save loses guildmates' bests and the sharing settings, no Guild tab, nothing sent
OLD_GUILD = ("TrackerKingDB = { version = 1, sessions = {}, live = {}, settings = { guildShare = true, guildShow = true, guildDays = 60 },"
             " ui = { tab = 'guild', guildAct = 'all', guildNear = true },"
             " guild = { ['Guild-Realm'] = { Bob = { t = 1, f = 'x', farms = { ['1429:Mobs'] = { m = 1429, a = 'Mobs', g = 100 } } } } } }")
L, KM, ns = load(seed=OLD_GUILD)
assert L.eval("TrackerKingDB.guild") is None, "guildmates' bests dropped"
for k in ("guildShare", "guildShow", "guildDays"):
    assert L.eval("TrackerKingDB.settings.%s" % k) is None, k
assert L.eval("TrackerKingDB.ui.tab") == "sessions" and L.eval("TrackerKingDB.ui.guildNear") is None
L.execute('RUN_TIMERS(); RECV("KingMaker1", "F1abc", "Bob-Realm"); RECV("KingMaker1", "Bwwww", "Bob-Realm"); RUN_TIMERS()')
assert not [m for m in L.eval("SENT").values() if m.prefix == "KingMaker1" and str(m.text)[:1] in "FAB"], "no guild bests sent"
L.globals().TRK = ns; KM.Show("farming")
assert L.eval("TRK.P.tabs.buttons.guild") is None and L.eval("TRK.P.tabs.buttons.trends") is not None
L.eval("SlashCmdList.KINGMAKERFARM")("guild")
assert not any("guild" in o.lower() for o in outputs(L)[-15:]), "/farm guild is gone: it shows the help, which has no guild line"
assert not KM.errorShown, last(L)
print("NO GUILD OK")

# --- the Zones tab (2.15.0): every session in a zone or dungeon added together, and one place's details -----------
L, KM, ns = load(seed="NOW = 10 * 86400 + 43200")
L.execute("TrackerKingDB.settings.idlePause = 0")
L.globals().TRK = ns
farm = L.eval("SlashCmdList.KINGMAKERFARM")
L.execute("MAPS[1414] = 'Kalimdor'; MAP_TYPES[1414] = 2; MAPS[317] = 'Stratholme'; MAP_TYPES[317] = 4")
z1 = coin_session(6000, 1200)                      # Elwynn Forest
z2 = coin_session(12000, 1200)                     # Elwynn Forest
L.execute("INSTANCE = true; INSTANCE_NAME = 'Stratholme'")
z3 = coin_session(30000, 1200, zone=1414)          # inside: the game says Kalimdor (or nothing), the instance says Stratholme
L.execute("INSTANCE = false")
assert z3.zi.Stratholme >= 1200 and z3.zk.Stratholme == "party", "the instance is recorded"
assert tuple(ns.Place(z3)) == ("i:Stratholme", "Stratholme", "dungeon"), tuple(ns.Place(z3))
assert tuple(ns.Place(z1)) == ("m:1429", "Elwynn Forest", "zone")
assert ns.SessionTitle(z3) == "Stratholme" and ns.FarmKey(z3)[0] == "i:Stratholme:Mobs"
# a session saved before 2.15.0 with no map: placed by the mobs it looted (Farm's zone for them)
L.execute("""
local Farm = TRK.KM.mods.Farm
TRK.oldMobInfo = Farm.MobInfo
Farm.MobInfo = function(id) if id == 10418 then return { name = 'Crimson Guardsman', map = 317 } end return TRK.oldMobInfo(id) end
local s = TRK.NewSession('Jay-Forever', NOW - 4000); s.act = 1800; s.value = 18000; s.coin = 18000; s.t1 = NOW - 2000
s.tl = nil; s.mobs = { [10418] = { k = 6, c = 18000 } }; s.src = { mob = { n = 6, c = 18000 } }; s.kills = 6
TRK.SaveRecord(s)
""")
old = L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions]")
assert old.map is None and tuple(ns.Place(old)) == ("i:Stratholme", "Stratholme", "dungeon"), tuple(ns.Place(old))
# a continent with no mobs known stays the continent
L.execute("local s = TRK.NewSession('Jay-Forever', NOW - 900); s.act = 500; s.value = 700; s.coin = 700; s.t1 = NOW - 100; "
          "s.tl = nil; s.z = { [1414] = 700 }; s.src = { mob = { n = 1, c = 700 } }; TRK.SaveRecord(s)")
kal = L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions]")
assert tuple(ns.Place(kal)) == ("m:1414", "Kalimdor", "zone"), tuple(ns.Place(kal))
# inside, the game gives no map: an old session with a few outdoor minutes and an hour unmapped is the dungeon its
# mobs are in, under the name GetInstanceInfo uses (Scholomance's floor 306 has no map type here)
L.execute("""
local Farm = TRK.KM.mods.Farm
local prev = Farm.MobInfo
Farm.MobInfo = function(id) if id == 10477 then return { name = 'Scholomance Necromancer', map = 306 } end return prev(id) end
local s = TRK.NewSession('Jay-Forever', NOW - 5000); s.act = 3600; s.value = 9000; s.coin = 9000; s.t1 = NOW - 1000
s.tl = nil; s.z = { [1429] = 100 }; s.mobs = { [10477] = { k = 40, c = 9000 } }; s.src = { mob = { n = 40, c = 9000 } }
TRK.SaveRecord(s)
""")
scholo = L.eval("TrackerKingDB.sessions[#TrackerKingDB.sessions]")
assert tuple(ns.Place(scholo)) == ("i:Scholomance", "Scholomance", "dungeon"), tuple(ns.Place(scholo))
L.execute("table.remove(TrackerKingDB.sessions)")

places = list(ns.Places(ns.SessionsSince(None, None)).values())
by = {p.key: p for p in places}
strat, elwynn = by["i:Stratholme"], by["m:1429"]
assert strat.n == 2 and strat.act == z3.act + 1800 and strat.value == 48000 and strat.kind == "dungeon", (strat.n, strat.act, strat.value)
assert abs(strat.gph - 48000 / strat.act * 3600) < 1e-6 and abs(strat.best - 90000) < 1e-6, "time-weighted; best session"
assert strat.mph and list(strat.acts.values()) == ["Mobs"]
assert elwynn.n == 2 and elwynn.value == 18000 and places[0].key == "i:Stratholme", [p.key for p in places]
assert by["m:1414"].gph is None, "under 10 active minutes: no rate"

# the tab: tiles, the filter, a place, a session from it and back
L.eval("SlashCmdList.KINGMAKER")("farming")
P, Zf = ns.P, ns.Z
L.execute("TRK.P.tabs.buttons.zones:Click()")
assert L.eval("TrackerKingDB.ui.tab") == "zones" and P.zones.shown and Zf.listView.shown and not Zf.placeView.shown, last(L)
t = texts(L)
for label in ("PLACES", "BEST ZONE", "BEST DUNGEON", "MOST FARMED", "MOST TIME", "LAST FARMED"):
    assert label in t, label
assert Zf.tiles[3].value.text == "Stratholme" and Zf.tiles[2].value.text == "Elwynn Forest", (Zf.tiles[3].value.text, Zf.tiles[2].value.text)
assert len(list(Zf.table.data.values())) == 3
L.execute("TRK.Z.filter.buttons.dungeon:Click()")
assert [p.key for p in Zf.table.data.values()] == ["i:Stratholme"] and L.eval("TrackerKingDB.ui.zoneFilter") == "dungeon"
row = [r for r in Zf.table.rows.values() if r.data and r.data.key == "i:Stratholme"][0]
row.Click(row, "LeftButton")
assert P.place == "i:Stratholme" and Zf.placeView.shown and not Zf.listView.shown and "Stratholme" in Zf.title.text
assert len(list(Zf.sessions.data.values())) == 2 and Zf.chart.bars.used >= 2
assert Zf.ptiles[4].value.text == "2" and "Mobs 2x" in Zf.what.text, (Zf.ptiles[4].value.text, Zf.what.text)
assert any("BEST|r" in x for x in texts(L)), "the best session here"
srow = [r for r in Zf.sessions.rows.values() if r.data and r.data.id == z3.id][0]
srow.Click(srow, "LeftButton")
assert P.view == "detail" and P.detail.shown and not P.zones.shown
L.execute("TRK.D.back:Click()")
assert P.view == "list" and P.zones.shown and Zf.placeView.shown and L.eval("TrackerKingDB.ui.tab") == "zones", "Back returns to the place"
L.execute("TRK.Z.back:Click()")
assert P.place is None and Zf.listView.shown
row = [r for r in Zf.table.rows.values() if r.data and r.data.key == "i:Stratholme"][0]
row.Click(row, "LeftButton")
L.execute("TRK.P.tabs.buttons.zones:Click()")
assert P.place is None and Zf.listView.shown, "the tab opens the list of places"
L.execute("TRK.P.tabs.buttons.trends:Click()")
assert any("Stratholme" in x for x in texts(L)), "Best farms names the dungeon too"
ns.ShowList()
assert L.eval("TrackerKingDB.ui.tab") == "sessions", "Back from the list goes to Sessions as before"
assert not KM.errorShown, last(L)
print("ZONES OK")

print("tracker: ok")
