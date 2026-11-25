"""
GET /deadwax/lastfm/radio (2.1.44, S5 - notes/lastfm.md "S5 - radio"; the design's 2.6): src/routes/lastfm.py's radio,
asked of the whole app, start(), with a real SQLite store, Last.fm as tests/test_lastfm_routes.py's stand-in - which
answers only what record.py recorded (tame-impala.let-it-happen.similar for track.getSimilar, tame-impala.similar.name
for the similar artists) or what is SHAPED below and says so - and Navidrome as a stand-in of its own (Library), shaped
from 0.64.2's source as tests/test_navidrome_shuffle.py's Shuffler is: search3's empty query answers every song in its
natural order, paged by songOffset; the shared login's token checked. Its songs are tests/test_lastfm.py's SHAPED
LIBRARY. Logins off here (the implicit admin asks). The Library stand-in and RADIO_UNRECORDED are tests/fixtures/
lastfm/answers.py's too, for the app's radio.json.

What this holds:
  - the answer {enabled, unavailable, why, songs}, each song in SHUFFLE_FIELDS as Navidrome has it - what the pure
    radio_order() makes of the same answers (pinned in tests/test_lastfm.py's test_the_recorded_radio);
  - the three asked at once; Last.fm asked with record.py's parameters, the seed's words as its key reads them;
    kept - a second radio asks Last.fm nothing - and the artist page's similar-artists row shared; the scope's songs
    the Shuffle's own list, reused;
  - the same radio all day, another the next;
  - degrading: Last.fm down, limiting, late or refused; Navidrome down, failing, not set up, or the library too big;
    a fault in deadwax - each an answer the app can say, never a 500; a session Navidrome ended is a 401;
  - no key: nothing asked of Last.fm or Navidrome; the query declared and bounded.

With logins on - `yours` the asker's library, asked as them, never the store's - tests/test_lastfm_radio_logins.py.
"""

import asyncio
import calendar
import hashlib
import json
import os
import sqlite3
import time

import httpx
import pytest

from src.api import lastfm_endpoint
from src.api.navidrome_endpoint import NOT_CONFIGURED, SUBSONIC_ERRORS, navidrome
from src.config import Config
from src.lastfm import NO_KEY_WHY, similar_artists, similar_of, similar_tracks, too_big_why
from src.lastfm_kept import DAY, ROW_MAX_BYTES, artist_key, track_key
from src.routes import lastfm as route
from src.routes import navidrome as navidrome_routes
from src.routes.navidrome import ID_MAX, SHUFFLE_FIELDS
from src.store import JobStore
from tests import test_lastfm_routes as T
from tests.test_lastfm import LIBRARY, answer, radio_order

#? the route's own, before a test replaces it
route_radio_order = route.radio_order

PATH = "/deadwax/lastfm/radio"
FIELDS = {"enabled", "unavailable", "why", "songs"}
NAVIDROME = "http://navidrome:4533"
#? the shared login the stand-in Navidrome checks tokens against
SHARED = ("demo", "demo-pw")
#? noon UTC on the day the recordings were made - the radio's day, unless a test says otherwise
NOON = calendar.timegm((2026, 11, 25, 12, 0, 0))
SEED = {"song_id": "so-seed", "title": "Let It Happen", "artist": "Tame Impala", "scope": "store"}
#? what record.py asked track.getSimilar and artist.getSimilar with, for the seed
TRACK_ASKED = {"artist": "Tame Impala", "track": "Let It Happen", "limit": "100", "autocorrect": "1"}
SIMILAR_ASKED = {"artist": "Tame Impala", "autocorrect": "1", "limit": "30"}
UNKNOWN_SONG = "Qzxvwy Nonexistent Song 7731"
LONG = chr(0xFDFA) * route.WORDS_MAX

