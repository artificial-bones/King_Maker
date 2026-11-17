# Profit & Loss (new in King Maker 2.7)

What every trade actually made. The Sales Ledger tells you what gold came in and went out; Profit & Loss tells you
what you made on each sale, whenever you bought what you sold, and what the stock you still hold is worth against
what it cost you.

- Everything that reaches you becomes a **lot**: when you got it, how many, what it cost you.
- Everything that leaves **uses lots up**. A sale's P&L is what it brought after the auction house's 5% cut, minus
  what those units cost.
- What you still hold is valued at today's market price after the cut.

It's the **Gold > Profit & Loss** page of the King Maker window, first in the Gold group.

## Where things are

| What | Where |
|---|---|
| The page | King Maker window, **Gold > Profit & Loss** (`/pnl` or `/km profit`) |
| P&L for the last 7 days | The **P&L, 7 days** tile on Home, or hover the crown |
| Each sale's P&L | The **P&L** column on the Sales Ledger's Sales tab |
| What you paid for what you hold | **Your cost** in item tooltips, and in Shopping's tooltips and detail pane |
| Cost and "if sold" for everything you own | **Avg cost** and **If sold** on Inventory's Items tab |
| Settings | King Maker **Settings > Profit & Loss** |

## What becomes a lot

| Where it came from | What it cost you |
|---|---|
| **Auction house purchases**, from any window or addon (read from the "Auction won" mail) | What you paid |
| **Loot**: mobs, skinning, mining, herbs, fishing, chests, containers | Nothing (or its value when looted: a setting) |
| **Vendor purchases** | What you paid |
| **Crafted** (2.8): anything you make from a recipe | What the mats that went into it cost you (oldest or newest first, as you chose) |
| **Disenchanted** (2.8): the dust, essences and shards | Their share of what the item cost, split by what each is worth |
| **Quest rewards** (2.8) | Nothing (or their value then, with the farmed setting) |
| **Trades** (2.8): what someone traded you | The gold you gave (or what you gave, at its worth, for a swap) |
| **Opening stock**: what you owned when tracking began, or the first time a new alt or a bank is seen | Its value that day |

Grey items, soulbound items and quest items are left out.

## Crafting, disenchanting, mail and trades (2.8)

- **Crafting.** When you craft, the mats that left your bags are used up (by the method you chose) and what you made
  becomes a lot that costs what they cost. Mats with no lot (untraced) count at their worth then; thread, vials and
  other vendor reagents at what a vendor charges. "Create all" counts as one batch. An enchant on an item, or
  something you make that binds to you, has nothing to sell: its mats' cost goes to **Used or gone**.
- **Disenchanting.** The item you disenchant is used up, and each dust, essence and shard gets a share of its cost,
  by what each is worth. A green you looted was free, so its mats are too.
- **Mail to your own characters** on this realm and faction is **in transit**: nothing closes, and it's counted until
  that character opens the mailbox. **Mail to anyone else** is gone at once ("mailed to Name", in Used or gone).
- **Quest rewards** become lots that cost nothing.
- **Trades**: what you get is a lot costing the gold you gave; what you give is a sale for the gold you got (a swap of
  items for items counts each side at what you got's worth). A trade that didn't go through records nothing; a gift
  either way is left to the counts.
- Something the module can't see (a craft from another addon's button, mail sent by a mail addon, a client without
  one of these functions) works as in 2.7: the mats go "used or gone" (pending) and the product is untraced.

## Day one

The first time you log in with 2.7, Profit & Loss reads your **whole Sales Ledger** (mails counted twice are left
out), so the purchases and sales you've already made are matched straight away. What you own beyond that becomes
opening stock at today's value. Chat says how many purchases and sales it matched.

## Oldest first or newest first

**Sales use up your oldest stock first (FIFO)** unless you choose otherwise. What you still hold is then what you
bought most recently, so "your cost" is what you paid lately, and an early mistake ages out.

**Newest first (LIFO)**: the last thing you bought is what you sold. A quick flip of an item you also keep a pile of
reads as the flip.

Switch in the counting menu on the page, in Settings, or with `/pnl fifo` / `/pnl lifo`. Every number is worked out
again at once. Over time the total is the same either way; only how much counts as realized now changes.

## Farmed items

**Free** (the default): what you loot cost you nothing, so selling it is all profit.

**Their value when looted**: loot costs what it was worth when you looted it, so P&L shows only what selling added on
top of what the Farming Ledger already counted. `/pnl farmed free` / `/pnl farmed value`.

## Counts keep it honest

The Inventory module counts what each character holds (bags, bank, mailbox, auctions). Your characters on one realm
and faction share their stock: mail between them isn't a sale, and a sale on your bank alt uses up what your main
bought.

