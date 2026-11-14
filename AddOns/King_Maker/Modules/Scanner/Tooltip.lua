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
--   Disenchant    the average value of disenchanting one (also in the verdict: DISENCHANT)
--   Craft cost    to make one, and the profit after the cut; You can craft it: which of your characters
--   Teaches       a recipe item: what it teaches, who knows it, who can learn it, whose skill is too low
--   Drops         the mobs with the best drop chance (Farm: your kills and your guild's, QuestieDB)
--   Used in       professions with recipes that take it, then the 3 most valuable things made from it
--   Shopping list on one of your lists: how many you have of how many you want
--   You own       how many, and on which character (Inventory's provider), then anyone else's lines
-- The crafting rows come from TooltipCraft.lua. Each group can be switched off (ui.tip, /sk tip), and the short
-- tooltip shows only the header, verdict, price and what you own until you hold Shift.
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
local TAG = { AUCTION = { 1, 0.82, 0 }, VENDOR = { 1, 0.6, 0.25 }, DISENCHANT = { 0.75, 0.55, 1 } }
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

-- Drops and Used in, and the crafting rows (TooltipCraft.lua), worked out once per item for a little while: Drops
-- walks every mob you know and the crafting rows every recipe that uses the item.
local cache, cacheAt = {}, 0
local function try(fn, id)
    if not fn then return nil end
    local ok, v = pcall(fn, id)
    return ok and v or nil
end
local function extras(id)
    local now = GetTime and GetTime() or 0
    if now - cacheAt > 30 then wipe(cache); cacheAt = now end
    local x = cache[id]
    if not x then
        x = { drops = try(drops, id), uses = try(uses, id), best = try(ns.TipBestCrafts, id), make = try(ns.TipMake, id),
              pattern = try(ns.TipPattern, id), de = try(ns.TipDisenchant, id), goal = try(ns.TipGoal, id) }
        cache[id] = x
    end
    return x
end
function ns.TooltipSources(id)
    local x, rows = extras(id), {}
    if x.drops then rows[#rows + 1] = { "Drops", x.drops } end
    if x.uses then rows[#rows + 1] = { "Used in", x.uses } end
    return rows
end
function ns.ClearTooltipCache() wipe(cache) end

-- Which rows show (Settings > Scanner, /sk tip): ui.tip[key].
local function on(key) return ns.db.ui.tip and ns.db.ui.tip[key] end

-- Short tooltip: only the header, the verdict, the price and how many you own, until you hold Shift.
local function short()
    return on("short") and not (IsShiftKeyDown and IsShiftKeyDown())
end
API.TooltipShort = short

local function signed(v)
    if v >= 0 then return "|cff4cff4c+|r" .. API.FormatMoney(v) end
    return "|cffff5050-|r" .. API.FormatMoney(-v)
end

local function itemText(id)
    local name, q
    if C_Item and C_Item.GetItemInfo then
        local ok, n, _, quality = pcall(C_Item.GetItemInfo, id)
        if ok then name, q = n, quality end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    local hex = KM.UI and KM.UI.QUALITY and KM.UI.QUALITY[q or 1] or "ffffff"
    return "|cff" .. hex .. (name or ("Item " .. id)) .. "|r"
end

-- Which pays most for one: the auction house after its cut, a vendor, or disenchanting it (when it can be).
local LOSER = { AUCTION = "the auction house", VENDOR = "vendoring", DISENCHANT = "disenchanting" }
local function verdict(ah, sell, de)
    local opts = {}
    if ah then opts[#opts + 1] = { "AUCTION", math.floor(ah * CUT) } end
    if sell then opts[#opts + 1] = { "VENDOR", sell } end
    if de then opts[#opts + 1] = { "DISENCHANT", math.floor(de) } end
    if #opts < 2 then return nil end
    table.sort(opts, function(a, b) return a[2] > b[2] end)
    local best, second = opts[1], opts[2]
    local diff = API.FormatMoney(best[2] - second[2])
    if best[1] == "AUCTION" then return "AUCTION", "Pays " .. diff .. " more than " .. LOSER[second[1]] .. "." end
    if best[1] == "VENDOR" then return "VENDOR", "Vendor it: " .. diff .. " more than " .. LOSER[second[1]] .. "." end
    return "DISENCHANT", "Disenchant it: about " .. diff .. " more than " .. LOSER[second[1]] .. "."
end

function ns.AddTooltipLines(tt, id)
    if not (ns.db and tt and id) then return end
    local pr = ns.db.ui.tooltip and ns.db.prices[id]
    local more = ns.db.ui.sources
    local x = extras(id)
    local buy = more and vendorBuy(id)
    local sell = vendorSell(id)
    local de = on("de") and x.de
    local make = on("make") and x.make
    local pattern = on("pattern") and x.pattern
    local best = on("crafts") and x.best
    local goal = on("goal") and x.goal
    local owned = InventoryKing and InventoryKing.GetCount and select(2, pcall(InventoryKing.GetCount, id))
    local section = pr or buy or make or pattern or goal or (more and (x.drops or x.uses))
        or (type(owned) == "number" and owned > 0)
    local brief = section and short()
    if section then
        tt:AddLine(" ") -- a gap between the game's lines (or another addon's) and ours
        local tag, says = verdict(pr and (pr.m or pr.p), sell, de)
        local tc = tag and TAG[tag] or WHITE
        line(tt, "King Maker", tag or " ", HEAD, tc)
        if says then tt:AddLine(says, tc[1], tc[2], tc[3]) end
        if pr then
            local age = API.PriceAge(pr.t) .. (pr.from and (", " .. pr.from) or "")
            line(tt, "Auction house", API.FormatMoney(pr.m or pr.p) .. "  " .. grey(age))
            if not brief then
                if pr.m then line(tt, "Lowest buyout", API.FormatMoney(pr.p)) end
                if pr.q then line(tt, "Listed", pr.q .. (pr.n and (" in " .. pr.n .. " auction" .. (pr.n == 1 and "" or "s")) or "")) end
            end
        end
    end
    if brief then
        tt:AddLine("Hold Shift for details", 0.55, 0.55, 0.55)
    else
        if providers[FIRST] then pcall(providers[FIRST], tt, id) end
        if section then
            if more and sell then line(tt, "Vendor", API.FormatMoney(sell)) end
            if buy then line(tt, "Vendors sell", API.FormatMoney(buy)) end
            if de then line(tt, "Disenchant", "about " .. API.FormatMoney(de)) end
            if make then
                if make.cost then
                    line(tt, "Craft cost", API.FormatMoney(make.cost)
                        .. (make.profit and ("  " .. grey("profit") .. " " .. signed(make.profit)) or ""))
                end
                if make.who then line(tt, "You can craft it", make.who) end
            end
            if pattern then
                line(tt, "Teaches", pattern.teaches
                    .. (pattern.prof and grey("  " .. pattern.prof .. " " .. (pattern.skill or "")) or ""))
                if pattern.known then line(tt, "Known by", pattern.known) end
                if pattern.can then line(tt, "Can learn it", pattern.can) end
                if pattern.low then line(tt, "Skill too low", pattern.low) end
            end
            if more and x.drops then line(tt, "Drops", x.drops) end
            if more and x.uses then line(tt, "Used in", x.uses) end
            if best then
                if not (more and x.uses) then line(tt, "Used in", " ") end
                for _, b in ipairs(best) do
                    line(tt, "   " .. itemText(b.item) .. (b.made > 1 and grey(" x" .. b.made) or ""),
                        API.FormatMoney(b.value) .. (b.profit and ("  " .. signed(b.profit)) or ""))
                end
            end
            if goal then line(tt, "Shopping list", goal) end
        end
    end
    for owner, fn in pairs(providers) do
        if owner ~= FIRST then pcall(fn, tt, id) end
    end
end

-- Holding or letting go of Shift redraws a short tooltip.
local mf = CreateFrame("Frame")
KM.Register(mf, "MODIFIER_STATE_CHANGED")
mf:SetScript("OnEvent", function(_, _, key)
    if not (ns.db and on("short")) or not (key == "LSHIFT" or key == "RSHIFT") then return end
    local tt = GameTooltip
    if tt and tt.IsShown and tt:IsShown() and tt.skItem and tt.RefreshData then
        tt.skItem = nil
        pcall(tt.RefreshData, tt)
    end
end)

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
