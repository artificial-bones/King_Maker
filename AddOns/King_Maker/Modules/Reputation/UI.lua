local _, KM = ...
local ns = KM.Module("Reputation")
local UI = KM.UI
local C = UI.C

-- The Reputation section of the sidebar:
--   Reputation     (overview) every tracked faction for your side: standing, a bar, rep to the next standing, rep a
--                  day at your 7-day pace, days to go, what the next standing unlocks; the rep chart below
--   Supply Writs   tiles (done today, to turn in, rep today, the reset, standing), the progress strip (bar, Merchant's
--                  Favor, the next unlock), and five tabs: Your orders (held), Cheapest rep, Favor shop, All orders,
--                  Characters
-- Also here: the crown's quick action, the Home cards (attention, characters), Settings > Reputation.

local TILE_W, TILE_H = 144, 60
local PROGRESS_H = 52
local TICK = 30

local function hex(c, t) return UI.Hex(c) .. t .. "|r" end
local function grey(t) return hex(C.muted, t) end
local short = function(c) return KM.MoneyShort(c) end

local function tierName(t) return ns.TIERS and ns.TIERS[t] and ns.TIERS[t].name or "?" end
local TIER_COLOR = { J = C.text, E = C.info, A = C.violet }
local function tierText(t) return hex(TIER_COLOR[t] or C.muted, tierName(t)) end

