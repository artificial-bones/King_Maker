local _, KM = ...
local ns = KM.Module("Blacklist")

-- Where the blacklist shows up outside the window. Every hook is feature-detected and pcall'd; nothing here ever
-- kicks, declines, invites, searches or opens a Blizzard panel (those are protected or taint): it warns and marks.
--
--   Right-click menus   Menu.ModifyMenu on the unit menus (portraits, party, raid, enemy players, focus, and chat
--                       names / the Who list / friends, which are MENU_UNIT_FRIEND): "Add to Blacklist", or
--                       "Blacklist: edit note" and "Remove from Blacklist" for someone already on it.
--   Joins your group    GROUP_ROSTER_UPDATE / GROUP_JOINED: a listed player new to the group gets a red message in
--                       the middle of the screen, a sound and a chat line with the note, once per session. The first
--                       read after login or /reload is silent (one "already in your group" line instead).
--   Invites you         PARTY_INVITE_REQUEST: the same warning before you accept.
--   Unit tooltips       TooltipDataProcessor (Unit): a red BLACKLISTED line, the reason and the note.
--   Chat                ChatFrameUtil.AddSenderNameFilter: a red BLACKLISTED before a listed sender's name (the
--                       fallback, a message filter, puts it before the message).
--   Group finder        Blizzard_GroupFinder_VanillaStyle (load on demand: hooked when it loads):
--                       LFGBrowseSearchEntry_Update tints a listed leader red and adds our own BLACKLISTED text;
--                       LFGBrowseSearchEntryTooltip_UpdateAndShow gets our own small box under the tooltip;
--                       Alt-click a listing to blacklist its leader (its right-click menu has no tag to extend);
--                       the Who list marks listed names the same way.

local RED = { 1, 0.13, 0.13 }
local ALERT_SOUND = 8959          -- SOUNDKIT.RAID_WARNING

local function S() return ns.db and ns.db.settings or {} end
local function plain(v) if ns.IsSecret(v) then return nil end return v end

-- Lookups by name are cached between list changes (chat runs this on every line).
local cache = {}
function ns.ClearLookups() wipe(cache) end
local function lookup(name)
    if type(name) ~= "string" or ns.IsSecret(name) or not ns.db then return nil end
    local hit = cache[name]
    if hit == nil then
        hit = ns.Get(name) or false
        cache[name] = hit
    end
    return hit or nil
end
ns.Lookup = lookup

local function reasonLine(e)
    return ns.ReasonLabel(e.r) .. ": " .. (e.note or "")
end

---------------------------------------------------------------------------
-- The warning: centre of the screen, a sound, a chat line
---------------------------------------------------------------------------

ns.alerts = 0
function ns.Alert(e, what)
    local text = ns.TAG .. " " .. e.n .. " " .. what
    ns.alerts = ns.alerts + 1
    ns.lastAlert = text
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = RED[1], g = RED[2], b = RED[3] })
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, RED[1], RED[2], RED[3], 1)
    end
    if S().sound and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or ALERT_SOUND, "Master")
    end
    KM.Print(ns, text .. ": " .. reasonLine(e) .. " |cff808080(added by " .. (e.by or "?") .. ")|r")
end

---------------------------------------------------------------------------
-- Your group
---------------------------------------------------------------------------

local members            -- key -> true: who was in the group at the last read; nil until the first read
local alerted = {}       -- key -> true: warned this session
local retried = false

