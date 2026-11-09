local _, ns = ...

-- The Rested King window: one line per character.
--   Character   name (in class colours) and realm
--   Level       level and how far into it
--   Rested      rested XP now, as XP and as a share of the level, with bubbles
--   Full        when the rest stops growing, or how long it's been full (wasted)
--   Where       logged out in an inn or city (full rate) or outside (a quarter)
--   Last seen   when you last played it
-- Click a column header to sort by it. Right-click a character for the Well
-- Rested perk rank and to forget it.

local WIDTH, HEIGHT = 720, 420
local ROWS, ROW_H = 16, 20
local COLS = {
    { key = "name", label = "Character", x = 0, w = 170 },
    { key = "level", label = "Level", x = 170, w = 70 },
    { key = "rested", label = "Rested", x = 240, w = 190 },
    { key = "full", label = "Full", x = 430, w = 110 },
    { key = "where", label = "Where", x = 540, w = 60 },
    { key = "seen", label = "Last seen", x = 600, w = 88 },
}

local frame, rows, headers, footer, maxBtn, mini
local offset = 0
local list = {}

local function grey(t) return "|cff808080" .. t .. "|r" end
local function colour(hex, t) return "|cff" .. hex .. t .. "|r" end

local function classColour(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.colorStr then return cc.colorStr:sub(3) end
    if cc then return string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) end
    return "ffffff"
end

-- What the Full column says, and its colour.
function ns.FullText(e, now)
    if e.max then return grey("max level") end
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
    local s = ns.Num(e.rested) .. "  " .. string.format("(%d%%, %.1f bubbles)", math.floor(e.pct * 100 + 0.5), e.bubbles)
    if e.estimated then s = s .. grey(" est") end
    return s
end

local function lastSeen(c, now)
    if c.online then return colour("80ff80", "online") end
    if not c.t then return grey("-") end
    return ns.Duration(now - c.t) .. " ago"
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function ns.RowMenu(owner, key)
    local c = ns.db.chars[key]
    if not c then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Print("use /rk forget " .. c.name .. " to stop tracking a character.")
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

local function makeRow(i)
    local r = CreateFrame("Button", nil, frame)
    r:SetSize(WIDTH - 32, ROW_H)
    r:SetPoint("TOPLEFT", 16, -70 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.cells = {}
    for j, col in ipairs(COLS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", col.x, 0)
        fs:SetWidth(col.w - 4)
        fs:SetJustifyH("LEFT")
        r.cells[j] = fs
    end
    r:SetScript("OnClick", function(self, which)
        if which == "RightButton" and self.key then ns.RowMenu(self, self.key) end
    end)
    r:SetScript("OnEnter", function(self)
        local c = self.key and ns.db.chars[self.key]
        if not c then return end
        local e = ns.Estimate(c)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.key)
        if e.max then
            GameTooltip:AddLine("Max level: no rest to track.", 1, 1, 1)
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
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function create()
    frame = CreateFrame("Frame", "RestedKingFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
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
    if UISpecialFrames then table.insert(UISpecialFrames, "RestedKingFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Rested King")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    maxBtn = button(frame, "", 130, function() ns.db.ui.showMax = not ns.db.ui.showMax; offset = 0; ns.Refresh() end)
    maxBtn:SetPoint("TOPRIGHT", -36, -12)

    headers = {}
    for j, col in ipairs(COLS) do
        local h = CreateFrame("Button", nil, frame)
        h:SetSize(col.w, 18)
        h:SetPoint("TOPLEFT", 16 + col.x, -46)
        local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT")
        h.text = fs
        h.col = col
        if col.key ~= "where" then
            h:SetScript("OnClick", function()
                if ns.db.ui.sort == col.key then ns.db.ui.desc = not ns.db.ui.desc
                else ns.db.ui.sort = col.key; ns.db.ui.desc = (col.key == "rested" or col.key == "level") end
                ns.Refresh()
            end)
        end
        headers[j] = h
    end

    rows = {}
    for i = 1, ROWS do rows[i] = makeRow(i) end

    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #list - ROWS), offset - delta * 3))
        ns.Refresh()
    end)

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 14)
    footer:SetPoint("BOTTOMRIGHT", -16, 14)
    footer:SetJustifyH("LEFT")

    -- Keep the numbers moving while it's open.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc >= 5 then acc = 0; ns.Refresh() end
    end)
    frame:Hide()
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local now = ns.Now()
    list = ns.Characters(ns.db.ui.sort, ns.db.ui.desc, ns.db.ui.showMax)
    offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
    maxBtn:SetText(ns.db.ui.showMax and "Hide max level" or "Show max level")
    for _, h in ipairs(headers) do
        local arrow = ""
        if ns.db.ui.sort == h.col.key then arrow = ns.db.ui.desc and " v" or " ^" end
        h.text:SetText(h.col.label .. arrow)
    end
    for i, r in ipairs(rows) do
        local item = list[i + offset]
        if item then
            local c, e = item.c, item.e
            r.key = item.key
            r.cells[1]:SetText(colour(classColour(c.class), c.name) .. " " .. grey(c.realm or ""))
            local lvl = tostring(c.level or "?")
            if not e.max and c.xpMax and c.xpMax > 0 then
                lvl = lvl .. grey(string.format(" %d%%", math.floor((c.xp or 0) / c.xpMax * 100)))
            end
            r.cells[2]:SetText(lvl)
            r.cells[3]:SetText(ns.RestedText(e))
            r.cells[4]:SetText(ns.FullText(e, now))
            r.cells[5]:SetText(e.max and grey("-") or (c.resting and "Inn/city" or colour("ffa040", "Outside")))
            r.cells[6]:SetText(lastSeen(c, now))
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    local full, n = 0, 0
    for _, item in ipairs(list) do
        if not item.e.max then n = n + 1; if item.e.full then full = full + 1 end end
    end
    if n == 0 then
        footer:SetText("Log in on each of your characters once and they'll show up here.")
    else
        footer:SetText(n .. " characters levelling" .. (full > 0 and (", " .. colour("ff4040", full .. " full of rest: play them before it's wasted")) or "")
            .. ".  Rest: 5% of a level per 8h in an inn or city, per 32h outside, up to 150%.")
    end
end

function ns.Toggle()
    if not frame then create() end
    if frame:IsShown() then frame:Hide() else frame:Show(); ns.Refresh() end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local function place()
    local angle = math.rad(ns.db.ui.buttonAngle or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
    if not ns.db or not Minimap then return end
    if not mini then
        mini = CreateFrame("Button", "RestedKingMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = mini:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function() ns.Toggle() end)
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
            local now = ns.Now()
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Rested King")
            local shown = 0
            for _, item in ipairs(ns.Characters("rested", true, false)) do
                if shown >= 8 then break end
                shown = shown + 1
                local e = item.e
                GameTooltip:AddDoubleLine(colour(classColour(item.c.class), item.c.name) .. " " .. (item.c.level or ""),
                    math.floor(e.pct * 100 + 0.5) .. "%  " .. ns.FullText(e, now), 1, 1, 1, 1, 1, 1)
            end
            if shown == 0 then GameTooltip:AddLine("No characters yet: log in on each one once.", 1, 1, 1) end
            GameTooltip:AddLine("Click: open. Drag: move this button.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    place()
    mini:SetShown(ns.db.ui.button)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if ns.db then ns.UpdateMinimapButton() end
end)
