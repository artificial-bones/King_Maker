# Oracle (the player's separate, private addon) next to King Maker: it keeps its own window, and its minimap button
# goes into King Maker's button drawer right under King Maker. Skipped when Oracle isn't installed beside this repo
# (E:\wow_addons\Oracle or ORACLE_DIR).
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last

ORACLE = os.environ.get("ORACLE_DIR") or r"E:\wow_addons\Oracle"
if not os.path.exists(os.path.join(ORACLE, "Oracle.toc")):
    print("oracle: skipped (no Oracle addon)")
    sys.exit(0)

files = [l.strip().replace("\\", "/") for l in open(os.path.join(ORACLE, "Oracle.toc"), encoding="utf-8-sig")
         if l.strip() and not l.strip().startswith("#")]

L, KM = fresh(only=["Minimap"], login=False)
# another addon's button too, to check the order
L.execute("""
local b = CreateFrame("Button", "LibDBIcon10_Atlas", Minimap); b:SetSize(31, 31); b:SetScript("OnClick", function() ATLAS = true end)
""")
ons = L.table()
for f in files:
    path = os.path.join(ORACLE, "tests", "sample_data.lua") if f == "OracleData.lua" else os.path.join(ORACLE, f)
    L.execute(open(path, encoding="utf-8").read(), "Oracle", ons)
L.execute('FIRE("ADDON_LOADED", "King_Maker"); FIRE("ADDON_LOADED", "Oracle"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')

assert not [i for i in KM.pages.keys() if str(i).startswith("oracle")], "Oracle's pages stay in Oracle's own window"
L.execute("SlashCmdList.ORACLE('')")
assert L.eval("OracleFrame and OracleFrame:IsShown()"), "/ora opens Oracle's own window"
assert not L.eval("KingMakerFrame and KingMakerFrame:IsShown()")

# The crown's left-click opens the drawer: King Maker first, then Oracle, then the rest by name.
L.execute('KingMakerMinimapButton:Click("LeftButton")')
assert L.eval("MinimapKingMenu:IsShown()"), "left-click opens the drawer"
names = [L.eval("MinimapKing.Shown()[%d]:GetName()" % i) for i in (1, 2)]
assert names == ["OracleMinimapButton", "LibDBIcon10_Atlas"], names
L.execute('KingMakerMinimapButton:Click("LeftButton")')
assert not L.eval("MinimapKingMenu:IsShown()"), "and closes it"
# The King Maker line opens the window.
L.execute('MinimapKing.ShowMenu(); MinimapKingMenu.km:Click("LeftButton")')
assert L.eval("KingMakerFrame:IsShown()") and not L.eval("MinimapKingMenu:IsShown()")
KM.Show("home")
assert not KM.errorShown, last(L)
print("oracle: ok (own window; its button sits under King Maker in the drawer)")
