"""
The Cover Art Archive's front covers, passed on to the iPhone app (2.1.24) - what GET /deadwax/coverart/{kind}/{mbid}
answers (src/routes/coverart.py), so the app can draw a MusicBrainz album's cover in Search while talking only to
deadwax. The web app doesn't use it: it loads those covers from coverartarchive.org itself, as it always has.
notes/ios.md "The Cover Art Archive relay (2.1.24)" is the write-up; src/api/coverart_endpoint.py ArchiveFronts asks
the Archive.

HOW AN ASK IS ANSWERED (`CoverRelay.answer()`):

  1. A cover kept on disk is answered from there at once, without asking the Archive. One kept longer than
     FRESH_SECONDS (30 days - an editor can change a release's front) is still answered at once, and fetched again
     behind it: a new one replaces it, a 404 drops it, a failure leaves it.
  2. A cover the Archive answered 404 for is answered 404 again for MISS_SECONDS (five minutes) without asking - the
     brief memory that stops a list of twenty albums with no art asking twenty times on every scroll. Brief, because
     one answer can't tell a missing cover from an outage (notes/tooling.md), and a cover added since should show.
  3. A failure is remembered the same way, for FAILED_SECONDS, and answered as it was (502, or 504 for a slow one).
     One that looks like an outage - the Archive not answering, answering 429 or 5xx, or too slowly - holds EVERY
     cover not kept for OUTAGE_SECONDS: a 502 at once, the Archive not asked, so a list drawn meanwhile fails quickly
     rather than each row waiting for a deadline. Said once in deadwax's log when the hold begins.
  4. Otherwise the Archive is asked: one fetch per cover however many ask for it at once (single flight), and the ask
     waits ANSWER_SECONDS for it at most - under the phone's eight seconds - before a 504. The fetch itself carries
     on to its own deadline (FRONT_DEADLINE_SECONDS), shielded, so a slow Archive costs that ask its answer and the
     next ask finds the cover kept.
  5. BOUNDED (the review's): at most FETCHING_AT_ONCE fetches ask the Archive at once - a semaphore around the fetch
     alone, so the wait for a turn isn't part of its deadline; the ask's ANSWER_SECONDS still bounds what the phone
     waits - and at most PENDING_MAX fetches are under way, running or waiting their turn. An ask that would start one
     more is a 502 at once, nothing remembered, so it is asked again once they drain. A kept cover's refresh is a
     fetch like any other and counts against both; the cover is answered at once all the same, and with no room the
     refresh is simply not started this time.

WHERE THEY ARE KEPT: in a folder of deadwax's own, `deadwax-covers`, beside the player cache's `deadwax-player` -
inside PLAYER_CACHE_PATH, else the container's temporary space - made private (0700) and checked as the player's is
(src/player_cache.py open_folder). Not the config volume, which people back up: these are only a cache, and deleting
the folder costs one fetch from the Archive per cover. Not the player's own folder either, whose MP4s it counts,
clears and trims by its own rules. No setting of its own: PLAYER_CACHE_PATH moves both.

HOW MUCH: KEPT_MAX_BYTES, 128 MB - a few thousand 250px covers, the size Search's rows ask for. Past it the covers
served longest ago go first, until the folder is back under TRIM_TO of it; one too big for the cap alone is answered
and not kept, and none is written when the disk has less than player_cache.DISK_SPARE_BYTES to spare. Which was served
when is kept in memory; after a start, the folder's files are ordered by when each was fetched.

ERRORS DEGRADE: a folder that can't be used (said once) or a disk that fails only means covers are fetched from the
Archive each time; a fault in deadwax while fetching is a 502 with its traceback in the log, never an answer that
hangs. What the Archive answered goes to deadwax's own log at info level - never the event log a listener's page reads.
"""

import asyncio
import errno
import hashlib
import os
import re
import secrets
import shutil
import stat
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path

from src import player_cache
from src.api.coverart_endpoint import (FRONT_KINDS, FRONT_MAX_BYTES, FRONT_SIZES, MIME_EXTENSIONS, ArchiveDown,
                                       ArchiveFronts, ArchiveRefused, ArchiveSlow, archive_fronts)
