# Cooldowns (new in 2.6): crafting cooldowns on every character. Checked: the catalogue against Market's recipe data,
# readings turned into server-time timestamps (spell, item, recipe window, cast estimates), the trust rules (a spell
# API "ready" can't erase a known timer), the wrap fix and the sanity cap, combat and secret values, the shared
# transmute group and split detection, discovery, the Salt Shaker, cross-character rows, the badge in each mode (table
# and plain string), money (profit each, per week, gold per day, picks, idle), the Shopping provider, the Scanner watch,
# reminders (chat, toast, sound, login line, alts), professions lost, /cdk, the page and that nothing ever crafts.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page

MODS = ["Scanner", "Econ", "Market", "Inventory", "Shopping", "Profession", "Cooldowns"]
DAY = 86400

EXTRA = """
ITEM(14256, "Felcloth", { class = 7 }); ITEM(14342, "Mooncloth", { class = 7 })
ITEM(12360, "Arcanite Bar", { class = 7 }); ITEM(12359, "Thorium Bar", { class = 7 }); ITEM(12363, "Arcane Crystal", { class = 7 })
ITEM(12803, "Living Essence", { class = 7 }); ITEM(7076, "Essence of Earth", { class = 7 })
ITEM(9149, "Philosopher's Stone", { class = 15 }); ITEM(15846, "Salt Shaker", { class = 15 })
ITEM(8150, "Deeprock Salt", { class = 7 }); ITEM(15409, "Refined Deeprock Salt", { class = 7 })
ITEM(99777, "Forever Silk", { class = 7 }); ITEM(99778, "Quick Thing", { class = 7 })
UPTIME = 100000   -- the client has been up a while (start times are GetTime() seconds)
SOUNDKIT = SOUNDKIT or {}; SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 120
SOUNDS = {}; function PlaySound(id) SOUNDS[#SOUNDS + 1] = id end
-- nothing may ever craft
CRAFTED = {}
DoTradeSkill = function() CRAFTED[#CRAFTED + 1] = "DoTradeSkill" end
C_TradeSkillUI.CraftRecipe = function() CRAFTED[#CRAFTED + 1] = "CraftRecipe" end
CastSpellByID = function() CRAFTED[#CRAFTED + 1] = "CastSpellByID" end
PROFS = { { name = "Tailoring", cur = 300, max = 300 }, { name = "Alchemy", cur = 300, max = 300 } }
KNOWN_SPELLS[18560] = true
BAGS[0][1] = { id = 14256, count = 1 }
"""

SEED = """
ScannerKingDB = { prices = {
  [14256] = { p = 5000, t = 990, q = 20 }, [14342] = { p = 30000, t = 990, q = 5 },
  [12360] = { p = 150000, t = 990, q = 3 }, [12359] = { p = 4000, t = 990 }, [12363] = { p = 60000, t = 990 },
  [12803] = { p = 20000, t = 990 }, [7076] = { p = 8000, t = 990 } } }
"""

L, KM = fresh(only=MODS, extra=EXTRA, seed=SEED)
ns = KM.mods.Cooldowns
db = lambda: L.eval("CooldownKingDB")
me = lambda: L.eval("CooldownKingDB.chars['Jay-Forever']")
NOW = lambda: L.eval("NOW")
WRAP = 2 ** 32 / 1000
read = lambda event="SPELL_UPDATE_COOLDOWN": L.execute(f"FIRE('{event}'); RUN_TIMERS()")

# --- 1. loads, saved data, the page --------------------------------------------------------------------------------
assert L.eval("CooldownKing.API_VERSION") == 1
assert db().version == 1 and db().settings.badge == "here+alts" and db().settings.days == 7
assert db().settings.chat is True and db().settings.altChat is False and db().settings.noToolCounts is False
c = me()
assert c.name == "Jay" and c.realm == "Forever" and c["class"] == "WARRIOR" and c.faction == "Alliance" and c.level == 42
assert c.profs[8] == 300 and c.profs[4] == 300
moon = c.cds.mooncloth
assert moon and moon.known[18560], "Mooncloth known (spellbook) and tracked"
assert moon.ready == NOW() and moon.readySince == NOW(), "first reading 0/0: ready, no reminder"
assert c.unread.transmute and not c.cds.transmute, "an alchemist who knows no transmute yet: 'open Alchemy once'"
assert not any("Mooncloth is ready" in o for o in outputs(L)), "no reminder for a first reading"
before = (db().settings.badge, db().settings.days, len(list(c.cds.keys())))
ns.InitDB(); ns.InitDB()
assert (db().settings.badge, db().settings.days, len(list(me().cds.keys()))) == before and me().cds.mooncloth.ready == NOW()
p = KM.pages.cooldowns
assert p.group == "craft" and p.order == 30 and p.crownBadge
L.execute("SLASH('/cdk')"); assert KM.IsShown("cooldowns")
L.execute("SLASH('/cdk')"); assert not KM.IsShown("cooldowns")
L.execute("SLASH('/km cooldowns')"); assert KM.IsShown("cooldowns")
open_every_page(L, KM)
assert not KM.errorShown
print("LOAD OK")

