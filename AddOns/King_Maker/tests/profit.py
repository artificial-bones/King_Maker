# Profit & Loss (King Maker 2.7), with Scanner, Inventory and Mail (a run adds Shopping, one has no Inventory): load and
# register, day one from the Sales Ledger, FIFO / LIFO and the farmed-items setting (the design's worked example),
# the per-buy ledger, cost unknown, deposits, opening stock and the startup shortfall, reconciliation (provisional
# closures, reclaim, reopen, final after 30 days, deferral while the mailbox is open), the stale auction count, loot
# lots, vendor purchases and sales, folding, the page, the integrations (Sales Ledger P&L column and tiles, mailbox
# line, Shopping, item tooltip, Home, crown), running without Inventory, and API copies.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page, ROOT

DAY = 86400
NOW = 1794787200 + 12 * 3600                 # 16 Nov 2026, noon UTC
def nov(d, h=12): return NOW - (16 - d) * DAY + (h - 12) * 3600

POOL = "Forever-Alliance"
ME = "Jay-Forever"

EXTRA = """
NOW = %d
ITEM(2589, "Linen Cloth", { quality = 1, class = 7, subclass = 5, sell = 13, stack = 20 })
ITEM(2770, "Copper Ore", { quality = 1, class = 7, subclass = 7, sell = 5, stack = 20 })
ITEM(4306, "Silk Cloth", { quality = 1, class = 7, subclass = 5, sell = 150, stack = 20 })
ITEM(13468, "Black Lotus", { quality = 2, class = 7, subclass = 9, sell = 1000, stack = 20 })
ITEM(4234, "Heavy Leather", { quality = 1, class = 7, subclass = 6, sell = 60, stack = 20 })
ITEM(159, "Refreshing Spring Water", { quality = 1, class = 0, subclass = 5, sell = 1, stack = 20 })
ITEM(4865, "Ruined Pelt", { quality = 0, class = 15, sell = 5 })
ITEM(5000, "Soulbound Ring", { quality = 3, class = 4, bind = 1, sell = 900 })
ITEM(5001, "Quest Token", { quality = 1, class = 12 })
function GetInboxHeaderInfo(i) local m = INBOX[i]; return nil, nil, "Auction House", m[1], m[2] or 0, 0, m[3] or 30 end
function GetInboxInvoiceInfo(i)
  local v = INBOX[i][4]; if not v then return nil end
  return v[1], v[2], v[3], v[4], v[5], v[6], v[7], 0, 0, v[8]
end
function GetInboxItem(i, n) local a = INBOX[i][5]; if a and (n or 1) == 1 then return a[1], a[2], 0, a[3] end end
function GetInboxItemLink(i, n) local a = INBOX[i][5]; if a then return LINK(a[2]) end end
function MAIL(box) INBOX = box; FIRE("MAIL_SHOW"); RUN_TIMERS() end
function HASFONT(s) for _, t in ipairs(FONTS) do if t.text and tostring(t.text):find(s, 1, true) then return true end end return false end
function BAG(id, n, slot) BAGS[0][slot or 1] = n and n > 0 and { id = id, count = n } or nil end
function PRICE(id, m) ScannerKingDB = ScannerKingDB or {}; ScannerKingDB.prices = ScannerKingDB.prices or {}; ScannerKingDB.prices[id] = { p = m, m = m, t = NOW } end
""" % NOW

MODS = ["Scanner", "Inventory", "Mail", "Profit"]


def load(only=MODS, seed=None, extra="", **kw):
    L, KM = fresh(only=only, seed=seed, extra=EXTRA + extra, **kw)
    return L, KM, KM.mods.Profit


def tbl(L, d): return L.table_from(d)


def add(L, ns, item, k, **f):
    if "who" not in f and k in ("b", "l", "m", "s", "n", "d"): f["who"] = ME
    return ns.Add(POOL, item, k, tbl(L, f))


def vals(t): return [t[i] for i in range(1, len(t) + 1)] if t else []


def events(L, item, pool=POOL):
    t = L.eval("ProfitKingDB.pools[%r] and ProfitKingDB.pools[%r].items[%d] and ProfitKingDB.pools[%r].items[%d].e" % (pool, pool, item, pool, item))
    return vals(t)


def kinds(L, item): return [e.split(":")[2] for e in events(L, item)]


def tiptext(L): return [str(x) for x in L.eval("GameTooltip.lines").values()]


def rows(t): return [r for r in t.rows.values() if r.data and r.shown is not False]


def click(b, which="LeftButton"): b.RunScript(b, "OnClick", which)


# --- 1. Load and register ------------------------------------------------------------------------------------------
L, KM, ns = load()
assert L.eval("ProfitKing.API_VERSION") == 1
assert L.eval("ProfitKingDB.version") == 2 and L.eval("ProfitKingDB.start") == NOW, "day one ran at login"
s = L.eval("ProfitKingDB.settings")
assert s.method == "fifo" and s.basis == "paid" and s.tooltip is True and s.keepDays == 60
assert ns.PoolOf(ME) == POOL and ns.MyPool() == POOL
assert L.eval("ProfitKingFrame") is None and L.eval("ProfitKingMinimapButton") is None, "no window or button of its own"
L.execute('SlashCmdList.PROFITKING("help")')
assert any("/pnl reset yes" in str(o) for o in outputs(L)) and any("/pnl fifo | lifo" in str(o) for o in outputs(L))
L.execute('SlashCmdList.KINGMAKER("profit")')
assert KM.IsShown("profit") and KM.CurrentPage() == "profit" and not KM.errorShown, last(L)
assert KM.pages.profit.group == "gold" and KM.pages.profit.order == 5
gold = [p.id for p in KM.groups.gold.pages.values()]
assert gold[0] == "profit", gold
L.execute('SLASH("/profitloss")'); assert not KM.IsShown("profit"), "/profitloss toggles it"
L.execute('SLASH("/pnl")'); assert KM.IsShown("profit")
open_every_page(L, KM)
assert not KM.errorShown, last(L)
KM.OpenSettings("profit"); assert KM.IsShown("settings") and L.eval("HASFONT('Sales use up')") and not KM.errorShown
assert L.eval("StaticPopupDialogs.KINGMAKER_PROFIT_RESET ~= nil")
src = "".join(open(os.path.join(ROOT, "Modules", "Profit", f), encoding="utf-8").read()
              for f in ("Core.lua", "Journal.lua", "Replay.lua", "Recon.lua", "Page.lua"))
assert "COMBAT_LOG" not in src and "hooksecurefunc" not in src and "C_AuctionHouse" not in src
for g in ("StaticPopupDialogs", "SlashCmdList", "UISpecialFrames"):
    assert (g + " =") not in src and (g + "=") not in src, g
toc = open(os.path.join(ROOT, "King_Maker.toc"), encoding="utf-8").read()
assert "ProfitKingDB" in toc.split("SavedVariables:")[1].split("\n")[0]
print("LOAD OK")

