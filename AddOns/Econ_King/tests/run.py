# Runs Econ King (with Scanner King) against a stand-in for the game:
#   python3 tests/run.py . [path/to/Scanner_King]
import sys, re
from lupa import lua51
root = sys.argv[1]
sk_root = sys.argv[2] if len(sys.argv) > 2 else f"{root}/../scanner_king"

def toc_files(path, name):
    return [l.strip().replace("\\", "/") for l in open(f"{path}/{name}.toc") if l.strip() and not l.startswith("#")]

L = lua51.LuaRuntime()
L.execute(open(f"{root}/tests/mock.lua").read())
L.execute("C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }")
L.execute("Enum.TooltipDataType = { Item = 0 }; TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) TT_HOOK = fn end }")
# items: name, quality, class, subclass
L.execute("""
ITEMS = {
  [2589] = { "Linen Cloth", 1, 7, 5 }, [2770] = { "Copper Ore", 1, 7, 7 }, [6000] = { "Big Sword", 2, 2, 7 },
  [6001] = { "Plate Helm", 2, 4, 4 }, [6002] = { "Cloth Hat", 2, 4, 1 }, [118] = { "Minor Healing Potion", 1, 0, 1 },
}
C_Item.GetItemInfo = function(id) local i = ITEMS[id]; if i then return i[1], "|Hitem:" .. id .. "|h[" .. i[1] .. "]|h", i[2] end end
C_Item.GetItemInfoInstant = function(id) local i = ITEMS[id]; if i then return id, "", "", "", 500 + id, i[3], i[4] end end
C_Item.GetItemClassInfo = function(c) return ({ [0] = "Consumable", [2] = "Weapon", [4] = "Armor", [7] = "Trade Goods" })[c] end
C_Item.GetItemSubClassInfo = function(c, s) return ({ ["7:5"] = "Cloth", ["7:7"] = "Metal & Stone", ["2:7"] = "One-Handed Swords",
  ["4:4"] = "Plate", ["4:1"] = "Cloth", ["0:1"] = "Potion" })[c .. ":" .. s] end
""")
skns = L.table()
for fn in toc_files(sk_root, "Scanner_King"):
    L.execute(open(f"{sk_root}/{fn}").read(), "Scanner_King", skns)
ns = L.table()
for fn in toc_files(root, "Econ_King"):
    L.execute(open(f"{root}/{fn}").read(), "Econ_King", ns)
L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("ADDON_LOADED", "Econ_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
ek = L.eval("SlashCmdList.ECONKING")
DAY = 86400
ITEMS_ = L.eval("EconKingDB.items")
def last(): return L.eval("OUTPUT[#OUTPUT]")

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
print(last())
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
ITEMS_[118] and None
print("ROLLUP OK")

# Tooltip lines under Scanner King's
L.execute("NOW = 1700000000 + 41 * 86400"); ns.ClearStats()
L.execute("""
TT = { lines = {} }
function TT:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. "|" .. r end
function TT:AddLine(l) self.lines[#self.lines+1] = l end
TT_HOOK(TT, { id = 2770 })
""")
lines = [L.eval("TT.lines")[i] for i in range(1, len(L.eval("TT.lines")) + 1)]
assert lines[0].startswith("Market price|") and any(l.startswith("30-day average|") for l in lines), lines
print("TOOLTIP OK")

# The window: favorites, deals, categories and the item page
def texts():
    fs = L.eval("FONTS"); out = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
    fr = L.eval("FRAMES"); out += [fr[i].text for i in range(1, len(fr) + 1) if fr[i].text and fr[i].shown != False]
    return out
def side(label):
    return L.eval("(function() for _, f in ipairs(FRAMES) do if f.entry and f.shown and f.text and f.text:find('%s', 1, true) then return f end end end)()" % label)
L.execute("""
LINES = 0
local make = CreateFrame
CreateFrame = function(...)
  local f = make(...)
  f.CreateLine = function() LINES = LINES + 1; return f:CreateTexture() end
  return f
end
""")
ek("")
t = texts()
assert any("Favorites" in x for x in t) and any(x.startswith("Trade Goods") for x in t) and any(x.startswith("Armor") for x in t), t
# no favorites yet: it opens on every item
rows = lambda: [r for r in L.eval("FRAMES").values() if r.id and r.shown and r.cells]
assert len(rows()) == 5, [r.id for r in rows()]
b = side("Armor"); b.scripts.OnClick(b)
assert sorted(r.id for r in rows()) == [6001], [r.id for r in rows()]  # the cloth hat was never listed
b = side("Trade Goods"); b.scripts.OnClick(b)
assert side("Cloth") and side("Metal & Stone")  # subcategories open under it
b = side("Metal & Stone"); b.scripts.OnClick(b)
assert [r.id for r in rows()] == [2770]
# right-click a row to favorite it
b = side("All items"); b.scripts.OnClick(b)
row = [r for r in rows() if r.id == 2589][0]
row.scripts.OnClick(row, "RightButton"); assert L.eval("EconKingDB.fav[2589]")
b = side("Favorites"); b.scripts.OnClick(b)
assert [r.id for r in rows()] == [2589]
# open the item page
row = rows()[0]; row.scripts.OnClick(row, "LeftButton")
t = texts()
assert "< Back" in t and "Market price" in t and "Supply" in t and "30-day average" in t and any("Linen Cloth" in x for x in t), t
assert "1 of 1" in t
back = L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '< Back' then return f end end end)()")
for label in ("7D", "1Y", "All"):
    rb = L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' then return f end end end)()" % label)
    rb.scripts.OnClick(rb)
