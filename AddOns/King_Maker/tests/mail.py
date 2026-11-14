# Mail (was Mail King), with Scanner and Inventory: posting, the mailbox (de-dup, dates), the ledger (periods,
# strategies, flips), buyers, not selling, export, the MailKing API, /mlk, commodity fixes, never reassigning
# Blizzard globals, and the Sales Ledger page. A second run without Inventory.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, ROOT

DAY = 86400
MODS = ["Scanner", "Inventory", "Mail"]

# Items, and the mailbox in the old suite's positional shape:
#   { subject, money, daysLeft, invoice = { type, item, who, bid, buyout, dep, cut, n }, att = { name, id, n } }
EXTRA = """
NOW = 1760000000
ITEM(2589, "Linen Cloth", { class = 7, subclass = 5 })
ITEM(2770, "Copper Ore", { class = 7, subclass = 7 })
ITEM(6000, "Green Sword", { class = 2, subclass = 0 })
ITEM(4306, "Silk Cloth", { class = 7, subclass = 5 })
ITEM(9999, "Wolf Fang", { class = 15, subclass = 0 })
function GetInboxHeaderInfo(i) local m = INBOX[i]; return nil, nil, "Auction House", m[1], m[2] or 0, 0, m[3] or 30 end
function GetInboxInvoiceInfo(i)
  local v = INBOX[i][4]; if not v then return nil end
  return v[1], v[2], v[3], v[4], v[5], v[6], v[7], 0, 0, v[8]
end
function GetInboxItem(i, n) local a = INBOX[i][5]; if a and (n or 1) == 1 then return a[1], a[2], 0, a[3] end end
function GetInboxItemLink(i, n) local a = INBOX[i][5]; if a then return LINK(a[2]) end end
function MAIL(box) INBOX = box; FIRE("MAIL_SHOW"); RUN_TIMERS() end
function HASFONT(s) for _, t in ipairs(FONTS) do if t.text and tostring(t.text):find(s, 1, true) then return true end end return false end
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
"""


def load(farm=False, only=MODS, **kw):
    extra = EXTRA + ("FarmKing = { IsDrop = function(id) return id == 9999 end }" if farm else "")
    L, KM = fresh(only=only, extra=extra, **kw)
    return L, KM, KM.mods.Mail


def entries(L): return list(L.eval("MailKingDB.entries").values())


def click(b, which="LeftButton"): b.RunScript(b, "OnClick", which)


def cur(ns):
    t = ns.CurrentList()
    return [t[i] for i in range(1, len(t) + 1)]


def rows(t): return [r for r in t.rows.values() if r.data and r.shown is not False]


L, KM, ns = load(True)
mlk = L.eval("SlashCmdList.MAILKING")
NOW = L.eval("NOW")
assert L.eval("MailKing.API_VERSION") == 1
assert L.eval("MailKingMinimapButton") is None and L.eval("MailKingFrame") is None, "no window or button of its own"
assert L.eval("MailKingDB.ui.button") is None and L.eval("MailKingDB.ui.period") == 7
assert ns.ParseSubject("Auction successful: Linen Cloth (20)") == ("sale", "Linen Cloth", 20)
assert ns.ParseSubject("Auction won: Green Sword")[0] == "buy"
assert ns.ParseSubject("Hello there") is None

