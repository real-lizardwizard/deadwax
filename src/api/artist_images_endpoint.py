"""
Fetching artist images, from the three places they actually live.

MusicBrainz has none of its own - see the header of src/artists.py - so this client talks to
Wikidata (and through it Wikimedia Commons) and, when a key is configured, to TheAudioDB.
Deciding WHICH pictures those payloads offer is artists.py's job and is pure; this module only
does the I/O, which is what keeps that decision testable without a network.

Its own client rather than MusicBrainzClient's, like the Cover Art Archive's: different hosts,
different rules, no MusicBrainz rate limit to respect, and redirects that must be followed -
Commons answers Special:FilePath with a 302 to the file itself.

(2.1.32) And ArtistPictures, below: the candidates' previews passed on to the iPhone app, which
talks only to deadwax - GET /deadwax/library/artist/picture?url= (src/routes/library.py).
"""

import asyncio
from urllib.parse import quote

import httpx

from src import __version__
from src.api.coverart_endpoint import IDENTITY, sent_as_it_is
from src.artists import (PREVIEW_WIDTH, SAVE_WIDTH, commons_file_url, commons_title,
                         from_fanarttv, from_relations, from_theaudiodb, from_wikidata,
                         safe_thumb_width, wikidata_id)
from src.config import Config
from src.logger import logger

WIKIDATA_ENTITY = "https://www.wikidata.org/wiki/Special:EntityData/{}.json"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
THEAUDIODB_ARTIST = "https://www.theaudiodb.com/api/v1/json/{key}/artist-mb.php?i={mbid}"
#? webservice.fanart.tv, NOT api.fanart.tv. Their own repo documents the latter, and it is the
#? website: it sits behind Cloudflare and answers a bot check with 403 and an HTML challenge
#? page, whatever key you send. The webservice host answers properly - a bad key gets
#? `401 {"error":"invalid API key"}` - and is what every other client uses.
FANARTTV_ARTIST = "https://webservice.fanart.tv/v3/music/{mbid}"
#? an album's artwork by RELEASE GROUP id - its `cdart` is disc art, numbered per disc
FANARTTV_ALBUM = "https://webservice.fanart.tv/v3/music/albums/{mbid}"

#? An artist page asks for a handful of pictures at once, and a Commons original can be a 20 MB
#? scan. Generous enough for a real background, mean enough that one artist can't fill the disk.
MAX_IMAGE_BYTES = 20 * 1024 * 1024

IMAGE_TIMEOUT = httpx.Timeout(30.0, connect=10.0)
JSON_TIMEOUT = httpx.Timeout(15.0, connect=10.0)


def image_user_agent() -> str:
    """
    What the image sources are told deadwax is: the string MusicBrainz is given, contact and all, else
    `deadwax/<version>`. Wikimedia asks every caller to identify itself. Built per request, never at construction:
    the Cover Art Archive client learned the expensive way that a header fixed when the client was made goes on
    reporting the contact the settings tab was changed away from. (2.1.32) Shared by ArtistImagesClient and the
    pictures' relay, ArtistPictures.
    """
    return Config.musicbrainz_user_agent() or f"deadwax/{__version__}"


