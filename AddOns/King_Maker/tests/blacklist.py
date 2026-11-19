# Guild Blacklist (new in 2.10, Modules/Blacklist): saved data and names, adding from the right-click menus (chat
# names, name + surname, units), guildmates and yourself refused, the note rules, the page (newest first, search,
# detail, edit, remove), the group join warning (silent first read, new members only, once a session), the invite
# warning, the chat tag, the unit tooltip, the group finder (late load, entry marks, tooltip box, Alt-click), and guild
# sharing between two (and three) clients: adds, last-write-wins edits, tombstones that don't resurrect, the
# fingerprint exchange, silence when in step, message length, rate limits; no guild = a personal list, nothing sent.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs, open_every_page

PREFIX = "KingMaker1"
DAY = 86400
BASE = 20000 * DAY


def load(name="Jay", surname="Doe", extra="", only=("Blacklist",)):
    L, KM = fresh(only=list(only), extra="PLAYER.name = '%s'; PLAYER.surname = %s; NOW = %d\n" % (
        name, ("'%s'" % surname) if surname else "nil", BASE) + extra)
    assert not KM.errorShown, last(L)
    ns = KM.mods.Blacklist
    L.execute("SENT = {}; RAID_NOTICES = {}")
    ns.SyncReset()
    L.execute("ADVANCE(5); RUN_TIMERS()")
    L.execute("SENT = {}; NOW = %d" % BASE)
    return L, KM, ns


def sent(L, kinds="LQWE"):
    out = []
    for i in range(1, L.eval("#SENT") + 1):
        s = L.eval("SENT[%d]" % i)
        if s.prefix == PREFIX and s.text[:1] in kinds:
            assert s.chan == "GUILD" and s.target is None, "guild channel only"
            assert len(s.text) <= 250, (len(s.text), s.text)
            out.append(s.text)
    return out


def clear(L):
    L.execute("SENT = {}")


def drain(L, secs=15):
    L.execute("RUN_TIMERS()")
    for _ in range(secs):
        L.execute("ADVANCE(1); RUN_TIMERS()")


def deliver(texts, dst, sender):
    for t in texts:
        dst.globals().RECV(PREFIX, t, sender)
    dst.execute("RUN_TIMERS()")


def exchange(clients, rounds=10, secs=15):
    """clients = [(L, 'Full Name')]: carries every guild message to every other client until all fall quiet."""
    log = []
    for _ in range(rounds):
        out = []
        for L, name in clients:
            drain(L, secs)
            out.append(sent(L))
            clear(L)
        if not any(out):
            break
        for (L, name), texts in zip(clients, out):
            log += [(name, t) for t in texts]
            for (L2, name2) in clients:
                if L2 is not L:
                    deliver(texts, L2, name + "-Forever")
    return log


def entry(L, key, list_key="Kings-Forever"):
    return L.eval("BlacklistKingDB.lists['%s'] and BlacklistKingDB.lists['%s'].entries['%s']" % (list_key, list_key, key))


def fp(ns):
    return tuple(ns.Fingerprint())


def advance_clock(L, secs):
    L.execute("NOW = NOW + %d" % secs)


# ---------------------------------------------------------------- 1. load, saved data, the page
L, KM, ns = load()
db = L.eval("BlacklistKingDB")
assert L.eval("BlacklistKing.API_VERSION") == 1
assert db.version == 1 and L.eval("type(BlacklistKingDB.lists)") == "table"
s = db.settings
for k in ("share", "alertJoin", "alertInvite", "sound", "chatTag", "lfg", "tooltip", "purge"):
    assert s[k] is True, k
assert db.ui.sort == "added" and db.ui.desc is True
assert ns.ListKey() == "Kings-Forever" and db.chars["Jay Doe-Forever"] == "Kings-Forever"
p = KM.pages.blacklist
assert p.group == "guild" and KM.groups.guild.order == 55 and KM.groups.guild.label == "Guild"
assert "/bl" in [L.eval("SLASH_KINGMAKERBLACKLIST1"), L.eval("SLASH_KINGMAKERBLACKLIST2")]
L.execute("SLASH('/bl')"); assert KM.IsShown("blacklist")
L.execute("SLASH('/bl')"); assert not KM.IsShown("blacklist")
L.execute("SLASH('/km blacklist')"); assert KM.IsShown("blacklist")
open_every_page(L, KM)
assert not KM.errorShown, last(L)
assert L.eval("PREFIXES['KingMaker1']") is True
print("LOAD OK")

# ---------------------------------------------------------------- 2. names
assert ns.Name("evil guy-Forever") == "Evil Guy"
assert ns.Name("  Evil   Guy ") == "Evil Guy"
assert ns.Key("Evil Guy-Some Realm") == "evil guy"
assert ns.Name("Unknown") is None and ns.Name("") is None and ns.Name("Bob2") is None and ns.Name("x" * 41) is None
assert ns.Clean("a|cffff0000b|r~c^d\ne") == "acffff0000brcd e"
assert ns.Cut("abc\xc3\xa9", 4) == "abc", "never splits a UTF-8 character"
assert ns.ParseAdd("Evil Guy: took my gold") == ("Evil Guy", "took my gold")
assert ns.ParseAdd("Evil Guy took my gold") == ("Evil Guy", "took my gold")
assert ns.ParseAdd("Evil took my gold") == ("Evil", "took my gold")
assert ns.ParseAdd('"evil guy" ninja') == ("evil guy", "ninja")
print("NAMES OK")

