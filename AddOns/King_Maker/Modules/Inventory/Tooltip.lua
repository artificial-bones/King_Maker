local _, KM = ...
local ns = KM.Module("Inventory")

-- Item tooltips: how many you own and where.
--
--   Inventory King: 85 owned                 worth 8g 50s
--     Jay        bags 20, bank 40, mail 10
--     Alt        bags 15
--
-- Under Scanner King's prices when it's installed, on its own otherwise.
-- /ik tooltip off turns it off.

local SHORT = { bags = "bags", bank = "bank", mail = "mail", ah = "on AH" }
local MAX_CHARS = 8

function ns.AddTooltipLines(tt, id)
    if not (ns.db and ns.db.ui.tooltip and tt and id) then return end
    local total, by = ns.API.GetCount(id)
    if total == 0 then return end
    local each = ns.Price(id)
    tt:AddDoubleLine("Inventory King: " .. total .. " owned", each and ("worth " .. ns.Money(each * total)) or " ",
        0.38, 0.75, 1, 1, 1, 1)
    local list = {}
    for who, n in pairs(by) do table.insert(list, { who, n }) end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    for i, c in ipairs(list) do
        if i > MAX_CHARS then
            tt:AddLine("  and " .. (#list - MAX_CHARS) .. " more", 0.6, 0.6, 0.6)
            break
        end
        local s, bits = ns.db.stock[c[1]] or {}, {}
        for _, place in ipairs(ns.PLACES) do
            local n = (s[place] or {})[id]
            if n and n > 0 then table.insert(bits, SHORT[place] .. " " .. n) end
        end
        tt:AddDoubleLine("  " .. ns.CharText(c[1]), table.concat(bits, ", "), 1, 1, 1, 0.8, 0.8, 0.8)
    end
end

local function linkID(link) return link and tonumber(link:match("item:(%d+)")) end

-- A tooltip can hear about the same item more than once: each remembers what it has until cleared.
local function add(tt, id)
    if not (tt and id) then return end
    if not tt.ikHooked and tt.HookScript then
        tt.ikHooked = true
        pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.ikItem = nil end)
    end
    if tt.ikItem == id then return end
    tt.ikItem = id
    ns.AddTooltipLines(tt, id)
end

local function hook()
    if ScannerKing and ScannerKing.AddTooltipProvider then
        ScannerKing.AddTooltipProvider("Inventory_King", function(tt, id) ns.AddTooltipLines(tt, id) end)
        return
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if not id and tt and tt.GetItem then id = linkID(select(2, tt:GetItem())) end
            add(tt, id)
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) add(self, linkID(select(2, self:GetItem()))) end)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", hook)
