local _, ns = ...

-- Things Market King learns while you play:
--   * what vendors charge for reagents (when you open a vendor), and
--   * recipes from your own trade skill windows, which covers anything new in
--     Forever that the built-in recipe list doesn't know, and
--   * which recipes this character knows, so pattern recipes count as yours.

-- Recipe spells that make an item, by profession and item, for windows that
-- only give the item (Classic's trade skill and craft lists).
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

-- Marks a recipe known on this character; returns true if that's news.
local function markKnown(spell)
    local known = ns.Char().known
    if known[spell] then return false end
    known[spell] = true
    return ns.PATTERNS[spell] ~= nil
end

-- Classic's trade skill window (GetTradeSkillInfo) and Enchanting's craft
-- window (GetCraftInfo) list only what you know. Recipes under collapsed
-- headers or hidden by a filter are missed until they're shown; we only ever
-- add, so nothing is lost.
local function learnClassicList(profName, count, info, recipeLink, itemLink)
    local prof = profName and ns.PROF_BY_NAME[profName]
    if not prof or not count or not info then return 0 end
    local news = 0
    for i = 1, count do
        local _, kind = info(i)
        if kind and kind ~= "header" and kind ~= "subheader" then
            local link = recipeLink and recipeLink(i)
            local spell = link and tonumber(link:match("enchant:(%d+)"))
            if spell then
                if markKnown(spell) then news = news + 1 end
            else
                link = itemLink and itemLink(i)
                local item = link and tonumber(link:match("item:(%d+)"))
                for _, s in ipairs(item and spellsMaking(prof.id, item) or {}) do
                    if markKnown(s) then news = news + 1 end
                end
            end
        end
    end
    return news
end

local function learnKnown()
    local news = 0
    if GetNumTradeSkills and GetTradeSkillLine then
        local ok, name = pcall(GetTradeSkillLine)
        local ok2, n = pcall(GetNumTradeSkills)
        if ok and ok2 and n and n > 0 then
            news = news + learnClassicList(name, n, GetTradeSkillInfo, GetTradeSkillRecipeLink, GetTradeSkillItemLink)
        end
    end
    if GetNumCrafts and GetCraftDisplaySkillLine then
        local ok, name = pcall(GetCraftDisplaySkillLine)
        local ok2, n = pcall(GetNumCrafts)
        if ok and ok2 and n and n > 0 then
            news = news + learnClassicList(name, n, GetCraftInfo, GetCraftRecipeLink, GetCraftItemLink)
        end
    end
    return news
end

local function recordMerchant()
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, n do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, quantity, available, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
            if ok and info then price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _, _, p, q, a, _, _, e = GetMerchantItemInfo(i)
            price, quantity, available, extended = p, q, a, e
        end
        -- Only items the vendor always has, for plain gold.
        if id and price and price > 0 and available == -1 and not extended then
            ns.db.vendor[id] = price / math.max(quantity or 1, 1)
        end
    end
end

local function learnTradeSkill()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic) then return end
    local profName
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        profName = ok and info and info.professionName
    end
    local prof = profName and ns.PROF_BY_NAME[profName]
    if not prof then return end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or not ids then return end
    local added, news = 0, 0
    for _, recipeID in ipairs(ids) do
        if C_TradeSkillUI.GetRecipeInfo then
            local ok3, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
            if ok3 and info and info.learned and markKnown(recipeID) then news = news + 1 end
        end
        if not ns.RECIPES[recipeID] and not ns.db.learned[recipeID] then
            local ok2, s = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            if ok2 and s and s.outputItemID then
                local reagents = {}
                for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                    local r = slot.reagents and slot.reagents[1]
                    if r and r.itemID then
                        table.insert(reagents, r.itemID)
                        table.insert(reagents, slot.quantityRequired or 1)
                    end
                end
                if #reagents > 0 then
                    ns.db.learned[recipeID] = { s.outputItemID, prof.id, 0, reagents, s.quantityMin or 1 }
                    added = added + 1
                end
            end
        end
    end
    if added > 0 then
        ns.Print("Learned " .. added .. " new " .. prof.name .. " recipe(s) from your trade skill window.")
    end
    return news
end

local function onTradeSkill()
    local ok, news = pcall(learnTradeSkill)
    local ok2, news2 = pcall(learnKnown)
    news = (ok and news or 0) + (ok2 and news2 or 0)
    if news > 0 then ns.Print("Noted " .. news .. " pattern recipe(s) this character knows.") end
    ns.Refresh()
end

local pendingInfo = false
local f = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
                     "NEW_RECIPE_LEARNED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LOGIN" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end
    if event == "MERCHANT_SHOW" then
        pcall(recordMerchant)
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE"
        or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        onTradeSkill()
    elseif event == "NEW_RECIPE_LEARNED" then
        -- (spellID) when the client gives it; otherwise the next window opening catches it
        local spell = ...
        if type(spell) == "number" then markKnown(spell); ns.Refresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item details trickle in one by one; recalculate once they settle.
        if not pendingInfo then
            pendingInfo = true
            C_Timer.After(0.5, function() pendingInfo = false; ns.Refresh() end)
        end
    elseif event == "PLAYER_LOGIN" then
        ns.UpdateMinimapButton()
        if ScannerKing and ScannerKing.RegisterCallback then
            ScannerKing.RegisterCallback("Market_King", function(e, ...)
                if e == "PRICES_UPDATED" then ns.Refresh() end
            end)
        end
        -- Scanner King runs Market Scan; we tell it what to offer and what to scan.
        if ScannerKing and ScannerKing.RegisterScanProvider then
            local options = {}
            for _, p in ipairs(ns.PROFESSIONS) do table.insert(options, { key = p.id, label = p.name }) end
            ScannerKing.RegisterScanProvider("Market_King", {
                options = options,
                items = ns.ItemsToScan,
                finished = function(picked)
                    -- Show the results for exactly what was scanned.
                    ns.db.profs = {}
                    for id in pairs(picked) do ns.db.profs[id] = true end
                    ns.Toggle(true)
                    ns.Refresh()
                end,
            })
        end
    end
end)
