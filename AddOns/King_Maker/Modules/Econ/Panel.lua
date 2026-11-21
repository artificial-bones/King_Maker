local _, KM = ...
local ns = KM.Module("Econ")
local UI = KM.UI
local C = UI.C

-- Favorites at the auction house: a small panel docked to the right edge of AuctionHouseFrame (anchored to it, never
-- parented to it or changing it), shown while the auction house is open. Your Price History favorites, A to Z, each
-- with its lowest price and 7-day trend:
--   click a row    its name goes into the auction house's own search bar and searches, so it comes up there to buy
--   Graph          its Price History page (the graph and the 30-day numbers) in the King Maker window
--   x              take it off your favorites
--   hover          the item's tooltip, with Price History's averages and trend
-- The button on top is for the item the auction house showed last (the one you opened or searched): add it to your
-- favorites, or remove it. The "Favorites" button beside the auction house brings the panel back after x.
-- Nothing here buys, and nothing hooks C_AuctionHouse (docs/gotchas.md 3): searching isn't protected.
--
-- Saved: EconKingDB.ui.ahPanel (show it at the auction house; x turns it off, the Favorites button back on).

local W, ROW_H, ROWS, ROW_TOP = 300, 24, 14, -72
local DASH = "|cff808080-|r"

local panel, toggle
local rows, offset, list = {}, 0, {}
local ahShown = false
local current -- itemID of what the auction house showed last (its search results), this visit only

function ns.AHOpen()
    return ahShown and AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false
end

local function anchorTo(frame, x, y)
    frame:ClearAllPoints()
    if AuctionHouseFrame then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", x or 2, y or 0)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
    end
end

-- The item's name, from the game when Price History hasn't seen it yet; nil while the game hasn't loaded it.
local function nameOf(id)
    local n = ns.Name(id)
    if n and not n:find("^Item %d+$") then return n end
    n = GetItemInfo and GetItemInfo(id)
    return n
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Fills the auction house's own search bar with the item's name and runs that search, so its results come up in
-- Blizzard's window to buy there as usual. Only from a click. Returns true when the search started.
function ns.SearchInAH(id)
    local f = AuctionHouseFrame
    local bar = type(f) == "table" and rawget(f, "SearchBar") or nil
    local box = type(bar) == "table" and rawget(bar, "SearchBox") or nil
    if not (ns.AHOpen() and type(box) == "table" and box.SetText) then return false end
    local name = nameOf(id)
    if not name then
        KM.Print(ns, "the game hasn't loaded that item's name yet; click it again in a moment.")
        return false
    end
    if not pcall(box.SetText, box, name) then return false end
    if type(bar.StartSearch) == "function" and pcall(bar.StartSearch, bar) then return true end
    local btn = rawget(bar, "SearchButton")
    if type(btn) == "table" and btn.Click and pcall(btn.Click, btn) then return true end
    return false
end

-- The item's Price History page in the King Maker window.
function ns.OpenHistory(id)
    if not id then return end
    ns.Toggle(true)
    ns.ShowItem(id)
end

function ns.CurrentAHItem() return current end

-- The top button: favorite the item the auction house showed last, or take it off.
function ns.ToggleCurrent()
    if not current then return end
    local on = not ns.db.fav[current]
    ns.SetFavorite(current, on)
    KM.Print(ns, ns.ColoredName(current) .. (on and " added to favorites." or " removed from favorites."))
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function lowest(id)
    local sk = ScannerKing
    if not (sk and sk.GetPrice) then return nil end
    local p, t = KM.Safe(sk.GetPrice, id)
    return p, t
end

