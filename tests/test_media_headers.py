"""
Pictures and audio go out with headers that keep them from ever acting as a page (1.0.3).

Their bytes come from strangers: an embedded picture in a file a Soulseek peer shared, served by
the library routes or relayed from Navidrome. Each route decides which types it will name, and
GuardMedia in app.py adds the rest to every one of them - nosniff, a sandbox with nothing
allowed, and same-origin, so no other website can embed them either.

Driven through the whole app, since the headers are a middleware's.
"""

from fastapi.testclient import TestClient

from src.api.app import serves_media, start
from src.config import Config

MEDIA_HEADERS = {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
    "cross-origin-resource-policy": "same-origin",
}


def test_library_art_carries_the_media_headers(tmp_path, monkeypatch):
    album = tmp_path / "Portishead" / "Dummy (1994)"
    album.mkdir(parents=True)
    (album / "cover.jpg").write_bytes(b"\xff\xd8\xff\xe0" + bytes(5000))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    response = TestClient(start()).get("/deadwax/library/art", params={"album": "Portishead/Dummy (1994)"},
                                       headers={"Accept-Encoding": "gzip"})

    assert response.status_code == 200
    assert response.headers["content-type"] == "image/jpeg"
    assert "content-encoding" not in response.headers
    for name, value in MEDIA_HEADERS.items():
        assert response.headers[name] == value


def test_a_media_routes_refusal_carries_them_too(tmp_path, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    response = TestClient(start()).get("/deadwax/library/tracks/picture", params={"album": "../..", "file": "x"})

    assert response.status_code == 404
    for name, value in MEDIA_HEADERS.items():
        assert response.headers[name] == value


def test_the_rest_of_the_app_is_left_alone():
    """The sandbox is for bytes nobody here made - not deadwax's own pages and JSON."""
    client = TestClient(start())

    for path in ("/deadwax/health", "/player/"):
        response = client.get(path)
        assert "content-security-policy" not in response.headers
        assert "cross-origin-resource-policy" not in response.headers


def test_exactly_the_media_routes_are_named():
    for path in ("/deadwax/library/art", "/deadwax/library/artist/art", "/deadwax/library/disc_art",
                 "/deadwax/library/disc_art/navidrome", "/deadwax/library/tracks/picture",
                 "/deadwax/navidrome/stream/song-1", "/deadwax/navidrome/cover/al-1"):
        assert serves_media(path), path

    #? "/deadwax/library/art" as a prefix caught all of these, and kept their JSON from being gzipped
    for path in ("/deadwax/library/artist", "/deadwax/library/artist/search", "/deadwax/library/art/fetch",
                 "/deadwax/library/disc_art/fetch", "/deadwax/library/tracks", "/deadwax/navidrome/status",
                 "/player/icon-512.png", "/styles/font/noto-sans/latin.woff2"):
        assert not serves_media(path), path
