# Minimap (was Minimap King): other addons' minimap buttons gathered into one menu that opens from King Maker's
# crown: which buttons, ordering, reparenting, click forwarding, ignore/unignore, release/gather, the crown never
# gathered, the quick action, the Settings rows and /mmk.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

# Fake buttons on the minimap. The shared mock's frames are 140x140 at (0, 0), so each gets a button's size and a
# spot on the minimap's edge (70 from the centre) unless said otherwise.
SEED = """
CLICKS = {}
function MAKE(name, kind, cx, cy, size)
  local b = CreateFrame(kind or "Button", name, Minimap)
  b.cx, b.cy = cx or 70, cy or 0
  b:SetSize(size or 31, size or 31)
  b:SetPoint("CENTER", Minimap, "CENTER", b.cx, b.cy)
  b:SetScript("OnClick", function(self, which) CLICKS[#CLICKS+1] = name .. ":" .. tostring(which) end)
  b:SetScript("OnEnter", function(self) GameTooltip:AddLine(name .. " tip") end)
  return b
end
MAKE("DetailsMinimapButton"); MAKE("DBM_MinimapButton")
MAKE("LibDBIcon10_Questie", "Button", 0, 0)             -- LibDBIcon: always taken
MAKE("AtlasLootMinimapButton", "Button", 0, -70)        -- another addon's button on the edge
MAKE("MiniMapTracking")                                 -- Blizzard: stays
MAKE("GatherKingPin1", "Button", 10, 10)                -- a map pin inside the minimap: stays
MAKE("SomeBigFrame", "Button", 70, 0, 120)              -- too big to be a button: stays
MAKE("QuestieFrame12", "Button", 0, 70, 16)             -- a Questie pin clamped to the edge: stays
MAKE("NotAButton", "Frame")                             -- not a button: stays
function CHECK(text) for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == text and rawget(f, "mark") then return f end end end
"""

L, KM = fresh(only=["Minimap"], seed=SEED)
ns = KM.mods.Minimap
mmk = L.eval("SlashCmdList.MINIMAPKING")
L.execute("RUN_TIMERS()")
names = lambda: [ns.NameOf(b) for b in ns.Shown().values()]
assert L.eval("MinimapKingButton") is None, "no crown of its own: the crown is King Maker's"
assert L.eval("MinimapKingDB.gather") is True and L.eval("MinimapKingDB.ignore") is not None
assert L.eval("type(MinimapKing.ShowMenu) == 'function' and type(MinimapKing.Gather) == 'function' and type(MinimapKing.Release) == 'function' and type(MinimapKing.Shown) == 'function'")
assert names() == ["AtlasLoot", "DBM", "Details", "Questie"], names()
for n in ["DetailsMinimapButton", "AtlasLootMinimapButton", "LibDBIcon10_Questie"]:
    assert L.eval(f"{n}:GetParent() == MinimapKingMenu"), n
for n in ["MiniMapTracking", "GatherKingPin1", "SomeBigFrame", "NotAButton", "QuestieFrame12"]:
    assert L.eval(f"{n}:GetParent() == Minimap"), n
assert L.eval("DetailsMinimapButton.drag") is False
# King Maker's crown is a minimap button too, but never goes in the menu, wherever it sits
assert L.eval("KingMakerMinimapButton ~= nil and KingMakerMinimapButton:GetParent() == Minimap")
L.execute("KingMakerMinimapButton.cx = 70; KingMakerMinimapButton:SetSize(31, 31)")
L.globals().MMNS = ns
assert not L.eval("MMNS.IsAddonButton(KingMakerMinimapButton)")
ns.Gather()
assert L.eval("KingMakerMinimapButton:GetParent() == Minimap") and "KingMaker" not in names()
print("GATHER OK")

# a button made later is caught; an addon moving or hiding its button keeps the menu tidy
L.execute('MAKE("ZygorMinimapButton"); RUN_TIMERS(); MinimapKing.Gather()')
assert names()[-1] == "Zygor", names()
L.execute("DBM_MinimapButton:SetPoint('CENTER', Minimap, 'CENTER', 1, 2)")
assert L.eval("DBM_MinimapButton.points[#DBM_MinimapButton.points][2] == MinimapKingMenu"), "laid out again in the menu"
L.execute("AtlasLootMinimapButton:SetShown(false)"); assert "AtlasLoot" not in names()
L.execute("AtlasLootMinimapButton:SetShown(true)"); assert "AtlasLoot" in names()
assert L.eval("MinimapKingMenu.empty.text") == ""
assert L.eval("MinimapKingMenu.heading.text") == "YOUR ADDONS"
print("LAYOUT OK")

