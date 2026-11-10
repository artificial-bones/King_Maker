# Gather (was Gather King), with Scanner and without it: /gt marking, undo, delete, auto-tagging from harvests,
# pin counts and menus, profiles, guild sync, fade and hide-near, new Forever gatherables, loot stats, prices via
# Scanner, the farming ledger HUD, the Gathering page, the crown's quick actions and settings, export/import and
# the 1.x migrations.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

EXTRA = """
-- Finders: a KM.UI button by its label (optionally only inside root), a check by its label.
function UNDER(f, root) while f do if f == root then return true end f = f.parent end return false end
function BTN(text, root) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel and (not root or UNDER(f, root)) then return f end end end
function BTNS(text) local r = {} for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetLabel then r[#r+1] = f end end return r end
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and f.SetChecked and rawget(f, "mark") then return f end end end
function DELBTN(text, scope) for _, f in ipairs(FRAMES) do if rawget(f, "scope") == scope and f.label.text == text then return f end end end
function PIN(name) for _, f in ipairs(FRAMES) do if f.node and f.node.n == name then return f end end end
"""


def load(only=("Scanner", "Gather"), **kw):
    L, KM = fresh(only=list(only), extra=EXTRA, **kw)
    return L, KM, KM.mods.Gather


def fonts(L, prefix):
    fs = L.eval("FONTS")
    for i in range(len(fs), 0, -1):
        t = fs[i].text
        if t and prefix in t and fs[i].shown != False:
            return t


def texts(L):
    return list(L.eval("TEXTS()").values())


