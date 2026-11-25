"""
GET /deadwax/lastfm/artist (2.1.41, S2; 2.1.43, S4 - notes/lastfm.md; the design's 2.5): src/routes/lastfm.py, asked of
the whole app, start(), with a real SQLite store, the module's own Last.fm client and keeper, and Last.fm as httpx's
MockTransport (LastFm below).

LAST.FM HERE ANSWERS FROM tests/test_lastfm.py's ANSWERS - its own answers, recorded by record.py on 2026-11-25. It
answers a request with the file whose `method` and `params` are exactly the request's (the key and `format` aside), so
every request the route sends must be one record.py records; a request no file answers is a 500, and a test failure
at the end. What no recording holds is given inline: Last.fm down, slow, limiting or answering junk (SHAPED, from its
API pages), refusing the key (the one real refusal kept, REFUSED_INVALID_KEY, and a SHAPED one that echoes the key),
getInfo for an unknown MusicBrainz id (Last.fm's recorded not-known answer for an unknown name, NOT_KNOWN), and
(2.1.43) getSimilar and getTopAlbums for the three askings record.py records only getInfo and getTopTracks of - an
unknown id, an unknown name, the misspelling (UNRECORDED, in every LastFm).

What this holds:
  - the four parts asked at once, by MusicBrainz id, with the parameters record.py asks with; the answer
    {enabled, unavailable, why, url, listeners, top_songs, similar, top_albums} and nothing else;
  - kept: the second visit asks nothing; what is kept is deadwax's parsed shape, never Last.fm's answer;
  - a "not known" by id asks again by name with autocorrect=1, and is kept; with no name, nothing more is asked;
  - one part failing, late or unreadable leaves the others; past ARTIST_DEADLINE_S the page is answered without the
    late part, which is kept when it comes; nothing gets to a 500;
  - (2.1.43) the artist themselves never among their similar artists, by the page's id or name;
  - no key: nothing asked, `enabled` false with `why`; refused: kept answers still answered, else `enabled` false,
    `why` in refused words either way, the key never in it;
  - the query declared: mbid and/or name, at least one, else a 422.
"""

import asyncio
import json
import sqlite3
import time
from contextlib import asynccontextmanager, contextmanager
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from src import lastfm as lastfm_rules
from src import lastfm_kept
from src.api import lastfm_endpoint
from src.api.app import start
from src.api.lastfm_endpoint import lastfm
from src.config import Config
from src.lastfm import (CONTENT_BYTES, COUNT_DIGITS, NO_KEY_WHY, URL_MAX, artist_info, count, similar_artists,
                        similar_of, top_albums, top_tracks)
from src.lastfm_kept import DAY, ROW_MAX_BYTES, artist_key
from src.routes import lastfm as route
from src.routes.lastfm import NAME_MAX
from src.store import JobStore
from tests.test_lastfm import ANSWERS, REFUSED_INVALID_KEY, answer

#? a sentinel, 32 hex digits as Last.fm's keys are
KEY = "5e17e1d0b5e17e1d0b5e17e1d0b5e1ab"
TAME = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"
DGD = "16456fed-c9f2-4adf-b6ea-97b648c474d2"
PORTISHEAD = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
#? record.py's id nobody has
UNKNOWN_MBID = "00000000-0000-4000-8000-000000000000"
UNKNOWN_NAME = "Qzxvwy Nonexistent Ensemble 7731"
PATH = "/deadwax/lastfm/artist"
FIELDS = {"enabled", "unavailable", "why", "url", "listeners", "top_songs", "similar", "top_albums"}
#? the four parts, as the route asks them by id
METHODS = ("artist.getinfo", "artist.gettoptracks", "artist.getsimilar", "artist.gettopalbums")

#? Last.fm's own answer for an artist it doesn't know - recorded, for getInfo by an unknown name (HTTP 200, error 6) -
#? given for getInfo by an unknown id too, which record.py doesn't record (its getTopTracks by one answered the same)
NOT_KNOWN = (json.loads((ANSWERS / "unknown-name.info.json").read_text(encoding="ascii"))["status"],
             json.loads((ANSWERS / "unknown-name.info.json").read_text(encoding="ascii"))["answer"])
#? SHAPED: an invalid key, as Last.fm's error codes page describes it - echoing the key, which it never should
SHAPED_REFUSED = (403, {"error": 10, "message": f"Invalid API key - You must be granted a valid key by last.fm ({KEY})"})
SHAPED_LIMITED = (429, {"error": 29, "message": "Rate Limit Exceeded"})
#? SHAPED (2.1.43): getSimilar and getTopAlbums for what record.py records only getInfo and getTopTracks of. The unknown
#? id and name: NOT_KNOWN, as their getTopTracks answered. The misspelling: Last.fm has a page under it (nine songs
#? scrobbled as typed - its recorded getInfo and getTopTracks), so lists of nothing, shaped from the recorded lists
UNRECORDED = {
    **{(method, frozenset({"mbid": UNKNOWN_MBID, "limit": limit}.items())): NOT_KNOWN
       for method, limit in (("artist.getsimilar", "30"), ("artist.gettopalbums", "50"))},
    **{(method, frozenset({"artist": UNKNOWN_NAME, "autocorrect": "1", "limit": limit}.items())): NOT_KNOWN
       for method, limit in (("artist.getsimilar", "30"), ("artist.gettopalbums", "50"))},
    ("artist.getsimilar", frozenset({"artist": "Tame Impla", "autocorrect": "1", "limit": "30"}.items())):
        (200, {"similarartists": {"artist": [], "@attr": {"artist": "Tame Impla"}}}),
    ("artist.gettopalbums", frozenset({"artist": "Tame Impla", "autocorrect": "1", "limit": "50"}.items())):
        (200, {"topalbums": {"album": [], "@attr": {"artist": "Tame Impla", "page": "1", "perPage": "50",
                                                     "totalPages": "0", "total": "0"}}}),
}


