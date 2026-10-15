local _, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local REF = "gather_king"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING = "Interface\\AddOns\\gather_king\\Textures\\ring"

local pool = {}
local active = {}

local function onEnter(self)
    local node = self.node
    local info = ns.TYPES[node.t]
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(node.n or info.label, info.color[1], info.color[2], info.color[3])
    if node.n then GameTooltip:AddLine(info.label, 1, 1, 1) end
    GameTooltip:AddLine(ns.MapName(self.mapID) .. "  " .. ns.FormatCoords(node.x, node.y), 0.8, 0.8, 0.8)
    if node.from then
        GameTooltip:AddLine("Shared by " .. node.from, 0.4, 0.8, 1)
    end
    if node.lastHarvest then
        local mins = math.floor((time() - node.lastHarvest) / 60)
        GameTooltip:AddLine("Harvested " .. (mins < 1 and "just now" or (mins .. " min ago")), 0.8, 0.8, 0.8)
    end
    local total, mine, items = ns.CombinedStats(node)
    if total > 0 then
        local who = (mine == total) and "" or (" (you: " .. mine .. ", guild: " .. (total - mine) .. ")")
        GameTooltip:AddLine("Harvested " .. total .. " time" .. (total == 1 and "" or "s") .. who, 1, 0.82, 0)
        local worth, oldest, priced = 0, nil, false
        for i, it in ipairs(items) do
            local price, t = ns.Price(it.id)
            if price then
                worth = worth + price * it.q / total
                priced = true
                if t and (not oldest or t < oldest) then oldest = t end
            end
            if i <= 8 then
                local pct = it.n / total * 100
                local right = pct >= 20 and string.format("%d%%  avg %.1f", pct + 0.5, it.q / it.n)
                    or string.format("%d%%  (%d of %d)", pct + 0.5, it.n, total)
                local left = "  " .. ns.ItemName(it.id) .. (price and ("  " .. ns.FormatMoney(price)) or "")
                GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 0.8, 0.8, 0.8)
            end
        end
        if priced then
            GameTooltip:AddLine("Worth about " .. ns.FormatMoney(worth) .. " per harvest", 0.4, 1, 0.4)
            GameTooltip:AddLine("Prices from " .. ns.PriceAge(oldest), 0.5, 0.5, 0.5)
        end
    elseif node.item then
        local price, t = ns.Price(node.item)
        if price then
            GameTooltip:AddLine(ns.ItemName(node.item) .. ": " .. ns.FormatMoney(price) .. " each", 1, 1, 1)
            GameTooltip:AddLine("Price from " .. ns.PriceAge(t), 0.5, 0.5, 0.5)
        end
    end
    GameTooltip:AddLine("Right-click for delete options", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function onLeave(self)
    self:SetAlpha(self.stateAlpha or self.baseAlpha or 1)
    GameTooltip:Hide()
end

local function showMenu(pin)
    local mapID, node = pin.mapID, pin.node
    local label = node.n or ns.TYPES[node.t].label
    MenuUtil.CreateContextMenu(pin, function(_, root)
        root:CreateTitle(label .. "  " .. ns.FormatCoords(node.x, node.y))
        root:CreateButton("Delete this node", function() ns.RemoveNode(mapID, node) end)
    end)
end

local function onMouseUp(self, button)
    if button ~= "RightButton" or not self.node then return end
    GameTooltip:Hide()
    if IsShiftKeyDown() or not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.RemoveNode(self.mapID, self.node)
    else
        showMenu(self)
    end
end

local function newPin()
    local f = CreateFrame("Frame")
    f:SetSize(16, 16)
    -- Round icon inside a colored ring (the ring color is the profession).
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetAllPoints()
    f.ringMask = f:CreateMaskTexture()
    f.ringMask:SetAllPoints(f.ring)
    f.ringMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.ring:AddMaskTexture(f.ringMask)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.iconMask = f:CreateMaskTexture()
    f.iconMask:SetAllPoints(f.icon)
    f.iconMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.icon:AddMaskTexture(f.iconMask)
    -- Minimap style: just a colored ring with an empty middle, so the game's
    -- own node dot shows through when the node is up.
    f.hollow = f:CreateTexture(nil, "ARTWORK")
    f.hollow:SetAllPoints()
    f.hollow:SetTexture(RING)
    f:EnableMouse(true)
    f:SetScript("OnEnter", onEnter)
    f:SetScript("OnLeave", onLeave)
    f:SetScript("OnMouseUp", onMouseUp)
    return f
end

local function acquire(mapID, node, size, alpha, ringOnly)
    local f = table.remove(pool) or newPin()
    local c = ns.TYPES[node.t].color
    f.mapID, f.node, f.isMinimap = mapID, node, ringOnly
    f:SetSize(size, size)
    f.baseAlpha = alpha or 1
    f:SetAlpha(f.baseAlpha)
    if ringOnly then
        f.hollow:SetVertexColor(c[1], c[2], c[3], 1)
        f.hollow:Show()
        f.ring:Hide()
        f.icon:Hide()
    else
        f.ring:SetColorTexture(c[1], c[2], c[3], 1)
        f.icon:SetTexture(ns.NodeIcon(node))
        f.hollow:Hide()
        f.ring:Show()
        f.icon:Show()
    end
    f:Show()
    table.insert(active, f)
    return f
end

---------------------------------------------------------------------------
-- Live state: faded while respawning, hidden on the minimap when you're at it
---------------------------------------------------------------------------

local NEAR_YARDS = 12
local GRAY = 0.55

local function isRecent(node, s)
    return node.lastHarvest and (s.fadeMinutes or 0) > 0
        and time() - node.lastHarvest < s.fadeMinutes * 60
end

local function applyState(f, s)
    local node = f.node
    if not node then return end
    local recent = isRecent(node, s)
    local c = recent and { GRAY, GRAY, GRAY } or ns.TYPES[node.t].color
    if f.isMinimap then
        f.hollow:SetVertexColor(c[1], c[2], c[3], 1)
    else
        f.ring:SetColorTexture(c[1], c[2], c[3], 1)
        f.icon:SetDesaturated(recent and true or false)
    end
    local alpha = f.baseAlpha * (recent and 0.4 or 1)
    if f.isMinimap and s.hideNear then
        local _, dist = HBDPins:GetVectorToIcon(f)
        if dist and dist < NEAR_YARDS then alpha = 0 end
    end
    f.stateAlpha = alpha
    if not f:IsMouseOver() then f:SetAlpha(alpha) end
    f:EnableMouse(alpha > 0)
end

function ns.UpdatePinStates()
    if not ns.db then return end
    local s = ns.S()
    for _, f in ipairs(active) do applyState(f, s) end
end

local function releaseAll()
    HBDPins:RemoveAllWorldMapIcons(REF)
    HBDPins:RemoveAllMinimapIcons(REF)
    for i = #active, 1, -1 do
        local f = active[i]
        f:Hide()
        f:ClearAllPoints()
        f.node, f.mapID = nil, nil
        table.insert(pool, f)
        active[i] = nil
    end
end

function ns.Refresh()
    if not ns.db then return end
    releaseAll()
    local s = ns.S()
    for mapID, list in pairs(ns.db.nodes) do
        for _, node in ipairs(list) do
            if ns.TYPES[node.t] and ns.Visible(node) then
                local wm = acquire(mapID, node, s.size)
                HBDPins:AddWorldMapIconMap(REF, wm, mapID, node.x, node.y)
                if s.minimap then
                    local mm = acquire(mapID, node, math.max(12, s.size - 2), s.minimapAlpha, true)
                    HBDPins:AddMinimapIconMap(REF, mm, mapID, node.x, node.y, false, false)
                end
            end
        end
    end
    ns.UpdatePinStates()
end

-- Twice a second: fade/unfade respawning nodes and hide the ring you're standing at.
local ticker = CreateFrame("Frame")
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
    C_Timer.NewTicker(0.5, ns.UpdatePinStates)
end)
