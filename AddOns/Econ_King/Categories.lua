local _, ns = ...

-- Item categories, the way the auction house sorts them: the game's own item
-- classes (Weapon, Armor, Trade Goods...) and their subclasses (Plate, Herb...).
-- These come straight from the item ID, no loading needed.

-- Tab order: what people trade most first.
ns.CLASS_ORDER = { 7, 0, 4, 2, 9, 5, 15, 1, 6, 11, 3, 8, 12, 13, 16, 17 }

local FALLBACK = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor", [5] = "Reagent",
    [6] = "Projectile", [7] = "Trade Goods", [8] = "Item Enhancement", [9] = "Recipe", [11] = "Quiver",
    [12] = "Quest", [13] = "Key", [15] = "Miscellaneous", [16] = "Glyph", [17] = "Battle Pets",
}

local classOf = {}

-- classID, subClassID
function ns.ClassOf(id)
    local c = classOf[id]
    if c then return c[1], c[2] end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local cls, sub
    if inst then cls, sub = select(6, inst(id)) end
    c = { cls or 15, sub or 0 }
    classOf[id] = c
    return c[1], c[2]
end

local names = {}
function ns.ClassName(cls)
    if names[cls] then return names[cls] end
    local n
    if C_Item and C_Item.GetItemClassInfo then n = C_Item.GetItemClassInfo(cls)
    elseif GetItemClassInfo then n = GetItemClassInfo(cls) end
    names[cls] = (n and n ~= "") and n or FALLBACK[cls] or ("Class " .. cls)
    return names[cls]
end

local subNames = {}
function ns.SubclassName(cls, sub)
    local key = cls .. ":" .. sub
    if subNames[key] then return subNames[key] end
    local n
    if C_Item and C_Item.GetItemSubClassInfo then n = C_Item.GetItemSubClassInfo(cls, sub)
    elseif GetItemSubClassInfo then n = GetItemSubClassInfo(cls, sub) end
    subNames[key] = (n and n ~= "") and n or "Other"
    return subNames[key]
end
