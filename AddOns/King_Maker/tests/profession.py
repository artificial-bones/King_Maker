# Profession: the King Maker panel docked to the game's profession window. Both window paths are faked here: the
# modern ProfessionsFrame (CraftingPage.SchematicForm + the EventRegistry recipe callback, C_TradeSkillUI) and the
# classic TradeSkillFrame / CraftFrame (GetTradeSkill* / GetCraft* + the selection hooks).
# Checked: panel shows and hides with the window, This recipe (cost, owned, profit after the cut, headline profit,
# margin and verdict for the mode, the other mode's verdict), the Buy mats / Use my mats switch (following Crafting
# Profits and fixed), All crafts (rows sorted by Profit now, Can make from the game and from bags, the Can make now
# and search filters, sortable headers, price-age footer), Profit & Loss lines with a stubbed ProfitKing and without,
# add-to-Shopping (present and absent), tooltips, settings, /km profession, InitDB twice, no Skillup module needed,
# and that nothing ever crafts.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

MODS = ["Scanner", "Econ", "Market", "Inventory", "Profession"]

ITEMS = """
ITEM(2840, "Copper Bar", { quality = 1, ilvl = 10, sell = 25, class = 7 })
ITEM(2880, "Weak Flux", { quality = 1, ilvl = 10, sell = 25, class = 7 })
ITEM(2589, "Linen Cloth", { quality = 1, ilvl = 5, sell = 13, class = 7 })
ITEM(2851, "Copper Chain Belt", { quality = 2, ilvl = 18, sell = 100, class = 4 })
ITEM(2852, "Copper Chain Pants", { quality = 1, ilvl = 9, sell = 50, class = 4 })
ITEM(2844, "Copper Mace", { quality = 1, ilvl = 11, sell = 80, class = 2 })
ITEM(10940, "Strange Dust", { quality = 1, ilvl = 1, sell = 0, class = 7 })
ITEM(10939, "Greater Magic Essence", { quality = 1, ilvl = 1, sell = 0, class = 7 })
ITEM(10978, "Small Glimmering Shard", { quality = 1, ilvl = 1, sell = 0, class = 7 })
ITEM(99001, "Forever Bracer", { quality = 1, ilvl = 12, sell = 40, class = 4 })
BAGS[0][1] = { id = 2840, count = 4 }
BAGS[0][2] = { id = 2589, count = 5 }
-- nothing may ever craft
CRAFTED = {}
DoTradeSkill = function() CRAFTED[#CRAFTED + 1] = "DoTradeSkill" end
DoCraft = function() CRAFTED[#CRAFTED + 1] = "DoCraft" end
function BTN(text, inside)
  for _, f in ipairs(FRAMES) do
    if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then
      if not inside then return f end
      local p = f.parent
      while p and p ~= inside do p = p.parent end
      if p then return f end
    end
  end
end
-- the card's money line with this label, if it's showing: its value text
function LINE(label)
  for _, l in ipairs(KingMakerTest_ns.ui.card.lines) do
    if l.l.text == label and l.l.shown ~= false then return l.v.text end
  end
end
"""

SEED = """
ScannerKingDB = { prices = {
  [2840] = { p = 100, t = 900, q = 50 }, [2589] = { p = 20, t = 900, q = 80 },
  [2851] = { p = 2000, t = 900, q = 7, m = 2200 }, [2852] = { p = 300, t = 900, q = 3 }, [2844] = { p = 900, t = 900, q = 2 },
  [10940] = { p = 150, t = 900 }, [10939] = { p = 600, t = 900 }, [10978] = { p = 800, t = 900 }, [99001] = { p = 700, t = 900 } } }
"""

