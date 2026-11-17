local _, KM = ...
local ns = KM.Module("Cooldowns")
local UI = KM.UI
local C = UI.C

-- The Cooldowns page (Crafting > Cooldowns, /cdk, /km cooldowns):
--   tiles       ready now, next up, income a week, lost to idling this week
--   toolbar     Everyone / This character, a profession filter, "Hide not ready", Shopping
--   table       one line per character and cooldown: a bar and the time left (READY in green), what to make, profit
--               each and per week, materials for one craft (here, and on alts)
--   detail      the selected line: what it sells for, materials, profit, per week, trend, last crafted and pace;
--               the choices in its group by gold per day, and the product's price chart
-- Also here: the "ready" toast (our own frame), the crown's quick action and tooltip line, the Home tile and note,
-- Settings.

local TILE_W, TILE_H = 182, 60
local DETAIL_H = 190
local TICK = 15

local page, tbl, tiles, tabs, profBtn, readyChk, shopBtn, emptyHint
local detail = {}
local list = {}
local ticker

local function hex(c, t) return UI.Hex(c) .. t .. "|r" end
local function grey(t) return hex(C.muted, t) end

local function classColour(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.colorStr then return cc.colorStr:sub(3) end
    if cc and cc.r then return string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) end
    return "ffffff"
end

-- Two money units at most, so columns fit: "78g 50s".
local function short(c)
    if c == nil then return grey("-") end
    local P = KM.mods.Profession
    if P and P.Short then return P.Short(c) end
    return KM.Money(c)
end

local function signed(c)
    if c == nil then return grey("-") end
    if c > 0 then return hex(C.good, "+") .. short(c) end
    return short(c)
end

local function charText(c, key, meKey)
    local name = ns.CharName(c, key)
    local realm = c.realm and c.realm ~= "" and meKey and not meKey:find("-" .. c.realm, 1, true) and (" " .. grey(c.realm)) or ""
    return "|cff" .. classColour(c.class) .. name .. "|r" .. realm
end

