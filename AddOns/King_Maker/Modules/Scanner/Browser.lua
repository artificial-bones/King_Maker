local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API
local UI = KM.UI
local C = UI.C

-- The Prices page: every item Scanner King has a price for, grouped the way the auction house groups them
-- (Metal & Stone, Herb, Cloth, ...), with search, sortable columns and the Scan button. Opened from the King
-- Maker window (Auction House > Prices), the crown's quick actions, /sk or /km prices.
--
--   tiles      prices known (last quick scan), last full scan, market prices, guild sharing
--   toolbar    search box; Scan (full when the game allows it, else quick: Scan.lua)
--   left       categories (wheel scrolls them when a Deep Scan brings more than fit)
--   right      the list: item, market price, lowest buyout, listed, scanned
--
-- Also here: the crown's quick actions, tooltip line, status line, the Home tile and the Settings section.

local CAT_W, CAT_H, CAT_ROWS = 150, 22, 18
local TILE_W, TILE_H = 182, 60

local page
local category, catOffset = "All", 0
local list = {}

---------------------------------------------------------------------------
-- Item info: name, icon and category, cached so the list works offline too
---------------------------------------------------------------------------

local function info(id)
    local c = ns.db.items[id]
    if c and c.name then return c end
    c = c or {}
    local name, icon, classID, sub, typeName
    if C_Item and C_Item.GetItemInfoInstant then
        local _, itemType, itemSubType, _, tex, cls = C_Item.GetItemInfoInstant(id)
        typeName, sub, icon, classID = itemType, itemSubType, tex, cls
    end
    name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id) -- arrives as GET_ITEM_INFO_RECEIVED; the shell redraws the page
    end
    c.name = name
    c.icon = icon or c.icon
    if classID == 7 and sub then
        c.cat = sub -- Trade Goods: use its subcategory (Metal & Stone, Herb, Cloth...)
    elseif typeName then
        c.cat = typeName
    end
    ns.db.items[id] = c
    return c
end

local function count()
    local n = 0
    for _ in pairs(ns.db.prices) do n = n + 1 end
    return n
end

local function categories()
    local seen, cats = {}, {}
    for id in pairs(ns.db.prices) do
        local cat = info(id).cat or "Other"
        if not seen[cat] then seen[cat] = true; table.insert(cats, cat) end
    end
    table.sort(cats)
    table.insert(cats, 1, "All")
    return cats
end

local SORT = {
    name = function(e) return e.name end,
    market = function(e) return e.m end,
    price = function(e) return e.p end,
    qty = function(e) return e.q end,
    age = function(e) return e.t end,
}

local function build(text, sortBy, sortDesc)
    wipe(list)
    text = (text or ""):lower()
    for id, pr in pairs(ns.db.prices) do
        local i = info(id)
        local name = i.name or ("Item " .. id)
        if (category == "All" or (i.cat or "Other") == category)
            and (text == "" or name:lower():find(text, 1, true)) then
            table.insert(list, { id = id, name = name, icon = i.icon, p = pr.p, m = pr.m, q = pr.q, t = pr.t, from = pr.from })
        end
    end
    local get = SORT[sortBy] or SORT.price
    table.sort(list, function(a, b)
        local x, y = get(a), get(b)
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end -- blanks last either way
            return a.name < b.name
        end
        if x == y then return a.name < b.name end
        if sortDesc then return x > y end
        return x < y
    end)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function scanAge(t) return t and API.PriceAge(t) or "never" end

-- The Prices known tooltip (this page and Home): where the prices came from.
function ns.PricesKnownTip(tt)
    local market, guild = 0, 0
    for _, pr in pairs(ns.db.prices) do
        if pr.m then market = market + 1 end
        if pr.from then guild = guild + 1 end
    end
    local n = count()
    tt:AddLine("Every item you have an auction price for, from your own scans and your guildmates'. Yellow on Home when the last full scan is over a day old.", 1, 1, 1, true)
    tt:AddDoubleLine("With a market price", KM.Commas(market), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Lowest buyout only", KM.Commas(n - market), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Scanned by a guildmate", KM.Commas(guild), 0.8, 0.8, 0.8, 1, 1, 1)
end

