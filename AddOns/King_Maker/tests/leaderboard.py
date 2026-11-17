# Guild bests (King Maker 2.7, Modules/Tracker/Guild.lua): two clients, Jay and Bob, in one guild, with their addon
# messages carried between them. Packing within 250 characters, a new personal best sends one update and a slower
# session nothing, the login fingerprint exchange sends only the farms that differ (and the digest brings a guildmate
# who is behind up to date), rate caps, expiry and leaving the guild, opting out, secret and garbage messages, and the
# Farming Ledger's Guild tab: rows, sorting, filters, one farm's rows, tooltips, no redraw in combat.
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from km import fresh, last, outputs

EXTRA = """
ITEM(2318, "Light Leather", { quality = 1, sell = 15, class = 7 })
ITEM(2770, "Copper Ore", { quality = 1, sell = 5, class = 7 })
ITEM(2447, "Peacebloom", { quality = 1, sell = 4, class = 7 })
ITEM(30001, "Forever Bloom", { quality = 2, sell = 50, class = 7 })
for id = 1400, 1460 do MAPS[id] = MAPS[id] or ("Zone " .. id) end
-- A saved session: kind "mob" (coin) or a gathering kind with an item.
function SESS(char, map, kind, value, act, daysAgo, item, lvl)
  local s = TRK.NewSession(char, NOW - daysAgo * 86400 - act)
  s.act, s.map, s.value, s.t1, s.tl, s.lvl = act, map, value, NOW - daysAgo * 86400, nil, lvl
  if kind == "mob" then s.src = { mob = { n = 3, c = value } }; s.coin = value
  else s.src = { [kind] = { n = 5, v = value, i = { [item] = 10 } } }; s.iv = value end
  if item then s.items = { [item] = { q = 10, v = value } } end
  TRK.SaveRecord(s)
  return s
end
"""
ONLY = ["Scanner", "Farm", "Gather", "Tracker"]
PREFIX = "KingMaker1"


def load(name="Jay", extra=""):
    L, KM = fresh(only=ONLY, extra=EXTRA + "PLAYER.name = '%s'; NOW = 20000 * 86400 + 43200\n" % name + extra)
    ns = KM.mods.Tracker
    L.globals().TRK = ns
    assert not KM.errorShown, last(L)
    L.execute("SENT = {}")
    ns.GuildResetSession()
    return L, KM, ns


def sent(L, kinds="FAB"):
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


def drain(L, secs=20):
    L.execute("RUN_TIMERS()")
    for _ in range(secs):
        L.execute("ADVANCE(1); RUN_TIMERS()")


def deliver(texts, dst, sender):
    for t in texts:
        dst.globals().RECV(PREFIX, t, sender)
    dst.execute("RUN_TIMERS()")


def exchange(a, b, a_name, b_name, rounds=6):
    """Carries messages both ways until both fall quiet; returns everything sent, in order, as (from, text)."""
    log = []
    for _ in range(rounds):
        drain(a); drain(b)
        ta, tb = sent(a), sent(b)
        clear(a); clear(b)
        if not ta and not tb:
            break
        log += [(a_name, t) for t in ta] + [(b_name, t) for t in tb]
        deliver(ta, b, a_name + "-Forever")
        deliver(tb, a, b_name + "-Forever")
    return log


def held(L, who):
    return L.eval("TrackerKingDB.guild['Kings-Forever'] and TrackerKingDB.guild['Kings-Forever']['%s']" % who)


def nums(ns, text):
    return list(ns.GuildUnpack(text[1:]).values())


def entries_in(ns, text):
    return (len(nums(ns, text)) - 4) // 6


# ---------------------------------------------------------------- 1. packing and the first catch-up
J, KMJ, nj = load("Jay")
B, KMB, nb = load("Bob")
for n in (0, 31, 32, 1023, 1024, 2147483628, 10 ** 12):
    assert list(nj.GuildUnpack(nj.GuildPack(n)).values()) == [n], n
assert nj.GuildUnpack("B!x") is None, "anything outside the alphabet is not a packed string"
db = J.eval("TrackerKingDB")
assert db.settings.guildShare is True and db.settings.guildShow is True and db.settings.guildDays == 60
assert db.ui.guildAct == "all" and db.ui.guildNear is False and J.eval("type(TrackerKingDB.guild)") == "table"
# Jay has 22 farms with big numbers (high zone IDs and item IDs, hundreds of gold an hour), plus sessions that never count
for i in range(22):
    J.execute("SESS('Jay-Forever', %d, 'herb', %d, %d, %d, 30001, 60)" % (1400 + i, 9000000 + i * 37000, 1800 + i * 7, i % 30))
