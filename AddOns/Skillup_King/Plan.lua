local _, ns = ...

-- The skill-up math.
--
-- A recipe gives a skill point:
--   orange  every time (from the skill you learn it at, up to yellow)
--   yellow, green  sometimes: the chance is (grey - skill) / (grey - yellow),
--          so it falls as you near grey (green is just its lower half)
--   grey   never
--
-- One craft costs its materials (the cheaper of the auction house and a vendor)
-- and gives back the best of, as you choose:
--   selling what it makes on the auction house (after the 5% cut),
--   disenchanting it and selling the materials (after the cut),
--   or selling it to a vendor.
-- Net = materials - what you get back. Below zero, the craft makes money.
-- Cost per skill point = net / chance.
--
-- The plan: at each skill from yours to the target, make whatever has the
-- lowest cost per point right there. Points don't depend on each other, so
-- that gives the cheapest expected total. Next to each step: how many crafts
-- (on average), what each costs, and the materials to buy.

function ns.Color(r, skill)
    if skill < r.orange then return nil end
    if skill >= r.grey then return "grey" end
    if skill < r.yellow then return "orange" end
    if skill < r.green then return "yellow" end
    return "green"
end

ns.COLORS = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40", grey = "|cff808080" }

function ns.Chance(r, skill)
    if skill < r.orange then return nil end
    if skill >= r.grey then return 0 end
    if skill < r.yellow then return 1 end
    return (r.grey - skill) / (r.grey - r.yellow)
end

-- Whether a recipe counts: trainer recipes and patterns you know, plus the
-- patterns you lack when you've asked for them.
function ns.Usable(r)
    return ns.HasRecipe(r.spell) or ns.db.ui.lack
end

-- The cheapest listing of a recipe's pattern, when it's taught by one.
function ns.PatternPrice(r)
    local best
    for _, id in ipairs(ns.PATTERNS[r.spell] or {}) do
        local p = ns.AHPrice(id)
        if p and (not best or p < best) then best = p end
    end
    return best
end

local cache = {}
function ns.ClearCache() cache = {} end

-- One craft of a recipe: { cost, missing = reagentID, back, how = "Sell"|"Disenchant"|"Vendor", net, mats }
function ns.Craft(r)
    local c = cache[r.spell]
    if c then return c end
    c = { cost = 0, back = 0, mats = {} }
    for i = 1, #r.reagents, 2 do
        local id, n = r.reagents[i], r.reagents[i + 1]
        local unit, vendor = ns.BuyCost(id)
        table.insert(c.mats, { id = id, n = n, unit = unit, vendor = vendor })
        if unit then c.cost = c.cost + unit * n else c.missing = c.missing or id end
    end
    if r.item ~= 0 then
        local function offer(value, how)
            if value and value > c.back then c.back, c.how = value, how end
        end
        local sell = ns.ItemInfo(r.item).sell
        offer(sell and sell * r.made, "Vendor")
        if ns.db.ui.sell then
            local p, listed = ns.SellPrice(r.item)
            c.listed = listed
            offer(p and p * r.made * ns.CUT, "Sell")
        end
        if ns.db.ui.de then
            local de = ns.DisenchantValue(r.item)
            offer(de and de * r.made * ns.CUT, "Disenchant")
        end
    end
    c.net = c.cost - c.back
    cache[r.spell] = c
    return c
end

-- Every recipe of a profession you could make at this skill, cheapest skill point first:
-- { r, craft, color, chance, perPoint, usable }.
function ns.Options(profID, skill)
    ns.ClearCache()
    local out = {}
    for _, r in ipairs(ns.Recipes()) do
        if r.prof == profID and r.orange <= skill then
            local chance = ns.Chance(r, skill)
            local craft = ns.Craft(r)
            local row = { r = r, craft = craft, color = ns.Color(r, skill), chance = chance, usable = ns.Usable(r),
                          has = ns.HasRecipe(r.spell) }
            if chance > 0 and not craft.missing then row.perPoint = craft.net / chance end
            table.insert(out, row)
        end
    end
    table.sort(out, function(a, b)
        if (a.perPoint ~= nil) ~= (b.perPoint ~= nil) then return a.perPoint ~= nil end
        if a.perPoint and a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
        if (a.chance > 0) ~= (b.chance > 0) then return a.chance > 0 end
        return a.r.orange > b.r.orange
    end)
    return out
