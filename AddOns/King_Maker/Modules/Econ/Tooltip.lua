local _, KM = ...
local ns = KM.Module("Econ")

-- Econ King's lines in item tooltips, under Scanner King's prices: the 30-day
-- average, how today compares, and the weekly trend. /ek tooltip off hides them.

local function addLines(tt, id)
    if not (ns.db and ns.db.ui.tooltip) then return end
    local s = ns.Stats(id)
    if not s or not s.avg30 then return end
    local function row(l, r)
        if ScannerKing and ScannerKing.TooltipLine then ScannerKing.TooltipLine(tt, l, r) else tt:AddDoubleLine(l, r, 1, 0.82, 0, 1, 1, 1) end
    end
    row("30-day average", ns.Money(s.avg30) .. (s.vs30 and ("  (now " .. ns.Percent(s.vs30, true) .. ")") or ""))
    if s.trend7 or s.supply then
        row("7-day trend", ns.Percent(s.trend7) .. (s.supply and ("   supply " .. ns.Percent(s.supply)) or ""))
    end
    if ns.db.fav[id] then tt:AddLine("|T" .. ns.STAR .. ":12|t Price History favorite", 0.6, 0.6, 0.6) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if ScannerKing and ScannerKing.AddTooltipProvider then
        ScannerKing.AddTooltipProvider("Econ_King", addLines)
    end
end)
