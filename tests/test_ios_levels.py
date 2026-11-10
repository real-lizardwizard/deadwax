"""
The iPhone app's Normalization rule against the server's (ios/, Phase 1).

The phone works an album's or a song's gain out itself, from the raw loudness and peak deadwax measured, with
src/loudness.py gain_for()'s rule and no reserve (it plays the original file, nothing resampled). Its Swift
port is held to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/levels/levels-vectors.json by the Swift tests;
this holds that file's `python_gain_for` half to gain_for() itself, case by case, and to the list
ios/scripts/level_vectors.py makes - so a change to the server's rule fails here until the vectors are
written again (`node ios/scripts/export-level-vectors.cjs`) and the phone's tests run on them. The TypeScript
half is ui/test/ioslevels.sim.cjs's.

No numpy needed: gain_for() is plain Python.
"""

import importlib.util
import json
import math
import re
import struct
from pathlib import Path

import pytest

from src import levels, loudness
from src.loudness import FULL_DB, REFERENCE_LUFS, gain_for

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "levels"
LEVELS_SWIFT = ROOT / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "Levels.swift"
HELPER = ROOT / "ios" / "scripts" / "level_vectors.py"


def _vectors() -> dict:
    return json.loads((FIXTURES / "levels-vectors.json").read_text(encoding="utf-8"))


def _helper():
    spec = importlib.util.spec_from_file_location("ios_level_vectors", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CASES = _vectors()["python_gain_for"]["cases"]


def _f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


@pytest.mark.parametrize("case", CASES, ids=[case["name"] for case in CASES])
def test_every_vector_is_gain_for_itself(case):
    lufs = -math.inf if case["loudness_lufs"] is None else case["loudness_lufs"]
    gain = gain_for(lufs, case["peak"], case["reserve_db"])
    assert gain.gain_db == case["gain_db"]
    assert gain.wanted_db == case["wanted_db"]
    assert gain.held is case["held"]
    if case["peak_db"] is None:
        assert gain.peak_db == -math.inf
    else:
        assert gain.peak_db == case["peak_db"]
    assert case["multiplier"] == 10 ** (gain.gain_db / 20)
    assert case["multiplier_f32"] == _f32(case["multiplier"])
    #? the peak at the gain, in the very Float the phone multiplies by, never past full scale
    assert _f32(case["peak"]) * case["multiplier_f32"] <= 1.0


def test_the_vectors_are_the_ones_the_helper_makes():
    """The committed half is the helper's list run now: a case added, or the rule changed, means writing the
    vectors again (and the Swift tests running on them)."""
    assert _helper().python_half() == _vectors()["python_gain_for"]


def test_the_constants_are_the_servers():
    half = _vectors()["python_gain_for"]
    assert half["REFERENCE_LUFS"] == REFERENCE_LUFS
    assert half["FULL_DB"] == FULL_DB
    assert half["FULL_DB_repr"] == repr(FULL_DB)
    assert len(CASES) >= 41


def test_the_swift_constants_are_the_servers():
    """Levels.swift writes FULL_DB as Python's repr of it (so the limit is the server's to the last bit, whatever
    the phone's log10 says), the reference, and the measurement's version the loudness route's `algorithm`
    carries."""
    source = LEVELS_SWIFT.read_text(encoding="utf-8")
    full = re.search(r"public static let fullDB = (\S+)\n", source)
    reference = re.search(r"public static let referenceLUFS = (\S+)\n", source)
    algorithm = re.search(r"public static let algorithm = (\d+)\n", source)
    assert full and reference and algorithm
    assert full.group(1) == repr(FULL_DB)
    assert float(reference.group(1)) == REFERENCE_LUFS
    assert int(algorithm.group(1)) == loudness.ALGORITHM_VERSION


def test_the_reasons_in_the_words_vectors_are_still_the_servers():
    """The words vectors read a few of levels.py's reasons as the server words them; About sorts them by what
    they say (aboutSound.ts ABOUT_REASONS), so one reworded here must be looked at there."""
    whys = {case["answer"]["why"] for case in _vectors()["typescript"]["words"] if case["answer"] and case["answer"]["why"]}
    for reason in (levels.NO_LIBRARIES, levels.NO_CACHE, levels.NOT_FLAC, levels.UNREADABLE):
        assert reason in whys
