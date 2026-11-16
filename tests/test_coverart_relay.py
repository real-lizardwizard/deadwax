"""
The Cover Art Archive relay for the iPhone app (2.1.24) - GET /deadwax/coverart/{kind}/{mbid} (src/routes/coverart.py),
src/coverart_cache.py and src/api/coverart_endpoint.py ArchiveFronts - through the whole app, start(), with an httpx
MockTransport for the Archive. The suite never calls out.

The fake Archive answers as the real one was seen to on 2026-11-14 (by hand, with curl - not deadwax):
`coverartarchive.org/release-group/<id>/front-250` and `/release/<id>/front-250` answer 307 to
`archive.org/download/mbid-<release>/mbid-<release>-<image>_thumb250.jpg`, which answers 302 to one of its servers
(`dn720706.ca.archive.org/0/items/...`), which answers 200 image/jpeg (41 KB at 250px, 268 KB at 1200); a release with
no art is a 404 as text/html.

What these hold: the two kinds, each through the Archive's redirects; any other kind, an mbid that isn't a lowercase
UUID and a size outside 250/500/1200 refused with 422 before anything is asked; a redirect off the Archive's hosts
refused (and never followed); a non-image refused; the size cap, declared or streamed; the deadline on the whole
fetch, and the ask's own shorter wait, the fetch carrying on for the next ask; the 404 and its brief memory; an
outage's hold, and a refusal that holds nothing else; one fetch for asks at once; the disk cache - a hit served
without asking, after a restart too, its folder private, its bound kept by the covers served longest ago; a kept
cover too old answered at once and refreshed behind it; the ETag and its 304; GuardMedia's headers and no gzip. The
route decided in tests/test_logins.py ROUTES, and a signed-out ask refused with logins on, are there.
"""

import asyncio
import gzip
import os
import re
import stat
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import __version__  # noqa: E402
from src import coverart_cache as C  # noqa: E402
from src.api import coverart_endpoint as E  # noqa: E402
from src.api.app import serves_media, start  # noqa: E402
from src.api.coverart_endpoint import archive_fronts, on_the_archive  # noqa: E402
from src.config import Config  # noqa: E402
from src.coverart_cache import CoverRelay, Front, KeptCovers  # noqa: E402
from src.routes import coverart as route  # noqa: E402

RELEASE = "30702389-5c67-4438-9ea0-2351c8de0f1d"
GROUP = "b1392450-e666-3926-a536-22c65f834433"
OTHER = "76df3287-6cda-33eb-8e9a-044b5e15ffdd"
BARE = "00000000-0000-4000-8000-000000000000"
IMAGE = "43287476628"
SERVER = "dn720706.ca.archive.org"


def jpeg(size: str, version: int = 1) -> bytes:
    """A cover's bytes, different for each size and version - a JPEG's start, then enough to be a real one's size."""
    return b"\xff\xd8\xff\xe0" + f"{size}px v{version} ".encode() * 600


class Clock:
    """The relay's two clocks, moved by hand: monotonic for what it remembers, the wall for a kept cover's age."""

    def __init__(self):
        self.now = 1000.0
        self.wall = time.time()

    def monotonic(self) -> float:
        return self.now

    def wall_clock(self) -> float:
        return self.wall


class Archive:
    """coverartarchive.org, archive.org and one of its servers, as seen by hand (the module's docstring). `releases`
    and `groups` say which have a front (a group's is RELEASE's); `instead`, when set, answers everything; `delay`
    waits before each answer. Every request kept."""

    def __init__(self):
        self.releases = {RELEASE: 1, OTHER: 1}
        self.groups = {GROUP}
        self.instead = None
        self.delay = 0.0
        self.requests: list[httpx.Request] = []

    async def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.delay:
            await asyncio.sleep(self.delay)
        if self.instead is not None:
            return self.instead(request)
        host, path = request.url.host, request.url.path
        if host == "coverartarchive.org":
            found = re.fullmatch(r"/(release|release-group)/([0-9a-f-]{36})/front-(250|500|1200)", path)
            if not found:
                return httpx.Response(400, text="Bad request")
            kind, mbid, size = found.groups()
            release = (RELEASE if mbid in self.groups else None) if kind == "release-group" else \
                (mbid if mbid in self.releases else None)
            if release is None:
                return httpx.Response(404, headers={"content-type": "text/html; charset=utf-8"},
                                      text="<html><body>No cover art found.</body></html>")
            return httpx.Response(307, headers={"location": f"https://archive.org/download/mbid-{release}/"
                                                            f"mbid-{release}-{IMAGE}_thumb{size}.jpg"},
                                  text="See: ...")
        if host == "archive.org" and path.startswith("/download/"):
            return httpx.Response(302, headers={"location": f"https://{SERVER}/0/items/{path[len('/download/'):]}",
                                                "content-type": "image/jpeg"})
        if host == SERVER:
            found = re.fullmatch(r"/0/items/mbid-([0-9a-f-]{36})/mbid-\1-\d+_thumb(250|500|1200)\.jpg", path)
            if found:
                mbid, size = found.groups()
                return httpx.Response(200, headers={"content-type": "image/jpeg"},
                                      content=jpeg(size, self.releases.get(mbid, 1)))
        return httpx.Response(404, text="not here")

    def hosts(self) -> list[str]:
        return [request.url.host for request in self.requests]

    def asked(self) -> list[str]:
        return [f"{request.url.host}{request.url.path}" for request in self.requests]


