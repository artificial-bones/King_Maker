local _, ns = ...

-- Farm King: which mobs are worth farming. For every mob it knows, it works
-- out the average gold a kill is worth: its coin plus each drop's chance times
-- what the drop sells for (Scanner King's prices, or the vendor).
--
-- Where the mobs come from:
--   * every mob you see, target or kill (always),
--   * every mob in the game from QuestieDB, when it's installed.
-- Drop rates come from your own kills, plus your guild's when they share.

FarmKing = { API_VERSION = 1 }
local API = FarmKing
ns.API = API

local PREFIX = "|cffe0a040Farm King|r: "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

function ns.Now()
    return ScannerKing and ScannerKing.Now and ScannerKing.Now() or (GetServerTime and GetServerTime()) or time()
end

function ns.Money(v)
    if not v then return "|cff808080-|r" end
    local s = ScannerKing and ScannerKing.FormatMoney and ScannerKing.FormatMoney(math.abs(v)) or tostring(math.floor(math.abs(v)))
    return v < 0 and ("-" .. s) or s
end

---------------------------------------------------------------------------
-- Items: name, quality, icon, vendor price, binding, class
---------------------------------------------------------------------------

local waiting = false
local itemCache = {}

-- { name, q = quality, icon, sell = vendor copper, bop = bind on pickup, class }
function ns.Item(id)
    local c = itemCache[id]
    if c and c.name then return c end
    c = c or {}
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if get then
        local name, _, quality, _, _, _, _, _, _, icon, sell, classID, _, bind = get(id)
        if name then
            c.name, c.q, c.icon, c.sell, c.class, c.bop = name, quality, icon, sell or 0, classID, bind == 1
        end
    end
    if not c.name then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if inst and not c.icon then
            local _, _, _, _, icon, classID = inst(id)
            c.icon, c.class = icon, c.class or classID
        end
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        waiting = true
    end
    itemCache[id] = c
    return c
end

function ns.TakeWaiting()
    local w = waiting
    waiting = false
    return w
end

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }
ns.QUALITY_COLOR = QUALITY
function ns.ItemText(id)
    local i = ns.Item(id)
    return (QUALITY[i.q or 1] or "|cffffffff") .. (i.name or ("Item " .. id)) .. "|r"
end

local CUT = 0.95

-- What one of an item is worth to you: grey and bind-on-pickup items go to a
-- vendor; anything else the better of the auction house (after its 5% cut)
-- and a vendor. Quest items are worth nothing here. Also returns where the
-- value came from ("ah", "vendor") or nil when it isn't known yet.
function ns.ItemValue(id)
    local i = ns.Item(id)
    if i.class == 12 then return 0, "quest" end
    if not i.name then return nil end
    local vendor = i.sell or 0
    if i.q == 0 or i.bop then return vendor, "vendor" end
    local ah = ScannerKing and ScannerKing.GetMarketPrice and ScannerKing.GetMarketPrice(id)
    if ah and ah * CUT > vendor then return ah * CUT, "ah" end
    return vendor, "vendor"
end

---------------------------------------------------------------------------
-- Saved data, slash command
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= "Farm_King" then return end
    FarmKingDB = FarmKingDB or {}
    local db = FarmKingDB
    db.mobs = db.mobs or {}       -- npcID -> what you've seen and looted (Tracker.lua)
    db.guild = db.guild or {}     -- guildmate -> { t = received, mobs = { [npcID] = { k, c, i } } }
    db.fav = db.fav or {}         -- npcID -> true
    db.track = db.track or {}     -- npcID -> true: spawns shown on the world map
    db.corpses = db.corpses or {} -- corpse GUID -> when it was counted (kept an hour)
    db.recent = db.recent or {}   -- npcIDs you killed, the latest first (Recent kills)
    db.session = db.session or {} -- the mini tracker's tally (Session.lua)
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
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
end)

SLASH_FARMKING1 = "/fk"
SLASH_FARMKING2 = "/farmking"
SlashCmdList.FARMKING = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "mob" then
        local id = tonumber(rest)
        if id then ns.Toggle(true); ns.ShowMob(id) end
    elseif cmd == "share" then
        ns.db.answer = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.answer)
        ns.Print("Answering guildmates' drop data requests: " .. (ns.db.answer and "on." or "off."))
    elseif cmd == "forget" and rest:lower() == "guild" then
        ns.db.guild = {}
        ns.Print("Forgot every guildmate's drop data.")
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "button" then
        ns.db.ui.button = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.button)
        ns.UpdateMinimapButton()
    elseif cmd == "mini" then
        ns.SetMini(rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.mini))
    elseif cmd == "status" then
        local mobs, kills = 0, 0
        for _, m in pairs(ns.db.mobs) do mobs = mobs + 1; kills = kills + (m.k or 0) end
        local mates = 0
        for _ in pairs(ns.db.guild) do mates = mates + 1 end
        ns.Print(mobs .. " mobs seen, " .. kills .. " kills recorded, drop data from " .. mates .. " guildmate(s). QuestieDB: "
            .. (ns.QuestieReady and ns.QuestieReady() and "found." or "not installed (only mobs you've seen are listed)."))
    else
        ns.Print("/fk   open Farm King (or click the minimap button)")
        ns.Print("/fk status   what's been recorded")
        ns.Print("/fk share [on|off]   answer guildmates' requests for your drop data")
        ns.Print("/fk forget guild   drop every guildmate's data")
        ns.Print("/fk mini [on|off]   the mini tracker: this session's kills, drops and gold per hour")
        ns.Print("/fk button [on|off]   minimap button")
    end
end
