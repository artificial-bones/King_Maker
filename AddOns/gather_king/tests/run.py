import sys, lupa
from lupa import lua51
L = lua51.LuaRuntime()
root = sys.argv[1]
L.execute(open(f"{root}/tests/mock.lua").read())
sk_root = sys.argv[2] if len(sys.argv) > 2 else f"{root}/../scanner_king"
L.execute("C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }")
skns = L.table()
for fn in ["Core.lua", "Scan.lua", "Sync.lua", "MarketScan.lua", "Browser.lua"]:
    L.execute(open(f"{sk_root}/{fn}").read(), "Scanner_King", skns)
L.execute('FIRE("ADDON_LOADED", "Scanner_King")')
ns = L.table()
for fn in ["Data.lua", "Core.lua", "Pins.lua", "Recorder.lua", "Sync.lua", "Button.lua", "Prices.lua", "Ledger.lua", "Options.lua"]:
    L.execute(open(f"{root}/{fn}").read(), "gather_king", ns)
L.execute('FIRE("ADDON_LOADED", "gather_king"); FIRE("PLAYER_LOGIN")')
gt = L.eval("SlashCmdList.GATHERKING")
def last(): return L.eval("OUTPUT[#OUTPUT]")
def nodes(): return L.eval("#(GatherKingDB.nodes[1423] or {})")
gt("mine (thorium)"); print(last())
assert nodes() == 1
n = L.eval("GatherKingDB.nodes[1423][1]"); assert n.n == "Thorium" and n.item == 10620 and n.t == "mine"
gt("mine thorium"); print(last()); assert nodes() == 1
L.execute("PLAYER.x = 0.50")
gt("herb black lotus"); print(last()); assert nodes() == 2
assert L.eval("GatherKingDB.nodes[1423][2].n") == "Black Lotus"
L.execute("PLAYER.x = 0.60")
gt("mine dark iron ore"); assert L.eval("GatherKingDB.nodes[1423][3].n") == "Dark Iron"
L.execute("PLAYER.x = 0.70")
gt("fish"); print(last()); assert L.eval("GatherKingDB.nodes[1423][4].n") is None
gt("fish weird pool name"); print(last()); assert L.eval("GatherKingDB.nodes[1423][4].n") == "Weird Pool Name"
L.execute("PLAYER.x = 0.80")
gt("peacebloom"); print(last()); assert L.eval("GatherKingDB.nodes[1423][5].t") == "herb"
assert L.eval("PINS.world") == 5 and L.eval("PINS.mini") == 5
gt("hide fish"); assert L.eval("PINS.world") == 4
gt("show all"); assert L.eval("PINS.world") == 5
gt("undo"); print(last()); assert nodes() == 4
L.execute("PLAYER.x = 0.701")
gt("remove"); print(last()); assert nodes() == 3
gt("list"); print("\n".join(L.eval("OUTPUT")[i] for i in range(len(L.eval("OUTPUT"))-3, len(L.eval("OUTPUT"))+1)))
# auto-record
L.execute("PLAYER.x = 0.30")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2575); LOOT = {"|cff|Hitem:2776::|h[Gold Ore]|h|r", "|Hitem:7909|h"}; FIRE("LOOT_OPENED")')
print(last()); assert L.eval("GatherKingDB.nodes[1423][4].n") == "Gold"
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 7620); FIRE("LOOT_OPENED")'); assert nodes() == 4
gt("auto off")
L.execute("PLAYER.x = 0.20")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366); FIRE("LOOT_OPENED")'); assert nodes() == 4
# right-click menu on a world map pin
L.execute("PLAYER.x = 0.302"); gt("mine gold")  # duplicate of auto-added gold, stays 4
assert nodes() == 4
pin = L.eval("(function() for _, f in ipairs(FRAMES) do if f.node and f.node.n == 'Gold' then return f end end end)()")
pin.scripts.OnMouseUp(pin, "RightButton"); menu = L.eval("MENU")
print([menu[i].text for i in range(1, len(menu)+1)])
menu[1].fn(); print(last()); assert nodes() == 3
gt("undo"); print(last()); assert nodes() == 4
assert len(menu) == 1  # bulk delete only lives on the settings page
gt("clear zone"); assert nodes() == 4  # no chat command for bulk delete
gt("settings"); assert L.eval("SETTINGS_OPENED")
L.execute("for _, f in ipairs(FRAMES) do if f.text == 'Mining' then LEDGER_MINING = f break end end")  # the ledger's Mat Prices tab, made at login
panel = L.eval("(function() for _, f in ipairs(FRAMES) do if f.name == 'Gather King' then return f end end end)()")
panel.scripts.OnShow(panel)
btns = L.eval("(function() local r = {} for _, f in ipairs(FRAMES) do if f.text == 'Mining' and f ~= LEDGER_MINING then r[#r+1] = f end end return r end)()")
assert len(btns) == 2
btns[1].scripts.OnClick(btns[1]); print(L.eval("POPUP")); print(last()); assert nodes() == 1
gt("undo"); assert nodes() == 4
allb = L.eval("(function() local r = {} for _, f in ipairs(FRAMES) do if f.text == 'All types' then r[#r+1] = f end end return r end)()")
allb[2].scripts.OnClick(allb[2]); print(last()); assert nodes() == 0
gt("undo"); assert nodes() == 4
L.execute("PLAYER.x = 0.5"); gt("delete nearby"); print(last()); assert nodes() == 3
L.execute("SHIFT = true")
pin = L.eval("(function() for _, f in ipairs(FRAMES) do if f.node and f.node.n == 'Gold' then return f end end end)()")
pin.scripts.OnMouseUp(pin, "RightButton"); assert nodes() == 2
# profiles: switch, filters, per-profile recording
L.execute("SHIFT = false"); gt("auto on")
gt("profile new Thorium run"); print(last()); assert L.eval("GatherKingDB.active") == "Thorium run"
gt("only thorium"); assert L.eval("PINS.world") == 1  # only the Thorium marker shows
gt("profile default"); assert L.eval("GatherKingDB.active") == "Default" and L.eval("PINS.world") == 2
gt("profile thorium run"); assert L.eval("PINS.world") == 1
gt("only all"); assert L.eval("PINS.world") == 2
gt("only mithril, dark iron"); assert L.eval("PINS.world") == 1
L.execute("GatherKingDB.profiles['Thorium run'].record.herb = false; PLAYER.x = 0.9")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366); LOOT = {"|Hitem:2447|h"}; FIRE("LOOT_OPENED")'); assert nodes() == 2
gt("profile Default")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366); FIRE("LOOT_OPENED")'); assert nodes() == 3
gt("profile delete Default"); print(last()); assert L.eval("GatherKingDB.profiles.Default") is not None
gt("profile delete thorium run"); print(last()); assert L.eval("GatherKingDB.profiles['Thorium run']") is None
gt("profile"); print(last())
panel.scripts.OnShow(panel)  # settings page refresh with profiles
gt("opacity 30"); assert abs(L.eval("GatherKingDB.profiles.Default.minimapAlpha") - 0.3) < 1e-9
gt("opacity 5"); assert abs(L.eval("GatherKingDB.profiles.Default.minimapAlpha") - 0.3) < 1e-9
# ---- guild sync ----
L.execute("RUN_TIMERS(); SENT = {}")
L.execute("PLAYER.x = 0.11"); gt("mine copper")
L.execute("RUN_TIMERS()")
sent = L.eval("SENT"); assert len(sent) == 1 and sent[1].chan == "GUILD" and sent[1].text.startswith("N1423,m,1100,6210,Copper"), sent[1].text
# receive two new markers from a guildmate, one duplicate
L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1423,h,2000,2000,Peacebloom;1423,m,1100,6210,Copper;1440,f,5000,5000,", "GUILD", "Bob-Realm")')
L.execute("RUN_TIMERS()"); print(last())
before = nodes()
assert L.eval("#GatherKingDB.nodes[1440]") == 1
shared = L.eval("(function() for _, n in ipairs(GatherKingDB.nodes[1423]) do if n.from == 'Bob' then return n end end end)()")
assert shared.n == "Peacebloom" and shared.item == 2447
# deleted markers don't come back via sync
L.execute("PLAYER.x = 0.2; PLAYER.y = 0.2"); gt("delete nearby"); print(last())
assert nodes() == before - 1
L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1423,h,2001,2001,Peacebloom", "GUILD", "Bob-Realm")'); L.execute("RUN_TIMERS()")
assert nodes() == before - 1
# but marking it yourself again works, and undo clears the tombstone
gt("herb peacebloom"); assert nodes() == before
# hide shared per profile
w = L.eval("PINS.world"); gt("profile new Mine only"); L.execute("GatherKingDB.profiles['Mine only'].showShared = false"); gt("size 16")
assert L.eval("PINS.world") == w - 1, (L.eval("PINS.world"), w)
gt("profile Default")
# hello -> whisper our list back once
L.execute("SENT = {}")
L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "H", "GUILD", "Amy-Realm")'); L.execute("RUN_TIMERS()")
sent = L.eval("SENT"); assert len(sent) >= 1 and all(sent[i].chan == "WHISPER" and sent[i].target == "Amy-Realm" for i in range(1, len(sent)+1))
total = sum(len(sent[i].text[1:].split(";")) for i in range(1, len(sent)+1) if sent[i].text.startswith("N"))
assert total == sum(L.eval("#GatherKingDB.nodes[%d]" % m) for m in (1423, 1440)), total
L.execute("SENT = {}"); L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "H", "GUILD", "Amy-Realm")'); L.execute("RUN_TIMERS()"); assert len(L.eval("SENT")) == 0
# own messages ignored, sync off ignores incoming
L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1450,m,100,100,Tin", "GUILD", "Jay-Realm")'); assert L.eval("GatherKingDB.nodes[1450]") is None
gt("sync off"); L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1450,m,100,100,Tin", "GUILD", "Bob-Realm")'); assert L.eval("GatherKingDB.nodes[1450]") is None
gt("sync on"); L.execute("RUN_TIMERS()")
# a big list splits into several messages under the size limit
L.execute("SENT = {}; for i = 1, 60 do table.insert(GatherKingDB.nodes[1423], { t = 'mine', n = 'Thorium', x = i / 100, y = 0.9 }) end")
gt("sync now"); L.execute("RUN_TIMERS()")
sent = L.eval("SENT"); assert len(sent) > 3 and all(len(sent[i].text) <= 240 for i in range(1, len(sent)+1))
print("SYNC OK")
# ---- harvest fade + hide near ----
gt("opacity 100"); L.execute("PLAYER.x = 0.6; PLAYER.y = 0.6"); gt("mine thorium")
def pins_for(name):
    return L.eval("(function() local r = {} for _, f in ipairs(FRAMES) do if f.node and f.node.n == '%s' and f.node.x == 0.6 and f.node.y == 0.6 then r[#r+1] = f end end return r end)()" % name)
