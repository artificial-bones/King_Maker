# The shell, settings, /km and the move from the 1.x folders, with no modules loaded.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# --- fresh install ----------------------------------------------------------------
L, KM = fresh(only=[])
assert L.eval("KingMakerDB.ui.button") is True
assert L.eval("KingMakerMinimapButton ~= nil"), "minimap button made at login"
assert L.eval("KingMaker.API_VERSION") == 2
slash = L.eval("SlashCmdList.KINGMAKER")
slash("")
assert L.eval("KingMakerFrame:IsShown()"), "/km opens the window"
assert KM.CurrentPage() == "home", KM.CurrentPage()
for pid in ["home", "settings"]:
    KM.Show(pid)
    assert not KM.errorShown, last(L)
slash("")
assert not L.eval("KingMakerFrame:IsShown()"), "/km toggles it closed"
slash("settings")
assert KM.CurrentPage() == "settings"
slash("button off")
assert L.eval("KingMakerDB.ui.button") is False
slash("bogus page")
assert "no page" in last(L), last(L)
slash("help")
assert any("/km settings" in o for o in outputs(L))

# A module page registered after the window exists shows up and opens.
L.execute("""
KingMaker.RegisterPage({ id = "demo", group = "ah", label = "Demo", order = 5, build = function(c) DEMO_BUILT = (DEMO_BUILT or 0) + 1 end,
  refresh = function(c) DEMO_REFRESH = (DEMO_REFRESH or 0) + 1 end })
""")
KM.Show("demo")
assert L.eval("DEMO_BUILT") == 1 and L.eval("DEMO_REFRESH") >= 1
KM.Show("home"); KM.Show("demo")
assert L.eval("DEMO_BUILT") == 1, "built once"
# Collapsing a group hides its pages except the open one.
L.execute('KingMakerDB.ui.collapsed.ah = true')
KM.LayoutNav()

# Quick actions in the minimap menu.
L.execute("""KingMaker.RegisterQuickAction({ label = "Do it", order = 1, func = function() DID = true end })""")
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Do it") ~= nil') and L.eval('MENU_ITEM("Settings") ~= nil')
L.execute('MENU_ITEM("Do it").fn()')
assert L.eval("DID") is True

# --- moving data in from 1.x stubs ------------------------------------------------
# A module stand-in that holds its table, like the real ones do.
MOD = """
local m = KingMakerTestKM.Module("Scanner", { title = "Scanner King", legacy = "Scanner_King", db = "ScannerKingDB" })
function m.InitDB()
  ScannerKingDB = ScannerKingDB or {}
  m.db = ScannerKingDB
  m.db.ui = m.db.ui or { tooltip = true }
  m.inits = (m.inits or 0) + 1
end
"""
OLD = "ScannerKingDB = { prices = { [2589] = { p = 120, t = 900 } }, ui = { tooltip = false } }"


def with_module(**kw):
    L, KM = fresh(only=[], login=False, **{k: v for k, v in kw.items() if k in ("seed",)})
    L.globals().KingMakerTestKM = KM
    L.execute(MOD)
    L.execute('LOADED_ADDONS["King_Maker"] = true; FIRE("ADDON_LOADED", "King_Maker")')
    return L, KM


# first login with the stub: old data moves into the module's own table
L, KM = with_module()
L.execute("HELD = KingMakerTestKM.mods.Scanner.db")
L.execute("ADDON_META['Scanner_King'] = { ['X-KingMaker-Stub'] = '1' }")
L.execute(OLD)
L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
assert L.eval("ScannerKingDB.prices[2589].p") == 120, "old prices moved in"
assert L.eval("ScannerKingDB == HELD"), "the module keeps the same table"
assert L.eval("KingMakerTestKM.mods.Scanner.db.ui.tooltip") is False, "old settings win"
assert L.eval("KingMakerTestKM.mods.Scanner.inits") == 2, "InitDB re-ran after the move"
assert L.eval("KingMakerDB.moved.ScannerKingDB") is not None
assert any("moved your old King addon data in" in o for o in outputs(L)), outputs(L)

# next login: King Maker's copy is newer; the stub's (stale) copy must not win
saved_km = "KingMakerDB = { moved = { ScannerKingDB = 900 }, ui = {} }; ScannerKingDB = { prices = { [2589] = { p = 150, t = 1000 } } }"
L, KM = fresh(only=[], login=False, seed=saved_km)
L.globals().KingMakerTestKM = KM
L.execute(MOD)
L.execute('FIRE("ADDON_LOADED", "King_Maker")')
L.execute("ADDON_META['Scanner_King'] = { ['X-KingMaker-Stub'] = '1' }")
L.execute("ScannerKingDB = { prices = { [2589] = { p = 120, t = 900 } } }")    # the stale stub file
L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("PLAYER_LOGIN")')
assert L.eval("ScannerKingDB.prices[2589].p") == 150, "King Maker's own data wins after the move"
assert L.eval("KingMakerTestKM.mods.Scanner.inits") == 1

# the real 1.x addon still installed: nothing is touched, the player is told
L, KM = with_module()
L.execute("ADDON_META['Scanner_King'] = { Version = '1.6.0' }")
L.execute(OLD)
L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("PLAYER_LOGIN")')
assert L.eval("KingMakerDB.moved.ScannerKingDB") is None
assert any("old King addons are still installed" in o for o in outputs(L)), outputs(L)

print("core: ok")
