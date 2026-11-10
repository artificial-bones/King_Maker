local _, KM = ...
local ns = KM.Module("Shopping")
local API = ns.API

-- Lists. "Favorites" is Econ's favorites (EconKing.IsFavorite / SetFavorite), so a star clicked in Price History
-- and one added here are the same thing; its qty / max / note live in ShoppingKingDB.favMeta. Every other list is
-- ShoppingKingDB.lists[name].items, in the order items were added.

---------------------------------------------------------------------------
-- Favorites (shared with Econ)
---------------------------------------------------------------------------

local function econ() return EconKing and EconKing.IsFavorite and EconKing.SetFavorite and EconKingDB and EconKingDB.fav end

local function favSet()
    if econ() then return EconKingDB.fav end
    return ns.db.fav
end

function ns.IsFavorite(id)
    if econ() then return KM.Safe(EconKing.IsFavorite, id) and true or false end
    return ns.db.fav[id] == true
end

function ns.SetFavorite(id, on)
    if econ() then KM.Safe(EconKing.SetFavorite, id, on) else ns.db.fav[id] = on and true or nil end
    if not on then ns.db.favMeta[id] = nil end
end

local function favEntries()
    local out = {}
    for id, v in pairs(favSet()) do
        if v then
            local m = ns.db.favMeta[id] or {}
            out[#out + 1] = { id = id, qty = m.qty, max = m.max, note = m.note, fav = true }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

local function clean(name)
    name = strtrim and strtrim(name or "") or (name or "")
    name = name:gsub("[:;|]", "")
    if #name > 32 then name = name:sub(1, 32) end
    return name
end
ns.CleanName = clean

function ns.ListNames()
    local out = { ns.FAV }
    for _, name in ipairs(ns.db.order) do out[#out + 1] = name end
    return out
end

function ns.HasList(name) return name == ns.FAV or (ns.db.lists[name] ~= nil) end

-- Case-insensitive lookup of a list name the player typed.
function ns.FindList(text)
    text = clean(text):lower()
    for _, name in ipairs(ns.ListNames()) do if name:lower() == text then return name end end
end

function ns.CreateList(name)
    name = clean(name)
    if name == "" or ns.HasList(name) or ns.FindList(name) then return nil end
    ns.db.lists[name] = { items = {}, created = KM.Now() }
    table.insert(ns.db.order, name)
    ns.Changed()
    return name
end

local function ensure(name)
    if name == nil then name = ns.DEFAULT end
    if name == ns.FAV then return name end
    name = clean(name)
    if name == "" then return nil end
    local found = ns.FindList(name)
    if found then return found end
    return ns.CreateList(name)
end

function ns.RenameList(old, new)
    new = clean(new)
    if old == ns.FAV or not ns.db.lists[old] or new == "" then return false end
    if new ~= old and ns.FindList(new) and ns.FindList(new) ~= old then return false end
    ns.db.lists[new] = ns.db.lists[old]
    if new ~= old then ns.db.lists[old] = nil end
    for i, n in ipairs(ns.db.order) do if n == old then ns.db.order[i] = new end end
    if ns.db.active == old then ns.db.active = new end
    ns.Changed()
    return true
end

function ns.DeleteList(name)
    if name == ns.FAV or not ns.db.lists[name] then return false end
    ns.db.lists[name] = nil
    for i, n in ipairs(ns.db.order) do if n == name then table.remove(ns.db.order, i) break end end
    if ns.db.active == name then ns.db.active = ns.FAV end
    ns.Changed()
    return true
end

-- The live entries of a list (tables you may edit through ns.Update), or nil.
function ns.Entries(name)
    if name == ns.FAV then return favEntries() end
    local l = ns.db.lists[name]
    return l and l.items or nil
end

function ns.Find(name, id)
    if name == ns.FAV then
        if not ns.IsFavorite(id) then return nil end
        local m = ns.db.favMeta[id] or {}
        return { id = id, qty = m.qty, max = m.max, note = m.note, fav = true }
    end
    for _, e in ipairs(ns.Entries(name) or {}) do if e.id == id then return e end end
end

-- Sets fields on an entry: fields = { qty =, max =, note = }; false clears a field.
function ns.Update(name, id, fields)
    local function apply(t)
        for _, k in ipairs({ "qty", "max", "note" }) do
            local v = fields[k]
            if v == false or v == "" then t[k] = nil elseif v ~= nil then t[k] = v end
        end
    end
    if name == ns.FAV then
        if not ns.IsFavorite(id) then return false end
        local m = ns.db.favMeta[id] or {}
        apply(m)
        ns.db.favMeta[id] = next(m) and m or nil
    else
        local e
        for _, x in ipairs(ns.Entries(name) or {}) do if x.id == id then e = x end end
        if not e then return false end
        apply(e)
    end
    ns.Changed()
    return true
end

local function validID(id)
    id = tonumber(id)
    if not id or id <= 0 or id ~= math.floor(id) then return nil end
    return id
end

function ns.AddTo(name, id, qty, max, note)
    id = validID(id)
    name = ensure(name)
    if not id or not name then return false end
    qty = tonumber(qty); max = tonumber(max)
    if qty and qty < 0 then qty = nil end
    if max and max <= 0 then max = nil end
    if name == ns.FAV then
        ns.SetFavorite(id, true)
    else
        local items = ns.db.lists[name].items
        local e
        for _, x in ipairs(items) do if x.id == id then e = x end end
        if not e then e = { id = id }; items[#items + 1] = e end
    end
    local f = {}
    if qty then f.qty = math.floor(qty) end
    if max then f.max = math.floor(max) end
    if note then f.note = note end
    if next(f) then ns.Update(name, id, f) else ns.Changed() end
    return true, name
end

function ns.RemoveFrom(name, id)
    id = validID(id)
    if not id then return false end
    if name == ns.FAV then
        if not ns.IsFavorite(id) then return false end
        ns.SetFavorite(id, false)
        ns.Changed()
        return true
    end
    local items = ns.Entries(name)
    if not items then return false end
    for i, e in ipairs(items) do
        if e.id == id then table.remove(items, i); ns.Changed(); return true end
    end
    return false
end

-- One purchase of n went through: the wanted quantity goes down (never below 0).
function ns.Bought(name, id, n)
    local e = ns.Find(name, id)
    if not e or not e.qty then return end
    ns.Update(name, id, { qty = math.max(0, e.qty - (n or 1)) })
end

-- Every item on every list, once (the scanner prices these).
function ns.AllWanted()
    local seen, out = {}, {}
    for _, name in ipairs(ns.ListNames()) do
        for _, e in ipairs(ns.Entries(name) or {}) do
            if not seen[e.id] then seen[e.id] = true; out[#out + 1] = e.id end
        end
    end
    return out
end

-- Items (counted once) whose lowest price is at or under their max, on any list.
function ns.UnderMaxCount()
    local seen, n = {}, 0
    for _, name in ipairs(ns.ListNames()) do
        for _, e in ipairs(ns.Entries(name) or {}) do
            if not seen[e.id] and ns.Status(e) == "under" then seen[e.id] = true; n = n + 1 end
        end
    end
    return n
end

function ns.Active()
    local a = ns.db.active
    if not ns.HasList(a) then a = ns.FAV; ns.db.active = a end
    return a
end

function ns.SetActive(name)
    if ns.HasList(name) then ns.db.active = name; ns.Changed() end
end

-- Something changed: redraw what shows it.
function ns.Changed()
    if ns.RefreshPanel then ns.RefreshPanel() end
    if KM.Refresh and KM.IsShown and KM.IsShown("shopping") then KM.Refresh("shopping") end
end

---------------------------------------------------------------------------
-- Export / import: "KMS1:<name>:<id>,<qty>,<max>,<note>;..." (empty fields stay empty)
---------------------------------------------------------------------------

local function noteSafe(s) return ((s or ""):gsub("[,;:|]", " ")) end

function ns.Export(name)
    local parts = {}
    for _, e in ipairs(ns.Entries(name) or {}) do
        local row = e.id .. "," .. (e.qty or "") .. "," .. (e.max or "") .. "," .. noteSafe(e.note)
        parts[#parts + 1] = (row:gsub(",+$", ""))
    end
    return "KMS1:" .. clean(name) .. ":" .. table.concat(parts, ";")
end

-- Returns the list name and the number of items added, or nil and why. intoName overrides the code's name.
function ns.Import(code, intoName)
    code = strtrim and strtrim(code or "") or (code or "")
    local name, body = code:match("^KMS1:([^:]*):(.*)$")
    if not name then return nil, "That isn't a King Maker shopping list code (it starts with KMS1:)." end
    name = clean(intoName or name)
    if name == "" then name = "Imported" end
    local rows = {}
    for row in body:gmatch("[^;]+") do
        local f, rest = {}, row
        for _ = 1, 3 do
            local a, b = rest:match("^([^,]*),(.*)$")
            if not a then break end
            f[#f + 1], rest = a, b
        end
        f[#f + 1] = rest
        local id, qty, max, note = f[1], f[2] or "", f[3] or "", f[4]
        id = id and id:match("^%d+$") and validID(id)
        if not id or not qty:match("^%d*$") or not max:match("^%d*$") then
            return nil, "The code is damaged near \"" .. row:sub(1, 20) .. "\"."
        end
        rows[#rows + 1] = { id = id, qty = tonumber(qty), max = tonumber(max), note = (note ~= "" and note or nil) }
    end
    local target = ensure(name)
    if not target then return nil, "Could not make a list called " .. name .. "." end
    for _, r in ipairs(rows) do ns.AddTo(target, r.id, r.qty, r.max, r.note) end
    return target, #rows
end

---------------------------------------------------------------------------
-- Oracle (the player's own addon, optional): its "buy" actions become the list "Oracle"
---------------------------------------------------------------------------

function ns.OracleData()
    if not (Oracle and Oracle.GetData) then return nil end
    local ok, data = pcall(Oracle.GetData)
    if ok and type(data) == "table" then return data end
end

function ns.ImportOracle()
    local data = ns.OracleData()
    if not data then return nil, "Oracle isn't loaded or has no data yet." end
    local buys = {}
    for _, a in ipairs(type(data.actions) == "table" and data.actions or {}) do
        if type(a) == "table" and a.verb == "buy" and tonumber(a.item_id) then buys[#buys + 1] = a end
    end
    if not ns.db.lists[ns.ORACLE] then ns.CreateList(ns.ORACLE) end
    local items = ns.db.lists[ns.ORACLE].items
    for i = #items, 1, -1 do items[i] = nil end
    for _, a in ipairs(buys) do
        local note = type(a.text) == "string" and a.text:sub(1, 60) or nil
        ns.AddTo(ns.ORACLE, tonumber(a.item_id), tonumber(a.qty or a.units), tonumber(a.target), note)
    end
    ns.Changed()
    return ns.ORACLE, #buys
end

---------------------------------------------------------------------------
-- The public API (other modules and addons call these; keep the shapes)
---------------------------------------------------------------------------

function API.Add(itemID, qty, maxPrice, listName)
    if not ns.db then return false end
    local ok = ns.AddTo(listName, itemID, qty, maxPrice)
    return ok and true or false
end

function API.Remove(itemID, listName)
    if not ns.db then return false end
    local name = listName == nil and ns.DEFAULT or (listName == ns.FAV and ns.FAV or ns.FindList(listName))
    if not name then return false end
    return ns.RemoveFrom(name, itemID)
end

function API.Lists()
    if not ns.db then return {} end
    return ns.ListNames()
end

function API.Items(listName)
    if not ns.db then return {} end
    local name = listName == nil and ns.DEFAULT or (listName == ns.FAV and ns.FAV or ns.FindList(listName))
    local out = {}
    for _, e in ipairs(name and ns.Entries(name) or {}) do
        out[#out + 1] = { itemID = e.id, qty = e.qty, max = e.max, note = e.note }
    end
    return out
end

-- The first list (yours first, then Favorites) that has the item and still wants some.
function API.IsWanted(itemID)
    if not ns.db then return nil end
    itemID = tonumber(itemID)
    if not itemID then return nil end
    for _, name in ipairs(ns.db.order) do
        local e = ns.Find(name, itemID)
        if e and not (e.qty and e.qty <= 0) then return name end
    end
    local f = ns.Find(ns.FAV, itemID)
    if f and not (f.qty and f.qty <= 0) then return ns.FAV end
    return nil
end
