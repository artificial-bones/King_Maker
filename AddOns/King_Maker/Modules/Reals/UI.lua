local _, KM = ...
local ns = KM.Module("Reals")
local UI = KM.UI
local C = UI.C

-- The Reals page (Farming > Reals): tiles (looted today, still to loot, held, the reset), a character picker and the
-- pop-up switch, the dungeons on the left (green: a Real still waiting today, red: all looted) and the clicked
-- dungeon's bosses on the right. Also: the toast, the crown's quick action, a Home card, Settings > Reals.

local TILE_W, TILE_H = 150, 60
local LIST_W = 330
local TICK = 30

local function hex(c, t) return UI.Hex(c) .. t .. "|r" end
local function grey(t) return hex(C.muted, t) end

local function classColour(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.colorStr then return cc.colorStr:sub(3) end
    return "ffffff"
end

local P = {}
ns.page = P

local function charLabel()
    local c, key = ns.Shown()
    return ns.CharName(c, key) .. (key == KM.Char() and " (you)" or "")
end

local function selected(states)
    local name = ns.db.ui.dungeon
    for _, st in ipairs(states) do if st.d.name == name then return st end end
    for _, st in ipairs(states) do if st.left > 0 then return st end end
    return states[1]
end

local function fillDungeon(r, st, cells)
    local col = st.left > 0 and C.good or C.bad
    cells.name:SetText(hex(col, st.d.name))
    cells.count:SetText(st.done .. grey(" / " .. st.total))
    cells.state:SetText(st.left > 0 and hex(C.good, st.left .. " to loot") or hex(C.bad, "all looted"))
    r.tip = function(tt)
        tt:AddLine(st.d.name .. (st.d.level ~= "" and grey("  level " .. st.d.level) or ""))
        tt:AddDoubleLine("Looted today", st.done .. " of " .. st.total, 1, 1, 1, 1, 1, 1)
        for _, e in ipairs(st.bosses) do
            local c = e.got and C.bad or ((e.noDrop or e.b.optional) and C.dim or C.good)
            tt:AddDoubleLine("  " .. e.b.name, e.got and "looted" or (e.noDrop and "no Real seen" or (e.b.optional and "optional" or "waiting")), c[1], c[2], c[3], c[1], c[2], c[3])
        end
        tt:AddLine("Click: its bosses on the right.", 0.6, 0.6, 0.6)
    end
end

local function fillBoss(r, e, cells)
    local b = e.b
    local col = e.got and C.bad or ((e.noDrop or b.optional) and C.dim or C.good)
    cells.name:SetText(hex(col, b.name) .. (b.learned and grey("  (learned)") or ""))
    cells.level:SetText(b.level and grey(b.level) or "")
    if e.got then
        cells.state:SetText(hex(C.bad, "looted") .. grey(date and ("  " .. date("%H:%M", e.got)) or ""))
    elseif e.noDrop then
        cells.state:SetText(grey("no Real seen in " .. ns.MISS_LIMIT .. " kills"))
    elseif b.optional then
        cells.state:SetText(grey("optional (summoned or an event)"))
    else
        cells.state:SetText(hex(C.good, "Real waiting"))
    end
    r.tip = function(tt)
        tt:AddLine(b.name)
        tt:AddDoubleLine("Dungeon", b.dungeon.name, 1, 1, 1, 1, 1, 1)
        local drops = ns.db.drops[b.npc] or 0
        tt:AddDoubleLine("Reals seen on it", drops > 0 and tostring(drops) or "not yet", 1, 1, 1, 1, 1, 1)
        if e.got then tt:AddLine("Looted today: it gives this character another after the daily reset.", C.bad[1], C.bad[2], C.bad[3], true)
        elseif e.noDrop then tt:AddLine("Looted " .. ns.MISS_LIMIT .. " times with no Real, so it isn't counted. It comes back the first time one drops.", 0.8, 0.8, 0.8, true)
        elseif b.optional then tt:AddLine("A summoned or event boss: counted once you loot a Real from it.", 0.8, 0.8, 0.8, true)
        else tt:AddLine("Its Real for today is still waiting for this character.", C.good[1], C.good[2], C.good[3], true) end
        if b.learned then tt:AddLine("Not in the boss list: King Maker learned it when a Real came from it.", 0.6, 0.6, 0.6, true) end
    end
end

local function refresh()
    if not P.tiles or not ns.db then return end
    ns.Snapshot()
    local c, key = ns.Shown()
    ns.CheckDay(ns.Me())
    local got, left, dl = ns.Totals(c)
    local states = ns.States(c)
    P.tiles[1]:Set("Looted today", tostring(got), got > 0 and "one per boss a day" or "none yet today", got > 0 and C.good or C.text)
    P.tiles[2]:Set("Still to loot", tostring(left), left > 0 and ("in " .. dl .. " dungeon" .. (dl == 1 and "" or "s")) or "every boss looted", left > 0 and C.good or C.bad)
    P.tiles[3]:Set("Holding", c.held and (tostring(c.held) .. (c.cap and grey(" / " .. c.cap) or "")) or "-",
        c.held and (c.cap and (c.held >= c.cap and "at the cap: spend some" or (c.cap - c.held) .. " to the cap") or "Tarnished Undermine Reals") or "log in on it once",
        (c.held and c.cap and c.held >= c.cap) and C.bad or C.accent)
    local secs, guessed = ns.SecondsToReset()
    P.tiles[4]:Set("Reset in", ns.Duration(secs), guessed and "a guess: the game didn't say" or (date and date("at %H:%M", ns.Now() + secs) or ""), secs < 3600 and C.warn or C.text)
    P.charBtn:Refresh()
    P.notify:SetChecked(ns.db.settings.notify)
    P.dungeons.emptyText = "No dungeons in the list."
    local st = selected(states)
    P.dungeons.selected = st
    P.dungeons:SetRows(states, fillDungeon)
    P.bossHead:SetText(st and (st.d.name:upper() .. (key ~= KM.Char() and ("  -  " .. ns.CharName(c, key):upper()) or "")) or "")
    P.bosses.emptyText = "Click a dungeon."
    P.bosses:SetRows(st and st.bosses or {}, fillBoss)
    P.note:SetText(grey(ns.IsToday(c) and "Green: a Real still waits for this character today. Red: looted. One per boss a day, per character."
        or "The reset passed since this character was on: everything is green again."))
    if not P.ticker and C_Timer and C_Timer.NewTicker then
        P.ticker = C_Timer.NewTicker(TICK, function(self)
            if not KM.IsShown("reals") then self:Cancel(); P.ticker = nil return end
            KM.Refresh("reals")
        end)
    end
end

local function hide() if P.ticker then P.ticker:Cancel(); P.ticker = nil end end

local function col(key, label, w, justify, tip) return { key = key, label = label, w = w, justify = justify, tip = tip } end

local function build(c)
    P.tiles = {}
    for i = 1, 4 do
        local t = UI.Tile(c, TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), 0)
        P.tiles[i] = t
    end
    P.tiles[1]:SetTip("Reals this character looted since the daily reset. Each boss gives each character one a day.")
    P.tiles[2]:SetTip("Bosses whose Real for today this character hasn't looted yet (optional bosses and bosses that never showed one aren't counted).")
    P.tiles[3]:SetTip("Tarnished Undermine Reals this character holds, and the cap: what's over the cap is lost. Spend them at Pix Xizzix in Booty Bay.")
    P.tiles[4]:SetTip("Time to the daily reset, from the game. Then every boss has a Real again.")

    local y = -(TILE_H + 12)
    P.charBtn = UI.MenuButton(c, 170, charLabel, function(_, root)
        for _, row in ipairs(ns.CharRows()) do
            local label = ns.CharName(row.c, row.key) .. (row.me and " (you)" or "") .. (row.got > 0 and ("  " .. row.got .. " today") or "")
            root:CreateRadio(label, function() return (ns.db.ui.char or KM.Char()) == row.key end, function()
                ns.db.ui.char = (row.key ~= KM.Char()) and row.key or nil
                KM.Refresh("reals")
            end)
        end
    end)
    P.charBtn:SetPoint("TOPLEFT", 0, y)
    UI.Tip(P.charBtn, "Whose Reals to show. Each character is read when you play it.")
    P.notify = UI.CheckLabel(c, "Pop-up when a boss has a Real to loot", function(v) ns.db.settings.notify = v; ns.Changed() end,
        "In a dungeon: a pop-up and a chat line when a boss whose Real you haven't looted today goes down, and when you close its loot with the Real still in it. Also /reals notify on|off.")
    P.notify.frame:SetPoint("LEFT", P.charBtn, "RIGHT", 14, 0)

    local top = y - 34
    P.dungeons = UI.Table(c, {
        col("name", "Dungeon", 170, nil, "Green: at least one boss still has today's Real for this character. Red: all looted."),
        col("count", "Today", 60, "RIGHT", "Reals looted today / bosses that give one."),
        col("state", "", 0, nil),
    }, 24, { noSort = true, fontSize = 11, onClick = function(st)
        ns.db.ui.dungeon = st.d.name
        KM.Refresh("reals")
    end })
    P.dungeons:SetPoint("TOPLEFT", 0, top)
    P.dungeons:SetPoint("BOTTOMLEFT", 0, 18)
    P.dungeons:SetWidth(LIST_W)

    P.bossHead = UI.Heading(c, "")
    P.bossHead:SetPoint("TOPLEFT", LIST_W + 14, top + 16)
    P.bosses = UI.Table(c, {
        col("name", "Boss", 220, nil, "Green: its Real still waits today. Red: looted. Grey: optional, or no Real seen."),
        col("level", "Level", 46, "RIGHT"),
        col("state", "Today", 0, nil),
    }, 24, { noSort = true, fontSize = 11 })
    P.bosses:SetPoint("TOPLEFT", LIST_W + 14, top)
    P.bosses:SetPoint("BOTTOMRIGHT", 0, 18)
    P.note = UI.Text(c, 10, C.muted)
    P.note:SetPoint("BOTTOMLEFT", 2, 2)
    P.note:SetPoint("RIGHT", -20, 0)
