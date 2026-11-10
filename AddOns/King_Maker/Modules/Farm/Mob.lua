local _, KM = ...
local ns = KM.Module("Farm")
local UI = KM.UI
local C = UI.C

-- A mob's page, drawn inside the Mob Farming page where the list was: level, rank, zone and where it spawns;
-- what a kill is worth with the filters at the top (three tiles); and its loot table: each drop's chance, how
-- many come at once, its price and what it adds per kill. Drops QuestieDB lists that nobody has seen yet are at
-- the bottom. Favorite, Track on map and Ask guild sit top right. Back returns to the list; the arrows step
-- through it.

local view, back, prevBtn, nextBtn, pos, name, about, star, trackCheck, tiles, note, spawnText, loot
local current, index
local value

local function pct(x)
    if not x then return "|cff808080-|r" end
    if x >= 0.1 then return string.format("%.0f%%", x * 100) end
    if x >= 0.01 then return string.format("%.1f%%", x * 100) end
    return string.format("%.2f%%", x * 100)
end

local COLS = {
    { key = "item", label = "Drop", w = 200 },
    { key = "chance", label = "Chance", w = 64, justify = "RIGHT" },
    { key = "avg", label = "Per drop", w = 64, justify = "RIGHT" },
    { key = "unit", label = "Price", w = 100, justify = "RIGHT" },
    { key = "perKill", label = "Per kill", w = 100, justify = "RIGHT" },
    { key = "from", label = "", w = 0 },
}

local function fillRow(r, row, cells)
    r.item = row.item
    if r.icon then r.icon:SetTexture(ns.Item(row.item).icon) end
    cells.item:SetText(ns.ItemText(row.item))
    cells.chance:SetText(row.possible and "|cff808080not seen|r" or pct(row.chance))
    cells.avg:SetText(row.avg and (row.avg >= 1.05 and string.format("%.1f", row.avg) or "1") or "")
    cells.unit:SetText(row.unit and ns.Money(row.unit) or "|cff808080loading|r")
    cells.perKill:SetText(row.perKill and ns.Money(row.perKill) or "")
    cells.from:SetText(row.from == "ah" and "|cffa0a0a0AH|r" or row.from == "vendor" and "|cffa0a0a0vendor|r"
        or row.from == "quest" and "|cffa0a0a0quest|r" or "")
    -- Drops left out by the filters, and ones nobody has seen yet, are dimmed.
    r:SetAlpha((row.possible or not row.included) and 0.45 or 1)
end

function ns.RefreshMob()
    if not current or not view:IsShown() then return end
    local id = current
    local info = ns.MobInfo(id)
    name:SetText(info.name .. (info.rank and (" |cffffd100(" .. info.rank .. ")|r") or ""))
    local bits = {}
    local lvl = ns.LevelText(info)
    if lvl ~= "" then table.insert(bits, "Level " .. lvl) end
    if info.type then table.insert(bits, info.type) end
    if info.map then table.insert(bits, ns.MapName(info.map)) end
    if info.sub and info.sub ~= "" then table.insert(bits, "<" .. info.sub .. ">") end
    about:SetText(table.concat(bits, "  -  "))
    star:SetActive(ns.db.fav[id] and true or false)
    trackCheck:SetChecked(ns.db.track[id] and true or false)

    local list = ns.CurrentList()
    if index and list[index] and list[index].id == id then
        pos:SetText(index .. " of " .. #list)
        prevBtn:SetEnabled2(index > 1)
        nextBtn:SetEnabled2(index < #list)
    else
        pos:SetText("")
        prevBtn:SetEnabled2(false)
        nextBtn:SetEnabled2(false)
    end

    value = ns.Value(id)
    local v = value
    local mine, others = v.mine, v.kills - v.mine
    tiles.gold:Set("Gold per kill", v.gold and ns.Money(v.gold) or "|cff808080-|r", v.kills > 0 and "coin and drops, with the filters" or "no kills yet", C.accent)
    tiles.coin:Set("Coin per kill", v.coin and ns.Money(v.coin) or "|cff808080-|r", "average coin looted")
    tiles.kills:Set("Kills recorded", tostring(v.kills), others > 0 and ("you " .. mine .. ", guild " .. others .. " from " .. v.mates) or "all yours")
    note:SetText(v.kills == 0 and "No kills recorded yet." or v.kills < ns.db.filter.minKills and "Few kills so far: rough numbers."
        or v.incomplete and "Some prices are still loading." or "")
    local spots, from = ns.Spots(id)
    spawnText:SetText(#spots > 0 and ((from == "QuestieDB" and (#spots .. " spawn points from QuestieDB.") or ("Seen at " .. #spots .. " spots.")))
        or "No spawn points known yet.")
    loot.emptyText = "No drops recorded yet. Kill and loot it, or Ask guild."
    loot:SetRows(v.rows, fillRow)
end

function ns.OpenMob(id, i)
    current, index = id, i
    loot.offset = 0
    view:Show()
    ns.RefreshMob()
end

function ns.HideMob() if view then view:Hide() end end
function ns.CurrentMob() return view and view:IsShown() and current or nil end

local function step(d)
    local list = ns.CurrentList()
    if not index or not list[index + d] then return end
    index = index + d
    current = list[index].id
    loot.offset = 0
    ns.RefreshMob()
end

function ns.CreateMobView(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    view:Hide()

    back = UI.Button(view, "< Back", 70, 22, function() ns.ShowList() end)
    back:SetPoint("TOPLEFT", 0, 0)
    prevBtn = UI.Button(view, "<", 26, 22, function() step(-1) end)
    prevBtn:SetPoint("LEFT", back, "RIGHT", 6, 0)
    nextBtn = UI.Button(view, ">", 26, 22, function() step(1) end)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    pos = UI.Text(view, 10, C.dim)
    pos:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)

    -- Top right: ask, track, favorite.
    local ask = UI.Button(view, "Ask guild", 90, 22, function() if current then ns.AskGuild({ current }) end end)
    ask:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(ask, "Ask guildmates for their kills of this mob.")
    trackCheck = UI.CheckLabel(view, "Track on map", function(v) if current then ns.SetTracked(current, v) end end,
        "Its spawn points as small dots on your world map (QuestieDB's, or the spots you've seen it).")
    trackCheck.frame:SetPoint("RIGHT", ask, "LEFT", -14, 0)
    star = UI.Button(view, "|T" .. ns.STAR .. ":13|t Favorite", 96, 22, function()
        if current then ns.db.fav[current] = (not ns.db.fav[current]) or nil; ns.RefreshMob() end
    end)
    star:SetPoint("RIGHT", trackCheck.frame, "LEFT", -14, 0)

    name = UI.Text(view, 16, C.text)
    name:SetPoint("TOPLEFT", 0, -34)
    about = UI.Text(view, 11, C.muted)
    about:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)

    -- What a kill is worth.
    tiles = {}
    for i, key in ipairs({ "gold", "coin", "kills" }) do
        local t = UI.Tile(view, 190, 58)
        t:SetPoint("TOPLEFT", (i - 1) * 200, -78)
        tiles[key] = t
    end
    note = UI.Text(view, 10, C.warn)
    note:SetPoint("TOPLEFT", 0, -144)
    spawnText = UI.Text(view, 10, C.muted, "RIGHT")
    spawnText:SetPoint("TOPRIGHT", 0, -144)

    -- The loot table.
    loot = UI.Table(view, COLS, 20, { icon = true, noSort = true })
    loot:SetPoint("TOPLEFT", 0, -162)
    loot:SetPoint("BOTTOMRIGHT", 0, 0)
    loot.fill = fillRow
end
