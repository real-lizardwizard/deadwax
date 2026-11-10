"""
Asking Wikidata and Wikipedia for a description (2.0.13) - the I/O half of src/descriptions.py.

Two small JSON requests per description, each with deadwax's user agent (the one MusicBrainz is given,
built per request - Wikimedia asks every caller to identify itself): Wikidata's wbgetentities for the
item's English page and its English one-line description, the subtitle (the enwiki sitelink and the `en`
description alone, so a band's answer is a few hundred bytes rather than the entity's whole JSON), then
Wikipedia's REST summary of that page.

Three outcomes, kept apart so a bad minute is never kept as "there is none" for days: an answer (the
payload), a definite NO (a 404, an item Wikidata doesn't have) - None - and a failure (nothing answered,
a 5xx, a 429, something that wasn't JSON), raised as Unreachable, which the route keeps nothing of.

Its own client rather than the artist images' (src/api/artist_images_endpoint.py): shorter patience, since
a page is waiting on it.
"""

import httpx

from src import __version__
from src.config import Config
from src.descriptions import WIKIDATA_ENTITY, summary_url
from src.logger import logger

#? A page waits for this (the description fills in, the page never blocks on it), so it gives up sooner
#? than the image picker's 15 s
TIMEOUT = httpx.Timeout(8.0, connect=5.0)


class Unreachable(Exception):
    """Wikidata or Wikipedia gave no usable answer - nothing to keep, ask again next time."""


class WikipediaClient:
    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            #? Wikipedia answers a title that is a redirect with a 302 to the page's canonical title
            self._client = httpx.AsyncClient(follow_redirects=True, timeout=TIMEOUT)
        return self._client

    async def close_client(self) -> None:
        if self._client is not None:
            await self._client.aclose()

    @staticmethod
    def user_agent() -> str:
        return Config.musicbrainz_user_agent() or f"deadwax/{__version__}"

    async def _json(self, url: str, what: str) -> dict | None:
        try:
            response = await self._http().get(url, headers={"User-Agent": self.user_agent(), "Accept": "application/json"})
        except httpx.HTTPError as e:
            raise Unreachable(f"{what} couldn't be reached: {str(e) or type(e).__name__}") from e
        if response.status_code == 404:
            return None
        if response.status_code != 200:
            raise Unreachable(f"{what} answered {response.status_code}")
        try:
            payload = response.json()
        except ValueError as e:
            raise Unreachable(f"{what} did not answer with JSON") from e
        if not isinstance(payload, dict):
            raise Unreachable(f"{what} answered with something that isn't an object")
        return payload

    async def entity(self, entity_id: str) -> dict | None:
        """wbgetentities' answer for one item's English page and description; None for an item Wikidata
        doesn't have."""
        payload = await self._json(WIKIDATA_ENTITY.format(entity_id), "Wikidata")
        error = (payload or {}).get("error")
        if isinstance(error, dict):
            if error.get("code") == "no-such-entity":
                return None
            raise Unreachable(f"Wikidata refused: {error.get('code') or 'an error'}")
        return payload

    async def summary(self, title: str) -> dict | None:
        """Wikipedia's REST summary of one page; None for a page it doesn't have."""
        payload = await self._json(summary_url(title), "Wikipedia")
        if payload is None:
            logger.debug(f"Wikipedia has no page {title!r}")
        return payload


wikipedia = WikipediaClient()