local function refreshTiles(c)
    local n = count()
    local quick = ns.db.lastQuick
    c.tiles[1]:Set("Prices known", KM.Commas(n), quick and ("quick scan " .. API.PriceAge(quick)) or "no quick scan yet")
    local deep = ns.db.lastDeep
    local stale = not deep or ns.Now() - deep > 86400
    c.tiles[2]:Set("Last full scan", deep and API.PriceAge(deep) or "never", stale and "over a day old: scan at the auction house" or "market prices are fresh",
        stale and C.warn or C.good)
    local market = 0
    for _, pr in pairs(ns.db.prices) do if pr.m then market = market + 1 end end
    c.tiles[3]:Set("Market prices", KM.Commas(market), "from full scans")
    local s = ns.Stamp()
    local sub = not (IsInGuild and IsInGuild()) and "not in a guild"
        or (s.t > 0 and ("newest scan: " .. (KM.IsMe(s.by) and "yours" or (s.by or "?")) .. ", " .. API.PriceAge(s.t)))
        or "newest price wins"
    c.tiles[4]:Set("Guild sharing", ns.db.sync.guild and "On" or "Off", sub, ns.db.sync.guild and C.text or C.dim)
end

local function refreshCategories(c)
    local cats = categories()
    local known = false
    for _, cat in ipairs(cats) do if cat == category then known = true end end
    if not known then category = "All" end
    catOffset = math.max(0, math.min(catOffset, #cats - CAT_ROWS))
    for i, b in ipairs(c.catButtons) do
        local cat = cats[i + catOffset]
        if cat then
            b.cat = cat
            b:SetLabel(cat)
            b:SetActive(cat == category)
            b:Show()
        else
            b.cat = nil
            b:Hide()
        end
    end
end

local function fillRow(r, e, cells)
    r.item = e.id
    if r.icon then r.icon:SetTexture(e.icon) end
    cells.name:SetText(e.name)
    cells.market:SetText(e.m and API.FormatMoney(e.m) or "|cff808080-|r")
    cells.price:SetText(API.FormatMoney(e.p))
    cells.qty:SetText(e.q and KM.Commas(e.q) or "")
    cells.age:SetText(UI.Hex(C.muted) .. API.PriceAge(e.t) .. (e.from and (" (" .. e.from .. ")") or "") .. "|r")
end

local function footerText(c)
    local tbl, total = c.table, count()
    local shown = math.min(#list, tbl.visible or #list)
    c.footer:SetText((#list > 0 and ((tbl.offset + 1) .. "-" .. (tbl.offset + shown) .. " of " .. #list) or "No items")
        .. (#list ~= total and (" (" .. total .. " in all)") or "")
        .. ".  Last full scan: " .. scanAge(ns.db.lastDeep) .. ".  Last quick scan: " .. scanAge(ns.db.lastQuick) .. ".")
end

local function refresh(c)
    if not ns.db then return end
    refreshTiles(c)
    refreshCategories(c)
    build(c.search:GetText(), c.table.sortKey, c.table.sortDesc)
    c.table.emptyText = count() == 0 and "No prices yet. Open the auction house and click Scan."
        or "Nothing matches. Names load as you browse; try again in a moment."
    c.table:SetRows(list, fillRow)
    local at = ns.AHOpen and ns.AHOpen()
    c.scan:SetEnabled2(at and not API.IsScanning())
    ns.RefreshScanCaption(c.scan)
end

local function buildPage(c)
    page = c
    -- Tiles across the top.
    c.tiles = {}
    for i = 1, 4 do
        local t = UI.Tile(c, TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), 0)
        c.tiles[i] = t
    end
    c.tiles[1]:SetTip(function(tt) ns.PricesKnownTip(tt) end)
    c.tiles[2]:SetTip("When you last ran a full scan: it downloads every auction and is the only scan that gives market prices. The game allows one every 15 minutes. Yellow once it's over a day old.")
    c.tiles[3]:SetTip("Items with a market price: the average of the cheapest 15-30% listed, so one cheap or silly listing doesn't move it. Only a full scan (yours or a guildmate's) works one out; a quick scan finds the lowest buyout only.")
    c.tiles[4]:SetTip("When on, the Trade Goods and watched-item prices you scan go to guildmates running King Maker after each scan, and theirs come to you; for each item the newest price wins. Change it in Settings > Scanner.")

    -- Toolbar: search left, scans right.
    c.search = UI.EditBox(c, 240, 24, "Search prices", function()
        if c.table then c.table.offset = 0; refresh(c) end
    end)
    c.search:SetPoint("TOPLEFT", 0, -(TILE_H + 12))
    c.scan = UI.Button(c, "Scan", 150, 24, function() API.SmartScan(); refresh(c) end, "primary")
    c.scan:SetPoint("TOPRIGHT", 0, -(TILE_H + 12))
    UI.Tip(c.scan, function(tt) ns.ScanTooltip(tt) end)

    local top = -(TILE_H + 12 + 24 + 10)

    -- Categories down the left.
    local side = CreateFrame("Frame", nil, c)
    side:SetPoint("TOPLEFT", 0, top)
    side:SetPoint("BOTTOMLEFT", 0, 22)
    side:SetWidth(CAT_W)
    UI.Fill(side, { 0, 0, 0, 0.18 })
    UI.Border(side)
    c.catButtons = {}
    for i = 1, CAT_ROWS do
        local b = UI.Button(side, "", CAT_W - 12, CAT_H - 2, function(self)
            if not self.cat then return end
            category, c.table.offset = self.cat, 0
            refresh(c)
        end, "ghost")
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * CAT_H)
        b.label:SetJustifyH("LEFT")
        c.catButtons[i] = b
    end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        catOffset = math.max(0, catOffset - delta * 3)
        refreshCategories(c)
    end)

    -- The list.
    local cols = {
        { key = "name", label = "Item", w = 210, sort = SORT.name, desc = false },
        { key = "market", label = "Market", w = 104, justify = "RIGHT", sort = SORT.market,
          tip = "Market price from the last full Deep Scan: the average of the cheapest 15-30% listed." },
        { key = "price", label = "Lowest", w = 104, justify = "RIGHT", sort = SORT.price,
          tip = "The cheapest buyout, each, when it was last scanned." },
        { key = "qty", label = "Listed", w = 64, justify = "RIGHT", sort = SORT.qty,
          tip = "How many were for sale in all, across every listing." },
        { key = "age", label = "Scanned", w = 0, sort = SORT.age,
          tip = "How old the price is. A name in brackets: the guildmate who sent it." },
    }
    c.table = UI.Table(c, cols, 22, { icon = true, noSort = true, onSort = function() refresh(c) end })
    c.table:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    c.table:SetPoint("BOTTOMRIGHT", 0, 22)
    c.table:SetSort("price", true)
    c.table.fill = fillRow
    c.table.onRedraw = function() footerText(c) end

    c.footer = UI.Text(c, 10, C.muted)
    c.footer:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 12, -16)
    c.footer:SetPoint("RIGHT", c, "RIGHT", 0, 0)
end

function API.ToggleBrowser(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("prices") end
    if show then KM.Show("prices") elseif KM.IsShown("prices") then KM.Toggle(false) end
end

-- The open page, for the module's own refreshes (nil until built).
function ns.UpdateBrowser() KM.Refresh("prices") end
ns.PricesPage = function() return page end
ns.PriceList = function() return list end

KM.RegisterPage({
    id = "prices", group = "ah", label = "Prices", icon = "Interface\\Icons\\INV_Misc_Coin_02", order = 10,
    title = "Prices",
    subtitle = function()
        if API.IsScanning() then return "Scanning the auction house..." end
        return "Every auction price you or your guild have scanned. Market prices come from full scans."
    end,
    build = buildPage, refresh = refresh,
})

API.RegisterCallback("Scanner_King_browser", function(event)
    if event == "PRICES_UPDATED" or event == "SCAN_FINISHED" or event == "SCAN_STARTED" then KM.Refresh() end
end)

---------------------------------------------------------------------------
-- The crown (quick actions, tooltip), the sidebar status, Home and Settings
---------------------------------------------------------------------------

-- One Scan, only at the auction house (it can't scan anywhere else).
KM.RegisterQuickAction({ id = "scanner-scan", label = "Scan", order = 10,
    func = function() API.SmartScan() end, shown = function() return ns.AHOpen and ns.AHOpen() end })
KM.RegisterQuickAction({ id = "scanner-prices", label = "Prices", order = 13, func = function() KM.Show("prices") end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    tt:AddLine(KM.Commas(count()) .. " prices. Full scan: " .. scanAge(ns.db.lastDeep)
        .. ". Quick scan: " .. scanAge(ns.db.lastQuick) .. ".", 1, 1, 1)
end)

KM.RegisterStatus(function()
    if not ns.db then return nil end
    if API.IsScanning() then return "Prices: scanning..." end
    local function ago(t) local a = KM.Ago(t); return a == "now" and "just now" or (a .. " ago") end
    local deep, quick = ns.db.lastDeep, ns.db.lastQuick
    local line = deep and ("Prices: full scan " .. ago(deep)) or "Prices: no full scan yet"
    if quick and (not deep or quick > deep) then line = line .. ", quick " .. ago(quick) end
    return line
end)

KM.RegisterSettings({ id = "scanner", label = "Scanner", order = 10, rows = {
    { type = "header", label = "Tooltips" },
    { type = "check", label = "Prices in item tooltips", tip = "Market price, lowest buyout, how many are listed and when it was scanned.",
      get = function() return ns.db.ui.tooltip end, set = function(v) ns.db.ui.tooltip = v end },
    { type = "check", label = "Vendor, drops and recipes in item tooltips", tip = "Under the prices: what a vendor pays, what vendors charge, the mobs that drop it (best chance first) and the professions that use it.",
      get = function() return ns.db.ui.sources end, set = function(v) ns.db.ui.sources = v end },
    { type = "check", label = "Most valuable crafts it's used in", tip = "Under Used in: the 3 best things to make from it, what each sells for and the profit after the cut. Off by default.",
      get = function() return ns.db.ui.tip.crafts end, set = function(v) ns.db.ui.tip.crafts = v end },
    { type = "check", label = "Cost to craft and who can craft it", tip = "On crafted items: what the materials for one cost at today's prices, whether crafting one to sell makes or loses money, and which of your characters can make it.",
      get = function() return ns.db.ui.tip.make end, set = function(v) ns.db.ui.tip.make = v end },
    { type = "check", label = "Recipe items: what they teach and who can learn them", tip = "On patterns, plans, formulas and recipes: the recipe, which of your characters know it, can learn it, or need more skill.",
      get = function() return ns.db.ui.tip.pattern end, set = function(v) ns.db.ui.tip.pattern = v end },
    { type = "check", label = "Disenchant value", tip = "On gear: what disenchanting it is worth on average, and DISENCHANT in the verdict when that pays most.",
      get = function() return ns.db.ui.tip.de end, set = function(v) ns.db.ui.tip.de = v end },
    { type = "check", label = "Short tooltip: details with Shift", tip = "Only the verdict, the price and how many you own; hold Shift for everything else.",
      get = function() return ns.db.ui.tip.short end, set = function(v) ns.db.ui.tip.short = v end },
    { type = "header", label = "Guild" },
    { type = "check", label = "Share prices with my guild", tip = "Your Trade Goods prices go to guildmates running King Maker after each scan; theirs come to you, and when you log in a guildmate online who holds a newer scan catches you up. The newest price wins.",
      get = function() return ns.db.sync.guild end, set = function(v) ns.db.sync.guild = v end },
    { type = "check", label = "Ask the guild for prices of what you loot", tip = "When something drops that you have no price for (or only one over 6 hours old), King Maker asks your guild for it: once a session per item, half a minute of drops in one small message. Grey items, quest items and items that bind when picked up are skipped.",
      get = function() return ns.db.sync.loot end, set = function(v) ns.db.sync.loot = v end },
    { type = "check", label = "Share my full scans (every item)", tip = "Also pass on every item of a full scan, not only Trade Goods and watched items. Off by default: a whole auction house is about 290 messages, so it takes a few minutes in the background.",
      get = function() return ns.db.sync.full end, set = function(v) ns.db.sync.full = v end },
    { type = "button", label = "Ask the guild for a newer scan", tip = "Done by itself when you log in: a guildmate online who holds a newer scan than yours sends you its prices.",
      func = function() ns.AskNewest(); KM.Print(ns, "Asking the guild for a newer scan than yours.") end },
    { type = "button", label = "Send my prices to the guild now", tip = "Sends the Trade Goods and watched-item prices you scanned yourself recently to guildmates now, instead of after your next scan.",
      func = function() ns.SharePrices(true) end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/sk   open the Prices page\n/sk scan   Scan (at the auction house): full when the game allows it, else quick\n"
        .. "/sk deep   force a full scan (progress window)\n/sk material   force a quick scan of Trade Goods and watched items\n"
        .. "/sk market   the same plus Crafting Profits' ticked professions\n/sk tooltip on|off   prices in tooltips\n/sk sources on|off   vendor, drops and recipes in tooltips\n/sk tip crafts|make|pattern|de|short   more tooltip rows\n"
        .. "/sk sync [on|off]   share now, or turn sharing on/off\n/sk sync pull   ask for a newer scan\n/sk sync loot on|off   ask for prices of what you loot\n/sk sync full on|off   share every item of full scans\n/sk status   how many prices and how old" },
} })

-- Home: a row when prices are missing or more than a day old. The auction house opening or closing changes which
-- scan buttons work, so the open page redraws then.
KM.RegisterHomeCard({ kind = "attention", id = "scanner", order = 50, get = function()
    if not ns.db then return nil end
    local deep, quick = ns.db.lastDeep, ns.db.lastQuick
    local newest = math.max(deep or 0, quick or 0)
    local tip = function(tt) ns.PricesKnownTip(tt); tt:AddLine("Click for Prices.", 0.6, 0.6, 0.6) end
    if newest == 0 then
        return { { text = "No prices yet: scan at the auction house", color = C.info, page = "prices", tip = tip } }
    end
    if ns.Now() - newest > 86400 then
        return { { text = "Last price scan " .. API.PriceAge(newest) .. ": scan again", color = C.warn, page = "prices",
            value = KM.Commas(count()), tip = tip } }
    end
end })

local f = CreateFrame("Frame")
KM.Register(f, "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED")
f:SetScript("OnEvent", function() C_Timer.After(0.5, function() KM.Refresh() end) end)

