# Runs Market King (with Scanner King) against a stand-in for the game:
#   python3 tests/run.py . [path/to/Scanner_King]
import sys
from lupa import lua51
root = sys.argv[1]
sk_root = sys.argv[2] if len(sys.argv) > 2 else f"{root}/../scanner_king"
L = lua51.LuaRuntime()
L.execute(open(f"{root}/tests/mock.lua").read())
L.execute("C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }")
# item details the game would know: name, quality, item level, sell price, class (2 weapon, 4 armor, 7 trade goods)
L.execute("""
ITEMS = {
  [2840] = {"Copper Bar", 1, 10, 25, 7},  [2770] = {"Copper Ore", 1, 10, 5, 7},
  [2880] = {"Weak Flux", 1, 10, 25, 7},    [2589] = {"Linen Cloth", 1, 5, 13, 7},
  [2851] = {"Copper Chain Belt", 2, 18, 100, 4},  -- green armor, DEs
  [2852] = {"Copper Chain Pants", 1, 9, 50, 4},
  [10940] = {"Strange Dust", 1, 1, 0, 7}, [10939] = {"Greater Magic Essence", 1, 1, 0, 7}, [10978] = {"Small Glimmering Shard", 1, 1, 0, 7},
  [1251] = {"Linen Bandage", 1, 5, 10, 0},
}
C_Item.GetItemInfo = function(id) local i = ITEMS[id]; if i then return i[1], nil, i[2], i[3], 1, "", "", 20, "", 100 + id, i[4], i[5] end end
""")
skns = L.table()
# Scanner King's files, in the order its .toc loads them
for fn in [l.strip() for l in open(f"{sk_root}/Scanner_King.toc") if l.strip() and not l.startswith("#")]:
    L.execute(open(f"{sk_root}/{fn}").read(), "Scanner_King", skns)
ns = L.table()
for fn in ["Data/Recipes.lua", "Data/Patterns.lua", "Data/Disenchant.lua", "Data/Vendor.lua", "Core.lua", "Profit.lua", "Events.lua", "UI.lua"]:
    L.execute(open(f"{root}/{fn}").read(), "Market_King", ns)
