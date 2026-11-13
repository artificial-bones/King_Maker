local _, KM = ...
local ns = KM.Module("Profession")

-- The numbers behind the panel. Everything comes from the other modules' public data:
--   Market (recipes, prices, ns.Evaluate / ns.Rank: the same math as Crafting Profits), Skillup (colours, chance,
--   SkillupKing.Plan), ScannerKing (prices), EconKing (averages, trend, history, favorites), InventoryKing (counts).
-- Market and Skillup have no public global, so their module namespaces are read through KM.mods (same addon).

local CUT = 0.95
ns.CUT = CUT
local call = ns.Call

local function market() local m = KM.mods.Market; return m and m.db and m.Evaluate and m or nil end
local function skillup() local s = KM.mods.Skillup; return s and s.db and s.Recipes and s or nil end

---------------------------------------------------------------------------
-- Items, professions, recipes
---------------------------------------------------------------------------

function ns.ItemInfo(id)
    if not id then return {} end
    local get = C_Item and C_Item.GetItemInfo
    local name, _, q, _, _, _, _, _, _, icon
    if get then name, _, q, _, _, _, _, _, _, icon = call(get, id) end
    if not icon and C_Item and C_Item.GetItemIconByID then icon = call(C_Item.GetItemIconByID, id) end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
    return { name = name, q = q, icon = icon }
end

function ns.ItemText(id, fallback)
    local i = ns.ItemInfo(id)
    local hex = KM.UI.QUALITY[i.q or 1] or "ffffff"
    return "|cff" .. hex .. (i.name or fallback or ("Item " .. tostring(id))) .. "|r"
end

local function spellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then return call(C_Spell.GetSpellName, id) end
end

-- "Blacksmithing" (or "Classic Blacksmithing", "Mining") -> Market's profession id.
function ns.ProfID(name)
    local m = market()
    if not (m and name) then return nil end
    local p = m.PROF_BY_NAME[name]
    if p then return p.id end
    for pname, prof in pairs(m.PROF_BY_NAME) do
        if name:find(pname, 1, true) then return prof.id end
    end
end

function ns.ProfName(id)
    local m = market()
    local p = m and m.PROF_BY_ID[id]
    return p and p.name
end

-- Market's recipe for a spell: { spell, item, prof, skill, reagents, made } or nil.
function ns.MarketRecipe(spell)
    local m = market()
    if not (m and spell) then return nil end
    local r = m.RECIPES[spell] or m.db.learned[spell]
    if not r then return nil end
    return { spell = spell, item = r[1], prof = r[2], skill = r[3] or 0, reagents = r[4], made = r[5] or 1 }
end

