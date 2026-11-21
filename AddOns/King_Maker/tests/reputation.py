# Reputation (new in 2.10): the Reputation section and its Supply Writs page. Checked: the generated data, the faction
# picked by side, standing and progress across the thresholds (both reputation APIs), writs done today from the quest
# flag and from QUEST_TURNED_IN, the daily reset rolling "today" over, orders held from bag counts and the red badge,
# rep today, daily snapshots and the 7-day pace, costs (buy vs craft), rep per gold and the cheapest-rep ranking with
# stub prices, the receipt path, Favor shopping through Crafting Profits, the per-character summary, the login reminder,
# customers learned at a turn-in, waypoints, the API, /rep, both pages and every tab, Settings, InitDB twice, and that
# nothing errors when the reputation, reset, currency and quest APIs are missing.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page

MODS = ["Scanner", "Econ", "Market", "Inventory", "Reputation"]
DAY = 86400
ACA, DSL = 2586, 2587

EXTRA = """
ITEM(264011, "Craftsman's Writ: Elixir of Ogre's Strength", { class = 12 })
ITEM(264012, "Craftsman's Writ: Elixir of Wisdom", { class = 12 })
ITEM(264013, "Craftsman's Writ: Lesser Mana Potion", { class = 12 })
ITEM(262888, "Sealed Journeyman Writ", { class = 15 }); ITEM(262889, "Sealed Expert Writ", { class = 15 })
ITEM(262890, "Sealed Artisan Writ", { class = 15 }); ITEM(248549, "Waylaid Crate", { class = 15 })
ITEM(3391, "Elixir of Ogre's Strength", { class = 0 }); ITEM(3383, "Elixir of Wisdom", { class = 0 })
ITEM(6050, "Frost Protection Potion", { class = 0 }); ITEM(250345, "Elixir of Lesser Spirit", { class = 0 })
REP[2586] = { name = "Azeroth Commerce Authority", value = 4000 }
CURRENCY[3402] = 135
COMPLETED[94212] = true                                   -- Elixir of Wisdom: done today (the flag)
BAGS[0][1] = { id = 264011, count = 2 }; BAGS[0][2] = { id = 264012, count = 1 }; BAGS[0][3] = { id = 262888, count = 1 }
"""

SEED = """
ScannerKingDB = { prices = {
  [3391] = { p = 5000, t = 990 }, [3383] = { p = 2000, t = 990 }, [785] = { p = 100, t = 990 }, [2450] = { p = 200, t = 990 },
  [3371] = { p = 10, t = 990 }, [6050] = { p = 10000, t = 990 }, [262888] = { p = 20000, t = 990 }, [262889] = { p = 30000, t = 990 },
  [262890] = { p = 90000, t = 990 }, [248549] = { p = 1000, t = 990 }, [250345] = { p = 20000, t = 990 }, [3355] = { p = 300, t = 990 } } }
ReputationKingDB = { chars = {
  ["Kay-Forever"] = { name = "Kay", realm = "Forever", class = "MAGE", side = "Horde", seen = 900, favor = 50,
    rep = { [2587] = { v = 10000, s = 6, at = 900 } }, done = { [94213] = 950 }, dayEnd = 1000 + 3600, held = { [264014] = 1 } },
  ["Old-Forever"] = { name = "Old", realm = "Forever", side = "Alliance", seen = 500, rep = { [2586] = { v = 100 } },
    done = { [94214] = 400 }, dayEnd = 800 } } }
"""

L, KM = fresh(only=MODS, extra=EXTRA, seed=SEED)
ns = KM.mods.Reputation
db = lambda: L.eval("ReputationKingDB")
me = lambda: L.eval("ReputationKingDB.chars['Jay-Forever']")
NOW = lambda: L.eval("NOW")
run = lambda code: L.execute(code + "; RUN_TIMERS()")

# --- 1. data, loading, saved data -----------------------------------------------------------------------------------
orders = list(ns.ORDER_LIST.values())
assert len(orders) == 150
tiers = {}
for o in orders:
    tiers[o.tier] = tiers.get(o.tier, 0) + 1
    assert o.rep == {"J": 75, "E": 125, "A": 200}[o.tier] and o.item > 0 and o.prof in (2, 3, 4, 8, 9), o.id
