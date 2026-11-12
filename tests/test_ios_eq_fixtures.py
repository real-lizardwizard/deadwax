"""
The iPhone EQ's fixtures are what ios/scripts/make-eq-fixtures.py writes (notes/ios-specs/eq.md, 5.1).

The Swift EQ in DeadwaxCore is held to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/eq/ - the cookbook, Equalizer
APO's reading rules, AutoEq's own biquads, the GraphicEQ fit, the presets and the Direct Form I reference, each written
out again in Python by that script, independently of the Swift. This runs the script into a temporary folder and
compares what it writes with what is committed, so neither can change without the other: a rule changed in the
script fails here until the fixtures are written again (`python -I ios/scripts/make-eq-fixtures.py`) and the Swift
tests run on them.

The fixtures are made on James's Mac; CI runs this on Linux, whose libm (and numpy's SIMD loops) may round a last bit
differently. So numbers are compared within a few parts in 10^9 of themselves (responses within 1e-4 dB above -120
dB), and everything else - every word, every count, every hand-made file - exactly. Skipped where scipy isn't
installed; tests.yml installs it.
"""

import base64
import json
import math
import subprocess
import sys
from pathlib import Path

import pytest

pytest.importorskip("scipy")
np = pytest.importorskip("numpy")

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "ios" / "scripts" / "make-eq-fixtures.py"
COMMITTED = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "eq"
JSON_FILES = ["apo.json", "filters.json", "profiles.json", "graphic.json", "preamp.json", "render.json"]
BUDGET = 3_000_000


@pytest.fixture(scope="module")
def made(tmp_path_factory):
    out = tmp_path_factory.mktemp("eq")
    run = subprocess.run([sys.executable, "-I", str(SCRIPT), "--out", str(out)], capture_output=True, text=True,
                         timeout=900)
    assert run.returncode == 0, run.stdout + run.stderr
    return out


def _as_number(text):
    try:
        return float(text)
    except ValueError:
        return None


def _numbers_close(a, b):
    if math.isnan(a) or math.isnan(b):
        return math.isnan(a) and math.isnan(b)
    if math.isinf(a) or math.isinf(b):
        return a == b
    return abs(a - b) <= 1e-12 + 5e-9 * max(abs(a), abs(b))


def _arrays_close(key, a, b):
    dtype = "<f4" if key.endswith("_f4") else "<f8"
    x = np.frombuffer(base64.b64decode(a), dtype=dtype).astype(float)
    y = np.frombuffer(base64.b64decode(b), dtype=dtype).astype(float)
    if x.shape != y.shape:
        return "%d values, not %d" % (len(y), len(x))
    if key.endswith("_f4"):
        shown = (x > -120) | (y > -120)
        worst = float(np.max(np.abs(x[shown] - y[shown]))) if shown.any() else 0.0
        bound = 1e-4
    else:
        scale = float(np.max(np.abs(x))) if len(x) else 0.0
        worst = float(np.max(np.abs(x - y))) if len(x) else 0.0
        bound = 1e-12 + 1e-9 * scale
    return None if worst <= bound else "differs by %g" % worst


def _differences(committed, made, path=""):
    out = []
    if isinstance(committed, dict) and isinstance(made, dict):
        if set(committed) != set(made):
            return ["%s: keys %s, not %s" % (path, sorted(made), sorted(committed))]
        for key in committed:
            here = "%s.%s" % (path, key)
            if key.endswith(("_f4", "_f8")):
                pairs = (list(zip(committed[key], made[key])) if isinstance(committed[key], list)
                         else [(committed[key], made[key])])
                if isinstance(committed[key], list) and len(committed[key]) != len(made[key]):
                    out.append("%s: %d arrays, not %d" % (here, len(made[key]), len(committed[key])))
                    continue
                for a, b in pairs:
                    if a is None or b is None:
                        if a is not b:
                            out.append("%s: one is null" % here)
                        continue
                    problem = _arrays_close(key, a, b)
                    if problem:
                        out.append("%s: %s" % (here, problem))
            else:
                out += _differences(committed[key], made[key], here)
        return out
    if isinstance(committed, list) and isinstance(made, list):
        if len(committed) != len(made):
            return ["%s: %d items, not %d" % (path, len(made), len(committed))]
        for i, (a, b) in enumerate(zip(committed, made)):
            out += _differences(a, b, "%s[%d]" % (path, i))
        return out
    if isinstance(committed, str) and isinstance(made, str):
        x, y = _as_number(committed), _as_number(made)
        if x is not None and y is not None:
            return [] if _numbers_close(x, y) else ["%s: %s, not %s" % (path, made, committed)]
        return [] if committed == made else ["%s: %r, not %r" % (path, made, committed)]
    if isinstance(committed, float) and isinstance(made, (int, float)) and not isinstance(made, bool):
        return [] if _numbers_close(committed, float(made)) else ["%s: %r, not %r" % (path, made, committed)]
    return [] if committed == made else ["%s: %r, not %r" % (path, made, committed)]


@pytest.mark.parametrize("name", JSON_FILES)
def test_each_fixture_is_what_the_script_writes(made, name):
    committed = json.loads((COMMITTED / name).read_text(encoding="utf-8"))
    fresh = json.loads((made / name).read_text(encoding="utf-8"))
    problems = _differences(committed, fresh)
    assert not problems, "%s no longer matches the script (first of %d): %s" % (name, len(problems), problems[:10])


def test_the_hand_made_apo_files_are_the_scripts_byte_for_byte(made):
    committed = {p.name: p.read_bytes() for p in (COMMITTED / "apo").glob("*.txt")}
    fresh = {p.name: p.read_bytes() for p in (made / "apo").glob("*.txt")}
    assert sorted(committed) == sorted(fresh)
    changed = [name for name in committed if committed[name] != fresh[name]]
    assert not changed


def test_every_case_of_the_reader_is_there(made):
    """3.9's accepted, skipped and refused cases each have a file: every refusal kind and every note kind."""
    readings = json.loads((COMMITTED / "apo.json").read_text(encoding="utf-8"))["readings"]
    refused = {r["reading"]["refused"]["kind"] for r in readings if r["reading"]["refused"]}
    assert refused == {"nothing", "tooBig", "unreadable", "crOnly", "include", "unsupported", "devices", "iir",
                       "frequencyHigh", "frequencyLow", "gain", "q", "width", "slope", "tooSteep", "preamp",
                       "tooMany", "graphicEmpty", "graphicZero"}
    notes = {n["kind"] for r in readings if not r["reading"]["refused"] for n in r["reading"]["notes"]}
    assert notes == {"device", "channels", "unknown", "leftOut", "utf16"}


def test_the_fixtures_stay_small():
    """The GitHub runner checks them out on every push: a few MB at most (5.1)."""
    size = sum(p.stat().st_size for p in COMMITTED.rglob("*") if p.is_file())
    assert size < BUDGET, "Fixtures/eq is %d bytes" % size