def _params(params: dict) -> frozenset:
    return frozenset(params.items())


class LastFm:
    """Last.fm's API, from ANSWERS' files: each request answered with the file asked exactly as it was."""

    def __init__(self) -> None:
        self.files: dict[tuple[str, frozenset], tuple[int, object]] = {}
        for path in sorted(ANSWERS.glob("*.json")):
            held = json.loads(path.read_text(encoding="ascii"))
            self.files[(held["method"], _params(held["params"]))] = (held["status"], held["answer"])
        assert not set(UNRECORDED) & set(self.files), "a recording now holds what UNRECORDED shapes: use it"
        self.files.update(UNRECORDED)
        #? (method, params) of every request, the key and `format` aside, in the order they came
        self.requests: list[tuple[str, dict]] = []
        self.keys: list[str | None] = []
        self.unmatched: list[tuple[str, dict]] = []
        #? method -> (status, body), answered in place of the files
        self.instead: dict[str, tuple[int, object]] = {}
        #? method -> seconds to wait before answering, or (a parameter, seconds): only when it was asked with it
        self.slow: dict[str, float | tuple[str, float]] = {}
        self.down = False

    def add(self, method: str, params: dict, status: int, body) -> None:
        """An answer no file holds."""
        self.files[(method, _params(params))] = (status, body)

    def add_every_part(self, params: dict, status: int, body) -> None:
        """One answer for all four parts, asked with `params` (and each part's own limit)."""
        for method, extra in (("artist.getinfo", {}), ("artist.gettoptracks", {"limit": "50"}),
                              ("artist.getsimilar", {"limit": "30"}), ("artist.gettopalbums", {"limit": "50"})):
            self.add(method, {**params, **extra}, status, body)

    def asked(self, method: str | None = None) -> list[dict]:
        return [params for asked, params in self.requests if method is None or asked == method]

    async def handle(self, request: httpx.Request) -> httpx.Response:
        query = dict(request.url.params)
        self.keys.append(query.pop("api_key", None))
        fmt = query.pop("format", None)
        method = query.pop("method", None)
        self.requests.append((method, query))
        if method in self.slow:
            wait = self.slow[method]
            if isinstance(wait, tuple):
                wait = wait[1] if wait[0] in query else 0.0
            await asyncio.sleep(wait)
        if self.down:
            return httpx.Response(503, text="<html>Service Unavailable</html>")
        if method in self.instead:
            status, body = self.instead[method]
            if isinstance(body, bytes):
                #? as Last.fm's JSON could send it, byte for byte - httpx's json= can't send a lone surrogate
                return httpx.Response(status, content=body, headers={"Content-Type": "application/json"})
            return httpx.Response(status, json=body)
        found = self.files.get((method, _params(query)))
        if found is None or fmt != "json":
            self.unmatched.append((method, query))
            return httpx.Response(500, json={"error": 8, "message": "no such answer in the fixtures"})
        status, body = found
        return httpx.Response(status, json=body)


@asynccontextmanager
async def no_lifespan(app):
    #? nothing connects: no slskd, no poller - one event loop for the whole test, so a late part runs on
    yield


@contextmanager
def serving(store: JobStore, fake: LastFm):
    """The whole app over `fake`, on one event loop; the parts and asks still under way stopped at the end, before the
    loop is, and the client as it was."""
    lastfm._client = None
    lastfm.transport = httpx.MockTransport(fake.handle)
    app = start()
    app.state.store = store
    app.router.lifespan_context = no_lifespan
    try:
        with TestClient(app) as client:
            yield app, client
            client.portal.call(route.stop)
            client.portal.call(lastfm_kept.stop)
            client.portal.call(lastfm.close_client)
    finally:
        lastfm._client = None
        lastfm.transport = None
        lastfm.refusal = None
        lastfm.refused_since = 0.0
        lastfm._retrying = False
        lastfm.limited_until = 0.0
        lastfm._starts.clear()
        lastfm._in_flight = 0


class Env:
    pass


