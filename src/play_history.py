"""
Play history that lasts (2.1.14) - the pure half of /deadwax/me/history (src/routes/play_history.py).

James, 2026-11-13: "I'd like it if the play history was persistent, so you can always look back and see what you
played yesterday." In Up Next, Apple Music's way - scrolled up past the queue's own History it keeps going, one
unbroken list, newest nearest - every song STARTED (skips included), kept by deadwax per person, so plays on the web
and on the iPhone show on both, the phone's offline ones once it reconnects. Kept for ever. notes/play-history.md.

A START is one person beginning to hear one song: the moment both apps already send "now playing" (a listen's first
sound - never a resume, a seek or a wait), dated by the listen's `startedAt` in whole milliseconds by the device's
clock - the very `time` the counted scrobble carries, so the scrobble route marks its start `counted` by the same
key. Each start carries the song as the queue plays it (lib/resume.ts bare(): QueueTrack without its level), so a
row reads, and plays again, after a rescan or a delete with nothing fetched first; and the queue's id and the entry's
key it came from, which the app alone reads - to draw each start exactly once, in the queue's History while its entry
is there, among the older plays above once it isn't.

Kept per person under (user, started_at, song_id): a retry whose answer was lost, an offline batch sent twice, are
the same row - and the second only ORs `counted` in. A start that can't be right is SKIPPED, never the batch refused:
the apps drop a batch answered with a 4xx (DeadwaxCore's PendingPlays.after, the web's historyOutbox), so one bad
clock reading must not lose a week of offline plays - and the route validates each start on its own for the same
reason, a field it doesn't know ignored (a newer app's, sent to an older deadwax). Nothing here talks to anything (tests/test_play_history.py).
"""

import math
import re

#? the plays a page answers by default, and at most - the app asks for the next as it is scrolled near
HISTORY_PAGE = 100
HISTORY_PAGE_MAX = 500
#? the starts one POST takes - the phone sends its offline ones in batches of at most this many
HISTORY_POST_MAX = 500
#? a start dated further than this past the server's clock is skipped (a phone whose clock is wrong) - ms
HISTORY_FUTURE_MS = 10 * 60 * 1000
#? ...and one before this (2020-01-01T00:00:00Z): a clock that reset to 1970
HISTORY_EARLIEST_MS = 1_577_836_800_000
#? a title, an artist or an album longer than this is cut, never refused
HISTORY_TEXT_MAX = 500
#? an id (the song's, its album's, its cover's), a content type or a suffix - routes/navidrome.py's ID_MAX
HISTORY_ID_MAX = 256
#? per person, the plays kept: a guard against a client gone wrong, not a policy - about 18 years at 150 songs a day
#? (~216 MB). The oldest past it go, looked at once a day per person after a write.
HISTORY_KEPT_MAX = 1_000_000
#? how often one person's history is looked at for the guard, in seconds
HISTORY_TRIM_EVERY_S = 24 * 3600
#? ...and sooner, once this many starts have been taken for them since it last looked - so a client gone wrong can't
#? write without limit for a day before the guard sees it
HISTORY_TRIM_AFTER = 10_000
#? the largest `before_at` a page is asked from: SQLite's INTEGER - past it a 422, never an overflow
HISTORY_AT_MAX = 2**63 - 1
#? the queue's id as the apps make it (lib/upNext.ts queueId) - anything else is kept as none
QUEUE_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
#? an entry's key, an int in the queue; sample rates, bit depths and channels - SQLite's INTEGER, kept sane
INT_MAX = 2**31 - 1
#? a song's length, in seconds - a day: no song is longer
DURATION_MAX = 86_400.0

#? the song as the queue holds it (lib/resume.ts bare()), in the page's own names - and its column in play_history
SONG_COLUMNS = {
    "id": "song_id", "title": "title", "artist": "artist", "album": "album", "albumId": "album_id",
    "coverArt": "cover_art", "duration": "duration", "contentType": "content_type", "suffix": "suffix",
    "sampleRate": "sample_rate", "bitDepth": "bit_depth", "channels": "channels",
}
#? every column a row is written with, in order (store.py record_starts)
COLUMNS = ("started_at", *SONG_COLUMNS.values(), "counted", "queue", "entry", "recorded_at")


def _text(value, limit: int = HISTORY_TEXT_MAX) -> str:
    return value[:limit] if isinstance(value, str) else ""


def _optional(value, limit: int = HISTORY_ID_MAX) -> str | None:
    return value[:limit] if isinstance(value, str) and value else None


def _count(value, ceiling: int = INT_MAX) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        return 0
    return min(max(value, 0), ceiling)


def clean_start(start: dict, now_ms: int) -> dict | None:
    """
    One start as it is kept - `COLUMNS`' row, `recorded_at` now - or None when it is skipped: dated more than
    HISTORY_FUTURE_MS past the server's clock or before HISTORY_EARLIEST_MS, or with no song id, or one longer than an
    id is. Text is cut rather than refused, a number clamped, a queue id that isn't one, or an entry that isn't a key,
    kept as none.
    """
    at = start.get("at")
    if isinstance(at, bool) or not isinstance(at, int) or not HISTORY_EARLIEST_MS <= at <= now_ms + HISTORY_FUTURE_MS:
        return None
    song = start.get("song") if isinstance(start.get("song"), dict) else {}
    song_id = song.get("id")
    if not isinstance(song_id, str) or not song_id or len(song_id) > HISTORY_ID_MAX:
        return None
    duration = song.get("duration")
    duration = float(duration) if isinstance(duration, (int, float)) and not isinstance(duration, bool) else 0.0
    queue = start.get("queue")
    entry = start.get("entry")
    return {
        "started_at": at,
        "song_id": song_id,
        "title": _text(song.get("title")),
        "artist": _text(song.get("artist")),
        "album": _text(song.get("album")),
        "album_id": _optional(song.get("albumId")),
        "cover_art": _optional(song.get("coverArt")),
        "duration": min(max(duration, 0.0), DURATION_MAX) if math.isfinite(duration) else 0.0,
        "content_type": _optional(song.get("contentType")),
        "suffix": _optional(song.get("suffix")),
        "sample_rate": _count(song.get("sampleRate")),
        "bit_depth": _count(song.get("bitDepth")),
        "channels": _count(song.get("channels")),
        "counted": 1 if start.get("counted") is True else 0,
        "queue": queue if isinstance(queue, str) and QUEUE_ID.match(queue) else None,
        "entry": entry if isinstance(entry, int) and not isinstance(entry, bool) and 0 <= entry <= INT_MAX else None,
        "recorded_at": now_ms,
    }


def play_of(row: dict) -> dict:
    """A kept row as the apps read it: the start's time, whether it counted, its queue and entry, and the song in the
    queue's own shape - exactly what lib/resume.ts bare() makes, so both apps rebuild a QueueTrack from it."""
    return {
        "at": row["started_at"],
        "counted": bool(row["counted"]),
        "queue": row["queue"],
        "entry": row["entry"],
        "song": {name: row[column] for name, column in SONG_COLUMNS.items()},
    }


def page(rows: list[dict], limit: int, shared: bool) -> dict:
    """GET's answer from up to `limit` + 1 rows read newest first: the first `limit` as plays, and `next` - the last
    one's own time and song, to ask for the page before it with - only when there was one more."""
    shown = rows[:limit]
    more = len(rows) > limit and bool(shown)
    last = shown[-1] if more else None
    return {
        "plays": [play_of(row) for row in shown],
        "next": {"at": last["started_at"], "id": last["song_id"]} if last else None,
        "shared": shared,
    }
