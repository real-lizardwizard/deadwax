import asyncio
import re
import traceback
import slskd_api
from requests.exceptions import HTTPError, ConnectionError
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
#? 429 is slskd's own one-at-a-time limiter - a static SemaphoreSlim(1, 1) taken with Wait(0) -
#? so two overlapping searches get it: two browser tabs, or a retry on top of one still running.
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
            logger.error(f"failed to create slskd client, traceback in logs", extra={"frontend": True, "src":"slskd"})
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
        """
        client = await self.get_client()
        running: list[tuple[str, str]] = []

        for query in queries:
            logger.info(f"searching slskd for: {query}", extra={"frontend": True, "src": "slskd"})

            try:
                state = await asyncio.to_thread(
                    client.searches.search_text,
                    searchText=query,
                    searchTimeout=search_timeout_ms,
                )

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


    async def enqueue(self, username: str, files: list[dict]) -> bool:
        """
        Queue a download. `files` must be [{'filename': ..., 'size': ...}] exactly as returned
        by search_responses - slskd matches on those two fields.
        """
        logger.info(
            f"queueing {len(files)} files from {username}",
            extra={"frontend": True, "src": "slskd"},
        )
        client = await self.get_client()

        payload = [{"filename": f["filename"], "size": f["size"]} for f in files]

        try:
            ok = await asyncio.to_thread(client.transfers.enqueue, username=username, files=payload)

            if ok:
                logger.info(f"queued {len(files)} files from {username}", extra={"frontend": True, "src": "slskd"})
            else:
                logger.error(f"slskd refused the download from {username}", extra={"frontend": True, "src": "slskd"})

            return bool(ok)

        except Exception:
            logger.error(f"failed to queue download from {username}", extra={"frontend": True, "src": "slskd"})
            logger.error(traceback.format_exc())
            return False


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


    async def get_downloads(self) -> list[dict]:
        """
        All current downloads, grouped by user then directory.

        Never raises: this is read on every downloads-panel refresh and by the poller, and a
        misconfigured or briefly unreachable slskd should degrade to "no live progress"
        rather than breaking the whole panel. get_client() is inside the try for that reason
        - it throws on missing config.
        """
        try:
            client = await self.get_client()
            return await asyncio.to_thread(client.transfers.get_all_downloads, includeRemoved=False)

        except Exception:
            logger.error("failed to fetch downloads from slskd", extra={"frontend": True, "src": "slskd"})
            logger.error(traceback.format_exc())
            return []


    async def ping(self) -> dict:
        logger.info("pinging slskd to check connectivity")

        try:
            client = await self.get_client()
            state = await asyncio.to_thread(client.application.state)

            if not state:
                logger.error("slskd ping didnt return a state")
                return {"status": "failed", "error": "slskd ping didnt return a state", "code": "NO_STATE"}

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
            logger.info(f"Connection successful", extra={"frontend": True, "src":"slskd"})
            return {"status": "ok"}


        except HTTPError as exc:
            status = exc.response.status_code
            logger.error(f"slskd ping replied but failed with HTTP error, status code: {status}")

            if status == 401:
                logger.error("slskd http 401, slskd functionality enabled, connection possible, but auth invalid")
                return {"status": "failed", "error": "slskd http 401, slskd functionality enabled, connection possible, but auth invalid", "code": 401}

            if status == 502:
                logger.error("slskd http 502, slskd functionality enabled, connection not made cause backend is down")
                return {"status": "failed", "error": "slskd http 502, slskd functionality enabled, connection not made cause backend is down", "code": 502}

            else:
                logger.error(f"slskd uncaught HTTP error {status}, unknown")
                return {"status": "failed", "error": f"slskd uncaught HTTP error {status}, unknown", "code": "UNKNOWN_HTTP_ERROR"}
    

        except ConnectionError as exc:
            logger.error(f"slskd ping failed with connection error, functionality enabled, but couldnt connect to the url provided (no auth checked)")
            return {"status": "failed", "error": f"slskd ping failed with connection error, functionality enabled, but couldnt connect to the url provided (no auth checked)", "code": "CONNECTION_ERROR"}

        except Exception as e:
            logger.error(f"slskd ping failed unexpectedly")
            logger.error(traceback.format_exc())
            return {"status": "failed", "error": f"slskd ping failed unexpectedly", "code": "UNKNOWN_ERROR"}



