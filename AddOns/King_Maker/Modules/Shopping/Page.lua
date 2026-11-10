local _, KM = ...
local ns = KM.Module("Shopping")
local UI = KM.UI
local C = UI.C

-- The Shopping page (Auction House > Shopping): your lists on the left, the chosen list on the right with prices,
-- your max, how many you want and how many you own. Add items by shift-clicking a link into the add box, or by
-- typing a name or item ID. Lists can be shared as a short text code (Export / Import).

local SIDE_W, SIDE_ROWS, SIDE_H = 168, 11, 26
local page, tbl, footer, msgFS
local sideButtons, sideOffset = {}, 0
local addBox, wantBox, maxBox
local edit = {}
local selected      -- itemID being edited
local codeWin

local DASH = "|cff808080-|r"

local function say(text, color)
    if not msgFS then return end
    msgFS:SetText(text or "")
    local c = color or C.muted
    msgFS:SetTextColor(c[1], c[2], c[3], 1)
end
ns.PageSay = say

---------------------------------------------------------------------------
-- Popups: name a list, delete a list (entries are added to StaticPopupDialogs, never replacing it)
---------------------------------------------------------------------------

local function popupText(self)
    local eb = self and (self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()))
    return eb and eb:GetText() or ""
end

local function acceptName(self, data)
    local text = popupText(self)
    if data and data.mode == "rename" then
        if ns.RenameList(data.list, text) then say("Renamed to " .. ns.CleanName(text) .. ".", C.good)
        else say("Can't rename: that name is empty or already used.", C.warn) end
    else
        local name = ns.CreateList(text)
        if name then ns.SetActive(name); say("Made the list " .. name .. ".", C.good)
        else say("Can't make that list: the name is empty or already used.", C.warn) end
    end
    KM.Refresh("shopping")
end

StaticPopupDialogs["KINGMAKER_SHOPPING_NAME"] = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 32,
    OnAccept = acceptName,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb and eb.SetText and data and data.mode == "rename" then eb:SetText(data.list) end
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
    OnAccept = function(_, data)
        if data and ns.DeleteList(data.list) then say("Deleted " .. data.list .. ".", C.muted) end
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
        codeWin.note:SetText("Copy this (Ctrl+C) and send it to a friend or another character; Import on the Shopping page reads it.")
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

local function fillEdit()
    local e = selected and ns.Find(ns.Active(), selected)
    if not e then selected = nil end
    local has = e ~= nil
    for _, w in ipairs({ edit.max, edit.want, edit.note, edit.save, edit.remove, edit.maxL, edit.wantL, edit.noteL }) do w:SetShown(has) end
    edit.name:SetText(has and ns.ColoredName(e.id) or (UI.Hex(C.dim) .. "Click an item to edit its max price, how many you want and a note.|r"))
    if has then
        edit.max:SetText(e.max and KM.Money(e.max, true) or "")
        edit.want:SetText(e.qty and tostring(e.qty) or "")
        edit.note:SetText(e.note or "")
    end
end

local function saveEdit()
    if not selected then return end
    local maxText = edit.max:GetText() or ""
    local max = ns.ParseMoney(maxText)
    if maxText ~= "" and not max then say("Max price: type it like 1g 50s, 75s or 2.5 (gold).", C.warn) return end
    local qty = tonumber(edit.want:GetText() or "")
    local note = edit.note:GetText() or ""
    ns.Update(ns.Active(), selected, { max = max or false, qty = qty or false, note = note ~= "" and note or false })
    say("Saved.", C.good)
    KM.Refresh("shopping")
end
ns.SaveEdit = saveEdit

local function removeSelected()
    if not selected then return end
    local id = selected
    if ns.RemoveFrom(ns.Active(), id) then say(ns.Name(id) .. " removed.", C.muted) end
    selected = nil
    KM.Refresh("shopping")
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function own(id)
    if InventoryKing and InventoryKing.GetCount then
        local n = KM.Safe(InventoryKing.GetCount, id)
        return n
    end
end

local function rowsData()
    local out = {}
    for _, e in ipairs(ns.Entries(ns.Active()) or {}) do
        local market, lowest, listed = ns.Prices(e.id)
        local max, fromMarket = ns.EffectiveMax(e)
        out[#out + 1] = { e = e, id = e.id, name = ns.Name(e.id), market = market, lowest = lowest, listed = listed,
            max = max, fromMarket = fromMarket, qty = e.qty, own = own(e.id), status = ns.Status(e) }
    end
    return out
end

local RANK = { under = 1, nomax = 2, over = 3, noprice = 4, done = 5 }

