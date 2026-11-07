local _, ns = ...
local API = ns.API

-- Net worth over time: one point a day, for every character. Today's point is
-- updated as things change; days you didn't play carry the last one forward.

local DAY = 86400
local KEEP = 730 -- days

local function today() return math.floor(ns.Now() / DAY) end

function ns.Snapshot()
    if not ns.db then return end
    local point = {}
    for _, c in ipairs(ns.Characters()) do
        point[c.who] = { g = c.gold + c.mail, a = math.floor(c.assets) }
    end
    local d = today()
    ns.db.history[d] = point
    for day in pairs(ns.db.history) do
        if day < d - KEEP then ns.db.history[day] = nil end
    end
end

-- The last n days, oldest first: { { day, label, gold, assets, total } }.
-- who: one character (or "Warband"), or nil for everyone.
function ns.Series(n, who)
    local d = today()
    local days = {}
    for day in pairs(ns.db.history) do table.insert(days, day) end
    table.sort(days)
    local last -- the newest point on or before each day
    local j = 1
    local out = {}
    for day = d - n + 1, d do
        while days[j] and days[j] <= day do last = ns.db.history[days[j]]; j = j + 1 end
        local g, a = 0, 0
        for k, v in pairs(last or {}) do
            if not who or k == who then g, a = g + (v.g or 0), a + (v.a or 0) end
        end
        table.insert(out, { day = day, label = date and date("%m-%d", day * DAY) or tostring(day),
            gold = g, assets = a, total = g + a, known = last ~= nil })
    end
    return out
end

-- { { day, gold, assets, total } } for the last n days (default 30).
function API.GetHistory(n, who)
    if not ns.db then return {} end
    return ns.Series(n or 30, who)
end

-- New prices change what everything is worth.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if ScannerKing and ScannerKing.RegisterCallback then
        ScannerKing.RegisterCallback("Inventory_King", function(event)
            if event == "SCAN_FINISHED" or event == "GUILD_PRICES" then
                ns.Snapshot()
                if ns.Refresh then ns.Refresh() end
            end
        end)
    end
end)
