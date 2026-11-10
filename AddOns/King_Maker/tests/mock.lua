-- wow_mock.lua: a stand-in for the WoW "Forever" client (Mainline API: modern auction
-- house, bags, tooltips, Settings, MenuUtil) good enough to load the King addons headlessly.
-- Union of the per-addon tests/mock.lua variants, reconciled. Everything a test can poke
-- or inspect is an UPPERCASE global (OUTPUT, FRAMES, FONTS, SENT, TIMERS, PINS, MENU, POPUP, ...).

---------------------------------------------------------------- Lua shorthands WoW provides
format, tinsert, tremove = string.format, table.insert, table.remove
floor, ceil, abs, max, min, random = math.floor, math.ceil, math.abs, math.max, math.min, math.random
strlower, strupper, strsub, strlen, strrep, strfind, strmatch = string.lower, string.upper, string.sub, string.len, string.rep, string.find, string.match
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local r = {} for k, v in pairs(t) do r[k] = type(v) == "table" and CopyTable(v) or v end return r end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strsplit(sep, s, n)
  local t = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = part end
  if n and #t > n then local rest = table.concat(t, sep, n) for i = #t, n, -1 do t[i] = nil end t[n] = rest end
  return unpack(t)
end
function tostringall(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return unpack(t) end
function Ambiguate(s) return (s:gsub("%-.*$", "")) end
function SecondsToTime(s) return format("%d min", floor(s / 60)) end
function Mixin(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGB = function(c) return c.r, c.g, c.b end } end
function seterrorhandler() end
function geterrorhandler() return error end

---------------------------------------------------------------- chat output
OUTPUT = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end OUTPUT[#OUTPUT + 1] = table.concat(t, " ") end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) OUTPUT[#OUTPUT + 1] = m end }
ChatFrame1 = DEFAULT_CHAT_FRAME
CHAT = {}
function SendChatMessage(msg, chan, lang, target) CHAT[#CHAT + 1] = { text = msg, chan = chan, target = target } end
function LAST() return OUTPUT[#OUTPUT] end

---------------------------------------------------------------- time
NOW = 1000          -- epoch seconds: time(), GetServerTime(), date()
UPTIME = 10         -- seconds since "client start": GetTime()
function time() return NOW end
function GetServerTime() return NOW end
function GetTime() return UPTIME end
date = os.date
TIMERS, TICKERS = {}, {}
C_Timer = {
  After = function(d, fn) TIMERS[#TIMERS + 1] = fn end,            -- FIFO; the delay is ignored
  NewTicker = function(d, fn, n)
    local t = { d = d, fn = fn, left = d, n = n, cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    TICKERS[#TICKERS + 1] = t return t
  end,
}
C_Timer.NewTimer = function(d, fn) local t = { cancelled = false, Cancel = function(s) s.cancelled = true end }
  TIMERS[#TIMERS + 1] = function() if not t.cancelled then fn(t) end end return t end
-- Runs every C_Timer.After callback queued so far, including ones queued while running (capped).
function RUN_TIMERS() local n = 0 while #TIMERS > 0 and n < 10000 do local fn = table.remove(TIMERS, 1) fn() n = n + 1 end end
-- Advances both clocks a second at a time, firing tickers that come due and OnUpdate scripts.
function ADVANCE(sec)
  for _ = 1, sec do
    NOW, UPTIME = NOW + 1, UPTIME + 1
    for i = #TICKERS, 1, -1 do
      local t = TICKERS[i]
      if t.cancelled then table.remove(TICKERS, i)
      else t.left = t.left - 1 if t.left <= 0 then t.fn(t) t.left = t.d if t.n then t.n = t.n - 1 if t.n <= 0 then t:Cancel() end end end end
    end
    RUN_ONUPDATE(1)
  end
end

---------------------------------------------------------------- the stub metatable
-- Any missing key that starts with an uppercase letter reads as a no-op function returning nil,
-- so unknown widget methods (SetBackdrop, SetJustifyH, ...) are harmless. Pitfalls: a capitalised
-- DATA field an addon stashes on a frame (f.QuestKingMark, f.Icon) reads as a function instead of
-- nil until it's assigned, and Get*/Is* calls return nil, not 0/false. STUB_IGNORE lists prefixes
-- that must read as nil instead.
STUB_IGNORE = { "^QuestKing", "^Mark$" }
local NOOP = function() end
local function stub(t)
  return setmetatable(t or {}, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then
      for _, p in ipairs(STUB_IGNORE) do if k:match(p) then return nil end end
      return NOOP
    end
  end })
end
STUB = stub

---------------------------------------------------------------- events the client doesn't know
-- RegisterEvent on these errors, like the real client. Addons must guard with C_EventUtils.
UNKNOWN_EVENTS = { AUCTION_ITEM_LIST_UPDATE = true, QUEST_WATCH_UPDATE = true, ITEM_LOCK_CHANGED_CLASSIC = true,
  COMBAT_LOG_EVENT_UNFILTERED = true }
C_EventUtils = { IsEventValid = function(e) return not UNKNOWN_EVENTS[e] end }
FORBIDDEN = {}
function CombatLogGetCurrentEventInfo() FORBIDDEN[#FORBIDDEN + 1] = "CombatLogGetCurrentEventInfo" end

---------------------------------------------------------------- frames
FRAMES, FONTS, TEXTURES = {}, {}, {}
LINES = 0
local KNOWN_SCRIPTS = {}
for _, s in ipairs({ "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnClick", "OnDoubleClick", "OnEnter", "OnLeave", "OnMouseDown",
  "OnMouseUp", "OnMouseWheel", "OnDragStart", "OnDragStop", "OnReceiveDrag", "OnTextChanged", "OnEnterPressed", "OnEscapePressed",
  "OnEditFocusLost", "OnEditFocusGained", "OnValueChanged", "OnSizeChanged", "OnKeyDown", "OnKeyUp", "OnLoad", "OnChar",
  "OnTabPressed", "OnSpacePressed", "OnAttributeChanged", "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave" }) do KNOWN_SCRIPTS[s] = true end
-- no OnTooltipSetItem: Forever's GameTooltip uses TooltipDataProcessor instead

local function region(kind)
  local r = stub({ kind = kind, shown = true, alpha = 1 })
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetShown(v) self.shown = not not v end
  function r:IsShown() return self.shown ~= false end
  function r:IsVisible() return self.shown ~= false end
  function r:SetAlpha(a) self.alpha = a end
  function r:GetAlpha() return self.alpha or 1 end
  function r:SetPoint(p, rel, rp, x, y) self.point = { p, rel, rp, x or 0, y or 0 }; self.points = self.points or {}; table.insert(self.points, self.point) end
  function r:ClearAllPoints() self.points = {} end
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetWidth() return self.w or 0 end
  function r:GetHeight() return self.h or 0 end
  function r:GetSize() return self.w or 0, self.h or 0 end
  function r:GetObjectType() return self.kind end
  function r:IsObjectType(k) return self.kind == k end
  function r:GetParent() return self.parent end
  return r
end
local function texture(kind)
  local t = region(kind or "Texture")
  function t:SetTexture(p) self.texture = p; self.tex = p end
  function t:GetTexture() return self.texture end
  function t:SetAtlas(a) self.atlas = a end
  function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
  function t:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
  function t:SetTexCoord(...) self.coords = { ... } end
  TEXTURES[#TEXTURES + 1] = t
  return t
end
local function fontstring()
  local t = region("FontString")
  function t:SetText(s) self.text = s end
  function t:GetText() return self.text end
  function t:SetFormattedText(f, ...) self.text = format(f, ...) end
  function t:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
  function t:SetFont(f, size, flags) self.font = { f, size, flags } end
  function t:GetFont() if self.font then return unpack(self.font) end return "Fonts\\FRIZQT__.TTF", 12, "" end
  function t:SetFontObject(o) self.fontObject = o end
  function t:GetStringWidth() return #(tostring(self.text or "")) * 6 end
  function t:GetStringHeight() return 12 end
  function t:SetJustifyH(j) self.justifyH = j end
  function t:SetJustifyV(j) self.justifyV = j end
  FONTS[#FONTS + 1] = t
  return t
end
function CreateFrame(kind, name, parent, template)
  local f = region(kind or "Frame")
  f.shown = nil  -- nil = never explicitly shown or hidden; IsShown() is still true, like a fresh WoW frame
  f.name, f.template, f.scripts, f.hooks, f.events, f.children, f.points = name, template, {}, {}, {}, {}, {}
  f.w, f.h = 140, 140
  function f:GetName() return self.name end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:HasScript(k) return KNOWN_SCRIPTS[k] or false end
  function f:HookScript(k, fn)
    if not KNOWN_SCRIPTS[k] then error((self.name or "Frame") .. " doesn't have a \"" .. k .. "\" script") end
    self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn)
  end
  function f:RunScript(k, ...)
    if self.scripts[k] then self.scripts[k](self, ...) end
    for _, h in ipairs(self.hooks[k] or {}) do h(self, ...) end
  end
  function f:RegisterEvent(e)
    if UNKNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end
    self.events[e] = true
  end
  f.RegisterUnitEvent = f.RegisterEvent
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:UnregisterAllEvents() wipe(self.events) end
  function f:IsEventRegistered(e) return self.events[e] or false end
  function f:Show() local was = self.shown ~= false; self.shown = true; if not was then self:RunScript("OnShow") end end
  function f:Hide() local was = self.shown ~= false; self.shown = false; if was then self:RunScript("OnHide") end end
  function f:SetShown(v) if v then self:Show() else self:Hide() end end
  function f:SetParent(p)
    if self.parent then for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end end
    self.parent = p; if p then table.insert(p.children, self) end
  end
  function f:GetChildren() return unpack(self.children) end
  function f:GetNumChildren() return #self.children end
  function f:GetRegions() return end
  function f:SetPoint(...) table.insert(self.points, { ... }) self.point = self.points[#self.points] end
  function f:GetNumPoints() return #self.points end
  function f:GetPoint(i) return unpack(self.points[i or 1] or {}) end
  function f:GetCenter() return self.cx or 0, self.cy or 0 end
  function f:GetLeft() return self.cx or 0 end
  function f:GetTop() return self.cy or 0 end
  function f:GetEffectiveScale() return 1 end
  function f:GetScale() return 1 end
  function f:GetFrameStrata() return self.strata or "MEDIUM" end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameLevel() return self.level or 1 end
  function f:SetFrameLevel(l) self.level = l end
  function f:EnableMouse(v) self.mouse = v end
  function f:IsMouseEnabled() return self.mouse or false end
  function f:RegisterForDrag(...) self.drag = select("#", ...) > 0 end
  function f:RegisterForClicks(...) self.clicks = { ... } end
  function f:SetID(id) self.id = id end
  function f:GetID() return self.id or 0 end
  function f:SetEnabled(v) self.enabled = v end
  function f:Enable() self.enabled = true end
  function f:Disable() self.enabled = false end
  function f:IsEnabled() return self.enabled ~= false end
  function f:Click(which) self:RunScript("OnClick", which or "LeftButton", false) end
  -- text (Button labels, EditBoxes): f.text, mirrored into the button's own font string (f._fs;
  -- addons use f.label for their own data, so the mock must not)
  function f:SetText(s) self.text = s; if self._fs then self._fs.text = s end end
  function f:GetText() return self.text or "" end
  function f:GetNumber() return tonumber(self.text) or 0 end
  function f:GetFontString() self._fs = self._fs or fontstring(); self._fs.text = self.text; return self._fs end
  function f:SetFormattedText(fmt, ...) self:SetText(format(fmt, ...)) end
  -- CheckButton
  function f:GetChecked() return self.checked or false end
  function f:SetChecked(v) self.checked = not not v end
  -- Slider / StatusBar / ScrollFrame
  function f:SetMinMaxValues(a, b) self.minv, self.maxv = a, b end
  function f:GetMinMaxValues() return self.minv or 0, self.maxv or 1 end
  function f:SetValue(v) self.value = v end
  function f:GetValue() return self.value or 0 end
  function f:SetVerticalScroll(v) self.scroll = v end
  function f:GetVerticalScroll() return self.scroll or 0 end
  function f:GetVerticalScrollRange() return self.scrollRange or 0 end
  function f:SetScrollChild(c) self.scrollChild = c end
  function f:GetScrollChild() return self.scrollChild end
  -- children regions
  function f:CreateTexture(n, layer) local t = texture("Texture"); t.name, t.parent = n, self; if n then _G[n] = t end return t end
  function f:CreateMaskTexture() local t = texture("MaskTexture"); t.parent = self return t end
  function f:CreateLine() LINES = LINES + 1 local t = texture("Line"); t.parent = self return t end
  function f:CreateFontString(n) local t = fontstring(); t.name, t.parent = n, self; if n then _G[n] = t end return t end
  if parent then f:SetParent(parent) end
  if name then _G[name] = f end
  FRAMES[#FRAMES + 1] = f
  return f
end
function FIRE(event, ...)
  for _, f in ipairs(FRAMES) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end
function RUN_ONUPDATE(elapsed)
  for _, f in ipairs(FRAMES) do if f.scripts.OnUpdate and f.shown ~= false then f.scripts.OnUpdate(f, elapsed or 1) end end
end
-- Finders for tests: by button/frame text, by field, by name.
function FRAME_WITH(text) for _, f in ipairs(FRAMES) do if f.text == text then return f end end end
function FRAMES_WITH(text) local r = {} for _, f in ipairs(FRAMES) do if f.text == text then r[#r + 1] = f end end return r end
function FRAME_WHERE(field, value) for _, f in ipairs(FRAMES) do if f[field] == value then return f end end end
function TEXTS() local r = {} for _, t in ipairs(FONTS) do if t.text then r[#r + 1] = t.text end end
  for _, f in ipairs(FRAMES) do if f.text and f.shown ~= false then r[#r + 1] = f.text end end return r end

UIParent = CreateFrame("Frame", "UIParent"); UIParent:SetSize(1024, 768)
WorldFrame = CreateFrame("Frame", "WorldFrame"); WorldFrame:SetSize(1024, 768)
Minimap = CreateFrame("Minimap", "Minimap"); Minimap:SetSize(140, 140)
MinimapCluster = CreateFrame("Frame", "MinimapCluster")
MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)
UISpecialFrames = {}
ATTACHMENTS_MAX_RECEIVE, ATTACHMENTS_MAX_SEND = 16, 12
function GetScreenWidth() return 1024 end
function GetScreenHeight() return 768 end
function GetCursorPosition() return 10, 10 end
SHIFT, CTRL, ALT = false, false, false
function IsShiftKeyDown() return SHIFT end
function IsControlKeyDown() return CTRL end
function IsAltKeyDown() return ALT end
function IsMouseButtonDown() return false end
FOCUS = nil
function GetMouseFoci() return { FOCUS } end
function GetMouseFocus() return FOCUS end
function InCombatLockdown() return false end
function PlaySound() end
function PlaySoundFile() end
FILE_IDS = {}
function GetFileIDFromPath(p) return FILE_IDS[p] end
CVARS = {}
function GetCVar(k) return CVARS[k] end
function GetCVarBool(k) return CVARS[k] == "1" or CVARS[k] == true end
function SetCVar(k, v) CVARS[k] = v end
C_CVar = { GetCVar = GetCVar, GetCVarBool = GetCVarBool, SetCVar = SetCVar }
local function fontObject(size) return { GetFont = function() return "Fonts\\FRIZQT__.TTF", size, "" end, GetTextColor = function() return 1, 1, 1 end } end
for name, size in pairs({ GameFontNormal = 12, GameFontNormalSmall = 10, GameFontNormalLarge = 16, GameFontNormalHuge = 20,
  GameFontHighlight = 12, GameFontHighlightSmall = 10, GameFontHighlightLarge = 16, GameFontDisable = 12, GameFontDisableSmall = 10,
  GameFontGreen = 12, GameFontRed = 12, GameFontWhite = 12, NumberFontNormal = 12, ChatFontNormal = 12, GameTooltipText = 12 }) do _G[name] = fontObject(size) end
YES, NO, OKAY, CANCEL, ACCEPT, CLOSE = "Yes", "No", "Okay", "Cancel", "Accept", "Close"
RAID_CLASS_COLORS = {}
for class, c in pairs({ WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1, 0.96, 0.41 },
  PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
  DEATHKNIGHT = { 0.77, 0.12, 0.23 }, MONK = { 0, 1, 0.6 }, DEMONHUNTER = { 0.64, 0.19, 0.79 }, EVOKER = { 0.2, 0.58, 0.5 } }) do
  RAID_CLASS_COLORS[class] = { r = c[1], g = c[2], b = c[3], colorStr = "ffffffff", GetRGB = function(s) return s.r, s.g, s.b end }
end
ITEM_QUALITY_COLORS = {}
for q, c in pairs({ [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }) do
  ITEM_QUALITY_COLORS[q] = { r = c[1], g = c[2], b = c[3], hex = "|cffffffff" }
end

---------------------------------------------------------------- slash commands
SlashCmdList = {}
-- SLASH("/gt mine thorium") finds the SLASH_X1.. global holding "/gt" and calls SlashCmdList.X("mine thorium").
function SLASH(line)
  local cmd, rest = line:match("^(%S+)%s*(.-)$")
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "string" and k:match("^SLASH_") and v:lower() == cmd:lower() then
      local key = k:match("^SLASH_(.-)%d+$")
      if SlashCmdList[key] then return SlashCmdList[key](rest, DEFAULT_CHAT_FRAME.editBox) end
    end
  end
  error("no slash command " .. cmd)
end

---------------------------------------------------------------- addons
ADDON_META, LOADED_ADDONS = {}, {}   -- the runner fills these from each .toc
C_AddOns = {
  GetAddOnMetadata = function(name, field) local m = ADDON_META[name]; return m and (m[field] or m[field:lower()]) end,
  IsAddOnLoaded = function(name) return LOADED_ADDONS[name] or false end,
  GetNumAddOns = function() local n = 0 for _ in pairs(ADDON_META) do n = n + 1 end return n end,
}
GetAddOnMetadata, IsAddOnLoaded = C_AddOns.GetAddOnMetadata, C_AddOns.IsAddOnLoaded
function GetBuildInfo() return "1.15.0", "60001", "Jan 1 2026", 16001 end
function GetLocale() return "enUS" end
function IsLoggedIn() return true end

---------------------------------------------------------------- the player, units, guild, group
PLAYER = { name = "Jay", realm = "Forever", class = "WARRIOR", classLocal = "Warrior", level = 42, faction = "Alliance",
  map = 1423, x = 0.4531, y = 0.6210, guid = "Player-1-AAA" }
GUIDS = { player = PLAYER.guid, pet = nil }
UNITS = {}            -- UNITS["target"] = { guid=, name=, level=, class=, dead=, tapDenied= }
THREAT = {}           -- THREAT[unit .. guid] = status
GROUP, IN_GUILD = false, true
function UnitName(u) if u == "player" or u == nil then return PLAYER.name, nil end return UNITS[u] and UNITS[u].name end
function UnitFullName(u) if u == "player" then return PLAYER.name, PLAYER.realm end return UnitName(u) end
function UnitClass(u) if u == "player" or u == nil then return PLAYER.classLocal, PLAYER.class end return UNITS[u] and UNITS[u].className, UNITS[u] and UNITS[u].class end
function UnitLevel(u) if u == "player" or u == nil then return PLAYER.level end return UNITS[u] and UNITS[u].level or 0 end
function UnitGUID(u) return GUIDS[u] or (UNITS[u] and UNITS[u].guid) end
function UnitExists(u) return u == "player" or UNITS[u] ~= nil end
function UnitIsPlayer(u) return u == "player" or (UNITS[u] and UNITS[u].isPlayer) or false end
function UnitIsUnit(a, b) return a == b end
function UnitCanAttack() return true end
function UnitClassification(u) return UNITS[u] and UNITS[u].classification or "normal" end
function UnitCreatureType(u) return UNITS[u] and UNITS[u].creatureType or "Beast" end
function UnitIsDead(u) return UNITS[u] and UNITS[u].dead or false end
function UnitIsDeadOrGhost(u) return UnitIsDead(u) end
function UnitIsTapDenied(u) return UNITS[u] and UNITS[u].tapDenied or false end
function UnitFactionGroup() return PLAYER.faction, PLAYER.faction end
function UnitRace() return "Human", "Human" end
function UnitThreatSituation(who, u) local g = UnitGUID(u); return g and THREAT[who .. g] end
function UnitHealth(u) return UNITS[u] and UNITS[u].dead and 0 or 100 end
function UnitHealthMax() return 100 end
function IsInGroup() return GROUP end
function IsInRaid() return false end
function GetNumGroupMembers() return GROUP and 5 or 0 end
function IsInGuild() return IN_GUILD end
function GetGuildInfo(u) if IN_GUILD then return "Kings", "Member", 1, PLAYER.realm end end
function GetNumGuildMembers() return IN_GUILD and 10 or 0 end
function GetRealmName() return PLAYER.realm end
function GetNormalizedRealmName() return PLAYER.realm end
MONEY = 1234567
function GetMoney() return MONEY end

---------------------------------------------------------------- map and position
MAPS = { [1423] = "Eastern Plaguelands", [1429] = "Elwynn Forest", [1436] = "Westfall", [1440] = "Ashenvale", [1451] = "Silithus",
  [1453] = "Stormwind City", [1454] = "Orgrimmar", [1458] = "Undercity", [1420] = "Tirisfal Glades", [1413] = "The Barrens" }
MAP_CHILDREN = {}   -- MAP_CHILDREN[rootMapID] = { { mapID=, name= }, ... }
WAYPOINT, TRACKED = nil, nil
C_Map = {
  GetBestMapForUnit = function() return PLAYER.map end,
  GetPlayerMapPosition = function() if not PLAYER.x then return nil end return { GetXY = function() return PLAYER.x, PLAYER.y end, x = PLAYER.x, y = PLAYER.y } end,
  GetMapInfo = function(id) return { mapID = id, name = MAPS[id] or ("Map " .. tostring(id)), mapType = 3, parentMapID = 0 } end,
  GetMapChildrenInfo = function(root) return MAP_CHILDREN[root] or {} end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) WAYPOINT = p end,
  GetUserWaypoint = function() return WAYPOINT end,
  ClearUserWaypoint = function() WAYPOINT = nil end,
  HasUserWaypoint = function() return WAYPOINT ~= nil end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, m = m, x = x, y = y, position = { x = x, y = y } } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) TRACKED = v end, IsSuperTrackingUserWaypoint = function() return TRACKED or false end }
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame")
function WorldMapFrame:GetMapID() return PLAYER.map end
function WorldMapFrame:OnMapChanged() end
function WorldMapFrame:OnCanvasScaleChanged() end
CANVAS = CreateFrame("Frame", "WorldMapCanvas"); CANVAS:SetSize(1000, 700)
function WorldMapFrame:GetCanvas() return CANVAS end
function WorldMapFrame:GetCanvasScale() return 1 end
WorldMapFrame.ScrollContainer = CANVAS

-- HereBeDragons-Pins: pins kept per icon frame; PINS.world/PINS.mini count them.
PINS = { world = 0, mini = 0 }
MINI, WORLD = {}, {}
DIST = 100
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function recount() PINS.world, PINS.mini = count(WORLD), count(MINI) end
function NMINI() return count(MINI) end
function NWORLD() return count(WORLD) end
local hbdPins = {
  AddMinimapIconMap = function(_, ref, f, map, x, y, parent, edge) MINI[f] = { ref = ref, map = map, x = x, y = y, edge = edge }; recount() return true end,
  AddWorldMapIconMap = function(_, ref, f, map, x, y, flag) WORLD[f] = { ref = ref, map = map, x = x, y = y, flag = flag }; f.cx, f.cy = x * 1000, (1 - y) * 1000; recount() return true end,
  RemoveMinimapIcon = function(_, ref, f) MINI[f] = nil; recount() end,
  RemoveWorldMapIcon = function(_, ref, f) WORLD[f] = nil; recount() end,
  RemoveAllMinimapIcons = function() wipe(MINI); recount() end,
  RemoveAllWorldMapIcons = function() wipe(WORLD); recount() end,
  GetVectorToIcon = function(_, f) return 0, DIST end,
  IsMinimapIconShown = function(_, f) return MINI[f] ~= nil end,
  SetMinimapObject = function() end,
}
local hbd = {
  GetPlayerZonePosition = function() return PLAYER.x, PLAYER.y, PLAYER.map end,
  GetPlayerWorldPosition = function() return (PLAYER.x or 0) * 1000, (PLAYER.y or 0) * 1000, 0 end,
  GetPlayerZone = function() return PLAYER.map end,
  GetWorldDistance = function() return DIST, 0, 0 end,
  GetZoneDistance = function() return DIST, 0, 0 end,
  GetZoneSize = function() return 1000, 1000 end,
  RegisterCallback = function() end,
}
LIBS = { ["HereBeDragons-Pins-2.0"] = hbdPins, ["HereBeDragons-2.0"] = hbd }
function LibStub(name, silent)
  if LIBS[name] then return LIBS[name] end
  if not silent then error("Cannot find a library instance of \"" .. tostring(name) .. "\"") end
end

---------------------------------------------------------------- items
-- ITEMS[id] = { name=, quality=, ilvl=, sell=, class=, subclass=, bind=, icon=, stack=, equipLoc= }
ITEMS = {}
function ITEM(id, name, t) t = t or {}; t.name = name; ITEMS[id] = t; return t end
ITEM_CLASSES = { [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor", [5] = "Reagent", [7] = "Trade Goods",
  [8] = "Item Enhancement", [9] = "Recipe", [12] = "Quest", [13] = "Key", [15] = "Miscellaneous", [16] = "Glyph", [17] = "Battle Pets" }
ITEM_SUBCLASSES = { ["7:5"] = "Cloth", ["7:6"] = "Leather", ["7:7"] = "Metal & Stone", ["7:8"] = "Cooking", ["7:9"] = "Herb",
  ["7:10"] = "Elemental", ["7:11"] = "Other", ["7:12"] = "Enchanting", ["2:7"] = "One-Handed Swords", ["4:1"] = "Cloth", ["4:2"] = "Leather",
  ["4:3"] = "Mail", ["4:4"] = "Plate", ["0:1"] = "Potion", ["0:5"] = "Food & Drink", ["15:0"] = "Junk", ["15:4"] = "Other", ["12:0"] = "Quest" }
function LINK(id) local i = ITEMS[id]; return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. (i and i.name or ("item:" .. id)) .. "]|h|r" end
local function itemId(x)
  if type(x) == "number" then return x end
  if type(x) == "string" then local id = x:match("item:(%d+)"); if id then return tonumber(id) end
    for i, it in pairs(ITEMS) do if it.name == x then return i end end return nil end
  if type(x) == "table" then return x.id or x.itemID end
end
C_Item = {
  GetItemInfo = function(x)
    local id = itemId(x); local i = id and ITEMS[id]; if not i then return nil end
    local c, s = i.class or 15, i.subclass or 0
    return i.name, LINK(id), i.quality or 1, i.ilvl or 1, i.reqLevel or 1, ITEM_CLASSES[c] or "", ITEM_SUBCLASSES[c .. ":" .. s] or "",
      i.stack or 20, i.equipLoc or "", i.icon or (100000 + id), i.sell or 0, c, s, i.bind or 0, 0, 0, false
  end,
  GetItemInfoInstant = function(x)
    local id = itemId(x); local i = id and ITEMS[id]; if not i then return nil end
    local c, s = i.class or 15, i.subclass or 0
    return id, ITEM_CLASSES[c] or "", ITEM_SUBCLASSES[c .. ":" .. s] or "", i.equipLoc or "", i.icon or (100000 + id), c, s
  end,
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id].name end,
  GetItemIconByID = function(id) return (ITEMS[id] and ITEMS[id].icon) or 100000 + id end,
  GetItemQualityByID = function(id) return ITEMS[id] and (ITEMS[id].quality or 1) end,
  GetItemClassInfo = function(c) return ITEM_CLASSES[c] end,
  GetItemSubClassInfo = function(c, s) return ITEM_SUBCLASSES[c .. ":" .. s] end,
  GetItemID = function(loc) return loc.id or loc.itemID end,
  GetItemName = function(loc) local id = loc.id or loc.itemID; return ITEMS[id] and ITEMS[id].name end,
  GetItemLink = function(loc) return LINK(loc.id or loc.itemID) end,
  IsItemDataCachedByID = function(id) return ITEMS[id] ~= nil end,
  RequestLoadItemDataByID = function(id) REQUESTED = id end,
  DoesItemExistByID = function(id) return ITEMS[id] ~= nil end,
}
SPELLS = { [2575] = "Mining", [2366] = "Herb Gathering", [7620] = "Fishing", [8613] = "Skinning", [8617] = "Skinning", [8618] = "Skinning", [10768] = "Skinning" }
C_Spell = {
  GetSpellName = function(id) return SPELLS[id] end,
  GetSpellInfo = function(id) if SPELLS[id] then return { name = SPELLS[id], spellID = id, iconID = 1 } end end,
}

---------------------------------------------------------------- bags and bag frames
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_CONTAINER_FRAMES = 4, 5, 13
Enum = Enum or {}
Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Bank = -1, Keyring = -2,
  CharacterBankTab_1 = 6, AccountBankTab_1 = 12 }
-- BAGS[bag][slot] = { id=, count=, bound=, quest = { isQuestItem=, questID=, isActive= } }; SIZES[bag] = slots
BAGS = { [-1] = {}, [0] = {}, {}, {}, {}, {}, {} }
SIZES = { [-1] = 28, [0] = 16, 10, 10, 0, 0, 0 }
C_Container = {
  GetContainerNumSlots = function(bag) return SIZES[bag] or (BAGS[bag] and #BAGS[bag]) or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local e = BAGS[bag] and BAGS[bag][slot]
    if e then return { itemID = e.id, hyperlink = LINK(e.id), stackCount = e.count or 1, iconFileID = 1, isBound = e.bound or false,
      quality = ITEMS[e.id] and ITEMS[e.id].quality or 1, isLocked = false, hasLoot = false, isReadable = false, isFiltered = false, hasNoValue = false } end
  end,
  GetContainerItemQuestInfo = function(bag, slot)
    local e = BAGS[bag] and BAGS[bag][slot]
    local q = e and e.quest or {}
    return { isQuestItem = q.isQuestItem or false, questID = q.questID, isActive = q.isActive or false }
  end,
  GetContainerItemID = function(bag, slot) local e = BAGS[bag] and BAGS[bag][slot]; return e and e.id end,
  GetContainerItemLink = function(bag, slot) local e = BAGS[bag] and BAGS[bag][slot]; return e and LINK(e.id) end,
  GetContainerNumFreeSlots = function(bag) local n = SIZES[bag] or 0 for _ in pairs(BAGS[bag] or {}) do n = n - 1 end return n, 0 end,
  PickupContainerItem = function() end,
  UseContainerItem = function() end,
}
-- Modern bag frames: combined bags plus one per bag, buttons from EnumerateValidItems.
local function bagFrame(name, bags)
  local f = CreateFrame("Frame", name)
  f.buttons = {}
  for _, bag in ipairs(bags) do
    for slot = 1, SIZES[bag] or 0 do
      local b = CreateFrame("ItemButton", name .. "Item" .. slot, f)
      b.id, b.bag = slot, bag
      function b:GetBagID() return self.bag end
      f.buttons[#f.buttons + 1] = b
    end
  end
  function f:EnumerateValidItems() local i = 0 return function() i = i + 1; if f.buttons[i] then return i, f.buttons[i] end end end
  function f:UpdateItems() end
  return f
end
bagFrame("ContainerFrameCombinedBags", { 0, 1, 2, 3, 4 })
for i = 1, NUM_CONTAINER_FRAMES do bagFrame("ContainerFrame" .. i, {}) end
function BUTTON(frame, bag, slot) for _, b in ipairs(_G[frame].buttons) do if b.bag == bag and b.id == slot then return b end end end
function MARKED(frame, bag, slot, field)
  local b = BUTTON(frame, bag, slot); local m = b and rawget(b, field or "QuestKingMark")
  return m ~= nil and m.shown == true
end

---------------------------------------------------------------- quest log
-- LOG = ordered entries { questID=, title=, isHeader=, isCollapsed=, objectives = { { text=, type= } }, desc=, objText=, special= }
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
  GetLogIndexForQuestID = function(id)
    local n, hidden = 0, false
    for _, e in ipairs(LOG) do
      local visible = e.isHeader or not hidden
      if e.isHeader then hidden = e.isCollapsed end
      if visible then n = n + 1; if e.questID == id then return n end end
    end
  end,
  GetQuestObjectives = function(id) for _, e in ipairs(LOG) do if e.questID == id then return e.objectives or {} end end end,
  IsOnQuest = function(id) for _, e in ipairs(LOG) do if e.questID == id then return true end end return false end,
  IsQuestFlaggedCompleted = function(id) return COMPLETED[id] or false end,
  GetTitleForQuestID = function(id) for _, e in ipairs(LOG) do if e.questID == id then return e.title end end end,
  GetQuestInfo = function(id) for _, e in ipairs(LOG) do if e.questID == id then return e.title end end end,
}
function GetQuestLogSpecialItemInfo(i) local e = C_QuestLog.GetInfo(i); if e and e.special then return LINK(e.special) end end
function GetQuestLogQuestText(i) local e = C_QuestLog.GetInfo(i); if e then return e.desc or "", e.objText or "" end end

---------------------------------------------------------------- loot
-- LOOT[i] = link string (gather_king style) or { link=, name=, qty=, quality=, sources = { guid, qty, ... } , coin = true }
-- LOOTINFO[i] = { name, quality, qty } supplements string entries.
LOOT, LOOTINFO, FISHING = {}, {}, false
local function slot(i) local e = LOOT[i]; if type(e) == "string" then local x = LOOTINFO[i] or {} return { link = e, name = x[1], quality = x[2], qty = x[3] } end return e end
function GetNumLootItems() return #LOOT end
function GetLootSlotLink(i) local e = slot(i); return e and e.link end
function GetLootSlotInfo(i) local e = slot(i) or {} return nil, e.name or (e.link and "x") or "5 Silver", e.qty or 1, nil, e.quality or 1, false, e.quest or false end
function GetLootSlotType(i) local e = slot(i); return (e and e.link) and 1 or 2 end
function GetLootSourceInfo(i) local e = slot(i); if e and e.sources then return unpack(e.sources) end return PLAYER.guid, (e and e.qty) or 1 end
function IsFishingLoot() return FISHING end
function OPEN_LOOT(slots, info) LOOT, LOOTINFO = slots, info or {}; FIRE("LOOT_OPENED") end
function CLOSE_LOOT() FIRE("LOOT_CLOSED"); LOOT, LOOTINFO = {}, {} end
LOOTABLE = {}
function CanLootUnit(guid) return LOOTABLE[guid] or false end

---------------------------------------------------------------- tooltips
Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
TOOLTIP_CALLS = {}          -- TOOLTIP_CALLS[kind] = { fn, fn, ... } in registration order
TT_HOOK = nil               -- the last Item post-call registered (back-compat with the old suites)
TooltipDataProcessor = {
  AddTooltipPostCall = function(kind, fn) TOOLTIP_CALLS[kind] = TOOLTIP_CALLS[kind] or {}; table.insert(TOOLTIP_CALLS[kind], fn); if kind == 0 then TT_HOOK = fn end end,
}
local function tooltip(name)
  local tt = CreateFrame("GameTooltip", name)
  tt.lines = {}
  function tt:AddLine(s) self.lines[#self.lines + 1] = s end
  function tt:AddDoubleLine(l, r) self.lines[#self.lines + 1] = tostring(l) .. "|" .. tostring(r) end
  function tt:ClearLines() self.lines = {} end
  function tt:NumLines() return #self.lines end
  function tt:SetOwner(o, anchor) self.owner = o; self.anchor = anchor end
  function tt:GetOwner() return self.owner end
  function tt:IsOwned(o) return self.owner == o end
  function tt:SetHyperlink(l) self.link = l end
  function tt:SetItemByID(id) self.link = LINK(id) end
  function tt:GetItem() if self.link then local id = tonumber(self.link:match("item:(%d+)")); return ITEMS[id] and ITEMS[id].name, self.link, id end end
  return tt
end
GameTooltip = tooltip("GameTooltip")
ItemRefTooltip = tooltip("ItemRefTooltip")
ShoppingTooltip1, ShoppingTooltip2 = tooltip("ShoppingTooltip1"), tooltip("ShoppingTooltip2")
TIP = GameTooltip.lines
-- Runs every Item tooltip post-call on GameTooltip for one item; returns the lines added.
function HOVER(id)
  GameTooltip.lines = {}; GameTooltip.link = LINK(id); GameTooltip.skItem = nil
  for _, fn in ipairs(TOOLTIP_CALLS[0] or {}) do fn(GameTooltip, { id = id, type = 0 }) end
  return GameTooltip.lines[1], GameTooltip.lines
end

---------------------------------------------------------------- menus, popups, settings
MENU, MENU_OWNER, MENU_TITLE = nil, nil, nil   -- MENU = the buttons only, in order; the title goes to MENU_TITLE
MenuUtil = { CreateContextMenu = function(owner, gen)
  local items = {}
  local function root()
    local r = {}
    function r:CreateTitle(text) MENU_TITLE = text return r end
    function r:CreateDivider() return r end
    function r:CreateButton(text, fn, data) local it = { text = text, fn = function() return fn and fn(data) end, data = data } items[#items + 1] = it return it end
    function r:CreateCheckbox(text, isSel, set, data) local it = { text = text, checked = isSel and isSel(data), fn = function() return set and set(data) end } items[#items + 1] = it return it end
    function r:CreateRadio(text, isSel, set, data) local it = { text = text, selected = isSel and isSel(data), fn = function() return set and set(data) end } items[#items + 1] = it return it end
    return r
  end
  gen(owner, root())
  MENU, MENU_OWNER = items, owner
  return { Close = function() end }
end }
function MENU_ITEM(text) for _, it in ipairs(MENU or {}) do if it.text == text then return it end end end

StaticPopupDialogs = {}
POPUP, POPUPS, POPUP_AUTO_ACCEPT, POPUP_INPUT = nil, {}, true, ""
function StaticPopup_Show(name, a1, a2, data)
  local d = StaticPopupDialogs[name]; if not d then error("no StaticPopupDialogs." .. tostring(name)) end
  local text = d.text or ""; if text:find("%%") then text = format(text, a1, a2) end
  local dialog = { data = data, editBox = { GetText = function() return POPUP_INPUT end, SetText = function(_, s) POPUP_INPUT = s end, text = POPUP_INPUT }, which = name }
  POPUP = (type(a1) == "string" and a1) or text; POPUPS[#POPUPS + 1] = { name = name, text = text, arg1 = a1, arg2 = a2, data = data, dialog = dialog }
  if d.OnShow then d.OnShow(dialog, data) end
  if POPUP_AUTO_ACCEPT and d.OnAccept then d.OnAccept(dialog, data) end
  return dialog
end
function StaticPopup_Hide() end
function POPUP_CANCEL() local p = POPUPS[#POPUPS]; local d = p and StaticPopupDialogs[p.name]; if d and d.OnCancel then d.OnCancel(p.dialog, p.data) end end

SETTINGS, SETTINGS_OPENED = { panels = {} }, false
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name) SETTINGS.panels[name] = frame; SETTINGS.panel = frame return { GetID = function() return name end, ID = name, name = name } end,
  RegisterVerticalLayoutCategory = function(name) return { GetID = function() return name end, ID = name, name = name } end,
  RegisterAddOnCategory = function(cat) SETTINGS.registered = cat end,
  OpenToCategory = function(id) SETTINGS_OPENED = true; SETTINGS.opened = id; local p = SETTINGS.panels[id]; if p then p:Show() end end,
}

---------------------------------------------------------------- addon messages
Enum.SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, NotInGroup = 5, NotInGuild = 8 }
SENT, THROTTLE, PREFIXES = {}, false, {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) PREFIXES[p] = true return true end,
  IsAddonMessagePrefixRegistered = function(p) return PREFIXES[p] or false end,
  SendAddonMessage = function(prefix, text, chan, target)
    if THROTTLE then return Enum.SendAddonMessageResult.AddonMessageThrottle end
    SENT[#SENT + 1] = { prefix = prefix, text = text, chan = chan, target = target } return Enum.SendAddonMessageResult.Success
  end,
}
function LASTSENT() local s = SENT[#SENT] return s and s.text end
-- RECV("GatherKing1", "N1423,...", "Bob-Realm") delivers an addon message from a guildmate.
function RECV(prefix, text, sender, chan) FIRE("CHAT_MSG_ADDON", prefix, text, chan or "GUILD", sender or "Bob-Realm") end

---------------------------------------------------------------- auction house (modern only)
Enum.AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4 }
Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
Enum.ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Questitem = 12, Key = 13, Miscellaneous = 15 }
Enum.PlayerInteractionType = { Auctioneer = 21, MailInfo = 17, Merchant = 5, Banker = 8 }
AH_OPEN, AH_PRICES, AH_QUERIES, AH_ASKED, OWNED = true, {}, 0, {}, {}
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
AuctionHouseFrame.IsShown = function() return AH_OPEN end
-- the two sell panes Mail King hooks: SELL.commodity / SELL.item hold what's in them
SELL = { commodity = { n = 1, duration = 1, unitPrice = 0 }, item = { n = 1, duration = 1, buyout = 0 } }
local function sellFrame(kind, key)
  local fr = CreateFrame("Frame", "AuctionHouseFrame" .. kind)
  fr.PostButton = CreateFrame("Button", "AuctionHouseFrame" .. kind .. "PostButton", fr)
  function fr:GetItem() return SELL[key].item end
  function fr:GetQuantity() return SELL[key].n end
  function fr:GetDuration() return SELL[key].duration end
  function fr:GetUnitPrice() return SELL[key].unitPrice end
  function fr:GetBuyout() return SELL[key].buyout end
  return fr
end
AuctionHouseFrame.CommoditiesSellFrame = sellFrame("CommoditiesSellFrame", "commodity")
AuctionHouseFrame.ItemSellFrame = sellFrame("ItemSellFrame", "item")
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return true end,
  MakeItemKey = function(id, level, suffix) return { itemID = id, itemLevel = level or 0, itemSuffix = suffix or 0, battlePetSpeciesID = 0 } end,
  SendSearchQuery = function(key)
    AH_QUERIES = AH_QUERIES + 1; AH_ASKED[key.itemID] = true
    C_Timer.After(0.2, function() FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID); FIRE("ITEM_SEARCH_RESULTS_UPDATED", key) end)
  end,
  GetCommoditySearchResultInfo = function(id, i) local p = AH_PRICES[id] if p and (i or 1) == 1 then return { itemID = id, unitPrice = p, quantity = 1 } end end,
  GetItemSearchResultInfo = function(key, i) local p = AH_PRICES[key.itemID] if p and (i or 1) == 1 then return { itemKey = key, buyoutAmount = p, quantity = 1 } end end,
  GetNumCommoditySearchResults = function(id) return AH_PRICES[id] and 1 or 0 end,
  GetNumItemSearchResults = function(key) return AH_PRICES[key.itemID] and 1 or 0 end,
  CalculateCommodityDeposit = function(id, duration, n) return 30 * n end,
  CalculateItemDeposit = function(loc, duration, n) return 500 end,
  PostCommodity = function() end,
  PostItem = function() end,
  GetNumOwnedAuctions = function() return #OWNED end,
  GetOwnedAuctionInfo = function(i) return OWNED[i] end,
  -- SendBrowseQuery / SearchForItemKeys / ReplicateItems are nil until a test installs them (USE_AH_BROWSE / USE_AH_REPLICATE)
}
-- Installs a modern "browse" auction house: results = { { itemKey = { itemID = }, minPrice = , totalQuantity = }, ... }, paged.
function USE_AH_BROWSE(results, pageSize)
  BROWSE, PAGES_SENT, KEYS, KEY_IDS, SHOWN, RESULTS = 0, 0, 0, {}, 0, {}
  C_AuctionHouse.SendBrowseQuery = function(q)
    BROWSE = BROWSE + 1; RESULTS = results or {}; SHOWN = 0
    C_Timer.After(0.1, function() SHOWN = math.min(pageSize or #RESULTS, #RESULTS); FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
  end
  C_AuctionHouse.SearchForItemKeys = function(keys)
    KEYS = KEYS + 1; RESULTS = {}
    for _, k in ipairs(keys) do KEY_IDS[k.itemID] = true; if AH_PRICES[k.itemID] then RESULTS[#RESULTS + 1] = { itemKey = { itemID = k.itemID }, minPrice = AH_PRICES[k.itemID], totalQuantity = 1 } end end
    SHOWN = #RESULTS
    C_Timer.After(0.1, function() FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
  end
  C_AuctionHouse.GetBrowseResults = function() local r = {} for i = 1, math.min(SHOWN, #RESULTS) do r[i] = RESULTS[i] end return r end
  C_AuctionHouse.HasFullBrowseResults = function() return SHOWN >= #RESULTS end
  C_AuctionHouse.RequestMoreBrowseResults = function() PAGES_SENT = PAGES_SENT + 1; SHOWN = math.min(SHOWN + (pageSize or #RESULTS), #RESULTS); FIRE("AUCTION_HOUSE_BROWSE_RESULTS_ADDED") end
end
-- Installs ReplicateItems (a Deep Scan dump): auctions = { { itemID, stack, buyout, seller }, ... }
function USE_AH_REPLICATE(auctions)
  AUCTIONS, REPLICATED = auctions or {}, 0
  C_AuctionHouse.ReplicateItems = function() REPLICATED = REPLICATED + 1; C_Timer.After(1, function() FIRE("REPLICATE_ITEM_LIST_UPDATE") end) end
  C_AuctionHouse.GetNumReplicateItems = function() return #AUCTIONS end
  C_AuctionHouse.GetReplicateItemInfo = function(i)
    local a = AUCTIONS[i + 1]
    return "x", 1, a[2], 1, true, 1, 0, 0, 0, a[3], 0, false, nil, a[4], a[4], 0, a[1], true
  end
end

---------------------------------------------------------------- mail
AUCTION_SOLD_MAIL_SUBJECT, AUCTION_WON_MAIL_SUBJECT = "Auction successful: %s", "Auction won: %s"
AUCTION_EXPIRED_MAIL_SUBJECT, AUCTION_REMOVED_MAIL_SUBJECT, AUCTION_OUTBID_MAIL_SUBJECT = "Auction expired: %s", "Auction cancelled: %s", "Outbid on %s"
-- INBOX[i] = { subject=, money=, days=, sender=, invoice = { type=, item=, who=, bid=, buyout=, dep=, cut=, n= }, att = { name=, id=, n= } }
INBOX = {}
function GetInboxNumItems() return #INBOX end
function GetInboxHeaderInfo(i) local m = INBOX[i]; return nil, nil, m.sender or "Auction House", m.subject, m.money or 0, 0, m.days or 30, m.att and 1 or nil, false, false, false, false end
function GetInboxInvoiceInfo(i)
  local v = INBOX[i].invoice; if not v then return nil end
  return v.type, v.item, v.who, v.bid or 0, v.buyout or 0, v.dep or 0, v.cut or 0, 0, 0, v.n or 1
end
function GetInboxItem(i, n) local a = INBOX[i].att; if a and (n or 1) == 1 then return a.name, a.id, 0, a.n or 1 end end
function GetInboxItemLink(i, n) local a = INBOX[i].att; if a then return LINK(a.id) end end
function TakeInboxMoney() end
function TakeInboxItem() end
function OPEN_MAIL(box) INBOX = box; FIRE("MAIL_SHOW"); FIRE("MAIL_INBOX_UPDATE"); RUN_TIMERS() end

---------------------------------------------------------------- merchant and trade skills
MERCHANT = {}   -- { { id=, name=, price=, n= }, ... }
function GetMerchantNumItems() return #MERCHANT end
function GetMerchantItemID(i) return MERCHANT[i] and MERCHANT[i].id end
function GetMerchantItemInfo(i) local m = MERCHANT[i]; if m then return m.name, 1, m.price or 0, m.n or 1, -1, true, true, nil end end
function GetMerchantItemLink(i) return MERCHANT[i] and LINK(MERCHANT[i].id) end
C_MerchantFrame = { GetItemInfo = function(i) local m = MERCHANT[i]; if m then return { name = m.name, price = m.price or 0, stackCount = m.n or 1, numAvailable = -1, isPurchasable = true, isUsable = true, hasExtendedCost = false } end end }
-- TRADESKILL = { name = "Blacksmithing", recipes = { [spellID] = { output = itemID, n = 1, reagents = { { id, n }, ... }, learned = true } } }
TRADESKILL = nil
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() if TRADESKILL then return { professionName = TRADESKILL.name, professionID = TRADESKILL.id or 0 } end end,
  GetAllRecipeIDs = function() local t = {} for id in pairs(TRADESKILL and TRADESKILL.recipes or {}) do t[#t + 1] = id end table.sort(t) return t end,
  GetRecipeInfo = function(id) local r = TRADESKILL and TRADESKILL.recipes[id]; if r then return { recipeID = id, learned = r.learned ~= false, name = r.name or ("Recipe " .. id) } end end,
  GetRecipeSchematic = function(id)
    local r = TRADESKILL and TRADESKILL.recipes[id]; if not r then return nil end
    local slots = {} for _, rg in ipairs(r.reagents or {}) do slots[#slots + 1] = { reagents = { { itemID = rg[1] } }, quantityRequired = rg[2] } end
    return { recipeID = id, outputItemID = r.output, quantityMin = r.n or 1, quantityMax = r.n or 1, reagentSlotSchematics = slots }
  end,
  IsTradeSkillLinked = function() return false end,
}

---------------------------------------------------------------- hooksecurefunc
function hooksecurefunc(a, b, c)
  if type(a) == "string" then
    local orig = _G[a]; _G[a] = function(...) local r = { orig(...) }; b(...); return unpack(r) end
  else
    local orig = a[b]; a[b] = function(...) local r = { orig(...) }; c(...); return unpack(r) end
  end
end
