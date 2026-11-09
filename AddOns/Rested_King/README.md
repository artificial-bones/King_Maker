# Rested King

Every character's rested XP in one window, so you know who to play before their rest goes to waste.

Click the sleeping-moon button on the minimap (or type `/rk`) and you get one line per character:
how much rest it has right now, when it'll be full, and whether it's already full and wasting rest.

## How it works

1. **Log in on each character once.** Rested King notes its level, XP, rested XP, where you are,
   and whether you're resting (in an inn or a city).
2. **Every login and every XP change updates it** with the real numbers from the game.
3. **While a character is logged out**, Rested King works out its rest from the time since you
   logged out, using the game's rules (these are the same in WoW Forever as in Classic):

| Rule | Value |
|---|---|
| Logged out in an inn or a city | 5% of the current level every 8 hours |
| Logged out anywhere else | a quarter of that: 5% every 32 hours |
| Most rest you can hold | 150% of the current level (30 bubbles) |
| Time to fill from empty in an inn | 10 days |
| Well Rested legacy perk | +4% rate and cap per rank (rank 5: 1.8 levels) |

Rest is counted in XP for the level the character logged out at, so the estimate is exact until you
play it again. Rested XP doubles the XP you get from kills until it runs out.

## The window

| Column | What it shows |
|---|---|
| Character | Name in class colours, and realm |
| Level | Level and how far into it |
| Rested | Rested XP now, its share of a level, and bubbles. "est" means worked out since you logged out |
| Full | When rest stops growing (yellow under a day), or **FULL** in red with how long it's been full |
| Where | Inn/city (full rate) or Outside (quarter rate) |
| Last seen | When you last played it |

- Click a column header to sort by it (most rested first by default).
- Hover a character for the details: rest out of the cap, XP left in the level, where it logged out.
- Right-click a character to set its **Well Rested** perk rank, or to forget it.
- Max-level characters are hidden; **Show max level** brings them back.
- The minimap button's tooltip lists your most rested characters.

## Commands

| Command | Does |
|---|---|
| `/rk` | Open or close the window |
| `/rk perk 0-5` | Your Well Rested legacy perk rank on this character |
| `/rk forget Name` | Stop tracking a character |
| `/rk button [on\|off]` | Show or hide the minimap button |

## Install

**With git** (updates are a `git pull`). The repo is private, so the computer needs to be signed in
to GitHub (`gh auth login`, or an SSH key on your account):

```
cd "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
git clone https://github.com/artificial-bones/Rested_King.git
```

The folder must be called `Rested_King` (the clone does that). To update: `git pull` in that folder,
then `/reload` in game. Use whichever client folder holds your Forever install.

**By hand:** copy the `Rested_King` folder into `Interface\AddOns\`, then `/reload`.

It's also part of **King Maker**, the download with every King addon.

## Tests

`python3 tests/run.py .` runs the addon against a stand-in for the game (needs `pip install lupa`).
