"""
The player's turntable finds its record's face (2.0.0-player.11).

The turntable draws the playing album's CD art on the record - the `disc.<ext>` or
`disc<N>.<ext>` that Get CD art saves beside the tracks - and a plain black record with the cover
as its label when there is none. The phone knows only Navidrome's album id, so deadwax finds the
file: the album's release id from Navidrome (getAlbum, an internal call - NOT a relay route; the
fixed list in routes/navidrome.py is unchanged), the release's folder from the store index, and
the picture from that folder's own listing.

Through the whole app start() builds (without its lifespan, so nothing connects), with Navidrome
replaced by httpx's MockTransport and a scratch library of real tagged FLACs indexed into a real
SQLite store - so the media headers, the gzip exemption and every guard are in the path.
"""

import asyncio
import logging
import os
import shutil
import sqlite3
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from src import library
from src.api.app import serves_media, start
from src.api.navidrome_endpoint import navidrome
from src.config import Config
from src.disc_art import disc_face
from src.routes import library as library_routes
from src.routes import navidrome as navidrome_routes
from src.store import JobStore
from src.store_index import index_folder
from tests.test_library import write_flac

ROUTE = "/deadwax/library/disc_art/navidrome"

#? big enough that gzip would take them on, were the route not a media one
JPEG_1 = b"\xff\xd8\xff\xe0" + b"disc one" + bytes(5000)
PNG_2 = b"\x89PNG\r\n\x1a\n" + b"disc two" + bytes(5000)
JPEG_ALL = b"\xff\xd8\xff\xe0" + b"every disc" + bytes(5000)

MEDIA_HEADERS = {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
    "cross-origin-resource-policy": "same-origin",
}

WYWH = "Pink Floyd/Wish You Were Here (1975) [Experience edition]"


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome", **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


@pytest.fixture(autouse=True)
def fresh():
    library.clear_scan_cache()
    library_routes._cache_loaded_for = None
    yield
    library.clear_scan_cache()
    library_routes._cache_loaded_for = None


@pytest.fixture
def root(tmp_path, monkeypatch):
    music = tmp_path / "music"
    music.mkdir()
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(music))
    return music


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


@pytest.fixture
def albums(monkeypatch):
    """
    Navidrome, knowing the albums a test puts in `known` (id -> its musicBrainzId), and nothing
    else - Subsonic's code 70, as Navidrome answers an id it has no album for. Every request kept.
    """
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    known: dict[str, str] = {}
    seen: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        album_id = parse_qs(urlparse(str(request.url)).query).get("id", [""])[0]
        if request.url.path.endswith("/getAlbum") and album_id in known:
            return httpx.Response(200, json=ok(album={"id": album_id, "name": "An album", "song": [],
                                                      "musicBrainzId": known[album_id]}))
        return httpx.Response(200, json=failed(70, "Album not found"))

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield known, seen
    asyncio.run(navidrome.close_client())


@pytest.fixture
def client(store):
    app = start()
    app.state.store = store
    return TestClient(app)  # no `with`: no lifespan, so nothing connects


def filed(root, store, folder, release="rel-wywh", discs=(1,), pictures=None):
    """An album folder deadwax filed - tagged with its release, a track per disc - indexed."""
    directory = root / folder
    for disc in discs:
        tags = {"album": "Wish You Were Here", "albumartist": "Pink Floyd", "artist": "Pink Floyd",
                "title": f"Track on disc {disc}", "tracknumber": "1", "musicbrainz_albumid": release}
        if len(discs) > 1 or disc != 1:
            tags["discnumber"] = str(disc)
        write_flac(directory / f"{disc}-01 - Track on disc {disc}.flac", **tags)
    for name, data in (pictures or {}).items():
        (directory / name).write_bytes(data)
    assert asyncio.run(index_folder(store, str(root), folder)) is not None
    return directory


def get(client, album, disc=None):
    params = {"album": album}
    if disc is not None:
        params["disc"] = disc
    return client.get(ROUTE, params=params, headers={"Accept-Encoding": "gzip"})


# ---------------------------------------------------------------- which picture

