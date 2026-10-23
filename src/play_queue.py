"""
Resume what was playing (2.0.0-player.64) - the pure half of the player's /deadwax/navidrome/queue routes.

James, 2026-10-22: "every time I open the app, whatever was playing is gone." Asked where it should be kept, he
chose "follows you everywhere": in Navidrome, as the signed-in person's play queue, so a desktop picks up where the
phone stopped. Two places are written together and read together (notes/app.md "Resume what was playing"):

  - NAVIDROME'S PLAY QUEUE, as the asker - the song ids, the current index and the position in milliseconds - the
    interchange any Subsonic client sees, and the authority on what was played last (`changedBy`, `changed`).
    Navidrome keeps ONE queue per user (model/playqueue.go, persistence/playqueue_repository.go,
    server/subsonic/bookmarks.go, read at 0.64.2). deadwax saves it BY INDEX (savePlayQueueByIndex): the plain
    savePlayQueue finds `current` by the FIRST occurrence of its id, and deadwax's queue holds the same song more
    than once by design (Repeat One's copies, Repeat All's rounds). On a read Navidrome drops songs no longer in
    its database but answers its stored index unchanged, so the page aligns rather than trusts (lib/resume.ts).
    (A file deleted from disk is NOT one of those until it is purged: the scanner marks it missing and keeps it -
    Scanner.PurgeMissing defaults to "never" - and getPlayQueueByIndex still answers it, since loadTracks asks
    mediaFileRepository.GetAll, which has no `missing` filter. It comes back, and the player skips it when its turn
    to play fails.)
  - DEADWAX'S OWN RECORD beside it (store.py's play_queue): the same ids and index, the position in seconds, the
    page's account of Up Next (an opaque, versioned snapshot only the page reads), the device that saved it, and
    two counters - `rev`, bumped by every save, and `ids_rev`, the rev of the last save that sent the ids, which a
    position save is made against.

Nothing here talks to anything: the window kept of a long list, the answer's shape from Navidrome's, a client
name and the parameters of a save - tested without a server (tests/test_play_queue.py).
"""

import json
import re
import unicodedata

#? the most entries kept, and of them the most before the song playing - the history Previous walks
RESUME_MAX = 2000
RESUME_BEFORE = 50
#? the page's snapshot of Up Next, in characters; one bigger is left out and the queue comes back a plain list
SNAPSHOT_MAX = 262_144
#? a position, in seconds - a day: no song is longer
POSITION_MAX = 86_400.0
#? Navidrome's `changedBy` as answered: control characters out, at most this long
CHANGED_BY_MAX = 64
#? the device a save came from: lib/resume.ts makes 16 of these characters; and its label, from the user agent
DEVICE_PATTERN = r"^[A-Za-z0-9_-]{8,64}$"
LABEL_PATTERN = r"^[A-Za-z0-9 ]{1,40}$"

#? a position save against ids another device or app has replaced since this page's full save: it saves in full
QUEUE_CHANGED = "The queue changed on another device or in another app"
#? a position save naming a place past the ids deadwax kept
NOT_IN_QUEUE = "That song isn't in the queue deadwax kept"
#? a save's body deadwax can't read - a field missing or out of bounds (a validator's own words go instead)
QUEUE_FORM = "deadwax couldn't read that queue - the player sent something it doesn't take"
#? the database isn't there to keep the record in
NO_RECORD = "deadwax can't keep your queue just now - its database isn't available"


def window(count: int, index: int) -> tuple[int, int]:
    """The entries [start, end) kept of a list of `count` playing `index`: at most RESUME_BEFORE before it and
    RESUME_MAX in all - the same window the page's toSave() keeps (lib/resume.ts)."""
    if count <= 0:
        return 0, 0
    at = min(max(index, 0), count - 1)
    start = max(0, at - RESUME_BEFORE)
    return start, min(count, start + RESUME_MAX)


def cleaned_name(text) -> str:
    """A client's name as Navidrome recorded it (the `c` of the call that saved), for the page's notice: control
    characters out, at most CHANGED_BY_MAX - '' for anything that isn't text."""
    if not isinstance(text, str):
        return ""
    kept = "".join(ch for ch in text if unicodedata.category(ch)[0] != "C")
    return kept.strip()[:CHANGED_BY_MAX]


def snapshot_problem(text: str | None) -> str | None:
    """Why a snapshot is refused (a 422), or None: it must be JSON, an object, of version 1. What is inside is the
    page's own account, read back only by the page (lib/resume.ts fromSnapshot) - deadwax never acts on it."""
    if text is None:
        return None
    if len(text) > SNAPSHOT_MAX:
        return f"The queue's account is over {SNAPSHOT_MAX} characters"
    try:
        made = json.loads(text)
    except ValueError:
        return "The queue's account isn't JSON"
    if not isinstance(made, dict):
        return "The queue's account isn't an object"
    if made.get("v") != 1 or isinstance(made.get("v"), bool):
        return "The queue's account isn't one deadwax knows (v 1)"
    return None


def save_params(ids: list[str], index: int, position: float) -> dict:
    """savePlayQueueByIndex's parameters: every id in order (a list is its key repeated), the current INDEX, and
    the position in milliseconds as Subsonic counts it. Nothing else the page sent."""
    return {"id": list(ids), "currentIndex": index, "position": round(position * 1000)}


def _integer(value) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def kept_view(record: dict) -> dict:
    """deadwax's record as the page reads it."""
    return {key: record[key] for key in ("rev", "ids_rev", "ids", "index", "position", "snapshot", "device", "label")}


def answer(body: dict, record: dict | None, shared: bool, fields: tuple[str, ...], client_name: str) -> dict:
    """
    GET /queue's answer from Navidrome's playQueueByIndex (`body`) and the asker's record:

      - `tracks`: Navidrome's entries in its order, each trimmed to `fields` (the shuffle's, which the page's
        shuffledTrack reads) - a list over RESUME_MAX as the window around its current index, the index moved with
        it; `index` its currentIndex as Navidrome said it (None when it said none), which after a deletion can name
        the wrong song or none at all: the page aligns it.
      - `position` in seconds; `changed_by` cleaned; `shared` with logins off (one queue for everyone).
      - `kept`: the record, only when deadwax saved last (`changed_by` is deadwax's client name) and there is one -
        the page still believes it only when the ids agree (lib/resume.ts resumed()).
    """
    entries = [entry for entry in (body.get("entry") or []) if isinstance(entry, dict) and isinstance(entry.get("id"), str)]
    index = _integer(body.get("currentIndex")) if entries else None
    if len(entries) > RESUME_MAX:
        start, end = window(len(entries), index if index is not None else 0)
        entries = entries[start:end]
        if index is not None:
            index -= start
    position = body.get("position")
    seconds = position / 1000 if isinstance(position, (int, float)) and not isinstance(position, bool) and position > 0 else 0
    changed_by = cleaned_name(body.get("changedBy"))
    kept = kept_view(record) if record is not None and changed_by == client_name and entries else None
    return {
        "tracks": [{name: entry[name] for name in fields if name in entry} for entry in entries],
        "index": index,
        "position": seconds,
        "changed_by": changed_by,
        "shared": shared,
        "kept": kept,
    }


#? what a label may hold, as LABEL_PATTERN says - for the tests' own checks
LABEL = re.compile(LABEL_PATTERN)
DEVICE = re.compile(DEVICE_PATTERN)
