"""
The iPhone EQ's fixtures are what ios/scripts/make-eq-fixtures.py writes (notes/ios-specs/eq.md, 5.1).

The Swift EQ in DeadwaxCore is held to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/eq/ - the cookbook, Equalizer
APO's reading rules, AutoEq's own biquads, the GraphicEQ fit, the presets and the Direct Form I reference, each written
out again in Python by that script, independently of the Swift. This runs the script into a temporary folder and
compares what it writes with what is committed, so neither can change without the other: a rule changed in the
script fails here until the fixtures are written again (`python -I ios/scripts/make-eq-fixtures.py`) and the Swift
tests run on them.

Two kinds of check, as the turntable's fixtures have (notes/ios.md). made.json records the machine that wrote them
(made_on: the platform, Python, numpy and scipy) and the script's sha256 (made_with):

- everywhere, made_with must be the script's: any change to it, maths or not, means writing the fixtures again;
- where made_on is this machine, every file byte for byte (the full check);
- elsewhere - CI's x64 Linux, another numpy - every word, count, flag and hand-made file exactly, and every number
  within what another libm's or another SIMD loop's last bit can move it. Measured on this Mac by running the script
  with every libm and numpy result it reaches moved by up to three ulps: coefficients moved by 1e-14 of themselves,
  impulses by 3e-13 of their largest sample, every other number by under 6e-10 of itself (or 2e-14 near zero), the
  render's Float32 samples by at most one of their own ulps, a curve's dB by one ulp or, for a filter at 1 Hz at
  192 kHz and above (whose coefficients cancel to their last bits), by up to 6e-7 dB - and the GraphicEQ fit's
  unrounded gains by up to 9e-8 dB, because its Jacobian is a finite difference over 0.001 dB, which magnifies the
  curve's last bit 500 times. So: numbers within 5e-9 of themselves, Float64 arrays within 1e-9 of their largest
  value, Float32 samples within two of their own ulps, a curve's points within two ulps and 1e-5 dB (those below
  -120 dB, where a notch's depth is all rounding, aren't compared), unrounded gains within 1e-6 dB (the Swift
  fit's own bound, and the script refuses any gain that close to a rounding boundary, so the rounded ones are
  compared exactly), the render's noise input bit for bit (PCG64's draws and their scaling are exact on any
  machine), and where a top or lowest point is ("topAt") only where it is clear of 0 dB: a flat curve's top is a tie
  between its ends. A change to the maths bigger than a last bit fails them - a 10% change to the fit's lambda, a
  peak's A moved by 2.5e-8 of itself, a level by 1e-6 dB, each tried; one at the last bit (DF1's order, pi to 15
  digits) is the maker's byte check's and the sha's.

Skipped where scipy isn't installed; tests.yml installs it.
"""

import base64
import hashlib
import json
import math
import re
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

NUMBER_RELATIVE = 5e-9
F8_OF_LARGEST = 1e-9
F4_ULPS = 2
DB_FLOOR = 1e-5
UNROUNDED_DB = 1e-6
CLEAR_OF_ZERO_DB = 1e-9
DB_KEYS = ("response_f4", "peq44100_f4", "peq48000_f4")
EXACT_KEYS = ("input_f4",)


@pytest.fixture(scope="module")
def made(tmp_path_factory):
    out = tmp_path_factory.mktemp("eq")
    run = subprocess.run([sys.executable, "-I", str(SCRIPT), "--out", str(out)], capture_output=True, text=True,
                         timeout=900)
    assert run.returncode == 0, run.stdout + run.stderr
    return out


def _on_the_maker(made):
    committed = json.loads((COMMITTED / "made.json").read_text(encoding="utf-8"))
    fresh = json.loads((made / "made.json").read_text(encoding="utf-8"))
    return committed["made_on"] == fresh["made_on"]


def _as_number(text):
    try:
        return float(text)
    except ValueError:
        return None


