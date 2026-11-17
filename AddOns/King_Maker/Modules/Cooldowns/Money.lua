local _, KM = ...
local ns = KM.Module("Cooldowns")

-- Cooldowns: what each cooldown is worth, and the hooks into the Scanner, Shopping and Inventory.
--
-- Same rules as Crafting Profits and the Profession panel (Market.Evaluate, disenchanting off): materials at the
-- cheaper of the lowest auction and a vendor, the product at the lowest auction, 5% auction cut. The headline
-- follows Crafting Profits' mode: "buy" = sale minus materials, "farm" = how much crafting beats selling the
-- materials. Per week = profit each x 7 days / the recipe's cooldown. A shared group (transmutes) ranks its
-- members by profit per day of cooldown, because Arcanite's two days block two days of essences.

local WEEK, DAY = 7 * 86400, 86400
ns.SHOP_LIST = "Cooldown mats"

local function market()
    local m = KM.mods.Market
    return m and m.db and m.Recipe and m.Evaluate and m or nil
end

-- The recipe for a spell: Market's (built-in or seen in your window), or the catalogue's own (the Salt Shaker).
-- { spell, item, prof, skill, reagents = { id, count, ... }, made }
function ns.Recipe(spell)
    local cat = ns.CATALOGUE[spell]
    if cat and cat.recipe then
        local r = cat.recipe
        return { spell = spell, item = r.item, prof = r.prof, skill = r.skill, reagents = r.reagents, made = r.made or 1 }
    end
    local m = market()
    if m then return ns.Call(m.Recipe, spell) end
end

function ns.Product(spell)
    local r = ns.Recipe(spell)
    return r and r.item
end

-- "buy" or "farm", from Crafting Profits.
function ns.Mode()
    local m = market()
    return (m and m.db.mode == "farm") and "farm" or "buy"
end

local function isVendor(id)
    local m = market()
    return m and m.VENDOR_ITEMS and m.VENDOR_ITEMS[id] and true or false
end

-- { spell, item, made, profit (headline, per craft), buyProfit, farmGain, sale, cost, price, listed, missing, mats }
-- or nil when Market isn't loaded or the recipe is unknown. profit is nil until every price is known.
function ns.Value(spell)
    local m, r = market(), ns.Recipe(spell)
    if not (m and r) then return nil end
    local row = ns.Call(m.Evaluate, r, "buy", { noDE = true })
    if type(row) ~= "table" then return nil end
    local v = { spell = spell, item = r.item, made = r.made, sale = row.craftSale, cost = row.cost, price = row.price,
        listed = row.listed, missing = row.missing, mats = row.mats }
    if not row.missing and row.craft then v.buyProfit = row.craft end
    local fr = ns.Call(m.Evaluate, r, "farm", { noDE = true })
    if type(fr) == "table" and not fr.missing then v.farmGain = fr.gain end
    if ns.Mode() == "farm" then v.profit = v.farmGain else v.profit = v.buyProfit end
    return v
end

function ns.PerWeek(profit, dur) return profit and dur and dur > 0 and profit * WEEK / dur or nil end
function ns.PerDay(profit, dur) return profit and dur and dur > 0 and profit * DAY / dur or nil end

