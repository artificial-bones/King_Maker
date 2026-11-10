local _, KM = ...
local ns = KM.Module("Quest", { title = "Quest King", short = "Quest", legacy = "Quest_King", db = "QuestKingDB" })

-- Quest King: the quest items in your bags that no quest needs (red X on the slot, a tooltip line, /qk), and the
-- Dungeon Quests page of the King Maker window (Characters > Dungeon Quests, Dungeon.lua and DungeonUI.lua).
-- Its public face is the whole module: QuestKing = ns, as in 1.x. It has no minimap button of its own any more:
-- the King Maker crown's quick actions open the page.

local QUEST_CLASS = 12 -- Enum.ItemClass.Questitem

local DEFAULTS = {
    marks = true,   -- show the mark on bag slots
    tooltip = true, -- add a line to the item tooltip
    dqHide60 = false, dqHideDone = false, dqView = "dungeons",
}

QuestKing = ns

-- Kept for anything that called QuestKing.Print in 1.x.
function ns.Print(msg) KM.Print(ns, msg) end

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
    if ns.RefreshDungeons then ns.RefreshDungeons() end -- redraws the Dungeon Quests page when it's open
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
        KM.Print(ns, "Expand all the headers in your quest log so I can see every quest, then try again.")
        return
    end
    local items = ns.Unneeded()
    if #items == 0 then
        KM.Print(ns, "Every quest item in your bags is needed by a quest in your log.")
        return
    end
    KM.Print(ns, #items == 1 and "1 quest item you can delete:" or (#items .. " quest items you can delete:"))
    for _, it in ipairs(items) do
        local count = it.count > 1 and (" x" .. it.count) or ""
        KM.Print(ns, "  " .. (it.link or "?") .. count .. " (" .. it.why .. ")")
    end
end

local function onOff(word, key, label)
    if word == "on" then QuestKingDB[key] = true
    elseif word == "off" then QuestKingDB[key] = false
    else QuestKingDB[key] = not QuestKingDB[key] end
    KM.Print(ns, label .. (QuestKingDB[key] and " on." or " off."))
    ns.Refresh()
end

SLASH_QUESTKING1 = "/qk"
SLASH_QUESTKING2 = "/questking"
SlashCmdList.QUESTKING = function(msg)
    if not QuestKingDB then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "" or cmd == "list" then
        list()
    elseif cmd == "dungeons" or cmd == "d" or cmd == "dungeon" then
        ns.ToggleDungeons()
    elseif cmd == "route" then
        QuestKingDB.dqView = "route"
        ns.ToggleDungeons(true)
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "marks" then
        onOff(arg, "marks", "Bag marks")
    elseif cmd == "tooltip" then
        onOff(arg, "tooltip", "Tooltip line")
    else
        KM.Print(ns, "/qk   list quest items no quest in your log needs")
        KM.Print(ns, "/qk dungeons   Dungeon Quests: what you've done, what's next, where to go (or /km dungeons)")
        KM.Print(ns, "/qk route   the dungeon route: what to pick up before each run")
        KM.Print(ns, "/qk marks on|off   show or hide the red X on bag slots")
        KM.Print(ns, "/qk tooltip on|off   show or hide the tooltip line")
    end
end

---------------------------------------------------------------------------
-- Saved data and events
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Quest_King data is moved in: safe twice.
function ns.InitDB()
    QuestKingDB = QuestKingDB or {}
    local db = QuestKingDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.dqDone = db.dqDone or {} -- dungeon quests you ticked off yourself
    db.button, db.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    ns.db = db
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
KM.Register(f, "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, event)
    if not QuestKingDB then return end
    if event == "PLAYER_LOGIN" then
        if ns.HookBags then ns.HookBags() end
    end
    ns.RequestRefresh()
end)
