# Econ (was Econ King), with Scanner: history, roll-ups, stats, deals, tooltips, Ask guild, /ek and the
# Price History page (list + item page).
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

EXTRA = """
-- name, quality, class, subclass (the shared mock reads ITEMS[id] = { name =, quality =, class =, subclass = })
ITEM(2589, "Linen Cloth", { quality = 1, class = 7, subclass = 5 })
ITEM(2770, "Copper Ore", { quality = 1, class = 7, subclass = 7 })
ITEM(6000, "Big Sword", { quality = 2, class = 2, subclass = 7 })
ITEM(6001, "Plate Helm", { quality = 2, class = 4, subclass = 4 })
ITEM(6002, "Cloth Hat", { quality = 2, class = 4, subclass = 1 })
ITEM(118, "Minor Healing Potion", { quality = 1, class = 0, subclass = 1 })
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function BTNS(text) local r = {} for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then r[#r+1] = f end end return r end
function SIDE(text) for _, f in ipairs(FRAMES) do if rawget(f, "entry") and f.shown ~= false and f.label.text and f.label.text:find(text, 1, true) then return f end end end
function SEARCHBOX() for _, f in ipairs(FRAMES) do if type(rawget(f, "hint")) == "table" and f.hint.text == "Search every item" then return f end end end
"""

L, KM = fresh(only=["Scanner", "Econ"], extra=EXTRA)
ns, skns = KM.mods.Econ, KM.mods.Scanner
ek = L.eval("SlashCmdList.ECONKING")
DAY = 86400
ITEMS_ = L.eval("EconKingDB.items")
assert L.eval("EconKing.API_VERSION") == 1 and L.eval("EconKingDB.ui.tooltip") is True
assert L.eval("EconKingMinimapButton") is None and L.eval("EconKingFrame") is None, "no window or button of its own"

# Deep Scans through the auction dump: the stand-in sells some linen between scans
L.execute("""
NOW = 1700000000
C_AuctionHouse.ReplicateItems = function() C_Timer.After(1, function() FIRE("REPLICATE_ITEM_LIST_UPDATE") end) end
C_AuctionHouse.GetNumReplicateItems = function() return #AUCTIONS end
C_AuctionHouse.GetReplicateItemInfo = function(i)
  local a = AUCTIONS[i + 1]
  return "x", 1, a[2], 1, true, 1, 0, 0, 0, a[3], 0, false, nil, a[4], a[4], 0, a[1], true
end
function DEEP(auctions) AUCTIONS = auctions; ScannerKing.DeepScan(); RUN_TIMERS() end
""")
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
L.execute("""DEEP({ { 2589, 20, 2000, "A" }, { 2589, 20, 2000, "B" }, { 2589, 10, 1200, "C" },
                    { 6000, 1, 50000, "D" }, { 2770, 5, 1000, "E" } })""")
assert any("Recorded 3 items from the Deep Scan." in str(o) for o in outputs(L)), outputs(L)
assert ITEMS_[2589] and len(list(ITEMS_[2589].r.values())) == 1
v = ns.Decode(ITEMS_[2589].r[1])
assert v[2] and v[3] == 100 and v[4] == 50 and v[5] == 3 and v[6] is None, list(v.values())  # first scan: nothing to compare yet
assert ns.db.listings[2589] and ns.db.lastDeep
# 16 minutes later: one 20-stack of linen gone, a new 5-stack listed; the sword is gone; ore unchanged
L.execute("NOW = NOW + 16 * 60")
L.execute("""DEEP({ { 2589, 20, 2000, "A" }, { 2589, 10, 1200, "C" }, { 2589, 5, 600, "F" }, { 2770, 5, 1000, "E" } })""")
v = ns.Decode(ITEMS_[2589].r[2])
assert v[4] == 35 and v[6] == 5 and v[7] == 20, list(v.values())  # listed 35, added 5, gone 20
sw = ns.Decode(ITEMS_[6000].r[2])
assert sw[4] == 0 and sw[2] is None and sw[7] == 1  # none listed now, 1 gone
assert ns.CompareListings("100x20,120x5", "100x10,130x5") == (5, 15)
# gone per day is over the time between the two Deep Scans: 20 units in 16 minutes
ns.ClearStats(); s0 = ns.Stats(2589)
assert abs(s0.gonePerDay - 20 * 86400 / 960) < 1e-6, s0.gonePerDay
# encoding round-trips, trailing blanks trimmed
assert ns.Encode(ns.Decode("1700000000::115:4397")) == "1700000000::115:4397"
print("RECORD OK")

