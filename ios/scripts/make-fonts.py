#!/usr/bin/env python3
"""
Makes the iPhone app's Noto Sans (ios/App/Fonts) from the web app's own files, interface/styles/font/noto-sans/ -
nothing is fetched. James chose it on 15 Nov: "Noto Sans (the web's)".

The web serves Noto Sans as seven variable-weight woff2 files, one per script (latin, latin-ext-europe, vietnamese,
greek, greek-ext, cyrillic, cyrillic-ext), each claiming its own unicode-range, and the browser takes each
character from the file whose range holds it. iOS has no unicode-range: every one of the seven calls itself
NotoSans-Regular (and its other named instances), so registering them side by side, only the first would register.
So each weight the app draws - 400, 500, 600, 700 - is made one font: each subset pinned at that weight
(fontTools' instancer), then the seven merged into one TrueType font (fontTools' merger), latin first, so its
glyph wins for a character two subsets share and its tables' header and names are the font's. The web's range
whole, as one face per weight under one family, "Noto Sans": SwiftUI's .weight() and .bold() pick the face.

Static rather than variable: fontTools' merger takes no variable font. TrueType rather than woff2: iOS is only
known to read a woff2 from this Mac's CoreText, not the phone's. The files come out the same byte for byte from the
same inputs (no timestamp written).

Needs fontTools and brotli (a woff2's tables are brotli'd) - neither in the repo's .venv nor the image. In a venv
of their own, outside the repo:

    python3 -m venv ~/Library/Caches/deadwax-build/fonttools-venv
    ~/Library/Caches/deadwax-build/fonttools-venv/bin/pip install fonttools brotli
    ~/Library/Caches/deadwax-build/fonttools-venv/bin/python -I ios/scripts/make-fonts.py
"""

import shutil
import sys
import tempfile
from pathlib import Path

from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent.parent / "interface" / "styles" / "font" / "noto-sans"
OUT = HERE.parent / "App" / "Fonts"

# latin first: the merger keeps the first font's glyph for a code point two subsets share, and its header and names
SUBSETS = [
    "noto-sans-latin",
    "noto-sans-latin-ext-europe",
    "noto-sans-vietnamese",
    "noto-sans-greek",
    "noto-sans-greek-ext",
    "noto-sans-cyrillic",
    "noto-sans-cyrillic-ext",
]
# the weights the app draws (Typeface.swift): its words, Medium, SemiBold and Bold
WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        for weight, style in WEIGHTS.items():
            pinned = []
            for subset in SUBSETS:
                font = TTFont(SOURCE / f"{subset}.woff2", recalcTimestamp=False)
                static = instancer.instantiateVariableFont(font, {"wght": weight}, updateFontNames=True)
                static.flavor = None
                path = Path(work) / f"{subset}-{weight}.ttf"
                static.save(path)
                pinned.append(str(path))
            merged = Merger().merge(pinned)
            merged.flavor = None
            # the latin file's own dates, never the time it was made: the same inputs, the same bytes
            latin = TTFont(SOURCE / f"{SUBSETS[0]}.woff2")["head"]
            merged["head"].created = latin.created
            merged["head"].modified = latin.modified
            merged.recalcTimestamp = False
            target = OUT / f"NotoSans-{style}.ttf"
            merged.save(target)
            print(f"{target.relative_to(HERE.parent.parent)}: {target.stat().st_size} bytes, "
                  f"{len(merged.getGlyphOrder())} glyphs, {len(merged.getBestCmap())} characters")
    # the licence goes with the fonts, as the web keeps it beside its files
    shutil.copyfile(SOURCE / "OFL.txt", OUT / "OFL.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
