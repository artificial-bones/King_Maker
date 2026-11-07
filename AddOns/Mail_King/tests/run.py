# Runs Mail King against a stand-in for the game and its mailbox:
#   python3 tests/run.py .
import sys
from lupa import lua51
root = sys.argv[1] if len(sys.argv) > 1 else "."
DAY = 86400

def toc_files(path, name):
    return [l.strip().replace("\\", "/") for l in open(f"{path}/{name}.toc") if l.strip() and not l.startswith("#")]

def fresh(farm_king=False):
    L = lua51.LuaRuntime()
    L.execute(open(f"{root}/tests/mock.lua").read())
    L.execute("""
NOW = 1760000000
date = os.date
function GetServerTime() return NOW end
function GetRealmName() return "Forever" end
MONEY = 1234567
function GetMoney() return MONEY end
C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }
function hooksecurefunc(t, k, fn) local old = t[k]; t[k] = function(...) local r = { old(...) }; fn(...); return unpack(r) end end
-- items: name, class, subclass
ITEMS = { [2589] = { "Linen Cloth", 7, 5 }, [2770] = { "Copper Ore", 7, 7 }, [6000] = { "Green Sword", 2, 0 },
  [4306] = { "Silk Cloth", 7, 5 }, [9999] = { "Wolf Fang", 15, 0 } }
local byName = {} for id, i in pairs(ITEMS) do byName[i[1]] = id end
C_Item.GetItemInfo = function(id) local i = ITEMS[id]; if i then return i[1], "", 1 end end
C_Item.GetItemInfoInstant = function(id)
  if type(id) == "string" then id = byName[id] end
  local i = ITEMS[id]; if i then return id, "", "", "", 0, i[2], i[3] end
end
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
-- the mailbox: { subject, money, daysLeft, invoice = { type, item, who, bid, buyout, dep, cut, n }, att = { name, id, n } }
INBOX = {}
function GetInboxNumItems() return #INBOX end
function GetInboxHeaderInfo(i) local m = INBOX[i]; return nil, nil, "Auction House", m[1], m[2] or 0, 0, m[3] or 30 end
function GetInboxInvoiceInfo(i)
  local v = INBOX[i][4]; if not v then return nil end
  return v[1], v[2], v[3], v[4], v[5], v[6], v[7], 0, 0, v[8]
end
function GetInboxItem(i, n) local a = INBOX[i][5]; if a and (n or 1) == 1 then return a[1], a[2], 0, a[3] end end
function MAIL(box) INBOX = box; FIRE("MAIL_SHOW"); RUN_TIMERS() end
-- the auction house
C_AuctionHouse.CalculateCommodityDeposit = function(id, duration, n) return 30 * n end
C_AuctionHouse.CalculateItemDeposit = function(loc, duration, n) return 500 end
C_AuctionHouse.PostCommodity = function() end
C_AuctionHouse.PostItem = function() end
C_Item.GetItemID = function(loc) return loc.id end
C_Item.GetItemName = function(loc) return ITEMS[loc.id][1] end
-- bags: bag -> { { itemID, count, bound } }
BAGS = {}
C_Container = {
  GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) local i = BAGS[bag][slot]; if i then return { itemID = i[1], stackCount = i[2], isBound = i[3] } end end,
}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
Enum.BagIndex = { Backpack = 0, Bag_1 = 1, ReagentBag = 5, Bank = -1, CharacterBankTab_1 = 6, AccountBankTab_1 = 12 }
OWNED = {}
C_AuctionHouse.GetNumOwnedAuctions = function() return #OWNED end
C_AuctionHouse.GetOwnedAuctionInfo = function(i) return OWNED[i] end
MenuUtil = { CreateContextMenu = function(owner, gen)
  local items = {}
  local function add(_, text, a, b) items[#items + 1] = { text = text, fn = b or a } end
  local root = { CreateTitle = function() end, CreateButton = add, CreateRadio = add }
  gen(owner, root)
  MENU = items
end }
""")
    if farm_king:
        L.execute("FarmKing = { IsDrop = function(id) return id == 9999 end }")
    ns = L.table()
    for fn in toc_files(root, "Mail_King"):
        L.execute(open(f"{root}/{fn}").read(), "Mail_King", ns)
    L.execute('FIRE("ADDON_LOADED", "Mail_King"); FIRE("PLAYER_LOGIN"); RUN_TIMERS()')
    return L, ns