# --- 2. Day one from the Sales Ledger -------------------------------------------------------------------------------
SEED = """
MailKingDB = { dedupe = 1, names = { ["Linen Cloth"] = 2589 }, entries = {
  { t = %d, k = "buy", item = 2589, name = "Linen Cloth", n = 20, g = 2000, c = "Jay-Forever", who = "Ann" },
  { t = %d, k = "sale", name = "Linen Cloth", n = 10, g = 1500, cut = 75, c = "Jay-Forever" },
  { t = %d, k = "sale", name = "Linen Cloth", n = 10, g = 1500, cut = 75, c = "Jay-Forever", who = "Bob" },
  { t = %d, k = "expired", item = 2770, name = "Copper Ore", n = 10, dep = 120, c = "Jay-Forever" },
  { t = %d, k = "expired", item = 2770, name = "Copper Ore", n = 10, c = "Jay-Forever" },
  { t = %d, k = "sale", name = "Mystery Thing", n = 1, g = 900, cut = 45, c = "Jay-Forever" },
} }
""" % (nov(3), nov(10), nov(10) + 3, nov(11), nov(12), nov(12))
L, KM, ns = load(seed=SEED, only=["Scanner", "Mail", "Profit"])
imp = L.eval("ProfitKingDB.import")
assert imp.mails == 6 and imp.copies == 1 and imp.unknown == 1 and imp.sales == 1 and imp.buys == 1, (imp.mails, imp.copies, imp.unknown)
assert kinds(L, 2589) == ["b", "s"], kinds(L, 2589)
assert kinds(L, 2770) == ["d"], "the deposit, not the expiry without one"
assert events(L, 2589)[1].split(":")[4] == str(1500 - 75), "a sale's c is what it brought after the cut"
assert "couldn't be matched to an item" in " ".join(str(o) for o in outputs(L))
before = (events(L, 2589), events(L, 2770))
again = ns.ImportLedger()
assert again.added == 0 and again.dup == 3, (again.added, again.dup)
assert (events(L, 2589), events(L, 2770)) == before, "a second import changes nothing"
ns.OnEntry("ENTRY", L.eval("MailKing.GetEntries()")[1])
assert (events(L, 2589), events(L, 2770)) == before, "nor does a mail the journal already has"
ns.FirstRun(); assert (events(L, 2589), events(L, 2770)) == before, "day one runs once"
assert ns.Summary(0).sales == 1 and ns.Summary(0).deposits == 120
print("DAY ONE OK")

# --- 3. FIFO / LIFO, the worked example (Linen Cloth; market now 1s 60c, 1s 52c after the cut) ---------------------
WORKED = """PRICE(2589, 160)"""
def worked():
    L, KM, ns = load(only=["Scanner", "Mail", "Profit"], extra=WORKED)
    add(L, ns, 2589, "b", t=nov(3), q=20, c=2000, v=1900)       # A
    add(L, ns, 2589, "l", t=nov(5), q=30, c=0, v=2850, s="mob")  # B
    add(L, ns, 2589, "b", t=nov(8), q=20, c=3000, v=2850)       # C
    add(L, ns, 2589, "s", t=nov(10), q=40, c=5700)              # gross 6000, cut 300
    return L, KM, ns
L, KM, ns = worked()
S = ns.Summary(0)
assert S.realized == 3700 and S.cost == 3000 and S.worth == 4560 and S.ifSold == 1560, (S.realized, S.cost, S.worth, S.ifSold)
ns.SetMethod("lifo")
S = ns.Summary(0)
assert S.realized == 2700 and S.cost == 2000 and S.ifSold == 2560, (S.realized, S.cost)
assert "newest stock first" in last(L)
ns.SetMethod("fifo")
assert ns.Summary(0).realized == 3700, "back again restores it"
ns.SetBasis("market")
S = ns.Summary(0)
assert S.realized == 1800 and S.cost == 3950 and S.ifSold == 610, (S.realized, S.cost)
ns.SetBasis("paid")
L.execute('SlashCmdList.PROFITKING("lifo")'); assert L.eval("ProfitKingDB.settings.method") == "lifo"
L.execute('SlashCmdList.PROFITKING("farmed value")'); assert L.eval("ProfitKingDB.settings.basis") == "market"
L.execute('SlashCmdList.PROFITKING("fifo"); SlashCmdList.PROFITKING("farmed free")')
print("FIFO LIFO OK")

# --- 4. Per buy -----------------------------------------------------------------------------------------------------
buys = {b.t: b for b in vals(ns.Buys(0))}
A, B, Cc = buys[nov(3)], buys[nov(5)], buys[nov(8)]
assert A.status == "closed" and A.left == 0 and A.realized == 850 and A.sold == 20
held = vals(ns.Trades(0))[0].held
assert abs(held - (20 * 7 * DAY + 20 * 5 * DAY) / 40) < 1, held
assert B.status == "part" and B.left == 10 and B.realized == 2850 and B.how == "Farmed"
assert Cc.status == "open" and Cc.left == 20 and Cc.realized is None and Cc.openPL == 20 * 152 - 3000
x = vals(ns.Trades(0))[0]
assert x.pl == 3700
assert x["from"] == "2 lots" and x.costEach == 50 and x.q == 40
print("PER BUY OK")

# --- 5. Cost unknown ------------------------------------------------------------------------------------------------
add(L, ns, 2770, "b", t=nov(9), q=40, c=4000, v=4000)
add(L, ns, 2770, "s", t=nov(11), q=50, c=7500)
t = [x for x in vals(ns.Trades(0)) if x.item == 2770][0]
assert t.matchedQ == 40 and t.unQ == 10 and t.unP == 1500 and t.pl == 6000 - 4000, (t.unQ, t.unP, t.pl)
S = ns.Summary(0)
assert S.unknownQ == 10 and S.unknownP == 1500 and S.realized == 3700 + 2000
print("COST UNKNOWN OK")

# --- 6. Deposits ----------------------------------------------------------------------------------------------------
add(L, ns, 2770, "d", t=nov(14), q=0, c=250, s="x")
assert ns.Summary(0).realized == 5700 - 250 and ns.Summary(0).deposits == 250
assert ns.Summary(nov(13)).realized == -250 and ns.Summary(nov(13)).sales == 0, "in its own period"
assert ns.Summary(nov(15)).deposits == 0
print("DEPOSITS OK")

# --- 7. Opening stock and the startup shortfall ---------------------------------------------------------------------
SEED7 = """
MailKingDB = { dedupe = 1, entries = {
  { t = %d, k = "buy", item = 4306, name = "Silk Cloth", n = 20, g = 10000, c = "Jay-Forever" },
} }
""" % nov(1)
L, KM, ns = load(seed=SEED7, extra="PRICE(2589, 100); PRICE(4306, 600); BAG(2589, 25, 1); BAG(4306, 5, 2)")
o = [e for e in events(L, 2589)]
assert len(o) == 1 and o[0].split(":")[2] == "o" and o[0].split(":")[3] == "25", o
assert o[0].split(":")[4] == o[0].split(":")[5] == str(25 * 95) and o[0].endswith(":start"), o
ev = events(L, 4306)
assert [e.split(":")[2] for e in ev] == ["b", "g"] and ev[1].split(":")[3] == "15" and ev[1].endswith("startup"), ev
S = ns.Summary(0)
assert S.goneStartup == 7500 and S.gonePending == 0 and S.goneFinal == 0, (S.goneStartup, S.gonePending)
assert ns.Summary(nov(1) - DAY).goneStartup == 0, "never in a period"
nots = vals(ns.NotSold(0))
assert len(nots) == 1 and nots[0].status == "before tracking"
assert not vals(ns.NotSold(nov(2)))
h = ns.Holding(POOL, 4306)
assert h.held == 5 and h.cost == 2500 and h.untraced == 0
seen = L.eval("ProfitKingDB.pools[%r].seen[%r]" % (POOL, ME))
assert seen and seen.bags, "the bags read on day one count as seen"
print("OPENING OK")

