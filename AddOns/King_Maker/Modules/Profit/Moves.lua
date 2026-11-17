local _, KM = ...
local ns = KM.Module("Profit")

-- 2.8: stock that changes form or hands keeps its cost, instead of "used or gone" on one side and untraced stock on the
-- other. Each case below is feature-detected; when a signal is missing, that case is left to the counts as in 2.7.
--   Crafting      UNIT_SPELLCAST_SUCCEEDED (player) for a recipe (Market's recipes, else C_TradeSkillUI's schematic),
--                 then the bags settling: the reagents that went down are used (u) and the product that came up is a
--                 lot (k) that costs what they cost. Casts of one recipe in a row ("Create all") are one batch. Nothing
--                 came up (an enchant on an item, a bound product): the reagents' cost is "used".
--   Disenchanting the "Disenchant" cast and its loot window (Core\Loot.lua's kind "de"): the item whose count fell by one
--                 is used (e) and each mat becomes a lot with a share of its cost, by what the mats are worth.
--   Quest rewards QUEST_TURNED_IN and what rose in the bags just after: lots that cost nothing (l, s = "quest").
--   Mail you send SendMailMailButton (HookScript, never a hook on SendMail) reads the To: box and GetSendMailItem;
--                 MAIL_SEND_SUCCESS records it: to one of your characters on this realm and faction it's in transit
--                 (y, "alt/..."; Recon counts it until that mailbox is read), to anyone else it's used up (y, "to/...").
--   Trades        the trade window's items and gold, read as they change (GetTradePlayerItemInfo/Link,
--                 GetTradeTargetItemInfo/Link, GetPlayerTradeMoney, GetTargetTradeMoney); when it closes, your gold and
--                 bags say whether it went through: what you got is a lot (t "in/...") costing what you gave, what you
--                 gave is a sale (t "out/...") for what you got.
-- While a craft, disenchant or quest reward is settling, the counts wait (ns.Moving), so they never close the mats
-- before the craft takes them.

local settled          -- the bags as they last settled (kept still while something is settling)
local casting, castAt  -- a recipe or Disenchant cast under way (UNIT_SPELLCAST_START), and when it began
local craft            -- { spell, recipe, n, base, t, last }
local de               -- { base, t, at, mats = { [id] = q }, closed }
local quest            -- { base, turned, at }
local pressed, pending -- mail read at the Send button: on mouse-down, and the one waiting for MAIL_SEND_SUCCESS
local trade            -- { base, money, partner, offer = { give, get, pm, tm }, closed, tries }

local STUCK = 60       -- seconds: a cast, disenchant or quest reward window that never finished lets go

local function snap() return ns.BagSnapshot and ns.BagSnapshot() or {} end
-- Lets go of anything that never finished (a missed event must never stop the counts for good).
local function unstick()
    local now = GetTime()
    if casting and now - (castAt or now) > STUCK then casting = nil end
    if de and now - (de.at or now) > STUCK then de = nil end
    if quest and now - (quest.at or now) > STUCK then quest = nil end
    if trade and now - (trade.at or now) > 10 * STUCK then trade = nil end   -- a trade window whose close we missed
end
local function held() unstick(); return casting or craft or de or quest or trade end
local function refresh() if not held() then settled = snap() end end
local function base() return settled or snap() end
local function money() return KM.Plain(GetMoney and GetMoney()) or 0 end
local function tracking() return ns.db and ns.db.start end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- True while a craft, disenchant or quest reward is settling (Recon waits).
function ns.Moving() unstick(); return (craft or de or quest) and true or false end

local function after()
    refresh()
    if ns.Schedule then ns.Schedule() end
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