# ---------------------------------------------------------------- 3. adding from the right-click menus
for tag in ("MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_ENEMY_PLAYER",
            "MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE"):
    assert L.eval("MENU_MODS['%s'] and #MENU_MODS['%s']" % (tag, tag)) == 1, tag
# a chat name (MENU_UNIT_FRIEND with chatTarget, realm and all)
items = L.eval("OPEN_MENU('MENU_UNIT_FRIEND', { chatTarget = 'Evil Guy-Forever', name = 'Evil', surname = 'Guy' })")
texts = [it.text for it in items.values()]
assert texts == ["Add to Blacklist"], texts
items[1].fn()
dlg = ns.Dialog()
assert dlg and dlg.IsShown(dlg) and not dlg.free and "Evil Guy" in dlg.nameFixed.text
dlg.reason.Select(dlg.reason, "scam"); dlg.reasonID = "scam"
dlg.note.SetText(dlg.note, "sold me a fake Arcanite Reaper for 200g")
assert ns.DialogSave() is True and not dlg.IsShown(dlg)
e = entry(L, "evil guy")
assert e and e.n == "Evil Guy" and e.r == "scam" and e.by == "Jay Doe" and e.t == BASE and e.e == BASE and not e.eb
assert "added Evil Guy" in last(L)
assert L.eval("BlacklistKing.IsListed('evil guy-Forever')") is True
g = L.eval("BlacklistKing.Get('Evil Guy')")
assert g.reasonLabel == "Scam" and g.note.startswith("sold me") and g.by == "Jay Doe"
# name + surname, no chatTarget
items = L.eval("OPEN_MENU('MENU_UNIT_FRIEND_OFFLINE', { name = 'Bad', surname = 'Apple' })")
assert [it.text for it in items.values()] == ["Add to Blacklist"]
items[1].fn()
dlg.reasonID = "ninja"; dlg.note.SetText(dlg.note, "needed on every blue")
assert ns.DialogSave() and entry(L, "bad apple").r == "ninja"
# a unit (portrait): UnitNameUnmodified, and the GUID is kept for tooltips
L.execute("UNITS.target = { name = 'Rude', surname = 'Dude', isPlayer = true, guid = 'Player-1-RUDE' }")
items = L.eval("OPEN_MENU('MENU_UNIT_TARGET', { unit = 'target' })")
items[1].fn()
dlg.reasonID = "toxic"; dlg.note.SetText(dlg.note, "spat at the healer")
assert ns.DialogSave() and entry(L, "rude dude").g == "Player-1-RUDE"
# someone already listed: edit and remove instead
items = L.eval("OPEN_MENU('MENU_UNIT_TARGET', { unit = 'target' })")
texts = [it.text for it in items.values()]
assert len(texts) == 2 and "edit note" in texts[0] and texts[1] == "Remove from Blacklist", texts
# a mob, or nothing to go on: no button
L.execute("UNITS.mob = { name = 'Kobold', isPlayer = false }")
assert len(L.eval("OPEN_MENU('MENU_UNIT_TARGET', { unit = 'mob' })")) == 0
assert len(L.eval("OPEN_MENU('MENU_UNIT_FRIEND', {})")) == 0
print("MENUS OK")

# ---------------------------------------------------------------- 4. guildmates, yourself, the note
L.execute("UNITS.party1 = { name = 'Good', surname = 'Mate', isPlayer = true, guild = true }")
assert len(L.eval("OPEN_MENU('MENU_UNIT_PARTY', { unit = 'party1' })")) == 0, "no button on a guildmate"
ok, msg = ns.Save("Good Mate", "scam", "x", L.eval("{ unit = 'party1' }"))[:2]
assert not ok and "guild" in msg
L.execute("GUILD_ROSTER = { { name = 'Roster Pal-Forever', class = 'MAGE' }, { name = 'Jay Doe-Forever', class = 'WARRIOR' } }")
ns.RosterReset()
ok, msg = ns.Save("roster pal", "scam", "x")[:2]
assert not ok and "guild" in msg, "the roster fallback"
L.execute("GUILD_ROSTER = nil"); ns.RosterReset()
ok, msg = ns.Save("Jay Doe", "scam", "x")[:2]
assert not ok and "yourself" in msg
assert len(L.eval("OPEN_MENU('MENU_UNIT_PLAYER', { unit = 'player' })")) == 0
assert len(L.eval("OPEN_MENU('MENU_UNIT_FRIEND', { chatTarget = 'Jay Doe' })")) == 0
ok, msg = ns.Save("Some One", "scam", "   ")[:2]
assert not ok and "note" in msg, "a note is required"
ok = ns.Save("Some One", "toxic", "|cffff0000red|r ~text^ " + "x" * 300)[0]
e = entry(L, "some one")
assert ok and "|" not in e.note and "~" not in e.note and "^" not in e.note
assert len(e.note) <= 160 and e.note.startswith("cffff0000redr text")
# a long name and a long note still fit one message
ok = ns.Save("Abcdefghijklmnopqrst Uvwxyzabcdefghijklm", "other", "y" * 160)[0]
e = entry(L, "abcdefghijklmnopqrst uvwxyzabcdefghijklm")
assert ok and len(ns.Wire(e)) + 1 <= 250, len(ns.Wire(e))
assert ns.Save("Some One", "nonsense", "fine")[0] and entry(L, "some one").r == "other", "unknown reasons are Other"
# the dialog shows the game's message on a refusal
ns.OpenDialog(L.eval("{ free = true }"))
dlg.name.SetText(dlg.name, "Jay Doe"); dlg.note.SetText(dlg.note, "me")
assert ns.DialogSave() is False and "yourself" in dlg.err.text and dlg.IsShown(dlg)
dlg.Hide(dlg)
print("RULES OK")

