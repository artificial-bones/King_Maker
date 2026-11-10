# Inventory (was Inventory King), with Scanner and Mail: bags, bank, warband bank, mailbox and auctions into stock,
# gold, net worth, the daily history, the one-time import of Mail King 1.1's stock and gold (also when Boot moves the
# old MailKingDB in after this module's InitDB), tooltip counts, the Inventory page (Overview, Items), export, /ik.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

DAY = 86400
ME = "Jay-Forever"

EXTRA = """
NOW = 1760000000
ITEM(2589, "Linen Cloth", { class = 7, subclass = 5, sell = 10 })
ITEM(2770, "Copper Ore", { class = 7, subclass = 7, sell = 5 })
ITEM(6000, "Green Sword", { class = 2, subclass = 7, quality = 2, sell = 1000 })
ITEM(118, "Minor Healing Potion", { class = 0, subclass = 1, sell = 6 })
ITEM(9000, "Soulbound Ring", { class = 4, subclass = 1, sell = 500 })
BAGS[0][1] = { id = 2589, count = 20 }; BAGS[0][2] = { id = 2589, count = 15 }; BAGS[1][1] = { id = 118, count = 5 }
BAGS[0][3] = { id = 9000, count = 1, bound = true }
BAGS[-1][1] = { id = 2770, count = 40 }
BAGS[12] = { { id = 2770, count = 10 } }; SIZES[12] = 1   -- the warband bank
function ChatEdit_InsertLink(l) LINKED = l return true end
function HASFONT(s) for _, t in ipairs(FONTS) do if t.text and tostring(t.text):find(s, 1, true) then return true end end return false end
function SIDE(text) for _, f in ipairs(FRAMES) do if rawget(f, "entry") and f.shown ~= false and f.label.text and f.label.text:find(text, 1, true) then return f end end end
"""
PRICES = "ScannerKingDB = { prices = { [2589] = { p = 90, m = 100, t = 1760000000 }, [2770] = { p = 40, t = 1760000000 } } }"


def load(only=("Scanner", "Inventory", "Mail"), seed=PRICES, **kw):
    L, KM = fresh(only=list(only), extra=EXTRA, seed=seed, **kw)
    return L, KM, KM.mods.Inventory


def click(b, which="LeftButton"): b.RunScript(b, "OnClick", which)
def rows(t): return [r for r in t.rows.values() if r.data and r.shown is not False]
def ids(ns): t = ns.CurrentItems(); return sorted(t[i].item for i in range(1, len(t) + 1))
def tip(L): return [str(x) for x in L.eval("GameTooltip.lines").values()]


L, KM, ns = load()
ik = L.eval("SlashCmdList.INVENTORYKING")
IK = L.eval("InventoryKing")
stock = lambda: L.eval("InventoryKingDB.stock")
assert IK.API_VERSION == 1
assert L.eval("InventoryKingMinimapButton") is None and L.eval("InventoryKingFrame") is None, "no window or button of its own"
assert L.eval("InventoryKingDB.ui.button") is None and L.eval("InventoryKingDB.ui.tooltip") is True
assert L.eval("InventoryKingDB.ui.vendor") is True and L.eval("InventoryKingDB.ui.price") == "market"

