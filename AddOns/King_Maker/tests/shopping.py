# Shopping: lists (Favorites = Econ's favorites), the ShoppingKing API, the page, the panel at the auction house,
# the one-click-per-step buy flows with the max-price guard, Search all, export/import, /shop, virtual lists; and
# 2.6.0: no Oracle import, compact money, the row model and totals, deals first, live lists read-only, typing that
# survives refreshes, the Scanner callback and the badge, the ladder and default quantity, the gold check, the
# big-spend second click, the bid timeout, Next deal and the auto-advance (never buying), /shop deals.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page

# The suite's own auction house: commodities answer COMMODITY_SEARCH_RESULTS_UPDATED, other items
# ITEM_SEARCH_RESULTS_UPDATED (only one, like the real client), and the purchase calls record what they were asked.
EXTRA = """
ITEM(2589, "Linen Cloth", { quality = 1, class = 7, subclass = 5, stack = 20 })
ITEM(2770, "Copper Ore", { quality = 1, class = 7, subclass = 7, stack = 20 })
ITEM(6000, "Big Sword", { quality = 2, class = 2, subclass = 7, stack = 1 })
ITEM(118, "Minor Healing Potion", { quality = 1, class = 0, subclass = 1, stack = 5 })
function BTN(text, parent) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel and (not parent or f.parent == parent) then return f end end end
-- a chat-link function to hook, like the game's
function ChatEdit_InsertLink(link) INSERTED = link return false end

COMMOD = { [2589] = true, [2770] = true, [118] = true }
LADDER = { [2589] = { { 100, 50 }, { 120, 100 } }, [2770] = { { 500, 10 } }, [118] = { { 30, 20 } } }
LOTS = { [6000] = { { aid = 902, buyout = 50000, n = 1 }, { aid = 901, buyout = 40000, n = 1 } } }
SEARCHES, STARTED, CONFIRMED, BIDS, CANCELLED = {}, {}, {}, {}, 0
EXTRA_UNIT, FAIL_NEXT, READY = 0, false, true
local A = C_AuctionHouse
A.IsThrottledMessageSystemReady = function() return READY end
A.SendSearchQuery = function(key, sorts, sep)
  SEARCHES[#SEARCHES + 1] = key.itemID
  C_Timer.After(0.2, function()
    if COMMOD[key.itemID] then FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID) else FIRE("ITEM_SEARCH_RESULTS_UPDATED", key) end
  end)
end
A.GetNumCommoditySearchResults = function(id) return #(LADDER[id] or {}) end
A.GetCommoditySearchResultInfo = function(id, i) local r = (LADDER[id] or {})[i]; if r then return { itemID = id, unitPrice = r[1], quantity = r[2], auctionID = 1000 + i } end end
A.GetNumItemSearchResults = function(key) return #(LOTS[key.itemID] or {}) end
A.GetItemSearchResultInfo = function(key, i) local r = (LOTS[key.itemID] or {})[i]; if r then return { itemKey = key, auctionID = r.aid, buyoutAmount = r.buyout, quantity = r.n } end end
A.StartCommoditiesPurchase = function(id, qty)
  STARTED[#STARTED + 1] = { id = id, qty = qty }
  local unit = LADDER[id][1][1] + EXTRA_UNIT
  C_Timer.After(0.1, function() FIRE("COMMODITY_PRICE_UPDATED", unit, unit * qty) end)
end
A.ConfirmCommoditiesPurchase = function(id, qty)
  CONFIRMED[#CONFIRMED + 1] = { id = id, qty = qty }
  C_Timer.After(0.1, function() FIRE(FAIL_NEXT and "COMMODITY_PURCHASE_FAILED" or "COMMODITY_PURCHASE_SUCCEEDED") end)
end
A.CancelCommoditiesPurchase = function() CANCELLED = CANCELLED + 1 end
A.PlaceBid = function(aid, amount)
  BIDS[#BIDS + 1] = { aid = aid, amount = amount }
  C_Timer.After(0.1, function() FIRE("AUCTION_HOUSE_PURCHASE_COMPLETED", aid) end)
end
"""

SEED = """
NOW = 5000
ScannerKingDB = { prices = {
  [2589] = { p = 110, t = 4000, q = 150, m = 105 },
  [2770] = { p = 520, t = 4000, q = 10, m = 300 },
  [6000] = { p = 45000, t = 4000, q = 2 },
} }
"""

L, KM = fresh(only=["Scanner", "Econ", "Inventory", "Shopping"], seed=SEED, extra=EXTRA)
ns = KM.mods.Shopping
SK = L.eval("ShoppingKing")
shop = L.eval("SlashCmdList.SHOPPINGKING")
n = lambda expr: L.eval(expr)
# Price History's name cache is "quality:name" strings since 2.6.1: Shopping still finds items by those names
L.execute('EconKingDB.info[77002] = "2:Recipe: Zesty Stew"')
assert ns.ItemFrom("recipe: zesty stew") == 77002 and ns.Name(77002) == "Recipe: Zesty Stew"
L.execute("EconKingDB.info[77002] = nil")


def lst(t):
    return [t[i] for i in range(1, len(t) + 1)] if t else []


def run():
    L.execute("RUN_TIMERS()")


# --- saved data and defaults -----------------------------------------------------
assert SK.API_VERSION == 1
assert n("ShoppingKingDB.settings.autoPanel") is True and n("ShoppingKingDB.settings.sound") is True
assert n("ShoppingKingDB.settings.defaultMax") == "market" and n("ShoppingKingDB.active") == "Favorites"
assert lst(SK.Lists()) == ["Favorites"], lst(SK.Lists())
assert not KM.errorShown, last(L)
print("INIT OK")

# --- the public API ---------------------------------------------------------------
assert SK.Add(2589, 40, 150) is True
assert lst(SK.Lists()) == ["Favorites", "Shopping"], "nil list = Shopping, made on demand"
items = lst(SK.Items(None))
assert len(items) == 1 and items[0].itemID == 2589 and items[0].qty == 40 and items[0].max == 150, items
assert SK.Add(2589, 30, None) is True and lst(SK.Items("Shopping"))[0].qty == 30 and lst(SK.Items("Shopping"))[0].max == 150, "re-adding updates, keeps max"
assert len(lst(SK.Items("Shopping"))) == 1
assert SK.IsWanted(2589) == "Shopping" and SK.IsWanted(2770) is None
assert SK.Add("junk") is False and SK.Add(-3) is False and SK.Add(1.5) is False
assert SK.Add(118, 5, None, "Potions") is True and "Potions" in lst(SK.Lists())
assert SK.Remove(118, "Potions") is True and SK.Remove(118, "Potions") is False
assert SK.Remove(118, "No such list") is False
assert len(lst(SK.Items("No such list"))) == 0
print("API OK")

# --- Favorites are Econ's favorites, both ways ------------------------------------
L.eval("EconKing.SetFavorite(2770, true)")
fav = [e.itemID for e in lst(SK.Items("Favorites"))]
assert fav == [2770], fav
assert SK.IsWanted(2770) == "Favorites"
assert SK.Add(6000, 1, 60000, "Favorites") is True
assert n("EconKingDB.fav[6000]") is True and n("EconKing.IsFavorite(6000)")
f6 = [e for e in lst(SK.Items("Favorites")) if e.itemID == 6000][0]
assert f6.qty == 1 and f6.max == 60000, "favorites keep qty/max on the Shopping side"
L.execute('SlashCmdList.ECONKING("fav 6000")')   # Econ's own star toggle
assert 6000 not in [e.itemID for e in lst(SK.Items("Favorites"))], "removed in Econ, gone here"
L.execute('SlashCmdList.ECONKING("fav 6000")')
assert SK.Remove(6000, "Favorites") is True and not n("EconKing.IsFavorite(6000)")
assert n("ShoppingKingDB.favMeta[6000]") is None, "meta goes with the star"
print("FAVORITES OK")

# --- list CRUD --------------------------------------------------------------------
assert ns.CreateList("Raid") == "Raid" and ns.CreateList("raid") is None and ns.CreateList("  ") is None
assert ns.RenameList("Raid", "Raid mats") is True and lst(SK.Lists())[-1] == "Raid mats"
assert ns.RenameList("Favorites", "x") is False and ns.DeleteList("Favorites") is False
assert ns.RenameList("Raid mats", "Shopping") is False, "no two lists with one name"
ns.SetActive("Raid mats"); assert ns.Active() == "Raid mats"
assert ns.DeleteList("Raid mats") is True and ns.Active() == "Favorites", "deleting the open list falls back"
assert "Raid mats" not in lst(SK.Lists())
print("LISTS OK")