L, KM, ns = load()
gt = L.eval("SlashCmdList.GATHERKING")
def nodes(): return L.eval("#(GatherKingDB.nodes[1423] or {})")
assert L.eval("GatherKingMinimapButton") is None, "no minimap button of its own"
assert L.eval("SETTINGS.panels['Gather King']") is None, "no Blizzard settings panel of its own"
assert L.eval("GatherKingDB.ui.button") is None and L.eval("GatherKingDB.version") == 3
gt("mine (thorium)")
assert nodes() == 1
n = L.eval("GatherKingDB.nodes[1423][1]"); assert n.n == "Thorium" and n.item == 10620 and n.t == "mine"
gt("mine thorium"); assert "already marked" in last(L); assert nodes() == 1
L.execute("PLAYER.x = 0.50")
gt("herb black lotus"); assert nodes() == 2
assert L.eval("GatherKingDB.nodes[1423][2].n") == "Black Lotus"
L.execute("PLAYER.x = 0.60")
gt("mine dark iron ore"); assert L.eval("GatherKingDB.nodes[1423][3].n") == "Dark Iron"
L.execute("PLAYER.x = 0.70")
gt("fish"); assert L.eval("GatherKingDB.nodes[1423][4].n") is None
gt("fish weird pool name"); assert L.eval("GatherKingDB.nodes[1423][4].n") == "Weird Pool Name"
L.execute("PLAYER.x = 0.80")
gt("peacebloom"); assert L.eval("GatherKingDB.nodes[1423][5].t") == "herb"
assert L.eval("PINS.world") == 5 and L.eval("PINS.mini") == 5
# pins use the ring texture from King Maker's own folder, and keep the 1.x HereBeDragons owner key
assert L.eval("(function() for _, f in ipairs(FRAMES) do if f.hollow then return f.hollow.texture end end end)()") == "Interface\\AddOns\\King_Maker\\Textures\\ring"
assert L.eval("(function() for f, e in pairs(WORLD) do return e.ref end end)()") == "gather_king"
gt("hide fish"); assert L.eval("PINS.world") == 4
gt("show all"); assert L.eval("PINS.world") == 5
gt("undo"); assert nodes() == 4
L.execute("PLAYER.x = 0.701")
gt("remove"); assert nodes() == 3
gt("list"); assert "marker(s) in Eastern Plaguelands" in L.eval("OUTPUT[#OUTPUT - 3]")
# auto-record
L.execute("PLAYER.x = 0.30")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2575); LOOT = {"|cff|Hitem:2776::|h[Gold Ore]|h|r", "|Hitem:7909|h"}; FIRE("LOOT_OPENED")')
assert L.eval("GatherKingDB.nodes[1423][4].n") == "Gold"
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 7620); FIRE("LOOT_OPENED")'); assert nodes() == 4
gt("auto off")
L.execute("PLAYER.x = 0.20")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366); FIRE("LOOT_OPENED")'); assert nodes() == 4
# right-click menu on a world map pin
L.execute("PLAYER.x = 0.302"); gt("mine gold")  # duplicate of auto-added gold, stays 4
assert nodes() == 4
pin = L.eval("PIN('Gold')")
pin.scripts.OnMouseUp(pin, "RightButton"); menu = L.eval("MENU")
assert [menu[i].text for i in range(1, len(menu) + 1)] == ["Delete this node"]
menu[1].fn(); assert nodes() == 3
gt("undo"); assert nodes() == 4
gt("clear zone"); assert nodes() == 4  # no chat command for bulk delete
# the Gathering page replaces the settings panel: bulk deletes live there
gt("settings"); assert KM.CurrentPage() == "gathering" and not KM.errorShown, last(L)
L.execute('DELBTN("Mining", "zone"):Click()'); assert "Delete Mining markers in Eastern Plaguelands" in L.eval("POPUPS[#POPUPS].arg1")
assert nodes() == 1
gt("undo"); assert nodes() == 4
L.execute('DELBTN("All types", "all"):Click()'); assert nodes() == 0 and "EVERY zone" in L.eval("POPUPS[#POPUPS].arg1")
gt("undo"); assert nodes() == 4
L.execute("PLAYER.x = 0.5"); gt("delete nearby"); assert nodes() == 3
L.execute("SHIFT = true")
pin = L.eval("PIN('Gold')")
pin.scripts.OnMouseUp(pin, "RightButton"); assert nodes() == 2
# profiles: switch, filters, per-profile recording
L.execute("SHIFT = false"); gt("auto on")
gt("profile new Thorium run"); assert L.eval("GatherKingDB.active") == "Thorium run"
gt("only thorium"); assert L.eval("PINS.world") == 1  # only the Thorium marker shows
gt("profile default"); assert L.eval("GatherKingDB.active") == "Default" and L.eval("PINS.world") == 2
gt("profile thorium run"); assert L.eval("PINS.world") == 1
gt("only all"); assert L.eval("PINS.world") == 2
gt("only mithril, dark iron"); assert L.eval("PINS.world") == 1
L.execute("GatherKingDB.profiles['Thorium run'].record.herb = false; PLAYER.x = 0.9")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366); LOOT = {"|Hitem:2447|h"}; FIRE("LOOT_OPENED")'); assert nodes() == 2
gt("profile Default")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366); FIRE("LOOT_OPENED")'); assert nodes() == 3
gt("profile delete Default"); assert "can't be deleted" in last(L) and L.eval("GatherKingDB.profiles.Default") is not None
gt("profile delete thorium run"); assert L.eval("GatherKingDB.profiles['Thorium run']") is None
gt("profile"); assert "Profiles (active: Default)" in L.eval("OUTPUT[#OUTPUT - 1]")
KM.Show("gathering"); assert not KM.errorShown, last(L)
gt("opacity 30"); assert abs(L.eval("GatherKingDB.profiles.Default.minimapAlpha") - 0.3) < 1e-9
gt("opacity 5"); assert abs(L.eval("GatherKingDB.profiles.Default.minimapAlpha") - 0.3) < 1e-9
print("MARKERS OK")