J.execute("SESS('Jay-Forever', 1453, 'mob', 999999, 300, 1)")              # under 10 active minutes
J.execute("local s = SESS('Jay-Forever', 1454, 'mob', 999999, 3000, 1); s.legacy = true")   # carried over
J.execute("SESS('Jay-Forever', 1458, 'mob', 999999, 3000, 61)")            # older than 60 days
J.execute("SESS('Alt-Forever', 1420, 'mob', 999999, 3000, 1)")             # another character: not Jay's to share
mine = nj.MyBests()
assert len(list(mine.keys())) == 20, "the top 20 farms only"
assert all(not k in ("1453:Mobs", "1454:Mobs", "1458:Mobs", "1420:Mobs") for k in mine.keys()), list(mine.keys())
assert "1400:Herbalism" not in mine and "1421:Herbalism" in mine, "the slowest two left out"
e = mine["1421:Herbalism"]
assert e.g % 100 == 0 and e.n == (1800 + 21 * 7) // 60 and e.i == 30001 and e.l == 60 and e.a == "Herbalism" and e.m == 1421
# Jay says hello; Bob has nothing of Jay's, asks; Jay answers in as few messages as fit
hello = nj.GuildHello(True)
assert hello.startswith("F") and len(hello) < 20, hello
log = exchange(J, B, "Jay", "Bob")
kinds = "".join(t[0] for _, t in log)
assert kinds.startswith("FAB"), kinds
asks = [t for w, t in log if t[0] == "A"]
assert len(asks) == 1 and asks[0].startswith("AJay:"), asks
answer = [t for w, t in log if w == "Jay" and t[0] == "B"]
assert len(answer) == 2, ("20 bests take two messages", [len(t) for t in answer])
assert sum(entries_in(nj, t) for t in answer) == 20
assert all(len(t) <= 250 for t in answer) and max(len(t) for t in answer) > 200, [len(t) for t in answer]
jay = held(B, "Jay")
assert jay and len(list(jay.farms.keys())) == 20
assert list(nb.GuildFingerprint(jay.farms)) == list(nj.GuildFingerprint(nj.MyBests())), "Bob's copy is Jay's set exactly"
assert jay.f == nj.GuildFingerprint(nj.MyBests())[1], "and Bob knows it is in step"
f = jay.farms["1421:Herbalism"]
assert f.g == e.g and f.n == e.n and f.i == 30001 and f.l == 60 and f.m == 1421 and f.a == "Herbalism"
assert J.eval("TrackerKingDB.guild['Kings-Forever']") is None, "Bob shares nothing yet, so Jay holds nothing"
assert not KMJ.errorShown and not KMB.errorShown, (last(J), last(B))
print("PACKING OK")

# ---------------------------------------------------------------- 2. a new personal best sends one update; a slower session nothing
clear(J)
J.execute("TrackerKingDB.settings.idlePause = 0; PLAYER.map = 1440")
farm = J.eval("SlashCmdList.KINGMAKERFARM")


def coin_session(L, copper, secs):
    farm = L.eval("SlashCmdList.KINGMAKERFARM")
    farm("start")
    L.execute("ADVANCE(%d)" % secs)
    L.execute("TRK.CreditCoin('mob', 299, %d)" % copper)
    farm("stop")
    L.execute("RUN_TIMERS()")


coin_session(J, 20000000, 1200)                # Ashenvale mobs: 600g/hr, a new farm in the top 20
out = sent(J)
assert len(out) == 1 and out[0][0] == "B", out
assert entries_in(nj, out[0]) == 2, "the new best, and the farm it pushed out of the top 20"
deliver(out, B, "Jay-Forever")
jay = held(B, "Jay")
assert jay.farms["1440:Mobs"].g == 60000000 and len(list(jay.farms.keys())) == 20
assert jay.f == nj.GuildFingerprint(nj.MyBests())[1], "still in step after the update"
clear(J)
coin_session(J, 10000000, 1200)                # slower at the same farm: not a best
drain(J)
assert sent(J) == [], "a session that sets no best sends nothing"
coin_session(J, 30000, 300)                    # under 10 minutes: never a best
drain(J)
assert sent(J) == []
print("NEW BEST OK")

