local _, KM = ...
local ns = KM.Module("Profession", { title = "Profession window", short = "Profession", db = "ProfessionKingDB" })

-- Profession window: a King Maker panel docked to the side of the game's own profession window. For the recipe
-- you have selected it shows what the materials cost (and how many you own), what the result sells for, the profit
-- after the auction cut, the disenchant value, Market's verdict in both its modes and your skill-up chance; a second
-- tab lists the best crafts right now and your next skill-up steps.
--
-- It only reads. It never crafts, never changes or re-parents a Blizzard frame, and never calls anything in
-- C_AuctionHouse. It supports whichever window the client has, feature-detected:
--   modern   ProfessionsFrame (Blizzard_Professions, load-on-demand): selection from
--            ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo() and the EventRegistry callback
--            "ProfessionsRecipeListMixin.Event.OnRecipeSelected"; data from C_TradeSkillUI
--   classic  TradeSkillFrame (Blizzard_TradeSkillUI): GetTradeSkillSelectionIndex / GetTradeSkill*, and
--            hooksecurefunc("TradeSkillFrame_SetSelection")
--   craft    CraftFrame (Blizzard_CraftUI, Enchanting in Classic): GetCraftSelectionIndex / GetCraft*, and
--            hooksecurefunc("CraftFrame_SetSelection")
-- The panel shows and hides with the window (HookScript OnShow / OnHide) and also polls the selection while it is
-- open, so a missing callback only costs a quarter of a second.
--
-- Files: Core.lua (saved data, window detection and hooks, tooltips, settings), Data.lua (the numbers: recipe,
-- reagents, prices, verdicts, best now), Panel.lua (the panel).

ns.CHECK_EVERY = 0.25 -- seconds between selection checks while the panel is open

local function market() local m = KM.mods.Market; return m and m.db and m or nil end
ns.Market = market

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- Runs when King Maker's saved variables load (and again if Boot ever re-runs it): safe twice.
function ns.InitDB()
    ProfessionKingDB = ProfessionKingDB or {}
    local db = ProfessionKingDB
    if db.show == nil then db.show = true end         -- dock the panel to the profession window
    if db.side ~= "left" and db.side ~= "right" then db.side = "right" end
    if db.tooltip == nil then db.tooltip = true end   -- King Maker lines in recipe tooltips
    if db.mode ~= "buy" and db.mode ~= "farm" and db.mode ~= "market" then db.mode = "market" end
    db.collapsed = db.collapsed and true or false
    if db.tab ~= "card" and db.tab ~= "best" then db.tab = "card" end
    db.crafts = math.max(1, math.min(200, tonumber(db.crafts) or 1))
    ns.db = db
    ns.WrapSlash()
end

-- Which way to count materials: "buy" (a cost) or "farm" (yours already); "market" follows Crafting Profits.
function ns.Mode()
    local mode = ns.db and ns.db.mode or "market"
    if mode == "market" then
        local m = market()
        return (m and m.db.mode == "farm") and "farm" or "buy"
    end
    return mode
end

-- "/km profession" opens this module's settings. Boot owns /km; we only pass everything else on to it.
function ns.WrapSlash()
    if ns.slashWrapped or not (SlashCmdList and SlashCmdList.KINGMAKER) then return end
    local orig = SlashCmdList.KINGMAKER
    ns.slashWrapped = true
    SlashCmdList.KINGMAKER = function(msg)
        local cmd = ((msg or ""):match("^%s*(%S+)") or ""):lower()
        if cmd == "profession" or cmd == "professions" then
            KM.OpenSettings("profession")
            return
        end
        return orig(msg)
    end
end

---------------------------------------------------------------------------
-- The game's profession windows
---------------------------------------------------------------------------

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end
ns.Call = call

local function idFrom(link, kind)
    return type(link) == "string" and tonumber(link:match((kind or "item") .. ":(%d+)")) or nil
end
ns.IDFrom = idFrom