-- { item (nil for an enchant), made, reagents = { { id, n } } } for a spell that crafts, or nil.
function ns.RecipeOf(spell)
    local mk = KM.mods.Market
    if mk and mk.Recipe and mk.db then
        local r = KM.Safe(mk.Recipe, spell)
        if r and type(r.reagents) == "table" and #r.reagents > 0 then
            local out = { item = r.item, made = r.made or 1, reagents = {} }
            for i = 1, #r.reagents, 2 do out.reagents[#out.reagents + 1] = { r.reagents[i], r.reagents[i + 1] or 1 } end
            return out
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, spell, false)
        if ok and type(s) == "table" and type(s.reagentSlotSchematics) == "table" then
            local out = { item = KM.Plain(s.outputItemID), made = KM.Plain(s.quantityMin) or 1, reagents = {} }
            for _, slot in ipairs(s.reagentSlotSchematics) do
                local first = type(slot.reagents) == "table" and slot.reagents[1]
                local id = first and KM.Plain(first.itemID)
                if id and slot.required ~= false then out.reagents[#out.reagents + 1] = { id, KM.Plain(slot.quantityRequired) or 1 } end
            end
            if #out.reagents > 0 then return out end
        end
    end
    return nil
end

local function isDisenchant(spell)
    if KM.CAST_IDS and KM.CAST_IDS[spell] == "de" then return true end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
    name = KM.Plain(name)
    return name ~= nil and KM.CAST_KIND ~= nil and KM.CAST_KIND[name] == "de"
end

-- What units no lot covers count at when they go into something: a vendor reagent at what a vendor charges (Market's
-- vendor price), anything else at its worth (KM.ItemValue).
function ns.ReagentValue(id, n)
    local mk = KM.mods.Market
    if mk and mk.db and mk.VENDOR_ITEMS and mk.VENDOR_ITEMS[id] and mk.VendorPrice then
        local p = KM.Safe(mk.VendorPrice, id)
        if p then return math.floor(p * n + 0.5) end
    end
    return ns.ValueOf(id, n)
end

---------------------------------------------------------------------------
-- Crafting
---------------------------------------------------------------------------

local function settleCraft()
    local c = craft
    craft = nil
    if not (c and tracking()) then return after() end
    local now = snap()
    local pool, who = ns.MyPool(), KM.Char()
    local uses = {}
    for _, rg in ipairs(c.recipe.reagents) do
        local id, per = rg[1], rg[2]
        local n = math.min((c.base[id] or 0) - (now[id] or 0), per * c.n)
        if n > 0 and not ns.Excluded(id) then uses[#uses + 1] = { id, n } end
    end
    local item = c.recipe.item
    local rose = item and ((now[item] or 0) - (c.base[item] or 0)) or 0
    if #uses > 0 then
        local made = rose > 0 and not ns.Excluded(item)
        local g = made and ns.Reserve() or nil
        local ins = {}
        for _, x in ipairs(uses) do
            ns.Add(pool, x[1], "u", { t = c.t, q = x[2], v = ns.ReagentValue(x[1], x[2]), who = who, s = g and tostring(g) or "used" })
            ins[#ins + 1] = x[1]
            ns.Mark(pool, x[1])
        end
        if made then
            ns.Add(pool, item, "k", { id = g, t = c.t, q = rose, v = ns.ValueOf(item, rose), who = who, s = g .. "/" .. table.concat(ins, ",") })
            ns.Mark(pool, item)
        end
    end
    after()
end

-- The batch is done once no cast of it is under way and the last one is a moment old.
local function trySettle()
    if craft and not casting and GetTime() - (craft.last or 0) >= 1.5 then settleCraft() end
end

local function onCraft(spell, recipe)
    if craft and craft.spell ~= spell then settleCraft() end
    if not craft then craft = { spell = spell, recipe = recipe, n = 0, base = base(), t = KM.Now() } end
    craft.n, craft.last = craft.n + 1, GetTime()
    C_Timer.After(2, trySettle)
end

---------------------------------------------------------------------------
-- Disenchanting
---------------------------------------------------------------------------

-- A disenchanted mat looted (Journal's loot reader asks): kept for the item's cost when the window closes.
function ns.DEMat(id, q)
    if not de or de.closed then return false end
    de.mats[id] = (de.mats[id] or 0) + (q or 1)
    return true
end

-- Splits total over list { { id, q } } by what each is worth (by units when a price is missing); shares add up.
local function split(list, total)
    local w, sum, known = {}, 0, true
    for i, x in ipairs(list) do
        w[i] = ns.ValueOf(x[1], x[2])
        if not w[i] then known = false end
    end
    if known then for i in ipairs(list) do sum = sum + w[i] end end
    if not known or sum <= 0 then
        sum = 0
        for i, x in ipairs(list) do w[i] = x[2]; sum = sum + x[2] end
    end
    local out, given = {}, 0
    for i in ipairs(list) do
        out[i] = i == #list and (total - given) or math.floor(total * w[i] / sum)
        given = given + out[i]
    end
    return out
end

local function settleDE()
    local d = de
    if not (d and d.closed) then return end
    de = nil
    if not tracking() then return after() end
    local now = snap()
    local pool, who = ns.MyPool(), KM.Char()
    local mats = {}
    for id, q in pairs(d.mats) do mats[#mats + 1] = { id, q } end
    table.sort(mats, function(a, b) return a[1] < b[1] end)
    -- the item: one fewer than before the cast and not one of the mats; an uncommon or better weapon or armour first
    local src, best, ties
    for id, n in pairs(d.base) do
        if not d.mats[id] and n - (now[id] or 0) == 1 then
            local i = KM.Item(id)
            local score = ((i.class == 2 or i.class == 4) and 2 or 0) + ((i.q or 0) >= 2 and 1 or 0)
            if not best or score > best then src, best, ties = id, score, 1
            elseif score == best then ties = ties + 1 end
        end
    end
    if src and ties == 1 and not ns.Excluded(src) and #mats > 0 then
        local g = ns.Reserve()
        ns.Add(pool, src, "e", { id = g, t = d.t, q = 1, v = ns.ValueOf(src, 1), who = who, s = tostring(g) })
        ns.Mark(pool, src)
        local shares = split(mats, 10000)
        for i, x in ipairs(mats) do
            ns.Add(pool, x[1], "k", { t = d.t, q = x[2], v = ns.ValueOf(x[1], x[2]), who = who, s = g .. "/" .. src .. "/" .. shares[i] })
            ns.Mark(pool, x[1])
        end
    else
        -- the item wasn't found (bound, or the bags moved too much): the mats are loot, as in 2.7
        for _, x in ipairs(mats) do
            ns.Add(pool, x[1], "l", { t = d.t, q = x[2], c = 0, v = ns.ValueOf(x[1], x[2]), who = who, s = "de" })
        end
    end
    after()
end

-- The disenchant's loot window closed (Journal's loot reader passes it on).
function ns.DEClose()
    if not de then return end
    de.closed = true
    C_Timer.After(0.5, settleDE)
end

---------------------------------------------------------------------------
-- Quest rewards
---------------------------------------------------------------------------

local function questCheck()
    local q = quest
    if not (q and q.turned) then return end
    local now = snap()
    local got = {}
    for id, n in pairs(now) do
        local d = n - (q.base[id] or 0)
        if d > 0 and not ns.Excluded(id) then got[#got + 1] = { id, d } end
    end
    if #got == 0 then return end
    quest = nil
    if tracking() then
        local pool, who = ns.MyPool(), KM.Char()
        for _, x in ipairs(got) do
            ns.Add(pool, x[1], "l", { t = q.turned, q = x[2], c = 0, v = ns.ValueOf(x[1], x[2]), who = who, s = "quest" })
            ns.Mark(pool, x[1])
        end
    end
    after()
end

local function questEnd()
    if quest and quest.turned then quest = nil; after() end
end

---------------------------------------------------------------------------
-- Mail you send
---------------------------------------------------------------------------

-- The character a To: box means, if it's one of yours on this realm and faction: "Cowlossus Bones", "Cowlossus" (when
-- only one of yours has that first name) or "Cowlossus Bones-Realm". nil for anyone else.
function ns.AltKey(to)
    if type(to) ~= "string" then return nil end
    to = to:match("^%s*(.-)%s*$")
    if to == "" then return nil end
    local name, realm = to:match("^(.-)%-(.+)$")
    name = (name or to):lower()
    local me, pool = KM.Char(), ns.MyPool()
    local myRealm = ns.RealmOf(me)
    if realm and myRealm and realm:gsub("[%s']", ""):lower() ~= myRealm:gsub("[%s']", ""):lower() then return nil end
    local keys = {}
    local inv = KM.mods.Inventory
    for key in pairs(inv and inv.db and inv.db.chars or {}) do keys[key] = true end
    local p = ns.Pool(pool)
    for _, key in ipairs(p and p.chars or {}) do keys[key] = true end
    local firstHit, firsts = nil, 0
    for key in pairs(keys) do
        if key ~= me and key ~= "Warband" and ns.PoolOf(key) == pool then
            local full = (key:match("^(.-)%-") or key):lower()
            if full == name then return key end
            if full:match("^(%S+)") == name then firstHit, firsts = key, firsts + 1 end
        end
    end
    if firsts == 1 then return firstHit end
    return nil
end

-- What's on the mail being sent: { to, items = { { id, q } } }. GetSendMailItem's returns differ between clients
-- (name, itemID, texture, count on modern ones; name, texture, count on Classic), so the item comes from the link
-- and the count from whichever place fits.
local function readSend()
    if not GetSendMailItem then return nil end
    local to = SendMailNameEditBox and SendMailNameEditBox.GetText and SendMailNameEditBox:GetText() or nil
    local items = {}
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        local r = { pcall(GetSendMailItem, i) }
        if r[1] and r[2] then
            local id
            if GetSendMailItemLink then
                local ok, link = pcall(GetSendMailItemLink, i)
                link = ok and KM.Plain(link)
                id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
            end
            local count
            if id and KM.Plain(r[3]) == id then count = KM.Plain(r[5])
            elseif not id then id, count = KM.Plain(r[3]), KM.Plain(r[5])
            else count = KM.Plain(r[4]) end
            if type(id) == "number" then items[#items + 1] = { id, tonumber(count) or 1 } end
        end
    end
    return { to = to, items = items }
end
ns.ReadSend = readSend

local function sent()
    local m = pending
    pending = nil
    if not (m and tracking()) or #m.items == 0 then return end
    local pool, who = ns.MyPool(), KM.Char()
    local alt = ns.AltKey(m.to)
    local to = tostring(m.to or ""):match("^%s*(.-)%s*$"):gsub(":", "")
    for _, x in ipairs(m.items) do
        if not ns.Excluded(x[1]) then
            ns.Add(pool, x[1], "y", { q = x[2], who = who, s = alt and ("alt/" .. alt) or ("to/" .. to) })
            ns.Mark(pool, x[1])
        end
    end
end

local function hookSend()
    if not (SendMailMailButton and SendMailMailButton.HookScript) or SendMailMailButton.kmProfit then return end
    SendMailMailButton.kmProfit = true
    SendMailMailButton:HookScript("OnMouseDown", function() if ns.db then pressed = KM.Safe(readSend) end end)
    SendMailMailButton:HookScript("OnClick", function()
        if not ns.db then return end
        pending = pressed or KM.Safe(readSend)
        pressed = nil
    end)
end

---------------------------------------------------------------------------
-- Trades
---------------------------------------------------------------------------

local function tradeItems(getLink, getInfo)
    local out = {}
    if not getLink then return out end
    for i = 1, MAX_TRADABLE_ITEMS or 6 do
        local ok, link = pcall(getLink, i)
        link = ok and KM.Plain(link)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
        if id then
            local n = 1
            if getInfo then
                local ok2, _, _, count = pcall(getInfo, i)
                if ok2 then n = tonumber(KM.Plain(count)) or 1 end
            end
            out[id] = (out[id] or 0) + n
        end
    end
    return out
end

local function readTrade()
    if not trade then return end
    local o = { give = tradeItems(GetTradePlayerItemLink, GetTradePlayerItemInfo),
        get = tradeItems(GetTradeTargetItemLink, GetTradeTargetItemInfo),
        pm = tonumber(KM.Plain(GetPlayerTradeMoney and GetPlayerTradeMoney())) or 0,
        tm = tonumber(KM.Plain(GetTargetTradeMoney and GetTargetTradeMoney())) or 0 }
    -- a window emptied as the trade completes doesn't replace what was offered
    if next(o.give) or next(o.get) or o.pm > 0 or o.tm > 0 then trade.offer = o end
end

local function partnerName()
    if not UnitName then return "someone" end
    local n, s = UnitName("NPC")
    n, s = KM.Plain(n), KM.Plain(s)
    if type(n) ~= "string" or n == "" then return "someone" end
    if type(s) == "string" and s ~= "" then n = n .. " " .. s end
    return (n:gsub("[:/]", ""))
end

local function tradeOpen()
    if trade or not (GetTradePlayerItemLink and GetTradeTargetItemLink) then return end
    trade = { base = base(), money = money(), partner = partnerName(), tries = 0, at = GetTime() }
end

-- What went through: what you got costs what you gave, what you gave sold for what you got (gold first; items at
-- their worth when both sides gave items). A gift either way records nothing: the counts deal with it.
local function recordTrade(o, partner)
    local give, get = {}, {}
    for id, n in pairs(o.give) do if not ns.Excluded(id) then give[#give + 1] = { id, n } end end
    for id, n in pairs(o.get) do if not ns.Excluded(id) then get[#get + 1] = { id, n } end end
    table.sort(give, function(a, b) return a[1] < b[1] end)
    table.sort(get, function(a, b) return a[1] < b[1] end)
    local worthGet = 0
    for _, x in ipairs(get) do
        local v = ns.ValueOf(x[1], x[2])
        if not v then worthGet = nil; break end
        worthGet = worthGet + v
    end
    local pool, who = ns.MyPool(), KM.Char()
    if #get > 0 and (o.pm > 0 or #give > 0) then
        local cost = (#give > 0 and worthGet) or o.pm
        local shares = split(get, cost)
        for i, x in ipairs(get) do
            ns.Add(pool, x[1], "t", { q = x[2], c = shares[i], v = ns.ValueOf(x[1], x[2]), who = who, s = "in/" .. partner })
            ns.Mark(pool, x[1])
        end
    end
    if #give > 0 and (o.tm > 0 or #get > 0) then
        local proceeds = o.tm
        if #get > 0 and worthGet then proceeds = math.max(0, o.tm + worthGet - o.pm) end
        local shares = split(give, proceeds)
        for i, x in ipairs(give) do
            ns.Add(pool, x[1], "t", { q = x[2], c = shares[i], who = who, s = "out/" .. partner })
            ns.Mark(pool, x[1])
        end
    end
end

-- After the window closes: did it go through? Your gold moved by exactly what was offered, and the items left and
-- arrived. Asked twice (the bags can lag); a trade that never happened records nothing.
local function settleTrade()
    local tr = trade
    if not (tr and tr.closed) then return end
    local o = tr.offer
    if not o then trade = nil; return after() end
    local now = snap()
    local ok = money() - tr.money == o.tm - o.pm
    for id, n in pairs(o.give) do if (tr.base[id] or 0) - (now[id] or 0) < n then ok = false end end
    for id, n in pairs(o.get) do if (now[id] or 0) - (tr.base[id] or 0) < n then ok = false end end
    if not ok then
        tr.tries = tr.tries + 1
        if tr.tries >= 2 then trade = nil; after() end
        return
    end
    trade = nil
    if tracking() then recordTrade(o, tr.partner) end
    after()
end

local function tradeClosed()
    if not trade or trade.closed then return end
    trade.closed = true
    C_Timer.After(0.5, settleTrade)
    C_Timer.After(2, settleTrade)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local TRADE = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.TradePartner) or 1
local TRADE_CHANGED = { TRADE_PLAYER_ITEM_CHANGED = true, TRADE_TARGET_ITEM_CHANGED = true, TRADE_MONEY_CHANGED = true,
    TRADE_ACCEPT_UPDATE = true }

local f = CreateFrame("Frame")
KM.Register(f, "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "QUEST_COMPLETE", "QUEST_TURNED_IN", "QUEST_FINISHED", "MAIL_SHOW",
    "MAIL_SEND_SUCCESS", "MAIL_FAILED", "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_SUCCEEDED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
        if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, e, "player") else pcall(f.RegisterEvent, f, e) end
    end
end

local function onSpell(event, unit, spell)
    if KM.Plain(unit) ~= "player" then return end
    spell = KM.Plain(spell)
    if type(spell) ~= "number" then return end
    if event == "UNIT_SPELLCAST_START" then
        if not inCombat() and (isDisenchant(spell) or ns.RecipeOf(spell)) then casting, castAt = spell, GetTime() end
        return
    end
    if casting == spell then casting = nil end
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if not held() then refresh() end
        return
    end
    if not tracking() or inCombat() then return end
    if isDisenchant(spell) then
        de = { base = base(), t = KM.Now(), at = GetTime(), mats = {} }
        -- a disenchant whose loot window never shows lets go after a while
        C_Timer.After(15, function() if de and not de.closed and GetTime() - de.at >= 10 then de = nil; after() end end)
        return
    end
    local recipe = ns.RecipeOf(spell)
    if recipe then onCraft(spell, recipe) end
end

f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        hookSend()
        settled = snap()
    elseif event:sub(1, 15) == "UNIT_SPELLCAST_" then
        KM.Safe(onSpell, event, a1, a3)
    elseif event == "BAG_UPDATE_DELAYED" then
        if craft then C_Timer.After(2, trySettle) end
        if quest and quest.turned then KM.Safe(questCheck) end
        refresh()
    elseif event == "QUEST_COMPLETE" then
        if not quest then quest = { base = base(), at = GetTime() } end
    elseif event == "QUEST_TURNED_IN" then
        quest = quest or { base = base() }
        quest.at = GetTime()
        quest.turned = KM.Now()
        C_Timer.After(0.5, function() KM.Safe(questCheck) end)
        C_Timer.After(2.5, questEnd)
    elseif event == "QUEST_FINISHED" then
        if quest and not quest.turned then quest = nil; refresh() end
    elseif event == "MAIL_SHOW" then
        hookSend()
    elseif event == "MAIL_SEND_SUCCESS" then
        KM.Safe(sent)
    elseif event == "MAIL_FAILED" then
        pending, pressed = nil, nil
    elseif event == "TRADE_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and KM.Plain(a1) == TRADE) then
        KM.Safe(tradeOpen)
    elseif TRADE_CHANGED[event] then
        if trade and not trade.closed then KM.Safe(readTrade) end
    elseif event == "TRADE_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and KM.Plain(a1) == TRADE) then
        tradeClosed()
    end
end)
