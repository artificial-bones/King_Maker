# Market (was Market King), with Scanner: recipes, disenchant tables, profit math, ranking and the red line,
# Market Scan as a Scanner scan provider, recipes learned from trade skill windows, have/don't-have marks,
# vendor prices, /mk and the Crafting Profits page.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# item details the game would know: name, quality, item level, sell price, class (2 weapon, 4 armor, 7 trade goods)
EXTRA = """
ITEM(2840, "Copper Bar", { quality = 1, ilvl = 10, sell = 25, class = 7 })
ITEM(2770, "Copper Ore", { quality = 1, ilvl = 10, sell = 5, class = 7 })
ITEM(2880, "Weak Flux", { quality = 1, ilvl = 10, sell = 25, class = 7 })
ITEM(2589, "Linen Cloth", { quality = 1, ilvl = 5, sell = 13, class = 7 })
ITEM(2851, "Copper Chain Belt", { quality = 2, ilvl = 18, sell = 100, class = 4 })   -- green armor, DEs
ITEM(2852, "Copper Chain Pants", { quality = 1, ilvl = 9, sell = 50, class = 4 })
ITEM(10940, "Strange Dust", { quality = 1, ilvl = 1, sell = 0, class = 7 })
ITEM(10939, "Greater Magic Essence", { quality = 1, ilvl = 1, sell = 0, class = 7 })
ITEM(10978, "Small Glimmering Shard", { quality = 1, ilvl = 1, sell = 0, class = 7 })
ITEM(1251, "Linen Bandage", { quality = 1, ilvl = 5, sell = 10, class = 0 })
-- no Trade Goods browse: the Scanner falls back to one search per item (AH_PRICES)
C_AuctionHouse.SendBrowseQuery = function() end
C_AuctionHouse.SearchForItemKeys = function() end
-- a King Maker button with this label inside frame `inside` (a page), or anywhere
function PBTN(inside, text)
  for _, f in ipairs(FRAMES) do
    if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then
      local p = f.parent
      while p and p ~= inside do p = p.parent end
      if p then return f end
    end
  end
end
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
"""

L, KM = fresh(only=["Scanner", "Market"], extra=EXTRA)
ns = KM.mods.Market
mk = L.eval("SlashCmdList.MARKETKING")


def fonts():
    fs = L.eval("FONTS")
    return [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]


def click(b, which="LeftButton"): b.RunScript(b, "OnClick", which)


assert L.eval("MarketKingMinimapButton") is None and L.eval("MarketKingFrame") is None, "no window or button of its own"
assert L.eval("MarketKingDB.mode") == "buy" and L.eval("MarketKingDB.includeDE") is True and L.eval("MarketKingDB.ui.button") is None

# Data loaded
assert ns.RECIPES[2661][1] == 2851  # Copper Chain Belt
recipes = list(ns.Recipes().values()); assert len(recipes) > 1100
# disenchant table: green armor ilvl 18 -> mostly Strange Dust; a weapon swaps to mostly essence
de = ns.DisenchantResults(2, 18, 4); assert de[1][1] == 10940 and abs(de[1][2] - 0.75 * 2.5) < 1e-9
dw = ns.DisenchantResults(2, 18, 2); assert dw[1][1] == 10940 and abs(dw[1][2] - 0.20 * 2.5) < 1e-9 and abs(dw[2][2] - 0.75 * 1.5) < 1e-9
assert ns.DisenchantResults(1, 18, 4) is None and ns.DisenchantResults(2, 18, 7) is None
# the King Dashboard runs Data/Recipes.lua on its own with a bare table for `...`: it must still work
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
for fn in ("Recipes", "Patterns", "Disenchant", "Vendor"):
    src = open(os.path.join(ROOT, "Modules", "Market", "Data", fn + ".lua"), encoding="utf-8").read()
    L.globals().SRC = src
    n = L.eval("(function() local ns = {} local f = assert(loadstring(SRC)) f('Market_King', ns) local c = 0 for _ in pairs(ns.RECIPES or ns.PATTERNS or ns.DE_UNCOMMON or ns.VENDOR_ITEMS) do c = c + 1 end return c end)()")
    assert n > 5, (fn, n)
print("DATA OK")

