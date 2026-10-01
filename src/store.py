"""
The application's SQLite state - the things worth remembering, and why each is kept.

**Download jobs.** slskd has no idea what it's downloading *for*. It knows "user bob is
sending me 12 files"; it does not know those files are MusicBrainz release f5093c06-... with a
specific tracklist. That link is exactly what's needed later to tag and file the result, and
nothing else in the stack remembers it - so we do.

The expected release is stored denormalized rather than as a bare MBID on purpose: by the
time a slow queue finishes, MusicBrainz may be unreachable (it went down twice while this
was being built), and re-fetching to organize a finished download would be a silly
dependency to introduce.

**Album review state.** Deliberately the *smallest* thing that makes the metadata queue work:
when each album was first seen, whether deadwax filed it or merely found it, and which of
its problems you have said you're happy with. What is wrong with an album is never stored -
metadata_health.py derives that from the scan every time - because a written-down "needs
attention" flag is a flag that goes stale the moment something fixes the album without
clearing it. Storing only the ignores means the queue empties itself.

**The store index** (step 2 of the multi-user plan): every album folder in the library under an
id that survives a rename, so a release already held - or already on its way - is not fetched a
second time. See store_album in the schema and src/store_index.py.

Every table lives in one file and one connection. A failure to open it degrades rather than
raises: downloads still work untracked, and the queue still works without remembering what
you ignored.
"""

import asyncio
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

from src.config import Config
from src.logger import logger
from src.peer_speed import merge_observation


SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    release_mbid  TEXT,
    artist        TEXT,
    album         TEXT,
    year          TEXT,
    username      TEXT NOT NULL,
    directory     TEXT,
    release_json  TEXT NOT NULL,
    files_json    TEXT NOT NULL,
    status        TEXT NOT NULL,
    error         TEXT,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    -- The runners-up from the candidates list the download was picked from (v0.9.12), in the
    -- order it was SHOWN - the user's filters and sort, not the server's ranking - so "try the
    -- next peer" means the next one they would have picked. JSON, [{username, directory, files,
    -- score}]. Existing databases gain these two through JOB_COLUMNS in init().
    alternatives_json  TEXT NOT NULL DEFAULT '[]',
    -- Every (username, directory) this job has been downloaded from, the current one included.
    tried_json         TEXT NOT NULL DEFAULT '[]'
);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);

