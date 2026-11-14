# Scanner (was Scanner King)

![Scanner King](../../../../screenshots/Scanner_King.png)

The auction house scanner of King Maker. It scans the auction house and keeps
the prices every other part of King Maker reads: Price History, Crafting
Profits, Skill-ups, Mob Farming, Gathering, the Sales Ledger and Inventory.

Since King Maker 2.0 it lives inside King Maker: no window or minimap button of
its own. Your Scanner King 1.x prices and settings move in by themselves.

## Where things are

| What | Where |
|---|---|
| The price list | King Maker window, **Auction House > Prices** (`/sk` or `/km prices`) |
| Scan | The auction house title bar, the Prices page, Crafting Profits, and the crown's right-click menu (at the auction house) |
| Tooltip and guild settings | King Maker **Settings > Scanner** |
| Price age | The status box under the King Maker sidebar, and the Home page |

## Scanning

King Maker has **one Scan**: a gold button in the auction house title bar (and
on the Prices page, on Crafting Profits, in the crown's right-click menu while
the auction house is open, and `/sk scan`). What a click does depends on what
the game allows right now, and the button's tooltip says which one you'll get:

- **Full scan** (the Deep Scan) when the game lets King Maker download every
  auction at once, which it allows once every 15 minutes. It prices every item
  on the auction house and works out each item's **market price**: the average
  of the cheapest 15 to 30% of what's listed, so one silly listing doesn't
  decide it. It also keeps the lowest buyout, how many are listed, and in how
  many auctions. About a minute.
- **Quick scan** the rest of the time: every Trade Goods item, plus everything
  the rest of King Maker watches (Price History favorites, Gathering, Shopping
  lists...), plus everything the professions ticked on **Crafting Profits**
  make and use. Lowest prices only. The tooltip says how long until the next
  full scan, for example "Full scan ready in 9 min; a click now does a quick
  scan of Trade Goods plus 1,240 items".

There is no profession picker any more: the ticks on Crafting Profits are the
choice. The scan in progress shows on the button, and hovering it shows what
it's on. Keep the auction house open until the scan says it's done.

On the modern auction house a quick scan takes a handful of requests: it
browses the whole Trade Goods category a page at a time, then looks up the
other items in searches of 100, and only searches item by item if one of those
doesn't answer.

For power users, `/sk deep` forces a full scan with a small progress window
(while the full download is on cooldown it browses every category instead:
lowest prices only), `/sk material` forces a quick scan of Trade Goods and
watched items only, and `/sk market` a quick scan with the ticked professions.

## The Prices page

Everything Scanner has a price for, not just raw materials.

- Across the top: how many prices you have (and when the last quick scan ran),
  when the last full scan ran (amber when it's more than a day old), how many
  have a market price, and whether guild sharing is on.
- The left side groups items the way the auction house does: Metal & Stone,
  Herb, Cloth, Leather, Enchanting, Elemental, and so on. **All** shows
  everything. The mouse wheel scrolls the list when a full scan brings more.
- Type in **Search prices** to filter by name.
- Click a column header (Item, Market, Lowest, Listed, Scanned) to sort by it,
  and again to flip the order. Hover an item for its tooltip.
- **Scan** sits top right (the same one scan as the title bar).

## Tooltips

Every item tooltip (bags, bank, loot, links, the auction house) gets a
**King Maker** section, laid out like this:

| Row | What it shows |
|---|---|
| **King Maker** ... **AUCTION** / **VENDOR** / **DISENCHANT** | Which pays most for one (the auction house after its 5% cut, a vendor, or disenchanting it), and by how much |
| Auction house | The market price (or lowest buyout) and when it was scanned, and by which guildmate if it came from one |
| Lowest buyout, Listed | The cheapest listing, and how many are up in how many auctions |
| 30-day average, 7-day trend | From Price History |
| Vendor, Vendors sell | What a vendor pays you for one, and what you paid a vendor for one |
| Disenchant | On gear: what disenchanting one is worth on average, at today's prices |
| Cost to make, You can craft it | On crafted gear, potions and bags (not on materials like leather or bars): what one costs to make from today's prices, the profit after the cut, and which of your characters can make it |
| Teaches, Known by, Can learn it, Skill too low | On patterns, plans, formulas and recipes: the recipe and its skill, and where each of your characters stands |
| Drops | The two mobs with the best drop chance (your kills and your guild's), with zone; QuestieDB fills in the rest |
| Used in | The professions with recipes that take it, then the **3 most valuable things to make from it**: what each sells for and the profit after the cut (best profit first) |
| Shopping list | On one of your lists: how many you have of how many you want |
| You own | How many, what they're worth, and on which characters |

Every group has its own switch in **Settings > Scanner**: `/sk tooltip off` hides
the prices, `/sk sources off` hides Vendor, Drops and Used in, and
`/sk tip crafts|make|pattern|de|goal off` hides the others. **Short tooltip**
(`/sk tip short on`) shows only the verdict, the price and how many you own
until you hold Shift. Your characters' skills and known recipes come from
opening their profession windows once.

| Command | What it does |
|---|---|
| `/sk` or `/sk show` | Open or close the Prices page |
| `/sk scan` | Scan (the auction house must be open): a full scan when the game allows one, else a quick scan |
| `/sk deep` | Force a full scan, with its progress window (browses every category while the full download is on cooldown) |
| `/sk material` | Force a quick scan of Trade Goods and watched items only |
| `/sk market` | Force a quick scan with the professions ticked on Crafting Profits |
| `/sk tooltip on` / `off` | Prices in item tooltips |
| `/sk sources on` / `off` | Vendor price, drops and recipes in item tooltips |
| `/sk tip crafts\|make\|pattern\|de\|goal\|short` `on` / `off` | Best crafts, craft cost, recipe items, disenchant value, shopping goal; short = details with Shift |
| `/sk status` | How many prices you have, when the last full and quick scans ran, and when a full scan is ready |
| `/sk sync` | Send your prices to your guild now |
| `/sk sync on` / `off` | Turn guild price sharing on or off |

`/sk button` now points you to the King Maker crown (`/km button`).

## Guild sharing

Everyone in your guild running King Maker (or Scanner King 1.x) shares
prices. For each item the newest price wins.

- **Trade Goods and Gathering's raw materials are shared automatically.**
  After a scan your prices go to the guild, and when you log in, guildmates who
  are online send you theirs. Only prices you scanned yourself in the last two
  days are sent, so old prices don't keep circling the guild.
- **Everything else is shared when someone asks.** Price History's **Ask
  guild** buttons ask for just those items. Guildmates who scanned them in the
  last week answer, and anyone who sees a price as fresh as theirs already sent
  stays quiet. Items you scanned yourself in the last hour aren't asked for.

Prices are packed tightly: about 25 to a message, with market price and number
listed included. The game allows about one addon message a second, so sharing
700 Trade Goods takes about 25 seconds. A whole Deep Scan of 3,000 items would
take about 2 minutes after every full scan and again for everyone who logs in,
which is why it isn't sent unasked.

## For addon authors

The `ScannerKing` global is unchanged; see [API.md](API.md).