# Pick Blacksmithing and First Aid, scan at the auction house
L.execute("""
AH_PRICES = { [2840] = 100, [2770] = 40, [2589] = 20, [2851] = 2000, [2852] = 300, [1251] = 30,
              [10940] = 150, [10939] = 600, [10978] = 800 }
""")
items = list(ns.ItemsToScan(L.eval("{ [2] = true, [1] = true }")).values())
assert 2851 in items and 2840 in items and 10940 in items and 2880 not in items  # crafted, reagent, DE mat; flux is a vendor item
# Scanner's title bar has Material Scan and Market Scan; Market Scan offers our professions
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
tb = KM.mods.Scanner.TitleButtons()
ms = tb.market; assert ms and ms.shown and tb.mat.label.text == "Material Scan"
click(ms)  # opens with every profession ticked
checks = [f for f in L.eval("FRAMES").values() if f.key is not None and f.checked is not None]
assert len(checks) == 9 and all(c.checked for c in checks)
click(L.eval("BTN('None')"))
assert not any(c.checked for c in checks)
# tick Blacksmithing and First Aid only, then Scan
for c, name in zip(checks, [p.name for p in ns.PROFESSIONS.values()]):
    if name in ("Blacksmithing", "First Aid"): click(c)  # ticks it and enables Scan
L.execute("SCANNED = nil; local real = ScannerKing.Scan; ScannerKing.Scan = function(o) SCANNED = o and #o.items; return real(o) end")
click(L.eval("BTN('Scan')"))
L.execute("RUN_TIMERS()")
assert L.eval("SCANNED") == len(items)
assert L.eval("ScannerKingDB.prices[2851].p") == 2000
# Crafting Profits opened on exactly what was scanned
assert L.eval("MarketKingDB.profs[2]") and L.eval("MarketKingDB.profs[1]") and not L.eval("MarketKingDB.profs[9]")
assert KM.IsShown("crafting") and not KM.errorShown, last(L)

# Copper Chain Belt: 6 Copper Bar -> green belt (sells 2000, DE ~ 0.75*2.5*150 + 0.2*1.5*600 + 0.05*800)
belt = [r for r in recipes if r.spell == 2661][0]
row = ns.Evaluate(belt, "buy")
assert row.cost == 600 and abs(row.craft - (2000 * 0.95 - 600)) < 1e-6
de_each = 0.75 * 2.5 * 150 + 0.2 * 1.5 * 600 + 0.05 * 800
assert abs(row.deEach - de_each) < 1e-6 and abs(row.de - (de_each * 0.95 - 600)) < 1e-6
assert row.best == "craft" and row.gain > 0
farm = ns.Evaluate(belt, "farm")
assert abs(farm.raw - 600 * 0.95) < 1e-6 and abs(farm.craft - 2000 * 0.95) < 1e-6 and abs(farm.gain - (2000 * 0.95 - 570)) < 1e-6
# Copper Chain Pants (4 bars -> 300): not worth crafting
pants = ns.Evaluate([r for r in recipes if r.spell == 2662][0], "buy")
assert pants.gain < 0
# Weak Flux has no auction price but is a vendor item: cost comes from its vendor value
flux_recipe = [r for r in recipes if r.prof == 2 and 2880 in list(r.reagents.values())][0]
fr = ns.Evaluate(flux_recipe, "buy"); assert fr.mats[[m.id for m in fr.mats.values()].index(2880) + 1].unit == 100  # 25 sell x 4
# Craft shows the sale value; profit is that minus the materials
assert abs(row.craftSale - 2000 * 0.95) < 1e-6 and abs(row.craftSale - row.cost - row.gain) < 1e-6
# without disenchanting
nde = ns.Evaluate(belt, "buy", L.table_from({"noDE": True})); assert nde.de is None and nde.deSale is None and nde.best == "craft"
# DE only: only disenchantable items, judged on disenchanting alone
do = ns.Evaluate(belt, "buy", L.table_from({"deOnly": True})); assert do.craft is None and do.best in ("de", "raw")
derows, _ = ns.Rank(2, "buy", L.table_from({"deOnly": True}))
derows = list(derows.values()); assert derows and all(r.deResults for r in derows) and len(derows) < len(list(ns.Rank(2, "buy")[0].values()))
# No procs: the 5% shard drops out of the disenchant value
assert de[3][3] and not de[1][3]
de_base = 0.75 * 2.5 * 150 + 0.2 * 1.5 * 600
np_ = ns.Evaluate(belt, "buy", L.table_from({"deOnly": True, "noProcs": True}))
assert abs(np_.deBaseEach - de_base) < 1e-6 and abs(np_.deSale - de_base * 0.95) < 1e-6 and abs(np_.deSaleProcs - de_each * 0.95) < 1e-6
assert abs(np_.de - (de_base * 0.95 - 600)) < 1e-6
print("PROFIT OK")

