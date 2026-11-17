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
def P(id, level="raw"): return list(ns.Points(id, level).values())
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
assert type(ITEMS_[2589]) is str and len(P(2589)) == 1
v = P(2589)[0]
assert v[2] and v[3] == 100 and v[4] == 50 and v[5] == 3 and v[6] is None, list(v.values())  # first scan: nothing to compare yet
assert ns.db.listings[2589] and ns.db.lastDeep
# 16 minutes later: one 20-stack of linen gone, a new 5-stack listed; the sword is gone; ore unchanged
L.execute("NOW = NOW + 16 * 60")
L.execute("""DEEP({ { 2589, 20, 2000, "A" }, { 2589, 10, 1200, "C" }, { 2589, 5, 600, "F" }, { 2770, 5, 1000, "E" } })""")
v = P(2589)[1]
assert v[4] == 35 and v[6] == 5 and v[7] == 20, list(v.values())  # listed 35, added 5, gone 20
sw = P(6000)[1]
assert sw[4] == 0 and sw[2] is None and sw[7] == 1  # none listed now, 1 gone
assert ns.CompareListings("100x20,120x5", "100x10,130x5") == (5, 15)
# listings are saved cheapest first as base-36 price steps ("*units" when more than one); both shapes compare
assert ns.db.listings[2589] == "#2s*k,k*f", ns.db.listings[2589]  # 20 at 100c, 15 at 120c
assert ns.CompareListings("100x20,120x5", "#2s*a,k*5") == (0, 10) and ns.ParseListings("#2s*a,k*5")[1] == 15
# gone per day is over the time between the two Deep Scans: 20 units in 16 minutes
ns.ClearStats(); s0 = ns.Stats(2589)
assert abs(s0.gonePerDay - 20 * 86400 / 960) < 1e-6, s0.gonePerDay
# the gap lives on the scan, not on every point; lowest = market and auctions = listed are written as "="
assert ns.db.scans[2].g == 960 and v[9] == 960, (ns.db.scans[2].g, v[9])
assert ITEMS_[2589].split("/")[4].split(";")[1].count(":") <= 6, ITEMS_[2589]  # "dt:m:p:q:n:a:r": no gap field
assert ITEMS_[6000].split("/")[4].split(";")[0].split(":")[2] == "=", ITEMS_[6000]
v1 = ns.DecodeV1("1700000000::115:4397"); assert v1[1] == 1700000000 and v1[2] is None and v1[3] == 115 and v1[4] == 4397
print("RECORD OK")

# A Material Scan adds points too, without zeroing anything it didn't look at
L.execute("NOW = NOW + 600; AH_PRICES = { [2770] = 210 }; C_AuctionHouse.SendBrowseQuery = function() end; C_AuctionHouse.SearchForItemKeys = function() end")
L.eval("ScannerKing").Watch("t", L.eval("{ 2770 }")); L.eval("ScannerKing").Scan(); L.execute("RUN_TIMERS()")
assert len(P(2770)) == 3 and len(P(2589)) == 2
assert ns.db.scans[3].k == "material"
m3 = P(2770)[2]
assert m3[2] is None and m3[3] == 210  # a Material Scan only sees the lowest price, so it isn't recorded as market
print("MATERIAL OK")

# Forty days of daily Deep Scans: linen gets cheaper, supply grows
L.execute("NOW = 1700000000")
for d in range(1, 41):
    price = 200 - d * 2  # copper each per unit
    L.execute(f"NOW = 1700000000 + {d} * 86400")
    L.execute(f"""DEEP({{ {{ 2589, 20, {price * 20}, "A" }}, {{ 2589, 20 + {d}, {price * (20 + d)}, "B" }}, {{ 2770, 5, 1000, "E" }},
                          {{ 6001, 1, 90000, "G" }}, {{ 118, 5, 250, "H" }} }})""")
