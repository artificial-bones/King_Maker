# The shell, settings, /km and the move from the 1.x folders, with no modules loaded.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page

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

# --- Forever names: "First Last" (UnitName's second value is the surname) --------------------------------
OLD = """PLAYER.surname = "Stone"
InventoryKingDB = { chars = { ["Jay-Forever"] = { gold = 500, class = "WARRIOR", faction = "Alliance" }, ["Alt-Forever"] = { gold = 1 } },
  stock = { ["Jay-Forever"] = { bank = { [2589] = 4 }, bankT = 5 } }, history = { [20000] = { ["Jay-Forever"] = { g = 500 } } } }
RestedKingDB = { chars = { ["Jay-Forever"] = { name = "Jay", realm = "Forever", rested = 100, perk = 3 } } }
MailKingDB = { entries = { { t = 1, k = "sale", name = "Linen Cloth", n = 1, g = 10, c = "Jay-Forever" },
  { t = 2, k = "sale", name = "Linen Cloth", n = 1, g = 10, c = "Alt-Forever" } }, posts = { { c = "Jay-Forever", t = 1 } } }
MarketKingDB = { chars = { ["Jay-Forever"] = { known = { [3321] = true }, owned = { [2661] = false } } } }
SkillupKingDB = { chars = { ["Jay-Forever"] = { known = { [100] = true }, skills = { Tailoring = { 50, 75 } } } } }
"""
L, KM = fresh(seed=OLD)
assert KM.PlayerName() == "Jay Stone" and KM.Char() == "Jay Stone-Forever" and KM.OldChar() == "Jay-Forever"
assert KM.IsMe("Jay Stone-Forever") and KM.IsMe("jay stone") and not KM.IsMe("Jay") and not KM.IsMe("Jay Other")
for path in ["InventoryKingDB.chars", "InventoryKingDB.stock", "InventoryKingDB.history[20000]", "RestedKingDB.chars",
             "MarketKingDB.chars", "SkillupKingDB.chars"]:
    assert L.eval(path + "['Jay-Forever']") is None and L.eval(path + "['Jay Stone-Forever']") is not None, path
assert L.eval("InventoryKingDB.chars['Jay Stone-Forever'].gold") is not None and L.eval("InventoryKingDB.chars['Alt-Forever'].gold") == 1
assert L.eval("InventoryKingDB.stock['Jay Stone-Forever'].bank[2589]") == 4, "old bank kept beside the fresh bag scan"
assert L.eval("RestedKingDB.chars['Jay Stone-Forever'].name") == "Jay Stone" and L.eval("RestedKingDB.chars['Jay Stone-Forever'].perk") == 3
assert L.eval("MarketKingDB.chars['Jay Stone-Forever'].known[3321]") is True, "recipes known survive an empty new entry"
assert L.eval("SkillupKingDB.chars['Jay Stone-Forever'].known[100]") is True
assert L.eval("MailKingDB.entries[1].c") == "Jay Stone-Forever" and L.eval("MailKingDB.entries[2].c") == "Alt-Forever"
assert L.eval("MailKingDB.posts[1].c") == "Jay Stone-Forever"
assert not KM.errorShown, last(L)
KM.RenameChar(); assert L.eval("MailKingDB.entries[1].c") == "Jay Stone-Forever", "safe twice"
# no surname: keys stay as they were
L, KM = fresh(seed=OLD.replace('PLAYER.surname = "Stone"', ''))
assert KM.Char() == "Jay-Forever" and L.eval("InventoryKingDB.chars['Jay-Forever']") is not None
assert L.eval("MailKingDB.entries[1].c") == "Jay-Forever"
print("NAMES OK")

# --- window zoom: the corner grip, /km size, Settings, re-clamping ---------------------------------------------
def near(a, b, eps=1e-6):
    return abs(a - b) < eps


def font_parent(L, text):
    L.globals().FP_TEXT = text
    return L.eval("(function() for _, t in ipairs(FONTS) do if t.text == FP_TEXT then return t.parent end end end)()")


