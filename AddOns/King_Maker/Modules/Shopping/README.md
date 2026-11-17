# Shopping

Lists of what you want to buy, with your own max price, and a panel beside the auction house that searches for
them and buys them. Open it from **Auction House > Shopping** in the King Maker window, the crown's right-click
menu, or `/shop`. When something on your lists is at or under your max, the Shopping button in the sidebar shows a
gold count.

## Lists

- **Favorites** is the same list as the stars in Price History: star an item there and it is here, remove it here
  and the star goes out.
- Make as many other lists as you like (**New list**, **Rename**, **Delete**). `/shop add` and other modules add to
  the list called **Shopping**.
- Add an item by shift-clicking it into the box at the top of the page (or dragging it there), or by typing its
  name or item ID. Set **Want** (how many more to buy) and **Max** (`1g 50s`, `75s`, or `2.5` for 2.5 gold) if you
  like. A blank Max means the market price (or no limit: Settings); once the box names an item, the Max box hints
  at its 7-day average.
- **Buy or Keep.** An item either has a **Want** that counts down as you buy (Buy), or **Keep N in stock**: it
  wants N minus what you own, never counts down, and wants more again as you use them. Switch with **Buy | Keep**
  in the item's editor (or `/shop keep Linen Cloth 40`). What you own is counted on your characters on this realm
  and faction plus the warband bank (Inventory); bought items count as on their way until the mailbox shows them.
- Each list on the left shows how many items it has and, in gold, how many are deals right now. **All lists** at the
  bottom adds up the deals everywhere and what everything would cost at your max.
- **After a scan**, one line in chat when the deals changed: `Scan done: 3 Shopping items under your max (Fel Leather
  8s 82c, ...)`. Up to three are named, best first, as links you can click. A scan that finds the same deals says
  nothing; nothing is said in combat. Turn it off in Settings or with `/shop notify off`.
- **Export** gives a short code (`KMS1:...`) to send to a friend or another character; **Import** reads one.
- **Live lists** (blue) come from another addon: Oracle's own lists, or **Cooldown mats** from Cooldowns. They change
  by themselves and are read-only here (no add, edit, rename or delete), but they show, price and buy like any list.
  Export one to keep a saved copy.
- An old **Oracle** list from the import button King Maker used to have is a normal list now; delete it if you
  don't need it. Oracle's own lists (Oracle Main / Oracle Bank) show here live while Oracle is installed.

## The table

| Column | What it shows |
|---|---|
| Lowest | the lowest buyout from your last scan, or from a search at the auction house this visit |
| Max | your max; grey with `*` when the item has none, so the market price is used |
| Vs max | how far the lowest is under (green) or over your max |
| Want / Own | how many more to buy (goes down as you buy), or **keep 20** for a Keep item / owned on all characters (a Keep item: on this realm and faction) |
| Cost | want x lowest: about what buying them now costs |
| 7d | the price over the last 7 days (Price History); down is green |
| Status | **DEAL** (under your max), **<= MKT** (under the market price, no max of your own), **DONE**, **STOCKED** (a Keep item you have enough of), **NO MAX**, **NO SCAN** |

Deals are tinted green and sorted first, biggest saving first; anything above max is dimmed. Click a column to sort
by it (remembered). Hover a row for the exact prices, the 7-day average and 30-day range, and who owns how many.
Right-click for **Search at the auction house**, **Open in Price History**, remove, or copy to another list.

