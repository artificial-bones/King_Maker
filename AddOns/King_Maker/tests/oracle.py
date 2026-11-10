# Oracle (a separate, private addon) in plug-in mode: its pages join the King Maker window. Skipped when the Oracle
# addon isn't next to this repo (E:\wow_addons\Oracle or ORACLE_DIR).
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last

ORACLE = os.environ.get("ORACLE_DIR") or r"E:\wow_addons\Oracle"
if not os.path.exists(os.path.join(ORACLE, "Oracle.toc")):
    print("oracle: skipped (no Oracle addon)")
    sys.exit(0)

files = [l.strip().replace("\\", "/") for l in open(os.path.join(ORACLE, "Oracle.toc"), encoding="utf-8-sig")
         if l.strip() and not l.strip().startswith("#")]

L, KM = fresh(only=[], login=False)
ons = L.table()
for f in files:
    path = os.path.join(ORACLE, "tests", "sample_data.lua") if f == "OracleData.lua" else os.path.join(ORACLE, f)
    L.execute(open(path, encoding="utf-8").read(), "Oracle", ons)
L.execute('FIRE("ADDON_LOADED", "King_Maker"); FIRE("ADDON_LOADED", "Oracle"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')

assert ons.plugin is True, "plug-in mode on"
ids = [i for i in KM.pages.keys() if str(i).startswith("oracle-")]
assert len(ids) == 7, ids
for i in ids:
    KM.Show(i)
    assert not KM.errorShown, (i, last(L))
assert L.eval("OracleFrame == nil"), "Oracle's own window is never made"
assert not L.eval("OracleMinimapButton and OracleMinimapButton:IsShown()"), "no second minimap button"
KM.Toggle(False)
L.execute("SlashCmdList.ORACLE('')")
assert L.eval("KingMakerFrame:IsShown()") and KM.CurrentPage().startswith("oracle-")
L.execute("SlashCmdList.ORACLE('')")
assert not L.eval("KingMakerFrame:IsShown()"), "/ora closes it again"
KM.Show("home")
assert not KM.errorShown, last(L)
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Oracle") ~= nil')
print("oracle: ok (7 pages in the King Maker window)")
