"""
GET /deadwax/lastfm/artist (2.1.41, S2 - notes/lastfm.md; the design's 2.5): src/routes/lastfm.py, asked of the whole
app, start(), with a real SQLite store, the module's own Last.fm client and keeper, and Last.fm as httpx's
MockTransport (LastFm below).

LAST.FM HERE ANSWERS FROM tests/test_lastfm.py's ANSWERS - its own answers, recorded by record.py on 2026-11-25. It
answers a request with the file whose `method` and `params` are exactly the request's (the key and `format` aside), so
every request the route sends must be one record.py records; a request no file answers is a 500, and a test failure
at the end. What no recording holds is given inline: Last.fm down, slow, limiting or answering junk (SHAPED, from its
API pages), refusing the key (the one real refusal kept, REFUSED_INVALID_KEY, and a SHAPED one that echoes the key),
and getInfo for an unknown MusicBrainz id (Last.fm's recorded not-known answer for an unknown name, NOT_KNOWN).

What this holds:
  - both parts asked at once, by MusicBrainz id, with the parameters record.py asks with; the answer
    {enabled, unavailable, why, url, listeners, top_songs} and nothing else (S4's parts not sent);
  - kept: the second visit asks nothing; what is kept is deadwax's parsed shape, never Last.fm's answer;
  - a "not known" by id asks again by name with autocorrect=1, and is kept; with no name, nothing more is asked;
  - one part failing, late or unreadable leaves the other; past ARTIST_DEADLINE_S the page is answered without the
    late part, which is kept when it comes; nothing gets to a 500;
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

from src import lastfm_kept
from src.api import lastfm_endpoint
from src.api.app import start
from src.api.lastfm_endpoint import lastfm
from src.config import Config
from src.lastfm import CONTENT_BYTES, COUNT_DIGITS, NO_KEY_WHY, URL_MAX, artist_info, count, top_tracks
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
FIELDS = {"enabled", "unavailable", "why", "url", "listeners", "top_songs"}

#? Last.fm's own answer for an artist it doesn't know - recorded, for getInfo by an unknown name (HTTP 200, error 6) -
#? given for getInfo by an unknown id too, which record.py doesn't record (its getTopTracks by one answered the same)
NOT_KNOWN = (json.loads((ANSWERS / "unknown-name.info.json").read_text(encoding="ascii"))["status"],
             json.loads((ANSWERS / "unknown-name.info.json").read_text(encoding="ascii"))["answer"])
#? SHAPED: an invalid key, as Last.fm's error codes page describes it - echoing the key, which it never should
SHAPED_REFUSED = (403, {"error": 10, "message": f"Invalid API key - You must be granted a valid key by last.fm ({KEY})"})
SHAPED_LIMITED = (429, {"error": 29, "message": "Rate Limit Exceeded"})


def _params(params: dict) -> frozenset:
    return frozenset(params.items())


class LastFm:
    """Last.fm's API, from ANSWERS' files: each request answered with the file asked exactly as it was."""

    def __init__(self) -> None:
        self.files: dict[tuple[str, frozenset], tuple[int, object]] = {}
        for path in sorted(ANSWERS.glob("*.json")):
            held = json.loads(path.read_text(encoding="ascii"))
            self.files[(held["method"], _params(held["params"]))] = (held["status"], held["answer"])
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


# ----- an artist, by MusicBrainz id ----------------------------------------------------------------------------------

@pytest.mark.parametrize("slug, mbid", [("tame-impala", TAME), ("dance-gavin-dance", DGD), ("portishead", PORTISHEAD)])
def test_an_artist_is_their_listeners_their_page_and_their_ten_top_songs(env, slug, mbid):
    got = ask(env, mbid=mbid, name="whoever")
    assert set(got) == FIELDS, "S4's similar and top_albums aren't sent until S4"
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, False, None)
    assert {k: got[k] for k in ("url", "listeners", "top_songs")} == expected(f"{slug}.info.mbid",
                                                                           f"{slug}.top-tracks.mbid")
    assert isinstance(got["listeners"], int) and got["url"].startswith("https://www.last.fm/")
    assert 0 < len(got["top_songs"]) <= 10
    #? both parts, by id, asked as record.py asks - never by name while the id is known
    assert sorted(env.fake.requests, key=lambda r: r[0]) == [
        ("artist.getinfo", {"mbid": mbid}), ("artist.gettoptracks", {"mbid": mbid, "limit": "50"})]
    assert env.fake.keys == [KEY, KEY]


def test_the_parts_are_asked_at_once(env):
    """Each part waits 0.4 s at Last.fm: one after the other would take 0.8."""
    env.fake.slow = {"artist.getinfo": 0.4, "artist.gettoptracks": 0.4}
    began = time.monotonic()
    got = ask(env, mbid=TAME)
    assert time.monotonic() - began < 0.75
    assert got["top_songs"] and got["listeners"]


def test_a_second_visit_is_answered_from_what_was_kept_and_asks_nothing(env):
    first = ask(env, mbid=TAME)
    assert len(env.fake.requests) == 2
    assert ask(env, mbid=TAME) == first
    assert len(env.fake.requests) == 2
    rows = kept_rows(env)
    assert set(rows) == {artist_key("artist.getinfo", mbid=TAME), artist_key("artist.gettoptracks", mbid=TAME)}
    #? deadwax's own shape, parsed and folded - never Last.fm's answer
    tracks = json.loads(rows[artist_key("artist.gettoptracks", mbid=TAME)])
    assert tracks == top_tracks(answer("tame-impala.top-tracks.mbid"))
    assert "toptracks" not in rows[artist_key("artist.gettoptracks", mbid=TAME)]
    assert json.loads(rows[artist_key("artist.getinfo", mbid=TAME)]) == artist_info(answer("tame-impala.info.mbid"))


# ----- by name, and the fallback -------------------------------------------------------------------------------------

def test_an_id_last_fm_doesnt_know_is_asked_again_by_name(env):
    #? record.py records getTopTracks for the id nobody has; getInfo for it is SHAPED here
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    got = ask(env, mbid=UNKNOWN_MBID, name="Tame Impala")
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, False, None)
    assert {k: got[k] for k in ("url", "listeners", "top_songs")} == expected("tame-impala.info.name",
                                                                           "tame-impala.top-tracks.name")
    for method, extra in (("artist.getinfo", {}), ("artist.gettoptracks", {"limit": "50"})):
        assert env.fake.asked(method) == [{"mbid": UNKNOWN_MBID, **extra},
                                          {"artist": "Tame Impala", "autocorrect": "1", **extra}]
    #? the "not known" kept (as none), and the answer by name kept under the name
    rows = kept_rows(env)
    assert rows[artist_key("artist.gettoptracks", mbid=UNKNOWN_MBID)] is None
    assert rows[artist_key("artist.getinfo", mbid=UNKNOWN_MBID)] is None
    assert rows[artist_key("artist.gettoptracks", name="Tame Impala")] is not None
    assert ask(env, mbid=UNKNOWN_MBID, name="tame impala") == got
    assert len(env.fake.requests) == 4


def test_a_misspelt_name_is_asked_with_autocorrect_and_answered_with_the_page_last_fm_has_for_it(env):
    """Recorded: autocorrect doesn't correct "Tame Impla" - Last.fm has a page under the misspelling (scrobbles typed
    so), and answers that. The app asks by the MusicBrainz name, so it meets this only for a name misspelt there."""
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    got = ask(env, mbid=UNKNOWN_MBID, name="Tame Impla")
    assert {k: got[k] for k in ("url", "listeners", "top_songs")} == expected("misspelt.info", "misspelt.top-tracks")
    assert (got["url"], got["listeners"]) == ("https://www.last.fm/music/Tame+Impla", 9)
    assert env.fake.asked("artist.getinfo")[-1] == {"artist": "Tame Impla", "autocorrect": "1"}


def test_with_no_id_the_artist_is_asked_by_name(env):
    got = ask(env, name="  Tame Impala ")
    assert {k: got[k] for k in ("url", "listeners", "top_songs")} == expected("tame-impala.info.name",
                                                                           "tame-impala.top-tracks.name")
    assert sorted(env.fake.requests, key=lambda r: r[0]) == [
        ("artist.getinfo", {"artist": "Tame Impala", "autocorrect": "1"}),
        ("artist.gettoptracks", {"artist": "Tame Impala", "autocorrect": "1", "limit": "50"})]


def test_an_id_last_fm_doesnt_know_and_no_name_is_nothing_and_nothing_more_asked(env):
    env.fake.add("artist.getinfo", {"mbid": UNKNOWN_MBID}, *NOT_KNOWN)
    got = ask(env, mbid=UNKNOWN_MBID)
    assert got == {"enabled": True, "unavailable": False, "why": None, "url": None, "listeners": None,
                   "top_songs": None}
    assert len(env.fake.requests) == 2


def test_an_artist_last_fm_doesnt_know_by_name_is_nothing_kept_as_none(env):
    got = ask(env, name=UNKNOWN_NAME)
    assert got == {"enabled": True, "unavailable": False, "why": None, "url": None, "listeners": None,
                   "top_songs": None}
    assert set(kept_rows(env).values()) == {None}
    ask(env, name=UNKNOWN_NAME)
    assert len(env.fake.requests) == 2


def test_a_name_that_folds_to_nothing_is_never_asked_by(env):
    """It would share one kept row with every other such name."""
    got = ask(env, name="!!!")
    assert (got["url"], got["listeners"], got["top_songs"], got["unavailable"]) == (None, None, None, False)
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
                   "top_songs": None}
    #? a failure by id is no "not known": nothing is asked by name
    assert all("mbid" in params for params in env.fake.asked())


def test_last_fm_limiting_is_a_blip_with_no_why(env):
    env.fake.instead = {"artist.getinfo": SHAPED_LIMITED, "artist.gettoptracks": SHAPED_LIMITED}
    got = ask(env, mbid=TAME)
    assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)


def test_last_fm_down_answers_what_was_kept_however_old(env):
    first = ask(env, mbid=TAME)
    with sqlite3.connect(env.db) as connection:
        connection.execute("UPDATE lastfm_kept SET fetched_at = fetched_at - ?", (90 * DAY,))
    env.fake.down = True
    assert ask(env, mbid=TAME) == first
    assert len(env.fake.requests) == 4


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


# ----- the key -------------------------------------------------------------------------------------------------------

def test_no_key_asks_nothing_and_says_where_to_add_one(env, monkeypatch):
    monkeypatch.setattr(Config, "LASTFM_API_KEY", "   ")
    got = ask(env, mbid=TAME, name="Tame Impala")
    assert got == {"enabled": False, "unavailable": False, "why": NO_KEY_WHY, "url": None, "listeners": None,
                   "top_songs": None}
    assert env.fake.requests == [] and kept_rows(env) == {}


def test_refused_with_nothing_kept_is_off_and_says_why_without_the_key(env):
    env.fake.instead = {"artist.getinfo": SHAPED_REFUSED, "artist.gettoptracks": SHAPED_REFUSED}
    response = env.client.get(PATH, params={"mbid": TAME})
    got = response.json()
    assert (got["enabled"], got["unavailable"]) == (False, True)
    assert (got["url"], got["listeners"], got["top_songs"]) == (None, None, None)
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
    env.fake.instead = {"artist.getinfo": (held["status"], held["answer"]),
                        "artist.gettoptracks": (held["status"], held["answer"])}
    got = ask(env, mbid=TAME)
    assert got == {"enabled": False, "unavailable": True,
                   "why": "Last.fm refused deadwax's API key (error 10: Invalid API key - You must be granted a valid "
                          "key by last.fm) - check LASTFM_API_KEY in Server settings > Connections: it's the API key, "
                          "not the shared secret.",
                   "url": None, "listeners": None, "top_songs": None}
    assert lastfm.held() is not None and lastfm.held().error == 10
    assert env.client.get("/deadwax/me").json()["lastfm"] == "refused"


def test_refused_answers_what_was_kept_and_still_says_why(env):
    first = ask(env, mbid=TAME)
    with sqlite3.connect(env.db) as connection:
        connection.execute("UPDATE lastfm_kept SET fetched_at = fetched_at - ?", (40 * DAY,))
    env.fake.instead = {"artist.getinfo": SHAPED_REFUSED, "artist.gettoptracks": SHAPED_REFUSED}
    got = ask(env, mbid=TAME)
    assert got["enabled"] and not got["unavailable"]
    assert got["why"].startswith("Last.fm refused deadwax's API key (error 10:")
    assert {k: got[k] for k in ("url", "listeners", "top_songs")} == {k: first[k] for k in ("url", "listeners",
                                                                                              "top_songs")}


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
    env.fake.add("artist.getinfo", {"artist": "x" * 200, "autocorrect": "1"}, *NOT_KNOWN)
    env.fake.add("artist.gettoptracks", {"artist": "x" * 200, "autocorrect": "1", "limit": "50"}, *NOT_KNOWN)
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
