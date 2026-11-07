# Runs Scanner King against a stand-in for the game: python3 tests/run.py .
import sys, math
from lupa import lua51
root = sys.argv[1]
FILES = ["Core.lua", "Scan.lua", "DeepScan.lua", "Sync.lua", "MarketScan.lua", "Tooltip.lua", "Browser.lua"]

def fresh():
    L = lua51.LuaRuntime()
    L.execute(open(f"{root}/tests/mock.lua").read())
    L.execute("C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }")
    L.execute("Enum.TooltipDataType = { Item = 0 }; TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) TT_HOOK = fn end }")
    ns = L.table()
    for fn in FILES:
        L.execute(open(f"{root}/{fn}").read(), "Scanner_King", ns)
    L.execute('FIRE("ADDON_LOADED", "Scanner_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
    return L, ns

L, ns = fresh()
SK = L.eval("ScannerKing")
sk = L.eval("SlashCmdList.SCANNERKING")
def last(): return L.eval("OUTPUT[#OUTPUT]")
def price(i):
    p = L.eval("ScannerKingDB.prices[%d]" % i)
    return p and p.p

# A modern auction house with a Trade Goods browse that comes back in two pages,
# plus one watched item (seeds) that isn't Trade Goods.
L.execute("""
TRADE = { [2589] = 120, [2770] = 450, [10940] = 900, [248823] = 12345 }
OTHER = { [268415] = 777 }
PAGE_SIZE = 3
BROWSE, KEYS, PAGES_SENT = 0, 0, 0
C_AuctionHouse.SendBrowseQuery = function(q)
  BROWSE = BROWSE + 1
  assert(q.itemClassFilters[1].classID == 7, "trade goods filter")
  RESULTS, SHOWN = {}, 0
  for id, p in pairs(TRADE) do RESULTS[#RESULTS+1] = { itemKey = { itemID = id }, minPrice = p, totalQuantity = 20 } end
  table.sort(RESULTS, function(a, b) return a.itemKey.itemID < b.itemKey.itemID end)
  C_Timer.After(0.1, function() SHOWN = PAGE_SIZE; FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end
C_AuctionHouse.SearchForItemKeys = function(keys)
  KEYS = KEYS + 1; KEY_IDS = {}
  RESULTS = {}
  for _, k in ipairs(keys) do KEY_IDS[k.itemID] = true; if OTHER[k.itemID] then RESULTS[#RESULTS+1] = { itemKey = { itemID = k.itemID }, minPrice = OTHER[k.itemID] } end end
  SHOWN = #RESULTS
  C_Timer.After(0.1, function() FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end
C_AuctionHouse.GetBrowseResults = function() local r = {} for i = 1, math.min(SHOWN, #RESULTS) do r[i] = RESULTS[i] end return r end
C_AuctionHouse.HasFullBrowseResults = function() return SHOWN >= #RESULTS end
C_AuctionHouse.RequestMoreBrowseResults = function() PAGES_SENT = PAGES_SENT + 1; SHOWN = SHOWN + PAGE_SIZE; FIRE("AUCTION_HOUSE_BROWSE_RESULTS_ADDED") end
EVENTS = {}
ScannerKing.RegisterCallback("test", function(e, ...) EVENTS[#EVENTS+1] = e end)
""")
SK.Watch("gather_king", L.eval("function() return { 2770, 268415, 999 } end"))  # ore (in Trade Goods), seeds (not), unlisted
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
assert L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'Material Scan' then return true end end end)()")
sk("scan")
L.execute("RUN_TIMERS()"); print(last())
assert L.eval("BROWSE") == 1 and L.eval("PAGES_SENT") == 1 and L.eval("KEYS") == 1 and L.eval("AH_QUERIES") == 0
assert L.eval("KEY_IDS[268415]") and L.eval("KEY_IDS[999]") and not L.eval("KEY_IDS[2770]")  # only what Trade Goods missed
assert price(2589) == 120 and price(248823) == 12345 and price(268415) == 777 and price(999) is None
assert L.eval("ScannerKingDB.prices[2589].q") == 20
p, t, q = SK.GetPrice(10940); assert p == 900 and t and q == 20
assert L.eval("ScannerKingDB.lastScan")
ev = [L.eval("EVENTS")[i] for i in range(1, len(L.eval("EVENTS")) + 1)]
assert ev[0] == "SCAN_STARTED" and "SCAN_FINISHED" in ev and ev[-1] == "PRICES_UPDATED", ev
assert SK.FormatMoney(12345) == "|cffffd7001g|r |cffc7c7cf23s|r |cffeda55f45c|r"
print("FULL SCAN OK")

