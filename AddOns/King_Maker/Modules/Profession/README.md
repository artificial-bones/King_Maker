# Profession window

When you open a profession, King Maker docks a panel next to the game's window that tells you what your crafts make
you. It only reads: it never crafts and never changes the game's window.

At the top: the **This recipe** and **All crafts** tabs, the **Buy mats / Use my mats** switch and the `-` button.

| Switch | What it means |
|---|---|
| **Buy mats** | The materials are a cost: a craft has to make more than you pay for them (flipping). |
| **Use my mats** | You already have the materials: crafting has to beat selling them raw. Vendor reagents are still a cost. |

If Settings > Profession window > "Count materials as" is *Like Crafting Profits* (the default), the switch flips
Crafting Profits' mode too, so the two always agree. Set to Buy mats or Use my mats there, the switch only changes the panel.

## This recipe

For the recipe you have selected, money first:

- **Profit per craft** in big green or red, Market's **verdict** for the mode you're in (CRAFT, DISENCHANT, SELL RAW,
  SKIP or NO PRICE) and the **margin** (profit over what the materials cost you). A grey line under it shows the
  other mode's verdict.
- **Reagents**: how many you need, how many you have (this character, plus `+N` on your alts), the price of one and the
  cost of the line. A reagent's price is the cheaper of the lowest auction and a vendor (`v` means a vendor sells it).
  Use `-` / `+` to count materials for more than one craft (hold shift to step by 5).
- **The money**: materials, what one craft sells for after the 5% auction cut, the disenchant alternative, the 30-day
  average and 7-day trend, how many are listed and the lowest price, about how many sell a day, and how many to
  **Make** so you don't flood the auction house (a quarter of what's listed, at most one day of units leaving it;
  nothing listed: make 1 to test the market).
- **With Profit & Loss tracking**: **At what you paid** is the profit with the materials you hold counted at what you
  paid for them (farmed ones by P&L's farmed setting), the rest at today's price. **Your last sales** is how many you
  sold in the last 7 days and what they brought each.
- A crafting **cooldown** line when the recipe has one, a small **price chart**, the **star** (a Price History
  favorite) and **History**.

Enchants have nothing to sell, so the card shows what the materials cost.

## All crafts

Every recipe you know in the open profession, ranked by **Profit now**.

| Column | What it shows |
|---|---|
| Profit | One craft's profit in the mode you're in |
| Margin | Profit over what the materials cost you |
| Can make | How many crafts your materials cover (the game's count when it gives one) |
| Listed | How many are on the auction house at your last scan |
| Make | How many to craft without flooding the auction house |
| Profit now | Profit x Make for CRAFT; one craft for DISENCHANT; nothing for sell raw or skip |
| Do | CRAFT, DE (disenchant), RAW (sell raw), SKIP, N/A (no price) |

Click a column to sort by it. Tick **Can make now** to see only what your bags cover, or type in **Search**. Click a
row to show it on This recipe (on the modern window this also selects it in the game's window). The line at the
bottom says how old your prices are, and nudges you to scan at the auction house when they're over 12 hours old.

## Tooltips

When you hover a recipe's item or spell inside the profession window, the tooltip gets one line: the cost, the profit
and the verdict.

## Settings

Go to Settings > Profession window, or type `/km profession`:

| Setting | |
|---|---|
| Show the King Maker panel | On or off |
| Dock it on the | Right or left of the window |
| King Maker lines in recipe tooltips | On or off |
| Count materials as | Like Crafting Profits, Buy mats or Use my mats |

The `-` button collapses the panel to a single line with the selected recipe's profit and verdict.
