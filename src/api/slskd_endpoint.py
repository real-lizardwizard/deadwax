import asyncio
from contextlib import asynccontextmanager
from urllib.parse import quote
from types import SimpleNamespace
import re
import traceback
import slskd_api
from requests.exceptions import HTTPError, ConnectionError, RequestException
from src.config import Config, describe_slskd_url
from src.logger import logger


_PUNCTUATION = r"[\[\](){}_\-.,'\"!?/\\:;&+]"

#? Punctuation only counts as punctuation when it is standing on its own - wrapping a word, or
#? already acting as a separator. BETWEEN two alphanumerics it is part of the name, and pulling
#? it out is what lost Metallica's "S&M2".
#?
#? Both readings of how Soulseek matches say to leave it where it is:
#?
#?   If a term has to appear in the path as a substring, "S&M2" is what the folder literally
#?   says, and "S" "M2" only match by luck.
#?
#?   If the server instead tokenizes on non-alphanumerics - which is what the reported failure
#?   looks like - then it tokenizes the QUERY the same way. Sending "S&M2" asks for s/m/2 and
#?   matches, while "S M2" asks for a token "m2" that exists on NEITHER side, so it matches
#?   nothing at all. The album name silently disappears from the search.
#?
#? Splitting it ourselves is the one option that can be wrong under both readings, which is why
#? this leaves the decision to whichever end actually does the matching.
LOOSE_PUNCTUATION = re.compile(
    rf"(?<![0-9A-Za-z]){_PUNCTUATION}|{_PUNCTUATION}(?![0-9A-Za-z])"
)


def build_search_query(artist: str, album: str) -> str:
    """
    Soulseek search is a match over shared filenames, not a metadata index. Edition text is
    actively harmful here - the Tubifarry maintainer's own guidance is that over-specific
    queries return nothing, because "deluxe edition" almost never appears in the folder names
    people actually share.

    So the query stays deliberately dumb: artist + album, with loose punctuation dropped and
    punctuation inside a word left alone. Edition preference is applied later when ranking what
    comes back (src/matching.py), which is where it can help instead of hurt.

    What this deliberately does NOT do is take a word apart. "S&M2" is one word that a sharer
    typed as one word; whatever Soulseek does to it, it will do the same thing to the folder
    name, and that is a far better bet than guessing on its behalf.
    """
    combined = LOOSE_PUNCTUATION.sub(" ", f"{artist or ''} {album or ''}")

    #? split()/join() rather than a whitespace regex - it collapses runs and strips the ends
    return " ".join(combined.split())


#? (2.0.4) The sentence under each of the ping's codes, in You -> Connections - drawn only for an admin and someone with
#? Settings and the log, so a setting is named where it is the thing to change. Until 2.0.4 they were the log's own
#? lines ("slskd ping failed with connection error, functionality enabled, but couldnt connect..."). slskd's state
#? (NOT_LOGGED_IN, NOT_CONNECTED, CONNECTING) keeps describe_server_state's words, which quote slskd.
PING_WORDS = {
    "NO_STATE": "slskd answered, but didn't say whether it's connected to Soulseek.",
    401: "slskd turned down deadwax's API key - check SLSKD_APIKEY in Server settings (Connections).",
    502: "slskd's address answers, but slskd itself isn't running behind it.",
    "UNKNOWN_HTTP_ERROR": "slskd answered with an error deadwax doesn't know (HTTP {status}) - the log has the details.",
    "CONNECTION_ERROR": ("deadwax can't reach slskd at its address - check slskd is running, and SLSKD_URL in Server "
                         "settings (Connections)."),
    "NOT_SET_UP": "{problem} - set it in Server settings (Connections).",
    "UNKNOWN_ERROR": "Asking slskd failed in a way deadwax doesn't know - the log has the details.",
}
#? ...and the three that send the reader to a setting, as someone with Settings and the log reads them: SLSKD_URL and
#? SLSKD_APIKEY are an admin's alone (src/routes/settings.py ADMINS_ONLY), locked on their page (review)
PING_WORDS_NOT_ADMIN = {
    401: "slskd turned down deadwax's API key (SLSKD_APIKEY) - only an admin can change it, in Server settings "
         "(Connections).",
    "CONNECTION_ERROR": ("deadwax can't reach slskd at its address - check slskd is running; its address (SLSKD_URL) "
                         "only an admin can change, in Server settings (Connections)."),
    "NOT_SET_UP": "{problem} - only an admin can set it, in Server settings (Connections).",
}


