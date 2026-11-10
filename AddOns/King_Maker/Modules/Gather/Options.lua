local _, KM = ...
local ns = KM.Module("Gather")
local UI = KM.UI
local C = UI.C

-- The Gathering page of the King Maker window (Farming > Gathering), or /gt settings. It replaces Gather King's
-- Blizzard settings panel. Everything here belongs to the active profile, except the delete buttons, which act
-- on the markers shared by all profiles, and the account-wide ticks (guild sync, the ledger). This is the only
-- place with bulk "delete all" buttons.
--
--   top        a small summary: markers by type, zones, harvests recorded, this zone
--   left       profile (switch, new, delete), node types (show / auto-tag), the account-wide ticks
--   right      display: marker size, minimap markers and opacity, hide near, fade; only these names
--   bottom     delete markers (this zone / every zone), share with friends (export / import codes)
-- The page scrolls with the mouse wheel. Also here: the Gather section of the Settings page.

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

local function confirm(text, fn)
    StaticPopup_Show("GATHERKING_CONFIRM", text, nil, fn)
end

local page, child
local refreshers = {}
local COL2 = 390               -- x of the right column
local MIN_HEIGHT = 560         -- the scrolled content is at least the page

local function currentMap() return C_Map.GetBestMapForUnit("player") end

local function heading(text, x, y)
    local fs = UI.Heading(child, text)
    fs:SetPoint("TOPLEFT", x, y)
    return fs
end

local function check(label, x, y, get, set, tip)
    local cb = UI.CheckLabel(child, label, function(v) set(v and true or false); ns.Refresh(); KM.Refresh("gathering") end, tip)
    cb.frame:SetPoint("TOPLEFT", x, y)
    table.insert(refreshers, function() cb:SetChecked(get()) end)
    return cb
end

-- "Label    [-] value [+]"
local function stepper(label, x, y, fmt, step)
    local fs = UI.Text(child, 12, C.text)
    fs:SetPoint("TOPLEFT", x, y - 4)
    fs:SetText(label)
    local minus = UI.Button(child, "-", 24, 22, function() step(-1); KM.Refresh("gathering") end)
    minus:SetPoint("TOPLEFT", x + 200, y)
    local val = UI.Text(child, 12, C.accent, "CENTER")
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    val:SetWidth(64)
    local plus = UI.Button(child, "+", 24, 22, function() step(1); KM.Refresh("gathering") end)
    plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
    table.insert(refreshers, function() val:SetText(fmt()) end)
end

---------------------------------------------------------------------------
-- The summary line
---------------------------------------------------------------------------

function ns.NodeSummary()
    local byType, zones, total, harvests, shared = {}, 0, 0, 0, 0
    for _, list in pairs(ns.db.nodes) do
        if #list > 0 then zones = zones + 1 end
        for _, node in ipairs(list) do
            total = total + 1
            byType[node.t] = (byType[node.t] or 0) + 1
            if node.from then shared = shared + 1 end
            if node.stats then harvests = harvests + (node.stats.h or 0) end
        end
    end
    return { total = total, zones = zones, byType = byType, harvests = harvests, shared = shared }
end

