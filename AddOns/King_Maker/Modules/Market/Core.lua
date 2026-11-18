local _, KM = ...
local ns = KM.Module("Market", { title = "Market King", short = "Market", legacy = "Market_King", db = "MarketKingDB" })

-- Market King: for the professions you pick, prices every craftable item and
-- everything that goes into it (through the Scanner), then works out the
-- best thing to do with your materials:
--   * sell the raw materials,
--   * craft the item and sell it, or
--   * craft it, disenchant it and sell the enchanting materials.
-- Two ways to count: "Buy mats" (you buy the materials, so they're a cost:
-- flips) or "Use my mats" (you already have them, so the question is whether
-- crafting beats just selling them). Saved as db.mode "buy" / "farm".
-- It also keeps each character's profession skills (2.9: moved in from the removed Skill-ups module), which
-- the crown's tooltip, Cooldowns, the profession panel and the item tooltip's "who can make it" read.
--
-- In King Maker it has no window or minimap button of its own: the ranked list is the "crafting" page
-- (Crafting > Crafting Profits, UI.lua), opened from the crown's quick actions, /mk or /km crafting. Market
-- It stays a Scanner scan provider (Events.lua): the Scanner's one Scan prices the ticked professions.

ns.AH_CUT = 0.05 -- the auction house keeps 5% of every sale

-- Professions, in the order they're shown. id matches Data/Recipes.lua.
ns.PROFESSIONS = {
    { id = 4, key = "alch", name = "Alchemy", short = "Alch" },
    { id = 2, key = "bs", name = "Blacksmithing", short = "Smith" },
    { id = 6, key = "cook", name = "Cooking", short = "Cook" },
    { id = 10, key = "ench", name = "Enchanting", short = "Ench" },
    { id = 9, key = "eng", name = "Engineering", short = "Eng" },
    { id = 1, key = "fa", name = "First Aid", short = "First Aid" },
    { id = 3, key = "lw", name = "Leatherworking", short = "Leather" },
    { id = 7, key = "smelt", name = "Smelting", short = "Smelt" },
    { id = 8, key = "tail", name = "Tailoring", short = "Tailor" },
}
ns.PROF_BY_ID, ns.PROF_BY_NAME = {}, {}
for _, p in ipairs(ns.PROFESSIONS) do
    ns.PROF_BY_ID[p.id] = p
    ns.PROF_BY_NAME[p.name] = p
end
ns.PROF_BY_NAME["Mining"] = ns.PROF_BY_ID[7]

-- What the two ways of counting are called, everywhere they show (keys stay "buy" / "farm").
ns.MODE_LABELS = { buy = "Buy mats", farm = "Use my mats" }

---------------------------------------------------------------------------
-- Item info (name, quality, item level, class), cached; the game loads it lazily
---------------------------------------------------------------------------

local waiting = false

function ns.ItemInfo(id)
    local c = ns.db.items[id]
    if c and c.name then return c end
    local name, _, quality, ilvl, _, _, _, _, _, icon, sellPrice, classID
    if C_Item and C_Item.GetItemInfo then
        name, _, quality, ilvl, _, _, _, _, _, icon, sellPrice, classID = C_Item.GetItemInfo(id)
    elseif GetItemInfo then
        name, _, quality, ilvl, _, _, _, _, _, icon, sellPrice, classID = GetItemInfo(id)
    end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        waiting = true
        return c or {}
    end
    c = { name = name, q = quality, ilvl = ilvl, icon = icon, sell = sellPrice, class = classID }
    ns.db.items[id] = c
    return c
end

function ns.ItemName(id)
    return ns.ItemInfo(id).name or ("Item " .. id)
end

function ns.TakeWaiting()
    local w = waiting
    waiting = false
    return w
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- Copper each and how many are listed (when the scan saw it).
function ns.AHPrice(id)
    if not ScannerKing then return nil end
    local p, _, q = ScannerKing.GetPrice(id)
    return p, q
end

function ns.VendorPrice(id)
    local v = ns.db.vendor[id]
    if v then return v end
    if ns.VENDOR_ITEMS[id] then
        local sell = ns.ItemInfo(id).sell
        if sell and sell > 0 then return sell * 4 end
    end
    return nil
end

-- What one of a reagent costs to buy: the cheaper of the auction house and a vendor.
function ns.BuyCost(id)
    local ah, vendor = ns.AHPrice(id), ns.VendorPrice(id)
    if ah and vendor then return math.min(ah, vendor), vendor <= ah end
    if vendor then return vendor, true end
    return ah, false
end

-- Expected auction value of disenchanting one item, before the auction cut, or nil.
function ns.DisenchantValue(id)
    local info = ns.ItemInfo(id)
    local results = ns.DisenchantResults(info.q, info.ilvl, info.class)
    if not results then return nil end
    -- Expected value per disenchant, and the same without rare procs.
    local total, base = 0, 0
    for _, r in ipairs(results) do
        local p = ns.AHPrice(r[1])
        if not p then return nil, results end
        total = total + p * r[2]
        if not r[3] then base = base + p * r[2] end
    end
    return total, results, base
