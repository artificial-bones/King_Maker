local addonName, ns = ...

-- Crown King: one minimap button for the whole King suite.
--
-- Each King addon still makes its own minimap button. Crown King hides those
-- buttons and lists them in a drop-down under a crown instead. A click on a
-- line is a click on that addon's button (left or right), and hovering a line
-- shows that addon's own tooltip. Nothing in the other addons changes:
-- "/crown release" puts their buttons back on the minimap.

ns.KINGS = {
    { name = "Scanner King", button = "ScannerKingMinimapButton", icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    { name = "Market King", button = "MarketKingMinimapButton", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { name = "Farm King", button = "FarmKingMinimapButton", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
    { name = "Gather King", button = "GatherKingMinimapButton", icon = "Interface\\Icons\\Trade_Mining" },
    { name = "Mail King", button = "MailKingMinimapButton", icon = "Interface\\Icons\\INV_Letter_15" },
    { name = "Quest King", button = "QuestKingMinimapButton", icon = "Interface\\Icons\\INV_Misc_Note_02" },
    { name = "Skillup King", button = "SkillupKingMinimapButton", icon = "Interface\\Icons\\INV_Misc_Book_11" },
}

local DEFAULTS = { gather = true, angle = 200 }

-- Crowns to pick from with "/crown icon". Newer ones may be missing from the
-- client, so only those the game can find count; the first found is the default.
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

-- The crowns this client has.
function ns.Crowns()
    local out = {}
    for _, c in ipairs(ns.CROWNS) do
        if not GetFileIDFromPath or GetFileIDFromPath(c[2]) then table.insert(out, c) end
    end
    if #out == 0 then out[1] = ns.CROWNS[#ns.CROWNS - 1] end
    return out
end

-- The crown in use: the one you picked, else the first the client has.
function ns.Crown()
    local have = ns.Crowns()
    for _, c in ipairs(have) do if c[2] == ns.db.icon then return c end end
    return have[1]
end

function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Crown King|r: " .. msg) end

---------------------------------------------------------------------------
-- Taking the buttons in
---------------------------------------------------------------------------

local hooked = {}  -- button -> true once we watch it
local wanted = {}  -- button -> whether its addon wants it shown

local function keepHidden(btn)
    wanted[btn] = btn:IsShown()
    if ns.db.gather then btn:Hide() end
end

-- Hide every King button we can find, and keep them hidden when their addons show them again.
function ns.Gather()
    for _, k in ipairs(ns.KINGS) do
        local btn = _G[k.button]
        if btn then
            if not hooked[btn] then
                hooked[btn] = true
                wanted[btn] = btn:IsShown()
                hooksecurefunc(btn, "Show", keepHidden)
                hooksecurefunc(btn, "SetShown", keepHidden)
            end
            if ns.db.gather then btn:Hide() end
        end
    end
end

-- Put the buttons back the way their addons want them.
function ns.Release()
    for btn in pairs(hooked) do btn:SetShown(wanted[btn]) end
end

-- The King addons that are loaded: { king, button }.
function ns.Installed()
    local out = {}
    for _, k in ipairs(ns.KINGS) do
        local btn = _G[k.button]
        if btn and btn:GetScript("OnClick") then table.insert(out, { king = k, button = btn }) end
    end
    return out
end

---------------------------------------------------------------------------
-- The drop-down
---------------------------------------------------------------------------

local menu, crown
local lines = {}
ns.lines = lines
local LINE_H, MENU_W = 22, 170

local function closeMenu() if menu then menu:Hide() end end

local function makeLine(i)
    local l = CreateFrame("Button", nil, menu)
    l:SetSize(MENU_W - 16, LINE_H)
    l:SetPoint("TOPLEFT", 8, -8 - (i - 1) * LINE_H)
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(18, 18)
    l.icon:SetPoint("LEFT", 2, 0)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
    l:SetScript("OnClick", function(self, which)
        local onClick = self.button and self.button:GetScript("OnClick")
        closeMenu()
        if onClick then onClick(self, which) end
    end)
    l:SetScript("OnEnter", function(self)
        local onEnter = self.button and self.button:GetScript("OnEnter")
        if onEnter then onEnter(self) end
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return l
end

function ns.ShowMenu()
    if not menu then
        menu = CreateFrame("Frame", "CrownKingMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        if menu.SetBackdrop then
            menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        end
        -- a click anywhere else closes it
        menu:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not (crown and crown:IsMouseOver()) then self:Hide() end
        end)
        menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
        table.insert(UISpecialFrames, "CrownKingMenu") -- Escape closes it
        menu:Hide() -- new frames start shown; hide it so the first Show runs OnShow
    end
    ns.Gather()
    local kings = ns.Installed()
    for i, k in ipairs(kings) do
        local l = lines[i] or makeLine(i)
        lines[i] = l
        l.button = k.button
        l.icon:SetTexture(k.king.icon)
        l.text:SetText(k.king.name)
        l:Show()
    end
    for i = #kings + 1, #lines do lines[i]:Hide() end
    menu.empty = menu.empty or menu:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    menu.empty:SetPoint("TOPLEFT", 12, -12)
    menu.empty:SetText(#kings == 0 and "No King addons loaded." or "")
    menu:SetSize(MENU_W, 16 + math.max(#kings, 1) * LINE_H)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", crown, "BOTTOMLEFT", 8, 8)
    menu:Show()
end

function ns.ToggleMenu()
    if menu and menu:IsShown() then closeMenu() else ns.ShowMenu() end
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
    crown = CreateFrame("Button", "CrownKingMinimapButton", Minimap)
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
        closeMenu()
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
        GameTooltip:AddLine("Crown King")
        local names = {}
        for _, k in ipairs(ns.Installed()) do table.insert(names, k.king.name) end
        GameTooltip:AddLine(#names > 0 and table.concat(names, ", ") or "No King addons loaded.", 1, 1, 1, true)
        GameTooltip:AddLine("Click: the King menu. Drag: move this button.", 0.8, 0.8, 0.8)
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
        CrownKingDB = CrownKingDB or {}
        for k, v in pairs(DEFAULTS) do if CrownKingDB[k] == nil then CrownKingDB[k] = v end end
        ns.db = CrownKingDB
    elseif event == "PLAYER_LOGIN" then
        createCrown()
        position()
        -- the Kings make their buttons at login too, so look now and again shortly after
        ns.Gather()
        C_Timer.After(1, ns.Gather)
        C_Timer.After(5, ns.Gather)
    end
end)

SLASH_CROWNKING1 = "/crown"
SLASH_CROWNKING2 = "/ck"
SlashCmdList.CROWNKING = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "release" then
        ns.db.gather = false
        ns.Release()
        ns.Print("The King buttons are back on the minimap. /crown gather puts them in the crown again.")
    elseif msg == "gather" then
        ns.db.gather = true
        ns.Gather()
        ns.Print("The King buttons are in the crown.")
    elseif msg:match("^icon") then
        local have, n = ns.Crowns(), tonumber(msg:match("^icon%s+(%d+)"))
        if not n then -- next one
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
        ns.Print("Crown: " .. c[1] .. ". /crown icon again for the next one, or /crown icon <number>: " .. table.concat(list, ", "))
    elseif msg == "" or msg == "menu" then
        ns.ShowMenu()
    else
        ns.Print("/crown opens the menu. /crown icon changes the crown. /crown release puts the King buttons back on the minimap, /crown gather takes them in again.")
    end
end

CrownKing = { ShowMenu = ns.ShowMenu, Gather = ns.Gather, Release = ns.Release, Installed = ns.Installed }
