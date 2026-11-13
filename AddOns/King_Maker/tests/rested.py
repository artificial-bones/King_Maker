# Rested (was Rested King): the rest maths, snapshots on events, the Well Rested perk, forgetting, sorting, /rk and
# the Rested XP page (table, sorting, right-click menu, live refresh), the crown, Home and Settings.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# The XP functions the shared mock lacks, and a context menu whose buttons can hold sub-items (radios).
EXTRA = """
XP, XPMAX, EXHAUSTION, RESTING, ZONE, MAXLEVEL = 1000, 10000, 2500, true, "Orgrimmar", 60
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
function GetXPExhaustion() return EXHAUSTION end
function IsResting() return RESTING end
function GetRealZoneText() return ZONE end
function GetMaxPlayerLevel() return MAXLEVEL end
MenuUtil.CreateContextMenu = function(owner, gen)
  local items = {}
  local function add(it) items[#items + 1] = it
    function it:CreateRadio(text, isSel, set) return add({ text = text, selected = isSel and isSel(), fn = function() return set and set() end }) end
    return it end
  local root = {}
  function root:CreateTitle(text) MENU_TITLE = text end
  function root:CreateButton(text, fn) return add({ text = text, fn = function() return fn and fn() end }) end
  gen(owner, root)
  MENU, MENU_OWNER = items, owner
end
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and rawget(f, "mark") then return f end end end
"""

H = 3600
L, KM = fresh(only=["Rested"], extra=EXTRA)
ns = KM.mods.Rested
rk = L.eval("SlashCmdList.RESTEDKING")
assert L.eval("RestedKing.API_VERSION") == 1
assert L.eval("RestedKingMinimapButton") is None and L.eval("RestedKingFrame") is None, "no button or window of its own"
assert L.eval("RestedKingDB.ui.sort") == "rested" and L.eval("RestedKingDB.ui.desc") is True

# --- the character you're on is noted at login ---------------------------------------
me = L.eval("RestedKingDB.chars['Jay-Forever']")
assert me and me.name == "Jay" and me.realm == "Forever" and me["class"] == "WARRIOR" and me.level == 42
assert me.xp == 1000 and me.xpMax == 10000 and me.rested == 2500 and me.resting is True and me.online is True
assert me.zone == "Orgrimmar" and me.t == L.eval("NOW") and me.maxLevel == 60
assert ns.Char() == "Jay-Forever"
print("SNAPSHOT OK")

