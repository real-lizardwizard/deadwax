"""
Last.fm's answers, kept (2.1.36 - notes/lastfm.md): in deadwax's own database (store.py lastfm_kept), parsed and
trimmed, shared by everyone - an artist's listeners and top songs are nobody's own.

STANDING, by age (standing(), pure):

  | age           | found                                         | "not known" (error 6)   |
  | under 3 days  | answered                                      | answered: none          |
  | 3-7 days      | answered                                      | asked first             |
  | 7-30 days     | answered at once, and asked again behind      | asked first             |
  | over 30 days  | asked first                                   | asked first             |

and whatever is kept is answered anyway when asking fails (Last.fm down, limiting, or refusing the key) - a kept answer
of any age beats none. A failure is never kept, and changes nothing kept.

ONE ASK PER KEY: a second ask of a key while one is under way waits for the first - a refresh behind included, which is
that key's ask too, so one runs at a time. The ask is shielded from whoever waits on it, so a page that stops waiting
(a deadline, a closed connection) costs it nothing: the answer is still kept when it comes. stop() cancels any under
way as deadwax stops.

SIZE: an answer over ROW_MAX_BYTES isn't kept (it is still answered). At start-up and once every TRIM_EVERY answers
kept, the table is trimmed past LASTFM_KEPT_BYTES down to TRIM_TO_BYTES, the answers used longest ago first - 50 MB
being half the "Reasonable Usage Cap" of 100 MB in Last.fm's terms. Between trims it can pass the cap by at most
TRIM_EVERY rows of ROW_MAX_BYTES (3.2 MB).

KEPT ONLY WHILE ITS KEY IS: an answer that comes after LASTFM_API_KEY was removed or replaced is answered, not kept -
and one being written as the key is removed is emptied again after. Keeping never raises: an answer written as ASCII
(a lone surrogate survives it), and any fault in keeping is said in the log while the answer is still answered.

EMPTIED with no key (at_start(), and the settings route's save that removes it): Last.fm's terms ask for its data to
go when its use ends. The table is deadwax's database's, not the MusicBrainz cache file's, so Server settings' Clear
of MusicBrainz's answers leaves it alone.
"""

import asyncio
import hashlib
import json
import time
from typing import Awaitable, Callable

from src import lastfm
from src.config import Config
from src.lastfm import Answer, NotKnown, Outcome, Unreachable, match_key, name_key
from src.logger import logger

DAY = 86400.0
FRESH_S = 7 * DAY
SERVED_S = 30 * DAY
NONE_FRESH_S = 3 * DAY

ROW_MAX_BYTES = 32 * 1024
LASTFM_KEPT_BYTES = 50 * 1024 * 1024
TRIM_TO_BYTES = 45 * 1024 * 1024
TRIM_EVERY = 100


def standing(found: bool, fetched_at: float, now: float) -> str:
    """"fresh" (answered, nothing asked), "stale" (answered, asked again behind) or "due" (asked first)."""
    age = max(0.0, now - fetched_at)
    if not found:
        return "fresh" if age < NONE_FRESH_S else "due"
    if age < FRESH_S:
        return "fresh"
    return "stale" if age < SERVED_S else "due"


# ----- the keys ------------------------------------------------------------------------------------------------------
#? LASTFM_SHAPE is read at each call, never captured: a bump means no row of the old shape is ever read again

def artist_key(method: str, mbid: str | None = None, name: str | None = None) -> str:
    """An artist's method, by MusicBrainz id when there is one, else by the name folded."""
    if mbid:
        return f"{lastfm.LASTFM_SHAPE}|{method}|mbid|{mbid.strip().lower()}"
    return f"{lastfm.LASTFM_SHAPE}|{method}|name|{name_key(name)}"


def album_key(method: str, artist: str, album: str) -> str:
    return f"{lastfm.LASTFM_SHAPE}|{method}|name|{name_key(artist)}|{name_key(album)}"


