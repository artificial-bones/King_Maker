local _, KM = ...

-- Settings: one page in the window (a list of sections on the left, the chosen section's rows on the right), plus
-- a small entry in Blizzard's Options > AddOns that opens it. Modules describe their settings as rows:
--
--   KM.RegisterSettings{ id = "scanner", label = "Scanner", order = 10, rows = {
--       { type = "header", label = "Tooltips" },
--       { type = "check",  label = "Prices in item tooltips", tip = "...", get = fn() -> bool, set = fn(bool) },
--       { type = "range",  label = "Pin size", min = 8, max = 32, step = 1, get = fn, set = fn(n), fmt = fn(n) },
--       { type = "choice", label = "Value items at", options = { { "market", "Market" }, ... }, get = fn, set = fn(v) },
--       { type = "button", label = "Forget guild data", func = fn, tip = "..." },
--       { type = "text",   label = "A grey note, wrapped." },
--       { type = "custom", height = 120, build = fn(frame, width), refresh = fn(frame) },
--   } }
-- rows may also be a function returning the list (rebuilt every time the section is opened).

local UI = KM.UI
local C = UI.C
local sections = {}
local current

function KM.RegisterSettings(s)
    sections[#sections + 1] = s
    table.sort(sections, function(a, b) return (a.order or 50) < (b.order or 50) end)
end
KingMaker.RegisterSettings = KM.RegisterSettings

local ROW_W = 470

local function buildRow(parent, row, y)
    local h = 26
    local kind = row.type
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 0, y)
    f:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if kind == "header" then
        h = 30
        local fs = UI.Heading(f, row.label)
        fs:SetPoint("BOTTOMLEFT", 0, 6)
    elseif kind == "text" then
        local fs = UI.Para(f, 11, C.muted, ROW_W + 60)
        fs:SetPoint("TOPLEFT", 0, -2)
        fs:SetText(row.label)
        h = math.max(18, (fs:GetStringHeight() or 14) + 8)
    elseif kind == "check" then
        local cb = UI.CheckLabel(f, row.label, function(v) KM.Safe(row.set, v); KM.Refresh("settings") end, row.tip)
        cb.frame:SetPoint("LEFT", 0, 0)
        f.refresh = function() cb:SetChecked(KM.Safe(row.get)) end
    elseif kind == "range" then
        local label = UI.Text(f, 12, C.text)
        label:SetPoint("LEFT", 0, 0)
        label:SetText(row.label)
        local val = UI.Text(f, 12, C.accent, "CENTER")
        local function step(d)
            local v = (KM.Safe(row.get) or row.min) + d * (row.step or 1)
            KM.Safe(row.set, math.max(row.min, math.min(row.max, v)))
            f.refresh()
        end
        local minus = UI.Button(f, "-", 24, 22, function() step(-1) end)
        minus:SetPoint("LEFT", 260, 0)
        val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        val:SetWidth(64)
        local plus = UI.Button(f, "+", 24, 22, function() step(1) end)
        plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
        if row.tip then UI.Tip(minus, row.tip) end
        f.refresh = function()
            local v = KM.Safe(row.get) or row.min
            val:SetText(row.fmt and row.fmt(v) or tostring(v))
        end
    elseif kind == "choice" then
        local label = UI.Text(f, 12, C.text)
        label:SetPoint("LEFT", 0, 0)
        label:SetText(row.label)
        local x = 260
        local buttons = {}
        for _, opt in ipairs(row.options or {}) do
            local w = math.max(60, 16 + 7 * #opt[2])
            local b = UI.Button(f, opt[2], w, 22, function() KM.Safe(row.set, opt[1]); f.refresh(); KM.Refresh("settings") end)
            b:SetPoint("LEFT", x, 0)
            x = x + w + 4
            buttons[opt[1]] = b
        end
        f.refresh = function()
            local v = KM.Safe(row.get)
            for value, b in pairs(buttons) do b:SetActive(value == v) end
        end
    elseif kind == "button" then
        local b = UI.Button(f, row.label, row.w or math.max(140, 20 + 7 * #row.label), 24, function() KM.Safe(row.func); KM.Refresh("settings") end)
        b:SetPoint("LEFT", 0, 0)
        if row.tip then UI.Tip(b, row.tip) end
        h = 30
    elseif kind == "custom" then
        h = row.height or 100
        KM.Safe(row.build, f, ROW_W + 60)
        if row.refresh then f.refresh = function() KM.Safe(row.refresh, f) end end
    end
    f:SetHeight(h)
    return f, h
end

local list, body, scroll

local function showSection(s)
    current = s
    for _, other in ipairs(sections) do
        if other.nav then other.nav:SetActive(other == s) end
        if other.frame then other.frame:Hide() end
    end
    local rows = type(s.rows) == "function" and KM.Safe(s.rows) or s.rows or {}
    if s.frame and type(s.rows) == "function" then s.frame:Hide(); s.frame = nil end
    if not s.frame then
        s.frame = CreateFrame("Frame", nil, scroll.child)
        s.frame:SetPoint("TOPLEFT")
        s.frame:SetPoint("RIGHT", scroll.child, "RIGHT")
        s.frame.rows = {}
        local y = 0
        for _, row in ipairs(rows) do
            local f, h = buildRow(s.frame, row, y)
            s.frame.rows[#s.frame.rows + 1] = f
            y = y - h
        end
        s.frame.height = -y
        s.frame:SetHeight(math.max(1, -y))
    end
    s.frame:Show()
    for _, f in ipairs(s.frame.rows) do if f.refresh then f.refresh() end end
    scroll:SetContentHeight(s.frame.height + 20)
    scroll:SetPos(0)
end

local function build(container)
    list = CreateFrame("Frame", nil, container)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    list:SetWidth(150)
    UI.Fill(list, { 0, 0, 0, 0.18 })
    UI.Border(list)
    body = UI.Panel(container, C.panel)
    body:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    scroll = UI.Scroll(body)
    scroll:SetPoint("TOPLEFT", 18, -12)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    for i, s in ipairs(sections) do
        local b = UI.Button(list, s.label, 134, 24, function() showSection(s) end, "ghost")
        b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 26)
        b.label:SetJustifyH("LEFT")
        s.nav = b
    end
end

local function refresh()
    if not current then
        current = sections[1]
        if current then showSection(current) end
        return
    end
    if current.frame then for _, f in ipairs(current.frame.rows) do if f.refresh then f.refresh() end end end
end

function KM.OpenSettings(id)
    for _, s in ipairs(sections) do if s.id == id then current = nil; KM.Show("settings"); showSection(s) return end end
    KM.Show("settings")
end
KingMaker.OpenSettings = KM.OpenSettings

KM.RegisterPage({ id = "settings", group = "system", label = "Settings", icon = "Interface\\Icons\\Trade_Engineering", order = 99,
    title = "Settings", subtitle = "Everything King Maker can show or do, module by module.", build = build, refresh = refresh })

-- The core's own section.
KM.RegisterSettings({ id = "general", label = "General", order = 0, rows = function()
    local rows = {
        { type = "header", label = "King Maker" },
        { type = "check", label = "Show the minimap button", get = function() return KingMakerDB.ui.button end,
          set = function(v) KingMakerDB.ui.button = v; KM.UpdateMinimapButton() end },
        { type = "range", label = "Window size", min = 0.7, max = 1.4, step = 0.05,
          get = function() return KingMakerDB.ui.scale or 1 end, set = function(v) KM.SetScale(math.floor(v * 20 + 0.5) / 20) end,
          fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end },
        { type = "text", label = "Left-click the crown on the minimap to open this window, right-click it for quick actions (scans, trackers). /km opens it too; every old slash command (/sk, /ek, /mk, ...) still works." },
        { type = "header", label = "Moved in from the old King addons" },
    }
    local done = KM.MigrationReport and KM.MigrationReport() or {}
    if #done == 0 then
        rows[#rows + 1] = { type = "text", label = "Nothing to move: no old King addon folders were loaded." }
    else
        for _, line in ipairs(done) do rows[#rows + 1] = { type = "text", label = line } end
    end
    return rows
end })

-- Blizzard Options > AddOns > King Maker: a pointer to the real settings page.
local panel = CreateFrame("Frame")
panel.name = "King Maker"
local category
panel:SetScript("OnShow", function(self)
    if self.built then return end
    self.built = true
    local t = self:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("King Maker")
    local s = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    s:SetText("Prices, history, crafting, gold, farming and characters in one window.")
    local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    b:SetSize(220, 26)
    b:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -16)
    b:SetText("Open King Maker settings")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.Hide then pcall(SettingsPanel.Hide, SettingsPanel) end
        KM.OpenSettings()
    end)
end)
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
KM.blizzardCategory = category
