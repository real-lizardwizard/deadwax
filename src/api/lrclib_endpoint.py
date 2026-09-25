"""
Asking LRCLIB for a track's lyrics.

LRCLIB (lrclib.net) is a free, open lyrics database with no key and no account, and it is the
one source with SYNCED lyrics for a large part of what people actually listen to. It is keyed on
what the tags already say - artist, title, album, duration - not on MusicBrainz ids, so it works
for an untagged library as well as a tagged one.

Two requests at most per artist name, in order:

  1. `/api/get` - an exact lookup, which LRCLIB matches on its own normalised names and a
     duration within two seconds. The right answer for the common case.
  2. `/api/search` - when the exact lookup misses, usually because the album title differs (a
     deluxe edition's longer name, or the single the song first appeared on). Its results are
     held to the same two seconds by `lyrics.choose_result()`, so a live version or a radio edit
     is never taken for the album track.

A 404 is "no lyrics for this" and comes back as None. Anything else going wrong raises
LyricsUnavailable, because "LRCLIB has nothing" and "LRCLIB didn't answer" call for opposite
responses - one is final, the other is worth trying again.
"""

import asyncio

import httpx

from src import __version__
from src.logger import logger
from src.lyrics import LyricsUnavailable, choose_result

BASE_URL = "https://lrclib.net"
HOMEPAGE = "https://github.com/real-lizardwizard/deadwax"

#? How long to wait before asking again after a 503 or 429, and so how many times to ask. A
#? Retry-After header is honoured when it is shorter than a few seconds.
RETRY_PAUSES = (1.0, 3.0)


def _retry_after(response: httpx.Response, default: float) -> float:
    try:
        return min(float(response.headers.get("retry-after", default)), 5.0)
    except ValueError:
        return default


class LrclibClient:
    def __init__(self):
        self.client: httpx.AsyncClient | None = None

    async def get_client(self) -> httpx.AsyncClient:
        if not self.client or self.client.is_closed:
            self.client = httpx.AsyncClient(
                base_url=BASE_URL,
                #? /api/get can go and ask LRCLIB's own upstream sources when it hasn't seen a
                #? track before, which takes a few seconds - generous, but not unbounded
                timeout=httpx.Timeout(connect=10.0, write=10.0, read=30.0, pool=10.0),
            )
        return self.client

    @staticmethod
    def user_agent() -> str:
        """What LRCLIB asks every client to send: the app, its version, and where it lives."""
        return f"deadwax/{__version__} ({HOMEPAGE})"

    async def close_client(self) -> None:
        if self.client and not self.client.is_closed:
            await self.client.aclose()
            self.client = None

    async def find(self, lookup: dict) -> dict | None:
        """
        LRCLIB's record for this track, or None if it has none. Raises LyricsUnavailable.

        `lookup` is what `lyrics.lookup_from_tags()` built: a title, the artist names to try in
        order (the track's own, then the album artist), the album, and the duration in seconds.
        """
        duration = lookup.get("duration") or 0

        for artist in lookup["artists"]:
            #? the exact lookup needs all four; without an album or a length, only search can help
            if lookup.get("album") and duration:
                found = await self._get("/api/get", {
                    "track_name": lookup["title"],
                    "artist_name": artist,
                    "album_name": lookup["album"],
                    "duration": round(duration),
                })
                if found:
                    return found

            results = await self._get("/api/search", {
                "track_name": lookup["title"], "artist_name": artist,
            })
            chosen = choose_result(results if isinstance(results, list) else [], lookup)
            if chosen:
                return chosen

        return None

    async def _get(self, path: str, params: dict):
        for attempt, pause in enumerate((*RETRY_PAUSES, None)):
            try:
                client = await self.get_client()
                response = await client.get(path, params=params, headers={"User-Agent": self.user_agent()})
            except httpx.HTTPError as e:
                logger.warning(f"LRCLIB could not be reached: {e}")
                raise LyricsUnavailable(f"LRCLIB could not be reached: {e}") from e

            #? "busy, ask again shortly" - which LRCLIB says with a 503 when it is being leaned on,
            #? as a bulk run does. Worth a short wait; anything else is not
            if response.status_code not in (429, 503) or pause is None:
                break

            await asyncio.sleep(_retry_after(response, pause))

        if response.status_code == 404:
            return None

        if response.status_code >= 400:
            logger.warning(f"LRCLIB answered {response.status_code} for {path}")
            raise LyricsUnavailable(f"LRCLIB answered {response.status_code}")

        try:
            return response.json()
        except ValueError as e:
            raise LyricsUnavailable("LRCLIB sent something that isn't JSON") from e


#? One client for the process, like the Cover Art Archive's. Both the library route and the
#? poller use it - the poller to fetch lyrics as an album is filed - and the app's lifespan
#? closes it.
lrclib = LrclibClient()
