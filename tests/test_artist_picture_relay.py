"""
The artist pictures' relay for the iPhone app (2.1.32, Phase 8's server change B) - GET /deadwax/library/artist/picture
(src/routes/library.py) and src/api/artist_images_endpoint.py ArtistPictures - through the whole app, start(), with an
httpx MockTransport for the picture hosts. The suite never calls out.

The fake hosts answer as the real ones were seen to on 2026-11-16 (by hand, with curl - not deadwax):
`commons.wikimedia.org/wiki/Special:FilePath/<file>?width=600` answers 302 to
`commons.wikimedia.org/w/index.php?title=Special:Redirect/file/<file>&width=600`, which answers 301 to
`thumb.wikimedia.org/wikipedia/commons/thumb/b/b6/<file>/960px-<file>` (a JPEG, 127 KB; an SVG's thumbnail a PNG) - or,
for a file no wider than asked, to `upload.wikimedia.org/wikipedia/commons/a/a9/<file>` as it is - each with a
utm_ query; the redirects typed text/html with no body. TheAudioDB's pictures are on `r2.theaudiodb.com` and answer
200 at once (a thumb 89 KB, a background 178 KB). fanart.tv's `assets.fanart.tv` was NOT seen (no project key here):
it answers as TheAudioDB's does, assumed.

What these hold: a preview of each source passed on, through Commons' own redirects; every preview the candidates
make on the hosts; fanart.tv's http:// pictures end to end, offered as https by the images preview, passed on, and
honoured by apply; an arbitrary host, http, a userinfo trick, an address by number, a port, a lookalike, an
unparseable address and too long a one refused with a 4xx before anything is asked; a redirect followed only within
the hosts, never off them, at most PICTURE_REDIRECTS; the cap, declared or streamed, and room under it for a 4K
background; the body asked for and taken undecoded (identity), an encoded answer refused unread; the deadline on the
whole fetch, under the phone's 8 s; a 404 or 410 a 404, a slow host a 504, a host away or in trouble a 502 said for
now, a refusal (403, off-list, not an image) a 502 said for good; at most PICTURES_AT_ONCE asked at once, a turn's wait
inside the deadline, past PICTURES_PENDING_MAX a 503 at once; nothing kept; the agent; GuardMedia's headers and no gzip;
the cache header. With logins off the implicit admin is let through; with logins on, the 401, the 403 without Edit
albums and an admin's 200 are in tests/test_logins.py, which decides the route (ROUTES, "edit").
"""

import asyncio
import gzip
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import quote, unquote

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import __version__  # noqa: E402
from src.api import artist_images_endpoint as E  # noqa: E402
from src.api.app import serves_media, start  # noqa: E402
from src.api.artist_images_endpoint import (ArtistPictures, PictureHostSlow, artist_pictures,  # noqa: E402
                                            image_user_agent, passes_on, picture_address)
from src.artists import (PREVIEW_WIDTH, commons_file_url, from_fanarttv, from_relations, from_theaudiodb,  # noqa: E402
                         from_wikidata)
from src.config import Config  # noqa: E402
from src.routes import library as route  # noqa: E402

ROUTE = "/deadwax/library/artist/picture"
PHOTO = "Felis catus-cat on snow.jpg"
SMALL = "Example.jpg"
LOGO = "Commons-logo.svg"
THEAUDIODB = "https://r2.theaudiodb.com/images/media/artist/thumb/uxrqxy1347913147.jpg"
FANARTTV = ("https://assets.fanart.tv/fanart/music/cc197bad-dc9c-440d-a5b5-d52ba2e14234/artistthumb/"
            "coldplay-5b4c1c0e8f6a1.jpg")
UTM = "utm_source=commons.wikimedia.org&utm_campaign=index&utm_content=thumbnail"
#? 16 MB of zeros gzipped twice: a few hundred bytes on the wire, twice the cap once inflated
BOMB = gzip.compress(gzip.compress(bytes(16 << 20)))
MEDIA_HEADERS = {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
    "cross-origin-resource-policy": "same-origin",
}


def jpeg(name: str) -> bytes:
    """A picture's bytes, different for each: a JPEG's start, then enough to be a real one's size."""
    return b"\xff\xd8\xff\xe0" + f"{name} ".encode() * 400


def png(name: str) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + f"{name} ".encode() * 400


