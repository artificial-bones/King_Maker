local _, KM = ...
local ns = KM.Module("Farm")
local UI = KM.UI
local C = UI.C

-- The Mob Farming page of the King Maker window (Farming > Mob Farming). White Items is its own page (White.lua).
--   Top:    what to price in (grey to epic drops, coin, guild data) and how many kills a mob needs before it's
--           ranked; then the search box (Mobs or Items), "near my level" and the farm tracker toggle.
--   Left:   Best farms, Favorites, Recent kills, Tracked, This zone, All mobs, then every zone.
--   Right:  the mobs, most gold per kill first. Click one for its page (Mob.lua), which takes the list's place.
--   Bottom: what's listed, whether QuestieDB was found, and Ask guild.
--
-- The search box looks for mobs, or (switched to Items) for items: pick an item and the list becomes every mob
-- that drops it, highest level first.
-- Also here: the crown's quick actions and tooltip line, the Home tile and the Settings section.

local SIDE_W, SIDE_H, SIDE_ROWS = 150, 22, 20
local TOP = -66                       -- where the sidebar and list start
local MIN_KILLS = { 1, 5, 10, 25, 50 }
local ITEM_RESULTS = 100
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
ns.STAR = STAR
local STAR_TEXT = "|T" .. STAR .. ":13|t"

local page, search, searchModeBtn, footer, listView, sideButtons, checks, minKillsBtn, askBtn, miniBtn
local tables = {}
local tab, sortBy, sortDesc, sideOffset = "best", "gold", true, 0
local list = {}
local view = "list"
local searchMode = "mobs"   -- what the search box looks for: "mobs" or "items"
local hunt                  -- itemID: the list shows every mob that drops it
local mode = "mobs"         -- what the list shows: "mobs", "items" (search results) or "hunt"

-- Column sets, one table each; the one for the current mode is shown.
local COLUMNS = {
    mobs = {
        { key = "fav", label = "", w = 22 },
        { key = "name", label = "Mob", w = 158, desc = false },
        { key = "level", label = "Level", w = 46 },
        { key = "zone", label = "Zone", w = 100, desc = false },
        { key = "gold", label = "Gold/kill", w = 84, justify = "RIGHT", tip = "Average value of a kill: coin plus each drop's chance times its price, with the filters above." },
        { key = "coin", label = "Coin", w = 64, justify = "RIGHT", tip = "Average coin a kill drops." },
        { key = "kills", label = "Kills", w = 46, justify = "RIGHT", tip = "Kills the numbers are based on: yours plus your guild's (when Guild data is on)." },
        { key = "best", label = "Best drop", w = 0, desc = false, tip = "The drop worth the most per kill." },
    },
    items = {
        { key = "name", label = "Item", w = 270, desc = false },
        { key = "mobs", label = "Dropped by", w = 90, justify = "RIGHT", tip = "How many mobs are known to drop it." },
        { key = "chance", label = "Best chance", w = 90, justify = "RIGHT", tip = "The best drop chance from the mobs you or your guild have killed." },
        { key = "price", label = "Price", w = 0, justify = "RIGHT" },
    },
    hunt = {
        { key = "fav", label = "", w = 22 },
        { key = "name", label = "Mob", w = 158, desc = false },
        { key = "level", label = "Level", w = 50 },
        { key = "zone", label = "Zone", w = 108, desc = false },
        { key = "spawns", label = "Spawns", w = 60, justify = "RIGHT", tip = "Spawn points (QuestieDB), or spots you've seen it." },
        { key = "chance", label = "Chance", w = 64, justify = "RIGHT", tip = "How often it dropped the item, from your kills and your guild's." },
        { key = "kills", label = "Kills", w = 50, justify = "RIGHT", tip = "Kills that chance is based on." },
        { key = "gold", label = "Gold/kill", w = 0, justify = "RIGHT", tip = "Average value of a kill, everything it drops included." },
    },
}
-- Every column sorts (the page sorts its own list: the table only shows the arrow and reports clicks).
for _, cols in pairs(COLUMNS) do for _, col in ipairs(cols) do col.sort = true end end

