# The King Addons

A suite of addons for **World of Warcraft: Forever**: price scanning, price history, trading, farming, gathering,
gold tracking, dungeon quests and profession leveling, all sharing one set of auction house prices.

**[Download the latest release](../../releases/latest)** (`King_Addons.zip`).

## Install

1. Download `King_Addons.zip` from the [latest release](../../releases/latest).
2. Unzip it. You get a folder for each addon (`Scanner_King`, `Market_King`, and so on).
3. Copy all of those folders into your AddOns folder. On the Forever client it is
   `World of Warcraft\_classic_beta_\Interface\AddOns\`
   (if the client folder is named differently, use the one that holds your Forever client).
4. Restart the game, or type `/reload` if you're already in. Check the AddOns list on the character
   screen that they're all turned on.

To update, download the new release and copy the folders over the old ones (say yes to replace).
Your settings and data are kept: they live in `WTF`, not in the addon folders.

You don't have to install everything. Scanner King is the one the others lean on, so keep it; the
rest are pick and choose. Optional extras from other authors make some of them better:
[Questie](https://github.com/Questie/Questie) (QuestieDB) for Farm King and Quest King, and
[TomTom](https://www.curseforge.com/wow/addons/tomtom) for Quest King's waypoint arrow.

## The addons

### Minimap King: one minimap button for all of them
![Minimap King](screenshots/Minimap_King.png)

Puts every addon's minimap button into one crown with a drop-down, King addons first and the rest under their own heading.
Each button still works exactly as before; shift-right-click one in the menu to leave it on the
minimap. `/mmk` · `/mmk icon` picks a different crown · `/mmk release` puts every button back.

### Scanner King: auction house prices (needed by the others)
![Scanner King](screenshots/Scanner_King.png)

Scans the auction house (trade goods, your professions, or everything with Deep Scan), keeps the
prices, and shows them in item tooltips. Shares prices with your guild.
`/sk`

### Market King: the most profitable crafts
![Market King](screenshots/Market_King.png)

For every item your professions make: sell the materials raw, craft and sell, or craft and
disenchant. Ranked by profit at today's prices. Needs Scanner King.
`/mk`

### Econ King: long-term price history
![Econ King](screenshots/Econ_King.png)

Keeps the price and supply history of every item on the auction house, with graphs, favorites and
deals. Needs Scanner King.
`/ek`

### Farm King: which mobs are worth farming
![Farm King](screenshots/Farm_King.png)

Gold per kill for every mob, from the coin and drops you, your guild and QuestieDB have seen, priced
by Scanner King. Tracks your farming sessions in gold per hour. Needs Scanner King.
`/fk`

### Gather King: mark gathering spots
![Gather King](screenshots/Gather_King.png)

Marks mining, herb and fishing spots on your world map and minimap, and tracks what you gather and
what it's worth. `/gt mine thorium` at a node marks it.
`/gt`

### Mail King: your auction house ledger
![Mail King](screenshots/Mail_King.png)

Reads your auction house mail into a ledger: what you sold, bought and lost to deposits, with profit
by item, day and strategy, and your stock across every character.
`/mlk`

### Quest King: dungeon quests
![Quest King](screenshots/Quest_King.png)

Every Horde dungeon quest from 13 to 60, with each chain laid out step by step: what you've done,
what's next, the levels that matter, and a map pin to every quest giver. Also marks quest items in
your bags that are safe to delete.
`/qk`

### Skillup King: level professions for the least gold
![Skillup King](screenshots/Skillup_King.png)

Works out what to craft at every skill point to max out a profession for the least gold, using
today's prices and what you can sell or disenchant along the way, plus the shopping list.
Needs Scanner King.
`/suk`

## For maintainers

Each addon lives in `AddOns/<folder>`. To publish a release, run the **Release** workflow from the
Actions tab (or push a tag like `v1.0.0`): it zips the `AddOns` folders into `King_Addons.zip` and
attaches it to a new release. `./build.sh` makes the same zip locally.