CREATE TABLE IF NOT EXISTS settings (
    -- Server settings edited from the settings tab.
    --
    -- Only keys the user has actually CHANGED live here. An unedited setting has no row at
    -- all, which is what lets the environment stay the source of truth for everything nobody
    -- has overridden - and lets "revert to the environment value" be a DELETE rather than a
    -- guess at what the value used to be.
    --
    -- A stored value WINS over the environment. The alternative - environment wins - would
    -- mean an edit made here silently vanished on the next restart for anyone configuring
    -- through compose, which is most people. Winning is the honest behaviour; the settings
    -- tab says plainly when a row here is overriding what the environment supplied.
    --
    -- DB_PATH is deliberately not storable: it is where this table lives.
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS album_review (
    -- Keyed on the album's path RELATIVE to LIBRARY_PATH, which is what every other library
    -- endpoint already takes. Not the scan's `key`: that is the release MBID when there is
    -- one, and two folders holding the same release deliberately share it - so ignoring one
    -- would silently ignore the other. A path is the thing you actually pointed at.
    --
    -- The consequence is that renaming a folder loses its row, which is the right outcome:
    -- the only thing that renames folders here is a retag, and a retagged album deserves to
    -- be looked at again rather than inheriting an older verdict. mark_album_reviewed()
    -- carries the row across for exactly that one case.
    album_path      TEXT PRIMARY KEY,
    artist          TEXT,
    album           TEXT,
    -- 'import' = deadwax filed it, so it is new and worth prompting about. 'scan' = it was
    -- already there when we looked.
    source          TEXT NOT NULL DEFAULT 'scan',
    first_seen      TEXT NOT NULL,
    -- set once you have actually looked at the album, which is what stops the new-import
    -- badge counting it forever
    reviewed_at     TEXT,
    -- JSON list of issue codes you have accepted. Per issue rather than per album: agreeing
    -- that a bootleg will never be in MusicBrainz should not also silence the day its cover
    -- art goes missing.
    ignored_issues  TEXT NOT NULL DEFAULT '[]',
    ignored_at      TEXT
);
CREATE INDEX IF NOT EXISTS idx_review_source ON album_review(source, reviewed_at);

CREATE TABLE IF NOT EXISTS peer_speed (
    -- What a peer actually gave us, measured, so the candidate row can show something
    -- better than the peer's own advertised average (see src/peer_speed.py for why that
    -- number is close to meaningless as a prediction).
    --
    -- Keyed on username alone, because that is the only durable identity Soulseek exposes -
    -- there is no stable peer id, and the same person reappears under the same name.
    --
    -- Deliberately NOT a row per transfer. The raw samples would be more flexible, but this
    -- table exists to answer one question on a list that renders per keystroke, and a
    -- running aggregate answers it with a single indexed read. `samples` is kept so the UI
    -- can say how much it is standing on rather than presenting one lucky transfer as
    -- settled fact.
    username        TEXT PRIMARY KEY,
    samples         INTEGER NOT NULL,
    avg_bytes_sec   REAL NOT NULL,
    last_bytes_sec  REAL NOT NULL,
    last_seen       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS library_cache (
    -- The library scan cache, saved so a restart starts from it rather than re-reading every
    -- tag in the library. One row per album folder: exactly what library._album_cache holds in
    -- memory, keyed the same way (the folder's absolute path).
    --
    -- A CACHE, not a record. Every row is validated against the folder's mtime before it is
    -- trusted, as it is in memory, and losing the whole table costs one slow scan and nothing
    -- else. Nothing about what the user decided lives here - that is album_review.
    --
    -- `format` is library.SCAN_FORMAT when the row was written. Other formats are ignored on
    -- load and swept on save: an old row would otherwise be served forever for any folder
    -- nobody has touched since the upgrade, missing whatever field the new version added.
    path    TEXT PRIMARY KEY,
    root    TEXT NOT NULL,
    mtime   REAL NOT NULL,
    format  INTEGER NOT NULL,
    album   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_library_cache_root ON library_cache(root, format);

CREATE TABLE IF NOT EXISTS library_scan (
    -- When each library root was last actually read from disk, so a snapshot drawn from the
    -- cache can say how old it is instead of passing itself off as the current state.
    root          TEXT PRIMARY KEY,
    scanned_at    REAL NOT NULL,
    scan_seconds  REAL NOT NULL,
    album_count   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS store_album (
    -- The store index (step 2 of the multi-user plan, 2.0.0-player.7): every album folder in
    -- the library, with an id that stays put while the album moves about.
    --
    -- Not the scan, and not library_cache. Step 5's per-user ledger keys on this `id`, and
    -- both the path and the release id change when an album is re-filed or a release is
    -- applied - so every writer UPDATES the row it moved rather than dropping it and adding
    -- another, and no row is ever deleted. An album that goes away becomes a tombstone:
    -- `missing` when a scan stops finding it (far more often an unmounted share than a deleted
    -- album), `deleted` when deadwax deleted it, `merged` when a disc folder merged into
    -- `merged_into`. See src/store_index.py for who writes what.
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    -- Config.LIBRARY_PATH as configured, as library_cache keys it
    root               TEXT NOT NULL,
    -- relative to root, exactly as the scan's album["path"]
    path               TEXT NOT NULL,
    release_mbid       TEXT,
    release_group_mbid TEXT,
    artist             TEXT,
    album              TEXT,
    year               TEXT,
    -- the folder's own edition, never the scan's display "Standard"
    edition            TEXT,
    track_count        INTEGER,
    -- JSON list, e.g. ["flac"]
    formats            TEXT NOT NULL DEFAULT '[]',
    -- present | missing | deleted | merged
    state              TEXT NOT NULL DEFAULT 'present',
    merged_into        INTEGER,
    first_seen         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    gone_at            TEXT
);
-- one LIVE row per folder; tombstones may share a path with each other and with the live row
CREATE UNIQUE INDEX IF NOT EXISTS idx_store_album_live ON store_album(root, path) WHERE state = 'present';
CREATE INDEX IF NOT EXISTS idx_store_album_release ON store_album(root, release_mbid);
CREATE INDEX IF NOT EXISTS idx_store_album_group ON store_album(root, release_group_mbid);
-- "is this release already downloading" is asked at every Find and every enqueue
CREATE INDEX IF NOT EXISTS idx_jobs_release ON jobs(release_mbid);
"""

#? Columns added to `jobs` after it first shipped, with the definition an existing database is
#? given - see JobStore.init. Keep in step with SCHEMA.
JOB_COLUMNS = {
    "alternatives_json": "TEXT NOT NULL DEFAULT '[]'",
    "tried_json": "TEXT NOT NULL DEFAULT '[]'",
}

#? how many runners-up a job keeps - enough to get past a run of offline peers, not the whole list
MAX_ALTERNATIVES = 10

#? queued/downloading/complete are phase 2. organizing/organized land with the organizer.
OPEN_STATUSES = ("queued", "downloading")
#? what "clear finished" is allowed to delete - anything still moving is excluded
CLEARABLE_STATUSES = ("complete", "organized", "failed", "cancelled")
#? what "try the next peer" can start again - anything still moving is left to finish
RETRYABLE_STATUSES = ("failed", "cancelled")

#? How long a job in `organizing` still counts as on its way into the library (step 2). A job a
#? stop caught mid-filing is settled when the poller starts (poller.settle_interrupted_filing,
#? 1.1.3), so this bound is the SECOND guard: should that ever miss one, a job stranded there must
#? not block its release for ever. An hour is far longer than any filing takes.
FILING_IN_FLIGHT_SECONDS = 3600

#? ...and a job `complete` with no error, which is the moment between the last file arriving and
#? the poller moving it to `organizing` - the same pass, so seconds. Any older, and it finished
#? while organizing was off and nothing will ever file it: the poller organizes a job only at the
#? moment it completes. Counting that one "on its way" for an hour, once organizing was turned
#? on, blocked the pressing with nothing to cancel (step 2 review).
COMPLETE_IN_FLIGHT_SECONDS = 120

#? what a store_album row can be; everything but `present` is a tombstone
STORE_ALBUM_STATES = ("present", "missing", "deleted", "merged")

#? the columns an album's scan decides - compared by index_reconcile to skip unchanged rows
_INDEX_FIELDS = ("release_mbid", "release_group_mbid", "artist", "album", "year", "edition",
                 "track_count", "formats")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _index_fields(album: dict) -> dict:
    """What store_album holds of a scan album (library.read_album_dir's shape)."""
    return {
        #? '' is how the scan says "untagged"; NULL in the index, so `IS` compares two alike
        "release_mbid": (album.get("release_mbid") or "").strip() or None,
        "release_group_mbid": (album.get("release_group_mbid") or "").strip() or None,
        "artist": album.get("artist") or "",
        "album": album.get("album") or "",
        "year": album.get("year") or "",
        "edition": album.get("edition") or "",
        "track_count": int(album.get("track_count") or 0),
        "formats": json.dumps(sorted(album.get("formats") or [])),
    }


def _index_row(row: sqlite3.Row) -> dict:
    entry = dict(row)
    try:
        entry["formats"] = json.loads(entry.get("formats") or "[]")
    except (TypeError, ValueError):
        entry["formats"] = []
    return entry


def pair_moved(found: list[str], missing: list[tuple[int, str]]) -> dict[str, int]:
    """
    Which newly found folders of ONE release are which `missing` rows of it - {path: row id} -
    for a move made outside deadwax. Only unambiguous pairs: one of each; or else, one of each
    under the same folder name, which is what a renamed ARTIST folder leaves every album with.
    Two discs of a set, or two copies, moved together otherwise swapped ids (step 2 review).
    """
    if len(found) == 1 and len(missing) == 1:
        return {found[0]: missing[0][0]}
    new_by_name: dict[str, list[str]] = {}
    for path in found:
        new_by_name.setdefault(Path(path).name, []).append(path)
    old_by_name: dict[str, list[int]] = {}
    for row_id, path in missing:
        old_by_name.setdefault(Path(path).name, []).append(row_id)
    return {
        paths[0]: old_by_name[name][0]
        for name, paths in new_by_name.items()
        if len(paths) == 1 and len(old_by_name.get(name, ())) == 1
    }


class JobStore:
    def __init__(self, path: str | None = None):
        self.path = path or Config.DB_PATH
        self.available = False

    def init(self) -> None:
        """
        Prepare the database. A failure here is logged loudly but does NOT raise: downloads
        are still perfectly usable without job tracking, and taking the whole app down
        because a volume wasn't mounted would be a worse outcome than degrading.
        """
        try:
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)

            with self._connect() as connection:
                connection.executescript(SCHEMA)
                #? CREATE TABLE IF NOT EXISTS never alters a table that is already there, so a
                #? column added since a database was made has to be added to it by hand
                existing = {row["name"] for row in connection.execute("PRAGMA table_info(jobs)")}
                for column, definition in JOB_COLUMNS.items():
                    if column not in existing:
                        connection.execute(f"ALTER TABLE jobs ADD COLUMN {column} {definition}")

            self.available = True
            logger.info(f"job store ready at {self.path}")

        except Exception as e:
            self.available = False
            logger.error(
                f"could not open the job store at {self.path}, downloads will still work "
                f"but wont be tracked ({e})",
                extra={"frontend": True, "src": "slskd"},
            )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    @staticmethod
    def _row_to_job(row: sqlite3.Row) -> dict:
        job = dict(row)
        if "release_json" in job:  # list_jobs() leaves it out
            job["release"] = json.loads(job.pop("release_json"))
        job["files"] = json.loads(job.pop("files_json"))
        job["alternatives"] = json.loads(job.pop("alternatives_json", None) or "[]")
        job["tried"] = json.loads(job.pop("tried_json", None) or "[]")
        return job

    # sqlite3 is blocking, so every call hops to a worker thread to keep the loop free.

    async def create_job(self, username: str, directory: str, files: list[dict], release: dict,
                         alternatives: list[dict] | None = None) -> int | None:
        if not self.available:
            return None

        def write():
            with self._connect() as connection:
                cursor = connection.execute(
                    """
                    INSERT INTO jobs (release_mbid, artist, album, year, username, directory,
                                      release_json, files_json, status, created_at, updated_at,
                                      alternatives_json, tried_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?, ?)
                    """,
                    (
                        release.get("release_mbid"),
                        release.get("artist"),
                        release.get("album"),
                        release.get("year"),
                        username,
                        directory,
                        json.dumps(release),
                        json.dumps(files),
                        _now(),
                        _now(),
                        json.dumps((alternatives or [])[:MAX_ALTERNATIVES]),
                        json.dumps([{"username": username, "directory": directory}]),
                    ),
                )
                return cursor.lastrowid

        try:
            return await asyncio.to_thread(write)

        except Exception:
            logger.error("failed to record the download job", extra={"frontend": True, "src": "slskd"})
            return None

    async def list_jobs(self, limit: int = 50) -> list[dict]:
        """
        The newest jobs as the downloads panel polls them - twice a second while it's open.

        Without the stored release, and with the runners-up cut down to their usernames - and read
        at all only for a job "try the next peer" can restart, the one place the panel counts
        them (v0.9.24). Fifty jobs used to decode 1.4 MB of JSON a poll, nearly all of it the
        runners-up's file lists; even having SQLite pull out just the usernames cost 3ms, for
        rows that mostly finished long ago. get_job() has the whole row.

        The app's Requests tab (2.0.0-player.12) also wants the release GROUP and the edition a
        row names ("Dummy · 2014 vinyl"). Both are read out of the stored release by SQLite, as
        the usernames are - never decoded here: the edition is the one set by hand, else
        MusicBrainz's disambiguation, a blank being none. A row whose release isn't valid JSON
        gives neither, rather than failing the whole poll.
        """
        if not self.available:
            return []

        def read():
            with self._connect() as connection:
                rows = connection.execute(
                    """
                    SELECT id, release_mbid, artist, album, year, username, directory, files_json,
                           status, error, created_at, updated_at, tried_json,
                           CASE WHEN json_valid(release_json) THEN
                               json_extract(release_json, '$.release_group_mbid')
                           END AS release_group_mbid,
                           CASE WHEN json_valid(release_json) THEN
                               COALESCE(NULLIF(TRIM(json_extract(release_json, '$.edition_label')), ''),
                                        NULLIF(TRIM(json_extract(release_json, '$.disambiguation')), ''))
                           END AS edition,
                           CASE WHEN status IN ({retryable}) THEN
                               (SELECT json_group_array(json_object('username', json_extract(value, '$.username')))
                                  FROM json_each(alternatives_json))
                           ELSE '[]' END AS alternatives_json
                      FROM jobs ORDER BY id DESC LIMIT ?
                    """.format(retryable=", ".join("?" * len(RETRYABLE_STATUSES))),
                    (*RETRYABLE_STATUSES, limit),
                ).fetchall()
                return [self._row_to_job(r) for r in rows]

        try:
            return await asyncio.to_thread(read)

        except Exception:
            logger.error("failed to read download jobs")
            return []

    async def open_jobs(self) -> list[dict]:
        """Jobs the poller still cares about."""
        if not self.available:
            return []

        def read():
            placeholders = ",".join("?" for _ in OPEN_STATUSES)
            with self._connect() as connection:
                rows = connection.execute(
                    f"SELECT * FROM jobs WHERE status IN ({placeholders}) ORDER BY id",
                    OPEN_STATUSES,
                ).fetchall()
                return [self._row_to_job(r) for r in rows]

        try:
            return await asyncio.to_thread(read)

        except Exception:
            logger.error("failed to read open download jobs")
            return []

    async def move_to_peer(self, job_id: int, username: str, directory: str, files: list[dict],
                           tried: list[dict]) -> bool:
        """
        Point a job at another peer's folder and start it again, recording where it has been.

        The same job rather than a new one: it is the same album, it keeps its place in the
        list, and "try the next peer" should read as the download carrying on, not as a second
        download appearing beside a dead one.
        """
        if not self.available:
            return False

        def write():
            with self._connect() as connection:
                connection.execute(
                    """
                    UPDATE jobs SET username = ?, directory = ?, files_json = ?, tried_json = ?,
                                    status = 'queued', error = NULL, updated_at = ?
                    WHERE id = ?
                    """,
                    (username, directory, json.dumps(files), json.dumps(tried), _now(), job_id),
                )

        try:
            await asyncio.to_thread(write)
            return True

        except Exception:
            logger.error(f"failed to move job {job_id} to {username}")
            return False

    async def record_tried(self, job_id: int, tried: list[dict]) -> None:
        """Remember peers a retry asked and was refused by, so the next retry skips them."""
        if not self.available:
            return

        def write():
            with self._connect() as connection:
                connection.execute("UPDATE jobs SET tried_json = ?, updated_at = ? WHERE id = ?",
                                   (json.dumps(tried), _now(), job_id))

        try:
            await asyncio.to_thread(write)
        except Exception:
            logger.error(f"failed to record the peers tried for job {job_id}")

    async def jobs_with_status(self, statuses: tuple[str, ...]) -> list[dict]:
        """Every job in one of `statuses`, oldest first."""
        if not self.available:
            return []

        def read():
            placeholders = ",".join("?" for _ in statuses)
            with self._connect() as connection:
                rows = connection.execute(
                    f"SELECT * FROM jobs WHERE status IN ({placeholders}) ORDER BY id",
                    statuses,
                ).fetchall()
                return [self._row_to_job(r) for r in rows]

        try:
            return await asyncio.to_thread(read)

        except Exception:
            logger.error(f"failed to read jobs in {statuses}")
            return []

    async def update_status(self, job_id: int, status: str, error: str | None = None) -> None:
        if not self.available:
            return

        def write():
            with self._connect() as connection:
                connection.execute(
                    "UPDATE jobs SET status = ?, error = ?, updated_at = ? WHERE id = ?",
                    (status, error, _now(), job_id),
                )

        try:
            await asyncio.to_thread(write)

        except Exception:
            logger.error(f"failed to update job {job_id} to {status}")


    async def delete_jobs(self, statuses: tuple[str, ...]) -> int:
        """Forget finished jobs. Only ever removes rows in the given terminal states."""
        if not self.available:
            return 0

        def write():
            placeholders = ",".join("?" for _ in statuses)
            with self._connect() as connection:
                cursor = connection.execute(
                    f"DELETE FROM jobs WHERE status IN ({placeholders})", statuses
                )
                return cursor.rowcount

        try:
            return await asyncio.to_thread(write)

        except Exception:
            logger.error("failed to clear finished jobs")
            return 0

    async def get_job(self, job_id: int) -> dict | None:
        if not self.available:
            return None

        def read():
            with self._connect() as connection:
                row = connection.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
                return self._row_to_job(row) if row else None

        try:
            return await asyncio.to_thread(read)

        except Exception:
            logger.error(f"failed to read job {job_id}")
            return None

    async def in_flight_job(self, release_mbid: str | None, excluding_job_id: int | None = None,
                            filing: bool = True, now: datetime | None = None,
                            covering: int = 0) -> dict | None:
        """
        The newest job still bringing this release in, or None (step 2).

        In flight is `queued` or `downloading`, or on its way into the library: `organizing`
        updated within FILING_IN_FLIGHT_SECONDS, or `complete` with no error updated within
        COMPLETE_IN_FLIGHT_SECONDS. `filing` says whether a `complete` job is going to be filed
        at all - with organizing off, `complete` is where a download ends. The short bound covers
        the rest: a job that completed while organizing was off is never filed after it is
        turned on. `excluding_job_id` is the job being retried, which is not another download of
        the release but the same one. `covering` is how many files a job must be fetching to count:
        the release's audio tracks, to ask for a job bringing the WHOLE pressing in - one for part
        of it (a lone disc folder, a 9-of-10 folder) is no reason to refuse the rest.
        """
        if not self.available or not release_mbid:
            return None

        statuses = OPEN_STATUSES + ("organizing",) + (("complete",) if filing else ())
        at = now or datetime.now(timezone.utc)

        def recent(stamp: str | None, seconds: int) -> bool:
            try:
                when = datetime.fromisoformat(stamp or "")
            except ValueError:
                #? a timestamp nobody can read can't prove the job is still moving
                return False
            if when.tzinfo is None:
                when = when.replace(tzinfo=timezone.utc)
            return when >= at - timedelta(seconds=seconds)

        def read():
            placeholders = ",".join("?" for _ in statuses)
            with self._connect() as connection:
                rows = connection.execute(
                    f"SELECT * FROM jobs WHERE release_mbid = ? AND status IN ({placeholders}) "
                    f"AND id != ? ORDER BY id DESC",
                    (release_mbid, *statuses, excluding_job_id if excluding_job_id is not None else -1),
                ).fetchall()

            for row in rows:
                job = self._row_to_job(row)
                if len(job["files"]) < covering:
                    continue
                if row["status"] in OPEN_STATUSES:
                    return job
                #? filing that stopped with an error has stopped - see _organize_if_enabled
                bound = FILING_IN_FLIGHT_SECONDS if row["status"] == "organizing" else COMPLETE_IN_FLIGHT_SECONDS
                if not row["error"] and recent(row["updated_at"], bound):
                    return job
            return None

        try:
            return await asyncio.to_thread(read)

        except Exception as e:
            logger.error(f"failed to look for a download of {release_mbid} in flight ({e})")
            return None

    # ---------------------------------------------------------------- album review
    #
    # Everything below backs the metadata queue. None of it records what is *wrong* with an
    # album - metadata_health.py works that out from the scan on every request - so a store
    # that can't be opened costs you the memory of what you ignored and nothing else.

    # ===== settings overrides =================================================

    def stored_settings(self) -> dict[str, str]:
        """
        Every stored override, as a plain dict.

        SYNCHRONOUS on purpose, unlike everything else on this class. It runs once during
        startup, before the event loop exists, so that Config can be reconciled before
        anything reads it. Making it async would mean the first request could arrive with
        the environment's values still in place.

        Returns {} on any failure - an unreadable settings table must degrade to "use the
        environment", never to a crash on boot.
        """
        if not self.available:
            return {}

        try:
            with self._connect() as connection:
                rows = connection.execute("SELECT key, value FROM settings").fetchall()

            return {row["key"]: row["value"] for row in rows}

        except Exception as e:
            logger.error(f"could not read stored settings, using the environment only ({e})")
            return {}

    async def set_setting(self, key: str, value: str) -> bool:
        """Store an override. Overwrites any existing one for that key."""
        if not self.available:
            return False

        def write():
            with self._connect() as connection:
                connection.execute(
                    "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value, "
                    "updated_at = excluded.updated_at",
                    (key, value, _now()),
                )
            return True

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not store the setting {key} ({e})", extra={"frontend": True})
            return False

    async def clear_setting(self, key: str) -> bool:
        """
        Drop an override, so the environment's value applies again.

        Deleting the row rather than writing the environment's value back is what keeps
        "revert" honest: if the compose file changes later, a reverted setting follows it,
        where a copied-back value would silently pin the old one forever.
        """
        if not self.available:
            return False

        def write():
            with self._connect() as connection:
                connection.execute("DELETE FROM settings WHERE key = ?", (key,))
            return True

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not clear the setting {key} ({e})", extra={"frontend": True})
            return False

    async def record_albums_seen(self, albums: list[dict], source: str = "scan") -> int:
        """
        Note that these albums exist, without disturbing anything already recorded.

        `INSERT OR IGNORE` is doing real work here rather than being defensive: `first_seen`
        has to mean the first time, and `source` has to keep saying 'import' for an album
        deadwax filed even though every later scan sees it too. An album's row is written
        once and then only ever updated by an explicit action of the user's.

        `albums` are dicts carrying at least `path`; `artist` and `album` are stored purely so
        the badge can name what's waiting without a scan.
        """
        if not self.available or not albums:
            return 0

        rows = [
            (album["path"], album.get("artist") or "", album.get("album") or "", source, _now())
            for album in albums
            if album.get("path")
        ]

        def write():
            with self._connect() as connection:
                cursor = connection.executemany(
                    """
                    INSERT OR IGNORE INTO album_review
                        (album_path, artist, album, source, first_seen)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    rows,
                )
                return cursor.rowcount

        try:
            return await asyncio.to_thread(write)

        except Exception as e:
            logger.error(f"failed to record albums for review: {e}")
            return 0

    async def album_reviews(self) -> dict[str, dict]:
        """
        Everything remembered about every album, keyed on its relative path.

        Returned whole rather than queried per album because the caller is about to decorate
        an entire library scan with it - a few hundred rows is nothing, and one read beats one
        per album by a wide margin.
        """
        if not self.available:
            return {}

        def read():
            with self._connect() as connection:
                rows = connection.execute("SELECT * FROM album_review").fetchall()

            reviews = {}
            for row in rows:
                entry = dict(row)
                try:
                    entry["ignored_issues"] = json.loads(entry["ignored_issues"] or "[]")
                except (TypeError, ValueError):
                    #? a hand-edited or truncated value must not take the whole library view
                    #? down; an unreadable ignore list simply means nothing is ignored
                    entry["ignored_issues"] = []
                reviews[entry["album_path"]] = entry

            return reviews

        try:
            return await asyncio.to_thread(read)

        except Exception as e:
            logger.error(f"failed to read album review state: {e}")
            return {}

    async def ignore_album_issues(self, album_path: str, issues: list[str]) -> bool:
        """
        Accept these issues on this album, so it drops out of the queue.

        The list is stored rather than a bare "ignored" flag, so an album that later develops
        a *different* problem comes back on its own. Also marks the album reviewed - you have
        by definition looked at it.
        """
        if not self.available or not album_path:
            return False

        payload = json.dumps(sorted(set(issues or [])))

        def write():
            with self._connect() as connection:
                cursor = connection.execute(
                    """
                    INSERT INTO album_review
                        (album_path, source, first_seen, reviewed_at, ignored_issues, ignored_at)
                    VALUES (?, 'scan', ?, ?, ?, ?)
                    ON CONFLICT(album_path) DO UPDATE SET
                        ignored_issues = excluded.ignored_issues,
                        ignored_at     = excluded.ignored_at,
                        reviewed_at    = excluded.reviewed_at
                    """,
                    (album_path, _now(), _now(), payload, _now()),
                )
                return cursor.rowcount > 0

        try:
            return await asyncio.to_thread(write)

        except Exception as e:
            logger.error(f"failed to ignore issues on {album_path}: {e}")
            return False

    async def unignore_album(self, album_path: str) -> bool:
        """Take an album off the ignore list, putting it back in the queue if it has issues."""
        if not self.available or not album_path:
            return False

        def write():
            with self._connect() as connection:
                cursor = connection.execute(
                    "UPDATE album_review SET ignored_issues = '[]', ignored_at = NULL "
                    "WHERE album_path = ?",
                    (album_path,),
                )
                return cursor.rowcount > 0

        try:
            return await asyncio.to_thread(write)

        except Exception as e:
            logger.error(f"failed to un-ignore {album_path}: {e}")
            return False

    async def mark_album_reviewed(self, album_path: str, new_path: str | None = None,
                                  merged: bool = False) -> bool:
        """
        Record that this album has been looked at, following it if the folder just moved.

        Called after a retag applies and when you step past an album in the queue. `new_path`
        is the retag case: the row is keyed on the path, so leaving it behind would orphan the
        history of an album that is still very much there. The destination row is cleared
        first because the primary key would otherwise reject the move - and if something *is*
        already recorded there, it describes a folder that no longer exists.

        Except after a MERGE (`merged`): a disc folder moved into its release's folder, which is
        still there and is the album now (v0.9.13). Its row - first seen, filed by deadwax or
        found, the issues you'd accepted - is that album's history, so it stays and is marked
        reviewed, and the merged-away folder's row goes with the folder (v1.1.4). Until then
        the merge replaced it with the disc folder's. With no row there, the moved row is the
        best history there is, and it moves as for a rename.
        """
        if not self.available or not album_path:
            return False

        target = new_path or album_path

        def write():
            with self._connect() as connection:
                if target != album_path and merged:
                    kept = connection.execute(
                        "UPDATE album_review SET reviewed_at = ? WHERE album_path = ?",
                        (_now(), target),
                    )
                    if kept.rowcount:
                        connection.execute(
                            "DELETE FROM album_review WHERE album_path = ?", (album_path,)
                        )
                        return True

                elif target != album_path:
                    connection.execute("DELETE FROM album_review WHERE album_path = ?", (target,))

                #? Written as move-then-insert rather than as one upsert because the two cases
                #? want different keys: an existing row must keep its first_seen and follow the
                #? album to `target`, while an album with no row at all should be recorded at
                #? where it is NOW, not at the path it has just stopped living at.
                moved = connection.execute(
                    "UPDATE album_review SET reviewed_at = ?, album_path = ? WHERE album_path = ?",
                    (_now(), target, album_path),
                )

                if moved.rowcount:
                    return True

                connection.execute(
                    "INSERT INTO album_review (album_path, source, first_seen, reviewed_at) "
                    "VALUES (?, 'scan', ?, ?)",
                    (target, _now(), _now()),
                )
                return True

        try:
            return await asyncio.to_thread(write)

        except Exception as e:
            logger.error(f"failed to mark {album_path} reviewed: {e}")
            return False

    async def forget_missing_albums(self, known_paths: set[str]) -> int:
        """
        Drop review rows for albums that are no longer in the library.

        A row is keyed on the album's path, so anything that moves a folder without going
        through the retag endpoint - a rename by hand, a delete from another tool - orphans it.
        An orphaned import row is worse than clutter: the tab badge counts it, and since the
        album isn't in the scan there is no row to put a chip on and no queue entry to step
        through. The interface ends up reporting an album that wants attention while being
        unable to name it or clear it, which is exactly the state this method exists to prevent.

        Called only after a scan that actually found albums. A library that reads as empty is
        far more often an unmounted volume than a deleted collection, and wiping every ignore
        the moment a mount goes missing would be a rotten trade for tidiness.
        """
        if not self.available or not known_paths:
            return 0

        def write():
            with self._connect() as connection:
                rows = connection.execute("SELECT album_path FROM album_review").fetchall()
                missing = [(r["album_path"],) for r in rows if r["album_path"] not in known_paths]

                if not missing:
                    return 0

                connection.executemany("DELETE FROM album_review WHERE album_path = ?", missing)
                return len(missing)

        try:
            removed = await asyncio.to_thread(write)
            if removed:
                logger.info(f"forgot {removed} review record(s) for albums no longer in the library")
            return removed

        except Exception as e:
            logger.error(f"failed to forget missing albums: {e}")
            return 0

    async def forget_album_review(self, album_path: str) -> bool:
        """
        Drop one album's review row, for an album deadwax has just deleted (v1.1.5).

        forget_missing_albums() would get to it, but only on the next full scan - and until then
        an `import` row for it went on being counted by the new-imports badge while naming an
        album that no longer exists, the exact state that method is there to end. The delete is
        the moment it is known to be gone, so it goes then. Never raises: the album is deleted
        either way, and failing to tidy its row is not a reason to report the delete as failed.
        """
        if not self.available or not album_path:
            return False

        def write():
            with self._connect() as connection:
                cursor = connection.execute(
                    "DELETE FROM album_review WHERE album_path = ?", (album_path,)
                )
                return cursor.rowcount > 0

        try:
            return await asyncio.to_thread(write)

        except Exception as e:
            logger.error(f"failed to forget the review record for {album_path}: {e}")
            return False

    async def new_import_summary(self, limit: int = 8) -> dict:
        """
        Albums deadwax filed that you haven't looked at yet.

        The one thing in the queue that can be answered without scanning the library, which is
        the whole reason the import source is recorded at all: the library is deliberately not
        read until you open its tab (a first scan reads tags off every file), so a badge that
        needed a scan would either be absent when it matters or would tax every page load.
        This is a single indexed count.
        """
        if not self.available:
            return {"count": 0, "albums": [], "tracking_enabled": False}

        def read():
            with self._connect() as connection:
                rows = connection.execute(
                    """
                    SELECT album_path, artist, album, first_seen FROM album_review
                    WHERE source = 'import' AND reviewed_at IS NULL AND ignored_at IS NULL
                    ORDER BY first_seen DESC
                    """
                ).fetchall()

            return {
                "count": len(rows),
                #? capped: this names what is waiting, it isn't a second album list
                "albums": [dict(r) for r in rows[:limit]],
                "tracking_enabled": True,
            }

        try:
            return await asyncio.to_thread(read)

        except Exception as e:
            logger.error(f"failed to count new imports: {e}")
            return {"count": 0, "albums": [], "tracking_enabled": False}

    async def record_peer_speed(self, username: str, rate: float) -> bool:
        """
        Fold one measured transfer rate into a peer's running figure.

        Never raises. This is bookkeeping hung off a download that has already finished, so a
        failure here must not colour the outcome of the job itself - the album arrived either
        way, and the poller has nothing useful to do about a write that did not land.
        """
        if not self.available or not username or rate <= 0:
            return False

        def write():
            with self._connect() as connection:
                row = connection.execute(
                    "SELECT samples, avg_bytes_sec FROM peer_speed WHERE username = ?",
                    (username,),
                ).fetchone()

                average, samples = merge_observation(
                    row["avg_bytes_sec"] if row else None,
                    row["samples"] if row else 0,
                    rate,
                )

                connection.execute(
                    """
                    INSERT INTO peer_speed
                        (username, samples, avg_bytes_sec, last_bytes_sec, last_seen)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(username) DO UPDATE SET
                        samples = excluded.samples,
                        avg_bytes_sec = excluded.avg_bytes_sec,
                        last_bytes_sec = excluded.last_bytes_sec,
                        last_seen = excluded.last_seen
                    """,
                    (username, samples, average, rate, _now()),
                )

            return True

        try:
            return await asyncio.to_thread(write)

        except Exception as e:
            logger.error(f"failed to record the speed measured from {username}: {e}")
            return False

    async def peer_speeds(self, usernames: list[str]) -> dict[str, dict]:
        """
        Measured rates for the peers named, keyed by username. Absent peers are simply absent.

        Takes the list rather than returning the whole table: a candidate list is at most a
        few dozen peers while the table grows for the life of the install, and the caller
        wants a lookup either way.

        Returns {} on any failure. A candidate row without this chip is the ordinary case -
        most peers have never been downloaded from - so a degraded read looks exactly like a
        peer nobody has met, which is the correct thing for it to look like.
        """
        if not self.available or not usernames:
            return {}

        unique = sorted(set(u for u in usernames if u))
        if not unique:
            return {}

        def read():
            placeholders = ",".join("?" * len(unique))

            with self._connect() as connection:
                rows = connection.execute(
                    f"""
                    SELECT username, samples, avg_bytes_sec, last_bytes_sec, last_seen
                    FROM peer_speed WHERE username IN ({placeholders})
                    """,
                    unique,
                ).fetchall()

            return {r["username"]: dict(r) for r in rows}

        try:
            return await asyncio.to_thread(read)

        except Exception as e:
            logger.error(f"failed to read measured peer speeds: {e}")
            return {}

    # ===== the saved library scan =============================================
    #
    # A cache, persisted. Everything here degrades to "scan from nothing", which is exactly
    # what every restart did before this existed - so no failure below is worth more than a log.

    async def load_library_cache(self, root: str, fmt: int) -> list[tuple[str, float, dict]]:
        """
        Every saved scan entry for this library root, in the current format.

        Parsed in the worker thread along with the read: a large library's JSON is tens of
        milliseconds to decode, which is too long to hold the event loop for. A row that won't
        parse is skipped rather than failing the lot.
        """
        if not self.available or not root:
            return []

        def read():
            with self._connect() as connection:
                rows = connection.execute(
                    "SELECT path, mtime, album FROM library_cache WHERE root = ? AND format = ?",
                    (root, fmt),
                ).fetchall()

            entries = []
            for row in rows:
                try:
                    entries.append((row["path"], float(row["mtime"]), json.loads(row["album"])))
                except (ValueError, TypeError):
                    continue
            return entries

        try:
            return await asyncio.to_thread(read)
        except Exception as e:
            logger.error(f"could not read the saved library scan, it will be rebuilt ({e})")
            return []

    async def save_library_cache(
        self,
        root: str,
        upserts: list[tuple[str, float, dict]],
        removals: list[str],
        fmt: int,
    ) -> bool:
        """Write changed scan entries and delete removed ones, in one transaction."""
        if not self.available or not root:
            return False

        def write():
            with self._connect() as connection:
                if removals:
                    connection.executemany(
                        "DELETE FROM library_cache WHERE path = ?", [(p,) for p in removals]
                    )
                if upserts:
                    connection.executemany(
                        "INSERT INTO library_cache (path, root, mtime, format, album) "
                        "VALUES (?, ?, ?, ?, ?) "
                        "ON CONFLICT(path) DO UPDATE SET root = excluded.root, "
                        "mtime = excluded.mtime, format = excluded.format, album = excluded.album",
                        [(path, root, mtime, fmt, json.dumps(album))
                         for path, mtime, album in upserts],
                    )
                #? rows an older version wrote can never be loaded again - see the schema note
                connection.execute("DELETE FROM library_cache WHERE format != ?", (fmt,))
            return True

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not save the library scan ({e})")
            return False

    async def record_library_scan(
        self, root: str, scanned_at: float, scan_seconds: float, album_count: int,
    ) -> bool:
        """Note that this root was just read from disk."""
        if not self.available or not root:
            return False

        def write():
            with self._connect() as connection:
                connection.execute(
                    "INSERT INTO library_scan (root, scanned_at, scan_seconds, album_count) "
                    "VALUES (?, ?, ?, ?) "
                    "ON CONFLICT(root) DO UPDATE SET scanned_at = excluded.scanned_at, "
                    "scan_seconds = excluded.scan_seconds, album_count = excluded.album_count",
                    (root, scanned_at, scan_seconds, album_count),
                )
            return True

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not record the library scan time ({e})")
            return False

    async def library_scan_info(self, root: str) -> dict | None:
        """When this root was last read from disk, or None if it never has been."""
        if not self.available or not root:
            return None

        def read():
            with self._connect() as connection:
                row = connection.execute(
                    "SELECT scanned_at, scan_seconds, album_count FROM library_scan WHERE root = ?",
                    (root,),
                ).fetchone()
            return dict(row) if row else None

        try:
            return await asyncio.to_thread(read)
        except Exception as e:
            logger.error(f"could not read the library scan time ({e})")
            return None

    # ===== the store index ====================================================
    #
    # store_album - see the schema for why it has stable ids and tombstones, and
    # src/store_index.py for the writers that keep it in step and the checks that read it.
    # Everything degrades to "nothing indexed": the index says whether a download can be
    # skipped, and a broken one must never stop a download - it only stops the skipping.

    @staticmethod
    def _index_write(connection: sqlite3.Connection, root: str, path: str, fields: dict, now: str,
                     row_id: int | None) -> int:
        """Bring `row_id` back to life at `path` with these fields - or, with no row, insert one."""
        values = [fields[name] for name in _INDEX_FIELDS]
        if row_id is not None:
            assignments = ", ".join(f"{name} = ?" for name in _INDEX_FIELDS)
            connection.execute(
                f"UPDATE store_album SET path = ?, {assignments}, state = 'present', merged_into = NULL, "
                f"gone_at = NULL, updated_at = ? WHERE id = ?",
                (path, *values, now, row_id),
            )
            return row_id
        columns = ", ".join(_INDEX_FIELDS)
        marks = ", ".join("?" for _ in _INDEX_FIELDS)
        cursor = connection.execute(
            f"INSERT INTO store_album (root, path, {columns}, state, first_seen, updated_at) "
            f"VALUES (?, ?, {marks}, 'present', ?, ?)",
            (root, path, *values, now, now),
        )
        return cursor.lastrowid

    @staticmethod
    def _missing_here(connection: sqlite3.Connection, root: str, path: str, release_mbid: str | None):
        """
        The `missing` row at this very path of this release that went LAST - the same folder,
        back. By when it went, not by id: the highest id is only the row made last, and an older
        dead copy's tombstone at the same path would otherwise take the album's id.
        """
        return connection.execute(
            "SELECT id FROM store_album WHERE root = ? AND path = ? AND state = 'missing' "
            "AND release_mbid IS ? ORDER BY gone_at DESC, id DESC LIMIT 1",
            (root, path, release_mbid),
        ).fetchone()

    @classmethod
    def _index_upsert(cls, connection: sqlite3.Connection, root: str, path: str, fields: dict, now: str) -> int:
        """
        The live row for this folder, updated - else its own `missing` row brought back (same
        path, same release) - else a new row.

        Only ever by the SAME path. A folder written by deadwax itself - filed, re-tagged,
        re-read after a rename - is that folder, and taking some other folder's row because it
        holds the same release is how a fresh download used to walk off with an unmounted
        share's id. Moves outside deadwax are paired by index_reconcile, which sees both ends.
        And only `missing`: a row deadwax deleted, or merged into another, is never brought
        back - a deleted album filed again at the same path is a new album with a new row.
        """
        live = connection.execute(
            "SELECT id FROM store_album WHERE root = ? AND path = ? AND state = 'present'", (root, path),
        ).fetchone()
        if live is not None:
            assignments = ", ".join(f"{name} = ?" for name in _INDEX_FIELDS)
            connection.execute(f"UPDATE store_album SET {assignments}, updated_at = ? WHERE id = ?",
                               (*[fields[name] for name in _INDEX_FIELDS], now, live["id"]))
            return live["id"]

        back = cls._missing_here(connection, root, path, fields["release_mbid"])
        return cls._index_write(connection, root, path, fields, now, back["id"] if back else None)

    async def index_upsert(self, root: str, album: dict) -> int | None:
        """Record one album folder (library.read_album_dir's shape). Returns its row id."""
        if not self.available or not root or not album.get("path"):
            return None

        def write():
            with self._connect() as connection:
                return self._index_upsert(connection, root, album["path"], _index_fields(album), _now())

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not index {album.get('path')} ({e})")
            return None

    async def index_reconcile(self, root: str, albums: list[dict], still_there=None,
                              since: float | None = None, not_pairable=None) -> tuple[int, int]:
        """
        Bring the index in line with a full scan: every album recorded, and every live row the
        scan didn't find marked `missing`. Returns (rows written, rows marked missing).

        Nothing is marked missing after a scan that found NO albums - an empty library is far
        more often an unmounted volume than a deleted collection, the rule forget_missing_albums
        keeps too.

        **A scan is a picture of the past.** The walk can take seconds on a NAS, and deadwax's
        own writers - filing, apply, refile, delete - don't wait for it, so by the time this runs
        a folder it listed may have been deleted or renamed, and one it didn't may have been
        filed. So `still_there(path)` (whether audio sits in that folder NOW) is asked about every
        row the scan didn't find before it is marked missing, AND about every folder the scan
        found that has no live row before it is recorded - otherwise a stale scan brings back a
        row deadwax just deleted, or leaves a live row at the old name of one it just renamed.
        `since` (when the scan began, epoch seconds) keeps it from rewriting a live row a writer
        updated after that - an apply re-tagging in place while the walk went by. Every look at
        the disk happens before the first write, so no write lock is held while it looks.

        **Moves outside deadwax** (a file manager, Picard) show as a path gone and a path found.
        A found folder first takes its own `missing` row (same path, same release). The rest are
        paired with `missing` rows of the same release only where that is unambiguous - one of
        each, or else one of each under the same folder name, which a renamed artist folder
        keeps - so the discs of a set, or two copies of a release, moved together can't swap ids.
        The rows THIS scan just marked missing are tried first, since a move is a path gone and a
        path found in the same scan; older tombstones only for what is still unpaired - otherwise
        one stale tombstone of the release made every later rename ambiguous. A folder in
        `not_pairable(path)` - one the poller is filing right now - is never paired: it is a new
        folder, whatever tombstones its release has. Anything still unpaired is a new row.

        One read and only the writes that change something: this runs after every real scan of
        the library tab, and a thousand unchanged albums should cost a comparison, not a
        thousand UPDATEs.
        """
        if not self.available or not root:
            return 0, 0

        scanned = {album["path"]: _index_fields(album) for album in albums or [] if album.get("path")}
        #? whole seconds, as updated_at is written: a row stamped in the scan's first second
        #? counts as newer, which at worst leaves one refresh to the next scan
        began = datetime.fromtimestamp(int(since), timezone.utc) if since else None

        def newer(stamp: str | None) -> bool:
            if began is None:
                return False
            try:
                when = datetime.fromisoformat(stamp or "")
            except (TypeError, ValueError):
                return False
            return (when if when.tzinfo else when.replace(tzinfo=timezone.utc)) >= began

        def there(path: str) -> bool:
            """Whether the folder holds audio now - taken on the scan's word when nobody can look."""
            return still_there is None or bool(still_there(path))

        def write():
            now = _now()
            with self._connect() as connection:
                live = {
                    row["path"]: row for row in connection.execute(
                        "SELECT * FROM store_album WHERE root = ? AND state = 'present'", (root,))
                }
                gone = [path for path in live if path not in scanned] if scanned else []
                if still_there is not None:
                    gone = [path for path in gone if not still_there(path)]
                found = [path for path in scanned if path not in live and there(path)]

                #? The looks at the disk are done; from here this holds the write lock, so no writer
                #? can slip a live row in under it. One that did so DURING the looks is caught here:
                #? a found folder a writer has indexed meanwhile is the writer's, left alone - taking
                #? it too broke the partial unique index and rolled the whole reconcile back.
                connection.execute("BEGIN IMMEDIATE")
                if found:
                    marks = ",".join("?" for _ in found)
                    taken = {row["path"] for row in connection.execute(
                        f"SELECT path FROM store_album WHERE root = ? AND state = 'present' AND path IN ({marks})",
                        (root, *found))}
                    found = [path for path in found if path not in taken]

                connection.executemany(
                    "UPDATE store_album SET state = 'missing', gone_at = ?, updated_at = ? "
                    "WHERE root = ? AND path = ? AND state = 'present'",
                    [(now, now, root, path) for path in gone],
                )

                written = 0
                for path, row in live.items():
                    fields = scanned.get(path)
                    if fields is None or all(row[name] == fields[name] for name in _INDEX_FIELDS):
                        continue
                    if newer(row["updated_at"]):
                        continue
                    assignments = ", ".join(f"{name} = ?" for name in _INDEX_FIELDS)
                    connection.execute(f"UPDATE store_album SET {assignments}, updated_at = ? WHERE id = ?",
                                       (*[fields[name] for name in _INDEX_FIELDS], now, row["id"]))
                    written += 1

                #? the same folder back where it was
                unpaired: list[str] = []
                for path in found:
                    back = self._missing_here(connection, root, path, scanned[path]["release_mbid"])
                    if back is not None:
                        self._index_write(connection, root, path, scanned[path], now, back["id"])
                        written += 1
                    else:
                        unpaired.append(path)

                #? moved outside deadwax: paired by release, only where that is unambiguous - against
                #? what this scan just marked missing first, then older tombstones
                just_gone = {live[path]["id"] for path in gone}
                by_release: dict[str, list[str]] = {}
                for path in unpaired:
                    if scanned[path]["release_mbid"] and not (not_pairable and not_pairable(path)):
                        by_release.setdefault(scanned[path]["release_mbid"], []).append(path)
                pairs: dict[str, int] = {}
                for release_mbid, paths in by_release.items():
                    missing = [(row["id"], row["path"]) for row in connection.execute(
                        "SELECT id, path FROM store_album WHERE root = ? AND release_mbid = ? "
                        "AND state = 'missing' ORDER BY id", (root, release_mbid))]
                    recent = [entry for entry in missing if entry[0] in just_gone]
                    older = [entry for entry in missing if entry[0] not in just_gone]
                    first = pair_moved(paths, recent)
                    pairs.update(first)
                    pairs.update(pair_moved([path for path in paths if path not in first], older))

                for path in unpaired:
                    self._index_write(connection, root, path, scanned[path], now, pairs.get(path))
                    written += 1
                return written, len(gone)

        try:
            written, gone = await asyncio.to_thread(write)
            if written or gone:
                logger.debug(f"store index: {written} album(s) recorded, {gone} marked missing")
            return written, gone
        except Exception as e:
            logger.error(f"could not bring the store index up to date ({e})")
            return 0, 0

    @staticmethod
    def _moving_row(connection: sqlite3.Connection, root: str, path: str):
        """
        The row a move or merge from `path` is about: its live one - or, when a Find or a scan
        marked it missing in the moment between the folder leaving and this call (the folder
        really was gone for that moment), the `missing` row there that went LAST (by gone_at, as
        _missing_here chooses - not the highest id, which may be an older album's tombstone).
        """
        return connection.execute(
            "SELECT id, state FROM store_album WHERE root = ? AND path = ? AND state IN ('present', 'missing') "
            "ORDER BY state = 'present' DESC, gone_at DESC, id DESC LIMIT 1",
            (root, path)).fetchone()

    async def index_move(self, root: str, old_path: str, new_path: str,
                         release_mbid: str | None = None) -> int | None:
        """
        The row at `old_path` lives at `new_path` now - the same row, so the same id - live again
        if a Find or scan had just marked it missing. Nothing when there is no row there at all;
        the re-index that follows adds one.

        Should the destination already have a live row of its own (something indexed the new
        folder first), that one is the newcomer: it is marked merged into the row that moved,
        which is the one with a history. Except when only a TOMBSTONE is left at the old path and
        the destination's live row carries the moving album's release (`release_mbid`; any, when
        the caller doesn't know it): then a scan landed between the move on disk and this call and
        has already paired the album there, and the tombstone may well be some older album's -
        merging the live row into it would hand the album's id to that one. Nothing is done.
        """
        if not self.available or not root or old_path == new_path:
            return None

        def write():
            now = _now()
            with self._connect() as connection:
                moving = self._moving_row(connection, root, old_path)
                if moving is None:
                    return None
                if moving["state"] != "present":
                    there = connection.execute(
                        "SELECT id, release_mbid FROM store_album WHERE root = ? AND path = ? "
                        "AND state = 'present'", (root, new_path)).fetchone()
                    if there is not None and (release_mbid is None or there["release_mbid"] == release_mbid):
                        return there["id"]
                connection.execute(
                    "UPDATE store_album SET state = 'merged', merged_into = ?, gone_at = ?, updated_at = ? "
                    "WHERE root = ? AND path = ? AND state = 'present' AND id != ?",
                    (moving["id"], now, now, root, new_path, moving["id"]))
                connection.execute(
                    "UPDATE store_album SET path = ?, state = 'present', gone_at = NULL, updated_at = ? "
                    "WHERE id = ?", (new_path, now, moving["id"]))
                return moving["id"]

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not move {old_path} in the store index ({e})")
            return None

    async def index_merge(self, root: str, source_path: str, target_path: str) -> int | None:
        """
        The folder at `source_path` was merged into the one at `target_path` - a disc folder into
        its release's (retag._merge_into). Its row becomes a `merged` tombstone pointing at the
        target's (found as index_move finds it). With no row for the target, it is a move instead.
        """
        if not self.available or not root:
            return None

        def write():
            now = _now()
            with self._connect() as connection:
                source = self._moving_row(connection, root, source_path)
                if source is None:
                    return None
                target = connection.execute(
                    "SELECT id FROM store_album WHERE root = ? AND path = ? AND state = 'present'",
                    (root, target_path)).fetchone()
                if target is None:
                    connection.execute(
                        "UPDATE store_album SET path = ?, state = 'present', gone_at = NULL, updated_at = ? "
                        "WHERE id = ?", (target_path, now, source["id"]))
                    return source["id"]
                connection.execute(
                    "UPDATE store_album SET state = 'merged', merged_into = ?, gone_at = ?, updated_at = ? "
                    "WHERE id = ?", (target["id"], now, now, source["id"]))
                return target["id"]

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not merge {source_path} in the store index ({e})")
            return None

    async def index_gone(self, root: str, path: str, state: str) -> bool:
        """The live row at `path` becomes a tombstone: `missing`, `deleted` or `merged`."""
        if not self.available or not root or state not in STORE_ALBUM_STATES or state == "present":
            return False

        def write():
            now = _now()
            with self._connect() as connection:
                cursor = connection.execute(
                    "UPDATE store_album SET state = ?, gone_at = ?, updated_at = ? "
                    "WHERE root = ? AND path = ? AND state = 'present'",
                    (state, now, now, root, path))
                return cursor.rowcount > 0

        try:
            return await asyncio.to_thread(write)
        except Exception as e:
            logger.error(f"could not mark {path} {state} in the store index ({e})")
            return False

    async def _index_read(self, sql: str, params: tuple, what: str) -> list[dict]:
        if not self.available:
            return []

        def read():
            with self._connect() as connection:
                return [_index_row(row) for row in connection.execute(sql, params).fetchall()]

        try:
            return await asyncio.to_thread(read)
        except Exception as e:
            logger.error(f"could not read {what} from the store index ({e})")
            return []

    async def index_present(self, root: str, release_mbid: str | None) -> list[dict]:
        """Every live folder indexed as this release - two or more for a set stored one per disc."""
        if not root or not release_mbid:
            return []
        return await self._index_read(
            "SELECT * FROM store_album WHERE root = ? AND release_mbid = ? AND state = 'present' ORDER BY path",
            (root, release_mbid), "a release")

    async def index_pressings(self, root: str, release_group_mbid: str | None,
                              excluding_release: str | None) -> list[dict]:
        """Every live folder of this album (release group) that is some OTHER pressing."""
        if not root or not release_group_mbid:
            return []
        return await self._index_read(
            "SELECT * FROM store_album WHERE root = ? AND release_group_mbid = ? AND state = 'present' "
            "AND COALESCE(release_mbid, '') != ? ORDER BY path",
            (root, release_group_mbid, excluding_release or ""), "an album's pressings")

    async def index_count(self, root: str) -> int:
        """How many rows the index holds for this root, tombstones included."""
        if not self.available or not root:
            return 0

        def read():
            with self._connect() as connection:
                return connection.execute("SELECT COUNT(*) FROM store_album WHERE root = ?", (root,)).fetchone()[0]

        try:
            return await asyncio.to_thread(read)
        except Exception as e:
            logger.error(f"could not count the store index ({e})")
            return 0


#? slskd reports a stopped transfer as "Completed, <substate>". "Succeeded" is the only good
#? one; every other substate is TERMINAL - a transfer sitting in one will never move again.
#?
#? Treating an unrecognised substate as "still going" is not a harmless omission. A rejected
#? download sat in the queue reporting that it hadn't started yet, indefinitely: it was neither
#? done nor failed, so no transition fired, and because slskd WAS reporting the transfer the
#? unmatched-transfer grace period never applied either. It could only ever be cleared by hand.
#?
#? So: if slskd grows another substate, it belongs in here. An unknown one is a stuck job.
TRANSFER_FAILURE_REASONS = {
    "Rejected": "the peer refused to send it",
    "TimedOut": "the peer stopped responding",
    "Errored": "the transfer errored",
    "Cancelled": "the transfer was cancelled",
}


def transfer_failure(state: str | None) -> str:
    """
    Why this transfer stopped for good, or '' if it hasn't stopped badly.

    Substring matching, like the rest of the state handling here, because slskd composes the
    string ("Completed, Rejected") and has changed the composition between versions.
    """
    text = state or ""
    return next((reason for key, reason in TRANSFER_FAILURE_REASONS.items() if key in text), "")


def summarize_transfers(job: dict, transfers_by_user: dict[str, list[dict]]) -> dict:
    """
    Work out how a job is doing from slskd's live transfer list.

    Progress is derived on read rather than stored, because it changes constantly and
    writing every tick to sqlite would be pure churn for data that slskd already owns.
    Matching is on (username, filename) since that's the only identity slskd exposes.
    """
    wanted = {f["filename"] for f in job["files"]}
    transfers = [t for t in transfers_by_user.get(job["username"], []) if t.get("filename") in wanted]

    if not transfers:
        return {
            "progress": 0.0,
            "state": None,
            "speed": 0,
            "bytes_transferred": 0,
            "files_done": 0,
            "files_total": len(wanted),
            #? present even here so every caller can read them without a .get() default, and
            #? so "no transfers" can never be mistaken for "no failures worth reporting"
            "files_failed": 0,
            "failure_reason": None,
            "matched": False,
        }

    done = sum(1 for t in transfers if "Completed, Succeeded" in (t.get("state") or ""))
    reasons = [reason for reason in (transfer_failure(t.get("state")) for t in transfers) if reason]

    return {
        # average over everything we asked for, not just what slskd currently reports, so a
        # job whose files haven't been picked up yet doesn't read as further along than it is
        "progress": sum(t.get("percentComplete", 0) or 0 for t in transfers) / max(len(wanted), 1),
        "state": transfers[0].get("state"),
        # slskd's averageSpeed is cumulative (bytes moved / elapsed), so it only ever climbs
        # and never reflects what's happening right now. Report the raw byte count instead and
        # let the caller derive a real rate from the change between two samples.
        "speed": sum(t.get("averageSpeed", 0) or 0 for t in transfers),
        "bytes_transferred": sum(t.get("bytesTransferred", 0) or 0 for t in transfers),
        "files_done": done,
        "files_total": len(wanted),
        "files_failed": len(reasons),
        #? The first one. Files in a folder fail together and for the same cause - a peer that
        #? refuses one refuses all of them - so listing every reason would just repeat itself.
        "failure_reason": reasons[0] if reasons else None,
        "matched": True,
    }


def settled_transfer_ids(job: dict, transfers_by_user: dict[str, list[dict]]) -> tuple[list[str], int]:
    """
    A job's transfers slskd still lists, split by whether it can let go of them yet.

    Returns (ids that have SETTLED - any "Completed, ..." state - and so can be removed from
    slskd's list, how many are still listed but not settled). slskd will only remove a transfer
    once it has completed, and a cancelled one gets there a moment AFTER the cancel returns -
    see tidy_cancelled_transfers in poller.py for why that moment is the whole problem.
    """
    wanted = {f["filename"] for f in job.get("files") or []}
    settled: list[str] = []
    unsettled = 0

    for transfer in transfers_by_user.get(job.get("username", ""), []):
        if transfer.get("filename") not in wanted or not transfer.get("id"):
            continue
        if "Completed" in str(transfer.get("state") or ""):
            settled.append(transfer["id"])
        else:
            unsettled += 1

    return settled, unsettled


def index_transfers_by_user(downloads: list[dict]) -> dict[str, list[dict]]:
    """Flatten slskd's user -> directories -> files shape into user -> files."""
    by_user: dict[str, list[dict]] = {}

    for entry in downloads or []:
        username = entry.get("username", "")
        files = []

        for directory in entry.get("directories", []) or []:
            files.extend(directory.get("files", []) or [])

        by_user.setdefault(username, []).extend(files)

    return by_user