# ---------------------------------------------------------------- 3. the login fingerprint: only what differs
# Jay beats one farm while Bob isn't listening, then logs in again
nj.GuildResetSession()
J.execute("SESS('Jay-Forever', 1421, 'herb', 99000000, 1800, 0, 30001, 60)")
clear(J)
nj.GuildHello(True)
log = exchange(J, B, "Jay", "Bob")
answer = [t for w, t in log if w == "Jay" and t[0] == "B"]
assert len(answer) == 1 and entries_in(nj, answer[0]) == 1, ("one farm differs, one entry", log)
assert held(B, "Jay").farms["1421:Herbalism"].g == round(99000000 / 1800 * 3600 / 100) * 100
assert list(nb.GuildFingerprint(held(B, "Jay").farms)) == list(nj.GuildFingerprint(nj.MyBests()))
# in step: the next login's fingerprint gets no ask at all
nj.GuildResetSession(); nb.GuildResetSession()
nj.GuildHello(True)
log = exchange(J, B, "Jay", "Bob")
assert [t[0] for _, t in log] == ["F"], log
# a farm Jay no longer has (its session deleted) goes from Bob's copy too
key = "1405:Herbalism"
assert key in list(held(B, "Jay").farms.keys())
J.execute("for i = #TrackerKingDB.sessions, 1, -1 do local s = TrackerKingDB.sessions[i]; if s.map == 1405 then table.remove(TrackerKingDB.sessions, i) end end")
nj.GuildResetSession(); nb.GuildResetSession()
nj.GuildHello(True)
log = exchange(J, B, "Jay", "Bob")
answer = [t for w, t in log if w == "Jay" and t[0] == "B"]
assert len(answer) == 1 and entries_in(nj, answer[0]) == 2, ("a drop, and the farm that moved up into the top 20", log)
assert key not in list(held(B, "Jay").farms.keys())
assert list(nb.GuildFingerprint(held(B, "Jay").farms)) == list(nj.GuildFingerprint(nj.MyBests()))
# Bob farms too: he shares when he logs in, with a digest of whose bests he holds
B.execute("SESS('Bob-Forever', 1436, 'mob', 900000, 1200, 0, nil, 41)")
nb.GuildResetSession(); nj.GuildResetSession()
nb.GuildHello(True)
log = exchange(J, B, "Jay", "Bob")
assert held(J, "Bob") and held(J, "Bob").farms["1436:Mobs"].g == 2700000 and held(J, "Bob").farms["1436:Mobs"].l == 41
assert not [t for w, t in log if w == "Jay" and t[0] == "F"], "Bob's digest says he holds Jay's latest: Jay stays quiet"
# Bob is behind on Jay (Jay set a best while Bob was offline): Bob's login digest makes Jay post his fingerprint again
J.execute("SESS('Jay-Forever', 1402, 'herb', 99000000, 1800, 0, 30001, 60)")
nb.GuildResetSession(); nj.GuildResetSession()
nb.GuildHello(True)
log = exchange(J, B, "Jay", "Bob")
seq = [(w, t[0]) for w, t in log]
assert ("Jay", "F") in seq and ("Bob", "A") in seq, seq
assert list(nb.GuildFingerprint(held(B, "Jay").farms)) == list(nj.GuildFingerprint(nj.MyBests())), "caught up"
jayF = [t for w, t in log if w == "Jay" and t[0] == "F"][0]
assert len(nums(nj, jayF)) == 2, "the repost carries no digest (no cascade)"
print("FINGERPRINT OK")

# ---------------------------------------------------------------- 4. a third guildmate stands down when someone else asked
C, KMC, nc = load("Cat")
nj.GuildResetSession()
clear(J)
nj.GuildHello(True)
drain(J)
hello = sent(J)
clear(J)
C.globals().RECV(PREFIX, hello[0], "Jay-Forever")         # Cat is behind on Jay: its ask waits 2-8 s
C.globals().RECV(PREFIX, "ACat Nobody:w", "Bob-Forever")   # an ask for someone else: nothing to do with Jay
C.globals().RECV(PREFIX, "AJay:w", "Bob-Forever")          # Bob asks for Jay first
C.execute("RUN_TIMERS()")
assert [t for t in sent(C) if t[0] == "A"] == [], "Cat stands down for Bob's answer (and looks again once, still held)"
C.execute("for i = 1, 31 do ADVANCE(1) end")
C.globals().RECV(PREFIX, hello[0], "Jay-Forever")         # Bob's answer never came: the next fingerprint
C.execute("RUN_TIMERS()")
asks = [t for t in sent(C) if t[0] == "A"]
assert len(asks) == 1 and asks[0].startswith("AJay:"), asks
C.globals().RECV(PREFIX, hello[0], "Jay-Forever")
C.execute("RUN_TIMERS(); for i = 1, 5 do ADVANCE(1) end")
assert len([t for t in sent(C) if t[0] == "A"]) == 1, "the same fingerprint is asked about once a session"
print("STAND DOWN OK")

