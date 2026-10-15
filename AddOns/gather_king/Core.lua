local addonName, ns = ...

local PREFIX = "|cff33ff99Gather King|r: "
local MERGE_DISTANCE = 0.006 -- 0.6 on the 0-100 map scale

-- Every profile holds its own copy of these. Markers themselves are shared
-- by all profiles; a profile only decides what you see and what gets recorded.
local DEFAULTS = {
    show = { mine = true, herb = true, fish = true, treasure = true },
    record = { mine = true, herb = true },
    only = "",      -- comma-separated node names; empty shows every name
    minimap = true,
    auto = true,
    size = 16,
    minimapAlpha = 1, -- lower it to fade the minimap rings
    showShared = true, -- markers that came from guildmates
    hideNear = true,   -- hide a minimap ring while you're standing at it
    fadeMinutes = 5,   -- fade nodes you harvested this recently (0 = off)
}

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function fmtCoords(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end
ns.FormatCoords = fmtCoords

function ns.MapName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

---------------------------------------------------------------------------
-- Names and icons
---------------------------------------------------------------------------

-- Turns "(Thorium)", "small thorium vein", "Thorium Ore" into a known key.
function ns.LookupKnown(text)
    if not text or text == "" then return nil end
    local s = text:lower()
    for _, key in ipairs(ns.KNOWN_KEYS) do
        if s:find(key, 1, true) then
            return key, ns.KNOWN[key]
        end
    end
    return nil
end

local function cleanName(text)
    if not text then return nil end
    text = text:gsub("[%(%)%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if text == "" then return nil end
    return (text:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- Icon for a node: the item icon if we know the name, otherwise the type icon.
function ns.NodeIcon(node)
    if node.item then
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(node.item)
        if icon then return icon end
    end
    return ns.TYPES[node.t].icon
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------

local undoStack = {}

local function fillDefaults(settings)
    for k, v in pairs(DEFAULTS) do
        if settings[k] == nil then
            settings[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" then
            for k2, v2 in pairs(v) do
                if settings[k][k2] == nil then settings[k][k2] = v2 end
            end
        end
    end
    return settings
end

local function initDB()
    GatherKingDB = GatherKingDB or {}
    local db = GatherKingDB
    if (db.version or 1) < 3 and db.profiles then
        -- 1.0.1 defaulted minimap markers to 50%; the hollow rings in 1.0.2 look best solid.
        for _, settings in pairs(db.profiles) do
            if settings.minimapAlpha == 0.5 then settings.minimapAlpha = 1 end
        end
    end
    db.version = 3
    db.deleted = db.deleted or {}
    db.itemNames = db.itemNames or {}
    db.ledger = db.ledger or {}
    db.ledger.items = db.ledger.items or {}
    db.ledger.timed = db.ledger.timed or {}
    db.ledger.timer = db.ledger.timer or { running = false, elapsed = 0 }
    db.sync = db.sync or {}
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
    db.ui.buttonAngle = db.ui.buttonAngle or 215
    if db.ui.ledger == nil then db.ui.ledger = true end
    if db.sync.guild == nil then db.sync.guild = true end
    db.nodes = db.nodes or {}
    db.profiles = db.profiles or {}
    if db.settings then -- version 1 had a single settings table
        db.profiles.Default = db.profiles.Default or db.settings
        db.settings = nil
    end
    db.profiles.Default = db.profiles.Default or {}
    for _, settings in pairs(db.profiles) do fillDefaults(settings) end
    if not db.profiles[db.active or ""] then db.active = "Default" end
    ns.db = db
    ns.settingsRef = db.profiles[db.active]
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------

-- ns.S() is the active profile's settings.
function ns.S() return ns.settingsRef end

function ns.ActiveProfile() return ns.db.active end

function ns.ProfileNames()
    local names = {}
    for name in pairs(ns.db.profiles) do table.insert(names, name) end
    table.sort(names, function(a, b)
        if a == "Default" then return true elseif b == "Default" then return false end
        return a:lower() < b:lower()
    end)
    return names
end

local function findProfile(name)
    if not name then return nil end
    for existing in pairs(ns.db.profiles) do
        if existing:lower() == name:lower() then return existing end
    end
end

function ns.UseProfile(name)
    local existing = findProfile(name)
    if not existing then
        ns.Print("No profile named '" .. tostring(name) .. "'. /gt profile new " .. tostring(name) .. " creates it.")
        return false
    end
    ns.db.active = existing
    ns.settingsRef = ns.db.profiles[existing]
    ns.Print("Using profile " .. existing .. ".")
    ns.Refresh()
    if ns.RefreshSettings then ns.RefreshSettings() end
    return true
end

-- New profiles start as a copy of the one you're using.
function ns.NewProfile(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then
        ns.Print("Give the profile a name, e.g. /gt profile new Thorium run")
        return false
    end
    if findProfile(name) then
        return ns.UseProfile(name)
    end
    local copy = CopyTable(ns.S())
    copy.show, copy.record = CopyTable(ns.S().show), CopyTable(ns.S().record)
    ns.db.profiles[name] = copy
    ns.Print("Created profile " .. name .. " (copied from " .. ns.db.active .. ").")
    return ns.UseProfile(name)
end

function ns.DeleteProfile(name)
    local existing = findProfile(name)
    if not existing then
        ns.Print("No profile named '" .. tostring(name) .. "'.")
        return false
    end
    if existing == "Default" then
        ns.Print("The Default profile can't be deleted.")
        return false
    end
    ns.db.profiles[existing] = nil
    ns.Print("Deleted profile " .. existing .. ". Your markers are untouched.")
    if ns.db.active == existing then ns.UseProfile("Default") end
    if ns.RefreshSettings then ns.RefreshSettings() end
    return true
end

-- Does the active profile want this node on the map?
function ns.Visible(node)
    local s = ns.S()
    if not s.show[node.t] then return false end
    if node.from and not s.showShared then return false end
    if not s.only or s.only:match("^%s*$") then return true end
    local name = node.n and node.n:lower()
    if not name then return false end
    for want in s.only:gmatch("[^,]+") do
        want = want:lower():gsub("^%s+", ""):gsub("%s+$", "")
        local key, known = ns.LookupKnown(want)
        if want ~= "" and (name == want or (known and name == known[2]:lower()) or name:find(want, 1, true)) then
            return true
        end
    end
    return false
end

function ns.PlayerPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

local function findNear(mapID, t, x, y)
    local list = ns.db.nodes[mapID]
    if not list then return nil end
    local best, bestD
    for i, node in ipairs(list) do
        if node.t == t then
            local dx, dy = node.x - x, node.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= MERGE_DISTANCE and (not bestD or d < bestD) then
                best, bestD = i, d
            end
        end
    end
    return best
end

-- Deleted spots are remembered so guild sync doesn't bring them back.
local function isDeleted(mapID, t, x, y)
    for _, d in ipairs(ns.db.deleted[mapID] or {}) do
        if d.t == t and math.abs(d.x - x) <= MERGE_DISTANCE and math.abs(d.y - y) <= MERGE_DISTANCE then
            return true
        end
    end
    return false
end

local function forget(mapID, node)
    ns.db.deleted[mapID] = ns.db.deleted[mapID] or {}
    table.insert(ns.db.deleted[mapID], { t = node.t, x = node.x, y = node.y })
end

local function unforget(mapID, node)
    local list = ns.db.deleted[mapID]
    if not list then return end
    for i = #list, 1, -1 do
        local d = list[i]
        if d.t == node.t and d.x == node.x and d.y == node.y then table.remove(list, i) end
    end
    if #list == 0 then ns.db.deleted[mapID] = nil end
end

-- Marking a spot again yourself undoes an earlier delete there.
local function clearDeletedNear(mapID, t, x, y)
    local list = ns.db.deleted[mapID]
    if not list then return end
    for i = #list, 1, -1 do
        local d = list[i]
        if d.t == t and math.abs(d.x - x) <= MERGE_DISTANCE and math.abs(d.y - y) <= MERGE_DISTANCE then
            table.remove(list, i)
        end
    end
    if #list == 0 then ns.db.deleted[mapID] = nil end
end

-- The marker of this type closest to x/y (within merge distance), if any.
function ns.FindNode(mapID, t, x, y)
    local idx = findNear(mapID, t, x, y)
    return idx and ns.db.nodes[mapID][idx]
end

-- Adds a node. Returns the node and a status: "added", "named" or "exists".
-- itemID (optional): icon to use when the name isn't in our known list.
function ns.AddNode(mapID, x, y, t, name, quiet, itemID)
    local key, known = ns.LookupKnown(name)
    local display, item
    if known then
        display, item = known[2], known[3]
    else
        display, item = cleanName(name), itemID
    end

    local list = ns.db.nodes[mapID]
    if not list then
        list = {}
        ns.db.nodes[mapID] = list
    end

    local idx = findNear(mapID, t, x, y)
    if idx then
        local node = list[idx]
        if display and node.n ~= display then
            if node.n then
                node.alt = node.alt or {}
                node.alt[node.n] = true
            end
            node.n, node.item = display, item
            if not quiet then ns.Print("Updated marker to " .. display .. " at " .. fmtCoords(node.x, node.y)) end
            if ns.ShareNode then ns.ShareNode(mapID, node) end
            ns.Refresh()
            return node, "named"
        end
        node.count = (node.count or 1) + 1
        if not quiet then
            ns.Print(ns.TYPES[t].label .. (node.n and (" (" .. node.n .. ")") or "") ..
                " is already marked at " .. fmtCoords(node.x, node.y))
        end
        return node, "exists"
    end

    local node = { t = t, n = display, item = item, x = x, y = y, ts = time(), count = 1 }
    table.insert(list, node)
    clearDeletedNear(mapID, t, x, y)
    if ns.ShareNode then ns.ShareNode(mapID, node) end
    table.insert(undoStack, { kind = "add", mapID = mapID, node = node })
    ns.Print("Added " .. ns.TYPES[t].label .. (display and (": " .. display) or "") ..
        " in " .. ns.MapName(mapID) .. " at " .. fmtCoords(x, y))
    ns.Refresh()
    return node, "added"
end

local function detach(mapID, node)
    local list = ns.db.nodes[mapID]
    if not list then return false end
    for i, n in ipairs(list) do
        if n == node then
            table.remove(list, i)
            if #list == 0 then ns.db.nodes[mapID] = nil end
            forget(mapID, node)
            return true
        end
    end
    return false
end

-- Merges a marker received from a guildmate. Returns true if it was new.
-- No chat message, no undo entry; the caller refreshes the map once per batch.
-- force: an import you chose to paste, so it also restores spots you deleted.
function ns.MergeShared(mapID, t, x, y, name, from, force, itemID)
    if not ns.TYPES[t] then return false end
    if isDeleted(mapID, t, x, y) then
        if not force then return false end
        clearDeletedNear(mapID, t, x, y)
    end
    local list = ns.db.nodes[mapID]
    local idx = list and findNear(mapID, t, x, y)
    if idx then
        local node = list[idx]
        if name and not node.n then
            local _, known = ns.LookupKnown(name)
            node.n = known and known[2] or name
            node.item = known and known[3] or itemID
        end
        return false
    end
    local _, known = ns.LookupKnown(name)
    ns.db.nodes[mapID] = list or {}
    table.insert(ns.db.nodes[mapID], {
        t = t, n = known and known[2] or name, item = known and known[3] or itemID,
        x = x, y = y, ts = time(), count = 1, from = from,
    })
    return true
end

local function describe(node)
    return ns.TYPES[node.t].label .. (node.n and (": " .. node.n) or "")
end

-- Deletes one node. Undo with /gt undo (until you /reload or log out).
function ns.RemoveNode(mapID, node)
    if not detach(mapID, node) then return false end
    table.insert(undoStack, { kind = "remove", items = { { mapID = mapID, node = node } } })
    ns.Print("Deleted " .. describe(node) .. " at " .. fmtCoords(node.x, node.y) .. ". /gt undo brings it back.")
    ns.Refresh()
    return true
end

-- Deletes every node in every zone, optionally only one type.
-- Used by the settings page.
function ns.ClearAll(t)
    local total = 0
    local removed = {}
    for mapID, list in pairs(ns.db.nodes) do
        for i = #list, 1, -1 do
            if not t or list[i].t == t then
                table.insert(removed, 1, { mapID = mapID, node = table.remove(list, i) })
            end
        end
        if #list == 0 then ns.db.nodes[mapID] = nil end
    end
    if #removed == 0 then
        ns.Print("Nothing to delete.")
        return 0
    end
    table.insert(undoStack, { kind = "remove", items = removed })
    ns.Print("Deleted " .. #removed .. " " .. (t and (ns.TYPES[t].label .. " ") or "") .. "marker(s) everywhere. /gt undo brings them back.")
    ns.Refresh()
    return #removed
end

-- Deletes every node in one zone, optionally only one type and/or one name.
function ns.ClearZone(mapID, t, name)
    local list = ns.db.nodes[mapID]
    local removed = {}
    if list then
        for i = #list, 1, -1 do
            local node = list[i]
            if (not t or node.t == t) and (not name or node.n == name) then
                table.remove(list, i)
                table.insert(removed, 1, { mapID = mapID, node = node })
            end
        end
        if #list == 0 then ns.db.nodes[mapID] = nil end
    end
    if #removed == 0 then
        ns.Print("Nothing to delete in " .. ns.MapName(mapID) .. ".")
        return 0
    end
    table.insert(undoStack, { kind = "remove", items = removed })
    local what = name or (t and ns.TYPES[t].label) or "all"
    ns.Print("Deleted " .. #removed .. " " .. what .. " marker(s) in " .. ns.MapName(mapID) .. ". /gt undo brings them back.")
    ns.Refresh()
    return #removed
end

function ns.Undo()
    local last = table.remove(undoStack)
    if not last then
        ns.Print("Nothing to undo.")
        return
    end
    if last.kind == "add" then
        if detach(last.mapID, last.node) then
            ns.Print("Undid adding " .. describe(last.node) .. " at " .. fmtCoords(last.node.x, last.node.y) .. ".")
        else
            return ns.Undo()
        end
    else
        for _, item in ipairs(last.items) do
            unforget(item.mapID, item.node)
            ns.db.nodes[item.mapID] = ns.db.nodes[item.mapID] or {}
            table.insert(ns.db.nodes[item.mapID], item.node)
        end
        ns.Print("Restored " .. #last.items .. " marker(s).")
    end
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Loot stats: what each node gives, combined across the guild
---------------------------------------------------------------------------
-- node.stats = { h = harvests, items = { [itemID] = { n = harvests it dropped in, q = total amount } } }
-- node.guild = { [player] = <their own stats for this node> }
-- Each guildmate's numbers are stored under their name and replaced (never
-- added) when they send an update, so nothing gets counted twice.

function ns.RecordHarvest(mapID, node, loot)
    node.stats = node.stats or { h = 0, items = {} }
    node.stats.h = node.stats.h + 1
    for itemID, qty in pairs(loot) do
        local it = node.stats.items[itemID] or { n = 0, q = 0 }
        it.n, it.q = it.n + 1, it.q + qty
        node.stats.items[itemID] = it
    end
    if ns.ShareStats then ns.ShareStats(mapID, node) end
end

-- Returns total harvests, your harvests, and a list of
-- { id, n, q } sorted by how often each item dropped.
function ns.CombinedStats(node)
    local total, mine = 0, node.stats and node.stats.h or 0
    local byItem = {}
    local function add(st)
        if not st then return end
        total = total + (st.h or 0)
        for id, it in pairs(st.items or {}) do
            local c = byItem[id] or { id = id, n = 0, q = 0 }
            c.n, c.q = c.n + it.n, c.q + it.q
            byItem[id] = c
        end
    end
    add(node.stats)
    for _, st in pairs(node.guild or {}) do add(st) end
    local list = {}
    for _, c in pairs(byItem) do table.insert(list, c) end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
    return total, mine, list
end

function ns.ItemName(id)
    local name = ns.db.itemNames[id] or ns.BONUS_ITEMS[id] or ns.MAT_NAMES[id]
    if not name and C_Item and C_Item.GetItemNameByID then
        name = C_Item.GetItemNameByID(id)
        if name then ns.db.itemNames[id] = name end
    end
    if not name then
        for _, v in pairs(ns.KNOWN) do if v[3] == id then name = v[2] break end end
    end
    return name or ("Item " .. id)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function help()
    ns.Print("commands:")
    print("  /gt mine [name]   e.g. /gt mine thorium   (also herb, fish, treasure)")
    print("  /gt delete nearby   delete the marker closest to you")
    print("  /gt settings      open the settings page (show/hide, size, delete all)")
    print("  /gt undo          undo the last add or delete (until /reload)")
    print("  /gt list          list markers in this zone")
    print("  /gt show|hide <type|all>   e.g. /gt hide fish")
    print("  /gt auto on|off   auto-mark nodes when you harvest them")
    print("  /gt sync on|off   share markers with guildmates who use gather_king (/gt sync now resends)")
    print("  /gt ledger [on|off|reset|timer]   farming ledger box")
    print("  /gt scan          scan auction house prices with Scanner King (auction house must be open)")
    print("  /gt button on|off   show or hide the minimap button")
    print("  /gt only thorium, mithril   only show these names (/gt only all to reset)")
    print("  /gt profile [name|new <name>|delete <name>]   list, switch, create or delete profiles")
    print("  /gt minimap on|off   show markers on the minimap")
    print("  /gt size <8-32>   marker size on the world map")
    print("  /gt opacity <10-100>   how solid minimap markers are (lower lets the real node show through)")
    print("  Right-click a marker for delete options. Shift + right-click deletes it at once.")
end

local function addHere(t, name)
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then
        ns.Print("Can't read your position here (instances and some areas don't report coordinates).")
        return
    end
    ns.AddNode(mapID, x, y, t, name)
end

local function removeNearest()
    local mapID, x, y = ns.PlayerPosition()
    if not mapID or not ns.db.nodes[mapID] then
        ns.Print("No markers in this zone.")
        return
    end
    local best, bestD
    for _, node in ipairs(ns.db.nodes[mapID]) do
        local dx, dy = node.x - x, node.y - y
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = node, d end
    end
    if best and math.sqrt(bestD) <= 0.03 then
        ns.RemoveNode(mapID, best)
    else
        ns.Print("No marker within 3 map units of you.")
    end
end

local function list(filter)
    local mapID = C_Map.GetBestMapForUnit("player")
    local nodes = mapID and ns.db.nodes[mapID]
    if not nodes or #nodes == 0 then
        ns.Print("No markers in this zone.")
        return
    end
    ns.Print(#nodes .. " marker(s) in " .. ns.MapName(mapID) .. ":")
    for _, node in ipairs(nodes) do
        if not filter or node.t == filter then
            print(string.format("  %s%s  %s", ns.TYPES[node.t].label,
                node.n and (" - " .. node.n) or "", fmtCoords(node.x, node.y)))
        end
    end
end

local function setShow(arg, value)
    if arg == "all" or arg == nil or arg == "" then
        for k in pairs(ns.TYPES) do ns.S().show[k] = value end
    else
        local t = ns.ALIAS[arg]
        if not t then
            ns.Print("Unknown type '" .. arg .. "'. Use mine, herb, fish, treasure or all.")
            return
        end
        ns.S().show[t] = value
    end
    ns.Print((value and "Showing " or "Hiding ") .. (ns.ALIAS[arg] and ns.TYPES[ns.ALIAS[arg]].label or "all") .. " markers.")
    ns.Refresh()
end

local function onOff(arg, current)
    if arg == "on" then return true elseif arg == "off" then return false end
    return not current
end

SLASH_GATHERKING1 = "/gt"
SLASH_GATHERKING2 = "/gatherking"
SlashCmdList.GATHERKING = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "help" then
        help()
    elseif ns.ALIAS[cmd] then
        addHere(ns.ALIAS[cmd], rest)
    elseif cmd == "undo" then
        ns.Undo()
    elseif cmd == "remove" or cmd == "delete" or cmd == "del" then
        removeNearest()
    elseif cmd == "config" or cmd == "settings" or cmd == "options" then
        ns.OpenSettings()
    elseif cmd == "profile" or cmd == "profiles" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "" or sub == "list" then
            ns.Print("Profiles (active: " .. ns.db.active .. "): " .. table.concat(ns.ProfileNames(), ", "))
            print("  /gt profile <name>   switch    /gt profile new <name>   create    /gt profile delete <name>")
        elseif sub == "new" or sub == "create" then
            ns.NewProfile(arg)
        elseif sub == "delete" or sub == "remove" then
            ns.DeleteProfile(arg)
        else
            ns.UseProfile(rest)
        end
    elseif cmd == "sync" then
        local arg = rest:lower()
        if arg == "now" then
            ns.SyncNow()
        else
            ns.db.sync.guild = onOff(arg, ns.db.sync.guild)
            ns.Print("Guild sync is " .. (ns.db.sync.guild and "on" or "off") .. ".")
            if ns.db.sync.guild then ns.SyncNow() end
            if ns.RefreshSettings then ns.RefreshSettings() end
        end
    elseif cmd == "ledger" then
        local arg = rest:lower()
        if arg == "reset" then
            ns.LedgerReset()
            ns.Print("Ledger reset.")
        elseif arg == "timer" then
            ns.LedgerToggleTimer()
        else
            ns.db.ui.ledger = onOff(arg, ns.db.ui.ledger)
            ns.UpdateLedger()
            if ns.RefreshSettings then ns.RefreshSettings() end
        end
    elseif cmd == "scan" or cmd == "prices" then
        ns.ScanPrices()
    elseif cmd == "button" then
        ns.db.ui.button = onOff(rest:lower(), ns.db.ui.button)
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
        ns.Print("Minimap button is " .. (ns.db.ui.button and "shown" or "hidden") .. ".")
        if ns.RefreshSettings then ns.RefreshSettings() end
    elseif cmd == "only" then
        if rest == "" or rest:lower() == "all" or rest:lower() == "clear" then
            ns.S().only = ""
            ns.Print("Showing every node name.")
        else
            ns.S().only = rest
            ns.Print("Only showing: " .. rest)
        end
        ns.Refresh()
        if ns.RefreshSettings then ns.RefreshSettings() end
    elseif cmd == "list" then
        list(ns.ALIAS[rest:lower()])
    elseif cmd == "show" then
        setShow(rest:lower(), true)
    elseif cmd == "hide" then
        setShow(rest:lower(), false)
    elseif cmd == "auto" then
        ns.S().auto = onOff(rest:lower(), ns.S().auto)
        ns.Print("Auto-marking on gather is " .. (ns.S().auto and "on" or "off") .. ".")
    elseif cmd == "minimap" then
        ns.S().minimap = onOff(rest:lower(), ns.S().minimap)
        ns.Print("Minimap markers are " .. (ns.S().minimap and "on" or "off") .. ".")
        ns.Refresh()
    elseif cmd == "opacity" or cmd == "alpha" then
        local n = tonumber((rest:gsub("%%", "")))
        if n and n >= 10 and n <= 100 then
            ns.S().minimapAlpha = n / 100
            ns.Print("Minimap marker opacity set to " .. n .. "%.")
            ns.Refresh()
            if ns.RefreshSettings then ns.RefreshSettings() end
        else
            ns.Print("Usage: /gt opacity <10-100>")
        end
    elseif cmd == "size" then
        local n = tonumber(rest)
        if n and n >= 8 and n <= 32 then
            ns.S().size = n
            ns.Print("Marker size set to " .. n .. ".")
            ns.Refresh()
        else
            ns.Print("Usage: /gt size <8-32>")
        end
    else
        -- "/gt thorium" with no type: guess the type from the name.
        local _, known = ns.LookupKnown(msg)
        if known then
            addHere(known[1], msg)
        else
            ns.Print("Unknown command '" .. cmd .. "'.")
            help()
        end
    end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        ns.Refresh()
    end
end)
