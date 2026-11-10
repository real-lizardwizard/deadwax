import asyncio
import json
import re
import time
import httpx
from collections import deque, OrderedDict
from typing import NamedTuple
from src.artists import artist_query
from src.config import Config
from src.logger import logger
class MusicBrainzUnavailable(Exception):
    """
    Raised when MusicBrainz couldn't be reached at all, as opposed to returning no matches.

    The distinction matters to whoever is staring at the screen: "no results" means try a
    different search, "unreachable" means wait and try the same one again.

    `busy` (2.0.0-player.55): MusicBrainz answered, saying it is shedding searches just now (a 503
    with `x-ratelimit-who: search-shed`, or its "currently busy" words) - the app's Search says
    "MusicBrainz is busy just now" rather than that it isn't answering.
    """

    def __init__(self, *args, busy: bool = False):
        super().__init__(*args)
        self.busy = busy


class MusicBrainzRejected(Exception):
    """
    A QUICK search (2.0.0-player.55, the app's Search) MusicBrainz refused as malformed - a 400. Said as
    "That search couldn't be read - try other words", never as an outage: the same words
    would be refused again, so the page offers no Try again. Every other path keeps a 400 as it was.
    """


class Patience(NamedTuple):
    """How long a request keeps trying (2.0.0-player.55): its attempts, and the pauses between them."""
    attempts: int
    #? after a 503 or a 429 - MusicBrainz shedding, or the rate limit
    busy_pause: float
    #? after a connection that failed or timed out
    network_pause: float


#? The app's Search (/fully_search with `quick`, /songs, /artists): somebody is looking at a list, and
#? three kinds of search go at once - so a search gives up after three attempts and says so, rather than
#? the ten everything else keeps (album pages, the download flow): about eight seconds while MusicBrainz is
#? turning searches away (a 503 or 429 answers at once), but each attempt still waits out the client's own
#? timeouts (_new_client: connect 10 s, read 30 s), so a connection that hangs takes up to ~1.5 minutes.
SEARCH_PATIENCE = Patience(attempts=3, busy_pause=2.0, network_pause=1.0)


def _shedding(response) -> bool:
    """Whether a 503 is MusicBrainz shedding searches: its header says so, or its words do."""
    headers = getattr(response, "headers", None) or {}
    try:
        who = headers.get("x-ratelimit-who") or ""
    except Exception:
        who = ""
    text = str(getattr(response, "text", "") or "")
    return who.strip().lower() == "search-shed" or "currently busy" in text.lower()


def raise_for_search(answer: dict, quick: bool) -> None:
    """
    A search that failed, as the exception its route answers (2.0.0-player.55): a quick search's 400 is
    MusicBrainzRejected; anything else MusicBrainzUnavailable, `busy` when MusicBrainz said it was shedding.
    """
    reason = answer.get("error", "unknown error") if isinstance(answer, dict) else "no answer"
    if quick and isinstance(answer, dict) and answer.get("code") == 400:
        raise MusicBrainzRejected(reason)
    raise MusicBrainzUnavailable(reason, busy=bool(isinstance(answer, dict) and answer.get("busy")))


class RateLimit:
    max_requests = 4
    time_window = 5.0

    def __init__(self):
        self.request_times = deque(maxlen=self.max_requests)
        #? (2.0.0-player.55) waiters take turns - see wait(). Made lazily, for the loop that runs it
        self._turns: asyncio.Lock | None = None
        self._turns_loop: asyncio.AbstractEventLoop | None = None
        #? the clock and the sleep wait() runs on - None for time.monotonic and asyncio.sleep, looked up as it
        #? waits; tests/test_musicbrainz_ratelimit.py hands it a clock of its own
        self.clock = None
        self.sleep = None

    def _now(self) -> float:
        return (self.clock or time.monotonic)()

    def _turn(self) -> asyncio.Lock:
        """
        The lock waiters take turns by, made for the RUNNING event loop: this limiter is a class attribute
        of MusicBrainzClient, shared by every loop in the process (a test's asyncio.run, each TestClient),
        and an asyncio.Lock that has waited in one loop raises RuntimeError when contended from another.
        """
        loop = asyncio.get_running_loop()
        if self._turns is None or self._turns_loop is not loop:
            self._turns = asyncio.Lock()
            self._turns_loop = loop
        return self._turns

    async def wait(self) -> None:
        #? (2.0.0-player.55) Under a lock held across the sleep. Without it, waiters arriving together
        #? each read the same oldest send, computed the same wake time and fired together - six sends in
        #? one five-second window, measured - and the app's Search asks three kinds at once, so that
        #? would be the normal case. With it they take turns, and no window holds more than four. A
        #? waiter cancelled while it sleeps (a search abandoned) lets the lock go and takes no turn.
        async with self._turn():
            curr_time = self._now()

            if len(self.request_times) >= self.max_requests:
                oldest_time = self.request_times[0]
                time_since_oldest = curr_time - oldest_time

                if time_since_oldest < self.time_window:
                    wait_time = self.time_window - time_since_oldest
                    #? Deliberately NOT a frontend warning. This is the throttle doing its job -
                    #? MusicBrainz asks for about a request a second and we hold ourselves to it -
                    #? so it fires constantly during any normal burst, and telling the user their
                    #? own politeness is a problem made a working search look broken. The interface
                    #? already says "asking MusicBrainz..." while this waits.
                    logger.debug(f"holding off {wait_time:.1f}s to stay inside the MusicBrainz rate limit")
                    await (self.sleep or asyncio.sleep)(wait_time)
                    curr_time = self._now()

            self.request_times.append(curr_time)

    def quiet(self, seconds: float) -> bool:
        """
        Whether a refresh of an old saved answer may go now (2.0.0-player.54): nothing asked of
        MusicBrainz for `seconds`, and room in the window - so wait() would not hold it. Asked with
        at least the whole window (_refresh_saved), it means the window is empty: the refresh is the
        only request in it, and the questions asked next still find three turns of the four.
        Synchronous, so nothing can slip in between this saying yes and the refresh taking its turn.
        """
        now = self._now()
        if self.request_times and now - self.request_times[-1] < seconds:
            return False
        return len(self.request_times) < self.max_requests or now - self.request_times[0] >= self.time_window


#? The whitespace a search query's runs of may be closed up in a key (2.0.0-player.54): what
#? Lucene's query parser splits terms on, ASCII only - not a no-break space, which it reads as part
#? of a word - and never a whitespace character right after a backslash, which escapes it.
_QUERY_SPACE_RUN = re.compile(r"(?<!\\)[ \t\r\n]+")


