# Shopping: lists (Favorites = Econ's favorites), the ShoppingKing API, the page, the panel at the auction house,
# the one-click-per-step buy flows with the max-price guard, Search all, export/import, Oracle import, /shop.
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
r1 = [r for r in lst(rows) if r.entry and r.entry.id == 2589][0]
r1.search.Click(r1.search)
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
assert ns.BuyItem(lst(cur.rows)[0]) is False and n("#BIDS") == 1, "guarded in code too, not just greyed"
print("ITEM OK")

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
KM.OpenSettings("shopping"); assert not KM.errorShown, last(L)
print("CROWN OK")

# --- Oracle (optional): its buy calls become the list "Oracle" -------------------------
L.execute("""Oracle = { GetData = function() return { actions = {
  { item_id = 2589, verb = "buy", target = 90, text = "Buy linen under 90c" },
  { item_id = 2770, verb = "sell", target = 700 },
  { verb = "buy", text = "no item" } } } end }""")
KM.Show("shopping")
assert ns.page.oracle.IsShown(ns.page.oracle)
ns.page.oracle.Click(ns.page.oracle)
assert ns.Active() == "Oracle"
o = lst(SK.Items("Oracle"))
assert len(o) == 1 and o[0].itemID == 2589 and o[0].max == 90, o
ns.page.oracle.Click(ns.page.oracle)
assert len(lst(SK.Items("Oracle"))) == 1, "importing again replaces, not doubles"
L.execute("Oracle = { GetData = function() error('boom') end }")
name, why = ns.ImportOracle()
assert name is None and "Oracle" in why
L.execute("Oracle = nil")
KM.Show("shopping"); assert not ns.page.oracle.IsShown(ns.page.oracle)
print("ORACLE OK")

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

assert not KM.errorShown, last(L)
print("shopping: ok")