# ---------------------------------------------------------------- 5. the page: newest first, search, detail, edit, remove
L2, KM2, n2 = load()
for i, (name, note) in enumerate([("Old Timer", "left mid-dungeon"), ("Mid Way", "ninja'd the Bloodfang"), ("New Kid", "scammed a portal")]):
    L2.execute("NOW = %d" % (BASE + i * 100))
    assert n2.Save(name, "scam", note)[0]
KM2.Show("blacklist")
rows = [r.e.n for r in n2.Rows().values()]
assert rows == ["New Kid", "Mid Way", "Old Timer"], rows
tbl_texts = L2.eval("(function() local t = {} for _, s in ipairs(TEXTS()) do t[#t+1] = s end return t end)()")
assert any("3 players" in str(t) for t in tbl_texts.values())
n2.SetSearch("bloodfang")
assert [r.e.n for r in n2.Rows().values()] == ["Mid Way"]
assert any("1 of 3" in str(t) for t in L2.eval("(function() local t = {} for _, s in ipairs(TEXTS()) do t[#t+1] = s end return t end)()").values())
n2.SetSearch("")
n2.Select("Mid Way")
d = n2.DetailState()
assert "Mid Way" in d.title.text and d.note.text == "ninja'd the Bloodfang" and d.edit.IsShown(d.edit)
lines = [d.lines[i].l.text + "=" + d.lines[i].v.text for i in range(1, 5)]
assert lines[0] == "Reason=Scam" and lines[1].startswith("Added=Jay Doe") and "never edited" in lines[2] and "not seen" in lines[3], lines
# edit from the detail
L2.execute("NOW = NOW + 500")
d.edit.Click(d.edit)
dl = n2.Dialog()
assert dl.IsShown(dl) and dl.note.GetText(dl.note) == "ninja'd the Bloodfang" and dl.reasonID == "scam"
dl.reasonID = "ninja"; dl.note.SetText(dl.note, "ninja'd the Bloodfang Hood")
assert n2.DialogSave()
e = entry(L2, "mid way")
assert e.r == "ninja" and e.note.endswith("Hood") and e.e == L2.eval("NOW") and e.t == BASE + 100
assert "Ninja loot" in d.lines[1].v.text or "Ninja loot" == d.lines[1].v.text
# remove (asks first: the popup), and the row goes
L2.execute("POPUPS = {}")
d.remove.Click(d.remove)
assert L2.eval("POPUPS[1].name") == "KINGMAKER_BLACKLIST_REMOVE" and "Mid Way" in L2.eval("POPUPS[1].text")
e = entry(L2, "mid way")
assert e["del"] is True and e.note is None and e.r is None
assert [r.e.n for r in n2.Rows().values()] == ["New Kid", "Old Timer"]
assert not L2.eval("BlacklistKing.IsListed('Mid Way')")
# sort by name
KM2.Show("blacklist")
assert not KM2.errorShown, last(L2)
print("PAGE OK")

# ---------------------------------------------------------------- 6. your group: silent first read, new members, once a session
L3, KM3, n3 = load()
for nm in ("Evil Guy", "Bad Apple"):
    assert n3.Save(nm, "scam", "bad")[0]
