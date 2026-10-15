local _, ns = ...

-- What crafted gear disenchants into in Classic, by quality and item level.
-- Each bracket: { highest item level, { itemID, chance, average amount }, ... }
-- Armor uses these chances; weapons swap the dust and essence chances
-- (weapons give mostly essences). Based on the Classic disenchanting tables,
-- so the value is an expected average, not a promise.

local DUST, ESS, SHARD = 1, 2, 3

ns.DE_UNCOMMON = {
    { 15, { 10940, 0.80, 1.5 }, { 10938, 0.20, 1.5 } },
    { 20, { 10940, 0.75, 2.5 }, { 10939, 0.20, 1.5 }, { 10978, 0.05, 1 } },
    { 25, { 10940, 0.75, 5.0 }, { 10998, 0.15, 1.5 }, { 10978, 0.10, 1 } },
    { 30, { 11083, 0.75, 1.5 }, { 11082, 0.20, 1.5 }, { 11084, 0.05, 1 } },
    { 35, { 11083, 0.75, 3.5 }, { 11134, 0.20, 1.5 }, { 11138, 0.05, 1 } },
    { 40, { 11137, 0.75, 1.5 }, { 11135, 0.20, 1.5 }, { 11139, 0.05, 1 } },
    { 45, { 11137, 0.75, 3.5 }, { 11174, 0.20, 1.5 }, { 11177, 0.05, 1 } },
    { 50, { 11176, 0.75, 1.5 }, { 11175, 0.20, 1.5 }, { 11178, 0.05, 1 } },
    { 55, { 11176, 0.75, 3.5 }, { 16202, 0.20, 1.5 }, { 14343, 0.05, 1 } },
    { 60, { 16204, 0.75, 1.5 }, { 16203, 0.20, 1.5 }, { 14344, 0.05, 1 } },
    { 999, { 16204, 0.75, 3.5 }, { 16203, 0.20, 2.5 }, { 14344, 0.05, 1 } },
}

ns.DE_RARE = {
    { 25, { 10978, 1, 1 } },
    { 30, { 11084, 1, 1 } },
    { 35, { 11138, 1, 1 } },
    { 40, { 11139, 1, 1 } },
    { 45, { 11177, 1, 1 } },
    { 50, { 11178, 1, 1 } },
    { 55, { 14343, 1, 1 } },
    { 999, { 14344, 0.995, 1 }, { 20725, 0.005, 1 } },
}

ns.DE_EPIC = {
    { 45, { 11177, 1, 3 } },
    { 50, { 11178, 1, 3 } },
    { 55, { 14343, 1, 3 } },
    { 60, { 20725, 1, 1 } },
    { 999, { 20725, 1, 1.5 } },
}

-- Every disenchanting material, so a scan prices them all.
ns.DE_MATS = {}
for _, t in ipairs({ ns.DE_UNCOMMON, ns.DE_RARE, ns.DE_EPIC }) do
    for _, bracket in ipairs(t) do
        for i = 2, #bracket do ns.DE_MATS[bracket[i][1]] = true end
    end
end

-- Expected results of disenchanting one item: { { itemID, expected amount }, ... },
-- or nil if it can't be disenchanted. quality 2/3/4 = green/blue/purple,
-- classID 2 = weapon, 4 = armor.
function ns.DisenchantResults(quality, itemLevel, classID)
    if not (quality and itemLevel and (classID == 2 or classID == 4)) then return nil end
    local tableFor = (quality == 2 and ns.DE_UNCOMMON) or (quality == 3 and ns.DE_RARE) or (quality == 4 and ns.DE_EPIC)
    if not tableFor or (quality == 3 and itemLevel < 11) or (quality == 4 and itemLevel < 40) then return nil end
    for _, bracket in ipairs(tableFor) do
        if itemLevel <= bracket[1] then
            local out = {}
            for i = 2, #bracket do
                local id, chance, amount = bracket[i][1], bracket[i][2], bracket[i][3]
                if quality == 2 and classID == 2 and i <= 3 then
                    chance = bracket[i == 2 and 3 or 2][2] -- weapons: dust and essence chances swap
                end
                -- A "proc" is a rare bonus result (the 5-10% shard on greens, the
                -- 0.5% Nexus Crystal on blues), not something you can count on.
                table.insert(out, { id, chance * amount, chance < 0.15 })
            end
            return out
        end
    end
end