local DIFFICULTY = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey",
    [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
ns.DIFFICULTY = DIFFICULTY

-- A selection: { key, source, spell, item, name, icon, made, reagents = { id, count, ... }, have = { [id] = n },
--                difficulty = "orange"..., profName, skill, maxSkill }
local adapters = {}
ns.adapters = adapters

-- Modern: ProfessionsFrame + C_TradeSkillUI.
adapters.modern = {
    key = "modern", addon = "Blizzard_Professions",
    frame = function() return _G.ProfessionsFrame end,
    recipeID = function()
        local f = _G.ProfessionsFrame
        local form = f and f.CraftingPage and f.CraftingPage.SchematicForm
        if form then
            local info = call(form.GetRecipeInfo, form)
            if type(info) == "table" and info.recipeID then return info.recipeID end
            local cur = rawget(form, "currentRecipeInfo")
            if type(cur) == "table" and cur.recipeID then return cur.recipeID end
        end
        return ns.modernSelected
    end,
    profession = function()
        local T = C_TradeSkillUI
        if not T then return nil end
        local base, child = call(T.GetBaseProfessionInfo), call(T.GetChildProfessionInfo)
        base = type(base) == "table" and base or nil
        child = type(child) == "table" and child or nil
        local name = (base and base.professionName ~= "" and base.professionName) or (child and child.professionName)
        if not name then return nil end
        -- the skill sits on the child line when the client splits professions by expansion
        local s = (child and (child.skillLevel or 0) > 0 and child) or base or child
        return name, s.skillLevel, s.maxSkillLevel
    end,
    current = function(self) local id = self.recipeID(); return id and ("m:" .. id) end,
    read = function(self)
        local T = C_TradeSkillUI
        local id = self.recipeID()
        if not (id and T) then return nil end
        local sel = { key = "m:" .. id, source = "modern", spell = id, reagents = {}, have = {} }
        local info = call(T.GetRecipeInfo, id)
        if type(info) == "table" then
            sel.name, sel.icon = info.name, info.icon
            sel.difficulty = DIFFICULTY[info.relativeDifficulty]
        end
        local s = call(T.GetRecipeSchematic, id, false)
        if type(s) == "table" then
            sel.item = s.outputItemID
            sel.made = s.quantityMin or 1
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                local r = slot.reagents and slot.reagents[1]
                if r and r.itemID then
                    table.insert(sel.reagents, r.itemID)
                    table.insert(sel.reagents, slot.quantityRequired or 1)
                end
            end
        end
        sel.profName, sel.skill, sel.maxSkill = self.profession()
        return sel
    end,
}

-- Classic: TradeSkillFrame + GetTradeSkill*.
local function classicRead(src, p)
    local idx = call(p.index)
    if not idx or idx <= 0 then return nil end
    local name, kind = p.info(idx)
    if not name or kind == "header" or kind == "subheader" then return nil end
    local sel = { key = src .. ":" .. idx .. ":" .. tostring(name), source = src, name = name, reagents = {}, have = {} }
    sel.difficulty = DIFFICULTY[kind]
    local link = call(p.itemLink, idx)
    sel.spell = idFrom(call(p.recipeLink, idx), "enchant") or idFrom(link, "enchant") or idFrom(link, "spell")
    sel.item = idFrom(link, "item")
    sel.icon = call(p.icon, idx)
    local lo = call(p.numMade, idx)
    sel.made = (type(lo) == "number" and lo > 0) and lo or 1
    for j = 1, call(p.numReagents, idx) or 0 do
        local _, _, count, playerCount = call(p.reagentInfo, idx, j)
        local id = idFrom(call(p.reagentLink, idx, j), "item")
        if id then
            table.insert(sel.reagents, id)
            table.insert(sel.reagents, count or 1)
            if playerCount then sel.have[id] = playerCount end
        end
    end
    sel.profName, sel.skill, sel.maxSkill = call(p.line)
    return sel
end

local function classicAPI()
    return { index = _G.GetTradeSkillSelectionIndex, info = function(i) return call(_G.GetTradeSkillInfo, i) end,
        itemLink = _G.GetTradeSkillItemLink, recipeLink = _G.GetTradeSkillRecipeLink, icon = _G.GetTradeSkillIcon,
        numMade = _G.GetTradeSkillNumMade, numReagents = _G.GetTradeSkillNumReagents,
        reagentInfo = _G.GetTradeSkillReagentInfo, reagentLink = _G.GetTradeSkillReagentItemLink, line = _G.GetTradeSkillLine }
end

local function craftAPI()
    return { index = _G.GetCraftSelectionIndex,
        info = function(i) local name, _, kind = call(_G.GetCraftInfo, i); return name, kind end,
        itemLink = _G.GetCraftItemLink, recipeLink = _G.GetCraftRecipeLink, icon = _G.GetCraftIcon,
        numMade = _G.GetCraftNumMade, numReagents = _G.GetCraftNumReagents,
        reagentInfo = _G.GetCraftReagentInfo, reagentLink = _G.GetCraftReagentItemLink, line = _G.GetCraftDisplaySkillLine }
end

adapters.classic = {
    key = "classic", addon = "Blizzard_TradeSkillUI", setter = "TradeSkillFrame_SetSelection",
    frame = function() return _G.TradeSkillFrame end,
    current = function()
        local idx = call(_G.GetTradeSkillSelectionIndex)
        if not idx then return nil end
        return "classic:" .. idx .. ":" .. tostring((call(_G.GetTradeSkillInfo, idx)))
    end,
    read = function() return classicRead("classic", classicAPI()) end,
}

adapters.craft = {
    key = "craft", addon = "Blizzard_CraftUI", setter = "CraftFrame_SetSelection",
    frame = function() return _G.CraftFrame end,
    current = function()
        local idx = call(_G.GetCraftSelectionIndex)
        if not idx then return nil end
        return "craft:" .. idx .. ":" .. tostring((call(_G.GetCraftInfo, idx)))
    end,
    read = function() return classicRead("craft", craftAPI()) end,
}

ns.ADAPTER_ORDER = { "modern", "classic", "craft" }

-- The window that is open now (the last one shown), or nil.
function ns.Active()
    local a = ns.active and adapters[ns.active]
    local f = a and a.frame()
    if f and f.IsShown and f:IsShown() then return a, f end
    return nil
end

local function onWindowShow(key)
    ns.active = key
    ns.pinned = nil
    if ns.ShowPanel then KM.Safe(ns.ShowPanel) end
end

local function onWindowHide(key)
    if ns.active ~= key then return end
    ns.active = nil
    ns.pinned = nil
    if ns.HidePanel then KM.Safe(ns.HidePanel) end
end

ns.hooked = {}

-- Hooks whatever profession windows exist now. Safe to call often: each hook goes in once.
function ns.Hook()
    for _, key in ipairs(ns.ADAPTER_ORDER) do
        local a = adapters[key]
        local f = a.frame()
        if f and f.HookScript and not ns.hooked[key] then
            ns.hooked[key] = true
            f:HookScript("OnShow", function() onWindowShow(key) end)
            f:HookScript("OnHide", function() onWindowHide(key) end)
            if f:IsShown() and (not f.IsVisible or f:IsVisible()) and ns.loggedIn then onWindowShow(key) end
        end
        -- the classic windows' selection functions: a post-hook on a Blizzard global (allowed), never a replacement
        if a.setter and not ns.hooked[a.setter] and type(_G[a.setter]) == "function" and hooksecurefunc then
            ns.hooked[a.setter] = true
            hooksecurefunc(a.setter, function() if ns.Changed then ns.Changed() end end)
        end
    end
    if not ns.hooked.registry and EventRegistry and EventRegistry.RegisterCallback then
        ns.hooked.registry = true
        pcall(EventRegistry.RegisterCallback, EventRegistry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected",
            function(_, recipeInfo)
                if type(recipeInfo) == "table" and recipeInfo.recipeID then ns.modernSelected = recipeInfo.recipeID end
                if ns.Changed then ns.Changed() end
            end, ns)
    end
end

-- Something about the selection or its numbers changed: redraw the panel if it is open.
function ns.Changed()
    if ns.Refresh then KM.Safe(ns.Refresh) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
KM.Register(ev, "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "CRAFT_SHOW",
    "CRAFT_UPDATE", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED")
ev:SetScript("OnEvent", function(_, event, name)
    if not ns.db then return end
    if event == "ADDON_LOADED" then
        if name == "Blizzard_Professions" or name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" then ns.Hook() end
    elseif event == "PLAYER_LOGIN" then
        ns.loggedIn = true
        ns.Hook()
        if ScannerKing and ScannerKing.RegisterCallback then
            ScannerKing.RegisterCallback("Profession_King", function(e) if e == "PRICES_UPDATED" then ns.Changed() end end)
        end
    else
        if event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then ns.Hook() end
        ns.Changed()
    end
end)

---------------------------------------------------------------------------
-- Tooltips: a line or two on recipe tooltips inside the profession window
---------------------------------------------------------------------------

-- True when the tooltip's owner sits inside one of the game's profession windows.
local function insideWindow(owner)
    local roots = {}
    for _, key in ipairs(ns.ADAPTER_ORDER) do
        local f = adapters[key].frame()
        if f then roots[f] = true end
    end
    if not next(roots) then return false end
    local p, n = owner, 0
    while p and n < 25 do
        if roots[p] then return true end
        p = p.GetParent and call(p.GetParent, p) or nil
        n = n + 1
    end
    return false
end
ns.InsideWindow = insideWindow

local function onTooltip(tooltip, data, kind)
    if not (ns.db and ns.db.tooltip) or tooltip ~= GameTooltip then return end
    local owner = tooltip.GetOwner and call(tooltip.GetOwner, tooltip)
    if not owner or not insideWindow(owner) then return end
    local id = type(data) == "table" and data.id
    if not id and kind == "item" and TooltipUtil and TooltipUtil.GetDisplayedItem then
        id = select(3, call(TooltipUtil.GetDisplayedItem, tooltip))
    end
    if not id or not ns.TooltipLines then return end
    local lines = KM.Safe(ns.TooltipLines, kind, id)
    if not lines or #lines == 0 then return end
    for _, l in ipairs(lines) do tooltip:AddLine(l, 1, 1, 1) end
    if tooltip.Show then tooltip:Show() end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    if Enum.TooltipDataType.Item then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data) onTooltip(tt, data, "item") end)
    end
    if Enum.TooltipDataType.Spell then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Spell, function(tt, data) onTooltip(tt, data, "spell") end)
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

