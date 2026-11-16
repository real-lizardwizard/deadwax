"""
Fetching cover art from the Cover Art Archive.

The interface already loads CAA thumbnails straight from the browser for albums that have
no local art. This is the other half: when you tell the metadata manager which release an
album is, it can put that release's cover in the folder so the album has real art on disk -
visible to every other music tool, and no longer dependent on the Archive being up.

Kept to its own client rather than reusing MusicBrainzClient. CAA is a different host with
different rules: no rate limit to respect, but it redirects to archive.org, so redirects
must be followed and the timeouts want to be generous - it can be slow, and an image is
bigger than a JSON document.

What gets saved is COVER_ART_SIZE: 500px unless you choose otherwise in the settings tab.
`full` asks for the original upload rather than one of the Archive's thumbnails - what you want
when the cover is going to be looked at, and what to avoid when it is going to be one of ten
thousand, since an original is often several megabytes.
"""

import asyncio

import httpx

from src import __version__
from src.config import COVER_ART_SIZES, Config
from src.logger import logger

BASE_URL = "https://coverartarchive.org"

#? The size asked for when nothing says otherwise: sharp enough to be worth keeping and to
#? survive being shown larger later, without pulling a multi-megabyte original for something
#? the library draws at 44px. COVER_ART_SIZE changes it.
DEFAULT_SIZE = "500"

#? What `full` settles for when the original isn't an image the library can keep. The Archive
#? accepts PDFs, and a release's front can be one; its thumbnails are always JPEGs.
FULL_SIZE_FALLBACK = "1200"

MIME_EXTENSIONS = {
    "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp",
}


def cover_art_path(release_mbid: str, size: str | int | None = None) -> str:
    """
    The Archive's address for one release's front cover at one size.

    `full` is the bare `front`, which redirects to the original upload. Anything unrecognised is
    treated as the default rather than trusted: the value can come from a database row somebody
    edited by hand, and asking for `front-huge` could only ever 404.
    """
    size = str(size or DEFAULT_SIZE)
    if size not in COVER_ART_SIZES:
        size = DEFAULT_SIZE

    if size == "full":
        return f"/release/{release_mbid}/front"

    return f"/release/{release_mbid}/front-{size}"


def describe_size(size: str) -> str:
    """How the log names a size: 'full size', or '1200px'."""
    return "full size" if size == "full" else f"{size}px"


def _amount(count: int) -> str:
    """Bytes as the log says them. An original can run to megabytes, a thumbnail to kilobytes."""
    if count >= 1024 * 1024:
        return f"{count / (1024 * 1024):.1f} MB"
    return f"{count // 1024} KB"


