"""
Asking Last.fm's API (2.1.36 - notes/lastfm.md) - the I/O half of src/lastfm.py, which says what each answer is.

Only reads, so only LASTFM_API_KEY: every method deadwax asks needs no authentication beyond the key, and nothing
here is signed, so there is no shared secret to set. One request shape - a GET of
https://ws.audioscrobbler.com/2.0/?method=...&api_key=...&format=json - and one client: 8 s (5 s to connect), and 8 s
for each answer as a whole, so one trickling in doesn't hold a turn; redirects NOT followed; the answer read a piece
at a time and refused past MAX_BYTES, never read whole first. Every request carries `deadwax/<version>` as its user
agent and nothing more: never Config.musicbrainz_user_agent(), which carries MUSICBRAINZ_EMAIL's address - MusicBrainz
and Wikimedia ask callers for one, Last.fm doesn't.

THE KEY IS IN THE QUERY, so no address is ever logged or raised: this logs a method's name and what came of it in its
own words, and never says an httpx exception (whose words carry the URL). httpx's own request lines are kept out of
the log by src/logger.py. Last.fm's own words, kept from a refusal, have the key taken out (src/lastfm.py cleaned).

POLITE (Last.fm's terms give no number):
  - at most PER_SECOND requests start in any one second and IN_FLIGHT are under way at once; a request waits its
    turn up to TURN_WAIT_S, else it is Unreachable ("busy");
  - Limited (error 29, an HTTP 429): nothing is asked for LIMITED_PAUSE_S, each ask meanwhile Unreachable at once -
    said once, at info, in the container's log;
  - a request waiting its turn sends nothing once a 29 or a refusal has come, or the key has been removed or replaced
    (each look for a turn asks first - _stopped);
  - the pace, the pause and the hour a refusal is held are timed on the monotonic clock, never the wall clock, which
    can be set back or on.

REFUSED (error 10 or 26 - the key itself): held in memory, with Last.fm's words and when. While it is held - an hour,
or until LASTFM_API_KEY is saved, reverted or removed in Server settings (forget_refusal) - nothing is asked: each ask
is that Refused at once. After the hour, ONE ask tries again, the rest still Refused until it answers. The first
refusal says so once in the event log; state() is what /deadwax/me tells the app.
"""

import asyncio
import time
from collections import deque

import httpx

from src import __version__
from src.config import Config
from src.lastfm import (Answer, Limited, NotKnown, Outcome, Refused, Unreachable, classify, refused_event)
from src.logger import logger

API_URL = "https://ws.audioscrobbler.com/2.0/"
TIMEOUT = httpx.Timeout(8.0, connect=5.0)
#? each answer as a whole - a request holds a turn no longer than this
FETCH_DEADLINE_S = 8.0
#? a trimmed answer is 1-15 KB; Last.fm's own for 50 top tracks are tens of KB
MAX_BYTES = 512 * 1024

PER_SECOND = 5
IN_FLIGHT = 4
TURN_WAIT_S = 2.0
#? how often a request waiting its turn looks again
TURN_TICK_S = 0.05

LIMITED_PAUSE_S = 60.0
REFUSED_HOLD_S = 3600.0


def user_agent() -> str:
    return f"deadwax/{__version__}"