@pytest.fixture
def env(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    monkeypatch.setattr(Config, "LASTFM_API_KEY", KEY)
    #? the pace is the client's tests' (tests/test_lastfm_client.py): here it would only make the tests slower
    monkeypatch.setattr(lastfm_endpoint, "PER_SECOND", 1000)
    fake = LastFm()
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    e = Env()
    e.fake, e.store, e.db = fake, store, tmp_path / "deadwax.db"
    with serving(store, fake) as (app, client):
        e.app, e.client = app, client
        yield e
    assert fake.unmatched == [], "asked something record.py doesn't record"
    assert set(fake.keys) <= {KEY}


def ask(env, **query):
    response = env.client.get(PATH, params=query)
    assert response.status_code == 200, response.text
    return response.json()


def kept_rows(env) -> dict[str, str | None]:
    with sqlite3.connect(env.db) as connection:
        return dict(connection.execute("SELECT key, body FROM lastfm_kept").fetchall())


def until(condition, limit: float = 5.0) -> None:
    give_up = time.monotonic() + limit
    while not condition():
        assert time.monotonic() < give_up, "waited too long"
        time.sleep(0.01)


def expected(info_file: str | None, tracks_file: str | None) -> dict:
    """The answer for those two files, as src/lastfm.py parses any answer - so it holds over recorded ones too."""
    info = artist_info(answer(info_file)) if info_file else None
    tracks = top_tracks(answer(tracks_file)) if tracks_file else None
    return {
        "url": (info or {}).get("url") or (tracks or {}).get("artist_url"),
        "listeners": (info or {}).get("listeners"),
        "top_songs": tracks["top_songs"] if tracks else None,
    }


def expected_s4(slug: str | None, by: str = "mbid", mbid: str | None = None, name: str | None = None) -> dict:
    """(2.1.43) The similar artists and top albums for an artist's recordings, as src/lastfm.py makes any answer's."""
    if slug is None:
        return {"similar": None, "top_albums": None}
    return {"similar": similar_of(similar_artists(answer(f"{slug}.similar.{by}")), mbid, name),
            "top_albums": top_albums(answer(f"{slug}.top-albums.{by}"))["top_albums"]}


def parts_of(got: dict) -> dict:
    return {k: got[k] for k in ("url", "listeners", "top_songs")}


def s4_of(got: dict) -> dict:
    return {k: got[k] for k in ("similar", "top_albums")}


# ----- an artist, by MusicBrainz id ----------------------------------------------------------------------------------

@pytest.mark.parametrize("slug, mbid", [("tame-impala", TAME), ("dance-gavin-dance", DGD), ("portishead", PORTISHEAD)])
def test_an_artist_is_their_listeners_their_page_their_top_songs_similar_artists_and_albums(env, slug, mbid):
    got = ask(env, mbid=mbid, name="whoever")
    assert set(got) == FIELDS
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, False, None)
    assert parts_of(got) == expected(f"{slug}.info.mbid", f"{slug}.top-tracks.mbid")
    assert s4_of(got) == expected_s4(slug, mbid=mbid, name="whoever")
    assert isinstance(got["listeners"], int) and got["url"].startswith("https://www.last.fm/")
    assert 0 < len(got["top_songs"]) <= 10
    #? (2.1.43) Last.fm's thirty, none of them the artist; its fifty albums, counted by plays
    assert len(got["similar"]) == 30 and len(got["top_albums"]) == 50
    assert {album["counted"] for album in got["top_albums"]} == {"plays"}
    #? the four parts, by id, asked as record.py asks - never by name while the id is known
    assert sorted(env.fake.requests, key=lambda r: r[0]) == [
        ("artist.getinfo", {"mbid": mbid}), ("artist.getsimilar", {"mbid": mbid, "limit": "30"}),
        ("artist.gettopalbums", {"mbid": mbid, "limit": "50"}), ("artist.gettoptracks", {"mbid": mbid, "limit": "50"})]
    assert env.fake.keys == [KEY] * 4


def test_the_parts_are_asked_at_once(env):
    """Each part waits 0.4 s at Last.fm: one after the other would take 1.6, two at a time 0.8."""
    env.fake.slow = {method: 0.4 for method in METHODS}
    began = time.monotonic()
    got = ask(env, mbid=TAME)
    assert time.monotonic() - began < 0.75
    assert got["top_songs"] and got["listeners"] and got["similar"] and got["top_albums"]


def test_a_second_visit_is_answered_from_what_was_kept_and_asks_nothing(env):
    first = ask(env, mbid=TAME)
    assert len(env.fake.requests) == 4
    assert ask(env, mbid=TAME) == first
    assert len(env.fake.requests) == 4
    rows = kept_rows(env)
    assert set(rows) == {artist_key(method, mbid=TAME) for method in METHODS}
    #? deadwax's own shape, parsed and folded - never Last.fm's answer
    tracks = json.loads(rows[artist_key("artist.gettoptracks", mbid=TAME)])
    assert tracks == top_tracks(answer("tame-impala.top-tracks.mbid"))
    assert "toptracks" not in rows[artist_key("artist.gettoptracks", mbid=TAME)]
    assert json.loads(rows[artist_key("artist.getinfo", mbid=TAME)]) == artist_info(answer("tame-impala.info.mbid"))
    #? (2.1.43) the similar artists and albums the same: parsed, 4-5 KB of Last.fm's 32-50 KB, no images
    assert json.loads(rows[artist_key("artist.getsimilar", mbid=TAME)]) == similar_artists(
        answer("tame-impala.similar.mbid"))
    assert json.loads(rows[artist_key("artist.gettopalbums", mbid=TAME)]) == top_albums(
        answer("tame-impala.top-albums.mbid"))
    for method in ("artist.getsimilar", "artist.gettopalbums"):
        assert "image" not in rows[artist_key(method, mbid=TAME)] and len(rows[artist_key(method, mbid=TAME)]) < 6000


# ----- by name, and the fallback -------------------------------------------------------------------------------------

