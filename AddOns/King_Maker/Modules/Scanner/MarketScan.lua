local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API

-- Scan providers and the quick scan.
--
-- Scanner King runs every scan, but some of what a scan covers comes from the addon that registered a scan
-- provider (Market King: professions and their recipes). Since King Maker 2.1 there is no picker: the
-- provider says what is selected right now (Crafting Profits' ticked professions), and every quick scan
-- (the Scan button while the full dump is on cooldown) prices those items along with Trade Goods and every
-- Watch() list. When a scan that included them finishes, the provider is told.
--
--   ScannerKing.RegisterScanProvider(owner, {
--       options  = { { key = ..., label = "Alchemy" }, ... },
--       items    = function(picked) return { itemID, ... } end,  -- picked = { [key] = true }
--       selected = function() return { [key] = true } end,      -- optional: the current selection
--                                                                --   (without it every option counts)
--       finished = function(picked, found) end,                 -- optional
--   })

local provider
local running = nil -- the picked set while a scan with the provider's items runs

function API.RegisterScanProvider(owner, def)
    provider = def -- one provider (the last to register); owner is kept for the API's shape
end

function ns.HasScanProvider() return provider ~= nil end

-- The provider's current selection as { [key] = true }, or nil (no provider, or nothing selected).
function ns.ProviderSelection()
    if not provider then return nil end
    local set = {}
    if type(provider.selected) == "function" then
        local ok, r = pcall(provider.selected)
        for k, v in pairs(ok and type(r) == "table" and r or {}) do
            if v then set[k] = true end
        end
    else
        for _, o in ipairs(provider.options or {}) do set[o.key] = true end
    end
    return next(set) and set or nil
end

-- The selection and the items it needs priced (nil, nil when there is nothing to add).
local function providerPick(set)
    set = set or ns.ProviderSelection()
    if not set then return nil, nil end
    local ok, items = pcall(provider.items, set)
    if not ok or type(items) ~= "table" then return set, nil end
    return set, items
end

-- What a quick scan covers besides Trade Goods, for the Scan button's tooltip:
-- { total = items, watched = from Watch() lists, prof = more from the provider, profs = options selected }.
function ns.QuickPlan()
    local have, watched = {}, 0
    for _, id in ipairs(ns.WatchedItems()) do have[id] = true; watched = watched + 1 end
    local set, items = providerPick()
    local prof, profs = 0, 0
    for _ in pairs(set or {}) do profs = profs + 1 end
    for _, id in ipairs(items or {}) do
        if not have[id] then have[id] = true; prof = prof + 1 end
    end
    return { total = watched + prof, watched = watched, prof = prof, profs = profs }
end

local function run(set, items)
    if API.IsScanning() then
        KM.Print(ns, "A scan is already running.")
        return
    end
    running = set
    API.Scan({ items = items, kind = "market" })
    if not API.IsScanning() then running = nil end -- e.g. the auction house was closed
end

-- The quick scan: Trade Goods + every Watch() list + the provider's current selection. Reports kind "market"
-- when the provider added items, else "material" (the kinds Econ and the King Dashboard already know).
function API.QuickScan()
    if not ns.db then return end
    local set, items = providerPick()
    if items and #items > 0 then return run(set, items) end
    return API.Scan()
end

-- Runs a quick scan with the provider's items for this set (default: its current selection); /sk market.
function API.MarketScan(set)
    if not provider then
        KM.Print(ns, "Pricing professions needs the Crafting Profits module (Market King).")
        return
    end
    if type(set) ~= "table" or not next(set) then set = ns.ProviderSelection() end
    if not set then
        KM.Print(ns, "Tick the professions to price on Crafting Profits first (/km crafting).")
        return
    end
    local _, items = providerPick(set)
    if type(items) ~= "table" then return end
    run(set, items)
end

-- Kept for addons that called it: there is no picker any more. At the auction house it runs the one scan;
-- elsewhere it opens Crafting Profits, where the professions to price are ticked.
function API.OpenMarketScan()
    if not ns.db then return end
    if ns.AHOpen and ns.AHOpen() then return API.SmartScan() end
    KM.Print(ns, "Open the auction house and click Scan. It prices the professions ticked on Crafting Profits.")
    if KM.pages and KM.pages.crafting then KM.Show("crafting") end
end
ns.ToggleMarketScan = function() API.OpenMarketScan() end

API.RegisterCallback("Scanner_King_market", function(event, arg)
    if not running or event ~= "SCAN_FINISHED" then return end
    local set = running
    running = nil
    if provider and provider.finished then pcall(provider.finished, set, arg) end
end)
