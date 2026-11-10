local _, KM = ...

-- Theme: King Maker's palette and widget kit, drawn flat with the white texture (no art files). Night panels and
-- a warm gold accent, shared with the Oracle addon so its pages sit in this window unchanged. Every module draws
-- with these, never with Blizzard panel templates, so the whole suite reads as one addon.
--
--   local UI = KM.UI
--   UI.C                                palette { r, g, b, a }
--   UI.Fill(f, color, layer)            texture covering f (tex:SetColor(c) recolours)
--   UI.Border(f, color)                 1 px edges
--   UI.Panel(parent, bg)                bordered card
--   UI.Text(parent, size, color, justify)
--   UI.Heading(parent, text)            small gold caps
--   UI.Button(parent, label, w, h, onClick, style)     style "primary" | "ghost" | nil; b:SetLabel(s), b:SetEnabled2(on)
--   UI.Check(parent, onToggle)          square checkbox; UI.CheckLabel(parent, label, onToggle, tip)
--   UI.Pill(parent)                     verb badge: pill:Set(word) or pill:SetCustom(text, color)
--   UI.Bar(parent, h)                   progress bar: bar:Set(fraction, color)
--   UI.Tabs(parent, items, onSelect)    segmented control: items = { {id, label} }; tabs:Select(id)
--   UI.EditBox(parent, w, h, hint, onChange)           search / text box
--   UI.NumberBox(parent, w, onChange)
--   UI.MenuButton(parent, w, getLabel, gen)            button that opens a MenuUtil menu: gen(owner, root)
--   UI.Tile(parent, w, h)               stat card: tile:Set(label, value, sub, color)
--   UI.Table(parent, cols, rowH, opts)  header + pooled rows + wheel + sortable headers: tbl:SetRows(list, fill)
--   UI.Scroll(parent)                   wheel-scrolled child frame: sc.child, sc:SetContentHeight(h)
--   UI.Window(name, title, w, h, opts)  themed floating dialog (Deep Scan, exports): frame.body, frame:SetTitle
--   UI.HUD(name, title, w, opts)        themed small tracker frame (Farm session, Gather ledger)
--   UI.Hex(c), UI.Click()

local UI = {}
KM.UI = UI
KingMaker.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.WHITE = WHITE

UI.C = {
    bg      = { 0.043, 0.047, 0.063, 0.97 },
    sidebar = { 0.059, 0.063, 0.086, 1 },
    panel   = { 0.082, 0.090, 0.122, 1 },
    panel2  = { 0.106, 0.116, 0.157, 1 },
    head    = { 0, 0, 0, 0.28 },
    zebra   = { 1, 1, 1, 0.022 },
    border  = { 1, 1, 1, 0.075 },
    hover   = { 0.94, 0.77, 0.30, 0.08 },
    sel     = { 0.94, 0.77, 0.30, 0.14 },
    text    = { 0.93, 0.91, 0.86, 1 },
    muted   = { 0.60, 0.59, 0.56, 1 },
    dim     = { 0.42, 0.42, 0.44, 1 },
    accent  = { 0.94, 0.77, 0.30, 1 },
    good    = { 0.30, 0.80, 0.48, 1 },
    warn    = { 1.00, 0.72, 0.22, 1 },
    bad     = { 0.92, 0.36, 0.36, 1 },
    info    = { 0.38, 0.64, 0.98, 1 },
    violet  = { 0.66, 0.56, 0.98, 1 },
}
local C = UI.C

-- Item quality colours (0 poor .. 5 legendary), as hex without the |c prefix.
UI.QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80" }

UI.VERB = {
    sell  = { label = "SELL",  c = C.good },
    buy   = { label = "BUY",   c = C.info },
    craft = { label = "CRAFT", c = C.violet },
    keep  = { label = "KEEP",  c = C.muted },
    hold  = { label = "HOLD",  c = C.muted },
    skip  = { label = "SKIP",  c = C.bad },
    avoid = { label = "AVOID", c = C.bad },
    watch = { label = "WATCH", c = C.warn },
    ["do"] = { label = "DO",   c = C.accent },
}

function UI.Hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function setColor(tex, c) tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
UI.SetColor = setColor

function UI.Fill(f, color, layer, sub)
    local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetTexture(WHITE)
    t:SetAllPoints(f)
    setColor(t, color or C.panel)
    t.SetColor = setColor
    return t