@asynccontextmanager
async def no_lifespan(app):
    #? nothing connects: no slskd, no poller - one event loop for the whole test, so a fetch carries on between asks
    yield


@pytest.fixture
def env(tmp_path, monkeypatch):
    archive = Archive()
    clock = Clock()
    base = tmp_path / "cache"
    base.mkdir()
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(base))
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "")
    monkeypatch.setattr(Config, "MUSICBRAINZ_USERAGENT", "")
    archive_fronts._client = httpx.AsyncClient(transport=httpx.MockTransport(archive.handle), follow_redirects=False)
    app = start()
    app.router.lifespan_context = no_lifespan
    app.state.coverart = CoverRelay(clock=clock.monotonic, wall_clock=clock.wall_clock)
    with TestClient(app) as client:
        yield SimpleNamespace(archive=archive, clock=clock, app=app, client=client, base=base,
                              folder=base / C.FOLDER_NAME)
    asyncio.run(archive_fronts.close_client())


def cover(env, kind: str = "release", mbid: str = RELEASE, headers: dict | None = None, **params) -> httpx.Response:
    return env.client.get(f"/deadwax/coverart/{kind}/{mbid}", params=params, headers=headers)


def raises(error: Exception):
    """An Archive that answers nothing: the request fails as `error`."""
    def answer(request):
        raise error
    return answer


def settle(env) -> None:
    """Every fetch under way finished."""
    async def wait():
        for task in list(env.app.state.coverart._flights.values()):
            await asyncio.gather(task, return_exceptions=True)
    env.client.portal.call(wait)


def restart(env) -> None:
    """A new relay, as after a start: nothing in memory, the folder as it was."""
    env.app.state.coverart = CoverRelay(clock=env.clock.monotonic, wall_clock=env.clock.wall_clock)


def kept_names(env) -> list[str]:
    return sorted(name for name in os.listdir(env.folder) if not name.endswith(".part"))


# ----------------------------------------------------------------- the two kinds

def test_a_release_front_is_fetched_through_the_archives_own_redirects_and_passed_on(env):
    answer = cover(env)

    assert answer.status_code == 200
    assert answer.content == jpeg("250")
    assert answer.headers["content-type"] == "image/jpeg"
    assert answer.headers["cache-control"] == route.COVER_CACHE
    assert answer.headers["etag"] == Front(jpeg("250"), "image/jpeg").etag
    #? the Archive, archive.org, its server - each hop checked and followed by hand
    assert env.archive.hosts() == ["coverartarchive.org", "archive.org", SERVER]
    assert env.archive.asked()[0] == f"coverartarchive.org/release/{RELEASE}/front-250"
    #? the agent the Archive is sent elsewhere: deadwax and its version, no contact without one
    assert all(request.headers["user-agent"] == f"deadwax/{__version__}" for request in env.archive.requests)


def test_the_contact_is_sent_when_there_is_one(env, monkeypatch):
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "someone@example.com")
    assert cover(env).status_code == 200
    agent = env.archive.requests[0].headers["user-agent"]
    assert __version__ in agent and "someone@example.com" in agent


def test_a_release_groups_front_is_the_archives_own_pick(env):
    answer = cover(env, "release-group", GROUP, size="500")

    assert answer.status_code == 200 and answer.content == jpeg("500")
    assert env.archive.asked()[0] == f"coverartarchive.org/release-group/{GROUP}/front-500"


@pytest.mark.parametrize("kind", ["artist", "recording", "Release", "release_group", "releasegroup", "front", "x"])
def test_any_other_kind_is_refused_before_anything_is_asked(env, kind):
    assert cover(env, kind).status_code == 422
    assert env.archive.requests == []


@pytest.mark.parametrize("mbid", [
    RELEASE.upper(),                     # MusicBrainz writes them lowercase, as every other route takes them
    RELEASE.replace("-", ""),            # not hyphenated
    RELEASE[:-1],                        # one short
    RELEASE + "0",                       # one long
    "{" + RELEASE + "}",
    "not-a-uuid",
    "3070238g-5c67-4438-9ea0-2351c8de0f1d",
    "%2e%2e",
    RELEASE + "%00",
    RELEASE + "%20",
])
def test_an_mbid_that_isnt_a_canonical_uuid_is_refused_with_422(env, mbid):
    assert cover(env, "release", mbid).status_code == 422
    assert env.archive.requests == []


@pytest.mark.parametrize("mbid", ["..%2F..%2Fadmin", f"{RELEASE}%2Ffront", f"{RELEASE}/front"])
def test_an_mbid_with_a_slash_in_it_never_reaches_the_route(env, mbid):
    assert cover(env, "release", mbid).status_code == 404
    assert env.archive.requests == []


@pytest.mark.parametrize("size", ["250", "500", "1200"])
def test_each_size_asks_for_that_thumbnail(env, size):
    answer = cover(env, size=size)

    assert answer.status_code == 200 and answer.content == jpeg(size)
    assert env.archive.asked()[0] == f"coverartarchive.org/release/{RELEASE}/front-{size}"


def test_250_is_what_is_asked_unless_another_size_is_given(env):
    """Search's rows draw a 44 pt cover, 132 px on a 3x screen: the Archive's smallest is the default."""
    assert cover(env).status_code == 200
    assert env.archive.asked()[0].endswith("/front-250")


