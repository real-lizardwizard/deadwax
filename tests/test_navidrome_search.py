"""
The app's Search tab, library half (2.0.0-player.13): `GET /deadwax/navidrome/search`, Subsonic's
search3 - and `client_for(request)`, the seam every Navidrome route asks through.

Through the whole app, start(), against a fake Navidrome (test_navidrome.py's fixtures), as the
rest of the player's routes are tested. What these protect is the same line the route list does:
only what the route declares reaches Navidrome, each count bounded, and the login laid over
everything last - a search3 that passed on whatever it was sent would be a proxy by another name.
"""

import asyncio
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient  # noqa: E402

from src.api import navidrome_endpoint  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import client_for, navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import library as library_routes  # noqa: E402
from src.routes import navidrome as navidrome_routes  # noqa: E402
#? Navidrome's answers as the player's other route tests make them
from test_navidrome import JPEG, failed, ok, streamed  # noqa: E402


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")


@pytest.fixture
def upstream(configured):
    """Navidrome, answering from a handler each test sets. Every request it saw is kept."""
    seen: list[httpx.Request] = []
    state = {"handler": lambda request: httpx.Response(200, json=ok())}

    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return state["handler"](request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield state, seen
    asyncio.run(navidrome.close_client())


@pytest.fixture
def client():
    """The whole app, as uvicorn serves it, without its lifespan: nothing connects anywhere."""
    return TestClient(start())

SEARCH = "/deadwax/navidrome/search"


def query(request: httpx.Request) -> dict:
    """What Navidrome was sent, blank values kept - an empty search is a value too."""
    return {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query, keep_blank_values=True).items()}

FOUND = {
    "artist": [{"id": "ar-1", "name": "Portishead", "albumCount": 2}],
    "album": [{"id": "al-1", "name": "Dummy", "artist": "Portishead", "year": 1994}],
    "song": [{"id": "so-1", "title": "Glory Box", "album": "Dummy", "albumId": "al-1"}],
}


def test_search_asks_search3_with_what_it_was_given(upstream, client):
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(searchResult3=FOUND))

    answer = client.get(f"{SEARCH}?q=portishead&artistCount=5&albumCount=8&songCount=10&songOffset=10")

    assert answer.status_code == 200
    assert answer.json() == {"artists": FOUND["artist"], "albums": FOUND["album"], "songs": FOUND["song"]}
    [request] = seen
    assert request.url.path == "/rest/search3"
    sent = query(request)
    assert {key: sent[key] for key in ("query", "artistCount", "albumCount", "songCount", "songOffset",
                                       "artistOffset", "albumOffset")} == {
        "query": "portishead", "artistCount": "5", "albumCount": "8", "songCount": "10",
        "songOffset": "10", "artistOffset": "0", "albumOffset": "0",
    }


def test_nothing_undeclared_reaches_navidrome(upstream, client):
    """A forged login, a folder, another format, another client name: none of it is passed on."""
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(searchResult3={}))

    client.get(f"{SEARCH}?q=x&u=admin&t=forged&s=salt&musicFolderId=3&f=xml&c=evil&v=1.0.0&id=al-9")

    sent = query(seen[0])
    assert sent["u"] == "james" and sent["t"] != "forged" and sent["s"] != "salt"
    assert sent["f"] == "json" and sent["c"] == "deadwax" and sent["v"] == "1.16.1"
    assert "musicFolderId" not in sent and "id" not in sent


def test_the_login_is_laid_over_whatever_the_query_holds(upstream, client):
    """The query is a value, never more parameters - an encoded `&u=` stays inside it."""
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(searchResult3={}))

    client.get(SEARCH, params={"q": "dummy&u=admin&t=forged"})

    sent = query(seen[0])
    assert sent["query"] == "dummy&u=admin&t=forged"
    assert sent["u"] == "james" and sent["t"] != "forged"


@pytest.mark.parametrize("params", [
    {},                                         # no query at all
    {"q": "x" * 201},                           # a query past its bound
    {"q": "x", "artistCount": "51"},
    {"q": "x", "albumCount": "51"},
    {"q": "x", "songCount": "501"},
    {"q": "x", "songCount": "-1"},
    {"q": "x", "artistOffset": "-1"},
    {"q": "x", "albumOffset": "-1"},
    {"q": "x", "songOffset": "-1"},
    {"q": "x", "songCount": "lots"},
])
def test_out_of_bounds_is_a_422_and_never_asked(upstream, client, params):
    _, seen = upstream

    assert client.get(SEARCH, params=params).status_code == 422
    assert seen == []