# The modern window: Blizzard_Professions loads on demand and makes ProfessionsFrame.
MODERN = """
SELECTED = nil
TRADESKILL = { name = "Blacksmithing", id = 164, recipes = {
  [2661] = { output = 2851, reagents = { { 2840, 6 } } },
  [2737] = { output = 2844, reagents = { { 2840, 6 }, { 2880, 1 }, { 2589, 2 } } },
  [999001] = { output = 99001, reagents = { { 2840, 2 } }, name = "Forever Bracer" },
} }
local base = C_TradeSkillUI.GetBaseProfessionInfo
C_TradeSkillUI.GetBaseProfessionInfo = function() local i = base(); if i then i.skillLevel, i.maxSkillLevel = 60, 150 end return i end
local info = C_TradeSkillUI.GetRecipeInfo
-- numAvailable: how many the bags cover, as the game counts it (only when a test sets .avail)
C_TradeSkillUI.GetRecipeInfo = function(id) local i = info(id); if i then i.numAvailable = TRADESKILL.recipes[id].avail end return i end
C_TradeSkillUI.OpenRecipe = function(id) OPENED = id; SELECTED = id end
C_TradeSkillUI.CraftRecipe = function() CRAFTED[#CRAFTED + 1] = "CraftRecipe" end
EventRegistry = { cbs = {} }
function EventRegistry:RegisterCallback(event, fn, owner) self.cbs[event] = self.cbs[event] or {}; table.insert(self.cbs[event], { fn, owner }) end
function EventRegistry:TriggerEvent(event, ...) for _, c in ipairs(self.cbs[event] or {}) do c[1](c[2], ...) end end
function LOAD_PROFESSIONS()
  ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame", UIParent)
  ProfessionsFrame:SetSize(940, 560)
  ProfessionsFrame:Hide()
  ProfessionsFrame.CraftingPage = CreateFrame("Frame", nil, ProfessionsFrame)
  local form = CreateFrame("Frame", nil, ProfessionsFrame.CraftingPage)
  form.GetRecipeInfo = function(self) return SELECTED and { recipeID = SELECTED } or nil end
  ProfessionsFrame.CraftingPage.SchematicForm = form
  RECIPE_ROW = CreateFrame("Button", nil, form)
  LOADED_ADDONS["Blizzard_Professions"] = true
  FIRE("ADDON_LOADED", "Blizzard_Professions")
end
function SELECT(id)  -- the game's recipe list picks a recipe
  SELECTED = id
  EventRegistry:TriggerEvent("ProfessionsRecipeListMixin.Event.OnRecipeSelected", { recipeID = id }, {})
end
"""

L, KM = fresh(only=MODS, seed=SEED, extra=ITEMS + MODERN)
ns = KM.mods.Profession
L.globals().KingMakerTest_ns = ns
assert not KM.errorShown, last(L)
assert KM.mods.Skillup is None and L.eval("SkillupKing") is None, "runs without the Skillup module"
assert L.eval("ProfessionKingDB.show") is True and L.eval("ProfessionKingDB.side") == "right"
assert L.eval("ProfessionKingDB.mode") == "market" and L.eval("ProfessionKingDB.tooltip") is True
assert L.eval("ProfessionKingDB.tab") == "card" and L.eval("ProfessionKingDB.canMake") is False and L.eval("ProfessionKingDB.search") == ""
assert L.eval("KingMakerProfessionPanel") is None, "nothing built before a profession window opens"

# Econ history for the belt: two scans a day apart -> 30-day average, history points
econ = KM.mods.Econ
econ.Record(L.eval("{ [2851] = { p = 1800, q = 9, m = 1900, n = 4 } }"), "deep", "replicate")
L.execute("NOW = 1000 + 86400")
econ.Record(L.eval("{ [2851] = { p = 2000, q = 7, m = 2200, n = 3 } }"), "deep", "replicate")
L.execute("NOW = 1000 + 86400 + 60")

# --- modern window -----------------------------------------------------------------------------------------
L.execute("LOAD_PROFESSIONS()")
assert ns.hooked.modern and ns.hooked.registry, "hooked ProfessionsFrame and the recipe callback on ADDON_LOADED"
L.execute("ProfessionsFrame:Show()")
assert L.eval("KingMakerProfessionPanel:IsShown()"), "panel appears with the window"
pt = L.eval("KingMakerProfessionPanel.point")
assert pt[1] == "TOPLEFT" and L.eval("KingMakerProfessionPanel.point[2] == ProfessionsFrame") and pt[3] == "TOPRIGHT", "docked on the right"
assert L.eval("KingMakerProfessionPanel:GetParent() == UIParent"), "our frame, not a child of Blizzard's"
assert L.eval("KingMakerProfessionPanel:GetWidth()") <= 460
assert ns.card is None and any("Pick a recipe" in (t or "") for t in L.eval("TEXTS()").values())

