# Runs every King Maker test suite: python tests/run.py [suite ...]   (pip install lupa)
# Suites are tests/core.py and tests/<module>.py (lower case module name). Each runs in its own interpreter.
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["core", "scanner", "econ", "market", "skillup", "farm", "gather", "inventory", "mail", "quest", "rested",
         "minimap", "oracle", "all"]

# run_tests.py passes folder paths; suite names are bare words (note "core" vs the Core folder on Windows)
wanted = [a.lower() for a in sys.argv[1:] if not a.startswith("-") and not os.path.isabs(a) and "/" not in a and "\\" not in a and a not in (".", "..")]
suites = [s for s in ORDER if os.path.exists(os.path.join(HERE, s + ".py")) and (not wanted or s in wanted)]
failed = []
for s in suites:
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, s + ".py")], capture_output=True, text=True, cwd=HERE)
    out = (r.stdout + r.stderr).strip()
    if r.returncode == 0:
        print(f"PASS {s}: {out.splitlines()[-1] if out else ''}")
    else:
        failed.append(s)
        print(f"FAIL {s}:\n{out}\n")
missing = [s for s in ORDER if s not in suites and s != "all" and not wanted]
if missing:
    print("no suite yet: " + ", ".join(missing))
print("ALL TESTS PASSED" if not failed else "FAILED: " + ", ".join(failed))
sys.exit(1 if failed else 0)