L, KM = fresh(only=[])
slash = L.eval("SlashCmdList.KINGMAKER")
slash("")
g = KM.grip
assert g is not None, "the grip is made with the window"
L.globals().KM_G = g
# the mock's UIParent is 1024 x 768: the window fits up to 102%
assert near(KM.MaxScale(), 1.02), KM.MaxScale()
assert near(KM.MinScale(), 0.7)
# a press that moves 2 px isn't a drag
L.execute("KingMakerFrame.left, KingMakerFrame.top = 12, 700")
L.execute("CURSOR_X, CURSOR_Y = 12 + 1000 - 8, 700 - 640 + 8")
L.execute('KM_G:RunScript("OnMouseDown", "LeftButton")')
L.execute("CURSOR_X, CURSOR_Y = 1005, 69; RUN_ONUPDATE(0.01)")
assert near(L.eval("KingMakerFrame:GetScale()"), 1.0), "a press that hasn't moved changes nothing"
# dragging far past the screen stops at what fits and slides the window back inside the right edge, top kept
L.execute("CURSOR_X, CURSOR_Y = 3000, -900; RUN_ONUPDATE(0.01)")
s = L.eval("KingMakerFrame:GetScale()")
assert near(s, 1.02), s
p = L.eval("{ KingMakerFrame:GetPoint(1) }")
assert p[1] == "TOPLEFT" and p[3] == "TOPLEFT", list(p.values())
assert near(p[4] * s, 1024 - 1000 * s), p[4] * s
assert near(p[5] * s, 700 - 768), p[5] * s
assert L.eval("KM_G.readout:IsShown()") and L.eval("KM_G.readout:GetText()") == "102%"
L.execute('KM_G:RunScript("OnMouseUp", "LeftButton")')
assert near(L.eval("KingMakerDB.ui.scale"), 1.02)
assert L.eval("KingMakerDB.ui.pos.point") == "TOPLEFT"
assert not L.eval("KM_G.readout:IsShown()") and L.eval("KM_G:GetScript('OnUpdate')") is None
# a big screen: the corner follows the mouse with the aspect ratio kept and the top-left fixed
L.execute("UIParent:SetSize(2000, 1500)")
L.execute("KingMakerFrame.scale = 1; KingMakerFrame.left, KingMakerFrame.top = 100, 1400")
L.execute("CURSOR_X, CURSOR_Y = 100 + 1000 - 8, 1400 - 640 + 8")
L.execute('KM_G:RunScript("OnMouseDown", "LeftButton")')
L.execute("CURSOR_X, CURSOR_Y = 100 + 1500 - 8, 1400 - 960 + 8; RUN_ONUPDATE(0.01)")
s = L.eval("KingMakerFrame:GetScale()")
assert near(s, 1.5), s
p = L.eval("{ KingMakerFrame:GetPoint(1) }")
assert near(p[4] * s, 100) and near(p[5] * s, 1400 - 1500), (p[4] * s, p[5] * s)
L.execute("CURSOR_X, CURSOR_Y = 100 + 1300, 1400 - 900; RUN_ONUPDATE(0.01)")     # off the diagonal: the nearest zoom on it
assert 1.3 < L.eval("KingMakerFrame:GetScale()") < 1.41
L.execute("CURSOR_X, CURSOR_Y = 120, 1380; RUN_ONUPDATE(0.01)")                    # tiny: the 70% floor
assert near(L.eval("KingMakerFrame:GetScale()"), 0.7)
# Escape mid-drag: hiding ends the drag and saves
L.execute("KingMakerFrame:Hide(); KM_G:RunScript('OnHide')")
assert L.eval("KM_G:GetScript('OnUpdate')") is None and near(L.eval("KingMakerDB.ui.scale"), 0.7)
# double-click: 100%
slash("")
L.execute('KM_G:RunScript("OnDoubleClick", "LeftButton")')
assert near(L.eval("KingMakerFrame:GetScale()"), 1.0) and near(L.eval("KingMakerDB.ui.scale"), 1.0)
# /km size
slash("size 250")
assert near(L.eval("KingMakerDB.ui.scale"), 2.0) and "200%" in last(L), last(L)
slash("size 50%")
assert near(L.eval("KingMakerDB.ui.scale"), 0.7) and "70%" in last(L), last(L)
slash("zoom 120")
assert near(L.eval("KingMakerDB.ui.scale"), 1.2)
slash("size")
assert "120%" in last(L) and "70-200%" in last(L), last(L)
slash("size reset")
assert L.eval("KingMakerDB.ui.scale") is None and L.eval("KingMakerDB.ui.pos") is None
assert L.eval("{ KingMakerFrame:GetPoint(1) }")[1] == "CENTER"
slash("help")
assert any("/km size" in o for o in outputs(L))
# Settings: "Window zoom" steps 5% and stops at what fits; the reset button
L.execute("UIParent:SetSize(1024, 768)")
KM.Show("settings")
assert not KM.errorShown, last(L)
assert font_parent(L, "Window zoom") is not None and font_parent(L, "Window size") is None
L.globals().PLUS = L.eval("(function() for _, t in ipairs(FONTS) do if t.text == '+' and t.parent and t.parent.Click then return t.parent end end end)()")
for _ in range(5):
    L.execute("PLUS:Click()")
