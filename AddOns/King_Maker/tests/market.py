# Market (was Market King), with Scanner: recipes, disenchant tables, profit math, ranking and the red line,
# a Scanner scan provider (the one Scan prices the ticked professions), recipes learned from trade skill windows, have/don't-have marks,
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
assert ns.AllSelected(), "every profession is picked by default"

# Data loaded
assert ns.RECIPES[2661][1] == 2851  # Copper Chain Belt
recipes = list(ns.Recipes().values()); assert len(recipes) > 1100
# disenchant table: green armor ilvl 18 -> mostly Strange Dust; a weapon swaps to mostly essence
de = ns.DisenchantResults(2, 18, 4); assert de[1][1] == 10940 and abs(de[1][2] - 0.75 * 2.5) < 1e-9
dw = ns.DisenchantResults(2, 18, 2); assert dw[1][1] == 10940 and abs(dw[1][2] - 0.20 * 2.5) < 1e-9 and abs(dw[2][2] - 0.75 * 1.5) < 1e-9
assert ns.DisenchantResults(1, 18, 4) is None and ns.DisenchantResults(2, 18, 7) is None
# the King Dashboard runs Data/Recipes.lua on its own with a bare table for `...`: it must still work
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
for fn in ("Recipes", "Patterns", "Disenchant", "Vendor", "Enchants"):
    src = open(os.path.join(ROOT, "Modules", "Market", "Data", fn + ".lua"), encoding="utf-8").read()
    L.globals().SRC = src
    n = L.eval("(function() local ns = {} local f = assert(loadstring(SRC)) f('Market_King', ns) local c = 0 for _ in pairs(ns.RECIPES or ns.ENCHANTS or ns.PATTERNS or ns.DE_UNCOMMON or ns.VENDOR_ITEMS) do c = c + 1 end return c end)()")
    assert n > 5, (fn, n)
print("DATA OK")