nr, nd, nw = (len(P(2589, x)) for x in ("raw", "day", "week"))
assert nr <= 8 and 20 <= nd <= 31 and nw >= 1, (nr, nd, nw)  # old scans rolled up into days, past 30 days into weeks
d0 = P(2589, "day")[0]; assert d0[8] and d0[8] >= 1
s = ns.Stats(2589)
assert s.market == 120 and abs(s.avg7 - (200 - 37 * 2)) < 3, (s.market, s.avg7)
assert s.vs30 < 0 and s.trend7 < 0 and s.days > 39 and s.listed == 80 and s.supply > 0
assert s.low30 == 120 and s.high30 > s.low30 and s.vol30 > 0
assert s.gonePerDay and s.gonePerDay > 50  # each day's price changed, so every unit listed the day before is "gone"
assert s.points == ns.Get(2589).n == 42 and not s.lowestOnly  # every scan counted, even rolled-up ones
st = L.eval("EconKing.GetStats(2589)"); assert st.market == 120
hist = L.eval("EconKing.GetHistory(2589)"); assert len(list(hist.values())) == nr + nd + nw
assert s.listed7 and 0 < s.supply7 < s.supply, (s.supply7, s.supply)  # listed now against the week and the month
assert s.corr < -0.9 and s.corrN >= 6, s.corr  # cheaper as supply grew: price and supply move opposite ways
assert s.auctions == 2 and not s.trendDays  # two weeks of scans: the trend is week against week
# A young item (four days, no week before this one): the trend is the later half of its days against the earlier half,
# and auctions come from the last scan that counted them even when a later one (a quick scan) didn't.
L.execute("""
local n = NOW
EconKingDB.items[9002] = { r = {
  (n - 4 * 86400) .. ":100:100:50:5", (n - 3 * 86400) .. ":110:110:40:4", (n - 2 * 86400) .. ":120:120:30:3",
  (n - 86400) .. ":130:130:20:7", (n - 600) .. "::125:10" }, d = {}, w = {}, n = 5, seen = n - 600 }
""")
ns.ClearStats(); y = ns.Stats(9002)
assert y.trend7 and y.trendDays == 3 and abs(y.trend7 - (125 / 105 - 1)) < 1e-6, (y.trend7, y.trendDays)  # days 3-4 (125) against days 1-2 (105)
assert y.auctions == 7 and y.listed == 10 and y.auctionsAt < y.seen
assert y.corr is None  # too few scans to say
L.execute("EconKingDB.items[9002] = nil"); ns.ClearStats()
print("STATS OK", round(s.vs30, 3), round(s.trend7, 3), s.points)

# Rolling up keeps each average's true weight: one priced scan (100) and three
# with none listed, then a day priced at 200, roll into one week at 150, not 120
L.execute("""
local t0 = 1700000000 - 100 * 86400
t0 = t0 - t0 % (7 * 86400) + 86400   -- a Monday-ish start, both days in one week
EconKingDB.items[9001] = { r = {
  t0 .. ":100:100:5:1", (t0 + 60) .. ":::0:0", (t0 + 120) .. ":::0:0", (t0 + 180) .. ":::0:0",
  (t0 + 86400) .. ":200:200:5:1" }, d = {}, w = {}, n = 5, seen = 1700000000 }
""")
ns.Compact(9001, L.eval("NOW"))
w = P(9001, "week")
assert len(w) == 1 and w[0][2] == 150 and w[0][8] == 5, list(w[0].values())
L.execute("EconKingDB.items[9001] = nil")

# Background jobs keep going past an item whose data is bad
L.execute("DONE = false")
ns.Background(L.eval("{ 1, 2, 3 }"), L.eval("function(id) if id == 2 then error('bad') end end"), L.eval("function() DONE = true end"))
L.execute("RUN_TIMERS()"); assert L.eval("DONE")
print("WEIGHTS OK")

# Long ago history rolls into weeks (not for favorites)
L.execute("NOW = 1700000000 + 200 * 86400; EconKingDB.keep.forget = 0")
ns.CompactAll(); L.execute("RUN_TIMERS()")
assert len(P(2589, "week")) > 0 and len(P(2589, "day")) == 0 and len(P(2589, "raw")) == 0
L.execute("EconKingDB.keep.forget = 90")
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
assert lines[1] == "King Maker| " and lines[2].startswith("Auction house|") and any(l.startswith("30-day average|") for l in lines), lines
ek("tooltip off"); assert L.eval("EconKingDB.ui.tooltip") is False
L.execute("TT.lines = {}; TT.skItem = nil; TT_HOOK(TT, { id = 2770 })")
lines = [L.eval("TT.lines")[i] for i in range(1, len(L.eval("TT.lines")) + 1)]
assert lines[2].startswith("Auction house|") and not any(l.startswith("30-day average|") for l in lines), lines
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
before = len(P(2770))
L.execute("ANSWER = { { id = 2770, p = 55, m = 60, q = 9, t = NOW - 60 } }")
msg = list(skns.PackPrices(L.eval("ANSWER")).values())[0]
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + msg + '", "GUILD", "Bob-Realm"); RUN_TIMERS()')
pts = P(2770); assert len(pts) == before + 1
v = pts[-1]; assert v[2] == 60 and v[3] == 55 and v[4] == 9, list(v.values())
# the same answer twice adds nothing
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + msg + '", "GUILD", "Cat-Realm"); RUN_TIMERS()')
assert len(P(2770)) == before + 1
print("ASK GUILD OK")

