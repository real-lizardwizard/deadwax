"""
The iPhone and Mac app's faces, measured from the fonts it bundles (ios/App/Fonts) - one place every fit test in
tests/test_ios_*.py takes a width from (notes/ios.md "The app's fonts: Libre Franklin and Courier Prime (2026-11-25)").
Not a test itself: the look tests load it beside them, as they load each other.

Each width is the sum of the characters' advances, read from the TrueType file by hand (its cmap and hmtx - the suite
has no fontTools), at the face the words are drawn in. That leaves out kerning: Libre Franklin's pairs draw a line a
little narrower than its sum, never wider - every sentence the fit tests measure was laid out by CoreText on this Mac
(kerning on) at or under its sum (WIDEST_KERNED_OVER, below, the most any came over: none did). Courier Prime has no
kerning: every character is 1228/2048 of an em. Re-run every fit test after a font changes: none keeps a width of its
own.

- `words(text, points, weight)`: Libre Franklin - "regular", "medium", "semibold" or "bold".
- `readout(text, points, bold=False)`: Courier Prime, Regular or Bold (it has no Medium or SemiBold).
- `face(name)`: a face's advances by code point, in ems, and `lacks(text, name)` what it can't draw - a character
  neither face has falls back to iOS's own font, whose width this can't know, so a fit test measuring one fails.
- `vertical(name)`: a face's line, in ems - its ascender, descender (negative, under the baseline) and line gap, as
  Apple's CoreText takes them (the hhea table's).
"""

from functools import lru_cache
from pathlib import Path

FONTS = Path(__file__).resolve().parent.parent / "ios" / "App" / "Fonts"
WORDS = {"regular": "LibreFranklin-Regular", "medium": "LibreFranklin-Medium", "semibold": "LibreFranklin-SemiBold",
         "bold": "LibreFranklin-Bold"}
READOUTS = {False: "CourierPrime-Regular", True: "CourierPrime-Bold"}
# CoreText's own line width (kerning on) over the sum of advances, at its most, for the sentences the fit tests measure
# (read on this Mac with the bundled faces, 25 Nov): kerning only ever narrowed them
WIDEST_KERNED_OVER = 0.0


def _u16(data: bytes, at: int) -> int:
    return int.from_bytes(data[at:at + 2], "big")


def _tables(data: bytes) -> dict:
    return {data[12 + 16 * i:16 + 16 * i].decode("latin-1"): int.from_bytes(data[20 + 16 * i:24 + 16 * i], "big")
            for i in range(_u16(data, 4))}


def _cmap(data: bytes, start: int) -> dict:
    """Code point -> glyph, from the (3, 1) format 4 subtable."""
    for index in range(_u16(data, start + 2)):
        record = start + 4 + 8 * index
        if (_u16(data, record), _u16(data, record + 2)) != (3, 1):
            continue
        table = start + int.from_bytes(data[record + 4:record + 8], "big")
        assert _u16(data, table) == 4
        segments = _u16(data, table + 6) // 2
        ends, starts = table + 14, table + 16 + 2 * segments
        deltas, offsets = table + 16 + 4 * segments, table + 16 + 6 * segments
        found = {}
        for i in range(segments):
            first, last = _u16(data, starts + 2 * i), _u16(data, ends + 2 * i)
            delta, offset = _u16(data, deltas + 2 * i), _u16(data, offsets + 2 * i)
            for code in range(first, last + 1):
                if code == 0xFFFF:
                    continue
                if offset == 0:
                    glyph = (code + delta) & 0xFFFF
                else:
                    glyph = _u16(data, offsets + 2 * i + offset + 2 * (code - first))
                    glyph = (glyph + delta) & 0xFFFF if glyph else 0
                if glyph:
                    found[code] = glyph
        return found
    raise AssertionError("no (3, 1) cmap")


@lru_cache(maxsize=None)
def face(name: str) -> dict:
    """A face's advance widths by code point, in ems."""
    data = (FONTS / f"{name}.ttf").read_bytes()
    tables = _tables(data)
    units = _u16(data, tables["head"] + 18)
    metrics = _u16(data, tables["hhea"] + 34)
    hmtx = tables["hmtx"]
    advances = [_u16(data, hmtx + 4 * i) for i in range(metrics)]
    return {code: (advances[glyph] if glyph < metrics else advances[-1]) / units
            for code, glyph in _cmap(data, tables["cmap"]).items()}


def lacks(text: str, name: str) -> str:
    """The characters of `text` the face has no glyph for."""
    advances = face(name)
    return "".join(sorted({c for c in text if ord(c) not in advances}))


def _sum(text: str, points: float, name: str) -> float:
    missing = lacks(text, name)
    assert not missing, f"{name} has no {missing!r}: it would draw in iOS's font, whose width isn't known here"
    advances = face(name)
    return sum(advances[ord(c)] for c in text) * points


def words(text: str, points: float, weight: str = "regular") -> float:
    """`text`'s width at `points` in Libre Franklin at a weight."""
    return _sum(text, points, WORDS[weight])


def readout(text: str, points: float, bold: bool = False) -> float:
    """`text`'s width at `points` in Courier Prime."""
    return _sum(text, points, READOUTS[bold])


@lru_cache(maxsize=None)
def vertical(name: str) -> tuple:
    """A face's ascender, descender and line gap, in ems (hhea's: CoreText's line)."""
    data = (FONTS / f"{name}.ttf").read_bytes()
    tables = _tables(data)
    units = _u16(data, tables["head"] + 18)

    def signed(at: int) -> int:
        value = _u16(data, tables["hhea"] + at)
        return value - 0x10000 if value & 0x8000 else value

    return signed(4) / units, signed(6) / units, signed(8) / units