class Hosts:
    """Commons, its two Wikimedia hosts, TheAudioDB's and fanart.tv's image hosts, as seen by hand (the module's
    docstring). `instead`, when set, answers everything; `gone` names hosts that answer 404; `delay` waits before each
    answer. Every request kept."""

    def __init__(self):
        self.instead = None
        self.gone: set[str] = set()
        self.delay = 0.0
        self.requests: list[httpx.Request] = []

    async def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.delay:
            await asyncio.sleep(self.delay)
        if self.instead is not None:
            return self.instead(request)
        host, path = request.url.host, request.url.path
        if host in self.gone:
            return httpx.Response(404, headers={"content-type": "text/html"}, text="<html>no such file</html>")
        if host == "commons.wikimedia.org" and path.startswith("/wiki/Special:FilePath/"):
            name = path[len("/wiki/Special:FilePath/"):]
            width = request.url.params.get("width", "")
            return httpx.Response(302, headers={
                "location": f"https://commons.wikimedia.org/w/index.php?title=Special:Redirect/file/{name}"
                            f"&width={width}",
                "content-type": "text/html; charset=UTF-8"})
        if host == "commons.wikimedia.org" and path == "/w/index.php":
            name = request.url.params["title"].removeprefix("Special:Redirect/file/")
            if unquote(name) == SMALL.replace(" ", "_"):
                location = f"https://upload.wikimedia.org/wikipedia/commons/a/a9/{name}?{UTM}_unscaled"
            else:
                served = f"960px-{name}" + (".png" if name.endswith(".svg") else "")
                location = f"https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b6/{name}/{served}?{UTM}"
            return httpx.Response(301, headers={"location": location, "content-type": "text/html; charset=UTF-8"})
        if host == "thumb.wikimedia.org" and path.startswith("/wikipedia/commons/thumb/"):
            if path.endswith(".png"):
                return httpx.Response(200, headers={"content-type": "image/png"}, content=png(path))
            return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=jpeg(path))
        if host == "upload.wikimedia.org" and path.startswith("/wikipedia/commons/"):
            return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=jpeg(path))
        if host in ("r2.theaudiodb.com", "assets.fanart.tv"):
            kind = "image/png" if path.endswith(".png") else "image/jpeg"
            return httpx.Response(200, headers={"content-type": kind},
                                  content=png(path) if kind == "image/png" else jpeg(path))
        return httpx.Response(404, headers={"content-type": "text/html"}, text="<html>not here</html>")

    def hosts(self) -> list[str]:
        return [request.url.host for request in self.requests]


@asynccontextmanager
async def no_lifespan(app):
    #? nothing connects: no slskd, no poller - one event loop for the whole test
    yield


@pytest.fixture
def env(tmp_path, monkeypatch):
    hosts = Hosts()
    #? nothing is kept: a folder it could have used, watched
    cache = tmp_path / "cache"
    cache.mkdir()
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(cache))
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "")
    monkeypatch.setattr(Config, "MUSICBRAINZ_USERAGENT", "")
    artist_pictures._client = httpx.AsyncClient(transport=httpx.MockTransport(hosts.handle), follow_redirects=False)
    app = start()
    app.router.lifespan_context = no_lifespan
    with TestClient(app) as client:
        yield SimpleNamespace(hosts=hosts, app=app, client=client, cache=cache, tmp=tmp_path)
    asyncio.run(artist_pictures.close_client())


def picture(env, url: str, headers: dict | None = None) -> httpx.Response:
    return env.client.get(ROUTE, params={"url": url}, headers=headers)


def answers(status: int, **headers):
    return lambda request: httpx.Response(status, headers=headers)


def raises(error: Exception):
    """A host that answers nothing: the request fails as `error`."""
    def answer(request):
        raise error
    return answer


# ----------------------------------------------------------------- each source's preview

def test_a_commons_preview_is_fetched_through_commons_own_redirects_and_passed_on(env):
    url = commons_file_url(PHOTO, PREVIEW_WIDTH)
    answer = picture(env, url)

    assert answer.status_code == 200
    assert answer.headers["content-type"] == "image/jpeg"
    assert answer.content.startswith(b"\xff\xd8\xff")
    assert answer.headers["cache-control"] == route.PICTURE_CACHE
    #? Special:FilePath, Special:Redirect, the thumbnail - each hop checked and followed by hand
    assert env.hosts.hosts() == ["commons.wikimedia.org", "commons.wikimedia.org", "thumb.wikimedia.org"]
    assert str(env.hosts.requests[0].url) == url
    #? the agent the image sources are sent elsewhere: deadwax and its version, no contact without one
    assert all(request.headers["user-agent"] == f"deadwax/{__version__}" for request in env.hosts.requests)


def test_a_commons_file_no_wider_than_asked_comes_from_upload(env):
    answer = picture(env, commons_file_url(SMALL, PREVIEW_WIDTH))

    assert answer.status_code == 200 and answer.headers["content-type"] == "image/jpeg"
    assert env.hosts.hosts() == ["commons.wikimedia.org", "commons.wikimedia.org", "upload.wikimedia.org"]


def test_a_commons_svg_logo_comes_back_as_its_png_thumbnail(env):
    answer = picture(env, commons_file_url(LOGO, PREVIEW_WIDTH))

    assert answer.status_code == 200 and answer.headers["content-type"] == "image/png"
    assert env.hosts.hosts()[-1] == "thumb.wikimedia.org"


@pytest.mark.parametrize("candidate", [
    from_theaudiodb({"strArtistThumb": THEAUDIODB})[0],
    from_fanarttv({"artistthumb": [{"url": FANARTTV, "likes": "3"}]})[0],
], ids=["theaudiodb", "fanarttv"])
def test_theaudiodb_and_fanarttv_previews_are_the_pictures_themselves_asked_once(env, candidate):
    assert candidate["preview"] == candidate["url"]
    answer = picture(env, candidate["preview"])

    assert answer.status_code == 200 and answer.headers["content-type"] == "image/jpeg"
    assert [str(request.url) for request in env.hosts.requests] == [candidate["preview"]]


