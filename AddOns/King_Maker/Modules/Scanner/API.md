# How the King modules connect

Since King Maker 2.0 every King addon is a module of one addon, King Maker
(`Modules\<Name>\`). Each module keeps its own saved variable and its own
public global, so other addons (Oracle, third-party code) call them exactly as
before.

## 1. Load order

`King_Maker.toc` lists the Scanner module first, so `ScannerKing` exists
before any other module's files run. Saved variables are ready when King
Maker's `ADDON_LOADED` fires (each module's `InitDB`), and the world at
`PLAYER_LOGIN`, which is when the other modules register their callbacks,
watches and scan providers.

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
ScannerKing.LastDeepScan()        -- server time of the last Deep Scan (full scan)

-- King Maker has one Scan button (2.1). It calls SmartScan; the rest are the parts it is made of.
ScannerKing.SmartScan()           -- the one scan: DeepScan() when the full dump is off cooldown, else QuickScan()
ScannerKing.FullScanReadyIn()     -- seconds until the game allows the next full dump (0 = now),
                                  -- nil when the client has no ReplicateItems (then SmartScan is always quick)
ScannerKing.QuickScan()           -- Trade Goods + every Watch() list + every scan provider's current selection
ScannerKing.DeepScan()            -- every item on the auction house (auction house must be open); while the dump
                                  -- is on cooldown it browses every category instead (lowest prices only)
ScannerKing.OpenDeepScan(start)   -- the Deep Scan progress window (/sk deep); start = true also starts the scan
ScannerKing.Scan()                -- Trade Goods + watched items (auction house must be open)
ScannerKing.Scan({ items = ids }) -- the same, plus these items (searched 100 at a time)
ScannerKing.IsScanning()

-- Ask for items outside Trade Goods to be included in every scan.
-- Pass a list, or a function that returns the list when a scan starts.
ScannerKing.Watch("gather_king", function() return { 268415, 268416 } end)

-- Hear about scans and new prices. fn(event, ...) gets:
--   "SCAN_STARTED", "SCAN_PROGRESS" (text), "SCAN_FINISHED" (found), "PRICES_UPDATED"
--   "SCAN_RESULTS" (results, kind, method) just before SCAN_FINISHED, with what this scan saw:
--       kind = "material" (Trade Goods + watched), "market" (the same plus a scan provider's items: a quick
--              scan with professions ticked, or /sk market) or "deep" (the full scan). No new kinds in 2.1.
--       results = { [itemID] = { p = lowest copper each, q = quantity listed,
--                                m = market price, n = auctions, s = sellers,      (Deep Scan)
--                                l = { { copper each, count }, ... } } }        (Deep Scan, full list only)
--   "GUILD_PRICES" (batch) when guildmates' newer prices arrived:
--       batch = { [itemID] = { p = lowest, m = market or nil, q = listed or nil, t = their scan time, from = name } }
--       method (Deep Scan) = "replicate" (every auction, all fields), "browse" (p and q only)
--                            or "partial" (browse that stopped answering: some items are missing)
ScannerKing.RegisterCallback("gather_king", fn)
ScannerKing.UnregisterCallback("gather_king")

-- Add your items to every quick scan (Market King does this). There is no picker since 2.1: `selected`
-- says what is chosen right now (Crafting Profits' ticked professions); without it every option counts.
-- finished is called after a scan that included your items.
ScannerKing.RegisterScanProvider("Market_King", {
    options  = { { key = 4, label = "Alchemy" }, ... },
    items    = function(picked) return { itemID, ... } end, -- picked = { [key] = true }
    selected = function() return { [4] = true } end,       -- optional
    finished = function(picked, found) end,                 -- optional
})
ScannerKing.MarketScan([picked])  -- a quick scan with the provider's items for picked (default: its selection)
ScannerKing.OpenMarketScan()      -- kept for old callers: at the auction house it runs SmartScan(),
                                  -- elsewhere it opens Crafting Profits

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

- **Scanner King** owns every auction house scan and the one Scan button.
- **Gather King**, **Econ King**, **Shopping** and **Market King** only read prices and tell Scanner King
  what they need: through `Watch` (Gather, Econ favorites, Shopping lists), or `RegisterScanProvider`
  (Market King's ticked professions). Every quick scan covers all of them.
- **Econ King** listens for `SCAN_RESULTS` and keeps every scan as history.

## Saved data

| Addon | Saved variable | Holds |
|---|---|---|
| gather_king | `GatherKingDB` | markers, profiles, loot stats, ledger |
| Scanner_King | `ScannerKingDB` | prices, `lastScan`, `lastDeep`, `lastReplicate`, `lastQuick` (2.1: last quick scan), sync setting |
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
