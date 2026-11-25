"""
The answers `GET /deadwax/lastfm/artist` gives (2.1.41, S2 - notes/lastfm.md), for the iPhone and Mac app's fixtures:
asked of the whole app, start(), over tests/test_lastfm_routes.py's stand-in Last.fm - which answers from
tests/test_lastfm.py's ANSWERS - Last.fm's own, recorded by record.py on 2026-11-25 - with a real
SQLite store of its own for each case, logins off (the route is a user's: the implicit admin asks). Written to

  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/answers/artist.json

on the `ios` branch, where the app's Core decodes them (slice A1's LastfmDecodeTests): run it there, after merging
main, as `.venv/bin/python tests/fixtures/lastfm/answers.py` (`--out DIR` to write elsewhere; `--check` to compare
with what is there, exit status 1 when it differs). tests/test_lastfm_routes.py holds the app's copy to what this
makes now - skipped where there is none, as on main - so a change to the route's answers fails there until it is
written again. The file says which fixtures it was made from (`fixtures`: "recorded"), so the app's tests run on
Last.fm's real answers; a recording made again changes them.

Names outside ASCII are written as JSON escapes, so the file holds none raw.
"""

import json
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from src.api import lastfm_endpoint  # noqa: E402
from src.config import Config  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests import test_lastfm_routes as T  # noqa: E402

OUT = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "lastfm" / "answers"
FILE = "artist.json"


def _real_refusal() -> tuple[int, object]:
    held = json.loads(T.REFUSED_INVALID_KEY.read_text(encoding="ascii"))
    return held["status"], held["answer"]


#? (what it is, the query, how Last.fm is set up, whether a key is set)
CASES = [
    ("Tame Impala, by MusicBrainz id: listeners, the page, ten top songs",
     {"mbid": T.TAME, "name": "Tame Impala"}, None, True),
    ("Dance Gavin Dance, by MusicBrainz id: ten top songs, nothing to fold",
     {"mbid": T.DGD, "name": "Dance Gavin Dance"}, None, True),
    ("Portishead, by MusicBrainz id: ten top songs, its three live takes (#34, #45, #50) past them",
     {"mbid": T.PORTISHEAD, "name": "Portishead"}, None, True),
    ("an id Last.fm doesn't know, asked again by name",
     {"mbid": T.UNKNOWN_MBID, "name": "Tame Impala"},
     lambda fake: fake.add("artist.getinfo", {"mbid": T.UNKNOWN_MBID}, *T.NOT_KNOWN), True),
    ("an artist Last.fm doesn't know: nothing, and nothing failed",
     {"name": T.UNKNOWN_NAME}, None, True),
    ("getInfo failing: no listeners, the page from the top tracks, unavailable",
     {"mbid": T.TAME}, lambda fake: fake.instead.update({"artist.getinfo": (500, {"error": 8, "message": "Operation failed"})}),
     True),
    ("Last.fm down with nothing kept: every part null, unavailable, no why",
     {"mbid": T.TAME}, lambda fake: setattr(fake, "down", True), True),
    ("Last.fm refusing the key (its real answer, 403 with error 10) with nothing kept: off, and why",
     {"mbid": T.TAME},
     lambda fake: fake.instead.update({"artist.getinfo": _real_refusal(), "artist.gettoptracks": _real_refusal()}),
     True),
    ("no key: off, and where to add one", {"mbid": T.TAME, "name": "Tame Impala"}, None, False),
]


@contextmanager
def _app(fake: "T.LastFm", key: bool):
    with tempfile.TemporaryDirectory() as folder:
        store = JobStore(str(Path(folder) / "deadwax.db"))
        store.init()
        with mock.patch.object(Config, "AUTH_MODE", None), \
                mock.patch.object(Config, "LASTFM_API_KEY", T.KEY if key else None), \
                mock.patch.object(lastfm_endpoint, "PER_SECOND", 1000):
            with T.serving(store, fake) as (_, client):
                yield client


def answers() -> dict:
    cases = []
    for name, query, setup, key in CASES:
        fake = T.LastFm()
        if setup is not None:
            setup(fake)
        with _app(fake, key) as client:
            response = client.get(T.PATH, params=query)
        if fake.unmatched:
            raise SystemExit(f"{name}: asked what no fixture answers - {fake.unmatched}")
        cases.append({"name": name, "path": T.PATH, "query": query, "status": response.status_code,
                      "answer": response.json()})
    return {
        "made_from": "src/routes/lastfm.py over tests/test_lastfm_routes.py's Last.fm (tests/fixtures/lastfm/answers.py)",
        "fixtures": T.ANSWERS.name,
        "cases": cases,
    }


def text() -> str:
    return json.dumps(answers(), indent=1, ensure_ascii=True) + "\n"


def main(argv: list[str]) -> int:
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else OUT
    made = text()
    if "--check" in argv:
        there = (out / FILE).read_text(encoding="ascii") if (out / FILE).exists() else None
        if there != made:
            print(f"{out / FILE} isn't what the route answers now - run this without --check", file=sys.stderr)
            return 1
        return 0
    out.mkdir(parents=True, exist_ok=True)
    (out / FILE).write_text(made, encoding="ascii")
    print(f"{len(json.loads(made)['cases'])} answers in {out / FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
