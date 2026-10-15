# Farm King

Which mobs are worth farming, for the King suite on WoW Forever. Farm King
ranks mobs by the **average gold a kill is worth**: the coin they drop plus
each drop's chance times what it sells for, priced by
**[Scanner King](https://github.com/base-reality-ai/Scanner_King)**.

- **Scanner King** (required) prices the drops.
- **[QuestieDB](https://github.com/Questie/QuestieDB/releases)** (optional)
  adds every mob in the game, with levels, zones, spawn points and what they
  can drop. Without it, Farm King lists the mobs you've seen yourself.

## Install

1. Download this repo (Code, then Download ZIP) and unzip it.
2. The folder must be named `Farm_King` (rename `Farm_King-main`).
3. Put it in `_classic_beta_\Interface\AddOns\` next to `Scanner_King`.
4. Optional: from the QuestieDB releases page, download **QuestieDB-Forever.zip**
   from the latest release (not "Source code") and extract it into
   `Interface\AddOns\`, so you get `Interface\AddOns\QuestieDB\QuestieDB_Forever.toc`.

## Where the numbers come from

Nobody publishes drop rates for Forever (Blizzard keeps loot tables on the
server), so Farm King records them as you play:

- **Mobs you see**: target, mouse over or see a nameplate, and Farm King notes
  its name, level, elite or rare, type, and where you were.
- **Kills**: every item and coin in a loot window is credited to the exact
  corpse it came from, so looting several corpses at once still adds up right.
  A corpse counts once (remembered for an hour, through `/reload`); opening it
  again changes nothing. Skinning, herb gathering, mining, fishing and
  pickpocketing are ignored, even on corpses someone else killed.
- **Kills with no loot** count too when you're solo, so a mob that often drops
  nothing isn't made to look better than it is. Mobs someone else tagged
  don't count. If a corpse counted as empty turns out to have loot, the loot
  is added without counting the kill twice.
  Forever closes the combat log to addons, so Farm King spots a kill by
  seeing a mob you were fighting die as your target or on its nameplate.
  With enemy nameplates off, an empty corpse you never target is missed.
- **In a group** only corpses you open count, so a mob can look a little
  better than it is (empty corpses and what groupmates already took are
  missed), and two guildmates opening the same corpse both record it. Solo
  farming gives the truest numbers.
- **Your guild**: see below.

Drop chances are averages over many kills. The more kills behind a mob, the
better its numbers: under **Min kills** they show in grey.

## Prices

| Drop | Worth |
|---|---|
| Grey (junk) | Its vendor price |
| Bind on pickup | Its vendor price (it can't go on the auction house) |
| Anything else | The better of the auction house (Scanner King's market price, after the 5% cut) and a vendor |
| Quest items | Nothing |

## The window

Open it with the wolf pelt button on your minimap or `/fk` (right-click the
button for mobs in your zone).

**Top.** Tick what to price in: Grey, White, Green, Blue, Epic drops and Coin.
**Guild data** adds your guildmates' kills to yours. **Near my level** shows
mobs from 5 levels under you to 3 over. **Min kills** is how many kills a mob
needs before it's ranked under Best farms (click to cycle 1, 5, 10, 25, 50).

**Mob Farming tab.** Everything below is the first tab.

**Left side.** Best farms, Favorites, Recent kills (the last 25 mobs you
killed, the latest first), Tracked on map, This zone, All mobs, then
every zone. Scroll it with the mouse wheel.

**The list.** Mob, level, zone, **gold per kill**, coin per kill, best drop and
kills. Click a column to sort by it. Click the star (or right-click) to make a
mob a favorite.

**Hunting an item.** Click **Mobs** next to the search box to switch it to
**Items**, then type part of an item's name (or shift-click an item link into
the box). Pick an item and the list shows every mob known to drop it: from
your kills, your guild's and QuestieDB's drop lists. Highest level first, with
level range, zone, spawn points, drop chance and the kills behind it, and gold
per kill. The bottom line sums it up: how many mobs, their levels and spawn
points. Econ King's **Hunt in Farm King** button opens this list for the item
you're looking at.

**A mob's page.** Click any mob:
- Gold per kill, coin per kill and kills recorded (yours and your guild's).
- Its loot table: each drop's chance, how many come at once, its price, what it
  adds per kill, and whether that price is the auction house or a vendor.
  Drops left out by your filters are dimmed. Drops QuestieDB lists that nobody
  has seen yet are at the bottom as "not seen".
- **Track on map** puts its spawn points on your world map as small gold dots (QuestieDB's spawn
  points, or the spots you've seen it). Hover a pin for its name and value.
- **< Back** returns to the list; the arrows step through it.

## White Items

The **White Items** tab at the top (next to **Mob Farming**) helps you find
white items worth hunting. It lists every white item that Scanner King has an
auction price for and that some mob is known to drop, with:

- **Price**: what one sells for at the auction house, after the 5% cut,
- **Listed**: how many are up for sale (lots listed means competition),
- **Mobs** and **Spawns**: how many mobs drop it and their spawn points
  together (QuestieDB's, or the spots you've seen them),
- **Best chance**: the best drop chance from your and your guild's kills,
- **Score**: price times the square root of spawn points, with the best item
  at 100. Plenty of mobs to farm counts, but a cheap drop can't win on numbers
  alone.

Click a column to sort by it. Click an item for every mob that drops it
(highest level first), and a mob for its page. A Deep Scan in Scanner King
prices every item, so run one first.

## Mini tracker

Click **Mini tracker** at the top of the window (or `/fk mini`) for a small
movable box that tallies what you're farming:

- every mob you've killed, how many, and what their kills brought in,
- every drop, how many, and what they're worth, plus the coin you looted,
- the total.

**Start timer** adds gold per hour for what you farm while it runs; without it
you just see totals. Pause and resume it as you like (a `/reload` pauses it and
keeps its time). **Reset** clears the box, `-` folds it to its title bar (which
still shows your total or gold per hour), `x` closes it.

## Your guild

Drop data is shared on request, so it costs nothing until someone asks:

- **Ask guild** (bottom right of every list, and on every mob page) asks
  guildmates running Farm King for their data on those mobs.
- Everyone who has killed them answers with their own totals. Each
  guildmate's latest answer replaces their last one, so asking again never
  counts the same kills twice. Only your own kills are ever sent, and only
  guild chat is listened to.
- With **Guild data** ticked their kills add to yours; untick it to see only
  your own. `/fk share off` stops you answering, `/fk forget guild` drops
  everything guildmates sent.

| Command | What it does |
|---|---|
| `/fk` | Open or close the window |
| `/fk status` | What's been recorded, and whether QuestieDB was found |
| `/fk share on` / `off` | Answer guildmates' requests for your drop data |
| `/fk forget guild` | Drop every guildmate's data |
| `/fk mini on` / `off` | The mini tracker |
| `/fk button on` / `off` | The minimap button |

## For addon authors

```lua
FarmKing.ShowItem(itemID)     -- open Farm King on every mob that drops the item
FarmKing.GoldPerKill(npcID)   -- gold per kill with the current filters, and the kills behind it
FarmKing.IsDrop(itemID)       -- true when mobs drop it (your loot, your guild's, or QuestieDB); Mail King uses it
```

## Tests

`python3 tests/run.py . ../Scanner_King` runs Farm King and Scanner King
against a stand-in for the game and a stand-in QuestieDB (needs `pip install lupa`).

## Credits

Mob, spawn and drop-list data comes from QuestieDB at runtime (it's read from
your installed copy, not copied into this addon).