class CoverArtClient:
    def __init__(self):
        self.client: httpx.AsyncClient | None = None

    async def get_client(self) -> httpx.AsyncClient:
        if not self.client or self.client.is_closed:
            self.client = httpx.AsyncClient(
                base_url=BASE_URL,
                #? CAA answers with a redirect to archive.org, so this is not optional
                follow_redirects=True,
                #? `read` is how long to wait for the NEXT chunk, not for the whole body, so a
                #? multi-megabyte original still arrives as long as it keeps arriving
                timeout=httpx.Timeout(connect=10.0, write=10.0, read=45.0, pool=10.0),
            )

        return self.client

    @staticmethod
    def user_agent() -> str:
        """
        The same identifying user agent MusicBrainz is sent, which the Archive asks for too.

        Sent with each request rather than fixed when the client is built: the client lives as
        long as the process, so a contact changed in the settings tab would otherwise go on being
        sent as the old one until a restart. Falls back rather than refusing - art is a nicety,
        and failing a retag because no contact was set would be out of proportion.
        """
        return Config.musicbrainz_user_agent() or f"deadwax/{__version__}"

    async def close_client(self) -> None:
        if self.client and not self.client.is_closed:
            await self.client.aclose()
            self.client = None

    async def fetch_front(
        self, release_mbid: str, size: str | int | None = None,
    ) -> tuple[bytes, str] | None:
        """
        The front cover for a release, or None.

        `size` defaults to COVER_ART_SIZE. None covers every ordinary way this doesn't work out -
        the release has no art, the Archive is down, the download is truncated - because none of
        them are errors worth failing a retag over. The tags are the point; the art is a bonus.
        """
        art, _reason = await self.fetch_front_why(release_mbid, size)
        return art

    async def fetch_front_why(
        self, release_mbid: str, size: str | int | None = None,
    ) -> tuple[tuple[bytes, str] | None, str]:
        """
        fetch_front, and why not when there's no cover: "missing" when the Archive answered that the
        release has none (or there is no release to ask about) - a fact about the release - and
        "unreachable", "failed", "truncated" or "not an image" when the request didn't come back with
        one, which is worth trying again (2.0.0-player.42: /library/art/fetch tells the two apart, as
        /library/disc_art/fetch does, so a run of Get covers during one of the Archive's outages says
        "failed - try those again" rather than "had none on the Archive"). After the 1200px fallback the
        reason is that request's own: a release whose 1200px copy is a 404 has no cover.
        """
        if not release_mbid:
            return None, "missing"

        size = str(size or Config.COVER_ART_SIZE or DEFAULT_SIZE)
        if size not in COVER_ART_SIZES:
            size = DEFAULT_SIZE

        art, reason = await self._fetch(release_mbid, size)

        if reason == "not an image" and size == "full":
            logger.info(
                f"the original cover for {release_mbid} isn't an image that can be saved, "
                f"so using the Archive's {FULL_SIZE_FALLBACK}px copy instead"
            )
            art, reason = await self._fetch(release_mbid, FULL_SIZE_FALLBACK)

        return art, reason

    async def _fetch(self, release_mbid: str, size: str) -> tuple[tuple[bytes, str] | None, str]:
        """One request: the art, or None and a short reason why not."""
        try:
            client = await self.get_client()
            response = await client.get(
                cover_art_path(release_mbid, size),
                headers={"User-Agent": self.user_agent()},
            )

        except Exception as e:
            logger.warning(f"could not reach the Cover Art Archive: {e}")
            return None, "unreachable"

        if response.status_code == 404:
            #? extremely common and not a problem: plenty of releases simply have no art
            logger.info(f"no cover art on file for release {release_mbid}")
            return None, "missing"

        if response.status_code != 200:
            logger.warning(f"cover art request returned {response.status_code} for {release_mbid}")
            return None, "failed"

        content_type = (response.headers.get("content-type") or "").split(";")[0].strip().lower()

        if content_type not in MIME_EXTENSIONS:
            logger.warning(f"cover art came back as {content_type!r}, which isn't an image")
            return None, "not an image"

        data = response.content

        #? a few hundred bytes is an error page or a truncated download, not a cover
        if len(data) < 1024:
            logger.warning(f"cover art for {release_mbid} was only {len(data)} bytes, ignoring it")
            return None, "truncated"

        logger.info(
            f"fetched {_amount(len(data))} of cover art ({describe_size(size)}) for {release_mbid}",
            extra={"frontend": True, "src": "musicbrainz"},
        )
        return (data, content_type), "ok"


    async def release_images(self, release_mbid: str) -> list[dict] | None:
        """
        Every image the Archive holds for a release, with its types and comment - or None.

        None means the Archive couldn't be asked; an empty list means it has nothing for this
        release. The two are kept apart for the same reason a cover's 404 is: one is a fact
        about the release, the other is worth trying again.
        """
        if not release_mbid:
            return []

        try:
            client = await self.get_client()
            response = await client.get(f"/release/{release_mbid}",
                                        headers={"User-Agent": self.user_agent()})
        except Exception as e:
            logger.warning(f"could not reach the Cover Art Archive: {e}")
            return None

        if response.status_code == 404:
            return []
        if response.status_code != 200:
            logger.warning(f"the Cover Art Archive answered {response.status_code} for {release_mbid}")
            return None

        try:
            images = response.json().get("images")
        except ValueError:
            return None
        return [image for image in images if isinstance(image, dict)] if isinstance(images, list) else []

    async def fetch_image(self, url: str) -> tuple[bytes, str] | None:
        """One image by the address the Archive's own listing gave - never one a caller sent."""
        try:
            client = await self.get_client()
            response = await client.get(url, headers={"User-Agent": self.user_agent()})
        except Exception as e:
            logger.warning(f"could not fetch an image from the Cover Art Archive: {e}")
            return None

        mime = (response.headers.get("content-type") or "").split(";")[0].strip().lower()
        if response.status_code != 200 or mime not in MIME_EXTENSIONS or len(response.content) < 1024:
            logger.warning(f"an Archive image answered {response.status_code} as {mime or 'nothing'}")
            return None
        return response.content, mime