- **Used or gone.** When your characters hold fewer than your lots say (you drank the potions, equipped the gear, gave
  it away), those units are closed as "used or gone". For 30 days that's **pending**: a sale mail read late, or the
  units turning up again (a bank not yet opened), undoes it. After 30 days it's final. It's shown beside your profit,
  never in it.
- **Untraced.** When you hold more than your lots explain (a gift, mail from another player), the extra units are
  untraced: valued, never given a made-up cost. **Count them as opening stock** (Holdings, Settings or `/pnl adopt`)
  makes them lots at today's value.
- Nothing is checked while the auction house, mailbox, bank, a merchant, trade or a loot window is open; it catches
  up a couple of seconds after.

## The page

Top, on every tab: **Overview**, **Trades**, **Holdings** and **Export**; **All characters** or **This character**;
the counting menu; the period (**Today**, **7 days**, **30 days**, **All**; Holdings are always "now"); and on Trades
and Holdings, **Search items** by name.

**Overview.**

| Tile | What it is |
|---|---|
| **Realized** | What sales brought after the cut, minus what those units cost, minus deposits on auctions that came back |
| **If sold now** | What what you hold is worth now, after the cut, minus what it cost |
| **Stock at cost** | What what you hold cost you, and what it's worth |
| **Underwater** | Items worth less now than they cost you, and what you'd lose selling them |
| **Used or gone** | What stock that left without a sale had cost you (pending and final) |
| **Sold, cost unknown** | What sales brought for units no lot covered |

Then realized per day (green up, red down; a week per bar on All), **where it came from** (auction buys, farmed,
crafted, opening stock, vendors and trades, deposits lost; click one for those trades) and every item you sold or
hold. Click an item for
its lots; right-click for Price History or to add it to a shopping list. Hover any tile for exactly how it's made.

**Trades.** **By sale**: every sale (and trade), the lots it used (hover it), its P&L, ROI and how long you held the
units. **By buy**: every lot (**AH**, **Farmed**, **Quest**, **Crafted**, **DE**, **Trade**, **Vendor**, **Opening**),
what it cost, how many sold and are left, its realized and open P&L, and whether it's **CLOSED**, **PART** or
**OPEN**; hover a crafted lot for where its cost came from. Filters: **Wins**, **Losses**, **Cost unknown**, and **Not
sold** (stock that left without a sale: pending with the days left, used or gone, used in a craft, mailed to someone).

