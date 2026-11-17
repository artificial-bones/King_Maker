local _, KM = ...

-- Charts for every page, drawn with flat textures in King Maker's palette (UI.C). Econ's price graph, made generic
-- in 2.6 (Econ\Graph.lua is now a one-line shim onto UI.Chart), plus three small widgets.
--
--   local ch = UI.Chart(parent, w, h)        ch.frame is the frame to anchor; ch:SetSize(w, h) re-lays it out
--   ch:Draw({
--       series = { { pts = { { x, y [, color] [, data] }, ... }, style = "line" | "bars" | "area", color = {r,g,b,a},
--                    agg = "avg" | "sum" | "last" | "none" }, ... },   -- long series are bucketed (avg by default)
--       tmin, tmax (or xmin, xmax)   x range; default: the points' own
--       format = fn(y) -> text       y labels;  xformat = fn(x, span) -> text  x labels (default: dates)
--       zero = true                  start the y axis at 0;  ymin / ymax force the range (negatives get a zero line)
--       ref = { y = n, label = s }   one hairline reference line on the same axis (an average), labelled
--       endLabel = true              an 8 px end dot with a surface ring and the last value, for series 1
--       hover = fn(x, point)         fill GameTooltip for the point of series 1 nearest the mouse
--       click = fn(x, point)         click the nearest bar or point
--       emptyText = "..."
--   })
--   UI.HBars(parent, w, rowH, n)  list:SetRows({ { label, value = text, frac, color, icon, tip } })   ranked bars
--   UI.Spark(parent, w, h, n)     spark:Set(values, color)                                          tiny bar sparkline
--   UI.SplitBar(parent, w, h)     bar:Set({ { frac, color }, ... })                                 thin segmented bar

local UI = KM.UI
local C = UI.C
local WHITE = UI.WHITE

local Chart = {}
Chart.__index = Chart

local LEFT, RIGHT, TOP, BOTTOM = 70, 8, 6, 16
local fmtDate = date or (os and os.date)

local function dateText(t, span)
    if not fmtDate then return tostring(t) end
    if span <= 2 * 86400 then return fmtDate("%d %b %H:%M", t) end
    return fmtDate("%d %b %Y", t)
end

local function tex(f, layer)
    local t = f:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(WHITE)
    return t
end

function UI.Chart(parent, w, h, opts)
    local g = setmetatable({ lines = {}, bars = {}, dots = {}, opts = opts or {} }, Chart)
    local f = CreateFrame("Frame", nil, parent)
    g.frame = f

    g.well = CreateFrame("Frame", nil, f)
    UI.Fill(g.well, { 0, 0, 0, 0.30 })
    UI.Border(g.well)

    g.ylabels, g.grid, g.xlabels = {}, {}, {}
    for i = 0, 2 do
        local line = tex(f, "BORDER")
        line:SetVertexColor(1, 1, 1, i == 0 and 0.18 or 0.06)
        line:SetHeight(1)
        g.grid[i] = line
        g.ylabels[i] = UI.Text(f, 9, C.muted, "RIGHT")
    end
    for i, anchor in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
        g.xlabels[i] = UI.Text(f, 9, C.dim, anchor)
        g.xlabels[i].anchor = anchor
    end
    g.zeroLine = tex(f, "BORDER")
    g.zeroLine:SetVertexColor(1, 1, 1, 0.22)
    g.zeroLine:SetHeight(1)
    g.zeroLine:Hide()
    g.refLine = tex(f, "OVERLAY")
    g.refLine:SetVertexColor(C.text[1], C.text[2], C.text[3], 0.45)
    g.refLine:SetHeight(1)
    g.refLine:Hide()
    g.refText = UI.Text(f, 9, C.muted, "RIGHT")
    g.ring = tex(f, "OVERLAY")
    g.ring:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 1)
    g.ring:SetSize(12, 12)
    g.ring:Hide()
    g.endDot = f:CreateTexture(nil, "OVERLAY", nil, 2)
    g.endDot:SetTexture(WHITE)
    g.endDot:SetSize(8, 8)
    g.endDot:Hide()
    g.endText = UI.Text(f, 10, C.text, "RIGHT")
    g.empty = UI.Text(f, 11, C.dim, "CENTER")

    g.cursor = tex(f, "OVERLAY")
    g.cursor:SetVertexColor(C.text[1], C.text[2], C.text[3], 0.30)
    g.cursor:SetWidth(1)
    g.cursor:Hide()

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() f:SetScript("OnUpdate", function() g:Hover() end) end)
    f:SetScript("OnLeave", function()
        f:SetScript("OnUpdate", nil)
        g.cursor:Hide()
        GameTooltip:Hide()
    end)
    f:SetScript("OnMouseUp", function() g:Click() end)
    g:SetSize(w or 300, h or 120)
    return g