assert near(L.eval("KingMakerDB.ui.scale"), 1.02), L.eval("KingMakerDB.ui.scale")
L.globals().RESET = font_parent(L, "Reset window zoom and position")
L.execute("RESET:Click()")
assert L.eval("KingMakerDB.ui.scale") is None and not KM.errorShown, last(L)
# a UI-scale change re-clamps a zoom that no longer fits
L.execute("KingMakerDB.ui.scale = 1.4; FIRE('UI_SCALE_CHANGED'); RUN_TIMERS()")
assert near(L.eval("KingMakerDB.ui.scale"), 1.02) and near(L.eval("KingMakerFrame:GetScale()"), 1.02)
# an old 140% save on a 768-tall screen opens at what fits (it used to run off the bottom)
L, KM = fresh(only=[], seed="KingMakerDB = { ui = { scale = 1.4 } }")
L.eval("SlashCmdList.KINGMAKER")("")
assert near(L.eval("KingMakerFrame:GetScale()"), 1.02), L.eval("KingMakerFrame:GetScale()")
L, KM = fresh(only=[], seed="KingMakerDB = { ui = { scale = 'big' } }")
assert L.eval("KingMakerDB.ui.scale") is None, "a broken saved zoom is dropped"
print("ZOOM OK")

# --- shell polish: header rule, status box sized to its text, group headers -------------------------------------
L, KM = fresh(only=[])
L.globals().KMT = KM
L.eval("SlashCmdList.KINGMAKER")("")
assert KM.headerRule is not None
L.execute("KingMaker.RegisterStatus(function() return 'Scanned 2h ago' end)")
L.execute("KingMakerFrame:Hide()")
L.eval("SlashCmdList.KINGMAKER")("")
box = font_parent(L, "Scanned 2h ago")
assert box is not None and box.IsShown(box) and box.h == 28, box.h
assert L.eval("KMT.groups.home.header.fs.font[2]") == 10, "group headers 10 pt"
print("POLISH OK")

# --- count badges: table vs text, collapsed group sum, the minimap crown -------------------------------------------
L, KM = fresh(only=[])
L.globals().KMT = KM
L.execute("""
BV = { count = 2, color = "red", tip = "Mooncloth is ready on Jay." }
KingMaker.RegisterPage({ id = "cd", group = "craft", label = "Cooldowns", order = 30, crownBadge = true, badge = function() return BV end, build = function() end })
KingMaker.RegisterPage({ id = "txt", group = "craft", label = "Text", order = 31, badge = function() return "3" end, build = function() end })
KingMaker.RegisterPage({ id = "num", group = "craft", label = "Number", order = 32, badge = function() return 12 end, build = function() end })
KingMaker.RegisterPage({ id = "alt", group = "craft", label = "Alts", order = 33, badge = function() return ALTV end, build = function() end })
""")
# before the window exists: no error, and the crown already shows the count
KM.RefreshBadges()
assert not KM.errorShown, last(L)
crown = L.eval("KingMakerMinimapButton.count")
assert crown.IsShown(crown) and crown.text.text == "2", crown.text.text
assert L.eval("KingMaker.RefreshBadges ~= nil")
L.eval("SlashCmdList.KINGMAKER")("")


def nav(pid):
    return L.eval("KMT.pages['%s'].nav" % pid)


