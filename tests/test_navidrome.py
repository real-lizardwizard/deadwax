"""
The player's way to Navidrome.

deadwax holds the Navidrome login and passes on a fixed list of calls, so what these tests
protect is that line: the password never leaves the process, the page cannot stand in for the
login, nothing beyond the listed calls gets through - and audio arrives the way Safari insists
on, as byte ranges, with a failed call reported as a failure rather than played as a song.

Navidrome itself is replaced by httpx's MockTransport, answering as Navidrome's Subsonic API
does, so none of this needs a server. deadwax is NOT replaced: every request goes through the
app start() builds, middleware and all (without its lifespan, so nothing connects anywhere). The
routes alone passed every test here while the real app gzipped Safari's byte ranges.
"""

import asyncio
import hashlib
import json
import logging
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import (NavidromeClient, NavidromeError, auth_params,  # noqa: E402
                                        navidrome, subsonic_body, without_login)
from src.config import Config, describe_navidrome_url  # noqa: E402
from src.routes import navidrome as navidrome_routes  # noqa: E402
from src.routes.settings import _validate, settings  # noqa: E402

AUDIO = bytes(range(256)) * 40  # 10240 bytes of "song"
JPEG = b"\xff\xd8\xff\xe0" + bytes(5000)  # big enough that gzip would take it on

#? What every media answer carries, whatever route it came from (GuardMedia in app.py).
MEDIA_HEADERS = {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
    "cross-origin-resource-policy": "same-origin",
}


class Streamed(httpx.AsyncByteStream):
    """
    A body that arrives as a network one does. httpx reads a plain `content=` body the moment
    the response is built, which a real connection never does - and the route streams it on
    raw, as it must for the byte counts to hold. `fails` is raised once `fails_after` bytes have
    gone, as httpx raises when a connection drops part-way.
    """

    def __init__(self, data: bytes, fails: Exception | None = None, fails_after: int | None = None):
        self.data = data
        self.fails = fails
        self.fails_after = len(data) if fails_after is None else fails_after

    async def __aiter__(self):
        for offset in range(0, len(self.data), 4096):
            if self.fails and offset >= self.fails_after:
                raise self.fails
            yield self.data[offset:offset + 4096]
        if self.fails:
            raise self.fails


def streamed(status: int, data: bytes, headers: dict, **failure) -> httpx.Response:
    return httpx.Response(status, stream=Streamed(data, **failure),
                          headers={"content-length": str(len(data)), **headers})


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome",
                                  "serverVersion": "0.55.2", **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1",
                                  "error": {"code": code, "message": message}}}


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

    navidrome.client = httpx.AsyncClient(
        transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest"
    )
    yield state, seen
    asyncio.run(navidrome.close_client())


@pytest.fixture
def client():
    """
    The whole app, as uvicorn serves it. The route reads the module's one Navidrome client,
    which `upstream` has already swapped for the fake.
    """
    return TestClient(start())


def query(request: httpx.Request) -> dict:
    return {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query).items()}


def asgi_messages(path: str, query_string: bytes = b"") -> list[dict]:
    """
    Every message the app sends for one GET, for what a TestClient can't show: whether the
    answer was FINISHED - its last body message saying there is no more to come.
    """
    app = start()
    sent = []

    async def receive():
        await asyncio.sleep(3600)  # the phone never hangs up during the test
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
        "scheme": "http", "path": path, "root_path": "", "raw_path": path.encode(),
        "query_string": query_string, "headers": [(b"host", b"test")],
        "server": ("test", 80), "client": ("phone", 1),
    }
    asyncio.run(app(scope, receive, send))
    return sent


# ---------------------------------------------------------------- the login

def test_the_token_is_the_salted_md5_subsonic_asks_for():
    params = auth_params("james", "sesame", salt="c19b2d")

    assert params["t"] == hashlib.md5(b"sesamec19b2d").hexdigest()
    assert params["s"] == "c19b2d"
    assert params["u"] == "james"
    assert params["c"] == "deadwax", "Navidrome lists the client by this name under Players"
    assert "sesame" not in json.dumps(params), "token auth - the password itself is never sent"


def test_every_request_gets_a_fresh_salt():
    assert auth_params("u", "p")["s"] != auth_params("u", "p")["s"]