def test_each_disc_of_a_set_gets_its_own_picture(root, store, albums, client):
    known, seen = albums
    known["al-wywh"] = "rel-wywh"
    filed(root, store, WYWH, discs=(1, 2), pictures={"disc1.jpg": JPEG_1, "disc2.png": PNG_2})

    one = get(client, "al-wywh", 1)
    assert one.status_code == 200
    assert one.content == JPEG_1
    assert one.headers["content-type"] == "image/jpeg"

    two = get(client, "al-wywh", 2)
    assert two.status_code == 200
    assert two.content == PNG_2
    assert two.headers["content-type"] == "image/png"

    #? found through Navidrome's own reading of the album, one internal getAlbum per ask
    assert [(request.url.path, parse_qs(urlparse(str(request.url)).query)["id"][0]) for request in seen] == [
        ("/rest/getAlbum", "al-wywh"), ("/rest/getAlbum", "al-wywh")]


def test_it_is_served_as_the_disc_art_route_serves_one(root, store, albums, client):
    known, _ = albums
    known["al-wywh"] = "rel-wywh"
    filed(root, store, WYWH, pictures={"disc.jpg": JPEG_ALL})

    answer = get(client, "al-wywh", 1)
    assert answer.status_code == 200
    #? a media answer: never gzipped (a Content-Length the image is), GuardMedia's three headers
    assert "content-encoding" not in answer.headers
    for name, value in MEDIA_HEADERS.items():
        assert answer.headers[name] == value
    #? kept as long as the library's own disc art route keeps one
    assert answer.headers["cache-control"] == "private, max-age=300"
    same = TestClient(start()).get("/deadwax/library/disc_art", params={"album": WYWH, "file": "disc.jpg"})
    assert same.headers["cache-control"] == answer.headers["cache-control"]
    assert same.content == answer.content


def test_a_disc_without_its_own_takes_the_one_every_disc_shares(root, store, albums, client):
    known, _ = albums
    known["al-wywh"] = "rel-wywh"
    filed(root, store, WYWH, discs=(1, 2), pictures={"disc.jpg": JPEG_ALL, "disc2.png": PNG_2})

    assert get(client, "al-wywh", 2).content == PNG_2
    assert get(client, "al-wywh", 1).content == JPEG_ALL
    assert get(client, "al-wywh", 3).content == JPEG_ALL


def test_a_one_disc_album_with_no_disc_number_takes_its_unnumbered_picture(root, store, albums, client):
    known, _ = albums
    known["al-dummy"] = "rel-dummy"
    filed(root, store, "Portishead/Dummy (1994)", release="rel-dummy", pictures={"disc.jpg": JPEG_ALL})

    #? no disc number is disc 1, and disc 1 with no disc1.* is the unnumbered one
    assert get(client, "al-dummy").content == JPEG_ALL
    assert get(client, "al-dummy", 0).content == JPEG_ALL
    assert get(client, "al-dummy", 1).content == JPEG_ALL


def test_a_set_stored_one_folder_per_disc_finds_each_discs_picture(root, store, albums, client):
    known, _ = albums
    known["al-wywh"] = "rel-wywh"
    filed(root, store, "Pink Floyd/Wish You Were Here (Disc 1)", discs=(1,), pictures={"disc1.jpg": JPEG_1})
    filed(root, store, "Pink Floyd/Wish You Were Here (Disc 2)", discs=(2,), pictures={"disc2.png": PNG_2})

    assert get(client, "al-wywh", 1).content == JPEG_1
    assert get(client, "al-wywh", 2).content == PNG_2


def test_only_deadwaxs_own_cd_art_is_the_face(root, store, albums, client):
    """A download's cd.jpg (and a cover) is left alone: Get CD art is still offered beside it."""
    known, _ = albums
    known["al-wywh"] = "rel-wywh"
    filed(root, store, WYWH, pictures={"cd.jpg": JPEG_1, "cover.jpg": JPEG_1, "discovery.jpg": JPEG_1})

    assert get(client, "al-wywh", 1).status_code == 404


# ---------------------------------------------------------------- none to be had