L.execute("SELECT(2661)")
c = ns.card
assert c is not None and c.spell == 2661 and c.item == 2851, c
assert c.cost == 600 and c.costAll == 600, c.cost                   # 6 Copper Bar x 1s
m1 = c.mats[1]
assert m1.id == 2840 and m1.need == 6 and m1.have == 4 and m1.unit == 100 and m1.line == 600
assert c.skill == 60 and c.maxSkill == 150, (c.skill, c.maxSkill)
assert c.market == 2200 and c.lowest == 2000 and c.listed == 7
assert abs(c.profit - (2000 * 0.95 - 600)) < 1e-6, c.profit          # after the 5% cut, Market's rule (lowest)
assert abs(c.sale - 2000 * 0.95) < 1e-6
assert c.de and c.de > 0 and c.deSale < c.de                         # green armor disenchants
assert c.verdict.buy == "craft" and c.verdict.farm == "craft", (c.verdict.buy, c.verdict.farm)
assert c.avg30 is not None and len(list(c.history.values())) == 2
assert abs(c.farm.gain - (2000 * 0.95 - 6 * 100 * 0.95)) < 1e-6
# the headline: Buy mats profit, its margin over the materials, one verdict
assert c.mode == "buy" and abs(c.head - 1300) < 1e-6 and abs(c.margin - 1300 / 600) < 1e-9, (c.mode, c.head, c.margin)
assert c.make == 2, c.make                                           # a quarter of 7 listed
ui = ns.ui
assert "+" in ui.card.profit.text and KM.Money(1300) in ui.card.profit.text, ui.card.profit.text
assert ui.card.pill.text.text == "CRAFT" and ui.card.pill.shown is not False
assert "+217%" in ui.card.margin.text, ui.card.margin.text
assert "Use my mats" in ui.card.other.text and "CRAFT" in ui.card.other.text, ui.card.other.text
assert L.eval("LINE('Materials')") is not None and L.eval("LINE('Make')").startswith("2"), L.eval("LINE('Make')")
assert L.eval("LINE('Sells for, after the 5% cut')") is not None
texts = list(L.eval("TEXTS()").values())
assert any("Copper Chain Belt" in (t or "") for t in texts)
assert not any("Skill-up" in (t or "") or "BOUGHT" in (t or "") or "FARMED" in (t or "") for t in texts), "no skill-up line, no dual pills"
# no Profit & Loss: its lines stay hidden
assert c.paid is None and c.sales is None and L.eval("LINE('At what you paid')") is None and L.eval("LINE('Your last sales')") is None

# a recipe with a vendor reagent, picked through the polled SchematicForm only (no callback)
L.execute("SELECTED = 2737")
L.execute("ADVANCE(1)")
c = ns.card
assert c.spell == 2737, c.spell
flux = [m for m in c.mats.values() if m.id == 2880][0]
assert flux.vendor and flux.unit == 100, (flux.vendor, flux.unit)    # vendor: 4x its sell price until seen at a merchant
assert c.cost == 6 * 100 + 100 + 2 * 20
L.execute("SELECT(2661)")