#? SHAPED: track.getSimilar for what record.py doesn't record. A track Last.fm doesn't know: error 6, as its API
#? pages give it for track.getInfo ("Track not found") and as the recorded not-known answers for an artist are
#? (HTTP 200) - NOT verified against track.getSimilar itself. Names past what Last.fm has, and the unknown artist:
#? the same. The seed of 500 letters: a list of nothing, shaped from the recorded list's envelope
TRACK_NOT_KNOWN = (200, {"error": 6, "message": "Track not found", "links": []})
RADIO_UNRECORDED = [
    ("track.getsimilar", {"artist": "Tame Impala", "track": UNKNOWN_SONG, "limit": "100", "autocorrect": "1"},
     TRACK_NOT_KNOWN),
    ("track.getsimilar", {"artist": T.UNKNOWN_NAME, "track": UNKNOWN_SONG, "limit": "100", "autocorrect": "1"},
     TRACK_NOT_KNOWN),
    ("track.getsimilar", {"artist": LONG, "track": LONG, "limit": "100", "autocorrect": "1"},
     (200, {"similartracks": {"track": [], "@attr": {"artist": LONG}}})),
]


def radio_lastfm() -> "T.LastFm":
    """tests/test_lastfm_routes.py's Last.fm, with the radio's SHAPED answers."""
    fake = T.LastFm()
    for method, params, (status, body) in RADIO_UNRECORDED:
        assert (method, T._params(params)) not in fake.files, "a recording now holds what RADIO_UNRECORDED shapes"
        fake.add(method, params, status, body)
    return fake


class Library:
    """
    Navidrome's search3, as the Shuffle reads it (SHAPED from 0.64.2's source - tests/test_navidrome_shuffle.py):
    the empty query answers `songs` in their natural order, paged by songOffset and songCount; the shared login's
    token checked. Anything else is a failure, and recorded as asked. The answer is sent as JSON with ASCII escapes,
    so a lone surrogate in a song's words gets through as Navidrome's JSON could send it.
    """

    def __init__(self, songs: list[dict] | None = None) -> None:
        self.songs = [dict(song) for song in (LIBRARY if songs is None else songs)]
        self.calls: list[tuple[str, dict]] = []
        self.down = False
        #? an answer in place of search3's: a Subsonic failure
        self.instead: dict | None = None

    def handle(self, request: httpx.Request) -> httpx.Response:
        endpoint = request.url.path.removeprefix("/rest/")
        q = dict(request.url.params)
        self.calls.append((endpoint, q))
        if self.down:
            raise httpx.ConnectError("connection refused")
        token = hashlib.md5((SHARED[1] + q.get("s", "")).encode()).hexdigest()
        if q.get("u") != SHARED[0] or q.get("t") != token:
            body = subsonic_failed(40, "Wrong username or password")
        elif self.instead is not None:
            body = self.instead
        elif endpoint == "search3" and q.get("query") == "":
            offset, count = int(q.get("songOffset", 0)), int(q.get("songCount", 20))
            body = {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome",
                                          "searchResult3": {"song": self.songs[offset:offset + count]}}}
        else:
            body = subsonic_failed(0, f"not in this stand-in: {endpoint}")
        return httpx.Response(200, content=json.dumps(body).encode("ascii"),
                              headers={"Content-Type": "application/json"})

    def asked(self, endpoint: str = "search3") -> list[dict]:
        return [q for called, q in self.calls if called == endpoint]


def subsonic_failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


class Env:
    pass


@pytest.fixture
def radio(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    monkeypatch.setattr(Config, "LASTFM_API_KEY", T.KEY)
    monkeypatch.setattr(Config, "NAVIDROME_URL", NAVIDROME)
    monkeypatch.setattr(Config, "NAVIDROME_USER", SHARED[0])
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", SHARED[1])
    monkeypatch.setattr(lastfm_endpoint, "PER_SECOND", 1000)
    e = Env()
    e.now = NOON
    monkeypatch.setattr(route, "clock", lambda: e.now)
    navidrome_routes.forget_shuffles()
    e.fake, e.library = radio_lastfm(), Library()
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(e.library.handle), base_url=f"{NAVIDROME}/rest")
    e.store = JobStore(str(tmp_path / "deadwax.db"))
    e.store.init()
    e.db = tmp_path / "deadwax.db"
    with T.serving(e.store, e.fake) as (app, client):
        e.app, e.client = app, client
        yield e
        client.portal.call(navidrome.close_client)
    navidrome.client = None
    navidrome_routes.forget_shuffles()
    assert e.fake.unmatched == [], "asked Last.fm something no recording or shaped answer holds"
    assert set(e.fake.keys) <= {T.KEY}