local function summaryText()
    local s = ns.NodeSummary()
    local parts = {}
    for _, t in ipairs(ns.TYPE_ORDER) do
        if s.byType[t] then parts[#parts + 1] = s.byType[t] .. " " .. ns.TYPES[t].label:lower() end
    end
    local mapID = currentMap()
    local here = mapID and ns.db.nodes[mapID] and #ns.db.nodes[mapID] or 0
    return KM.Commas(s.total) .. " markers in " .. s.zones .. " zone" .. (s.zones == 1 and "" or "s")
        .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
        .. (s.shared > 0 and (", " .. s.shared .. " from guildmates") or "") .. ".  "
        .. KM.Commas(s.harvests) .. " harvests recorded.  "
        .. (mapID and (ns.MapName(mapID) .. ": " .. here .. " marker" .. (here == 1 and "" or "s") .. ".") or "")
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function buildProfiles(y)
    heading("Profile", 0, y)
    local using = UI.Text(child, 12, C.muted)
    using:SetPoint("TOPLEFT", 70, y + 1)
    table.insert(refreshers, function() using:SetText("Using: |cfff0c44d" .. ns.ActiveProfile() .. "|r") end)

    -- Switch: one button per profile, three to a row (up to six shown; /gt profile lists them all).
    local buttons = {}
    for i = 1, 6 do
        local b = UI.Button(child, "", 116, 22, function(self) if self.profile then ns.UseProfile(self.profile); KM.Refresh("gathering") end end)
        b:SetPoint("TOPLEFT", ((i - 1) % 3) * 122, y - 22 - math.floor((i - 1) / 3) * 26)
        buttons[i] = b
    end
    table.insert(refreshers, function()
        local names = ns.ProfileNames()
        for i, b in ipairs(buttons) do
            local name = names[i]
            b.profile = name
            if name then
                b:SetLabel(name)
                b:SetActive(name == ns.ActiveProfile())
                b:Show()
            else
                b:Hide()
            end
        end
    end)

    local newBox = UI.EditBox(child, 180, 22, "New profile name")
    newBox:SetPoint("TOPLEFT", 0, y - 80)
    local function create()
        local name = newBox:GetText() or ""
        if name:match("^%s*$") then KM.Print(ns, "Type a name for the new profile first (it starts as a copy of this one).") return end
        ns.NewProfile(name)
        newBox:SetText("")
        newBox:ClearFocus()
        KM.Refresh("gathering")
    end
    newBox:SetScript("OnEnterPressed", create)
    local newBtn = UI.Button(child, "Create", 70, 22, create)
    newBtn:SetPoint("LEFT", newBox, "RIGHT", 6, 0)
    UI.Tip(newBtn, "A new profile starts as a copy of the one you're using.")
    local delBtn = UI.Button(child, "Delete this profile", 112, 22, function()
        local name = ns.ActiveProfile()
        if name == "Default" then
            KM.Print(ns, "The Default profile can't be deleted.")
            return
        end
        confirm("Delete the profile '" .. name .. "'?\n\nYour markers are kept.", function() ns.DeleteProfile(name); KM.Refresh("gathering") end)
    end)
    delBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
    return y - 116
end

local function buildTypes(y)
    heading("Node types", 0, y)
    local showHead = UI.Text(child, 9, C.muted, "CENTER")
    showHead:SetPoint("TOPLEFT", 110, y - 20)
    showHead:SetWidth(90)
    showHead:SetText("SHOW ON MAP")
    local recHead = UI.Text(child, 9, C.muted, "CENTER")
    recHead:SetPoint("TOPLEFT", 210, y - 20)
    recHead:SetWidth(120)
    recHead:SetText("AUTO-TAG ON HARVEST")
    for i, t in ipairs(ns.TYPE_ORDER) do
        local rowY = y - 18 - 24 * i
        local label = UI.Text(child, 12, C.text)
        label:SetPoint("TOPLEFT", 0, rowY - 2)
        label:SetText(ns.TYPES[t].label)
        local show = UI.Check(child, function(v) ns.S().show[t] = v; ns.Refresh() end)
        show:SetPoint("TOPLEFT", 147, rowY)
        table.insert(refreshers, function() show:SetChecked(ns.S().show[t]) end)
        -- Only mining and herbs can be detected when you harvest them.
        if t == "mine" or t == "herb" then
            local rec = UI.Check(child, function(v) ns.S().record[t] = v end)
            rec:SetPoint("TOPLEFT", 262, rowY)
            table.insert(refreshers, function() rec:SetChecked(ns.S().record[t]) end)
        end
    end
    y = y - 18 - 24 * 5
    check("Auto-tag nodes when I harvest them", 0, y, function() return ns.S().auto end, function(v) ns.S().auto = v end,
        "The master switch: uses the auto-tag ticks above. Harvests still fade markers that exist with it off.")
    check("Show markers shared by guildmates", 0, y - 24, function() return ns.S().showShared end, function(v) ns.S().showShared = v end)
    check("Sync markers with my guild (all profiles)", 0, y - 48, function() return ns.db.sync.guild end, function(v)
        ns.db.sync.guild = v
        if v and IsInGuild() then ns.SyncNow() end
    end, "Markers you add go to guildmates running King Maker or Gather King; theirs come to you. Deletes stay yours.")
    check("Show the farming ledger box (all profiles)", 0, y - 72, function() return ns.db.ui.ledger end, function(v)
        ns.db.ui.ledger = v
        ns.UpdateLedger()
    end, "A small floating box with everything you've gathered, its value, and gold per hour while its timer runs.")
    return y - 100
end

local function buildDisplay(y)
    local x = COL2
    heading("Display", x, y)
    stepper("World map marker size", x, y - 22, function() return tostring(ns.S().size) end, function(d)
        ns.S().size = math.max(8, math.min(32, ns.S().size + 2 * d)); ns.Refresh()
    end)
    check("Show markers on the minimap", x, y - 52, function() return ns.S().minimap end, function(v) ns.S().minimap = v end)
    -- Lower opacity lets the game's own node dot show through minimap markers.
    stepper("Minimap marker opacity", x, y - 78, function() return math.floor(ns.S().minimapAlpha * 100 + 0.5) .. "%" end, function(d)
        local v = math.floor(ns.S().minimapAlpha * 100 + 0.5) + 10 * d
        ns.S().minimapAlpha = math.min(100, math.max(10, v)) / 100
        ns.Refresh()
    end)
    check("Hide a minimap marker while I'm standing at it", x, y - 108, function() return ns.S().hideNear end,
        function(v) ns.S().hideNear = v end)
    -- Nodes you harvested recently show gray and faded until they've likely respawned.
    stepper("Fade harvested nodes for", x, y - 134, function()
        local m = ns.S().fadeMinutes or 0
        return m == 0 and "off" or (m .. " min")
    end, function(d)
        ns.S().fadeMinutes = math.min(30, math.max(0, (ns.S().fadeMinutes or 0) + d))
        ns.UpdatePinStates()
    end)

    heading("Only show these names", x, y - 174)
    local only = UI.EditBox(child, 300, 22, "e.g. thorium, mithril, black lotus")
    only:SetPoint("TOPLEFT", x, y - 194)
    local function saveOnly(self)
        ns.S().only = self:GetText() or ""
        self:ClearFocus()
        ns.Refresh()
    end
    only:SetScript("OnEnterPressed", saveOnly)
    only:HookScript("OnEditFocusLost", function(self) if (self:GetText() or "") ~= (ns.S().only or "") then saveOnly(self) end end)
    only:SetScript("OnEscapePressed", function(self) self:SetText(ns.S().only or ""); self:ClearFocus() end)
    table.insert(refreshers, function() if not only.focused then only:SetText(ns.S().only or "") end end)
    page.only = only
    local hint = UI.Text(child, 10, C.dim)
    hint:SetPoint("TOPLEFT", x, y - 222)
    hint:SetText("Leave empty to show everything. Press Enter to apply.")
end

local function deleteRow(y, scope)
    local label = UI.Text(child, 12, C.text)
    label:SetPoint("TOPLEFT", 0, y - 4)
    label:SetText(scope == "zone" and "In this zone:" or "In every zone:")
    local x = 110
    for _, t in ipairs({ "mine", "herb", "fish", "treasure", false }) do
        local b = UI.Button(child, t and ns.TYPES[t].label or "All types", 92, 22, function()
            local what = (t and ns.TYPES[t].label or "all") .. " markers"
            if scope == "zone" then
                local mapID = currentMap()
                if not mapID then return end
                confirm("Delete " .. what .. " in " .. ns.MapName(mapID) .. "?\n\nYou can /gt undo until you /reload.",
                    function() ns.ClearZone(mapID, t or nil); KM.Refresh("gathering") end)
            else
                confirm("Delete " .. what .. " in EVERY zone?\n\nYou can /gt undo until you /reload.",
                    function() ns.ClearAll(t or nil); KM.Refresh("gathering") end)
            end
        end)
        b.scope = scope
        b:SetPoint("TOPLEFT", x, y)
        x = x + 98
    end
end

local function buildDelete(y)
    heading("Delete markers", 0, y)
    local zoneText = UI.Text(child, 11, C.muted)
    zoneText:SetPoint("TOPLEFT", 140, y + 1)
    table.insert(refreshers, function()
        local mapID = currentMap()
        local n = mapID and ns.db.nodes[mapID] and #ns.db.nodes[mapID] or 0
        zoneText:SetText("Current zone: " .. (mapID and ns.MapName(mapID) or "unknown") .. " (" .. n ..
            " markers). Markers are shared by all profiles.")
    end)
    deleteRow(y - 22, "zone")
    deleteRow(y - 50, "all")
    return y - 86
end

local function buildShare(y)
    heading("Share with friends", 0, y)
    local help = UI.Text(child, 11, C.muted)
    help:SetPoint("TOPLEFT", 160, y + 1)
    help:SetText("Export puts a code in the box: Ctrl+C copies it. Paste a friend's code with Ctrl+V, then Import.")

    local codeBox = UI.EditBox(child, 740, 24, "Export a code, or paste one here")
    codeBox:SetPoint("TOPLEFT", 0, y - 54)
    if codeBox.SetMaxLetters then codeBox:SetMaxLetters(0) end
    page.codeBox = codeBox
    local function showCode(code, n)
        if n == 0 then
            KM.Print(ns, "Nothing to export.")
            return
        end
        codeBox:SetText(code)
        codeBox:SetFocus()
        codeBox:HighlightText()
        KM.Print(ns, "Exported " .. n .. " marker(s). Press Ctrl+C to copy the code.")
    end
    local expAll = UI.Button(child, "Export all", 100, 22, function() showCode(ns.ExportCode()) end)
    expAll:SetPoint("TOPLEFT", 0, y - 22)
    local expZone = UI.Button(child, "Export this zone", 130, 22, function()
        local mapID = currentMap()
        if mapID then showCode(ns.ExportCode(mapID)) end
    end)
    expZone:SetPoint("LEFT", expAll, "RIGHT", 6, 0)
    local imp = UI.Button(child, "Import", 100, 22, function()
        ns.ImportCode(codeBox:GetText())
        codeBox:SetText("")
        codeBox:ClearFocus()
        KM.Refresh("gathering")
    end, "primary")
    imp:SetPoint("LEFT", expZone, "RIGHT", 6, 0)
    return y - 90
end

local function buildPage(c)
    page = c
    local scroll = UI.Scroll(c)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    child = scroll.child
    child:SetWidth(760)
    page.scroll = scroll

    local summary = UI.Panel(child, C.panel)
    summary:SetPoint("TOPLEFT", 0, 0)
    summary:SetSize(756, 34)
    summary.text = UI.Text(summary, 11, C.text)
    summary.text:SetPoint("LEFT", 10, 0)
    summary.text:SetPoint("RIGHT", -10, 0)
    table.insert(refreshers, function() summary.text:SetText(summaryText()) end)
    page.summary = summary.text

    local y = buildProfiles(-50)
    y = buildTypes(y)
    buildDisplay(-50)
    y = buildDelete(math.min(y, -330) - 4)
    y = buildShare(y)
    scroll:SetContentHeight(math.max(MIN_HEIGHT, -y + 10))
end

local function refresh()
    if not ns.db or not page then return end
    for _, fn in ipairs(refreshers) do fn() end
end

-- Slash commands and the HUD call this after changing something the page shows.
function ns.RefreshSettings()
    KM.Refresh("gathering")
    KM.Refresh("settings")
end

function ns.OpenSettings() KM.Show("gathering") end

KM.RegisterPage({
    id = "gathering", group = "farm", label = "Gathering", icon = "Interface\\Icons\\Trade_Mining", order = 20,
    title = "Gathering",
    subtitle = function()
        if not ns.db then return "" end
        return "Gathering spots on your map, shared with your guild. Profile: " .. ns.ActiveProfile() .. "."
    end,
    build = buildPage, refresh = refresh,
})

---------------------------------------------------------------------------
-- Settings section: a pointer to the page plus the most-used toggles
---------------------------------------------------------------------------

KM.RegisterSettings({ id = "gather", label = "Gather", order = 45, rows = function()
    local profiles = {}
    for _, name in ipairs(ns.db and ns.ProfileNames() or {}) do profiles[#profiles + 1] = { name, name } end
    return {
        { type = "text", label = "Every gathering option (profiles, node types, marker size and opacity, deleting markers, export and import codes) is on the Gathering page." },
        { type = "button", label = "Open the Gathering page", func = function() ns.OpenSettings() end },
        { type = "header", label = "Active profile" },
        { type = "choice", label = "Profile", options = profiles, get = function() return ns.ActiveProfile() end,
          set = function(v) ns.UseProfile(v) end },
        { type = "header", label = "Markers (this profile)" },
        { type = "check", label = "Auto-tag nodes when I harvest them", get = function() return ns.S().auto end,
          set = function(v) ns.S().auto = v end },
        { type = "check", label = "Show markers on the minimap", get = function() return ns.S().minimap end,
          set = function(v) ns.S().minimap = v; ns.Refresh() end },
        { type = "header", label = "All profiles" },
        { type = "check", label = "Sync markers with my guild", get = function() return ns.db.sync.guild end,
          set = function(v) ns.db.sync.guild = v; if v and IsInGuild() then ns.SyncNow() end end },
        { type = "check", label = "Show the farming ledger box", get = function() return ns.db.ui.ledger end,
          set = function(v) ns.db.ui.ledger = v; ns.UpdateLedger() end },
        { type = "header", label = "Commands" },
        { type = "text", label = "/gt mine|herb|fish|treasure [name]   mark a node here\n/gt delete nearby   /gt undo   /gt list\n"
            .. "/gt profile [name|new <name>|delete <name>]\n/gt ledger [on|off|reset|timer]   /gt settings   /gt help for the rest" },
    }
end })
