# Skillup (was Skillup King), with Scanner: skill colors and chances, the cost of one craft, the plan and its
# trainer lines and gaps, At my skill, skills and known recipes (skill list, trade skill windows), vendor prices,
# Scan prices, /suk, the public SkillupKing.Plan and the Skill-ups page.
import os, sys, math; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

EXTRA = """
ITEM(2589, "Linen Cloth", { quality = 1, ilvl = 5, sell = 13, class = 7 })
ITEM(2592, "Wool Cloth", { quality = 1, ilvl = 15, sell = 33, class = 7 })
ITEM(1251, "Linen Bandage", { quality = 1, ilvl = 5, sell = 10, class = 0 })
ITEM(2581, "Heavy Linen Bandage", { quality = 1, ilvl = 10, sell = 20, class = 0 })
ITEM(3530, "Wool Bandage", { quality = 1, ilvl = 15, sell = 28, class = 0 })
ITEM(6454, "Manual: Strong Anti-Venom", { quality = 1, ilvl = 26, sell = 250, class = 9 })
ITEM(2320, "Coarse Thread", { quality = 1, ilvl = 5, sell = 2, class = 7 })
-- the character's skill list (Classic API): First Aid 55/150, Tailoring 80/150
SKILLS = { { "Professions", true }, { "First Aid", false, 55, 150 }, { "Tailoring", false, 80, 150 }, { "Swords", false, 200, 210 } }
GetNumSkillLines = function() return #SKILLS end
GetSkillLineInfo = function(i) local s = SKILLS[i]; return s[1], s[2], true, s[3], 0, 0, s[4] end
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function PRICE(id, p, m) ScannerKingDB.prices[id] = { p = p, m = m, t = NOW } end
"""

L, KM = fresh(only=["Scanner", "Skillup"], extra=EXTRA)
ns = KM.mods.Skillup
suk = L.eval("SlashCmdList.SKILLUPKING")
API = L.eval("SkillupKing")


def fonts():
    fs = L.eval("FONTS")
    return [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]


def click(b, which="LeftButton"): b.RunScript(b, "OnClick", which)


assert API.API_VERSION == 1 and L.eval("SkillupKingMinimapButton") is None and L.eval("SkillupKingFrame") is None
assert L.eval("SkillupKingDB.ui.de") is True and L.eval("SkillupKingDB.ui.sell") is True and L.eval("SkillupKingDB.ui.view") == "plan"

# Data and colors
rs = list(ns.Recipes().values())
assert len(rs) > 1000 and all(rs[i].orange <= rs[i + 1].orange for i in range(len(rs) - 1)), "sorted by orange"
linen = [r for r in rs if r.spell == 3275][0]      # Linen Bandage: orange 1, yellow 30, grey 60
heavy = [r for r in rs if r.spell == 3276][0]      # Heavy Linen Bandage: 40, 50, 100
assert (linen.orange, linen.yellow, linen.green, linen.grey) == (1, 30, 45, 60)
assert ns.Color(linen, 10) == "orange" and ns.Color(linen, 30) == "yellow" and ns.Color(linen, 45) == "green" and ns.Color(linen, 60) == "grey"
assert ns.Color(heavy, 39) is None and ns.Chance(heavy, 39) is None
assert ns.Chance(linen, 29) == 1 and abs(ns.Chance(linen, 45) - 0.5) < 1e-9 and ns.Chance(linen, 60) == 0
assert ns.FindProfession("first aid").id == 1 and ns.FindProfession(" Smelting ").id == 7 and ns.FindProfession("bogus") is None
assert ns.PROF_BY_NAME["Smelting"].id == 7
# the King Dashboard may run the data files on their own with a bare table for `...`
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
for fn in ("Recipes", "Patterns", "Disenchant", "Vendor"):
    L.globals().SRC = open(os.path.join(ROOT, "Modules", "Skillup", "Data", fn + ".lua"), encoding="utf-8").read()
    n = L.eval("(function() local ns = {} local f = assert(loadstring(SRC)) f('Skillup_King', ns) local c = 0 for _ in pairs(ns.RECIPES or ns.PATTERNS or ns.DE_UNCOMMON or ns.VENDOR_ITEMS) do c = c + 1 end return c end)()")
    assert n > 5, (fn, n)