# --- the sums ---------------------------------------------------------------------------
L.execute("""
NOW = 1700000000
RestedKingDB.chars["Alt-Forever"] = { name = "Alt", realm = "Forever", class = "MAGE", level = 30, xp = 0, xpMax = 10000,
  rested = 0, resting = true, t = NOW - 8 * 3600 }
RestedKingDB.chars["Out-Forever"] = { name = "Out", realm = "Forever", class = "ROGUE", level = 20, xp = 5000, xpMax = 10000,
  rested = 0, resting = false, t = NOW - 8 * 3600 }
RestedKingDB.chars["Full-Forever"] = { name = "Full", realm = "Forever", class = "PRIEST", level = 25, xp = 0, xpMax = 10000,
  rested = 0, resting = true, t = NOW - 30 * 86400 }
RestedKingDB.chars["Max-Forever"] = { name = "Max", realm = "Forever", class = "WARRIOR", level = 60, maxLevel = 60, xp = 0, xpMax = 0, t = NOW - 3600 }
""")
chars = L.eval("RestedKingDB.chars")
alt, out, full, mx = chars["Alt-Forever"], chars["Out-Forever"], chars["Full-Forever"], chars["Max-Forever"]
assert abs(ns.Rate(alt) - 10000 * 0.05 / (8 * H)) < 1e-12, "5% of a level per 8 hours in an inn or city"
assert abs(ns.Rate(out) - ns.Rate(alt) / 4) < 1e-12, "a quarter of that outside"
assert ns.Cap(alt) == 15000, "150% of a level"
e = ns.Estimate(alt)
assert e.rested == 500 and abs(e.pct - 0.05) < 1e-9 and abs(e.bubbles - 1.0) < 1e-9 and e.estimated and not e.full
assert abs(e.fullIn - 14500 / ns.Rate(alt)) < 1e-6 and e.toLevel == 10000
assert ns.Estimate(out).rested == 125
ef = ns.Estimate(full)
assert ef.full and ef.rested == 15000 and abs(ef.fullSince - (L.eval("NOW") - 30 * 86400 + 10 * 86400)) < 1, "fills in 10 days from empty"
assert ns.Estimate(mx).max and ns.IsMax(mx)
# the Well Rested perk: +4% per rank on the rate and the cap
L.execute('RestedKingDB.chars["Alt-Forever"].perk = 5')
assert ns.Cap(alt) == 18000 and abs(ns.Rate(alt) - 1.2 * 10000 * 0.05 / (8 * H)) < 1e-12
L.execute('RestedKingDB.chars["Alt-Forever"].perk = nil')
# online characters show the game's own number, never an estimate
L.execute('RestedKingDB.chars["Jay-Forever"].t = NOW - 86400')
ej = ns.Estimate(me); assert ej.rested == 2500 and not ej.estimated
assert ns.Duration(90061) == "1d 1h" and ns.Duration(3720) == "1h 2m" and ns.Duration(120) == "2m" and ns.Duration(None) == "-"
assert ns.Num(1234567) == "1,234,567" and ns.Num(12) == "12"
assert "FULL" in ns.FullText(ef, L.eval("NOW")) and "in " in ns.FullText(e, L.eval("NOW")) and "max level" in ns.FullText(ns.Estimate(mx), 0)
assert "est" in ns.RestedText(e) and "(5%, 1.0 bubbles)" in ns.RestedText(e)
assert L.eval("RestedKing.Get('Alt-Forever').rested") == 500 and L.eval("RestedKing.Get().rested") == 2500
assert L.eval("RestedKing.Get('Nobody-Forever')") is None
print("SUMS OK")

# --- sorting -----------------------------------------------------------------------------
keys = lambda *a: [r.key for r in ns.Characters(*a).values()]
assert keys("rested", True, False) == ["Full-Forever", "Jay-Forever", "Alt-Forever", "Out-Forever"], keys("rested", True, False)
assert "Max-Forever" not in keys("rested", True, False) and "Max-Forever" in keys("rested", True, True)
assert keys("name", False, False) == ["Alt-Forever", "Full-Forever", "Jay-Forever", "Out-Forever"]
assert keys("level", True, False)[0] == "Jay-Forever" and keys("level", False, False)[0] == "Out-Forever"
assert keys("full", False, False)[0] == "Full-Forever", "wasting rest first"
assert keys("seen", True, False)[0] == "Alt-Forever" and keys("seen", False, False)[0] == "Full-Forever"
assert ns.MostRestedAlt().key == "Full-Forever", "the most rested character you're not on"
print("SORT OK")

