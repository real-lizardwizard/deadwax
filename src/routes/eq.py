"""
AutoEq through deadwax, for the iPhone app's EQ (2.1.7) - `GET /deadwax/eq/autoeq` (search AutoEq's list) and
`GET /deadwax/eq/autoeq/{id}` (one result's ParametricEQ.txt): a user's routes (tests/test_logins.py ROUTES), the
describe routes' kind - an outside source, read for one person's listening. The phone never talks to GitHub.
notes/ios-specs/eq.md (on `ios`) section 2 is the spec; notes/ios.md "The EQ's AutoEq routes (2.1.7)" what was
built. src/autoeq.py reads the list and searches it (pure); src/api/autoeq_endpoint.py asks GitHub.

KEPT, in the database (store.py autoeq_list, autoeq_meta, autoeq_profile) and, for the list, in memory - one per app
(app.state.autoeq), read from the database at the first ask after a start:

  - THE LIST at one commit of AutoEq's master, and every profile fetched at that same commit, so the list and its
    files always agree. Older than a week (src/autoeq.py REFRESH_SECONDS), it is fetched again in the background -
    one at a time, under an asyncio.Lock - while the old one answers; with none at all, it is fetched before
    answering (FIRST_FETCH_SECONDS at most - what was being fetched carries on for the next ask). When master's
    commit is the one kept, nothing more is fetched and nothing dropped: only the time moves. A new list replaces
    the old in one transaction, and every kept profile goes with it. A background refresh that failed is not tried
    again for RETRY_SECONDS, while the old list answers.
  - A PROFILE once fetched, at its commit: asked again, it is answered from the database without asking GitHub -
    while the list is still at that commit.

Failures in words for whoever reads them (`detail`, which the app's ErrorWords say - eq.md 3.17): no list and GitHub
not answering with one, or a profile that can't be fetched - 503 UNREACHABLE; an id not in the list, or a profile
GitHub answers 404 for - 404 GONE. What GitHub answered goes to deadwax's own log (the container's output) at info
level, never the event log a listener's page could show.
"""

import asyncio
import dataclasses
import time

from fastapi import APIRouter, HTTPException, Path, Query, Request, Response

from src.api.autoeq_endpoint import Unreachable, autoeq_client
from src.autoeq import (FIRST_FETCH_SECONDS, ID_PATTERN, RETRY_SECONDS, Result, Row, is_stale, parse_index,
                        profile_answer, row_answer, rows_of, search, when)
from src.logger import logger

router = APIRouter()

UNREACHABLE = "deadwax can't reach AutoEq just now."
GONE = "AutoEq doesn't have that measurement any more."

#? a profile at a commit never changes: the phone may keep the answer a day without asking
PROFILE_CACHE = "private, max-age=86400"


class Gone(Exception):
    """AutoEq doesn't have that result, or GitHub doesn't have its file."""


