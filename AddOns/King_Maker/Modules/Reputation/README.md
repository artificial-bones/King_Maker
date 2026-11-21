# Reputation (new in King Maker 2.10)

A new **Reputation** section in the King Maker sidebar, for the factions that pay you back in recipes, Favor and
gold. The first one is your side's supply faction: the **Azeroth Commerce Authority** (Alliance, Three Corners in
Redridge) or **Durotar Supply and Logistics** (Horde, west of the Crossroads), and its **Supply Writs**.

## Where things are

| What | Where |
|---|---|
| Every tracked faction | **Reputation > Reputation** (`/rep overview`) |
| Supply Writs | **Reputation > Supply Writs** (`/rep`, `/reputation` or `/km writs`) |
| Orders to turn in | A **red count** by Supply Writs: orders in your bags or bank you haven't turned in today |
| From the minimap | Right-click the crown: **Supply Writs** |
| Home | "Writ orders to turn in" under **Needs your attention**; writs done today by each character |
| Settings | King Maker **Settings > Reputation** |

## How writs work

Sealed writs drop from mobs and chests and sell on the auction house (Journeyman, Expert, Artisan). Using one gives a
random order of that tier, "Craftsman's Writ: X". Using the order starts its quest: take the crafted item to a
customer somewhere in the world. You don't need the profession: buy the item if you can't make it.

**Every named order is its own daily quest.** Turn in as many different ones as you like each day, each one once.
Duplicates wait in your bags; they don't expire.

| Tier | Rep | Coin pouch | Orders |
|---|---|---|---|
| Journeyman | 75 | about 22-45s | 45 |
| Expert | 125 | about 50-90s | 60 |
| Artisan | 200 | about 75s | 45 |

All 150 once is 19,875 rep. Orders never give Merchant's Favor; filled crates and the Shipping Label do.

## The Supply Writs page

| Part | What it shows |
|---|---|
| **Done today** | Orders this character turned in since the daily reset |
| **To turn in** | Orders you hold and can still turn in today (the red count) |
| **Rep today** | Rep with the supply faction since the reset (receipts included) |
| **Reset in** | Time to the daily reset: 10 a.m. Eastern (US daylight saving included) |
| **Standing** | Your standing, rep to the next one, and the days to get there at your 7-day pace |
| **Progress strip** | The bar, your rep a day, Merchant's Favor and what the next standing unlocks (hover it for the whole list) |

Five tabs below:

| Tab | What's in it |
|---|---|
| **Your orders** | Every order you hold: what to deliver, what it costs (buy it, or craft it with bought materials: whichever is cheaper), the rep, **rep per gold** after the coin pouch, and the customer and zone. Click one for a waypoint (TomTom if you have it, else the game's map pin) |
| **Cheapest rep** | Sealed writs on the auction house ranked by gold per rep point: (writ + the tier's average item - the pouch) / rep. The receipt path is on the list too |
| **Favor shop** | The faction's recipes for Merchant's Favor, with Crafting Profits' profit per craft and per Favor point, so your Favor goes where it pays most. Tick **My professions** to hide the rest |
| **All orders** | All 150, filtered by tier, profession, held or not done today |
| **Characters** | Every character: standing, writs done today, rep today, orders it holds, Merchant's Favor |

**The receipt path**: a Forged Delivery Receipt (15 Favor, at Friendly) and an empty Waylaid Crate make a Notarized
Shipping Container: 50 rep and 1s, with no daily limit. The Cheapest rep tab compares its gold per rep with writs.

## What each standing unlocks

| Standing (rep from Neutral) | Unlocks |
|---|---|
| Neutral | Recipes for 30-45 Favor |
| Friendly (3,000) | Recipes for 60-120 Favor, the Scribe, Forged Delivery Receipt (15 Favor) |
| Honored (9,000) | Recipes for 180-360 Favor, Forger's Quill (15 Favor: rerolls a writ in its tier), Advertising License Application (1,200) |
| Revered (21,000) | Packmule Treat (1,500) |
| Exalted (42,000) | Tabard (200), Reins of the Pack Kodo (6,000) |

Certifications cost 1,000 Favor at 300 skill. The standing each recipe needs is worked out from its Favor cost.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Red count on the sidebar | on | The number by Supply Writs |
| At login, say which orders you can turn in | on | One chat line when you log in holding orders not turned in today |
| Diplomat perk | none | Your rank of the Legacy perk (+2% rep a rank), so expected rep and gold per rep match |
| Forget characters not seen in 90 days | | Clears their writ and standing data |

## Commands

| Command | What it does |
|---|---|
| `/rep` | Open Supply Writs |
| `/rep overview` | Every tracked faction |
| `/rep status` | Standing, writs done today and the orders you hold, in chat |
| `/rep remind on\|off` | The login reminder |
| `/rep badge on\|off` | The sidebar count |
| `/rep forget First Last` | Forget a character |
| `/rep debug` | What the game reports (for bug reports) |

## Good to know

- **Writs are per character.** Log in on each one once and it shows on the Characters tab; what an alt did today is
  from the last time you were on it.
- **Done today** comes from the game's quest flag and from the turn-in itself (the flag can lag a few seconds).
- **51 Expert and Artisan orders have no known customer yet.** When you turn one in, King Maker writes the customer
  and the spot down, and shows it from then on.
- **Costs need prices**: scan at the auction house (a Market Scan prices crafting materials). With Crafting Profits
  off, only buying counts.

## Credits

Order, customer and reputation data from [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0); recipe Favor
costs and professions from [ForeverDB.net](https://foreverdb.net) (GPL-3.0); order counts and some customers from
[Craftman's Helper](https://github.com/emsw0rth/craftmanshelper) by Emsworth (GPL-3.0, data only). Thank you all.