def test_the_page_cannot_stand_in_for_the_login(configured):
    """The login is laid on last, so a `u` or `t` from anywhere else is overwritten."""
    params = NavidromeClient._params({"u": "admin", "t": "forged", "id": "song-1"})

    assert params["u"] == "james"
    assert params["t"] != "forged"
    assert params["id"] == "song-1"


def test_the_password_never_reaches_navidrome_in_the_clear(upstream, client):
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(albumList2={"album": []}))

    client.get("/deadwax/navidrome/albums")

    assert "hunter2-very-secret" not in str(seen[0].url)


def test_the_login_never_reaches_the_container_log(upstream, client, caplog):
    """
    httpx logs every request's whole URL at INFO, and the container log takes INFO - so every
    cover and every byte range wrote the login's token and salt where `docker logs` and Komodo
    show them, and Navidrome accepts that pair again for as long as the password stands.
    src/logger.py quiets httpx; this holds it to that, through a real call.
    """
    state, seen = upstream
    state["handler"] = lambda request: streamed(200, JPEG, {"content-type": "image/jpeg"})
    caplog.set_level(logging.INFO)

    #? first, that this test can see a leak at all: with httpx back at INFO, the line is there
    httpx_log = logging.getLogger("httpx")
    quiet = httpx_log.level
    httpx_log.setLevel(logging.INFO)
    try:
        client.get("/deadwax/navidrome/cover/al-1")
    finally:
        httpx_log.setLevel(quiet)
    assert query(seen[0])["t"] in caplog.text, "the check can't see httpx's lines, so it proves nothing"

    caplog.clear()
    client.get("/deadwax/navidrome/stream/song-1?format=raw")
    client.get("/deadwax/navidrome/status")

    for request in seen[1:]:
        sent = query(request)
        for record in caplog.records:
            assert sent["t"] not in record.getMessage() and sent["s"] not in record.getMessage()


# ---------------------------------------------------------------- only the listed calls

def test_there_is_no_general_proxy():
    """
    Each Subsonic call the player may make is its own route. The account may be Navidrome's
    admin and deadwax has no login, so a catch-all would hand out user management.
    """
    paths = sorted(route.path for route in navidrome_routes.router.routes)

    assert paths == [
        "/albums", "/albums/{album_id}", "/cover/{cover_id}", "/scrobble/{song_id}",
        "/status", "/stream/{song_id}",
    ]


def test_an_album_list_order_outside_subsonics_own_is_refused(upstream, client):
    _, seen = upstream

    assert client.get("/deadwax/navidrome/albums?order=deleteUser").status_code == 422
    assert seen == []


# ---------------------------------------------------------------- answers and failures

def test_not_configured_says_what_to_fill_in(monkeypatch, client):
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)

    status = client.get("/deadwax/navidrome/status").json()
    assert status["configured"] is False
    assert "NAVIDROME_URL" in status["problem"]

    response = client.get("/deadwax/navidrome/albums")
    assert response.status_code == 503
    assert "settings tab" in response.json()["detail"]


def test_a_refused_login_names_the_settings_to_check(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(40, "Wrong username or password"))

    status = client.get("/deadwax/navidrome/status").json()

    assert status["ok"] is False
    assert "NAVIDROME_USER" in status["problem"] and "NAVIDROME_PASSWORD" in status["problem"]


def test_an_unusable_address_from_the_environment_is_refused_by_the_client_too(upstream, client, monkeypatch):
    """
    The settings tab refuses an address with a login in it; one from compose never went through
    the tab. Start-up says it can't be used - and now nothing is sent to it either, and the player
    is told why without the password being quoted back (1.0.3 review).
    """
    state, seen = upstream
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://james:hunter2@navidrome:4533")

    status = client.get("/deadwax/navidrome/status")
    albums = client.get("/deadwax/navidrome/albums")

    assert status.json()["configured"] is True and status.json()["ok"] is False
    assert "user name or password" in status.json()["problem"]
    assert albums.status_code == 503 and "user name or password" in albums.json()["detail"]
    for response in (status, albums):
        assert "hunter2" not in response.text
    assert seen == [], "nothing was sent to that address"