# Tick Blacksmithing and First Aid on Crafting Profits, then Scan at the auction house
L.execute("""
AH_PRICES = { [2840] = 100, [2770] = 40, [2589] = 20, [2851] = 2000, [2852] = 300, [1251] = 30,
              [10940] = 150, [10939] = 600, [10978] = 800 }
""")
items = list(ns.ItemsToScan(L.eval("{ [2] = true, [1] = true }")).values())
assert 2851 in items and 2840 in items and 10940 in items and 2880 not in items  # crafted, reagent, DE mat; flux is a vendor item
# The Scanner's title bar has one Scan; with no full dump on this client it's a quick scan, and the quick scan
# prices exactly the professions ticked on Crafting Profits (no picker dialog)
L.execute("MarketKingDB.profs = { [2] = true, [1] = true }")
assert L.eval("MarketKingDB.profs[2]") and L.eval("MarketKingDB.profs[1]") and not L.eval("MarketKingDB.profs[9]")
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
tb = KM.mods.Scanner.TitleButtons()
assert tb.scan.label.text == "Quick scan" and tb.market is None and tb.mat is None
L.execute("GameTooltip.lines = {}"); tb.scan.RunScript(tb.scan, "OnEnter")
tip = [str(x) for x in L.eval("GameTooltip.lines").values()]
assert any("for the 2 profession(s) ticked on Crafting Profits" in x for x in tip), tip
L.execute("SCANNED, KIND = nil, nil; local real = ScannerKing.Scan; ScannerKing.Scan = function(o) SCANNED = o and #o.items; return real(o) end")
L.execute("ScannerKing.RegisterCallback('mtest', function(e, res, kind) if e == 'SCAN_RESULTS' then KIND = kind end end)")
click(tb.scan)
L.execute("RUN_TIMERS()")
assert L.eval("ScannerKingMarketScan") is None, "no picker dialog"
assert L.eval("SCANNED") == len(items) and L.eval("KIND") == "market"
assert L.eval("ScannerKingDB.prices[2851].p") == 2000
# the selection is unchanged and the page isn't forced open over the auction house
assert L.eval("MarketKingDB.profs[2]") and L.eval("MarketKingDB.profs[1]") and not L.eval("MarketKingDB.profs[9]")
assert not KM.IsShown("crafting") and not KM.errorShown, last(L)

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
KM.Show("crafting")
t = fonts()
assert "All" in t and "Smith" in t and "First Aid" in t and "Leather" in t and "PROFIT" in t, t[:60]
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
assert "Use my mats" in t and "Buy mats" in t and not any("Yrgna" in x or "Ethical" in x for x in t)
assert L.eval("BTN('Use my mats')").active and not L.eval("BTN('Buy mats')").active
mk("mode buy"); assert L.eval("MarketKingDB.mode") == "buy"
mk("mode mine"); assert L.eval("MarketKingDB.mode") == "farm", "/mk mode mine = Use my mats"
assert any("Use my mats" in o for o in outputs(L)[-2:])
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
# profession tabs: All lights them all; with all lit a tab picks just that profession, then each click toggles one
L.globals().MKPAGE = ns.Page()
def tab(label): return L.eval("PBTN(MKPAGE, %r)" % label)
all_btn = tab("All")
click(all_btn)
assert ns.AllSelected() and all_btn.active and all(tab(x).active for x in ("Alch", "Smith", "Tailor", "First Aid"))
click(tab("Smith"))
assert all(r.prof == 2 for r in ns.CurrentRows()[0].values()) and len(list(ns.CurrentRows()[0].values())) > 0
assert tab("Smith").active and not tab("Tailor").active and not all_btn.active
assert L.eval("MarketKingDB.profs[2]") and L.eval("MarketKingDB.profs[8]") is None
click(tab("First Aid"))
assert {r.prof for r in ns.CurrentRows()[0].values()} == {1, 2} and tab("First Aid").active
click(tab("Smith"))
assert {r.prof for r in ns.CurrentRows()[0].values()} == {1} and not tab("Smith").active
click(tab("First Aid"))   # the last one off: back to all, never an empty list
assert ns.AllSelected() and all_btn.active
# search: any part of an item's name, any case; the counts and red line follow the filtered list
box = ns.search
box.SetText(box, "cHaIn"); box.RunScript(box, "OnTextChanged", True)
names = [ns.ItemName(r.item) for r in ns.CurrentRows()[0].values()]
assert names and all("chain" in n.lower() for n in names) and "Copper Chain Belt" in names, names[:5]
assert ns.CurrentRows()[1] <= len(names) and ns.footer.text.startswith("%d recipes" % len(names)), ns.footer.text
box.SetText(box, "zzqx"); box.RunScript(box, "OnTextChanged", True)
assert len(list(ns.CurrentRows()[0].values())) == 0 and "zzqx" in ns.table.emptyText
box.RunScript(box, "OnEscapePressed"); box.RunScript(box, "OnTextChanged", False)  # the game fires it on SetText
assert box.GetText(box) == "" and len(list(ns.CurrentRows()[0].values())) > len(names)
assert len(list(ns.Rank(None, "buy", L.table_from({"search": "  copper chain  "}))[0].values())) >= 2
L.execute("MarketKingDB.profs = { [2] = true, [1] = true }"); mk(""); mk("")
assert not KM.errorShown, last(L)
print("UI OK")