end

function UI.Border(f, color)
    color = color or C.border
    local edges = {}
    local function edge(p1, p2, w, h)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(WHITE)
        setColor(t, color)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    return edges
end

function UI.Panel(parent, bg)
    local p = CreateFrame("Frame", nil, parent)
    p.bg = UI.Fill(p, bg or C.panel)
    UI.Border(p)
    return p
end

function UI.Font(fs, size, flags)
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
end

function UI.Text(parent, size, color, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    UI.Font(fs, size)
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

-- Multi-line text that wraps inside width w.
function UI.Para(parent, size, color, w)
    local fs = UI.Text(parent, size, color)
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetJustifyV("TOP")
    if w then fs:SetWidth(w) end
    return fs
end

function UI.Heading(parent, text)
    local fs = UI.Text(parent, 11, C.accent)
    fs:SetText((text or ""):upper())
    return fs
end

function UI.Click()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- Shows a simple tooltip on owner from a string or a function(tooltip).
function UI.Tip(owner, tip)
    owner:HookScript("OnEnter", function(self)
        local t = type(tip) == "function" and tip or nil
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if t then t(GameTooltip, self) else GameTooltip:AddLine(tip, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function accentA(a) return { C.accent[1], C.accent[2], C.accent[3], a } end

function UI.Button(parent, label, w, h, onClick, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 90, h or 24)
    local primary, ghost = style == "primary", style == "ghost"
    local base = primary and accentA(0.18) or (ghost and { 0, 0, 0, 0 } or C.panel2)
    local over = primary and accentA(0.28) or { 0.15, 0.16, 0.21, 1 }
    b.bg = UI.Fill(b, base)
    b.edges = UI.Border(b, primary and accentA(0.55) or C.border)
    b.label = UI.Text(b, 12, primary and C.accent or C.text, "CENTER")
    b.label:SetPoint("LEFT", 4, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.label:SetText(label)
    b.enabled2 = true
    function b:SetLabel(s) self.label:SetText(s) end
    function b:SetEnabled2(on)
        self.enabled2 = on and true or false
        local c = on and (primary and C.accent or C.text) or C.dim
        self.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    -- A toggle look: b:SetActive(true) paints it as the selected option.
    function b:SetActive(on)
        self.active = on
        self.bg:SetColor(on and accentA(0.22) or base)
        local c = on and C.accent or (self.enabled2 and (primary and C.accent or C.text) or C.dim)
        self.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    b:SetScript("OnEnter", function(self) if not self.active then self.bg:SetColor(over) end end)
    b:SetScript("OnLeave", function(self) if not self.active then self.bg:SetColor(base) end end)
    -- b:SetPadding(left, right) moves the label in (left-aligned sidebar buttons); the press nudge keeps it.
    b.padL, b.padR = 4, 4
    function b:SetPadding(l, r) self.padL, self.padR = l or 4, r or 4; self.label:SetPoint("LEFT", self.padL, 0); self.label:SetPoint("RIGHT", -self.padR, 0) end
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("LEFT", self.padL + 1, -1); self.label:SetPoint("RIGHT", -self.padR + 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", self.padL, 0); self.label:SetPoint("RIGHT", -self.padR, 0) end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, ...)
        if not self.enabled2 then return end
        UI.Click()
        if onClick then onClick(self, ...) end
    end)
    return b
end

function UI.Pill(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(46, 16)
    p.bg = UI.Fill(p, C.panel2, "ARTWORK")
    p.text = UI.Text(p, 9, C.text, "CENTER")
    p.text:SetPoint("CENTER", 0, 0)
    function p:SetCustom(text, c)
        if not text then self:Hide() return end
        c = c or C.muted
        self.bg:SetColor({ c[1], c[2], c[3], 0.18 })
        self.text:SetTextColor(c[1], c[2], c[3], 1)
        self.text:SetText(text)
        self:Show()
    end
    function p:Set(word)
        local v = word and UI.VERB[word]
        if not v then self:Hide() return end
        self:SetCustom(v.label, v.c)
    end
    return p
end

function UI.Bar(parent, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(h or 8)
    b.bg = UI.Fill(b, { 0, 0, 0, 0.45 })
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetTexture(WHITE)
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    function b:Set(frac, color)
        frac = math.max(0, math.min(1, frac or 0))
        self.frac, self.color = frac, color
        local w = (self:GetWidth() or 0) * frac
        self.fill:SetWidth(math.max(w, 0.001))
        self.fill:SetShown(frac > 0)
        setColor(self.fill, color or C.accent)
    end
    b:SetScript("OnSizeChanged", function(self) if self.frac then self:Set(self.frac, self.color) end end)
    return b
end

function UI.Check(parent, onToggle)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)
    cb.bg = UI.Fill(cb, { 0, 0, 0, 0.4 })
    UI.Border(cb, { 1, 1, 1, 0.18 })
    cb.mark = cb:CreateTexture(nil, "OVERLAY")
    cb.mark:SetTexture(WHITE)
    cb.mark:SetPoint("TOPLEFT", 4, -4)
    cb.mark:SetPoint("BOTTOMRIGHT", -4, 4)
    setColor(cb.mark, C.accent)
    cb.mark:Hide()
    function cb:SetChecked(v) self.checked = v and true or false; self.mark:SetShown(self.checked) end
    function cb:GetChecked() return self.checked or false end
    cb:SetScript("OnClick", function(self)
        UI.Click()
        self:SetChecked(not self.checked)
        if onToggle then onToggle(self.checked, self) end
    end)
    return cb
end

-- A checkbox with a label to its right; the label is clickable too. Returns the checkbox (cb.label, cb.frame).
function UI.CheckLabel(parent, label, onToggle, tip)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(18)
    local cb = UI.Check(f, onToggle)
    cb:SetPoint("LEFT", 0, 0)
    cb.label = UI.Text(f, 12, C.text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    cb.label:SetText(label)
    f:SetWidth(24 + (cb.label:GetStringWidth() or 80))
    f:SetScript("OnClick", function() cb:GetScript("OnClick")(cb) end)
    if tip then UI.Tip(f, tip) end
    cb.frame = f
    -- Position the pair with cb.frame:SetPoint(...).
    return cb
end

-- Segmented control. items = { { id = "sales", label = "Sales" }, ... }; onSelect(id).
function UI.Tabs(parent, items, onSelect, h)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(h or 24)
    t.buttons, t.items = {}, items
    local x = 0
    for _, it in ipairs(items) do
        local w = it.w or math.max(64, 18 + 7 * #(it.label or ""))
        local b = UI.Button(t, it.label, w, h or 24, function() t:Select(it.id, true) end, "ghost")
        b:SetPoint("LEFT", x, 0)
        x = x + w - 1
        t.buttons[it.id] = b
    end
    t:SetWidth(x + 1)
    function t:Select(id, user)
        self.current = id
        for bid, b in pairs(self.buttons) do b:SetActive(bid == id) end
        if user and onSelect then onSelect(id) end
    end
    function t:SetLabel(id, label) if self.buttons[id] then self.buttons[id]:SetLabel(label) end end
    return t
end

function UI.EditBox(parent, w, h, hint, onChange)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or 160, h or 24)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    if e.SetTextInsets then e:SetTextInsets(8, 8, 0, 0) end
    e.bg = UI.Fill(e, { 0, 0, 0, 0.35 })
    UI.Border(e, { 1, 1, 1, 0.12 })
    e.hint = UI.Text(e, 11, C.dim)
    e.hint:SetPoint("LEFT", 8, 0)
    e.hint:SetText(hint or "")
    local function hintShown(self) self.hint:SetShown((self:GetText() or "") == "" and not self.focused) end
    e:SetScript("OnEditFocusGained", function(self) self.focused = true; hintShown(self) end)
    e:SetScript("OnEditFocusLost", function(self) self.focused = false; hintShown(self) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnTextChanged", function(self, user)
        hintShown(self)
        if onChange then onChange(self:GetText() or "", user) end
    end)
    return e
end

function UI.NumberBox(parent, w, onChange)
    local e = UI.EditBox(parent, w or 48, 22, "", nil)
    if e.SetNumeric then e:SetNumeric(true) end
    if e.SetMaxLetters then e:SetMaxLetters(4) end
    e:SetJustifyH("CENTER")
    local function commit(self) if onChange then onChange(tonumber(self:GetText() or "")) end end
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
    e:HookScript("OnEditFocusLost", commit)
    return e
end

-- A button whose click opens a context menu. gen(owner, root) fills it (MenuUtil). getLabel() -> text.
function UI.MenuButton(parent, w, getLabel, gen)
    local b
    b = UI.Button(parent, "", w or 120, 24, function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, gen) end
    end)
    b.arrow = UI.Text(b, 10, C.muted, "RIGHT")
    b.arrow:SetPoint("RIGHT", -7, 0)
    b.arrow:SetText("v")
    b.label:SetPoint("RIGHT", -16, 0)
    function b:Refresh() self.label:SetText(getLabel and getLabel() or "") end
    b:Refresh()
    return b
end

-- Stat card: a small caps label, a big value, an optional grey line under it.
function UI.Tile(parent, w, h)
    local t = UI.Panel(parent, C.panel)
    t:SetSize(w or 150, h or 64)
    t.label = UI.Text(t, 9, C.muted)
    t.label:SetPoint("TOPLEFT", 10, -9)
    t.value = UI.Text(t, 17, C.text)
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -6)
    t.value:SetPoint("RIGHT", -8, 0)
    t.sub = UI.Text(t, 10, C.dim)
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.sub:SetPoint("RIGHT", -8, 0)
    function t:Set(label, value, sub, color)
        self.label:SetText((label or ""):upper())
        self.value:SetText(value or "")
        local c = color or C.text
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        self.sub:SetText(sub or "")
    end
    return t
end

---------------------------------------------------------------------------
-- Table: header band, pooled rows, zebra, hover mark, mouse-wheel scrolling, sortable headers
---------------------------------------------------------------------------

-- cols = { { key, label, w, justify, sort = function(row) -> value, desc = bool } }; the last column may have
-- w = 0 (stretch). fill(rowFrame, rowData, cells) draws one row; cells[key] is a font string, rowFrame.icon a
-- texture (opts.icon). Set rowFrame.item (an itemID) or rowFrame.tip (string | function(tt)) for a hover tooltip.
-- opts.onClick(data, mouseButton, rowFrame); opts.onEnter(rowFrame) replaces the default tooltip.
function UI.Table(parent, cols, rowH, opts)
    opts = opts or {}
    rowH = rowH or 22
    local t = CreateFrame("Frame", nil, parent)
    t.cols, t.rows, t.data, t.offset = cols, {}, {}, 0
    t.head = CreateFrame("Frame", nil, t)
    t.head:SetPoint("TOPLEFT")
    t.head:SetPoint("TOPRIGHT")
    t.head:SetHeight(20)
    UI.Fill(t.head, C.head)
    t.headers = {}
    local x = opts.icon and 26 or 8
    for _, col in ipairs(cols) do
        local h = CreateFrame("Button", nil, t.head)
        h:SetPoint("TOPLEFT", x, 0)
        h:SetSize(col.w > 0 and col.w or 100, 20)
        h.fs = UI.Text(h, 9, C.muted, col.justify or "LEFT")
        h.fs:SetPoint("LEFT", 0, 0)
        h.fs:SetPoint("RIGHT", -6, 0)
        h.fs:SetText((col.label or ""):upper())
        if col.sort then
            h:SetScript("OnClick", function()
                if t.sortKey == col.key then t.sortDesc = not t.sortDesc else t.sortKey, t.sortDesc = col.key, col.desc ~= false end
                UI.Click()
                if opts.onSort then opts.onSort(t.sortKey, t.sortDesc) end
                t:Redraw()
            end)
        end
        if col.tip then UI.Tip(h, col.tip) end
        col.x = x
        t.headers[col.key] = h
        x = x + (col.w > 0 and col.w or 0)
    end
    t.empty = UI.Text(t, 12, C.dim, "CENTER")
    t.empty:SetPoint("TOP", 0, -44)

    function t:Layout()
        local h = self:GetHeight() or 0
        local n = math.max(1, math.floor((h - 20) / rowH))
        for i = #self.rows + 1, n do
            local r = CreateFrame("Button", nil, self)
            r:SetHeight(rowH)
            r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * rowH)
            r:SetPoint("TOPRIGHT", 0, -20 - (i - 1) * rowH)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r.zebra = UI.Fill(r, C.zebra)
            r.hl = UI.Fill(r, C.hover, "ARTWORK")
            r.hl:Hide()
            r.sel = UI.Fill(r, C.sel, "ARTWORK")
            r.sel:Hide()
            r.mark = r:CreateTexture(nil, "OVERLAY")
            r.mark:SetTexture(WHITE)
            r.mark:SetPoint("TOPLEFT")
            r.mark:SetPoint("BOTTOMLEFT")
            r.mark:SetWidth(2)
            setColor(r.mark, C.accent)
            r.mark:Hide()
            if opts.icon then
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(rowH - 6, rowH - 6)
                r.icon:SetPoint("LEFT", 5, 0)
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            r.cells = {}
            for ci, col in ipairs(self.cols) do
                local fs = UI.Text(r, opts.fontSize or 12, C.text, col.justify or "LEFT")
                fs:SetPoint("LEFT", col.x, 0)
                if col.w > 0 then fs:SetWidth(col.w - 8) else fs:SetPoint("RIGHT", -8, 0) end
                r.cells[col.key] = fs
                r.cells[ci] = fs
            end
            r:SetScript("OnEnter", function(self2)
                self2.hl:Show(); self2.mark:Show()
                if opts.onEnter then opts.onEnter(self2) return end
                if self2.item and GameTooltip.SetItemByID then
                    GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                    pcall(GameTooltip.SetItemByID, GameTooltip, self2.item)
                    GameTooltip:Show()
                elseif self2.tip then
                    GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                    if type(self2.tip) == "function" then self2.tip(GameTooltip, self2) else GameTooltip:AddLine(self2.tip, 1, 1, 1, true) end
                    GameTooltip:Show()
                end
            end)
            r:SetScript("OnLeave", function(self2) self2.hl:Hide(); self2.mark:Hide(); GameTooltip:Hide() end)
            if opts.onClick then r:SetScript("OnClick", function(self2, btn) if self2.data then opts.onClick(self2.data, btn, self2) end end) end
            self.rows[i] = r
        end
        self.visible = n
    end

    function t:Sort()
        if not self.sortKey then return end
        local col
        for _, c in ipairs(self.cols) do if c.key == self.sortKey then col = c end end
        if not (col and col.sort) then return end
        local desc = self.sortDesc
        table.sort(self.data, function(a, b)
            local x2, y2 = col.sort(a), col.sort(b)
            if x2 == nil or y2 == nil then return x2 ~= nil and y2 == nil end
            if x2 == y2 then return false end
            if desc then return x2 > y2 end
            return x2 < y2
        end)
    end

    function t:Redraw()
        if not self.visible then self:Layout() end
        local data = self.data
        if not opts.noSort then self:Sort() end
        self.offset = math.max(0, math.min(self.offset, #data - self.visible))
        for i, r in ipairs(self.rows) do
            local row = i <= self.visible and data[i + self.offset]
            if row then
                r.data, r.item, r.tip = row, nil, nil
                r.zebra:SetShown((i + self.offset) % 2 == 0)
                r.sel:SetShown(self.selected ~= nil and self.selected == row)
                if r.icon then r.icon:SetTexture(nil) end
                self.fill(r, row, r.cells)
                r:Show()
            else
                r.data = nil
                r:Hide()
            end
        end
        for key, h in pairs(self.headers) do
            local label
            for _, c in ipairs(self.cols) do if c.key == key then label = (c.label or ""):upper() end end
            if self.sortKey == key then label = label .. (self.sortDesc and "  v" or "  ^") end
            h.fs:SetText(label)
            local c = self.sortKey == key and C.accent or C.muted
            h.fs:SetTextColor(c[1], c[2], c[3])
        end
        self.empty:SetText(#data == 0 and (self.emptyText or "Nothing here yet.") or "")
        if self.onRedraw then self.onRedraw(self) end
    end

    function t:SetRows(list, fill)
        self.data = list or {}
        if fill then self.fill = fill end
        self:Redraw()
    end

    function t:SetSort(key, desc) self.sortKey, self.sortDesc = key, desc end
    function t:ScrollTo(i) self.offset = math.max(0, (i or 1) - 1); self:Redraw() end

    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * 3)
        self:Redraw()
    end)
    t:SetScript("OnSizeChanged", function(self) self:Layout(); if self.fill then self:Redraw() end end)
    return t
end

---------------------------------------------------------------------------
-- Scroll: a clipped child frame moved by the mouse wheel (for long settings lists and detail panes)
---------------------------------------------------------------------------

function UI.Scroll(parent)
    local sc = CreateFrame("ScrollFrame", nil, parent)
    sc.child = CreateFrame("Frame", nil, sc)
    sc.child:SetSize(1, 1)
    sc:SetScrollChild(sc.child)
    sc.pos, sc.height = 0, 0
    sc:EnableMouseWheel(true)
    function sc:SetContentHeight(h)
        self.height = h or 0
        self.child:SetHeight(math.max(1, self.height))
        self:SetPos(self.pos)
    end
    function sc:SetPos(p)
        local maxp = math.max(0, self.height - (self:GetHeight() or 0))
        self.pos = math.max(0, math.min(p or 0, maxp))
        if self.SetVerticalScroll then self:SetVerticalScroll(self.pos) end
    end
    sc:SetScript("OnMouseWheel", function(self, d) self:SetPos(self.pos - d * 40) end)
    sc:SetScript("OnSizeChanged", function(self, w) self.child:SetWidth(w or self:GetWidth() or 1); self:SetPos(self.pos) end)
    return sc
end

---------------------------------------------------------------------------
-- Floating frames: dialogs and trackers in the same style as the main window
---------------------------------------------------------------------------

local function closeButton(parent, onClick)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(20, 20)
    close.bg = UI.Fill(close, C.panel2)
    UI.Border(close)
    local x = UI.Text(close, 12, C.muted, "CENTER")
    x:SetPoint("CENTER", 0, 0)
    x:SetText("x")
    close:SetScript("OnEnter", function() close.bg:SetColor({ C.bad[1], C.bad[2], C.bad[3], 0.35 }); x:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() close.bg:SetColor(C.panel2); x:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    close:SetScript("OnClick", onClick)
    return close
end
UI.CloseButton = closeButton

local function goldEdge(f)
    local top = f:CreateTexture(nil, "OVERLAY")
    top:SetTexture(WHITE)
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(2)
    top:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
end
UI.GoldEdge = goldEdge

-- A dialog: title bar, close button, Escape closes it, draggable. opts.strata (default "DIALOG").
function UI.Window(name, title, w, h, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, opts.parent or UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata(opts.strata or "DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if name and UISpecialFrames and not opts.noEscape then table.insert(UISpecialFrames, name) end
    UI.Fill(f, C.bg)
    UI.Border(f, { 1, 1, 1, 0.10 })
    goldEdge(f)
    f.title = UI.Text(f, 14, C.text)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(title or "")
    function f:SetTitle(s) self.title:SetText(s) end
    f.close = closeButton(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -8, -8)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 14, -38)
    f.body:SetPoint("BOTTOMRIGHT", -14, 12)
    f:Hide()
    return f
end

-- A small tracker that floats during play. opts.getPos() -> {point,x,y}, opts.setPos(pos), opts.onClose(),
-- opts.onCollapse(collapsed). frame.body is the content; frame:SetCollapsed(bool) shows only the title bar.
function UI.HUD(name, title, w, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w or 268, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    local pos = opts.getPos and opts.getPos()
    if pos and pos.point then f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y) else f:SetPoint("RIGHT", -60, 60) end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if opts.setPos then opts.setPos({ point = point, x = x, y = y }) end
    end)
    UI.Fill(f, { C.bg[1], C.bg[2], C.bg[3], 0.92 })
    UI.Border(f, { 1, 1, 1, 0.10 })
    goldEdge(f)
    f.title = UI.Text(f, 12, C.accent)
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetText(title or "")
    f.close = closeButton(f, function() f:Hide(); if opts.onClose then opts.onClose() end end)
    f.close:SetSize(18, 18)
    f.close:SetPoint("TOPRIGHT", -6, -5)
    f.collapse = UI.Button(f, "-", 18, 18, function() f:SetCollapsed(not f.collapsed); if opts.onCollapse then opts.onCollapse(f.collapsed) end end)
    f.collapse:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 8, -28)
    f.body:SetPoint("BOTTOMRIGHT", -8, 8)
    f.fullHeight = 120
    function f:SetBodyHeight(h)
        self.fullHeight = 36 + (h or 0)
        if not self.collapsed then self:SetHeight(self.fullHeight) end
    end
    function f:SetCollapsed(on)
        self.collapsed = on and true or false
        self.body:SetShown(not self.collapsed)
        self:SetHeight(self.collapsed and 28 or self.fullHeight)
        self.collapse:SetLabel(self.collapsed and "+" or "-")
    end
    return f
end
