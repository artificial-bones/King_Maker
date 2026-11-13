# Rested XP (was Rested King)

Every character's rested XP on one page, so you know who to play before their rest goes to waste.

Since King Maker 2.0 it has no window or minimap button of its own: it's the **Characters > Rested XP**
page of the King Maker window. Your Rested King 1.x characters and perk ranks move in by themselves.

## Where things are

| What | Where |
|---|---|
| The character list | King Maker window, **Characters > Rested XP** (`/rk` or `/km rested`) |
| Open it from the minimap | Right-click the King Maker crown: **Rested XP**. Its tooltip lists your three most rested characters |
| Most rested alt | A tile on the King Maker **Home** page |
| Show max level, this character's Well Rested rank | King Maker **Settings > Rested** |

## How it works

1. **Log in on each character once.** King Maker notes its level, XP, rested XP, where you are,
   and whether you're resting (in an inn or a city).
2. **Every login and every XP change updates it** with the real numbers from the game.
3. **While a character is logged out**, it works out the rest from the time since you logged out,
   using the game's rules (these are the same in WoW Forever as in Classic):

| Rule | Value |
|---|---|
| Logged out in an inn or a city | 5% of the current level every 8 hours |
| Logged out anywhere else | a quarter of that: 5% every 32 hours |
| Most rest you can hold | 150% of the current level (30 bubbles) |
| Time to fill from empty in an inn | 10 days |
| Well Rested legacy perk | +4% rate and cap per rank (rank 5: 1.8 levels) |

Rest is counted in XP for the level the character logged out at, so the estimate is exact until you
play it again. Rested XP doubles the XP you get from kills until it runs out.

## The page

Four tiles across the top: characters levelling, your most rested alt, how many are full of rest,
and who fills up next. Under them, one line per character:

| Column | What it shows |
|---|---|
| Character | Name in class colours, and realm |
| Level | Level and how far into it |
| Rested | Rested XP now, its share of a level, and bubbles. "est" means worked out since you logged out |
| Full | When rest stops growing (yellow under a day), or **FULL** in red with how long it's been full |
| Where | Inn/city (full rate) or Outside (quarter rate) |
| Last seen | When you last played it |

- Click a column header to sort by it, click again to flip it (most rested first by default).
- Hover a character for the details: rest out of the cap, XP left in the level, where it logged out.
- Right-click a character to set its **Well Rested** perk rank, or to forget it.
- Max-level characters are hidden; **Show max level** brings them back.
- A character saved by 2.1 or older can show *log in once to read*: log in on it once and its rest shows up.
- The numbers keep moving while the page is open.

## Commands

| Command | Does |
|---|---|
| `/rk` | Open or close the Rested XP page |
| `/rk perk 0-5` | Your Well Rested legacy perk rank on this character |
| `/rk forget Name` | Stop tracking a character |

`/rk button` now points you to the King Maker crown (`/km button`).

## For addon authors

```lua
RestedKing.Get([ "Name-Realm" ])   -- a character's rest now (default: the one you're on):
                                   -- { rested, cap, pct, bubbles, full, fullIn | fullSince, toLevel, estimated } or { max = true }
```

## Tests

`python tests/run.py rested` from `AddOns/King_Maker` runs the module against a stand-in for the game
(needs `pip install lupa`).