# the quick action opens the menu under the crown; names click through to the real buttons, tooltips are theirs
L.execute('KingMakerMinimapButton:Click("RightButton")')
assert L.eval('MENU_ITEM("Minimap buttons") ~= nil')
L.execute('MENU_ITEM("Minimap buttons").fn()')
assert L.eval("MinimapKingMenu:IsShown()") and L.eval("MinimapKingMenu.events.GLOBAL_MOUSE_DOWN")
assert L.eval("MinimapKingMenu.points[1][2] == KingMakerMinimapButton"), "anchored to King Maker's crown"
labels = ns.labels
lab = next(l for l in labels.values() if l.text.text == "Details")
lab.RunScript(lab, "OnClick", "RightButton"); assert L.eval("CLICKS[#CLICKS]") == "DetailsMinimapButton:RightButton"
# picking an addon closes the menu (just after its click runs), from the name or the button itself
assert L.eval("MinimapKingMenu:IsShown()"); L.execute("RUN_TIMERS()"); assert not L.eval("MinimapKingMenu:IsShown()")
mmk(""); L.execute('DBM_MinimapButton:Click("LeftButton"); RUN_TIMERS()')
assert not L.eval("MinimapKingMenu:IsShown()") and L.eval("CLICKS[#CLICKS]") == "DBM_MinimapButton:LeftButton"
mmk("")
L.execute("GameTooltip.lines = {}"); lab.RunScript(lab, "OnEnter"); assert L.eval("GameTooltip.lines[1]") == "DetailsMinimapButton tip"
assert lab.hl.shown is True
# clicks on other windows leave it open; a click in the world closes it
L.execute('FOCUS = UIParent; FIRE("GLOBAL_MOUSE_DOWN")'); assert L.eval("MinimapKingMenu:IsShown()")
L.execute('FOCUS = WorldFrame; FIRE("GLOBAL_MOUSE_DOWN")'); assert not L.eval("MinimapKingMenu:IsShown()")
assert not L.eval("MinimapKingMenu.events.GLOBAL_MOUSE_DOWN")
# with the crown hidden the menu opens by the minimap
L.execute("KingMakerMinimapButton:Hide()"); mmk("menu")
assert L.eval("MinimapKingMenu.points[1][2] == Minimap")
L.execute("MinimapKingMenu:Hide(); KingMakerMinimapButton:Show()")
assert "MinimapKingMenu" in list(L.eval("UISpecialFrames").values()), "Escape closes it"
print("MENU OK")

# shift-right-click leaves a button on the minimap, remembered; unignore brings it back
L.execute("SHIFT = true"); q = next(l for l in labels.values() if l.text.text == "Questie")
q.RunScript(q, "OnClick", "RightButton"); L.execute("SHIFT = false")
assert "Questie" not in names() and L.eval("LibDBIcon10_Questie:GetParent() == Minimap") and L.eval("MinimapKingDB.ignore.LibDBIcon10_Questie")
assert "stays on the minimap" in last(L)
mmk("unignore"); assert "Questie" in names()
# release puts every button back where it was
mmk("release")
assert L.eval("DetailsMinimapButton:GetParent() == Minimap") and L.eval("DetailsMinimapButton.points[1][2] == Minimap")
assert L.eval("DetailsMinimapButton.drag") is True and names() == [] and L.eval("MinimapKingDB.gather") is False
L.execute('KingMakerMinimapButton:Click("RightButton")'); assert L.eval('MENU_ITEM("Minimap buttons") == nil'), "no menu to open while released"
mmk("gather"); assert "Details" in names() and L.eval("MinimapKingDB.gather") is True
# names
assert ns.NameOf(L.eval("DBM_MinimapButton")) == "DBM" and ns.NameOf(L.eval("LibDBIcon10_Questie")) == "Questie"
L.execute('Y = CreateFrame("Button", "HandyNotesMinimapButton")'); assert ns.NameOf(L.eval("Y")) == "HandyNotes"
mmk("icon"); assert "crown on the minimap is King Maker's" in last(L)
mmk("help"); assert any("/mmk release" in str(o) for o in outputs(L))
print("SLASH OK")


# settings: a check per button, by name; unticking puts it on the minimap, ticking takes it back
def texts():
    fs = L.eval("FONTS")
    return [str(fs[i].text) for i in range(1, len(fs) + 1) if fs[i].text]


mmk("settings"); assert KM.IsShown("settings") and not KM.errorShown, last(L)
t = texts()
assert "Gather minimap buttons into the menu" in t
for n in ["AtlasLoot", "DBM", "Details", "Questie", "Zygor"]:
    assert n in t, n
assert "KingMaker" not in t and "Tracking" not in t
cb = L.eval('CHECK("Details")'); assert cb.checked
cb.GetScript(cb, "OnClick")(cb)
assert "Details" not in names() and L.eval("DetailsMinimapButton:GetParent() == Minimap") and L.eval("MinimapKingDB.ignore.DetailsMinimapButton")
cb.GetScript(cb, "OnClick")(cb); assert "Details" in names()
master = L.eval('CHECK("Gather minimap buttons into the menu")'); assert master.checked
master.GetScript(master, "OnClick")(master)
assert names() == [] and L.eval("MinimapKingDB.gather") is False and L.eval("AtlasLootMinimapButton:GetParent() == Minimap")
master.GetScript(master, "OnClick")(master); assert "AtlasLoot" in names()
assert not KM.errorShown, last(L)
print("SETTINGS OK")

# InitDB is safe twice and keeps the 1.x shape (gather, ignore; angle and icon left alone)
L2, KM2 = fresh(only=["Minimap"], seed=SEED + "MinimapKingDB = { gather = true, angle = 120, icon = 'x', ignore = { DBM_MinimapButton = true } }")
L2.execute("RUN_TIMERS(); HELD = MinimapKingDB"); KM2.mods.Minimap.InitDB()
assert L2.eval("MinimapKingDB == HELD") and L2.eval("MinimapKingDB.ignore.DBM_MinimapButton") and L2.eval("MinimapKingDB.angle") == 120
assert L2.eval("DBM_MinimapButton:GetParent() == Minimap"), "an ignored button stays on the minimap"
print("INITDB OK")

print("minimap: ok")