end

-- Re-lays the grid and labels for a new size and redraws the last chart.
function Chart:SetSize(w, h)
    w, h = math.max(LEFT + RIGHT + 20, w or self.w), math.max(TOP + BOTTOM + 20, h or self.h)
    if w == self.w and h == self.h then return end
    self.w, self.h = w, h
    local f = self.frame
    f:SetSize(w, h)
    self.pw, self.ph = w - LEFT - RIGHT, h - TOP - BOTTOM
    self.well:ClearAllPoints()
    self.well:SetPoint("TOPLEFT", LEFT, -TOP)
    self.well:SetPoint("BOTTOMRIGHT", -RIGHT, BOTTOM)
    for i = 0, 2 do
        local y = BOTTOM + self.ph * i / 2
        self.grid[i]:ClearAllPoints()
        self.grid[i]:SetPoint("BOTTOMLEFT", LEFT, y)
        self.grid[i]:SetPoint("BOTTOMRIGHT", -RIGHT, y)
        self.ylabels[i]:ClearAllPoints()
        self.ylabels[i]:SetPoint("RIGHT", f, "BOTTOMLEFT", LEFT - 6, y)
    end
    for i, label in ipairs(self.xlabels) do
        label:ClearAllPoints()
        local a = label.anchor
        label:SetPoint("TOP" .. (a == "CENTER" and "" or a), f, "BOTTOMLEFT", LEFT + self.pw * (i - 1) / 2, BOTTOM - 3)
    end
    self.empty:ClearAllPoints()
    self.empty:SetPoint("CENTER", LEFT / 2, BOTTOM / 2)
    if self.spec then self:Draw(self.spec) end
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

function Chart:Segment(x1, y1, x2, y2, color)
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

function Chart:Dot(x, y, color, size)
    local d = take(self.dots, function() return self.frame:CreateTexture(nil, "ARTWORK") end)
    size = size or 3
    d:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    d:SetSize(size, size)
    d:ClearAllPoints()
    d:SetPoint("CENTER", self.frame, "BOTTOMLEFT", LEFT + x, BOTTOM + y)
end