def test_nothing_to_draw_is_a_404(root, store, albums, client, monkeypatch):
    known, seen = albums
    known["al-no-release"] = ""
    known["al-not-indexed"] = "rel-nowhere"
    known["al-bare"] = "rel-bare"
    filed(root, store, "Portishead/Third (2008)", release="rel-bare")  # indexed, with no CD art

    for album in ("al-unknown", "al-no-release", "al-not-indexed", "al-bare"):
        answer = get(client, album, 1)
        assert answer.status_code == 404, album
        #? a refusal is a media answer too
        assert answer.headers["x-content-type-options"] == "nosniff"

    #? Navidrome not set up: nothing is asked of it, and there is nothing to draw
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    asked = len(seen)
    assert get(client, "al-bare", 1).status_code == 404
    assert len(seen) == asked


def test_no_library_or_no_store_is_a_404(root, store, albums, client, monkeypatch):
    known, seen = albums
    known["al-wywh"] = "rel-wywh"
    filed(root, store, WYWH, pictures={"disc.jpg": JPEG_ALL})
    assert get(client, "al-wywh", 1).status_code == 200

    #? no store (a route in a harness without the lifespan): nothing is remembered, nothing found
    assert get(TestClient(start()), "al-wywh", 1).status_code == 404

    monkeypatch.setattr(Config, "LIBRARY_PATH", None)
    asked = len(seen)
    assert get(client, "al-wywh", 1).status_code == 404
    assert len(seen) == asked, "with no library there is nothing to look for"


def test_a_disc_or_an_album_that_isnt_one_is_refused(albums, client):
    assert client.get(ROUTE, params={"album": "al-wywh", "disc": -1}).status_code == 422
    assert client.get(ROUTE, params={"album": "al-wywh", "disc": "two"}).status_code == 422
    assert client.get(ROUTE).status_code == 422
    assert client.get(ROUTE, params={"album": ""}).status_code == 422


# ---------------------------------------------------------------- nothing outside the library

def test_the_album_id_is_only_ever_navidromes_id(root, store, albums, client):
    """A path in the id goes to Navidrome as the id it claims to be, and is never joined onto one."""
    _, seen = albums
    (root.parent / "secret").mkdir()
    (root.parent / "secret" / "disc.jpg").write_bytes(JPEG_ALL)

    for album in ("../secret", "../../secret/disc.jpg", "/etc/passwd"):
        answer = get(client, album, 1)
        assert answer.status_code == 404
        assert answer.content != JPEG_ALL

    assert [request.url.path for request in seen] == ["/rest/getAlbum"] * 3
    assert [parse_qs(urlparse(str(request.url)).query)["id"][0] for request in seen] == [
        "../secret", "../../secret/disc.jpg", "/etc/passwd"]


def test_a_folder_that_leads_out_of_the_library_is_refused(root, store, albums, client):
    known, _ = albums
    known["al-outside"] = "rel-outside"
    outside = root.parent / "outside" / "Album"
    for disc in (1,):
        write_flac(outside / f"0{disc} - Track.flac", album="Album", albumartist="Someone",
                   title="Track", tracknumber="1", musicbrainz_albumid="rel-outside")
    (outside / "disc.jpg").write_bytes(JPEG_ALL)
    #? a folder in the library that is a link out of it, indexed as the release
    os.symlink(outside, root / "Linked")
    asyncio.run(index_folder(store, str(root), "Linked"))
    #? and a row climbing out by its path, as no writer would ever record one
    with sqlite3.connect(store.path) as connection:
        connection.execute(
            "INSERT INTO store_album (root, path, release_mbid, state, first_seen, updated_at) "
            "VALUES (?, ?, 'rel-outside', 'present', 0, 0)", (str(root), "../outside/Album"))

    assert len(asyncio.run(store.index_present(str(root), "rel-outside"))) >= 1
    answer = get(client, "al-outside", 1)
    assert answer.status_code == 404
    assert answer.content != JPEG_ALL


def test_a_folder_climbing_out_is_warned_of(root, store, albums, client, caplog):
    known, _ = albums
    known["al-outside"] = "rel-outside"
    (root.parent / "outside").mkdir()
    with sqlite3.connect(store.path) as connection:
        connection.execute(
            "INSERT INTO store_album (root, path, release_mbid, state, first_seen, updated_at) "
            "VALUES (?, ?, 'rel-outside', 'present', 0, 0)", (str(root), "../outside"))
    caplog.set_level(logging.DEBUG)

    assert get(client, "al-outside", 1).status_code == 404
    refused = [r for r in caplog.records if "outside the library" in r.getMessage()]
    assert [r.levelno for r in refused] == [logging.WARNING]
    #? a refusal is not a folder that has gone: the row is left as it is
    assert [row["path"] for row in asyncio.run(store.index_present(str(root), "rel-outside"))] == ["../outside"]