-- The members a character knows in a group (every member when it has no entry yet), sorted.
function ns.KnownBy(key, gk)
    local c = ns.db.chars[key]
    local e = c and c.cds[gk]
    local out = {}
    if e then
        for spell in pairs(e.known or {}) do if ns.GroupOf(spell) == gk then out[#out + 1] = spell end end
    end
    if not e then out = ns.Members(gk) end
    table.sort(out)
    return out
end

-- Every member the character knows, valued, best profit per day of cooldown first (unpriced last).
function ns.Choices(key, gk)
    local list = {}
    for _, spell in ipairs(ns.KnownBy(key, gk)) do
        local v = ns.Value(spell) or { spell = spell, item = ns.Product(spell) }
        v.dur = ns.Dur(spell)
        v.perDay, v.perWeek = ns.PerDay(v.profit, v.dur), ns.PerWeek(v.profit, v.dur)
        list[#list + 1] = v
    end
    table.sort(list, function(a, b)
        if (a.perDay ~= nil) ~= (b.perDay ~= nil) then return a.perDay ~= nil end
        if a.perDay and a.perDay ~= b.perDay then return a.perDay > b.perDay end
        return a.spell < b.spell
    end)
    return list
end

-- The member to show: the player's pick if still known, else the best. Returns spell, its value, the choices.
function ns.Pick(key, gk)
    local c = ns.db.chars[key]
    local p = c and c.pick and c.pick[gk]
    local list = ns.Choices(key, gk)
    if p then
        for _, v in ipairs(list) do if v.spell == p then return p, v, list end end
    end
    local v = list[1]
    return v and v.spell, v, list
end

function ns.SetPick(key, gk, spell)
    local c = ns.db.chars[key]
    if not c then return end
    c.pick = c.pick or {}
    local best = ns.Choices(key, gk)[1]
    c.pick[gk] = (best and best.spell ~= spell) and spell or nil   -- the best needs no pick (it follows prices)
    ns.Changed(true)
end

-- Idle since it came ready: seconds, crafts that idling cost, and their gold at today's price.
function ns.Idle(key, gk, now)
    now = now or ns.Now()
    local c = ns.db.chars[key]
    local e = c and c.cds[gk]
    if not (e and e.ready and e.ready <= now) then return 0, 0, 0 end
    local spell, v = ns.Pick(key, gk)
    local dur = ns.Dur(spell or e.spell)
    local secs = now - (e.readySince or e.ready)
    local crafts = secs / dur
    return secs, crafts, (v and v.profit) and crafts * v.profit or nil
end

-- Idle time in the last 7 days (closed intervals plus the open one): seconds, crafts, gold.
function ns.IdleWeek(key, gk, now)
    now = now or ns.Now()
    local c = ns.db.chars[key]
    local e = c and c.cds[gk]
    if not e then return 0, 0, 0 end
    local from = now - WEEK
    local secs = 0
    for _, iv in ipairs(e.idle or {}) do
        local a, b = math.max(iv[1], from), math.min(iv[2], now)
        if b > a then secs = secs + (b - a) end
    end
    if e.ready and e.ready <= now then
        local a = math.max(e.readySince or e.ready, from)
        if now > a then secs = secs + (now - a) end
    end
    local spell, v = ns.Pick(key, gk)
    local crafts = secs / ns.Dur(spell or e.spell)
    return secs, crafts, (v and v.profit and v.profit > 0) and crafts * v.profit or 0
end

-- Crafts in the last 28 days and their share of the most the cooldown allowed; and the last craft's time.
function ns.Pace(key, gk, now)
    now = now or ns.Now()
    local c = ns.db.chars[key]
    if not c then return 0, 0, nil end
    local n, last = 0, nil
    for _, l in ipairs(c.log or {}) do
        if l[2] == gk then
            if l[1] >= now - 28 * DAY then n = n + 1 end
            if not last or l[1] > last then last = l[1] end
        end
    end
    local spell = ns.Pick(key, gk)
    local most = 28 * DAY / ns.Dur(spell or (c.cds[gk] and c.cds[gk].spell) or 0)
    return n, most > 0 and math.min(1, n / most) or 0, last
end

-- Totals for the tiles and Home: { ready, readyHere, readyAlts, next = { key, c, gk, left }, week, groups, chars,
-- idleWeek, idleCrafts, tracked }
function ns.Summary()
    local now = ns.Now()
    local here, alts = ns.ReadyList()
    local s = { ready = #here + #alts, readyHere = #here, readyAlts = #alts, week = 0, groups = 0, chars = 0,
        idleWeek = 0, idleCrafts = 0, tracked = 0, here = here, alts = alts }
    local who = {}
    for key, c in pairs(ns.db.chars) do
        for gk, e in pairs(c.cds or {}) do
            if ns.Group(gk) and not c.hide[gk] then
                s.tracked = s.tracked + 1
                local _, v = ns.Pick(key, gk)
                if v and v.perWeek and v.perWeek > 0 then
                    s.week = s.week + v.perWeek
                    s.groups = s.groups + 1
                    who[key] = true
                end
                if e.ready and e.ready > now and (not s.next or e.ready - now < s.next.left) then
                    s.next = { key = key, c = c, gk = gk, left = e.ready - now }
                end
                local _, crafts, gold = ns.IdleWeek(key, gk, now)
                s.idleWeek = s.idleWeek + (gold or 0)
                if gold and gold > 0 then s.idleCrafts = s.idleCrafts + crafts end
            end
        end
    end
    for _ in pairs(who) do s.chars = s.chars + 1 end
    return s
end

---------------------------------------------------------------------------
-- The Scanner, Shopping and Inventory
---------------------------------------------------------------------------

-- Every product and material of every member any character knows (and the salt's downstream items): the Scanner
-- prices them in every quick scan, ticked on Crafting Profits or not.
function ns.WatchedItems()
    local seen, out = {}, {}
    local function add(id) if id and not seen[id] then seen[id] = true; out[#out + 1] = id end end
    local spells = {}
    for _, c in pairs(ns.db.chars) do
        for _, e in pairs(c.cds or {}) do for spell in pairs(e.known or {}) do spells[spell] = true end end
    end
    local list = {}
    for spell in pairs(spells) do list[#list + 1] = spell end
    table.sort(list)
    for _, spell in ipairs(list) do
        local r = ns.Recipe(spell)
        if r then
            add(r.item)
            for i = 1, #(r.reagents or {}), 2 do
                if not isVendor(r.reagents[i]) then add(r.reagents[i]) end
            end
        end
    end
    if spells[19566] then for _, id in ipairs(ns.DOWNSTREAM) do add(id) end end
    return out
end

local function owned(id)
    if InventoryKing and InventoryKing.GetCount then
        local total = ns.Call(InventoryKing.GetCount, id)
        if type(total) == "number" then
            local mine = C_Item and C_Item.GetItemCount and ns.Call(C_Item.GetItemCount, id, true)
            return math.max(total, type(mine) == "number" and mine or 0)
        end
    end
    if C_Item and C_Item.GetItemCount then return ns.Call(C_Item.GetItemCount, id, true) or 0 end
    return 0
end

-- How many crafts a cooldown allows in the next `days`: one now if ready, then one per length.
function ns.CraftsAhead(e, dur, days, now)
    local horizon = days * DAY
    local wait = (e and e.ready) and math.max(0, e.ready - now) or 0
    if wait > horizon then return 0 end
    return 1 + math.floor((horizon - wait) / dur)
end

-- The Shopping list "Cooldown mats": what your characters (this realm and faction, or just you) need for the next
-- N days of cooldowns, minus what you own anywhere (you can mail it). Vendor materials are left out.
function ns.ShoppingItems()
    if not ns.db then return {} end
    local now, set = ns.Now(), ns.db.settings
    local me = KM.Char()
    local mine = ns.db.chars[me]
    local realm, faction = mine and mine.realm, mine and mine.faction
    local need, why = {}, {}
    for key, c in pairs(ns.db.chars) do
        local inScope
        if set.shopScope == "me" then inScope = key == me
        else inScope = (not realm or c.realm == nil or c.realm == realm) and (not faction or c.faction == nil or c.faction == faction) end
        if inScope then
            for gk, e in pairs(c.cds or {}) do
                local g = ns.Group(gk)
                if g and not c.hide[gk] then
                    local spell, v = ns.Pick(key, gk)
                    local r = spell and v and v.profit and ns.Recipe(spell)
                    if r then
                        local crafts = ns.CraftsAhead(e, ns.Dur(spell), set.days, now)
                        if crafts > 0 then
                            for i = 1, #(r.reagents or {}), 2 do
                                local id, n = r.reagents[i], r.reagents[i + 1] or 1
                                if not isVendor(id) then
                                    need[id] = (need[id] or 0) + n * crafts
                                    why[id] = why[id] or {}
                                    why[id][g.label] = (why[id][g.label] or 0) + crafts
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local m = market()
    local out = {}
    for id, n in pairs(need) do
        local qty = n - (owned(id) or 0)
        if qty > 0 then
            local unit = m and ns.Call(m.BuyCost, id)
            local parts = {}
            for label, k in pairs(why[id]) do parts[#parts + 1] = label .. " x" .. k end
            table.sort(parts)
            out[#out + 1] = { itemID = id, qty = qty, max = unit and math.ceil(unit) or nil, note = table.concat(parts, ", ") }
        end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
end

local shopPending = false
function ns.ShoppingChanged()
    if shopPending or not (ShoppingKing and ShoppingKing.RefreshLists) then return end
    shopPending = true
    C_Timer.After(1, function() shopPending = false; pcall(ShoppingKing.RefreshLists) end)
end

function ns.ShoppingAvailable()
    return type(ShoppingKing) == "table" and type(ShoppingKing.RegisterListProvider) == "function"
end

-- Adds one cooldown's next N days of materials to the saved Shopping list "Crafting" (like the Profession panel's
-- "Add missing to Shopping"). Returns how many items were added.
function ns.AddToShopping(key, gk)
    if not (ShoppingKing and ShoppingKing.Add) then return 0 end
    local spell = ns.Pick(key, gk)
    local r = spell and ns.Recipe(spell)
    local c = ns.db.chars[key]
    if not (r and c) then return 0 end
    local crafts = ns.CraftsAhead(c.cds[gk], ns.Dur(spell), ns.db.settings.days, ns.Now())
    local m, added = market(), 0
    for i = 1, #(r.reagents or {}), 2 do
        local id, n = r.reagents[i], r.reagents[i + 1] or 1
        local qty = n * crafts - (owned(id) or 0)
        if qty > 0 and not isVendor(id) then
            local unit = m and ns.Call(m.BuyCost, id)
            if pcall(ShoppingKing.Add, id, qty, unit and math.ceil(unit) or nil, "Crafting") then added = added + 1 end
        end
    end
    return added
end

local registered = false
function ns.RegisterIntegrations()
    if registered then return end
    registered = true
    if ScannerKing and ScannerKing.Watch then
        pcall(ScannerKing.Watch, "Cooldowns", function() return ns.WatchedItems() end)
    end
    if ScannerKing and ScannerKing.RegisterCallback then
        pcall(ScannerKing.RegisterCallback, "Cooldowns", function(e)
            if e == "PRICES_UPDATED" and KM.IsShown("cooldowns") then KM.Refresh("cooldowns") end
        end)
    end
    if ns.ShoppingAvailable() then
        pcall(ShoppingKing.RegisterListProvider, ns.SHOP_LIST, {
            items = function() return ns.ShoppingItems() end,
            bought = function() ns.ShoppingChanged() end,
            owner = "Cooldowns", note = "Materials for your crafting cooldowns over the next days, less what you own.",
        })
    end
    if InventoryKing and InventoryKing.RegisterCallback then
        pcall(InventoryKing.RegisterCallback, "STOCK", function()
            ns.ShoppingChanged()
            if KM.IsShown("cooldowns") then KM.Refresh("cooldowns") end
        end, "Cooldowns")
    end
end