def test_every_preview_the_candidates_make_is_one_the_relay_asks():
    """Commons' previews are made by commons_file_url (always commons.wikimedia.org); TheAudioDB's and fanart.tv's are
    their payloads' own addresses - the hosts seen (TheAudioDB) and documented (fanart.tv)."""
    relations = [{"type": "image", "url": {"resource": "https://commons.wikimedia.org/wiki/File:Pink_Floyd%2C_1971.jpg"}},
                 {"type": "image", "url": {"resource": "https://commons.m.wikimedia.org/wiki/File:A_band.jpg"}}]
    entity = {"claims": {"P18": [{"mainsnak": {"datavalue": {"value": "Thom Yorke 2010.jpg"}}}],
                         "P154": [{"mainsnak": {"datavalue": {"value": "Radiohead logo.svg"}}}]}}
    row = {field: f"https://r2.theaudiodb.com/images/media/artist/{kind}/abc123.jpg"
           for field, kind in (("strArtistThumb", "thumb"), ("strArtistBanner", "banner"),
                               ("strArtistFanart", "fanart"), ("strArtistLogo", "logo"),
                               ("strArtistClearart", "clearart"), ("strArtistWideThumb", "widethumb"),
                               ("strArtistCutout", "cutout"))}
    art = {field: [{"url": f"https://assets.fanart.tv/fanart/music/x/{field}/a.jpg", "likes": "1"}]
           for field in ("artistthumb", "musicbanner", "artistbackground", "artist4kbackground", "hdmusiclogo",
                         "musiclogo")}
    candidates = from_relations(relations) + from_wikidata(entity) + from_theaudiodb(row) + from_fanarttv(art)

    assert len(candidates) == 2 + 2 + 7 + 6
    for candidate in candidates:
        assert picture_address(candidate["preview"]) is not None, candidate["preview"]


def test_fanarttvs_http_pictures_go_from_the_preview_through_the_relay_to_apply(env, monkeypatch):
    """The review's: fanart.tv's v3 API names its pictures http://assets.fanart.tv/..., which the relay refuses. End to
    end: the images preview offers them as https (artists.fanarttv_https), the relay passes each on, and apply honours
    that same address as a choice and fetches it over https."""
    from tests.test_artists import ARTIST, seed_artist

    mbid = "cc197bad-dc9c-440d-a5b5-d52ba2e14234"
    library = env.tmp / "library"
    folder = seed_artist(library)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(library))
    monkeypatch.setattr(Config, "FANARTTV_KEY", "a-project-key")
    monkeypatch.setattr(Config, "FANARTTV_PERSONAL_KEY", None)
    monkeypatch.setattr(Config, "THEAUDIODB_KEY", None)

    async def get_artist(asked):
        return {"id": asked, "name": ARTIST, "relations": []}

    env.app.state.musicbrainz_client = SimpleNamespace(get_artist=get_artist)
    sources = []

    def fanarttv(request: httpx.Request) -> httpx.Response:
        sources.append(str(request.url))
        if request.url.host == "webservice.fanart.tv":
            return httpx.Response(200, json={
                "artistthumb": [{"url": f"http://assets.fanart.tv/fanart/music/{mbid}/artistthumb/a.jpg", "likes": "3"}],
                "musicbanner": [{"url": f"http://assets.fanart.tv/fanart/music/{mbid}/musicbanner/b.jpg"}],
            })
        if str(request.url).startswith("https://assets.fanart.tv/"):
            return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=jpeg("saved"))
        return httpx.Response(404)

    monkeypatch.setattr(route.artist_images_client, "_client",
                        httpx.AsyncClient(transport=httpx.MockTransport(fanarttv), follow_redirects=True))

    preview = env.client.post("/deadwax/library/artist/images/preview", json={"artist": ARTIST, "artist_mbid": mbid})
    assert preview.status_code == 200
    candidates = preview.json()["candidates"]
    assert [c["preview"] for c in candidates] == [
        f"https://assets.fanart.tv/fanart/music/{mbid}/artistthumb/a.jpg",
        f"https://assets.fanart.tv/fanart/music/{mbid}/musicbanner/b.jpg"]

    for candidate in candidates:
        assert candidate["url"] == candidate["preview"]
        answer = picture(env, candidate["preview"])
        assert answer.status_code == 200 and answer.headers["content-type"] == "image/jpeg"
    assert [str(request.url) for request in env.hosts.requests] == [c["preview"] for c in candidates]

    applied = env.client.post("/deadwax/library/artist/images/apply",
                              json={"artist": ARTIST, "artist_mbid": mbid, "choices": {"thumb": candidates[0]["url"]}})
    assert applied.status_code == 200
    assert applied.json()["results"]["written"] == ["artist.jpg"]
    assert (folder / "artist.jpg").read_bytes() == jpeg("saved")
    assert sources[-1] == candidates[0]["url"]


def test_the_contact_is_sent_when_there_is_one(env, monkeypatch):
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "someone@example.com")
    assert picture(env, THEAUDIODB).status_code == 200
    agent = env.hosts.requests[0].headers["user-agent"]
    assert __version__ in agent and "someone@example.com" in agent
    #? the one the artist images client sends the same hosts
    assert agent == image_user_agent()


# ----------------------------------------------------------------- not a general proxy