print("DATA OK")

# Skills read at login from the skill list; per character
assert tuple(ns.Skill(1)) == (55, 150) and tuple(ns.Skill(8)) == (80, 150) and tuple(ns.Skill(4)) == (0, 0)
assert ns.StartSkill(1) == 55 and ns.StartSkill(4) == 1
assert L.eval("SkillupKingDB.chars['Jay-Forever'].skills[1].cur") == 55
L.execute("SKILLS[2][3] = 60; FIRE('SKILL_LINES_CHANGED')")
assert ns.Skill(1) == (60, 150)
# Recipes known: trainer recipes count as yours; patterns once a trade skill window shows them
assert ns.PATTERNS[7935] and not ns.HasRecipe(7935) and ns.HasRecipe(3275)
L.execute("""
TS = { { "Bandages", "header" }, { "Strong Anti-Venom", "easy", link = "|Henchant:7935|h" }, { "Wool Bandage", "easy", item = 3530 } }
GetTradeSkillLine = function() return "First Aid", 62, 150 end
GetNumTradeSkills = function() return #TS end
GetTradeSkillInfo = function(i) return TS[i][1], TS[i][2] end
GetTradeSkillRecipeLink = function(i) return TS[i].link end
GetTradeSkillItemLink = function(i) return TS[i].item and ("|Hitem:" .. TS[i].item .. ":0|h") end
FIRE("TRADE_SKILL_SHOW"); FIRE("TRADE_SKILL_UPDATE"); RUN_TIMERS()
""")
assert ns.HasRecipe(7935) and L.eval("SkillupKingDB.chars['Jay-Forever'].known[3277]"), "by recipe link, and by the item it makes"
assert ns.Skill(1) == (62, 150), "the window's skill wins"
# the modern trade skill window
L.execute("""
GetTradeSkillLine, GetNumTradeSkills = nil, nil
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Tailoring", skillLevel = 85, maxSkillLevel = 150 } end,
  GetAllRecipeIDs = function() return { 2387, 999001 } end,
  GetRecipeInfo = function(id) return { learned = id == 999001 } end,
}
FIRE("TRADE_SKILL_LIST_UPDATE"); RUN_TIMERS()
C_TradeSkillUI = nil
""")
assert ns.Skill(8) == (85, 150) and L.eval("SkillupKingDB.chars['Jay-Forever'].known[999001]") and not L.eval("SkillupKingDB.chars['Jay-Forever'].known[2387]")
L.execute("SKILLS[2][3] = 55; FIRE('SKILL_LINES_CHANGED')")
# vendor prices noted at a merchant
L.execute("""
C_MerchantFrame = nil
GetMerchantNumItems = function() return 1 end
GetMerchantItemID = function() return 2320 end
GetMerchantItemInfo = function() return "Coarse Thread", 0, 10, 1, -1, true, true, nil end
FIRE("MERCHANT_SHOW")
""")
assert L.eval("SkillupKingDB.vendor[2320]") == 10 and ns.VendorPrice(2320) == 10
assert ns.VendorPrice(2589) is None
print("SKILLS OK")

# One craft: materials, and the best of selling, disenchanting or a vendor
L.execute("PRICE(2589, 20); PRICE(1251, 30); PRICE(2581, 50, 60)")
ns.ClearCache()
c = ns.Craft(linen)
assert c.cost == 20 and c.how == "Sell" and abs(c.back - 30 * 0.95) < 1e-9 and abs(c.net - (20 - 28.5)) < 1e-9
ch = ns.Craft(heavy)
assert ch.cost == 40 and abs(ch.back - 60 * 0.95) < 1e-9, "a Deep Scan market price is what it sells for"
L.execute("SkillupKingDB.ui.sell = false"); ns.ClearCache()
c2 = ns.Craft(linen); assert c2.how == "Vendor" and c2.back == 10
L.execute("SkillupKingDB.ui.sell = true"); ns.ClearCache()
# an unpriced material is never free
wool = [r for r in rs if r.spell == 3277][0]
cw = ns.Craft(wool); assert cw.missing == 2592
print("CRAFT OK")

