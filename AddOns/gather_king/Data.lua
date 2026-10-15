local _, ns = ...

-- Node types. Aliases are the words you can type after /gt.
ns.TYPES = {
    mine = {
        label = "Mining",
        icon = "Interface\\Icons\\Trade_Mining",
        color = { 1.00, 0.78, 0.15 },
        aliases = { "mine", "mining", "ore", "m" },
    },
    herb = {
        label = "Herb",
        icon = "Interface\\Icons\\Trade_Herbalism",
        color = { 0.35, 0.85, 0.35 },
        aliases = { "herb", "herbs", "herbalism", "flower", "h" },
    },
    fish = {
        label = "Fishing",
        icon = "Interface\\Icons\\Trade_Fishing",
        color = { 0.30, 0.65, 1.00 },
        aliases = { "fish", "fishing", "pool", "f" },
    },
    treasure = {
        label = "Treasure",
        icon = "Interface\\Icons\\INV_Box_02",
        color = { 0.75, 0.45, 1.00 },
        aliases = { "treasure", "chest", "box", "t" },
    },
}
ns.TYPE_ORDER = { "mine", "herb", "fish", "treasure" }

ns.ALIAS = {}
for key, info in pairs(ns.TYPES) do
    for _, a in ipairs(info.aliases) do
        ns.ALIAS[a] = key
    end
end

-- Known nodes: the name you type (or the item you loot) -> display name and
-- the item whose icon is used for the pin.
-- [key] = { type, display name, itemID }
local KNOWN = {
    -- Mining
    copper       = { "mine", "Copper", 2770 },
    tin          = { "mine", "Tin", 2771 },
    silver       = { "mine", "Silver", 2775 },
    iron         = { "mine", "Iron", 2772 },
    gold         = { "mine", "Gold", 2776 },
    mithril      = { "mine", "Mithril", 3858 },
    truesilver   = { "mine", "Truesilver", 7911 },
    ["dark iron"]= { "mine", "Dark Iron", 11370 },
    thorium      = { "mine", "Thorium", 10620 },
    incendicite  = { "mine", "Incendicite", 3340 },
    bloodstone   = { "mine", "Lesser Bloodstone", 4278 },
    indurium     = { "mine", "Indurium", 5833 },
    obsidian     = { "mine", "Obsidian", 22202 },   -- Small/Large Obsidian Chunk (AQ, Silithus)
    -- New in WoW Forever
    ["heavy thorium"] = { "mine", "Heavy Thorium", 248815 },
    -- Herbs
    peacebloom   = { "herb", "Peacebloom", 2447 },
    silverleaf   = { "herb", "Silverleaf", 765 },
    earthroot    = { "herb", "Earthroot", 2449 },
    mageroyal    = { "herb", "Mageroyal", 785 },
    briarthorn   = { "herb", "Briarthorn", 2450 },
    swiftthistle = { "herb", "Swiftthistle", 2452 },
    stranglekelp = { "herb", "Stranglekelp", 3820 },
    bruiseweed   = { "herb", "Bruiseweed", 2453 },
    steelbloom   = { "herb", "Wild Steelbloom", 3355 },
    ["grave moss"] = { "herb", "Grave Moss", 3369 },
    kingsblood   = { "herb", "Kingsblood", 3356 },
    liferoot     = { "herb", "Liferoot", 3357 },
    fadeleaf     = { "herb", "Fadeleaf", 3818 },
    goldthorn    = { "herb", "Goldthorn", 3821 },
    khadgar      = { "herb", "Khadgar's Whisker", 3358 },
    wintersbite  = { "herb", "Wintersbite", 3819 },
    firebloom    = { "herb", "Firebloom", 4625 },
    ["purple lotus"] = { "herb", "Purple Lotus", 8831 },
    ["arthas"]   = { "herb", "Arthas' Tears", 8836 },
    sungrass     = { "herb", "Sungrass", 8838 },
    blindweed    = { "herb", "Blindweed", 8839 },
    ["ghost mushroom"] = { "herb", "Ghost Mushroom", 8845 },
    gromsblood   = { "herb", "Gromsblood", 8846 },
    ["golden sansam"] = { "herb", "Golden Sansam", 13464 },
    dreamfoil    = { "herb", "Dreamfoil", 13463 },
    silversage   = { "herb", "Mountain Silversage", 13465 },
    plaguebloom  = { "herb", "Plaguebloom", 13466 },
    icecap       = { "herb", "Icecap", 13467 },
    ["black lotus"] = { "herb", "Black Lotus", 13468 },
    -- New in WoW Forever (spawn locations not published yet)
    marefoil     = { "herb", "Marefoil", 248823 },
    demonsage    = { "herb", "Demonsage", 248821 },
    ["death lotus"] = { "herb", "Death Lotus", 248822 },
    -- Fishing pools / catches
    ["oily blackmouth"]  = { "fish", "Oily Blackmouth", 6358 },
    ["firefin snapper"]  = { "fish", "Firefin Snapper", 6359 },
    ["stonescale eel"]   = { "fish", "Stonescale Eel", 13422 },
    ["deviate fish"]     = { "fish", "Deviate Fish", 6522 },
    ["sagefish"]         = { "fish", "Sagefish", 21071 },
    ["greater sagefish"] = { "fish", "Greater Sagefish", 21153 },
    ["floating wreckage"]= { "fish", "Floating Wreckage", 6291 },
    ["schooner"]         = { "fish", "Schooner Wreckage", 6291 },
    ["school of fish"]   = { "fish", "School of Fish", 6291 },
}
ns.KNOWN = KNOWN