# ---------------------------------------------------------------- 5. rate caps
clear(J)
nj.GuildResetSession()
for _ in range(20):
    nj.GuildHello(False)
assert len(sent(J)) == 1, "one now; the rest wait their turn"
assert len(list(nj.GuildQueue().values())) == 12, "the queue holds 12 at most; the rest are dropped"
J.execute("for i = 1, 59 do ADVANCE(1) end")
assert len(sent(J)) == 6, ("at most 6 messages in any minute", len(sent(J)))
J.execute("for i = 1, 120 do ADVANCE(1) end")
assert len(sent(J)) == 13 and len(list(nj.GuildQueue().values())) == 0
# answers: a few per 10 minutes, and the same ask twice is answered once
clear(J)
nj.GuildResetSession()
for who in ["Ann", "Ben", "Cid", "Dee", "Eve", "Fay"]:
    J.globals().RECV(PREFIX, "AJay:w", who + "-Forever")
J.globals().RECV(PREFIX, "AJay:w", "Ann-Forever")
J.execute("for i = 1, 120 do ADVANCE(1) end")
answers = [t for t in sent(J) if t[0] == "B"]
assert len(answers) == 4 * 2, ("4 answers of 2 parts in 10 minutes", len(answers))
# inbound: past 30 messages a minute from one guildmate, the rest are ignored
nj.GuildResetSession()
for i in range(30):
    J.globals().RECV(PREFIX, "Fw" + nj.GuildPack(i + 1), "Zed-Forever")
st = nj.GuildState()
assert st.lastF["Zed"].h == 30
J.globals().RECV(PREFIX, "Fw" + nj.GuildPack(99), "Zed-Forever")
assert nj.GuildState().lastF["Zed"].h == 30, "the 31st in a minute is dropped"
J.execute("for i = 1, 61 do ADVANCE(1) end")
J.globals().RECV(PREFIX, "Fw" + nj.GuildPack(99), "Zed-Forever")
assert nj.GuildState().lastF["Zed"].h == 99
print("RATE CAPS OK")

# ---------------------------------------------------------------- 6. expiry and leaving the guild
J, KMJ, nj = load("Jay")
J.execute("""TrackerKingDB.guild['Kings-Forever'] = {
  Bob = { t = NOW, f = 5, farms = { ['1436:Mobs'] = { m = 1436, a = 'Mobs', g = 100000, n = 20, t = NOW - 10 * 86400 },
                                    ['1429:Mobs'] = { m = 1429, a = 'Mobs', g = 900000, n = 20, t = NOW - 61 * 86400 } } },
  Old = { t = NOW - 70 * 86400, farms = { ['1429:Mobs'] = { m = 1429, a = 'Mobs', g = 50000, n = 20, t = NOW - 70 * 86400 } } },
  Cat = { t = NOW, farms = { ['1440:Mixed'] = { m = 1440, a = 'Mixed', g = 70000, n = 30, t = NOW - 5 * 86400 } } },
}
TrackerKingDB.guild['Other Guild-Forever'] = { Zed = { t = NOW - 100 * 86400, farms = { ['1429:Mobs'] = { m = 1429, a = 'Mobs', g = 1, n = 20, t = NOW - 100 * 86400 } } } }""")
nj.GuildPrune()
g = J.eval("TrackerKingDB.guild['Kings-Forever']")
assert g.Bob.farms["1429:Mobs"] is None and g.Bob.farms["1436:Mobs"] is not None, "older than 60 days goes"
assert g.Old is None, "a guildmate with nothing left, not heard from in 60 days, goes"
assert J.eval("TrackerKingDB.guild['Other Guild-Forever']") is None, "every guild's data expires"
J.execute("TrackerKingDB.settings.guildDays = 30; TrackerKingDB.guild['Kings-Forever'].Bob.farms['1436:Mobs'].t = NOW - 40 * 86400")
nj.GuildPrune()
assert J.eval("next(TrackerKingDB.guild['Kings-Forever'].Bob.farms)") is None, "the setting decides"
J.execute("TrackerKingDB.settings.guildDays = 60")
# the roster has loaded (you're on it) and Cat isn't: Cat left the guild
J.execute("GUILD_ROSTER = { { name = 'Jay-Forever', class = 'WARRIOR' }, { name = 'Bob-Forever', class = 'MAGE' } }")
nj.GuildRosterReset(); nj.GuildPrune()
assert J.eval("TrackerKingDB.guild['Kings-Forever'].Cat") is None and J.eval("TrackerKingDB.guild['Kings-Forever'].Bob") is not None
# a roster that hasn't loaded (you aren't on it yet) removes nobody
J.execute("TrackerKingDB.guild['Kings-Forever'].Dan = { t = NOW, farms = { ['1440:Mixed'] = { m = 1440, a = 'Mixed', g = 70000, n = 30, t = NOW } } }")
J.execute("GUILD_ROSTER = { { name = 'Bob-Forever', class = 'MAGE' } }")
nj.GuildRosterReset(); nj.GuildPrune()
assert J.eval("TrackerKingDB.guild['Kings-Forever'].Dan") is not None
J.execute("GUILD_ROSTER = nil"); nj.GuildRosterReset()
print("EXPIRY OK")

