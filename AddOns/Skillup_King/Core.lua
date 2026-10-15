local _, ns = ...

-- Skillup King: the cheapest way to level a profession. For every recipe it
-- knows where the skill points are (orange, yellow, green, grey), what the
-- materials cost at the auction house today (Scanner King's prices), and what
-- you get back for what you make: selling it, disenchanting it, or a vendor.
-- From that, the cost of each skill point, and a plan from your skill to the
-- top: what to make, how many, and what it costs (or makes).
--
-- Files:
--   Core.lua           saved data, prices, your skills and recipes
--   Plan.lua           the skill-up math and the plan
--   UI.lua             the window and the minimap button
--   Data/Recipes.lua   every recipe and its colors
--   Data/Patterns.lua  recipes taught by a pattern (not a trainer)
--   Data/Disenchant.lua, Data/Vendor.lua

SkillupKing = { API_VERSION = 1 }
local API = SkillupKing
ns.API = API

local PREFIX = "|cff7fd36eSkillup King|r: "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

ns.CUT = 0.95 -- the auction house keeps 5% of a sale

-- Professions, in the order they're shown. id matches Data/Recipes.lua.
ns.PROFESSIONS = {
    { id = 4, name = "Alchemy", short = "Alchemy" },
    { id = 2, name = "Blacksmithing", short = "Smithing" },
    { id = 6, name = "Cooking", short = "Cooking" },
    { id = 10, name = "Enchanting", short = "Enchanting" },
    { id = 9, name = "Engineering", short = "Engineering" },
    { id = 1, name = "First Aid", short = "First Aid" },
    { id = 3, name = "Leatherworking", short = "Leather" },
    { id = 7, name = "Mining", short = "Smelting" },
    { id = 8, name = "Tailoring", short = "Tailoring" },
}
ns.PROF_BY_ID, ns.PROF_BY_NAME = {}, {}
for _, p in ipairs(ns.PROFESSIONS) do
    ns.PROF_BY_ID[p.id] = p
    ns.PROF_BY_NAME[p.name] = p
end
ns.PROF_BY_NAME["Smelting"] = ns.PROF_BY_ID[7]

-- Trainer ranks: the skill they let you reach, the skill a trainer wants to
-- teach them, and the character level they need.
ns.RANKS = {
    { name = "Apprentice", cap = 75, skill = 0, level = 5 },
    { name = "Journeyman", cap = 150, skill = 50, level = 10 },
    { name = "Expert", cap = 225, skill = 125, level = 20 },
    { name = "Artisan", cap = 300, skill = 200, level = 35 },
}
ns.MAX_SKILL = 300

---------------------------------------------------------------------------
-- Items and spells
---------------------------------------------------------------------------

function ns.ItemInfo(id)
    if not id or id == 0 then return {} end
    local c = ns.db.items[id]
    if c and c.name then return c end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, quality, ilvl, _, _, _, _, _, icon, sellPrice, classID
    if get then name, _, quality, ilvl, _, _, _, _, _, icon, sellPrice, classID = get(id) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return c or {}
    end
    c = { name = name, q = quality, ilvl = ilvl, icon = icon, sell = sellPrice, class = classID }
    ns.db.items[id] = c
    return c
end

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }

function ns.SpellName(spell)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spell) end
    if GetSpellInfo then return (GetSpellInfo(spell)) end
end

-- What a recipe is called: the item it makes, or the enchant's name.
function ns.RecipeName(r)
    if r.item ~= 0 then
        local info = ns.ItemInfo(r.item)
        return info.name or ("Item " .. r.item), QUALITY[info.q or 1]
    end
    return ns.SpellName(r.spell) or ("Spell " .. r.spell), "|cffffd100"
end

function ns.ItemText(id)
    local info = ns.ItemInfo(id)
    return (QUALITY[info.q or 1] or "|cffffffff") .. (info.name or ("Item " .. id)) .. "|r"
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- Lowest price listed (what buying one costs) and how many are up.
function ns.AHPrice(id)
    if not (ScannerKing and ScannerKing.GetPrice) then return nil end
    local p, _, q = ScannerKing.GetPrice(id)
    return p, q
end

-- What one sells for: the market price when a Deep Scan has one, else the lowest.
function ns.SellPrice(id)
    if ScannerKing and ScannerKing.GetMarketPrice then
        local p, _, q = ScannerKing.GetMarketPrice(id)
        if p then return p, q end
    end
    return ns.AHPrice(id)
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

-- What one of a reagent costs: the cheaper of the auction house and a vendor.
function ns.BuyCost(id)
    local ah, vendor = ns.AHPrice(id), ns.VendorPrice(id)
    if ah and vendor then return math.min(ah, vendor), vendor <= ah end
    if vendor then return vendor, true end
    return ah, false