from src.config import Config
from src.logger import logger

FOLDER_NAME = "deadwax-covers"

KEPT_MAX_BYTES = 128 << 20
TRIM_TO = 0.9
FRESH_SECONDS = 30 * 24 * 3600

MISS_SECONDS = 300
FAILED_SECONDS = 30
OUTAGE_SECONDS = 30
#? how long an ask waits for the Archive: under the iPhone app's own eight seconds (URLSessionTransport)
ANSWER_SECONDS = 7.0
#? The fetches asking the Archive at once - a browser's own six connections a host. Each can hold FRONT_MAX_BYTES
#? for FRONT_DEADLINE_SECONDS and carries on past its ask's answer, so without this a Search list of fifty asked
#? archive.org fifty times at once, and anyone asking new mbids in a loop could start hundreds.
FETCHING_AT_ONCE = 6
#? The fetches under way, running or waiting their turn: a Search list of fifty fits, queued six at a time. Past it
#? an ask for a cover not kept and not already being fetched is a 502 at once, and nothing is remembered of it.
PENDING_MAX = 64
#? misses and failures remembered at most, the oldest forgotten first
REMEMBERED = 4096
#? a .part a stopped process left behind is cleared when the folder is first used, once it is this old
LEFTOVER_SECONDS = 600

EXTENSIONS = {extension: mime for mime, extension in MIME_EXTENSIONS.items()}
#? a kept cover's name: its kind, mbid and size, and its type as the extension - `release-group_<mbid>_250.jpg`
KEPT_NAME = re.compile(
    r"^(?P<stem>(?:release|release-group)_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_"
    r"(?:250|500|1200))\.(?P<ext>" + "|".join(EXTENSIONS) + r")$"
)

Key = tuple[str, str, str]


def stem_of(key: Key) -> str:
    kind, mbid, size = key
    return f"{kind}_{mbid}_{size}"


@dataclass(frozen=True)
class Front:
    """A cover as passed on: its bytes and its type (one of MIME_EXTENSIONS')."""

    data: bytes
    mime: str

    @property
    def etag(self) -> str:
        #? of the bytes, as json_etag's: the same cover kept, fetched again, or never kept gives the same tag
        return '"' + hashlib.blake2b(self.data, digest_size=12).hexdigest() + '"'


@dataclass(frozen=True)
class Answer:
    """What the route answers: 200 with a front, 404 (the Archive has none), 502 or 504."""

    status: int
    front: Front | None = None


@dataclass
class _Kept:
    name: str
    size: int
    fetched_at: float