# ---------------------------------------------------------------- 7. opting out
J, KMJ, nj = load("Jay")
B, KMB, nb = load("Bob")
J.execute("SESS('Jay-Forever', 1436, 'mob', 900000, 1200, 0)")
J.eval("SlashCmdList.KINGMAKERFARM")("guild off")
assert J.eval("TrackerKingDB.settings.guildShare") is False and J.eval("TrackerKingDB.settings.guildShow") is False
assert "guild bests off" in last(J)
assert nj.GuildHello(True) is None and sent(J) == [], "sharing off: no fingerprint"
J.globals().RECV(PREFIX, "AJay:w", "Bob-Forever")
J.execute("SESS('Jay-Forever', 1440, 'mob', 9000000, 1200, 0); TRK.Fire('SESSION_SAVED')")
drain(J)
assert sent(J) == [], "no answer, no new-best update"
# sharing off but showing on: still reads what guildmates send, never asks
KMJ.OpenSettings("tracker")
J.execute('for _, f in ipairs(FRAMES) do if type(rawget(f, "label")) == "table" and f.label.text == "Show guild bests" and f.SetChecked and rawget(f, "mark") then f:Click() end end')
assert J.eval("TrackerKingDB.settings.guildShow") is True and J.eval("TrackerKingDB.settings.guildShare") is False
B.execute("SESS('Bob-Forever', 1436, 'mob', 900000, 1200, 0)")
clear(B)
nb.GuildHello(True)
drain(B)
deliver(sent(B), J, "Bob-Forever")
drain(J)
assert sent(J) == [], "behind on Bob, but asking is sending"
clear(B)
B.execute("SESS('Bob-Forever', 1429, 'mob', 9000000, 1200, 0); TRK.Fire('SESSION_SAVED')")
drain(B)
upd = sent(B)
assert len(upd) == 1
deliver(upd, J, "Bob-Forever")
assert held(J, "Bob").farms["1429:Mobs"].g == 27000000, "a live update still arrives"
# showing off: nothing is read
nj.SetGuildShow(False)
B.execute("SESS('Bob-Forever', 1440, 'mob', 9900000, 1200, 0); TRK.Fire('SESSION_SAVED')")
clear(B); drain(B)
deliver(sent(B), J, "Bob-Forever")
assert held(J, "Bob").farms["1440:Mobs"] is None
J.eval("SlashCmdList.KINGMAKERFARM")("guild on")
assert J.eval("TrackerKingDB.settings.guildShare") is True and J.eval("TrackerKingDB.settings.guildShow") is True
drain(J)
assert [t[0] for t in sent(J)] == ["F"], "turned back on: one hello"
J.eval("SlashCmdList.KINGMAKERFARM")("guild")
assert J.eval("TrackerKingDB.settings.guildShare") is False, "no argument toggles"
J.eval("SlashCmdList.KINGMAKERFARM")("guild on")
# not in a guild: nothing is sent
J.execute("IN_GUILD = false")
clear(J); nj.GuildResetSession()
assert nj.GuildHello(True) is None and sent(J) == []
J.execute("IN_GUILD = true")
print("OPT OUT OK")

# ---------------------------------------------------------------- 8. secret and garbage messages
J, KMJ, nj = load("Jay")
before = J.eval("TrackerKingDB.guild['Kings-Forever']")
bad = [
    ("B", None), ("Bxx", None), ("F", None), ("B!!!!", None), ("Xwww", None), ("A", None), ("A:w", None),
    ("AJay", None), ("Bwwwwwwww", None),                                   # ragged entries
    ("Bwwwx" + "w" * 6, None),                                             # zone 0, activity 0
    ("Bwwxx" + "1v9w" + "w" * 5, None),                                    # part 2 of 1
    ("Bwwww" + "1KxA" + "wwww", None),                                     # a short entry
    ("B" + "vvvvvvvvvvvvvvvvvw" * 3, None),                                # numbers far too big
    ("V2.9.0", None), ("R2.9.0", None),                                    # the version check's
]
for text, _ in bad:
    J.globals().RECV(PREFIX, text, "Bob-Forever")