# A Material Scan adds points too, without zeroing anything it didn't look at
L.execute("NOW = NOW + 600; AH_PRICES = { [2770] = 210 }; C_AuctionHouse.SendBrowseQuery = function() end; C_AuctionHouse.SearchForItemKeys = function() end")
L.eval("ScannerKing").Watch("t", L.eval("{ 2770 }")); L.eval("ScannerKing").Scan(); L.execute("RUN_TIMERS()")
assert len(list(ITEMS_[2770].r.values())) == 3 and len(list(ITEMS_[2589].r.values())) == 2
assert ns.db.scans[3].k == "material"
m3 = ns.Decode(ITEMS_[2770].r[3])
assert m3[2] is None and m3[3] == 210  # a Material Scan only sees the lowest price, so it isn't recorded as market
print("MATERIAL OK")

# Forty days of daily Deep Scans: linen gets cheaper, supply grows
L.execute("NOW = 1700000000")
for d in range(1, 41):
    price = 200 - d * 2  # copper each per unit
    L.execute(f"NOW = 1700000000 + {d} * 86400")
    L.execute(f"""DEEP({{ {{ 2589, 20, {price * 20}, "A" }}, {{ 2589, 20 + {d}, {price * (20 + d)}, "B" }}, {{ 2770, 5, 1000, "E" }},
                          {{ 6001, 1, 90000, "G" }}, {{ 118, 5, 250, "H" }} }})""")
it = ITEMS_[2589]
nr, nd, nw = (len(list(x.values())) for x in (it.r, it.d, it.w))
assert nr <= 8 and nd >= 30, (nr, nd, nw)  # old scans rolled up into days
d0 = ns.Decode(it.d[1]); assert d0[8] and d0[8] >= 1
s = ns.Stats(2589)
assert s.market == 120 and abs(s.avg7 - (200 - 37 * 2)) < 3, (s.market, s.avg7)
assert s.vs30 < 0 and s.trend7 < 0 and s.days > 39 and s.listed == 80 and s.supply > 0
assert s.low30 == 120 and s.high30 > s.low30 and s.vol30 > 0
assert s.gonePerDay and s.gonePerDay > 50  # each day's price changed, so every unit listed the day before is "gone"
assert s.points == ITEMS_[2589].n == 42 and not s.lowestOnly  # every scan counted, even rolled-up ones
st = L.eval("EconKing.GetStats(2589)"); assert st.market == 120
hist = L.eval("EconKing.GetHistory(2589)"); assert len(list(hist.values())) == nr + nd + nw
print("STATS OK", round(s.vs30, 3), round(s.trend7, 3), s.points)

# Rolling up keeps each average's true weight: one priced scan (100) and three
# with none listed, then a day priced at 200, roll into one week at 150, not 120
L.execute("""
local t0 = 1700000000 - 300 * 86400
t0 = t0 - t0 % (7 * 86400) + 86400   -- a Monday-ish start, both days in one week
EconKingDB.items[9001] = { r = {
  t0 .. ":100:100:5:1", (t0 + 60) .. ":::0:0", (t0 + 120) .. ":::0:0", (t0 + 180) .. ":::0:0",
  (t0 + 86400) .. ":200:200:5:1" }, d = {}, w = {}, n = 5 }
""")
ns.Compact(9001, L.eval("NOW"))
w = ns.Decode(ITEMS_[9001].w[1])
assert len(list(ITEMS_[9001].w.values())) == 1 and w[2] == 150 and w[8] == 5, list(w.values())
L.execute("EconKingDB.items[9001] = nil")

# Background jobs keep going past an item whose data is bad
L.execute("DONE = false")
ns.Background(L.eval("{ 1, 2, 3 }"), L.eval("function(id) if id == 2 then error('bad') end end"), L.eval("function() DONE = true end"))
L.execute("RUN_TIMERS()"); assert L.eval("DONE")
print("WEIGHTS OK")

