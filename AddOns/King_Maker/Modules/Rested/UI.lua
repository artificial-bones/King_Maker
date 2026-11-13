local _, KM = ...
local ns = KM.Module("Rested")
local UI = KM.UI
local C = UI.C

-- The Rested XP page of the King Maker window (Characters > Rested XP, /rk, /km rested): one line per character.
--   tiles       characters levelling, most rested alt, full of rest, next to fill up
--   toolbar     Show / Hide max level
--   Character   name (in class colours) and realm
--   Level       level and how far into it
--   Rested      rested XP now, as XP and as a share of the level, with bubbles
--   Full        when the rest stops growing, or how long it's been full (wasted)
--   Where       logged out in an inn or city (full rate) or outside (a quarter)
--   Last seen   when you last played it
-- Click a column header to sort by it. Right-click a character for the Well Rested perk rank and to forget it.
-- While the page is open a ticker redraws it every few seconds, so the estimates keep moving.
-- Also here: the crown's quick action and tooltip lines, the Home tile and the Settings section.

local TILE_W, TILE_H = 182, 60
local TICK = 5

local page, tbl, footer, maxBtn, tiles
local list = {}
local ticker

local function grey(t) return UI.Hex(C.muted) .. t .. "|r" end
local function colour(hex, t) return "|cff" .. hex .. t .. "|r" end

local function classColour(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.colorStr then return cc.colorStr:sub(3) end
    if cc then return string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) end
    return "ffffff"
end
ns.ClassColour = classColour

-- What the Full column says, and its colour.
function ns.FullText(e, now)
    if e.max then return grey("max level") end
    if e.unknown then return grey("-") end
    if e.full then
        local since = e.fullSince and (" " .. ns.Duration(now - e.fullSince)) or ""
        return colour("ff4040", "FULL" .. since)
    end
    if not e.fullIn then return grey("-") end
    local t = ns.Duration(e.fullIn)
    if e.fullIn < 86400 then return colour("ffd040", "in " .. t) end
    return colour("80ff80", "in " .. t)
end

function ns.RestedText(e)
    if e.max then return grey("-") end
    if e.unknown then return grey("log in once to read") end
    local s = ns.Num(e.rested) .. "  " .. string.format("(%d%%, %.1f bubbles)", math.floor(e.pct * 100 + 0.5), e.bubbles)
    if e.estimated then s = s .. grey(" est") end
    return s
end

local function lastSeen(c, now)
    if c.online then return colour("80ff80", "online") end
    if not c.t then return grey("-") end
    return ns.Duration(now - c.t) .. " ago"
end

-- The most rested character you're not playing right now (nil when there's none).
function ns.MostRestedAlt()
    if not ns.db then return nil end
    local me = ns.Char()
    for _, item in ipairs(ns.Characters("rested", true, false)) do
        if item.key ~= me and not item.e.unknown then return item end
    end
end

---------------------------------------------------------------------------
-- The right-click menu
---------------------------------------------------------------------------

function ns.RowMenu(owner, key)
    local c = ns.db.chars[key]
    if not c then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        KM.Print(ns, "use /rk forget " .. c.name .. " to stop tracking a character.")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(key)
        local perk = root:CreateButton("Well Rested perk")
        for r = 0, ns.PERK_RANKS do
            perk:CreateRadio(r == 0 and "None" or ("Rank " .. r .. " (+" .. (r * 4) .. "%)"),
                function() return (c.perk or 0) == r end, function() ns.SetPerk(key, r) end)
        end
        root:CreateButton("Forget this character", function() ns.Forget(key) end)
    end)
end