def test_an_id_last_fm_doesnt_know_is_asked_again_by_name(env):
    #? record.py records getTopTracks for the id nobody has; getInfo for it is SHAPED here
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    got = ask(env, mbid=UNKNOWN_MBID, name="Tame Impala")
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, False, None)
    assert parts_of(got) == expected("tame-impala.info.name", "tame-impala.top-tracks.name")
    assert s4_of(got) == expected_s4("tame-impala", "name", name="Tame Impala")
    for method, extra in (("artist.getinfo", {}), ("artist.gettoptracks", {"limit": "50"}),
                          ("artist.getsimilar", {"limit": "30"}), ("artist.gettopalbums", {"limit": "50"})):
        assert env.fake.asked(method) == [{"mbid": UNKNOWN_MBID, **extra},
                                          {"artist": "Tame Impala", "autocorrect": "1", **extra}]
    #? the "not known" kept (as none), and the answer by name kept under the name
    rows = kept_rows(env)
    for method in METHODS:
        assert rows[artist_key(method, mbid=UNKNOWN_MBID)] is None
        assert rows[artist_key(method, name="Tame Impala")] is not None
    assert ask(env, mbid=UNKNOWN_MBID, name="tame impala") == got
    assert len(env.fake.requests) == 8


def test_a_misspelt_name_is_asked_with_autocorrect_and_answered_with_the_page_last_fm_has_for_it(env):
    """Recorded: autocorrect doesn't correct "Tame Impla" - Last.fm has a page under the misspelling (scrobbles typed
    so), and answers that. The app asks by the MusicBrainz name, so it meets this only for a name misspelt there."""
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    got = ask(env, mbid=UNKNOWN_MBID, name="Tame Impla")
    assert parts_of(got) == expected("misspelt.info", "misspelt.top-tracks")
    assert s4_of(got) == {"similar": [], "top_albums": []}
    assert (got["url"], got["listeners"]) == ("https://www.last.fm/music/Tame+Impla", 9)
    assert env.fake.asked("artist.getinfo")[-1] == {"artist": "Tame Impla", "autocorrect": "1"}


def test_with_no_id_the_artist_is_asked_by_name(env):
    got = ask(env, name="  Tame Impala ")
    assert parts_of(got) == expected("tame-impala.info.name", "tame-impala.top-tracks.name")
    assert s4_of(got) == expected_s4("tame-impala", "name", name="Tame Impala")
    by_name = {"artist": "Tame Impala", "autocorrect": "1"}
    assert sorted(env.fake.requests, key=lambda r: r[0]) == [
        ("artist.getinfo", by_name), ("artist.getsimilar", {**by_name, "limit": "30"}),
        ("artist.gettopalbums", {**by_name, "limit": "50"}), ("artist.gettoptracks", {**by_name, "limit": "50"})]


def test_an_id_last_fm_doesnt_know_and_no_name_is_nothing_and_nothing_more_asked(env):
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    got = ask(env, mbid=UNKNOWN_MBID)
    assert got == {"enabled": True, "unavailable": False, "why": None, "url": None, "listeners": None,
                   "top_songs": None, "similar": None, "top_albums": None}
    assert len(env.fake.requests) == 4


def test_an_artist_last_fm_doesnt_know_by_name_is_nothing_kept_as_none(env):
    got = ask(env, name=UNKNOWN_NAME)
    assert got == {"enabled": True, "unavailable": False, "why": None, "url": None, "listeners": None,
                   "top_songs": None, "similar": None, "top_albums": None}
    assert set(kept_rows(env).values()) == {None} and len(kept_rows(env)) == 4
    ask(env, name=UNKNOWN_NAME)
    assert len(env.fake.requests) == 4


def test_a_name_that_folds_to_nothing_is_never_asked_by(env):
    """It would share one kept row with every other such name."""
    got = ask(env, name="!!!")
    assert (got["url"], got["listeners"], got["top_songs"], got["unavailable"]) == (None, None, None, False)
    assert s4_of(got) == {"similar": None, "top_albums": None}
    assert env.fake.requests == []


# ----- what goes wrong -----------------------------------------------------------------------------------------------

def test_one_part_failing_leaves_the_other(env):
    env.fake.instead["artist.getinfo"] = (500, {"error": 8, "message": "Operation failed"})
    got = ask(env, mbid=TAME)
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)
    assert got["listeners"] is None
    assert got["top_songs"] == expected(None, "tame-impala.top-tracks.mbid")["top_songs"]
    #? the page's address from the top tracks' artist
    assert got["url"] == top_tracks(answer("tame-impala.top-tracks.mbid"))["artist_url"]
    #? the failure isn't kept: the next visit asks getInfo again, and not the top tracks
    del env.fake.instead["artist.getinfo"]
    again = ask(env, mbid=TAME)
    assert again["listeners"] == expected("tame-impala.info.mbid", None)["listeners"] and not again["unavailable"]
    assert [method for method, _ in env.fake.requests].count("artist.gettoptracks") == 1


def test_the_other_part_failing_too(env):
    env.fake.instead["artist.gettoptracks"] = (200, "<html>not JSON</html>")
    got = ask(env, mbid=TAME)
    assert got["unavailable"] and got["top_songs"] is None and got["listeners"] is not None


def test_an_answer_deadwax_cant_read_is_a_part_not_had_and_not_kept(env):
    env.fake.instead["artist.gettoptracks"] = (200, {"unexpected": True})
    got = ask(env, mbid=TAME)
    assert got["unavailable"] and got["top_songs"] is None
    assert artist_key("artist.gettoptracks", mbid=TAME) not in kept_rows(env)


def test_a_fault_in_deadwax_reading_an_answer_is_never_a_500(env, monkeypatch):
    def broken(body):
        raise KeyError("a fault")
    monkeypatch.setattr(route, "TRACKS", ("artist.gettoptracks", {"limit": "50"}, broken))
    got = ask(env, mbid=TAME)
    assert got["unavailable"] and got["top_songs"] is None and got["listeners"] is not None