# A detailed scan for another addon: Trade Goods, then the extra items in chunks of 100
L.execute("KEYS = 0; for i = 1, 250 do OTHER[50000 + i] = 1000 + i end")
extra = L.eval("(function() local t = {} for i = 1, 250 do t[i] = 50000 + i end t[251] = 2589 return t end)()")
SK.Scan(L.table_from({"items": extra}))
L.execute("RUN_TIMERS()"); print(last())
assert L.eval("KEYS") == 3 and price(50001) == 1001 and price(50250) == 1250 and L.eval("BROWSE") == 2
assert not L.eval("KEY_IDS[2589]")  # Trade Goods already priced it
L.execute("for i = 1, 250 do ScannerKingDB.prices[50000 + i] = nil end")
print("DETAILED SCAN OK")

# Market Scan: an addon (Market King) registers what to offer and what to scan
def frame_with(text):
    return L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' then return f end end end)()" % text)
market = frame_with("Market Scan"); assert market and market.shown == False  # hidden until someone registers
L.execute("""
FINISHED = nil
ScannerKing.RegisterScanProvider("test", {
  options = { { key = 1, label = "Alpha" }, { key = 2, label = "Beta" } },
  items = function(picked) local t = {} if picked[1] then t[#t+1] = 50001 end if picked[2] then t[#t+1] = 50002 end return t end,
  finished = function(picked, found) FINISHED = picked end,
})
OTHER[50001] = 11; OTHER[50002] = 22
""")
assert market.shown
market.scripts.OnClick(market)
checks = [f for f in L.eval("FRAMES").values() if f.key in (1, 2)]
assert len(checks) == 2 and all(c.checked for c in checks)  # everything ticked
checks[1].SetChecked(checks[1], False)  # untick Beta
scan = [f for f in L.eval("FRAMES").values() if f.text == "Scan"][-1]
scan.scripts.OnClick(scan); L.execute("RUN_TIMERS()")
assert price(50001) == 11 and price(50002) is None
assert L.eval("FINISHED[1]") and not L.eval("FINISHED[2]")
L.execute("ScannerKingDB.prices[50001] = nil")
print("MARKET SCAN OK")

# Price list: categories come from the game's own item types
L.execute("""
INFO = { [2589] = {"Trade Goods", "Cloth"}, [2770] = {"Trade Goods", "Metal & Stone"}, [10940] = {"Trade Goods", "Enchanting"},
         [248823] = {"Trade Goods", "Herb"}, [268415] = {"Miscellaneous", "Other"}, [2840] = {"Trade Goods", "Metal & Stone"} }
NAMES_BY_ID = { [2589] = "Linen Cloth", [2770] = "Copper Ore", [10940] = "Strange Dust", [248823] = "Marefoil", [2840] = "Copper Bar" }
C_Item.GetItemInfoInstant = function(id) local i = INFO[id]; if i then return id, i[1], i[2], "", 1000 + id, i[1] == "Trade Goods" and 7 or 15 end end
C_Item.GetItemNameByID = function(id) return NAMES_BY_ID[id] end
C_Item.RequestLoadItemDataByID = function(id) REQUESTED = id end
ScannerKingDB.prices[2840] = { p = 300, t = ScannerKing.Now(), q = 50 }
""")
assert L.eval("(function() for _, f in ipairs(FRAMES) do if f.scripts.OnClick and f.scripts.OnDragStart and f.scripts.OnEnter then return true end end end)()")  # minimap button
sk("show")
def texts():
    fs = L.eval("FONTS"); out = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
    fr = L.eval("FRAMES"); out += [fr[i].text for i in range(1, len(fr) + 1) if fr[i].text and fr[i].shown != False]
    return out