def test_a_folder_gone_since_the_last_scan_is_not_a_refusal(root, store, albums, client, caplog):
    """Renamed or deleted outside deadwax, its row still `present` until a scan: a 404, a quiet
    log line and a `missing` tombstone - never a warning of a traversal that isn't there."""
    known, _ = albums
    known["al-wywh"] = "rel-wywh"
    directory = filed(root, store, WYWH, pictures={"disc.jpg": JPEG_ALL})
    assert get(client, "al-wywh", 1).status_code == 200
    shutil.rmtree(directory)
    caplog.set_level(logging.DEBUG)

    assert get(client, "al-wywh", 1).status_code == 404
    lines = [r for r in caplog.records if WYWH in r.getMessage()]
    assert lines and all(r.levelno < logging.WARNING for r in lines)
    assert not [r for r in caplog.records if "outside the library" in r.getMessage()]
    #? marked missing, as held_copy marks one: the next ask doesn't look for it at all
    assert asyncio.run(store.index_present(str(root), "rel-wywh")) == []
    with sqlite3.connect(store.path) as connection:
        assert connection.execute("SELECT state FROM store_album WHERE path = ?", (WYWH,)).fetchall() == [("missing",)]

    #? and when it comes back, filed again, it is found again
    filed(root, store, WYWH, pictures={"disc.jpg": JPEG_ALL})
    assert get(client, "al-wywh", 1).content == JPEG_ALL


def test_a_picture_that_is_a_link_out_of_its_folder_is_refused(root, store, albums, client):
    known, _ = albums
    known["al-wywh"] = "rel-wywh"
    directory = filed(root, store, WYWH)
    secret = root.parent / "secret.jpg"
    secret.write_bytes(JPEG_ALL)
    os.symlink(secret, directory / "disc.jpg")

    answer = get(client, "al-wywh", 1)
    assert answer.status_code == 404
    assert answer.content != JPEG_ALL


def test_it_is_a_library_route_and_the_navidrome_list_is_unchanged():
    assert serves_media(ROUTE)
    #? the player's own list - search3 joined it in 2.0.0-player.13, on purpose; this route never did
    assert sorted(route.path for route in navidrome_routes.router.routes) == [
        "/albums", "/albums/{album_id}", "/cover/{cover_id}", "/scrobble/{song_id}",
        "/search", "/status", "/stream/{song_id}",
    ]
    assert "/disc_art/navidrome" in {route.path for route in library_routes.router.routes}


# ---------------------------------------------------------------- the choice itself

def test_disc_face_chooses_a_discs_own_then_the_shared_one():
    assert disc_face([["disc1.jpg", "disc2.png", "disc.jpg"]], 2) == (0, "disc2.png")
    assert disc_face([["disc1.jpg", "disc.jpg"]], 2) == (0, "disc.jpg")
    #? a disc's own picture in any folder beats a shared one in an earlier folder
    assert disc_face([["disc.jpg"], ["disc2.jpg"]], 2) == (1, "disc2.jpg")
    assert disc_face([["disc.jpg"], ["disc2.jpg"]], 1) == (0, "disc.jpg")
    #? no disc number is disc 1; the spellings find_disc_art counts, numbers read as numbers
    assert disc_face([["disc1.jpg"]], None) == (0, "disc1.jpg")
    assert disc_face([["disc1.jpg"]], 0) == (0, "disc1.jpg")
    assert disc_face([["Disc 02.PNG"]], 2) == (0, "Disc 02.PNG")
    assert disc_face([["disc_3.webp"]], 3) == (0, "disc_3.webp")
    #? never a download's cd*, and nothing for a disc with no picture of its own or shared
    assert disc_face([["cd.jpg", "cd2.jpg"]], 2) is None
    assert disc_face([["disc1.jpg"]], 2) is None
    assert disc_face([], 1) is None