# Recipes from your own trade skill window (anything new in Forever)
L.execute("""
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Blacksmithing" } end,
  GetAllRecipeIDs = function() return { 2661, 2662, 999001 } end,
  GetRecipeSchematic = function(id)
    if id == 2661 then -- Copper Chain Belt, as our data has it
      return { outputItemID = 2851, quantityMin = 1, reagentSlotSchematics = { { reagents = { { itemID = 2840 } }, quantityRequired = 6 } } }
    elseif id == 2662 then -- Copper Chain Pants, changed since our data was made: 9 bars instead of 4
      return { outputItemID = 2852, quantityMin = 1, reagentSlotSchematics = { { reagents = { { itemID = 2840 } }, quantityRequired = 9 } } }
    end
    return { outputItemID = 777001, quantityMin = 2, quantityMax = 4,
      reagentSlotSchematics = { { reagents = { { itemID = 2840 } }, quantityRequired = 3 } } }
  end,
}
FIRE("TRADE_SKILL_LIST_UPDATE")
""")
assert L.eval("MarketKingDB.learned[999001][1]") == 777001 and L.eval("MarketKingDB.learned[999001][5]") == 3, "new: kept, made = average"
assert L.eval("MarketKingDB.learned[2661]") is None, "same as our data: nothing saved"
assert L.eval("MarketKingDB.learned[2662][4][2]") == 9, "changed: the window's reagents are saved"
r = ns.Recipe(2662)
assert r.reagents[2] == 9 and r.skill > 0, "and win, keeping our learn skill"
assert any("Learned 1 new Blacksmithing recipe" in str(o) for o in outputs(L)), outputs(L)[-3:]
assert any("1 Blacksmithing recipe(s) differ" in str(o) for o in outputs(L)), outputs(L)[-3:]

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
lacking0 = [s for s in ns.PATTERNS.keys() if ns.RECIPES[s] and ns.RECIPES[s][2] == 2 and not ns.HasRecipe(s)]
L.execute('FIRE("NEW_RECIPE_LEARNED", %d)' % lacking0[-1]); assert ns.HasRecipe(lacking0[-1])
L.execute("MarketKingDB.chars[next(MarketKingDB.chars)].known[%d] = nil" % lacking0[-1])
# right-click marks: off and back on; a mark that matches what we'd work out isn't stored
ns.SetHasRecipe(3321, False); assert not ns.HasRecipe(3321)
ns.SetHasRecipe(3321, True); assert ns.HasRecipe(3321) and L.eval("next(MarketKingDB.chars[next(MarketKingDB.chars)].owned)") is None
lacking = [s for s in ns.PATTERNS.keys() if ns.RECIPES[s] and ns.RECIPES[s][2] == 2 and not ns.HasRecipe(s)]
ns.SetHasRecipe(lacking[0], True); assert ns.HasRecipe(lacking[0])
# filters
allr = list(ns.Rank(2, "buy", L.table_from({"recipes": "all"}))[0].values())
mine = list(ns.Rank(2, "buy", L.table_from({"recipes": "mine"}))[0].values())
miss = list(ns.Rank(2, "buy", L.table_from({"recipes": "missing"}))[0].values())
assert len(mine) + len(miss) == len(allr) and all(r.has for r in mine) and all(not r.has and r.pattern for r in miss)
assert any(r.recipe.spell == lacking[0] for r in mine)
# every recipe shows, the ones you don't have greyed out; Hide unlearned hides them; right-click toggles a row
L.execute("MarketKingDB.profs = { [2] = true }"); KM.Refresh()
hide = [f for f in L.eval("FRAMES").values() if type(f.label) != type(None) and getattr(f.label, "text", None) == "Hide unlearned" and f.SetChecked][0]
assert not hide.GetChecked(hide) and L.eval("MarketKingDB.recipes") == "all"
greyed = [r for r in ns.table.rows.values() if r.data is not None and r.shown != False and not r.data.has]
assert greyed and all(r.alpha < 1 for r in greyed)
row_btn = greyed[0]; spell = row_btn.data.recipe.spell
click(row_btn, "RightButton"); assert ns.HasRecipe(spell) and row_btn.alpha == 1
click(hide); assert L.eval("MarketKingDB.recipes") == "mine" and hide.GetChecked(hide)
assert all(r.has for r in ns.CurrentRows()[0].values())
click(hide); assert L.eval("MarketKingDB.recipes") == "all"
assert any(not r.has for r in ns.CurrentRows()[0].values())
ns.SetHasRecipe(spell, False)
mk("recipes reset"); assert not ns.HasRecipe(spell) and ns.HasRecipe(3321)
mk("recipes mine"); assert L.eval("MarketKingDB.recipes") == "mine"
mk("recipes missing"); assert L.eval("MarketKingDB.recipes") == "all", "Patterns I lack is gone: all, greyed out"
mk("recipes bogus"); assert L.eval("MarketKingDB.recipes") == "all"
assert not KM.errorShown, last(L)
print("PATTERNS OK")