# --- the Buy mats / Use my mats switch ---
buyB, farmB = L.eval("BTN('Buy mats', KingMakerProfessionPanel)"), L.eval("BTN('Use my mats', KingMakerProfessionPanel)")
assert buyB is not None and farmB is not None and buyB.active and not farmB.active
# following Crafting Profits (the default): the switch flips Crafting Profits' mode too
farmB.RunScript(farmB, "OnClick", "LeftButton")
assert L.eval("MarketKingDB.mode") == "farm" and L.eval("ProfessionKingDB.mode") == "market" and ns.Mode() == "farm"
c = ns.card
assert c.mode == "farm" and abs(c.head - c.farm.gain) < 1e-6 and farmB.active, c.mode
assert abs(c.margin - c.farm.gain / (c.farm.raw + c.farm.vendorCost)) < 1e-9
assert "Buy mats" in ui.card.other.text
buyB.RunScript(buyB, "OnClick", "LeftButton")
assert L.eval("MarketKingDB.mode") == "buy" and ns.card.mode == "buy"
# a fixed panel mode: only the panel's changes
L.execute("ProfessionKingDB.mode = 'buy'")
farmB.RunScript(farmB, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.mode") == "farm" and L.eval("MarketKingDB.mode") == "buy" and ns.Mode() == "farm"
buyB.RunScript(buyB, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.mode") == "buy"
L.execute("ProfessionKingDB.mode = 'market'")
# Market's own labels win when it has them
KM.mods.Market.MODE_LABELS = L.eval("{ buy = 'Flip mats', farm = 'Mine' }")
assert ns.ModeLabel("buy") == "Flip mats" and ns.ModeLabel("farm") == "Mine"
KM.mods.Market.MODE_LABELS = None
assert ns.ModeLabel("buy") == "Buy mats" and ns.ModeLabel("farm") == "Use my mats"

# --- Profit & Loss: at what you paid, your last sales ---
L.execute("""
PL_CALLS = {}
ProfitKing = {
  IsTracking = function() return true end,
  Basis = function(id) PL_CALLS[#PL_CALLS + 1] = id; if id == 2840 then return { held = 4, cost = 200, avg = 50 } end end,
  Trades = function(since)
    SINCE = since
    return { { t = NOW - 3600, item = 2851, q = 2, proceeds = 3800 }, { t = NOW - 7200, item = 2851, q = 1, proceeds = 1700 },
             { t = NOW - 3600, item = 2844, q = 1, proceeds = 5 }, { t = NOW - 9 * 86400, item = 2851, q = 9, proceeds = 9 } }
  end,
}
""")
ns.tradesAt = None
ns.Refresh()
c = ns.card
assert c.paid is not None and c.paid.covered == 4 and c.paid.units == 6, c.paid
assert abs(c.paid.profit - (1900 - (4 * 50 + 2 * 100))) < 1e-6, c.paid.profit   # 4 held at 50c, 2 more at 1s
assert c.sales.q == 3 and c.sales.sales == 2 and abs(c.sales.each - 5500 / 3) < 1e-6, (c.sales.q, c.sales.each)
assert L.eval("SINCE") == L.eval("NOW") - 7 * 86400
assert "4 of 6" in L.eval("LINE('At what you paid')") and "3 sold" in L.eval("LINE('Your last sales')")
# a broken P&L call hides its line, never the card
L.execute("ProfitKing.Basis = function() error('boom') end; ProfitKing.Trades = function() error('boom') end")
ns.tradesAt = None
ns.Refresh()
assert not KM.errorShown, last(L)
assert ns.card.paid is None and L.eval("LINE('At what you paid')") is None and "none" in L.eval("LINE('Your last sales')")
L.execute("ProfitKing.IsTracking = function() return false end")
ns.Refresh()
assert ns.card.paid is None and ns.card.sales is None and L.eval("LINE('Your last sales')") is None, "not tracking: hidden"
L.execute("ProfitKing = nil")
ns.Refresh()
assert ns.card.paid is None and not KM.errorShown

# more crafts multiply what you need
plus = L.eval("BTN('+', KingMakerProfessionPanel)")
plus.RunScript(plus, "OnClick", "LeftButton")
c = ns.card
assert c.crafts == 2 and c.mats[1].need == 12 and c.costAll == 1200 and c.cost == 600

# Shopping absent: the button is hidden
shop = L.eval("BTN('Add missing to Shopping', KingMakerProfessionPanel)")
assert shop is not None and shop.shown is False, "hidden without ShoppingKing"
# Shopping present: shown, and it calls ShoppingKing.Add for the shortfall (12 needed, 4 owned)
L.execute("SHOP = {}; ShoppingKing = { Add = function(id, n, max, list) table.insert(SHOP, { id = id, n = n, max = max, list = list }) return true end }")
ns.Refresh()
assert shop.shown is True
shop.RunScript(shop, "OnClick", "LeftButton")
assert L.eval("#SHOP") == 1, L.eval("#SHOP")
assert L.eval("SHOP[1].id") == 2840 and L.eval("SHOP[1].n") == 8 and L.eval("SHOP[1].max") == 100 and L.eval("SHOP[1].list") == "Crafting"
assert "Shopping list" in last(L), last(L)
# a failing Add does not break the panel
L.execute("ShoppingKing.Add = function() error('boom') end")
shop.RunScript(shop, "OnClick", "LeftButton")
assert not KM.errorShown, last(L)
L.execute("ShoppingKing = nil")
ns.SetCrafts(1)

# favorite star and Price History
fav = L.eval("(function() for _, f in ipairs(FRAMES) do if rawget(f, 'icon') and f.icon.texture == 'Interface\\\\TargetingFrame\\\\UI-RaidTargetingIcon_1' and f.SetActive then return f end end end)()")
assert fav is not None and fav.shown is not False
fav.RunScript(fav, "OnClick", "LeftButton")
assert L.eval("EconKing.IsFavorite(2851)") is True
fav.RunScript(fav, "OnClick", "LeftButton")
assert L.eval("EconKing.IsFavorite(2851)") is False
hist = L.eval("BTN('History', KingMakerProfessionPanel)")
hist.RunScript(hist, "OnClick", "LeftButton")
assert KM.CurrentPage() == "history" and not KM.errorShown, (KM.CurrentPage(), last(L))
KM.Toggle(False)

# a Forever-only recipe the data doesn't know: the window's own reagents
L.execute("SELECT(999001)")
c = ns.card
assert c.item == 99001 and c.cost == 200, c.cost
assert abs(c.profit - (700 * 0.95 - 200)) < 1e-6
L.execute("SELECT(2661)")

def ours(lines):   # our lines (the Scanner, Econ and Inventory add their own item lines too)
    return [l for l in lines.values() if "King Maker|r cost" in l or "Skill-up" in l]


# tooltips: hovering a recipe's item inside the window adds a King Maker line; elsewhere nothing
L.execute("GameTooltip:SetOwner(RECIPE_ROW, 'ANCHOR_RIGHT')")
_, lines = L.eval("HOVER(2851)")
lines = ours(lines)
assert len(lines) == 1, lines
assert "profit" in lines[0] and "craft" in lines[0], lines
L.execute("GameTooltip:SetOwner(UIParent, 'ANCHOR_RIGHT')")
_, lines = L.eval("HOVER(2851)")
assert len(ours(lines)) == 0, "not inside the profession window"
L.execute("GameTooltip:SetOwner(RECIPE_ROW, 'ANCHOR_RIGHT')")
_, lines = L.eval("HOVER(2840)")
assert len(ours(lines)) == 0, "a reagent is not a recipe of this profession"
L.execute("GameTooltip.lines = {}; for _, fn in ipairs(TOOLTIP_CALLS[1] or {}) do fn(GameTooltip, { id = 2661, type = 1 }) end")
assert len(ours(L.eval("GameTooltip.lines"))) == 1, "spell tooltips too"
L.execute("ProfessionKingDB.tooltip = false")
_, lines = L.eval("HOVER(2851)")
assert len(ours(lines)) == 0, "setting off"
L.execute("ProfessionKingDB.tooltip = true")

# --- All crafts ---
L.execute("TRADESKILL.recipes[2661].avail = 3")      # the game says the bags cover 3 belts
allB = L.eval("BTN('All crafts', KingMakerProfessionPanel)")
allB.RunScript(allB, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.tab") == "all" and not KM.errorShown, last(L)
rows = list(ns.AllCrafts(2).values())
spells = [r.spell for r in rows]
assert 2661 in spells and 2737 in spells and 2662 not in spells, spells   # the window's list: what you know
nows = [r.now for r in rows if r.now is not None]
assert len(nows) >= 2 and nows == sorted(nows, reverse=True), nows
belt = rows[0]
assert belt.item == 2851 and belt.verdict == "craft" and belt.listed == 7 and belt.make == 2, (belt.item, belt.make)
assert abs(belt.now - belt.gain * 2) < 1e-6 and abs(belt.margin - 1300 / 600) < 1e-9
assert belt.can == 3, belt.can                                        # the game's numAvailable
mace = [r for r in rows if r.spell == 2737][0]
assert mace.can == 0, mace.can                                        # no count from the game: 4 bars / 6 = 0
assert abs(mace.now - mace.gain * mace.make) < 1e-6
# the table shows them, Profit now first, and every header sorts
tbl = ui.all.tbl
assert tbl.data[1].item == 2851 and L.eval("ProfessionKingDB.sortKey") == "now" and tbl.sortDesc is True
tbl.headers.gain.RunScript(tbl.headers.gain, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.sortKey") == "gain"
tbl.headers.name.RunScript(tbl.headers.name, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.sortKey") == "name" and L.eval("ProfessionKingDB.sortDesc") is False
names = [r.name for r in tbl.data.values()]
assert names == sorted(names, key=str.lower), names
tbl.headers.now.RunScript(tbl.headers.now, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.sortKey") == "now" and tbl.data[1].item == 2851
# Can make now
cb = ui.all.canMake
cb.RunScript(cb, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.canMake") is True
shown = [r.spell for r in ui.all.rows.values()]
assert shown == [2661], shown
cb.RunScript(cb, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.canMake") is False and len(list(ui.all.rows.values())) == len(rows)
# search
box = ui.all.search
box.SetText(box, "mace"); box.RunScript(box, "OnTextChanged", True)
assert L.eval("ProfessionKingDB.search") == "mace"
assert [r.spell for r in ui.all.rows.values()] == [2737]
box.SetText(box, "nothing like it"); box.RunScript(box, "OnTextChanged", True)
assert len(list(ui.all.rows.values())) == 0 and tbl.emptyText == "No recipe matches."
box.SetText(box, ""); box.RunScript(box, "OnTextChanged", True)
assert len(list(ui.all.rows.values())) == len(rows)
# the footer: how old the prices are, and a nudge when they're stale
assert "No price scan yet" in ui.all.foot.text and "Scan at the auction house" in ui.all.foot.text, ui.all.foot.text
L.execute("ScannerKingDB.lastDeep = NOW - 3600")
ns.Refresh()
assert "Prices from 1 h ago" in ui.all.foot.text and "Scan at the auction house" not in ui.all.foot.text, ui.all.foot.text
L.execute("ScannerKingDB.lastDeep = NOW - 13 * 3600")
ns.Refresh()
assert "Scan at the auction house" in ui.all.foot.text
# Use my mats ranks by the gain over selling raw
L.execute("MarketKingDB.mode = 'farm'")
ns.Refresh()
assert all(r.mode == "farm" for r in ui.all.rows.values()) and "Use my mats" in ui.all.foot.text
L.execute("MarketKingDB.mode = 'buy'")
# Batch: no more than a day's worth; nothing listed: make one to test
L.execute("EconKing = EconKing or {}; OLD_STATS = EconKing.GetStats; EconKing.GetStats = function(id) if id == 2851 then return { gonePerDay = 1.4 } end end")
assert tuple(ns.Batch(2851))[:2] == (7, 1), "no more than a day's worth"
L.execute("ScannerKingDB.prices[2851].q = 0")
assert tuple(ns.Batch(2851))[:2] == (0, 1), "nothing listed: make one to test"
L.execute("ScannerKingDB.prices[2851].q = 7; EconKing.GetStats = OLD_STATS")
assert ns.Batch(10940) is None, "never scanned for quantity"
# your skill: the window's, else Market's for this character when it has one
assert ns.SkillFor(None, 2) is None
KM.mods.Market.Skill = L.eval("function() return 77, 150 end")
assert tuple(ns.SkillFor(None, 2)) == (77, 150)
KM.mods.Market.Skill = L.eval("function() error('boom') end")
assert ns.SkillFor(None, 2) is None
KM.mods.Market.Skill = None
assert not KM.errorShown, last(L)
# clicking an All crafts row shows its card, selecting it in the window through C_TradeSkillUI.OpenRecipe
L.execute("SELECTED = 2737; SELECT(2737)")
ns.Refresh()
row1 = L.eval("(function() return KingMakerTest_ns.ui.all.tbl.rows[1] end)()")
row1.RunScript(row1, "OnClick", "LeftButton")
assert L.eval("OPENED") == 2661 and L.eval("ProfessionKingDB.tab") == "card"
L.execute("ADVANCE(1)")
assert ns.card.spell == 2661
# a pinned recipe the window can't select stays on the card until the window's selection changes
ns.Pin(2662)
assert ns.card.spell == 2662 and ns.card.source == "data"
L.execute("ADVANCE(1)")
assert ns.card.spell == 2662 and "All crafts" in ui.card.sub.text
L.execute("SELECT(2737)")
L.execute("ADVANCE(1)")
assert ns.card.spell == 2737, "the window's new selection wins"

# collapse keeps it small, with the one-line summary
col = L.eval("BTN('-', KingMakerProfessionPanel)")
col.RunScript(col, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.collapsed") is True and L.eval("KingMakerProfessionPanel:GetHeight()") == 30
assert "Copper Mace" in L.eval("(function() for _, t in ipairs(FONTS) do if t.text and t.text:find('Copper Mace') and t.shown ~= false and t.parent == KingMakerProfessionPanel then return t.text end end end)()")
col.RunScript(col, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.collapsed") is False and L.eval("KingMakerProfessionPanel:GetHeight()") >= 420

# side setting
L.execute("ProfessionKingDB.side = 'left'")
ns.Place()
pt = L.eval("KingMakerProfessionPanel.points[#KingMakerProfessionPanel.points]")
assert pt[1] == "TOPRIGHT" and pt[3] == "TOPLEFT", pt
L.execute("ProfessionKingDB.side = 'right'")
# Things hanging off the window's right edge (its side tabs, the help button) push the panel past them
L.execute("""
local f = ProfessionsFrame
f.GetLeft, f.GetRight, f.GetTop, f.GetBottom = function() return 100 end, function() return 800 end, function() return 700 end, function() return 100 end
TAB = CreateFrame("Button", nil, f)
TAB.GetLeft, TAB.GetRight, TAB.GetTop, TAB.GetBottom = function() return 798 end, function() return 862 end, function() return 650 end, function() return 590 end
""")
assert ns.Overhang(L.eval("ProfessionsFrame"), "right") == 62
ns.Place()
pt = L.eval("KingMakerProfessionPanel.points[#KingMakerProfessionPanel.points]")
assert pt[1] == "TOPLEFT" and pt[3] == "TOPRIGHT" and pt[4] == 66, list(pt.values())
# a frame the game won't let addons read (forbidden) must not stop the panel from showing
L.execute("""
BAD = CreateFrame("Frame", nil, UIParent)
for _, m in ipairs({ "IsShown", "GetLeft", "GetRight", "GetTop", "GetBottom", "GetChildren" }) do
  BAD[m] = function() error("attempt to access forbidden object") end
end
""")
L.execute("ProfessionsFrame:Hide(); ProfessionsFrame:Show()")
assert L.eval("KingMakerProfessionPanel:IsShown()") and not KM.errorShown, last(L)
assert ns.Overhang(L.eval("ProfessionsFrame"), "right") == 62
L.execute("BAD:SetParent(nil)")
L.execute("TAB:Hide()"); ns.Place()
assert L.eval("KingMakerProfessionPanel.points[#KingMakerProfessionPanel.points][4]") == 4, "hidden tabs don't count"

# hides with the window
L.execute("ProfessionsFrame:Hide()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is False, "panel hides with the window"
# show off: the window opens alone
L.execute("ProfessionKingDB.show = false; ProfessionsFrame:Show()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is False
L.execute("ProfessionsFrame:Hide(); ProfessionKingDB.show = true; ProfessionsFrame:Show()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is True
L.execute("ProfessionsFrame:Hide()")

# settings section, /km profession
KM.OpenSettings("profession")
assert KM.CurrentPage() == "settings" and not KM.errorShown, last(L)
texts = list(L.eval("TEXTS()").values())
assert any("Show the King Maker panel" in (t or "") for t in texts)
assert any("Use my mats" in (t or "") for t in texts) and not any(t in ("Bought", "Farmed") for t in texts)
KM.Toggle(False)
L.eval("SlashCmdList.KINGMAKER")("profession")
assert KM.CurrentPage() == "settings"
L.eval("SlashCmdList.KINGMAKER")("")          # everything else still goes to /km
assert not L.eval("KingMakerFrame:IsShown()")

# InitDB twice keeps the same table and settings, and /km is wrapped once; the old Best now tab moves to All crafts
L.execute("ProfessionKingDB.side = 'left'; ProfessionKingDB.mode = 'farm'; ProfessionKingDB.tab = 'best'; ProfessionKingDB.canMake = true; HELD = ProfessionKingDB")
L.execute("WRAPPED = SlashCmdList.KINGMAKER")
ns.InitDB(); ns.InitDB()
assert L.eval("ProfessionKingDB == HELD") and L.eval("ProfessionKingDB.side") == "left" and L.eval("ProfessionKingDB.mode") == "farm"
assert L.eval("ProfessionKingDB.tab") == "all" and L.eval("ProfessionKingDB.canMake") is True
assert L.eval("SlashCmdList.KINGMAKER == WRAPPED")
assert ns.Mode() == "farm"
L.execute("ProfessionKingDB.mode = 'market'; MarketKingDB.mode = 'farm'")
assert ns.Mode() == "farm", "follows Crafting Profits"
L.execute("MarketKingDB.mode = 'buy'")

assert L.eval("#CRAFTED") == 0, "never crafts"
assert not KM.errorShown, last(L)
print("profession modern: ok")

# --- classic windows ---------------------------------------------------------------------------------------
CLASSIC = """
C_TradeSkillUI = nil
TS = {
  { "Blacksmithing", "header" },
  { "Copper Chain Belt", "easy", item = 2851, reagents = { { 2840, 6, 3 } }, avail = 5 },
  { "Copper Chain Pants", "trivial", item = 2852, reagents = { { 2840, 4, 3 } } },
}
TS_SEL = 0
GetTradeSkillLine = function() return "Blacksmithing", 95, 150 end
GetNumTradeSkills = function() return #TS end
GetTradeSkillInfo = function(i) local t = TS[i]; if t then return t[1], t[2], t.avail or 0, true end end
GetTradeSkillSelectionIndex = function() return TS_SEL end
GetTradeSkillItemLink = function(i) return TS[i] and TS[i].item and LINK(TS[i].item) end
GetTradeSkillRecipeLink = function(i) return nil end
GetTradeSkillIcon = function(i) return 1234 end
GetTradeSkillNumMade = function(i) return 1, 1 end
GetTradeSkillNumReagents = function(i) return TS[i] and TS[i].reagents and #TS[i].reagents or 0 end
GetTradeSkillReagentInfo = function(i, j) local r = TS[i].reagents[j]; return ITEMS[r[1]].name, 1, r[2], r[3] end
GetTradeSkillReagentItemLink = function(i, j) return LINK(TS[i].reagents[j][1]) end
function LOAD_TRADESKILL()
  TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame", UIParent)
  TradeSkillFrame:SetSize(384, 512)
  TradeSkillFrame:Hide()
  TS_ICON = CreateFrame("Button", "TradeSkillSkillIcon", TradeSkillFrame)
  TradeSkillFrame_SetSelection = function(i) TS_SEL = i end
  LOADED_ADDONS["Blizzard_TradeSkillUI"] = true
  FIRE("ADDON_LOADED", "Blizzard_TradeSkillUI")
end
CR = { { "Enchant Bracer - Minor Health", "", "optimal", link = "|Henchant:7418|h[Enchant Bracer - Minor Health]|h", reagents = { { 10940, 1, 0 } } } }
CR_SEL = 0
GetCraftDisplaySkillLine = function() return "Enchanting", 21, 150 end
GetNumCrafts = function() return #CR end
GetCraftInfo = function(i) local t = CR[i]; if t then return t[1], t[2], t[3], 0 end end
GetCraftSelectionIndex = function() return CR_SEL end
GetCraftItemLink = function(i) return CR[i] and CR[i].link end
GetCraftRecipeLink = function(i) return CR[i] and CR[i].link end
GetCraftIcon = function(i) return 4321 end
GetCraftNumReagents = function(i) return CR[i] and #CR[i].reagents or 0 end
GetCraftReagentInfo = function(i, j) local r = CR[i].reagents[j]; return ITEMS[r[1]].name, 1, r[2], r[3] end
GetCraftReagentItemLink = function(i, j) return LINK(CR[i].reagents[j][1]) end
function LOAD_CRAFT()
  CraftFrame = CreateFrame("Frame", "CraftFrame", UIParent)
  CraftFrame:Hide()
  CraftFrame_SetSelection = function(i) CR_SEL = i end
  LOADED_ADDONS["Blizzard_CraftUI"] = true
  FIRE("ADDON_LOADED", "Blizzard_CraftUI")
end
"""

L, KM = fresh(only=MODS, seed=SEED, extra=ITEMS + CLASSIC)
ns = KM.mods.Profession
L.globals().KingMakerTest_ns = ns
assert not KM.errorShown, last(L)
L.execute("LOAD_TRADESKILL()")
assert ns.hooked.classic and ns.hooked.TradeSkillFrame_SetSelection, "hooked TradeSkillFrame and its selection function"
L.execute("TradeSkillFrame:Show()")
assert L.eval("KingMakerProfessionPanel:IsShown()")
pt = L.eval("KingMakerProfessionPanel.point")
assert L.eval("KingMakerProfessionPanel.point[2] == TradeSkillFrame")
L.execute("TradeSkillFrame_SetSelection(2)")      # the game's own call: our post-hook redraws
c = ns.card
assert c is not None and c.item == 2851 and c.spell == 2661, (c and c.item, c and c.spell)
assert c.mats[1].have == 3, "the window's own reagent count"
assert c.skill == 95, c.skill
assert c.cost == 600 and abs(c.profit - 1300) < 1e-6 and abs(c.head - 1300) < 1e-6
L.execute("TradeSkillFrame_SetSelection(3)")
c = ns.card
assert c.item == 2852 and c.verdict.buy == "skip" and c.head < 0, c.verdict.buy     # 300 * 0.95 - 400 < 0: don't buy mats for it
assert ns.ui.card.pill.text.text == "SKIP"
# All crafts reads the classic list: what you know, and GetTradeSkillInfo's numAvailable
rows = list(ns.AllCrafts(2).values())
assert sorted(r.item for r in rows) == [2851, 2852], [r.item for r in rows]
assert rows[0].item == 2851 and rows[0].can == 5 and rows[1].can == 0 and rows[1].now is None, (rows[0].can, rows[1].can)
L.execute("ProfessionKingDB.tab = 'all'"); ns.Refresh()
assert not KM.errorShown, last(L)
L.execute("ProfessionKingDB.tab = 'card'")
L.execute("TradeSkillFrame_SetSelection(1)")      # a header: nothing to show
assert ns.card is None
L.execute("TradeSkillFrame:Hide()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is False

# Enchanting's craft window: an enchant, nothing to sell (not in Market's data: the window's reagents)
L.execute("LOAD_CRAFT(); CraftFrame:Show(); CraftFrame_SetSelection(1)")
assert ns.hooked.craft and L.eval("KingMakerProfessionPanel:IsShown()")
c = ns.card
assert c.spell == 7418 and c.item is None and c.cost == 150 and c.skill == 21, (c.spell, c.cost, c.skill)
assert "Enchant Bracer" in c.name
assert "nothing to sell" in L.eval("LINE('Sells for')") and ns.ui.card.pill.shown is False
L.execute("CraftFrame:Hide()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is False

# a client with no profession window at all: nothing breaks
L, KM = fresh(only=MODS, seed=SEED, extra=ITEMS + "C_TradeSkillUI = nil")
assert not KM.errorShown and L.eval("KingMakerProfessionPanel") is None
assert KM.mods.Profession.Active() is None and KM.mods.Profession.TooltipLines("item", 2851) is None
assert L.eval("#CRAFTED") == 0
print("profession classic: ok")