L3.execute("""
GROUP = true; GROUP_SIZE = 3
UNITS.party1 = { name = 'Evil', surname = 'Guy', isPlayer = true, guid = 'Player-1-EVIL' }
UNITS.party2 = { name = 'Nice', surname = 'Person', isPlayer = true }
RAID_NOTICES = {}; OUTPUT = {}
""")
n3.AlertReset()
L3.execute("FIRE('GROUP_ROSTER_UPDATE'); RUN_TIMERS()")
assert L3.eval("#RAID_NOTICES") == 0, "the first read is silent"
assert any("already in your group" in o and "Evil Guy" in o for o in outputs(L3))
assert entry(L3, "evil guy").g == "Player-1-EVIL", "the GUID is learnt"
assert L3.eval("BlacklistKingDB.lists['Kings-Forever'].seen['evil guy']") == BASE
badge = n3.Badge()
assert badge and badge["count"] == 1 and badge.color == "red"
L3.execute("SOUNDS = {}; function PlaySound(id) SOUNDS[#SOUNDS + 1] = id end")
L3.execute("GROUP_SIZE = 4; UNITS.party3 = { name = 'Bad', surname = 'Apple', isPlayer = true }; NOW = NOW + 60")
L3.execute("FIRE('GROUP_ROSTER_UPDATE'); RUN_TIMERS()")
assert L3.eval("#RAID_NOTICES") == 1 and "Bad Apple" in L3.eval("RAID_NOTICES[1]") and "BLACKLISTED" in L3.eval("RAID_NOTICES[1]")
assert L3.eval("#SOUNDS") == 1 and L3.eval("SOUNDS[1]") == 8959
assert "joined your group" in last(L3) and "bad" in last(L3)
assert L3.eval("BlacklistKingDB.lists['Kings-Forever'].seen['bad apple']") == BASE + 60
L3.execute("FIRE('GROUP_ROSTER_UPDATE'); FIRE('GROUP_JOINED'); RUN_TIMERS()")
assert L3.eval("#RAID_NOTICES") == 1, "no repeat"
# they leave and come back: still once a session
L3.execute("GROUP_SIZE = 3; UNITS.party3 = nil; FIRE('GROUP_ROSTER_UPDATE')")
L3.execute("GROUP_SIZE = 4; UNITS.party3 = { name = 'Bad', surname = 'Apple', isPlayer = true }; FIRE('GROUP_ROSTER_UPDATE')")
assert L3.eval("#RAID_NOTICES") == 1
# a name the game doesn't know yet is read again a second later
L3.execute("UNITS.party3 = { name = 'Unknown', isPlayer = true }; FIRE('GROUP_ROSTER_UPDATE')")
assert L3.eval("#TIMERS") >= 1
L3.execute("UNITS.party3 = { name = 'Bad', surname = 'Apple', isPlayer = true }; RUN_TIMERS()")
assert n3.Members()["bad apple"]
# alerts off: nothing
n3.AlertReset()
L3.execute("FIRE('GROUP_ROSTER_UPDATE')")       # silent first read again
L3.execute("BlacklistKingDB.settings.alertJoin = false; GROUP_SIZE = 5; UNITS.party4 = { name = 'Some', surname = 'One', isPlayer = true }")
assert n3.Save("Some One", "toxic", "rude")[0]
L3.execute("FIRE('GROUP_ROSTER_UPDATE')")
assert L3.eval("#RAID_NOTICES") == 1
# a raid
L3.execute("BlacklistKingDB.settings.alertJoin = true; GROUP = false; RAID = true; GROUP_SIZE = 2; UNITS.party1 = nil; UNITS.party2 = nil; UNITS.party3 = nil; UNITS.party4 = nil")
L3.execute("UNITS.raid1 = { name = 'Jay', surname = 'Doe', isPlayer = true }; UNITS.raid2 = { name = 'Evil', surname = 'Guy', isPlayer = true }")
L3.execute("FIRE('GROUP_ROSTER_UPDATE')")
assert n3.Members()["evil guy"] and not n3.Members()["jay doe"], "raid units, never yourself"
print("GROUP OK")

# ---------------------------------------------------------------- 7. invites, chat, tooltips
L3.execute("RAID_NOTICES = {}")
L3.execute("FIRE('PARTY_INVITE_REQUEST', 'Evil Guy', false, false, false, true, false, false, 'Player-1-EVIL')")
assert L3.eval("#RAID_NOTICES") == 1 and "inviting you" in L3.eval("RAID_NOTICES[1]")
L3.execute("FIRE('PARTY_INVITE_REQUEST', 'Evil Guy')")
assert L3.eval("#RAID_NOTICES") == 1, "not twice in 10 seconds"
L3.execute("FIRE('PARTY_INVITE_REQUEST', 'Nice Person')")
assert L3.eval("#RAID_NOTICES") == 1, "only listed players"
assert n3.chatHook == "name" and L3.eval("#SENDER_FILTERS") == 1
tagged = L3.eval("CHAT_NAME('CHAT_MSG_SAY', 'Evil Guy')")
assert tagged.startswith("|cffff2020BLACKLISTED|r ") and tagged.endswith("Evil Guy"), tagged
assert L3.eval("CHAT_NAME('CHAT_MSG_WHISPER', 'Evil Guy-Forever')").startswith("|cffff2020BLACKLISTED")
assert L3.eval("CHAT_NAME('CHAT_MSG_SAY', 'Nice Person')") == "Nice Person"
assert L3.eval("CHAT_NAME('CHAT_MSG_SAY', SECRET('Evil Guy'))") is not None
L3.execute("BlacklistKingDB.settings.chatTag = false")
assert L3.eval("CHAT_NAME('CHAT_MSG_SAY', 'Evil Guy')") == "Evil Guy", "the setting turns it off"
L3.execute("BlacklistKingDB.settings.chatTag = true")
# the fallback message filter puts the tag before the message
mf = n3.ChatMessageFilter
out = L3.eval("function(f) local a, b, c = f(nil, 'CHAT_MSG_SAY', 'hello', 'Evil Guy') return a, b, c end")(mf)
assert out[0] is False and out[1] == "|cffff2020BLACKLISTED|r hello" and out[2] == "Evil Guy"
out = L3.eval("function(f) local a, b, c = f(nil, 'CHAT_MSG_SAY', 'hello', 'Nice Person') return a, b, c end")(mf)
assert out[1] == "hello"
# unit tooltip
L3.execute("UNITS.target = { name = 'Evil', surname = 'Guy', isPlayer = true }")
tip = list(L3.eval("HOVER_UNIT('target')").values())
assert any("BLACKLISTED" in t and "Scam" in t for t in tip) and "bad" in tip, tip
L3.execute("UNITS.target = { name = 'Nice', surname = 'Person', isPlayer = true }")
assert len(L3.eval("HOVER_UNIT('target')")) == 0
tip = list(L3.eval("HOVER_UNIT(nil, 'Player-1-EVIL')").values())
assert any("BLACKLISTED" in t for t in tip), "matched by GUID"
L3.execute("BlacklistKingDB.settings.tooltip = false")
L3.execute("UNITS.target = { name = 'Evil', surname = 'Guy', isPlayer = true }")
assert len(L3.eval("HOVER_UNIT('target')")) == 0
L3.execute("BlacklistKingDB.settings.tooltip = true")
print("CHAT TOOLTIP OK")

