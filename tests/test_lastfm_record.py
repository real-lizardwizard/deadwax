"""
The Last.fm recorder (tests/fixtures/lastfm/record.py, 2.1.36) run offline, against a fake urlopen that echoes the key
back wherever an answer could: in an answer's JSON, an error's message, a header, a page that isn't JSON. What it
holds: the key is in no file written and nothing printed, every file has Last.fm's caching headers, and the key is
only ever sent to Last.fm's API over https.
"""

import email.message
import http
import importlib.util
import io
import json
import urllib.request
import urllib.response
from pathlib import Path

import pytest

RECORDER = Path(__file__).resolve().parent / "fixtures/lastfm/record.py"
KEY = "5e17e1d0b5e17e1d0b5e17e1d0b5e1ab"


@pytest.fixture
def recorder():
    spec = importlib.util.spec_from_file_location("lastfm_recorder", RECORDER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeLastFm(urllib.request.BaseHandler):
    """Last.fm as a urllib handler, ahead of urllib's own (handler_order): the recorder's real opener - its handling
    of redirects and errors included - runs around it, and nothing reaches the network. `answer(url)` is the
    (status, headers, body) of each request, http:// or https://, all of them kept in `sent`."""
    handler_order = 100

    def __init__(self, sent: list, answer):
        self.sent, self.answer = sent, answer

    def https_open(self, request):
        self.sent.append(request)
        status, headers, body = self.answer(request.full_url)
        response = urllib.response.addinfourl(io.BytesIO(body), headers, request.full_url, status)
        response.msg = http.HTTPStatus(status).phrase
        return response

    http_open = https_open


def headers_echoing(url: str) -> email.message.Message:
    headers = email.message.Message()
    headers["Cache-Control"] = f"max-age=86400, private; for={KEY}"
    headers["Expires"] = "Tue, 01 Dec 2026 12:00:00 GMT"
    headers["Content-Type"] = "application/json"
    headers["X-Echo"] = url
    return headers


def echoing(url: str):
    headers = headers_echoing(url)
    if "Nonexistent" in url or "00000000-0000" in url:
        body = json.dumps({"error": 6, "message": f"The artist you supplied could not be found ({url})"})
        return 400, headers, body.encode()
    if "album.getinfo" in url:
        return 200, headers, f"<html>a page, not JSON: {url}</html>".encode()
    return 200, headers, json.dumps({"echo": {"url": url, "key": KEY, "list": [KEY]}}).encode()


def fake_last_fm(sent: list) -> tuple:
    return (FakeLastFm(sent, echoing),)


def test_the_key_is_in_nothing_written_or_said(recorder, tmp_path, capsys):
    sent: list = []

    code = recorder.main([], out=tmp_path, network=fake_last_fm(sent), pause=0, environ={"LASTFM_API_KEY": KEY})

    assert code == 0
    files = sorted(tmp_path.glob("*.json"))
    assert len(files) == len(recorder.recordings()) == len(sent)
    for path in files:
        raw = path.read_bytes()
        assert KEY.encode() not in raw, path.name
        assert raw.isascii()
        written = json.loads(raw)
        assert "api_key" not in written["params"]
        assert set(written["headers"]) >= {"Cache-Control", "Expires"}
        assert written["headers"]["Cache-Control"] == f"max-age=86400, private; for={recorder.MARK}"
    printed = capsys.readouterr()
    assert KEY not in printed.out + printed.err


def test_errors_and_pages_that_aren_t_json_are_recorded_as_they_came(recorder, tmp_path):
    recorder.main([], out=tmp_path, network=fake_last_fm([]), pause=0, environ={"LASTFM_API_KEY": KEY})

    unknown = json.loads((tmp_path / "unknown-name.info.json").read_text())
    page = json.loads((tmp_path / "portishead.dummy.album-info.json").read_text())

    assert unknown["status"] == 400 and unknown["answer"]["error"] == 6
    assert recorder.MARK in unknown["answer"]["message"]
    assert page["status"] == 200 and page["answer"].startswith("<html>a page, not JSON")


def test_the_key_goes_only_to_last_fm_over_https(recorder, tmp_path):
    sent: list = []

    recorder.main([], out=tmp_path, network=fake_last_fm(sent), pause=0, environ={"LASTFM_API_KEY": KEY})

    for request in sent:
        assert request.full_url.startswith("https://ws.audioscrobbler.com/2.0/?")
        assert f"api_key={KEY}" in request.full_url
        assert request.get_header("User-agent").startswith("deadwax/")


def test_what_it_records(recorder):
    asked = {name: (method, params) for name, method, params in recorder.recordings()}

    for artist in ("tame-impala", "dance-gavin-dance", "portishead"):
        for short in ("info", "top-tracks", "similar", "top-albums"):
            assert f"{artist}.{short}.mbid" in asked and f"{artist}.{short}.name" in asked
    assert asked["portishead.dummy.album-info"][0] == "album.getinfo"
    assert asked["tame-impala.let-it-happen.similar"] == (
        "track.getsimilar", {"artist": "Tame Impala", "track": "Let It Happen", "limit": "100", "autocorrect": "1"})
    assert {"unknown-name.info", "unknown-mbid.top-tracks", "misspelt.info"} <= set(asked)


def test_no_key_records_nothing(recorder, tmp_path):
    def never(url):
        raise AssertionError("asked Last.fm with no key")

    assert recorder.main([], out=tmp_path, network=(FakeLastFm([], never),), pause=0, environ={}) == 2
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("status", [301, 302, 303, 307, 308])
@pytest.mark.parametrize("to", ["http://elsewhere.example/2.0/", "https://ws.audioscrobbler.com/2.0/again/"])
def test_a_redirect_is_never_followed_and_stops_the_run(recorder, tmp_path, capsys, status, to):
    """The key is in the address: a redirect followed would carry it wherever the answer pointed - over plain http
    too. The first answer redirects: nothing more is asked, the redirect is recorded (the key out of its Location)
    and the run stops, saying so."""
    sent: list = []

    def moving(url):
        if len(sent) > 1:
            return echoing(url)
        headers = headers_echoing(url)
        headers["Location"] = to + "?" + url.split("?", 1)[1]
        return status, headers, b"<html>moved</html>"

    code = recorder.main([], out=tmp_path, network=(FakeLastFm(sent, moving),), pause=0,
                         environ={"LASTFM_API_KEY": KEY})

    assert [request.full_url.split("?")[0] for request in sent] == ["https://ws.audioscrobbler.com/2.0/"]
    assert code == 3
    first = recorder.recordings()[0][0]
    assert [path.name for path in tmp_path.iterdir()] == [f"{first}.json"]
    written = json.loads((tmp_path / f"{first}.json").read_text())
    assert written["status"] == status
    assert written["headers"]["Location"].startswith(to + "?method=artist.getinfo")
    assert f"api_key={recorder.MARK}" in written["headers"]["Location"]
    assert KEY not in (tmp_path / f"{first}.json").read_text()
    printed = capsys.readouterr()
    assert KEY not in printed.out + printed.err
    assert f"redirect ({status})" in printed.err and to in printed.err and "stopped" in printed.err


def test_the_recorder_s_opener_refuses_redirects_itself(recorder):
    """What main() asks with is opener(); every 3xx urllib knows how to follow is refused by it, not by a caller."""
    handlers = recorder.opener().handlers

    assert any(isinstance(handler, recorder.NoRedirects) for handler in handlers)
    assert not any(type(handler) is urllib.request.HTTPRedirectHandler for handler in handlers)
