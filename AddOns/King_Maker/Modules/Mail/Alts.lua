local _, KM = ...
local ns = KM.Module("Mail")
local UI = KM.UI
local C = UI.C

-- My characters, beside the mailbox: every other character of yours that can get mail from this one (same realm,
-- same faction), highest level first. Click one and its name goes in the To: box of Send Mail (from the Inbox it
-- switches to Send Mail first), and the cursor moves on to the subject.
--
-- The list comes from what the Inventory and Rested modules already save about each character you log in to
-- (class, level, faction, gold); a character shows up here once you've logged in to it with King Maker.
-- Our own frame, anchored to the right of MailFrame (never parented to it or changing it). The only Blizzard
-- things touched are the To: and Subject boxes (SetText, SetFocus) and the Send Mail tab's click.

local W, ROW_H, MAX_ROWS = 210, 22, 16

local panel, stillOpen
local rows, offset, list = {}, 0, {}

-- "Jay-Forever" -> "Jay", realm
local function split(key)
    local name, realm = key:match("^(.-)%-(.+)$")
    return name or key, realm or ""
end

-- An alt saved before 2.3.0 (and not logged in to since) has only its first name. Forever names have a surname,
-- and mail needs the full name. Where it comes from, until you log in to that alt (which fixes it for good):
--   - mail: you send mail to "First Last", or "First Last" sends you mail, and First is one of those alts
--     (db.altNames, learned below);
--   - your guild roster: one match by first name and class.
local function guildFull(first, class)
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return nil end
    local found
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if type(name) == "string" then
            name = name:gsub("%-.*$", "")
            local f1 = name:match("^(%S+) ")
            if f1 and f1:lower() == first:lower() and (not class or not classFile or classFile == class) then
                if found and found ~= name then return nil end
                found = name
            end
        end
    end
    return found
end

