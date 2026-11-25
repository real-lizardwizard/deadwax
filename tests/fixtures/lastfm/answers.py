"""
The answers `GET /deadwax/lastfm/artist` gives (2.1.41, S2; similar artists and top albums since 2.1.43, S4 -
notes/lastfm.md) - and since 2.1.44 (S5) `GET /deadwax/lastfm/radio`'s - for the iPhone and Mac app's fixtures:
asked of the whole app, start(), over tests/test_lastfm_routes.py's stand-in Last.fm - which answers from
tests/test_lastfm.py's ANSWERS - Last.fm's own, recorded by record.py on 2026-11-25 - with a real
SQLite store of its own for each case, logins off (the route is a user's: the implicit admin asks). Written to

  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/answers/artist.json
  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/answers/radio.json   (2.1.44)

on the `ios` branch, where the app's Core decodes them (slice A1's LastfmDecodeTests): run it there, after merging
main, as `.venv/bin/python tests/fixtures/lastfm/answers.py` (`--out DIR` to write elsewhere; `--check` to compare
with what is there, exit status 1 when it differs). tests/test_lastfm_routes.py holds the app's copy to what this
makes now - skipped where there is none, as on main - so a change to the route's answers fails there until it is
written again. The file says which fixtures it was made from (`fixtures`: "recorded"), so the app's tests run on
Last.fm's real answers; a recording made again changes them.

Names outside ASCII are written as JSON escapes, so the file holds none raw.

The same nine cases since 2.1.41 (the app's LastfmDecodeTests counts them): from 2.1.43 each answer also carries
`similar` and `top_albums` - the three artists' whole, by id (and by name for the id Last.fm doesn't know); null where
nothing could be had. getSimilar and getTopAlbums for the unknown id are SHAPED (tests/test_lastfm_routes.py
UNRECORDED: Last.fm's not-known answer, as record.py recorded for its getTopTracks).

radio.json (2.1.44, S5): RADIO_CASES, each the radio's whole answer {enabled, unavailable, why, songs} - `songs` a list
of songs as the Shuffle answers them (SHUFFLE_FIELDS, which Core's Song decodes), [] (a definite nothing: every part
had) or null (not made, or nothing while a part couldn't be had - ask again) - over the same Last.fm
and tests/test_lastfm_radio.py's stand-in Navidrome holding tests/test_lastfm.py's SHAPED LIBRARY, on 2026-11-25 (the
radio's day, which seeds its widening: the file is the same whenever it is made). track.getSimilar for Let It Happen
is recorded; for a song Last.fm doesn't know it is SHAPED (tests/test_lastfm_radio.py RADIO_UNRECORDED).
"""

import json
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

import httpx  # noqa: E402

from src.api import lastfm_endpoint  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import lastfm as route  # noqa: E402
from src.routes import navidrome as navidrome_routes  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests import test_lastfm_radio as R  # noqa: E402
from tests import test_lastfm_routes as T  # noqa: E402

OUT = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "lastfm" / "answers"
FILE = "artist.json"
RADIO_FILE = "radio.json"


def _real_refusal() -> tuple[int, object]:
    held = json.loads(T.REFUSED_INVALID_KEY.read_text(encoding="ascii"))
    return held["status"], held["answer"]


