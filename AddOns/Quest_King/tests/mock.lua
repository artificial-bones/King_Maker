-- Stand-in for the WoW Forever client (Mainline API, modern bags and tooltips),
-- enough to run Quest King outside the game.
local out = {}
_G.OUTPUT = out
function print(...) local t = {} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end out[#out+1]=table.concat(t," ") end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out+1] = m end }
SlashCmdList = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_CONTAINER_FRAMES = 4, 5, 13

-- Forever doesn't have these Classic globals; touching them must fail loudly.
for _, name in ipairs({ "GetItemInfo", "GetContainerItemInfo", "GetContainerNumSlots", "GetQuestLogTitle" }) do
  _G[name] = nil
end
-- Events the Forever client doesn't know.
UNKNOWN_EVENTS = { QUEST_WATCH_UPDATE = true, ITEM_LOCK_CHANGED_CLASSIC = true }
C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }

TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS+1] = fn end }
function RUN_TIMERS() while #TIMERS > 0 do table.remove(TIMERS, 1)() end end

local function stub(t)
  return setmetatable(t, {__index=function(_, k) if type(k) == "string" and k:match("^%u") and not k:match("^QuestKing") then return function() end end end})
end
function hooksecurefunc(a, b, c)
  if type(a) == "string" then
    local orig = _G[a]; _G[a] = function(...) local r = orig(...); b(...); return r end
  else
    local orig = a[b]; a[b] = function(...) local r = orig(...); c(...); return r end
  end
end

local frames = {}
_G.FRAMES = frames
local KNOWN_SCRIPTS = { OnShow = true, OnHide = true, OnEvent = true, OnEnter = true, OnLeave = true }
function CreateFrame(_, name)
  local f = stub({ scripts = {}, events = {}, hooks = {} })
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:HasScript(k) return KNOWN_SCRIPTS[k] or false end
  function f:HookScript(k, fn)
    if not KNOWN_SCRIPTS[k] then error(self:GetName() .. " doesn't have a \"" .. k .. "\" script") end
    self.hooks[k] = fn
  end
  function f:GetName() return name end
  function f:RegisterEvent(e)
    if UNKNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end
    self.events[e] = true
  end
  function f:CreateTexture()
    local t = stub({})
    function t:SetShown(v) self.shown = v end
    function t:SetTexture(p) self.texture = p end
    return t
  end
  function f:Show() self.shown = true; if self.hooks.OnShow then self.hooks.OnShow(self) end end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown == true end
  function f:GetID() return self.id or 0 end
  frames[#frames+1] = f
  if name then _G[name] = f end
  return f
end
function FIRE(event, ...)
  for _, f in ipairs(frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end

-- Items: id -> { name, classID }
ITEMS = {}
function LINK(id) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. ITEMS[id][1] .. "]|h|r" end
C_Item = {
  GetItemInfoInstant = function(id) local i = ITEMS[id]; if i then return id, "", "", "", 0, i[2], 0 end end,
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end,
}

-- Bags: BAGS[bag][slot] = { id = , count = , quest = { isQuestItem, questID, isActive } }
BAGS = { [0] = {}, {}, {}, {}, {}, {} }
SIZES = { [0] = 16, 10, 10, 0, 0, 0 }
C_Container = {
  GetContainerNumSlots = function(bag) return SIZES[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local e = BAGS[bag] and BAGS[bag][slot]
    if e then return { itemID = e.id, hyperlink = LINK(e.id), stackCount = e.count or 1, iconFileID = 1 } end
  end,
  GetContainerItemQuestInfo = function(bag, slot)
    local e = BAGS[bag] and BAGS[bag][slot]
    local q = e and e.quest or {}
    return { isQuestItem = q.isQuestItem or false, questID = q.questID, isActive = q.isActive or false }
  end,
}

-- Quest log: entries in order; headers have isHeader.
LOG, COMPLETED = {}, {}
C_QuestLog = {
  GetNumQuestLogEntries = function()
    local shown, quests, hidden = 0, 0, false
    for _, e in ipairs(LOG) do
      if e.isHeader then shown = shown + 1; hidden = e.isCollapsed
      else quests = quests + 1; if not hidden then shown = shown + 1 end end
    end
    return shown, quests
  end,
  GetInfo = function(i)
    local n, hidden = 0, false
    for _, e in ipairs(LOG) do
      local visible = e.isHeader or not hidden
      if e.isHeader then hidden = e.isCollapsed end
      if visible then n = n + 1; if n == i then return e end end
    end
  end,
  GetQuestObjectives = function(id)
    for _, e in ipairs(LOG) do if e.questID == id then return e.objectives or {} end end
  end,
  IsOnQuest = function(id) for _, e in ipairs(LOG) do if e.questID == id then return true end end return false end,
  IsQuestFlaggedCompleted = function(id) return COMPLETED[id] or false end,
}
function GetQuestLogSpecialItemInfo(i) local e = C_QuestLog.GetInfo(i); if e and e.special then return LINK(e.special) end end
function GetQuestLogQuestText(i) local e = C_QuestLog.GetInfo(i); if e then return e.desc or "", e.objText or "" end end

-- Modern tooltips: GameTooltip has no OnTooltipSetItem script on Forever.
TOOLTIP_CALLS = {}
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TOOLTIP_CALLS[kind] = fn end }
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
function GameTooltip:AddLine(s) self.lines = self.lines or {}; table.insert(self.lines, s) end
function HOVER(id) GameTooltip.lines = {}; TOOLTIP_CALLS[0](GameTooltip, { id = id }); return GameTooltip.lines[1] end

-- Modern bag frames: combined bags plus one per bag, buttons from EnumerateValidItems.
local function bagFrame(name, bags)
  local f = CreateFrame("Frame", name)
  f.buttons = {}
  for _, bag in ipairs(bags) do
    for slot = 1, SIZES[bag] do
      local b = CreateFrame("ItemButton")
      b.id = slot; b.bag = bag
      function b:GetBagID() return self.bag end
      f.buttons[#f.buttons+1] = b
    end
  end
  function f:EnumerateValidItems() local i = 0 return function() i = i + 1; if f.buttons[i] then return i, f.buttons[i] end end end
  function f:UpdateItems() end
  return f
end
bagFrame("ContainerFrameCombinedBags", { 0, 1, 2 })
for i = 1, 13 do bagFrame("ContainerFrame" .. i, {}) end
function BUTTON(frame, bag, slot)
  for _, b in ipairs(_G[frame].buttons) do if b.bag == bag and b.id == slot then return b end end
end
function MARKED(frame, bag, slot)
  local b = BUTTON(frame, bag, slot); return b.QuestKingMark ~= nil and b.QuestKingMark.shown == true
end
