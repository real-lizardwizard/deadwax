"""
The songs each person played (2.1.14): `POST /deadwax/me/history` takes starts, `GET /deadwax/me/history` pages
them back, newest first. What a start is, why it is kept as it is and what is skipped is src/play_history.py's;
this reads and writes them per user, through `current_user` like everything per user (`local` with logins off: one
history for everyone, `shared` in the answer, as the play queue's), every write behind the same-origin guard
(src/api/same_origin.py) like every other. deadwax's own data - Navidrome is asked nothing, so this is no Navidrome
route.

  - POST takes 1 to HISTORY_POST_MAX starts, each VALIDATED ON ITS OWN (HistoryStart): one that fails - a wrong
    type, no song id - or that can't be right (src/play_history.py clean_start) is skipped, the rest taken:
    -> {taken, skipped}. Only a body that isn't a batch at all (no `starts`, none, too many) is a 422 - the apps
    drop a batch refused with a 4xx, so one bad start must never cost the rest. Every field the apps send is
    declared (pydantic drops an undeclared one without a word); a field this deadwax doesn't know - a newer app's -
    is ignored, never refused. A start already kept is the same row - its `counted` ORed in - so a retry, or the
    phone's offline batch sent twice, changes nothing. The guard (`_guard`): the oldest past HISTORY_KEPT_MAX go,
    looked at once a day per person after a write, and sooner once HISTORY_TRIM_AFTER starts have been taken
    since.
  - GET answers up to `limit` plays newest first, and `next` - the last one's own time and song id - to ask for the
    page before it with (`before_at`, `before_id`). By count, not by day: the day is the device's own calendar's,
    which the server doesn't know.

No database: GET answers no plays and nothing more; POST is a 503 - the apps keep their starts and send them later.
A database that fails just now is a 503 either way. Every answer no-store.
"""

import asyncio
import time
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from src import play_history as rules
from src.config import Config
from src.logger import logger
from src.users import current_user

router = APIRouter()

#? the words of a 503
NO_RECORD = "deadwax can't keep what you played: its database isn't there"
UNREAD = "deadwax couldn't read what you played just now"
UNWRITTEN = "deadwax couldn't keep what you played just now"

#? user -> when their history was last looked at for the guard (time.monotonic)
_trimmed: dict[str, float] = {}
#? user -> the starts taken for them since the guard last looked
_taken: dict[str, int] = {}


def forget_trims() -> None:
    """Every guard's last look forgotten (the tests)."""
    _trimmed.clear()
    _taken.clear()


class HistorySong(BaseModel):
    """The song as the queue holds it - lib/resume.ts bare(), QueueTrack without its level. Every field the apps send
    declared; one this deadwax doesn't know ignored (a newer app's, or the web's `level` if it ever slipped through)."""
    model_config = ConfigDict(extra="ignore")
    id: str
    title: str = ""
    artist: str = ""
    album: str = ""
    albumId: str | None = None
    coverArt: str | None = None
    duration: float = 0
    contentType: str | None = None
    suffix: str | None = None
    sampleRate: int = 0
    bitDepth: int = 0
    channels: int = 0


class HistoryStart(BaseModel):
    """One start - validated on its own by record(), so one that fails is skipped, never the batch's refusal."""
    model_config = ConfigDict(extra="ignore")
    #? ms since the epoch, the device's clock: when the listen began
    at: int
    counted: bool = False
    #? the queue's id (lib/upNext.ts UpNextState.id) and the entry's key in it - only the app reads them
    queue: str | None = None
    entry: int | None = None
    song: HistorySong


class HistoryPost(BaseModel):
    """The batch: only its size is checked here - each start is HistoryStart's, one at a time (record())."""
    model_config = ConfigDict(extra="ignore")
    starts: list[Any] = Field(min_length=1, max_length=rules.HISTORY_POST_MAX)


def _start(item: Any) -> HistoryStart | None:
    """One start of a batch validated, or None - skipped, the rest of the batch kept."""
    try:
        return HistoryStart.model_validate(item)
    except ValidationError:
        return None


def _no_store(body: dict) -> JSONResponse:
    return JSONResponse(body, headers={"Cache-Control": "no-store"})


def _store(request: Request):
    store = getattr(request.app.state, "store", None)
    return store if store is not None and getattr(store, "available", False) else None


async def _guard(store, user: str, taken: int) -> None:
    """The oldest past HISTORY_KEPT_MAX gone - looked at once a day per person, and again sooner once HISTORY_TRIM_AFTER
    starts have been taken for them since (`taken` this write's), never in anyone's way."""
    now = time.monotonic()
    last = _trimmed.get(user)
    since = _taken.get(user, 0) + taken
    if last is not None and now - last < rules.HISTORY_TRIM_EVERY_S and since < rules.HISTORY_TRIM_AFTER:
        _taken[user] = since
        return
    _trimmed[user] = now
    _taken[user] = 0
    try:
        gone = await asyncio.to_thread(store.trim_history, user, rules.HISTORY_KEPT_MAX)
    except Exception as e:
        logger.error(f"couldn't trim {user}'s play history ({e})")
        return
    if gone:
        logger.info(f"{user}'s play history passed {rules.HISTORY_KEPT_MAX:,} songs: the oldest {gone:,} went")


@router.post("")
async def record(posted: HistoryPost, request: Request, user: str = Depends(current_user)):
    """Songs started, in either app - see the module. -> {taken, skipped}."""
    store = _store(request)
    if store is None:
        raise HTTPException(status_code=503, detail=NO_RECORD)
    now_ms = int(time.time() * 1000)
    starts = [start for start in (_start(item) for item in posted.starts) if start is not None]
    rows = [row for row in (rules.clean_start(start.model_dump(), now_ms) for start in starts) if row]
    try:
        await asyncio.to_thread(store.record_starts, user, rows)
    except Exception as e:
        logger.error(f"couldn't keep {len(rows)} of {user}'s plays ({e})")
        raise HTTPException(status_code=503, detail=UNWRITTEN)
    await _guard(store, user, len(rows))
    return _no_store({"taken": len(rows), "skipped": len(posted.starts) - len(rows)})


@router.get("")
async def history(request: Request, user: str = Depends(current_user),
                  limit: int = Query(rules.HISTORY_PAGE, ge=1, le=rules.HISTORY_PAGE_MAX),
                  before_at: int | None = Query(None, ge=0, le=rules.HISTORY_AT_MAX),
                  before_id: str = Query("", max_length=rules.HISTORY_ID_MAX)):
    """Newest first, up to `limit` - before (`before_at`, `before_id`), the last play of the page before, when given."""
    shared = not Config.logins_on()
    if before_id and before_at is None:
        raise HTTPException(status_code=422, detail="before_id goes with before_at")
    store = _store(request)
    if store is None:
        return _no_store({"plays": [], "next": None, "shared": shared})
    try:
        rows = await asyncio.to_thread(store.history_page, user, limit + 1, before_at, before_id)
    except Exception as e:
        logger.error(f"couldn't read {user}'s play history ({e})")
        raise HTTPException(status_code=503, detail=UNREAD)
    return _no_store(rules.page(rows, limit, shared))