L.execute("ns_update = nil")
mm = [p for p in pins_for("Thorium").values() if p.isMinimap]; wmp = [p for p in pins_for("Thorium").values() if not p.isMinimap]
assert mm[0].alpha == 1 and wmp[0].alpha == 1
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2575); LOOT = {"|Hitem:10620|h"}; FIRE("LOOT_OPENED")')
mm = [p for p in pins_for("Thorium").values() if p.isMinimap]; wmp = [p for p in pins_for("Thorium").values() if not p.isMinimap]
assert abs(wmp[0].alpha - 0.4) < 1e-9 and abs(mm[0].alpha - 0.4) < 1e-9, (wmp[0].alpha, mm[0].alpha)
# auto off still stamps harvests on existing markers
gt("auto off"); L.execute("NOW = NOW + 600"); gt("size 16")
assert pins_for("Thorium")[1].alpha == 1
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2575); FIRE("LOOT_OPENED")'); assert abs(pins_for("Thorium")[1].alpha - 0.4) < 1e-9
gt("auto on")
L.execute("NOW = NOW + 600; DIST = 5"); gt("size 16")
mm = [p for p in pins_for("Thorium").values() if p.isMinimap]; wmp = [p for p in pins_for("Thorium").values() if not p.isMinimap]
assert mm[0].alpha == 0 and mm[0].mouse == False and wmp[0].alpha == 1
L.execute("DIST = 100"); gt("button off"); gt("button on")
# ---- export / import ----
print("FADE/NEAR OK")
# ---- new Forever gatherables ----
L.execute("PLAYER.map = 1451; PLAYER.x = 0.3; PLAYER.y = 0.3")
gt("mine small obsidian chunk"); assert L.eval("GatherKingDB.nodes[1451][1].n") == "Obsidian"
L.execute("PLAYER.x = 0.4")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366); LOOT = {"|Hitem:249399|h", "|Hitem:248823|h"}; LOOTINFO = {{"Frilled Lichen", 2}, {"Marefoil", 1}}; FIRE("LOOT_OPENED")')
n2 = L.eval("GatherKingDB.nodes[1451][2]"); assert n2.n == "Marefoil" and n2.item == 248823 and n2.t == "herb", (n2.n, n2.item)
L.execute("PLAYER.x = 0.5")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2575); LOOT = {"|Hitem:249391|h", "|Hitem:2835|h", "|Hitem:999999|h"}; LOOTINFO = {{"Pyrite", 2}, {"Rough Stone", 1}, {"Mystery Ore", 1}}; FIRE("LOOT_OPENED")')
n3 = L.eval("GatherKingDB.nodes[1451][3]"); assert n3.n == "Mystery" and n3.item == 999999, (n3.n, n3.item)
# unknown names keep their icon through export/import
c, _ = ns.ExportCode(1451); assert "Mystery,999999" in c and "Marefoil,248823" not in c, c
L.execute("PLAYER.map = 1423")
print("NEW GATHERABLES OK")
# ---- loot stats ----
L.execute("PLAYER.map = 1451; PLAYER.x = 0.4; PLAYER.y = 0.3; SENT = {}")
for loot, info in [('{"|Hitem:248823|h", "|Hitem:249399|h"}', '{{"Marefoil", 1, 2}, {"Frilled Lichen", 2, 1}}'),
                   ('{"|Hitem:248823|h"}', '{{"Marefoil", 1, 3}}'),
                   ('{"|Hitem:248823|h", "|Hitem:268415|h"}', '{{"Marefoil", 1, 1}, {"Commonplace Herb Seeds", 1, 1}}')]:
    L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366); LOOT = %s; LOOTINFO = %s; FIRE("LOOT_OPENED")' % (loot, info))