class ArtistImagesClient:
    """Reads the image sources. Holds no state beyond one httpx client."""

    def __init__(self) -> None:
        self._client = httpx.AsyncClient(follow_redirects=True, timeout=IMAGE_TIMEOUT)

    async def close_client(self) -> None:
        await self._client.aclose()

    def user_agent(self) -> str:
        """image_user_agent(): built per request, the same string MusicBrainz is given."""
        return image_user_agent()

    async def _json(self, url: str, what: str) -> dict | None:
        try:
            response = await self._client.get(
                url, headers={"User-Agent": self.user_agent()}, timeout=JSON_TIMEOUT,
            )
        except httpx.HTTPError as e:
            logger.warning(f"could not reach {what}: {e}")
            return None

        if response.status_code != 200:
            #? 404 from TheAudioDB means "this artist isn't in it", which is ordinary and not
            #? worth an error in the user's log
            logger.debug(f"{what} answered {response.status_code}")
            return None

        try:
            return response.json()
        except ValueError:
            logger.warning(f"{what} did not answer with JSON")
            return None

    async def wikidata(self, entity_id: str) -> dict | None:
        """One Wikidata entity, or None if it can't be had."""
        data = await self._json(WIKIDATA_ENTITY.format(entity_id), "Wikidata")
        entities = (data or {}).get("entities") or {}
        return entities.get(entity_id) or (next(iter(entities.values()), None) if entities else None)

    async def theaudiodb(self, artist_mbid: str) -> dict | None:
        """
        One TheAudioDB artist row, looked up by MusicBrainz artist id.

        Returns None when no key is configured, which is the ordinary case: everything else on
        the artist page works without one, and this is the only source with banners.
        """
        key = (Config.THEAUDIODB_KEY or "").strip()
        if not key or not artist_mbid:
            return None

        data = await self._json(
            THEAUDIODB_ARTIST.format(key=key, mbid=artist_mbid), "TheAudioDB",
        )
        artists = (data or {}).get("artists")
        return artists[0] if isinstance(artists, list) and artists else None

    async def fanarttv(self, artist_mbid: str) -> dict | None:
        """
        One fanart.tv music response, looked up by MusicBrainz artist id.

        None when no key is configured, which is the ordinary case. fanart.tv issues a PROJECT
        key per application rather than per person, so it cannot be shipped with deadwax and
        has to be registered by whoever runs it; the personal key beside it is optional and only
        buys earlier sight of images added in the last week.
        """
        key = (Config.FANARTTV_KEY or "").strip()
        if not key or not artist_mbid:
            return None

        params = f"?api_key={quote(key)}"
        personal = (Config.FANARTTV_PERSONAL_KEY or "").strip()
        if personal:
            params += f"&client_key={quote(personal)}"

        return await self._json(FANARTTV_ARTIST.format(mbid=artist_mbid) + params, "fanart.tv")

    async def fanarttv_cdart(self, release_group_mbid: str) -> list[dict] | None:
        """
        fanart.tv's disc art for an album, by release group id - or None without a key.

        Lives here rather than beside the Cover Art Archive client because it is the same host,
        the same key and the same request as the artist lookup above.
        """
        key = (Config.FANARTTV_KEY or "").strip()
        if not key or not release_group_mbid:
            return None

        params = f"?api_key={quote(key)}"
        personal = (Config.FANARTTV_PERSONAL_KEY or "").strip()
        if personal:
            params += f"&client_key={quote(personal)}"

        data = await self._json(FANARTTV_ALBUM.format(mbid=release_group_mbid) + params, "fanart.tv")
        albums = (data or {}).get("albums") or {}
        album = albums.get(release_group_mbid) or (next(iter(albums.values()), None) if albums else None)
        cdart = (album or {}).get("cdart")
        return [art for art in cdart if isinstance(art, dict)] if isinstance(cdart, list) else []

    async def candidates(self, artist: dict) -> list[dict]:
        """
        Every picture the three sources offer for this artist, best source first.

        `artist` is a MusicBrainz artist as looked up with url-rels. Each source is allowed to
        fail on its own: a Wikidata outage costs the Commons portrait and leaves fanart.tv's
        banner, which is the behaviour an artist page wants.
        """
        relations = artist.get("relations") or []
        mbid = artist.get("id") or ""
        found = list(from_relations(relations))

        row = await self.theaudiodb(mbid)
        if row:
            found = list(from_theaudiodb(row)) + found

        art = await self.fanarttv(mbid)
        if art:
            found = list(from_fanarttv(art)) + found

        entity_id = wikidata_id(relations)
        if entity_id:
            entity = await self.wikidata(entity_id)
            if entity:
                found += list(from_wikidata(entity))

        return await self._size_commons(found)

    async def commons_width(self, title: str) -> int:
        """
        How wide a Commons file actually is, so a thumbnail can be asked for under it.

        One small JSON request per picture, and the reason is in safe_thumb_width: ask for a
        thumbnail wider than the original and MediaWiki answers with the original, which
        upload.wikimedia.org refuses to a robot. 0 when it can't be found, which leaves the
        asked-for width alone.
        """
        data = await self._json(
            f"{COMMONS_API}?action=query&titles=File:{quote(title)}&prop=imageinfo"
            "&iiprop=size&format=json&formatversion=2",
            "Commons",
        )

        for page in ((data or {}).get("query") or {}).get("pages") or []:
            for info in page.get("imageinfo") or []:
                if isinstance(info.get("width"), int):
                    return info["width"]

        return 0

    async def _size_commons(self, candidates: list[dict]) -> list[dict]:
        """
        Point every Commons candidate at a thumbnail rather than an original.

        Done once here rather than at the point of writing, so the picker shows the same picture
        that would be saved - and so a file too small to thumbnail at the wanted size is caught
        while it can still be reported, instead of failing at the write.
        """
        widths: dict[str, int] = {}
        resolved = []

        for candidate in candidates:
            title = commons_title(candidate["url"])
            if not title:
                resolved.append(candidate)
                continue

            if title not in widths:
                widths[title] = await self.commons_width(title)

            original = widths[title]
            #? an SVG logo is drawn at whatever size is asked for, so it keeps the full width
            vector = title.lower().endswith(".svg")
            resolved.append({
                **candidate,
                "url": commons_file_url(title, safe_thumb_width(original, SAVE_WIDTH, vector)),
                "preview": commons_file_url(title, safe_thumb_width(original, PREVIEW_WIDTH, vector)),
            })

        return resolved

    async def fetch(self, url: str) -> tuple[bytes, str] | None:
        """
        The bytes behind one candidate, with its content type.

        Anything that isn't an image is refused rather than written: Commons will happily serve
        an HTML error page with a 200, and a folder full of `artist.jpg` files that are really
        error pages is a mess nobody would think to look for.
        """
        try:
            response = await self._client.get(url, headers={"User-Agent": self.user_agent()})
        except httpx.HTTPError as e:
            logger.warning(f"could not fetch an artist image: {e}")
            return None

        if response.status_code != 200:
            #? 403 from upload.wikimedia.org is their robot policy, and it means the URL resolved
            #? to an ORIGINAL rather than a thumbnail - see safe_thumb_width
            reason = (" - Wikimedia refuses originals to robots, so this needs a smaller thumbnail"
                      if response.status_code == 403 else "")
            logger.warning(f"an artist image answered {response.status_code}{reason}")
            return None

        mime = (response.headers.get("content-type") or "").split(";")[0].strip().lower()
        if not mime.startswith("image/"):
            logger.warning(f"an artist image was {mime or 'untyped'} rather than an image")
            return None

        data = response.content
        if len(data) > MAX_IMAGE_BYTES:
            logger.warning(f"an artist image was {len(data) // 1024 // 1024} MB and was skipped")
            return None

        return data, mime


