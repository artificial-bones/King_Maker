# King Maker

One addon for **World of Warcraft: Forever** that does the lot: auction house prices and price history, crafting
profits, the cheapest way to level a profession, your sales ledger, everything you own and your net worth, which mobs
are worth farming, gathering spots, what quests are worth and rested XP. All of it in one window, one minimap button and
one set of auction house prices.

**[Download the latest release](https://github.com/artificial-bones/King_Maker/releases/latest)** (`King_Maker.zip`),
or install **King Maker** from CurseForge.

## New in 2.0: one addon, one window

King Maker used to be eleven separate addons (Scanner King, Econ King, Market King, ...). In 2.0 they're one addon
with one window: a sidebar of pages, a Home page with your numbers at a glance, one Settings page, and one crown on
the minimap. Every feature is still there, and every old slash command still works.

**Upgrading from 1.x keeps everything.** The download still has small folders with the old names (`Scanner_King`,
`Econ_King`, ...). They carry your old settings, prices, history, ledger and the rest into King Maker the first time
you log in, and King Maker tells you in chat when it's done. After that you can delete those old-name folders, or
just leave them.

## Install

1. Download `King_Maker.zip` from the [latest release](https://github.com/artificial-bones/King_Maker/releases/latest)
   (or let the CurseForge app install it).
2. Unzip it and copy **every** folder in it into your AddOns folder (say yes to replace). On the Forever client it
   is `World of Warcraft\_forever_\Interface\AddOns\` (if your client folder is named differently, use the one that
   holds your Forever client).
3. Restart the game. A `/reload` isn't enough the first time: the game only finds new addons at startup.
4. Click the **crown** on the minimap.

Your settings and data live in `WTF`, not in the addon folders, so updating never loses them.

### The minimap crown

- **Left-click**: a drawer with **King Maker** on top, then every other addon's minimap button (Questie, DBM,
  Details, anything that uses LibDBIcon, and other buttons around the minimap's edge). Each one works exactly as
  before: clicks, right-clicks, tooltips and menus.
- **Right-click**: quick actions: Deep Scan, Material Scan, Market Scan, the farm tracker, the farming ledger, any
  page.
- **Drag** it anywhere around the minimap. `/km button` hides it.

### For the best experience, also install Questie and QuestieDB

[Questie](https://github.com/Questie/Questie) and its database,
[QuestieDB](https://github.com/Questie/QuestieDB/releases), aren't part of King Maker but make it much better:

- **Mob Farming** gets every mob in the game from QuestieDB (levels, zones, spawn points, drops) instead of only the
  mobs you've seen yourself.


## The pages

| Group | Page | Slash | What it does |
|---|---|---|---|
| | Home | `/km` | Your numbers at a glance and every quick action |
| Auction House | Prices | `/sk` | Scans and today's prices |
| Auction House | Price History | `/ek` | Every item's price and supply over time |
| Auction House | Sales Ledger | `/mlk` | What you sold and bought, profit, buyers, what isn't selling |
| Crafting | Crafting Profits | `/mk` | The most profitable crafts for your professions |
| Crafting | Skill-ups | `/suk` | The cheapest way to level a profession |
| Gold | Inventory | `/ik` | Everything on every character, and your net worth |
| Gold | Quest Gold | `/qk gold` | What the level 48+ quests left are worth, zone by zone |
| Farming | Mob Farming, White Items | `/fk` | Which mobs and white items are worth farming |
| Farming | Gathering | `/gt` | Mining, herb, fishing and treasure spots on your maps |
| Characters | Rested XP | `/rk` | Rested XP on all your characters |
| | Settings | `/km settings` | Everything, module by module |

### Prices (was Scanner King)

The price engine every other page reads from.

- **Three scans**, from buttons on the auction house title bar (or the crown's quick actions):
  - **Material Scan** prices every Trade Goods item plus anything the other pages ask for.
  - **Market Scan** prices your chosen professions: everything they make and use.
  - **Deep Scan** prices every item on the auction house. Its **market price** comes from the cheapest 15 to 30% of
    listings, so one silly listing doesn't decide it, and it keeps the lowest buyout and how many are listed.
- **A King Maker section in every item tooltip**: auction house, vendor or disenchant (which pays most, and by how
  much), market price and when it was scanned, the 30-day average and trend, who drops it, the 3 most valuable things
  to craft from it, what it costs to craft and which of your characters can, what a recipe teaches and who can learn
  it, your shopping-list goal, and how many you own. Each part can be switched off, or held back until you press Shift.
- **The price list**, grouped like the auction house, with search and sortable columns.
- **Guild sharing**: Trade Goods prices go to guildmates running King Maker after every scan.

[Full guide](AddOns/King_Maker/Modules/Scanner#readme)

### Price History (was Econ King)

The long-term memory of the auction house: every scan is kept, so you can see how any item's price and supply move.

- **Every item, every category**: market price, today against its 30-day average, the 7-day trend, units listed and
  supply against normal.
- **Item pages** with averages, lows and highs, volatility, units leaving per day, and **price and supply graphs**
  over 7 days, 30 days, 90 days, a year or everything, and how price follows supply.
- **Deals** (at least 20% under the 30-day average), **favorites**, and **Ask guild** to fill gaps between your scans.

[Full guide](AddOns/King_Maker/Modules/Econ#readme)

### Sales Ledger (was Mail King)

Your auction house mail as a ledger: what you actually made, where it came from, who's buying, what isn't selling.

- **Every sale, purchase, expired and cancelled auction**, recorded once and dated when it happened.
- **Summary**: profit, income, the auction house cut, spent and deposits lost, with a profit-per-day chart.
- **Strategies** (Herbalism, Mining, Cloth, Mob drops...) so you see which farms pay off.
- **Items**, **Not selling** (and why it might be stuck), **Buyers** and **Sellers**, and **Export** to a spreadsheet.
- **My characters** beside the mailbox: click an alt to put its name in Send Mail.

[Full guide](AddOns/King_Maker/Modules/Mail#readme)

### Crafting Profits (was Market King)

For every item your professions make: sell the raw materials, craft and sell, or craft and disenchant?

- **Every WoW: Forever recipe** (over 2,200, Forever's new ones included) for nine professions, ranked most profitable
  first, after the 5% auction cut.
- **Two ways to count materials**: *Yrgna Special* treats them as bought (finds flips), *Ethical Gaming* treats them
  as farmed.
- **Disenchanting**, or **DE only** to hunt disenchant profits; **your recipes** or the patterns you lack.
- A **red line** where crafting stops paying, and a hover breakdown of every material and price.

[Full guide](AddOns/King_Maker/Modules/Market#readme)

### Skill-ups (was Skillup King)

The cheapest way to level a profession: what to craft at every skill point, at today's prices.

- **A plan from your skill to the top**: what to make, how many, the cost per craft and per point, and the total,
  counting what you get back by selling, disenchanting or vendoring.
- **Trainer reminders**, **patterns you lack** with their price, and a **shopping list**.

[Full guide](AddOns/King_Maker/Modules/Skillup#readme)

### Inventory (was Inventory King)

Everything on every character (bags, bank, warband bank, mailbox, your auctions still up), what it's worth, and your
net worth.

- **Overview**: net worth, gold on characters and in mailboxes, item value, 30 days of net worth, every character
  ranked.
- **Items**: auction house categories, filter by character and place, search, sort any column, **Export**.
- **Item tooltips** show how many you own and where.
- A **red X on the cheapest stack** in your bags, for when you need the space.

Log in on each character and open each bank once. [Full guide](AddOns/King_Maker/Modules/Inventory#readme)

### Mob Farming and White Items (was Farm King)

Ranks mobs by the average gold a kill is worth: coin plus each drop's chance times what it sells for.

- **Drop rates from real kills**: every loot window you open is recorded.
- **Best farms**, favorites, recent kills, this zone and every zone; **mob pages** with every drop's chance and value.
- **Track on map** (with QuestieDB), **White Items** worth farming, and the **farm tracker**: a small box that
  tallies kills, drops and coin, with a timer for gold per hour.

[Full guide](AddOns/King_Maker/Modules/Farm#readme)

### Gathering (was Gather King)

Marks mining, herb, fishing and treasure spots on your world map and minimap, and tracks what your gathering is worth.

- **Auto-tags nodes when you harvest them**, or mark one by hand: `/gt mine thorium`.
- **Markers** with size, opacity and per-type show/hide; filters like `/gt only thorium, mithril`.
- **Loot stats per node**, a **farming ledger** with a timer, **profiles**, **guild sync** and share codes.
- Works with **Leatrix Maps**.

[Full guide](AddOns/King_Maker/Modules/Gather#readme)

### Quest Gold (was Quest King)

Since Forever's November hotfix, most quests of level 48 and up pay gold. Quest Gold works out what each one is
worth and where the most is left for the character you're on.

- **Every 48+ quest** (853 of them, in 40 zones) for your faction and class, with the zones ranked by the gold
  you have left to earn there: quests left of total, and what they're worth.
- **Each quest's worth**: its gold, plus the best reward item at today's prices (auction house after the cut, or
  a vendor), plus any item it always gives, minus what the items you hand in would sell for.
- **Done, in your log, ready, your level too low, or after another quest**, for the character you're logged in on.
- **Forever's real quest gold** is learned as you quest (quest givers, your log, turn-ins), and **Ask the game**
  fetches a whole zone's at once. Amounts not seen yet are estimates, marked ~.
- **Bag cleanup** marks quest items you no longer need (Bagnon too).

Dungeon Quests is gone in 2.4.0: other addons do dungeon quests better.

[Full guide](AddOns/King_Maker/Modules/Quest#readme)

### Rested XP (was Rested King)

How much rested XP every character has built up, when each one is full, and where they're resting.

[Full guide](AddOns/King_Maker/Modules/Rested#readme)

## Credits

Thank you to the [Questie](https://github.com/Questie/Questie) team for Questie and
[QuestieDB](https://github.com/Questie/QuestieDB). Their quest, NPC and item database is what lets Mob Farming know
every mob, spawn point and drop in the game. King Maker only reads that data; it
doesn't include or change any of it, so install Questie and QuestieDB from their own pages and support their authors.

**Recipe data from [ForeverDB.net](https://foreverdb.net)** (GPL-3.0): every Forever recipe, its reagents, skill
ranges and where it's learned, used by Crafting Profits, Skill-ups and the item tooltips. Thank you to ForeverDB for
collecting it and sharing it.

**Quest data from [CMaNGOS classic-db](https://github.com/cmangos/classic-db)** (GPL-3.0), the open Classic world
database: quest levels, requirements and rewards for Quest Gold, with zones and Forever's own quests from ForeverDB.net.

Thanks also to the authors of LibStub, CallbackHandler and HereBeDragons, which King Maker includes.

King Maker is free software under the [GNU General Public License v3](LICENSE).

## For maintainers

The addon is `AddOns/King_Maker` (design: [docs/unified.md](docs/unified.md)); the other `AddOns/*` folders are the
1.x stubs that move old saved data in. Tests: `cd AddOns/King_Maker && python tests/run.py`. To publish a release,
push a tag like `v2.0.0` (or run the **Release** workflow from the Actions tab): it zips `AddOns` into
`King_Maker.zip`, attaches it to a GitHub release and uploads it to CurseForge. `./build.sh` makes the same zip
locally.