local function fillRow(r, row, cells)
    r.item = row.id
    if r.icon then r.icon:SetTexture(ns.Icon(row.id)) end
    r.sel:SetShown(selected == row.id)
    cells.name:SetText(ns.ColoredName(row.id))
    cells.market:SetText(ns.Money(row.market))
    cells.lowest:SetText(row.lowest and ((row.status == "under" and UI.Hex(C.good) or "") .. KM.Money(row.lowest, row.status == "under") .. (row.status == "under" and "|r" or "")) or DASH)
    cells.listed:SetText(row.listed and KM.Commas(row.listed) or DASH)
    cells.max:SetText(row.max and ((row.fromMarket and UI.Hex(C.muted) or "") .. KM.Money(row.max, row.fromMarket) .. (row.fromMarket and "|r" or "")) or DASH)
    cells.want:SetText(row.qty and tostring(row.qty) or DASH)
    cells.own:SetText(row.own and KM.Commas(row.own) or DASH)
    cells.status:SetText(ns.StatusText(row.e))
end

local function refreshSide()
    local names = ns.ListNames()
    sideOffset = math.max(0, math.min(sideOffset, #names - SIDE_ROWS))
    local active = ns.Active()
    for i, b in ipairs(sideButtons) do
        local name = names[i + sideOffset]
        b.list = name
        if name then
            b:SetLabel(name == ns.FAV and ("|T" .. "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" .. ":13|t " .. name) or name)
            b.count:SetText(tostring(#(ns.Entries(name) or {})))
            b:SetActive(name == active)
            b:Show()
        else
            b:Hide()
        end
    end
    local mine = active ~= ns.FAV
    page.rename:SetEnabled2(mine)
    page.delete:SetEnabled2(mine)
    page.oracle:SetShown(ns.OracleData() ~= nil)
end

local function refresh()
    if not (ns.db and page) then return end
    refreshSide()
    local data = rowsData()
    local under = 0
    for _, r in ipairs(data) do if r.status == "under" then under = under + 1 end end
    tbl.emptyText = ns.Active() == ns.FAV
        and "No favorites yet. Add items here, or click the star on an item in Price History (the same favorites)."
        or "This list is empty. Shift-click an item into the box above, or type its name or item ID."
    tbl:SetRows(data, fillRow)
    footer:SetText(#data .. " items" .. (under > 0 and ("   " .. UI.Hex(C.good) .. under .. " under your max|r") or "")
        .. "   Last scan: " .. ((ScannerKing and ScannerKing.LastScan and ScannerKing.LastScan()) and KM.Ago(ScannerKing.LastScan()) or "never")
        .. ".  The panel at the auction house searches live.")
    fillEdit()
end

local function buildPage(container)
    page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    ns.page = page

    -- left: the lists
    local side = UI.Panel(page, C.panel)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDE_W)
    local head = UI.Heading(side, "Lists")
    head:SetPoint("TOPLEFT", 10, -10)
    for i = 1, SIDE_ROWS do
        local b = UI.Button(side, "", SIDE_W - 12, SIDE_H - 2, function(self)
            if self.list then selected = nil; ns.SetActive(self.list); KM.Refresh("shopping") end
        end, "ghost")
        b:SetPoint("TOPLEFT", 6, -28 - (i - 1) * SIDE_H)
        b:SetPadding(8, 30)
        b.label:SetJustifyH("LEFT")
        b.count = UI.Text(b, 10, C.muted, "RIGHT")
        b.count:SetPoint("RIGHT", -8, 0)
        sideButtons[i] = b
    end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta) sideOffset = math.max(0, sideOffset - delta); refreshSide() end)

    local y = -34 - SIDE_ROWS * SIDE_H
    local half = (SIDE_W - 18) / 2
    page.new = UI.Button(side, "New list", half, 22, function()
        if StaticPopup_Show then StaticPopup_Show("KINGMAKER_SHOPPING_NAME", "Name the new shopping list:", nil, { mode = "new" }) end
    end)
    page.new:SetPoint("TOPLEFT", 6, y)
    page.rename = UI.Button(side, "Rename", half, 22, function()
        local a = ns.Active()
        if a ~= ns.FAV and StaticPopup_Show then StaticPopup_Show("KINGMAKER_SHOPPING_NAME", "Rename \"" .. a .. "\" to:", nil, { mode = "rename", list = a }) end
    end)
    page.rename:SetPoint("LEFT", page.new, "RIGHT", 6, 0)
    page.import = UI.Button(side, "Import", half, 22, function() openCode("import") end)
    page.import:SetPoint("TOPLEFT", 6, y - 26)
    page.export = UI.Button(side, "Export", half, 22, function() openCode("export") end)
    page.export:SetPoint("LEFT", page.import, "RIGHT", 6, 0)
    page.delete = UI.Button(side, "Delete list", SIDE_W - 12, 22, function()
        local a = ns.Active()
        if a ~= ns.FAV and StaticPopup_Show then StaticPopup_Show("KINGMAKER_SHOPPING_DELETE", a, nil, { list = a }) end
    end)
    page.delete:SetPoint("TOPLEFT", 6, y - 52)
    page.oracle = UI.Button(side, "Import Oracle buy list", SIDE_W - 12, 22, function()
        local name, n = ns.ImportOracle()
        if name then ns.SetActive(name); say(n .. " buy calls from Oracle in the list " .. name .. ".", C.good)
        else say(n, C.warn) end
        KM.Refresh("shopping")
    end, "primary")
    page.oracle:SetPoint("TOPLEFT", 6, y - 82)
    page.oracle:Hide()

    -- right: add bar, table, edit bar
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", SIDE_W + 12, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    addBox = UI.EditBox(right, 250, 24, "Shift-click an item, or type a name or ID")
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
    maxBox = UI.EditBox(right, 84, 24, "1g 50s")
    maxBox:SetPoint("LEFT", ml, "RIGHT", 6, 0)
    maxBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); addFromBoxes() end)
    ns.wantBox, ns.maxBox = wantBox, maxBox
    local add = UI.Button(right, "Add", 56, 24, function() addFromBoxes() end, "primary")
    add:SetPoint("LEFT", maxBox, "RIGHT", 8, 0)
    ns.addButton = add

    local function col(key, label, w, justify, sort, desc)
        return { key = key, label = label, w = w, justify = justify, sort = sort, desc = desc }
    end
    tbl = UI.Table(right, {
        col("name", "Item", 150, nil, function(r) return r.name end, false),
        col("market", "Market", 70, "RIGHT", function(r) return r.market end),
        col("lowest", "Lowest", 70, "RIGHT", function(r) return r.lowest end),
        col("listed", "Listed", 46, "RIGHT", function(r) return r.listed end),
        col("max", "Max", 70, "RIGHT", function(r) return r.max end),
        col("want", "Want", 38, "RIGHT", function(r) return r.qty end),
        col("own", "Own", 38, "RIGHT", function(r) return r.own end),
        col("status", "Status", 0, nil, function(r) return -(RANK[r.status] or 9) end),
    }, 24, { icon = true, onClick = function(row, btn)
        selected = row.id
        if btn == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(page, function(_, root)
                root:CreateTitle(row.name)
                root:CreateButton("Remove from " .. ns.Active(), function() removeSelected() end)
                for _, name in ipairs(ns.ListNames()) do
                    if name ~= ns.Active() then
                        root:CreateButton("Also add to " .. name, function()
                            local e = row.e
                            ns.AddTo(name, e.id, e.qty, e.max, e.note)
                            say(row.name .. " added to " .. name .. ".", C.good)
                        end)
                    end
                end
            end)
        end
        KM.Refresh("shopping")
    end })
    tbl:SetPoint("TOPLEFT", 0, -34)
    tbl:SetPoint("BOTTOMRIGHT", 0, 106)
    tbl:SetSort("status", true)
    ns.table = tbl

    -- edit bar
    local bar = UI.Panel(right, C.panel)
    bar:SetPoint("BOTTOMLEFT", 0, 22)
    bar:SetPoint("BOTTOMRIGHT", 0, 22)
    bar:SetHeight(58)
    edit.name = UI.Text(bar, 12, C.text)
    edit.name:SetPoint("TOPLEFT", 10, -8)
    edit.name:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    edit.maxL = UI.Text(bar, 11, C.muted); edit.maxL:SetPoint("BOTTOMLEFT", 10, 12); edit.maxL:SetText("Max")
    edit.max = UI.EditBox(bar, 84, 22, "none")
    edit.max:SetPoint("LEFT", edit.maxL, "RIGHT", 6, 0)
    edit.wantL = UI.Text(bar, 11, C.muted); edit.wantL:SetPoint("LEFT", edit.max, "RIGHT", 10, 0); edit.wantL:SetText("Want")
    edit.want = UI.NumberBox(bar, 46)
    edit.want:SetPoint("LEFT", edit.wantL, "RIGHT", 6, 0)
    edit.noteL = UI.Text(bar, 11, C.muted); edit.noteL:SetPoint("LEFT", edit.want, "RIGHT", 10, 0); edit.noteL:SetText("Note")
    edit.note = UI.EditBox(bar, 150, 22, "")
    edit.note:SetPoint("LEFT", edit.noteL, "RIGHT", 6, 0)
    if edit.note.SetMaxLetters then edit.note:SetMaxLetters(60) end
    edit.save = UI.Button(bar, "Save", 56, 22, function() saveEdit() end, "primary")
    edit.save:SetPoint("LEFT", edit.note, "RIGHT", 8, 0)
    edit.remove = UI.Button(bar, "Remove", 64, 22, function() removeSelected() end)
    edit.remove:SetPoint("LEFT", edit.save, "RIGHT", 6, 0)
    ns.edit = edit

    footer = UI.Text(right, 10, C.muted)
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    msgFS = UI.Text(right, 11, C.muted)
    msgFS:SetPoint("BOTTOMLEFT", 0, 86)
    msgFS:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    ns.pageMsg = msgFS
end

function ns.SelectItem(id) selected = id; KM.Refresh("shopping") end
function ns.Selected() return selected end

KM.RegisterPage({
    id = "shopping", group = "ah", label = "Shopping", icon = "Interface\\Icons\\INV_Misc_Bag_10", order = 25,
    title = "Shopping",
    subtitle = "Lists of what you want to buy, with your max price. At the auction house the Shopping panel searches and buys them.",
    build = buildPage, refresh = refresh,
})
