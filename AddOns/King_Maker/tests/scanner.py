# Scanner (was Scanner King): the one Scan (full or quick), Deep Scan, scan providers, guild sync, tooltips, /sk
# and the Prices page.
import os, sys, math, random; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# Finders for King Maker widgets: UI.Button keeps its text on b.label (a font string).
HELPERS = """
function BTN(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then return f end end end
function BTNS(text) local r = {} for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then r[#r+1] = f end end return r end
function HASFONT(s) for _, t in ipairs(FONTS) do if t.text and tostring(t.text):find(s, 1, true) then return true end end return false end
"""


def load():
    L, KM = fresh(only=["Scanner"], extra=HELPERS)
    return L, KM, KM.mods.Scanner


def fonts(L):
    fs = L.eval("FONTS")
    return [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]


def hover(LL, b):
    """The tooltip lines a hover over button b shows."""
    LL.execute("GameTooltip.lines = {}")
    b.RunScript(b, "OnEnter")
    lines = LL.eval("GameTooltip.lines")
    return [str(lines[i]) for i in range(1, len(lines) + 1)]


L, KM, ns = load()
SK = L.eval("ScannerKing")
sk = L.eval("SlashCmdList.SCANNERKING")
assert SK.API_VERSION == 1 and SK.ready
assert L.eval("ScannerKingDB.ui.tooltip") is True and L.eval("ScannerKingDB.sync.guild") is True
assert L.eval("ScannerKingMinimapButton") is None, "no minimap button of its own"


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
EVENTS, KIND = {}, nil
ScannerKing.RegisterCallback("test", function(e, res, kind) EVENTS[#EVENTS+1] = e; if e == "SCAN_RESULTS" then KIND = kind end end)
""")
SK.Watch("gather_king", L.eval("function() return { 2770, 268415, 999 } end"))  # ore (in Trade Goods), seeds (not), unlisted
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
tb = ns.TitleButtons()
assert tb and tb.scan.label.text == "Scan", "one Scan button in the title bar"
for old in ("Material Scan", "Market Scan", "Deep Scan"):
    assert len(L.eval("BTNS('%s')" % old)) == 0, old + " button is gone"
L.globals().SKNS = ns
assert L.eval("SKNS.TitleButtons().scan.parent == AuctionHouseFrame") and tb.scan.template is None, "King Maker button, no Blizzard template"
# no ReplicateItems on this client: a click is always a quick scan of Trade Goods plus the 3 watched items
tip = hover(L, tb.scan)
assert tip[0] == "Scan" and any("A click does a quick scan of Trade Goods plus 3 items." in x for x in tip), tip
assert any("3 watched" in x for x in tip) and any("Last full scan: never" in x for x in tip), tip
sk("scan")
assert tb.scan.label.text == "Scanning..." and not tb.scan.enabled2, "the button shows progress"
assert any("Trade Goods" in x for x in hover(L, tb.scan)), "the tooltip follows the scan"
L.execute("RUN_TIMERS()")
assert "Scan done" in last(L) and "King Maker" in last(L), last(L)
assert L.eval("BROWSE") == 1 and L.eval("PAGES_SENT") == 1 and L.eval("KEYS") == 1 and L.eval("AH_QUERIES") == 0
assert L.eval("KEY_IDS[268415]") and L.eval("KEY_IDS[999]") and not L.eval("KEY_IDS[2770]")  # only what Trade Goods missed
assert price(2589) == 120 and price(248823) == 12345 and price(268415) == 777 and price(999) is None
assert L.eval("ScannerKingDB.prices[2589].q") == 20
p, t, q = SK.GetPrice(10940); assert p == 900 and t and q == 20
assert L.eval("ScannerKingDB.lastScan") and L.eval("ScannerKingDB.lastQuick") and L.eval("KIND") == "material"
assert tb.scan.label.text == "Scan" and tb.scan.enabled2, "button back to rest after the scan"
assert any("Last quick scan: just now" in x for x in hover(L, tb.scan))
ev = [L.eval("EVENTS")[i] for i in range(1, len(L.eval("EVENTS")) + 1)]
assert ev[0] == "SCAN_STARTED" and "SCAN_FINISHED" in ev and ev[-1] == "PRICES_UPDATED", ev
assert SK.FormatMoney(12345) == "|cffffd7001g|r |cffc7c7cf23s|r |cffeda55f45c|r"
print("FULL SCAN OK")

# A detailed scan for another module: Trade Goods, then the extra items in chunks of 100
L.execute("KEYS = 0; for i = 1, 250 do OTHER[50000 + i] = 1000 + i end")
extra = L.eval("(function() local t = {} for i = 1, 250 do t[i] = 50000 + i end t[251] = 2589 return t end)()")
SK.Scan(L.table_from({"items": extra}))
L.execute("RUN_TIMERS()")
assert L.eval("KEYS") == 3 and price(50001) == 1001 and price(50250) == 1250 and L.eval("BROWSE") == 2
assert not L.eval("KEY_IDS[2589]")  # Trade Goods already priced it
L.execute("for i = 1, 250 do ScannerKingDB.prices[50000 + i] = nil end")
print("DETAILED SCAN OK")

# Scan providers: a module (Market) says what it has selected; every quick scan prices it. No picker.
L.execute('KingMakerMinimapButton:Click("RightButton")')
for old in ("Material Scan", "Market Scan", "Deep Scan"):
    assert L.eval('MENU_ITEM("%s")' % old) is None, old + " quick action is gone"
assert L.eval('MENU_ITEM("Scan") ~= nil'), "one Scan quick action at the auction house"
L.execute("""
FINISHED, ASKED = nil, nil
SEL = { [1] = true }
ScannerKing.RegisterScanProvider("test", {
  options = { { key = 1, label = "Alpha" }, { key = 2, label = "Beta" } },
  items = function(picked) ASKED = picked; local t = {} if picked[1] then t[#t+1] = 50001 end if picked[2] then t[#t+1] = 50002 end return t end,
  selected = function() return SEL end,
  finished = function(picked, found) FINISHED = picked end,
})
OTHER[50001] = 11; OTHER[50002] = 22
""")
tip = hover(L, tb.scan)
assert any("quick scan of Trade Goods plus 4 items." in x for x in tip), tip
assert any("1 more for the 1 profession(s) ticked on Crafting Profits" in x for x in tip), tip
tb.scan.Click(tb.scan); L.execute("RUN_TIMERS()")
assert L.eval("ScannerKingMarketScan") is None, "no picker dialog"
assert price(50001) == 11 and price(50002) is None and price(268415) == 777, "selected items plus watched ones"
assert L.eval("KIND") == "market" and L.eval("FINISHED[1]") and not L.eval("FINISHED[2]")
# nothing selected: a plain Trade Goods + watched scan (kind material), the provider isn't told
L.execute("SEL = {}; FINISHED = nil; ScannerKingDB.prices[50001] = nil")
SK.QuickScan(); L.execute("RUN_TIMERS()")
assert L.eval("KIND") == "material" and price(50001) is None and L.eval("FINISHED") is None
# /sk market forces the provider's items; with nothing ticked it says where to tick them
sk("market"); assert "Crafting Profits" in last(L), last(L)
L.execute("SEL = { [2] = true }"); sk("market"); L.execute("RUN_TIMERS()")
assert L.eval("KIND") == "market" and price(50002) == 22 and L.eval("FINISHED[2]")
# /sk material forces Trade Goods + watched only, whatever is selected
L.execute("ScannerKingDB.prices[50002] = nil"); sk("material"); L.execute("RUN_TIMERS()")
assert L.eval("KIND") == "material" and price(50002) is None
# OpenMarketScan (old API) runs the one scan at the auction house
L.execute("ScannerKingDB.prices[50002] = nil"); SK.OpenMarketScan(); L.execute("RUN_TIMERS()")
assert price(50002) == 22 and L.eval("ScannerKingMarketScan") is None
# a provider without `selected` counts every option, like the old picker's defaults
L.execute("""
ScannerKingDB.prices[50001] = nil; ScannerKingDB.prices[50002] = nil
ScannerKing.RegisterScanProvider("test", { options = { { key = 1, label = "Alpha" }, { key = 2, label = "Beta" } },
  items = function(picked) local t = {} if picked[1] then t[#t+1] = 50001 end if picked[2] then t[#t+1] = 50002 end return t end })
""")
sk("scan"); L.execute("RUN_TIMERS()")
assert price(50001) == 11 and price(50002) == 22
L.execute("ScannerKingDB.prices[50001] = nil; ScannerKingDB.prices[50002] = nil; OTHER[50001] = nil; OTHER[50002] = nil")
L.execute('ScannerKing.RegisterScanProvider("test", { options = {}, items = function() return {} end, selected = function() return {} end })')
print("PROVIDERS OK")

# The Prices page: categories come from the game's own item types
L.execute("""
INFO = { [2589] = {"Trade Goods", "Cloth"}, [2770] = {"Trade Goods", "Metal & Stone"}, [10940] = {"Trade Goods", "Enchanting"},
         [248823] = {"Trade Goods", "Herb"}, [268415] = {"Miscellaneous", "Other"}, [2840] = {"Trade Goods", "Metal & Stone"} }
NAMES_BY_ID = { [2589] = "Linen Cloth", [2770] = "Copper Ore", [10940] = "Strange Dust", [248823] = "Marefoil", [2840] = "Copper Bar" }
C_Item.GetItemInfoInstant = function(id) local i = INFO[id]; if i then return id, i[1], i[2], "", 1000 + id, i[1] == "Trade Goods" and 7 or 15 end end
C_Item.GetItemNameByID = function(id) return NAMES_BY_ID[id] end
C_Item.RequestLoadItemDataByID = function(id) REQUESTED = id end
ScannerKingDB.prices[2840] = { p = 300, t = ScannerKing.Now(), q = 50 }
""")
sk("show")
assert KM.IsShown("prices") and not KM.errorShown, last(L)
c = ns.PricesPage()
names = sorted(e.name for e in ns.PriceList().values())
assert names == ["Copper Bar", "Copper Ore", "Item 268415", "Linen Cloth", "Marefoil", "Strange Dust"], names
cats = [b.cat for b in c.catButtons.values() if b.cat]
assert cats[0] == "All" and "Metal & Stone" in cats and "Cloth" in cats and "Miscellaneous" in cats, cats
t = fonts(L)
assert "Copper Bar" in t and "Copper Ore" in t, t                          # rows fill
assert any("PRICES KNOWN" == x for x in t) and "6" in t, "tiles"
first = [e.id for e in ns.PriceList().values()]
assert first[0] == 248823, first                                          # sorted by price, dearest first
b = [b for b in c.catButtons.values() if b.cat == "Metal & Stone"][0]
b.Click(b)
assert sorted(e.id for e in ns.PriceList().values()) == [2770, 2840]       # ore and bars together, nothing else
assert b.active, "the picked category is marked"
foot = c.footer.text
assert "of 2" in foot and "(6 in all)" in foot, foot
assert L.eval("REQUESTED") == 999 or L.eval("ScannerKingDB.items[268415].cat") == "Miscellaneous"
# search filters, within the category, then across All
c.search.SetText(c.search, "bar"); c.search.RunScript(c.search, "OnTextChanged", True)
assert [e.id for e in ns.PriceList().values()] == [2840]
all_ = [b for b in c.catButtons.values() if b.cat == "All"][0]; all_.Click(all_)
c.search.SetText(c.search, "copper"); c.search.RunScript(c.search, "OnTextChanged", True)
assert sorted(e.id for e in ns.PriceList().values()) == [2770, 2840]
# a header click sorts by that column
h = c.table.headers.name
h.RunScript(h, "OnClick")
assert [e.name for e in ns.PriceList().values()] == ["Copper Bar", "Copper Ore"] and c.table.sortKey == "name"
h.RunScript(h, "OnClick")
assert [e.name for e in ns.PriceList().values()] == ["Copper Ore", "Copper Bar"]
c.search.SetText(c.search, ""); c.search.RunScript(c.search, "OnTextChanged", True)
assert len(ns.PriceList()) == 6
# the toolbar has one Scan: it works at the auction house, and its tooltip says what a click does
assert c.scan.enabled2 and c.scan.label.text == "Scan" and c.mat is None and c.deep is None and c.market is None
assert any("quick scan of Trade Goods" in x for x in hover(L, c.scan))
sk("show"); assert not KM.IsShown(), "/sk toggles the page closed"
SK.ToggleBrowser(True); assert KM.IsShown("prices")
SK.ToggleBrowser(False); assert not KM.IsShown()
sk("button off"); assert "crown" in last(L), last(L)
assert not KM.errorShown
print("PRICES PAGE OK")

# The crown, the sidebar status, Home and Settings
L.execute('KingMakerMinimapButton:Click("RightButton")')
for label in ("Scan", "Prices"):
    assert L.eval('MENU_ITEM("%s") ~= nil' % label), label
L.execute('MENU_ITEM("Prices").fn()'); assert KM.IsShown("prices")
assert L.eval("HASFONT('Prices: no full scan yet, quick')"), "status line: no full scan, a quick one just now"
L.execute('KingMakerMinimapButton:RunScript("OnEnter")')
tip = list(L.eval("GameTooltip.lines").values())
assert any("prices. Full scan: never. Quick scan:" in str(x) for x in tip), tip
L.execute("AH_OPEN = false"); L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Scan")') is None, "Scan only at the auction house"
KM.Show("prices"); c = ns.PricesPage()
assert not c.scan.enabled2 and any("Open the auction house to scan." in x for x in hover(L, c.scan))
SK.OpenMarketScan(); assert "Open the auction house and click Scan" in last(L), last(L)  # old API, away from the AH
sk("scan"); assert "Open the auction house first" in last(L), last(L)
L.execute("AH_OPEN = true")
KM.Show("home"); assert not KM.errorShown, last(L)
assert "PRICES KNOWN" in fonts(L)
KM.OpenSettings("scanner"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
t = fonts(L)
assert "Prices in item tooltips" in t and "Share prices with my guild" in t and any("/sk deep" in x for x in t)
KM.Toggle(False)
print("SHELL OK")

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
assert "newer price" in last(L), last(L)
# Bob's prices aren't re-shared by us
L.execute("SENT = {}"); sk("sync")
L.execute("RUN_TIMERS()")
got = sent_prices(L, ns); assert 2589 in got and 4338 not in got
# a guildmate logging in gets our prices whispered once
L.execute('SENT = {}; FIRE("CHAT_MSG_ADDON", "ScannerKing1", "H", "GUILD", "Amy-Realm"); RUN_TIMERS()')
sent = L.eval("SENT"); assert len(sent) >= 1 and sent[1].chan == "WHISPER" and sent[1].target == "Amy-Realm"
L.execute('SENT = {}; FIRE("CHAT_MSG_ADDON", "ScannerKing1", "H", "GUILD", "Amy-Realm"); RUN_TIMERS()'); assert len(L.eval("SENT")) == 0
sk("sync off"); assert L.eval("ScannerKingDB.sync.guild") is False
sk("sync on"); assert L.eval("ScannerKingDB.sync.guild") is True
print("SYNC OK")

# Browse never answers: give up and look items up one at a time
L.execute("""
ScannerKingDB.prices = {}
C_AuctionHouse.SendBrowseQuery = function() BROWSE = BROWSE + 1 end
C_AuctionHouse.SearchForItemKeys = function() KEYS = KEYS + 1 end
AH_PRICES = { [2770] = 450 }
AH_QUERIES = 0
""")
sk("scan"); L.execute("RUN_TIMERS()")
assert L.eval("AH_QUERIES") == 3 and price(2770) == 450 and price(268415) is None
print("FALLBACK OK")

# Closing the auction house mid-scan stops it
L.execute("AH_OPEN = false"); sk("scan"); assert "Open the auction house" in last(L), last(L)
L.execute("AH_OPEN = true; C_AuctionHouse.SendBrowseQuery = function() end")
sk("scan"); L.execute('FIRE("AUCTION_HOUSE_CLOSED")'); assert "closed" in last(L), last(L)
assert not SK.IsScanning()
L.execute("RUN_TIMERS()")
print("STOP OK")

# Classic-style auction house window: watched items one by one by name
L2, KM2, _ = load()
L2.execute("""
AH_OPEN = false
UNKNOWN_EVENTS = {}
AuctionFrame = CreateFrame("Frame"); AuctionFrame.IsShown = function() return true end
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
# the scan frame registered AUCTION_ITEM_LIST_UPDATE only if the client knows it; a classic client does
L2.execute("for _, f in ipairs(FRAMES) do if f.events.COMMODITY_SEARCH_RESULTS_UPDATED then f.events.AUCTION_ITEM_LIST_UPDATE = true end end")
L2.eval("ScannerKing").Watch("x", L2.eval("{ 2770, 12345 }"))
L2.eval("ScannerKing").Scan(); L2.execute("RUN_TIMERS()")
assert L2.eval("ScannerKingDB.prices[2770].p") == 100  # 500/5 beats 300/2
assert not KM2.errorShown
print("CLASSIC OK")

# Deep Scan: every auction at once (ReplicateItems), read in batches
L4, KM4, ns4 = load()
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
scanb = ns4.TitleButtons().scan
assert scanb, "Scan button"
# the full dump is available: the tooltip says so, and a click runs the Deep Scan (no dialog), progress on the button
tip = hover(L4, scanb)
assert any("Full scan ready" in x for x in tip) and L4.eval("REPLICATED") == 0, tip
assert SK4.FullScanReadyIn() == 0
scanb.Click(scanb)
assert L4.eval("REPLICATED") == 1 and SK4.IsScanning() and not scanb.enabled2
assert scanb.label.text == "Downloading every auction...", scanb.label.text
assert L4.eval("ScannerKingDeepScan") is None, "a click doesn't open the Deep Scan dialog"
L4.execute("RUN_TIMERS()")
assert any("Deep Scan done: 10 items priced." in str(o) for o in outputs(L4))
assert scanb.label.text == "Scan" and scanb.enabled2, "the title button is back to rest"
assert L4.eval("GOT.kind") == "deep" and L4.eval("GOT.method") == "replicate"
# now on cooldown: the tooltip says when the next full scan is possible, and a click does a quick scan
assert SK4.FullScanReadyIn() == 900
tip = hover(L4, scanb)
assert any("Full scan ready in 15 min; a click now does a quick scan of Trade Goods plus 0 items." in x for x in tip), tip
L4.execute("NOW = NOW + 9 * 60")
assert any("Full scan ready in 6 min" in x for x in hover(L4, scanb))
L4.execute("NOW = NOW - 9 * 60; DEEPGOT = GOT; GOT = {}")
scanb.Click(scanb); L4.execute("RUN_TIMERS()")
assert L4.eval("REPLICATED") == 1 and L4.eval("GOT.kind") == "material", "quick scan while the dump is on cooldown"
pr = L4.eval("ScannerKingDB.prices")
# Linen: 1300/10 = 130 each is the cheapest; the 1000-each stack of 50 is an outlier
assert pr[2589].p == 100 and pr[2589].q == 100 and pr[2589].n == 4, (pr[2589].p, pr[2589].q)
assert pr[2589].m < 200 and pr[2589].m >= 100, pr[2589].m
assert L4.eval("DEEPGOT.res[2589].s") == 3 and pr[6000].n == 3 and pr[7000] is None
assert len([k for k in pr.keys()]) == 3 + 7
assert pr[2770].p == 333 and pr[2770].m == math.floor(pr[2770].m)  # whole copper, so guild sync can read it
assert pr[2589].d is None and pr[6000].d  # trade goods are shared with the guild, a weapon isn't
assert SK4.GetMarketPrice(2589)[0] == pr[2589].m and SK4.GetMarketPrice(2589)[3] and L4.eval("ScannerKingDB.lastDeep")
assert SK4.LastDeepScan() == L4.eval("ScannerKingDB.lastDeep") and SK4.LastScan()
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
assert ns4.UnpackNumbers("a!") is None  # not a packed string
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
# a newer price from a guildmate is kept, tagged, and reported to other modules
L4.execute("GP = nil; ScannerKing.RegisterCallback('gp', function(e, b) if e == 'GUILD_PRICES' then GP = b end end)")
newer = list(ns4.PackPrices(L4.eval("{ { id = 6000, p = 777, t = %d, m = 800, q = 3 } }" % (t6 + 600))).values())[0]
L4.execute('FIRE("CHAT_MSG_ADDON", "ScannerKing1", "' + newer + '", "GUILD", "Dan-Realm"); RUN_TIMERS()')
pr = L4.eval("ScannerKingDB.prices[6000]")
assert pr.p == 777 and pr.m == 800 and pr.q == 3 and pr["from"] == "Dan" and pr.d
assert L4.eval("GP[6000].p") == 777 and L4.eval("GP[6000].from") == "Dan"
L4.execute("NOW = SAVED_NOW")
# MergePrice keeps only newer prices; ShareCost counts messages
assert SK4.MergePrice(6000, 5, 1, "Old") is False and SK4.MergePrice(6000, 5, t6 + 9999, "New") is True
assert SK4.ShareCost(L4.eval("{ 2589, 6000 }"))[1] == 2
print("REQUESTS OK")

# What sharing costs: the old format against the packed one
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
for label, n, deep in (("Trade Goods (700)", 700, False), ("Deep Scan (3163)", 3163, True)):
    old, packed = cost(n, deep)
    assert packed < old, (label, old, packed)

# Tooltips: market price, lowest buyout and listed; other modules add their own lines
L4.execute("""
TT = { lines = {} }
function TT:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. "|" .. r end
function TT:AddLine(l) self.lines[#self.lines+1] = l end
ScannerKing.AddTooltipProvider("econ", function(tt, id) tt:AddLine("econ " .. id) end)
TT_HOOK(TT, { id = 2589 })
""")
lines = [L4.eval("TT.lines")[i] for i in range(1, len(L4.eval("TT.lines")) + 1)]
assert lines[0] == " " and lines[1] == "King Maker| ", lines        # a gap, then the header (no vendor price: no tag)
assert lines[2].startswith("Auction house|") and ("min ago" in lines[2] or "just now" in lines[2]), lines
assert lines[3].startswith("Lowest buyout|") and lines[4] == "Listed|100 in 4 auctions", lines
assert lines[-1] == "econ 2589"
# the same item again before the tooltip is cleared adds nothing
L4.execute("TT.lines = {}; TT_HOOK(TT, { id = 2589 })"); assert len(L4.eval("TT.lines")) == 0
# /sk tooltip off hides Scanner's lines but not other modules'
L4.execute("TT.lines = {}; TT.skItem = nil"); L4.eval("SlashCmdList.SCANNERKING")("tooltip off")
assert L4.eval("ScannerKingDB.ui.tooltip") is False
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
assert "lowest prices only" in L4.eval("OUTPUT[#OUTPUT]"), L4.eval("OUTPUT[#OUTPUT]")
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
KM4.Show("prices")
assert L4.eval("HASFONT('Prices: scanning')"), "status says a scan is running"
L4.execute('FIRE("AUCTION_HOUSE_CLOSED")'); assert not SK4.IsScanning()
# /sk scan: the full dump once it's off cooldown (no dialog)
sk4 = L4.eval("SlashCmdList.SCANNERKING")
L4.execute("NOW = NOW + 3600; AH_OPEN = true; REPLICATED = 0; C_AuctionHouse.ReplicateItems = function() REPLICATED = REPLICATED + 1 end")
sk4("scan")
assert L4.eval("REPLICATED") == 1 and SK4.IsScanning() and L4.eval("ScannerKingDeepScan") is None
L4.execute('FIRE("AUCTION_HOUSE_CLOSED")'); assert not SK4.IsScanning()
# /sk material forces a quick scan even when the full dump is ready
L4.execute("NOW = NOW + 3600; AH_OPEN = true; REPLICATED = 0; GOT = {}")
sk4("material"); L4.execute("RUN_TIMERS()")
assert L4.eval("REPLICATED") == 0 and L4.eval("GOT.kind") == "material"
# /sk deep opens the progress dialog and starts; the dialog follows it to the end
L4.execute("""C_AuctionHouse.ReplicateItems = function() REPLICATED = REPLICATED + 1; C_Timer.After(1, function() FIRE("REPLICATE_ITEM_LIST_UPDATE") end) end""")
sk4("deep")
dwin = L4.eval("ScannerKingDeepScan")
assert L4.eval("REPLICATED") == 1 and SK4.IsScanning() and dwin.shown and dwin.template is None
L4.execute("RUN_TIMERS()")
assert any("Deep Scan done: 10 items priced." in t for t in fonts(L4)), [t for t in fonts(L4) if "Deep" in t]
assert L4.eval("BTN('Scan again')") is not None
assert any("Full scan ready again in 15 min" in t for t in fonts(L4))
# while the dump is on cooldown, /sk deep browses every category (lowest prices only)
L4.execute("GOT = {}; USE_AH_BROWSE({ { itemKey = { itemID = 2589 }, minPrice = 90, totalQuantity = 30 } })")
sk4("deep"); L4.execute("RUN_TIMERS()")
assert L4.eval("REPLICATED") == 1 and L4.eval("GOT.method") == "browse"
assert not KM4.errorShown, L4.eval("OUTPUT[#OUTPUT]")
print("SCAN RESULTS OK")

# /sk status and help
L4.eval("SlashCmdList.SCANNERKING")("status")
st = L4.eval("OUTPUT[#OUTPUT]"); assert "prices stored" in st and "Last full scan: just now" in st and "Full scan ready in 15 min" in st, st
L4.eval("SlashCmdList.SCANNERKING")("help")
helps = [str(o) for o in outputs(L4)]
for cmd in ("/sk scan", "/sk deep", "/sk material", "/sk market"):
    assert any(cmd in h for h in helps), cmd
assert not any("Material Scan" in h or "Market Scan" in h for h in helps)

# InitDB runs twice (Boot re-runs it after moving old data in): same table, old keys gone
L5, KM5 = fresh(only=["Scanner"], seed="ScannerKingDB = { prices = { [2589] = { p = 5, t = 900 } }, ui = { button = true, buttonAngle = 30, tooltip = false } }")
held = L5.eval("ScannerKingDB")
KM5.mods.Scanner.InitDB()
L5.globals().HELD = held
assert L5.eval("ScannerKingDB == HELD") and L5.eval("ScannerKingDB.prices[2589].p") == 5
assert L5.eval("ScannerKingDB.ui.tooltip") is False and L5.eval("ScannerKingDB.ui.button") is None
# moved in from a 1.x stub folder
L6, KM6 = fresh(only=["Scanner"], stubs={"Scanner_King": "ScannerKingDB = { prices = { [2770] = { p = 42, t = 900 } }, sync = { guild = false } }"})
assert L6.eval("ScannerKingDB.prices[2770].p") == 42 and L6.eval("ScannerKingDB.sync.guild") is False
assert L6.eval("(ScannerKing.GetPrice(2770))") == 42 and L6.eval("ScannerKingDB.ui.tooltip") is True
print("INITDB OK")

# King Maker's section with everything in it: which pays more, vendor, drops, recipes, what you own
L7, KM7 = fresh(only=["Scanner", "Econ", "Farm", "Market", "Inventory"], seed="""
ITEM(13463, "Dreamfoil", { sell = 100, class = 7, subclass = 9 })
ScannerKingDB = { prices = { [13463] = { p = 3589, m = 3594, q = 722, n = 31, t = (GetServerTime and GetServerTime() or time()) - 7200, from = "Abram Gaunt" } } }
FarmKingDB = { mobs = { [5850] = { name = "Flamebringer Stalker", k = 20, i = { [13463] = { 3, 3 } } },
  [5851] = { name = "Dust Stormer", k = 50, i = { [13463] = { 2, 2 } } }, [5852] = { name = "Scorpid", k = 10, i = { [13463] = { 1, 1 } } } } }
MarketKingDB = { learned = { [99001] = { 99002, 4, 270, { 13463, 2, 2453, 1 }, 1 } }, vendor = { [13463] = 5000 } }
InventoryKingDB = { stock = { ["Alt Two-Forever"] = { bags = { [13463] = 4 }, bank = { [13463] = 8 } } },
  chars = { ["Alt Two-Forever"] = { class = "MAGE", level = 30 } } }
""")
L7.execute("""
TT = { lines = {} }
function TT:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. "|" .. r end
function TT:AddLine(l) self.lines[#self.lines+1] = l end
TT_HOOK(TT, { id = 13463 })
""")
lines = [L7.eval("TT.lines")[i] for i in range(1, len(L7.eval("TT.lines")) + 1)]
row = lambda k: next((l for l in lines if l.startswith(k + "|")), None)
assert lines[1] == "King Maker|AUCTION" and lines[2].startswith("Pays ") and "more than vendoring" in lines[2], lines
assert "2 h ago, Abram Gaunt" in row("Auction house"), lines
assert row("Vendor") and row("Vendors sell"), lines
d = row("Drops")
assert d.index("Flamebringer Stalker") < d.index("Scorpid") < d.index("+1 more") and "15%" in d and "Dust Stormer" not in d, d
assert row("Used in").startswith("Used in|Alchemy ("), lines
assert row("You own").startswith("You own|12") and any("bags 4, bank 8" in l for l in lines), lines
order = [l.split("|")[0] for l in lines]
assert order.index("Listed") < order.index("Vendor") < order.index("Drops") < order.index("You own"), order
# a vendor pays more: VENDOR, and /sk sources off drops Vendor / Drops / Used in
L7.execute("ITEMS[13463].sell = 9000; TT.lines = {}; TT.skItem = nil; TT_HOOK(TT, { id = 13463 })")
assert L7.eval("TT.lines[2]") == "King Maker|VENDOR" and L7.eval("TT.lines[3]").startswith("Vendor it: ")
L7.eval("SlashCmdList.SCANNERKING")("sources off"); assert L7.eval("ScannerKingDB.ui.sources") is False
L7.execute("TT.lines = {}; TT.skItem = nil; TT_HOOK(TT, { id = 13463 })")
lines = [L7.eval("TT.lines")[i] for i in range(1, len(L7.eval("TT.lines")) + 1)]
assert not any(l.split("|")[0] in ("Vendor", "Drops", "Used in") for l in lines) and row("Auction house"), lines
print("SECTION OK")

# The crafting rows: best crafts, craft cost and who can craft it, recipe items, disenchant, shopping goal, Shift
L8, KM8 = fresh(only=["Scanner", "Econ", "Farm", "Market", "Skillup", "Inventory", "Shopping"], seed="""
ITEM(13463, "Dreamfoil", { sell = 100, class = 7, subclass = 9 })
ITEM(99004, "Fake Elixir", { sell = 10 }); ITEM(99006, "Fake Cloth", { sell = 10 }); ITEM(99008, "Fake Flask", { sell = 10 })
ITEM(99002, "Fake Potion", { sell = 10 })
ITEM(99100, "Green Boots", { quality = 2, ilvl = 20, class = 4, sell = 50 })
local now = (GetServerTime and GetServerTime() or time())
ScannerKingDB = { prices = {
  [13463] = { p = 3589, t = now }, [99002] = { p = 50000, t = now }, [99004] = { p = 9000, t = now },
  [99006] = { p = 100, t = now }, [99008] = { p = 30000, t = now }, [99100] = { p = 200, t = now },
  [10940] = { p = 1000, t = now }, [10939] = { p = 1000, t = now }, [10978] = { p = 1000, t = now } } }
MarketKingDB = { learned = {
  [99001] = { 99002, 4, 270, { 13463, 2, 2453, 1 }, 1 },   -- a reagent with no price: no profit, not ranked first
  [99003] = { 99004, 4, 280, { 13463, 1 }, 2 },            -- makes 2: 18000 a craft
  [99005] = { 99006, 8, 200, { 13463, 3 }, 1 },            -- a loss
  [99007] = { 99008, 4, 1, { 13463, 1 }, 1 } } }           -- the best
SkillupKingDB = { chars = { ["Alt Two-Forever"] = { known = {}, skills = { [4] = { cur = 300, max = 300 } } } } }
InventoryKingDB = { stock = { ["Alt Two-Forever"] = { bags = { [13463] = 12 } } },
  chars = { ["Alt Two-Forever"] = { class = "MAGE", level = 30 } } }
""")
L8.execute("""
TT = { lines = {} }
function TT:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. "|" .. r end
function TT:AddLine(l) self.lines[#self.lines+1] = l end
function HOVER8(id) TT.lines = {}; TT.skItem = nil; TT_HOOK(TT, { id = id }); return TT.lines end
""")
def hover8(id_):
    t = L8.eval("HOVER8(%d)" % id_)
    return [t[i] for i in range(1, len(t) + 1)]
def row8(lines, k):
    return next((l for l in lines if l.split("|")[0] == k), None)
sk8 = L8.eval("SlashCmdList.SCANNERKING")

# Dreamfoil: Used in, then the 3 best crafts, profit first (Fake Flask, Fake Elixir x2, Fake Cloth at a loss);
# Fake Potion has no profit (a reagent without a price) so it isn't in the top 3
lines = hover8(13463)
i = [l.split("|")[0] for l in lines].index("Used in")
top = lines[i + 1:i + 4]
assert "Fake Flask" in top[0] and "Fake Elixir" in top[1] and " x2" in top[1] and "Fake Cloth" in top[2], top
assert "4cff4cprofit" in top[0] and "ff5050loss" in top[2], top   # profit in green, loss in red, in words
assert not any("Fake Potion" in l for l in lines), lines

# Fake Flask: craft cost from Dreamfoil's price, the profit, and Alt Two can make it (trainer recipe, skill 300)
lines = hover8(99008)
assert row8(lines, "Cost to make") and "35" in row8(lines, "Cost to make") and "profit" in row8(lines, "Cost to make"), lines
# a material other recipes use (Fake Elixir goes into Fake Flask here): no Cost to make on it
L8.execute("MarketKingDB.learned[99009] = { 99010, 4, 1, { 99004, 1 }, 1 }"); KM8.mods.Scanner.ClearTooltipCache()
assert row8(hover8(99004), "Cost to make") is None
assert "Alt Two" in row8(lines, "You can craft it"), lines

# A recipe item: what it teaches, who knows it, who can learn it
s = KM8.mods.Skillup
spell = next(sp for sp in s.PATTERNS.keys() if s.RECIPES[sp] and s.RECIPES[sp][2] == 4 and s.RECIPES[sp][3] <= 300)
item = s.PATTERNS[spell][1]
L8.execute("ITEM(%d, 'Recipe: Something', { class = 9 })" % item)
lines = hover8(item)
assert row8(lines, "Teaches") and "Alchemy" in row8(lines, "Teaches"), lines
assert "Alt Two" in row8(lines, "Can learn it") and "(300)" in row8(lines, "Can learn it"), lines
L8.execute("SkillupKingDB.chars['Alt Two-Forever'].known[%d] = true" % spell); KM8.mods.Scanner.ClearTooltipCache()
lines = hover8(item)
assert "Alt Two" in row8(lines, "Known by") and row8(lines, "Can learn it") is None, lines

# Green boots: disenchanting pays more than the auction house and the vendor
lines = hover8(99100)
assert lines[1] == "King Maker|DISENCHANT" and lines[2].startswith("Disenchant it: about "), lines
assert row8(lines, "Disenchant").startswith("Disenchant|about "), lines

# On a shopping list: have / want
L8.execute("ShoppingKing.Add(13463, 20, nil, 'Favorites')"); KM8.mods.Scanner.ClearTooltipCache()
assert row8(hover8(13463), "Shopping list") == "Shopping list|Favorites: 12 / 20"

# /sk tip turns a row off
sk8("tip crafts off"); assert L8.eval("ScannerKingDB.ui.tip.crafts") is False
assert not any("Fake Flask" in l for l in hover8(13463))
sk8("tip crafts on")

# Short tooltip: verdict, price and the total you own; Shift shows the rest
sk8("tip short on")
L8.execute("SHIFT = false")
lines = hover8(13463)
assert "Hold Shift for details" in lines and row8(lines, "Drops") is None and row8(lines, "Used in") is None, lines
assert row8(lines, "Auction house") and row8(lines, "You own") and not any("bags 12" in l for l in lines), lines
L8.execute("SHIFT = true")
lines = hover8(13463)
assert "Hold Shift for details" not in lines and row8(lines, "Used in") and any("bags 12" in l for l in lines), lines
L8.execute("SHIFT = false"); sk8("tip short off")
print("CRAFT ROWS OK")

print("scanner: ok")
