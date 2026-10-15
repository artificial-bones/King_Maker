# How the King addons connect

Each addon is its own folder in `Interface\AddOns`, with its own repo and its
own saved data. They connect in two ways.

## 1. Load order through the .toc

The game loads an addon after the addons it lists as dependencies.

- `gather_king.toc` has `## OptionalDeps: Scanner_King`. Gather King loads
  after Scanner King when it's installed, and still works without it (markers,
  sync and the ledger all work; prices fall back to Auctionator or show "no price").
- `Market_King.toc` has `## Dependencies: Scanner_King`. Market King is all
  about prices, so the game won't load it without Scanner King.
- `Econ_King.toc` has `## Dependencies: Scanner_King` too. Econ King keeps the
  long-term history of what Scanner King scans.

## 2. The ScannerKing global

Scanner King creates one global table, `ScannerKing`. The other addons only
ever use these functions, never its saved data directly, so either side can
change internally without breaking the other.

```lua
if ScannerKing and ScannerKing.API_VERSION then ... end   -- is it installed?

ScannerKing.GetPrice(itemID)      -- copper each, scan time (server time), quantity listed; nil if unknown
ScannerKing.GetMarketPrice(itemID) -- market price from a Deep Scan (or the lowest price), time, quantity,
                                   -- and true when it's a real market price
ScannerKing.GetAllPrices()        -- { [itemID] = { p = copper, t = time, q = quantity, from = guildmate,
                                  --                m = market price, n = auctions } } (read only)
ScannerKing.LastScan()            -- server time of the last scan that covered Trade Goods
ScannerKing.LastDeepScan()        -- server time of the last Deep Scan
ScannerKing.DeepScan()            -- every item on the auction house (auction house must be open)
ScannerKing.OpenDeepScan(start)   -- the Deep Scan window; start = true also starts the scan
ScannerKing.Scan()                -- Trade Goods + watched items (auction house must be open)
ScannerKing.Scan({ items = ids }) -- the same, plus these items (searched 100 at a time)
ScannerKing.IsScanning()

-- Ask for items outside Trade Goods to be included in every scan.
-- Pass a list, or a function that returns the list when a scan starts.
ScannerKing.Watch("gather_king", function() return { 268415, 268416 } end)

-- Hear about scans and new prices. fn(event, ...) gets:
--   "SCAN_STARTED", "SCAN_PROGRESS" (text), "SCAN_FINISHED" (found), "PRICES_UPDATED"
--   "SCAN_RESULTS" (results, kind, method) just before SCAN_FINISHED, with what this scan saw:
--       kind = "material", "market" or "deep"
--       results = { [itemID] = { p = lowest copper each, q = quantity listed,
--                                m = market price, n = auctions, s = sellers,      (Deep Scan)
--                                l = { { copper each, count }, ... } } }        (Deep Scan, full list only)
--   "GUILD_PRICES" (batch) when guildmates' newer prices arrived:
--       batch = { [itemID] = { p = lowest, m = market or nil, q = listed or nil, t = their scan time, from = name } }
--       method (Deep Scan) = "replicate" (every auction, all fields), "browse" (p and q only)
--                            or "partial" (browse that stopped answering: some items are missing)
ScannerKing.RegisterCallback("gather_king", fn)
ScannerKing.UnregisterCallback("gather_king")

-- Offer a Market Scan (Market King does this). Scanner King shows the Market Scan
-- button and picker, runs the scan, and calls finished when it's done.
ScannerKing.RegisterScanProvider("Market_King", {
    options  = { { key = 4, label = "Alchemy" }, ... },  -- ticked by default
    items    = function(picked) return { itemID, ... } end, -- picked = { [key] = true }
    finished = function(picked, found) end,
})
ScannerKing.OpenMarketScan()      -- open the picker (auction house open)

-- Add lines to item tooltips, under Scanner King's prices.
ScannerKing.AddTooltipProvider("Econ_King", function(tooltip, itemID) tooltip:AddLine(...) end)

-- Ask guildmates for their latest prices of these items (Econ King's "Ask guild").
-- Returns items asked for and messages used, or nil if sharing is off / no guild.
-- Items you scanned yourself in the last hour are skipped; at most 2000 per call.
ScannerKing.RequestPrices({ itemID, ... })

ScannerKing.MergePrice(itemID, copper, time, from)  -- keep a price if it's newer than ours
ScannerKing.FormatMoney(copper)   -- "1g 23s 45c" with colors
ScannerKing.PriceAge(time)        -- "5 min ago", "3 h ago", ...
ScannerKing.Now()                 -- server time, the same clock for every guildmate
```

`API_VERSION` goes up only if one of these changes in a way that breaks callers.

## Who does what

- **Scanner King** owns every auction house scan and both scan buttons.
- **Gather King** and **Market King** only read prices and tell Scanner King what
  they need: Gather King through `Watch`, Market King through `RegisterScanProvider`.
- **Econ King** listens for `SCAN_RESULTS` and keeps every scan as history.

## Saved data

| Addon | Saved variable | Holds |
|---|---|---|
| gather_king | `GatherKingDB` | markers, profiles, loot stats, ledger |
| Scanner_King | `ScannerKingDB` | prices, last scan time, sync setting |
| Market_King | `MarketKingDB` | its own settings and history |
| Econ_King | `EconKingDB` | price and supply history, favorites |

Gather King 1.x kept its own prices. Version 2.0 moves them into Scanner King
the first time both are installed.

## Guild messages

Each addon uses its own addon-message prefix, so they never read each other's
traffic: `GatherKing1` (markers and loot stats) and `ScannerKing1` (prices).

`ScannerKing1` messages are at most 250 characters:

| Starts with | Means |
|---|---|
| `H` | Hello: guildmates online whisper back their shared prices |
| `Z` | Packed prices (below) |
| `R` | A request: packed item IDs |
| `P` | The old `id:copper:time;...` format, still read but no longer sent |

Packing writes numbers in base 32 and each number marks its own end: every digit
but the last is one of `0-9a-v`, the last one of `wxyzA-Z+/`, so nothing
separates them. A `Z` message is the newest scan time in seconds, then for
each item, sorted by ID: the ID minus the previous one, the lowest price, how
many minutes older than that time, market minus lowest plus 1 (0 = none), and
the number listed plus 1 (0 = unknown). An `R` message is just the ID
differences. A price takes 8 to 10 characters, about 25 per message.