def test_the_bounds_themselves_are_allowed(upstream, client):
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(searchResult3={}))

    answer = client.get(SEARCH, params={"q": "x", "artistCount": 50, "albumCount": 50, "songCount": 500})

    assert answer.status_code == 200
    assert (query(seen[0])["artistCount"], query(seen[0])["albumCount"], query(seen[0])["songCount"]) == ("50", "50", "500")


def test_an_empty_query_is_passed_on(upstream, client):
    """Navidrome answers an empty search3 with everything, a page at a time (a later Songs list)."""
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(searchResult3={}))

    assert client.get(f"{SEARCH}?q=").status_code == 200
    assert query(seen[0])["query"] == ""


def test_nothing_found_is_three_empty_lists(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(searchResult3={}))

    assert client.get(f"{SEARCH}?q=zzz").json() == {"artists": [], "albums": [], "songs": []}


def test_a_refusal_is_said_as_navidrome_said_it(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(40, "Wrong username or password"))

    answer = client.get(f"{SEARCH}?q=x")

    assert answer.status_code == 502
    assert "NAVIDROME_USER" in answer.json()["detail"]


# ---------------------------------------------------------------- client_for, the seam

def test_with_logins_off_every_request_gets_the_one_shared_client():
    assert client_for(None) is navidrome
    assert client_for(object()) is navidrome  # type: ignore[arg-type]


def test_every_navidrome_route_asks_through_client_for(upstream, client, monkeypatch):
    """
    Step 6 gives each user their own Navidrome login by changing client_for's body, and nothing
    else - which holds only while every route asks through it. A route reaching for the shared
    client directly would go on answering every user with the one account.
    """
    state, _ = upstream
    asked = []

    def recorder(request):
        asked.append(request.url.path)
        return navidrome

    monkeypatch.setattr(navidrome_routes, "client_for", recorder)
    monkeypatch.setattr(library_routes, "client_for", recorder)

    def answer(request):
        endpoint = request.url.path.rsplit("/", 1)[-1]
        if endpoint == "getCoverArt":
            return streamed(200, JPEG, {"content-type": "image/jpeg"})
        if endpoint == "stream":
            return streamed(200, JPEG, {"content-type": "audio/mpeg"})
        return httpx.Response(200, json=ok(searchResult3={}, albumList2={}, album={}))

    state["handler"] = answer
    paths = [
        "/deadwax/navidrome/status", "/deadwax/navidrome/albums", "/deadwax/navidrome/albums/al-1",
        f"{SEARCH}?q=x", "/deadwax/navidrome/cover/al-1", "/deadwax/navidrome/stream/so-1?format=mp3",
    ]
    for path in paths:
        client.get(path)
    client.post("/deadwax/navidrome/scrobble/so-1", headers={"origin": "http://testserver"})

    asked_routes = sorted(set(asked))
    assert asked_routes == sorted({path.split("?")[0] for path in paths} | {"/deadwax/navidrome/scrobble/so-1"})
    #? and the routes are exactly these and /scrub: a new one must be added here, asking through the
    #? seam too. /scrub (2.0.0-player.14, the turntable's window) answers from the shared MP4 cache,
    #? as the stream's wrap=mp4 does - one MP4 serves every phone - so like that path it asks Navidrome
    #? through the cache's own client, and step 6 checks a user's access at the route
    assert "/scrub/{song_id}" in {route.path for route in navidrome_routes.router.routes}
    assert len({route.path for route in navidrome_routes.router.routes}) == 8


def test_the_turntables_internal_call_asks_through_client_for(monkeypatch, tmp_path, configured):
    """The turntable's getAlbum is made while answering the phone, so it reads that user's library."""
    monkeypatch.setattr(library_routes.Config, "LIBRARY_PATH", str(tmp_path))
    asked = []

    class Navidrome:
        async def call(self, endpoint, params=None):
            asked.append(endpoint)
            return {"album": {"musicBrainzId": ""}}

    monkeypatch.setattr(library_routes, "client_for", lambda request: asked.append("client_for") or Navidrome())

    response = TestClient(start()).get("/deadwax/library/disc_art/navidrome?album=al-1")

    assert response.status_code == 404  # no release id: the plain record
    assert asked == ["client_for", "getAlbum"]


def test_the_shared_client_is_still_the_one_the_settings_route_drops():
    """client_for hands out the module's client, so dropping that one on a URL change still works."""
    assert navidrome_endpoint.navidrome is client_for(None)
    asyncio.run(navidrome.close_client())
    assert navidrome.client is None