def extension_for(mime: str) -> str:
    return MIME_EXTENSIONS.get(mime, "jpg")


# ---------------------------------------------------------------- the relay's fetch (2.1.24)
#
# The fronts GET /deadwax/coverart/{kind}/{mbid} passes on to the iPhone app (src/coverart_cache.py keeps them,
# src/routes/coverart.py answers): a release's front, or a release group's - the Archive's own pick of the group's
# front - at one of the Archive's three thumbnail sizes. A client of its own beside CoverArtClient rather than that one:
# CoverArtClient follows a redirect anywhere, which is fine for saving the cover of a release somebody chose, and not
# for a route that fetches whatever a phone names. Here nothing from a request is part of an address but a kind, an
# mbid and a size, each from a fixed set or a fixed pattern (the route checks them first); a redirect is followed only
# to the Archive's own hosts; an answer is read a piece at a time and refused past FRONT_MAX_BYTES; and the whole
# fetch, every hop and the body, has FRONT_DEADLINE_SECONDS. Three outcomes kept apart, as the AutoEq client keeps
# them: a front, a 404 (the Archive has none: None), and a failure that says whether it looks like an outage
# (ArchiveDown, ArchiveSlow) or belongs to this one answer (ArchiveRefused).

#? the kinds and sizes the Archive answers `front-<size>` for - the route takes only these
FRONT_KINDS = ("release", "release-group")
FRONT_SIZES = ("250", "500", "1200")

#? Every host a front may come from. The Archive answers with a redirect to archive.org, which redirects again to one
#? of its own servers (ia800101.us.archive.org and the like) - so these two, archive.org's servers, and nothing else.
ARCHIVE_HOSTS = ("coverartarchive.org", "archive.org")
ARCHIVE_SUFFIX = ".archive.org"

#? A 1200px thumbnail is a few hundred KB; past this it isn't a cover a phone should be sent
FRONT_MAX_BYTES = 4 << 20
#? The whole fetch: every redirect and the body. The route waits less (src/coverart_cache.py ANSWER_SECONDS) - a
#? slow Archive costs that ask its answer, not the fetch, whose cover the next ask finds kept.
FRONT_DEADLINE_SECONDS = 20.0
#? The Archive's chain is two or three hops (a release group's front is a release's, then archive.org, then its server)
FRONT_REDIRECTS = 5
#? between pieces, and to connect: an Archive that isn't there fails in seconds, not at the deadline
FRONT_TIMEOUT = httpx.Timeout(10.0, connect=5.0)

REDIRECTS = frozenset({301, 302, 303, 307, 308})

#? (2.1.32, a fix to 2.1.24 - the review of the artist pictures' relay found it in both) The body is counted as it
#? comes off the wire, so it must come undecoded: asked for as it is (`Accept-Encoding: identity`; httpx asks for gzip
#? by default) and an answer encoded anyway refused unread. Read with aiter_bytes(), httpx inflated a gzip - or
#? `gzip, gzip` - body far past FRONT_MAX_BYTES before the count saw it: 141 MB from 269 bytes on the wire, in the
#? review. With identity alone let through, httpx decodes nothing, so the pieces counted are the bytes that came.
#? Covers are compressed already, so nothing is lost. Shared with src/api/artist_images_endpoint.py.
IDENTITY = "identity"


def sent_as_it_is(response: httpx.Response) -> bool:
    """Whether an answer's body is its bytes, undecoded: no Content-Encoding, or `identity`."""
    return (response.headers.get("content-encoding") or "").strip().lower() in ("", IDENTITY)


class ArchiveDown(Exception):
    """The Archive (or archive.org) didn't answer, or answered as a server in trouble (429, 5xx): an outage, most
    likely, and a reason to stop asking for a moment."""


class ArchiveSlow(ArchiveDown):
    """The fetch took longer than its deadline, or a piece of it longer than FRONT_TIMEOUT: a 504."""


class ArchiveRefused(Exception):
    """This answer wasn't a cover deadwax passes on: a redirect off the Archive's hosts, not an image, too big, empty,
    another status, too many redirects. It says nothing about the Archive as a whole."""


def front_address(kind: str, mbid: str, size: str) -> str:
    """The Archive's address for a front at a thumbnail size. `kind`, `mbid` and `size` are the route's, already
    checked: one of FRONT_KINDS, a lowercase UUID, one of FRONT_SIZES."""
    if kind not in FRONT_KINDS or size not in FRONT_SIZES:
        raise ValueError(f"not a front the relay asks for: {kind} at {size}")
    return f"{BASE_URL}/{kind}/{mbid}/front-{size}"