class KeptList:
    """AutoEq's list as this deadwax holds it in memory, and the one refresh at a time."""

    def __init__(self) -> None:
        self.read = False
        self.sha: str | None = None
        self.fetched_at: float | None = None
        self.rows: list[Row] = []
        self.by_id: dict[str, Result] = {}
        self.lock = asyncio.Lock()
        self.refreshing: asyncio.Task | None = None
        #? when the last refresh failed - a list still answering is not asked for again until RETRY_SECONDS on
        self.failed_at: float | None = None

    def take(self, sha: str, fetched_at: float, results: list[Result]) -> None:
        self.rows = rows_of(results)
        self.by_id = {result.id: result for result in results}
        self.sha, self.fetched_at, self.failed_at = sha, fetched_at, None

    async def read_kept(self, store) -> None:
        """The list kept in the database, read once after a start - under the lock, so a second ask meanwhile
        waits for it rather than finding nothing and asking GitHub."""
        if self.read:
            return
        async with self.lock:
            if self.read:
                return
            kept = await store.autoeq_list_get() if store is not None else None
            if kept and self.sha is None:
                self.take(kept["sha"], kept["fetched_at"], [Result(**row) for row in kept["results"]])
            self.read = True

    def refresh(self, store) -> asyncio.Task:
        """The refresh under way, or a new one."""
        if self.refreshing is None or self.refreshing.done():
            self.refreshing = asyncio.create_task(self._fetch(store))
            self.refreshing.add_done_callback(_settled)
        return self.refreshing

    async def _fetch(self, store) -> None:
        async with self.lock:
            if self.sha is not None and not is_stale(self.fetched_at, time.time()):
                return
            try:
                sha = await autoeq_client.master_commit()
                if sha == self.sha:
                    now = time.time()
                    if store is not None:
                        await store.autoeq_list_seen(sha, now)
                    self.fetched_at, self.failed_at = now, None
                    logger.info(f"AutoEq's list is unchanged at {sha[:7]}")
                    return
                #? on a worker thread: the list is 851 KB, parsed in about 60 ms - the player's streams share this loop
                results, skipped = await asyncio.to_thread(parse_index, await autoeq_client.index(sha))
                if skipped:
                    logger.info(f"AutoEq's list at {sha[:7]}: {skipped} line(s) didn't parse and were skipped")
                if not results:
                    raise Unreachable(f"GitHub's answer for AutoEq's list at {sha[:7]} held no results")
            except Unreachable as e:
                self.failed_at = time.time()
                logger.info(f"AutoEq's list couldn't be fetched - {e}")
                raise
            now = time.time()
            if store is not None:
                await store.autoeq_list_put(sha, now, [dataclasses.asdict(result) for result in results])
            self.take(sha, now, results)
            logger.info(f"AutoEq's list fetched at {sha[:7]}: {len(results)} results")

    async def ready(self, store) -> None:
        """A list to answer with - the kept one, refreshed behind it when a week old - or Unreachable."""
        await self.read_kept(store)
        if self.sha is None:
            try:
                #? shielded: a slow GitHub costs this ask its answer, not the fetch, which the next ask finds
                await asyncio.wait_for(asyncio.shield(self.refresh(store)), FIRST_FETCH_SECONDS)
            except TimeoutError as e:
                logger.info(f"AutoEq's list took more than {FIRST_FETCH_SECONDS:.0f} s to fetch")
                raise Unreachable("timed out") from e
            if self.sha is None:
                raise Unreachable("no list")
            return
        now = time.time()
        if is_stale(self.fetched_at, now) and (self.failed_at is None or now - self.failed_at >= RETRY_SECONDS):
            self.refresh(store)

    async def profile(self, store, result_id: str) -> tuple[Result, str]:
        """A result and its ParametricEQ.txt at the list's commit - Gone, or Unreachable."""
        await self.ready(store)
        result = self.by_id.get(result_id)
        if result is None:
            raise Gone()
        sha = self.sha
        kept = await store.autoeq_profile_get(result_id) if store is not None else None
        #? only the list's own commit's: one kept before a new list (a fetch that crossed it) is fetched again
        if kept and kept.get("sha") == sha:
            return result, kept["text"]
        try:
            text = await autoeq_client.profile(sha, result.path)
        except Unreachable as e:
            logger.info(f"AutoEq's {result.source} {result.name!r} couldn't be fetched - {e}")
            raise
        if text is None:
            logger.info(f"GitHub answered 404 for AutoEq's {result.path} at {sha[:7]}")
            raise Gone()
        if store is not None:
            await store.autoeq_profile_put(result_id, sha, text, time.time())
        return result, text


def _settled(task: asyncio.Task) -> None:
    #? a refresh's Unreachable is logged by _fetch, and retrieved here so asyncio doesn't log it again; anything else
    #? is a fault in deadwax, said as one
    if task.cancelled():
        return
    error = task.exception()
    if error is not None and not isinstance(error, Unreachable):
        logger.error(f"AutoEq's list couldn't be refreshed: {type(error).__name__}: {error}")


def kept_list(request: Request) -> KeptList:
    state = request.app.state
    kept = getattr(state, "autoeq", None)
    if kept is None:
        kept = state.autoeq = KeptList()
    return kept


async def stop_refreshing(app) -> None:
    """A refresh under way, cancelled - deadwax is stopping."""
    kept = getattr(app.state, "autoeq", None)
    task = kept.refreshing if kept is not None else None
    if task is not None and not task.done():
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Unreachable):
            pass


@router.get("/autoeq")
async def search_autoeq(
    request: Request,
    q: str = Query(..., min_length=1, max_length=100),
    limit: int = Query(30, ge=1, le=50),
):
    """AutoEq's corrections whose names hold every word of `q` - one row per headphone, the best source first."""
    kept = kept_list(request)
    try:
        await kept.ready(getattr(request.app.state, "store", None))
    except Unreachable:
        raise HTTPException(status_code=503, detail=UNREACHABLE)
    found = search(kept.rows, q)
    return {"results": [row_answer(row) for row in found[:limit]], "total": len(found),
            "list_from": when(kept.fetched_at)}


@router.get("/autoeq/{id}")
async def autoeq_profile(
    request: Request,
    response: Response,
    id: str = Path(..., pattern=ID_PATTERN),  # noqa: A002 - the spec's name for it, and the route's
):
    """One result's ParametricEQ.txt, as AutoEq wrote it, at the list's commit."""
    kept = kept_list(request)
    try:
        result, text = await kept.profile(getattr(request.app.state, "store", None), id)
    except Gone:
        raise HTTPException(status_code=404, detail=GONE)
    except Unreachable:
        raise HTTPException(status_code=503, detail=UNREACHABLE)
    response.headers["Cache-Control"] = PROFILE_CACHE
    return profile_answer(result, text)
