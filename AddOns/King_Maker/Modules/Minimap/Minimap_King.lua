local _, KM = ...
local ns = KM.Module("Minimap", { title = "Minimap King", short = "Minimap", legacy = "Minimap_King", db = "MinimapKingDB" })
local UI = KM.UI
local C = UI.C

-- Minimap buttons (was Minimap King): every other addon's minimap button in one drop-down.
--
-- It moves addon minimap buttons (LibDBIcon buttons, and any other addon's button around the edge of the minimap)
-- into a menu that opens under King Maker's crown. The real buttons move, so they work exactly as before: clicks,
-- right-clicks, tooltips and menus. Blizzard's own minimap buttons, map pins and King Maker's crown stay put.
-- In King Maker the crown is King Maker's own (KingMakerMinimapButton, Shell.lua): the menu is the quick action
-- "Minimap buttons", and the list of which buttons go in is the Settings section "Minimap buttons".
-- "/mmk release" puts everything back.
--
-- MinimapKingDB = { gather = bool, ignore = { [buttonName] = true } }   (angle and icon: 1.x, unused now)

-- Never gathered: King Maker's crown (and Minimap King 1.x's, if it's still installed).
local OWN = { KingMakerMinimapButton = true, MinimapKingButton = true }

-- Blizzard's minimap frames, which stay where they are.
local BLIZZARD = {
    "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^Expansion",
    "^AddonCompartment", "^GarrisonLandingPage", "^MinimapCluster", "^LFG", "^Battlefield",
    "^HelpOpenTicket", "^FeedbackUI", "^TaxiRouteFrame",
}

-- Map pins and arrows other addons put on the minimap (some sit on its edge).
local PINS = { "^QuestieFrame", "^GatherMate", "^HandyNotes", "^TomTom", "^Routes", "Pin%d*$", "Arrow%d*$" }

local DEFAULTS = { gather = true }

---------------------------------------------------------------------------
-- Which buttons
---------------------------------------------------------------------------

-- A readable name: "LibDBIcon10_Questie" -> "Questie", "AtlasLootMinimapButton" -> "AtlasLoot".
function ns.NameOf(btn)
    local name = btn:GetName() or "?"
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
    if not name or OWN[name] then return false end
    if name:match("^LibDBIcon10_") or name == "OracleMinimapButton" then return true end
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

local menu
local gathered = {} -- button -> { parent, points, strata, level }
local order = {}    -- the gathered buttons, in order
local laying = false
local LINE_H, MENU_W, HEAD_H = 30, 210, 30

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
    return out
end

ns.known = {} -- every addon minimap button seen: name -> button (in the menu or not)

-- Notes every addon button there is, for the Settings list.
local function learn()
    for _, btn in ipairs(candidates()) do
        local name = btn:GetName()
        if name and not ns.known[name] and (gathered[btn] or ns.IsAddonButton(btn)) then ns.known[name] = btn end
    end
end

local function closeSoon()
    -- after the click has run, so whatever it opened opens first
    C_Timer.After(0, function() if menu then menu:Hide() end end)
end

-- Oracle (the player's companion addon) right under King Maker; everything else by name.
local FIRST = { OracleMinimapButton = 1 }
local function byName(a, b)
    local fa, fb = FIRST[a:GetName() or ""] or 99, FIRST[b:GetName() or ""] or 99
    if fa ~= fb then return fa < fb end
    return ns.NameOf(a):lower() < ns.NameOf(b):lower()
end

function ns.Gather()
    if not ns.db then return end
    learn()
    if ns.RefreshSettings then ns.RefreshSettings() end
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
            if not btn.minimapKingHooked then
                btn.minimapKingHooked = true
                hooksecurefunc(btn, "SetPoint", function(self)
                    if gathered[self] and not laying then ns.Layout() end
                end)
                hooksecurefunc(btn, "Show", function(self) if gathered[self] then ns.Layout() end end)
                hooksecurefunc(btn, "Hide", function(self) if gathered[self] and not laying then ns.Layout() end end)
                hooksecurefunc(btn, "SetShown", function(self) if gathered[self] and not laying then ns.Layout() end end)
                btn:HookScript("OnClick", function(self) if gathered[self] then closeSoon() end end)
            end
        end
    end
    table.sort(order, byName)
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
    if gathered[btn] then giveBack(btn) end
    ns.Layout()
    if ns.RefreshSettings then ns.RefreshSettings() end
end

-- In the menu (true) or on the minimap (false).
function ns.SetInMenu(btn, on)
    if on then
        ns.db.ignore[btn:GetName()] = nil
        ns.Gather()
    else
        ns.Ignore(btn)
    end
end

function ns.InMenu(btn) return not ns.db.ignore[btn:GetName()] and ns.db.gather end

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
    l:SetSize(MENU_W - 50, LINE_H - 2)
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l.hl = UI.Fill(l, C.hover, "ARTWORK")
    l.hl:Hide()
    l.text = UI.Text(l, 12, C.text)
    l.text:SetPoint("LEFT", 6, 0)
    l.text:SetPoint("RIGHT", -4, 0)
    -- the name works like the button next to it; shift-right-click leaves it on the minimap
    l:SetScript("OnClick", function(self, which)
        if not self.button then return end
        if which == "RightButton" and IsShiftKeyDown() then
            KM.Print(ns, ns.NameOf(self.button) .. " stays on the minimap now. /mmk unignore brings every button back in.")
            ns.Ignore(self.button)
            return
        end
        self.button:Click(which) -- its own OnClick hook closes the menu
    end)
    l:SetScript("OnEnter", function(self)
        self.hl:Show()
        local onEnter = self.button and self.button:GetScript("OnEnter")
        if onEnter then onEnter(self.button) end
    end)
    l:SetScript("OnLeave", function(self)
        self.hl:Hide()
        local onLeave = self.button and self.button:GetScript("OnLeave")
        if onLeave then onLeave(self.button) else GameTooltip:Hide() end
    end)
    labels[i] = l
    return l
end

-- The menu: a heading, then one line per button (the real button on the left, its name beside it).
function ns.Layout()
    if not menu then return end
    laying = true
    local shown = ns.Shown()
    -- the first line is King Maker itself
    menu.km:ClearAllPoints()
    menu.km:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -HEAD_H)
    menu.km:SetPoint("RIGHT", menu, "RIGHT", -8, 0)
    local y = -HEAD_H - LINE_H
    for i, btn in ipairs(shown) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
        btn:SetFrameStrata("DIALOG")
        btn:SetFrameLevel(menu:GetFrameLevel() + 5)
        local l = label(i)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", menu, "TOPLEFT", 44, y - 1)
        l.button = btn
        l.text:SetText(ns.NameOf(btn))
        l:Show()
        y = y - LINE_H
    end
    for i = #shown + 1, #labels do labels[i]:Hide(); labels[i].button = nil end
    menu.empty:SetText(#shown == 0 and "No other addon buttons to show." or "")
    if #shown == 0 then y = y - LINE_H end
    menu:SetSize(MENU_W, -y + 10)
    laying = false
end

function ns.EnsureMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "MinimapKingMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    UI.Fill(menu, C.bg)
    UI.Border(menu, { 1, 1, 1, 0.10 })
    UI.GoldEdge(menu)
    menu.heading = UI.Heading(menu, "Your addons")
    menu.heading:SetPoint("TOPLEFT", 12, -12)
    menu.empty = UI.Text(menu, 12, C.dim)
    menu.empty:SetPoint("TOPLEFT", 12, -HEAD_H - LINE_H - 8)
    -- King Maker's own line: its crown icon and name; left-click opens the window, right-click the quick actions
    local km = CreateFrame("Button", nil, menu)
    km:SetHeight(LINE_H - 2)
    km:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    km.hl = UI.Fill(km, C.hover, "ARTWORK")
    km.hl:Hide()
    km.icon = km:CreateTexture(nil, "ARTWORK")
    km.icon:SetSize(22, 22)
    km.icon:SetPoint("LEFT", 3, 0)
    km.icon:SetTexture("Interface\\Icons\\INV_Crown_01")
    km.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    km.text = UI.Text(km, 12, C.accent)
    km.text:SetPoint("LEFT", 34, 0)
    km.text:SetText("King Maker")
    km:SetScript("OnClick", function(self, which)
        if which == "RightButton" then KM.QuickMenu(self) else menu:Hide(); KM.Toggle() end
    end)
    km:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("King Maker", C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:AddLine("Left-click: open the window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: quick actions", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    km:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    menu.km = km
    -- a click out in the world closes it (clicks on other windows, or on a
    -- menu one of the buttons opened, leave it open)
    menu:SetScript("OnEvent", function(self)
        local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
        if focus == nil or focus == WorldFrame then self:Hide() end
    end)
    menu:SetScript("OnShow", function(self) KM.Register(self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    if UISpecialFrames then table.insert(UISpecialFrames, "MinimapKingMenu") end -- Escape closes it
    menu:Hide() -- new frames start shown; hide it so the first Show runs OnShow
    return menu
end

-- Opens the menu under King Maker's crown (or under the minimap when the crown is hidden).
function ns.ShowMenu()
    if not ns.db then return end
    ns.EnsureMenu()
    ns.Gather() -- catch buttons made since login
    menu:ClearAllPoints()
    local crown = KM.minimapButton or KingMakerMinimapButton
    if crown and crown:IsShown() then
        menu:SetPoint("TOPRIGHT", crown, "BOTTOMLEFT", 8, 8)
    else
        menu:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
    end
    menu:Show()
end

function ns.ToggleMenu()
    if menu and menu:IsShown() then menu:Hide() else ns.ShowMenu() end
end

function ns.Menu() return menu end

---------------------------------------------------------------------------
-- The crown's quick action, and Settings: which buttons go in the menu
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "minimap-buttons", label = "Minimap buttons", order = 90, func = function() ns.ToggleMenu() end,
    shown = function() return ns.db and ns.db.gather end })

-- Every addon button there is: in the menu or left on the minimap, by name.
function ns.KnownButtons()
    local out = {}
    for _, btn in pairs(ns.known) do table.insert(out, btn) end
    table.sort(out, byName)
    return out
end

function ns.RefreshSettings() KM.Refresh("settings") end

local function settingsRows()
    learn()
    local rows = {
        { type = "text", label = "Other addons' minimap buttons, gathered into one menu that opens from the King Maker crown "
            .. "(left-click it; King Maker itself is the first line). Each line is the addon's real button, so clicks, right-clicks, tooltips and "
            .. "menus work as before. Blizzard's own buttons and map pins stay where they are." },
        { type = "check", label = "Gather minimap buttons into the menu", tip = "Off: every button goes back to the minimap.",
          get = function() return ns.db.gather end,
          set = function(v)
              ns.db.gather = v and true or false
              if ns.db.gather then ns.Gather() else ns.Release() end
          end },
        { type = "header", label = "Buttons" },
    }
    local buttons = ns.KnownButtons()
    if #buttons == 0 then
        rows[#rows + 1] = { type = "text", label = "No addon minimap buttons found yet." }
    end
    for _, btn in ipairs(buttons) do
        rows[#rows + 1] = { type = "check", label = ns.NameOf(btn), tip = "Ticked: in the menu. Unticked: stays on the minimap.",
            get = function() return not ns.db.ignore[btn:GetName()] end,
            set = function(v) ns.SetInMenu(btn, v) end }
    end
    rows[#rows + 1] = { type = "text", label = "In the menu, shift-right-click a name to leave that button on the minimap." }
    rows[#rows + 1] = { type = "header", label = "Commands" }
    rows[#rows + 1] = { type = "text", label = "/mmk   open the menu\n/mmk release   every button back on the minimap\n"
        .. "/mmk gather   take them into the menu again\n/mmk unignore   take back the buttons you left on the minimap" }
    return rows
end

KM.RegisterSettings({ id = "minimap", label = "Minimap buttons", order = 90, rows = settingsRows })

---------------------------------------------------------------------------
-- Saved data, start up, slash command
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Minimap_King data is moved in: safe twice.
function ns.InitDB()
    MinimapKingDB = MinimapKingDB or {}
    local db = MinimapKingDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    db.ignore = db.ignore or {}
    ns.db = db
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not ns.db then return end
    -- addons make their buttons at login or a little after, so look a few times
    ns.Gather()
    C_Timer.After(1, ns.Gather)
    C_Timer.After(5, ns.Gather)
    C_Timer.After(15, ns.Gather)
end)

SLASH_MINIMAPKING1 = "/mmk"
SLASH_MINIMAPKING2 = "/minimapking"
SlashCmdList.MINIMAPKING = function(msg)
    if not ns.db then return end
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd = msg:lower():match("^(%S*)")
    if cmd == "release" then
        ns.db.gather = false
        ns.Release()
        ns.RefreshSettings()
        KM.Print(ns, "Every button is back on the minimap. /mmk gather takes them in again.")
    elseif cmd == "gather" then
        ns.db.gather = true
        ns.Gather()
        KM.Print(ns, "The minimap buttons are in the menu: left-click the King Maker crown.")
    elseif cmd == "unignore" then
        wipe(ns.db.ignore)
        ns.Gather()
        KM.Print(ns, "Every button goes in the menu again.")
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        KM.OpenSettings("minimap")
    elseif cmd == "icon" or cmd == "button" then
        KM.Print(ns, "The crown on the minimap is King Maker's now: /km button shows or hides it.")
    elseif cmd == "" or cmd == "menu" then
        ns.ShowMenu()
    else
        KM.Print(ns, "/mmk   open the menu of minimap buttons")
        KM.Print(ns, "/mmk settings   choose which buttons go in it")
        KM.Print(ns, "/mmk release   put every button back on the minimap; /mmk gather takes them in again")
        KM.Print(ns, "/mmk unignore   take back the buttons you left on the minimap (shift-right-click a name in the menu)")
    end
end

MinimapKing = { ShowMenu = ns.ShowMenu, Gather = ns.Gather, Release = ns.Release, Shown = ns.Shown }

-- The crown's left-click opens this drawer (King Maker first, then every gathered addon button); with gathering
-- off it just opens the window.
function KM.CrownLeftClick()
    if ns.db and ns.db.gather then ns.ToggleMenu() else KM.Toggle() end
end