node = L.eval("GatherKingDB.nodes[1451][2]"); assert node.n == "Marefoil"
# the earlier auto-tag harvest of this node counts too: 4 harvests
assert node.stats.h == 4 and node.stats["items"][248823].n == 4, node.stats.h
L.execute("RUN_TIMERS()")
sent = [L.eval("SENT")[i].text for i in range(1, len(L.eval("SENT")) + 1)]
stat_msgs = [t for t in sent if t.startswith("S")]
assert stat_msgs and "1451,h,4000,3000,4," in stat_msgs[-1], stat_msgs
# Bob's numbers for the same node: stored under Bob and replaced, not added
for msg in ["S1451,h,4001,3001,10,248823:10:25/249424:1:1", "S1451,h,4000,3000,12,248823:12:30/249424:2:2"]:
    L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "%s", "GUILD", "Bob-Realm")' % msg)
total, mine, items = ns.CombinedStats(L.eval("GatherKingDB.nodes[1451][2]"))
assert total == 16 and mine == 4, (total, mine)
assert items[1].id == 248823 and items[1].n == 16 and items[1].q == 30 + 2 + 3 + 1 + L.eval("GatherKingDB.nodes[1451][2].stats.items[248823].q") - 6, items[1].q
assert ns.ItemName(249424) == "Rosecap" and ns.ItemName(248823) == "Marefoil"
# tooltip renders
pin = L.eval("(function() for _, f in ipairs(FRAMES) do if f.node and f.node.n == 'Marefoil' then return f end end end)()")
pin.scripts.OnEnter(pin); pin.scripts.OnLeave(pin)
L.execute("PLAYER.map = 1423")
print("LOOT STATS OK")
# ---- auction prices, through Scanner King ----
L.execute("RUN_TIMERS(); AH_PRICES = { [248823] = 12345, [249424] = 50000, [2318] = 600 }")
L.execute('FIRE("AUCTION_HOUSE_SHOW")')
gt("scan"); L.execute("RUN_TIMERS()"); print(last())
# no browse search in this stand-in, so Scanner King looks up what Gather King watches one by one
assert 100 < L.eval("AH_QUERIES") < 200, L.eval("AH_QUERIES")
assert L.eval("AH_ASKED[10620]") and L.eval("AH_ASKED[249391]") and L.eval("AH_ASKED[2318]") and L.eval("AH_ASKED[10940]") and not L.eval("AH_ASKED[6358]")
assert L.eval("ScannerKingDB.prices[248823].p") == 12345 and L.eval("GatherKingDB.prices") is None
assert ns.FormatMoney(12345) == "|cffffd7001g|r |cffc7c7cf23s|r |cffeda55f45c|r"
p, t = ns.Price(248823); assert p == 12345
pin = L.eval("(function() for _, f in ipairs(FRAMES) do if f.node and f.node.n == 'Marefoil' then return f end end end)()")
pin.scripts.OnEnter(pin)
# gather_king no longer sends prices itself
assert not any(L.eval("SENT")[i].prefix == "GatherKing1" and L.eval("SENT")[i].text.startswith("P") for i in range(1, len(L.eval("SENT")) + 1))
L.execute("ScannerKingDB.prices[248823] = { p = 12345, t = 2000000000 }")
print("PRICES OK")
# ---- farming ledger ----
def font(prefix):
    fs = L.eval("FONTS")
    for i in range(len(fs), 0, -1):
        t = fs[i].text
        if t and prefix in t: return t