# ---- guild sync ----
L.execute("RUN_TIMERS(); SENT = {}")
L.execute("PLAYER.x = 0.11"); gt("mine copper")
L.execute("RUN_TIMERS()")
sent = L.eval("SENT"); assert len(sent) == 1 and sent[1].chan == "GUILD" and sent[1].text.startswith("N1423,m,1100,6210,Copper"), sent[1].text
# receive two new markers from a guildmate, one duplicate
L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1423,h,2000,2000,Peacebloom;1423,m,1100,6210,Copper;1440,f,5000,5000,", "GUILD", "Bob-Realm")')
L.execute("RUN_TIMERS()"); assert "Got 2 new marker(s) from Bob." in last(L)
before = nodes()
assert L.eval("#GatherKingDB.nodes[1440]") == 1
shared = L.eval("(function() for _, n in ipairs(GatherKingDB.nodes[1423]) do if n.from == 'Bob' then return n end end end)()")
assert shared.n == "Peacebloom" and shared.item == 2447
# deleted markers don't come back via sync
L.execute("PLAYER.x = 0.2; PLAYER.y = 0.2"); gt("delete nearby")
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
sent = L.eval("SENT"); assert len(sent) >= 1 and all(sent[i].chan == "WHISPER" and sent[i].target == "Amy-Realm" for i in range(1, len(sent) + 1))
total = sum(len(sent[i].text[1:].split(";")) for i in range(1, len(sent) + 1) if sent[i].text.startswith("N"))
assert total == sum(L.eval("#GatherKingDB.nodes[%d]" % m) for m in (1423, 1440)), total
L.execute("SENT = {}"); L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "H", "GUILD", "Amy-Realm")'); L.execute("RUN_TIMERS()"); assert len(L.eval("SENT")) == 0
# own messages ignored, sync off ignores incoming
L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1450,m,100,100,Tin", "GUILD", "Jay-Realm")'); assert L.eval("GatherKingDB.nodes[1450]") is None
gt("sync off"); L.execute('FIRE("CHAT_MSG_ADDON", "GatherKing1", "N1450,m,100,100,Tin", "GUILD", "Bob-Realm")'); assert L.eval("GatherKingDB.nodes[1450]") is None
gt("sync on"); L.execute("RUN_TIMERS()")
# a big list splits into several messages under the size limit
L.execute("SENT = {}; for i = 1, 60 do table.insert(GatherKingDB.nodes[1423], { t = 'mine', n = 'Thorium', x = i / 100, y = 0.9 }) end")
gt("sync now"); L.execute("RUN_TIMERS()")
sent = L.eval("SENT"); assert len(sent) > 3 and all(len(sent[i].text) <= 240 for i in range(1, len(sent) + 1))
print("SYNC OK")

# ---- harvest fade + hide near ----
gt("opacity 100"); L.execute("PLAYER.x = 0.6; PLAYER.y = 0.6"); gt("mine thorium")
def pins_for(name):
    return L.eval("(function() local r = {} for _, f in ipairs(FRAMES) do if f.node and f.node.n == '%s' and f.node.x == 0.6 and f.node.y == 0.6 then r[#r+1] = f end end return r end)()" % name)
mm = [p for p in pins_for("Thorium").values() if p.isMinimap]; wmp = [p for p in pins_for("Thorium").values() if not p.isMinimap]
assert mm[0].alpha == 1 and wmp[0].alpha == 1
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2575); LOOT = {"|Hitem:10620|h"}; LOOTINFO = {}; FIRE("LOOT_OPENED")')
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
L.execute("DIST = 100"); gt("button"); assert "/km button" in last(L)
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
assert items[1].id == 248823 and items[1].n == 16 and items[1].q == 30 + L.eval("GatherKingDB.nodes[1451][2].stats.items[248823].q"), items[1].q
assert ns.ItemName(249424) == "Rosecap" and ns.ItemName(248823) == "Marefoil"
# tooltip renders
pin = L.eval("PIN('Marefoil')")
pin.scripts.OnEnter(pin); assert any("Harvested 16 times (you: 4, guild: 12)" in str(x) for x in L.eval("GameTooltip.lines").values())
pin.scripts.OnLeave(pin)
L.execute("PLAYER.map = 1423")
print("LOOT STATS OK")

