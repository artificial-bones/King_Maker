# Profession (new in 2.1): the King Maker panel docked to the game's profession window. Both window paths are
# faked here: the modern ProfessionsFrame (CraftingPage.SchematicForm + the EventRegistry recipe callback,
# C_TradeSkillUI) and the classic TradeSkillFrame / CraftFrame (GetTradeSkill* / GetCraft* + the selection hooks).
# Checked: panel shows and hides with the window, card values (cost, owned, profit after the cut, skill-up colour,
# verdicts), Best now ranking and skill-ups, add-to-Shopping (present and absent), tooltips, settings, /km
# profession, InitDB twice, and that nothing ever crafts.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

MODS = ["Scanner", "Econ", "Market", "Skillup", "Inventory", "Profession"]

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
"""

SEED = """
ScannerKingDB = { prices = {
  [2840] = { p = 100, t = 900, q = 50 }, [2589] = { p = 20, t = 900, q = 80 },
  [2851] = { p = 2000, t = 900, q = 7, m = 2200 }, [2852] = { p = 300, t = 900, q = 3 }, [2844] = { p = 900, t = 900, q = 2 },
  [10940] = { p = 150, t = 900 }, [10939] = { p = 600, t = 900 }, [10978] = { p = 800, t = 900 }, [99001] = { p = 700, t = 900 } } }
SkillupKingDB = { chars = { ["Jay-Forever"] = { known = {}, skills = { [2] = { cur = 60, max = 150 } } } } }
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
C_TradeSkillUI.GetRecipeInfo = function(id) local i = info(id); if i and id == 999001 then i.relativeDifficulty = 1 end return i end
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
assert not KM.errorShown, last(L)
assert L.eval("ProfessionKingDB.show") is True and L.eval("ProfessionKingDB.side") == "right"
assert L.eval("ProfessionKingDB.mode") == "market" and L.eval("ProfessionKingDB.tooltip") is True
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
assert ns.card is None and any("Pick a recipe" in (t or "") for t in L.eval("TEXTS()").values())

L.execute("SELECT(2661)")
c = ns.card
assert c is not None and c.spell == 2661 and c.item == 2851, c
assert c.cost == 600 and c.costAll == 600, c.cost                   # 6 Copper Bar x 1s
m1 = c.mats[1]
assert m1.id == 2840 and m1.need == 6 and m1.have == 4 and m1.unit == 100 and m1.line == 600
assert c.color == "orange" and c.chance == 1 and c.skill == 60, (c.color, c.chance, c.skill)
assert c.market == 2200 and c.lowest == 2000 and c.listed == 7
assert abs(c.profit - (2000 * 0.95 - 600)) < 1e-6, c.profit          # after the 5% cut, Market's rule (lowest)
assert c.de and c.de > 0 and c.deSale < c.de                         # green armor disenchants
assert c.verdict.buy == "craft" and c.verdict.farm == "craft", (c.verdict.buy, c.verdict.farm)
assert c.avg30 is not None and len(list(c.history.values())) == 2
assert abs(c.farm.gain - (2000 * 0.95 - 6 * 100 * 0.95)) < 1e-6
texts = L.eval("TEXTS()")
assert any("Copper Chain Belt" in (t or "") for t in texts.values())
assert any("orange" in (t or "") for t in texts.values())

# a recipe with a vendor reagent, picked through the polled SchematicForm only (no callback)
L.execute("SELECTED = 2737")
L.execute("ADVANCE(1)")
c = ns.card
assert c.spell == 2737, c.spell
flux = [m for m in c.mats.values() if m.id == 2880][0]
assert flux.vendor and flux.unit == 100, (flux.vendor, flux.unit)    # vendor: 4x its sell price until seen at a merchant
assert c.cost == 6 * 100 + 100 + 2 * 20
assert c.color == "yellow" and abs(c.chance - 35 / 40) < 1e-9, c.color   # 2737: yellow 55, grey 95: at 60 it is (95-60)/(95-55)
L.execute("SELECT(2661)")

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

