local _, ns = ...

-- Econ King's lines in item tooltips, under Scanner King's prices: the 30-day
-- average, how today compares, and the weekly trend. /ek tooltip off hides them.

local function addLines(tt, id)
    if not (ns.db and ns.db.ui.tooltip) then return end
    local s = ns.Stats(id)
    if not s or not s.avg30 then return end
    tt:AddDoubleLine("30-day average", ns.Money(s.avg30) .. (s.vs30 and ("  (now " .. ns.Percent(s.vs30, true) .. ")") or ""),
        1, 0.82, 0, 1, 1, 1)
    if s.trend7 or s.supply then
        tt:AddDoubleLine("7-day trend", ns.Percent(s.trend7) .. (s.supply and ("   supply " .. ns.Percent(s.supply)) or ""),
            1, 0.82, 0, 1, 1, 1)
    end
    if ns.db.fav[id] then tt:AddLine("|T" .. ns.STAR .. ":12|t Econ King favorite", 0.6, 0.6, 0.6) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if ScannerKing and ScannerKing.AddTooltipProvider then
        ScannerKing.AddTooltipProvider("Econ_King", addLines)
    end
end)
