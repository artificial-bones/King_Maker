local _, ns = ...

-- A small line and bar chart drawn with textures.
--
--   local g = ns.CreateGraph(parent, width, height)
--   g:Draw({
--       tmin = t0, tmax = t1,
--       series = { { pts = { { t, value }, ... }, color = { r, g, b }, style = "line" or "bars" }, ... },
--       format = function(value) return text end,   -- y-axis labels
--       zero = true,                                -- start the y-axis at 0
--       hover = function(t) ... end,                -- fill GameTooltip for the point nearest the mouse
--   })
-- Long series are averaged into buckets a few pixels wide.

local Graph = {}
Graph.__index = Graph

local LEFT, RIGHT, TOP, BOTTOM = 70, 8, 6, 16
local fmtDate = date or (os and os.date)

local function dateText(t, span)
    if not fmtDate then return tostring(t) end
    if span <= 2 * 86400 then return fmtDate("%d %b %H:%M", t) end
    return fmtDate("%d %b %Y", t)
end

function ns.CreateGraph(parent, w, h)
    local g = setmetatable({ w = w, h = h, lines = {}, bars = {}, dots = {} }, Graph)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    g.frame = f
    g.pw, g.ph = w - LEFT - RIGHT, h - TOP - BOTTOM

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.4)
    bg:SetPoint("TOPLEFT", LEFT, -TOP)
    bg:SetPoint("BOTTOMRIGHT", -RIGHT, BOTTOM)

    g.ylabels, g.grid = {}, {}
    for i = 0, 2 do
        local line = f:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, i == 0 and 0.25 or 0.08)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", LEFT, BOTTOM + g.ph * i / 2)
        line:SetPoint("BOTTOMRIGHT", -RIGHT, BOTTOM + g.ph * i / 2)
        g.grid[i] = line
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("RIGHT", f, "BOTTOMLEFT", LEFT - 4, BOTTOM + g.ph * i / 2)
        label:SetJustifyH("RIGHT")
        g.ylabels[i] = label
    end
    g.xlabels = {}
    for i, anchor in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOP" .. (anchor == "CENTER" and "" or anchor), f, "BOTTOMLEFT", LEFT + g.pw * (i - 1) / 2, BOTTOM - 2)
        g.xlabels[i] = label
    end
    g.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    g.empty:SetPoint("CENTER", LEFT / 2, BOTTOM / 2)

    g.cursor = f:CreateTexture(nil, "OVERLAY")
    g.cursor:SetColorTexture(1, 1, 1, 0.35)
    g.cursor:SetWidth(1)
    g.cursor:Hide()

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() f:SetScript("OnUpdate", function() g:Hover() end) end)
    f:SetScript("OnLeave", function()
        f:SetScript("OnUpdate", nil)
        g.cursor:Hide()
        GameTooltip:Hide()
    end)
    return g
end

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------

local function take(pool, make)
    pool.used = (pool.used or 0) + 1
    local o = pool[pool.used]
    if not o then
        o = make()
        pool[pool.used] = o
    end
    if o then o:Show() end
    return o
end

local function release(pool)
    for i = 1, #pool do pool[i]:Hide() end
    pool.used = 0
end

function Graph:Segment(x1, y1, x2, y2, color)
    local f = self.frame
    if not f.CreateLine then return false end
    local l = take(self.lines, function()
        local line = f:CreateLine(nil, "ARTWORK")
        if line and line.SetThickness then line:SetThickness(2) end
        return line
    end)
    if not l then self.lines.used = self.lines.used - 1; return false end
    l:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    l:SetStartPoint("BOTTOMLEFT", f, LEFT + x1, BOTTOM + y1)
    l:SetEndPoint("BOTTOMLEFT", f, LEFT + x2, BOTTOM + y2)
    return true
end

function Graph:Dot(x, y, color, size)
    local d = take(self.dots, function() return self.frame:CreateTexture(nil, "ARTWORK") end)
    size = size or 3
    d:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    d:SetSize(size, size)
    d:ClearAllPoints()
    d:SetPoint("CENTER", self.frame, "BOTTOMLEFT", LEFT + x, BOTTOM + y)
end