# Posting: the deposit is noted, from the sell window's Post button (never C_AuctionHouse hooks)
L.execute("""
SELL.commodity = { item = { id = 2589 }, n = 20, duration = 1, unitPrice = 100 }
SELL.item = { item = { id = 6000 }, n = 1, duration = 1, buyout = 10000 }
POST_ITEM, POST_COMMODITY = C_AuctionHouse.PostItem, C_AuctionHouse.PostCommodity
FIRE("AUCTION_HOUSE_SHOW")
-- press Post: the window is read on the press, the post noted on the click (after the window clears)
local c = AuctionHouseFrame.CommoditiesSellFrame
c.PostButton:RunScript("OnMouseDown"); SELL.commodity.item = nil; c.PostButton:RunScript("OnClick", "LeftButton")
local i = AuctionHouseFrame.ItemSellFrame
i.PostButton:RunScript("OnMouseDown"); i.PostButton:RunScript("OnClick", "LeftButton")
-- a disabled button posts nothing
i.PostButton:Disable(); i.PostButton:RunScript("OnMouseDown"); i.PostButton:RunScript("OnClick", "LeftButton"); i.PostButton:Enable()
FIRE("AUCTION_HOUSE_SHOW") -- hooks only once
""")
assert L.eval("C_AuctionHouse.PostItem == POST_ITEM and C_AuctionHouse.PostCommodity == POST_COMMODITY"), "C_AuctionHouse untouched"
assert L.eval("#AuctionHouseFrame.CommoditiesSellFrame.PostButton.hooks.OnClick") == 1
assert L.eval("#AuctionHouseFrame.ItemSellFrame.PostButton.hooks.OnMouseDown") == 1
posts = list(L.eval("MailKingDB.posts").values())
assert len(posts) == 2 and posts[0].id == 2589 and posts[0].dep == 600 and posts[0].n == 20 and posts[1].dep == 500, len(posts)
assert posts[0].each == 100 and posts[1].each == 10000
print("POSTING OK")

# The mailbox: a sale (sold 2 days ago), a purchase, an expired auction, an outbid refund, a letter
box = """{
  { "Auction successful: Linen Cloth (20)", 1900, 28, { "seller", "Linen Cloth", "Bob", 2000, 2000, 600, 100, 20 } },
  { "Auction won: Green Sword", 0, 30, { "buyer", "Green Sword", "Ann", 5000, 5000, 0, 0, 1 }, { "Green Sword", 6000, 1 } },
  { "Auction expired: Linen Cloth (20)", 0, 30, nil, { "Linen Cloth", 2589, 20 } },
  { "Outbid on Silk Cloth", 300, 30 },
  { "Hi from a friend", 50, 3 },
}"""
L.execute(f"MAIL({box})")
es = entries(L)
assert len(es) == 3, [(e.k, e.name) for e in es]
sale, buy, exp = es
assert sale.k == "sale" and sale.g == 2000 and sale.cut == 100 and sale.who == "Bob" and sale.n == 20 and sale.item == 2589
assert sale.t == NOW - 2 * DAY and sale.c == "Jay-Forever"
assert buy.k == "buy" and buy.g == 5000 and buy.item == 6000 and buy.who == "Ann"
assert exp.k == "expired" and exp.dep == 600 and exp.item == 2589 and exp.each == 100  # what you asked, from the posting
assert len(list(L.eval("MailKingDB.posts").values())) == 1  # the expired one's posting is used up

# Opening the mailbox again changes nothing; neither does time passing with the mail still there
L.execute(f"MAIL({box})"); assert len(entries(L)) == 3
L.execute(f"NOW = NOW + 3600; INBOX = {box}; for _, m in ipairs(INBOX) do m[3] = m[3] - 3600 / 86400 end; FIRE('MAIL_INBOX_UPDATE'); RUN_TIMERS(); NOW = NOW - 3600")
assert len(entries(L)) == 3
# a second identical sale (a different mail) counts
L.execute('MAIL({ { "Auction successful: Linen Cloth (20)", 1900, 25, { "seller", "Linen Cloth", "Bob", 2000, 2000, 600, 100, 20 } } })')
assert len(entries(L)) == 4
# a sale whose money is still on its way isn't counted yet
L.execute('MAIL({ { "Auction successful: Linen Cloth", 0, 30, { "seller_temp_invoice", "Linen Cloth", "Bob", 2000, 2000, 0, 100, 1 } } })')
assert len(entries(L)) == 4
# leaving the mailbox says what was added
L.execute('FIRE("MAIL_CLOSED")'); assert "sold for" in last(L) and "bought for" in last(L) and "King Maker" in last(L), last(L)
print("MAILBOX OK")

