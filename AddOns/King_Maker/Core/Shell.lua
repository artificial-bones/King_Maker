local _, KM = ...

-- The King Maker window: a sidebar of groups and pages, a header with the page title, and the one minimap button.
-- Modules register pages; a page is built the first time it is opened and refreshed every time it is shown.
--
--   KM.RegisterGroup{ id, label, order }
--   KM.RegisterPage{ id, group, label, icon, order, title, subtitle = string | fn, badge = fn,
--                    build = fn(container), refresh = fn(container), hide = fn(container) }
--   KM.Show(id)            opens the window on that page
--   KM.Toggle(show)        nil toggles
--   KM.Refresh(id)         redraws the current page (only when it is page id, if given)
--   KM.IsShown(id)         true when the window is open (on page id, if given)
--   KM.RegisterQuickAction{ id, label, order, func, shown = fn }   right-click menu of the minimap button
--   KM.RegisterTooltip(fn(tooltip))                                 lines in the minimap button's tooltip
--   KM.RegisterStatus(fn() -> text)                                 lines in the sidebar status box
-- The same functions are on the public KingMaker table, so another addon (Oracle) can add its own pages.

local UI = KM.UI
local C = UI.C
local W, H, SIDE = 1000, 640, 200
local NAV_H, GROUP_H = 28, 22

local frame, content, titleFS, subFS, statusFS, navArea
local pages, groups = {}, {}
local current
local actions, tips, statuses = {}, {}, {}

local function db() return KingMakerDB and KingMakerDB.ui end

function KM.RegisterGroup(g)
    groups[g.id] = groups[g.id] or { pages = {} }
    for k, v in pairs(g) do groups[g.id][k] = v end
    if frame then KM.LayoutNav() end
end

function KM.RegisterPage(p)
    p.group = p.group or "other"
    if not groups[p.group] then KM.RegisterGroup({ id = p.group, label = p.group, order = 90 }) end
    pages[p.id] = p
    table.insert(groups[p.group].pages, p)
    table.sort(groups[p.group].pages, function(a, b) return (a.order or 50) < (b.order or 50) end)
    if frame then KM.LayoutNav() end
end

function KM.RegisterQuickAction(a) table.insert(actions, a); table.sort(actions, function(x, y) return (x.order or 50) < (y.order or 50) end) end
function KM.RegisterTooltip(fn) table.insert(tips, fn) end
function KM.RegisterStatus(fn) table.insert(statuses, fn) end

-- Home page tiles and notes (drawn by Home.lua): KM.RegisterHomeTile{ id, order, get = fn() -> label, value, sub, color }
KM.homeTiles, KM.homeNotes = {}, {}
function KM.RegisterHomeTile(t) table.insert(KM.homeTiles, t); table.sort(KM.homeTiles, function(a, b) return (a.order or 50) < (b.order or 50) end) end
function KM.RegisterHomeNote(fn) table.insert(KM.homeNotes, fn) end

KM.groups, KM.pages, KM.QuickActions = groups, pages, actions

-- Default groups. Modules may add more.
KM.RegisterGroup({ id = "home", label = "King Maker", order = 0 })
KM.RegisterGroup({ id = "ah", label = "Auction House", order = 10 })
KM.RegisterGroup({ id = "craft", label = "Crafting", order = 20 })
KM.RegisterGroup({ id = "gold", label = "Gold", order = 30 })
KM.RegisterGroup({ id = "farm", label = "Farming", order = 40 })
KM.RegisterGroup({ id = "char", label = "Characters", order = 50 })
KM.RegisterGroup({ id = "system", label = "", order = 100 })

local function sortedGroups()
    local list = {}
    for id, g in pairs(groups) do if #g.pages > 0 then g.id = g.id or id; list[#list + 1] = g end end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    return list
end

local function savePos()
    local point, _, _, x, y = frame:GetPoint(1)
    db().pos = { point = point, x = x, y = y }
end

local function navButton(p)
    local b = CreateFrame("Button", nil, navArea)
    b:SetHeight(NAV_H - 2)
    b.sel = UI.Fill(b, C.sel, "ARTWORK")
    b.sel:Hide()
    b.hl = UI.Fill(b, C.hover, "ARTWORK")
    b.hl:Hide()
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetTexture(UI.WHITE)
    b.bar:SetPoint("LEFT", 0, 0)
    b.bar:SetSize(3, 16)
    b.bar:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    b.bar:Hide()
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 12, 0)
    b.icon:SetTexture(p.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = UI.Text(b, 12, C.muted)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 9, 0)
    b.label:SetPoint("RIGHT", -34, 0)
    b.label:SetText(p.label)
    b.badge = UI.Text(b, 10, C.accent, "RIGHT")
    b.badge:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnEnter", function(self) if current ~= p.id then self.hl:Show() end end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    b:SetScript("OnClick", function() UI.Click(); KM.Show(p.id) end)
    p.nav = b
    return b
end

