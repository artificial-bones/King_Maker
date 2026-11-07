# Runs Minimap King against a stand-in for the game:
#   python3 tests/run.py .
import sys
from lupa import lua51
root = sys.argv[1] if len(sys.argv) > 1 else "."
MOCK = r"""
OUTPUT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) OUTPUT[#OUTPUT+1] = m end }
SlashCmdList, UISpecialFrames, TIMERS = {}, {}, {}
C_Timer = { After = function(_, fn) TIMERS[#TIMERS+1] = fn end }
function RUN_TIMERS() while #TIMERS > 0 do table.remove(TIMERS, 1)() end end
function GetCursorPosition() return 0, 0 end
function IsShiftKeyDown() return SHIFT end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
local function stub(t) return setmetatable(t, { __index = function(_, k) if k:match("^%u") then return function() end end end }) end
local frames = {}
function CreateFrame(kind, name, parent)
  local f = stub({ scripts = {}, events = {}, shown = true, kind = kind, name = name, children = {}, points = {}, w = 31, h = 31, cx = 0, cy = 0 })
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
  function f:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
  function f:SetShown(v) if v then self:Show() else self:Hide() end end
  function f:IsShown() return self.shown end
  function f:GetName() return self.name end
  function f:GetObjectType() return self.kind end
  function f:GetSize() return self.w, self.h end
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:GetWidth() return self.w end
  function f:GetCenter() return self.cx, self.cy end
  function f:GetEffectiveScale() return 1 end
  function f:GetParent() return self.parent end
  function f:SetParent(p) if self.parent then for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end end
    self.parent = p; if p then table.insert(p.children, self) end end
  function f:GetChildren() return unpack(self.children) end
  function f:ClearAllPoints() self.points = {} end
  function f:SetPoint(...) table.insert(self.points, { ... }) end
  function f:GetNumPoints() return #self.points end
  function f:GetPoint(i) return unpack(self.points[i]) end
  function f:GetFrameStrata() return self.strata or "MEDIUM" end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameLevel() return self.level or 1 end
  function f:SetFrameLevel(l) self.level = l end
  function f:RegisterForDrag(...) self.drag = select("#", ...) > 0 end
  function f:HookScript(k, fn) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end fn(...) end end
  function f:GetChecked() return self.checked or false end
  function f:SetChecked(v) self.checked = not not v end
  function f:SetEnabled(v) self.enabled = v end
  function f:Click(which) if self.scripts.OnClick then self.scripts.OnClick(self, which) end end
  function f:CreateTexture() return stub({ SetTexture = function(s, t) s.tex = t end }) end
  function f:CreateMaskTexture() return stub({}) end
  function f:CreateFontString() return stub({ SetText = function(s, t) s.text = t end, SetShown = function(s, v) s.shown = v end, Hide = function(s) s.shown = false end }) end
  if parent then f:SetParent(parent) end
  if name then _G[name] = f end
  frames[#frames+1] = f
  return f
end
function FIRE(e, ...) for _, f in ipairs(frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end end
function hooksecurefunc(t, k, fn) local old = t[k]; t[k] = function(...) local r = old(...); fn(...); return r end end
UIParent = CreateFrame("Frame")
WorldFrame = CreateFrame("Frame")
Minimap = CreateFrame("Frame"); Minimap.w = 140
GameTooltip = stub({ AddLine = function(s, l) TIP[#TIP+1] = l end, Show = function() end })
TIP = {}
FOCUS = nil
SETTINGS = {}
Settings = { RegisterCanvasLayoutCategory = function(panel, name) SETTINGS.panel = panel; return { GetID = function() return name end } end,
  RegisterAddOnCategory = function() end, OpenToCategory = function(id) SETTINGS.opened = id; SETTINGS.panel:Show() end }
function GetMouseFoci() return { FOCUS } end
CLICKS = {}
-- a button on the minimap's edge (70 from the center)
function MAKE(name, kind, cx, cy, size)
  local b = CreateFrame(kind or "Button", name, Minimap)
  b.cx, b.cy = cx or 70, cy or 0
  if size then b.w, b.h = size, size end
  b:SetPoint("CENTER", Minimap, "CENTER", b.cx, b.cy)
  b:SetScript("OnClick", function(self, which) CLICKS[#CLICKS+1] = name .. ":" .. tostring(which) end)
  b:SetScript("OnEnter", function(self) GameTooltip:AddLine(name .. " tip") end)
  return b
end
"""
L = lua51.LuaRuntime()
L.execute(MOCK)
L.execute("""
MAKE("ScannerKingMinimapButton"); MAKE("EconKingMinimapButton")
MAKE("LibDBIcon10_Questie", "Button", 0, 0)            -- LibDBIcon: always taken
MAKE("AtlasLootMinimapButton", "Button", 0, -70)        -- another addon's button on the edge
MAKE("MiniMapTracking")                                 -- Blizzard: stays
MAKE("GatherKingPin1", "Button", 10, 10)                -- a map pin inside the minimap: stays
MAKE("SomeBigFrame", "Button", 70, 0, 120)              -- too big to be a button: stays
MAKE("QuestieFrame12", "Button", 0, 70, 16)            -- a Questie pin clamped to the edge: stays
MAKE("NotAButton", "Frame")                             -- not a button: stays
""")
ns = L.table()
for fn in [l.strip() for l in open(f"{root}/Minimap_King.toc") if l.strip() and not l.startswith("#")]:
    L.execute(open(f"{root}/{fn}").read(), "Minimap_King", ns)
