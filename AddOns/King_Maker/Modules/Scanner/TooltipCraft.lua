local _, KM = ...
local ns = KM.Module("Scanner")

-- The crafting rows of King Maker's tooltip section (Tooltip.lua lays them out). Everything here is read from the
-- other modules through KM.mods (same addon): Market (recipes, reagent costs, disenchanting), Skillup (your
-- characters' skill and known recipes, skill ranges, patterns), Shopping (lists), Inventory (counts, names).
-- Every function returns nil when a module or the data isn't there, and the caller pcalls it.
--
--   ns.TipBestCrafts(id)  the 3 most valuable things made from it: { { item, value, profit }, ... }
--   ns.TipMake(id)        a crafted end product: cost to make one, the profit after the cut, who can make it
--   ns.TipPattern(id)     a recipe item: what it teaches, who knows it, who can learn it
--   ns.TipDisenchant(id)  what disenchanting one is worth on average
--   ns.TipGoal(id)        on a shopping list: "Favorites: 12 / 20"

local CUT = 0.95
local TOP = 3

local function market() local m = KM.mods.Market; return m and m.db and m.Recipes and m or nil end
local function skillup() local s = KM.mods.Skillup; return s and s.db and s.RECIPES and s or nil end

-- What one sells for: the market price, else the lowest buyout.
local function price(id)
    local pr = ns.db and ns.db.prices[id]
    return pr and (pr.m or pr.p)
end

-- What one recipe costs to make, from reagent prices (the cheaper of the AH and a vendor); nil if one is unpriced.
local function cost(m, r)
    local total = 0
    for i = 1, #(r.reagents or {}), 2 do
        local unit = m.BuyCost(r.reagents[i])
        if not unit then return nil end
        total = total + unit * (r.reagents[i + 1] or 1)
    end
    return total
end

---------------------------------------------------------------------------
-- Indexes over the recipes (rebuilt when the number of recipes changes: a trade skill window added some)
---------------------------------------------------------------------------

local usedBy, madeBy, taught, indexed
local function index(m)
    -- the built-in recipes never change in a session; what trade skill windows add or change lives in db.learned
    local learned = 0
    for _ in pairs(m.db.learned or {}) do learned = learned + 1 end
    if indexed == learned then return end
    indexed = learned
    usedBy, madeBy = {}, {}
    for _, r in ipairs(m.Recipes()) do
        madeBy[r.item] = madeBy[r.item] or {}
        table.insert(madeBy[r.item], r)
        local seen = {}
        for i = 1, #(r.reagents or {}), 2 do
            local reagent = r.reagents[i]
            if reagent and not seen[reagent] then
                seen[reagent] = true
                usedBy[reagent] = usedBy[reagent] or {}
                table.insert(usedBy[reagent], r)
            end
        end
    end
end

local function patternIndex(s)
    if taught then return end
    taught = {}
    for spell, items in pairs(s.PATTERNS or {}) do
        for _, item in ipairs(items) do
            taught[item] = taught[item] or {}
            table.insert(taught[item], spell)
        end
    end
end

---------------------------------------------------------------------------
-- Your characters
---------------------------------------------------------------------------

-- Every character Skillup or Market knows about, with its skill per profession and the recipes it knows.
local function characters()
    local s, m = skillup(), market()
    local out, seen = {}, {}
    local function add(key)
        if seen[key] then return seen[key] end
        local c = { key = key, skills = {}, known = {} }
        seen[key] = c
        out[#out + 1] = c
        return c
    end
    for key, c in pairs(s and s.db.chars or {}) do
        local e = add(key)
        for prof, sk in pairs(c.skills or {}) do e.skills[prof] = sk.cur end
        for spell in pairs(c.known or {}) do e.known[spell] = true end
    end
    for key, c in pairs(m and m.db.chars or {}) do
        local e = add(key)
        for spell in pairs(c.known or {}) do e.known[spell] = true end
    end
    return out
end

local function charName(key)
    local inv = KM.mods.Inventory
    if inv and inv.CharText then
        local ok, text = pcall(inv.CharText, key)
        if ok and text then return text end
    end
    return (key:gsub("%-.*$", ""))
end

-- Can this character make the recipe? It knows it (a trade skill window showed it learned), or it's a trainer
-- recipe and its skill is high enough.
local function canMake(c, r, isPattern)
    if c.known[r.spell] then return true end
    local skill = c.skills[r.prof]
    return not isPattern and skill ~= nil and skill >= (r.skill or 1)
end

local function names(list, max)
    max = max or 3
    local out = {}
    for i = 1, math.min(max, #list) do out[i] = list[i] end
    if #list > max then out[#out + 1] = "+" .. (#list - max) end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------

-- The most valuable things made from this item: { { item, value, profit, made }, ... } (value = what one craft's
-- output sells for), best profit first; recipes whose output has no price aren't ranked.
function ns.TipBestCrafts(id)
    local m = market()
    if not m then return nil end
    index(m)
    local list = usedBy[id]
    if not list then return nil end
    local best, seen = {}, {}
    for _, r in ipairs(list) do
        local each = price(r.item)
        if each and not seen[r.item] then
            seen[r.item] = true
            local value = each * (r.made or 1)
            local c = cost(m, r)
            best[#best + 1] = { item = r.item, value = value, profit = c and (value * CUT - c), made = r.made or 1 }
        end
    end
    table.sort(best, function(a, b)
        if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
        if a.profit and a.profit ~= b.profit then return a.profit > b.profit end
        if a.value ~= b.value then return a.value > b.value end
        return a.item < b.item
    end)
    while #best > TOP do table.remove(best) end
    return #best > 0 and best or nil
end

-- A crafted end product (gear, potions, bags: not a material other recipes use, like leather or bars):
-- { cost = to make one, profit = per one after the cut (nil without a price), who = { names } }.
function ns.TipMake(id)
    local m = market()
    if not m then return nil end
    index(m)
    local list = madeBy[id]
    if not list or usedBy[id] then return nil end
    local s = skillup()
    local cheapest
    for _, r in ipairs(list) do
        local c = cost(m, r)
        if c then
            local each = c / (r.made or 1)
            if not cheapest or each < cheapest then cheapest = each end
        end
    end
    local who = {}
    for _, c in ipairs(characters()) do
        for _, r in ipairs(list) do
            if canMake(c, r, s and s.PATTERNS[r.spell] ~= nil) then who[#who + 1] = charName(c.key) break end
        end
    end
    table.sort(who)
    local each = price(id)
    if not cheapest and #who == 0 then return nil end
    return { cost = cheapest, profit = cheapest and each and (each * CUT - cheapest), who = #who > 0 and names(who) or nil }
end

-- A recipe item: { teaches = "Elixir of Giants", prof = "Alchemy", skill = 245, known = "Jay", can = "Alt (250)" }.
function ns.TipPattern(id)
    local s = skillup()
    if not s then return nil end
    patternIndex(s)
    local spells = taught[id]
    if not spells then return nil end
    local spell = spells[1]
    local r = s.RECIPES[spell]
    if not r then return nil end
    local prof = s.PROF_BY_ID and s.PROF_BY_ID[r[2]]
    local name = r[1] and r[1] > 0 and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r[1])
    if not name and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spell) end
    local out = { teaches = name or ("Recipe " .. spell), prof = prof and prof.name, skill = r[3] }
    local known, can, low = {}, {}, {}
    for _, c in ipairs(characters()) do
        local skill = c.skills[r[2]]
        if c.known[spell] then
            known[#known + 1] = charName(c.key)
        elseif skill then
            if skill >= (r[3] or 1) then can[#can + 1] = charName(c.key) .. " (" .. skill .. ")"
            else low[#low + 1] = charName(c.key) .. " (" .. skill .. ")" end
        end
    end
    out.known = #known > 0 and names(known) or nil
    out.can = #can > 0 and names(can) or nil
    out.low = #low > 0 and names(low) or nil
    return out
end

-- Average value of disenchanting one (Classic's tables, today's prices), or nil.
function ns.TipDisenchant(id)
    local m = market()
    if not (m and m.DisenchantValue) then return nil end
    local v = m.DisenchantValue(id)
    return v and v > 0 and v or nil
end

-- On a shopping list: "Favorites: 12 / 20", "Raid mats: want 20", or just the list's name.
function ns.TipGoal(id)
    if not (ShoppingKing and ShoppingKing.IsWanted) then return nil end
    local list = ShoppingKing.IsWanted(id)
    if not list then return nil end
    local shop = KM.mods.Shopping
    local e = shop and shop.Find and shop.Find(list, id)
    local want = e and e.qty
    if not want then return list end
    local have = InventoryKing and InventoryKing.GetCount and InventoryKing.GetCount(id) or nil
    if have then return list .. ": " .. have .. " / " .. want end
    return list .. ": want " .. want
end
