local _, ns = ...

-- White Items: the second tab at the top of the window. Every white (common)
-- item Scanner King has an auction price for, that some mob drops, ranked by
-- how worth hunting it is:
--
--   score = price x the square root of the drop's spawn points
--
-- Price is what one sells for at the auction house (after the 5% cut).
-- Spawn points add up every mob known to drop it (QuestieDB's spawns, or the
-- spots you've seen it), so an item with plenty of mobs to farm beats an
-- equally priced one with a single rare spawn; the square root keeps a common
-- junk drop from winning on numbers alone. The best item scores 100.
--
-- Click an item for every mob that drops it (the Mobs tab's item hunt); click
-- a mob there for its page.

local ROWS, ROW_H = 24, 18

local pane, rows, headers, footer, empty
local list = {}
local sortBy, sortDesc, offset = "score", true, 0

local COLS = {
    { key = "name", label = "White item", w = 250, justify = "LEFT" },
    { key = "price", label = "Price", w = 100, justify = "RIGHT", tip = "What one sells for at the auction house, after its 5% cut (Scanner King's market price)." },
    { key = "listed", label = "Listed", w = 70, justify = "RIGHT", tip = "How many are on the auction house: lots listed means lots of competition." },
    { key = "mobs", label = "Mobs", w = 60, justify = "RIGHT", tip = "How many different mobs are known to drop it." },
    { key = "spawns", label = "Spawns", w = 70, justify = "RIGHT", tip = "Spawn points of all those mobs together: how much there is to farm." },
    { key = "chance", label = "Best chance", w = 90, justify = "RIGHT", tip = "The best drop chance from the mobs you or your guild have killed." },
    { key = "score", label = "Score", w = 70, justify = "RIGHT", tip = "Price times the square root of spawn points; the best item is 100." },
}

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- itemID -> { [npcID] = true } from your kills and your guild's, in one pass.
local function seenDrops()
    local out = {}
    local function add(item, id)
        local t = out[item]
        if not t then t = {}; out[item] = t end
        t[id] = true
    end
    for id, m in pairs(ns.db.mobs) do for item in pairs(m.i or {}) do add(item, id) end end
    for _, g in pairs(ns.db.guild) do
        for id, gm in pairs(g.mobs or {}) do for item in pairs(gm.i or {}) do add(item, id) end end
    end
    return out
end

-- Every white item worth listing, with its numbers. Also how many white items
-- have prices, and how many of those wait on item info.
function ns.WhiteItems()
    local out, priced, loading = {}, 0, 0
    local prices = ScannerKing and ScannerKing.GetAllPrices and ScannerKing.GetAllPrices() or {}
    local seen = seenDrops()
    local spawnCount = {}
    local function spawns(id)
        if not spawnCount[id] then spawnCount[id] = #(ns.Spots(id)) end
        return spawnCount[id]
    end
    for item in pairs(prices) do
        local info = ns.Item(item)
        if not info.name then
            loading = loading + 1
        elseif info.q == 1 and not info.bop and info.class ~= 12 then
            local price, from = ns.ItemValue(item)
            if from == "ah" and price and price > 0 then
                priced = priced + 1
                local mobs = {}
                for id in pairs(seen[item] or {}) do mobs[id] = true end
                for _, id in ipairs(ns.QuestieDroppedBy(item) or {}) do mobs[id] = true end
                local n, sp, best = 0, 0, nil
                for id in pairs(mobs) do
                    n = n + 1
                    sp = sp + spawns(id)
                    local c = ns.Chance(id, item)
                    if c and c > 0 and (not best or c > best) then best = c end
                end
                if n > 0 then
                    local _, _, listed = ScannerKing.GetMarketPrice(item)
                    table.insert(out, { id = item, name = info.name, price = price, listed = listed, mobs = n,
                        spawns = sp, chance = best, raw = price * math.sqrt(math.max(sp, 1)) })
                end
            end
        end
    end
    local top = 0
    for _, e in ipairs(out) do top = math.max(top, e.raw) end
    for _, e in ipairs(out) do e.score = top > 0 and math.floor(e.raw / top * 100 + 0.5) or 0 end
    return out, priced, loading
end

local function build()
    local priced, loading
    list, priced, loading = ns.WhiteItems()
    table.sort(list, function(a, b)
        local x, y = a[sortBy], b[sortBy]
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end
            return a.name < b.name
        end
        if x == y then return a.raw > b.raw end
        if sortDesc then return x > y end
        return x < y
    end)
    return priced, loading
end

local function grey(t) return "|cff808080" .. t .. "|r" end

local function cellText(e, key)
    if key == "name" then return ns.ItemText(e.id) end
    if key == "price" then return ns.Money(e.price) end
    if key == "listed" then return e.listed and tostring(e.listed) or grey("-") end
    if key == "mobs" then return tostring(e.mobs) end
    if key == "spawns" then return e.spawns > 0 and tostring(e.spawns) or grey("-") end
    if key == "chance" then
        if not e.chance then return grey("-") end
        local pct = e.chance * 100
        return pct >= 10 and string.format("%.0f%%", pct) or string.format("%.1f%%", pct)
    end
    if key == "score" then return "|cffffd100" .. e.score .. "|r" end
    return ""
end

function ns.RefreshWhite()
    if not pane or not pane:IsShown() then return end
    local priced, loading = build()
    offset = math.max(0, math.min(offset, #list - ROWS))
    for i = 1, ROWS do
        local r, e = rows[i], list[i + offset]
        if e then
            r.id = e.id
            r.icon:SetTexture(ns.Item(e.id).icon)
            for c, col in ipairs(COLS) do r.cells[c]:SetText(cellText(e, col.key)) end
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    for _, h in ipairs(headers) do h:SetText(h.label .. (sortBy == h.key and (sortDesc and " v" or " ^") or "")) end

    local text
    if not (ScannerKing and ScannerKing.GetAllPrices) then
        text = "Needs Scanner King's prices."
    elseif #list == 0 then
        text = priced == 0 and "No white items priced yet. Run a Deep Scan at the auction house (Scanner King) to price every item."
            or "None of the priced white items has a known dropper yet."
                .. (ns.QuestieAvailable() and "" or " QuestieDB adds every mob's drops.")
    end
    empty:SetText(text or "")
    local building, progress = ns.QuestieBuilding()
    footer:SetText((#list > 0 and ((offset + 1) .. "-" .. (offset + math.min(#list, ROWS)) .. " of " .. #list
        .. " white items mobs drop.  ") or "")
        .. (loading > 0 and ("Loading " .. loading .. " items.  ") or "")
        .. (building and ("|cffffd100QuestieDB: " .. progress .. "|r  ") or "")
        .. "Score: price x square root of spawn points, best = 100.")
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

function ns.CreateWhiteView(parent)
    pane = CreateFrame("Frame", nil, parent)
    pane:SetPoint("TOPLEFT", 16, -44)
    pane:SetPoint("BOTTOMRIGHT", -14, 14)
    pane:Hide()

    headers = {}
    local x = 20
    for i, col in ipairs(COLS) do
        local h = CreateFrame("Button", nil, pane)
        h:SetHeight(18)
        h:SetWidth(col.w)
        h:SetPoint("TOPLEFT", x, 0)
        h:SetNormalFontObject("GameFontNormalSmall")
        h.key, h.label, h.tip = col.key, col.label, col.tip
        h:SetText(col.label)
        local fs = h:GetFontString()
        if fs then fs:ClearAllPoints(); fs:SetPoint(col.justify, col.justify == "RIGHT" and -6 or 0, 0) end
        h:SetScript("OnClick", function(self)
            if sortBy == self.key then sortDesc = not sortDesc
            else sortBy, sortDesc = self.key, self.key ~= "name" end
            offset = 0
            ns.RefreshWhite()
        end)
        h:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        headers[i] = h
        x = x + col.w
    end

    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, pane)
        r:SetSize(x, ROW_H)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 0, 0)
        r.cells = {}
        local cx = 20
        for c, col in ipairs(COLS) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.w - 6)
            fs:SetJustifyH(col.justify)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            r.cells[c] = fs
            cx = cx + col.w
        end
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:AddLine("Click: every mob that drops it.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            if self.id then ns.SetPage("mobs"); ns.HuntItem(self.id) end
        end)
        rows[i] = r
    end
    empty = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -80)
    empty:SetWidth(600)
    footer = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 0, 2)
    footer:SetJustifyH("LEFT")
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 5)
        ns.RefreshWhite()
    end)
    return pane
end
