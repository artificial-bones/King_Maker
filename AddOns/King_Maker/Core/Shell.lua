local _, KM = ...

-- The King Maker window: a sidebar of groups and pages, a header with the page title, and the one minimap button.
-- Modules register pages; a page is built the first time it is opened and refreshed every time it is shown.
--
--   KM.RegisterGroup{ id, label, order }
--   KM.RegisterPage{ id, group, label, icon, order, title, subtitle = string | fn, badge = fn, crownBadge = bool,
--                    build = fn(container), refresh = fn(container), hide = fn(container) }
--     badge() returns a string or number (gold text on the sidebar button, as always), or a count badge
--     { count = n, color = "red" | "gold", tip = "..." }: a round disc with the number (9+ above nine), summed on the
--     group header while the group is collapsed, and on the minimap crown when the page sets crownBadge = true.
--   KM.RefreshBadges()     works every badge out again and draws it (window open or not: the crown shows anyway)
--   KM.Show(id)            opens the window on that page
--   KM.Toggle(show)        nil toggles
--   KM.Refresh(id)         redraws the current page (only when it is page id, if given)
--   KM.IsShown(id)         true when the window is open (on page id, if given)
--   KM.RegisterQuickAction{ id, label, order, func, shown = fn }   right-click menu of the minimap button
--   KM.RegisterTooltip(fn(tooltip))                                 lines in the minimap button's tooltip
--   KM.RegisterStatus(fn() -> text)                                 lines in the sidebar status box
--   KM.SetScale(s) -> s    window zoom, clamped to KM.MinScale() .. KM.MaxScale() (what fits on the screen)
--   KM.ResetWindow()       zoom 100%, back in the middle of the screen
-- The same functions are on the public KingMaker table, so another addon (Oracle) can add its own pages.

local UI = KM.UI
local C = UI.C
local W, H, SIDE = 1000, 640, 200
local NAV_H, GROUP_H = 28, 22

local frame, content, titleFS, subFS, statusFS, statusBox, navArea
local mini              -- the minimap crown (made at login, further down)
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

-- Home page tiles, notes and cards (drawn by Home.lua, which says what each kind returns):
--   KM.RegisterHomeTile{ id, order, get = fn() -> label, value, sub, color, tip, page, spark }
--   KM.RegisterHomeNote(fn() -> text)
--   KM.RegisterHomeCard{ kind = "attention" | "chart" | "income" | "top" | "stats", id, order, get, ... }
-- A tile or card registered again with the same id replaces the old one.
KM.homeTiles, KM.homeNotes, KM.homeCards = {}, {}, {}
local function byOrder(a, b) return (a.order or 50) < (b.order or 50) end
local function put(list, t)
    for i, old in ipairs(list) do
        if t.id ~= nil and old.id == t.id then list[i] = t; table.sort(list, byOrder) return end
    end
    table.insert(list, t)
    table.sort(list, byOrder)
end
function KM.RegisterHomeTile(t) put(KM.homeTiles, t) end
function KM.RegisterHomeNote(fn) table.insert(KM.homeNotes, fn) end
function KM.RegisterHomeCard(card)
    if type(card) ~= "table" or not card.kind then return end
    KM.homeCards[card.kind] = KM.homeCards[card.kind] or {}
    put(KM.homeCards[card.kind], card)
end

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

-- Count badge: a disc with a number. Flat: the white texture under the round portrait mask (the same mask the
-- minimap crown uses), so there is no art file. color: "red" (something to do here), "gold", "muted".
local BADGE = { red = { 0.86, 0.19, 0.17, 1 }, gold = C.accent, muted = C.dim }
local BADGE_TEXT = { red = { 1, 1, 1, 1 }, gold = { 0.10, 0.07, 0.01, 1 }, muted = { 1, 1, 1, 1 } }
local function countBadge(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    size = size or 16
    f:SetSize(size, size)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)
    f.disc = UI.Fill(f, BADGE.red, "ARTWORK")
    if f.CreateMaskTexture and f.disc.AddMaskTexture then
        local m = f:CreateMaskTexture()
        m:SetAllPoints(f.disc)
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.disc:AddMaskTexture(m)
    end
    local fsize = size >= 16 and 10 or 8
    f.text = UI.Text(f, fsize, BADGE_TEXT.red, "CENTER", "OVERLAY")
    f.text:SetPoint("CENTER", 0, 0)
    function f:SetCount(n, color)
        n = tonumber(n)
        if not n or n <= 0 then self.n = nil; self:Hide() return end
        color = BADGE[color] and color or "red"
        n = math.floor(n)
        self.n, self.color = n, color
        self.disc:SetColor(BADGE[color])
        local tc = BADGE_TEXT[color]
        self.text:SetTextColor(tc[1], tc[2], tc[3], 1)
        self.text:SetText(n > 9 and "9+" or tostring(n))
        self:Show()
    end
    f:Hide()
    return f
