# Mail King

![Mail King](../../screenshots/Mail_King.png)

The money side of the King suite. Every auction house mail you open goes into a ledger, so you can
see what you actually made, where it came from, and which of your farms and strategies pay off.

- **Gather King** finds the nodes, **Farm King** finds the mobs, **Scanner King** prices it all.
- **Mail King** tells you what it turned into.

## Requirements

- **Needs:** Nothing. Mail King reads your mail on its own.
- **Better with** (optional):
  - **Scanner King** adds today's market price on the Items page and what your stock is worth.
  - **Farm King** puts items mobs drop under the Mob drops strategy.

## What it records

Open your mailbox and every auction house mail in it is recorded, once:

| Mail | What's kept |
|---|---|
| Auction successful | Price, the auction house cut, the buyer, and when it sold |
| Auction won | What you paid and the seller |
| Auction expired / cancelled | The deposit you lost |

- **Opening the mailbox again changes nothing.** You don't have to take the gold out either: a mail
  is remembered and only ever counted once.
- **Sales are dated when they sold, not when you read the mail.** Auction mail lasts 30 days, so the
  time left on it gives the date.
- **Deposits.** When you post an auction, Mail King notes its deposit, so an expired auction shows
  what it cost you.
- **Your gold.** Every character's gold is noted, and the total is on the Summary page and the
  minimap button.
- **Stock.** Everything you're holding on every character, and what it's worth (see below).
- **Characters.** Each character's mail is kept separately. Look at all of them together, or just
  the one you're on.

## The window

Open it with `/mlk` or the minimap button. Pick the period (**Today**, **7 days**, **30 days** or
**All**) and whose mail you're looking at (all characters, or this one).

- **Summary.** Profit, income, the auction house cut, what you spent and deposits lost. Below that,
  profit per day for the last two weeks, and every strategy ranked by profit with its sell-through.
  Click a strategy to see its items.
- **Sales, Purchases, Expired.** Every one, newest first.
- **Items.** Every item you've traded: units sold, average price, income, spent, sell-through, and
  Scanner King's market price today, so you can see whether you're selling under the market. Click
  a column to sort.

- **Stock.** Everything you're sitting on, per item: how many are in your bags, bank, mailbox and
  auctions still up, across every character and the warband bank, and what it's worth at Scanner
  King's market price. Hover an item to see which character holds it. The Summary page shows your
  gold, your stock and the two together.

**Profit = income (after the cut) − what you spent − deposits lost.**

## Strategies

Every item counts toward a strategy, which is how the ledger answers "which of my farms is working?"
An item gets one automatically, in this order:

1. **Your choice.** Right-click any item, in any list, to pick a strategy or make a new one, such as
   "Arathi wool farm" or "Strath runs".
2. **Flips.** You bought it on the auction house within 30 days before selling it. What you paid and
   what it sold for land on the same line, so its profit is your margin. Something you bought and
   haven't sold counts under **Purchases**.
3. **The kind of material.** Mining, Herbalism, Skinning, Cloth, Enchanting, Cooking, Elemental.
4. **Mob drops.** Farm King knows mobs drop it, from your loot, your guild's, or QuestieDB.
5. **Everything else.** Gear, Consumables, Recipes, Other.

Your choices apply to past sales too, so you can sort old history into strategies whenever you like.

## Stock

Each character's items are noted where Mail King can see them:

- **Bags:** whenever they change.
- **Bank:** when you open it. The bank can't be read anywhere else, so visit it once on each
  character. The warband bank is counted once, under "Warband".
- **Mail:** items still attached to mail in your mailbox.
- **On AH:** your auctions still up, whenever the auction house lists them for you (the Auctions tab).

Soulbound items are left out, since they can't be sold.

## Export

**Export** (or `/mlk export`) gives the whole ledger as comma-separated text. Press Ctrl+A, then
Ctrl+C, and paste it into a spreadsheet.

## Commands

| Command | |
|---|---|
| `/mlk` | Open Mail King |
| `/mlk status` | What's been recorded |
| `/mlk export` | The ledger as text for a spreadsheet |
| `/mlk button on` / `off` | The minimap button |
| `/mlk reset yes` | Clear the whole ledger |

## Works with

Mail King works on its own. Each of these adds to it if you have it:

- **Scanner King.** Today's market price on the Items page, and its money formatting.
- **Farm King.** Items mobs drop go under Mob drops.

## For addon authors

```lua
MailKing.GetEntries()      -- copies of every ledger line: { t, k = "sale"|"buy"|"expired"|"cancelled",
                           --   item, name, n, g = price, cut, dep, who, c = "Name-Realm" }
MailKing.Summary(since)    -- { income, spent, lost, profit, sales } since a server time (0 = all)
MailKing.StrategyOf(itemID)
MailKing.Stock(itemID)     -- how many you hold across every character: bags, bank, mail, auctions
```

## Limits

- Only mail you open is recorded. Mail that expires unread, or that you read before installing Mail
  King, isn't.
- A deposit is known only for auctions posted while Mail King was running.
- A sale mail names the item but doesn't carry its ID. Mail King learns IDs as you post, buy and get
  items back, and looks up the rest by name.

## Tests

```
pip install lupa
python3 tests/run.py .
```