# Long ago history rolls into weeks (not for favorites)
L.execute("NOW = 1700000000 + 200 * 86400")
ns.CompactAll()
it = ITEMS_[2589]
assert len(list(it.w.values())) > 0 and len(list(it.d.values())) < 30
print("ROLLUP OK")

# Tooltip lines under Scanner's
L.execute("NOW = 1700000000 + 41 * 86400"); ns.ClearStats()
L.execute("""
TT = { lines = {} }
function TT:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. "|" .. r end
function TT:AddLine(l) self.lines[#self.lines+1] = l end
TT_HOOK(TT, { id = 2770 })
""")
lines = [L.eval("TT.lines")[i] for i in range(1, len(L.eval("TT.lines")) + 1)]
assert lines[0].startswith("Market price|") and any(l.startswith("30-day average|") for l in lines), lines
ek("tooltip off"); assert L.eval("EconKingDB.ui.tooltip") is False
L.execute("TT.lines = {}; TT.skItem = nil; TT_HOOK(TT, { id = 2770 })")
lines = [L.eval("TT.lines")[i] for i in range(1, len(L.eval("TT.lines")) + 1)]
assert lines[0].startswith("Market price|") and not any(l.startswith("30-day average|") for l in lines), lines
ek("tooltip on"); assert L.eval("EconKingDB.ui.tooltip") is True
print("TOOLTIP OK")

# The Price History page: favorites, deals, categories and the item page
def fonts():
    fs = L.eval("FONTS")
    return [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
def ids(): return [e.id for e in ns.CurrentList().values()]
def side(label): return L.eval("SIDE(%r)" % label)
def click(b, which="LeftButton"): b.RunScript(b, "OnClick", which)

ek("")
assert KM.IsShown("history") and not KM.errorShown, last(L)
assert side("Favorites") and side("Trade Goods") and side("Armor")
# no favorites yet: it opens on every item
assert sorted(ids()) == [118, 2589, 2770, 6000, 6001], ids()
assert any("Linen Cloth" in str(t) for t in fonts()), "rows fill"
assert "items tracked" in ns.footer.text, ns.footer.text
click(side("Armor"))
assert ids() == [6001], ids()  # the cloth hat was never listed
click(side("Trade Goods"))
assert side("Cloth") and side("Metal & Stone")  # subcategories open under it
click(side("Metal & Stone"))
assert ids() == [2770] and side("Metal & Stone").active
# right-click a row to favorite it
click(side("All items"))
row = [r for r in ns.table.rows.values() if r.data and r.data.id == 2589][0]
click(row, "RightButton"); assert L.eval("EconKingDB.fav[2589]")
assert row.star.tex.alpha == 1, "the star lights up"
click(side("Favorites"))
assert ids() == [2589]
# a header click sorts by that column (blanks last)
click(side("All items"))
assert ns.table.sortKey == "name" and [e.name for e in ns.CurrentList().values()][0] == "Big Sword"  # kept from Favorites
h = ns.table.headers.name; click(h)
assert [e.name for e in ns.CurrentList().values()][0] == "Plate Helm" and ns.table.sortDesc  # flipped
h = ns.table.headers.market; click(h)
assert ns.table.sortKey == "market" and ns.CurrentList()[1].id == 6001  # dearest first
# open the item page
click(side("Favorites"))
row = [r for r in ns.table.rows.values() if r.data and r.data.id == 2589][0]
click(row)
t = fonts()
assert "MARKET PRICE" in t and "SUPPLY" in t and "30-DAY AVERAGE" in t and any("Linen Cloth" in str(x) for x in t), t
assert "1 of 1" in t
back = L.eval("BTN('< Back')")
assert back.parent.shown, "the item page took the list's place"
L.execute("LINES = 0")
for label in ("7D", "1Y", "All", "30D"):
    rb = L.eval("BTN(%r)" % label); click(rb)
assert L.eval("LINES") > 5  # the price graph drew line segments
assert not KM.errorShown, last(L)
click(back)
assert ids() == [2589] and not back.parent.shown
print("PAGE OK")

# Deals: something 20%+ under its 30-day average
L.execute("NOW = 1700000000 + 42 * 86400")
L.execute("""DEEP({ { 2589, 20, 1600, "A" }, { 2770, 5, 300, "E" }, { 6001, 1, 90000, "G" }, { 118, 5, 250, "H" } })""")
click(side("Deals"))
assert 2770 in ids() and 6001 not in ids(), ids()
assert ns.table.sortKey == "vs30" and not ns.table.sortDesc
# search every item by name
box = L.eval("SEARCHBOX()")
box.SetText(box, "potion"); box.RunScript(box, "OnTextChanged", True)
assert ids() == [118]
print("DEALS OK")

# Sidebar: the count sits in its own right-aligned text, not in the label
b = side("Trade Goods"); assert b.label.text == "Trade Goods" and b.count.text == "2", (b.label.text, b.count.text)

# Ask guild: the list's items go out as one request; answers become history
L.execute("SENT = {}; NOW = NOW + 7200")
box.SetText(box, ""); box.RunScript(box, "OnTextChanged", True)
click(side("All items"))
ask = L.eval("BTNS('Ask guild')[1]")
click(ask); L.execute("RUN_TIMERS()")
reqs = [L.eval("SENT")[i].text for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].text.startswith("R")]
assert len(reqs) == 1 and "Asked the guild about 5 item(s)" in last(L), (reqs, last(L))
before = len(list(ITEMS_[2770].r.values()))
L.execute("ANSWER = { { id = 2770, p = 55, m = 60, q = 9, t = NOW - 60 } }")
msg = list(skns.PackPrices(L.eval("ANSWER")).values())[0]
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + msg + '", "GUILD", "Bob-Realm"); RUN_TIMERS()')
pts = list(ITEMS_[2770].r.values()); assert len(pts) == before + 1
v = ns.Decode(pts[-1]); assert v[2] == 60 and v[3] == 55 and v[4] == 9, list(v.values())
# the same answer twice adds nothing
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + msg + '", "GUILD", "Cat-Realm"); RUN_TIMERS()')
assert len(list(ITEMS_[2770].r.values())) == before + 1
print("ASK GUILD OK")

