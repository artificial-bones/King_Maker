local _, KM = ...
local ns = KM.Module("Shopping")
local UI = KM.UI
local C = UI.C

-- The Shopping page (Auction House > Shopping): your lists on the left (deals counted on each), the chosen list on
-- the right with what decides a purchase: lowest price, your max, how far under or over it, how many you still want,
-- what that costs and where the price is going. Deals are tinted and sorted first. Below the table, the list's
-- totals, or the selected item's editor, facts and a 30-day price line. Add items by shift-clicking a link into the
-- add box, or by typing a name or item ID. Lists can be shared as a short text code (Export / Import). Live lists
-- (another addon supplies them, ShoppingKing.RegisterListProvider) show and buy like any list but are read-only.
-- An item is either "Buy N" (Want counts down as you buy) or "Keep N in stock" (2.6.2: the need is N minus what you
-- own, it refills as you use them): the editor's Buy | Keep switch, "keep 20" in the Want column.
--
-- The window draws for a fixed size and zooms with SetScale, so everything here is anchored to the page's edges.

local SIDE_W, SIDE_ROWS, SIDE_H = 168, 11, 26
local ROW_H, BAR_H = 22, 140
local page, tbl, footer, bar
local sideButtons, sideOffset = {}, 0
local addBox, wantBox, maxBox, addInfo, addWidgets
local edit, tiles = {}, {}
local selected      -- itemID being edited
local codeWin, graph
local allBox
local msgToken = 0   -- a message shows for 6 s, then the footer's hint comes back
local data = {}

local DASH = "|cff808080-|r"

local function hintText()
    local last = ScannerKing and ScannerKing.LastScan and KM.Safe(ScannerKing.LastScan)
    local scanning = ScannerKing and ScannerKing.IsScanning and KM.Safe(ScannerKing.IsScanning)
    return #data .. " items   Last scan " .. (scanning and "running..." or (last and KM.Ago(last) or "never"))
        .. "   /shop deals prints today's deals"
end

local function say(text, color)
    if not footer then return end
    msgToken = msgToken + 1
    local my = msgToken
    footer.msg = text ~= nil and text ~= ""
    footer:SetText(text or "")
    local c = color or C.muted
    footer:SetTextColor(c[1], c[2], c[3], 1)
    if footer.msg and C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            if msgToken ~= my or not footer then return end
            footer.msg = false
            footer:SetText(hintText())
            footer:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
        end)
    end
end
ns.PageSay = say

local function liveText(name)
    local owner = ns.ProviderInfo(name) or "another addon"
    return name .. " is a live list from " .. owner .. ": read-only here. Add items to one of your own lists."
end

---------------------------------------------------------------------------
-- Popups: name a list, delete a list (entries are added to StaticPopupDialogs, never replacing it)
---------------------------------------------------------------------------

local function popupText(self)
    local eb = self and (self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()))
    return eb and eb:GetText() or ""
end

local function acceptName(self, d)
    local text = popupText(self)
    if d and d.mode == "rename" then
        if not ns.IsMine(d.list) then say("Favorites and live lists can't be renamed.", C.warn)
        elseif ns.RenameList(d.list, text) then say("Renamed to " .. ns.CleanName(text) .. ".", C.good)
        else say("Can't rename: that name is empty or already used.", C.warn) end
    else
        local name = ns.CreateList(text)
        if name then ns.SetActive(name); selected = nil; say("Made the list " .. name .. ".", C.good)
        else say("Can't make that list: the name is empty or already used.", C.warn) end
    end
    KM.Refresh("shopping")
end

StaticPopupDialogs["KINGMAKER_SHOPPING_NAME"] = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 32,
    OnAccept = acceptName,
    OnShow = function(self, d)
        local eb = self.editBox or self.EditBox
        if eb and eb.SetText and d and d.mode == "rename" then eb:SetText(d.list) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        acceptName(p, p.data)
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["KINGMAKER_SHOPPING_DELETE"] = {
    text = "Delete the shopping list \"%s\"?", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, d)
        if d and ns.DeleteList(d.list) then selected = nil; say("Deleted " .. d.list .. ".", C.muted) end
        KM.Refresh("shopping")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Export / import window
---------------------------------------------------------------------------

local function openCode(mode)
    if not codeWin then
        codeWin = UI.Window("KingMakerShoppingCode", "Shopping list code", 480, 150)
        local b = codeWin.body
        codeWin.box = UI.EditBox(b, 452, 26, "Paste a code that starts with KMS1:")
        codeWin.box:SetPoint("TOPLEFT", 0, -6)
        if codeWin.box.SetMaxLetters then codeWin.box:SetMaxLetters(0) end
        codeWin.note = UI.Para(b, 11, C.muted, 452)
        codeWin.note:SetPoint("TOPLEFT", 0, -42)
        codeWin.go = UI.Button(b, "Import", 90, 24, function()
            local name, n = ns.Import(codeWin.box:GetText())
            if name then
                ns.SetActive(name)
                selected = nil
                codeWin:Hide()
                say("Imported " .. n .. " items into " .. name .. ".", C.good)
                KM.Refresh("shopping")
            else
                codeWin.note:SetText(UI.Hex(C.bad) .. tostring(n) .. "|r")
            end
        end, "primary")
        codeWin.go:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    codeWin.mode = mode
    if mode == "export" then
        local name = ns.Active()
        codeWin:SetTitle("Export " .. name)
        codeWin.box:SetText(ns.Export(name))
        codeWin.note:SetText("Copy this (Ctrl+C) and send it to a friend or another character; Import on the Shopping page reads it."
            .. (ns.IsVirtual(name) and " Importing it makes a saved copy of this live list." or ""))
        codeWin.go:Hide()
        codeWin:Show()
        codeWin.box:SetFocus()
        codeWin.box:HighlightText()
    else
        codeWin:SetTitle("Import a shopping list")
        codeWin.box:SetText("")
        codeWin.note:SetText("Paste a code (Ctrl+V) and click Import. Items join the list named in the code (made if it doesn't exist).")
        codeWin.go:Show()
        codeWin:Show()
        codeWin.box:SetFocus()
    end
