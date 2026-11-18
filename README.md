# King Maker

One addon for **World of Warcraft: Forever** that does the lot: auction house prices and price history, crafting
profits (with a profit panel beside the profession window), your sales ledger, profit and loss on every trade, everything you own
and your net worth, which mobs
are worth farming, one tracker and ledger for every farming session, gathering spots, crafting cooldowns on every
character, shopping lists, what quests are worth and rested XP. All of it in one window, one minimap button and
one set of auction house prices.

**[Download the latest release](https://github.com/artificial-bones/King_Maker/releases/latest)** (`King_Maker.zip`),
or install **King Maker** from CurseForge.

## New in 2.8

- **Profit & Loss.** A new page, first in the Gold group: what every trade actually made. Every purchase, loot and
  vendor buy becomes a lot; every sale is matched to what it cost (oldest first, or newest first if you prefer), and
  the cost follows your stock through crafting, disenchanting, mail to your alts, quest rewards and trades. `/pnl`.
- **Home is an overview of your gold**: net worth, this week's results and charts, what needs your attention, where
  your gold came from, the best things to do right now and every character at a glance.
- **Farm Tracker and Farming Ledger.** One floating tracker for mob farming and all gathering (mining, herbs,
  skinning, fishing, pickpocketing, chests, clams and lockboxes), with Start, Pause, Stop and Split. Every session is
  saved: the **Farming Ledger** page shows what each one made, gold per hour, a gold-over-time graph and where the
  money came from. `/farm` or a key binding opens it. It replaces the old farm tracker and farming ledger boxes.
- **Crafting Cooldowns.** Transmutes, Mooncloth and the Salt Shaker on every character: what's ready, what to make,
  profit per craft and per week, and a red count by the page when one is ready on the character you're on. `/cdk`.
- **Shopping, redone.** Deals first (green, biggest saving first), short prices that fit, cost to buy what you still
  want, the 7-day trend, a detail pane with a price chart, and an auction house panel that looks items up, shows how
  many are under your max and steps through the deals (every buy is still your click).
- **Zoom the window**: drag the dots in its bottom-right corner (`/km size 120`, `/km size reset`).
- **Quest Gold looks up quest gold by itself** the first time each character enters a zone, and ships with every
  amount learned so far.
- **Version check**: when a guildmate has a newer King Maker, you get one line in chat. `/km version`.

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
- **Right-click**: quick actions: Deep Scan, Material Scan, Market Scan, the Farm Tracker, any page. A small number
  on the crown means a page has something ready (a crafting cooldown, for one).
- **Drag** it anywhere around the minimap. `/km button` hides it.

### For the best experience, also install Questie and QuestieDB

[Questie](https://github.com/Questie/Questie) and its database,
[QuestieDB](https://github.com/Questie/QuestieDB/releases), aren't part of King Maker but make it much better:

- **Mob Farming** gets every mob in the game from QuestieDB (levels, zones, spawn points, drops) instead of only the
  mobs you've seen yourself.


## The pages

| Group | Page | Slash | What it does |
|---|---|---|---|
| | Home | `/km` | Everything at a glance: net worth, P&L, gold per hour and cooldowns up top, a 30-day chart, what needs your attention, where your gold came from, the best craft / farm / white item / quest zone right now, and your characters |
| Auction House | Prices | `/sk` | Scans and today's prices |
| Auction House | Price History | `/ek` | Every item's price and supply over time |
| Auction House | Shopping | `/shop` | Lists of what to buy with your max price; deals first; buys at the auction house |
| Auction House | Sales Ledger | `/mlk` | What you sold and bought, profit, buyers, what isn't selling |
| Crafting | Crafting Profits | `/mk` | The most profitable crafts for your professions |
| Crafting | Cooldowns | `/cdk` | Transmutes, Mooncloth and salt on every character, and what they're worth |
| Gold | Profit & Loss | `/pnl` | Every sale matched to what you paid; what you hold, at cost and at today's price |
| Gold | Inventory | `/ik` | Everything on every character, and your net worth |
| Gold | Quest Gold | `/qk` | What the level 48+ quests left are worth, zone by zone |
| Farming | Farming Ledger | `/farm` | Every farming session: what it made, gold per hour, graphs |
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
  much), market price and when it was scanned, the 30-day average and trend, who drops it, what the materials to
  craft it cost and whether crafting one to sell pays, which of your characters can craft it, what a recipe teaches
  and who can learn it, your shopping-list goal, and how many you own. Each part can be switched off, or held back
  until you press Shift (the 3 most valuable crafts from a material are there too, off by default).
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
- **Two ways to count materials**: *Buy mats* treats them as a cost (finds flips), *Use my mats* treats them as
  already yours (is crafting worth more than selling them raw?).
- **Disenchanting**, or **DE only** to hunt disenchant profits; **your recipes** or the patterns you lack.
- A **red line** where crafting stops paying, and a hover breakdown of every material and price.

[Full guide](AddOns/King_Maker/Modules/Market#readme)

### Profession window panel

Open a profession and King Maker docks a profit panel beside it.

- **This recipe**: the profit per craft and its margin up front, what the mats cost and the item sells for, how fast
  it sells, how many to make, and, with Profit & Loss on, your profit at what you actually paid for the mats.
- **All crafts**: every recipe you know in that profession, ranked by what it can make you right now (profit per
  craft times how many the auction house will take), with how many your bags can make.

[Full guide](AddOns/King_Maker/Modules/Profession#readme)

### Profit & Loss (new in 2.7)

What every trade actually made. Every auction house purchase, everything you loot, what you buy from vendors, what you
craft, disenchant, get from quests or trade for becomes a lot; every sale uses lots up (oldest first, or newest first
if you'd rather) and its profit is what it brought after the 5% cut minus what those units cost you.

- **Crafting and disenchanting carry the cost** (2.8): a bandage costs what its linen cost you, disenchanted dust its
  share of the item. Mail to your own characters is "in transit", never a gap; mail to anyone else is gone at once.
- **Overview**: realized profit, what you'd make selling what you hold now, stock at cost, what's underwater, and
  beside them (never in them) stock used or gone and sales no purchase covered. Realized per day, where it came from
  (auction buys, farming, crafting, opening stock, vendors and trades) and every item.
- **Trades**: each sale and the lots it used, each purchase and what used it (closed, part, open), what left unsold.
  Search by name.
- **Holdings**: what you hold at cost and at today's price, the underwater ones marked with the price that breaks
  even, and what you listed on the auction house at.
- **Farmed items count as free**, or at their value when looted. Day one reads your whole Sales Ledger, so your past
  flips are matched straight away. A P&L column on the Sales Ledger, your cost in item tooltips, in Shopping and in
  Inventory's Items tab.

`/pnl`. [Full guide](AddOns/King_Maker/Modules/Profit#readme)

### Inventory (was Inventory King)

Everything on every character (bags, bank, warband bank, mailbox, your auctions still up), what it's worth, and your
net worth.

- **Overview**: net worth, gold on characters and in mailboxes, item value, 30 days of net worth, every character
  ranked.
- **Items**: auction house categories, filter by character and place, search, sort any column, **Export**; with
  Profit & Loss, what each item cost you and what selling it now would make.
- **Item tooltips** show how many you own and where.

Log in on each character and open each bank once. [Full guide](AddOns/King_Maker/Modules/Inventory#readme)

### Mob Farming and White Items (was Farm King)

Ranks mobs by the average gold a kill is worth: coin plus each drop's chance times what it sells for.

- **Drop rates from real kills**: every loot window you open is recorded.
- **Best farms**, favorites, recent kills, this zone and every zone; **mob pages** with every drop's chance and value.
- **Track on map** (with QuestieDB) and **White Items** worth farming. Kills and drops also go to the **Farm
  Tracker** (below).

[Full guide](AddOns/King_Maker/Modules/Farm#readme)

### Gathering (was Gather King)

Marks mining, herb, fishing and treasure spots on your world map and minimap, and tracks what your gathering is worth.

- **Auto-tags nodes when you harvest them**, or mark one by hand: `/gt mine thorium`.
- **Markers** with size, opacity and per-type show/hide; filters like `/gt only thorium, mithril`.
- **Loot stats per node**, **profiles**, **guild sync** and share codes. What you gather goes to the **Farm
  Tracker** (below), whose Prices tab lists raw materials by their auction price.
- Works with **Leatrix Maps**.

[Full guide](AddOns/King_Maker/Modules/Gather#readme)

### Farm Tracker and Farming Ledger (new in 2.6)

One tracker for everything you farm, and a ledger of every session.

- **The Farm Tracker**: a small floating box with All, Mobs, Gathering and Prices tabs. Mob loot and coin, mining,
  herbs, skinning, fishing, pickpocketing, chests and opened clams or lockboxes, valued at the auction house after
  its cut (or a vendor, when that pays more). Start, Pause, Stop & save and Split; it pauses itself when you're idle
  and can start itself when you begin farming. Its lists grow with what you loot; drag its corner dots for more rows
  or wider names. Ctrl + mouse wheel zooms it.
- **The Farming Ledger page**: every session with its gold per hour on a chart; click one for a gold-over-time graph,
  where the money came from, and its items, mobs, gathering and money (repairs, vendor, quest gold) tables.
- `/farm` opens or closes the tracker; Key Bindings > AddOns > King Maker has keys for it. `/fk mini` and
  `/gt ledger` still work.

[Full guide](AddOns/King_Maker/Modules/Tracker#readme)

### Quest Gold (was Quest King)

Since Forever's November hotfix, most quests of level 48 and up pay gold. Quest Gold works out what each one is
worth and where the most is left for the character you're on.

- **Every 48+ quest** (853 of them, in 40 zones) for your faction and class, with the zones ranked by the gold
  you have left to earn there: quests left of total, and what they're worth.
- **Each quest's worth**: its gold, plus the best reward item at today's prices (auction house after the cut, or
  a vendor), plus any item it always gives, minus what the items you hand in would sell for.
- **Done, in your log, ready, your level too low, or after another quest**, for the character you're logged in on.
- **Forever's real quest gold** ships with King Maker (every amount learned so far), is looked up by itself the
  first time each character enters a zone, and is learned as you quest (quest givers, your log, turn-ins). Amounts not
  known yet are estimates, marked ~.

Dungeon Quests is gone in 2.4.0: other addons do dungeon quests better.

[Full guide](AddOns/King_Maker/Modules/Quest#readme)

### Shopping

Lists of what you want to buy with your own max price. The page puts deals first (green, biggest saving first) with
what they cost, how far under your max they are and where the price is heading; the sidebar shows a gold count when
something is under your max. At the auction house the Shopping panel looks items up, shows how many are listed under
your max, and buys one click per step: Search all, then Buy, Confirm, Next deal. It never buys on its own, refuses
anything over your max or your gold, and asks twice before spending a quarter of your gold. Lists from Oracle and
Cooldowns show live and read-only. After a scan, one line in chat names what's newly under your max. `/shop`,
`/shop deals`.

[Full guide](AddOns/King_Maker/Modules/Shopping#readme)

### Cooldowns (new in 2.6)

Every profession cooldown on every character: the transmutes (one shared timer, Forever's Legionite included),
Mooncloth and the Salt Shaker, plus any other long cooldown your profession window shows.

- **What's ready**, with a red count by the page when one is ready on the character you're on (gold when only alts
  have one), a chat line and a sound when one comes ready, and a login line for your alts.
- **What it's worth**: the materials and product at today's prices, profit per craft and per week, the best
  transmute right now, and what you own of the materials on every character.
- **A live "Cooldown mats" shopping list** for the next week of cooldowns. `/cdk`.

[Full guide](AddOns/King_Maker/Modules/Cooldowns#readme)

### Rested XP (was Rested King)

How much rested XP every character has built up, when each one is full, and where they're resting.

[Full guide](AddOns/King_Maker/Modules/Rested#readme)

## Credits

Thank you to the [Questie](https://github.com/Questie/Questie) team for Questie and
[QuestieDB](https://github.com/Questie/QuestieDB). Their quest, NPC and item database is what lets Mob Farming know
every mob, spawn point and drop in the game. King Maker only reads that data; it
doesn't include or change any of it, so install Questie and QuestieDB from their own pages and support their authors.

**Recipe data from [ForeverDB.net](https://foreverdb.net)** (GPL-3.0): every Forever recipe, its reagents, skill
ranges and where it's learned, used by Crafting Profits, the profession panel and the item tooltips. Thank you to ForeverDB for
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