end

---------------------------------------------------------------------------
-- The toast: our own small frame (no Blizzard alert frames)
---------------------------------------------------------------------------

local toast
ns.toasts = 0
function ns.Toast(text)
    if not toast then
        toast = CreateFrame("Button", "KingMakerRealsToast", UIParent)
        toast:SetSize(300, 50)
        toast:SetPoint("TOP", 0, -190)
        toast:SetFrameStrata("HIGH")
        UI.Fill(toast, { C.bg[1], C.bg[2], C.bg[3], 0.94 })
        UI.Border(toast, { 1, 1, 1, 0.10 })
        UI.GoldEdge(toast)
        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(30, 30)
        toast.icon:SetPoint("LEFT", 9, 0)
        toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        toast.text = UI.Text(toast, 12, C.text)
        toast.text:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 9, -1)
        toast.text:SetPoint("RIGHT", -8, 0)
        toast.sub = UI.Text(toast, 10, C.muted)
        toast.sub:SetPoint("TOPLEFT", toast.text, "BOTTOMLEFT", 0, -4)
        toast.sub:SetText("King Maker: click to open Reals")
        toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        toast:SetScript("OnClick", function(self, which)
            self:Hide()
            if which ~= "RightButton" then KM.Show("reals") end
        end)
        toast:Hide()
    end
    local icon = C_Item and C_Item.GetItemIconByID and ns.Call(C_Item.GetItemIconByID, ns.REAL_ITEM)
    toast.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Coin_17")
    toast.text:SetText(text)
    toast:Show()
    ns.toasts = ns.toasts + 1
    ns.lastToast = text
    if toast.timer then toast.timer:Cancel() end
    if C_Timer.NewTimer then toast.timer = C_Timer.NewTimer(10, function() toast:Hide(); toast.timer = nil end) end
