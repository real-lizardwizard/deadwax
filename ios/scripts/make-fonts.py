#!/usr/bin/env python3
"""
Makes the iPhone and Mac app's fonts (ios/App/Fonts) from the files in ios/scripts/fonts/ - nothing is fetched. James
chose them on 25 Nov 2026 ("libre franklin", then "Adopt it"): Libre Franklin for the words (Typeface's text styles,
Typeface.Mac.text, Typeface.Phone.text, Typeface.Look.text) and Courier Prime for the readouts (Typeface.Mac.mono,
Phone.mono, Look.mono and Typeface.readout). They replace Noto Sans (15 Nov) and Noto Sans Mono (24 Nov), which this
script made from the web app's files until then; the web app keeps Noto Sans. ios/scripts/fonts/README.md says where
the sources came from (google/fonts at 6ebe737e, downloaded once with James's OK) and holds their hashes.

- Libre Franklin is one variable font, wght 100-900. Each weight the app draws - 400, 500, 600 and 700 - is pinned with
  fontTools' instancer into a static TrueType font named as the app asks for it (LibreFranklin-Regular, -Medium,
  -SemiBold and -Bold), under the one family "Libre Franklin": SwiftUI's .weight() and .bold() pick the face, as they
  did Noto Sans's. Static rather than variable: the app names a face by its PostScript name (Typeface.Face, for UIKit),
  and a static file per weight is what UIAppFonts registered before and is known to work on the phones.
- Courier Prime comes as two static fonts, Regular and Bold, copied as they are. It has no 500 or 600: the drawings'
  browser draws a readout at 500 Regular and one at 600 Bold. Apple's CoreText draws SemiBold Bold too, but Medium Bold
  as well (measured), so the app never asks a readout for Medium (Typeface.Mac.MonoFace; test_ios_palette.py holds it).
- Each family's licence, its own OFL.txt with its own copyright line, is copied beside its fonts under the family's
  name (LibreFranklin-OFL.txt, CourierPrime-OFL.txt): every file in App/ lands at the bundle's root, so two of one name
  would collide (check_project.py).
- Anything else in App/Fonts is removed, so the folder is exactly what this makes.

The files come out the same byte for byte from the same inputs: the variable font's own dates, never the time it ran.

Needs fontTools - not in the repo's .venv nor the image - in a venv of its own, outside the repo, at the version that
made the files in App/Fonts (another's instancer may write other bytes):

    python3 -m venv ~/Library/Caches/deadwax-build/fonttools-venv
    ~/Library/Caches/deadwax-build/fonttools-venv/bin/pip install fonttools==4.68.0
    ~/Library/Caches/deadwax-build/fonttools-venv/bin/python -I ios/scripts/make-fonts.py
"""

import io
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = Path(__file__).resolve().parent
SOURCES = HERE / "fonts"
OUT = HERE.parent / "App" / "Fonts"

# Typeface.swift's words: Regular, Medium, SemiBold and Bold - Libre Franklin's variable font pinned at each weight
WORDS = ("librefranklin", "LibreFranklin[wght].ttf", "LibreFranklin",
         {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"})
# Typeface's readouts: Courier Prime's own two files, as they are
READOUTS = ("courierprime", ["CourierPrime-Regular.ttf", "CourierPrime-Bold.ttf"], "CourierPrime")


def pin(source: Path, weight: int) -> bytes:
    """The variable font pinned at `weight`, as a static TrueType font's bytes - its names the weight's own (its STAT
    table's: LibreFranklin-Medium under the family Libre Franklin), its dates the variable font's."""
    font = TTFont(source, recalcTimestamp=False)
    static = instancer.instantiateVariableFont(font, {"wght": weight}, updateFontNames=True)
    static.recalcTimestamp = False
    data = io.BytesIO()
    static.save(data)
    return data.getvalue()


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    made = []
    folder, variable, name, weights = WORDS
    for weight, style in weights.items():
        target = OUT / f"{name}-{style}.ttf"
        target.write_bytes(pin(SOURCES / folder / variable, weight))
        made.append(target)
    shutil.copyfile(SOURCES / folder / "OFL.txt", OUT / f"{name}-OFL.txt")
    made.append(OUT / f"{name}-OFL.txt")
    folder, files, name = READOUTS
    for file in files:
        shutil.copyfile(SOURCES / folder / file, OUT / file)
        made.append(OUT / file)
    shutil.copyfile(SOURCES / folder / "OFL.txt", OUT / f"{name}-OFL.txt")
    made.append(OUT / f"{name}-OFL.txt")
    for stale in sorted(set(OUT.iterdir()) - set(made)):
        if stale.is_file():
            stale.unlink()
            print(f"removed {stale.relative_to(HERE.parent.parent)}")
    for target in made:
        line = f"{target.relative_to(HERE.parent.parent)}: {target.stat().st_size} bytes"
        if target.suffix == ".ttf":
            font = TTFont(target)
            line += (f", {len(font.getGlyphOrder())} glyphs, {len(font.getBestCmap())} characters, "
                     f"weight {font['OS/2'].usWeightClass}, {font['name'].getDebugName(6)}")
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
