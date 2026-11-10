local _, KM = ...
local ns = KM.Module("Farm")
local UI = KM.UI
local C = UI.C

-- White Items: its own page of the King Maker window (Farming > White Items). Every white (common)
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
-- Click an item for every mob that drops it (Mob Farming's item hunt); click
-- a mob there for its page.

local page, tbl, footer
local list = {}
local sortBy, sortDesc = "score", true

local COLS = {
    { key = "name", label = "White item", w = 220, desc = false },
    { key = "price", label = "Price", w = 96, justify = "RIGHT", tip = "What one sells for at the auction house, after its 5% cut (Scanner King's market price)." },
    { key = "listed", label = "Listed", w = 64, justify = "RIGHT", tip = "How many are on the auction house: lots listed means lots of competition." },
    { key = "mobs", label = "Mobs", w = 56, justify = "RIGHT", tip = "How many different mobs are known to drop it." },
    { key = "spawns", label = "Spawns", w = 64, justify = "RIGHT", tip = "Spawn points of all those mobs together: how much there is to farm." },
    { key = "chance", label = "Best chance", w = 84, justify = "RIGHT", tip = "The best drop chance from the mobs you or your guild have killed." },
    { key = "score", label = "Score", w = 0, justify = "RIGHT", tip = "Price times the square root of spawn points; the best item is 100." },
}
for _, col in ipairs(COLS) do col.sort = true end

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

local function fillRow(r, e, cells)
    r.item = e.id
    if r.icon then r.icon:SetTexture(ns.Item(e.id).icon) end
    for _, col in ipairs(COLS) do cells[col.key]:SetText(cellText(e, col.key)) end
end

local state = { priced = 0, loading = 0 }

local function footerText()
    local building, progress = ns.QuestieBuilding()
    local shown = math.min(#list, tbl.visible or #list)
    footer:SetText((#list > 0 and ((tbl.offset + 1) .. "-" .. (tbl.offset + shown) .. " of " .. #list
        .. " white items mobs drop.  ") or "")
        .. (state.loading > 0 and ("Loading " .. state.loading .. " items.  ") or "")
        .. (building and ("|cffffd100QuestieDB: " .. progress .. "|r  ") or "")
        .. "Score: price x square root of spawn points, best = 100.")
end

function ns.RefreshWhite()
    if not page or not ns.db then return end
    if ns.EnsureQuestie then ns.EnsureQuestie() end
    state.priced, state.loading = build()
    local text
    if not (ScannerKing and ScannerKing.GetAllPrices) then
        text = "Needs Scanner King's prices."
    elseif state.priced == 0 then
        text = "No white items priced yet. Run a Deep Scan at the auction house to price every item."
    else
        text = "None of the priced white items has a known dropper yet."
            .. (ns.QuestieAvailable() and "" or " QuestieDB adds every mob's drops.")
    end
    tbl.emptyText = text
    tbl:SetSort(sortBy, sortDesc)
    tbl:SetRows(list, fillRow)
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function buildPage(c)
    page = c
    tbl = UI.Table(c, COLS, 20, {
        icon = true, noSort = true,
        onSort = function(key, desc) sortBy, sortDesc = key, desc; tbl.offset = 0; ns.RefreshWhite() end,
        onClick = function(e)
            KM.Show("mobs")
            ns.HuntItem(e.id)
        end,
        onEnter = function(r)
            if not r.data then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, r.data.id) end
            GameTooltip:AddLine("Click: every mob that drops it.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, 0)
    tbl:SetPoint("BOTTOMRIGHT", 0, 22)
    tbl.fill = fillRow
    tbl.onRedraw = footerText
    ns.whiteTable = tbl
    footer = UI.Text(c, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", c, "RIGHT", 0, 0)
end

function ns.WhiteList() return list end

KM.RegisterPage({
    id = "whites", group = "farm", label = "White Items", icon = "Interface\\Icons\\INV_Fabric_Linen_01", order = 11,
    title = "White Items",
    subtitle = "White drops worth hunting: auction price against how many mobs drop them. A Deep Scan prices them all.",
    build = buildPage, refresh = function() ns.RefreshWhite() end,
})