def ask(env, **query) -> dict:
    response = env.client.get(PATH, params={**SEED, **query})
    assert response.status_code == 200, response.text
    assert set(response.json()) == FIELDS
    return response.json()


def ids(got: dict | list) -> list[str]:
    return [song["id"] for song in (got["songs"] if isinstance(got, dict) else got)]


def recorded_names(name: str = "Tame Impala") -> list[str]:
    return [entry["name"] for entry in similar_of(similar_artists(answer("tame-impala.similar.name")), None, name)]


def made(songs=None, tracks: bool = True, similar: bool = True, seed=("so-seed", "Let It Happen", "Tame Impala"),
         user: str = "local", day: str = "2026-11-25") -> list[dict]:
    """What the pure radio_order() makes of the recorded answers and `songs` (LIBRARY): what the route must answer."""
    listed = similar_tracks(answer("tame-impala.let-it-happen.similar"))["tracks"] if tracks else []
    return radio_order(LIBRARY if songs is None else songs, listed, recorded_names() if similar else [], *seed, user,
                       day)


def kept_rows(env) -> dict[str, str | None]:
    return T.kept_rows(env)


# ----- a radio --------------------------------------------------------------------------------------------------------

def test_a_radio_is_the_songs_of_your_scope_last_fm_calls_similar(radio):
    got = ask(radio)
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, False, None)
    assert got["songs"] == made() and len(got["songs"]) == 25
    #? each song as the Shuffle answers one - Navidrome's own fields, nothing else - so the app plays it as it plays one
    for song in got["songs"]:
        assert set(song) <= set(SHUFFLE_FIELDS) and song == next(s for s in LIBRARY if s["id"] == song["id"])
    assert "so-seed" not in ids(got) and "so-seed-live" not in ids(got)
    #? Last.fm asked as record.py asked it, once each; Navidrome's songs read once, a page
    assert radio.fake.asked("track.getsimilar") == [TRACK_ASKED]
    assert radio.fake.asked("artist.getsimilar") == [SIMILAR_ASKED]
    assert len(radio.fake.requests) == 2
    assert [q["songOffset"] for q in radio.library.asked()] == ["0"]


def test_the_three_are_asked_at_once(radio):
    radio.fake.slow = {"track.getsimilar": 0.4, "artist.getsimilar": 0.4}
    began = time.monotonic()
    assert ask(radio)["songs"] == made()
    assert time.monotonic() - began < 0.7, "the parts were asked one after another"


def test_a_second_radio_asks_last_fm_nothing_and_reuses_the_scopes_songs(radio):
    first = ask(radio)
    rows = kept_rows(radio)
    assert set(rows) == {track_key("track.getsimilar", "Tame Impala", "Let It Happen"),
                         artist_key("artist.getsimilar", name="Tame Impala")}
    #? deadwax's shape kept, never Last.fm's answer
    assert json.loads(rows[track_key("track.getsimilar", "Tame Impala", "Let It Happen")]) == similar_tracks(
        answer("tame-impala.let-it-happen.similar"))
    assert ask(radio) == first
    assert len(radio.fake.requests) == 2 and len(radio.library.asked()) == 1
    #? the Shuffle's own list: a shuffle after it reads Navidrome no more
    assert radio.client.get("/deadwax/navidrome/shuffle?scope=store").json()["total"] == len(LIBRARY)
    assert len(radio.library.asked()) == 1