@pytest.mark.parametrize("size", ["full", "0", "100", "2000", "0250", "250px", "-1", ""])
def test_any_other_size_is_refused_with_422(env, size):
    assert cover(env, size=size).status_code == 422
    assert env.archive.requests == []


# ----------------------------------------------------------------- not a general proxy

@pytest.mark.parametrize("location", [
    "https://example.com/cover.jpg",
    "https://archive.org.example.com/cover.jpg",
    "https://notarchive.org/cover.jpg",
    "https://coverartarchive.org.example.com/cover.jpg",
    "https://www.coverartarchive.org/cover.jpg",
    "https://coverartarchive.org:8443/cover.jpg",
    "https://archive.org:444/download/x.jpg",
    "https://user@archive.org/download/x.jpg",
    "http://127.0.0.1/cover.jpg",
    "http://[::1]/cover.jpg",
    "http://169.254.169.254/latest/meta-data/",
    "file:///etc/passwd",
    "ftp://archive.org/x.jpg",
    "//example.com/cover.jpg",
])
def test_a_redirect_off_the_archives_hosts_is_refused_and_never_followed(env, location):
    env.archive.instead = lambda request: httpx.Response(307, headers={"location": location})

    answer = cover(env)

    assert answer.status_code == 502
    assert answer.headers["cache-control"] == "no-store"
    #? asked once, of the Archive; the place it pointed at never
    assert env.archive.hosts() == ["coverartarchive.org"]


def test_a_redirect_with_nowhere_to_go_is_refused(env):
    env.archive.instead = lambda request: httpx.Response(302)
    assert cover(env).status_code == 502


@pytest.mark.parametrize("location, host", [
    ("https://archive.org/download/x/y.jpg", "archive.org"),
    ("https://ia800101.us.archive.org/0/items/x/y.jpg", "ia800101.us.archive.org"),
    ("http://archive.org/download/x/y.jpg", "archive.org"),
    #? relative to where it came from: still the Archive
    ("/release/30702389-5c67-4438-9ea0-2351c8de0f1d/43287476628-250.jpg", "coverartarchive.org"),
])
def test_a_redirect_to_the_archives_own_hosts_is_followed(env, location, host):
    first = []

    def answer(request):
        if not first:
            first.append(request)
            return httpx.Response(307, headers={"location": location})
        return httpx.Response(200, headers={"content-type": "image/png"}, content=b"\x89PNG" + b"\x00" * 2000)

    env.archive.instead = answer
    got = cover(env)

    assert got.status_code == 200 and got.headers["content-type"] == "image/png"
    assert env.archive.hosts() == ["coverartarchive.org", host]


def test_the_archives_hosts_are_exactly_these():
    for url in ("https://coverartarchive.org/x", "https://archive.org/x", f"https://{SERVER}/x",
                "https://ia800101.us.archive.org/x", "http://archive.org/x", "https://ARCHIVE.ORG/x"):
        assert on_the_archive(httpx.URL(url)), url
    for url in ("https://example.com/x", "https://evilarchive.org/x", "https://archive.org.evil/x",
                "https://coverartarchive.org:8080/x", "https://a:b@archive.org/x", "ftp://archive.org/x",
                "https://1.2.3.4/x", "https://sub.coverartarchive.org/x"):
        assert not on_the_archive(httpx.URL(url)), url


def test_more_redirects_than_the_chain_needs_are_refused(env):
    env.archive.instead = lambda request: httpx.Response(307, headers={"location": "https://archive.org/again"})

    assert cover(env).status_code == 502
    assert len(env.archive.requests) == E.FRONT_REDIRECTS + 1


@pytest.mark.parametrize("content_type", ["text/html; charset=utf-8", "image/svg+xml", "application/pdf",
                                          "application/octet-stream", "", "text/plain"])
def test_anything_but_an_image_is_refused(env, content_type):
    headers = {"content-type": content_type} if content_type else {}
    page = b"<script>alert(1)</script>" * 99
    env.archive.instead = lambda request: httpx.Response(200, headers=headers, content=page)

    answer = cover(env)

    assert answer.status_code == 502
    assert b"<script>" not in answer.content


@pytest.mark.parametrize("content_type", ["image/jpeg", "image/png", "image/gif", "image/webp"])
def test_each_image_type_is_passed_on_as_it_is(env, content_type):
    env.archive.instead = lambda request: httpx.Response(200, headers={"content-type": content_type},
                                                         content=b"pixels" * 500)
    answer = cover(env)
    assert answer.status_code == 200 and answer.headers["content-type"] == content_type


def test_an_empty_answer_is_refused(env):
    env.archive.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"}, content=b"")
    assert cover(env).status_code == 502


@pytest.mark.parametrize("status", [400, 401, 403, 410, 418])
def test_another_status_is_refused(env, status):
    env.archive.instead = lambda request: httpx.Response(status, text="no")
    assert cover(env).status_code == 502


class Pieces(httpx.AsyncByteStream):
    """A body sent a piece at a time, counting the pieces deadwax took."""

    def __init__(self, pieces: list[bytes]):
        self.pieces, self.taken = pieces, 0

    async def __aiter__(self):
        for piece in self.pieces:
            self.taken += 1
            yield piece


def test_every_hop_asks_for_the_cover_as_it_is(env):
    """(2.1.32, a fix to 2.1.24) Accept-Encoding: identity on every hop - httpx asks for gzip unless told otherwise."""
    assert cover(env).status_code == 200
    assert len(env.archive.requests) == 3
    assert all(request.headers["accept-encoding"] == "identity" for request in env.archive.requests)


