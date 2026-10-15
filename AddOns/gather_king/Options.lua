local _, ns = ...

-- Settings page: Esc > Options > AddOns > Gather King, or /gt settings.
-- Everything here belongs to the active profile, except the delete buttons,
-- which act on the markers shared by all profiles. This is the only place
-- with bulk "delete all" buttons.

local panel = CreateFrame("Frame")
panel.name = "Gather King"
local category
local content -- scrollable area that holds every widget (the page is taller than the window)

StaticPopupDialogs["GATHERKING_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, fn) fn() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["GATHERKING_NEW_PROFILE"] = {
    text = "Name for the new profile (it starts as a copy of the current one):",
    button1 = OKAY or "OK",
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox
        ns.NewProfile(box and box:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        ns.NewProfile(self:GetText())
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function confirm(text, fn)
    StaticPopup_Show("GATHERKING_CONFIRM", text, nil, fn)
end

local refreshers = {}

local function text(template, point, anchor, rel, x, y, str)
    local fs = content:CreateFontString(nil, "ARTWORK", template)
    fs:SetPoint(point, anchor, rel, x, y)
    if str then fs:SetText(str) end
    return fs
end

local function checkbox(label, point, anchor, rel, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint(point, anchor, rel, x, y)
    if label then
        cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.label:SetText(label)
    end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Refresh()
    end)
    table.insert(refreshers, function() cb:SetChecked(get()) end)
    return cb
end

local function button(label, width, onClick)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function build()
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(620, 1180)
    scroll:SetScrollChild(content)

    local title = text("GameFontNormalHuge", "TOPLEFT", content, "TOPLEFT", 16, -16, "Gather King")

    -------------------------------------------------------------------
    -- Profiles
    -------------------------------------------------------------------
    local profHead = text("GameFontNormalLarge", "TOPLEFT", title, "BOTTOMLEFT", 0, -16, "Profile")
    local profText = text("GameFontHighlight", "LEFT", profHead, "RIGHT", 10, 0)
    table.insert(refreshers, function() profText:SetText("Using: |cffffd100" .. ns.ActiveProfile() .. "|r") end)

    local newBtn = button("New profile", 110, function() StaticPopup_Show("GATHERKING_NEW_PROFILE") end)
    newBtn:SetPoint("TOPLEFT", profHead, "BOTTOMLEFT", 0, -8)
    local delBtn = button("Delete this profile", 140, function()
        local name = ns.ActiveProfile()
        if name == "Default" then
            ns.Print("The Default profile can't be deleted.")
            return
        end
        confirm("Delete the profile '" .. name .. "'?\n\nYour markers are kept.", function() ns.DeleteProfile(name) end)
    end)
    delBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)

    local switchLabel = text("GameFontNormal", "TOPLEFT", newBtn, "BOTTOMLEFT", 0, -10, "Switch to:")
    local profileButtons = {}
    table.insert(refreshers, function()
        for _, b in ipairs(profileButtons) do b:Hide() end
        local prev
        for i, name in ipairs(ns.ProfileNames()) do
            local b = profileButtons[i]
            if not b then
                b = button("", 100, function(self) ns.UseProfile(self.profile) end)
                profileButtons[i] = b
            end
            b.profile = name
            b:SetText(name)
            b:SetEnabled(name ~= ns.ActiveProfile())
            b:ClearAllPoints()
            if not prev then
                b:SetPoint("LEFT", switchLabel, "RIGHT", 8, 0)
            elseif (i - 1) % 5 == 0 then
                b:SetPoint("TOPLEFT", profileButtons[i - 5], "BOTTOMLEFT", 0, -4)
            else
                b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
            end
            b:Show()
            prev = b
        end
    end)

    -------------------------------------------------------------------
    -- What this profile shows and records
    -------------------------------------------------------------------
    local typesHead = text("GameFontNormalLarge", "TOPLEFT", switchLabel, "BOTTOMLEFT", 0, -50, "Node types")
    local colShow = text("GameFontNormalSmall", "TOPLEFT", typesHead, "BOTTOMLEFT", 110, -6, "Show on map")
    local colRec = text("GameFontNormalSmall", "LEFT", colShow, "RIGHT", 20, 0, "Auto-tag on harvest")
    for i, t in ipairs(ns.TYPE_ORDER) do
        local rowY = -26 * i + 4
        text("GameFontHighlight", "TOPLEFT", typesHead, "BOTTOMLEFT", 4, -2 - 26 * i, ns.TYPES[t].label)
        checkbox(nil, "CENTER", colShow, "CENTER", 0, rowY,
            function() return ns.S().show[t] end,
            function(v) ns.S().show[t] = v end)
        -- Only mining and herbs can be detected when you harvest them.
        if t == "mine" or t == "herb" then
            checkbox(nil, "CENTER", colRec, "CENTER", 0, rowY,
                function() return ns.S().record[t] end,
                function(v) ns.S().record[t] = v end)
        end
    end

    local auto = checkbox("Auto-tag nodes when I harvest them (uses the ticks above)", "TOPLEFT", typesHead, "BOTTOMLEFT", 0, -6 - 26 * 5,
        function() return ns.S().auto end,
        function(v) ns.S().auto = v end)
    local mm = checkbox("Show markers on the minimap", "TOPLEFT", auto, "BOTTOMLEFT", 0, -2,
        function() return ns.S().minimap end,
        function(v) ns.S().minimap = v end)

    local shared = checkbox("Show markers shared by guildmates", "TOPLEFT", mm, "BOTTOMLEFT", 0, -2,
        function() return ns.S().showShared end,
        function(v) ns.S().showShared = v end)
    -- Sync is account-wide, not per profile.
    local sync = checkbox("Sync markers with my guild automatically (all profiles)", "TOPLEFT", shared, "BOTTOMLEFT", 0, -2,
        function() return ns.db.sync.guild end,
        function(v)
            ns.db.sync.guild = v
            if v and IsInGuild() then ns.SyncNow() end
        end)

    local near = checkbox("Hide a minimap marker while I'm standing at it", "TOPLEFT", sync, "BOTTOMLEFT", 0, -2,
        function() return ns.S().hideNear end,
        function(v) ns.S().hideNear = v end)
    local btn = checkbox("Show the Gather King minimap button (all profiles)", "TOPLEFT", near, "BOTTOMLEFT", 0, -2,
        function() return ns.db.ui.button end,
        function(v) ns.db.ui.button = v; ns.UpdateMinimapButton() end)

    local ledger = checkbox("Show the farming ledger box (all profiles)", "TOPLEFT", btn, "BOTTOMLEFT", 0, -2,
        function() return ns.db.ui.ledger end,
        function(v) ns.db.ui.ledger = v; ns.UpdateLedger() end)

    local onlyLabel = text("GameFontHighlight", "TOPLEFT", ledger, "BOTTOMLEFT", 4, -12, "Only show these names:")
    local only = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    only:SetSize(260, 20)
    only:SetAutoFocus(false)
    only:SetPoint("LEFT", onlyLabel, "RIGHT", 12, 0)
    local function saveOnly(self)
        ns.S().only = self:GetText() or ""
        self:ClearFocus()
        ns.Refresh()
    end
    only:SetScript("OnEnterPressed", saveOnly)
    only:SetScript("OnEditFocusLost", saveOnly)
    only:SetScript("OnEscapePressed", function(self) self:SetText(ns.S().only or ""); self:ClearFocus() end)
    table.insert(refreshers, function() only:SetText(ns.S().only or "") end)
    text("GameFontDisableSmall", "TOPLEFT", onlyLabel, "BOTTOMLEFT", 0, -6,
        "e.g. thorium, mithril, black lotus. Leave empty to show everything.")

    local sizeLabel = text("GameFontHighlight", "TOPLEFT", onlyLabel, "BOTTOMLEFT", 0, -30)
    local minus = button("-", 26, function()
        ns.S().size = math.max(8, ns.S().size - 2); ns.Refresh(); panel.refresh()
    end)
    minus:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
    local plus = button("+", 26, function()
        ns.S().size = math.min(32, ns.S().size + 2); ns.Refresh(); panel.refresh()
    end)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    table.insert(refreshers, function() sizeLabel:SetText("Marker size: " .. ns.S().size) end)

    -- Lower opacity lets the game's own node dot show through minimap markers.
    local alphaLabel = text("GameFontHighlight", "TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -14)
    local function stepAlpha(d)
        local v = math.floor(ns.S().minimapAlpha * 100 + 0.5) + d
        ns.S().minimapAlpha = math.min(100, math.max(10, v)) / 100
        ns.Refresh(); panel.refresh()
    end
    local aMinus = button("-", 26, function() stepAlpha(-10) end)
    aMinus:SetPoint("LEFT", alphaLabel, "RIGHT", 10, 0)
    local aPlus = button("+", 26, function() stepAlpha(10) end)
    aPlus:SetPoint("LEFT", aMinus, "RIGHT", 4, 0)
    table.insert(refreshers, function()
        alphaLabel:SetText("Minimap marker opacity: " .. math.floor(ns.S().minimapAlpha * 100 + 0.5) .. "%")
    end)

    -- Nodes you harvested recently show gray and faded until they've likely respawned.
    local fadeLabel = text("GameFontHighlight", "TOPLEFT", alphaLabel, "BOTTOMLEFT", 0, -14)
    local function stepFade(d)
        ns.S().fadeMinutes = math.min(30, math.max(0, (ns.S().fadeMinutes or 0) + d))
        ns.UpdatePinStates(); panel.refresh()
    end
    local fMinus = button("-", 26, function() stepFade(-1) end)
    fMinus:SetPoint("LEFT", fadeLabel, "RIGHT", 10, 0)
    local fPlus = button("+", 26, function() stepFade(1) end)
    fPlus:SetPoint("LEFT", fMinus, "RIGHT", 4, 0)
    table.insert(refreshers, function()
        local m = ns.S().fadeMinutes or 0
        fadeLabel:SetText("Fade nodes I harvested in the last: " .. (m == 0 and "off" or (m .. " min")))
    end)

    -------------------------------------------------------------------
    -- Delete (markers are shared by every profile)
    -------------------------------------------------------------------
    local del = text("GameFontNormalLarge", "TOPLEFT", fadeLabel, "BOTTOMLEFT", 0, -22, "Delete markers")
    local zoneText = text("GameFontHighlightSmall", "TOPLEFT", del, "BOTTOMLEFT", 0, -6)
    table.insert(refreshers, function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local n = mapID and ns.db.nodes[mapID] and #ns.db.nodes[mapID] or 0
        zoneText:SetText("Current zone: " .. (mapID and ns.MapName(mapID) or "unknown") .. " (" .. n ..
            " markers). Markers are shared by all profiles.")
    end)

    local function deleteRow(anchor, scope)
        local prev
        for _, t in ipairs({ "mine", "herb", "fish", "treasure", false }) do
            local b = button(t and ns.TYPES[t].label or "All types", 90, function()
                local what = (t and ns.TYPES[t].label or "all") .. " markers"
                if scope == "zone" then
                    local mapID = C_Map.GetBestMapForUnit("player")
                    if not mapID then return end
                    confirm("Delete " .. what .. " in " .. ns.MapName(mapID) .. "?\n\nYou can /gt undo until you /reload.",
                        function() ns.ClearZone(mapID, t or nil); panel.refresh() end)
                else
                    confirm("Delete " .. what .. " in EVERY zone?\n\nYou can /gt undo until you /reload.",
                        function() ns.ClearAll(t or nil); panel.refresh() end)
                end
            end)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", anchor, "LEFT", 150, 0) end
            prev = b
        end
    end

    local zoneLabel = text("GameFontNormal", "TOPLEFT", zoneText, "BOTTOMLEFT", 0, -14, "In this zone:")
    deleteRow(zoneLabel, "zone")
    local allLabel = text("GameFontNormal", "TOPLEFT", zoneLabel, "BOTTOMLEFT", 0, -18, "In every zone:")
    deleteRow(allLabel, "all")

    -------------------------------------------------------------------
    -- Share with friends outside the guild: export / import codes
    -------------------------------------------------------------------
    local shareHead = text("GameFontNormalLarge", "TOPLEFT", allLabel, "BOTTOMLEFT", 0, -26, "Share with friends")
    local shareHelp = text("GameFontHighlightSmall", "TOPLEFT", shareHead, "BOTTOMLEFT", 0, -6,
        "Export puts a code in the box: press Ctrl+C to copy it and paste it anywhere.\n" ..
        "To import, paste a friend's code in the box with Ctrl+V and click Import.")
    shareHelp:SetJustifyH("LEFT")

    local codeBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    codeBox:SetSize(540, 22)
    codeBox:SetAutoFocus(false)
    codeBox:SetMaxLetters(0)
    codeBox:SetPoint("TOPLEFT", shareHelp, "BOTTOMLEFT", 6, -34)
    codeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function showCode(code, n)
        if n == 0 then
            ns.Print("Nothing to export.")
            return
        end
        codeBox:SetText(code)
        codeBox:SetFocus()
        codeBox:HighlightText()
        ns.Print("Exported " .. n .. " marker(s). Press Ctrl+C to copy the code.")
    end
    local expAll = button("Export all", 100, function() showCode(ns.ExportCode()) end)
    expAll:SetPoint("TOPLEFT", shareHelp, "BOTTOMLEFT", 0, -6)
    local expZone = button("Export this zone", 130, function()
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then showCode(ns.ExportCode(mapID)) end
    end)
    expZone:SetPoint("LEFT", expAll, "RIGHT", 6, 0)
    local imp = button("Import", 100, function()
        ns.ImportCode(codeBox:GetText())
        codeBox:SetText("")
        codeBox:ClearFocus()
        panel.refresh()
    end)
    imp:SetPoint("TOPLEFT", codeBox, "BOTTOMLEFT", -6, -6)
end

function panel.refresh()
    if not ns.db or not panel.built then return end
    for _, fn in ipairs(refreshers) do fn() end
end
ns.RefreshSettings = panel.refresh

panel:SetScript("OnShow", function(self)
    if not self.built then
        build()
        self.built = true
    end
    self.refresh()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenSettings()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
