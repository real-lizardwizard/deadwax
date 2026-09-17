"""
Fetching artist images, from the three places they actually live.

MusicBrainz has none of its own - see the header of src/artists.py - so this client talks to
Wikidata (and through it Wikimedia Commons) and, when a key is configured, to TheAudioDB.
Deciding WHICH pictures those payloads offer is artists.py's job and is pure; this module only
does the I/O, which is what keeps that decision testable without a network.

Its own client rather than MusicBrainzClient's, like the Cover Art Archive's: different hosts,
different rules, no MusicBrainz rate limit to respect, and redirects that must be followed -
Commons answers Special:FilePath with a 302 to the file itself.
"""

import httpx

from src import __version__
from src.artists import from_relations, from_theaudiodb, from_wikidata, wikidata_id
from src.config import Config
from src.logger import logger

WIKIDATA_ENTITY = "https://www.wikidata.org/wiki/Special:EntityData/{}.json"
THEAUDIODB_ARTIST = "https://www.theaudiodb.com/api/v1/json/{key}/artist-mb.php?i={mbid}"

#? An artist page asks for a handful of pictures at once, and a Commons original can be a 20 MB
#? scan. Generous enough for a real background, mean enough that one artist can't fill the disk.
MAX_IMAGE_BYTES = 20 * 1024 * 1024

IMAGE_TIMEOUT = httpx.Timeout(30.0, connect=10.0)
JSON_TIMEOUT = httpx.Timeout(15.0, connect=10.0)


class ArtistImagesClient:
    """Reads the image sources. Holds no state beyond one httpx client."""

    def __init__(self) -> None:
        self._client = httpx.AsyncClient(follow_redirects=True, timeout=IMAGE_TIMEOUT)

    async def close_client(self) -> None:
        await self._client.aclose()

    def user_agent(self) -> str:
        """
        Built per request, never at construction.

        The Cover Art Archive client learned this the expensive way: a header fixed when the
        client was made goes on reporting the contact the settings tab was changed away from.
        Wikimedia asks every caller to identify itself, and this is the same string MusicBrainz
        is given.
        """
        return Config.musicbrainz_user_agent() or f"jimbrainz/{__version__}"

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

    async def candidates(self, artist: dict) -> list[dict]:
        """
        Every picture the three sources offer for this artist, best source first.

        `artist` is a MusicBrainz artist as looked up with url-rels. Each source is allowed to
        fail on its own: a Wikidata outage costs the Commons portrait and leaves TheAudioDB's
        banner, which is the behaviour an artist page wants.
        """
        relations = artist.get("relations") or []
        found = list(from_relations(relations))

        row = await self.theaudiodb(artist.get("id") or "")
        if row:
            found = list(from_theaudiodb(row)) + found

        entity_id = wikidata_id(relations)
        if entity_id:
            entity = await self.wikidata(entity_id)
            if entity:
                found += list(from_wikidata(entity))

        return found

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
            logger.warning(f"an artist image answered {response.status_code}")
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
