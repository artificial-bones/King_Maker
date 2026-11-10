local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API
local UI = KM.UI
local C = UI.C

-- Market Scan: Scanner King runs every scan, but what a market scan covers
-- comes from the addon that registered it (Market King: professions and their
-- recipes). The Market Scan button opens a King Maker dialog with every option ticked;
-- untick what you don't want and click Scan. When it finishes, the provider
-- is told so it can show its results.
--
--   ScannerKing.RegisterScanProvider(owner, {
--       options  = { { key = ..., label = "Alchemy" }, ... },
--       items    = function(picked) return { itemID, ... } end,  -- picked = { [key] = true }
--       finished = function(picked, found) end,                 -- optional
--   })

local provider, providerOwner
local win, checks, status, scanBtn
local running = nil -- the picked set while a market scan runs

function API.RegisterScanProvider(owner, def)
    provider, providerOwner = def, owner
    local b = ns.MarketButton and ns.MarketButton()
    if b then b:Show() end
end

function ns.HasScanProvider() return provider ~= nil end

local function picked()
    local set = {}
    for _, c in ipairs(checks) do if c:GetChecked() then set[c.key] = true end end
    return set
end

local function updateButton()
    scanBtn:SetEnabled2(next(picked()) ~= nil and not API.IsScanning())
end

local function create()
    local n = #provider.options
    win = UI.Window("ScannerKingMarketScan", "Market Scan", 280, 150 + n * 22)
    local body = win.body
    local help = UI.Para(body, 11, C.muted, 252)
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetText("Prices Trade Goods plus everything these professions make and use.")

    checks = {}
    for i, opt in ipairs(provider.options) do
        local c = UI.CheckLabel(body, opt.label, updateButton)
        c.frame:SetPoint("TOPLEFT", 0, -34 - (i - 1) * 22)
        c.key = opt.key
        checks[i] = c
    end
    local function setAll(v)
        for _, c in ipairs(checks) do c:SetChecked(v) end
        updateButton()
    end
    local all = UI.Button(body, "All", 60, 22, function() setAll(true) end)
    all:SetPoint("TOPRIGHT", 0, -32)
    local none = UI.Button(body, "None", 60, 22, function() setAll(false) end)
    none:SetPoint("TOP", all, "BOTTOM", 0, -4)

    scanBtn = UI.Button(body, "Scan", 130, 26, function() API.MarketScan(picked()) end, "primary")
    scanBtn:SetPoint("BOTTOM", 0, 22)
    status = UI.Text(body, 11, C.muted, "CENTER")
    status:SetPoint("BOTTOMLEFT", 0, 4)
    status:SetPoint("BOTTOMRIGHT", 0, 4)
end

function ns.ToggleMarketScan(anchor, show)
    if not provider then
        KM.Print(ns, "Market Scan needs the Crafting Profits module (Market King).")
        return
    end
    if not win then create() end
    if show == nil then show = not win:IsShown() end
    if show then
        for _, c in ipairs(checks) do c:SetChecked(true) end -- everything ticked each time
        win:ClearAllPoints()
        if anchor and anchor:IsShown() then
            win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
        else
            win:SetPoint("CENTER")
        end
        if not running then
            status:SetText(ns.db.lastScan and ("Last scan " .. API.PriceAge(ns.db.lastScan)) or "")
        end
        updateButton()
    end
    win:SetShown(show)
end

function API.OpenMarketScan()
    ns.ToggleMarketScan(ns.ahParent, true)
end

-- Runs a market scan for these picked options.
function API.MarketScan(set)
    if not provider or not next(set) then return end
    if API.IsScanning() then
        KM.Print(ns, "A scan is already running.")
        return
    end
    local ok, items = pcall(provider.items, set)
    if not ok or type(items) ~= "table" then return end
    running = set
    if status then status:SetText("Starting: " .. #items .. " items plus Trade Goods") end
    local b = ns.MarketButton and ns.MarketButton()
    if b and ns.SetScanButton then ns.SetScanButton(b) end
    API.Scan({ items = items, kind = "market" })
    if not API.IsScanning() then running = nil end -- e.g. the auction house was closed
    if scanBtn then updateButton() end
end

API.RegisterCallback("Scanner_King_market", function(event, arg)
    if not running then return end
    if event == "SCAN_PROGRESS" then
        if status then status:SetText(arg or "") end
    elseif event == "SCAN_FINISHED" then
        local set = running
        running = nil
        if status then status:SetText("Done: " .. (arg or 0) .. " prices") end
        if scanBtn then updateButton() end
        if win then win:Hide() end
        if provider.finished then pcall(provider.finished, set, arg) end
    end
end)