# --- the scanner prices every listed item -----------------------------------------
watched = lst(KM.mods.Scanner.WatchedItems())
assert 2589 in watched and 2770 in watched, watched
print("WATCH OK")

# --- export / import ----------------------------------------------------------------
ns.Update("Shopping", 2589, L.eval("{ note = 'for bandages, ok' }"))
code = ns.Export("Shopping")
assert code == "KMS1:Shopping:2589,30,150,for bandages  ok", code
name, count = ns.Import(code.replace("KMS1:Shopping:", "KMS1:Copy:") + ";2770,,600;118")
assert name == "Copy" and count == 3, (name, count)
copy = {e.itemID: e for e in lst(SK.Items("Copy"))}
assert copy[2589].qty == 30 and copy[2589].max == 150 and copy[2589].note == "for bandages  ok"
assert copy[2770].qty is None and copy[2770].max == 600 and copy[118].max is None
bad, why = ns.Import("hello")
assert bad is None and "KMS1" in why
bad, why = ns.Import("KMS1:X:12a,4")
assert bad is None and "damaged" in why
ns.DeleteList("Copy")
print("CODES OK")

# --- the page ----------------------------------------------------------------------
ns.SetActive("Shopping")
KM.Show("shopping")
assert not KM.errorShown, last(L)
assert KM.IsShown("shopping")
tbl = ns.table
assert len(lst(tbl.data)) == 1 and tbl.data[1].id == 2589 and tbl.data[1].status == "under", "110 lowest <= 150 max"
# shift-click a link into the focused add box
ab = ns.addBox
ab.RunScript(ab, "OnEditFocusGained")
L.execute("ChatEdit_InsertLink(LINK(6000))")
assert "item:6000" in ab.GetText(ab), ab.GetText(ab)
ns.wantBox.SetText(ns.wantBox, "2"); ns.maxBox.SetText(ns.maxBox, "4g 50s")
assert ns.AddFromBoxes() is True
e6 = ns.Find("Shopping", 6000)
assert e6.qty == 2 and e6.max == 45000, (e6.qty, e6.max)
ab.RunScript(ab, "OnEditFocusLost")
L.execute("ChatEdit_InsertLink(LINK(2770))")
assert ab.GetText(ab) == "", "only while the box has focus"
# by name, and a bad max
ab.SetText(ab, "Copper Ore"); ns.maxBox.SetText(ns.maxBox, "lots")
assert ns.AddFromBoxes() is False and "Max price" in ns.pageMsg.text
ns.maxBox.SetText(ns.maxBox, "")
assert ns.AddFromBoxes() is True and ns.Find("Shopping", 2770)
ab.SetText(ab, "Nothing Like This"); assert ns.AddFromBoxes() is False
assert len(lst(tbl.data)) == 3
# the edit bar
ns.SelectItem(2770)
ns.edit.max.SetText(ns.edit.max, "6s"); ns.edit.want.SetText(ns.edit.want, "10"); ns.edit.note.SetText(ns.edit.note, "ore")
ns.SaveEdit()
e7 = ns.Find("Shopping", 2770)
assert e7.max == 600 and e7.qty == 10 and e7.note == "ore"
ns.edit.max.SetText(ns.edit.max, ""); ns.SaveEdit()
assert ns.Find("Shopping", 2770).max is None, "an empty box clears the max"
# rows draw every column; Inventory's count shows when it has one
row = [r for r in lst(tbl.data) if r.id == 2589][0]
assert row.market == 105 and row.lowest == 110 and row.listed == 150
# new / rename / delete through the popups (the mock accepts them)
L.execute('POPUP_INPUT = "Raid"')
ns.page.new.Click(ns.page.new)
assert "Raid" in lst(SK.Lists()) and ns.Active() == "Raid"
L.execute('POPUP_AUTO_ACCEPT = false')
ns.page.rename.Click(ns.page.rename)
assert n("POPUPS[#POPUPS].dialog.editBox:GetText()") == "Raid", "rename starts from the old name"
L.execute('local p = POPUPS[#POPUPS]; p.dialog.editBox:SetText("Raid mats"); StaticPopupDialogs[p.name].OnAccept(p.dialog, p.data); POPUP_AUTO_ACCEPT = true')
assert ns.Active() == "Raid mats"
ns.page.delete.Click(ns.page.delete)
assert "Raid mats" not in lst(SK.Lists()) and ns.Active() == "Favorites"
ns.SetActive("Shopping")
# export window shows the code; import window reads one
ns.page.export.Click(ns.page.export)
assert n("KingMakerShoppingCode:IsShown()") and n("KingMakerShoppingCode").box.GetText(n("KingMakerShoppingCode").box).startswith("KMS1:Shopping:")
ns.page["import"].Click(ns.page["import"])
win = n("KingMakerShoppingCode")
win.box.SetText(win.box, "KMS1:Mats:2589,5")
win.go.Click(win.go)
assert ns.Active() == "Mats" and not win.IsShown(win)
ns.DeleteList("Mats"); ns.SetActive("Shopping")
for pid in open_every_page(L, KM):
    pass
KM.Show("shopping"); assert not KM.errorShown, last(L)
print("PAGE OK")

