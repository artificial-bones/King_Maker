local _, ns = ...
local API = ns.API

-- Prices in item tooltips: market price (from a Deep Scan), lowest buyout and
-- how many are listed, wherever the item shows up: bags, bank, loot, links,
-- the auction house. Other addons can add their own lines under ours:
--
--   ScannerKing.AddTooltipProvider("Econ_King", function(tooltip, itemID) ... end)
--
-- /sk tooltip off turns it all off.

local providers = {}

function API.AddTooltipProvider(owner, fn)
    providers[owner] = fn
end

local GOLD, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.55, 0.55, 0.55 }

local function line(tt, left, right, lc, rc)
    lc, rc = lc or GOLD, rc or WHITE
    tt:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
end

function ns.AddTooltipLines(tt, id)
    if not (ns.db and tt and id) then return end
    local pr = ns.db.ui.tooltip and ns.db.prices[id]
    if pr then
        if pr.m then line(tt, "Market price", API.FormatMoney(pr.m)) end
        line(tt, pr.m and "Lowest buyout" or "Auction price", API.FormatMoney(pr.p))
        if pr.q then line(tt, "Listed", pr.q .. (pr.n and (" in " .. pr.n .. " auction" .. (pr.n == 1 and "" or "s")) or "")) end
        line(tt, " ", "Scanner King, " .. API.PriceAge(pr.t) .. (pr.from and (" from " .. pr.from) or ""), GREY, GREY)
    end
    for _, fn in pairs(providers) do pcall(fn, tt, id) end
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