def on_the_archive(url: httpx.URL) -> bool:
    """Whether a redirect's target is the Archive's own: http or https, no port but the scheme's own, no user, and the
    host coverartarchive.org, archive.org or one of archive.org's servers. An address by number is never one."""
    host = (url.host or "").lower()
    return (url.scheme in ("https", "http") and url.port is None and not url.userinfo
            and (host in ARCHIVE_HOSTS or host.endswith(ARCHIVE_SUFFIX)))


class ArchiveFronts:
    """The relay's client: one httpx.AsyncClient, redirects followed by hand, a deadline on the whole of each fetch."""

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            #? never followed by httpx: each hop is checked here first (on_the_archive)
            self._client = httpx.AsyncClient(follow_redirects=False, timeout=FRONT_TIMEOUT)
        return self._client

    async def close_client(self) -> None:
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
        self._client = None

    async def front(self, kind: str, mbid: str, size: str) -> tuple[bytes, str] | None:
        """The front's bytes and type, None when the Archive has none - or ArchiveDown, ArchiveSlow, ArchiveRefused."""
        what = f"the {kind} {mbid}'s front at {size}px"
        address = httpx.URL(front_address(kind, mbid, size))
        #? read at each call, so the tests can shorten it
        deadline = FRONT_DEADLINE_SECONDS
        try:
            async with asyncio.timeout(deadline):
                return await self._follow(address, what)
        except TimeoutError as e:
            raise ArchiveSlow(f"the Cover Art Archive took more than {deadline:g} s for {what}") from e

    async def _follow(self, address: httpx.URL, what: str) -> tuple[bytes, str] | None:
        headers = {"User-Agent": CoverArtClient.user_agent(), "Accept-Encoding": IDENTITY}
        for _ in range(FRONT_REDIRECTS + 1):
            host = address.host
            try:
                async with self._http().stream("GET", address, headers=headers) as response:
                    status = response.status_code
                    if status in REDIRECTS:
                        location = response.headers.get("location")
                        if not location:
                            raise ArchiveRefused(f"{host} answered {status} with nowhere to go for {what}")
                        target = address.join(location)
                        if not on_the_archive(target):
                            raise ArchiveRefused(f"{host} sent {what} on to {target.host or location!r}, which isn't "
                                                 f"the Archive's own, so it wasn't followed")
                        address = target
                        continue
                    if status == 404:
                        return None
                    if status == 429 or status >= 500:
                        raise ArchiveDown(f"{host} answered {status} for {what}")
                    if status != 200:
                        raise ArchiveRefused(f"{host} answered {status} for {what}")
                    mime = (response.headers.get("content-type") or "").split(";")[0].strip().lower()
                    if mime not in MIME_EXTENSIONS:
                        raise ArchiveRefused(f"{host} answered {what} as {mime or 'no type'}, which isn't an image")
                    if not sent_as_it_is(response):
                        raise ArchiveRefused(f"{host} answered {what} encoded as "
                                             f"{response.headers.get('content-encoding')!r}, though it was asked for "
                                             f"as it is")
                    declared = response.headers.get("content-length") or ""
                    if declared.isdigit() and int(declared) > FRONT_MAX_BYTES:
                        raise ArchiveRefused(f"{what} was refused: {_amount(int(declared))}, past "
                                             f"{_amount(FRONT_MAX_BYTES)}")
                    body = bytearray()
                    #? identity or nothing (sent_as_it_is, above), so nothing is decoded: what is counted is what came
                    async for piece in response.aiter_bytes():
                        body += piece
                        if len(body) > FRONT_MAX_BYTES:
                            raise ArchiveRefused(f"{what} was refused: more than {_amount(FRONT_MAX_BYTES)}")
                    if not body:
                        raise ArchiveRefused(f"{host} answered {what} with nothing")
                    return bytes(body), mime
            except httpx.TimeoutException as e:
                raise ArchiveSlow(f"{host} took too long for {what} ({type(e).__name__})") from e
            except httpx.HTTPError as e:
                raise ArchiveDown(f"{host} couldn't be reached for {what}: {str(e) or type(e).__name__}") from e
        raise ArchiveRefused(f"{what} was refused: more than {FRONT_REDIRECTS} redirects")


archive_fronts = ArchiveFronts()