@pytest.mark.parametrize("encoding", ["gzip", "gzip, gzip", "deflate", "br", "zstd", "GZIP"])
def test_a_cover_encoded_anyway_is_refused_unread(env, encoding):
    """(2.1.32, a fix to 2.1.24 - the artist pictures' review) read with aiter_bytes(), a gzip body was inflated past
    FRONT_MAX_BYTES before the cap counted it: 141 MB from 269 bytes of nested gzip. Refused before it is read."""
    stream = Pieces([gzip.compress(gzip.compress(bytes(16 << 20)))])
    env.archive.instead = lambda request: httpx.Response(
        200, headers={"content-type": "image/jpeg", "content-encoding": encoding}, stream=stream)

    assert cover(env).status_code == 502
    assert stream.taken == 0
    assert not env.folder.exists() or kept_names(env) == []


def test_a_cover_said_to_be_identity_is_passed_on(env):
    env.archive.instead = lambda request: httpx.Response(
        200, headers={"content-type": "image/jpeg", "content-encoding": "identity"}, content=jpeg("250"))
    answer = cover(env)
    assert answer.status_code == 200 and answer.content == jpeg("250")


def test_a_body_declared_past_the_cap_is_refused_unread(env, monkeypatch):
    monkeypatch.setattr(E, "FRONT_MAX_BYTES", 10_000)
    stream = Pieces([b"x" * 1000] * 20)
    env.archive.instead = lambda request: httpx.Response(
        200, headers={"content-type": "image/jpeg", "content-length": "20000"}, stream=stream)

    assert cover(env).status_code == 502
    assert stream.taken == 0
    assert not env.folder.exists() or kept_names(env) == []


def test_a_body_that_runs_past_the_cap_is_refused_as_soon_as_it_does(env, monkeypatch):
    monkeypatch.setattr(E, "FRONT_MAX_BYTES", 10_000)
    stream = Pieces([b"x" * 1000] * 50)
    env.archive.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"}, stream=stream)

    assert cover(env).status_code == 502
    #? the eleventh piece passes the cap: nothing after it is read
    assert stream.taken == 11


def test_a_body_at_the_cap_is_passed_on(env, monkeypatch):
    monkeypatch.setattr(E, "FRONT_MAX_BYTES", 10_000)
    env.archive.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"},
                                                         stream=Pieces([b"x" * 1000] * 10))
    answer = cover(env)
    assert answer.status_code == 200 and len(answer.content) == 10_000


# ----------------------------------------------------------------- slow, down, missing

def test_the_whole_fetch_has_a_deadline_and_a_slow_archive_is_a_504(env, monkeypatch):
    monkeypatch.setattr(E, "FRONT_DEADLINE_SECONDS", 0.2)
    env.archive.delay = 0.08   # each hop is quick enough; the three together aren't

    began = time.monotonic()
    answer = cover(env)

    assert answer.status_code == 504
    assert answer.json()["detail"] == route.WORDS[504]
    assert time.monotonic() - began < 2
    assert answer.headers["cache-control"] == "no-store"
    #? the third hop was asked and cut off before it answered: nothing kept
    assert env.archive.hosts() == ["coverartarchive.org", "archive.org", SERVER]
    assert not env.folder.exists() or kept_names(env) == []


def test_an_ask_waits_less_than_the_phone_does_and_the_fetch_carries_on_for_the_next(env, monkeypatch):
    """ANSWER_SECONDS: the ask is a 504 in time for the phone, the fetch shielded - its cover kept for the next ask."""
    monkeypatch.setattr(C, "ANSWER_SECONDS", 0.1)
    env.archive.delay = 0.1

    began = time.monotonic()
    assert cover(env).status_code == 504
    assert time.monotonic() - began < 1
    settle(env)
    asked = len(env.archive.requests)
    assert asked == 3

    answer = cover(env)
    assert answer.status_code == 200 and answer.content == jpeg("250")
    assert len(env.archive.requests) == asked


def test_the_ask_waits_under_the_phones_eight_seconds():
    assert C.ANSWER_SECONDS < 8 and E.FRONT_DEADLINE_SECONDS > C.ANSWER_SECONDS


def test_a_missing_front_is_a_404_remembered_briefly(env):
    answer = cover(env, mbid=BARE)
    assert answer.status_code == 404
    assert answer.json()["detail"] == route.WORDS[404]
    assert answer.headers["cache-control"] == "no-store"
    assert len(env.archive.requests) == 1

    #? a list of twenty, drawn again and again, asks once
    for _ in range(20):
        assert cover(env, mbid=BARE).status_code == 404
    assert len(env.archive.requests) == 1

    #? ...for a few minutes: then the Archive is asked again, and a cover added since shows
    env.clock.now += C.MISS_SECONDS + 1
    env.archive.releases[BARE] = 1
    assert cover(env, mbid=BARE).status_code == 200
    assert len(env.archive.requests) == 4


def test_a_missing_front_doesnt_hold_any_other_cover(env):
    assert cover(env, mbid=BARE).status_code == 404
    assert cover(env).status_code == 200


def test_the_memory_is_per_size_and_kind(env):
    assert cover(env, "release-group", BARE).status_code == 404
    env.archive.groups.add(BARE)
    assert cover(env, "release-group", BARE, size="500").status_code == 200