def entries(L): return list(L.eval("MailKingDB.entries").values())
def last(L): return L.eval("OUTPUT[#OUTPUT]")

L, ns = fresh(True)
NOW = L.eval("NOW")
assert ns.ParseSubject("Auction successful: Linen Cloth (20)") == ("sale", "Linen Cloth", 20)
assert ns.ParseSubject("Auction won: Green Sword")[0] == "buy"
assert ns.ParseSubject("Hello there") is None

# Posting: the deposit is noted
L.execute("""
local function sellFrame(item, n, extra)
  local b = { scripts = {}, enabled = true }
  function b:HookScript(k, fn) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end fn(...) end end
  function b:IsEnabled() return self.enabled end
  local fr = { PostButton = b, item = item }
  function fr:GetItem() return self.item end
  function fr:GetQuantity() return n end
  function fr:GetDuration() return 1 end
  for k, v in pairs(extra) do fr[k] = function() return v end end
  return fr
end
AuctionHouseFrame = { CommoditiesSellFrame = sellFrame({ id = 2589 }, 20, { GetUnitPrice = 100 }),
                      ItemSellFrame = sellFrame({ id = 6000 }, 1, { GetBuyout = 10000 }) }
FIRE("AUCTION_HOUSE_SHOW")
-- press Post: the window is read on the press, the post noted on the click (after the window clears)
local c = AuctionHouseFrame.CommoditiesSellFrame
c.PostButton.scripts.OnMouseDown(c.PostButton); c.item = nil; c.PostButton.scripts.OnClick(c.PostButton)
local i = AuctionHouseFrame.ItemSellFrame
i.PostButton.scripts.OnMouseDown(i.PostButton); i.PostButton.scripts.OnClick(i.PostButton)
-- a disabled button posts nothing
i.PostButton.enabled = false; i.PostButton.scripts.OnMouseDown(i.PostButton); i.PostButton.scripts.OnClick(i.PostButton)
FIRE("AUCTION_HOUSE_SHOW") -- hooks only once
""")
assert L.eval("C_AuctionHouse.PostItem ~= nil")
posts = list(L.eval("MailKingDB.posts").values())
assert len(posts) == 2 and posts[0].id == 2589 and posts[0].dep == 600 and posts[0].n == 20 and posts[1].dep == 500, len(posts)
assert posts[0].each == 100 and posts[1].each == 10000

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
assert len(es) == 3, ([(e.kind, e.name) for e in es], list(L.eval("out or {}").values())[-5:])
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
L.execute('FIRE("MAIL_CLOSED")'); assert "sold for" in last(L) and "bought for" in last(L), last(L)

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

# The window: every tab draws, right-click sets a strategy
L.execute('SlashCmdList.MAILKING("")')
for t in ["summary", "sale", "buy", "expired", "items", "unsold", "buyers"]:
    ns.SelectTab(t)
ns.StrategyMenu(L.table(), 2589, "Linen Cloth")
menu = list(L.eval("MENU").values())
assert menu[0].text == "Automatic" and any(m.text == "Mining" for m in menu)
next(m for m in menu if m.text == "Mining").fn()
assert L.eval("MailKingDB.strategy[2589]") == "Mining"
L.execute('function StaticPopup_Show(name, _, _, data) StaticPopupDialogs[name].OnAccept({ editBox = { GetText = function() return "Night farm" end } }, data) end')
next(m for m in menu if m.text == "New strategy...").fn()
assert L.eval("MailKingDB.strategy[2589]") == "Night farm" and L.eval("MailKingDB.custom[2]") == "Night farm"

# Export
text, n = ns.ExportText()
lines = text.split("\n")
assert n == 6 and lines[0].startswith("date,kind,item") and len(lines) == 7 and "Linen Cloth" in lines[1]

# Other addons
assert L.eval("MailKing.Summary(0)").sales == 4
assert len(list(L.eval("MailKing.GetEntries()").values())) == 6
assert L.eval("MailKing.StrategyOf(2770)") == "Mining"

# Slash commands
L.execute('SlashCmdList.MAILKING("status")'); assert "6 mails recorded" in last(L), last(L)
L.execute('SlashCmdList.MAILKING("reset yes")'); assert len(entries(L)) == 0

