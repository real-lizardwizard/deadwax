"""
MusicBrainz's answers kept on disk (2.0.0-player.54) - the layer under ResponseCache's hour in memory.

Asked for by James (2026-10-15): "the first time I search an artist it asks musicbrainz, and when it gets
results it caches them so the next time I search that artist, it's instant." Until then every answer was
kept in memory alone - an hour, 64 of them - so a search repeated after an hour, after a restart (every
image update) or after a few album pages asked MusicBrainz again, at a request a second, when it is often
slow or away.

WHAT IS KEPT: every answer request_with_retries keeps in memory - successes only, failures never, on disk
as in memory (the decision's whole reason: a bad minute must not become a bad month) - in a SQLite file of
its own, musicbrainz-cache.db (inside the FOLDER MUSICBRAINZ_CACHE_PATH names, which can be the player
cache's fast-disk mount; by default beside the database, never the database itself), its JSON compressed
with zlib, under the very key ResponseCache keys it with, with when it was fetched and when it was last
used. Shared by everyone: MusicBrainz's data isn't anybody's own.

HOW BIG: MUSICBRAINZ_CACHE_MB, 200 by default. Past it the answers used longest ago are dropped until the
file's used pages are back under TRIM_TO of it (so a full cache isn't trimmed on every answer), and the
pages freed are given back to the disk (auto_vacuum = INCREMENTAL). An answer bigger than that alone is
not kept. 0 is off: memory only, as before - the file is neither read nor written then, only left where
it is (Clear still empties it).

FRESH ENOUGH: a search (anything asked with a `query`) is old after SEARCH_FRESH_SECONDS (7 days), a
lookup (an artist, a release, a release group's pressings, a discography) after LOOKUP_FRESH_SECONDS (30).
An old answer is still answered AT ONCE - that is the point - and the client asks for a new one quietly
behind it (MusicBrainzClient._queue_refresh), which replaces it only if it comes. When MusicBrainz is
away, answers of any age keep working.

NEVER IN THE WAY: SQLite runs on one worker thread of its own, never on the event loop - every read, write,
trim and Clear in the order asked. A read not answered within READ_TIMEOUT_SECONDS (1 s: about what
MusicBrainz's quickest answer costs, at its request a second) is given up, and MusicBrainz is asked
instead; a write is queued and never waited for. A musicbrainz-cache.db that can't be read as a database
is set aside (renamed, with its journal) and a new one started, with one log line - nothing is lost but
speed - by real use (a read, a write, Clear), never by the settings' look at it (stats); a new file's tables
and the meta rows saying whose they are are made in one transaction, so one cut short is never taken for
somebody else's. A file of any
other name is never set aside, and one that IS a database but not this one is left alone, nothing saved
until the setting names another folder. A failure inside a transaction is rolled back at once, so it
costs that answer and no more. Errors degrade: a disk that fails only means MusicBrainz is asked, as
before.
"""

import asyncio
import json
import os
import sqlite3
import time
import zlib
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from src import saved_index
from src.config import (MUSICBRAINZ_CACHE_FILE, Config, is_the_database, musicbrainz_cache_file,
                        musicbrainz_cache_megabytes)
from src.logger import logger

#? What the file says it is, so a database that isn't this one is never written into or emptied
KIND = "deadwax: MusicBrainz's saved answers"
#? The shape of the table. A file of another shape is this one's own, and is emptied and made afresh.
FORMAT = "1"

SEARCH_FRESH_SECONDS = 7 * 24 * 3600
LOOKUP_FRESH_SECONDS = 30 * 24 * 3600

#? A read that hasn't answered in this long is given up for MusicBrainz (see the module's docstring)
READ_TIMEOUT_SECONDS = 1.0
#? Past the budget, answers go until the file's used pages are back under this share of it
TRIM_TO = 0.9
#? A file that couldn't be opened is tried again after this long (a volume being mounted, say)
RETRY_OPEN_SECONDS = 60.0
#? (2.0.0-player.56) the answers already saved, read into the saved-search index in steps this small - so a search
#? asked meanwhile waits behind one step at most, never behind the whole file (the worker does one thing at a time)
BACKFILL_ANSWERS = 25
BACKFILL_BYTES = 256 * 1024

#? One statement each, run inside ONE transaction with the meta rows (_make_tables) - never executescript,
#? which commits each CREATE on its own
SCHEMA = (
    """CREATE TABLE IF NOT EXISTS meta (
    name  TEXT PRIMARY KEY,
    value TEXT NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS answers (
    key        TEXT PRIMARY KEY,   -- json.dumps(ResponseCache.key(endpoint, params))
    body       BLOB NOT NULL,      -- zlib of the answer's JSON
    size       INTEGER NOT NULL,   -- len(body) + len(key), what dropping it gives back, roughly
    fetched_at REAL NOT NULL,      -- seconds since the epoch: when MusicBrainz gave it
    used_at    REAL NOT NULL       -- ...and when it was last answered with, which orders the dropping
)""",
    "CREATE INDEX IF NOT EXISTS answers_used ON answers (used_at)",
)