# The ledger
s = ns.Summary(0)
assert s.sales == 2 and s.income == 3800 and s.cut == 200 and s.spent == 5000 and s.lost == 600 and s.profit == 3800 - 5000 - 600
strat = {r.key: r for r in s.strategies.values()}
assert strat["Cloth"].income == 3800 and strat["Cloth"].lost == 600 and strat["Purchases"].spent == 5000
# a period: only the last day holds no sales
assert ns.Summary(NOW - DAY).sales == 0
# flips: sell the sword you bought, and both land under Flips
L.execute('MAIL({ { "Auction successful: Green Sword", 9500, 30, { "seller", "Green Sword", "Cid", 10000, 10000, 500, 500, 1 } } })')
strat = {r.key: r for r in ns.Summary(0).strategies.values()}
assert strat["Flips"].spent == 5000 and strat["Flips"].income == 9500 and strat["Flips"].profit == 4500 and "Purchases" not in strat
# Farm King knows Wolf Fang drops from mobs
L.execute('MAIL({ { "Auction successful: Wolf Fang (5)", 500, 30, { "seller", "Wolf Fang", "Dee", 500, 500, 0, 25, 5 } } })')
assert ns.EntryStrategy(entries(L)[-1], L.table(), L.table()) == "Mob drops"
# your own choice wins, for every sale of that item, past ones too
ns.SetStrategy(2589, "Linen Cloth", "Tailoring farm")
strat = {r.key: r for r in ns.Summary(0).strategies.values()}
assert strat["Tailoring farm"].income == 3800 and "Cloth" not in strat
assert "Tailoring farm" in list(ns.Strategies().values())
ns.SetStrategy(2589, "Linen Cloth", None)
assert "Cloth" in {r.key for r in ns.Summary(0).strategies.values()}

# Days: today's flip and fang sale, two days ago the linen
days = list(ns.Daily(14).values())
assert len(days) == 14 and days[-1].income == 9500 + 475 and days[-3].income == 1900, [d.income for d in days]
print("LEDGER OK")

# The page: every tab draws, right-click sets a strategy
mlk("")
assert KM.IsShown("ledger") and KM.CurrentPage() == "ledger" and not KM.errorShown, last(L)
assert L.eval("HASFONT('PROFIT')") and L.eval("HASFONT('Best buyer: Bob')"), "Summary tiles and best buyer"
assert len(rows(ns.stratTable)) >= 3, "strategy table"
for t in ["summary", "sale", "buy", "expired", "items", "unsold", "buyers"]:
    ns.SelectTab(t)
    assert ns.CurrentTab() == t and not KM.errorShown, (t, last(L))
    if t != "summary":
        assert ns.tables[t].shown is not False and ns.tabs.buttons[t].active, t