@pytest.mark.parametrize("trouble", [
    raises(httpx.ConnectError("no route to host")),
    raises(httpx.ReadError("connection reset")),
    lambda request: httpx.Response(503, text="Service Unavailable"),
    lambda request: httpx.Response(502, text="Bad Gateway"),
    lambda request: httpx.Response(429, text="Too Many Requests"),
])
def test_an_outage_is_a_quick_502_for_every_cover_not_kept_for_a_while(env, trouble):
    #? one kept before the Archive went away
    assert cover(env, mbid=OTHER).status_code == 200
    asked = len(env.archive.requests)
    env.archive.instead = trouble

    assert cover(env).status_code == 502
    assert len(env.archive.requests) == asked + 1

    #? meanwhile: every other cover a 502 at once, the Archive not asked - and a kept one served as ever
    for mbid in (BARE, GROUP):
        answer = cover(env, mbid=mbid)
        assert answer.status_code == 502 and answer.json()["detail"] == route.WORDS[502]
    assert cover(env, mbid=OTHER).status_code == 200
    assert len(env.archive.requests) == asked + 1

    #? and after it, asked again
    env.clock.now += max(C.OUTAGE_SECONDS, C.FAILED_SECONDS) + 1
    env.archive.instead = None
    assert cover(env).status_code == 200


def test_an_archive_that_hangs_at_connect_is_a_504_and_holds_the_rest(env):
    env.archive.instead = raises(httpx.ConnectTimeout("timed out"))

    assert cover(env).status_code == 504
    assert cover(env, mbid=OTHER).status_code == 502
    assert len(env.archive.requests) == 1


def test_one_bad_answer_holds_only_its_own_cover(env):
    """A refusal (not an image, here) is this answer's, not the Archive's: the next cover is asked as ever."""
    env.archive.instead = lambda request: httpx.Response(200, headers={"content-type": "text/html"}, text="<p>")
    assert cover(env).status_code == 502
    env.archive.instead = None

    #? remembered for its own few seconds...
    assert cover(env).status_code == 502
    assert len(env.archive.requests) == 1
    #? ...and nothing else held
    assert cover(env, mbid=OTHER).status_code == 200
    env.clock.now += C.FAILED_SECONDS + 1
    assert cover(env).status_code == 200


def test_a_fault_in_deadwax_is_a_502_not_a_crash(env, monkeypatch):
    async def broken(kind, mbid, size):
        raise KeyError("a bug")

    monkeypatch.setattr(archive_fronts, "front", broken)
    assert cover(env).status_code == 502


def test_asks_at_once_share_one_fetch(env):
    env.archive.delay = 0.05
    relay = env.app.state.coverart

    async def five():
        return await asyncio.gather(*(relay.answer("release", RELEASE, "250") for _ in range(5)))

    answers = env.client.portal.call(five)

    assert [answer.status for answer in answers] == [200] * 5
    assert env.archive.hosts() == ["coverartarchive.org", "archive.org", SERVER]


# ----------------------------------------------------------------- bounded (the review's)

def mbid_of(n: int) -> str:
    return f"{n:08x}-0000-4000-8000-000000000000"


class CountedFronts:
    """ArchiveFronts' place: every front a JPEG, after `pause` seconds - or, while `held` is set, once it is released -
    counting how many are being asked at once."""

    def __init__(self, pause: float = 0.0):
        self.pause = pause
        self.held: asyncio.Event | None = None
        self.asked: list[str] = []
        self.now = 0
        self.most = 0

    def hold(self) -> None:
        self.held = asyncio.Event()

    async def front(self, kind: str, mbid: str, size: str):
        self.asked.append(mbid)
        self.now += 1
        self.most = max(self.most, self.now)
        try:
            if self.held is not None:
                await self.held.wait()
            else:
                await asyncio.sleep(self.pause)
        finally:
            self.now -= 1
        return jpeg(size), "image/jpeg"


def relay_over(tmp_path, fronts: CountedFronts, clock: Clock | None = None) -> CoverRelay:
    clock = clock or Clock()
    return CoverRelay(KeptCovers(tmp_path / "covers", wall_clock=clock.wall_clock), fronts,
                      clock=clock.monotonic, wall_clock=clock.wall_clock)


async def settled(relay: CoverRelay) -> None:
    await asyncio.gather(*list(relay._flights.values()), return_exceptions=True)


def test_at_most_six_fronts_are_asked_of_the_archive_at_once(tmp_path):
    """A Search list of twenty new covers: every one answered, never more than FETCHING_AT_ONCE asking at once."""
    assert C.FETCHING_AT_ONCE == 6
    fronts = CountedFronts(pause=0.02)
    relay = relay_over(tmp_path, fronts)

    async def twenty():
        return await asyncio.gather(*(relay.answer("release", mbid_of(n), "250") for n in range(20)))

    answers = asyncio.run(twenty())

    assert [answer.status for answer in answers] == [200] * 20
    assert len(fronts.asked) == 20
    assert fronts.most == C.FETCHING_AT_ONCE