-- Sorted longest key first so "dark iron" wins over "iron",
-- "greater sagefish" over "sagefish", etc.
ns.KNOWN_KEYS = {}
for k in pairs(KNOWN) do table.insert(ns.KNOWN_KEYS, k) end
table.sort(ns.KNOWN_KEYS, function(a, b) return #a > #b end)

-- itemID -> known key, for auto-recording from loot.
ns.ITEM_TO_KEY = {}
for k, v in pairs(KNOWN) do
    if not ns.ITEM_TO_KEY[v[3]] then ns.ITEM_TO_KEY[v[3]] = k end
end
ns.ITEM_TO_KEY[22203] = "obsidian" -- Small Obsidian Shard

-- Extra loot that can come from any node, so it never names a node:
-- Forever's Scarce materials, herb seeds, and mining stones.
ns.BONUS_ITEMS = {
    [249391] = "Pyrite", [249425] = "Bauxite", [249426] = "Pitchblende",
    [249399] = "Frilled Lichen", [249424] = "Rosecap", [249274] = "Stranglevine",
    [268415] = "Commonplace Herb Seeds", [268416] = "Uncommon Herb Seeds",
    [268417] = "Unusual Herb Seeds", [268418] = "Scarce Herb Seeds",
    [2835] = "Rough Stone", [2836] = "Coarse Stone", [2838] = "Heavy Stone",
    [7912] = "Solid Stone", [12365] = "Dense Stone",
}

-- Gather spells, matched by name so it keeps working if Forever uses
-- different spell IDs than classic.
ns.GATHER_SPELLS = {
    ["Mining"] = "mine",
    ["Herb Gathering"] = "herb",
    ["Herbalism"] = "herb",
}

-- Raw materials for the Mat Prices tabs beyond mining and herbs.
-- { itemID, name } so names show even before the game has the item cached.
ns.MATS = {
    skin = {
        { 2934, "Ruined Leather Scraps" }, { 2318, "Light Leather" }, { 783, "Light Hide" },
        { 2319, "Medium Leather" }, { 4232, "Medium Hide" }, { 4234, "Heavy Leather" },
        { 4235, "Heavy Hide" }, { 4304, "Thick Leather" }, { 8169, "Thick Hide" },
        { 8170, "Rugged Leather" }, { 8171, "Rugged Hide" }, { 4461, "Raptor Hide" },
        { 8368, "Thick Wolfhide" }, { 5784, "Slimy Murloc Scale" }, { 5785, "Thick Murloc Scale" },
        { 6470, "Deviate Scale" }, { 6471, "Perfect Deviate Scale" }, { 7286, "Black Whelp Scale" },
        { 7392, "Green Whelp Scale" }, { 8154, "Scorpid Scale" }, { 8167, "Turtle Scale" },
        { 8165, "Worn Dragonscale" }, { 15412, "Green Dragonscale" }, { 15414, "Red Dragonscale" },
        { 15415, "Blue Dragonscale" }, { 15416, "Black Dragonscale" }, { 15417, "Devilsaur Leather" },
        { 15419, "Warbear Leather" }, { 15422, "Frostsaber Leather" }, { 15423, "Chimera Leather" },
        { 17012, "Core Leather" }, { 19767, "Primal Bat Leather" }, { 19768, "Primal Tiger Leather" },
    },
    cloth = {
        { 2589, "Linen Cloth" }, { 2592, "Wool Cloth" }, { 4306, "Silk Cloth" },
        { 4338, "Mageweave Cloth" }, { 14047, "Runecloth" }, { 14256, "Felcloth" },
    },
    ench = {
        { 10940, "Strange Dust" }, { 11083, "Soul Dust" }, { 11137, "Vision Dust" },
        { 11176, "Dream Dust" }, { 16204, "Illusion Dust" },
        { 10938, "Lesser Magic Essence" }, { 10939, "Greater Magic Essence" },
        { 10998, "Lesser Astral Essence" }, { 11082, "Greater Astral Essence" },
        { 11134, "Lesser Mystic Essence" }, { 11135, "Greater Mystic Essence" },
        { 11174, "Lesser Nether Essence" }, { 11175, "Greater Nether Essence" },
        { 16202, "Lesser Eternal Essence" }, { 16203, "Greater Eternal Essence" },
        { 10978, "Small Glimmering Shard" }, { 11084, "Large Glimmering Shard" },
        { 11138, "Small Glowing Shard" }, { 11139, "Large Glowing Shard" },
        { 11177, "Small Radiant Shard" }, { 11178, "Large Radiant Shard" },
        { 14343, "Small Brilliant Shard" }, { 14344, "Large Brilliant Shard" },
        { 20725, "Nexus Crystal" },
    },
}
ns.MAT_NAMES = {}
for _, list in pairs(ns.MATS) do
    for _, e in ipairs(list) do ns.MAT_NAMES[e[1]] = e[2] end
end

-- The Mat Prices sub-tabs, in order.
ns.MAT_TABS = {
    { key = "mine", label = "Mining" },
    { key = "herb", label = "Herbs" },
    { key = "skin", label = "Skins" },
    { key = "cloth", label = "Cloth" },
    { key = "ench", label = "Ench" },
}
