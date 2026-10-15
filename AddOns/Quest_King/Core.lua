local addonName, ns = ...

local PREFIX = "|cffffd100Quest King|r: "
local QUEST_CLASS = 12 -- Enum.ItemClass.Questitem

local DEFAULTS = {
    marks = true,   -- show the mark on bag slots
    tooltip = true, -- add a line to the item tooltip
    button = true,  -- minimap button (the dungeon quest window)
    dqHide60 = false, dqHideDone = false, dqView = "dungeons",
}

QuestKing = ns

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

---------------------------------------------------------------------------
-- Quest log
---------------------------------------------------------------------------

-- Everything the quest log says, lowercased into one string, so an item can be
-- matched by name against objectives ("Wolf Fang: 3/10"), descriptions
-- ("Bring the Sealed Letter to...") and usable quest items.
local questText = ""
local logComplete = true    -- false when collapsed headers hide quests from us
local logHasCollapsed = false

local function add(parts, s)
    if type(s) == "string" and s ~= "" then parts[#parts + 1] = s:lower() end
end

local function linkName(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end
ns.LinkName = linkName

function ns.ScanQuestLog()
    local parts = {}
    local shown, numQuests = C_QuestLog.GetNumQuestLogEntries()
    local seen, collapsed = 0, false
    for i = 1, shown or 0 do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            if info.isCollapsed then collapsed = true end
        elseif info then
            seen = seen + 1
            add(parts, info.title)
            local objectives = info.questID and C_QuestLog.GetQuestObjectives(info.questID)
            for _, o in ipairs(objectives or {}) do add(parts, o.text) end
            if GetQuestLogSpecialItemInfo then
                add(parts, linkName((GetQuestLogSpecialItemInfo(i))))
            end
            if GetQuestLogQuestText then
                local desc, objText = GetQuestLogQuestText(i)
                add(parts, desc); add(parts, objText)
            end
        end
    end
    questText = table.concat(parts, "\n")
    logHasCollapsed = collapsed
    -- Only distrust the log when quests are missing AND a header is collapsed;
    -- some clients count hidden quests that never show as entries.
    logComplete = not (collapsed and numQuests and seen < numQuests)
end

local function onQuest(questID)
    if C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(questID) end
    return C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

local function questDone(questID)
    return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID)
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

-- Per slot: nil (not a quest item, or we can't tell), "needed", "starter"
-- (starts a quest you haven't done) or "unneeded" (safe to delete).
local status = {}
local unneededIDs = {}

function ns.IsQuestItem(itemID, questInfo)
    if questInfo and (questInfo.isQuestItem or questInfo.questID) then return true end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == QUEST_CLASS
end

-- Why a quest item is or isn't needed. Returns status, reason.
function ns.Judge(itemID, link, questInfo)
    if not ns.IsQuestItem(itemID, questInfo) then return nil end
    local questID = questInfo and questInfo.questID
    if questID then
        if questInfo.isActive or onQuest(questID) then return "needed", "its quest is in your log" end
        if questDone(questID) then return "unneeded", "you already did the quest it starts" end
        return "starter", "it starts a quest"
    end
    if not logComplete then return nil end
    local name = linkName(link) or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
    if not name then return nil end
    if questText:find(name:lower(), 1, true) then return "needed", "a quest in your log mentions it" end
    return "unneeded", "no quest in your log needs it"
end

local function lastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

function ns.ScanBags()
    wipe(status); wipe(unneededIDs)
    for bag = 0, lastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                local s, why = ns.Judge(info.itemID, info.hyperlink, q)
                if s then
                    status[bag * 1000 + slot] = s
                    if s == "unneeded" then unneededIDs[info.itemID] = why end
                end
            end
        end
    end
end

function ns.Status(bag, slot)
    if not bag or not slot then return nil end
    return status[bag * 1000 + slot]
end

-- Reason text when no quest needs this item, else nil.
function ns.UnneededReason(itemID)
    return itemID and unneededIDs[itemID]
end

function ns.Unneeded()
    local list = {}
    for bag = 0, lastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            if status[bag * 1000 + slot] == "unneeded" then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                list[#list + 1] = { bag = bag, slot = slot, link = info.hyperlink, count = info.stackCount or 1,
                                    why = unneededIDs[info.itemID] }
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local pending = false
function ns.Refresh()
    ns.ScanQuestLog()
    ns.ScanBags()
    if ns.UpdateBagButtons then ns.UpdateBagButtons() end
    if ns.RefreshDungeons then ns.RefreshDungeons() end
end

-- Bag and quest events come in bursts; refresh once after they settle.
function ns.RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false; ns.Refresh() end)
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function list()
    ns.Refresh()
    if not logComplete then
        ns.Print("Expand all the headers in your quest log so I can see every quest, then try again.")
        return
    end
    local items = ns.Unneeded()
    if #items == 0 then
        ns.Print("Every quest item in your bags is needed by a quest in your log.")
        return
    end
    ns.Print(#items == 1 and "1 quest item you can delete:" or (#items .. " quest items you can delete:"))
    for _, it in ipairs(items) do
        local count = it.count > 1 and (" x" .. it.count) or ""
        ns.Print("  " .. (it.link or "?") .. count .. " (" .. it.why .. ")")
    end
end

local function onOff(word, key, label)
    if word == "on" then QuestKingDB[key] = true
    elseif word == "off" then QuestKingDB[key] = false
    else QuestKingDB[key] = not QuestKingDB[key] end
    ns.Print(label .. (QuestKingDB[key] and " on." or " off."))
    ns.Refresh()
end

SLASH_QUESTKING1 = "/qk"
SLASH_QUESTKING2 = "/questking"
SlashCmdList.QUESTKING = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "" or cmd == "list" then
        list()
    elseif cmd == "dungeons" or cmd == "d" or cmd == "dungeon" then
        ns.ToggleDungeons()
    elseif cmd == "route" then
        QuestKingDB.dqView = "route"
        ns.ToggleDungeons(true)
    elseif cmd == "button" then
        onOff(arg, "button", "Minimap button")
        ns.UpdateMinimapButton()
    elseif cmd == "marks" then
        onOff(arg, "marks", "Bag marks")
    elseif cmd == "tooltip" then
        onOff(arg, "tooltip", "Tooltip line")
    else
        ns.Print("/qk - list quest items no quest in your log needs")
        ns.Print("/qk dungeons - dungeon quests: what you've done, what's next, where to go")
        ns.Print("/qk route - the dungeon route: what to pick up before each run")
        ns.Print("/qk button on|off - the minimap button")
        ns.Print("/qk marks on|off - show or hide the red X on bag slots")
        ns.Print("/qk tooltip on|off - show or hide the tooltip line")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- Only register events this client knows; registering an unknown one errors.
local function known(event)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
    if known(e) then f:RegisterEvent(e) end
end
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        QuestKingDB = QuestKingDB or {}
        for k, v in pairs(DEFAULTS) do
            if QuestKingDB[k] == nil then QuestKingDB[k] = v end
        end
        QuestKingDB.dqDone = QuestKingDB.dqDone or {} -- dungeon quests you ticked off yourself
    elseif event == "PLAYER_LOGIN" then
        if ns.HookBags then ns.HookBags() end
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
        ns.RequestRefresh()
    else
        ns.RequestRefresh()
    end
end)