# --- 2. the catalogue against Market's data --------------------------------------------------------------------------
M = KM.mods.Market
for spell, cat in ns.CATALOGUE.items():
    if spell == 19566:
        continue
    r = M.Recipe(spell)
    assert r, f"Market knows {spell}"
    assert r.prof == ns.GROUPS[cat.group].prof, f"{spell} in its group's profession"
leg = M.Recipe(1317279)
assert leg.item == 251290 and list(leg.reagents.values()) == [251291, 1, 248819, 1]
assert ns.GroupOf(17187) == "transmute" and ns.GroupOf(1317279) == "transmute" and ns.GroupOf(18560) == "mooncloth"
assert ns.GroupOf(2661) is None
assert len(ns.Members("transmute")) == 12 and list(ns.Members("mooncloth").values()) == [18560]
salt = ns.Recipe(19566)
assert salt.item == 15409 and salt.prof == 3 and list(salt.reagents.values()) == [8150, 1]
print("CATALOGUE OK")

# --- 3. the spell API on cooldown -> a server-time timestamp ---------------------------------------------------------
assert not db().trust.spell
L.execute("SPELL_CD[18560] = { UPTIME - 3600, 345600 }")
read()
moon = me().cds.mooncloth
assert moon.ready == NOW() + 345600 - 3600 and moon.src == "spell" and moon.dur == 345600 and not moon.readySince
assert db().learned[18560].dur == 345600 and db().trust.spell == NOW()
assert ns.Dur(18560) == 345600
print("SPELL OK")

# --- 5. the wrap fix and the sanity cap -----------------------------------------------------------------------------
assert abs(ns.Left(L.eval("UPTIME") + WRAP - 100, 1000) - 900) < 1
assert ns.Left(0, 0) == 0 and ns.Left(L.eval("UPTIME"), 1.5) == 0, "not on cooldown / just the GCD"
assert ns.Left(None, 10) is None
L.execute(f"SPELL_CD[18560] = {{ UPTIME + {WRAP} - 7200, 345600 }}")
read()
assert abs(me().cds.mooncloth.ready - (NOW() + 345600 - 7200)) <= 1, "start 'in the future' corrected"
L.execute("SPELL_CD[18560] = { UPTIME, 10 * 86400 }")   # longer than 1.5x the length: garbage
read()
assert abs(me().cds.mooncloth.ready - (NOW() + 345600 - 7200)) <= 1, "garbage kept out"
print("WRAP OK")

# --- 6. combat and secret values ------------------------------------------------------------------------------------
L.execute("SPELL_CD[18560] = { UPTIME - 100, 345600 }; COMBAT = true")
read()
assert abs(me().cds.mooncloth.ready - (NOW() + 345600 - 7200)) <= 1, "nothing read in combat"
assert ns.IsDeferred()
L.execute("COMBAT = false")
read("PLAYER_REGEN_ENABLED")
assert me().cds.mooncloth.ready == NOW() + 345600 - 100, "read after the fight"
L.execute("SECRET_CD = true; SPELL_CD[18560] = { UPTIME, 345600 }")
read()
assert me().cds.mooncloth.ready == NOW() + 345600 - 100 and not KM.errorShown, "secret: skipped silently"
L.execute("SECRET_CD = false")
print("COMBAT OK")