assert L.eval("LINES") > 5  # the price graph drew line segments
back.scripts.OnClick(back)
assert [r.id for r in rows()] == [2589]
print("UI OK")

# Deals: something 20%+ under its 30-day average
L.execute("NOW = 1700000000 + 42 * 86400")
L.execute("""DEEP({ { 2589, 20, 1600, "A" }, { 2770, 5, 300, "E" }, { 6001, 1, 90000, "G" }, { 118, 5, 250, "H" } })""")
b = side("Deals"); b.scripts.OnClick(b)
assert 2770 in [r.id for r in rows()] and 6001 not in [r.id for r in rows()], [r.id for r in rows()]
# search every item by name
L.execute("(function() for _, f in ipairs(FRAMES) do if f.SetAutoFocus and f.scripts.OnTextChanged then f.GetText = function() return 'potion' end; f.scripts.OnTextChanged(f, true) end end end)()")
assert [r.id for r in rows()] == [118]
print("DEALS OK")

# Sidebar: the count sits in its own right-aligned text, not in the label
b = side("Trade Goods"); assert b.text == "Trade Goods" and b.count.text == "2", (b.text, b.count.text)

# Ask guild: the list's items go out as one request; answers become history
L.execute("SENT = {}; NOW = NOW + 7200")
L.execute("(function() for _, f in ipairs(FRAMES) do if f.SetAutoFocus and f.scripts.OnTextChanged then f.GetText = function() return '' end end end end)()")
b = side("All items"); b.scripts.OnClick(b)
ask = L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'Ask guild' and f.scripts.OnEnter and not f.scripts.OnClick ~= nil then return f end end end)()")
ask.scripts.OnClick(ask); L.execute("RUN_TIMERS()")
reqs = [L.eval("SENT")[i].text for i in range(1, len(L.eval("SENT")) + 1) if L.eval("SENT")[i].text.startswith("R")]
assert len(reqs) == 1 and "Asked the guild about 5 item(s)" in last(), (reqs, last())
before = len(list(ITEMS_[2770].r.values()))
skns_ = L.eval("ScannerKing")
L.execute("ANSWER = { { id = 2770, p = 55, m = 60, q = 9, t = NOW - 60 } }")
msg = list(skns.PackPrices(L.eval("ANSWER")).values())[0]
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + msg + '", "GUILD", "Bob-Realm"); RUN_TIMERS()')
pts = list(ITEMS_[2770].r.values()); assert len(pts) == before + 1
v = ns.Decode(pts[-1]); assert v[2] == 60 and v[3] == 55 and v[4] == 9, list(v.values())
# the same answer twice adds nothing
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + msg + '", "GUILD", "Cat-Realm"); RUN_TIMERS()')
assert len(list(ITEMS_[2770].r.values())) == before + 1
print("ASK GUILD OK")

ek("fav 2770"); assert L.eval("EconKingDB.fav[2770]")
ek("status"); print(last())
ek("item 2589"); assert "< Back" in texts()
print("ALL TESTS PASSED")