# ---------------------------------------------------------------- 8. the group finder (load on demand)
assert not n3.lfgHooked
L3.execute("""
C_LFGList = {
  GetSearchResultInfo = function(id) return LFG[id] end,
  GetSearchResultPlayerInfo = function(id, i) local r = LFG[id]; return r and r.members and r.members[i] end,
}
LFG = {
  [1] = { leaderName = 'Evil Guy', numMembers = 1 },
  [2] = { leaderName = 'Nice Person', numMembers = 3, members = { { name = 'Nice Person' }, { name = 'Bad Apple' }, { name = 'Other Guy' } } },
  [3] = { leaderName = 'Fresh Face', numMembers = 1 },
}
LFG_UPDATES = 0
function LFGBrowseSearchEntry_Update(self) LFG_UPDATES = LFG_UPDATES + 1; self.Name:SetText(LFG[self.resultID].leaderName); self.Name:SetTextColor(1, 1, 1) end
function LFGBrowseSearchEntryTooltip_UpdateAndShow(self, resultID) end
LFGBrowseSearchEntryTooltip = CreateFrame('Frame', 'LFGBrowseSearchEntryTooltip')
function ENTRY(id) local e = CreateFrame('Button'); e.resultID = id; e.Name = e:CreateFontString(); e.DataDisplay = CreateFrame('Frame', nil, e); return e end
ScrollBoxListMixin = { Event = { OnInitializedFrame = 'OnInitializedFrame' } }
LFGWhoListFrame = CreateFrame('Frame', 'LFGWhoListFrame')
LFGWhoListFrame.ScrollBox = CreateFrame('Frame')
WHO_CB = nil
function LFGWhoListFrame.ScrollBox:RegisterCallback(ev, fn, owner) if ev == 'OnInitializedFrame' then WHO_CB = { fn, owner } end end
""")
L3.execute("LOADED_ADDONS['Blizzard_GroupFinder_VanillaStyle'] = true; FIRE('ADDON_LOADED', 'Blizzard_GroupFinder_VanillaStyle')")
assert n3.lfgHooked, "hooked when the group finder loads"
L3.execute("E1 = ENTRY(1); E2 = ENTRY(2); E3 = ENTRY(3); LFGBrowseSearchEntry_Update(E1); LFGBrowseSearchEntry_Update(E2); LFGBrowseSearchEntry_Update(E3)")
assert L3.eval("LFG_UPDATES") == 3, "Blizzard's function still runs"
marks = n3.Marks
m1 = marks[L3.eval("E1")]
assert m1 and m1.text == "BLACKLISTED" and m1.shown, "a listed leader"
assert L3.eval("E1.Name.color[1]") == 1 and abs(L3.eval("E1.Name.color[2]") - 0.13) < 0.01, "tinted red"
assert L3.eval("E1.Name.text") == "Evil Guy", "the name itself is never changed"
assert L3.eval("rawget(E1, 'BlacklistMark')") is None, "nothing stored on Blizzard's frame"
m2 = marks[L3.eval("E2")]
assert m2 and m2.text == "1 BLACKLISTED" and m2.shown, "a group with a listed member"
assert L3.eval("E2.Name.color[2]") == 1, "the leader isn't listed: not tinted"
m3 = marks[L3.eval("E3")]
assert not m3 or not m3.shown
# the listing's tooltip gets our own box
L3.execute("LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 1)")
box = n3.TipBox()
assert box and box.IsShown(box) and "leader Evil Guy" in box.text.text and "Scam" in box.text.text
L3.execute("LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 2)")
assert box.IsShown(box) and "Bad Apple" in box.text.text
L3.execute("LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 3)")
assert not box.IsShown(box)
# Alt-click a listing: blacklist its leader
L3.execute("ALT = true; E3:Click('LeftButton'); ALT = false")
dl = n3.Dialog()
assert dl and dl.IsShown(dl) and "Fresh Face" in dl.nameFixed.text
dl.reasonID = "toxic"; dl.note.SetText(dl.note, "spammed the LFG channel")
assert n3.DialogSave() and L3.eval("BlacklistKing.IsListed('Fresh Face')")
L3.execute("LFGBrowseSearchEntry_Update(E3)")
assert marks[L3.eval("E3")].text == "BLACKLISTED" and marks[L3.eval("E3")].shown
L3.execute("E2:Click('LeftButton')")
assert not dl.IsShown(dl), "a plain click doesn't open it"
# the Who list
assert L3.eval("WHO_CB ~= nil")
L3.execute("W1 = CreateFrame('Button'); W1.Name = W1:CreateFontString(); W1.Name:SetText('Evil Guy'); WHO_CB[1](WHO_CB[2], W1, {})")
assert marks[L3.eval("W1")].text == "BLACKLISTED" and L3.eval("W1.Name.color[2]") < 0.2
L3.execute("W2 = CreateFrame('Button'); W2.Name = W2:CreateFontString(); W2.OriginalName = 'Nice Person-Forever'; WHO_CB[1](WHO_CB[2], W2, {})")
assert not marks[L3.eval("W2")] or not marks[L3.eval("W2")].shown
# marks off
L3.execute("BlacklistKingDB.settings.lfg = false; LFGBrowseSearchEntry_Update(E1)")
assert not marks[L3.eval("E1")].shown
# hooked once only (an already-loaded group finder at login takes the same path)
L3.execute("FIRE('ADDON_LOADED', 'Blizzard_GroupFinder_VanillaStyle'); LFG_UPDATES = 0; LFGBrowseSearchEntry_Update(E1)")
assert L3.eval("LFG_UPDATES") == 1
assert not KM3.errorShown, last(L3)
print("GROUP FINDER OK")