def is_search(params: dict | None) -> bool:
    """A search is anything asked with a `query`; everything else is a lookup or a browse."""
    return "query" in (params or {})


def fresh_for(params: dict | None) -> int:
    """How long an answer to this question is fresh, in seconds: a search 7 days, a lookup 30."""
    return SEARCH_FRESH_SECONDS if is_search(params) else LOOKUP_FRESH_SECONDS


def is_stale(params: dict | None, fetched_at: float, now: float) -> bool:
    """Whether an answer fetched at `fetched_at` is old enough to be asked for again behind itself."""
    return now - fetched_at > fresh_for(params)


def pack(payload) -> bytes:
    """An answer as kept: its JSON, compressed. json.dumps of what json.loads gave back is the same JSON."""
    return zlib.compress(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"), 6)


def unpack(body: bytes):
    """An answer as kept, as it was."""
    return json.loads(zlib.decompress(body))


class NotOurs(Exception):
    """The file isn't the saved answers - a database of something else's, or not named musicbrainz-cache.db at
    all. Left alone: never written into, emptied or set aside."""


class SavedAnswers:
    """
    The file, opened on first use and held open on the worker thread. `path` and `max_bytes` fix the
    file and the budget (the tests); left out, both are read from the settings at every use, so a change
    saved in the settings tab applies at once (the settings route calls reset() to close the old file).
    """

    def __init__(self, path: str | None = None, max_bytes: int | None = None, clock=time.time):
        self._path = path
        self._max_bytes = max_bytes
        self._clock = clock
        self._pool: ThreadPoolExecutor | None = None
        self._connection: sqlite3.Connection | None = None
        self._open_path: str | None = None
        #? path -> when it last failed to open (time.monotonic), so it isn't tried on every answer
        self._failed: dict[str, float] = {}
        #? why nothing is being saved, in words for the settings row - None when nothing is wrong
        self.problem: str | None = None
        #? (2.0.0-player.56) whether the open file's saved-search index can be used (SQLite without FTS5 can't make
        #? one: answers are still saved, Search just finds nothing saved), and the answers this run's backfill read
        self._index_ready = False
        self._index_checked = False
        self._index_said: str | None = None
        self._backfilled = 0
        #? when making the index last failed (a read-only or locked file - time.monotonic): answers are still read
        #? from it meanwhile, and the index is tried again after RETRY_OPEN_SECONDS
        self._index_failed_at: float | None = None
        #? closing (the app's lifespan ending): nothing more is queued - a backfill step already queued does nothing -
        #? so no step runs after the file is closed, reopening it on a thread that is going away (the review's catch:
        #? the next step then ran on a NEW worker against the old thread's connection, and SQLite's "objects created
        #? in a thread" error was taken for a broken file and the whole file set aside)
        self._closing = False

    # ------------------------------------------------------------- what the settings say now

    def path(self) -> str:
        return self._path or musicbrainz_cache_file()

    def max_bytes(self) -> int:
        return self._max_bytes if self._max_bytes is not None else musicbrainz_cache_megabytes() << 20

    def enabled(self) -> bool:
        """Whether answers are saved at all: MUSICBRAINZ_CACHE_MB isn't 0."""
        return self.max_bytes() > 0

    def now(self) -> float:
        """Wall time as this file keeps it: what `fetched_at` is measured in."""
        return self._clock()

    def is_stale(self, params: dict | None, fetched_at: float) -> bool:
        return is_stale(params, fetched_at, self._clock())

    # ------------------------------------------------------------- from the event loop

    async def get(self, key: str) -> tuple[dict, float] | None:
        """The answer kept under `key` and when it was fetched, or None - never waiting past READ_TIMEOUT_SECONDS."""
        if not self.enabled():
            return None
        try:
            found = await asyncio.wait_for(self._run(self._get, key), READ_TIMEOUT_SECONDS)
        except (asyncio.TimeoutError, TimeoutError):
            logger.info(
                f"MusicBrainz's saved answers took more than {READ_TIMEOUT_SECONDS:g}s to read, so "
                f"MusicBrainz is asked instead"
            )
            return None
        except Exception as e:
            logger.warning(f"couldn't read MusicBrainz's saved answers ({e}), so MusicBrainz is asked instead")
            return None
        if found is not None:
            #? used now: what orders the dropping. Queued, never waited for.
            self._later(self._touch, key, self._clock())
        return found

    def put(self, key: str, payload, fetched_at: float | None = None) -> None:
        """Keep a successful answer. Queued for the worker: nothing waits for the disk. `fetched_at` (the
        pages of one browse, which share their first page's - see MusicBrainzClient._browse) defaults to now."""
        if self.enabled():
            now = self._clock()
            self._later(self._put, key, payload, now, now if fetched_at is None else fetched_at)

    async def search(self, words: str) -> dict | None:
        """
        What the saved answers hold matching `words` (2.0.0-player.56, Search what's saved): the artists, albums and
        songs, in MusicBrainz's own shapes (saved_index.search). Read on the worker, never the event loop - and
        given up after READ_TIMEOUT_SECONDS, as a read is: None then, and when saving is off (0), there is no file
        yet, its index can't be used, or it failed - with one log line, never an error: Search draws MusicBrainz's
        answer alone, as before.
        """
        if not self.enabled():
            return None
        try:
            return await asyncio.wait_for(self._run(self._search, words), READ_TIMEOUT_SECONDS)
        except (asyncio.TimeoutError, TimeoutError):
            logger.info(f"MusicBrainz's saved answers took more than {READ_TIMEOUT_SECONDS:g}s to search, so Search "
                        f"shows MusicBrainz's answer alone")
            return None
        except Exception as e:
            logger.warning(f"couldn't search MusicBrainz's saved answers ({e}), so Search shows MusicBrainz's answer alone")
            return None

    def warm(self) -> None:
        """The app has started (its lifespan): the file opened on the worker if it is there - which reads the answers
        a file without an index already holds into one, in the background (2.0.0-player.56). Never makes a file."""
        if self.enabled():
            self._later(lambda: self._connection_for(False))

    async def stats(self) -> dict:
        """What the settings show beside Clear: the file, its size, how many answers it holds."""
        return await self._run(self._stats)

    async def clear(self) -> dict:
        """Every answer gone and the file shrunk to nothing much (the settings' Clear) - then its stats."""
        return await self._run(self._clear)

    async def reset(self) -> None:
        """The settings changed: close the file, so the next use opens the one they name, at their size."""
        await self._run(self._reset)

    async def flush(self) -> None:
        """Wait for everything queued so far (the tests, and shutting down)."""
        await self._run(lambda: None)

    async def close(self) -> None:
        if self._pool is None:
            return
        self._closing = True
        try:
            await self._run(self._close)
            pool, self._pool = self._pool, None
            pool.shutdown(wait=True)
        finally:
            #? closed: a later use (a test, a lifespan started again) opens it afresh, as before
            self._closing = False

    # ------------------------------------------------------------- the worker

    def _ensure_pool(self) -> ThreadPoolExecutor:
        if self._pool is None:
            #? ONE thread: every use of the file in the order asked, and the connection only ever on it
            self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="musicbrainz-answers")
        return self._pool

    async def _run(self, work, *args):
        return await asyncio.get_running_loop().run_in_executor(self._ensure_pool(), work, *args)

    def _later(self, work, *args) -> None:
        if self._closing:
            return
        def guarded():
            try:
                work(*args)
            except Exception as e:
                logger.warning(f"couldn't update MusicBrainz's saved answers ({e})")

        self._ensure_pool().submit(guarded)

    def _close(self) -> None:
        if self._connection is not None:
            try:
                self._connection.close()
            except sqlite3.Error:
                pass
        self._connection = self._open_path = None
        self._index_ready = self._index_checked = False
        self._index_failed_at = None

    def _reset(self) -> None:
        self._close()
        self._failed.clear()
        self.problem = None
        self._index_said = None

    def _connection_for(self, create: bool, repair: bool = True) -> sqlite3.Connection | None:
        """
        The file the settings name now, open - or None, `problem` saying why when something is wrong.
        `create` makes it when it isn't there (a write); `repair=False` is the settings' look at it (stats),
        which never sets a broken file aside nor starts a new one - that is left to the next write.
        """
        path = self.path()
        if self._connection is not None and self._open_path == path:
            return self._indexed(self._connection, path, repair)
        self._close()

        if is_the_database(path, Config.DB_PATH):
            self.problem = (f"{path} is deadwax's own database - the saved answers need a file of their own: "
                            f"point MUSICBRAINZ_CACHE_PATH at another folder")
            return None
        failed = self._failed.get(path)
        if failed is not None and time.monotonic() - failed < RETRY_OPEN_SECONDS:
            return None
        if not create and not os.path.exists(path):
            #? nothing to read - which puts nothing right: a problem a save found (a folder that can't be
            #? made, say) stands until a file opens or the settings are saved (reset). The build cleared it
            #? here, so a look a minute later (the Clear line's) showed a folder that can't be made as fine.
            return None
        if not repair and self._not_a_database(path):
            #? only looking: what would be set aside is left for the next answer saved to do
            return None

        try:
            connection = self._open(path, repair)
        except NotOurs as e:
            self._failed[path] = time.monotonic()
            if self.problem != str(e):
                logger.warning(f"MusicBrainz's answers aren't being saved: {e}")
            self.problem = str(e)
            return None
        except (OSError, sqlite3.Error) as e:
            if not repair and isinstance(e, sqlite3.DatabaseError) and not isinstance(e, sqlite3.OperationalError):
                #? broken, and only looking: left for the next answer saved to set aside - not held against it
                return None
            self._failed[path] = time.monotonic()
            problem = f"couldn't open {path} ({e})"
            if self.problem != problem:
                logger.warning(f"MusicBrainz's answers aren't being saved: {problem}")
            self.problem = problem
            return None

        self._connection, self._open_path = connection, path
        self._failed.pop(path, None)
        self.problem = None
        logger.info(f"MusicBrainz's answers are saved in {path}")
        return self._indexed(connection, path, repair)

    def _indexed(self, connection: sqlite3.Connection, path: str, repair: bool) -> sqlite3.Connection | None:
        """
        The open file, its saved-search index made sure of (2.0.0-player.56) - once per open, by real use: the
        settings' look (`repair=False`) only reads whether one is there, and writes nothing. A failure making it is
        the file's, as any other: the connection closed, None.
        """
        if self._index_checked:
            if self._index_failed_at is None or time.monotonic() - self._index_failed_at < RETRY_OPEN_SECONDS or not repair:
                return connection
            #? making it failed a minute ago: tried again on the file opened afresh (one opened read-only stays so)
            self._close()
            return self._connection_for(False, repair)
        if not repair:
            if not self._index_checked:
                meta = dict(connection.execute("SELECT name, value FROM meta").fetchall())
                self._index_ready = meta.get("index_format") == saved_index.INDEX_FORMAT
            return connection
        try:
            self._index_ready = self._ensure_index(connection, path)
            self._index_failed_at = None
        except sqlite3.OperationalError as e:
            #? locked, a full disk, read-only: the answers are still read (and saved, when they can be) as they were,
            #? without the index - Search finds nothing saved - and it is tried again after the retry minute (the
            #? review's catch: closing the file for it lost every saved answer of a read-only file 2.0.0-player.55
            #? still read)
            said = f"couldn't make the saved-search index ({e}), so Search won't find what is saved for now"
            if self._index_said != said:
                logger.warning(f"MusicBrainz's saved answers: {said}")
            self._index_said = said
            self._index_ready = False
            self._index_checked = True
            self._index_failed_at = time.monotonic()
            return connection
        self._index_checked = True
        if self._index_ready and self._backfill_left(connection):
            #? answers saved before there was an index: read into it, a step at a time, behind whatever is queued
            self._later(self._backfill_step)
        return connection

    def _open(self, path: str, repair: bool = True) -> sqlite3.Connection:
        #? the folder MUSICBRAINZ_CACHE_PATH names, made when it isn't there yet (a file of that name is
        #? an OSError here: nothing of it is touched, and the row says why)
        folder = os.path.dirname(path)
        if folder:
            os.makedirs(folder, exist_ok=True)

        #? Not a database at all (no SQLite header): set aside before SQLite opens it - which would
        #? otherwise decide for itself what to do with a journal lying beside it
        if self._not_a_database(path):
            self._set_aside(path, "it isn't a SQLite database")

        for attempt in (1, 2):
            #? autocommit: each write is its own transaction, and VACUUM can run
            connection = sqlite3.connect(path, timeout=5, isolation_level=None)
            try:
                tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
                if not tables:
                    #? before any table exists, or it can't be set: lets a trim give pages back to the disk
                    connection.execute("PRAGMA auto_vacuum = INCREMENTAL")
                    self._make_tables(connection)
                else:
                    meta = dict(connection.execute("SELECT name, value FROM meta").fetchall()) if "meta" in tables else {}
                    if meta.get("kind") != KIND:
                        connection.close()
                        raise NotOurs(f"{path} is a database, but not deadwax's saved answers - it is left alone. "
                                      f"Point MUSICBRAINZ_CACHE_PATH at a folder of its own")
                    if meta.get("format") != FORMAT:
                        #? this file's own, in another shape: emptied and made afresh
                        self._make_tables(connection, drop=True)
                connection.execute("PRAGMA synchronous = NORMAL")
                budget = self.max_bytes()
                if budget > 0:
                    #? the budget may have shrunk since the file was last open
                    self._trim(connection, budget)
                return connection
            except sqlite3.OperationalError:
                #? can't be opened or read (permissions, a full disk, locked) - not the file's fault
                connection.close()
                raise
            except sqlite3.DatabaseError as e:
                #? not a database, or a broken one
                connection.close()
                if attempt == 2 or not repair:
                    raise
                self._set_aside(path, e)
        raise AssertionError("unreachable")

    @staticmethod
    def _make_tables(connection: sqlite3.Connection, drop: bool = False) -> None:
        """
        The tables and the meta rows saying whose they are, in ONE transaction - all of it or none. Made
        a statement at a time on an autocommit connection, a file killed (or a disk filling) between the
        CREATEs and the meta rows was left with tables and no `kind`: refused ever after as "a database,
        but not deadwax's saved answers", nothing saved until it was deleted by hand (the review's
        catch). A failure rolls back to the file as it was - empty, made afresh next time.
        """
        connection.execute("BEGIN IMMEDIATE")
        try:
            if drop:
                connection.execute("DROP TABLE IF EXISTS answers")
                #? its index goes with it, made afresh by _ensure_index - over no answers
                if SavedAnswers._has_table(connection, "meta"):
                    connection.execute("DELETE FROM meta WHERE name LIKE 'index_%'")
            for statement in SCHEMA:
                connection.execute(statement)
            connection.executemany("INSERT OR REPLACE INTO meta (name, value) VALUES (?, ?)",
                                   (("kind", KIND), ("format", FORMAT)))
            connection.execute("COMMIT")
        except BaseException:
            SavedAnswers._rolled_back(connection)
            raise

    @staticmethod
    def _has_table(connection: sqlite3.Connection, name: str) -> bool:
        return connection.execute("SELECT 1 FROM sqlite_master WHERE name = ?", (name,)).fetchone() is not None

    def _ensure_index(self, connection: sqlite3.Connection, path: str) -> bool:
        """
        The saved-search index (2.0.0-player.56) beside the answers, of this version's shape - made when it isn't,
        in ONE transaction with the meta rows saying how far the answers already saved have been read into it
        (`index_at` of `index_to`, the answers' rowids): a file 2.0.0-player.54 or .55 made has its answers read in
        once, in the background (_backfill_step). False when it can't be (SQLite built without FTS5): answers are
        saved as ever, and Search finds nothing saved - said once.
        """
        meta = dict(connection.execute("SELECT name, value FROM meta").fetchall())
        if meta.get("index_format") == saved_index.INDEX_FORMAT and all(
                self._has_table(connection, table) for table in saved_index.INDEX_TABLES):
            triggers = connection.execute(
                f"SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name IN "
                f"({', '.join('?' for _ in saved_index.TRIGGER_NAMES)})", saved_index.TRIGGER_NAMES).fetchone()[0]
            if triggers == len(saved_index.TRIGGER_NAMES) and saved_index.STALE not in meta:
                return True
            #? the answers have changed without it - an older deadwax (2.0.0-player.55) used the file since this one
            #? indexed it, adding, trimming or clearing answers it never told the index of: made afresh and read in again
            logger.info("MusicBrainz's saved answers changed while the saved-search index wasn't kept (an older "
                        "deadwax used the file?) - it is read into the index again, in the background")
        connection.execute("BEGIN IMMEDIATE")
        try:
            saved_index.make_index(connection, drop=True)
            last = connection.execute("SELECT COALESCE(MAX(rowid), 0) FROM answers").fetchone()[0]
            connection.executemany("INSERT OR REPLACE INTO meta (name, value) VALUES (?, ?)", (
                ("index_format", saved_index.INDEX_FORMAT), ("index_at", "0"), ("index_to", str(last))))
            connection.execute("DELETE FROM meta WHERE name = ?", (saved_index.STALE,))
            connection.execute("COMMIT")
        except sqlite3.OperationalError as e:
            self._rolled_back(connection)
            #? FTS5 missing, or too old for a contentless table deleted from (3.43): no index - anything else (locked,
            #? a full disk) is the file's, and tried again
            if not any(word in str(e).lower() for word in ("fts5", "no such module", "unrecognized", "contentless")):
                raise
            said = f"this SQLite can't search text (FTS5, 3.43 or newer), so Search won't find what is saved ({e})"
            if self._index_said != said:
                logger.warning(f"MusicBrainz's saved answers: {said}")
            self._index_said = said
            return False
        except BaseException:
            self._rolled_back(connection)
            raise
        return True

    @classmethod
    def _has_index(cls, connection: sqlite3.Connection) -> bool:
        """Whether the file holds a saved-search index of this version's shape."""
        row = connection.execute("SELECT value FROM meta WHERE name = 'index_format'").fetchone()
        return row is not None and row[0] == saved_index.INDEX_FORMAT and cls._has_table(connection, "saved_mentions")

    @staticmethod
    def _stale(connection: sqlite3.Connection) -> bool:
        """Whether the answers changed without the index being told (saved_index.STALE)."""
        return connection.execute("SELECT 1 FROM meta WHERE name = ?", (saved_index.STALE,)).fetchone() is not None

    @classmethod
    def _in_step(cls, connection: sqlite3.Connection, stale_before: bool) -> None:
        """A change to the answers the index was kept in step with, inside its transaction: the mark the triggers
        made taken off again - unless it was there before the change (an older deadwax's), which only a fresh
        index takes off."""
        if not stale_before:
            connection.execute("DELETE FROM meta WHERE name = ?", (saved_index.STALE,))

    @staticmethod
    def _backfill_left(connection: sqlite3.Connection) -> bool:
        meta = dict(connection.execute("SELECT name, value FROM meta WHERE name IN ('index_at', 'index_to')").fetchall())
        return int(meta.get("index_at", 0) or 0) < int(meta.get("index_to", 0) or 0)

    def _backfill_step(self) -> None:
        """
        One step of reading the answers saved before there was an index into it (2.0.0-player.56): a few answers
        (BACKFILL_ANSWERS, BACKFILL_BYTES), in one transaction with how far it has got - then the next step queued
        BEHIND whatever was asked meanwhile, so a search waits for one step at most. Ends with one log line.
        """
        def step(connection) -> bool:
            if not self._index_ready:
                return False
            meta = dict(connection.execute("SELECT name, value FROM meta WHERE name IN ('index_at', 'index_to')").fetchall())
            at, to = int(meta.get("index_at", 0) or 0), int(meta.get("index_to", 0) or 0)
            if at >= to:
                return False
            rows, size = [], 0
            for row in connection.execute(
                    "SELECT rowid, key, body, fetched_at FROM answers WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?",
                    (at, to, BACKFILL_ANSWERS)):
                rows.append(row)
                size += len(row[2])
                if size >= BACKFILL_BYTES:
                    break
            reached = rows[-1][0] if rows else to
            connection.execute("BEGIN")
            try:
                for rowid, key, body, fetched_at in rows:
                    try:
                        payload = unpack(body)
                    except (zlib.error, ValueError):
                        continue
                    found = self._read(key, payload)
                    saved_index.unindex(connection, [rowid])
                    saved_index.index_answer(connection, rowid, found, fetched_at)
                connection.execute("INSERT OR REPLACE INTO meta (name, value) VALUES ('index_at', ?)", (str(reached),))
                connection.execute("COMMIT")
            except BaseException:
                self._rolled_back(connection)
                raise
            self._backfilled += len(rows)
            if reached >= to:
                logger.info(f"MusicBrainz's saved answers: {self._backfilled} read into the saved-search index - Search "
                            f"finds what they hold under any words now")
                self._backfilled = 0
                return False
            return True

        if self._closing:
            #? the app is stopping: the rest is read in from where it got to, next start
            return
        if self._with_file(False, step, False):
            self._later(self._backfill_step)

    @staticmethod
    def _read(key: str, payload) -> "saved_index.Found":
        """What an answer saved under `key` mentions - nothing, never an error, for a key or answer of a shape the
        index doesn't read (saved_index.read_answer)."""
        try:
            endpoint, params = json.loads(key)
            return saved_index.read_answer(endpoint, params, payload)
        except Exception:
            return saved_index.Found()

    @staticmethod
    def _not_a_database(path: str) -> bool:
        """A file there with something in it, that doesn't begin as every SQLite database does."""
        try:
            with open(path, "rb") as file:
                head = file.read(16)
        except FileNotFoundError:
            return False
        return bool(head) and head != b"SQLite format 3" + bytes(1)

    def _set_aside(self, path: str, why) -> None:
        """
        A musicbrainz-cache.db that can't be read: renamed out of the way, with its journal, and logged
        once. Only ever a file of that name - deadwax's own, which the log may call deletable - and never
        one of any other (NotOurs): a path given by hand naming somebody's file leaves it as it is.
        """
        if os.path.basename(path) != MUSICBRAINZ_CACHE_FILE:
            raise NotOurs(f"{path} can't be read as deadwax's saved answers ({why}), and isn't named "
                          f"{MUSICBRAINZ_CACHE_FILE} - it is left alone")
        aside = f"{path}.unreadable-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        os.replace(path, aside)
        #? a journal left beside a NEW file of the old name would be played back into it
        for suffix in ("-journal", "-wal", "-shm"):
            if os.path.exists(path + suffix):
                os.replace(path + suffix, aside + suffix)
        logger.warning(
            f"MusicBrainz's saved answers at {path} couldn't be read ({why}) - set aside as {aside}, and a new "
            f"file started. Only speed is lost; the old one can be deleted."
        )

    def _with_file(self, create: bool, work, default=None, repair: bool = True):
        connection = self._connection_for(create, repair)
        if connection is None:
            return default
        try:
            return work(connection)
        except sqlite3.OperationalError as e:
            #? locked by something else, a full disk, a read-only file: this answer goes unsaved, no more -
            #? which means never left inside a transaction it began, where everything after it would go
            #? uncommitted (and the file's lock held) until a restart
            logger.warning(f"MusicBrainz's saved answers: {e}")
            if not self._rolled_back(connection):
                self._close()
            return default
        except sqlite3.ProgrammingError as e:
            #? the connection misused (another thread's, or closed) - deadwax's, never the file's: closed, the next use
            #? opening it afresh, and NOTHING set aside (it is a DatabaseError too, which would have been)
            logger.warning(f"MusicBrainz's saved answers: {e}")
            self._close()
            return default
        except sqlite3.DatabaseError as e:
            #? broken while in use: set aside, and the next use starts afresh (only looking: left for it)
            path = self._open_path or self.path()
            self._close()
            if not repair:
                return default
            try:
                self._set_aside(path, e)
            except (OSError, NotOurs) as moved:
                self._failed[path] = time.monotonic()
                self.problem = f"{path} can't be read ({e}), and wasn't set aside ({moved})"
                logger.warning(f"MusicBrainz's answers aren't being saved: {self.problem}")
            return default

    @staticmethod
    def _rolled_back(connection: sqlite3.Connection) -> bool:
        """Out of any transaction left open by a failure - True when it is (or never was in one)."""
        if connection.in_transaction:
            try:
                connection.execute("ROLLBACK")
            except sqlite3.Error:
                pass
        return not connection.in_transaction

    def _get(self, key: str):
        def read(connection):
            row = connection.execute("SELECT body, fetched_at FROM answers WHERE key = ?", (key,)).fetchone()
            if row is None:
                return None
            try:
                return unpack(row[0]), row[1]
            except (zlib.error, ValueError):
                #? one answer that can't be read is dropped, not the file - with what only it mentioned in the
                #? saved-search index (the review's catch: its things were found ever after)
                connection.execute("BEGIN")
                try:
                    stale = self._stale(connection)
                    rowid = connection.execute("SELECT rowid FROM answers WHERE key = ?", (key,)).fetchone()
                    connection.execute("DELETE FROM answers WHERE key = ?", (key,))
                    if self._index_ready and rowid is not None:
                        saved_index.unindex(connection, [rowid[0]])
                        self._in_step(connection, stale)
                    connection.execute("COMMIT")
                except BaseException:
                    self._rolled_back(connection)
                    raise
                return None

        return self._with_file(False, read)

    def _touch(self, key: str, now: float) -> None:
        self._with_file(False, lambda connection: connection.execute(
            "UPDATE answers SET used_at = ? WHERE key = ?", (now, key)))

    def _put(self, key: str, payload, now: float, fetched_at: float) -> None:
        budget = self.max_bytes()
        if budget <= 0:
            return
        body = pack(payload)
        size = len(body) + len(key)
        if size > budget * TRIM_TO:
            #? bigger than the whole budget leaves room for: not kept, rather than emptying the file for it
            return

        #? what the answer mentions, read before the file is touched (2.0.0-player.56)
        found = self._read(key, payload)

        def write(connection):
            #? the answer and its place in the saved-search index together: a refresh replacing an answer takes the
            #? old one's mentions with it, and what only it mentioned
            connection.execute("BEGIN")
            try:
                stale = self._stale(connection)
                if self._index_ready:
                    old = connection.execute("SELECT rowid FROM answers WHERE key = ?", (key,)).fetchone()
                    if old is not None:
                        saved_index.unindex(connection, [old[0]])
                cursor = connection.execute(
                    "INSERT OR REPLACE INTO answers (key, body, size, fetched_at, used_at) VALUES (?, ?, ?, ?, ?)",
                    (key, body, size, fetched_at, now),
                )
                if self._index_ready:
                    saved_index.index_answer(connection, cursor.lastrowid, found, fetched_at)
                    self._in_step(connection, stale)
                connection.execute("COMMIT")
            except BaseException:
                self._rolled_back(connection)
                raise
            self._trim(connection, budget)

        self._with_file(True, write)

    @staticmethod
    def _used_bytes(connection: sqlite3.Connection) -> int:
        """The file's pages in use - its size, less the pages free inside it."""
        pages = connection.execute("PRAGMA page_count").fetchone()[0]
        free = connection.execute("PRAGMA freelist_count").fetchone()[0]
        page = connection.execute("PRAGMA page_size").fetchone()[0]
        return (pages - free) * page

    def _trim(self, connection: sqlite3.Connection, budget: int) -> None:
        """Past the budget, the answers used longest ago go until the file is back under TRIM_TO of it."""
        dropped = False
        for _ in range(8):
            used = self._used_bytes(connection)
            if used <= budget:
                break
            excess = used - int(budget * TRIM_TO)
            doomed, rowids, freed = [], [], 0
            #? (2.0.0-player.56) an answer's place in the saved-search index is freed with it too: each answer's
            #? share counted by its mentions, at what a mention costs in this file on average (the pages beyond the
            #? answers themselves, over every mention) - so the trim drops what it needs to, not every answer it
            #? would take to free the excess from the answers' own bytes alone. Mentions another answer shares free
            #? less; the loop measures again and goes on
            #? (the trim on opening runs before the index is made sure of: an index of this shape is kept in step then too)
            indexed = self._has_index(connection)
            share = 0.0
            if indexed:
                stored = connection.execute("SELECT COALESCE(SUM(size), 0) FROM answers").fetchone()[0]
                mentions = connection.execute("SELECT COUNT(*) FROM saved_mentions").fetchone()[0]
                share = max(0, used - stored) / mentions if mentions else 0.0
            cursor = connection.execute(
                "SELECT key, size, rowid, (SELECT COUNT(*) FROM saved_mentions m WHERE m.answer = answers.rowid) "
                "FROM answers ORDER BY used_at, rowid" if indexed else
                "SELECT key, size, rowid, 0 FROM answers ORDER BY used_at, rowid")
            for key, size, rowid, mentioned in cursor:
                doomed.append((key,))
                rowids.append(rowid)
                freed += size + mentioned * share
                if freed >= excess:
                    break
            cursor.close()
            if not doomed:
                break
            connection.execute("BEGIN")
            try:
                stale = self._stale(connection)
                connection.executemany("DELETE FROM answers WHERE key = ?", doomed)
                #? (2.0.0-player.56) what only they mentioned goes from the saved-search index with them
                if indexed:
                    saved_index.unindex(connection, rowids)
                    self._in_step(connection, stale)
                connection.execute("COMMIT")
            except sqlite3.Error:
                #? a DELETE or COMMIT refused (another process's lock past the timeout, a full disk): out
                #? of the transaction at once - SQLite leaves it open on SQLITE_BUSY - and the trim given
                #? up, so the answer just saved stands and the next write tries the trim again
                self._rolled_back(connection)
                raise
            dropped = True
        if dropped:
            #? the full-text tables' deleted entries merged away, so their pages are freed too - a little work each
            #? time, never a rewrite of the whole index
            if self._has_index(connection):
                connection.execute("INSERT INTO saved_words (saved_words, rank) VALUES ('merge', 64)")
            #? the freed pages back to the disk
            connection.execute("PRAGMA incremental_vacuum").fetchall()

    def _stats(self) -> dict:
        path = self.path()
        answers = size = 0
        #? only a file that is the saved answers is counted - never the database, nor a file typed wrong -
        #? and only looked at: nothing made, nothing set aside (repair=False)
        if self._connection_for(False, repair=False) is not None:
            answers = self._with_file(False, lambda connection: connection.execute(
                "SELECT COUNT(*) FROM answers").fetchone()[0], 0, repair=False)
            for suffix in ("", "-journal", "-wal"):
                try:
                    size += os.path.getsize(path + suffix)
                except OSError:
                    pass
        return {
            "enabled": self.enabled(),
            "path": path,
            "bytes": size,
            "answers": answers,
            "limit_mb": self.max_bytes() >> 20,
            "problem": self.problem,
        }

    def _search(self, words: str) -> dict | None:
        def find(connection):
            if not self._index_ready:
                return None
            return saved_index.search(connection, words)

        return self._with_file(False, find)

    def _clear(self) -> dict:
        def empty(connection):
            connection.execute("BEGIN")
            try:
                connection.execute("DELETE FROM answers")
                #? (2.0.0-player.56) the saved-search index with them - and nothing left to read into it
                if self._index_ready:
                    saved_index.clear_index(connection)
                    connection.execute("INSERT OR REPLACE INTO meta (name, value) VALUES ('index_at', '0')")
                    connection.execute("INSERT OR REPLACE INTO meta (name, value) VALUES ('index_to', '0')")
                    #? nothing left either side: in step, whoever changed the answers before
                    connection.execute("DELETE FROM meta WHERE name = ?", (saved_index.STALE,))
                connection.execute("COMMIT")
            except BaseException:
                self._rolled_back(connection)
                raise
            #? the file shrunk, not just emptied - Clear is also how it is made small again
            connection.execute("VACUUM")

        self._with_file(False, empty)
        return self._stats()


#? The one the app uses, read from the settings at every use - attached to MusicBrainzClient's
#? ResponseCache in the app's lifespan, so nothing outside a running app (a test) ever touches it.
saved_answers = SavedAnswers()