# Bags at login (soulbound left out), the character and their gold
me = stock()[ME]
assert me.bags[2589] == 35 and me.bags[118] == 5 and me.bags[9000] is None and me.bagsT == L.eval("NOW"), list(me.bags.items())
c = L.eval("InventoryKingDB.chars")[ME]
assert c.gold == 1234567 and c["class"] == "WARRIOR" and c.level == 42 and c.faction == "Alliance" and c.seen
assert me.bank is None, "the bank is only read while it's open"
# a bag change is read once it settles
L.execute("BAGS[1][2] = { id = 118, count = 3 }; FIRE('BAG_UPDATE_DELAYED'); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert stock()[ME].bags[118] == 8
L.execute("BAGS[1][2] = nil; FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
print("BAGS OK")

# The bank and the warband bank, while the banker window is open
L.execute("FIRE('PLAYER_INTERACTION_MANAGER_FRAME_SHOW', Enum.PlayerInteractionType.Banker); RUN_TIMERS()")
assert stock()[ME].bank[2770] == 40 and stock()["Warband"].bank[2770] == 10
L.execute("FIRE('PLAYER_INTERACTION_MANAGER_FRAME_HIDE', Enum.PlayerInteractionType.Banker)")
# closed: bag changes don't touch what the bank had
L.execute("BAGS[-1][1] = nil; FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert stock()[ME].bank[2770] == 40
print("BANK OK")

# The mailbox: attachments and gold waiting there (not COD)
L.execute("""OPEN_MAIL({ { subject = "From Alt", money = 5000, att = { name = "Green Sword", id = 6000, n = 1 } },
                         { subject = "Hello", money = 0 } })""")
assert stock()[ME].mail[6000] == 1 and L.eval("InventoryKingDB.chars")[ME].mail == 5000
# your auctions still up (a sold one is on its way as gold)
L.execute("""OWNED = { { itemKey = { itemID = 2589 }, quantity = 10, status = 0 }, { itemKey = { itemID = 2770 }, quantity = 5, status = 1 } }
FIRE("OWNED_AUCTIONS_UPDATED"); RUN_TIMERS()""")
assert stock()[ME].ah[2589] == 10 and stock()[ME].ah[2770] is None
# gold changes
L.execute("MONEY = 2000000; FIRE('PLAYER_MONEY'); RUN_TIMERS()")
assert L.eval("InventoryKingDB.chars")[ME].gold == 2000000
print("MAIL AND AH OK")

# What it's worth: market price, else lowest, else vendor
assert ns.Price(2589) == (100, "market") and ns.Price(2770) == (40, "lowest") and ns.Price(118) == (6, "vendor")
assert ns.Price(6000) == (1000, "vendor")
w = IK.NetWorth()
jay_assets = 35 * 100 + 5 * 6 + 40 * 40 + 1000 + 10 * 100
assert w.gold == 2000000 and w.mail == 5000 and w.assets == jay_assets + 400 and w.chars == 1, (w.gold, w.mail, w.assets, w.chars)
assert w.total == 2005000 + jay_assets + 400 and w["items"] == 35 + 5 + 40 + 1 + 10 + 10
total, by = IK.GetCount(2770)
assert total == 50 and by[ME] == 40 and by["Warband"] == 10
chars = list(IK.GetCharacters().values())
assert [x.who for x in chars] == [ME, "Warband"] and chars[0].worth == 2005000 + jay_assets and chars[0].bankSeen
res = ns.Items(L.table_from({"who": ME, "place": "bags"}))
assert sorted(r.item for r in res.rows.values()) == [118, 2589], "filter by who and where"
res = ns.Items(L.table_from({"search": "metal"}))
assert [r.item for r in res.rows.values()] == [2770], "search matches categories too"
print("WORTH OK")

# Net worth history: today's point, carried forward over days without one
hist = list(IK.GetHistory(30).values())
assert len(hist) == 30 and hist[-1].total == w.total and hist[-1].known and not hist[0].known
day = L.eval("math.floor(NOW / 86400)")
assert L.eval("InventoryKingDB.history[%d]['%s'].g" % (day, ME)) == 2005000
L.execute("NOW = NOW + 2 * 86400; MONEY = 2100000; FIRE('PLAYER_MONEY'); RUN_TIMERS()")
hist = list(IK.GetHistory(5).values())
assert hist[-1].gold == 2100000 + 5000 and hist[-2].gold == 2005000 and hist[-3].gold == 2005000, [h.gold for h in hist]
only_bank = list(IK.GetHistory(3, "Warband").values())
assert only_bank[-1].assets == 400 and only_bank[-1].gold == 0
# a scan reprices everything
L.execute("ScannerKingDB.prices[118] = { p = 50, t = NOW }")
ns.Snapshot()
assert L.eval("InventoryKingDB.history[%d]['%s'].a" % (day + 2, ME)) == jay_assets - 30 + 250
print("HISTORY OK")

# Tooltips: how many you own and where, under the Scanner module's lines
first, lines = L.eval("HOVER(2589)")
lines = [str(x) for x in lines.values()]
assert any(l.startswith("Inventory King: 45 owned|worth") for l in lines), lines
assert any("Jay" in l and l.endswith("|bags 35, on AH 10") for l in lines), lines
ik("tooltip off"); assert L.eval("InventoryKingDB.ui.tooltip") is False
_, lines = L.eval("HOVER(2589)")
assert not any("owned" in str(l) for l in lines.values())
ik("tooltip on")
_, lines = L.eval("HOVER(9000)")
assert not any("owned" in str(l) for l in lines.values()), "soulbound is never counted"
print("TOOLTIP OK")

# Settings that change the price
ik("price lowest"); assert ns.Price(2589) == (90, "lowest") and "lowest buyout" in last(L)
ik("price market")
ik("vendor off"); assert ns.Price(118)[0] == 50 and ns.Price(6000) is None
ik("vendor on")

# The Inventory page: Overview
L.execute('InventoryKingDB.chars["Alt-Forever"] = { gold = 50000, goldT = NOW, class = "MAGE", level = 20, seen = NOW - 3 * 86400 }')
ik("")
assert KM.IsShown("inventory") and ns.CurrentTab() == "overview" and not KM.errorShown, last(L)
assert L.eval("HASFONT('NET WORTH')") and L.eval("HASFONT('GOLD IN MAILBOXES')") and L.eval("HASFONT('NET WORTH, LAST 30 DAYS')")
crs = rows(ns.charTable)
assert [r.data.who for r in crs] == [ME, "Alt-Forever", "Warband"], [r.data.who for r in crs]
assert "not yet" in crs[1].cells.bank.text and "3 days ago" in crs[1].cells.seen.text
assert "1 bank not seen yet" in ns.overFooter.text, ns.overFooter.text
# the 30-day chart: stacked textures, gold under items
assert L.eval("TEXTURES ~= nil")
# sort characters by a column
click(ns.charTable.headers.gold)
assert [r.data.who for r in rows(ns.charTable)][0] == ME
# click a character: their items
click(crs[0])
assert ns.CurrentTab() == "items" and ns.GetFilter().who == ME and ns.tabs.buttons["items"].active
assert ids(ns) == [118, 2589, 2770, 6000], ids(ns)
assert ns.whoBtn.label.text.find("Jay") is not None, ns.whoBtn.label.text
# right-click: forget them (asks first)
click(ns.tabs.buttons["overview"])
alt = [r for r in rows(ns.charTable) if r.data.who == "Alt-Forever"][0]
click(alt, "RightButton")
assert L.eval("MENU_ITEM('Show their items') ~= nil")
L.execute("MENU_ITEM('Forget this character').fn()")
assert L.eval("POPUPS[#POPUPS].name") == "INVENTORYKING_FORGET" and L.eval("InventoryKingDB.chars['Alt-Forever']") is None
assert not KM.errorShown, last(L)
print("OVERVIEW OK")

# Items: sidebar categories and strategies, whose / where menus, search, sort, links, valued at
ns.ShowItems(L.table())
assert ns.CurrentTab() == "items" and ids(ns) == [118, 2589, 2770, 6000]
assert L.eval("SIDE('All items')") and L.eval("SIDE('Trade Goods')") and L.eval("SIDE('LEDGER STRATEGIES')")
click(L.eval("SIDE('Trade Goods')"))
assert ids(ns) == [2589, 2770] and L.eval("SIDE('Trade Goods')").active
assert L.eval("SIDE('Cloth')") and L.eval("SIDE('Metal & Stone')"), "subcategories open under it"
click(L.eval("SIDE('Metal & Stone')")); assert ids(ns) == [2770]
click(L.eval("SIDE('Trade Goods')")); click(L.eval("SIDE('Trade Goods')"))  # the open category again closes it
assert ns.GetFilter().cls is None and len(ids(ns)) == 4
click(L.eval("SIDE('Mining')")); assert ids(ns) == [2770] and ns.GetFilter().strategy == "Mining"
click(L.eval("SIDE('All items')"))
# whose: a menu of characters
click(ns.whoBtn)
assert L.eval("MENU_TITLE") == "Whose items" and L.eval("MENU[1].text") == "All characters"
L.execute("MENU[#MENU].fn()")  # the last one is the warband bank
assert ns.GetFilter().who == "Warband" and ids(ns) == [2770] and "Warband" in ns.whoBtn.label.text
click(ns.whoBtn); L.execute("MENU_ITEM('All characters').fn()")
# where
click(ns.whereBtn); L.execute("MENU_ITEM('On the auction house').fn()")
assert ids(ns) == [2589] and ns.whereBtn.label.text == "On the auction house"
click(ns.whereBtn); L.execute("MENU_ITEM('Everywhere').fn()")
# search by name or category
box = ns.searchBox
box.SetText(box, "potion"); box.RunScript(box, "OnTextChanged", True)
assert ids(ns) == [118]
box.SetText(box, ""); box.RunScript(box, "OnTextChanged", True)
assert len(ids(ns)) == 4
# sorted by worth (dearest first), then by any column
t = ns.CurrentItems()
assert t[1].item == 2589 and ns.itemTable.sortKey == "value"
click(ns.itemTable.headers.name)
t = ns.CurrentItems()
assert [t[i].name for i in range(1, 5)] == ["Copper Ore", "Green Sword", "Linen Cloth", "Minor Healing Potion"]
click(ns.itemTable.headers.total)
assert ns.CurrentItems()[1].item == 2770 and ns.itemTable.sortDesc
# a vendor price is marked
vrow = [r for r in rows(ns.itemTable) if r.data.item == 6000][0]
assert "(v)" in vrow.cells.each.text
# hover: who holds it; shift-click: a link in chat
orow = [r for r in rows(ns.itemTable) if r.data.item == 2770][0]
orow.RunScript(orow, "OnEnter")
assert any("Warband" in l and "bank 10" in l for l in tip(L)), tip(L)
L.execute("SHIFT = true"); click(orow); L.execute("SHIFT = false")
assert "Copper Ore" in L.eval("LINKED")
assert "items." in ns.itemFooter.text and "Worth" in ns.itemFooter.text, ns.itemFooter.text
# valued at
click(ns.priceBtn)
assert L.eval("MENU_TITLE") == "Value items at"
L.execute("MENU_ITEM('Lowest buyout').fn()")
assert L.eval("InventoryKingDB.ui.price") == "lowest" and ns.priceBtn.label.text == "Valued at: lowest buyout"
click(ns.priceBtn); L.execute("MENU_ITEM('No auction price: use the vendor price').fn()")
assert L.eval("InventoryKingDB.ui.vendor") is False
click(ns.priceBtn); L.execute("MENU_ITEM('Market price (Deep Scan)').fn(); MENU_ITEM('No auction price: use the vendor price').fn()")
assert L.eval("InventoryKingDB.ui.price") == "market" and L.eval("InventoryKingDB.ui.vendor") is True
assert not KM.errorShown, last(L)
print("ITEMS OK")

# Export: every item and every character, in a King Maker window
text, n = ns.ExportText()
lines = text.split("\n")
assert n == 4 and lines[0].startswith("item,item_id,category") and "character,level,gold,mailbox,items_worth,net_worth" in lines
assert any(l.startswith("Copper Ore,2770,Trade Goods,Metal & Stone,0,50,0,0,50,40,2000,lowest,") for l in lines), lines
ik("export")
win = L.eval("InventoryKingExport")
assert win and win.shown and win.template is None and win.box.text == text and "Exported 4 items" in last(L)
print("EXPORT OK")

# The crown, Home and Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Inventory") ~= nil')
KM.Toggle(False); L.execute('MENU_ITEM("Inventory").fn()'); assert KM.IsShown("inventory")
L.execute('KingMakerMinimapButton:RunScript("OnEnter")')
assert any(l.startswith("Net worth|") for l in tip(L)), tip(L)
KM.Show("home"); assert L.eval("HASFONT('NET WORTH')") and not KM.errorShown, last(L)
KM.OpenSettings("inventory"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
assert L.eval("HASFONT('How many you own, in item tooltips')")
fb = L.eval("(function() for _, f in ipairs(FRAMES) do if type(rawget(f, 'label')) == 'table' and f.label.text == 'Forget the warband bank' and f.SetLabel then return f end end end)()")
assert fb, "a Forget button per character"
click(fb)
assert L.eval("InventoryKingDB.stock.Warband") is None and KM.IsShown("settings") and not KM.errorShown, last(L)
print("SHELL OK")

# Slash commands
ik("status"); assert "net worth" in last(L) and "1 characters" in last(L), last(L)
L.execute('InventoryKingDB.chars["Bob-Forever"] = { gold = 1 }')
ik("forget Bob"); assert "forgot Bob-Forever" in last(L)
ik("forget Nobody"); assert "no character called Nobody-Forever" in last(L)
ik("button"); assert "crown" in last(L)
ik("help"); assert any("/ik forget" in str(o) for o in outputs(L))
ik(""); assert KM.IsShown("inventory"); ik(""); assert not KM.IsShown(), "/ik toggles the page"
assert not KM.errorShown, last(L)
print("SLASH OK")

# --- Mail King 1.1's stock and gold come over once ---------------------------------
MAIL_OLD = 'stock = { ["Alt-Forever"] = { bags = { [2589] = 7 }, bagsT = 1759000000 } }, gold = { ["Alt-Forever"] = { m = 50000, t = 1759000000 } }'

def imported(L):
    return (L.eval("InventoryKingDB.stock['Alt-Forever'] and InventoryKingDB.stock['Alt-Forever'].bags[2589]") == 7
            and L.eval("InventoryKingDB.chars['Alt-Forever'].gold") == 50000 and L.eval("InventoryKingDB.imported") is True
            and L.eval("MailKingDB.stock") is None and L.eval("MailKingDB.gold") is None)

# saved in King Maker's own file already
L, KM, ns = load(seed=PRICES + "; MailKingDB = { entries = {}, " + MAIL_OLD + " }")
assert imported(L) and any("brought over what Mail King knew about 1 characters" in str(o) for o in outputs(L)), outputs(L)
# only once: more stock turning up later is left alone
L.execute('MailKingDB.stock = { ["Cat-Forever"] = { bags = { [2589] = 1 } } }'); ns.InitDB(); ns.ImportMailKing()
assert L.eval("InventoryKingDB.stock['Cat-Forever']") is None
# moved in by Boot from the Mail_King (and Inventory_King) folders, after both modules' InitDB ran
OLD_INV = 'InventoryKingDB = { stock = { ["Jay-Forever"] = { bank = { [2770] = 3 }, bankT = 1759000000 } }, chars = { ["Jay-Forever"] = { gold = 10 } }, ui = { price = "lowest", button = true, buttonAngle = 5 } }'
L, KM, ns = load(stubs={"Inventory_King": OLD_INV, "Mail_King": "MailKingDB = { entries = {}, " + MAIL_OLD + " }"})
assert imported(L), (L.eval("InventoryKingDB.imported"), L.eval("MailKingDB.stock"))
assert L.eval("InventoryKingDB.stock[\"Jay-Forever\"].bank[2770]") == 3 and L.eval("InventoryKingDB.ui.price") == "lowest"
assert L.eval("InventoryKingDB.ui.button") is None and L.eval("MailKingDB.entries") is not None
# ...also when King Maker's file already had an (empty) MailKingDB from an earlier session
L, KM, ns = load(seed=PRICES + "; MailKingDB = { entries = {} }; KingMakerDB = { moved = {}, ui = {} }",
                 stubs={"Mail_King": "MailKingDB = { entries = {}, " + MAIL_OLD + " }"})
assert imported(L)
# ...and without the Mail module at all: the old table stays in place and is read at login
L, KM, ns = load(only=("Inventory",), seed=None, stubs={"Mail_King": "MailKingDB = { " + MAIL_OLD + " }"})
assert imported(L)
# nothing to bring over: not marked done, so a later move still counts
L, KM, ns = load()
assert L.eval("InventoryKingDB.imported") is None
print("MAIL IMPORT OK")

# InitDB is safe twice and keeps the table
L, KM, ns = load(seed=PRICES + '; InventoryKingDB = { stock = { ["Old-Forever"] = { bags = { [2589] = 2 } } }, ui = { button = false, buttonAngle = 9, tooltip = false } }')
L.execute("HELD = InventoryKingDB"); ns.InitDB()
assert L.eval("InventoryKingDB == HELD") and L.eval("InventoryKingDB.stock['Old-Forever'].bags[2589]") == 2
assert L.eval("InventoryKingDB.ui.button") is None and L.eval("InventoryKingDB.ui.tooltip") is False and L.eval("InventoryKingDB.history") is not None
# without Scanner: vendor prices, its own tooltip hook, the page still opens
L, KM, ns = load(only=("Inventory",), seed=None)
assert ns.Price(2589) == (10, "vendor")
_, lines = L.eval("HOVER(2589)")
assert any(str(l).startswith("Inventory King: 35 owned") for l in lines.values()), list(lines.values())
KM.Show("inventory"); ns.SelectTab("items"); assert not KM.errorShown and not L.eval("SIDE('LEDGER STRATEGIES')"), last(L)
print("INITDB OK")

print("inventory: ok")
