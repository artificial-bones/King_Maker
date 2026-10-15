local _, ns = ...

-- World map pins for the mobs you track (the Track button on a mob's page).
-- Spawn points come from QuestieDB when it's installed; otherwise from where
-- you've seen and killed the mob yourself.

local MAX_PINS = 600
local pins, layer = {}, nil
-- Small round dots with a dark outline: gold for the first tracked mob, then other colors.
local COLORS = { { 1, 0.82, 0 }, { 0.3, 0.8, 1 }, { 0.6, 1, 0.3 }, { 1, 0.4, 0.8 }, { 1, 0.55, 0.1 }, { 0.8, 0.5, 1 } }
local DOT, RING = 6, 8          -- dot and outline size on screen
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Spots for one mob: { { uiMapID, x, y }, ... } (x and y from 0 to 1)
function ns.Spots(id)
    local spots = ns.QuestieSpawns(id)
    if spots and #spots > 0 then return spots, "QuestieDB" end
    spots = {}
    local m = ns.db.mobs[id]
    for _, p in ipairs(m and m.p or {}) do
        local map, x, y = p:match("^(%d+):([%d%.]+):([%d%.]+)$")
        if map then table.insert(spots, { tonumber(map), tonumber(x), tonumber(y) }) end
    end
    return spots, "seen"
end

local function canvas()
    return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
end

local function pinTooltip(self)
    local info = ns.MobInfo(self.mob)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(info.name)
    GameTooltip:AddLine("Level " .. ns.LevelText(info) .. (info.rank and (" " .. info.rank) or ""), 1, 1, 1)
    local s = ns.Value(self.mob)
    if s.gold then GameTooltip:AddLine("About " .. ns.Money(s.gold) .. " a kill (" .. s.kills .. " kills)", 1, 0.82, 0) end
    GameTooltip:AddLine("Farm King. Untrack it on its page.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function ns.UpdateMapPins()
    for _, p in ipairs(pins) do p:Hide() end
    local c = canvas()
    if not c or not WorldMapFrame:IsShown() or not ns.db then return end
    local mapID = WorldMapFrame:GetMapID()
    if not layer then
        layer = CreateFrame("Frame", nil, c)
        layer:SetAllPoints(c)
        layer:SetFrameLevel((c:GetFrameLevel() or 1) + 20)
    end
    local w, h = c:GetWidth(), c:GetHeight()
    local scale = (c.GetScale and c:GetScale()) or 1
    local n, colorIndex = 0, 0
    for id in pairs(ns.db.track) do
        colorIndex = colorIndex % #COLORS + 1
        local color = COLORS[colorIndex]
        for _, s in ipairs((ns.Spots(id))) do
            if s[1] == mapID and n < MAX_PINS then
                n = n + 1
                local p = pins[n]
                if not p then
                    p = CreateFrame("Button", nil, layer)
                    p.ring = p:CreateTexture(nil, "ARTWORK")
                    p.ring:SetPoint("CENTER")
                    p.ring:SetColorTexture(0, 0, 0, 0.85)
                    p.tex = p:CreateTexture(nil, "OVERLAY")
                    p.tex:SetPoint("CENTER")
                    p.tex:SetColorTexture(1, 1, 1, 1)
                    -- A round mask turns both squares into circles.
                    if p.CreateMaskTexture then
                        local mask = p:CreateMaskTexture()
                        mask:SetAllPoints(p)
                        mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                        p.ring:AddMaskTexture(mask)
                        local inner = p:CreateMaskTexture()
                        inner:SetAllPoints(p.tex)
                        inner:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                        p.tex:AddMaskTexture(inner)
                    end
                    p:SetScript("OnEnter", pinTooltip)
                    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    pins[n] = p
                end
                p.mob = id
                p:SetSize(RING / scale, RING / scale)
                p.ring:SetSize(RING / scale, RING / scale)
                p.tex:SetSize(DOT / scale, DOT / scale)
                p.tex:SetColorTexture(color[1], color[2], color[3], 1)
                p:ClearAllPoints()
                p:SetPoint("CENTER", layer, "TOPLEFT", s[2] * w, -s[3] * h)
                p:Show()
            end
        end
    end
end

local hooked = false
local function hook()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() ns.UpdateMapPins() end)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() ns.UpdateMapPins() end)
    end
    -- Zooming changes the canvas scale: keep pins the same size on screen.
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function() ns.UpdateMapPins() end)
    end
end

function ns.SetTracked(id, on)
    ns.db.track[id] = on and true or nil
    hook()
    ns.UpdateMapPins()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() pcall(hook) end)