# The plan: at each skill, the cheapest point
plan = ns.Plan(1, 1, 40)
steps = list(plan.steps.values())
assert len(steps) == 1 and steps[0].r.spell == 3275 and steps[0]["from"] == 1 and steps[0].to == 40
exact = 29 + sum(30 / (60 - s) for s in range(30, 40))
assert abs(plan.crafts - exact) < 1e-6 and abs(plan.cost - exact * -8.5) < 1e-6
assert steps[0].crafts == math.ceil(exact - 0.05) and plan.gaps == 0
mats = list(plan.mats.values()); assert mats[0].id == 2589 and mats[0].n == math.ceil(exact - 0.05)
# to 80: Heavy Linen takes over where it's cheaper per point, and Journeyman is its own line at 75
plan = ns.Plan(1, 1, 80)
steps = list(plan.steps.values())
notes = [s.note for s in steps if s.note]
assert len(notes) == 1 and "Journeyman" in notes[0] and "needs level" not in notes[0]
assert any(s.r and s.r.spell == 3276 for s in steps)
assert all(steps[i].to == steps[i + 1]["from"] for i in range(len(steps) - 1) if not steps[i].note and not steps[i + 1].note)
# too low a level for the next trainer: said in red
L.execute("PLAYER.level = 5")
assert "needs level 10" in [s.note for s in ns.Plan(1, 1, 80).steps.values() if s.note][0]
L.execute("PLAYER.level = 42")
# nothing priced: a gap, not a free point
L.execute("ScannerKingDB.prices[2589] = nil")
gp = ns.Plan(1, 1, 40); assert gp.gaps == 39 and list(gp.steps.values())[0].gap and gp.cost == 0
L.execute("PRICE(2589, 20)")
# patterns you lack only count when allowed
assert not any(o.usable for o in ns.Options(1, 130).values() if o.r.spell == 7935 and not ns.HasRecipe(7935))
# public API
st, cost = API.Plan(1, 1, 40)
assert abs(cost - exact * -8.5) < 1e-6 and st[1].r.spell == 3275
print("PLAN OK")

# At my skill: every recipe you can make, cheapest point first
opts = list(ns.Options(1, 45).values())
lo = [o for o in opts if o.r.spell == 3275][0]
assert abs(lo.chance - 0.5) < 1e-9 and abs(lo.perPoint - (-8.5 / 0.5)) < 1e-6 and lo.color == "green"
ho = [o for o in opts if o.r.spell == 3276][0]
assert ho.color == "orange" and ho.chance == 1 and abs(ho.perPoint - (40 - 57)) < 1e-6
priced = [o.perPoint for o in opts if o.perPoint is not None]
assert priced == sorted(priced) and opts[0].perPoint is not None, "cheapest point first, unpriced last"
assert all(o.r.orange <= 45 for o in opts)
print("OPTIONS OK")