**Holdings.** What you hold: average cost, cost, worth now, if sold, ROI and age. Underwater items have a red edge and
**UNDER**; hover one for the price that breaks even, how many are on the auction house and what you listed them at
("listed at 3g 10s: +38% if they sell", from auctions posted through the auction house's own Post buttons). **List**
shows only one Shopping list (Oracle's lists too, so a strategy's position at cost is one click). The footer says how
much is untraced, with **Count them as opening stock**.

## Elsewhere

- **Sales Ledger**: a **P&L** column on the Sales tab ("no cost" when no lot covered the sale, "-" when it's older
  than the detail Profit & Loss keeps), a **Realized P&L** line on the Summary, and **Still holding** / **Net if sold
  now** worked out from your lots. Its own **Net cash** is cash, not profit: buying stock lowers it, holding it doesn't.
- **Mailbox**: the line when you close it says what the sales made: "3 sold for 4g 10s (P&L +1g 50s)".
- **Shopping**: "You hold 7 at 3g 02s each; 2g 85s now after the cut" in the item's tooltip, and your cost in its facts.
- **Inventory**: **Avg cost** and **If sold** columns on the Items tab.
- **Home**: **P&L, 7 days** takes the profit tile's place; a note when what you hold is underwater by more than 1g.

## How it adds up with the Farming Ledger

The Farming Ledger counts what you farmed at its value when looted. Profit & Loss counts what you made when you sold
it. With farmed items free, a sale of farmed goods is all profit here; with "their value when looted", P&L shows only
what selling added on top of the Farming Ledger.

## What's kept

Sale-by-sale detail for 60 days (or 120 or 365: a setting), then monthly totals, so your saved data stays small. The
King Dashboard keeps every detail.

## Commands

| Command | |
|---|---|
| `/pnl` | Open Profit & Loss (or `/km profit`); `/profitloss` works too |
| `/pnl status` | Realized for 7 days, if sold now, items held, underwater, in one line |
| `/pnl item [link]` | An item's lots: held, average cost, every lot and what used it |
| `/pnl fifo` / `lifo` | Sales use up your oldest or newest stock first |
| `/pnl farmed free` / `value` | Farmed items cost nothing, or their value when looted |
| `/pnl adopt` | Count untraced items as opening stock |
| `/pnl export` | Trades and lots as comma-separated text |
| `/pnl reset yes` | Start the ledger over from the Sales Ledger (the button in Settings asks first) |

## Settings

| Setting | |
|---|---|
| Sales use up | Oldest first (FIFO) or newest first (LIFO) |
| Farmed items cost | Nothing, or their value when looted |
| Your cost in item tooltips | On by default |
| Keep sale-by-sale detail for | 60, 120 or 365 days |
| Count untraced items as opening stock | Untraced units become lots at today's value |
| Start the ledger over | Forgets every lot and reads your Sales Ledger again (farmed and vendor lots are lost) |

## Limits

- Crafts and mail are followed through Blizzard's own windows: another addon's craft queue or mail sender is missed
  (the 2.7 way takes over: the mats used or gone, the product untraced). COD mail counts as mailed away.
- A quest reward is whatever rose in your bags just after you turned the quest in.
- The same item with different random suffixes ("of the Bear") counts as one item.
- An auction house purchase is known when its mail is read on the character who bought it.

## Checks to make in game (2.8)

Unverified on Forever, so worth one `/run` each (paste into chat). If one prints something unexpected, send the line
along.

| What | Do this |
|---|---|
| What `GetSendMailItem` returns (itemID second, count fourth?) | Put two stacks on a mail, then `/run for i=1,2 do print(GetSendMailItem(i)) print(GetSendMailItemLink(i)) end` |
| Mail to an alt on the same account arrives at once | Mail an item to an alt, log in on it and open the mailbox: P&L shows no "pending" closure for it |
| When a disenchanted item leaves your bags (before or after the loot window) | `/run local f=CreateFrame("Frame") for _,e in ipairs({"BAG_UPDATE_DELAYED","LOOT_OPENED","LOOT_CLOSED"}) do f:RegisterEvent(e) end for _,e in ipairs({"UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_STOP"}) do f:RegisterUnitEvent(e,"player") end f:SetScript("OnEvent",function(_,e) print(format("%.2f",GetTime()),e,C_Item.GetItemCount(ITEMID)) end)` (put the item's ID for ITEMID), then disenchant it |
| The same order while crafting with Create All | The frame above, then craft three of something |
| The trade window's functions | Open a trade, put an item in each side and some gold, then `/run print(GetTradePlayerItemInfo(1)) print(GetTradePlayerItemLink(1)) print(GetTradeTargetItemInfo(1)) print(GetTradeTargetItemLink(1)) print(GetPlayerTradeMoney(), GetTargetTradeMoney())` |
| A recipe's reagents from the game (enchants included) | With the profession window open: `/run local s=C_TradeSkillUI.GetRecipeSchematic(7418,false) print(s and s.outputItemID, s and #s.reagentSlotSchematics)` (7418 is Enchant Bracer - Minor Health) |
| A quest reward arrives after QUEST_TURNED_IN | `/run local f=CreateFrame("Frame") for _,e in ipairs({"QUEST_COMPLETE","QUEST_TURNED_IN","QUEST_FINISHED","BAG_UPDATE_DELAYED"}) do f:RegisterEvent(e) end f:SetScript("OnEvent",function(_,e) print(format("%.2f",GetTime()),e) end)`, then turn in a quest with an item reward |

## For other addons

```lua
ProfitKing.API_VERSION                 -- 1
ProfitKing.Basis(itemID [, pool])      -- { held, cost, avg, each, worth, ifSold, oldest, untraced, onAH, listed,
                                       --   listedEach } or nil (listed: units on the AH you posted, at listedEach)
ProfitKing.Summary(since [, charKey])  -- { realized, proceeds, basis, sales, units, deposits, unknownP, gonePending,
                                       --   goneFinal, ifSold, held, cost, worth, underwater, underwaterLoss, ... }
ProfitKing.Lots(itemID [, pool])       -- { { t, kind, q, left, cost, value, char, src, uses }, ... } newest first
ProfitKing.Trades(since [, charKey])   -- { { t, item, q, proceeds, basis, pl, roi, held, char, unknownQ, parts }, ... }
ProfitKing.ForMail(entry)              -- { pl, basis, unknownQ, parts } for a Sales Ledger sale, or nil
ProfitKing.BoughtHeld(since [, charKey]) -- { held, worth, unpriced, units }: auction purchases you still hold
ProfitKing.IsTracking()                -- true once day one has run
ProfitKing.RegisterCallback(owner, fn) -- fn("CHANGED") after the journal changed (half a second later)
```

Every table returned is a copy. The saved data (`ProfitKingDB`) is described for the King Dashboard in
`E:\King_Dashboard\docs\data-contracts\profit.md`.

## Tests

`python tests/run.py profit` from `AddOns/King_Maker` runs Profit & Loss with the Scanner, Inventory, the Sales Ledger
and Shopping against a stand-in for the game (needs `pip install lupa`).