-- Every other character that can be mailed from this one: { key, name, class, level, gold }.
function ns.Alts()
    local mine, realm = ns.Char(), GetRealmName and GetRealmName() or ""
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local seen, out = {}, {}
    local function add(key, c)
        if type(c) ~= "table" or key == mine then return end
        local name, r = split(key)
        r = c.realm or r
        if r ~= "" and realm ~= "" and r ~= realm then return end
        local a = seen[key]
        if not a then
            a = { key = key, name = c.name or name }
            seen[key] = a
            out[#out + 1] = a
        end
        a.class = a.class or c.class
        a.faction = a.faction or c.faction
        if (c.level or 0) > (a.level or 0) then a.level = c.level end
        if c.gold then a.gold = c.gold end
    end
    local inv, rested = KM.mods.Inventory, KM.mods.Rested
    for key, c in pairs(inv and inv.db and inv.db.chars or {}) do add(key, c) end
    for key, c in pairs(rested and rested.db and rested.db.chars or {}) do add(key, c) end
    for i = #out, 1, -1 do
        if faction and out[i].faction and out[i].faction ~= faction then table.remove(out, i) end
    end
    local learned = ns.db and ns.db.altNames or {}
    for _, a in ipairs(out) do
        if not a.name:find(" ") then a.name = learned[a.key] or guildFull(a.name, a.class) or a.name end
    end
    table.sort(out, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return a.name < b.name
    end)
    return out
end

local function classText(a)
    local color = a.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[a.class]
    if color and color.colorStr then return "|c" .. color.colorStr .. a.name .. "|r" end
    return a.name
end

---------------------------------------------------------------------------
-- Putting the name in
---------------------------------------------------------------------------

local function sendShown() return SendMailFrame and SendMailFrame:IsShown() end

-- Puts name in the To: box of Send Mail (switching to that tab first) and moves on to the subject.
function ns.MailTo(name)
    if not sendShown() and MailFrameTab2 and MailFrameTab2.Click then pcall(MailFrameTab2.Click, MailFrameTab2) end
    local box = SendMailNameEditBox
    if not box then return false end
    box:SetText(name)
    if box.SetCursorPosition then box:SetCursorPosition(#name) end
    local subject = SendMailSubjectEditBox
    if subject and subject.SetFocus then subject:SetFocus() end
    if ns.RefreshAlts then ns.RefreshAlts() end
    return true
end

local function current()
    local box = SendMailNameEditBox
    local t = box and box.GetText and box:GetText() or ""
    return (t:match("^%s*(.-)%s*$") or ""):lower()
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function makeRow(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 6, -32 - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
    r.zebra = UI.Fill(r, C.zebra)
    r.zebra:SetShown(i % 2 == 0)
    r.sel = UI.Fill(r, C.sel, "ARTWORK")
    r.sel:Hide()
    r.hover = UI.Fill(r, C.hover, "ARTWORK")
    r.hover:Hide()
    r.level = UI.Text(r, 11, C.muted, "RIGHT")
    r.level:SetPoint("LEFT", 2, 0)
    r.level:SetWidth(20)
    r.name = UI.Text(r, 12, C.text)
    r.name:SetPoint("LEFT", r.level, "RIGHT", 6, 0)
    r.name:SetWidth(90)
    r.gold = UI.Text(r, 10, C.muted, "RIGHT")
    r.gold:SetPoint("RIGHT", -4, 0)
    r.gold:SetWidth(76)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnClick", function(self)
        if self.alt then UI.Click(); ns.MailTo(self.alt.name) end
    end)
    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not self.alt then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(classText(self.alt))
        GameTooltip:AddLine("Click to send mail to " .. self.alt.name .. ".", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    return r
end

function ns.RefreshAlts()
    if not (panel and panel:IsShown()) then return end
    local n = math.min(#list, MAX_ROWS)
    offset = math.max(0, math.min(offset, #list - n))
    local to = current()
    for i = 1, MAX_ROWS do
        local r = rows[i]
        local a = list[i + offset]
        if a and i <= n then
            r.alt = a
            r.level:SetText(a.level and tostring(a.level) or "")
            r.name:SetText(classText(a))
            r.gold:SetText(a.gold and KM.Money(a.gold - a.gold % 100) or "")
            r.sel:SetShown(to ~= "" and a.name:lower() == to)
            r:Show()
        else
            r.alt = nil
            r:Hide()
        end
    end
    panel.empty:SetShown(#list == 0)
    panel:SetHeight(40 + math.max(n, #list == 0 and 3 or 1) * ROW_H)
    panel.more:SetText(#list > n and ((offset + 1) .. "-" .. (offset + n) .. " of " .. #list .. ", scroll for more") or "")
end

local function build()
    panel = CreateFrame("Frame", "MailKingAltsPanel", UIParent)
    panel:SetWidth(W)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    UI.Fill(panel, C.bg)
    UI.Border(panel, { 1, 1, 1, 0.10 })
    UI.GoldEdge(panel)
    panel.title = UI.Text(panel, 13, C.accent)
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetText("My characters")
    panel.more = UI.Text(panel, 10, C.dim)
    panel.more:SetPoint("BOTTOMLEFT", 10, 4)
    panel.empty = UI.Para(panel, 11, C.muted, W - 20)
    panel.empty:SetPoint("TOPLEFT", 10, -36)
    panel.empty:SetText("Log in to your other characters once and they show up here.")
    for i = 1, MAX_ROWS do rows[i] = makeRow(i) end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta; ns.RefreshAlts() end)
    panel:SetScript("OnUpdate", function(self, dt) stillOpen(self, dt) end)
    panel:Hide()
    -- the selected row follows whatever is in the To: box
    if SendMailNameEditBox and SendMailNameEditBox.HookScript then
        SendMailNameEditBox:HookScript("OnTextChanged", function() ns.RefreshAlts() end)
    end
end

function ns.ShowAlts(show)
    if show and not ns.db.ui.alts then show = false end
    if not show then
        if panel then panel:Hide() end
        return
    end
    if not panel then build() end
    panel:ClearAllPoints()
    if MailFrame then
        panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("LEFT", UIParent, "LEFT", 420, 120)
    end
    list, offset = ns.Alts(), 0
    panel:Show()
    ns.RefreshAlts()
end

---------------------------------------------------------------------------
-- Learning surnames from mail
---------------------------------------------------------------------------

-- "Cowlossus Bones" (from the To: box or an inbox sender): if exactly one first-name-only alt is called Cowlossus,
-- that's its full name.
function ns.LearnAltName(full)
    if not (ns.db and type(full) == "string") then return false end
    full = full:gsub("%-.*$", ""):match("^%s*(.-)%s*$")
    local first = full:match("^(%S+) %S")
    if not first then return false end
    first = first:lower()
    local hit
    for _, a in ipairs(ns.Alts()) do
        local f = split(a.key)
        if not f:find(" ") and f:lower() == first then
            if hit then return false end -- two alts with that first name: can't tell which
            hit = a
        end
    end
    if not hit or ns.db.altNames[hit.key] == full then return false end
    ns.db.altNames[hit.key] = full
    if panel and panel:IsShown() then list = ns.Alts(); ns.RefreshAlts() end
    return true
end

local pendingTo
local function hookSend()
    if not (SendMailMailButton and SendMailMailButton.HookScript) or SendMailMailButton.kmAlts then return end
    SendMailMailButton.kmAlts = true
    SendMailMailButton:HookScript("OnClick", function()
        pendingTo = SendMailNameEditBox and SendMailNameEditBox.GetText and SendMailNameEditBox:GetText() or nil
    end)
end

local function learnInbox()
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    for i = 1, GetInboxNumItems() or 0 do
        local ok, _, _, sender = pcall(GetInboxHeaderInfo, i)
        if ok and sender then ns.LearnAltName(sender) end
    end
end

local function mailOpen() return MailFrame and MailFrame:IsShown() end

-- It opens and closes with the mail window itself: MailFrame's OnShow/OnHide (hooked, not replaced), the mailbox
-- events as a backup, and while it's up it checks each frame that the mail window still is (walking away, Escape
-- or the X can close the mailbox without MAIL_CLOSED reaching us).
local hooked = false
local function hookMailFrame()
    if hooked or not (MailFrame and MailFrame.HookScript) then return end
    hooked = true
    MailFrame:HookScript("OnShow", function() if ns.db then KM.Safe(ns.ShowAlts, true) end end)
    MailFrame:HookScript("OnHide", function() if ns.db then KM.Safe(ns.ShowAlts, false) end end)
end

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MAIL_SEND_SUCCESS",
    "MAIL_INBOX_UPDATE")
f:SetScript("OnEvent", function(_, event)
    hookMailFrame()
    hookSend()
    if not ns.db or event == "PLAYER_LOGIN" then return end
    if event == "MAIL_SEND_SUCCESS" then
        if pendingTo then KM.Safe(ns.LearnAltName, pendingTo) end
        pendingTo = nil
    elseif event == "MAIL_INBOX_UPDATE" then
        KM.Safe(learnInbox)
    elseif event == "MAIL_SHOW" then
        KM.Safe(ns.ShowAlts, true)
    elseif not mailOpen() then
        KM.Safe(ns.ShowAlts, false)
    end
end)

local watch = 0
stillOpen = function(self, dt)
    watch = watch + dt
    if watch < 0.2 then return end
    watch = 0
    if MailFrame and not MailFrame:IsShown() then self:Hide() end
end

-- The setting (Settings > Sales Ledger, or /mlk alts): shows or hides it right away if the mailbox is open.
function ns.SetAlts(on)
    ns.db.ui.alts = on and true or false
    ns.ShowAlts(on and mailOpen())
end