def same_question(name: str, value) -> str:
    """
    A param as a cache key holds it: as written, but for a search's `query`, whose runs of whitespace
    are one space and whose ends are trimmed - which cannot change what MusicBrainz answers, so
    `Massive  Attack ` and `Massive Attack` are one question asked once. Nothing else is touched:
    never the case (Lucene's AND, OR and NOT are operators only in capitals), never punctuation, never
    another param. An escaped space (`\\ `) is kept as it is.
    """
    text = str(value)
    if name != "query":
        return text
    text = _QUERY_SPACE_RUN.sub(" ", text).lstrip(" \t\r\n")
    if text.endswith(" ") and not text.endswith("\\ "):
        text = text[:-1]
    return text


class ResponseCache:
    """
    Recently fetched MusicBrainz responses, keyed on the request that produced them.

    Worth having because the questions repeat far more than they change. Opening the metadata
    editor asks for a release-group search and then the releases of the best few groups; the
    first group's releases are ALSO fetched by fully_search as `best-match-releases`, so that
    one was fetched twice every single time. Stepping through the review queue and back asks the
    same questions again, and MusicBrainz is rate limited to roughly one request a second - so
    every avoided request is a second of someone waiting.

    The data is nearly static. A release group's pressings do not change while you are looking
    at them, so a stale answer is not a real risk on this timescale.

    Bounded rather than unbounded: a release list with recordings included is a large payload
    (the Black Album's group runs to hundreds of releases), and a long-running container asking
    about a big library would otherwise hold every one it had ever seen.

    **Only successful responses are ever stored** - see request_with_retries. It returns an
    error dict rather than raising when it gives up, and caching that would pin a transient
    MusicBrainz outage in place for the whole TTL, turning a bad minute into a bad hour.

    **On disk too, since 2.0.0-player.54** (`disk`, a src/musicbrainz_cache.SavedAnswers): every
    answer stored here is kept there as well, under the same key, so a question asked again after
    the hour - or after a restart - is answered without asking MusicBrainz. None (every test's,
    unless it says otherwise) is memory alone; the app's lifespan attaches the real one.
    """

    def __init__(self, ttl_seconds: float = 3600.0, max_entries: int = 64, disk=None):
        self.ttl = ttl_seconds
        self.max_entries = max_entries
        #? key -> (stored at, by time.monotonic - what the hour runs on; the answer; fetched at, by now() -
        #? what a paged browse's pages are matched on, see MusicBrainzClient._browse)
        self.entries: OrderedDict[tuple, tuple[float, dict, float]] = OrderedDict()
        self.hits = 0
        self.misses = 0
        self.disk = disk

    def now(self) -> float:
        """Wall time as the answers are stamped with it: the saved answers' clock when they're attached."""
        return self.disk.now() if self.disk is not None else time.time()

    @staticmethod
    def key(endpoint: str, params: dict) -> tuple:
        #? sorted so the same request written two ways is the same key - and a query's whitespace
        #? closed up, which can't change the answer either (same_question)
        return (endpoint, tuple(sorted((str(k), same_question(str(k), v)) for k, v in (params or {}).items())))

    @classmethod
    def disk_key(cls, endpoint: str, params: dict) -> str:
        """The same key, as the saved answers' file holds it."""
        return json.dumps(cls.key(endpoint, params), ensure_ascii=False)

    def get(self, endpoint: str, params: dict) -> dict | None:
        entry = self.entry(endpoint, params)
        return None if entry is None else entry[0]

    def entry(self, endpoint: str, params: dict) -> tuple[dict, float] | None:
        """The answer kept for this question and when it was fetched - or None."""
        key = self.key(endpoint, params)
        entry = self.entries.get(key)

        if entry is None:
            self.misses += 1
            return None

        stored_at, value, fetched_at = entry

        if time.monotonic() - stored_at > self.ttl:
            del self.entries[key]
            self.misses += 1
            return None

        #? touch, so the entries actually being used are the ones that survive eviction
        self.entries.move_to_end(key)
        self.hits += 1
        return value, fetched_at

    def put(self, endpoint: str, params: dict, value: dict, fetched_at: float | None = None) -> None:
        key = self.key(endpoint, params)
        self.entries[key] = (time.monotonic(), value, self.now() if fetched_at is None else fetched_at)
        self.entries.move_to_end(key)

        while len(self.entries) > self.max_entries:
            self.entries.popitem(last=False)

    def clear(self) -> None:
        self.entries.clear()
        self.hits = 0
        self.misses = 0


class Browse:
    """
    One read of a paged browse - an artist's discography, a release group's pressings - as ONE answer
    (2.0.0-player.54). Each page is its own question to MusicBrainz, cached and saved under its own key,
    so before this a browse could be put together from pages of different ages: a refresh that replaced
    the first page and failed on the second, the size trim dropping one page and keeping the next, or a
    look between two refreshes, joined today's first page to a month-old second - and an edit on
    MusicBrainz that moved the page boundary meanwhile showed an album twice, or not at all (the review
    reproduced 150 release groups with only 149 different). So every page of a browse carries the first
    page's `fetched_at` - the browse's STAMP: pages asked together are saved under it together - and a
    read takes pages from the caches only while their stamp is the first page's (`cached`). A page of
    another age, or one in no cache after pages that were (`mixed`), and the read is thrown away and
    made again from MusicBrainz, every page (`live`) - which is also how a read whose first page came
    from MusicBrainz goes on. `stale`: a page read from disk is old, so the whole browse is refreshed
    behind it as one (`refreshing`: every page asked, kept back in `answers`, and saved together, under
    one stamp, only when every page came).
    """

    def __init__(self, *, live: bool = False, refreshing: bool = False):
        self.refreshing = refreshing
        self.live = live or refreshing
        self.stamp: float | None = None
        self.mixed = False
        self.stale = False
        self.answers: list[tuple[str, dict, dict]] = []

    def cached(self, value: dict, fetched_at: float, stale: bool) -> dict:
        """A page from memory or the disk - this browse's own while it was fetched with the first page."""
        if self.stamp is None:
            self.stamp = fetched_at
        elif fetched_at != self.stamp:
            self.mixed = True
        self.stale = self.stale or stale
        return value


class BrowseRefresh(NamedTuple):
    """A whole browse queued to be asked again behind its old saved pages (MusicBrainzClient._browse)."""
    endpoint: str
    params: dict
    items: str
    count: str
    stop_at: int | None


def _answered(answer) -> bool:
    return isinstance(answer, dict) and answer.get("status") != "failed"


def _distinct(items) -> list[dict]:
    """Each id once, the first kept: the pages of one browse are asked seconds apart, and an edit on
    MusicBrainz between them can still move an item across their boundary (2.0.0-player.54)."""
    seen, kept = set(), []
    for item in items:
        key = item.get("id") if isinstance(item, dict) else None
        if key is not None:
            if key in seen:
                continue
            seen.add(key)
        kept.append(item)
    return kept