@pytest.mark.parametrize("url", [
    "https://example.com/picture.jpg",                                 # an arbitrary host
    "https://evil.example/wiki/Special:FilePath/A.jpg",
    "http://commons.wikimedia.org/wiki/Special:FilePath/A.jpg",        # http
    "http://r2.theaudiodb.com/images/media/artist/thumb/a.jpg",
    "http://assets.fanart.tv/fanart/music/x/artistthumb/a.jpg",
    "https://commons.wikimedia.org@evil.example/",                     # the userinfo trick
    "https://commons.wikimedia.org%2F@evil.example/",
    "https://evil.example\\@commons.wikimedia.org/",                   # backslash: a user to httpx, refused as one
    "https://user:pw@commons.wikimedia.org/wiki/Special:FilePath/A.jpg",
    "https://user@r2.theaudiodb.com/a.jpg",
    "https://1.2.3.4/picture.jpg",                                     # addresses by number
    "https://127.0.0.1/picture.jpg",
    "https://169.254.169.254/latest/meta-data/",
    "https://[::1]/picture.jpg",
    "https://0x7f.1/picture.jpg",
    "https://2130706433/picture.jpg",
    "https://commons.wikimedia.org:8443/wiki/Special:FilePath/A.jpg",  # a port
    "https://r2.theaudiodb.com:80/a.jpg",
    "https://commons.wikimedia.org./wiki/Special:FilePath/A.jpg",      # lookalikes
    "https://evil.commons.wikimedia.org/a.jpg",
    "https://commons.wikimedia.org.evil.example/a.jpg",
    "https://xcommons.wikimedia.org/a.jpg",
    "https://wikimedia.org/a.jpg",
    "https://commöns.wikimedia.org/a.jpg",
    "https://commons.m.wikimedia.org/wiki/Special:FilePath/A.jpg",     # a relation's host, never a preview's
    "https://webservice.fanart.tv/v3/music/x",                         # the sources' API hosts, not their pictures
    "https://www.theaudiodb.com/images/media/artist/thumb/a.jpg",
    "https://fanart.tv/a.jpg",
    "https://www.wikidata.org/wiki/Special:EntityData/Q1.json",
    "file:///etc/passwd",                                              # not https at all
    "ftp://commons.wikimedia.org/a.jpg",
    "data:image/png;base64,iVBORw0KGgo=",
    "javascript:alert(1)",
    "//commons.wikimedia.org/wiki/Special:FilePath/A.jpg",
    "commons.wikimedia.org/wiki/Special:FilePath/A.jpg",
    "https:commons.wikimedia.org/a.jpg",
    " https://commons.wikimedia.org/a.jpg",
    "https://commons.wikimedia.org\t/a.jpg",                           # unparseable
    "https://xn--commons-.wikimedia.org/a.jpg",
    "",
])
def test_an_address_off_the_hosts_is_refused_before_anything_is_asked(env, url):
    answer = picture(env, url)

    assert answer.status_code == 400, url
    assert answer.json()["detail"] == route.PICTURE_WORDS[400]
    assert answer.headers["cache-control"] == "no-store"
    assert env.hosts.requests == []


def test_no_address_or_too_long_a_one_is_refused_before_anything_is_asked(env):
    assert env.client.get(ROUTE).status_code == 422
    long = "https://commons.wikimedia.org/wiki/Special:FilePath/" + "a" * E.PICTURE_URL_MAX + ".jpg"
    assert picture(env, long).status_code == 422
    assert env.hosts.requests == []


def test_the_hosts_are_exactly_these():
    assert E.PICTURE_HOSTS == {"commons.wikimedia.org", "thumb.wikimedia.org", "upload.wikimedia.org",
                               "r2.theaudiodb.com", "assets.fanart.tv"}
    for url in ("https://commons.wikimedia.org/x", "https://thumb.wikimedia.org/x", "https://upload.wikimedia.org/x",
                "https://r2.theaudiodb.com/x", "https://assets.fanart.tv/x", "https://COMMONS.Wikimedia.org/x",
                "https://upload.wikimedia.org:443/x"):
        assert passes_on(httpx.URL(url)), url
    for url in ("http://commons.wikimedia.org/x", "https://a:b@upload.wikimedia.org/x", "https://1.2.3.4/x",
                "https://upload.wikimedia.org:444/x", "https://sub.thumb.wikimedia.org/x", "https://archive.org/x"):
        assert not passes_on(httpx.URL(url)), url


def test_the_client_checks_again_and_never_asks_an_address_off_the_hosts():
    """ArtistPictures.picture() refuses what picture_address() would have, so nothing reaches the network unchecked."""
    asked = []
    pictures = ArtistPictures()
    pictures._client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: asked.append(r) or httpx.Response(200)))

    async def ask():
        with pytest.raises(E.PictureRefused):
            await pictures.picture(httpx.URL("https://evil.example/a.jpg"))
        await pictures.close_client()

    asyncio.run(ask())
    assert asked == []


# ----------------------------------------------------------------- redirects