J.globals().RECV(PREFIX, "F" + "w" * 300, "Bob-Forever")                    # too long
J.execute('RECV("KingMaker1", SECRET("Fww"), "Bob-Forever")')
J.execute('RECV("KingMaker1", "Fww", SECRET("Bob-Forever"))')
J.execute('FIRE("CHAT_MSG_ADDON", SECRET("KingMaker1"), "Fww", "GUILD", "Bob-Forever")')
J.execute('FIRE("CHAT_MSG_ADDON", "KingMaker1", "Fww", SECRET("GUILD"), "Bob-Forever")')
J.execute('RECV("KingMaker1", "Fww", "Bob-Forever", "WHISPER")')           # guild channel only
J.execute('FIRE("CHAT_MSG_ADDON", "KingMaker1", "Fww", "GUILD", nil)')
J.execute('FIRE("CHAT_MSG_ADDON", "KingMaker1", nil, "GUILD", "Bob-Forever")')
J.execute('FIRE("CHAT_MSG_ADDON", "KingMaker1", 42, "GUILD", "Bob-Forever")')
J.execute("RUN_TIMERS()")
assert not KMJ.errorShown, last(J)
assert J.eval("TrackerKingDB.guild['Kings-Forever']") is None or J.eval("next(TrackerKingDB.guild['Kings-Forever'].Bob and TrackerKingDB.guild['Kings-Forever'].Bob.farms or {})") is None
assert nj.GuildState().lastF["Bob"] is None, "nothing taken from a secret, a whisper or a broken message"
# a good entry among bad ones: the bad one is skipped, the good one kept
good_code = nj.GuildPack(1436 * 8 + 1) + nj.GuildPack(500) + nj.GuildPack(20) + nj.GuildPack(20000) + nj.GuildPack(2318) + nj.GuildPack(30)
bad_day = nj.GuildPack(1429 * 8 + 1) + nj.GuildPack(500) + nj.GuildPack(20) + nj.GuildPack(10000) + nj.GuildPack(0) + nj.GuildPack(0)
J.globals().RECV(PREFIX, "Bwwxx" + good_code + bad_day, "Bob-Forever")
bob = held(J, "Bob")
assert bob.farms["1436:Mobs"].g == 50000 and bob.farms["1429:Mobs"] is None, "a day long ago is not a best"
# a two-part answer: part 1 brings a slow new farm, part 2 drops a stale fast one; the copy is cut to 20 only at the end
J.execute("""local farms = {}
for i = 1, 19 do farms[(1300 + i) .. ':Mobs'] = { m = 1300 + i, a = 'Mobs', g = (1000 + i) * 100, n = 20, t = NOW } end
farms['1299:Mobs'] = { m = 1299, a = 'Mobs', g = 99999900, n = 20, t = NOW }
TrackerKingDB.guild['Kings-Forever'].Zed = { t = NOW, farms = farms }""")
P_ = nj.GuildPack
slow = P_(1350 * 8 + 1) + P_(500) + P_(20) + P_(20000) + P_(0) + P_(0)
J.globals().RECV(PREFIX, "B" + P_(0) + P_(77) + P_(1) + P_(2) + slow, "Zed-Forever")
assert held(J, "Zed").farms["1350:Mobs"] is not None, "not cut while part 2 is still to come"
J.globals().RECV(PREFIX, "B" + P_(0) + P_(77) + P_(2) + P_(2) + P_(1299 * 8 + 1) + "wwwww", "Zed-Forever")
zed = held(J, "Zed")
assert zed.farms["1299:Mobs"] is None and zed.farms["1350:Mobs"] is not None and len(list(zed.farms.keys())) == 20, len(list(zed.farms.keys()))
J.globals().RECV(PREFIX, "B" + P_(77) + P_(78) + P_(1) + P_(1) + P_(1351 * 8 + 1) + P_(400) + P_(20) + P_(20000) + "www", "Zed-Forever")
zed = held(J, "Zed")
assert len(list(zed.farms.keys())) == 20 and zed.farms["1351:Mobs"] is None, "a 21st, slowest of all, is cut at once"
# your own message coming back is never read
J.globals().RECV(PREFIX, "Bwwxx" + good_code.replace(nj.GuildPack(1436 * 8 + 1), nj.GuildPack(1440 * 8 + 1)), "Jay-Forever")
assert held(J, "Jay") is None
print("GARBAGE OK")