# --- the panel at the auction house ------------------------------------------------
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
panel = n("KingMakerShoppingPanel")
assert panel.IsShown(panel), "shows on AUCTION_HOUSE_SHOW"
assert n("KingMakerShoppingPanel.points[1][2] == AuctionHouseFrame and KingMakerShoppingPanel.points[1][3] == 'TOPRIGHT'"), "docked to the AH's right edge"
assert n("KingMakerShoppingPanel.parent == UIParent"), "our own frame, not parented to Blizzard's"
L.execute('FIRE("AUCTION_HOUSE_CLOSED"); FIRE("AUCTION_HOUSE_CLOSED")')
assert not panel.IsShown(panel) and not ns.toggle.IsShown(ns.toggle), "hides on close (twice is fine)"
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
panel.close.Click(panel.close)
assert not panel.IsShown(panel) and ns.toggle.IsShown(ns.toggle) and n("ShoppingKingDB.panel.shown") is False
L.execute('FIRE("AUCTION_HOUSE_CLOSED"); FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
assert not panel.IsShown(panel) and ns.toggle.IsShown(ns.toggle), "remembers it was closed"
ns.toggle.Click(ns.toggle)
assert panel.IsShown(panel) and not ns.toggle.IsShown(ns.toggle)
L.execute('ShoppingKingDB.settings.autoPanel = false; FIRE("AUCTION_HOUSE_CLOSED"); FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
assert not panel.IsShown(panel) and ns.toggle.IsShown(ns.toggle), "setting off: only the toggle"
assert n("ShoppingKingDB.panel.shown") is True
L.execute('ShoppingKingDB.settings.autoPanel = true; FIRE("AUCTION_HOUSE_CLOSED"); FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
assert panel.IsShown(panel)
rows = ns.panelRows
assert rows[1].entry and rows[1].IsShown(rows[1])
print("PANEL OK")

d = ns.detail
cur = ns.cur

# --- a commodity: two clicks, never one --------------------------------------------
# a row's Search fills Blizzard's search bar and runs its search, then the panel looks the item up too
L.execute("""
  AH_SEARCHED = {}
  AuctionHouseFrame.SearchBar = CreateFrame("Frame")
  AuctionHouseFrame.SearchBar.SearchBox = CreateFrame("EditBox")
  function AuctionHouseFrame.SearchBar:StartSearch() table.insert(AH_SEARCHED, self.SearchBox:GetText()) end
""")
r1 = [r for r in lst(rows) if r.entry and r.entry.id == 2589][0]
r1.search.Click(r1.search)
name = L.eval("AuctionHouseFrame.SearchBar.SearchBox:GetText()")
assert name and not name.startswith("Item "), name
assert L.eval("AH_SEARCHED[1]") == name and n("#AH_SEARCHED") == 1, "Blizzard's search ran once with the name"
run()
assert cur.id == 2589 and cur.kind == "commodity" and lst(cur.rows)[0].unit == 100, cur.kind
assert n("SEARCHES[#SEARCHES]") == 2589
assert ns.live[2589].p == 100 and ns.live[2589].q == 150
assert d.buy.enabled2 and not d.confirm.enabled2
assert d.qty.GetText(d.qty) == "30", "quantity defaults to the wanted amount"
d.qty.SetText(d.qty, "10")
d.buy.Click(d.buy)
run()
assert n("#STARTED") == 1 and n("STARTED[1].qty") == 10
assert cur.phase == "confirm" and "Confirm: 10 for" in cur.msg, cur.msg
assert n("#CONFIRMED") == 0, "no purchase without the Confirm click"
assert d.confirm.enabled2
d.confirm.Click(d.confirm)
assert n("#CONFIRMED") == 1 and n("CONFIRMED[1].id") == 2589 and n("CONFIRMED[1].qty") == 10
run()
assert ns.Find("Shopping", 2589).qty == 20, "wanted 30, bought 10"
assert cur.phase == "idle" and "Bought 10" in cur.msg
d.confirm.Click(d.confirm); assert n("#CONFIRMED") == 1, "a second Confirm click buys nothing"
assert ns.ConfirmBuy() is False
# Cancel after the price arrives
d.buy.Click(d.buy); run()
assert cur.phase == "confirm"
d.cancel.Click(d.cancel)
assert cur.phase == "idle" and n("CANCELLED") >= 1 and n("#CONFIRMED") == 1
print("COMMODITY OK")

# --- the max-price guard -----------------------------------------------------------
# the price comes back above the max: blocked, cancelled, Confirm greyed
L.execute("EXTRA_UNIT = 100")    # 200 each > max 150
before = n("CANCELLED")
d.buy.Click(d.buy); run()
assert cur.phase == "blocked" and n("CANCELLED") == before + 1 and "above your max" in cur.msg, cur.msg
assert not d.confirm.enabled2 and ns.ConfirmBuy() is False and n("#CONFIRMED") == 1
# the override, ticked for this purchase, lets it through (still two clicks)
d.override.frame.Click(d.override.frame)
assert cur.override
d.buy.Click(d.buy); run()
assert cur.phase == "confirm"
d.confirm.Click(d.confirm); run()
assert n("#CONFIRMED") == 2 and ns.Find("Shopping", 2589).qty == 0
L.execute("EXTRA_UNIT = 0")
# a max below the cheapest listing greys Buy before anything is asked
ns.Update("Shopping", 2589, L.eval("{ max = 50, qty = 5 }"))
ns.Select(2589, "Shopping"); ns.Search(2589, L.eval("{ select = true }")); run()
assert not cur.override, "picking the item again clears the override"
assert not d.buy.enabled2
started = n("#STARTED")
assert ns.StartBuy(5) is False and n("#STARTED") == started
# no max of its own: the market price is the max (setting), Copper Ore market 300 < cheapest 500
ns.Select(2770, "Shopping"); ns.Search(2770, L.eval("{ select = true }")); run()
assert cur.kind == "commodity" and ns.CurMax() == 300
assert ns.StartBuy(1) is False and n("#STARTED") == started and not d.buy.enabled2
L.execute('ShoppingKingDB.settings.defaultMax = "none"')
assert ns.CurMax() is None and ns.StartBuy(1) is True
run(); ns.CancelBuy(True)
L.execute('ShoppingKingDB.settings.defaultMax = "market"')
# a failed purchase leaves the wanted quantity alone
ns.Update("Shopping", 2589, L.eval("{ max = 150, qty = 5 }"))
ns.Select(2589, "Shopping"); ns.Search(2589, L.eval("{ select = true }")); run()
L.execute("FAIL_NEXT = true")
d.buy.Click(d.buy); run(); d.confirm.Click(d.confirm); run()
assert "failed" in cur.msg and ns.Find("Shopping", 2589).qty == 5 and cur.phase == "idle"
L.execute("FAIL_NEXT = false")
print("GUARD OK")

# --- a non-commodity item: one click per auction ------------------------------------
r6 = [r for r in lst(rows) if r.entry and r.entry.id == 6000][0]
r6.search.Click(r6.search); run()
assert cur.id == 6000 and cur.kind == "item"
lots = lst(cur.rows)
assert [x.buyout for x in lots] == [40000, 50000], "cheapest first"
a1, a2 = d.auctions[1], d.auctions[2]
assert a1.IsShown(a1) and a1.buy.enabled2 and not a2.buy.enabled2, "50g is above the 4g50s max"
a2.buy.Click(a2.buy); assert n("#BIDS") == 0
a1.buy.Click(a1.buy)
assert n("#BIDS") == 1 and n("BIDS[1].aid") == 901 and n("BIDS[1].amount") == 40000
assert len(lst(cur.rows)) == 1, "the bought auction leaves the list"
run()
assert ns.Find("Shopping", 6000).qty == 1 and "Bought" in cur.msg
over = [x for x in lst(cur.rows) if x.buyout == 50000][0]
assert ns.BuyItem(over) is False and n("#BIDS") == 1, "guarded in code too, not just greyed"
print("ITEM OK")

# Blizzard's search bar missing (or the AH closed): Search falls back to the panel's own search, nothing breaks
L.execute("AuctionHouseFrame.SearchBar = nil; SEARCHES = {}")
r1.search.Click(r1.search); run()
assert n("SEARCHES[#SEARCHES]") == 2589
L.execute("AH_SEARCHED = {}")
assert ns.SearchInAH(2589) is False
print("AH SEARCH OK")

# a pattern (stack of 1) whose auction row reports quantity 24: the unit price is the buyout, not buyout / 24
L.execute("""
  ITEM(8390, "Pattern: Big Voodoo Cloak", { quality = 2, class = 9, subclass = 1, stack = 1 })
  LOTS[8390] = { { aid = 950, buyout = 1400, n = 24 } }
""")
ns.Select(8390, "Shopping"); ns.Search(8390, L.eval("{ select = true }")); run()
assert lst(cur.rows)[0].unit == 1400 and lst(cur.rows)[0].qty == 1, lst(cur.rows)[0].unit
assert ns.live[8390].p == 1400 and ns.live[8390].q == 24, "listed still counts what the game reported"
print("STACK OK")

# --- Search all only searches -------------------------------------------------------
L.execute("SEARCHES = {}")
s0, c0, b0 = n("#STARTED"), n("#CONFIRMED"), n("#BIDS")
ns.live[2770] = None
panel.all.Click(panel.all)
run()
assert sorted(lst(n("SEARCHES"))) == [2589, 2770, 6000], lst(n("SEARCHES"))
assert (n("#STARTED"), n("#CONFIRMED"), n("#BIDS")) == (s0, c0, b0), "nothing bought"
assert ns.live[2770].p == 500 and "Searched 3 items" in cur.msg, cur.msg
assert not ns.SearchAllRunning()
under = [r for r in lst(rows) if r.entry and r.good.shown]
assert sorted(r.entry.id for r in under) == [2589, 6000], "under-max rows are highlighted (the mock still lists the 40g sword)"
# a scan in progress: Search all waits
L.execute("ScannerKing.IsScanning = function() return true end")
L.execute("SEARCHES = {}"); ns.SearchAll(); run()
assert len(lst(n("SEARCHES"))) == 0 and "scan is running" in cur.msg
L.execute("ScannerKing.IsScanning = function() return false end")
print("SEARCH ALL OK")

# --- throttle and a closed auction house ---------------------------------------------
L.execute("READY = false")
ns.Select(2589, "Shopping")
assert ns.Search(2589, L.eval("{ select = true }")) is False and "throttled" in cur.msg
assert ns.StartBuy(1) is False and "throttled" in cur.msg
L.execute("READY = true")
L.execute('FIRE("AUCTION_HOUSE_CLOSED")')
L.execute('AH_OPEN = false')
assert ns.Search(2589) is False and ns.StartBuy(1) is False
L.execute('AH_OPEN = true; FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
print("THROTTLE OK")

# --- the crown tooltip and Home ------------------------------------------------------
L.execute('GameTooltip.lines = {}; KingMakerMinimapButton:RunScript("OnEnter")')
tip = [str(x) for x in n("GameTooltip.lines").values()]
assert any(x.startswith("Shopping: ") and "under your max" in x for x in tip), tip
assert ns.UnderMaxCount() >= 1
L.execute('MENU = nil; KingMakerMinimapButton:Click("RightButton")')
L.execute('MENU_ITEM("Shopping").fn()'); assert KM.IsShown("shopping")
KM.Show("home"); assert not KM.errorShown, last(L)
deal = [a for a in KM.home.attItems.values() if a.page == "shopping"]
assert deal and "under your max" in deal[0].text and deal[0].text.startswith(str(ns.UnderMaxCount())), "Home: the deals row"
KM.OpenSettings("shopping"); assert not KM.errorShown, last(L)
print("CROWN OK")

# --- the old "Import Oracle buy list" is gone: Oracle supplies its own live list (RegisterListProvider) ------
L.execute("""Oracle = { GetData = function() return { actions = {
  { item_id = 2589, verb = "buy", target = 90, text = "Buy linen under 90c" } } } end }""")
KM.Show("shopping"); assert not KM.errorShown, last(L)
assert n('BTN("Import Oracle buy list")') is None, "no import button, even with Oracle loaded"
assert ns.ImportOracle is None and ns.OracleData is None
assert ns.page.oracle is None
L.execute("Oracle = nil")
print("ORACLE IMPORT GONE OK")

# --- /shop ----------------------------------------------------------------------------
shop("add 118 12 25c")
e = ns.Find("Shopping", 118)
assert e and e.qty == 12 and e.max == 25, (e and e.qty, e and e.max)
shop("add Linen Cloth 7")
assert ns.Find("Shopping", 2589).qty == 7
L.execute('SlashCmdList.SHOPPINGKING("add " .. LINK(6000) .. " 3 5g")')
assert ns.Find("Shopping", 6000).qty == 3 and ns.Find("Shopping", 6000).max == 50000
shop("list")
assert any("Shopping: 4 items" in o for o in outputs(L)), outputs(L)[-4:]
shop("list shopping"); assert any("Minor Healing Potion" in o for o in outputs(L))
shop("remove 118"); assert ns.Find("Shopping", 118) is None
shop("help"); assert any("/shop add" in o for o in outputs(L))
shop("panel"); assert not panel.IsShown(panel)
shop("panel"); assert panel.IsShown(panel)
shop(""); assert KM.IsShown("shopping")
print("SLASH OK")

# --- InitDB twice, and repairs a damaged table ------------------------------------------
before = lst(SK.Lists())
ns.InitDB(); ns.InitDB()
assert lst(SK.Lists()) == before and ns.Find("Shopping", 2589).qty == 7
L2, KM2 = fresh(only=["Scanner", "Econ", "Inventory", "Shopping"], extra=EXTRA, seed="""
ShoppingKingDB = { lists = { Mats = { items = { { id = 2589, qty = 3 } } }, Favorites = { items = {} }, Bad = 5 },
  order = { "Gone", "Mats", "Mats" }, active = "Gone", settings = { defaultMax = "weird", sound = false } }
""")
SK2 = L2.eval("ShoppingKing")
assert [SK2.Lists()[i] for i in range(1, len(SK2.Lists()) + 1)] == ["Favorites", "Mats"]
assert L2.eval("ShoppingKingDB.active") == "Favorites" and L2.eval("ShoppingKingDB.settings.defaultMax") == "market"
assert L2.eval("ShoppingKingDB.settings.sound") is False, "a saved false stays false"
assert SK2.IsWanted(2589) == "Mats"
for pid in open_every_page(L2, KM2):
    pass
print("INITDB OK")

# Virtual lists (RegisterListProvider, for Oracle): live items, never saved, read-only here, purchases reported back
L3, KM3 = fresh(only=["Scanner", "Econ", "Inventory", "Shopping"], extra=EXTRA, seed="""
ShoppingKingDB = { lists = { ["Oracle Bank"] = { items = { { id = 2770, qty = 9 } } } }, order = { "Oracle Bank" } }
""")
SK3 = L3.eval("ShoppingKing")
before = L3.eval("ShoppingKingDB.lists['Oracle Bank'].items[1].qty")
L3.execute("""VB = {}; VQTY = 5
ok = ShoppingKing.RegisterListProvider("Oracle Bank", {
  items = function() return { { itemID = 2589, qty = VQTY, max = 150 } } end,
  bought = function(id, n) VB[#VB + 1] = { id, n }; VQTY = VQTY - n end })""")
assert L3.eval("ok") is True
names = [SK3.Lists()[i] for i in range(1, len(SK3.Lists()) + 1)]
assert names == ["Favorites", "Oracle Bank"], names
items = SK3.Items("Oracle Bank")
assert items[1].itemID == 2589 and items[1].qty == 5 and items[1].max == 150 and len(items) == 1, "the provider's items, not the saved ones"
assert SK3.IsWanted(2589) == "Oracle Bank"
assert SK3.Add(2770, 1, 1, "Oracle Bank") is False and SK3.Remove(2589, "Oracle Bank") is False, "read-only"
KMS = KM3.mods.Shopping
KMS.Bought("Oracle Bank", 2589, 2)
assert L3.eval("VB[1][1]") == 2589 and L3.eval("VB[1][2]") == 2 and SK3.Items("Oracle Bank")[1].qty == 3, "purchase reported back"
assert KMS.RenameList("Oracle Bank", "X") is False and KMS.DeleteList("Oracle Bank") is False
assert L3.eval("ShoppingKingDB.lists['Oracle Bank'].items[1].qty") == before, "the saved list is untouched"
for name in ["Favorites", "Shopping", "Oracle"]:
    assert L3.eval(f'ShoppingKing.RegisterListProvider("{name}", {{ items = function() return {{}} end }})') is False, name
for pid in open_every_page(L3, KM3):
    pass
L3.execute('ShoppingKing.UnregisterListProvider("Oracle Bank")')
assert SK3.Items("Oracle Bank")[1].itemID == 2770, "unregistered: the saved list is back"
assert "Oracle Bank" in [SK3.Lists()[i] for i in range(1, len(SK3.Lists()) + 1)]
print("VIRTUAL LISTS OK")


# =====================================================================================================
# 2.6.0: compact money, the row model and totals, the redesigned page and panel, buying safety
# =====================================================================================================

# --- ns.Short: money that fits a table cell ----------------------------------------------------------
S = ns.Short
assert S(None, True) == "-" and "-" in S(None)
assert S(9, True) == "9c" and S(4509, True) == "45s 9c" and S(4500, True) == "45s"
assert S(34509, True) == "3g 45s", S(34509, True)
assert S(29999, True) == "3g", "rounded to the silver, 0s left out"
assert S(12345678, True) == "1,234g", S(12345678, True)
assert S(-4509, True) == "-45s 9c"
assert "|c" not in S(34509, True) and "|cffffd700g|r" in S(34509)
assert ns.Pct(-0.334) == "-33%" and ns.Pct(0.13) == "+13%" and ns.Pct(0.001) == "0%" and ns.Pct(None) is None
print("SHORT OK")

EXTRA4 = EXTRA + """
ITEM(4306, "Silk Cloth", { quality = 1, class = 7, subclass = 5, stack = 20 })
COMMOD[4306] = true
LADDER[4306] = { { 400, 10 } }
"""
SEED4 = """
NOW = 5000
ScannerKingDB = { prices = {
  [2589] = { p = 100, t = 4000, q = 150, m = 105 },
  [2770] = { p = 540, t = 4000, q = 10, m = 300 },
  [118]  = { p = 105, t = 4000, q = 20, m = 110 },
  [4306] = { p = 400, t = 4000, q = 10 },
}, lastScan = 4000 }
ShoppingKingDB = { lists = {
    Mats = { items = { { id = 2589, qty = 30, max = 150 }, { id = 2770, qty = 5, max = 600 }, { id = 118, qty = 4, max = 100 },
                       { id = 6000, qty = 1, max = 50000 }, { id = 4306, qty = 0, max = 500 } } },
    Oracle = { items = { { id = 2589, qty = 1 } } } },
  order = { "Mats", "Oracle" }, active = "Mats" }
"""
L, KM = fresh(only=["Scanner", "Econ", "Inventory", "Shopping"], seed=SEED4, extra=EXTRA4)
ns = KM.mods.Shopping
SK = L.eval("ShoppingKing")
shop = L.eval("SlashCmdList.SHOPPINGKING")
n = lambda expr: L.eval(expr)
assert not KM.errorShown, last(L)

# --- saved data: new settings default on, the sort is remembered, nothing renamed -------------------------
assert n("ShoppingKingDB.settings.autoNext") is True and n("ShoppingKingDB.settings.bigSpend") is True
assert n("ShoppingKingDB.ui.sort.key") == "status" and n("ShoppingKingDB.ui.sort.desc") is False
assert n("ShoppingKingDB.version") == 1
# an old imported "Oracle" list is a normal list now: it shows, can be renamed, and no provider may take the name
assert "Oracle" in lst(SK.Lists()) and ns.IsMine("Oracle")
assert n('ShoppingKing.RegisterListProvider("Oracle", { items = function() return {} end })') is False
print("SAVED 2.6 OK")

# --- ns.Row / Summary / AllSummary ----------------------------------------------------------------
r = ns.Row(ns.Find("Mats", 2589))
assert r.status == "under" and abs(r.pct - (-50 / 150)) < 1e-9 and r.cost == 3000 and r.costMax == 4500 and r.save == 1500, (r.status, r.pct, r.cost)
assert ns.Row(ns.Find("Mats", 118)).status == "over" and ns.Row(ns.Find("Mats", 6000)).status == "noprice"
assert ns.Row(ns.Find("Mats", 4306)).status == "done"
s = ns.Summary("Mats")
assert (s["items"], s.deals, s.over, s.noPrice, s.done) == (5, 2, 1, 1, 1), (s["items"], s.deals, s.over, s.noPrice, s.done)
assert s.dealsCost == 30 * 100 + 5 * 540 and s.dealsSave == 1500 + 5 * 60, (s.dealsCost, s.dealsSave)
assert s.fillMax == 4500 + 3000 + 400 + 50000, s.fillMax
a = ns.AllSummary()
assert a.deals == 2 and ns.UnderMaxCount() == 2, "Linen on two lists counts once"
assert ns.SortKey(ns.Row(ns.Find("Mats", 2589))) < ns.SortKey(ns.Row(ns.Find("Mats", 2770))), "bigger saving first"
print("ROW SUMMARY OK")

# --- the page: sort, row looks, money that fits ------------------------------------------------------
KM.Show("shopping"); assert not KM.errorShown, last(L)
tbl = ns.table
order = [tbl.data[i].id for i in range(1, len(tbl.data) + 1)]
assert order == [2589, 2770, 118, 6000, 4306], order
rows = tbl.rows
def cells(i): return rows[i].cells
assert rows[1].deal.shown and rows[1].dealBar.shown and cells(1).status.text == "DEAL"
assert cells(3).status.text == "" and abs(cells(3).lowest.color[1] - KM.UI.C.dim[1]) < 1e-6, "over max: no word, dim numbers"
assert cells(4).status.text == "NO SCAN" and cells(5).status.text == "DONE"
for i in range(1, 6):
    row = tbl.data[i]
    dim = row.status not in ("under", "nomax")
    if row.lowest:
        assert cells(i).lowest.text == S(row.lowest, dim), (i, cells(i).lowest.text)
    if row.cost:
        assert cells(i).cost.text == S(row.cost, row.status != "under")
assert cells(1).pct.text == "-33%" and cells(3).pct.text == "+5%"
# pooled rows reset their looks when the order changes
tbl.SetSort(tbl, "name", False); tbl.Redraw(tbl)
for i in range(1, 6):
    if tbl.data[i].status != "under" and rows[i].deal:
        assert not rows[i].deal.shown, "a reused row drops the deal tint"
tbl.headers.status.RunScript(tbl.headers.status, "OnClick")
assert n("ShoppingKingDB.ui.sort.key") == "status", "the sort is remembered"
KM.Refresh("shopping")
# tooltip: the numbers behind the row
L.execute("GameTooltip.lines = {}")
rows[1].RunScript(rows[1], "OnEnter")
tip = [str(x) for x in n("GameTooltip.lines").values()]
assert any("Your max" in x and "under" in x for x in tip) and any(x.startswith("Lowest") for x in tip), tip
print("PAGE TABLE OK")

# --- the detail pane: list totals, the editor, Price History's average --------------------------------
ns.SelectItem(None)
t = ns.tiles
assert t[1].IsShown(t[1]) and "2 of 5" in t[1].value.text and "1 above max" in t[1].sub.text
assert t[2].value.text == S(5700) and "saves" in t[2].sub.text
assert t[3].value.text == S(57900)
assert t[4].value.text == "16m ago", t[4].value.text
ns.SelectItem(2589)
ed = ns.edit
assert not t[1].IsShown(t[1]) and ed.max.IsShown(ed.max) and ed.max.GetText(ed.max) == "1s 50c"
assert "DEAL" in ed.status.text and "-33%" in ed.status.text
assert "Lowest" in ed.facts1.text and "Fill 30" in ed.facts2.text
assert not ed.suggest.IsShown(ed.suggest), "no Price History numbers yet: no suggestion"
L.execute("REAL_STATS = EconKing.GetStats; EconKing.GetStats = function(id) return { avg7 = 12000, trend7 = 0.04, low30 = 9000, high30 = 15000 } end")
ns.edit.filledFor = None
ns.SelectItem(2589)
assert ed.suggest.IsShown(ed.suggest) and "7d" in ed.suggest.label.text, ed.suggest.label.text
ed.suggest.Click(ed.suggest)
assert ed.max.GetText(ed.max) == "1g 20s" and ns.Find("Mats", 2589).max == 150, "fills the box, doesn't save"
assert "+4%" in cells(1).trend.text
L.execute("EconKing.GetStats = REAL_STATS")
ns.SelectItem(2770)
assert ed.max.GetText(ed.max) == "6s", "another item refills the boxes"
print("DETAIL OK")

# --- typing survives refreshes (a scan, a purchase, another addon's list) ---------------------------------
ns.SelectItem(2589)
ed.max.RunScript(ed.max, "OnEditFocusGained")
ed.max.SetText(ed.max, "9s")
ns.Changed(); SK.RefreshLists(); KM.Refresh("shopping")
assert ed.max.GetText(ed.max) == "9s", "focused: never wiped"
ed.max.RunScript(ed.max, "OnEditFocusLost")
ns.Changed()
assert ed.max.GetText(ed.max) == "9s", "same item, unsaved: still not wiped"
ed.max.RunScript(ed.max, "OnEnterPressed")
assert ns.Find("Mats", 2589).max == 900 and "Saved" in ns.pageMsg.text, "Enter saves"
ns.Update("Mats", 2589, L.eval("{ max = 150 }"))
print("FOCUS GUARD OK")

# --- the add row's Max hint ----------------------------------------------------------------------------
assert ns.maxBox.hint.text == "market"
L.execute('ShoppingKingDB.settings.defaultMax = "none"'); KM.Refresh("shopping")
assert ns.maxBox.hint.text == "no limit"
L.execute('ShoppingKingDB.settings.defaultMax = "market"'); KM.Refresh("shopping")
print("ADD HINT OK")

# --- live lists are read-only on the page ------------------------------------------------------------
L.execute("""ShoppingKing.RegisterListProvider("Raid buys", { owner = "TestAddon", note = "from the raid sheet",
  items = function() return { { itemID = 2589, qty = 3, max = 150 }, { itemID = 118, qty = 2, max = 200 } } end })""")
assert tuple(ns.ProviderInfo("Raid buys")) == ("TestAddon", "from the raid sheet")
ns.SetActive("Raid buys"); ns.SelectItem(None)
pg = ns.page
assert not pg.rename.enabled2 and not pg.delete.enabled2 and pg.export.enabled2
assert not ns.addBox.IsShown(ns.addBox) and ns.addInfo.IsShown(ns.addInfo) and "TestAddon" in ns.addInfo.text
assert "Live list from TestAddon" in ed.vhint.text
ns.SelectItem(2589)
assert not ed.max.IsShown(ed.max) and not ed.save.IsShown(ed.save) and ed.virtual.IsShown(ed.virtual)
assert ns.SaveEdit() is False and "Can't edit a live list" in ns.pageMsg.text
pg.rename.Click(pg.rename); pg.delete.Click(pg.delete)
assert "Raid buys" in lst(SK.Lists()) and ns.Active() == "Raid buys", "disabled buttons do nothing"
# right-click: no Remove, no live lists as targets, and "Also add" reports what really happened
L.execute("MENU = nil")
r1 = [rows[i] for i in range(1, 3) if rows[i].data and rows[i].data.id == 2589][0]
r1.RunScript(r1, "OnClick", "RightButton")
items = [it.text for it in lst(n("MENU"))]
assert not any(x.startswith("Remove") for x in items), items
assert "Also add to Mats" in items and "Also add to Raid buys" not in items and "Open in Price History" in items, items
L.execute('MENU_ITEM("Also add to Favorites").fn()')
assert n("EconKing.IsFavorite(2589)") and "added to Favorites" in ns.pageMsg.text
# the side: a divider before the live lists, their deal counts
side = [b for b in lst(L.eval("(function() local t = {} for _, f in ipairs(FRAMES) do if f.list then t[#t+1] = f end end return t end)()"))]
assert any(b.list == "Raid buys" for b in side)
assert pg.divider.shown
ns.SetActive("Mats")
print("LIVE LIST READ-ONLY OK")

# --- a scan refreshes the page and the badge (Scanner callback) ---------------------------------------
L.execute("ScannerKingDB.prices[118].p = 90")
assert ns.Row(ns.Find("Mats", 118)).status == "under"
ns.SelectItem(None)
before = [tbl.data[i].id for i in range(1, len(tbl.data) + 1)]
KM.mods.Scanner.Fire("PRICES_UPDATED")
run()
row118 = [tbl.data[i] for i in range(1, len(tbl.data) + 1) if tbl.data[i].id == 118][0]
assert row118.lowest == 90 and row118.status == "under", "the page redrew after the scan"
badge = KM.pages.shopping.badgeValue
assert badge.count == 3 and badge.color == "gold" and "3 items" in badge.tip, badge
assert not KM.pages.shopping.crownBadge
L.execute("ScannerKingDB.prices[118].p = 105")
KM.mods.Scanner.Fire("SCAN_FINISHED"); run()
assert KM.pages.shopping.badgeValue.count == 2
print("SCANNER CALLBACK BADGE OK")

# --- /shop deals ----------------------------------------------------------------------------------------
L.execute("OUTPUT = {}")
shop("deals")
out = outputs(L)
lin = [i for i, o in enumerate(out) if "Linen Cloth" in o]
cop = [i for i, o in enumerate(out) if "Copper Ore" in o]
assert lin and cop and lin[0] < cop[0], out
assert any("2 deals" in o for o in out), out
shop("help"); assert any("/shop deals" in o for o in outputs(L))
print("SHOP DEALS OK")

# --- the panel: row click looks up, deals first, ladder, default quantity, estimate ------------------------
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
panel = n("KingMakerShoppingPanel")
assert panel.IsShown(panel)
prow = ns.panelRows
assert prow[1].data.id == 2589 and prow[1].good.shown and prow[1].bar.shown, "deals first, tinted"
assert "2 deals" in panel.summary.text, panel.summary.text
d, cur = ns.detail, ns.cur
L.execute("SEARCHES = {}")
prow[1].Click(prow[1]); run()
assert cur.id == 2589 and lst(n("SEARCHES")) == [2589], "a row click selects and looks the item up (one search)"
assert len(lst(ns.live[2589].ladder)) == 2
assert ns.UnderQty(2589, 110) == 50 and ns.UnderQty(2589, 150) == 150 and ns.UnderQty(2589, 50) == 0
cost, full = ns.LadderCost(2589, 60)
assert cost == 50 * 100 + 10 * 120 and full is True
assert d.qty.GetText(d.qty) == "30" and "~" in d.buy.label.text, d.buy.label.text
assert any("your max" in fs.text for fs in lst(d.ladderLines)) is False, "everything under max: no divider"
assert "150 listed at or under your max" in d.under.text, d.under.text
# want more than are under the max: the quantity starts at what's under it
ns.Update("Mats", 2589, L.eval("{ max = 110, qty = 80 }"))
ns.Select(2589, "Mats"); run()
assert cur.qty == 50 and d.qty.GetText(d.qty) == "50", cur.qty
assert any("your max" in fs.text for fs in lst(d.ladderLines)), "a line where the max falls"
ns.Update("Mats", 2589, L.eval("{ max = 150, qty = 30 }"))
ns.Select(2589, "Mats"); run()
print("PANEL LOOKUP LADDER OK")

# --- the gold check -----------------------------------------------------------------------------------
started, confirmed, cancelled = n("#STARTED"), n("#CONFIRMED"), n("CANCELLED")
L.execute("MONEY = 100")
d.buy.Click(d.buy)
assert n("#STARTED") == started and "you carry" in cur.msg, cur.msg
L.execute("MONEY = 1234567")
d.buy.Click(d.buy)
assert n("#STARTED") == started + 1
L.execute("MONEY = 50"); run()
assert cur.phase == "blocked" and n("CANCELLED") == cancelled + 1 and n("#CONFIRMED") == confirmed and "you carry" in cur.msg
L.execute("MONEY = 1234567")
print("GOLD CHECK OK")

# --- a big spend needs a second Confirm click ------------------------------------------------------------
ns.Select(2589, "Mats"); run()
L.execute("MONEY = 10000")                    # 30 x 100 = 3000: 30% of the gold carried
d.buy.Click(d.buy); run()
assert cur.phase == "confirm" and "% of your gold" in cur.msg and d.confirm.label.text.startswith("Confirm "), d.confirm.label.text
d.confirm.Click(d.confirm)
assert n("#CONFIRMED") == confirmed and d.confirm.label.text.startswith("Click again"), "the first click only arms it"
d.confirm.Click(d.confirm)
assert n("#CONFIRMED") == confirmed + 1
run()
spent1 = 3000
# the arm runs out after 4 seconds
ns.Update("Mats", 2589, L.eval("{ qty = 30 }")); ns.Select(2589, "Mats"); run()
d.buy.Click(d.buy); run()
d.confirm.Click(d.confirm); L.execute("ADVANCE(5)")
d.confirm.Click(d.confirm)
assert n("#CONFIRMED") == confirmed + 1, "too late: the second click arms again instead of buying"
ns.CancelBuy(True)
L.execute("ShoppingKingDB.settings.bigSpend = false")
d.buy.Click(d.buy); run(); d.confirm.Click(d.confirm)
assert n("#CONFIRMED") == confirmed + 2, "setting off: one click"
run()
spent2 = 3000
L.execute("ShoppingKingDB.settings.bigSpend = true; MONEY = 1234567")
print("BIG SPEND OK")

# --- Next deal and the auto-advance: they select and search, never buy -------------------------------------
ns.Update("Mats", 2589, L.eval("{ qty = 30 }"))
ns.Select(2589, "Mats"); run()
L.execute("SEARCHES = {}")
assert ns.NextDeal() == 2770
d.next.Click(d.next); run()
assert cur.id == 2770 and lst(n("SEARCHES")) == [2770], lst(n("SEARCHES"))
s0, c0, b0 = n("#STARTED"), n("#CONFIRMED"), n("#BIDS")
d.buy.Click(d.buy); run(); d.confirm.Click(d.confirm)
assert (n("#STARTED"), n("#CONFIRMED")) == (s0 + 1, c0 + 1)
run()                                           # bought all 5: looks again, then moves on by itself
assert ns.Find("Mats", 2770).qty == 0
assert cur.id == 2589, cur.id
assert (n("#STARTED"), n("#CONFIRMED"), n("#BIDS")) == (s0 + 1, c0 + 1, b0), "moving on never buys"
spent3 = 5 * 500
# setting off: stays put
L.execute("ShoppingKingDB.settings.autoNext = false")
ns.Update("Mats", 2770, L.eval("{ qty = 5 }")); ns.Select(2770, "Mats"); run()
d.buy.Click(d.buy); run(); d.confirm.Click(d.confirm); run()
assert cur.id == 2770 and ns.Find("Mats", 2770).qty == 0
spent4 = 5 * 500
L.execute("ShoppingKingDB.settings.autoNext = true")
ns.Update("Mats", 2770, L.eval("{ qty = 5 }"))
print("NEXT DEAL AUTO-ADVANCE OK")

# --- Search all picks the best deal with no extra search ----------------------------------------------
L.execute("SEARCHES = {}")
ns.Select(4306, "Mats")
panel.all.Click(panel.all); run()
assert len(lst(n("SEARCHES"))) == 5, lst(n("SEARCHES"))
# the live prices now: potions at 30c (max 1s) are the biggest saving
assert ns.ActiveRows()[1].id == 118 and cur.id == 118 and len(lst(cur.rows)) > 0 and "4 deals" in cur.msg, (cur.id, cur.msg)
assert d.buy.enabled2, "its auctions came from the search just made"
print("SEARCH ALL PICKS OK")

# --- an auction that never answers: dropped after 6 s, searched again -------------------------------------
L.execute("C_AuctionHouse.PlaceBid = function(aid, amount) BIDS[#BIDS + 1] = { aid = aid, amount = amount } end")
ns.Select(6000, "Mats"); ns.Search(6000, L.eval("{ select = true }")); run()
a1 = d.auctions[1]
assert cur.kind == "item" and a1.buy.enabled2
L.execute("SEARCHES = {}")
a1.buy.Click(a1.buy)
assert ns.PendingBids() == 1
run()
assert ns.PendingBids() == 0 and "No answer" in cur.msg and ns.Find("Mats", 6000).qty == 1
assert lst(n("SEARCHES")) == [6000], "and looks again"
# a buyout above the gold carried is refused before asking
L.execute("MONEY = 100")
b0 = n("#BIDS")
d.auctions[1].buy.Click(d.auctions[1].buy)
assert n("#BIDS") == b0 and "you carry" in cur.msg
L.execute("MONEY = 1234567")
print("BID TIMEOUT OK")

# --- what this visit spent ------------------------------------------------------------------------------
sess = ns.session
assert sess.spent == spent1 + spent2 + spent3 + spent4 and sess.buys == 4, (sess.spent, sess.buys)
ns.RefreshPanel()
assert "spent" in panel.summary.text and "spent this visit" in d.spent.text
L.execute("OUTPUT = {}")
L.execute('FIRE("AUCTION_HOUSE_CLOSED"); FIRE("AUCTION_HOUSE_CLOSED")')
assert len([o for o in outputs(L) if "this visit" in o]) == 1, outputs(L)
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
assert ns.session.spent == 0 and ns.session.buys == 0
# Page: opens the page on the panel's item
ns.Select(2770, "Mats")
panel.page.Click(panel.page)
assert KM.IsShown("shopping") and ns.Selected() == 2770
for pid in open_every_page(L, KM):
    pass
assert not KM.errorShown, last(L)
print("SESSION OK")

# --- no deals; and without Price History the page still works -------------------------------------------
L5, KM5 = fresh(only=["Scanner", "Inventory", "Shopping"], seed=SEED4, extra=EXTRA4)
L5.execute("ScannerKingDB.prices = {}")
L5.execute('SlashCmdList.SHOPPINGKING("deals")')
assert any("No deals right now" in o for o in outputs(L5)), outputs(L5)
L5.execute("ScannerKingDB.prices[2589] = { p = 100, t = 4000, q = 150 }")
KM5.Show("shopping"); assert not KM5.errorShown, last(L5)
ns5 = KM5.mods.Shopping
assert "-" in ns5.table.rows[1].cells.trend.text
ns5.SelectItem(2589)
assert ns5.edit.graphOff.shown and not ns5.edit.history.shown
assert not KM5.errorShown, last(L5)
print("NO ECON OK")

# --- the deal line: one chat line after a scan when the deals changed (2.6.0) ---------------------------
L6, KM6 = fresh(only=["Scanner", "Econ", "Inventory", "Shopping"], seed=SEED4, extra=EXTRA4)
fire6 = KM6.mods.Scanner.Fire
shop6 = L6.eval("SlashCmdList.SHOPPINGKING")
assert L6.eval("ShoppingKingDB.settings.dealLine") is True, "on by default"


def scan6(found=5):
    L6.execute("OUTPUT = {}")
    fire6("SCAN_FINISHED", found)
    L6.execute("RUN_TIMERS()")
    return [o for o in outputs(L6) if "Shopping item" in o]


got = scan6()
assert len(got) == 1, outputs(L6)
line = got[0]
assert "Scan done: 2 Shopping items under your max (" in line, line
assert line.index("Linen Cloth") < line.index("Copper Ore"), "best deal first"
assert "|Hitem:2589" in line and "|Hitem:2770" in line, "clickable item links"
assert "1|cffc7c7cfs|r" in line and "5|cffc7c7cfs|r 40|cffeda55fc|r" in line, "compact money"
assert line.count("Linen Cloth") == 1, "an item on two lists is named once"
assert scan6() == [], "the same deals again: no line"
# one more deal: a line naming all three
L6.execute("ScannerKingDB.prices[118].p = 90")
got = scan6(); assert len(got) == 1 and "3 Shopping items" in got[0] and "Minor Healing Potion" in got[0], got
# the same count, but a different item became a deal: a line
L6.execute("ScannerKingDB.prices[2770].p = 700; ScannerKingDB.prices[6000] = { p = 40000, t = 4000, q = 1 }")
got = scan6(); assert len(got) == 1 and "3 Shopping items" in got[0] and "Big Sword" in got[0] and "Copper Ore" not in got[0], got
# fewer deals is a change too; no deals at all says nothing
L6.execute("ScannerKingDB.prices[118].p = 105")
got = scan6(); assert len(got) == 1 and "2 Shopping items" in got[0], got
# more than three: three named, then "+N more"
L6.execute("ScannerKingDB.prices[118].p = 90; ScannerKingDB.prices[2770].p = 500")
got = scan6(); assert len(got) == 1 and "4 Shopping items" in got[0] and got[0].endswith(", +1 more)"), got
# a scan that found nothing (stopped, or the auction house closed) never prints
L6.execute("ScannerKingDB.prices[118].p = 105")
assert scan6(found=0) == [], "a failed scan says nothing"
got = scan6(); assert len(got) == 1 and "3 Shopping items" in got[0]
# in combat: nothing, and the next scan out of combat still reports the change
L6.execute("COMBAT = true; ScannerKingDB.prices[118].p = 90")
assert scan6() == [], "never in combat"
L6.execute("COMBAT = false")
got = scan6(); assert len(got) == 1 and "4 Shopping items" in got[0], got
# the setting (Settings > Shopping) and /shop notify
KM6.OpenSettings("shopping")
assert "Say in chat when a scan finds deals" in [str(x) for x in L6.eval("TEXTS()").values()]
shop6("notify")
assert L6.eval("ShoppingKingDB.settings.dealLine") is False and "off." in last(L6)
L6.execute("ScannerKingDB.prices[118].p = 105")
assert scan6() == [], "setting off: no line"
shop6("notify on"); assert L6.eval("ShoppingKingDB.settings.dealLine") is True and "on." in last(L6)
shop6("help"); assert any("/shop notify" in o for o in outputs(L6))
assert not KM6.errorShown, last(L6)
print("DEAL LINE OK")

assert not KM.errorShown, last(L)

# --- 2.6.2: Keep N in stock -------------------------------------------------------------------------------
SEED7 = """
NOW = 5000
ScannerKingDB = { prices = {
  [2589] = { p = 100, t = 4000, q = 150, m = 105 },
  [2770] = { p = 540, t = 4000, q = 10, m = 300 },
}, lastScan = 4000 }
ShoppingKingDB = { lists = {
    Mats = { items = { { id = 2589, keep = 20, max = 150 }, { id = 2770, qty = 5, max = 600 } } } },
  order = { "Mats" }, active = "Mats" }
"""
L, KM = fresh(only=["Scanner", "Econ", "Inventory", "Shopping"], seed=SEED7, extra=EXTRA)
ns = KM.mods.Shopping
SK = L.eval("ShoppingKing")
shop = L.eval("SlashCmdList.SHOPPINGKING")
n = lambda expr: L.eval(expr)
assert not KM.errorShown, last(L)


def badge():
    b = KM.pages.shopping.badge()
    return b if b is None or isinstance(b, (int, float)) else b["count"]


# what you own: this character and an alt on this realm and faction, and the warband bank; not the Horde alt, not
# another realm (they can't mail it here)
L.execute("""
local st = InventoryKingDB.stock
st["Jay-Forever"] = { bags = { [2589] = 8 } }
st["Alt-Forever"] = { bank = { [2589] = 4 } }
st["Horde Guy-Forever"] = { bags = { [2589] = 50 } }
st["Other-Elsewhere"] = { bags = { [2589] = 100 } }
st["Warband"] = { bank = { [2589] = 1 } }
InventoryKingDB.chars["Horde Guy-Forever"] = { faction = "Horde" }
InventoryKingDB.chars["Alt-Forever"] = { faction = "Alliance" }
""")
owned, here = ns.OwnHere(2589)
assert owned == 13 and here["Horde Guy-Forever"] is None and here["Other-Elsewhere"] is None, owned
e = ns.Find("Mats", 2589)
need, own2, coming = ns.KeepNeed(e)
assert (need, own2, coming) == (7, 13, 0), (need, own2, coming)
r = ns.Row(e)
assert r.keep == 20 and r.qty == 7 and r.need == 7 and r.status == "under", (r.keep, r.qty, r.need, r.status)
assert r.cost == 700 and r.costMax == 1050 and r.save == 350, (r.cost, r.costMax, r.save)
assert ns.KeepNeed(ns.Find("Mats", 2770)) is None, "a Buy item has no keep need"
s = ns.Summary("Mats")
assert s.deals == 2 and s.dealsCost == 700 + 5 * 540 and s.fillMax == 1050 + 3000, (s.deals, s.dealsCost, s.fillMax)
assert badge() == 2
assert SK.IsWanted(2589) == "Mats"
items = {i.itemID: i for i in lst(SK.Items("Mats"))}
assert items[2589].keep == 20 and items[2589].qty == 7 and items[2770].keep is None and items[2770].qty == 5
# the table: "keep 20" in Want, what you own here in Own, a tooltip that says what it means
KM.Show("shopping"); assert not KM.errorShown, last(L)
tbl = ns.table
i = [k for k in range(1, len(tbl.data) + 1) if tbl.data[k].id == 2589][0]
assert tbl.rows[i].cells.qty.text == "keep 20" and tbl.rows[i].cells.own.text == "13", tbl.rows[i].cells.qty.text
L.execute("GameTooltip.lines = {}")
tbl.rows[i].RunScript(tbl.rows[i], "OnEnter")
tip = [str(x) for x in n("GameTooltip.lines").values()]
assert any("Keep 20 in stock: you have 13" in x and "buy 7" in x and "doesn't count down" in x for x in tip), tip
ns.SelectItem(2589)
ed = ns.edit
assert ed.mode.current == "keep" and ed.want.GetText(ed.want) == "20" and "Keep 20: 13 here, buy 7" in ed.facts2.text, ed.facts2.text
print("KEEP NEED OK")

# at the auction house: the panel buys up to the need; a purchase doesn't count down, it's on its way until counted
L.execute("MONEY = 10000000")
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
d, cur = ns.detail, ns.cur
ns.Select(2589, "Mats"); ns.Search(2589, L.eval("{ select = true }")); run()
assert cur.qty == 7 and d.qty.GetText(d.qty) == "7", cur.qty
assert "Need 7 (keep 20)" in d.info.text, d.info.text
d.buy.Click(d.buy); run()
assert n("STARTED[#STARTED].qty") == 7
d.confirm.Click(d.confirm); run()
e = ns.Find("Mats", 2589)
assert e.keep == 20 and e.qty is None, "Keep doesn't count down"
assert e.transit.n == 7 and e.transit.own == 13
assert ns.KeepNeed(e)[0] == 0 and ns.Row(e).status == "done" and ns.StatusLabel(ns.Row(e))[0] == "STOCKED"
assert SK.IsWanted(2589) is None and badge() == 1, "stocked: no longer a deal"
assert cur.id == 2770, "stocked, so the panel moves on to the next deal"
# the mail is read: the count shows them, nothing on its way any more
L.execute("ADVANCE(5); InventoryKingDB.stock['Jay-Forever'].mail = { [2589] = 7 }; InventoryKingDB.stock['Jay-Forever'].mailT = NOW")
assert ns.KeepNeed(ns.Find("Mats", 2589))[0] == 0 and ns.OwnHere(2589)[0] == 20
# using some refills the need
L.execute("InventoryKingDB.stock['Jay-Forever'].bags[2589] = 3")
need, owned, coming = ns.KeepNeed(ns.Find("Mats", 2589))
assert (need, owned, coming) == (5, 15, 0), (need, owned, coming)
assert ns.Row(ns.Find("Mats", 2589)).status == "under" and SK.IsWanted(2589) == "Mats"
# bought again, the mailbox not opened yet: held as on its way; arrivals count against it; two days and it lapses
L.execute("ADVANCE(60)")
ns.Select(2589, "Mats"); run()
assert cur.qty == 5
d.buy.Click(d.buy); run(); d.confirm.Click(d.confirm); run()
assert n("STARTED[#STARTED].qty") == 5
e = ns.Find("Mats", 2589)
assert e.transit.n == 5 and ns.KeepNeed(e)[0] == 0
L.execute("InventoryKingDB.stock['Jay-Forever'].bags[2589] = 5")
assert ns.KeepNeed(ns.Find("Mats", 2589))[0] == 0 and ns.TransitLeft(ns.Find("Mats", 2589), 17) == 3, "2 of 5 arrived"
L.execute("ShoppingKingDB.lists.Mats.items[1].transit.t = NOW - 3 * 86400")
assert ns.KeepNeed(ns.Find("Mats", 2589))[0] == 3, "a purchase never counted lapses after two days"
L.execute('FIRE("AUCTION_HOUSE_CLOSED")')
print("KEEP PANEL OK")

# switching modes in the editor: Keep saves at once with the number in the box; Buy goes back to counting down
KM.Show("shopping")
ns.SelectItem(2770)
assert ed.mode.current == "buy" and ed.want.GetText(ed.want) == "5"
ed.mode.buttons.keep.Click(ed.mode.buttons.keep)
e = ns.Find("Mats", 2770)
assert e.keep == 5 and e.qty is None and ns.Row(e).keep == 5
i = [k for k in range(1, len(tbl.data) + 1) if tbl.data[k].id == 2770][0]
assert tbl.rows[i].cells.qty.text == "keep 5"
ed.want.SetText(ed.want, "12"); ed.save.Click(ed.save)
assert ns.Find("Mats", 2770).keep == 12
ed.want.SetText(ed.want, ""); ed.save.Click(ed.save)
assert ns.Find("Mats", 2770).keep == 12 and "Keep how many" in ns.pageMsg.text, "Keep needs a number"
ed.mode.buttons.buy.Click(ed.mode.buttons.buy)
ed.want.SetText(ed.want, "6"); ed.save.Click(ed.save)
e = ns.Find("Mats", 2770)
assert e.keep is None and e.transit is None and e.qty == 6 and ns.Row(e).qty == 6
# a Buy item counts down as before
ns.Bought("Mats", 2770, 2); assert ns.Find("Mats", 2770).qty == 4
# Favorites take Keep too (its fields live in favMeta)
SK.Add(2589, None, None, "Favorites")
ns.SetKeep("Favorites", 2589, 30)
assert n("ShoppingKingDB.favMeta[2589].keep") == 30 and ns.KeepNeed(ns.Find("Favorites", 2589))[0] == 30 - 17
ns.SetKeep("Favorites", 2589, False); assert n("ShoppingKingDB.favMeta[2589]") is None
print("KEEP MODES OK")

# /shop keep, the list code and live lists
shop("keep 2770 12")
assert ns.Find("Shopping", 2770).keep == 12 and "keeping 12 Copper Ore in stock" in last(L), last(L)
shop("list Shopping"); assert any("keep 12" in o for o in outputs(L))
shop("keep 2770 off")
assert ns.Find("Shopping", 2770).keep is None and "back to buying" in last(L)
shop("keep"); assert "/shop keep [item" in last(L)
shop("help"); assert any("/shop keep" in o for o in outputs(L))
ns.SetKeep("Mats", 2770, 9)
code = ns.Export("Mats")
assert code == "KMS1:Mats:2589,,150,,20;2770,,600,,9", code
name, count = ns.Import(code.replace("KMS1:Mats:", "KMS1:Copy:"))
assert name == "Copy" and count == 2 and ns.Find("Copy", 2589).keep == 20 and ns.Find("Copy", 2770).keep == 9
name, count = ns.Import("KMS1:Old:2589,30,150,a note")
assert ns.Find("Old", 2589).qty == 30 and ns.Find("Old", 2589).keep is None and ns.Find("Old", 2589).note == "a note", "old codes still read"
# a live list's items never take Keep (they belong to the other addon)
SK.RegisterListProvider("Live", L.eval("{ items = function() return { { itemID = 2589, qty = 3, keep = 50 } } end }"))
assert ns.KeepNeed(ns.Find("Live", 2589)) is None and ns.Row(ns.Find("Live", 2589)).qty == 3
assert ns.SetKeep("Live", 2589, 5) is False
KM.Show("shopping"); assert not KM.errorShown, last(L)
print("KEEP SLASH CODES OK")

assert not KM.errorShown, last(L)
print("shopping: ok")