def test_the_artist_page_and_the_radio_share_the_similar_artists_row(radio):
    page = radio.client.get(T.PATH, params={"name": "Tame Impala"})
    assert page.status_code == 200
    asked = len(radio.fake.asked("artist.getsimilar"))
    assert ask(radio)["songs"] == made()
    assert len(radio.fake.asked("artist.getsimilar")) == asked == 1
    assert radio.fake.asked("track.getsimilar") == [TRACK_ASKED]


def test_the_seeds_words_are_asked_as_its_key_reads_them(radio):
    """A remaster's, a live take's or a feature's words ask Last.fm what record.py recorded - the one row they share."""
    got = ask(radio, title="Let It Happen - 2015 Remaster", artist="Tame Impala feat. Someone Else")
    assert radio.fake.asked("track.getsimilar") == [TRACK_ASKED]
    assert radio.fake.asked("artist.getsimilar") == [SIMILAR_ASKED]
    assert got["songs"] == made(seed=("so-seed", "Let It Happen - 2015 Remaster", "Tame Impala feat. Someone Else"))
    assert ask(radio, title=" Let It Happen (Live) ")["songs"] == got["songs"]
    assert len(radio.fake.requests) == 2


@pytest.fixture
def new_york():
    """The server's clock in New York, where UTC's day turns over at 19:00 (EST) - so a radio seeded by the local day
    would differ from one seeded by UTC's at the hours the test asks at. Put back afterwards."""
    before = os.environ.get("TZ")
    os.environ["TZ"] = "America/New_York"
    time.tzset()
    assert time.localtime(calendar.timegm((2026, 11, 25, 0, 0, 1))).tm_mday == 24
    try:
        yield
    finally:
        if before is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = before
        time.tzset()


def test_the_same_radio_all_day_and_another_the_next(radio, new_york):
    """A day by UTC, whatever the server's TZ: at 00:00:01 UTC on the 25th it is still the 24th in New York, and at
    00:00:01 on the 26th still the 25th."""
    first = ask(radio)
    radio.now = calendar.timegm((2026, 11, 25, 0, 0, 1))
    assert ask(radio) == first
    radio.now = calendar.timegm((2026, 11, 25, 23, 59, 59))
    assert ask(radio) == first
    radio.now = calendar.timegm((2026, 11, 26, 0, 0, 1))
    following = ask(radio)
    assert following["songs"] == made(day="2026-11-26") and ids(following) != ids(first)
    #? Last.fm's twenty the same; only the widening moved
    assert ids(following)[:5] == ids(first)[:5]


# ----- what Last.fm doesn't know -------------------------------------------------------------------------------------

def test_a_song_last_fm_doesnt_know_is_widened_by_its_artists_similar_artists(radio):
    got = ask(radio, song_id="so-elsewhere", title=UNKNOWN_SONG)
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, False, None)
    assert got["songs"] == made(tracks=False, seed=("so-elsewhere", UNKNOWN_SONG, "Tame Impala"))
    assert 0 < len(got["songs"]) < 25
    #? the "not known" kept - asked again, nothing more is asked
    asked = len(radio.fake.requests)
    assert ask(radio, song_id="so-elsewhere", title=UNKNOWN_SONG) == got
    assert len(radio.fake.requests) == asked


def test_nothing_while_the_similar_artists_failed_is_null_not_a_definite_nothing(radio):
    """Last.fm doesn't know the song, and its artist's similar artists - which would have widened it - failed: no
    songs, but not "none similar". null and unavailable, so the app asks again."""
    radio.fake.instead = {"artist.getsimilar": (500, {"error": 8, "message": "Operation failed"})}
    got = ask(radio, song_id="so-elsewhere", title=UNKNOWN_SONG)
    assert got == {"enabled": True, "unavailable": True, "why": None, "songs": None}


def test_nothing_while_the_similar_artists_were_late_is_null_too(radio, monkeypatch):
    monkeypatch.setattr(route, "RADIO_DEADLINE_S", 0.3)
    radio.fake.slow = {"artist.getsimilar": 1.0}
    got = ask(radio, song_id="so-elsewhere", title=UNKNOWN_SONG)
    assert got == {"enabled": True, "unavailable": True, "why": None, "songs": None}
    T.until(lambda: artist_key("artist.getsimilar", name="Tame Impala") in kept_rows(radio))
    radio.fake.slow = {}
    assert ask(radio, song_id="so-elsewhere", title=UNKNOWN_SONG)["songs"] == made(
        tracks=False, seed=("so-elsewhere", UNKNOWN_SONG, "Tame Impala"))