class SlskdSearchRefused(Exception):
    """
    A search slskd would not start, carrying the reason it gave rather than its status code.

    Raised instead of letting requests' HTTPError through, because that one renders as its
    status line and nothing else - see slskd_said() below for why that matters here.
    """

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


#? What slskd answers a refused search with, and what each status actually MEANS - which in the
#? case that brought this about is nothing like what its name says.
#?
#? 409 Conflict reads as "that already exists". What slskd means by it is that its connection to
#? the Soulseek server is down: SearchesController.Post maps InvalidOperationException to
#? Conflict, and the only thing that throws one on this path is Soulseek.NET's own precondition -
#? "The server connection must be connected and logged in to perform a search". slskd's web API
#? answers perfectly while logged out, so a refused search can be the FIRST sign anything is
#? wrong. Traced through slskd's SearchesController.Post, SearchService.StartAsync and
#? SoulseekClient.SearchAsync rather than guessed at.
#?
#? 429 is slskd's own one-at-a-time limiter - a static SemaphoreSlim(1, 1) taken with Wait(0) - held
#? while a search STARTS, so a second start made while one is starting gets it. Since 2.0.0-player.49
#? every start deadwax makes waits its turn at SEARCH_GATE, so two tabs, two people or a retry inside
#? deadwax no longer meet it; something else starting a search at that moment (slskd's own page,
#? another app) still can - and so can a start the gate let through after SEARCH_TURN_SECONDS behind
#? one stuck starting. The words keep "one at a time": of starts, that is true.
SEARCH_REFUSALS = {
    400: "slskd rejected the search itself",
    401: "slskd refused the API key",
    403: "this slskd is running as a relay agent, and those cannot start searches",
    409: "slskd is not connected to the Soulseek network, so it cannot search",
    429: "slskd is already running a search, and it only runs one at a time",
}


def slskd_said(exc: HTTPError) -> str:
    """
    The explanation slskd put in the response body, or '' when there wasn't a usable one.

    This exists because requests renders an HTTPError as its status line alone - "409 Client
    Error: Conflict for url: ..." - and drops the body on the floor. slskd puts the whole reason
    in that body, so not reading it is what turns a sentence into a number.
    """
    response = getattr(exc, "response", None)
    if response is None:
        return ""

    #? slskd declares [Produces("application/json")] and returns bare strings, so the usual body
    #? is a JSON string. A ProblemDetails object and plain text both turn up too.
    try:
        body = response.json()
    except Exception:
        body = getattr(response, "text", "") or ""

    if isinstance(body, dict):
        body = next(
            (body[key] for key in ("detail", "title", "message", "error")
             if isinstance(body.get(key), str) and body[key].strip()),
            "",
        )

    text = " ".join(str(body or "").split())

    #? An HTML page is somebody else's - a proxy, or a login portal in front of slskd - and a
    #? screenful of markup in the log helps nobody. Our own headline is better than that.
    if text.startswith("<") or len(text) > 300:
        return ""

    return text


def describe_search_refusal(status: int | None, said: str = "", connection: str = "") -> str:
    """
    One sentence saying why a search didn't run.

    `connection` is what slskd says about its Soulseek connection right now, where that was
    worth asking for; it wins outright, being both more specific and more current than a status
    code. Otherwise the status is explained and slskd's own words follow ours rather than
    replacing them - the body is specific and occasionally cryptic, and the status is the part
    that can be explained once and for all.

    Every branch names slskd as its subject, because this one string is shown in two places: on
    its own in the event log, and after "search failed: " in the candidates panel. A sentence
    that opened with "could not search" would read as a stutter in the second.
    """
    if connection:
        return connection

    headline = SEARCH_REFUSALS.get(status or 0)

    if headline is None:
        headline = (
            f"slskd refused the search (HTTP {status})" if status else "slskd refused the search"
        )

    return f"{headline} - slskd said: {said}" if said else headline


