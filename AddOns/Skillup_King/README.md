# Skillup King

The cheapest way to level a profession on WoW Forever. Part of the King suite, next to Scanner King,
Market King, Gather King, Farm King, Mail King and Quest King.

It knows every Classic recipe and the skill levels where each one turns orange, yellow, green and
grey. It prices the materials and what you make with Scanner King's auction house scans. From your
skill (and your level), it works out what to craft at every point to the top, for the least gold. A
plan can even make money when what you craft sells or disenchants for more than its materials.

Needs **[Scanner King](https://github.com/base-reality-ai/Scanner_King)** for prices.

## Install

1. Unzip it into `_classic_beta_\Interface\AddOns\`. The folder must be named `Skillup_King`.
2. Open it with `/suk` (or `/skillup`, or the minimap button). `/suk tailoring` opens straight on a
   profession.

## Use

1. **Get prices.** At the auction house, click **Scan prices** in Skillup King. It scans everything the
   profession uses and makes, its patterns, and the disenchanting materials. A Deep Scan in Scanner
   King covers everything too.
2. **Pick a profession.** Your skill and level show next to it. Open the profession's window once
   (press its spellbook button) so Skillup King learns which pattern recipes you know.
3. **Read the plan.** For each stretch of skill it shows:

   | Column | |
   |---|---|
   | Make | The recipe to craft |
   | Crafts | How many, on average (yellow and green don't always give a point) |
   | Each | One craft: materials minus what you get back. Below zero, it makes money |
   | Get back by | Selling it on the auction house, disenchanting it, or a vendor: whichever pays most |
   | Per point / Total | What the skill points cost |
   | Recipe | Trainer, Known, or the pattern you'd need and its price |

   Trainer visits (Journeyman at 75, Expert at 150, Artisan at 225) get their own lines, in red when
   you're not high enough level yet. **Shopping list** shows every material the plan needs; click it
   to print the list in chat.
4. **At my skill** lists every recipe you can make right now, cheapest skill point first, with its
   color and its chance of a point.

Change **From** and **To** to plan any stretch, like your next 25 points or the way to 300.

### What counts

- **Disenchant:** count disenchanting what you make and selling the materials. Turn it off if no one
  can disenchant for you.
- **Sell on AH:** count selling what you make. Turn it off when the market is flooded; only a vendor
  (and disenchanting) is counted then.
- **Patterns I lack:** also use recipes from patterns you don't have yet. Their price shows so you can
  see if buying one pays off.

## The math

- Orange gives a point every time. Yellow and green give one with a chance of
  (grey − skill) / (grey − yellow), which falls as you near grey. Grey gives nothing.
- Materials cost the cheaper of the auction house and a vendor.
- Cost per point = (materials − what you get back) / chance.
- At every skill, the plan makes whatever is cheapest per point. Points don't depend on each other,
  so that's the cheapest plan on average.
- Missing prices are never counted as free. Points with nothing priced show as a gap: scan, or allow
  patterns you lack.

## Commands

| Command | |
|---|---|
| `/suk` | Open Skillup King |
| `/suk <profession>` | Open it on a profession (`/suk first aid`, `/suk smelting`) |
| `/suk button on` / `off` | The minimap button |

## For addon authors

```lua
SkillupKing.Plan(professionID, fromSkill, toSkill)
-- returns steps { { from, to, r = recipe, crafts, cost } or { note } ... }, total cost in copper
```

## Data

Recipes, skill colors and patterns come from AtlasLootClassic's profession data (GPL-2.0,
github.com/Hoizame/AtlasLootClassic). Disenchanting tables are shared with Market King. Recipes added
only on Forever aren't included yet.

## Tests

```
pip install lupa
python3 tests/run.py .
```