# --- 7. the shared transmute group, the stone, the badge -------------------------------------------------------------
L.execute("KNOWN_SPELLS[17187] = true; KNOWN_SPELLS[17566] = true; BAGS[0][5] = { id = 9149 }")
read("SKILL_LINES_CHANGED")
c = me()
tm = c.cds.transmute
assert tm and tm.known[17187] and tm.known[17566] and not c.unread.transmute
assert len([k for k in c.cds.keys()]) == 2, "one transmute line for every transmute"
assert tm.ready == NOW() and c.tools[9149] is True
assert KM.BadgeTables is True, "the Shell draws count badges (red disc)"
b = ns.Badge()
assert b.count == 1 and b.color == "red" and "Transmute is ready on Jay" in b.tip
assert p.badge().count == 1
L.execute("BAGS[0][5] = nil")
read("BAG_UPDATE_DELAYED")
assert me().tools[9149] is False and ns.Badge() is None, "no stone: a transmute you can't do doesn't count"
db().settings.noToolCounts = True
assert ns.Badge().count == 1
db().settings.noToolCounts = False
L.execute("BAGS[0][5] = { id = 9149 }"); read("BAG_UPDATE_DELAYED")
print("SHARED OK")

# --- 8. the profession window: authoritative timer, discovery --------------------------------------------------------
L.execute("""
TRADESKILL = { name = "Alchemy", recipes = {
  [17187] = { output = 12360, reagents = { { 12359, 1 }, { 12363, 1 } }, cd = 3600 },
  [17566] = { output = 12803, reagents = { { 7076, 1 } } },
  [999777] = { output = 99777, reagents = { { 7076, 2 } }, cd = 3 * 86400 },
  [999778] = { output = 99778, reagents = { { 7076, 1 } }, cd = 600 },
  [999779] = { output = 99778, reagents = { { 7076, 1 } }, cd = 3 * 86400, learned = false },
} }
""")
read("TRADE_SKILL_LIST_UPDATE")
c = me()
assert c.cds.transmute.ready == NOW() + 3600 and c.cds.transmute.src == "recipe"
assert db().learned[999777].group == "r:999777" and db().learned[999777].prof == 4 and db().learned[999777].dur == 3 * DAY
assert c.cds["r:999777"].ready == NOW() + 3 * DAY and c.read[4] == NOW()
assert not db().learned[999778], "under two hours: never discovered"
assert not db().learned[999779], "not learned: not ours"
assert any("found 1 more crafting cooldown" in o for o in outputs(L))
assert ns.Group("r:999777").label == "Forever Silk" and ns.Group("r:999777").discovered
assert "r:999777" in list(ns.GroupKeys().values())
rows = ns.Entries("all")
assert any(r.gk == "r:999777" for r in rows.values())
# the window's "ready" (nil) is believed both ways
L.execute("TRADESKILL.recipes[17187].cd = nil")
read("TRADE_SKILL_UPDATE")
assert me().cds.transmute.ready == NOW()
L.execute("TRADESKILL = nil")
print("WINDOW OK")

# --- 9. a craft: logged, estimated, then replaced by the game's number ----------------------------------------------
L.execute("SPELL_CD[18560] = { 0, 0 }")
read()
L.execute("FIRE('UNIT_SPELLCAST_SUCCEEDED', 'target', 'Cast-0', 18560)")
assert len(list(me().log.keys())) == 0, "someone else's cast"
L.execute("FIRE('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 18560)")
c = me()
assert c.log[1][1] == NOW() and c.log[1][2] == "mooncloth" and c.log[1][3] == 18560
assert c.cds.mooncloth.est is True and c.cds.mooncloth.ready == NOW() + 345600 and c.cds.mooncloth.src == "cast"
L.execute("SPELL_CD[18560] = { UPTIME, 345600 }; RUN_TIMERS()")
assert me().cds.mooncloth.est is None and me().cds.mooncloth.src == "spell"
assert ns.LastCast().spell == 18560
print("CAST OK")

# --- 4. trust: a spell API "ready" can't erase a timer we know -------------------------------------------------------
L2, KM2 = fresh(only=MODS, extra=EXTRA, seed=SEED)
n2 = KM2.mods.Cooldowns
L2.execute("FIRE('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 18560); RUN_TIMERS()")
m2 = L2.eval("CooldownKingDB.chars['Jay-Forever'].cds.mooncloth")
assert not L2.eval("CooldownKingDB.trust.spell")
assert m2.ready == L2.eval("NOW") + 4 * DAY and m2.est, "unproven 0/0 ignored: the estimate stays"
L2.execute("FIRE('SPELL_UPDATE_COOLDOWN'); RUN_TIMERS()")
assert m2.ready == L2.eval("NOW") + 4 * DAY
L2.execute("CooldownKingDB.trust.spell = 1; FIRE('SPELL_UPDATE_COOLDOWN'); RUN_TIMERS()")
assert m2.ready == L2.eval("NOW") + 4 * DAY, "the API lags a craft: a fresh estimate stays"
L2.execute("ADVANCE(601); FIRE('SPELL_UPDATE_COOLDOWN'); RUN_TIMERS()")
assert m2.ready == L2.eval("NOW") and m2.readySince == L2.eval("NOW"), "proven API: 0/0 means ready"
o2 = list(L2.eval("OUTPUT").values())
assert sum("Mooncloth is ready" in o for o in o2) == 1, "one chat line on the flip"
assert "Best: Mooncloth" in [o for o in o2 if "Mooncloth is ready" in o][0]
assert n2.toasts == 1 and n2.lastToast == "Mooncloth is ready" and L2.eval("SOUNDS[#SOUNDS]") == 120
print("TRUST OK")

