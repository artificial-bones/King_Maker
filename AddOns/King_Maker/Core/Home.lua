local _, KM = ...

-- Home: the first page. A row of stat tiles that modules provide, the quick actions as buttons, and short notes.
--
--   KM.RegisterHomeTile{ id, order, get = fn() -> label, value, sub, color }   (return nil to hide the tile)
--   KM.RegisterHomeNote(fn() -> text | nil)                                    (a line under the tiles)

local UI = KM.UI
local C = UI.C
local tiles, notes = KM.homeTiles, KM.homeNotes   -- registries live in Shell.lua so modules can register at load

local TILE_W, TILE_H, PER_ROW = 182, 66, 4
local tileFrames, actionButtons, noteFS = {}, {}, nil

local function build(c)
    c.tiles = CreateFrame("Frame", nil, c)
    c.tiles:SetPoint("TOPLEFT")
    c.tiles:SetPoint("TOPRIGHT")
    c.tiles:SetHeight(2 * (TILE_H + 10))
    c.actHead = UI.Heading(c, "Quick actions")
    c.actions = CreateFrame("Frame", nil, c)
    c.actions:SetPoint("TOPLEFT", c.actHead, "BOTTOMLEFT", 0, -8)
    c.actions:SetPoint("RIGHT", c, "RIGHT")
    c.actions:SetHeight(64)
    c.noteHead = UI.Heading(c, "Notes")
    c.noteHead:SetPoint("TOPLEFT", c.actions, "BOTTOMLEFT", 0, -14)
    noteFS = UI.Para(c, 12, C.muted, 720)
    noteFS:SetPoint("TOPLEFT", c.noteHead, "BOTTOMLEFT", 0, -8)
end

local function refresh(c)
    local shown = 0
    for _, t in ipairs(tiles) do
        local label, value, sub, color = KM.Safe(t.get)
        if label then
            shown = shown + 1
            local f = tileFrames[shown]
            if not f then
                f = UI.Tile(c.tiles, TILE_W, TILE_H)
                tileFrames[shown] = f
            end
            local row, col = math.floor((shown - 1) / PER_ROW), (shown - 1) % PER_ROW
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", col * (TILE_W + 10), -row * (TILE_H + 10))
            f:Set(label, value, sub, color)
            f:Show()
        end
    end
    for i = shown + 1, #tileFrames do tileFrames[i]:Hide() end
    local rows = math.max(1, math.ceil(shown / PER_ROW))
    c.tiles:SetHeight(rows * (TILE_H + 10))
    c.actHead:ClearAllPoints()
    c.actHead:SetPoint("TOPLEFT", c.tiles, "BOTTOMLEFT", 0, -6)

    -- Quick actions as buttons, four to a row.
    local n = 0
    for _, a in ipairs(KM.QuickActions or {}) do
        if not a.shown or KM.Safe(a.shown) then
            n = n + 1
            local b = actionButtons[n]
            if not b then
                b = UI.Button(c.actions, "", TILE_W, 26, function(self) KM.Safe(self.action.func); KM.Refresh() end)
                actionButtons[n] = b
            end
            b.action = a
            b:SetLabel(type(a.label) == "function" and a.label() or a.label)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ((n - 1) % PER_ROW) * (TILE_W + 10), -math.floor((n - 1) / PER_ROW) * 32)
            b:Show()
        end
    end
    for i = n + 1, #actionButtons do actionButtons[i]:Hide() end
    c.actions:SetHeight(math.max(1, math.ceil(n / PER_ROW)) * 32)

    local lines = {}
    for _, fn in ipairs(notes) do
        local s = KM.Safe(fn)
        if s and s ~= "" then lines[#lines + 1] = s end
    end
    if #lines == 0 then lines[1] = "Open the auction house and press Deep Scan to fill every page with prices." end
    noteFS:SetText(table.concat(lines, "\n\n"))
end

KM.RegisterPage({ id = "home", group = "home", label = "Home", icon = "Interface\\Icons\\INV_Crown_01", order = 1,
    title = "King Maker", subtitle = function()
        local name = UnitName and UnitName("player")
        return name and ("Welcome back, " .. name .. ".") or ""
    end, build = build, refresh = refresh })