# ---- auction prices, through the Scanner module ----
L.execute("RUN_TIMERS(); AH_PRICES = { [248823] = 12345, [249424] = 50000, [2318] = 600 }")
L.execute('FIRE("AUCTION_HOUSE_SHOW"); RUN_TIMERS()')
gt("scan"); L.execute("RUN_TIMERS()")
# no browse search in this stand-in, so Scanner looks up what Gather watches one by one
assert 100 < L.eval("AH_QUERIES") < 200, L.eval("AH_QUERIES")
assert L.eval("AH_ASKED[10620]") and L.eval("AH_ASKED[249391]") and L.eval("AH_ASKED[2318]") and L.eval("AH_ASKED[10940]") and not L.eval("AH_ASKED[6358]")
assert L.eval("ScannerKingDB.prices[248823].p") == 12345 and L.eval("GatherKingDB.prices") is None
assert ns.FormatMoney(12345) == "|cffffd7001g|r |cffc7c7cf23s|r |cffeda55f45c|r"
p, t = ns.Price(248823); assert p == 12345
pin = L.eval("PIN('Marefoil')")
pin.scripts.OnEnter(pin); assert any("per harvest" in str(x) for x in L.eval("GameTooltip.lines").values())
# Gather doesn't send prices itself
assert not any(L.eval("SENT")[i].prefix == "GatherKing1" and L.eval("SENT")[i].text.startswith("P") for i in range(1, len(L.eval("SENT")) + 1))
L.execute("ScannerKingDB.prices[248823] = { p = 12345, t = 2000000000 }")
print("PRICES OK")