def test_an_address_without_a_scheme_is_described_without_being_quoted():
    """Typed as `user:password@host`, the old advice repeated it back as "use http://user:password@..."."""
    problem = describe_navidrome_url("james:hunter2@navidrome:4533")
    assert "scheme" in problem and "hunter2" not in problem and "james" not in problem
    assert "hunter2" not in describe_navidrome_url("james:hunter2@navidrome://x")


def test_an_address_quoted_in_an_error_carries_no_login():
    assert without_login("http://james:hunter2@navidrome:4533/music") == "http://navidrome:4533/music"
    assert without_login("http://navidrome:4533") == "http://navidrome:4533"
    assert without_login(None) == ""


def test_navidrome_not_answering_says_it_couldnt_be_reached(upstream):
    """And marks it as such, for the apply - which holds a rename back for this, not for a refusal."""
    state, _ = upstream

    def refused(request):
        raise httpx.ConnectError("All connection attempts failed", request=request)

    state["handler"] = refused
    with pytest.raises(NavidromeError) as caught:
        asyncio.run(navidrome.call("ping"))
    assert caught.value.unreachable is True
    assert "couldn't be reached at http://navidrome:4533" in str(caught.value)

    state["handler"] = lambda request: httpx.Response(200, json=failed(40, "Wrong username or password"))
    with pytest.raises(NavidromeError) as caught:
        asyncio.run(navidrome.call("ping"))
    assert caught.value.unreachable is False, "an answer came - it just said no"


def test_status_names_the_server(upstream, client):
    status = client.get("/deadwax/navidrome/status").json()

    assert status == {"configured": True, "ok": True, "server": "Navidrome 0.55.2", "problem": None}


def test_something_that_isnt_navidrome_is_named_as_such():
    with pytest.raises(NavidromeError, match="address of Navidrome itself"):
        subsonic_body({"hello": "this is a router login page"})


def test_albums_are_asked_for_in_the_order_given(upstream, client):
    state, seen = upstream
    state["handler"] = lambda request: httpx.Response(
        200, json=ok(albumList2={"album": [{"id": "a1", "name": "Dummy"}]})
    )

    albums = client.get("/deadwax/navidrome/albums?order=alphabeticalByArtist&size=30&offset=60").json()

    assert albums == {"albums": [{"id": "a1", "name": "Dummy"}]}
    sent = query(seen[0])
    assert seen[0].url.path == "/rest/getAlbumList2"
    assert (sent["type"], sent["size"], sent["offset"]) == ("alphabeticalByArtist", "30", "60")


def test_an_empty_library_is_an_empty_list_not_an_error(upstream, client):
    """Subsonic leaves `album` out entirely when there are none."""
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok(albumList2={}))

    assert client.get("/deadwax/navidrome/albums").json() == {"albums": []}


def test_an_unknown_album_is_a_404(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(70, "Album not found"))

    assert client.get("/deadwax/navidrome/albums/nope").status_code == 404


# ---------------------------------------------------------------- audio

def ranged(request: httpx.Request) -> httpx.Response:
    """Navidrome serving a file as it is (Go's ServeContent): whole, or the byte range asked for."""
    header = request.headers.get("range")
    if not header:
        return streamed(200, AUDIO, {"content-type": "audio/flac", "accept-ranges": "bytes"})
    start, _, end = header.removeprefix("bytes=").partition("-")
    start, end = int(start), int(end) if end else len(AUDIO) - 1
    if start >= len(AUDIO):
        return httpx.Response(416, text="invalid range: failed to overlap\n", headers={
            "content-type": "text/plain; charset=utf-8", "content-range": f"bytes */{len(AUDIO)}",
        })
    return streamed(206, AUDIO[start:end + 1], {
        "content-type": "audio/flac",
        "accept-ranges": "bytes",
        "content-range": f"bytes {start}-{end}/{len(AUDIO)}",
    })


#? What Navidrome says a transcode will come to (duration x bit rate / 8 x 1024) and what it then
#? sends - a few per cent under, as an MP3 at a constant bit rate is.
ESTIMATE = 10240
TRANSCODED = bytes(range(256)) * 39