#? (what it is, the query, how Last.fm is set up, whether a key is set)
CASES = [
    ("Tame Impala, by MusicBrainz id: listeners, the page, ten top songs, thirty similar artists, fifty albums",
     {"mbid": T.TAME, "name": "Tame Impala"}, None, True),
    ("Dance Gavin Dance, by MusicBrainz id: ten top songs, nothing to fold; similar artists and albums",
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
     lambda fake: fake.instead.update({method: _real_refusal() for method in T.METHODS}),
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


#? (what it is, the query, how Last.fm and Navidrome are set up, whether a key is set, what deadwax's limits are)
RADIO_CASES = [
    ("Let It Happen by Tame Impala, from the store: the songs you have of Last.fm's 100 similar tracks (20), widened "
     "by its similar artists to 25, each next song by another artist whenever one is left to take",
     R.SEED, None, True, {}),
    ("a song Last.fm doesn't know: its artist's similar artists alone, two each (16)",
     {**R.SEED, "song_id": "so-elsewhere", "title": R.UNKNOWN_SONG}, None, True, {}),
    ("an artist Last.fm doesn't know: no songs, and nothing failed",
     {**R.SEED, "song_id": "so-elsewhere", "title": R.UNKNOWN_SONG, "artist": T.UNKNOWN_NAME}, None, True, {}),
    ("the similar artists failing: the similar tracks' songs alone (20), unavailable",
     R.SEED, lambda fake, library: fake.instead.update(
         {"artist.getsimilar": (500, {"error": 8, "message": "Operation failed"})}), True, {}),
    ("a song Last.fm doesn't know while the similar artists fail: nothing could be had - no songs (null, not []), "
     "unavailable",
     {**R.SEED, "song_id": "so-elsewhere", "title": R.UNKNOWN_SONG}, lambda fake, library: fake.instead.update(
         {"artist.getsimilar": (500, {"error": 8, "message": "Operation failed"})}), True, {}),
    ("Last.fm down with nothing kept: no songs (null), unavailable, no why",
     R.SEED, lambda fake, library: setattr(fake, "down", True), True, {}),
    ("Navidrome down: no songs (null), unavailable, no why",
     R.SEED, lambda fake, library: setattr(library, "down", True), True, {}),
    ("a library too big to match (here past 10 songs): no songs (null), unavailable, and why",
     R.SEED, None, True, {"SHUFFLE_MAX": 10}),
    ("Last.fm refusing the key (its real answer, 403 with error 10) with nothing kept: off, and why",
     R.SEED, lambda fake, library: fake.instead.update(
         {method: _real_refusal() for method in ("track.getsimilar", "artist.getsimilar")}), True, {}),
    ("no key: off, and where to add one", R.SEED, None, False, {}),
]


@contextmanager
def _radio_app(fake: "T.LastFm", library: "R.Library", key: bool, limits: dict):
    with tempfile.TemporaryDirectory() as folder:
        store = JobStore(str(Path(folder) / "deadwax.db"))
        store.init()
        navidrome_routes.forget_shuffles()
        navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(library.handle),
                                             base_url=f"{R.NAVIDROME}/rest")
        try:
            with mock.patch.object(Config, "AUTH_MODE", None), \
                    mock.patch.object(Config, "LASTFM_API_KEY", T.KEY if key else None), \
                    mock.patch.object(Config, "NAVIDROME_URL", R.NAVIDROME), \
                    mock.patch.object(Config, "NAVIDROME_USER", R.SHARED[0]), \
                    mock.patch.object(Config, "NAVIDROME_PASSWORD", R.SHARED[1]), \
                    mock.patch.object(lastfm_endpoint, "PER_SECOND", 1000), \
                    mock.patch.object(route, "clock", lambda: R.NOON), \
                    mock.patch.multiple(navidrome_routes, **limits) if limits else _nothing():
                with T.serving(store, fake) as (_, client):
                    yield client
                    client.portal.call(navidrome.close_client)
        finally:
            navidrome.client = None
            navidrome_routes.forget_shuffles()


@contextmanager
def _nothing():
    yield


def radio_answers() -> dict:
    cases = []
    for name, query, setup, key, limits in RADIO_CASES:
        fake, library = R.radio_lastfm(), R.Library()
        if setup is not None:
            setup(fake, library)
        with _radio_app(fake, library, key, limits) as client:
            response = client.get(R.PATH, params=query)
        if fake.unmatched:
            raise SystemExit(f"{name}: asked what no fixture answers - {fake.unmatched}")
        cases.append({"name": name, "path": R.PATH, "query": query, "status": response.status_code,
                      "answer": response.json()})
    return {
        "made_from": "src/routes/lastfm.py over tests/test_lastfm_routes.py's Last.fm and tests/test_lastfm_radio.py's "
                     "Navidrome (tests/fixtures/lastfm/answers.py)",
        "fixtures": T.ANSWERS.name,
        "cases": cases,
    }


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


def radio_text() -> str:
    return json.dumps(radio_answers(), indent=1, ensure_ascii=True) + "\n"


def texts() -> dict[str, str]:
    """Each file the app's fixtures hold, as the routes answer now."""
    return {FILE: text(), RADIO_FILE: radio_text()}


def main(argv: list[str]) -> int:
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else OUT
    made = texts()
    if "--check" in argv:
        differ = [name for name, wanted in made.items()
                  if ((out / name).read_text(encoding="ascii") if (out / name).exists() else None) != wanted]
        for name in differ:
            print(f"{out / name} isn't what the route answers now - run this without --check", file=sys.stderr)
        return 1 if differ else 0
    out.mkdir(parents=True, exist_ok=True)
    for name, wanted in made.items():
        (out / name).write_text(wanted, encoding="ascii")
        print(f"{len(json.loads(wanted)['cases'])} answers in {out / name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