# Ranking and the red line
rows, above = ns.Rank(2, "buy")
rows = list(rows.values())
assert rows[0].gain >= rows[1].gain and above >= 1
assert all(r.gain > 0 for r in rows[:above]) and all((r.gain or 0) <= 0 for r in rows[above:])
best, ab2 = ns.Rank(None, "buy"); assert len(list(best.values())) > len(rows)
# the page draws it (headers are drawn in capitals)
t = fonts()
assert "Best" in t and "Blacksmithing" in t and "First Aid" in t and "PROFIT" in t, t[:60]
assert any("above the red line" in str(x) for x in t), ns.footer.text
assert any("Copper Chain Belt" in str(x) for x in t)
assert ns.redLine.shown, "the red line is drawn under the last row that beats not crafting"
shown_rows, ab = ns.CurrentRows()
assert ab >= 1 and list(shown_rows.values())[0].gain > 0
# the Best column is a pill
r1 = ns.table.rows[1]
assert r1.best.text.text in ("CRAFT", "DISENCHANT"), r1.best.text.text
# hovering a row gives the full breakdown
r1.RunScript(r1, "OnEnter")
tip = [str(x) for x in L.eval("GameTooltip.lines").values()]
assert any(x.startswith("Mat cost|") for x in tip) and any(x.startswith("Profit|") for x in tip), tip
assert any("Taught by a trainer" in x for x in tip)
r1.RunScript(r1, "OnLeave")
mk("mode farm"); t = fonts()
assert "RAW VALUE" in t and "GAIN VS RAW" in t, t
assert "Ethical Gaming" in t and "Yrgna Special" in t
assert L.eval("BTN('Ethical Gaming')").active and not L.eval("BTN('Yrgna Special')").active
# vendor prices seen at a merchant replace the estimate
L.execute("""
C_MerchantFrame = nil
GetMerchantNumItems = function() return 1 end
GetMerchantItemID = function() return 2880 end
GetMerchantItemInfo = function() return "Weak Flux", 0, 95, 1, -1, true, true, nil end
FIRE("MERCHANT_SHOW")
""")
assert L.eval("MarketKingDB.vendor[2880]") == 95
# Listed counts come through from the Scanner
assert row.listed is None or row.listed >= 0
L.execute("ScannerKingDB.prices[2851].q = 7")
assert ns.Evaluate(belt, "buy").listed == 7
mk("mode buy"); t = fonts()
assert "LISTED" in t and "7" in t
L.execute("MarketKingDB.includeDE = false"); mk(""); mk("")
assert KM.IsShown("crafting")
assert "CRAFT SELLS" in fonts()
de_btn = L.eval("BTN('DE only')")
click(de_btn); assert L.eval("MarketKingDB.deOnly") == True and de_btn.active
assert "DE SELLS" in fonts()
assert all(r.deResults for r in ns.CurrentRows()[0].values())
assert any(r.de is not None for r in ns.CurrentRows()[0].values()), "DE only counts disenchanting even with Include disenchanting off"
click(de_btn); L.execute("MarketKingDB.includeDE = true"); KM.Refresh()
assert KM.IsShown("crafting")
# with every profession ticked the tabs switch to short names so they fit
L.execute("for _, p in ipairs({1,2,3,4,6,7,8,9,10}) do MarketKingDB.profs[p] = true end")
mk(""); mk("")
labels = fonts()
assert "Leather" in labels and "Tailor" in labels, labels
# a profession tab shows just that profession
smith = [f for f in L.eval("FRAMES").values() if type(f.label) != type(None) and f.SetLabel and getattr(f.label, "text", None) == "Smith" and f.shown != False][0]
click(smith)
assert all(r.prof == 2 for r in ns.CurrentRows()[0].values())
# unticking a profession on the page filters it out
c_fa = [f for f in L.eval("FRAMES").values() if f.prof == 1][0]
c_fa.RunScript(c_fa, "OnClick"); assert L.eval("MarketKingDB.profs[1]") is None
L.globals().MKPAGE = ns.Page(); all_btn = L.eval("PBTN(MKPAGE, 'All')"); click(all_btn)
assert all(L.eval("MarketKingDB.profs[%d]" % p) for p in (1, 2, 3, 4, 6, 7, 8, 9, 10))
click(all_btn); assert L.eval("next(MarketKingDB.profs)") is None
assert "Tick the professions" in ns.footer.text
L.execute("MarketKingDB.profs = { [2] = true, [1] = true }"); mk(""); mk("")
assert not KM.errorShown, last(L)
print("UI OK")