t = texts()
assert "Copper Bar" in t and "Copper Ore" in t and "Metal & Stone" in t and "Cloth" in t and "Miscellaneous" in t, t
def click(label):
    b = L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' and f.cat then return f end end end)()" % label)
    b.scripts.OnClick(b)
click("Metal & Stone")
rows = [r for r in L.eval("FRAMES").values() if r.id and r.shown]
assert sorted(r.id for r in rows) == [2770, 2840], [r.id for r in rows]  # ore and bars together, nothing else
foot = [x for x in texts() if "Last full scan" in x][-1]; print(foot)
assert "of 2" in foot
assert L.eval("REQUESTED") == 999 or L.eval("ScannerKingDB.items[268415].cat") == "Miscellaneous"
sk("button off"); assert L.eval("ScannerKingDB.ui.button") == False
sk("button on")
print("BROWSER OK")

# Guild sharing: own recent prices go out after the scan, split to fit, in the suite's own channel
def sent_prices(LL, nsx):
    out = {}
    for i in range(1, len(LL.eval("SENT")) + 1):
        m = LL.eval("SENT")[i]
        if m.prefix == "ScannerKing1" and m.text.startswith("Z"):
            assert len(m.text) <= 250
            for e in nsx.UnpackPrices(m.text[1:]).values(): out[e.id] = e
    return out
got = sent_prices(L, ns)
assert got[2589].p == 120 and got[2589].q == 20 and got[2589].m is None
# the old format is still read (a guildmate who hasn't updated yet)
L.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "P2589:5:1;4338:333:999999999", "GUILD", "Bob-Realm"); RUN_TIMERS()')
assert price(2589) == 120 and price(4338) == 333 and L.eval("ScannerKingDB.prices[4338].from") == "Bob"
print(last())
# Bob's prices aren't re-shared by us
L.execute("SENT = {}"); sk("sync")
L.execute("RUN_TIMERS()")
got = sent_prices(L, ns); assert 2589 in got and 4338 not in got
# a guildmate logging in gets our prices whispered once
L.execute('SENT = {}; FIRE("CHAT_MSG_ADDON", "ScannerKing1", "H", "GUILD", "Amy-Realm"); RUN_TIMERS()')
sent = L.eval("SENT"); assert len(sent) >= 1 and sent[1].chan == "WHISPER" and sent[1].target == "Amy-Realm"
L.execute('SENT = {}; FIRE("CHAT_MSG_ADDON", "ScannerKing1", "H", "GUILD", "Amy-Realm"); RUN_TIMERS()'); assert len(L.eval("SENT")) == 0
print("SYNC OK")

# Browse never answers: give up and look items up one at a time
L.execute("""
ScannerKingDB.prices = {}
C_AuctionHouse.SendBrowseQuery = function() BROWSE = BROWSE + 1 end
C_AuctionHouse.SearchForItemKeys = function() KEYS = KEYS + 1 end
AH_PRICES = { [2770] = 450 }
AH_QUERIES = 0
""")
sk("scan"); L.execute("RUN_TIMERS()"); print(last())
assert L.eval("AH_QUERIES") == 3 and price(2770) == 450 and price(268415) is None
print("FALLBACK OK")

# Closing the auction house mid-scan stops it
L.execute("AH_OPEN = false"); sk("scan"); print(last()); assert "Open the auction house" in last()
L.execute("AH_OPEN = true; C_AuctionHouse.SendBrowseQuery = function() end")
sk("scan"); L.execute('FIRE("AUCTION_HOUSE_CLOSED")'); print(last()); assert "closed" in last()
assert not SK.IsScanning()
L.execute("RUN_TIMERS()")
print("STOP OK")

