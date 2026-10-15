# Market King

The trading addon of the King suite on WoW Forever. Pick the professions you
care about and Market King tells you, for every item they can make, whether
you're better off:

- **selling the raw materials**,
- **crafting the item and selling it**, or
- **crafting it, disenchanting it and selling the enchanting materials**.

Needs **[Scanner King](https://github.com/base-reality-ai/Scanner_King)**, which
does the auction house scanning. See its
[API.md](https://github.com/base-reality-ai/Scanner_King/blob/main/API.md) for
how the addons connect.

## Install

1. Download this repo (Code, then Download ZIP) and unzip it, or
   `gh repo clone base-reality-ai/Market_King` in your AddOns folder.
2. The folder must be named `Market_King` (rename `Market_King-main`).
3. Put it in `_classic_beta_\Interface\AddOns\` next to `Scanner_King`.

## Use

1. At the auction house, click **Market Scan** in the title bar (the button
   comes from Scanner King, next to Material Scan). A small window opens with
   every profession ticked: Alchemy, Blacksmithing, Cooking, Enchanting,
   Engineering, First Aid, Leatherworking, Smelting, Tailoring. Untick what you
   don't want (**None** clears them all).
2. Click **Scan**. Scanner King prices Trade Goods, then every item those
   professions make and use, and every disenchanting material.
3. When it's done, Market King opens on the professions you scanned. Open it
   any time with the bag button on your minimap or `/mk`.
4. The ticks at the top of Market King only filter what you see. **Best** has
   every ticked profession together; the other tabs have one profession each.
   Everything is sorted most profitable first.

Each row shows:

| Column | Yrgna Special (buying mats) | Ethical Gaming (farming mats) |
|---|---|---|
| Mat cost / Raw value | What the materials cost to buy | What your materials would sell for |
| Craft sells | What the crafted item(s) sell for, after the 5% auction cut | same |
| DE sells | Average disenchant value of the item(s), after the cut | same |
| Listed | How many of the crafted item are on the auction house right now | same |
| Best | Craft, Disenchant, or Skip | Craft, Disenchant, or Sell raw |
| Profit / Gain vs raw | The better sale minus the material cost | The better sale minus vendor reagents, minus what the raw materials would sell for |

**Include disenchanting** (on by default) decides whether disenchanting counts
as an option. **DE only** shows just the items that can be disenchanted, ranked
by what crafting and disenchanting them makes, for when you're only hunting
disenchant profits.

**Recipes** (top right) chooses which recipes you see:

- **All recipes**: everything, with patterns you don't have greyed out.
- **My recipes**: trainer recipes plus the patterns you have.
- **Patterns I lack**: only patterns you don't have, to see which are worth
  getting.

Trainer recipes always count as yours. A pattern recipe (one taught by a
pattern, plans, schematic, formula, manual or recipe item) counts once you open
that profession's trade skill window and Market King sees you know it. Right-click
any row to mark it as had or not had yourself, for example a pattern sitting in
your bank. Marks are kept per character; `/mk recipes reset` clears them.

**Listed** shows supply, not sales: lots listed means competition, very few
can mean nobody makes it, or nobody buys it. Check the item's listings before
crafting a stack.

The **red line** marks where crafting stops paying. Everything below it is
better left as raw materials.

**Yrgna Special** (buying mats) treats materials as something you buy, which is how you find
flips. **Ethical Gaming** (farming mats) treats them as already yours, so it compares crafting
with just selling what you gathered. Vendor reagents (thread, flux, vials) are
a cost either way.

Hover a row for the full breakdown: each material and its price, what the item
sells for, and what it disenchants into on average.

## Where the numbers come from

- **Recipes:** every Classic recipe that makes an item (1,139 of them). When you
  open your own trade skill window, Market King also picks up any recipe it
  doesn't know, so anything new in Forever gets added.
- **Patterns:** which of those recipes need a pattern (728 of them) and which
  pattern items teach them, also from AtlasLootClassic.
- **Disenchanting:** the Classic disenchant tables by quality and item level.
  The value is an average over many disenchants, not a guarantee for one.
- **Vendor reagents:** what you last paid at a vendor (noted whenever you open
  one), or an estimate until you've visited one.
- **Prices:** Scanner King's latest scan. Items not on the auction house show
  "-", and a recipe with an unpriced material shows "missing" until it's priced.

| Command | What it does |
|---|---|
| `/mk` | Open or close the window |
| `/mk scan` | Open Market Scan (auction house open) |
| `/mk mode buy` / `farm` | Count materials as bought or farmed |
| `/mk recipes all` / `mine` / `missing` | Which recipes to show |
| `/mk recipes reset` | Clear your have/don't-have marks |
| `/mk button on` / `off` | Show or hide the minimap button |

## Credits

The recipe list in `Data/Recipes.lua` and the pattern list in `Data/Patterns.lua` were generated from AtlasLootClassic's
profession data (GPL-2.0, https://github.com/Hoizame/AtlasLootClassic). If this
addon is ever shared publicly it should be released under the GPL as well.