KM.RegisterSettings({ id = "profession", label = "Profession window", order = 22, rows = {
    { type = "header", label = "Panel next to the profession window" },
    { type = "check", label = "Show the King Maker panel", tip = "Docks a panel to the game's profession window with costs, profit, verdicts and skill-ups for the selected recipe.",
      get = function() return ns.db.show end,
      set = function(v) ns.db.show = v and true or false; if v then KM.Safe(ns.ShowPanel) else KM.Safe(ns.HidePanel) end end },
    { type = "choice", label = "Dock it on the", options = { { "right", "Right" }, { "left", "Left" } },
      get = function() return ns.db.side end, set = function(v) ns.db.side = v; KM.Safe(ns.Place) end },
    { type = "check", label = "King Maker lines in recipe tooltips", tip = "Cost, profit and skill-up chance when you hover a recipe's item in the profession window.",
      get = function() return ns.db.tooltip end, set = function(v) ns.db.tooltip = v and true or false end },
    { type = "choice", label = "Count materials as", options = { { "market", "Like Crafting Profits" }, { "buy", "Bought" }, { "farm", "Farmed" } },
      get = function() return ns.db.mode end, set = function(v) ns.db.mode = v; ns.Changed() end },
    { type = "text", label = "Bought: materials are a cost, so a craft has to beat zero. Farmed: you already have them, so a craft has to beat selling them raw. The recipe card always shows both verdicts; this picks the profit line, the Best now ranking and the tooltips. /km profession opens this section." },
} })