# --- 10. the Salt Shaker --------------------------------------------------------------------------------------------
L.execute("""
PROFS[3] = { name = "Leatherworking", cur = 260, max = 300 }
BAGS[0][6] = { id = 15846 }
ITEM_CD[15846] = { UPTIME - 60, 259200 }
""")
read("BAG_UPDATE_DELAYED")
s = me().cds.salt
assert s and s.src == "item" and s.ready == NOW() + 259200 - 60 and s.known[19566]
# a loading screen: the item API reads 0/0 for a moment. Not ready, no reminder; a real reading clears the doubt
n0 = len(outputs(L))
L.execute("ITEM_CD[15846] = { 0, 0 }"); read("PLAYER_ENTERING_WORLD")
assert s.ready == NOW() + 259200 - 60 and not s.readySince, "a 0/0 blip doesn't end a 3-day timer"
assert not any("Refined Salt is ready" in o for o in outputs(L)[n0:]), "no reminder on a blip"
L.execute("ITEM_CD[15846] = { UPTIME - 60, 259200 }"); read("BAG_UPDATE_COOLDOWN")
L.execute("ITEM_CD[15846] = { 0, 0 }; ADVANCE(704)"); read("BAG_UPDATE_COOLDOWN")
assert s.ready > NOW() and not s.readySince, "doubt restarts after a real reading"
# a 0/0 that holds for 10 minutes is believed (the timer really was wrong). 704 + 601 = a whole number of 15 s ticks,
# so the reminder checks further down keep their phase
L.execute("ADVANCE(601)"); read("BAG_UPDATE_COOLDOWN")
assert s.ready == NOW() and s.readySince == NOW(), "a ready that holds is believed"
L.execute("BAGS[0][6] = nil")
read("BAG_UPDATE_DELAYED")
assert not me().cds.salt, "no shaker: no salt line"
print("SALT OK")

# --- 11. split: a transmute that doesn't share the cooldown gets its own line ----------------------------------------
L.execute("""
KNOWN_SPELLS[1317279] = true
SPELL_CD[17187] = { 0, 0 }; SPELL_CD[17566] = { 0, 0 }
FIRE('SKILL_LINES_CHANGED'); RUN_TIMERS()
SPELL_CD[1317279] = { UPTIME, 47 * 3600 }
FIRE('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-2', 1317279); RUN_TIMERS()
""")
assert db().learned[1317279].split is True
assert ns.GroupOf(1317279) == "r:1317279"
c = me()
assert c.cds["r:1317279"].ready == NOW() + 47 * 3600 and c.cds.transmute.ready == NOW()
assert not c.cds.transmute.known[1317279]
assert any("has a cooldown of its own" in o for o in outputs(L))
print("SPLIT OK")

# --- 13. money -------------------------------------------------------------------------------------------------------
v = ns.Value(18560)
assert v.profit == 18500 and v.cost == 10000 and v.sale == 28500
assert ns.PerWeek(18500, 4 * DAY) == 32375 and ns.PerDay(78500, 2 * DAY) == 39250
ch = ns.Choices("Jay-Forever", "transmute")
assert ch[1].spell == 17187 and ch[1].perDay == 39250 and ch[2].spell == 17566 and ch[2].perDay == 11000
assert ns.Pick("Jay-Forever", "transmute")[0] == 17187
ns.SetPick("Jay-Forever", "transmute", 17566)
assert ns.Pick("Jay-Forever", "transmute")[0] == 17566 and me().pick.transmute == 17566
ns.SetPick("Jay-Forever", "transmute", 17187)
assert me().pick.transmute is None, "picking the best clears the pick"
L.execute("MarketKingDB.mode = 'farm'")
assert ns.Value(18560).profit == ns.Value(18560).farmGain and ns.Value(18560).buyProfit == 18500
L.execute("MarketKingDB.mode = 'buy'")
print("MONEY OK")

