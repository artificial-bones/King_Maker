local _, ns = ...
local API = ns.API

-- Price and supply history.
--
-- Every scan adds a point per item it saw. A point is a short string, so a
-- year of a whole auction house still loads quickly:
--     "time:market:lowest:listed:auctions:added:gone:scans:gap:..."
--   market   market price in copper (full Deep Scans only)
--   lowest   lowest buyout in copper
--   listed   units on the auction house (0 when a Deep Scan didn't find any)
--   auctions number of auctions
--   added    units newly listed since the last Deep Scan  (full Deep Scans only)
--   gone     units that disappeared since the last Deep Scan: sold, cancelled
--            or expired. The closest thing to sales the game lets us see.
--   scans    how many scans this point stands for (1 unless rolled up)
--   gap      seconds between the two Deep Scans that added and gone cover
--   then, for rolled-up points only, how many of the scans had a market price,
--   lowest, listed and auctions (when that's fewer than all of them), so each
--   average keeps its true weight when it's rolled up again.
--
-- Each item keeps:   r = every scan from the last 7 days,
--                    d = one point per day after that, up to 120 days,
--                    w = one point per week after that.
-- Favorites keep a point per day forever.

local DAY, WEEK = 86400, 7 * 86400
local RAW_KEEP = 7 * DAY
local DAILY_KEEP = 120 * DAY
local ZERO_KEEP = 30 * DAY      -- keep noting "none listed" for items seen in the last 30 days
local DIFF_GAP = 2 * DAY        -- compare listings only between Deep Scans this close together
local SCANS_KEEP = 2000

local T, M, P, Q, N, A, R, C, G = 1, 2, 3, 4, 5, 6, 7, 8, 9
local FIELDS = 13
local COUNT = { [M] = 10, [P] = 11, [Q] = 12, [N] = 13 } -- where each average's scan count goes
ns.F = { T = T, M = M, P = P, Q = Q, N = N, A = A, R = R, C = C, G = G }

-- How many scans a field's value stands for.
local function weight(v, k)
    if not v[k] then return 0 end
    return v[COUNT[k]] or v[C] or 1
end

---------------------------------------------------------------------------
-- Points
---------------------------------------------------------------------------

function ns.Encode(v)
    local parts, last = {}, 1
    for i = 1, FIELDS do
        local x = v[i]
        if x then
            parts[i] = tostring(math.floor(x + 0.5))
            last = i
        else
            parts[i] = ""
        end
    end
    return table.concat(parts, ":", 1, last)
end

local PATTERN = "^([^:]*)" .. string.rep(":?([^:]*)", FIELDS - 1)
local tonumber = tonumber

-- One pattern match per point: this runs for thousands of items at a time.
function ns.Decode(s)
    local t, m, p, q, n, a, r, c, g, cm, cp, cq, cn = s:match(PATTERN)
    return { tonumber(t), tonumber(m), tonumber(p), tonumber(q), tonumber(n), tonumber(a), tonumber(r), tonumber(c),
             tonumber(g), tonumber(cm), tonumber(cp), tonumber(cq), tonumber(cn) }
end

local function timeOf(s) return tonumber(s:match("^(%d+)")) end

-- Several points into one, starting at time t: averages for price and supply,
-- each weighted by how many scans had it; totals for added, gone and the gap.
local AVERAGED = { M, P, Q, N }
local function merge(points, t)
    local sum, cnt = {}, {}
    local out = { t }
    local scans = 0
    for _, v in ipairs(points) do
        scans = scans + (v[C] or 1)
        for _, k in ipairs(AVERAGED) do
            local w = weight(v, k)
            if w > 0 then sum[k] = (sum[k] or 0) + v[k] * w; cnt[k] = (cnt[k] or 0) + w end
        end
        for _, k in ipairs({ A, R, G }) do
            if v[k] then out[k] = (out[k] or 0) + v[k] end
        end
    end
    out[C] = scans
    for k, s in pairs(sum) do
        out[k] = s / cnt[k]
        if cnt[k] ~= scans then out[COUNT[k]] = cnt[k] end
    end
    return out
end

-- Moves points older than cutoff from list `from` into buckets of `size` in list `to`.
local function rollUp(from, to, cutoff, size)
    if not from[1] or timeOf(from[1]) >= cutoff then return end
    local keep, buckets, order = {}, {}, {}
    for _, s in ipairs(from) do
        local v = ns.Decode(s)
        if v[T] < cutoff then
            local b = math.floor(v[T] / size) * size
            if not buckets[b] then buckets[b] = {}; table.insert(order, b) end
            table.insert(buckets[b], v)
        else
            table.insert(keep, s)
        end
    end
    for _, b in ipairs(order) do
        local pts = buckets[b]
        local lastTo = to[#to]
        if lastTo and timeOf(lastTo) == b then
            table.insert(pts, 1, ns.Decode(lastTo))
            to[#to] = ns.Encode(merge(pts, b))
        else
            table.insert(to, ns.Encode(merge(pts, b)))
        end
    end
    for i = #from, 1, -1 do from[i] = nil end
    for i, s in ipairs(keep) do from[i] = s end
end

function ns.Compact(id, now)
    local it = ns.db.items[id]
    if not it then return end
    now = now or ns.Now()
    rollUp(it.r, it.d, now - RAW_KEEP, DAY)
    if not ns.db.fav[id] then rollUp(it.d, it.w, now - DAILY_KEEP, WEEK) end
end

function ns.CompactAll()
    local now = ns.Now()
    for id in pairs(ns.db.items) do ns.Compact(id, now) end
end

---------------------------------------------------------------------------
-- Background work: a few hundred items per frame, so a whole auction house
-- never freezes the game.
---------------------------------------------------------------------------

local BATCH = 150
local jobs, jobRunning = {}, false

local function runJobs()
    local job = jobs[1]
    if not job then jobRunning = false; return end
    local n = 0
    -- Always come back next frame, even if one item's data is bad.
    C_Timer.After(0, runJobs)
    while n < BATCH and job.i <= #job.ids do
        pcall(job.fn, job.ids[job.i])
        job.i, n = job.i + 1, n + 1
    end
    if job.i > #job.ids then
        table.remove(jobs, 1)
        if job.done then pcall(job.done) end
    end
end

-- Calls fn(id) for every id, a batch per frame, then done().
function ns.Background(ids, fn, done)
    table.insert(jobs, { ids = ids, fn = fn, done = done, i = 1 })
    if not jobRunning then
        jobRunning = true
        C_Timer.After(0, runJobs)
    end
end

function ns.Busy() return jobRunning end

local function item(id)
    local it = ns.db.items[id]
    if not it then
        it = { r = {}, d = {}, w = {}, n = 0 }
        ns.db.items[id] = it
    end
    return it
end

---------------------------------------------------------------------------
-- Listings: what sold (or was pulled) between two Deep Scans
---------------------------------------------------------------------------

-- "price x count, ..." with prices rounded to the copper.
local function listingString(list)
    local byPrice, order = {}, {}
    for _, l in ipairs(list) do
        local u = math.floor(l[1] + 0.5)
        if not byPrice[u] then byPrice[u] = 0; table.insert(order, u) end
        byPrice[u] = byPrice[u] + l[2]
    end
    local parts = {}
    for _, u in ipairs(order) do table.insert(parts, u .. "x" .. byPrice[u]) end
    return table.concat(parts, ",")
end

local function parseListings(s)
    local map, units = {}, 0
    for u, c in (s or ""):gmatch("(%d+)x(%d+)") do
        map[u] = (map[u] or 0) + tonumber(c)
        units = units + tonumber(c)
    end
    return map, units
end

-- Units added and gone between two listing strings.
function ns.CompareListings(before, after)
    local b, a = parseListings(before), parseListings(after)
    local added, gone = 0, 0
    for u, c in pairs(a) do added = added + math.max(0, c - (b[u] or 0)) end
    for u, c in pairs(b) do gone = gone + math.max(0, c - (a[u] or 0)) end
    return added, gone
end

---------------------------------------------------------------------------
-- Recording a scan
---------------------------------------------------------------------------

local cache, cacheTime = {}, 0

-- Numbers are kept until the next scan, or an hour at most, so "last 7 days" stays true.
local function checkCache()
    local now = ns.Now()
    if now - cacheTime > 3600 then wipe(cache); cacheTime = now end
end

-- Stats only if they're already worked out: stats (or nil) and whether they're still missing.
function ns.CachedStats(id)
    checkCache()
    local s = cache[id]
    if s == nil then return nil, true end
    return s or nil, false
end

function ns.Record(results, kind, method)
    if not ns.db or type(results) ~= "table" then return 0 end
    local now = ns.Now()
    local deep = kind == "deep"
    local full = deep and method == "replicate"
    local complete = deep and method ~= "partial"
    local diff = full and ns.db.listingsTime and now - ns.db.listingsTime <= DIFF_GAP
    local gap = diff and (now - ns.db.listingsTime) or nil
    local newListings = full and {} or nil
    local n = 0
    for id, r in pairs(results) do
        if type(id) == "number" and type(r) == "table" and (r.p or r.q) then
            local added, gone
            if newListings and r.l then
                local s = listingString(r.l)
                newListings[id] = s
                if diff then added, gone = ns.CompareListings(ns.db.listings[id], s) end
            end
            local it = item(id)
            -- Market only from a full Deep Scan; other scans only see the lowest price.
            table.insert(it.r, ns.Encode({ now, r.m, r.p, r.q, r.n, added, gone, nil, added and gap }))
            it.seen, it.n = now, (it.n or 0) + 1
            n = n + 1
        end
    end
    if complete then
        -- Items that were on the auction house lately but aren't now: none listed.
        for id, it in pairs(ns.db.items) do
            if not results[id] and it.seen and now - it.seen <= ZERO_KEEP then
                local gone
                if diff and ns.db.listings[id] then gone = select(2, parseListings(ns.db.listings[id])) end
                table.insert(it.r, ns.Encode({ now, nil, nil, 0, 0, diff and 0 or nil, gone, nil, diff and gap or nil }))
                it.n = (it.n or 0) + 1
            end
        end
        ns.db.lastDeep = now
    end
    if newListings then ns.db.listings, ns.db.listingsTime = newListings, now end
    table.insert(ns.db.scans, { t = now, k = kind, n = n })
    while #ns.db.scans > SCANS_KEEP do table.remove(ns.db.scans, 1) end
    wipe(cache)
    cacheTime = now
    -- Roll up old points, then work out every item's numbers ahead of time.
    local ids = {}
    for id in pairs(ns.db.items) do table.insert(ids, id) end
    ns.Background(ids, function(id) ns.Compact(id, now) end)
    ns.Background(ids, function(id) ns.Stats(id) end, function() if ns.Refresh then ns.Refresh() end end)
    return n
end

---------------------------------------------------------------------------
-- Reading history
---------------------------------------------------------------------------

-- Every point for an item, oldest first, decoded.
function ns.Series(id)
    local it = ns.db.items[id]
    local out = {}
    if not it then return out end
    for _, list in ipairs({ it.w, it.d, it.r }) do
        for _, s in ipairs(list) do table.insert(out, ns.Decode(s)) end
    end
    return out
end

function API.GetHistory(id) return ns.Series(id) end

-- The numbers for an item, worked out once per scan:
--   market, lowest, listed, auctions, seen   the latest point (market and lowest from the latest point that had a price)
--   avg7, avg30, prev7       average market price: last 7 days, last 30 days, the 7 days before the last 7
--   low30, high30, vol30     lowest and highest market price in 30 days; volatility (spread / average)
--   listed30                 average number listed over 30 days
--   gonePerDay               units gone (sold, cancelled or expired) per day over the last 7 days, when known
--   vs30, trend7, supply     current price vs the 30-day average; avg7 vs prev7; listed now vs the 30-day average
--   first, points            when tracking started; how many scans are behind it
--   lowestOnly               no full Deep Scan has priced it in 30 days, so the price figures use the lowest buyout
function ns.Stats(id)
    checkCache()
    local s = cache[id]
    if s ~= nil then return s or nil end
    local it = ns.db.items[id]
    if not it then cache[id] = false; return nil end
    local now = ns.Now()
    s = {}

    -- Only the last month needs reading point by point.
    local recent, older, hasMarket = {}, 0, false
    for _, list in ipairs({ it.r, it.d, it.w }) do
        for i = #list, 1, -1 do
            local str = list[i]
            if now - timeOf(str) > 31 * DAY and #recent > 0 then
                older = older + i
                break
            end
            local v = ns.Decode(str)
            if v[M] and now - v[T] <= 30 * DAY then hasMarket = true end
            table.insert(recent, v)
        end
    end
    -- Price figures use the market price; without a full Deep Scan lately, the lowest buyout.
    local K = hasMarket and M or P
    s.lowestOnly = not hasMarket or nil

    local acc = { avg7 = { 0, 0 }, avg30 = { 0, 0 }, prev7 = { 0, 0 }, listed30 = { 0, 0 } }
    local function addTo(a, value, w) a[1], a[2] = a[1] + value * w, a[2] + w end
    local sq, goneSum, gapSum, scans = 0, 0, 0, 0
    for _, v in ipairs(recent) do
        local t = v[T]
        scans = scans + (v[C] or 1)
        if not s.seen or t > s.seen then s.seen, s.listed, s.auctions = t, v[Q], v[N] end
        if v[K] and (not s.priced or t > s.priced) then s.priced, s.market = t, v[K] end
        if v[P] and (not s.lowestAt or t > s.lowestAt) then s.lowestAt, s.lowest = t, v[P] end
        local age = now - t
        local w = weight(v, K)
        if w > 0 then
            if age <= 30 * DAY then
                addTo(acc.avg30, v[K], w)
                sq = sq + v[K] * v[K] * w
                s.low30 = math.min(s.low30 or v[K], v[K])
                s.high30 = math.max(s.high30 or v[K], v[K])
            end
            if age <= 7 * DAY then addTo(acc.avg7, v[K], w)
            elseif age <= 14 * DAY then addTo(acc.prev7, v[K], w) end
        end
        if age <= 30 * DAY and v[Q] then addTo(acc.listed30, v[Q], weight(v, Q)) end
        -- Gone per day: units gone over the time between the Deep Scans that saw them go.
        if age <= 7 * DAY and v[R] and v[G] and v[G] > 0 then
            goneSum, gapSum = goneSum + v[R], gapSum + v[G]
        end
    end
    for k, a in pairs(acc) do if a[2] > 0 then s[k] = a[1] / a[2] end end
    if s.avg30 and acc.avg30[2] > 1 and s.avg30 > 0 then
        local var = math.max(0, sq / acc.avg30[2] - s.avg30 * s.avg30)
        s.vol30 = math.sqrt(var) / s.avg30
    end
    if gapSum > 0 then s.gonePerDay = goneSum / (gapSum / DAY) end
    if s.market and s.avg30 and s.avg30 > 0 then s.vs30 = (s.market - s.avg30) / s.avg30 end
    if s.avg7 and s.prev7 and s.prev7 > 0 then s.trend7 = (s.avg7 - s.prev7) / s.prev7 end
    if s.listed and s.listed30 and s.listed30 > 0 then s.supply = (s.listed - s.listed30) / s.listed30 end
    local firstList = (it.w[1] and it.w) or (it.d[1] and it.d) or it.r
    s.first = firstList[1] and timeOf(firstList[1])
    s.days = s.first and (now - s.first) / DAY or 0
    s.points = it.n or (scans + older) -- it.n counts every scan; older saved data only has an estimate
    cache[id] = s
    return s
end

function API.GetStats(id) return ns.Stats(id) end

-- Prices guildmates sent (an answer to "Ask guild", or their shared Trade
-- Goods): each becomes a point in the item's history when it's newer than
-- anything we have, so their scans fill the gaps between yours.
function ns.RecordGuild(batch)
    if not ns.db or type(batch) ~= "table" then return 0 end
    local n = 0
    for id, r in pairs(batch) do
        if type(id) == "number" and type(r) == "table" and r.t and r.p then
            local it = item(id)
            local last = it.r[#it.r] or it.d[#it.d] or it.w[#it.w]
            if not last or r.t > timeOf(last) then
                table.insert(it.r, ns.Encode({ r.t, r.m, r.p, r.q }))
                it.n = (it.n or 0) + 1
                it.seen = math.max(it.seen or 0, r.t)
                n = n + 1
            end
        end
    end
    if n > 0 then wipe(cache) end
    return n
end

function ns.ClearStats() wipe(cache); cacheTime = ns.Now() end

---------------------------------------------------------------------------
-- Hearing about scans
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not ns.db then return end
    local ids = {}
    for id in pairs(ns.db.items) do table.insert(ids, id) end
    ns.Background(ids, function(id) ns.Compact(id) end)
    ns.Background(ids, function(id) ns.Stats(id) end)
    if ScannerKing and ScannerKing.RegisterCallback then
        ScannerKing.RegisterCallback("Econ_King", function(event, results, kind, method)
            if event == "GUILD_PRICES" then
                if ns.RecordGuild(results) > 0 and ns.Refresh then ns.Refresh() end
            elseif event == "SCAN_RESULTS" then
                local n = ns.Record(results, kind, method)
                if kind == "deep" and n > 0 then ns.Print("Recorded " .. n .. " items from the Deep Scan.") end
                if ns.Refresh then ns.Refresh() end
            end
        end)
    end
end)
