local _, KM = ...
local ns = KM.Module("Gather")

-- Notices when you harvest a mining or herb node. The gather spell tells us
-- the type; the node's own name (sent with the cast, or the tooltip you clicked)
-- tells us what it was, so Small and Rich Thorium Veins stay apart even though
-- both give Thorium Ore; failing that, the loot window does. Every harvest stamps
-- the marker so it shows faded while the node respawns; with auto-tagging on,
-- unmarked nodes also get a new marker. What a harvest is worth is the Farm
-- Tracker's job (Core\Loot.lua reads the same window for it).

local pending -- { t = "mine", at = GetTime(), mapID, x, y, target = "Rich Thorium Vein" }
local sent    -- { target = node name, at = GetTime() } from UNIT_SPELLCAST_SENT

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

local function plain(s)
    if type(s) ~= "string" or s == "" then return nil end
    if issecretvalue and issecretvalue(s) then return nil end
    return s
end

-- The cast is starting: note the node's name. The game passes it as the target; if not, it's the world
-- tooltip you had up when you clicked the node.
local function onSent(unit, target, _, spellID)
    if unit ~= "player" then return end
    local name = spellName(spellID)
    if not (name and ns.GATHER_SPELLS[name]) then return end
    target = plain(target)
    if not target and GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent then
        target = plain(GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText())
    end
    sent = target and { target = target, at = GetTime() } or nil
end

local function onSpell(unit, spellID)
    if unit ~= "player" or not ns.db then return end
    local name = spellName(spellID)
    local t = name and ns.GATHER_SPELLS[name]
    if not t then return end
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then return end
    pending = { t = t, at = GetTime(), mapID = mapID, x = x, y = y,
        record = ns.S().auto and ns.S().record[t],
        target = sent and GetTime() - sent.at < 15 and sent.target or nil }
    sent = nil
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
        return
    end
    local p = pending
    pending = nil

    -- Name the node after what it gave you. Known ores/herbs come from our
    -- list; anything else (new Forever nodes) is named after the first plain
    -- item looted, skipping Scarce materials, seeds and stones.
    local nodeName, nodeItem
    local loot = readLoot() -- everything this harvest gave, for loot stats
    local tkey, tknown = ns.LookupKnown(p.target)
    if tknown and tknown[1] == p.t then nodeName = tkey end
    local best -- the most exact known name among the loot (Heavy Thorium over Thorium)
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDFromLink(GetLootSlotLink(slot))
        if not nodeName and itemID and not ns.BONUS_ITEMS[itemID] then
            local key = ns.ITEM_TO_KEY[itemID]
            if key and ns.KNOWN[key][1] == p.t then
                if not best or not ns.KNOWN[best] or #key > #best then best, nodeItem = key, nil end
            elseif not best then
                local _, itemName, _, _, quality = GetLootSlotInfo(slot)
                if itemName and (quality or 1) <= 1 then
                    best, nodeItem = (itemName:gsub("%s+Ore$", "")), itemID
                end
            end
        end
    end
    if not nodeName then nodeName = best end

    local node
    if p.record then
        node = ns.AddNode(p.mapID, p.x, p.y, p.t, nodeName, true, nodeItem)
    else
        node = ns.FindNode(p.mapID, p.t, p.x, p.y)
        -- an old "Thorium" marker learns which vein it is
        if node and nodeName and (not node.n or ns.IsVaguer(node.n, nodeName)) then
            node = ns.AddNode(p.mapID, p.x, p.y, p.t, nodeName, true, nodeItem)
        end
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
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("LOOT_READY") then
    pcall(f.RegisterEvent, f, "LOOT_READY") -- before fast auto-loot empties the window; the second read finds nothing pending
end
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("UNIT_SPELLCAST_SENT") then
    pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SENT", "player")
end
f:SetScript("OnEvent", function(self, event, ...)
    -- pcall: Forever runs Midnight's addon restrictions; never let a blocked
    -- value break the rest of the addon.
    if event == "UNIT_SPELLCAST_SENT" then
        pcall(onSent, ...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        pcall(onSpell, unit, spellID)
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        pcall(onLoot)
    end
end)