end
ns.OpenCode = openCode

---------------------------------------------------------------------------
-- Adding and editing
---------------------------------------------------------------------------

local function addFromBoxes()
    if not ns.IsEditable(ns.Active()) then say(liveText(ns.Active()), C.warn) return false end
    local text = addBox:GetText() or ""
    local id = ns.ItemFrom(text)
    if not id then
        say(text == "" and "Shift-click an item into the box, or type its name or item ID."
            or "No item called \"" .. text .. "\" yet: shift-click it, or type its item ID (names work once the item has been seen).", C.warn)
        return false
    end
    local maxText = maxBox:GetText() or ""
    local max = ns.ParseMoney(maxText)
    if maxText ~= "" and not max then say("Max price: type it like 1g 50s, 75s or 2.5 (gold).", C.warn) return false end
    local qty = tonumber(wantBox:GetText() or "")
    local ok, name = ns.AddTo(ns.Active(), id, qty, max)
    if not ok then say("Couldn't add that item.", C.bad) return false end
    addBox:SetText(""); wantBox:SetText(""); maxBox:SetText("")
    addBox:ClearFocus()
    selected = id
    edit.filledFor = nil
    say(ns.Name(id) .. " added to " .. name .. ".", C.good)
    KM.Refresh("shopping")
    return true
end
ns.AddFromBoxes = addFromBoxes

-- Shift-clicking an item while the add box has focus puts its link there (like chat).
local function insertLink(link)
    if type(link) ~= "string" or not link:find("item:") then return end
    if addBox and addBox.focused and addBox:IsVisible() then addBox:SetText(link) end
end
if hooksecurefunc then
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
    if type(ChatFrameUtil) == "table" and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end
end
ns.InsertLink = insertLink

-- What a blank Max means, and a nudge: the item's 7-day average once the add box names an item (never filled in).
local function maxHint()
    if not maxBox then return end
    local hint = ns.db.settings.defaultMax == "market" and "market" or "no limit"
    local id = addBox and ns.ItemFrom(addBox:GetText() or "")
    local s = id and ns.Stats(id)
    if s and s.avg7 then hint = "7d " .. ns.Short(s.avg7, true) end
    maxBox.hint:SetText(hint)
end

local function saveEdit()
    if not selected then return false end
    local active = ns.Active()
    if not ns.IsEditable(active) then say("Can't edit a live list: change it in " .. (ns.ProviderInfo(active) or "its addon") .. ".", C.warn) return false end
    local maxText = edit.max:GetText() or ""
    local max = ns.ParseMoney(maxText)
    if maxText ~= "" and not max then say("Max price: type it like 1g 50s, 75s or 2.5 (gold).", C.warn) return false end
    local qty = tonumber(edit.want:GetText() or "")
    local note = edit.note:GetText() or ""
    local fields = { max = max or false, note = note ~= "" and note or false }
    if edit.modeID == "keep" then
        if not qty or qty < 1 then say("Keep how many in stock? Type a number next to Keep.", C.warn) return false end
        local e = ns.Find(active, selected)
        fields.keep, fields.qty = math.floor(qty), false
        if e and tonumber(e.keep) ~= fields.keep then fields.transit = false end
    else
        fields.qty, fields.keep, fields.transit = qty or false, false, false
    end
    for _, b in ipairs({ edit.max, edit.want, edit.note }) do b:ClearFocus() end
    local ok = ns.Update(active, selected, fields)
    edit.filledFor = nil
    if ok then say("Saved.", C.good) else say("Couldn't save: that item is no longer on " .. active .. ".", C.warn) end
    KM.Refresh("shopping")
    return ok
end
ns.SaveEdit = saveEdit

local function removeSelected()
    if not selected then return end
    local id, active = selected, ns.Active()
    if not ns.IsEditable(active) then say(liveText(active), C.warn) return end
    if ns.RemoveFrom(active, id) then say(ns.Name(id) .. " removed.", C.muted) end
    selected = nil
    KM.Refresh("shopping")
end

local function openHistory(id)
    local E = KM.mods.Econ
    if not (E and E.ShowItem) then return false end
    KM.Show("history")
    KM.Safe(E.ShowItem, id)
    return true
end
ns.OpenHistory = openHistory

---------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------

