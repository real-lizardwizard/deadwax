#!/usr/bin/env python3
"""
The /scrub answer DeadwaxAudioTests' DeckWindowTests read (notes/ios-specs/turntable.md 4.5, 7.2): deadwax's own code
cutting a window out of Fixtures/deck/deck-44k.flac exactly as the route answers for a song with no MP4 kept -
src/flac_ranges.py's read_head and cut, the very steps player_cache's answer_window drives against the FLAC on
Navidrome, here answered from the file - written beside it as deck-44k-scrub.flac, with what `X-Deadwax-Window` says
in deck-44k-scrub.json. So the phone's reader is held to the real format, not to a copy of it.

Asked as the phone asks (DeckScrub.ask) for a window from the 2 s grid start 2.0 at 48 kHz: `at` 1.8 (the grid start
less the 0.2 s pre-roll), `seconds` 41.2 (40 s, the pre-roll and 1 s). Run from the checkout with the server's Python,
after make-test-album.py --deck-fixtures:

    .venv/bin/python ios/scripts/export-scrub-window.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src import flac_ranges  # noqa: E402
from src.player_cache import WINDOW_MAX_BYTES  # noqa: E402

FIXTURES = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxAudioTests" / "Fixtures" / "deck"
AT = 1.8
SECONDS = 41.2


def answer() -> tuple[bytes, str]:
    """The window's FLAC as the route answers it, and the JSON written beside it (what X-Deadwax-Window says)."""
    source = (FIXTURES / "deck-44k.flac").read_bytes()

    def read(offset: int, length: int) -> bytes:
        return source[offset:offset + length]

    head = flac_ranges.run(flac_ranges.read_head(len(source)), read)
    window, _ = flac_ranges.run(flac_ranges.cut(head, AT, SECONDS, WINDOW_MAX_BYTES), read)
    about = {
        "about": "deadwax's /scrub answer for deck-44k.flac at=1.8&seconds=41.2, cut by src/flac_ranges.py (written "
                 "by ios/scripts/export-scrub-window.py - never edit by hand)",
        "from": "deck-44k.flac",
        "at": AT,
        "seconds": SECONDS,
        "header": f"{window.first}/{window.samples}/{window.rate}",
        "bytes": len(window.data),
    }
    return window.data, json.dumps(about, indent=2) + "\n"


def main() -> int:
    flac, about = answer()
    (FIXTURES / "deck-44k-scrub.flac").write_bytes(flac)
    (FIXTURES / "deck-44k-scrub.json").write_text(about, encoding="utf-8")
    print(f"deck-44k-scrub.flac  {len(flac)} bytes, X-Deadwax-Window {json.loads(about)['header']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