# ---------------------------------------------------------------- the pictures' relay (2.1.32)
#
# The candidates' previews passed on to the iPhone app (Phase 8's server change B), which talks only to deadwax:
# GET /deadwax/library/artist/picture?url= (src/routes/library.py) hands the address a preview named to
# ArtistPictures, modelled on the Cover Art Archive's relay (src/api/coverart_endpoint.py ArchiveFronts). NOT A
# GENERAL PROXY: an address is fetched only when it is https, on exactly one of PICTURE_HOSTS, with no user and no
# port but https's own (picture_address - the route asks it first, so anything else is a 400 and never asked); a
# redirect is followed by hand and only when its target passes the same check; at most PICTURE_REDIRECTS of them;
# only an image type is read, asked for and taken undecoded, a piece at a time, refused past PICTURE_MAX_BYTES; at
# most PICTURES_AT_ONCE fetch and PICTURES_PENDING_MAX are under way; and the whole fetch - a turn, every hop and the
# body - has PICTURE_DEADLINE_SECONDS. Nothing is kept: no cache on disk, nothing remembered. The outcomes kept apart,
# as ArchiveFronts keeps them: a picture, a 404 (None), too many under way (PicturesBusy), and a failure that says
# whether it looks like the host's trouble (PictureHostDown, PictureHostSlow) or belongs to this one answer
# (PictureRefused).