---------------------------------------------------------------------------
-- What's in each tab
---------------------------------------------------------------------------

local function currentMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function nearLevel(info)
    if not ns.db.filter.near or not info.lmin then return true end
    local lvl = UnitLevel("player") or 1
    return info.lmax >= lvl - 5 and info.lmin <= lvl + 3
end

-- npcID -> place under Recent kills (1 = the latest)
local function recentRanks()
    local r = {}
    for i, id in ipairs(ns.db.recent) do r[id] = i end
    return r
end
local recent = {}

local function inTab(id, info, value)
    if tab == "best" then return value.kills >= ns.db.filter.minKills end
    if tab == "fav" then return ns.db.fav[id] end
    if tab == "recent" then return recent[id] ~= nil end
    if tab == "track" then return ns.db.track[id] end
    if tab == "all" then return true end
    local map = tab == "zone" and currentMap() or tonumber(tostring(tab):match("^map:(%d+)$"))
    if not map then return false end
    local m = ns.db.mobs[id]
    return info.map == map or (m and m.z and m.z[map]) ~= nil
end

local function sortValue(e, key)
    if key == "name" then return e.name end
    if key == "level" then return e.info and e.info.lmax end
    if key == "zone" then return e.info and ns.MapName(e.info.map) end
    if key == "best" then return e.v and e.v.best and ns.Item(e.v.best).name end
    if key == "kills" then return mode == "hunt" and e.kills or (e.v and e.v.kills) end
    if key == "gold" or key == "coin" then return e.v and e.v[key] end
    if key == "recent" then return recent[e.id] end
    if key == "fav" then return ns.db.fav[e.id] and 1 or 0 end
    return e[key]
end

local function mobEntry(id)
    local info = ns.MobInfo(id)
    local kills = ns.Combined(id, ns.db.filter.guild)
    return { id = id, info = info, name = info.name, v = kills > 0 and ns.Value(id) or { kills = 0 } }
end

local function build()
    wipe(list)
    local text = (search and search:GetText() or ""):lower()
    if searchMode == "items" and text ~= "" then
        mode = "items"
        for _, r in ipairs(ns.SearchItems(text, ITEM_RESULTS)) do
            local n, best = 0, nil
            for id in pairs(ns.DroppedBy(r.item)) do
                n = n + 1
                local c = ns.Chance(id, r.item)
                if c and c > 0 and (not best or c > best) then best = c end
            end
            table.insert(list, { id = r.item, name = r.name, mobs = n, chance = best, price = (ns.ItemValue(r.item)) })
        end
    elseif hunt then
        mode = "hunt"
        for id in pairs(ns.DroppedBy(hunt)) do
            local e = mobEntry(id)
            e.chance, e.kills = ns.Chance(id, hunt)
            e.spawns = #(ns.Spots(id))
            if nearLevel(e.info) then table.insert(list, e) end
        end
    else
        mode = "mobs"
        recent = recentRanks()
        local all = ns.AllMobs()
        for id in pairs(recent) do all[id] = true end
        for id in pairs(all) do
            local e = mobEntry(id)
            local match
            if text ~= "" then
                match = e.name:lower():find(text, 1, true) ~= nil
            else
                match = inTab(id, e.info, e.v)
            end
            if match and (tab == "recent" or nearLevel(e.info)) then table.insert(list, e) end
        end
    end
    table.sort(list, function(a, b)
        local x, y = sortValue(a, sortBy), sortValue(b, sortBy)
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end
            return a.name < b.name
        end
        if x == y then return a.name < b.name end
        if sortDesc then return x > y end
        return x < y
    end)
end

function ns.CurrentList() return list end
function ns.CurrentMode() return mode end

---------------------------------------------------------------------------
-- Left side
---------------------------------------------------------------------------