# a Forever-only recipe the data doesn't know: the window's own reagents and difficulty
L.execute("SELECT(999001)")
c = ns.card
assert c.item == 99001 and c.cost == 200 and c.color == "yellow" and c.chance is None, (c.cost, c.color)
assert abs(c.profit - (700 * 0.95 - 200)) < 1e-6
L.execute("SELECT(2661)")

def ours(lines):   # our lines (the Scanner, Econ and Inventory add their own item lines too)
    return [l for l in lines.values() if "King Maker|r cost" in l or "Skill-up|r" in l]


# tooltips: hovering a recipe's item inside the window adds King Maker lines; elsewhere nothing
L.execute("GameTooltip:SetOwner(RECIPE_ROW, 'ANCHOR_RIGHT')")
_, lines = L.eval("HOVER(2851)")
lines = ours(lines)
assert len(lines) == 2, lines
assert any("King Maker" in l and "profit" in l for l in lines), lines
assert any("Skill-up" in l and "orange" in l and "100%" in l for l in lines), lines
L.execute("GameTooltip:SetOwner(UIParent, 'ANCHOR_RIGHT')")
_, lines = L.eval("HOVER(2851)")
assert len(ours(lines)) == 0, "not inside the profession window"
L.execute("GameTooltip:SetOwner(RECIPE_ROW, 'ANCHOR_RIGHT')")
_, lines = L.eval("HOVER(2840)")
assert len(ours(lines)) == 0, "a reagent is not a recipe of this profession"
L.execute("GameTooltip.lines = {}; for _, fn in ipairs(TOOLTIP_CALLS[1] or {}) do fn(GameTooltip, { id = 2661, type = 1 }) end")
assert len(ours(L.eval("GameTooltip.lines"))) == 2, "spell tooltips too"
L.execute("ProfessionKingDB.tooltip = false")
_, lines = L.eval("HOVER(2851)")
assert len(ours(lines)) == 0, "setting off"
L.execute("ProfessionKingDB.tooltip = true")