def test_last_fm_down_with_nothing_kept_is_parts_not_had_and_no_why(env):
    env.fake.down = True
    got = ask(env, mbid=TAME, name="Tame Impala")
    assert got == {"enabled": True, "unavailable": True, "why": None, "url": None, "listeners": None,
                   "top_songs": None, "similar": None, "top_albums": None}
    #? a failure by id is no "not known": nothing is asked by name
    assert all("mbid" in params for params in env.fake.asked())


def test_last_fm_limiting_is_a_blip_with_no_why(env):
    env.fake.instead = {method: SHAPED_LIMITED for method in METHODS}
    got = ask(env, mbid=TAME)
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)


def test_last_fm_down_answers_what_was_kept_however_old(env):
    first = ask(env, mbid=TAME)
    with sqlite3.connect(env.db) as connection:
        connection.execute("UPDATE lastfm_kept SET fetched_at = fetched_at - ?", (90 * DAY,))
    env.fake.down = True
    assert ask(env, mbid=TAME) == first
    assert len(env.fake.requests) == 8


def test_a_part_past_the_deadline_is_left_out_and_kept_when_it_comes(env, monkeypatch):
    assert route.ARTIST_DEADLINE_S == 4.0
    monkeypatch.setattr(route, "ARTIST_DEADLINE_S", 0.3)
    env.fake.slow = {"artist.gettoptracks": 1.0}
    began = time.monotonic()
    got = ask(env, mbid=TAME)
    assert time.monotonic() - began < 0.8, "the page waited for the late part"
    assert got["unavailable"] and got["top_songs"] is None
    assert got["listeners"] == expected("tame-impala.info.mbid", None)["listeners"]
    #? the late part goes on, and is kept when it lands
    until(lambda: artist_key("artist.gettoptracks", mbid=TAME) in kept_rows(env))
    env.fake.slow = {}
    again = ask(env, mbid=TAME)
    assert again["top_songs"] == expected(None, "tame-impala.top-tracks.mbid")["top_songs"] and not again["unavailable"]
    assert [method for method, _ in env.fake.requests].count("artist.gettoptracks") == 1


def test_a_late_part_goes_on_to_ask_by_name_and_that_is_kept_too(env, monkeypatch):
    """The deadline passes while getInfo by id is still out; Last.fm then doesn't know the id. The part goes on as it
    would have: by name, kept - so the next visit has the listeners. Cancelled at the deadline, it would ask nothing
    more (the id's own ask is shielded, and would land and be kept either way)."""
    monkeypatch.setattr(route, "ARTIST_DEADLINE_S", 0.3)
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    env.fake.slow = {"artist.getinfo": ("mbid", 0.8)}
    got = ask(env, mbid=UNKNOWN_MBID, name="Tame Impala")
    assert got["unavailable"] and got["listeners"] is None
    assert got["top_songs"] == expected(None, "tame-impala.top-tracks.name")["top_songs"]
    until(lambda: artist_key("artist.getinfo", name="Tame Impala") in kept_rows(env))
    assert env.fake.asked("artist.getinfo") == [{"mbid": UNKNOWN_MBID}, {"artist": "Tame Impala", "autocorrect": "1"}]
    again = ask(env, mbid=UNKNOWN_MBID, name="Tame Impala")
    assert again["listeners"] == expected("tame-impala.info.name", None)["listeners"] and not again["unavailable"]
    assert len(env.fake.asked("artist.getinfo")) == 2


# ----- similar artists and top albums (2.1.43, S4) ------------------------------------------------------------------

#? what each part puts in the answer
FIELD_OF = {"artist.getinfo": "listeners", "artist.gettoptracks": "top_songs", "artist.getsimilar": "similar",
            "artist.gettopalbums": "top_albums"}


@pytest.mark.parametrize("method", METHODS)
def test_each_part_failing_alone_leaves_the_other_three(env, method):
    """SHAPED: Last.fm's error 8 for one part. The other three are the recordings', whole; the one failed is null,
    the page unavailable, nothing in it kept - the next visit asks that part again, and only that one."""
    whole = {**expected("tame-impala.info.mbid", "tame-impala.top-tracks.mbid"),
             **expected_s4("tame-impala", mbid=TAME, name="Tame Impala")}
    env.fake.instead[method] = (500, {"error": 8, "message": "Operation failed"})
    got = ask(env, mbid=TAME, name="Tame Impala")
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)
    assert got[FIELD_OF[method]] is None
    for other in set(FIELD_OF.values()) - {FIELD_OF[method]}:
        assert got[other] == whole[other] and got[other], other
    assert artist_key(method, mbid=TAME) not in kept_rows(env) and len(kept_rows(env)) == 3
    del env.fake.instead[method]
    again = ask(env, mbid=TAME, name="Tame Impala")
    assert not again["unavailable"] and again[FIELD_OF[method]] == whole[FIELD_OF[method]]
    assert [asked for asked, _ in env.fake.requests[4:]] == [method]


def test_a_late_similar_part_is_left_out_and_kept_when_it_comes(env, monkeypatch):
    monkeypatch.setattr(route, "ARTIST_DEADLINE_S", 0.3)
    env.fake.slow = {"artist.getsimilar": 1.0, "artist.gettopalbums": 1.0}
    began = time.monotonic()
    got = ask(env, mbid=TAME)
    assert time.monotonic() - began < 0.8, "the page waited for the late parts"
    assert got["unavailable"] and got["similar"] is None and got["top_albums"] is None
    assert got["top_songs"] and got["listeners"]
    late = {artist_key(method, mbid=TAME) for method in ("artist.getsimilar", "artist.gettopalbums")}
    until(lambda: late <= set(kept_rows(env)))
    env.fake.slow = {}
    again = ask(env, mbid=TAME)
    assert s4_of(again) == expected_s4("tame-impala", mbid=TAME) and not again["unavailable"]
    assert len(env.fake.requests) == 4


