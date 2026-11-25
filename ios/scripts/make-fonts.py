#!/usr/bin/env python3
"""
Makes the iPhone app's Noto Sans (ios/App/Fonts) from the web app's own files, interface/styles/font/noto-sans/ -
nothing is fetched. James chose it on 15 Nov: "Noto Sans (the web's)". And (the Mac redesign's R1, 24 Nov, James:
"Bundle Noto Sans Mono") its Noto Sans Mono, the same way from interface/styles/font/noto-sans-mono/: the Mac's data
face (Typeface.Mac.mono) - numbers, lengths, paths, formats, as the redesign draws them.

The web serves Noto Sans as seven variable-weight woff2 files, one per script (latin, latin-ext-europe, vietnamese,
greek, greek-ext, cyrillic, cyrillic-ext), each claiming its own unicode-range, and the browser takes each
character from the file whose range holds it. iOS has no unicode-range: every one of the seven calls itself
NotoSans-Regular (and its other named instances), so registering them side by side, only the first would register.
So each weight the app draws - 400, 500, 600, 700 - is made one font: each subset pinned at that weight
(fontTools' instancer), then the seven merged into one TrueType font (fontTools' merger), latin first, so its
glyph wins for a character two subsets share and its tables' header and names are the font's. The web's range
whole, as one face per weight under one family, "Noto Sans": SwiftUI's .weight() and .bold() pick the face. Noto Sans
Mono is served the same way (seven variable woff2 files, every one NotoSansMono-Regular) and made the same way: 400, 500
and 600, the weights the redesign's drawings load, under the family "Noto Sans Mono". Both licences are the one OFL.txt
(the web keeps the same file, byte for byte, beside each family), copied once.

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
FONTS = HERE.parent.parent / "interface" / "styles" / "font"
OUT = HERE.parent / "App" / "Fonts"

# Each family: the web's folder, the files' names, its subsets - latin first: the merger keeps the first font's glyph
# for a code point two subsets share, and its header and names - and the weights the app draws.
FAMILIES = [
    # Typeface.swift's words: Regular, Medium, SemiBold and Bold
    ("noto-sans", "NotoSans", [
        "noto-sans-latin",
        "noto-sans-latin-ext-europe",
        "noto-sans-vietnamese",
        "noto-sans-greek",
        "noto-sans-greek-ext",
        "noto-sans-cyrillic",
        "noto-sans-cyrillic-ext",
    ], {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}),
    # (the Mac redesign's R1) Typeface.Mac.mono's: Regular, Medium and SemiBold - the drawings' 400, 500 and 600
    ("noto-sans-mono", "NotoSansMono", [
        "noto-sans-mono-latin",
        "noto-sans-mono-latin-ext",
        "noto-sans-mono-vietnamese",
        "noto-sans-mono-greek",
        "noto-sans-mono-greek-ext",
        "noto-sans-mono-cyrillic",
        "noto-sans-mono-cyrillic-ext",
    ], {400: "Regular", 500: "Medium", 600: "SemiBold"}),
]


def make(folder: str, name: str, subsets: list, weights: dict, work: Path) -> None:
    source = FONTS / folder
    for weight, style in weights.items():
        pinned = []
        for subset in subsets:
            font = TTFont(source / f"{subset}.woff2", recalcTimestamp=False)
            static = instancer.instantiateVariableFont(font, {"wght": weight}, updateFontNames=True)
            static.flavor = None
            path = work / f"{subset}-{weight}.ttf"
            static.save(path)
            pinned.append(str(path))
        merged = Merger().merge(pinned)
        merged.flavor = None
        # the latin file's own dates, never the time it was made: the same inputs, the same bytes
        latin = TTFont(source / f"{subsets[0]}.woff2")["head"]
        merged["head"].created = latin.created
        merged["head"].modified = latin.modified
        merged.recalcTimestamp = False
        target = OUT / f"{name}-{style}.ttf"
        merged.save(target)
        print(f"{target.relative_to(HERE.parent.parent)}: {target.stat().st_size} bytes, "
              f"{len(merged.getGlyphOrder())} glyphs, {len(merged.getBestCmap())} characters")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        for folder, name, subsets, weights in FAMILIES:
            make(folder, name, subsets, weights, Path(work))
    # the licence goes with the fonts, as the web keeps it beside its files - one file for both families: the web's
    # two copies are the same, byte for byte (said here, so a licence that ever differs is never dropped unseen)
    licences = {(FONTS / folder / "OFL.txt").read_bytes() for folder, _, _, _ in FAMILIES}
    if len(licences) != 1:
        print("the families' OFL.txt files differ: App/Fonts holds one", file=sys.stderr)
        return 1
    shutil.copyfile(FONTS / FAMILIES[0][0] / "OFL.txt", OUT / "OFL.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
