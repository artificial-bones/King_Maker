local _, ns = ...

-- The profit math for one recipe.
--
-- Buying mats (flip): the materials are a cost.
--   Craft  = crafted item's price x number made, minus the auction cut, minus material cost
--   DE     = expected disenchant value x number made, minus the cut, minus material cost
--   Raw    = 0 (don't buy anything)
-- Farming mats: you already have the materials, so the comparison is with
-- selling them. Vendor reagents (thread, flux, vials...) are still a cost.
--   Raw    = what the farmed materials sell for, minus the cut
--   Craft  = crafted item's price x number made, minus the cut, minus vendor reagents
--   DE     = disenchant value x number made, minus the cut, minus vendor reagents
-- The Craft and DE columns show the sale value after the cut; costs come off
-- in Profit. Gain is the better of Craft and DE minus Raw. Above zero, crafting wins;
-- at or below zero you're better off selling the raw materials (the red line).

local CUT = 1 - 0.05

-- opts.noDE: ignore disenchanting.  opts.deOnly: only compare disenchanting with raw.
-- opts.noProcs: value disenchants without rare procs (bonus shards, Nexus Crystals).
function ns.Evaluate(r, mode, opts)
    opts = opts or {}
    local row = { recipe = r, item = r.item, prof = r.prof, skill = r.skill, made = r.made, mats = {},
                  pattern = ns.PATTERNS[r.spell], has = ns.HasRecipe(r.spell) }
    local cost, vendorCost, rawValue = 0, 0, 0
    for i = 1, #r.reagents, 2 do
        local id, count = r.reagents[i], r.reagents[i + 1]
        local unit, fromVendor = ns.BuyCost(id)
        local ah = ns.AHPrice(id)
        table.insert(row.mats, { id = id, count = count, unit = unit, vendor = fromVendor })
        if not unit then
            row.missing = row.missing or id
        else
            cost = cost + unit * count
            if fromVendor or not ah then
                vendorCost = vendorCost + unit * count
            else
                rawValue = rawValue + ah * count * CUT
            end
        end
    end

    local price, listed = ns.AHPrice(r.item)
    row.listed = listed
    local de, deResults, deBase = ns.DisenchantValue(r.item)
    row.price, row.deEach, row.deBaseEach, row.deResults = price, de, deBase, deResults
    row.noProcs = opts.noProcs

    local base = mode == "farm" and vendorCost or cost
    row.raw = mode == "farm" and rawValue or 0
    row.cost, row.vendorCost, row.mode = cost, vendorCost, mode
    -- What it sells for after the auction cut (shown), and what's left after costs (ranked).
    if price and not opts.deOnly then
        row.craftSale = price * r.made * CUT
        row.craft = row.craftSale - base
    end
    if de and not opts.noDE then
        -- With procs is the long-run average; without is what you can count on.
        row.deSaleProcs = de * r.made * CUT
        row.deSaleBase = deBase * r.made * CUT
        row.deSale = opts.noProcs and row.deSaleBase or row.deSaleProcs
        row.de = row.deSale - base
    end

    if row.missing then return row end -- can't judge without every material's price
    local best, bestValue = "raw", row.raw
    if row.craft and row.craft > bestValue then best, bestValue = "craft", row.craft end
    if row.de and row.de > bestValue then best, bestValue = "de", row.de end
    row.best = best
    if row.craft or row.de then
        row.gain = math.max(row.craft or -math.huge, row.de or -math.huge) - row.raw
    end
    return row
end

-- Rows for one profession id, or every selected profession when profID is nil,
-- most profitable first. Returns rows and how many are above the red line.
-- opts.recipes: "mine" only recipes you have, "missing" only patterns you don't.
function ns.Rank(profID, mode, opts)
    local rows = {}
    for _, r in ipairs(ns.Recipes()) do
        if (profID and r.prof == profID) or (not profID and ns.Selected(r.prof)) then
            local row = ns.Evaluate(r, mode, opts)
            local which = opts and opts.recipes
            local keep = (which == "mine" and row.has) or (which == "missing" and not row.has) or (which ~= "mine" and which ~= "missing")
            -- DE only: just the items that can be disenchanted
            if keep and (not (opts and opts.deOnly) or row.deResults) then table.insert(rows, row) end
        end
    end
    table.sort(rows, function(a, b)
        if a.gain and b.gain then
            if a.gain ~= b.gain then return a.gain > b.gain end
        elseif a.gain or b.gain then
            return a.gain ~= nil -- priced rows before rows we can't judge
        end
        return (a.skill or 0) > (b.skill or 0)
    end)
    local above = 0
    for _, row in ipairs(rows) do
        if row.gain and row.gain > 0 then above = above + 1 end
    end
    return rows, above
end