def transcoding(request: httpx.Request) -> httpx.Response:
    """
    Navidrome transcoding as it plays (core/stream/media_streamer.go): a 200 whatever range was
    asked for, Accept-Ranges: none, and a length only when asked for one - its estimate. It closes
    the connection where the transcode really ends, which httpx reports as an error.
    """
    headers = {"content-type": "audio/mpeg", "accept-ranges": "none"}
    if query(request).get("estimateContentLength") != "true":
        return httpx.Response(200, stream=Streamed(TRANSCODED), headers=headers)
    cut = httpx.RemoteProtocolError(
        f"peer closed connection without sending complete message body: "
        f"received {len(TRANSCODED)} bytes, expected {ESTIMATE}"
    )
    return httpx.Response(200, stream=Streamed(TRANSCODED, fails=cut),
                          headers={**headers, "content-length": str(ESTIMATE)})


def test_safaris_two_byte_probe_gets_a_206(upstream, client):
    """
    Safari asks for bytes 0-1 before it will play anything, and gives up on audio from a server
    that answers a range with the whole file. It says it takes gzip, and the app's gzip used to
    take it at its word: a compressed 206 with no length.
    """
    state, seen = upstream
    state["handler"] = ranged

    response = client.get("/deadwax/navidrome/stream/song-1?format=raw",
                          headers={"Range": "bytes=0-1", "Accept-Encoding": "gzip, deflate, br"})

    assert response.status_code == 206
    assert response.content == AUDIO[:2]
    assert "content-encoding" not in response.headers
    assert response.headers["content-length"] == "2"
    assert response.headers["content-range"] == f"bytes 0-1/{len(AUDIO)}"
    assert response.headers["accept-ranges"] == "bytes"
    assert seen[0].headers["range"] == "bytes=0-1", "the range is passed on, not served whole"


def test_a_seek_gets_the_rest_of_the_file(upstream, client):
    state, _ = upstream
    state["handler"] = ranged

    response = client.get("/deadwax/navidrome/stream/song-1?format=raw",
                          headers={"Range": "bytes=1000-", "Accept-Encoding": "gzip"})

    assert response.status_code == 206
    assert response.content == AUDIO[1000:]
    assert "content-encoding" not in response.headers
    assert response.headers["content-length"] == str(len(AUDIO) - 1000)
    assert response.headers["content-range"] == f"bytes 1000-{len(AUDIO) - 1}/{len(AUDIO)}"


def test_a_range_past_the_end_says_where_the_end_is(upstream, client):
    """Go's own 416 carries Content-Range: bytes */N, which is how the phone learns the length."""
    state, _ = upstream
    state["handler"] = ranged

    response = client.get("/deadwax/navidrome/stream/song-1?format=raw",
                          headers={"Range": f"bytes={len(AUDIO)}-"})

    assert response.status_code == 416
    assert response.headers["content-range"] == f"bytes */{len(AUDIO)}"


def test_a_seek_carries_its_conditions_to_navidrome(upstream, client):
    """
    If-Range is what stops a seek splicing two versions of a file a retag rewrote in place:
    Navidrome answers the whole new file instead of a range of it.
    """
    state, seen = upstream
    state["handler"] = ranged

    client.get("/deadwax/navidrome/stream/song-1?format=raw", headers={
        "Range": "bytes=1000-", "If-Range": '"v1"', "If-None-Match": '"v1"',
        "If-Modified-Since": "Sat, 26 Sep 2026 10:00:00 GMT", "Cookie": "not=forwarded",
    })

    sent = seen[0].headers
    assert (sent["range"], sent["if-range"], sent["if-none-match"]) == ("bytes=1000-", '"v1"', '"v1"')
    assert sent["if-modified-since"] == "Sat, 26 Sep 2026 10:00:00 GMT"
    assert "cookie" not in sent, "only the listed request headers are passed on"


def test_audio_is_always_revalidated(upstream, client):
    """A retag rewrites a file in place under the same URL, so a cached song must be asked about."""
    state, _ = upstream
    state["handler"] = ranged

    response = client.get("/deadwax/navidrome/stream/song-1?format=raw")

    assert response.headers["cache-control"] == "no-cache"
    assert response.headers["content-type"] == "audio/flac"


