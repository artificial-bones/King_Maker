local _, ns = ...

-- Minimap button: left-click opens settings, right-click picks a profile.
-- Drag it to move it around the minimap edge.

local button

local function position()
    local angle = math.rad(ns.db.ui.buttonAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.ui.buttonAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    position()
end

local function profileMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Print("Profiles: " .. table.concat(ns.ProfileNames(), ", ") .. ". /gt profile <name> switches.")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Gather King profile")
        for _, name in ipairs(ns.ProfileNames()) do
            root:CreateRadio(name,
                function() return ns.ActiveProfile() == name end,
                function() ns.UseProfile(name) end)
        end
        root:CreateDivider()
        root:CreateButton("Open settings", function() ns.OpenSettings() end)
    end)
end

local function create()
    button = CreateFrame("Button", "GatherKingMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    local mask = button:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(self, which)
        if which == "RightButton" then profileMenu(self) else ns.OpenSettings() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Gather King")
        GameTooltip:AddLine("Profile: " .. ns.ActiveProfile(), 1, 1, 1)
        GameTooltip:AddLine("Left-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: switch profile", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if not button then create() end
    position()
    button:SetShown(ns.db.ui.button)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() ns.UpdateMinimapButton() end)