def _waiting_on(state: dict | None, transitioning: bool = False) -> str:
    """
    The reason slskd itself gives for being disconnected, where its state carries one.

    Both fields are newer than some slskd versions, so both are optional - and the VPN one is
    the entire answer when slskd runs inside a VPN container, which is a common way to run it
    and the way this one is deployed.

    "Trying to reconnect" is dropped while slskd is already reported as connecting, where it
    only says the same thing twice.
    """
    watchdog = state.get("connectionWatchdog") if isinstance(state, dict) else None
    watchdog = watchdog if isinstance(watchdog, dict) else {}

    if watchdog.get("isAwaitingVpn"):
        return ", and it is waiting for its VPN"

    if watchdog.get("isAttemptingConnection") and not transitioning:
        return ", and it is trying to reconnect"

    return ""


def describe_server_state(state: dict | None) -> dict:
    """
    What slskd's own state says about its connection to Soulseek, as {ok, code, detail}.

    `ok` is True when a search could actually run, which is the half of "is slskd working" that
    pinging its API cannot see. slskd answers its own API perfectly while logged out of
    Soulseek, so a connection pill built on the ping alone reads "ok" right up until the first
    search fails - and then blames the search.

    An slskd too old to report `server` is treated as connected. Absence of the field is not
    evidence of a disconnection, and a red pill on a working install is the worse mistake of the
    two - the same call as _attach_measured_speeds failing silently.
    """
    #? slskd answering with something other than an object is not a disconnection either - it
    #? is a proxy or an error page, which the ping's own HTTP handling is the place to notice
    server = state.get("server") if isinstance(state, dict) else None
    if not isinstance(server, dict) or not server:
        return {"ok": True, "code": "connected", "detail": ""}

    #? The flags are booleans wherever they exist; `state` is a string like "Connected, LoggedIn"
    #? or "Disconnected" and is only ever quoted back, never parsed - it is a .NET flags enum and
    #? reading it ourselves would be one more thing to keep in step with slskd.
    reported = " ".join(str(server.get("state") or "").split()) or "an unknown state"

    if server.get("isConnected") and server.get("isLoggedIn"):
        return {"ok": True, "code": "connected",
                "detail": f"slskd is logged in to Soulseek ({reported})"}

    transitioning = bool(
        server.get("isTransitioning") or server.get("isConnecting") or server.get("isLoggingIn")
    )

    #? the fact and the advice are kept apart so the state slskd reported sits beside the fact
    #? rather than after a clause about what to go and change
    if transitioning:
        code, note, advice = "CONNECTING", "slskd is still connecting to Soulseek", ""

    elif server.get("isConnected"):
        code = "NOT_LOGGED_IN"
        note = "slskd has reached the Soulseek server but is not logged in"
        advice = " - check the username and password in its own configuration"

    else:
        code, note, advice = "NOT_CONNECTED", "slskd is not connected to the Soulseek server", ""

    return {
        "ok": False,
        "code": code,
        "detail": f"{note} ({reported}){_waiting_on(state, transitioning)}{advice}",
    }


#? How long a search waits for its turn to START before it starts anyway (2.0.0-player.49). A start is
#? one POST that slskd answers at once, so a turn is a fraction of a second; this is the far end -
#? slskd hanging on one - past which the gate gives up waiting rather than holding a Find for ever,
#? and a start still going gives up its turn so the next goes ahead (SearchGate).
SEARCH_TURN_SECONDS = 30.0