# --- 8. Reconciliation ----------------------------------------------------------------------------------------------
L.execute("BAG(2589, 15, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 2589) == ["o", "g"] and events(L, 2589)[1].split(":")[3] == "10", events(L, 2589)
g = vals(ns.NotSold(nov(16) - DAY))
assert g[0].state == "pending" and g[0].daysLeft == 30
assert ns.Summary(0).gonePending == 10 * 95
# a sale mail dated after it: the closure was really that sale
L.execute("""NOW = NOW + 60; MAIL({ { "Auction successful: Linen Cloth (6)", 1140, 30, { "seller", "Linen Cloth", "Bob", 1200, 1200, 0, 60, 6 } } }); FIRE("MAIL_CLOSED"); RUN_TIMERS()""")
assert kinds(L, 2589)[:3] == ["o", "g", "s"], kinds(L, 2589)
x = [t for t in vals(ns.Trades(0)) if t.item == 2589][0]
assert x.matchedQ == 6 and x.unQ == 0 and x.pl == 1140 - 6 * 95, (x.matchedQ, x.pl)
assert ns.Summary(0).gonePending == 4 * 95, "the rest still pending"
# a later rise reopens what's left
L.execute("BAG(2589, 17, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 2589)[-1] == "r" and events(L, 2589)[-1].split(":")[3] == "2", events(L, 2589)
assert ns.OpenQ(ns.Replay(POOL, 2589)) == 17 and ns.Summary(0).gonePending == 2 * 95
# nothing runs while the mailbox is open; it runs after it closes
L.execute("FIRE('MAIL_SHOW'); RUN_TIMERS(); BAG(2589, 12, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 2589)[-1] == "r", "deferred while the mailbox is open"
assert ns.Pending() > 0
L.execute("FIRE('MAIL_CLOSED'); RUN_TIMERS()")
assert kinds(L, 2589)[-1] == "g" and events(L, 2589)[-1].split(":")[3] == "5", events(L, 2589)
# and the auction house the same
L.execute("FIRE('AUCTION_HOUSE_SHOW'); BAG(2589, 10, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
n = len(events(L, 2589))
L.execute("FIRE('AUCTION_HOUSE_CLOSED'); FIRE('AUCTION_HOUSE_CLOSED'); RUN_TIMERS()")
assert len(events(L, 2589)) == n + 1 and kinds(L, 2589)[-1] == "g"
# 31 days on, everything left is final
L.execute("NOW = NOW + 31 * 86400")
st = {r.state for r in vals(ns.NotSold(0))}
assert "pending" not in st and "final" in st, st
assert ns.Summary(0).gonePending == 0 and ns.Summary(0).goneFinal > 0
print("RECONCILE OK")

# --- 9. Stale auction house count -----------------------------------------------------------------------------------
L, KM, ns = load(extra="PRICE(2770, 50)")
L.globals().KMT = KM
L.execute("""
local s = KMT.mods.Inventory.db.stock["Jay-Forever"]
s.ah, s.ahT = { [2770] = 20 }, NOW - 7200
""")
assert ns.Owned(POOL, 2770) == 20
add(L, ns, 2770, "b", t=NOW - 10 * DAY, q=20, c=1000, v=950)
L.execute("""MAIL({ { "Auction successful: Copper Ore (20)", 1900, 30 - 3600 / 86400, { "seller", "Copper Ore", "Bob", 2000, 2000, 0, 100, 20 } } }); FIRE("MAIL_CLOSED"); RUN_TIMERS()""")
e = L.eval("MailKingDB.entries[#MailKingDB.entries]")
assert e.t > NOW - 7200, "the sale is dated after the auction house was read"
assert ns.Owned(POOL, 2770) == 0, "the sold units come off the stale auction count"
ns.Reconcile(POOL, 2770)
assert kinds(L, 2770) == ["b", "s"], kinds(L, 2770)
assert ns.Holding(POOL, 2770).untraced == 0
print("STALE AH OK")

# --- 10. Loot -------------------------------------------------------------------------------------------------------
L, KM, ns = load(extra="PRICE(2589, 100)")
L.execute("""OPEN_LOOT({ { link = LINK(2589), qty = 3 }, { link = LINK(4865), qty = 1, quality = 0 }, { link = LINK(5000), qty = 1 },
  { link = LINK(5001), qty = 1, quest = true } }); LOOT_ALL(); RUN_TIMERS()""")
ev = events(L, 2589)
assert len(ev) == 1 and ev[0].split(":")[2] == "l" and ev[0].split(":")[3] == "3" and ev[0].split(":")[4] == "0", ev
assert ev[0].split(":")[5] == str(3 * 95), "worth when looted, from the Scanner"
assert not events(L, 4865) and not events(L, 5000) and not events(L, 5001), "grey, soulbound and quest items make no lot"
L.execute("""OPEN_LOOT({ { link = LINK(2589), qty = 2 } }); LOOT_ALL(); RUN_TIMERS()""")
ev = events(L, 2589)
assert len(ev) == 1 and ev[0].split(":")[3] == "5" and ev[0].split(":")[5] == str(5 * 95), "same day: the lot grows"
# an item that hasn't loaded: its worth is filled in later
L.execute("""OPEN_LOOT({ { link = "|cffffffff|Hitem:7777::::::::60:::::|h[Strange Dust]|h|r", qty = 4 } }); LOOT_ALL(); RUN_TIMERS()""")
ev = events(L, 7777)
assert len(ev) == 1 and ev[0].split(":")[5] == "" and L.eval("#ProfitKingDB.pend") == 1, ev
L.execute("""ITEM(7777, "Strange Dust", { quality = 1, class = 7, subclass = 12, sell = 10 }); PRICE(7777, 200); FIRE("GET_ITEM_INFO_RECEIVED", 7777); RUN_TIMERS()""")
ev = events(L, 7777)
assert ev[0].split(":")[5] == str(4 * 190) and L.eval("#ProfitKingDB.pend") == 0, ev
print("LOOT OK")

# --- 11. Vendors ----------------------------------------------------------------------------------------------------
L, KM, ns = load(extra="PRICE(2589, 100); BAG(2589, 20, 1); MONEY = 100000; MERCHANT = { { id = 159, name = 'Refreshing Spring Water', price = 25, n = 1 } }")
assert kinds(L, 2589) == ["o"]
L.execute("FIRE('MERCHANT_SHOW'); BAG(2589, 15, 1); MONEY = MONEY + 5 * 13; FIRE('BAG_UPDATE_DELAYED'); FIRE('PLAYER_MONEY'); RUN_TIMERS()")
ev = events(L, 2589)
assert kinds(L, 2589) == ["o", "n"] and ev[1].split(":")[3] == "5" and ev[1].split(":")[4] == "65", ev
L.execute("BAG(159, 3, 2); MONEY = MONEY - 75; FIRE('BAG_UPDATE_DELAYED'); FIRE('PLAYER_MONEY'); RUN_TIMERS()")
ev = events(L, 159)
assert len(ev) == 1 and ev[0].split(":")[2] == "m" and ev[0].split(":")[3] == "3" and ev[0].split(":")[4] == "75", ev
# buying the same stack back removes the sale
L.execute("BAG(2589, 20, 1); MONEY = MONEY - 65; FIRE('BAG_UPDATE_DELAYED'); FIRE('PLAYER_MONEY'); RUN_TIMERS()")
assert kinds(L, 2589) == ["o"], kinds(L, 2589)
# a repair alone records nothing
n = sum(len(events(L, i)) for i in (2589, 159))
L.execute("REPAIR = 500; MONEY = MONEY - 500; FIRE('PLAYER_MONEY'); FIRE('UPDATE_INVENTORY_DURABILITY'); RUN_TIMERS()")
assert sum(len(events(L, i)) for i in (2589, 159)) == n
# money that doesn't match the vendor price: left to the counts
L.execute("BAG(2589, 18, 1); MONEY = MONEY + 999; FIRE('BAG_UPDATE_DELAYED'); FIRE('PLAYER_MONEY'); RUN_TIMERS()")
assert kinds(L, 2589) == ["o"]
L.execute("FIRE('MERCHANT_CLOSED'); FIRE('MERCHANT_CLOSED'); RUN_TIMERS()")
assert kinds(L, 2589) == ["o", "g"], "after the merchant closes, the counts close the 2 that went"
print("VENDOR OK")

# --- 12. Folding ----------------------------------------------------------------------------------------------------
L, KM, ns = load(only=["Scanner", "Mail", "Profit"], extra="PRICE(2589, 160); PRICE(2770, 50)")
add(L, ns, 2589, "b", t=NOW - 100 * DAY, q=20, c=2000, v=1900)
add(L, ns, 2589, "l", t=NOW - 95 * DAY, q=30, c=0, v=2850, s="mob")
add(L, ns, 2589, "s", t=NOW - 90 * DAY, q=40, c=5700)
add(L, ns, 2589, "d", t=NOW - 85 * DAY, q=0, c=100)
add(L, ns, 2589, "g", t=NOW - 80 * DAY, q=4)
add(L, ns, 2589, "b", t=NOW - 10 * DAY, q=10, c=1500, v=1500)
add(L, ns, 2589, "s", t=NOW - 5 * DAY, q=12, c=1800)
def snapshot():
    r = ns.Replay(POOL, 2589)
    lots = sorted((l.id, l.left) for l in vals(r.lots) if l.left > 0)
    S = ns.Summary(0)
    return lots, S.realized, S.goneFinal, S.cost
before = snapshot()
ns.SetBasis("market"); market_before = ns.Summary(0).realized; ns.SetBasis("paid")
assert ns.FoldAll() == 1
L.execute("RUN_TIMERS()")
rec = L.eval("ProfitKingDB.pools[%r].items[2589]" % POOL)
assert len(vals(rec.e)) == 2 and rec.ck and len(vals(rec.ck.lots)) == 1, (len(vals(rec.e)),)
after = snapshot()
assert after == before, (before, after)
months = list(rec.m.values())
assert len(months) >= 1 and all(len(m.split(":")) == 11 for m in months), months
allm = {}
for m in months:
    for i, v in enumerate(m.split(":")): allm[i] = allm.get(i, 0) + int(v)
assert allm[3] == 2000 and allm[4] == 2000 + 1900, "both bases kept (paid, market)"
pm = vals(L.eval("(function() local t = {} for k, v in pairs(ProfitKingDB.pools[%r].months) do t[#t+1] = v end return t end)()" % POOL))
assert pm, "the pool's months"
ns.SetBasis("market"); market_after = ns.Summary(0).realized; ns.SetBasis("paid")
assert abs(market_after - market_before) < 1, ("folded months follow the farmed setting", market_before, market_after)
print("FOLDING OK")

# --- 13. The page ---------------------------------------------------------------------------------------------------
L, KM, ns = worked()
add(L, ns, 2770, "b", t=nov(9), q=40, c=4000, v=4000)
add(L, ns, 2770, "s", t=nov(11), q=50, c=7500)
add(L, ns, 13468, "b", t=nov(7), q=3, c=9060, v=9000)           # Black Lotus at 3g 02s, worth less now: underwater
add(L, ns, 2589, "d", t=nov(12), q=0, c=100, s="x")
L.execute("PRICE(13468, 3000); PRICE(2770, 120)")
L.execute("RUN_TIMERS()")
KM.Show("profit")
P = ns.P
ns.SelectTab("overview")
assert not KM.errorShown, last(L)
rv = P.tiles.realized.value.text
assert rv.startswith("+") and P.tiles.realized.value.color[1] == L.eval("KingMaker.UI.C.good[1]"), rv
assert P.tiles.under.value.text == "1 item" and P.tiles.under.value.color[1] == L.eval("KingMaker.UI.C.bad[1]")
assert "unit" in P.tiles.unknown.sub.text
for key in ("realized", "ifsold", "stock", "under", "gone", "unknown"):
    t = P.tiles[key]
    L.execute("GameTooltip.lines = {}"); t.RunScript(t, "OnEnter")
    assert len(tiptext(L)) >= 3, key
L.execute("GameTooltip.lines = {}"); P.tiles.realized.RunScript(P.tiles.realized, "OnEnter")
assert any("Deposits lost" in x for x in tiptext(L)) and any("Everything, with sales of unknown cost" in x for x in tiptext(L))
bars = [P.chart.bars[i] for i in range(1, (P.chart.bars.used or 0) + 1)]
assert len(bars) >= 3, len(bars)
cols = {round(b.color[1], 2) for b in bars}
assert len(cols) >= 2, "per-point colours: green days and the red deposit day"
hb = [r for r in P.hbars.rows.values() if r.shown is not False]
assert [r.data.label for r in hb] == ["Auction buys", "Farmed", "Crafted", "Opening stock", "Vendor, trades", "Deposits lost"]
assert hb[1].value.text.find("+") >= 0, "farmed units sold free: all profit"
irows = rows(P.itemTable)
assert {r.data.item for r in irows} >= {2589, 2770, 13468}
lotus = [r for r in irows if r.data.item == 13468][0]
assert "UNDER" in lotus.cells.flag.text and lotus.pnlTint.shown, "underwater: the flag and the red tint"
lotus.RunScript(lotus, "OnEnter")
assert any("List at" in x for x in tiptext(L)), "break-even"
click(hb[1])
assert ns.db.ui.tab == "trades" and all(any(p.lot.k == "l" for p in vals(r.data.parts)) for r in rows(P.saleTable)), "click: those trades"
assert "From: Farmed" in P.footer.text
click(P.sub.buttons["sale"])   # By sale again: every source
assert "From:" not in P.footer.text
# Trades by sale and its filters
ns.db.ui.sub, ns.db.ui.filter = "sale", "all"; KM.Refresh("profit")
srows = rows(P.saleTable)
assert len(srows) == 2 and not KM.errorShown
lin = [r for r in srows if r.data.item == 2589][0]
assert lin.cells.pl.text.find("+") >= 0 and lin.cells["from"].text == "2 lots" and lin.cells.q.text == "40"
lin.RunScript(lin, "OnEnter")
assert any("of 20 bought" in x for x in tiptext(L)) and any("farmed" in x for x in tiptext(L))
ns.db.ui.filter = "unknown"; KM.Refresh("profit")
assert [r.data.item for r in rows(P.saleTable)] == [2770]
ns.db.ui.filter = "losses"; KM.Refresh("profit")
assert rows(P.saleTable) == [] and "No sales" in P.saleTable.empty.text
# by buy
ns.db.ui.sub, ns.db.ui.filter = "buy", "all"; KM.Refresh("profit")
brows = rows(P.buyTable)
st = {(r.data.item, r.data.t): r.cells.status.text for r in brows}
assert "CLOSED" in st[(2589, nov(3))] and "PART" in st[(2589, nov(5))] and "OPEN" in st[(2589, nov(8))]
assert P.filter.buttons["unknown"].shown is False, "cost unknown is for sales"
# not sold
add(L, ns, 2770, "b", t=nov(13), q=5, c=500, v=500)
add(L, ns, 2770, "g", t=nov(14), q=5)
ns.db.ui.filter = "gone"; KM.Refresh("profit")
grows = rows(P.goneTable)
assert len(grows) == 1 and "pending" in grows[0].cells.status.text and "days left" in grows[0].cells.status.text
ns.db.ui.filter = "all"
# holdings
ns.SelectTab("holdings")
hrows = rows(P.holdTable)
lotus = [r for r in hrows if r.data.item == 13468][0]
assert "UNDER" in lotus.cells.flag.text and lotus.pnlTint.shown and lotus.pnlEdge.shown
assert P.periods.shown is False, "holdings are now: no period"
assert len([p for p in vals(P.ageBar.parts) if p[1] > 0]) >= 1
assert "held" in P.hText.text and "under" in P.hText.text
L.execute("GameTooltip.lines = {}"); lotus.RunScript(lotus, "OnEnter")
assert any("You hold" in x for x in tiptext(L))
assert "Counts are off" in P.footer.text, "this run has no Inventory"
# empty state
L2, KM2, ns2 = load(only=["Scanner", "Mail", "Profit"])
KM2.Show("profit")
assert "Nothing to match yet" in ns2.P.itemTable.empty.text, ns2.P.itemTable.empty.text
assert not KM2.errorShown
print("PAGE OK")

# Holdings with Inventory: untraced stock, the footer and Adopt
L, KM, ns = load(extra="PRICE(2589, 100); PRICE(4234, 300)")
L.execute("BAG(4234, 12, 3); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert not events(L, 4234), "bags seen on day one: what turns up later is untraced, not a lot"
L.globals().KMT = KM
L.execute("""local s = KMT.mods.Inventory.db.stock["Alt-Forever"] or {}; KMT.mods.Inventory.db.stock["Alt-Forever"] = s
s.bags, s.bagsT = { [2589] = 30 }, NOW
KMT.mods.Inventory.db.chars["Alt-Forever"] = { faction = "Alliance" }
KMT.mods.Profit.ClearPools()
ProfitKingDB.pools["Forever-Alliance"].seen["Alt-Forever"] = { bags = NOW }""")
KM.Show("profit"); ns.SelectTab("holdings")
P = ns.P
assert "42 untraced items" in P.footer.text and P.adopt.shown is not False, P.footer.text   # 30 linen + 12 leather
r = [r for r in rows(P.holdTable) if r.data.item == 2589][0]
assert r.data.held == 0 and r.data.untraced == 30 and "+30" in r.cells.flag.text
click(P.adopt)
assert kinds(L, 2589)[-1] == "o" and events(L, 2589)[-1].endswith(":adopt") and "counted 42 untraced" in last(L)
KM.Refresh("profit")
assert "Every item you hold has a lot" in P.footer.text
# a first sighting: a character's bank seen for the first time
L.execute("""KMT.mods.Inventory.db.stock["Jay-Forever"].bank, KMT.mods.Inventory.db.stock["Jay-Forever"].bankT = { [4306] = 7 }, NOW
KMT.mods.Profit.OnStock(); RUN_TIMERS()""")
assert events(L, 4306) and events(L, 4306)[0].endswith(":bank"), events(L, 4306)
print("HOLDINGS OK")

# --- 14. Integrations -----------------------------------------------------------------------------------------------
L, KM, ns = load(extra="PRICE(2589, 160); PRICE(2770, 50)")
L.execute("""MAIL({ { "Auction won: Linen Cloth (20)", 0, 30 - 5, { "buyer", "Linen Cloth", "Ann", 2000, 2000, 0, 0, 20 }, { "Linen Cloth", 2589, 20 } } }); FIRE("MAIL_CLOSED"); RUN_TIMERS()""")
assert kinds(L, 2589) == ["b"], kinds(L, 2589)
L.execute("BAG(2589, 20, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 2589) == ["b"], "the purchase arrived: no surplus, no closure"
L.execute("""MAIL({ { "Auction successful: Linen Cloth (10)", 1900, 30 - 1, { "seller", "Linen Cloth", "Bob", 2000, 2000, 0, 100, 10 } },
  { "Auction successful: Copper Ore (5)", 475, 30 - 1, { "seller", "Copper Ore", "Cid", 500, 500, 0, 25, 5 } } })""")
L.execute('FIRE("MAIL_CLOSED"); RUN_TIMERS()')
line = last(L)
assert "sold for" in line and "(P&L " in line, line
assert "(P&L +9" in line, line                  # 1900 - 1000 = +9s; the copper ore had no cost
# the Sales tab's P&L column
L.execute('SlashCmdList.MAILKING("")')
mail = KM.mods.Mail
mail.SelectTab("sale")
srows = rows(mail.tables["sale"])
cells = {r.data.name: r.cells.pl.text for r in srows}
assert cells["Linen Cloth"].find("+") >= 0 and "no cost" in cells["Copper Ore"], cells
srow = [r for r in srows if r.data.name == "Linen Cloth"][0]
srow.RunScript(srow, "OnEnter")
assert any(x.startswith("P&L|") for x in tiptext(L)) and any("of 20 bought" in x for x in tiptext(L)), tiptext(L)
# an entry P&L never saw: "-"
L.execute('table.insert(MailKingDB.entries, { t = NOW - 200 * 86400, k = "sale", item = 2589, name = "Linen Cloth", n = 1, g = 100, cut = 5, c = "Jay-Forever" })')
mail.SelectTab("sale")
old = [r for r in rows(mail.tables["sale"]) if r.data.t == NOW - 200 * DAY]
assert not old or "-" in old[0].cells.pl.text
# the Summary's P&L line and the tiles now from P&L's holdings
mail.SelectTab("summary")
assert mail.pnlBtn.shown is not False and "Realized P&L, period" in mail.pnlBtn.label.text
bw = mail.BoughtWorth(0, None)
assert bw.fromPnL and bw.held == 1000 and bw.worth == 10 * 152, (bw.held, bw.worth)
click(mail.pnlBtn); assert KM.IsShown("profit")
# the item tooltip line: with stock, and not without
first_line, lines = L.eval("HOVER(2589)")
assert any(str(x).startswith("Your cost|") for x in lines.values()), list(lines.values())
first_line, lines = L.eval("HOVER(4306)")
assert not any(str(x).startswith("Your cost|") for x in lines.values())
L.execute("ProfitKingDB.settings.tooltip = false")
first_line, lines = L.eval("HOVER(2589)")
assert not any(str(x).startswith("Your cost|") for x in lines.values()), "the setting turns it off"
L.execute("ProfitKingDB.settings.tooltip = true")
# Home: P&L's tile replaces the cash one; the crown line
KM.Show("home")
assert L.eval("HASFONT('P&L, 7 DAYS')") and not L.eval("HASFONT('PROFIT, 7 DAYS')"), "Home's profit tile is realized P&L"
L.execute('KingMakerMinimapButton:RunScript("OnEnter")')
tl = tiptext(L)
assert any(x.startswith("P&L, last 7 days|") for x in tl) and not any(x.startswith("Profit, last 7 days|") for x in tl), tl
assert not KM.errorShown, last(L)
print("INTEGRATIONS OK")

# --- 15. Without Inventory ------------------------------------------------------------------------------------------
L, KM, ns = load(only=["Scanner", "Mail", "Profit"], extra="PRICE(2589, 100)")
add(L, ns, 2589, "b", t=nov(10), q=5, c=500, v=475)
assert ns.Owned(POOL, 2589) is None
ns.Reconcile(POOL, 2589); assert kinds(L, 2589) == ["b"], "no reconciliation"
KM.Show("profit")
for tab in ("overview", "trades", "holdings"):
    ns.SelectTab(tab); assert not KM.errorShown, (tab, last(L))
    if tab != "trades":     # Trades' footer counts its rows
        assert "Counts are off: what you hold isn't checked" in ns.P.footer.text, (tab, ns.P.footer.text)
print("WITHOUT INVENTORY OK")

# --- 16. API copies -------------------------------------------------------------------------------------------------
L, KM, ns = worked()
b = L.eval("ProfitKing.Basis(2589)")
assert b.held == 30 and b.cost == 3000
b.held = 999
assert L.eval("ProfitKing.Basis(2589)").held == 30
s = L.eval("ProfitKing.Summary(0)")
assert s.realized == 3700
s.realized = 0
assert L.eval("ProfitKing.Summary(0)").realized == 3700
tr = L.eval("ProfitKing.Trades(0)")
assert tr[1].pl == 3700 and tr[1].parts[1].q > 0
tr[1].parts[1].q = -5
assert L.eval("ProfitKing.Trades(0)")[1].parts[1].q > 0
lots = L.eval("ProfitKing.Lots(2589)")
assert len(vals(lots)) == 3 and lots[1].kind == "b" and lots[1].left == 20
lots[1].left = 0
assert L.eval("ProfitKing.Lots(2589)")[1].left == 20
assert L.eval("ProfitKing.IsTracking()") is True
L.globals().GOT = L.table()
L.execute('ProfitKing.RegisterCallback("Test", function(ev) GOT[#GOT + 1] = ev end)')
add(L, ns, 2589, "b", t=nov(15), q=1, c=100, v=95)
L.execute("RUN_TIMERS()")
assert L.eval("GOT[1]") == "CHANGED"
# /pnl status, item, export, adopt, reset
L.execute('SlashCmdList.PROFITKING("status")'); assert "realized, last 7 days" in last(L), last(L)
L.execute('SlashCmdList.PROFITKING("item " .. LINK(2589))'); assert any("Linen Cloth" in str(o) and "held" in str(o) for o in outputs(L))
L.execute('SlashCmdList.PROFITKING("export")')
win = L.eval("KingMakerProfitExport")
assert win and win.shown and "trades" in win.box.text and "lots" in win.box.text and "Exported" in last(L)
L.execute('SlashCmdList.PROFITKING("reset")'); assert L.eval("ProfitKingDB.pools[%r].items[2589]" % POOL) is not None, "reset needs yes"
L.execute('SlashCmdList.PROFITKING("reset yes")')
assert L.eval("ProfitKingDB.pools[%r]" % POOL) is None or L.eval("ProfitKingDB.pools[%r].items[2589]" % POOL) is None
assert L.eval("ProfitKingDB.start") is not None, "day one ran again"
assert not KM.errorShown, last(L)
print("API OK")

# ===================================================================================================================
# King Maker 2.8: crafting, disenchanting, mail you send, quest rewards, trades, "listed at", Inventory's columns, an old
# journal, folding a craft, and the fallbacks when a signal is missing.
# ===================================================================================================================
EXTRA28 = """
ITEM(1251, "Linen Bandage", { quality = 1, class = 0, subclass = 7, sell = 10, stack = 20 })
ITEM(2320, "Coarse Thread", { quality = 1, class = 7, subclass = 5, sell = 10, stack = 20 })
ITEM(2318, "Light Leather", { quality = 1, class = 7, subclass = 6, sell = 15, stack = 20 })
ITEM(2302, "Handstitched Leather Boots", { quality = 1, class = 4, subclass = 2, sell = 30 })
ITEM(5002, "Bound Bracers", { quality = 2, class = 4, subclass = 1, bind = 1, sell = 50 })
ITEM(6000, "Green Sword", { quality = 2, class = 2, subclass = 7, sell = 300 })
ITEM(10940, "Strange Dust", { quality = 1, class = 7, subclass = 12, sell = 10, stack = 20 })
ITEM(10938, "Lesser Magic Essence", { quality = 2, class = 7, subclass = 12, sell = 20, stack = 20 })
SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox")
SendMailMailButton = CreateFrame("Button", "SendMailMailButton")
function SEND_MAIL(to, items, ok)
  SENDMAIL = { to = to, items = items }
  SendMailNameEditBox:SetText(to)
  SendMailMailButton:RunScript("OnMouseDown"); SendMailMailButton:Click()
  FIRE(ok == false and "MAIL_FAILED" or "MAIL_SEND_SUCCESS")
end
function CAST(spell, n) for _ = 1, n or 1 do FIRE("UNIT_SPELLCAST_START", "player", "c", spell); FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "c", spell) end end
function SETTLE() FIRE("BAG_UPDATE_DELAYED"); ADVANCE(2); RUN_TIMERS() end
"""


def load28(only=MODS, extra="", **kw):
    return load(only=only, extra=EXTRA28 + extra, **kw)


def ev(L, item, i=-1): return events(L, item)[i].split(":")


# --- 17. Crafting: the product costs what its mats cost (FIFO and LIFO), vendor reagents, bound products -----------
L, KM, ns = load28(extra="""PRICE(2589, 100); PRICE(1251, 1000)
TRADESKILL = { name = "First Aid", recipes = { [3275] = { output = 1251, reagents = { { 2589, 2 }, { 2320, 1 } } },
  [9999] = { output = 5002, reagents = { { 4306, 2 } } } } }""")
L.execute("BAG(2589, 20, 1); BAG(2320, 5, 2); BAG(4306, 4, 4); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
add(L, ns, 2589, "b", t=nov(3), q=10, c=1000, v=950)       # A: 1s each
add(L, ns, 2589, "b", t=nov(5), q=10, c=2000, v=950)       # B: 2s each
add(L, ns, 2320, "m", t=nov(5), q=5, c=250, v=50)          # thread from a vendor, 50c each
add(L, ns, 4306, "b", t=nov(6), q=4, c=2000, v=2000)
L.execute("RUN_TIMERS()")
assert "g" not in kinds(L, 2589) + kinds(L, 2320), "lots match the bags"
# "Create all": five casts, then the bags settle once
L.execute("CAST(3275, 5); BAG(2589, 10, 1); BAG(2320, 0, 2); BAG(1251, 5, 3); SETTLE()")
assert kinds(L, 2589) == ["b", "b", "u"] and kinds(L, 2320) == ["m", "u"] and kinds(L, 1251) == ["k"], (kinds(L, 2589), kinds(L, 1251))
k = ev(L, 1251)
assert k[3] == "5" and k[7] == k[0] + "/2589,2320", k
assert ev(L, 2589)[7] == k[0] and ev(L, 2589)[3] == "10", "the mats' use links to the product"
h = ns.Holding(POOL, 1251)
assert h.held == 5 and h.cost == 1000 + 250 and h.untraced == 0, (h.held, h.cost, h.untraced)
assert ns.Holding(POOL, 2589).cost == 2000 and ns.Holding(POOL, 2589).held == 10, "FIFO: the oldest linen went in"
S = ns.Summary(0)
assert S.gonePending == 0 and S.goneFinal == 0, "crafting isn't used or gone"
ns.SetMethod("lifo")
assert ns.Holding(POOL, 1251).cost == 2000 + 250, "LIFO: the newest linen went in"
assert ns.Holding(POOL, 2589).cost == 1000
ns.SetMethod("fifo")
add(L, ns, 1251, "s", t=NOW + 60, q=5, c=5000)
x = [t for t in vals(ns.Trades(0)) if t.item == 1251][0]
assert x.pl == 5000 - 1250 and x.unQ == 0 and x["from"].startswith("crafted"), (x.pl, x["from"])
b = [b for b in vals(ns.Buys(0)) if b.item == 1251][0]
assert b.how == "Crafted" and b.cost == 1250
a = [b for b in vals(ns.Buys(0)) if b.item == 2589 and b.t == nov(3)][0]
assert a.made == 10 and a.used == 0 and a.status == "closed", (a.made, a.used)
# a product that binds: the mats' cost is used up, final at once
L.execute("CAST(9999); BAG(4306, 2, 4); BAG(5002, 1, 6); BAGS[0][6].bound = true; SETTLE()")
assert kinds(L, 4306) == ["b", "u"] and ev(L, 4306)[7] == "used" and not events(L, 5002), events(L, 4306)
S = ns.Summary(0)
assert S.goneFinal == 1000 and S.gonePending == 0 and S.goneUsed == 1000, (S.goneFinal, S.gonePending)
row = [r for r in vals(ns.NotSold(0)) if r.item == 4306][0]
assert row.status == "used in a craft" and row.state == "final" and row.cost == 1000
KM.Show("profit"); ns.db.ui.tab, ns.db.ui.sub, ns.db.ui.filter = "trades", "buy", "all"; KM.Refresh("profit")
crow = [r for r in rows(ns.P.buyTable) if r.data.item == 1251][0]
assert crow.cells.how.text == "Crafted", crow.cells.how.text
L.execute("GameTooltip.lines = {}"); crow.RunScript(crow, "OnEnter")
assert any("what the mats that went into it cost" in x for x in tiptext(L)), tiptext(L)
arow = [r for r in rows(ns.P.buyTable) if r.data.item == 2589 and r.data.t == nov(3)][0]
L.execute("GameTooltip.lines = {}"); arow.RunScript(arow, "OnEnter")
assert any("crafted with" in x for x in tiptext(L)), tiptext(L)
ns.db.ui.filter = "gone"; KM.Refresh("profit")
assert any("used in a craft" in r.cells.status.text for r in rows(ns.P.goneTable))
assert not KM.errorShown, last(L)
print("CRAFT OK")

# vendor reagents with no lot count at what a vendor charges (Market's price), the recipe from Market's data
L, KM, ns = load28(only=["Scanner", "Market", "Inventory", "Mail", "Profit"], extra="PRICE(2318, 105); PRICE(2302, 2000)")
L.execute("BAG(2318, 4, 1); BAG(2320, 2, 2); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
add(L, ns, 2318, "b", t=nov(8), q=4, c=400, v=400)
assert KM.mods.Market.Recipe(2149).item == 2302
L.execute("CAST(2149, 2); BAG(2318, 0, 1); BAG(2320, 0, 2); BAG(2302, 2, 3); SETTLE()")
assert kinds(L, 2302) == ["k"] and kinds(L, 2320) == ["u"], (kinds(L, 2302), kinds(L, 2320))
assert ev(L, 2320)[5] == str(2 * 40), "untraced thread: 4 x its vendor sell price, Market's vendor price"
assert ns.Holding(POOL, 2302).cost == 400 + 80, ns.Holding(POOL, 2302).cost
print("VENDOR REAGENTS OK")

# --- 18. Disenchanting: the item's cost split over the mats by what they're worth --------------------------------
L, KM, ns = load28(extra="PRICE(10940, 200); PRICE(10938, 400); PRICE(6000, 4000)")
L.execute("BAG(6000, 1, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
add(L, ns, 6000, "b", t=nov(10), q=1, c=3000, v=3800)
L.execute("RUN_TIMERS(); CAST(13262); BAG(6000, 0, 1); BAG(10940, 2, 2); BAG(10938, 1, 3)")
L.execute("OPEN_LOOT({ { link = LINK(10940), qty = 2 }, { link = LINK(10938), qty = 1 } }, {}, true); LOOT_ALL(); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 6000) == ["b", "e"] and kinds(L, 10940) == ["k"] and kinds(L, 10938) == ["k"], (kinds(L, 6000), kinds(L, 10940))
e = ev(L, 6000)
assert ev(L, 10940)[7] == e[0] + "/6000/5000" and ev(L, 10938)[7] == e[0] + "/6000/5000", (ev(L, 10940), ev(L, 10938))
assert ns.Holding(POOL, 10940).cost == 1500 and ns.Holding(POOL, 10938).cost == 1500
assert ns.Summary(0).goneFinal == 0 and ns.Summary(0).gonePending == 0
b = [b for b in vals(ns.Buys(0)) if b.item == 10940][0]
assert b.how == "DE", b.how
print("DISENCHANT OK")

# --- 19. Mail you send: to an alt it's in transit (no gap), to someone else it's gone ------------------------------
L, KM, ns = load28(extra="PRICE(2589, 100); PRICE(2770, 50)")
L.globals().KMT = KM
L.execute("""KMT.mods.Inventory.db.chars["Ann-Forever"] = { faction = "Alliance" }
KMT.mods.Inventory.db.stock["Ann-Forever"] = { bags = {}, bank = {}, mail = {}, ah = {}, bagsT = NOW - 86400, mailT = NOW - 86400 }
BAG(2589, 20, 1); BAG(2770, 5, 2); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()""")
add(L, ns, 2589, "b", t=nov(10), q=20, c=2000, v=1900)
add(L, ns, 2770, "b", t=nov(10), q=5, c=500, v=250)
L.execute("RUN_TIMERS(); FIRE('MAIL_SHOW'); RUN_TIMERS()")
L.execute("SEND_MAIL('Ann', { { 2589, 20 } }); BAG(2589, 0, 1); FIRE('BAG_UPDATE_DELAYED')")
L.execute("SEND_MAIL('Bob Stranger', { { 2770, 5 } }); BAG(2770, 0, 2); FIRE('BAG_UPDATE_DELAYED')")
L.execute("SEND_MAIL('Ann', { { 4306, 1 } }, false)")
L.execute("FIRE('MAIL_CLOSED'); ADVANCE(3); RUN_TIMERS()")
assert kinds(L, 2589) == ["b", "y"] and ev(L, 2589)[7] == "alt/Ann-Forever", events(L, 2589)
assert ns.InTransit(POOL, 2589) == 20 and ns.Owned(POOL, 2589) == 20 and ns.OpenQ(ns.Replay(POOL, 2589)) == 20
assert not events(L, 4306), "a mail that failed records nothing"
assert kinds(L, 2770) == ["b", "y"] and ev(L, 2770)[7] == "to/Bob Stranger", events(L, 2770)
S = ns.Summary(0)
assert S.gonePending == 0 and S.goneFinal == 500, (S.gonePending, S.goneFinal)
row = [r for r in vals(ns.NotSold(0)) if r.item == 2770][0]
assert row.status == "mailed to Bob Stranger" and row.state == "final"
# Ann opens her mailbox: the 20 are in her mail count now, still nothing closed or reopened
L.execute("""local s = KMT.mods.Inventory.db.stock["Ann-Forever"]; s.mail, s.mailT = { [2589] = 20 }, NOW + 5
NOW = NOW + 10; KMT.mods.Profit.Mark("Forever-Alliance", 2589); RUN_TIMERS()""")
assert ns.InTransit(POOL, 2589) == 0 and ns.Owned(POOL, 2589) == 20 and kinds(L, 2589) == ["b", "y"], kinds(L, 2589)
assert ns.Holding(POOL, 2589).cost == 2000
print("MAIL OK")

# --- 20. Quest rewards: a lot at no cost, with its worth then -------------------------------------------------------
L, KM, ns = load28(extra="PRICE(4234, 300)")
L.execute("FIRE('BAG_UPDATE_DELAYED'); FIRE('QUEST_COMPLETE'); BAG(4234, 3, 4); FIRE('QUEST_TURNED_IN', 123, 0, 0); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
e = ev(L, 4234)
assert kinds(L, 4234) == ["l"] and e[3] == "3" and e[4] == "0" and e[5] == str(3 * 285) and e[7] == "quest", e
b = [b for b in vals(ns.Buys(0)) if b.item == 4234][0]
assert b.how == "Quest" and b.cost == 0
L.execute("FIRE('QUEST_COMPLETE'); FIRE('QUEST_FINISHED'); BAG(4234, 5, 4); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 4234) == ["l"], "the reward window closed without turning in: nothing"
print("QUEST OK")

# --- 21. Trades: buying and selling for gold, and one that never went through -------------------------------------
L, KM, ns = load28(extra="PRICE(4306, 600); UNITS.NPC = { name = 'Bob' }")
L.execute("MONEY = 100000; FIRE('BAG_UPDATE_DELAYED')")
L.execute("TRADE = { get = { { 4306, 10 } }, pm = 5000 }; FIRE('TRADE_SHOW'); FIRE('TRADE_TARGET_ITEM_CHANGED'); FIRE('TRADE_MONEY_CHANGED')")
L.execute("MONEY = MONEY - 5000; BAG(4306, 10, 5); TRADE = { }; FIRE('TRADE_PLAYER_ITEM_CHANGED'); FIRE('TRADE_CLOSED'); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
e = ev(L, 4306)
assert kinds(L, 4306) == ["t"] and e[3] == "10" and e[4] == "5000" and e[7] == "in/Bob", e
assert ns.Holding(POOL, 4306).cost == 5000 and ns.Holding(POOL, 4306).untraced == 0
L.execute("TRADE = { give = { { 4306, 4 } }, tm = 4000 }; FIRE('TRADE_SHOW'); FIRE('TRADE_PLAYER_ITEM_CHANGED'); FIRE('TRADE_ACCEPT_UPDATE', 1, 0)")
L.execute("MONEY = MONEY + 4000; BAG(4306, 6, 5); FIRE('TRADE_CLOSED'); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
assert kinds(L, 4306) == ["t", "t"] and ev(L, 4306)[7] == "out/Bob", events(L, 4306)
x = [t for t in vals(ns.Trades(0)) if t.item == 4306][0]
assert x.kind == "t" and x.pl == 4000 - 2000 and x.partner == "Bob", (x.pl, x.partner)
KM.Show("profit"); ns.db.ui.tab, ns.db.ui.sub, ns.db.ui.filter = "trades", "sale", "all"; KM.Refresh("profit")
assert "trade to Bob" in rows(ns.P.saleTable)[0].cells["from"].text
L.execute("TRADE = { give = { { 4306, 6 } }, tm = 9000 }; FIRE('TRADE_SHOW'); FIRE('TRADE_PLAYER_ITEM_CHANGED'); FIRE('TRADE_CLOSED'); RUN_TIMERS()")
assert kinds(L, 4306) == ["t", "t"], "cancelled: no gold moved, nothing left the bags"
print("TRADES OK")

# --- 22. Listed at, from the Sales Ledger's postings; the search box ----------------------------------------------
L, KM, ns = load28(extra="PRICE(2589, 200)")
L.globals().KMT = KM
add(L, ns, 2589, "b", t=nov(12), q=10, c=1000, v=1900)
L.execute("""local s = KMT.mods.Inventory.db.stock["Jay-Forever"]; s.ah, s.ahT = { [2589] = 10 }, NOW
table.insert(MailKingDB.posts, { id = 2589, name = "Linen Cloth", n = 10, dep = 30, each = 250, t = NOW - 600, c = "Jay-Forever" })
RUN_TIMERS()""")
bs = L.eval("ProfitKing.Basis(2589)")
assert bs.onAH == 10 and bs.listed == 10 and bs.listedEach == 250, (bs.onAH, bs.listed, bs.listedEach)
assert L.eval("#MailKing.GetPosts(2589)") == 1 and L.eval("#MailKing.GetPosts(4306)") == 0
KM.Show("profit"); ns.SelectTab("holdings")
r = [r for r in rows(ns.P.holdTable) if r.data.item == 2589][0]
L.execute("GameTooltip.lines = {}"); r.RunScript(r, "OnEnter")
tl = tiptext(L)
assert any(x.startswith("On the auction house|10") for x in tl), tl
assert any("listed at" in x and "+138% if they sell" in x for x in tl), tl      # 250 x 0.95 = 237.5 against 100
ns.P.searchBox.text = "lin"; ns.P.searchBox.RunScript(ns.P.searchBox, "OnTextChanged", True)
assert [r.data.item for r in rows(ns.P.holdTable)] == [2589]
ns.P.searchBox.text = "silk"; ns.P.searchBox.RunScript(ns.P.searchBox, "OnTextChanged", True)
assert rows(ns.P.holdTable) == [] and "matches the search" in ns.P.holdTable.empty.text
ns.SelectTab("overview"); assert ns.P.searchBox.shown is False
print("LISTED OK")

# --- 23. Inventory's Items tab: Avg cost and If sold ----------------------------------------------------------------
L, KM, ns = load28(extra="PRICE(2589, 200); PRICE(4306, 600)")
L.execute("BAG(2589, 12, 1); BAG(4306, 3, 2); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
add(L, ns, 2589, "b", t=nov(12), q=10, c=1000, v=1900)
L.execute("RUN_TIMERS()")
inv = KM.mods.Inventory
inv.ShowItems(L.table())
assert not KM.errorShown, last(L)
irows = {r.data.item: r for r in rows(inv.itemTable)}
lin = irows[2589]
import re
def plain(t): return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(t))
assert plain(lin.cells.avgCost.text).startswith("1s"), lin.cells.avgCost.text
assert plain(lin.cells.ifSold.text).startswith("+9s"), lin.cells.ifSold.text   # 10 x (190 - 100)
assert "-" in irows[4306].cells.avgCost.text, "untraced: no cost"
assert "chars" not in list(lin.cells.keys()) and inv.itemTable.pnlCols
L.execute("GameTooltip.lines = {}"); lin.RunScript(lin, "OnEnter")
assert any(x.startswith("Your cost (Profit & Loss)|") for x in tiptext(L)), tiptext(L)
click(inv.itemTable.headers.avgCost)
assert not KM.errorShown, last(L)
print("INVENTORY COLUMNS OK")

# --- 24. A 2.7 journal (version 1) replays unchanged ---------------------------------------------------------------
OLD = """ProfitKingDB = { version = 1, start = %d, seq = 9, home = "Forever-Alliance",
  settings = { method = "fifo", basis = "paid", tooltip = true, keepDays = 60 }, ui = { tab = "overview" },
  pools = { ["Forever-Alliance"] = { chars = { "Jay-Forever" }, seen = {}, months = {}, items = {
    [2589] = { e = { "1:%d:b:20:2000:1900:1", "2:%d:l:30:0:2850:1:mob", "3:%d:b:20:3000:2850:1", "4:%d:s:40:5700::1" } } } } },
  pend = {} }""" % (nov(1), nov(3), nov(5), nov(8), nov(10))
L, KM, ns = load28(only=["Scanner", "Mail", "Profit"], extra="PRICE(2589, 160)", seed=OLD)
assert L.eval("ProfitKingDB.version") == 2 and L.eval("ProfitKingDB.seq") == 9
assert events(L, 2589) == ["1:%d:b:20:2000:1900:1" % nov(3), "2:%d:l:30:0:2850:1:mob" % nov(5), "3:%d:b:20:3000:2850:1" % nov(8),
                           "4:%d:s:40:5700::1" % nov(10)], events(L, 2589)
S = ns.Summary(0)
assert S.realized == 3700 and S.cost == 3000 and S.ifSold == 1560, (S.realized, S.cost)
ns.SetMethod("lifo"); assert ns.Summary(0).realized == 2700; ns.SetMethod("fifo")
print("OLD JOURNAL OK")

# --- 25. Folding a craft: the product keeps its cost after its mats' use is folded ----------------------------------
L, KM, ns = load28(only=["Scanner", "Mail", "Profit"], extra="PRICE(2589, 100); PRICE(1251, 1000)")
add(L, ns, 2589, "b", t=NOW - 100 * DAY, q=10, c=1000, v=950)
add(L, ns, 2589, "b", t=NOW - 99 * DAY, q=10, c=2000, v=950)
g = ns.Reserve()
add(L, ns, 2589, "u", t=NOW - 90 * DAY, q=10, v=950, s=str(g))
add(L, ns, 1251, "k", id=g, t=NOW - 90 * DAY, q=5, v=5000, s="%d/2589" % g)
add(L, ns, 1251, "s", t=NOW - 85 * DAY, q=2, c=2000)
before = (ns.Holding(POOL, 1251).cost, ns.Holding(POOL, 2589).cost, ns.Summary(0).realized)
assert before == (600, 2000, 2000 - 400), before
assert ns.FoldAll() == 2
L.execute("RUN_TIMERS()")
after = (ns.Holding(POOL, 1251).cost, ns.Holding(POOL, 2589).cost, ns.Summary(0).realized)
assert after == before, (before, after)
ck = L.eval("ProfitKingDB.pools[%r].items[1251].ck" % POOL)
lot = vals(ck.lots)[0].split(":")
assert lot[2] == "k" and lot[3] == "3" and lot[4] == "600" and len(lot) <= 7, lot
print("FOLD CRAFT OK")

# --- 26. A missing signal falls back to 2.7: the counts close the mats, the product is untraced -------------------
L, KM, ns = load28(extra="""PRICE(2589, 100); PRICE(1251, 1000); PRICE(10940, 200)
TRADESKILL = { name = "First Aid", recipes = { [3275] = { output = 1251, reagents = { { 2589, 2 } } } } }
C_TradeSkillUI.GetRecipeSchematic = nil; GetSendMailItem = nil; GetTradePlayerItemLink = nil""")
L.execute("BAG(2589, 20, 1); FIRE('BAG_UPDATE_DELAYED'); RUN_TIMERS()")
add(L, ns, 2589, "b", t=nov(3), q=20, c=2000, v=1900)
L.execute("RUN_TIMERS(); CAST(3275, 2); BAG(2589, 16, 1); BAG(1251, 2, 3); SETTLE()")
assert kinds(L, 2589) == ["b", "g"] and not events(L, 1251), (kinds(L, 2589), events(L, 1251))
assert ns.Holding(POOL, 1251).untraced == 2 and ns.Summary(0).gonePending == 400
L.execute("FIRE('MAIL_SHOW'); SEND_MAIL('Ann', { { 2589, 6 } }); BAG(2589, 10, 1); FIRE('BAG_UPDATE_DELAYED'); FIRE('MAIL_CLOSED'); ADVANCE(3); RUN_TIMERS()")
assert kinds(L, 2589) == ["b", "g", "g"], kinds(L, 2589)
L.execute("UNITS.NPC = { name = 'Bob' }; TRADE = { give = { { 2589, 10 } }, tm = 900 }; FIRE('TRADE_SHOW'); FIRE('TRADE_PLAYER_ITEM_CHANGED')")
L.execute("MONEY = MONEY + 900; BAG(2589, 0, 1); FIRE('TRADE_CLOSED'); FIRE('BAG_UPDATE_DELAYED'); ADVANCE(3); RUN_TIMERS()")
assert kinds(L, 2589) == ["b", "g", "g", "g"], kinds(L, 2589)
# disenchanting with no cast seen: the mats are loot, as in 2.7
L.execute("OPEN_LOOT({ { link = LINK(10940), qty = 2 } }, {}, true); LOOT_ALL(); RUN_TIMERS()")
assert ev(L, 10940)[2] == "l" and ev(L, 10940)[7] in ("box", "de"), events(L, 10940)
assert not KM.errorShown, last(L)
print("FALLBACK OK")

print("profit: ok")