# the group finder already loaded at login
L4, KM4, n4 = load(extra="""
LOADED_ADDONS['Blizzard_GroupFinder_VanillaStyle'] = true
function LFGBrowseSearchEntry_Update(self) end
""")
assert n4.lfgHooked
print("GROUP FINDER AT LOGIN OK")

# ---------------------------------------------------------------- 9. two clients: adds, edits, removals
J, KMJ, nj = load("Jay", "Doe")
B, KMB, nb = load("Bob", "Stone")
clients = [(J, "Jay Doe"), (B, "Bob Stone")]
assert nj.Save("Evil Guy", "scam", "fake Arcanite Reaper")[0]
out = sent(J)
assert len(out) == 1 and out[0].startswith("EEvil Guy~s~"), out
deliver(out, B, "Jay Doe-Forever")
e = entry(B, "evil guy")
assert e and e.n == "Evil Guy" and e.r == "scam" and e.note == "fake Arcanite Reaper" and e.by == "Jay Doe" and e.t == BASE
assert e.g is None
B.execute("RUN_TIMERS()")
assert any("Jay Doe added" in o and "Evil Guy" in o and "guild blacklist" in o for o in outputs(B)), outputs(B)[-3:]
assert B.eval("BlacklistKing.IsListed('Evil Guy')")
assert fp(nj) == fp(nb)
assert B.eval("BlacklistKingDB.lists['Kings-Forever'].heard['Jay Doe']") == BASE
# both edit; the later change wins on both sides, whichever arrives first
clear(J); clear(B)
J.execute("NOW = NOW + 10"); B.execute("NOW = NOW + 5")
assert nj.Save("Evil Guy", "scam", "Jay's later note")[0]
assert nb.Save("Evil Guy", "ninja", "Bob's earlier note")[0]
drain(J); drain(B)
tj, tb = sent(J), sent(B)
deliver(tb, J, "Bob Stone-Forever"); deliver(tj, B, "Jay Doe-Forever")
assert entry(J, "evil guy").note == "Jay's later note" and entry(B, "evil guy").note == "Jay's later note"
assert entry(B, "evil guy").eb is None, "Jay added it and edited it: no separate editor"
assert fp(nj) == fp(nb)
# a tie on e: both settle on the same copy
clear(J); clear(B)
J.execute("NOW = %d" % (BASE + 1000)); B.execute("NOW = %d" % (BASE + 1000))
assert nj.Save("Tie Break", "other", "aaa")[0]
deliver(sent(J), B, "Jay Doe-Forever"); clear(J)
J.execute("NOW = NOW + 50"); B.execute("NOW = NOW + 50")
assert nj.Save("Tie Break", "other", "from jay")[0] and nb.Save("Tie Break", "other", "from bob")[0]
drain(J); drain(B)
tj, tb = sent(J), sent(B)
deliver(tb, J, "Bob Stone-Forever"); deliver(tj, B, "Jay Doe-Forever")
assert entry(J, "tie break").note == entry(B, "tie break").note, "the same winner on both sides"
assert fp(nj) == fp(nb)
# a removal travels as a tombstone and an old copy can't bring them back
clear(J); clear(B)
J.execute("NOW = NOW + 100"); B.execute("NOW = NOW + 100")
stale = nb.Wire(entry(B, "evil guy"))
assert nj.Remove("Evil Guy")[0]
deliver(sent(J), B, "Jay Doe-Forever")
e = entry(B, "evil guy")
assert e["del"] is True and e.e == J.eval("NOW") and e.eb is None and e.by == "Jay Doe" and e.note is None
assert not B.eval("BlacklistKing.IsListed('Evil Guy')")
B.execute("RUN_TIMERS()")
assert any("removed" in o and "Evil Guy" in o for o in outputs(B))
deliver(["E" + stale], J, "Cat Sun-Forever")
deliver(["E" + stale], B, "Cat Sun-Forever")
assert entry(J, "evil guy")["del"] is True and entry(B, "evil guy")["del"] is True, "no resurrection"
assert fp(nj) == fp(nb)
# re-adding after a removal is a fresh entry that beats the tombstone
clear(J); clear(B)
J.execute("NOW = NOW + 100"); B.execute("NOW = NOW + 100")
assert nb.Save("Evil Guy", "toxic", "back again")[0]
deliver(sent(B), J, "Bob Stone-Forever")
e = entry(J, "evil guy")
assert not e["del"] and e.note == "back again" and e.by == "Bob Stone" and e.t == B.eval("NOW")
assert fp(nj) == fp(nb)
print("SYNC EDITS OK")

