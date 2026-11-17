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
            out[#out + 1] = { id = id, qty = m.qty, max = m.max, note = m.note, keep = m.keep, transit = m.transit, fav = true }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

---------------------------------------------------------------------------
-- Virtual lists (ShoppingKing.RegisterListProvider): another addon supplies a list's items live. They show and
-- buy like any list but are never saved, can't be edited, renamed or deleted here, and a purchase is reported back
-- to the provider. With no provider registered (every player without such an addon) nothing here runs.
---------------------------------------------------------------------------

ns.providers, ns.providerOrder = {}, {}

local function provider(name) return name and ns.providers[name] end
ns.Provider = provider

-- Read-only guards the page and the panel ask (instead of "is it Favorites"):
--   IsVirtual  another addon supplies it live;  IsEditable  max / want / note can change (not virtual);
--   IsMine     it can also be renamed and deleted (editable and not Favorites).
function ns.IsVirtual(name) return provider(name) ~= nil end
function ns.IsEditable(name) return name ~= nil and not provider(name) and ns.HasList(name) end
function ns.IsMine(name) return ns.IsEditable(name) and name ~= ns.FAV end

-- Who supplies a live list, and its note: "Oracle", "Cooldowns", or "another addon" when it didn't say.
function ns.ProviderInfo(name)
    local p = provider(name)
    if not p then return nil end
    local owner = type(p.owner) == "string" and p.owner ~= "" and p.owner
        or (name:find("^Oracle") and "Oracle") or "another addon"
    return owner, type(p.note) == "string" and p.note or nil
end

local function virtualEntries(name)
    local p = provider(name)
    local ok, items = pcall(p.items)
    local out = {}
    if ok and type(items) == "table" then
        for _, x in ipairs(items) do
            local id = tonumber(x.itemID or x.id)
            if id then out[#out + 1] = { id = id, qty = tonumber(x.qty), max = tonumber(x.max), note = x.note, virtual = true } end
        end
    end
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
    for _, name in ipairs(ns.db.order) do if not provider(name) then out[#out + 1] = name end end
    for _, name in ipairs(ns.providerOrder) do out[#out + 1] = name end
    return out
end

function ns.HasList(name) return name == ns.FAV or provider(name) ~= nil or (ns.db.lists[name] ~= nil) end

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
    if found and provider(found) then return nil end   -- a virtual list takes no entries
    if found then return found end
    return ns.CreateList(name)
end

function ns.RenameList(old, new)
    new = clean(new)
    if old == ns.FAV or provider(old) or not ns.db.lists[old] or new == "" then return false end
    if new ~= old and ns.FindList(new) and ns.FindList(new) ~= old then return false end
    ns.db.lists[new] = ns.db.lists[old]
    if new ~= old then ns.db.lists[old] = nil end
    for i, n in ipairs(ns.db.order) do if n == old then ns.db.order[i] = new end end
    if ns.db.active == old then ns.db.active = new end
    ns.Changed()
    return true
end

function ns.DeleteList(name)
    if name == ns.FAV or provider(name) or not ns.db.lists[name] then return false end
    ns.db.lists[name] = nil
    for i, n in ipairs(ns.db.order) do if n == name then table.remove(ns.db.order, i) break end end
    if ns.db.active == name then ns.db.active = ns.FAV end
    ns.Changed()
    return true
end

-- The live entries of a list (tables you may edit through ns.Update), or nil.
function ns.Entries(name)
    if name == ns.FAV then return favEntries() end
    if provider(name) then return virtualEntries(name) end
    local l = ns.db.lists[name]
    return l and l.items or nil
end

function ns.Find(name, id)
    if name == ns.FAV then
        if not ns.IsFavorite(id) then return nil end
        local m = ns.db.favMeta[id] or {}
        return { id = id, qty = m.qty, max = m.max, note = m.note, keep = m.keep, transit = m.transit, fav = true }
    end
    for _, e in ipairs(ns.Entries(name) or {}) do if e.id == id then return e end end
end

-- Sets fields on an entry: fields = { qty =, max =, note =, keep =, transit = }; false clears a field.
function ns.Update(name, id, fields)
    local function apply(t)
        for _, k in ipairs({ "qty", "max", "note", "keep", "transit" }) do
            local v = fields[k]
            if v == false or v == "" then t[k] = nil elseif v ~= nil then t[k] = v end
        end
    end
    if name == ns.FAV then
        if not ns.IsFavorite(id) then return false end
        local m = ns.db.favMeta[id] or {}
        apply(m)
        ns.db.favMeta[id] = next(m) and m or nil
    elseif provider(name) then
        return false
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
    if not id or provider(name) then return false end
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

-- One purchase of n went through: the wanted quantity goes down (never below 0). A Keep entry doesn't count down
-- (owning them is what lowers its need): the purchase is noted as on its way until the count shows it.
function ns.Bought(name, id, n)
    local p = provider(name)
    if p then
        if p.bought then pcall(p.bought, id, n or 1) end
        ns.Changed()
        return
    end
    local e = ns.Find(name, id)
    if not e then return end
    if tonumber(e.keep) then
        local owned = ns.OwnHere(id) or 0
        local left = ns.TransitLeft(e, owned)
        -- still waiting on an earlier purchase: add to it (what has arrived of it already shows in owned)
        local tr = left > 0 and { n = left + (n or 1), own = owned, t = KM.Now() } or { n = n or 1, own = owned, t = KM.Now() }
        ns.Update(name, id, { transit = tr })
        return
    end
    if not e.qty then return end
    ns.Update(name, id, { qty = math.max(0, e.qty - (n or 1)) })
end

-- Buy n (keep = nil) or Keep n in stock (keep = n): switching clears what the other mode kept.
function ns.SetKeep(name, id, n)
    n = tonumber(n)
    if n and n > 0 then return ns.Update(name, id, { keep = math.floor(n), qty = false, transit = false }) end
    return ns.Update(name, id, { keep = false, transit = false })
end

-- Is any of your own lists' items in Keep mode? (Bag changes then move the badge.)
function ns.HasKeep()
    for _, name in ipairs(ns.ListNames()) do
        if not provider(name) then
            for _, e in ipairs(ns.Entries(name) or {}) do if e.keep then return true end end
        end
    end
    return false
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

-- A list's totals: { items, deals, dealsCost, dealsSave, fillMax (what everything not done costs at your max),
--   over, noMax (not done, with neither a max of its own nor a market price), noPrice, done, ownMax (every item has
--   its own max), virtual, owner, dealRows = { row, ... } }. seen (optional) skips items counted already.
function ns.Summary(name, seen)
    local s = { items = 0, deals = 0, dealsCost = 0, dealsSave = 0, fillMax = 0, over = 0, noMax = 0, noPrice = 0,
        done = 0, ownMax = true, virtual = ns.IsVirtual(name), owner = ns.ProviderInfo(name), dealRows = {} }
    for _, e in ipairs(ns.Entries(name) or {}) do
        if not (seen and seen[e.id]) then
            if seen then seen[e.id] = true end
            local r = ns.Row(e, true)
            r.list = name
            s.items = s.items + 1
            if not e.max then s.ownMax = false end
            if r.status == "under" then
                s.deals = s.deals + 1
                s.dealsCost = s.dealsCost + (r.cost or 0)
                s.dealsSave = s.dealsSave + (r.save or 0)
                s.dealRows[#s.dealRows + 1] = r
            elseif r.status == "over" then s.over = s.over + 1
            elseif r.status == "noprice" then s.noPrice = s.noPrice + 1
            elseif r.status == "done" then s.done = s.done + 1 end
            if r.status ~= "done" then
                if r.costMax then s.fillMax = s.fillMax + r.costMax else s.noMax = s.noMax + 1 end
            end
        end
    end
    return s
end

-- The same over every list, each item once (the first list that has it counts it, like AllWanted). perList holds
-- { name, deals, dealsCost } for each list with a deal (the hover tooltips).
function ns.AllSummary()
    local seen = {}
    local all = { items = 0, deals = 0, dealsCost = 0, dealsSave = 0, fillMax = 0, over = 0, noMax = 0, noPrice = 0,
        done = 0, dealRows = {}, perList = {} }
    for _, name in ipairs(ns.ListNames()) do
        local s = ns.Summary(name, seen)
        for _, k in ipairs({ "items", "deals", "dealsCost", "dealsSave", "fillMax", "over", "noMax", "noPrice", "done" }) do
            all[k] = all[k] + s[k]
        end
        for _, r in ipairs(s.dealRows) do all.dealRows[#all.dealRows + 1] = r end
        if s.deals > 0 then all.perList[#all.perList + 1] = { name = name, deals = s.deals, dealsCost = s.dealsCost } end
    end
    return all
end

-- Items (counted once) whose lowest price is at or under their max, on any list.
function ns.UnderMaxCount() return ns.AllSummary().deals end

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
    if KM.RefreshBadges then KM.RefreshBadges() end
end

---------------------------------------------------------------------------
-- Export / import: "KMS1:<name>:<id>,<qty>,<max>,<note>,<keep>;..." (empty fields stay empty; trailing ones are
-- left off, so a list with no Keep items reads exactly as before 2.6.2; a note never holds a comma)
---------------------------------------------------------------------------

local function noteSafe(s) return ((s or ""):gsub("[,;:|]", " ")) end

function ns.Export(name)
    local parts = {}
    for _, e in ipairs(ns.Entries(name) or {}) do
        local row = e.id .. "," .. (e.qty or "") .. "," .. (e.max or "") .. "," .. noteSafe(e.note) .. "," .. (e.keep or "")
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
        for _ = 1, 4 do
            local a, b = rest:match("^([^,]*),(.*)$")
            if not a then break end
            f[#f + 1], rest = a, b
        end
        f[#f + 1] = rest
        local id, qty, max, note, keep = f[1], f[2] or "", f[3] or "", f[4], f[5] or ""
        id = id and id:match("^%d+$") and validID(id)
        if not id or not qty:match("^%d*$") or not max:match("^%d*$") or not keep:match("^%d*$") then
            return nil, "The code is damaged near \"" .. row:sub(1, 20) .. "\"."
        end
        rows[#rows + 1] = { id = id, qty = tonumber(qty), max = tonumber(max), note = (note ~= "" and note or nil), keep = tonumber(keep) }
    end
    local target = ensure(name)
    if not target then return nil, "Could not make a list called " .. name .. "." end
    for _, r in ipairs(rows) do
        ns.AddTo(target, r.id, r.qty, r.max, r.note)
        if r.keep and r.keep > 0 then ns.SetKeep(target, r.id, r.keep) end
    end
    return target, #rows
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

-- A list another addon supplies live (never saved): provider = { items = fn() -> { { itemID, qty, max, note } },
-- bought = fn(itemID, n) (optional), owner = "Oracle" (optional: the page says "Live list from Oracle"),
-- note = "..." (optional: shown under it) }. A saved list of the same name stays saved but hidden while the provider
-- is registered. Returns true when registered. Call ShoppingKing.RefreshLists() when the items change.
function API.RegisterListProvider(name, p)
    if not ns.db or type(p) ~= "table" or type(p.items) ~= "function" then return false end
    name = clean(name)
    if name == "" or name == ns.FAV or name == ns.DEFAULT or name == ns.ORACLE then return false end
    if not ns.providers[name] then table.insert(ns.providerOrder, name) end
    ns.providers[name] = p
    ns.Changed()
    return true
end

function API.UnregisterListProvider(name)
    if not ns.providers[name] then return false end
    ns.providers[name] = nil
    for i, n in ipairs(ns.providerOrder) do if n == name then table.remove(ns.providerOrder, i) break end end
    ns.Changed()
    return true
end

function API.RefreshLists() if ns.db then ns.Changed() end end

function API.Lists()
    if not ns.db then return {} end
    return ns.ListNames()
end

function API.Items(listName)
    if not ns.db then return {} end
    local name = listName == nil and ns.DEFAULT or (listName == ns.FAV and ns.FAV or ns.FindList(listName))
    local out = {}
    for _, e in ipairs(name and ns.Entries(name) or {}) do
        -- keep (2.6.2): "Keep this many in stock"; then qty is how many to buy right now (what's missing)
        local need = ns.KeepNeed(e)
        out[#out + 1] = { itemID = e.id, qty = need or e.qty, max = e.max, note = e.note, keep = need and tonumber(e.keep) or nil }
    end
    return out
end

-- The first list (yours first, then Favorites) that has the item and still wants some.
function API.IsWanted(itemID)
    if not ns.db then return nil end
    itemID = tonumber(itemID)
    if not itemID then return nil end
    for _, name in ipairs(ns.db.order) do
        local e = not provider(name) and ns.Find(name, itemID)
        if e and ns.StillWanted(e) then return name end
    end
    for _, name in ipairs(ns.providerOrder) do
        local e = ns.Find(name, itemID)
        if e and ns.StillWanted(e) then return name end
    end
    local f = ns.Find(ns.FAV, itemID)
    if f and ns.StillWanted(f) then return ns.FAV end
    return nil
end
