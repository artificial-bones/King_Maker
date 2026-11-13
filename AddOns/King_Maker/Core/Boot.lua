local addonName, KM = ...

-- Boot: loads last. Initialises King Maker's own saved variable, every module's (in .toc order), moves old data in
-- from the legacy King addon folders, and owns /km.
--
-- Moving data in from 1.x. King Maker keeps every module's old saved-variable name (ScannerKingDB, ...) inside its
-- own file (WTF\...\SavedVariables\King_Maker.lua). Release 2.0 also ships tiny stub folders with the old names
-- (Scanner_King, ...): each declares its old saved variable and depends on King_Maker, so the game loads it right
-- after King Maker and reads the player's old Scanner_King.lua back into _G.ScannerKingDB. When that stub's
-- ADDON_LOADED arrives:
--   * not moved yet: the old contents are copied into the table the module already holds (so every reference stays
--     valid), the module's InitDB runs again to fill in defaults, and the move is recorded in KingMakerDB.moved;
--   * moved before: the stub's copy is stale (or identical); the module's live table is put back.
-- While the stubs stay installed the game keeps writing the same tables to both files, which is harmless (and
-- keeps the King Dashboard reading the old file names). Deleting the stub folders later loses nothing.

KM.LEGACY = {
    Scanner_King = { var = "ScannerKingDB", mod = "Scanner" },
    Econ_King = { var = "EconKingDB", mod = "Econ" },
    Market_King = { var = "MarketKingDB", mod = "Market" },
    Skillup_King = { var = "SkillupKingDB", mod = "Skillup" },
    Farm_King = { var = "FarmKingDB", mod = "Farm" },
    gather_king = { var = "GatherKingDB", mod = "Gather" },
    Inventory_King = { var = "InventoryKingDB", mod = "Inventory" },
    Mail_King = { var = "MailKingDB", mod = "Mail" },
    Quest_King = { var = "QuestKingDB", mod = "Quest" },
    Rested_King = { var = "RestedKingDB", mod = "Rested" },
    Minimap_King = { var = "MinimapKingDB", mod = "Minimap" },
}

local live = {}          -- var -> the table the module holds
local report = {}        -- lines for Settings > General
local oldCode = {}       -- legacy folders that are the real 1.x addon, not a stub

local function initModule(m)
    if m.InitDB then KM.Safe(m.InitDB) end
end

local function initCore()
    KingMakerDB = KingMakerDB or {}
    local db = KingMakerDB
    db.version = 1
    db.moved = db.moved or {}
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
    db.ui.collapsed = db.ui.collapsed or {}
    db.ui.buttonAngle = db.ui.buttonAngle or 200
    KM.db = db
end

local function isStub(folder)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return true end
    local ok, v = pcall(get, folder, "X-KingMaker-Stub")
    return ok and v ~= nil
end

local function copyInto(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end

-- A legacy folder has loaded and the game has just put its saved variable in _G.
function KM.TakeLegacy(folder)
    local l = KM.LEGACY[folder]
    if not l then return end
    local m = KM.mods[l.mod]
    local title = (m and m.info.title) or folder
    if not isStub(folder) then
        oldCode[#oldCode + 1] = title
        report[#report + 1] = "|cffff6060" .. title .. ": the old 1.x addon is still installed.|r Replace its folder with the one from King Maker 2.0 (or delete it), or both run at once."
        return
    end
    local cur, old = live[l.var], _G[l.var]
    if type(cur) ~= "table" then
        -- the module never initialised (an error): leave the old data where it is
        return
    end
    if KingMakerDB.moved[l.var] then
        _G[l.var] = cur
        report[#report + 1] = title .. ": moved in " .. date("%Y-%m-%d", KingMakerDB.moved[l.var]) .. ". Its old folder (" .. folder .. ") can be deleted."
        return
    end
    if type(old) == "table" and old ~= cur and next(old) ~= nil then
        copyInto(cur, old)
        report[#report + 1] = title .. ": your settings and data were moved in just now."
        KM.movedNow = (KM.movedNow or 0) + 1
    else
        report[#report + 1] = title .. ": nothing to move (no old data)."
    end
    _G[l.var] = cur
    KingMakerDB.moved[l.var] = KM.Now()
    if m then initModule(m); live[l.var] = _G[l.var] or cur end
end

function KM.MigrationReport() return report end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName then
            initCore()
            KM.Each(initModule)
            for _, l in pairs(KM.LEGACY) do live[l.var] = _G[l.var] end
            KM.loaded = true
            KM.RenameChar()
            if KM.OnLoaded then KM.Safe(KM.OnLoaded) end
        elseif KM.loaded and KM.LEGACY[name] then
            KM.TakeLegacy(name)
        end
    elseif event == "PLAYER_LOGIN" then
        KM.RenameChar() -- again: the surname may only be known now
        KM.UpdateMinimapButton()
        if KM.movedNow then
            KM.Print("moved your old King addon data in (" .. KM.movedNow .. " addons). Everything now lives in King Maker; /km opens it.")
        end
        if #oldCode > 0 then
            KM.Print("|cffff6060old King addons are still installed:|r " .. table.concat(oldCode, ", ") .. ". Replace their folders with the King Maker 2.0 ones, or delete them.")
        end
    end
end)

-- If the game ever stops King Maker from doing something, say what it was (one guard for every module).
local guard = CreateFrame("Frame")
KM.Register(guard, "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED")
guard:SetScript("OnEvent", function(_, event, addon, what)
    if addon == addonName then
        KM.Print("the game blocked King Maker from " .. tostring(what) .. " (" .. event .. "). Please send this line along.")
    end
end)

-----
-- /km
-----

local function findPage(q)
    q = q:lower()
    for id, p in pairs(KM.pages) do if id == q then return id end end
    for id, p in pairs(KM.pages) do if (p.label or ""):lower():find(q, 1, true) then return id end end
end

SLASH_KINGMAKER1, SLASH_KINGMAKER2 = "/km", "/kingmaker"
SlashCmdList.KINGMAKER = function(msg)
    msg = strtrim and strtrim(msg or "") or (msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        KM.Toggle()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        KM.OpenSettings(rest ~= "" and rest or nil)
    elseif cmd == "button" then
        local u = KingMakerDB.ui
        u.button = rest == "on" or (rest ~= "off" and not u.button)
        KM.UpdateMinimapButton()
        KM.Print("minimap button " .. (u.button and "shown" or "hidden") .. ".")
    elseif cmd == "status" then
        KM.Print("version " .. KM.version .. ", " .. #KM.order .. " modules.")
        for _, line in ipairs(report) do KM.Print(line) end
    elseif cmd == "help" or cmd == "?" then
        KM.Print("commands:")
        KM.Print("/km   open or close the window")
        KM.Print("/km <page>   open a page (prices, history, crafting, skillups, ledger, inventory, mobs, gathering, dungeons, rested)")
        KM.Print("/km settings   settings")
        KM.Print("/km button [on|off]   minimap button")
        KM.Print("/km status   version and what was moved in from the old addons")
    else
        local id = findPage(msg)
        if id then KM.Show(id) else KM.Print("no page called '" .. msg .. "'. /km help lists the commands.") end
    end
end
