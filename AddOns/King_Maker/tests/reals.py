# Reals (new in 2.13): Tarnished Undermine Reals per boss per day. Checked: the generated boss list, the currency found
# on the currency tab (and from a loot link), held and the cap, a Real in a loot window credited to the boss it came
# from when the slot clears (and when the window closes with the count up), a Real left behind (warning), the miss
# count that stops a boss counting and a drop that brings it back, a boss the list didn't have learned into its
# dungeon, the boss-down pop-up (encounter event, a dead target with loot), once a visit, only while its Real is due,
# the switch, the leaving reminder, the daily reset, dungeon green/red states, other characters, /reals, the page,
# Settings, InitDB twice, and nothing erroring without the loot, currency, encounter and reset APIs.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page

CUR = 3517
WITHER, IMPAAN, BEHEMOTH = 247195, 247206, 247207
EXTRA = """
CURRENCY_LIST = { { name = "Honor", currencyID = 1901, quantity = 0 }, { name = "Tarnished Undermine Real", currencyID = %d, quantity = 7 } }
CURRENCY[%d] = 7; CURRENCY_MAX[%d] = 250
""" % (CUR, CUR, CUR)
SEED = """
RealsKingDB = { chars = { ["Kay-Forever"] = { name = "Kay", class = "MAGE", seen = 900, dayEnd = 1000 + 3600, got = { [247195] = 950 }, held = 40 },
  ["Old-Forever"] = { name = "Old", seen = 500, dayEnd = 800, got = { [247206] = 700 } } } }
"""

L, KM = fresh(only=["Reals"], extra=EXTRA, seed=SEED)
ns = KM.mods.Reals
db = lambda: L.eval("RealsKingDB")
me = lambda: L.eval("RealsKingDB.chars['Jay-Forever']")
run = lambda code: L.execute(code + "; RUN_TIMERS()")
G = lambda npc, n=1: "Creature-0-1-2-3-%d-%04d" % (npc, n)
REAL = lambda: '{ link = "|cff1eff00|Hcurrency:%d:0|h[Tarnished Undermine Real]|h|r", name = "Tarnished Undermine Real", qty = 1 }' % CUR

def slot(link_entry, *guids):
    srcs = ", ".join('"%s", 1' % g for g in guids)
    return link_entry[:-1] + ", sources = { %s } }" % srcs

# --- 1. data and loading ------------------------------------------------------------------------------------------
names = [d.name for d in ns.DUNGEONS.values()]
assert "Blackmaw Hold" in names and "Shaper's Terrace" in names and "Scholomance" in names and "Upper Blackrock Spire" in names
assert ns.BOSS[WITHER].name == "Withermaw" and ns.BOSS[WITHER].dungeon.name == "Blackmaw Hold"
assert ns.BOSS[269104] is None, "rares aren't on the list"
assert ns.BOSS[9025] is None, "Lord Roccor (51) is under 55"
assert ns.BOSS[11032].optional, "Malor is summoned"
s = db().settings
assert s.notify is True and s.leave is True and s.sound is None and db().version == 1
assert db().currency == CUR, "found on the currency tab"
c = me()
assert c.held == 7 and c.cap == 250 and c.dayEnd > L.eval("NOW")
ns.InitDB(); ns.InitDB()
assert me().held == 7 and len(list(ns.DUNGEONS.values())) == len(names)
assert KM.pages.reals.group == "farm"
print("LOAD OK")

# --- 2. states: everything green, Kay's Withermaw red, Old's day is over --------------------------------------------
bh = [st for st in ns.States(me()).values() if st.d.name == "Blackmaw Hold"][0]
assert bh.done == 0 and bh.left == bh.total == 7, (bh.done, bh.left, bh.total)   # 7 non-rare bosses
kay = L.eval("RealsKingDB.chars['Kay-Forever']")
assert ns.Got(kay, WITHER) and ns.Totals(kay)[0] == 1
old = L.eval("RealsKingDB.chars['Old-Forever']")
assert not ns.Got(old, IMPAAN) and ns.Totals(old)[0] == 0, "the reset passed since Old was on"
print("STATES OK")