function Graph:Bar(x, width, height, color)
    local b = take(self.bars, function() return self.frame:CreateTexture(nil, "ARTWORK") end)
    b:SetColorTexture(color[1], color[2], color[3], color[4] or 0.8)
    b:SetSize(math.max(1, width), math.max(1, height))
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", LEFT + x - width / 2, BOTTOM)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- Averages points into at most n buckets across [tmin, tmax].
local function bucket(pts, tmin, tmax, n)
    if #pts <= n then return pts end
    local size = (tmax - tmin) / n
    local out, cur, sumT, sumV, cnt = {}, nil, 0, 0, 0
    for _, p in ipairs(pts) do
        local b = math.min(n - 1, math.floor((p[1] - tmin) / size))
        if cur and b ~= cur then
            table.insert(out, { sumT / cnt, sumV / cnt })
            sumT, sumV, cnt = 0, 0, 0
        end
        cur = b
        sumT, sumV, cnt = sumT + p[1], sumV + p[2], cnt + 1
    end
    if cnt > 0 then table.insert(out, { sumT / cnt, sumV / cnt }) end
    return out
end

function Graph:Draw(spec)
    release(self.lines); release(self.bars); release(self.dots)
    self.spec = spec
    self.hoverPts = nil
    local tmin, tmax = spec.tmin, spec.tmax
    local any, ymin, ymax = false, math.huge, -math.huge
    local drawn = {}
    for i, s in ipairs(spec.series) do
        local pts = {}
        for _, p in ipairs(s.pts) do
            if p[2] and p[1] >= tmin and p[1] <= tmax then table.insert(pts, p) end
        end
        pts = bucket(pts, tmin, tmax, math.max(10, math.floor(self.pw / (s.style == "bars" and 5 or 3))))
        drawn[i] = pts
        for _, p in ipairs(pts) do
            any = true
            ymin, ymax = math.min(ymin, p[2]), math.max(ymax, p[2])
        end
    end
    if not any or tmax <= tmin then
        self.empty:SetText(spec.emptyText or "No data in this range yet")
        self.empty:Show()
        for i = 0, 2 do self.ylabels[i]:SetText("") end
        for i = 1, 3 do self.xlabels[i]:SetText("") end
        return
    end
    self.empty:Hide()
    if spec.zero then ymin = 0 end
    if ymax <= ymin then
        ymax = ymin + math.max(1, math.abs(ymin) * 0.1)
        if not spec.zero then ymin = math.max(0, ymin - (ymax - ymin)) end
    else
        local pad = (ymax - ymin) * 0.08
        ymax = ymax + pad
        if not spec.zero then ymin = math.max(0, ymin - pad) end
    end
    self.ymin, self.ymax = ymin, ymax
    local pw, ph = self.pw, self.ph
    local function X(t) return (t - tmin) / (tmax - tmin) * pw end
    local function Y(v) return (v - ymin) / (ymax - ymin) * ph end

    for i, s in ipairs(spec.series) do
        local pts, color = drawn[i], s.color
        if s.style == "bars" then
            local bw = math.max(1, math.min(12, pw / math.max(#pts, 1) - 1))
            for _, p in ipairs(pts) do self:Bar(X(p[1]), bw, Y(p[2]), color) end
        else
            for j, p in ipairs(pts) do
                local prev = pts[j - 1]
                local ok = prev and self:Segment(X(prev[1]), Y(prev[2]), X(p[1]), Y(p[2]), color)
                if not ok and (not prev or not self.frame.CreateLine) then self:Dot(X(p[1]), Y(p[2]), color) end
            end
        end
        if i == 1 then
            self.hoverPts = {}
            for _, p in ipairs(pts) do table.insert(self.hoverPts, { p[1], X(p[1]) }) end
        end
    end
    local fmt = spec.format or tostring
    for i = 0, 2 do self.ylabels[i]:SetText(fmt(ymin + (ymax - ymin) * i / 2)) end
    local span = tmax - tmin
    for i = 1, 3 do self.xlabels[i]:SetText(dateText(tmin + span * (i - 1) / 2, span)) end
end

function Graph:Hover()
    local pts, f = self.hoverPts, self.frame
    if not pts or #pts == 0 or not self.spec or not self.spec.hover then return end
    local left, scale = f:GetLeft(), f:GetEffectiveScale()
    if not left or not scale then return end
    local cx = GetCursorPosition() / scale - left - LEFT
    local best, bestD = nil, math.huge
    for _, p in ipairs(pts) do
        local d = math.abs(p[2] - cx)
        if d < bestD then best, bestD = p, d end
    end
    if not best then return end
    self.cursor:ClearAllPoints()
    self.cursor:SetPoint("TOP", f, "TOPLEFT", LEFT + best[2], -TOP)
    self.cursor:SetPoint("BOTTOM", f, "BOTTOMLEFT", LEFT + best[2], BOTTOM)
    self.cursor:Show()
    if self.hovered ~= best[1] or not GameTooltip:IsShown() then
        self.hovered = best[1]
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:AddLine(dateText(best[1], 0))
        self.spec.hover(best[1])
        GameTooltip:Show()
    end
end