def release_group_key(method: str, mbid: str) -> str:
    """(2.1.42) An album's method kept under its MusicBrainz release group, whatever names it is asked of Last.fm by:
    names fold alike for different albums - name_key drops a bracketed aside and a leading "The", so "Fearless" and
    "Fearless (Taylor's Version)", "Live" and "Live [Bonus]", "The Wall" and "Wall" would share one answer, the first
    asked shown for both."""
    return f"{lastfm.LASTFM_SHAPE}|{method}|group|{mbid.strip().lower()}"


#? (2.1.44) a track's folded names past this many bytes are kept under their SHA-256 instead: the radio asks by a
#? title and an artist of up to 500 letters each, which can fold to 33 bytes a letter - a key that would leave no
#? room under ROW_MAX_BYTES for the row, so it would never be kept and be asked again at every radio
TRACK_KEY_MOST = 1024


def track_key(method: str, artist: str, title: str) -> str:
    """A track's method, by its artist's name and its title folded (name_key, match_key) - or, past TRACK_KEY_MOST
    bytes, by their SHA-256, so the key is never what stops a row being kept."""
    folded = f"{name_key(artist)}|{match_key(title)}"
    written = folded.encode("utf-8", "surrogatepass")
    if len(written) > TRACK_KEY_MOST:
        return f"{lastfm.LASTFM_SHAPE}|{method}|digest|{hashlib.sha256(written).hexdigest()}"
    return f"{lastfm.LASTFM_SHAPE}|{method}|name|{folded}"


def shape_prefix() -> str:
    return f"{lastfm.LASTFM_SHAPE}|"


# ----- keeping -------------------------------------------------------------------------------------------------------

Ask = Callable[[], Awaitable[Outcome]]


class Keeper:
    def __init__(self) -> None:
        self.asking: dict[str, asyncio.Task] = {}
        self.kept_count = 0
        #? the tests' to replace
        self.clock = time.time

    async def kept(self, store, key: str, ask: Ask) -> Outcome:
        """The answer for `key`: kept, or asked of Last.fm through `ask` (which answers deadwax's parsed shape as an
        Answer) and kept - see the module's table."""
        row = await store.lastfm_get(key, self.clock()) if _usable(store) else None
        kept = _outcome(row)
        if kept is None:
            return await asyncio.shield(self._asked(store, key, ask))
        stand = standing(isinstance(kept, Answer), row["fetched_at"], self.clock())
        if stand == "fresh":
            return kept
        if stand == "stale":
            self._asked(store, key, ask, behind=True)
            return kept
        fresh = await asyncio.shield(self._asked(store, key, ask))
        return fresh if isinstance(fresh, (Answer, NotKnown)) else kept

    def _asked(self, store, key: str, ask: Ask, behind: bool = False) -> asyncio.Task:
        """The ask of `key` under way, or a new one - `behind`, a refresh nobody waits for, whose failure is said once
        however many visits it answered (_behind is the new task's, never each visit's)."""
        task = self.asking.get(key)
        if task is None or task.done():
            task = self.asking[key] = asyncio.create_task(self._ask(store, key, ask))
            task.add_done_callback(lambda done: self._settled(key, done))
            if behind:
                task.add_done_callback(lambda done: _behind(key, done))
        return task

    def _settled(self, key: str, task: asyncio.Task) -> None:
        if self.asking.get(key) is task:
            del self.asking[key]

    async def _ask(self, store, key: str, ask: Ask) -> Outcome:
        """Last.fm asked, and what it answered kept. Never raises but for a cancellation: an answer that can't be kept
        is still answered."""
        #? the key it is asked with - read here, as the client reads it, with nothing awaited between
        asked_with = Config.lastfm_key()
        try:
            outcome = await ask()
        except Exception as e:
            #? a fault in deadwax's own reading of an answer: the client itself never raises
            logger.warning(f"Last.fm's answer for {key} couldn't be read - a fault in deadwax: {type(e).__name__}",
                           exc_info=True)
            return Unreachable(f"a fault in deadwax ({type(e).__name__})")
        try:
            await self._keep(store, key, outcome, asked_with)
        except Exception as e:
            logger.warning(f"Last.fm's answer for {key} couldn't be kept - a fault in deadwax: {type(e).__name__}",
                           exc_info=True)
        return outcome

    async def _keep(self, store, key: str, outcome: Outcome, asked_with: str | None) -> None:
        if not _usable(store) or not isinstance(outcome, (Answer, NotKnown)):
            return
        if not asked_with or Config.lastfm_key() != asked_with:
            #? the key removed (Last.fm's data goes when its use ends) or replaced while Last.fm was asked
            logger.info(f"Last.fm's answer for {key} came after LASTFM_API_KEY changed, so it isn't kept")
            return
        body = None
        if isinstance(outcome, Answer):
            #? ASCII: a lone surrogate (half a pair, which json.loads makes of an escape) is written as an escape -
            #? UTF-8 can't hold it - and read back as it was
            body = json.dumps(outcome.body, ensure_ascii=True, separators=(",", ":"))
            if len(body) + len(key.encode()) > ROW_MAX_BYTES:
                logger.info(f"Last.fm's answer for {key} is over {ROW_MAX_BYTES // 1024} KB, so it isn't kept")
                return
        if not await store.lastfm_put(key, body, self.clock()):
            return
        if not Config.lastfm_key():
            #? removed while this was written: the save's emptying runs on a thread of its own and may have landed
            #? first - so it is emptied again, after
            await store.lastfm_clear()
            return
        self.kept_count += 1
        if self.kept_count % TRIM_EVERY == 0:
            await _trim(store)

    async def stop(self) -> None:
        """deadwax is stopping: every ask under way cancelled."""
        tasks = list(self.asking.values())
        for task in tasks:
            task.cancel()
        for task in tasks:
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
        self.asking.clear()