led = L.eval("GatherKingDB.ledger")
assert L.eval("GatherKingDB.ui.ledger") == True and L.eval("GatherKingDB.ledger.items[248823]") > 0  # harvests above were logged
gt("ledger reset"); assert L.eval("next(GatherKingDB.ledger.items)") is None
L.execute("T = 100; function GetTime() return T end")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366); LOOT = {"|Hitem:248823|h"}; LOOTINFO = {{"Marefoil", 1, 4}}; FIRE("LOOT_OPENED")')
assert L.eval("GatherKingDB.ledger.items[248823]") == 4 and L.eval("next(GatherKingDB.ledger.timed)") is None
assert "4g" in font("Total:")  # no timer yet, totals only
assert L.eval("(function() for _, f in ipairs(FONTS) do if f.text and f.text:find('/hr') then return true end end end)()") is None
gt("ledger timer")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366); LOOT = {"|Hitem:248823|h"}; LOOTINFO = {{"Marefoil", 1, 2}}; FIRE("LOOT_OPENED")')
L.execute("T = 100 + 1800"); ns.UpdateLedger()
print(font("Total:"), "|", font("/hr"))
assert "0:30:00" in font("/hr") and "4g" in font("/hr")  # 2 x 1.2345g in half an hour = ~4.9g/hr
# folded to its title bar, the title still shows gold per hour
def btn(label): return L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' then return f end end end)()" % label)
b = btn("-"); b.scripts.OnClick(b)
assert L.eval("GatherKingDB.ui.ledgerCollapsed") and font("Gather King  ").endswith("/hr|r"), font("Gather King")
b = btn("+"); b.scripts.OnClick(b); assert not L.eval("GatherKingDB.ui.ledgerCollapsed") and font("Gather King  ") is None
# fishing catches go in the ledger without making a node
before = L.eval("#GatherKingDB.nodes[1423]")
L.execute('FISHING = true; LOOT = {"|Hitem:6358|h"}; LOOTINFO = {{"Oily Blackmouth", 1, 3}}; FIRE("LOOT_OPENED"); FISHING = false')
assert L.eval("GatherKingDB.ledger.items[6358]") == 3 and L.eval("GatherKingDB.ledger.timed[6358]") == 3
assert L.eval("#GatherKingDB.nodes[1423]") == before
gt("ledger timer"); assert "paused" in font("/hr")
gt("ledger reset"); assert L.eval("GatherKingDB.ledger.timer.running") == False and L.eval("GatherKingDB.ledger.timer.elapsed") == 0
gt("ledger off"); assert L.eval("GatherKingDB.ui.ledger") == False
gt("ledger on")
# x closes it, /gt ledger brings it back
b = btn("x"); b.scripts.OnClick(b); assert L.eval("GatherKingDB.ui.ledger") == False and "/gt ledger" in L.eval("OUTPUT[#OUTPUT]")
gt("ledger on")
L.execute("function GetTime() return 10 end")
# Mat Prices tab
ledger_frame = L.eval("(function() for _, f in ipairs(FRAMES) do if f.scripts.OnMouseWheel then return f end end end)()")
def click(label):
    b = L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == '%s' then return f end end end)()" % label)
    b.scripts.OnClick(b)