L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("ADDON_LOADED", "Market_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
mk = L.eval("SlashCmdList.MARKETKING")
def last(): return L.eval("OUTPUT[#OUTPUT]")

# Data loaded
assert ns.RECIPES[2661][1] == 2851  # Copper Chain Belt
recipes = list(ns.Recipes().values()); assert len(recipes) > 1100
# disenchant table: green armor ilvl 18 -> mostly Strange Dust; a weapon swaps to mostly essence
de = ns.DisenchantResults(2, 18, 4); assert de[1][1] == 10940 and abs(de[1][2] - 0.75 * 2.5) < 1e-9
dw = ns.DisenchantResults(2, 18, 2); assert dw[1][1] == 10940 and abs(dw[1][2] - 0.20 * 2.5) < 1e-9 and abs(dw[2][2] - 0.75 * 1.5) < 1e-9
assert ns.DisenchantResults(1, 18, 4) is None and ns.DisenchantResults(2, 18, 7) is None
print("DATA OK")

# Pick Blacksmithing and First Aid, scan at the auction house
L.execute("""
AH_PRICES = { [2840] = 100, [2770] = 40, [2589] = 20, [2851] = 2000, [2852] = 300, [1251] = 30,
              [10940] = 150, [10939] = 600, [10978] = 800 }
""")
items = list(ns.ItemsToScan(L.eval("{ [2] = true, [1] = true }")).values())
assert 2851 in items and 2840 in items and 10940 in items and 2880 not in items  # crafted, reagent, DE mat; flux is a vendor item
# Scanner King's title bar has Material Scan and Market Scan; Market Scan offers our professions
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
def frame_with(text):
    return L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' then return f end end end)()" % text)
ms = frame_with("Market Scan"); assert ms and ms.shown and frame_with("Material Scan")
ms.scripts.OnClick(ms)  # opens with every profession ticked
checks = [f for f in L.eval("FRAMES").values() if f.key is not None and f.checked is not None]
assert len(checks) == 9 and all(c.checked for c in checks)
none = frame_with("None"); none.scripts.OnClick(none)
assert not any(c.checked for c in checks)
# tick Blacksmithing and First Aid only, then Scan
for c, name in zip(checks, [p.name for p in ns.PROFESSIONS.values()]):
    if name in ("Blacksmithing", "First Aid"): c.SetChecked(c, True)
L.execute("SCANNED = nil; local real = ScannerKing.Scan; ScannerKing.Scan = function(o) SCANNED = o and #o.items; return real(o) end")
scan = [f for f in L.eval("FRAMES").values() if f.text == "Scan"][-1]
scan.scripts.OnClick(scan)
L.execute("RUN_TIMERS()"); print(last())
assert L.eval("SCANNED") == len(items)
assert L.eval("ScannerKingDB.prices[2851].p") == 2000
# Market King opened on exactly what was scanned
assert L.eval("MarketKingDB.profs[2]") and L.eval("MarketKingDB.profs[1]") and not L.eval("MarketKingDB.profs[9]")

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
# the window draws it
fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
fr_ = L.eval("FRAMES"); texts += [fr_[i].text for i in range(1, len(fr_) + 1) if fr_[i].text]
assert "Best" in texts and "Blacksmithing" in texts and "First Aid" in texts and "Profit" in texts, texts[:40]
assert any("above the red line" in t for t in texts)
assert any("Copper Chain Belt" in t for t in texts)
mk("mode farm"); fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "Raw value" in texts and "Gain vs raw" in texts
# vendor prices seen at a merchant replace the estimate
L.execute("""
GetMerchantNumItems = function() return 1 end
GetMerchantItemID = function() return 2880 end
GetMerchantItemInfo = function() return "Weak Flux", 0, 95, 1, -1, true, true, nil end
FIRE("MERCHANT_SHOW")
""")
assert L.eval("MarketKingDB.vendor[2880]") == 95
# Listed counts come through from Scanner King
assert row.listed is None or row.listed >= 0
L.execute("ScannerKingDB.prices[2851].q = 7")
assert ns.Evaluate(belt, "buy").listed == 7
mk("mode buy"); fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "Listed" in texts and "7" in texts
L.execute("MarketKingDB.includeDE = false"); mk(""); mk("")
fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "Craft sells" in texts
de_btn = L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'DE only' then return f end end end)()")
de_btn.scripts.OnClick(de_btn); assert L.eval("MarketKingDB.deOnly") == True
fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "DE sells" in texts
de_btn.scripts.OnClick(de_btn); L.execute("MarketKingDB.includeDE = true")
# with every profession ticked the tabs switch to short names so they fit
L.execute("for _, p in ipairs({1,2,3,4,6,7,8,9,10}) do MarketKingDB.profs[p] = true end")
mk(""); mk("")
fr_ = L.eval("FRAMES"); labels = [fr_[i].text for i in range(1, len(fr_) + 1) if fr_[i].text]
assert "Leather" in labels and "Tailor" in labels, labels
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
print(last())

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
assert ns.HasRecipe(3321) and "pattern recipe" in last(), last()
assert ns.HasRecipe(3325)                                         # Gemmed Copper Gauntlets (Plans), matched by item
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
# the button cycles the view; right-clicking a row toggles it
btn = frame_with("All recipes"); btn.scripts.OnClick(btn); assert L.eval("MarketKingDB.recipes") == "mine"
btn.scripts.OnClick(btn); assert L.eval("MarketKingDB.recipes") == "missing"
row_btn = [f for f in L.eval("FRAMES").values() if f.row is not None and f.shown][0]
spell = row_btn.row.recipe.spell; assert not ns.HasRecipe(spell)
row_btn.scripts.OnClick(row_btn, "RightButton"); assert ns.HasRecipe(spell)
btn.scripts.OnClick(btn); assert L.eval("MarketKingDB.recipes") == "all"
mk("recipes reset"); assert not ns.HasRecipe(spell) and ns.HasRecipe(3321)
print("PATTERNS OK")
print("ALL TESTS PASSED")