L.execute('FIRE("ADDON_LOADED", "Minimap_King"); FIRE("PLAYER_LOGIN")')
names = lambda: [ns.NameOf(b) for b in ns.Shown().values()]
assert names() == ["Econ King", "Scanner King", "AtlasLoot", "Questie"], names()
assert L.eval("MinimapKingMenu.kingsHeader.text") == "King Addons" and L.eval("MinimapKingMenu.othersHeader.text") == "Other Addons"
assert L.eval("MinimapKingMenu.othersHeader.shown") != False
for n in ["ScannerKingMinimapButton", "AtlasLootMinimapButton"]:
    assert L.eval(f"{n}:GetParent() == MinimapKingMenu"), n
for n in ["MiniMapTracking", "GatherKingPin1", "SomeBigFrame", "NotAButton", "QuestieFrame12"]:
    assert L.eval(f"{n}:GetParent() == Minimap"), n
assert L.eval("ScannerKingMinimapButton.drag") == False
# a button made later is caught; an addon moving or hiding its button keeps the menu tidy
L.execute('MAKE("MailKingMinimapButton"); RUN_TIMERS()')
assert "Mail King" in names()
L.execute("EconKingMinimapButton:SetPoint('CENTER', Minimap, 'CENTER', 1, 2)")
assert L.eval("EconKingMinimapButton.points[1][2] == MinimapKingMenu")
L.execute("AtlasLootMinimapButton:SetShown(false)"); assert "AtlasLoot" not in names()
assert L.eval("MinimapKingMenu.empty.text") == ""
# the menu: names click through to the real buttons, tooltips are theirs
L.execute('MinimapKingButton:GetScript("OnClick")(MinimapKingButton, "LeftButton")')
assert L.eval("MinimapKingMenu:IsShown()") and L.eval("MinimapKingMenu.events.GLOBAL_MOUSE_DOWN")
labels = ns.labels
lab = next(l for l in labels.values() if l.text.text == "Scanner King")
lab.scripts.OnClick(lab, "RightButton"); assert L.eval("CLICKS[#CLICKS]") == "ScannerKingMinimapButton:RightButton"
# picking an addon closes the menu (just after its click runs), from the name or the button itself
assert L.eval("MinimapKingMenu:IsShown()"); L.execute("RUN_TIMERS()"); assert not L.eval("MinimapKingMenu:IsShown()")
L.execute('SlashCmdList.MINIMAPKING(""); EconKingMinimapButton:Click("LeftButton"); RUN_TIMERS()')
assert not L.eval("MinimapKingMenu:IsShown()") and L.eval("CLICKS[#CLICKS]") == "EconKingMinimapButton:LeftButton"
L.execute('SlashCmdList.MINIMAPKING("")')
L.execute("TIP = {}"); lab.scripts.OnEnter(lab); assert L.eval("TIP[1]") == "ScannerKingMinimapButton tip"
# clicks on other windows leave it open; a click in the world closes it
L.execute('FOCUS = UIParent; FIRE("GLOBAL_MOUSE_DOWN")'); assert L.eval("MinimapKingMenu:IsShown()")
L.execute('FOCUS = WorldFrame; FIRE("GLOBAL_MOUSE_DOWN")'); assert not L.eval("MinimapKingMenu:IsShown()")
# shift-right-click leaves a button on the minimap, remembered; unignore brings it back
L.execute("SHIFT = true"); q = next(l for l in labels.values() if l.text.text == "Questie")
q.scripts.OnClick(q, "RightButton"); L.execute("SHIFT = false")
assert "Questie" not in names() and L.eval("LibDBIcon10_Questie:GetParent() == Minimap") and L.eval("MinimapKingDB.ignore.LibDBIcon10_Questie")
L.execute('SlashCmdList.MINIMAPKING("unignore")'); assert "Questie" in names()
# release puts every button back where it was
L.execute('SlashCmdList.MINIMAPKING("release")')
assert L.eval("ScannerKingMinimapButton:GetParent() == Minimap") and L.eval("ScannerKingMinimapButton.points[1][2] == Minimap")
assert L.eval("ScannerKingMinimapButton.drag") == True and names() == []
L.execute('SlashCmdList.MINIMAPKING("gather")'); assert "Scanner King" in names()
# only King buttons: no "Other Addons" heading
for n in ["AtlasLootMinimapButton", "LibDBIcon10_Questie"]: L.execute(f"{n}:Hide()")
assert L.eval("MinimapKingMenu.othersHeader.shown") == False and L.eval("MinimapKingMenu.kingsHeader.shown") == True
# names
L.execute('X = CreateFrame("Button", "DBM_MinimapButton")'); assert ns.NameOf(L.eval("X")) == "DBM"
L.execute('Y = CreateFrame("Button", "HandyNotesMinimapButton")'); assert ns.NameOf(L.eval("Y")) == "HandyNotes"
# crowns
L.execute('GetFileIDFromPath = function(p) if p:find("Crown_C_01_Gold") or p:find("INV_Crown_01") then return 1 end end')
assert ns.Crown()[1] == "Gold crown"
L.execute('SlashCmdList.MINIMAPKING("icon")'); assert ns.Crown()[1] == "Classic crown"
L.execute('SlashCmdList.MINIMAPKING("icon 7")'); assert "Pick 1 to 2" in L.eval("OUTPUT[#OUTPUT]")
L.execute('TIP = {}; MinimapKingButton:GetScript("OnEnter")(MinimapKingButton)'); assert L.eval("TIP[1]") == "Minimap King"
# settings: a checkbox per button, Kings first; unticking puts it on the minimap, ticking takes it back
L.execute('SETTINGS.panel.shown = false; MinimapKingButton:GetScript("OnClick")(MinimapKingButton, "RightButton")')
assert L.eval("SETTINGS.opened") == "Minimap King"
L.execute("""CHECKS = {}
for _, c in ipairs(SETTINGS.panel.children) do end""")
checks = L.eval("""(function() local out = {}
  local function walk(f) for _, c in ipairs(f.children or {}) do if c.label and c.button then out[#out+1] = c end walk(c) end end
  walk(SETTINGS.panel) return out end)()""")
cl = {c.label.text: c for c in checks.values() if c.shown}
assert list(cl)[:3] == ["Econ King", "Mail King", "Scanner King"], list(cl)
assert "Questie" in cl and "AtlasLoot" in cl and cl["Questie"].checked
cb = cl["Econ King"]; cb.checked = False; cb.scripts.OnClick(cb)
assert "Econ King" not in names() and L.eval("EconKingMinimapButton:GetParent() == Minimap")
cb.checked = True; cb.scripts.OnClick(cb); assert "Econ King" in names()
print("ALL TESTS PASSED")
