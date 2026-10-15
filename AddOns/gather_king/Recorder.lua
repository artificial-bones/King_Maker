local _, ns = ...

-- Notices when you harvest a mining or herb node. The gather spell tells us
-- the type; the loot window tells us what the node was. Every harvest stamps
-- the marker so it shows faded while the node respawns; with auto-tagging on,
-- unmarked nodes also get a new marker.

local pending -- { t = "mine", at = GetTime(), mapID, x, y }

local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function onSpell(unit, spellID)
    if unit ~= "player" or not ns.db then return end
    local name = spellName(spellID)
    local t = name and ns.GATHER_SPELLS[name]
    if not t then return end
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then return end
    pending = { t = t, at = GetTime(), mapID = mapID, x = x, y = y,
        record = ns.S().auto and ns.S().record[t] }
end

-- Everything in the loot window as { [itemID] = amount }.
local function readLoot()
    local loot = {}
    for slot = 1, GetNumLootItems() do
        local lootID = itemIDFromLink(GetLootSlotLink(slot))
        if lootID then
            local _, lootName, qty = GetLootSlotInfo(slot)
            loot[lootID] = (loot[lootID] or 0) + (qty or 1)
            if lootName then ns.db.itemNames[lootID] = lootName end
        end
    end
    return loot
end

local function onLoot()
    if not pending or GetTime() - pending.at > 5 then
        pending = nil
        -- Fishing isn't a node, but its catch still goes in the farming ledger.
        if IsFishingLoot and IsFishingLoot() and ns.LedgerAdd then ns.LedgerAdd(readLoot()) end
        return
    end
    local p = pending
    pending = nil

    -- Name the node after what it gave you. Known ores/herbs come from our
    -- list; anything else (new Forever nodes) is named after the first plain
    -- item looted, skipping Scarce materials, seeds and stones.
    local nodeName, nodeItem
    local loot = readLoot() -- everything this harvest gave, for loot stats and the ledger
    if ns.LedgerAdd then ns.LedgerAdd(loot) end
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDFromLink(GetLootSlotLink(slot))
        if itemID and not ns.BONUS_ITEMS[itemID] then
            local key = ns.ITEM_TO_KEY[itemID]
            if key and ns.KNOWN[key][1] == p.t then
                nodeName, nodeItem = key, nil
                break
            end
            if not nodeName then
                local _, itemName, _, _, quality = GetLootSlotInfo(slot)
                if itemName and (quality or 1) <= 1 then
                    nodeName, nodeItem = (itemName:gsub("%s+Ore$", "")), itemID
                end
            end
        end
    end

    local node
    if p.record then
        node = ns.AddNode(p.mapID, p.x, p.y, p.t, nodeName, true, nodeItem)
    else
        node = ns.FindNode(p.mapID, p.t, p.x, p.y)
    end
    if node then
        node.lastHarvest = time()
        ns.RecordHarvest(p.mapID, node, loot)
        if ns.UpdatePinStates then ns.UpdatePinStates() end
    end
end

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterEvent("LOOT_OPENED")
f:SetScript("OnEvent", function(self, event, ...)
    -- pcall: Forever runs Midnight's addon restrictions; never let a blocked
    -- value break the rest of the addon.
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        pcall(onSpell, unit, spellID)
    elseif event == "LOOT_OPENED" then
        pcall(onLoot)
    end
end)