ek("fav 2770"); assert L.eval("EconKingDB.fav[2770]") and L.eval("EconKing.IsFavorite(2770)")
ek("status"); assert "items tracked" in last(L), last(L)
ek("item 2589"); assert KM.IsShown("history") and L.eval("BTN('< Back')").parent.shown
ek(""); assert not KM.IsShown(), "/ek toggles the page closed"
ek("button"); assert "crown" in last(L)
ek("help"); assert any("/ek item" in str(o) for o in outputs(L))

# The crown and Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Price History") ~= nil')
L.execute('MENU_ITEM("Price History").fn()'); assert KM.IsShown("history")
L.execute('KingMakerMinimapButton:RunScript("OnEnter")')
assert any("items with price history" in str(x) for x in L.eval("GameTooltip.lines").values())
KM.OpenSettings("econ"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
assert "Averages and trend in item tooltips" in fonts()
KM.Show("prices"); KM.Show("history"); KM.Show("home")
assert not KM.errorShown, last(L)
print("SHELL OK")

# InitDB is safe twice and keeps the table; old minimap keys go
L2, KM2 = fresh(only=["Scanner", "Econ"], extra=EXTRA,
                seed="EconKingDB = { items = { [2589] = { r = { '1700000000:120:100:5:1' }, d = {}, w = {}, n = 1 } }, ui = { button = false, buttonAngle = 30 } }")
L2.execute("HELD = EconKingDB"); KM2.mods.Econ.InitDB()
assert L2.eval("EconKingDB == HELD") and L2.eval("EconKingDB.items[2589].n") == 1 and L2.eval("EconKingDB.ui.button") is None
assert L2.eval("EconKingDB.fav") is not None and L2.eval("EconKingDB.ui.tooltip") is True
KM2.Show("history"); assert not KM2.errorShown
# Econ without Scanner still loads and opens
L3, KM3 = fresh(only=["Econ"], extra=EXTRA)
KM3.Show("history"); assert not KM3.errorShown, last(L3)
print("INITDB OK")

print("econ: ok")