@pytest.mark.parametrize("location, host", [
    ("https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ab/A.jpg/960px-A.jpg", "thumb.wikimedia.org"),
    ("https://upload.wikimedia.org/wikipedia/commons/a/ab/A.jpg", "upload.wikimedia.org"),
    ("https://r2.theaudiodb.com/images/media/artist/thumb/a.jpg", "r2.theaudiodb.com"),
    ("https://assets.fanart.tv/fanart/music/x/artistthumb/a.jpg", "assets.fanart.tv"),
    #? relative to where it came from: still Commons
    ("/w/index.php?title=Special:Redirect/file/A.jpg&width=600", "commons.wikimedia.org"),
])
def test_a_redirect_within_the_hosts_is_followed(env, location, host):
    first = []

    def answer(request):
        if not first:
            first.append(request)
            return httpx.Response(302, headers={"location": location})
        return httpx.Response(200, headers={"content-type": "image/png"}, content=png("moved"))

    env.hosts.instead = answer
    got = picture(env, commons_file_url("A.jpg", PREVIEW_WIDTH))

    assert got.status_code == 200 and got.headers["content-type"] == "image/png"
    assert env.hosts.hosts() == ["commons.wikimedia.org", host]


@pytest.mark.parametrize("location", [
    "https://example.com/picture.jpg",
    "http://upload.wikimedia.org/wikipedia/commons/a/ab/A.jpg",       # down to http
    "http://thumb.wikimedia.org/a.jpg",
    "https://commons.wikimedia.org@evil.example/a.jpg",
    "https://user@upload.wikimedia.org/a.jpg",
    "https://127.0.0.1/a.jpg",
    "http://169.254.169.254/latest/meta-data/",
    "https://[::1]/a.jpg",
    "https://10.0.0.1:8080/a.jpg",
    "https://upload.wikimedia.org:8443/a.jpg",
    "https://upload.wikimedia.org.evil.example/a.jpg",
    "https://archive.org/download/x.jpg",                              # the cover relay's, not this one's
    "//evil.example/a.jpg",
    "file:///etc/passwd",
    "ftp://upload.wikimedia.org/a.jpg",
    "https://xn--commons-.wikimedia.org/a.jpg",                        # a name that can't be decoded
    "https://[::1/a.jpg",                                              # not an address at all
])
def test_a_redirect_off_the_hosts_is_refused_and_never_followed(env, location):
    env.hosts.instead = lambda request: httpx.Response(302, headers={"location": location})

    answer = picture(env, THEAUDIODB)

    assert answer.status_code == 502
    #? said for good: asking again gets the same
    assert answer.json()["detail"] == route.PICTURE_REFUSED_WORDS
    assert answer.headers["cache-control"] == "no-store"
    #? asked once, of the host named; the place it pointed at never
    assert env.hosts.hosts() == ["r2.theaudiodb.com"]


def test_a_chain_that_leaves_the_hosts_part_way_is_refused_there(env):
    """Commons' first hop is followed, and a second off the list isn't."""
    def answer(request):
        if request.url.path.startswith("/wiki/"):
            return httpx.Response(302, headers={"location": "/w/index.php?title=Special:Redirect/file/A.jpg"})
        return httpx.Response(301, headers={"location": "https://evil.example/A.jpg"})

    env.hosts.instead = answer

    assert picture(env, commons_file_url("A.jpg", PREVIEW_WIDTH)).status_code == 502
    assert env.hosts.hosts() == ["commons.wikimedia.org", "commons.wikimedia.org"]


def test_a_redirect_with_nowhere_to_go_is_refused(env):
    env.hosts.instead = answers(302)
    assert picture(env, THEAUDIODB).status_code == 502


def test_more_redirects_than_a_chain_needs_are_refused(env):
    env.hosts.instead = lambda request: httpx.Response(301, headers={"location": "https://upload.wikimedia.org/again"})

    assert picture(env, THEAUDIODB).status_code == 502
    assert len(env.hosts.requests) == E.PICTURE_REDIRECTS + 1
    #? Commons' own chain is two
    assert E.PICTURE_REDIRECTS >= 2


# ----------------------------------------------------------------- what comes back

@pytest.mark.parametrize("content_type", ["text/html; charset=utf-8", "image/svg+xml", "application/pdf",
                                          "application/octet-stream", "", "text/plain", "image/avif",
                                          "image/x-icon"])
def test_anything_but_an_image_deadwax_serves_is_refused(env, content_type):
    headers = {"content-type": content_type} if content_type else {}
    page = b"<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>" * 40
    env.hosts.instead = lambda request: httpx.Response(200, headers=headers, content=page)

    answer = picture(env, THEAUDIODB)

    assert answer.status_code == 502
    assert b"<script>" not in answer.content


@pytest.mark.parametrize("content_type", ["text/html; charset=UTF-8", "application/octet-stream", ""])
def test_an_answer_not_typed_as_an_image_is_refused_unread_whatever_its_bytes(env, content_type):
    """The declared type is checked before the body is read - so bytes that start like a JPEG don't make a page (or an
    untyped answer) a picture."""
    stream = Pieces([b"\xff\xd8\xff\xe0" + b"x" * 1000] * 3)
    headers = {"content-type": content_type} if content_type else {}
    env.hosts.instead = lambda request: httpx.Response(200, headers=headers, stream=stream)

    assert picture(env, THEAUDIODB).status_code == 502
    assert stream.taken == 0


@pytest.mark.parametrize("content_type", ["image/jpeg", "image/png", "image/gif", "image/webp"])
def test_each_image_type_is_passed_on_as_it_is(env, content_type):
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": content_type},
                                                       content=b"pixels" * 500)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 200 and answer.headers["content-type"] == content_type