#? Every host a preview may come from, or be redirected to - read off the candidates and seen by hand (2026-11-16):
#?   commons.wikimedia.org  every Commons candidate's preview (artists.py commons_file_url, Special:FilePath with
#?                          ?width=), and its own first hop (/w/index.php?title=Special:Redirect/file/...)
#?   thumb.wikimedia.org    where that redirects for a thumbnail narrower than the original (seen: a 960px JPEG,
#?                          and an SVG logo as a PNG)
#?   upload.wikimedia.org   where it redirects for a file no wider than asked, served as it is (seen: Example.jpg)
#?   r2.theaudiodb.com      every TheAudioDB picture (its preview is the picture itself; tests/test_artists.py's
#?                          fixture, and every field of a row asked with TheAudioDB's public test key) - no redirect
#?   assets.fanart.tv       fanart.tv's pictures (their preview is the picture itself) - from fanart.tv's API
#?                          documentation; NOT seen, there being no project key here
#? Exactly these names: no subdomain, no address by number, so nothing on the network deadwax runs in can be reached.
PICTURE_HOSTS = frozenset({"commons.wikimedia.org", "thumb.wikimedia.org", "upload.wikimedia.org",
                           "r2.theaudiodb.com", "assets.fanart.tv"})

#? Commons' previews are 600px thumbnails (artists.py PREVIEW_WIDTH; seen: 127 KB), but fanart.tv's and TheAudioDB's
#? preview is the picture itself - a TheAudioDB background 178 KB, and fanart.tv offers 4K backgrounds, a few MB each.
#? Room for those; no more than a picker should be sent.
PICTURE_MAX_BYTES = 8 << 20
#? The whole fetch: waiting for a turn, every hop and the body. Nothing carries on past the ask (nothing is kept), so
#? this is what the phone waits - under its 8 s (ios/App/URLSessionTransport.swift timeoutIntervalForRequest), so a
#? slow host is deadwax's 504 rather than the phone's own timeout.
PICTURE_DEADLINE_SECONDS = 7.0
#? Commons' chain is two hops (Special:FilePath, Special:Redirect, then the file); TheAudioDB's none
PICTURE_REDIRECTS = 4
#? between pieces, and to connect: a host that isn't there fails in seconds
PICTURE_TIMEOUT = httpx.Timeout(5.0, connect=4.0)
#? at most this many fetches at once, each reading up to PICTURE_MAX_BYTES (48 MB being read, at most); the rest wait
#? their turn inside the deadline. A picture once read leaves both counts and is held until its answer is handed on.
PICTURES_AT_ONCE = 6
#? the asks under way - waiting for a turn or fetching - past which another is a 503 at once, nothing asked (the
#? review's; the cover relay's PENDING_MAX): a picker's grid of thirty-odd fits, a loop of asks doesn't pile up
PICTURES_PENDING_MAX = 64
#? the longest address the route takes: a Commons title is at most 255 bytes, three times that percent-encoded
PICTURE_URL_MAX = 2048

PICTURE_REDIRECT_STATUSES = frozenset({301, 302, 303, 307, 308})
#? the host has no such picture: a 404 either way
PICTURE_GONE_STATUSES = frozenset({404, 410})

class PictureHostDown(Exception):
    """The picture's host didn't answer, or answered as a server in trouble (429, 5xx): a 502, said as for now."""


