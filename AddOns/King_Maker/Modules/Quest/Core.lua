local _, KM = ...
local ns = KM.Module("Quest", { title = "Quest King", short = "Quest", legacy = "Quest_King", db = "QuestKingDB" })

-- Quest King: the Quest Gold page of the King Maker window (Gold > Quest Gold: Money.lua and MoneyUI.lua, data in
-- Data/Quests.lua). King Maker 2.4.0 replaced the Dungeon Quests page with Quest Gold; 2.5.3 took out the bag
-- cleanup (red X on quest items, the tooltip line, /qk list).
-- Its public face is the whole module: QuestKing = ns, as in 1.x. It has no minimap button of its own any more:
-- the King Maker crown's quick actions open the page.

local DEFAULTS = {
    qgHideDone = false, -- Quest Gold: leave out quests you've done
}

QuestKing = ns

-- Kept for anything that called QuestKing.Print in 1.x.
function ns.Print(msg) KM.Print(ns, msg) end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local pending = false
function ns.Refresh()
    if ns.RefreshQuestGold then ns.RefreshQuestGold() end -- redraws the Quest Gold page when it's open
end

-- Quest events come in bursts; refresh once after they settle.
function ns.RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false; ns.Refresh() end)
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_QUESTKING1 = "/qk"
SLASH_QUESTKING2 = "/questking"
SlashCmdList.QUESTKING = function(msg)
    if not QuestKingDB then return end
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "gold" or cmd == "g" then
        ns.ToggleQuestGold()
    elseif cmd == "dungeons" or cmd == "route" then
        KM.Print(ns, "Dungeon Quests is gone (other addons do it better); Quest Gold took its place: /qk gold")
    elseif cmd == "list" or cmd == "tooltip" or cmd == "marks" then
        KM.Print(ns, "Bag cleanup is gone from King Maker (2.5.3). /qk opens Quest Gold.")
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    else
        KM.Print(ns, "/qk   Quest Gold: the 48+ quests left for this character and what each zone is worth (or /km questgold)")
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
    db.gold = db.gold or {} -- quest ID -> copper: Forever's real quest gold, learned in game (Money.lua), every character
    db.noData = db.noData or {} -- quest ID -> true: the server had nothing on it (not in Forever yet); out of the totals
    db.dqDone, db.dqHide60, db.dqHideDone, db.dqView = nil, nil, nil, nil -- Dungeon Quests (gone in 2.4.0)
    db.button, db.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    db.marks, db.tooltip = nil, nil -- bag cleanup (gone in 2.5.3)
    ns.db = db
end

local f = CreateFrame("Frame")
KM.Register(f, "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function()
    if not QuestKingDB then return end
    ns.RequestRefresh()
end)