def test_an_image_labelled_oddly_is_served_by_its_registered_name(env):
    """served_image_type: `image/jpg` is what files commonly say for image/jpeg."""
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpg"}, content=jpeg("odd"))
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 200 and answer.headers["content-type"] == "image/jpeg"


def test_an_empty_answer_is_refused(env):
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"}, content=b"")
    assert picture(env, THEAUDIODB).status_code == 502


class Pieces(httpx.AsyncByteStream):
    """A body sent a piece at a time, counting the pieces deadwax took."""

    def __init__(self, pieces: list[bytes]):
        self.pieces, self.taken = pieces, 0

    async def __aiter__(self):
        for piece in self.pieces:
            self.taken += 1
            yield piece


def test_a_body_declared_past_the_cap_is_refused_unread(env, monkeypatch):
    monkeypatch.setattr(E, "PICTURE_MAX_BYTES", 10_000)
    stream = Pieces([b"x" * 1000] * 20)
    env.hosts.instead = lambda request: httpx.Response(
        200, headers={"content-type": "image/jpeg", "content-length": "20000"}, stream=stream)

    assert picture(env, THEAUDIODB).status_code == 502
    assert stream.taken == 0


def test_a_body_that_runs_past_the_cap_is_refused_as_soon_as_it_does(env, monkeypatch):
    monkeypatch.setattr(E, "PICTURE_MAX_BYTES", 10_000)
    stream = Pieces([b"x" * 1000] * 50)
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"}, stream=stream)

    assert picture(env, THEAUDIODB).status_code == 502
    #? the eleventh piece passes the cap: nothing after it is read
    assert stream.taken == 11


def test_a_body_at_the_cap_is_passed_on(env, monkeypatch):
    monkeypatch.setattr(E, "PICTURE_MAX_BYTES", 10_000)
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"},
                                                       stream=Pieces([b"\xff\xd8\xff" + b"x" * 997] * 10))
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 200 and len(answer.content) == 10_000


def test_every_hop_asks_for_the_picture_as_it_is(env):
    """Accept-Encoding: identity - httpx asks for gzip unless told otherwise."""
    assert picture(env, commons_file_url(PHOTO, PREVIEW_WIDTH)).status_code == 200
    assert len(env.hosts.requests) == 3
    assert all(request.headers["accept-encoding"] == "identity" for request in env.hosts.requests)


@pytest.mark.parametrize("encoding", ["gzip", "gzip, gzip", "x-gzip", "deflate", "br", "zstd", "compress", "GZIP"])
def test_an_answer_encoded_anyway_is_refused_unread(env, encoding):
    """The review's bomb: 269 bytes of nested gzip inflated to 141 MB before the cap could count it. Asked for as it
    is, an answer encoded anyway is refused before its body is read."""
    stream = Pieces([BOMB])
    env.hosts.instead = lambda request: httpx.Response(
        200, headers={"content-type": "image/jpeg", "content-encoding": encoding}, stream=stream)

    answer = picture(env, THEAUDIODB)

    assert answer.status_code == 502 and answer.json()["detail"] == route.PICTURE_REFUSED_WORDS
    assert stream.taken == 0


@pytest.mark.parametrize("encoding", ["identity", "Identity ", ""])
def test_an_answer_sent_as_it_is_is_passed_on(env, encoding):
    env.hosts.instead = lambda request: httpx.Response(
        200, headers={"content-type": "image/jpeg", "content-encoding": encoding}, content=jpeg("plain"))
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 200 and answer.content == jpeg("plain")


def test_the_bytes_counted_are_the_bytes_sent(env, monkeypatch):
    """Read raw: a body is never decoded on its way through, so what passed the cap is exactly what goes out."""
    monkeypatch.setattr(E, "PICTURE_MAX_BYTES", 10_000)
    small = gzip.compress(b"\xff\xd8\xff" + bytes(50_000))
    assert len(small) < 10_000
    #? an answer that says nothing of an encoding is passed on as its bytes, never inflated
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"}, content=small)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 200 and answer.content == small


def test_the_cap_has_room_for_a_4k_background_and_not_much_more(env):
    """fanart.tv's preview is the picture itself, and it offers 4K backgrounds: a few MB each."""
    assert E.PICTURE_MAX_BYTES == 8 << 20
    background = b"\xff\xd8\xff\xe0" + bytes(6 << 20)
    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"}, content=background)

    answer = picture(env, FANARTTV)
    assert answer.status_code == 200 and len(answer.content) == len(background)

    env.hosts.instead = lambda request: httpx.Response(200, headers={"content-type": "image/jpeg"},
                                                       content=bytes(E.PICTURE_MAX_BYTES + 1))
    assert picture(env, FANARTTV).status_code == 502


# ----------------------------------------------------------------- missing, slow, down

def test_a_404_stays_a_404(env):
    env.hosts.instead = lambda request: httpx.Response(404, headers={"content-type": "text/html"}, text="<p>gone</p>")

    answer = picture(env, THEAUDIODB)

    assert answer.status_code == 404
    assert answer.json()["detail"] == route.PICTURE_WORDS[404]
    assert answer.headers["cache-control"] == "no-store"


def test_a_404_at_the_end_of_commons_chain_is_a_404(env):
    env.hosts.gone.add("thumb.wikimedia.org")

    assert picture(env, commons_file_url(PHOTO, PREVIEW_WIDTH)).status_code == 404
    assert env.hosts.hosts() == ["commons.wikimedia.org", "commons.wikimedia.org", "thumb.wikimedia.org"]