click("Mat Prices"); assert L.eval("GatherKingDB.ui.ledgerTab") == "prices"
click("Herbs")
herbs = [ns.ItemName(i) for i in ns.LedgerMaterials("herb").values()]
mines = [ns.ItemName(i) for i in ns.LedgerMaterials("mine").values()]
assert "Marefoil" in herbs and "Rosecap" in herbs and "Thorium" not in " ".join(herbs) and "Pyrite" in mines and "Rough Stone" in mines
fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "Rosecap" in texts and any("Prices from" in t for t in texts), texts[-20:]
ledger_frame.scripts.OnMouseWheel(ledger_frame, -1)
fs = L.eval("FONTS"); print([fs[i].text for i in range(1, len(fs) + 1) if fs[i].text and "Scroll" in fs[i].text][-1])
for label, key in [("Skins", "skin"), ("Cloth", "cloth"), ("Ench", "ench")]:
    click(label); assert L.eval("GatherKingDB.ui.priceTab") == key
    fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
click("Skins")
fs = L.eval("FONTS"); texts = [fs[i].text for i in range(1, len(fs) + 1) if fs[i].text]
assert "Light Leather" in texts and "Devilsaur Leather" in texts
assert [ns.ItemName(i) for i in ns.MaterialList("cloth").values()][:2] == ["Linen Cloth", "Wool Cloth"]
assert "Nexus Crystal" in [ns.ItemName(i) for i in ns.MaterialList("ench").values()]
click("Mining"); assert L.eval("GatherKingDB.ui.priceTab") == "mine"
click("Farming"); assert L.eval("GatherKingDB.ui.ledgerTab") == "farm"
print("LEDGER OK")
code, n = ns.ExportCode()
assert code.startswith("GK1:") and n == sum(len(list(L.eval("GatherKingDB.nodes")[m].values())) for m in L.eval("GatherKingDB.nodes").keys())
zcode, zn = ns.ExportCode(1440); assert zn == 1
# settings page buttons exist and import works through them
panel.scripts.OnShow(panel)
assert L.eval("(function() for _, f in ipairs(FRAMES) do if f.text == 'Export all' then return true end end end)()")
gt("bogus"); gt("")
print("ALL TESTS PASSED")