# --- 3. a boss goes down: the pop-up, once a visit -------------------------------------------------------------------
run('INSTANCE = true; INSTANCE_NAME = "Blackmaw Hold"; FIRE("ZONE_CHANGED_NEW_AREA")')
assert ns.visit and ns.visit.dungeon.name == "Blackmaw Hold"
n0 = ns.toasts
run('FIRE("ENCOUNTER_END", 3001, "Withermaw", 1, 5, 1)')
assert ns.toasts == n0 + 1 and "Withermaw may have a Real for you" in ns.lastToast, ns.lastToast
run('FIRE("ENCOUNTER_END", 3001, "Withermaw", 1, 5, 1)')
assert ns.toasts == n0 + 1, "once a visit"
run('FIRE("ENCOUNTER_END", 3002, "Impaan the Imprisoner", 1, 5, 0)')
assert ns.toasts == n0 + 1, "a wipe isn't a kill"
# a dead boss you target, still lootable
run('UNITS.target = { guid = "%s", name = "Blackmaw Behemoth", dead = true }; LOOTABLE["%s"] = true; FIRE("PLAYER_TARGET_CHANGED")' % (G(BEHEMOTH), G(BEHEMOTH)))
assert ns.toasts == n0 + 2 and "Blackmaw Behemoth" in ns.lastToast
print("BOSS DOWN OK")

# --- 4. looting: credited to the corpse it came from -------------------------------------------------------------------
run('OPEN_LOOT({ %s, { link = LINK(2589), qty = 2, sources = { "%s", 2 } } })' % (slot(REAL(), G(WITHER)), G(WITHER)))
assert db().drops[WITHER] == 1 and not ns.Got(me(), WITHER), "seen, not taken yet"
run('FIRE("LOOT_SLOT_CLEARED", 1); CURRENCY[%d] = 8; CLOSE_LOOT()' % CUR)
assert ns.Got(me(), WITHER) and me().held == 8
assert ns.visit.killed[WITHER] is None
# the pop-up never comes for a boss already looted today
n1 = ns.toasts
run('ns_visit_reset = true'); ns.visit.told = L.table(); run('FIRE("ENCOUNTER_END", 3001, "Withermaw", 1, 5, 1)')
assert ns.toasts == n1
# fast auto-loot with no clear event: the count going up credits it
L.execute("CURRENCY[%d] = 8" % CUR)
run('OPEN_LOOT({ %s })' % slot(REAL(), G(IMPAAN)))
run('CURRENCY[%d] = 9; CLOSE_LOOT()' % CUR)
assert ns.Got(me(), IMPAAN), "count up at close"
print("LOOT OK")

# --- 5. left behind: a warning, and it stays green ------------------------------------------------------------------------
n2 = ns.toasts
run('OPEN_LOOT({ %s })' % slot(REAL(), G(BEHEMOTH)))
run('CLOSE_LOOT()')
assert ns.toasts == n2 + 1 and "You left a Real on Blackmaw Behemoth" in ns.lastToast
assert not ns.Got(me(), BEHEMOTH) and db().drops[BEHEMOTH] == 1
# and on leaving the dungeon, the reminder names it
n3 = ns.toasts
run('INSTANCE = false; FIRE("ZONE_CHANGED_NEW_AREA")')
assert ns.visit is None and ns.toasts == n3 + 1 and "You left without looting 1 Real: Blackmaw Behemoth" in ns.lastToast, ns.lastToast
print("LEFT BEHIND OK")

# --- 6. misses: a boss that never shows one stops counting; a drop brings it back ---------------------------------------
UNB = 247231
run('INSTANCE = true; FIRE("ZONE_CHANGED_NEW_AREA")')
for i in range(3):
    run('OPEN_LOOT({ { link = LINK(2589), qty = 1, sources = { "%s", 1 } } }); CLOSE_LOOT()' % G(UNB, i + 1))
run('OPEN_LOOT({ { link = LINK(2589), qty = 1, sources = { "%s", 1 } } }); CLOSE_LOOT()' % G(UNB, 1))
assert db().misses[UNB] == 3, "the same corpse counts once"
assert ns.NoDrop(ns.BOSS[UNB])
n4 = ns.toasts
run('FIRE("ENCOUNTER_END", 3009, "Unbound Spirit", 1, 5, 1)'); assert ns.toasts == n4, "not counted: no pop-up"
run('OPEN_LOOT({ %s }); FIRE("LOOT_SLOT_CLEARED", 1); CLOSE_LOOT()' % slot(REAL(), G(UNB, 9)))
assert not ns.NoDrop(ns.BOSS[UNB]) and db().misses[UNB] is None and ns.Got(me(), UNB)
print("MISSES OK")