class LastfmClient:
    def __init__(self, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self._client: httpx.AsyncClient | None = None
        #? the tests' stand-in for the network
        self.transport = transport
        #? the clocks and the wait, all the tests' to replace. The pace, the pause and the hold are timed on the one
        #? that only goes forward: the wall clock can be set back or on (NTP, a sleeping machine), and on it a pause
        #? could last an hour or none. The wall clock is only when a refusal came - its HH:MM in Server settings.
        self.monotonic = time.monotonic
        self.clock = time.time
        self.sleep = asyncio.sleep
        self.refusal: Refused | None = None
        #? when the refusal came, on the monotonic clock: the hour it is held is timed from this
        self.refused_since = 0.0
        self._retrying = False
        self.limited_until = 0.0
        self._starts: deque[float] = deque()
        self._in_flight = 0

    def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            #? a redirect is never followed: the one address deadwax asks should simply answer
            self._client = httpx.AsyncClient(follow_redirects=False, timeout=TIMEOUT, transport=self.transport)
        return self._client

    async def close_client(self) -> None:
        if self._client is not None:
            await self._client.aclose()

    # ----- what the app is told ----------------------------------------------------------------------------------

    def held(self) -> Refused | None:
        """The refusal held, while it is - an hour from when Last.fm last refused the key."""
        if self.refusal is not None and self.monotonic() - self.refused_since < REFUSED_HOLD_S:
            return self.refusal
        return None

    def state(self) -> str:
        """/deadwax/me's `lastfm`: "off" with no key, "refused" while a refusal is held, else "on"."""
        if not Config.lastfm_key():
            return "off"
        return "refused" if self.held() else "on"

    def forget_refusal(self) -> None:
        """LASTFM_API_KEY was saved, reverted or removed: whatever Last.fm said of the old one no longer holds."""
        if self.refusal is not None:
            logger.info("LASTFM_API_KEY changed: deadwax will ask Last.fm with it from the next request")
        self.refusal = None

    # ----- asking ------------------------------------------------------------------------------------------------

    async def ask(self, method: str, params: dict[str, str]) -> Outcome:
        """Last.fm's answer to `method` with `params` (never the key, which this adds), as src/lastfm.py classifies
        it. Never raises, but for a cancellation."""
        key = Config.lastfm_key()
        if not key:
            return Unreachable("no LASTFM_API_KEY")
        retry = False
        if self.refusal is not None:
            if self._retrying or self.monotonic() - self.refused_since < REFUSED_HOLD_S:
                return self.refusal
            #? the hour is up: this ask is the one that tries again
            self._retrying = retry = True
        try:
            stopped = await self._turn(key, retry)
            if stopped is not None:
                return stopped
            try:
                outcome = await self._fetch(method, params, key)
            finally:
                self._in_flight -= 1
        finally:
            if retry:
                self._retrying = False
        #? an answer to a key since replaced in Server settings says nothing of the new one
        if Config.lastfm_key() == key:
            self._settle(method, outcome, retry)
        return outcome

    async def _turn(self, key: str, retry: bool) -> Outcome | None:
        """None once a turn is taken: fewer than IN_FLIGHT under way and fewer than PER_SECOND begun in the second
        before now - waited for up to TURN_WAIT_S, else Unreachable("busy"). Nothing is awaited between looking and
        taking it, so two asks can't take one turn - and each look first asks whether to send at all, so an ask that
        waited through a 29, a refusal or the key's removal sends nothing (_stopped)."""
        give_up = self.monotonic() + TURN_WAIT_S
        while True:
            stopped = self._stopped(key, retry)
            if stopped is not None:
                return stopped
            now = self.monotonic()
            while self._starts and now - self._starts[0] >= 1.0:
                self._starts.popleft()
            if self._in_flight < IN_FLIGHT and len(self._starts) < PER_SECOND:
                self._in_flight += 1
                self._starts.append(now)
                return None
            if now >= give_up:
                return Unreachable("busy")
            await self.sleep(min(TURN_TICK_S, give_up - now))

    def _stopped(self, key: str, retry: bool) -> Outcome | None:
        """Why nothing may be sent now, if anything: the key removed or replaced since the ask began, the pause after
        a 29, or a refusal that came while it waited (the ask retrying after the hour is the one ask a refusal lets
        through)."""
        if Config.lastfm_key() != key:
            return Unreachable("LASTFM_API_KEY changed while the request waited")
        if self.monotonic() < self.limited_until:
            return Unreachable("paused: Last.fm asked deadwax to slow down")
        if self.refusal is not None and not retry:
            return self.refusal
        return None

    async def _fetch(self, method: str, params: dict[str, str], key: str) -> Outcome:
        query = {"method": method, **params, "api_key": key, "format": "json"}
        headers = {"User-Agent": user_agent(), "Accept": "application/json"}
        try:
            async with asyncio.timeout(FETCH_DEADLINE_S):
                async with self._http().stream("GET", API_URL, params=query, headers=headers) as response:
                    if 300 <= response.status_code < 400:
                        return Unreachable(f"a redirect ({response.status_code}), not followed")
                    body = bytearray()
                    async for piece in response.aiter_bytes():
                        body += piece
                        if len(body) > MAX_BYTES:
                            return Unreachable(f"an answer over {MAX_BYTES // 1024} KB, refused")
                    return classify(response.status_code, bytes(body), self.clock(), key)
        except TimeoutError:
            return Unreachable(f"no answer in {FETCH_DEADLINE_S:g} s")
        except httpx.HTTPError as e:
            #? its name only: an httpx error's words carry the URL, and the key in its query
            return Unreachable(type(e).__name__)
        except Exception as e:
            logger.warning(f"Last.fm {method}: a fault in deadwax asking it ({type(e).__name__})")
            return Unreachable(f"a fault in deadwax ({type(e).__name__})")

    def _settle(self, method: str, outcome: Outcome, retry: bool) -> None:
        """What an answer changes: a refusal held (said once in the event log), a pause, a refusal let go."""
        if isinstance(outcome, Refused):
            first = self.refusal is None
            self.refusal = outcome
            self.refused_since = self.monotonic()
            if first:
                logger.warning(refused_event(outcome), extra={"frontend": True})
            else:
                logger.info(f"Last.fm still refuses LASTFM_API_KEY (error {outcome.error}): asked again in an hour")
            return
        if isinstance(outcome, (Answer, NotKnown)):
            if retry and self.refusal is not None:
                logger.info("Last.fm takes LASTFM_API_KEY again")
                self.refusal = None
            return
        if isinstance(outcome, Limited):
            if self.monotonic() >= self.limited_until:
                logger.info(f"Last.fm asked deadwax to slow down ({method}, {outcome.why}): nothing is asked of it "
                            f"for {LIMITED_PAUSE_S:g} s")
            self.limited_until = self.monotonic() + LIMITED_PAUSE_S
            return
        logger.info(f"Last.fm {method}: no answer - {outcome.why}")


lastfm = LastfmClient()