# --- events ------------------------------------------------------------------------------
L.execute("XP, EXHAUSTION = 4000, 1200; FIRE('PLAYER_XP_UPDATE')")
assert me.xp == 4000 and me.rested == 1200 and me.t == L.eval("NOW")
L.execute("RESTING, ZONE = false, 'Durotar'; FIRE('PLAYER_UPDATE_RESTING')")
assert me.resting is False and me.zone == "Durotar"
L.execute("PLAYER.level, XPMAX = 43, 11000; FIRE('PLAYER_LEVEL_UP', 43)")
assert me.level == 42, "the new level's numbers come a moment later"
L.execute("RUN_TIMERS()"); assert me.level == 43 and me.xpMax == 11000
L.execute("FIRE('PLAYER_LOGOUT')"); assert me.online is False
L.execute("FIRE('PLAYER_ENTERING_WORLD', false, true)"); assert me.online is True
# The game reports 0 XP needed while you log out: that must not wipe the saved numbers (it hid every alt as "max level").
L.execute("XP, XPMAX, EXHAUSTION = 0, 0, nil; FIRE('PLAYER_LOGOUT')")
me = L.eval("RestedKingDB.chars['Jay-Forever']")
assert me.xpMax == 11000 and me.xp > 0 and me.rested > 0 and me.online is False, "last real XP numbers kept"
assert not ns.IsMax(me) and not ns.Estimate(me).max
# Characters already saved that way (2.1 and older) still show up, marked to log in once.
L.execute('RestedKingDB.chars["Zero-Forever"] = { name = "Zero", realm = "Forever", class = "MAGE", level = 42, maxLevel = 60, xp = 0, xpMax = 0, rested = 0, t = NOW }')
z = L.eval("RestedKingDB.chars['Zero-Forever']")
assert ns.Unknown(z) and ns.Estimate(z).unknown and not ns.IsMax(z)
assert "Zero-Forever" in [r.key for r in ns.Characters("rested", True, False).values()], "listed, not hidden as max level"
assert "log in" in ns.RestedText(ns.Estimate(z))
for k in ("rested", "full", "name", "level", "seen"): ns.Characters(k, True, False)
L.execute('RestedKingDB.chars["Zero-Forever"] = nil; XP, XPMAX, EXHAUSTION = 4000, 11000, 1200')
print("EVENTS OK")

# --- perk and forget ----------------------------------------------------------------------
L.execute("NOW = NOW + 8 * 3600")  # Alt has 16 hours of rest now
ns.SetPerk("Alt-Forever", 9)
assert alt.perk == 5 and alt.rested == 1000 and alt.t == L.eval("NOW"), "rest so far banked at the old rate"
ns.SetPerk("Alt-Forever", -1); assert alt.perk == 0
rk("perk 3"); assert me.perk == 3 and "Well Rested rank 3 on Jay-Forever" in last(L), last(L)
rk("forget out"); assert L.eval("RestedKingDB.chars['Out-Forever']") is None and "forgot Out-Forever" in last(L)
rk("forget nobody"); assert "no character called nobody" in last(L)
rk("button"); assert "crown" in last(L)
rk("help"); assert any("/rk perk" in str(o) for o in outputs(L))
print("PERK + FORGET OK")


# --- the Rested XP page ------------------------------------------------------------------
def texts():
    fs = L.eval("FONTS")
    return [str(fs[i].text) for i in range(1, len(fs) + 1) if fs[i].text]


def click(b, which="LeftButton"):
    b.RunScript(b, "OnClick", which)


def names():
    return [r.data.c.name for r in ns.table.rows.values() if r.data and r.shown]


