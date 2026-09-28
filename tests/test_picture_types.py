"""
A picture from inside an audio file is served as an image, or as nothing a browser would render.

An embedded picture carries its own MIME type, typed by whoever made the file - for a download,
a stranger on Soulseek - and /library/tracks/picture and /library/art used to hand that string
to the browser as the Content-Type. A FLAC whose PICTURE block said `text/html` then served a
page, script and all, from deadwax's own address (found in the 1.0.3 audit). Now only the five
image types are named, the bytes' own signature stands in for a label that isn't one of them,
and anything else goes out as application/octet-stream.
"""

import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from mutagen.flac import FLAC, Picture

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import Config  # noqa: E402
from src.routes import library  # noqa: E402
from src.routes.library import served_image_type  # noqa: E402
from tests.test_retag import seed  # noqa: E402

ALBUM = "Tame Impala/The Slow Rush (2020)"
FIRST = "01 - One More Year.flac"
PAGE = b"<html><body><script>alert(document.domain)</script></body></html>"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


@pytest.fixture
def client(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    app = FastAPI()
    app.include_router(library.router, prefix="/deadwax/library")
    return TestClient(app)


def embed(path: Path, mime: str, data: bytes) -> None:
    audio = FLAC(str(path))
    picture = Picture()
    picture.type, picture.mime, picture.data = 3, mime, data
    audio.add_picture(picture)
    audio.save()


def test_a_picture_that_says_it_is_a_page_is_not_served_as_one(client, tmp_path):
    embed(seed(tmp_path) / FIRST, "text/html", PAGE)

    response = client.get("/deadwax/library/tracks/picture", params={"album": ALBUM, "file": FIRST})

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/octet-stream"
    assert response.content == PAGE, "the bytes are what the file holds; only the label changed"


def test_nor_as_an_album_cover(client, tmp_path):
    """/art falls back to the embedded picture when the folder has no cover file."""
    embed(seed(tmp_path) / FIRST, "text/html", PAGE)

    response = client.get("/deadwax/library/art", params={"album": ALBUM})

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/octet-stream"


def test_a_real_picture_is_served_as_it_always_was(client, tmp_path):
    embed(seed(tmp_path) / FIRST, "image/png", PNG)

    for path, params in (("tracks/picture", {"album": ALBUM, "file": FIRST}), ("art", {"album": ALBUM})):
        response = client.get(f"/deadwax/library/{path}", params=params)
        assert (response.headers["content-type"], response.content) == ("image/png", PNG)


def test_a_mislabelled_picture_is_known_by_its_bytes(client, tmp_path):
    embed(seed(tmp_path) / FIRST, "text/html", PNG)

    response = client.get("/deadwax/library/tracks/picture", params={"album": ALBUM, "file": FIRST})

    assert response.headers["content-type"] == "image/png"


@pytest.mark.parametrize("declared, data, served", [
    ("image/jpeg", JPEG, "image/jpeg"),
    ("IMAGE/PNG; charset=binary", PNG, "image/png"),
    ("image/jpg", JPEG, "image/jpeg"),
    ("image/x-png", PNG, "image/png"),
    ("PNG", PNG, "image/png"),
    ("", JPEG, "image/jpeg"),
    (None, b"GIF89a" + b"\x00" * 8, "image/gif"),
    ("application/octet-stream", b"RIFF\x00\x00\x00\x00WEBPVP8 ", "image/webp"),
    ("image/svg+xml", b"<svg xmlns='http://www.w3.org/2000/svg'><script/></svg>", "application/octet-stream"),
    ("text/html", PAGE, "application/octet-stream"),
    ("text/html; charset=utf-8", b"", "application/octet-stream"),
])
def test_which_type_is_served(declared, data, served):
    assert served_image_type(declared, data) == served