local function groupHeader(g)
    local h = CreateFrame("Button", nil, navArea)
    h:SetHeight(GROUP_H)
    h.fs = UI.Text(h, 9, C.dim)
    h.fs:SetPoint("LEFT", 12, -2)
    h.arrow = UI.Text(h, 9, C.dim, "RIGHT")
    h.arrow:SetPoint("RIGHT", -10, -2)
    h:SetScript("OnEnter", function(self) self.fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    h:SetScript("OnLeave", function(self) self.fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end)
    h:SetScript("OnClick", function()
        local col = db().collapsed
        col[g.id] = not col[g.id] or nil
        UI.Click()
        KM.LayoutNav()
    end)
    g.header = h
    return h
end

-- Lays the sidebar out top to bottom; collapsed groups hide their pages; the wheel scrolls when it overflows.
function KM.LayoutNav()
    if not frame then return end
    local y = navArea.scroll or 0          -- scrolled down = the list moves up
    local col = db().collapsed
    for _, g in ipairs(sortedGroups()) do
        local label = g.label or ""
        if label ~= "" then
            local h = g.header or groupHeader(g)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h:SetPoint("TOPRIGHT", 0, y)
            h.fs:SetText(label:upper())
            h.arrow:SetText(col[g.id] and "+" or "-")
            h:Show()
            y = y - GROUP_H
        end
        for _, p in ipairs(g.pages) do
            local b = p.nav or navButton(p)
            if col[g.id] and current ~= p.id then
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 8, y)
                b:SetPoint("TOPRIGHT", -8, y)
                b:Show()
                y = y - NAV_H
            end
        end
    end
    navArea.total = (navArea.scroll or 0) - y   -- height of the whole list
end

local function create()
    local u = db()
    frame = CreateFrame("Frame", "KingMakerFrame", UIParent)
    frame:SetSize(W, H)
    if u.pos and u.pos.point then frame:SetPoint(u.pos.point, UIParent, u.pos.point, u.pos.x, u.pos.y) else frame:SetPoint("CENTER") end
    frame:SetScale(u.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "KingMakerFrame") end
    UI.Fill(frame, C.bg)
    UI.Border(frame, { 1, 1, 1, 0.10 })
    UI.GoldEdge(frame)

    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 1, -3)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDE)
    UI.Fill(side, C.sidebar)
    local sep = side:CreateTexture(nil, "BORDER")
    sep:SetTexture(UI.WHITE)
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetWidth(1)
    sep:SetVertexColor(1, 1, 1, 0.06)

    local crown = side:CreateTexture(nil, "ARTWORK")
    crown:SetSize(32, 32)
    crown:SetPoint("TOPLEFT", 16, -16)
    crown:SetTexture("Interface\\Icons\\INV_Crown_01")
    crown:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = CreateFrame("Frame", nil, side)
    ring:SetPoint("TOPLEFT", crown, -1, 1)
    ring:SetPoint("BOTTOMRIGHT", crown, 1, -1)
    UI.Border(ring, { C.accent[1], C.accent[2], C.accent[3], 0.6 })
    local brand = UI.Text(side, 17, C.accent)
    brand:SetPoint("TOPLEFT", crown, "TOPRIGHT", 10, -1)
    brand:SetText("KING MAKER")
    local tag = UI.Text(side, 10, C.muted)
    tag:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
    tag:SetText("v" .. KM.version .. "  |cff6b6b70WoW Forever|r")

    navArea = CreateFrame("Frame", nil, side)
    navArea:SetPoint("TOPLEFT", 0, -62)
    navArea:SetPoint("BOTTOMRIGHT", 0, 74)
    if navArea.SetClipsChildren then navArea:SetClipsChildren(true) end
    navArea:EnableMouseWheel(true)
    navArea.scroll = 0
    navArea:SetScript("OnMouseWheel", function(self, d)
        local room = (self.total or 0) - (self:GetHeight() or 0)
        self.scroll = math.max(0, math.min(math.max(0, room), (self.scroll or 0) - d * NAV_H * 2))
        KM.LayoutNav()
    end)

    local status = CreateFrame("Frame", nil, side)
    status:SetPoint("BOTTOMLEFT", 10, 10)
    status:SetPoint("BOTTOMRIGHT", -10, 10)
    status:SetHeight(58)
    UI.Fill(status, { 0, 0, 0, 0.25 })
    UI.Border(status)
    statusFS = UI.Para(status, 10, C.muted, SIDE - 36)
    statusFS:SetPoint("TOPLEFT", 8, -8)

    titleFS = UI.Text(frame, 18, C.text)
    titleFS:SetPoint("TOPLEFT", side, "TOPRIGHT", 22, -18)
    subFS = UI.Text(frame, 11, C.muted)
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetPoint("RIGHT", frame, "RIGHT", -60, 0)
    local close = UI.CloseButton(frame, function() KM.Toggle(false) end)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -12, -14)

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT", 18, -64)
    content:SetPoint("BOTTOMRIGHT", -18, 16)
    KM.content = content

    frame:SetScript("OnShow", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        KM.Refresh()
    end)
    frame:SetScript("OnHide", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
        local p = pages[current]
        if p and p.hide and p.container then KM.Safe(p.hide, p.container) end
    end)
    frame:Hide()
    KM.frame = frame
    KM.LayoutNav()
