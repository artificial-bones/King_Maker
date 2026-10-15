local addonName, ns = ...

-- Minimap King: one crown on the minimap for every minimap button.
--
-- It moves addon minimap buttons (the King addons, LibDBIcon buttons, and any
-- other addon's button around the edge of the minimap) into a drop-down under
-- a crown. The real buttons move, so they work exactly as before: clicks,
-- right-clicks, tooltips and menus. Blizzard's own minimap buttons stay put.
-- "/mmk release" puts everything back.

-- The King addons, by button name, so they're always caught and named nicely.
ns.KINGS = {
    ScannerKingMinimapButton = "Scanner King", MarketKingMinimapButton = "Market King",
    EconKingMinimapButton = "Econ King", FarmKingMinimapButton = "Farm King",
    GatherKingMinimapButton = "Gather King", MailKingMinimapButton = "Mail King",
    QuestKingMinimapButton = "Quest King", SkillupKingMinimapButton = "Skillup King",
}

-- Blizzard's minimap frames, which stay where they are.
local BLIZZARD = {
    "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^Expansion",
    "^AddonCompartment", "^GarrisonLandingPage", "^MinimapCluster", "^LFG", "^Battlefield",
    "^HelpOpenTicket", "^FeedbackUI", "^TaxiRouteFrame",
}

-- Map pins and arrows other addons put on the minimap (some sit on its edge).
local PINS = { "^QuestieFrame", "^GatherMate", "^HandyNotes", "^TomTom", "^Routes", "Pin%d*$", "Arrow%d*$" }

local DEFAULTS = { gather = true, angle = 200, ignore = {} }

ns.CROWNS = {
    { "Gold crown", "Interface\\Icons\\INV_Helm_Crown_C_01_Gold" },
    { "Jeweled crown", "Interface\\Icons\\INV_Crown_13" },
    { "Royal crown", "Interface\\Icons\\INV_Crown_14" },
    { "Regal crown", "Interface\\Icons\\INV_Crown_15" },
    { "Crown of the Heavens", "Interface\\Icons\\Ability_Crown_of_the_Heavens_Icon" },
    { "Crown jewels", "Interface\\Icons\\INV_Archaeology_70_CrownJewelsofSuramar" },
    { "Silver crown", "Interface\\Icons\\INV_Helm_Crown_C_01_Silver" },
    { "Classic crown", "Interface\\Icons\\INV_Crown_01" },
    { "Classic silver crown", "Interface\\Icons\\INV_Crown_02" },
}

function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Minimap King|r: " .. msg) end

-- The crowns this client has (newer icons may be missing).
function ns.Crowns()
    local out = {}
    for _, c in ipairs(ns.CROWNS) do
        if not GetFileIDFromPath or GetFileIDFromPath(c[2]) then table.insert(out, c) end
    end
    if #out == 0 then out[1] = ns.CROWNS[#ns.CROWNS - 1] end
    return out
end

function ns.Crown()
    local have = ns.Crowns()
    for _, c in ipairs(have) do if c[2] == ns.db.icon then return c end end
    return have[1]
end

---------------------------------------------------------------------------
-- Which buttons
---------------------------------------------------------------------------

-- A readable name: "LibDBIcon10_Questie" -> "Questie", "AtlasLootMinimapButton" -> "AtlasLoot".
function ns.NameOf(btn)
    local name = btn:GetName() or "?"
    if ns.KINGS[name] then return ns.KINGS[name] end
    local lib = name:match("^LibDBIcon10_(.+)$")
    if lib then return lib end
    local s = name:gsub("_?[Mm]ini[Mm]ap", ""):gsub("_?Button$", ""):gsub("_?Frame$", ""):gsub("_", " ")
    if s == "" then s = name end
    return s
end

local function isBlizzard(name)
    for _, p in ipairs(BLIZZARD) do if name:match(p) then return true end end
    return false
end

-- Whether a frame looks like an addon's minimap button: named, clickable,
-- button-sized, and sitting on the edge of the minimap (map pins sit inside it).
function ns.IsAddonButton(f)
    local name = f.GetName and f:GetName()
    if not name or name == "MinimapKingButton" then return false end
    if ns.KINGS[name] or name:match("^LibDBIcon10_") then return true end
    if isBlizzard(name) then return false end
    for _, p in ipairs(PINS) do if name:match(p) then return false end end
    if not (f.GetObjectType and f:GetObjectType() == "Button") then return false end
    if not (f:GetScript("OnClick") or f:GetScript("OnMouseUp")) then return false end
    local w, h = f:GetSize()
    if not w or w > 40 or h > 40 or w < 12 then return false end
    local fx, fy = f:GetCenter()
    local mx, my = Minimap:GetCenter()
    if fx and mx then
        local d = math.sqrt((fx - mx) ^ 2 + (fy - my) ^ 2)
        if d < Minimap:GetWidth() / 2 - 12 then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Taking them in
---------------------------------------------------------------------------

local menu, crown
local gathered = {} -- button -> { parent, points, strata, level }
local order = {}    -- the gathered buttons, in order
local laying = false
local LINE_H, MENU_W = 32, 200

local function savePoints(btn)
    local pts = {}
    for i = 1, (btn.GetNumPoints and btn:GetNumPoints() or 0) do pts[i] = { btn:GetPoint(i) } end
    return pts
end

-- Where to look: the minimap, and the frame behind it some addons use.
local function candidates()
    local out = {}
    for _, holder in ipairs({ Minimap, MinimapBackdrop }) do
        if holder and holder.GetChildren then
            for _, f in ipairs({ holder:GetChildren() }) do table.insert(out, f) end
        end
    end
    for name in pairs(ns.KINGS) do if _G[name] then table.insert(out, _G[name]) end end
    return out
end

function ns.Gather()
    if not ns.db.gather then return end
    ns.EnsureMenu()
    for _, btn in ipairs(candidates()) do
        local name = btn:GetName()
        if not gathered[btn] and name and not ns.db.ignore[name] and ns.IsAddonButton(btn) then
            gathered[btn] = { parent = btn:GetParent(), points = savePoints(btn),
                              strata = btn:GetFrameStrata(), level = btn:GetFrameLevel() }
            table.insert(order, btn)
            btn:SetParent(menu)
            btn:RegisterForDrag() -- no dragging it around inside the menu
            hooksecurefunc(btn, "SetPoint", function(self)
                if gathered[self] and not laying then ns.Layout() end
            end)
            hooksecurefunc(btn, "Show", function(self) if gathered[self] then ns.Layout() end end)
            hooksecurefunc(btn, "Hide", function(self) if gathered[self] and not laying then ns.Layout() end end)
            hooksecurefunc(btn, "SetShown", function(self) if gathered[self] and not laying then ns.Layout() end end)
        end
    end
    table.sort(order, function(a, b) return ns.NameOf(a):lower() < ns.NameOf(b):lower() end)
    ns.Layout()
end

-- Put one button back where it came from.
local function giveBack(btn)
    local g = gathered[btn]
    gathered[btn] = nil
    btn:SetParent(g.parent)
    btn:SetFrameStrata(g.strata)
    btn:SetFrameLevel(g.level)
    btn:RegisterForDrag("LeftButton")
    laying = true
    btn:ClearAllPoints()
    for _, p in ipairs(g.points) do btn:SetPoint(unpack(p)) end
    laying = false
end

function ns.Release()
    for _, btn in ipairs(order) do if gathered[btn] then giveBack(btn) end end
    wipe(order)
    ns.Layout()
end

function ns.Ignore(btn)
    ns.db.ignore[btn:GetName()] = true
    for i, b in ipairs(order) do if b == btn then table.remove(order, i) end end
    giveBack(btn)
    ns.Layout()
end

-- The buttons on show in the menu (an addon may have its own button turned off).
function ns.Shown()
    local out = {}
    for _, btn in ipairs(order) do if btn:IsShown() then table.insert(out, btn) end end
    return out
end

---------------------------------------------------------------------------
-- The drop-down
---------------------------------------------------------------------------

local labels = {}
ns.labels = labels

local function label(i)
    if labels[i] then return labels[i] end
    local l = CreateFrame("Button", nil, menu)
    l:SetSize(MENU_W - 52, LINE_H)
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l.text:SetPoint("LEFT", 4, 0)
    l.text:SetJustifyH("LEFT")
    -- the name works like the button next to it; shift-right-click leaves it on the minimap
    l:SetScript("OnClick", function(self, which)
        if not self.button then return end
        if which == "RightButton" and IsShiftKeyDown() then
            ns.Print(ns.NameOf(self.button) .. " stays on the minimap now. /mmk unignore brings every button back in.")
            ns.Ignore(self.button)
            return
        end
        self.button:Click(which)
    end)
    l:SetScript("OnEnter", function(self)
        local onEnter = self.button and self.button:GetScript("OnEnter")
        if onEnter then onEnter(self.button) end
    end)
    l:SetScript("OnLeave", function(self)
        local onLeave = self.button and self.button:GetScript("OnLeave")
        if onLeave then onLeave(self.button) else GameTooltip:Hide() end
    end)
    labels[i] = l
    return l
end

function ns.Layout()
    if not menu then return end
    laying = true
    local shown = ns.Shown()
    for i, btn in ipairs(shown) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -8 - (i - 1) * LINE_H)
        btn:SetFrameStrata("DIALOG")
        btn:SetFrameLevel(menu:GetFrameLevel() + 5)
        local l = label(i)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", menu, "TOPLEFT", 42, -8 - (i - 1) * LINE_H)
        l.button = btn
        l.text:SetText(ns.NameOf(btn))
        l:Show()
    end
    for i = #shown + 1, #labels do labels[i]:Hide(); labels[i].button = nil end
    menu.empty:SetText(#shown == 0 and "No minimap buttons to show." or "")
    menu:SetSize(MENU_W, 16 + math.max(#shown, 1) * LINE_H)
    laying = false
end

function ns.EnsureMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "MinimapKingMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    end
    menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    menu.empty:SetPoint("TOPLEFT", 12, -12)
    -- a click out in the world closes it (clicks on other windows, or on a
    -- menu one of the buttons opened, leave it open)
    menu:SetScript("OnEvent", function(self)
        local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
        if focus == nil or focus == WorldFrame then self:Hide() end
    end)
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    table.insert(UISpecialFrames, "MinimapKingMenu") -- Escape closes it
    menu:Hide() -- new frames start shown; hide it so the first Show runs OnShow
    return menu
end

function ns.ShowMenu()
    ns.EnsureMenu()
    ns.Gather() -- catch buttons made since login
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", crown, "BOTTOMLEFT", 8, 8)
    menu:Show()
end

function ns.ToggleMenu()
    if menu and menu:IsShown() then menu:Hide() else ns.ShowMenu() end
end

---------------------------------------------------------------------------
-- The crown on the minimap
---------------------------------------------------------------------------

local function position()
    local angle = math.rad(ns.db.angle)
    local radius = (Minimap:GetWidth() / 2) + 5
    crown:ClearAllPoints()
    crown:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createCrown()
    crown = CreateFrame("Button", "MinimapKingButton", Minimap)
    crown:SetSize(31, 31)
    crown:SetFrameStrata("MEDIUM")
    crown:SetFrameLevel(8)
    crown:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    crown:RegisterForDrag("LeftButton")
    crown:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = crown:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ns.Crown()[2])
    crown.icon = icon
    local mask = crown:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)
    local border = crown:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    crown:SetScript("OnClick", function() GameTooltip:Hide(); ns.ToggleMenu() end)
    crown:SetScript("OnDragStart", function(self)
        if menu then menu:Hide() end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            ns.db.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            position()
        end)
    end)
    crown:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    crown:SetScript("OnEnter", function(self)
        if menu and menu:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Minimap King")
        local names = {}
        for _, btn in ipairs(ns.Shown()) do table.insert(names, ns.NameOf(btn)) end
        GameTooltip:AddLine(#names > 0 and table.concat(names, ", ") or "No minimap buttons gathered yet.", 1, 1, 1, true)
        GameTooltip:AddLine("Click: the menu. Drag: move this button.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("In the menu, shift-right-click a name to leave that button on the minimap.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    crown:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Start up, slash command
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        MinimapKingDB = MinimapKingDB or {}
        for k, v in pairs(DEFAULTS) do if MinimapKingDB[k] == nil then MinimapKingDB[k] = v end end
        ns.db = MinimapKingDB
    elseif event == "PLAYER_LOGIN" then
        createCrown()
        position()
        -- addons make their buttons at login or a little after, so look a few times
        ns.Gather()
        C_Timer.After(1, ns.Gather)
        C_Timer.After(5, ns.Gather)
        C_Timer.After(15, ns.Gather)
    end
end)

SLASH_MINIMAPKING1 = "/mmk"
SLASH_MINIMAPKING2 = "/minimapking"
SlashCmdList.MINIMAPKING = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:lower():match("^(%S*)%s*(.-)$")
    if cmd == "release" then
        ns.db.gather = false
        ns.Release()
        ns.Print("Every button is back on the minimap. /mmk gather takes them in again.")
    elseif cmd == "gather" then
        ns.db.gather = true
        ns.Gather()
        ns.Print("The minimap buttons are in the crown.")
    elseif cmd == "unignore" then
        wipe(ns.db.ignore)
        ns.Gather()
        ns.Print("Every button goes in the crown again.")
    elseif cmd == "icon" then
        local have, n = ns.Crowns(), tonumber(rest)
        if not n then
            local cur = ns.Crown()
            for i, c in ipairs(have) do if c == cur then n = i % #have + 1 end end
        end
        local c = have[n]
        if not c then
            ns.Print("Pick 1 to " .. #have .. ".")
            return
        end
        ns.db.icon = c[2]
        if crown then crown.icon:SetTexture(c[2]) end
        local list = {}
        for i, h in ipairs(have) do table.insert(list, (h == c and "|cffffd100" or "") .. i .. ". " .. h[1] .. (h == c and "|r" or "")) end
        ns.Print("Crown: " .. c[1] .. ". /mmk icon again for the next one, or /mmk icon <number>: " .. table.concat(list, ", "))
    elseif cmd == "" or cmd == "menu" then
        ns.ShowMenu()
    else
        ns.Print("/mmk opens the menu. /mmk icon changes the crown. /mmk release puts every button back on the minimap, /mmk gather takes them in again. Shift-right-click a name in the menu to leave that button on the minimap; /mmk unignore undoes that.")
    end
end

MinimapKing = { ShowMenu = ns.ShowMenu, Gather = ns.Gather, Release = ns.Release, Shown = ns.Shown }