end

-- The best recipe at one skill: the recipe, its chance, cost per point.
local function bestAt(recipes, skill)
    local best, bestChance, bestPer
    for _, r in ipairs(recipes) do
        if r.orange <= skill and skill < r.grey and ns.Usable(r) then
            local craft = ns.Craft(r)
            if not craft.missing then
                local chance = ns.Chance(r, skill)
                local per = craft.net / chance
                if not bestPer or per < bestPer - 0.5 or (math.abs(per - bestPer) <= 0.5 and chance > bestChance) then
                    best, bestChance, bestPer = r, chance, per
                end
            end
        end
    end
    return best, bestChance, bestPer
end

-- The plan from one skill to another:
--   { steps = { { from, to, r, crafts, cost, each } or { note }... }, cost, crafts,
--     mats = { { id, n, unit, vendor } }, gaps = number of points nothing priced covers }
function ns.Plan(profID, from, to)
    from = math.max(from or 1, 1)
    to = math.min(to or ns.MAX_SKILL, ns.MAX_SKILL)
    ns.ClearCache()
    local recipes = {}
    for _, r in ipairs(ns.Recipes()) do if r.prof == profID then table.insert(recipes, r) end end
    local plan = { steps = {}, cost = 0, crafts = 0, gaps = 0, mats = {} }
    local step, mats = nil, {}
    local level = ns.Level()
    for skill = from, to - 1 do
        for _, rank in ipairs(ns.RANKS) do
            if rank.cap ~= ns.MAX_SKILL and skill == rank.cap and skill > from then
                local nxt = ns.RANKS[_ + 1]
                local note = "Learn " .. nxt.name .. " from a trainer (skill " .. nxt.cap .. ")"
                if level < nxt.level then note = note .. ": |cffff6060needs level " .. nxt.level .. ", you're " .. level .. "|r" end
                table.insert(plan.steps, { note = note })
                step = nil
            end
        end
        local r, chance = bestAt(recipes, skill)
        if not r then
            plan.gaps = plan.gaps + 1
            if step and step.gap then step.to = skill + 1
            else step = { from = skill, to = skill + 1, gap = true }; table.insert(plan.steps, step) end
        else
            local craft = ns.Craft(r)
            if not (step and step.r == r) then
                step = { from = skill, to = skill + 1, r = r, crafts = 0, cost = 0, each = craft.net, how = craft.how }
                table.insert(plan.steps, step)
            end
            step.to = skill + 1
            step.crafts = step.crafts + 1 / chance
            step.cost = step.cost + craft.net / chance
            plan.cost = plan.cost + craft.net / chance
            plan.crafts = plan.crafts + 1 / chance
            for _, m in ipairs(craft.mats) do
                local t = mats[m.id]
                if not t then t = { id = m.id, n = 0, unit = m.unit, vendor = m.vendor }; mats[m.id] = t end
                t.n = t.n + m.n / chance
            end
        end
    end
    for _, s in ipairs(plan.steps) do
        if s.crafts then s.crafts = math.ceil(s.crafts - 0.05) end
    end
    for _, m in pairs(mats) do
        m.n = math.ceil(m.n - 0.05)
        table.insert(plan.mats, m)
    end
    table.sort(plan.mats, function(a, b) return (a.unit or 0) * a.n > (b.unit or 0) * b.n end)
    return plan
end

-- Where a plan starts: your skill (1 when you haven't learned it).
function ns.StartSkill(profID)
    local cur = ns.Skill(profID)
    return math.max(cur or 0, 1)
end