# Recipes from your own trade skill window (anything new in Forever)
L.execute("""
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Blacksmithing" } end,
  GetAllRecipeIDs = function() return { 2661, 999001 } end,
  GetRecipeSchematic = function(id) return { outputItemID = 777001, quantityMin = 1,
    reagentSlotSchematics = { { reagents = { { itemID = 2840 } }, quantityRequired = 3 } } } end,
}
FIRE("TRADE_SKILL_LIST_UPDATE")
""")
assert L.eval("MarketKingDB.learned[999001][1]") == 777001 and L.eval("MarketKingDB.learned[2661]") is None
assert any("Learned 1 new Blacksmithing recipe" in str(o) for o in outputs(L)), outputs(L)[-3:]

# Patterns: trainer recipes are yours, pattern recipes aren't until a trade skill window shows them
assert ns.PATTERNS[2661] is None and ns.HasRecipe(2661)            # Copper Chain Belt: trainer
assert ns.PATTERNS[3321] is not None and not ns.HasRecipe(3321) and not ns.HasRecipe(3325)  # Plans
assert len(list(ns.PATTERNS)) > 700
# Classic trade skill window lists what you know (by recipe link, or by the item it makes)
L.execute("""
C_TradeSkillUI = nil
TS = { { "Armor", "header" }, { "Copper Chain Vest", "easy", link = "|Henchant:3321|h", item = 3471 },
       { "Gemmed Copper Gauntlets", "easy", item = 3474 } }
GetTradeSkillLine = function() return "Blacksmithing" end
GetNumTradeSkills = function() return #TS end
GetTradeSkillInfo = function(i) return TS[i][1], TS[i][2] end
GetTradeSkillRecipeLink = function(i) return TS[i].link end
GetTradeSkillItemLink = function(i) return TS[i].item and ("|Hitem:" .. TS[i].item .. ":0|h") end
FIRE("TRADE_SKILL_SHOW")
""")
assert ns.HasRecipe(3321) and "pattern recipe" in last(L), last(L)
assert ns.HasRecipe(3325)                                         # Gemmed Copper Gauntlets (Plans), matched by item
# NEW_RECIPE_LEARNED marks one known straight away
lacking0 = [s for s in ns.PATTERNS.keys() if ns.RECIPES[s][2] == 2 and not ns.HasRecipe(s)]
L.execute('FIRE("NEW_RECIPE_LEARNED", %d)' % lacking0[-1]); assert ns.HasRecipe(lacking0[-1])
L.execute("MarketKingDB.chars[next(MarketKingDB.chars)].known[%d] = nil" % lacking0[-1])
# right-click marks: off and back on; a mark that matches what we'd work out isn't stored
ns.SetHasRecipe(3321, False); assert not ns.HasRecipe(3321)
ns.SetHasRecipe(3321, True); assert ns.HasRecipe(3321) and L.eval("next(MarketKingDB.chars[next(MarketKingDB.chars)].owned)") is None
lacking = [s for s in ns.PATTERNS.keys() if ns.RECIPES[s][2] == 2 and not ns.HasRecipe(s)]
ns.SetHasRecipe(lacking[0], True); assert ns.HasRecipe(lacking[0])
# filters
allr = list(ns.Rank(2, "buy", L.table_from({"recipes": "all"}))[0].values())
mine = list(ns.Rank(2, "buy", L.table_from({"recipes": "mine"}))[0].values())
miss = list(ns.Rank(2, "buy", L.table_from({"recipes": "missing"}))[0].values())
assert len(mine) + len(miss) == len(allr) and all(r.has for r in mine) and all(not r.has and r.pattern for r in miss)
assert any(r.recipe.spell == lacking[0] for r in mine)
# patterns you lack are greyed out in "All recipes"
click([f for f in L.eval("FRAMES").values() if type(f.label) != type(None) and f.SetLabel and getattr(f.label, "text", None) == "Best" and f.shown != False][0])
# the button cycles the view; right-clicking a row toggles it
btn = L.eval("BTN('All recipes')"); click(btn); assert L.eval("MarketKingDB.recipes") == "mine"
assert btn.label.text == "My recipes"
click(btn); assert L.eval("MarketKingDB.recipes") == "missing"
row_btn = [r for r in ns.table.rows.values() if r.data is not None and r.shown != False][0]
spell = row_btn.data.recipe.spell; assert not ns.HasRecipe(spell)
click(row_btn, "RightButton"); assert ns.HasRecipe(spell)
click(btn); assert L.eval("MarketKingDB.recipes") == "all"
greyed = [r for r in ns.table.rows.values() if r.data is not None and r.shown != False and not r.data.has]
assert all(r.alpha < 1 for r in greyed)
mk("recipes reset"); assert not ns.HasRecipe(spell) and ns.HasRecipe(3321)
mk("recipes mine"); assert L.eval("MarketKingDB.recipes") == "mine"
mk("recipes bogus"); assert L.eval("MarketKingDB.recipes") == "all"
assert not KM.errorShown, last(L)
print("PATTERNS OK")