assert tiers == {"J": 45, "E": 60, "A": 45}, tiers
assert sum(o.rep for o in orders) == 19875, "all 150 once"
shot = ns.Order(264037)
assert shot.item == 8069 and shot.count == 200 and shot.prof == 9, "Crafted Solid Shot wants 200"
assert ns.QUEST_ORDER[94004].id == 264011 and ns.QUEST_ORDER[94360].id == 264160
assert ns.TIERS.J.sealed == 262888 and ns.SEALED[262890] == "A" and ns.CURRENCY == 3402 and ns.RECEIPT.rep == 50
assert ns.FAVOR_RECIPES[1250794][0 + 1] == 45
assert L.eval("ReputationKing.API_VERSION") == 1
s = db().settings
assert s.remind is True and s.badge is True and s.diplomat == 0 and db().version == 1
c = me()
assert c.name == "Jay" and c.side == "Alliance" and c["class"] == "WARRIOR" and c.favor == 135
before = (c.rep[ACA].v, c.dayEnd, len(list(c.done.keys())))
ns.InitDB(); ns.InitDB()
c = me()
assert (c.rep[ACA].v, c.dayEnd, len(list(c.done.keys()))) == before and db().chars["Kay-Forever"].favor == 50
assert KM.pages.writs.group == "rep" and KM.pages.reputation.group == "rep" and KM.groups.rep.label == "Reputation"
print("LOAD OK")

# --- 2. the faction for your side ----------------------------------------------------------------------------------
assert ns.Supply("Alliance").faction == ACA and ns.Supply("Horde").faction == DSL and ns.Supply("Neutral") is None
assert ns.Supply("Alliance").name == "Azeroth Commerce Authority" and ns.Supply("Horde").name == "Durotar Supply and Logistics"
t = ns.Tracked("Alliance"); assert t[1].factionID == ACA and t[1]["def"].page == "writs"
assert ns.Tracked("Horde")[1].factionID == DSL
L.execute("PLAYER.faction = 'Neutral'"); assert ns.Side() is None and len(list(ns.Tracked().values())) == 0
L.execute("PLAYER.faction = 'Horde'"); assert ns.Side() == "Horde"
L.execute("PLAYER.faction = 'Alliance'")
print("SIDE OK")

# --- 3. standings across the thresholds ------------------------------------------------------------------------------
def st(v):
    x = ns.Standing(v)
    return (x.standing, x.into, x.size, x.toNext)
assert st(0) == (4, 0, 3000, 3000) and st(2999) == (4, 2999, 3000, 1)
assert st(3000) == (5, 0, 6000, 6000) and st(8999) == (5, 5999, 6000, 1)
assert st(9000) == (6, 0, 12000, 12000) and st(21000) == (7, 0, 21000, 21000) and st(41999)[0] == 7
assert st(42000)[0] == 8 and st(99999) == (8, 999, 1000, 0) and st(-100)[0] == 3 and st(-50000)[0] == 1
assert ns.Standing(4500).frac == 0.25 and ns.Standing(0).toExalted == 42000
x = ns.CharStanding(me()); assert x.standing == 5 and x.into == 1000 and x.size == 6000
assert ns.StandingName(6) == "Honored"
r = ns.ReadFaction(ACA); assert r.value == 4000 and r.standing == 5 and r.name == "Azeroth Commerce Authority"
L.execute("SAVED_CR = C_Reputation; C_Reputation = nil")
r = ns.ReadFaction(ACA); assert r.value == 4000 and r.standing == 5, "GetFactionInfoByID fallback"
L.execute("C_Reputation = SAVED_CR")
assert ns.ReadFaction(1234) is None, "a faction the game doesn't know"
assert ns.NextUnlock(5)[0] == 6 and ns.NextUnlock(8) is None
print("STANDING OK")

# --- 4. done today: the flag and QUEST_TURNED_IN ---------------------------------------------------------------------
c = me()
assert c.done[94212], "the flag at login"
assert ns.DoneToday(c) == (1, 75)
run("TURN_IN(94004, false)")                               # the flag lags: the event alone counts it
c = me()
assert c.done[94004] and ns.DoneToday(c) == (2, 150)
assert L.eval("ReputationKing.IsDoneToday(264011)") and L.eval("ReputationKing.IsDoneToday(94212)")
assert len(list(c.log.values())) == 1 and c.log[1].q == 94004 and c.log[1].rep == 75
run("TURN_IN(12345)")                                      # not a writ: ignored
assert ns.DoneToday(me())[0] == 2
db().settings.diplomat = 5
assert ns.OrderRep(ns.Order(264011)) == 83 and ns.DoneToday(me()) == (2, 166)
db().settings.diplomat = 0
print("DONE OK")

