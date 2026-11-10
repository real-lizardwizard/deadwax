"""
The server's half of the iPhone app's level vectors: src/loudness.py gain_for() over the cases below, as
`python_gain_for` in ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/levels/levels-vectors.json.

ios/scripts/export-level-vectors.cjs runs this (it prints the half as JSON) and writes the file; the Swift tests
(LevelsTests.swift) hold the phone's gainFor() to every case, and tests/test_ios_levels.py recomputes each from
the server's gain_for() and checks this list is the committed one - so the rule changed on either side fails
where it was changed. The phone keeps no reserve (it plays the file as it is, nothing resampled), so most cases
have reserve 0; the web's 3 dB room for a resampled copy is in a few, to show the difference.

`loudness_lufs` None stands for -inf (silence: no block above the gate), as the loudness route sends null for it;
`peak_db` None for -inf (a peak of 0). `multiplier` is 10 ** (gain_db / 20) and `multiplier_f32` that rounded
once to a 32-bit float - the one number the phone multiplies every sample by.
"""

import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from src.loudness import FULL_DB, REFERENCE_LUFS, gain_for  # noqa: E402
from src.resample import HEADROOM_DB  # noqa: E402

#? peaks a hundred-millionth of a dB either side of a hundredth's limit: the rounding's guard decides them
_HELD_UNDER_3 = 10 ** ((FULL_DB - 3.0 + 1e-10) / 20)
_HELD_OVER_3 = 10 ** ((FULL_DB - 3.0 - 1e-10) / 20)
_HELD_UNDER_HALF = 10 ** ((FULL_DB - 0.5 + 1e-10) / 20)

#? (name, loudness LUFS or None for silence, peak (1.0 = full scale), reserve dB)
CASES = [
    ("typical loud song", -10.6, 10 ** (-1 / 20), 0.0),
    ("quiet song held by its peak", -24.0, 10 ** (-3.5 / 20), 0.0),
    ("room enough for the reserve", -20.0, 10 ** (-6 / 20), 3.0),
    ("held inside the reserve", -20.0, 10 ** (-4 / 20), 3.0),
    ("same, no reserve (the phone)", -20.0, 10 ** (-4 / 20), 0.0),
    ("silence: loudness null, peak 0", None, 0.0, 0.0),
    ("under the gate: loudness null, peak 0.5", None, 0.5, 0.0),
    ("under the gate: loudness null, full-scale peak", None, 1.0, 0.0),
    ("peak 0 (digital zero) but loudness given", -30.0, 0.0, 0.0),
    ("very quiet, small peak, not held", -60.0, 0.001, 0.0),
    ("very quiet, held", -60.0, 0.01, 0.0),
    ("very loud master", -3.0, 1.0, 0.0),
    ("0 LUFS", 0.0, 1.0, 0.0),
    ("exactly the reference", -18.0, 0.5, 0.0),
    ("full-scale peak, wants up", -20.0, 1.0, 0.0),
    ("16-bit full scale peak 32767/32768", -20.0, 32767 / 32768, 0.0),
    ("24-bit largest sample", -20.0, ((1 << 23) - 1) / (1 << 23), 0.0),
    ("wanted -7.42", -10.58, 0.01, 0.0),
    ("wanted -7.425 (floors to -7.43)", -10.575, 0.01, 0.0),
    ("wanted -7.4299999", REFERENCE_LUFS + 7.4299999, 0.01, 0.0),
    ("wanted -7.4200000001 (snaps to -7.42)", REFERENCE_LUFS + 7.4200000001, 0.01, 0.0),
    ("wanted 2.9999999999 (snaps up to 3.00)", REFERENCE_LUFS - 2.9999999999, 0.01, 0.0),
    ("wanted 1.2", REFERENCE_LUFS - 1.2, 0.01, 0.0),
    ("wanted 7.42 from -25.42", -25.42, 0.01, 0.0),
    ("wanted -0.001 (floors to -0.01)", REFERENCE_LUFS + 0.001, 0.01, 0.0),
    ("wanted 3.999", REFERENCE_LUFS - 3.999, 0.01, 0.0),
    ("wanted 0.004", REFERENCE_LUFS - 0.004, 0.01, 0.0),
    ("gain -0.25 exactly (JS toFixed(1) tie)", REFERENCE_LUFS + 0.25, 0.01, 0.0),
    ("gain 0.75 exactly", REFERENCE_LUFS - 0.75, 0.01, 0.0),
    ("gain -1.75 exactly", REFERENCE_LUFS + 1.75, 0.01, 0.0),
    ("gain 2.25 exactly", REFERENCE_LUFS - 2.25, 0.01, 0.0),
    ("held, limit 1e-10 under 3.00 (guard: 2.99)", -40.0, _HELD_UNDER_3, 0.0),
    ("held, limit 1e-10 over 3.00 (3.00)", -40.0, _HELD_OVER_3, 0.0),
    ("held, limit 1e-10 under 0.50 (guard: 0.49)", -30.0, _HELD_UNDER_HALF, 0.0),
    ("wanted 3 - 4e-9: within 5e-7 of 300 hundredths, snaps to 3.00", REFERENCE_LUFS - (3 - 4e-9), 0.01, 0.0),
    ("wanted 3 - 6e-9: just outside, floors to 2.99", REFERENCE_LUFS - (3 - 6e-9), 0.01, 0.0),
    ("wanted -2 - 4e-9: within 5e-7 above -200, snaps to -2.00", REFERENCE_LUFS + (2 + 4e-9), 0.01, 0.0),
    ("wanted -2 - 6e-9: floors to -2.01", REFERENCE_LUFS + (2 + 6e-9), 0.01, 0.0),
    ("h=799.9999995: round(h,6) is 799.999999 (7.99); (h*1e6).rounded()/1e6 says 8.00", -25.999999995, 0.01, 0.0),
    ("h=656.9999995: 6.56, the multiply shortcut says 6.57", -24.569999995, 0.01, 0.0),
    ("h=-818.0000005: -8.19, the multiply shortcut says -8.18", -9.819999995, 0.01, 0.0),
    ("the loudness route's example album (3.1)", -11.437218417201565, 0.98876953125, 0.0),
    ("a hi-res album held by its peak: the phone, no reserve", -23.81630525, 0.50115966796875, 0.0),
    ("...and the web's copy of it, with the resample's room", -23.81630525, 0.50115966796875, HEADROOM_DB),
]


def f32(value: float) -> float:
    """A float as a 32-bit float holds it, back as a Python float (exact)."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def finite(value: float) -> float | None:
    return value if math.isfinite(value) else None


def case(name: str, lufs: float | None, peak: float, reserve: float) -> dict:
    gain = gain_for(-math.inf if lufs is None else lufs, peak, reserve)
    multiplier = 10 ** (gain.gain_db / 20)
    return {
        "name": name, "loudness_lufs": lufs, "peak": peak, "reserve_db": reserve,
        "gain_db": gain.gain_db, "wanted_db": gain.wanted_db, "peak_db": finite(gain.peak_db), "held": gain.held,
        "multiplier": multiplier, "multiplier_f32": f32(multiplier),
    }


def python_half() -> dict:
    return {"REFERENCE_LUFS": REFERENCE_LUFS, "FULL_DB": FULL_DB, "FULL_DB_repr": repr(FULL_DB), "HEADROOM_DB": HEADROOM_DB,
            "cases": [case(*each) for each in CASES]}


if __name__ == "__main__":
    print(json.dumps(python_half(), allow_nan=False))
