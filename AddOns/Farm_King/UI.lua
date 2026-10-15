local _, ns = ...

-- The Farm King window. Two tabs at the top: Mob Farming (all of the below) and
-- White Items (White.lua: white drops worth hunting).
--   Top:   what to price in (grey to epic drops, coin, guild data), how many
--          kills a mob needs before it's ranked, and "near my level".
--   Left:  Best farms, Favorites, Recent kills, Tracked, This zone, All mobs,
--          then every zone.
--   Right: the mobs, most gold per kill first. Click one for its page (Mob.lua).
--
-- The search box looks for mobs, or (switched to Items) for items: pick an
-- item and the list becomes every mob that drops it, highest level first.

local WIDTH, HEIGHT = 880, 590
local SIDE_W, SIDE_ROWS, SIDE_H = 150, 23, 20
local ROWS, ROW_H = 22, 18
local TOP = -70                       -- where the sidebar and list start
local MIN_KILLS = { 1, 5, 10, 25, 50 }
local ITEM_RESULTS = 100
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
ns.STAR = STAR

local frame, search, searchModeBtn, footer, listView, sideButtons, rows, headers, checks, minKillsBtn, askBtn, miniBtn
local page = "mobs"          -- the tab at the top: "mobs" or "white"
local pageTabs, mobWidgets, whitePane
local tab, sortBy, sortDesc, offset, sideOffset = "best", "gold", true, 0, 0
local list = {}
local view = "list"
local searchMode = "mobs"   -- what the search box looks for: "mobs" or "items"
local hunt                  -- itemID: the list shows every mob that drops it
local mode = "mobs"         -- what the list shows: "mobs", "items" (search results) or "hunt"
local laidOut

-- Column sets. Cells and headers are laid out again when the list changes what it shows.
local COLUMNS = {
    mobs = {
        { key = "fav", label = "", w = 20 },
        { key = "name", label = "Mob", w = 172, justify = "LEFT" },
        { key = "level", label = "Level", w = 46, justify = "LEFT" },
        { key = "zone", label = "Zone", w = 112, justify = "LEFT" },
        { key = "gold", label = "Gold/kill", w = 90, justify = "RIGHT", tip = "Average value of a kill: coin plus each drop's chance times its price, with the filters above." },
        { key = "coin", label = "Coin", w = 68, justify = "RIGHT", tip = "Average coin a kill drops." },
        { key = "best", label = "Best drop", w = 128, justify = "LEFT", tip = "The drop worth the most per kill." },
        { key = "kills", label = "Kills", w = 48, justify = "RIGHT", tip = "Kills the numbers are based on: yours plus your guild's (when Guild data is on)." },
    },
    items = {
        { key = "fav", label = "", w = 20 },
        { key = "name", label = "Item", w = 280, justify = "LEFT" },
        { key = "mobs", label = "Dropped by", w = 90, justify = "RIGHT", tip = "How many mobs are known to drop it." },
        { key = "chance", label = "Best chance", w = 90, justify = "RIGHT", tip = "The best drop chance from the mobs you or your guild have killed." },
        { key = "price", label = "Price", w = 110, justify = "RIGHT" },
    },
    hunt = {
        { key = "fav", label = "", w = 20 },
        { key = "name", label = "Mob", w = 172, justify = "LEFT" },
        { key = "level", label = "Level", w = 50, justify = "LEFT" },
        { key = "zone", label = "Zone", w = 120, justify = "LEFT" },
        { key = "spawns", label = "Spawns", w = 60, justify = "RIGHT", tip = "Spawn points (QuestieDB), or spots you've seen it." },
        { key = "chance", label = "Chance", w = 70, justify = "RIGHT", tip = "How often it dropped the item, from your kills and your guild's." },
        { key = "kills", label = "Kills", w = 50, justify = "RIGHT", tip = "Kills that chance is based on." },
        { key = "gold", label = "Gold/kill", w = 90, justify = "RIGHT", tip = "Average value of a kill, everything it drops included." },
    },
}
local MAX_CELLS = 8

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
    if key == "kills" then return e.v and e.v.kills end
    if key == "gold" or key == "coin" then return e.v and e.v[key] end
    if key == "recent" then return recent[e.id] end
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