def test_the_wait_for_a_turn_isnt_part_of_the_fetchs_deadline(env, monkeypatch):
    """Two turns and six covers through the real client, each fetch 0.15 s (three hops) under a 0.3 s deadline: the
    last two wait 0.3 s for a turn and still come back - the deadline is the Archive's, never the queue's."""
    monkeypatch.setattr(C, "FETCHING_AT_ONCE", 2)
    monkeypatch.setattr(E, "FRONT_DEADLINE_SECONDS", 0.3)
    env.archive.delay = 0.05
    covers = [mbid_of(n) for n in range(6)]
    for mbid in covers:
        env.archive.releases[mbid] = 1
    relay = env.app.state.coverart

    async def six():
        return await asyncio.gather(*(relay.answer("release", mbid, "250") for mbid in covers))

    began = time.monotonic()
    answers = env.client.portal.call(six)

    assert [answer.status for answer in answers] == [200] * 6
    #? three rounds of two: the queue alone was longer than the deadline
    assert time.monotonic() - began >= 0.45
    assert len(env.archive.requests) == 18


def test_an_ask_past_the_pending_cap_is_a_502_at_once_and_asked_once_they_drain(tmp_path, monkeypatch):
    monkeypatch.setattr(C, "PENDING_MAX", 3)
    fronts = CountedFronts()
    relay = relay_over(tmp_path, fronts)

    async def go():
        fronts.hold()
        waiting = [asyncio.create_task(relay.answer("release", mbid_of(n), "250")) for n in range(3)]
        await asyncio.sleep(0.01)
        assert len(fronts.asked) == 3

        #? a fourth new cover: answered at once, the Archive not asked, nothing remembered of it
        began = time.monotonic()
        fourth = await relay.answer("release", mbid_of(3), "250")
        assert fourth.status == 502 and time.monotonic() - began < 0.5
        assert mbid_of(3) not in fronts.asked
        assert relay._failures == {} and relay._misses == {} and relay._down_until == 0.0
        #? one already under way is joined, not refused
        joined = asyncio.create_task(relay.answer("release", mbid_of(0), "250"))
        await asyncio.sleep(0.01)
        assert not joined.done()

        fronts.held.set()
        assert [answer.status for answer in await asyncio.gather(*waiting, joined)] == [200] * 4
        await settled(relay)

        #? drained: the fourth is asked as ever
        again = await relay.answer("release", mbid_of(3), "250")
        assert again.status == 200 and fronts.asked.count(mbid_of(3)) == 1

    asyncio.run(go())


def test_the_pending_cap_answers_502_through_the_route(env, monkeypatch):
    monkeypatch.setattr(C, "PENDING_MAX", 0)
    answer = cover(env)
    assert answer.status_code == 502 and answer.headers["cache-control"] == "no-store"
    assert env.archive.requests == []
    monkeypatch.setattr(C, "PENDING_MAX", 64)
    assert cover(env).status_code == 200


def test_a_kept_covers_refresh_counts_against_the_pending_cap_and_is_still_served_at_once(tmp_path, monkeypatch):
    monkeypatch.setattr(C, "PENDING_MAX", 1)
    clock = Clock()
    fronts = CountedFronts()
    relay = relay_over(tmp_path, fronts, clock)

    async def go():
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        clock.wall += C.FRESH_SECONDS + 60
        fronts.hold()

        #? the old cover at once, its refresh under way behind it
        began = time.monotonic()
        kept = await relay.answer("release", mbid_of(1), "250")
        assert kept.status == 200 and kept.front.data == jpeg("250")
        assert time.monotonic() - began < 0.5
        await asyncio.sleep(0.01)
        assert fronts.asked == [mbid_of(1), mbid_of(1)]

        #? the refresh fills the cap: a new cover is a 502 at once...
        assert (await relay.answer("release", mbid_of(2), "250")).status == 502
        #? ...and the kept one is still served, its refresh not started twice
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        assert fronts.asked == [mbid_of(1), mbid_of(1)]

        fronts.held.set()
        await settled(relay)
        assert (await relay.answer("release", mbid_of(2), "250")).status == 200

    asyncio.run(go())


def test_a_kept_cover_with_no_room_for_its_refresh_is_served_and_refreshed_later(tmp_path, monkeypatch):
    monkeypatch.setattr(C, "PENDING_MAX", 1)
    clock = Clock()
    fronts = CountedFronts()
    relay = relay_over(tmp_path, fronts, clock)

    async def go():
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        clock.wall += C.FRESH_SECONDS + 60
        fronts.hold()
        busy = asyncio.create_task(relay.answer("release", mbid_of(2), "250"))
        await asyncio.sleep(0.01)

        #? the cap is full: the old cover at once, no refresh started
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        assert fronts.asked == [mbid_of(1), mbid_of(2)]

        fronts.held.set()
        await busy
        await settled(relay)
        fronts.held = None
        #? room again: the next ask starts its refresh
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        await settled(relay)
        assert fronts.asked == [mbid_of(1), mbid_of(2), mbid_of(1)]

    asyncio.run(go())


def test_a_kept_covers_refresh_takes_a_turn_at_the_archive(tmp_path, monkeypatch):
    monkeypatch.setattr(C, "FETCHING_AT_ONCE", 1)
    clock = Clock()
    fronts = CountedFronts()
    relay = relay_over(tmp_path, fronts, clock)

    async def go():
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        clock.wall += C.FRESH_SECONDS + 60
        fronts.hold()
        assert (await relay.answer("release", mbid_of(1), "250")).status == 200
        await asyncio.sleep(0.01)

        #? the refresh holds the one turn: a new cover waits for it, not asked yet
        waiting = asyncio.create_task(relay.answer("release", mbid_of(2), "250"))
        await asyncio.sleep(0.02)
        assert fronts.asked == [mbid_of(1), mbid_of(1)] and fronts.most == 1

        fronts.held.set()
        assert (await waiting).status == 200
        assert fronts.asked == [mbid_of(1), mbid_of(1), mbid_of(2)] and fronts.most == 1

    asyncio.run(go())