# a strategy row opens its items
ns.SelectTab("summary")
r = [r for r in rows(ns.stratTable) if r.data.key == "Flips"][0]
click(r)
assert ns.CurrentTab() == "items" and all(e.strategy == "Flips" for e in cur(ns))
assert "Strategy: Flips" in ns.footer.text, ns.footer.text
ns.SelectTab("items")  # again: every strategy
assert len(cur(ns)) >= 3
# Items sort by any column; Sales lists newest first
ns.tables["items"].headers["name"].RunScript(ns.tables["items"].headers["name"], "OnClick")
names = [e.name for e in cur(ns)]
assert names == sorted(names), names
ns.SelectTab("sale")
ts = [e.t for e in cur(ns)]
assert ts == sorted(ts, reverse=True), ts
# right-click an item row: the strategy menu
row = rows(ns.tables["sale"])[0]
click(row, "RightButton")
assert L.eval("MENU_TITLE").startswith("Strategy for"), L.eval("MENU_TITLE")
ns.StrategyMenu(L.table(), 2589, "Linen Cloth")
menu = list(L.eval("MENU").values())
assert menu[0].text == "Automatic" and any(m.text == "Mining" for m in menu)
next(m for m in menu if m.text == "Mining").fn()
assert L.eval("MailKingDB.strategy[2589]") == "Mining"
L.execute('POPUP_INPUT = "Night farm"')
next(m for m in menu if m.text == "New strategy...").fn()
assert L.eval("MailKingDB.strategy[2589]") == "Night farm" and L.eval("MailKingDB.custom[2]") == "Night farm"
# periods and whose mail
ns.SelectTab("summary")
click(L.eval("BTN('All')")); assert L.eval("MailKingDB.ui.period") == 0 and L.eval("BTN('All')").active
click(L.eval("BTN('Today')")); assert L.eval("MailKingDB.ui.period") == 1
click(L.eval("BTN('7 days')")); assert L.eval("MailKingDB.ui.period") == 7
click(ns.charBtn); assert L.eval("MailKingDB.ui.mine") is True and ns.charBtn.label.text == "This character"
click(ns.charBtn); assert not L.eval("MailKingDB.ui.mine")
assert not KM.errorShown, last(L)
print("PAGE OK")

# Export
text, n = ns.ExportText()
lines = text.split("\n")
assert n == 6 and lines[0].startswith("date,kind,item") and len(lines) == 7 and "Linen Cloth" in lines[1]
mlk("export")
win = L.eval("MailKingExport")
assert win and win.shown and win.template is None and win.box.text == text, "export in a UI.Window"
assert "Exported 6 ledger lines" in last(L)

# Other addons
assert L.eval("MailKing.Summary(0)").sales == 4
assert len(list(L.eval("MailKing.GetEntries()").values())) == 6
assert L.eval("MailKing.StrategyOf(2770)") == "Mining"