# ---------------------------------------------------------------- 10. the login fingerprint: silence when in step, catch-up when not
clear(J); clear(B)
nj.SyncReset(); nb.SyncReset()
hello = nj.Hello()
assert hello.startswith("L") and len(hello) < 20
log = exchange(clients)
assert [t[0] for _, t in log] == ["L"], ("in step: only the hello, then silence", log)
# Bob misses three changes while offline, and adds one Jay doesn't have
J.execute("NOW = NOW + 100"); B.execute("NOW = NOW + 100")
J.execute("SENT = {}")
J.execute("BlacklistKingDB.settings.share = false")       # nothing leaves Jay while Bob is "offline"
assert nj.Save("Late One", "scam", "while Bob was away")[0]
assert nj.Save("Tie Break", "toxic", "edited while away")[0]
assert nj.Remove("Bad Apple")[0] is False                 # not on the list
assert nj.Save("Gone Soon", "other", "temp")[0]
assert nj.Remove("Gone Soon")[0]
J.execute("BlacklistKingDB.settings.share = true")
B.execute("BlacklistKingDB.settings.share = false")
assert nb.Save("Bobs Find", "ninja", "only Bob knows")[0]
B.execute("BlacklistKingDB.settings.share = true")
clear(J); clear(B)
nj.SyncReset(); nb.SyncReset()
assert fp(nj) != fp(nb)
nb.Hello()
log = exchange(clients)
kinds = "".join(t[0] for _, t in log)
assert kinds.startswith("LQ"), kinds
assert sum(1 for w, t in log if t[0] == "Q") == 1, "one asker"
assert any(t[0] == "W" for _, t in log), "Bob asks back for what he lacks"
assert fp(nj) == fp(nb), (fp(nj), fp(nb))
assert entry(B, "late one").note == "while Bob was away" and entry(B, "tie break").note == "edited while away"
assert entry(B, "gone soon")["del"] is True
assert entry(J, "bobs find").note == "only Bob knows"
entries_sent = sum(t.count("^") + 1 for _, t in log if t[0] == "E")
# Jay: Late One, Tie Break (edited), Gone Soon (tombstone); Bob: Bobs Find and his older Tie Break (he can't know
# it lost until he sees Jay's). Nothing that matched travels.
assert entries_sent == 5, ("only what differs travels", entries_sent, log)
assert all(len(t) <= 250 for _, t in log)
print("SYNC CATCH-UP OK")

# ---------------------------------------------------------------- 11. a third client with an empty list gets everything; others stand down
C, KMC, nc = load("Cat", "Sun")
clients3 = clients + [(C, "Cat Sun")]
for L_, n_ in ((J, nj), (B, nb)):
    n_.SyncReset()
    clear(L_)
assert fp(nc) == (0, 0)
hello = nc.Hello()
clear(C)
# Jay's random wait ends first: his ask reaches Bob before Bob's own wait is over, so Bob stands down
deliver([hello], J, "Cat Sun-Forever")
drain(J)
first = sent(J)
clear(J)
assert first and first[0].startswith("QCat Sun:"), first
deliver(first, B, "Jay Doe-Forever")
deliver(first, C, "Jay Doe-Forever")
deliver([hello], B, "Cat Sun-Forever")
drain(B)
assert not any(t[0] == "Q" for t in sent(B)), ("whoever asks first, the other stands down", sent(B))
log = [("Jay Doe", t) for t in first] + exchange(clients3)
assert sum(1 for w, t in log if t[0] == "Q") == 1, log
assert fp(nc) == fp(nj) == fp(nb)
assert not any(t[0] == "W" for _, t in log), "an empty list asks for nothing back"
assert C.eval("BlacklistKing.IsListed('Late One')") and not C.eval("BlacklistKing.IsListed('Gone Soon')")
assert entry(C, "gone soon")["del"] is True, "tombstones travel too"
assert any("caught up" in o for o in outputs(C))
print("SYNC THREE OK")