-- Favorites, A to Z: { id, name, lowest, t, trend }.
function ns.PanelRows()
    local out = {}
    for id in pairs(ns.db and ns.db.fav or {}) do
        local p, t = lowest(id)
        local s = ns.Stats(id)
        out[#out + 1] = { id = id, name = ns.Name(id), lowest = p, t = t, trend = s and s.trend7 }
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

local function rowTip(self)
    local r = self.data
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, r.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Lowest " .. (r.lowest and ns.Money(r.lowest) or "not scanned") .. (r.t and ("  (" .. ns.Age(r.t) .. ")") or ""), 1, 1, 1)
    GameTooltip:AddLine("Click: search it here.  Graph: its price history.  x: remove.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function makeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 8, ROW_TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    r.zebra = UI.Fill(r, C.zebra)
    r.zebra:SetShown(i % 2 == 0)
    r.sel = UI.Fill(r, C.sel, "ARTWORK")
    r.sel:Hide()
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(ROW_H - 6, ROW_H - 6)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.remove = UI.Button(r, "x", 20, ROW_H - 4, function()
        if not r.data then return end
        UI.Click()
        ns.SetFavorite(r.data.id, false)
    end)
    r.remove:SetPoint("RIGHT", 0, 0)
    UI.Tip(r.remove, "Remove from favorites.")
    r.graph = UI.Button(r, "Graph", 44, ROW_H - 4, function()
        if r.data then UI.Click(); ns.OpenHistory(r.data.id) end
    end)
    r.graph:SetPoint("RIGHT", r.remove, "LEFT", -3, 0)
    UI.Tip(r.graph, "Its price history: the graph, the 7- and 30-day averages, the low and high.")
    r.trend = UI.Text(r, 10, C.text, "RIGHT")
    r.trend:SetPoint("RIGHT", r.graph, "LEFT", -4, 0)
    r.trend:SetWidth(36)
    r.price = UI.Text(r, 11, C.text, "RIGHT")
    r.price:SetPoint("RIGHT", r.trend, "LEFT", -3, 0)
    r.price:SetWidth(56)
    r.name = UI.Text(r, 11, C.text)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetPoint("RIGHT", r.price, "LEFT", -4, 0)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnClick", function(self)
        if not self.data then return end
        if IsShiftKeyDown() and ChatEdit_InsertLink then
            local _, link = GetItemInfo(self.data.id)
            if link then ChatEdit_InsertLink(link) end
            return
        end
        UI.Click()
        ns.SearchInAH(self.data.id)
    end)
    r:SetScript("OnEnter", rowTip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

---------------------------------------------------------------------------
-- Building and drawing
---------------------------------------------------------------------------

local function build()
    if panel then return end
    panel = CreateFrame("Frame", "KingMakerFavoritesPanel", UIParent)
    panel:SetSize(W, -ROW_TOP + ROWS * ROW_H + 34)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    UI.Fill(panel, C.bg)
    UI.Border(panel, { 1, 1, 1, 0.10 })
    UI.GoldEdge(panel)
    panel:Hide()
    panel.title = UI.Text(panel, 13, C.accent)
    panel.title:SetPoint("TOPLEFT", 12, -11)
    panel.close = UI.CloseButton(panel, function() ns.ShowPanel(false) end)
    panel.close:SetPoint("TOPRIGHT", -6, -6)

    panel.add = UI.Button(panel, "", W - 16, 24, function() UI.Click(); ns.ToggleCurrent() end, "primary")
    panel.add:SetPoint("TOPLEFT", 8, -34)
    UI.Tip(panel.add, function(tt)
        tt:AddLine(current and "Adds the item the auction house showed last to your favorites, or takes it off."
            or "Open an item in the auction house (search it, click a result) and this button favorites it.", 1, 1, 1, true)
    end)

    for i = 1, ROWS do rows[i] = makeRow(panel, i) end
    panel.empty = UI.Para(panel, 11, C.dim, W - 24)
    panel.empty:SetPoint("TOPLEFT", 12, ROW_TOP - 8)
    panel.hint = UI.Text(panel, 9, C.muted)
    panel.hint:SetPoint("BOTTOMLEFT", 12, 10)
    panel.hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta * 3, #list - ROWS))
        ns.RefreshPanel()
    end)
    ns.panel, ns.panelRows = panel, rows

    toggle = UI.Button(UIParent, "|T" .. ns.STAR .. ":12|t Favorites", 92, 22, function() ns.ShowPanel(true) end, "primary")
    toggle:SetFrameStrata("HIGH")
    toggle:Hide()
    ns.toggle = toggle
end

function ns.RefreshPanel()
    if not (panel and panel:IsShown() and ns.db) then return end
    list = ns.PanelRows()
    offset = math.max(0, math.min(offset, #list - ROWS))
    panel.title:SetText("|T" .. ns.STAR .. ":14|t Favorites" .. (#list > 0 and ("  |cff808080" .. #list .. "|r") or ""))
    if current then
        local name = ns.ColoredName(current)
        panel.add:SetLabel((ns.db.fav[current] and "Remove " or "|T" .. ns.STAR .. ":12|t Add ") .. name)
        panel.add:SetEnabled2(true)
    else
        panel.add:SetLabel("Open an item to favorite it")
        panel.add:SetEnabled2(false)
    end
    for i, f in ipairs(rows) do
        local r = list[i + offset]
        f.data = r
        if r then
            f.icon:SetTexture(ns.Icon(r.id))
            f.name:SetText(ns.ColoredName(r.id))
            f.price:SetText(r.lowest and KM.MoneyShort(r.lowest) or DASH)
            f.trend:SetText(r.trend and ns.Percent(r.trend, true) or "")
            f.sel:SetShown(r.id == current)
            f:Show()
        else
            f:Hide()
        end
    end
    panel.empty:SetText(#list == 0 and ("No favorites yet. Open an item in the auction house and click Add above, or "
        .. "click the star on an item in Price History.") or "")
    panel.hint:SetText(#list > ROWS and ("Scroll for more (" .. (offset + 1) .. "-" .. math.min(offset + ROWS, #list) .. " of " .. #list .. ")")
        or (#list > 0 and "Click an item to search it. Trend: last 7 days." or ""))
end

---------------------------------------------------------------------------
-- Showing and hiding with the auction house
---------------------------------------------------------------------------

function ns.ShowPanel(on)
    build()
    ns.db.ui.ahPanel = on and true or false
    if on and ns.AHOpen() then
        anchorTo(panel, 2, 0)
        panel:Show()
        toggle:Hide()
        ns.RefreshPanel()
    else
        panel:Hide()
        if ns.AHOpen() then anchorTo(toggle, 2, -4); toggle:Show() else toggle:Hide() end
    end
end

function ns.TogglePanel()
    if not ns.AHOpen() then return KM.Print(ns, "open the auction house first; the Favorites panel sits beside it.") end
    ns.ShowPanel(not (panel and panel:IsShown()))
end

local function onShow()
    if not AuctionHouseFrame then
        -- the auction house UI loads on demand: try again once it's there
        if C_Timer and C_Timer.After then C_Timer.After(0.2, function() if AuctionHouseFrame and ahShown then onShow() end end) end
        return
    end
    ns.ShowPanel(ns.db.ui.ahPanel)
end

local f = CreateFrame("Frame")
KM.Register(f, "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED")
f:SetScript("OnEvent", function(_, event, a)
    if not ns.db then return end
    if event == "AUCTION_HOUSE_SHOW" then
        ahShown, current = true, nil
        KM.Safe(onShow)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahShown, current = false, nil
        if panel then panel:Hide() end
        if toggle then toggle:Hide() end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if tonumber(a) then current = tonumber(a); ns.RefreshPanel() end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if type(a) == "table" and tonumber(a.itemID) then current = tonumber(a.itemID); ns.RefreshPanel() end
    end
end)