# ---- farming ledger (a UI.HUD) ----
led = L.eval("GatherKingLedger")
assert led and led.shown and led.collapse and led.close and led.body
assert L.eval("GatherKingDB.ui.ledger") == True and L.eval("GatherKingDB.ledger.items[248823]") > 0  # harvests above were logged
gt("ledger reset"); assert L.eval("next(GatherKingDB.ledger.items)") is None
L.execute("T = 100; function GetTime() return T end")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366); LOOT = {"|Hitem:248823|h"}; LOOTINFO = {{"Marefoil", 1, 4}}; FIRE("LOOT_OPENED")')
assert L.eval("GatherKingDB.ledger.items[248823]") == 4 and L.eval("next(GatherKingDB.ledger.timed)") is None
assert "4g" in fonts(L, "Total:")  # no timer yet, totals only
assert fonts(L, "/hr") is None
gt("ledger timer")
L.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366); LOOT = {"|Hitem:248823|h"}; LOOTINFO = {{"Marefoil", 1, 2}}; FIRE("LOOT_OPENED")')
L.execute("T = 100 + 1800"); ns.UpdateLedger()
assert "0:30:00" in fonts(L, "/hr") and "4g" in fonts(L, "/hr")  # 2 x 1.2345g in half an hour = ~4.9g/hr
assert L.eval('BTN("Pause timer", GatherKingLedger)') is not None
# folded to its title bar, the title still shows gold per hour
L.execute("GatherKingLedger.collapse:Click()")
assert L.eval("GatherKingDB.ui.ledgerCollapsed") and led.collapsed and led.title.text.startswith("Farming ledger  ") and led.title.text.endswith("/hr|r"), led.title.text
L.execute("GatherKingLedger.collapse:Click()")
assert not L.eval("GatherKingDB.ui.ledgerCollapsed") and led.title.text == "Farming ledger"
# its position is kept in ui.ledgerPos (the 1.x shape)
L.execute('GatherKingLedger:ClearAllPoints(); GatherKingLedger:SetPoint("LEFT", UIParent, "LEFT", 30, 40); GatherKingLedger.scripts.OnDragStop(GatherKingLedger)')
assert list(L.eval("GatherKingDB.ui.ledgerPos").values()) == ["LEFT", "LEFT", 30, 40]
# fishing catches go in the ledger without making a node
before = L.eval("#GatherKingDB.nodes[1423]")
L.execute('FISHING = true; LOOT = {"|Hitem:6358|h"}; LOOTINFO = {{"Oily Blackmouth", 1, 3}}; FIRE("LOOT_OPENED"); FISHING = false')
assert L.eval("GatherKingDB.ledger.items[6358]") == 3 and L.eval("GatherKingDB.ledger.timed[6358]") == 3
assert L.eval("#GatherKingDB.nodes[1423]") == before
gt("ledger timer"); assert "paused" in fonts(L, "/hr")
gt("ledger reset"); assert L.eval("GatherKingDB.ledger.timer.running") == False and L.eval("GatherKingDB.ledger.timer.elapsed") == 0
gt("ledger off"); assert L.eval("GatherKingDB.ui.ledger") == False and not led.shown
gt("ledger on"); assert led.shown
# x closes it, /gt ledger brings it back
L.execute("GatherKingLedger.close:Click()"); assert L.eval("GatherKingDB.ui.ledger") == False and "/gt ledger" in last(L)
gt("ledger on")
L.execute('BTN("Reset", GatherKingLedger):Click()'); assert L.eval("POPUPS[#POPUPS].name") == "GATHERKING_CONFIRM"
L.execute("function GetTime() return 10 end")
# Mat Prices tab
def click(label): L.execute('BTN("%s", GatherKingLedger):Click()' % label)
click("Mat Prices"); assert L.eval("GatherKingDB.ui.ledgerTab") == "prices"
click("Herbs")
herbs = [ns.ItemName(i) for i in ns.LedgerMaterials("herb").values()]
mines = [ns.ItemName(i) for i in ns.LedgerMaterials("mine").values()]
assert "Marefoil" in herbs and "Rosecap" in herbs and "Thorium" not in " ".join(herbs) and "Pyrite" in mines and "Rough Stone" in mines
t = texts(L)
assert "Rosecap" in t and any("Prices from" in x for x in t), t[-20:]
L.execute("GatherKingLedger.scripts.OnMouseWheel(GatherKingLedger, -1)")
assert fonts(L, "Scroll for more (4-") is not None
for label, key in [("Skins", "skin"), ("Cloth", "cloth"), ("Ench", "ench")]:
    click(label); assert L.eval("GatherKingDB.ui.priceTab") == key
click("Skins")
t = texts(L)
assert "Light Leather" in t and "Devilsaur Leather" in t
assert [ns.ItemName(i) for i in ns.MaterialList("cloth").values()][:2] == ["Linen Cloth", "Wool Cloth"]
assert "Nexus Crystal" in [ns.ItemName(i) for i in ns.MaterialList("ench").values()]
click("Mining"); assert L.eval("GatherKingDB.ui.priceTab") == "mine"
click("Farming"); assert L.eval("GatherKingDB.ui.ledgerTab") == "farm"
print("LEDGER OK")

