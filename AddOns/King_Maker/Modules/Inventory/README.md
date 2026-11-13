# Inventory (was Inventory King)

The asset side of King Maker. Everything you own on every character, what it's worth, and your net
worth: the gold on every character plus everything they hold that can be sold.

- The **Scanner** prices it all, the **Sales Ledger** tells you what you sold.
- **Inventory** tells you what you've got.

Since King Maker 2.0 it has no window or minimap button of its own: it's the **Gold > Inventory**
page of the King Maker window. Your Inventory King 1.x data and settings move in by themselves.

## Where things are

| What | Where |
|---|---|
| Overview and Items | King Maker window, **Gold > Inventory** (`/ik` or `/km inventory`) |
| Open it from the minimap | Right-click the King Maker crown: **Inventory** |
| Net worth at a glance | Hover the crown, or the **Net worth** tile on Home |
| Tooltip, price and vendor settings, forgetting a character | King Maker **Settings > Inventory** |

## Getting data in

Log in on each of your characters once, and open each one's bank once. That's it: from then on
Inventory keeps up as you play.

| Where | When it's read |
|---|---|
| Bags | Whenever they change |
| Bank | When you open it. The game only lets addons read the bank while it's open |
| Warband bank | When you open it, kept once under "Warband" |
| Mailbox | Items attached to mail, and gold waiting in it, whenever you open it |
| On the auction house | Your auctions still up, whenever the auction house lists them (the Auctions tab) |
| Gold | Whenever it changes |

Soulbound items are left out: they can't be sold, so they aren't worth anything.

## The page

Two tabs at the top, **Overview** and **Items**. **Valued at** and **Export** sit top right on both.

**Overview.** Your net worth, the gold on your characters, the gold waiting in their mailboxes, what
your items are worth and how many there are. Below that, net worth for the last 30 days (gold at the
bottom of each bar, items stacked on top; hover a bar for the numbers), and every character with
their level, gold, mailbox, items, net worth, share of the total, when you last played them and when
their bank was last seen. Click a column to sort. Click a character for their items; right-click to
forget one you've deleted or moved.

**Items.** Every item you own.

- **Categories** down the left, the way the auction house sorts them (Trade Goods, then Cloth, Herb,
  Metal & Stone...), each with what it's worth. Click the open one again to close it. The **Sales
  Ledger's strategies** are listed under them, so you can see what your herb farm is sitting on.
- **Whose:** all characters (with the warband bank) or one.
- **Where:** everywhere, or just bags, bank, mailbox or the auction house.
- **Search** by item name or category.
- **Click a column to sort**: bags, bank, mail, on AH, total, how many characters hold it, price each,
  worth. A price marked **(v)** is a vendor price.
- Hover an item for who holds it and where. Shift-click links it in chat.

**Item tooltips** everywhere show how many you own and on which characters.

**Cheapest stack.** When your bags are full, the stack you'd lose least by deleting gets a **red X** in the
bottom-left corner of its slot (Bagnon or the game's bags) and a line in its tooltip. A stack is worth the vendor
price or the auction price after the 5% cut, whichever is more, times the stack. Quest items, keys, profession
tools and anything with no price are never marked; `/ik keep <item>` protects one more.

## What it's worth

Items are valued at the Scanner's **market price** (from a Deep Scan), or its lowest buyout if you
prefer. An item the auction house has no price for counts at what a vendor would pay; turn that off
if you'd rather it counted as nothing. Change both with the **Valued at** button or in Settings.

**Net worth = gold on your characters + gold in their mailboxes + what your items are worth.**

## Coming from Mail King 1.1

Mail King's Stock page moved here in 1.2. If your Mail King data still holds its old stock and gold,
Inventory brings it over once (every character's items and gold), so nothing is lost. That works
whether the old data was already in King Maker or arrives from an old Mail_King folder.

## Export

**Export** (or `/ik export`) opens every item and every character as comma-separated text. Press
Ctrl+A, then Ctrl+C, and paste it into a spreadsheet.

## Commands

| Command | |
|---|---|
| `/ik` | Open or close the Inventory page |
| `/ik status` | Your net worth in one line |
| `/ik price market` / `lowest` | Value items at the market price or the lowest buyout |
| `/ik vendor on` / `off` | Items with no auction price count at their vendor price |
| `/ik tooltip on` / `off` | How many you own, in item tooltips |
| `/ik cheapest on` / `off` | The red X on the cheapest stack in your bags |
| `/ik keep <item>` | Never mark that item as cheapest (again to undo) |
| `/ik forget Name-Realm` | Forget a deleted or moved character |
| `/ik export` | Items and characters as text for a spreadsheet |

`/ik button` now points you to the King Maker crown (`/km button`).

## For addon authors

```lua
InventoryKing.GetCount(itemID)    -- total, { ["Name-Realm"] = n } across bags, bank, mail and auctions
InventoryKing.NetWorth()          -- { total, gold, mail, assets, items, chars }, in copper
InventoryKing.GetCharacters()     -- { { who, class, level, gold, mail, assets, items, worth, seen, bankSeen } }
InventoryKing.GetHistory(days, who) -- { { day, gold, assets, total } }, oldest first
```

## Limits

- A character's numbers are as of when you last played them, and their bank as of when you last
  opened it.
- Equipped gear isn't counted (it's soulbound anyway).
- The mailbox shows at most 50 mails at a time, so mail beyond that isn't seen until you clear some.

## Tests

`python tests/run.py inventory` from `AddOns/King_Maker` runs Inventory with the Scanner and the
Sales Ledger against a stand-in for the game (needs `pip install lupa`).