cd, txt, num = nav("cd"), nav("txt"), nav("num")
assert cd.count.IsShown(cd.count) and cd.count.text.text == "2" and (cd.badge.text or "") == ""
assert txt.badge.text == "3" and not txt.count.IsShown(txt.count), "strings keep the gold text (Oracle)"
assert num.badge.text == "12" and not num.count.IsShown(num.count), "numbers too"
assert near(cd.count.disc.vertex[1], 0.86) and near(cd.count.disc.vertex[2], 0.19)
L.execute("BV.count = 12; KingMaker.RefreshBadges()")
assert cd.count.text.text == "9+"
L.execute("BV.count = 2")
# gold
L.execute("ALTV = { count = 1, color = 'gold' }; KingMaker.RefreshBadges()")
alt = nav("alt")
assert alt.count.text.text == "1" and near(alt.count.disc.vertex[1], 0.94)
# the tip shows on hover
L.execute("GameTooltip.lines = {}; KMT.pages.cd.nav:RunScript('OnEnter')")
assert any("Mooncloth is ready" in str(x) for x in L.eval("GameTooltip.lines").values())
# collapsing the group: its header shows the sum of the pages it hides, red if any is red; expanding clears it
hdr = L.eval("KMT.groups.craft.header")
assert not hdr.count.IsShown(hdr.count)
L.execute("KMT.groups.craft.header:Click()")
assert L.eval("KingMakerDB.ui.collapsed.craft") is True
assert hdr.count.IsShown(hdr.count) and hdr.count.text.text == "3" and hdr.count.color == "red", (hdr.count.text.text, hdr.count.color)
L.execute("BV.count = 0; KingMaker.RefreshBadges()")
assert hdr.count.text.text == "1" and hdr.count.color == "gold"
L.execute("BV.count = 2; KingMaker.RefreshBadges()")
KM.Show("cd")                                  # the open page keeps its own button: not counted on the header
assert hdr.count.text.text == "1", hdr.count.text.text
KM.Show("home")
L.execute("KMT.groups.craft.header:Click()")
assert not hdr.count.IsShown(hdr.count), "expanded: the header is clean"
# the crown: only crownBadge pages, off with the setting
assert crown.text.text == "2" and crown.IsShown(crown)
L.execute("KingMakerDB.ui.crownBadge = false; KingMaker.RefreshBadges()")
assert not crown.IsShown(crown)
L.execute("KingMakerDB.ui.crownBadge = true; KingMaker.RefreshBadges()")
assert crown.IsShown(crown)
# the Settings tick
KM.OpenSettings("general")
L.globals().CHK = font_parent(L, "Count on the minimap crown")
L.execute("CHK:Click()")
assert L.eval("KingMakerDB.ui.crownBadge") is False and not crown.IsShown(crown)
L.execute("CHK:Click()")
assert L.eval("KingMakerDB.ui.crownBadge") is True and crown.IsShown(crown)
# a nil badge clears both
L.execute("BV = nil; KingMaker.RefreshBadges()")
assert not cd.count.IsShown(cd.count) and (cd.badge.text or "") == "" and not crown.IsShown(crown)
assert not KM.errorShown, last(L)
L2, KM2 = fresh(only=[], seed="IN_GUILD = false")
assert L2.eval("KingMakerDB.ui.crownBadge") is True, "crown count on by default"
print("BADGES OK")

# --- every page, whole addon, at 70%, 100% and the screen maximum; no two sidebar icons alike ---------------------
L, KM = fresh()
icons = {}
for pid in list(KM.pages.keys()):
    icon = KM.pages[pid].icon
    assert icon not in icons, (pid, icons.get(icon), icon)
    icons[icon] = pid
for zoom in (0.7, 1.0, KM.MaxScale()):
    KM.SetScale(zoom)
    open_every_page(L, KM)
assert not KM.errorShown, last(L)
print("ALL PAGES AT EVERY ZOOM OK")

# --- every stat tile a page shows explains itself on hover ---------------------------------------------------------
L, KM = fresh(seed="KMT_TILES = {}")
L.globals().KMT_UI = KM.UI
L.execute("""
local UI = KMT_UI
local orig = UI.Tile
UI.Tile = function(...) local t = orig(...); KMT_TILES[#KMT_TILES + 1] = t; return t end
""")
CHECK = L.eval("""function()
  local bad = {}
  local function visible(f) while f do if f.shown == false then return false end f = f.parent end return true end
  for _, t in ipairs(KMT_TILES) do
    if visible(t) and (t.labelText or "") ~= "" then
      if not (t.tip and t:GetScript("OnEnter")) then bad[#bad + 1] = t.labelText
      else
        GameTooltip.lines = {}; t:RunScript("OnEnter")
        if #GameTooltip.lines < 2 then bad[#bad + 1] = t.labelText .. " (empty)" end
      end
    end
  end
  return table.concat(bad, ", ")
end""")
untipped = []
for pid in list(KM.pages.keys()):
    KM.Show(pid)
    assert not KM.errorShown, (pid, last(L))
    bad = CHECK()
    if bad:
        untipped.append(f"{pid}: {bad}")
assert not untipped, "tiles without a tooltip: " + "; ".join(untipped)
assert L.eval("#KMT_TILES") > 10, L.eval("#KMT_TILES")
assert not KM.errorShown, last(L)
print("TILE TOOLTIPS OK")

# --- Home: the overview (2.7) -----------------------------------------------------------------------------------
HOME = """
function UNDER(f, root) while f do if f == root then return true end f = f.parent end return false end
function HOME_BUTTON_LABELS()   -- the label of every themed button on Home
  local root, out = KingMaker.UI and KMT.pages.home.container, {}
  for _, f in ipairs(FRAMES) do
    if f.SetLabel and type(rawget(f, "label")) == "table" and UNDER(f, root) then out[#out + 1] = f.label.text or "" end
  end
  return out
end
"""
# a fresh install: every section explains itself, nothing errors, the quick actions are gone from Home
L, KM = fresh(extra=HOME)
L.globals().KMT = KM
KM.Show("home")
assert not KM.errorShown, last(L)
H = KM.home
quick = set()
for a in KM.QuickActions.values():
    lab = a.label
    quick.add(lab if isinstance(lab, str) else lab())