# --- 5. orders held, the badge, the reminder -------------------------------------------------------------------------
c = me()
assert c.held[264011] == 2 and c.held[264012] == 1 and c.sealed.J == 1
assert ns.Badge() is None, "both held orders are done today"
assert L.eval("ReputationKing.HeldCount()") == 0
run("GIVE(264013, 1)")
assert me().held[264013] == 1
b = ns.Badge()
assert KM.BadgeTables and b.count == 1 and b.color == "red" and "Lesser Mana Potion" in b.tip and "+75 rep" in b.tip
assert KM.pages.writs.badge().count == 1
line = ns.LoginLine()
assert line and "1 writ order not turned in today" in line and "Lesser Mana Potion" in line and "/rep" in last(L)
db().settings.badge = False; assert ns.Badge() is None; db().settings.badge = True
db().settings.remind = False; assert ns.LoginLine() is None; db().settings.remind = True
print("HELD OK")

# --- 6. the login reminder at login --------------------------------------------------------------------------------
L2, KM2 = fresh(only=MODS, extra=EXTRA + "COMPLETED[94212] = nil", seed=SEED)
assert any("you hold 2 writ orders not turned in today (+150 rep)" in o for o in outputs(L2)), outputs(L2)[-3:]
L3, KM3 = fresh(only=MODS, extra=EXTRA, seed=SEED + "ReputationKingDB.settings = { remind = false }")
assert not any("writ order" in o for o in outputs(L3))
print("REMINDER OK")

# --- 7. rep today, snapshots and the pace, the reset ----------------------------------------------------------------
c = me()
assert c.dayStart[ACA] == 4000 and len(list(c.snaps[ACA].values())) == 1
assert ns.RepToday(c) == 150, "the writs' rep while the bar hasn't moved"
run("REP[2586].value = 4400; FIRE('UPDATE_FACTION')")
assert me().rep[ACA].v == 4400 and ns.RepToday(me()) == 400, "the bar moved more (a receipt too)"
assert len(list(me().snaps[ACA].values())) == 1 and me().snaps[ACA][1].v == 4400, "one snapshot a day"
end1 = me().dayEnd
assert end1 == 54000, end1   # NOW 1000 is 7:16 p.m. EST on Dec 31 1969: the next reset is 10 a.m., 15:00 UTC
L.execute("COMPLETED = {}; NOW = 54000 + 60; REP[2586].value = 5400")
ns.Tick()
c = me()
assert len(list(c.done.keys())) == 0 and c.dayEnd == 54000 + 86400 and ns.IsToday(c), "rolled over"
assert c.dayStart[ACA] == 5400 and ns.RepToday(c) == 0
assert len(list(c.snaps[ACA].values())) == 2
pace, span = ns.Pace(c, ACA)
assert pace == 1000 and span == 1, (pace, span)          # 1,000 rep in 7 hours: a day at the least, never stretched
b = ns.Badge(); assert b.count == 3, "after the reset every held order counts again"
L.execute("NOW = NOW + 86400; REP[2586].value = 6400"); ns.Tick()
L.execute("NOW = NOW + 2 * 86400; REP[2586].value = 8400"); ns.Tick()
pace, span = ns.Pace(me(), ACA)
assert pace and 700 < pace < 1500 and span >= 2.9, (pace, span)
eta = ns.ETA(ns.CharStanding(me()), pace)
assert eta and abs(eta - 600 / pace) < 0.01, "600 to Honored"
print("RESET OK")

# --- 8. costs, rep per gold, the cheapest rep ------------------------------------------------------------------------
cost, how, buy, craft = ns.ItemCost(3383)
assert (cost, how, buy, craft) == (510, "craft", 2000, 510), (cost, how, buy, craft)
cost, how = ns.ItemCost(3391)[0], ns.ItemCost(3391)[1]
assert (cost, how) == (5000, "buy")
assert ns.ItemCost(99999)[0] is None
assert ns.PouchAvg("J") == 3350 and ns.PouchAvg("A") == 7500
rows = {r.order.id: r for r in ns.HeldRows().values()}
assert rows[264012].perGold == float("inf"), "the pouch pays for a 510c craft"
assert abs(rows[264011].perGold - 75 / 0.165) < 0.01 and rows[264011].net == 1650
cheap = list(ns.CheapestRep().values())
keys = [r.key for r in cheap]
avgJ = ns.TierAvgCost("J")[0]
rJ = next(r for r in cheap if r.key == "J"); rE = next(r for r in cheap if r.key == "E")
rR = next(r for r in cheap if r.key == "receipt"); rA = next(r for r in cheap if r.key == "A")
assert rR.perRep == (1000 - 100) / 50
assert abs(rJ.perRep - (20000 + avgJ - 3350) / 75) < 1e-6
assert rE.perRep == (30000 + 10000 - 7000) / 125 and rE.priced == 1 and rE.of == 60
assert rA.perRep is None and keys[-1] == "A", "no Artisan item priced: last"
priced = [r.perRep for r in cheap if r.perRep is not None]
assert priced == sorted(priced) and keys[0] == "receipt"
receipt, best = ns.ReceiptVsWrits()
assert receipt.key == "receipt" and best.key in ("J", "E")
print("COSTS OK")

