local _, KM = ...
local ns = KM.Module("Scanner")
local API = ns.API

-- King Maker's section in item tooltips, wherever the item shows up (bags, bank, loot, links, the auction house):
--
--   King Maker                                   AUCTION   <- header; AUCTION or VENDOR: which pays more
--   Pays 34s 20c more than vendoring.                      <- after the auction house's 5% cut
--   Auction house   35s 94c  2 h ago                       <- market price (else lowest), when it was scanned
--   Lowest buyout / Listed
--   30-day average, 7-day trend                            <- Price History (Econ's provider), first
-- Laid out like a crafting addon's block: light grey labels, white values (API.TooltipLine for providers).
--   Vendor        what a vendor pays you for one
--   Vendors sell  what you paid a vendor for one (Crafting Profits saw it)
--   Drops         the mobs with the best drop chance (Farm: your kills and your guild's, QuestieDB)
--   Used in       professions with recipes that take it (Crafting Profits' recipes)
--   You own         how many, and on which character (Inventory's provider), then anyone else's lines
--
-- Other addons can add their own lines under ours:
--
--   ScannerKing.AddTooltipProvider("Econ_King", function(tooltip, itemID) ... end)
--
-- /sk tooltip off hides the prices and the header; /sk sources off hides Vendor / Drops / Used in.

local providers = {}

function API.AddTooltipProvider(owner, fn)
    providers[owner] = fn
end

local LABEL, WHITE = { 0.78, 0.78, 0.78 }, { 1, 1, 1 }
local HEAD = { 0.94, 0.77, 0.30 }                       -- the crown's gold
local TAG = { AUCTION = { 1, 0.82, 0 }, VENDOR = { 1, 0.6, 0.25 } }
local CUT = 0.95                                        -- the auction house keeps 5% of a sale
local FIRST = "Econ_King"                               -- averages and trend sit right under the prices

local function line(tt, left, right, lc, rc)
    lc, rc = lc or LABEL, rc or WHITE
    tt:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
end
-- A row in King Maker's section, for the modules that add to it (Price History's averages).
API.TooltipLine = line

local function grey(text) return "|cff8c8c8c" .. text .. "|r" end

local function vendorSell(id)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, id)
    if ok and name and type(sell) == "number" and sell > 0 then return sell end
end

---------------------------------------------------------------------------
-- Where it comes from and what it's for (other modules' data, read through KM.mods: same addon)
---------------------------------------------------------------------------

local MAX_MOBS = 2

-- "Flamebringer Stalker (Searing Gorge) 15%, Dust Stormer 4%, +3 more" or nil
local function drops(id)
    local farm = KM.mods.Farm
    if not (farm and farm.db and farm.DroppedBy and farm.MobInfo) then return nil end
    local list = {}
    for npc in pairs(farm.DroppedBy(id)) do
        local chance = farm.Chance and farm.Chance(npc, id)
        list[#list + 1] = { npc = npc, chance = chance or -1 }
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.npc < b.npc
    end)
    local out = {}
    for i = 1, math.min(MAX_MOBS, #list) do
        local e, info = list[i], farm.MobInfo(list[i].npc)
        local zone = farm.MapName and farm.MapName(info.map) or ""
        local text = info.name .. (zone ~= "" and (" (" .. zone .. ")") or "")
        if e.chance > 0 then text = text .. " " .. math.max(1, math.floor(e.chance * 100 + 0.5)) .. "%" end
        out[#out + 1] = text
    end
    if #list > MAX_MOBS then out[#out + 1] = "+" .. (#list - MAX_MOBS) .. " more" end
    return table.concat(out, ", ")
end

-- Reagent -> { [profession name] = recipes }, built from Crafting Profits' recipes (again when you learn more).
local usedIn, usedFor
local function uses(id)
    local market = KM.mods.Market
    if not (market and market.db and market.Recipes and market.PROF_BY_ID) then return nil end
    local learned = 0
    for _ in pairs(market.db.learned or {}) do learned = learned + 1 end
    if not usedIn or usedFor ~= learned then
        usedIn, usedFor = {}, learned
        for _, r in ipairs(market.Recipes()) do
            local prof = market.PROF_BY_ID[r.prof]
            local name = prof and prof.name
            for i = 1, #(r.reagents or {}), 2 do
                local reagent = r.reagents[i]
                if name and reagent then
                    usedIn[reagent] = usedIn[reagent] or {}
                    usedIn[reagent][name] = (usedIn[reagent][name] or 0) + 1
                end
            end
        end
    end
    local by = usedIn[id]
    if not by then return nil end
    local names = {}
    for name in pairs(by) do names[#names + 1] = name end
    table.sort(names, function(a, b) if by[a] ~= by[b] then return by[a] > by[b] end return a < b end)
    for i, name in ipairs(names) do names[i] = name .. " (" .. by[name] .. ")" end
    return table.concat(names, ", ")
end

local function vendorBuy(id)
    local market = KM.mods.Market
    return market and market.db and market.db.vendor and market.db.vendor[id]
end

-- Drops and Used in, worked out once per item for a little while (Drops walks every mob you know).
local cache, cacheAt = {}, 0
local function sources(id)
    local now = GetTime and GetTime() or 0
    if now - cacheAt > 30 then wipe(cache); cacheAt = now end
    if cache[id] == nil then
        local rows = {}
        local ok, d = pcall(drops, id)
        if ok and d then rows[#rows + 1] = { "Drops", d } end
        local ok2, u = pcall(uses, id)
        if ok2 and u then rows[#rows + 1] = { "Used in", u } end
        cache[id] = rows
    end
    return cache[id]
end
ns.TooltipSources = sources

function ns.AddTooltipLines(tt, id)
    if not (ns.db and tt and id) then return end
    local pr = ns.db.ui.tooltip and ns.db.prices[id]
    local more = ns.db.ui.sources
    local rows = more and sources(id) or {}
    local buy = more and vendorBuy(id)
    local sell = vendorSell(id)
    local owned = InventoryKing and InventoryKing.GetCount and select(2, pcall(InventoryKing.GetCount, id))
    local section = pr or #rows > 0 or buy or (type(owned) == "number" and owned > 0)
    if section then
        tt:AddLine(" ") -- a gap between the game's lines (or another addon's) and ours
        -- the header, and which pays more: the auction house (after its cut) or a vendor
        local value = pr and (pr.m or pr.p)
        local tag, verdict
        if value and sell then
            local diff = math.floor(value * CUT) - sell
            if diff > 0 then
                tag, verdict = "AUCTION", "Pays " .. API.FormatMoney(diff) .. " more than vendoring."
            else
                tag, verdict = "VENDOR", "Vendor it: " .. API.FormatMoney(-diff) .. " more than the auction house."
            end
        end
        local tc = tag and TAG[tag] or WHITE
        line(tt, "King Maker", tag or " ", HEAD, tc)
        if verdict then tt:AddLine(verdict, tc[1], tc[2], tc[3]) end
        if pr then
            local age = API.PriceAge(pr.t) .. (pr.from and (", " .. pr.from) or "")
            line(tt, "Auction house", API.FormatMoney(pr.m or pr.p) .. "  " .. grey(age))
            if pr.m then line(tt, "Lowest buyout", API.FormatMoney(pr.p)) end
            if pr.q then line(tt, "Listed", pr.q .. (pr.n and (" in " .. pr.n .. " auction" .. (pr.n == 1 and "" or "s")) or "")) end
        end
    end
    if providers[FIRST] then pcall(providers[FIRST], tt, id) end
    if section and more then
        if sell then line(tt, "Vendor", API.FormatMoney(sell)) end
        if buy then line(tt, "Vendors sell", API.FormatMoney(buy)) end
        for _, r in ipairs(rows) do line(tt, r[1], r[2]) end
    end
    for owner, fn in pairs(providers) do
        if owner ~= FIRST then pcall(fn, tt, id) end
    end
end

local function linkID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- A tooltip can hear about the same item more than once (and through both
-- hooks below), so each tooltip remembers what it already has until it's cleared.
local function watchClear(tt)
    if tt.skHooked or not tt.HookScript then return end
    tt.skHooked = true
    pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.skItem = nil end)
end

local function add(tt, id)
    if not (tt and id) then return end
    watchClear(tt)
    if tt.skItem == id then return end
    tt.skItem = id
    ns.AddTooltipLines(tt, id)
end

-- Clients differ in how item tooltips are filled, so hook both ways.
local function hook()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if not id and tt and tt.GetItem then id = linkID(select(2, tt:GetItem())) end
            add(tt, id)
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                add(self, linkID(select(2, self:GetItem())))
            end)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", hook)