-- One place to make a chart, so it can move (Econ's graph today; a shared Core chart later) without touching the page.
local function createChart(parent, w, h)
    local E = KM.mods.Econ
    local make = E and E.CreateGraph
    if not make then return nil end
    return KM.Safe(make, parent, w, h)
end

---------------------------------------------------------------------------
-- Materials for one craft: on this character, and on everyone else
---------------------------------------------------------------------------

local function countOn(id, key)
    if key == KM.Char() and C_Item and C_Item.GetItemCount then
        local n = ns.Call(C_Item.GetItemCount, id, true)
        if type(n) == "number" then return n end
    end
    if InventoryKing and InventoryKing.GetCount then
        local _, by = ns.Call(InventoryKing.GetCount, id)
        return type(by) == "table" and by[key] or 0
    end
    return 0
end

local function totalOf(id)
    if InventoryKing and InventoryKing.GetCount then
        local t = ns.Call(InventoryKing.GetCount, id)
        if type(t) == "number" then return t end
    end
    return 0
end

-- Crafts the character's own stock covers, crafts everyone else's covers, and the first material nobody has.
function ns.Mats(key, spell)
    local r = spell and ns.Recipe(spell)
    if not r then return nil end
    local m = KM.mods.Market
    local here, others, missing = math.huge, math.huge, nil
    for i = 1, #(r.reagents or {}), 2 do
        local id, n = r.reagents[i], r.reagents[i + 1] or 1
        if not (m and m.VENDOR_ITEMS and m.VENDOR_ITEMS[id]) then
            local mine = countOn(id, key)
            local rest = math.max(0, math.max(totalOf(id), mine) - mine)
            here = math.min(here, math.floor(mine / n))
            others = math.min(others, math.floor((mine + rest) / n))
            if mine + rest < n and not missing then missing = id end
        end
    end
    if here == math.huge then return 0, 0, nil, true end   -- vendor materials only
    return here, math.max(0, others - here), missing
end

local function matsText(key, spell)
    local here, others, missing, vendorOnly = ns.Mats(key, spell)
    if here == nil then return grey("-") end
    if vendorOnly then return grey("vendor") end
    if missing and here == 0 then return hex(C.bad, "need " .. ns.ItemName(missing)) end
    if here == 0 then return hex(C.bad, "0, " .. others .. " alts") end
    return tostring(here) .. (others > 0 and grey(" (+" .. others .. ")") or "")
end

---------------------------------------------------------------------------
-- Status text and the row
---------------------------------------------------------------------------

function ns.StatusText(row)
    if row.unread then return hex(C.dim, "open " .. ns.ProfName(row.g and row.g.prof) .. " once to read") end
    local s
    if row.ready then
        s = hex(C.good, "READY")
        if (row.idle or 0) >= 3600 then s = s .. " " .. hex(C.warn, ns.Duration(row.idle) .. " idle") end
    else
        s = row.left < 3600 and hex(C.warn, ns.Duration(row.left)) or ns.Duration(row.left)
        if row.est then s = s .. grey(" est") end
    end
    if row.noTool then s = s .. " " .. hex(C.warn, "no " .. (row.g.tool == 9149 and "stone" or "tool")) end
    return s
end

local function fillRow(r, row, cells)
    local g = row.g
    local spell, v = nil, nil
    if not row.unread then spell, v = ns.Pick(row.key, row.gk) end
    row.each, row.week = v and v.profit, v and v.perWeek
    if r.icon then r.icon:SetTexture(ns.ItemIcon(v and v.item or (g and g.icon)) or "Interface\\Icons\\INV_Misc_PocketWatch_01") end
    local label = g and g.label or row.gk
    cells.name:SetText(g and g.discovered and hex(C.accent, label) or label)
    cells.char:SetText(charText(row.c, row.key, KM.Char()) .. (row.me and grey(" (you)") or ""))
    -- a bar in the Status column, made once per pooled row frame
    if not r.cdBar then
        local col = tbl.cols[3]
        r.cdBar = UI.Bar(r, 6)
        r.cdBar:SetPoint("LEFT", col.x, 0)
        r.cdBar:SetWidth(54)
        cells.status:ClearAllPoints()
        cells.status:SetPoint("LEFT", col.x + 60, 0)
        cells.status:SetWidth(col.w - 64)
    end
    if row.unread then
        r.cdBar:Hide()
    else
        r.cdBar:Show()
        r.cdBar:Set(row.frac or 0, row.ready and C.good or (row.left and row.left < 3600 and C.warn or C.accent))
    end
    cells.status:SetText(ns.StatusText(row))
    cells.make:SetText(v and v.item and ns.ItemName(v.item) or grey("-"))
    cells.each:SetText(signed(row.each))
    cells.week:SetText(signed(row.week))
    cells.mats:SetText(spell and matsText(row.key, spell) or grey("-"))
    r:SetAlpha(row.old and 0.5 or 1)
end

local function rowTip(r)
    local row = r.data
    if not row then return end
    local g, e, c = row.g, row.e, row.c
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:AddLine((g and g.label or row.gk) .. "  -  " .. ns.CharName(c, row.key))
    if row.unread then
        GameTooltip:AddLine("Open this character's " .. ns.ProfName(g and g.prof) .. " window once (or craft it) and King Maker reads the timer from then on.", 1, 1, 1, true)
    else
        local srcText = { recipe = "the profession window", item = "the Salt Shaker", spell = "the game's spell cooldown", cast = "your craft (an estimate until the game confirms it)" }
        if e.at then GameTooltip:AddDoubleLine("Read from", (srcText[e.src] or tostring(e.src)) .. ", " .. KM.Ago(e.at) .. " ago", 1, 1, 1, 1, 1, 1) end
        local spell = ns.Pick(row.key, row.gk) or e.spell
        local l = spell and ns.db.learned[spell]
        GameTooltip:AddDoubleLine("Full length", ns.Duration(e.dur or ns.Dur(spell)) .. ((l and l.dur) and " (as the game reported)" or ""), 1, 1, 1, 1, 1, 1)
        if e.day then GameTooltip:AddLine("Resets at the daily reset.", 0.8, 0.8, 0.8) end
        if g and g.tool then
            local have = c.tools[g.tool]
            GameTooltip:AddDoubleLine("Needs", ns.TOOLS[g.tool] .. (have == false and hex(C.warn, " (not in your bags or bank)") or ""), 1, 1, 1, 1, 1, 1)
        end
        if g and g.where then GameTooltip:AddDoubleLine("Made", g.where, 1, 1, 1, 1, 1, 1) end
        if g and g.shared then GameTooltip:AddLine("Every transmute shares this one cooldown.", 0.8, 0.8, 0.8) end
        local n, share, last = ns.Pace(row.key, row.gk)
        GameTooltip:AddDoubleLine("Last crafted", last and (KM.Ago(last) .. " ago") or "not seen", 1, 1, 1, 1, 1, 1)
        if n > 0 then GameTooltip:AddDoubleLine("Last 28 days", n .. " crafts (" .. math.floor(share * 100 + 0.5) .. "% of the most)", 1, 1, 1, 1, 1, 1) end
        if row.ready then
            local secs, crafts, gold = ns.Idle(row.key, row.gk)
            if secs >= 3600 then GameTooltip:AddDoubleLine("Idle", ns.Duration(secs) .. string.format(" (~%.2f crafts", crafts) .. (gold and gold > 0 and (", ~" .. short(gold)) or "") .. ")", 1, 1, 1, 1, 1, 1) end
        end
    end
    if c.seen then GameTooltip:AddLine("Character last seen " .. KM.Ago(c.seen) .. " ago.", 0.6, 0.6, 0.6) end
    GameTooltip:AddLine("Click: details below.  Right-click: stop tracking, forget, what to make.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function ns.RowMenu(owner, row)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        KM.Print(ns, "use /cdk forget " .. ns.CharName(row.c, row.key) .. " to stop tracking a character.")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle((row.g and row.g.label or row.gk) .. " - " .. ns.CharName(row.c, row.key))
        if not row.unread then
            local choices = ns.Choices(row.key, row.gk)
            if #choices > 1 then
                local current = ns.Pick(row.key, row.gk)
                for _, v in ipairs(choices) do
                    root:CreateRadio("Make: " .. ns.ItemName(v.item), function() return current == v.spell end,
                        function() ns.SetPick(row.key, row.gk, v.spell) end)
                end
            end
        end
        root:CreateButton("Stop tracking this cooldown", function()
            row.c.hide[row.gk] = true
            ns.Changed(true)
        end)
        root:CreateButton("Forget this character", function() ns.Forget(row.key) end)
    end)
end

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------

local function refreshTiles(s)
    tiles[1]:Set("Ready now", tostring(s.ready), s.ready == 0 and "nothing waiting" or (s.readyHere .. " here, " .. s.readyAlts .. " on alts"),
        s.readyHere > 0 and C.bad or (s.ready > 0 and C.accent or C.text))
    if s.next then
        tiles[2]:Set("Next up", ns.Group(s.next.gk).label, ns.CharName(s.next.c, s.next.key) .. ", in " .. ns.Duration(s.next.left))
    else
        tiles[2]:Set("Next up", "-", s.tracked == 0 and "nothing tracked yet" or "everything is ready", C.dim)
    end
    tiles[3]:Set("Income / week", s.week > 0 and short(s.week) or "-",
        s.groups > 0 and (s.groups .. " cooldown" .. (s.groups == 1 and "" or "s") .. " on " .. s.chars .. " character" .. (s.chars == 1 and "" or "s")) or "scan at the auction house for prices",
        s.week > 0 and C.good or C.dim)
    tiles[4]:Set("Lost to idling", s.idleWeek > 0 and ("~" .. short(s.idleWeek)) or "-",
        s.idleWeek > 0 and string.format("this week, %.1f crafts' worth", s.idleCrafts) or "this week", s.idleWeek > 0 and C.warn or C.text)
end

-- Tile tooltips: what each number is, then the lines behind it (biggest first, up to six).
local PRICE_RULE = "Profit each: the product's lowest auction after the 5% cut, minus materials at the cheaper of their lowest auction or a vendor."

local function topLines(tt, rows, fmt)
    table.sort(rows, function(a, b) return a.v > b.v end)
    for i = 1, math.min(6, #rows) do
        local r = rows[i]
        tt:AddDoubleLine(r.label .. "  " .. grey(r.name), fmt(r), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if #rows > 6 then tt:AddLine("and " .. (#rows - 6) .. " more", 0.6, 0.6, 0.6) end
end

local function eachTracked(fn)
    for key, c in pairs(ns.db.chars) do
        for gk, e in pairs(c.cds or {}) do
            local g = ns.Group(gk)
            if g and not c.hide[gk] then fn(key, c, gk, e, g) end
        end
    end
end

local function readyTip(tt)
    tt:AddLine("Cooldowns ready to craft right now, on this character and on your alts. Red: one is waiting on the character you're on.", 1, 1, 1, true)
    tt:AddLine("A transmute without a Philosopher's Stone in bags or bank isn't counted (Settings > Cooldowns).", 0.8, 0.8, 0.8, true)
    local here, alts = ns.ReadyList()
    for _, it in ipairs(here) do tt:AddDoubleLine(it.label, it.name .. " (you)", 0.8, 0.8, 0.8, C.good[1], C.good[2], C.good[3]) end
    for i, it in ipairs(alts) do
        if i > 6 then tt:AddLine("and " .. (#alts - 6) .. " more on alts", 0.6, 0.6, 0.6) break end
        tt:AddDoubleLine(it.label, it.name, 0.8, 0.8, 0.8, 1, 1, 1)
    end
end

local function weekTip(tt)
    tt:AddLine("What your cooldowns make in a week if you craft each one as soon as it's ready: profit each x crafts a week (7 days / the cooldown), added up over every character.", 1, 1, 1, true)
    tt:AddLine(PRICE_RULE .. (ns.Mode() == "farm" and " Crafting Profits is on farm mode, so profit is how much crafting beats selling the materials." or ""), 0.8, 0.8, 0.8, true)
    tt:AddLine("Cooldowns at a loss or with a price missing aren't added.", 0.8, 0.8, 0.8, true)
    local rows = {}
    eachTracked(function(key, c, gk, e, g)
        local _, v = ns.Pick(key, gk)
        if v and v.perWeek and v.perWeek > 0 then rows[#rows + 1] = { label = g.label, name = ns.CharName(c, key), v = v.perWeek } end
    end)
    if #rows > 0 then tt:AddLine(" ") end
    topLines(tt, rows, function(r) return short(r.v) end)
end

local function idleTip(tt)
    tt:AddLine("Profit missed in the last 7 days while a cooldown sat ready and nobody crafted it: time idle / the cooldown's length = crafts missed, x profit each at today's prices.", 1, 1, 1, true)
    tt:AddLine("Only cooldowns that make a profit count.", 0.8, 0.8, 0.8, true)
    local now, rows = ns.Now(), {}
    eachTracked(function(key, c, gk)
        local secs, crafts, gold = ns.IdleWeek(key, gk, now)
        if gold and gold > 0 then rows[#rows + 1] = { label = ns.Group(gk).label, name = ns.CharName(c, key), v = gold, secs = secs, crafts = crafts } end
    end)
    if #rows > 0 then tt:AddLine(" ") end
    topLines(tt, rows, function(r) return ns.Duration(r.secs) .. string.format(", %.1f crafts, ~", r.crafts) .. short(r.v) end)
end

---------------------------------------------------------------------------
-- The detail panel
---------------------------------------------------------------------------

local function pct(x)
    if not x then return grey("-") end
    local p = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
    return hex(p > 0 and C.good or (p < 0 and C.bad or C.muted), (p > 0 and "+" or "") .. p .. "%")
end

local function selectedRow()
    local sel = ns.db.ui.selected
    for _, row in ipairs(list) do
        if sel == row.key .. "|" .. row.gk then return row end
    end
    return list[1]
end

local function drawChart(item)
    local g = detail.chart
    if not g then return end
    local pts = {}
    if item and EconKing and EconKing.GetHistory then
        local h = ns.Call(EconKing.GetHistory, item) or {}
        for i = math.max(1, #h - 59), #h do
            local v = h[i]
            local p = v and (v[2] or v[3])
            if v and v[1] and p then pts[#pts + 1] = { v[1], p } end
        end
    end
    local tmin, tmax = pts[1] and pts[1][1] or ns.Now() - 86400, pts[#pts] and pts[#pts][1] or ns.Now()
    if tmax <= tmin then tmin = tmax - 86400 end
    KM.Safe(g.Draw, g, { tmin = tmin, tmax = tmax, emptyText = "No price history yet: scan at the auction house",
        series = { { pts = pts, color = C.accent, style = "line" } }, format = function(v) return short(v) end })
end

local function drawDetail()
    local row = selectedRow()
    detail.row = row
    local L = detail.lines
    if not row then
        detail.title:SetText("")
        detail.status:SetText(grey("Pick a line above to see what it's worth."))
        for _, l in ipairs(L) do l.l:SetText(""); l.v:SetText("") end
        detail.choices:SetRows({})
        detail.shop:Hide(); detail.hist:Hide()
        drawChart(nil)
        return
    end
    local g = row.g
    detail.title:SetText(((g and g.label or row.gk) .. "  .  " .. ns.CharName(row.c, row.key)):upper())
    local spell, v, choices = nil, nil, {}
    if not row.unread then spell, v, choices = ns.Pick(row.key, row.gk) end
    choices = choices or {}
    if row.unread then
        detail.status:SetText(hex(C.dim, "Open " .. ns.ProfName(g and g.prof) .. " once on this character to read it."))
    elseif row.ready then
        local secs, crafts, gold = ns.Idle(row.key, row.gk)
        detail.status:SetText(hex(C.good, "Ready") .. (secs >= 60 and (" for " .. ns.Duration(secs) .. grey(string.format("  (~%.2f crafts", crafts) .. (gold and gold > 0 and (", ~" .. short(gold) .. " idle") or "") .. ")")) or ""))
    else
        detail.status:SetText("Ready in " .. ns.Duration(row.left) .. (row.est and grey("  (estimated from your craft)") or ""))
    end
    local rows = {}
    local function add(a, b) rows[#rows + 1] = { a, b } end
    local item = v and v.item
    if item then
        local best = choices[1] and choices[1].spell == spell
        add("Make", ns.ItemName(item) .. ((v.made or 1) > 1 and (" x" .. v.made) or "") .. grey(best and "   best now" or "   your pick"))
        local depth = ""
        local _, _, listed = ScannerKing and ScannerKing.GetPrice and ns.Call(ScannerKing.GetPrice, item)
        local st = EconKing and EconKing.GetStats and ns.Call(EconKing.GetStats, item)
        if listed then depth = listed .. " listed" end
        if type(st) == "table" and st.gonePerDay then depth = depth .. (depth ~= "" and ", " or "") .. string.format("~%d a day", math.floor(st.gonePerDay + 0.5)) end
        add("Sells for", short(v.price) .. (depth ~= "" and grey("   " .. depth) or ""))
        local here, others = ns.Mats(row.key, spell)
        add("Materials", (v.missing and hex(C.bad, "no price for " .. ns.ItemName(v.missing)) or short(v.cost)) .. (here and grey("   have " .. here .. (others and others > 0 and (", alts " .. others) or "")) or ""))
        local mode = ns.Mode()
        add(mode == "farm" and "Beats selling mats" or "Profit each", signed(v.profit) .. grey(mode == "farm" and ("   bought: " .. (v.buyProfit and short(v.buyProfit) or "-")) or "   after the 5% cut"))
        local dur = ns.Dur(spell)
        add("Per week", signed(v.perWeek) .. grey(string.format("   %.2f crafts (1 / %s)", 7 * 86400 / dur, ns.Duration(dur))))
        if type(st) == "table" then add("30d avg / 7d", short(st.avg30) .. "  /  " .. pct(st.trend7)) end
        local n, share, last = ns.Pace(row.key, row.gk)
        add("Last crafted", (last and (KM.Ago(last) .. " ago") or "not seen") .. grey(n > 0 and string.format("; %d in 28 days (%d%%)", n, math.floor(share * 100 + 0.5)) or ""))
    else
        add("Make", grey(KM.mods.Market and "-" or "Crafting Profits is off: timers only"))
    end
    for i, l in ipairs(L) do
        local r = rows[i]
        l.l:SetText(r and r[1] or "")
        l.v:SetText(r and r[2] or "")
    end
    detail.choices:SetRows(choices, function(r, c, cells)
        r.item = c.item
        if r.icon then r.icon:SetTexture(ns.ItemIcon(c.item)) end
        cells.make:SetText((c.spell == spell and hex(C.accent, "* ") or "") .. ns.ItemName(c.item))
        cells.cost:SetText(c.missing and grey("no price") or short(c.cost))
        cells.each:SetText(signed(c.profit))
        cells.day:SetText(signed(c.perDay) .. grey(" (" .. ns.Duration(c.dur) .. ")"))
    end)
    detail.choices.emptyText = row.unread and "" or "Scan at the auction house for prices."
    local canShop = item and ShoppingKing and ShoppingKing.Add and true or false
    detail.shop:SetShown(canShop)
    detail.hist:SetShown(item and KM.pages and KM.pages.history and true or false)
    drawChart(item)
end

---------------------------------------------------------------------------
-- Drawing the page
---------------------------------------------------------------------------

local function profLabel()
    local p = ns.db.ui.prof
    return p and ns.ProfName(p) or "All professions"
end

local function refresh()
    if not page or not ns.db then return end
    local u = ns.db.ui
    local s = ns.Summary()
    refreshTiles(s)
    tabs:Select(u.view)
    profBtn:Refresh()
    readyChk:SetChecked(u.readyOnly)
    shopBtn:SetShown(ns.ShoppingAvailable())
    list = ns.Entries(u.view, u.prof, u.readyOnly)
    for _, row in ipairs(list) do
        if not row.unread then
            local _, v = ns.Pick(row.key, row.gk)
            row.each, row.week = v and v.profit, v and v.perWeek
        end
    end
    ns.SortRows(list, u.sort, u.desc)
    tbl:SetSort(u.sort, u.desc)
    tbl.selected = selectedRow()
    tbl.emptyText = s.tracked == 0 and "No crafting cooldowns yet. Log in on each crafter and open its profession window once." or "Nothing matches."
    tbl:SetRows(list, fillRow)
    drawDetail()
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(TICK, function(self)
            if not KM.IsShown("cooldowns") then self:Cancel(); ticker = nil return end
            ns.CheckFlips(false)
            KM.Refresh("cooldowns")
        end)
    end
end

local function hide()
    if ticker then ticker:Cancel(); ticker = nil end
end

function ns.Refresh() KM.Refresh("cooldowns") end
function ns.List() return list end
function ns.IsTicking() return ticker ~= nil end

function ns.ShopWeek()
    if not ns.ShoppingAvailable() then return end
    local items = ns.ShoppingItems()
    if #items == 0 then
        KM.Print(ns, "you already own the materials for the next " .. ns.db.settings.days .. " days of cooldowns.")
    else
        local parts = {}
        for i, it in ipairs(items) do
            if i > 6 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = it.qty .. " " .. ns.ItemName(it.itemID)
        end
        KM.Print(ns, "the Shopping list \"" .. ns.SHOP_LIST .. "\" has " .. table.concat(parts, ", ") .. ".")
    end
    if KM.pages and KM.pages.shopping then KM.Show("shopping") end
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function line(parent, y)
    local l = UI.Text(parent, 11, C.muted)
    l:SetPoint("TOPLEFT", 10, y)
    l:SetWidth(110)
    local v = UI.Text(parent, 11, C.text)
    v:SetPoint("TOPLEFT", 122, y)
    v:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return { l = l, v = v }
end

local function buildDetail(c)
    local box = CreateFrame("Frame", nil, c)
    box:SetPoint("BOTTOMLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    box:SetHeight(DETAIL_H)
    local left = UI.Panel(box, C.panel)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    local right = UI.Panel(box, C.panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT")
    left:SetWidth(376)
    box:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then left:SetWidth(math.floor((w - 10) / 2)) end end)
    detail.box, detail.left, detail.right = box, left, right

    detail.title = UI.Heading(left, "")
    detail.title:SetPoint("TOPLEFT", 10, -9)
    detail.status = UI.Text(left, 12, C.text)
    detail.status:SetPoint("TOPLEFT", 10, -26)
    detail.status:SetPoint("RIGHT", left, "RIGHT", -8, 0)
    detail.lines = {}
    for i = 1, 7 do detail.lines[i] = line(left, -46 - (i - 1) * 15) end
    detail.shop = UI.Button(left, "Shopping: " .. "mats", 120, 22, function()
        local row = detail.row
        if not row then return end
        local n = ns.AddToShopping(row.key, row.gk)
        KM.Print(ns, n > 0 and ("added " .. n .. " material" .. (n == 1 and "" or "s") .. " to the Shopping list \"Crafting\".") or "nothing to add: you have the materials.")
    end, "primary")
    detail.shop:SetPoint("BOTTOMLEFT", 10, 8)
    UI.Tip(detail.shop, "Adds what this cooldown needs for the next days (Settings > Cooldowns) and you don't own anywhere to the Shopping list \"Crafting\".")
    detail.hist = UI.Button(left, "History", 70, 22, function()
        local row = detail.row
        local spell = row and not row.unread and ns.Pick(row.key, row.gk)
        local item = spell and ns.Product(spell)
        local E = KM.mods.Econ
        if not item then return end
        if E and E.Toggle and E.ShowItem then
            KM.Safe(E.Toggle, true)
            KM.Safe(E.ShowItem, item)
        else
            KM.Show("history")
        end
    end)
    detail.hist:SetPoint("LEFT", detail.shop, "RIGHT", 6, 0)
    UI.Tip(detail.hist, "Open the product in Price History.")

    local h = UI.Heading(right, "Choices for this cooldown")
    h:SetPoint("TOPLEFT", 10, -9)
    local by = UI.Text(right, 10, C.dim, "RIGHT")
    by:SetPoint("TOPRIGHT", -10, -9)
    by:SetText("by gold per day")
    detail.choices = UI.Table(right, {
        { key = "make", label = "Make", w = 120, tip = "Everything this character can make with this cooldown. * marks the one it's set to make; click another to pick it." },
        { key = "cost", label = "Cost", w = 64, justify = "RIGHT", tip = "Materials for one craft, each at the cheaper of its lowest auction or a vendor." },
        { key = "each", label = "Each", w = 70, justify = "RIGHT", tip = "Profit from one craft, after the 5% auction cut." },
        { key = "day", label = "Per day", w = 0, justify = "RIGHT", tip = "Profit each spread over the cooldown it blocks (in brackets). The list is sorted by this: a two-day transmute has to beat two one-day ones." },
    }, 18, { icon = true, fontSize = 11, noSort = true, onClick = function(v)
        local row = detail.row
        if row and not row.unread then ns.SetPick(row.key, row.gk, v.spell) end
    end })
    detail.choices:SetPoint("TOPLEFT", 6, -24)
    detail.choices:SetPoint("TOPRIGHT", -6, -24)
    detail.choices:SetHeight(20 + 18 * 4)
    local ph = UI.Heading(right, "Price")
    ph:SetPoint("TOPLEFT", 10, -122)
    detail.chart = createChart(right, 356, 54)
    if detail.chart and detail.chart.frame then detail.chart.frame:SetPoint("TOPLEFT", 4, -132) end
end

local function buildPage(c)
    page = c
    tiles = {}
    for i = 1, 4 do
        local t = UI.Tile(c, TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), 0)
        tiles[i] = t
    end
    tiles[1]:SetTip(readyTip)
    tiles[2]:SetTip("The tracked cooldown that comes ready soonest, on any of your characters.")
    tiles[3]:SetTip(weekTip)
    tiles[4]:SetTip(idleTip)
    local y = -(TILE_H + 12)
    tabs = UI.Tabs(c, { { id = "all", label = "Everyone" }, { id = "here", label = "This character" } }, function(id)
        ns.db.ui.view = id
        tbl.offset = 0
        ns.Refresh()
    end)
    tabs:SetPoint("TOPLEFT", 0, y)
    profBtn = UI.MenuButton(c, 140, profLabel, function(_, root)
        root:CreateRadio("All professions", function() return ns.db.ui.prof == nil end, function() ns.db.ui.prof = nil; ns.Refresh() end)
        local seen = {}
        for _, gk in ipairs(ns.GroupKeys()) do
            local g = ns.Group(gk)
            if g and g.prof and not seen[g.prof] then
                seen[g.prof] = true
                local p = g.prof
                root:CreateRadio(ns.ProfName(p), function() return ns.db.ui.prof == p end, function() ns.db.ui.prof = p; ns.Refresh() end)
            end
        end
    end)
    profBtn:SetPoint("LEFT", tabs, "RIGHT", 12, 0)
    readyChk = UI.CheckLabel(c, "Hide not ready", function(v) ns.db.ui.readyOnly = v; tbl.offset = 0; ns.Refresh() end)
    readyChk.frame:SetPoint("LEFT", profBtn, "RIGHT", 14, 0)
    shopBtn = UI.Button(c, "Shopping: a week of mats", 180, 24, function() ns.ShopWeek() end, "primary")
    shopBtn:SetPoint("TOPRIGHT", 0, y)
    UI.Tip(shopBtn, "The Shopping list \"Cooldown mats\" fills itself: what your characters need for the next days of cooldowns, minus what you own anywhere. Opens Shopping.")

    local function col(key, label, w, justify, sortable, tip)
        return { key = key, label = label, w = w, justify = justify, sort = sortable and function() return 0 end or nil, desc = false, tip = tip }
    end
    tbl = UI.Table(c, {
        col("name", "Cooldown", 140, nil, true, "A gold name is a cooldown King Maker found in your profession window that isn't in its built-in list."),
        col("char", "Character", 110, nil, true),
        col("status", "Status", 160, nil, true, function(tt)
            tt:AddLine("Status")
            tt:AddLine("The bar fills as the cooldown runs down.", 1, 1, 1, true)
            tt:AddDoubleLine(hex(C.good, "READY"), "craft it now (idle: how long it has waited)", 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine(hex(C.warn, "time in orange"), "ready within the hour", 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine(grey("est"), "guessed from your craft until the game confirms it", 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine(hex(C.warn, "no stone / no tool"), "the tool isn't in bags or bank", 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine(hex(C.dim, "open ... once"), "not read yet on that character", 1, 1, 1, 1, 1, 1)
        end),
        col("make", "Make", 110, nil, false, "What the character makes with it: the best profit per day, or your pick. Right-click a line to change it."),
        col("each", "Each", 74, "RIGHT", true, "Profit from one craft. " .. PRICE_RULE),
        col("week", "Week", 74, "RIGHT", true, "Profit each x the crafts the cooldown allows in 7 days."),
        col("mats", "Mats", 0, "RIGHT", false, "Crafts the materials on this character cover; (+n): more with what your alts hold. Red: not enough here. vendor: everything comes from a vendor."),
    }, 24, {
        icon = true, noSort = true,
        onSort = function(key, desc)
            ns.db.ui.sort, ns.db.ui.desc = key, desc
            tbl.offset = 0
            ns.Refresh()
        end,
        onClick = function(row, which, r)
            if which == "RightButton" then ns.RowMenu(r, row) return end
            ns.db.ui.selected = row.key .. "|" .. row.gk
            ns.Refresh()
        end,
        onEnter = rowTip,
    })
    tbl:SetPoint("TOPLEFT", 0, y - 34)
    tbl:SetPoint("BOTTOMRIGHT", 0, DETAIL_H + 10)
    tbl.fill = fillRow
    ns.table = tbl
    buildDetail(c)
    ns.detail = detail
end

local function icon()
    local p = "Interface\\Icons\\INV_Misc_PocketWatch_01"
    if GetFileIDFromPath and not GetFileIDFromPath(p) then return "Interface\\Icons\\Trade_Alchemy" end
    return p
end

KM.RegisterPage({
    id = "cooldowns", group = "craft", label = "Cooldowns", icon = icon(), order = 30, crownBadge = true,
    title = "Cooldowns",
    subtitle = "Transmutes, Mooncloth and salt on every character: what's ready, what to make, what it's worth.",
    badge = function() return ns.Badge() end,
    build = buildPage, refresh = refresh, hide = hide,
})

---------------------------------------------------------------------------
-- The toast: our own small frame (no Blizzard alert frames)
---------------------------------------------------------------------------

local toast
ns.toasts = 0
function ns.Toast(text, itemIcon)
    if not toast then
        toast = CreateFrame("Button", "KingMakerCooldownToast", UIParent)
        toast:SetSize(250, 46)
        toast:SetPoint("TOP", 0, -140)
        toast:SetFrameStrata("HIGH")
        UI.Fill(toast, { C.bg[1], C.bg[2], C.bg[3], 0.94 })
        UI.Border(toast, { 1, 1, 1, 0.10 })
        UI.GoldEdge(toast)
        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(28, 28)
        toast.icon:SetPoint("LEFT", 9, 0)
        toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        toast.text = UI.Text(toast, 12, C.text)
        toast.text:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 9, -1)
        toast.text:SetPoint("RIGHT", -8, 0)
        toast.sub = UI.Text(toast, 10, C.muted)
        toast.sub:SetPoint("TOPLEFT", toast.text, "BOTTOMLEFT", 0, -4)
        toast.sub:SetText("King Maker: click to open Cooldowns")
        toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        toast:SetScript("OnClick", function(self, which)
            self:Hide()
            if which ~= "RightButton" then KM.Show("cooldowns") end
        end)
        toast:Hide()
    end
    toast.icon:SetTexture(ns.ItemIcon(itemIcon) or "Interface\\Icons\\INV_Misc_PocketWatch_01")
    toast.text:SetText(text)
    toast:Show()
    ns.toasts = ns.toasts + 1
    ns.lastToast = text
    if toast.timer then toast.timer:Cancel() end
    if C_Timer.NewTimer then toast.timer = C_Timer.NewTimer(8, function() toast:Hide(); toast.timer = nil end) end
end
function ns.ToastFrame() return toast end

---------------------------------------------------------------------------
-- The crown, Home and Settings
---------------------------------------------------------------------------

KM.RegisterQuickAction({ id = "cooldowns", label = "Cooldowns", order = 22, func = function() ns.Toggle(true) end })

-- The crown's tooltip: the first three by readiness.
KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local rows = ns.SortRows(ns.Entries("all"), "status")
    local parts = {}
    for _, r in ipairs(rows) do
        if #parts >= 3 then break end
        if not r.unread then
            parts[#parts + 1] = (r.g and r.g.label or r.gk) .. (r.ready and " ready" or (" in " .. ns.Duration(r.left))) .. " (" .. ns.CharName(r.c, r.key) .. ")"
        end
    end
    if #parts > 0 then tt:AddLine("Cooldowns: " .. table.concat(parts, ", "), 1, 1, 1, true) end
end)

KM.RegisterHomeTile({ id = "cooldowns", order = 40, page = "cooldowns", get = function()
    if not ns.db then return nil end
    local s = ns.Summary()
    if s.tracked == 0 then return nil end
    local sub
    local first = s.here[1] or s.alts[1]
    if first then sub = first.label .. " on " .. first.name elseif s.next then sub = ns.Group(s.next.gk).label .. " on " .. ns.CharName(s.next.c, s.next.key) end
    if s.week > 0 then sub = (sub and (sub .. ", ") or "") .. "~" .. short(s.week) .. " a week" end
    if s.ready > 0 then return "Cooldowns", s.ready .. " ready", sub, s.readyHere > 0 and C.bad or C.accent end
    return "Cooldowns", s.next and ("next in " .. ns.Duration(s.next.left)) or "-", sub, C.text
end, tip = "Profession cooldowns ready on any of your characters (red when one is ready on this one), or how long until the next comes back. The ~ a week figure is what your tracked cooldowns make if you use each one every time it's ready, at today's prices after the 5% cut, worked out like Crafting Profits. Click for Cooldowns." })

-- Home: what's ready (this character's each on a red row, alts' together in gold), each character's count, and what
-- the crafts you made in the period are worth at today's prices.
KM.RegisterHomeCard({ kind = "attention", id = "cooldowns", order = 10, get = function()
    if not ns.db then return nil end
    local here, alts = ns.ReadyList()
    local now, out = ns.Now(), {}
    for _, it in ipairs(here) do
        local idle = now - (it.e.readySince or it.e.ready or now)
        out[#out + 1] = { text = it.label .. " ready on " .. it.name, color = C.bad, page = "cooldowns",
            value = idle >= 3600 and ("idle " .. ns.Duration(idle)) or nil,
            tip = it.label .. " is ready on " .. it.name .. (idle >= 60 and (" and has been for " .. ns.Duration(idle)) or "") .. ". Every hour it waits is a craft you don't get back." }
    end
    if #alts > 0 then
        local names = {}
        for _, it in ipairs(alts) do names[#names + 1] = it.label .. " on " .. it.name end
        out[#out + 1] = { text = #alts .. " cooldown" .. (#alts == 1 and "" or "s") .. " ready on alts", color = C.accent, count = #alts,
            page = "cooldowns", tip = table.concat(names, "\n") }
    end
    return out
end })

KM.RegisterHomeCard({ kind = "chars", id = "cooldowns", order = 30, get = function()
    if not ns.db then return nil end
    local here, alts = ns.ReadyList()
    local out = {}
    for _, it in ipairs(here) do out[it.key] = out[it.key] or { n = 0, color = C.bad }; out[it.key].n = out[it.key].n + 1 end
    for _, it in ipairs(alts) do out[it.key] = out[it.key] or { n = 0, color = C.accent }; out[it.key].n = out[it.key].n + 1 end
    for _, f in pairs(out) do f.text = f.n .. " cd" .. (f.n == 1 and "" or "s") .. " ready"; f.tip = f.n .. " profession cooldown" .. (f.n == 1 and "" or "s") .. " ready." end
    return out
end })

KM.RegisterHomeCard({ kind = "income", id = "cooldowns", order = 30, get = function(since)
    if not ns.db then return nil end
    local total, n, value = 0, 0, {}
    for _, c in pairs(ns.db.chars) do
        for _, l in ipairs(c.log or {}) do
            if (l[1] or 0) >= since and l[3] then
                if value[l[3]] == nil then local v = ns.Value(l[3]); value[l[3]] = v and v.profit or false end
                local p = value[l[3]]
                if p and p > 0 then total, n = total + p, n + 1 end
            end
        end
    end
    if total <= 0 then return nil end
    return { { label = "Cooldowns", value = total, page = "cooldowns",
        tip = n .. " cooldown craft" .. (n == 1 and "" or "s") .. ", worth about " .. KM.Money(total) .. " at today's prices after the 5% cut (an estimate: what each would sell for, minus its materials)." } }
end })

local function set(k) return function(v) ns.db.settings[k] = v; ns.Changed(true) end end
local function get(k) return function() return ns.db.settings[k] end end

KM.RegisterSettings({ id = "cooldowns", label = "Cooldowns", order = 23, rows = {
    { type = "header", label = "The sidebar count" },
    { type = "choice", label = "Counts", options = { { "here", "This character" }, { "here+alts", "Here, alts in gold" }, { "any", "Any character" } },
      get = get("badge"), set = set("badge"),
      tip = "What the number by Cooldowns in the sidebar counts. Here, alts in gold: this character's ready ones in red; when it has none, your alts' in gold." },
    { type = "check", label = "Count a ready transmute without a Philosopher's Stone", get = get("noToolCounts"), set = set("noToolCounts"),
      tip = "Off: a transmute you can't do (no stone in your bags or bank) doesn't light the count." },
    { type = "header", label = "When a cooldown is ready" },
    { type = "check", label = "Chat line", get = get("chat"), set = set("chat") },
    { type = "check", label = "Pop-up (click it to open this page)", get = get("toast"), set = set("toast") },
    { type = "check", label = "Sound", get = get("sound"), set = set("sound") },
    { type = "check", label = "At login, list what's ready on your alts", get = get("login"), set = set("login") },
    { type = "check", label = "Tell me when an alt's cooldown is ready", get = get("altChat"), set = set("altChat"),
      tip = "A chat line when a cooldown comes ready on another of your characters while you play this one." },
    { type = "header", label = "Shopping list \"Cooldown mats\"" },
    { type = "range", label = "Covers the next", min = 1, max = 14, step = 1, get = get("days"), set = set("days"),
      fmt = function(v) return v .. (v == 1 and " day" or " days") end,
      tip = "How many days of crafting the list buys materials for: one craft now if ready, then one each time the cooldown comes back." },
    { type = "choice", label = "Counts", options = { { "realm", "Realm and faction" }, { "me", "This character" } },
      get = get("shopScope"), set = set("shopScope"),
      tip = "Whose cooldowns the list buys for: every character on this realm and faction, or only this one. What you already own anywhere is taken off." },
    { type = "header", label = "Characters" },
    { type = "button", label = "Forget characters not seen in 90 days", tip = "Deletes the cooldowns, picks and craft log of every character (not this one) you haven't logged in on for 90 days.", func = function()
        local n = ns.ForgetOld()
        KM.Print(ns, n > 0 and ("forgot " .. n .. " character" .. (n == 1 and "" or "s") .. ".") or "every character was seen in the last 90 days.")
    end },
    { type = "text", label = "Cooldowns come from the game: open each profession window once if a character shows \"open ... once\". Right-click a line on the page to stop tracking it or forget a character." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/cdk   open the Cooldowns page\n/cdk list   every character's cooldowns\n/cdk scan   read them now\n/cdk badge here|alts|any   what the count counts\n/cdk remind on|off   reminders\n/cdk forget Name   stop tracking a character\n/cdk debug   what the game reports" },
} })