# --- 9. Favor shopping (Crafting Profits' profit) -------------------------------------------------------------------
fav = list(ns.FavorRows("buy").values())
assert len(fav) == 311
top = fav[0]
assert top.spell == 1250794 and top.favor == 45 and top.standing == 4 and top.item == 250345
assert abs(top.profit - (20000 * 0.95 - 710)) < 0.01, top.profit
assert abs(top.perFavor - top.profit / 45) < 1e-6
ench = next(r for r in fav if r.item is None)
assert ench.profit is None
assert ns.StandingForFavor(30) == 4 and ns.StandingForFavor(120) == 5 and ns.StandingForFavor(360) == 6
print("FAVOR OK")

# --- 10. every character ------------------------------------------------------------------------------------------
crow = {r.key: r for r in ns.CharRows().values()}
assert list(ns.CharRows().values())[0].me
kay = crow["Kay-Forever"]
assert kay.side == "Horde" and kay.standing.standing == 6 and kay.favor == 50 and kay.held == 1 and kay.stale, "Kay's day ended"
old = crow["Old-Forever"]
assert old.done == 0 and old.stale and not old.me
jay = crow["Jay-Forever"]
assert not jay.stale and jay.held == 3 and jay.standing.standing == 5
assert L.eval("ReputationKing.DoneToday('Kay-Forever')") == (0, 0)
assert L.eval("ReputationKing.GetFavor('Kay-Forever')") == 50
assert ns.FindChar("kay") == "Kay-Forever" and ns.Forget("Old-Forever") and not db().chars["Old-Forever"]
assert not ns.Forget("Jay-Forever"), "never forgets you"
print("CHARS OK")

# --- 11. a customer learned at the turn-in, waypoints ---------------------------------------------------------------
o = ns.Order(264116)
assert o.cust is None and ns.Customer(o) is None, "Potion of Demonslaying: nobody in the data"
run("QUEST_ID = 94316; UNITS.npc = { name = 'Kum\\'isha' }; PLAYER.map = 1419; PLAYER.x = 0.5; PLAYER.y = 0.255; FIRE('QUEST_COMPLETE'); TURN_IN(94316)")
cu = ns.Customer(o)
assert cu.name == "Kum'isha" and cu.map == 1419 and cu.x == 50 and cu.y == 25.5 and cu.learned
cu = ns.Customer(ns.Order(264014))
assert cu.name == "Kzixx" and cu.map == 1431 and cu.x == 81.8
assert ns.Waypoint(cu, "Shadow Protection Potion") == "map" and L.eval("WAYPOINT.uiMapID") == 1431 and L.eval("TRACKED") is True
L.execute("TomTom = { AddWaypoint = function(self, m, x, y, o) TT = { m, x, y, o.title } end }")
assert ns.Waypoint(cu, "x") == "tomtom" and L.eval("TT[1]") == 1431
L.execute("TomTom = nil")
assert ns.Waypoint(None) is False
assert ns.ZoneName(1431) == "Duskwood", "the data's name when the game has none"
assert ns.ZoneName(1453) == "Stormwind City"
print("CUSTOMER OK")

# --- 12. the API -------------------------------------------------------------------------------------------------
std, into, size, value = L.eval("{ ReputationKing.GetStanding() }").values()
assert (std, into, size, value) == (5, 5400, 6000, 8400), (std, into, size, value)
assert L.eval("ReputationKing.GetOrder(264037).count") == 200 and L.eval("ReputationKing.GetOrder(1)") is None
assert L.eval("ReputationKing.SecondsToReset()") > 0
for k, v in L.eval("ReputationKing").items():
    assert k == "API_VERSION" or callable(v) or L.eval("type(ReputationKing['%s'])" % k) == "function", k
print("API OK")