# ---------------------------------------------------------------- 12. limits: message length, 6 a minute out, 30 a minute in
J5, KMJ5, nj5 = load("Jay", "Doe")
for i in range(40):
    J5.execute("NOW = NOW + 1")
    assert nj5.Save("Spam Bot" + chr(97 + i % 26) * (1 + i // 26), "other", "z" * 150)[0]
J5.execute("ADVANCE(1); RUN_TIMERS()")
n_first = len(sent(J5))
assert n_first <= 6, n_first
J5.execute("ADVANCE(30); RUN_TIMERS()")
assert len(sent(J5)) <= 6, "at most 6 a minute"
J5.execute("ADVANCE(31); RUN_TIMERS()")
assert 6 < len(sent(J5)) <= 12
assert all(len(t) <= 250 for t in sent(J5))
B5, KMB5, nb5 = load("Bob", "Stone")
msgs = sent(J5)
J5.execute("ADVANCE(600); RUN_TIMERS()")
msgs = sent(J5)
assert len(msgs) == 40
deliver(msgs, B5, "Jay Doe-Forever")
assert nb5.Count() == 30, ("over 30 a minute from one guildmate is ignored", nb5.Count())
B5.execute("ADVANCE(61)")
deliver(msgs[30:], B5, "Jay Doe-Forever")
assert nb5.Count() == 40
# garbage, secrets, other channels, your own echo
before = nb5.Count()
for bad in ["E", "Ex~s~ww~a~~n", "EEvil Guy~q~wwww~A~~n", "EEvil Guy~s~w~A~~n", "EEvil|Guy~s~ww~A~~n", "EEvil Guy~s~ww~A~~",
            "L!!", "QBob Stone:!", "Wnobody", "Ezz~s~" + "w" * 300]:
    B5.globals().RECV(PREFIX, bad, "Mal Lory-Forever")
B5.execute("RECV('KingMaker1', SECRET('EEvil Guy~s~ww~A~~n'), 'Mal Lory-Forever')")
B5.execute("RECV('KingMaker1', 'EEvil Guy~s~wx~A~~n', 'Mal Lory-Forever', 'WHISPER')")
B5.execute("RECV('KingMaker1', 'EEvil Guy~s~wx~A~~n', 'Bob Stone-Forever')")
assert nb5.Count() == before and not KMB5.errorShown, last(B5)
# a far-future timestamp is refused
far = nb5.Pack(BASE + 10 * DAY)
B5.globals().RECV(PREFIX, "EEvil Guy~s~w" + far + "~A~~n", "Mal Lory-Forever")
assert nb5.Count() == before
print("LIMITS OK")

# ---------------------------------------------------------------- 13. sharing off; no guild = a personal list; InitDB twice
clear(J)
J.execute("BlacklistKingDB.settings.share = false")
assert nj.Save("Quiet One", "other", "not shared")[0]
drain(J)
assert sent(J) == []
J.execute("RECV('KingMaker1', 'EOutside Guy~s~ww~A~~n', 'Bob Stone-Forever')")
assert not J.eval("BlacklistKing.IsListed('Outside Guy')"), "sharing off: not read either"
J.execute("SLASH('/bl share on')")
assert J.eval("BlacklistKingDB.settings.share") is True
P, KMP, np_ = load("Solo", "Wolf", extra="IN_GUILD = false")
assert np_.ListKey() == "personal" and np_.IsPersonal()
assert np_.Save("Evil Guy", "scam", "mine alone")[0]
drain(P)
assert sent(P) == [] and P.eval("BlacklistKingDB.lists.personal.entries['evil guy'].note") == "mine alone"
assert np_.Hello() is None
assert P.eval("BlacklistKing.IsListed('Evil Guy')")
assert np_.IsGuildmate("Evil Guy") is False
KMP.Show("blacklist")
assert not KMP.errorShown, last(P)
# InitDB twice keeps everything
before = (np_.Count(), P.eval("BlacklistKingDB.settings.chatTag"))
np_.InitDB(); np_.InitDB()
assert (np_.Count(), P.eval("BlacklistKingDB.settings.chatTag")) == before
# a broken saved file is repaired
P.execute("BlacklistKingDB.lists.bad = 5; BlacklistKingDB.lists.personal.entries.junk = 'x'")
np_.InitDB()
assert P.eval("BlacklistKingDB.lists.bad") is None and P.eval("BlacklistKingDB.lists.personal.entries.junk") is None
# old removals are forgotten after 60 days, recent ones kept
assert np_.Remove("Evil Guy")[0]
P.execute("NOW = NOW + 61 * 86400")
assert np_.Save("Fresh Gone", "other", "x")[0] and np_.Remove("Fresh Gone")[0]
assert np_.Purge() == 1 and P.eval("BlacklistKingDB.lists.personal.entries['evil guy']") is None
assert P.eval("BlacklistKingDB.lists.personal.entries['fresh gone']") is not None
print("PERSONAL OK")

# ---------------------------------------------------------------- 14. /bl and the API callbacks
L6, KM6, n6 = load()
L6.execute("CB = {}; BlacklistKing.RegisterCallback('test', function(ev, key, how, who) CB[#CB + 1] = ev .. ':' .. tostring(key) .. ':' .. tostring(how) end)")
L6.execute("SLASH('/bl add Evil Guy: scammed me')")
assert L6.eval("BlacklistKing.IsListed('Evil Guy')") and "added Evil Guy" in last(L6)
assert L6.eval("CB[1]") == "CHANGED:evil guy:added"
L6.execute("SLASH('/bl add Some One')")
dl = n6.Dialog()
assert dl.IsShown(dl) and "Some One" in dl.nameFixed.text, "no note: the dialog"
dl.Hide(dl)
L6.execute("UNITS.target = { name = 'Tar', surname = 'Get', isPlayer = true, guid = 'Player-1-TAR' }")
L6.execute("SLASH('/bl add')")
assert dl.IsShown(dl) and "Tar Get" in dl.nameFixed.text, "no name: your target"
dl.Hide(dl)
L6.execute("SLASH('/bl list')")
assert any("Evil Guy" in o for o in outputs(L6))
L6.execute("SLASH('/bl remove evil guy')")
assert not L6.eval("BlacklistKing.IsListed('Evil Guy')") and L6.eval("CB[2]") == "CHANGED:evil guy:removed"
L6.execute("SLASH('/bl help')")
assert any("/bl add" in o for o in outputs(L6))
all_ = L6.eval("BlacklistKing.GetAll()")
assert len(all_) == 0
L6.execute("BlacklistKing.RegisterCallback('bad', function() error('boom') end)")
assert n6.Save("Next One", "other", "x")[0], "a broken callback doesn't break saving"
assert not KM6.errorShown, last(L6)
print("SLASH API OK")

print("ALL BLACKLIST TESTS PASSED")
