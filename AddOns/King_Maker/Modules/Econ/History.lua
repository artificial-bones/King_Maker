local _, KM = ...
local ns = KM.Module("Econ")
local API = ns.API

-- Price and supply history.
--
-- Every scan adds a point per item it saw:
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
-- How much detail is kept (Settings > Price History, ns.db.keep):
--   every scan          for keep.raw days (7; the 7-day numbers and "gone per day" read these)
--   a point a day       until keep.day days old (30; every 30-day number reads these). Favorites: forever.
--   a point a week      until 180 days old
--   a point per 4 weeks after that
-- Items nobody has listed for keep.forget days (90; 0 = never) are forgotten. Favorites never are.
--
-- Saved shape (schema 2, King Maker 2.6.1): ONE string per item, every number in base 36:
--     items[id] = "n:seen:last/month/week/day/raw"
--   n      how many scans are behind it      seen   when it was last listed
--   last   the time of the newest point in raw ("=" when that's seen; blank when raw is empty)
--   each level: its points oldest first, split by ";", each "dt:m:p:q:n:a:r:c:g:cm:cp:cq:cn" in the order above
--   (blank = not measured, trailing blanks trimmed, c left out when 1)
--     dt   raw: "A".."Z" = 1 to 26 scans after the reference scan ("." and a number for more), else seconds since
--          the point before (the first point: the time itself). Scans are numbered (db.scans[k].i); the reference
--          scan is that of the latest point before that sits on a scan.
--          day, week, month: days since the point before (the first point: days since 1970)
--     "="  as lowest: the same as market; as auctions: the same as listed
--     g    left out of a raw point when it's the gap saved on its scan (db.scans[i].g)
--   Day, week and month points leave out the gap (only the last 7 days use it, and those are always raw),
--   and week and month points leave out added as well.
-- A quick scan's point that only repeats the item's last one from under 15 minutes before (the same lowest
-- and listed, no market price) isn't kept: the scan still counts towards n and seen.
-- Schema 1 (King Maker 2.6.0 and Econ King) was { r = {str}, d = {str}, w = {str}, n, seen } with decimal
-- "t:m:p:..." strings. ns.Migrate converts it in the background a few items per frame, and anything that reads
-- an old item converts it first, so a conversion cut short by /reload or logout just carries on next time.

local DAY, WEEK, MONTH = 86400, 7 * 86400, 28 * 86400
local WEEK_KEEP = 180 * DAY      -- week points older than this become 4-week points
local ZERO_KEEP = 30 * DAY       -- keep noting "none listed" for items seen in the last 30 days
local DIFF_GAP = 2 * DAY         -- compare listings only between Deep Scans this close together
local REPEAT = 15 * 60           -- a quick scan repeating the last point within this long adds nothing
local SCANS_KEEP = 2000
local SCHEMA = 2

-- Settings: { default, min, max } in days (forget: 0 = never).
ns.KEEP = { raw = { 7, 7, 30 }, day = { 30, 14, 180 }, forget = { 90, 0, 365 } }

local T, M, P, Q, N, A, R, C, G = 1, 2, 3, 4, 5, 6, 7, 8, 9
local CM, CP, CQ, CN = 10, 11, 12, 13
local COUNT = { [M] = CM, [P] = CP, [Q] = CQ, [N] = CN } -- where each average's scan count goes
ns.F = { T = T, M = M, P = P, Q = Q, N = N, A = A, R = R, C = C, G = G }

-- The levels, in the order they sit in the string (oldest first).
local MON, WK, DY, RAW = 1, 2, 3, 4
ns.LEVEL = { month = MON, week = WK, day = DY, raw = RAW }
local LEVEL_NAME = { "month", "week", "day", "raw" }

-- How many scans a field's value stands for.
local function weight(v, k)
    if not v[k] then return 0 end
    return v[COUNT[k]] or v[C] or 1
end

local function byTime(a, b) return a[T] < b[T] end

-- The settings, each clamped to its range.
function ns.Keep()
    local k = ns.db and ns.db.keep or {}
    local out = {}
    for key, d in pairs(ns.KEEP) do
        local v = tonumber(k[key]) or d[1]
        out[key] = math.max(d[2], math.min(d[3], math.floor(v)))
    end
    out.day = math.max(out.day, out.raw)
    return out
end

---------------------------------------------------------------------------
-- Base 36
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local SMALL = {}
for i = 0, 1295 do
    local hi, lo = math.floor(i / 36), i % 36
    SMALL[i] = (hi > 0 and DIGITS:sub(hi + 1, hi + 1) or "") .. DIGITS:sub(lo + 1, lo + 1)
end
local MAX36 = 2 ^ 53             -- whole numbers stay exact up to here

local function b36(x)
    x = math.floor(x + 0.5)
    if x < 0 then return "-" .. b36(-x) end
    if x < 1296 then return SMALL[x] end
    if x > MAX36 then x = MAX36 end -- (copper prices never come near it)
    local s = ""
    while x > 0 do
        local d = x % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        x = (x - d) / 36
    end
    return s
end
ns.B36 = b36

local tonumber = tonumber
-- tonumber(s, 36) reads at most 32 bits in the game's Lua (4294967295, about 429k gold): prices that can be bigger
-- (a placeholder listing at 9,999,999g) are read in two halves once they're 7 digits long.
local function big36(s)
    if #s < 7 then return tonumber(s, 36) end
    local hi, lo = tonumber(s:sub(1, -6), 36), tonumber(s:sub(-5), 36)
    return hi and lo and hi * 60466176 + lo or nil
end
ns.Big36 = big36
-- tonumber(s, 36) wraps a minus sign round to 2^32, so signed values (time steps only) go through here.
local function signed36(s)
    if s:byte(1) == 45 then return -(tonumber(s:sub(2), 36) or 0) end
    return tonumber(s, 36)
end

---------------------------------------------------------------------------
-- Scans: each has a number (i), so a raw point can say "the next scan" in one letter instead of its time, and
-- the gap its added/gone cover (g), so raw points needn't repeat it
---------------------------------------------------------------------------

local gapAt, scanAt, seqAt, timeOf, mapN, mapLast

-- gapAt[t] = gap, scanAt[t] = scan entry, seqAt[t] = scan number (the highest when two share a second),
-- timeOf[i] = time. Numbers the scans that don't have one yet (2.6.0's), oldest first.
local function scanMaps()
    local db = ns.db
    local sc = db.scans
    local last = sc[#sc]
    local lt = last and last.t
    if not gapAt or mapN ~= #sc or mapLast ~= lt then
        gapAt, scanAt, seqAt, timeOf = {}, {}, {}, {}
        local top = db.scanSeq or 0
        for _, s in ipairs(sc) do
            if type(s) == "table" and s.i and s.i > top then top = s.i end
        end
        for _, s in ipairs(sc) do
            if type(s) == "table" and s.t then
                if not s.i then top = top + 1; s.i = top end
                if s.g then gapAt[s.t] = s.g end
                if not scanAt[s.t] or s.k == "deep" then scanAt[s.t] = s end
                if not seqAt[s.t] or s.i > seqAt[s.t] then seqAt[s.t] = s.i end
                timeOf[s.i] = s.t
            end
        end
        db.scanSeq = top
        mapN, mapLast = #sc, lt
    end
    return gapAt, scanAt, seqAt, timeOf
end

-- The time step of a raw point at scan `seq` after one whose reference scan is `ps`: "A".."Z" for 1 to 26 scans
-- on, "." and the count beyond that; nil when it can't be said in scans.
local function scanStep(ps, seq)
    if not (ps and seq and seq > ps) then return nil end
    local k = seq - ps
    if k <= 26 then return string.char(64 + k) end
    return "." .. b36(k)
end

---------------------------------------------------------------------------
-- Points and levels
---------------------------------------------------------------------------

local function field(x) return x and b36(x) or "" end
local function same(x, y) return x and y and math.floor(x + 0.5) == math.floor(y + 0.5) end

-- One point; dt is its time step, already written. gap: the gap saved on its scan (raw points), left out when it matches.
local function encodePoint(v, dt, level, gap)
    local a, g = v[A], v[G]
    if level ~= RAW or (g and gap and same(g, gap)) then g = nil end
    if level <= WK then a = nil end
    local c = v[C]
    if c == 1 then c = nil end
    local parts = { dt, field(v[M]), same(v[P], v[M]) and "=" or field(v[P]), field(v[Q]),
        same(v[N], v[Q]) and "=" or field(v[N]), field(a), field(v[R]), field(c), field(g),
        field(v[CM]), field(v[CP]), field(v[CQ]), field(v[CN]) }
    local last = 13
    while last > 1 and parts[last] == "" do last = last - 1 end
    return table.concat(parts, ":", 1, last)
end

-- A level's points (sorted oldest first) into its string, and the time of the last one.
-- Raw: a point on a scan after the reference scan is written as the scan step; after every point the reference
-- becomes that point's scan, when it has one (decodeLevel follows the same rule).
local function encodeLevel(points, level)
    if #points == 0 then return "", nil end
    local raw = level == RAW
    local unit = raw and 1 or DAY
    local gaps, seqs
    if raw then gaps, _, seqs = scanMaps() end
    local parts, prev, ps = {}, nil, nil
    for i, v in ipairs(points) do
        local tt = math.floor(v[T] / unit + 0.5)
        local seq = seqs and seqs[tt]
        local dt = prev and scanStep(ps, seq) or b36(prev and (tt - prev) or tt)
        parts[i] = encodePoint(v, dt, level, gaps and gaps[tt])
        prev, ps = tt, seq or ps
    end
    return table.concat(parts, ";"), points[#points][T]
end

local PATTERN = "^([^:]*)" .. string.rep(":?([^:]*)", 12)

-- Appends a level's points to out, decoded: { t, market, lowest, listed, auctions, added, gone, scans, gap, ... }.
local function decodeLevel(str, level, out)
    out = out or {}
    if not str or str == "" then return out end
    local unit = level == RAW and 1 or DAY
    local gaps, seqs, times
    if level == RAW then gaps, _, seqs, times = scanMaps() end
    local t, ps, started
    for s in str:gmatch("[^;]+") do
        local dt, m, p, q, n, a, r, c, g, cm, cp, cq, cn = s:match(PATTERN)
        local b = dt:byte(1)
        local step = seqs and b and ((b >= 65 and b <= 90 and b - 64) or (b == 46 and (tonumber(dt:sub(2), 36) or 0)))
        local seq
        if step then
            seq = ps and ps + step
            t = seq and times[seq] -- nil if that scan isn't listed any more: the point is skipped
        else
            local d = signed36(dt) or 0
            t = (not started and d) or (t and t + d) or nil
        end
        started = true
        if seqs then ps = (t and seqs[t]) or seq or ps end
        if t then
            local mm, qq = big36(m), tonumber(q, 36)
            local v = { t * unit, mm, p == "=" and mm or big36(p), qq, n == "=" and qq or tonumber(n, 36),
                        tonumber(a, 36), tonumber(r, 36), tonumber(c, 36), tonumber(g, 36),
                        tonumber(cm, 36), tonumber(cp, 36), tonumber(cq, 36), tonumber(cn, 36) }
            if gaps then
                if not v[G] and (v[A] or v[R]) then v[G] = gaps[v[T]] end
            elseif not v[C] then
                v[C] = 1 -- a rolled-up point of one scan
            end
            out[#out + 1] = v
        end
    end
    return out
end
ns.DecodeLevel = decodeLevel

-- The time of a level's first point, without reading the rest.
local function firstTime(str, level)
    local d = str and str:match("^(%-?%w+)")
    if not d then return nil end
    return (signed36(d) or 0) * (level == RAW and 1 or DAY)
end

-- Schema 1 point strings (decimal "t:m:p:q:n:a:r:c:g:cm:cp:cq:cn").
local V1 = "^([^:]*)" .. string.rep(":?([^:]*)", 12)
function ns.DecodeV1(s)
    local t, m, p, q, n, a, r, c, g, cm, cp, cq, cn = s:match(V1)
    return { tonumber(t), tonumber(m), tonumber(p), tonumber(q), tonumber(n), tonumber(a), tonumber(r), tonumber(c),
             tonumber(g), tonumber(cm), tonumber(cp), tonumber(cq), tonumber(cn) }
end

---------------------------------------------------------------------------
-- Items: "n:seen:last/month/week/day/raw" <-> { n, seen, last, [1..4] = level strings }
---------------------------------------------------------------------------

local HEAD = "^([^/]*)/([^/]*)/([^/]*)/([^/]*)/(.*)$"

local function unpackItem(s)
    local h, mo, wk, dy, rw = s:match(HEAD)
    if not h then return nil end
    local n, seen, last = h:match("^([^:]*):?([^:]*):?([^:]*)")
    seen = tonumber(seen, 36)
    return { n = tonumber(n, 36) or 0, seen = seen, last = last == "=" and seen or tonumber(last, 36), mo, wk, dy, rw }
end

local function packItem(rec)
    local raw, last = rec[RAW], ""
    if raw ~= "" and rec.last then last = rec.last == rec.seen and "=" or b36(rec.last) end
    return b36(rec.n or 0) .. ":" .. (rec.seen and b36(rec.seen) or "") .. ":" .. last
        .. "/" .. rec[MON] .. "/" .. rec[WK] .. "/" .. rec[DY] .. "/" .. raw
end

-- About how many bytes an item takes in the saved file, either shape (the game writes `[id] = "...",`).
local function sizeOf(id, it)
    local base = #tostring(id) + 8
    if type(it) == "string" then return base + #it end
    if type(it) ~= "table" then return 0 end
    local n = base + 40 -- braces, seen and n
    for _, k in ipairs({ "r", "d", "w" }) do
        n = n + 10
        for _, s in ipairs(it[k] or {}) do n = n + #tostring(s) + 4 end
    end
    return n
end
ns.SizeOf = sizeOf

local function decodeV1List(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, s in ipairs(list) do
        if type(s) == "string" then
            local v = ns.DecodeV1(s)
            if v[T] then out[#out + 1] = v end
        end
    end
    table.sort(out, byTime)
    return out
end

-- Schema 1 item -> record. Each scan's gap moves onto the scan, so the points can leave it out.
local function fromV1(it)
    local raw = decodeV1List(it.r)
    local _, scans = scanMaps()
    local changed = false
    for _, v in ipairs(raw) do
        local sc = v[G] and (v[A] or v[R]) and scans[v[T]]
        if sc and not sc.g then sc.g = math.floor(v[G] + 0.5); changed = true end
    end
    if changed then gapAt = nil end
    local day, week = decodeV1List(it.d), decodeV1List(it.w)
    local n = tonumber(it.n)
    if not n then
        n = 0
        for _, list in ipairs({ raw, day, week }) do for _, v in ipairs(list) do n = n + (v[C] or 1) end end
    end
    local rec = { n = n, seen = tonumber(it.seen), "", "", "", "" }
    rec[WK] = encodeLevel(week, WK)
    rec[DY] = encodeLevel(day, DY)
    rec[RAW], rec.last = encodeLevel(raw, RAW)
    return rec
end

-- An item's record (converting an old one first), or nil.
function ns.Get(id)
    local it = ns.db.items[id]
    if type(it) == "string" then return unpackItem(it) end
    if type(it) == "table" then
        local before = sizeOf(id, it)
        local rec = fromV1(it)
        local s = packItem(rec)
        ns.db.items[id] = s
        local mig = ns.db.migration
        if mig then mig.before, mig.after, mig.done = mig.before + before, mig.after + sizeOf(id, s), mig.done + 1 end
        return rec
    end
end

local function put(id, rec) ns.db.items[id] = packItem(rec) end

local function item(id)
    local rec = ns.Get(id)
    if not rec then
        rec = { n = 0, "", "", "", "" }
        put(id, rec)
    end
    return rec
end

-- Adds a point to the end of raw; gap: the gap saved on its scan. A scan step only when the last point sits on a
-- scan (then that's decodeLevel's reference scan at the end of the string).
local function appendRaw(rec, v, gap)
    local raw = rec[RAW]
    local dt
    if raw ~= "" and rec.last then
        local _, _, seqs = scanMaps()
        dt = scanStep(seqs[rec.last], seqs[v[T]]) or b36(v[T] - rec.last)
    else
        dt = b36(v[T])
    end
    local s = encodePoint(v, dt, RAW, gap)
    rec[RAW] = raw == "" and s or (raw .. ";" .. s)
    rec.last = v[T]
end

-- Every point, oldest first.
local function allPoints(rec)
    local out = {}
    for level = MON, RAW do decodeLevel(rec[level], level, out) end
    return out
end

-- The newest point's time in any level.
local function lastTime(rec)
    if rec[RAW] ~= "" and rec.last then return rec.last end
    for level = DY, MON, -1 do
        if rec[level] ~= "" then
            local pts = decodeLevel(rec[level], level)
            return pts[#pts] and pts[#pts][T]
        end
    end
end

-- The points of one level of an item (tests, /ek status).
function ns.Points(id, levelName)
    local rec = ns.Get(id)
    if not rec then return {} end
    return decodeLevel(rec[ns.LEVEL[levelName]], ns.LEVEL[levelName])
end

---------------------------------------------------------------------------
-- Rolling up
---------------------------------------------------------------------------

-- Several points into one, starting at time t: averages for price and supply,
-- each weighted by how many scans had it; totals for added, gone and the gap.
local AVERAGED = { M, P, Q, N }
local SUMMED = { A, R, G }
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
        for _, k in ipairs(SUMMED) do
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

-- Splits list at cutoff: the points to keep, and the older ones.
local function split(list, cutoff)
    local keep, old = {}, {}
    for _, v in ipairs(list) do
        if v[T] < cutoff then old[#old + 1] = v else keep[#keep + 1] = v end
    end
    return keep, old
end

-- Folds points into list's buckets of `size` (joining a bucket that's already there).
local function rollInto(list, points, size)
    local at = {}
    for i, v in ipairs(list) do at[v[T]] = i end
    local groups, order = {}, {}
    for _, v in ipairs(points) do
        local b = math.floor(v[T] / size) * size
        if not groups[b] then groups[b] = {}; order[#order + 1] = b end
        table.insert(groups[b], v)
    end
    for _, b in ipairs(order) do
        local pts = groups[b]
        local i = at[b]
        if i then
            table.insert(pts, 1, list[i])
            list[i] = merge(pts, b)
        else
            list[#list + 1] = merge(pts, b)
            at[b] = #list
        end
    end
    table.sort(list, byTime)
end

local cache = {}

function ns.Forget(id)
    ns.db.items[id] = nil
    if not ns.db.fav[id] then ns.db.info[id] = nil end
    ns.db.listings[id] = nil
    cache[id] = nil
end

-- Rolls an item's old points into coarser levels, or forgets it. Returns "forgot", "rolled" or nil.
function ns.Compact(id, now)
    local rec = ns.Get(id)
    if not rec then return end
    now = now or ns.Now()
    local keep = ns.Keep()
    local fav = ns.db.fav[id]
    if keep.forget > 0 and not fav then
        local seen = rec.seen or lastTime(rec)
        if not seen or now - seen > keep.forget * DAY then
            ns.Forget(id)
            return "forgot"
        end
    end
    local rawCut, dayCut, weekCut = now - keep.raw * DAY, now - keep.day * DAY, now - WEEK_KEEP
    local function older(level, cut)
        local t = firstTime(rec[level], level)
        return t and t < cut
    end
    if not (older(RAW, rawCut) or (not fav and older(DY, dayCut)) or older(WK, weekCut)) then return end
    local raw, day = decodeLevel(rec[RAW], RAW), decodeLevel(rec[DY], DY)
    local week, month = decodeLevel(rec[WK], WK), decodeLevel(rec[MON], MON)
    local old
    raw, old = split(raw, rawCut)
    if #old > 0 then rollInto(day, old, DAY) end
    if not fav then
        day, old = split(day, dayCut)
        if #old > 0 then rollInto(week, old, WEEK) end
    end
    week, old = split(week, weekCut)
    if #old > 0 then rollInto(month, old, MONTH) end
    rec[MON] = encodeLevel(month, MON)
    rec[WK] = encodeLevel(week, WK)
    rec[DY] = encodeLevel(day, DY)
    rec[RAW], rec.last = encodeLevel(raw, RAW)
    put(id, rec)
    cache[id] = nil
    return "rolled"
end

---------------------------------------------------------------------------
-- Background work: a batch of items per frame, so a whole auction house
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
    while n < job.batch and job.i <= #job.ids do
        pcall(job.fn, job.ids[job.i])
        job.i, n = job.i + 1, n + 1
    end
    if job.i > #job.ids then
        table.remove(jobs, 1)
        if job.done then pcall(job.done) end
    end
end

-- Calls fn(id) for every id, `batch` (150) per frame, then done().
function ns.Background(ids, fn, done, batch)
    table.insert(jobs, { ids = ids, fn = fn, done = done, i = 1, batch = batch or BATCH })
    if not jobRunning then
        jobRunning = true
        C_Timer.After(0, runJobs)
    end
end

function ns.Busy() return jobRunning end

local function allIds()
    local ids = {}
    for id in pairs(ns.db.items) do ids[#ids + 1] = id end
    return ids
end

---------------------------------------------------------------------------
-- Size: what /ek status and Compact now report
---------------------------------------------------------------------------

local function countPoints(s, into)
    local rec = unpackItem(s)
    if not rec then return end
    for level = MON, RAW do
        local str = rec[level]
        if str ~= "" then
            local _, semis = str:gsub(";", "")
            into[level] = (into[level] or 0) + semis + 1
        end
    end
end

-- About how big Price History is in the saved file, and how many points it holds (per level, when asked).
function ns.SavedSize(withPoints)
    local db = ns.db
    local bytes, items, points = 0, 0, withPoints and { 0, 0, 0, 0 } or nil
    for id, it in pairs(db.items) do
        bytes, items = bytes + sizeOf(id, it), items + 1
        if points then
            if type(it) == "string" then
                countPoints(it, points)
            elseif type(it) == "table" then
                points[WK] = points[WK] + #(it.w or {})
                points[DY] = points[DY] + #(it.d or {})
                points[RAW] = points[RAW] + #(it.r or {})
            end
        end
    end
    for id, c in pairs(db.info) do
        if type(c) == "table" then
            bytes = bytes + #tostring(id) + 12 + (c.name and #c.name + 14 or 0) + (c.q and 10 or 0) + (c.icon and 20 or 0)
        else
            bytes = bytes + #tostring(id) + #tostring(c) + 8
        end
    end
    for id, s in pairs(db.listings) do bytes = bytes + #tostring(id) + #tostring(s) + 8 end
    bytes = bytes + #db.scans * 45
    return bytes, items, points
end

function ns.FormatBytes(b)
    if not b then return "-" end
    if b >= 1048576 then return string.format("%.1f MB", b / 1048576) end
    return string.format("%d KB", math.floor(b / 1024 + 0.5))
end

---------------------------------------------------------------------------
-- Converting schema 1 (2.6.0) data
---------------------------------------------------------------------------

local MIGRATE_BATCH = 50
local migrating = false

-- Starts (or carries on with) converting old items; true if there was anything to do.
function ns.Migrate(done)
    local db = ns.db
    local ids, icons, books = {}, {}, {}
    for id, it in pairs(db.items) do if type(it) == "table" then ids[#ids + 1] = id end end
    for id, c in pairs(db.info) do if type(c) == "table" then icons[#icons + 1] = id end end
    for id, l in pairs(db.listings) do if type(l) == "string" and l:byte(1) ~= 35 then books[#books + 1] = id end end
    if #ids == 0 and #icons == 0 and #books == 0 then
        db.v, db.migration = SCHEMA, nil
        return false
    end
    if migrating then return true end
    migrating = true
    db.migration = db.migration or { before = 0, after = 0, done = 0, started = ns.Now() }
    db.migration.total = db.migration.done + #ids
    -- The name cache becomes "quality:name" strings; icons are the game's to look up (instant), so they go.
    ns.Background(icons, function(id) ns.PackInfo(id) end, nil, 500)
    ns.Background(books, function(id) ns.PackListings(id) end, nil, 200)
    ns.Background(ids, function(id) ns.Get(id) end, function()
        migrating = false
        local mig = db.migration
        db.v, db.migration = SCHEMA, nil
        if mig and mig.done > 0 then
            db.sizeLog = { t = ns.Now(), what = "convert", before = mig.before, after = mig.after }
            KM.Print(ns, "Price History now takes less space: " .. KM.Commas(mig.done) .. " items converted, about "
                .. ns.FormatBytes(mig.before) .. " -> " .. ns.FormatBytes(mig.after) .. ".")
        end
        if done then pcall(done) end
    end, MIGRATE_BATCH)
    return true
end

function ns.Migrating() return migrating, ns.db and ns.db.migration end

-- Rolls up and forgets across every item in the background, then calls done(before, after, forgot, rolled).
-- quiet (at login): no sizes, which would mean reading every item in one frame.
function ns.CompactAll(done, quiet)
    local now = ns.Now()
    local before = not quiet and ns.SavedSize() or nil
    local forgot, rolled = 0, 0
    ns.Background(allIds(), function(id)
        local r = ns.Compact(id, now)
        if r == "forgot" then forgot = forgot + 1 elseif r == "rolled" then rolled = rolled + 1 end
    end, function()
        local after = not quiet and ns.SavedSize() or nil
        if not quiet then
            ns.db.sizeLog = { t = ns.Now(), what = "compact", before = before, after = after, forgot = forgot, rolled = rolled }
        end
        if done then pcall(done, before, after, forgot, rolled) end
        if ns.Refresh then ns.Refresh() end
    end, MIGRATE_BATCH)
end

-- Settings > Price History > Compact now, and /ek compact.
function ns.CompactNow()
    if not ns.db then return end
    KM.Print(ns, "Compacting Price History...")
    ns.CompactAll(function(before, after, forgot)
        local _, items, pts = ns.SavedSize(true)
        local total = pts[1] + pts[2] + pts[3] + pts[4]
        KM.Print(ns, "Price History compacted: about " .. ns.FormatBytes(before) .. " -> " .. ns.FormatBytes(after) .. ", "
            .. KM.Commas(items) .. " items, " .. KM.Commas(total) .. " points kept"
            .. (forgot > 0 and (", " .. KM.Commas(forgot) .. " items not seen for a long time forgotten") or "") .. ".")
    end)
end

---------------------------------------------------------------------------
-- Listings: what sold (or was pulled) between two Deep Scans
---------------------------------------------------------------------------

-- The last full Deep Scan's listings per item (db.listings[id]), saved as "#" and then, cheapest first, each price
-- as the step up from the one before and "*units" when that's more than 1, all in base 36:
--     "#q2w*2,2s*5,2s" = 2 at 33800c, 5 at 33900c, 1 at 34000c
-- 2.6.0 saved "33800x2,33900x5,34000x1" (decimal, in auction order). Both read; ns.Migrate rewrites the old ones.

-- { { price, count }, ... } from a scan -> { [price] = units }, prices rounded to the copper.
local function listingMap(list)
    local map = {}
    for _, l in ipairs(list) do
        local u = math.floor(l[1] + 0.5)
        map[u] = (map[u] or 0) + l[2]
    end
    return map
end

local function listingString(map)
    local prices = {}
    for u in pairs(map) do prices[#prices + 1] = u end
    table.sort(prices)
    local parts, prev = {}, 0
    for i, u in ipairs(prices) do
        local c = map[u]
        parts[i] = b36(u - prev) .. (c == 1 and "" or ("*" .. b36(c)))
        prev = u
    end
    return "#" .. table.concat(parts, ",")
end

-- Either shape -> { [price] = units }, total units.
local function parseListings(s)
    local map, units = {}, 0
    s = type(s) == "string" and s or ""
    if s:byte(1) == 35 then
        local price = 0
        for e in s:gmatch("[^,#]+") do
            local step, c = e:match("^([^*]*)%*?(.*)$")
            price = price + (big36(step) or 0)
            local n = c == "" and 1 or (tonumber(c, 36) or 0)
            map[price] = (map[price] or 0) + n
            units = units + n
        end
    else
        for u, c in s:gmatch("(%d+)x(%d+)") do
            u, c = tonumber(u), tonumber(c)
            map[u] = (map[u] or 0) + c
            units = units + c
        end
    end
    return map, units
end

local function compareMaps(b, a)
    local added, gone = 0, 0
    for u, c in pairs(a) do added = added + math.max(0, c - (b[u] or 0)) end
    for u, c in pairs(b) do gone = gone + math.max(0, c - (a[u] or 0)) end
    return added, gone
end

-- Units added and gone between two listing strings (either shape).
function ns.CompareListings(before, after)
    return compareMaps(parseListings(before), (parseListings(after)))
end

-- A 2.6.0 listing string into the compact one (ns.Migrate).
function ns.PackListings(id)
    local s = ns.db.listings[id]
    if type(s) == "string" and s:byte(1) ~= 35 then ns.db.listings[id] = listingString((parseListings(s))) end
end
ns.ParseListings = parseListings

---------------------------------------------------------------------------
-- Recording a scan
---------------------------------------------------------------------------

local cacheTime = 0

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

-- Whether a quick scan's point only repeats the item's last one from moments before (Market and Material Scans
-- run seconds after each other and see the same listings): no market price, added or gone, the same lowest and
-- listed (and auctions, when counted), within REPEAT.
local function repeats(rec, v, now)
    if v[M] or v[A] or v[R] or rec[RAW] == "" or not rec.last or now - rec.last > REPEAT or now < rec.last then return false end
    local _, m, p, q, n = rec[RAW]:match("([^;]*)$"):match(PATTERN)
    local mm, qq = big36(m), tonumber(q, 36)
    p = p == "=" and mm or big36(p)
    n = n == "=" and qq or tonumber(n, 36)
    return same(p, v[P]) and same(qq, v[Q]) and (v[N] == nil or same(n, v[N])) or false
end

-- When an item was last listed, read from the front of its string.
local function seenOf(it)
    if type(it) == "string" then return tonumber(it:match("^[^:/]*:([^:/]*)"), 36) end
    if type(it) == "table" then return tonumber(it.seen) end
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
    -- The scan first: its number, and its gap (what its points' added and gone cover).
    scanMaps() -- numbers any scans from before 2.6.1 first
    ns.db.scanSeq = (ns.db.scanSeq or 0) + 1
    local scan = { t = now, k = kind, n = 0, g = gap, i = ns.db.scanSeq }
    table.insert(ns.db.scans, scan)
    while #ns.db.scans > SCANS_KEEP do table.remove(ns.db.scans, 1) end
    local n = 0
    for id, r in pairs(results) do
        if type(id) == "number" and type(r) == "table" and (r.p or r.q) then
            local added, gone
            if newListings and r.l then
                local map = listingMap(r.l)
                newListings[id] = listingString(map)
                if diff then added, gone = compareMaps(parseListings(ns.db.listings[id]), map) end
            end
            local rec = item(id)
            -- Market only from a full Deep Scan; other scans only see the lowest price.
            local v = { now, r.m, r.p, r.q, r.n, added, gone, nil, added and gap }
            if not repeats(rec, v, now) then appendRaw(rec, v, gap) end
            rec.seen, rec.n = now, rec.n + 1
            put(id, rec)
            n = n + 1
        end
    end
    if complete then
        -- Items that were on the auction house lately but aren't now: none listed.
        local zero = {}
        for id, it in pairs(ns.db.items) do
            local seen = seenOf(it)
            if not results[id] and seen and now - seen <= ZERO_KEEP then zero[#zero + 1] = id end
        end
        for _, id in ipairs(zero) do
            local rec = ns.Get(id)
            if rec then
                local gone
                if diff and ns.db.listings[id] then gone = select(2, parseListings(ns.db.listings[id])) end
                appendRaw(rec, { now, nil, nil, 0, 0, diff and 0 or nil, gone, nil, diff and gap or nil }, gap)
                rec.n = rec.n + 1
                put(id, rec)
            end
        end
        ns.db.lastDeep = now
    end
    if newListings then ns.db.listings, ns.db.listingsTime = newListings, now end
    scan.n = n
    wipe(cache)
    cacheTime = now
    -- Roll up old points, then work out every item's numbers ahead of time.
    local ids = allIds()
    ns.Background(ids, function(id) ns.Compact(id, now) end, nil, MIGRATE_BATCH)
    ns.Background(ids, function(id) ns.Stats(id) end, function() if ns.Refresh then ns.Refresh() end end)
    return n
end

---------------------------------------------------------------------------
-- Reading history
---------------------------------------------------------------------------

-- Every point for an item, oldest first, decoded.
function ns.Series(id)
    local rec = ns.Get(id)
    if not rec then return {} end
    return allPoints(rec)
end

function API.GetHistory(id) return ns.Series(id) end

-- The numbers for an item, worked out once per scan:
--   market, lowest, listed, auctions, seen   the latest point (market and lowest from the latest point that had a price)
--   avg7, avg30, prev7       average market price: last 7 days, last 30 days, the 7 days before the last 7
--   low30, high30, vol30     lowest and highest market price in 30 days; volatility (spread / average)
--   listed30                 average number listed over 30 days
--   gonePerDay               units gone (sold, cancelled or expired) per day over the last 7 days, when known
--   vs30, supply             current price vs the 30-day average; listed now vs the 30-day average
--   trend7, trendDays        avg7 vs prev7; until there are two weeks of scans, the later half of the days there are
--                            against the earlier half (trendDays says how many days)
--   listed7, supply7         average number listed over 7 days; listed now vs that
--   corr, corrN              how price and supply move together over 30 days (-1 to 1), from corrN scans
--   auctions, auctionsAt     auctions in the latest scan that counted them (only Deep Scans do)
--   first, points            when tracking started; how many scans are behind it
--   lowestOnly               no full Deep Scan has priced it in 30 days, so the price figures use the lowest buyout
function ns.Stats(id)
    checkCache()
    local s = cache[id]
    if s ~= nil then return s or nil end
    local rec = ns.Get(id)
    if not rec then cache[id] = false; return nil end
    local now = ns.Now()
    s = {}

    -- Only the last month needs reading point by point: raw and day, and week when day doesn't reach back a month.
    local recent = decodeLevel(rec[RAW], RAW)
    decodeLevel(rec[DY], DY, recent)
    local fd = firstTime(rec[DY], DY)
    if not fd or fd > now - 31 * DAY then decodeLevel(rec[WK], WK, recent) end
    if #recent == 0 then decodeLevel(rec[MON], MON, recent) end
    local hasMarket = false
    for _, v in ipairs(recent) do
        if v[M] and now - v[T] <= 30 * DAY then hasMarket = true; break end
    end
    -- Price figures use the market price; without a full Deep Scan lately, the lowest buyout.
    local K = hasMarket and M or P
    s.lowestOnly = not hasMarket or nil

    local acc = { avg7 = { 0, 0 }, avg30 = { 0, 0 }, prev7 = { 0, 0 }, listed30 = { 0, 0 }, listed7 = { 0, 0 } }
    local week, pairs30 = {}, {} -- { t, price, weight } in the last 7 days; { price, listed } in the last 30
    local function addTo(a, value, w) a[1], a[2] = a[1] + value * w, a[2] + w end
    local sq, goneSum, gapSum = 0, 0, 0
    for _, v in ipairs(recent) do
        local t = v[T]
        if not s.seen or t > s.seen then s.seen, s.listed = t, v[Q] end
        if v[N] and (not s.auctionsAt or t > s.auctionsAt) then s.auctionsAt, s.auctions = t, v[N] end
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
            if age <= 30 * DAY and v[Q] then table.insert(pairs30, { v[K], v[Q] }) end
            if age <= 7 * DAY then addTo(acc.avg7, v[K], w); table.insert(week, { t, v[K], w })
            elseif age <= 14 * DAY then addTo(acc.prev7, v[K], w) end
        end
        if age <= 30 * DAY and v[Q] then addTo(acc.listed30, v[Q], weight(v, Q)) end
        if age <= 7 * DAY and v[Q] then addTo(acc.listed7, v[Q], weight(v, Q)) end
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
    if s.avg7 and s.prev7 and s.prev7 > 0 then
        s.trend7 = (s.avg7 - s.prev7) / s.prev7
    elseif s.avg7 and s.avg7 > 0 and #week >= 4 then
        -- No week before this one yet: the average price over the later half of the days there are, against the
        -- earlier half (weighted like the averages).
        local t0, t1 = math.huge, 0
        for _, x in ipairs(week) do t0, t1 = math.min(t0, x[1]), math.max(t1, x[1]) end
        local span, mid = (t1 - t0) / DAY, (t0 + t1) / 2
        local early, late = { 0, 0 }, { 0, 0 }
        for _, x in ipairs(week) do addTo(x[1] < mid and early or late, x[2], x[3]) end
        if span >= 2 and early[2] > 0 and late[2] > 0 and early[1] > 0 then
            s.trend7 = (late[1] / late[2]) / (early[1] / early[2]) - 1
            s.trendDays = math.floor(span + 0.5)
        end
    end
    if s.listed and s.listed30 and s.listed30 > 0 then s.supply = (s.listed - s.listed30) / s.listed30 end
    if s.listed and s.listed7 and s.listed7 > 0 then s.supply7 = (s.listed - s.listed7) / s.listed7 end
    -- Price against supply (Pearson's r over the month's scans): near -1, the price drops when more are listed.
    if #pairs30 >= 6 then
        local n, sx, sy, sxx, syy, sxy = #pairs30, 0, 0, 0, 0, 0
        for _, x in ipairs(pairs30) do
            sx, sy, sxx, syy, sxy = sx + x[1], sy + x[2], sxx + x[1] * x[1], syy + x[2] * x[2], sxy + x[1] * x[2]
        end
        local vx, vy = n * sxx - sx * sx, n * syy - sy * sy
        if vx > 0 and vy > 0 then s.corr, s.corrN = (n * sxy - sx * sy) / math.sqrt(vx * vy), n end
    end
    for level = MON, RAW do
        s.first = firstTime(rec[level], level)
        if s.first then break end
    end
    s.days = s.first and (now - s.first) / DAY or 0
    s.points = rec.n
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
            local rec = item(id)
            local last = lastTime(rec)
            if not last or r.t > last then
                appendRaw(rec, { r.t, r.m, r.p, r.q })
                rec.n = rec.n + 1
                rec.seen = math.max(rec.seen or 0, r.t)
                put(id, rec)
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
    -- Old data first (a few items a frame), then roll up, then the numbers for every item.
    ns.Migrate()
    ns.CompactAll(nil, true)
    ns.Background(allIds(), function(id) ns.Stats(id) end)
    if ScannerKing and ScannerKing.RegisterCallback then
        ScannerKing.RegisterCallback("Econ_King", function(event, results, kind, method)
            if event == "GUILD_PRICES" then
                if ns.RecordGuild(results) > 0 and ns.Refresh then ns.Refresh() end
            elseif event == "SCAN_RESULTS" then
                local n = ns.Record(results, kind, method)
                if kind == "deep" and n > 0 then KM.Print(ns, "Recorded " .. n .. " items from the Deep Scan.") end
                if ns.Refresh then ns.Refresh() end
            end
        end)
    end
end)