end

local function statusText()
    local lines = {}
    for _, fn in ipairs(statuses) do
        local s = KM.Safe(fn)
        if s and s ~= "" then lines[#lines + 1] = s end
        if #lines >= 4 then break end
    end
    statusFS:SetText(#lines > 0 and table.concat(lines, "\n") or "")
end

local function firstPage()
    for _, g in ipairs(sortedGroups()) do if g.pages[1] then return g.pages[1] end end
end

function KM.Show(id)
    if not db() then return end
    if not frame then create() end
    local p = pages[id] or pages[db().page] or firstPage()
    if not p then return end
    local prev = pages[current]
    if prev and prev ~= p and prev.hide and prev.container then KM.Safe(prev.hide, prev.container) end
    for _, q in pairs(pages) do
        if q.container then q.container:Hide() end
        if q.nav then
            q.nav.sel:Hide(); q.nav.bar:Hide()
            q.nav.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        end
    end
    current = p.id
    db().page = p.id
    KM.LayoutNav()
    if not p.container then
        p.container = CreateFrame("Frame", nil, content)
        p.container:SetAllPoints(content)
        KM.Safe(p.build, p.container)
    end
    p.nav.sel:Show(); p.nav.bar:Show(); p.nav.hl:Hide()
    p.nav.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    titleFS:SetText(p.title or p.label)
    p.container:Show()
    if not frame:IsShown() then frame:Show() end
    KM.Refresh()
end

function KM.Refresh(id)
    if not frame or not frame:IsShown() or not db() then return end
    if id and id ~= current then return end
    statusText()
    for _, p in pairs(pages) do
        if p.nav then p.nav.badge:SetText(p.badge and KM.Safe(p.badge) or "") end
    end
    local p = pages[current]
    if p then
        subFS:SetText(type(p.subtitle) == "function" and (KM.Safe(p.subtitle) or "") or (p.subtitle or ""))
        if p.container and p.refresh then KM.Safe(p.refresh, p.container) end
    end
end

function KM.Toggle(show)
    if not db() then return end
    if not frame then create() end
    if show == nil then show = not frame:IsShown() end
    if show then KM.Show(current or db().page) else frame:Hide() end
end

function KM.IsShown(id)
    if not frame or not frame:IsShown() then return false end
    return id == nil or id == current
end

function KM.CurrentPage() return current end

function KM.SetScale(s)
    db().scale = s
    if frame then frame:SetScale(s) end
end

---------------------------------------------------------------------------
-- The minimap button: left-click opens the window, right-click the quick actions
---------------------------------------------------------------------------

local mini
local function place()
    local angle = math.rad(db().buttonAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function KM.QuickMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then KM.Toggle() return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("King Maker")
        for _, a in ipairs(actions) do
            if not a.shown or KM.Safe(a.shown) then
                root:CreateButton(type(a.label) == "function" and a.label() or a.label, function() KM.Safe(a.func) end)
            end
        end
        root:CreateButton("Settings", function() KM.Show("settings") end)
    end)
end

function KM.UpdateMinimapButton()
    if not db() or not Minimap then return end
    if not mini then
        mini = CreateFrame("Button", "KingMakerMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mini:RegisterForDrag("LeftButton")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local back = mini:CreateTexture(nil, "BACKGROUND")
        back:SetSize(24, 24)
        back:SetPoint("CENTER", 0, 1)
        back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        local icon = mini:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Crown_01")
        local mask = mini:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        local border = mini:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetScript("OnClick", function(self, which)
            GameTooltip:Hide()
            if which == "RightButton" then KM.QuickMenu(self)
            elseif KM.CrownLeftClick then KM.CrownLeftClick(self)   -- the button drawer (Modules\Minimap)
            else KM.Toggle() end
        end)
        mini:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                db().buttonAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
                place()
            end)
        end)
        mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        mini:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("King Maker", C.accent[1], C.accent[2], C.accent[3])
            for _, fn in ipairs(tips) do KM.Safe(fn, GameTooltip) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(KM.CrownLeftClick and "Left-click: King Maker and your addon buttons" or "Left-click: open", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: quick actions", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", function() if mini then place() end end) end
        KM.minimapButton = mini
    end
    place()
    mini:SetShown(db().button)
end

-- Names trickle in one item at a time; redraw the open page once they've settled.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
ev:SetScript("OnEvent", function()
    if not pending and frame and frame:IsShown() then
        pending = true
        C_Timer.After(0.5, function() pending = false; KM.Refresh() end)
    end
end)

for _, name in ipairs({ "RegisterGroup", "RegisterPage", "Show", "Toggle", "Refresh", "IsShown", "RegisterQuickAction",
    "RegisterTooltip", "RegisterStatus", "RegisterHomeTile", "RegisterHomeNote" }) do
    KingMaker[name] = KM[name]
end