def _numbers_close(a, b, path):
    if math.isnan(a) or math.isnan(b):
        return math.isnan(a) and math.isnan(b)
    if math.isinf(a) or math.isinf(b):
        return a == b
    if re.search(r"\.unrounded\[\d+\]$", path):
        return abs(a - b) <= UNROUNDED_DB
    return abs(a - b) <= 1e-12 + NUMBER_RELATIVE * max(abs(a), abs(b))


def _arrays_close(key, a, b):
    dtype = "<f4" if key.endswith("_f4") else "<f8"
    x = np.frombuffer(base64.b64decode(a), dtype=dtype)
    y = np.frombuffer(base64.b64decode(b), dtype=dtype)
    if x.shape != y.shape:
        return "%d values, not %d" % (len(y), len(x))
    if key in EXACT_KEYS:
        return None if x.tobytes() == y.tobytes() else "differs (it is compared bit for bit)"
    if key.endswith("_f4"):
        shown = (x > -120) | (y > -120) if key in DB_KEYS else np.ones(x.shape, dtype=bool)
        ulps = np.spacing(np.maximum(np.abs(x[shown]), np.abs(y[shown]))).astype(float)
        gap = np.abs(x[shown].astype(float) - y[shown].astype(float))
        over = gap > F4_ULPS * ulps + (DB_FLOOR if key in DB_KEYS else 1e-12)
        return None if not over.any() else "%d values differ by more than %d of their ulps (by %g)" % (
            int(over.sum()), F4_ULPS, float(np.max(gap[over])))
    worst = float(np.max(np.abs(x - y))) if len(x) else 0.0
    bound = 1e-12 + F8_OF_LARGEST * (float(np.max(np.abs(x))) if len(x) else 0.0)
    return None if worst <= bound else "differs by %g" % worst


def _ties(committed, made):
    """The "...At" keys not compared: where the point they place is within CLEAR_OF_ZERO_DB of 0 dB on both."""
    out = set()
    for key in committed:
        if key.endswith("At") and key[:-2] in committed and key[:-2] in made:
            a, b = _as_number(str(committed[key[:-2]])), _as_number(str(made[key[:-2]]))
            if a is not None and b is not None and abs(a) <= CLEAR_OF_ZERO_DB and abs(b) <= CLEAR_OF_ZERO_DB:
                out.add(key)
    return out


def _differences(committed, made, path=""):
    out = []
    if isinstance(committed, dict) and isinstance(made, dict):
        if set(committed) != set(made):
            return ["%s: keys %s, not %s" % (path, sorted(made), sorted(committed))]
        ties = _ties(committed, made)
        for key in committed:
            here = "%s.%s" % (path, key)
            if key in ties:
                continue
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
            return [] if _numbers_close(x, y, path) else ["%s: %s, not %s" % (path, made, committed)]
        return [] if committed == made else ["%s: %r, not %r" % (path, made, committed)]
    if isinstance(committed, float) and isinstance(made, (int, float)) and not isinstance(made, bool):
        return [] if _numbers_close(committed, float(made), path) else ["%s: %r, not %r" % (path, made, committed)]
    return [] if committed == made else ["%s: %r, not %r" % (path, made, committed)]


def test_the_fixtures_were_written_by_this_script():
    """Everywhere: made.json's made_with is the script as it is now, so a change to it - its maths or a comment -
    fails until the fixtures are written again."""
    made_with = json.loads((COMMITTED / "made.json").read_text(encoding="utf-8"))["made_with"]
    now = hashlib.sha256(SCRIPT.read_bytes()).hexdigest()
    assert made_with == {"ios/scripts/make-eq-fixtures.py": now}, (
        "make-eq-fixtures.py changed since the fixtures were written: run `python -I ios/scripts/make-eq-fixtures.py`"
        " and the Swift tests on what it writes")


@pytest.mark.parametrize("name", JSON_FILES)
def test_each_fixture_is_what_the_script_writes(made, name):
    if _on_the_maker(made):
        assert (made / name).read_bytes() == (COMMITTED / name).read_bytes(), (
            "%s is not byte for byte what the script writes on the machine that wrote it" % name)
        return
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