ek("fav 2770"); assert L.eval("EconKingDB.fav[2770]") and L.eval("EconKing.IsFavorite(2770)")
assert L.eval("EconKing.SetFavorite(2589, true)") and L.eval("EconKing.IsFavorite(2589)"); L.eval("EconKing.SetFavorite(2589, false)"); assert not L.eval("EconKing.IsFavorite(2589)") and L.eval("EconKing.SetFavorite('x', true)") is False
ek("status"); out = [str(o) for o in outputs(L)][-5:]
assert any("items tracked" in o and "points" in o and "saved" in o for o in out) and any("every scan for 7 days" in o for o in out), out
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
assert L2.eval("EconKingDB == HELD") and KM2.mods.Econ.Get(2589).n == 1 and L2.eval("EconKingDB.ui.button") is None
assert L2.eval("type(EconKingDB.items[2589])") == "string" and L2.eval("EconKingDB.v") == 2  # converted at login
assert L2.eval("EconKingDB.fav") is not None and L2.eval("EconKingDB.ui.tooltip") is True
KM2.Show("history"); assert not KM2.errorShown
# Econ without Scanner still loads and opens
L3, KM3 = fresh(only=["Econ"], extra=EXTRA)
KM3.Show("history"); assert not KM3.errorShown, last(L3)
print("INITDB OK")

# ---------------------------------------------------------------------------
# Schema 2 (2.6.1): the old shape converts in the background, resumes after /reload, and the pages read the same
# ---------------------------------------------------------------------------
import math
NOW2 = 1750000000
DEEP_GAP = 12 * 3600
SER = """
function SER(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" then return string.format("%.17g", v) end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = "[" .. SER(k) .. "]=" .. SER(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end
function STEP() local fn = table.remove(TIMERS, 1); if fn then fn() end; return fn ~= nil end
function COUNT_OLD() local o, n = 0, 0 for _, it in pairs(EconKingDB.items) do n = n + 1; if type(it) == "table" then o = o + 1 end end return o, n end
"""


def price(i, t):  # a market that wanders: a slow wave plus a drift per item
    base = 500 + 37 * i
    return int(base * (1 + 0.25 * math.sin(t / (5 * DAY) + i)) + (NOW2 - t) / DAY * (i % 3))