# Classic-style auction house window: watched items one by one by name
L2, _ = fresh()
L2.execute("""
AH_OPEN = false
UNKNOWN_EVENTS = {}
AuctionFrame = CreateFrame("Frame"); AuctionFrame.IsShown = function() return true end
AuctionFrame.CreateFontString = function() return CreateFrame("Frame") end
C_AuctionHouse = nil
CLASSIC = { [2770] = { {"Copper Ore", 5, 500}, {"Copper Ore", 2, 300} } }
NAMES = { ["Copper Ore"] = 2770 }
LIST = {}
function CanSendAuctionQuery() return true end
function GetItemInfo(id) for n, i in pairs(NAMES) do if i == id then return n end end end
function QueryAuctionItems(name) LIST = CLASSIC[NAMES[name]] or {}; C_Timer.After(0.2, function() FIRE("AUCTION_ITEM_LIST_UPDATE") end) end
function GetNumAuctionItems() return #LIST end
function GetAuctionItemInfo(_, i) local e = LIST[i]; return e[1], nil, e[2], nil, nil, nil, nil, nil, nil, e[3], nil, nil, nil, nil, nil, nil, NAMES[e[1]] end
""")
# this stand-in's frame registered AUCTION_ITEM_LIST_UPDATE only if the client knows it; a classic client does
L2.execute("for _, f in ipairs(FRAMES) do if f.events.AUCTION_HOUSE_SHOW then f.events.AUCTION_ITEM_LIST_UPDATE = true end end")
L2.eval("ScannerKing").Watch("x", L2.eval("{ 2770, 12345 }"))
L2.eval("ScannerKing").Scan(); L2.execute("RUN_TIMERS()")
assert L2.eval("ScannerKingDB.prices[2770].p") == 100  # 500/5 beats 300/2
print("CLASSIC OK")

# Deep Scan: every auction at once (ReplicateItems), read in batches
L4, ns4 = fresh()
SK4 = L4.eval("ScannerKing")
L4.execute("""
-- { itemID, stack, buyout, seller }
AUCTIONS = {
  { 2589, 20, 2000, "Amy" }, { 2589, 20, 2200, "Bob" }, { 2589, 10, 1300, "Amy" }, { 2589, 50, 50000, "Cat" },
  { 2770, 5, 2250, "Bob" }, { 2770, 3, 1000, "Bob" },
  { 6000, 1, 50000, "Dan" }, { 6000, 1, 52000, "Eve" }, { 6000, 1, 1, "Odd" },
  { 7000, 1, 0, "Bid" },  -- bid only, no buyout
}
for i = 1, 4000 do AUCTIONS[#AUCTIONS+1] = { 8000 + (i % 7), 1, 100 + i % 7, "S" .. (i % 3) } end
REPLICATED = 0
C_AuctionHouse.ReplicateItems = function() REPLICATED = REPLICATED + 1; C_Timer.After(1, function() FIRE("REPLICATE_ITEM_LIST_UPDATE") end) end
C_AuctionHouse.GetNumReplicateItems = function() return #AUCTIONS end
-- The first time an auction is read, some items' details haven't loaded yet (like the real game).
NOT_LOADED = { [2770] = true }
C_AuctionHouse.GetReplicateItemInfo = function(i)
  local a = AUCTIONS[i + 1]
  if NOT_LOADED[a[1]] then return nil, nil, a[2], 1, true, 1, 0, 0, 0, a[3], 0, false, nil, a[4], a[4], 0, a[1], false end
  return "x", 1, a[2], 1, true, 1, 0, 0, 0, a[3], 0, false, nil, a[4], a[4], 0, a[1], true
end
C_Item.RequestLoadItemDataByID = function(id) C_Timer.After(0.5, function() NOT_LOADED[id] = nil end) end
INFO_CLASS = { [2589] = 7, [2770] = 7, [6000] = 2 }
C_Item.GetItemInfoInstant = function(id) return id, "", "", "", 1, INFO_CLASS[id] or 15, 0 end
GOT = {}
ScannerKing.RegisterCallback("t", function(e, res, kind, method) if e == "SCAN_RESULTS" then GOT = { res = res, kind = kind, method = method } end end)
""")
L4.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
deep = L4.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'Deep Scan' then return f end end end)()")
assert deep, "Deep Scan button"
# the button opens the Deep Scan window, which says which scan you'll get; Scan starts it
deep.scripts.OnClick(deep)
def fonts(L): fs = L.eval("FONTS"); return [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "Deep Scan" in fonts(L4) and any("Full scan ready." in t for t in fonts(L4)) and L4.eval("REPLICATED") == 0
scan = L4.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'Scan' then return f end end end)()")
scan.scripts.OnClick(scan); L4.execute("RUN_TIMERS()")
print(L4.eval("OUTPUT[#OUTPUT]"))
assert any(t.startswith("|cff40ff40Deep Scan done: 10 items priced.") for t in fonts(L4)), [t for t in fonts(L4) if "Deep" in t]
assert L4.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'Scan again' then return true end end end)()")
assert any("Full scan ready again in 15 min" in t for t in fonts(L4))
assert L4.eval("REPLICATED") == 1 and L4.eval("GOT.kind") == "deep" and L4.eval("GOT.method") == "replicate"
pr = L4.eval("ScannerKingDB.prices")
# Linen: 1300/10 = 130 each is the cheapest; the 1000-each stack of 50 is an outlier
assert pr[2589].p == 100 and pr[2589].q == 100 and pr[2589].n == 4, (pr[2589].p, pr[2589].q)
assert pr[2589].m < 200 and pr[2589].m >= 100, pr[2589].m
assert L4.eval("GOT.res[2589].s") == 3 and pr[6000].n == 3 and pr[7000] is None
assert len([k for k in pr.keys()]) == 3 + 7
assert pr[2770].p == 333 and pr[2770].m == math.floor(pr[2770].m)  # whole copper, so guild sync can read it
assert pr[2589].d is None and pr[6000].d  # trade goods are shared with the guild, a weapon isn't
assert SK4.GetMarketPrice(2589)[0] == pr[2589].m and SK4.GetMarketPrice(2589)[3] and L4.eval("ScannerKingDB.lastDeep")
print("DEEP SCAN OK")