# ---------------------------------------------------------------- 9. the Guild tab
J, KMJ, nj = load("Jay", extra="PLAYER.level = 42")
J.execute("""
GUILD_ROSTER = { { name = 'Jay-Forever', class = 'WARRIOR' }, { name = 'Bob-Forever', class = 'MAGE' }, { name = 'Cat-Forever', class = 'DRUID' } }
FarmKingDB.mobs[299] = { name = 'Wolf', k = 5, lmin = 10, lmax = 12, z = { [1429] = 5 } }
FarmKingDB.mobs[300] = { name = 'Ghoul', k = 5, lmin = 40, lmax = 44, z = { [1423] = 5 } }
SESS('Jay-Forever', 1429, 'mob', 600000, 1200, 2, nil, 11)         -- Elwynn mobs: 18g/hr, levels 10-12
SESS('Jay-Forever', 1423, 'mob', 1200000, 1200, 1, nil, 42)        -- Eastern Plaguelands mobs: 36g/hr
SESS('Alt-Forever', 1436, 'mine', 300000, 1200, 3, 2770, 20)       -- an alt: Westfall mining 9g/hr
TrackerKingDB.guild['Kings-Forever'] = {
  Bob = { t = NOW - 3600, f = 1, farms = {
    ['1429:Mobs'] = { m = 1429, a = 'Mobs', g = 2400000, n = 25, t = NOW - 86400, i = 2318, l = 12 },
    ['1440:Mixed'] = { m = 1440, a = 'Mixed', g = 1500000, n = 40, t = NOW - 2 * 86400, l = 30 } } },
  Cat = { t = NOW - 7200, farms = {
    ['1423:Mobs'] = { m = 1423, a = 'Mobs', g = 3000000, n = 60, t = NOW - 86400, i = 2447, l = 43 },
    ['1436:Mining'] = { m = 1436, a = 'Mining', g = 1000000, n = 30, t = NOW - 86400, i = 2770, l = 22 } } },
}""")
J.eval("SlashCmdList.KINGMAKER")("farming")
P, G = nj.P, nj.G
J.execute("TRK.P.tabs.buttons.guild:Click()")
assert J.eval("TrackerKingDB.ui.tab") == "guild" and P.guild.shown and not P.list.shown and not KMJ.errorShown, last(J)
assert not P.periods.shown and not P.export.shown and not P.charBtn.shown, "no period, export or character filter here"
assert "best gold per hour at each farm across your guild" in KMJ.pages.farming.subtitle()
rows = list(G.board.data.values())
assert [r.key for r in rows] == ["1423:Mobs", "1429:Mobs", "1440:Mixed", "1436:Mining"], [r.key for r in rows]
ep = rows[0]
assert ep.best.who == "Jay" and ep.best.mine and ep.best.g == 3600000 and ep.you.who == "Jay", "yours beats Cat's 30g"
el = rows[1]
assert el.best.who == "Bob" and el.you.g == 1800000 and el.levels.lo == 10 and el.levels.hi == 12
wm = rows[3]
assert wm.best.who == "Cat" and wm.you.who == "Alt" and wm.you.g == 900000, "your alt counts as you"
t = [str(x) for x in J.eval("TEXTS()").values()]
for label in ("FARMS", "GUILD'S BEST", "YOUR BEST", "YOU LEAD", "GUILDMATES", "SHARING", "GUILD BEST  v", "WHO", "TOP ITEM"):
    assert label in t, label
assert G.tiles[1].value.text == "4" and G.tiles[4].value.text == "1" and G.tiles[4].sub.text == "of 3 you farmed", (G.tiles[4].value.text, G.tiles[4].sub.text)
assert G.tiles[5].value.text == "2" and G.tiles[6].value.text == "On"
mage = J.eval("string.format('|cff%02x%02x%02x', RAID_CLASS_COLORS.MAGE.r * 255, RAID_CLASS_COLORS.MAGE.g * 255, RAID_CLASS_COLORS.MAGE.b * 255)")
row = [r for r in G.board.rows.values() if r.data and r.data.key == "1429:Mobs"][0]
assert row.cells.who.text.startswith(mage + "Bob"), ("class-coloured", row.cells.who.text)
assert "Light Leather" in row.cells.item.text and "Elwynn Forest" == row.cells.zone.text
# every tile and row explains itself
for i in range(1, 7):
    tile = G.tiles[i]
    J.execute("GameTooltip.lines = {}")
    tile.RunScript(tile, "OnEnter")
    assert len(list(J.eval("GameTooltip.lines").values())) >= 2, ("tile without a tooltip", i)