def test_the_file_as_it_is_is_asked_for_by_name(upstream, client):
    """
    format=raw is what the player sends for everything it can play: Navidrome answers it before
    it looks at the Players page, where a bit rate would turn every song into a transcode. It
    needs no estimated length - it has a real one.
    """
    state, seen = upstream
    state["handler"] = ranged

    client.get("/deadwax/navidrome/stream/song-1?format=raw")

    sent = query(seen[0])
    assert sent["format"] == "raw" and sent["id"] == "song-1"
    assert "estimateContentLength" not in sent and "maxBitRate" not in sent


def test_no_format_is_passed_on_as_none(upstream, client):
    """Left out, it stays out - but it may still become a transcode, so it asks for a length."""
    state, seen = upstream
    state["handler"] = ranged

    client.get("/deadwax/navidrome/stream/song-1")

    sent = query(seen[0])
    assert "format" not in sent and "maxBitRate" not in sent
    assert sent["estimateContentLength"] == "true", "Navidrome reads it only for a transcode"


def test_a_transcode_asks_navidrome_for_a_length(upstream, client):
    """
    Without estimateContentLength a transcode goes out with no length at all, and it has no byte
    ranges either way: Safari's probe gets the whole thing, as a 200.
    """
    state, seen = upstream
    state["handler"] = transcoding

    response = client.get("/deadwax/navidrome/stream/song-1?format=mp3&max_bitrate=256",
                          headers={"Range": "bytes=0-1", "Accept-Encoding": "gzip"})

    sent = query(seen[0])
    assert (sent["format"], sent["maxBitRate"], sent["estimateContentLength"]) == ("mp3", "256", "true")
    assert response.status_code == 200
    assert response.headers["accept-ranges"] == "none"
    assert response.headers["content-length"] == str(ESTIMATE)
    assert response.headers["content-type"] == "audio/mpeg"
    assert "content-encoding" not in response.headers


def test_a_transcode_ending_short_of_its_estimate_is_one_line_not_an_error(upstream, caplog):
    """
    Navidrome's estimate is usually a few per cent over, and it closes the connection where the
    transcode ends - an error to httpx, and to h11 on the way out. The phone's answer is left
    unfinished, as Navidrome's was, and the log says what happened in words.
    """
    state, _ = upstream
    state["handler"] = transcoding
    caplog.set_level(logging.INFO)

    sent = asgi_messages("/deadwax/navidrome/stream/song-1", b"format=mp3")

    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body")
    assert body == TRANSCODED, "every byte Navidrome sent is passed on"
    assert sent[-1]["more_body"] is True, "left unfinished: no closing message"
    about = [r for r in caplog.records if "song-1" in r.getMessage()]
    assert [r.getMessage() for r in about] == [
        f"player: the transcode of song song-1 ended at {len(TRANSCODED)} of the {ESTIMATE} bytes "
        f"Navidrome estimated, and its connection was closed there"
    ]
    assert about[0].levelno == logging.INFO, "how a transcode ordinarily ends - not a warning"