def test_the_radio_is_made_off_the_event_loop(radio, monkeypatch):
    """radio_order keys every song of the scope - seconds at SHUFFLE_MAX - so it runs in a thread, never stalling the
    other routes (a stream's among them) while it works."""
    made_in = []

    def watched(*args):
        try:
            asyncio.get_running_loop()
            made_in.append("the event loop")
        except RuntimeError:
            made_in.append("a thread")
        return route_radio_order(*args)

    monkeypatch.setattr(route, "radio_order", watched)
    assert ask(radio)["songs"] == made()
    assert made_in == ["a thread"]


def test_an_artist_last_fm_doesnt_know_is_no_songs_and_nothing_failed(radio):
    got = ask(radio, song_id="so-elsewhere", title=UNKNOWN_SONG, artist=T.UNKNOWN_NAME)
    assert got == {"enabled": True, "unavailable": False, "why": None, "songs": []}


def test_words_that_fold_to_nothing_are_never_asked_by(radio):
    got = ask(radio, title="!!!")
    assert radio.fake.asked("track.getsimilar") == []
    assert got["songs"] == made(tracks=False, seed=("so-seed", "!!!", "Tame Impala")) and not got["unavailable"]
    assert ask(radio, title="!!!", artist="???") == {"enabled": True, "unavailable": False, "why": None, "songs": []}
    assert radio.fake.asked("artist.getsimilar") == [SIMILAR_ASKED]


def test_a_seed_of_five_hundred_letters_is_asked_and_kept_under_a_digest(radio):
    got = ask(radio, title=LONG, artist=LONG)
    assert got == {"enabled": True, "unavailable": False, "why": None, "songs": []}
    #? the artist's similar artists not asked: past NAME_MAX, its key would leave the row no room
    assert radio.fake.asked("artist.getsimilar") == []
    key = track_key("track.getsimilar", LONG, LONG)
    assert "|digest|" in key and key in kept_rows(radio)
    with sqlite3.connect(radio.db) as connection:
        assert max(len(k) + len(b or "") for k, b in connection.execute("SELECT key, body FROM lastfm_kept")) < (
            ROW_MAX_BYTES)
    assert ask(radio, title=LONG, artist=LONG) == got and len(radio.fake.requests) == 1


# ----- when something fails ------------------------------------------------------------------------------------------

def test_last_fm_down_is_no_songs_unavailable_and_no_why(radio):
    radio.fake.down = True
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}
    assert kept_rows(radio) == {}


def test_last_fm_limiting_is_a_blip_with_no_why(radio):
    radio.fake.instead = {"track.getsimilar": T.SHAPED_LIMITED, "artist.getsimilar": T.SHAPED_LIMITED}
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}


def test_the_similar_artists_failing_leaves_the_similar_tracks_songs(radio):
    radio.fake.instead = {"artist.getsimilar": (500, {"error": 8, "message": "Operation failed"})}
    got = ask(radio)
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)
    assert got["songs"] == made(similar=False) and len(got["songs"]) == 20


def test_the_similar_tracks_failing_is_no_songs(radio):
    radio.fake.instead = {"track.getsimilar": (500, {"error": 8, "message": "Operation failed"})}
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}


def test_a_fault_in_deadwax_reading_the_similar_tracks_is_never_a_500(radio, monkeypatch):
    def broken(body):
        raise KeyError("a fault")
    monkeypatch.setattr(route, "TRACK", ("track.getsimilar", route.TRACK[1], broken))
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}