def test_the_artist_is_never_among_their_own_similar_artists(env):
    """SHAPED: no recording lists the artist - here Last.fm does, by their id under another name and by their name
    in other cases, beside Various Artists and an id of the wrong shape. Each asking drops them by what it knows."""
    listed = answer("tame-impala.similar.mbid")
    artists = [{"name": "Kevin Parker Project", "mbid": TAME.upper(), "match": "0.99"},
               {"name": "tame impala", "match": "0.98"}, {"name": "Various Artists", "match": "0.97"},
               {"name": "Pond", "mbid": "a3b8...", "match": "0.96", "url": "https://www.last.fm/music/Pond"},
               *listed["similarartists"]["artist"][1:]]
    env.fake.instead["artist.getsimilar"] = (200, {"similarartists": {**listed["similarartists"], "artist": artists}})
    got = ask(env, mbid=TAME, name="Tame Impala")
    names = [artist["name"] for artist in got["similar"]]
    assert names[0] == "Pond" and got["similar"][0]["mbid"] is None
    assert not {"Kevin Parker Project", "tame impala", "Various Artists"} & set(names)
    #? kept: Last.fm's first thirty but Various Artists (the two of him among them); answered: those, him out
    kept = json.loads(kept_rows(env)[artist_key("artist.getsimilar", mbid=TAME)])
    assert len(kept["similar"]) == 30 and len(names) == 28
    #? asked by the id alone, the name Last.fm answered for (its @attr, kept) still drops the one by name
    assert [artist["name"] for artist in ask(env, mbid=TAME)["similar"]] == names


def test_albums_counted_by_listeners_when_last_fm_gives_no_plays(env):
    """SHAPED, from getTopAlbums' API page, whose sample shows listeners and no playcount: the design's fork."""
    env.fake.instead["artist.gettopalbums"] = (200, {"topalbums": {"album": [
        {"name": "Currents", "mbid": "031ecbde-35e1-4d3a-917f-f89f31aca1c9", "listeners": "456789",
         "url": "https://www.last.fm/music/Tame+Impala/Currents", "@attr": {"rank": "1"}},
        {"name": "Lonerism", "mbid": "", "listeners": "123456", "@attr": {"rank": "2"}}]}})
    got = ask(env, mbid=TAME)
    assert got["top_albums"] == [
        {"title": "Currents", "mbid": "031ecbde-35e1-4d3a-917f-f89f31aca1c9", "plays": 456789, "counted": "listeners"},
        {"title": "Lonerism", "mbid": None, "plays": 123456, "counted": "listeners"}]
    assert not got["unavailable"]


def test_lists_of_nothing_are_kept_and_not_unavailable(env):
    """Known, listing none: [] each, kept - the next visit asks nothing."""
    env.fake.instead["artist.getsimilar"] = (200, {"similarartists": {"artist": [],
                                                                       "@attr": {"artist": "Tame Impala"}}})
    env.fake.instead["artist.gettopalbums"] = (200, {"topalbums": {"album": []}})
    got = ask(env, mbid=TAME)
    assert (got["similar"], got["top_albums"], got["unavailable"]) == ([], [], False)
    assert ask(env, mbid=TAME) == got and len(env.fake.requests) == 4


# ----- what UTF-8 can carry, and what the keeping can keep (2.1.43's review) ---------------------------------------

LONE = chr(0xD800)
FFFD = chr(0xFFFD)


def raw(body) -> bytes:
    """SHAPED: an answer as Last.fm's JSON could send it - ASCII, a lone surrogate as its \\u escape."""
    return json.dumps(body).encode("ascii")


def with_lone_surrogates():
    """Tame Impala's recorded answers, a lone surrogate in a song's, an artist's and an album's name - and a
    "(null)" album beside them."""
    tracks, similar, albums = (answer(f"tame-impala.{part}.mbid") for part in ("top-tracks", "similar", "top-albums"))
    first = tracks["toptracks"]["track"][0]["name"]
    tracks["toptracks"]["track"][0]["name"] = first + LONE
    similar["similarartists"]["artist"][0]["name"] = "Po" + LONE + "nd"
    albums["topalbums"]["album"][0]["name"] = "Curr" + chr(0xDC00) + "ents"
    albums["topalbums"]["album"].insert(1, {"name": "(null)", "playcount": 99})
    return first, {"artist.gettoptracks": tracks, "artist.getsimilar": similar, "artist.gettopalbums": albums}


def test_a_lone_surrogate_from_last_fm_is_answered_and_kept_whole(env):
    """SHAPED (2.1.43's review): JSON's "\\ud800" with no pair after it, in a top song's, a similar artist's and an
    album's name. Kept as it came, the answer's encoder raised on it - a 500 at every visit for a week, Last.fm never
    asked again. Now each is U+FFFD, in the answer and the row, and the next visit is answered from the row."""
    first, bodies = with_lone_surrogates()
    for method, body in bodies.items():
        env.fake.instead[method] = (200, raw(body))
    got = ask(env, mbid=TAME)
    assert got["top_songs"][0]["title"] == first + FFFD
    assert got["similar"][0]["name"] == "Po" + FFFD + "nd"
    assert [album["title"] for album in got["top_albums"][:2]] == ["Curr" + FFFD + "ents", "The Slow Rush"]
    assert not got["unavailable"]
    rows = kept_rows(env)
    for method in bodies:
        row = rows[artist_key(method, mbid=TAME)]
        assert "\\ud800" not in row and "\\udc00" not in row and "\\ufffd" in row, method
    assert ask(env, mbid=TAME) == got and len(env.fake.requests) == 4