# --- 13. /rep, the pages, every tab, Settings ----------------------------------------------------------------------
L.execute("SLASH('/rep')"); assert KM.IsShown("writs")
L.execute("SLASH('/rep')"); assert not KM.IsShown("writs")
L.execute("SLASH('/reputation overview')"); assert KM.IsShown("reputation")
L.execute("SLASH('/km writs')"); assert KM.IsShown("writs")
L.execute("SLASH('/rep status')"); assert any("Azeroth Commerce Authority:" in o for o in outputs(L))
L.execute("SLASH('/rep remind off')"); assert db().settings.remind is False
L.execute("SLASH('/rep remind on')"); assert db().settings.remind is True
L.execute("SLASH('/rep badge off')"); assert db().settings.badge is False
L.execute("SLASH('/rep badge')"); assert db().settings.badge is True
L.execute("SLASH('/rep debug')"); assert "different orders held" in last(L)
L.execute("SLASH('/rep help')"); assert "/rep debug" in last(L)
open_every_page(L, KM)
P = ns.page
for tab in ["held", "cheap", "favor", "all", "chars"]:
    db().ui.tab = tab
    KM.Show("writs")
    assert not KM.errorShown, (tab, last(L))
    assert P.tables[tab].data is not None
db().ui.tab = "all"; db().ui.tier = "A"; db().ui.prof = 8; KM.Show("writs")
assert len(list(P.tables["all"].data.values())) == 9 and all(r.order.tier == "A" and r.order.prof == 8 for r in P.tables["all"].data.values())
db().ui.tier = None; db().ui.prof = None; db().ui.held = True; KM.Show("writs")
assert len(list(P.tables["all"].data.values())) == 3
db().ui.held = False
assert P.tiles[2].value.text == "3" and P.tiles[3].labelText == "Rep today"
db().ui.tab = "held"; KM.Show("writs")
assert len(list(P.tables["held"].data.values())) == 3
KM.Show("reputation")
ov = ns.overview.table.data
assert len(list(ov.values())) == 1 and ov[1].f.factionID == ACA and ov[1].page == "writs"
# every tooltip on the page draws: tiles, the progress strip, column headers, the rows of every tab
GT = L.eval("GameTooltip")
for tab in ["held", "cheap", "favor", "all", "chars"]:
    db().ui.tab = tab; KM.Show("writs")
    t = P.tables[tab]
    for r in t.rows.values():
        if r.data and r.tip:
            r.tip(GT)
    for h in t.headers.values():
        h.RunScript(h, "OnEnter")
for tile in P.tiles.values():
    tile.RunScript(tile, "OnEnter")
P.progress.RunScript(P.progress, "OnEnter")
for r in ns.overview.table.rows.values():
    if r.data and r.tip:
        r.tip(GT)
assert not KM.errorShown, last(L)
assert len([r for r in P.tables["held"].rows.values() if r.data]) == 3, "the held tab draws its rows"
KM.OpenSettings("reputation")
assert not KM.errorShown
print("PAGES OK")

# --- 14. no APIs: nothing errors ----------------------------------------------------------------------------------
BARE = EXTRA + """
C_Reputation = nil; GetFactionInfoByID = nil; C_DateAndTime = nil; GetQuestResetTime = nil; C_CurrencyInfo = nil
C_QuestLog.IsQuestFlaggedCompleted = nil; GetQuestID = nil
"""
L4, KM4 = fresh(only=MODS, extra=BARE)
n4 = KM4.mods.Reputation
secs, guessed = n4.SecondsToReset()
assert not guessed and 0 < secs <= DAY
c4 = L4.eval("ReputationKingDB.chars['Jay-Forever']")
assert c4.favor is None and n4.CharStanding(c4) is None and c4.dayEnd
L4.execute("TURN_IN(94004, false); FIRE('QUEST_COMPLETE'); FIRE('UPDATE_FACTION'); RUN_TIMERS()")
assert n4.DoneToday(c4)[0] == 1
open_every_page(L4, KM4)
for tab in ["held", "cheap", "favor", "all", "chars"]:
    L4.execute("ReputationKingDB.ui.tab = '%s'" % tab); KM4.Show("writs")
L4.execute("SLASH('/rep status'); SLASH('/rep debug')")
assert not KM4.errorShown, last(L4)
# Reputation alone (no Scanner, Market, Inventory): costs are unknown, nothing breaks
L5, KM5 = fresh(only=["Reputation"], extra=EXTRA)
n5 = KM5.mods.Reputation
assert n5.ItemCost(3391)[0] is None and n5.CheapestRep()[1].perRep is None
open_every_page(L5, KM5)
for tab in ["held", "cheap", "favor", "all", "chars"]:
    L5.execute("ReputationKingDB.ui.tab = '%s'" % tab); KM5.Show("writs")
assert not KM5.errorShown, last(L5)
print("BARE OK")

print("reputation: all checks passed")
