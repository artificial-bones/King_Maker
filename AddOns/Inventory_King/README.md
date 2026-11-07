# Inventory King

The asset side of the King suite. Everything you own on every character, what it's worth, and your
net worth: the gold on every character plus everything they hold that can be sold.

- **Scanner King** prices it all, **Mail King** tells you what you sold.
- **Inventory King** tells you what you've got.

## Requirements

- **Needs:** Nothing. Inventory King reads your bags, bank and mail on its own.
- **Better with** (optional):
  - **Scanner King** prices your items. Without it only vendor prices are known.
  - **Mail King** sorts your items into its strategies (Herbalism, Mob drops, Flips...).

## Install

Get it with **[King Maker](https://github.com/artificial-bones/King_Maker/releases/latest)** (every
King addon in one download), or on its own: download this repo, name the folder `Inventory_King`,
and put it in `_classic_beta_\Interface\AddOns\`.

## Getting data in

Log in on each of your characters once, and open each one's bank once. That's it: from then on
Inventory King keeps up as you play.

| Where | When it's read |
|---|---|
| Bags | Whenever they change |
| Bank | When you open it. The game only lets addons read the bank while it's open |
| Warband bank | When you open it, kept once under "Warband" |
| Mailbox | Items attached to mail, and gold waiting in it, whenever you open it |
| On the auction house | Your auctions still up, whenever the auction house lists them (the Auctions tab) |
| Gold | Whenever it changes |

Soulbound items are left out: they can't be sold, so they aren't worth anything.

## The window

Open it with `/ik` or the bag button on the minimap.

**Overview.** Your net worth, the gold on your characters, the gold waiting in their mailboxes, and
what your items are worth. Below that, net worth for the last 30 days (gold and items stacked), and
every character with their gold, mailbox, items, net worth, share of the total, when you last played
them and when their bank was last seen. Click a character for their items; right-click to forget one
you've deleted or moved.

**Items.** Every item you own.

- **Categories** down the left, the way the auction house sorts them (Trade Goods, then Cloth, Herb,
  Metal & Stone...), each with what it's worth. With Mail King installed, its strategies are there
  too, so you can see what your herb farm is sitting on.
- **Whose:** all characters (with the warband bank) or one.
- **Where:** everywhere, or just bags, bank, mailbox or the auction house.
- **Search** by item name or category.
- **Click a column to sort**: bags, bank, mail, on AH, total, how many characters hold it, price each, worth.
- Hover an item for who holds it and where. Shift-click links it in chat.

**Item tooltips** everywhere show how many you own and on which characters.

## What it's worth

Items are valued at Scanner King's **market price** (from a Deep Scan), or its lowest buyout if you
prefer. An item the auction house has no price for counts at what a vendor would pay; turn that off
if you'd rather it counted as nothing. Change both with the **Valued at** button.

**Net worth = gold on your characters + gold in their mailboxes + what your items are worth.**

## Coming from Mail King 1.1

Mail King's Stock page moved here. The first time Inventory King loads, it brings over everything
Mail King knew (every character's items and gold), so nothing is lost.

## Export

**Export** (or `/ik export`) gives every item and every character as comma-separated text. Press
Ctrl+A, then Ctrl+C, and paste it into a spreadsheet.

## Commands

| Command | |
|---|---|
| `/ik` | Open Inventory King |
| `/ik status` | Your net worth in one line |
| `/ik price market` / `lowest` | Value items at the market price or the lowest buyout |
| `/ik vendor on` / `off` | Items with no auction price count at their vendor price |
| `/ik tooltip on` / `off` | How many you own, in item tooltips |
| `/ik forget Name-Realm` | Forget a deleted or moved character |
| `/ik export` | Items and characters as text for a spreadsheet |
| `/ik button on` / `off` | The minimap button |

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

```
pip install lupa
python3 tests/run.py .
```