# The page
suk("")
assert KM.IsShown("skillups") and not KM.errorShown, last(L)
assert L.eval("SkillupKingDB.ui.prof") == 1, "opens on the first profession you have"
t = fonts()
assert any("First Aid: 55 / 150" in str(x) for x in t), [x for x in t if "First" in str(x)]
tables = ns.Tables()
assert tables.plan.shown is not False and tables.now.shown is False
assert any("Linen Bandage" in str(x) for x in t) or any("Heavy Linen" in str(x) for x in t)
assert "55 to 300: about" in ns.footer.text, ns.footer.text
assert "MAKE" in t and "PER POINT" in t and "GET BACK BY" in t
# a trainer line shows in the plan
assert any("Learn Journeyman" in str(x) for x in t) or any(r.data and r.data.note for r in tables.plan.rows.values())
# hovering a recipe row
row = [r for r in tables.plan.rows.values() if r.data and r.data.r][0]
row.RunScript(row, "OnEnter")
tip = [str(x) for x in L.eval("GameTooltip.lines").values()]
assert any(x.startswith("Materials|") for x in tip) and any(x.startswith("Each craft|") for x in tip), tip
row.RunScript(row, "OnLeave")
# From / To
L.globals().SUPAGE = ns.Page()
boxes = [f for f in L.eval("FRAMES").values() if f.SetNumeric is not None and f.hint is not None and f.parent is not None and f.text in ("55", "300")]
fromBox = [b for b in boxes if b.text == "55"][0]; toBox = [b for b in boxes if b.text == "300"][0]
fromBox.SetText(fromBox, "10"); fromBox.RunScript(fromBox, "OnEnterPressed")
assert L.eval("SkillupKingDB.ui.from[1]") == 10 and "10 to 300" in ns.footer.text
toBox.SetText(toBox, "40"); toBox.RunScript(toBox, "OnEnterPressed")
assert L.eval("SkillupKingDB.ui.to[1]") == 40 and "10 to 40" in ns.footer.text
fromBox.SetText(fromBox, ""); fromBox.RunScript(fromBox, "OnEnterPressed")
assert L.eval("SkillupKingDB.ui.from[1]") is None and "55 to 40" in ns.footer.text, "empty: back to your skill"
toBox.SetText(toBox, "300"); toBox.RunScript(toBox, "OnEnterPressed")
assert L.eval("SkillupKingDB.ui.to[1]") is None, "the default isn't pinned"
# Escape puts the saved value back
fromBox.SetText(fromBox, "99"); fromBox.RunScript(fromBox, "OnEscapePressed"); fromBox.RunScript(fromBox, "OnEditFocusLost")
assert L.eval("SkillupKingDB.ui.from[1]") is None and fromBox.text == "55"
# checkboxes
de = [f for f in L.eval("FRAMES").values() if f.key == "de" and f.SetChecked is not None and f.mark is not None][0]
assert de.checked
click(de); assert L.eval("SkillupKingDB.ui.de") is False
click(de); assert L.eval("SkillupKingDB.ui.de") is True
lack = [f for f in L.eval("FRAMES").values() if f.key == "lack" and f.mark is not None][0]
click(lack); assert L.eval("SkillupKingDB.ui.lack") is True
click(lack); assert L.eval("SkillupKingDB.ui.lack") is False
# shopping list
shop = L.eval("BTN('Shopping list')"); assert shop.shown is not False
shop.RunScript(shop, "OnEnter")
assert any("Total to buy" in str(x) for x in L.eval("GameTooltip.lines").values())
shop.RunScript(shop, "OnLeave")
click(shop); assert any("Shopping list, First Aid 55 to 300" in str(o) for o in outputs(L)), outputs(L)[-4:]
assert any("Linen Cloth" in str(o) for o in outputs(L)[-6:])
sl = list(ns.ShoppingList().values()); assert sl[0].id == 2589 and sl[0].cost == sl[0].n * 20
# At my skill
click(L.eval("BTN('At my skill')"))
assert L.eval("SkillupKingDB.ui.view") == "now" and tables.now.shown is not False and tables.plan.shown is False
assert "At skill 55" in ns.footer.text and shop.shown is False
assert "CHANCE" in fonts() and "COLOR" in fonts()
assert tables.now.data[1].perPoint is not None
click(L.eval("BTN('Plan')")); assert L.eval("SkillupKingDB.ui.view") == "plan"
# profession buttons
click(L.eval("BTN('Tailoring')")); assert L.eval("SkillupKingDB.ui.prof") == 8
assert any("Tailoring: 80 / 150" in str(x) for x in fonts())
click(L.eval("BTN('First Aid')"))
# Scan prices: only at the auction house
scan = L.eval("BTN('Scan prices')")
L.execute("AH_OPEN = false"); KM.Refresh()
assert not scan.enabled2
ns.ScanPrices(); assert "Open the auction house" in last(L)
L.execute("AH_OPEN = true; SCANNED = nil; ScannerKing.Scan = function(o) SCANNED = #o.items end"); KM.Refresh()
assert scan.enabled2
click(scan)
items = list(ns.ItemsToScan(1).values())
assert L.eval("SCANNED") == len(items) and "items for First Aid" in last(L)
assert 2589 in items and 1251 in items and 6454 in items and 2320 not in items  # reagents, products, patterns; not vendor thread
assert not KM.errorShown, last(L)
print("PAGE OK")

