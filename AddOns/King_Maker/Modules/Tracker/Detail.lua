local _, KM = ...
local ns = KM.Module("Tracker")
local UI = KM.UI
local C = UI.C

-- One saved session on the Farming Ledger page, in the list's place: a header (back, previous / next, prices when
-- looted or today, keep, rename, delete), six tiles, gold over time, where the gold came from, and four tabs:
-- Items, Mobs, Gathering and Money (the wallet reconciliation). Lays out from the container's width.

local P = ns.P
local D = {}
local TABS = { { id = "items", label = "Items", w = 80 }, { id = "mobs", label = "Mobs", w = 80 },
    { id = "gathering", label = "Gathering", w = 90 }, { id = "money", label = "Money", w = 80 } }
local FROM = { mob = "drops", skin = "Skinning", pick = "Pickpocket", mine = "Mining", herb = "Herbs", fish = "Fishing",
    chest = "Treasure", box = "Boxes", de = "Disenchant", unknown = "Other", share = "Party", quest = "Quest" }
local GATHER_ORDER = { "mine", "herb", "fish", "chest", "box" }

local function U() return ns.db.ui end
local function cur() return ns.Find(P.sessionID or -1) end

local function shareBar(r, col)
    if not r.bar then
        r.bar = UI.Bar(r, 6)
        r.bar:SetWidth(70)
    end
    r.bar:ClearAllPoints()
    r.bar:SetPoint("LEFT", r, "LEFT", col.x + 36, 0)
    return r.bar
end

local function colOf(cols, key) for _, c in ipairs(cols) do if c.key == key then return c end end end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------

local ITEM_COLS = {
    { key = "item", label = "Item", w = 196, sort = function(e) return e.name end, desc = false },
    { key = "from", label = "From", w = 112 },
    { key = "qty", label = "Qty", w = 52, justify = "RIGHT", sort = function(e) return e.q end },
    { key = "each", label = "Each", tip = "What one is worth: AH is the market price after the 5% cut, vendor the vendor price, whichever is higher. Greys and soulbound items go at vendor.", w = 118, justify = "RIGHT", sort = function(e) return e.each or -1 end },
    { key = "total", label = "Total", w = 92, justify = "RIGHT", sort = function(e) return e.total end },
    { key = "share", label = "Share", tip = "Its part of everything looted in this session.", w = 0 },
}

local MOB_COLS = {
    { key = "mob", label = "Mob", w = 170, sort = function(e) return e.name end, desc = false },
    { key = "kills", label = "Kills", w = 50, justify = "RIGHT", sort = function(e) return e.k end },
    { key = "coin", label = "Coin", w = 80, justify = "RIGHT", sort = function(e) return e.c end },
    { key = "drops", label = "Drops", tip = "Items looted from its corpse (and pickpocketed), at their value.", w = 86, justify = "RIGHT", sort = function(e) return e.v end },
    { key = "skins", label = "Skins", tip = "What skinning it gave, and how many skins in brackets.", w = 86, justify = "RIGHT", sort = function(e) return e.sv end },
    { key = "total", label = "Total", w = 90, justify = "RIGHT", sort = function(e) return e.total end },
    { key = "per", label = "Per kill", tip = "Coin, drops and skins together, divided by kills.", w = 80, justify = "RIGHT", sort = function(e) return e.per or -1 end },
    { key = "share", label = "Share", w = 0 },
}

local GATHER_COLS = {
    { key = "kind", label = "Kind", w = 150 },
    { key = "n", label = "Actions", tip = "Nodes mined or picked, fish caught, chests or boxes opened, items disenchanted.", w = 64, justify = "RIGHT", sort = function(e) return e.n end },
    { key = "per", label = "Per action", tip = "Value divided by actions: what one node, catch or box was worth.", w = 92, justify = "RIGHT", sort = function(e) return e.per or -1 end },
    { key = "top", label = "Top item", w = 180 },
    { key = "value", label = "Value", w = 92, justify = "RIGHT", sort = function(e) return e.value end },
    { key = "share", label = "Share", tip = "Its part of the gathering here. A kind that isn't counted as farmed (see Settings > Farm Tracker) has no share.", w = 0 },
}