end
UI.CountBadge = countBadge   -- other windows may use it: UI.CountBadge(parent, size) -> f, f:SetCount(n, color)

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
    b.count = countBadge(b, 16)
    b.count:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnEnter", function(self)
        if current ~= p.id then self.hl:Show() end
        local v = p.badgeValue            -- the count badge's tip, when the page gave one
        if type(v) == "table" and type(v.tip) == "string" and v.tip ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(p.label or "", C.accent[1], C.accent[2], C.accent[3])
            GameTooltip:AddLine(v.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    b:SetScript("OnClick", function() UI.Click(); KM.Show(p.id) end)
    p.nav = b
    return b
end

local function groupHeader(g)
    local h = CreateFrame("Button", nil, navArea)
    h:SetHeight(GROUP_H)
    h.fs = UI.Text(h, 10, C.muted)
    h.fs:SetPoint("LEFT", 12, -2)
    h.arrow = UI.Text(h, 10, C.muted, "RIGHT")
    h.arrow:SetPoint("RIGHT", -10, -2)
    h.count = countBadge(h, 14)
    h.count:SetPoint("RIGHT", h.arrow, "LEFT", -6, 0)
    h:SetScript("OnEnter", function(self) self.fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    h:SetScript("OnLeave", function(self) self.fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    h:SetScript("OnClick", function()
        local col = db().collapsed
        col[g.id] = not col[g.id] or nil
        UI.Click()
        KM.LayoutNav()
        KM.RefreshBadges()           -- the header shows its pages' sum while collapsed
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
    frame:SetScale(KM.ClampScale(u.scale or 1))
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
    crown:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
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
    -- the status box sits at the bottom and is as tall as its text (statusText); the nav list takes the rest
    local status = CreateFrame("Frame", nil, side)
    status:SetPoint("BOTTOMLEFT", 10, 10)
    status:SetPoint("BOTTOMRIGHT", -10, 10)
    status:SetHeight(1)
    UI.Fill(status, { 0, 0, 0, 0.25 })
    UI.Border(status)
    statusFS = UI.Para(status, 10, C.muted, SIDE - 36)
    statusFS:SetPoint("TOPLEFT", 8, -8)
    status:Hide()
    statusBox = status

    navArea:SetPoint("TOPLEFT", 0, -62)
    navArea:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", 10, 6)
    if navArea.SetClipsChildren then navArea:SetClipsChildren(true) end
    navArea:EnableMouseWheel(true)
    navArea.scroll = 0
    navArea:SetScript("OnMouseWheel", function(self, d)
        local room = (self.total or 0) - (self:GetHeight() or 0)
        self.scroll = math.max(0, math.min(math.max(0, room), (self.scroll or 0) - d * NAV_H * 2))
        KM.LayoutNav()
    end)

    titleFS = UI.Text(frame, 18, C.text)
    titleFS:SetPoint("TOPLEFT", side, "TOPRIGHT", 22, -18)
    subFS = UI.Text(frame, 11, C.muted)
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetPoint("RIGHT", frame, "RIGHT", -60, 0)
    local close = UI.CloseButton(frame, function() KM.Toggle(false) end)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -12, -14)
    local rule = frame:CreateTexture(nil, "BORDER")   -- a top edge for the page, under the title and subtitle
    rule:SetTexture(UI.WHITE)
    rule:SetPoint("TOPLEFT", side, "TOPRIGHT", 18, -56)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -56)
    rule:SetHeight(1)
    UI.SetColor(rule, C.border)
    KM.headerRule = rule

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
    KM.AttachGrip()
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
    if #lines > 0 then
        statusBox:SetHeight(math.floor((statusFS:GetStringHeight() or 12) + 16.5))
        statusBox:Show()
    else
        statusBox:SetHeight(1)
        statusBox:Hide()
    end
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
    KM.RefreshBadges()
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

---------------------------------------------------------------------------
-- Badges: the gold text or count disc on each sidebar button, the sum on a collapsed group's header, the crown's dot
---------------------------------------------------------------------------

local function applyBadge(b, v)
    if type(v) == "table" then
        b.badge:SetText("")
        b.count:SetCount(v.count, v.color)
    else
        b.count:SetCount(nil)
        b.badge:SetText(v ~= nil and tostring(v) or "")   -- strings and numbers: the gold text, as before (Oracle)
    end
end

local RANK = { red = 3, gold = 2, muted = 1 }
local function stronger(a, v)            -- the colour a sum shows: red if any part is red, then gold
    local b = RANK[v.color] and v.color or "red"
    if not a or RANK[b] > RANK[a] then return b end
    return a
end

local function countOf(v)
    if type(v) ~= "table" then return 0 end
    local n = tonumber(v.count) or 0
    return n > 0 and math.floor(n) or 0
end

-- Works out every page's badge once and draws it: on its sidebar button, summed on a collapsed group's header (the
-- pages it hides), and on the minimap crown (pages with crownBadge = true). Cheap; modules call it when their counts
-- change, window open or not.
KM.BadgeTables = true   -- page badges may be { count, color, tip } tables (modules check this before returning one)
function KM.RefreshBadges()
    if not db() then return end
    local crown, crownColor = 0, nil
    for _, p in pairs(pages) do
        p.badgeValue = p.badge and KM.Safe(p.badge) or nil
        local v = p.badgeValue
        if p.nav then applyBadge(p.nav, v) end
        local n = countOf(v)
        if p.crownBadge and n > 0 then
            crown = crown + n
            crownColor = stronger(crownColor, v)
        end
    end
    local col = db().collapsed or {}
    for _, g in pairs(groups) do
        if g.header then
            local n, color = 0, nil
            if col[g.id] then
                for _, p in ipairs(g.pages) do
                    local c = p.id ~= current and countOf(p.badgeValue) or 0   -- the open page keeps its own button
                    if c > 0 then
                        n = n + c
                        color = stronger(color, p.badgeValue)
                    end
                end
            end
            g.header.count:SetCount(n, color)
        end
    end
    if mini and mini.count then mini.count:SetCount(db().crownBadge ~= false and crown or 0, crownColor) end
end

---------------------------------------------------------------------------
-- Window zoom: the layout is drawn for W x H and never reflows; the corner grip, Settings > General > Window zoom
-- and /km size scale it whole. 70% keeps the 9 pt labels readable; the top is whatever still fits on the screen.
---------------------------------------------------------------------------

local ZOOM_MIN, ZOOM_CAP = 0.7, 2.0
local DRAG_START = 3          -- the mouse must move this far before a press on the grip counts as a drag

local function floor2(s) return math.floor(s * 100 + 1e-6) / 100 end

function KM.MinScale() return ZOOM_MIN end

-- The largest zoom at which the whole window fits inside UIParent.
function KM.MaxScale()
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local w, h = W, H
    if frame then w, h = frame:GetWidth(), frame:GetHeight() end
    if not (uw and uh and uw > 0 and uh > 0 and w and h and w > 0 and h > 0) then return 1 end
    return floor2(math.max(ZOOM_MIN, math.min(ZOOM_CAP, uw / w, uh / h)))
end

function KM.ClampScale(s)
    return floor2(math.max(KM.MinScale(), math.min(KM.MaxScale(), tonumber(s) or 1)))
end

-- The window's top-left corner in UIParent units, measured from UIParent's bottom-left.
local function topLeft()
    local s, l, t = frame:GetScale(), frame:GetLeft(), frame:GetTop()
    if not (l and t and s) then return nil end
    return l * s, t * s
end

-- Zoom to s with the top-left corner at (L, T), slid back inside the screen if the bigger window would cross an edge.
-- Anchored TOPLEFT to UIParent's TOPLEFT (point == relative point, like a dragged frame), so savePos and create()
-- read it back unchanged. Offsets are in the frame's own scaled units, hence the / s.
local function placeAt(s, L, T)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local w, h = frame:GetWidth() * s, frame:GetHeight() * s
    L = math.max(0, math.min(L, uw - w))
    T = math.min(uh, math.max(T, h))
    frame:SetScale(s)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", L / s, (T - uh) / s)
end

function KM.SetScale(s)
    s = KM.ClampScale(s)
    db().scale = s
    if frame then
        local L, T = topLeft()
        if L then placeAt(s, L, T); savePos() else frame:SetScale(s) end
    end
    return s
end

function KM.ResetWindow()
    local u = db()
    u.scale, u.pos = nil, nil
    if frame then
        frame:SetScale(KM.ClampScale(1))
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
    end
    KM.Refresh("settings")
end

local function zoomStart(g)
    local L, T = topLeft()
    if not L then return end
    local s0, es = frame:GetScale(), UIParent:GetEffectiveScale()
    local w, h = frame:GetWidth(), frame:GetHeight()
    local x0, y0 = GetCursorPosition()
    x0, y0 = x0 / es, y0 / es
    local offX, offY = w * s0 - (x0 - L), h * s0 - (T - y0)   -- where in the grip the press was: no jump
    local lo, hi, cur, moved = KM.MinScale(), KM.MaxScale(), s0, false
    g.drag = true
    g:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        x, y = x / es, y / es
        if not moved and math.abs(x - x0) + math.abs(y - y0) < DRAG_START then return end
        moved = true
        local dx, dy = x - L + offX, T - y + offY
        -- the zoom whose corner lands closest to the mouse, aspect ratio kept (least squares along the diagonal)
        local s = floor2(math.max(lo, math.min(hi, (dx * w + dy * h) / (w * w + h * h))))
        if s ~= cur then cur = s; placeAt(s, L, T) end
        g.readout:SetText(math.floor(s * 100 + 0.5) .. "%")
        g.readout:Show()
    end)
end

local function zoomStop(g)
    if not g.drag then return end
    g.drag = nil
    g:SetScript("OnUpdate", nil)
    g.readout:Hide()
    db().scale = KM.ClampScale(frame:GetScale())
    savePos()
    KM.Refresh("settings")
end

-- The grip: six dots in the bottom-right corner, dim until hovered (drawn flat like the rest of the theme).
function KM.AttachGrip()
    local g = CreateFrame("Button", nil, frame)
    g:SetSize(16, 16)
    g:SetPoint("BOTTOMRIGHT", -3, 3)
    g:SetFrameLevel(frame:GetFrameLevel() + 20)
    g.dots = {}
    for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 0, 2 } }) do
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetTexture(UI.WHITE)
        t:SetSize(2, 2)
        t:SetPoint("BOTTOMRIGHT", -1 - d[1] * 5, 1 + d[2] * 5)
        UI.SetColor(t, C.dim)
        g.dots[#g.dots + 1] = t
    end
    g.readout = UI.Text(g, 10, C.accent, "RIGHT")      -- on the grip, so it draws above the page
    g.readout:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", 0, 2)
    g.readout:Hide()
    local function tint(c) for _, t in ipairs(g.dots) do UI.SetColor(t, c) end end
    g:SetScript("OnEnter", function(self)
        tint(C.accent)
        if self.drag then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Window zoom " .. math.floor(frame:GetScale() * 100 + 0.5) .. "%")
        GameTooltip:AddLine("Drag to make the whole window bigger or smaller.", 1, 1, 1, true)
        GameTooltip:AddLine("Double-click: back to 100%.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function(self) if not self.drag then tint(C.dim) end GameTooltip:Hide() end)
    g:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then GameTooltip:Hide(); zoomStart(self) end end)
    g:SetScript("OnMouseUp", function(self) zoomStop(self); if not (self.IsMouseOver and self:IsMouseOver()) then tint(C.dim) end end)
    g:SetScript("OnHide", zoomStop)               -- Escape mid-drag ends it and saves
    g:SetScript("OnDoubleClick", function() KM.SetScale(1); KM.Refresh("settings") end)
    KM.grip = g
end

-- A new UI scale or resolution changes what fits: re-clamp (a moment later, once UIParent has its new size).
local zoomEv = CreateFrame("Frame")
KM.Register(zoomEv, "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED")
zoomEv:SetScript("OnEvent", function()
    C_Timer.After(0.2, function() if frame and db() then KM.SetScale(db().scale or 1) end end)
end)

---------------------------------------------------------------------------
-- The minimap button: left-click opens the window, right-click the quick actions
---------------------------------------------------------------------------

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
        icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
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
        mini.count = countBadge(mini, 13)          -- a page's count (crownBadge = true), Settings > General
        mini.count:SetPoint("TOPRIGHT", -1, -1)
        mini.count:SetFrameLevel(mini:GetFrameLevel() + 5)
        KM.minimapButton = mini
        KM.RefreshBadges()
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
    "RegisterTooltip", "RegisterStatus", "RegisterHomeTile", "RegisterHomeNote", "RegisterHomeCard", "RefreshBadges" }) do
    KingMaker[name] = KM[name]
end