# /suk, the crown and Settings
suk(""); assert not KM.IsShown(), "/suk toggles the page closed"
suk("tailoring"); assert KM.IsShown("skillups") and L.eval("SkillupKingDB.ui.prof") == 8
suk("first aid"); assert KM.IsShown("skillups") and L.eval("SkillupKingDB.ui.prof") == 1, "stays open on another profession"
suk("button"); assert "crown" in last(L)
suk("help"); assert any("/suk tailoring" in str(o) for o in outputs(L))
KM.Toggle(False)
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Skill-ups") ~= nil')
L.execute('MENU_ITEM("Skill-ups").fn()'); assert KM.IsShown("skillups")
L.execute('KingMakerMinimapButton:RunScript("OnEnter")')
tip = [str(x) for x in L.eval("GameTooltip.lines").values()]
assert any("Skills: First Aid 55/150, Tailoring 80/150" in x for x in tip), tip
KM.OpenSettings("skillup"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
t = fonts()
assert "Disenchant what you make" in t and "Use patterns I don't have yet" in t and any("/suk tailoring" in str(x) for x in t)
for pid in ("home", "prices", "settings", "skillups"):
    KM.Show(pid); assert not KM.errorShown, (pid, last(L))
print("SHELL OK")

# InitDB is safe twice and keeps the table; old minimap keys go; shapes stay
L2, KM2 = fresh(only=["Scanner", "Skillup"], extra=EXTRA,
                seed="SkillupKingDB = { chars = { ['Jay-Forever'] = { known = { [7935] = true }, skills = { [3] = { cur = 113, max = 150 } } } }, vendor = { [2320] = 9 }, ui = { button = false, buttonAngle = 40, de = false, prof = 3 } }")
L2.execute("HELD = SkillupKingDB"); KM2.mods.Skillup.InitDB()
assert L2.eval("SkillupKingDB == HELD") and L2.eval("SkillupKingDB.ui.de") is False and L2.eval("SkillupKingDB.ui.sell") is True
assert L2.eval("SkillupKingDB.ui.button") is None and L2.eval("SkillupKingDB.ui.buttonAngle") is None
assert KM2.mods.Skillup.HasRecipe(7935) and L2.eval("SkillupKingDB.chars['Jay-Forever'].skills[3].cur") == 113
assert L2.eval("SkillupKingDB.vendor[2320]") == 9
KM2.Show("skillups"); assert not KM2.errorShown and L2.eval("SkillupKingDB.ui.prof") == 3, last(L2)
# moved in from a 1.x stub folder
L3, KM3 = fresh(only=["Scanner", "Skillup"], extra=EXTRA, stubs={"Skillup_King": "SkillupKingDB = { ui = { view = 'now', lack = true } }"})
assert L3.eval("SkillupKingDB.ui.view") == "now" and L3.eval("SkillupKingDB.ui.lack") is True and L3.eval("SkillupKingDB.chars") is not None
# Skillup without Scanner still loads and opens
L4, KM4 = fresh(only=["Skillup"], extra=EXTRA)
KM4.Show("skillups"); assert not KM4.errorShown, last(L4)
assert L4.eval("(function() for _, f in ipairs(FONTS) do if f.text and tostring(f.text):find('needs the Scanner', 1, true) then return true end end end)()")
print("INITDB OK")

print("skillup: ok")