# The crown, Home, Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Sales Ledger") ~= nil')
KM.Toggle(False); L.execute('MENU_ITEM("Sales Ledger").fn()'); assert KM.IsShown("ledger")
L.execute('KingMakerMinimapButton:RunScript("OnEnter")')
assert any(str(x).startswith("Profit, last 7 days|") for x in L.eval("GameTooltip.lines").values())
KM.Show("home"); assert L.eval("HASFONT('PROFIT, 7 DAYS')"), "Home tile"
KM.OpenSettings("mail"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
assert L.eval("HASFONT('Only this character')")
assert L.eval("StaticPopupDialogs.MAILKING_RESET ~= nil")

# Slash commands
mlk("status"); assert "6 mails recorded" in last(L), last(L)
mlk("button"); assert "crown" in last(L)
mlk("help"); assert any("/mlk reset yes" in str(o) for o in outputs(L))
mlk("reset"); assert len(entries(L)) == 6, "reset needs 'yes'"
mlk("reset yes"); assert len(entries(L)) == 0 and "Ledger cleared" in last(L)
mlk(""); assert KM.IsShown("ledger"); mlk(""); assert not KM.IsShown(), "/mlk toggles the page"
print("API AND SLASH OK")

# Commodity invoices can give 0 for how many sold: the subject's count is used
L, KM, ns = load()
L.execute('MAIL({ { "Auction successful: Silk Cloth (20)", 1900, 30, { "seller", "Silk Cloth", "Bob", 2000, 2000, 0, 100, 0 } } })')
assert entries(L)[0].n == 20 and ns.Summary(0)["items"][1].units == 20
# and old entries saved with 0 count as 1
L.execute('MailKingDB.entries[1].n = 0'); ns.Prune(); assert entries(L)[0].n == 1
# the module never reassigns Blizzard's globals (that taints them and gets the addon blocked)
src = "".join(open(os.path.join(ROOT, "Modules", "Mail", f), encoding="utf-8").read() for f in ("Core.lua", "Mail.lua", "Ledger.lua", "UI.lua"))
for g in ("StaticPopupDialogs", "SlashCmdList", "UISpecialFrames"):
    assert (g + " =") not in src and (g + "=") not in src, g
assert "hooksecurefunc(" not in src

# Without an invoice a sale counts what arrived
L, KM, ns = load()
L.execute('MAIL({ { "Auction successful: Copper Ore (10)", 950, 30 } })')
e = entries(L)[0]; assert e.g == 950 and e.cut == 0 and e.n == 10 and e.item == 2770
assert ns.Summary(0).strategies[1].key == "Mining"
print("COMMODITY OK")

# Buyers: who buys from you, how often, what
L, KM, ns = load()
def sale(item, n, gold, who, days=30):
    return f'{{ "Auction successful: {item} ({n})", {gold}, {days}, {{ "seller", "{item}", "{who}", {gold}, {gold}, 0, 0, {n} }} }}'
L.execute("MAIL({" + ",".join([
    sale("Linen Cloth", 20, 2000, "Bob", 30), sale("Linen Cloth", 20, 2100, "Bob", 29), sale("Silk Cloth", 10, 5000, "Bob", 28),
    sale("Linen Cloth", 5, 500, "Cid", 27), sale("Copper Ore", 10, 900, "Dee", 26),
    '{ "Auction successful: Copper Ore (5)", 450, 25 }',  # no invoice: no buyer's name
    '{ "Auction won: Green Sword", 0, 30, { "buyer", "Green Sword", "Ann", 5000, 5000, 0, 0, 1 }, { "Green Sword", 6000, 1 } }',
]) + "})")
b = ns.Buyers(0)
brows = list(b.rows.values())
assert [r.who for r in brows] == ["Bob", "Dee", "Cid"] and b.unknown == 1 and b.mails == 5  # ties: who paid more
bob = brows[0]
assert bob.mails == 3 and bob.units == 50 and bob.gold == 9100 and bob.regular and abs(bob.share - 0.6) < 1e-9
assert bob.fav.name == "Silk Cloth" and bob.kinds == 2 and not brows[1].regular
assert [i.name for i in ns.BuyerItems(bob).values()] == ["Silk Cloth", "Linen Cloth"]
sellers = list(ns.Buyers(0, None, "buy").rows.values())
assert len(sellers) == 1 and sellers[0].who == "Ann" and sellers[0].gold == 5000
assert L.eval("MailKing.Buyers(0)")[1].who == "Bob"
# the Buyers page; clicking a buyer shows only their sales
L.execute('SlashCmdList.MAILKING("")'); ns.db.ui.period = 0; ns.SelectTab("buyers")
assert ns.sideBtn.shown is not False and "with no name" in ns.footer.text, ns.footer.text
brow = [r for r in rows(ns.tables["buyers"]) if r.data.who == "Bob"][0]
brow.RunScript(brow, "OnEnter")
assert any("Silk Cloth" in str(x) for x in L.eval("GameTooltip.lines").values())
click(brow)
assert ns.CurrentTab() == "sale" and all(e.who == "Bob" for e in cur(ns)) and len(cur(ns)) == 3
assert L.eval("HASFONT('Buyer: Bob')")
srow = rows(ns.tables["sale"])[0]; srow.RunScript(srow, "OnEnter")
assert any("has bought from you 3 times" in str(x) for x in L.eval("GameTooltip.lines").values())
ns.SelectTab("sale")  # again: everyone
assert len(cur(ns)) == 6
# Sellers instead of buyers
ns.SelectTab("buyers"); click(ns.sideBtn)
assert ns.sideBtn.label.text == "Sellers" and [r.who for r in cur(ns)] == ["Ann"]
click(ns.sideBtn)
ns.db.ui.period = 7
ns.SelectTab("summary")
assert L.eval("HASFONT('Best buyer: Bob, 3 sales (60%)')")
assert not KM.errorShown, last(L)
print("BUYERS OK")

# Not selling: what came back, what you asked, against the market
L, KM, ns = load()
L.execute("""ScannerKingDB.prices[2589] = { p = 90, m = 100, t = NOW }; ScannerKingDB.prices[2770] = { p = 45, m = 50, t = NOW }
MailKingDB.posts = { { id = 2589, name = "Linen Cloth", n = 20, dep = 600, each = 150, t = NOW },
  { id = 2770, name = "Copper Ore", n = 10, dep = 100, each = 50, t = NOW } }""")
L.execute("MAIL({" + ",".join([
    '{ "Auction expired: Linen Cloth (20)", 0, 30, nil, { "Linen Cloth", 2589, 20 } }',
    '{ "Auction expired: Copper Ore (10)", 0, 29, nil, { "Copper Ore", 2770, 10 } }',
    sale("Copper Ore", 10, 500, "Bob", 28),
    '{ "Auction expired: Silk Cloth (5)", 0, 27, nil, { "Silk Cloth", 4306, 5 } }',
]) + "})")
u = {r.name: r for r in ns.NotSelling(0).values()}
assert set(u) == {"Linen Cloth", "Copper Ore", "Silk Cloth"}
lin = u["Linen Cloth"]
assert lin.listEach == 150 and lin.market == 100 and abs(lin.vsMarket - 0.5) < 1e-9 and lin.why == "over" and lin.lost == 600
cop = u["Copper Ore"]
assert cop.through == 0.5 and cop.why is None and cop.lastSale is not None and cop.soldEach == 50
assert u["Silk Cloth"].why == "never" and u["Silk Cloth"].listEach is None
assert list(ns.NotSelling(0).values())[0].name == "Linen Cloth"  # most deposits lost first
# with the Inventory module: how many you still have (the mailbox read above holds the returned items)
L.execute('InventoryKingDB.stock["Alt-Forever"] = { bags = { [2589] = 40 } }')
held = {r.name: r for r in ns.NotSelling(0).values()}["Linen Cloth"].held
assert held == 40 + 20, held
assert L.eval("MailKing.Stock(2589)") == 60
L.execute('SlashCmdList.MAILKING("")'); ns.SelectTab("unsold")
assert L.eval("HASFONT('came back unsold')")
urow = [r for r in rows(ns.tables["unsold"]) if r.data.name == "Linen Cloth"][0]
assert "over market" in urow.cells.why.text and "+50%" in urow.cells.why.text
urow.RunScript(urow, "OnEnter")
assert any("over the market" in str(x) for x in L.eval("GameTooltip.lines").values())
ns.SelectTab("summary")
assert L.eval("HASFONT('Net worth:')"), "net worth on the Summary with Inventory"
assert not KM.errorShown, last(L)
print("NOT SELLING OK")

# Without Inventory the summary and Stock() still work
L, KM, ns = load(only=["Scanner", "Mail"])
assert L.eval("InventoryKing") is None and L.eval("MailKing.Stock(2589)") == 0
L.execute('MAIL({ ' + sale("Linen Cloth", 20, 2000, "Bob", 30) + ' })')
L.execute('SlashCmdList.MAILKING("")')
for t in ["summary", "sale", "unsold", "buyers"]:
    ns.SelectTab(t)
assert not KM.errorShown and not L.eval("HASFONT('Net worth:')"), last(L)
assert L.eval("MailKingDB.stock") is None
# ...and without Scanner either
L, KM, ns = load(only=["Mail"])
L.execute('MAIL({ ' + sale("Linen Cloth", 20, 2000, "Bob", 30) + ' }); SlashCmdList.MAILKING("")')
ns.SelectTab("items"); assert not KM.errorShown, last(L)
print("WITHOUT INVENTORY OK")

# InitDB is safe twice and keeps the table; old minimap keys go; moved in from a 1.x Mail_King folder
L, KM, ns = load(seed="MailKingDB = { entries = { { t = 1759000000, k = 'sale', name = 'Linen Cloth', n = 0, g = 100, cut = 5, c = 'Jay-Forever' } }, ui = { button = false, buttonAngle = 10, period = 30 } }")
L.execute("HELD = MailKingDB"); ns.InitDB()
assert L.eval("MailKingDB == HELD") and len(entries(L)) == 1 and entries(L)[0].n == 1, "Prune fixed the 0 count"
assert L.eval("MailKingDB.ui.button") is None and L.eval("MailKingDB.ui.period") == 30 and L.eval("MailKingDB.seen") is not None
OLD = "MailKingDB = { entries = { { t = 1759500000, k = 'sale', name = 'Copper Ore', n = 10, g = 950, cut = 50, who = 'Bob', c = 'Jay-Forever' } }, strategy = { [2770] = 'Ore run' }, custom = { 'Ore run' }, ui = { period = 0 } }"
L, KM, ns = load(stubs={"Mail_King": OLD})
assert len(entries(L)) == 1 and L.eval("MailKingDB.strategy[2770]") == "Ore run" and L.eval("MailKingDB.ui.period") == 0
assert L.eval("MailKingDB.posts") is not None and L.eval("KingMakerDB.moved.MailKingDB") is not None
assert L.eval("MailKing.StrategyOf(2770)") == "Ore run" and ns.Summary(0).profit == 900
print("INITDB OK")

# My characters beside the mailbox: same realm and faction only, highest level first, click -> To: box, Send tab
ALTS = """
InventoryKingDB = { chars = {
  ["Jay-Forever"] = { class = "WARRIOR", level = 42, faction = "Alliance", gold = 100000 },
  ["Bank-Forever"] = { class = "MAGE", level = 5, faction = "Alliance", gold = 2500000 },
  ["Tank-Forever"] = { class = "PALADIN", level = 60, faction = "Alliance" },
  ["Orc-Forever"] = { class = "ROGUE", level = 30, faction = "Horde" },
  ["Away-Elsewhere"] = { class = "PRIEST", level = 20, faction = "Alliance" } } }
RestedKingDB = { chars = { ["Fresh-Forever"] = { name = "Fresh", realm = "Forever", class = "DRUID", level = 1 },
  ["Bank-Forever"] = { name = "Bank", realm = "Forever", class = "MAGE", level = 6 } } }
MailFrame = CreateFrame("Frame", "MailFrame")
SendMailFrame = CreateFrame("Frame", "SendMailFrame"); SendMailFrame:Hide()
SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox")
SendMailSubjectEditBox = CreateFrame("EditBox", "SendMailSubjectEditBox")
function SendMailSubjectEditBox:SetFocus() FOCUSED = "subject" end
MailFrameTab2 = CreateFrame("Button", "MailFrameTab2")
MailFrameTab2:SetScript("OnClick", function() SendMailFrame:Show() end)
"""
L, KM, ns = load(only=["Inventory", "Rested", "Mail"], seed=ALTS)
assert L.eval("MailKingDB.ui.alts") is True
got = ns.Alts()
names = [got[i].name for i in range(1, len(got) + 1)]
assert names == ["Tank", "Bank", "Fresh"], names
assert got[2].level == 6 and got[2].gold == 2500000
L.execute('MailFrame:Show(); FIRE("MAIL_SHOW"); RUN_TIMERS()')
panel = L.eval("MailKingAltsPanel")
assert panel and panel.shown is True and panel.point[1] == "TOPLEFT" and panel.point[3] == "TOPRIGHT"
assert L.eval("HASFONT('My characters')") and not KM.errorShown, last(L)
row = [f for f in L.eval("FRAMES").values() if f.alt is not None and f.alt.name == "Bank"][0]
click(row)
assert L.eval("SendMailNameEditBox:GetText()") == "Bank" and L.eval("SendMailFrame.shown") is True
assert L.eval("FOCUSED") == "subject" and row.sel.shown is True
# the setting and /mlk alts hide and show it
mlk = L.eval("SlashCmdList.MAILKING")
mlk("alts off"); assert L.eval("MailKingDB.ui.alts") is False and panel.shown is False
mlk("alts"); assert L.eval("MailKingDB.ui.alts") is True and panel.shown is True
L.execute('MailFrame:Hide(); FIRE("MAIL_CLOSED")'); assert panel.shown is False
mlk("alts off"); L.execute('MailFrame:Show(); FIRE("MAIL_SHOW")'); assert panel.shown is False
# no other characters yet: a hint instead of an empty box
L, KM, ns = load(only=["Mail"], seed="MailFrame = CreateFrame('Frame', 'MailFrame')")
L.execute('FIRE("MAIL_SHOW")')
assert len(ns.Alts()) == 0 and L.eval("HASFONT('Log in to your other characters')") and not KM.errorShown, last(L)
# Forever names: alts known by full name show it; an alt saved by first name gets its surname from the guild roster
L, KM, ns = load(only=["Inventory", "Rested", "Mail"], seed=ALTS + """
PLAYER.surname = "Stone"
InventoryKingDB.chars["Jay-Forever"] = nil
InventoryKingDB.chars["Tank Shield-Forever"] = InventoryKingDB.chars["Tank-Forever"]; InventoryKingDB.chars["Tank-Forever"] = nil
GUILD_ROSTER = { { name = "Bank Vault-Forever", class = "MAGE" }, { name = "Fresh Leaf-Forever", class = "PRIEST" } }
""")
got = ns.Alts(); names = [got[i].name for i in range(1, len(got) + 1)]
assert names == ["Tank Shield", "Bank Vault", "Fresh"], names
assert "Jay" not in names and "Jay Stone" not in names
L.execute('MailFrame:Show(); FIRE("MAIL_SHOW")')
row = [f for f in L.eval("FRAMES").values() if f.alt is not None and f.alt.name == "Tank Shield"][0]
click(row); assert L.eval("SendMailNameEditBox:GetText()") == "Tank Shield"
# it closes with the mail window, even when MAIL_CLOSED never comes
panel = L.eval("MailKingAltsPanel"); assert panel.shown is True
L.execute("MailFrame:Hide()"); assert panel.shown is False
L.execute("MailFrame:Show()"); assert panel.shown is True
L.execute("MailFrame.shown = false; RUN_ONUPDATE(1)"); assert panel.shown is False, "the per-frame check"
# Surnames learned from mail: sending to "Bank Vault" names the first-name-only alt Bank; an inbox sender too
L, KM, ns = load(only=["Inventory", "Rested", "Mail"], seed=ALTS)
L.execute('MailFrame:Show(); FIRE("MAIL_SHOW")')
L.execute('SendMailMailButton = CreateFrame("Button", "SendMailMailButton"); FIRE("MAIL_SHOW")')
L.execute('SendMailNameEditBox:SetText("Bank Vault"); SendMailMailButton:Click(); FIRE("MAIL_SEND_SUCCESS")')
assert L.eval("MailKingDB.altNames['Bank-Forever']") == "Bank Vault"
assert "Bank Vault" in [a.name for a in ns.Alts().values()]
assert not ns.LearnAltName("Somebody Else") and not ns.LearnAltName("Tank"), "no alt called that / no surname"
L.execute('GetInboxHeaderInfo = function(i) return nil, nil, INBOX[i].sender, "hi", 0, 0, 30 end; GetInboxNumItems = function() return #INBOX end')
L.execute('INBOX = { { sender = "Fresh Start" } }; FIRE("MAIL_INBOX_UPDATE")')
assert L.eval("MailKingDB.altNames['Fresh-Forever']") == "Fresh Start"
print("ALTS OK")

print("mail: ok")