end

---------------------------------------------------------------------------
-- Recipes: built-in data plus what your trade skill windows showed
---------------------------------------------------------------------------
-- The game's own window wins: a recipe Forever changed after Data/Recipes.lua was made is saved in db.learned with
-- what the window showed (item, reagents, how many), and that's what counts. The skill to learn it comes from the
-- built-in data when the window doesn't say (it never does).

-- Same item and reagents (how many it makes isn't compared: the data has the average of a random count).
function ns.SameRecipe(a, b)
    if not (a and b) or a[1] ~= b[1] or #(a[4] or {}) ~= #(b[4] or {}) then return false end
    local want = {}
    for i = 1, #a[4], 2 do want[a[4][i]] = a[4][i + 1] end
    for i = 1, #b[4], 2 do if want[b[4][i]] ~= b[4][i + 1] then return false end end
    return true
end

-- { spell, item, prof, skill, reagents = { id, count, ... }, made, learned } or nil.
function ns.Recipe(spell)
    local b, l = ns.RECIPES[spell], ns.db and ns.db.learned[spell]
    if l then
        local skill = (l[3] and l[3] > 0 and l[3]) or (b and b[3]) or 0
        return { spell = spell, item = l[1], prof = l[2], skill = skill, reagents = l[4], made = l[5] or 1, learned = not b }
    end
    if b then return { spell = spell, item = b[1], prof = b[2], skill = b[3], reagents = b[4], made = b[5] or 1 } end
end

-- Iterates { spell, item, prof, skill, reagents = { id, count, ... }, made }.
function ns.Recipes()
    local list = {}
    for spell in pairs(ns.RECIPES) do table.insert(list, ns.Recipe(spell)) end
    for spell in pairs(ns.db.learned) do
        if not ns.RECIPES[spell] then table.insert(list, ns.Recipe(spell)) end
    end
    return list
end

---------------------------------------------------------------------------
-- Which recipes you have. Trainer recipes count as yours (any trainer will
-- teach them); pattern recipes count once a trade skill window shows you know
-- them. Right-clicking a row overrides either way. Kept per character.
---------------------------------------------------------------------------

function ns.Char()
    local key = KM.Char() -- "First Last-Realm"
    local c = ns.db.chars[key]
    if not c then
        c = { known = {}, owned = {} }
        ns.db.chars[key] = c
    end
    c.skills = c.skills or {}
    return c
end

-- This character's skill in a profession and its cap (0, 0 when it doesn't have it or nothing has read it yet).
function ns.Skill(profID)
    local s = ns.db and ns.Char().skills[profID]
    if s then return s.cur or 0, s.max or s.cur or 0 end
    return 0, 0
end

local function noteSkill(name, cur, max)
    local p = name and (ns.PROF_BY_NAME[name] or (name == "Smelting" and ns.PROF_BY_ID[7]))
    if p and type(cur) == "number" then ns.Char().skills[p.id] = { cur = cur, max = max or cur } end
end

-- Reads every profession's skill from the character's skill list (login, skill changes, level ups).
function ns.ReadSkills()
    if not ns.db then return end
    if GetProfessions and GetProfessionInfo then
        local list = { pcall(GetProfessions) }
        if list[1] then
            for i = 2, 7 do
                local idx = list[i]
                if idx then
                    local ok, name, _, cur, max = pcall(GetProfessionInfo, idx)
                    if ok then noteSkill(name, cur, max) end
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() or 0 do
            local name, header, _, cur, _, _, max = GetSkillLineInfo(i)
            if not header then noteSkill(name, cur, max) end
        end
    end
end

-- 2.3.0 keys characters by their full name: this character's entry under its first name moves over.
function ns.RenameChar(old, new) KM.MoveKey(ns.db.chars, old, new) end

-- What you'd have without an override: known, or not a pattern recipe.
local function autoOwned(spell)
    return ns.Char().known[spell] or not ns.PATTERNS[spell]
end

function ns.HasRecipe(spell)
    local o = ns.Char().owned[spell]
    if o ~= nil then return o end
    return autoOwned(spell) and true or false
end

function ns.SetHasRecipe(spell, has)
    has = has and true or false
    -- Only remember the choice when it differs from what we'd work out anyway.
    if has == (autoOwned(spell) and true or false) then ns.Char().owned[spell] = nil else ns.Char().owned[spell] = has end
end

function ns.Selected(profID)
    return ns.db.profs[profID] == true
end

