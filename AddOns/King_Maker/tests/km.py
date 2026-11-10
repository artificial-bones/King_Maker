# Shared loader for King Maker's tests: a Lua 5.1 runtime with tests/mock.lua (the workspace's wow_mock), then
# every file King_Maker.toc lists, in order, run with ("King_Maker", KM) as `...` exactly like the game.
#
#   from km import fresh, ROOT
#   L, KM = fresh()                                   # whole addon, ADDON_LOADED + PLAYER_LOGIN fired
#   L, KM = fresh(seed="ScannerKingDB = {...}")       # saved variables as the game would load them
#   L, KM = fresh(only=["Scanner", "Econ"])           # core + just these modules (faster, isolates a suite)
#   L, KM = fresh(stubs={"Scanner_King": "ScannerKingDB = {...}"})   # legacy folders loading after King Maker
#   L, KM = fresh(login=False)                        # stop before the load events
#
# Module suites live in tests/<module>.py and run with: python tests/run.py   (from the King_Maker folder)
import os
import re
from lupa import lua51

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ADDON = "King_Maker"


def toc_files():
    files = []
    for line in open(os.path.join(ROOT, f"{ADDON}.toc"), encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def toc_meta():
    meta = {}
    for line in open(os.path.join(ROOT, f"{ADDON}.toc"), encoding="utf-8-sig"):
        m = re.match(r"^##\s*([^:]+):\s*(.*)$", line.strip())
        if m:
            meta[m.group(1).strip()] = m.group(2).strip()
    return meta


def module_of(path):
    m = re.match(r"Modules/([^/]+)/", path)
    return m.group(1) if m else None


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fresh(seed=None, only=None, stubs=None, login=True, extra=None, oldcode=None):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(os.path.join(ROOT, "tests", "mock.lua"), encoding="utf-8").read())
    meta = toc_meta()
    L.execute("ADDON_META[%s] = { Version = %s, Title = %s }" % (lua_str(ADDON), lua_str(meta.get("Version", "2")), lua_str(meta.get("Title", ADDON))))
    for name in (stubs or {}):
        L.execute("ADDON_META[%s] = { Version = '2.0.0', ['X-KingMaker-Stub'] = '1' }" % lua_str(name))
    for name in (oldcode or {}):
        L.execute("ADDON_META[%s] = { Version = '1.6.0' }" % lua_str(name))
    if seed:
        L.execute(seed)
    if extra:
        L.execute(extra)
    KM = L.table()
    for f in toc_files():
        if f.lower().startswith("libs/"):
            continue            # the mock provides LibStub and HereBeDragons
        mod = module_of(f)
        if only is not None and mod is not None and mod not in only:
            continue
        code = open(os.path.join(ROOT, f), encoding="utf-8-sig").read()
        try:
            L.execute(code, ADDON, KM)
        except Exception as e:
            raise RuntimeError(f"{f}: {e}") from None
    if login:
        L.execute('LOADED_ADDONS["King_Maker"] = true; FIRE("ADDON_LOADED", "King_Maker")')
        for name, sv in (stubs or {}).items():
            if sv:
                L.execute(sv)
            L.execute('LOADED_ADDONS[%s] = true; FIRE("ADDON_LOADED", %s)' % (lua_str(name), lua_str(name)))
        for name, sv in (oldcode or {}).items():
            L.execute('LOADED_ADDONS[%s] = true; FIRE("ADDON_LOADED", %s)' % (lua_str(name), lua_str(name)))
        L.execute('FIRE("PLAYER_LOGIN"); FIRE("PLAYER_ENTERING_WORLD", true, false); RUN_TIMERS()')
    return L, KM


def last(L):
    return L.eval("OUTPUT[#OUTPUT]")


def outputs(L):
    return list(L.eval("OUTPUT").values())


def pages(L):
    return sorted(L.eval("(function() local t = {} for id in pairs(KingMakerTest.pages) do t[#t+1] = id end return t end)()").values())


def open_every_page(L, KM):
    """Builds and refreshes every registered page; returns the ids. Raises on the first Lua error."""
    ids = []
    for pid in list(KM.pages.keys()):
        ids.append(pid)
        KM.Show(pid)
        if KM.errorShown:
            raise AssertionError(f"page {pid}: {last(L)}")
    return ids