local function pctText(frac)
    if frac <= 0 then return "" end
    if frac < 0.01 then return "<1%" end
    return math.floor(frac * 100 + 0.5) .. "%"
end

local function itemRows(s)
    local revalue = U().revalue
    local rows, total = {}, 0
    for id, it in pairs(s["items"] or {}) do
        local unit, from = KM.ItemValue(id)
        local q = it.q or 0
        local tot = revalue and q * (unit or 0) or (it.v or 0)
        local each = q > 0 and tot / q or nil
        local froms = {}
        for _, kind in ipairs(ns.KIND_ORDER) do
            local e = s.src and s.src[kind]
            if e and e.i and e.i[id] then froms[#froms + 1] = FROM[kind] or kind end
        end
        local quest = from == "quest"
        rows[#rows + 1] = { id = id, name = KM.Item(id).name or ("Item " .. id), q = q, each = each, total = tot,
            from = froms, src = from, np = it.np, quest = quest }
        total = total + tot
    end
    if s.rest then
        rows[#rows + 1] = { rest = true, name = "~", q = s.rest.q or 0, total = s.rest.v or 0, from = {} }
        total = total + (s.rest.v or 0)
    end
    for _, r in ipairs(rows) do r.frac = total > 0 and r.total / total or 0 end
    return rows
end

local function fillItem(r, e, cells)
    if e.rest then
        cells.item:SetText(UI.Hex(C.muted) .. "+" .. (cur() and cur().rest and cur().rest.n or 0) .. " more items (older than 45 days: folded)|r")
        cells.from:SetText(""); cells.qty:SetText(e.q); cells.each:SetText("")
        cells.total:SetText(KM.Money(e.total)); cells.share:SetText(pctText(e.frac))
        shareBar(r, colOf(ITEM_COLS, "share")):Set(e.frac, C.accent)
        return
    end
    if r.icon then r.icon:SetTexture(KM.Item(e.id).icon) end
    r.item = e.id
    local dim = e.quest
    cells.item:SetText(dim and (UI.Hex(C.dim) .. (KM.Item(e.id).name or ("Item " .. e.id)) .. "|r") or KM.ItemText(e.id))
    cells.from:SetText(UI.Hex(C.muted) .. table.concat(e.from, ", ", 1, math.min(2, #e.from)) .. (#e.from > 2 and ", ..." or "") .. "|r")
    cells.qty:SetText(e.q)
    if e.quest then
        cells.each:SetText(UI.Hex(C.dim) .. "quest item|r")
        cells.total:SetText(UI.Hex(C.dim) .. "-|r")
    elseif e.np and (e.total or 0) == 0 then
        cells.each:SetText(UI.Hex(C.warn) .. "no price yet|r")
        cells.total:SetText(UI.Hex(C.dim) .. "-|r")
    else
        cells.each:SetText(KM.Money(e.each) .. " " .. UI.Hex(C.dim) .. (e.src == "ah" and "AH" or "vendor") .. "|r")
        cells.total:SetText(KM.Money(e.total))
    end
    cells.share:SetText(pctText(e.frac))
    shareBar(r, colOf(ITEM_COLS, "share")):Set(e.frac, C.accent)
end

local function mobRows(s)
    local rows, total = {}, 0
    for npc, m in pairs(s.mobs or {}) do
        local t = (m.v or 0) + (m.c or 0) + (m.sv or 0)
        rows[#rows + 1] = { npc = npc, name = ns.MobName(npc, s), k = m.k or 0, c = m.c or 0, v = m.v or 0, sv = m.sv or 0,
            sn = m.sn or 0, total = t, per = (m.k or 0) > 0 and t / m.k or nil }
        total = total + t
    end
    for _, r in ipairs(rows) do r.frac = total > 0 and r.total / total or 0 end
    return rows
end

local function fillMob(r, e, cells)
    cells.mob:SetText(e.name)
    cells.kills:SetText(e.k > 0 and e.k or "|cff808080-|r")
    cells.coin:SetText(KM.Money(e.c))
    cells.drops:SetText(KM.Money(e.v))
    cells.skins:SetText(e.sn > 0 and (KM.Money(e.sv) .. UI.Hex(C.dim) .. " (" .. e.sn .. ")|r") or "|cff808080-|r")
    cells.total:SetText(KM.Money(e.total))
    cells.per:SetText(e.per and KM.Money(e.per) or "|cff808080-|r")
    cells.share:SetText(pctText(e.frac))
    shareBar(r, colOf(MOB_COLS, "share")):Set(e.frac, ns.ORANGE)
    r.tip = "Click to open " .. e.name .. " on Mob Farming."
end

local function gatherRows(s)
    local rows, total = {}, 0
    local kinds = {}
    for _, k in ipairs(GATHER_ORDER) do kinds[#kinds + 1] = k end
    kinds[#kinds + 1] = "de"
    for _, kind in ipairs(kinds) do
        local e = s.src and s.src[kind]
        if e and ((e.n or 0) > 0 or (e.v or 0) + (e.c or 0) > 0) then
            local v = (e.v or 0) + (e.c or 0)
            local top, topV
            for id, q in pairs(e.i or {}) do
                local it = s["items"] and s["items"][id]
                local share = it and (it.q or 0) > 0 and (it.v or 0) * q / it.q or 0
                if not topV or share > topV then top, topV = id, share end
            end
            local excluded = not ns.CountsIn(s, kind)
            rows[#rows + 1] = { kind = kind, n = e.n or 0, value = v, per = (e.n or 0) > 0 and v / e.n or nil, top = top, excluded = excluded }
            if not excluded then total = total + v end
        end
    end
    for _, r in ipairs(rows) do r.frac = (total > 0 and not r.excluded) and r.value / total or 0 end
    return rows
end

local function fillGather(r, e, cells)
    local label = ns.KIND_LABEL[e.kind] or e.kind
    if e.excluded then label = UI.Hex(C.dim) .. label .. " (not counted)|r" end
    cells.kind:SetText(label)
    cells.n:SetText(e.n)
    cells.per:SetText(e.per and KM.Money(e.per) or "|cff808080-|r")
    cells.top:SetText(e.top and KM.ItemText(e.top) or "")
    cells.value:SetText(KM.Money(e.value))
    cells.share:SetText(pctText(e.frac))
    shareBar(r, colOf(GATHER_COLS, "share")):Set(e.frac, ns.AQUA)
end

---------------------------------------------------------------------------
-- Money: the wallet reconciliation
---------------------------------------------------------------------------

local function moneyLines(s)
    local cash = s.cash or {}
    local share = s.src and s.src.share and s.src.share.c or 0
    local other = (cash.mail or 0) + (cash.ah or 0) + (cash.trade or 0) + (cash.bank or 0) + (cash.other or 0)
    local wallet = {
        { "At start", s.gold0 and KM.Money(s.gold0) or "-" },
        { "+ Looted coin", KM.Money((s.coin or 0) - share - ((s.src and s.src.quest and s.src.quest.c) or 0)) },
        { "+ Party coin shares", share ~= 0 and KM.Money(share) or "-" },
        { "+ Sold to vendors", cash.vendor and KM.Money(cash.vendor) or "-" },
        { "+ Quest rewards", cash.quest and (KM.Money(cash.quest) .. (ns.Counts("quest") and "" or UI.Hex(C.dim) .. "  (not in farmed)|r")) or "-" },
        { "- Repairs", cash.repair and KM.Money(cash.repair) or "-" },
        { "- Bought from vendors", cash.buy and KM.Money(cash.buy) or "-" },
        { "- Flight paths", cash.travel and KM.Money(cash.travel) or "-" },
        { "- Training", cash.train and KM.Money(cash.train) or "-" },
        { "+/- Mail, AH, trade, bank, other", other ~= 0 and KM.Money(other) or "-" },
    }
    local t = ns.Totals(s)
    wallet[#wallet + 1] = { "= At end", s.gold1 and (KM.Money(s.gold1) .. (t.wallet and ("  (" .. (t.wallet >= 0 and "+" or "") .. KM.Money(t.wallet) .. ")") or "")) or "-" }
    local costs = {
        { "Repairs", KM.Money(-(cash.repair or 0)) },
        { "Bought from vendors", KM.Money(-(cash.buy or 0)) },
        { "Flights and training", KM.Money(-((cash.travel or 0) + (cash.train or 0))) },
        { " ", " " },
        { "Farmed (at loot prices)", KM.Money(s.value or 0) },
        { "Net farmed", KM.Money((s.value or 0) + t.costs) },
    }
    if U().revalue then
        local d = ns.ValueNow(s) - (s.value or 0)
        costs[#costs + 1] = { "Today's prices", (d >= 0 and "+" or "") .. KM.Money(d) }
    end
    return wallet, costs
end

local function pairRows(parent, n, x, w)
    local rows = {}
    for i = 1, n do
        local l = UI.Text(parent, 12, C.text)
        l:SetPoint("TOPLEFT", x, -24 - (i - 1) * 18)
        local r = UI.Text(parent, 12, C.text, "RIGHT")
        r:SetPoint("TOPLEFT", x, -24 - (i - 1) * 18)
        r:SetWidth(w)
        rows[i] = { l = l, r = r }
    end
    return rows
end

---------------------------------------------------------------------------
-- Build and refresh
---------------------------------------------------------------------------

local zoneAverage   -- below: your gold per hour in this session's zone

function ns.BuildDetail(c)
    local v = CreateFrame("Frame", nil, c)
    v:SetAllPoints(c)
    v:Hide()
    P.detail = v

    D.back = UI.Button(v, "< Back", 70, 24, function() ns.ShowList() end)
    D.back:SetPoint("TOPLEFT", 0, 0)
    D.prev = UI.Button(v, "<", 26, 24, function() ns.StepSession(-1) end)
    D.prev:SetPoint("LEFT", D.back, "RIGHT", 6, 0)
    D.next = UI.Button(v, ">", 26, 24, function() ns.StepSession(1) end)
    D.next:SetPoint("LEFT", D.prev, "RIGHT", 4, 0)
    D.pos = UI.Text(v, 11, C.muted)
    D.pos:SetPoint("LEFT", D.next, "RIGHT", 10, 0)

    D.del = UI.Button(v, "Delete", 66, 24, function() local s = cur(); if s then ns.AskDelete(s.id, ns.ShowList) end end)
    D.del:SetPoint("TOPRIGHT", 0, 0)
    D.rename = UI.Button(v, "Rename", 70, 24, function() ns.StartRename() end)
    D.rename:SetPoint("RIGHT", D.del, "LEFT", -6, 0)
    D.keep = UI.Button(v, "Keep", 62, 24, function() local s = cur(); if s then ns.Star(s.id, not s.star); KM.Refresh("farming") end end)
    D.keep:SetPoint("RIGHT", D.rename, "LEFT", -6, 0)
    UI.Tip(D.keep, "Kept sessions are never pruned or folded.")
    D.prices = UI.Tabs(v, { { id = "looted", label = "When looted", w = 92 }, { id = "today", label = "Today", w = 60 } },
        function(id) U().revalue = id == "today"; KM.Refresh("farming") end, 24)
    D.prices:SetPoint("RIGHT", D.keep, "LEFT", -14, 0)
    UI.Tip(D.prices.buttons.looted, "Each item at the price it had when you looted it: what the session was worth then.")
    UI.Tip(D.prices.buttons.today, "Revalue this session's loot at today's prices (a view; the saved numbers never change).")
    local pl = UI.Text(v, 10, C.muted, "RIGHT")
    pl:SetPoint("RIGHT", D.prices, "LEFT", -6, 0)
    pl:SetText("Prices:")

    D.title = UI.Text(v, 16, C.text)
    D.title:SetPoint("TOPLEFT", 0, -34)
    D.pill = UI.Pill(v)
    D.pill:SetSize(96, 16)
    D.pill:SetPoint("LEFT", D.title, "RIGHT", 10, 0)
    UI.Tip(D.pill, "What the gold came from: Mobs, or a gathering kind, when it made 70% or more of the value; Mixed otherwise. Carried over: from the old trackers, left out of the totals.")
    D.best = UI.Pill(v)
    D.best:SetSize(40, 16)
    D.best:SetPoint("LEFT", D.pill, "RIGHT", 6, 0)
    D.best:Hide()
    UI.Tip(D.best, "Your best gold per hour for this farm (this zone and this activity), out of its sessions with 10+ active minutes.")
    D.renameBox = UI.EditBox(v, 300, 24, "Name this session (empty: its zone)")
    D.renameBox:SetPoint("TOPLEFT", 0, -30)
    D.renameBox:Hide()
    D.renameBox:SetScript("OnEnterPressed", function(self)
        local s = cur()
        if s then ns.Rename(s.id, self:GetText() or "") end
        self:ClearFocus(); self:Hide()
        KM.Refresh("farming")
    end)
    D.renameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:Hide() end)
    D.meta = UI.Text(v, 10, C.muted)
    D.meta:SetPoint("TOPLEFT", 0, -56)
    D.meta:SetPoint("RIGHT", v, "RIGHT", 0, 0)

    D.tileRow, D.tiles = ns.MakeTiles(v, -72)
    local function dl(tt, l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
    local T = D.tiles
    T[1]:SetTip(function(tt)
        local s = cur()
        if not s then return end
        local t = ns.Totals(s, U().revalue)
        tt:AddLine("Coin plus loot. Each item at the higher of its market price after the 5% cut or its vendor price, "
            .. (U().revalue and "at today's prices." or "as it was when looted.") .. " Switch with Prices at the top.", 1, 1, 1, true)
        dl(tt, "Coin", KM.Money(t.coin)); dl(tt, "Items", KM.Money(t.value - t.coin))
    end)
    T[2]:SetTip(function(tt)
        local s = cur()
        if not s then return end
        local t = ns.Totals(s, U().revalue)
        local avg = zoneAverage(s)
        tt:AddLine("Farmed divided by active time. Compared with all your other sessions in the same zone.", 1, 1, 1, true)
        dl(tt, "Farmed", KM.Money(t.value)); dl(tt, "Active time", ns.Clock(t.act))
        if avg then dl(tt, "Your average here", KM.Money(avg) .. "/hr") end
    end)
    T[3]:SetTip("Time the clock ran, out of the time from start to end. Idle and paused time aren't counted.")
    T[4]:SetTip("Coin you looted, plus party coin shares and quest gold when Settings > Farm Tracker counts them.")
    T[5]:SetTip("Mobs you killed, kills per active minute, and how often you died.")
    T[6]:SetTip(function(tt)
        local s = cur()
        if not s then return end
        local t = ns.Totals(s, U().revalue)
        tt:AddLine("Farmed minus what you spent while farming. The Money tab has the full wallet.", 1, 1, 1, true)
        dl(tt, "Farmed", KM.Money(t.value)); dl(tt, "Repairs, vendors, flights, training", KM.Money(t.costs))
    end)

    D.left = UI.Panel(v, C.panel)
    D.left:SetPoint("TOPLEFT", 0, -140)
    D.left:SetSize(470, 160)
    local lh = UI.Heading(D.left, "Gold over time")
    lh:SetPoint("TOPLEFT", 10, -8)
    D.chart = UI.Chart(D.left, 456, 130)
    D.chart.frame:SetPoint("TOPLEFT", 4, -24)
    D.right = UI.Panel(v, C.panel)
    D.right:SetPoint("TOPLEFT", D.left, "TOPRIGHT", 10, 0)
    D.right:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, -140)
    D.right:SetHeight(160)
    local rh = UI.Heading(D.right, "Where it came from")
    rh:SetPoint("TOPLEFT", 10, -8)
    D.bars = UI.HBars(D.right, 264, 18, 6)
    D.bars:SetPoint("TOPLEFT", 10, -26)
    D.bars:SetPoint("TOPRIGHT", -10, -26)
    D.note = UI.Text(D.right, 10, C.warn)
    D.note:SetPoint("BOTTOMLEFT", 10, 8)

    D.tabs = UI.Tabs(v, TABS, function(id) D.tab = id; KM.Refresh("farming") end, 20)
    D.tabs:SetPoint("TOPLEFT", 0, -310)
    D.tab = "items"

    local function tbl(cols, opts)
        local t = UI.Table(v, cols, 20, opts)
        t:SetPoint("TOPLEFT", 0, -336)
        t:SetPoint("BOTTOMRIGHT", 0, 0)
        t:Hide()
        return t
    end
    D.items = tbl(ITEM_COLS, { icon = true, onClick = function(e, button)
        if not e.id then return end
        if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
            local _, link = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(e.id)
            if link then pcall(ChatEdit_InsertLink, link) end
            return
        end
        local Econ = KM.mods.Econ
        if Econ and Econ.Toggle and Econ.ShowItem then KM.Safe(Econ.Toggle, true); KM.Safe(Econ.ShowItem, e.id) end
    end })
    D.items:SetSort("total", true)
    D.items.emptyText = "Nothing looted in this session."
    D.mobs = tbl(MOB_COLS, { onClick = function(e)
        local Farm = KM.mods.Farm
        if Farm and Farm.ShowMob and e.npc ~= 0 then KM.Show("mobs"); KM.Safe(Farm.ShowMob, e.npc) end
    end })
    D.mobs:SetSort("total", true)
    D.mobs.emptyText = "No mobs in this session."
    D.gather = tbl(GATHER_COLS)
    D.gather:SetSort("value", true)
    D.gather.emptyText = "No gathering in this session."
    D.gather:SetPoint("BOTTOMRIGHT", 0, 22)
    D.nodes = UI.Text(v, 10, C.muted)
    D.nodes:SetPoint("BOTTOMLEFT", 0, 4)
    D.nodes:SetPoint("RIGHT", v, "RIGHT", 0, 0)

    D.money = CreateFrame("Frame", nil, v)
    D.money:SetPoint("TOPLEFT", 0, -336)
    D.money:SetPoint("BOTTOMRIGHT", 0, 0)
    D.money:Hide()
    local wh = UI.Heading(D.money, "Wallet")
    wh:SetPoint("TOPLEFT", 0, -4)
    local ch = UI.Heading(D.money, "Costs and net")
    ch:SetPoint("TOPLEFT", 400, -4)
    D.walletRows = pairRows(D.money, 11, 0, 340)
    D.costRows = pairRows(D.money, 7, 400, 340)
end

function ns.StepSession(d)
    local order = P.order or {}
    for i, id in ipairs(order) do
        if id == P.sessionID then
            local nid = order[i + d]
            if nid then ns.ShowSession(nid) end
            return
        end
    end
end

function ns.StartRename()
    local s = cur()
    if not s then return end
    D.renameBox:SetText(s.name or "")
    D.renameBox:Show()
    if D.renameBox.SetFocus then D.renameBox:SetFocus() end
end

local function sourceBars(s)
    local rows, coin = {}, 0
    for kind, e in pairs(s.src or {}) do
        if ns.CountsIn(s, kind) then
            if (e.v or 0) > 0 then rows[#rows + 1] = { label = ns.KIND_LABEL[kind] or kind, v = e.v } end
            coin = coin + (e.c or 0)
        end
    end
    if coin > 0 then rows[#rows + 1] = { label = "Coin", v = coin } end
    table.sort(rows, function(a, b) return a.v > b.v end)
    local top = rows[1] and rows[1].v or 0
    for _, r in ipairs(rows) do
        r.frac = top > 0 and r.v / top or 0
        r.value = KM.Money(r.v)
        r.color = C.accent
    end
    return rows
end

function zoneAverage(s)
    local list = {}
    local map = ns.MainZone(s)
    for _, o in ipairs(ns.db.sessions) do
        if o ~= s and not o.legacy and ns.MainZone(o) == map then list[#list + 1] = o end
    end
    return ns.Aggregate(list).gph
end

function ns.RefreshDetail(c)
    local s = cur()
    if not s then return ns.ShowList() end
    local revalue = U().revalue
    local t = ns.Totals(s, revalue)
    local w = (c and c:GetWidth()) or 763
    if w ~= D.width then
        D.width = w
        ns.LayoutTiles(D.tiles, w)
        local lw = math.max(300, math.floor((w - 10) * 0.62))
        D.left:SetWidth(lw)
        D.chart:SetSize(lw - 8, 130)
        D.bars:SetWidth(math.max(160, w - lw - 30))
    end

    -- header
    local order = P.order or {}
    local idx
    for i, id in ipairs(order) do if id == s.id then idx = i end end
    D.pos:SetText(idx and (idx .. " of " .. #order) or "")
    D.prev:SetEnabled2(idx ~= nil and idx > 1)
    D.next:SetEnabled2(idx ~= nil and idx < #order)
    D.prices:Select(revalue and "today" or "looted")
    D.keep:SetLabel(s.star and "Kept" or "Keep")
    D.keep:SetActive(s.star and true or false)
    local short, activity = ns.ActivityText(s)
    D.title:SetText(ns.SessionTitle(s))
    D.pill:SetCustom(s.legacy and "CARRIED OVER" or short, s.legacy and C.dim or ns.ACTIVITY_COLOR[activity])
    D.best:SetCustom(ns.BestIDs()[s.id] and "BEST" or nil, C.accent)
    local parts = {}
    local d0, d1 = ns.Date("%a %d %b, %H:%M", s.t0), ns.Date("%H:%M", s.t1)
    if d0 then parts[#parts + 1] = d0 .. (d1 and (" - " .. d1) or "") end
    parts[#parts + 1] = ((s.c or "?"):gsub("%-.*$", "")) .. (s.lvl and (" (" .. s.lvl .. ")") or "")
    parts[#parts + 1] = ns.Clock(s.act) .. " active"
    if (s.idle or 0) >= 60 then parts[#parts + 1] = math.floor(s.idle / 60) .. " min idle not counted" end
    if (s.paused or 0) >= 60 then parts[#parts + 1] = ns.Dur(s.paused) .. " paused" end
    if s.auto then parts[#parts + 1] = "started by itself" end
    if s.prev then parts[#parts + 1] = "continues an earlier session" end
    if s.legacy then parts[#parts + 1] = "carried over from the old trackers (start time unknown)" end
    local opened = 0
    for _, n in pairs(s.opened or {}) do opened = opened + n end
    if opened > 0 then parts[#parts + 1] = opened .. " container" .. (opened == 1 and "" or "s") .. " opened (counted as what was inside)" end
    D.meta:SetText(table.concat(parts, "  .  "))

    -- tiles
    local T = D.tiles
    T[1]:Set("Farmed", KM.Money(t.value), revalue and "at today's prices" or "at loot prices")
    local avg = zoneAverage(s)
    T[2]:Set("Gold/hr", t.gph and KM.Money(t.gph) or "-",
        (t.gph and avg) and ns.Delta((t.gph - avg) / avg * 100, "vs your avg here") or (t.gph and "active time only" or "under a minute"))
    T[3]:Set("Active", ns.Clock(s.act), (s.t1 and s.t0 and s.t1 > s.t0) and ("of " .. ns.Clock(s.t1 - s.t0)) or "")
    local corpses = s.src and s.src.mob and s.src.mob.n or 0
    T[4]:Set("Coin", KM.Money(s.coin or 0), corpses > 0 and ("from " .. corpses .. " corpses") or "")
    local perMin = (s.act or 0) >= 60 and string.format("%.1f/min", (s.kills or 0) / s.act * 60) or ""
    T[5]:Set("Kills", tostring(s.kills or 0), perMin .. ((s.deaths or 0) > 0 and ("  .  " .. s.deaths .. " death" .. (s.deaths == 1 and "" or "s")) or ""))
    T[6]:Set("Net", KM.Money(t.net), t.costs ~= 0 and (KM.Money(t.costs, true) .. " costs") or "no costs")

    -- gold over time (cumulative, x = active minutes)
    local tl = ns.Unpack(s.tl)
    local pts = {}
    if tl and #tl.v > 0 then
        local sum = 0
        pts[1] = { 0, 0 }
        for i, v in ipairs(tl.v) do
            sum = sum + v
            pts[#pts + 1] = { i * tl.bw / 60, sum }
        end
    end
    D.chart:Draw({
        series = { { pts = pts, style = "area", color = C.accent, agg = "last" } },
        format = function(y) return KM.Money(y, true) end,
        xformat = function(x) local m = math.floor(x + 0.5); return string.format("%d:%02d", math.floor(m / 60), m % 60) end,
        endLabel = true,
        hover = function(x, p)
            GameTooltip:AddLine(string.format("%d min active", math.floor(x + 0.5)), 1, 1, 1)
            if p then GameTooltip:AddLine(KM.Money(p[2]) .. " farmed by then", 0.8, 0.8, 0.8) end
        end,
        emptyText = s.compact and "No timeline: older than 45 days" or (s.legacy and "No timeline: carried over from the old trackers" or "Nothing farmed yet"),
    })

    -- where it came from
    D.bars:SetRows(sourceBars(s))
    local np = 0
    for _, it in pairs(s["items"] or {}) do if it.np and (it.v or 0) == 0 then np = np + 1 end end
    D.note:SetText(np > 0 and (np .. " item" .. (np == 1 and " has" or "s have") .. " no price yet: scan at the auction house") or "")

    -- the tab
    D.tabs:Select(D.tab)
    for _, f in ipairs({ D.items, D.mobs, D.gather, D.money }) do f:Hide() end
    D.nodes:SetText("")
    if D.tab == "mobs" then
        D.mobs:Show(); D.mobs:SetRows(mobRows(s), fillMob)
    elseif D.tab == "gathering" then
        D.gather:Show(); D.gather:SetRows(gatherRows(s), fillGather)
        local nodes = {}
        for name, n in pairs(s.nodes or {}) do nodes[#nodes + 1] = name .. " " .. n end
        table.sort(nodes)
        D.nodes:SetText(#nodes > 0 and ("Nodes: " .. table.concat(nodes, "  .  ")) or "")
    elseif D.tab == "money" then
        D.money:Show()
        local wallet, costs = moneyLines(s)
        for i, r in ipairs(D.walletRows) do
            local e = wallet[i]
            r.l:SetText(e and e[1] or ""); r.r:SetText(e and e[2] or "")
        end
        for i, r in ipairs(D.costRows) do
            local e = costs[i]
            r.l:SetText(e and e[1] or ""); r.r:SetText(e and e[2] or "")
        end
    else
        D.items:Show(); D.items:SetRows(itemRows(s), fillItem)
    end
end

ns.D = D