class SearchGate:
    """
    One Soulseek search STARTS at a time, across the whole process (2.0.0-player.49).

    slskd starts one search at a time - a static SemaphoreSlim(1, 1) taken with Wait(0) around the
    start (SEARCH_REFUSALS' 429) - and refuses a second START made while one is starting, though
    searches already started run side by side. One person's Find starts its searches in turn
    (_run_searches), so a single user never met it; two people's Finds at once could, and the second
    was told "slskd is already running a search". So every start in the process takes its turn here
    first, waiting in line - bounded by SEARCH_TURN_SECONDS, after which it starts regardless - and
    never refusing. Only the start is held, never the listening for answers, so two Finds still cost
    barely more than one.

    A turn is bounded the same way: one still in its start after SEARCH_TURN_SECONDS gives up its
    place itself, so the next start goes ahead. The start runs in a thread no cancel can stop, and
    slskd_api sends its requests with no timeout, so a POST never answered (a connection dropped
    without a reset) would otherwise hold the gate for the life of the process, and every start after
    it - anyone's - would wait the whole bound. One stuck start holds up the line once, not for ever.

    Its lock is made for the event loop it is used in (each test runs its own loop, and asyncio's
    lock belongs to the first loop it waits in).
    """

    def __init__(self, bound: float = SEARCH_TURN_SECONDS):
        self.bound = bound
        self._lock: asyncio.Lock | None = None
        self._loop = None

    def _lock_here(self) -> asyncio.Lock:
        loop = asyncio.get_running_loop()
        if self._lock is None or self._loop is not loop:
            self._lock, self._loop = asyncio.Lock(), loop
        return self._lock

    @asynccontextmanager
    async def turn(self, query: str = ""):
        lock = self._lock_here()
        try:
            await asyncio.wait_for(lock.acquire(), timeout=self.bound)
            held = True
        except asyncio.TimeoutError:
            #? waited its whole bound behind another start: starting anyway is better than never
            held = False
            logger.warning(f"waited {self.bound:.0f}s for another Soulseek search to start; starting "
                           f"{query!r} anyway", extra={"frontend": True, "src": "slskd"})

        timer = None
        if held:
            def give_up_the_turn():
                #? still starting after the whole bound: the next start goes ahead, rather than every
                #? start after this one waiting the bound behind it (see the docstring)
                nonlocal held
                held = False
                lock.release()
                logger.warning(f"the Soulseek search for {query!r} has taken over {self.bound:.0f}s to "
                               f"start; letting the next one start", extra={"frontend": True, "src": "slskd"})

            timer = asyncio.get_running_loop().call_later(self.bound, give_up_the_turn)
        try:
            yield
        finally:
            if timer is not None:
                timer.cancel()
            if held:
                lock.release()


#? the process's one gate - every SlskdClient's starts go through it
SEARCH_GATE = SearchGate()


