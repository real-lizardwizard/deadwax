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
        if not release_mbid:
            return None

        size = str(size or Config.COVER_ART_SIZE or DEFAULT_SIZE)
        if size not in COVER_ART_SIZES:
            size = DEFAULT_SIZE

        art, reason = await self._fetch(release_mbid, size)

        if reason == "not an image" and size == "full":
            logger.info(
                f"the original cover for {release_mbid} isn't an image that can be saved, "
                f"so using the Archive's {FULL_SIZE_FALLBACK}px copy instead"
            )
            art, _ = await self._fetch(release_mbid, FULL_SIZE_FALLBACK)

        return art

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