local function rowTip(r)
    local item = r.data
    local c = item and ns.db.chars[item.key]
    if not c then return end
    local e = ns.Estimate(c)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:AddLine(item.key)
    if e.max then
        GameTooltip:AddLine("Max level: no rest to track.", 1, 1, 1)
    elseif e.unknown then
        GameTooltip:AddLine("No XP numbers saved for this character yet. Log in on it once and they'll show up.", 1, 1, 1, true)
    else
        GameTooltip:AddDoubleLine("Rested now", ns.Num(e.rested) .. " / " .. ns.Num(e.cap), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("XP left this level", ns.Num(e.toLevel), 1, 1, 1, 1, 1, 1)
        local hours = c.resting and ns.HOURS_PER_STEP or ns.HOURS_PER_STEP / ns.OUTSIDE
        GameTooltip:AddDoubleLine("Gaining", "5% of a level per " .. hours .. "h"
            .. ((c.perk or 0) > 0 and (" +" .. (c.perk * 4) .. "%") or ""), 1, 1, 1, 1, 1, 1)
        if c.zone then GameTooltip:AddDoubleLine("Logged out in", c.zone .. (c.resting and " (resting)" or ""), 1, 1, 1, 1, 1, 1) end
        if e.estimated then
            GameTooltip:AddLine("Worked out from when you logged out. Logging in shows the exact number.", 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:AddLine("Right-click: Well Rested perk, forget.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function fillRow(r, item, cells)
    local now = ns.Now()
    local c, e = item.c, item.e
    cells.name:SetText(colour(classColour(c.class), c.name) .. " " .. grey(c.realm or ""))
    local lvl = tostring(c.level or "?")
    if not e.max and c.xpMax and c.xpMax > 0 then
        lvl = lvl .. grey(string.format(" %d%%", math.floor((c.xp or 0) / c.xpMax * 100)))
    end
    cells.level:SetText(lvl)
    cells.rested:SetText(ns.RestedText(e))
    cells.full:SetText(ns.FullText(e, now))
    cells.where:SetText((e.max or e.unknown) and grey("-") or (c.resting and "Inn/city" or colour("ffa040", "Outside")))
    cells.seen:SetText(lastSeen(c, now))
end

local function refreshTiles(now)
    local levelling, full, next = 0, 0, nil
    for _, c in pairs(ns.db.chars) do
        if not ns.IsMax(c) then
            levelling = levelling + 1
            local e = ns.Estimate(c, now)
            if e.unknown then -- nothing to add up yet
            elseif e.full then full = full + 1
            elseif e.fullIn and (not next or e.fullIn < next.e.fullIn) then next = { c = c, e = e } end
        end
    end
    tiles[1]:Set("Characters levelling", tostring(levelling), levelling == 0 and "log in on each one once" or "below max level")
    local alt = ns.MostRestedAlt()
    if alt then
        tiles[2]:Set("Most rested alt", alt.c.name, math.floor(alt.e.pct * 100 + 0.5) .. "% of a level", alt.e.full and C.warn or C.text)
    else
        tiles[2]:Set("Most rested alt", "-", "no other characters yet", C.dim)
    end
    tiles[3]:Set("Full of rest", tostring(full), full > 0 and "play them before it's wasted" or "nobody is wasting rest",
        full > 0 and C.bad or C.text)
    if next then
        tiles[4]:Set("Next to fill up", next.c.name, "in " .. ns.Duration(next.e.fullIn))
    else
        tiles[4]:Set("Next to fill up", "-", "", C.dim)
    end
end

local function refresh()
    if not page or not ns.db then return end
    local now = ns.Now()
    refreshTiles(now)
    maxBtn:SetLabel(ns.db.ui.showMax and "Hide max level" or "Show max level")
    tbl:SetSort(ns.db.ui.sort, ns.db.ui.desc)
    list = ns.Characters(ns.db.ui.sort, ns.db.ui.desc, ns.db.ui.showMax)
    tbl.emptyText = "Log in on each of your characters once and they'll show up here."
    tbl:SetRows(list, fillRow)
    local full, n = 0, 0
    for _, item in ipairs(list) do
        if not item.e.max and not item.e.unknown then n = n + 1; if item.e.full then full = full + 1 end end
    end
    if n == 0 then
        footer:SetText("Rest: 5% of a level per 8h in an inn or city, per 32h outside, up to 150%.")
    else
        footer:SetText(n .. " characters levelling" .. (full > 0 and (", " .. colour("ff4040", full .. " full of rest: play them before it's wasted")) or "")
            .. ".  Rest: 5% of a level per 8h in an inn or city, per 32h outside, up to 150%.")
    end
    -- Keep the numbers moving while it's open; the ticker stops itself once the page is gone.
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(TICK, function(self)
            if not KM.IsShown("rested") then self:Cancel(); ticker = nil return end
            KM.Refresh("rested")
        end)
    end
end

local function hide()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- Redraws the page if it's the one showing (snapshots, perk changes and forgetting call this).
function ns.Refresh() KM.Refresh("rested") end
function ns.IsTicking() return ticker ~= nil end
function ns.List() return list end

-- Opens (true), closes (false) or toggles (nil) the page.
function ns.Toggle(show)
    if not ns.db then return end
    if show == nil then show = not KM.IsShown("rested") end
    if show then KM.Show("rested") elseif KM.IsShown("rested") then KM.Toggle(false) end
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function buildPage(c)
    page = c
    tiles = {}
    for i = 1, 4 do
        local t = UI.Tile(c, TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), 0)
        tiles[i] = t
    end

    maxBtn = UI.Button(c, "Show max level", 130, 24, function()
        ns.db.ui.showMax = not ns.db.ui.showMax
        tbl.offset = 0
        ns.Refresh()
    end)
    maxBtn:SetPoint("TOPRIGHT", 0, -(TILE_H + 12))
    local hint = UI.Text(c, 11, C.muted)
    hint:SetPoint("TOPLEFT", 0, -(TILE_H + 18))
    hint:SetText("Click a header to sort. Right-click a character: Well Rested perk, forget.")

    local function col(key, label, w, desc)
        return { key = key, label = label, w = w, desc = desc, sort = key ~= "where" and function() return 0 end or nil }
    end
    local cols = {
        col("name", "Character", 170, false),
        col("level", "Level", 70, true),
        col("rested", "Rested", 200, true),
        col("full", "Full", 116, false),
        col("where", "Where", 70),
        col("seen", "Last seen", 0, false),
    }
    -- The table only draws: ns.Characters sorts (it knows how to rank a full or max-level character).
    tbl = UI.Table(c, cols, 22, {
        noSort = true,
        onSort = function(key, desc)
            ns.db.ui.sort, ns.db.ui.desc = key, desc
            tbl.offset = 0
            ns.Refresh()
        end,
        onClick = function(item, which, r)
            if which == "RightButton" then ns.RowMenu(r, item.key) end
        end,
        onEnter = rowTip,
    })
    tbl:SetPoint("TOPLEFT", 0, -(TILE_H + 12 + 24 + 10))
    tbl:SetPoint("BOTTOMRIGHT", 0, 22)
    tbl.fill = fillRow
    ns.table = tbl

    footer = UI.Text(c, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    ns.footer = footer
end

KM.RegisterPage({
    id = "rested", group = "char", label = "Rested XP", icon = "Interface\\Icons\\Spell_Nature_Sleep", order = 20,
    title = "Rested XP",
    subtitle = "Every character's rest, worked out since you logged it out: who to play before it goes to waste.",
    build = buildPage, refresh = refresh, hide = hide,
})

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "rested", label = "Rested XP", order = 51, func = function() ns.Toggle(true) end })

-- The crown's tooltip: the three most rested characters.
KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local now, shown = ns.Now(), 0
    for _, item in ipairs(ns.Characters("rested", true, false)) do
        if shown >= 3 or item.e.unknown then break end
        shown = shown + 1
        local e = item.e
        tt:AddDoubleLine("Rested: " .. colour(classColour(item.c.class), item.c.name) .. " " .. (item.c.level or ""),
            math.floor(e.pct * 100 + 0.5) .. "%  " .. ns.FullText(e, now), 1, 1, 1, 1, 1, 1)
    end
end)

