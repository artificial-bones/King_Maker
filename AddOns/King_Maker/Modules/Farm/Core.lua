local _, KM = ...
local ns = KM.Module("Farm", { title = "Farm King", short = "Farm", legacy = "Farm_King", db = "FarmKingDB" })

-- Farm King: which mobs are worth farming. For every mob it knows, it works
-- out the average gold a kill is worth: its coin plus each drop's chance times
-- what the drop sells for (Scanner King's prices, or the vendor).
--
-- Where the mobs come from:
--   * every mob you see, target or kill (always),
--   * every mob in the game from QuestieDB, when it's installed.
-- Drop rates come from your own kills, plus your guild's when they share.
--
-- In King Maker it has no window or minimap button of its own: the list and a mob's page are the "mobs"
-- page (UI.lua, Mob.lua), White Items is the "whites" page (White.lua), and its clicks are quick actions on the
-- King Maker crown. The session tracker is King Maker's Farm Tracker (Modules\Tracker), which Farm feeds kills.

FarmKing = { API_VERSION = 1 }
local API = FarmKing
ns.API = API

function ns.Now()
    return ScannerKing and ScannerKing.Now and ScannerKing.Now() or (GetServerTime and GetServerTime()) or time()
end

function ns.Money(v)
    if not v then return "|cff808080-|r" end
    local s = ScannerKing and ScannerKing.FormatMoney and ScannerKing.FormatMoney(math.abs(v)) or tostring(math.floor(math.abs(v)))
    return v < 0 and ("-" .. s) or s
end

---------------------------------------------------------------------------
-- Items: the shared cache and value rule (Core\Items.lua since King Maker 2.6; the Farm Tracker uses the same)
---------------------------------------------------------------------------

-- { name, q = quality, icon, sell = vendor copper, bop = bind on pickup, class }
ns.Item = KM.Item
ns.ItemText = KM.ItemText
ns.TakeWaiting = KM.TakeItemWaiting
ns.QUALITY_COLOR = KM.QUALITY_COLOR

-- What one of an item is worth to you: grey and bind-on-pickup items go to a vendor; anything else the better of
-- the auction house (after its 5% cut) and a vendor. Quest items are worth nothing here. Also returns where the
-- value came from ("ah", "vendor") or nil when it isn't known yet.
ns.ItemValue = KM.ItemValue

---------------------------------------------------------------------------
-- Saved data, slash command
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Farm_King data is moved in: safe twice.
function ns.InitDB()
    FarmKingDB = FarmKingDB or {}
    local db = FarmKingDB
    db.mobs = db.mobs or {}       -- npcID -> what you've seen and looted (Tracker.lua)
    db.guild = db.guild or {}     -- guildmate -> { t = received, mobs = { [npcID] = { k, c, i } } }
    db.fav = db.fav or {}         -- npcID -> true
    db.track = db.track or {}     -- npcID -> true: spawns shown on the world map
    db.corpses = db.corpses or {} -- corpse GUID -> when it was counted (kept an hour)
    db.recent = db.recent or {}   -- npcIDs you killed, the latest first (Recent kills)
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    db.filter = db.filter or {}
    local fl = db.filter
    for _, k in ipairs({ "q0", "q1", "q2", "q3", "q4", "coin", "guild" }) do
        if fl[k] == nil then fl[k] = true end
    end
    fl.minKills = fl.minKills or 5
    if fl.near == nil then fl.near = false end
    if db.answer == nil then db.answer = true end -- answer guildmates' requests for drop data
    ns.db = db
    ns.PruneCorpses()
end

SLASH_FARMKING1 = "/fk"
SLASH_FARMKING2 = "/farmking"
SlashCmdList.FARMKING = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "white" or cmd == "whites" then
        KM.Show("whites")
    elseif cmd == "mob" then
        local id = tonumber(rest)
        if id then ns.Toggle(true); ns.ShowMob(id) end
    elseif cmd == "share" then
        ns.db.answer = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.answer)
        KM.Print(ns, "Answering guildmates' drop data requests: " .. (ns.db.answer and "on." or "off."))
    elseif cmd == "forget" and rest:lower() == "guild" then
        ns.ForgetGuild()
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    elseif cmd == "mini" then
        -- the old farm tracker box is King Maker's Farm Tracker now (also /farm)
        if TrackerKing and TrackerKing.SetHUD then
            local on = rest:lower() == "on" or (rest:lower() ~= "off" and not TrackerKing.HUDShown())
            KM.Safe(TrackerKing.SetHUD, on)
        else
            KM.Print(ns, "The Farm Tracker isn't loaded.")
        end
    elseif cmd == "status" then
        local mobs, kills = 0, 0
        for _, m in pairs(ns.db.mobs) do mobs = mobs + 1; kills = kills + (m.k or 0) end
        local mates = 0
        for _ in pairs(ns.db.guild) do mates = mates + 1 end
        KM.Print(ns, mobs .. " mobs seen, " .. kills .. " kills recorded, drop data from " .. mates .. " guildmate(s). QuestieDB: "
            .. (ns.QuestieReady and ns.QuestieReady() and "found." or "not installed (only mobs you've seen are listed)."))
    else
        KM.Print(ns, "/fk   open the Mob Farming page (or /km mobs)")
        KM.Print(ns, "/fk white   open the White Items page")
        KM.Print(ns, "/fk status   what's been recorded")
        KM.Print(ns, "/fk share [on|off]   answer guildmates' requests for your drop data")
        KM.Print(ns, "/fk forget guild   drop every guildmate's data")
        KM.Print(ns, "/fk mini [on|off]   the Farm Tracker (also /farm)")
    end
end

function ns.ForgetGuild()
    ns.db.guild = {}
    KM.Print(ns, "Forgot every guildmate's drop data.")
    if ns.Refresh then ns.Refresh() end
end