local function rowsData()
    local out = {}
    for _, e in ipairs(ns.Entries(ns.Active()) or {}) do out[#out + 1] = ns.Row(e) end
    return out
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end

local function fillRow(r, row, cells)
    r.item = row.id
    if r.icon then r.icon:SetTexture(ns.Icon(row.id)) end
    r.sel:SetShown(selected == row.id)
    local deal = row.status == "under"
    local dim = not deal and row.status ~= "nomax"
    -- rows are pooled: every per-row look is set each time
    if deal and not r.deal then
        r.deal = UI.Fill(r, { C.good[1], C.good[2], C.good[3], 0.07 }, "BORDER")
        r.dealBar = r:CreateTexture(nil, "ARTWORK")
        r.dealBar:SetTexture(UI.WHITE)
        r.dealBar:SetPoint("TOPLEFT"); r.dealBar:SetPoint("BOTTOMLEFT"); r.dealBar:SetWidth(2)
        UI.SetColor(r.dealBar, C.good)
    end
    if r.deal then r.deal:SetShown(deal); r.dealBar:SetShown(deal) end
    cells.name:SetText(ns.ColoredName(row.id))
    cells.name:SetAlpha(dim and 0.7 or 1)
    local num = dim and C.dim or C.text
    cells.lowest:SetText(row.lowest and ns.Short(row.lowest, dim) or DASH)
    setColor(cells.lowest, deal and C.good or num)
    cells.max:SetText(row.max and (ns.Short(row.max, dim or row.fromMarket) .. (row.fromMarket and "*" or "")) or DASH)
    setColor(cells.max, (row.fromMarket or dim) and C.dim or C.text)
    cells.pct:SetText(ns.Pct(row.pct) or DASH)
    setColor(cells.pct, deal and C.good or (row.pct and C.muted or C.dim))
    if row.keep then
        cells.qty:SetText("keep " .. row.keep)
        setColor(cells.qty, C.info)
    else
        cells.qty:SetText(row.qty and tostring(row.qty) or DASH)
        setColor(cells.qty, row.status == "done" and C.info or num)
    end
    local own = row.keep and row.owned or row.own
    cells.own:SetText(own and KM.Commas(own) or DASH)
    setColor(cells.own, num)
    cells.cost:SetText(row.cost and ns.Short(row.cost, not deal) or DASH)
    setColor(cells.cost, deal and C.good or C.dim)
    cells.trend:SetText(ns.Trend(row.trend7))
    local text, col = ns.StatusLabel(row)
    cells.status:SetText(text)
    setColor(cells.status, col)
end

local function ownText(by, total)
    if not by then return total and KM.Commas(total) or nil end
    local list = {}
    for name, n in pairs(by) do if (tonumber(n) or 0) > 0 then list[#list + 1] = { (name:match("^[^-]+") or name), n } end end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local parts = {}
    for i, x in ipairs(list) do
        if i > 3 then parts[#parts + 1] = "+" .. (#list - 3) break end
        parts[#parts + 1] = x[1] .. " " .. x[2]
    end
    return KM.Commas(total or 0) .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
end

local function seenText(row)
    if not row.t then return "" end
    return " (" .. (row.live and "searched " or "scan ") .. KM.Ago(row.t) .. ")"
end

local function rowTooltip(rf)
    local row = rf.data
    if not row then return end
    local tt = GameTooltip
    tt:SetOwner(rf, "ANCHOR_RIGHT")
    if tt.SetItemByID then pcall(tt.SetItemByID, tt, row.id) end
    tt:AddLine(" ")
    tt:AddLine("Lowest " .. KM.Money(row.lowest) .. seenText(row), 1, 1, 1)
    if row.max then
        local d = row.pct and ("   " .. ns.Pct(math.abs(row.pct)):gsub("^%+", "") .. (row.diff <= 0 and " under" or " over")
            .. " (" .. KM.Money(math.abs(row.diff)) .. " each)") or ""
        tt:AddLine("Your max " .. KM.Money(row.max) .. (row.fromMarket and " (market: no max of your own)" or "") .. d, 1, 1, 1)
    end
    tt:AddLine("Market " .. KM.Money(row.market) .. "   Listed " .. (row.listed and KM.Commas(row.listed) or "-")
        .. (row.underQty and ("  (under your max: " .. KM.Commas(row.underQty) .. ", searched)") or ""), 0.8, 0.8, 0.8)
    if row.avg7 or row.low30 then
        tt:AddLine((row.avg7 and ("7-day avg " .. KM.Money(row.avg7) .. " (" .. ns.Trend(row.trend7) .. ")") or "")
            .. (row.low30 and ("   30 days " .. ns.Short(row.low30) .. " - " .. ns.Short(row.high30)) or ""), 0.8, 0.8, 0.8)
    end
    local own = ownText(row.ownBy, row.own)
    if own then tt:AddLine("Own " .. own, 0.8, 0.8, 0.8) end
    local basis = ns.BasisText(row.basis)
    if basis then tt:AddLine(basis, 0.8, 0.8, 0.8, true) end
    if row.keep then
        tt:AddLine("Keep " .. row.keep .. " in stock: you have " .. KM.Commas(row.owned or 0)
            .. (InventoryKing and " on this realm and faction" or " (Inventory is off: counted as none)")
            .. ((row.coming or 0) > 0 and (", " .. row.coming .. " bought and on the way") or "")
            .. ", so " .. (row.qty > 0 and ("buy " .. row.qty) or "nothing to buy") .. ". It doesn't count down; it refills as you use them.",
            C.info[1], C.info[2], C.info[3], true)
    end
    if row.e.note then tt:AddLine("Note: " .. row.e.note, 0.6, 0.6, 0.6, true) end
    tt:AddLine(ns.IsEditable(ns.Active()) and "Click to edit   Right-click for more" or "Click for details   Right-click for more", 0.42, 0.42, 0.44)
    tt:Show()
end

local function rowMenu(row)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local active = ns.Active()
    MenuUtil.CreateContextMenu(page, function(_, root)
        root:CreateTitle(row.name)
        if ns.AHOpen() and ns.FindItem then
            root:CreateButton("Search at the auction house", function() ns.FindItem(row.id) end)
        end
        if KM.mods.Econ and KM.mods.Econ.ShowItem then
            root:CreateButton("Open in Price History", function() openHistory(row.id) end)
        end
        if ns.IsEditable(active) then
            root:CreateButton("Remove from " .. active, function() selected = row.id; removeSelected() end)
        end
        for _, name in ipairs(ns.ListNames()) do
            if name ~= active and ns.IsEditable(name) then
                root:CreateButton("Also add to " .. name, function()
                    local e = row.e
                    if ns.AddTo(name, e.id, e.qty, e.max, e.note) then
                        if e.keep then ns.SetKeep(name, e.id, e.keep) end
                        say(row.name .. " added to " .. name .. ".", C.good)
                    else say("Couldn't add " .. row.name .. " to " .. name .. ".", C.warn) end
                end)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- The detail pane: the list's totals, or the selected item
---------------------------------------------------------------------------

local function fillSummary()
    local active = ns.Active()
    local s = ns.Summary(active)
    local t1, t2, t3, t4 = tiles[1], tiles[2], tiles[3], tiles[4]
    t1:Set("Deals now", s.deals .. " of " .. s.items, s.over .. " above max" .. (s.noPrice > 0 and ("   " .. s.noPrice .. " no scan") or ""),
        s.deals > 0 and C.good or C.text)
    t2:Set("Cost of deals", s.deals > 0 and ns.Short(s.dealsCost) or DASH, s.deals > 0 and ("saves " .. ns.Short(s.dealsSave, true) .. " vs your max") or "nothing under your max")
    local notDone = s.items - s.done
    t3:Set("Fill all at max", s.fillMax > 0 and ns.Short(s.fillMax) or DASH,
        s.noMax > 0 and (s.noMax .. " item" .. (s.noMax == 1 and " has" or "s have") .. " no max") or ("budget, " .. notDone .. " item" .. (notDone == 1 and "" or "s")))
    if s.noMax > 0 then t3.sub:SetTextColor(C.warn[1], C.warn[2], C.warn[3], 1) else t3.sub:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1) end
    local last = ScannerKing and ScannerKing.LastScan and KM.Safe(ScannerKing.LastScan)
    local scanning = ScannerKing and ScannerKing.IsScanning and KM.Safe(ScannerKing.IsScanning)
    local age = last and (KM.Now() - last) or nil
    t4:Set("Prices", last and (KM.Ago(last) .. (KM.Ago(last) == "now" and "" or " ago")) or "never",
        scanning and "Scanning..." or "Search at the AH for live prices",
        (not age or age > 86400) and C.bad or (age > 7200 and C.warn or C.text))
    edit.hint:SetText(s.items == 0 and "" or (ns.IsEditable(active)
        and "Click an item to edit its max, want and note. Right-click for more. Deals are sorted first."
        or "Click an item for its details. Right-click for more."))
    local owner, note = ns.ProviderInfo(active)
    edit.vhint:SetText(owner and ("Live list from " .. owner .. ": it changes itself; buy it at the auction house." .. (note and ("  " .. note) or "")) or "")
end

local function drawGraph(row)
    local E = KM.mods.Econ
    if not graph and E and E.CreateGraph and EconKing and EconKing.GetHistory then
        graph = KM.Safe(E.CreateGraph, bar, 218, 68)
        if graph then graph.frame:SetPoint("TOPLEFT", bar, "TOPLEFT", 356, -4) end
        ns.graph = graph
    end
    edit.graphOff:SetShown(not graph)
    edit.history:SetShown(graph ~= nil and E.ShowItem ~= nil)
    if not graph then return end
    graph.frame:Show()
    local now = KM.Now()
    local tmin = now - 30 * 86400
    local pts = {}
    for _, v in ipairs(KM.Safe(EconKing.GetHistory, row.id) or {}) do
        local val = (not row.lowestOnly and v[2]) or v[3]
        if v[1] and val and v[1] >= tmin then pts[#pts + 1] = { v[1], val } end
    end
    local series = {}
    if #pts > 0 then
        series[1] = { pts = pts, color = C.accent, style = "line" }
        if row.max then series[2] = { pts = { { tmin, row.max }, { now, row.max } }, color = { C.warn[1], C.warn[2], C.warn[3], 0.7 }, style = "line" } end
    end
    KM.Safe(graph.Draw, graph, { tmin = tmin, tmax = now, series = series, emptyText = "No scans yet",
        format = function(v) return ns.Short(v, true) end })
end

local EDITORS = { "maxL", "max", "suggest", "mode", "want", "noteL", "note", "save", "remove" }

local function fillEdit()
    local active = ns.Active()
    local row
    if selected then for _, r in ipairs(data) do if r.id == selected then row = r end end end
    if not row then selected = nil end
    local has = row ~= nil
    for _, t in ipairs(tiles) do t:SetShown(not has) end
    edit.hint:SetShown(not has); edit.vhint:SetShown(not has)
    for _, k in ipairs({ "icon", "name", "status", "facts1", "facts2" }) do edit[k]:SetShown(has) end
    if not has then
        for _, k in ipairs(EDITORS) do edit[k]:Hide() end
        edit.virtual:Hide(); edit.graphOff:Hide(); edit.history:Hide()
        if graph then graph.frame:Hide() end
        edit.filledFor = nil
        fillSummary()
        return
    end
    local editable = ns.IsEditable(active)
    for _, k in ipairs(EDITORS) do edit[k]:SetShown(editable) end
    edit.virtual:SetShown(not editable)
    edit.icon:SetTexture(ns.Icon(row.id))
    edit.name:SetText(ns.ColoredName(row.id))
    local text, col = ns.StatusLabel(row)
    if row.status == "over" then text, col = "OVER", C.muted end
    edit.status:SetText(UI.Hex(col) .. text .. "|r" .. ((row.pct and row.status ~= "done") and ("  " .. ns.Pct(row.pct)) or ""))
    local e = row.e
    if editable then
        -- refreshes (a scan, a purchase, another addon's list) never wipe what the player is typing: the boxes are
        -- written only when the selection changes, and never while one has focus
        if edit.filledFor ~= selected then
            edit.modeID = e.keep and "keep" or "buy"
            if not edit.max.focused then edit.max:SetText(e.max and KM.Money(e.max, true) or "") end
            if not edit.want.focused then
                local n = e.keep or e.qty
                edit.want:SetText(n and tostring(n) or "")
            end
            if not edit.note.focused then edit.note:SetText(e.note or "") end
            edit.filledFor = selected
        end
        edit.modeID = edit.modeID or "buy"
        edit.mode:Select(edit.modeID)
        local avg, label = row.avg7, "7d"
        if not avg then avg, label = row.avg30, "30d" end
        edit.suggest.value = avg and math.floor(avg / 100 + 0.5) * 100 or nil
        edit.suggest:SetLabel(avg and (label .. " avg " .. ns.Short(avg, true)) or "")
        edit.suggest:SetShown(avg ~= nil)
    else
        edit.filledFor = nil
        edit.virtual:SetText(UI.Hex(C.info) .. "From " .. (ns.ProviderInfo(active) or "another addon") .. ": max "
            .. (e.max and ns.Short(e.max, true) or "none") .. ", want " .. (row.qty and tostring(row.qty) or "-")
            .. ". Change it in " .. (ns.ProviderInfo(active) or "that addon") .. ".|r")
    end
    local listed = row.listed and KM.Commas(row.listed) or "-"
    edit.facts1:SetText("Lowest " .. KM.Money(row.lowest) .. seenText(row) .. "    Market " .. KM.Money(row.market)
        .. "    Listed " .. listed .. (row.underQty and (" (" .. KM.Commas(row.underQty) .. " under max)") or ""))
    local fill, full = ns.LadderCost(row.id, row.need)
    local parts = {}
    if row.avg7 then parts[#parts + 1] = "7d avg " .. KM.Money(row.avg7) .. " (" .. ns.Trend(row.trend7) .. ")" end
    if row.low30 then parts[#parts + 1] = "30d " .. ns.Short(row.low30) .. " - " .. ns.Short(row.high30) end
    local own = ownText(row.ownBy, row.own)
    if row.keep then
        parts[#parts + 1] = UI.Hex(C.info) .. "Keep " .. row.keep .. ": " .. KM.Commas(row.owned or 0) .. " here"
            .. ((row.coming or 0) > 0 and (", " .. row.coming .. " on the way") or "") .. ", buy " .. row.qty .. "|r"
    elseif own then parts[#parts + 1] = "Own " .. own end
    if row.basis and row.basis.avg then parts[#parts + 1] = "Your cost " .. ns.Short(row.basis.avg) end
    if fill then parts[#parts + 1] = "Fill " .. row.need .. " ~ " .. ns.Short(fill) .. (full and "" or " (not that many listed)")
    elseif row.cost then parts[#parts + 1] = "Fill " .. row.need .. " ~ " .. ns.Short(row.cost) .. " at the lowest" end
    if e.note and not editable then parts[#parts + 1] = "Note: " .. e.note end
    edit.facts2:SetText(table.concat(parts, "    "))
    drawGraph(row)
end

---------------------------------------------------------------------------
-- The side: lists, buttons, all lists
---------------------------------------------------------------------------

local function refreshSide()
    local names = ns.ListNames()
    sideOffset = math.max(0, math.min(sideOffset, #names - SIDE_ROWS))
    local active = ns.Active()
    local more = #names - sideOffset > SIDE_ROWS and (#names - sideOffset - (SIDE_ROWS - 1)) or 0
    page.divider:Hide()
    local prevVirtual = nil
    for i, b in ipairs(sideButtons) do
        local name = names[i + sideOffset]
        b.list, b.more = nil, nil
        if more > 0 and i == SIDE_ROWS then
            b.more = more
            b:SetLabel("+" .. more .. " more")
            b:SetActive(false)
            b.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
            b.count:SetText("")
            if b.deals then b.deals:SetCount(nil) end
            b:Show()
        elseif name then
            b.list = name
            local virtual = ns.IsVirtual(name)
            local s = ns.Summary(name)
            b:SetLabel(name == ns.FAV and ("|T" .. "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" .. ":13|t " .. name) or name)
            b.count:SetText(tostring(s.items))
            if b.deals then b.deals:SetCount(s.deals, "gold") end
            b:SetActive(name == active)
            if virtual and name ~= active then b.label:SetTextColor(C.info[1], C.info[2], C.info[3], 1) end
            if virtual and prevVirtual == false then
                page.divider:ClearAllPoints()
                page.divider:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 4, 1)
                page.divider:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", -4, 1)
                page.divider:Show()
            end
            prevVirtual = virtual
            b:Show()
        else
            b:Hide()
        end
    end
    local mine = ns.IsMine(active)
    page.rename:SetEnabled2(mine)
    page.delete:SetEnabled2(mine)
    -- all lists
    local all = ns.AllSummary()
    allBox.deals:SetText(all.deals > 0 and (all.deals .. " deal" .. (all.deals == 1 and "" or "s") .. " ~ " .. ns.Short(all.dealsCost)) or "No deals right now")
    local dc = all.deals > 0 and C.good or C.muted
    allBox.deals:SetTextColor(dc[1], dc[2], dc[3], 1)
    allBox.fill:SetText("Fill all at max ~ " .. ns.Short(all.fillMax, true))
    allBox.data = all
end

local function listTip(tt, b)
    if b.more then tt:AddLine("Scroll for " .. b.more .. " more lists.", 1, 1, 1) return end
    local name = b.list
    if not name then return end
    local s = ns.Summary(name)
    tt:AddLine(name, C.accent[1], C.accent[2], C.accent[3])
    tt:AddLine(s.items .. " items   " .. s.deals .. " deal" .. (s.deals == 1 and "" or "s")
        .. (s.deals > 0 and (" (~" .. ns.Short(s.dealsCost, true) .. ")") or "")
        .. "   fill all at your max ~ " .. ns.Short(s.fillMax, true), 1, 1, 1)
    local owner, note = ns.ProviderInfo(name)
    if owner then
        tt:AddLine("Live list from " .. owner .. ". It updates itself; edit it in " .. owner .. ". Prices and buying work as usual.", C.info[1], C.info[2], C.info[3], true)
        if note then tt:AddLine(note, 0.6, 0.6, 0.6, true) end
    end
end

---------------------------------------------------------------------------
-- Refresh and build
---------------------------------------------------------------------------

local function refresh()
    if not (ns.db and page) then return end
    refreshSide()
    local active = ns.Active()
    data = rowsData()
    local editable = ns.IsEditable(active)
    for _, w in ipairs(addWidgets) do w:SetShown(editable) end
    addInfo:SetShown(not editable)
    if not editable then addInfo:SetText(liveText(active)) end
    maxHint()
    tbl.emptyText = active == ns.FAV
        and "No favorites yet. Add items here, or click the star on an item in Price History (the same favorites)."
        or (editable and "This list is empty. Shift-click an item into the box above, or type its name or item ID."
        or "Nothing on this live list right now.")
    tbl:SetRows(data, fillRow)
    if not footer.msg then
        footer:SetText(hintText())
        footer:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
    end
    fillEdit()
end

local function col(key, label, w, justify, sort, desc, tip)
    return { key = key, label = label, w = w, justify = justify, sort = sort, desc = desc, tip = tip }
end

local function buildSide()
    local side = UI.Panel(page, C.panel)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDE_W)
    local head = UI.Heading(side, "Lists")
    head:SetPoint("TOPLEFT", 10, -10)
    for i = 1, SIDE_ROWS do
        local b = UI.Button(side, "", SIDE_W - 12, SIDE_H - 2, function(self)
            if self.more then sideOffset = sideOffset + SIDE_ROWS - 1; refreshSide() return end
            if self.list then selected = nil; ns.SetActive(self.list); KM.Refresh("shopping") end
        end, "ghost")
        b:SetPoint("TOPLEFT", 6, -28 - (i - 1) * SIDE_H)
        b:SetPadding(8, 46)
        b.label:SetJustifyH("LEFT")
        b.count = UI.Text(b, 10, C.muted, "RIGHT")
        b.count:SetPoint("RIGHT", -8, 0)
        if UI.CountBadge then
            b.deals = UI.CountBadge(b, 14)
            b.deals:SetPoint("RIGHT", -28, 0)
        end
        UI.Tip(b, listTip)
        sideButtons[i] = b
    end
    page.divider = side:CreateTexture(nil, "ARTWORK")
    page.divider:SetTexture(UI.WHITE)
    page.divider:SetHeight(1)
    UI.SetColor(page.divider, C.border)
    page.divider:Hide()
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta) sideOffset = math.max(0, sideOffset - delta); refreshSide() end)

    local y = -34 - SIDE_ROWS * SIDE_H
    local half, third = (SIDE_W - 18) / 2, (SIDE_W - 24) / 3
    page.new = UI.Button(side, "New list", half, 22, function()
        if StaticPopup_Show then StaticPopup_Show("KINGMAKER_SHOPPING_NAME", "Name the new shopping list:", nil, { mode = "new" }) end
    end)
    page.new:SetPoint("TOPLEFT", 6, y)
    page.import = UI.Button(side, "Import", half, 22, function() openCode("import") end)
    page.import:SetPoint("LEFT", page.new, "RIGHT", 6, 0)
    UI.Tip(page.import, "Paste a list code (KMS1:...) a friend or another character exported. Its items join the list named in the code.")
    local lockedTip = function(tt)
        tt:AddLine(ns.IsMine(ns.Active()) and ("For the list " .. ns.Active() .. ".") or "Favorites and live lists can't be renamed or deleted.", 1, 1, 1, true)
    end
    page.rename = UI.Button(side, "Rename", third, 22, function()
        local a = ns.Active()
        if ns.IsMine(a) and StaticPopup_Show then StaticPopup_Show("KINGMAKER_SHOPPING_NAME", "Rename \"" .. a .. "\" to:", nil, { mode = "rename", list = a }) end
    end)
    page.rename:SetPoint("TOPLEFT", 6, y - 26)
    UI.Tip(page.rename, lockedTip)
    page.export = UI.Button(side, "Export", third, 22, function() openCode("export") end)
    page.export:SetPoint("LEFT", page.rename, "RIGHT", 6, 0)
    UI.Tip(page.export, "The selected list as a code to copy and share; Import reads it back.")
    page.delete = UI.Button(side, "Delete", third, 22, function()
        local a = ns.Active()
        if ns.IsMine(a) and StaticPopup_Show then StaticPopup_Show("KINGMAKER_SHOPPING_DELETE", a, nil, { list = a }) end
    end)
    page.delete:SetPoint("LEFT", page.export, "RIGHT", 6, 0)
    UI.Tip(page.delete, lockedTip)

    -- all lists: what's under your max anywhere, and what everything costs at your max
    allBox = CreateFrame("Frame", nil, side)
    allBox:SetPoint("BOTTOMLEFT", 10, 10)
    allBox:SetPoint("BOTTOMRIGHT", -10, 10)
    allBox:SetHeight(44)
    allBox:EnableMouse(true)
    local ah = UI.Text(allBox, 9, C.accent)
    ah:SetPoint("TOPLEFT", 0, 0)
    ah:SetText("ALL LISTS")
    allBox.deals = UI.Text(allBox, 11, C.muted)
    allBox.deals:SetPoint("TOPLEFT", 0, -14)
    allBox.deals:SetPoint("RIGHT", allBox, "RIGHT", 0, 0)
    allBox.fill = UI.Text(allBox, 11, C.muted)
    allBox.fill:SetPoint("TOPLEFT", 0, -30)
    allBox.fill:SetPoint("RIGHT", allBox, "RIGHT", 0, 0)
    UI.Tip(allBox, function(tt)
        local all = allBox.data
        if not all then return end
        tt:AddLine("All lists (each item counted once)", C.accent[1], C.accent[2], C.accent[3])
        if #all.perList == 0 then tt:AddLine("Nothing under your max in the last scan.", 1, 1, 1) end
        for _, x in ipairs(all.perList) do tt:AddLine(x.name .. ": " .. x.deals .. " ~ " .. ns.Short(x.dealsCost, true), 1, 1, 1) end
        tt:AddLine("/shop deals prints them in chat.", 0.6, 0.6, 0.6)
    end)
    ns.allBox = allBox
end

local function buildDetail(right)
    bar = UI.Panel(right, C.panel)
    bar:SetPoint("BOTTOMLEFT", 0, 22)
    bar:SetPoint("BOTTOMRIGHT", 0, 22)
    bar:SetHeight(BAR_H)
    ns.detailBar = bar

    -- A: nothing selected: the list's totals
    for i = 1, 4 do
        tiles[i] = UI.Tile(bar, 137, 64)
        tiles[i]:SetPoint("TOPLEFT", 10 + (i - 1) * 142, -10)
    end
    local function line(tt, l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
    tiles[1]:SetTip(function(tt)
        local s = ns.Summary(ns.Active())
        tt:AddLine("Items on this list whose lowest price is at or under your max right now.", 1, 1, 1, true)
        line(tt, "Deals", s.deals)
        line(tt, "Above your max", s.over)
        if s.noMax > 0 then line(tt, "No max to judge by", s.noMax) end
        if s.noPrice > 0 then line(tt, "Not seen in a scan", s.noPrice) end
        if s.done > 0 then line(tt, "Done (bought all you wanted, or stocked)", s.done) end
    end)
    tiles[2]:SetTip(function(tt)
        local s = ns.Summary(ns.Active())
        tt:AddLine("What buying every deal costs at the lowest price: Want x lowest, an item with no Want counts as one. The saving is the same items at your max minus that.", 1, 1, 1, true)
        tt:AddLine("Commodities get dearer as the cheap ones sell, so the panel's price before you buy is the real one.", 0.7, 0.7, 0.7, true)
        if s.deals > 0 then
            line(tt, "At your max", KM.Money(s.dealsCost + s.dealsSave))
            line(tt, "At the lowest price", KM.Money(s.dealsCost))
            line(tt, "Saved", KM.Money(s.dealsSave))
        end
    end)
    tiles[3]:SetTip("Your budget: Want x your max for every item not done yet, whatever it costs today (an item with no Want counts as one). Items with neither a max nor a market price can't be counted; the line under says how many.")
    tiles[4]:SetTip("When your last full auction house scan finished; every price on the list comes from it unless you searched an item at the auction house since. Red after a day, orange after two hours.")
    edit.hint = UI.Text(bar, 11, C.muted)
    edit.hint:SetPoint("TOPLEFT", 12, -84)
    edit.hint:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    edit.vhint = UI.Text(bar, 11, C.info)
    edit.vhint:SetPoint("TOPLEFT", 12, -102)
    edit.vhint:SetPoint("RIGHT", bar, "RIGHT", -12, 0)

    -- B: an item selected: the editor, its facts and a price line
    edit.icon = bar:CreateTexture(nil, "ARTWORK")
    edit.icon:SetSize(20, 20)
    edit.icon:SetPoint("TOPLEFT", 10, -8)
    edit.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    edit.status = UI.Text(bar, 11, C.good, "RIGHT")
    edit.status:SetPoint("TOPRIGHT", bar, "TOPLEFT", 336, -12)
    edit.name = UI.Text(bar, 13, C.text)
    edit.name:SetPoint("LEFT", edit.icon, "RIGHT", 7, 0)
    edit.name:SetPoint("RIGHT", edit.status, "LEFT", -8, 0)

    local function enterSaves(box)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); saveEdit() end)
    end
    edit.maxL = UI.Text(bar, 11, C.muted); edit.maxL:SetPoint("TOPLEFT", 10, -39); edit.maxL:SetText("Max")
    edit.max = UI.EditBox(bar, 80, 22, "none")
    edit.max:SetPoint("TOPLEFT", 40, -34)
    enterSaves(edit.max)
    edit.suggest = UI.Button(bar, "", 104, 22, function(self)
        -- fills the box only: Save keeps it
        if self.value then edit.max:SetText(KM.Money(self.value, true)) end
    end, "ghost")
    edit.suggest:SetPoint("LEFT", edit.max, "RIGHT", 4, 0)
    UI.Tip(edit.suggest, "Puts Price History's average in the Max box. Save keeps it.")
    -- Buy N (counts down as you buy) or Keep N in stock (the need is N minus what you own): switching saves
    edit.mode = UI.Tabs(bar, { { id = "buy", label = "Buy", w = 38 }, { id = "keep", label = "Keep", w = 42 } }, function(id)
        edit.modeID = id
        if id == "keep" and not tonumber(edit.want:GetText() or "") then
            local e = selected and ns.Find(ns.Active(), selected)
            edit.want:SetText(tostring((e and e.qty and e.qty > 0) and e.qty or 1))
        end
        saveEdit()
    end, 22)
    edit.mode:SetPoint("LEFT", edit.suggest, "RIGHT", 6, 0)
    UI.Tip(edit.mode.buttons.buy, "Buy this many: Want goes down with each purchase, and the item is done at 0.")
    UI.Tip(edit.mode.buttons.keep, "Keep this many in stock: it needs the number minus what you own on this realm and faction (Inventory), doesn't count down as you buy, and wants more again as you use them.")
    edit.wantL = edit.mode   -- (the label it replaced)
    edit.want = UI.NumberBox(bar, 38)
    edit.want:SetPoint("LEFT", edit.mode, "RIGHT", 4, 0)
    enterSaves(edit.want)
    edit.noteL = UI.Text(bar, 11, C.muted); edit.noteL:SetPoint("TOPLEFT", 10, -67); edit.noteL:SetText("Note")
    edit.note = UI.EditBox(bar, 178, 22, "")
    edit.note:SetPoint("TOPLEFT", 40, -62)
    if edit.note.SetMaxLetters then edit.note:SetMaxLetters(60) end
    enterSaves(edit.note)
    edit.save = UI.Button(bar, "Save", 52, 22, function() saveEdit() end, "primary")
    edit.save:SetPoint("LEFT", edit.note, "RIGHT", 6, 0)
    edit.remove = UI.Button(bar, "Remove", 60, 22, function() removeSelected() end)
    edit.remove:SetPoint("LEFT", edit.save, "RIGHT", 6, 0)
    edit.virtual = UI.Para(bar, 11, C.info, 326)
    edit.virtual:SetPoint("TOPLEFT", 10, -36)
    edit.facts1 = UI.Text(bar, 10, C.muted)
    edit.facts1:SetPoint("TOPLEFT", 10, -96)
    edit.facts1:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    edit.facts2 = UI.Text(bar, 10, C.muted)
    edit.facts2:SetPoint("TOPLEFT", 10, -112)
    edit.facts2:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    edit.graphOff = UI.Para(bar, 10, C.dim, 200)
    edit.graphOff:SetPoint("TOPLEFT", 370, -30)
    edit.graphOff:SetText("Price History is off: no price line.")
    edit.history = UI.Button(bar, "Price history", 96, 18, function() if selected then openHistory(selected) end end, "ghost")
    edit.history:SetPoint("TOPRIGHT", -10, -74)
    ns.edit = edit
    ns.tiles = tiles
end

local function buildPage(container)
    page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    ns.page = page
    buildSide()

    -- right: add bar, table, detail pane, footer
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", SIDE_W + 12, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    addBox = UI.EditBox(right, 250, 24, "Shift-click an item, or type a name or ID", function() maxHint() end)
    addBox:SetPoint("TOPLEFT", 0, 0)
    addBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); addFromBoxes() end)
    addBox:SetScript("OnReceiveDrag", function(self)
        if GetCursorInfo then
            local kind, id, link = GetCursorInfo()
            if kind == "item" then self:SetText(link or tostring(id)); if ClearCursor then ClearCursor() end end
        end
    end)
    ns.addBox = addBox
    local wl = UI.Text(right, 11, C.muted)
    wl:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
    wl:SetText("Want")
    wantBox = UI.NumberBox(right, 46)
    wantBox:SetPoint("LEFT", wl, "RIGHT", 6, 0)
    local ml = UI.Text(right, 11, C.muted)
    ml:SetPoint("LEFT", wantBox, "RIGHT", 10, 0)
    ml:SetText("Max")
    maxBox = UI.EditBox(right, 84, 24, "market")
    maxBox:SetPoint("LEFT", ml, "RIGHT", 6, 0)
    maxBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); addFromBoxes() end)
    ns.wantBox, ns.maxBox = wantBox, maxBox
    local add = UI.Button(right, "Add", 56, 24, function() addFromBoxes() end, "primary")
    add:SetPoint("LEFT", maxBox, "RIGHT", 8, 0)
    ns.addButton = add
    addWidgets = { addBox, wl, wantBox, ml, maxBox, add }
    addInfo = UI.Text(right, 11, C.info)
    addInfo:SetPoint("LEFT", right, "TOPLEFT", 2, -12)
    addInfo:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    addInfo:Hide()
    ns.addInfo = addInfo

    tbl = UI.Table(right, {
        col("name", "Item", 138, nil, function(r) return r.name end, false),
        col("lowest", "Lowest", 62, "RIGHT", function(r) return r.lowest end, false,
            "Lowest buyout from your last scan, or from a search at the auction house this visit (the tooltip says which)."),
        col("max", "Max", 58, "RIGHT", function(r) return r.max end, false,
            "Your max price. Grey*: no max of your own, so the market price is used (Settings)."),
        col("pct", "Vs max", 50, "RIGHT", function(r) return r.pct end, false,
            "How far the lowest price is under (green) or over your max."),
        col("qty", "Want", 50, "RIGHT", function(r) return r.qty end, true, "How many more to buy. Goes down as you buy. \"keep 20\": keep 20 in stock, so it wants 20 minus what you own and never counts down (hover the row for how many that is now)."),
        col("own", "Own", 38, "RIGHT", function(r) return r.own end, true, "Owned on all characters (Inventory)."),
        col("cost", "Cost", 66, "RIGHT", function(r) return r.cost end, true,
            "Want x lowest price: about what buying them now costs (commodities get dearer as the cheap ones sell; the panel shows the real price before you buy)."),
        col("trend", "7d", 40, "RIGHT", function(r) return r.trend7 end, false, "Price change over the last 7 days (Price History). Down is green: good for a buyer."),
        col("status", "Status", 0, "RIGHT", function(r) return ns.SortKey(r) end, false, function(tt)
            tt:AddLine("Status", C.accent[1], C.accent[2], C.accent[3])
            tt:AddDoubleLine("DEAL", "lowest price at or under your max", C.good[1], C.good[2], C.good[3], 1, 1, 1)
            tt:AddDoubleLine("<= MKT", "at or under the market price (no max of your own)", C.info[1], C.info[2], C.info[3], 1, 1, 1)
            tt:AddDoubleLine("NO MAX", "no max of your own, and Settings don't use the market price", C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
            tt:AddDoubleLine("NO SCAN", "not seen in a scan yet", C.dim[1], C.dim[2], C.dim[3], 1, 1, 1)
            tt:AddDoubleLine("DONE", "you've bought all you wanted", C.info[1], C.info[2], C.info[3], 1, 1, 1)
            tt:AddDoubleLine("STOCKED", "a Keep item: you own as many as you keep", C.info[1], C.info[2], C.info[3], 1, 1, 1)
            tt:AddLine("Blank, row dimmed: over your max.", 0.7, 0.7, 0.7, true)
        end),
    }, ROW_H, { icon = true, fontSize = 11, onEnter = rowTooltip,
        onSort = function(key, desc) ns.db.ui.sort = { key = key, desc = desc and true or false } end,
        onClick = function(row, btn)
            if btn == "RightButton" then
                selected = row.id
                rowMenu(row)
            elseif selected == row.id then
                selected = nil        -- a second click goes back to the list's totals
            else
                selected = row.id
            end
            KM.Refresh("shopping")
        end })
    tbl:SetPoint("TOPLEFT", 0, -34)
    tbl:SetPoint("BOTTOMRIGHT", 0, BAR_H + 26)
    local sort = ns.db and ns.db.ui and ns.db.ui.sort
    tbl:SetSort(sort and sort.key or "status", sort and sort.desc or false)
    ns.table = tbl

    buildDetail(right)

    footer = UI.Text(right, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    ns.pageMsg = footer
end

function ns.SelectItem(id) selected = id; edit.filledFor = nil; KM.Refresh("shopping") end
function ns.Selected() return selected end

KM.RegisterPage({
    id = "shopping", group = "ah", label = "Shopping", icon = "Interface\\Icons\\INV_Misc_Note_01", order = 25,
    title = "Shopping",
    subtitle = "Lists of what you want to buy, with your max price. At the auction house the Shopping panel searches and buys them.",
    build = buildPage, refresh = refresh,
    -- items under your max on any list (each once): a gold disc, an opportunity rather than a to-do, so not on the crown
    badge = function()
        if not (ns.db and ns.AllSummary) then return nil end
        local s = ns.AllSummary()
        if s.deals == 0 then return nil end
        if not KM.BadgeTables then return s.deals end
        return { count = s.deals, color = "gold",
            tip = s.deals .. " item" .. (s.deals == 1 and "" or "s") .. " at or under your max, about " .. KM.Money(s.dealsCost) }
    end,
    crownBadge = false,
})