def test_a_text_the_parse_let_through_is_still_never_a_500(env, monkeypatch):
    """The route's last guard (lastfm.answerable): with the parse letting a lone surrogate through - as the parse
    before 2.1.43's review did, and its rows were kept so - the answer is still a 200, U+FFFD in its place, on the
    first visit and from the row."""
    monkeypatch.setattr(lastfm_rules, "_name", lambda value: value.strip() if isinstance(value, str) else "")
    first, bodies = with_lone_surrogates()
    for method, body in bodies.items():
        env.fake.instead[method] = (200, raw(body))
    for _ in range(2):
        got = ask(env, mbid=TAME)
        assert got["top_songs"][0]["title"] == first + FFFD and got["similar"][0]["name"] == "Po" + FFFD + "nd"
    assert "\\ud800" in kept_rows(env)[artist_key("artist.getsimilar", mbid=TAME)]
    assert len(env.fake.requests) == 4


def test_the_largest_similar_and_albums_rows_are_kept(env):
    """SHAPED: thirty similar artists and fifty albums named in letters outside the BMP (12 bytes each, kept), asked
    by the name that makes the longest key there is: each row is kept as far as it fits - Last.fm's first - never
    too big to keep and asked again at every visit."""
    name = chr(0xFDFA) * NAME_MAX
    for method, extra in (("artist.getinfo", {}), ("artist.gettoptracks", {"limit": "50"})):
        env.fake.add(method, {"artist": name, "autocorrect": "1", **extra}, *NOT_KNOWN)
    star = chr(0x1F3B8)
    names = [star * 1000 + str(n) for n in range(30)]
    titles = [star * 600 + str(n) for n in range(50)]
    env.fake.instead["artist.getsimilar"] = (200, {"similarartists": {
        "artist": [{"name": artist, "match": "0.5"} for artist in names], "@attr": {"artist": name}}})
    env.fake.instead["artist.gettopalbums"] = (200, {"topalbums": {
        "album": [{"name": title, "playcount": 50 - n} for n, title in enumerate(titles)]}})
    got = ask(env, name=name)
    assert 0 < len(got["similar"]) < 30 and [artist["name"] for artist in got["similar"]] == names[:len(got["similar"])]
    assert 0 < len(got["top_albums"]) < 50
    assert [album["title"] for album in got["top_albums"]] == titles[:len(got["top_albums"])]
    rows = kept_rows(env)
    for method in ("artist.getsimilar", "artist.gettopalbums"):
        key = artist_key(method, name=name)
        assert len(rows[key]) + len(key.encode()) <= ROW_MAX_BYTES, method
    assert ask(env, name=name) == got and len(env.fake.requests) == 4


# ----- the key -------------------------------------------------------------------------------------------------------

def test_no_key_asks_nothing_and_says_where_to_add_one(env, monkeypatch):
    monkeypatch.setattr(Config, "LASTFM_API_KEY", "   ")
    got = ask(env, mbid=TAME, name="Tame Impala")
    assert got == {"enabled": False, "unavailable": False, "why": NO_KEY_WHY, "url": None, "listeners": None,
                   "top_songs": None, "similar": None, "top_albums": None}
    assert env.fake.requests == [] and kept_rows(env) == {}


def test_refused_with_nothing_kept_is_off_and_says_why_without_the_key(env):
    env.fake.instead = {method: SHAPED_REFUSED for method in METHODS}
    response = env.client.get(PATH, params={"mbid": TAME})
    got = response.json()
    assert (got["enabled"], got["unavailable"]) == (False, True)
    assert (got["url"], got["listeners"], got["top_songs"], got["similar"], got["top_albums"]) == (None,) * 5
    assert got["why"] == ("Last.fm refused deadwax's API key (error 10: Invalid API key - You must be granted a valid "
                          "key by last.fm ((the key))) - check LASTFM_API_KEY in Server settings > Connections: it's "
                          "the API key, not the shared secret.")
    assert KEY not in response.text
    assert env.client.get("/deadwax/me").json()["lastfm"] == "refused"
    #? held: the next visit asks Last.fm nothing
    asked = len(env.fake.requests)
    assert ask(env, mbid=TAME)["enabled"] is False
    assert len(env.fake.requests) == asked


def test_last_fms_real_invalid_key_answer_through_the_client_and_the_route(env):
    """RECORDED (tests/test_lastfm.py REFUSED_INVALID_KEY): Last.fm's own 403 with error 10, as the client meets it -
    held as a refusal, and with nothing kept the page is off, saying why."""
    held = json.loads(REFUSED_INVALID_KEY.read_text(encoding="ascii"))
    env.fake.instead = {method: (held["status"], held["answer"]) for method in METHODS}
    got = ask(env, mbid=TAME)
    assert got == {"enabled": False, "unavailable": True,
                   "why": "Last.fm refused deadwax's API key (error 10: Invalid API key - You must be granted a valid "
                          "key by last.fm) - check LASTFM_API_KEY in Server settings > Connections: it's the API key, "
                          "not the shared secret.",
                   "url": None, "listeners": None, "top_songs": None, "similar": None, "top_albums": None}
    assert lastfm.held() is not None and lastfm.held().error == 10
    assert env.client.get("/deadwax/me").json()["lastfm"] == "refused"


