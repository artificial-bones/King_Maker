local _, KM = ...

-- Items: one item cache and THE value rule for the whole suite (moved here from Farm in 2.6 so Farm, the Farm
-- Tracker and the HUD's Mat Prices agree on what an item is worth).
--
--   KM.Item(id)        { name, q = quality, icon, sell = vendor copper, class, bop } (cached; may lack name until
--                      the client has loaded it: GetItemInfo can return nil, so a load is requested instead)
--   KM.ItemText(id)    the name in its quality colour ("Item 1234" until it loads)
--   KM.ItemValue(id)   what one is worth to you, and where that came from ("ah" | "vendor" | "quest");
--                      nil while the item isn't loaded yet
--   KM.IsQuestItem(id) a Quest-class item worth nothing (one that sells or has a market price is ordinary loot)
--   KM.TakeItemWaiting()  true once after any lookup had to wait for item data (Farm redraws on it)

KM.AH_CUT = 0.95

local cache = {}
local waiting = false

function KM.Item(id)
    local c = cache[id]
    if c and c.name then return c end
    c = c or {}
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if get and id then
        local ok, name, _, quality, _, _, _, _, _, _, icon, sell, classID, _, bind = pcall(get, id)
        if ok and name then
            c.name, c.q, c.icon, c.sell, c.class, c.bop = name, quality, icon, sell or 0, classID, bind == 1
        end
    end
    if not c.name and id then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if inst and not c.icon then
            local ok, _, _, _, _, icon, classID = pcall(inst, id)
            if ok then c.icon, c.class = icon, c.class or classID end
        end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        waiting = true
    end
    if id then cache[id] = c end
    return c
end

function KM.TakeItemWaiting()
    local w = waiting
    waiting = false
    return w
end

KM.QUALITY_COLOR = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }

function KM.ItemText(id)
    local i = KM.Item(id)
    return (KM.QUALITY_COLOR[i.q or 1] or "|cffffffff") .. (i.name or ("Item " .. tostring(id))) .. "|r"
end

local function marketPrice(id)
    if not (ScannerKing and ScannerKing.GetMarketPrice) then return nil end
    local ok, p = pcall(ScannerKing.GetMarketPrice, id)
    return ok and tonumber(p) or nil
end

-- A quest item that's worth nothing: item class Quest (12) with no vendor price and no market price. A Quest-class
-- item that sells (Righteous Orb and friends) is ordinary loot. Until the item loads, a Quest-class item with no
-- market price counts as a quest item.
function KM.IsQuestItem(id)
    local i = KM.Item(id)
    if i.class ~= 12 then return false end
    if i.name and (i.sell or 0) > 0 then return false end
    local ah = marketPrice(id)
    return not (ah and ah > 0)
end

-- Grey and bind-on-pickup items go to a vendor; anything else is the better of the auction house (Scanner's market
-- price, after the 5% cut) and a vendor. Quest items (KM.IsQuestItem) are worth nothing here.
function KM.ItemValue(id)
    local i = KM.Item(id)
    if i.class == 12 and KM.IsQuestItem(id) then return 0, "quest" end
    if not i.name then return nil end
    local vendor = i.sell or 0
    if i.q == 0 or i.bop then return vendor, "vendor" end
    local ah = ScannerKing and ScannerKing.GetMarketPrice and ScannerKing.GetMarketPrice(id)
    if ah and ah * KM.AH_CUT > vendor then return ah * KM.AH_CUT, "ah" end
    return vendor, "vendor"
end

-- A value Forever may hide from addons (Midnight's "secret" values) is treated as unknown.
function KM.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