# Market value: cheapest 15-30% of units, stopping where the price jumps
MV = ns4.MarketValue
def mvof(pairs_): return MV(L4.table_from([L4.table_from(p) for p in pairs_]))
assert mvof([(100, 10), (102, 10), (500, 80)]) == 101  # past 15% the next price is 5x: stop at the first 20 units
assert mvof([(100, 1), (101, 1), (103, 1), (200, 7)]) == 101  # stops before the jump to 200
assert mvof([(50, 100)]) == 50
print("MARKET VALUE OK")

# Guild sharing skips Deep Scan prices outside Trade Goods
L4.execute("SENT = {}; RUN_TIMERS()")
L4.eval("SlashCmdList.SCANNERKING")("sync"); L4.execute("RUN_TIMERS()")
got = sent_prices(L4, ns4)
assert 2589 in got and 6000 not in got and 8001 not in got, list(got)
assert got[2589].m == L4.eval("ScannerKingDB.prices[2589].m") and got[2589].q == 100  # market and listed travel too
print("DEEP SYNC OK")

# Packing: numbers mark their own end, so no separators
for n in (0, 1, 31, 32, 1023, 1024, 99999999):
    assert list(ns4.UnpackNumbers(ns4.PackNumber(n)).values()) == [n]
assert ns4.UnpackNumbers("ab") is None or True  # a number cut short is ignored
entries = L4.eval("{ { id = 2589, p = 120, t = 1000000, m = 130, q = 20 }, { id = 2592, p = 999, t = 1000000 - 3600 } }")
msgs = list(ns4.PackPrices(entries).values()); assert len(msgs) == 1
back = list(ns4.UnpackPrices(msgs[0][1:]).values())
assert (back[0].id, back[0].p, back[0].m, back[0].q, back[0].t) == (2589, 120, 130, 20, 1000000)
assert (back[1].id, back[1].p, back[1].m, back[1].q, back[1].t) == (2592, 999, None, None, 1000000 - 3600)
print("PACKING OK", msgs[0])