class SlskdClient:
    def __init__(self):
        self.client: slskd_api.SlskdClient | None = None
    
    async def get_client(self) -> slskd_api.SlskdClient:
        logger.info("getting slskd SlskdClient")

        try:
            if self.client is None:
                # Check the URL is actually usable before handing it over. slskd_api builds its
                # base URL by urljoin-ing the host, so a blank or scheme-less value doesn't fail
                # here - it fails much later inside requests as
                # "Invalid URL '///api/v0/searches': No scheme supplied", which says nothing
                # about which setting is wrong or where to fix it.
                #? Since 1.0.5 this is also where an address from compose or .env meets the
                #? settings tab's rule - no login, no ? or # - since it never passed through the
                #? tab. Nothing is sent to one, the API key least of all.
                url_problem = describe_slskd_url(Config.SLSKD_URL)
                if url_problem:
                    message = f"SLSKD_URL is unusable ({url_problem})"
                    logger.error(message, extra={"frontend": True, "src": "slskd"})
                    raise ValueError(message)

                if not Config.SLSKD_APIKEY:
                    logger.warning("SLSKD_APIKEY is not configured", extra={"frontend": True, "src":"slskd"})
                    raise ValueError("SLSKD_APIKEY is not configured")

                self.client = slskd_api.SlskdClient(
                    host=Config.SLSKD_URL,
                    api_key=Config.SLSKD_APIKEY
                )
        except Exception as e:
            logger.error("failed to create slskd client, traceback in logs", extra={"frontend": True, "src":"slskd"})
            logger.error(traceback.format_exc())
            raise e
        
        return self.client


    async def close_client(self) -> None:
        logger.info("closing slskd client")
        self.client = None


    async def _explain_refusal(self, exc: HTTPError) -> str:
        """
        Turn a refused search into a sentence, asking slskd how it is doing where that helps.

        The extra request runs on the failure path only, and only for the one status a
        connection explains. It is the difference between "not connected" and "not connected,
        and it is waiting for its VPN" - which is the whole answer when slskd runs inside a VPN
        container, and is not something the refusal itself can say.
        """
        status = getattr(getattr(exc, "response", None), "status_code", None)
        connection = ""

        if status == 409 and self.client is not None:
            try:
                described = describe_server_state(
                    await asyncio.to_thread(self.client.application.state)
                )
                connection = "" if described["ok"] else described["detail"]

            except Exception as e:
                #? the diagnosis is a bonus - never let it replace the error it explains
                logger.debug(f"couldnt read slskd's connection state to explain a refusal: {e}")

        return describe_search_refusal(status, slskd_said(exc), connection)


    async def search(
        self,
        query: str,
        search_timeout_ms: int = 8000,
        poll_interval: float = 0.5,
        max_wait: float = 25.0,
    ) -> list[dict]:
        """One Soulseek search - see search_all(), which this is the one-query case of."""
        return await self.search_all([query], search_timeout_ms, poll_interval, max_wait)


    async def search_all(
        self,
        queries: list[str],
        search_timeout_ms: int = 8000,
        poll_interval: float = 0.5,
        max_wait: float = 25.0,
    ) -> list[dict]:
        """
        Run Soulseek searches side by side and wait for them all to settle.

        slskd searches are asynchronous: you POST one, peers trickle in responses, and it
        flips isComplete when the timeout expires. slskd_api is synchronous so every call goes
        through asyncio.to_thread, same as ping() already does.

        Several at once because one album can be shared under several names - an artist who
        has renamed is filed by some people under each - and every search costs the whole
        search timeout. Run one after another, two names would double the wait; run together
        they cost barely more than one. slskd's one-at-a-time limiter only covers STARTING a
        search, which is why the starts below go strictly in turn and the waiting is shared.

        Responses are returned as slskd gave them, one list for all the queries. The same share
        found by two of them is merged where files are grouped (group_files_by_directory).

        CANCELLING this - which the route does when the page that asked has gone - stops and
        deletes every search it started, rather than leaving slskd to run them out to their
        timeout for nobody. See _abandon.
        """
        client = await self.get_client()
        running: list[tuple[str, str]] = []

        try:
            return await self._run_searches(client, queries, running, search_timeout_ms,
                                            poll_interval, max_wait)
        except asyncio.CancelledError:
            await self._abandon(client, running)
            raise


    async def _abandon(self, client, running: list[tuple[str, str]]) -> None:
        """
        Stop and delete searches nobody is waiting for any more.

        Before this, a search the page had given up on - another album's Find pressed, the
        panel closed - ran in slskd to its full timeout and was then scored and returned into a
        closed connection. Stopping it frees slskd for the search that replaced it. Each step is
        best effort: a search that already finished can't be stopped, and that's fine.
        """
        for query, search_id in running:
            for step in (client.searches.stop, client.searches.delete):
                try:
                    await asyncio.to_thread(step, search_id)
                except Exception:
                    pass
            logger.info(f"stopped the abandoned search for: {query}", extra={"frontend": True, "src": "slskd"})


    async def _run_searches(self, client, queries, running, search_timeout_ms, poll_interval, max_wait):
        for query in queries:
            logger.info(f"searching slskd for: {query}", extra={"frontend": True, "src": "slskd"})

            #? The start runs in a thread, and a cancel can't stop a thread: the POST reaches slskd
            #? and the search runs whether anyone is still waiting or not. So a cancel that lands
            #? mid-start waits for the start and records its id before going on, or _abandon never
            #? hears of that search and slskd runs it to its timeout for nobody (v1.1.7 - CI's
            #? slower runner cancelled during the second start of two).
            #? (2.0.0-player.49) in turn with every other start in the process - another person's
            #? Find included - held until slskd has answered this one (SearchGate)
            try:
                async with SEARCH_GATE.turn(query):
                    start = asyncio.ensure_future(asyncio.to_thread(
                        client.searches.search_text,
                        searchText=query,
                        searchTimeout=search_timeout_ms,
                    ))
                    try:
                        state = await asyncio.shield(start)

                    except asyncio.CancelledError:
                        try:
                            begun = (await start).get("id")
                        except Exception:
                            begun = None
                        if begun:
                            running.append((query, begun))
                        raise

            except HTTPError as exc:
                #? slskd refused to START the search, which is a different thing from a search
                #? that found nothing, and it always says why. See _explain_refusal.
                reason = await self._explain_refusal(exc)

                #? With nothing running, this IS the answer - and the rest would only be
                #? refused for the same reason, so they are not even asked.
                if not running:
                    logger.error(reason, extra={"frontend": True, "src": "slskd"})
                    raise SlskdSearchRefused(
                        reason, getattr(getattr(exc, "response", None), "status_code", None)
                    ) from exc

                #? One is already under way, so losing another name narrows the search rather
                #? than failing it. Said, because a narrower search is still worth knowing about.
                logger.warning(
                    f"{reason} - so it searched without {query!r}",
                    extra={"frontend": True, "src": "slskd"},
                )
                continue

            search_id = state.get("id")
            if search_id:
                running.append((query, search_id))
            else:
                logger.error(
                    f"slskd did not return a search id for: {query}",
                    extra={"frontend": True, "src": "slskd"},
                )

        if not running:
            return []

        pending = {search_id for _, search_id in running}
        elapsed = 0.0
        while pending and elapsed < max_wait:
            await asyncio.sleep(poll_interval)
            elapsed += poll_interval

            for search_id in list(pending):
                state = await asyncio.to_thread(client.searches.state, search_id)
                if state.get("isComplete"):
                    pending.discard(search_id)

        if pending:
            logger.warning(
                f"slskd search didnt complete within {max_wait}s, using whatever came back",
                extra={"frontend": True, "src": "slskd"},
            )

        responses: list[dict] = []
        for query, search_id in running:
            found = await asyncio.to_thread(client.searches.search_responses, search_id)
            logger.info(
                f"slskd returned {len(found)} responses for: {query}",
                extra={"frontend": True, "src": "slskd"},
            )
            responses.extend(found)

            #? don't let one-shot searches pile up in slskd's UI forever
            try:
                await asyncio.to_thread(client.searches.delete, search_id)
            except Exception:
                logger.warning(f"couldnt clean up slskd search {search_id}, harmless")

        return responses


    async def enqueue(self, username: str, files: list[dict]) -> tuple[bool, str]:
        """
        Queue a download. `files` must be [{'filename': ..., 'size': ...}] exactly as returned
        by search_responses - slskd matches on those two fields.

        Returns (accepted, slskd's reason when it wasn't). slskd_api's own enqueue returns only
        `response.ok` and drops the body, which is where slskd says WHY - usually that the peer
        is offline, from the exception its enqueue threw looking the peer up. So the request is
        made on slskd_api's session directly, the same URL and payload, and the body kept.

        Slow on purpose, and the reason the downloads panel shows a placeholder the moment you
        click (v0.9.9): slskd does not answer until it has looked up the peer's address and
        opened a connection to them, which takes seconds for a firewalled peer.
        """
        logger.info(
            f"queueing {len(files)} files from {username}",
            extra={"frontend": True, "src": "slskd"},
        )
        client = await self.get_client()

        payload = [{"filename": f["filename"], "size": f["size"]} for f in files]
        transfers = client.transfers
        url = transfers.api_url + f"/transfers/downloads/{quote(username)}"

        try:
            #? slskd_api's session RAISES on a non-2xx (a response hook calling
            #? raise_for_status), so a refusal arrives as an HTTPError carrying the response
            response = await asyncio.to_thread(transfers.session.post, url, json=payload)
            if response.ok:
                logger.info(f"queued {len(files)} files from {username}", extra={"frontend": True, "src": "slskd"})
                return True, ""
            refused = response

        except HTTPError as exc:
            refused = getattr(exc, "response", None)
            if refused is None:
                logger.error(f"failed to queue download from {username}: {exc}", extra={"frontend": True, "src": "slskd"})
                return False, f"couldn't reach slskd to queue it: {exc}"

        except Exception as e:
            logger.error(f"failed to queue download from {username}", extra={"frontend": True, "src": "slskd"})
            logger.error(traceback.format_exc())
            return False, f"couldn't reach slskd to queue it: {e}"

        said = slskd_said(SimpleNamespace(response=refused))
        reason = f"slskd couldn't queue it: {said}" if said else f"slskd refused the download ({refused.status_code})"
        logger.error(f"{reason} - from {username}", extra={"frontend": True, "src": "slskd"})
        return False, reason


    async def cancel_download(self, username: str, transfer_id: str, remove: bool = True) -> bool:
        """Cancel one in-flight transfer. `remove` also drops it from slskd's own list."""
        try:
            client = await self.get_client()
            return bool(await asyncio.to_thread(
                client.transfers.cancel_download, username=username, id=transfer_id, remove=remove
            ))

        except Exception:
            logger.error(f"failed to cancel transfer {transfer_id} from {username}")
            logger.error(traceback.format_exc())
            return False


    async def queue_position(self, username: str, transfer_id: str) -> int | None:
        """
        Where we sit in a peer's upload queue.

        slskd only answers this per transfer, so it's asked for sparingly - a queued job
        rather than every file on every poll.
        """
        try:
            client = await self.get_client()
            position = await asyncio.to_thread(
                client.transfers.get_queue_position, username=username, id=transfer_id
            )
            return int(position) if isinstance(position, (int, str)) and str(position).isdigit() else None

        except Exception:
            #? peers drop out constantly; a missing position isn't worth logging loudly
            return None


    async def get_downloads(self, usernames) -> list[dict]:
        """
        What slskd holds from these users, in the shape of its full list: [{username, directories}].

        Asked user by user (v0.9.29). Every caller wants the transfers of a few jobs' peers, and
        slskd's full list is every download it has kept - it only shrinks when somebody clears it -
        fetched twice a second while the downloads panel is open. 300 finished albums there is
        2.3 MB of JSON a poll; one peer's is a few KB. The asks go side by side.

        Never raises: this is read on every downloads-panel refresh and by the poller, and a
        misconfigured or briefly unreachable slskd should degrade to "no live progress"
        rather than breaking the whole panel. get_client() is inside the try for that reason
        - it throws on missing config. As before, one failure answers nothing at all, not a
        partial list: a job missing from a partial one would look like its peer had vanished.
        """
        names = sorted({name for name in usernames if name})
        if not names:
            return []

        try:
            client = await self.get_client()
            answers = await asyncio.gather(*(asyncio.to_thread(self._user_downloads, client, n) for n in names))
            return [answer for answer in answers if answer]

        except Exception:
            logger.error("failed to fetch downloads from slskd", extra={"frontend": True, "src": "slskd"})
            logger.error(traceback.format_exc())
            return []

    @staticmethod
    def _user_downloads(client, username: str) -> dict | None:
        """One user's downloads, or None when slskd holds none - its 404, and no failure."""
        transfers = client.transfers
        #? encoded whole, a "/" included - slskd_api's own quote() leaves that one as a path separator
        url = transfers.api_url + f"/transfers/downloads/{quote(username, safe='')}"
        try:
            return transfers.session.get(url).json()
        except HTTPError as exc:
            #? slskd_api's session raises on a non-2xx (see enqueue)
            if getattr(exc.response, "status_code", None) == 404:
                return None
            raise


    async def ping(self, admin: bool = True) -> dict:
        """
        Whether deadwax can search through slskd now - You's Connections row (an admin's, and someone's with Settings
        and the log, since 2.0.4). `status` ok, or failed with `code`, the short name the app keys its word on
        (NOT_LOGGED_IN, 401, CONNECTION_ERROR...), and `error`, the sentence under it: what is wrong, and where to
        put it right (PING_WORDS; slskd's own state in describe_server_state's words). The log keeps its own lines.
        `admin`: the reader may change slskd's address and key - anyone else is told only an admin can
        (PING_WORDS_NOT_ADMIN).
        """
        words = {**PING_WORDS, **({} if admin else PING_WORDS_NOT_ADMIN)}
        logger.info("pinging slskd to check connectivity")

        try:
            client = await self.get_client()
            state = await asyncio.to_thread(client.application.state)

            if not state:
                logger.error("slskd ping didnt return a state")
                return {"status": "failed", "error": PING_WORDS["NO_STATE"], "code": "NO_STATE"}

            #? slskd's API answering says the container is up and the key is right. It says
            #? NOTHING about the connection to Soulseek, which is the one a search needs - so a
            #? pill that stopped here read "ok" right up until the first search failed with a
            #? 409, and then the search took the blame for it. Report what slskd reports.
            connection = describe_server_state(state)

            if not connection["ok"]:
                #? connecting is a state it passes THROUGH; the others are states it sits in
                report = logger.warning if connection["code"] == "CONNECTING" else logger.error
                report(connection["detail"], extra={"frontend": True, "src": "slskd"})
                return {"status": "failed", "error": connection["detail"], "code": connection["code"]}

            logger.info("slskd functionality enabled, auth correct, and connection successful")
            logger.info("Connection successful", extra={"frontend": True, "src":"slskd"})
            return {"status": "ok"}


        except HTTPError as exc:
            status = exc.response.status_code
            logger.error(f"slskd ping replied but failed with HTTP error, status code: {status}")

            if status == 401:
                logger.error("slskd http 401, slskd functionality enabled, connection possible, but auth invalid")
                return {"status": "failed", "error": words[401], "code": 401}

            if status == 502:
                logger.error("slskd http 502, slskd functionality enabled, connection not made cause backend is down")
                return {"status": "failed", "error": PING_WORDS[502], "code": 502}

            else:
                logger.error(f"slskd uncaught HTTP error {status}, unknown")
                return {"status": "failed", "error": PING_WORDS["UNKNOWN_HTTP_ERROR"].format(status=status),
                        "code": "UNKNOWN_HTTP_ERROR"}
    

        except ConnectionError:
            logger.error("slskd ping failed with connection error, functionality enabled, but couldnt connect to the url provided (no auth checked)")
            return {"status": "failed", "error": words["CONNECTION_ERROR"], "code": "CONNECTION_ERROR"}

        except ValueError as e:
            #? (2.0.4) get_client's own refusals - SLSKD_URL unusable, SLSKD_APIKEY not set: said, not "unknown".
            #? requests' own ValueErrors (an InvalidURL) are the unknown below, as they always were
            if isinstance(e, RequestException):
                logger.error("slskd ping failed unexpectedly")
                logger.error(traceback.format_exc())
                return {"status": "failed", "error": PING_WORDS["UNKNOWN_ERROR"], "code": "UNKNOWN_ERROR"}
            return {"status": "failed", "error": words["NOT_SET_UP"].format(problem=e), "code": "NOT_SET_UP"}

        except Exception:
            logger.error("slskd ping failed unexpectedly")
            logger.error(traceback.format_exc())
            return {"status": "failed", "error": PING_WORDS["UNKNOWN_ERROR"], "code": "UNKNOWN_ERROR"}