KM.RegisterHomeTile({ id = "rested", order = 51, get = function()
    local alt = ns.MostRestedAlt()
    if not alt then return nil end
    local e = alt.e
    return "Most rested alt", alt.c.name .. " " .. (alt.c.level or ""),
        math.floor(e.pct * 100 + 0.5) .. "% rested, " .. (e.full and "full" or (e.fullIn and ("full in " .. ns.Duration(e.fullIn)) or "")),
        e.full and C.warn or C.text
end })

KM.RegisterSettings({ id = "rested", label = "Rested", order = 51, rows = {
    { type = "header", label = "The page" },
    { type = "check", label = "Show max-level characters", tip = "They have no rest to track, so they're hidden unless you want them listed.",
      get = function() return ns.db.ui.showMax end, set = function(v) ns.db.ui.showMax = v; ns.Refresh() end },
    { type = "header", label = "This character" },
    { type = "range", label = "Well Rested perk rank", min = 0, max = ns.PERK_RANKS, step = 1,
      fmt = function(v) return v == 0 and "None" or ("Rank " .. v) end,
      get = function() local c = ns.db.chars[ns.Char()]; return c and (c.perk or 0) or 0 end,
      set = function(v) if not ns.db.chars[ns.Char()] then ns.Snapshot() end; ns.SetPerk(ns.Char(), v) end },
    { type = "text", label = "The legacy perk adds 4% per rank to how fast rest builds and to the most you can hold. Set it for other characters by right-clicking them on the Rested XP page." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/rk   open the Rested XP page\n/rk perk 0-5   your Well Rested rank on this character\n/rk forget Name   stop tracking a character" },
} })