# --- 7. a boss the list didn't have: learned into the dungeon you're in -------------------------------------------------
NEW = 280001
run('UNITS.target = { guid = "%s", name = "Gloomroot", level = 60, dead = true }' % G(NEW))
run('OPEN_LOOT({ %s }); FIRE("LOOT_SLOT_CLEARED", 1); CLOSE_LOOT()' % slot(REAL(), G(NEW)))
b = ns.BOSS[NEW]
assert b and b.name == "Gloomroot" and b.learned and b.dungeon.name == "Blackmaw Hold" and ns.Got(me(), NEW)
assert db().learned[NEW].dungeon == "Blackmaw Hold"
ns.InitDB()
assert ns.BOSS[NEW] and ns.BOSS[NEW].dungeon.name == "Blackmaw Hold", "kept after a reload"
assert len([x for x in ns.BOSS[NEW].dungeon.bosses.values() if x.npc == NEW]) == 1, "not added twice"
run('INSTANCE = false; FIRE("ZONE_CHANGED_NEW_AREA")')
print("LEARN OK")

# --- 8. switch off; the reset; the API ------------------------------------------------------------------------------------
L.execute("SlashCmdList.REALSKING('notify off')"); assert db().settings.notify is False
n5 = ns.toasts
run('INSTANCE = true; FIRE("ZONE_CHANGED_NEW_AREA"); FIRE("ENCOUNTER_END", 1, "Bonesnout the Unbroken", 1, 5, 1)')
assert ns.toasts == n5
run('INSTANCE = false; FIRE("ZONE_CHANGED_NEW_AREA")')
assert ns.toasts == n5 + 1 and "Bonesnout" in ns.lastToast, "the leaving reminder has its own switch"
L.execute("SlashCmdList.REALSKING('notify on'); SlashCmdList.REALSKING('leave off')")
assert db().settings.notify is True and db().settings.leave is False
assert L.eval("RealsKing.GotToday(%d)" % WITHER) is True and L.eval("RealsKing.GotToday(%d)" % 247198) is False
got, left, dl = L.eval("{ RealsKing.Today() }").values()
assert got == 4 and dl >= 11, (got, left, dl)
assert L.eval("RealsKing.Held()") == (9, 250)
L.execute("NOW = NOW + 7 * 3600; RESET_IN = 17 * 3600")   # past the reset
assert not ns.Got(me(), WITHER) and L.eval("RealsKing.Today()")[0] == 0
ns.CheckDay(me()); assert len(list(me().got.keys())) == 0
print("RESET OK")

# --- 9. /reals, the page, settings -------------------------------------------------------------------------------------------
L.execute("SlashCmdList.REALSKING('status')")
assert any("looted today" in o for o in outputs(L)), outputs(L)[-3:]
L.execute("SlashCmdList.REALSKING('debug'); SlashCmdList.REALSKING('help')")
assert L.eval("SLASH_REALSKING1") == "/reals"
open_every_page(L, KM)
assert not KM.errorShown
KM.Show("reals"); P = ns.page
assert P.dungeons.data[1] and P.bosses.data[1]
L.execute("RealsKingDB.ui.char = 'Kay-Forever'"); KM.Refresh("reals")
assert P.charBtn.label.GetText(P.charBtn.label).startswith("Kay")
L.execute("SlashCmdList.REALSKING('forget Kay')"); assert db().chars["Kay-Forever"] is None and db().ui.char is None
KM.Refresh("reals"); assert not KM.errorShown
print("PAGE OK")

# --- 10. nothing errors without the APIs ------------------------------------------------------------------------------------
L2, KM2 = fresh(only=["Reals"], extra="""
GetLootSourceInfo = nil; CanLootUnit = nil; C_CurrencyInfo = nil; C_DateAndTime = nil; GetQuestResetTime = nil
GetInstanceInfo = nil
""")
ns2 = KM2.mods.Reals
L2.execute('INSTANCE = true; FIRE("ZONE_CHANGED_NEW_AREA"); FIRE("ENCOUNTER_END", 1, "Withermaw", 1, 5, 1)')
L2.execute('OPEN_LOOT({ { link = "x", name = "Tarnished Undermine Real", qty = 1 } }); FIRE("LOOT_SLOT_CLEARED", 1); CLOSE_LOOT(); RUN_TIMERS()')
L2.execute("SlashCmdList.REALSKING('status'); SlashCmdList.REALSKING('debug')")
open_every_page(L2, KM2)
assert not KM2.errorShown, L2.eval("OUTPUT[#OUTPUT]")
print("NO API OK")
print("REALS OK")