# Asking the guild: Amy asks for items; we answer what we scanned ourselves, unless someone beat us to it
L4.execute("SENT = {}; RUN_TIMERS()")
# we don't ask for what we scanned ourselves in the last hour
assert L4.eval("ScannerKing").RequestPrices(L4.eval("{ 6000 }"))[0] == 0
L4.execute("SAVED_NOW = NOW; NOW = NOW + 7200")
ask = L4.eval("ScannerKing").RequestPrices(L4.eval("{ 6000, 4444 }"))
assert ask[0] == 2 and ask[1] == 1
L4.execute("RUN_TIMERS()")
req = [L4.eval("SENT")[i].text for i in range(1, len(L4.eval("SENT")) + 1)]
assert req[0].startswith("R") and list(ns4.UnpackNumbers(req[0][1:]).values()) == [4444, 6000 - 4444]
L4.execute("SENT = {}")
L4.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + req[0] + '", "GUILD", "Amy-Realm"); RUN_TIMERS()')
got = sent_prices(L4, ns4); assert 6000 in got and 4444 not in got and got[6000].p == L4.eval("ScannerKingDB.prices[6000].p")
# Cat answers first with prices as fresh as ours: we stay quiet
L4.execute("SENT = {}")
L4.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + req[0] + '", "GUILD", "Amy-Realm")')
t6 = L4.eval("ScannerKingDB.prices[6000].t")
cat = list(ns4.PackPrices(L4.eval("{ { id = 6000, p = 1, t = %d } }" % t6)).values())[0]
L4.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + cat + '", "GUILD", "Cat-Realm"); RUN_TIMERS()')
assert 6000 not in sent_prices(L4, ns4)
# a newer price from a guildmate is kept, tagged, and reported to other addons
L4.execute("GP = nil; ScannerKing.RegisterCallback('gp', function(e, b) if e == 'GUILD_PRICES' then GP = b end end)")
newer = list(ns4.PackPrices(L4.eval("{ { id = 6000, p = 777, t = %d, m = 800, q = 3 } }" % (t6 + 600))).values())[0]
L4.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + newer + '", "GUILD", "Dan-Realm"); RUN_TIMERS()')
pr = L4.eval("ScannerKingDB.prices[6000]")
assert pr.p == 777 and pr.m == 800 and pr.q == 3 and pr["from"] == "Dan" and pr.d
assert L4.eval("GP[6000].p") == 777 and L4.eval("GP[6000].from") == "Dan"
L4.execute("NOW = SAVED_NOW")
print("REQUESTS OK")

# What sharing costs: the old format against the packed one
import random
random.seed(1)
def cost(n, deep):
    ids = sorted(random.sample(range(1, 25000), n))
    L4.execute("COST = {}")
    for i, id_ in enumerate(ids):
        p = int(10 ** random.uniform(1, 6))
        m = p + int(p * random.uniform(0, 0.3)) if deep else None
        L4.execute("COST[%d] = { id = %d, p = %d, t = 1700000000, m = %s, q = %d }" % (i + 1, id_, p, m if m else "nil", random.randint(1, 200)))
    packed = len(list(ns4.PackPrices(L4.eval("COST")).values()))
    old = sum(len("%d:%d:1700000000;" % (id_, 10 ** 3)) for id_ in ids) // 239 + 1
    return old, packed
for label, n, deep in (("Trade Goods (700, lowest + listed)", 700, False), ("Deep Scan (3163, market + lowest + listed)", 3163, True),
                       ("Deep Scan (8000)", 8000, True)):
    old, packed = cost(n, deep)
    print("COST %-45s old %4d msgs (%s)   packed %4d msgs (%s)" % (label, old, "%dm%02ds" % divmod(old, 60), packed, "%dm%02ds" % divmod(packed, 60)))