# --- 14. idle --------------------------------------------------------------------------------------------------------
L.execute("local e = CooldownKingDB.chars['Jay-Forever'].cds.mooncloth; e.ready = NOW - 2 * 86400; e.readySince = NOW - 2 * 86400")
secs, crafts, gold = ns.Idle("Jay-Forever", "mooncloth")
assert secs == 2 * DAY and abs(crafts - 0.5) < 1e-9 and abs(gold - 9250) < 1e-6
ws, wc, wg = ns.IdleWeek("Jay-Forever", "mooncloth")
assert ws == 2 * DAY and abs(wg - 9250) < 1e-6
print("IDLE OK")

# --- 12. cross-character -------------------------------------------------------------------------------------------
L.execute("""
for _, e in pairs(CooldownKingDB.chars['Jay-Forever'].cds) do e.ready = NOW + 1000; e.readySince = nil end
CooldownKingDB.chars['Bob Stone-Forever'] = { name = 'Bob Stone', realm = 'Forever', class = 'MAGE', faction = 'Alliance', level = 60,
  seen = NOW, profs = { [4] = 300 }, tools = { [9149] = true }, pick = {}, hide = {}, log = {}, unread = {}, read = {},
  cds = { transmute = { ready = NOW - 7200, readySince = NOW - 7200, known = { [17187] = true } } } }
""")
b = ns.Badge()
assert b.count == 1 and b.color == "gold" and "Transmute is ready on Bob Stone" in b.tip, "here+alts: alts in gold"
db().settings.badge = "any"; b = ns.Badge(); assert b.count == 1 and b.color == "red"
db().settings.badge = "here"; assert ns.Badge() is None
db().settings.badge = "here+alts"
assert L.eval("CooldownKing.ReadyCount('alts')") == 1 and L.eval("CooldownKing.ReadyCount('here')") == 0 and L.eval("CooldownKing.ReadyCount()") == 1
all_ = L.eval("CooldownKing.GetAll()")
assert any(r.char == "Bob Stone-Forever" and r.group == "transmute" and r.left == 0 for r in all_.values())
assert L.eval("CooldownKing.Length(18560)") == 345600 and L.eval("CooldownKing.Length(2661)") is None
assert ns.FindChar("Bob Stone") == "Bob Stone-Forever" and ns.FindChar("bob") == "Bob Stone-Forever"
rows = ns.SortRows(ns.Entries("all"), "status")
assert rows[1].key == "Bob Stone-Forever" and rows[1].ready, "ready first"
assert all(r.key == "Jay-Forever" for r in ns.Entries("here").values())
print("CROSS OK")

# --- 16. the Scanner watches products and materials ------------------------------------------------------------------
watched = list(KM.mods.Scanner.WatchedItems().values())
assert 14342 in watched and 14256 in watched and 12360 in watched and 251290 in watched
print("SCANNER OK")

# --- 17. reminders --------------------------------------------------------------------------------------------------
L.execute("for _, e in pairs(CooldownKingDB.chars['Jay-Forever'].cds) do e.ready = NOW + 1000; e.readySince = nil end")
n = len(outputs(L))
L.execute("CooldownKingDB.chars['Jay-Forever'].cds.mooncloth.ready = NOW + 5; ADVANCE(15)")
new = outputs(L)[n:]
assert sum("Mooncloth is ready" in o for o in new) == 1, new
assert ns.toasts >= 1
db().settings.chat = False
n = len(outputs(L))
L.execute("CooldownKingDB.chars['Jay-Forever'].cds.mooncloth.ready = NOW + 5; CooldownKingDB.chars['Jay-Forever'].cds.mooncloth.readySince = nil; ADVANCE(15)")
assert not any("Mooncloth is ready" in o for o in outputs(L)[n:]), "chat off"
db().settings.chat = True
# an alt coming ready while you play someone else: nothing unless asked
n = len(outputs(L))
L.execute("local e = CooldownKingDB.chars['Bob Stone-Forever'].cds.transmute; e.ready = NOW + 5; e.readySince = nil; ADVANCE(15)")
assert not any("Bob Stone" in o for o in outputs(L)[n:])
db().settings.altChat = True
L.execute("local e = CooldownKingDB.chars['Bob Stone-Forever'].cds.transmute; e.ready = NOW + 5; e.readySince = nil; ADVANCE(15)")
assert "Transmute is ready on Bob Stone" in last(L)
db().settings.altChat = False
# the login line
ns.LoginLine()
assert "Ready on your alts: Transmute (Bob Stone)." in last(L) and "Here: Mooncloth." in last(L)
db().settings.login = False; n = len(outputs(L)); ns.LoginLine(); assert len(outputs(L)) == n
db().settings.login = True
print("REMIND OK")

