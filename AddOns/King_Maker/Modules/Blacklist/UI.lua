local _, KM = ...
local ns = KM.Module("Blacklist")
local UI = KM.UI
local C = UI.C

-- The Guild > Blacklist page (/bl, /km blacklist):
--   tiles     on the list, added this week, last added, last in your group, sharing, guildmates heard from
--   toolbar   search, the count, Add
--   table     newest first (sortable): name, reason, added, by, the start of the note
--   detail    the selected entry: the full note, reason, who added it and when, the last edit, the last time they
--             were in your group; Edit and Remove (asks first)
-- Also here: the add / edit dialog (our own window), the remove confirmation, the sidebar badge (listed players in
-- your group right now), Settings > Blacklist.

local TILE_H = 60
local DETAIL_H = 150
local WEEK = 7 * 86400

local page, tbl, tiles, search, countFS, addBtn
local detail = {}
local rows = {}
local query = ""

local function hex(c, t) return UI.Hex(c) .. t .. "|r" end
local function grey(t) return hex(C.muted, t) end
local function red(t) return ns.RED .. t .. "|r" end
local function day(t) return t and (date and date("%d %b %Y", t) or tostring(t)) or "-" end
local function ago(t)
    if not t then return "never" end
    local a = KM.Ago(t)
    return a == "now" and "just now" or (a .. " ago")
end

---------------------------------------------------------------------------
-- The dialog: add or edit
---------------------------------------------------------------------------

local dlg

local function dialogError(text)
    dlg.err:SetText(text and hex(C.bad, text) or "")
end

local function noteCount()
    local n = #(dlg.note:GetText() or "")
    dlg.count:SetText(n .. " / " .. ns.NOTE_MAX)
    dlg.count:SetTextColor((n > ns.NOTE_MAX and C.bad or C.dim)[1], (n > ns.NOTE_MAX and C.bad or C.dim)[2], (n > ns.NOTE_MAX and C.bad or C.dim)[3])
end

local function buildDialog()
    dlg = UI.Window("KingMakerBlacklistDialog", "Add to Blacklist", 420, 286)
    local b = dlg.body
    local l1 = UI.Heading(b, "Name")
    l1:SetPoint("TOPLEFT", 0, -2)
    dlg.name = UI.EditBox(b, 392, 24, "First Last")
    dlg.name:SetPoint("TOPLEFT", 0, -16)
    if dlg.name.SetMaxLetters then dlg.name:SetMaxLetters(ns.NAME_MAX) end
    dlg.nameFixed = UI.Text(b, 14, C.text)
    dlg.nameFixed:SetPoint("TOPLEFT", 2, -20)
    local l2 = UI.Heading(b, "Reason")
    l2:SetPoint("TOPLEFT", 0, -50)
    local items = {}
    for _, r in ipairs(ns.REASONS) do items[#items + 1] = { id = r.id, label = r.label, w = 96 } end
    dlg.reason = UI.Tabs(b, items, function(id) dlg.reasonID = id end)
    dlg.reason:SetPoint("TOPLEFT", 0, -64)
    for _, r in ipairs(ns.REASONS) do UI.Tip(dlg.reason.buttons[r.id], r.tip) end
    local l3 = UI.Heading(b, "Note")
    l3:SetPoint("TOPLEFT", 0, -98)
    dlg.note = UI.EditBox(b, 392, 24, "What happened (your guild reads this)", function() noteCount() end)
    dlg.note:SetPoint("TOPLEFT", 0, -112)
    if dlg.note.SetMaxLetters then dlg.note:SetMaxLetters(ns.NOTE_MAX) end
    dlg.count = UI.Text(b, 10, C.dim, "RIGHT")
    dlg.count:SetPoint("TOPRIGHT", dlg.note, "BOTTOMRIGHT", 0, -4)
    dlg.hint = UI.Para(b, 10, C.muted, 300)
    dlg.hint:SetPoint("TOPLEFT", dlg.note, "BOTTOMLEFT", 0, -4)
    dlg.err = UI.Para(b, 11, C.bad, 392)
    dlg.err:SetPoint("TOPLEFT", 0, -170)
    dlg.save = UI.Button(b, "Save", 110, 26, function() ns.DialogSave() end, "primary")
    dlg.save:SetPoint("BOTTOMRIGHT", 0, 4)
    dlg.cancel = UI.Button(b, "Cancel", 90, 26, function() dlg:Hide() end)
    dlg.cancel:SetPoint("RIGHT", dlg.save, "LEFT", -8, 0)
    dlg.note:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ns.DialogSave() end)
    dlg.name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); dlg.note:SetFocus() end)