end
function ns.ToastFrame() return toast end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function icon()
    local path = "Interface\\Icons\\INV_Misc_Coin_17"
    return path
end

KM.RegisterPage({
    id = "reals", group = "farm", label = "Reals", icon = icon(), order = 60,
    title = "Tarnished Undermine Reals",
    subtitle = "One Real per boss a day in the level 55+ dungeons: green still waits for you, red is looted.",
    build = build, refresh = refresh, hide = hide,
})

KM.RegisterQuickAction({ id = "reals", label = "Reals", order = 26, func = function() ns.Toggle(true) end })

KM.RegisterHomeCard({ kind = "chars", id = "reals", order = 45, get = function()
    if not ns.db then return nil end
    local out = {}
    for _, row in ipairs(ns.CharRows()) do
        if row.got > 0 then
            out[row.key] = { text = row.got .. " Real" .. (row.got == 1 and "" or "s"), color = C.good,
                tip = row.got .. " Tarnished Undermine Real" .. (row.got == 1 and "" or "s") .. " looted today." }
        end
    end
    return out
end })

local function set(k) return function(v) ns.db.settings[k] = v; ns.Changed() end end
local function get(k) return function() return ns.db.settings[k] end end

KM.RegisterSettings({ id = "reals", label = "Reals", order = 26, rows = {
    { type = "header", label = "In the dungeon" },
    { type = "check", label = "Pop-up when a boss has a Real to loot", get = get("notify"), set = set("notify"),
      tip = "A pop-up and a chat line when a boss whose Real you haven't looted today goes down, and when you close its loot with the Real still in it." },
    { type = "check", label = "Remind me when I leave with Reals unlooted", get = get("leave"), set = set("leave"),
      tip = "When you leave a dungeon, names the bosses you killed but didn't take the Real from." },
    { type = "header", label = "Commands" },
    { type = "text", label = "/reals   open the Reals page\n/reals status   what's left today, in chat\n/reals notify on|off   the pop-up\n/reals leave on|off   the leaving reminder\n/reals forget Name   forget a character\n/reals debug   what the game reports" },
} })