Below the table: with nothing selected, the list's totals (deals now, what they cost, what filling the list costs at
your max, and how old the prices are). Click an item to edit its max, want and note (Enter saves; **7d avg**
puts Price History's average in the Max box; **Buy | Keep** switches the number between "buy this many" and "keep
this many in stock", and saves), with its numbers and a 30-day price line against your max. Click it
again to go back to the totals. What you type is never wiped by a scan or a purchase while you edit.

## At the auction house

The Shopping panel docks to the right of the auction house (close it with x; the **Shopping** button brings it
back). Pick a list (the menu shows the deals on each); the panel lists it deals first with lowest, max and how many
you still need.

- **Click an item** to look it up: the panel shows what's listed, cheapest first, with a line where your max falls
  and how many are listed under it. **Find** also types the name into the auction house's own search, so you can buy
  in its window as usual. **Search all** looks up the whole list, then picks the best deal for you. Searching never
  buys anything.
- **Commodities** (cloth, ore, herbs...): the quantity starts at what you want (a Keep item: what's missing from
  its stock), but no more than are listed under your max, and **Buy** shows about what it costs. The auction house tells you the real price, **Confirm** shows it,
  and only your click on Confirm buys. **Cancel** backs out. A purchase of a quarter of your gold or more needs a
  second click on Confirm.
- **Other items**: the cheapest auctions are listed, each with its own **Buy** button. One click buys one auction.
  If the auction house doesn't answer in a few seconds (it sold), the panel says so and looks again.
- Anything above the item's max is greyed out and refused. Tick **Allow one buy above my max** for one purchase.
  Anything costing more than the gold you carry is refused before it's asked.
- After a purchase the wanted amount goes down (a Keep item's number stays; what you bought counts toward its stock). When the item is done (or no longer under your max) the panel moves
  to the next deal and looks it up; **Next deal** does the same any time. Buying it is still your click.
- The panel adds up what this visit spent; closing the auction house prints it once in chat.

Buying a whole list is **Search all**, then **Buy**, **Confirm**, **Buy**, **Confirm**... one click per step. King
Maker never buys on its own.

## Commands

| Command | What it does |
|---|---|
| `/shop` | open the Shopping page (also `/shopping`, `/km shopping`) |
| `/shop add [item] [qty] [max]` | add to the Shopping list: `/shop add Linen Cloth 40 12s` |
| `/shop remove [item]` | remove from the Shopping list |
| `/shop keep [item] [n\|off]` | keep n in stock (on the Shopping list); `off` goes back to buying a set number |
| `/shop list [name]` | your lists, or one list's items |
| `/shop deals` | what's under your max right now on any list, best first |
| `/shop panel` | show or hide the panel at the auction house |
| `/shop notify [on\|off]` | the chat line after a scan that finds deals |

## Settings (Settings > Shopping)

| Setting | Default |
|---|---|
| Show the Shopping panel when the auction house opens | on |
| Items without a max price: Max = market, or No limit | Max = market |
| After a purchase, go to the next deal (selects and searches only) | on |
| Ask twice before spending a quarter of your gold | on |
| Play a sound when a purchase goes through | on |
| Say in chat when a scan finds deals | on |

## For other addons

```lua
ShoppingKing.Add(itemID, qty, maxPrice, listName) -> true/false   -- listName nil = "Shopping" (made if needed)
ShoppingKing.Remove(itemID, listName)
ShoppingKing.Lists()          -> { "Favorites", "Shopping", ... }
ShoppingKing.Items(listName)  -> { { itemID =, qty =, max =, note =, keep = }, ... }   -- keep: "Keep n in stock"
ShoppingKing.IsWanted(itemID) -> the list's name, or nil

-- A live list another addon supplies (Oracle and Cooldowns use it). Never saved; it shows and buys like any list but
-- can't be edited, renamed or deleted here; each purchase calls bought(itemID, n). owner and note (optional strings)
-- show on the page: "Live list from <owner>". Nothing changes when no addon registers.
ShoppingKing.RegisterListProvider(name, { items = function() return { { itemID =, qty =, max =, note = } } end,
                                          bought = function(itemID, n) end,
                                          owner = "MyAddon", note = "what this list is" }) -> true/false
ShoppingKing.UnregisterListProvider(name)
ShoppingKing.RefreshLists()   -- the provider's items changed: redraw
```

`qty` is how many are still to buy (it counts down as you buy; for an item with `keep`, it's what's missing from its
stock right now); the names "Favorites", "Shopping" and "Oracle" are taken. Live lists don't take Keep.