@pytest.mark.parametrize("status", [429, 500, 502, 503])
def test_a_host_in_trouble_is_a_502(env, status):
    env.hosts.instead = answers(status)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 502 and answer.json()["detail"] == route.PICTURE_WORDS[502]


def test_a_410_is_a_404_too(env):
    env.hosts.instead = answers(410)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 404 and answer.json()["detail"] == route.PICTURE_WORDS[404]


def test_a_403_is_a_502_said_for_good(env):
    """Wikimedia's robot policy, for an address that resolved to an original: asking again gets the same, so the words
    don't say "just now"."""
    env.hosts.instead = answers(403)
    answer = picture(env, commons_file_url(PHOTO, PREVIEW_WIDTH))

    assert answer.status_code == 502
    assert answer.json()["detail"] == route.PICTURE_REFUSED_WORDS
    assert "just now" not in route.PICTURE_REFUSED_WORDS and "just now" in route.PICTURE_WORDS[502]


@pytest.mark.parametrize("status", [400, 401, 403, 418])
def test_another_status_is_refused(env, status):
    env.hosts.instead = answers(status)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 502 and answer.json()["detail"] == route.PICTURE_REFUSED_WORDS


@pytest.mark.parametrize("error", [httpx.ConnectError("connection refused"),
                                   httpx.RemoteProtocolError("Server disconnected without sending a response.")])
def test_a_host_that_cant_be_reached_is_a_502_said_for_now(env, error):
    env.hosts.instead = raises(error)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 502 and answer.headers["cache-control"] == "no-store"
    assert answer.json()["detail"] == route.PICTURE_WORDS[502]


@pytest.mark.parametrize("error", [httpx.ConnectTimeout("connect"), httpx.ReadTimeout("read")])
def test_a_host_that_times_out_is_a_504(env, error):
    env.hosts.instead = raises(error)
    answer = picture(env, THEAUDIODB)
    assert answer.status_code == 504 and answer.json()["detail"] == route.PICTURE_WORDS[504]


def test_the_whole_fetch_has_a_deadline_and_a_slow_host_is_a_504(env, monkeypatch):
    monkeypatch.setattr(E, "PICTURE_DEADLINE_SECONDS", 0.2)
    env.hosts.delay = 0.08   # each hop is quick enough; Commons' three together aren't

    began = time.monotonic()
    answer = picture(env, commons_file_url(PHOTO, PREVIEW_WIDTH))

    assert answer.status_code == 504
    assert answer.json()["detail"] == route.PICTURE_WORDS[504]
    assert answer.headers["cache-control"] == "no-store"
    assert time.monotonic() - began < 2
    #? the third hop was asked and cut off before it answered
    assert env.hosts.hosts() == ["commons.wikimedia.org", "commons.wikimedia.org", "thumb.wikimedia.org"]


def test_the_deadline_is_under_the_phones_eight_seconds():
    """Nothing carries on past the ask, so the deadline is what the phone waits: under URLSessionTransport's 8 s."""
    assert E.PICTURE_DEADLINE_SECONDS < 8
    assert E.PICTURE_TIMEOUT.connect < E.PICTURE_DEADLINE_SECONDS


# ----------------------------------------------------------------- bounded, and nothing kept

class Counting:
    """A host that answers after `delay`, counting how many it is answering at once."""

    def __init__(self, delay: float):
        self.delay, self.now, self.most, self.asked = delay, 0, 0, 0

    async def handle(self, request: httpx.Request) -> httpx.Response:
        self.asked += 1
        self.now += 1
        self.most = max(self.most, self.now)
        try:
            await asyncio.sleep(self.delay)
        finally:
            self.now -= 1
        return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=jpeg(request.url.path))


def test_at_most_six_pictures_are_asked_at_once():
    """A picker's grid of twenty previews: every one answered, never more than PICTURES_AT_ONCE asking at once."""
    assert E.PICTURES_AT_ONCE == 6
    host = Counting(0.02)
    pictures = ArtistPictures()
    pictures._client = httpx.AsyncClient(transport=httpx.MockTransport(host.handle), follow_redirects=False)

    async def twenty():
        got = await asyncio.gather(*(pictures.picture(httpx.URL(f"https://r2.theaudiodb.com/{n}.jpg"))
                                     for n in range(20)))
        await pictures.close_client()
        return got

    got = asyncio.run(twenty())
    assert all(answer is not None and answer[1] == "image/jpeg" for answer in got)
    assert host.asked == 20
    assert host.most == E.PICTURES_AT_ONCE


def test_waiting_for_a_turn_is_inside_the_deadline(monkeypatch):
    """Nothing carries on past the ask, so a picture queued past the deadline is a 504 - not a wait the phone gives up
    on first."""
    monkeypatch.setattr(E, "PICTURES_AT_ONCE", 1)
    monkeypatch.setattr(E, "PICTURE_DEADLINE_SECONDS", 0.15)
    host = Counting(0.1)
    pictures = ArtistPictures()
    pictures._client = httpx.AsyncClient(transport=httpx.MockTransport(host.handle), follow_redirects=False)

    async def two():
        got = await asyncio.gather(*(pictures.picture(httpx.URL(f"https://r2.theaudiodb.com/{n}.jpg"))
                                     for n in range(2)), return_exceptions=True)
        await pictures.close_client()
        return got

    first, second = asyncio.run(two())
    assert first[1] == "image/jpeg"
    assert isinstance(second, PictureHostSlow)
    assert host.most == 1