class PictureHostSlow(PictureHostDown):
    """The fetch took longer than its deadline, or a piece of it longer than PICTURE_TIMEOUT: a 504."""


class PictureRefused(Exception):
    """This answer wasn't a picture deadwax passes on: a redirect off PICTURE_HOSTS, not an image, too big, empty,
    encoded, refused (403 - Wikimedia's robot policy), another status, too many redirects. A 502, said as for good:
    asking again gets the same."""


class PicturesBusy(Exception):
    """PICTURES_PENDING_MAX asks are under way already: a 503 at once, nothing asked."""


def host_of(url: httpx.URL) -> str:
    """An address's host as it goes on the wire (an international name in its xn-- form), never decoded: httpx's
    `.host` decodes one, and raises for a malformed one (`xn--commons-.wikimedia.org`)."""
    return url.raw_host.decode("ascii", "replace").lower()


def passes_on(url: httpx.URL) -> bool:
    """Whether an address is one the relay asks: https, no user, no port but https's own, and a host exactly one of
    PICTURE_HOSTS. Every address it fetches, the first and each redirect's, is checked by this."""
    return url.scheme == "https" and url.port is None and not url.userinfo and host_of(url) in PICTURE_HOSTS


def picture_address(raw: str) -> httpx.URL | None:
    """The address a phone sent, parsed once - the same parse is checked and fetched - or None when the relay won't
    ask it (unparseable, or not passes_on)."""
    try:
        url = httpx.URL(raw)
    except Exception:
        #? httpx.InvalidURL, and idna's errors (a ValueError) for a host that isn't a name
        return None
    return url if passes_on(url) else None