def _read(path: Path) -> bytes:
    """A kept cover's bytes - a file, never a link, and never more than a cover can be."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "rb") as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > FRONT_MAX_BYTES:
            raise OSError(errno.EINVAL, "not a kept cover")
        return file.read(FRONT_MAX_BYTES + 1)


class KeptCovers:
    """
    The covers on disk, and which was served when. Every method is ordinary blocking code, safe from any thread under
    one lock - the relay calls them with asyncio.to_thread, so the event loop never waits on the disk. A read happens
    outside the lock; everything that changes the folder or the index happens inside it.
    """

    def __init__(self, folder: Path | None = None, max_bytes: int | None = None, wall_clock=time.time):
        #? a folder given here is used exactly (the tests); otherwise PLAYER_CACHE_PATH's, read at every use
        self._fixed = folder
        self._max_bytes = max_bytes
        self.wall_clock = wall_clock
        self._lock = threading.Lock()
        self._using: Path | None = None
        #? stem -> kept, the one served longest ago first
        self._index: "OrderedDict[str, _Kept]" = OrderedDict()
        self._total = 0
        self._said: str | None = None

    @property
    def max_bytes(self) -> int:
        return self._max_bytes if self._max_bytes is not None else KEPT_MAX_BYTES

    @property
    def total(self) -> int:
        return self._total

    def _folder(self) -> Path | None:
        """The folder now, made and checked - read again from the folder when it is a new one - or None, said once."""
        if self._fixed is not None:
            folder, problem = player_cache._own(self._fixed)
        else:
            folder, problem = player_cache.open_folder(Config.PLAYER_CACHE_PATH, FOLDER_NAME)
        if folder is None:
            if problem != self._said:
                self._said = problem
                logger.warning(f"covers: the Cover Art Archive's covers for the iPhone app can't be kept on disk - "
                               f"{problem}. Until that is fixed each one is fetched from the Archive whenever it is "
                               f"asked for")
            return None
        self._said = None
        if folder != self._using:
            self._using = folder
            self._scan(folder)
            logger.info(f"covers: the Cover Art Archive's covers for the iPhone app are kept in {folder}, "
                        f"{self.max_bytes >> 20} MB at most")
        return folder

    def _scan(self, folder: Path) -> None:
        """What the folder holds, in the order each was fetched - and a stopped process's leftovers cleared."""
        found, stale = [], self.wall_clock() - LEFTOVER_SECONDS
        try:
            with os.scandir(folder) as entries:
                for entry in entries:
                    try:
                        info = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if not stat.S_ISREG(info.st_mode):
                        continue
                    named = KEPT_NAME.match(entry.name)
                    if named:
                        found.append((info.st_mtime, named["stem"], entry.name, info.st_size))
                    elif entry.name.endswith(".part") and info.st_mtime < stale:
                        try:
                            os.unlink(entry.path)
                        except OSError:
                            pass
        except OSError as e:
            #? what it held is unknown: nothing is answered from it, and what is put from here on is counted
            logger.warning(f"covers: {folder} couldn't be read ({e.strerror or e}) - its covers are fetched again")
        self._index.clear()
        self._total = 0
        for fetched_at, stem, name, size in sorted(found):
            #? two types of one cover (a write cut short between them): the later stays
            old = self._index.pop(stem, None)
            if old is not None:
                self._total -= old.size
                self._unlink(folder, old.name)
            self._index[stem] = _Kept(name, size, fetched_at)
            self._total += size
        self._trim(folder, keep=None)

    def get(self, key: Key) -> tuple[Front, float] | None:
        """A kept cover and when it was fetched (the wall clock), or None. Marks it served."""
        stem = stem_of(key)
        with self._lock:
            folder = self._folder()
            kept = self._index.get(stem) if folder is not None else None
            if kept is None:
                return None
            self._index.move_to_end(stem)
            name, fetched_at = kept.name, kept.fetched_at
        try:
            data = _read(folder / name)
        except OSError:
            #? gone from under it (the folder cleared by hand): forgotten, unless it was put again meanwhile
            with self._lock:
                now = self._index.get(stem)
                if now is not None and now.name == name and now.fetched_at == fetched_at:
                    del self._index[stem]
                    self._total -= now.size
            return None
        return Front(data, EXTENSIONS[name.rsplit(".", 1)[1]]), fetched_at

    def put(self, key: Key, front: Front) -> bool:
        """The cover kept - written under a temporary name and renamed into place, so a half-written one is never
        read - then the folder trimmed back under its cap. False when it wasn't (no folder, too big, a disk short of
        room or failing): the cover is still answered, only not kept."""
        stem, size = stem_of(key), len(front.data)
        name = f"{stem}.{MIME_EXTENSIONS[front.mime]}"
        with self._lock:
            folder = self._folder()
            if folder is None or size > self.max_bytes:
                return False
            try:
                free = shutil.disk_usage(folder).free
            except OSError:
                free = None
            if free is not None and free < size + player_cache.DISK_SPARE_BYTES:
                return False
            part = folder / f".{name}.{secrets.token_hex(4)}.part"
            try:
                fd = os.open(part, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
                with os.fdopen(fd, "wb") as file:
                    file.write(front.data)
                os.replace(part, folder / name)
            except OSError as e:
                logger.info(f"covers: a cover couldn't be kept in {folder} ({e.strerror or e}) - it is answered, "
                            f"and fetched again next time")
                self._unlink(folder, part.name)
                return False
            old = self._index.pop(stem, None)
            if old is not None:
                self._total -= old.size
                if old.name != name:
                    #? the same cover in another type: the new one replaces it
                    self._unlink(folder, old.name)
            self._index[stem] = _Kept(name, size, self.wall_clock())
            self._total += size
            self._trim(folder, keep=stem)
            return True

    def drop(self, key: Key) -> None:
        """A kept cover forgotten and removed - the Archive has no front for it any more."""
        stem = stem_of(key)
        with self._lock:
            folder = self._folder()
            old = self._index.pop(stem, None) if folder is not None else None
            if old is not None:
                self._total -= old.size
                self._unlink(folder, old.name)

    def _trim(self, folder: Path, keep: str | None) -> None:
        """Past the cap, the covers served longest ago removed until under TRIM_TO of it - never `keep`, the one just
        put, which is about to be answered."""
        if self._total <= self.max_bytes:
            return
        goal = int(self.max_bytes * TRIM_TO)
        for stem in list(self._index):
            if self._total <= goal:
                break
            if stem == keep:
                continue
            old = self._index.pop(stem)
            self._total -= old.size
            self._unlink(folder, old.name)

    @staticmethod
    def _unlink(folder: Path, name: str) -> None:
        try:
            os.unlink(folder / name)
        except OSError:
            pass


class CoverRelay:
    """The answers, with what is remembered between them: the misses, the failures, an outage's hold, the fetches
    under way. One per app (src/routes/coverart.py relay_of)."""

    def __init__(self, kept: KeptCovers | None = None, fronts: ArchiveFronts | None = None,
                 clock=time.monotonic, wall_clock=time.time):
        self.kept = kept if kept is not None else KeptCovers(wall_clock=wall_clock)
        self.fronts = fronts if fronts is not None else archive_fronts
        self.clock = clock
        self.wall_clock = wall_clock
        #? key -> until when (the monotonic clock)
        self._misses: "OrderedDict[Key, float]" = OrderedDict()
        #? key -> (until when, the status it was answered with)
        self._failures: "OrderedDict[Key, tuple[float, int]]" = OrderedDict()
        self._down_until = 0.0
        self._flights: dict[Key, asyncio.Task] = {}
        #? the turns at the Archive (FETCHING_AT_ONCE), one per event loop - a semaphore waited on belongs to its loop
        self._turns: tuple[asyncio.AbstractEventLoop, asyncio.Semaphore] | None = None
        #? said once while the fetches under way are at PENDING_MAX, again after they drain
        self._said_full = False

    async def answer(self, kind: str, mbid: str, size: str) -> Answer:
        if kind not in FRONT_KINDS or size not in FRONT_SIZES:
            raise ValueError(f"not a front the relay passes on: {kind} at {size}")
        key = (kind, mbid, size)
        try:
            kept = await asyncio.to_thread(self.kept.get, key)
        except Exception as e:
            #? the disk failing costs the keeping, never the cover
            logger.warning(f"covers: the disk cache failed - {type(e).__name__}: {e}", exc_info=True)
            kept = None
        if kept is not None:
            front, fetched_at = kept
            if self.wall_clock() - fetched_at > FRESH_SECONDS and self._held(key) is None:
                #? answered at once all the same; the fetch replaces it, drops it, or leaves it - and with
                #? PENDING_MAX under way already, isn't started this time
                self._flight(key)
            return Answer(200, front)
        held = self._held(key)
        if held is not None:
            return held
        task = self._flight(key)
        if task is None:
            #? too many under way: nothing remembered, so it is asked again once they drain
            return Answer(502)
        try:
            return await asyncio.wait_for(asyncio.shield(task), ANSWER_SECONDS)
        except TimeoutError:
            return Answer(504)

    def _held(self, key: Key) -> Answer | None:
        """What is remembered of this cover - or of the Archive, while an outage holds - or None: ask it."""
        now = self.clock()
        until = self._misses.get(key)
        if until is not None:
            if until > now:
                return Answer(404)
            del self._misses[key]
        failed = self._failures.get(key)
        if failed is not None:
            if failed[0] > now:
                return Answer(failed[1])
            del self._failures[key]
        if self._down_until > now:
            return Answer(502)
        return None

    def _pending(self, loop: asyncio.AbstractEventLoop) -> int:
        """The fetches under way on this event loop, running or waiting their turn."""
        return sum(1 for task in self._flights.values() if not task.done() and task.get_loop() is loop)

    def _flight(self, key: Key) -> asyncio.Task | None:
        """The fetch of this cover under way, or a new one - or None when PENDING_MAX are under way already. A task left
        by another event loop (a test's) is never joined, nor counted."""
        loop = asyncio.get_running_loop()
        task = self._flights.get(key)
        if task is not None and not task.done() and task.get_loop() is loop:
            return task
        if self._pending(loop) >= PENDING_MAX:
            if not self._said_full:
                self._said_full = True
                logger.info(f"covers: {PENDING_MAX} covers are being fetched from the Archive already - more are "
                            f"answered 502 until they are")
            return None
        task = loop.create_task(self._fetch(key))
        self._flights[key] = task
        task.add_done_callback(lambda done, key=key: self._landed(key, done))
        return task

    def _landed(self, key: Key, task: asyncio.Task) -> None:
        if self._flights.get(key) is task:
            del self._flights[key]
        if self._said_full and self._pending(task.get_loop()) < PENDING_MAX:
            self._said_full = False
        if not task.cancelled():
            #? _fetch answers every failure itself; this only keeps asyncio from saying "never retrieved"
            task.exception()

    def _turn(self) -> asyncio.Semaphore:
        """This event loop's turns at the Archive."""
        loop = asyncio.get_running_loop()
        if self._turns is None or self._turns[0] is not loop:
            self._turns = (loop, asyncio.Semaphore(FETCHING_AT_ONCE))
        return self._turns[1]

    async def _fetch(self, key: Key) -> Answer:
        kind, mbid, size = key
        try:
            #? the wait for a turn is outside the fetch, and so outside its deadline
            async with self._turn():
                got = await self.fronts.front(kind, mbid, size)
        except ArchiveSlow as e:
            return self._failed(key, 504, str(e), outage=True)
        except ArchiveDown as e:
            return self._failed(key, 502, str(e), outage=True)
        except ArchiveRefused as e:
            return self._failed(key, 502, str(e), outage=False)
        except Exception as e:
            logger.warning(f"covers: the {kind} {mbid}'s front couldn't be fetched - a fault in deadwax: "
                           f"{type(e).__name__}: {e}", exc_info=True)
            return self._failed(key, 502, None, outage=False)
        if got is None:
            self._failures.pop(key, None)
            self._remember(self._misses, key, self.clock() + MISS_SECONDS)
            await self._quietly(self.kept.drop, key)
            return Answer(404)
        front = Front(*got)
        self._failures.pop(key, None)
        self._misses.pop(key, None)
        await self._quietly(self.kept.put, key, front)
        return Answer(200, front)

    @staticmethod
    async def _quietly(work, *args) -> None:
        """The disk's part of a fetch: a failure there is logged, and costs only the keeping."""
        try:
            await asyncio.to_thread(work, *args)
        except Exception as e:
            logger.warning(f"covers: the disk cache failed - {type(e).__name__}: {e}", exc_info=True)

    def _failed(self, key: Key, status: int, why: str | None, outage: bool) -> Answer:
        now = self.clock()
        self._remember(self._failures, key, (now + FAILED_SECONDS, status))
        if outage:
            if self._down_until <= now and why:
                logger.info(f"covers: {why} - for {OUTAGE_SECONDS} s, covers deadwax hasn't kept are answered "
                            f"502 without asking the Archive")
            self._down_until = now + OUTAGE_SECONDS
        elif why:
            logger.info(f"covers: {why}")
        return Answer(status)

    @staticmethod
    def _remember(table: OrderedDict, key: Key, value) -> None:
        table[key] = value
        table.move_to_end(key)
        while len(table) > REMEMBERED:
            table.popitem(last=False)

    async def stop(self) -> None:
        """Every fetch under way cancelled - deadwax is stopping. Only this event loop's: another's has gone."""
        loop = asyncio.get_running_loop()
        tasks = [task for task in self._flights.values() if not task.done() and task.get_loop() is loop]
        for task in tasks:
            task.cancel()
        for task in tasks:
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
        self._flights.clear()