def seed_v1(n_items=240):
    """Old-shape history like a real save: 7 days of scans (a Deep Scan every 12 h, with added/gone and the gap),
    then a point a day back to 120 days, then a point a week back to 400 days; some items gone for months; a favorite."""
    items, scans = {}, []
    deep_times = [NOW2 - k * DEEP_GAP for k in range(13, -1, -1)]
    for t in deep_times:
        scans.append(f'{{ t = {t}, k = "deep", n = {n_items} }}')
    scans.append(f'{{ t = {NOW2 - 3 * DAY + 30}, k = "market", n = 40 }}')
    for i in range(n_items):
        dead = i % 20 == 7           # last listed 150 days ago
        r, d, w = [], [], []
        if not dead:
            for t in deep_times:
                m, q = price(i, t), 10 + (i + t // DEEP_GAP) % 25
                r.append(f"{t}:{m}:{m - 3}:{q}:{q if i % 2 else q - 1}:{(i + t) % 7}:{(i * t) % 5}::{DEEP_GAP}")
            if i < 40:  # a Market Scan point
                r.append(f"{NOW2 - 3 * DAY + 30}::{price(i, NOW2 - 3 * DAY) - 5}:12")
            r.sort(key=lambda x: int(x.split(':')[0]))
        start = 150 if dead else 8
        for k in range(120, start - 1, -1):
            b = (NOW2 - k * DAY) // DAY * DAY
            m = price(i, b)
            d.append(f"{b}:{m}:{m - 4}:{15 + k % 9}:{14 + k % 9}:{k % 6}:{k % 4}:2:{2 * DEEP_GAP}")
        for k in range(400, 120, -7):
            b = (NOW2 - k * DAY) // (7 * DAY) * (7 * DAY)
            if w and w[-1].startswith(str(b) + ":"):
                continue
            m = price(i, b)
            w.append(f"{b}:{m}:{m - 6}:{20 + k % 5}:{18 + k % 5}:{k % 9}:{k % 8}:14:{14 * DEEP_GAP}:13")
        seen = (NOW2 - 150 * DAY) if dead else NOW2
        q = lambda lst: "{" + ",".join('"' + x + '"' for x in lst) + "}"
        items[3000 + i] = f"{{ r = {q(r)}, d = {q(d)}, w = {q(w)}, n = {len(r) + 2 * len(d) + 14 * len(w)}, seen = {seen} }}"
    body = ",".join(f"[{k}] = {v}" for k, v in items.items())
    info = ",".join(f'[{k}] = {{ name = "Thing {k}", q = 2, icon = {130000 + k} }}' for k in items)
    return (f"NOW = {NOW2}\nEconKingDB = {{ items = {{ {body} }}, info = {{ {info} }}, fav = {{ [3007] = true, [3008] = true }}, "
            f"scans = {{ {','.join(scans)} }}, listings = {{ [3000] = \"33800x2,34000x1,33900x5\" }}, "
            f"listingsTime = {NOW2}, ui = {{ tooltip = true }} }}")


def ref_stats(L_, id_):
    """What 2.6.0's Stats gave for an old-shape item, worked out here straight from its strings."""
    it = L_.eval(f"EconKingDB.items[{id_}]")
    pts = []
    for k in ("r", "d", "w"):
        for sv in it[k].values():
            f = (sv.split(":") + [""] * 13)[:13]
            pts.append([float(x) if x != "" else None for x in f])
    now = NOW2
    has_m = any(v[1] is not None and now - v[0] <= 30 * DAY for v in pts)
    K = 1 if has_m else 2
    cnt = {1: 9, 2: 10, 3: 11, 4: 12}

    def wt(v, k):
        return 0 if v[k] is None else (v[cnt[k]] or v[7] or 1)
    acc = {"avg7": [0, 0], "avg30": [0, 0], "prev7": [0, 0], "listed30": [0, 0]}
    gone = gap = 0
    for v in pts:
        age, w = now - v[0], wt(v, K)
        if w:
            if age <= 30 * DAY:
                acc["avg30"][0] += v[K] * w; acc["avg30"][1] += w
            if age <= 7 * DAY:
                acc["avg7"][0] += v[K] * w; acc["avg7"][1] += w
            elif age <= 14 * DAY:
                acc["prev7"][0] += v[K] * w; acc["prev7"][1] += w
        if age <= 30 * DAY and v[3] is not None:
            acc["listed30"][0] += v[3] * wt(v, 3); acc["listed30"][1] += wt(v, 3)
        if age <= 7 * DAY and v[6] is not None and v[8]:
            gone += v[6]; gap += v[8]
    out = {k: a[0] / a[1] for k, a in acc.items() if a[1]}
    out["trend7"] = (out["avg7"] - out["prev7"]) / out["prev7"]
    out["gonePerDay"] = gone / (gap / DAY) if gap else None
    days = {}  # the 30-day graph: the average market price per day
    for v in pts:
        if v[1] is not None and now - v[0] <= 30 * DAY:
            days.setdefault(int(v[0] // DAY), []).append(v[1])
    out["graph"] = {d: sum(x) / len(x) for d, x in days.items()}
    out["first"] = min(v[0] for v in pts)
    return out


def close(a, b, tol=0.01):
    return a is not None and b is not None and abs(a - b) <= tol * max(1, abs(b))


SEED = seed_v1()
Lm, KMm = fresh(only=["Scanner", "Econ"], extra=EXTRA + SER, seed=SEED, login=False)
nsm = KMm.mods.Econ
REF = {i: ref_stats(Lm, i) for i in (3000, 3001, 3005, 3017)}
assert Lm.eval("COUNT_OLD()") == (240, 240)
# Load and log in, but let only a few frames run: each frame converts at most a batch of items.
Lm.execute('LOADED_ADDONS["King_Maker"] = true; FIRE("ADDON_LOADED", "King_Maker")')
v1_size = nsm.SavedSize()[0]
Lm.execute('FIRE("PLAYER_LOGIN")')
assert Lm.eval("EconKingDB.v") is None, "old data: not schema 2 until it's converted"
olds = [Lm.eval("COUNT_OLD()")[0]]
for _ in range(200):  # frame by frame (other modules' timers run too) until a few batches have gone
    Lm.execute("STEP()")
    olds.append(Lm.eval("COUNT_OLD()")[0])
    if olds[-1] <= 240 - 3 * 50:
        break
steps = [a - b for a, b in zip(olds, olds[1:])]
assert max(steps) <= 50 and 0 < olds[-1] < 240, (olds, steps)  # batched, never one long loop
mig = Lm.eval("EconKingDB.migration")
assert mig.done == 240 - olds[-1] and mig.total == 240, (mig.done, mig.total)
# A /reload now: the game saves what's there, part old and part new
saved = Lm.eval("SER(EconKingDB)")
print("MIGRATE BATCHED OK", olds)

Lr, KMr = fresh(only=["Scanner", "Econ"], extra=EXTRA + SER, seed=f"NOW = {NOW2}\nEconKingDB = " + saved)
nsr = KMr.mods.Econ
assert Lr.eval("COUNT_OLD()")[0] == 0 and Lr.eval("EconKingDB.v") == 2 and Lr.eval("EconKingDB.migration") is None
assert any("Price History now takes less space" in str(o) for o in outputs(Lr)), outputs(Lr)
log = Lr.eval("EconKingDB.sizeLog")
assert log.what == "convert" and log.after < log.before * 0.6, (log.before, log.after)
for i in (3000, 3001, 3239):
    assert Lr.eval(f"EconKingDB.info[{i}]") == f"2:Thing {i}", i  # "quality:name": names stay, icons don't
    assert nsr.Info(i).name == f"Thing {i}" and nsr.Info(i).q == 2 and nsr.Name(i) == f"Thing {i}"
assert Lr.eval("EconKingDB.listings[3000]") == "#q2w*2,2s*5,2s", Lr.eval("EconKingDB.listings[3000]")  # rewritten compactly
# Every Deep Scan's gap now sits on the scan; the points leave it out
gaps = [Lr.eval(f"EconKingDB.scans[{k}].g") for k in range(1, 15)]
assert gaps.count(DEEP_GAP) >= 13, gaps
raw0 = Lr.eval("EconKingDB.items[3000]").split("/")[4].split(";")
assert all(len(p.split(":")) <= 8 for p in raw0), raw0[:3]
print("MIGRATE RESUMED OK", round(log.before / 1024), "KB ->", round(log.after / 1024), "KB")


def lv(id_, level):
    return list(nsr.Points(id_, level).values())


# Tiers after login's compaction: every scan for 7 days, a day each to 30 days, weeks to 180 days, then 4 weeks
for i in (3000, 3001, 3017):
    raw, day, week, month = (lv(i, x) for x in ("raw", "day", "week", "month"))
    assert raw and all(NOW2 - v[1] <= 7 * DAY for v in raw), i
    assert day and all(6 * DAY <= NOW2 - v[1] <= 30 * DAY for v in day), [(NOW2 - v[1]) / DAY for v in day]
    assert week and all(30 * DAY < NOW2 - v[1] <= 187 * DAY for v in week), i
    assert month and all(NOW2 - v[1] > 152 * DAY for v in month), i
    assert all(v[1] % (28 * DAY) == 0 for v in month) and all(v[1] % (7 * DAY) == 0 for v in week)
    assert all(v[6] is None and v[9] is None for v in week + month), "weeks and months leave out added and gap"
    times = [v[1] for v in nsr.Series(i).values()]
    assert times == sorted(times)
fav_days = lv(3008, "day")
assert len(fav_days) > 100 and any(NOW2 - v[1] > 100 * DAY for v in fav_days), len(fav_days)  # a favorite keeps its days
assert Lr.eval("EconKingDB.items[3007]") and Lr.eval("EconKingDB.info[3007]")  # and is never forgotten (gone 150 days)
# Items not listed for 150 days are forgotten (the setting: 90 days), name and all
assert Lr.eval("EconKingDB.items[3027]") is None and Lr.eval("EconKingDB.info[3027]") is None
assert Lr.eval("EconKingDB.items[3028]") is not None
print("TIERS OK")

# The pages read the same numbers as before: 30-day average, 7-day trend, gone per day, the graph's shape
for i, ref in REF.items():
    nsr.ClearStats()
    st = nsr.Stats(i)
    for k in ("avg30", "avg7", "prev7", "listed30", "trend7", "gonePerDay"):
        a, b = st[k], ref[k]
        assert (a is None and b is None) or close(a, b, 0.01 if k != "trend7" else 0.02), (i, k, a, b)
    assert abs(st.first - ref["first"]) <= 28 * DAY, (st.first, ref["first"])
    graph = {}
    for v in nsr.Series(i).values():
        if v[2] is not None and NOW2 - v[1] <= 30 * DAY:
            graph.setdefault(int(v[1] // DAY), []).append(v[2])
    for d, vals in graph.items():
        assert d in ref["graph"] and close(sum(vals) / len(vals), ref["graph"][d], 0.01), (i, d)
    assert len(graph) >= len(ref["graph"]) - 1
    hist = list(Lr.eval(f"EconKing.GetHistory({i})").values())
    assert all(h[1] and (h[8] or 1) >= 1 for h in hist)
print("READERS SAME OK")

# A new scan appends to the packed string; the numbers follow
Lr.execute(f"NOW = {NOW2 + 3600}")
nsr.Record(Lr.eval("{ [3000] = { m = 999, p = 990, q = 4, n = 4 } }"), "market", None)
Lr.execute("RUN_TIMERS()")
last_raw = lv(3000, "raw")[-1]
assert last_raw[1] == NOW2 + 3600 and last_raw[2] == 999 and last_raw[3] == 990 and last_raw[5] == 4
nsr.ClearStats()
assert nsr.Stats(3000).market == 999 and nsr.Stats(3000).points == nsr.Get(3000).n

# Settings > Price History: three ranges, Compact now, and the size line
KMr.OpenSettings("econ")
fs = [str(Lr.eval("FONTS")[k].text) for k in range(1, len(Lr.eval("FONTS")) + 1)]
for label in ("Keep every scan for", "Keep a point a day for", "Forget items not seen for", "Compact now", "7 days", "30 days", "90 days"):
    assert label in fs, label
assert any("items tracked" in t and "saved" in t for t in fs)
assert not KMr.errorShown, last(Lr)
# Every scan is kept at least 7 days (the 7-day numbers read them)
Lr.execute("EconKingDB.keep.raw = 3; EconKingDB.keep.day = 20; EconKingDB.keep.forget = 0")
assert nsr.Keep().raw == 7
# Fewer days of a point a day: Compact now rolls them up and says what it saved
Lr.execute("EconKingDB.keep.raw = 10")
btn = Lr.eval("BTN('Compact now')")
btn.RunScript(btn, "OnClick", "LeftButton")
Lr.execute("RUN_TIMERS()")
assert any("Price History compacted: about" in str(o) and "points kept" in str(o) for o in outputs(Lr)), outputs(Lr)[-3:]
assert lv(3001, "raw") and all(NOW2 + 3600 - v[1] <= 20 * DAY for v in lv(3001, "day"))
Lr.execute("EconKingDB.keep.raw = 7; EconKingDB.keep.day = 30")
srx = Lr.eval("SlashCmdList.ECONKING")
srx("compact")
Lr.execute("RUN_TIMERS()")
assert "compacted" in last(Lr), last(Lr)
srx("status")
out = [str(o) for o in outputs(Lr)][-5:]
assert any("Last compacted" in o and "->" in o for o in out), out
v2_size = nsr.SavedSize()[0]
assert v2_size < v1_size * 0.55, (v1_size, v2_size)
print("SETTINGS OK", round(v1_size / 1024), "KB ->", round(v2_size / 1024), "KB")

# Base 36, and time steps that go backwards (a guildmate's clock ahead of ours) survive the round trip
assert nsr.B36(0) == "0" and nsr.B36(35) == "z" and nsr.B36(1296) == "100" and nsr.B36(-5) == "-5"
# Prices past 32 bits (a placeholder listing at 9,999,999g 99s 99c) survive: the game's tonumber(s, 36) stops at 2^32
assert nsr.Big36(nsr.B36(99999999999)) == 99999999999 and nsr.Big36(nsr.B36(4294967296)) == 4294967296
Lr.execute(f"NOW = {NOW2 + 4000}")
nsr.Record(Lr.eval("{ [4343] = { m = 99999999999, p = 99999999999, q = 1, n = 1, l = { { 99999999999, 1 }, { 120, 2 } } } }"), "deep", "replicate")
big = lv(4343, "raw")[-1]
assert big[2] == 99999999999 and big[3] == 99999999999, (big[2], big[3])
assert sorted(nsr.ParseListings(Lr.eval("EconKingDB.listings[4343]"))[0].items()) == [(120, 2), (99999999999, 1)]
nsr.RecordGuild(Lr.eval(f"{{ [4242] = {{ t = {NOW2 + 7000}, p = 50, q = 2 }} }}"))
Lr.execute(f"NOW = {NOW2 + 5000}")
nsr.Record(Lr.eval("{ [4242] = { p = 40, q = 3 } }"), "market", None)
assert sorted(v[1] for v in lv(4242, "raw")) == [NOW2 + 5000, NOW2 + 7000]
# A Market Scan seconds after a Deep Scan that sees the same lowest and listed adds no point (it still counts)
Lr.execute(f"NOW = {NOW2 + 9000}")
nsr.Record(Lr.eval("{ [3001] = { m = 700, p = 650, q = 9, n = 9 } }"), "deep", "replicate")
before_pts, before_n = len(lv(3001, "raw")), nsr.Get(3001).n
Lr.execute(f"NOW = {NOW2 + 9040}")
nsr.Record(Lr.eval("{ [3001] = { p = 650, q = 9 } }"), "market", None)
assert len(lv(3001, "raw")) == before_pts and nsr.Get(3001).n == before_n + 1 and nsr.Get(3001).seen == NOW2 + 9040
Lr.execute(f"NOW = {NOW2 + 9080}")
nsr.Record(Lr.eval("{ [3001] = { p = 640, q = 9 } }"), "market", None)  # a new lowest is news
assert len(lv(3001, "raw")) == before_pts + 1
# Raw times point at numbered scans: "the next scan" is one letter
raw3000 = Lr.eval("EconKingDB.items[3000]").split("/")[4].split(";")
assert sum(1 for x in raw3000 if x[:1].isupper()) >= 10, raw3000[:4]
assert all(Lr.eval(f"EconKingDB.scans[{k}].i") == k for k in range(1, 15))  # 2.6.0's scans numbered oldest first
# Two scans in the same second, then one more: every time decodes back
T3 = NOW2 + 20000
Lr.execute(f"NOW = {T3}")
nsr.Record(Lr.eval("{ [5151] = { p = 10, q = 1 } }"), "material", None)
nsr.Record(Lr.eval("{ [5151] = { p = 11, q = 2 } }"), "market", None)
Lr.execute(f"NOW = {T3 + 100}")
nsr.Record(Lr.eval("{ [5151] = { p = 12, q = 3 } }"), "market", None)
assert [(v[1], v[3]) for v in lv(5151, "raw")] == [(T3, 10), (T3, 11), (T3 + 100, 12)], [(v[1], v[3]) for v in lv(5151, "raw")]
# A point whose scan has left the list is skipped; the rest still read (and the page doesn't break)
Lr.execute("for k = #EconKingDB.scans, 1, -1 do if EconKingDB.scans[k].t == %d then table.remove(EconKingDB.scans, k) end end" % (T3 + 100))
assert [(v[1], v[3]) for v in lv(5151, "raw")] == [(T3, 10), (T3, 11)]
nsr.ClearStats(); assert nsr.Stats(5151).lowest in (10, 11) and nsr.Stats(5151).points == 3
# Names learnt from the game are saved as "quality:name"
Lr.execute('ITEM(77001, "Zesty Thing", { quality = 3, class = 7, subclass = 5 })')
assert nsr.Info(77001).name == "Zesty Thing" and Lr.eval("EconKingDB.info[77001]") == "3:Zesty Thing"
print("ENCODING OK")

print("econ: ok")