-- The recipe spells that make an item in a profession (built once from Market's data).
local byItem
function ns.SpellForItem(profID, item)
    local m = market()
    if not (m and item) then return nil end
    if not byItem then
        byItem = {}
        for spell, r in pairs(m.RECIPES) do
            local key = r[2] .. ":" .. r[1]
            if not byItem[key] or spell < byItem[key] then byItem[key] = spell end
        end
    end
    if profID and byItem[profID .. ":" .. item] then return byItem[profID .. ":" .. item] end
    for spell, r in pairs(m.db.learned) do
        if r[1] == item and (not profID or r[2] == profID) then return spell end
    end
    if not profID then
        for key, spell in pairs(byItem) do
            if key:match(":(%d+)$") == tostring(item) then return spell end
        end
    end
end

-- Skillup's recipe for a spell (colours), or nil.
local bySpell, bySpellList
function ns.SkillRecipe(spell)
    local s = skillup()
    if not (s and spell) then return nil end
    local list = s.Recipes()
    if bySpellList ~= list then
        bySpell, bySpellList = {}, list
        for _, r in ipairs(list) do bySpell[r.spell] = r end
    end
    return bySpell[spell]
end

---------------------------------------------------------------------------
-- What you own
---------------------------------------------------------------------------

local function charKey() return KM.Char() end -- "First Last-Realm", Inventory's key

local function bagCount(id)
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local n = 0
    for bag = 0, 4 do
        for slot = 1, call(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id then n = n + (info.stackCount or 1) end
        end
    end
    return n
end

-- This character's count (bags and bank when the client says so) and the count on every character.
function ns.Owned(id)
    local mine
    if C_Item and C_Item.GetItemCount then mine = call(C_Item.GetItemCount, id, true) end
    local total, by
    if InventoryKing and InventoryKing.GetCount then total, by = call(InventoryKing.GetCount, id) end
    if mine == nil and type(by) == "table" then mine = by[charKey()] end
    if mine == nil then mine = bagCount(id) end
    mine = mine or 0
    return mine, math.max(total or 0, mine)
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- What one reagent costs: Market's rule (the cheaper of the lowest listing and a vendor), and whether a vendor sells it.
function ns.UnitCost(id)
    local m = market()
    if m then return m.BuyCost(id) end
    if ScannerKing and ScannerKing.GetPrice then return (ScannerKing.GetPrice(id)), false end
end

local function marketOpts()
    local m = market()
    local d = m and m.db or {}
    return { noDE = not d.includeDE and not d.deOnly, deOnly = d.deOnly, noProcs = d.deOnly and d.deNoProcs }
end
ns.MarketOpts = marketOpts

-- Market's verdict for an evaluated row: "craft", "disenchant", "sellraw", "skip" or "noprice".
function ns.Verdict(row, mode)
    if not row then return nil end
    if row.missing or (not row.craft and not row.de) then return "noprice" end
    if row.best == "craft" then return "craft" end
    if row.best == "de" then return "disenchant" end
    return mode == "farm" and "sellraw" or "skip"
end

ns.VERDICTS = {
    craft = { "CRAFT", "violet" }, disenchant = { "DISENCHANT", "info" }, sellraw = { "SELL RAW", "good" },
    skip = { "SKIP", "bad" }, noprice = { "NO PRICE", "dim" },
}

---------------------------------------------------------------------------
-- The selection and its card
---------------------------------------------------------------------------

-- A selection built from the recipe data (Best now clicks), not the game's window.
function ns.SelectionFromSpell(spell)
    local r = ns.MarketRecipe(spell)
    local sr = ns.SkillRecipe(spell)
    if not r and not sr then return nil end
    local a = ns.Active()
    local sel = { key = "p:" .. spell, source = "data", spell = spell, item = (r and r.item) or (sr and sr.item ~= 0 and sr.item) or nil,
        made = (r and r.made) or (sr and sr.made) or 1, reagents = (r and r.reagents) or sr.reagents, have = {} }
    sel.prof = (r and r.prof) or (sr and sr.prof)
    if a and a.profession then sel.profName, sel.skill, sel.maxSkill = a.profession() end
    return sel
end

-- What the panel shows now: a recipe picked in Best now, else the window's selection.
function ns.Selection()
    if ns.pinned then return ns.pinned end
    local a = ns.Active()
    if a then return a:read() end
end

-- Your skill in a profession: the open window's, else what Skillup saw last.
function ns.SkillFor(sel, profID)
    if sel and sel.skill and sel.skill > 0 then return sel.skill, sel.maxSkill end
    local s = skillup()
    if s and profID then
        local cur, max = s.Skill(profID)
        if cur and cur > 0 then return cur, max end
    end
    return nil
end

-- Every number for one selection:
--   spell, item, name, q, icon, prof, made, crafts, skill, color, chance
--   mats = { { id, count, need, have, alts, unit, vendor, line } }, cost (one craft), costAll (crafts), missingPrice
--   market, lowest, listed, avg30, trend7, history = { values }
--   buy, farm (Market rows), verdict = { buy, farm }, profit (one craft, after the cut), de, deSale
function ns.Card(sel, opts)
    if not sel then return nil end
    opts = opts or {}
    local m = market()
    -- Classic's trade skill list names the item, not always the recipe spell: find it in the data
    if not sel.spell and sel.item then sel.spell = ns.SpellForItem(sel.prof or ns.ProfID(sel.profName), sel.item) end
    local mr = ns.MarketRecipe(sel.spell)
    local profID = sel.prof or ns.ProfID(sel.profName) or (mr and mr.prof)
    local reagents = (sel.reagents and #sel.reagents > 0) and sel.reagents or (mr and mr.reagents) or {}
    local c = { spell = sel.spell, item = sel.item or (mr and mr.item), prof = profID, made = sel.made or (mr and mr.made) or 1,
        crafts = math.max(1, ns.db and ns.db.crafts or 1), mats = {}, cost = 0, source = sel.source, key = sel.key }
    if c.item then
        local info = ns.ItemInfo(c.item)
        c.name, c.q, c.icon = info.name or sel.name, info.q, info.icon or sel.icon
    else
        c.name, c.icon = sel.name or spellName(sel.spell), sel.icon
    end
    c.name = c.name or (sel.spell and ("Recipe " .. sel.spell)) or "?"

    -- reagents
    for i = 1, #reagents, 2 do
        local id, count = reagents[i], reagents[i + 1] or 1
        local unit, vendor = ns.UnitCost(id)
        local have, total = ns.Owned(id)
        if sel.have and sel.have[id] then have = sel.have[id]; total = math.max(total or 0, have) end
        local need = count * c.crafts
        local mat = { id = id, count = count, need = need, have = have, alts = math.max(0, (total or have) - have),
            unit = unit, vendor = vendor, line = unit and unit * need }
        table.insert(c.mats, mat)
        if unit then c.cost = c.cost + unit * count else c.missingPrice = c.missingPrice or id end
    end
    c.costAll = c.cost * c.crafts

    -- skill-up colour and chance
    local skill = ns.SkillFor(sel, profID)
    c.skill = skill
    local sr = ns.SkillRecipe(sel.spell)
    local s = skillup()
    if sr and s and skill then
        c.color, c.chance = s.Color(sr, skill), s.Chance(sr, skill)
        c.grey = sr.grey
    end
    -- The game's own colour wins (Forever may have moved a recipe); Skillup's chance only when the colours agree.
    if sel.difficulty and sel.difficulty ~= c.color then
        c.color = sel.difficulty
        c.chance = (sel.difficulty == "orange" and 1) or (sel.difficulty == "grey" and 0) or nil
        c.grey = nil
    end

    -- what it sells for
    if c.item then
        if ScannerKing and ScannerKing.GetPrice then
            local low, _, listed = ScannerKing.GetPrice(c.item)
            c.lowest, c.listed = low, listed
            local mp, _, _, real = ScannerKing.GetMarketPrice(c.item)
            c.market, c.marketReal = mp, real
        end
        local st = EconKing and EconKing.GetStats and call(EconKing.GetStats, c.item)
        if type(st) == "table" then
            c.avg30, c.trend7 = st.avg30, st.trend7
            c.market = c.market or st.market
        end
        if not opts.noHistory and EconKing and EconKing.GetHistory then
            local h = call(EconKing.GetHistory, c.item) or {}
            local vals = {}
            for i = math.max(1, #h - 29), #h do
                local v = h[i]
                local p = v and (v[2] or v[3])
                if p then vals[#vals + 1] = p end
            end
            c.history = vals
        end
        if m then
            local r = { spell = sel.spell or 0, item = c.item, prof = profID, skill = (mr and mr.skill) or 0, reagents = reagents, made = c.made }
            local mo = marketOpts()
            c.buy = m.Evaluate(r, "buy", mo)
            c.farm = m.Evaluate(r, "farm", mo)
            c.verdict = { buy = ns.Verdict(c.buy, "buy"), farm = ns.Verdict(c.farm, "farm") }
            c.profit = c.buy.craft
            c.sale = c.buy.craftSale
            c.de, c.deSale = c.buy.deEach, c.buy.deSale
        end
    end
    return c
end

-- The headline number for the chosen mode: buy = craft sale minus materials; farm = how much crafting beats selling raw.
function ns.Headline(c, mode)
    if not c then return nil end
    mode = mode or ns.Mode()
    if mode == "farm" then return c.farm and c.farm.gain, "farm" end
    return c.buy and (c.buy.gain or c.buy.craft), "buy"
end

---------------------------------------------------------------------------
-- Shopping
---------------------------------------------------------------------------

-- What you're short of for the card's crafts: auction house items, and vendor items (bought from a vendor instead).
function ns.Missing(c)
    local ah, vendor = {}, {}
    for _, m in ipairs(c and c.mats or {}) do
        local short = m.need - (m.have or 0)
        if short > 0 then
            table.insert(m.vendor and vendor or ah, { id = m.id, n = short, unit = m.unit })
        end
    end
    return ah, vendor
end

function ns.ShoppingAvailable()
    return type(ShoppingKing) == "table" and type(ShoppingKing.Add) == "function"
end

-- Adds the missing auction house materials to the Shopping list "Crafting". Returns items added, vendor items skipped.
function ns.AddMissing(c)
    if not ns.ShoppingAvailable() then return 0, {} end
    local ah, vendor = ns.Missing(c)
    local added = 0
    for _, m in ipairs(ah) do
        local ok = pcall(ShoppingKing.Add, m.id, m.n, m.unit and math.ceil(m.unit) or nil, "Crafting")
        if ok then added = added + 1 end
    end
    return added, vendor
end

---------------------------------------------------------------------------
-- Best now: top crafts for this profession, and the next skill-ups
---------------------------------------------------------------------------

-- How many to craft to sell without flooding the auction house: a quarter of what's listed now, and no more than one
-- day of units leaving it (gone per day counts sales, cancels and expiries, so it overstates sales). Nothing listed:
-- 1, to test the market. Returns listed, make, gone per day (nil when the item has never been scanned).
ns.BATCH_SHARE = 0.25
function ns.Batch(item)
    if not (item and ScannerKing and ScannerKing.GetPrice) then return nil end
    local _, _, listed = ScannerKing.GetPrice(item)
    if not listed then return nil end
    if listed <= 0 then return 0, 1, nil end
    local make = math.ceil(listed * ns.BATCH_SHARE)
    local st = EconKing and EconKing.GetStats and call(EconKing.GetStats, item)
    local gone = st and st.gonePerDay
    if gone then make = math.min(make, math.floor(gone)) end
    return listed, math.max(1, make), gone
end

function ns.BestCrafts(profID, limit)
    local m = market()
    if not (m and profID) then return {} end
    local mode = ns.Mode()
    local opts = marketOpts()
    opts.recipes = "mine"
    local ok, rows = pcall(m.Rank, profID, mode, opts)
    local out = {}
    for _, row in ipairs(ok and rows or {}) do
        if row.gain then
            local r = { spell = row.recipe.spell, item = row.item, gain = row.gain, verdict = ns.Verdict(row, mode), row = row }
            if r.verdict == "craft" then r.listed, r.make, r.gone = ns.Batch(row.item) end
            out[#out + 1] = r
            if #out >= (limit or 12) then break end
        end
    end
    return out
end

function ns.NextSkillups(profID, skill, maxSkill, limit)
    if not (SkillupKing and SkillupKing.Plan and profID) then return {} end
    local from = math.max(skill or 1, 1)
    local to = (maxSkill and maxSkill > from) and maxSkill or 300
    if to <= from then return {} end
    local ok, steps = pcall(SkillupKing.Plan, profID, from, to)
    local out = {}
    for _, st in ipairs(ok and steps or {}) do
        if st.r then
            out[#out + 1] = { from = st.from, to = st.to, spell = st.r.spell, item = st.r.item ~= 0 and st.r.item or nil,
                crafts = st.crafts, cost = st.cost }
        elseif st.note then
            out[#out + 1] = { note = st.note }
        end
        if #out >= (limit or 8) then break end
    end
    return out
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------

function ns.TooltipLines(kind, id)
    local a = ns.Active()
    if not a then return nil end
    local profName = a.profession and select(1, a.profession())
    local profID = ns.ProfID(profName)
    local spell
    if kind == "spell" then
        if ns.MarketRecipe(id) or ns.SkillRecipe(id) then spell = id end
    else
        local cur = ns.Selection()
        if cur and cur.item == id and cur.spell then spell = cur.spell end
        spell = spell or ns.SpellForItem(profID, id)
    end
    if not spell then return nil end
    local sel = ns.SelectionFromSpell(spell)
    if not sel then return nil end
    local saved = ns.db.crafts
    ns.db.crafts = 1
    local ok, c = pcall(ns.Card, sel, { noHistory = true })
    ns.db.crafts = saved
    if not ok or not c then return nil end
    local lines = {}
    local gold = "|cff" .. KM.COLOR
    local head, mode = ns.Headline(c)
    local parts = { "cost " .. (c.missingPrice and "?" or KM.Money(c.cost)) }
    if head then parts[#parts + 1] = (mode == "farm" and "vs raw " or "profit ") .. KM.Money(head) end
    local v = c.verdict and c.verdict[mode]
    if v and ns.VERDICTS[v] then parts[#parts + 1] = ns.VERDICTS[v][1]:lower() end
    lines[1] = gold .. "King Maker|r " .. table.concat(parts, ", ")
    if c.color then
        local Sk = KM.mods.Skillup
        local hex = (Sk and Sk.COLORS and Sk.COLORS[c.color]) or "|cffffffff"
        lines[2] = gold .. "Skill-up|r " .. hex .. c.color .. "|r" .. (c.chance and (" " .. math.floor(c.chance * 100 + 0.5) .. "%") or "")
    end
    return lines
end