on_home = set(L.eval("HOME_BUTTON_LABELS()").values())
assert not (on_home & quick), ("quick actions on Home", on_home & quick)
assert len(quick) > 10, "they're still in the crown's menu"
assert H.tiles[1].labelText == "Net worth" and H.tiles[1].shown, "net worth leads the hero row"
assert H.src.empty.text.startswith("Nothing earned"), H.src.empty.text
assert H.graph.empty.text.startswith("Your net worth over time"), H.graph.empty.text
assert [b.label for b in H.bestItems.values()] == ["Quests"], "only the shipped quest data has a best yet"
first = H.attItems[1]
assert first.text.startswith("No prices yet") and first.page == "prices", first.text
L.execute("KMT.home.att.rows[1]:Click()")
assert KM.CurrentPage() == "prices", "an attention row opens its page"
print("HOME FRESH OK")

# seeded: a month of net worth, auction sales, a farming session, an alt full of rest, a cooldown ready, characters
SEED = """
NOW = 1763000000
local today = math.floor(NOW / 86400)
local hist = {}
for i = 0, 29 do hist[today - i] = { ["Jay-Forever"] = { g = 1000000 + (29 - i) * 20000, a = 500000 } } end
InventoryKingDB = { chars = { ["Jay-Forever"] = { gold = 1600000, class = "WARRIOR", level = 60, faction = "Alliance" },
  ["Alt Two-Forever"] = { gold = 30000, class = "MAGE", level = 20, faction = "Alliance" } }, history = hist }
MailKingDB = { entries = {
  { t = NOW - 2 * 86400, k = "sale", name = "Linen Cloth", n = 20, g = 200000, cut = 10000, c = "Jay-Forever" },
  { t = NOW - 3 * 86400, k = "sale", name = "Copper Ore", n = 10, g = 50000, cut = 2500, c = "Jay-Forever" },
  { t = NOW - 4 * 86400, k = "expired", name = "Rusty Sword", n = 1, dep = 1500, each = 90000, c = "Jay-Forever" },
  { t = NOW - 5 * 86400, k = "expired", name = "Rusty Sword", n = 1, dep = 1500, each = 90000, c = "Jay-Forever" } } }
RestedKingDB = { chars = { ["Old Timer-Forever"] = { name = "Old Timer", level = 12, xpMax = 4000, rested = 100, t = 900, class = "ROGUE" } } }
"""
L, KM = fresh(seed=SEED, extra=HOME)
L.globals().KMT = KM
L.execute("""
TrackerKingDB.sessions = { { id = 1, c = "Jay-Forever", t0 = NOW - 86400 - 3600, t1 = NOW - 86400, act = 3600, value = 600000,
  coin = 20000, src = { mob = { v = 580000, c = 20000, n = 30 } }, map = 1429, items = {} } }
local CD = KMT.mods.Cooldowns
CD.ReadyList = function()
  return { { key = "Jay-Forever", c = { name = "Jay" }, gk = "mooncloth", e = { ready = NOW - 7200, readySince = NOW - 7200 },
    label = "Mooncloth", name = "Jay" } }, {}
end
-- another addon on the public API: a legacy tile, a note, and more attention rows than fit
KingMaker.RegisterHomeTile({ id = "other", order = 90, get = function() return "Other addon", "42", "its tile" end, tip = "From another addon." })
KingMaker.RegisterHomeNote(function() return "A note from another addon." end)
KingMaker.RegisterHomeCard({ kind = "attention", id = "many", order = 99, get = function()
  local t = {} for i = 1, 12 do t[i] = { text = "Extra " .. i, color = KingMaker.UI.C.info } end return t end })
""")
for zoom in (0.7, 1.0, KM.MaxScale()):
    KM.SetScale(zoom)
    KM.Show("home")
    assert not KM.errorShown, (zoom, last(L))