# Best now: Market's ranking for this profession and the next skill-ups
best = L.eval("BTN('Best now', KingMakerProfessionPanel)")
best.RunScript(best, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.tab") == "best"
rows = ns.BestCrafts(2, 10)
gains = [r.gain for r in rows.values()]
assert len(gains) >= 2 and gains == sorted(gains, reverse=True), gains
assert rows[1].item == 2851, rows[1].item                             # the belt is the best flip at these prices
# Listed and Make on craft rows: a quarter of the 7 belts listed rounds up to 2; one day of units leaving caps it
assert rows[1].verdict == "craft" and rows[1].listed == 7 and rows[1].make == 2, (rows[1].verdict, rows[1].listed, rows[1].make)
L.execute("EconKing = EconKing or {}; OLD_STATS = EconKing.GetStats; EconKing.GetStats = function(id) if id == 2851 then return { gonePerDay = 1.4 } end end")
assert tuple(ns.Batch(2851))[:2] == (7, 1), "no more than a day's worth"
L.execute("ScannerKingDB.prices[2851].q = 0")
assert tuple(ns.Batch(2851))[:2] == (0, 1), "nothing listed: make one to test"
L.execute("ScannerKingDB.prices[2851].q = 7; EconKing.GetStats = OLD_STATS")
assert ns.Batch(10940) is None, "never scanned for quantity"
steps = ns.NextSkillups(2, 60, 150, 8)
assert len(list(steps.values())) > 0 and steps[1]["from"] == 60, steps[1]
assert not KM.errorShown, last(L)
# clicking a Best now row shows its card, selecting it in the window through C_TradeSkillUI.OpenRecipe
L.execute("SELECTED = 2737; SELECT(2737)")
ns.Pin(2661)
assert L.eval("OPENED") == 2661 and L.eval("ProfessionKingDB.tab") == "card"
L.execute("ADVANCE(1)")
assert ns.card.spell == 2661
# a pinned recipe the window can't select stays on the card until the window's selection changes
ns.Pin(2662)
assert ns.card.spell == 2662 and ns.card.source == "data"
L.execute("ADVANCE(1)")
assert ns.card.spell == 2662
L.execute("SELECT(2737)")
L.execute("ADVANCE(1)")
assert ns.card.spell == 2737, "the window's new selection wins"

# collapse keeps it small
col = L.eval("BTN('-', KingMakerProfessionPanel)")
col.RunScript(col, "OnClick", "LeftButton")
assert L.eval("ProfessionKingDB.collapsed") is True and L.eval("KingMakerProfessionPanel:GetHeight()") == 30
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
assert any("Show the King Maker panel" in (t or "") for t in L.eval("TEXTS()").values())
KM.Toggle(False)
L.eval("SlashCmdList.KINGMAKER")("profession")
assert KM.CurrentPage() == "settings"
L.eval("SlashCmdList.KINGMAKER")("")          # everything else still goes to /km
assert not L.eval("KingMakerFrame:IsShown()")

# InitDB twice keeps the same table and settings, and /km is wrapped once
L.execute("ProfessionKingDB.side = 'left'; ProfessionKingDB.mode = 'farm'; HELD = ProfessionKingDB")
L.execute("WRAPPED = SlashCmdList.KINGMAKER")
ns.InitDB(); ns.InitDB()
assert L.eval("ProfessionKingDB == HELD") and L.eval("ProfessionKingDB.side") == "left" and L.eval("ProfessionKingDB.mode") == "farm"
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
  { "Copper Chain Belt", "easy", item = 2851, reagents = { { 2840, 6, 3 } } },
  { "Copper Chain Pants", "trivial", item = 2852, reagents = { { 2840, 4, 3 } } },
}
TS_SEL = 0
GetTradeSkillLine = function() return "Blacksmithing", 95, 150 end
GetNumTradeSkills = function() return #TS end
GetTradeSkillInfo = function(i) local t = TS[i]; if t then return t[1], t[2], 0, true end end
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
GetCraftDisplaySkillLine = function() return "Enchanting", 72, 150 end
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
assert c.skill == 95 and c.color == "green" and abs(c.chance - 0.5) < 1e-9, (c.skill, c.color, c.chance)
assert c.cost == 600 and abs(c.profit - 1300) < 1e-6
L.execute("TradeSkillFrame_SetSelection(3)")
c = ns.card
assert c.item == 2852 and c.verdict.buy == "skip", c.verdict.buy     # 300 * 0.95 - 400 < 0: don't buy mats for it
L.execute("TradeSkillFrame_SetSelection(1)")      # a header: nothing to show
assert ns.card is None
L.execute("TradeSkillFrame:Hide()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is False

# Enchanting's craft window: an enchant, nothing to sell
L.execute("LOAD_CRAFT(); CraftFrame:Show(); CraftFrame_SetSelection(1)")
assert ns.hooked.craft and L.eval("KingMakerProfessionPanel:IsShown()")
c = ns.card
assert c.spell == 7418 and c.item is None and c.cost == 150 and c.color == "orange" and c.chance == 1, (c.spell, c.cost, c.color)
assert "Enchant Bracer" in c.name
# the window's colour wins over the built-in data (Skillup's data says yellow at 72)
L.execute("CR[1][3] = 'medium'; CraftFrame_SetSelection(1)")
c = ns.card
assert c.color == "yellow" and abs(c.chance - 38 / 40) < 1e-9, (c.color, c.chance)
L.execute("CraftFrame:Hide()")
assert L.eval("KingMakerProfessionPanel:IsShown()") is False

# a client with no profession window at all: nothing breaks
L, KM = fresh(only=MODS, seed=SEED, extra=ITEMS + "C_TradeSkillUI = nil")
assert not KM.errorShown and L.eval("KingMakerProfessionPanel") is None
assert KM.mods.Profession.Active() is None and KM.mods.Profession.TooltipLines("item", 2851) is None
assert L.eval("#CRAFTED") == 0
print("profession classic: ok")