end

-- Expected auction value of disenchanting one, before the cut, or nil.
function ns.DisenchantValue(id)
    local info = ns.ItemInfo(id)
    local results = ns.DisenchantResults(info.q, info.ilvl, info.class)
    if not results then return nil end
    local total = 0
    for _, r in ipairs(results) do
        local p = ns.SellPrice(r[1])
        if not p then return nil end
        total = total + p * r[2]
    end
    return total
end

function ns.Money(v)
    if not v then return "|cff808080-|r" end
    local a = math.floor(math.abs(v) + 0.5)
    local s
    if ScannerKing and ScannerKing.FormatMoney then
        s = ScannerKing.FormatMoney(a)
    else
        local g, sv, c = math.floor(a / 10000), math.floor(a / 100) % 100, a % 100
        s = (g > 0 and (g .. "g ") or "") .. ((g > 0 or sv > 0) and (sv .. "s ") or "") .. c .. "c"
    end
    return v < 0 and ("|cffff6060-|r" .. s) or s
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

-- { spell, item, prof, orange, yellow, green, grey, reagents = { id, count, ... }, made }
local all
function ns.Recipes()
    if all then return all end
    all = {}
    for spell, r in pairs(ns.RECIPES) do
        if r[4] > 0 and r[5] > 0 and ns.PROF_BY_ID[r[2]] then -- a couple have no colors: skip them
            table.insert(all, { spell = spell, item = r[1], prof = r[2], orange = r[3], yellow = math.max(r[4], r[3]),
                green = math.floor((math.max(r[4], r[3]) + r[5]) / 2), grey = r[5], reagents = r[6], made = r[7] or 1 })
        end
    end
    table.sort(all, function(a, b)
        if a.orange ~= b.orange then return a.orange < b.orange end
        return a.spell < b.spell
    end)
    return all
end

---------------------------------------------------------------------------
-- This character: skills, level, known recipes
---------------------------------------------------------------------------

function ns.CharKey()
    return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end

function ns.Char()
    local key = ns.CharKey()
    local c = ns.db.chars[key]
    if not c then
        c = { known = {}, skills = {} }
        ns.db.chars[key] = c
    end
    return c
end

function ns.Level() return UnitLevel and UnitLevel("player") or 60 end