local function classColour(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.colorStr then return cc.colorStr:sub(3) end
    return "ffffff"
end

local function perGoldText(v)
    if v == nil then return grey("-") end
    if v == math.huge then return hex(C.good, "free") end
    return (v >= 100 and hex(C.good, KM.Commas(v)) or string.format("%.1f", v))
end

local function perRepText(v)
    if v == nil then return grey("-") end
    if v <= 0 then return hex(C.good, "free") end
    return short(v)
end

local function custText(cust)
    if not cust then return grey("unknown: learned when you turn it in") end
    local zone = cust.map and ns.ZoneName(cust.map)
    return (cust.name or "?") .. (zone and grey("  " .. zone) or "")
end

local COST_RULE = "Cost: the cheaper of buying the item (your last scan's lowest buyout) or crafting it with bought materials (Crafting Profits' recipe cost). The coin pouch the order pays back comes off before rep per gold."

---------------------------------------------------------------------------
-- An order's tooltip (rows of the held and all lists)
---------------------------------------------------------------------------

local function orderTip(tt, row)
    local o = row.order
    tt:AddLine("Craftsman's Writ: " .. o.title)
    tt:AddDoubleLine("Tier", tierName(o.tier) .. ", +" .. ns.OrderRep(o) .. " rep", 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Deliver", o.count .. "x " .. ns.ItemName(o.item) .. grey(" (" .. ns.ProfName(o.prof) .. ")"), 1, 1, 1, 1, 1, 1)
    local cost, how, buy, craft = ns.OrderCost(o)
    tt:AddDoubleLine("Buy", buy and KM.Money(buy * o.count) or grey("no price: scan at the auction house"), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Craft", craft and KM.Money(craft * o.count) or grey(KM.mods.Market and "no recipe or a material unpriced" or "Crafting Profits is off"), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Coin pouch", "~" .. KM.Money(ns.PouchAvg(o.tier)), 1, 1, 1, 1, 1, 1)
    local cust = row.cust or ns.Customer(o)
    if cust then
        tt:AddDoubleLine("Customer", (cust.name or "?") .. (cust.learned and grey(" (seen in game)") or ""), 1, 1, 1, 1, 1, 1)
        if cust.map then tt:AddDoubleLine("Where", ns.ZoneName(cust.map) .. (cust.x and string.format(" %.1f, %.1f", cust.x, cust.y) or ""), 1, 1, 1, 1, 1, 1) end
    else
        tt:AddLine("Customer not in the data yet: King Maker writes it down when you turn this order in.", 0.8, 0.8, 0.8, true)
    end
    if row.done then tt:AddLine("Done today on this character: it can be turned in again after the reset.", C.good[1], C.good[2], C.good[3], true) end
    if (row.held or row.n or 0) > 1 then tt:AddLine("You hold " .. (row.held or row.n) .. ": one a day, the rest wait in your bags (they don't expire).", 0.8, 0.8, 0.8, true) end
    tt:AddLine(COST_RULE, 0.6, 0.6, 0.6, true)
    if cust and cust.map then tt:AddLine("Click: a waypoint to the customer" .. (TomTom and " (TomTom)" or "") .. ".", 0.6, 0.6, 0.6) end
end

local function waypoint(row)
    local cust = row.cust or ns.Customer(row.order)
    local how = ns.Waypoint(cust, row.order.title)
    if how then
        KM.Print(ns, "waypoint: " .. (cust.name or "?") .. " in " .. ns.ZoneName(cust.map) .. string.format(" (%.1f, %.1f)", cust.x, cust.y) .. ".")
    elseif cust and cust.map then
        KM.Print(ns, (cust.name or "?") .. " is in " .. ns.ZoneName(cust.map) .. string.format(" at %.1f, %.1f.", cust.x or 0, cust.y or 0))
    else
        KM.Print(ns, "nobody knows where " .. row.order.title .. " goes yet: the quest's map marker shows it once you use the order.")
    end
end

---------------------------------------------------------------------------
-- The Supply Writs page
---------------------------------------------------------------------------

local P = { tables = {} }
ns.page = P

local function profLabel() local p = ns.db.ui.prof return p and ns.ProfName(p) or "All professions" end
local function tierLabel() local t = ns.db.ui.tier return t and tierName(t) or "All tiers" end

local function refreshTiles(c)
    local s = ns.Supply(c.side)
    local done, doneRep = ns.DoneToday(c)
    local held = ns.HeldNotDone(c)
    local heldRep = 0
    for _, h in ipairs(held) do heldRep = heldRep + ns.OrderRep(h.order) end
    P.tiles[1]:Set("Done today", tostring(done), done > 0 and ("+" .. KM.Commas(doneRep) .. " rep from writs") or "no writs turned in yet", done > 0 and C.good or C.text)
    P.tiles[2]:Set("To turn in", tostring(#held), #held > 0 and ("+" .. KM.Commas(heldRep) .. " rep waiting") or "none in your bags", #held > 0 and C.bad or C.text)
    P.tiles[3]:Set("Rep today", "+" .. KM.Commas(ns.RepToday(c)), s and s.name or "no supply faction", C.accent)
    local secs, guessed = ns.SecondsToReset()
    P.tiles[4]:Set("Reset in", ns.Duration(secs), guessed and "a guess: the game didn't say" or (date and date("at %H:%M", ns.Now() + secs) or ""), secs < 3600 and C.warn or C.text)
    local st = ns.CharStanding(c)
    if st then
        local pace = s and ns.Pace(c, s.faction)
        local eta = ns.ETA(st, pace)
        P.tiles[5]:Set("Standing", ns.StandingName(st.standing), st.standing < 8 and (KM.Commas(st.toNext) .. " to " .. ns.StandingName(st.standing + 1) .. (eta and (", ~" .. math.ceil(eta) .. "d") or "")) or "the top", C.accent)
    else
        P.tiles[5]:Set("Standing", "-", "not read yet", C.dim)
    end
end

local function refreshProgress(c)
    local s = ns.Supply(c.side)
    local st = ns.CharStanding(c)
    local pr = P.progress
    if not st then
        pr.line1:SetText(s and (s.name .. grey("  not met yet: use a Craftsman's Writ, or open your reputation panel once")) or grey("Supply Writs are for Alliance and Horde characters."))
        pr.bar:Set(0, C.accent)
        pr.line2:SetText("")
        return
    end
    local pace, span = ns.Pace(c, s.faction)
    local eta = ns.ETA(st, pace)
    pr.line1:SetText(hex(C.accent, ns.StandingName(st.standing)) .. "  " .. KM.Commas(st.into) .. " / " .. KM.Commas(st.size)
        .. grey(st.standing < 8 and ("   " .. KM.Commas(st.toNext) .. " to " .. ns.StandingName(st.standing + 1)) or "")
        .. grey(pace and string.format("   %s a day (%dd)", KM.Commas(pace), math.floor(span + 0.5)) or "   pace: after a second day")
        .. (eta and grey(string.format(", ~%d days to go", math.ceil(eta))) or ""))
    pr.bar:Set(st.frac, st.standing >= 8 and C.good or C.accent)
    local nextS, list = ns.NextUnlock(st.standing)
    local parts = {}
    for _, u in ipairs(list or {}) do parts[#parts + 1] = u.text .. (u.favor and grey(" (" .. KM.Commas(u.favor) .. ")") or "") end
    pr.line2:SetText("Merchant's Favor " .. hex(C.accent, c.favor and KM.Commas(c.favor) or "?")
        .. (nextS and (grey("   Next at " .. ns.StandingName(nextS) .. ": ") .. table.concat(parts, ", ")) or grey("   Everything is unlocked.")))
end

-- Held -----------------------------------------------------------------------------------------------------------
local function fillHeld(r, row, cells)
    local o = row.order
    if r.icon then r.icon:SetTexture(ns.ItemIcon(o.item)) end
    cells.order:SetText(row.done and hex(C.dim, o.title) or o.title)
    cells.tier:SetText(tierText(o.tier))
    cells.deliver:SetText((o.count > 1 and (o.count .. "x ") or "") .. ns.ItemName(o.item) .. (row.n > 1 and grey("  (" .. row.n .. " held)") or ""))
    cells.cost:SetText(row.cost and (short(row.cost) .. grey(row.how == "craft" and " c" or "")) or grey("-"))
    cells.rep:SetText(row.done and hex(C.good, "done") or ("+" .. row.rep))
    cells.pergold:SetText(row.done and grey("-") or perGoldText(row.perGold))
    cells.cust:SetText(custText(row.cust))
    r.tip = function(tt) orderTip(tt, row) end
end

-- Cheapest ---------------------------------------------------------------------------------------------------------
local function fillCheap(r, row, cells)
    if r.icon then r.icon:SetTexture(ns.ItemIcon(row.sealed)) end
    cells.way:SetText(row.label)
    cells.rep:SetText("+" .. row.rep)
    if row.key == "receipt" then
        cells.buy:SetText(row.crate and short(row.crate) or grey("no price"))
        cells.item:SetText(hex(C.accent, row.favor .. " Favor"))
        cells.note:SetText(grey("no daily limit; needs Friendly"))
    else
        cells.buy:SetText(row.writ and short(row.writ) or grey("no price"))
        cells.item:SetText(row.item and short(row.item) or grey("-"))
        cells.note:SetText(grey(row.priced .. " of " .. row.of .. " orders priced"))
    end
    cells.pouch:SetText(short(row.pouch))
    cells.per:SetText(perRepText(row.perRep))
    r.tip = function(tt)
        tt:AddLine(row.label)
        if row.key == "receipt" then
            tt:AddLine("A Forged Delivery Receipt (15 Merchant's Favor, at Friendly) and an empty Waylaid Crate make a Notarized Shipping Container: 50 rep and 1s, as many as you like.", 1, 1, 1, true)
            tt:AddDoubleLine("Waylaid Crate", row.crate and KM.Money(row.crate) or "no price yet", 1, 1, 1, 1, 1, 1)
            tt:AddLine("Gold per rep counts the crate only: the Favor is yours to spend on recipes instead (Favor shopping).", 0.8, 0.8, 0.8, true)
        else
            tt:AddLine("Buy a sealed " .. row.label:lower() .. " on the auction house, use it for a random " .. row.label:gsub(" writ", ""):lower() .. " order, deliver the item: +" .. row.rep .. " rep and a coin pouch.", 1, 1, 1, true)
            tt:AddDoubleLine("Sealed writ", row.writ and KM.Money(row.writ) or "no price yet", 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Average item", row.item and KM.Money(row.item) or "-", 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Coin pouch", "-~" .. KM.Money(row.pouch), 1, 1, 1, 1, 1, 1)
            tt:AddLine("(writ + average item - pouch) / rep. Each order of the tier is as likely; the average is over the " .. row.priced .. " of " .. row.of .. " with a price.", 0.8, 0.8, 0.8, true)
        end
    end
end

-- Favor --------------------------------------------------------------------------------------------------------------
local function fillFavor(r, row, cells, c)
    if r.icon then r.icon:SetTexture(ns.ItemIcon(row.item or row.recipeItem)) end
    cells.recipe:SetText(row.name)
    cells.prof:SetText(ns.ProfName(row.prof) .. grey(" " .. row.skill))
    local can = (c.favor or 0) >= row.favor
    cells.favor:SetText(can and hex(C.accent, row.favor) or tostring(row.favor))
    local st = ns.CharStanding(c)
    local ok = st and st.standing >= row.standing
    cells.standing:SetText(ok and ns.StandingName(row.standing) or hex(C.warn, ns.StandingName(row.standing)))
    cells.profit:SetText(row.profit and (row.profit > 0 and hex(C.good, short(row.profit)) or short(row.profit)) or grey(row.item and "-" or "enchant"))
    cells.per:SetText(row.perFavor and short(row.perFavor) or grey("-"))
    cells.have:SetText(row.has and hex(C.good, "known") or (row.mine and grey("yours") or grey("")))
    r.tip = function(tt)
        tt:AddLine(row.name)
        tt:AddDoubleLine("Recipe", ns.ItemName(row.recipeItem), 1, 1, 1, 1, 1, 1)
        tt:AddDoubleLine("Costs", row.favor .. " Merchant's Favor" .. (can and "" or hex(C.warn, " (you have " .. (c.favor or 0) .. ")")), 1, 1, 1, 1, 1, 1)
        tt:AddDoubleLine("Needs", ns.ProfName(row.prof) .. " " .. row.skill .. ", " .. ns.StandingName(row.standing), 1, 1, 1, 1, 1, 1)
        if row.profit then tt:AddDoubleLine("Profit each", KM.Money(row.profit), 1, 1, 1, 1, 1, 1)
        elseif row.missing then tt:AddDoubleLine("Profit each", "no price for " .. ns.ItemName(row.missing), 1, 1, 1, 1, 1, 1) end
        tt:AddLine("Profit as Crafting Profits counts it (its Buy mats / Use my mats switch), after the 5% cut. The standing each recipe needs comes from its Favor cost (the guides: 30-45 Neutral, 60-120 Friendly, 180+ Honored).", 0.6, 0.6, 0.6, true)
    end
end

-- All orders ------------------------------------------------------------------------------------------------------
local function fillAll(r, row, cells)
    ns.CostRow(row)
    local o = row.order
    if r.icon then r.icon:SetTexture(ns.ItemIcon(o.item)) end
    cells.order:SetText(row.done and hex(C.dim, o.title) or o.title)
    cells.tier:SetText(tierText(o.tier))
    cells.prof:SetText(ns.ProfName(o.prof))
    cells.deliver:SetText((o.count > 1 and (o.count .. "x ") or "") .. ns.ItemName(o.item))
    cells.rep:SetText("+" .. row.rep)
    cells.cost:SetText(row.cost and (short(row.cost) .. grey(row.how == "craft" and " c" or "")) or grey("-"))
    local st = row.done and hex(C.good, "done today") or (row.held > 0 and hex(C.bad, "held" .. (row.held > 1 and (" x" .. row.held) or "")) or "")
    cells.status:SetText(st .. (st ~= "" and "  " or "") .. grey(row.cust and row.cust.name or ""))
    r.tip = function(tt) orderTip(tt, row) end
end

-- Characters --------------------------------------------------------------------------------------------------------
local function fillChar(r, row, cells)
    local c = row.c
    cells.char:SetText("|cff" .. classColour(c.class) .. ns.CharName(c, row.key) .. "|r" .. (row.me and grey(" (you)") or ""))
    local st = row.standing
    cells.standing:SetText(st and ns.StandingName(st.standing) or grey("-"))
    cells.progress:SetText(st and (KM.Commas(st.into) .. grey(" / " .. KM.Commas(st.size))) or grey("-"))
    cells.done:SetText(row.stale and grey("0 (new day)") or tostring(row.done))
    cells.today:SetText(row.stale and grey("-") or ("+" .. KM.Commas(row.today)))
    cells.held:SetText(row.held > 0 and hex(C.bad, row.held) or grey("0"))
    cells.favor:SetText(row.favor and KM.Commas(row.favor) or grey("-"))
    cells.seen:SetText(row.me and grey("now") or grey(KM.Ago(c.seen)))
    r:SetAlpha(row.old and 0.5 or 1)
    r.tip = function(tt)
        tt:AddLine(ns.CharName(c, row.key) .. (c.side and grey("  " .. c.side) or ""))
        local s = ns.Supply(c.side)
        if s then tt:AddDoubleLine("Faction", s.name, 1, 1, 1, 1, 1, 1) end
        if st then tt:AddDoubleLine("Standing", ns.StandingName(st.standing) .. " " .. KM.Commas(st.into) .. "/" .. KM.Commas(st.size), 1, 1, 1, 1, 1, 1) end
        tt:AddDoubleLine("Writs today", row.stale and "none yet (the reset passed since you were on)" or (row.done .. ", +" .. KM.Commas(row.doneRep) .. " rep"), 1, 1, 1, 1, 1, 1)
        local list = ns.HeldNotDone(c)
        for i, h in ipairs(list) do
            if i > 6 then tt:AddLine("and " .. (#list - 6) .. " more", 0.6, 0.6, 0.6) break end
            tt:AddDoubleLine("  " .. h.order.title, "+" .. ns.OrderRep(h.order), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        tt:AddLine("Writs are per character: each one can turn in every order once a day. From the last time you were on it.", 0.6, 0.6, 0.6, true)
    end
end

local function selectTab(id)
    for k, t in pairs(P.tables) do t:SetShown(k == id) end
    local all, fav = id == "all", id == "favor"
    P.tierBtn:SetShown(all); P.profBtn:SetShown(all); P.showBtn:SetShown(all)
    P.mineChk.frame:SetShown(fav)
    P.note:SetShown(id == "cheap" or id == "held")
end

local function refreshWrits()
    if not P.tiles or not ns.db then return end
    local c = ns.Me()
    ns.CheckDay(c)
    local u = ns.db.ui
    refreshTiles(c)
    refreshProgress(c)
    P.tabs:Select(u.tab)
    selectTab(u.tab)
    P.tierBtn:Refresh(); P.profBtn:Refresh(); P.showBtn:Refresh()
    P.mineChk:SetChecked(u.mine)
    local t = P.tables[u.tab]
    if u.tab == "held" then
        local rows = ns.HeldRows()
        t.emptyText = "No writ orders in your bags or bank. Sealed writs drop from mobs and chests, or buy one: see Cheapest rep."
        t:SetRows(rows, fillHeld)
        P.note:SetText(#rows > 0 and grey("Click an order for a waypoint to its customer. Done ones come back after the reset.") or "")
    elseif u.tab == "cheap" then
        t.emptyText = "Scan at the auction house for sealed writ prices."
        t:SetRows(ns.CheapestRep(), fillCheap)
        local receipt, best = ns.ReceiptVsWrits()
        if receipt and receipt.perRep and best then
            local diff = receipt.perRep < best.perRep and "cheaper" or "dearer"
            P.note:SetText("Receipt path: " .. perRepText(receipt.perRep) .. " a rep point plus 15 Favor, " .. diff .. " than a " .. best.label:lower() .. " (" .. perRepText(best.perRep) .. ").")
        else
            P.note:SetText(grey("Receipt path: scan a Waylaid Crate and the sealed writs to compare."))
        end
    elseif u.tab == "favor" then
        t.emptyText = "No faction recipes match."
        t:SetRows(ns.FavorRows(nil, u.mine), function(r, row, cells) fillFavor(r, row, cells, c) end)
    elseif u.tab == "all" then
        t.emptyText = "No order matches the filters."
        t:SetRows(ns.AllRows({ tier = u.tier, prof = u.prof, held = u.held, notDone = u.notDone }), fillAll)
    else
        t.emptyText = "No character has met the supply faction yet."
        t:SetRows(ns.CharRows(), fillChar)
    end
    if not P.ticker and C_Timer and C_Timer.NewTicker then
        P.ticker = C_Timer.NewTicker(TICK, function(self)
            if not KM.IsShown("writs") then self:Cancel(); P.ticker = nil return end
            ns.Tick()
            KM.Refresh("writs")
        end)
    end
end

local function hideWrits() if P.ticker then P.ticker:Cancel(); P.ticker = nil end end

local function col(key, label, w, justify, tip) return { key = key, label = label, w = w, justify = justify, tip = tip } end

local function makeTable(c, id, cols, onClick)
    local t = UI.Table(c, cols, 22, { icon = true, noSort = true, fontSize = 11, onClick = onClick })
    t:SetPoint("TOPLEFT", 0, -(TILE_H + 10 + PROGRESS_H + 10 + 34))
    t:SetPoint("BOTTOMRIGHT", 0, 18)
    t:Hide()
    P.tables[id] = t
    return t
end

local function buildWrits(c)
    P.tiles = {}
    for i = 1, 5 do
        local t = UI.Tile(c, TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), 0)
        P.tiles[i] = t
    end
    P.tiles[1]:SetTip("Writ orders this character turned in since the last daily reset. Each named order is its own daily quest: any number of different ones a day, each once.")
    P.tiles[2]:SetTip(function(tt)
        tt:AddLine("Orders in your bags or bank you haven't turned in today. The red count on the sidebar is this number.", 1, 1, 1, true)
        for i, h in ipairs(ns.HeldNotDone()) do
            if i > 8 then tt:AddLine("...", 0.6, 0.6, 0.6) break end
            tt:AddDoubleLine(h.order.title, tierName(h.order.tier) .. ", +" .. ns.OrderRep(h.order), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end)
    P.tiles[3]:SetTip("Rep with your supply faction since the reset: how far the bar moved since King Maker first read it today (receipts and the Diplomat perk included), or your writs' rep when that's more.")
    P.tiles[4]:SetTip("Time to the daily reset, from the game. Then every order can be turned in again.")
    P.tiles[5]:SetTip("Your standing with the supply faction, rep to the next one, and the days to get there at your pace over the last 7 days (from one reading a day).")

    local pr = UI.Panel(c, C.panel)
    pr:SetPoint("TOPLEFT", 0, -(TILE_H + 10))
    pr:SetPoint("TOPRIGHT", 0, -(TILE_H + 10))
    pr:SetHeight(PROGRESS_H)
    pr.line1 = UI.Text(pr, 11, C.text)
    pr.line1:SetPoint("TOPLEFT", 10, -7)
    pr.line1:SetPoint("RIGHT", -10, 0)
    pr.bar = UI.Bar(pr, 5)
    pr.bar:SetPoint("TOPLEFT", 10, -23)
    pr.bar:SetPoint("TOPRIGHT", -10, -23)
    pr.line2 = UI.Text(pr, 10, C.muted)
    pr.line2:SetPoint("TOPLEFT", 10, -34)
    pr.line2:SetPoint("RIGHT", -10, 0)
    UI.Tip(pr, function(tt)
        tt:AddLine("Progress")
        tt:AddLine("Standing, the bar to the next one, your rep a day (7-day pace) and the days to go. Merchant's Favor is per character: orders never give it; filled crates and the Shipping Label do.", 1, 1, 1, true)
        tt:AddLine("Neutral is 3,000 rep, Friendly 6,000, Honored 12,000, Revered 21,000: 42,000 from Neutral to Exalted. All 150 orders once: 19,875 rep.", 0.8, 0.8, 0.8, true)
        local st = ns.CharStanding(ns.Me())
        for s = math.max(4, st and (st.standing + 1) or 4), 8 do
            tt:AddLine(ns.StandingName(s), C.accent[1], C.accent[2], C.accent[3])
            for _, u in ipairs(ns.Unlocks(s)) do
                tt:AddDoubleLine("  " .. u.text .. (u.note and (" (" .. u.note .. ")") or ""), u.favor and (KM.Commas(u.favor) .. " Favor") or "", 0.8, 0.8, 0.8, 1, 1, 1)
            end
        end
        tt:AddLine("Certifications: 1,000 Favor each at 300 skill.", 0.6, 0.6, 0.6)
    end)
    P.progress = pr

    local y = -(TILE_H + 10 + PROGRESS_H + 10)
    P.tabs = UI.Tabs(c, { { id = "held", label = "Your orders" }, { id = "cheap", label = "Cheapest rep" },
        { id = "favor", label = "Favor shop" }, { id = "all", label = "All orders" }, { id = "chars", label = "Characters" } }, function(id)
        ns.db.ui.tab = id
        KM.Refresh("writs")
    end)
    P.tabs:SetPoint("TOPLEFT", 0, y)
    P.tierBtn = UI.MenuButton(c, 80, tierLabel, function(_, root)
        root:CreateRadio("All tiers", function() return ns.db.ui.tier == nil end, function() ns.db.ui.tier = nil; KM.Refresh("writs") end)
        for _, tk in ipairs(ns.TIER_ORDER) do
            root:CreateRadio(tierName(tk), function() return ns.db.ui.tier == tk end, function() ns.db.ui.tier = tk; KM.Refresh("writs") end)
        end
    end)
    
    UI.Tip(P.tierBtn, "Show one tier: Journeyman (75 rep), Expert (125) or Artisan (200).")
    P.profBtn = UI.MenuButton(c, 100, profLabel, function(_, root)
        root:CreateRadio("All professions", function() return ns.db.ui.prof == nil end, function() ns.db.ui.prof = nil; KM.Refresh("writs") end)
        for _, p in ipairs({ 4, 2, 9, 3, 8 }) do
            root:CreateRadio(ns.ProfName(p), function() return ns.db.ui.prof == p end, function() ns.db.ui.prof = p; KM.Refresh("writs") end)
        end
    end)
    
    UI.Tip(P.profBtn, "Show orders whose item one profession makes. You don't need the profession: buy the item if you can't craft it.")
    local SHOW = { { "Every order", false, false }, { "Held", true, false }, { "Not done today", false, true }, { "Held, not done", true, true } }
    P.showBtn = UI.MenuButton(c, 110, function()
        local u = ns.db.ui
        for _, o in ipairs(SHOW) do if o[2] == u.held and o[3] == u.notDone then return o[1] end end
        return SHOW[1][1]
    end, function(_, root)
        for _, o in ipairs(SHOW) do
            root:CreateRadio(o[1], function() return ns.db.ui.held == o[2] and ns.db.ui.notDone == o[3] end,
                function() ns.db.ui.held, ns.db.ui.notDone = o[2], o[3]; KM.Refresh("writs") end)
        end
    end)
    P.showBtn:SetPoint("TOPRIGHT", 0, y)
    UI.Tip(P.showBtn, "Held: only orders in your bags or bank. Not done today: hide the ones this character already turned in.")
    P.profBtn:SetPoint("RIGHT", P.showBtn, "LEFT", -6, 0)
    P.tierBtn:SetPoint("RIGHT", P.profBtn, "LEFT", -6, 0)
    P.mineChk = UI.CheckLabel(c, "My professions", function(v) ns.db.ui.mine = v; KM.Refresh("writs") end, "Only recipes for professions this character has (from Crafting Profits).")
    P.mineChk.frame:SetPoint("TOPRIGHT", -4, y - 3)
    P.note = UI.Text(c, 10, C.muted)
    P.note:SetPoint("BOTTOMLEFT", 2, 2)
    P.note:SetPoint("RIGHT", -20, 0)

    makeTable(c, "held", {
        col("order", "Order", 150, nil, "The order (Craftsman's Writ: ...). Grey: done today on this character."),
        col("tier", "Tier", 72, nil, "Journeyman 75 rep, Expert 125, Artisan 200."),
        col("deliver", "Deliver", 150, nil, "What the customer wants, and how many."),
        col("cost", "Cost", 70, "RIGHT", COST_RULE .. " A small c: crafting is cheaper."),
        col("rep", "Rep", 44, "RIGHT", "Rep it gives (with the Diplomat perk from Settings)."),
        col("pergold", "Rep/g", 56, "RIGHT", "Rep per gold: rep / (cost - the coin pouch). free: the pouch pays for the item. Best first."),
        col("cust", "Customer", 0, nil, "Who takes it and in which zone. Click the line for a waypoint."),
    }, function(row) waypoint(row) end)
    makeTable(c, "cheap", {
        col("way", "Way", 150, nil, "Ways to buy rep today, cheapest gold per rep point first."),
        col("rep", "Rep", 50, "RIGHT", "Rep each time."),
        col("buy", "Writ / crate", 84, "RIGHT", "The sealed writ's (or the Waylaid Crate's) lowest buyout from your last scan."),
        col("item", "Avg item", 84, "RIGHT", "What the tier's orders want, on average (each as likely), the cheaper of buying and crafting. The receipt path costs 15 Merchant's Favor instead."),
        col("pouch", "Pouch", 64, "RIGHT", "The coin pouch (or the 1s from a container) you get back."),
        col("per", "Gold / rep", 84, "RIGHT", "(writ + average item - pouch) / rep: what one rep point costs. Lower is better."),
        col("note", "", 0, nil),
    })
    makeTable(c, "favor", {
        col("recipe", "Recipe", 190, nil, "The supply faction's recipes, bought with Merchant's Favor. Same list on both sides."),
        col("prof", "Profession", 110, nil, "The profession and the skill it needs."),
        col("favor", "Favor", 50, "RIGHT", "Merchant's Favor it costs. Gold: you have enough."),
        col("standing", "Standing", 76, nil, "The standing it needs (from its cost; orange: not there yet)."),
        col("profit", "Profit", 80, "RIGHT", "Profit per craft as Crafting Profits counts it, after the 5% cut. Best first."),
        col("per", "Per Favor", 70, "RIGHT", "Profit per craft for each Favor point it costs: where Favor goes furthest."),
        col("have", "", 0, nil, "known: you have it (Crafting Profits). yours: your profession."),
    })
    makeTable(c, "all", {
        col("order", "Order", 160, nil, "All 150 orders. Grey: done today."),
        col("tier", "Tier", 72, nil, "Journeyman 75 rep, Expert 125, Artisan 200."),
        col("prof", "Profession", 96, nil, "The profession that makes the item."),
        col("deliver", "Deliver", 150, nil, "What the customer wants."),
        col("rep", "Rep", 44, "RIGHT", "Rep it gives."),
        col("cost", "Cost", 70, "RIGHT", COST_RULE),
        col("status", "Status", 0, nil, "done today / held (red: you can turn it in today) and the customer."),
    }, function(row) waypoint(row) end)
    makeTable(c, "chars", {
        col("char", "Character", 150, nil, "Every character that has met the supply faction or held an order."),
        col("standing", "Standing", 80, nil, "With its own side's supply faction."),
        col("progress", "Progress", 110, "RIGHT", "Rep into the standing / its size."),
        col("done", "Today", 76, "RIGHT", "Writs turned in since the reset. 0 (new day): the reset passed since you were on it."),
        col("today", "Rep today", 70, "RIGHT", "Rep with the supply faction since the reset."),
        col("held", "Hold", 50, "RIGHT", "Orders it holds that it can still turn in today."),
        col("favor", "Favor", 60, "RIGHT", "Merchant's Favor, from the last time you were on it."),
        col("seen", "Seen", 0, "RIGHT", "When you were last on it."),
    })
end

---------------------------------------------------------------------------
-- The Reputation overview page
---------------------------------------------------------------------------

local O = {}
ns.overview = O

local function factionRows()
    local c = ns.Me()
    local out = {}
    for _, f in ipairs(ns.Tracked(c.side)) do
        local e = c.rep[f.factionID]
        local st = e and ns.Standing(e.v)
        local pace, span = ns.Pace(c, f.factionID)
        local nextS, list = nil, nil
        if f.def.unlocks then
            for s = math.max(4, (st and st.standing or 4) + 1), 8 do
                local l = ns.Call(f.def.unlocks, s)
                if type(l) == "table" and #l > 0 then nextS, list = s, l break end
            end
        end
        out[#out + 1] = { f = f, name = (e and e.name) or f.name, st = st, pace = pace, span = span, eta = ns.ETA(st, pace),
            nextS = nextS, unlocks = list or {}, page = f.def.page }
    end
    return out
end

local function fillFaction(r, row, cells)
    cells.name:SetText(row.name)
    local st = row.st
    if not r.repBar then
        local cl = O.table.cols[3]
        r.repBar = UI.Bar(r, 6)
        r.repBar:SetPoint("LEFT", cl.x, 0)
        r.repBar:SetWidth(70)
        cells.progress:ClearAllPoints()
        cells.progress:SetPoint("LEFT", cl.x + 76, 0)
        cells.progress:SetWidth(cl.w - 80)
    end
    r.repBar:Set(st and st.frac or 0, st and st.standing >= 8 and C.good or C.accent)
    cells.standing:SetText(st and ns.StandingName(st.standing) or grey("not met"))
    cells.progress:SetText(st and (KM.Commas(st.into) .. grey("/" .. KM.Commas(st.size))) or grey("-"))
    cells.tonext:SetText(st and st.standing < 8 and KM.Commas(st.toNext) or grey("-"))
    cells.pace:SetText(row.pace and KM.Commas(row.pace) or grey("-"))
    cells.eta:SetText(row.eta and (math.ceil(row.eta) .. "d") or grey("-"))
    local parts = {}
    for _, u in ipairs(row.unlocks) do parts[#parts + 1] = u.text end
    cells.unlock:SetText(row.nextS and (hex(C.accent, ns.StandingName(row.nextS)) .. "  " .. table.concat(parts, ", ")) or grey("-"))
    r.tip = function(tt)
        tt:AddLine(row.name)
        if st then
            tt:AddDoubleLine("Standing", ns.StandingName(st.standing) .. " " .. KM.Commas(st.into) .. "/" .. KM.Commas(st.size), 1, 1, 1, 1, 1, 1)
            if st.standing < 8 then tt:AddDoubleLine("To Exalted", KM.Commas(st.toExalted), 1, 1, 1, 1, 1, 1) end
        else
            tt:AddLine("Not met on this character yet.", 0.8, 0.8, 0.8)
        end
        tt:AddDoubleLine("Pace", row.pace and (KM.Commas(row.pace) .. " a day over " .. math.floor(row.span + 0.5) .. "d") or "needs readings on two days", 1, 1, 1, 1, 1, 1)
        for _, u in ipairs(row.unlocks) do tt:AddDoubleLine("  " .. u.text, u.favor and (KM.Commas(u.favor) .. " Favor") or "", 0.8, 0.8, 0.8, 1, 1, 1) end
        if row.page then tt:AddLine("Click: open its page.", 0.6, 0.6, 0.6) end
    end
end

local function drawChart()
    local g = O.chart
    if not g then return end
    local c = ns.Me()
    local s = ns.Supply(c.side)
    local pts = {}
    for _, p in ipairs(s and c.snaps[s.faction] or {}) do pts[#pts + 1] = { p.t, p.v } end
    local tmax = pts[#pts] and pts[#pts][1] or ns.Now()
    local tmin = pts[1] and pts[1][1] or (tmax - 86400)
    if tmax <= tmin then tmin = tmax - 86400 end
    KM.Safe(g.Draw, g, { tmin = tmin, tmax = tmax, emptyText = "One reading a day: the line grows as you play",
        series = { { pts = pts, color = C.accent, style = "line" } }, format = function(v) return KM.Commas(v) end,
        hover = function(_, p) if p then GameTooltip:AddLine(KM.Commas(p[2]) .. " rep from Neutral", 1, 1, 1) end end })
end

local function refreshOverview()
    if not O.table or not ns.db then return end
    local c = ns.Me()
    O.table.emptyText = ns.Side() and "No faction tracked for this character yet." or "Reputation tracks the supply factions of the Alliance and the Horde."
    O.table:SetRows(factionRows(), fillFaction)
    local s = ns.Supply(c.side)
    O.chartHead:SetText(s and (s.name:upper() .. ": REP FROM NEUTRAL") or "REP")
    drawChart()
end

local function buildOverview(c)
    O.table = UI.Table(c, {
        col("name", "Faction", 190, nil, "Every faction King Maker tracks for your side. More plug in later."),
        col("standing", "Standing", 76, nil, "Your standing on this character."),
        col("progress", "Progress", 150, nil, "The bar to the next standing, rep into it / its size."),
        col("tonext", "To next", 62, "RIGHT", "Rep to the next standing."),
        col("pace", "Per day", 60, "RIGHT", "Rep a day over the last 7 days (one reading a day)."),
        col("eta", "Days", 44, "RIGHT", "Days to the next standing at that pace."),
        col("unlock", "Next unlock", 0, nil, "What the next standing up brings."),
    }, 24, { noSort = true, fontSize = 11, onClick = function(row) if row.page then KM.Show(row.page) end end })
    O.table:SetPoint("TOPLEFT", 0, 0)
    O.table:SetPoint("TOPRIGHT", 0, 0)
    O.table:SetHeight(20 + 24 * 6)
    local box = UI.Panel(c, C.panel)
    box:SetPoint("TOPLEFT", 0, -(20 + 24 * 6 + 12))
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    O.chartHead = UI.Heading(box, "")
    O.chartHead:SetPoint("TOPLEFT", 10, -9)
    UI.Tip(box, "Your rep with the supply faction from Neutral, one point a day (the last reading of each day, on this character).")
    O.chart = UI.Chart(box, 740, 300)
    O.chart.frame:SetPoint("TOPLEFT", 4, -26)
    box:SetScript("OnSizeChanged", function(_, w, h) if w and h and w > 40 and h > 60 then O.chart:SetSize(w - 12, h - 34) end end)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function icon(path, fallback)
    if GetFileIDFromPath and not GetFileIDFromPath(path) then return fallback end
    return path
end

KM.RegisterGroup({ id = "rep", label = "Reputation", order = 45 })

KM.RegisterPage({
    id = "reputation", group = "rep", label = "Reputation", order = 10, icon = icon("Interface\\Icons\\INV_Scroll_08", "Interface\\Icons\\INV_Misc_Book_11"),
    title = "Reputation",
    subtitle = "The factions that pay in recipes, Favor and gold: where you stand, your pace, what's next.",
    build = buildOverview, refresh = refreshOverview,
})

KM.RegisterPage({
    id = "writs", group = "rep", label = "Supply Writs", order = 20, icon = icon("Interface\\Icons\\INV_Scroll_05", "Interface\\Icons\\INV_Letter_05"),
    title = "Supply Writs",
    subtitle = function()
        local s = ns.db and ns.Supply(ns.Me().side)
        return s and (s.name .. ", " .. s.camp .. ". One of each order a day, per character.") or "The supply factions' daily orders (Alliance and Horde)."
    end,
    badge = function() return ns.Badge() end,
    crownBadge = false,
    build = buildWrits, refresh = refreshWrits, hide = hideWrits,
})

KM.RegisterQuickAction({ id = "writs", label = "Supply Writs", order = 24, func = function() ns.Toggle(true, "writs") end })

KM.RegisterHomeCard({ kind = "attention", id = "writs", order = 20, get = function()
    if not ns.db then return nil end
    local list = ns.HeldNotDone()
    if #list == 0 then return nil end
    local rep, names = 0, {}
    for _, h in ipairs(list) do rep = rep + ns.OrderRep(h.order); names[#names + 1] = h.order.title end
    return { { text = #list .. " writ order" .. (#list == 1 and "" or "s") .. " to turn in", color = C.bad, count = #list, page = "writs",
        value = "+" .. KM.Commas(rep) .. " rep", tab = function() ns.db.ui.tab = "held" end,
        tip = "In your bags and not turned in today: " .. table.concat(names, ", ") .. ". They reset with the daily reset." } }
end })

KM.RegisterHomeCard({ kind = "chars", id = "writs", order = 40, get = function()
    if not ns.db then return nil end
    local out = {}
    for _, row in ipairs(ns.CharRows()) do
        if row.done > 0 and not row.stale then
            out[row.key] = { text = row.done .. " writ" .. (row.done == 1 and "" or "s"), color = C.good,
                tip = row.done .. " Supply Writ order" .. (row.done == 1 and "" or "s") .. " today, +" .. KM.Commas(row.today) .. " rep." }
        end
    end
    return out
end })

local function set(k) return function(v) ns.db.settings[k] = v; ns.Changed() end end
local function get(k) return function() return ns.db.settings[k] end end

KM.RegisterSettings({ id = "reputation", label = "Reputation", order = 24, rows = {
    { type = "header", label = "Supply Writs" },
    { type = "check", label = "Red count on the sidebar", get = get("badge"), set = set("badge"),
      tip = "The number by Supply Writs: orders in your bags or bank you can still turn in today." },
    { type = "check", label = "At login, say which orders you can turn in", get = get("remind"), set = set("remind"),
      tip = "One chat line when you log in holding orders not turned in today." },
    { type = "range", label = "Diplomat perk", min = 0, max = 5, step = 1, get = get("diplomat"), set = set("diplomat"),
      fmt = function(v) return v == 0 and "none" or ("rank " .. v .. " (+" .. (v * 2) .. "%)") end,
      tip = "The Legacy perk Diplomat adds 2% rep a rank. Set yours so expected rep and gold per rep match what you get." },
    { type = "header", label = "Characters" },
    { type = "button", label = "Forget characters not seen in 90 days", tip = "Deletes the writ and standing data of every character (not this one) you haven't logged in on for 90 days.", func = function()
        local now, me, n = ns.Now(), KM.Char(), 0
        for key, c in pairs(ns.db.chars) do
            if key ~= me and (c.seen or 0) < now - 90 * 86400 then ns.db.chars[key] = nil; n = n + 1 end
        end
        ns.Changed()
        KM.Print(ns, n > 0 and ("forgot " .. n .. " character" .. (n == 1 and "" or "s") .. ".") or "every character was seen in the last 90 days.")
    end },
    { type = "text", label = "Writs, standings and Favor are read from the game on each character: log in on one once and it shows on the Characters tab." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/rep   open Supply Writs\n/rep overview   every tracked faction\n/rep status   standing and orders in chat\n/rep remind on|off   the login reminder\n/rep badge on|off   the sidebar count\n/rep forget Name   forget a character\n/rep debug   what the game reports" },
} })