H = KM.home
labels = [t.labelText for t in H.tiles.values() if t.shown]
assert labels[0] == "Net worth" and "Farmed, 7 days" in labels and "Other addon" in labels, labels
worth = H.tiles[1]
assert worth.spark.shown and worth.spark.shownBars == 30 and "vs 7 days ago" in worth.sub.text, worth.sub.text
assert worth.page == "inventory"
farm = [t for t in H.tiles.values() if t.labelText == "Farmed, 7 days"][0]
assert farm.value.text.endswith("/hr") and farm.page == "farming", farm.value.text
L.execute("for _, t in ipairs(KMT.home.tiles) do if t.labelText == 'Farmed, 7 days' then t:RunScript('OnMouseUp') end end")
assert KM.CurrentPage() == "farming", "a hero tile opens its page"
KM.Show("home")
# the chart: net worth first, the other tab switches it and is remembered
assert H.chartPick == "networth" and H.graph.lines.used > 0 and H.graph.endDot.shown, H.chartPick
other = [k for k in H.tabs.buttons.keys() if k != "networth"][0]
L.execute("KMT.home.tabs.buttons[%r]:Click()" % other)
assert H.chartPick == other and L.eval("KingMakerDB.ui.homeChart") == other, H.chartPick
assert H.graph.bars.used > 0 or H.graph.empty.text.startswith("No sales"), "daily profit, or why there's none yet"
L.execute("KMT.home.tabs.buttons.networth:Click()")
# needs your attention: red first, then warnings; what doesn't fit goes in a last "and N more" row
items = list(H.attItems.values())
assert items[0].text == "Mooncloth ready on Jay" and items[0].value.startswith("idle 2h"), (items[0].text, items[0].value)
texts_ = [i.text for i in items]
assert "1 item not selling" in texts_ and any("full of rest" in t for t in texts_), texts_
assert texts_.index("1 item not selling") < texts_.index("Extra 1"), "warnings before info"
rows = [r for r in H.att.rows.values() if r.shown]
assert rows[-1].text.text.startswith("and ") and "more" in rows[-1].text.text and len(rows) < len(items)
assert H.att.right.text == str(len(items))
# every row that links somewhere opens it; Not selling opens the Sales Ledger's tab
for i, r in enumerate(rows, start=1):
    if r.page:
        L.execute("KMT.home.att.rows[%d]:Click()" % i)
        assert KM.CurrentPage() == r.page, (r.text.text, KM.CurrentPage())
        if r.data and r.data.text == "1 item not selling":
            assert KM.mods.Mail.CurrentTab() == "unsold"
        KM.Show("home")
# where your gold came from: the farming session and the auction sales by strategy, biggest first
inc = [(r.label, r.value) for r in H.incomeRows.values()]
assert inc[0][0] == "Farming" and inc[0][1] == 600000 and sum(v for _, v in inc) == 600000 + 190000 + 47500, inc
assert H.src.split.segs[1].shown and H.src.bars.rows[1].label.text == "Farming" and "in 30 days" in H.src.right.text
# best right now: the farm; the characters, richest first, with their rest and cooldowns
assert any(b.label == "Farm" and b.value.endswith("/hr") for b in H.bestItems.values())
chars = list(H.charsShown.values())
assert chars[0].key == "Jay-Forever" and "g|r" in chars[0].primary.text, chars[0].primary.text
assert any(f.text == "1 cd ready" for f in chars[0].facts.values())
old = [c for c in chars if c.key == "Old Timer-Forever"][0]
assert any(f.text == "full rest" for f in old.facts.values())
assert "A note from another addon." in H.notes.text
# the page stays inside the container: the last card ends above its bottom
bottom = max(-c.point[4] + c.h for c in (H.chart, H.src, H.chars))
assert bottom <= 557, bottom
assert not KM.errorShown, last(L)
print("HOME OK")

# --- version check: guildmates tell each other their King Maker version ------------------------------------------
L, KM = fresh(only=[], seed="IN_GUILD = true")
ver = L.eval("KingMaker.version")
L.execute("RUN_TIMERS()")
sent = [m for m in L.eval("SENT").values() if m.prefix == "KingMaker1"]
assert len(sent) == 1 and sent[0].text == "V" + ver and sent[0].chan == "GUILD", "one hello after login"
assert L.eval("PREFIXES.KingMaker1") is True
assert KM.CompareVersions("2.10.0", "2.9.9") == 1 and KM.CompareVersions("2.6", "2.6.0") == 0 and KM.CompareVersions("2.5.3", "2.6.0") == -1
assert KM.CompareVersions("abc", "2.6.0") is None
# a guildmate with a newer one: one line, once per session per version; /km version names them
L.execute("RECV('KingMaker1', 'V99.0.0', 'Bob-Realm')")
assert "King Maker 99.0.0 is out" in last(L) and "Bob has it" in last(L) and ver in last(L), last(L)
n = len(outputs(L))
L.execute("RECV('KingMaker1', 'R99.0.0', 'Ann-Realm')")
assert len(outputs(L)) == n, "the same version isn't announced twice"
L.execute("RECV('KingMaker1', 'V99.1.0', 'Cid-Realm')")
assert "99.1.0" in last(L)
assert L.eval("KingMakerDB.newest.v") == "99.1.0" and L.eval("KingMakerDB.newest.who") == "Cid"
L.eval("SlashCmdList.KINGMAKER")("version")
assert "Cid has 99.1.0" in last(L), last(L)
# the same or an older version: no line; junk, other channels, other prefixes and our own echo are ignored
n = len(outputs(L))
for text, who, chan in [("V" + ver, "Dee-Realm", "GUILD"), ("V1.0.0", "Eve-Realm", "GUILD"), ("Vjunk", "Fay-Realm", "GUILD"),
                        ("V100.0.0", "Gus-Realm", "PARTY"), ("V100.0.0", L.eval("PLAYER.name") + "-Realm", "GUILD")]:
    L.execute("RECV('KingMaker1', %r, %r, %r)" % (text, who, chan))