---------------------------------------------------------------------------
-- Left side
---------------------------------------------------------------------------

local function sideEntries()
    local entries = {
        { key = "best", label = "Best farms" },
        { key = "fav", label = "|T" .. STAR .. ":14|t Favorites" },
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
        table.insert(entries, { key = "map:" .. map, label = ns.MapName(map), count = count[map] })
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
            b:SetText(e.label)
            b.count:SetText(e.count and tostring(e.count) or "")
            local on = e.key == tab and not hunt and (search:GetText() or "") == ""
            if on then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
        else
            b.entry = nil
            b:Hide()
        end
    end
end

function ns.SelectTab(key)
    tab, offset, hunt = key, 0, nil
    search:SetText("")
    search:ClearFocus()
    if key == "best" then sortBy, sortDesc = "gold", true
    elseif key == "recent" then sortBy, sortDesc = "recent", false  -- the latest kill first
    elseif sortBy == "recent" then sortBy, sortDesc = "gold", true end
    ns.ShowList()
end

-- Every mob that drops this item, highest level first.
function ns.HuntItem(item)
    hunt, offset = item, 0
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
    searchModeBtn:SetText(m == "items" and "Items" or "Mobs")
    offset = 0
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
    if tab == "fav" then return "No favorites yet. Click the star next to a mob." end
    if tab == "recent" then return "No kills yet. The last " .. ns.RECENT .. " mobs you kill show here, the latest first." end
    if tab == "track" then return "Nothing tracked. Open a mob and tick Track on map." end
    return "No mobs here yet."
end

-- Puts the headers and cells where this mode's columns go.
local function layout()
    if laidOut == mode then return end
    laidOut = mode
    local cols = COLUMNS[mode]
    for _, h in ipairs(headers) do h:Hide() end
    local x, n = 0, 0
    for _, col in ipairs(cols) do
        if col.key ~= "fav" then
            n = n + 1
            local h = headers[n]
            h.key, h.label, h.tip = col.key, col.label, col.tip
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", x + (mode == "items" and col.key == "name" and 0 or 0), 0)
            h:SetWidth(col.w)
            local fs = h:GetFontString()
            if fs then fs:ClearAllPoints(); fs:SetPoint(col.justify, col.justify == "RIGHT" and -6 or 0, 0) end
            h:Show()
            for _, r in ipairs(rows) do
                local c = r.cells[n]
                local inset = (col.key == "name" and mode == "items") and 20 or 0
                c:ClearAllPoints()
                c:SetPoint("LEFT", x + inset, 0)
                c:SetWidth(col.w - 6 - inset)
                c:SetJustifyH(col.justify)
            end
        end
        x = x + col.w
    end
    for _, r in ipairs(rows) do
        for i = n + 1, MAX_CELLS do r.cells[i]:SetText("") end
        r.columns = n
    end
end

local function grey(text, on) return on and ("|cff909090" .. text .. "|r") or text end

local function cellText(e, key, minKills)
    local v, info = e.v, e.info
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

local function refreshList()
    build()
    layout()
    offset = math.max(0, math.min(offset, #list - ROWS))
    local minKills = ns.db.filter.minKills
    local cols = COLUMNS[mode]
    for i = 1, ROWS do
        local r, e = rows[i], list[i + offset]
        if e then
            r.id = e.id
            r.isItem = mode == "items"
            r.star:SetShown(mode ~= "items")
            r.star:SetAlpha(ns.db.fav[e.id] and 1 or 0.15)
            r.icon:SetShown(mode == "items")
            if mode == "items" then r.icon:SetTexture(ns.Item(e.id).icon) end
            local n = 0
            for _, col in ipairs(cols) do
                if col.key ~= "fav" then
                    n = n + 1
                    r.cells[n]:SetText(cellText(e, col.key, minKills))
                end
            end
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    listView.empty:SetText(#list == 0 and emptyText() or "")
    for _, h in ipairs(headers) do
        if h.key then h:SetText(h.label .. (sortBy == h.key and (sortDesc and " v" or " ^") or "")) end
    end
    askBtn:SetShown(mode ~= "items")
    local building, progress = ns.QuestieBuilding()
    local shownN = math.min(#list, ROWS)
    local qdb = ns.QuestieReady() and "QuestieDB: every mob." or building and ("|cffffd100QuestieDB: " .. progress .. "|r")
        or ns.QuestieAvailable() and "QuestieDB found." or "No QuestieDB: mobs you've seen."
    if mode == "hunt" then
        footer:SetText(huntSummary() .. "  " .. qdb)
    else
        footer:SetText((#list > 0 and ((offset + 1) .. "-" .. (offset + shownN) .. " of " .. #list .. ".  ") or "") .. qdb)
    end
end

function ns.Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    if ns.db.ui.mini then miniBtn:LockHighlight() else miniBtn:UnlockHighlight() end
    for key, b in pairs(pageTabs) do if key == page then b:LockHighlight() else b:UnlockHighlight() end end
    if page == "white" then return ns.RefreshWhite() end
    for key, c in pairs(checks) do c:SetChecked(ns.db.filter[key] and true or false) end
    minKillsBtn:SetText("Min kills: " .. ns.db.filter.minKills)
    refreshSide()
    if view == "list" then refreshList() elseif ns.RefreshMob then ns.RefreshMob() end
end

local function showPage(p)
    page = p
    for _, w in ipairs(mobWidgets) do w:SetShown(p == "mobs") end
    whitePane:SetShown(p == "white")
    if p == "mobs" then listView:SetShown(view == "list") end
end

-- Switches the tab at the top.
function ns.SetPage(p)
    showPage(p)
    ns.Refresh()
end

function ns.ShowList()
    view = "list"
    if page ~= "mobs" then showPage("mobs") end
    if ns.HideMob then ns.HideMob() end
    listView:Show()
    ns.Refresh()
end

function ns.ShowMob(id, index)
    if not frame then return end
    view = "mob"
    if page ~= "mobs" then showPage("mobs") end
    listView:Hide()
    ns.OpenMob(id, index)
    refreshSide()
end

-- Asks guildmates for their drop data on these mobs.
function ns.AskGuild(ids)
    local n, msgs = ns.API.RequestDrops(ids)
    if not n then return end
    if n == 0 then ns.Print("Nothing to ask about.") return end
    ns.Print("Asked the guild about " .. n .. " mob(s) in " .. msgs .. " message(s). Answers arrive over the next minute or so.")
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function header(i)
    local h = CreateFrame("Button", nil, listView)
    h:SetHeight(18)
    h:SetNormalFontObject("GameFontNormalSmall")
    h:SetText("")
    h:SetScript("OnClick", function(self)
        local key = self.key
        if sortBy == key then sortDesc = not sortDesc
        else sortBy, sortDesc = key, key ~= "name" and key ~= "zone" end
        offset = 0
        ns.Refresh()
    end)
    h:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    headers[i] = h
end

local function check(key, label, x, tip)
    local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c:SetPoint("TOPLEFT", x, -40)
    c.key = key
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", c, "RIGHT", 0, 1)
    fs:SetText(label)
    c.label = fs
    c:SetScript("OnClick", function(self)
        ns.db.filter[self.key] = self:GetChecked() and true or false
        ns.Refresh()
    end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    checks[key] = c
    return c
end

local function create()
    frame = CreateFrame("Frame", "FarmKingFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "FarmKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Farm King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- The tabs at the top
    pageTabs = {}
    local prevTab = title
    for _, t in ipairs({ { "mobs", "Mob Farming", 96, "Every mob, ranked by gold per kill." },
                         { "white", "White Items", 100, "White items worth hunting: auction price against how many mobs drop them." } }) do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(t[3], 20)
        b:SetPoint("LEFT", prevTab, "RIGHT", prevTab == title and 14 or 2, 0)
        b:SetText(t[2])
        b:SetScript("OnClick", function() ns.SetPage(t[1]) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(t[2])
            GameTooltip:AddLine(t[4], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pageTabs[t[1]] = b
        prevTab = b
    end

    miniBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    miniBtn:SetSize(96, 20)
    miniBtn:SetPoint("LEFT", prevTab, "RIGHT", 14, 0)
    miniBtn:SetText("Mini tracker")
    miniBtn:SetScript("OnClick", function() ns.SetMini(not ns.db.ui.mini) end)
    miniBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Mini tracker")
        GameTooltip:AddLine("A small box that tallies what you're farming: each mob killed and what it brought in, "
            .. "each drop and its value, and the total. Start its timer for gold per hour. Also /fk mini.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    miniBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(170, 20)
    search:SetPoint("TOPRIGHT", -40, -12)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        offset = 0
        -- A shift-clicked item link goes straight to the mobs that drop it.
        local item = tonumber((self:GetText() or ""):match("item:(%d+)"))
        if item then return ns.HuntItem(item) end
        hunt = nil
        if view ~= "list" then ns.ShowList() else ns.Refresh() end
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    searchModeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    searchModeBtn:SetSize(60, 20)
    searchModeBtn:SetPoint("RIGHT", search, "LEFT", -8, 0)
    searchModeBtn:SetText("Mobs")
    searchModeBtn:SetScript("OnClick", function() setSearchMode(searchMode == "mobs" and "items" or "mobs") end)
    searchModeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Search for mobs, or for items")
        GameTooltip:AddLine("Items: pick one and see every mob that drops it, highest level first, with spawn points and drop chances. "
            .. "You can also shift-click an item link into the box.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    searchModeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", searchModeBtn, "LEFT", -6, 0)
    searchLabel:SetText("Search")

    -- Filters
    checks = {}
    local priceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLabel:SetPoint("TOPLEFT", 16, -45)
    priceLabel:SetText("Price in:")
    local x = 66
    for _, q in ipairs({ { "q0", "|cff9d9d9dGrey|r", "Grey (junk) drops, at their vendor price." },
                         { "q1", "White", "White drops: cloth, leather, meat and the like." },
                         { "q2", "|cff1eff00Green|r", "Uncommon drops." },
                         { "q3", "|cff0070ddBlue|r", "Rare drops." },
                         { "q4", "|cffa335eeEpic|r", "Epic and better." },
                         { "coin", "Coin", "The coin mobs drop." },
                         { "guild", "Guild data", "Add your guildmates' kills to yours (after they answer an Ask guild)." } }) do
        check(q[1], q[2], x, q[3])
        x = x + (q[1] == "guild" and 90 or 64)
    end
    check("near", "Near my level", x + 10, "Only mobs from 5 levels under you to 3 over.")
    minKillsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minKillsBtn:SetSize(100, 20)
    minKillsBtn:SetPoint("TOPRIGHT", -16, -40)
    minKillsBtn:SetScript("OnClick", function()
        local nextValue = MIN_KILLS[1]
        for i, v in ipairs(MIN_KILLS) do
            if v == ns.db.filter.minKills then nextValue = MIN_KILLS[i % #MIN_KILLS + 1] end
        end
        ns.db.filter.minKills = nextValue
        ns.Refresh()
    end)
    minKillsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("How many kills a mob needs before it's ranked under Best farms. Fewer kills means rougher numbers; they show in grey everywhere.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    minKillsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Left side
    sideButtons = {}
    for i = 1, SIDE_ROWS do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(SIDE_W, SIDE_H - 1)
        b:SetPoint("TOPLEFT", 12, TOP - (i - 1) * SIDE_H)
        b:SetScript("OnClick", function(self) if self.entry then ns.SelectTab(self.entry.key) end end)
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.count:SetPoint("RIGHT", -8, 0)
        local fs = b.GetFontString and b:GetFontString()
        if fs and fs.SetJustifyH then
            fs:SetJustifyH("LEFT")
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", 8, 0)
            fs:SetPoint("RIGHT", -34, 0)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
        end
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta)
            sideOffset = math.max(0, sideOffset - delta * 3)
            refreshSide()
        end)
        sideButtons[i] = b
    end

    -- The list
    listView = CreateFrame("Frame", nil, frame)
    listView:SetPoint("TOPLEFT", SIDE_W + 24, TOP)
    listView:SetPoint("BOTTOMRIGHT", -14, 40)
    ns.content = CreateFrame("Frame", nil, frame)
    ns.content:SetPoint("TOPLEFT", SIDE_W + 24, TOP)
    ns.content:SetPoint("BOTTOMRIGHT", -14, 40)
    headers = {}
    for i = 1, MAX_CELLS do header(i) end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, listView)
        r:SetSize(WIDTH - SIDE_W - 38, ROW_H)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local star = CreateFrame("Button", nil, r)
        star:SetSize(14, 14)
        star:SetPoint("LEFT", 2, 0)
        star:SetNormalTexture(STAR)
        star:SetScript("OnClick", function()
            if r.id then ns.db.fav[r.id] = (not ns.db.fav[r.id]) or nil; ns.Refresh() end
        end)
        r.star = star
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 2, 0)
        r.cells = {}
        for c = 1, MAX_CELLS do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            r.cells[c] = fs
        end
        r:SetScript("OnEnter", function(self)
            if not (self.id and self.isItem) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:AddLine("Click: every mob that drops it.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self, which)
            if not self.id then return end
            if self.isItem then
                ns.HuntItem(self.id)
            elseif which == "RightButton" then
                ns.db.fav[self.id] = (not ns.db.fav[self.id]) or nil
                ns.Refresh()
            else
                ns.ShowMob(self.id, i + offset)
            end
        end)
        rows[i] = r
    end
    listView.empty = listView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    listView.empty:SetPoint("TOP", 0, -60)
    listView.empty:SetWidth(560)
    listView:EnableMouseWheel(true)
    listView:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 5)
        ns.Refresh()
    end)

    local ask = CreateFrame("Button", nil, listView, "UIPanelButtonTemplate")
    askBtn = ask
    ask:SetSize(110, 22)
    ask:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", 0, -30)
    ask:SetText("Ask guild")
    ask:SetScript("OnClick", function()
        local ids = {}
        for _, e in ipairs(list) do table.insert(ids, e.id) end
        ns.AskGuild(ids)
    end)
    ask:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Ask guild")
        GameTooltip:AddLine("Ask guildmates running Farm King for their drop data on the " .. #list .. " mob(s) in this list"
            .. (#list > 500 and " (the first 500)" or "") .. ". Their kills add to yours when Guild data is ticked.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ask:SetScript("OnLeave", function() GameTooltip:Hide() end)

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", SIDE_W + 24, 16)
    footer:SetJustifyH("LEFT")

    ns.CreateMobView(ns.content)
    whitePane = ns.CreateWhiteView(frame)

    -- What the Mobs tab shows; the White Items tab hides it.
    mobWidgets = { search, searchModeBtn, searchLabel, priceLabel, minKillsBtn, listView, ns.content, footer }
    for _, c in pairs(checks) do table.insert(mobWidgets, c); table.insert(mobWidgets, c.label) end
    for _, b in ipairs(sideButtons) do table.insert(mobWidgets, b) end
    frame:SetScript("OnShow", ns.Refresh)
    frame:Hide()
end

-- While QuestieDB is being read, keep the footer moving (one loop at a time).
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

function ns.Toggle(show)
    if not ns.db then return end
    if not frame then create() end
    if show == nil then show = not frame:IsShown() end
    frame:SetShown(show)
    if show then
        if ns.QuestieAvailable() and not ns.QuestieReady() then
            ns.BuildQuestie(ns.Refresh)
            if not watching then watchBuild() end
        end
        ns.Refresh()
    end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 115)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if not mini then
        mini = CreateFrame("Button", "FarmKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Pelt_Wolf_01")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function(_, which)
            ns.Toggle(true)
            if which == "RightButton" then ns.SelectTab("zone") end
        end)
        mini:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                ns.db.ui.buttonAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
                place()
            end)
        end)
        mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        mini:SetScript("OnEnter", function(self)
            local kills = 0
            for _, m in pairs(ns.db.mobs) do kills = kills + (m.k or 0) end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Farm King")
            GameTooltip:AddLine(kills .. " kills recorded.", 1, 1, 1)
            GameTooltip:AddLine("Left-click: open", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: mobs in this zone", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(ns.db.ui.button)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pendingInfo = false
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        ns.UpdateMinimapButton()
    elseif ns.TakeWaiting() and not pendingInfo then
        pendingInfo = true
        C_Timer.After(0.5, function() pendingInfo = false; ns.Refresh() end)
    end
end)