-- Your skill in a profession and its cap (0, 0 when you don't have it).
function ns.Skill(profID)
    local s = ns.Char().skills[profID]
    if s then return s.cur, s.max end
    return 0, 0
end

local function noteSkill(name, cur, max)
    local p = name and ns.PROF_BY_NAME[name]
    if p and cur then ns.Char().skills[p.id] = { cur = cur, max = max or cur } end
end

-- Reads every profession's skill from the character's skill list.
function ns.ReadSkills()
    if not ns.db then return end
    if GetProfessions and GetProfessionInfo then
        local list = { GetProfessions() }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local ok, name, _, cur, max = pcall(GetProfessionInfo, idx)
                if ok then noteSkill(name, cur, max) end
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

-- Recipes this character knows. Trainer recipes count as yours (any trainer
-- teaches them, for a fee); a pattern recipe once a trade skill window shows it.
function ns.HasRecipe(spell)
    return ns.Char().known[spell] or not ns.PATTERNS[spell]
end

local byItem
local function spellsMaking(profID, itemID)
    if not byItem then
        byItem = {}
        for spell, r in pairs(ns.RECIPES) do
            local key = r[2] .. ":" .. r[1]
            byItem[key] = byItem[key] or {}
            table.insert(byItem[key], spell)
        end
    end
    return byItem[profID .. ":" .. itemID]
end

-- The open trade skill window: its skill, and the recipes you know.
function ns.ReadTradeSkill()
    if not ns.db then return end
    local known = ns.Char().known
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and info and info.professionName then
            noteSkill(info.professionName, info.skillLevel, info.maxSkillLevel)
            local ok2, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
            for _, id in ipairs(ok2 and ids or {}) do
                local ok3, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
                if ok3 and r and r.learned then known[id] = true end
            end
        end
    end
    -- Classic's windows: the trade skill list, and Enchanting's craft list.
    local function classic(line, count, info, recipeLink, itemLink)
        local ok, name, cur, max = pcall(line)
        if not ok or not name then return end
        noteSkill(name, cur, max)
        local p = ns.PROF_BY_NAME[name]
        local ok2, n = pcall(count)
        for i = 1, (ok2 and n) or 0 do
            local _, kind = info(i)
            if kind and kind ~= "header" and kind ~= "subheader" then
                local link = recipeLink and recipeLink(i)
                local spell = link and tonumber(link:match("enchant:(%d+)"))
                if spell then
                    known[spell] = true
                elseif p and itemLink then
                    link = itemLink(i)
                    local item = link and tonumber(link:match("item:(%d+)"))
                    for _, s in ipairs(item and spellsMaking(p.id, item) or {}) do known[s] = true end
                end
            end
        end
    end
    if GetTradeSkillLine and GetNumTradeSkills then
        classic(GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillRecipeLink, GetTradeSkillItemLink)
    end
    if GetCraftDisplaySkillLine and GetNumCrafts then
        classic(GetCraftDisplaySkillLine, GetNumCrafts, GetCraftInfo, GetCraftRecipeLink, GetCraftItemLink)
    end
end

local function recordMerchant()
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, quantity, available, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
            if ok and info then price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _, _, p, q, a, _, _, e = GetMerchantItemInfo(i)
            price, quantity, available, extended = p, q, a, e
        end
        if id and price and price > 0 and available == -1 and not extended then
            ns.db.vendor[id] = price / math.max(quantity or 1, 1)
        end
    end
end

-- Every item a profession's plan needs a price for: reagents, what it makes,
-- the disenchanting materials and the patterns.
function ns.ItemsToScan(profID)
    local seen, list = {}, {}
    local function add(id) if id and id ~= 0 and not seen[id] then seen[id] = true; table.insert(list, id) end end
    for _, r in ipairs(ns.Recipes()) do
        if not profID or r.prof == profID then
            add(r.item)
            for i = 1, #r.reagents, 2 do
                if not ns.VENDOR_ITEMS[r.reagents[i]] then add(r.reagents[i]) end
            end
            for _, p in ipairs(ns.PATTERNS[r.spell] or {}) do add(p) end
        end
    end
    for id in pairs(ns.DE_MATS) do add(id) end
    return list
end

---------------------------------------------------------------------------
-- Saved data, events, slash command
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "MERCHANT_SHOW", "PLAYER_LEVEL_UP" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end
local pending = false
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "Skillup_King" then return end
        SkillupKingDB = SkillupKingDB or {}
        local db = SkillupKingDB
        db.chars = db.chars or {}   -- "Name-Realm" -> { known = { spell = true }, skills = { prof = { cur, max } } }
        db.vendor = db.vendor or {} -- reagent -> what a vendor charges
        db.items = db.items or {}   -- item info cache
        db.ui = db.ui or {}
        if db.ui.button == nil then db.ui.button = true end
        if db.ui.de == nil then db.ui.de = true end     -- count disenchanting what you make
        if db.ui.sell == nil then db.ui.sell = true end -- count selling it on the auction house
        db.ui.view = db.ui.view or "plan"
        ns.db = db
        return
    end
    if not ns.db then return end
    if event == "MERCHANT_SHOW" then
        recordMerchant()
    elseif event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_LEVEL_UP" then
        ns.ReadSkills()
        if event == "PLAYER_LOGIN" and ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
        if ns.Refresh then ns.Refresh() end
    elseif not pending then
        -- The trade skill window fills over several events: read it once things settle.
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            ns.ReadTradeSkill()
            if ns.Refresh then ns.Refresh() end
        end)
    end
end)

-- "tailoring", "first aid", "smelting"... -> the profession
function ns.FindProfession(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, p in ipairs(ns.PROFESSIONS) do
        if p.name:lower() == text or p.short:lower() == text then return p end
    end
end

-- If the game ever stops Skillup King from doing something, say what it was.
local guard = CreateFrame("Frame")
guard:RegisterEvent("ADDON_ACTION_FORBIDDEN")
guard:RegisterEvent("ADDON_ACTION_BLOCKED")
guard:SetScript("OnEvent", function(_, event, addon, what)
    if addon == "Skillup_King" then
        ns.Print("the game blocked Skillup King from " .. tostring(what) .. " (" .. event .. "). Please send this line along.")
    end
end)

SLASH_SKILLUPKING1 = "/suk"
SLASH_SKILLUPKING2 = "/skillup"
SlashCmdList.SKILLUPKING = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        ns.Toggle()
    elseif cmd == "button" then
        ns.db.ui.button = rest:lower() == "on" or (rest:lower() ~= "off" and not ns.db.ui.button)
        ns.UpdateMinimapButton()
    elseif ns.FindProfession(msg) then
        ns.Toggle(true, ns.FindProfession(msg).id)
    else
        ns.Print("/suk   open Skillup King (or click the minimap button)")
        ns.Print("/suk tailoring   open it on a profession")
        ns.Print("/suk button [on|off]   minimap button")
    end
end

---------------------------------------------------------------------------
-- For other addons
---------------------------------------------------------------------------

-- The plan from a skill to another: { { from, to, spell, item, crafts, cost } ... }, total cost.
function API.Plan(profID, from, to)
    local plan = ns.Plan(profID, from, to)
    return plan.steps, plan.cost
end