@pytest.mark.parametrize("sent", [0, ESTIMATE // 2, int(ESTIMATE * 0.9) - 1])
def test_a_transcode_far_short_of_its_estimate_is_a_warning(upstream, caplog, sent):
    """
    ffmpeg producing nothing, or dying part-way: Navidrome sends the estimate as its length and
    closes the connection where it stopped, exactly as a transcode that finished does. Only how
    far short says which - the estimate is never out by as much as a tenth (1.0.3 review).
    """
    state, _ = upstream
    cut = httpx.RemoteProtocolError("peer closed connection without sending complete message body")
    state["handler"] = lambda request: httpx.Response(
        200, stream=Streamed(TRANSCODED[:sent], fails=cut),
        headers={"content-type": "audio/mpeg", "accept-ranges": "none", "content-length": str(ESTIMATE)})
    caplog.set_level(logging.INFO)

    sent_messages = asgi_messages("/deadwax/navidrome/stream/song-1", b"format=mp3")

    assert not any(m.get("more_body") is False for m in sent_messages), "left unfinished, as a cut is"
    about = [r for r in caplog.records if "song-1" in r.getMessage()]
    assert [r.levelno for r in about] == [logging.WARNING]
    assert about[0].getMessage() == (
        f"player: Navidrome stopped sending song song-1 after {sent} of the {ESTIMATE} bytes Navidrome "
        f"estimated (peer closed connection without sending complete message body); the phone's "
        f"connection was closed there too")


def test_a_transcode_at_nine_tenths_of_its_estimate_is_its_ordinary_end(upstream, caplog):
    state, _ = upstream
    sent = int(ESTIMATE * 0.9) + 1
    cut = httpx.RemoteProtocolError("peer closed connection without sending complete message body")
    state["handler"] = lambda request: httpx.Response(
        200, stream=Streamed((TRANSCODED * 2)[:sent], fails=cut),
        headers={"content-type": "audio/mpeg", "accept-ranges": "none", "content-length": str(ESTIMATE)})
    caplog.set_level(logging.INFO)

    asgi_messages("/deadwax/navidrome/stream/song-1", b"format=mp3")

    about = [r for r in caplog.records if "song-1" in r.getMessage()]
    assert [r.levelno for r in about] == [logging.INFO]
    assert f"ended at {sent} of the {ESTIMATE} bytes" in about[0].getMessage()


def test_navidrome_stopping_part_way_is_one_warning_not_a_traceback(upstream, client, caplog):
    """
    Finishing the phone's answer would say the song ended there; with a Content-Length h11 won't
    allow it anyway, and uvicorn printed the refusal as a traceback. The connection is closed
    unfinished instead, and deadwax says why in one line.
    """
    state, _ = upstream
    state["handler"] = lambda request: streamed(
        200, AUDIO, {"content-type": "audio/flac", "accept-ranges": "bytes"},
        fails=httpx.ReadError("connection reset by peer"), fails_after=4096,
    )

    #? raise_server_exceptions is on: anything escaping the app would fail the test here
    response = client.get("/deadwax/navidrome/stream/song-1?format=raw")
    assert response.status_code == 200

    warnings = [r.getMessage() for r in caplog.records if r.levelno == logging.WARNING]
    assert warnings == [f"player: Navidrome stopped sending song song-1 after 4096 of {len(AUDIO)} "
                        f"bytes (connection reset by peer); the phone's connection was closed there too"]

    sent = asgi_messages("/deadwax/navidrome/stream/song-1", b"format=raw")
    assert sent[-1]["more_body"] is True, "left unfinished: no closing message"


def test_a_whole_song_is_finished_properly(upstream):
    state, _ = upstream
    state["handler"] = ranged

    sent = asgi_messages("/deadwax/navidrome/stream/song-1", b"format=raw")

    assert sent[-1] == {"type": "http.response.body", "body": b"", "more_body": False}


def test_a_failed_stream_is_not_played_as_a_song(upstream, client):
    """Subsonic answers a failed stream with a 200 and a JSON body - which is not audio."""
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(70, "Song not found"))

    response = client.get("/deadwax/navidrome/stream/gone?format=raw")

    assert response.status_code == 404
    assert response.headers["content-type"].startswith("application/json")


@pytest.mark.parametrize("status, content_type", [
    (200, "text/html; charset=utf-8"),  # a proxy's sign-in page, answering for Navidrome
    (200, "text/plain"),
    (302, "text/html"),                 # a redirect to one
    (401, "text/html"),                 # a proxy's own refusal - Subsonic's is a code in a 200
    (404, "text/plain"),                # a web server at the wrong path
])
def test_something_other_than_navidrome_answering_a_stream_is_named(upstream, client, status, content_type):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(
        status, text="<html>please sign in</html>", headers={"content-type": content_type, "location": "/login"}
    )

    response = client.get("/deadwax/navidrome/stream/song-1?format=raw")

    assert response.status_code == (404 if status == 404 else 502)
    assert "address of Navidrome itself" in response.json()["detail"]
    assert "please sign in" not in response.text
    assert "location" not in response.headers


def test_navidromes_limit_on_transcodes_is_passed_on_with_its_retry_after(upstream, client):
    """Navidrome 0.64 answers a transcode over its cap with a 429, a Subsonic body and Retry-After."""
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(
        429, json=failed(0, "too many concurrent transcodes, please retry shortly"), headers={"retry-after": "5"}
    )

    response = client.get("/deadwax/navidrome/stream/song-1?format=mp3")

    assert response.status_code == 429
    assert response.headers["retry-after"] == "5"
    assert "too many concurrent transcodes" in response.json()["detail"]


@pytest.mark.parametrize("declared, served", [
    ("audio/flac", "audio/flac"),
    ("audio/ogg", "audio/ogg"),
    ("application/ogg", "application/ogg"),
    ("video/mp4", "application/octet-stream"),
    ("application/javascript", "application/octet-stream"),
    (None, "application/octet-stream"),
])
def test_audio_goes_out_as_audio_or_as_bytes(upstream, client, declared, served):
    state, _ = upstream
    headers = {"content-type": declared} if declared else {}
    state["handler"] = lambda request: streamed(200, AUDIO, headers)

    response = client.get("/deadwax/navidrome/stream/song-1?format=raw")

    assert response.headers["content-type"] == served
    for name, value in MEDIA_HEADERS.items():
        assert response.headers[name] == value


# ---------------------------------------------------------------- covers

def test_a_cover_is_never_gzipped(upstream, client):
    """Safari's <img> requests always say they take gzip. A JPEG is compressed already."""
    state, seen = upstream
    state["handler"] = lambda request: streamed(200, JPEG, {"content-type": "image/jpeg"})

    response = client.get("/deadwax/navidrome/cover/al-1?size=300", headers={"Accept-Encoding": "gzip"})

    assert response.content == JPEG
    assert "content-encoding" not in response.headers
    assert response.headers["content-length"] == str(len(JPEG))
    assert query(seen[0])["size"] == "300"


@pytest.mark.parametrize("policy", [
    "no-store",                              # a placeholder, for art Navidrome hasn't resolved yet
    "public, max-age=31536000, immutable",   # an id carrying the picture's hash
    "public, no-cache",                      # any other id: revalidate, by its ETag
])
def test_a_covers_cache_policy_is_navidromes(upstream, client, policy):
    state, _ = upstream
    state["handler"] = lambda request: streamed(200, JPEG, {"content-type": "image/jpeg", "cache-control": policy})

    assert client.get("/deadwax/navidrome/cover/al-1").headers["cache-control"] == policy


def test_a_cover_with_no_policy_of_its_own_is_kept_for_a_day(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: streamed(200, JPEG, {"content-type": "image/jpeg"})

    assert client.get("/deadwax/navidrome/cover/al-1").headers["cache-control"] == "private, max-age=86400"


def test_a_cover_the_phone_already_has_is_a_304(upstream, client):
    state, seen = upstream

    def handler(request):
        headers = {"etag": '"al-1-v2"', "cache-control": "public, no-cache"}
        if request.headers.get("if-none-match") == '"al-1-v2"':
            return httpx.Response(304, stream=Streamed(b""), headers=headers)
        return streamed(200, JPEG, {**headers, "content-type": "image/jpeg"})

    state["handler"] = handler

    response = client.get("/deadwax/navidrome/cover/al-1", headers={
        "If-None-Match": '"al-1-v2"', "If-Modified-Since": "Sat, 26 Sep 2026 10:00:00 GMT",
    })

    assert response.status_code == 304
    assert response.content == b""
    assert response.headers["etag"] == '"al-1-v2"'
    assert "content-type" not in response.headers
    assert seen[0].headers["if-modified-since"] == "Sat, 26 Sep 2026 10:00:00 GMT"


@pytest.mark.parametrize("declared", ["image/jpeg", "image/png", "image/gif", "image/webp", "image/avif", "image/bmp"])
def test_a_picture_goes_out_as_the_picture_it_is(upstream, client, declared):
    state, _ = upstream
    state["handler"] = lambda request: streamed(200, JPEG, {"content-type": declared})

    assert client.get("/deadwax/navidrome/cover/al-1").headers["content-type"] == declared


def test_a_cover_that_isnt_a_picture_goes_out_as_bytes_nothing_renders(upstream, client):
    """
    Navidrome sets no type on a cover - Go guesses one from the bytes - and serves one it can't
    decode as the bytes it was given, which a Soulseek peer's file chose.
    """
    state, _ = upstream
    state["handler"] = lambda request: streamed(200, b"alert(document.domain)", {"content-type": "application/javascript"})

    response = client.get("/deadwax/navidrome/cover/al-1")

    assert response.headers["content-type"] == "application/octet-stream"
    for name, value in MEDIA_HEADERS.items():
        assert response.headers[name] == value


@pytest.mark.parametrize("declared", ["text/html; charset=utf-8", "image/svg+xml"])
def test_a_cover_that_is_a_page_is_never_served(upstream, client, declared):
    """A web page, or an SVG, which carries script of its own: refused outright, never relayed."""
    state, _ = upstream
    page = b"<html><body><script>alert(document.domain)</script></body></html>"
    state["handler"] = lambda request: streamed(200, page, {"content-type": declared})

    response = client.get("/deadwax/navidrome/cover/al-1")

    assert response.status_code == 502
    assert response.headers["content-type"] == "application/json"
    assert b"<script>" not in response.content
    for name, value in MEDIA_HEADERS.items():
        assert response.headers[name] == value


# ---------------------------------------------------------------- plays

def test_a_play_is_counted_as_a_submission(upstream, client):
    _, seen = upstream

    client.post("/deadwax/navidrome/scrobble/song-1?submission=true&time=1727000000000")

    sent = query(seen[0])
    assert seen[0].url.path == "/rest/scrobble"
    assert (sent["id"], sent["submission"], sent["time"]) == ("song-1", "true", "1727000000000")


def test_a_scrobble_from_another_port_never_reaches_navidrome(upstream, client):
    """Navidrome's own pages, slskd's and the NAS's share deadwax's host, and aren't deadwax."""
    _, seen = upstream

    response = client.post("/deadwax/navidrome/scrobble/song-1?submission=true",
                           headers={"Origin": f"http://{client.base_url.host}:4533"})

    assert response.status_code == 403
    assert seen == []


def test_a_scrobble_from_deadwaxs_own_page_goes_through(upstream, client):
    _, seen = upstream
    origin = f"{client.base_url.scheme}://{client.base_url.netloc.decode()}"

    response = client.post("/deadwax/navidrome/scrobble/song-1?submission=true", headers={"Origin": origin})

    assert response.status_code == 200
    assert seen[0].url.path == "/rest/scrobble"


# ---------------------------------------------------------------- the page itself

def test_the_player_page_is_always_revalidated(client):
    """An installed web app revalidates on launch like any page, and a cached page is an old app."""
    response = client.get("/player/")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"


def test_the_players_icons_are_not_gzipped_but_its_stylesheet_is(client):
    icon = client.get("/player/icon-512.png", headers={"Accept-Encoding": "gzip"})
    stylesheet = client.get("/player/player.css", headers={"Accept-Encoding": "gzip"})

    assert icon.status_code == 200 and "content-encoding" not in icon.headers
    assert stylesheet.headers.get("content-encoding") == "gzip"


# ---------------------------------------------------------------- the settings tab

def find(payload: dict, key: str) -> dict:
    for group in payload["groups"]:
        for setting in group["settings"]:
            if setting["key"] == key:
                return setting
    raise AssertionError(f"{key} is not in the settings payload")


def test_the_navidrome_password_is_never_in_the_settings_payload(configured):
    payload = asyncio.run(settings())

    assert find(payload, "NAVIDROME_PASSWORD")["value"] == "set"
    assert "hunter2-very-secret" not in json.dumps(payload)


def test_unset_navidrome_is_optional_not_an_error(monkeypatch):
    for key in ("NAVIDROME_URL", "NAVIDROME_USER", "NAVIDROME_PASSWORD"):
        monkeypatch.setattr(Config, key, None)

    payload = asyncio.run(settings())

    assert {find(payload, key)["status"] for key in
            ("NAVIDROME_URL", "NAVIDROME_USER", "NAVIDROME_PASSWORD")} == {"unset"}


def test_a_url_without_a_login_is_flagged_incomplete(monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", None)
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", None)

    payload = asyncio.run(settings())

    assert find(payload, "NAVIDROME_URL")["status"] == "ok"
    assert find(payload, "NAVIDROME_USER")["status"] == "error"
    assert find(payload, "NAVIDROME_PASSWORD")["status"] == "error"


def test_a_navidrome_url_without_a_scheme_is_refused():
    assert "scheme" in _validate("NAVIDROME_URL", "navidrome:4533")
    assert _validate("NAVIDROME_URL", "http://navidrome:4533") is None
