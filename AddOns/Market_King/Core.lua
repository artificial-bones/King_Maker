local _, ns = ...

-- Market King: for the professions you pick, prices every craftable item and
-- everything that goes into it (through Scanner King), then works out the
-- best thing to do with your materials:
--   * sell the raw materials,
--   * craft the item and sell it, or
--   * craft it, disenchant it and sell the enchanting materials.
-- Two ways to count: "Buying mats" (you buy the materials, so they're a cost:
-- flips) or "Farming mats" (you gathered them, so the question is whether
-- crafting beats just selling them).

local PREFIX = "|cff4fc3f7Market King|r: "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

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
-- Recipes: built-in data plus anything learned from your trade skill windows
---------------------------------------------------------------------------

-- Iterates { spell, item, prof, skill, reagents = { id, count, ... }, made }.
function ns.Recipes()
    local list = {}
    for spell, r in pairs(ns.RECIPES) do
        table.insert(list, { spell = spell, item = r[1], prof = r[2], skill = r[3], reagents = r[4], made = r[5] or 1 })
    end
    for spell, r in pairs(ns.db.learned) do
        if not ns.RECIPES[spell] then
            table.insert(list, { spell = spell, item = r[1], prof = r[2], skill = r[3] or 0, reagents = r[4], made = r[5] or 1, learned = true })
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Which recipes you have. Trainer recipes count as yours (any trainer will
-- teach them); pattern recipes count once a trade skill window shows you know
-- them. Right-clicking a row overrides either way. Kept per character.
---------------------------------------------------------------------------

function ns.Char()
    local key = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
    local c = ns.db.chars[key]
    if not c then
        c = { known = {}, owned = {} }
        ns.db.chars[key] = c
    end
    return c
end

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

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= "Market_King" then return end
    MarketKingDB = MarketKingDB or {}
    local db = MarketKingDB
    db.profs = db.profs or {}
    db.mode = db.mode or "buy"         -- "buy" (materials are a cost) or "farm" (you gathered them)
    db.items = db.items or {}
    if db.includeDE == nil then db.includeDE = true end
    db.deOnly = db.deOnly or false
    db.deNoProcs = db.deNoProcs or false
    db.vendor = db.vendor or {}        -- itemID -> copper paid at a vendor
    db.learned = db.learned or {}      -- recipes seen in your trade skill windows
    db.chars = db.chars or {}          -- per character: recipes known, and your own have/don't-have marks
    db.recipes = db.recipes or "all"   -- show "all" recipes, only "mine", or only patterns "missing"
    db.ui = db.ui or {}
    if db.ui.button == nil then db.ui.button = true end
    ns.db = db
end)

SLASH_MARKETKING1 = "/mk"
SLASH_MARKETKING2 = "/marketking"
SlashCmdList.MARKETKING = function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "scan" then
        ns.OpenMarketScan()
    elseif cmd == "mode" then
        ns.db.mode = (rest == "farm" or rest == "buy") and rest or (ns.db.mode == "buy" and "farm" or "buy")
        ns.Print(ns.db.mode == "buy" and "Counting materials as bought." or "Counting materials as farmed (no material cost).")
        ns.Refresh()
    elseif cmd == "recipes" then
        if rest == "reset" then
            ns.Char().owned = {}
            ns.Print("Cleared your have/don't-have marks; back to what your trade skill windows show.")
        else
            ns.db.recipes = (rest == "all" or rest == "mine" or rest == "missing") and rest or "all"
        end
        ns.Refresh()
    elseif cmd == "button" then
        ns.db.ui.button = rest == "on" or (rest ~= "off" and not ns.db.ui.button)
        ns.UpdateMinimapButton()
    else
        ns.Print("/mk   open Market King")
        ns.Print("/mk scan   open Market Scan to pick professions and scan (auction house open)")
        ns.Print("/mk mode [buy|farm]   count materials as bought or farmed")
        ns.Print("/mk recipes [all|mine|missing]   which recipes to show; /mk recipes reset clears your marks")
        ns.Print("/mk button [on|off]   minimap button")
    end
end