rk("")
assert KM.IsShown("rested") and not KM.errorShown, last(L)
assert names() == ["Full", "Jay", "Alt"], names()
assert any("characters levelling" in x for x in texts()) and "MOST RESTED ALT" in texts() and "FULL OF REST" in texts()
assert "Full" in texts(), "the most rested alt tile"
assert ns.IsTicking(), "a ticker keeps the numbers moving while the page is open"
# a header click sorts (and is remembered); a second click flips it
click(ns.table.headers.name)
assert L.eval("RestedKingDB.ui.sort") == "name" and L.eval("RestedKingDB.ui.desc") is False and names() == ["Alt", "Full", "Jay"], names()
click(ns.table.headers.name); assert names() == ["Jay", "Full", "Alt"] and L.eval("RestedKingDB.ui.desc") is True
assert "CHARACTER  v" in texts()
click(ns.table.headers.rested); assert names()[0] == "Full"
# max-level characters: hidden until asked for
click(L.eval('BTN("Show max level")')); assert "Max" in names() and L.eval("RestedKingDB.ui.showMax") is True
assert L.eval('BTN("Hide max level")')
click(L.eval('BTN("Hide max level")')); assert "Max" not in names()
# the right-click menu: perk ranks and forget
row = [r for r in ns.table.rows.values() if r.data and r.data.key == "Alt-Forever"][0]
click(row, "RightButton")
assert L.eval("MENU_TITLE") == "Alt-Forever" and L.eval('MENU_ITEM("Rank 2 (+8%)") ~= nil') and L.eval('MENU_ITEM("None").selected')
L.execute('MENU_ITEM("Rank 2 (+8%)").fn()'); assert alt.perk == 2
row.RunScript(row, "OnEnter"); assert any("Rested now" in str(x) for x in L.eval("GameTooltip.lines").values())
click(row, "RightButton"); L.execute('MENU_ITEM("Forget this character").fn()')
assert L.eval("RestedKingDB.chars['Alt-Forever']") is None and "Alt" not in names()
# live refresh: the ticker redraws; leaving the page stops it
L.execute('RestedKingDB.chars["New-Forever"] = { name = "New", realm = "Forever", class = "MAGE", level = 10, xp = 0, xpMax = 2000, rested = 0, resting = true, t = NOW }')
L.execute("ADVANCE(5)"); assert "New" in names(), "the ticker picked it up"
KM.Show("home"); assert not ns.IsTicking()
KM.Show("rested"); assert ns.IsTicking()
rk(""); assert not KM.IsShown()
L.execute("ADVANCE(6)"); assert not ns.IsTicking()
assert not KM.errorShown, last(L)
print("PAGE OK")

# --- the crown, Home and Settings -----------------------------------------------------------
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Rested XP") ~= nil')
L.execute('MENU_ITEM("Rested XP").fn()'); assert KM.IsShown("rested")
L.execute('GameTooltip.lines = {}; KingMakerMinimapButton:RunScript("OnEnter")')
tip = [str(x) for x in L.eval("GameTooltip.lines").values()]
rested = [x for x in tip if x.startswith("Rested: ")]
assert 1 <= len(rested) <= 3 and "Full" in rested[0], tip
KM.Show("home"); assert "MOST RESTED ALT" in texts() and not KM.errorShown, last(L)
KM.OpenSettings("rested"); assert "Show max-level characters" in texts() and "Well Rested perk rank" in texts()
cb = L.eval('CHECK("Show max-level characters")'); cb.GetScript(cb, "OnClick")(cb)
assert L.eval("RestedKingDB.ui.showMax") is True
assert "Rank 3" in texts(), "this character's perk"
assert not KM.errorShown, last(L)
print("SHELL OK")

# --- InitDB twice ---------------------------------------------------------------------------
L2, KM2 = fresh(only=["Rested"], extra=EXTRA, login=False,
                seed="RestedKingDB = { chars = { ['Old-Forever'] = { name = 'Old', level = 12, xpMax = 4000, rested = 100, t = 900, online = true } }, ui = { button = true, buttonAngle = 225, sort = 'name', desc = false } }")
L2.execute('LOADED_ADDONS["King_Maker"] = true; FIRE("ADDON_LOADED", "King_Maker")')
L2.execute("HELD = RestedKingDB")
assert L2.eval("RestedKingDB.chars['Old-Forever'].online") is None, "nobody is online until they log in"
KM2.mods.Rested.InitDB()
assert L2.eval("RestedKingDB == HELD") and L2.eval("RestedKingDB.ui.sort") == "name" and L2.eval("RestedKingDB.ui.desc") is False
assert L2.eval("RestedKingDB.ui.button") is None and L2.eval("RestedKingDB.ui.buttonAngle") is None
assert L2.eval("RestedKingDB.chars['Old-Forever'].rested") == 100
L2.execute('FIRE("PLAYER_LOGIN"); FIRE("PLAYER_ENTERING_WORLD", true, false)')
assert L2.eval("RestedKingDB.chars['Jay-Forever'].online") is True
KM2.Show("rested"); assert not KM2.errorShown, last(L2)
print("INITDB OK")

print("rested: ok")