L.execute("RECV('OtherAddon', 'V100.0.0', 'Hal-Realm')")
assert len(outputs(L)) == n, outputs(L)[n:]
# an older version says hello: we answer it after a short wait, unless someone as new as us answers first
L.execute("SENT = {}; TIMERS = {}; RECV('KingMaker1', 'V1.0.0', 'Ivy-Realm')")
L.execute("RECV('KingMaker1', 'R' .. KingMaker.version, 'Jon-Realm'); RUN_TIMERS()")
assert not [m for m in L.eval("SENT").values() if m.prefix == "KingMaker1"], "someone else answered: we stay quiet"
L.execute("UPTIME = UPTIME + 120; SENT = {}; RECV('KingMaker1', 'V1.0.0', 'Kim-Realm'); RUN_TIMERS()")
sent = [m.text for m in L.eval("SENT").values() if m.prefix == "KingMaker1"]
assert sent == ["R" + ver], sent
L.execute("SENT = {}; RECV('KingMaker1', 'V1.0.0', 'Lou-Realm'); RUN_TIMERS()")
assert not [m for m in L.eval("SENT").values() if m.prefix == "KingMaker1"], "at most one answer a minute"
# the setting turns the line off (we still say our version); not in a guild: nothing is sent
L.execute("KingMakerDB.ui.versionNotice = false"); n = len(outputs(L))
L.execute("RECV('KingMaker1', 'V200.0.0', 'Max-Realm')"); assert len(outputs(L)) == n
L2, KM2 = fresh(only=[], seed="IN_GUILD = false")
L2.execute("RUN_TIMERS()")
assert not [m for m in L2.eval("SENT").values() if m.prefix == "KingMaker1"], "no guild, no message"
print("VERSION CHECK OK")

