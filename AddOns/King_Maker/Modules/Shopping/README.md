# Shopping

Lists of what you want to buy, with your own max price, and a panel beside the auction house that searches for
them and buys them. Open it from **Auction House > Shopping** in the King Maker window, the crown's right-click
menu, or `/shop`.

## Lists

- **Favorites** is the same list as the stars in Price History: star an item there and it is here, remove it here
  and the star goes out.
- Make as many other lists as you like (**New list**, **Rename**, **Delete list**). `/shop add` and other modules
  add to the list called **Shopping**.
- Add an item by shift-clicking it into the box at the top of the page (or dragging it there), or by typing its
  name or item ID. Set **Want** (how many) and **Max** (`1g 50s`, `75s`, or `2.5` for 2.5 gold) if you like.
- Click an item in the list to change its max, wanted amount or note; right-click to remove it or copy it to
  another list.
- **Export** gives a short code (`KMS1:...`) to send to a friend or another character; **Import** reads one.
- With the Oracle addon loaded, **Import Oracle buy list** makes the list **Oracle** from its buy calls (the
  target price becomes the max).

The table shows the market and lowest price from your last scan (your lists are included in every scan), how many
are listed, your max, how many you want and how many you own on all characters. **under max!** means the lowest
price is at or under your max.

## At the auction house

The Shopping panel docks to the right of the auction house (close it with x; the **Shopping** button brings it
back). Pick a list, then:

- **Search** on an item shows what's listed. **Search all** searches the whole list one item after another and
  highlights what's under your max. Searching never buys anything.
- **Commodities** (cloth, ore, herbs...): set the quantity (it starts at how many you want), click **Buy**. The
  auction house tells you the real price, the panel shows `Confirm: 10 for 1g 20s (each 12s)`, and only your
  click on **Confirm** buys. **Cancel** backs out.
- **Other items**: the cheapest auctions are listed, each with its own **Buy** button. One click buys one auction.
- Anything above the item's max is greyed out and refused. Tick **Buy above my max** to allow one purchase anyway.
- After a purchase the wanted amount goes down by what you bought.

Every purchase is one click of yours per step; King Maker never buys on its own.

## Commands

| Command | What it does |
|---|---|
| `/shop` | open the Shopping page (also `/shopping`, `/km shopping`) |
| `/shop add [item] [qty] [max]` | add to the Shopping list: `/shop add Linen Cloth 40 12s` |
| `/shop remove [item]` | remove from the Shopping list |
| `/shop list [name]` | your lists, or one list's items |
| `/shop panel` | show or hide the panel at the auction house |

## Settings (Settings > Shopping)

| Setting | Default |
|---|---|
| Show the Shopping panel when the auction house opens | on |
| Items without a max price: Max = market, or No limit | Max = market |
| Play a sound when a purchase goes through | on |

## For other addons

```lua
ShoppingKing.Add(itemID, qty, maxPrice, listName) -> true/false   -- listName nil = "Shopping" (made if needed)
ShoppingKing.Remove(itemID, listName)
ShoppingKing.Lists()          -> { "Favorites", "Shopping", ... }
ShoppingKing.Items(listName)  -> { { itemID =, qty =, max =, note = }, ... }
ShoppingKing.IsWanted(itemID) -> the list's name, or nil
```
