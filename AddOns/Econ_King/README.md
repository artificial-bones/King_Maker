# Econ King

The long-term memory of the auction house, for the King suite on WoW Forever.
Econ King keeps every scan Scanner King makes, so for any item you can see how
its price and supply have moved over days, weeks and months, and spot what's
cheap right now, what's drying up and what's flooding the market.

Needs **[Scanner King](https://github.com/base-reality-ai/Scanner_King)** 1.5
or newer, which does the scanning. See its
[API.md](https://github.com/base-reality-ai/Scanner_King/blob/main/API.md) for
how the addons connect.

## Install

1. Download this repo (Code, then Download ZIP) and unzip it.
2. The folder must be named `Econ_King` (rename `Econ_King-main`).
3. Put it in `_classic_beta_\Interface\AddOns\` next to `Scanner_King`.

## Getting data in

At the auction house, click **Deep Scan** in the title bar (it comes from
Scanner King, next to Material Scan and Market Scan). It prices every item on
the auction house, and Econ King records it. Material Scans and Market Scans
are recorded too, for the items they cover.

The more often you Deep Scan, the better the history: once or twice a day is
plenty. Scans less than two days apart also tell you how much **left** the
auction house in between (see below).

## The window

Open it with the spyglass button on your minimap or `/ek`.

**Left side.** **Favorites** at the top, then **Deals**, **All items**, and
every item category the auction house has (Trade Goods, Consumable, Armor,
Weapon, Recipe...). Click a category to open its subcategories (Armor: Cloth,
Leather, Mail, Plate...). Scroll the list with the mouse wheel.

**The list.** Click any column to sort by it, click again to flip it:

| Column | What it means |
|---|---|
| Market | Market price at the last scan |
| vs 30d | Market price now compared with its 30-day average. Below zero: cheaper than usual |
| 7d trend | This week's average price compared with last week's |
| Listed | Units on the auction house at the last scan |
| Supply | Listed now compared with the 30-day average. Below zero: drying up |
| Scanned | When it was last seen |

Click the star (or right-click a row) to make it a favorite. Shift-click links
it in chat. **Search every item** at the top looks across everything, whatever
tab you're on.

**Ask guild** (bottom right of every tab) asks guildmates running Scanner King
for their latest prices of the items in that list: favorites, a category, deals
or a search. Their answers fill in prices and become points in each item's
history, so their scans fill the gaps between yours. Only the items you ask
for are sent, which keeps guild traffic small; items you scanned yourself in
the last hour are skipped.

**An item's page.** Click any item. At the top: **< Back** to the list, and
the arrows step to the previous and next item in the list without going back.
The page shows:

- Market price, lowest buyout, how many are listed and in how many auctions.
- 7-day and 30-day averages, today against the 30-day average, the 7-day trend.
- 30-day low and high, and **volatility** (how far the price usually swings
  from its average).
- Average listed over 30 days, and supply now against that.
- **Gone per day**: units that left the auction house between Deep Scans.
- **Ask guild** for the latest price of just this item.
- Two graphs over **7D, 30D, 90D, 1Y or All**: market price (gold) with the
  lowest buyout (grey), and supply: units listed (blue bars) with units gone
  (red). Hover a graph for the numbers on that day.

**Deals** lists items whose market price is at least 20% under their 30-day
average, with at least 5 days of history and a price from the last 2 days.

## Reading the numbers

Blizzard doesn't tell addons what actually sells, so Econ King works with what
the auction house shows:

- **Market price** is the average of the cheapest 15 to 30% of what's listed
  (Scanner King's Deep Scan works it out from every auction), not just the
  single cheapest one, so one silly listing doesn't move it. Material Scans,
  Market Scans and Deep Scans done by browsing (within 15 minutes of the last
  full one) only see the lowest buyout: that goes on the grey line, never the
  market one. An item with no full Deep Scan in 30 days uses its lowest buyout
  instead, and its page says so.
- **Gone** compares two full Deep Scans less than two days apart, auction by auction: units listed at the
  first scan that aren't there at the second were sold, cancelled or expired.
  It can't tell those apart, but over time it's a fair sign of demand,
  especially next to the supply graph: supply falling while lots go means
  people are buying.
- Some ways to use them: a price under its 30-day average with steady demand
  is a buy; supply drying up ahead of a price rise is worth watching; a high
  volatility item is one to buy low and relist, not to hold.

## How much it keeps

Every scan from the last 7 days, then one point per day for 120 days, then one
point per week. Favorites keep one point per day forever. The heavy work after
a Deep Scan is done a little each frame, so the game doesn't freeze.

## Tooltips

Item tooltips show Scanner King's prices, and under them Econ King's 30-day
average, today against it, and the weekly trend. `/ek tooltip off` hides
Econ King's lines; `/sk tooltip off` hides them all.

| Command | What it does |
|---|---|
| `/ek` | Open or close the window |
| `/ek item [link]` | Open an item's page |
| `/ek fav [link]` | Add or remove a favorite |
| `/ek status` | How much history you have |
| `/ek tooltip on` / `off` | Econ King's lines in item tooltips |
| `/ek button on` / `off` | The minimap button |

## For addon authors

```lua
EconKing.GetStats(itemID)    -- market, avg7, avg30, vs30, trend7, listed, supply, gonePerDay, ... or nil
EconKing.GetHistory(itemID)  -- { { time, market, lowest, listed, auctions, added, gone, scans }, ... } oldest first
EconKing.IsFavorite(itemID)
```

## Tests

`python3 tests/run.py . ../Scanner_King` runs Econ King and Scanner King
against a stand-in for the game (needs `pip install lupa`).