# --- the page with rows, details and the menu ------------------------------------------------------------------------
L.execute("SLASH('/km cooldowns')")
assert len(list(ns.List().values())) >= 4 and not KM.errorShown
assert ns.IsTicking()
ns.table.rows[1].RunScript(ns.table.rows[1], "OnEnter")
assert not KM.errorShown
ns.table.rows[1].RunScript(ns.table.rows[1], "OnClick", "LeftButton")
assert db().ui.selected and ns.detail.row
ns.table.rows[1].RunScript(ns.table.rows[1], "OnClick", "RightButton")
assert L.eval("MENU_ITEM('Stop tracking this cooldown')") and L.eval("MENU_ITEM('Forget this character')")
L.execute("ADVANCE(15)")
assert not KM.errorShown
KM.OpenSettings("cooldowns")
assert not KM.errorShown
print("PAGE OK")

# --- slash ---------------------------------------------------------------------------------------------------------
n = len(outputs(L))
L.execute("SLASH('/cdk list')")
assert any("Mooncloth - Jay" in o for o in outputs(L)[n:])
L.execute("SLASH('/cdk badge any')"); assert db().settings.badge == "any"
L.execute("SLASH('/cdk badge alts')"); assert db().settings.badge == "here+alts"
L.execute("SLASH('/cdk remind off')"); assert db().settings.chat is False and db().settings.toast is False and db().settings.sound is False
L.execute("SLASH('/cdk remind on')"); assert db().settings.chat is True
L.execute("SLASH('/cdk scan')"); assert "read your cooldowns" in last(L)
L.execute("SLASH('/cdk debug')"); assert not KM.errorShown
L.execute("SLASH('/cdk help')"); assert "/cdk debug" in last(L)
L.execute("SLASH('/cooldownking forget Bob Stone')")
assert "forgot Bob Stone-Forever" in last(L) and not db().chars["Bob Stone-Forever"]
L.execute("SLASH('/cdk forget Nobody')"); assert "no character called Nobody" in last(L)
print("SLASH OK")

# --- rename, forgetting old characters ------------------------------------------------------------------------------
L.execute("CooldownKingDB.chars['Old-Forever'] = { name = 'Old', seen = NOW - 100 * 86400, cds = {} }")
assert ns.ForgetOld() == 1 and not db().chars["Old-Forever"]
ns.RenameChar("Jay-Forever", "Jay Smith-Forever")
assert db().chars["Jay Smith-Forever"] and not db().chars["Jay-Forever"]
ns.RenameChar("Jay Smith-Forever", "Jay-Forever")
print("RENAME OK")

# --- 18. a profession dropped takes its cooldowns (here only) -------------------------------------------------------
L.execute("""
CooldownKingDB.chars['Ann-Forever'] = { name = 'Ann', realm = 'Forever', seen = NOW, cds = { mooncloth = { ready = NOW - 5, readySince = NOW - 5, known = { [18560] = true } } } }
table.remove(PROFS, 1)
FIRE('SKILL_LINES_CHANGED'); RUN_TIMERS()
""")
assert not me().cds.mooncloth and me().cds.transmute, "Tailoring gone: Mooncloth gone here"
assert db().chars["Ann-Forever"].cds.mooncloth, "an alt keeps its own"
print("PROF LOST OK")

# --- the Profession panel line and Crafting Profits' CD tag ------------------------------------------------------
t = L.eval("CooldownKing.PanelText(17187, 78500)")
assert t
assert "2d" in t and "a week" in t
assert L.eval("CooldownKing.PanelText(2661, 100)") is None
L.execute("MarketKingDB.profs[4] = true; MarketKingDB.profs[8] = true")
L.execute("SLASH('/km crafting')")
assert not KM.errorShown
texts = [x for x in L.eval("TEXTS()").values()]
assert any("CD 2d" in x for x in texts if isinstance(x, str)), "cooldown recipes tagged on Crafting Profits"
print("INTEGRATIONS OK")

# --- 19. nothing crafts ---------------------------------------------------------------------------------------------
assert len(list(L.eval("CRAFTED").values())) == 0
assert len(list(L2.eval("CRAFTED").values())) == 0
assert not KM.errorShown and not KM2.errorShown
print("cooldowns: ok")