# ---- the Gathering page ----
KM.Show("gathering")
assert not KM.errorShown, last(L)
assert "Using: |cfff0c44dDefault|r" in texts(L)
assert any("markers in" in x and "harvests recorded" in x for x in texts(L)), [x for x in texts(L) if "markers" in x]
# profiles: switch by button, create from the box, delete
L.execute('for _, f in ipairs(FRAMES) do if rawget(f, "profile") == "Mine only" then f:Click() end end')
assert L.eval("GatherKingDB.active") == "Mine only"
L.execute('for _, f in ipairs(FRAMES) do if rawget(f, "profile") == "Default" then f:Click() end end')
assert L.eval("GatherKingDB.active") == "Default"
L.execute('for _, f in ipairs(FRAMES) do if type(rawget(f, "hint")) == "table" and f.hint.text == "New profile name" then f:SetText("Herbs") end end')
L.execute('BTN("Create"):Click()'); assert L.eval("GatherKingDB.active") == "Herbs" and L.eval("GatherKingDB.profiles.Herbs.size") == 16
L.execute('BTN("Delete this profile"):Click()'); assert L.eval("GatherKingDB.profiles.Herbs") is None and L.eval("GatherKingDB.active") == "Default"
# per-type show and the display steppers
w = L.eval("PINS.world")
L.execute('CHECK("Show markers on the minimap"):Click()'); assert L.eval("GatherKingDB.profiles.Default.minimap") is False and L.eval("PINS.mini") == 0
L.execute('CHECK("Show markers on the minimap"):Click()'); assert L.eval("PINS.mini") > 0
size = L.eval("GatherKingDB.profiles.Default.size")
L.execute('for _, f in ipairs(FRAMES) do if rawget(f, "label") and f.label.text == "+" and f.SetLabel then f:Click() break end end')
assert L.eval("GatherKingDB.profiles.Default.size") == size + 2
# only these names: typed and applied with Enter
L.execute('for _, f in ipairs(FRAMES) do if type(rawget(f, "hint")) == "table" and f.hint.text and f.hint.text:find("thorium, mithril") then f:SetText("copper"); f.scripts.OnEnterPressed(f) end end')
assert L.eval("GatherKingDB.profiles.Default.only") == "copper" and L.eval("PINS.world") < w
gt("only all"); assert L.eval("PINS.world") == w
# ledger tick on the page
L.execute('CHECK("Show the farming ledger box (all profiles)"):Click()'); assert L.eval("GatherKingDB.ui.ledger") is False
L.execute('CHECK("Show the farming ledger box (all profiles)"):Click()'); assert L.eval("GatherKingDB.ui.ledger") is True
# export / import from the page
L.execute('BTN("Export all"):Click()')
box = L.eval('(function() for _, f in ipairs(FRAMES) do if type(rawget(f, "hint")) == "table" and f.hint.text == "Export a code, or paste one here" then return f end end end)()')
code, n = ns.ExportCode()
assert box.text == code and code.startswith("GK1:") and n == sum(len(list(L.eval("GatherKingDB.nodes")[m].values())) for m in L.eval("GatherKingDB.nodes").keys())
zcode, zn = ns.ExportCode(1440); assert zn == 1
L.execute('BTN("Import"):Click()'); assert "Imported 0 new marker(s)" in last(L)
print("PAGE OK")

# ---- the crown and the Settings section ----
L.execute('KingMakerMinimapButton:Click("RightButton")')
for label in ("Gathering", "Farming ledger", "Switch gathering profile"):
    assert L.eval('MENU_ITEM("%s") ~= nil' % label), label
KM.Show("home")
L.execute('MENU_ITEM("Gathering").fn()'); assert KM.CurrentPage() == "gathering"
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("Farming ledger").fn()'); assert L.eval("GatherKingDB.ui.ledger") is False and not led.shown
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("Farming ledger").fn()'); assert L.eval("GatherKingDB.ui.ledger") is True and led.shown
L.execute('KingMakerMinimapButton:Click("RightButton"); MENU_ITEM("Switch gathering profile").fn(); RUN_TIMERS()')
assert L.eval("MENU_TITLE") == "Gathering profile"
menu = L.eval("MENU"); names = [menu[i].text for i in range(1, len(menu) + 1)]
assert names == ["Default", "Mine only", "Open the Gathering page"], names
assert L.eval('MENU_ITEM("Default").selected') is True
L.execute('MENU_ITEM("Mine only").fn()'); assert L.eval("GatherKingDB.active") == "Mine only"
gt("profile Default")
L.execute('KingMakerMinimapButton.scripts.OnEnter(KingMakerMinimapButton)')
assert any("gathering markers. Profile: Default." in str(x) for x in L.eval("GameTooltip.lines").values())
KM.OpenSettings("gather"); assert not KM.errorShown, last(L)
t = texts(L); assert "Open the Gathering page" in t and "Sync markers with my guild" in t
L.execute('BTN("Open the Gathering page"):Click()'); assert KM.CurrentPage() == "gathering"
gt("bogus"); assert any("Unknown command 'bogus'" in o for o in outputs(L))
gt(""); assert any("/gt settings" in o for o in outputs(L))
assert not KM.errorShown, last(L)
print("SHELL OK")

