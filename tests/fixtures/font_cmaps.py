"""
Writes font_cmaps.json beside it: every bundled font file's characters, as its cmap has them, with the file's sha256
(2.0.9). tests/test_type.py reads the JSON - the suite has neither fontTools nor brotli, which a woff2's tables need -
and fails when a file's sha256 no longer matches, so a rebuilt or a new font file means running this again:

    <a Python with fontTools and brotli> tests/fixtures/font_cmaps.py

A face's unicode-range says which characters the browser may ask its file for; only the cmap says which the file can
draw. Google's Latin file claims U+2000-206F and has no dagger or U+2010 hyphen, so a range-only check passes a
character that falls out of Noto.
"""

import hashlib
import itertools
import json
from pathlib import Path

from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
FONTS = HERE.parent.parent / "interface" / "styles" / "font"


def ranges(points: set[int]) -> str:
    """'U+0020-007E, U+00A0' - the CSS unicode-range form."""
    out = []
    for _, run in itertools.groupby(enumerate(sorted(points)), lambda pair: pair[1] - pair[0]):
        run = [point for _, point in run]
        out.append(f"U+{run[0]:04X}-{run[-1]:04X}" if len(run) > 1 else f"U+{run[0]:04X}")
    return ", ".join(out)


def main() -> None:
    found = {}
    for path in sorted(FONTS.rglob("*.woff2")):
        found[path.relative_to(FONTS).as_posix()] = {
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "cmap": ranges(set(TTFont(path).getBestCmap())),
        }
    (HERE / "font_cmaps.json").write_text(json.dumps(found, indent=1, ensure_ascii=True) + "\n")


if __name__ == "__main__":
    main()
