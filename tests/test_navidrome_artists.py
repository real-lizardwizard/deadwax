"""
The app's artists and Info's song (2.0.0-player.17): `GET /deadwax/navidrome/artists` (getArtists),
`/artists/{id}` (getArtist) and `/songs/{id}` (getSong) - three more calls on the player's fixed
list, each its own route.

Through the whole app, start(), against a fake Navidrome (test_navidrome.py's answers), as the rest
of the player's routes are tested. What these hold is the line the list draws: each route makes ITS
call and no other, passes on only what it declares (an id, as Navidrome's `id` parameter - never a
path; getArtists nothing at all), lays the login over everything last, refuses an id far longer
than any of Navidrome's with Navidrome asked nothing, and hands Navidrome's answer back as it came.
"""

import asyncio
import sys
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi.testclient import TestClient  # noqa: E402

from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes.navidrome import ID_MAX  # noqa: E402
#? Navidrome's answers, and the query reader, as the search route's tests use them
from test_navidrome import failed, ok  # noqa: E402
from test_navidrome_search import query  # noqa: E402


@pytest.fixture
def upstream(monkeypatch):
    """Navidrome, answering from a handler each test sets. Every request it saw is kept."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
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

PORTISHEAD = {"id": "ar-1", "name": "Portishead", "albumCount": 2, "coverArt": "ar-ar-1",
              "musicBrainzId": "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"}
INDEX = {"ignoredArticles": "The El La", "index": [
    {"name": "P", "artist": [PORTISHEAD, {"id": "ar-2", "name": "Pink Floyd", "albumCount": 1}]},
    {"name": "Y", "artist": [{"id": "ar-3", "name": "Ye", "albumCount": 2}]},
]}
ARTIST = {**PORTISHEAD, "album": [{"id": "al-1", "name": "Dummy", "year": 1994}, {"id": "al-2", "name": "Third", "year": 2008}]}
SONG = {"id": "so-1", "title": "Glory Box", "albumId": "al-1", "artistId": "ar-1", "playCount": 12,
        "displayComposer": "Geoff Barrow, Beth Gibbons, Adrian Utley"}


def answering(state, **body):
    state["handler"] = lambda request: httpx.Response(200, json=ok(**body))


# ---------------------------------------------------------------- what reaches Navidrome

def test_artists_asks_getartists_and_flattens_its_index_in_order(upstream, client):
    state, seen = upstream
    answering(state, artists=INDEX)

    answer = client.get("/deadwax/navidrome/artists")

    assert answer.status_code == 200
    assert [artist["name"] for artist in answer.json()["artists"]] == ["Portishead", "Pink Floyd", "Ye"]
    #? each artist as Navidrome sent it - the album artist's MusicBrainz id included
    assert answer.json()["artists"][0] == PORTISHEAD
    [request] = seen
    assert request.url.path == "/rest/getArtists"


def test_artists_passes_nothing_on(upstream, client):
    """getArtists' only parameter is a music folder, and none is passed - whatever the page sends."""
    state, seen = upstream
    answering(state, artists=INDEX)

    client.get("/deadwax/navidrome/artists?musicFolderId=3&u=admin&t=forged&f=xml&id=x")

    sent = query(seen[0])
    assert "musicFolderId" not in sent and "id" not in sent
    assert sent["u"] == "james" and sent["t"] != "forged" and sent["f"] == "json"


def test_an_empty_library_is_no_artists(upstream, client):
    state, _ = upstream
    answering(state, artists={"index": []})

    assert client.get("/deadwax/navidrome/artists").json() == {"artists": []}


def test_artist_asks_getartist_by_id_and_passes_the_answer_back(upstream, client):
    state, seen = upstream
    answering(state, artist=ARTIST)

    answer = client.get("/deadwax/navidrome/artists/ar-1")

    assert answer.status_code == 200 and answer.json() == ARTIST
    [request] = seen
    assert request.url.path == "/rest/getArtist"
    assert query(request)["id"] == "ar-1"


def test_song_asks_getsong_by_id_and_passes_the_answer_back(upstream, client):
    state, seen = upstream
    answering(state, song=SONG)

    answer = client.get("/deadwax/navidrome/songs/so-1")

    assert answer.status_code == 200 and answer.json() == SONG
    [request] = seen
    assert request.url.path == "/rest/getSong"
    assert query(request)["id"] == "so-1"


@pytest.mark.parametrize("path", ["/deadwax/navidrome/artists/ar-1", "/deadwax/navidrome/songs/so-1"])
def test_by_id_nothing_undeclared_reaches_navidrome_and_the_login_is_laid_over_last(upstream, client, path):
    state, seen = upstream
    answering(state, artist=ARTIST, song=SONG)

    client.get(f"{path}?u=admin&t=forged&s=salt&id=other&f=xml&c=evil&musicFolderId=3")

    sent = query(seen[0])
    assert sent["id"] in ("ar-1", "so-1"), "the id is the path's, never a query's"
    assert sent["u"] == "james" and sent["t"] != "forged" and sent["s"] != "salt"
    assert sent["f"] == "json" and sent["c"] == "deadwax" and "musicFolderId" not in sent


@pytest.mark.parametrize("path", ["/deadwax/navidrome/artists/ar-1", "/deadwax/navidrome/songs/so-1"])
def test_an_id_with_query_characters_is_one_value(upstream, client, path):
    """An encoded `&u=` in the id stays inside Navidrome's `id` - never another parameter."""
    state, seen = upstream
    answering(state, artist=ARTIST, song=SONG)

    base = path.rsplit("/", 1)[0]
    client.get(f"{base}/x%26u%3Dadmin")

    sent = query(seen[0])
    assert sent["id"] == "x&u=admin" and sent["u"] == "james"


@pytest.mark.parametrize("base", ["/deadwax/navidrome/artists", "/deadwax/navidrome/songs"])
def test_an_id_longer_than_any_of_navidromes_is_a_422_and_never_asked(upstream, client, base):
    _, seen = upstream

    assert client.get(f"{base}/{'x' * (ID_MAX + 1)}").status_code == 422
    assert seen == []


@pytest.mark.parametrize("base", ["/deadwax/navidrome/artists", "/deadwax/navidrome/songs"])
def test_the_longest_id_is_allowed(upstream, client, base):
    state, seen = upstream
    answering(state, artist=ARTIST, song=SONG)

    assert client.get(f"{base}/{'x' * ID_MAX}").status_code == 200
    assert query(seen[0])["id"] == "x" * ID_MAX


# ---------------------------------------------------------------- failures

@pytest.mark.parametrize("path", ["/deadwax/navidrome/artists", "/deadwax/navidrome/artists/ar-9",
                                  "/deadwax/navidrome/songs/so-9"])
def test_navidromes_not_found_is_a_404(upstream, client, path):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(70, "Artist not found"))

    assert client.get(path).status_code == 404


@pytest.mark.parametrize("path", ["/deadwax/navidrome/artists", "/deadwax/navidrome/artists/ar-1",
                                  "/deadwax/navidrome/songs/so-1"])
def test_a_refused_login_is_said_as_navidrome_said_it(upstream, client, path):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(40, "Wrong username or password"))

    answer = client.get(path)

    assert answer.status_code == 502
    assert "NAVIDROME_USER" in answer.json()["detail"]