# --- the chart kit (Core\Chart.lua), the UI.HUD options and the one item value rule (Core\Items.lua) -------------
L, KM = fresh(only=[])
L.execute("""
local UI = KingMaker.UI
CH = UI.Chart(UIParent, 400, 120)
CH:Draw({ series = {
    { pts = { { 1, 10 }, { 2, 30 }, { 3, 20 } }, style = "line" },
    { pts = { { 1, 5, { 1, 0, 0, 1 } }, { 2, 6 }, { 3, 7 } }, style = "bars", agg = "none", color = UI.C.accent } },
  ref = { y = 15, label = "avg 15" }, endLabel = true, xformat = function(x) return "m" .. x end,
  format = function(y) return "y" .. math.floor(y) end, click = function(x, p) CLICKED = x end })
""")
ch = L.eval("CH")
assert L.eval("LINES") >= 2 and ch.lines.used == 2, "a line chart draws segments"
assert ch.bars.used == 3 and list(ch.bars[1].color.values())[:3] == [1, 0, 0], "per-bar colours"
assert ch.refLine.shown and ch.refText.text == "avg 15" and ch.endDot.shown and ch.endText.text == "y20"
assert ch.xlabels[1].text == "m1" and ch.xlabels[3].text == "m3" and ch.ylabels[0].text == "y0", "bars start the axis at 0"
L.execute("CH:Click()"); assert L.eval("CLICKED") == 1, "click the nearest point"
L.execute("CH:SetSize(600, 150)"); assert ch.w == 600 and ch.pw == 600 - 78 and ch.bars.used == 3, "SetSize redraws the last chart"
L.execute("CH:Draw({ series = { { pts = { { 1, -50 }, { 2, 80 } }, style = 'bars', agg = 'none' } } })")
assert ch.zeroLine.shown and ch.ymin < 0, "negatives get a zero line"
L.execute("CH:Draw({ series = { { pts = { { 0, 0 }, { 1, 10 }, { 2, 30 } }, style = 'area', agg = 'last' } } })")
assert ch.bars.used == 2 and ch.lines.used == 2, "area: a line with a wash under it"
L.execute("CH:Draw({ series = {}, emptyText = 'Nothing yet' })"); assert ch.empty.text == "Nothing yet" and ch.bars.used == 0
# sum bucketing for long series
L.execute("local pts = {} for i = 1, 1000 do pts[i] = { i, 1 } end CH:Draw({ tmin = 1, tmax = 1000, series = { { pts = pts, style = 'bars', agg = 'sum' } } })")
assert ch.bars.used < 1000 and ch.ymax >= 5, "summed into buckets"
# ranked bars, the sparkline and the split bar (econ.py checks Econ's graph through the shim)
L.execute("""
local UI = KingMaker.UI
HB = UI.HBars(UIParent, 300, 18, 4)
HB:SetRows({ { label = "Mob drops", value = "31g", frac = 1 }, { label = "Coin", value = "6g", frac = 0.2, tip = "coin" } })
SP = UI.Spark(UIParent, 120, 18, 30); SP:Set({ 1, 2, 4, 0 })
SB = UI.SplitBar(UIParent, 200, 6); SB:Set({ { 0.6, UI.C.accent }, { 0.4, UI.C.good }, { 0, UI.C.bad } })
""")
hb = L.eval("HB")
assert hb.rows[1].shown and hb.rows[2].shown and not hb.rows[3].shown and hb.rows[1].value.text == "31g"
assert abs(hb.rows[2].fill.w / hb.rows[1].fill.w - 0.2) < 1e-6, "bars ranked by fraction"
sp = L.eval("SP"); assert sp.shownBars == 4 and sp.bars[3].h == 18 and not sp.bars[5].shown
sb = L.eval("SB"); assert sb.segs[1].shown and sb.segs[2].shown and abs(sb.segs[1].w + sb.segs[2].w - 198) < 1e-6
# UI.HUD's new options (old callers unchanged)
L.execute("""
local UI = KingMaker.UI
ZOOM = 1
HUD = UI.HUD("TestHUD", "Test", 280, { status = true, buttons = { { label = "L", tip = "ledger", onClick = function() LCLICK = true end } },
  onWheel = function(d) WHEEL = d end, zoom = { get = function() return ZOOM end, set = function(z) ZOOM = z end } })
HUD:SetStatus(UI.C.good); HUD:SetRightText("0:42:17")
HUD.extra[1]:Click()
HUD.scripts.OnMouseWheel(HUD, -1)
CTRL = true; HUD.scripts.OnMouseWheel(HUD, 1); HUD.scripts.OnMouseWheel(HUD, 1); CTRL = false
PLAIN = UI.HUD("PlainHUD", "Plain", 268)
""")
hud = L.eval("HUD")
assert hud.dot and list(hud.dot.vertex.values())[1] == L.eval("KingMaker.UI.C.good[2]") and hud.right.text == "0:42:17"
assert L.eval("LCLICK") is True and L.eval("WHEEL") == -1 and abs(L.eval("ZOOM") - 1.1) < 1e-9, "Ctrl+wheel zooms"
assert L.eval("PlainHUD.dot") is None and L.eval("PlainHUD.right") is not None, "old callers get no status square"
L.execute("for i = 1, 20 do CTRL = true; HUD.scripts.OnMouseWheel(HUD, 1) end CTRL = false")
assert abs(L.eval("ZOOM") - 1.4) < 1e-9, "zoom stops at 140%"
# the one value rule: vendor without the Scanner, quest items 0, nil until the item loads
L.execute('ITEM(2318, "Light Leather", { quality = 1, sell = 15, class = 7 }); ITEM(5000, "Quest Fang", { class = 12 }); ITEM(4865, "Ruined Pelt", { quality = 0, sell = 5 })')
assert KM.ItemValue(2318) == (15, "vendor") and KM.ItemValue(5000) == (0, "quest") and KM.ItemValue(4865) == (5, "vendor")
assert KM.ItemValue(123456) is None and L.eval("REQUESTED") == 123456, "not loaded yet: nil, and a load is requested"
assert "Light Leather" in KM.ItemText(2318) and KM.ItemText(123456) == "|cffffffffItem 123456|r"
L.execute("ScannerKing = { GetMarketPrice = function(id) if id == 2318 then return 100 end end }")
assert KM.ItemValue(2318) == (95, "ah"), "the AH after its 5% cut, when that beats the vendor"
print("CHARTS OK")

print("core: ok")