def test_refused_answers_what_was_kept_and_still_says_why(env):
    first = ask(env, mbid=TAME)
    with sqlite3.connect(env.db) as connection:
        connection.execute("UPDATE lastfm_kept SET fetched_at = fetched_at - ?", (40 * DAY,))
    env.fake.instead = {method: SHAPED_REFUSED for method in METHODS}
    got = ask(env, mbid=TAME)
    assert got["enabled"] and not got["unavailable"]
    assert got["why"].startswith("Last.fm refused deadwax's API key (error 10:")
    assert {k: v for k, v in got.items() if k != "why"} == {k: v for k, v in first.items() if k != "why"}


# ----- the query -----------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("query", [
    {}, {"name": ""}, {"name": "   "}, {"name": "x" * 201}, {"mbid": "not-an-id"}, {"mbid": TAME.upper()},
    {"mbid": ""},
    #? names the route doesn't declare are dropped without a word, so they ask for nothing
    {"artist": "Tame Impala"}, {"id": TAME},
])
def test_an_artist_is_needed_by_id_or_name(env, query):
    assert env.client.get(PATH, params=query).status_code == 422
    assert env.fake.requests == []


def test_a_name_of_two_hundred_letters_is_taken(env):
    env.fake.add_every_part({"artist": "x" * 200, "autocorrect": "1"}, *NOT_KNOWN)
    assert ask(env, name="x" * 200)["top_songs"] is None


def test_the_largest_info_row_there_can_be_is_kept(env):
    """The longest key a name of NAME_MAX letters makes (U+FDFA folds to 18 letters), the longest address passed on,
    a listener count of COUNT_DIGITS, and a bio in letters outside the BMP: kept, under ROW_MAX_BYTES."""
    name = chr(0xFDFA) * NAME_MAX
    link = "https://www.last.fm/music/" + "%" * (URL_MAX - 26)
    env.fake.add("artist.getinfo", {"artist": name, "autocorrect": "1"}, 200,
                 {"artist": {"name": name, "url": link, "stats": {"listeners": "9" * COUNT_DIGITS},
                             "bio": {"summary": chr(0x1F3B8) * 5000, "content": chr(0x1F3B8) * 5000}}})
    env.fake.add("artist.gettoptracks", {"artist": name, "autocorrect": "1", "limit": "50"}, *NOT_KNOWN)
    env.fake.add("artist.getsimilar", {"artist": name, "autocorrect": "1", "limit": "30"}, *NOT_KNOWN)
    env.fake.add("artist.gettopalbums", {"artist": name, "autocorrect": "1", "limit": "50"}, *NOT_KNOWN)
    got = ask(env, name=name)
    assert (got["url"], got["listeners"], got["unavailable"]) == (link, int("9" * COUNT_DIGITS), False)
    key = artist_key("artist.getinfo", name=name)
    row = kept_rows(env)[key]
    assert len(row) + len(key.encode()) <= ROW_MAX_BYTES
    assert json.loads(row)["bio"]["content"] == chr(0x1F3B8) * (CONTENT_BYTES // 12)


def test_counts_read_from_the_answer_as_from_the_files():
    """The fixtures' own counts go through count(): a string in Last.fm's JSON is a number in the answer."""
    raw = answer("tame-impala.info.mbid")["artist"]["stats"]["listeners"]
    assert count(raw) == expected("tame-impala.info.mbid", None)["listeners"]


# ----- the app's fixtures ---------------------------------------------------------------------------------------------

EXPORTER = Path(__file__).resolve().parent / "fixtures" / "lastfm" / "answers.py"
#? the iPhone app's copy, on the `ios` branch once the exporter has been run there
APP_COPY = (Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures"
            / "lastfm" / "answers" / "artist.json")


def exporter():
    import importlib.util
    spec = importlib.util.spec_from_file_location("lastfm_answers", EXPORTER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_answers_for_the_app_are_the_routes_and_the_same_each_time(tmp_path):
    helper = exporter()
    assert helper.main(["--out", str(tmp_path)]) == 0
    made = json.loads((tmp_path / "artist.json").read_text(encoding="ascii"))
    assert made["fixtures"] == ANSWERS.name
    assert len(made["cases"]) == len(helper.CASES)
    for case in made["cases"]:
        assert case["status"] == 200 and set(case["answer"]) == FIELDS, case["name"]
    answers = {case["name"].split(",")[0].split(":")[0]: case["answer"] for case in made["cases"]}
    assert answers["Tame Impala"]["top_songs"] and answers["no key"]["enabled"] is False
    assert answers["Last.fm refusing the key (its real answer"]["why"].startswith("Last.fm refused")
    #? made again, it is the same, byte for byte - and --check says so
    assert helper.main(["--out", str(tmp_path), "--check"]) == 0
    (tmp_path / "artist.json").write_text("{}\n", encoding="ascii")
    assert helper.main(["--out", str(tmp_path), "--check"]) == 1


def test_the_app_s_copy_is_what_the_exporter_makes():
    if not APP_COPY.exists():
        pytest.skip("no iPhone app copy in this checkout")
    assert APP_COPY.read_text(encoding="ascii") == exporter().text()