class MusicBrainzClient:
    RETRIES = 10
    rate_limit = RateLimit()
    #? shared for the process, like the rate limiter and for the same reason: both are about
    #? how much this application as a whole asks of MusicBrainz, not any one client object
    cache = ResponseCache()

    #? (2.0.0-player.54) refreshing an old saved answer, behind it: only once nobody's question is on its
    #? way and nothing has been asked of MusicBrainz for a whole window of the rate limiter (5 s), and
    #? never less than REFRESH_QUIET_SECONDS (checked every REFRESH_POLL_SECONDS), one at a time, at most
    #? REFRESH_QUEUE_MAX waiting - see _refresh_saved
    REFRESH_QUIET_SECONDS = 2.0
    REFRESH_POLL_SECONDS = 0.5
    REFRESH_QUEUE_MAX = 100
    #? a refresh that failed for its own question alone - MusicBrainz answered, rejecting the search as
    #? malformed (400) or finding nothing at the address any more, something since deleted (404): that
    #? one is dropped and the rest go on, where any other failure means MusicBrainz is away
    REFRESH_ONE_QUESTION_FAILURES = (400, 404)

    def __init__(self):
        self.client: httpx.AsyncClient | None = None
        #? the refreshes' own connection, so one never holds the connection a question is waiting for
        self.refresh_client: httpx.AsyncClient | None = None
        #? questions somebody is waiting on MusicBrainz for, right now - a refresh goes only at none
        self.asking = 0
        #? old saved answers to ask for again: key -> (endpoint, params), oldest first
        self.refreshes: OrderedDict[tuple, tuple[str, dict]] = OrderedDict()
        self.refresher: asyncio.Task | None = None

    async def get_client(self) -> httpx.AsyncClient:
        logger.info("getting MusicBrainz httpx AsyncClient")

        if not self.client or self.client.is_closed:
            self.client = self._new_client()

        return self.client

    async def get_refresh_client(self) -> httpx.AsyncClient:
        """The refreshes' connection (2.0.0-player.54): the same user agent and limits, its own socket."""
        if not self.refresh_client or self.refresh_client.is_closed:
            self.refresh_client = self._new_client()
        return self.refresh_client

    def _new_client(self) -> httpx.AsyncClient:
        #? built from MUSICBRAINZ_EMAIL and the running version - see config.py. Fixed for
        #? the life of this client, which the settings route drops when the contact changes.
        user_agent = Config.musicbrainz_user_agent()
        if not user_agent:
            logger.error(
                "MUSICBRAINZ_EMAIL is not set - MusicBrainz asks for a contact address with "
                "every request. Set it in Server settings (Connections).",
                extra={"frontend": True, "src": "musicbrainz"},
            )
            raise ValueError("MUSICBRAINZ_EMAIL is not configured")
        logger.info(f" user agent is {user_agent}")
        return httpx.AsyncClient(
            base_url="https://musicbrainz.org/ws/2",
            headers={
                "User-Agent": user_agent,
                "Accept": "application/json"
            },
            timeout=httpx.Timeout(
                connect=10.0, #init connection
                write=10.0,  #request send
                read=30.0, #request answer
                pool=10.0   #connection from pool
            ),
            limits=httpx.Limits(
                max_connections=1,
                max_keepalive_connections=1,
                keepalive_expiry=60.0
            ),
            http2=True #saw mb supported it ans given it all seems to struggle i figure its better
        )

    async def close_client(self) -> None:
        """Both connections dropped (the settings changed the contact, or shutting down)."""
        await self._close_main_client()
        await self._close_refresh_client()

    async def _close_main_client(self) -> None:
        if self.client is not None:
            try:
                await self.client.aclose()

            except Exception:
                pass  

            self.client = None

    async def _close_refresh_client(self) -> None:
        if self.refresh_client is not None:
            try:
                await self.refresh_client.aclose()
            except Exception:
                pass
            self.refresh_client = None

    async def stop_refreshing(self) -> None:
        """Shutting down: the waiting refreshes dropped, and one under way called off."""
        self.refreshes.clear()
        task, self.refresher = self.refresher, None
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass


    async def request_with_retries(self, endpoint: str, params: dict, *, disk: bool = True,
                                   refreshing: bool = False, browse: Browse | None = None,
                                   patience: Patience | None = None) -> dict:
        """
        Every MusicBrainz request deadwax makes goes through here (a test holds it to that), so every
        caller gets the caches for free: memory first (an hour), then - since 2.0.0-player.54 - the
        answers saved on disk, then MusicBrainz.

        `disk=False` leaves the saved answers out, reading and writing: the connection check (ping),
        which an answer kept from last week would only lie for. `refreshing` is _refresh_saved asking
        again for an old saved answer, behind it: no cache read, one attempt, its own connection, and
        nothing said in the event log - nobody is waiting for it. `browse` is one page of a paged
        browse, read with the pages around it as one answer - see Browse and _browse.

        `patience` (2.0.0-player.55) is how long MusicBrainz is asked before giving up: SEARCH_PATIENCE for
        the app's Search (three attempts, short pauses), None for everything else - RETRIES and the pauses
        as they always were. It changes nothing before MusicBrainz: the caches answer as ever.
        """
        if refreshing or (browse is not None and browse.refreshing):
            if browse is not None and browse.answers:
                #? a whole browse asked again: every page after the first waits for a quiet turn of its own
                await self._refresh_turn()
            answer = await self._ask(endpoint, params, disk=disk, refreshing=True, keep=browse is None)
            if browse is not None and _answered(answer):
                browse.answers.append((endpoint, dict(params or {}), answer))
            return answer

        live = browse is not None and browse.live
        if not live:
            #? Before the rate limiter, not after: the whole point is to not spend a turn of the
            #? budget - and therefore up to a second of somebody's time - on a question already
            #? answered. See ResponseCache for what does and does not get stored.
            entry = self.cache.entry(endpoint, params)
            if entry is not None:
                logger.debug(f"MusicBrainz cache hit for {endpoint}")
                return entry[0] if browse is None else browse.cached(*entry, stale=False)

        #? somebody is waiting from here on - while the disk is read too - so no refresh goes meanwhile
        self.asking += 1
        try:
            if disk and not live:
                saved = await self._saved_answer(endpoint, params, browse)
                if saved is not None:
                    return saved

            if browse is not None:
                if browse.stamp is not None and not browse.live:
                    #? a page in no cache after pages that were: asked now, it would be joined to them -
                    #? so nothing is asked, and the browse is read again from MusicBrainz, every page
                    browse.mixed = True
                    return {}
                if browse.stamp is None:
                    #? the first page, from MusicBrainz: so is every page after it, under its stamp
                    browse.live = True
                    browse.stamp = self.cache.now()

            return await self._ask(endpoint, params, disk=disk,
                                   fetched_at=browse.stamp if browse is not None else None, patience=patience)
        finally:
            self.asking -= 1

    async def _saved_answer(self, endpoint: str, params: dict, browse: Browse | None = None) -> dict | None:
        """The answer saved on disk for this question, put back in memory - and, when it is old, a
        refresh queued behind it (a browse's page: the browse refreshed whole, by _browse). None when
        there is none (or no disk layer)."""
        saved_answers = self.cache.disk
        if saved_answers is None:
            return None
        found = await saved_answers.get(ResponseCache.disk_key(endpoint, params))
        if found is None:
            return None
        payload, fetched_at = found
        self.cache.put(endpoint, params, payload, fetched_at=fetched_at)
        if browse is not None:
            logger.info(f"MusicBrainz answer for {endpoint} from the saved answers on disk, nothing asked")
            return browse.cached(payload, fetched_at, saved_answers.is_stale(params, fetched_at))
        if saved_answers.is_stale(params, fetched_at):
            logger.info(f"MusicBrainz answer for {endpoint} from the saved answers on disk, nothing asked - "
                        f"it is old, so a new one is asked for behind it")
            self._queue_refresh(endpoint, params)
        else:
            logger.info(f"MusicBrainz answer for {endpoint} from the saved answers on disk, nothing asked")
        return payload

    def _queue_refresh(self, endpoint: str, params: dict) -> None:
        """An old saved answer to ask for again, once - never more than REFRESH_QUEUE_MAX waiting."""
        self._queue(ResponseCache.key(endpoint, params), (endpoint, dict(params or {})))

    def _queue_browse_refresh(self, browse: BrowseRefresh) -> None:
        """A whole browse to ask for again, once - one place in the queue, however many pages it has."""
        self._queue(("browse",) + ResponseCache.key(browse.endpoint, browse.params), browse)

    def _queue(self, key: tuple, item) -> None:
        if key in self.refreshes or len(self.refreshes) >= self.REFRESH_QUEUE_MAX:
            return
        self.refreshes[key] = item
        if self.refresher is None or self.refresher.done():
            self.refresher = asyncio.get_running_loop().create_task(self._refresh_saved())

    async def _refresh_turn(self) -> None:
        """Until a refresh may take a turn: nobody's question on its way, and the limiter quiet (_refresh_saved)."""
        quiet = max(self.REFRESH_QUIET_SECONDS, self.rate_limit.time_window)
        while self.asking or not self.rate_limit.quiet(quiet):
            await asyncio.sleep(self.REFRESH_POLL_SECONDS)

    async def _refresh_saved(self) -> None:
        """
        Ask again for the old saved answers queued, one at a time, at the lowest priority: each waits
        until nobody's question is on its way (`asking`) and nothing at all has been asked of MusicBrainz
        for a whole window of the rate limiter (and never less than REFRESH_QUIET_SECONDS: a question
        chained on another follows it within milliseconds, so the quiet keeps a refresh from slipping
        between them) - so a refresh never takes a turn somebody is waiting for, and at most ONE refresh
        is ever in the limiter's window: a burst of up to three questions right after one goes at once,
        and only a fourth waits for the refresh's turn to pass (at most the window, 5 s). A hundred
        waiting take about nine minutes. A new answer replaces the saved one (in memory too); the screen
        showing the old one is not redrawn.

        A failure keeps the saved answer. One for that question alone (REFRESH_ONE_QUESTION_FAILURES:
        MusicBrainz answered 400 or 404) drops only it and the rest go on; any other (no connection, a
        503, a 429, a 403, a 5xx) means MusicBrainz is away, and drops every refresh waiting - each is
        queued again the next time its answer is read from disk.

        A browse (BrowseRefresh) is one refresh of every page, each page taking a turn of its own as
        above, saved only when every page has come - so its pages are never of different ages (Browse).
        """
        while self.refreshes:
            await self._refresh_turn()
            #? emptied while it waited (Clear, or stopping): nothing to ask
            if not self.refreshes:
                return
            _, item = self.refreshes.popitem(last=False)
            if isinstance(item, BrowseRefresh):
                endpoint = item.endpoint
                _, answer = await self._browse(*item, refreshing=True)
                answer = answer or {}
            else:
                endpoint, params = item
                answer = await self.request_with_retries(endpoint, params, refreshing=True)
            if not isinstance(answer, dict) or answer.get("status") == "failed":
                why = (answer or {}).get("error", "no answer") if isinstance(answer, dict) else "no answer"
                if isinstance(answer, dict) and answer.get("http_status") in self.REFRESH_ONE_QUESTION_FAILURES:
                    logger.info(
                        f"couldn't refresh an old saved MusicBrainz answer for {endpoint} ({why}) - the saved one "
                        f"is kept, and the rest waiting go on"
                    )
                    continue
                dropped = len(self.refreshes)
                self.refreshes.clear()
                logger.info(
                    f"couldn't refresh an old saved MusicBrainz answer ({why}) - "
                    f"the saved one is kept, and {dropped} more waiting are left until they are next used"
                )
                return

    async def _ask(self, endpoint: str, params: dict, *, disk: bool = True, refreshing: bool = False,
                   keep: bool = True, fetched_at: float | None = None, patience: Patience | None = None) -> dict:
        """
        MusicBrainz asked, retrying what is worth retrying. Only request_with_retries calls this.
        `keep=False` stores nothing (a browse's refresh keeps its pages back until every one has come);
        `fetched_at` is the stamp the answer is stored with (a browse's pages share the first one's), now
        when left out. `patience` (2.0.0-player.55): its attempts and pauses instead of RETRIES and the
        usual ones, and no pause after the last attempt - a 503 that said MusicBrainz is shedding marks
        the failure `busy`.
        """
        logger.info("refreshing an old saved MusicBrainz answer" if refreshing else "requesting MusicBrainz")
        #? a refresh is asked once: dropped if MusicBrainz is away, and nobody is told - nobody is waiting
        attempts = 1 if refreshing else patience.attempts if patience is not None else self.RETRIES
        quick = patience is not None and not refreshing
        loud = {} if refreshing else {"frontend": True, "src": "musicbrainz"}
        connect = self.get_refresh_client if refreshing else self.get_client
        attempt = 0

        ping_error_obj = {
            "error": "Failed to get valid response from MusicBrainz after retries",
            "status": "failed",
            "code": "MAX_RETRIES_EXCEEDED"
        }

        while attempt < attempts:
            attempt += 1

            try:
                await self.rate_limit.wait()
                client = await connect()
                response = await client.get(
                    endpoint,
                    params=params
                )
                response.raise_for_status()

                #? The only place anything is cached, deliberately. Every other exit from this
                #? function is a failure that returns ping_error_obj, and storing one of those
                #? would keep serving "MusicBrainz is unreachable" for the whole TTL after it
                #? had come back - turning a bad minute into a bad hour. On disk too (2.0.0-player.54),
                #? where it would be a bad month: the same one place, the same successes.
                payload = response.json()
                if keep:
                    self.cache.put(endpoint, params, payload, fetched_at=fetched_at)
                    if disk and self.cache.disk is not None:
                        self.cache.disk.put(ResponseCache.disk_key(endpoint, params), payload, fetched_at=fetched_at)
                return payload
            
            except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout) as exc:
                #? (2.0.0-player.55) a search somebody is looking at pauses its patience's short while
                delay = patience.network_pause if quick else 2.0 + (attempt * 0.5)  # type: ignore[union-attr]

                if attempt < attempts:
                    logger.warning(f"Network error on attempt {attempt}. Retrying in {delay:.2f} seconds...", extra={"frontend": True, "src":"musicbrainz"})
                    logger.warning(f"Network error on attempt {attempt} Retrying in {delay:.2f} seconds...")
                    logger.warning(f"Error details: {type(exc).__name__}: {exc}")
                    
                    ping_error_obj["error"] =  "musicbrainz ping failed with connection error"
                    ping_error_obj["status"] =  "failed"
                    ping_error_obj["code"] =  "CONNECTION_ERROR"
                    

                #? only the connection that failed: a refresh's never takes down a question's, nor the reverse
                await (self._close_refresh_client() if refreshing else self._close_main_client())
                if quick:
                    #? ...and none after its last attempt; the failure said as a connection's, never as busy
                    ping_error_obj.update({"error": "musicbrainz ping failed with connection error",
                                           "status": "failed", "code": "CONNECTION_ERROR", "busy": False})
                    if attempt < attempts:
                        await asyncio.sleep(delay)
                    continue
                await asyncio.sleep(delay)

            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code
                if refreshing:
                    #? for _refresh_saved alone (only it sees a refresh's answer): whether MusicBrainz is
                    #? away, or answered about this one question (REFRESH_ONE_QUESTION_FAILURES)
                    ping_error_obj["http_status"] = status  # type: ignore

                if status == 503:
                    logger.warning("MusicBrainz returned 503 (overloaded), retrying...")
                    logger.warning(f"Response text: {exc.response.text[:200]}")
                    ping_error_obj["error"] =  "musicbrainz ping failed with 503 overloaded error, responded to ping but server currenty busy"
                    ping_error_obj["status"] =  "failed"
                    ping_error_obj["code"] = 503 # type: ignore
                    if quick:
                        #? (2.0.0-player.55) shedding searches, said so: the page words it as busy
                        ping_error_obj["busy"] = _shedding(exc.response)  # type: ignore
                        if attempt < attempts:
                            await asyncio.sleep(patience.busy_pause)  # type: ignore[union-attr]
                        continue
                    await asyncio.sleep(3.0) #shrugs
                    continue

                if status == 403: 
                    logger.error("MusicBrainz refused the request - usually the user agent. Check MUSICBRAINZ_EMAIL in Server settings (Connections)", extra=loud)
                    logger.error(f"Response text: {exc.response.text}")
                    ping_error_obj["error"] =  "musicbrainz ping failed with 403 forbidden error, connection was made but user agent / ip not accepted"
                    ping_error_obj["status"] =  "failed"
                    ping_error_obj["code"] = 403 # type: ignore
                    break
                    
                if status == 429:  
                    logger.warning("Rate limited by server (429), waiting 10s...")
                    logger.warning(f"Response text: {exc.response.text[:200]}")
                    ping_error_obj["error"] =  "musicbrainz ping failed with 429 rate limit error, responded to ping but server is rate limiting"
                    ping_error_obj["status"] =  "failed"
                    ping_error_obj["code"] = 429 # type: ignore
                    if quick:
                        ping_error_obj["busy"] = False  # type: ignore
                        if attempt < attempts:
                            await asyncio.sleep(patience.busy_pause)  # type: ignore[union-attr]
                        continue
                    await asyncio.sleep(6) #? this is just a fallback if the rate limit class is a little zesty 
                    continue

                if status == 404:
                    #? (2.0.13) nothing at that address - an id MusicBrainz doesn't have (a bad tag, an entity
                    #? merged away): as deterministic as a 400, so asked once, not ten times through the rate
                    #? limit; the caller tells it apart by its code (src/routes/describe.py keeps it as "none")
                    logger.info(f"MusicBrainz has nothing at {endpoint}")
                    ping_error_obj["error"] = "MusicBrainz has nothing at that address"
                    ping_error_obj["status"] = "failed"
                    ping_error_obj["code"] = 404  # type: ignore
                    break

                if status == 400:
                    #? A rejected QUERY, not an outage - deterministic, so retrying it ten
                    #? times just spends thirty seconds arriving at the same answer and then
                    #? reports "MusicBrainz is unreachable", which sends you looking at your
                    #? network instead of at your search. Matters more now that the search view
                    #? builds type-filter clauses: a syntax mistake has to say so.
                    logger.error(
                        f"MusicBrainz rejected that search as malformed - this is a problem "
                        f"with the query, not the connection ({exc.response.text[:160]})",
                        extra=loud,
                    )
                    ping_error_obj["error"] = "MusicBrainz rejected the search as malformed"
                    ping_error_obj["status"] = "failed"
                    ping_error_obj["code"] = 400  # type: ignore
                    break

                else:
                    ping_error_obj["error"] =  f"musicbrainz ping failed with uncaught HTTP error {status}, unknown"
                    ping_error_obj["status"] =  "failed"
                    ping_error_obj["code"] = "UNKNOWN_HTTP_ERROR" # type: ignore

                #? a refresh's is no error of anybody's - nobody is waiting for it; _refresh_saved says it
                (logger.info if refreshing else logger.error)(f"HTTP {status}: {exc.response.text[:200]}")
            
            except ValueError:
                ping_error_obj["error"] =  "MUSICBRAINZ_EMAIL is not set - add your email in Server settings (Connections)"
                ping_error_obj["status"] =  "failed"
                ping_error_obj["code"] = "VALUE_ERROR"
                break
            
            except Exception:
                ping_error_obj["error"] =  "musicbrainz ping failed unexpectedly"
                ping_error_obj["status"] =  "failed"
                ping_error_obj["code"] = "UNKNOWN_ERROR"

        if refreshing:
            #? _refresh_saved says it, quietly: the saved answer stands, and nobody was waiting
            return ping_error_obj

        if ping_error_obj.get("code") == 404:
            #? MusicBrainz answered - with nothing there; no outage to tell anyone of
            return ping_error_obj
        logger.error("exceeded maximum retries for MusicBrainz request without getting valid response")
        logger.error("failed to get valid response from MusicBrainz after retries", extra=loud)
        return ping_error_obj
        

      
     
    #? Everything needed to TELL releases apart: format, labels, country, disambiguation, and
    #? media[].track-count. Note the track COUNT is here - only the track list itself is not.
    RELEASE_LIST_INC = "media+labels+artist-credits"

    #? The above plus every track of every disc. Needed to actually apply a release, and to
    #? match a Soulseek folder against its real tracklist, which is the whole point of the
    #? download flow - so this is still the default.
    RELEASE_FULL_INC = "media+recordings+labels+artist-credits"

    async def get_release(self, release_mbid: str) -> dict:
        """
        One release, with its tracklist.

        The companion to `get_releases(with_tracks=False)`: list them cheaply, then pay for the
        tracks of the one that was actually chosen. Measured on Metallica's 1991 album, whose
        group holds 58 releases: **carrying recordings for all of them costs 5 requests and
        1.4 MB, against 1 request and 101 KB without.** MusicBrainz allows about one request a
        second, so those four extra round trips are four seconds of somebody waiting for track
        listings of 57 pressings they did not pick.
        """
        return await self.request_with_retries(
            f"release/{release_mbid}", {"inc": self.RELEASE_FULL_INC, "fmt": "json"}
        )

    #? What an artist page is made of. `url-rels` is doing double duty: it carries the links
    #? the page lists AND the only two routes to a picture MusicBrainz knows - an `image`
    #? relation, and the `wikidata` relation that leads to one. `artist-rels` is the band's
    #? line-up. Tags and genres are what the artist IS, in other people's words.
    ARTIST_INC = "url-rels+tags+genres+aliases+artist-rels"

    async def search_artists(self, name: str, limit: int = 5, offset: int = 0, quick: bool = False) -> dict:
        """
        Artists by name, for when the files don't say which one they are.

        The fallback behind read_artist_mbid: anything deadwax filed carries the id in its
        tags, and a library that predates it does not. A name is a far weaker key - there are
        several bands called Nirvana - so the caller checks the answer before believing it.

        The query searches ALIASES as well as current names, because the name on disk is the
        one the release was credited under and MusicBrainz keeps only the current one under
        `artist:`. See artist_query() for what that cost before it did.

        `offset` (2.0.0-player.55, the app's Search) is sent only past the first page, so every
        existing call keeps its request and its cache entry; `quick` is the app's Search's patience
        (SEARCH_PATIENCE). Answers MusicBrainz's own payload, or request_with_retries' error dict.
        """
        params = {"query": artist_query(name), "fmt": "json", "limit": limit}
        if offset:
            params["offset"] = offset
        if quick:
            return await self.request_with_retries("artist/", params, patience=SEARCH_PATIENCE)
        return await self.request_with_retries("artist/", params)

    async def get_artist_aliases(self, artist_mbid: str) -> dict:
        """
        One artist with their aliases and nothing else - what the Soulseek search needs to know
        which names an artist has stopped using.

        Deliberately not get_artist(): that one carries relations, tags and genres for a page,
        which is a far larger payload to wait for in the middle of a search. Its own cache key,
        so an artist searched twice in an hour costs one request.
        """
        return await self.request_with_retries(
            f"artist/{artist_mbid}", {"inc": "aliases", "fmt": "json"}
        )

    async def get_artist(self, artist_mbid: str) -> dict:
        """
        One artist, with everything an artist page shows.

        Shaped into a page's terms by artists.artist_facts(); this returns MusicBrainz's own
        payload so the cache stores one thing and the shaping stays pure.
        """
        return await self.request_with_retries(
            f"artist/{artist_mbid}", {"inc": self.ARTIST_INC, "fmt": "json"}
        )

    async def get_release_group_urls(self, release_group_mbid: str) -> dict:
        """
        One release group with its url relations and nothing else (2.0.13) - its `wikidata` link (or a
        `wikipedia` one), which is how an album's description is found (src/descriptions.py). The least that
        answers: no releases, no tags; a lookup, so kept on disk for a month like the others.
        """
        return await self.request_with_retries(
            f"release-group/{release_group_mbid}", {"inc": "url-rels", "fmt": "json"}
        )

    async def _browse(self, endpoint: str, params: dict, items: str, count: str, stop_at: int | None = None,
                      *, refreshing: bool = False) -> tuple[list[dict], dict | None]:
        """
        A paged browse (2.0.0-player.54): `params` asked at offset 0, 100, ... until `count` says every one
        of `items` has come, or `stop_at` of them have - read as ONE answer (Browse): every page from the
        caches under the first page's stamp, or every page from MusicBrainz. A read that finds pages of
        different ages - or a page gone from both caches after pages that weren't - is made again from
        MusicBrainz, every page, which is what a browse cost before anything was saved; and a read from
        disk that is old has the whole browse refreshed behind it, as one (`refreshing`: what that
        refresh runs). Answers the pages, in order, and the failed answer when a page failed - None when
        none did. The callers put the items together.
        """
        for live in ((True,) if refreshing else (False, True)):
            read = Browse(live=live, refreshing=refreshing)
            pages: list[dict] = []
            got, offset = 0, 0
            while True:
                data = await self.request_with_retries(endpoint, {**params, "offset": offset}, browse=read)
                if read.mixed:
                    break
                if not _answered(data):
                    return pages, data
                page = data.get(items, [])
                if not page:
                    break
                pages.append(data)
                got += len(page)
                if got >= data.get(count, 0) or (stop_at is not None and got >= stop_at):
                    break
                offset += len(page)
            if read.mixed:
                logger.info(f"MusicBrainz's saved pages of that {endpoint} browse are of different ages, so "
                            f"it is asked of MusicBrainz again, every page")
                continue
            if refreshing:
                #? every page came: saved together, under one stamp - so never joined to an older page
                stamp = self.cache.now()
                for asked, question, answer in read.answers:
                    self.cache.put(asked, question, answer, fetched_at=stamp)
                    if self.cache.disk is not None:
                        self.cache.disk.put(ResponseCache.disk_key(asked, question), answer, fetched_at=stamp)
            elif read.stale:
                logger.info(f"MusicBrainz's saved pages of that {endpoint} browse are old, so every page is "
                            f"asked for again behind them")
                self._queue_browse_refresh(BrowseRefresh(endpoint, dict(params), items, count, stop_at))
            return pages, None
        raise AssertionError("a browse read from MusicBrainz is never of mixed ages")

    async def get_releases(self, release_group_id: str, log=True, with_tracks: bool = True,
                           with_group: bool = False) -> dict:
        """
        Every release in a group.

        `with_tracks` defaults to True because the download flow needs real tracklists to match
        Soulseek folders against, and the search view renders them. The metadata editor asks for
        False: it is choosing BETWEEN pressings, which needs their format, country, catalogue
        number and track count but not their contents - and then fetches the tracklist of the one
        you pick. See get_release for what that saves.

        `with_group` adds each release's `release-group` (`inc=release-groups`): the app's album
        page reads the group's title, type and first year from it when nothing handed them over (a
        reload, a link), at no extra request. Its own cache key, as every inc is.
        """
        if log:
            logger.info(
                "getting specific releases from musicbrainz",
                extra={"frontend": True, "src": "musicbrainz"}
            )

        params = {
            "release-group": release_group_id,
            "inc": (self.RELEASE_FULL_INC if with_tracks else self.RELEASE_LIST_INC)
            + ("+release-groups" if with_group else ""),
            "fmt": "json",
            "limit": 100,
        }
        #? page by page, read as one answer - see _browse
        pages, failed = await self._browse("release/", params, "releases", "release-count")
        all_releases = _distinct(release for page in pages for release in page.get("releases", []))

        #? A FAILED request and a group with no releases are not the same thing, and this
        #? is the one place they were indistinguishable: request_with_retries answers with
        #? an error dict rather than raising, so `data.get("releases", [])` quietly turned
        #? an outage into "this album has no pressings". The interface believed it, showed
        #? the top result with nothing to expand, and built its filter facets from the
        #? grids that never mounted - so a MusicBrainz blip read as a search with no
        #? releases and no filters, with nothing on screen suggesting a retry.
        if failed is not None:
            problem = failed.get("error") or "the request failed"
            logger.warning(
                f"couldn't load the releases for that album ({problem}) - "
                f"expand it to try again",
                extra={"frontend": True, "src": "musicbrainz"},
            )
            return {"release-count": len(all_releases), "releases": all_releases,
                    "problem": problem}

        return {
            "release-count": len(all_releases),
            "releases": all_releases,
            #? None means the answer is complete and an empty list really does mean empty
            "problem": None,
        }

    

    #? A hard ceiling on how far a discography browse will page.
    #?
    #? MusicBrainz answers 100 groups a request and allows roughly one request a second, so
    #? this is also a five-second ceiling on how long the user waits. It exists because the
    #? artist credited on a record is not always a person: "Various Artists" carries tens of
    #? thousands of release groups, and paging that to completion would hammer a service that
    #? is rate limited and frequently down, to build a list nobody could read. Truncation is
    #? REPORTED rather than hidden - see the `truncated` flag below.
    DISCOGRAPHY_PAGE = 100
    DISCOGRAPHY_MAX = 500

    #? Secondary types that mean "not an original studio record". The same list the search
    #? query's "studio only" filter excludes by name - kept in step with it deliberately, so
    #? the two views of an artist agree about what counts as an album.
    NOISY_SECONDARY_TYPES = frozenset(
        {"live", "compilation", "interview", "demo", "remix", "dj-mix", "mixtape/street", "audiobook", "soundtrack"}
    )

    async def get_artist_release_groups(
        self,
        artist_mbid: str,
        primary_types: list[str] | None = None,
        studio_only: bool = False,
    ) -> dict:
        """
        Every release group credited to an artist, in full.

        THIS IS A BROWSE, NOT A SEARCH, and that distinction is the entire point of the
        endpoint. A search answers in relevance order and spends its limit on whatever matches,
        so "the 50 best matches for Portishead, sorted by year" is the oldest of the fifty most
        relevant - not the artist's earliest work. A browse asks for everything credited to one
        artist id and pages until it has it, which is the only way a chronological discography
        can be honest about being complete.

        `primary_types` filters server-side (album, ep, single, broadcast, other). Filtering
        here rather than after the fact matters for the same reason it does in the search
        query: the cap below is spent on what was asked for instead of on singles nobody
        wanted.

        `studio_only` drops live albums, compilations and the rest AFTER the browse, because
        MusicBrainz browse has no secondary-type parameter. Filtering returned rows is exactly
        what CLAUDE.md says not to do for the SEARCH - but the reason it is wrong there does
        not apply here. A search spends a limited budget on whatever matched, so discarding
        rows throws that budget away; a browse has already paged through everything credited
        to the artist, so what is being filtered is the complete set rather than a sample.
        """
        logger.info(
            "browsing an artist's release groups from musicbrainz",
            extra={"frontend": True, "src": "musicbrainz"},
        )

        params = {
            "artist": artist_mbid,
            "inc": "artist-credits",
            "fmt": "json",
            "limit": self.DISCOGRAPHY_PAGE,
        }

        #? MusicBrainz takes these as a `type` param repeated per value; httpx renders a
        #? list that way. Omitted entirely when nothing is selected - an empty `type` is
        #? not the same as no filter and returns nothing.
        if primary_types:
            params["type"] = primary_types

        #? page by page, read as one answer - see _browse - and stopping at the ceiling
        pages, failed = await self._browse("release-group/", params, "release-groups", "release-group-count",
                                           stop_at=self.DISCOGRAPHY_MAX)
        paged = [group for page in pages for group in page.get("release-groups", [])]
        groups = _distinct(paged)

        #? A failed request and an artist with no release groups are NOT the same thing.
        #? request_with_retries answers with an error dict rather than raising, so reading
        #? .get("release-groups", []) would turn an outage into "this artist has released
        #? nothing" - stated confidently, with nothing on screen suggesting a retry. The
        #? same trap get_releases documents above.
        if failed is not None:
            problem = failed.get("error") or "the request failed"
            logger.warning(
                f"couldn't load that artist's discography ({problem})",
                extra={"frontend": True, "src": "musicbrainz"},
            )
            return {
                "release-group-count": len(groups),
                "release-groups": groups,
                "truncated": False,
                "problem": problem,
            }

        total = pages[-1].get("release-group-count", 0) if pages else 0

        if len(paged) >= self.DISCOGRAPHY_MAX and len(paged) < total:
            kept = self._filter_studio(groups[: self.DISCOGRAPHY_MAX], studio_only)
            return {
                "release-group-count": len(kept),
                "release-groups": kept,
                #? Says the list is not the whole story, so the interface can too. An
                #? incomplete discography presented as complete is the failure to avoid.
                "truncated": True,
                "total-available": total,
                "problem": None,
            }

        kept = self._filter_studio(groups, studio_only)

        return {
            "release-group-count": len(kept),
            "release-groups": kept,
            "truncated": False,
            #? None means the answer is complete and an empty list really does mean empty
            "problem": None,
        }

    @classmethod
    def _filter_studio(cls, groups: list[dict], studio_only: bool) -> list[dict]:
        """Drop anything carrying a secondary type, when asked. See the note above."""
        if not studio_only:
            return groups

        return [
            group
            for group in groups
            if not any(
                str(t).lower() in cls.NOISY_SECONDARY_TYPES
                for t in (group.get("secondary-types") or [])
            )
        ]


    async def fully_search(self, query: str, limit: int = 5, include_releases: bool = True, offset: int = 0,
                           quick: bool = False) -> dict:
        """
        Release groups matching the query, and by default the releases of the best one.

        `include_releases=False` exists because that second half is expensive and not everyone
        wants it. It walks the best group's full release list WITH tracklists - five requests
        and 1.4 MB for an album like Metallica's 1991 one. The search view needs it, since it
        renders those releases immediately. The metadata editor does not: it ranks the groups
        itself and then asks for the ones it actually wants, so the eager fetch was five round
        trips spent on a payload it dropped on the floor.

        `offset` (2.0.0-player.50) pages on through the answers - the app's "More from
        MusicBrainz". It is sent only when it isn't 0, so the first page is asked exactly as before
        (the same request, the same cache entry). The answer carries MusicBrainz's `count` - how
        many groups match in all - so a page can tell whether there are more to ask for.

        `quick` (2.0.0-player.55, the app's Search alone): SEARCH_PATIENCE instead of the ten attempts, a
        400 raised as MusicBrainzRejected, and a failure's `busy` passed on. Not sent to MusicBrainz, so the
        request and its cache entry are the same either way.
        """
        logger.info("searching musicbrainz...", extra={"frontend": True, "src":"musicbrainz"})
        params = {
            "query": query,
            "fmt": "json",
            "limit": limit
        }
        if offset:
            params["offset"] = offset
        #? a quick search's patience - the call otherwise exactly as it always was
        release_groups = (await self.request_with_retries("release-group/", params, patience=SEARCH_PATIENCE) if quick
                          else await self.request_with_retries("release-group/", params))

        #? request_with_retries returns an error dict rather than raising when it gives up, so
        #? reaching straight for "release-groups" threw a KeyError that surfaced as
        #? "Error searching MusicBrainz: 'release-groups'" - a message that reads like a bad
        #? query rather than "the service is down". MusicBrainz goes unreachable often enough
        #? that people reasonably blamed their own search terms for it.
        if release_groups.get("status") == "failed" or "release-groups" not in release_groups:
            reason = release_groups.get("error", "unknown error")
            if quick and release_groups.get("code") == 400:
                raise_for_search(release_groups, quick)
            logger.error(
                f"MusicBrainz is unreachable, this is not a problem with your search ({reason})",
                extra={"frontend": True, "src": "musicbrainz"},
            )
            if quick:
                raise_for_search(release_groups, quick)
            raise MusicBrainzUnavailable(reason)

        if not release_groups["release-groups"]:
            logger.info(f"no release groups found for query: ({query})", extra={"frontend": True, "src":"musicbrainz"})
            return {}


        logger.info("release groups parsed", extra={"frontend": True, "src":"musicbrainz"})

        #? how many groups match in all, as MusicBrainz counts them - a page reads it to know whether
        #? another page is there to ask for (absent when MusicBrainz didn't say)
        count = release_groups.get("count")
        counted = {"count": count} if isinstance(count, int) and not isinstance(count, bool) else {}

        if not include_releases:
            #? the key is still present, so callers reading it don't have to special-case this
            return {"release-groups": release_groups["release-groups"], "best-match-releases": [], **counted}

        first_release_group = release_groups["release-groups"][0]
        first_release_group_releases = await self.get_releases(first_release_group["id"], log=False)

        return {
            "release-groups": release_groups["release-groups"],
            "best-match-releases": first_release_group_releases["releases"],
            **counted,
        }
    
    async def search_recordings(self, query: str, limit: int = 25, offset: int = 0, quick: bool = False) -> dict:
        """
        Recordings - songs - matching the query (2.0.0-player.53): the app's "Songs on MusicBrainz".

        One request, and nothing more asked per song: MusicBrainz's recording search answers each
        recording with its `releases`, every one carrying its `release-group` (id, title, primary and
        secondary types), its status, date and country, and the track itself (`media[].track`: its
        number, title and length) - which is all the app needs to say which albums a song is on and
        open one on a pressing that has it. Measured on 2026-10-15: Queen's studio "Bohemian
        Rhapsody" came with all 353 of its releases, in 133 release groups, in one answer.

        `offset` is sent only past the first page, as fully_search does. The answer is `recordings`
        (an empty list when nothing matched - never a failure) and MusicBrainz's `count` when it said
        one; a failed request raises MusicBrainzUnavailable, so an outage never reads as no songs.
        `quick` (2.0.0-player.55 - /songs always sends it): SEARCH_PATIENCE, a 400 raised as
        MusicBrainzRejected, a failure's `busy` passed on.
        """
        logger.info("searching musicbrainz for songs...")
        params = {"query": query, "fmt": "json", "limit": limit}
        if offset:
            params["offset"] = offset
        found = (await self.request_with_retries("recording/", params, patience=SEARCH_PATIENCE) if quick
                 else await self.request_with_retries("recording/", params))

        #? request_with_retries answers a failure with an error dict rather than raising - the trap
        #? fully_search documents: read as an answer, an outage would be "no songs found"
        if found.get("status") == "failed" or not isinstance(found.get("recordings"), list):
            reason = found.get("error", "unknown error")
            if quick and found.get("code") == 400:
                raise_for_search(found, quick)
            logger.error(
                f"MusicBrainz is unreachable, this is not a problem with your search ({reason})",
                extra={"frontend": True, "src": "musicbrainz"},
            )
            if quick:
                raise_for_search(found, quick)
            raise MusicBrainzUnavailable(reason)

        count = found.get("count")
        counted = {"count": count} if isinstance(count, int) and not isinstance(count, bool) else {}
        return {"recordings": found["recordings"], **counted}

    async def ping(self) -> dict:
        logger.info("pinging MusicBrainz to check connectivity")
        try: 
            #? never from the saved answers (2.0.0-player.54): this asks whether MusicBrainz can be
            #? reached, which an answer kept from last week can't say - in memory for an hour, as ever
            test_release = await self.request_with_retries("release-group/f6b1b900-6108-32f0-abbd-2855af9151eb", {}, disk=False)
            if test_release.get("status") == "failed":
                logger.error(test_release.get("error"))
                return test_release #? {"status":"failed"}
            else: 
                logger.info("Connection successful", extra={"frontend": True, "src":"musicbrainz"})
                return {"status": "ok"}
        except Exception:
            logger.error("musicbrainz ping failed unexpectedly")
            return {"status": "failed", "error": "musicbrainz ping failed unexpectedly", "code": "UNKNOWN_ERROR"}