def test_past_the_pending_cap_an_ask_is_refused_at_once_and_asked_once_they_drain(monkeypatch):
    """The six at a time cover the fetch; PICTURES_PENDING_MAX covers the asks waiting their turn as well, so a loop of
    asks can't pile up behind them. Past it: PicturesBusy at once, nothing asked, nothing remembered."""
    assert E.PICTURES_PENDING_MAX == 64
    monkeypatch.setattr(E, "PICTURES_PENDING_MAX", 3)
    host = Counting(0.1)
    pictures = ArtistPictures()
    pictures._client = httpx.AsyncClient(transport=httpx.MockTransport(host.handle), follow_redirects=False)

    async def run():
        under_way = [asyncio.create_task(pictures.picture(httpx.URL(f"https://r2.theaudiodb.com/{n}.jpg")))
                     for n in range(3)]
        await asyncio.sleep(0.02)
        assert pictures.pending == 3
        began = time.monotonic()
        with pytest.raises(E.PicturesBusy):
            await pictures.picture(httpx.URL("https://r2.theaudiodb.com/one-more.jpg"))
        quick = time.monotonic() - began
        done = await asyncio.gather(*under_way)
        after = await pictures.picture(httpx.URL("https://r2.theaudiodb.com/one-more.jpg"))
        await pictures.close_client()
        return quick, done, after

    quick, done, after = asyncio.run(run())
    assert quick < 0.05
    assert all(answer is not None for answer in done) and after is not None
    #? the refused one was never asked; asked normally once the others drained
    assert host.asked == 4
    assert pictures.pending == 0


def test_the_pending_count_comes_back_down_whatever_happens(monkeypatch):
    monkeypatch.setattr(E, "PICTURE_DEADLINE_SECONDS", 0.05)
    outcomes = {"/0.jpg": httpx.Response(200, headers={"content-type": "image/jpeg"}, content=jpeg("a")),
                "/1.jpg": httpx.Response(503),
                "/2.jpg": httpx.Response(200, headers={"content-type": "text/html"}, text="no"),
                "/3.jpg": httpx.Response(404),
                "/4.jpg": None}

    async def handle(request):
        answer = outcomes[request.url.path]
        if answer is None:
            await asyncio.sleep(1)
        return answer

    pictures = ArtistPictures()
    pictures._client = httpx.AsyncClient(transport=httpx.MockTransport(handle), follow_redirects=False)

    async def run():
        got = await asyncio.gather(*(pictures.picture(httpx.URL(f"https://r2.theaudiodb.com/{n}.jpg"))
                                     for n in range(5)), return_exceptions=True)
        await pictures.close_client()
        return got

    got = asyncio.run(run())
    assert [type(answer).__name__ for answer in got] == ["tuple", "PictureHostDown", "PictureRefused", "NoneType",
                                                         "PictureHostSlow"]
    assert pictures.pending == 0


def test_too_many_under_way_is_a_503_in_words(env, monkeypatch):
    async def busy(address):
        raise E.PicturesBusy("64 under way")

    monkeypatch.setattr(artist_pictures, "picture", busy)
    answer = picture(env, THEAUDIODB)

    assert answer.status_code == 503
    assert answer.json()["detail"] == route.PICTURE_WORDS[503]
    assert answer.headers["cache-control"] == "no-store"


def test_nothing_is_kept_and_each_ask_asks_again(env):
    for _ in range(2):
        assert picture(env, THEAUDIODB).status_code == 200
    assert env.hosts.hosts() == ["r2.theaudiodb.com", "r2.theaudiodb.com"]
    assert list(env.cache.iterdir()) == []


# ----------------------------------------------------------------- headers, and who may ask

def test_the_answer_carries_the_media_headers_and_is_never_gzipped(env):
    assert serves_media(ROUTE)
    answer = picture(env, THEAUDIODB, headers={"Accept-Encoding": "gzip"})

    assert answer.status_code == 200
    assert "content-encoding" not in answer.headers
    for name, value in MEDIA_HEADERS.items():
        assert answer.headers[name] == value


def test_a_refusal_carries_them_too(env):
    answer = picture(env, "https://example.com/a.jpg")

    assert answer.status_code == 400
    for name, value in MEDIA_HEADERS.items():
        assert answer.headers[name] == value


def test_with_logins_off_the_implicit_admin_is_let_through(env):
    assert not Config.logins_on()
    assert picture(env, THEAUDIODB).status_code == 200


def test_the_preview_url_survives_the_query_string(env):
    """A Commons title percent-encoded (artists.commons_file_url quotes it once), sent as the app would - the whole
    address encoded as one query value - reaches Commons exactly as the candidate named it."""
    url = commons_file_url("Pink Floyd, 1971 (HQ).jpg", PREVIEW_WIDTH)
    assert "%2C" in url and "%28" in url
    answer = env.client.get(f"{ROUTE}?url={quote(url, safe='')}")

    assert answer.status_code == 200
    assert str(env.hosts.requests[0].url) == url