# /mk, the crown and Settings
mk("button"); assert "crown" in last(L), last(L)
mk("help"); assert any("/mk mode" in str(o) for o in outputs(L))
mk("mode"); assert L.eval("MarketKingDB.mode") == "farm" and "Ethical Gaming" in last(L)
mk("mode"); assert L.eval("MarketKingDB.mode") == "buy" and "Yrgna Special" in last(L)
L.execute("SCAN_OPENED = false; local real = ScannerKing.OpenMarketScan; ScannerKing.OpenMarketScan = function() SCAN_OPENED = true end")
mk("scan"); assert L.eval("SCAN_OPENED")
click(L.eval("BTN('Market Scan')"))  # the page's own button (the title-bar one is the Scanner's)
KM.Toggle(False)
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Crafting Profits") ~= nil')
L.execute('MENU_ITEM("Crafting Profits").fn()'); assert KM.IsShown("crafting")
KM.OpenSettings("market"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
t = fonts()
assert "Count materials as" in t and "Include disenchanting" in t and any("/mk recipes" in str(x) for x in t)
farm_choice = [f for f in L.eval("FRAMES").values() if type(f.label) != type(None) and f.SetLabel and getattr(f.label, "text", None) == "Ethical Gaming" and f.shown != False][-1]
click(farm_choice); assert L.eval("MarketKingDB.mode") == "farm"
mk("mode buy")
for pid in ("home", "prices", "settings", "crafting"):
    KM.Show(pid); assert not KM.errorShown, (pid, last(L))
mk(""); assert not KM.IsShown(), "/mk toggles the page closed"
print("SHELL OK")

# InitDB is safe twice and keeps the table; old minimap keys go; shapes stay
L2, KM2 = fresh(only=["Scanner", "Market"], extra=EXTRA,
                seed="MarketKingDB = { profs = { [3] = true }, mode = 'farm', includeDE = false, chars = { ['Jay-Forever'] = { known = { [3321] = true }, owned = { [2661] = false } } }, ui = { button = false, buttonAngle = 30 } }")
L2.execute("HELD = MarketKingDB"); KM2.mods.Market.InitDB()
assert L2.eval("MarketKingDB == HELD") and L2.eval("MarketKingDB.mode") == "farm" and L2.eval("MarketKingDB.includeDE") is False
assert L2.eval("MarketKingDB.ui.button") is None and L2.eval("MarketKingDB.ui.buttonAngle") is None
assert L2.eval("MarketKingDB.recipes") == "all" and L2.eval("MarketKingDB.vendor") is not None
ns2 = KM2.mods.Market
assert ns2.HasRecipe(3321) and not ns2.HasRecipe(2661)
KM2.Show("crafting"); assert not KM2.errorShown, last(L2)
# moved in from a 1.x stub folder
L3, KM3 = fresh(only=["Scanner", "Market"], extra=EXTRA, stubs={"Market_King": "MarketKingDB = { profs = { [8] = true }, recipes = 'mine' }"})
assert L3.eval("MarketKingDB.profs[8]") and L3.eval("MarketKingDB.recipes") == "mine" and L3.eval("MarketKingDB.mode") == "buy"
# Market without Scanner still loads and opens
L4, KM4 = fresh(only=["Market"], extra=EXTRA)
KM4.Show("crafting"); assert not KM4.errorShown, last(L4)
L4.eval("SlashCmdList.MARKETKING")("scan"); assert "Scanner" in last(L4)
print("INITDB OK")

print("market: ok")