J.execute("GameTooltip.lines = {}")
row.RunScript(row, "OnEnter")
lines = [str(x) for x in J.eval("GameTooltip.lines").values()]
assert any("Zone levels" in x for x in lines) and any("Click for everyone" in x for x in lines), lines
# sorting by a header
J.execute("TRK.G.board.headers.zone:Click()")
assert [r.key for r in G.board.data.values()][0] == "1440:Mixed", "Ashenvale first by zone name"
J.execute("TRK.G.board.headers.gph:Click()")
assert [r.key for r in G.board.data.values()][0] == "1423:Mobs", "back to gold per hour, best first"
# filters: activity
J.execute("TRK.G.acts.buttons.gathering:Click()")
assert J.eval("TrackerKingDB.ui.guildAct") == "gathering" and [r.key for r in G.board.data.values()] == ["1436:Mining"]
J.execute("TRK.G.acts.buttons.mobs:Click()")
assert [r.key for r in G.board.data.values()] == ["1423:Mobs", "1429:Mobs"]
J.execute("TRK.G.acts.buttons.all:Click()")
# near my level (42): Elwynn's mobs are 10-12 (out); Plaguelands 40-44 (in); Ashenvale has no mob data: Bob was 30 (out);
# Westfall: no mob data, Cat was 22 (out)
J.execute("TRK.G.near.frame:Click()")
assert J.eval("TrackerKingDB.ui.guildNear") is True
assert [r.key for r in G.board.data.values()] == ["1423:Mobs"], [r.key for r in G.board.data.values()]
assert nj.GuildNear(J.eval("{ best = {} }")) is True, "no levels known: it shows"
J.execute("TRK.G.near.frame:Click()")
# a farm's rows: everyone's best there
row = [r for r in G.board.rows.values() if r.data and r.data.key == "1423:Mobs"][0]
row.Click(row, "LeftButton")
assert G.rows.shown and not G.board.shown and G.back.shown and "Eastern Plaguelands, Mobs" in G.back.label.text
ent = list(G.rows.data.values())
assert [e.who for e in ent] == ["Jay", "Cat"] and ent[0].mine, [e.who for e in ent]
r0 = [r for r in G.rows.rows.values() if r.data and r.data.who == "Cat"][0]
assert r0.cells.lvl.text == "43" and "Peacebloom" in r0.cells.item.text
J.execute("GameTooltip.lines = {}")
r0.RunScript(r0, "OnEnter")
assert len(list(J.eval("GameTooltip.lines").values())) >= 3
J.execute("TRK.G.back:Click()")
assert G.board.shown and not G.rows.shown and not G.back.shown
# it lays out from the container: a wider page widens the tiles
w0 = G.tiles[1].w
J.execute("RESIZE(TRK.P.container, 1100, 600); RUN_TIMERS()")
assert G.tiles[1].w > w0, (w0, G.tiles[1].w)
# a guild best arriving in combat waits for the fight to end before the page redraws
J.execute("REFRESHES = 0; local orig = TRK.RefreshGuild; TRK.RefreshGuild = function(...) REFRESHES = REFRESHES + 1; return orig(...) end")
J.execute("COMBAT = true")
code = nj.GuildPack(1458 * 8 + 1) + nj.GuildPack(800) + nj.GuildPack(20) + nj.GuildPack(20000) + nj.GuildPack(0) + nj.GuildPack(0)
J.globals().RECV(PREFIX, "Bwwxx" + code, "Bob-Forever")
J.execute("RUN_TIMERS()")
assert J.eval("REFRESHES") == 0, "no UI work in combat"
assert held(J, "Bob").farms["1458:Mobs"] is not None, "the message itself is read"
J.execute("COMBAT = false; FIRE('PLAYER_REGEN_ENABLED'); RUN_TIMERS()")
assert J.eval("REFRESHES") >= 1
# a fresh guild record says so in chat, once
assert any("Bob set a new guild best" in o for o in outputs(J)) is False, "Undercity had no best before: nothing beaten"
code = nj.GuildPack(1423 * 8 + 1) + nj.GuildPack(40000) + nj.GuildPack(20) + nj.GuildPack(20000) + nj.GuildPack(0) + nj.GuildPack(0)
J.globals().RECV(PREFIX, "Bwwxx" + code, "Bob-Forever")
J.execute("RUN_TIMERS()")
assert any("Bob set a new guild best: Eastern Plaguelands (Mobs)" in o for o in outputs(J)), outputs(J)[-3:]
# showing off, not in a guild: the tab says why it's empty
nj.SetGuildShow(False)
J.execute("RUN_TIMERS()")
assert "Show guild bests" in G.board.emptyText and len(list(G.board.data.values())) == 3, "your own farms still show"
nj.SetGuildShow(True)
assert not KMJ.errorShown, last(J)
print("GUILD TAB OK")

print("leaderboard: ok")
