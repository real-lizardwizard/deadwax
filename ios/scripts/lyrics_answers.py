"""
The server's answers the iPhone app reads its lyrics from (app 0.4, notes/app-lyrics.md 4.8): src/lyrics.py
song_lyrics() - what `GET /deadwax/navidrome/lyrics/{song_id}` sends (json_with_etag of it) - over Navidrome bodies
shaped as v0.64.2 answers getLyricsBySongId, as tests/test_navidrome_lyrics.py fakes them. Written to

  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lyrics/answers.json

which DeadwaxCoreTests' LyricsTests decodes as SongLyrics - each answer read whole, every case of the route's (synced,
plain, none) - and tests/test_ios_contract.py holds to song_lyrics() itself, case by case, and to what this makes now:
so a change to the server's answer fails there until the file is written again
(`.venv/bin/python ios/scripts/lyrics_answers.py`) and the phone's tests run on it.

Every line of lyrics here is invented; text outside ASCII is written as JSON escapes, so the file holds none raw.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.lyrics import song_lyrics  # noqa: E402

FIXTURE = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "lyrics" / "answers.json"


def _entry(lines: list, synced: bool = True, **more) -> dict:
    """One structuredLyrics entry; `lines` as (start or None, value) pairs - test_navidrome_lyrics.py's entry()."""
    return {"displayArtist": "A", "displayTitle": "B", "lang": "xxx", "synced": synced, **more,
            "line": [{"value": value} if start is None else {"start": start, "value": value} for start, value in lines]}


def _body(*entries) -> dict:
    """getLyricsBySongId's body as the route's client hands it on: the inside of the Subsonic answer."""
    return {"status": "ok", "lyricsList": {"structuredLyrics": list(entries)}}


#? Navidrome's own snapshot's shape - two entries, offset 100, one synced at 18800 and 22801, one plain - as
#? tests/test_navidrome_lyrics.py SNAPSHOT has it
SNAPSHOT = {"structuredLyrics": [
    {"displayArtist": "Some Artist", "displayTitle": "Some Song", "lang": "eng", "offset": 100, "synced": True,
     "line": [{"start": 18800, "value": "The first line we sing"}, {"start": 22801, "value": "And then the second"}]},
    {"displayArtist": "Some Artist", "displayTitle": "Some Song", "lang": "xxx", "offset": 100, "synced": False,
     "line": [{"value": "The first line we sing"}, {"value": "And then the second"}]},
]}

BODIES = [
    ("Navidrome's snapshot: the synced entry, the offset taken off", {"lyricsList": SNAPSHOT}),
    ("synced: an intro's break at 0, a verse, a long break, the last line, an outro's break", _body(_entry([
        (0, ""), (12500, "The first line sung"), (15250, "The second line  "), (21000, ""),
        (33000, "After the guitar"), (36500, "And the last one"), (40000, "")]))),
    ("synced, sorted: a hand-made file out of order", _body(_entry([(9000, "Third"), (1000, "First"), (5000, "Second")]))),
    ("a duet's shared stamp stays synced", _body(_entry([(5000, "Me"), (5000, "You"), (8000, "Together")]))),
    ("every worded line at one stamp is plain", _body(_entry([(0, "All at once"), (0, "Every one of them")]))),
    ("synced with an untimed worded line is plain", _body(_entry([(1000, "Timed"), (None, "Not timed")]))),
    ("plain: a joined line keeps its newline, the edge blanks go", _body(_entry(
        [(None, ""), (None, "Words with no times"), (None, "A joined line\nkeeps its break"), (None, "  ")],
        synced=False))),
    ("text outside ASCII", _body(_entry([(1000, "Zweite Zeile"), (2500, "Troisi\u00e8me ligne \u266a")]))),
    ("none: lyricsList is {}", {"status": "ok", "lyricsList": {}}),
    ("none: no lyricsList at all", {"status": "ok"}),
    ("none: entries whose lines are all empty", _body(_entry([(0, ""), (1000, " ")]), _entry([(None, "")], synced=False))),
]


def answers() -> dict:
    return {
        "made_from": "src/lyrics.py song_lyrics() (ios/scripts/lyrics_answers.py)",
        "cases": [{"name": name, "navidrome": body, "answer": song_lyrics(body)} for name, body in BODIES],
    }


def text() -> str:
    return json.dumps(answers(), indent=1, ensure_ascii=True) + "\n"


if __name__ == "__main__":
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(text(), encoding="utf-8")
    print(f"wrote {FIXTURE.relative_to(ROOT)}")
