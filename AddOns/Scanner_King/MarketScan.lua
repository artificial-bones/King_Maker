local _, ns = ...
local API = ns.API

-- Market Scan: Scanner King runs every scan, but what a market scan covers
-- comes from the addon that registered it (Market King: professions and their
-- recipes). The Market Scan button opens a picker with every option ticked;
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
    scanBtn:SetEnabled(next(picked()) ~= nil and not API.IsScanning())
end

local function create()
    win = CreateFrame("Frame", "ScannerKingMarketScan", UIParent, "BackdropTemplate")
    win:SetSize(260, 120 + #provider.options * 22)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "ScannerKingMarketScan") end

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Market Scan")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local help = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 16, -38)
    help:SetWidth(228)
    help:SetJustifyH("LEFT")
    help:SetText("Prices Trade Goods plus everything these professions make and use.")

    checks = {}
    for i, opt in ipairs(provider.options) do
        local c = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        c:SetSize(22, 22)
        c:SetPoint("TOPLEFT", 16, -64 - (i - 1) * 22)
        c.key = opt.key
        local label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", c, "RIGHT", 2, 1)
        label:SetText(opt.label)
        c:SetScript("OnClick", updateButton)
        checks[i] = c
    end
    local function setAll(v)
        for _, c in ipairs(checks) do c:SetChecked(v) end
        updateButton()
    end
    local all = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    all:SetSize(60, 20)
    all:SetPoint("TOPRIGHT", -16, -64)
    all:SetText("All")
    all:SetScript("OnClick", function() setAll(true) end)
    local none = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    none:SetSize(60, 20)
    none:SetPoint("TOP", all, "BOTTOM", 0, -4)
    none:SetText("None")
    none:SetScript("OnClick", function() setAll(false) end)

    scanBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    scanBtn:SetSize(120, 24)
    scanBtn:SetPoint("BOTTOM", 0, 36)
    scanBtn:SetText("Scan")
    scanBtn:SetScript("OnClick", function() API.MarketScan(picked()) end)
    status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOM", 0, 18)
    status:SetWidth(228)
    win:Hide()
end

function ns.ToggleMarketScan(anchor, show)
    if not provider then
        ns.Print("Market Scan needs Market King installed.")
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
        ns.Print("A scan is already running.")
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