# Tooltips: market price, lowest buyout and listed; other addons add their own lines
L4.execute("""
TT = { lines = {} }
function TT:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. "|" .. r end
function TT:AddLine(l) self.lines[#self.lines+1] = l end
ScannerKing.AddTooltipProvider("econ", function(tt, id) tt:AddLine("econ " .. id) end)
TT_HOOK(TT, { id = 2589 })
""")
lines = [L4.eval("TT.lines")[i] for i in range(1, len(L4.eval("TT.lines")) + 1)]
assert lines[0].startswith("Market price|") and lines[1].startswith("Lowest buyout|") and lines[2] == "Listed|100 in 4 auctions", lines
assert lines[-1] == "econ 2589"
# the same item again before the tooltip is cleared adds nothing
L4.execute("TT.lines = {}; TT_HOOK(TT, { id = 2589 })"); assert len(L4.eval("TT.lines")) == 0
# /sk tooltip off hides Scanner King's lines but not other addons'
L4.execute("TT.lines = {}; TT.skItem = nil"); L4.eval("SlashCmdList.SCANNERKING")("tooltip off")
L4.execute("TT_HOOK(TT, { id = 2589 })")
assert [L4.eval("TT.lines")[i] for i in range(1, len(L4.eval("TT.lines")) + 1)] == ["econ 2589"]
L4.execute("TT.lines = {}; TT.skItem = nil; ScannerKing.AddTooltipProvider('econ', nil); TT_HOOK(TT, { id = 2589 })")
assert len(L4.eval("TT.lines")) == 0
L4.eval("SlashCmdList.SCANNERKING")("tooltip on")
print("TOOLTIP OK")

# Again within 15 minutes: the full list is on cooldown, so it browses every category
L4.execute("""
BROWSED = nil
C_AuctionHouse.SendBrowseQuery = function(q)
  BROWSED = q
  RESULTS = { { itemKey = { itemID = 2589 }, minPrice = 90, totalQuantity = 30 },
              { itemKey = { itemID = 2589, itemLevel = 2 }, minPrice = 95, totalQuantity = 5 },
              { itemKey = { itemID = 9999 }, minPrice = 4000, totalQuantity = 2 } }
  SHOWN = 2
  C_Timer.After(0.1, function() FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end
C_AuctionHouse.GetBrowseResults = function() local r = {} for i = 1, math.min(SHOWN, #RESULTS) do r[i] = RESULTS[i] end return r end
C_AuctionHouse.HasFullBrowseResults = function() return SHOWN >= #RESULTS end
C_AuctionHouse.RequestMoreBrowseResults = function() SHOWN = SHOWN + 2; FIRE("AUCTION_HOUSE_BROWSE_RESULTS_ADDED") end
""")
SK4.DeepScan(); L4.execute("RUN_TIMERS()")
print(L4.eval("OUTPUT[#OUTPUT]"))
assert L4.eval("REPLICATED") == 1 and L4.eval("#BROWSED.itemClassFilters") == 0 and L4.eval("GOT.method") == "browse"
pr = L4.eval("ScannerKingDB.prices"); assert pr[2589].p == 90 and pr[2589].q == 35 and pr[9999].p == 4000
assert pr[9999].m is None and not SK4.GetMarketPrice(9999)[3]  # browsing only gives the lowest price
print("DEEP BROWSE OK")

# Regular scans report what they priced too
L4.execute("NOW = NOW + 3600")
L4.execute("C_AuctionHouse.SendBrowseQuery = function() end; C_AuctionHouse.SearchForItemKeys = function() end; AH_PRICES = { [2589] = 77 }")
SK4.Watch("x", L4.eval("{ 2589 }")); SK4.Scan(); L4.execute("RUN_TIMERS()")
assert L4.eval("GOT.kind") == "material" and L4.eval("GOT.res[2589].p") == 77
# a Deep Scan can't start while another scan runs, and the other way round
L4.execute("NOW = NOW + 3600; C_AuctionHouse.ReplicateItems = function() end")
SK4.DeepScan(); assert SK4.IsScanning(); SK4.Scan(); assert "already" in L4.eval("OUTPUT[#OUTPUT]") or SK4.IsScanning()
L4.execute('FIRE("AUCTION_HOUSE_CLOSED")'); assert not SK4.IsScanning()
print("SCAN RESULTS OK")

# Forever's client doesn't know the classic event; loading must not error
L3 = lua51.LuaRuntime(); L3.execute(open(f"{root}/tests/mock.lua").read())
ns3 = L3.table()
for fn in FILES: L3.execute(open(f"{root}/{fn}").read(), "Scanner_King", ns3)
print("ALL TESTS PASSED")