def test_a_part_past_the_deadline_is_left_out_and_kept_when_it_comes(radio, monkeypatch):
    assert route.RADIO_DEADLINE_S == 4.0
    monkeypatch.setattr(route, "RADIO_DEADLINE_S", 0.3)
    radio.fake.slow = {"track.getsimilar": 1.0}
    began = time.monotonic()
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}
    assert time.monotonic() - began < 0.8, "the radio waited for the late part"
    T.until(lambda: track_key("track.getsimilar", "Tame Impala", "Let It Happen") in kept_rows(radio))
    radio.fake.slow = {}
    again = ask(radio)
    assert again["songs"] == made() and not again["unavailable"]
    assert len(radio.fake.asked("track.getsimilar")) == 1


def test_navidrome_down_is_no_songs_unavailable_and_no_why_and_last_fm_is_still_kept(radio):
    radio.library.down = True
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}
    assert len(kept_rows(radio)) == 2
    radio.library.down = False
    assert ask(radio)["songs"] == made() and len(radio.fake.requests) == 2


def test_navidrome_failing_says_why_in_deadwaxs_words(radio):
    radio.library.instead = subsonic_failed(40, "Wrong username or password")
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": SUBSONIC_ERRORS[40], "songs": None}


def test_navidrome_not_set_up_says_so(radio, monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": NOT_CONFIGURED, "songs": None}
    assert radio.library.calls == []


def test_a_library_too_big_to_match_says_so_and_never_crashes(radio, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "SHUFFLE_MAX", 10)
    got = ask(radio)
    assert got == {"enabled": True, "unavailable": True, "why": too_big_why(10), "songs": None}
    assert got["why"] == "Your library is too big to match radio songs against (over 10 songs)."


def test_a_fault_in_deadwax_reading_the_scope_is_never_a_500(radio, monkeypatch):
    async def broken(request, user, scope):
        raise RuntimeError("a fault")
    monkeypatch.setattr(navidrome_routes, "songs_of", broken)
    assert ask(radio) == {"enabled": True, "unavailable": True, "why": None, "songs": None}


def test_a_lone_surrogate_in_navidromes_words_is_answered_whole(radio):
    lone = chr(0xD800)
    radio.library.songs[4]["album"] = "Oracular" + lone + "Spectacular"
    assert radio.library.songs[4]["id"] == "so-kids"
    response = radio.client.get(PATH, params=SEED)
    assert response.status_code == 200
    kids = next(song for song in response.json()["songs"] if song["id"] == "so-kids")
    assert kids["album"] == "Oracular" + chr(0xFFFD) + "Spectacular"


# ----- the key ------------------------------------------------------------------------------------------------------

def test_no_key_asks_nothing_of_last_fm_or_navidrome(radio, monkeypatch):
    monkeypatch.setattr(Config, "LASTFM_API_KEY", "   ")
    assert ask(radio) == {"enabled": False, "unavailable": False, "why": NO_KEY_WHY, "songs": None}
    assert radio.fake.requests == [] and radio.library.calls == [] and kept_rows(radio) == {}


def test_refused_with_nothing_kept_is_off_and_says_why_without_the_key(radio):
    radio.fake.instead = {"track.getsimilar": T.SHAPED_REFUSED, "artist.getsimilar": T.SHAPED_REFUSED}
    response = radio.client.get(PATH, params=SEED)
    got = response.json()
    assert (got["enabled"], got["unavailable"], got["songs"]) == (False, True, None)
    assert got["why"].startswith("Last.fm refused deadwax's API key (error 10:") and T.KEY not in response.text
    assert kept_rows(radio) == {}
    #? held: the next radio asks Last.fm nothing
    asked = len(radio.fake.requests)
    assert ask(radio)["enabled"] is False and len(radio.fake.requests) == asked


def test_refused_answers_what_was_kept_and_still_says_why(radio):
    first = ask(radio)
    with sqlite3.connect(radio.db) as connection:
        connection.execute("UPDATE lastfm_kept SET fetched_at = fetched_at - ?", (40 * DAY,))
    radio.fake.instead = {"track.getsimilar": T.SHAPED_REFUSED, "artist.getsimilar": T.SHAPED_REFUSED}
    got = ask(radio)
    assert got["enabled"] and not got["unavailable"] and got["songs"] == first["songs"]
    assert got["why"].startswith("Last.fm refused deadwax's API key (error 10:")


# ----- the query -----------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("query", [
    {"song_id": None}, {"title": None}, {"artist": None}, {"scope": None},
    {"song_id": ""}, {"title": ""}, {"artist": ""}, {"title": "   "}, {"artist": " "},
    {"song_id": "x" * (ID_MAX + 1)}, {"title": "x" * (route.WORDS_MAX + 1)}, {"artist": "x" * (route.WORDS_MAX + 1)},
    {"scope": "all"}, {"scope": "Yours"},
])
def test_a_radio_needs_a_song_and_a_scope(radio, query):
    params = {name: value for name, value in {**SEED, **query}.items() if value is not None}
    response = radio.client.get(PATH, params=params)
    assert response.status_code == 422
    if query in ({"title": "   "}, {"artist": " "}):
        assert response.json()["detail"] == route.NEEDS_A_SONG
    assert radio.fake.requests == [] and radio.library.calls == []