# ----------------------------------------------------------------- kept on disk

def test_a_cover_is_kept_and_served_from_disk_without_asking(env):
    assert cover(env).status_code == 200
    asked = len(env.archive.requests)

    #? the folder of deadwax's own beside the player's, private to it
    assert env.folder == env.base / "deadwax-covers"
    assert stat.S_IMODE(os.lstat(env.folder).st_mode) == 0o700
    assert kept_names(env) == [f"release_{RELEASE}_250.jpg"]
    assert (env.folder / f"release_{RELEASE}_250.jpg").read_bytes() == jpeg("250")

    answer = cover(env)
    assert answer.status_code == 200 and answer.content == jpeg("250")
    assert answer.headers["etag"] == Front(jpeg("250"), "image/jpeg").etag
    assert len(env.archive.requests) == asked


def test_a_kept_cover_outlives_a_restart(env):
    assert cover(env, "release-group", GROUP, size="1200").status_code == 200
    asked = len(env.archive.requests)
    restart(env)

    answer = cover(env, "release-group", GROUP, size="1200")
    assert answer.status_code == 200 and answer.content == jpeg("1200")
    assert len(env.archive.requests) == asked


def test_each_kind_and_size_is_kept_apart(env):
    for kind, mbid, size in (("release", RELEASE, "250"), ("release", RELEASE, "500"),
                             ("release-group", GROUP, "250")):
        assert cover(env, kind, mbid, size=size).status_code == 200
    assert kept_names(env) == [f"release-group_{GROUP}_250.jpg", f"release_{RELEASE}_250.jpg",
                               f"release_{RELEASE}_500.jpg"]


def test_a_kept_cover_too_old_is_answered_at_once_and_refreshed_behind_it(env):
    assert cover(env).status_code == 200
    asked = len(env.archive.requests)
    env.archive.releases[RELEASE] = 2      # an editor uploaded a better front
    env.clock.wall += C.FRESH_SECONDS + 60

    #? the kept one, at once...
    answer = cover(env)
    assert answer.content == jpeg("250", 1)
    settle(env)
    assert len(env.archive.requests) == asked + 3

    #? ...and the new one from then on, kept
    assert cover(env).content == jpeg("250", 2)
    assert (env.folder / f"release_{RELEASE}_250.jpg").read_bytes() == jpeg("250", 2)
    assert len(env.archive.requests) == asked + 3


def test_an_old_kept_cover_the_archive_no_longer_has_is_dropped(env):
    assert cover(env).status_code == 200
    del env.archive.releases[RELEASE]
    env.clock.wall += C.FRESH_SECONDS + 60

    assert cover(env).status_code == 200
    settle(env)
    assert kept_names(env) == []
    assert cover(env).status_code == 404


def test_an_old_kept_cover_stays_when_its_refresh_fails(env):
    assert cover(env).status_code == 200
    env.archive.instead = lambda request: httpx.Response(503)
    env.clock.wall += C.FRESH_SECONDS + 60

    assert cover(env).status_code == 200
    settle(env)
    assert kept_names(env) == [f"release_{RELEASE}_250.jpg"]
    assert cover(env).content == jpeg("250")


def test_a_folder_that_cant_be_used_only_means_asking_each_time(env, tmp_path, monkeypatch):
    blocker = tmp_path / "a file"
    blocker.write_text("not a folder")
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(blocker))
    restart(env)

    assert cover(env).status_code == 200
    assert cover(env).status_code == 200
    assert len(env.archive.requests) == 6


def test_a_disk_that_fails_costs_the_keeping_never_the_cover(env, monkeypatch):
    def failing(*_):
        raise OSError(5, "Input/output error")

    monkeypatch.setattr(KeptCovers, "get", failing)
    monkeypatch.setattr(KeptCovers, "put", failing)
    answer = cover(env)
    assert answer.status_code == 200 and answer.content == jpeg("250")


def test_a_folder_that_cant_be_listed_is_read_as_empty(tmp_path, monkeypatch):
    kept = KeptCovers(tmp_path / "covers")
    real = os.scandir

    def refused(path):
        if Path(path) == tmp_path / "covers":
            raise PermissionError(13, "Permission denied")
        return real(path)

    monkeypatch.setattr(os, "scandir", refused)
    assert kept.get(key(1)) is None
    assert kept.put(key(1), front(1))
    assert kept.get(key(1))[0] == front(1)


def test_the_folder_is_refused_when_it_isnt_deadwaxs_own(env):
    """A folder of that name open to others (a /tmp somebody else made it in) is never used, as the player's isn't."""
    env.folder.mkdir(mode=0o755)
    os.chmod(env.folder, 0o755)

    assert cover(env).status_code == 200
    assert os.listdir(env.folder) == []


def test_the_player_caches_folder_is_left_alone(env):
    (env.base / "deadwax-player").mkdir(mode=0o700)
    assert cover(env).status_code == 200
    assert os.listdir(env.base / "deadwax-player") == []


# ----------------------------------------------------------------- the bound