end

-- opts: { name, guid, unit, free = true (the name can be typed: opened from the page) }
function ns.OpenDialog(opts)
    if not ns.db then return end
    opts = opts or {}
    if not dlg then buildDialog() end
    local name = ns.Name(opts.name) or opts.name
    local e = name and ns.Get(name)
    dlg.opts = opts
    dlg.free = opts.free or not name
    dlg:SetTitle(e and ("Blacklist: " .. e.n) or "Add to Blacklist")
    dlg.name:SetText(name or "")
    dlg.name:SetShown(dlg.free)
    dlg.nameFixed:SetText(dlg.free and "" or red(name or ""))
    dlg.nameFixed:SetShown(not dlg.free)
    dlg.reasonID = e and e.r or "scam"
    dlg.reason:Select(dlg.reasonID)
    dlg.note:SetText(e and e.note or "")
    noteCount()
    dlg.hint:SetText(ns.IsPersonal() and "No guild: this list is yours alone." or (ns.Sharing() and "Shared with your guild: everyone running King Maker sees it." or "Sharing is off: only you see this."))
    dialogError(nil)
    dlg:Show()
    if dlg.Raise then dlg:Raise() end
    if dlg.free and (dlg.name:GetText() or "") == "" then dlg.name:SetFocus() else dlg.note:SetFocus() end
end

function ns.DialogSave()
    if not dlg then return false end
    local opts = dlg.opts or {}
    local name = dlg.free and dlg.name:GetText() or opts.name
    local ok, text = ns.Save(name, dlg.reasonID, dlg.note:GetText(), { guid = opts.guid, unit = opts.unit })
    if not ok then dialogError(text) return false end
    dlg:Hide()
    KM.Print(ns, text)
    local key = ns.Key(name)
    if key then ns.db.ui.selected = key end
    return true
end
function ns.Dialog() return dlg end