def test_nothing_the_page_sends_reaches_last_fm_but_the_seeds_words(radio):
    """Names the route doesn't declare are dropped without a word - Last.fm is asked for 100, autocorrected, always."""
    got = ask(radio, limit="5", autocorrect="0", user="ethan", day="2026-12-01", track="Glory Box")
    assert got["songs"] == made()
    assert radio.fake.asked("track.getsimilar") == [TRACK_ASKED]


def test_the_largest_seed_words_are_taken(radio):
    assert radio.client.get(PATH, params={**SEED, "song_id": "x" * ID_MAX}).status_code == 200


# ----- the app's fixtures ---------------------------------------------------------------------------------------------

#? the iPhone app's copy, on the `ios` branch once the exporter has been run there
APP_RADIO = T.APP_COPY.parent / "radio.json"


def test_the_radios_answers_for_the_app_are_the_route_and_the_same_each_time(tmp_path):
    helper = T.exporter()
    assert helper.main(["--out", str(tmp_path)]) == 0
    written = json.loads((tmp_path / "radio.json").read_text(encoding="ascii"))
    assert written["fixtures"] == T.ANSWERS.name and len(written["cases"]) == len(helper.RADIO_CASES)
    for case in written["cases"]:
        assert case["status"] == 200 and set(case["answer"]) == FIELDS, case["name"]
        for song in case["answer"]["songs"] or []:
            assert isinstance(song["id"], str) and set(song) <= set(SHUFFLE_FIELDS), case["name"]
    answers = [case["answer"] for case in written["cases"]]
    assert answers[0]["songs"] == made() and answers[1]["songs"] == made(
        tracks=False, seed=("so-elsewhere", UNKNOWN_SONG, "Tame Impala"))
    #? each of the shapes the app reads: songs, none, null with and without why, off
    assert [None if a["songs"] is None else len(a["songs"]) for a in answers] == [25, 16, 0, 20, None, None, None, None,
                                                                                   None, None]
    #? [] only where every part was had; nothing with a part not had is null
    assert (answers[2]["unavailable"], answers[4]["unavailable"]) == (False, True)
    assert answers[7]["why"] == too_big_why(10) and answers[8]["why"].startswith("Last.fm refused")
    assert answers[9] == {"enabled": False, "unavailable": False, "why": NO_KEY_WHY, "songs": None}
    #? made again, it is the same, byte for byte - and --check says so, of each file
    assert helper.main(["--out", str(tmp_path), "--check"]) == 0
    (tmp_path / "radio.json").write_text("{}\n", encoding="ascii")
    assert helper.main(["--out", str(tmp_path), "--check"]) == 1


def test_the_app_s_radio_copy_is_what_the_exporter_makes():
    if not APP_RADIO.exists():
        pytest.skip("no iPhone app copy of the radio's answers in this checkout")
    assert APP_RADIO.read_text(encoding="ascii") == T.exporter().radio_text()