def _usable(store) -> bool:
    return store is not None and getattr(store, "available", False)


def _outcome(row: dict | None) -> Outcome | None:
    """A kept row as the answer it was - None for no row, or one that can't be read."""
    if row is None:
        return None
    if row["body"] is None:
        return NotKnown()
    try:
        return Answer(json.loads(row["body"]))
    except ValueError:
        return None


async def _trim(store) -> None:
    dropped = await store.lastfm_trim(LASTFM_KEPT_BYTES, TRIM_TO_BYTES)
    if dropped:
        logger.info(f"Last.fm's kept answers trimmed to {TRIM_TO_BYTES >> 20} MB: {dropped} used longest ago dropped")


def _behind(key: str, task: asyncio.Task) -> None:
    """A refresh behind, ended: its failure said, at info, and nothing else."""
    if task.cancelled():
        return
    if task.exception() is not None:
        #? _ask never raises; should it ever, it is said rather than lost
        logger.warning(f"Last.fm's kept answer for {key} couldn't be refreshed - a fault in deadwax: "
                       f"{type(task.exception()).__name__}")
        return
    outcome = task.result()
    if not isinstance(outcome, (Answer, NotKnown)):
        logger.info(f"Last.fm's kept answer for {key} couldn't be refreshed ({type(outcome).__name__}): it's answered "
                    f"as it is")


keeper = Keeper()


async def kept(store, key: str, ask: Ask) -> Outcome:
    return await keeper.kept(store, key, ask)


async def stop() -> None:
    await keeper.stop()


async def at_start(store, key_set: bool) -> None:
    """At start-up: with no key, every kept answer gone; with one, the answers of any older shape, and the table
    trimmed past its cap."""
    if not _usable(store):
        return
    if not key_set:
        dropped = await store.lastfm_clear()
        if dropped:
            logger.info(f"no LASTFM_API_KEY, so Last.fm's {dropped} kept answer(s) were emptied")
        return
    dropped = await store.lastfm_clear(keep_prefix=shape_prefix())
    if dropped:
        logger.info(f"{dropped} of Last.fm's kept answers were of an older shape, and were dropped")
    #? the trim every TRIM_EVERY answers counts in memory, and deadwax restarts with every update: a start trims too
    await _trim(store)