local function unitList()
    local list = {}
    if IsInRaid and plain(IsInRaid()) then
        local n = tonumber(plain(GetNumGroupMembers and GetNumGroupMembers())) or 0
        for i = 1, math.min(n, 40) do list[#list + 1] = "raid" .. i end
    elseif IsInGroup and plain(IsInGroup()) then
        local n = tonumber(plain(GetNumGroupMembers and GetNumGroupMembers())) or 0
        for i = 1, math.min(n - 1, 4) do list[#list + 1] = "party" .. i end
    end
    return list
end

-- Reads the group; alerts for listed players who weren't in it at the last read.
function ns.ReadGroup()
    if not ns.db then return end
    local now, unknown, listed = {}, false, {}
    for _, unit in ipairs(unitList()) do
        if UnitExists and plain(UnitExists(unit)) and not (UnitIsUnit and plain(UnitIsUnit(unit, "player"))) then
            local name = ns.UnitFullName(unit)
            if not name then
                unknown = true
            elseif not KM.IsMe(name) then
                local key = name:lower()
                now[key] = true
                local e = lookup(name)
                if e then
                    listed[#listed + 1] = e
                    ns.Seen(key)
                    local g = UnitGUID and plain(UnitGUID(unit))
                    if type(g) == "string" and not e.g then e.g = g end
                    if members and not members[key] and not alerted[key] then
                        alerted[key] = true
                        if S().alertJoin then ns.Alert(e, "joined your group") end
                    end
                end
            end
        end
    end
    if not members then
        -- the first read (login, /reload): no alarms for a group you were already in
        for _, e in ipairs(listed) do alerted[e.n:lower()] = true end
        if #listed > 0 and S().alertJoin then
            local names = {}
            for _, e in ipairs(listed) do names[#names + 1] = ns.RED .. e.n .. "|r (" .. ns.ReasonLabel(e.r) .. ")" end
            KM.Print(ns, ns.TAG .. " already in your group: " .. table.concat(names, ", ") .. ".")
        end
    end
    members = now
    if unknown and not retried then
        retried = true
        C_Timer.After(1, function() retried = false; KM.Safe(ns.ReadGroup) end)
    end
    if KM.RefreshBadges then KM.RefreshBadges() end
end

-- Listed players in your group right now (the sidebar badge).
function ns.InGroupListed()
    local out = {}
    for key in pairs(members or {}) do
        local e = ns.Entries()[key]
        if e and not e.del then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end

local lastInvite = {}
local function onInvite(name)
    if not ns.db or not S().alertInvite then return end
    local e = lookup(plain(name))
    if not e then return end
    local t = GetTime and GetTime() or 0
    if lastInvite[e.n] and t - lastInvite[e.n] < 10 then return end
    lastInvite[e.n] = t
    ns.Alert(e, "is inviting you to a group")
end

---------------------------------------------------------------------------
-- Right-click menus
---------------------------------------------------------------------------

ns.MENU_TAGS = { "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID",
    "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE" }

-- Who a menu is about: "Evil Guy" (plus a unit and GUID when it has them), or nil.
function ns.MenuName(cd)
    if type(cd) ~= "table" then return nil end
    local unit = plain(cd.unit)
    if type(unit) == "string" then
        if UnitIsPlayer and not plain(UnitIsPlayer(unit)) then return nil end
        if UnitIsUnit and plain(UnitIsUnit(unit, "player")) then return nil end
        local n = ns.UnitFullName(unit)
        if n then return n, unit, UnitGUID and plain(UnitGUID(unit)) end
    end
    local name = plain(cd.chatTarget)
    if type(name) ~= "string" or name == "" then
        local first, sur = plain(cd.name), plain(cd.surname)
        if type(first) ~= "string" then return nil end
        name = first
        if type(sur) == "string" and sur ~= "" and sur ~= (GetNormalizedRealmName and GetNormalizedRealmName()) then
            name = first .. " " .. sur
        end
    end
    local guid = plain(cd.guid)
    return ns.Name(name), nil, type(guid) == "string" and guid or nil
end

local function onMenu(_, root, cd)
    if not ns.db or not root then return end
    local name, unit, guid = ns.MenuName(cd)
    if not name or KM.IsMe(name) then return end
    local e = ns.Get(name)
    if not e and ns.IsGuildmate(name, unit) then return end
    root:CreateDivider()
    if e then
        root:CreateButton(ns.RED .. "Blacklist:|r edit note", function() ns.OpenDialog({ name = name, guid = guid, unit = unit }) end)
        root:CreateButton("Remove from Blacklist", function() ns.ConfirmRemove(name) end)
    else
        root:CreateButton("Add to Blacklist", function() ns.OpenDialog({ name = name, guid = guid, unit = unit }) end)
    end
end
ns.OnMenu = onMenu

local menusDone = false
local function hookMenus()
    if menusDone or not (Menu and Menu.ModifyMenu) then return end
    menusDone = true
    for _, tag in ipairs(ns.MENU_TAGS) do
        pcall(Menu.ModifyMenu, tag, function(owner, root, cd) KM.Safe(onMenu, owner, root, cd) end)
    end
end

---------------------------------------------------------------------------
-- Unit tooltips
---------------------------------------------------------------------------

local function onUnitTooltip(tooltip, data)
    if not ns.db or not S().tooltip or tooltip ~= GameTooltip then return end
    local e
    local unit
    if tooltip.GetUnit then
        local ok, _, u = pcall(tooltip.GetUnit, tooltip)
        if ok then unit = plain(u) end
    end
    if type(unit) == "string" and UnitIsPlayer and plain(UnitIsPlayer(unit)) then
        local name = ns.UnitFullName(unit)
        if name and not KM.IsMe(name) then e = lookup(name) end
    end
    if not e and type(data) == "table" then e = ns.GetByGUID(plain(data.guid)) end
    if not e then return end
    tooltip:AddLine(ns.TAG .. " |cffff8080" .. ns.ReasonLabel(e.r) .. "|r")
    tooltip:AddLine(e.note or "", 1, 0.55, 0.55, true)
    tooltip:AddLine("added by " .. (e.by or "?") .. ", " .. (date and date("%d %b %Y", e.t or 0) or ""), 0.6, 0.6, 0.6)
    if tooltip.Show then pcall(tooltip.Show, tooltip) end
end
ns.OnUnitTooltip = onUnitTooltip

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

local function senderTag(sender)
    if not ns.db or not S().chatTag then return nil end
    return lookup(plain(sender))
end

-- ChatFrameUtil.AddSenderNameFilter: (event, decoratedName, text, sender, ...) -> new name, or nil to leave it.
local function nameFilter(_, decorated, _, sender)
    if ns.IsSecret(decorated) or type(decorated) ~= "string" then return nil end
    if senderTag(sender) then return ns.TAG .. " " .. decorated end
    return nil
end
ns.ChatNameFilter = nameFilter

-- The fallback message filter: (chatFrame, event, text, sender, ...) -> false, text with the tag in front, ...
local function messageFilter(_, _, text, sender, ...)
    if type(text) == "string" and not ns.IsSecret(text) and senderTag(sender) then
        return false, ns.TAG .. " " .. text, sender, ...
    end
    return false, text, sender, ...
end
ns.ChatMessageFilter = messageFilter

local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }

ns.chatHook = nil
local function hookChat()
    if ns.chatHook then return end
    if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
        if pcall(ChatFrameUtil.AddSenderNameFilter, nameFilter) then ns.chatHook = "name" return end
    end
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        for _, ev in ipairs(CHAT_EVENTS) do pcall(add, ev, messageFilter) end
        ns.chatHook = "message"
    end
end

---------------------------------------------------------------------------
-- The group finder (Blizzard_GroupFinder_VanillaStyle) and its Who list
---------------------------------------------------------------------------

local marks = setmetatable({}, { __mode = "k" })     -- Blizzard frame -> our font string (never a field on theirs)
local clickHooked = setmetatable({}, { __mode = "k" })
local tipBox

local function mark(frame, anchor, text)
    local fs = marks[frame]
    if not fs then
        if not frame.CreateFontString then return nil end
        fs = frame:CreateFontString(nil, "OVERLAY")
        KM.UI.Font(fs, 10, "OUTLINE")
        fs:SetTextColor(RED[1], RED[2], RED[3], 1)
        fs:SetPoint("RIGHT", anchor or frame, anchor and "LEFT" or "RIGHT", -6, 0)
        marks[frame] = fs
    end
    if text then fs:SetText(text); fs:Show() else fs:Hide() end
    return fs
end
ns.Marks = marks

local function leaderOf(resultID)
    if not (resultID and C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or type(info) ~= "table" then return nil end
    return plain(info.leaderName), info
end

-- Listed players in a listing: the leader's entry (or nil) and the listed members' entries.
local function listingHits(resultID)
    local leader, info = leaderOf(resultID)
    if not info then return nil, {} end
    local lead = lookup(leader)
    local others = {}
    local n = tonumber(plain(info.numMembers)) or 0
    if n > 1 and C_LFGList.GetSearchResultPlayerInfo then
        for i = 1, math.min(n, 40) do
            local ok, m = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
            local mname = ok and type(m) == "table" and plain(m.name) or nil
            local e = mname and lookup(mname)
            if e and e ~= lead then others[#others + 1] = e end
        end
    end
    return lead, others, leader
end
ns.ListingHits = listingHits

local function onEntryClick(entry, button)
    if not ns.db or button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) then return end
    local leader = leaderOf(entry.resultID)
    local name = ns.Name(leader)
    if not name or KM.IsMe(name) then return end
    if ns.Get(name) then ns.OpenDialog({ name = name }) return end
    if ns.IsGuildmate(name) then KM.Print(ns, name .. " is in your guild: guildmates can't be blacklisted.") return end
    ns.OpenDialog({ name = name })
end

local function decorateEntry(entry)
    if not ns.db or type(entry) ~= "table" then return end
    if not clickHooked[entry] and entry.HookScript then
        clickHooked[entry] = true
        pcall(entry.HookScript, entry, "OnClick", function(self, button) KM.Safe(onEntryClick, self, button) end)
    end
    if not S().lfg then mark(entry, nil, nil) return end
    local lead, others = listingHits(entry.resultID)
    if lead then
        if entry.Name and entry.Name.SetTextColor then pcall(entry.Name.SetTextColor, entry.Name, RED[1], RED[2], RED[3]) end
        mark(entry, entry.DataDisplay, "BLACKLISTED")
    elseif others and #others > 0 then
        mark(entry, entry.DataDisplay, #others == 1 and "1 BLACKLISTED" or (#others .. " BLACKLISTED"))
    else
        mark(entry, entry.DataDisplay, nil)
    end
end
ns.DecorateEntry = decorateEntry

-- Our own small box under the listing's tooltip (the tooltip is a custom frame we don't resize).
local function decorateTip(tip, resultID)
    if not ns.db or type(tip) ~= "table" then return end
    if not tipBox then
        tipBox = CreateFrame("Frame", nil, tip)
        tipBox:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -2)
        tipBox:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", 0, -2)
        KM.UI.Fill(tipBox, { 0.08, 0.02, 0.02, 0.94 })
        KM.UI.Border(tipBox, { RED[1], RED[2], RED[3], 0.6 })
        tipBox.text = KM.UI.Para(tipBox, 11, { 1, 0.55, 0.55, 1 })
        tipBox.text:SetPoint("TOPLEFT", 8, -6)
        tipBox.text:SetPoint("RIGHT", -8, 0)
        tipBox:Hide()
    end
    if tipBox:GetParent() ~= tip and tipBox.SetParent then tipBox:SetParent(tip) end
    local lead, others = nil, {}
    if S().lfg then lead, others = listingHits(resultID) end
    local lines = {}
    if lead then lines[#lines + 1] = ns.TAG .. " leader " .. lead.n .. ": " .. reasonLine(lead) end
    for _, e in ipairs(others or {}) do lines[#lines + 1] = ns.TAG .. " " .. e.n .. ": " .. reasonLine(e) end
    if #lines == 0 then tipBox:Hide() return end
    tipBox.text:SetText(table.concat(lines, "\n"))
    tipBox:SetHeight(12 + 14 * #lines + 14)
    tipBox:Show()
end
ns.DecorateTip = decorateTip
function ns.TipBox() return tipBox end

local function decorateWho(_, frame)
    if not ns.db or type(frame) ~= "table" then return end
    local name = plain(frame.OriginalName)
    if type(name) ~= "string" and frame.Name and frame.Name.GetText then name = plain(frame.Name:GetText()) end
    local e = S().lfg and lookup(name)
    if e then
        if frame.Name and frame.Name.SetTextColor then pcall(frame.Name.SetTextColor, frame.Name, RED[1], RED[2], RED[3]) end
        mark(frame, nil, "BLACKLISTED")
    else
        mark(frame, nil, nil)
    end
end
ns.DecorateWho = decorateWho

ns.lfgHooked = false
function ns.HookGroupFinder()
    if ns.lfgHooked then return end
    if not (LFGBrowseSearchEntry_Update or LFGBrowseSearchEntryTooltip_UpdateAndShow or LFGWhoListFrame) then return end
    ns.lfgHooked = true
    if hooksecurefunc and LFGBrowseSearchEntry_Update then
        pcall(hooksecurefunc, "LFGBrowseSearchEntry_Update", function(entry) KM.Safe(decorateEntry, entry) end)
    end
    if hooksecurefunc and LFGBrowseSearchEntryTooltip_UpdateAndShow then
        pcall(hooksecurefunc, "LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tip, id) KM.Safe(decorateTip, tip, id) end)
    end
    local box = LFGWhoListFrame and LFGWhoListFrame.ScrollBox
    local ev = ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnInitializedFrame
    if box and box.RegisterCallback and ev then
        pcall(box.RegisterCallback, box, ev, function(owner, frame) KM.Safe(decorateWho, owner, frame) end, ns)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local GF = "Blizzard_GroupFinder_VanillaStyle"

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "ADDON_LOADED", "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT", "PARTY_INVITE_REQUEST",
    "PLAYER_GUILD_UPDATE")
f:SetScript("OnEvent", function(_, event, a1)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        KM.Safe(hookMenus)
        KM.Safe(hookChat)
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
            pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt, data) KM.Safe(onUnitTooltip, tt, data) end)
        end
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and ns.Call(C_AddOns.IsAddOnLoaded, GF)
        if loaded then KM.Safe(ns.HookGroupFinder) end
        C_Timer.After(2, function() KM.Safe(ns.ReadGroup) end)
    elseif event == "ADDON_LOADED" then
        if a1 == GF then KM.Safe(ns.HookGroupFinder) end
    elseif event == "PARTY_INVITE_REQUEST" then
        KM.Safe(onInvite, a1)
    elseif event == "PLAYER_GUILD_UPDATE" then
        ns.RosterReset()
        ns.ClearLookups()
        if ns.Refresh then ns.Refresh() end
    else
        KM.Safe(ns.ReadGroup)
    end
end)

-- Tests: the session state.
function ns.AlertReset() members = nil; wipe(alerted); wipe(lastInvite); retried = false; ns.alerts = 0 end
function ns.Members() return members end