-- Every item a scan for these professions ({ [profID] = true }) needs a price for.
function ns.ItemsToScan(profs)
    profs = profs or ns.db.profs
    local seen, list = {}, {}
    local function add(id) if id and not seen[id] then seen[id] = true; table.insert(list, id) end end
    for _, r in ipairs(ns.Recipes()) do
        if profs[r.prof] then
            add(r.item)
            for i = 1, #r.reagents, 2 do
                if not ns.VENDOR_ITEMS[r.reagents[i]] then add(r.reagents[i]) end
            end
        end
    end
    for id in pairs(ns.DE_MATS) do add(id) end
    return list
end

---------------------------------------------------------------------------
-- Saved data, slash command
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load, and again after old Market_King data is moved in: safe twice.
function ns.InitDB()
    MarketKingDB = MarketKingDB or {}
    local db = MarketKingDB
    db.profs = db.profs or {}
    db.mode = db.mode or "buy"         -- "buy" (materials are a cost) or "farm" (you gathered them)
    db.items = db.items or {}
    if db.includeDE == nil then db.includeDE = true end
    db.deOnly = db.deOnly or false
    db.deNoProcs = db.deNoProcs or false
    db.vendor = db.vendor or {}        -- itemID -> copper paid at a vendor
    db.learned = db.learned or {}      -- recipes seen in your trade skill windows: new ones, and ones that differ from ours
    -- 2.4.0's recipe data has Forever's recipes: what windows taught us before and the data now has, it doesn't need
    for spell, l in pairs(db.learned) do
        if ns.RECIPES and ns.SameRecipe(ns.RECIPES[spell], l) then db.learned[spell] = nil end
    end
    db.chars = db.chars or {}          -- per character: recipes known, and your own have/don't-have marks
    db.recipes = db.recipes or "all"   -- show "all" recipes, only "mine", or only patterns "missing"
    db.ui = db.ui or {}
    db.ui.button, db.ui.buttonAngle = nil, nil -- 1.x minimap button: the King Maker crown replaces it
    ns.db = db
    ns.TakeSkillup()
end

-- 2.9 removed Skill-ups: its saved skills, known recipes and vendor prices move in here once, then its save is
-- cleared (SkillupKingDB stays declared in the TOC for this release so the game still loads it to move).
function ns.TakeSkillup()
    local old = SkillupKingDB
    if type(old) ~= "table" then return end
    local db = ns.db
    for key, c in pairs(type(old.chars) == "table" and old.chars or {}) do
        if type(key) == "string" and type(c) == "table" then
            local mine = db.chars[key]
            if not mine then mine = { known = {}, owned = {} }; db.chars[key] = mine end
            mine.known = mine.known or {}
            mine.skills = mine.skills or {}
            for spell, v in pairs(type(c.known) == "table" and c.known or {}) do
                if v and mine.known[spell] == nil then mine.known[spell] = true end
            end
            for prof, s in pairs(type(c.skills) == "table" and c.skills or {}) do
                if type(s) == "table" and mine.skills[prof] == nil then mine.skills[prof] = { cur = s.cur, max = s.max } end
            end
        end
    end
    for id, v in pairs(type(old.vendor) == "table" and old.vendor or {}) do
        if type(v) == "number" and db.vendor[id] == nil then db.vendor[id] = v end
    end
    SkillupKingDB = nil
end

SLASH_MARKETKING1 = "/mk"
SLASH_MARKETKING2 = "/marketking"
SlashCmdList.MARKETKING = function(msg)
    if not ns.db then return end
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "scan" then
        ns.OpenMarketScan()
    elseif cmd == "mode" then
        if rest == "mine" or rest == "my" or rest == "use" then rest = "farm" end
        ns.db.mode = (rest == "farm" or rest == "buy") and rest or (ns.db.mode == "buy" and "farm" or "buy")
        KM.Print(ns, ns.db.mode == "buy" and "Buy mats: the materials are a cost (flips)."
            or "Use my mats: crafting is compared with selling your materials raw.")
        ns.Refresh()
    elseif cmd == "recipes" then
        if rest == "reset" then
            ns.Char().owned = {}
            KM.Print(ns, "Cleared your have/don't-have marks; back to what your trade skill windows show.")
        else
            ns.db.recipes = (rest == "all" or rest == "mine" or rest == "missing") and rest or "all"
        end
        ns.Refresh()
    elseif cmd == "button" then
        KM.Print(ns, "The King Maker crown on the minimap replaces this button: /km button")
    else
        KM.Print(ns, "/mk   open Crafting Profits (or /km crafting)")
        KM.Print(ns, "/mk scan   Scan at the auction house: prices the professions ticked on Crafting Profits")
        KM.Print(ns, "/mk mode [buy|mine]   Buy mats (the materials are a cost) or Use my mats (you already have them)")
        KM.Print(ns, "/mk recipes [all|mine|missing]   which recipes to show; /mk recipes reset clears your marks")
    end
end