class ArtistPictures:
    """The relay's client: one httpx.AsyncClient, redirects followed by hand, PICTURES_AT_ONCE at a time, a deadline
    on the whole of each fetch."""

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        #? the turns, one semaphore per event loop - a semaphore waited on belongs to its loop
        self._turns: tuple[asyncio.AbstractEventLoop, asyncio.Semaphore] | None = None
        #? the asks under way, waiting for a turn or fetching (PICTURES_PENDING_MAX)
        self.pending = 0

    def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            #? never followed by httpx: each hop is checked here first (passes_on)
            self._client = httpx.AsyncClient(follow_redirects=False, timeout=PICTURE_TIMEOUT)
        return self._client

    def _turn(self) -> asyncio.Semaphore:
        loop = asyncio.get_running_loop()
        if self._turns is None or self._turns[0] is not loop:
            self._turns = (loop, asyncio.Semaphore(PICTURES_AT_ONCE))
        return self._turns[1]

    async def close_client(self) -> None:
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
        self._client = None

    async def picture(self, address: httpx.URL) -> tuple[memoryview, str] | None:
        """The picture's bytes (a view of what was read, not a copy) and declared type, None when its host has none (a
        404 or 410) - or PicturesBusy, PictureHostDown, PictureHostSlow, PictureRefused. `address` is
        picture_address()'s, already checked; checked again here, so nothing reaches the network that didn't pass."""
        if not passes_on(address):
            raise PictureRefused(f"{host_of(address) or 'that address'} isn't one of the hosts deadwax passes "
                                 f"pictures on from")
        if self.pending >= PICTURES_PENDING_MAX:
            raise PicturesBusy(f"{self.pending} artist pictures are being fetched already")
        self.pending += 1
        #? read at each call, so the tests can shorten it
        deadline = PICTURE_DEADLINE_SECONDS
        try:
            async with asyncio.timeout(deadline):
                async with self._turn():
                    return await self._follow(address)
        except TimeoutError as e:
            raise PictureHostSlow(f"{host_of(address)} took more than {deadline:g} s for an artist picture") from e
        finally:
            self.pending -= 1

    async def _follow(self, address: httpx.URL) -> tuple[memoryview, str] | None:
        headers = {"User-Agent": image_user_agent(), "Accept-Encoding": IDENTITY}
        for _ in range(PICTURE_REDIRECTS + 1):
            host = host_of(address)
            try:
                async with self._http().stream("GET", address, headers=headers) as response:
                    status = response.status_code
                    if status in PICTURE_REDIRECT_STATUSES:
                        location = response.headers.get("location")
                        if not location:
                            raise PictureRefused(f"{host} answered {status} with nowhere to go for an artist picture")
                        try:
                            target = address.join(location)
                        except Exception as e:
                            #? httpx.InvalidURL isn't an httpx.HTTPError
                            raise PictureRefused(f"{host} sent an artist picture on to {location[:200]!r}, which "
                                                 f"isn't an address") from e
                        if not passes_on(target):
                            raise PictureRefused(f"{host} sent an artist picture on to {host_of(target) or location!r}, "
                                                 f"which isn't one of the hosts deadwax passes pictures on from, so "
                                                 f"it wasn't followed")
                        address = target
                        continue
                    if status in PICTURE_GONE_STATUSES:
                        return None
                    if status == 429 or status >= 500:
                        raise PictureHostDown(f"{host} answered {status} for an artist picture")
                    if status != 200:
                        #? 403 from Wikimedia is its robot policy: the address resolved to an original
                        raise PictureRefused(f"{host} answered {status} for an artist picture")
                    mime = (response.headers.get("content-type") or "").split(";")[0].strip().lower()
                    if not mime.startswith("image/"):
                        raise PictureRefused(f"{host} answered an artist picture as {mime or 'no type'}, which "
                                             f"isn't an image")
                    if not sent_as_it_is(response):
                        raise PictureRefused(f"{host} answered an artist picture encoded as "
                                             f"{response.headers.get('content-encoding')!r}, though it was asked "
                                             f"for as it is")
                    declared = response.headers.get("content-length") or ""
                    if declared.isdigit() and int(declared) > PICTURE_MAX_BYTES:
                        raise PictureRefused(f"an artist picture from {host} was refused: {int(declared):,} bytes, "
                                             f"past {PICTURE_MAX_BYTES:,}")
                    body = bytearray()
                    #? identity or nothing (sent_as_it_is, above), so nothing is decoded: what is counted is what came
                    async for piece in response.aiter_bytes():
                        body += piece
                        if len(body) > PICTURE_MAX_BYTES:
                            raise PictureRefused(f"an artist picture from {host} was refused: more than "
                                                 f"{PICTURE_MAX_BYTES:,} bytes")
                    if not body:
                        raise PictureRefused(f"{host} answered an artist picture with nothing")
                    #? a view, not bytes(body): the answer goes out without a second copy of it
                    return memoryview(body), mime
            #? httpx reads a redirect's Location itself, followed or not, before the answer reaches the lines above: one
            #? that isn't an address is its RemoteProtocolError "Invalid URL in location header", one whose name can't
            #? be decoded (xn--commons-.wikimedia.org) idna's ValueError - this answer's own fault, not an outage
            except ValueError as e:
                raise PictureRefused(f"{host} sent an artist picture on to an address that isn't one ({e})") from e
            except httpx.RemoteProtocolError as e:
                if "location header" not in str(e):
                    raise PictureHostDown(f"{host} broke off an artist picture: {str(e) or type(e).__name__}") from e
                raise PictureRefused(f"{host} sent an artist picture on to an address that isn't one ({e})") from e
            except httpx.TimeoutException as e:
                raise PictureHostSlow(f"{host} took too long for an artist picture ({type(e).__name__})") from e
            except httpx.HTTPError as e:
                raise PictureHostDown(f"{host} couldn't be reached for an artist picture: "
                                      f"{str(e) or type(e).__name__}") from e
        raise PictureRefused(f"an artist picture was refused: more than {PICTURE_REDIRECTS} redirects")


artist_pictures = ArtistPictures()
