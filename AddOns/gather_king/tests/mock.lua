-- Minimal WoW API stubs to exercise the addon's logic outside the game.
local out = {}
_G.OUTPUT = out
function print(...) local t = {} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end out[#out+1]=table.concat(t," ") end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out+1] = m end }
function CopyTable(t) local r = {} for k,v in pairs(t) do r[k]=v end return r end
NOW = 1000
function time() return NOW end
function GetTime() return 10 end
function IsShiftKeyDown() return false end
SlashCmdList = {}
PLAYER = { map = 1423, x = 0.4531, y = 0.6210 }
C_Map = {
  GetBestMapForUnit = function() return PLAYER.map end,
  GetPlayerMapPosition = function() return { GetXY = function() return PLAYER.x, PLAYER.y end } end,
  GetMapInfo = function(id) return { name = "Eastern Plaguelands" } end,
}
C_Item = { GetItemIconByID = function(id) return 100000 + id end }
C_Spell = { GetSpellName = function(id) return ({[2575]="Mining",[2366]="Herb Gathering",[7620]="Fishing"})[id] end }
LOOT = {}
function GetNumLootItems() return #LOOT end
function GetLootSlotLink(i) return LOOT[i] end
-- Forever's client has the modern auction house only.
UNKNOWN_EVENTS = { AUCTION_ITEM_LIST_UPDATE = true }
local frames = {}
_G.FRAMES = frames
FONTS = {}
local function tex()
  local t = setmetatable({}, {__index=function(t,k) if k:match("^%u") then return function() end end end})
  t.SetText = function(self, s) self.text = s end
  FONTS[#FONTS+1] = t
  return t
end
function CreateFrame()
  local f = { scripts = {}, events = {} }
  setmetatable(f, {__index=function(t,k) if k:match("^%u") then return function() end end end})
  f.SetScript = function(self, k, fn) self.scripts[k] = fn end
  f.RegisterEvent = function(self, e)
    if UNKNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end
    self.events[e] = true
  end
  f.RegisterUnitEvent = f.RegisterEvent
  f.CreateTexture = function() return tex() end
  f.CreateMaskTexture = function() return tex() end
  f.CreateFontString = function() return tex() end
  f.SetText = function(self, t) self.text = t end
  f.GetChecked = function() return false end
  f.SetPoint = function() end
  f.SetAlpha = function(self, a) self.alpha = a end
  f.EnableMouse = function(self, v) self.mouse = v end
  f.GetWidth = function() return 140 end
  f.GetCenter = function() return 0, 0 end
  f.GetEffectiveScale = function() return 1 end
  frames[#frames+1] = f
  return f
end
GameTooltip = tex()
PINS = { world = 0, mini = 0 }
local hbdp = {
  AddWorldMapIconMap = function() PINS.world = PINS.world + 1 return true end,
  AddMinimapIconMap = function() PINS.mini = PINS.mini + 1 return true end,
  RemoveAllWorldMapIcons = function() PINS.world = 0 end,
  RemoveAllMinimapIcons = function() PINS.mini = 0 end,
  GetVectorToIcon = function(self, icon) return 0, DIST end,
}
function LibStub(name) return hbdp end
function FIRE(event, ...)
  for _, f in ipairs(frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end

SHIFT = false
function IsShiftKeyDown() return SHIFT end
MENU = nil
MenuUtil = { CreateContextMenu = function(owner, gen)
  local items = {}
  local root = { CreateTitle = function() end, CreateButton = function(_, text, fn) items[#items+1] = { text = text, fn = fn } end }
  gen(owner, root)
  MENU = items
end }

YES, NO = "Yes", "No"
StaticPopupDialogs = {}
function StaticPopup_Show(name, text, _, data) POPUP = text; StaticPopupDialogs[name].OnAccept(nil, data) end
SETTINGS_OPENED = false
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end } end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() SETTINGS_OPENED = true end,
}

TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS+1] = fn end }
function RUN_TIMERS() local n = 0 while #TIMERS > 0 and n < 10000 do local fn = table.remove(TIMERS, 1) fn() n = n + 1 end end
IN_GUILD = true
function IsInGuild() return IN_GUILD end
function UnitName() return "Jay" end
function Ambiguate(s) return (s:gsub("%-.*$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SENT = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text, chan, target) SENT[#SENT+1] = { prefix = prefix, text = text, chan = chan, target = target } end,
}

DIST = 100
C_Timer.NewTicker = function() end
Minimap = CreateFrame("Frame")
function GetCursorPosition() return 10, 10 end

LOOTINFO = {}
function GetLootSlotInfo(i) local e = LOOTINFO[i] or {} return nil, e[1], e[3] or 1, nil, e[2] end

Enum = { AuctionHouseSortOrder = { Price = 0 } }
AuctionHouseFrame = CreateFrame("Frame")
AH_OPEN = true
AuctionHouseFrame.IsShown = function() return AH_OPEN end
AuctionHouseFrame.CreateFontString = function() return CreateFrame("Frame") end
AH_PRICES = {}
AH_QUERIES = 0
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return true end,
  MakeItemKey = function(id) return { itemID = id } end,
  SendSearchQuery = function(key)
    AH_QUERIES = AH_QUERIES + 1
    AH_ASKED = AH_ASKED or {}; AH_ASKED[key.itemID] = true
    C_Timer.After(0.2, function() FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID) end)
  end,
  GetCommoditySearchResultInfo = function(id, i) local p = AH_PRICES[id] if p then return { unitPrice = p } end end,
}

FISHING = false
function IsFishingLoot() return FISHING end