# ---- migration from the single-settings format, without the Scanner module ----
L2, KM2, ns2 = load(only=["Gather"], seed='GatherKingDB = { version = 1, nodes = {}, settings = { show = { mine = true, herb = false, fish = true, treasure = true }, minimap = false, auto = true, size = 20, minimapAlpha = 0.5 }, ui = { button = true, buttonAngle = 30 } }')
assert L2.eval("GatherKingDB.profiles.Default.size") == 20 and L2.eval("GatherKingDB.profiles.Default.show.herb") == False
assert L2.eval("GatherKingDB.profiles.Default.record.mine") == True and L2.eval("GatherKingDB.settings") is None
assert L2.eval("GatherKingDB.ui.button") is None and L2.eval("GatherKingDB.ui.buttonAngle") is None
# without Scanner, Gather still works and says where scanning went
L2.eval("SlashCmdList.GATHERKING")("scan"); assert "Scanner King" in last(L2)
assert ns2.Price(2770) is None and ns2.FormatMoney(10000) == "|cffffd7001g|r"
KM2.Show("gathering"); assert not KM2.errorShown, last(L2)
L2.execute('BTN("Mat Prices", GatherKingLedger):Click()'); assert any("The Scanner module scans prices" in x for x in texts(L2))
print("MIGRATION OK")

# prices scanned by gather_king 1.x move into the Scanner on first login
L3, KM3, ns3 = load(seed='GatherKingDB = { version = 3, nodes = {}, prices = { [2770] = { p = 450, t = 1700000000 } }, pricesScanned = 1700000000 }')
assert L3.eval("ScannerKingDB.prices[2770].p") == 450 and L3.eval("GatherKingDB.prices") is None
assert ns3.Price(2770)[0] == 450
print("PRICE MOVE OK")

# export / import into another account
added = ns2.ImportCode(code); assert added == n, (added, n)
assert ns2.ImportCode(code) == 0
assert ns2.ImportCode("garbage") == 0
assert L2.eval("GatherKingDB.nodes[1423][1].from") == "an import"
assert ns2.ImportCode(c) == 0  # already imported with the full export above
m = L2.eval("(function() for _, n in ipairs(GatherKingDB.nodes[1451]) do if n.n == 'Mystery' then return n end end end)()"); assert m.item == 999999
print("EXPORT/IMPORT OK")

# moving 1.x data in from a gather_king stub folder: markers and the ledger come along and show
OLD = ("GatherKingDB = { version = 3, active = 'Herbs', nodes = { [1423] = { { t = 'herb', n = 'Peacebloom', x = 0.5, y = 0.5, item = 2447 } } }, "
       "profiles = { Default = {}, Herbs = { show = { herb = true, mine = false } } }, ui = { button = false, buttonAngle = 99, ledger = true, ledgerPos = { 'TOP', 'TOP', 5, -5 } }, "
       "ledger = { items = { [2447] = 7 }, timed = {}, timer = { running = true, elapsed = 60, startedAt = 5 } } }")
L4, KM4, ns4 = load(stubs={"gather_king": OLD})
assert L4.eval("KingMakerDB.moved.GatherKingDB") is not None
assert L4.eval("GatherKingDB.active") == "Herbs" and L4.eval("GatherKingDB.profiles.Herbs.size") == 16
assert L4.eval("GatherKingDB.ui.button") is None and L4.eval("GatherKingDB.ledger.items[2447]") == 7
assert L4.eval("PINS.world") == 1 and L4.eval("GatherKingDB.ledger.timer.running") is False
led4 = L4.eval("GatherKingLedger"); assert led4.shown and led4.points[1][1] == "TOP"
print("STUB MOVE OK")

print("gather: ok")