-- A rectangle from y0 up (or down) to y1, centred on x.
function Chart:Bar(x, width, y1, color, y0, alpha)
    local b = take(self.bars, function() return self.frame:CreateTexture(nil, "ARTWORK") end)
    y0 = y0 or 0
    b:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 0.8)
    b:SetSize(math.max(1, width), math.max(1, math.abs(y1 - y0)))
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", LEFT + x - width / 2, BOTTOM + math.min(y0, y1))
    return b
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- Points into at most n buckets across [tmin, tmax]: averaged (Econ's default), summed, or the last of each.
local function bucket(pts, tmin, tmax, n, agg)
    if agg == "none" or #pts <= n then return pts end
    local size = (tmax - tmin) / n
    local out, cur, sumT, sumV, cnt, lastP = {}, nil, 0, 0, 0, nil
    local function flush()
        if cnt == 0 then return end
        local v = agg == "sum" and sumV or (agg == "last" and lastP[2] or sumV / cnt)
        table.insert(out, { agg == "last" and lastP[1] or sumT / cnt, v, lastP[3], lastP[4] })
        sumT, sumV, cnt = 0, 0, 0
    end
    for _, p in ipairs(pts) do
        local b = math.min(n - 1, math.floor((p[1] - tmin) / size))
        if cur and b ~= cur then flush() end
        cur = b
        sumT, sumV, cnt, lastP = sumT + p[1], sumV + p[2], cnt + 1, p
    end
    flush()
    return out
end

function Chart:Draw(spec)
    release(self.lines); release(self.bars); release(self.dots)
    self.refLine:Hide(); self.refText:SetText(""); self.zeroLine:Hide()
    self.endDot:Hide(); self.ring:Hide(); self.endText:SetText("")
    self.spec = spec
    self.hoverPts = nil
    local tmin, tmax = spec.tmin or spec.xmin, spec.tmax or spec.xmax
    if not (tmin and tmax) then
        local lo, hi = math.huge, -math.huge
        for _, s in ipairs(spec.series or {}) do
            for _, p in ipairs(s.pts or {}) do lo, hi = math.min(lo, p[1]), math.max(hi, p[1]) end
        end
        tmin, tmax = tmin or lo, tmax or hi
        if tmin == tmax then tmin, tmax = tmin - 1, tmax + 1 end
    end
    local any, ymin, ymax = false, math.huge, -math.huge
    local drawn = {}
    for i, s in ipairs(spec.series or {}) do
        local pts = {}
        for _, p in ipairs(s.pts or {}) do
            if p[2] and p[1] >= tmin and p[1] <= tmax then table.insert(pts, p) end
        end
        pts = bucket(pts, tmin, tmax, math.max(10, math.floor(self.pw / (s.style == "bars" and 5 or 3))), s.agg)
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
    if spec.ref and spec.ref.y then ymax = math.max(ymax, spec.ref.y) end
    local hasBars = false
    for _, s in ipairs(spec.series) do if s.style == "bars" or s.style == "area" then hasBars = true end end
    if spec.zero or hasBars then ymin = math.min(0, ymin) end
    if ymax <= ymin then
        ymax = ymin + math.max(1, math.abs(ymin) * 0.1)
        if not spec.zero then ymin = math.max(0, ymin - (ymax - ymin)) end
    else
        local pad = (ymax - ymin) * 0.08
        ymax = ymax + pad
        if not (spec.zero or hasBars) then ymin = (ymin >= 0) and math.max(0, ymin - pad) or ymin - pad end
    end
    ymin, ymax = spec.ymin or ymin, spec.ymax or ymax
    self.ymin, self.ymax, self.tmin, self.tmax = ymin, ymax, tmin, tmax
    local pw, ph = self.pw, self.ph
    local function X(t) return (t - tmin) / (tmax - tmin) * pw end
    local function Y(v) return (math.max(ymin, math.min(ymax, v)) - ymin) / (ymax - ymin) * ph end
    local base = Y(math.max(ymin, math.min(0, ymax)))
    if ymin < 0 then
        self.zeroLine:ClearAllPoints()
        self.zeroLine:SetPoint("BOTTOMLEFT", LEFT, BOTTOM + base)
        self.zeroLine:SetPoint("BOTTOMRIGHT", -RIGHT, BOTTOM + base)
        self.zeroLine:Show()
    end

    for i, s in ipairs(spec.series) do
        local pts, color = drawn[i], s.color or C.accent
        if s.style == "bars" then
            -- at most 24 px wide, a 2 px gap between bars
            local bw = math.max(1, math.min(24, pw / math.max(#pts, 1) - 2))
            for _, p in ipairs(pts) do
                local x = math.max(bw / 2, math.min(pw - bw / 2, X(p[1])))
                self:Bar(x, bw, Y(p[2]), p[3] or color, base)
            end
        else
            if s.style == "area" then
                for j = 2, #pts do
                    local a, b = pts[j - 1], pts[j]
                    local x1, x2 = X(a[1]), X(b[1])
                    self:Bar((x1 + x2) / 2, x2 - x1, (Y(a[2]) + Y(b[2])) / 2, color, base, 0.10)
                end
            end
            for j, p in ipairs(pts) do
                local prev = pts[j - 1]
                local ok = prev and self:Segment(X(prev[1]), Y(prev[2]), X(p[1]), Y(p[2]), color)
                if not ok and (not prev or not self.frame.CreateLine) then self:Dot(X(p[1]), Y(p[2]), color) end
            end
        end
        if i == 1 then
            self.hoverPts = {}
            for _, p in ipairs(pts) do table.insert(self.hoverPts, { p[1], X(p[1]), p }) end
            local last = pts[#pts]
            if spec.endLabel and last then
                local x, y = X(last[1]), Y(last[2])
                self.ring:ClearAllPoints(); self.ring:SetPoint("CENTER", self.frame, "BOTTOMLEFT", LEFT + x, BOTTOM + y); self.ring:Show()
                self.endDot:ClearAllPoints(); self.endDot:SetPoint("CENTER", self.ring, "CENTER", 0, 0)
                self.endDot:SetVertexColor(color[1], color[2], color[3], 1); self.endDot:Show()
                self.endText:ClearAllPoints(); self.endText:SetPoint("BOTTOMRIGHT", self.ring, "TOPLEFT", 0, 2)
                self.endText:SetText((spec.format or tostring)(last[2]))
            end
        end
    end
    if spec.ref and spec.ref.y then
        local y = Y(spec.ref.y)
        self.refLine:ClearAllPoints()
        self.refLine:SetPoint("BOTTOMLEFT", LEFT, BOTTOM + y)
        self.refLine:SetPoint("BOTTOMRIGHT", -RIGHT, BOTTOM + y)
        self.refLine:Show()
        self.refText:ClearAllPoints()
        self.refText:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMLEFT", LEFT + pw - 4, BOTTOM + y + 2)
        self.refText:SetText(spec.ref.label or "")
    end
    local fmt = spec.format or tostring
    for i = 0, 2 do self.ylabels[i]:SetText(fmt(ymin + (ymax - ymin) * i / 2)) end
    local span = tmax - tmin
    local xf = spec.xformat or dateText
    for i = 1, 3 do self.xlabels[i]:SetText(xf(tmin + span * (i - 1) / 2, span)) end
end

-- The point of series 1 nearest the cursor: x, its pixel x, the point.
function Chart:Nearest()
    local pts, f = self.hoverPts, self.frame
    if not pts or #pts == 0 then return end
    local left, scale = f:GetLeft(), f:GetEffectiveScale()
    if not left or not scale then return end
    local cx = GetCursorPosition() / scale - left - LEFT
    local best, bestD = nil, math.huge
    for _, p in ipairs(pts) do
        local d = math.abs(p[2] - cx)
        if d < bestD then best, bestD = p, d end
    end
    return best
end

function Chart:Hover()
    if not self.spec or not self.spec.hover then return end
    local best, f = self:Nearest(), self.frame
    if not best then return end
    self.cursor:ClearAllPoints()
    self.cursor:SetPoint("TOP", f, "TOPLEFT", LEFT + best[2], -TOP)
    self.cursor:SetPoint("BOTTOM", f, "BOTTOMLEFT", LEFT + best[2], BOTTOM)
    self.cursor:Show()
    if self.hovered ~= best[1] or not GameTooltip:IsShown() then
        self.hovered = best[1]
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        if not self.spec.xformat then GameTooltip:AddLine(dateText(best[1], 0)) end
        self.spec.hover(best[1], best[3])
        GameTooltip:Show()
    end
end

function Chart:Click()
    if not self.spec or not self.spec.click then return end
    local best = self:Nearest()
    if best then self.spec.click(best[1], best[3]) end
end

---------------------------------------------------------------------------
-- Ranked horizontal bars: label, a bar in one hue, the value at its tip
---------------------------------------------------------------------------

function UI.HBars(parent, w, rowH, n)
    local list = CreateFrame("Frame", nil, parent)
    rowH, n = rowH or 18, n or 6
    list.rowH, list.n, list.rows, list.labelW = rowH, n, {}, 92
    list:SetSize(w or 280, rowH * n)
    for i = 1, n do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(rowH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(rowH - 6, rowH - 6)
        r.icon:SetPoint("LEFT", 0, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.label = UI.Text(r, 11, C.muted)
        r.label:SetPoint("LEFT", 0, 0)
        r.label:SetWidth(list.labelW - 6)
        r.track = tex(r, "BACKGROUND")
        r.track:SetVertexColor(0, 0, 0, 0.30)
        r.track:SetPoint("LEFT", list.labelW, 0)
        r.track:SetPoint("RIGHT", -64, 0)
        r.track:SetHeight(math.max(4, rowH - 8))
        r.fill = tex(r, "ARTWORK")
        r.fill:SetPoint("LEFT", r.track, "LEFT", 0, 0)
        r.fill:SetHeight(math.max(4, rowH - 8))
        r.value = UI.Text(r, 11, C.text)
        r.value:SetPoint("LEFT", r.fill, "RIGHT", 4, 0)
        r:SetScript("OnEnter", function(self)
            if not self.data or not self.data.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local tip = self.data.tip
            if type(tip) == "function" then tip(GameTooltip) else GameTooltip:AddLine(tip, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        list.rows[i] = r
    end
    function list:SetRows(rows)
        self.data = rows or {}
        local trackW = math.max(10, (self:GetWidth() or 280) - self.labelW - 64)
        for i, r in ipairs(self.rows) do
            local d = self.data[i]
            r.data = d
            if d then
                local c = d.color or C.accent
                r.label:SetText(d.label or "")
                if d.icon then
                    r.icon:SetTexture(d.icon); r.icon:Show()
                    r.label:SetPoint("LEFT", self.rowH - 2, 0)
                else
                    r.icon:Hide()
                    r.label:SetPoint("LEFT", 0, 0)
                end
                local frac = math.max(0, math.min(1, d.frac or 0))
                r.fill:SetWidth(math.max(1, trackW * frac))
                r.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
                r.fill:SetShown(frac > 0)
                r.value:SetText(d.value or "")
                r:Show()
            else
                r:Hide()
            end
        end
    end
    list:SetScript("OnSizeChanged", function(self) if self.data then self:SetRows(self.data) end end)
    return list
end

---------------------------------------------------------------------------
-- Sparkline: up to n thin bars, scaled to the largest
---------------------------------------------------------------------------

function UI.Spark(parent, w, h, n)
    local s = CreateFrame("Frame", nil, parent)
    n = n or 30
    s:SetSize(w or 120, h or 18)
    s.n, s.bars = n, {}
    s.base = tex(s, "BACKGROUND")
    s.base:SetVertexColor(1, 1, 1, 0.06)
    s.base:SetHeight(1)
    s.base:SetPoint("BOTTOMLEFT")
    s.base:SetPoint("BOTTOMRIGHT")
    for i = 1, n do
        local b = tex(s, "ARTWORK")
        b:Hide()
        s.bars[i] = b
    end
    function s:Set(values, color)
        values, color = values or {}, color or C.accent
        local first = math.max(1, #values - self.n + 1)
        local top = 0
        for i = first, #values do top = math.max(top, values[i] or 0) end
        local W, H = self:GetWidth() or 120, self:GetHeight() or 18
        local bw = math.max(1, (W - (self.n - 1)) / self.n)
        local shown = 0
        for i = 1, self.n do
            local v = values[first + i - 1]
            local b = self.bars[i]
            if v then
                shown = shown + 1
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (i - 1) * (bw + 1), 0)
                b:SetSize(bw, math.max(1, top > 0 and H * math.max(0, v) / top or 1))
                b:SetVertexColor(color[1], color[2], color[3], v > 0 and 0.9 or 0.25)
                b:Show()
            else
                b:Hide()
            end
        end
        self.shownBars = shown
    end
    return s
end

---------------------------------------------------------------------------
-- Split bar: thin segments with 2 px surface gaps (the HUD's Mobs | Gathering share)
---------------------------------------------------------------------------

function UI.SplitBar(parent, w, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(w or 200, h or 6)
    b.segs = {}
    b.bg = UI.Fill(b, { 0, 0, 0, 0.35 })
    function b:Set(parts)
        self.parts = parts or {}
        local W = self:GetWidth() or 200
        local live = {}
        for _, p in ipairs(self.parts) do if (p[1] or 0) > 0 then live[#live + 1] = p end end
        local gaps = math.max(0, #live - 1) * 2
        local x = 0
        for i = 1, math.max(#live, #self.segs) do
            local p, t = live[i], self.segs[i]
            if p then
                if not t then t = tex(self, "ARTWORK"); self.segs[i] = t end
                local sw = math.max(1, (W - gaps) * p[1])
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", x, 0)
                t:SetPoint("BOTTOMLEFT", x, 0)
                t:SetWidth(sw)
                local c = p[2] or C.accent
                t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
                t:Show()
                x = x + sw + 2
            elseif t then
                t:Hide()
            end
        end
        self.bg:SetShown(#live == 0)
    end
    b:SetScript("OnSizeChanged", function(self) if self.parts then self:Set(self.parts) end end)
    return b
end