def front(n: int, size: int = 1000) -> Front:
    return Front(bytes([n]) * size, "image/jpeg")


def key(n: int) -> tuple[str, str, str]:
    return ("release", f"{n:08x}-0000-4000-8000-000000000000", "250")


def test_the_disk_cache_keeps_to_its_cap_the_covers_served_longest_ago_going_first(tmp_path):
    kept = KeptCovers(tmp_path / "covers", max_bytes=3500)
    for n in (1, 2, 3):
        assert kept.put(key(n), front(n))
    assert kept.total == 3000

    #? 2 served: 1 is now the one served longest ago, then 3
    assert kept.get(key(2))[0] == front(2)
    assert kept.put(key(4), front(4))

    #? past 3500, trimmed to under 90% of it (3150): 1 goes
    assert kept.total == 3000
    assert kept.get(key(1)) is None
    assert sorted(os.listdir(tmp_path / "covers")) == sorted(f"{C.stem_of(key(n))}.jpg" for n in (2, 3, 4))

    #? the next goes past it again: 3, served before 2 was, goes - never 5, the one just put
    assert kept.put(key(5), front(5))
    assert kept.total == 3000
    assert kept.get(key(3)) is None
    assert [kept.get(key(n))[0] for n in (2, 4, 5)] == [front(2), front(4), front(5)]
    assert sorted(os.listdir(tmp_path / "covers")) == sorted(f"{C.stem_of(key(n))}.jpg" for n in (2, 4, 5))


def test_the_cover_just_put_is_never_trimmed(tmp_path):
    kept = KeptCovers(tmp_path / "covers", max_bytes=1500)
    assert kept.put(key(1), front(1))
    assert kept.put(key(2), front(2, 1400))
    assert kept.get(key(1)) is None and kept.get(key(2))[0] == front(2, 1400)


def test_a_cover_bigger_than_the_cap_alone_isnt_kept(tmp_path):
    kept = KeptCovers(tmp_path / "covers", max_bytes=500)
    assert not kept.put(key(1), front(1))
    assert kept.total == 0 and os.listdir(tmp_path / "covers") == []


def test_the_bound_counts_what_a_start_finds(tmp_path):
    folder = tmp_path / "covers"
    first = KeptCovers(folder, max_bytes=10_000)
    for n in (1, 2, 3):
        first.put(key(n), front(n))
    #? the oldest fetched first, after a start
    os.utime(folder / f"{C.stem_of(key(1))}.jpg", (1, 1))

    later = KeptCovers(folder, max_bytes=2500)
    assert later.get(key(2))[0] == front(2)
    assert later.total <= 2250
    assert later.get(key(1)) is None


def test_a_start_clears_what_a_stopped_write_left_and_ignores_what_isnt_a_cover(tmp_path):
    folder = tmp_path / "covers"
    folder.mkdir(mode=0o700)
    os.chmod(folder, 0o700)
    old_part = folder / ".release_x.jpg.abcd.part"
    old_part.write_bytes(b"half")
    os.utime(old_part, (1, 1))
    new_part = folder / ".release_y.jpg.abcd.part"
    new_part.write_bytes(b"being written")
    (folder / "notes.txt").write_text("someone's")

    kept = KeptCovers(folder)
    assert kept.get(key(1)) is None
    assert sorted(os.listdir(folder)) == [".release_y.jpg.abcd.part", "notes.txt"]
    assert kept.total == 0


def test_a_kept_cover_gone_from_under_it_is_fetched_again(env):
    assert cover(env).status_code == 200
    os.unlink(env.folder / f"release_{RELEASE}_250.jpg")

    assert cover(env).status_code == 200
    assert len(env.archive.requests) == 6
    assert kept_names(env) == [f"release_{RELEASE}_250.jpg"]


def test_a_link_in_the_folder_is_never_served(env, tmp_path):
    assert cover(env).status_code == 200
    secret = tmp_path / "secret.jpg"
    secret.write_bytes(b"\xff\xd8 not yours" * 100)
    name = env.folder / f"release_{RELEASE}_250.jpg"
    os.unlink(name)
    os.symlink(secret, name)

    answer = cover(env)
    assert answer.status_code == 200 and answer.content == jpeg("250")


# ----------------------------------------------------------------- headers

def test_an_etag_the_phone_holds_is_a_304_with_no_body(env):
    first = cover(env)
    etag = first.headers["etag"]

    for header in (etag, f"W/{etag}", f'"other", {etag}', "*"):
        again = env.client.get(f"/deadwax/coverart/release/{RELEASE}", headers={"If-None-Match": header})
        assert again.status_code == 304, header
        assert again.content == b"" and again.headers["etag"] == etag
        assert again.headers["cache-control"] == route.COVER_CACHE

    assert env.client.get(f"/deadwax/coverart/release/{RELEASE}",
                          headers={"If-None-Match": '"other"'}).status_code == 200


def test_covers_go_out_under_the_media_guard_and_are_never_gzipped(env):
    assert serves_media(f"/deadwax/coverart/release/{RELEASE}")
    answer = env.client.get(f"/deadwax/coverart/release/{RELEASE}", headers={"Accept-Encoding": "gzip"})

    assert answer.status_code == 200
    assert answer.headers["x-content-type-options"] == "nosniff"
    assert "sandbox" in answer.headers["content-security-policy"]
    assert "content-encoding" not in answer.headers
    assert answer.headers["content-length"] == str(len(jpeg("250")))