-- Remove asks first (a dialog entry of our own; Blizzard's table is only written into).
StaticPopupDialogs["KINGMAKER_BLACKLIST_REMOVE"] = {
    text = "Remove %s from the blacklist?\n\nYour guild's lists lose them too.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data)
        local _, text = ns.Remove(data)
        KM.Print(ns, text)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.ConfirmRemove(name)
    local e = ns.Get(name)
    if not e then return end
    if StaticPopup_Show then StaticPopup_Show("KINGMAKER_BLACKLIST_REMOVE", e.n, nil, e.n) end
end

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------

local function guildmatesHeard()
    local n, newest = 0, nil
    local cutoff = KM.Now() - 30 * 86400
    for _, t in pairs(ns.Heard()) do
        if t >= cutoff then n = n + 1 end
        if not newest or t > newest then newest = t end
    end
    return n, newest
end

function ns.Summary()
    local list = ns.Sorted()
    local s = { count = #list, week = 0, last = list[1] and list[1].e or nil }
    local cutoff = KM.Now() - WEEK
    local l = ns.List()
    for _, it in ipairs(list) do
        if (it.e.t or 0) >= cutoff then s.week = s.week + 1 end
        local seen = l and l.seen[it.key]
        if seen and (not s.seenT or seen > s.seenT) then s.seenT, s.seenE = seen, it.e end
    end
    s.heard, s.heardT = guildmatesHeard()
    return s
end

local function refreshTiles(s)
    tiles[1]:Set("On the list", tostring(s.count), ns.IsPersonal() and "your own list" or "your guild's list")
    tiles[2]:Set("Added this week", tostring(s.week), "last 7 days")
    tiles[3]:Set("Last added", s.last and s.last.n or "-", s.last and (ago(s.last.t) .. " by " .. (s.last.by or "?")) or "nobody yet", s.last and C.bad or nil)
    tiles[4]:Set("Last in your group", s.seenE and s.seenE.n or "-", s.seenT and ago(s.seenT) or "never", s.seenE and C.bad or nil)
    local share = ns.db.settings.share
    tiles[5]:Set("Sharing", ns.IsPersonal() and "No guild" or (share and "On" or "Off"),
        ns.IsPersonal() and "a personal list" or (share and "with your guild" or "only you see it"),
        (not ns.IsPersonal() and not share) and C.warn or (share and not ns.IsPersonal() and C.good or nil))
    tiles[6]:Set("Guildmates heard", tostring(s.heard), s.heardT and ("last " .. ago(s.heardT)) or "none yet")
end

---------------------------------------------------------------------------
-- The table and the detail
---------------------------------------------------------------------------

local function matches(it, q)
    if q == "" then return true end
    local e = it.e
    return it.key:find(q, 1, true) or (e.note or ""):lower():find(q, 1, true) or (e.by or ""):lower():find(q, 1, true)
        or ns.ReasonLabel(e.r):lower():find(q, 1, true)
end

local COLS = {
    { key = "name", label = "Name", w = 150, sort = function(it) return it.key end, desc = false,
      tip = "Who's on the list. Click a line for the whole entry." },
    { key = "reason", label = "Reason", w = 90, sort = function(it) return ns.ReasonLabel(it.e.r) end, desc = false },
    { key = "added", label = "Added", w = 86, sort = function(it) return it.e.t or 0 end,
      tip = "When they were added (server time). Newest first until you sort by something else." },
    { key = "by", label = "By", w = 120, sort = function(it) return (it.e.by or ""):lower() end, desc = false,
      tip = "Who added them. Anyone in the guild running King Maker can add, edit or remove." },
    { key = "note", label = "Note", w = 0, tip = "The start of the note; the whole note is below when you click the line." },
}

local function fillRow(r, it, cells)
    local e = it.e
    cells.name:SetText(red(e.n))
    cells.reason:SetText(ns.ReasonLabel(e.r))
    cells.added:SetText(day(e.t))
    cells.by:SetText(e.by or grey("?"))
    cells.note:SetText(grey(e.note or ""))
    r.tip = function(tt)
        tt:AddLine(e.n, RED_FONT_COLOR and RED_FONT_COLOR.r or 1, 0.2, 0.2)
        tt:AddLine(ns.ReasonLabel(e.r) .. ": " .. (e.note or ""), 1, 1, 1, true)
        tt:AddLine("Added by " .. (e.by or "?") .. ", " .. day(e.t), 0.6, 0.6, 0.6)
        tt:AddLine("Click for the whole entry, Edit and Remove.", 0.6, 0.6, 0.6)
    end
end

local function selected()
    local key = ns.db.ui.selected
    local e = key and ns.Entries()[key]
    if e and not e.del then return { key = key, e = e } end
end

local function line(parent, y)
    local l = UI.Text(parent, 11, C.muted)
    l:SetPoint("TOPLEFT", 10, y)
    l:SetWidth(100)
    local v = UI.Text(parent, 11, C.text)
    v:SetPoint("TOPLEFT", 112, y)
    v:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return { l = l, v = v }
end

local function drawDetail()
    local it = selected()
    detail.it = it
    local L = detail.lines
    if not it then
        detail.title:SetText("")
        detail.empty:SetText(ns.Count() == 0 and "Nobody on the list. Right-click a player in chat, on a portrait or in your group and pick Add to Blacklist, or press Add." or "Click a line to see the whole entry.")
        detail.note:SetText("")
        for _, l in ipairs(L) do l.l:SetText(""); l.v:SetText("") end
        detail.edit:Hide(); detail.remove:Hide()
        return
    end
    local e = it.e
    detail.empty:SetText("")
    detail.title:SetText(red(e.n))
    local l = ns.List()
    local seen = l and l.seen[it.key]
    local data = {
        { "Reason", ns.ReasonLabel(e.r) },
        { "Added", (e.by or "?") .. grey(", " .. day(e.t) .. " (" .. ago(e.t) .. ")") },
        { "Last change", (e.e and e.e ~= e.t) and ((e.eb or e.by or "?") .. grey(", " .. day(e.e) .. " (" .. ago(e.e) .. ")")) or grey("never edited") },
        { "In your group", seen and (day(seen) .. grey(" (" .. ago(seen) .. ")")) or grey("not seen with you") },
    }
    for i, ln in ipairs(L) do
        local d = data[i]
        ln.l:SetText(d and d[1] or "")
        ln.v:SetText(d and d[2] or "")
    end
    detail.note:SetText(e.note or "")
    detail.edit:Show(); detail.remove:Show()
end

local function buildDetail(c)
    local box = UI.Panel(c, C.panel)
    box:SetPoint("BOTTOMLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    box:SetHeight(DETAIL_H)
    detail.box = box
    detail.title = UI.Text(box, 14, C.text)
    detail.title:SetPoint("TOPLEFT", 10, -10)
    detail.empty = UI.Para(box, 11, C.muted, 520)
    detail.empty:SetPoint("TOPLEFT", 10, -12)
    detail.lines = {}
    for i = 1, 4 do detail.lines[i] = line(box, -34 - (i - 1) * 16) end
    for _, ln in ipairs(detail.lines) do ln.v:SetPoint("RIGHT", box, "CENTER", -10, 0) end
    local nh = UI.Heading(box, "Note")
    nh:SetPoint("TOPLEFT", box, "TOP", 0, -12)
    detail.note = UI.Para(box, 12, C.text)
    detail.note:SetPoint("TOPLEFT", box, "TOP", 0, -28)
    detail.note:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    detail.edit = UI.Button(box, "Edit", 80, 24, function()
        local it = detail.it
        if it then ns.OpenDialog({ name = it.e.n }) end
    end, "primary")
    detail.edit:SetPoint("BOTTOMLEFT", 10, 10)
    UI.Tip(detail.edit, "Change the reason or the note. Your guild gets the change.")
    detail.remove = UI.Button(box, "Remove", 80, 24, function()
        local it = detail.it
        if it then ns.ConfirmRemove(it.e.n) end
    end)
    detail.remove:SetPoint("LEFT", detail.edit, "RIGHT", 8, 0)
    UI.Tip(detail.remove, "Take them off the list (asks first). Your guild's lists lose them too.")
end

local function refresh()
    if not page or not ns.db then return end
    local u = ns.db.ui
    refreshTiles(ns.Summary())
    local q = (query or ""):lower()
    rows = {}
    for _, it in ipairs(ns.Sorted()) do if matches(it, q) then rows[#rows + 1] = it end end
    tbl:SetSort(u.sort, u.desc)
    tbl.selected = nil
    local sel = selected()
    if sel then for _, it in ipairs(rows) do if it.key == sel.key then tbl.selected = it end end end
    local total = ns.Count()
    countFS:SetText(q ~= "" and (#rows .. " of " .. total) or (total .. (total == 1 and " player" or " players")))
    tbl.emptyText = total == 0 and "Nobody on the list yet." or "Nothing matches the search."
    tbl:SetRows(rows, fillRow)
    drawDetail()
end

function ns.Refresh()
    if KM.RefreshBadges then KM.RefreshBadges() end
    KM.Refresh("blacklist")
end
function ns.Rows() return rows end
function ns.SetSearch(q)
    query = q or ""
    if search and search:GetText() ~= query then search:SetText(query) end
    refresh()
end
function ns.Select(name)
    local key = ns.Key(name)
    ns.db.ui.selected = key
    refresh()
end
function ns.DetailState() return detail end

local function buildPage(c)
    page = c
    tiles = {}
    local w = math.floor(((c:GetWidth() or 0) > 200 and c:GetWidth() or 763) / 6) - 8
    w = math.max(110, math.min(150, w))
    for i = 1, 6 do
        local t = UI.Tile(c, w, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (w + 8), 0)
        tiles[i] = t
    end
    tiles[1]:SetTip(function(tt)
        tt:AddLine("Everyone on the blacklist." .. (ns.IsPersonal() and " You aren't in a guild, so it's your own list." or " Your guild shares one list: anyone running King Maker can add, edit or remove."), 1, 1, 1, true)
    end)
    tiles[2]:SetTip("Added in the last 7 days, by you or a guildmate.")
    tiles[3]:SetTip("The newest entry, and who added it.")
    tiles[4]:SetTip("The last listed player who was in a group with you (King Maker notes it when the warning goes off).")
    tiles[5]:SetTip(function(tt)
        tt:AddLine("Share with my guild: your adds, edits and removals go to guildmates running King Maker, and theirs come to you. Only the list itself is sent.", 1, 1, 1, true)
        tt:AddLine("Settings > Blacklist, or /bl share on|off.", 0.6, 0.6, 0.6, true)
    end)
    tiles[6]:SetTip("Guildmates running King Maker whose blacklist messages reached you in the last 30 days.")

    local y = -(TILE_H + 12)
    search = UI.EditBox(c, 220, 24, "Search names, notes, who added", function(text) query = text or ""; refresh() end)
    search:SetPoint("TOPLEFT", 0, y)
    countFS = UI.Text(c, 11, C.muted)
    countFS:SetPoint("LEFT", search, "RIGHT", 12, 0)
    addBtn = UI.Button(c, "Add", 90, 24, function() ns.OpenDialog({ free = true }) end, "primary")
    addBtn:SetPoint("TOPRIGHT", 0, y)
    UI.Tip(addBtn, "Add a player by name. Quicker: right-click them in chat, on a portrait or in your group and pick Add to Blacklist, or Alt-click a group finder listing.")

    tbl = UI.Table(c, COLS, 22, {
        noSort = false,
        onSort = function(key, desc) ns.db.ui.sort, ns.db.ui.desc = key, desc end,
        onClick = function(it, which)
            ns.db.ui.selected = it.key
            if which == "RightButton" then ns.OpenDialog({ name = it.e.n }) end
            refresh()
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, y - 34)
    tbl:SetPoint("BOTTOMRIGHT", 0, DETAIL_H + 10)
    buildDetail(c)
end

---------------------------------------------------------------------------
-- The page, the badge, Settings
---------------------------------------------------------------------------

local function icon()
    local p = "Interface\\Icons\\Ability_Rogue_FeignDeath"
    if GetFileIDFromPath and not GetFileIDFromPath(p) then return "Interface\\Icons\\Spell_Shadow_Curse" end
    return p
end

-- Red count: listed players in your group right now.
function ns.Badge()
    if not ns.db then return nil end
    local list = ns.InGroupListed and ns.InGroupListed() or {}
    if #list == 0 then return nil end
    local names = {}
    for _, e in ipairs(list) do names[#names + 1] = e.n end
    return { count = #list, color = "red", tip = "Blacklisted and in your group: " .. table.concat(names, ", ") }
end

KM.RegisterGroup({ id = "guild", label = "Guild", order = 55 })
KM.RegisterPage({
    id = "blacklist", group = "guild", label = "Blacklist", icon = icon(), order = 10,
    title = "Guild Blacklist",
    subtitle = function()
        if not ns.db then return "" end
        return ns.IsPersonal() and "Players you won't group with. No guild: this list is yours alone."
            or "Players your guild won't group with, shared by everyone running King Maker."
    end,
    badge = function() return ns.Badge() end,
    build = buildPage, refresh = refresh,
})

local function get(k) return function() return ns.db.settings[k] end end
local function set(k) return function(v) ns.db.settings[k] = v and true or false; ns.ClearLookups(); ns.Refresh() end end

KM.RegisterSettings({ id = "blacklist", label = "Blacklist", order = 60, rows = {
    { type = "header", label = "Guild" },
    { type = "check", label = "Share with my guild", get = get("share"), set = function(v) ns.SetShare(v); ns.Refresh() end,
      tip = "Your adds, edits and removals go to guildmates running King Maker, and theirs come to you. Only the list is sent (names, reasons, notes, who and when), nothing else. Off: nothing is sent and guildmates' changes aren't read." },
    { type = "header", label = "Warnings" },
    { type = "check", label = "When one joins your group", get = get("alertJoin"), set = set("alertJoin"),
      tip = "A red message in the middle of the screen and a chat line with the note, once per player per session." },
    { type = "check", label = "When one invites you", get = get("alertInvite"), set = set("alertInvite"),
      tip = "The same warning before you accept the invite." },
    { type = "check", label = "Play a sound with the warning", get = get("sound"), set = set("sound") },
    { type = "header", label = "Marks" },
    { type = "check", label = "BLACKLISTED before their name in chat", get = get("chatTag"), set = set("chatTag"),
      tip = "A red BLACKLISTED in front of a listed player's name in say, yell, whispers, party, raid and channels." },
    { type = "check", label = "Line in their tooltip", get = get("tooltip"), set = set("tooltip"),
      tip = "Hover a listed player: a red BLACKLISTED line, the reason and the note." },
    { type = "check", label = "Marks in the group finder and Who list", get = get("lfg"), set = set("lfg"),
      tip = "A listed leader shows red with BLACKLISTED, a group with a listed member says so, and the listing's tooltip names them. Alt-click a listing to blacklist its leader." },
    { type = "header", label = "Removed entries" },
    { type = "check", label = "Forget removed entries after 60 days", get = get("purge"), set = set("purge"),
      tip = "A removal is kept so a guildmate who missed it can't put the player back. After 60 days it's forgotten." },
    { type = "text", label = "Nothing is ever kicked or declined (the game doesn't let addons do that): King Maker warns and marks only." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/bl   open the Blacklist page\n/bl add First Last: note   add a player (no note opens the dialog; no name uses your target)\n/bl remove First Last   take a player off\n/bl list   everyone, in chat\n/bl share on|off   share with your guild" },
} })