# /mk, the crown and Settings
mk("button"); assert "crown" in last(L), last(L)
mk("help"); assert any("/mk mode" in str(o) for o in outputs(L))
mk("mode"); assert L.eval("MarketKingDB.mode") == "farm" and "Use my mats" in last(L)
mk("mode"); assert L.eval("MarketKingDB.mode") == "buy" and "Buy mats" in last(L)
L.execute("SCAN_OPENED = 0; local real = ScannerKing.OpenMarketScan; ScannerKing.OpenMarketScan = function() SCAN_OPENED = SCAN_OPENED + 1 end")
mk("scan"); assert L.eval("SCAN_OPENED") == 1
KM.Show("crafting")
L.globals().PG = ns.Page()
click(L.eval("PBTN(PG, 'Scan')"))  # the page's own Scan button
assert L.eval("SCAN_OPENED") == 2
KM.Toggle(False)
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Crafting Profits") ~= nil')
L.execute('MENU_ITEM("Crafting Profits").fn()'); assert KM.IsShown("crafting")
KM.OpenSettings("market"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
t = fonts()
assert "Count materials as" in t and "Include disenchanting" in t and "Hide unlearned recipes" in t and any("/mk recipes" in str(x) for x in t)
farm_choice = [f for f in L.eval("FRAMES").values() if type(f.label) != type(None) and f.SetLabel and getattr(f.label, "text", None) == "Use my mats" and f.shown != False][-1]
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
assert not KM3.mods.Market.AllSelected(), "a saved pick is kept"
# 2.18.0: an empty pick becomes every profession, and "Patterns I lack" becomes all, greyed out
L5, KM5 = fresh(only=["Scanner", "Market"], extra=EXTRA, seed="MarketKingDB = { profs = {}, recipes = 'missing' }")
assert KM5.mods.Market.AllSelected() and L5.eval("MarketKingDB.recipes") == "all"
# Market without Scanner still loads and opens
L4, KM4 = fresh(only=["Market"], extra=EXTRA)
KM4.Show("crafting"); assert not KM4.errorShown, last(L4)
L4.eval("SlashCmdList.MARKETKING")("scan"); assert "Scanner" in last(L4)
print("INITDB OK")

# Windows taught us a recipe that the built-in data now has (2.4.0's Forever data): the saved copy goes at load;
# one that still differs stays
L3, KM3 = fresh(only=["Scanner", "Market"], extra=EXTRA, seed="""
MarketKingDB = { learned = { [2661] = { 2851, 2, 0, { 2840, 6 }, 1 }, [2662] = { 2852, 2, 0, { 2840, 9 }, 1 },
  [999002] = { 777002, 2, 0, { 2840, 1 }, 1 } } }""")
assert L3.eval("MarketKingDB.learned[2661]") is None and L3.eval("MarketKingDB.learned[2662]") is not None
assert L3.eval("MarketKingDB.learned[999002]") is not None
print("LEARNED CLEANUP OK")

# --- 2.9: profession skills live here now (Skill-ups is gone): read at login and on changes, moved in from its save,
# shown on the crown's tooltip ----------------------------------------------------------------------------------
L2, KM2 = fresh(only=["Scanner", "Market"], seed="""PROFS = { { name = "Tailoring", cur = 150, max = 225 }, { name = "Mining", cur = 80, max = 150 } }
SkillupKingDB = { chars = { ["Old Alt-Forever"] = { known = { [3321] = true }, skills = { [2] = { cur = 200, max = 225 } } } },
  vendor = { [2880] = 90 } }
MarketKingDB = { vendor = { [2880] = 100 } }""")
m2 = KM2.mods.Market
assert m2.Skill(8) == (150, 225) and m2.Skill(7) == (80, 150) and m2.Skill(4) == (0, 0)
assert L2.eval("SkillupKingDB") is None
assert L2.eval("MarketKingDB.chars['Old Alt-Forever'].skills[2].cur") == 200 and L2.eval("MarketKingDB.chars['Old Alt-Forever'].known[3321]") is True
assert L2.eval("MarketKingDB.vendor[2880]") == 100, "a price Market already had wins"
L2.execute('PROFS[1].cur = 151; FIRE("SKILL_LINES_CHANGED")')
assert m2.Skill(8) == (151, 225)
L2.execute('KingMakerMinimapButton:GetScript("OnEnter")(KingMakerMinimapButton)')
tip = [str(x) for x in L2.eval("GameTooltip.lines").values()]
assert any(x.startswith("Skills: ") and "Tailoring 151/225" in x and "Mining 80/150" in x for x in tip), tip
assert not KM2.errorShown, last(L2)
print("SKILLS OK")

print("market: ok")