local function sideEntries()
    local entries = {
        { key = "best", label = "Best farms" },
        { key = "fav", label = STAR_TEXT .. " Favorites" },
        { key = "recent", label = "Recent kills" },
        { key = "track", label = "Tracked on map" },
        { key = "zone", label = "This zone" },
        { key = "all", label = "All mobs" },
    }
    local count = {}
    for id in pairs(ns.AllMobs()) do
        local map = ns.MobInfo(id).map
        if map then count[map] = (count[map] or 0) + 1 end
    end
    local maps = {}
    for map in pairs(count) do if ns.MapName(map) ~= "" then table.insert(maps, map) end end
    table.sort(maps, function(a, b) return ns.MapName(a) < ns.MapName(b) end)
    for _, map in ipairs(maps) do
        table.insert(entries, { key = "map:" .. map, label = ns.MapName(map), count = count[map], zone = true })
    end
    return entries
end

local function refreshSide()
    local entries = sideEntries()
    sideOffset = math.max(0, math.min(sideOffset, #entries - SIDE_ROWS))
    for i, b in ipairs(sideButtons) do
        local e = entries[i + sideOffset]
        if e then
            b.entry = e
            b:SetLabel(e.label)
            b.count:SetText(e.count and tostring(e.count) or "")
            b:SetActive(e.key == tab and not hunt and (search:GetText() or "") == "")
            b:Show()
        else
            b.entry = nil
            b:Hide()
        end
    end
end

function ns.SelectTab(key)
    if not page then return end
    tab, hunt = key, nil
    search:SetText("")
    search:ClearFocus()
    if key == "best" then sortBy, sortDesc = "gold", true
    elseif key == "recent" then sortBy, sortDesc = "recent", false  -- the latest kill first
    elseif sortBy == "recent" then sortBy, sortDesc = "gold", true end
    ns.ShowList()
end

-- Every mob that drops this item, highest level first.
function ns.HuntItem(item)
    if not page then return end
    hunt = item
    sortBy, sortDesc = "level", true
    search:SetText("")
    search:ClearFocus()
    ns.ShowList()
end

function ns.API.ShowItem(item)
    if not ns.db or not tonumber(item) then return end
    ns.Toggle(true)
    ns.HuntItem(tonumber(item))
end

local function setSearchMode(m)
    searchMode = m
    searchModeBtn:SetLabel(m == "items" and "Items" or "Mobs")
    searchModeBtn:SetActive(m == "items")
    search.hint:SetText(m == "items" and "Search items (or shift-click a link)" or "Search mobs")
    if m == "items" then sortBy, sortDesc = "name", false
    elseif sortBy ~= "gold" and sortBy ~= "name" and sortBy ~= "level" then sortBy, sortDesc = "gold", true end
    ns.ShowList()
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function emptyText()
    if mode == "items" then return "No item by that name. Names come from QuestieDB and the drops you've seen." end
    if mode == "hunt" then return "No mob is known to drop this yet." end
    if (search:GetText() or "") ~= "" then return "No mob by that name yet." end
    if tab == "best" then
        return "No mob has " .. ns.db.filter.minKills .. "+ kills yet. Go kill things: every corpse you loot is recorded."
            .. "\nLower Min kills above, or Ask guild for their drop data."
    end
    if tab == "fav" then return "No favorites yet. Right-click a mob to make it one." end
    if tab == "recent" then return "No kills yet. The last " .. ns.RECENT .. " mobs you kill show here, the latest first." end
    if tab == "track" then return "Nothing tracked. Open a mob and tick Track on map." end
    return "No mobs here yet."
end

local function grey(text, on) return on and ("|cff909090" .. text .. "|r") or text end

local function cellText(e, key, minKills)
    local v, info = e.v, e.info
    if key == "fav" then return ns.db.fav[e.id] and STAR_TEXT or "" end
    if key == "name" then
        if mode == "items" then return ns.ItemText(e.id) end
        return info.name .. (info.rank and (" |cffffd100" .. info.rank .. "|r") or "")
    end
    if key == "level" then return ns.LevelText(info) end
    if key == "zone" then return ns.MapName(info.map) end
    local few = v and v.kills > 0 and v.kills < minKills
    if key == "gold" then return v.gold and grey(ns.Money(v.gold), few) or "|cff808080-|r" end
    if key == "coin" then return v.coin and ns.Money(v.coin) or "|cff808080-|r" end
    if key == "best" then return v.best and ns.ItemText(v.best) or "" end
    if key == "kills" then
        local k = mode == "hunt" and e.kills or v.kills
        return k and k > 0 and grey(tostring(k), k < minKills) or "|cff808080-|r"
    end
    if key == "mobs" then return tostring(e.mobs) end
    if key == "chance" then
        if not e.chance then return "|cff808080-|r" end
        local pct = e.chance * 100
        return grey(pct >= 10 and string.format("%.0f%%", pct) or string.format("%.1f%%", pct), mode == "hunt" and (e.kills or 0) < minKills)
    end
    if key == "price" then return e.price and ns.Money(e.price) or "|cff808080-|r" end
    if key == "spawns" then return e.spawns > 0 and tostring(e.spawns) or "|cff808080-|r" end
    return ""
end

local function fillRow(r, e, cells)
    local minKills = ns.db.filter.minKills
    if mode == "items" then
        r.item = e.id
        if r.icon then r.icon:SetTexture(ns.Item(e.id).icon) end
    end
    for _, col in ipairs(COLUMNS[mode]) do cells[col.key]:SetText(cellText(e, col.key, minKills)) end
end

local function huntSummary()
    local levels, spawns = {}, 0
    for _, e in ipairs(list) do
        if e.info.lmin then
            levels.lo = math.min(levels.lo or e.info.lmin, e.info.lmin)
            levels.hi = math.max(levels.hi or e.info.lmax, e.info.lmax)
        end
        spawns = spawns + (e.spawns or 0)
    end
    return ns.ItemText(hunt) .. ": dropped by " .. #list .. " mob" .. (#list == 1 and "" or "s")
        .. (levels.lo and (", levels " .. levels.lo .. "-" .. levels.hi) or "")
        .. (spawns > 0 and (", " .. spawns .. " spawn points") or "") .. "."
end

local function footerText()
    local tbl = tables[mode]
    local building, progress = ns.QuestieBuilding()
    local qdb = ns.QuestieReady() and "QuestieDB: every mob." or building and ("|cffffd100QuestieDB: " .. progress .. "|r")
        or ns.QuestieAvailable() and "QuestieDB found." or "No QuestieDB: mobs you've seen."
    if mode == "hunt" then
        footer:SetText(huntSummary() .. "  " .. qdb)
    else
        local shown = math.min(#list, tbl.visible or #list)
        footer:SetText((#list > 0 and ((tbl.offset + 1) .. "-" .. (tbl.offset + shown) .. " of " .. #list .. ".  ") or "") .. qdb)
    end
end

local function refreshList()
    build()
    for m, t in pairs(tables) do t:SetShown(m == mode) end
    local tbl = tables[mode]
    tbl:SetSort(sortBy, sortDesc)
    tbl.emptyText = emptyText()
    tbl:SetRows(list, fillRow)
    askBtn:SetShown(mode ~= "items")
end

-- The Questie indexes are read in the background the first time either page opens; keep the footer moving.
local watching = false
local function watchBuild()
    if ns.QuestieBuilding() then
        watching = true
        ns.Refresh()
        C_Timer.After(0.5, watchBuild)
    else
        watching = false
    end
end

function ns.EnsureQuestie()
    if ns.QuestieAvailable() and not ns.QuestieReady() then
        ns.BuildQuestie(ns.Refresh)
        if not watching then watchBuild() end
    end
end

local function refresh()
    if not ns.db or not page then return end
    ns.EnsureQuestie()
    for key, c in pairs(checks) do c:SetChecked(ns.db.filter[key] and true or false) end
    minKillsBtn:SetLabel("Min kills: " .. ns.db.filter.minKills)
    miniBtn:SetActive(ns.db.ui.mini and true or false)
    refreshSide()
    if view == "list" then refreshList() elseif ns.RefreshMob then ns.RefreshMob() end
end

function ns.Refresh()
    KM.Refresh("mobs")
    KM.Refresh("whites")
end

function ns.ShowList()
    if not page then return end
    view = "list"
    if ns.HideMob then ns.HideMob() end
    listView:Show()
    if KM.IsShown("mobs") then KM.Refresh("mobs") else refresh() end
end

function ns.ShowMob(id, index)
    if not page then return end
    view = "mob"
    listView:Hide()
    ns.OpenMob(id, index)
    if KM.IsShown("mobs") then KM.Refresh("mobs") else refreshSide() end
end

-- Asks guildmates for their drop data on these mobs.
function ns.AskGuild(ids)
    local n, msgs = ns.API.RequestDrops(ids)
    if not n then return end
    if n == 0 then KM.Print(ns, "Nothing to ask about.") return end
    KM.Print(ns, "Asked the guild about " .. n .. " mob(s) in " .. msgs .. " message(s). Answers arrive over the next minute or so.")
end

local function indexOf(e)
    for i, x in ipairs(list) do if x == e then return i end end
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function makeTable(m)
    local t = UI.Table(listView, COLUMNS[m], 20, {
        icon = m == "items", noSort = true,
        onSort = function(key, desc) sortBy, sortDesc = key, desc; refresh() end,
        onClick = function(e, which)
            if mode == "items" then
                ns.HuntItem(e.id)
            elseif which == "RightButton" then
                ns.db.fav[e.id] = (not ns.db.fav[e.id]) or nil
                refresh()
            else
                ns.ShowMob(e.id, indexOf(e))
            end
        end,
        onEnter = function(r)
            if not r.data then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            if mode == "items" then
                if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, r.data.id) end
                GameTooltip:AddLine("Click: every mob that drops it.", 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(r.data.name)
                GameTooltip:AddLine("Click: its page and loot table.  Right-click: favorite.", 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end,
    })
    t:SetPoint("TOPLEFT")
    t:SetPoint("BOTTOMRIGHT")
    t.fill = fillRow
    t.onRedraw = footerText
    t:Hide()
    return t
end

local function cycleMinKills()
    local nextValue = MIN_KILLS[1]
    for i, v in ipairs(MIN_KILLS) do
        if v == ns.db.filter.minKills then nextValue = MIN_KILLS[i % #MIN_KILLS + 1] end
    end
    ns.db.filter.minKills = nextValue
    refresh()
end

local function buildPage(c)
    page = c
    checks = {}

    -- Row 1: what to price in, and the ranking threshold.
    local priceLabel = UI.Text(c, 9, C.muted)
    priceLabel:SetPoint("TOPLEFT", 0, -7)
    priceLabel:SetText("PRICE IN")
    local x = 52
    for _, q in ipairs({ { "q0", "|cff9d9d9dGrey|r", "Grey (junk) drops, at their vendor price." },
                         { "q1", "White", "White drops: cloth, leather, meat and the like." },
                         { "q2", "|cff1eff00Green|r", "Uncommon drops." },
                         { "q3", "|cff0070ddBlue|r", "Rare drops." },
                         { "q4", "|cffa335eeEpic|r", "Epic and better." },
                         { "coin", "Coin", "The coin mobs drop." },
                         { "guild", "Guild data", "Add your guildmates' kills to yours (after they answer an Ask guild)." } }) do
        local key = q[1]
        local cb = UI.CheckLabel(c, q[2], function(v) ns.db.filter[key] = v and true or false; refresh() end, q[3])
        cb.frame:SetPoint("TOPLEFT", x, -3)
        cb.key = key
        checks[key] = cb
        x = x + (cb.frame:GetWidth() or 60) + 12
    end
    minKillsBtn = UI.Button(c, "Min kills: 5", 110, 24, cycleMinKills)
    minKillsBtn:SetPoint("TOPRIGHT", 0, 0)
    UI.Tip(minKillsBtn, "How many kills a mob needs before it's ranked under Best farms (click to cycle 1, 5, 10, 25, 50). "
        .. "Fewer kills means rougher numbers; they show in grey everywhere.")

    -- Row 2: search (mobs or items), near my level, the farm tracker.
    search = UI.EditBox(c, 230, 24, "Search mobs", function(text, user)
        if not user then return end
        -- A shift-clicked item link goes straight to the mobs that drop it.
        local item = tonumber((text or ""):match("item:(%d+)"))
        if item then return ns.HuntItem(item) end
        hunt = nil
        for _, t in pairs(tables) do t.offset = 0 end
        if view ~= "list" then ns.ShowList() else refresh() end
    end)
    search:SetPoint("TOPLEFT", 0, -32)
    searchModeBtn = UI.Button(c, "Mobs", 70, 24, function() setSearchMode(searchMode == "mobs" and "items" or "mobs") end)
    searchModeBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    UI.Tip(searchModeBtn, "Search for mobs, or for items. Items: pick one and see every mob that drops it, highest level "
        .. "first, with spawn points and drop chances. You can also shift-click an item link into the box.")
    local near = UI.CheckLabel(c, "Near my level", function(v) ns.db.filter.near = v and true or false; refresh() end,
        "Only mobs from 5 levels under you to 3 over.")
    near.frame:SetPoint("LEFT", searchModeBtn, "RIGHT", 14, 0)
    checks.near = near
    miniBtn = UI.Button(c, "Farm tracker", 110, 24, function() ns.SetMini(not ns.db.ui.mini) end)
    miniBtn:SetPoint("TOPRIGHT", 0, -32)
    UI.Tip(miniBtn, "A small floating box that tallies what you're farming: each mob killed and what it brought in, "
        .. "each drop and its value, and the total. Start its timer for gold per hour. Also /fk mini.")

    -- Left: tabs and zones.
    local side = CreateFrame("Frame", nil, c)
    side:SetPoint("TOPLEFT", 0, TOP)
    side:SetPoint("BOTTOMLEFT", 0, 26)
    side:SetWidth(SIDE_W)
    UI.Fill(side, { 0, 0, 0, 0.18 })
    UI.Border(side)
    sideButtons = {}
    for i = 1, SIDE_ROWS do
        local b = UI.Button(side, "", SIDE_W - 12, SIDE_H - 2, function(self)
            if self.entry then ns.SelectTab(self.entry.key) end
        end, "ghost")
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * SIDE_H)
        b.label:SetJustifyH("LEFT")
        b:SetPadding(8, 30)
        b.count = UI.Text(b, 10, C.dim, "RIGHT")
        b.count:SetPoint("RIGHT", -6, 0)
        sideButtons[i] = b
    end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        sideOffset = math.max(0, sideOffset - delta * 3)
        refreshSide()
    end)

    -- Right: the list, or a mob's page in its place.
    listView = CreateFrame("Frame", nil, c)
    listView:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    listView:SetPoint("BOTTOMRIGHT", 0, 26)
    for m in pairs(COLUMNS) do tables[m] = makeTable(m) end
    ns.tables = tables

    local mobArea = CreateFrame("Frame", nil, c)
    mobArea:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    mobArea:SetPoint("BOTTOMRIGHT", 0, 26)
    ns.CreateMobView(mobArea)

    footer = UI.Text(c, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 12, -18)
    footer:SetPoint("RIGHT", c, "RIGHT", -110, 0)

    askBtn = UI.Button(c, "Ask guild", 100, 22, function()
        local ids = {}
        for _, e in ipairs(list) do table.insert(ids, e.id) end
        ns.AskGuild(ids)
    end)
    askBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.Tip(askBtn, function(tt)
        tt:AddLine("Ask guild")
        tt:AddLine("Ask guildmates running King Maker (or Farm King) for their drop data on the " .. #list .. " mob(s) in this list"
            .. (#list > 500 and " (the first 500)" or "") .. ". Their kills add to yours when Guild data is ticked.", 1, 1, 1, true)
    end)
end

function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("mobs") end
    if show then KM.Show("mobs") elseif KM.IsShown("mobs") then KM.Toggle(false) end
end

function ns.MobsPage() return page end

KM.RegisterPage({
    id = "mobs", group = "farm", label = "Mob Farming", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", order = 10,
    title = "Mob Farming",
    subtitle = function()
        if view == "mob" then return "A mob's loot table: each drop's chance, price and what it adds per kill." end
        return "Every mob, ranked by the gold a kill is worth: coin plus each drop's chance times its price."
    end,
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

local function totalKills()
    local kills = 0
    for _, m in pairs(ns.db.mobs) do kills = kills + (m.k or 0) end
    return kills
end

KM.RegisterQuickAction({ id = "farm-mobs", label = "Mob Farming", order = 40, func = function() ns.Toggle(true) end })
KM.RegisterQuickAction({ id = "farm-zone", label = "This zone's mobs", order = 41,
    func = function() ns.Toggle(true); ns.SelectTab("zone") end })
KM.RegisterQuickAction({ id = "farm-tracker", label = "Farm tracker", order = 42,
    func = function() ns.SetMini(not ns.db.ui.mini) end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    tt:AddLine(KM.Commas(totalKills()) .. " kills recorded.", 1, 1, 1)
end)

KM.RegisterHomeTile({ id = "farm", order = 40, get = function()
    if not (ns.db and ns.SessionTotals) then return nil end
    local s = ns.db.session
    local kills = 0
    for _, m in pairs(s.mobs or {}) do kills = kills + (m.k or 0) end
    local total, gph, secs = ns.SessionTotals()
    if kills == 0 and (total or 0) == 0 and secs < 1 then return nil end
    if gph then
        return "Farm session", ns.Money(gph) .. "/hr", kills .. " kills, " .. ns.Money(total) .. " in all"
    end
    return "Farm session", kills .. " kills", ns.Money(total) .. " looted"
end })

KM.RegisterSettings({ id = "farm", label = "Farm", order = 40, rows = {
    { type = "header", label = "Guild" },
    { type = "check", label = "Answer guildmates' requests for my drop data",
      tip = "When a guildmate clicks Ask guild, send them your own kills of those mobs. Only your own kills are ever sent.",
      get = function() return ns.db.answer end, set = function(v) ns.db.answer = v end },
    { type = "check", label = "Add guildmates' kills to mine (Guild data)",
      get = function() return ns.db.filter.guild end, set = function(v) ns.db.filter.guild = v; ns.Refresh() end },
    { type = "button", label = "Forget every guildmate's drop data", func = function() ns.ForgetGuild() end },
    { type = "header", label = "Ranking" },
    { type = "choice", label = "Min kills for Best farms", options = { { 1, "1" }, { 5, "5" }, { 10, "10" }, { 25, "25" }, { 50, "50" } },
      get = function() return ns.db.filter.minKills end, set = function(v) ns.db.filter.minKills = v; ns.Refresh() end },
    { type = "check", label = "Only mobs near my level", tip = "From 5 levels under you to 3 over.",
      get = function() return ns.db.filter.near end, set = function(v) ns.db.filter.near = v; ns.Refresh() end },
    { type = "header", label = "Farm tracker" },
    { type = "check", label = "Show the farm tracker", tip = "The small floating box with this session's kills, drops and gold per hour.",
      get = function() return ns.db.ui.mini end, set = function(v) ns.SetMini(v) end },
    { type = "button", label = "Reset the farm tracker", func = function() ns.SessionReset() end },
    { type = "header", label = "Commands" },
    { type = "text", label = "/fk   open Mob Farming\n/fk white   White Items\n/fk mini on|off   the farm tracker\n"
        .. "/fk share on|off   answer guildmates' requests\n/fk forget guild   drop guildmates' data\n/fk status   what's been recorded" },
} })
