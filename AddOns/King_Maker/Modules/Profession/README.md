# Profession window

When you open a profession, King Maker docks a panel next to the game's window. It only reads: it never crafts and never changes the game's window.

## Recipe tab

For the recipe you have selected:

- **The item**: icon, name and quality, and your **skill-up colour and chance** at your current skill. The colour comes from the game's window when it gives one, otherwise from Skillup's data.
- **Reagents**: how many you need, how many you have (this character, plus `+N` on your alts), the price of one and the cost of the line. A reagent's price is the cheaper of the lowest auction and a vendor (`v` means a vendor sells it). Use `-` / `+` to count materials for more than one craft (hold shift to step by 5).
- **What it sells for**: the market price, the lowest auction and how many are listed, the 30-day average and the 7-day trend (Price History), the **profit for each craft after the 5% auction cut**, and the disenchant value.
- **Market's verdict** for both ways of counting: *Bought* (you buy the materials) and *Farmed* (you already have them, so crafting has to beat selling them raw). The verdict is CRAFT, DISENCHANT, SELL RAW, SKIP or NO PRICE. Profit uses the same numbers as Crafting Profits (the lowest auction).
- A small **price chart** of the last 30 points in Price History.
- **Add missing to Shopping** puts the materials you're short of on the Shopping list "Crafting", with today's price as the most to pay. Vendor items are left out, and chat lists them so you can buy them from a vendor. The button only shows when the Shopping module is there.
- **Star**: makes the item a Price History favorite. **History** opens the item in Price History.

## Best now tab

- The **best crafts right now** for this profession, using only recipes you have, ranked the way Crafting Profits ranks them.
- For the ones worth crafting: how many are **Listed**, and how many to **Make** so you don't flood the auction house (a
  quarter of what's listed, at most one day of units leaving it; nothing listed: make 1 to test the market).
- Your **next skill-up steps** from your current skill (Skillup's cheapest plan).

Click a row to show its card. On the modern profession window this also selects the recipe in the game's window.

## Tooltips

When you hover a recipe's item or spell inside the profession window, the tooltip gets two lines: the cost, the profit and the verdict, then the skill-up colour and chance.

## Settings

Go to Settings > Profession window, or type `/km profession`:

- show the panel or hide it
- dock it on the right or on the left
- turn the tooltip lines on or off
- count materials as bought, as farmed, or the same way as Crafting Profits

The `-` button in the panel's corner collapses it to a single line that shows the selected recipe's profit and verdict.
