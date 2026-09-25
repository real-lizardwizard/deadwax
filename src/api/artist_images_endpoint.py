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

from urllib.parse import quote

import httpx

from src import __version__
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
        return Config.musicbrainz_user_agent() or f"deadwax/{__version__}"

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