# Commodity invoices can give 0 for how many sold: the subject's count is used
L, ns = fresh()
L.execute('MAIL({ { "Auction successful: Silk Cloth (20)", 1900, 30, { "seller", "Silk Cloth", "Bob", 2000, 2000, 0, 100, 0 } } })')
assert entries(L)[0].n == 20 and ns.Summary(0)["items"][1].units == 20
# and old entries saved with 0 count as 1
L.execute('MailKingDB.entries[1].n = 0'); ns.Prune(); assert entries(L)[0].n == 1
# the window never reassigns Blizzard's globals (that taints them and gets the addon blocked)
src = "".join(open(f"{root}/{f}").read() for f in toc_files(root, "Mail_King"))
assert "StaticPopupDialogs =" not in src

# Without an invoice a sale counts what arrived
L, ns = fresh()
L.execute('MAIL({ { "Auction successful: Copper Ore (10)", 950, 30 } })')
e = entries(L)[0]; assert e.g == 950 and e.cut == 0 and e.n == 10 and e.item == 2770
assert ns.Summary(0).strategies[1].key == "Mining"

# Buyers: who buys from you, how often, what
L, ns = fresh()
def sale(item, n, gold, who, days=30):
    return f'{{ "Auction successful: {item} ({n})", {gold}, {days}, {{ "seller", "{item}", "{who}", {gold}, {gold}, 0, 0, {n} }} }}'
L.execute("MAIL({" + ",".join([
    sale("Linen Cloth", 20, 2000, "Bob", 30), sale("Linen Cloth", 20, 2100, "Bob", 29), sale("Silk Cloth", 10, 5000, "Bob", 28),
    sale("Linen Cloth", 5, 500, "Cid", 27), sale("Copper Ore", 10, 900, "Dee", 26),
    '{ "Auction successful: Copper Ore (5)", 450, 25 }',  # no invoice: no buyer's name
    '{ "Auction won: Green Sword", 0, 30, { "buyer", "Green Sword", "Ann", 5000, 5000, 0, 0, 1 }, { "Green Sword", 6000, 1 } }',
]) + "})")
b = ns.Buyers(0)
rows = list(b.rows.values())
assert [r.who for r in rows] == ["Bob", "Dee", "Cid"]  # ties: who paid more and b.unknown == 1 and b.mails == 5
bob = rows[0]
assert bob.mails == 3 and bob.units == 50 and bob.gold == 9100 and bob.regular and abs(bob.share - 0.6) < 1e-9
assert bob.fav.name == "Silk Cloth" and bob.kinds == 2 and not rows[1].regular
assert [i.name for i in ns.BuyerItems(bob).values()] == ["Silk Cloth", "Linen Cloth"]
sellers = list(ns.Buyers(0, None, "buy").rows.values())
assert len(sellers) == 1 and sellers[0].who == "Ann" and sellers[0].gold == 5000
assert L.eval("MailKing.Buyers(0)")[1].who == "Bob"
# the Buyers page; clicking a buyer shows only their sales
L.execute('SlashCmdList.MAILKING("")'); ns.SelectTab("buyers")
ns.SelectTab("sale", None, "Bob")
assert any("Buyer: Bob" in (t.text or "") for t in L.eval("FONTS").values())
ns.SelectTab("sale")  # again: everyone
ns.SelectTab("summary")
assert any("Best buyer: Bob, 3 sales (60%)" in (t.text or "") for t in L.eval("FONTS").values())

# Not selling: what came back, what you asked, against the market
L, ns = fresh()
L.execute("ScannerKing = { GetMarketPrice = function(id) return ({ [2589] = 100, [2770] = 50 })[id] end }")
L.execute("""MailKingDB.posts = { { id = 2589, name = "Linen Cloth", n = 20, dep = 600, each = 150, t = NOW },
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
# with Inventory King: how many you still have
L.execute("InventoryKing = { GetCount = function(id) return id == 2589 and 40 or 0, {} end }")
assert {r.name: r for r in ns.NotSelling(0).values()}["Linen Cloth"].held == 40
assert L.eval("MailKing.Stock(2589)") == 40
L.execute('SlashCmdList.MAILKING("")'); ns.SelectTab("unsold")
assert any("came back unsold" in (t.text or "") for t in L.eval("FONTS").values())
# without Inventory King the summary and Stock() still work
L.execute("InventoryKing = nil"); assert L.eval("MailKing.Stock(2589)") == 0
ns.SelectTab("summary")
print("all Mail King tests passed")