# migration from the single-settings format
L2 = lua51.LuaRuntime()
L2.execute(open(f"{root}/tests/mock.lua").read())
L2.execute('GatherKingDB = { version = 1, nodes = {}, settings = { show = { mine = true, herb = false, fish = true, treasure = true }, minimap = false, auto = true, size = 20 } }')
ns2 = L2.table()
for fn in ["Data.lua", "Core.lua", "Pins.lua", "Recorder.lua", "Sync.lua", "Button.lua", "Prices.lua", "Ledger.lua", "Options.lua"]:
    L2.execute(open(f"{root}/{fn}").read(), "gather_king", ns2)
L2.execute('FIRE("ADDON_LOADED", "gather_king")')
assert L2.eval("GatherKingDB.profiles.Default.size") == 20 and L2.eval("GatherKingDB.profiles.Default.show.herb") == False
assert L2.eval("GatherKingDB.profiles.Default.record.mine") == True and L2.eval("GatherKingDB.settings") is None
# without Scanner King, Gather King still works and says where scanning went
L2.execute('FIRE("PLAYER_LOGIN")')
L2.eval("SlashCmdList.GATHERKING")("scan"); assert "Scanner King" in L2.eval("OUTPUT[#OUTPUT]")
assert ns2.Price(2770) is None and ns2.FormatMoney(10000) == "|cffffd7001g|r"
print("MIGRATION OK")

# prices scanned by gather_king 1.x move into Scanner King on first login
L3 = lua51.LuaRuntime()
L3.execute(open(f"{root}/tests/mock.lua").read())
L3.execute('GatherKingDB = { version = 3, nodes = {}, prices = { [2770] = { p = 450, t = 1700000000 } }, pricesScanned = 1700000000 }')
sk3 = L3.table()
for fn in ["Core.lua", "Scan.lua", "Sync.lua", "MarketScan.lua", "Browser.lua"]:
    L3.execute(open(f"{sk_root}/{fn}").read(), "Scanner_King", sk3)
L3.execute('FIRE("ADDON_LOADED", "Scanner_King")')
ns3 = L3.table()
for fn in ["Data.lua", "Core.lua", "Pins.lua", "Recorder.lua", "Sync.lua", "Button.lua", "Prices.lua", "Ledger.lua", "Options.lua"]:
    L3.execute(open(f"{root}/{fn}").read(), "gather_king", ns3)
L3.execute('FIRE("ADDON_LOADED", "gather_king"); FIRE("PLAYER_LOGIN")')
assert L3.eval("ScannerKingDB.prices[2770].p") == 450 and L3.eval("GatherKingDB.prices") is None
assert ns3.Price(2770)[0] == 450
print("PRICE MOVE OK")

L2.execute('FIRE("PLAYER_LOGIN")')
added = ns2.ImportCode(code); assert added == n, (added, n)
assert ns2.ImportCode(code) == 0
assert ns2.ImportCode("garbage") == 0
assert L2.eval("GatherKingDB.nodes[1423][1].from") == "an import"
assert ns2.ImportCode(c) == 0  # already imported with the full export above
m = L2.eval("(function() for _, n in ipairs(GatherKingDB.nodes[1451]) do if n.n == 'Mystery' then return n end end end)()"); assert m.item == 999999
print("EXPORT/IMPORT OK")
